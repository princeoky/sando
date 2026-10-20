-- Matchmaking queues for each mode. Players join from the lobby pads or the
-- HUD; when enough players are waiting and an arena is free, a match starts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local QueueRequest = Remotes.QueueRequest :: RemoteEvent
local QueueState = Remotes.QueueState :: RemoteEvent
local Notify = Remotes.Notify :: RemoteEvent

local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

local QueueService = {}

local queues: { [string]: { Player } } = {}
for _, modeId in Config.ModeOrder do
	queues[modeId] = {}
end

local pads = {}

local function counts()
	local result = {}
	for modeId, queue in queues do
		result[modeId] = #queue
	end
	return result
end

local function publish()
	local current = counts()
	QueueState:FireAllClients(current)
	for modeId, pad in pads do
		local mode = Config.Modes[modeId]
		if mode.practice then
			pad.status.Text = "Starts instantly"
		else
			pad.status.Text = string.format("%d / %d waiting", current[modeId] or 0, mode.teamSize * 2)
		end
	end
end

local function removeFromAll(player: Player)
	for _, queue in queues do
		local index = table.find(queue, player)
		if index then
			table.remove(queue, index)
		end
	end
	player:SetAttribute("QueuedMode", nil)
end

function QueueService.leave(player: Player)
	if player:GetAttribute("QueuedMode") then
		removeFromAll(player)
		Notify:FireClient(player, "Left the queue")
		publish()
	end
end

function QueueService.tryMatch()
	for _, modeId in Config.ModeOrder do
		local mode = Config.Modes[modeId]
		local queue = queues[modeId]
		local needed = mode.teamSize * 2

		while not mode.practice and #queue >= needed and MatchService.hasFreeArena() do
			local picked = {}
			for _ = 1, needed do
				table.insert(picked, table.remove(queue, 1))
			end
			-- Ranked: pair similar ratings by sorting the picked group
			if mode.ranked then
				table.sort(picked, function(a, b)
					local da, db = DataService.get(a), DataService.get(b)
					return (da and da.elo or 0) > (db and db.elo or 0)
				end)
			end
			local teams = { {}, {} }
			for i, player in picked do
				player:SetAttribute("QueuedMode", nil)
				-- Snake draft keeps 2v2 teams balanced: 1,2,2,1
				local team = if (i % 4 == 1 or i % 4 == 0) then 1 else 2
				table.insert(teams[team], player)
			end
			MatchService.start(modeId, teams)
		end
	end
	publish()
end

function QueueService.join(player: Player, modeId: string)
	local mode = Config.Modes[modeId]
	if not mode then
		return
	end
	if MatchService.isInMatch(player) then
		Notify:FireClient(player, "You're already in a match")
		return
	end
	local data = DataService.get(player)
	if not data then
		Notify:FireClient(player, "Still loading your data, try again in a moment")
		return
	end
	if data.duels < mode.unlockDuels then
		Notify:FireClient(player, string.format("%s unlocks after %d duels (%d to go)", mode.displayName, mode.unlockDuels, mode.unlockDuels - data.duels))
		return
	end
	if mode.practice then
		removeFromAll(player)
		if MatchService.startPractice(player) then
			Notify:FireClient(player, "Starting practice against a bot")
		else
			Notify:FireClient(player, "All arenas are busy, try again in a moment", "bad")
		end
		publish()
		return
	end
	if player:GetAttribute("QueuedMode") == modeId then
		return
	end

	removeFromAll(player)
	table.insert(queues[modeId], player)
	player:SetAttribute("QueuedMode", modeId)
	Notify:FireClient(player, "Queued for " .. mode.displayName)
	QueueService.tryMatch()
end

function QueueService.init(lobbyPads)
	pads = lobbyPads

	for modeId, pad in pads do
		pad.prompt.Triggered:Connect(function(player)
			if player:GetAttribute("QueuedMode") == modeId then
				QueueService.leave(player)
			else
				QueueService.join(player, modeId)
			end
		end)
	end

	QueueRequest.OnServerEvent:Connect(function(player, action: unknown, modeId: unknown)
		if action == "Join" and type(modeId) == "string" then
			QueueService.join(player, modeId)
		elseif action == "Leave" then
			QueueService.leave(player)
		elseif action == "Sync" then
			QueueState:FireClient(player, counts())
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		removeFromAll(player)
		publish()
	end)

	publish()
end

return QueueService
