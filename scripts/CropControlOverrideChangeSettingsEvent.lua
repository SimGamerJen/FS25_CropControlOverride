CropControlOverrideChangeSettingsEvent = {}
CropControlOverrideChangeSettingsEvent_mt = Class(CropControlOverrideChangeSettingsEvent, Event)
InitEventClass(CropControlOverrideChangeSettingsEvent, "CropControlOverrideChangeSettingsEvent")

function CropControlOverrideChangeSettingsEvent.emptyNew()
    return Event.new(CropControlOverrideChangeSettingsEvent_mt)
end

function CropControlOverrideChangeSettingsEvent.new(operation, a, b, c, d, e, f, g)
    local self = CropControlOverrideChangeSettingsEvent.emptyNew()
    self.operation = tostring(operation or "")
    self.args = {
        tostring(a or ""),
        tostring(b or ""),
        tostring(c or ""),
        tostring(d or ""),
        tostring(e or ""),
        tostring(f or ""),
        tostring(g or ""),
    }
    return self
end

function CropControlOverrideChangeSettingsEvent:readStream(streamId, connection)
    self.operation = streamReadString(streamId)
    self.args = {}
    for i = 1, 7 do
        self.args[i] = streamReadString(streamId)
    end
    self:run(connection)
end

function CropControlOverrideChangeSettingsEvent:writeStream(streamId, connection)
    streamWriteString(streamId, tostring(self.operation or ""))
    local args = self.args or {}
    for i = 1, 7 do
        streamWriteString(streamId, tostring(args[i] or ""))
    end
end

function CropControlOverrideChangeSettingsEvent:run(connection)
    local operation = tostring(self.operation or "")

    if CropControlOverride ~= nil and CropControlOverride.handleMultiplayerEvent ~= nil then
        CropControlOverride:handleMultiplayerEvent(operation, self.args or {}, connection)
    end

    if g_server ~= nil then
        -- requestSettings is answered directly to the requesting connection by
        -- CropControlOverride:sendSettingsSnapshotToClient(). syncSettings is
        -- already a server-authoritative snapshot, so do not rebroadcast it from
        -- clients/receivers and create loops.
        if operation ~= "requestSettings" and operation ~= "syncSettings" and operation ~= "adminStatus" then
            if CropControlOverride ~= nil and CropControlOverride.sendSettingsSnapshotToClient ~= nil then
                CropControlOverride:sendSettingsSnapshotToClient(nil, operation)
            else
                g_server:broadcastEvent(self, false)
            end
        end
    end
end
