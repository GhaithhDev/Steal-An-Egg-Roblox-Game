local EggGuardsConfig = {}

-- Cadences
EggGuardsConfig.THINK_INTERVAL_MIN = 0.08 -- target selection / state decision (randomized - staggers the guards)
EggGuardsConfig.THINK_INTERVAL_MAX = 0.15
EggGuardsConfig.LOCOMOTION_STEP = 0.1 -- steer / repath-staleness check

-- Movement
EggGuardsConfig.REPATH_DISTANCE = 6 -- only recompute a path once the target has drifted this far (studs)
EggGuardsConfig.ARRIVE_EPSILON = 1 -- treated as "arrived back at spawn"

-- How long (seconds) an Idle guard takes to tween back to its spawn point's
-- original facing.
EggGuardsConfig.RETURN_FACING_TWEEN_TIME = 0.6

-- How long (seconds) a guard holds still playing its one-shot Wakeup
-- animation, from Idle, before it actually starts chasing. Matches the real
-- ChickenWakeup clip length (0.5s) - retune if other guard species' wake-up
-- clips run a different length.
EggGuardsConfig.WAKEUP_DURATION = 0.5

-- Catch: while Chasing, a guard within this distance (studs) of its target
-- force-drops the egg and ragdolls/knocks the player back.
EggGuardsConfig.CATCH_DISTANCE = 4
EggGuardsConfig.STUN_DURATION = 1.5
EggGuardsConfig.KNOCKBACK_FORCE = 145
EggGuardsConfig.KNOCKBACK_UPWARD_FORCE = 15

return EggGuardsConfig
