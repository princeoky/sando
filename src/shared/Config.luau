-- Global tuning values shared by the server and the client.

local Config = {}

Config.GameName = "sando"

-- Movement
Config.WalkSpeed = 16
Config.AttackWalkSpeed = 10
Config.ChargeWalkSpeed = 7
Config.StunWalkSpeed = 4

-- Health
Config.MaxHealth = 100

-- Parry
Config.ParryWindow = 0.25 -- seconds a parry is active
Config.ParryCooldown = 0.8 -- seconds from pressing parry until it can be used again
Config.ParryWhiffRecovery = 0.4 -- seconds you can't act after a parry that blocked nothing
Config.ParryStun = 1.0 -- seconds the attacker is stunned after getting parried

-- Dodge
Config.DodgeCooldown = 1.6
Config.DodgeIFrames = 0.3
Config.DodgeSpeed = 62
Config.DodgeDuration = 0.18

-- Hits
Config.HitStun = 0.28 -- a hit cancels whatever the victim was winding up
Config.Knockback = 22
Config.HeavyUnparryableAt = 0.85 -- a heavy charged past this fraction can't be parried

-- Ultimate meter (0..100)
Config.UltMax = 100
Config.UltGainDealt = 0.9 -- meter per point of damage dealt
Config.UltGainTaken = 0.5 -- meter per point of damage taken
Config.UltGainParry = 15

-- Matches
Config.CountdownTime = 3
Config.RoundTime = 90
Config.RoundEndTime = 3
Config.MatchEndTime = 5

-- Queue modes
Config.Modes = {
	Practice = {
		id = "Practice",
		displayName = "Practice vs Bot",
		teamSize = 1,
		roundsToWin = 2,
		ranked = false,
		practice = true, -- fights an AI bot, starts instantly, doesn't count as a duel
		unlockDuels = 0,
		winGold = 20,
		lossGold = 5,
	},
	Casual = {
		id = "Casual",
		displayName = "1v1 Duel",
		teamSize = 1,
		roundsToWin = 2, -- best of 3
		ranked = false,
		unlockDuels = 0,
		winGold = 100,
		lossGold = 25,
	},
	Ranked = {
		id = "Ranked",
		displayName = "Ranked 1v1",
		teamSize = 1,
		roundsToWin = 3, -- best of 5
		ranked = true,
		unlockDuels = 10,
		winGold = 150,
		lossGold = 30,
	},
	Clash = {
		id = "Clash",
		displayName = "2v2 Clash",
		teamSize = 2,
		roundsToWin = 2,
		ranked = false,
		unlockDuels = 3,
		winGold = 120,
		lossGold = 30,
	},
}
Config.ModeOrder = { "Practice", "Casual", "Ranked", "Clash" }

-- Ranked
Config.StartingElo = 1000
Config.EloK = 32

-- Data
Config.DataStoreName = "SandoPlayerData_v1"
Config.AutosaveInterval = 120

-- Practice bot: chance to react to an incoming swing
Config.BotParryChance = 0.3
Config.BotDodgeChance = 0.15

-- Map
Config.ArenaCount = 4

return Config
