-- A practice opponent. It spawns a real R15 character, chases its target,
-- throws combos and heavies, and sometimes parries or dodges incoming swings.
-- It fights through CombatService.perform, so it follows the same rules as
-- players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local WeaponFactory = require(Shared.WeaponFactory)

local CombatService = require(script.Parent.CombatService)

local Bot = {}
Bot.__index = Bot

local NAMES = { "Ronin", "Kage", "Tetsu", "Hayate", "Raiden", "Sora" }

export type Bot = typeof(setmetatable({} :: {
	isBot: boolean,
	Name: string,
	DisplayName: string,
	Character: Model?,
	weaponId: string,
	active: boolean,
	getTargets: (any) -> { Model },
	canFight: (any) -> boolean,
	connection: RBXScriptConnection?,
}, Bot))

function Bot.new(getTargets: (any) -> { Model }, canFight: (any) -> boolean): Bot
	local name = NAMES[math.random(1, #NAMES)] .. " (Bot)"
	local weapons = Weapons.sorted()
	local self = setmetatable({
		isBot = true,
		Name = name,
		DisplayName = name,
		Character = nil,
		weaponId = weapons[math.random(1, #weapons)].id,
		active = true,
		getTargets = getTargets,
		canFight = canFight,
		connection = nil,
	}, Bot)

	self.connection = CombatService.Swung:Connect(function(attacker: Model, kind: string, windup: number)
		self:react(attacker, kind, windup)
	end)
	task.spawn(function()
		self:think()
	end)
	return self
end

local function buildCharacter(name: string): Model
	local ok, model = pcall(function()
		local description = Instance.new("HumanoidDescription")
		local skin = Color3.fromRGB(234, 184, 146)
		description.HeadColor = skin
		description.LeftArmColor = skin
		description.RightArmColor = skin
		description.TorsoColor = Color3.fromRGB(40, 36, 44)
		description.LeftLegColor = Color3.fromRGB(30, 28, 34)
		description.RightLegColor = Color3.fromRGB(30, 28, 34)
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		model.Name = name
		return model
	end

	-- Fallback: a simple welded body if the avatar service is unavailable
	warn("[sando] Couldn't build an R15 bot, using a simple body:", model)
	local rig = Instance.new("Model")
	rig.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = rig
	local function limb(partName: string, size: Vector3, offset: CFrame, color: Color3)
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = size
		p.Color = color
		p.CFrame = root.CFrame * offset
		p.CanCollide = false
		p.Parent = rig
		local weld = Instance.new("Weld")
		weld.Part0 = root
		weld.Part1 = p
		weld.C0 = offset
		weld.Parent = p
	end
	limb("Torso", Vector3.new(2, 2, 1), CFrame.new(), Color3.fromRGB(40, 36, 44))
	limb("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.6, 0), Color3.fromRGB(234, 184, 146))
	limb("Right Arm", Vector3.new(1, 2, 1), CFrame.new(1.5, 0, 0), Color3.fromRGB(234, 184, 146))
	limb("Left Arm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 0, 0), Color3.fromRGB(234, 184, 146))
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- uses HipHeight with no legs
	humanoid.HipHeight = 2
	humanoid.Parent = rig
	rig.PrimaryPart = root
	return rig
end

function Bot:spawn(at: CFrame)
	if self.Character then
		self.Character:Destroy()
	end
	local character = buildCharacter(self.Name)
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.MaxHealth = Config.MaxHealth
	humanoid.Health = Config.MaxHealth
	humanoid.WalkSpeed = Config.WalkSpeed
	humanoid.AutoRotate = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	character:PivotTo(at)
	character.Parent = workspace

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	WeaponFactory.attach(character, self.weaponId)

	self.Character = character
	CombatService.reset(self)
	return character
end

function Bot:destroy()
	self.active = false
	if self.connection then
		self.connection:Disconnect()
	end
	if self.Character then
		self.Character:Destroy()
		self.Character = nil
	end
	CombatService.remove(self)
end

local function parts(character: Model?): (Humanoid?, BasePart?)
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return humanoid, root
end

-- Defend against a swing aimed at us.
function Bot:react(attacker: Model, kind: string, windup: number)
	if not self.active or attacker == self.Character or not self.canFight(self) then
		return
	end
	local _, root = parts(self.Character)
	local attackerRoot = attacker:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not attackerRoot then
		return
	end
	if not table.find(self.getTargets(self), attacker) then
		return -- not someone we're fighting
	end
	local weapon = Weapons.get(attacker:GetAttribute("Weapon") or Weapons.Default)
	if (attackerRoot.Position - root.Position).Magnitude > weapon.range + 4 then
		return
	end

	local roll = math.random()
	local reaction = math.random() * 0.08
	if kind ~= "Ultimate" and roll < Config.BotParryChance then
		-- Time the parry window over the moment the hit lands
		task.delay(math.max(0, windup - Config.ParryWindow * 0.6 + reaction), function()
			CombatService.perform(self, "Parry")
		end)
	elseif roll < Config.BotParryChance + Config.BotDodgeChance or kind == "Ultimate" then
		task.delay(math.max(0, windup - 0.15 + reaction), function()
			local _, r = parts(self.Character)
			if r then
				local away = r.Position - attackerRoot.Position
				local side = r.CFrame.RightVector * (if math.random() < 0.5 then 1 else -1)
				CombatService.perform(self, "Dodge", Vector3.new(away.X, 0, away.Z).Unit + side)
			end
		end)
	end
end

-- Main loop: chase, face and attack the closest enemy.
function Bot:think()
	local nextAttack = 0
	local strafeUntil = 0
	local strafeDir = 1
	while self.active do
		task.wait(0.1)
		local humanoid, root = parts(self.Character)
		if not humanoid or not root then
			continue
		end
		if not self.canFight(self) then
			humanoid:Move(Vector3.zero)
			continue
		end

		local closest: BasePart? = nil
		local best = math.huge
		for _, target in self.getTargets(self) do
			local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if targetRoot then
				local d = (targetRoot.Position - root.Position).Magnitude
				if d < best then
					best, closest = d, targetRoot
				end
			end
		end
		if not closest then
			humanoid:Move(Vector3.zero)
			continue
		end

		local weapon = Weapons.get(self.weaponId)
		local flatTarget = Vector3.new(closest.Position.X, root.Position.Y, closest.Position.Z)
		if (flatTarget - root.Position).Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, flatTarget)
		end

		local now = os.clock()
		local toTarget = (flatTarget - root.Position)
		if best > weapon.range * 0.8 then
			humanoid:Move(toTarget.Unit)
		elseif now < strafeUntil then
			humanoid:Move(root.CFrame.RightVector * strafeDir)
		else
			humanoid:Move(Vector3.zero)
			if math.random() < 0.05 then
				strafeUntil = now + 0.6
				strafeDir = if math.random() < 0.5 then 1 else -1
			end
		end

		if best <= weapon.range + 0.5 and now >= nextAttack and not CombatService.isBusy(self) then
			if CombatService.getUlt(self) >= Config.UltMax then
				CombatService.perform(self, "Ultimate")
			elseif math.random() < 0.18 then
				CombatService.perform(self, "HeavyStart")
				local hold = math.random() * weapon.maxCharge
				task.delay(hold, function()
					if CombatService.isCharging(self) then
						CombatService.perform(self, "HeavyRelease")
					end
				end)
			else
				CombatService.perform(self, "Light")
			end
			nextAttack = now + 0.1 + math.random() * 0.45
		end
	end
end

return Bot
