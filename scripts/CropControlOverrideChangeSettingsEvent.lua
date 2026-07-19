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
    local resultOk, resultMessage, resultExtra, resultExtra2 = nil, nil, nil, nil

    if CropControlOverride ~= nil and CropControlOverride.handleMultiplayerEvent ~= nil then
        resultOk, resultMessage, resultExtra, resultExtra2 = CropControlOverride:handleMultiplayerEvent(operation, self.args or {}, connection)
    end

    if g_server ~= nil then
        -- requestSettings is answered directly to the requesting connection by
        -- CropControlOverride:sendSettingsSnapshotToClient(). syncSettings is
        -- already a server-authoritative snapshot, so do not rebroadcast it from
        -- clients/receivers and create loops.
        if operation ~= "requestSettings" and operation ~= "syncSettings" and operation ~= "adminStatus" and operation ~= "operationResult" then
            local returnsOperationResult = operation == "applyRule"
                or operation == "resetBlockedDryRun"
                or operation == "resetBlocked"
            if returnsOperationResult and connection ~= nil then
                -- Dedicated-server rule edits are asynchronous from the client's
                -- point of view. Return the authoritative validation result to the
                -- requesting client. A rejected APPLY must not be followed by an
                -- unchanged snapshot because that would discard the staged rule
                -- before the client can offer FORCE APPLY.
                local changesServerState = operation == "applyRule" or operation == "resetBlocked"
                if resultOk == true and changesServerState and CropControlOverride ~= nil and CropControlOverride.sendSettingsSnapshotToClient ~= nil then
                    CropControlOverride:sendSettingsSnapshotToClient(nil, operation)
                end
                if CropControlOverride ~= nil and CropControlOverride.sendOperationResultToClient ~= nil then
                    local canForce = operation == "applyRule" and resultExtra == true
                    local value1 = operation == "applyRule" and "" or resultExtra
                    CropControlOverride:sendOperationResultToClient(connection, operation, resultOk == true, resultMessage, canForce, value1, resultExtra2)
                end
            elseif CropControlOverride ~= nil and CropControlOverride.sendSettingsSnapshotToClient ~= nil then
                CropControlOverride:sendSettingsSnapshotToClient(nil, operation)
            else
                g_server:broadcastEvent(self, false)
            end
        end
    end
end
