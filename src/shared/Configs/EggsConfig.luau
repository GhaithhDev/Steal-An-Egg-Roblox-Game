local EggsConfig = {}

EggsConfig.Eggs = {
	Dragon = {
		ScaleRange = { Min = 1, Max = 1.5 },
		Rarity = "Common",
		GrowTime = 10,
	},
	Snake = {
		ScaleRange = { Min = 1.2, Max = 1.7 },
		Rarity = "Rare",
		GrowTime = 15,
	},
	Stud = {
		ScaleRange = { Min = 2, Max = 5 },
		Rarity = "Rare",
		GrowTime = 5
	}
}

EggsConfig.EggsInEachArea = 5
EggsConfig.EggsPerArea = {
	Forest = {
		{ Name = "Dragon", Chance = 0.7 },
	},
	Lake = {
		{ Name = "Snake", Chance = 0.3 },
	},
	Desert = {
		{ Name = "Stud", Chance = 0.3 },
	},
}

-- Order matters: closest-to-spawn area first. Drives AreaEggsService.GetAreaAtPosition's
-- boundary walk (workspace.Functional.AreaEndAt) - must mirror the real world layout.
EggsConfig.AreaOrder = { "Forest", "Lake", "Desert" }

-- How much bigger a nest's visible horizontal size is than the egg it holds
EggsConfig.NEST_SCALE_MULTIPLIER = 1.25

-- Fraction of picked EggScale a "not yet grown" egg visually renders at -
-- nest, dropped, carried, backpack Tool, and freshly-placed-in-base all start
-- here; only a placed egg growing in a base climbs from this up to 1.0 (see
-- GrowingEggsConfig).
EggsConfig.BABY_SCALE_FRACTION = 0.2

-- Gap (studs) left between two touching nests' footprints - every egg is placed
-- touching another egg by this much, so the group always reads as one cluster
EggsConfig.EGG_PLACEMENT_PADDING = 0.5

-- How many times we retry a random anchor/angle before giving up and skipping the egg
EggsConfig.EGG_PLACEMENT_MAX_ATTEMPTS = 20

-- Carrying
EggsConfig.CARRY_PROMPT_ACTION_TEXT = "Carry"
EggsConfig.CARRY_PROMPT_HOLD_DURATION = 0.5
EggsConfig.CARRY_PROMPT_MAX_DISTANCE = 8
EggsConfig.CARRY_OFFSET = Vector3.new(0, 3, -3) -- carried egg's position relative to the rig's HumanoidRootPart
EggsConfig.DropOffset = 3 -- how much studs away the egg will be from player

function EggsConfig.GetRandomEgg(area: string): (string, number)
	local pool = EggsConfig.EggsPerArea[area]
	assert(pool, `No egg pool configured for area "{area}"`)

	local roll = math.random()
	local cumulative = 0
	for _, entry in pool do
		cumulative += entry.Chance
		if roll <= cumulative then
			local scaleRange = EggsConfig.Eggs[entry.Name].ScaleRange
			return entry.Name, scaleRange.Min + math.random() * (scaleRange.Max - scaleRange.Min)
		end
	end

	local fallback = pool[#pool]
	local scaleRange = EggsConfig.Eggs[fallback.Name].ScaleRange
	return fallback.Name, scaleRange.Min + math.random() * (scaleRange.Max - scaleRange.Min)
end

return EggsConfig
