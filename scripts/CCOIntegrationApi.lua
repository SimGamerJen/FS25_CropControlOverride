-- FS25_CropControlOverride - supported cross-mod integration surface.
--
-- This adapter deliberately sits outside the core CCO implementation so the
-- proven NPC regeneration code can remain unchanged. Consumers must use this
-- API instead of reaching into CropControlOverride private state.

CCO_IntegrationApi = CCO_IntegrationApi or {
    API_VERSION = "1.1",
    BUILD_ID = "2.1.0.0-alpha.10.3-fsm.2",
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

        return {
            state = lastRun.state,
            phase = lastRun.phase,
            planned = numberOrZero(lastRun.planned),
            npcFields = numberOrZero(lastRun.npcFields),
            queued = lastRun.queued,
            skipped = lastRun.skipped,
            removedMissions = lastRun.removedMissions,
            refillCycles = lastRun.refillCycles,
            freshContracts = lastRun.freshContracts,
            period = lastRun.period,
            year = lastRun.year,
        }
    end

    if type(lastRun) == "table" and lastRun.started == true then
        lastRun.state = "complete"
        lastRun.phase = "complete"
        lastRun.freshContracts = getMissionCount(cco)

        return {
            state = "complete",
            phase = "complete",
            planned = numberOrZero(lastRun.planned),
            npcFields = numberOrZero(lastRun.npcFields),
            queued = numberOrZero(lastRun.queued),
            skipped = numberOrZero(lastRun.skipped),
            removedMissions = numberOrZero(lastRun.removedMissions),
            refillCycles = numberOrZero(lastRun.refillCycles),
            freshContracts = lastRun.freshContracts,
            period = lastRun.period,
            year = lastRun.year,
        }
    end

    return {
        state = "idle",
        phase = "idle",
        freshContracts = getMissionCount(cco),
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

local function startNpcMapRegeneration(_, expected)
    local cco = getCco()
    if cco == nil then return false, "CCO core is unavailable." end
    if g_currentMission == nil or g_currentMission.getIsServer == nil or not g_currentMission:getIsServer() then
        return false, "NPC map regeneration can only be started by the server/host."
    end
    if type(cco._npcMapRegenerationState) == "table" then
        return false, "NPC map regeneration is already in progress."
    end

    if type(cco.getActiveContractCount) == "function" then
        local active = numberOrZero(cco:getActiveContractCount())
        if active > 0 then
            return false, ("NPC map regeneration blocked: %d accepted/active contract(s) exist."):format(active)
        end
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

    API.CCO_VERSION = tostring(cco.VERSION or "unknown")
    API.VERSION = API.CCO_VERSION

    API.buildNpcMapRegenerationPlan = type(cco.buildNpcMapRegenerationPlan) == "function"
        and function(_) return cco:buildNpcMapRegenerationPlan() end or nil

    API.confirmNpcMapRegeneration = type(cco.confirmNpcMapRegeneration) == "function"
        and function(_) return cco:confirmNpcMapRegeneration() end or nil

    -- Retained for API 1.0 compatibility. CCO services this lifecycle from its
    -- own mission update hook; FSM 0.5.1+ polls getNpcMapRegenerationStatus()
    -- and must not advance the CCO timer itself.
    API.updateNpcMapRegeneration = type(cco.updateNpcMapRegeneration) == "function"
        and function(_, dt) return cco:updateNpcMapRegeneration(dt) end or nil

    API.getActiveContractCount = type(cco.getActiveContractCount) == "function"
        and function(_) return cco:getActiveContractCount() end or nil

    API.getContractBoardSummary = type(cco.getContractBoardSummary) == "function"
        and function(_) return cco:getContractBoardSummary() end or nil

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
