local GrowingEggsConfig = {}

-- Studs kept clear from the base's bounding-box edge - a click that lands
-- inside the raw bounding box but within this distance of its edge is still
-- rejected.
GrowingEggsConfig.EDGE_PADDING = 3

-- Place-down juice: jump up then fall/jiggle into its resting CFrame.
GrowingEggsConfig.PLACE_JUMP_HEIGHT = 4
GrowingEggsConfig.PLACE_JUMP_TIME = 0.15
GrowingEggsConfig.PLACE_LAND_TIME = 0.45

-- How often (seconds) a GrowingEggGui countdown label refreshes its text.
GrowingEggsConfig.GUI_REFRESH_INTERVAL = 1

return GrowingEggsConfig
