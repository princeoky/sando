-- Loads and saves player progress with DataStoreService and mirrors it onto
-- player attributes (for the HUD) and leaderstats (for the player list).
-- If DataStores are unavailable (e.g. Studio without API access), progress
-- is kept in memory for the session and never written.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)

local DataService = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[sando] DataStore unavailable, progress will not save:", result)
	end
end

type Profile = {
	data: { [string]: any },
	canSave: boolean,
}

local profiles: { [Player]: Profile } = {}

local function defaultData()
	return {
		gold = 0,
		wins = 0,
		losses = 0,
		duels = 0,
		elo = Config.StartingElo,
		owned = { [Weapons.Default] = true },
		equipped = Weapons.Default,
	}
end

local function reconcile(data)
	local defaults = defaultData()
	for key, value in defaults do
		if data[key] == nil then
			data[key] = value
		end
	end
	data.owned[Weapons.Default] = true
	if not Weapons.List[data.equipped] or not data.owned[data.equipped] then
		data.equipped = Weapons.Default
	end
	return data
end

local function key(player: Player)
	return "player_" .. player.UserId
end

-- Errors that will never succeed on retry (unpublished place, or Studio
-- without API access). After one of these we stop using DataStores.
local function isPermanentError(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "403", 1, true) ~= nil
		or string.find(lower, "studio", 1, true) ~= nil
		or string.find(lower, "publish", 1, true) ~= nil
		or string.find(lower, "api services", 1, true) ~= nil
end

local function withRetries(fn: () -> any): (boolean, any)
	local ok, result
	for attempt = 1, 3 do
		ok, result = pcall(fn)
		if ok then
			return ok, result
		end
		if isPermanentError(tostring(result)) then
			warn("[sando] DataStores unavailable, progress will not save:", result)
			store = nil
			return ok, result
		end
		task.wait(attempt)
	end
	return ok, result
end

local function publish(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local data = profile.data
	player:SetAttribute("Gold", data.gold)
	player:SetAttribute("Wins", data.wins)
	player:SetAttribute("Duels", data.duels)
	player:SetAttribute("Elo", data.elo)
	player:SetAttribute("Equipped", data.equipped)
	local ownedList = {}
	for id in data.owned do
		table.insert(ownedList, id)
	end
	player:SetAttribute("Owned", table.concat(ownedList, ","))

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		(leaderstats :: any).Gold.Value = data.gold;
		(leaderstats :: any).Wins.Value = data.wins;
		(leaderstats :: any).Elo.Value = data.elo
	end
end

local function makeLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, name in { "Wins", "Elo", "Gold" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = leaderstats
	end
	leaderstats.Parent = player
end

function DataService.load(player: Player)
	makeLeaderstats(player)

	local data = nil
	local canSave = false
	if store then
		local ok, result = withRetries(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok then
			data = result
			canSave = true
		else
			warn("[sando] Failed to load data for", player.Name, result)
		end
	end

	profiles[player] = {
		data = reconcile(data or defaultData()),
		canSave = canSave,
	}
	publish(player)
end

function DataService.save(player: Player)
	local profile = profiles[player]
	if not profile or not profile.canSave or not store then
		return
	end
	local ok, err = withRetries(function()
		return (store :: DataStore):SetAsync(key(player), profile.data, { player.UserId })
	end)
	if not ok then
		warn("[sando] Failed to save data for", player.Name, err)
	end
end

function DataService.release(player: Player)
	DataService.save(player)
	profiles[player] = nil
end

function DataService.get(player: Player)
	local profile = profiles[player]
	return profile and profile.data
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService.waitForLoad(player: Player, timeout: number)
	local started = os.clock()
	while not profiles[player] and player.Parent and os.clock() - started < timeout do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.addGold(player: Player, amount: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.gold = math.max(0, data.gold + amount)
	publish(player)
end

function DataService.recordMatch(player: Player, won: boolean, goldReward: number, eloDelta: number?)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.duels += 1
	if won then
		data.wins += 1
	else
		data.losses += 1
	end
	data.gold += goldReward
	if eloDelta then
		data.elo = math.max(0, data.elo + eloDelta)
	end
	publish(player)
end

-- Returns (ok, message)
function DataService.buyOrEquip(player: Player, weaponId: string): (boolean, string)
	local data = DataService.get(player)
	local weapon = Weapons.List[weaponId]
	if not data or not weapon then
		return false, "Unknown weapon"
	end

	if data.owned[weaponId] then
		if data.equipped == weaponId then
			return false, weapon.displayName .. " is already equipped"
		end
		data.equipped = weaponId
		publish(player)
		return true, "Equipped " .. weapon.displayName
	end

	if data.gold < weapon.price then
		return false, string.format("You need %d more gold for the %s", weapon.price - data.gold, weapon.displayName)
	end
	data.gold -= weapon.price
	data.owned[weaponId] = true
	data.equipped = weaponId
	publish(player)
	return true, "Bought and equipped " .. weapon.displayName .. "!"
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for _, player in Players:GetPlayers() do
				task.spawn(DataService.save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				DataService.save(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
