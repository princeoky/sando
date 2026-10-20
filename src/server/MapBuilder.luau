-- Builds the whole map at server start: lighting, the lobby (spawn, queue pads,
-- weapon shop, training dummies) and a pool of themed duel arenas.
-- Everything is made from plain parts so it works with no Studio assets.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local WeaponFactory = require(Shared.WeaponFactory)

local MapBuilder = {}

local ARENA_ORIGIN_X = 700
local ARENA_SPACING = 450

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function billboard(adornee: BasePart, text: string, color: Color3, offsetY: number, size: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(260, size or 60)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	return label
end

-- Lays a cylinder flat on the ground (cylinders run along the X axis).
local function disc(props, position: Vector3, diameter: number, height: number): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return part(props)
end

-- Stands a cylinder upright.
local function pole(props, base: Vector3, diameter: number, height: number): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	return part(props)
end

---------------------------------------------------------------------------
-- Props
---------------------------------------------------------------------------

local function cherryTree(parent: Instance, base: Vector3, rng: Random, blossom: Color3?)
	local model = Instance.new("Model")
	model.Name = "CherryTree"
	local height = rng:NextNumber(9, 14)
	pole({ Name = "Trunk", Color = Color3.fromRGB(86, 60, 48), Material = Enum.Material.Wood, Parent = model }, base, 1.6, height)
	local leaves = blossom or Color3.fromRGB(255, 176, 205)
	for _ = 1, 5 do
		local offset = Vector3.new(rng:NextNumber(-3.5, 3.5), height + rng:NextNumber(-1, 2.5), rng:NextNumber(-3.5, 3.5))
		local d = rng:NextNumber(5, 8)
		part({
			Name = "Blossom",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(d, d, d),
			CFrame = CFrame.new(base + offset),
			Color = leaves:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.25)),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = model,
		})
	end
	model.Parent = parent
end

local function pineTree(parent: Instance, base: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "PineTree"
	local height = rng:NextNumber(12, 18)
	pole({ Name = "Trunk", Color = Color3.fromRGB(80, 58, 44), Material = Enum.Material.Wood, Parent = model }, base, 1.4, height * 0.4)
	local layers = 4
	for i = 1, layers do
		local w = 9 - i * 1.8
		local y = height * 0.3 + (i - 1) * (height * 0.65 / layers)
		part({
			Name = "Needles",
			Size = Vector3.new(w, height * 0.22, w),
			CFrame = CFrame.new(base + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(45 * i), 0),
			Color = Color3.fromRGB(38, 74, 56),
			Material = Enum.Material.Grass,
			Parent = model,
		})
		part({
			Name = "Snow",
			Size = Vector3.new(w * 0.8, 0.4, w * 0.8),
			CFrame = CFrame.new(base + Vector3.new(0, y + height * 0.11, 0)) * CFrame.Angles(0, math.rad(45 * i), 0),
			Color = Color3.fromRGB(245, 250, 255),
			Material = Enum.Material.Snow,
			CanCollide = false,
			Parent = model,
		})
	end
	model.Parent = parent
end

local function stoneLantern(parent: Instance, base: Vector3, lightColor: Color3)
	local model = Instance.new("Model")
	model.Name = "StoneLantern"
	local stone = Color3.fromRGB(150, 148, 140)
	part({ Name = "Base", Size = Vector3.new(2.4, 0.8, 2.4), CFrame = CFrame.new(base + Vector3.new(0, 0.4, 0)), Color = stone, Material = Enum.Material.Slate, Parent = model })
	part({ Name = "Post", Size = Vector3.new(0.9, 3, 0.9), CFrame = CFrame.new(base + Vector3.new(0, 2.3, 0)), Color = stone, Material = Enum.Material.Slate, Parent = model })
	local lamp = part({
		Name = "Lamp",
		Size = Vector3.new(1.8, 1.5, 1.8),
		CFrame = CFrame.new(base + Vector3.new(0, 4.5, 0)),
		Color = lightColor,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	part({ Name = "Roof", Size = Vector3.new(3, 0.6, 3), CFrame = CFrame.new(base + Vector3.new(0, 5.55, 0)), Color = stone, Material = Enum.Material.Slate, Parent = model })
	part({ Name = "Cap", Size = Vector3.new(1, 0.6, 1), CFrame = CFrame.new(base + Vector3.new(0, 6.15, 0)), Color = stone, Material = Enum.Material.Slate, Parent = model })
	local light = Instance.new("PointLight")
	light.Color = lightColor
	light.Range = 16
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = lamp
	model.Parent = parent
end

local function toriiGate(parent: Instance, center: Vector3, facingY: number, scale: number)
	local model = Instance.new("Model")
	model.Name = "ToriiGate"
	local red = Color3.fromRGB(196, 44, 38)
	local black = Color3.fromRGB(30, 26, 28)
	local rot = CFrame.new(center) * CFrame.Angles(0, math.rad(facingY), 0)
	local h = 20 * scale
	local span = 9 * scale
	for _, side in { -1, 1 } do
		part({
			Name = "Pillar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h, 2 * scale, 2 * scale),
			CFrame = rot * CFrame.new(side * span, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = red,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		part({
			Name = "Foot",
			Size = Vector3.new(2.6 * scale, 1.4 * scale, 2.6 * scale),
			CFrame = rot * CFrame.new(side * span, 0.7 * scale, 0),
			Color = black,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
	part({ Name = "Kasagi", Size = Vector3.new(span * 2 + 9 * scale, 1.6 * scale, 2.6 * scale), CFrame = rot * CFrame.new(0, h + 0.8 * scale, 0), Color = black, Material = Enum.Material.SmoothPlastic, Parent = model })
	part({ Name = "Shimaki", Size = Vector3.new(span * 2 + 7 * scale, 1 * scale, 2.2 * scale), CFrame = rot * CFrame.new(0, h - 0.4 * scale, 0), Color = red, Material = Enum.Material.SmoothPlastic, Parent = model })
	part({ Name = "Nuki", Size = Vector3.new(span * 2 + 3 * scale, 1 * scale, 1.4 * scale), CFrame = rot * CFrame.new(0, h - 4 * scale, 0), Color = red, Material = Enum.Material.SmoothPlastic, Parent = model })
	part({ Name = "Gakuzuka", Size = Vector3.new(1.2 * scale, 3 * scale, 1.6 * scale), CFrame = rot * CFrame.new(0, h - 2.2 * scale, 0), Color = black, Material = Enum.Material.SmoothPlastic, Parent = model })
	model.Parent = parent
	return model
end

local function rock(parent: Instance, position: Vector3, size: number, color: Color3, rng: Random)
	part({
		Name = "Rock",
		Size = Vector3.new(size, size * rng:NextNumber(0.6, 1.2), size * rng:NextNumber(0.7, 1.3)),
		CFrame = CFrame.new(position) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.4, 0.4)),
		Color = color,
		Material = Enum.Material.Rock,
		Parent = parent,
	})
end

---------------------------------------------------------------------------
-- Lighting
---------------------------------------------------------------------------

local function setupLighting()
	Lighting.ClockTime = 16.6
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(70, 64, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(135, 125, 145)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.5

	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(255, 222, 205)
	atmosphere.Decay = Color3.fromRGB(125, 95, 120)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.5
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.12
	color.Contrast = 0.06
	color.TintColor = Color3.fromRGB(255, 246, 238)
	color.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.05
	rays.Spread = 0.6
	rays.Parent = Lighting
end

---------------------------------------------------------------------------
-- Lobby
---------------------------------------------------------------------------

local function buildDummy(parent: Instance, position: Vector3, lookAt: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Training Dummy"

	local cf = CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
	local straw = Color3.fromRGB(214, 180, 112)
	local cloth = Color3.fromRGB(150, 50, 46)

	local root = part({ Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1), CFrame = cf * CFrame.new(0, 3, 0), Transparency = 1, CanCollide = false, Parent = model })
	local pieces = {
		part({ Name = "Torso", Size = Vector3.new(2, 2, 1), CFrame = cf * CFrame.new(0, 3, 0), Color = cloth, Material = Enum.Material.Fabric, Parent = model }),
		part({ Name = "Head", Size = Vector3.new(1.3, 1.3, 1.3), Shape = Enum.PartType.Ball, CFrame = cf * CFrame.new(0, 4.65, 0), Color = straw, Material = Enum.Material.Fabric, Parent = model }),
		part({ Name = "Left Arm", Size = Vector3.new(1, 2, 1), CFrame = cf * CFrame.new(-1.5, 3, 0), Color = straw, Material = Enum.Material.Fabric, Parent = model }),
		part({ Name = "Right Arm", Size = Vector3.new(1, 2, 1), CFrame = cf * CFrame.new(1.5, 3, 0), Color = straw, Material = Enum.Material.Fabric, Parent = model }),
		part({ Name = "Post", Size = Vector3.new(0.5, 2, 0.5), CFrame = cf * CFrame.new(0, 1, 0), Color = Color3.fromRGB(100, 72, 50), Material = Enum.Material.Wood, Parent = model }),
		part({ Name = "Stand", Size = Vector3.new(2.5, 0.4, 2.5), CFrame = cf * CFrame.new(0, 0.2, 0), Color = Color3.fromRGB(100, 72, 50), Material = Enum.Material.Wood, Parent = model }),
	}
	for _, p in pieces do
		p.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = Config.MaxHealth
	humanoid.Health = Config.MaxHealth
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.HealthDisplayDistance = 60
	humanoid.NameDisplayDistance = 60
	humanoid.Parent = model

	model.PrimaryPart = root
	model:SetAttribute("Dummy", true)
	CollectionService:AddTag(model, "SandoDummy")
	model.Parent = parent
	return model
end

local function buildLobby(map: Folder)
	local lobby = folder("Lobby", map)
	local rng = Random.new(7)

	local grass = Color3.fromRGB(98, 140, 74)
	local stone = Color3.fromRGB(176, 170, 160)

	part({ Name = "Ground", Size = Vector3.new(280, 4, 280), CFrame = CFrame.new(0, -2, 0), Color = grass, Material = Enum.Material.Grass, Parent = lobby })
	part({ Name = "Plaza", Size = Vector3.new(130, 1, 130), CFrame = CFrame.new(0, -0.3, 0), Color = stone, Material = Enum.Material.Cobblestone, Parent = lobby })
	part({ Name = "PlazaTrim", Size = Vector3.new(134, 0.9, 134), CFrame = CFrame.new(0, -0.4, 0), Color = Color3.fromRGB(110, 104, 98), Material = Enum.Material.Slate, Parent = lobby })

	-- Keep players on the island
	for _, info in {
		{ Vector3.new(0, 20, 140), Vector3.new(280, 50, 2) },
		{ Vector3.new(0, 20, -140), Vector3.new(280, 50, 2) },
		{ Vector3.new(140, 20, 0), Vector3.new(2, 50, 280) },
		{ Vector3.new(-140, 20, 0), Vector3.new(2, 50, 280) },
	} do
		part({ Name = "Barrier", Size = info[2], CFrame = CFrame.new(info[1]), Transparency = 1, Parent = lobby })
	end

	-- Spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(0, 0.2, 10)
	spawn.Color = Color3.fromRGB(196, 44, 38)
	spawn.Material = Enum.Material.Slate
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = lobby
	for _, child in spawn:GetChildren() do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end
	disc({ Name = "SpawnEmblem", Color = Color3.fromRGB(240, 230, 210), Material = Enum.Material.Neon, CanCollide = false, Parent = lobby }, Vector3.new(0, 0.72, 10), 6, 0.05)

	-- Title sign above the torii
	toriiGate(lobby, Vector3.new(0, 0.2, -52), 0, 1.2)
	local titleAnchor = part({ Name = "TitleAnchor", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(0, 32, -52), Transparency = 1, CanCollide = false, Parent = lobby })
	local title = billboard(titleAnchor, string.upper(Config.GameName), Color3.fromRGB(255, 236, 214), 0, 110);
	(title.Parent :: BillboardGui).Size = UDim2.fromOffset(420, 110)

	-- Queue pads
	local pads = {}
	local padColors = {
		Practice = Color3.fromRGB(140, 230, 140),
		Casual = Color3.fromRGB(90, 200, 255),
		Ranked = Color3.fromRGB(255, 196, 70),
		Clash = Color3.fromRGB(255, 90, 110),
	}
	for i, modeId in Config.ModeOrder do
		local mode = Config.Modes[modeId]
		local x = (i - (#Config.ModeOrder + 1) / 2) * 24
		local pos = Vector3.new(x, 0.2, -28)
		disc({ Name = "PadGlow", Color = padColors[modeId], Material = Enum.Material.Neon, Parent = lobby }, pos + Vector3.new(0, 0.1, 0), 15.5, 0.6)
		local pad = disc({ Name = "QueuePad_" .. modeId, Color = Color3.fromRGB(44, 40, 46), Material = Enum.Material.Slate, Parent = lobby }, pos + Vector3.new(0, 0.3, 0), 14, 0.8)
		pad:SetAttribute("Mode", modeId)

		local label = billboard(pad, mode.displayName, padColors[modeId], 7, 50)
		label.Name = "Title"
		local status = billboard(pad, "0 / " .. mode.teamSize * 2, Color3.new(1, 1, 1), 4.5, 34)
		status.Parent.Name = "StatusGui"

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "QueuePrompt"
		prompt.ActionText = "Join Queue"
		prompt.ObjectText = mode.displayName
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = pad

		stoneLantern(lobby, pos + Vector3.new(-9, 0, 6), padColors[modeId])
		stoneLantern(lobby, pos + Vector3.new(9, 0, 6), padColors[modeId])

		pads[modeId] = { part = pad, prompt = prompt, status = status }
	end

	-- Weapon shop (west)
	local shop = folder("Shop", lobby)
	local shopSign = part({ Name = "ShopSign", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(-50, 14, 0), Transparency = 1, CanCollide = false, Parent = shop })
	billboard(shopSign, "ARMORY", Color3.fromRGB(255, 220, 150), 0, 70)
	part({ Name = "ShopFloor", Size = Vector3.new(16, 0.6, 74), CFrame = CFrame.new(-52, 0.4, 0), Color = Color3.fromRGB(120, 82, 56), Material = Enum.Material.WoodPlanks, Parent = shop })
	part({ Name = "ShopRoof", Size = Vector3.new(18, 1, 78), CFrame = CFrame.new(-52, 13, 0), Color = Color3.fromRGB(40, 34, 36), Material = Enum.Material.Slate, Parent = shop })
	for _, z in { -36, -12, 12, 36 } do
		pole({ Name = "RoofPost", Color = Color3.fromRGB(196, 44, 38), Material = Enum.Material.SmoothPlastic, Parent = shop }, Vector3.new(-45, 0.7, z), 1.2, 12)
		pole({ Name = "RoofPost", Color = Color3.fromRGB(196, 44, 38), Material = Enum.Material.SmoothPlastic, Parent = shop }, Vector3.new(-59, 0.7, z), 1.2, 12)
	end

	local stands = {}
	local sorted = Weapons.sorted()
	for i, weapon in sorted do
		local z = (i - (#sorted + 1) / 2) * 11
		local base = Vector3.new(-52, 0.7, z)
		local pedestal = part({ Name = "Pedestal_" .. weapon.id, Size = Vector3.new(4, 3, 4), CFrame = CFrame.new(base + Vector3.new(0, 1.5, 0)), Color = Color3.fromRGB(70, 64, 66), Material = Enum.Material.Slate, Parent = shop })
		part({ Name = "Trim", Size = Vector3.new(4.4, 0.3, 4.4), CFrame = CFrame.new(base + Vector3.new(0, 3.1, 0)), Color = Color3.fromRGB(212, 168, 70), Material = Enum.Material.Metal, Parent = shop })

		local display = WeaponFactory.build(weapon.id)
		display.Name = "Display_" .. weapon.id
		for _, d in display:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		display:PivotTo(CFrame.new(base + Vector3.new(0, 4.4, 0)) * CFrame.Angles(math.rad(90), 0, math.rad(90)))
		display.Parent = shop

		local priceText = if weapon.price == 0 then "FREE" else (weapon.price .. " gold")
		billboard(pedestal, weapon.displayName, Color3.new(1, 1, 1), 7.5, 36)
		local price = billboard(pedestal, priceText, Color3.fromRGB(255, 210, 90), 5.8, 28)
		price.Parent.Name = "PriceGui"

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = "Buy / Equip"
		prompt.ObjectText = weapon.displayName .. " (" .. priceText .. ")"
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("WeaponId", weapon.id)
		prompt.Parent = pedestal
		table.insert(stands, prompt)
	end

	-- Training yard (east)
	local yard = folder("TrainingYard", lobby)
	part({ Name = "YardFloor", Size = Vector3.new(26, 0.6, 50), CFrame = CFrame.new(48, 0.4, 0), Color = Color3.fromRGB(196, 172, 128), Material = Enum.Material.Sand, Parent = yard })
	local yardSign = part({ Name = "YardSign", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(50, 12, 0), Transparency = 1, CanCollide = false, Parent = yard })
	billboard(yardSign, "TRAINING", Color3.fromRGB(200, 240, 255), 0, 70)
	for _, z in { -14, 0, 14 } do
		buildDummy(yard, Vector3.new(54, 0.7, z), Vector3.new(0, 0, z))
	end
	for _, z in { -24, 24 } do
		stoneLantern(yard, Vector3.new(38, 0.7, z), Color3.fromRGB(255, 205, 150))
	end

	-- Plaza decoration
	for _, pos in {
		Vector3.new(-30, 0.2, 40), Vector3.new(30, 0.2, 40), Vector3.new(-30, 0.2, -10), Vector3.new(30, 0.2, -10),
	} do
		stoneLantern(lobby, pos, Color3.fromRGB(255, 196, 140))
	end

	-- Cherry trees on the grass around the plaza
	local trees = folder("Trees", lobby)
	for _ = 1, 34 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(76, 128)
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		if math.abs(x) < 128 and math.abs(z) < 128 then
			cherryTree(trees, Vector3.new(x, 0, z), rng)
		end
	end

	-- Controls board near spawn
	local board = part({ Name = "ControlsBoard", Size = Vector3.new(14, 7, 0.6), CFrame = CFrame.new(0, 4.5, 34) * CFrame.Angles(0, math.rad(180), 0), Color = Color3.fromRGB(60, 44, 36), Material = Enum.Material.Wood, Parent = lobby })
	part({ Name = "BoardPostL", Size = Vector3.new(0.6, 4, 0.6), CFrame = CFrame.new(-6, 1, 34), Color = Color3.fromRGB(60, 44, 36), Material = Enum.Material.Wood, Parent = lobby })
	part({ Name = "BoardPostR", Size = Vector3.new(0.6, 4, 0.6), CFrame = CFrame.new(6, 1, 34), Color = Color3.fromRGB(60, 44, 36), Material = Enum.Material.Wood, Parent = lobby })
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Parent = board
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 240, 220)
	text.TextScaled = true
	text.Text = "HOW TO DUEL\n\nClick: attack combo\nHold E: heavy (full charge can't be parried)\nF: parry   Q: dodge   G: ultimate\n\nParry a hit to stun your opponent.\nPlaying alone? Try Practice vs Bot.\nWin rounds to earn gold, then buy weapons at the Armory."
	text.Parent = surface

	return {
		folder = lobby,
		spawn = spawn,
		pads = pads,
		shopPrompts = stands,
	}
end

---------------------------------------------------------------------------
-- Arenas
---------------------------------------------------------------------------

local THEMES = {
	{
		name = "Dojo Courtyard",
		floorMaterial = Enum.Material.WoodPlanks,
		floorColor = Color3.fromRGB(156, 110, 72),
		borderMaterial = Enum.Material.Slate,
		borderColor = Color3.fromRGB(52, 46, 48),
		pillarMaterial = Enum.Material.SmoothPlastic,
		pillarColor = Color3.fromRGB(196, 44, 38),
		groundMaterial = Enum.Material.Grass,
		groundColor = Color3.fromRGB(98, 140, 74),
		light = Color3.fromRGB(255, 200, 150),
		decorate = function(arena: Folder, origin: Vector3, rng: Random)
			toriiGate(arena, origin + Vector3.new(0, 0, -62), 0, 1)
			toriiGate(arena, origin + Vector3.new(0, 0, 62), 180, 1)
			for _ = 1, 22 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local r = rng:NextNumber(62, 105)
				cherryTree(arena, origin + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r), rng)
			end
		end,
	},
	{
		name = "Bamboo Grove",
		floorMaterial = Enum.Material.Ground,
		floorColor = Color3.fromRGB(128, 104, 74),
		borderMaterial = Enum.Material.Cobblestone,
		borderColor = Color3.fromRGB(120, 118, 110),
		pillarMaterial = Enum.Material.Wood,
		pillarColor = Color3.fromRGB(110, 150, 70),
		groundMaterial = Enum.Material.LeafyGrass,
		groundColor = Color3.fromRGB(70, 112, 58),
		light = Color3.fromRGB(190, 255, 170),
		decorate = function(arena: Folder, origin: Vector3, rng: Random)
			for _ = 1, 140 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local r = rng:NextNumber(52, 110)
				local base = origin + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
				local height = rng:NextNumber(20, 38)
				local green = Color3.fromRGB(90, 140, 60):Lerp(Color3.fromRGB(150, 180, 80), rng:NextNumber())
				pole({ Name = "Bamboo", Color = green, Material = Enum.Material.Wood, Parent = arena }, base, rng:NextNumber(0.7, 1.2), height)
				part({
					Name = "BambooLeaves",
					Size = Vector3.new(4, 1.2, 4),
					CFrame = CFrame.new(base + Vector3.new(0, height, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0.3),
					Color = Color3.fromRGB(80, 130, 60),
					Material = Enum.Material.Grass,
					CanCollide = false,
					Parent = arena,
				})
			end
		end,
	},
	{
		name = "Volcanic Rim",
		floorMaterial = Enum.Material.Basalt,
		floorColor = Color3.fromRGB(56, 50, 50),
		borderMaterial = Enum.Material.CrackedLava,
		borderColor = Color3.fromRGB(80, 40, 30),
		pillarMaterial = Enum.Material.Basalt,
		pillarColor = Color3.fromRGB(36, 32, 34),
		groundMaterial = Enum.Material.Neon,
		groundColor = Color3.fromRGB(255, 96, 30),
		groundDrop = 10,
		light = Color3.fromRGB(255, 120, 50),
		decorate = function(arena: Folder, origin: Vector3, rng: Random)
			for _ = 1, 40 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local r = rng:NextNumber(55, 110)
				rock(arena, origin + Vector3.new(math.cos(angle) * r, -8, math.sin(angle) * r), rng:NextNumber(6, 16), Color3.fromRGB(40, 36, 38), rng)
			end
			-- Heat light from below
			local glow = part({ Name = "LavaGlow", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(origin + Vector3.new(0, -6, 0)), Transparency = 1, CanCollide = false, Parent = arena })
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 110, 40)
			light.Range = 60
			light.Brightness = 2
			light.Parent = glow
		end,
	},
	{
		name = "Frozen Shrine",
		floorMaterial = Enum.Material.Snow,
		floorColor = Color3.fromRGB(236, 242, 250),
		borderMaterial = Enum.Material.Glacier,
		borderColor = Color3.fromRGB(150, 200, 230),
		pillarMaterial = Enum.Material.Glacier,
		pillarColor = Color3.fromRGB(170, 215, 240),
		groundMaterial = Enum.Material.Snow,
		groundColor = Color3.fromRGB(230, 238, 248),
		light = Color3.fromRGB(150, 210, 255),
		decorate = function(arena: Folder, origin: Vector3, rng: Random)
			for _ = 1, 30 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local r = rng:NextNumber(60, 108)
				pineTree(arena, origin + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r), rng)
			end
			for _ = 1, 16 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local r = rng:NextNumber(52, 100)
				rock(arena, origin + Vector3.new(math.cos(angle) * r, 0.5, math.sin(angle) * r), rng:NextNumber(3, 7), Color3.fromRGB(160, 170, 185), rng)
			end
		end,
	},
}

local function buildArena(map: Folder, index: number)
	local theme = THEMES[(index - 1) % #THEMES + 1]
	local origin = Vector3.new(ARENA_ORIGIN_X + (index - 1) * ARENA_SPACING, 0, 0)
	local rng = Random.new(100 + index)

	local arena = folder("Arena" .. index, map)
	arena:SetAttribute("ArenaName", theme.name)

	local size = 84
	local half = size / 2

	-- Ground around the arena
	part({
		Name = "Ground",
		Size = Vector3.new(240, 4, 240),
		CFrame = CFrame.new(origin + Vector3.new(0, -2 - (theme.groundDrop or 0), 0)),
		Color = theme.groundColor,
		Material = theme.groundMaterial,
		Parent = arena,
	})
	if theme.groundDrop then
		-- Rock column holding the fighting platform above the lava
		part({ Name = "Pillar", Size = Vector3.new(size + 2, theme.groundDrop, size + 2), CFrame = CFrame.new(origin + Vector3.new(0, -theme.groundDrop / 2 - 0.6, 0)), Color = Color3.fromRGB(40, 36, 38), Material = Enum.Material.Basalt, Parent = arena })
	end

	-- Fighting floor
	part({ Name = "Floor", Size = Vector3.new(size, 1, size), CFrame = CFrame.new(origin + Vector3.new(0, -0.1, 0)), Color = theme.floorColor, Material = theme.floorMaterial, Parent = arena })
	disc({ Name = "CenterRing", Color = theme.borderColor, Material = theme.borderMaterial, Parent = arena }, origin + Vector3.new(0, 0.42, 0), 22, 0.05)
	disc({ Name = "CenterEmblem", Color = theme.floorColor, Material = theme.floorMaterial, Parent = arena }, origin + Vector3.new(0, 0.44, 0), 19, 0.05)
	disc({ Name = "CenterDot", Color = theme.light, Material = Enum.Material.Neon, CanCollide = false, Parent = arena }, origin + Vector3.new(0, 0.46, 0), 2, 0.05)

	-- Low border wall and invisible barrier
	for _, info in {
		{ Vector3.new(0, 0, half + 1), Vector3.new(size + 4, 1, 2) },
		{ Vector3.new(0, 0, -half - 1), Vector3.new(size + 4, 1, 2) },
		{ Vector3.new(half + 1, 0, 0), Vector3.new(2, 1, size + 4) },
		{ Vector3.new(-half - 1, 0, 0), Vector3.new(2, 1, size + 4) },
	} do
		local pos, s = info[1], info[2]
		part({ Name = "Border", Size = Vector3.new(s.X, 2.5, s.Z), CFrame = CFrame.new(origin + pos + Vector3.new(0, 0.85, 0)), Color = theme.borderColor, Material = theme.borderMaterial, Parent = arena })
		part({ Name = "Barrier", Size = Vector3.new(s.X, 60, s.Z), CFrame = CFrame.new(origin + pos + Vector3.new(0, 30, 0)), Transparency = 1, Parent = arena })
	end
	part({ Name = "Ceiling", Size = Vector3.new(size + 4, 2, size + 4), CFrame = CFrame.new(origin + Vector3.new(0, 61, 0)), Transparency = 1, Parent = arena })

	-- Pillars with lights at corners and edges
	for _, offset in {
		Vector3.new(half, 0, half), Vector3.new(-half, 0, half), Vector3.new(half, 0, -half), Vector3.new(-half, 0, -half),
		Vector3.new(half, 0, 0), Vector3.new(-half, 0, 0),
	} do
		local base = origin + offset + Vector3.new(0, 0.4, 0)
		pole({ Name = "Pillar", Color = theme.pillarColor, Material = theme.pillarMaterial, Parent = arena }, base, 2.2, 14)
		local lamp = part({ Name = "PillarLamp", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(base + Vector3.new(0, 15, 0)), Color = theme.light, Material = Enum.Material.Neon, Parent = arena })
		local light = Instance.new("PointLight")
		light.Color = theme.light
		light.Range = 30
		light.Brightness = 1.4
		light.Parent = lamp
	end

	-- Team spawn markers
	local teamColors = { Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 90, 100) }
	local spawns = {}
	for team, zSign in { 1, -1 } do
		spawns[team] = {}
		local z = zSign * 28
		disc({ Name = "SpawnMarker" .. team, Color = teamColors[team], Material = Enum.Material.Neon, CanCollide = false, Parent = arena }, origin + Vector3.new(0, 0.43, z), 8, 0.05)
		for slot, x in { 0, 7, -7 } do
			local pos = origin + Vector3.new(x, 3.5, z)
			spawns[team][slot] = CFrame.lookAt(pos, origin + Vector3.new(x, 3.5, 0))
		end
	end

	-- Name sign visible from both spawns
	local signAnchor = part({ Name = "ArenaSign", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(origin + Vector3.new(0, 24, 0)), Transparency = 1, CanCollide = false, Parent = arena })
	local sign = billboard(signAnchor, theme.name, Color3.new(1, 1, 1), 0, 50);
	(sign.Parent :: BillboardGui).MaxDistance = 200

	theme.decorate(arena, origin, rng)

	return {
		index = index,
		name = theme.name,
		folder = arena,
		origin = origin,
		spawns = spawns,
		busy = false,
	}
end

function MapBuilder.build()
	setupLighting()
	workspace.FallenPartsDestroyHeight = -80

	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local map = folder("Map", workspace)

	local lobby = buildLobby(map)
	local arenas = {}
	for i = 1, Config.ArenaCount do
		arenas[i] = buildArena(map, i)
	end

	return {
		lobby = lobby,
		arenas = arenas,
	}
end

return MapBuilder
