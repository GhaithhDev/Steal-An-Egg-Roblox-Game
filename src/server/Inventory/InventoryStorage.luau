local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConfig = require(ReplicatedStorage.Shared.Configs.InventoryConfig)

local InventoryStorage = {}

-- Category never moves a Tool between Backpack and anywhere else — the hotbar is the
-- same regardless of which category tab is open. It's purely a UI-state signal the
-- client uses to decide which grid slots (never hotbar slots) are visible; see
-- Satchel/SatchelInit.luau's Category-attribute mirroring and InventoryController.luau.
function InventoryStorage.SetupPlayer(player: Player)
	player:SetAttribute(InventoryConfig.ACTIVE_CATEGORY_ATTRIBUTE, InventoryConfig.DEFAULT_CATEGORY)

	-- A Tool equipped in-hand lives under Character, not Backpack, so without this it
	-- gets destroyed along with the character on death, losing it permanently.
	player.CharacterRemoving:Connect(function(character: Model)
		local backpack = player:FindFirstChildOfClass("Backpack")
		local equippedTool = character:FindFirstChildOfClass("Tool")
		if backpack and equippedTool then
			equippedTool.Parent = backpack
		end
	end)
end

function InventoryStorage.SwitchCategory(player: Player, category: string)
	if not InventoryConfig.Categories[category] then
		return
	end
	player:SetAttribute(InventoryConfig.ACTIVE_CATEGORY_ATTRIBUTE, category)
end

return InventoryStorage
