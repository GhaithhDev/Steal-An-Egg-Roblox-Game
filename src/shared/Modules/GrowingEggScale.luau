--[[
	GrowingEggScale

	Shared between server (GrowingEggsService) and client
	(GrowingEggScaleController) so both react identically to a growing egg's
	"ScaleFraction" NumberValue changing: re-apply Model:ScaleTo() and
	re-ground the model, since scaling shifts its bounding box and doesn't
	keep the bottom face pinned to the floor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--//Configs
local GrowingEggsConfig = require(ReplicatedStorage.Shared.Configs.GrowingEggsConfig)

local ModelUtils = require(ReplicatedStorage.Shared.Packages.ModelUtils)

local GrowingEggScale = {}

function GrowingEggScale.Apply(eggModel: Model, scaleFractionValue: NumberValue)
	local eggScale = eggModel:GetAttribute("EggScale")
	local restPosition = eggModel:GetAttribute("RestPosition")
	if not (eggScale and restPosition) then
		return
	end

	eggModel:ScaleTo(eggScale * scaleFractionValue.Value)
	local gui = eggModel:FindFirstChild("GrowingEggGui")
	if gui then
		gui.Size = GrowingEggsConfig.GUI_SIZE
	end
	ModelUtils.AlignModelBottom(eggModel, restPosition)
end

return GrowingEggScale
