--//Services
local ServerScriptService = game.ServerScriptService
local RunService = game.RunService
local ReplicatedStorage = game.ReplicatedStorage
local ProfileStore = require(ReplicatedStorage.Shared.Packages.ProfileStore)
local DataManager = require(ServerScriptService.Server.Data.Manager)
local PROFILE_TEMPLATE = require(ServerScriptService.Server.Data.Template)

local Players = game:GetService("Players")
local Key = RunService:IsStudio() and "Studio_Store_1" or "Test_Store_1"

local PlayerStore = ProfileStore.New(Key, PROFILE_TEMPLATE)

local InitData = {}

local function PlayerAdded(player)
	-- Start a profile session for this player's data:

	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	-- Handling new profile session or failure to start it:

	if profile ~= nil then
		profile:AddUserId(player.UserId) -- GDPR compliance
		profile:Reconcile() -- Fill in missing variables from PROFILE_TEMPLATE (optional)

		profile.OnSessionEnd:Connect(function()
			DataManager.Profiles[player] = nil
			player:Kick(`Profile session end - Please rejoin`)
		end)

		if player.Parent == Players then
			DataManager.Profiles[player] = profile
			print(profile)
			print(`Profile loaded for {player.DisplayName}!`)
			DataManager.SetupLeaderstats(player)
			DataManager.SyncAllToClient(player)
		else
			-- The player has left before the profile session started
			profile:EndSession()
		end
	else
		-- This condition should only happen when the Roblox server is shutting down
		player:Kick(`Profile load fail - Please rejoin`)
	end
end

-- In case Players have joined the server earlier than this script ran:
for _, player in Players:GetPlayers() do
	task.spawn(PlayerAdded, player)
end

Players.PlayerAdded:Connect(PlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	local profile = DataManager.Profiles[player]
	if profile ~= nil then
		profile:EndSession()
	end
end)

return InitData
