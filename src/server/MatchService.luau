-- Runs matches: grabs a free arena, spawns teams, loops countdown -> fight ->
-- round end until a team wins enough rounds, then pays out and returns
-- everyone to the lobby.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchState = Remotes.MatchState :: RemoteEvent
local CombatFeedback = Remotes.CombatFeedback :: RemoteEvent

local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)

local MatchService = {}

type Arena = {
	index: number,
	name: string,
	origin: Vector3,
	spawns: { { CFrame } },
	busy: boolean,
}

type Match = {
	mode: any,
	arena: Arena,
	teams: { { Player } },
	scores: { number },
	round: number,
	phase: string,
	alive: { [Player]: boolean },
	endsAt: number,
	connections: { RBXScriptConnection },
}

local arenas: { Arena } = {}
local playerMatch: { [Player]: Match } = {}

local endedEvent = Instance.new("BindableEvent")
MatchService.Ended = endedEvent.Event

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function teamOf(match: Match, player: Player): number?
	for team, members in match.teams do
		if table.find(members, player) then
			return team
		end
	end
	return nil
end

local function forEachPlayer(match: Match, fn: (Player, number, number) -> ())
	for team, members in match.teams do
		for slot, player in members do
			fn(player, team, slot)
		end
	end
end

local function aliveCount(match: Match, team: number): number
	local count = 0
	for _, player in match.teams[team] do
		if match.alive[player] then
			count += 1
		end
	end
	return count
end

local function teamHealth(match: Match, team: number): number
	local total = 0
	for _, player in match.teams[team] do
		local humanoid = match.alive[player] and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			total += humanoid.Health / humanoid.MaxHealth
		end
	end
	return total
end

local function sendState(match: Match, extra: { [string]: any }?, personalize: ((Player, { [string]: any }) -> ())?)
	local payload = {
		state = match.phase,
		mode = match.mode.id,
		modeName = match.mode.displayName,
		arena = match.arena.name,
		round = match.round,
		scores = table.clone(match.scores),
		roundsToWin = match.mode.roundsToWin,
		teams = { table.clone(match.teams[1]), table.clone(match.teams[2]) },
		endsAt = match.endsAt,
	}
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	forEachPlayer(match, function(player, team)
		local personal = table.clone(payload)
		personal.myTeam = team
		if personalize then
			personalize(player, personal)
		end
		MatchState:FireClient(player, personal)
	end)
end

local function setFrozen(match: Match, frozen: boolean)
	forEachPlayer(match, function(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			(root :: BasePart).Anchored = frozen
		end
	end)
end

local function clearConnections(match: Match)
	for _, connection in match.connections do
		connection:Disconnect()
	end
	table.clear(match.connections)
end

local function spawnRound(match: Match)
	clearConnections(match)
	table.clear(match.alive)

	local pending = 0
	forEachPlayer(match, function(player, team, slot)
		pending += 1
		task.spawn(function()
			local ok, err = pcall(function()
				player:LoadCharacterAsync()
			end)
			local character = player.Character
			local root = character and character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
			local humanoid = character and character:WaitForChild("Humanoid", 5) :: Humanoid?
			if ok and character and root and humanoid and player.Parent then
				local spawnSlot = match.arena.spawns[team][slot] or match.arena.spawns[team][1]
				character:PivotTo(spawnSlot)
				root.Anchored = true
				match.alive[player] = true
				table.insert(match.connections, humanoid.Died:Connect(function()
					match.alive[player] = nil
					CombatFeedback:FireAllClients("KO", character)
				end))
			elseif not ok then
				warn("[sando] Failed to spawn", player.Name, err)
			end
			pending -= 1
		end)
	end)

	local started = os.clock()
	while pending > 0 and os.clock() - started < 10 do
		task.wait()
	end
end

local function forfeitWinner(match: Match): number?
	local empty1 = #match.teams[1] == 0
	local empty2 = #match.teams[2] == 0
	if empty1 and empty2 then
		return 0
	elseif empty1 then
		return 2
	elseif empty2 then
		return 1
	end
	return nil
end

local function eloChanges(match: Match, winner: number): { [Player]: number }
	local changes = {}
	if not match.mode.ranked then
		return changes
	end
	local function averageElo(team: number): number
		local sum, n = 0, 0
		for _, player in match.teams[team] do
			local data = DataService.get(player)
			if data then
				sum += data.elo
				n += 1
			end
		end
		return if n > 0 then sum / n else Config.StartingElo
	end
	local ratings = { averageElo(1), averageElo(2) }
	for team = 1, 2 do
		local other = 3 - team
		local expected = 1 / (1 + 10 ^ ((ratings[other] - ratings[team]) / 400))
		local score = if team == winner then 1 else 0
		local delta = math.floor(Config.EloK * (score - expected) + 0.5)
		for _, player in match.teams[team] do
			changes[player] = delta
		end
	end
	return changes
end

local function finishMatch(match: Match, winner: number)
	match.phase = "Ended"
	match.endsAt = serverNow() + Config.MatchEndTime

	local elo = eloChanges(match, winner)
	local rewards = {}
	forEachPlayer(match, function(player, team)
		local won = team == winner
		local gold = if won then match.mode.winGold else match.mode.lossGold
		DataService.recordMatch(player, won, gold, elo[player])
		rewards[player] = { gold = gold, elo = elo[player] }
	end)

	sendState(match, { winner = winner }, function(player, payload)
		local reward = rewards[player]
		payload.won = payload.myTeam == winner
		payload.gold = reward and reward.gold or 0
		payload.eloDelta = reward and reward.elo
	end)
	task.wait(Config.MatchEndTime)

	clearConnections(match)
	forEachPlayer(match, function(player)
		playerMatch[player] = nil
		player:SetAttribute("InMatch", false)
		CombatService.reset(player, true)
		MatchState:FireClient(player, { state = "Lobby" })
		task.spawn(function()
			if player.Parent then
				pcall(function()
					player:LoadCharacterAsync()
				end)
			end
		end)
	end)
	match.arena.busy = false
	endedEvent:Fire()
end

local function runMatch(match: Match)
	local winner: number? = nil

	while true do
		winner = forfeitWinner(match)
		if winner then
			break
		end

		match.round += 1
		match.phase = "Starting"
		spawnRound(match)

		winner = forfeitWinner(match)
		if winner then
			break
		end

		match.phase = "Countdown"
		match.endsAt = serverNow() + Config.CountdownTime
		sendState(match)
		task.wait(Config.CountdownTime)

		setFrozen(match, false)
		match.phase = "Fighting"
		match.endsAt = serverNow() + Config.RoundTime
		sendState(match)

		while true do
			task.wait(0.1)
			if forfeitWinner(match) then
				break
			end
			if aliveCount(match, 1) == 0 or aliveCount(match, 2) == 0 then
				task.wait(0.25) -- let simultaneous KOs land
				break
			end
			if serverNow() >= match.endsAt then
				break
			end
		end

		winner = forfeitWinner(match)
		if winner then
			break
		end

		local a1, a2 = aliveCount(match, 1), aliveCount(match, 2)
		local roundWinner: number? = nil
		if a1 > 0 and a2 == 0 then
			roundWinner = 1
		elseif a2 > 0 and a1 == 0 then
			roundWinner = 2
		elseif a1 > 0 and a2 > 0 then
			local h1, h2 = teamHealth(match, 1), teamHealth(match, 2)
			if h1 > h2 then
				roundWinner = 1
			elseif h2 > h1 then
				roundWinner = 2
			end
		end

		match.phase = "RoundEnd"
		if roundWinner then
			match.scores[roundWinner] += 1
		end
		match.endsAt = serverNow() + Config.RoundEndTime
		sendState(match, { roundWinner = roundWinner or 0, timeout = a1 > 0 and a2 > 0 })
		task.wait(Config.RoundEndTime)

		if match.scores[1] >= match.mode.roundsToWin then
			winner = 1
			break
		elseif match.scores[2] >= match.mode.roundsToWin then
			winner = 2
			break
		end
	end

	finishMatch(match, winner or 0)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function MatchService.init(mapArenas: { Arena })
	arenas = mapArenas

	Players.PlayerRemoving:Connect(function(player)
		local match = playerMatch[player]
		if not match then
			return
		end
		playerMatch[player] = nil
		match.alive[player] = nil
		for _, members in match.teams do
			local index = table.find(members, player)
			if index then
				table.remove(members, index)
			end
		end
	end)
end

function MatchService.hasFreeArena(): boolean
	for _, arena in arenas do
		if not arena.busy then
			return true
		end
	end
	return false
end

function MatchService.isInMatch(player: Player): boolean
	return playerMatch[player] ~= nil
end

function MatchService.start(modeId: string, teams: { { Player } }): boolean
	local mode = Config.Modes[modeId]
	local free = {}
	for _, arena in arenas do
		if not arena.busy then
			table.insert(free, arena)
		end
	end
	if not mode or #free == 0 then
		return false
	end
	local arena = free[math.random(1, #free)]
	arena.busy = true

	local match: Match = {
		mode = mode,
		arena = arena,
		teams = teams,
		scores = { 0, 0 },
		round = 0,
		phase = "Starting",
		alive = {},
		endsAt = 0,
		connections = {},
	}
	forEachPlayer(match, function(player)
		playerMatch[player] = match
		player:SetAttribute("InMatch", true)
		CombatService.reset(player, true)
	end)

	task.spawn(function()
		local ok, err = pcall(runMatch, match)
		if not ok then
			warn("[sando] Match crashed:", err)
			if match.phase ~= "Ended" then
				pcall(finishMatch, match, 0)
			end
		end
	end)
	return true
end

-- Who a player's swings can hit right now.
function MatchService.getTargets(player: Player): { Model }
	local match = playerMatch[player]
	if not match then
		return CollectionService:GetTagged("SandoDummy") :: { Model }
	end
	local myTeam = teamOf(match, player)
	local targets = {}
	for team, members in match.teams do
		if team ~= myTeam then
			for _, enemy in members do
				if match.alive[enemy] and enemy.Character then
					table.insert(targets, enemy.Character)
				end
			end
		end
	end
	return targets
end

function MatchService.canFight(player: Player): boolean
	local match = playerMatch[player]
	if not match then
		return true -- lobby: only dummies are valid targets
	end
	return match.phase == "Fighting" and match.alive[player] == true
end

return MatchService
