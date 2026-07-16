-- FS25_CropControlOverride
-- Rebuild branch: crop availability + NPC planting policy + NPC field correction.
--
-- Version 2 config remains backward-compatible with the original v1:
--   <fruit name="ONION" enabled="false" />
-- New optional attributes:
--   npcAllowed="false"        -- NPC may never plant this crop
--   npcMaxHa="10"             -- NPC may only plant/use this crop on fields <= 10 ha; 0 = no limit
--   resetNpcFields="true"     -- ccoResetNpcFields may clear NPC fields that violate this rule
--
-- First merged build is intentionally console-driven. UI can be added once the
-- crop policy engine is proven stable in live saves.

CropControlOverride = {
    MOD_ID = g_currentModName or "FS25_CropControlOverride",
    VERSION = "2.1.0.0-alpha.10",

    _origFlags = {},
    _rules = {},
    _configPath = nil,
    _hookApplied = false,
    _sowHookApplied = false,
    _loadFinishedHookApplied = false,
    _startupValidationPrinted = false,
    MOD_DIRECTORY = g_currentModDirectory or "",
    _mpClientOnly = false,
    _awaitingServerSettings = false,
    _serverSettingsSynced = false,
    _serverConfigPath = nil,
    _serverSaveId = nil,
    _serverCanEditRules = false,
    _connectionToMasterUser = {},
    _permissionHooksApplied = false,
    _clientReportedMasterUser = false,
    _seedGuardHooksApplied = false,
    _serverSettingsRetryTimer = 0,
    _serverSettingsRetryCount = 0,
    _npcMapRegenerationPlan = nil,
    _npcMapRegenerationState = nil,
}

local CCO = CropControlOverride
local log = CCO_Debug or Debug or nil

local NPC_FARM_ID = 0
local CONFIG_ROOT = "cropControl"
local SETTINGS_FOLDER = "FS25_CropControlOverride"

local DEFAULT_RESEED_WEIGHTS = {
    leaveCultivated = 1,
}

local DEFAULT_FRUIT_RESEED_WEIGHT = 5

local function clampWeight(value, defaultValue)
    local n = tonumber(value)
    if n == nil then n = tonumber(defaultValue or 0) or 0 end
    n = math.floor(n)
    if n < 0 then n = 0 end
    if n > 5 then n = 5 end
    return n
end

local function normalizeReseedWeights(weights)
    weights = weights or {}
    return {
        leaveCultivated = clampWeight(weights.leaveCultivated, DEFAULT_RESEED_WEIGHTS.leaveCultivated),
    }
end

local FRUIT_FLAG_FIELDS = {
    "useForFieldJob",
    "useForFieldMissions",
    "allowsSeeding",
    "allowsHarvesting",
    "allowsGrowing",
    "needsSeeding",
    "showOnPriceTable",
    "showOnMap",
    "allowsMapVisualization",
    "isVisibleOnPda",
}

local function debug(msg) if log and log.debug then log:debug(msg) end end
local function info(msg) if log and log.info then log:info(msg) else print("CCO [INFO] " .. tostring(msg)) end end
local function warn(msg) if log and log.warn then log:warn(msg) else print("CCO [WARN] " .. tostring(msg)) end end
local function err(msg)  if log and log.error then log:error(msg) else print("CCO [ERROR] " .. tostring(msg)) end end

local function upper(s)
    return s and string.upper(tostring(s)) or s
end


local HA_TO_ACRES = 2.47105

local function formatHaAcCompact(ha)
    local n = tonumber(ha or 0) or 0
    return string.format("%.1fha/%.1fac", n, n * HA_TO_ACRES)
end

local function policyText(v)
    if v == nil then return "Map Default" end
    if v == true then return "Yes" end
    if v == false then return "No" end
    return tostring(v)
end

local function policyTextOnOff(v)
    if v == nil then return "Map Default" end
    if v == true then return "ON" end
    if v == false then return "OFF" end
    return tostring(v)
end

local function boolTextOnOff(v)
    return v and "ON" or "OFF"
end

local function boolFromStringOrBool(v, default)
    if v == nil then return default end
    if type(v) == "boolean" then return v end
    local s = string.lower(tostring(v))
    if s == "true" or s == "1" or s == "yes" or s == "on" or s == "enabled" then return true end
    if s == "false" or s == "0" or s == "no" or s == "off" or s == "disabled" then return false end
    if s == "mapdefault" or s == "map_default" or s == "native" or s == "default" then return nil end
    return default
end

local function ensureSlash(path)
    if path == nil or path == "" then return path end
    local c = path:sub(-1)
    if c ~= "/" and c ~= "\\" then
        return path .. "/"
    end
    return path
end

local function settingsRoot()
    local base = g_modSettingsDirectory
    if base == nil or base == "" then
        base = getUserProfileAppPath() .. "modSettings/"
    end
    return ensureSlash(ensureSlash(base) .. SETTINGS_FOLDER)
end

local function isClientOnlyMultiplayer()
    return g_client ~= nil and g_server == nil
end

local function getLocalMissionMasterUserState()
    if g_currentMission ~= nil and g_currentMission.isMasterUser == true then
        return true
    end
    return false
end

local function ccoCanEditRules()
    -- Single-player, local-host multiplayer and the dedicated server process are
    -- authoritative. Remote dedicated clients are editable only when the player
    -- has elevated to the game master/admin state or the server has confirmed
    -- CCO edit rights for this connection.
    if not isClientOnlyMultiplayer() then
        return true
    end

    if CCO._serverCanEditRules == true then
        return true
    end

    if getLocalMissionMasterUserState() == true then
        return true
    end

    return false
end

local function templatePath()
    return settingsRoot() .. "config.xml"
end

local function getSaveIdFromMissionInfo(mi)
    if mi == nil then return nil end
    if mi.savegameIndex ~= nil and tonumber(mi.savegameIndex) ~= nil then
        return ("savegame%d"):format(tonumber(mi.savegameIndex))
    end
    if mi.savegameDirectory ~= nil and mi.savegameDirectory ~= "" then
        return mi.savegameDirectory:match("([^/\\]+)$")
    end
    return nil
end

local function perSavePathForId(saveId)
    if saveId == nil then return nil end
    return settingsRoot() .. "saves/" .. saveId .. ".xml"
end

local function ensureFolderForFile(path)
    local dir = path and path:match("^(.*)[/\\][^/\\]+$") or nil
    if dir == nil or dir == "" then return end

    -- GIANTS createFolder can normally create the final directory when the
    -- parent exists, but this loop is safer for nested modSettings/saves paths.
    local acc = ""
    for part in string.gmatch(dir, "[^/\\]+") do
        acc = acc .. part .. "/"
        if createFolder ~= nil then
            createFolder(acc)
        end
    end
end

local function getFruitByName(name)
    if g_fruitTypeManager == nil or name == nil then return nil end
    local target = upper(name)
    for _, ft in ipairs(g_fruitTypeManager.fruitTypes) do
        if upper(ft.name) == target then
            return ft
        end
    end
    return nil
end

local function iterFruitTypesSorted()
    local list = {}
    if g_fruitTypeManager ~= nil and g_fruitTypeManager.fruitTypes ~= nil then
        for _, ft in ipairs(g_fruitTypeManager.fruitTypes) do
            if ft ~= nil and ft.name ~= nil then
                table.insert(list, ft)
            end
        end
    end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return list
end

local function getCurrentPeriodIndex()
    -- FS25 generally exposes the current seasonal period through environment/currentPeriod.
    -- Keep this deliberately defensive because custom maps/mods can alter environment data.
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local period = nil

    if env ~= nil then
        period = env.currentPeriod or env.period or env.currentSeasonPeriod
        if period == nil and env.getCurrentPeriod ~= nil then
            local ok, result = pcall(function() return env:getCurrentPeriod() end)
            if ok then period = result end
        end
        if period == nil and env.getPeriod ~= nil then
            local ok, result = pcall(function() return env:getPeriod() end)
            if ok then period = result end
        end
    end

    period = tonumber(period)
    if period ~= nil then
        return math.floor(period)
    end

    -- Fallback for non-seasonal or unknown runtime: month is usually 1-12 if present.
    if env ~= nil then
        local month = tonumber(env.currentMonth or env.month)
        if month ~= nil then return math.floor(month) end
    end

    return nil
end

local function tableHasPeriod(value, period)
    if value == nil or period == nil then return nil end

    if type(value) == "table" then
        -- Common patterns are either boolean arrays indexed by period, or arrays of period numbers.
        local direct = value[period]
        if direct ~= nil then
            if type(direct) == "boolean" then return direct end
            if tonumber(direct) ~= nil then return tonumber(direct) ~= 0 end
            return true
        end

        for _, v in pairs(value) do
            if tonumber(v) == period then return true end
            if type(v) == "table" then
                local first = tonumber(v[1] or v.start or v.from)
                local last = tonumber(v[2] or v.finish or v.to or v["end"])
                if first ~= nil and last ~= nil then
                    if first <= last then
                        if period >= first and period <= last then return true end
                    else
                        -- wrap around year end
                        if period >= first or period <= last then return true end
                    end
                end
            end
        end
        return false
    end

    return nil
end

local SEEDING_KEY_HINTS = {
    "plant", "seed", "sow", "seeding", "sowing", "planting"
}

local function keyLooksLikeSeeding(key)
    local s = string.lower(tostring(key or ""))
    for _, hint in ipairs(SEEDING_KEY_HINTS) do
        if s:find(hint, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function trySeasonalContainer(container, period, label, depth)
    if container == nil or type(container) ~= "table" or period == nil then return nil end
    depth = tonumber(depth or 0) or 0
    if depth > 3 then return nil end

    -- Prefer explicitly named sowing/seeding/planting keys first.
    for key, value in pairs(container) do
        if keyLooksLikeSeeding(key) then
            local result = tableHasPeriod(value, period)
            if result ~= nil then
                return result == true, ("%s.%s"):format(tostring(label), tostring(key))
            end

            if type(value) == "table" then
                local ok, source = trySeasonalContainer(value, period, ("%s.%s"):format(tostring(label), tostring(key)), depth + 1)
                if ok ~= nil then return ok, source end
            end
        end
    end

    -- Some structures are nested by fruit/growth period without obvious key names.
    -- Only recurse shallowly here; do not guess from unrelated scalar values.
    for key, value in pairs(container) do
        if type(value) == "table" then
            local ok, source = trySeasonalContainer(value, period, ("%s.%s"):format(tostring(label), tostring(key)), depth + 1)
            if ok ~= nil then return ok, source end
        end
    end

    return nil
end

local SEEDING_PERIOD_FIELDS = {
    "seedingPeriods",
    "seedingPeriod",
    "plantingPeriods",
    "plantingPeriod",
    "sowingPeriods",
    "sowingPeriod",
}

local function getSeasonalSowingStatus(ft)
    local period = getCurrentPeriodIndex()
    if ft == nil then return true, "no fruit type", period end

    if period == nil then
        return nil, "season period unavailable", nil
    end

    for _, key in ipairs(SEEDING_PERIOD_FIELDS) do
        local result = tableHasPeriod(ft[key], period)
        if result ~= nil then
            return result == true, result == true and ("seasonal period " .. tostring(period) .. " allowed by " .. key) or ("outside seasonal period " .. tostring(period) .. " via " .. key), period
        end
    end

    -- FS25 exposes planting windows through growthDataSeasonal.periods[period].plantingAllowed.
    if ft.growthDataSeasonal ~= nil and type(ft.growthDataSeasonal) == "table" then
        local periods = ft.growthDataSeasonal.periods
        if type(periods) == "table" then
            local periodData = periods[period]
            if type(periodData) == "table" and periodData.plantingAllowed ~= nil then
                local allowed = periodData.plantingAllowed == true
                return allowed,
                    allowed and ("seasonal period " .. tostring(period) .. " plantingAllowed=true")
                        or ("seasonal period " .. tostring(period) .. " plantingAllowed=false"),
                    period
            end
        end

        local seasonalResult, seasonalSource = trySeasonalContainer(ft.growthDataSeasonal, period, "growthDataSeasonal", 0)
        if seasonalResult ~= nil then
            return seasonalResult == true,
                seasonalResult == true and ("seasonal period " .. tostring(period) .. " allowed by " .. tostring(seasonalSource))
                    or ("outside seasonal period " .. tostring(period) .. " via " .. tostring(seasonalSource)),
                period
        end
    end

    -- Some fruit types may expose a data table with the same fields.
    if ft.data ~= nil then
        for _, key in ipairs(SEEDING_PERIOD_FIELDS) do
            local result = tableHasPeriod(ft.data[key], period)
            if result ~= nil then
                return result == true, result == true and ("seasonal period " .. tostring(period) .. " allowed by data." .. key) or ("outside seasonal period " .. tostring(period) .. " via data." .. key), period
            end
        end

        local seasonalResult, seasonalSource = trySeasonalContainer(ft.data, period, "data", 0)
        if seasonalResult ~= nil then
            return seasonalResult == true,
                seasonalResult == true and ("seasonal period " .. tostring(period) .. " allowed by " .. tostring(seasonalSource))
                    or ("outside seasonal period " .. tostring(period) .. " via " .. tostring(seasonalSource)),
                period
        end
    end

    return nil, "no seasonal sowing data exposed", period
end

local function getFieldSizeHa(field)
    if field == nil then return 0 end

    -- Prefer the actual field/cultivated area over the farmland/plot area.
    -- Farmland plots can contain roads, yards, woodland or several field pieces, so
    -- using farmland.areaInHa can wrongly block small fields on large plots.
    local candidates = {
        field.areaHa,
        field.fieldAreaHa,
        field.fieldArea,
        field.area,
        field.sizeHa,
    }

    for _, value in ipairs(candidates) do
        local n = tonumber(value)
        if n ~= nil and n > 0 then
            return n
        end
    end

    if field.fieldDimensions ~= nil and field.fieldDimensions.areaInHa ~= nil then
        local n = tonumber(field.fieldDimensions.areaInHa)
        if n ~= nil and n > 0 then return n end
    end

    -- Last resort only: this is plot/farmland area, not necessarily field area.
    if field.farmland ~= nil and field.farmland.areaInHa ~= nil then
        local n = tonumber(field.farmland.areaInHa)
        if n ~= nil and n > 0 then return n end
    end

    return 0
end

local function isNpcField(field)
    local farmId = (field ~= nil and field.farmland ~= nil and field.farmland.farmId) or NPC_FARM_ID
    return farmId == NPC_FARM_ID
end

local function getFieldId(field, fallback)
    if field ~= nil and field.farmland ~= nil and field.farmland.id ~= nil then
        return field.farmland.id
    end
    return fallback or "?"
end

local function getFieldFruit(field)
    if field == nil or field.fieldState == nil then return nil, nil end
    local index = field.fieldState.fruitTypeIndex
    if index == nil or index == 0 or index == FruitType.UNKNOWN then return nil, index end
    if g_fruitTypeManager == nil then return nil, index end
    return g_fruitTypeManager:getFruitTypeByIndex(index), index
end

local function normalizeRule(name, rule)
    rule = rule or {}
    local nameU = upper(name or rule.name)
    if nameU == nil or nameU == "" then return nil end

    local enabled = rule.enabled
    if enabled == nil then enabled = true end

    local npcAllowed = rule.npcAllowed
    -- disabled globally means NPC disabled too unless explicitly re-enabled,
    -- which we intentionally do not support because it would be contradictory.
    if enabled == false then npcAllowed = false end

    local npcMaxHa = tonumber(rule.npcMaxHa or rule.maxHa or 0) or 0
    if npcMaxHa < 0 then npcMaxHa = 0 end

    local resetNpcFields = rule.resetNpcFields
    if resetNpcFields == nil then
        resetNpcFields = true
    end

    return {
        name = nameU,
        enabled = enabled ~= false,
        npcAllowed = npcAllowed,
        npcMaxHa = npcMaxHa,
        resetNpcFields = resetNpcFields ~= false,
        reseedWeight = clampWeight(rule.reseedWeight, DEFAULT_FRUIT_RESEED_WEIGHT),
    }
end

local function defaultRuleForFruit(ft)
    return normalizeRule(ft and ft.name, {
        enabled = true,
        npcAllowed = nil,
        npcMaxHa = 0,
        resetNpcFields = true,
        reseedWeight = DEFAULT_FRUIT_RESEED_WEIGHT,
    })
end

function CCO:_snapshotFruitIfNeeded(nameU, fruit)
    if nameU == nil or fruit == nil or self._origFlags[nameU] ~= nil then return end
    local snap = {}
    for _, key in ipairs(FRUIT_FLAG_FIELDS) do
        snap[key] = fruit[key]
    end
    self._origFlags[nameU] = snap
end

function CCO:_restoreFruitFlags(nameU, fruit)
    local snap = self._origFlags[nameU]
    if snap ~= nil then
        for _, key in ipairs(FRUIT_FLAG_FIELDS) do
            if snap[key] ~= nil or fruit[key] ~= nil then
                fruit[key] = snap[key]
            end
        end
        return
    end

    -- Permissive fallback for very late fruit types without a snapshot.
    if fruit.useForFieldJob ~= nil then fruit.useForFieldJob = true end
    if fruit.useForFieldMissions ~= nil then fruit.useForFieldMissions = true end
    if fruit.allowsSeeding ~= nil then fruit.allowsSeeding = true end
    if fruit.allowsHarvesting ~= nil then fruit.allowsHarvesting = true end
    if fruit.allowsGrowing ~= nil then fruit.allowsGrowing = true end
    if fruit.showOnPriceTable ~= nil then fruit.showOnPriceTable = true end
end

function CCO:_applyDisabledFlags(fruit)
    fruit.useForFieldJob = false
    fruit.useForFieldMissions = false
    fruit.allowsSeeding = false
    fruit.allowsHarvesting = false
    fruit.allowsGrowing = false
    fruit.needsSeeding = false
    fruit.showOnPriceTable = false
    -- Deliberately leave map visualization flags alone by default, matching the
    -- previous CCO behaviour. PDA list hooks below hide disabled entries where possible.
end

function CCO:_applyNpcBlockedFlags(fruit)
    -- NPC-only rules are enforced in FieldManager.generatePlannedFruitForField
    -- and mission availability hooks. Do not mutate global fruit mission flags here;
    -- doing so can cause contract-list flicker and affects player-facing crop data.
end

function CCO:applyRules(rules)
    if g_fruitTypeManager == nil then return end
    rules = rules or self._rules or {}

    for _, fruit in ipairs(g_fruitTypeManager.fruitTypes) do
        local nameU = upper(fruit.name)
        self:_snapshotFruitIfNeeded(nameU, fruit)
        self:_restoreFruitFlags(nameU, fruit)

        local rule = rules[nameU]
        if rule == nil then
            rule = defaultRuleForFruit(fruit)
            rules[nameU] = rule
        end

        if rule.enabled == false then
            self:_applyDisabledFlags(fruit)
        elseif rule.npcAllowed == false then
            self:_applyNpcBlockedFlags(fruit)
        end
    end

    self._rules = rules

    -- Fruit flags only influence data that is built AFTER this point. Sowing
    -- machines that are already loaded cached their seed list at vehicle load
    -- time, so a mid-session rule change (GUI APPLY, server sync on a remote
    -- client) never reached them. Rebuild those cached lists now.
    local ok, e = pcall(function() self:refreshAllSowingMachines() end)
    if not ok then debug("refreshAllSowingMachines skipped: " .. tostring(e)) end
end

local function buildDefaultRules()
    local rules = {}
    for _, ft in ipairs(iterFruitTypesSorted()) do
        local rule = defaultRuleForFruit(ft)
        if rule ~= nil then rules[rule.name] = rule end
    end
    return rules
end

local function readConfig(path)
    local rules = {}
    local settings = { reseedWeights = normalizeReseedWeights(nil) }
    if path == nil or not fileExists(path) then return rules, settings end

    local xml = XMLFile.load("CCO_read", path, CONFIG_ROOT)
    if xml == nil then return rules, settings end

    local weightsKey = CONFIG_ROOT .. ".settings.reseedCandidateWeights"
    if xml:hasProperty(weightsKey) then
        settings.reseedWeights = normalizeReseedWeights({
            leaveCultivated = xml:getInt(weightsKey .. "#leaveCultivated", DEFAULT_RESEED_WEIGHTS.leaveCultivated),
        })
    end

    local i = 0
    local count = 0
    while true do
        local k = ("%s.fruits.fruit(%d)"):format(CONFIG_ROOT, i)
        if not xml:hasProperty(k) then break end

        local name = xml:getString(k .. "#name")
        if name ~= nil and name ~= "" then
            local enabled = xml:getBool(k .. "#enabled", true)
            local npcAllowed = nil
            if xml:hasProperty(k .. "#npcAllowed") then
                npcAllowed = boolFromStringOrBool(xml:getString(k .. "#npcAllowed"), nil)
                if npcAllowed == nil and xml:getString(k .. "#npcAllowed") ~= "mapDefault" then
                    npcAllowed = xml:getBool(k .. "#npcAllowed", nil)
                end
            end
            local npcMaxHa = xml:getFloat(k .. "#npcMaxHa", xml:getFloat(k .. "#maxHa", 0))
            local resetNpcFields = xml:getBool(k .. "#resetNpcFields", true)

            local rule = normalizeRule(name, {
                enabled = enabled,
                npcAllowed = npcAllowed,
                npcMaxHa = npcMaxHa,
                resetNpcFields = resetNpcFields,
                reseedWeight = xml:getInt(k .. "#reseedWeight", DEFAULT_FRUIT_RESEED_WEIGHT),
            })
            if rule ~= nil then
                rules[rule.name] = rule
                count = count + 1
            end
        end
        i = i + 1
    end

    -- Backward compatibility with old flat layout:
    -- <cropControl><fruit name="..." enabled="..."/></cropControl>
    if count == 0 then
        local function readLegacyNode(k)
            local name = xml:getString(k .. "#name")
            if name ~= nil and name ~= "" then
                local enabled = xml:getBool(k .. "#enabled", true)
                local npcAllowed = nil
                if xml:hasProperty(k .. "#npcAllowed") then
                    npcAllowed = boolFromStringOrBool(xml:getString(k .. "#npcAllowed"), nil)
                else
                    npcAllowed = enabled == false and false or nil
                end
                local rule = normalizeRule(name, {
                    enabled = enabled,
                    npcAllowed = npcAllowed,
                    npcMaxHa = xml:getFloat(k .. "#npcMaxHa", xml:getFloat(k .. "#maxHa", 0)),
                    resetNpcFields = xml:getBool(k .. "#resetNpcFields", true),
                    reseedWeight = xml:getInt(k .. "#reseedWeight", DEFAULT_FRUIT_RESEED_WEIGHT),
                })
                if rule ~= nil then rules[rule.name] = rule end
            end
        end

        i = 0
        while true do
            local k = ("%s.fruit(%d)"):format(CONFIG_ROOT, i)
            if not xml:hasProperty(k) then break end
            readLegacyNode(k)
            i = i + 1
        end

        i = 0
        while true do
            local k = ("%s.crops.crop(%d)"):format(CONFIG_ROOT, i)
            if not xml:hasProperty(k) then break end
            readLegacyNode(k)
            i = i + 1
        end

        i = 0
        while true do
            local k = ("%s.crop(%d)"):format(CONFIG_ROOT, i)
            if not xml:hasProperty(k) then break end
            readLegacyNode(k)
            i = i + 1
        end
    end

    xml:delete()
    return rules, settings
end

local function inspectConfigNormalization(path)
    local meta = {
        exists = false,
        needsNormalize = false,
        version = nil,
        nestedCount = 0,
        flatCount = 0,
        missingAttrs = 0,
        reasons = {},
    }

    if path == nil or not fileExists(path) then return meta end
    meta.exists = true

    local xml = XMLFile.load("CCO_inspect", path, CONFIG_ROOT)
    if xml == nil then
        meta.needsNormalize = true
        table.insert(meta.reasons, "xml load failed")
        return meta
    end

    meta.version = xml:getString(CONFIG_ROOT .. "#version")
    if tostring(meta.version or "") ~= "2" then
        meta.needsNormalize = true
        table.insert(meta.reasons, "config version is not 2")
    end

    local function inspectNode(k)
        local name = xml:getString(k .. "#name")
        if name ~= nil and name ~= "" then
            meta.nestedCount = meta.nestedCount + 1
            if not xml:hasProperty(k .. "#npcAllowed") then meta.missingAttrs = meta.missingAttrs + 1 end
            if not xml:hasProperty(k .. "#npcMaxHa") and not xml:hasProperty(k .. "#maxHa") then meta.missingAttrs = meta.missingAttrs + 1 end
            if not xml:hasProperty(k .. "#resetNpcFields") then meta.missingAttrs = meta.missingAttrs + 1 end
            if not xml:hasProperty(k .. "#reseedWeight") then meta.missingAttrs = meta.missingAttrs + 1 end
        end
    end

    local i = 0
    while true do
        local k = ("%s.fruits.fruit(%d)"):format(CONFIG_ROOT, i)
        if not xml:hasProperty(k) then break end
        inspectNode(k)
        i = i + 1
    end

    local flatFruitCount = 0
    i = 0
    while true do
        local k = ("%s.fruit(%d)"):format(CONFIG_ROOT, i)
        if not xml:hasProperty(k) then break end
        local name = xml:getString(k .. "#name")
        if name ~= nil and name ~= "" then flatFruitCount = flatFruitCount + 1 end
        i = i + 1
    end

    local flatCropCount = 0
    i = 0
    while true do
        local k = ("%s.crops.crop(%d)"):format(CONFIG_ROOT, i)
        if not xml:hasProperty(k) then break end
        local name = xml:getString(k .. "#name")
        if name ~= nil and name ~= "" then flatCropCount = flatCropCount + 1 end
        i = i + 1
    end

    i = 0
    while true do
        local k = ("%s.crop(%d)"):format(CONFIG_ROOT, i)
        if not xml:hasProperty(k) then break end
        local name = xml:getString(k .. "#name")
        if name ~= nil and name ~= "" then flatCropCount = flatCropCount + 1 end
        i = i + 1
    end

    meta.flatCount = flatFruitCount + flatCropCount
    if meta.flatCount > 0 then
        meta.needsNormalize = true
        table.insert(meta.reasons, "legacy flat crop/fruit layout")
    end
    if meta.missingAttrs > 0 then
        meta.needsNormalize = true
        table.insert(meta.reasons, ("missing v2 attributes=%d"):format(meta.missingAttrs))
    end

    xml:delete()
    return meta
end

local function describeNormalization(meta)
    if meta == nil then return "unknown" end
    if meta.reasons == nil or #meta.reasons == 0 then return "no changes needed" end
    return table.concat(meta.reasons, "; ")
end

local function mergeMissingDiscoveredFruits(rules)
    rules = rules or {}
    for _, ft in ipairs(iterFruitTypesSorted()) do
        local nameU = upper(ft.name)
        if rules[nameU] == nil then
            rules[nameU] = defaultRuleForFruit(ft)
        end
    end
    return rules
end

local function writeConfig(path, rules, settings)
    if path == nil then return false end
    ensureFolderForFile(path)

    local xml = XMLFile.create("CCO_write", path, CONFIG_ROOT)
    if xml == nil then
        err("cannot create config at " .. tostring(path))
        return false
    end

    xml:setString(CONFIG_ROOT .. "#version", "2")
    xml:setString(CONFIG_ROOT .. "#modVersion", CCO.VERSION)

    local reseedWeights = normalizeReseedWeights(settings ~= nil and settings.reseedWeights or nil)
    local weightsKey = CONFIG_ROOT .. ".settings.reseedCandidateWeights"
    xml:setInt(weightsKey .. "#leaveCultivated", reseedWeights.leaveCultivated)

    local names = {}
    for nameU, _ in pairs(rules or {}) do table.insert(names, nameU) end
    table.sort(names)

    local i = 0
    for _, nameU in ipairs(names) do
        local rule = normalizeRule(nameU, rules[nameU])
        if rule ~= nil then
            local k = ("%s.fruits.fruit(%d)"):format(CONFIG_ROOT, i)
            xml:setString(k .. "#name", rule.name)
            xml:setBool(k .. "#enabled", rule.enabled ~= false)
            if rule.npcAllowed == nil then
                xml:setString(k .. "#npcAllowed", "mapDefault")
            else
                xml:setBool(k .. "#npcAllowed", rule.npcAllowed ~= false)
            end
            xml:setFloat(k .. "#npcMaxHa", rule.npcMaxHa or 0)
            xml:setBool(k .. "#resetNpcFields", rule.resetNpcFields ~= false)
            xml:setInt(k .. "#reseedWeight", rule.reseedWeight)
            i = i + 1
        end
    end

    xml:save()
    xml:delete()
    return true
end

local function ensureTemplateExists()
    local tpl = templatePath()
    if fileExists(tpl) then return tpl end
    local rules = buildDefaultRules()
    if writeConfig(tpl, rules, { reseedWeights = normalizeReseedWeights(nil) }) then
        debug("wrote default template at " .. tpl)
    end
    return tpl
end


local function serializeRulesForMultiplayer(rules, settings)
    local lines = {}
    local weights = normalizeReseedWeights(settings ~= nil and settings.reseedWeights or nil)
    table.insert(lines, ("@weights|%d"):format(weights.leaveCultivated))

    local names = {}
    for nameU, _ in pairs(rules or {}) do table.insert(names, nameU) end
    table.sort(names)

    for _, nameU in ipairs(names) do
        local rule = normalizeRule(nameU, rules[nameU])
        if rule ~= nil then
            local npc = "M"
            if rule.npcAllowed == true then npc = "1" elseif rule.npcAllowed == false then npc = "0" end
            table.insert(lines, table.concat({
                tostring(rule.name or nameU),
                rule.enabled ~= false and "1" or "0",
                npc,
                tostring(tonumber(rule.npcMaxHa or 0) or 0),
                rule.resetNpcFields ~= false and "1" or "0",
                tostring(rule.reseedWeight),
            }, "|"))
        end
    end

    return table.concat(lines, "\n")
end

local function deserializeRulesFromMultiplayer(payload)
    local rules = {}
    local settings = { reseedWeights = normalizeReseedWeights(nil) }
    payload = tostring(payload or "")

    for line in (payload .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then
            local parts = {}
            for part in (line .. "|"):gmatch("(.-)|") do
                table.insert(parts, part)
            end

            if parts[1] == "@weights" then
                -- New payloads store leaveCultivated as the only global weight.
                -- Legacy payloads used mission|lifecycle|leaveCultivated.
                local leaveValue = tonumber(parts[2])
                if parts[4] ~= nil and parts[4] ~= "" then leaveValue = tonumber(parts[4]) end
                settings.reseedWeights = normalizeReseedWeights({ leaveCultivated = leaveValue })
            else
                local nameU = upper(parts[1] or "")
                if nameU ~= "" then
                    local npcAllowed = nil
                    if parts[3] == "1" then npcAllowed = true elseif parts[3] == "0" then npcAllowed = false end
                    rules[nameU] = normalizeRule(nameU, {
                        enabled = parts[2] ~= "0",
                        npcAllowed = npcAllowed,
                        npcMaxHa = tonumber(parts[4] or 0) or 0,
                        resetNpcFields = parts[5] ~= "0",
                        reseedWeight = tonumber(parts[6]),
                    })
                end
            end
        end
    end

    if rules == nil or not next(rules) then
        rules = buildDefaultRules()
    end
    rules = mergeMissingDiscoveredFruits(rules)
    return rules, settings
end

function CCO:loadRulesForMission(missionInfo)
    if isClientOnlyMultiplayer() then
        self._mpClientOnly = true
        self._awaitingServerSettings = true
        self._serverSettingsSynced = false
        self._serverCanEditRules = false
        self._serverSaveId = getSaveIdFromMissionInfo(missionInfo)
        self._configPath = "server:pending"
        self._rules = mergeMissingDiscoveredFruits(buildDefaultRules())
        self._settings = { reseedWeights = normalizeReseedWeights(nil) }
        self:requestServerSettings("loadRulesForMission")
        return self._rules, self._configPath
    end

    self._mpClientOnly = false
    self._awaitingServerSettings = false
    local saveId = getSaveIdFromMissionInfo(missionInfo)
    local per = perSavePathForId(saveId)
    local tpl = ensureTemplateExists()

    local path = tpl
    local rules = nil
    local settings = { reseedWeights = normalizeReseedWeights(nil) }

    if per ~= nil and fileExists(per) then
        path = per
        local meta = inspectConfigNormalization(per)
        rules, settings = readConfig(per)
        if rules == nil or not next(rules) then rules = buildDefaultRules() end
        settings = settings or { reseedWeights = normalizeReseedWeights(nil) }
        rules = mergeMissingDiscoveredFruits(rules)
        if meta ~= nil and meta.needsNormalize then
            if writeConfig(per, rules, settings) then
                debug(("normalized legacy per-save config at %s (%s)"):format(per, describeNormalization(meta)))
            end
        end
    else
        local meta = inspectConfigNormalization(tpl)
        rules, settings = readConfig(tpl)
        if not next(rules) then rules = buildDefaultRules() end
        settings = settings or { reseedWeights = normalizeReseedWeights(nil) }
        rules = mergeMissingDiscoveredFruits(rules)
        if per ~= nil and writeConfig(per, rules, settings) then
            path = per
            if meta ~= nil and meta.needsNormalize then
                debug(("created per-save config from legacy template at %s (%s)"):format(per, describeNormalization(meta)))
            else
                debug("created per-save config at " .. per)
            end
        end
    end

    if rules == nil or not next(rules) then
        rules = buildDefaultRules()
    end

    rules = mergeMissingDiscoveredFruits(rules)
    self._configPath = path
    self._rules = rules
    self._settings = settings or { reseedWeights = normalizeReseedWeights(nil) }
    return rules, path
end

function CCO:isNpcCropAllowedForField(fieldHa, cropName)
    if cropName == nil then return true, "no crop" end
    local rule = self._rules and self._rules[upper(cropName)] or nil
    if rule == nil then return true, "no rule" end

    if rule.enabled == false then
        return false, "crop disabled"
    end
    if rule.npcAllowed == false then
        return false, "npc disabled"
    end
    if rule.npcMaxHa ~= nil and rule.npcMaxHa > 0 and fieldHa > rule.npcMaxHa then
        return false, ("field %.2f ha > max %.2f ha"):format(fieldHa, rule.npcMaxHa)
    end
    return true, "allowed"
end

function CCO:shouldResetNpcField(field, cropName)
    if not isNpcField(field) then return false, "not NPC field" end
    local rule = self._rules and self._rules[upper(cropName)] or nil
    if rule ~= nil and rule.resetNpcFields == false then
        return false, "reset disabled for crop"
    end
    local allowed, reason = self:isNpcCropAllowedForField(getFieldSizeHa(field), cropName)
    return not allowed, reason
end


-- Player seeding enforcement --------------------------------------------------
-- Fruit flags (allowsSeeding etc.) are only read when data structures are
-- BUILT, most importantly the per-vehicle seed list a sowing machine creates in
-- onLoad. They are not consulted again while sowing. These helpers provide
-- (a) a live policy check, (b) rebuilding of cached seed lists, and (c) a
-- last-line guard on the actual sowing work so a disabled crop can never be
-- planted regardless of when the rules arrived (GUI apply, server sync, etc).

function CCO:isFruitIndexAllowedForPlayer(fruitTypeIndex)
    if fruitTypeIndex == nil then return true end
    if self._rules == nil then return true end
    local ft = g_fruitTypeManager ~= nil and g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex) or nil
    if ft == nil or ft.name == nil then return true end
    local rule = self._rules[upper(ft.name)]
    if rule == nil then return true end
    return rule.enabled ~= false
end

local function getSowingMachineSpec(vehicle)
    if vehicle == nil then return nil end
    return vehicle.spec_sowingMachine
end

function CCO:getVehicleSelectedSeedFruitIndex(vehicle)
    local spec = getSowingMachineSpec(vehicle)
    if spec == nil then return nil end

    -- Prefer the fruit the work area is actually planting right now.
    if spec.workAreaParameters ~= nil and spec.workAreaParameters.seedsFruitType ~= nil then
        local n = tonumber(spec.workAreaParameters.seedsFruitType)
        if n ~= nil and n > 0 then return n end
    end

    local seeds = spec.seeds
    local index = tonumber(spec.currentSeed or spec.seedIndex)
    if type(seeds) == "table" and index ~= nil then
        local n = tonumber(seeds[index])
        if n ~= nil and n > 0 then return n end
    end
    return nil
end

function CCO:filterSowingMachineSeeds(vehicle)
    local spec = getSowingMachineSpec(vehicle)
    if spec == nil or type(spec.seeds) ~= "table" then return false end

    -- Remember the vehicle's full seed list once, so re-enabling a crop later
    -- restores it without a reload.
    if type(spec.ccoOriginalSeeds) ~= "table" then
        spec.ccoOriginalSeeds = {}
        for i, fruitIndex in ipairs(spec.seeds) do
            spec.ccoOriginalSeeds[i] = fruitIndex
        end
    end

    local previousSelected = nil
    local selIndex = tonumber(spec.currentSeed or spec.seedIndex)
    if selIndex ~= nil and spec.seeds[selIndex] ~= nil then
        previousSelected = spec.seeds[selIndex]
    end

    local filtered = {}
    local removed = 0
    for _, fruitIndex in ipairs(spec.ccoOriginalSeeds) do
        if self:isFruitIndexAllowedForPlayer(fruitIndex) then
            table.insert(filtered, fruitIndex)
        else
            removed = removed + 1
        end
    end

    -- Never leave the spec with an empty list if the engine does not expect
    -- one; the processSowingMachineArea guard still blocks disabled crops.
    if #filtered == 0 then
        filtered = spec.ccoOriginalSeeds
    end

    -- Replace contents in-place so any engine references to the table survive.
    for i = #spec.seeds, 1, -1 do spec.seeds[i] = nil end
    for i, fruitIndex in ipairs(filtered) do spec.seeds[i] = fruitIndex end

    -- Keep the current selection valid; move to the same fruit if it survived,
    -- otherwise snap to the first allowed entry.
    local newIndex = 1
    if previousSelected ~= nil then
        for i, fruitIndex in ipairs(spec.seeds) do
            if fruitIndex == previousSelected then newIndex = i break end
        end
    end
    if spec.currentSeed ~= nil then
        if vehicle.setSeedIndex ~= nil then
            pcall(function() vehicle:setSeedIndex(newIndex) end)
        else
            spec.currentSeed = math.min(math.max(1, newIndex), #spec.seeds)
        end
    elseif spec.seedIndex ~= nil then
        spec.seedIndex = math.min(math.max(1, newIndex), #spec.seeds)
    end

    return removed > 0
end

local function iterMissionVehicles()
    local vehicles = nil
    if g_currentMission ~= nil then
        vehicles = g_currentMission.vehicles
        if vehicles == nil and g_currentMission.vehicleSystem ~= nil then
            vehicles = g_currentMission.vehicleSystem.vehicles
        end
    end
    return vehicles or {}
end

function CCO:refreshAllSowingMachines()
    local refreshed = 0
    for _, vehicle in pairs(iterMissionVehicles()) do
        if getSowingMachineSpec(vehicle) ~= nil then
            local ok, changed = pcall(function() return self:filterSowingMachineSeeds(vehicle) end)
            if ok and changed == true then refreshed = refreshed + 1 end
        end
    end
    if refreshed > 0 then
        debug(("rebuilt seed lists on %d loaded sowing machine(s)"):format(refreshed))
    end
    return refreshed
end


local CCO_SPECIAL_RESEED_EXCLUSIONS = {
    GRAPE = true,
    OLIVE = true,
    POPLAR = true,
    MEADOW = true,
    OILSEEDRADISH = true,
    RICE = true,
    RICELONGGRAIN = true,
}

local CCO_LIFECYCLE_RESEED_CROPS = {
    GRASS = true,
}

function isFruitUsableForNpcCandidate(ft)
    if ft == nil or ft.name == nil then return false, "invalid fruit", "blocked" end

    local cropName = upper(ft.name)

    if CCO_SPECIAL_RESEED_EXCLUSIONS[cropName] == true then
        return false, "special crop excluded from reseed candidates", "blocked"
    end

    if ft.allowsSeeding == false then
        return false, "allowsSeeding=false", "blocked"
    end

    -- Standard arable mission crops are preferred.
    if ft.useForFieldMissions ~= false and ft.useForFieldJob ~= false then
        return true, "engine mission flags ok", "mission"
    end

    -- Some lifecycle crops, notably GRASS, are not marked as standard field-mission crops
    -- but are still seeded/maintained by the game and can generate grasswork contracts.
    if CCO_LIFECYCLE_RESEED_CROPS[cropName] == true then
        return true, "lifecycle crop allowed", "lifecycle"
    end

    if ft.useForFieldMissions == false then return false, "useForFieldMissions=false", "blocked" end
    if ft.useForFieldJob == false then return false, "useForFieldJob=false", "blocked" end

    return true, "engine flags ok", "mission"
end

function CCO:buildNpcCandidatesForField(field, includeBlocked)
    local candidates = {}
    if field == nil then return candidates end

    local fieldHa = getFieldSizeHa(field)
    for _, ft in ipairs(iterFruitTypesSorted()) do
        local cropName = upper(ft.name)
        local flagOk, flagReason, category = isFruitUsableForNpcCandidate(ft)
        local policyOk, policyReason = self:isNpcCropAllowedForField(fieldHa, cropName)
        local seasonOk, seasonReason, seasonPeriod = getSeasonalSowingStatus(ft)
        local ok = flagOk and policyOk
        local seasonalKnown = seasonOk ~= nil
        local seasonalOk = ok and seasonOk == true

        if includeBlocked == true or ok then
            local rule = self._rules and self._rules[cropName] or nil
            local limited = rule ~= nil and rule.npcMaxHa ~= nil and rule.npcMaxHa > 0
            local explicitNpcAllowed = rule ~= nil and rule.npcAllowed == true
            local priority = 50
            if seasonalOk and limited and category == "mission" then
                priority = 10
            elseif seasonalOk and explicitNpcAllowed and category == "mission" then
                priority = 20
            elseif seasonalOk and category == "mission" then
                priority = 30
            elseif seasonalOk and category == "lifecycle" then
                priority = 35
            elseif ok and category == "mission" then
                priority = 80
            elseif ok then
                priority = 90
            end

            table.insert(candidates, {
                fruit = ft,
                cropName = cropName,
                ok = ok,
                seasonalKnown = seasonalKnown,
                seasonalOk = seasonalOk,
                seasonPeriod = seasonPeriod,
                seasonReason = seasonReason,
                reason = ok and "allowed" or (not flagOk and flagReason or policyReason),
                category = category or "blocked",
                limited = limited,
                explicitNpcAllowed = explicitNpcAllowed,
                priority = priority,
            })
        end
    end

    table.sort(candidates, function(a, b)
        if a.ok ~= b.ok then return a.ok and not b.ok end
        if a.priority ~= b.priority then return a.priority < b.priority end
        return tostring(a.cropName) < tostring(b.cropName)
    end)

    return candidates
end


function CCO:getReseedWeights()
    local settings = self._settings or {}
    return normalizeReseedWeights(settings.reseedWeights)
end

function CCO:buildWeightedReseedPool(candidates)
    local weights = self:getReseedWeights()
    local pool = {}

    for _, c in ipairs(candidates or {}) do
        if c ~= nil and c.ok == true and c.seasonalOk == true then
            local rule = self._rules ~= nil and self._rules[c.cropName] or nil
            local weight = clampWeight(rule ~= nil and rule.reseedWeight or nil, DEFAULT_FRUIT_RESEED_WEIGHT)

            for _ = 1, weight do
                table.insert(pool, c)
            end
        end
    end

    for _ = 1, weights.leaveCultivated do
        table.insert(pool, {
            cropName = "NONE",
            category = "leaveCultivated",
            ok = true,
            seasonalOk = true,
            seasonalKnown = true,
            priority = 30,
            fruit = nil,
            reason = "authoritative weighted leave cultivated", authoritative = true,
        })
    end

    return pool, weights
end


function CCO:findReplacementNpcCropForField(field, blockedCropName)
    local candidates = self:buildNpcCandidatesForField(field, false)
    if #candidates == 0 then return nil, "no valid NPC candidates" end

    local filtered = {}
    for _, c in ipairs(candidates) do
        if blockedCropName == nil or upper(blockedCropName) ~= c.cropName then
            table.insert(filtered, c)
        end
    end
    if #filtered == 0 then filtered = candidates end

    local weightedPool, weights = self:buildWeightedReseedPool(filtered)
    local fieldIdNum = tonumber(getFieldId(field)) or 1

    if #weightedPool > 0 then
        local pickIndex = ((fieldIdNum - 1) % #weightedPool) + 1
        local picked = weightedPool[pickIndex]
        if picked ~= nil then
            if picked.category == "leaveCultivated" then
                return nil, ("weighted leave cultivated (leaveCultivated=%d)"):format(weights.leaveCultivated)
            end

            local seasonText = "seasonal-unverified"
            if picked.seasonalKnown == true then
                seasonText = picked.seasonalOk and "seasonal" or "out-of-season"
            end
            return picked.fruit, "replacement selected (" .. seasonText .. ", " .. tostring(picked.category or "unknown") .. ")"
        end
    end

    return nil, "no weighted seasonal reseed candidate; field remains cultivated"
end

function CCO:getReseedCandidateTextForField(field, blockedCropName)
    local fruit, reason = self:findReplacementNpcCropForField(field, blockedCropName)
    if fruit ~= nil and fruit.name ~= nil then
        return upper(fruit.name), tostring(reason or "replacement selected")
    end
    return "NONE", tostring(reason or "no valid NPC candidates")
end

function CCO:setFieldCultivated(field)
    if field == nil or field.farmland == nil then return false end
    if FieldUpdateTask == nil then
        warn("FieldUpdateTask is unavailable; cannot reset field " .. tostring(getFieldId(field)))
        return false
    end

    local polygon = field.getDensityMapPolygon ~= nil and field:getDensityMapPolygon() or nil
    if polygon == nil then
        warn("No density map polygon for field " .. tostring(getFieldId(field)) .. "; skipping")
        return false
    end

    local task = FieldUpdateTask.new()
    task:setField(field)
    task:setArea(polygon)
    task:setFruit(FruitType.UNKNOWN, 1)
    task:setGroundType(FieldGroundType.CULTIVATED)
    task:setGroundAngle(0)

    if FieldSprayType ~= nil and task.setSprayType ~= nil then task:setSprayType(FieldSprayType.NONE) end
    if task.setSprayLevel ~= nil then task:setSprayLevel(0) end
    if task.setWeedState ~= nil then task:setWeedState(0) end
    if task.setStoneLevel ~= nil then task:setStoneLevel(0) end
    if task.setLimeLevel ~= nil then task:setLimeLevel(0) end
    if task.setPlowLevel ~= nil then task:setPlowLevel(1) end
    if task.setRollerLevel ~= nil then task:setRollerLevel(1) end
    if task.setStubbleShredLevel ~= nil then task:setStubbleShredLevel(0) end
    if task.resetDisplacement ~= nil then task:resetDisplacement() end
    if task.clearTireTracks ~= nil then task:clearTireTracks() end

    -- async=false spreads the task over frames and is safer for larger fields/MP.
    task:enqueue(false)
    return true
end

function CCO:setFieldReseeded(field, fruit, growthState)
    if field == nil or field.farmland == nil then return false, "no field" end
    if fruit == nil or fruit.index == nil then return false, "no fruit/index" end
    if FieldUpdateTask == nil then
        return false, "FieldUpdateTask unavailable"
    end

    local polygon = field.getDensityMapPolygon ~= nil and field:getDensityMapPolygon() or nil
    if polygon == nil then
        return false, "no density map polygon"
    end

    local fruitIndex = tonumber(fruit.index)
    if fruitIndex == nil then
        return false, "invalid fruit index"
    end

    local state = tonumber(growthState or 1) or 1
    if state < 1 then state = 1 end

    local groundType = nil
    if fruit.getGrowthStateGroundType ~= nil then
        local okGround, resolvedGround = pcall(function() return fruit:getGrowthStateGroundType(state) end)
        if okGround then groundType = resolvedGround end
    end
    if groundType == nil and FieldGroundType ~= nil then
        groundType = FieldGroundType.SOWN or FieldGroundType.SEEDBED or FieldGroundType.CULTIVATED
    end

    local task = FieldUpdateTask.new()
    task:setField(field)
    task:setArea(polygon)
    task:setFruit(fruitIndex, state)
    if groundType ~= nil and task.setGroundType ~= nil then
        task:setGroundType(groundType)
    end
    if task.setGroundAngle ~= nil then task:setGroundAngle(0) end

    -- Keep this deliberately simpler than the cultivated cleanup path.
    -- Reseed mode is about replacing an invalid crop, not simulating a full field-prep pass.
    if task.setWeedState ~= nil then task:setWeedState(0) end
    if task.setStoneLevel ~= nil then task:setStoneLevel(0) end
    if task.resetDisplacement ~= nil then task:resetDisplacement() end
    if task.clearTireTracks ~= nil then task:clearTireTracks() end

    task:enqueue(false)
    return true, "queued"
end

function CCO:getSeasonalReseedFruitForField(field, cropName)
    local action, candidateCrop, candidateReason = self:getDryRunResetActionForField(field, cropName, "reseedSeasonal")
    if action ~= "RESEED_SEASONAL" then
        return nil, action, candidateCrop, candidateReason
    end

    local fruit = getFruitByName(candidateCrop)
    if fruit == nil then
        return nil, "CULTIVATED_FALLBACK", candidateCrop, "candidate fruit not loaded"
    end

    return fruit, action, candidateCrop, candidateReason
end

function CCO:applyResetActionToField(field, cropName, reason, resetMode)
    local modeKey, modeLabel = self:normaliseResetMode(resetMode)
    if modeKey == "reseedSeasonal" then
        local fruit, action, candidateCrop, candidateReason = self:getSeasonalReseedFruitForField(field, cropName)
        if fruit ~= nil then
            local ok, writeReason = self:setFieldReseeded(field, fruit, 1)
            if ok then
                info(("queued field %s (%s, %.2f ha) to reseeded crop %s growthState=1 resetMode=%s reason=%s candidateReason=%s"):format(
                    tostring(getFieldId(field)), tostring(cropName), getFieldSizeHa(field), tostring(candidateCrop), tostring(modeLabel), tostring(reason), tostring(candidateReason)))
                return true, "reseeded", tostring(candidateCrop)
            end

            warn(("reseed failed for field %s candidate=%s writeReason=%s; falling back to cultivated"):format(
                tostring(getFieldId(field)), tostring(candidateCrop), tostring(writeReason)))
        else
            info(("reseed cultivated outcome for field %s (%s): action=%s candidate=%s candidateReason=%s"):format(
                tostring(getFieldId(field)), tostring(cropName), tostring(action), tostring(candidateCrop), tostring(candidateReason)))
        end
    end

    if self:setFieldCultivated(field) then
        info(("queued field %s (%s, %.2f ha) to cultivated state: %s"):format(
            tostring(getFieldId(field)), tostring(cropName), getFieldSizeHa(field), tostring(reason)))
        return true, "cultivated", nil
    end

    return false, "failed", nil
end

function CCO:scanFields(filterCrop, blockedOnly)
    blockedOnly = blockedOnly == true
    local results = { offending = 0, total = 0, printed = 0 }
    if g_fieldManager == nil or g_fieldManager.getFields == nil then
        warn("field manager not ready")
        return results
    end

    local target = filterCrop ~= nil and filterCrop ~= "" and upper(filterCrop) or nil
    local fields = g_fieldManager:getFields()
    if fields == nil then return results end

    for idx, field in pairs(fields) do
        local ft = getFieldFruit(field)
        if ft ~= nil then
            local cropName = upper(ft.name)
            if target == nil or cropName == target then
                results.total = results.total + 1
                local reset, reason = self:shouldResetNpcField(field, cropName)
                if reset then
                    results.offending = results.offending + 1
                    results.printed = results.printed + 1
                    print(("CCO: field=%s npc=%s crop=%s size=%.2fha status=BLOCKED reason=%s"):format(
                        tostring(getFieldId(field, idx)), tostring(isNpcField(field)), tostring(cropName), getFieldSizeHa(field), tostring(reason)))
                elseif not blockedOnly then
                    results.printed = results.printed + 1
                    print(("CCO: field=%s npc=%s crop=%s size=%.2fha status=OK reason=%s"):format(
                        tostring(getFieldId(field, idx)), tostring(isNpcField(field)), tostring(cropName), getFieldSizeHa(field), tostring(reason)))
                end
            end
        end
    end

    if blockedOnly then
        print(("CCO: blocked scan complete. checked=%d offendingNpcFields=%d printed=%d"):format(results.total, results.offending, results.printed))
    else
        print(("CCO: scan complete. checked=%d offendingNpcFields=%d"):format(results.total, results.offending))
    end
    return results
end

function CCO:buildFieldSummary(filterCrop)
    local summary = {
        total = 0,
        npcTotal = 0,
        playerTotal = 0,
        offending = 0,
        crops = {},
    }

    if g_fieldManager == nil or g_fieldManager.getFields == nil then
        warn("field manager not ready")
        return summary
    end

    local target = filterCrop ~= nil and filterCrop ~= "" and upper(filterCrop) or nil
    local fields = g_fieldManager:getFields()
    if fields == nil then return summary end

    for _, field in pairs(fields) do
        local ft = getFieldFruit(field)
        if ft ~= nil then
            local cropName = upper(ft.name)
            if target == nil or cropName == target then
                local npc = isNpcField(field)
                local blocked, reason = self:shouldResetNpcField(field, cropName)
                local sizeHa = getFieldSizeHa(field)

                summary.total = summary.total + 1
                if npc then summary.npcTotal = summary.npcTotal + 1 else summary.playerTotal = summary.playerTotal + 1 end
                if blocked then summary.offending = summary.offending + 1 end

                local crop = summary.crops[cropName]
                if crop == nil then
                    crop = { total = 0, npc = 0, player = 0, ok = 0, blocked = 0, minHa = nil, maxHa = nil, reasons = {} }
                    summary.crops[cropName] = crop
                end

                crop.total = crop.total + 1
                if npc then crop.npc = crop.npc + 1 else crop.player = crop.player + 1 end
                if blocked then crop.blocked = crop.blocked + 1 else crop.ok = crop.ok + 1 end
                crop.minHa = crop.minHa == nil and sizeHa or math.min(crop.minHa, sizeHa)
                crop.maxHa = crop.maxHa == nil and sizeHa or math.max(crop.maxHa, sizeHa)
                crop.reasons[reason or "allowed"] = (crop.reasons[reason or "allowed"] or 0) + 1
            end
        end
    end

    return summary
end

function CCO:printFieldSummary(filterCrop)
    local summary = self:buildFieldSummary(filterCrop)
    local names = {}
    for cropName, _ in pairs(summary.crops or {}) do table.insert(names, cropName) end
    table.sort(names)

    print("CCO: NPC crop summary" .. ((filterCrop ~= nil and filterCrop ~= "") and (" for " .. upper(filterCrop)) or ""))
    for _, cropName in ipairs(names) do
        local c = summary.crops[cropName]
        local status = c.blocked > 0 and "BLOCKED" or "OK"
        local reasonText = ""
        if c.blocked > 0 then
            local reasonNames = {}
            for reason, _ in pairs(c.reasons) do
                if reason ~= "allowed" and reason ~= "not NPC field" then table.insert(reasonNames, reason) end
            end
            table.sort(reasonNames)
            if #reasonNames > 0 then reasonText = " reasons=" .. table.concat(reasonNames, "; ") end
        end
        print(("CCO:   %-14s %s total=%d npc=%d player=%d ok=%d blocked=%d size=%.2f-%.2fha%s"):format(
            cropName, status, c.total, c.npc, c.player, c.ok, c.blocked, c.minHa or 0, c.maxHa or 0, reasonText))
    end

    print(("CCO: summary complete. checked=%d npcFields=%d playerFields=%d offendingNpcFields=%d crops=%d"):format(
        summary.total, summary.npcTotal, summary.playerTotal, summary.offending, #names))
    return summary
end

function CCO:validateSave()
    local summary = self:buildFieldSummary(nil)
    if summary.offending == 0 then
        print(("CCO: validation passed. checked=%d npcFields=%d playerFields=%d offendingNpcFields=0"):format(
            summary.total, summary.npcTotal, summary.playerTotal))
    else
        print(("CCO: validation failed. checked=%d npcFields=%d playerFields=%d offendingNpcFields=%d. Run ccoScanBlocked for details."):format(
            summary.total, summary.npcTotal, summary.playerTotal, summary.offending))
    end
    return summary.offending == 0
end


function CCO:printStartupValidation()
    if self._startupValidationPrinted then return end
    self._startupValidationPrinted = true

    local ok, summaryOrError = pcall(function()
        return self:buildFieldSummary(nil)
    end)
    if not ok then
        warn("startup validation skipped: " .. tostring(summaryOrError))
        return
    end

    local summary = summaryOrError
    if summary == nil then return end
    if summary.offending ~= nil and summary.offending > 0 then
        warn(("startup validation found %d blocked NPC field(s). Run ccoScanBlocked, then ccoResetBlocked dryrun if cleanup is intended."):format(summary.offending))
    else
        debug(("startup validation passed. checked=%d npcFields=%d playerFields=%d offendingNpcFields=0"):format(
            tonumber(summary.total or 0), tonumber(summary.npcTotal or 0), tonumber(summary.playerTotal or 0)))
    end
end

function CCO:resetNpcFields(filterCrop, dryRun, resetMode)
    dryRun = dryRun == true
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        warn("reset skipped: must run on server/host")
        return 0, 0
    end
    if g_fieldManager == nil or g_fieldManager.getFields == nil then
        warn("field manager not ready")
        return 0, 0
    end

    local target = filterCrop ~= nil and filterCrop ~= "" and upper(filterCrop) or nil
    local queued, skipped = 0, 0
    local wouldQueue = 0

    for idx, field in pairs(g_fieldManager:getFields()) do
        local ft = getFieldFruit(field)
        if ft ~= nil then
            local cropName = upper(ft.name)
            if target == nil or target == cropName then
                local reset, reason = self:shouldResetNpcField(field, cropName)
                if reset then
                    if dryRun then
                        wouldQueue = wouldQueue + 1
                        local action, candidateCrop, candidateReason = self:getDryRunResetActionForField(field, cropName, resetMode)
                        print(("CCO: dry-run would reset field=%s crop=%s size=%.2fha reason=%s resetMode=%s action=%s reseedCandidate=%s candidateReason=%s"):format(
                            tostring(getFieldId(field, idx)), cropName, getFieldSizeHa(field), tostring(reason), select(2, self:normaliseResetMode(resetMode)), tostring(action), tostring(candidateCrop), tostring(candidateReason)))
                    else
                        local ok = self:applyResetActionToField(field, cropName, reason, resetMode)
                        if ok then
                            queued = queued + 1
                        else
                            skipped = skipped + 1
                        end
                    end
                end
            end
        end
    end

    if dryRun then
        local msg = ("CCO: NPC field reset dry-run complete. wouldQueue=%d skipped=%d"):format(wouldQueue, skipped)
        print(msg)
        return wouldQueue, skipped
    end

    if queued > 0 and g_missionManager ~= nil then
        info("triggering mission generation after field reset")
        if g_missionManager.generationTimer ~= nil then g_missionManager.generationTimer = 0 end
        if g_missionManager.startMissionGeneration ~= nil then g_missionManager:startMissionGeneration() end
    end

    local msg = ("CCO: NPC field reset complete. queued=%d skipped=%d"):format(queued, skipped)
    print(msg)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, msg)
    end
    return queued, skipped
end


function CCO:generatePlannedFruitForField(superFunc, fieldManager, field)
    local ok, proposedFruit = pcall(function()
        return superFunc(fieldManager, field)
    end)

    if not ok then
        warn("generatePlannedFruitForField original call failed: " .. tostring(proposedFruit))
        return nil
    end

    local ok2, selectedFruit = pcall(function()
        if proposedFruit == nil or proposedFruit == FruitType.UNKNOWN then
            return proposedFruit
        end

        if field ~= nil and not isNpcField(field) then
            return proposedFruit
        end

        local ft = g_fruitTypeManager ~= nil and g_fruitTypeManager:getFruitTypeByIndex(proposedFruit) or nil
        if ft == nil then
            return proposedFruit
        end

        local cropName = upper(ft.name)
        local fieldHa = getFieldSizeHa(field)
        local allowed, reason = self:isNpcCropAllowedForField(fieldHa, cropName)
        if allowed then
            return proposedFruit
        end

        local replacement, replacementReason = self:findReplacementNpcCropForField(field, cropName)
        if replacement ~= nil and replacement.index ~= nil then
            debug(("planned fruit replacement for field %s: %s -> %s (%.2f ha): %s"):format(
                tostring(getFieldId(field)), cropName, upper(replacement.name), fieldHa, tostring(reason)))
            return replacement.index
        end

        debug(("planned fruit blocked for field %s: %s (%.2f ha): %s; no replacement selected (%s)"):format(
            tostring(getFieldId(field)), cropName, fieldHa, tostring(reason), tostring(replacementReason)))
        return nil
    end)

    if not ok2 then
        warn("generatePlannedFruitForField CCO selection failed: " .. tostring(selectedFruit))
        return proposedFruit
    end

    return selectedFruit
end

-- Enhanced runtime sowing enforcement (v2.0.3.x) ----------------------------
function CCO:isPlayerCropAllowedByIndex(fruitTypeIndex)
    if fruitTypeIndex == nil or fruitTypeIndex == FruitType.UNKNOWN or g_fruitTypeManager == nil then
        return true
    end

    local fruit = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    if fruit == nil then return true end

    local rule = self._rules and self._rules[upper(fruit.name)] or nil
    return rule == nil or rule.enabled ~= false
end

local function getSelectedSowingFruitTypeIndex(vehicle)
    if vehicle == nil then return nil end
    local spec = vehicle.spec_sowingMachine
    if spec == nil then return nil end

    -- FS25 copies the actively processed crop into workAreaParameters while the
    -- implement is working. Outside work-area processing, the selected crop is
    -- stored as an index into spec.seeds, not in seedFruitTypeIndex.
    if spec.workAreaParameters ~= nil then
        local activeFruitTypeIndex = spec.workAreaParameters.seedsFruitType
        if activeFruitTypeIndex ~= nil and activeFruitTypeIndex ~= FruitType.UNKNOWN then
            return activeFruitTypeIndex
        end
    end

    if spec.seeds ~= nil and spec.currentSeed ~= nil then
        local selectedFruitTypeIndex = spec.seeds[spec.currentSeed]
        if selectedFruitTypeIndex ~= nil then
            return selectedFruitTypeIndex
        end
    end

    -- Compatibility fallbacks for third-party specializations that expose their
    -- selected crop through one of these fields.
    return spec.seedFruitTypeIndex or spec.fruitTypeIndex or spec.currentFruitTypeIndex
end

function CCO:isVehicleSowingCropAllowed(vehicle)
    local fruitTypeIndex = getSelectedSowingFruitTypeIndex(vehicle)
    return self:isPlayerCropAllowedByIndex(fruitTypeIndex), fruitTypeIndex
end

local function getSowingCropName(fruitTypeIndex)
    local fruit = g_fruitTypeManager ~= nil and g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex) or nil
    return fruit ~= nil and upper(fruit.name) or tostring(fruitTypeIndex)
end

function CCO:showSowingNotPermitted(fruitTypeIndex)
    local now = g_time or 0
    if self._lastSowingWarningTime ~= nil and now - self._lastSowingWarningTime < 2500 then
        return
    end
    self._lastSowingWarningTime = now

    local cropName = getSowingCropName(fruitTypeIndex)
    local message = ccoL10n("cco_sowing_not_permitted", "Crop Control Override: Seeding %s is not permitted.", cropName)
    if g_currentMission ~= nil then
        -- FS25 renders the normal gameplay blinking warning through the HUD.
        -- Calling the similarly named mission function is not reliable once an AI
        -- job has already been stopped, and may succeed without displaying text.
        local hud = g_currentMission.hud
        if hud ~= nil and hud.showBlinkingWarning ~= nil then
            local ok, result = pcall(hud.showBlinkingWarning, hud, message, 5000)
            info(("SOW-BLOCK warning display path=hud.showBlinkingWarning ok=%s result=%s message=%s"):format(
                tostring(ok), tostring(result), tostring(message)))
            if ok then return end
        end

        -- Compatibility fallback for game builds/mod stacks exposing the method
        -- directly on the mission.
        if g_currentMission.showBlinkingWarning ~= nil then
            local ok, result = pcall(g_currentMission.showBlinkingWarning, g_currentMission, message, 5000)
            info(("SOW-BLOCK warning display path=mission.showBlinkingWarning ok=%s result=%s message=%s"):format(
                tostring(ok), tostring(result), tostring(message)))
            if ok then return end
        end

        -- INGAME_NOTIFICATION_OK is already used elsewhere by CCO and is known to
        -- be a valid numeric side-notification type. Do not use guessed warning or
        -- critical constants, as a nil type creates a blank overlay in FS25.
        local notificationType = FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_OK or nil
        if type(notificationType) == "number" and g_currentMission.addIngameNotification ~= nil then
            local ok, result = pcall(g_currentMission.addIngameNotification, g_currentMission, notificationType, message)
            info(("SOW-BLOCK warning display path=addIngameNotification ok=%s result=%s type=%s message=%s"):format(
                tostring(ok), tostring(result), tostring(notificationType), tostring(message)))
            if ok then return end
        end

        info("SOW-BLOCK warning display failed message=" .. tostring(message))
    end
end

local function ccoObjectName(object)
    if object == nil then return "nil" end
    if object.getName ~= nil then
        local ok, name = pcall(object.getName, object)
        if ok and name ~= nil then return tostring(name) end
    end
    return tostring(object)
end

function CCO:stopBlockedSowingWorker(vehicle, fruitTypeIndex)
    local rootVehicle = vehicle
    if vehicle ~= nil and vehicle.getRootVehicle ~= nil then
        local ok, result = pcall(vehicle.getRootVehicle, vehicle)
        if ok and result ~= nil then rootVehicle = result end
    end

    self:showSowingNotPermitted(fruitTypeIndex)

    if rootVehicle == nil then
        warn(("SOW-BLOCK stop requested with no vehicle; crop=%s"):format(getSowingCropName(fruitTypeIndex)))
        return
    end

    local getIsAIActiveOk, getIsAIActiveResult = false, nil
    local isAIActive = false
    if rootVehicle.getIsAIActive ~= nil then
        getIsAIActiveOk, getIsAIActiveResult = pcall(rootVehicle.getIsAIActive, rootVehicle)
        isAIActive = getIsAIActiveOk and getIsAIActiveResult == true
    elseif rootVehicle.spec_aiFieldWorker ~= nil then
        isAIActive = rootVehicle.spec_aiFieldWorker.isActive == true
    end

    local aiSpec = rootVehicle.spec_aiFieldWorker
    local job = rootVehicle.getCurrentAIJob ~= nil and rootVehicle:getCurrentAIJob() or nil
    info(("SOW-BLOCK worker state crop=%s implement=%s root=%s aiActive=%s getIsAIActiveOk=%s specActive=%s currentJob=%s methods[stopCurrentAIJob=%s stopAIVehicle=%s setAIFieldWorkerActive=%s setIsAIActive=%s]"):format(
        getSowingCropName(fruitTypeIndex), ccoObjectName(vehicle), ccoObjectName(rootVehicle), tostring(isAIActive),
        tostring(getIsAIActiveOk), tostring(aiSpec ~= nil and aiSpec.isActive or nil), tostring(job),
        tostring(rootVehicle.stopCurrentAIJob ~= nil), tostring(rootVehicle.stopAIVehicle ~= nil),
        tostring(rootVehicle.setAIFieldWorkerActive ~= nil), tostring(rootVehicle.setIsAIActive ~= nil)))

    local stopSucceeded = false
    local attempts = {}
    local function attempt(name, fn, object, ...)
        if fn == nil then
            attempts[#attempts + 1] = name .. "=missing"
            return false
        end
        local ok, result = pcall(fn, object, ...)
        attempts[#attempts + 1] = name .. "[ok=" .. tostring(ok) .. ",result=" .. tostring(result) .. "]"
        if ok then stopSucceeded = true end
        return ok
    end

    if isAIActive or job ~= nil then
        attempt("stopCurrentAIJob", rootVehicle.stopCurrentAIJob, rootVehicle)
        if not stopSucceeded then attempt("stopAIVehicle", rootVehicle.stopAIVehicle, rootVehicle) end
        if not stopSucceeded then attempt("setAIFieldWorkerActive", rootVehicle.setAIFieldWorkerActive, rootVehicle, false) end
        if not stopSucceeded then attempt("setIsAIActive", rootVehicle.setIsAIActive, rootVehicle, false) end
    else
        attempts[#attempts + 1] = "no-active-ai-detected"
    end

    local turnOffOk = false
    if vehicle ~= nil and vehicle.setIsTurnedOn ~= nil then
        turnOffOk = pcall(vehicle.setIsTurnedOn, vehicle, false, true)
    end

    info(("SOW-BLOCK stop result crop=%s root=%s success=%s turnOffOk=%s attempts=%s"):format(
        getSowingCropName(fruitTypeIndex), ccoObjectName(rootVehicle), tostring(stopSucceeded), tostring(turnOffOk), table.concat(attempts, "; ")))
end

local function installSowingAreaBlock(specialization, specializationName)
    if specialization == nil or specialization.processSowingMachineArea == nil then
        warn(tostring(specializationName) .. ".processSowingMachineArea not available; sowing block not installed")
        return false
    end

    specialization.processSowingMachineArea = Utils.overwrittenFunction(
        specialization.processSowingMachineArea,
        function(vehicle, superFunc, ...)
            local allowed, fruitTypeIndex = CCO:isVehicleSowingCropAllowed(vehicle)
            if not allowed then
                CCO:stopBlockedSowingWorker(vehicle, fruitTypeIndex)
                debug(("blocked sowing write in %s for disabled crop %s on vehicle %s"):format(
                    tostring(specializationName),
                    getSowingCropName(fruitTypeIndex),
                    vehicle.getName ~= nil and tostring(vehicle:getName()) or tostring(vehicle)))
                return 0, 0
            end
            return superFunc(vehicle, ...)
        end
    )

    debug("hooked " .. tostring(specializationName) .. ".processSowingMachineArea")
    return true
end

function CCO:applyPlayerSowingHooks()
    if self._playerSowingHooksApplied then return end

    if SowingMachine == nil then
        warn("SowingMachine specialization not available; player sowing hooks not installed")
        return
    end

    self._playerSowingHooksApplied = true

    -- FS25 fertilizer-capable seeders register an overwritten implementation on
    -- FertilizingSowingMachine. Hook both implementations because patching only
    -- SowingMachine does not intercept those implements.
    installSowingAreaBlock(SowingMachine, "SowingMachine")
    if FertilizingSowingMachine ~= nil then
        installSowingAreaBlock(FertilizingSowingMachine, "FertilizingSowingMachine")
    end

    -- Prevent normal activation where supported. The work-area hooks above are
    -- the server-authoritative safeguards and cannot be bypassed by stale client
    -- selection state, helpers or automation mods.
    if SowingMachine.getCanBeTurnedOn ~= nil then
        SowingMachine.getCanBeTurnedOn = Utils.overwrittenFunction(
            SowingMachine.getCanBeTurnedOn,
            function(vehicle, superFunc, ...)
                local allowed, fruitTypeIndex = CCO:isVehicleSowingCropAllowed(vehicle)
                if not allowed then
                    CCO:showSowingNotPermitted(fruitTypeIndex)
                    return false
                end
                return superFunc(vehicle, ...)
            end
        )
        debug("hooked SowingMachine.getCanBeTurnedOn")
    end

    local function installAIBlock(functionName)
        if SowingMachine[functionName] == nil then return end
        SowingMachine[functionName] = Utils.overwrittenFunction(
            SowingMachine[functionName],
            function(vehicle, superFunc, ...)
                local allowed, fruitTypeIndex = CCO:isVehicleSowingCropAllowed(vehicle)
                if not allowed then
                    CCO:stopBlockedSowingWorker(vehicle, fruitTypeIndex)
                    return false
                end
                return superFunc(vehicle, ...)
            end
        )
        debug("hooked SowingMachine." .. functionName)
    end

    installAIBlock("getCanAIImplementStart")
    installAIBlock("getCanAIImplementContinueWork")
end

function CCO:applyDensityMapSowingHooks()
    if self._densityMapSowingHooksApplied then return end
    if FSDensityMapUtil == nil then
        warn("FSDensityMapUtil not available; density-map sowing block not installed")
        return
    end

    local installed = false

    local function install(functionName)
        local original = FSDensityMapUtil[functionName]
        if original == nil then
            warn("FSDensityMapUtil." .. tostring(functionName) .. " not available; sowing block not installed")
            return
        end

        FSDensityMapUtil[functionName] = function(fruitTypeIndex, ...)
            if not CCO:isPlayerCropAllowedByIndex(fruitTypeIndex) then
                local fruit = g_fruitTypeManager ~= nil and g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex) or nil
                local cropName = fruit ~= nil and upper(fruit.name) or tostring(fruitTypeIndex)
                local now = g_time or 0
                CCO._lastDensityMapBlockedCrop = cropName
                CCO._lastDensityMapBlockedTime = now

                -- INFO-level diagnostic is throttled so the normal game log remains usable.
                local diagnosticKey = tostring(functionName) .. ":" .. tostring(fruitTypeIndex)
                if CCO._lastSowingBlockDiagnosticKey ~= diagnosticKey or
                   CCO._lastSowingBlockDiagnosticTime == nil or
                   now - CCO._lastSowingBlockDiagnosticTime >= 2000 then
                    CCO._lastSowingBlockDiagnosticKey = diagnosticKey
                    CCO._lastSowingBlockDiagnosticTime = now
                    local argTypes = {}
                    for i = 1, select("#", ...) do
                        argTypes[#argTypes + 1] = tostring(i) .. "=" .. type(select(i, ...))
                    end
                    local isServer = g_server ~= nil
                    local isClient = g_client ~= nil
                    info(("SOW-BLOCK density write blocked function=%s crop=%s index=%s server=%s client=%s argCount=%s argTypes=[%s]"):format(
                        tostring(functionName), cropName, tostring(fruitTypeIndex), tostring(isServer), tostring(isClient),
                        tostring(select("#", ...)), table.concat(argTypes, ",")))
                end
                return 0, 0
            end
            return original(fruitTypeIndex, ...)
        end

        installed = true
        debug("hooked FSDensityMapUtil." .. tostring(functionName))
    end

    install("updateSowingArea")
    install("updateDirectSowingArea")

    if installed then
        self._densityMapSowingHooksApplied = true
    end
end



local function ccoCreateAIStopMessage()
    local constructors = {
        AIMessageErrorUnknown,
        AIMessageErrorBlockedByObject,
        AIMessageErrorCouldNotStart,
    }
    for _, class in ipairs(constructors) do
        if class ~= nil and class.new ~= nil then
            local ok, message = pcall(class.new, class)
            if ok and message ~= nil then
                return message
            end
            ok, message = pcall(class.new)
            if ok and message ~= nil then
                return message
            end
        end
    end
    return nil
end

local function ccoCollectSowingImplements(rootVehicle)
    local result = {}
    local seen = {}
    local function add(object)
        if object == nil or seen[object] then return end
        seen[object] = true
        if object.spec_sowingMachine ~= nil or object.spec_fertilizingSowingMachine ~= nil then
            result[#result + 1] = object
        end
        if object.getAttachedImplements ~= nil then
            local ok, attached = pcall(object.getAttachedImplements, object)
            if ok and attached ~= nil then
                for _, entry in pairs(attached) do
                    add(entry.object or entry)
                end
            end
        end
    end
    add(rootVehicle)
    return result
end

function CCO:scanAndStopBlockedSowingWorkers(dt)
    if g_server == nil or g_currentMission == nil then return end

    self._blockedSowingWorkerScanTimer = (self._blockedSowingWorkerScanTimer or 0) + (dt or 0)
    if self._blockedSowingWorkerScanTimer < 250 then return end
    self._blockedSowingWorkerScanTimer = 0

    local now = g_time or 0
    local recentDensityBlock = self._lastDensityMapBlockedTime ~= nil and now - self._lastDensityMapBlockedTime < 3000
    if not recentDensityBlock then return end

    local function resolveJobVehicle(job)
        if job == nil then return nil end
        local direct = job.vehicle or job.rootVehicle or job.aiVehicle
        if direct ~= nil then return direct end

        local parameter = job.vehicleParameter
        if parameter == nil and job.parameters ~= nil then
            parameter = job.parameters.vehicle or job.parameters.vehicleParameter
        end
        if parameter ~= nil then
            if parameter.getVehicle ~= nil then
                local ok, vehicle = pcall(parameter.getVehicle, parameter)
                if ok and vehicle ~= nil then return vehicle end
            end
            if parameter.vehicle ~= nil then return parameter.vehicle end
            if parameter.value ~= nil and type(parameter.value) == "table" then return parameter.value end
        end
        return nil
    end

    local jobs, seenJobs = {}, {}
    local function addJob(job)
        if type(job) ~= "table" or seenJobs[job] then return end
        seenJobs[job] = true
        jobs[#jobs + 1] = job
    end
    local function addJobsFrom(container)
        if type(container) ~= "table" then return end
        for key, value in pairs(container) do
            if type(key) == "table" then addJob(key) end
            if type(value) == "table" then addJob(value) end
        end
    end

    local aiSystem = g_currentMission.aiSystem
    if aiSystem ~= nil then
        addJobsFrom(aiSystem.activeJobs)
        addJobsFrom(aiSystem.jobs)
        addJobsFrom(aiSystem.currentJobs)
        if aiSystem.getActiveJobs ~= nil then
            local ok, activeJobs = pcall(aiSystem.getActiveJobs, aiSystem)
            if ok then addJobsFrom(activeJobs) end
        end
    end

    local vehicles, seenVehicles = {}, {}
    local function addVehicle(vehicle, source, job)
        if type(vehicle) ~= "table" or seenVehicles[vehicle] then return end
        seenVehicles[vehicle] = true
        vehicles[#vehicles + 1] = {vehicle=vehicle, source=source, job=job}
    end

    for _, job in ipairs(jobs) do
        addVehicle(resolveJobVehicle(job), "aiJob", job)
    end

    local vehicleSystem = g_currentMission.vehicleSystem
    if vehicleSystem ~= nil then
        local collections = {vehicleSystem.vehicles, vehicleSystem.rootVehicles, vehicleSystem.enterables}
        for _, collection in ipairs(collections) do
            if type(collection) == "table" then
                for _, vehicle in pairs(collection) do addVehicle(vehicle, "vehicleSystem", nil) end
            end
        end
    end
    if type(g_currentMission.vehicles) == "table" then
        for _, vehicle in pairs(g_currentMission.vehicles) do addVehicle(vehicle, "missionVehicles", nil) end
    end

    local rows = {}
    local stoppedCount = 0
    for _, entry in ipairs(vehicles) do
        local rootVehicle = entry.vehicle
        local implements = ccoCollectSowingImplements(rootVehicle)
        local cropParts = {}
        for _, implement in ipairs(implements) do
            local allowed, fruitTypeIndex = self:isVehicleSowingCropAllowed(implement)
            cropParts[#cropParts + 1] = ("%s:%s:%s"):format(ccoObjectName(implement), tostring(fruitTypeIndex), tostring(allowed))
            if not allowed then
                local key = tostring(rootVehicle) .. ":" .. tostring(fruitTypeIndex)
                local lastStop = self._blockedSowingWorkerLastStop[key] or -100000
                if now - lastStop >= 2000 then
                    self._blockedSowingWorkerLastStop[key] = now
                    local attempts = {}
                    local stopped = false
                    local job = entry.job

                    local function attempt(name, fn, object, ...)
                        if fn == nil then
                            attempts[#attempts + 1] = name .. "=missing"
                            return
                        end
                        local ok, result = pcall(fn, object, ...)
                        attempts[#attempts + 1] = name .. "[ok=" .. tostring(ok) .. ",result=" .. tostring(result) .. "]"
                        if ok then stopped = true end
                    end

                    -- Do not pass a fabricated AIMessage object. Courseplay and
                    -- the base game expect concrete AIMessage classes with methods
                    -- such as getMessage() and getI18NText(). The normal vehicle stop
                    -- route accepts no explicit message and is compatible with both.
                    attempt("root.stopCurrentAIJob()", rootVehicle.stopCurrentAIJob, rootVehicle)
                    attempt("root.stopAIVehicle", rootVehicle.stopAIVehicle, rootVehicle)
                    attempt("root.setAIFieldWorkerActive(false)", rootVehicle.setAIFieldWorkerActive, rootVehicle, false)
                    attempt("root.setIsAIActive(false)", rootVehicle.setIsAIActive, rootVehicle, false)
                    attempt("implement.setIsTurnedOn(false)", implement.setIsTurnedOn, implement, false, true)

                    self:showSowingNotPermitted(fruitTypeIndex)
                    stoppedCount = stoppedCount + (stopped and 1 or 0)
                    info(("SOW-BLOCK active job enforcement crop=%s source=%s job=%s implement=%s root=%s stopped=%s attempts=%s"):format(
                        getSowingCropName(fruitTypeIndex), tostring(entry.source), tostring(job), ccoObjectName(implement),
                        ccoObjectName(rootVehicle), tostring(stopped), table.concat(attempts, "; ")))
                end
                break
            end
        end
        rows[#rows + 1] = ("source=%s job=%s root=%s implements=[%s]"):format(
            tostring(entry.source), tostring(entry.job), ccoObjectName(rootVehicle), table.concat(cropParts, ","))
    end

    if self._lastWorkerScanDiagnosticTime == nil or now - self._lastWorkerScanDiagnosticTime >= 2000 then
        self._lastWorkerScanDiagnosticTime = now
        info(("SOW-BLOCK worker scan heartbeat jobs=%s vehicles=%s stopped=%s aiSystem.activeJobs=%s vehicleSystem=%s rows=%s"):format(
            tostring(#jobs), tostring(#vehicles), tostring(stoppedCount),
            tostring(aiSystem ~= nil and aiSystem.activeJobs or nil), tostring(vehicleSystem), table.concat(rows, " || ")))
    end
end

function CCO:update(dt)
    self:scanAndStopBlockedSowingWorkers(dt)
    self:updateNpcMapRegeneration(dt)
end

function CCO:updateTick(dt)
    self:scanAndStopBlockedSowingWorkers(dt)
end


function CCO:installSeedingGuards()
    if self._seedGuardHooksApplied == true then return end
    self._seedGuardHooksApplied = true

    -- Keep the proven 2.0.1.8 selector filtering exactly: filter each newly
    -- loaded/purchased sowing machine, while applyRules() refreshes all already
    -- loaded machines from their preserved ccoOriginalSeeds list.
    if SowingMachine == nil then
        warn("SowingMachine class not available; seed selector filter not installed")
    elseif SowingMachine.onPostLoad ~= nil then
        SowingMachine.onPostLoad = Utils.appendedFunction(SowingMachine.onPostLoad, function(vehicle, ...)
            pcall(function() CCO:filterSowingMachineSeeds(vehicle) end)
        end)
        debug("hooked SowingMachine.onPostLoad (seed list filter)")
    elseif SowingMachine.onLoad ~= nil then
        SowingMachine.onLoad = Utils.appendedFunction(SowingMachine.onLoad, function(vehicle, ...)
            pcall(function() CCO:filterSowingMachineSeeds(vehicle) end)
        end)
        debug("hooked SowingMachine.onLoad (seed list filter)")
    end

    -- Layer the proven v2.0.3.x protections underneath the selector filter.
    self:applyDensityMapSowingHooks()
    self:applyPlayerSowingHooks()
end

function CCO:applyRuntimeHooks()
    if self._hookApplied then return end
    self._hookApplied = true

    self:installSeedingGuards()

    if FieldManager ~= nil and FieldManager.generatePlannedFruitForField ~= nil then
        FieldManager.generatePlannedFruitForField = Utils.overwrittenFunction(FieldManager.generatePlannedFruitForField, function(fieldManager, superFunc, field)
            return CCO:generatePlannedFruitForField(superFunc, fieldManager, field)
        end)
        debug("hooked FieldManager.generatePlannedFruitForField")
    else
        warn("FieldManager.generatePlannedFruitForField not available; NPC crop planning hook not installed")
    end


    if FieldManager ~= nil and FieldManager.getFruitIndexForField ~= nil then
        local originalGetFruitIndexForField = FieldManager.getFruitIndexForField
        FieldManager.getFruitIndexForField = function(fm, field, ...)
            local fruitIndex = originalGetFruitIndexForField(fm, field, ...)
            if fruitIndex == nil then return nil end

            local ft = g_fruitTypeManager ~= nil and g_fruitTypeManager:getFruitTypeByIndex(fruitIndex) or nil
            if ft == nil then return fruitIndex end

            local cropName = upper(ft.name)
            local fieldHa = getFieldSizeHa(field)
            local allowed, reason = CCO:isNpcCropAllowedForField(fieldHa, cropName)
            if not allowed then
                local replacement, replacementReason = CCO:findReplacementNpcCropForField(field, cropName)
                if replacement ~= nil and replacement.index ~= nil then
                    debug(("replaced blocked NPC crop choice %s with %s on field %s (%.2f ha): %s"):format(
                        cropName, upper(replacement.name), tostring(getFieldId(field)), fieldHa, tostring(reason)))
                    return replacement.index
                end

                debug(("blocked NPC crop choice %s on field %s (%.2f ha): %s; %s"):format(
                    cropName, tostring(getFieldId(field)), fieldHa, tostring(reason), tostring(replacementReason)))
                return nil
            end

            return fruitIndex
        end
        debug("hooked FieldManager.getFruitIndexForField")
    end
end

function CCO:applyLateHooks()
    if SowMission ~= nil and SowMission.isAvailableForField ~= nil and not self._sowHookApplied then
        self._sowHookApplied = true
        local originalSowIsAvailable = SowMission.isAvailableForField
        SowMission.isAvailableForField = function(field, mission, ...)
            local result = originalSowIsAvailable(field, mission, ...)
            if not result then return false end

            local cropName = nil
            if mission ~= nil then
                if mission.fruitType ~= nil then
                    cropName = mission.fruitType.name
                elseif mission.fruitTypeIndex ~= nil and g_fruitTypeManager ~= nil then
                    local ft = g_fruitTypeManager:getFruitTypeByIndex(mission.fruitTypeIndex)
                    if ft ~= nil then cropName = ft.name end
                end
            end

            if cropName == nil then return result end

            local allowed, reason = CCO:isNpcCropAllowedForField(getFieldSizeHa(field), cropName)
            if not allowed then
                debug(("blocked sow mission for %s on field %s (%.2f ha): %s"):format(
                    upper(cropName), tostring(getFieldId(field)), getFieldSizeHa(field), tostring(reason)))
                return false
            end

            return result
        end
        debug("hooked SowMission.isAvailableForField")
    end
end

-- PDA / UI filtering hooks, inherited from the original CCO build.
local function applyPdaFilterHooks()
    if IngameMenu == nil then return end

    local function filteredFruitList()
        local list = {}
        if g_fruitTypeManager == nil then return list end
        for _, fruit in ipairs(g_fruitTypeManager.fruitTypes) do
            local rule = CCO._rules and CCO._rules[upper(fruit.name)] or nil
            if rule == nil or rule.enabled ~= false then
                table.insert(list, fruit)
            end
        end
        return list
    end

    IngameMenu.onOpen = Utils.appendedFunction(IngameMenu.onOpen, function(menuSelf)
        if CCO._rules == nil then return end

        if menuSelf.cropCalendarFrame ~= nil and menuSelf.cropCalendarFrame.updateData ~= nil and not menuSelf.cropCalendarFrame.ccoHooked then
            menuSelf.cropCalendarFrame.ccoHooked = true
            local orig = menuSelf.cropCalendarFrame.updateData
            function menuSelf.cropCalendarFrame:updateData(...)
                self.fruitTypes = filteredFruitList()
                return orig(self, ...)
            end
        end

        if menuSelf.mapOverviewFrame ~= nil and menuSelf.mapOverviewFrame.updateFruitTypes ~= nil and not menuSelf.mapOverviewFrame.ccoHooked then
            menuSelf.mapOverviewFrame.ccoHooked = true
            local orig = menuSelf.mapOverviewFrame.updateFruitTypes
            function menuSelf.mapOverviewFrame:updateFruitTypes(...)
                self.fruitTypes = filteredFruitList()
                return orig(self, ...)
            end
        end

        if menuSelf.statisticsFrame ~= nil and menuSelf.statisticsFrame.updateFruitTypes ~= nil and not menuSelf.statisticsFrame.ccoHooked then
            menuSelf.statisticsFrame.ccoHooked = true
            local orig = menuSelf.statisticsFrame.updateFruitTypes
            function menuSelf.statisticsFrame:updateFruitTypes(...)
                self.fruitTypes = filteredFruitList()
                return orig(self, ...)
            end
        end
    end)
end

applyPdaFilterHooks()

-- Early application: catches base fruit types before fields/contracts are set up.
local originalFruitTypeLoadMapData = FruitTypeManager.loadMapData
function FruitTypeManager:loadMapData(xmlFile, missionInfo, baseDir, customEnv, isMission)
    local result = originalFruitTypeLoadMapData(self, xmlFile, missionInfo, baseDir, customEnv, isMission)

    local ok, e = pcall(function()
        local rules, path = CCO:loadRulesForMission(missionInfo)
        if CCO._mpClientOnly == true and CCO._serverSettingsSynced ~= true then
            -- Remote client before the server snapshot: the in-memory rules
            -- are all-enabled placeholders. Applying them would actively
            -- (re)enable every crop; leave the map defaults untouched and let
            -- applyServerSettingsPayload do the first real apply.
            debug("remote client: deferring crop policy apply until server rules arrive")
        else
            CCO:applyRules(rules)
            debug(("applied crop policy from %s"):format(tostring(path)))
        end
    end)
    if not ok then warn("failed applying crop policy in loadMapData: " .. tostring(e)) end

    CCO:applyRuntimeHooks()

    return result
end

-- Late reapplication: catches DLC/mod fruit types that appear later.
local originalFSBaseMissionLoadMapFinished = FSBaseMission.loadMapFinished
function FSBaseMission:loadMapFinished(...)
    local results = nil
    if originalFSBaseMissionLoadMapFinished ~= nil then
        results = { originalFSBaseMissionLoadMapFinished(self, ...) }
    end

    local ok, e = pcall(function()
        CCO._rules = mergeMissingDiscoveredFruits(CCO._rules or {})
        if not isClientOnlyMultiplayer() and CCO._configPath ~= nil then
            writeConfig(CCO._configPath, CCO._rules, CCO._settings)
        end
        if CCO._mpClientOnly == true and CCO._serverSettingsSynced ~= true then
            debug("remote client: skipping loadMapFinished reapply until server rules arrive")
        else
            CCO:applyRules(CCO._rules)
        end
        CCO:applyLateHooks()
        debug("reapplied crop policy after loadMapFinished")
        CCO:printStartupValidation()
    end)
    if not ok then warn("failed during loadMapFinished reapply: " .. tostring(e)) end

    if results ~= nil then return unpack(results) end
end

-- Save the v2 rules on normal game save so newly discovered fruit types are
-- persisted into the per-save config once the save is stable.
if ItemSystem ~= nil and ItemSystem.save ~= nil then
    ItemSystem.save = Utils.prependedFunction(ItemSystem.save, function(...)
        if g_currentMission ~= nil and g_currentMission:getIsServer() and CCO._configPath ~= nil and CCO._rules ~= nil then
            writeConfig(CCO._configPath, CCO._rules, CCO._settings)
        end
    end)
end

FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, function()
    CCO._rules = {}
    CCO._configPath = nil
    CCO._startupValidationPrinted = false
    CCO._serverCanEditRules = false
    CCO._connectionToMasterUser = {}
    -- Snapshots belong to the fruit types of the map that was just unloaded.
    -- Keeping them would "restore" stale flag values onto the next map's
    -- fruit types in the same game session.
    CCO._origFlags = {}
    CCO._mpClientOnly = false
    CCO._awaitingServerSettings = false
    CCO._serverSettingsSynced = false
    CCO._clientReportedMasterUser = false
    CCO._serverSettingsRetryTimer = 0
    CCO._serverSettingsRetryCount = 0
    CCO._npcMapRegenerationPlan = nil
    CCO._npcMapRegenerationState = nil
end)

-- Multiplayer sync reliability ------------------------------------------------
-- The only automatic client request used to fire inside FruitTypeManager
-- loadMapData, which is too early in the join process to be reliable, and there
-- was no retry: a lost request left the client on all-enabled default rules for
-- the whole session. Two fixes: the server now pushes its snapshot to every
-- client that finishes loading, and clients re-request until a snapshot lands.

if FSBaseMission ~= nil and FSBaseMission.onConnectionFinishedLoading ~= nil then
    FSBaseMission.onConnectionFinishedLoading = Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading, function(mission, connection, ...)
        if g_server ~= nil and connection ~= nil then
            local ok, e = pcall(function()
                CCO:sendSettingsSnapshotToClient(connection, "clientFinishedLoading")
            end)
            if not ok then warn("failed to push CCO rules to joining client: " .. tostring(e)) end
        end
    end)
end

function CCO:updateServerSettingsRetry(dt)
    if not isClientOnlyMultiplayer() then return end
    if self._serverSettingsSynced == true then return end
    if self._awaitingServerSettings ~= true then return end

    self._serverSettingsRetryTimer = (self._serverSettingsRetryTimer or 0) + (tonumber(dt) or 0)
    if self._serverSettingsRetryTimer < 5000 then return end
    self._serverSettingsRetryTimer = 0

    self._serverSettingsRetryCount = (self._serverSettingsRetryCount or 0) + 1
    if self._serverSettingsRetryCount > 24 then
        if self._serverSettingsRetryCount == 25 then
            warn("giving up on automatic CCO server rule sync after 24 attempts; open the CCO GUI or run ccoReload to retry")
        end
        return
    end

    debug(("re-requesting CCO server rules (attempt %d)"):format(self._serverSettingsRetryCount))
    self:requestServerSettings("retry")
end

if FSBaseMission ~= nil and FSBaseMission.update ~= nil then
    FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(mission, dt)
        if CCO ~= nil and CCO.updateServerSettingsRetry ~= nil then
            CCO:updateServerSettingsRetry(dt)
        end
        -- CCO is not installed as a ModEventListener, so its CCO:update(dt)
        -- method is not called automatically. Service the staged NPC map
        -- regeneration explicitly from the mission update loop.
        if CCO ~= nil and CCO.updateNpcMapRegeneration ~= nil then
            CCO:updateNpcMapRegeneration(dt)
        end
    end)
end



-- GUI foundation -----------------------------------------------------------
-- Read-only GIANTS XML screen backed by the validated CCO policy engine.
-- Alpha.16 adds a structured crop-policy table while keeping editing disabled.
local function showCcoCustomGui(title, text, topic, page)
    title = title or "Crop Control Override"
    text = text or ""

    if CropControlOverrideMenu ~= nil and CropControlOverrideMenu.show ~= nil then
        local ok, shown = pcall(function()
            return CropControlOverrideMenu.show(title, text, CCO.MOD_DIRECTORY or g_currentModDirectory, topic, page)
        end)
        if ok and shown then
            return true
        end
        if not ok then
            print("CCO GUI: custom screen failed: " .. tostring(shown))
        end
    else
        print("CCO GUI: CropControlOverrideMenu class is not available")
    end

    print("CCO GUI: custom screen unavailable; using console fallback output")
    print("CCO GUI: " .. tostring(title))
    for line in tostring(text):gmatch("[^\n]+") do
        print("CCO GUI: " .. line)
    end
    return false
end

function CCO:consoleGuiTest()
    return showCcoCustomGui("Crop Control Override - Dialog Test", "If you can read this, the custom CCO GUI screen is rendering correctly.\n\nThis screen replaces the experimental InfoDialog approach used in alpha.11-alpha.13.")
end

function CCO:buildGuiStatusText()
    local rules = self._rules or {}
    local total, discovered, disabled, npcBlocked, limited, undiscovered = 0, 0, 0, 0, 0, 0
    for nameU, r in pairs(rules) do
        total = total + 1
        if getFruitByName(nameU) ~= nil then discovered = discovered + 1 else undiscovered = undiscovered + 1 end
        if r.enabled == false then disabled = disabled + 1 end
        if r.enabled == false or r.npcAllowed == false then npcBlocked = npcBlocked + 1 end
        if tonumber(r.npcMaxHa or 0) > 0 then limited = limited + 1 end
    end

    local summary = self:buildFieldSummary(nil)
    local validation = (summary.offending or 0) == 0 and "PASS" or ("FAILED - " .. tostring(summary.offending or 0) .. " offending NPC field(s)")

    local lines = {}

    if self._guiNotice ~= nil and self._guiNotice ~= "" then
        table.insert(lines, "NOTICE")
        table.insert(lines, tostring(self._guiNotice))
        table.insert(lines, "")
        self._guiNotice = nil
    end

    table.insert(lines, "ACTIVE CONFIG")
    table.insert(lines, tostring(self._configPath or "not loaded"))
    table.insert(lines, "")

    table.insert(lines, "CONFIG HIERARCHY")
    table.insert(lines, "APPLY / FORCE APPLY writes the selected rule to the active per-save XML.")
    table.insert(lines, "SAVE DEFAULTS writes the full active rule set to config.xml for future/default use.")
    table.insert(lines, "Existing per-save XML files are not overwritten by SAVE DEFAULTS.")
    table.insert(lines, "")

    table.insert(lines, "CROP RULES")
    table.insert(lines, ("Configured rules:       %d"):format(total))
    table.insert(lines, ("Loaded crop rules:      %d"):format(discovered))
    table.insert(lines, ("Not loaded on map:      %d"):format(undiscovered))
    table.insert(lines, "")

    table.insert(lines, "POLICY SUMMARY")
    table.insert(lines, ("Disabled crops:         %d"):format(disabled))
    table.insert(lines, ("NPC-disabled crops:      %d"):format(npcBlocked))
    table.insert(lines, ("Size-limited crops:     %d"):format(limited))
    table.insert(lines, "")

    table.insert(lines, "SAVE VALIDATION")
    table.insert(lines, ("Status:                 %s"):format(validation))
    table.insert(lines, ("Checked fields:         %d"):format(tonumber(summary.total or 0)))
    table.insert(lines, ("NPC fields:             %d"):format(tonumber(summary.npcTotal or 0)))
    table.insert(lines, ("Player fields:          %d"):format(tonumber(summary.playerTotal or 0)))
    table.insert(lines, "")

    table.insert(lines, "ACTIONS")
    table.insert(lines, "APPLY / FORCE APPLY writes staged crop changes to this save only.")
    table.insert(lines, "SAVE DEFAULTS exports the current save rules to template config.xml.")
    table.insert(lines, "LOAD DEFAULTS imports template config.xml into this save and overwrites the active per-save rules.")
    table.insert(lines, "")
    table.insert(lines, "VALIDATION CLEANUP")
    table.insert(lines, "Use RESET SCOPE to choose ALL, CROP, or FIELD.")
    table.insert(lines, "Use RESET BLOCKED DRY-RUN first, then CONFIRM RESET if the result looks correct. Dry-run also reports a reseed candidate for future reseed mode.")
    table.insert(lines, "")
    table.insert(lines, "NAVIGATION")
    table.insert(lines, "Use the top tabs, or PREV TAB / NEXT TAB, to move between sections. Use BACK to close.")
    return table.concat(lines, "\n")
end

function CCO:ruleStatusText(nameU, r)
    if r == nil then return "UNKNOWN" end
    if getFruitByName(nameU) == nil then return "NOT LOADED" end
    if r.enabled == false then return "DISABLED" end
    if r.npcAllowed == false then return "NPC DISABLED" end
    if tonumber(r.npcMaxHa or 0) > 0 then return "SIZE LIMITED" end
    return "ALLOWED"
end

function CCO:ruleModeTitle(mode)
    if mode == "disabled" then return "Disabled crop rules" end
    if mode == "limited" then return "Size-limited NPC crop rules" end
    if mode == "blockedrules" or mode == "blocked-rules" then return "NPC-disabled crop rules" end
    if mode == "undiscovered" then return "Configured but not loaded on this map" end
    return "All configured crop rules"
end


function CCO:getGuiRuleRows(mode)
    mode = mode ~= nil and string.lower(tostring(mode)) or "rules"

    local names = {}
    for nameU, _ in pairs(self._rules or {}) do
        table.insert(names, nameU)
    end
    table.sort(names)

    local rows = {}
    for _, nameU in ipairs(names) do
        local r = self._rules[nameU]
        local include = true
        if mode == "disabled" then include = r.enabled == false end
        if mode == "limited" then include = tonumber(r.npcMaxHa or 0) > 0 end
        if mode == "blockedrules" or mode == "blocked-rules" then include = r.enabled == false or r.npcAllowed == false end
        if mode == "undiscovered" then include = getFruitByName(nameU) == nil end

        if include then
            local enabledBool = r.enabled ~= false
            local loadedBool = getFruitByName(nameU) ~= nil
            local npcValue = "mapDefault"
            if r.npcAllowed == true then
                npcValue = "yes"
            elseif r.npcAllowed == false then
                npcValue = "no"
            end

            table.insert(rows, {
                crop = nameU,
                enabled = boolTextOnOff(enabledBool),
                enabledBool = enabledBool,
                npc = policyTextOnOff(r.npcAllowed),
                npcValue = npcValue,
                maxHa = tonumber(r.npcMaxHa or 0) or 0,
                maxHaDisplay = formatHaAcCompact(r.npcMaxHa or 0),
                reseedWeight = clampWeight(r.reseedWeight, DEFAULT_FRUIT_RESEED_WEIGHT),
                loaded = loadedBool and "Yes" or "No",
                loadedBool = loadedBool,
                status = self:ruleStatusText(nameU, r),
            })
        end
    end

    return rows
end

function CCO:buildGuiRuleListText(mode, pageArg)
    mode = mode ~= nil and string.lower(tostring(mode)) or "rules"
    local rows = self:getGuiRuleRows(mode)
    local count = #rows

    local pageSize = 200
    local totalPages = math.max(1, math.ceil(count / pageSize))
    local page = tonumber(pageArg or 1) or 1
    page = math.floor(page)
    if page < 1 then page = 1 end
    if page > totalPages then page = totalPages end

    local startIndex = ((page - 1) * pageSize) + 1
    local endIndex = math.min(startIndex + pageSize - 1, count)

    local lines = {
        ("%s — Page %d/%d"):format(self:ruleModeTitle(mode), page, totalPages),
        "",
        string.format("%-16s %-7s %-11s %-17s %-10s %-10s", "Crop", "Player", "NPC", "Max Field", "Loaded", "Status"),
        string.rep("-", 82),
    }

    local shown = 0
    for i = startIndex, endIndex do
        local row = rows[i]
        if row ~= nil then
            shown = shown + 1
            table.insert(lines, string.format("%-16s %-7s %-11s %-17s %-10s %-10s",
                row.crop, row.enabled, tostring(row.npc), row.maxHaDisplay, row.loaded, row.status))
        end
    end

    if count == 0 then
        table.insert(lines, "No matching crop rules.")
    elseif page < totalPages then
        table.insert(lines, ("Page %d/%d. Use ccoGui %s %d for next page."):format(page, totalPages, mode == "rules" and "rules" or mode, page + 1))
    elseif totalPages > 1 then
        table.insert(lines, ("Page %d/%d. End of list."):format(page, totalPages))
    end

    table.insert(lines, "")
    if count > 0 then
        table.insert(lines, ("Shown %d-%d of %d matching rule(s)."):format(startIndex, endIndex, count))
    else
        table.insert(lines, "Shown 0 of 0 matching rule(s).")
    end
    return table.concat(lines, "\n")
end

function CCO:buildGuiBlockedText()
    local summary = self:buildFieldSummary(nil)
    if (summary.offending or 0) == 0 then
        return table.concat({
            "SAVE VALIDATION",
            "Validation:     PASS",
            "",
            ("Checked fields: %d"):format(tonumber(summary.total or 0)),
            ("NPC fields:     %d"):format(tonumber(summary.npcTotal or 0)),
            ("Player fields:  %d"):format(tonumber(summary.playerTotal or 0)),
            "Blocked NPC fields: 0",
            "",
            "No blocked NPC fields were detected under the current crop policy.",
        }, "\n")
    end

    local lines = {
        "SAVE VALIDATION",
        "Validation:     FAILED",
        ("Blocked NPC fields: %d"):format(tonumber(summary.offending or 0)),
        "",
        "BLOCKED NPC FIELD DETAILS",
        "Field       Crop             Size ha   Candidate        Reason",
        "--------------------------------------------------------------------------",
    }

    if g_fieldManager ~= nil and g_fieldManager.getFields ~= nil then
        local fields = g_fieldManager:getFields()
        local rows = {}

        for i, field in pairs(fields or {}) do
            local ft = getFieldFruit(field)
            if ft ~= nil then
                local cropName = upper(ft.name)
                local blocked, reason = self:shouldResetNpcField(field, cropName)
                if blocked then
                    local candidateCrop, candidateReason = self:getReseedCandidateTextForField(field, cropName)
                    table.insert(rows, {
                        fieldId = tostring(getFieldId(field, i)),
                        cropName = cropName,
                        sizeHa = getFieldSizeHa(field),
                        candidateCrop = candidateCrop,
                        candidateReason = candidateReason,
                        reason = tostring(reason or "blocked"),
                    })
                end
            end
        end

        table.sort(rows, function(a, b)
            local an = tonumber(a.fieldId)
            local bn = tonumber(b.fieldId)
            if an ~= nil and bn ~= nil then return an < bn end
            return tostring(a.fieldId) < tostring(b.fieldId)
        end)

        local maxRows = 12
        for i, row in ipairs(rows) do
            if i > maxRows then
                table.insert(lines, ("... %d more blocked NPC field(s). Use ccoScanBlocked for the full console list."):format(#rows - maxRows))
                break
            end

            table.insert(lines, ("%-11s %-16s %7.2f   %-16s %s"):format(
                row.fieldId,
                row.cropName,
                tonumber(row.sizeHa or 0) or 0,
                tostring(row.candidateCrop or "NONE"),
                row.reason
            ))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "GUI CLEANUP")
    table.insert(lines, "1. Use RESET SCOPE to choose ALL, a crop, or an individual field.")
    table.insert(lines, "2. Run RESET BLOCKED DRY-RUN before changing the save state.")
    table.insert(lines, "3. Use CONFIRM RESET only after the dry-run result looks correct.")
    table.insert(lines, "")
    table.insert(lines, "Console alternatives remain available: ccoScanBlocked, ccoResetBlocked dryrun, ccoResetBlocked.")
    return table.concat(lines, "\n")
end

function CCO:buildGuiHelpText()
    return table.concat({
        "CROP CONTROL OVERRIDE HELP",
        "",
        "NAVIGATION",
        "Use the tab headings or PREV TAB / NEXT TAB to switch sections.",
        "Use BACK or ESC to close the CCO screen.",
        "",
        "EDITING",
        "Use ALL RULES to select a crop and stage changes in the right panel.",
        "APPLY writes safe changes to the active per-save XML.",
        "FORCE APPLY deliberately saves a rule that creates blocked NPC fields.",
        "DISCARD resets staged values for the selected crop.",
        "",
        "CONFIG FILES",
        "config.xml is the template/default rule file.",
        "saves/savegameX.xml is the active rule file for the current save.",
        "SAVE DEFAULTS exports the full active save rules to config.xml and creates a backup.",
        "LOAD DEFAULTS imports config.xml into this save and overwrites the active per-save XML.",
        "",
        "TABLE COLUMNS",
        "Player Permitted: whether the crop is available under the crop policy.",
        "NPC Permitted: whether NPCs may plant the crop, or whether the map default is used.",
        "Max Field: maximum actual NPC field size. Values are stored in hectares; acres are shown for reference.",
        "Loaded: whether the crop exists on the active map/save.",
        "",
        "POLICY TERMS",
        "Disabled: the crop is unavailable under the crop policy.",
        "NPC Disabled: NPCs should not plant this crop. Globally disabled crops also count as NPC-disabled.",
        "Size Limited: NPCs may plant the crop only below the configured hectare limit.",
        "Blocked NPC Fields: existing NPC fields that currently violate the active policy.",
        "Not Loaded: the rule is preserved, but the crop is not present on this map/save.",
        "",
        "VALIDATION CLEANUP",
        "Use RESET SCOPE to cycle through ALL, CROP, and FIELD cleanup targets.",
        "Run RESET BLOCKED DRY-RUN first. It does not change the save state.",
        "Use CONFIRM RESET only after the dry-run result looks correct.",
        "Console alternatives remain available: ccoScanBlocked and ccoResetBlocked dryrun.",
    }, "\n")
end

function CCO:openGui(topic, pageArg)
    if isClientOnlyMultiplayer() and self._serverSettingsSynced ~= true then
        local ok, msg = self:requestServerSettings("openGui")
        local status = tostring(msg or self._guiNotice or "Waiting for server CCO rules.")
        local body = table.concat({
            "CROP CONTROL OVERRIDE - SERVER SYNC",
            "",
            status,
            "",
            "This is a remote multiplayer client. Local CCO config.xml and savegame?.xml files are not used in this session.",
            "",
            "Open CCO again once the server snapshot has been received, or use ccoReload to request the server rules again.",
        }, "\n")
        return showCcoCustomGui("Crop Control Override - Waiting for Server Rules", body, "status", 1)
    end
    topic = topic ~= nil and topic ~= "" and string.lower(tostring(topic)) or "rules"
    if topic == "status" then
        return showCcoCustomGui("Crop Control Override - Summary", self:buildGuiStatusText(), "status", 1)
    elseif topic == "rules" then
        return showCcoCustomGui("Crop Control Override - Configured Rules", self:buildGuiRuleListText("rules", pageArg), "rules", pageArg or 1)
    elseif topic == "disabled" then
        return showCcoCustomGui("Crop Control Override - Disabled Crops", self:buildGuiRuleListText("disabled", pageArg), "disabled", pageArg or 1)
    elseif topic == "limited" then
        return showCcoCustomGui("Crop Control Override - Size-Limited Crops", self:buildGuiRuleListText("limited", pageArg), "limited", pageArg or 1)
    elseif topic == "blockedrules" or topic == "blocked-rules" then
        return showCcoCustomGui("Crop Control Override - Blocked Rules", self:buildGuiRuleListText("blockedrules", pageArg), "blockedrules", pageArg or 1)
    elseif topic == "blocked" then
        return showCcoCustomGui("Crop Control Override - Blocked Fields", self:buildGuiBlockedText(), "blocked", 1)
    elseif topic == "undiscovered" then
        return showCcoCustomGui("Crop Control Override - Undiscovered Rules", self:buildGuiRuleListText("undiscovered", pageArg), "undiscovered", pageArg or 1)
    elseif topic == "help" then
        return showCcoCustomGui("Crop Control Override - GUI Help", self:buildGuiHelpText(), "help", 1)
    end

    return showCcoCustomGui("Crop Control Override - GUI Help", "Unknown topic: " .. tostring(topic) .. "\n\n" .. self:buildGuiHelpText(), "help", 1)
end



local function cloneRulesForGuiApply(rules)
    local cloned = {}
    for nameU, rule in pairs(rules or {}) do
        cloned[nameU] = {
            name = rule.name or nameU,
            enabled = rule.enabled ~= false,
            npcAllowed = rule.npcAllowed,
            npcMaxHa = tonumber(rule.npcMaxHa or 0) or 0,
            resetNpcFields = rule.resetNpcFields ~= false,
            reseedWeight = clampWeight(rule.reseedWeight, DEFAULT_FRUIT_RESEED_WEIGHT),
        }
    end
    return cloned
end


function CCO:loadTemplateDefaultsIntoCurrentSave()
    if not self:canEditRules() then
        local msg = "CCO defaults are read-only for remote multiplayer clients. Log in as server admin/master user to change them."
        self._guiNotice = msg
        return false, msg
    end
    if self:_shouldUseMultiplayerEvent() then
        return self:_sendMultiplayerEvent("loadDefaults")
    end
    return self:_loadTemplateDefaultsIntoCurrentSaveLocal()
end

function CCO:buildFieldSummaryWithRules(rules, filterCrop)
    local oldRules = self._rules
    self._rules = rules
    local summary = self:buildFieldSummary(filterCrop)
    self._rules = oldRules
    return summary
end




function CCO:_refreshOpenGuiPermissionState(msg)
    local controller = nil
    if CropControlOverrideMenu ~= nil then
        controller = CropControlOverrideMenu.INSTANCE
    end

    if controller ~= nil and controller.showTopic ~= nil then
        pcall(function()
            controller:showTopic(controller.currentTopic or "rules", controller.currentPage or 1)
        end)
    end

    if msg ~= nil then
        self._guiNotice = tostring(msg)
    end
end

function CCO:_setServerConnectionMasterUser(connection, isMasterUser)
    if connection == nil then
        return false
    end

    self._connectionToMasterUser = self._connectionToMasterUser or {}

    if isMasterUser == true then
        local user = true
        if g_currentMission ~= nil and g_currentMission.userManager ~= nil and g_currentMission.userManager.getUserByConnection ~= nil then
            local okUser, resolvedUser = pcall(function()
                return g_currentMission.userManager:getUserByConnection(connection)
            end)
            if okUser and resolvedUser ~= nil then
                user = resolvedUser
            end
        end
        self._connectionToMasterUser[connection] = user
        return true
    end

    self._connectionToMasterUser[connection] = nil
    return true
end

function CCO:_notifyServerOfLocalMasterUserState(reason)
    if not isClientOnlyMultiplayer() then
        return false
    end
    if CropControlOverrideChangeSettingsEvent == nil then
        return false
    end
    if g_client == nil or g_client.getServerConnection == nil then
        return false
    end

    local connection = g_client:getServerConnection()
    if connection == nil or connection.sendEvent == nil then
        return false
    end

    local isMasterUser = getLocalMissionMasterUserState() == true
    if self._clientReportedMasterUser == isMasterUser and reason ~= "force" then
        return false
    end

    self._clientReportedMasterUser = isMasterUser
    connection:sendEvent(CropControlOverrideChangeSettingsEvent.new("adminStatus", tostring(isMasterUser), tostring(reason or "statusChanged")))
    return true
end

function CCO:_onLocalAdminStateChanged(reason)
    local wasEditable = self._serverCanEditRules == true

    if getLocalMissionMasterUserState() == true then
        self._serverCanEditRules = true
    elseif isClientOnlyMultiplayer() then
        self._serverCanEditRules = false
    end

    self:_notifyServerOfLocalMasterUserState(reason or "adminStateChanged")

    if isClientOnlyMultiplayer() then
        self:requestServerSettings(reason or "adminStateChanged")
    end

    if self._serverCanEditRules ~= wasEditable then
        local msg = self._serverCanEditRules == true
            and "CCO admin access enabled for this session."
            or "CCO admin access removed; server rules are read-only."
        self:_refreshOpenGuiPermissionState(msg)
    else
        self:_refreshOpenGuiPermissionState(nil)
    end
end

function CCO:onNativeAdminAccessGranted()
    self:_onLocalAdminStateChanged("gameAdminLogin")
end

function CCO:onPlayerFarmChanged(player)
    if player == nil or player == g_localPlayer then
        self:_onLocalAdminStateChanged("playerFarmChanged")
    end
end

function CCO:onMasterUserAdded(user)
    if user ~= nil and user.getConnection ~= nil then
        local ok, connection = pcall(function() return user:getConnection() end)
        if ok and connection ~= nil then
            self:_setServerConnectionMasterUser(connection, true)
        end
    end

    if g_currentMission ~= nil and user ~= nil and user.getId ~= nil then
        local ok, userId = pcall(function() return user:getId() end)
        if ok and userId == g_currentMission.playerUserId then
            self:_onLocalAdminStateChanged("masterUserAdded")
        end
    end
end

function CCO:onUserAdded(user)
    if user == nil or user.getConnection == nil then
        return
    end

    -- Local server/host authority is always trusted. Track that connection too,
    -- matching the EasyDevControls master-user model.
    if g_currentMission ~= nil and user.getId ~= nil then
        local okId, userId = pcall(function() return user:getId() end)
        if okId and userId == g_currentMission.playerUserId then
            local okCon, connection = pcall(function() return user:getConnection() end)
            if okCon and connection ~= nil then
                self:_setServerConnectionMasterUser(connection, true)
            end
        end
    end
end

function CCO:onUserRemoved(user)
    if user ~= nil and user.getConnection ~= nil then
        local ok, connection = pcall(function() return user:getConnection() end)
        if ok and connection ~= nil then
            self:_setServerConnectionMasterUser(connection, false)
        end
    end
end

function CCO:installPermissionHooks()
    if self._permissionHooksApplied == true or g_messageCenter == nil or MessageType == nil then
        return
    end

    self._permissionHooksApplied = true
    self._connectionToMasterUser = self._connectionToMasterUser or {}

    if MessageType.MASTERUSER_ADDED ~= nil then
        g_messageCenter:subscribe(MessageType.MASTERUSER_ADDED, self.onMasterUserAdded, self)
    end
    if MessageType.USER_ADDED ~= nil then
        g_messageCenter:subscribe(MessageType.USER_ADDED, self.onUserAdded, self)
    end
    if MessageType.USER_REMOVED ~= nil then
        g_messageCenter:subscribe(MessageType.USER_REMOVED, self.onUserRemoved, self)
    end
    if MessageType.PLAYER_FARM_CHANGED ~= nil then
        g_messageCenter:subscribe(MessageType.PLAYER_FARM_CHANGED, self.onPlayerFarmChanged, self)
    end
    if PlayerPermissionsEvent ~= nil then
        g_messageCenter:subscribe(PlayerPermissionsEvent, self.onNativeAdminAccessGranted, self)
    end
    if GetAdminAnswerEvent ~= nil then
        g_messageCenter:subscribe(GetAdminAnswerEvent, self.onNativeAdminAccessGranted, self)
    end
end

function CCO:getIsAdminConnection(connection)
    -- Server/host/local calls have no remote connection and are authoritative.
    if connection == nil then
        return true
    end

    if self._connectionToMasterUser ~= nil and self._connectionToMasterUser[connection] ~= nil then
        return true
    end

    if connection ~= nil then
        local connectionChecks = { "getIsMasterUser", "getIsAdmin", "getIsServerAdmin" }
        for _, fn in ipairs(connectionChecks) do
            if connection[fn] ~= nil then
                local okCheck, value = pcall(function() return connection[fn](connection) end)
                if okCheck and value == true then
                    self:_setServerConnectionMasterUser(connection, true)
                    return true
                end
            end
        end
        if connection.isMasterUser == true or connection.isAdmin == true or connection.isServerAdmin == true then
            self:_setServerConnectionMasterUser(connection, true)
            return true
        end
    end

    -- Defensive fallback: if FS25 exposes the remote user and marks it directly
    -- as master/admin, honour that without requiring CCO to own an admin login.
    if g_currentMission ~= nil and g_currentMission.userManager ~= nil and g_currentMission.userManager.getUserByConnection ~= nil then
        local ok, user = pcall(function()
            return g_currentMission.userManager:getUserByConnection(connection)
        end)
        if ok and user ~= nil then
            local checks = { "getIsMasterUser", "getIsAdmin", "getIsServerAdmin" }
            for _, fn in ipairs(checks) do
                if user[fn] ~= nil then
                    local okCheck, value = pcall(function() return user[fn](user) end)
                    if okCheck and value == true then
                        self:_setServerConnectionMasterUser(connection, true)
                        return true
                    end
                end
            end
            if user.isMasterUser == true or user.isAdmin == true or user.isServerAdmin == true then
                self:_setServerConnectionMasterUser(connection, true)
                return true
            end
            if user.getId ~= nil then
                local okId, userId = pcall(function() return user:getId() end)
                if okId and userId ~= nil then
                    local missionChecks = { "getIsUserMasterUser", "getIsUserAdmin", "getIsMasterUser" }
                    for _, fn in ipairs(missionChecks) do
                        if g_currentMission[fn] ~= nil then
                            local okMission, value = pcall(function() return g_currentMission[fn](g_currentMission, userId) end)
                            if okMission and value == true then
                                self:_setServerConnectionMasterUser(connection, true)
                                return true
                            end
                        end
                    end
                    local managerChecks = { "getIsUserMasterUser", "getIsUserAdmin", "getIsMasterUser" }
                    for _, fn in ipairs(managerChecks) do
                        if g_currentMission.userManager[fn] ~= nil then
                            local okManager, value = pcall(function() return g_currentMission.userManager[fn](g_currentMission.userManager, userId) end)
                            if okManager and value == true then
                                self:_setServerConnectionMasterUser(connection, true)
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end

-- Install permission hooks after the hook functions have been defined.
-- Calling this earlier during Lua load can fail because method declarations below
-- the call have not yet been assigned to the CCO table.
CCO:installPermissionHooks()

function CCO:isClientOnlyMultiplayer()
    return isClientOnlyMultiplayer()
end

function CCO:canEditRules()
    return ccoCanEditRules()
end

function CCO:requestServerSettings(reason)
    if not isClientOnlyMultiplayer() then
        return false, "CCO server sync is only needed by remote multiplayer clients."
    end
    if CropControlOverrideChangeSettingsEvent == nil then
        return false, "CCO multiplayer event is not available."
    end

    self._awaitingServerSettings = true
    self._pendingServerSettingsReason = tostring(reason or "manual")

    if g_client == nil or g_client.getServerConnection == nil then
        self._guiNotice = "Waiting for multiplayer server connection before syncing CCO rules."
        return false, self._guiNotice
    end

    local connection = g_client:getServerConnection()
    if connection == nil or connection.sendEvent == nil then
        self._guiNotice = "Waiting for multiplayer server connection before syncing CCO rules."
        return false, self._guiNotice
    end

    self:_notifyServerOfLocalMasterUserState("requestSettings")
    local event = CropControlOverrideChangeSettingsEvent.new("requestSettings", tostring(reason or self._pendingServerSettingsReason or "manual"), tostring(getLocalMissionMasterUserState() == true))
    connection:sendEvent(event)
    self._pendingServerSettingsReason = nil
    self._guiNotice = "Requested CCO rules from server."
    return true, self._guiNotice
end

function CCO:applyServerSettingsPayload(payload, configPath, saveId, canEdit)
    local rules, settings = deserializeRulesFromMultiplayer(payload)
    self._rules = rules
    self._settings = settings or { reseedWeights = normalizeReseedWeights(nil) }
    self._configPath = "server:" .. tostring(saveId or "active")
    self._serverConfigPath = tostring(configPath or "server")
    self._serverSaveId = tostring(saveId or "")
    if canEdit ~= nil and tostring(canEdit) ~= "" then
        self._serverCanEditRules = boolFromStringOrBool(canEdit, false) == true
    end
    self._awaitingServerSettings = false
    self._serverSettingsSynced = true
    self._mpClientOnly = true
    self._serverSettingsRetryTimer = 0
    self._serverSettingsRetryCount = 0
    -- applyRules also rebuilds the seed lists of already-loaded sowing
    -- machines, so a snapshot that arrives after vehicles loaded still takes
    -- effect immediately.
    self:applyRules(self._rules)
    local msg = self._serverCanEditRules == true
        and "Server CCO rules synced. Admin editing is enabled for this session. Local CCO XML files were not read or written."
        or "Server CCO rules synced. Local CCO XML files were not read or written."
    self._guiNotice = msg
    self:refreshOpenGuiAfterMultiplayerSync("syncSettings", msg)
    return true, msg
end

function CCO:sendSettingsSnapshotToClient(connection, reason)
    if self._rules == nil or not next(self._rules) then
        if not isClientOnlyMultiplayer() then
            pcall(function() self:loadRulesForMission(g_currentMission and g_currentMission.missionInfo) end)
        end
    end

    if CropControlOverrideChangeSettingsEvent == nil then
        return false, "CCO multiplayer event is not available."
    end

    local saveId = getSaveIdFromMissionInfo(g_currentMission and g_currentMission.missionInfo) or tostring(self._serverSaveId or "active")
    local payload = serializeRulesForMultiplayer(self._rules or buildDefaultRules(), self._settings)
    local canEdit = ""
    if connection ~= nil then
        canEdit = tostring(self:getIsAdminConnection(connection) == true)
    end
    local event = CropControlOverrideChangeSettingsEvent.new("syncSettings", payload, tostring(self._configPath or "server"), tostring(saveId or "active"), tostring(reason or "server"), canEdit)

    if connection ~= nil and connection.sendEvent ~= nil then
        connection:sendEvent(event)
        return true, "Sent CCO server rules to client."
    end

    if g_server ~= nil then
        g_server:broadcastEvent(event, false)
        return true, "Broadcast CCO server rules to clients."
    end

    return false, "No connection/server available for CCO settings sync."
end

function CCO:_shouldUseMultiplayerEvent()
    if self._handlingMpEvent == true then
        return false
    end
    if CropControlOverrideChangeSettingsEvent == nil then
        return false
    end
    return g_client ~= nil or g_server ~= nil
end

function CCO:_sendMultiplayerEvent(operation, a, b, c, d, e, f, g)
    if isClientOnlyMultiplayer() and operation ~= "requestSettings" and not self:canEditRules() then
        local msg = "CCO rules are read-only for remote multiplayer clients. Log in as server admin/master user to change them."
        self._guiNotice = msg
        return false, msg
    end

    if CropControlOverrideChangeSettingsEvent == nil then
        return false, "CCO multiplayer event is not available."
    end

    if isClientOnlyMultiplayer() and operation ~= "requestSettings" and operation ~= "syncSettings" then
        self:_notifyServerOfLocalMasterUserState("beforeEdit")
    end

    local event = CropControlOverrideChangeSettingsEvent.new(operation, a, b, c, d, e, f, g)

    if g_client ~= nil and g_server == nil and g_client.getServerConnection ~= nil then
        local connection = g_client:getServerConnection()
        if connection ~= nil and connection.sendEvent ~= nil then
            connection:sendEvent(event)
            local msg = "Sent CCO " .. tostring(operation) .. " request to the server."
            self._guiNotice = msg
            return true, msg
        end
        local msg = "Waiting for multiplayer server connection before sending CCO " .. tostring(operation) .. " request."
        self._guiNotice = msg
        return false, msg
    end

    if g_server ~= nil then
        local ok, msg, extra = self:handleMultiplayerEvent(operation, {a, b, c, d, e, f, g}, nil)
        if operation ~= "requestSettings" and operation ~= "syncSettings" and ok == true then
            self:sendSettingsSnapshotToClient(nil, operation)
        end
        return ok, msg, extra
    end

    return false, "No multiplayer connection is available."
end

function CCO:refreshOpenGuiAfterMultiplayerSync(operation, msg)
    self._guiNotice = tostring(msg or self._guiNotice or "CCO settings synced from server.")

    local controller = nil
    if CropControlOverrideMenu ~= nil then
        controller = CropControlOverrideMenu.INSTANCE
    end

    if controller ~= nil and controller.showTopic ~= nil then
        local topic = controller.currentTopic or "rules"
        local page = controller.currentPage or 1
        pcall(function()
            controller:showTopic(topic, page)
        end)

        if controller.selectedDirtyText ~= nil and controller.selectedDirtyText.setText ~= nil then
            pcall(function()
                controller.selectedDirtyText:setText("Settings synced from server.")
            end)
        end
        if controller.selectedInfoText ~= nil and controller.selectedInfoText.setText ~= nil then
            pcall(function()
                controller.selectedInfoText:setText(tostring(self._guiNotice or "Server settings applied."))
            end)
        end
    end
end

function CCO:handleMultiplayerEvent(operation, args, connection)
    args = args or {}
    self._handlingMpEvent = true

    local ok, r1, r2, r3 = pcall(function()
        if operation == "syncSettings" then
            return self:applyServerSettingsPayload(args[1], args[2], args[3], args[5])
        elseif operation == "adminStatus" then
            if g_server ~= nil and connection ~= nil then
                self:_setServerConnectionMasterUser(connection, boolFromStringOrBool(args[1], false) == true)
                return self:sendSettingsSnapshotToClient(connection, args[2] or "adminStatus")
            end
            return true, "CCO admin status ignored outside server context."
        elseif operation == "requestSettings" then
            if g_server ~= nil and connection ~= nil and boolFromStringOrBool(args[2], false) == true then
                self:_setServerConnectionMasterUser(connection, true)
            end
            return self:sendSettingsSnapshotToClient(connection, args[1])
        elseif g_server ~= nil and connection ~= nil and not self:getIsAdminConnection(connection) then
            local msg = "CCO edit rejected: this player is not logged in as a server admin/master user."
            warn(msg)
            self:sendSettingsSnapshotToClient(connection, "editRejected")
            return false, msg
        elseif isClientOnlyMultiplayer() and not self:canEditRules() then
            return false, "CCO rules are read-only for remote multiplayer clients. Log in as server admin/master user to change them."
        elseif operation == "applyRule" then
            local staged = {
                crop = args[1],
                enabled = boolFromStringOrBool(args[2], true) == true,
                npc = tostring(args[3] or "mapDefault"),
                maxHa = tonumber(args[4] or 0) or 0,
                resetNpcFields = boolFromStringOrBool(args[5], true) ~= false,
                reseedWeight = tonumber(args[6]),
            }
            local forceApply = boolFromStringOrBool(args[7], false) == true
            return self:_applyGuiStagedRuleLocal(staged, forceApply)
        elseif operation == "saveDefaults" then
            return self:_saveCurrentRulesToTemplateConfigLocal()
        elseif operation == "loadDefaults" then
            return self:_loadTemplateDefaultsIntoCurrentSaveLocal()
        elseif operation == "resetBlocked" then
            local scopeArg = args[1]
            local scope = scopeArg
            if type(scopeArg) == "string" then
                local mode, value = string.match(scopeArg, "^([^:]+):(.*)$")
                if mode == "all" then
                    scope = { mode = "all", label = "ALL" }
                elseif mode == "crop" then
                    scope = { mode = "crop", crop = upper(value or ""), label = upper(value or "") }
                elseif mode == "field" then
                    scope = { mode = "field", fieldId = tonumber(value), label = "FIELD " .. tostring(value) }
                end
            end
            return self:_resetBlockedFieldsFromGuiLocal(scope, args[2])
        elseif operation == "consoleSetCrop" then
            return self:_consoleSetCropLocal(args[1], args[2], args[3], args[4])
        end
        return false, "Unknown CCO multiplayer operation: " .. tostring(operation)
    end)

    self._handlingMpEvent = false

    if not ok then
        local msg = "CCO multiplayer event failed: " .. tostring(r1)
        warn(msg)
        self._guiNotice = msg
        return false, msg
    end

    if r1 == true and g_client ~= nil and self.refreshOpenGuiAfterMultiplayerSync ~= nil then
        self:refreshOpenGuiAfterMultiplayerSync(operation, r2)
    end

    return r1, r2, r3
end

function CCO:applyGuiStagedRule(staged, forceApply)
    if not self:canEditRules() then
        local msg = "CCO rules are read-only for remote multiplayer clients. Log in as server admin/master user to change them."
        self._guiNotice = msg
        return false, msg
    end

    if self:_shouldUseMultiplayerEvent() then
        local npc = staged ~= nil and staged.npc or "mapDefault"
        return self:_sendMultiplayerEvent(
            "applyRule",
            staged ~= nil and staged.crop or "",
            tostring(staged ~= nil and staged.enabled == true),
            tostring(npc or "mapDefault"),
            tostring(staged ~= nil and staged.maxHa or 0),
            tostring(staged == nil or staged.resetNpcFields ~= false),
            tostring(staged ~= nil and staged.reseedWeight or DEFAULT_FRUIT_RESEED_WEIGHT),
            tostring(forceApply == true)
        )
    end

    return self:_applyGuiStagedRuleLocal(staged, forceApply)
end

function CCO:_applyGuiStagedRuleLocal(staged, forceApply)
    if staged == nil or staged.crop == nil or staged.crop == "" then
        return false, "No crop selected."
    end

    local nameU = upper(staged.crop)
    local enabled = staged.enabled == true
    local npcAllowed = nil
    if staged.npc == "yes" then
        npcAllowed = true
    elseif staged.npc == "no" then
        npcAllowed = false
    else
        npcAllowed = nil
    end
    local npcMaxHa = math.max(0, tonumber(staged.maxHa or 0) or 0)
    local resetNpcFields = staged.resetNpcFields ~= false
    local reseedWeight = clampWeight(staged.reseedWeight, DEFAULT_FRUIT_RESEED_WEIGHT)

    self._rules = self._rules or buildDefaultRules()

    local proposedRules = cloneRulesForGuiApply(self._rules)
    proposedRules[nameU] = normalizeRule(nameU, {
        enabled = enabled,
        npcAllowed = npcAllowed,
        npcMaxHa = npcMaxHa,
        resetNpcFields = resetNpcFields,
        reseedWeight = reseedWeight,
    })

    local preflight = self:buildFieldSummaryWithRules(proposedRules, nameU)
    local preflightOffending = tonumber(preflight.offending or 0) or 0
    if preflightOffending > 0 and forceApply ~= true then
        local msg = ("Apply blocked for %s: proposed rule would create %d blocked NPC field(s). Click FORCE APPLY to save anyway, then review VALIDATION before cleanup."):format(
            nameU, preflightOffending)
        print("CCO GUI APPLY BLOCKED: " .. msg)
        self._guiNotice = msg
        return false, msg, true
    end

    self._rules = proposedRules

    local sid = getSaveIdFromMissionInfo(g_currentMission and g_currentMission.missionInfo)
    local per = sid ~= nil and perSavePathForId(sid) or nil
    local tpl = templatePath()

    if per ~= nil then
        if self._configPath == nil or self._configPath == tpl or self._configPath ~= per then
            if not fileExists(per) then
                writeConfig(per, self._rules, self._settings)
            end
            self._configPath = per
        end
    elseif self._configPath == nil then
        self._configPath = tpl
    end

    local writeOk = writeConfig(self._configPath, self._rules, self._settings)
    if not writeOk then
        return false, "Failed to write active CCO config."
    end

    self:applyRules(self._rules)

    local summary = self:buildFieldSummary(nil)
    local validation = (summary.offending or 0) == 0
        and "validation passed"
        or ("validation failed; offendingNpcFields=" .. tostring(summary.offending or 0))

    local npcText = npcAllowed == nil and "mapDefault" or tostring(npcAllowed)
    local msg = ("Applied %s enabled=%s npcAllowed=%s npcMaxHa=%.2f resetNpcFields=%s; %s"):format(
        nameU, tostring(enabled), npcText, npcMaxHa, tostring(resetNpcFields), validation)

    if forceApply == true then
        msg = msg .. " (forced)"
    end
    msg = msg .. "; target=" .. tostring(self._configPath)
    print("CCO GUI APPLY: " .. msg)
    self._guiNotice = msg
    return true, msg
end


function CCO:_saveCurrentRulesToTemplateConfigLocal()
    local rules = self._rules
    if rules == nil or not next(rules) then
        return false, "No active CCO rules are loaded."
    end

    local tpl = templatePath()
    local stamp = (os ~= nil and os.date ~= nil) and os.date("%Y%m%d_%H%M%S") or tostring(g_time or "unknown")
    local backupPath = settingsRoot() .. "backups/config_backup_" .. stamp .. ".xml"

    local backupRules = nil
    if fileExists(tpl) then
        local backupSettings
        backupRules, backupSettings = readConfig(tpl)
        if backupRules == nil or not next(backupRules) then
            backupRules = buildDefaultRules()
        end

        if not writeConfig(backupPath, backupRules, backupSettings or self._settings) then
            local msg = "Failed to create template backup; config.xml was not changed."
            print("CCO GUI SAVE DEFAULTS: " .. msg)
            self._guiNotice = msg
            return false, msg
        end
    end

    if not writeConfig(tpl, rules, self._settings) then
        local msg = "Failed to write template config.xml."
        print("CCO GUI SAVE DEFAULTS: " .. msg)
        self._guiNotice = msg
        return false, msg
    end

    local msg = "Saved current active rules to template config.xml. Existing per-save XML files were not overwritten"
    if backupRules ~= nil then
        msg = msg .. "; backup=" .. tostring(backupPath)
    else
        msg = msg .. "; no previous config.xml found"
    end

    print("CCO GUI SAVE DEFAULTS: " .. msg)
    self._guiNotice = msg
    return true, msg
end




function CCO:saveCurrentRulesToTemplateConfig()
    if not self:canEditRules() then
        local msg = "CCO defaults are read-only for remote multiplayer clients. Log in as server admin/master user to change them."
        self._guiNotice = msg
        return false, msg
    end
    if self:_shouldUseMultiplayerEvent() then
        return self:_sendMultiplayerEvent("saveDefaults")
    end
    return self:_saveCurrentRulesToTemplateConfigLocal()
end

function CCO:_loadTemplateDefaultsIntoCurrentSaveLocal()
    local sid = getSaveIdFromMissionInfo(g_currentMission and g_currentMission.missionInfo)
    local per = sid ~= nil and perSavePathForId(sid) or nil
    local tpl = templatePath()

    local templateRules, templateSettings = readConfig(tpl)
    if templateRules == nil or not next(templateRules) then
        templateRules = buildDefaultRules()
    end
    templateSettings = templateSettings or { reseedWeights = normalizeReseedWeights(nil) }

    templateRules = mergeMissingDiscoveredFruits(templateRules)

    if per == nil then
        self._rules = templateRules
        self._settings = templateSettings
        self._configPath = tpl
        self:applyRules(templateRules)
        local msg = "Loaded template config.xml. No savegame context was available, so no per-save XML was written."
        print("CCO GUI LOAD DEFAULTS: " .. msg)
        self._guiNotice = msg
        return true, msg
    end

    if not writeConfig(per, templateRules, templateSettings) then
        local msg = "Failed to write template defaults into active per-save XML."
        print("CCO GUI LOAD DEFAULTS: " .. msg)
        self._guiNotice = msg
        return false, msg
    end

    self._rules = templateRules
    self._settings = templateSettings
    self._configPath = per
    self:applyRules(templateRules)

    local msg = "Loaded template config.xml into active save config: " .. tostring(per)
    print("CCO GUI LOAD DEFAULTS: " .. msg)
    self._guiNotice = msg
    return true, msg
end


-- Global GUI hotkey ---------------------------------------------------------
function CCO:onInputOpenGui(actionName, inputValue, callbackState, isAnalog)
    if g_gui ~= nil and g_gui.currentGui ~= nil and g_gui.currentGui.name == "CropControlOverrideMenu" then
        return
    end
    self:openGui("rules", 1)
end

function CCO:registerGlobalActionEvents(player, inputBinding)
    if inputBinding == nil or InputAction == nil or InputAction.CCO_OPEN_GUI == nil then
        return
    end

    local ok, _, eventId = pcall(function()
        return inputBinding:registerActionEvent(InputAction.CCO_OPEN_GUI, self, self.onInputOpenGui, false, true, false, true)
    end)

    if ok and eventId ~= nil then
        self._openGuiActionEventId = eventId
        if inputBinding.setActionEventText ~= nil and g_i18n ~= nil then
            inputBinding:setActionEventText(eventId, g_i18n:getText("input_CCO_OPEN_GUI"))
        end
        if inputBinding.setActionEventTextVisibility ~= nil then
            inputBinding:setActionEventTextVisibility(eventId, false)
        end
    end
end

local function ccoRegisterGlobalPlayerActionEvents(playerInputComponent, contextName)
    if playerInputComponent ~= nil and playerInputComponent.player ~= nil and playerInputComponent.player.isOwner then
        local inputBinding = g_inputBinding
        if inputBinding ~= nil then
            CCO:registerGlobalActionEvents(playerInputComponent.player, inputBinding)
        end
    end
end

if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil and not CCO._globalGuiInputHooked then
    CCO._globalGuiInputHooked = true
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, ccoRegisterGlobalPlayerActionEvents)
end

-- Console commands ---------------------------------------------------------
function CCO:consoleReload()
    if isClientOnlyMultiplayer() then
        local ok, msg = self:requestServerSettings("consoleReload")
        print("CCO: " .. tostring(msg or (ok and "requested server settings" or "server settings request failed")))
        return
    end

    local sid = getSaveIdFromMissionInfo(g_currentMission and g_currentMission.missionInfo)
    local per = sid ~= nil and perSavePathForId(sid) or nil
    local tpl = templatePath()
    local path = tpl

    if per ~= nil then
        if not fileExists(per) then
            local templateRules, templateSettings = readConfig(tpl)
            if not next(templateRules) then templateRules = buildDefaultRules() end
            templateSettings = templateSettings or { reseedWeights = normalizeReseedWeights(nil) }
            templateRules = mergeMissingDiscoveredFruits(templateRules)
            if writeConfig(per, templateRules, templateSettings) then
                print(("CCO: created per-save config during reload: %s"):format(tostring(per)))
            end
        end
        if fileExists(per) then
            path = per
        end
    end

    local meta = inspectConfigNormalization(path)
    local rules, settings = readConfig(path)
    if not next(rules) then rules = buildDefaultRules() end
    settings = settings or { reseedWeights = normalizeReseedWeights(nil) }
    rules = mergeMissingDiscoveredFruits(rules)
    if meta ~= nil and meta.needsNormalize then
        writeConfig(path, rules, settings)
        print(("CCO: normalized config during reload: %s"):format(describeNormalization(meta)))
    end
    self._configPath = path
    self._rules = rules
    self._settings = settings
    self:applyRules(rules)
    print(("CCO: reload complete from %s"):format(tostring(path)))
end
addConsoleCommand("ccoReload", "Reload CropControlOverride config and reapply", "consoleReload", CCO)

function CCO:consoleWhichConfig()
    if isClientOnlyMultiplayer() then
        print("CCO: remote multiplayer client mode")
        print("CCO: local XML files are ignored for this session")
        print("CCO: server save : " .. tostring(self._serverSaveId or "pending"))
        print("CCO: server path : " .. tostring(self._serverConfigPath or "pending"))
        print("CCO: USING       : " .. tostring(self._configPath or "server:pending"))
        return
    end

    local sid = getSaveIdFromMissionInfo(g_currentMission and g_currentMission.missionInfo)
    local per = sid ~= nil and perSavePathForId(sid) or nil
    local tpl = templatePath()
    print("CCO: template : " .. tostring(tpl))
    print("CCO: per-save : " .. tostring(per) .. "  (exists=" .. tostring(per and fileExists(per)) .. ")")
    print("CCO: USING    : " .. tostring(self._configPath or ((per and fileExists(per)) and per or tpl)))
end
addConsoleCommand("ccoWhichConfig", "Show which CCO config file is in use", "consoleWhichConfig", CCO)

function CCO:consoleListRules(name)
    local target = name ~= nil and name ~= "" and upper(name) or nil
    local names = {}
    for nameU, _ in pairs(self._rules or {}) do table.insert(names, nameU) end
    table.sort(names)
    for _, nameU in ipairs(names) do
        if target == nil or target == nameU then
            local r = self._rules[nameU]
            print(("CCO: %s enabled=%s npcAllowed=%s npcMaxHa=%.2f resetNpcFields=%s"):format(
                nameU, tostring(r.enabled), tostring(r.npcAllowed == nil and "mapDefault" or r.npcAllowed), tonumber(r.npcMaxHa or 0), tostring(r.resetNpcFields)))
        end
    end
end
addConsoleCommand("ccoListRules", "List CCO crop rules. Usage: ccoListRules [CROP]", "consoleListRules", CCO)

function CCO:consoleListConfigured(name)
    local target = name ~= nil and name ~= "" and upper(name) or nil
    local names = {}
    for nameU, _ in pairs(self._rules or {}) do table.insert(names, nameU) end
    table.sort(names)
    local printed = 0
    print("CCO: configured crop rules")
    for _, nameU in ipairs(names) do
        if target == nil or target == nameU then
            local r = self._rules[nameU]
            local ft = getFruitByName(nameU)
            print(("CCO: %s enabled=%s npcAllowed=%s npcMaxHa=%.2f resetNpcFields=%s reseedWeight=%d discovered=%s"):format(
                nameU, tostring(r.enabled), tostring(r.npcAllowed == nil and "mapDefault" or r.npcAllowed), tonumber(r.npcMaxHa or 0), tostring(r.resetNpcFields), clampWeight(r.reseedWeight, DEFAULT_FRUIT_RESEED_WEIGHT), tostring(ft ~= nil)))
            printed = printed + 1
        end
    end
    print(("CCO: configured crop list complete. count=%d"):format(printed))
end
addConsoleCommand("ccoListConfigured", "List all configured CCO rules, including undiscovered crops. Usage: ccoListConfigured [CROP]", "consoleListConfigured", CCO)

function CCO:consoleListUndiscovered()
    local names = {}
    for nameU, _ in pairs(self._rules or {}) do
        if getFruitByName(nameU) == nil then table.insert(names, nameU) end
    end
    table.sort(names)
    if #names == 0 then
        print("CCO: no configured crops are undiscovered on this map/save")
        return
    end
    print("CCO: configured but undiscovered crop rules")
    for _, nameU in ipairs(names) do
        local r = self._rules[nameU]
        print(("CCO: %s enabled=%s npcAllowed=%s npcMaxHa=%.2f resetNpcFields=%s reseedWeight=%d"):format(
            nameU, tostring(r.enabled), tostring(r.npcAllowed == nil and "mapDefault" or r.npcAllowed), tonumber(r.npcMaxHa or 0), tostring(r.resetNpcFields), clampWeight(r.reseedWeight, DEFAULT_FRUIT_RESEED_WEIGHT)))
    end
    print(("CCO: undiscovered crop list complete. count=%d"):format(#names))
end
addConsoleCommand("ccoListUndiscovered", "List configured crops that are not loaded on this map/save", "consoleListUndiscovered", CCO)

function CCO:consoleNormalizeConfig(modeArg)
    if isClientOnlyMultiplayer() then
        print("CCO: ccoNormalizeConfig is disabled for remote multiplayer clients; local XML files are ignored in this session.")
        return
    end

    local path = self._configPath or templatePath()
    local dryRun = modeArg ~= nil and string.lower(tostring(modeArg)) == "dryrun"
    local meta = inspectConfigNormalization(path)
    local rules, settings = readConfig(path)
    if not next(rules) then rules = self._rules or buildDefaultRules() end
    settings = settings or self._settings or { reseedWeights = normalizeReseedWeights(nil) }
    rules = mergeMissingDiscoveredFruits(rules)

    if meta == nil or not meta.exists then
        print("CCO: active config does not exist; nothing to normalize")
        return
    end

    if not meta.needsNormalize then
        print(("CCO: config already normalized: %s"):format(tostring(path)))
        return
    end

    print(("CCO: config normalization %s for %s"):format(dryRun and "dry-run" or "write", tostring(path)))
    print(("CCO: reasons: %s"):format(describeNormalization(meta)))
    print(("CCO: rules to preserve/write=%d"):format((function() local n=0; for _,_ in pairs(rules or {}) do n=n+1 end; return n end)()))
    if dryRun then
        print("CCO: dry-run only; run ccoNormalizeConfig to rewrite active config")
        return
    end

    if writeConfig(path, rules, settings) then
        self._rules = rules
        self._settings = settings
        self._configPath = path
        self:applyRules(rules)
        print("CCO: config normalization complete")
    else
        print("CCO: config normalization failed")
    end
end
addConsoleCommand("ccoNormalizeConfig", "Normalize/migrate active config to v2. Usage: ccoNormalizeConfig [dryrun]", "consoleNormalizeConfig", CCO)

function CCO:_consoleSetCropLocal(name, enabledArg, npcAllowedArg, npcMaxHaArg)
    if name == nil or name == "" then
        print("CCO: usage ccoSetCrop <CROP> <enabled:true|false> [npcAllowed:true|false|mapDefault] [npcMaxHa]")
        return
    end
    local nameU = upper(name)
    local enabled = boolFromStringOrBool(enabledArg, nil)
    if enabled == nil then
        print("CCO: enabled must be true or false")
        return
    end

    local npcAllowed = nil
    if npcAllowedArg ~= nil and npcAllowedArg ~= "" then
        npcAllowed = boolFromStringOrBool(npcAllowedArg, nil)
    end
    local npcMaxHa = tonumber(npcMaxHaArg or 0) or 0

    self._rules = self._rules or buildDefaultRules()
    self._rules[nameU] = normalizeRule(nameU, {
        enabled = enabled,
        npcAllowed = npcAllowed,
        npcMaxHa = npcMaxHa,
        resetNpcFields = true,
    })
    self:applyRules(self._rules)

    if self._configPath ~= nil then
        writeConfig(self._configPath, self._rules, self._settings)
    end
    self:consoleListRules(nameU)
end

function CCO:consoleSetCrop(name, enabledArg, npcAllowedArg, npcMaxHaArg)
    if not self:canEditRules() then
        print("CCO: rules are read-only for remote multiplayer clients. Log in as server admin/master user to change them.")
        self:requestServerSettings("consoleSetCropDenied")
        return
    end
    if self:_shouldUseMultiplayerEvent() then
        local ok, msg = self:_sendMultiplayerEvent("consoleSetCrop", tostring(name or ""), tostring(enabledArg or ""), tostring(npcAllowedArg or ""), tostring(npcMaxHaArg or 0))
        if msg ~= nil then print("CCO: " .. tostring(msg)) end
        return
    end
    return self:_consoleSetCropLocal(name, enabledArg, npcAllowedArg, npcMaxHaArg)
end
addConsoleCommand("ccoSetCrop", "Set a crop rule. Usage: ccoSetCrop <CROP> <enabled> [npcAllowed] [npcMaxHa]", "consoleSetCrop", CCO)

function CCO:consoleListFlags(name)
    local function dump(ft)
        print(("CCO: %s"):format(ft.name))
        print(("  index=%s"):format(tostring(ft.index)))
        for _, key in ipairs(FRUIT_FLAG_FIELDS) do
            print(("  %s=%s"):format(key, tostring(ft[key])))
        end
    end

    if g_fruitTypeManager == nil then print("CCO: fruit manager not ready"); return end
    if name ~= nil and name ~= "" then
        local ft = getFruitByName(name)
        if ft ~= nil then dump(ft) else print("CCO: fruit not found: " .. tostring(name)) end
        return
    end
    for _, ft in ipairs(iterFruitTypesSorted()) do dump(ft) end
end
addConsoleCommand("ccoListFlags", "List fruit flags. Usage: ccoListFlags [CROP]", "consoleListFlags", CCO)

function CCO:consoleFindFruit(pattern)
    if pattern == nil or pattern == "" then print("CCO: usage ccoFindFruit <namePart>"); return end
    if g_fruitTypeManager == nil then print("CCO: fruit manager not ready"); return end
    local p = upper(pattern)
    local found = false
    for _, ft in ipairs(iterFruitTypesSorted()) do
        local n = upper(ft.name or "")
        if string.find(n, p, 1, true) then
            found = true
            print(("CCO: match '%s' (index=%s)"):format(tostring(ft.name), tostring(ft.index)))
        end
    end
    if not found then print("CCO: no fruits matching '" .. tostring(pattern) .. "'") end
end
addConsoleCommand("ccoFindFruit", "Search fruitTypes by substring. Usage: ccoFindFruit <namePart>", "consoleFindFruit", CCO)

function CCO:consoleExplain(name)
    if name == nil or name == "" then print("CCO: usage ccoExplain <CROP>"); return end
    local nameU = upper(name)
    local rule = self._rules and self._rules[nameU] or nil
    local ft = getFruitByName(nameU)
    print("CCO: " .. nameU)
    print("  discovered=" .. tostring(ft ~= nil))
    if ft ~= nil then print("  index=" .. tostring(ft.index)) end
    if rule ~= nil then
        print("  enabled=" .. tostring(rule.enabled))
        print("  npcAllowed=" .. tostring(rule.npcAllowed == nil and "mapDefault" or rule.npcAllowed))
        print("  npcMaxHa=" .. tostring(rule.npcMaxHa or 0))
        print("  resetNpcFields=" .. tostring(rule.resetNpcFields))
        if ft == nil then
            print("  note=rule exists but fruitType is not registered in this session")
        end
    else
        print("  rule=nil")
        if ft == nil then
            print("  note=fruitType is not registered and no staged rule exists; DLC/mod may be inactive or the crop name may be wrong")
            print("  hint=use ccoSetCrop " .. nameU .. " false false 0 to pre-stage a disabled rule")
        end
    end
    if ft ~= nil then
        for _, key in ipairs(FRUIT_FLAG_FIELDS) do print(("  %s=%s"):format(key, tostring(ft[key]))) end
    end
end
addConsoleCommand("ccoExplain", "Explain CCO state for a crop. Usage: ccoExplain <CROP>", "consoleExplain", CCO)

function CCO:consoleScanFields(cropName)
    self:scanFields(cropName, false)
end
addConsoleCommand("ccoScanFields", "Scan fields against CCO NPC rules. Usage: ccoScanFields [CROP]", "consoleScanFields", CCO)

function CCO:consoleScanBlocked(cropName)
    self:scanFields(cropName, true)
end
addConsoleCommand("ccoScanBlocked", "Scan only NPC fields blocked by CCO rules. Usage: ccoScanBlocked [CROP]", "consoleScanBlocked", CCO)

function CCO:consoleScanSummary(cropName)
    self:printFieldSummary(cropName)
end
addConsoleCommand("ccoScanSummary", "Summarise field crop status against CCO rules. Usage: ccoScanSummary [CROP]", "consoleScanSummary", CCO)

function CCO:consoleValidateSave()
    self:validateSave()
end
addConsoleCommand("ccoValidateSave", "Validate that no NPC fields violate CCO rules", "consoleValidateSave", CCO)


function CCO:consoleListDisabled()
    local names = {}
    for nameU, rule in pairs(self._rules or {}) do
        if rule ~= nil and rule.enabled == false then
            table.insert(names, nameU)
        end
    end
    table.sort(names)
    if #names == 0 then
        print("CCO: no crops are currently disabled by rule")
        return
    end
    print("CCO: disabled crop rules")
    for _, nameU in ipairs(names) do
        local r = self._rules[nameU]
        local ft = getFruitByName(nameU)
        print(("CCO: %s enabled=%s npcAllowed=%s npcMaxHa=%.2f resetNpcFields=%s discovered=%s"):format(
            nameU, tostring(r.enabled), tostring(r.npcAllowed == nil and "mapDefault" or r.npcAllowed), tonumber(r.npcMaxHa or 0), tostring(r.resetNpcFields), tostring(ft ~= nil)))
    end
    print(("CCO: disabled crop list complete. count=%d"):format(#names))
end
addConsoleCommand("ccoListDisabled", "List crops disabled by CCO rules", "consoleListDisabled", CCO)

function CCO:consoleListBlockedRules()
    local names = {}
    for nameU, rule in pairs(self._rules or {}) do
        if rule ~= nil and (rule.enabled == false or rule.npcAllowed == false) then
            table.insert(names, nameU)
        end
    end
    table.sort(names)
    if #names == 0 then
        print("CCO: no crops are currently NPC-disabled by rule")
        return
    end
    print("CCO: NPC-disabled crop rules")
    for _, nameU in ipairs(names) do
        local r = self._rules[nameU]
        local ft = getFruitByName(nameU)
        print(("CCO: %s enabled=%s npcAllowed=%s npcMaxHa=%.2f resetNpcFields=%s discovered=%s"):format(
            nameU, tostring(r.enabled), tostring(r.npcAllowed == nil and "mapDefault" or r.npcAllowed), tonumber(r.npcMaxHa or 0), tostring(r.resetNpcFields), tostring(ft ~= nil)))
    end
    print(("CCO: NPC-disabled rule list complete. count=%d"):format(#names))
end
addConsoleCommand("ccoListBlockedRules", "List crops disabled or blocked for NPCs by CCO rules", "consoleListBlockedRules", CCO)

function CCO:consoleListLimited()
    local names = {}
    for nameU, rule in pairs(self._rules or {}) do
        if rule ~= nil and rule.npcMaxHa ~= nil and rule.npcMaxHa > 0 then
            table.insert(names, nameU)
        end
    end
    table.sort(names)
    if #names == 0 then
        print("CCO: no crops currently have npcMaxHa limits")
        return
    end
    for _, nameU in ipairs(names) do
        local r = self._rules[nameU]
        print(("CCO: %s npcMaxHa=%.2f enabled=%s npcAllowed=%s resetNpcFields=%s"):format(
            nameU, tonumber(r.npcMaxHa or 0), tostring(r.enabled), tostring(r.npcAllowed == nil and "mapDefault" or r.npcAllowed), tostring(r.resetNpcFields)))
    end
    print(("CCO: limited crop list complete. count=%d"):format(#names))
end
addConsoleCommand("ccoListLimited", "List crops with NPC field-size limits", "consoleListLimited", CCO)


local function findFieldByFarmlandId(idArg)
    local target = tonumber(idArg)
    if target == nil then return nil end
    if g_fieldManager == nil or g_fieldManager.getFields == nil then return nil end
    for idx, field in pairs(g_fieldManager:getFields() or {}) do
        local fid = tonumber(getFieldId(field, idx))
        if fid == target then return field, idx end
    end
    return nil
end


function CCO:consoleFieldSizeProbe(fieldIdArg)
    if fieldIdArg == nil or fieldIdArg == "" then
        print("CCO: usage ccoFieldSizeProbe <FIELD_ID>")
        return
    end
    if g_fieldManager == nil or g_fieldManager.getFields == nil then
        print("CCO: field manager not ready")
        return
    end

    local wanted = tostring(fieldIdArg)
    local found = nil
    local fallbackIndex = nil

    for idx, field in pairs(g_fieldManager:getFields()) do
        if tostring(getFieldId(field, idx)) == wanted then
            found = field
            fallbackIndex = idx
            break
        end
    end

    if found == nil then
        print("CCO: field not found: " .. tostring(fieldIdArg))
        return
    end

    local ft = getFieldFruit(found)
    print(("CCO: field size probe field=%s fallbackIndex=%s"):format(tostring(getFieldId(found, fallbackIndex)), tostring(fallbackIndex)))
    print(("  calculatedFieldSizeHa=%s"):format(tostring(getFieldSizeHa(found))))
    print(("  fruit=%s"):format(ft ~= nil and tostring(ft.name) or "none"))
    print(("  field.areaHa=%s"):format(tostring(found.areaHa)))
    print(("  field.fieldAreaHa=%s"):format(tostring(found.fieldAreaHa)))
    print(("  field.fieldArea=%s"):format(tostring(found.fieldArea)))
    print(("  field.area=%s"):format(tostring(found.area)))
    print(("  field.sizeHa=%s"):format(tostring(found.sizeHa)))
    print(("  field.fieldDimensions.areaInHa=%s"):format(tostring(found.fieldDimensions ~= nil and found.fieldDimensions.areaInHa or nil)))
    print(("  farmland.id=%s"):format(tostring(found.farmland ~= nil and found.farmland.id or nil)))
    print(("  farmland.areaInHa=%s"):format(tostring(found.farmland ~= nil and found.farmland.areaInHa or nil)))
    print(("  farmland.farmId=%s"):format(tostring(found.farmland ~= nil and found.farmland.farmId or nil)))
end
addConsoleCommand("ccoFieldSizeProbe", "Show actual field-size values used by CCO. Usage: ccoFieldSizeProbe <FIELD_ID>", "consoleFieldSizeProbe", CCO)


function CCO:consoleListNpcCandidates(fieldIdArg)
    if fieldIdArg == nil or fieldIdArg == "" then
        print("CCO: usage ccoListNpcCandidates <FIELD_ID>")
        return
    end

    local field = findFieldByFarmlandId(fieldIdArg)
    if field == nil then
        print("CCO: field not found: " .. tostring(fieldIdArg))
        return
    end

    local fieldHa = getFieldSizeHa(field)
    print(("CCO: NPC crop candidates for field=%s size=%.2fha npc=%s"):format(tostring(getFieldId(field)), fieldHa, tostring(isNpcField(field))))
    local candidates = self:buildNpcCandidatesForField(field, true)
    local valid = 0
    for _, c in ipairs(candidates) do
        if c.ok then valid = valid + 1 end
        local rule = self._rules and self._rules[c.cropName] or nil
        local limitText = ""
        if rule ~= nil and rule.npcMaxHa ~= nil and rule.npcMaxHa > 0 then
            limitText = (" npcMaxHa=%.2f"):format(rule.npcMaxHa)
        end
        local seasonalText = ""
        if c.ok then
            if c.seasonalKnown == true then
                seasonalText = c.seasonalOk and " seasonal=OK" or (" seasonal=NO(" .. tostring(c.seasonReason) .. ")")
            else
                seasonalText = " seasonal=UNKNOWN(" .. tostring(c.seasonReason) .. ")"
            end
        end
        print(("CCO:   %-14s %s category=%s reason=%s%s%s"):format(c.cropName, c.ok and "OK" or "BLOCKED", tostring(c.category or "blocked"), tostring(c.reason), seasonalText, limitText))
    end
    print(("CCO: candidate list complete. valid=%d total=%d"):format(valid, #candidates))
end
addConsoleCommand("ccoListNpcCandidates", "List NPC crop candidates for a field. Usage: ccoListNpcCandidates <FIELD_ID>", "consoleListNpcCandidates", CCO)



local function describeTableKeys(obj, label, maxKeys)
    maxKeys = tonumber(maxKeys or 40) or 40
    if obj == nil then
        print(("CCO:   %s=nil"):format(tostring(label)))
        return
    end
    if type(obj) ~= "table" then
        print(("CCO:   %s=%s (%s)"):format(tostring(label), tostring(obj), type(obj)))
        return
    end

    local keys = {}
    for k, _ in pairs(obj) do
        table.insert(keys, tostring(k))
    end
    table.sort(keys)

    local shown = {}
    for i = 1, math.min(#keys, maxKeys) do
        table.insert(shown, keys[i])
    end
    print(("CCO:   %s keys[%d]=%s"):format(tostring(label), #keys, table.concat(shown, ", ")))
end

local function describeValueDeep(obj, label, depth, maxDepth, maxKeys)
    depth = tonumber(depth or 0) or 0
    maxDepth = tonumber(maxDepth or 2) or 2
    maxKeys = tonumber(maxKeys or 30) or 30

    if obj == nil then
        print(("CCO:   %s=nil"):format(tostring(label)))
        return
    end

    if type(obj) ~= "table" then
        print(("CCO:   %s=%s (%s)"):format(tostring(label), tostring(obj), type(obj)))
        return
    end

    describeTableKeys(obj, label, maxKeys)
    if depth >= maxDepth then return end

    local keys = {}
    for k, _ in pairs(obj) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    local count = 0
    for _, k in ipairs(keys) do
        count = count + 1
        if count > maxKeys then
            print(("CCO:   %s ... %d more key(s)"):format(tostring(label), #keys - maxKeys))
            break
        end
        describeValueDeep(obj[k], tostring(label) .. "." .. tostring(k), depth + 1, maxDepth, maxKeys)
    end
end

local function periodIndexBefore(period)
    if period == nil then return nil end
    local p = tonumber(period)
    if p == nil then return nil end
    p = math.floor(p) - 1
    if p < 1 then p = 12 end
    return p
end

local function periodIndexAfter(period)
    if period == nil then return nil end
    local p = tonumber(period)
    if p == nil then return nil end
    p = math.floor(p) + 1
    if p > 12 then p = 1 end
    return p
end

function CCO:consoleGrowthProbe(cropNameArg)
    local cropName = cropNameArg ~= nil and cropNameArg ~= "" and upper(cropNameArg) or nil
    print("CCO: growth/calendar diagnostic probe")

    local period = getCurrentPeriodIndex()
    print(("CCO:   currentPeriod=%s calendarYear=%s"):format(tostring(period), tostring(getCalendarYearToken ~= nil and getCalendarYearToken() or "n/a")))

    local printed = 0
    for _, ft in ipairs(iterFruitTypesSorted()) do
        if cropName == nil or upper(ft.name) == cropName then
            local name = upper(ft.name)
            print(("CCO: fruit=%s index=%s allowsSeeding=%s numFoliageStates=%s minHarvestingGrowthState=%s maxHarvestingGrowthState=%s cutState=%s witheredState=%s"):format(
                name, tostring(ft.index), tostring(ft.allowsSeeding), tostring(ft.numFoliageStates),
                tostring(ft.minHarvestingGrowthState), tostring(ft.maxHarvestingGrowthState),
                tostring(ft.cutState), tostring(ft.witheredState)))

            if type(ft.growthStateToName) == "table" then
                local stateKeys = {}
                for k in pairs(ft.growthStateToName) do table.insert(stateKeys, k) end
                table.sort(stateKeys, function(a,b) return tostring(a) < tostring(b) end)
                for _, k in ipairs(stateKeys) do
                    print(("CCO:   fruit.%s.growthStateToName[%s]=%s"):format(name, tostring(k), tostring(ft.growthStateToName[k])))
                end
            else
                print(("CCO:   fruit.%s.growthStateToName=%s"):format(name, tostring(ft.growthStateToName)))
            end

            local seasonal = ft.growthDataSeasonal
            print(("CCO:   fruit.%s.growthDataSeasonal.type=%s"):format(name, type(seasonal)))
            if type(seasonal) == "table" then
                describeTableKeys(seasonal, "fruit." .. name .. ".growthDataSeasonal", 160)
                local periods = seasonal.periods
                print(("CCO:   fruit.%s.growthDataSeasonal.periods.type=%s"):format(name, type(periods)))
                if type(periods) == "table" then
                    for periodIndex = 1, 12 do
                        describeValueDeep(periods[periodIndex], "fruit." .. name .. ".growthDataSeasonal.periods[" .. tostring(periodIndex) .. "]", 0, 5, 100)
                    end
                end
            end

            describeTableKeys(ft, "fruit." .. name, 140)
            if ft.data ~= nil then
                describeValueDeep(ft.data, "fruit." .. name .. ".data", 0, 4, 100)
            end
            printed = printed + 1
        end
    end

    print(("CCO: growth/calendar diagnostic probe complete. fruitsPrinted=%d"):format(printed))
end
addConsoleCommand("ccoGrowthProbe", "Probe growth/calendar runtime objects. Usage: ccoGrowthProbe [CROP]", "consoleGrowthProbe", CCO)


function CCO:consoleSeasonProbe(cropNameArg)
    local cropName = cropNameArg ~= nil and cropNameArg ~= "" and upper(cropNameArg) or nil
    local period = getCurrentPeriodIndex()
    print(("CCO: season probe currentPeriod=%s"):format(tostring(period)))

    local printed = 0
    for _, ft in ipairs(iterFruitTypesSorted()) do
        if cropName == nil or upper(ft.name) == cropName then
            local ok, reason = getSeasonalSowingStatus(ft)
            print(("CCO:   %-14s seasonalSowing=%s reason=%s allowsSeeding=%s"):format(
                upper(ft.name),
                tostring(ok),
                tostring(reason),
                tostring(ft.allowsSeeding)
            ))

            for _, key in ipairs(SEEDING_PERIOD_FIELDS) do
                if ft[key] ~= nil then
                    print(("CCO:      %s=%s"):format(key, tostring(ft[key])))
                end
                if ft.data ~= nil and ft.data[key] ~= nil then
                    print(("CCO:      data.%s=%s"):format(key, tostring(ft.data[key])))
                end
            end

            printed = printed + 1
        end
    end
    print(("CCO: season probe complete. printed=%d"):format(printed))
end
addConsoleCommand("ccoSeasonProbe", "Probe exposed seasonal sowing data. Usage: ccoSeasonProbe [CROP]", "consoleSeasonProbe", CCO)


local function parseResetArgs(first, second)
    local cropName = first
    local mode = second

    if cropName ~= nil and cropName ~= "" then
        local cropLower = string.lower(tostring(cropName))
        if cropLower == "all" or cropLower == "*" then
            cropName = nil
        elseif cropLower == "dryrun" or cropLower == "dry-run" or cropLower == "preview" then
            mode = cropName
            cropName = nil
        end
    end

    local dryRun = false
    if mode ~= nil and mode ~= "" then
        local modeLower = string.lower(tostring(mode))
        dryRun = modeLower == "dryrun" or modeLower == "dry-run" or modeLower == "preview"
    end

    return cropName, dryRun
end



function CCO:getBlockedFieldRows()
    local rows = {}

    if g_fieldManager ~= nil and g_fieldManager.getFields ~= nil then
        for i, field in pairs(g_fieldManager:getFields() or {}) do
            local ft = getFieldFruit(field)
            if ft ~= nil then
                local cropName = upper(ft.name)
                local blocked, reason = self:shouldResetNpcField(field, cropName)
                if blocked then
                    table.insert(rows, {
                        field = field,
                        fallbackIndex = i,
                        fieldId = tostring(getFieldId(field, i)),
                        cropName = cropName,
                        sizeHa = getFieldSizeHa(field),
                        reason = tostring(reason or "blocked"),
                    })
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        local an = tonumber(a.fieldId)
        local bn = tonumber(b.fieldId)
        if an ~= nil and bn ~= nil then return an < bn end
        return tostring(a.fieldId) < tostring(b.fieldId)
    end)

    return rows
end

function CCO:getBlockedCropList()
    local crops = {}
    local seen = {}

    for _, row in ipairs(self:getBlockedFieldRows()) do
        if row.cropName ~= nil and not seen[row.cropName] then
            seen[row.cropName] = true
            table.insert(crops, row.cropName)
        end
    end

    table.sort(crops)
    return crops
end

function CCO:getBlockedResetScopeList()
    local scopes = {
        { mode = "all", label = "ALL" }
    }

    local crops = self:getBlockedCropList()
    for _, crop in ipairs(crops) do
        table.insert(scopes, {
            mode = "crop",
            crop = crop,
            label = "CROP: " .. tostring(crop),
        })
    end

    for _, row in ipairs(self:getBlockedFieldRows()) do
        table.insert(scopes, {
            mode = "field",
            crop = row.cropName,
            fieldId = row.fieldId,
            label = ("FIELD: %s %s"):format(tostring(row.fieldId), tostring(row.cropName)),
        })
    end

    return scopes
end


function CCO:normaliseResetMode(mode)
    local m = mode ~= nil and string.lower(tostring(mode)) or "cultivated"
    if m == "reseed" or m == "reseedseasonal" or m == "reseed_seasonal" or m == "seasonal" then
        return "reseedSeasonal", "RESEED SEASONAL"
    end
    return "cultivated", "CULTIVATED"
end

function CCO:getDryRunResetActionForField(field, cropName, mode)
    local modeKey, modeLabel = self:normaliseResetMode(mode)
    if modeKey == "reseedSeasonal" then
        local candidateCrop, candidateReason = self:getReseedCandidateTextForField(field, cropName)
        local reasonText = tostring(candidateReason or "")
        local hasSeasonalCandidate = candidateCrop ~= nil
            and candidateCrop ~= "NONE"
            and reasonText:find("replacement selected (seasonal", 1, true) ~= nil

        if hasSeasonalCandidate then
            return "RESEED_SEASONAL", tostring(candidateCrop), reasonText
        end

        if reasonText:find("weighted leave cultivated", 1, true) ~= nil then
            return "CULTIVATED_VARIETY", tostring(candidateCrop or "NONE"), reasonText
        end

        return "CULTIVATED_FALLBACK", tostring(candidateCrop or "NONE"), tostring(candidateReason or "no seasonal candidate")
    end
    return "CULTIVATED", "NONE", "reset mode cultivated"
end


function CCO:resetBlockedFieldById(fieldId, dryRun, resetMode)
    local wanted = tostring(fieldId or "")
    if wanted == "" then return 0, 0 end

    if g_currentMission == nil or not g_currentMission:getIsServer() then
        warn("field reset skipped: must run on server/host")
        return 0, 0
    end
    if g_fieldManager == nil or g_fieldManager.getFields == nil then
        warn("field manager not ready")
        return 0, 0
    end

    for idx, field in pairs(g_fieldManager:getFields() or {}) do
        if tostring(getFieldId(field, idx)) == wanted then
            local ft = getFieldFruit(field)
            if ft ~= nil then
                local cropName = upper(ft.name)
                local reset, reason = self:shouldResetNpcField(field, cropName)
                if reset then
                    if dryRun == true then
                        local action, candidateCrop, candidateReason = self:getDryRunResetActionForField(field, cropName, resetMode)
                        print(("CCO: dry-run would reset field=%s crop=%s size=%.2fha reason=%s resetMode=%s action=%s reseedCandidate=%s candidateReason=%s"):format(
                            tostring(getFieldId(field, idx)), cropName, getFieldSizeHa(field), tostring(reason), select(2, self:normaliseResetMode(resetMode)), tostring(action), tostring(candidateCrop), tostring(candidateReason)))
                        return 1, 0
                    else
                        local ok = self:applyResetActionToField(field, cropName, reason, resetMode)
                        if ok then
                            if g_missionManager ~= nil then
                                info("triggering mission generation after field reset")
                                if g_missionManager.generationTimer ~= nil then g_missionManager.generationTimer = 0 end
                                if g_missionManager.startMissionGeneration ~= nil then g_missionManager:startMissionGeneration() end
                            end
                            return 1, 0
                        else
                            return 0, 1
                        end
                    end
                end
            end
            return 0, 0
        end
    end

    return 0, 1
end

function CCO:normaliseGuiResetScope(scope)
    if type(scope) == "table" then
        return scope
    end

    if scope ~= nil and tostring(scope) ~= "" then
        return { mode = "crop", crop = upper(scope), label = upper(scope) }
    end

    return { mode = "all", label = "ALL" }
end


function CCO:getBlockedCountForGuiScope(scope)
    local s = self:normaliseGuiResetScope(scope)
    local count = 0

    for _, row in ipairs(self:getBlockedFieldRows()) do
        if s.mode == "all" then
            count = count + 1
        elseif s.mode == "crop" and row.cropName == upper(s.crop) then
            count = count + 1
        elseif s.mode == "field" and tostring(row.fieldId) == tostring(s.fieldId) then
            count = count + 1
        end
    end

    return count
end

function CCO:resetBlockedFieldsDryRunFromGui(scope, resetMode)
    local s = self:normaliseGuiResetScope(scope)
    local wouldQueue, skipped = 0, 0

    if s.mode == "field" then
        wouldQueue, skipped = self:resetBlockedFieldById(s.fieldId, true, resetMode)
    else
        local target = s.mode == "crop" and upper(s.crop) or nil
        wouldQueue, skipped = self:resetNpcFields(target, true, resetMode)
    end

    local scopeText = tostring(s.label or s.crop or s.fieldId or "ALL")
    local _, resetModeLabel = self:normaliseResetMode(resetMode)
    local msg = ("Dry-run complete for scope=%s resetMode=%s. %d blocked NPC field(s) would be processed. skipped=%d. No save-state changes were made."):format(
        scopeText,
        resetModeLabel,
        tonumber(wouldQueue or 0) or 0,
        tonumber(skipped or 0) or 0
    )

    if tonumber(wouldQueue or 0) == 0 then
        msg = ("Dry-run complete for scope=%s resetMode=%s. No blocked NPC fields were detected. No save-state changes were made."):format(scopeText, resetModeLabel)
    end

    print("CCO GUI RESET DRY-RUN: " .. msg)
    self._guiNotice = msg
    return msg, tonumber(wouldQueue or 0) or 0, tonumber(skipped or 0) or 0
end

function CCO:_resetBlockedFieldsFromGuiLocal(scope, resetMode)
    local s = self:normaliseGuiResetScope(scope)
    local queued, skipped = 0, 0

    if s.mode == "field" then
        queued, skipped = self:resetBlockedFieldById(s.fieldId, false, resetMode)
    else
        local target = s.mode == "crop" and upper(s.crop) or nil
        queued, skipped = self:resetNpcFields(target, false, resetMode)
    end

    local scopeText = tostring(s.label or s.crop or s.fieldId or "ALL")
    local _, resetModeLabel = self:normaliseResetMode(resetMode)
    if tonumber(queued or 0) <= 0 and tonumber(skipped or 0) <= 0 then
        local msg = ("Reset skipped for scope=%s resetMode=%s. No blocked NPC fields were detected."):format(scopeText, resetModeLabel)
        print("CCO GUI RESET BLOCKED: " .. msg)
        self._guiNotice = msg
        return msg, tonumber(queued or 0) or 0, tonumber(skipped or 0) or 0
    end

    local msg = ("Reset complete for scope=%s resetMode=%s. queued=%d skipped=%d. Reopen VALIDATION or run RESET BLOCKED DRY-RUN again after refresh."):format(
        scopeText,
        resetModeLabel,
        tonumber(queued or 0) or 0,
        tonumber(skipped or 0) or 0
    )

    print("CCO GUI RESET BLOCKED: " .. msg)
    self._guiNotice = msg
    return msg, tonumber(queued or 0) or 0, tonumber(skipped or 0) or 0
end



function CCO:resetBlockedFieldsFromGui(scope, resetMode)
    if not self:canEditRules() then
        local msg = "CCO reset is read-only for remote multiplayer clients. Log in as server admin/master user to change fields."
        self._guiNotice = msg
        return msg, 0, 0
    end
    if self:_shouldUseMultiplayerEvent() then
        local s = self:normaliseGuiResetScope(scope)
        local scopeArg = "all:"
        if s.mode == "crop" then
            scopeArg = "crop:" .. tostring(upper(s.crop or ""))
        elseif s.mode == "field" then
            scopeArg = "field:" .. tostring(s.fieldId or "")
        end
        return self:_sendMultiplayerEvent("resetBlocked", scopeArg, tostring(resetMode or "cultivated"))
    end
    return self:_resetBlockedFieldsFromGuiLocal(scope, resetMode)
end

function CCO:consoleResetNpcFields(cropNameArg, modeArg)
    local cropName, dryRun = parseResetArgs(cropNameArg, modeArg)
    if isClientOnlyMultiplayer() and dryRun ~= true then
        print("CCO: reset is read-only for remote multiplayer clients. Run dryrun for viewing only, or use the server/host.")
        return
    end
    self:resetNpcFields(cropName, dryRun)
end
addConsoleCommand("ccoResetNpcFields", "Reset offending NPC fields to cultivated state. Usage: ccoResetNpcFields [CROP|all] [dryrun]", "consoleResetNpcFields", CCO)

function CCO:consoleResetBlocked(modeArg)
    local _, dryRun = parseResetArgs(modeArg, nil)
    if isClientOnlyMultiplayer() and dryRun ~= true then
        print("CCO: reset is read-only for remote multiplayer clients. Run ccoResetBlocked dryrun for viewing only, or use the server/host.")
        return
    end
    self:resetNpcFields(nil, dryRun)
end
addConsoleCommand("ccoResetBlocked", "Reset all currently blocked NPC fields. Usage: ccoResetBlocked [dryrun]", "consoleResetBlocked", CCO)


-- Experimental 2.1 alpha: rebuild every NPC-owned field using enabled crops,
-- per-crop reseed weights, and a calendar-derived plausible growth state.
local CCO_REGEN_STATE_KEYS = {
    "growthState", "targetGrowthState", "newGrowthState", "nextGrowthState",
    "foliageState", "targetState", "newState", "state"
}

local function getCalendarYearToken()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then return 0 end
    return tonumber(env.currentYear or env.year or env.currentSeason or 0) or 0
end

local function getFruitMaximumPlausibleState(ft)
    if ft == nil then return nil end
    local maximum = tonumber(ft.maxHarvestingGrowthState)
    if maximum == nil or maximum < 1 then
        maximum = tonumber(ft.minHarvestingGrowthState)
    end
    if maximum == nil or maximum < 1 then
        local count = tonumber(ft.numFoliageStates)
        if count == nil and type(ft.growthStateToName) == "table" then
            count = #ft.growthStateToName
        end
        if count ~= nil and count > 1 then maximum = count - 1 end
    end
    if maximum ~= nil then return math.max(1, math.floor(maximum)) end
    return nil
end

local function getFruitHarvestStateRange(ft)
    if ft == nil then return nil, nil end
    local minimum = tonumber(ft.minHarvestingGrowthState)
    local maximum = tonumber(ft.maxHarvestingGrowthState)
    if minimum ~= nil then minimum = math.max(1, math.floor(minimum)) end
    if maximum ~= nil then maximum = math.max(1, math.floor(maximum)) end
    if minimum ~= nil and maximum == nil then maximum = minimum end
    if maximum ~= nil and minimum == nil then minimum = maximum end
    if minimum ~= nil and maximum ~= nil and maximum < minimum then maximum = minimum end
    return minimum, maximum
end

local CCO_REGEN_PLANTING_KEYS = { "plantingAllowed", "sowingAllowed", "seedingAllowed" }
local CCO_REGEN_HARVEST_KEYS = { "isHarvestable", "harvestingAllowed", "harvestAllowed", "harvestable", "isHarvestPeriod" }

local function getSeasonalBoolean(entry, keys)
    if type(entry) ~= "table" then return nil, nil end
    for _, key in ipairs(keys) do
        if entry[key] ~= nil then return entry[key] == true, key end
    end
    return nil, nil
end

local function isSeasonalPeriodAllowed(entry, keys)
    local value, source = getSeasonalBoolean(entry, keys)
    return value == true, source
end

local function findExplicitSeasonalGrowthState(value, maximum, depth, visited)
    if type(value) ~= "table" then return nil, nil end
    depth = depth or 0
    if depth > 3 then return nil, nil end
    visited = visited or {}
    if visited[value] then return nil, nil end
    visited[value] = true

    for _, key in ipairs(CCO_REGEN_STATE_KEYS) do
        local candidate = tonumber(value[key])
        if candidate ~= nil then
            candidate = math.floor(candidate)
            if candidate >= 1 and (maximum == nil or candidate <= maximum) then
                return candidate, key
            end
        end
    end

    for key, child in pairs(value) do
        if type(child) == "table" then
            local state, source = findExplicitSeasonalGrowthState(child, maximum, depth + 1, visited)
            if state ~= nil then return state, tostring(key) .. "." .. tostring(source) end
        end
    end
    return nil, nil
end

local function findNearestSeasonalOffset(periods, period, keys, direction)
    if type(periods) ~= "table" or period == nil then return nil, nil end
    for offset = 0, 11 do
        local testPeriod = period
        for _ = 1, offset do
            if direction < 0 then testPeriod = periodIndexBefore(testPeriod) else testPeriod = periodIndexAfter(testPeriod) end
        end
        local allowed, source = isSeasonalPeriodAllowed(periods[testPeriod], keys)
        if allowed then return offset, testPeriod, source end
    end
    return nil, nil, nil
end

local function getSeasonalGrowthMapping(entry)
    if type(entry) ~= "table" or type(entry.growthMapping) ~= "table" then return nil end
    return entry.growthMapping
end

local function applySeasonalGrowthMapping(periods, state, period)
    local entry = type(periods) == "table" and periods[period] or nil
    local mapping = getSeasonalGrowthMapping(entry)
    if mapping == nil then return nil, "period " .. tostring(period) .. " has no growthMapping" end
    local mapped = tonumber(mapping[state])
    if mapped == nil then return nil, "period " .. tostring(period) .. " has no mapping for state " .. tostring(state) end
    mapped = math.floor(mapped)
    if mapped < 1 then return nil, "period " .. tostring(period) .. " mapped to invalid state " .. tostring(mapped) end
    return mapped, nil
end

local function replaySeasonalGrowthFromPlanting(periods, plantingPeriod, currentPeriod, maximum, harvestMin, harvestMax)
    local state = 1
    local period = plantingPeriod
    local steps = 0
    local passedHarvestReady = false

    -- The planting period contains the transition that establishes a newly
    -- seeded crop (for example invisible -> greenSmall). Skipping this first
    -- mapping leaves year-crossing crops stuck in state 1 for their entire
    -- replay. Apply the planting period itself before advancing through later
    -- periods. When planting happens in the current period, retain state 1 so
    -- the result represents a newly seeded crop before the period transition.
    if plantingPeriod ~= currentPeriod then
        local mapped, reason = applySeasonalGrowthMapping(periods, state, plantingPeriod)
        if mapped == nil then return nil, steps, reason, passedHarvestReady end
        state = mapped
        steps = steps + 1
        if maximum ~= nil and state > maximum then
            return nil, steps, "mapped state exceeds plausible maximum " .. tostring(maximum), passedHarvestReady
        end

        if harvestMin ~= nil and harvestMax ~= nil then
            local plantingEntry = periods[plantingPeriod]
            local harvestable = isSeasonalPeriodAllowed(plantingEntry, CCO_REGEN_HARVEST_KEYS)
            if harvestable and state >= harvestMin and state <= harvestMax then
                passedHarvestReady = true
            end
        end
    end

    while period ~= currentPeriod and steps < 12 do
        period = periodIndexAfter(period)
        local mapped, reason = applySeasonalGrowthMapping(periods, state, period)
        if mapped == nil then return nil, steps, reason, passedHarvestReady end
        state = mapped
        steps = steps + 1
        if maximum ~= nil and state > maximum then
            return nil, steps, "mapped state exceeds plausible maximum " .. tostring(maximum), passedHarvestReady
        end

        -- A crop that was already harvest-ready in an earlier period has
        -- completed the useful standing lifecycle for regeneration purposes.
        -- Do not allow later mappings to wrap it back to a young state.
        if period ~= currentPeriod and harvestMin ~= nil and harvestMax ~= nil then
            local entry = periods[period]
            local harvestable = isSeasonalPeriodAllowed(entry, CCO_REGEN_HARVEST_KEYS)
            if harvestable and state >= harvestMin and state <= harvestMax then
                passedHarvestReady = true
            end
        end
    end
    if period ~= currentPeriod then return nil, steps, "calendar replay did not reach current period", passedHarvestReady end
    return state, steps, nil, passedHarvestReady
end

local function isRejectedMappedState(ft, state, currentHarvestable)
    if state == nil then return true, "missing state" end
    local withered = tonumber(ft ~= nil and ft.witheredState or nil)
    if withered ~= nil and state == math.floor(withered) then return true, "withered state" end
    local harvestMin, harvestMax = getFruitHarvestStateRange(ft)
    if harvestMin ~= nil and harvestMax ~= nil and state >= harvestMin and state <= harvestMax and currentHarvestable ~= true then
        return true, "harvest state outside current harvest period"
    end
    return false, nil
end

function CCO:resolveRegenerationGrowthState(ft)
    if ft == nil then return nil, "invalid fruit", false end
    local cropName = upper(ft.name or "")
    local maximum = getFruitMaximumPlausibleState(ft)
    local harvestMin, harvestMax = getFruitHarvestStateRange(ft)
    local period = getCurrentPeriodIndex()
    if period == nil then return nil, "current seasonal period unavailable", false end

    local periods = ft.growthDataSeasonal ~= nil and ft.growthDataSeasonal.periods or nil
    if type(periods) ~= "table" then
        return nil, "seasonal growth periods unavailable", false
    end

    local currentEntry = periods[period]
    local currentHarvestable, harvestSource = isSeasonalPeriodAllowed(currentEntry, CCO_REGEN_HARVEST_KEYS)

    -- Permanent/regrowing crops do not have one unambiguous planting origin.
    -- Use their real harvesting range when the current period is harvestable,
    -- otherwise use firstRegrowthState and advance it through the current
    -- period's authoritative mapping when available.
    if CCO_LIFECYCLE_RESEED_CROPS[cropName] == true or ft.regrows == true then
        if currentHarvestable and harvestMin ~= nil then
            return harvestMin, ("authoritative lifecycle harvest state via %s; harvestRange=%s-%s"):format(
                tostring(harvestSource), tostring(harvestMin), tostring(harvestMax)), true
        end
        local state = tonumber(ft.firstRegrowthState) or tonumber(ft.cutState) or 1
        state = math.max(1, math.floor(state))
        local mapped = applySeasonalGrowthMapping(periods, state, period)
        if mapped ~= nil then state = mapped end
        local rejected, reason = isRejectedMappedState(ft, state, currentHarvestable)
        if not rejected then
            return state, ("authoritative lifecycle state via growthMapping; currentHarvestable=%s"):format(tostring(currentHarvestable)), true
        end
        return nil, "lifecycle mapping rejected: " .. tostring(reason), false
    end

    local outcomes = {}
    local replayedOrigins = 0
    local rejectedOrigins = 0
    local rejectionReasons = {}
    for plantingPeriod = 1, 12 do
        local plantingAllowed = isSeasonalPeriodAllowed(periods[plantingPeriod], CCO_REGEN_PLANTING_KEYS)
        if plantingAllowed then
            replayedOrigins = replayedOrigins + 1
            local state, steps, replayReason, passedHarvestReady = replaySeasonalGrowthFromPlanting(
                periods, plantingPeriod, period, maximum, harvestMin, harvestMax)
            if state ~= nil then
                local rejected, rejectReason = isRejectedMappedState(ft, state, currentHarvestable)
                local inHarvestRange = harvestMin ~= nil and harvestMax ~= nil and state >= harvestMin and state <= harvestMax

                -- During an active harvest period, a plausible standing crop
                -- must actually be in its authoritative harvesting range.
                if not rejected and currentHarvestable == true and harvestMin ~= nil and harvestMax ~= nil and not inHarvestRange then
                    rejected = true
                    rejectReason = "current harvest period but mapped state is outside harvest range"
                end

                -- A multi-period harvest window may legitimately keep a
                -- crop harvest-ready across more than one seasonal period.
                -- Reject an origin only when it previously reached harvest
                -- readiness but no longer ends inside the current harvest
                -- range.
                if not rejected and passedHarvestReady == true and not inHarvestRange then
                    rejected = true
                    rejectReason = "planting origin already passed a harvest-ready period"
                end

                -- Catch long year-crossing paths that have wrapped back to a
                -- newly planted state without the current period being a valid
                -- planting period for the crop.
                if not rejected and steps >= 8 and state <= 2 then
                    local plantingNow = isSeasonalPeriodAllowed(currentEntry, CCO_REGEN_PLANTING_KEYS)
                    if not plantingNow then
                        rejected = true
                        rejectReason = "long lifecycle wrapped to early growth state"
                    end
                end

                if not rejected then
                    table.insert(outcomes, {
                        state = state,
                        plantingPeriod = plantingPeriod,
                        steps = steps,
                        harvestReady = currentHarvestable == true and inHarvestRange == true,
                    })
                else
                    rejectedOrigins = rejectedOrigins + 1
                    rejectionReasons[tostring(rejectReason or "rejected")] = (rejectionReasons[tostring(rejectReason or "rejected")] or 0) + 1
                end
            else
                rejectedOrigins = rejectedOrigins + 1
                rejectionReasons[tostring(replayReason or "replay failed")] = (rejectionReasons[tostring(replayReason or "replay failed")] or 0) + 1
            end
        end
    end

    local function summarizeRejections()
        local parts = {}
        for reason, count in pairs(rejectionReasons) do
            table.insert(parts, tostring(reason) .. "=" .. tostring(count))
        end
        table.sort(parts)
        return #parts > 0 and table.concat(parts, "|") or "none"
    end

    if #outcomes == 0 then
        -- Some map growth XMLs expose an authoritative harvest window and
        -- harvesting-state range even when replay from every planting origin
        -- has already rolled past, reset, or otherwise cannot reproduce the
        -- standing map-initialisation state. In that narrow case, initialise
        -- the crop directly at its first authoritative harvest-ready state.
        if currentHarvestable == true
            and harvestMin ~= nil
            and harvestMax ~= nil
            and harvestMin >= 1
            and harvestMin <= harvestMax
            and ft.useForFieldMissions ~= false then
            return harvestMin, ("authoritative harvest-window fallback; source=%s harvestRange=%s-%s naturalOrigins=0 replayedOrigins=%d rejectedOrigins=%d rejectionReasons=%s fallbackUsed=true"):format(
                tostring(harvestSource), tostring(harvestMin), tostring(harvestMax), replayedOrigins, rejectedOrigins, summarizeRejections()), true
        end

        return nil, ("no authoritative mapped outcome for current period; harvestable=%s harvestRange=%s-%s"):format(
            tostring(currentHarvestable), tostring(harvestMin), tostring(harvestMax)), false
    end

    table.sort(outcomes, function(a, b)
        if a.harvestReady ~= b.harvestReady then return a.harvestReady == true end
        if a.state ~= b.state then return a.state > b.state end
        if a.steps ~= b.steps then return a.steps > b.steps end
        return a.plantingPeriod < b.plantingPeriod
    end)
    local selected = outcomes[1]
    return selected.state, ("authoritative seasonal growthMapping replay; plantedPeriod=%d steps=%d currentHarvestable=%s harvestReady=%s harvestRange=%s-%s naturalOrigins=%d replayedOrigins=%d rejectedOrigins=%d fallbackUsed=false"):format(
        selected.plantingPeriod, selected.steps, tostring(currentHarvestable), tostring(selected.harvestReady),
        tostring(harvestMin), tostring(harvestMax), #outcomes, replayedOrigins, rejectedOrigins), true
end

local function deterministicRegenerationValue(fieldId, period, year, totalWeight)
    if totalWeight == nil or totalWeight <= 0 then return nil end

    -- Build a deterministic hash from the complete field/calendar key rather
    -- than using fieldId as a near-linear arithmetic seed. The two rolling
    -- passes and final LCG rounds deliberately avalanche adjacent field IDs so
    -- neighbouring fields do not walk through adjacent weighted-pool slots.
    local key = tostring(math.floor(tonumber(fieldId) or 1)) .. ":"
        .. tostring(math.floor(tonumber(period) or 0)) .. ":"
        .. tostring(math.floor(tonumber(year) or 0))
    local modulus = 2147483647
    local hash = 104729
    for i = 1, #key do
        hash = (hash * 131 + string.byte(key, i) + i * 17) % modulus
    end
    for i = #key, 1, -1 do
        hash = (hash * 137 + string.byte(key, i) + i * 31) % modulus
    end
    hash = (hash * 48271 + 1) % modulus
    hash = (hash * 69621 + 17) % modulus
    return (hash % totalWeight) + 1
end

function CCO:buildRegenerationCandidatesForField(field)
    local candidates = {}
    local totalWeight = 0
    if field == nil then return candidates, totalWeight end
    local fieldHa = getFieldSizeHa(field)

    for _, ft in ipairs(iterFruitTypesSorted()) do
        local cropName = upper(ft.name)
        local flagOk = isFruitUsableForNpcCandidate(ft)
        local policyOk = self:isNpcCropAllowedForField(fieldHa, cropName)
        local rule = self._rules ~= nil and self._rules[cropName] or nil
        local weight = clampWeight(rule ~= nil and rule.reseedWeight or nil, DEFAULT_FRUIT_RESEED_WEIGHT)
        if flagOk == true and policyOk == true and weight > 0 then
            local state, stateReason, stateAuthoritative = self:resolveRegenerationGrowthState(ft)
            if state ~= nil then
                totalWeight = totalWeight + weight
                table.insert(candidates, {
                    action = "crop", fruit = ft, cropName = cropName, growthState = state,
                    weight = weight, cumulativeWeight = totalWeight, reason = stateReason, authoritative = stateAuthoritative == true,
                })
            end
        end
    end

    local leaveWeight = self:getReseedWeights().leaveCultivated
    if leaveWeight > 0 then
        totalWeight = totalWeight + leaveWeight
        table.insert(candidates, {
            action = "cultivated", cropName = "NONE", growthState = 0,
            weight = leaveWeight, cumulativeWeight = totalWeight,
            reason = "authoritative weighted leave cultivated", authoritative = true,
        })
    end
    return candidates, totalWeight
end

function CCO:selectRegenerationActionForField(field, fallbackIndex)
    local candidates, totalWeight = self:buildRegenerationCandidatesForField(field)
    if totalWeight <= 0 then return nil, "no weighted calendar-valid candidates" end
    local fieldId = getFieldId(field, fallbackIndex)
    local pick = deterministicRegenerationValue(fieldId, getCurrentPeriodIndex(), getCalendarYearToken(), totalWeight)
    for _, candidate in ipairs(candidates) do
        if pick <= candidate.cumulativeWeight then return candidate, "deterministic weighted pick=" .. tostring(pick) end
    end
    return nil, "weighted selection failed"
end

function CCO:buildNpcMapRegenerationPlan()
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return nil, "must run on server/host"
    end
    if g_fieldManager == nil or g_fieldManager.getFields == nil then
        return nil, "field manager not ready"
    end

    local plan = {
        period = getCurrentPeriodIndex(), year = getCalendarYearToken(), actions = {},
        distribution = {}, excluded = 0, npcFields = 0, unverified = 0,
    }
    for idx, field in pairs(g_fieldManager:getFields() or {}) do
        if field ~= nil and isNpcField(field) then
            plan.npcFields = plan.npcFields + 1
            local polygon = field.getDensityMapPolygon ~= nil and field:getDensityMapPolygon() or nil
            if polygon == nil then
                plan.excluded = plan.excluded + 1
            else
                local candidate, pickReason = self:selectRegenerationActionForField(field, idx)
                if candidate ~= nil then
                    local action = {
                        field = field, fieldId = getFieldId(field, idx), fieldHa = getFieldSizeHa(field),
                        action = candidate.action, fruit = candidate.fruit, cropName = candidate.cropName,
                        growthState = candidate.growthState, reason = candidate.reason,
                        pickReason = pickReason, authoritative = candidate.authoritative == true,
                    }
                    table.insert(plan.actions, action)
                    plan.distribution[action.cropName] = (plan.distribution[action.cropName] or 0) + 1
                    if action.authoritative ~= true then plan.unverified = plan.unverified + 1 end
                else
                    plan.excluded = plan.excluded + 1
                    print(("CCO: regeneration excludes field=%s size=%.2fha reason=%s"):format(
                        tostring(getFieldId(field, idx)), getFieldSizeHa(field), tostring(pickReason)))
                end
            end
        end
    end
    return plan, "ok"
end

function CCO:printNpcMapRegenerationPlan(plan)
    if plan == nil then return end
    print(("CCO: NPC map regeneration dry-run period=%s year=%s npcFields=%d planned=%d excluded=%d"):format(
        tostring(plan.period), tostring(plan.year), tonumber(plan.npcFields or 0), #plan.actions, tonumber(plan.excluded or 0)))
    print(("CCO: regeneration verification authoritative=%d unverified=%d confirmAllowed=%s"):format(
        #plan.actions - tonumber(plan.unverified or 0), tonumber(plan.unverified or 0), tostring(tonumber(plan.unverified or 0) == 0)))
    table.sort(plan.actions, function(a, b) return tonumber(a.fieldId or 0) < tonumber(b.fieldId or 0) end)
    for _, action in ipairs(plan.actions) do
        print(("CCO: dry-run regenerate field=%s size=%.2fha action=%s crop=%s growthState=%s stateReason=%s selection=%s"):format(
            tostring(action.fieldId), tonumber(action.fieldHa or 0), string.upper(tostring(action.action)),
            tostring(action.cropName), tostring(action.growthState), tostring(action.reason), tostring(action.pickReason)) ..
            " authoritative=" .. tostring(action.authoritative == true))
    end
    local names = {}
    for name in pairs(plan.distribution or {}) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        print(("CCO: regeneration distribution %s=%d"):format(tostring(name), tonumber(plan.distribution[name] or 0)))
    end
    if tonumber(plan.unverified or 0) > 0 then
        print("CCO: dry-run made no save-state changes. CONFIRM IS BLOCKED because one or more selected crop states are unverified. Run ccoGrowthProbe CROP and upload the diagnostic output.")
    else
        print("CCO: dry-run made no save-state changes. All selected states are authoritative; run ccoRegenerateNpcFields confirm to apply.")
    end
end

function CCO:getActiveContractCount()
    if g_missionManager == nil then return 0 end
    local count = 0
    for _, mission in ipairs(g_missionManager:getMissions() or {}) do
        local wasStarted = false
        if mission.getWasStarted ~= nil then
            local ok, value = pcall(mission.getWasStarted, mission)
            wasStarted = ok and value == true
        end
        if wasStarted or mission.farmId ~= nil or mission.activeMissionId ~= nil then
            count = count + 1
        end
    end
    return count
end

function CCO:purgeAvailableContractsForRegeneration()
    if g_missionManager == nil then return 0, "mission manager unavailable" end
    if self:getActiveContractCount() > 0 then
        return 0, "one or more accepted/active contracts exist"
    end

    -- Stop automatic generation while field tasks are being applied.
    g_missionManager.missionGenerationInProgress = false
    if g_missionManager.generationTimer ~= nil then
        g_missionManager.generationTimer = 2147483647
    end

    local missions = {}
    for _, mission in ipairs(g_missionManager:getMissions() or {}) do
        table.insert(missions, mission)
    end

    local removed = 0
    for _, mission in ipairs(missions) do
        local ok, err = pcall(function() mission:delete() end)
        if ok then
            removed = removed + 1
        else
            warn("failed deleting stale available contract: " .. tostring(err))
        end
    end
    return removed, "ok"
end

function CCO:getMissionCountForRegeneration()
    if g_missionManager == nil then return 0 end
    return #(g_missionManager:getMissions() or {})
end

function CCO:refreshRegeneratedFieldStates(state)
    local refreshed, failed = 0, 0
    for _, field in ipairs(state.fields or {}) do
        local ok, err = pcall(function()
            if field ~= nil and field.getFieldState ~= nil and field.getIndicatorPosition ~= nil then
                local fieldState = field:getFieldState()
                local posX, posZ = field:getIndicatorPosition()
                if fieldState ~= nil and fieldState.update ~= nil and posX ~= nil and posZ ~= nil then
                    fieldState:update(posX, posZ)
                    refreshed = refreshed + 1
                    return
                end
            end
            failed = failed + 1
        end)
        if not ok then
            failed = failed + 1
            warn("failed refreshing regenerated field state: " .. tostring(err))
        end
    end
    info(("refreshed regenerated field-state caches refreshed=%d failed=%d"):format(refreshed, failed))
    return refreshed, failed
end

function CCO:startFreshMissionGenerationAfterRegeneration()
    if g_missionManager == nil or g_missionManager.startMissionGeneration == nil then return false end
    if g_missionManager.missionGenerationInProgress == true then return false end
    -- Directly start a base-game generation cycle. Each cycle creates at most
    -- one mission and advances the mission-type cursor. Native generation can
    -- occasionally add nothing even while other eligible contracts remain, so
    -- the refill controller requires several consecutive empty cycles before
    -- it concludes that the board is exhausted.
    g_missionManager:startMissionGeneration()
    return true
end

local function normalizeRegenerationFieldId(value)
    if value == nil then return nil end
    if type(value) == "number" or type(value) == "string" then
        return tonumber(value) or value
    end
    return nil
end

local function getRegenerationFieldIdFromValue(value)
    local direct = normalizeRegenerationFieldId(value)
    if direct ~= nil then return direct end
    if type(value) ~= "table" then return nil end

    local keys = {"fieldId", "fieldID", "id", "fieldIndex", "index"}
    for _, key in ipairs(keys) do
        local resolved = normalizeRegenerationFieldId(value[key])
        if resolved ~= nil then return resolved end
    end

    local getters = {"getFieldId", "getFieldID", "getId", "getIndex"}
    for _, getter in ipairs(getters) do
        local fn = value[getter]
        if type(fn) == "function" then
            local ok, result = pcall(fn, value)
            if ok then
                local resolved = normalizeRegenerationFieldId(result)
                if resolved ~= nil then return resolved end
            end
        end
    end

    if g_fieldManager ~= nil and g_fieldManager.getFields ~= nil then
        for _, field in ipairs(g_fieldManager:getFields() or {}) do
            if value == field then
                return normalizeRegenerationFieldId(field.fieldId or field.id or field.fieldIndex)
            end
        end
    end
    return nil
end

local function getRegenerationMissionClassName(mission)
    if mission == nil then return "UNKNOWN" end
    if mission.className ~= nil then return tostring(mission.className) end
    if mission.typeName ~= nil then return tostring(mission.typeName) end
    if mission.missionTypeName ~= nil then return tostring(mission.missionTypeName) end
    if type(mission.type) == "table" then
        if mission.type.className ~= nil then return tostring(mission.type.className) end
        if mission.type.typeName ~= nil then return tostring(mission.type.typeName) end
        if mission.type.name ~= nil then return tostring(mission.type.name) end
    elseif mission.type ~= nil then
        return tostring(mission.type)
    end
    if type(mission.missionType) == "table" then
        if mission.missionType.className ~= nil then return tostring(mission.missionType.className) end
        if mission.missionType.typeName ~= nil then return tostring(mission.missionType.typeName) end
        if mission.missionType.name ~= nil then return tostring(mission.missionType.name) end
    elseif mission.missionType ~= nil then
        return tostring(mission.missionType)
    end
    local mt = getmetatable(mission)
    if mt ~= nil and type(mt.__index) == "table" then
        local idx = mt.__index
        if idx.className ~= nil then return tostring(idx.className) end
        if idx.typeName ~= nil then return tostring(idx.typeName) end
    end
    return tostring(mission)
end

local function describeRegenerationMissionFieldCandidates(mission)
    if type(mission) ~= "table" then return "NONE" end
    local entries = {}
    local seen = {}
    local function add(path, value)
        if seen[path] then return end
        seen[path] = true
        local valueType = type(value)
        local suffix = valueType
        local resolved = getRegenerationFieldIdFromValue(value)
        if resolved ~= nil then suffix = suffix .. ":" .. tostring(resolved) end
        table.insert(entries, path .. "=" .. suffix)
    end
    local function scan(tbl, prefix, depth, visited)
        if type(tbl) ~= "table" or depth > 3 or visited[tbl] then return end
        visited[tbl] = true
        local keys = {}
        for key in pairs(tbl) do table.insert(keys, key) end
        table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do
            local value = tbl[key]
            local keyText = string.lower(tostring(key))
            local path = prefix .. tostring(key)
            if string.find(keyText, "field", 1, true) ~= nil then
                add(path, value)
                if type(value) == "table" then scan(value, path .. ".", depth + 1, visited) end
            elseif type(value) == "table" and depth < 2 and (keyText == "data" or keyText == "info" or keyText == "mission" or keyText == "job") then
                scan(value, path .. ".", depth + 1, visited)
            end
        end
    end
    scan(mission, "mission.", 0, {})
    table.sort(entries)
    if #entries == 0 then return "NONE" end
    if #entries > 16 then
        local clipped = {}
        for i=1,16 do clipped[i] = entries[i] end
        return table.concat(clipped, "|") .. "|..."
    end
    return table.concat(entries, "|")
end

local function getRegenerationMissionFieldId(mission)
    if mission == nil then return nil, "none" end

    local directPaths = {
        {"mission.fieldId", mission.fieldId},
        {"mission.fieldID", mission.fieldID},
        {"mission.fieldIndex", mission.fieldIndex},
        {"mission.field", mission.field},
        {"mission.fieldData", mission.fieldData},
        {"mission.fieldInfo", mission.fieldInfo},
        {"mission.fieldMissionInfo", mission.fieldMissionInfo},
        {"mission.missionInfo", mission.missionInfo},
        {"mission.data", mission.data},
        {"mission.job", mission.job}
    }
    for _, candidate in ipairs(directPaths) do
        local resolved = getRegenerationFieldIdFromValue(candidate[2])
        if resolved ~= nil then return resolved, candidate[1] end
        if type(candidate[2]) == "table" then
            local nested = candidate[2]
            local nestedPaths = {
                {candidate[1] .. ".fieldId", nested.fieldId},
                {candidate[1] .. ".fieldID", nested.fieldID},
                {candidate[1] .. ".fieldIndex", nested.fieldIndex},
                {candidate[1] .. ".field", nested.field},
                {candidate[1] .. ".data", nested.data},
                {candidate[1] .. ".info", nested.info}
            }
            for _, nestedCandidate in ipairs(nestedPaths) do
                local nestedResolved = getRegenerationFieldIdFromValue(nestedCandidate[2])
                if nestedResolved ~= nil then return nestedResolved, nestedCandidate[1] end
            end
        end
    end

    local getters = {"getFieldId", "getFieldID", "getFieldIndex", "getField", "getFieldData", "getFieldInfo"}
    for _, getter in ipairs(getters) do
        local fn = mission[getter]
        if type(fn) == "function" then
            local ok, result = pcall(fn, mission)
            if ok then
                local resolved = getRegenerationFieldIdFromValue(result)
                if resolved ~= nil then return resolved, "mission:" .. getter .. "()" end
            end
        end
    end

    local visited = {}
    local function recursiveScan(tbl, path, depth)
        if type(tbl) ~= "table" or depth > 4 or visited[tbl] then return nil, nil end
        visited[tbl] = true
        for key, value in pairs(tbl) do
            local keyText = string.lower(tostring(key))
            local valuePath = path .. "." .. tostring(key)
            local isFieldReference = keyText == "field" or keyText == "fieldid" or keyText == "fieldindex"
                or keyText == "fielddata" or keyText == "fieldinfo" or keyText == "fieldmissioninfo"
            if isFieldReference then
                local resolved = getRegenerationFieldIdFromValue(value)
                if resolved ~= nil then return resolved, valuePath end
                if type(value) == "table" then
                    local nestedId, nestedPath = recursiveScan(value, valuePath, depth + 1)
                    if nestedId ~= nil then return nestedId, nestedPath end
                end
            elseif type(value) == "table" and depth < 2 then
                local nestedId, nestedPath = recursiveScan(value, valuePath, depth + 1)
                if nestedId ~= nil then return nestedId, nestedPath end
            end
        end
        return nil, nil
    end
    return recursiveScan(mission, "mission", 0)
end

local function getRegenerationMissionCropName(mission)
    if mission == nil then return "UNKNOWN" end
    local fruit = mission.fruitType
    if fruit ~= nil and fruit.name ~= nil then return upper(fruit.name) end
    local fruitIndex = mission.fruitTypeIndex or mission.fruitIndex
    if fruitIndex ~= nil and g_fruitTypeManager ~= nil then
        local ft = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
        if ft ~= nil and ft.name ~= nil then return upper(ft.name) end
    end
    return "UNKNOWN"
end

local function getRegenerationMissionTypeName(mission)
    if mission == nil then return "UNKNOWN" end
    if mission.type ~= nil then
        if type(mission.type) == "table" then
            if mission.type.name ~= nil then return tostring(mission.type.name) end
            if mission.type.typeName ~= nil then return tostring(mission.type.typeName) end
        else
            return tostring(mission.type)
        end
    end
    if mission.missionType ~= nil then return tostring(mission.missionType) end
    if mission.className ~= nil then return tostring(mission.className) end
    return tostring(mission)
end

function CCO:auditNpcMapRegenerationMissions(state)
    local actions = state.actions or {}
    local missions = g_missionManager ~= nil and (g_missionManager:getMissions() or {}) or {}
    local missionsByField = {}
    local unmatchedMissions = 0
    for missionIndex, mission in ipairs(missions) do
        local fieldId, fieldSource = getRegenerationMissionFieldId(mission)
        local missionClass = getRegenerationMissionClassName(mission)
        local missionCrop = getRegenerationMissionCropName(mission)
        local candidates = describeRegenerationMissionFieldCandidates(mission)
        debug(("mission inspect index=%d class=%s crop=%s resolvedFieldId=%s fieldSource=%s fieldCandidates=%s"):format(
            missionIndex, tostring(missionClass), tostring(missionCrop), tostring(fieldId or "NONE"), tostring(fieldSource or "NONE"), candidates))
        if fieldId ~= nil then
            local key = tostring(fieldId)
            missionsByField[key] = missionsByField[key] or {}
            table.insert(missionsByField[key], mission)
        else
            unmatchedMissions = unmatchedMissions + 1
        end
    end

    local cropStats = {}
    local readyFields, readyWithMission, readyWithoutMission = 0, 0, 0
    local naturalReady, naturalContracts, fallbackReady, fallbackContracts = 0, 0, 0, 0
    for _, action in ipairs(actions) do
        if action.action == "crop" and action.fruit ~= nil then
            local minState = tonumber(action.fruit.minHarvestingGrowthState)
            local maxState = tonumber(action.fruit.maxHarvestingGrowthState)
            local stateValue = tonumber(action.growthState)
            local harvestReady = minState ~= nil and maxState ~= nil and stateValue ~= nil
                and stateValue >= minState and stateValue <= maxState
            if harvestReady then
                readyFields = readyFields + 1
                local crop = upper(action.cropName or (action.fruit.name or "UNKNOWN"))
                local fallback = string.find(tostring(action.reason or ""), "harvest%-window fallback") ~= nil
                local matches = missionsByField[tostring(action.fieldId)] or {}
                local hasMission = #matches > 0
                cropStats[crop] = cropStats[crop] or {ready=0, contracts=0, naturalReady=0, naturalContracts=0, fallbackReady=0, fallbackContracts=0}
                local stats = cropStats[crop]
                stats.ready = stats.ready + 1
                if fallback then
                    fallbackReady = fallbackReady + 1
                    stats.fallbackReady = stats.fallbackReady + 1
                else
                    naturalReady = naturalReady + 1
                    stats.naturalReady = stats.naturalReady + 1
                end
                if hasMission then
                    readyWithMission = readyWithMission + 1
                    stats.contracts = stats.contracts + 1
                    if fallback then fallbackContracts = fallbackContracts + 1; stats.fallbackContracts = stats.fallbackContracts + 1
                    else naturalContracts = naturalContracts + 1; stats.naturalContracts = stats.naturalContracts + 1 end
                else
                    readyWithoutMission = readyWithoutMission + 1
                end
                local missionDetails = {}
                for _, mission in ipairs(matches) do
                    table.insert(missionDetails, getRegenerationMissionTypeName(mission) .. "/" .. getRegenerationMissionCropName(mission))
                end
                debug(("mission audit field=%s crop=%s state=%s source=%s harvestReady=true missionPresent=%s missions=%s"):format(
                    tostring(action.fieldId), crop, tostring(action.growthState), fallback and "fallback" or "natural",
                    tostring(hasMission), #missionDetails > 0 and table.concat(missionDetails, ",") or "NONE"))
            end
        end
    end

    local crops = {}
    for crop in pairs(cropStats) do table.insert(crops, crop) end
    table.sort(crops)
    for _, crop in ipairs(crops) do
        local stats = cropStats[crop]
        debug(("mission audit crop=%s ready=%d contracts=%d naturalReady=%d naturalContracts=%d fallbackReady=%d fallbackContracts=%d"):format(
            crop, stats.ready, stats.contracts, stats.naturalReady, stats.naturalContracts, stats.fallbackReady, stats.fallbackContracts))
    end
    info(("mission audit summary harvestReadyFields=%d readyWithMission=%d readyWithoutMission=%d naturalReady=%d naturalContracts=%d fallbackReady=%d fallbackContracts=%d totalMissions=%d unmatchedMissionFields=%d"):format(
        readyFields, readyWithMission, readyWithoutMission, naturalReady, naturalContracts, fallbackReady, fallbackContracts, #missions, unmatchedMissions))
end

function CCO:finishNpcMapRegenerationMissionRefill(state, reason)
    self:auditNpcMapRegenerationMissions(state)
    local missions = self:getMissionCountForRegeneration()
    local msg = ("CCO: NPC map regeneration complete. queued=%d skipped=%d staleContractsRemoved=%d freshContracts=%d refillCycles=%d reason=%s"):format(
        tonumber(state.queued or 0), tonumber(state.skipped or 0), tonumber(state.removedMissions or 0),
        tonumber(missions or 0), tonumber(state.refillCycles or 0), tostring(reason or "complete"))
    print(msg)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, msg)
    end
    self._npcMapRegenerationState = nil
end

function CCO:updateNpcMapRegeneration(dt)
    local state = self._npcMapRegenerationState
    if state == nil then return end

    state.elapsedMs = (state.elapsedMs or 0) + (tonumber(dt) or 0)

    if state.phase == "waitingForFieldTasks" then
        if state.elapsedMs < 5000 then return end

        state.elapsedMs = 0
        self:refreshRegeneratedFieldStates(state)
        state.phase = "refillingContracts"
        state.refillCycles = 0
        state.lastMissionCount = self:getMissionCountForRegeneration()
        state.maxRefillCycles = math.max(30, math.min(100,
            tonumber((MissionManager ~= nil and MissionManager.MAX_MISSIONS) or 100) + 10))
        state.requiredEmptyCycles = 5
        state.emptyCycleStreak = 0

        local started = self:startFreshMissionGenerationAfterRegeneration()
        if not started then
            warn("field regeneration completed but fresh mission generation could not be started")
            self:finishNpcMapRegenerationMissionRefill(state, "mission-generation-start-failed")
            return
        end
        state.refillCycles = 1
        info(("field regeneration settle delay complete; starting contract refill after removing %d stale contract(s); initialMissions=%d"):format(
            tonumber(state.removedMissions or 0), tonumber(state.lastMissionCount or 0)))
        return
    end

    if state.phase ~= "refillingContracts" then return end
    if g_missionManager == nil then
        self:finishNpcMapRegenerationMissionRefill(state, "mission-manager-unavailable")
        return
    end

    -- Let MissionManager:update() finish the active generation cycle first.
    if g_missionManager.missionGenerationInProgress == true then return end

    local missionCount = self:getMissionCountForRegeneration()
    local previousCount = tonumber(state.lastMissionCount or 0)
    local maxMissions = tonumber((MissionManager ~= nil and MissionManager.MAX_MISSIONS) or 100)
    local added = missionCount - previousCount
    local requiredEmptyCycles = tonumber(state.requiredEmptyCycles or 5)
    if added > 0 then
        state.emptyCycleStreak = 0
    else
        state.emptyCycleStreak = tonumber(state.emptyCycleStreak or 0) + 1
    end
    info(("contract refill cycle=%d missions=%d added=%d emptyStreak=%d/%d"):format(
        tonumber(state.refillCycles or 0), missionCount, added,
        tonumber(state.emptyCycleStreak or 0), requiredEmptyCycles))

    if missionCount >= maxMissions then
        self:finishNpcMapRegenerationMissionRefill(state, "mission-limit-reached")
        return
    end

    -- A single empty native cycle is not conclusive. Stop only after several
    -- consecutive cycles add no missions; any successful cycle resets the streak.
    if tonumber(state.emptyCycleStreak or 0) >= requiredEmptyCycles then
        self:finishNpcMapRegenerationMissionRefill(state, "consecutive-empty-cycles")
        return
    end

    if tonumber(state.refillCycles or 0) >= tonumber(state.maxRefillCycles or 100) then
        self:finishNpcMapRegenerationMissionRefill(state, "safety-cycle-limit")
        return
    end

    state.lastMissionCount = missionCount
    local started = self:startFreshMissionGenerationAfterRegeneration()
    if not started then
        self:finishNpcMapRegenerationMissionRefill(state, "next-generation-start-failed")
        return
    end
    state.refillCycles = tonumber(state.refillCycles or 0) + 1
end

function CCO:confirmNpcMapRegeneration()
    local plan = self._npcMapRegenerationPlan
    if plan == nil then
        print("CCO: no armed regeneration plan. Run ccoRegenerateNpcFields dryrun first.")
        return 0, 0
    end
    if self._npcMapRegenerationState ~= nil then
        print("CCO: NPC map regeneration is already in progress.")
        return 0, 0
    end
    if tonumber(plan.unverified or 0) > 0 then
        print(("CCO: regeneration confirmation blocked: %d planned field action(s) use unverified growth states. Run a new dry-run and ccoGrowthProbe for the affected crops."):format(tonumber(plan.unverified or 0)))
        return 0, 0
    end
    if plan.period ~= getCurrentPeriodIndex() or plan.year ~= getCalendarYearToken() then
        self._npcMapRegenerationPlan = nil
        print("CCO: regeneration plan expired because the calendar changed. Run a new dry-run.")
        return 0, 0
    end

    local activeContracts = self:getActiveContractCount()
    if activeContracts > 0 then
        print(("CCO: regeneration refused because %d accepted/active contract(s) exist. Complete or cancel them, then run a new dry-run."):format(activeContracts))
        return 0, 0
    end

    local removedMissions, purgeReason = self:purgeAvailableContractsForRegeneration()
    if purgeReason ~= "ok" then
        print("CCO: regeneration refused: " .. tostring(purgeReason))
        return 0, 0
    end
    info(("removed %d stale available contract(s) before full NPC map regeneration"):format(removedMissions))

    local queued, skipped = 0, 0
    local regeneratedFields = {}
    for _, action in ipairs(plan.actions or {}) do
        local ok, reason
        if action.action == "crop" then
            ok, reason = self:setFieldReseeded(action.field, action.fruit, action.growthState)
        else
            ok = self:setFieldCultivated(action.field)
            reason = ok and "queued" or "field update failed"
        end
        if ok then
            queued = queued + 1
            table.insert(regeneratedFields, action.field)
            info(("regenerate queued field=%s action=%s crop=%s growthState=%s"):format(
                tostring(action.fieldId), tostring(action.action), tostring(action.cropName), tostring(action.growthState)))
        else
            skipped = skipped + 1
            warn(("regenerate skipped field=%s action=%s crop=%s reason=%s"):format(
                tostring(action.fieldId), tostring(action.action), tostring(action.cropName), tostring(reason)))
        end
    end
    self._npcMapRegenerationPlan = nil

    self._npcMapRegenerationState = {
        phase = "waitingForFieldTasks", elapsedMs = 0, queued = queued, skipped = skipped,
        removedMissions = removedMissions,
        fields = regeneratedFields,
        actions = plan.actions,
    }
    print(("CCO: NPC map regeneration queued. queued=%d skipped=%d staleContractsRemoved=%d; waiting for field tasks before fresh mission generation."):format(
        queued, skipped, removedMissions))
    return queued, skipped
end

function CCO:buildNpcMapRegenerationGuiSummary(plan)
    if plan == nil then return "No regeneration plan is available." end
    local lines = {
        ("NPC fields: %d | Planned: %d | Excluded: %d"):format(
            tonumber(plan.npcFields or 0), #(plan.actions or {}), tonumber(plan.excluded or 0)),
        ("Authoritative: %d | Unverified: %d"):format(
            #(plan.actions or {}) - tonumber(plan.unverified or 0), tonumber(plan.unverified or 0)),
        "Crop distribution:",
    }
    local names = {}
    for name in pairs(plan.distribution or {}) do table.insert(names, name) end
    table.sort(names)
    local chunks = {}
    for _, name in ipairs(names) do
        table.insert(chunks, tostring(name) .. "=" .. tostring(plan.distribution[name]))
    end
    table.insert(lines, #chunks > 0 and table.concat(chunks, " | ") or "NONE")
    return table.concat(lines, "\n")
end

function CCO:regenerateNpcFieldsDryRunFromGui()
    if g_currentMission == nil or g_currentMission.getIsServer == nil or not g_currentMission:getIsServer() then
        self._npcMapRegenerationPlan = nil
        return "Regeneration can only be run by the server/host.", 0, false
    end
    if self.canEditRules ~= nil and not self:canEditRules() then
        self._npcMapRegenerationPlan = nil
        return "Regeneration is read-only for remote multiplayer clients.", 0, false
    end
    if self._npcMapRegenerationState ~= nil then
        return "NPC map regeneration is already in progress.", 0, false
    end
    local activeContracts = self:getActiveContractCount()
    if activeContracts > 0 then
        self._npcMapRegenerationPlan = nil
        return ("Preview blocked: %d accepted/active contract(s) exist. Complete or cancel them first."):format(activeContracts), 0, false
    end
    local plan, reason = self:buildNpcMapRegenerationPlan()
    if plan == nil then
        self._npcMapRegenerationPlan = nil
        return "Preview failed: " .. tostring(reason), 0, false
    end
    self._npcMapRegenerationPlan = plan
    self:printNpcMapRegenerationPlan(plan)
    local confirmAllowed = tonumber(plan.unverified or 0) == 0 and #(plan.actions or {}) > 0
    return self:buildNpcMapRegenerationGuiSummary(plan), #(plan.actions or {}), confirmAllowed
end

function CCO:regenerateNpcFieldsFromGui()
    if g_currentMission == nil or g_currentMission.getIsServer == nil or not g_currentMission:getIsServer() then
        return "Regeneration can only be run by the server/host."
    end
    if self.canEditRules ~= nil and not self:canEditRules() then
        return "Regeneration is read-only for remote multiplayer clients."
    end
    local plan = self._npcMapRegenerationPlan
    if plan == nil then
        return "No preview is armed. Run PREVIEW NPC REGENERATION first."
    end
    local planned = #(plan.actions or {})
    local queued, skipped = self:confirmNpcMapRegeneration()
    queued = tonumber(queued or 0) or 0
    skipped = tonumber(skipped or 0) or 0
    if queued <= 0 then
        return "Regeneration was not started. Review the game log for the refusal reason."
    end
    return ("Regeneration queued for %d of %d planned NPC field(s); skipped=%d. Field caches and contracts will rebuild after the settle delay."):format(queued, planned, skipped)
end

function CCO:consoleRegenerateNpcFields(modeArg)
    local mode = string.lower(tostring(modeArg or "dryrun"))
    if mode == "dryrun" or mode == "dry" or mode == "preview" then
        local plan, reason = self:buildNpcMapRegenerationPlan()
        if plan == nil then
            print("CCO: NPC map regeneration dry-run failed: " .. tostring(reason))
            return
        end
        self._npcMapRegenerationPlan = plan
        self:printNpcMapRegenerationPlan(plan)
        return
    end
    if mode == "confirm" or mode == "apply" then
        self:confirmNpcMapRegeneration()
        return
    end
    if mode == "clear" or mode == "cancel" then
        self._npcMapRegenerationPlan = nil
        print("CCO: armed NPC map regeneration plan cleared.")
        return
    end
    print("CCO: usage ccoRegenerateNpcFields [dryrun|confirm|clear]")
end
addConsoleCommand("ccoRegenerateNpcFields", "Experimental: regenerate all NPC fields using weighted enabled crops at calendar-derived growth states. Usage: ccoRegenerateNpcFields [dryrun|confirm|clear]", "consoleRegenerateNpcFields", CCO)


function CCO:consoleStatus()
    local disabled, npcDisabledRules, limited = 0, 0, 0
    for _, rule in pairs(self._rules or {}) do
        if rule ~= nil then
            if rule.enabled == false then disabled = disabled + 1 end
            if rule.enabled == false or rule.npcAllowed == false then npcDisabledRules = npcDisabledRules + 1 end
            if rule.npcMaxHa ~= nil and rule.npcMaxHa > 0 then limited = limited + 1 end
        end
    end

    local summary = self:buildFieldSummary(nil)
    print(("CCO: status version=%s config=%s"):format(tostring(self.VERSION), tostring(self._configPath)))
    print(("CCO: rules disabled=%d npcDisabledRules=%d limited=%d totalRules=%d"):format(disabled, npcDisabledRules, limited, (function()
        local n = 0
        for _, _ in pairs(self._rules or {}) do n = n + 1 end
        return n
    end)()))
    print(("CCO: fields checked=%d npcFields=%d playerFields=%d offendingNpcFields=%d"):format(
        tonumber(summary.total or 0), tonumber(summary.npcTotal or 0), tonumber(summary.playerTotal or 0), tonumber(summary.offending or 0)))
    local weights = self:getReseedWeights()
    print(("CCO: reseedWeights perCrop=0-5 leaveCultivated=%d"):format(weights.leaveCultivated))
    if summary.offending ~= nil and summary.offending > 0 then
        print("CCO: status=ATTENTION run ccoScanBlocked, then ccoResetBlocked dryrun if cleanup is intended")
    else
        print("CCO: status=OK validation would pass")
    end
end
addConsoleCommand("ccoStatus", "Show CCO version/config/rule/field status", "consoleStatus", CCO)

function CCO:consoleHelp(topic)
    local t = topic ~= nil and string.lower(tostring(topic)) or ""
    print("CCO: Crop Control Override command help")
    if t == "rules" or t == "rule" or t == "" then
        print("CCO: Rules/config:")
        print("CCO:   ccoWhichConfig")
        print("CCO:   ccoStatus")
        print("CCO:   ccoReload")
        print("CCO:   ccoExplain <CROP>")
        print("CCO:   ccoListRules [CROP]")
        print("CCO:   ccoListConfigured [CROP]")
        print("CCO:   ccoListUndiscovered")
        print("CCO:   ccoNormalizeConfig [dryrun]")
        print("CCO:   ccoSetCrop <CROP> <enabled> [npcAllowed] [npcMaxHa]")
        print("CCO:   ccoListDisabled | ccoListBlockedRules | ccoListLimited")
    end
    if t == "scan" or t == "scans" or t == "" then
        print("CCO: Scanning/validation:")
        print("CCO:   ccoScanFields [CROP]")
        print("CCO:   ccoScanBlocked [CROP]")
        print("CCO:   ccoScanSummary [CROP]")
        print("CCO:   ccoValidateSave")
        print("CCO:   ccoListNpcCandidates <FIELD_ID>")
        print("CCO:   ccoSeasonProbe [CROP]")
        print("CCO:   ccoGrowthProbe [CROP]")
        print("CCO:   ccoRegenerateNpcFields [dryrun|confirm|clear]  (experimental alpha)")
        print("CCO:   Seasonal reseed candidates use growthDataSeasonal.periods[currentPeriod].plantingAllowed.")
        print("CCO:   Each <fruit> has reseedWeight='0-5'; leaveCultivated remains under <settings><reseedCandidateWeights leaveCultivated='0-5'/>.")
        print("CCO:   ccoFieldSizeProbe <FIELD_ID>")
    end
    if t == "reset" or t == "cleanup" or t == "" then
        print("CCO: Cleanup:")
        print("CCO:   ccoResetBlocked dryrun")
        print("CCO:   ccoResetBlocked")
        print("CCO:   ccoResetNpcFields [CROP|all] [dryrun]")
        print("CCO:   GUI cleanup supports RESET MODE: CULTIVATED or RESEED SEASONAL.")
        print("CCO:   Reset commands only target offending NPC fields; use dryrun first.")
    end
    if t == "debug" or t == "log" or t == "" then
        print("CCO: Logging/debug:")
        print("CCO:   ccoDebug on|off|toggle")
        print("CCO:   ccoLogLevel DEBUG|INFO|WARN|ERROR")
        print("CCO:   NPC replacement and field-blocking detail is logged at DEBUG level.")
    end
end
addConsoleCommand("ccoHelp", "Show CCO command help. Usage: ccoHelp [rules|scan|reset|debug]", "consoleHelp", CCO)

info("loaded " .. CCO.MOD_ID .. " v" .. CCO.VERSION)

function CCO:consoleGui(topic, pageArg)
    self:openGui(topic, pageArg)
end
addConsoleCommand("ccoGui", "Open CCO GUI. Usage: ccoGui [status|rules|disabled|limited|blocked|undiscovered|help]", "consoleGui", CCO)
addConsoleCommand("ccoGuiTest", "Open a minimal CCO GUI dialog test", "consoleGuiTest", CCO)
