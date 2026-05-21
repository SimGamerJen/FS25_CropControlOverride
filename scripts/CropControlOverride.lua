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
    VERSION = "2.0.0-alpha.90",

    _origFlags = {},
    _rules = {},
    _configPath = nil,
    _hookApplied = false,
    _sowHookApplied = false,
    _loadFinishedHookApplied = false,
    _startupValidationPrinted = false,
    MOD_DIRECTORY = g_currentModDirectory or "",
}

local CCO = CropControlOverride
local log = CCO_Debug or Debug or nil

local NPC_FARM_ID = 0
local CONFIG_ROOT = "cropControl"
local SETTINGS_FOLDER = "FS25_CropControlOverride"

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

local function policyText(v)
    if v == nil then return "Map Default" end
    if v == true then return "Yes" end
    if v == false then return "No" end
    return tostring(v)
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

local function getFieldSizeHa(field)
    if field == nil then return 0 end
    if field.farmland ~= nil and field.farmland.areaInHa ~= nil then
        return field.farmland.areaInHa
    end
    return field.areaHa or 0
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
    }
end

local function defaultRuleForFruit(ft)
    return normalizeRule(ft and ft.name, {
        enabled = true,
        npcAllowed = nil,
        npcMaxHa = 0,
        resetNpcFields = true,
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
    -- Keep the crop available to the player, but prevent generated field jobs
    -- and NPC mission crop selection where the engine respects this flag.
    fruit.useForFieldMissions = false
    fruit.useForFieldJob = false
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
    if path == nil or not fileExists(path) then return rules end

    local xml = XMLFile.load("CCO_read", path, CONFIG_ROOT)
    if xml == nil then return rules end

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
    return rules
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

local function writeConfig(path, rules)
    if path == nil then return false end
    ensureFolderForFile(path)

    local xml = XMLFile.create("CCO_write", path, CONFIG_ROOT)
    if xml == nil then
        err("cannot create config at " .. tostring(path))
        return false
    end

    xml:setString(CONFIG_ROOT .. "#version", "2")
    xml:setString(CONFIG_ROOT .. "#modVersion", CCO.VERSION)

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
    if writeConfig(tpl, rules) then
        debug("wrote default template at " .. tpl)
    end
    return tpl
end

function CCO:loadRulesForMission(missionInfo)
    local saveId = getSaveIdFromMissionInfo(missionInfo)
    local per = perSavePathForId(saveId)
    local tpl = ensureTemplateExists()

    local path = tpl
    local rules = nil

    if per ~= nil and fileExists(per) then
        path = per
        local meta = inspectConfigNormalization(per)
        rules = readConfig(per)
        if rules == nil or not next(rules) then rules = buildDefaultRules() end
        rules = mergeMissingDiscoveredFruits(rules)
        if meta ~= nil and meta.needsNormalize then
            if writeConfig(per, rules) then
                debug(("normalized legacy per-save config at %s (%s)"):format(per, describeNormalization(meta)))
            end
        end
    else
        local meta = inspectConfigNormalization(tpl)
        rules = readConfig(tpl)
        if not next(rules) then rules = buildDefaultRules() end
        rules = mergeMissingDiscoveredFruits(rules)
        if per ~= nil and writeConfig(per, rules) then
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


local function isFruitUsableForNpcCandidate(ft)
    if ft == nil or ft.name == nil then return false, "invalid fruit" end
    -- Respect engine-facing flags that CCO or the map/DLC has already applied.
    if ft.useForFieldMissions == false then return false, "useForFieldMissions=false" end
    if ft.useForFieldJob == false then return false, "useForFieldJob=false" end
    if ft.allowsSeeding == false then return false, "allowsSeeding=false" end
    return true, "engine flags ok"
end

function CCO:buildNpcCandidatesForField(field, includeBlocked)
    local candidates = {}
    if field == nil then return candidates end

    local fieldHa = getFieldSizeHa(field)
    for _, ft in ipairs(iterFruitTypesSorted()) do
        local cropName = upper(ft.name)
        local flagOk, flagReason = isFruitUsableForNpcCandidate(ft)
        local policyOk, policyReason = self:isNpcCropAllowedForField(fieldHa, cropName)
        local ok = flagOk and policyOk

        if includeBlocked == true or ok then
            local rule = self._rules and self._rules[cropName] or nil
            local limited = rule ~= nil and rule.npcMaxHa ~= nil and rule.npcMaxHa > 0
            local explicitNpcAllowed = rule ~= nil and rule.npcAllowed == true
            local priority = 50
            if ok and limited then
                priority = 10
            elseif ok and explicitNpcAllowed then
                priority = 20
            elseif ok then
                priority = 30
            end

            table.insert(candidates, {
                fruit = ft,
                cropName = cropName,
                ok = ok,
                reason = ok and "allowed" or (not flagOk and flagReason or policyReason),
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

function CCO:findReplacementNpcCropForField(field, blockedCropName)
    local candidates = self:buildNpcCandidatesForField(field, false)
    if #candidates == 0 then return nil, "no valid NPC candidates" end

    local fieldIdNum = tonumber(getFieldId(field)) or 1
    local bestPriority = candidates[1].priority
    local pool = {}
    for _, c in ipairs(candidates) do
        if c.priority == bestPriority then
            if blockedCropName == nil or upper(blockedCropName) ~= c.cropName then
                table.insert(pool, c)
            end
        end
    end
    if #pool == 0 then pool = candidates end

    local pickIndex = ((fieldIdNum - 1) % #pool) + 1
    local picked = pool[pickIndex]
    if picked ~= nil then
        return picked.fruit, "replacement selected"
    end
    return nil, "no replacement selected"
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

function CCO:resetNpcFields(filterCrop, dryRun)
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
                        print(("CCO: dry-run would reset field=%s crop=%s size=%.2fha reason=%s"):format(
                            tostring(getFieldId(field, idx)), cropName, getFieldSizeHa(field), tostring(reason)))
                    elseif self:setFieldCultivated(field) then
                        queued = queued + 1
                        info(("queued field %s (%s, %.2f ha) to cultivated state: %s"):format(
                            tostring(getFieldId(field, idx)), cropName, getFieldSizeHa(field), tostring(reason)))
                    else
                        skipped = skipped + 1
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

function CCO:applyRuntimeHooks()
    if self._hookApplied then return end
    self._hookApplied = true

    if MissionManager ~= nil and MissionManager.generateMissions ~= nil then
        local originalGenerateMissions = MissionManager.generateMissions
        MissionManager.generateMissions = function(mm, ...)
            local saved = {}

            if g_currentMission ~= nil and g_currentMission.getIsServer ~= nil and g_currentMission:getIsServer()
                and CCO._rules ~= nil and g_fieldManager ~= nil and g_fieldManager.getFields ~= nil then

                for _, field in pairs(g_fieldManager:getFields()) do
                    local ft = getFieldFruit(field)
                    if ft ~= nil then
                        local cropName = upper(ft.name)
                        local allowed, reason = CCO:isNpcCropAllowedForField(getFieldSizeHa(field), cropName)
                        if not allowed and saved[cropName] == nil then
                            saved[cropName] = { fruit = ft, useForFieldMissions = ft.useForFieldMissions }
                            ft.useForFieldMissions = false
                            debug(("temporarily blocked %s during mission generation: %s"):format(cropName, tostring(reason)))
                        end
                    end
                end
            end

            local result = originalGenerateMissions(mm, ...)

            for cropName, state in pairs(saved) do
                state.fruit.useForFieldMissions = state.useForFieldMissions
                debug(("restored mission flag for %s to %s"):format(cropName, tostring(state.useForFieldMissions)))
            end

            return result
        end
        debug("hooked MissionManager.generateMissions")
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
        CCO:applyRules(rules)
        debug(("applied crop policy from %s"):format(tostring(path)))
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
        if CCO._configPath ~= nil then
            writeConfig(CCO._configPath, CCO._rules)
        end
        CCO:applyRules(CCO._rules)
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
            writeConfig(CCO._configPath, CCO._rules)
        end
    end)
end

FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, function()
    CCO._rules = {}
    CCO._configPath = nil
    CCO._startupValidationPrinted = false
end)



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

    table.insert(lines, "NAVIGATION")
    table.insert(lines, "Use the top tabs, or PREV TAB / NEXT TAB, to move between sections.")
    table.insert(lines, "Use RELOAD to re-read the active config. Use BACK to close the screen.")
    table.insert(lines, "Crop rules can be edited from the ALL RULES table. Select a crop, stage changes in the right panel, then use APPLY.")
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

function CCO:buildGuiRuleListText(mode, pageArg)
    mode = mode ~= nil and string.lower(tostring(mode)) or "rules"
    local names = {}
    for nameU, _ in pairs(self._rules or {}) do table.insert(names, nameU) end
    table.sort(names)

    local rows = {}
    local count = 0
    for _, nameU in ipairs(names) do
        local r = self._rules[nameU]
        local include = true
        if mode == "disabled" then include = r.enabled == false end
        if mode == "limited" then include = tonumber(r.npcMaxHa or 0) > 0 end
        if mode == "blockedrules" or mode == "blocked-rules" then include = r.enabled == false or r.npcAllowed == false end
        if mode == "undiscovered" then include = getFruitByName(nameU) == nil end

        if include then
            count = count + 1
            table.insert(rows, {
                crop = nameU,
                enabled = r.enabled == false and "No" or "Yes",
                npc = policyText(r.npcAllowed),
                maxHa = tonumber(r.npcMaxHa or 0),
                discovered = getFruitByName(nameU) ~= nil and "Yes" or "No",
                status = self:ruleStatusText(nameU, r),
            })
        end
    end

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
        string.format("%-16s %-7s %-10s %-8s %-10s %-10s", "Crop", "Enabled", "NPC", "Max ha", "Loaded", "Status"),
        string.rep("-", 72),
    }

    local shown = 0
    for i = startIndex, endIndex do
        local row = rows[i]
        if row ~= nil then
            shown = shown + 1
            table.insert(lines, string.format("%-16s %-7s %-10s %8.2f %-10s %-10s",
                row.crop, row.enabled, tostring(row.npc), row.maxHa, row.discovered, row.status))
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
    table.insert(lines, "")
    table.insert(lines, "Read-only view. Rule editing still uses XML or ccoSetCrop in this build.")
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
        "Field       Crop             Size ha   Reason",
        "------------------------------------------------------------",
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
                    table.insert(rows, {
                        fieldId = tostring(getFieldId(field, i)),
                        cropName = cropName,
                        sizeHa = getFieldSizeHa(field),
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

            table.insert(lines, ("%-11s %-16s %7.2f   %s"):format(
                row.fieldId,
                row.cropName,
                tonumber(row.sizeHa or 0) or 0,
                row.reason
            ))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "RECOMMENDED CLEANUP")
    table.insert(lines, "1. Review the blocked field rows above.")
    table.insert(lines, "2. Run ccoResetBlocked dryrun before changing the save state.")
    table.insert(lines, "3. Run ccoResetBlocked only after confirming the dry-run output.")
    return table.concat(lines, "\n")
end

function CCO:buildGuiHelpText()
    return table.concat({
        "CROP CONTROL OVERRIDE HELP",
        "",
        "NAVIGATION",
        "Use the tab headings or PREV TAB / NEXT TAB to switch sections.",
        "Use RELOAD to re-read the active per-save XML.",
        "Use BACK or ESC to close the CCO screen.",
        "",
        "TABLE COLUMNS",
        "Player Permitted: whether the crop is available under the crop policy.",
        "NPC Permitted: whether NPCs may plant the crop, or whether the map default is used.",
        "Max Field (ha): maximum NPC field size for that crop. 0.00 means no CCO size limit.",
        "Loaded: whether the crop exists on the active map/save.",
        "",
        "POLICY TERMS",
        "Disabled: the crop is unavailable under the crop policy.",
        "NPC Disabled: NPCs should not plant this crop. Globally disabled crops also count as NPC-disabled.",
        "Size Limited: NPCs may plant the crop only below the configured hectare limit.",
        "Blocked NPC Fields: existing NPC fields that currently violate the active policy.",
        "Not Loaded: the rule is preserved, but the crop is not present on this map/save.",
        "",
        "CONFIG FILES",
        "config.xml: template/default rules used when creating or normalising saves.",
        "saves/savegameX.xml: active per-save rules used by the current savegame.",
        "APPLY / FORCE APPLY: writes one staged crop rule to the active per-save XML.",
        "SAVE DEFAULTS: backs up config.xml, then writes the full active rule set to config.xml.",
        "SAVE DEFAULTS does not overwrite existing per-save XML files.",
        "",
        "SAFE CLEANUP",
        "Use ccoScanBlocked to review invalid NPC fields.",
        "Use ccoResetBlocked dryrun before resetting fields.",
        "Use ccoResetBlocked only after the dry-run output looks correct.",
        "",
        "EDITING",
        "Crop rules can be edited from the ALL RULES table. Guarded APPLY prevents accidental blocked-field changes; FORCE APPLY allows deliberate policy changes.",
    }, "\n")
end

function CCO:openGui(topic, pageArg)
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
        }
    end
    return cloned
end

function CCO:buildFieldSummaryWithRules(rules, filterCrop)
    local oldRules = self._rules
    self._rules = rules
    local summary = self:buildFieldSummary(filterCrop)
    self._rules = oldRules
    return summary
end

function CCO:applyGuiStagedRule(staged, forceApply)
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

    self._rules = self._rules or buildDefaultRules()

    local proposedRules = cloneRulesForGuiApply(self._rules)
    proposedRules[nameU] = normalizeRule(nameU, {
        enabled = enabled,
        npcAllowed = npcAllowed,
        npcMaxHa = npcMaxHa,
        resetNpcFields = resetNpcFields,
    })

    local preflight = self:buildFieldSummaryWithRules(proposedRules, nil)
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
                writeConfig(per, self._rules)
            end
            self._configPath = per
        end
    elseif self._configPath == nil then
        self._configPath = tpl
    end

    local writeOk = writeConfig(self._configPath, self._rules)
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


function CCO:saveCurrentRulesToTemplateConfig()
    local rules = self._rules
    if rules == nil or not next(rules) then
        return false, "No active CCO rules are loaded."
    end

    local tpl = templatePath()
    local stamp = (os ~= nil and os.date ~= nil) and os.date("%Y%m%d_%H%M%S") or tostring(g_time or "unknown")
    local backupPath = settingsRoot() .. "backups/config_backup_" .. stamp .. ".xml"

    local backupRules = nil
    if fileExists(tpl) then
        backupRules = readConfig(tpl)
        if backupRules == nil or not next(backupRules) then
            backupRules = buildDefaultRules()
        end

        if not writeConfig(backupPath, backupRules) then
            local msg = "Failed to create template backup; config.xml was not changed."
            print("CCO GUI SAVE DEFAULTS: " .. msg)
            self._guiNotice = msg
            return false, msg
        end
    end

    if not writeConfig(tpl, rules) then
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
            inputBinding:setActionEventText(eventId, "Open Crop Control Override")
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
    local sid = getSaveIdFromMissionInfo(g_currentMission and g_currentMission.missionInfo)
    local per = sid ~= nil and perSavePathForId(sid) or nil
    local tpl = templatePath()
    local path = tpl

    if per ~= nil then
        if not fileExists(per) then
            local templateRules = readConfig(tpl)
            if not next(templateRules) then templateRules = buildDefaultRules() end
            templateRules = mergeMissingDiscoveredFruits(templateRules)
            if writeConfig(per, templateRules) then
                print(("CCO: created per-save config during reload: %s"):format(tostring(per)))
            end
        end
        if fileExists(per) then
            path = per
        end
    end

    local meta = inspectConfigNormalization(path)
    local rules = readConfig(path)
    if not next(rules) then rules = buildDefaultRules() end
    rules = mergeMissingDiscoveredFruits(rules)
    if meta ~= nil and meta.needsNormalize then
        writeConfig(path, rules)
        print(("CCO: normalized config during reload: %s"):format(describeNormalization(meta)))
    end
    self._configPath = path
    self._rules = rules
    self:applyRules(rules)
    print(("CCO: reload complete from %s"):format(tostring(path)))
end
addConsoleCommand("ccoReload", "Reload CropControlOverride config and reapply", "consoleReload", CCO)

function CCO:consoleWhichConfig()
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
            print(("CCO: %s enabled=%s npcAllowed=%s npcMaxHa=%.2f resetNpcFields=%s discovered=%s"):format(
                nameU, tostring(r.enabled), tostring(r.npcAllowed == nil and "mapDefault" or r.npcAllowed), tonumber(r.npcMaxHa or 0), tostring(r.resetNpcFields), tostring(ft ~= nil)))
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
        print(("CCO: %s enabled=%s npcAllowed=%s npcMaxHa=%.2f resetNpcFields=%s"):format(
            nameU, tostring(r.enabled), tostring(r.npcAllowed == nil and "mapDefault" or r.npcAllowed), tonumber(r.npcMaxHa or 0), tostring(r.resetNpcFields)))
    end
    print(("CCO: undiscovered crop list complete. count=%d"):format(#names))
end
addConsoleCommand("ccoListUndiscovered", "List configured crops that are not loaded on this map/save", "consoleListUndiscovered", CCO)

function CCO:consoleNormalizeConfig(modeArg)
    local path = self._configPath or templatePath()
    local dryRun = modeArg ~= nil and string.lower(tostring(modeArg)) == "dryrun"
    local meta = inspectConfigNormalization(path)
    local rules = readConfig(path)
    if not next(rules) then rules = self._rules or buildDefaultRules() end
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

    if writeConfig(path, rules) then
        self._rules = rules
        self._configPath = path
        self:applyRules(rules)
        print("CCO: config normalization complete")
    else
        print("CCO: config normalization failed")
    end
end
addConsoleCommand("ccoNormalizeConfig", "Normalize/migrate active config to v2. Usage: ccoNormalizeConfig [dryrun]", "consoleNormalizeConfig", CCO)

function CCO:consoleSetCrop(name, enabledArg, npcAllowedArg, npcMaxHaArg)
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
        writeConfig(self._configPath, self._rules)
    end
    self:consoleListRules(nameU)
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
        print(("CCO:   %-14s %s reason=%s%s"):format(c.cropName, c.ok and "OK" or "BLOCKED", tostring(c.reason), limitText))
    end
    print(("CCO: candidate list complete. valid=%d total=%d"):format(valid, #candidates))
end
addConsoleCommand("ccoListNpcCandidates", "List NPC crop candidates for a field. Usage: ccoListNpcCandidates <FIELD_ID>", "consoleListNpcCandidates", CCO)

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


function CCO:resetBlockedFieldsDryRunFromGui()
    local wouldQueue, skipped = self:resetNpcFields(nil, true)
    local summary = self:buildFieldSummary(nil)

    local msg = ("Dry-run complete. %d blocked NPC field(s) would be reset. skipped=%d. No save-state changes were made."):format(
        tonumber(wouldQueue or 0) or 0,
        tonumber(skipped or 0) or 0
    )

    if tonumber(summary.offending or 0) == 0 then
        msg = "Dry-run complete. No blocked NPC fields were detected. No save-state changes were made."
    end

    print("CCO GUI RESET DRY-RUN: " .. msg)
    self._guiNotice = msg
    return msg, tonumber(wouldQueue or 0) or 0, tonumber(skipped or 0) or 0
end

function CCO:resetBlockedFieldsFromGui()
    local before = self:buildFieldSummary(nil)
    local beforeCount = tonumber(before.offending or 0) or 0

    if beforeCount <= 0 then
        local msg = "Reset skipped. No blocked NPC fields were detected."
        print("CCO GUI RESET BLOCKED: " .. msg)
        self._guiNotice = msg
        return msg, 0, 0
    end

    local queued, skipped = self:resetNpcFields(nil, false)
    local after = self:buildFieldSummary(nil)
    local remaining = tonumber(after.offending or 0) or 0

    local msg = ("Reset complete. queued=%d skipped=%d remainingBlockedNpcFields=%d."):format(
        tonumber(queued or 0) or 0,
        tonumber(skipped or 0) or 0,
        remaining
    )

    print("CCO GUI RESET BLOCKED: " .. msg)
    self._guiNotice = msg
    return msg, tonumber(queued or 0) or 0, tonumber(skipped or 0) or 0
end


function CCO:consoleResetNpcFields(cropNameArg, modeArg)
    local cropName, dryRun = parseResetArgs(cropNameArg, modeArg)
    self:resetNpcFields(cropName, dryRun)
end
addConsoleCommand("ccoResetNpcFields", "Reset offending NPC fields to cultivated state. Usage: ccoResetNpcFields [CROP|all] [dryrun]", "consoleResetNpcFields", CCO)

function CCO:consoleResetBlocked(modeArg)
    local _, dryRun = parseResetArgs(modeArg, nil)
    self:resetNpcFields(nil, dryRun)
end
addConsoleCommand("ccoResetBlocked", "Reset all currently blocked NPC fields. Usage: ccoResetBlocked [dryrun]", "consoleResetBlocked", CCO)


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
    end
    if t == "reset" or t == "cleanup" or t == "" then
        print("CCO: Cleanup:")
        print("CCO:   ccoResetBlocked dryrun")
        print("CCO:   ccoResetBlocked")
        print("CCO:   ccoResetNpcFields [CROP|all] [dryrun]")
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
