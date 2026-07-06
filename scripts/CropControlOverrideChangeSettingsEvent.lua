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
    if CropControlOverride ~= nil and CropControlOverride.handleMultiplayerEvent ~= nil then
        CropControlOverride:handleMultiplayerEvent(self.operation, self.args or {}, connection)
    end

    if g_server ~= nil then
        g_server:broadcastEvent(self, false, connection)
    end
end
