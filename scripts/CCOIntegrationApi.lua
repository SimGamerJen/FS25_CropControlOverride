-- FS25_CropControlOverride - supported cross-mod integration surface.
--
-- Compatibility lineage:
--   integration/fsm-bootstrap-alpha10.3
--   refactor/field-regeneration-core-alpha10.3
--
-- Farm Sim Manager's production bootstrap now vendors the shared field core
-- directly and does not require CCO to be loaded. This API remains a protected
-- CCO compatibility surface for FSMBootstrap diagnostics and other consumers.
--
-- Consumers must use this adapter instead of reading/writing CCO private state.

CCO_IntegrationApi = CCO_IntegrationApi or {
    API_VERSION = "1.2",
    BUILD_ID = "2.1.0.0-alpha.18.6.3.2-fsm-api1.2",
}

local API = CCO_IntegrationApi
local MISSION_KEY = "cropControlOverrideIntegration"

local function getCco()
    if type(CropControlOverride) == "table" then return CropControlOverride end
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
        fieldCoreVersion = lastRun.fieldCoreVersion,
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
        lastRun.fieldCoreVersion = cco.FIELD_REGENERATION_CORE_VERSION
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
        fieldCoreVersion = cco.FIELD_REGENERATION_CORE_VERSION,
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
        local key, actual = check[1], check[2]
        if expected[key] ~= nil and tostring(expected[key]) ~= tostring(actual) then
            return false, ("plan changed since integration preflight: %s expected=%s actual=%s"):format(
                tostring(key), tostring(expected[key]), tostring(actual))
        end
    end
    return true, nil
end

local function getNpcMapRegenerationEquivalence(_)
    local cco = getCco()
    if cco == nil then return nil, "CCO core is unavailable." end

    -- Newer builds may expose the shared-core equivalence method directly.
    if type(cco.getNpcMapRegenerationEquivalence) == "function" then
        return cco:getNpcMapRegenerationEquivalence()
    end

    -- Do not invent equivalence from private field state. The integration
    -- contract is fail-closed when the capability is not present.
    return nil, "Field-regeneration equivalence capability is unavailable in this CCO build."
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
    if type(cco.buildNpcMapRegenerationPlan) ~= "function"
        or type(cco.confirmNpcMapRegeneration) ~= "function" then
        return false, "CCO regeneration capability is unavailable."
    end

    local plan, reason = cco:buildNpcMapRegenerationPlan()
    if plan == nil then return false, "CCO regeneration plan build failed: " .. tostring(reason) end

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

    if type(cco.getActiveContractCount) == "function" then
        local active = numberOrZero(cco:getActiveContractCount())
        if active > 0 then
            return false, ("NPC map regeneration blocked: %d accepted/active contract(s) exist."):format(active)
        end
    end

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
        noOp = false,
        reason = "mutation-started",
        fieldCoreVersion = cco.FIELD_REGENERATION_CORE_VERSION,
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
    API.FIELD_REGENERATION_CORE_VERSION = cco.FIELD_REGENERATION_CORE_VERSION
    API.FIELD_REGENERATION_CORE_API_VERSION = cco.FIELD_REGENERATION_CORE_API_VERSION
    API.FIELD_REGENERATION_CORE_SOURCE = cco.FIELD_REGENERATION_CORE_SOURCE

    API.buildNpcMapRegenerationPlan = type(cco.buildNpcMapRegenerationPlan) == "function"
        and function(_) return cco:buildNpcMapRegenerationPlan() end or nil
    API.confirmNpcMapRegeneration = type(cco.confirmNpcMapRegeneration) == "function"
        and function(_) return cco:confirmNpcMapRegeneration() end or nil
    API.updateNpcMapRegeneration = type(cco.updateNpcMapRegeneration) == "function"
        and function(_, dt) return cco:updateNpcMapRegeneration(dt) end or nil
    API.getActiveContractCount = type(cco.getActiveContractCount) == "function"
        and function(_) return cco:getActiveContractCount() end or nil
    API.getContractBoardSummary = type(cco.getContractBoardSummary) == "function"
        and function(_) return cco:getContractBoardSummary() end or nil
    API.getNpcMapRegenerationEquivalence = getNpcMapRegenerationEquivalence
    API.startNpcMapRegeneration = startNpcMapRegeneration
    API.getNpcMapRegenerationStatus = getNpcMapRegenerationStatus

    mission[MISSION_KEY] = API

    local message = ("integration API %s published (%s; CCO %s)"):format(
        tostring(API.API_VERSION), tostring(API.BUILD_ID), tostring(API.CCO_VERSION))
    if CCO_Debug ~= nil and CCO_Debug.info ~= nil then CCO_Debug:info(message)
    else print("CCO [INFO] " .. message) end
    return true
end

API.publish = publishApi

-- CropControlOverride.lua is loaded before this source file in Alpha 18.
-- Publish after the mission map has fully loaded.
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
