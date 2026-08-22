local AnimalsConfig = {}


AnimalsConfig.Pets = {
    Chicken = {
        HatchesFrom = "Dragon",
    },
    Goose = {
        HatchesFrom = "Snake",
    },
    Scorpion = {
        HatchesFrom = "Stud",
    }
}

-- Reverse lookup built once: which pet a given egg name hatches into.
AnimalsConfig.PetForEgg = {}
for animalName, data in AnimalsConfig.Pets do
	AnimalsConfig.PetForEgg[data.HatchesFrom] = animalName
end

-- Spawned animal's uniform scale = (egg's footprint radius / animal
-- template's own footprint radius) * SCALE_MULTIPLIER - keeps its bounding
-- box close to the egg's at the moment it hatches. 1 = exact parity.
AnimalsConfig.SCALE_MULTIPLIER = 1

-- Wandering: how often (and how quickly) an idle base animal picks a new
-- spot inside its base and walks there. Wander bounds themselves are derived
-- from the base's own bounding box at pick time (see AnimalsService.PickWanderTarget),
-- not a fixed radius here - a bigger/upgraded base naturally gives more room
-- to roam.
AnimalsConfig.WANDER_MAX_ATTEMPTS = 10 -- ground-snap retries per wander target pick
AnimalsConfig.WANDER_INTERVAL_MIN = 2
AnimalsConfig.WANDER_INTERVAL_MAX = 5
AnimalsConfig.WALK_SPEED = 8
AnimalsConfig.THINK_INTERVAL = 0.5
AnimalsConfig.LOCOMOTION_STEP = 0.2
AnimalsConfig.REPATH_DISTANCE = 4
AnimalsConfig.ARRIVE_EPSILON = 1.5


AnimalsConfig.SHOWCASE_SPIN_STEPS = 4
AnimalsConfig.SHOWCASE_SPIN_TIME = 3 
AnimalsConfig.SHOWCASE_SPIN_SPEED = 90
-- World-space offset applied to the egg's own center (ExplodeEgg's `center`)
-- to get where the pet actually appears/spins during the showcase - e.g. a
-- positive Y here lifts it higher above where the egg was.
AnimalsConfig.SHOWCASE_SPIN_POSITION_OFFSET = Vector3.new(0, 0, 0)
AnimalsConfig.SHOWCASE_ARC_PEAK_HEIGHT = 5
AnimalsConfig.SHOWCASE_FLIGHT_TIME = 0.6
AnimalsConfig.SHOWCASE_TARGET_OFFSET = Vector3.new(0, 2,0) -- roughly torso height, in front of the player - same idea as EggsConfig.CARRY_OFFSET
AnimalsConfig.SHOWCASE_TRAIL_LIFETIME = 0.35

return AnimalsConfig