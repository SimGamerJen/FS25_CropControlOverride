-- FS25_CropControlOverride - supported cross-mod integration surface.
--
-- This adapter deliberately sits outside the core CCO implementation so the
-- proven NPC regeneration code can remain unchanged. Consumers must use this
-- API instead of reaching into CropControlOverride private state.

CCO_IntegrationApi = CCO_IntegrationApi or {
    API_VERSION = "1.0",
    BUILD_ID = "2.1.0.0-alpha.10.3-fsm.1",
}

local API = CCO_IntegrationApi
local MISSION_KEY = "cropControlOverrideIntegration"

local function getCco()
    if type(CropControlOverride) == "table" then
        return CropControlOverride
    end
    return nil
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

    API.updateNpcMapRegeneration = type(cco.updateNpcMapRegeneration) == "function"
        and function(_, dt) return cco:updateNpcMapRegeneration(dt) end or nil

    API.getActiveContractCount = type(cco.getActiveContractCount) == "function"
        and function(_) return cco:getActiveContractCount() end or nil

    API.getContractBoardSummary = type(cco.getContractBoardSummary) == "function"
        and function(_) return cco:getContractBoardSummary() end or nil

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
-- and NPC regeneration methods have been defined. The wrapper is intentionally
-- read-only with respect to CCO state; it only installs the supported adapter.
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
