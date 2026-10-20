-- Server-authoritative melee combat: light combos, charged heavies, parries,
-- dodges and ultimates. Clients only send inputs; the server owns timing,
-- hit detection, damage and the ultimate meter.
--
-- A "fighter" is either a Player or a practice Bot. Both expose .Character,
-- and bots drive the same actions through CombatService.perform.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatAction = Remotes.CombatAction :: RemoteEvent
local CombatFeedback = Remotes.CombatFeedback :: RemoteEvent

local CombatService = {}

-- Fires (attackerCharacter, kind, windup) whenever a swing starts. Bots use
-- it to react to incoming attacks.
local swungEvent = Instance.new("BindableEvent")
CombatService.Swung = swungEvent.Event

type Fighter = any -- Player or Bot

type State = {
	busyUntil: number,
	stunUntil: number,
	iframeUntil: number,
	parryStart: number,
	parryActiveUntil: number,
	parryReadyAt: number,
	dodgeReadyAt: number,
	combo: number,
	lastLight: number,
	charging: boolean,
	chargeStart: number,
	token: number,
	ult: number,
}

type Attack = {
	kind: string,
	damage: number,
	range: number,
	arc: number,
	parryable: boolean,
}

local states: { [Fighter]: State } = {}
local characterOwner: { [Model]: Fighter } = setmetatable({}, { __mode = "k" }) :: any

-- Wired up by the bootstrap so this module doesn't depend on MatchService.
local getTargets: (Fighter) -> { Model } = function()
	return {}
end
local canFight: (Fighter) -> boolean = function()
	return true
end

local function isPlayer(fighter: Fighter): boolean
	return typeof(fighter) == "Instance" and fighter:IsA("Player")
end

local function newState(ult: number?): State
	return {
		busyUntil = 0,
		stunUntil = 0,
		iframeUntil = 0,
		parryStart = -math.huge,
		parryActiveUntil = 0,
		parryReadyAt = 0,
		dodgeReadyAt = 0,
		combo = 0,
		lastLight = 0,
		charging = false,
		chargeStart = 0,
		token = 0,
		ult = ult or 0,
	}
end

local function broadcast(kind: string, ...)
	CombatFeedback:FireAllClients(kind, ...)
end

local function aliveCharacter(fighter: Fighter): (Model?, Humanoid?, BasePart?)
	local character = fighter.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return character, humanoid, root :: BasePart
end

local function weaponOf(fighter: Fighter)
	local character = fighter.Character
	return Weapons.get(character and character:GetAttribute("Weapon") or Weapons.Default)
end

local function setUlt(fighter: Fighter, value: number)
	local state = states[fighter]
	if not state then
		return
	end
	state.ult = math.clamp(value, 0, Config.UltMax)
	if isPlayer(fighter) then
		fighter:SetAttribute("Ultimate", state.ult)
	end
end

local function addUlt(fighter: Fighter, amount: number)
	local state = states[fighter]
	if state then
		setUlt(fighter, state.ult + amount)
	end
end

local function updateSpeed(fighter: Fighter)
	local state = states[fighter]
	local _, humanoid = aliveCharacter(fighter)
	if not state or not humanoid then
		return
	end
	local now = os.clock()
	local speed = Config.WalkSpeed
	if now < state.stunUntil then
		speed = Config.StunWalkSpeed
	elseif state.charging then
		speed = Config.ChargeWalkSpeed
	elseif now < state.busyUntil then
		speed = Config.AttackWalkSpeed
	end
	humanoid.WalkSpeed = speed
end

local function updateSpeedAt(fighter: Fighter, at: number)
	task.delay(math.max(0, at - os.clock()) + 0.01, updateSpeed, fighter)
end

-- Short horizontal shove. Players move their own character (the client owns
-- its physics); bots are moved here on the server.
local function shove(fighter: Fighter, velocity: Vector3, duration: number)
	if isPlayer(fighter) then
		CombatFeedback:FireClient(fighter, "Knockback", velocity, duration)
		return
	end
	local _, _, root = aliveCharacter(fighter)
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
	task.delay(duration, function()
		mover:Destroy()
		attachment:Destroy()
	end)
end

local function stun(fighter: Fighter, duration: number)
	local state = states[fighter]
	if not state then
		return
	end
	local now = os.clock()
	local wasCharging = state.charging
	state.token += 1 -- cancel any pending windup
	state.charging = false
	state.stunUntil = math.max(state.stunUntil, now + duration)
	state.busyUntil = math.max(state.busyUntil, state.stunUntil)
	state.parryActiveUntil = 0

	local character = fighter.Character
	if character then
		character:SetAttribute("Stunned", true)
		if wasCharging then
			broadcast("Cancel", character)
		end
		broadcast("Stunned", character, duration)
	end
	updateSpeed(fighter)

	local stunUntil = state.stunUntil
	task.delay(duration + 0.01, function()
		if states[fighter] == state and state.stunUntil == stunUntil then
			if character and character.Parent then
				character:SetAttribute("Stunned", false)
			end
			updateSpeed(fighter)
		end
	end)
end

local function inCone(origin: BasePart, target: BasePart, range: number, arc: number): boolean
	local offset = target.Position - origin.Position
	if math.abs(offset.Y) > 6 then
		return false
	end
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	if distance > range + 1.5 then
		return false
	end
	if distance < 2.5 then
		return true
	end
	local look = origin.CFrame.LookVector
	local lookFlat = Vector3.new(look.X, 0, look.Z)
	if lookFlat.Magnitude < 1e-3 then
		return false
	end
	return lookFlat.Unit:Dot(flat.Unit) >= math.cos(math.rad(arc))
end

local function damageDummy(model: Model, humanoid: Humanoid, damage: number)
	if humanoid.Health - damage <= 0 then
		humanoid.Health = humanoid.MaxHealth
	else
		humanoid.Health -= damage
	end
	local stamp = os.clock()
	model:SetAttribute("LastHit", stamp)
	task.delay(4, function()
		if model:GetAttribute("LastHit") == stamp then
			humanoid.Health = humanoid.MaxHealth
		end
	end)
end

-- Returns true if the attack was parried (which ends the swing).
local function applyHit(attacker: Fighter, attackerRoot: BasePart, target: Model, attack: Attack): boolean
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not targetRoot then
		return false
	end
	local now = os.clock()
	local victim = characterOwner[target]
	local vs = victim and states[victim]

	if vs then
		if now < vs.iframeUntil then
			broadcast("Dodged", target)
			return false
		end
		if attack.parryable and now >= vs.parryStart and now <= vs.parryActiveUntil then
			vs.parryActiveUntil = 0
			vs.busyUntil = now -- free to punish right away
			addUlt(victim, Config.UltGainParry)
			updateSpeed(victim)
			stun(attacker, Config.ParryStun)
			broadcast("Parried", attacker.Character, target)
			return true
		end
	end

	local damage = attack.damage
	if vs then
		humanoid.Health = math.max(0, humanoid.Health - damage)
		addUlt(victim, damage * Config.UltGainTaken)
		if humanoid.Health > 0 then
			stun(victim, Config.HitStun)
			local push = targetRoot.Position - attackerRoot.Position
			push = Vector3.new(push.X, 0, push.Z)
			if push.Magnitude > 1e-3 then
				local strength = if attack.kind == "Light" then Config.Knockback else Config.Knockback * 1.8
				shove(victim, push.Unit * strength, 0.12)
			end
		end
	else
		damageDummy(target, humanoid, damage)
	end

	addUlt(attacker, damage * Config.UltGainDealt)
	broadcast("Hit", target, damage, attacker.Character, attack.kind)
	return false
end

local function resolve(fighter: Fighter, token: number, attack: Attack)
	local state = states[fighter]
	if not state or state.token ~= token then
		return
	end
	local _, _, root = aliveCharacter(fighter)
	if not root or not canFight(fighter) then
		return
	end
	for _, target in getTargets(fighter) do
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot and inCone(root, targetRoot, attack.range, attack.arc) then
			if applyHit(fighter, root, target, attack) then
				break
			end
		end
	end
end

local function schedule(fighter: Fighter, state: State, windup: number, attack: Attack)
	state.token += 1
	local token = state.token
	task.delay(windup, resolve, fighter, token, attack)
end

local function announceSwing(character: Model, kind: string, index: number, windup: number)
	broadcast("Swing", character, kind, index, windup)
	swungEvent:Fire(character, kind, windup)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local actions = {}

function actions.Light(fighter: Fighter, state: State, character: Model, now: number)
	if now < state.busyUntil or state.charging then
		return
	end
	local weapon = weaponOf(fighter)
	local combo = weapon.damage.light
	if now - state.lastLight > weapon.comboReset or state.combo >= #combo then
		state.combo = 1
	else
		state.combo += 1
	end
	state.lastLight = now
	local index = state.combo
	local isLast = index == #combo
	state.busyUntil = now + weapon.lightWindup + (if isLast then weapon.comboEndRecovery else weapon.lightRecovery)

	announceSwing(character, "Light", index, weapon.lightWindup)
	schedule(fighter, state, weapon.lightWindup, {
		kind = "Light",
		damage = combo[index],
		range = weapon.range,
		arc = weapon.arc,
		parryable = true,
	})
	updateSpeed(fighter)
	updateSpeedAt(fighter, state.busyUntil)
end

function actions.HeavyStart(fighter: Fighter, state: State, character: Model, now: number)
	if now < state.busyUntil or state.charging then
		return
	end
	local weapon = weaponOf(fighter)
	state.charging = true
	state.chargeStart = now
	state.token += 1
	local token = state.token
	broadcast("ChargeStart", character, weapon.maxCharge)
	updateSpeed(fighter)

	-- Don't let anyone hold a charge forever
	task.delay(weapon.maxCharge + 1, function()
		if states[fighter] == state and state.token == token and state.charging then
			actions.HeavyRelease(fighter, state, character, os.clock())
		end
	end)
end

function actions.HeavyRelease(fighter: Fighter, state: State, character: Model, now: number)
	if not state.charging then
		return
	end
	local weapon = weaponOf(fighter)
	state.charging = false
	local charge = math.clamp((now - state.chargeStart) / weapon.maxCharge, 0, 1)
	local damage = weapon.damage.heavyMin + (weapon.damage.heavyMax - weapon.damage.heavyMin) * charge
	state.busyUntil = now + weapon.heavyWindup + weapon.heavyRecovery
	state.combo = 0

	announceSwing(character, "Heavy", charge, weapon.heavyWindup)
	schedule(fighter, state, weapon.heavyWindup, {
		kind = "Heavy",
		damage = math.floor(damage + 0.5),
		range = weapon.range + 0.5,
		arc = weapon.arc,
		parryable = charge < Config.HeavyUnparryableAt,
	})
	updateSpeed(fighter)
	updateSpeedAt(fighter, state.busyUntil)
end

function actions.Parry(fighter: Fighter, state: State, character: Model, now: number)
	if now < state.busyUntil or state.charging or now < state.parryReadyAt then
		return
	end
	state.parryStart = now
	state.parryActiveUntil = now + Config.ParryWindow
	state.parryReadyAt = now + Config.ParryCooldown
	state.busyUntil = now + Config.ParryWindow + Config.ParryWhiffRecovery
	broadcast("Parry", character)
	updateSpeed(fighter)
	updateSpeedAt(fighter, state.busyUntil)
end

function actions.Dodge(fighter: Fighter, state: State, character: Model, now: number, direction: Vector3?)
	if now < state.dodgeReadyAt then
		return
	end
	if state.charging then
		state.charging = false
		broadcast("Cancel", character)
	end
	state.token += 1 -- dodging cancels your own windup
	state.dodgeReadyAt = now + Config.DodgeCooldown
	state.iframeUntil = now + Config.DodgeIFrames
	state.busyUntil = math.max(state.busyUntil, now + Config.DodgeDuration)
	state.parryActiveUntil = 0
	broadcast("Dodge", character)
	if not isPlayer(fighter) and direction and direction.Magnitude > 0.1 then
		shove(fighter, direction.Unit * Config.DodgeSpeed, Config.DodgeDuration)
	end
	updateSpeed(fighter)
	updateSpeedAt(fighter, state.busyUntil)
end

function actions.Ultimate(fighter: Fighter, state: State, character: Model, now: number)
	if state.ult < Config.UltMax or now < state.busyUntil or state.charging then
		return
	end
	local weapon = weaponOf(fighter)
	local windup = 0.55
	setUlt(fighter, 0)
	state.busyUntil = now + windup + 0.6
	announceSwing(character, "Ultimate", 0, windup)
	schedule(fighter, state, windup, {
		kind = "Ultimate",
		damage = weapon.damage.ultimate,
		range = weapon.ultRange,
		arc = 120,
		parryable = false,
	})
	updateSpeed(fighter)
	updateSpeedAt(fighter, state.busyUntil)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function CombatService.setResolvers(targets: (Fighter) -> { Model }, fight: (Fighter) -> boolean)
	getTargets = targets
	canFight = fight
end

-- Fresh combat state for a fighter's current character. Keeps the ultimate
-- meter unless clearUlt is set (the meter carries between rounds).
function CombatService.reset(fighter: Fighter, clearUlt: boolean?)
	local previous = states[fighter]
	local ult = if clearUlt or not previous then 0 else previous.ult
	states[fighter] = newState(ult)
	if fighter.Character then
		characterOwner[fighter.Character] = fighter
	end
	if isPlayer(fighter) then
		fighter:SetAttribute("Ultimate", ult)
	end
end

function CombatService.remove(fighter: Fighter)
	states[fighter] = nil
end

function CombatService.getUlt(fighter: Fighter): number
	local state = states[fighter]
	return state and state.ult or 0
end

function CombatService.isBusy(fighter: Fighter): boolean
	local state = states[fighter]
	if not state then
		return true
	end
	local now = os.clock()
	return state.charging or now < state.busyUntil or now < state.stunUntil
end

function CombatService.isCharging(fighter: Fighter): boolean
	local state = states[fighter]
	return state ~= nil and state.charging
end

-- Runs one action for a fighter. Returns nothing; invalid actions are ignored.
function CombatService.perform(fighter: Fighter, action: string, arg: any?)
	local handler = actions[action]
	local state = states[fighter]
	if not handler or not state then
		return
	end
	local character = aliveCharacter(fighter)
	if not character or not canFight(fighter) then
		return
	end
	local now = os.clock()
	if now < state.stunUntil then
		return
	end
	handler(fighter, state, character, now, arg)
end

function CombatService.start()
	CombatAction.OnServerEvent:Connect(function(player: Player, action: unknown)
		if type(action) == "string" then
			-- Players move themselves when dodging, so no direction is passed
			CombatService.perform(player, action)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return CombatService
