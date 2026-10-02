-- Plays everything players see and hear when combat happens: procedural
-- weapon swings (no animation assets needed), trails, charge glow, parry
-- sparks, hit flashes, damage numbers and camera shake.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WeaponFactory = require(Shared.WeaponFactory)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatFeedback = Remotes:WaitForChild("CombatFeedback") :: RemoteEvent

local player = Players.LocalPlayer

local Effects = {}

local SOUNDS = {
	Light = "rbxasset://sounds/swordslash.wav",
	Heavy = "rbxasset://sounds/swordlunge.wav",
	Ultimate = "rbxasset://sounds/swordlunge.wav",
	Parry = "rbxasset://sounds/unsheath.wav",
	Hit = "rbxasset://sounds/swordslash.wav",
}

local activeTweens: { [Weld]: Tween } = {}
local chargeTokens: { [Model]: number } = {}

local function playSound(id: string, parent: Instance?, volume: number?, pitch: number?)
	if not parent then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 80
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function rootOf(character: Model?): BasePart?
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

type Grip = { weld: Weld, base: CFrame, model: Model }

local function grip(character: Model, name: string): Grip?
	local model = character:FindFirstChild(name)
	if not model or not model:IsA("Model") then
		return nil
	end
	local gripPart = model:FindFirstChild("Grip")
	local weld = gripPart and gripPart:FindFirstChild("GripWeld")
	local base = gripPart and gripPart:GetAttribute("GripBase")
	if not weld or typeof(base) ~= "CFrame" then
		return nil
	end
	return { weld = weld :: Weld, base = base :: CFrame, model = model }
end

local function grips(character: Model): (Grip?, Grip?)
	return grip(character, WeaponFactory.MainName), grip(character, WeaponFactory.OffhandName)
end

local function tweenGrip(g: Grip, rotation: CFrame, time: number, style: Enum.EasingStyle?): Tween
	local existing = activeTweens[g.weld]
	if existing then
		existing:Cancel()
	end
	local tween = TweenService:Create(g.weld, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		C0 = g.base * rotation,
	})
	activeTweens[g.weld] = tween
	tween:Play()
	return tween
end

local function setTrail(g: Grip?, enabled: boolean)
	if not g then
		return
	end
	for _, d in g.model:GetDescendants() do
		if d:IsA("Trail") then
			d.Enabled = enabled
		end
	end
end

local function setGlow(character: Model, enabled: boolean)
	for _, name in { WeaponFactory.MainName, WeaponFactory.OffhandName } do
		local model = character:FindFirstChild(name)
		if model then
			for _, d in model:GetDescendants() do
				if d:IsA("PointLight") and d.Name == "ChargeGlow" then
					d.Enabled = enabled
				end
			end
			local highlight = model:FindFirstChild("ChargeHighlight")
			if enabled and not highlight then
				local h = Instance.new("Highlight")
				h.Name = "ChargeHighlight"
				h.FillColor = Color3.fromRGB(255, 60, 60)
				h.FillTransparency = 0.3
				h.OutlineColor = Color3.fromRGB(255, 220, 120)
				h.DepthMode = Enum.HighlightDepthMode.Occluded
				h.Parent = model
			elseif not enabled and highlight then
				highlight:Destroy()
			end
		end
	end
end

-- Wind up to `from`, strike through to `to`, then settle back to rest.
local function swingGrip(g: Grip?, from: CFrame, to: CFrame, windup: number, strike: number)
	if not g then
		return
	end
	tweenGrip(g, from, math.max(windup - 0.02, 0.03))
	task.delay(windup, function()
		setTrail(g, true)
		tweenGrip(g, to, strike, Enum.EasingStyle.Quart)
		task.delay(strike + 0.08, function()
			setTrail(g, false)
			tweenGrip(g, CFrame.new(), 0.22)
		end)
	end)
end

local function spinGrip(g: Grip?, windup: number)
	if not g then
		return
	end
	tweenGrip(g, CFrame.Angles(math.rad(110), 0, 0), windup * 0.9)
	task.delay(windup, function()
		local existing = activeTweens[g.weld]
		if existing then
			existing:Cancel()
		end
		setTrail(g, true)
		local started = os.clock()
		local duration = 0.35
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - started) / duration, 0, 1)
			if g.weld.Parent then
				g.weld.C0 = g.base * CFrame.Angles(0, -t * math.pi * 2, 0) * CFrame.Angles(math.rad(-10), 0, 0)
			end
			if t >= 1 then
				connection:Disconnect()
				setTrail(g, false)
				tweenGrip(g, CFrame.new(), 0.2)
			end
		end)
	end)
end

local SLASH_RIGHT = CFrame.Angles(0, math.rad(-85), math.rad(20))
local SLASH_LEFT = CFrame.Angles(0, math.rad(85), math.rad(-20))
local OVERHEAD = CFrame.Angles(math.rad(105), 0, 0)
local DOWNWARD = CFrame.Angles(math.rad(-55), 0, 0)

local function onSwing(character: Model, kind: string, index: number, windup: number)
	local main, off = grips(character)
	local root = rootOf(character)
	chargeTokens[character] = (chargeTokens[character] or 0) + 1
	setGlow(character, false)

	if kind == "Light" then
		local finisher = index >= 3 and index % 2 == 1 and not off
		if finisher then
			swingGrip(main, OVERHEAD, DOWNWARD, windup, 0.12)
		elseif index % 2 == 0 and off then
			swingGrip(off, SLASH_LEFT, SLASH_RIGHT, windup, 0.1)
		elseif index % 2 == 0 then
			swingGrip(main, SLASH_LEFT, SLASH_RIGHT, windup, 0.1)
		else
			swingGrip(main, SLASH_RIGHT, SLASH_LEFT, windup, 0.1)
		end
		task.delay(windup, playSound, SOUNDS.Light, root, 0.5, 1 + index * 0.05)
	elseif kind == "Heavy" then
		swingGrip(main, OVERHEAD, DOWNWARD, windup, 0.14)
		swingGrip(off, OVERHEAD, DOWNWARD, windup, 0.14)
		task.delay(windup, playSound, SOUNDS.Heavy, root, 0.7, 0.9)
	elseif kind == "Ultimate" then
		spinGrip(main, windup)
		spinGrip(off, windup)
		task.delay(windup, playSound, SOUNDS.Ultimate, root, 0.9, 0.7)
		if root then
			local aura = Instance.new("Part")
			aura.Shape = Enum.PartType.Ball
			aura.Anchored = true
			aura.CanCollide = false
			aura.CanQuery = false
			aura.Material = Enum.Material.ForceField
			aura.Color = Color3.fromRGB(255, 200, 90)
			aura.Size = Vector3.new(4, 4, 4)
			aura.CFrame = root.CFrame
			aura.Parent = workspace
			TweenService:Create(aura, TweenInfo.new(windup + 0.35), { Size = Vector3.new(22, 22, 22), Transparency = 1 }):Play()
			Debris:AddItem(aura, windup + 0.4)
		end
	end
end

local function onChargeStart(character: Model, maxCharge: number)
	local main, off = grips(character)
	if main then
		tweenGrip(main, OVERHEAD, 0.3)
	end
	if off then
		tweenGrip(off, OVERHEAD, 0.3)
	end
	local token = (chargeTokens[character] or 0) + 1
	chargeTokens[character] = token
	task.delay(maxCharge * Config.HeavyUnparryableAt, function()
		if chargeTokens[character] == token then
			setGlow(character, true)
		end
	end)
end

local function resetGrips(character: Model)
	chargeTokens[character] = (chargeTokens[character] or 0) + 1
	setGlow(character, false)
	local main, off = grips(character)
	for _, g in { main, off } do
		if g then
			setTrail(g, false)
			tweenGrip(g, CFrame.new(), 0.15)
		end
	end
end

local function onParry(character: Model)
	local main, off = grips(character)
	local guard = CFrame.Angles(math.rad(75), math.rad(-35), 0)
	for _, g in { main, off } do
		if g then
			tweenGrip(g, guard, 0.06)
			task.delay(Config.ParryWindow, function()
				tweenGrip(g, CFrame.new(), 0.18)
			end)
		end
	end
	playSound(SOUNDS.Parry, rootOf(character), 0.35, 1.4)
end

local function burst(position: Vector3, color: Color3, count: number, speed: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.2, 0.45)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 6
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(count)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 4
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.3), { Brightness = 0 }):Play()

	Debris:AddItem(anchor, 1)
end

local function flash(character: Model, color: Color3)
	local h = Instance.new("Highlight")
	h.FillColor = color
	h.FillTransparency = 0.35
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = character
	TweenService:Create(h, TweenInfo.new(0.2), { FillTransparency = 1 }):Play()
	Debris:AddItem(h, 0.25)
end

local function damageNumber(character: Model, amount: number, color: Color3)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(math.random(-10, 10) / 10, 2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = head
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = tostring(math.floor(amount + 0.5))
	label.Parent = gui

	TweenService:Create(gui, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 2.5, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(gui, 0.75)
end

local shakeUntil = 0
local shakeStrength = 0
function Effects.shake(strength: number, duration: number)
	shakeStrength = math.max(shakeStrength, strength)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

local function afterimage(character: Model)
	local root = rootOf(character)
	if not root then
		return
	end
	local ghost = Instance.new("Part")
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.Material = Enum.Material.Neon
	ghost.Color = Color3.fromRGB(200, 230, 255)
	ghost.Transparency = 0.6
	ghost.Size = Vector3.new(2, 5, 1)
	ghost.CFrame = root.CFrame
	ghost.Parent = workspace
	TweenService:Create(ghost, TweenInfo.new(0.3), { Transparency = 1, Size = Vector3.new(2.6, 5.4, 0.2) }):Play()
	Debris:AddItem(ghost, 0.35)
end

local function stunRing(character: Model, duration: number)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head or duration < 0.6 then
		return
	end
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 225, 80)
	ring.Size = Vector3.new(0.15, 2.4, 2.4)
	ring.Transparency = 0.3
	ring.Parent = workspace
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > duration or not head.Parent then
			connection:Disconnect()
			ring:Destroy()
			return
		end
		ring.CFrame = CFrame.new(head.Position + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, t * 8, math.rad(90))
	end)
end

function Effects.start()
	CombatFeedback.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any)
		local myCharacter = player.Character
		if kind == "Swing" then
			onSwing(a, b, c, d)
		elseif kind == "ChargeStart" then
			onChargeStart(a, b)
		elseif kind == "Cancel" then
			resetGrips(a)
		elseif kind == "Stunned" then
			resetGrips(a)
			stunRing(a, b)
		elseif kind == "Parry" then
			onParry(a)
		elseif kind == "Parried" then
			local attackerRoot, parrierRoot = rootOf(a), rootOf(b)
			if attackerRoot and parrierRoot then
				burst(attackerRoot.Position:Lerp(parrierRoot.Position, 0.5) + Vector3.new(0, 1, 0), Color3.fromRGB(255, 230, 120), 40, 30)
				playSound(SOUNDS.Parry, parrierRoot, 0.9, 1.1)
			end
			if a == myCharacter or b == myCharacter then
				Effects.shake(0.35, 0.2)
			end
		elseif kind == "Hit" then
			local target: Model, damage: number, attacker: Model?, attackKind: string = a, b, c, d
			local root = rootOf(target)
			flash(target, Color3.fromRGB(255, 70, 70))
			if root then
				burst(root.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 90, 80), 14, 18)
				playSound(SOUNDS.Hit, root, 0.4, 1.6)
			end
			local color = if attackKind == "Light" then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(255, 200, 70)
			damageNumber(target, damage, color)
			if target == myCharacter or attacker == myCharacter then
				local strength = if attackKind == "Light" then 0.2 else 0.55
				Effects.shake(strength, 0.18)
			end
		elseif kind == "Dodge" or kind == "Dodged" then
			afterimage(a)
		elseif kind == "KO" then
			local root = rootOf(a)
			if root then
				burst(root.Position, Color3.fromRGB(255, 255, 255), 60, 40)
			end
		end
	end)

	-- Camera shake
	RunService:BindToRenderStep("SandoShake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		if now >= shakeUntil then
			shakeStrength = 0
			return
		end
		local camera = workspace.CurrentCamera
		local s = shakeStrength * ((shakeUntil - now) / 0.2)
		camera.CFrame = camera.CFrame * CFrame.Angles(
			math.rad((math.random() - 0.5) * s * 4),
			math.rad((math.random() - 0.5) * s * 4),
			0
		)
	end)
end

return Effects
