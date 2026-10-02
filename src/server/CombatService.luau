-- Server-authoritative melee combat: light combos, charged heavies, parries,
-- dodges and ultimates. Clients only send inputs; the server owns timing,
-- hit detection, damage and the ultimate meter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatAction = Remotes.CombatAction :: RemoteEvent
local CombatFeedback = Remotes.CombatFeedback :: RemoteEvent

local CombatService = {}

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

local states: { [Player]: State } = {}

-- Wired up by the bootstrap so this module doesn't depend on MatchService.
local getTargets: (Player) -> { Model } = function()
	return {}
end
local canFight: (Player) -> boolean = function()
	return true
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

local function aliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
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

local function weaponOf(player: Player)
	local character = player.Character
	return Weapons.get(character and character:GetAttribute("Weapon") or Weapons.Default)
end

local function setUlt(player: Player, value: number)
	local state = states[player]
	if not state then
		return
	end
	state.ult = math.clamp(value, 0, Config.UltMax)
	player:SetAttribute("Ultimate", state.ult)
end

local function addUlt(player: Player, amount: number)
	local state = states[player]
	if state then
		setUlt(player, state.ult + amount)
	end
end

local function updateSpeed(player: Player)
	local state = states[player]
	local _, humanoid = aliveCharacter(player)
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

local function updateSpeedAt(player: Player, at: number)
	task.delay(math.max(0, at - os.clock()) + 0.01, updateSpeed, player)
end

local function stun(player: Player, duration: number)
	local state = states[player]
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

	local character = player.Character
	if character then
		character:SetAttribute("Stunned", true)
		if wasCharging then
			broadcast("Cancel", character)
		end
		broadcast("Stunned", character, duration)
	end
	updateSpeed(player)

	local stunUntil = state.stunUntil
	task.delay(duration + 0.01, function()
		if states[player] == state and state.stunUntil == stunUntil then
			if player.Character then
				player.Character:SetAttribute("Stunned", false)
			end
			updateSpeed(player)
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
local function applyHit(attacker: Player, attackerRoot: BasePart, target: Model, attack: Attack): boolean
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not targetRoot then
		return false
	end
	local now = os.clock()
	local victim = Players:GetPlayerFromCharacter(target)

	if victim then
		local vs = states[victim]
		if vs and now < vs.iframeUntil then
			broadcast("Dodged", target)
			return false
		end
		if vs and attack.parryable and now >= vs.parryStart and now <= vs.parryActiveUntil then
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
	if victim then
		humanoid.Health = math.max(0, humanoid.Health - damage)
		addUlt(victim, damage * Config.UltGainTaken)
		if humanoid.Health > 0 then
			stun(victim, Config.HitStun)
			local push = targetRoot.Position - attackerRoot.Position
			push = Vector3.new(push.X, 0, push.Z)
			if push.Magnitude > 1e-3 then
				local strength = if attack.kind == "Light" then Config.Knockback else Config.Knockback * 1.8
				CombatFeedback:FireClient(victim, "Knockback", push.Unit * strength)
			end
		end
	else
		damageDummy(target, humanoid, damage)
	end

	addUlt(attacker, damage * Config.UltGainDealt)
	broadcast("Hit", target, damage, attacker.Character, attack.kind)
	return false
end

local function resolve(player: Player, token: number, attack: Attack)
	local state = states[player]
	if not state or state.token ~= token then
		return
	end
	local _, _, root = aliveCharacter(player)
	if not root or not canFight(player) then
		return
	end
	for _, target in getTargets(player) do
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot and inCone(root, targetRoot, attack.range, attack.arc) then
			if applyHit(player, root, target, attack) then
				break
			end
		end
	end
end

local function schedule(player: Player, state: State, windup: number, attack: Attack)
	state.token += 1
	local token = state.token
	task.delay(windup, resolve, player, token, attack)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local actions = {}

function actions.Light(player: Player, state: State, character: Model, now: number)
	if now < state.busyUntil or state.charging then
		return
	end
	local weapon = weaponOf(player)
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

	broadcast("Swing", character, "Light", index, weapon.lightWindup)
	schedule(player, state, weapon.lightWindup, {
		kind = "Light",
		damage = combo[index],
		range = weapon.range,
		arc = weapon.arc,
		parryable = true,
	})
	updateSpeed(player)
	updateSpeedAt(player, state.busyUntil)
end

function actions.HeavyStart(player: Player, state: State, character: Model, now: number)
	if now < state.busyUntil or state.charging then
		return
	end
	local weapon = weaponOf(player)
	state.charging = true
	state.chargeStart = now
	state.token += 1
	local token = state.token
	broadcast("ChargeStart", character, weapon.maxCharge)
	updateSpeed(player)

	-- Don't let anyone hold a charge forever
	task.delay(weapon.maxCharge + 1, function()
		if states[player] == state and state.token == token and state.charging then
			actions.HeavyRelease(player, state, character, os.clock())
		end
	end)
end

function actions.HeavyRelease(player: Player, state: State, character: Model, now: number)
	if not state.charging then
		return
	end
	local weapon = weaponOf(player)
	state.charging = false
	local charge = math.clamp((now - state.chargeStart) / weapon.maxCharge, 0, 1)
	local damage = weapon.damage.heavyMin + (weapon.damage.heavyMax - weapon.damage.heavyMin) * charge
	state.busyUntil = now + weapon.heavyWindup + weapon.heavyRecovery
	state.combo = 0

	broadcast("Swing", character, "Heavy", charge, weapon.heavyWindup)
	schedule(player, state, weapon.heavyWindup, {
		kind = "Heavy",
		damage = math.floor(damage + 0.5),
		range = weapon.range + 0.5,
		arc = weapon.arc,
		parryable = charge < Config.HeavyUnparryableAt,
	})
	updateSpeed(player)
	updateSpeedAt(player, state.busyUntil)
end

function actions.Parry(player: Player, state: State, character: Model, now: number)
	if now < state.busyUntil or state.charging or now < state.parryReadyAt then
		return
	end
	state.parryStart = now
	state.parryActiveUntil = now + Config.ParryWindow
	state.parryReadyAt = now + Config.ParryCooldown
	state.busyUntil = now + Config.ParryWindow + Config.ParryWhiffRecovery
	broadcast("Parry", character)
	updateSpeed(player)
	updateSpeedAt(player, state.busyUntil)
end

function actions.Dodge(player: Player, state: State, character: Model, now: number)
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
	updateSpeed(player)
	updateSpeedAt(player, state.busyUntil)
end

function actions.Ultimate(player: Player, state: State, character: Model, now: number)
	if state.ult < Config.UltMax or now < state.busyUntil or state.charging then
		return
	end
	local weapon = weaponOf(player)
	local windup = 0.55
	setUlt(player, 0)
	state.busyUntil = now + windup + 0.6
	broadcast("Swing", character, "Ultimate", 0, windup)
	schedule(player, state, windup, {
		kind = "Ultimate",
		damage = weapon.damage.ultimate,
		range = weapon.ultRange,
		arc = 120,
		parryable = false,
	})
	updateSpeed(player)
	updateSpeedAt(player, state.busyUntil)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function CombatService.setResolvers(targets: (Player) -> { Model }, fight: (Player) -> boolean)
	getTargets = targets
	canFight = fight
end

-- Fresh combat state for a new character. Keeps the ultimate meter unless
-- clearUlt is set (the meter carries between rounds of a match).
function CombatService.reset(player: Player, clearUlt: boolean?)
	local previous = states[player]
	local ult = if clearUlt or not previous then 0 else previous.ult
	states[player] = newState(ult)
	player:SetAttribute("Ultimate", ult)
end

function CombatService.remove(player: Player)
	states[player] = nil
end

function CombatService.start()
	CombatAction.OnServerEvent:Connect(function(player: Player, action: unknown)
		if type(action) ~= "string" then
			return
		end
		local handler = actions[action]
		local state = states[player]
		if not handler or not state then
			return
		end
		local character = aliveCharacter(player)
		if not character or not canFight(player) then
			return
		end
		local now = os.clock()
		if now < state.stunUntil then
			return
		end
		handler(player, state, character, now)
	end)
end

return CombatService
