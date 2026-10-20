-- sando server entry point: builds the map, starts every service and handles
-- player spawning (CharacterAutoLoads is off so matches control respawns).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local WeaponFactory = require(Shared.WeaponFactory)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Notify = Remotes.Notify :: RemoteEvent

local MapBuilder = require(script.MapBuilder)
local DataService = require(script.DataService)
local CombatService = require(script.CombatService)
local MatchService = require(script.MatchService)
local QueueService = require(script.QueueService)

Players.CharacterAutoLoads = false

-- If the map ever fails to build, still give players something to stand on
-- and report the error, instead of everyone falling forever.
local built, map = pcall(MapBuilder.build)
if not built then
	warn("[sando] Map failed to build:", map)
	local floor = Instance.new("SpawnLocation")
	floor.Anchored = true
	floor.Size = Vector3.new(100, 1, 100)
	floor.Duration = 0
	floor.Parent = workspace
	map = { lobby = { pads = {}, shopPrompts = {} }, arenas = {} }
end

DataService.start()
CombatService.start()
MatchService.init(map.arenas)
CombatService.setResolvers(MatchService.getTargets, MatchService.canFight)
QueueService.init(map.lobby.pads)
MatchService.Ended:Connect(QueueService.tryMatch)

-- Armory pedestals
for _, prompt in map.lobby.shopPrompts do
	prompt.Triggered:Connect(function(player)
		local weaponId = prompt:GetAttribute("WeaponId")
		local ok, message = DataService.buyOrEquip(player, weaponId)
		Notify:FireClient(player, message, if ok then "good" else "bad")
		if ok and not MatchService.isInMatch(player) and player.Character then
			WeaponFactory.attach(player.Character, weaponId)
		end
	end)
end

local function waitForBody(player: Player, character: Model)
	if not player:HasAppearanceLoaded() then
		local loaded = false
		local connection = player.CharacterAppearanceLoaded:Connect(function()
			loaded = true
		end)
		local started = os.clock()
		while not loaded and os.clock() - started < 4 and character.Parent do
			task.wait()
		end
		connection:Disconnect()
	end
	if not character:FindFirstChild("RightHand") and not character:FindFirstChild("Right Arm") then
		character:WaitForChild("RightHand", 3)
	end
end

local function onCharacter(player: Player, character: Model)
	CombatService.reset(player)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.MaxHealth = Config.MaxHealth
	humanoid.Health = Config.MaxHealth
	humanoid.WalkSpeed = Config.WalkSpeed

	-- No natural regen: health only comes back between rounds
	local regen = character:FindFirstChild("Health")
	if regen and regen:IsA("Script") then
		regen:Destroy()
	end

	humanoid.Died:Connect(function()
		if MatchService.isInMatch(player) then
			return -- the match respawns players between rounds
		end
		task.wait(2)
		if player.Parent and player.Character == character and not MatchService.isInMatch(player) then
			MatchService.spawnPlayer(player)
		end
	end)

	waitForBody(player, character)
	local data = DataService.waitForLoad(player, 10)
	if character.Parent and player.Character == character then
		WeaponFactory.attach(character, data and data.equipped or Weapons.Default)
	end
end

local setUp: { [Player]: boolean } = {}

local function onPlayerAdded(player: Player)
	if setUp[player] then
		return
	end
	setUp[player] = true
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	-- Spawn right away; saved data loads alongside and the weapon is attached
	-- once it arrives.
	task.spawn(DataService.load, player)
	if player.Parent and not player.Character then
		MatchService.spawnPlayer(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	setUp[player] = nil
	CombatService.remove(player)
	DataService.release(player)
end)
