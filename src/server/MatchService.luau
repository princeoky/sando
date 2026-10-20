-- Runs matches: grabs a free arena, spawns teams, loops countdown -> fight ->
-- round end until a team wins enough rounds, then pays out and returns
-- everyone to the lobby.
--
-- Team members are Players or practice Bots. Helpers below hide the
-- difference (spawning, messaging, rewards).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchState = Remotes.MatchState :: RemoteEvent
local CombatFeedback = Remotes.CombatFeedback :: RemoteEvent

local Bot = require(script.Parent.Bot)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)

local MatchService = {}

type Member = any -- Player or Bot

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
	teams: { { Member } },
	scores: { number },
	round: number,
	phase: string,
	alive: { [Member]: boolean },
	endsAt: number,
	connections: { RBXScriptConnection },
	bots: { any },
}

local arenas: { Arena } = {}
local memberMatch: { [Member]: Match } = {}

local endedEvent = Instance.new("BindableEvent")
MatchService.Ended = endedEvent.Event

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function isBot(member: Member): boolean
	return type(member) == "table" and member.isBot == true
end

local function stillHere(member: Member): boolean
	if isBot(member) then
		return member.active
	end
	return member.Parent ~= nil
end

-- Spawns a player's character. LoadCharacterAsync is the current API; fall
-- back to LoadCharacter on Studio builds that don't have it yet.
function MatchService.spawnPlayer(player: Player): boolean
	local ok, err = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok then
		ok, err = pcall(function()
			(player :: any):LoadCharacter()
		end)
	end
	if not ok then
		warn("[sando] Couldn't spawn", player.Name, err)
	end
	return ok
end

local function teamOf(match: Match, member: Member): number?
	for team, members in match.teams do
		if table.find(members, member) then
			return team
		end
	end
	return nil
end

local function forEachMember(match: Match, fn: (Member, number, number) -> ())
	for team, members in match.teams do
		for slot, member in members do
			fn(member, team, slot)
		end
	end
end

local function forEachPlayer(match: Match, fn: (Player, number, number) -> ())
	forEachMember(match, function(member, team, slot)
		if not isBot(member) then
			fn(member, team, slot)
		end
	end)
end

local function aliveCount(match: Match, team: number): number
	local count = 0
	for _, member in match.teams[team] do
		if match.alive[member] then
			count += 1
		end
	end
	return count
end

local function teamHealth(match: Match, team: number): number
	local total = 0
	for _, member in match.teams[team] do
		local humanoid = match.alive[member] and member.Character and member.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			total += humanoid.Health / humanoid.MaxHealth
		end
	end
	return total
end

-- Clients get a plain snapshot of each team: names and current characters.
local function teamSnapshot(match: Match)
	local snapshot = {}
	for team, members in match.teams do
		snapshot[team] = {}
		for _, member in members do
			table.insert(snapshot[team], { name = member.DisplayName, character = member.Character })
		end
	end
	return snapshot
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
		teams = teamSnapshot(match),
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
	forEachMember(match, function(member)
		local character = member.Character
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
	forEachMember(match, function(member, team, slot)
		pending += 1
		task.spawn(function()
			local spawnAt = match.arena.spawns[team][slot] or match.arena.spawns[team][1]
			local ok, err = pcall(function()
				local character: Model
				if isBot(member) then
					character = member:spawn(spawnAt)
				else
					if not MatchService.spawnPlayer(member) then
						return
					end
					character = member.Character
				end
				if not character or not stillHere(member) then
					return
				end
				local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
				local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
				if not root or not humanoid then
					return
				end
				character:PivotTo(spawnAt)
				root.Anchored = true
				match.alive[member] = true
				table.insert(match.connections, humanoid.Died:Connect(function()
					match.alive[member] = nil
					CombatFeedback:FireAllClients("KO", character)
				end))
			end)
			if not ok then
				warn("[sando] Failed to spawn", member.Name, err)
			end
			pending -= 1
		end)
	end)

	local started = os.clock()
	while pending > 0 and os.clock() - started < 10 do
		task.wait()
	end
end

-- A team with no real players left forfeits (bots can't win on their own).
local function forfeitWinner(match: Match): number?
	local function hasPlayers(team: number): boolean
		for _, member in match.teams[team] do
			if not isBot(member) then
				return true
			end
		end
		return false
	end
	local function empty(team: number): boolean
		return #match.teams[team] == 0
	end
	if not hasPlayers(1) and not hasPlayers(2) then
		return 0
	elseif empty(1) then
		return 2
	elseif empty(2) then
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
		for _, member in match.teams[team] do
			local data = not isBot(member) and DataService.get(member)
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
		for _, member in match.teams[team] do
			changes[member] = delta
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
		if match.mode.practice then
			DataService.addGold(player, gold) -- practice doesn't count as a duel
		else
			DataService.recordMatch(player, won, gold, elo[player])
		end
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
	for _, bot in match.bots do
		memberMatch[bot] = nil
		bot:destroy()
	end
	forEachPlayer(match, function(player)
		memberMatch[player] = nil
		player:SetAttribute("InMatch", false)
		CombatService.reset(player, true)
		MatchState:FireClient(player, { state = "Lobby" })
		task.spawn(function()
			if player.Parent then
				MatchService.spawnPlayer(player)
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
		local match = memberMatch[player]
		if not match then
			return
		end
		memberMatch[player] = nil
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
	return memberMatch[player] ~= nil
end

-- Who a fighter's swings can hit right now.
function MatchService.getTargets(member: Member): { Model }
	local match = memberMatch[member]
	if not match then
		return CollectionService:GetTagged("SandoDummy") :: { Model }
	end
	local myTeam = teamOf(match, member)
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

function MatchService.canFight(member: Member): boolean
	local match = memberMatch[member]
	if not match then
		return not isBot(member) -- lobby: players can hit dummies
	end
	return match.phase == "Fighting" and match.alive[member] == true
end

function MatchService.start(modeId: string, teams: { { Member } }): boolean
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
		bots = {},
	}
	forEachMember(match, function(member)
		memberMatch[member] = match
		if isBot(member) then
			table.insert(match.bots, member)
		else
			member:SetAttribute("InMatch", true)
			CombatService.reset(member, true)
		end
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

-- Practice: one player against a bot, starting right away.
function MatchService.startPractice(player: Player): boolean
	if not MatchService.hasFreeArena() then
		return false
	end
	local bot = Bot.new(MatchService.getTargets, MatchService.canFight)
	if not MatchService.start("Practice", { { player }, { bot } }) then
		bot:destroy()
		return false
	end
	return true
end

return MatchService
