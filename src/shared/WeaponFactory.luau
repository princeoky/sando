-- Builds weapon models from the part lists in Weapons and welds them to a
-- character's hands. Shared so the lobby shop and characters use the same code.

local Weapons = require(script.Parent.Weapons)

local WeaponFactory = {}

local MAIN_NAME = "SandoWeapon"
local OFFHAND_NAME = "SandoWeaponOffhand"
WeaponFactory.MainName = MAIN_NAME
WeaponFactory.OffhandName = OFFHAND_NAME

-- Builds an unattached model. Its PrimaryPart ("Handle") sits so that the
-- model's pivot is the grip point.
function WeaponFactory.build(weaponId: string): Model
	local weapon = Weapons.get(weaponId)
	local model = Instance.new("Model")
	model.Name = weapon.id

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.1, 0.1, 0.1)
	grip.Transparency = 1
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	grip.Massless = true
	grip.CFrame = CFrame.new()
	grip.Parent = model
	model.PrimaryPart = grip

	for _, spec in weapon.parts do
		local part = Instance.new("Part")
		part.Name = spec.name
		part.Size = spec.size
		part.CFrame = spec.cf
		part.Color = spec.color
		part.Material = spec.material
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = grip
		weld.Part1 = part
		weld.Parent = part

		if spec.trail then
			local half = spec.size.Z / 2
			local a0 = Instance.new("Attachment")
			a0.Name = "TrailStart"
			a0.Position = Vector3.new(0, 0, half * 0.6)
			a0.Parent = part
			local a1 = Instance.new("Attachment")
			a1.Name = "TrailEnd"
			a1.Position = Vector3.new(0, 0, -half)
			a1.Parent = part

			local trail = Instance.new("Trail")
			trail.Name = "SwingTrail"
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(weapon.trailColor)
			trail.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			trail.Lifetime = 0.18
			trail.LightEmission = 0.6
			trail.FaceCamera = true
			trail.Enabled = false
			trail.Parent = part

			local glow = Instance.new("PointLight")
			glow.Name = "ChargeGlow"
			glow.Color = weapon.trailColor
			glow.Range = 10
			glow.Brightness = 3
			glow.Enabled = false
			glow.Parent = part
		end
	end

	return model
end

local function findHand(character: Model, side: string): BasePart?
	local hand = character:FindFirstChild(side .. "Hand") -- R15
	if hand and hand:IsA("BasePart") then
		return hand
	end
	local arm = character:FindFirstChild(side .. " Arm") -- R6
	if arm and arm:IsA("BasePart") then
		return arm
	end
	return nil
end

local function attachTo(character: Model, model: Model, hand: BasePart, name: string)
	model.Name = name
	local grip = model.PrimaryPart :: BasePart
	local base = CFrame.new(0, -hand.Size.Y * 0.4, 0)

	model:PivotTo(hand.CFrame * base)
	local weld = Instance.new("Weld")
	weld.Name = "GripWeld"
	weld.Part0 = hand
	weld.Part1 = grip
	weld.C0 = base
	weld.Parent = grip
	grip:SetAttribute("GripBase", base)

	model.Parent = character
end

function WeaponFactory.detach(character: Model)
	for _, name in { MAIN_NAME, OFFHAND_NAME } do
		local existing = character:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
end

function WeaponFactory.attach(character: Model, weaponId: string)
	WeaponFactory.detach(character)
	local weapon = Weapons.get(weaponId)

	local right = findHand(character, "Right")
	if right then
		attachTo(character, WeaponFactory.build(weapon.id), right, MAIN_NAME)
	end
	if weapon.offhand then
		local left = findHand(character, "Left")
		if left then
			attachTo(character, WeaponFactory.build(weapon.id), left, OFFHAND_NAME)
		end
	end
	character:SetAttribute("Weapon", weapon.id)
end

return WeaponFactory
