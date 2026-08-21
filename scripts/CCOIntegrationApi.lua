-- FS25_CropControlOverride - supported cross-mod integration surface.
--
-- P6.0 keeps the public API 1.2 contract unchanged, but the field-regeneration
-- implementation behind the CCO host methods is now supplied by the shared
-- FieldRegenerationCore. Consumers still use this API and never touch CCO or
-- shared-core private state directly.

CCO_IntegrationApi = CCO_IntegrationApi or {
    API_VERSION = "1.2",
    BUILD_ID = "2.1.0.0-alpha.10.3-fsm.4-core0.1",
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
        fieldCoreVersion = lastRun.fieldCoreVersion or API.FIELD_REGENERATION_CORE_VERSION,
    }
end

local function buildStatus(cco)
    if cco == nil then return { state = "unavailable", phase = "unavailable" } end

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
        lastRun.fieldCoreVersion = cco.FIELD_REGENERATION_CORE_VERSION
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
            return false, ("plan changed since FSM preflight: %s expected=%s actual=%s"):format(
                tostring(key), tostring(expected[key]), tostring(actual))
        end
    end
    return true, nil
end

local function getNpcMapRegenerationEquivalence(_)
    local cco = getCco()
    if cco == nil or type(cco.getNpcMapRegenerationEquivalence) ~= "function" then
        return nil, "Shared field-regeneration equivalence capability is unavailable."
    end
    return cco:getNpcMapRegenerationEquivalence()
end

local function startNpcMapRegeneration(_, expected)
    local cco = getCco()
    if cco == nil then return false, "CCO core is unavailable." end
    if type(cco._fieldRegenerationCore) ~= "table" then
        return false, "Shared field-regeneration core is not attached; refusing legacy fallback for P6.0."
    end
    if g_currentMission == nil or g_currentMission.getIsServer == nil or not g_currentMission:getIsServer() then
        return false, "NPC map regeneration can only be started by the server/host."
    end
    if type(cco._npcMapRegenerationState) == "table" then
        return false, "NPC map regeneration is already in progress."
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

    -- Equivalence is now owned by the shared field core. It deliberately builds
    -- the same deterministic target independently so a no-op decision is not
    -- based on stale adapter-local comparison logic.
    local equivalence, equivalenceReason = cco:getNpcMapRegenerationEquivalence()
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
            fieldCoreVersion = cco.FIELD_REGENERATION_CORE_VERSION,
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

    -- The API still owns the guarded start request for compatibility with FSM
    -- 0.5.2. The actual confirm/write/cache/contract lifecycle is delegated by
    -- CCO to FieldRegenerationCore 0.1.0.
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

    -- P6.0 must prove the extracted core itself. Never silently publish an API
    -- backed by the legacy in-file implementations if attachment failed.
    if type(cco._fieldRegenerationCore) ~= "table" then
        error("shared FieldRegenerationCore did not attach to CCO before integration publication")
    end

    if API._publishedMission ~= mission then
        API._publishedMission = mission
        API._lastRun = nil
    end

    API.CCO_VERSION = tostring(cco.VERSION or "unknown")
    API.VERSION = API.CCO_VERSION
    API.FIELD_REGENERATION_CORE_VERSION = tostring(cco.FIELD_REGENERATION_CORE_VERSION or "unknown")
    API.FIELD_REGENERATION_CORE_API_VERSION = tonumber(cco.FIELD_REGENERATION_CORE_API_VERSION or 0) or 0
    API.FIELD_REGENERATION_CORE_SOURCE = tostring(cco.FIELD_REGENERATION_CORE_SOURCE or "unknown")

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
    API.getNpcMapRegenerationEquivalence = type(cco.getNpcMapRegenerationEquivalence) == "function"
        and getNpcMapRegenerationEquivalence or nil
    API.startNpcMapRegeneration = type(cco.buildNpcMapRegenerationPlan) == "function"
        and type(cco.confirmNpcMapRegeneration) == "function"
        and type(cco.getNpcMapRegenerationEquivalence) == "function"
        and startNpcMapRegeneration or nil
    API.getNpcMapRegenerationStatus = getNpcMapRegenerationStatus

    mission[MISSION_KEY] = API

    local message = ("integration API %s published (%s; CCO %s; fieldCore %s api=%s source=%s)"):format(
        tostring(API.API_VERSION), tostring(API.BUILD_ID), tostring(API.CCO_VERSION),
        tostring(API.FIELD_REGENERATION_CORE_VERSION), tostring(API.FIELD_REGENERATION_CORE_API_VERSION),
        tostring(API.FIELD_REGENERATION_CORE_SOURCE))
    if CCO_Debug ~= nil and CCO_Debug.info ~= nil then CCO_Debug:info(message)
    else print("CCO [INFO] " .. message) end
    return true
end

API.publish = publishApi

-- Debug.lua loads the shared core bridge before this adapter. Therefore the
-- bridge's loadMapFinished wrapper runs first and attaches the engine; this
-- wrapper publishes only after that attachment has succeeded.
if FSBaseMission ~= nil then
    local previousLoadMapFinished = FSBaseMission.loadMapFinished
    function FSBaseMission:loadMapFinished(...)
        local results = nil
        if previousLoadMapFinished ~= nil then results = { previousLoadMapFinished(self, ...) } end

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
