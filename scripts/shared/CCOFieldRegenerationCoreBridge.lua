-- CCO host bridge for the shared field-regeneration engine.
--
-- Loaded before CropControlOverride.lua. It attaches only after the mission map
-- has finished loading, by which point CCO has defined all of its policy,
-- diagnostic and GUI-facing methods. CropControlOverride.lua itself therefore
-- remains byte-for-byte identical to the proven Alpha 10.3 implementation.

CCO_FieldRegenerationCoreBridge = CCO_FieldRegenerationCoreBridge or {}

local Bridge = CCO_FieldRegenerationCoreBridge
Bridge.VERSION = "0.1.0"

local function logInfo(message)
    if CCO_Debug ~= nil and CCO_Debug.info ~= nil then
        CCO_Debug:info(message)
    else
        print("CCO [INFO] " .. tostring(message))
    end
end

local function logWarn(message)
    if CCO_Debug ~= nil and CCO_Debug.warn ~= nil then
        CCO_Debug:warn(message)
    else
        print("CCO [WARN] " .. tostring(message))
    end
end

local function attach()
    if type(FieldRegenerationCore) ~= "table"
        or type(FieldRegenerationCore.attachToCco) ~= "function" then
        return false, "shared FieldRegenerationCore is unavailable"
    end

    if type(CropControlOverride) ~= "table" then
        return false, "CropControlOverride host is unavailable"
    end

    local engine, reason = FieldRegenerationCore.attachToCco(CropControlOverride)
    if type(engine) ~= "table" then
        return false, tostring(reason or "shared core attach failed")
    end

    CropControlOverride.FIELD_REGENERATION_CORE_SOURCE = tostring(FieldRegenerationCore.SOURCE or "unknown")
    CropControlOverride.FIELD_REGENERATION_CORE_API_VERSION = tonumber(FieldRegenerationCore.API_VERSION or 0) or 0

    logInfo(("field-regeneration core bridge %s ready core=%s api=%s source=%s attach=%s"):format(
        tostring(Bridge.VERSION),
        tostring(FieldRegenerationCore.VERSION or "unknown"),
        tostring(FieldRegenerationCore.API_VERSION or "unknown"),
        tostring(FieldRegenerationCore.SOURCE or "unknown"),
        tostring(reason or "attached")))
    return true, reason
end

Bridge.attach = attach

if FSBaseMission ~= nil then
    local previousLoadMapFinished = FSBaseMission.loadMapFinished
    function FSBaseMission:loadMapFinished(...)
        local results = nil
        if previousLoadMapFinished ~= nil then
            results = { previousLoadMapFinished(self, ...) }
        end

        local ok, attached, reason = pcall(attach)
        if not ok then
            logWarn("shared field-regeneration core attach raised an error: " .. tostring(attached))
        elseif attached ~= true then
            logWarn("shared field-regeneration core attach failed: " .. tostring(reason))
        end

        if results ~= nil then return unpack(results) end
    end
end

return Bridge
