-- The whole on-screen UI, built in code: lobby play menu and stats, match
-- scoreboard, team health bars, round announcer, ultimate meter, cooldowns
-- and toast notifications.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchState = Remotes:WaitForChild("MatchState") :: RemoteEvent
local QueueRequest = Remotes:WaitForChild("QueueRequest") :: RemoteEvent
local QueueState = Remotes:WaitForChild("QueueState") :: RemoteEvent
local Notify = Remotes:WaitForChild("Notify") :: RemoteEvent
local CombatFeedback = Remotes:WaitForChild("CombatFeedback") :: RemoteEvent

local CombatController = require(script.Parent.CombatController)

local player = Players.LocalPlayer

local Hud = {}

local COLORS = {
	panel = Color3.fromRGB(20, 18, 24),
	panelLight = Color3.fromRGB(38, 34, 44),
	text = Color3.fromRGB(245, 240, 232),
	muted = Color3.fromRGB(170, 162, 160),
	gold = Color3.fromRGB(255, 205, 90),
	ally = Color3.fromRGB(90, 170, 255),
	enemy = Color3.fromRGB(255, 90, 100),
	good = Color3.fromRGB(120, 230, 140),
	bad = Color3.fromRGB(255, 110, 110),
	ult = Color3.fromRGB(255, 180, 60),
}

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	instance.Parent = parent
	return instance
end

local function corner(radius: number)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color: Color3, thickness: number, transparency: number?)
	return new("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function label(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or COLORS.text
	props.TextScaled = if props.TextScaled == nil then true else props.TextScaled
	return new("TextLabel", props)
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local gui = new("ScreenGui", {
	Name = "SandoHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Announcer
local announcer = label({
	Name = "Announcer",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.36),
	Size = UDim2.fromScale(0.6, 0.12),
	Font = Enum.Font.GothamBlack,
	TextTransparency = 1,
	TextStrokeTransparency = 1,
	Text = "",
	ZIndex = 20,
	Parent = gui,
})
local subAnnouncer = label({
	Name = "SubAnnouncer",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromScale(0.5, 0.045),
	TextTransparency = 1,
	TextStrokeTransparency = 1,
	Text = "",
	ZIndex = 20,
	Parent = gui,
})

local announceToken = 0
local function announce(text: string, color: Color3?, sub: string?, hold: number?)
	announceToken += 1
	local token = announceToken
	announcer.Text = text
	announcer.TextColor3 = color or COLORS.text
	subAnnouncer.Text = sub or ""
	announcer.TextTransparency = 0
	announcer.TextStrokeTransparency = 0.3
	subAnnouncer.TextTransparency = 0
	subAnnouncer.TextStrokeTransparency = 0.5
	announcer.Size = UDim2.fromScale(0.75, 0.15)
	TweenService:Create(announcer, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.6, 0.12) }):Play()
	task.delay(hold or 1.2, function()
		if announceToken ~= token then
			return
		end
		local info = TweenInfo.new(0.35)
		TweenService:Create(announcer, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(subAnnouncer, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

-- Toasts
local toastList = new("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 120),
	Size = UDim2.fromOffset(420, 200),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
})
local toastOrder = 0
local function toast(text: string, kind: string?)
	toastOrder += 1
	local color = if kind == "good" then COLORS.good elseif kind == "bad" then COLORS.bad else COLORS.text
	local frame = new("Frame", {
		Size = UDim2.fromOffset(400, 34),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.15,
		LayoutOrder = toastOrder,
		Parent = toastList,
	}, {
		corner(8),
		stroke(color, 1.5, 0.3),
	})
	local text_ = label({ Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), Text = text, TextColor3 = color, Parent = frame })
	task.delay(2.6, function()
		local info = TweenInfo.new(0.3)
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(text_, info, { TextTransparency = 1 }):Play()
		task.wait(0.3)
		frame:Destroy()
	end)
end

-- Lobby stats (top right)
local stats = new("Frame", {
	Name = "Stats",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 60),
	Size = UDim2.fromOffset(210, 96),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.2,
	Parent = gui,
}, { corner(10), stroke(COLORS.gold, 1, 0.6) })
local goldLabel = label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 30), Text = "0 gold", TextColor3 = COLORS.gold, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, Parent = stats })
local recordLabel = label({ Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 20), Text = "", TextColor3 = COLORS.muted, TextXAlignment = Enum.TextXAlignment.Left, Parent = stats })
local weaponLabel = label({ Position = UDim2.fromOffset(12, 66), Size = UDim2.new(1, -24, 0, 20), Text = "", TextColor3 = COLORS.text, TextXAlignment = Enum.TextXAlignment.Left, Parent = stats })

-- Play menu (left)
local playPanel = new("Frame", {
	Name = "PlayPanel",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.5, 0),
	Size = UDim2.fromOffset(250, 300),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { corner(12), stroke(COLORS.panelLight, 2) })
label({ Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 34), Text = "PLAY A DUEL", Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, Parent = playPanel })
local queueStatus = label({ Position = UDim2.new(0, 16, 1, -36), Size = UDim2.new(1, -32, 0, 22), Text = "Pick a mode or step on a pad", TextColor3 = COLORS.muted, TextXAlignment = Enum.TextXAlignment.Left, Parent = playPanel })

local modeButtons = {}
local queueCounts: { [string]: number } = {}
for i, modeId in Config.ModeOrder do
	local mode = Config.Modes[modeId]
	local button = new("TextButton", {
		Name = modeId,
		Position = UDim2.fromOffset(16, 56 + (i - 1) * 66),
		Size = UDim2.new(1, -32, 0, 58),
		BackgroundColor3 = COLORS.panelLight,
		AutoButtonColor = true,
		Text = "",
		Parent = playPanel,
	}, { corner(10) })
	local buttonStroke = stroke(COLORS.ally, 2, 1)
	buttonStroke.Parent = button
	local title = label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 26), Text = mode.displayName, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, Parent = button })
	local detail = label({ Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 18), Text = "", TextColor3 = COLORS.muted, TextXAlignment = Enum.TextXAlignment.Left, Parent = button })
	button.Activated:Connect(function()
		if player:GetAttribute("QueuedMode") == modeId then
			QueueRequest:FireServer("Leave")
		else
			QueueRequest:FireServer("Join", modeId)
		end
	end)
	modeButtons[modeId] = { button = button, stroke = buttonStroke, title = title, detail = detail }
end

local function refreshPlayPanel()
	local duels = player:GetAttribute("Duels") or 0
	local queued = player:GetAttribute("QueuedMode")
	for modeId, entry in modeButtons do
		local mode = Config.Modes[modeId]
		local needed = mode.teamSize * 2
		local locked = duels < mode.unlockDuels
		if locked then
			entry.detail.Text = string.format("Locked: %d more duels", mode.unlockDuels - duels)
			entry.title.TextColor3 = COLORS.muted
		elseif queued == modeId then
			entry.detail.Text = string.format("In queue (%d/%d). Click to leave", queueCounts[modeId] or 1, needed)
			entry.title.TextColor3 = COLORS.text
		else
			entry.detail.Text = string.format("%d/%d waiting  ·  Bo%d", queueCounts[modeId] or 0, needed, mode.roundsToWin * 2 - 1)
			entry.title.TextColor3 = COLORS.text
		end
		entry.stroke.Transparency = if queued == modeId then 0 else 1
	end
	if queued then
		queueStatus.Text = "Searching for " .. Config.Modes[queued].displayName .. "..."
		queueStatus.TextColor3 = COLORS.gold
	else
		queueStatus.Text = "Pick a mode or step on a pad"
		queueStatus.TextColor3 = COLORS.muted
	end
end

local function refreshStats()
	goldLabel.Text = string.format("%d gold", player:GetAttribute("Gold") or 0)
	recordLabel.Text = string.format("Wins %d  ·  Duels %d  ·  Elo %d", player:GetAttribute("Wins") or 0, player:GetAttribute("Duels") or 0, player:GetAttribute("Elo") or Config.StartingElo)
	local weapon = Weapons.get(player:GetAttribute("Equipped") or Weapons.Default)
	weaponLabel.Text = "Weapon: " .. weapon.displayName
	refreshPlayPanel()
end

-- Match scoreboard (top center)
local scoreboard = new("Frame", {
	Name = "Scoreboard",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(240, 96),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.15,
	Visible = false,
	Parent = gui,
}, { corner(12) })
local roundLabel = label({ Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 18), Text = "ROUND 1", TextColor3 = COLORS.muted, Parent = scoreboard })
local allyScore = label({ Position = UDim2.fromOffset(20, 24), Size = UDim2.fromOffset(60, 44), Text = "0", TextColor3 = COLORS.ally, Font = Enum.Font.GothamBlack, Parent = scoreboard })
local enemyScore = label({ Position = UDim2.new(1, -80, 0, 24), Size = UDim2.fromOffset(60, 44), Text = "0", TextColor3 = COLORS.enemy, Font = Enum.Font.GothamBlack, Parent = scoreboard })
local timerLabel = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 28), Size = UDim2.fromOffset(90, 34), Text = "1:30", Font = Enum.Font.GothamBlack, Parent = scoreboard })
local arenaLabel = label({ Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 16), Text = "", TextColor3 = COLORS.muted, Parent = scoreboard })

-- Team health bars
local function makeTeamColumn(side: number)
	return new("Frame", {
		Name = if side == 1 then "AllyBars" else "EnemyBars",
		AnchorPoint = Vector2.new(if side == 1 then 1 else 0, 0),
		Position = UDim2.new(0.5, if side == 1 then -132 else 132, 0, 14),
		Size = UDim2.fromOffset(280, 120),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	}, {
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
end
local columns = { makeTeamColumn(1), makeTeamColumn(2) }

type Bar = { player: Player, fill: Frame, text: TextLabel, frame: Frame }
local bars: { Bar } = {}

local function clearBars()
	for _, bar in bars do
		bar.frame:Destroy()
	end
	table.clear(bars)
end

local function addBar(target: Player, column: Frame, color: Color3, order: number)
	local frame = new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = column,
	})
	label({ Size = UDim2.new(1, 0, 0, 16), Text = target.DisplayName, TextXAlignment = if column == columns[1] then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left, Parent = frame })
	local back = new("Frame", {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.1,
		Parent = frame,
	}, { corner(6), stroke(Color3.new(0, 0, 0), 1, 0.4) })
	local fill = new("Frame", {
		AnchorPoint = Vector2.new(if column == columns[1] then 1 else 0, 0),
		Position = UDim2.fromScale(if column == columns[1] then 1 else 0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		Parent = back,
	}, { corner(6) })
	local text = label({ Size = UDim2.fromScale(1, 1), Text = "100", Font = Enum.Font.GothamBlack, ZIndex = 2, Parent = back })
	table.insert(bars, { player = target, fill = fill, text = text, frame = frame })
end

-- Ultimate meter + cooldowns (bottom center)
local combatBar = new("Frame", {
	Name = "CombatBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(360, 74),
	BackgroundTransparency = 1,
	Parent = gui,
})
local ultBack = new("Frame", {
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.15,
	Parent = combatBar,
}, { corner(8), stroke(COLORS.ult, 1.5, 0.5) })
local ultFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = COLORS.ult, Parent = ultBack }, { corner(8) })
local ultText = label({ Size = UDim2.fromScale(1, 1), Text = "ULTIMATE 0%", Font = Enum.Font.GothamBlack, ZIndex = 2, Parent = ultBack })

local function cooldownBox(x: number, key: string, name: string)
	local box = new("Frame", {
		Position = UDim2.new(0, x, 0, 30),
		Size = UDim2.new(0.33, -6, 0, 40),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.15,
		ClipsDescendants = true,
		Parent = combatBar,
	}, { corner(8) })
	local shade = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		ZIndex = 2,
		Parent = box,
	})
	label({ Size = UDim2.new(1, -8, 0.5, 0), Position = UDim2.fromOffset(4, 2), Text = key, Font = Enum.Font.GothamBlack, TextColor3 = COLORS.gold, ZIndex = 3, Parent = box })
	label({ Size = UDim2.new(1, -8, 0.4, 0), Position = UDim2.new(0, 4, 0.55, 0), Text = name, TextColor3 = COLORS.muted, ZIndex = 3, Parent = box })
	return shade
end
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local parryShade = cooldownBox(0, if isTouch then "PARRY" else CombatController.Keys.Parry, "Parry")
local dodgeShade = cooldownBox(122, if isTouch then "DODGE" else CombatController.Keys.Dodge, "Dodge")
local heavyBox = cooldownBox(244, if isTouch then "HEAVY" else CombatController.Keys.Heavy, "Heavy")
heavyBox.Size = UDim2.fromScale(1, 0)

-- Controls hint (bottom left)
if not isTouch then
	label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(330, 18),
		Text = "Click attack · Hold E heavy · F parry · Q dodge · G ultimate",
		TextColor3 = COLORS.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = gui,
	})
end

---------------------------------------------------------------------------
-- Match state
---------------------------------------------------------------------------

local currentMatch: { [string]: any }? = nil
local countdownToken = 0

local function setLobbyVisible(visible: boolean)
	playPanel.Visible = visible
	stats.Visible = visible
end

local function setMatchVisible(visible: boolean)
	scoreboard.Visible = visible
	columns[1].Visible = visible
	columns[2].Visible = visible
end

local function rebuildBars(match)
	clearBars()
	local myTeam = match.myTeam
	local enemyTeam = 3 - myTeam
	for i, member in match.teams[myTeam] do
		addBar(member, columns[1], COLORS.ally, i)
	end
	for i, member in match.teams[enemyTeam] do
		addBar(member, columns[2], COLORS.enemy, i)
	end
end

local function onMatchState(match: { [string]: any })
	if match.state == "Lobby" then
		currentMatch = nil
		clearBars()
		setMatchVisible(false)
		setLobbyVisible(true)
		refreshStats()
		return
	end

	currentMatch = match
	setLobbyVisible(false)
	setMatchVisible(true)
	rebuildBars(match)

	local myTeam = match.myTeam
	allyScore.Text = tostring(match.scores[myTeam])
	enemyScore.Text = tostring(match.scores[3 - myTeam])
	roundLabel.Text = string.format("ROUND %d  ·  FIRST TO %d", match.round, match.roundsToWin)
	arenaLabel.Text = match.arena

	if match.state == "Countdown" then
		countdownToken += 1
		local token = countdownToken
		announce("ROUND " .. match.round, COLORS.text, match.modeName .. "  ·  " .. match.arena, 1)
		task.spawn(function()
			while countdownToken == token do
				local remaining = match.endsAt - workspace:GetServerTimeNow()
				if remaining <= 0 then
					break
				end
				local whole = math.ceil(remaining)
				if remaining < Config.CountdownTime - 0.9 then
					announcer.Text = tostring(whole)
					announcer.TextColor3 = COLORS.gold
					announcer.TextTransparency = 0
					announcer.TextStrokeTransparency = 0.3
					subAnnouncer.TextTransparency = 1
				end
				task.wait(0.05)
			end
		end)
	elseif match.state == "Fighting" then
		countdownToken += 1
		announce("FIGHT!", COLORS.gold, nil, 0.7)
	elseif match.state == "RoundEnd" then
		countdownToken += 1
		if match.roundWinner == myTeam then
			announce("ROUND WON", COLORS.good, if match.timeout then "Time up: more health left" else nil)
		elseif match.roundWinner == 0 then
			announce("DRAW", COLORS.muted, "No point awarded")
		else
			announce("ROUND LOST", COLORS.bad, if match.timeout then "Time up: less health left" else nil)
		end
	elseif match.state == "Ended" then
		countdownToken += 1
		local sub = string.format("+%d gold", match.gold or 0)
		if match.eloDelta then
			sub ..= string.format("   %s%d Elo", if match.eloDelta >= 0 then "+" else "", match.eloDelta)
		end
		if match.won then
			announce("VICTORY", COLORS.gold, sub, Config.MatchEndTime - 0.5)
		else
			announce("DEFEAT", COLORS.bad, sub, Config.MatchEndTime - 0.5)
		end
	end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

function Hud.start()
	for _, attribute in { "Gold", "Wins", "Duels", "Elo", "Equipped" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshStats)
	end
	player:GetAttributeChangedSignal("QueuedMode"):Connect(refreshPlayPanel)
	refreshStats()

	QueueState.OnClientEvent:Connect(function(counts)
		queueCounts = counts
		refreshPlayPanel()
	end)
	QueueRequest:FireServer("Sync")

	Notify.OnClientEvent:Connect(toast)
	MatchState.OnClientEvent:Connect(onMatchState)

	CombatFeedback.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		local myCharacter = player.Character
		if kind == "Parried" then
			if b == myCharacter then
				announce("PARRY!", COLORS.gold, nil, 0.5)
			elseif a == myCharacter then
				announce("PARRIED", COLORS.bad, nil, 0.5)
			end
		elseif kind == "Dodged" and a == myCharacter then
			announce("DODGE", COLORS.ally, nil, 0.4)
		elseif kind == "KO" and currentMatch and a ~= myCharacter then
			local victim = Players:GetPlayerFromCharacter(a)
			if victim then
				toast(victim.DisplayName .. " was knocked out", "good")
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()

		-- Ultimate meter
		local ult = player:GetAttribute("Ultimate") or 0
		ultFill.Size = UDim2.fromScale(ult / Config.UltMax, 1)
		if ult >= Config.UltMax then
			ultText.Text = if isTouch then "ULTIMATE READY" else "ULTIMATE READY [" .. CombatController.Keys.Ultimate .. "]"
			ultFill.BackgroundColor3 = COLORS.ult:Lerp(Color3.new(1, 1, 1), (math.sin(now * 8) + 1) * 0.2)
		else
			ultText.Text = string.format("ULTIMATE %d%%", math.floor(ult))
			ultFill.BackgroundColor3 = COLORS.ult
		end

		-- Cooldowns
		local parryLeft = math.max(0, CombatController.parryReadyAt - now) / Config.ParryCooldown
		local dodgeLeft = math.max(0, CombatController.dodgeReadyAt - now) / Config.DodgeCooldown
		parryShade.Size = UDim2.fromScale(1, math.clamp(parryLeft, 0, 1))
		dodgeShade.Size = UDim2.fromScale(1, math.clamp(dodgeLeft, 0, 1))

		-- Health bars and round timer
		if currentMatch then
			for _, bar in bars do
				local character = bar.player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local fraction = if humanoid then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
				bar.fill.Size = UDim2.fromScale(fraction, 1)
				bar.text.Text = tostring(math.ceil(if humanoid then humanoid.Health else 0))
			end
			local remaining = (currentMatch.endsAt or 0) - workspace:GetServerTimeNow()
			if currentMatch.state == "Fighting" then
				timerLabel.Text = formatTime(remaining)
				timerLabel.TextColor3 = if remaining < 10 then COLORS.bad else COLORS.text
			elseif currentMatch.state == "Countdown" then
				timerLabel.Text = formatTime(Config.RoundTime)
				timerLabel.TextColor3 = COLORS.text
			end
		end
	end)
end

return Hud
