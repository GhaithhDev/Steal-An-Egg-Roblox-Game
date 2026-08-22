local GrowingEggsConfig = {}

-- Studs kept clear from the base's bounding-box edge - a click that lands
-- inside the raw bounding box but within this distance of its edge is still
-- rejected.
GrowingEggsConfig.EDGE_PADDING = 3

-- Minimum gap (studs) kept between two growing eggs' footprints in a base
-- (edge to edge, not center to center, accounting for each egg's full-grown
-- footprint radius) - a placement too close to an already-growing egg is
-- rejected.
GrowingEggsConfig.MIN_EGG_GAP = 3

-- Place-down juice: jump up then fall/jiggle into its resting CFrame.
GrowingEggsConfig.PLACE_JUMP_HEIGHT = 4
GrowingEggsConfig.PLACE_JUMP_TIME = 0.15
GrowingEggsConfig.PLACE_LAND_TIME = 0.45

-- How often (seconds) a GrowingEggGui countdown label refreshes its text.
GrowingEggsConfig.GUI_REFRESH_INTERVAL = 1

-- Fixed world-space size (studs) every mounted GrowingEggGui is forced to.
-- The template asset's own Size is Scale-based, and BillboardGui Scale is
-- relative to the Adornee's bounding box - since the egg's own ScaleTo grows
-- over time (see the growth-scale system below), a Scale-based Size would
-- visibly grow right along with it. Offset-only keeps it a constant size.
GrowingEggsConfig.GUI_SIZE = UDim2.fromScale(10, 10)

-- Growth-scale steps: a placed egg climbs from EggsConfig.BABY_SCALE_FRACTION
-- to 1.0 in GROWTH_STEP_SIZE-sized jumps (0.1 -> 8 steps), each played as a
-- GROWTH_STEP_TWEEN_TIME pop animation the moment real elapsed time crosses
-- that step's threshold. GROWTH_CHECK_INTERVAL is how often the server
-- re-checks every growing egg for a newly-crossed threshold.
GrowingEggsConfig.GROWTH_STEP_SIZE = 0.1
GrowingEggsConfig.GROWTH_STEP_TWEEN_TIME = 0.3
GrowingEggsConfig.GROWTH_CHECK_INTERVAL = 0.5

-- Ready-egg idle animation: every READY_ANIM_MIN/MAX_INTERVAL seconds, a fully
-- grown egg wiggles, pops up to READY_ANIM_SCALE_MULTIPLIER of its normal
-- size with a white highlight, holds, then settles back down - "come catch
-- me". Reuses the same ScaleFraction NumberValue the growth-scale system
-- drives (1.0 -> multiplier -> 1.0), so no separate scale mechanism needed.
GrowingEggsConfig.READY_ANIM_MIN_INTERVAL = 4
GrowingEggsConfig.READY_ANIM_MAX_INTERVAL = 6
GrowingEggsConfig.READY_ANIM_WIGGLE_ANGLE = 15 -- degrees
GrowingEggsConfig.READY_ANIM_WIGGLE_TIME = 0.5
GrowingEggsConfig.READY_ANIM_SCALE_MULTIPLIER = 1.3
GrowingEggsConfig.READY_ANIM_SCALE_TIME = 0.2
GrowingEggsConfig.READY_ANIM_HOLD_TIME = 0.6
GrowingEggsConfig.READY_ANIM_HIGHLIGHT_FILL_TRANSPARENCY = 0.5
GrowingEggsConfig.READY_ANIM_HIGHLIGHT_OUTLINE_TRANSPARENCY = 0

-- Hatch prompt: appears on a growing egg the moment it's fully grown (mirrors
-- SpawnsEggsService.AddCarryPrompt's convention).
GrowingEggsConfig.HATCH_PROMPT_ACTION_TEXT = "Hatch"
GrowingEggsConfig.HATCH_PROMPT_HOLD_DURATION = 0.5
GrowingEggsConfig.HATCH_PROMPT_MAX_DISTANCE = 8

-- Hatch wiggle: 3 escalating shake phases (mild -> harder -> hardest), each a
-- single offset-then-Elastic-settle wiggle on PrimaryPart (same technique as
-- READY_ANIM_WIGGLE_*, just repeated with a growing angle and a pause between
-- each settle finishing and the next phase starting).
GrowingEggsConfig.HATCH_WIGGLE_ANGLES = { 8, 18, 32 } -- degrees, mild -> hardest
GrowingEggsConfig.HATCH_WIGGLE_TIME = 0.35
GrowingEggsConfig.HATCH_WIGGLE_PAUSE_TIME = 0.25

-- Hatch explosion: once scaled+highlighted (reuses READY_ANIM_SCALE_MULTIPLIER/
-- READY_ANIM_SCALE_TIME/READY_ANIM_HIGHLIGHT_* - same visual, held instead of
-- settled back down), every individual BasePart flies outward from the model
-- along a real quadratic bezier curve (start -> outward-and-up peak -> a
-- randomized ground point), fades out, and the whole model is destroyed.
-- The curve itself is animated client-side via RunService (see
-- HatchExplosionController.luau), not ReplicatedTween - it's a one-shot
-- cosmetic with no gameplay state riding on it, so there's no need to pay for
-- replicated tween goals here. MIN/MAX_DISTANCE is horizontal distance
-- travelled; ARC_PEAK_HEIGHT is added on top of the peak control point;
-- ARC_TIME is how long the whole curve takes, start to landing.
GrowingEggsConfig.HATCH_EXPLODE_ARC_PEAK_HEIGHT = 8
GrowingEggsConfig.HATCH_EXPLODE_MIN_DISTANCE = 4
GrowingEggsConfig.HATCH_EXPLODE_MAX_DISTANCE = 20
GrowingEggsConfig.HATCH_EXPLODE_ARC_TIME = 0.8
GrowingEggsConfig.HATCH_EXPLODE_FADE_TIME = 0.6

-- Trail glued to each flying part for the up+down arc only - disabled (stops
-- emitting new points, existing ones age out over TRAIL_LIFETIME) the moment
-- the fade starts, so it never lingers as a static streak on a landed part.
GrowingEggsConfig.HATCH_EXPLODE_TRAIL_LIFETIME = 0.35

return GrowingEggsConfig
