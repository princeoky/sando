-- Weapon definitions. Every weapon is data: add an entry here and it shows up
-- in the lobby shop, works in combat and gets a model built automatically.
--
-- Model parts are positioned relative to the grip point (the player's fist).
-- The weapon points along -Z (forward out of the hand).

local Weapons = {}

local STEEL = Color3.fromRGB(205, 210, 220)
local DARK = Color3.fromRGB(28, 26, 30)
local GOLD = Color3.fromRGB(212, 168, 70)
local WOOD = Color3.fromRGB(122, 84, 52)
local RED = Color3.fromRGB(170, 35, 40)

Weapons.List = {
	Katana = {
		id = "Katana",
		displayName = "Katana",
		description = "Balanced and reliable. Everyone starts with one.",
		price = 0,
		order = 1,
		offhand = false,
		damage = { light = { 9, 9, 13 }, heavyMin = 15, heavyMax = 28, ultimate = 35 },
		range = 7.5,
		arc = 70, -- half-angle of the hit cone, in degrees
		lightWindup = 0.16,
		lightRecovery = 0.3,
		comboEndRecovery = 0.55,
		comboReset = 0.9,
		heavyWindup = 0.3,
		heavyRecovery = 0.55,
		maxCharge = 1.2,
		ultRange = 11,
		trailColor = Color3.fromRGB(235, 240, 255),
		parts = {
			{ name = "Handle", size = Vector3.new(0.22, 0.22, 1.1), cf = CFrame.new(0, 0, 0.15), color = DARK, material = Enum.Material.Fabric },
			{ name = "Guard", size = Vector3.new(0.7, 0.12, 0.12), cf = CFrame.new(0, 0, -0.45), color = GOLD, material = Enum.Material.Metal },
			{ name = "Blade", size = Vector3.new(0.06, 0.24, 3.4), cf = CFrame.new(0, 0, -2.2), color = STEEL, material = Enum.Material.Metal, trail = true },
		},
	},

	DualDaggers = {
		id = "DualDaggers",
		displayName = "Dual Daggers",
		description = "Fast four-hit combos, but you have to get close.",
		price = 300,
		order = 2,
		offhand = true,
		damage = { light = { 6, 6, 6, 10 }, heavyMin = 12, heavyMax = 22, ultimate = 32 },
		range = 5.5,
		arc = 75,
		lightWindup = 0.1,
		lightRecovery = 0.2,
		comboEndRecovery = 0.45,
		comboReset = 0.8,
		heavyWindup = 0.24,
		heavyRecovery = 0.45,
		maxCharge = 1.0,
		ultRange = 9,
		trailColor = Color3.fromRGB(150, 255, 190),
		parts = {
			{ name = "Handle", size = Vector3.new(0.2, 0.2, 0.7), cf = CFrame.new(0, 0, 0.1), color = DARK, material = Enum.Material.Fabric },
			{ name = "Guard", size = Vector3.new(0.45, 0.1, 0.1), cf = CFrame.new(0, 0, -0.28), color = GOLD, material = Enum.Material.Metal },
			{ name = "Blade", size = Vector3.new(0.06, 0.2, 1.4), cf = CFrame.new(0, 0, -1.0), color = STEEL, material = Enum.Material.Metal, trail = true },
		},
	},

	BoStaff = {
		id = "BoStaff",
		displayName = "Bo Staff",
		description = "Wide sweeping swings that are hard to dodge.",
		price = 450,
		order = 3,
		offhand = false,
		damage = { light = { 7, 7, 9 }, heavyMin = 13, heavyMax = 24, ultimate = 33 },
		range = 8.5,
		arc = 95,
		lightWindup = 0.15,
		lightRecovery = 0.28,
		comboEndRecovery = 0.5,
		comboReset = 0.9,
		heavyWindup = 0.3,
		heavyRecovery = 0.5,
		maxCharge = 1.2,
		ultRange = 12,
		trailColor = Color3.fromRGB(255, 220, 150),
		parts = {
			{ name = "Handle", size = Vector3.new(0.24, 0.24, 2.4), cf = CFrame.new(0, 0, 0.6), color = WOOD, material = Enum.Material.Wood },
			{ name = "Blade", size = Vector3.new(0.24, 0.24, 2.6), cf = CFrame.new(0, 0, -2.0), color = WOOD, material = Enum.Material.Wood, trail = true },
			{ name = "CapBack", size = Vector3.new(0.3, 0.3, 0.2), cf = CFrame.new(0, 0, 1.85), color = GOLD, material = Enum.Material.Metal },
			{ name = "CapFront", size = Vector3.new(0.3, 0.3, 0.2), cf = CFrame.new(0, 0, -3.35), color = GOLD, material = Enum.Material.Metal },
		},
	},

	Gauntlets = {
		id = "Gauntlets",
		displayName = "Gauntlets",
		description = "The fastest weapon in the game. Tiny range.",
		price = 400,
		order = 4,
		offhand = true,
		damage = { light = { 6, 7, 7, 11 }, heavyMin = 14, heavyMax = 26, ultimate = 34 },
		range = 4.8,
		arc = 70,
		lightWindup = 0.09,
		lightRecovery = 0.18,
		comboEndRecovery = 0.42,
		comboReset = 0.75,
		heavyWindup = 0.22,
		heavyRecovery = 0.42,
		maxCharge = 1.0,
		ultRange = 8,
		trailColor = Color3.fromRGB(255, 120, 90),
		parts = {
			{ name = "Handle", size = Vector3.new(0.5, 0.5, 0.6), cf = CFrame.new(0, 0.2, 0), color = RED, material = Enum.Material.Metal },
			{ name = "Blade", size = Vector3.new(0.56, 0.2, 0.2), cf = CFrame.new(0, 0.05, -0.3), color = GOLD, material = Enum.Material.Metal, trail = true },
		},
	},

	Naginata = {
		id = "Naginata",
		displayName = "Naginata",
		description = "Huge reach. Keep them at the end of your blade.",
		price = 600,
		order = 5,
		offhand = false,
		damage = { light = { 10, 10, 14 }, heavyMin = 17, heavyMax = 30, ultimate = 36 },
		range = 10.5,
		arc = 55,
		lightWindup = 0.22,
		lightRecovery = 0.38,
		comboEndRecovery = 0.65,
		comboReset = 1.0,
		heavyWindup = 0.38,
		heavyRecovery = 0.65,
		maxCharge = 1.4,
		ultRange = 14,
		trailColor = Color3.fromRGB(200, 170, 255),
		parts = {
			{ name = "Handle", size = Vector3.new(0.22, 0.22, 5.2), cf = CFrame.new(0, 0, -1.4), color = RED, material = Enum.Material.Wood },
			{ name = "Collar", size = Vector3.new(0.3, 0.3, 0.25), cf = CFrame.new(0, 0, -4.0), color = GOLD, material = Enum.Material.Metal },
			{ name = "Blade", size = Vector3.new(0.06, 0.3, 2.0), cf = CFrame.new(0, 0.05, -5.1), color = STEEL, material = Enum.Material.Metal, trail = true },
		},
	},

	Warhammer = {
		id = "Warhammer",
		displayName = "Warhammer",
		description = "Slow and brutal. A full charge ends rounds.",
		price = 900,
		order = 6,
		offhand = false,
		damage = { light = { 13, 17 }, heavyMin = 22, heavyMax = 40, ultimate = 42 },
		range = 7.5,
		arc = 80,
		lightWindup = 0.32,
		lightRecovery = 0.5,
		comboEndRecovery = 0.8,
		comboReset = 1.1,
		heavyWindup = 0.5,
		heavyRecovery = 0.8,
		maxCharge = 1.6,
		ultRange = 11,
		trailColor = Color3.fromRGB(255, 170, 60),
		parts = {
			{ name = "Handle", size = Vector3.new(0.26, 0.26, 3.6), cf = CFrame.new(0, 0, -1.0), color = WOOD, material = Enum.Material.Wood },
			{ name = "Blade", size = Vector3.new(1.7, 0.9, 0.9), cf = CFrame.new(0, 0, -3.1), color = Color3.fromRGB(90, 92, 100), material = Enum.Material.Metal, trail = true },
			{ name = "Band", size = Vector3.new(0.4, 0.4, 0.3), cf = CFrame.new(0, 0, -2.5), color = GOLD, material = Enum.Material.Metal },
		},
	},
}

Weapons.Default = "Katana"

function Weapons.get(id: string)
	return Weapons.List[id] or Weapons.List[Weapons.Default]
end

function Weapons.sorted()
	local list = {}
	for _, weapon in Weapons.List do
		table.insert(list, weapon)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

return Weapons
