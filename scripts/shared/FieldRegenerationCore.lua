-- Shared field-regeneration engine used by Crop Control Override and Farm Sim Manager.
--
-- This module deliberately contains no CCO GUI/config dependencies. Product-specific
-- policy is supplied through callbacks when an engine is created. The GIANTS field,
-- fruit, FieldUpdateTask and MissionManager primitives are shared by both consumers.

FieldRegenerationCore = FieldRegenerationCore or {}

local Core = FieldRegenerationCore
Core.VERSION = "0.1.0"
Core.API_VERSION = 1
Core.SOURCE = "FS25_CropControlOverride"

local DEFAULT_FRUIT_RESEED_WEIGHT = 5
local DEFAULT_LEAVE_CULTIVATED_WEIGHT = 1
local NPC_FARM_ID = 0

local SPECIAL_RESEED_EXCLUSIONS = {
    GRAPE = true,
    OLIVE = true,
    POPLAR = true,
    MEADOW = true,
    OILSEEDRADISH = true,
    RICE = true,
    RICELONGGRAIN = true,
}

local LIFECYCLE_RESEED_CROPS = {
    GRASS = true,
}

local REGEN_PLANTING_KEYS = { "plantingAllowed", "sowingAllowed", "seedingAllowed" }
local REGEN_HARVEST_KEYS = { "isHarvestable", "harvestingAllowed", "harvestAllowed", "harvestable", "isHarvestPeriod" }

local function upper(value)
    return value ~= nil and string.upper(tostring(value)) or value
end

local function numberOrZero(value)
    return tonumber(value or 0) or 0
end

local function clampWeight(value, defaultValue)
    local n = tonumber(value)
    if n == nil then n = tonumber(defaultValue or 0) or 0 end
    n = math.floor(n)
    if n < 0 then n = 0 end
    if n > 5 then n = 5 end
    return n
end

local function iterFruitTypesSorted()
    local list = {}
    if g_fruitTypeManager ~= nil and g_fruitTypeManager.fruitTypes ~= nil then
        for _, fruit in ipairs(g_fruitTypeManager.fruitTypes) do
            if fruit ~= nil and fruit.name ~= nil then table.insert(list, fruit) end
        end
    end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return list
end

local function getCurrentPeriodIndex()
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
    if period ~= nil then return math.floor(period) end

    if env ~= nil then
        local month = tonumber(env.currentMonth or env.month)
        if month ~= nil then return math.floor(month) end
    end

    return nil
end

local function getCalendarYearToken()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then return 0 end
    return tonumber(env.currentYear or env.year or env.currentSeason or 0) or 0
end

local function getFieldSizeHa(field)
    if field == nil then return 0 end

    -- Keep the proven Alpha 10.3 lookup order unchanged for P6.0 behavioural
    -- equivalence. A later core revision can address any field-size edge cases.
    local candidates = {
        field.areaHa,
        field.fieldAreaHa,
        field.fieldArea,
        field.area,
        field.sizeHa,
    }

    for _, value in ipairs(candidates) do
        local n = tonumber(value)
        if n ~= nil and n > 0 then return n end
    end

    if field.fieldDimensions ~= nil and field.fieldDimensions.areaInHa ~= nil then
        local n = tonumber(field.fieldDimensions.areaInHa)
        if n ~= nil and n > 0 then return n end
    end

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

local function getFruitMaximumPlausibleState(ft)
    if ft == nil then return nil end
    local maximum = tonumber(ft.maxHarvestingGrowthState)
    if maximum == nil or maximum < 1 then maximum = tonumber(ft.minHarvestingGrowthState) end
    if maximum == nil or maximum < 1 then
        local count = tonumber(ft.numFoliageStates)
        if count == nil and type(ft.growthStateToName) == "table" then count = #ft.growthStateToName end
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
            local harvestable = isSeasonalPeriodAllowed(plantingEntry, REGEN_HARVEST_KEYS)
            if harvestable and state >= harvestMin and state <= harvestMax then passedHarvestReady = true end
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

        if period ~= currentPeriod and harvestMin ~= nil and harvestMax ~= nil then
            local entry = periods[period]
            local harvestable = isSeasonalPeriodAllowed(entry, REGEN_HARVEST_KEYS)
            if harvestable and state >= harvestMin and state <= harvestMax then passedHarvestReady = true end
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

local function deterministicRegenerationValue(fieldId, period, year, totalWeight)
    if totalWeight == nil or totalWeight <= 0 then return nil end
    local key = tostring(math.floor(tonumber(fieldId) or 1)) .. ":"
        .. tostring(math.floor(tonumber(period) or 0)) .. ":"
        .. tostring(math.floor(tonumber(year) or 0))
    local modulus = 2147483647
    local hash = 104729
    for i = 1, #key do hash = (hash * 131 + string.byte(key, i) + i * 17) % modulus end
    for i = #key, 1, -1 do hash = (hash * 137 + string.byte(key, i) + i * 31) % modulus end
    hash = (hash * 48271 + 1) % modulus
    hash = (hash * 69621 + 17) % modulus
    return (hash % totalWeight) + 1
end

local function isFruitUsableForNpcCandidate(ft)
    if ft == nil or ft.name == nil then return false, "invalid fruit", "blocked" end
    local cropName = upper(ft.name)
    if SPECIAL_RESEED_EXCLUSIONS[cropName] == true then
        return false, "special crop excluded from reseed candidates", "blocked"
    end
    if ft.allowsSeeding == false then return false, "allowsSeeding=false", "blocked" end
    if ft.useForFieldMissions ~= false and ft.useForFieldJob ~= false then
        return true, "engine mission flags ok", "mission"
    end
    if LIFECYCLE_RESEED_CROPS[cropName] == true then
        return true, "lifecycle crop allowed", "lifecycle"
    end
    if ft.useForFieldMissions == false then return false, "useForFieldMissions=false", "blocked" end
    if ft.useForFieldJob == false then return false, "useForFieldJob=false", "blocked" end
    return true, "engine flags ok", "mission"
end

local Engine = {}
Engine.__index = Engine

function Core.create(options)
    options = options or {}
    local engine = setmetatable({}, Engine)
    engine.options = options
    engine.storage = options.storage or {}
    engine.label = tostring(options.label or "FIELD-REGEN")
    return engine
end

function Engine:info(message)
    local fn = self.options.info
    if type(fn) == "function" then fn(message) else print(self.label .. " [INFO] " .. tostring(message)) end
end

function Engine:warn(message)
    local fn = self.options.warn
    if type(fn) == "function" then fn(message) else print(self.label .. " [WARN] " .. tostring(message)) end
end

function Engine:debug(message)
    local fn = self.options.debug
    if type(fn) == "function" then fn(message) end
end

function Engine:isCropAllowed(fieldHa, cropName, fruit)
    local fn = self.options.isCropAllowed
    if type(fn) ~= "function" then return true, "allowed" end
    return fn(fieldHa, cropName, fruit)
end

function Engine:getCropWeight(cropName, fruit)
    local fn = self.options.getCropWeight
    if type(fn) == "function" then
        return clampWeight(fn(cropName, fruit), DEFAULT_FRUIT_RESEED_WEIGHT)
    end
    return DEFAULT_FRUIT_RESEED_WEIGHT
end

function Engine:getLeaveCultivatedWeight()
    local fn = self.options.getLeaveCultivatedWeight
    if type(fn) == "function" then return clampWeight(fn(), DEFAULT_LEAVE_CULTIVATED_WEIGHT) end
    return DEFAULT_LEAVE_CULTIVATED_WEIGHT
end

function Engine:resolveRegenerationGrowthState(ft)
    if ft == nil then return nil, "invalid fruit", false end
    local cropName = upper(ft.name or "")
    local maximum = getFruitMaximumPlausibleState(ft)
    local harvestMin, harvestMax = getFruitHarvestStateRange(ft)
    local period = getCurrentPeriodIndex()
    if period == nil then return nil, "current seasonal period unavailable", false end

    local periods = ft.growthDataSeasonal ~= nil and ft.growthDataSeasonal.periods or nil
    if type(periods) ~= "table" then return nil, "seasonal growth periods unavailable", false end

    local currentEntry = periods[period]
    local currentHarvestable, harvestSource = isSeasonalPeriodAllowed(currentEntry, REGEN_HARVEST_KEYS)

    if LIFECYCLE_RESEED_CROPS[cropName] == true or ft.regrows == true then
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
        local plantingAllowed = isSeasonalPeriodAllowed(periods[plantingPeriod], REGEN_PLANTING_KEYS)
        if plantingAllowed then
            replayedOrigins = replayedOrigins + 1
            local state, steps, replayReason, passedHarvestReady = replaySeasonalGrowthFromPlanting(
                periods, plantingPeriod, period, maximum, harvestMin, harvestMax)
            if state ~= nil then
                local rejected, rejectReason = isRejectedMappedState(ft, state, currentHarvestable)
                local inHarvestRange = harvestMin ~= nil and harvestMax ~= nil and state >= harvestMin and state <= harvestMax
                if not rejected and currentHarvestable == true and harvestMin ~= nil and harvestMax ~= nil and not inHarvestRange then
                    rejected = true
                    rejectReason = "current harvest period but mapped state is outside harvest range"
                end
                if not rejected and passedHarvestReady == true and not inHarvestRange then
                    rejected = true
                    rejectReason = "planting origin already passed a harvest-ready period"
                end
                if not rejected and steps >= 8 and state <= 2 then
                    local plantingNow = isSeasonalPeriodAllowed(currentEntry, REGEN_PLANTING_KEYS)
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
        for reason, count in pairs(rejectionReasons) do table.insert(parts, tostring(reason) .. "=" .. tostring(count)) end
        table.sort(parts)
        return #parts > 0 and table.concat(parts, "|") or "none"
    end

    if #outcomes == 0 then
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

function Engine:buildRegenerationCandidatesForField(field)
    local candidates = {}
    local totalWeight = 0
    if field == nil then return candidates, totalWeight end
    local fieldHa = getFieldSizeHa(field)

    for _, ft in ipairs(iterFruitTypesSorted()) do
        local cropName = upper(ft.name)
        local flagOk = isFruitUsableForNpcCandidate(ft)
        local policyOk = self:isCropAllowed(fieldHa, cropName, ft)
        local weight = self:getCropWeight(cropName, ft)
        if flagOk == true and policyOk == true and weight > 0 then
            local state, stateReason, stateAuthoritative = self:resolveRegenerationGrowthState(ft)
            if state ~= nil then
                totalWeight = totalWeight + weight
                table.insert(candidates, {
                    action = "crop",
                    fruit = ft,
                    cropName = cropName,
                    growthState = state,
                    weight = weight,
                    cumulativeWeight = totalWeight,
                    reason = stateReason,
                    authoritative = stateAuthoritative == true,
                })
            end
        end
    end

    local leaveWeight = self:getLeaveCultivatedWeight()
    if leaveWeight > 0 then
        totalWeight = totalWeight + leaveWeight
        table.insert(candidates, {
            action = "cultivated",
            cropName = "NONE",
            growthState = 0,
            weight = leaveWeight,
            cumulativeWeight = totalWeight,
            reason = "authoritative weighted leave cultivated",
            authoritative = true,
        })
    end

    return candidates, totalWeight
end

function Engine:selectRegenerationActionForField(field, fallbackIndex)
    local candidates, totalWeight = self:buildRegenerationCandidatesForField(field)
    if totalWeight <= 0 then return nil, "no weighted calendar-valid candidates" end
    local fieldId = getFieldId(field, fallbackIndex)
    local pick = deterministicRegenerationValue(fieldId, getCurrentPeriodIndex(), getCalendarYearToken(), totalWeight)
    for _, candidate in ipairs(candidates) do
        if pick <= candidate.cumulativeWeight then return candidate, "deterministic weighted pick=" .. tostring(pick) end
    end
    return nil, "weighted selection failed"
end

function Engine:buildPlan()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return nil, "must run on server/host" end
    if g_fieldManager == nil or g_fieldManager.getFields == nil then return nil, "field manager not ready" end

    local plan = {
        period = getCurrentPeriodIndex(),
        year = getCalendarYearToken(),
        actions = {},
        distribution = {},
        excluded = 0,
        npcFields = 0,
        unverified = 0,
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
                        field = field,
                        fieldId = getFieldId(field, idx),
                        fieldHa = getFieldSizeHa(field),
                        action = candidate.action,
                        fruit = candidate.fruit,
                        cropName = candidate.cropName,
                        growthState = candidate.growthState,
                        reason = candidate.reason,
                        pickReason = pickReason,
                        authoritative = candidate.authoritative == true,
                    }
                    table.insert(plan.actions, action)
                    plan.distribution[action.cropName] = (plan.distribution[action.cropName] or 0) + 1
                    if action.authoritative ~= true then plan.unverified = plan.unverified + 1 end
                else
                    plan.excluded = plan.excluded + 1
                    print(("%s: regeneration excludes field=%s size=%.2fha reason=%s"):format(
                        self.label, tostring(getFieldId(field, idx)), getFieldSizeHa(field), tostring(pickReason)))
                end
            end
        end
    end

    return plan, "ok"
end

local function getFieldState(field)
    if type(field) ~= "table" then return nil end
    if type(field.getFieldState) == "function" then
        local ok, state = pcall(field.getFieldState, field)
        if ok and type(state) == "table" then return state end
    end
    if type(field.fieldState) == "table" then return field.fieldState end
    return nil
end

local function getCurrentFruitIndex(state)
    if type(state) ~= "table" then return nil end
    return tonumber(state.fruitTypeIndex or state.fruitIndex or state.fruitType)
end

local function getCurrentGrowthState(state)
    if type(state) ~= "table" then return nil end
    return tonumber(state.growthState or state.lastGrowthState)
end

local function getCurrentGroundType(state)
    if type(state) ~= "table" then return nil end
    return state.groundType or state.fieldGroundType or state.fieldGroundState
end

local function fruitNameFromIndex(index)
    local n = tonumber(index)
    if n == nil then return "UNKNOWN" end
    if FruitType ~= nil and FruitType.UNKNOWN ~= nil and n == tonumber(FruitType.UNKNOWN) then return "UNKNOWN" end
    if n == 0 then return "UNKNOWN" end
    if g_fruitTypeManager ~= nil and type(g_fruitTypeManager.getFruitTypeByIndex) == "function" then
        local ok, fruit = pcall(g_fruitTypeManager.getFruitTypeByIndex, g_fruitTypeManager, n)
        if ok and fruit ~= nil and fruit.name ~= nil then return upper(fruit.name) end
    end
    return tostring(n)
end

local function groundTypeMatchesCultivated(value)
    if value == nil or FieldGroundType == nil or FieldGroundType.CULTIVATED == nil then return nil end
    if tonumber(value) ~= nil and tonumber(FieldGroundType.CULTIVATED) ~= nil then
        return tonumber(value) == tonumber(FieldGroundType.CULTIVATED)
    end
    return upper(value) == upper(FieldGroundType.CULTIVATED)
end

function Engine:compareActionToLiveState(action)
    local state = getFieldState(action ~= nil and action.field or nil)
    if state == nil then
        return nil, {
            fieldId = action ~= nil and action.fieldId or nil,
            desiredAction = action ~= nil and action.action or nil,
            desiredCrop = action ~= nil and action.cropName or nil,
            desiredGrowthState = action ~= nil and action.growthState or nil,
            reason = "field state unavailable",
        }
    end

    local currentFruitIndex = getCurrentFruitIndex(state)
    local currentGrowthState = getCurrentGrowthState(state)
    local currentGroundType = getCurrentGroundType(state)
    local desiredAction = tostring(action.action or "")
    local desiredFruitIndex = action.fruit ~= nil and tonumber(action.fruit.index) or nil
    local desiredGrowthState = tonumber(action.growthState)

    local row = {
        fieldId = action.fieldId,
        desiredAction = desiredAction,
        desiredCrop = tostring(action.cropName or "UNKNOWN"),
        desiredGrowthState = desiredGrowthState,
        currentFruitIndex = currentFruitIndex,
        currentCrop = fruitNameFromIndex(currentFruitIndex),
        currentGrowthState = currentGrowthState,
        currentGroundType = currentGroundType,
        authoritative = action.authoritative == true,
    }

    if desiredAction == "crop" then
        if currentFruitIndex == nil or currentGrowthState == nil or desiredFruitIndex == nil or desiredGrowthState == nil then
            row.reason = "crop equivalence value unavailable"
            return nil, row
        end
        local fruitMatch = currentFruitIndex == desiredFruitIndex
        local growthMatch = currentGrowthState == desiredGrowthState
        row.equivalent = fruitMatch and growthMatch
        row.reason = row.equivalent and "fruit and growth state match"
            or ("fruitMatch=%s growthMatch=%s"):format(tostring(fruitMatch), tostring(growthMatch))
        return row.equivalent, row
    end

    if desiredAction == "cultivated" then
        local unknownIndex = FruitType ~= nil and FruitType.UNKNOWN ~= nil and tonumber(FruitType.UNKNOWN) or 0
        local fruitUnknown = currentFruitIndex ~= nil and (currentFruitIndex == 0 or currentFruitIndex == unknownIndex)
        local growthZero = currentGrowthState ~= nil and currentGrowthState == 0
        local groundCultivated = groundTypeMatchesCultivated(currentGroundType)
        if currentFruitIndex == nil or currentGrowthState == nil or groundCultivated == nil then
            row.reason = "cultivated equivalence value unavailable"
            return nil, row
        end
        row.equivalent = fruitUnknown and growthZero and groundCultivated == true
        row.reason = row.equivalent and "unknown fruit, growth 0 and cultivated ground match"
            or ("fruitUnknown=%s growthZero=%s groundCultivated=%s"):format(
                tostring(fruitUnknown), tostring(growthZero), tostring(groundCultivated))
        return row.equivalent, row
    end

    row.reason = "unsupported regeneration action"
    return nil, row
end

function Engine:buildEquivalenceForPlan(plan)
    if type(plan) ~= "table" then return nil, "regeneration plan unavailable" end
    local result = {
        period = plan.period,
        year = plan.year,
        npcFields = numberOrZero(plan.npcFields),
        planned = #(plan.actions or {}),
        excluded = numberOrZero(plan.excluded),
        unverified = numberOrZero(plan.unverified),
        alreadyMatching = 0,
        needsMutation = 0,
        unresolved = 0,
        rows = {},
    }

    for _, action in ipairs(plan.actions or {}) do
        local equivalent, row = self:compareActionToLiveState(action)
        if equivalent == true then result.alreadyMatching = result.alreadyMatching + 1
        elseif equivalent == false then result.needsMutation = result.needsMutation + 1
        else result.unresolved = result.unresolved + 1 end
        table.insert(result.rows, row)
    end

    table.sort(result.rows, function(a, b)
        return numberOrZero(a ~= nil and a.fieldId) < numberOrZero(b ~= nil and b.fieldId)
    end)
    return result, "ok"
end

function Engine:getEquivalence()
    local plan, reason = self:buildPlan()
    if plan == nil then return nil, reason end
    return self:buildEquivalenceForPlan(plan)
end

function Engine:getActiveContractCount()
    if g_missionManager == nil then return 0 end
    local count = 0
    for _, mission in ipairs(g_missionManager:getMissions() or {}) do
        local wasStarted = false
        if mission.getWasStarted ~= nil then
            local ok, value = pcall(mission.getWasStarted, mission)
            wasStarted = ok and value == true
        end
        if wasStarted or mission.farmId ~= nil or mission.activeMissionId ~= nil then count = count + 1 end
    end
    return count
end

function Engine:purgeAvailableContractsForRegeneration()
    if g_missionManager == nil then return 0, "mission manager unavailable" end
    if self:getActiveContractCount() > 0 then return 0, "one or more accepted/active contracts exist" end

    g_missionManager.missionGenerationInProgress = false
    if g_missionManager.generationTimer ~= nil then g_missionManager.generationTimer = 2147483647 end

    local missions = {}
    for _, mission in ipairs(g_missionManager:getMissions() or {}) do table.insert(missions, mission) end

    local removed = 0
    for _, mission in ipairs(missions) do
        local ok, err = pcall(function() mission:delete() end)
        if ok then removed = removed + 1 else self:warn("failed deleting stale available contract: " .. tostring(err)) end
    end
    return removed, "ok"
end

function Engine:getMissionCountForRegeneration()
    if g_missionManager == nil then return 0 end
    return #(g_missionManager:getMissions() or {})
end

function Engine:refreshRegeneratedFieldStates(state)
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
            self:warn("failed refreshing regenerated field state: " .. tostring(err))
        end
    end
    self:info(("refreshed regenerated field-state caches refreshed=%d failed=%d"):format(refreshed, failed))
    return refreshed, failed
end

function Engine:startFreshMissionGenerationAfterRegeneration()
    if g_missionManager == nil or g_missionManager.startMissionGeneration == nil then return false end
    if g_missionManager.missionGenerationInProgress == true then return false end
    g_missionManager:startMissionGeneration()
    return true
end

function Engine:setFieldCultivated(field)
    if field == nil or field.farmland == nil then return false end
    if FieldUpdateTask == nil then
        self:warn("FieldUpdateTask is unavailable; cannot reset field " .. tostring(getFieldId(field)))
        return false
    end
    local polygon = field.getDensityMapPolygon ~= nil and field:getDensityMapPolygon() or nil
    if polygon == nil then
        self:warn("No density map polygon for field " .. tostring(getFieldId(field)) .. "; skipping")
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
    task:enqueue(false)
    return true
end

function Engine:setFieldReseeded(field, fruit, growthState)
    if field == nil or field.farmland == nil then return false, "no field" end
    if fruit == nil or fruit.index == nil then return false, "no fruit/index" end
    if FieldUpdateTask == nil then return false, "FieldUpdateTask unavailable" end
    local polygon = field.getDensityMapPolygon ~= nil and field:getDensityMapPolygon() or nil
    if polygon == nil then return false, "no density map polygon" end
    local fruitIndex = tonumber(fruit.index)
    if fruitIndex == nil then return false, "invalid fruit index" end
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
    if groundType ~= nil and task.setGroundType ~= nil then task:setGroundType(groundType) end
    if task.setGroundAngle ~= nil then task:setGroundAngle(0) end
    if task.setWeedState ~= nil then task:setWeedState(0) end
    if task.setStoneLevel ~= nil then task:setStoneLevel(0) end
    if task.resetDisplacement ~= nil then task:resetDisplacement() end
    if task.clearTireTracks ~= nil then task:clearTireTracks() end
    task:enqueue(false)
    return true, "queued"
end

function Engine:finishNpcMapRegenerationMissionRefill(state, reason)
    local audit = self.options.auditMissions
    if type(audit) == "function" then audit(state) end
    local missions = self:getMissionCountForRegeneration()
    local msg = ("%s: NPC map regeneration complete. queued=%d skipped=%d staleContractsRemoved=%d freshContracts=%d refillCycles=%d reason=%s"):format(
        self.label, tonumber(state.queued or 0), tonumber(state.skipped or 0), tonumber(state.removedMissions or 0),
        tonumber(missions or 0), tonumber(state.refillCycles or 0), tostring(reason or "complete"))
    print(msg)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, msg)
    end
    self.storage._npcMapRegenerationState = nil
end

function Engine:update(dt)
    local state = self.storage._npcMapRegenerationState
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
            self:warn("field regeneration completed but fresh mission generation could not be started")
            self:finishNpcMapRegenerationMissionRefill(state, "mission-generation-start-failed")
            return
        end
        state.refillCycles = 1
        self:info(("field regeneration settle delay complete; starting contract refill after removing %d stale contract(s); initialMissions=%d"):format(
            tonumber(state.removedMissions or 0), tonumber(state.lastMissionCount or 0)))
        return
    end

    if state.phase ~= "refillingContracts" then return end
    if g_missionManager == nil then
        self:finishNpcMapRegenerationMissionRefill(state, "mission-manager-unavailable")
        return
    end
    if g_missionManager.missionGenerationInProgress == true then return end

    local missionCount = self:getMissionCountForRegeneration()
    local previousCount = tonumber(state.lastMissionCount or 0)
    local maxMissions = tonumber((MissionManager ~= nil and MissionManager.MAX_MISSIONS) or 100)
    local added = missionCount - previousCount
    local requiredEmptyCycles = tonumber(state.requiredEmptyCycles or 5)
    if added > 0 then state.emptyCycleStreak = 0
    else state.emptyCycleStreak = tonumber(state.emptyCycleStreak or 0) + 1 end

    self:info(("contract refill cycle=%d missions=%d added=%d emptyStreak=%d/%d"):format(
        tonumber(state.refillCycles or 0), missionCount, added,
        tonumber(state.emptyCycleStreak or 0), requiredEmptyCycles))

    if missionCount >= maxMissions then
        self:finishNpcMapRegenerationMissionRefill(state, "mission-limit-reached")
        return
    end
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

function Engine:confirm()
    local plan = self.storage._npcMapRegenerationPlan
    if plan == nil then
        print(self.label .. ": no armed regeneration plan. Run the regeneration preview first.")
        return 0, 0
    end
    if self.storage._npcMapRegenerationState ~= nil then
        print(self.label .. ": NPC map regeneration is already in progress.")
        return 0, 0
    end
    if tonumber(plan.unverified or 0) > 0 then
        print(("%s: regeneration confirmation blocked: %d planned field action(s) use unverified growth states."):format(
            self.label, tonumber(plan.unverified or 0)))
        return 0, 0
    end
    if plan.period ~= getCurrentPeriodIndex() or plan.year ~= getCalendarYearToken() then
        self.storage._npcMapRegenerationPlan = nil
        print(self.label .. ": regeneration plan expired because the calendar changed. Run a new dry-run.")
        return 0, 0
    end

    local activeContracts = self:getActiveContractCount()
    if activeContracts > 0 then
        print(("%s: regeneration refused because %d accepted/active contract(s) exist. Complete or cancel them, then run a new dry-run."):format(
            self.label, activeContracts))
        return 0, 0
    end

    local removedMissions, purgeReason = self:purgeAvailableContractsForRegeneration()
    if purgeReason ~= "ok" then
        print(self.label .. ": regeneration refused: " .. tostring(purgeReason))
        return 0, 0
    end
    self:info(("removed %d stale available contract(s) before full NPC map regeneration"):format(removedMissions))

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
            self:info(("regenerate queued field=%s action=%s crop=%s growthState=%s"):format(
                tostring(action.fieldId), tostring(action.action), tostring(action.cropName), tostring(action.growthState)))
        else
            skipped = skipped + 1
            self:warn(("regenerate skipped field=%s action=%s crop=%s reason=%s"):format(
                tostring(action.fieldId), tostring(action.action), tostring(action.cropName), tostring(reason)))
        end
    end
    self.storage._npcMapRegenerationPlan = nil
    self.storage._npcMapRegenerationState = {
        phase = "waitingForFieldTasks",
        elapsedMs = 0,
        queued = queued,
        skipped = skipped,
        removedMissions = removedMissions,
        fields = regeneratedFields,
        actions = plan.actions,
    }
    print(("%s: NPC map regeneration queued. queued=%d skipped=%d staleContractsRemoved=%d; waiting for field tasks before fresh mission generation."):format(
        self.label, queued, skipped, removedMissions))
    return queued, skipped
end

function Core.attachToCco(cco)
    if type(cco) ~= "table" then return nil, "CCO host unavailable" end
    if type(cco._fieldRegenerationCore) == "table" then return cco._fieldRegenerationCore, "already-attached" end

    local engine = Core.create({
        label = "CCO",
        storage = cco,
        isCropAllowed = function(fieldHa, cropName)
            if type(cco.isNpcCropAllowedForField) == "function" then
                return cco:isNpcCropAllowedForField(fieldHa, cropName)
            end
            return true, "allowed"
        end,
        getCropWeight = function(cropName)
            local rule = cco._rules ~= nil and cco._rules[cropName] or nil
            return rule ~= nil and rule.reseedWeight or DEFAULT_FRUIT_RESEED_WEIGHT
        end,
        getLeaveCultivatedWeight = function()
            if type(cco.getReseedWeights) == "function" then
                local weights = cco:getReseedWeights()
                return weights ~= nil and weights.leaveCultivated or DEFAULT_LEAVE_CULTIVATED_WEIGHT
            end
            return DEFAULT_LEAVE_CULTIVATED_WEIGHT
        end,
        info = function(message)
            if CCO_Debug ~= nil and CCO_Debug.info ~= nil then CCO_Debug:info(message)
            else print("CCO [INFO] " .. tostring(message)) end
        end,
        warn = function(message)
            if CCO_Debug ~= nil and CCO_Debug.warn ~= nil then CCO_Debug:warn(message)
            else print("CCO [WARN] " .. tostring(message)) end
        end,
        debug = function(message)
            if CCO_Debug ~= nil and CCO_Debug.debug ~= nil then CCO_Debug:debug(message) end
        end,
        auditMissions = function(state)
            if type(cco.auditNpcMapRegenerationMissions) == "function" then cco:auditNpcMapRegenerationMissions(state) end
        end,
    })

    cco._fieldRegenerationCore = engine
    cco.FIELD_REGENERATION_CORE_VERSION = Core.VERSION

    -- Keep all existing CCO call sites and integration API names intact. Runtime
    -- behaviour is now delegated to the shared engine while the legacy Alpha
    -- 10.3 implementations remain in-file as a temporary fallback during P6.0.
    cco.resolveRegenerationGrowthState = function(_, fruit) return engine:resolveRegenerationGrowthState(fruit) end
    cco.buildRegenerationCandidatesForField = function(_, field) return engine:buildRegenerationCandidatesForField(field) end
    cco.selectRegenerationActionForField = function(_, field, fallbackIndex) return engine:selectRegenerationActionForField(field, fallbackIndex) end
    cco.buildNpcMapRegenerationPlan = function(_) return engine:buildPlan() end
    cco.getNpcMapRegenerationEquivalence = function(_) return engine:getEquivalence() end
    cco.getActiveContractCount = function(_) return engine:getActiveContractCount() end
    cco.purgeAvailableContractsForRegeneration = function(_) return engine:purgeAvailableContractsForRegeneration() end
    cco.getMissionCountForRegeneration = function(_) return engine:getMissionCountForRegeneration() end
    cco.refreshRegeneratedFieldStates = function(_, state) return engine:refreshRegeneratedFieldStates(state) end
    cco.startFreshMissionGenerationAfterRegeneration = function(_) return engine:startFreshMissionGenerationAfterRegeneration() end
    cco.finishNpcMapRegenerationMissionRefill = function(_, state, reason) return engine:finishNpcMapRegenerationMissionRefill(state, reason) end
    cco.updateNpcMapRegeneration = function(_, dt) return engine:update(dt) end
    cco.confirmNpcMapRegeneration = function(_) return engine:confirm() end
    cco.setFieldCultivated = function(_, field) return engine:setFieldCultivated(field) end
    cco.setFieldReseeded = function(_, field, fruit, growthState) return engine:setFieldReseeded(field, fruit, growthState) end

    if CCO_Debug ~= nil and CCO_Debug.info ~= nil then
        CCO_Debug:info(("shared field-regeneration core %s attached"):format(tostring(Core.VERSION)))
    end
    return engine, "attached"
end

return Core
