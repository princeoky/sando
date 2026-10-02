-- sando client entry point.

local StarterGui = game:GetService("StarterGui")

local CombatController = require(script.CombatController)
local Effects = require(script.Effects)
local Hud = require(script.Hud)

Effects.start()
CombatController.start()
Hud.start()

-- Resetting your character would count as a knockout, so turn it off
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)
