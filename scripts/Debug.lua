-- FS25_CropControlOverride - Debug helpers
-- Levels, write-through file logging, and robust console commands.

Debug = {
    enabled     = true,
    level       = "INFO",   -- DEBUG < INFO < WARN < ERROR
    prefix      = "CCO",
    buffer      = {},
    bufferSize  = 0,
    flushEvery  = 1,        -- write-through on every message
    logFilePath = nil,
}

local LEVELS = { DEBUG=1, INFO=2, WARN=3, ERROR=4 }
local function levelOK(cur, want) return LEVELS[want] >= LEVELS[cur] end

local function ensureFolder(pathOrFile)
    local dir = pathOrFile:match("^(.*)[/\\][^/\\]+$") or pathOrFile
    if not dir or dir == "" then return end
    local acc = ""
    for part in string.gmatch(dir, "[^/\\]+") do
        acc = acc .. part .. "/"
        if createFolder then createFolder(acc) end
    end
end

function Debug:setLevel(newLevel)
    newLevel = string.upper(newLevel or "INFO")
    if LEVELS[newLevel] then
        self.level = newLevel
        print(("%s: log level set to %s"):format(self.prefix, self.level))
    else
        print(("%s: invalid level '%s' (use DEBUG|INFO|WARN|ERROR)"):format(self.prefix, tostring(newLevel)))
    end
end

function Debug:setLogFile(path)
    self.logFilePath = path
    ensureFolder(path)
    local ok, f = pcall(io.open, path, "w")
    if ok and f then
        f:write(("%s: log started\n"):format(self.prefix))
        f:close()
        print(("%s: log file created at %s"):format(self.prefix, tostring(path)))
    else
        print(("%s: WARNING could not open log file for writing: %s"):format(self.prefix, tostring(path)))
    end
    self.buffer, self.bufferSize = {}, 0
end

local function fmt(prefix, lvl, msg)
    return ("%s [%s] %s"):format(prefix, lvl, tostring(msg))
end

function Debug:_write(line, forceFlush)
    table.insert(self.buffer, line)
    self.bufferSize = self.bufferSize + #line + 1
    print(line)
    if self.logFilePath ~= nil and (forceFlush or self.bufferSize >= self.flushEvery) then
        self:flush(false)
    end
end

function Debug:flush(startFresh)
    if not self.logFilePath then return end
    local ok, f = pcall(io.open, self.logFilePath, "w")
    if not ok or not f then
        print(("%s: WARNING could not open log file for writing: %s"):format(self.prefix, tostring(self.logFilePath)))
        return
    end
    if startFresh then f:write(("%s: log started\n"):format(self.prefix)) end
    for i=1, #self.buffer do f:write(self.buffer[i]); f:write("\n") end
    f:close()
end

function Debug:debug(msg) if self.enabled and levelOK(self.level,"DEBUG") then self:_write(fmt(self.prefix,"DEBUG",msg), false) end end
function Debug:info(msg)  if self.enabled and levelOK(self.level,"INFO")  then self:_write(fmt(self.prefix,"INFO", msg), false) end end
function Debug:warn(msg)  if self.enabled and levelOK(self.level,"WARN")  then self:_write(fmt(self.prefix,"WARN", msg), true)  end end
function Debug:error(msg) self:_write(fmt(self.prefix,"ERROR",msg), true) end
function Debug:log(msg) self:info(msg) end

function Debug:logTable(tbl, label)
    if not self.enabled or not levelOK(self.level,"DEBUG") then return end
    label = label or "table"; self:debug("dumping "..label)
    if type(tbl) ~= "table" then self:debug("(not a table)"); return end
    for k, v in pairs(tbl) do self:debug(("%s = %s"):format(tostring(k), tostring(v))) end
end

-- ===== console commands (no references to CropControlOverride here) =====
local function normalizeBoolWord(s)
    if not s then return nil end
    s = string.lower(tostring(s))
    if s=="on" or s=="true" or s=="1" or s=="yes" then return true end
    if s=="off" or s=="false" or s=="0" or s=="no" then return false end
    if s=="toggle" or s=="" then return nil end
    return nil
end

function Debug:consoleToggleDebug(arg)
    local val = normalizeBoolWord(arg)
    if val == nil then self.enabled = not self.enabled else self.enabled = val end
    print(("%s: debug %s"):format(self.prefix, self.enabled and "ENABLED" or "DISABLED"))
end

function Debug:consoleSetLogLevel(level) self:setLevel(level or "INFO") end
function Debug:consoleFlush() self:flush(false); print(("%s: flushed log to file"):format(self.prefix)) end
function Debug:consoleLogPath() print(("%s: log file = %s"):format(self.prefix, tostring(self.logFilePath))) end

addConsoleCommand("ccoDebug",    "Toggle/Set CropControlOverride debug (on|off|toggle)", "consoleToggleDebug", Debug)
addConsoleCommand("ccoLogLevel", "Set CCO log level (DEBUG|INFO|WARN|ERROR)",            "consoleSetLogLevel", Debug)
addConsoleCommand("ccoFlush",    "Force flush CCO log buffer to file",                   "consoleFlush",       Debug)
addConsoleCommand("ccoLogPath",  "Print path to current CCO log file",                   "consoleLogPath",     Debug)

return Debug
