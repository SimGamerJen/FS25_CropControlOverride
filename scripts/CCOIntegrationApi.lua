-- FS25_CropControlOverride - supported cross-mod integration surface.
--
-- This adapter deliberately sits outside the core CCO implementation so the
-- proven NPC regeneration code can remain unchanged. Consumers must use this
-- API instead of reaching into CropControlOverride private state.

CCO_IntegrationApi = CCO_IntegrationApi or {
    API_VERSION = "1.2",
    BUILD_ID = "2.1.0.0-alpha.10.3-fsm.3",
}

local API = CCO_IntegrationApi
local MISSION_KEY = "cropControlOverrideIntegration"

local function getCco()
    if type(CropControlOverride) == "table" then
        return CropControlOverride
    end
    return nil
end

local function numberOrZero(value)
    return tonumber(value or 0) or 0
end

local function getMissionCount(cco)
    if cco ~= nil and type(cco.getMissionCountForRegeneration) == "function" then
        local ok, value = pcall(cco.getMissionCountForRegeneration, cco)
        if ok then return tonumber(value) end
    end

    if g_missionManager ~= nil and type(g_missionManager.getMissions) == "function" then
        local ok, missions = pcall(g_missionManager.getMissions, g_missionManager)
        if ok and type(missions) == "table" then return #missions end
    end

    return nil
end

local function shallowStatus(lastRun)
    lastRun = type(lastRun) == "table" and lastRun or {}
    return {
        state = lastRun.state,
        phase = lastRun.phase,
        planned = numberOrZero(lastRun.planned),
        npcFields = numberOrZero(lastRun.npcFields),
        queued = numberOrZero(lastRun.queued),
        skipped = numberOrZero(lastRun.skipped),
        removedMissions = numberOrZero(lastRun.removedMissions),
        refillCycles = numberOrZero(lastRun.refillCycles),
        freshContracts = lastRun.freshContracts,
        period = lastRun.period,
        year = lastRun.year,
        alreadyMatching = numberOrZero(lastRun.alreadyMatching),
        needsMutation = numberOrZero(lastRun.needsMutation),
        equivalenceUnresolved = numberOrZero(lastRun.equivalenceUnresolved),
        noOp = lastRun.noOp == true,
        reason = lastRun.reason,
    }
end

local function buildStatus(cco)
    if cco == nil then
        return { state = "unavailable", phase = "unavailable" }
    end

    local coreState = cco._npcMapRegenerationState
    local lastRun = API._lastRun

    if type(coreState) == "table" then
        if type(lastRun) ~= "table" then
            lastRun = { started = true }
            API._lastRun = lastRun
        end

        lastRun.state = "applying"
        lastRun.phase = tostring(coreState.phase or "applying")
        lastRun.queued = numberOrZero(coreState.queued or lastRun.queued)
        lastRun.skipped = numberOrZero(coreState.skipped or lastRun.skipped)
        lastRun.removedMissions = numberOrZero(coreState.removedMissions or lastRun.removedMissions)
        lastRun.refillCycles = numberOrZero(coreState.refillCycles or lastRun.refillCycles)
        lastRun.freshContracts = getMissionCount(cco)
        return shallowStatus(lastRun)
    end

    if type(lastRun) == "table" and lastRun.started == true then
        lastRun.state = "complete"
        lastRun.phase = "complete"
        lastRun.freshContracts = getMissionCount(cco)
        return shallowStatus(lastRun)
    end

    return {
        state = "idle",
        phase = "idle",
        freshContracts = getMissionCount(cco),
        alreadyMatching = 0,
        needsMutation = 0,
        equivalenceUnresolved = 0,
        noOp = false,
    }
end

local function matchesExpected(plan, expected)
    if type(expected) ~= "table" then return true, nil end

    local checks = {
        { "planned", #(plan.actions or {}) },
        { "npcFields", numberOrZero(plan.npcFields) },
        { "period", plan.period },
        { "year", plan.year },
    }

    for _, check in ipairs(checks) do
        local key = check[1]
        local actual = check[2]
        if expected[key] ~= nil and tostring(expected[key]) ~= tostring(actual) then
            return false, ("plan changed since FSM preflight: %s expected=%s actual=%s"):format(
                tostring(key), tostring(expected[key]), tostring(actual))
        end
    end

    return true, nil
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
    if FruitType ~= nil and FruitType.UNKNOWN ~= nil and n == tonumber(FruitType.UNKNOWN) then
        return "UNKNOWN"
    end
    if n == 0 then return "UNKNOWN" end
    if g_fruitTypeManager ~= nil and type(g_fruitTypeManager.getFruitTypeByIndex) == "function" then
        local ok, fruit = pcall(g_fruitTypeManager.getFruitTypeByIndex, g_fruitTypeManager, n)
        if ok and fruit ~= nil and fruit.name ~= nil then return string.upper(tostring(fruit.name)) end
    end
    return tostring(n)
end

local function groundTypeMatchesCultivated(value)
    if value == nil or FieldGroundType == nil or FieldGroundType.CULTIVATED == nil then return nil end
    if tonumber(value) ~= nil and tonumber(FieldGroundType.CULTIVATED) ~= nil then
        return tonumber(value) == tonumber(FieldGroundType.CULTIVATED)
    end
    return string.upper(tostring(value)) == string.upper(tostring(FieldGroundType.CULTIVATED))
end

local function compareActionToLiveState(action)
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

local function buildEquivalenceForPlan(plan)
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
        local equivalent, row = compareActionToLiveState(action)
        if equivalent == true then
            result.alreadyMatching = result.alreadyMatching + 1
        elseif equivalent == false then
            result.needsMutation = result.needsMutation + 1
        else
            result.unresolved = result.unresolved + 1
        end
        table.insert(result.rows, row)
    end

    table.sort(result.rows, function(a, b)
        return numberOrZero(a ~= nil and a.fieldId) < numberOrZero(b ~= nil and b.fieldId)
    end)

    return result, "ok"
end

local function getNpcMapRegenerationEquivalence(_)
    local cco = getCco()
    if cco == nil or type(cco.buildNpcMapRegenerationPlan) ~= "function" then
        return nil, "CCO regeneration plan builder is unavailable."
    end

    local plan, reason = cco:buildNpcMapRegenerationPlan()
    if plan == nil then return nil, "CCO regeneration plan build failed: " .. tostring(reason) end
    return buildEquivalenceForPlan(plan)
end

local function startNpcMapRegeneration(_, expected)
    local cco = getCco()
    if cco == nil then return false, "CCO core is unavailable." end
    if g_currentMission == nil or g_currentMission.getIsServer == nil or not g_currentMission:getIsServer() then
        return false, "NPC map regeneration can only be started by the server/host."
    end
    if type(cco._npcMapRegenerationState) == "table" then
        return false, "NPC map regeneration is already in progress."
    end

    local plan, reason = cco:buildNpcMapRegenerationPlan()
    if plan == nil then
        return false, "CCO regeneration plan build failed: " .. tostring(reason)
    end

    local planned = #(plan.actions or {})
    local excluded = numberOrZero(plan.excluded)
    local unverified = numberOrZero(plan.unverified)
    if planned <= 0 then return false, "CCO regeneration plan contains no actions." end
    if excluded > 0 then
        return false, ("CCO regeneration plan contains %d excluded field(s)."):format(excluded)
    end
    if unverified > 0 then
        return false, ("CCO regeneration plan contains %d unverified action(s)."):format(unverified)
    end

    local matches, mismatch = matchesExpected(plan, expected)
    if not matches then return false, mismatch end

    local equivalence, equivalenceReason = buildEquivalenceForPlan(plan)
    if equivalence == nil then return false, "Equivalence check failed: " .. tostring(equivalenceReason) end
    if numberOrZero(equivalence.unresolved) > 0 then
        return false, ("Equivalence check is unresolved for %d field(s); regeneration was not started."):format(
            numberOrZero(equivalence.unresolved))
    end

    if numberOrZero(equivalence.needsMutation) == 0 then
        API._lastRun = {
            started = true,
            state = "complete",
            phase = "complete",
            planned = planned,
            npcFields = numberOrZero(plan.npcFields),
            queued = 0,
            skipped = 0,
            period = plan.period,
            year = plan.year,
            removedMissions = 0,
            refillCycles = 0,
            freshContracts = getMissionCount(cco),
            alreadyMatching = numberOrZero(equivalence.alreadyMatching),
            needsMutation = 0,
            equivalenceUnresolved = 0,
            noOp = true,
            reason = "already-equivalent",
        }
        if CCO_Debug ~= nil and CCO_Debug.info ~= nil then
            CCO_Debug:info(("integration regeneration no-op planned=%d alreadyMatching=%d needsMutation=0; fields and contracts left unchanged"):format(
                planned, numberOrZero(equivalence.alreadyMatching)))
        end
        return true, buildStatus(cco)
    end

    if type(cco.getActiveContractCount) == "function" then
        local active = numberOrZero(cco:getActiveContractCount())
        if active > 0 then
            return false, ("NPC map regeneration blocked: %d accepted/active contract(s) exist."):format(active)
        end
    end

    -- Arming remains an internal CCO operation. External consumers never receive
    -- or manipulate the private plan/state tables; they only request a guarded
    -- start through this adapter after their own preflight has passed.
    cco._npcMapRegenerationPlan = plan
    local queued, skipped = cco:confirmNpcMapRegeneration()
    queued = numberOrZero(queued)
    skipped = numberOrZero(skipped)

    if queued <= 0 or type(cco._npcMapRegenerationState) ~= "table" then
        cco._npcMapRegenerationPlan = nil
        return false, ("CCO did not enter regeneration lifecycle. queued=%d skipped=%d"):format(queued, skipped)
    end

    API._lastRun = {
        started = true,
        state = "applying",
        phase = tostring(cco._npcMapRegenerationState.phase or "applying"),
        planned = planned,
        npcFields = numberOrZero(plan.npcFields),
        queued = queued,
        skipped = skipped,
        period = plan.period,
        year = plan.year,
        removedMissions = numberOrZero(cco._npcMapRegenerationState.removedMissions),
        refillCycles = numberOrZero(cco._npcMapRegenerationState.refillCycles),
        alreadyMatching = numberOrZero(equivalence.alreadyMatching),
        needsMutation = numberOrZero(equivalence.needsMutation),
        equivalenceUnresolved = numberOrZero(equivalence.unresolved),
        noOp = false,
        reason = "mutation-started",
    }

    return true, buildStatus(cco)
end

local function getNpcMapRegenerationStatus(_)
    return buildStatus(getCco())
end

local function publishApi(mission)
    mission = mission or g_currentMission
    if mission == nil then return false end

    local cco = getCco()
    if cco == nil then return false end

    if API._publishedMission ~= mission then
        API._publishedMission = mission
        API._lastRun = nil
    end

    API.CCO_VERSION = tostring(cco.VERSION or "unknown")
    API.VERSION = API.CCO_VERSION

    API.buildNpcMapRegenerationPlan = type(cco.buildNpcMapRegenerationPlan) == "function"
        and function(_) return cco:buildNpcMapRegenerationPlan() end or nil

    API.confirmNpcMapRegeneration = type(cco.confirmNpcMapRegeneration) == "function"
        and function(_) return cco:confirmNpcMapRegeneration() end or nil

    -- Retained for API 1.0 compatibility. CCO services this lifecycle from its
    -- own mission update hook; FSM polls status and must not advance CCO itself.
    API.updateNpcMapRegeneration = type(cco.updateNpcMapRegeneration) == "function"
        and function(_, dt) return cco:updateNpcMapRegeneration(dt) end or nil

    API.getActiveContractCount = type(cco.getActiveContractCount) == "function"
        and function(_) return cco:getActiveContractCount() end or nil

    API.getContractBoardSummary = type(cco.getContractBoardSummary) == "function"
        and function(_) return cco:getContractBoardSummary() end or nil

    API.getNpcMapRegenerationEquivalence = type(cco.buildNpcMapRegenerationPlan) == "function"
        and getNpcMapRegenerationEquivalence or nil

    API.startNpcMapRegeneration = type(cco.buildNpcMapRegenerationPlan) == "function"
        and type(cco.confirmNpcMapRegeneration) == "function"
        and startNpcMapRegeneration or nil

    API.getNpcMapRegenerationStatus = getNpcMapRegenerationStatus

    mission[MISSION_KEY] = API

    if CCO_Debug ~= nil and CCO_Debug.info ~= nil then
        CCO_Debug:info(("integration API %s published (%s; CCO %s)"):format(
            tostring(API.API_VERSION), tostring(API.BUILD_ID), tostring(API.CCO_VERSION)))
    else
        print(("CCO [INFO] integration API %s published (%s; CCO %s)"):format(
            tostring(API.API_VERSION), tostring(API.BUILD_ID), tostring(API.CCO_VERSION)))
    end

    return true
end

API.publish = publishApi

-- This file is loaded before CropControlOverride.lua through Debug.lua, so
-- publish after the mission has finished loading. By that point the CCO table
-- and NPC regeneration methods have been defined.
if FSBaseMission ~= nil then
    local previousLoadMapFinished = FSBaseMission.loadMapFinished
    function FSBaseMission:loadMapFinished(...)
        local results = nil
        if previousLoadMapFinished ~= nil then
            results = { previousLoadMapFinished(self, ...) }
        end

        local ok, publishError = pcall(publishApi, self)
        if not ok then
            if CCO_Debug ~= nil and CCO_Debug.warn ~= nil then
                CCO_Debug:warn("failed publishing integration API: " .. tostring(publishError))
            else
                print("CCO [WARN] failed publishing integration API: " .. tostring(publishError))
            end
        end

        if results ~= nil then return unpack(results) end
    end
end

return API
