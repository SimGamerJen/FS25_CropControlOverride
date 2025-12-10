-- FS25 — Crop Control Override (config-driven; matches original "disable" flags)
-- Disables crops from the start by applying all original flags for disabled crops.
-- Reads from modSettings template or per-save; applies immediately in loadMapData.
-- Also provides console helpers for debugging and inspection.

CropControlOverride = {
    MOD_ID       = g_currentModName or "FS25_CropControlOverride",
    _origFlags   = {},   -- per-fruit snapshot of original flags (NAME -> { key->value })
    _enabledMap  = nil,  -- last-applied config (NAME -> bool)
}

---------------------------------------------------------------------------
-- Helpers / Paths
---------------------------------------------------------------------------
local function upper(s) return s and string.upper(s) or s end

local function userRoot()
    return getUserProfileAppPath()
end

local function ensureSlash(p)
    if not p or p == "" then return p end
    local c = p:sub(-1)
    if c ~= "/" and c ~= "\\" then
        return p .. "/"
    end
    return p
end

local function settingsRoot()
    local base = g_modSettingsDirectory or (userRoot() .. "modSettings/")
    return ensureSlash(base .. "FS25_CropControlOverride")
end

local function templatePath()
    return settingsRoot() .. "config.xml"
end

local function getSaveIdFromMissionInfo(mi)
    if not mi then return nil end
    if mi.savegameIndex and tonumber(mi.savegameIndex) then
        return ("savegame%d"):format(tonumber(mi.savegameIndex))
    end
    if mi.savegameDirectory and mi.savegameDirectory ~= "" then
        return mi.savegameDirectory:match("([^/\\]+)$")
    end
    return nil
end

local function perSavePathForId(saveId)
    if not saveId then return nil end
    return settingsRoot() .. "saves/" .. saveId .. ".xml"
end

local function ensureFolder(pathOrFile)
    local dir = pathOrFile:match("^(.*)[/\\][^/\\]+$") or pathOrFile
    if not dir or dir == "" then return end
    local acc = ""
    for part in string.gmatch(dir, "[^/\\]+") do
        acc = acc .. part .. "/"
        if createFolder then
            createFolder(acc)
        end
    end
end

---------------------------------------------------------------------------
-- Config I/O (XMLFile only)
---------------------------------------------------------------------------
local function writeConfig(toPath, enabledMap)
    ensureFolder(toPath)
    local xml = XMLFile.create("CCO_write", toPath, "cropControl")
    if not xml then
        print("CCO [ERROR]: cannot create config at " .. tostring(toPath))
        return false
    end

    local i = 0
    for nameU, en in pairs(enabledMap) do
        local k = ("cropControl.fruits.fruit(%d)"):format(i)
        i = i + 1
        xml:setString(k .. "#name", nameU)
        xml:setBool(k .. "#enabled", en ~= false)
    end

    xml:save()
    xml:delete()
    return true
end

local function readConfig(path)
    local map = {}
    local xml = XMLFile.load("CCO_read", path, "cropControl")
    if not xml then return map end

    -- Prefer nested form <cropControl><fruits><fruit/></fruits></cropControl>
    local i, count = 0, 0
    while true do
        local k = ("cropControl.fruits.fruit(%d)"):format(i)
        if not xml:hasProperty(k) then break end
        local n  = xml:getString(k .. "#name")
        local en = xml:getBool(k .. "#enabled", true)
        if n and n ~= "" then
            map[upper(n)] = en
            count = count + 1
        end
        i = i + 1
    end

    -- Fallback to flat <cropControl><fruit/></cropControl>
    if count == 0 then
        i = 0
        while true do
            local k = ("cropControl.fruit(%d)"):format(i)
            if not xml:hasProperty(k) then break end
            local n  = xml:getString(k .. "#name")
            local en = xml:getBool(k .. "#enabled", true)
            if n and n ~= "" then
                map[upper(n)] = en
            end
            i = i + 1
        end
    end

    xml:delete()
    return map
end

local function buildDefaultEnabledMap()
    local m = {}
    if g_fruitTypeManager then
        for _, ft in ipairs(g_fruitTypeManager.fruitTypes) do
            if ft and ft.name then
                m[upper(ft.name)] = true
            end
        end
    end
    return m
end

local function ensureTemplateExists()
    local tpl = templatePath()
    if fileExists(tpl) then return tpl end
    local defaults = buildDefaultEnabledMap()
    if writeConfig(tpl, defaults) then
        print("CCO: wrote default template at " .. tpl)
    end
    return tpl
end

---------------------------------------------------------------------------
-- Core: apply full "disabled" set (matches your original)
---------------------------------------------------------------------------
local FIELDS = {
    "useForFieldJob", "allowsSeeding", "allowsHarvesting", "allowsGrowing",
    "needsSeeding", "showOnPriceTable", "showOnMap", "allowsMapVisualization"
}

local function snapshotIfNeeded(self, fruitName, fruit)
    if self._origFlags[fruitName] then return end
    local snap = {}
    for _, key in ipairs(FIELDS) do
        snap[key] = fruit[key]
    end
    self._origFlags[fruitName] = snap
end

local function applyDisabledFlags(fruit)
    fruit.useForFieldJob         = false
    fruit.allowsSeeding          = false
    fruit.allowsHarvesting       = false
    fruit.allowsGrowing          = false
    fruit.needsSeeding           = false
    fruit.showOnPriceTable       = false
    -- NOTE: we deliberately leave showOnMap/allowsMapVisualization alone in this
    -- variant so map colours stay visible, even if the fruit is "disabled" for AI.
end

local function restoreFlags(self, fruitName, fruit)
    local snap = self._origFlags[fruitName]
    if not snap then
        -- permissive defaults if no snapshot (brand-new fruit)
        fruit.useForFieldJob         = true
        fruit.allowsSeeding          = true
        fruit.allowsHarvesting       = true
        fruit.allowsGrowing          = true
        fruit.needsSeeding           = fruit.needsSeeding or false
        fruit.showOnPriceTable       = true
        fruit.showOnMap              = true
        fruit.allowsMapVisualization = true
        return
    end
    for _, key in ipairs(FIELDS) do
        if type(fruit[key]) == "boolean" then
            fruit[key] = (snap[key] ~= nil) and snap[key] or fruit[key]
        end
    end
end

function CropControlOverride:_applyEnabledMap(enabledMap)
    if not g_fruitTypeManager then return end

    for _, fruit in ipairs(g_fruitTypeManager.fruitTypes) do
        local n = upper(fruit.name)
        snapshotIfNeeded(self, n, fruit)
        if enabledMap[n] == false then
            applyDisabledFlags(fruit)
        else
            restoreFlags(self, n, fruit)
        end
    end

    self._enabledMap = enabledMap
end

---------------------------------------------------------------------------
-- EARLY hook: apply right after fruitTypes are loaded for THIS session
-- If per-save missing, read template NOW, apply NOW, then write per-save.
---------------------------------------------------------------------------
local origFTLoad = FruitTypeManager.loadMapData
function FruitTypeManager:loadMapData(xmlFile, missionInfo, baseDir, customEnv, isMission)
    local ok = origFTLoad(self, xmlFile, missionInfo, baseDir, customEnv, isMission)

    local saveId = getSaveIdFromMissionInfo(missionInfo)
    local per    = perSavePathForId(saveId)
    local tpl    = ensureTemplateExists()

    local usedPath, usedMap

    if per and fileExists(per) then
        usedPath = per
        usedMap  = readConfig(per)
        if not next(usedMap) then
            usedMap = buildDefaultEnabledMap()
        end
        CropControlOverride:_applyEnabledMap(usedMap)
        print(("CCO: applied crop disables from %s"):format(usedPath))
    else
        usedPath = tpl
        usedMap  = readConfig(tpl)
        if not next(usedMap) then
            usedMap = buildDefaultEnabledMap()
        end
        CropControlOverride:_applyEnabledMap(usedMap)
        print(("CCO: applied crop disables from %s (per-save missing)"):format(usedPath))
        if per then
            if writeConfig(per, usedMap) then
                print(("CCO: created per-save config at %s"):format(per))
            else
                print(("CCO [WARN]: failed to create per-save config at %s"):format(tostring(per)))
            end
        end
    end

    return ok
end

---------------------------------------------------------------------------
-- PDA / UI filtering hooks (optional; only hides disabled in PDA lists)
---------------------------------------------------------------------------
local function applyPdaFilterHooks()
    if IngameMenu == nil then return end

    local function filteredFruitList()
        local list = {}
        if not g_fruitTypeManager or not CropControlOverride._enabledMap then
            -- fallback: just return all fruits
            if g_fruitTypeManager then
                for _, fruit in ipairs(g_fruitTypeManager.fruitTypes) do
                    table.insert(list, fruit)
                end
            end
            return list
        end

        for _, fruit in ipairs(g_fruitTypeManager.fruitTypes) do
            local n = upper(fruit.name)
            if CropControlOverride._enabledMap[n] ~= false then
                table.insert(list, fruit)
            end
        end
        return list
    end

    IngameMenu.onOpen = Utils.appendedFunction(IngameMenu.onOpen, function(menuSelf)
        if CropControlOverride._enabledMap == nil then return end

        -- Crop Calendar
        if menuSelf.cropCalendarFrame and menuSelf.cropCalendarFrame.updateData then
            local orig = menuSelf.cropCalendarFrame.updateData
            function menuSelf.cropCalendarFrame:updateData()
                self.fruitTypes = filteredFruitList()
                if orig then orig(self) end
            end
        end

        -- Map Overview
        if menuSelf.mapOverviewFrame and menuSelf.mapOverviewFrame.updateFruitTypes then
            local orig = menuSelf.mapOverviewFrame.updateFruitTypes
            function menuSelf.mapOverviewFrame:updateFruitTypes()
                self.fruitTypes = filteredFruitList()
                if orig then orig(self) end
            end
        end

        -- Statistics / Prices
        if menuSelf.statisticsFrame and menuSelf.statisticsFrame.updateFruitTypes then
            local orig = menuSelf.statisticsFrame.updateFruitTypes
            function menuSelf.statisticsFrame:updateFruitTypes()
                self.fruitTypes = filteredFruitList()
                if orig then orig(self) end
            end
        end
    end)
end
applyPdaFilterHooks()

---------------------------------------------------------------------------
-- Console helpers
---------------------------------------------------------------------------
function CropControlOverride:consoleReload()
    local sid = getSaveIdFromMissionInfo(g_currentMission and g_currentMission.missionInfo)
    local per = perSavePathForId(sid)
    local tpl = templatePath()
    local path = (per and fileExists(per)) and per or tpl
    local map  = readConfig(path)
    if not next(map) then
        map = buildDefaultEnabledMap()
    end
    self:_applyEnabledMap(map)
    print(("CCO: reload complete from %s"):format(path))
end
addConsoleCommand(
    "ccoReload",
    "Reload CropControlOverride config and reapply",
    "consoleReload",
    CropControlOverride
)

function CropControlOverride:consoleWhichConfig()
    local sid = getSaveIdFromMissionInfo(g_currentMission and g_currentMission.missionInfo)
    local per = perSavePathForId(sid) or "nil"
    local tpl = templatePath()
    local perExists = (per ~= "nil") and fileExists(per)
    local chosen = perExists and per or tpl
    print("CCO: template : " .. tostring(tpl))
    print("CCO: per-save : " .. tostring(per) .. "  (exists=" .. tostring(perExists) .. ")")
    print("CCO: USING    : " .. tostring(chosen))
end
addConsoleCommand(
    "ccoWhichConfig",
    "Show which config file is in use",
    "consoleWhichConfig",
    CropControlOverride
)

function CropControlOverride:consoleListFlags(name)
    local function dump(ft)
        print(("CCO: %s"):format(ft.name))
        print(("  useForFieldJob=%s"):format(tostring(ft.useForFieldJob)))
        print(("  allowsSeeding=%s"):format(tostring(ft.allowsSeeding)))
        print(("  allowsHarvesting=%s"):format(tostring(ft.allowsHarvesting)))
        print(("  allowsGrowing=%s"):format(tostring(ft.allowsGrowing)))
        print(("  needsSeeding=%s"):format(tostring(ft.needsSeeding)))
        print(("  showOnPriceTable=%s"):format(tostring(ft.showOnPriceTable)))
        print(("  showOnMap=%s"):format(tostring(ft.showOnMap)))
        print(("  allowsMapVisualization=%s"):format(tostring(ft.allowsMapVisualization)))
        -- we include isVisibleOnPda if present, for completeness
        print(("  isVisibleOnPda=%s"):format(tostring(ft.isVisibleOnPda)))
    end

    if not g_fruitTypeManager then
        print("CCO: fruit manager not ready")
        return
    end

    if name and name ~= "" then
        local target = upper(name)
        for _, ft in ipairs(g_fruitTypeManager.fruitTypes) do
            if upper(ft.name) == target then
                dump(ft)
                return
            end
        end
        print("CCO: fruit not found: " .. tostring(name))
    else
        for _, ft in ipairs(g_fruitTypeManager.fruitTypes) do
            dump(ft)
        end
    end
end
addConsoleCommand(
    "ccoListFlags",
    "List flag set for a fruit (or all). Usage: ccoListFlags [NAME]",
    "consoleListFlags",
    CropControlOverride
)

-- NEW: helper to find the exact fruitType name (e.g. ONION vs ONIONS)
function CropControlOverride:consoleFindFruit(pattern)
    if not g_fruitTypeManager then
        print("CCO: fruit manager not ready")
        return
    end

    if not pattern or pattern == "" then
        print("CCO: usage ccoFindFruit <namePart>")
        return
    end

    local up = upper(pattern)
    local found = false

    for _, ft in ipairs(g_fruitTypeManager.fruitTypes) do
        local n = upper(ft.name or "")
        if string.find(n, up, 1, true) then  -- plain substring match
            found = true
            print(("CCO: match '%s' (index=%s)"):format(tostring(ft.name), tostring(ft.index)))
        end
    end

    if not found then
        print("CCO: no fruits matching '" .. tostring(pattern) .. "'")
    end
end
addConsoleCommand(
    "ccoFindFruit",
    "Search fruitTypes by substring. Usage: ccoFindFruit <namePart>",
    "consoleFindFruit",
    CropControlOverride
)

---------------------------------------------------------------------------
-- Late hook: re-apply once after the whole mission has loaded
-- This catches DLC fruits (like ONION) that are registered AFTER loadMapData.
---------------------------------------------------------------------------
local _cco_orig_loadMapFinished = FSBaseMission.loadMapFinished

function FSBaseMission:loadMapFinished(...)
    local results
    if _cco_orig_loadMapFinished ~= nil then
        results = { _cco_orig_loadMapFinished(self, ...) }
    end

    if CropControlOverride ~= nil and CropControlOverride._enabledMap ~= nil then
        CropControlOverride:_applyEnabledMap(CropControlOverride._enabledMap)
        print("CCO: reapplied crop config after FSBaseMission:loadMapFinished (late DLC safety)")
    end

    if results ~= nil then
        return unpack(results)
    end
end
