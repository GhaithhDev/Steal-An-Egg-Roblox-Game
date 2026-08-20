return {
	-- Egg Guards: each guard species has its own pair, keyed as
	-- "<GuardName>Idle"/"<GuardName>Walk", where <GuardName> matches the
	-- template's name under ReplicatedStorage.Shared.Assets.EggGuard (and the
	-- spawn point's Name in workspace.Functional.EggGuardsSpawnPositions).
	-- Add one pair per guard species the same way. TODO: replace with real ids.
	ChickenSleep = "rbxassetid://100807402155680",
	ChickenRun = "rbxassetid://81361492031369",
	ChickenWalk = "rbxassetid://81361492031369",
	ChickenWakeup = "rbxassetid://137656111065541"
}
