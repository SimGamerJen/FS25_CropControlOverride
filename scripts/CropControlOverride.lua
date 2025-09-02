
-- scripts/CropControlOverride.lua
-- FS25 — Per-save config stored in modSettings (not in save folder) to avoid deletion on save
-- Early application via FruitTypeManager:loadMapData; safe XML I/O; PDA filtering hooks

CropControlOverride = {
    MOD_ID = g_currentModName or "FS25_CropControlOverride",
    SAVE_FILENAME = "CropControlOverride.xml"
}

-- ===== Defaults (only to seed the template if missing) ===================
local DEFAULT_ORDER = {
    "WHEAT","BARLEY","OAT","CANOLA","MAIZE",
    "SORGHUM","SOYBEAN","GRASS",
    "PEA","OILSEEDRADISH","POTATO","RICE","RICELONGGRAIN",
	"SUGARCANE","COTTON","GRAPE","OLIVE","POPLAR","GREENBEAN",
	"SUGARBEET","BEETROOT","CARROT","PARSNIP","SPINACH"
}

local DEFAULT_DISABLED = {}

-- ===== Path helpers ======================================================
local function userRoot()
    return getUserProfileAppPath()
end

local function ensureTrailingSlash(p)
    if not p or p == "" then return p end
    local last = p:sub(-1)
    if last ~= "/" and last ~= "\\" then
        return p .. "/"
    end
    return p
end

local function templateDir()
    local base = g_modSettingsDirectory or (userRoot() .. "modSettings/")
    return ensureTrailingSlash(base .. "FS25_CropControlOverride")
end

local function templatePath()
    return templateDir() .. "config.xml"
end

local function perSaveDir()
    return ensureTrailingSlash(templateDir() .. "saves")
end

local function saveFolderId()
    local mi = g_currentMission and g_currentMission.missionInfo
    if not mi or not mi.savegameDirectory or mi.savegameDirectory == "" then
        return nil
    end
    -- Extract last path component (works for relative 'savegame10' or absolute path)
    local last = mi.savegameDirectory:match("([^/\\]+)$")
    return last
end

local function perSaveSettingsPath()
    local id = saveFolderId()
    if not id then return nil end
    return perSaveDir() .. id .. ".xml"
end

local function ensureFolder(pathOrFile)
    local dir = pathOrFile:match("^(.*)[/\\][^/\\]+$") or pathOrFile
    if createFolder then createFolder(dir) end
end

-- ===== Config I/O (safe: XMLFile only) ===================================
local function writeConfigFromData(toPath, order, enabledMap)
    ensureFolder(toPath)
    local xml = XMLFile.create("CCO_write_config", toPath, "cropControl")
    if not xml then
        print("CCO: ERROR creating config at " .. toPath)
        return false
    end

    if order and #order > 0 then
        for i, n in ipairs(order) do
            xml:setString(("cropControl.order.fruit(%d)#name"):format(i-1), n)
        end
    end

    if enabledMap then
        local i = 0
        for nameU, en in pairs(enabledMap) do
            local k = ("cropControl.fruits.fruit(%d)"):format(i); i = i + 1
            xml:setString(k.."#name", nameU)
            xml:setBool(  k.."#enabled", en ~= false) -- default true
        end
    end

    xml:save(); xml:delete()
    return true
end

local function readConfigToData(path)
    local enabledMap, order = {}, nil
    local xml = XMLFile.load("CCO_read_cfg", path, "cropControl")
    if not xml then
        print("CCO: ERROR reading " .. tostring(path) .. " (using all enabled, default order)")
        return enabledMap, order
    end

    local i=0
    while true do
        local k=("cropControl.fruits.fruit(%d)"):format(i)
        if not xml:hasProperty(k) then break end
        local name  = xml:getString(k.."#name")
        local en    = xml:getBool(k.."#enabled", true)
        if name and name ~= "" then enabledMap[string.upper(name)] = en end
        i=i+1
    end

    local ord = {}
    i=0
    while true do
        local k=("cropControl.order.fruit(%d)"):format(i)
        if not xml:hasProperty(k) then break end
        local name = xml:getString(k.."#name")
        if name and name ~= "" then table.insert(ord, string.upper(name)) end
        i=i+1
    end
    xml:delete()
    if #ord > 0 then order = ord end
    return enabledMap, order
end

local function writeDefaultTemplateIfMissing()
    local tpl = templatePath()
    if fileExists(tpl) then return end
    ensureFolder(tpl)
    local ok = writeConfigFromData(tpl, DEFAULT_ORDER, DEFAULT_DISABLED)
    if ok then
        print("CCO: wrote default template: " .. tpl)
    end
end

local function ensurePerSaveFromTemplate()
    local per = perSaveSettingsPath()
    if not per then
        print("CCO: per-save id not available yet; using template only this run")
        return nil
    end
    if fileExists(per) then return per end
    -- Create per-save file in modSettings/saves/<id>.xml from template (or defaults)
    writeDefaultTemplateIfMissing()
    local enabledMap, order = readConfigToData(templatePath())
    if not order then order = DEFAULT_ORDER end
    local ok = writeConfigFromData(per, order, enabledMap)
    if ok then
        print("CCO: created per-save settings in modSettings: " .. per)
        return per
    else
        print("CCO: WARNING failed to create per-save settings at " .. tostring(per))
        return nil
    end
end

local function upper(s) return s and string.upper(s) or s end

-- ===== Early hook: apply BEFORE AI/UI/economy consume fruitTypes =========
local origLoad = FruitTypeManager.loadMapData
function FruitTypeManager:loadMapData(xmlFile, missionInfo, baseDir, customEnv, isMission)
    local ok = origLoad(self, xmlFile, missionInfo, baseDir, customEnv, isMission)

    -- Ensure template exists
    writeDefaultTemplateIfMissing()

    -- Ensure a per-save file exists in modSettings/saves/<id>.xml (won't be deleted by game saves)
    local perPath = ensurePerSaveFromTemplate()

    -- Choose config: per-save (if present) else template
    local cfgToUse = perPath or templatePath()
    print("CCO: using config -> " .. cfgToUse)

    -- Read config and apply immediately
    local enabledMap, userOrder = readConfigToData(cfgToUse)

    -- Disable unwanted fruitTypes (applies to AI, equipment, prices, map)
    for _, fruit in ipairs(self.fruitTypes) do
        local n = upper(fruit.name)
        local en = enabledMap[n]
        if en == false then
            fruit.useForFieldJob         = false
            fruit.allowsSeeding          = false
            fruit.allowsHarvesting       = false
            fruit.allowsGrowing          = false
            fruit.needsSeeding           = false
            fruit.showOnPriceTable       = false
            fruit.showOnMap              = false
            fruit.allowsMapVisualization = false
            print("CCO: disabled " .. n)
        end
    end

    -- PDA order now (filter out disabled)
    local econ = g_currentMission and g_currentMission.economyManager
    if econ then
        local base = userOrder or econ.fruitTypeDisplayOrder or DEFAULT_ORDER
        local filtered, seen = {}, {}
        for _, n in ipairs(base) do
            local u = upper(n)
            if enabledMap[u] ~= false and not seen[u] then
                table.insert(filtered, u); seen[u] = true
            end
        end
        econ.fruitTypeDisplayOrder = filtered
        print(("CCO: PDA order applied (%d items)"):format(#filtered))
    end

    CropControlOverride._enabledMap = enabledMap

    return ok
end

-- ===== Optional: PDA UI filtering hooks =================================
local function applyPdaFilterHooks()
    if IngameMenu == nil then return end

    IngameMenu.onOpen = Utils.appendedFunction(IngameMenu.onOpen, function(menuSelf)
        if CropControlOverride._enabledMap == nil then return end

        local function filterFruitList()
            local filtered = {}
            for _, fruit in ipairs(g_fruitTypeManager.fruitTypes) do
                if CropControlOverride._enabledMap[upper(fruit.name)] ~= false then
                    table.insert(filtered, fruit)
                end
            end
            return filtered
        end

        if menuSelf.cropCalendarFrame and menuSelf.cropCalendarFrame.updateData then
            local original = menuSelf.cropCalendarFrame.updateData
            function menuSelf.cropCalendarFrame:updateData()
                self.fruitTypes = filterFruitList()
                if original then original(self) end
            end
        end

        if menuSelf.mapOverviewFrame and menuSelf.mapOverviewFrame.updateFruitTypes then
            local originalMap = menuSelf.mapOverviewFrame.updateFruitTypes
            function menuSelf.mapOverviewFrame:updateFruitTypes()
                self.fruitTypes = filterFruitList()
                if originalMap then originalMap(self) end
            end
        end

        if menuSelf.statisticsFrame and menuSelf.statisticsFrame.updateFruitTypes then
            local originalStats = menuSelf.statisticsFrame.updateFruitTypes
            function menuSelf.statisticsFrame:updateFruitTypes()
                self.fruitTypes = filterFruitList()
                if originalStats then originalStats(self) end
            end
        end
    end)
end

applyPdaFilterHooks()

addModEventListener(CropControlOverride)
