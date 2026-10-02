-- Reads player input (keyboard/mouse, gamepad, touch buttons) and sends it
-- to the server. Movement-based moves (dodge, knockback) run locally because
-- the client owns its character's physics.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatAction = Remotes:WaitForChild("CombatAction") :: RemoteEvent
local CombatFeedback = Remotes:WaitForChild("CombatFeedback") :: RemoteEvent

local player = Players.LocalPlayer

local CombatController = {}

CombatController.Keys = {
	Light = "Click",
	Heavy = "E (hold)",
	Parry = "F",
	Dodge = "Q",
	Ultimate = "G",
}

-- Local predictions so the HUD can show cooldowns and inputs can be buffered
local busyUntil = 0
local bufferedLight = false
local charging = false
CombatController.parryReadyAt = 0
CombatController.dodgeReadyAt = 0

local function character(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return char, humanoid, root
end

local function canAct(): boolean
	local char, _, root = character()
	if not char or not root or root.Anchored then
		return false
	end
	return char:GetAttribute("Stunned") ~= true
end

local function push(velocity: Vector3, duration: number)
	local _, _, root = character()
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	mover.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	mover.MaxForce = 60000
	mover.Parent = root
	Debris:AddItem(mover, duration)
	Debris:AddItem(attachment, duration)
end

local function sendLight()
	if not canAct() or charging then
		return
	end
	local now = os.clock()
	if now < busyUntil then
		-- Buffer one click if it's close to the end of the current move
		if busyUntil - now < 0.3 and not bufferedLight then
			bufferedLight = true
			task.delay(busyUntil - now + 0.02, function()
				bufferedLight = false
				sendLight()
			end)
		end
		return
	end
	CombatAction:FireServer("Light")
end

local function startHeavy()
	if not canAct() or charging or os.clock() < busyUntil then
		return
	end
	charging = true
	CombatAction:FireServer("HeavyStart")
end

local function releaseHeavy()
	if not charging then
		return
	end
	charging = false
	CombatAction:FireServer("HeavyRelease")
end

local function parry()
	local now = os.clock()
	if not canAct() or charging or now < busyUntil or now < CombatController.parryReadyAt then
		return
	end
	CombatController.parryReadyAt = now + Config.ParryCooldown
	CombatAction:FireServer("Parry")
end

local function dodge()
	local now = os.clock()
	local _, humanoid, root = character()
	if not humanoid or not root or not canAct() or now < CombatController.dodgeReadyAt then
		return
	end
	CombatController.dodgeReadyAt = now + Config.DodgeCooldown
	charging = false
	CombatAction:FireServer("Dodge")

	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = -root.CFrame.LookVector -- back-step when standing still
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit
	push(direction * Config.DodgeSpeed, Config.DodgeDuration)
end

local function ultimate()
	if not canAct() or charging or os.clock() < busyUntil then
		return
	end
	if (player:GetAttribute("Ultimate") or 0) < Config.UltMax then
		return
	end
	CombatAction:FireServer("Ultimate")
end

-- Exposed for touch buttons and the HUD
CombatController.actions = {
	Light = sendLight,
	HeavyStart = startHeavy,
	HeavyRelease = releaseHeavy,
	Parry = parry,
	Dodge = dodge,
	Ultimate = ultimate,
}

local function onOwnSwing(kind: string, index: number, windup: number)
	local char = player.Character
	local weapon = Weapons.get(char and char:GetAttribute("Weapon") or Weapons.Default)
	local now = os.clock()
	if kind == "Light" then
		local isLast = index >= #weapon.damage.light
		busyUntil = now + windup + (if isLast then weapon.comboEndRecovery else weapon.lightRecovery) - 0.05
	elseif kind == "Heavy" then
		busyUntil = now + windup + weapon.heavyRecovery - 0.05
		charging = false
	elseif kind == "Ultimate" then
		busyUntil = now + windup + 0.55
	end
end

function CombatController.start()
	-- Keyboard and mouse
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			sendLight()
		elseif input.KeyCode == Enum.KeyCode.E then
			startHeavy()
		elseif input.KeyCode == Enum.KeyCode.F then
			parry()
		elseif input.KeyCode == Enum.KeyCode.Q then
			dodge()
		elseif input.KeyCode == Enum.KeyCode.G then
			ultimate()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.E then
			releaseHeavy()
		end
	end)

	-- Gamepad + on-screen touch buttons
	local function bind(name: string, title: string, key: Enum.KeyCode, position: UDim2, onBegin: () -> (), onEnd: (() -> ())?)
		ContextActionService:BindAction(name, function(_, state)
			if state == Enum.UserInputState.Begin then
				onBegin()
			elseif state == Enum.UserInputState.End and onEnd then
				onEnd()
			end
			return Enum.ContextActionResult.Sink
		end, true, key)
		ContextActionService:SetTitle(name, title)
		ContextActionService:SetPosition(name, position)
	end
	bind("SandoLight", "Attack", Enum.KeyCode.ButtonR2, UDim2.new(1, -95, 1, -170), sendLight)
	bind("SandoHeavy", "Heavy", Enum.KeyCode.ButtonL2, UDim2.new(1, -165, 1, -130), startHeavy, releaseHeavy)
	bind("SandoParry", "Parry", Enum.KeyCode.ButtonR1, UDim2.new(1, -165, 1, -200), parry)
	bind("SandoDodge", "Dodge", Enum.KeyCode.ButtonB, UDim2.new(1, -95, 1, -240), dodge)
	bind("SandoUlt", "Ult", Enum.KeyCode.ButtonY, UDim2.new(1, -235, 1, -165), ultimate)

	CombatFeedback.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any)
		local myCharacter = player.Character
		if kind == "Swing" and a == myCharacter then
			onOwnSwing(b, c, d)
		elseif kind == "Knockback" then
			push(a, 0.12)
		elseif (kind == "Stunned" or kind == "Cancel") and a == myCharacter then
			charging = false
		elseif kind == "Parried" and b == myCharacter then
			busyUntil = 0 -- successful parry: free to punish
		end
	end)

	player.CharacterAdded:Connect(function()
		busyUntil = 0
		charging = false
		CombatController.parryReadyAt = 0
		CombatController.dodgeReadyAt = 0
	end)
end

return CombatController
