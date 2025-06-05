-- CropControlOverride.lua (with debug prints)
-- FS25 Mod: Override base game and map crop (fruit) order and disable selected crops for AI and players

CropControlOverride = {}

-- Custom crop order to enforce across PDA, prices, and contracts
CropControlOverride.fruitOrder = {
    "WHEAT", "BARLEY", "OAT", "CANOLA", "MAIZE",
    "SORGHUM", "SOYBEAN", "GRASS", "ALFALFA", "CLOVER",
    "PEA", "LENTILS", "RYE", "FLAX", "TRITICALE", "BEANS", "CHICKPEAS", "DRYPEAS", "FIELDGRASS", "OILSEEDRADISH"
}

-- Disallowed crops for AI and players
CropControlOverride.disallowedCrops = {
    POTATO = true, RICE = true, RICELONGGRAIN = true, SUGARBEET = true,
    SUGARCANE = true, COTTON = true, GRAPE = true, OLIVE = true,
    POPLAR = true, BEETROOT = true, CARROT = true, PARSNIP = true,
    GREENBEAN = true, SPINACH = true
}

function CropControlOverride:applyFruitOrder()
    if g_currentMission and g_currentMission.economyManager then
        g_currentMission.economyManager.fruitTypeDisplayOrder = CropControlOverride.fruitOrder
        print("CropControlOverride: PDA fruit order applied:")
        for _, name in ipairs(CropControlOverride.fruitOrder) do
            print(" -", name)
        end
    else
        print("CropControlOverride: EconomyManager not ready")
    end
end

function CropControlOverride:disableDisallowedCrops()
    print("CropControlOverride: Disabling disallowed crops...")
    for fruitName, disallow in pairs(CropControlOverride.disallowedCrops) do
        print("   checking fruit name:", fruitName)
        local fruitType = g_fruitTypeManager:getFruitTypeByName(fruitName)
        if fruitType ~= nil then
            fruitType.useForFieldJob = false
            fruitType.allowsSeeding = false
            fruitType.allowsHarvesting = false
            fruitType.allowsGrowing = false
            fruitType.needsSeeding = false
			fruitType.showOnPriceTable = false
			fruitType.showOnMap = false
			fruitType.allowsMapVisualization = false
            print(" - Disabled:", fruitName)
        else
            print(" - WARNING: Fruit not found:", fruitName)
        end
    end
end

function CropControlOverride:removeFromEconomyDisplay()
    local economy = g_currentMission.economyManager
    if economy == nil then
        print(" - WARNING: EconomyManager not available")
        return
    end

    local cleanedDisplayOrder = {}

    for _, fruitName in ipairs(economy.fruitTypeDisplayOrder) do
        if not CropControlOverride.disallowedCrops[fruitName] then
            table.insert(cleanedDisplayOrder, fruitName)
        else
            print(" - Removed from PDA display order:", fruitName)
        end
    end

    economy.fruitTypeDisplayOrder = cleanedDisplayOrder
end

function CropControlOverride:onLoadMap()
    print("CropControlOverride: onLoadMap() triggered")
    self:applyFruitOrder()
    self:disableDisallowedCrops()
	self:removeFromEconomyDisplay()
end

function CropControlOverride.init()
    print("CropControlOverride: init() called")
    FSBaseMission.loadMapFinished = Utils.appendedFunction(FSBaseMission.loadMapFinished, function(self)
        CropControlOverride:onLoadMap()
    end)
end

CropControlOverride.init()
