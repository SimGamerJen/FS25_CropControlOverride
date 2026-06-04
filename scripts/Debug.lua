-- FS25_CropControlOverride - lightweight debug/log helpers
-- Default INFO keeps lifecycle messages visible. Use ccoLogLevel DEBUG for detailed NPC crop replacement/block traces.

CCO_Debug = {
    enabled = true,
    level = "INFO",
    prefix = "CCO",
}

local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

local function levelOK(current, wanted)
    current = string.upper(current or "INFO")
    wanted = string.upper(wanted or "INFO")
    return (LEVELS[wanted] or 2) >= (LEVELS[current] or 2)
end

local function fmt(prefix, lvl, msg)
    return ("%s [%s] %s"):format(prefix, lvl, tostring(msg))
end

function CCO_Debug:setLevel(newLevel)
    newLevel = string.upper(newLevel or "INFO")
    if LEVELS[newLevel] ~= nil then
        self.level = newLevel
        print(("%s: log level set to %s"):format(self.prefix, self.level))
    else
        print(("%s: invalid log level '%s' (use DEBUG|INFO|WARN|ERROR)"):format(self.prefix, tostring(newLevel)))
    end
end

function CCO_Debug:debug(msg)
    if self.enabled and levelOK(self.level, "DEBUG") then print(fmt(self.prefix, "DEBUG", msg)) end
end

function CCO_Debug:info(msg)
    if self.enabled and levelOK(self.level, "INFO") then print(fmt(self.prefix, "INFO", msg)) end
end

function CCO_Debug:warn(msg)
    if self.enabled and levelOK(self.level, "WARN") then print(fmt(self.prefix, "WARN", msg)) end
end

function CCO_Debug:error(msg)
    print(fmt(self.prefix, "ERROR", msg))
end

local function normalizeBoolWord(s)
    if s == nil then return nil end
    s = string.lower(tostring(s))
    if s == "on" or s == "true" or s == "1" or s == "yes" then return true end
    if s == "off" or s == "false" or s == "0" or s == "no" then return false end
    if s == "toggle" or s == "" then return nil end
    return nil
end

function CCO_Debug:consoleToggleDebug(arg)
    local val = normalizeBoolWord(arg)
    if val == nil then
        self.enabled = not self.enabled
    else
        self.enabled = val
    end
    print(("%s: debug %s"):format(self.prefix, self.enabled and "ENABLED" or "DISABLED"))
end

function CCO_Debug:consoleSetLogLevel(level)
    self:setLevel(level or "INFO")
end

addConsoleCommand("ccoDebug", "Toggle/Set CropControlOverride debug (on|off|toggle)", "consoleToggleDebug", CCO_Debug)
addConsoleCommand("ccoLogLevel", "Set CCO log level (DEBUG|INFO|WARN|ERROR)", "consoleSetLogLevel", CCO_Debug)

return CCO_Debug
