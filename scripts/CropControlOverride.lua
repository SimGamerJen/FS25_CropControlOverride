-- FS25 — Crop Control Override (AI-only, new-save policy)
-- Reads config from modSettings and toggles AI usage (useForFieldJob) only.
-- No PDA changes. Designed for saves CREATED AFTER the map contains the fruits.

CropControlOverride = {
    MOD_ID      = g_currentModName or "FS25_CropControlOverride",
    _origUseFor = {},    -- snapshot of original useForFieldJob per fruit (NAME -> bool)
    _enabledMap = nil,   -- last-applied config map (NAME -> bool)
}

---------------------------------------------------------------------------
-- Helpers / Paths
---------------------------------------------------------------------------
local function upper(s) return s and string.upper(s) or s end
local function userRoot() return getUserProfileAppPath() end
local function ensureSlash(p) if not p or p=="" then return p end local c=p:sub(-1) if c~="/" and c~="\\" then return p.."/" end return p end
local function settingsRoot() local base = g_modSettingsDirectory or (userRoot().."modSettings/"); return ensureSlash(base.."FS25_CropControlOverride") end
local function templatePath() return settingsRoot().."config.xml" end
local function getSaveId()
    local mi = g_currentMission and g_currentMission.missionInfo
    if not mi then return nil end
    if mi.savegameIndex and tonumber(mi.savegameIndex) then return ("savegame%d"):format(tonumber(mi.savegameIndex)) end
    if mi.savegameDirectory and mi.savegameDirectory~="" then return mi.savegameDirectory:match("([^/\\]+)$") end
    return nil
end
local function perSavePath() local id=getSaveId(); if not id then return nil end return settingsRoot().."saves/"..id..".xml" end
local function ensureFolder(pathOrFile)
    local dir = pathOrFile:match("^(.*)[/\\][^/\\]+$") or pathOrFile
    if not dir or dir=="" then return end
    local acc=""; for part in string.gmatch(dir,"[^/\\]+") do acc = acc..part.."/"; if createFolder then createFolder(acc) end end
end

---------------------------------------------------------------------------
-- Config I/O (XMLFile only)
---------------------------------------------------------------------------
local function writeConfig(toPath, enabledMap)
    ensureFolder(toPath)
    local xml = XMLFile.create("CCO_write", toPath, "cropControl")
    if not xml then print("CCO [ERROR]: cannot create config at "..tostring(toPath)); return false end
    local i=0
    for nameU, en in pairs(enabledMap) do
        local k=("cropControl.fruits.fruit(%d)"):format(i); i=i+1
        xml:setString(k.."#name", nameU)
        xml:setBool(k.."#enabled", en~=false)
    end
    xml:save(); xml:delete(); return true
end

local function readConfig(path)
    local map = {}
    local xml = XMLFile.load("CCO_read", path, "cropControl")
    if not xml then return map end

    -- Prefer nested form <cropControl><fruits><fruit/></fruits></cropControl>
    local i=0; local count=0
    while true do
        local k=("cropControl.fruits.fruit(%d)"):format(i)
        if not xml:hasProperty(k) then break end
        local n  = xml:getString(k.."#name")
        local en = xml:getBool(k.."#enabled", true)
        if n and n~="" then map[upper(n)]=en; count = count+1 end
        i=i+1
    end
    -- Fallback to flat <cropControl><fruit/></cropControl>
    if count==0 then
        i=0
        while true do
            local k=("cropControl.fruit(%d)"):format(i)
            if not xml:hasProperty(k) then break end
            local n  = xml:getString(k.."#name")
            local en = xml:getBool(k.."#enabled", true)
            if n and n~="" then map[upper(n)]=en end
            i=i+1
        end
    end
    xml:delete()
    return map
end

local function buildDefaultEnabledMap()
    local m = {}
    if g_fruitTypeManager then
        for _, ft in ipairs(g_fruitTypeManager.fruitTypes) do
            if ft and ft.name then m[upper(ft.name)] = true end
        end
    end
    return m
end

local function ensureTemplateExists()
    local tpl = templatePath()
    if fileExists(tpl) then return tpl end
    local defaults = buildDefaultEnabledMap()
    if writeConfig(tpl, defaults) then print("CCO: wrote default template at "..tpl) end
    return tpl
end

local function ensurePerSaveExists()
    local per = perSavePath()
    if not per then return nil end
    if fileExists(per) then return per end
    local tpl = ensureTemplateExists()
    local map = readConfig(tpl)
    if not next(map) then map = buildDefaultEnabledMap() end
    if writeConfig(per, map) then print("CCO: created per-save config at "..per) end
    return per
end

---------------------------------------------------------------------------
-- Core: apply AI enable/disable only
---------------------------------------------------------------------------
function CropControlOverride:_applyEnabledMap(enabledMap)
    if not g_fruitTypeManager then return end

    -- snapshot original AI flag once
    for _, ft in ipairs(g_fruitTypeManager.fruitTypes) do
        local n = upper(ft.name)
        if self._origUseFor[n] == nil then self._origUseFor[n] = ft.useForFieldJob end
    end

    -- apply AI toggle
    local missing = {}
    for _, ft in ipairs(g_fruitTypeManager.fruitTypes) do
        local n = upper(ft.name)
        local en = enabledMap[n]
        if en == false then
            ft.useForFieldJob = false
        else
            local orig = self._origUseFor[n]
            if orig ~= nil then ft.useForFieldJob = orig else ft.useForFieldJob = true end
        end
    end

    -- warn about enabled fruits that aren't registered in this save (new-save-only caveat)
    for nameU, en in pairs(enabledMap) do
        if en ~= false then
            local found = false
            for _, ft in ipairs(g_fruitTypeManager.fruitTypes) do if upper(ft.name)==nameU then found=true; break end end
            if not found then table.insert(missing, nameU) end
        end
    end
    if #missing > 0 then
        print("CCO [WARN]: these enabled fruits are not present in this save (likely needs a NEW SAVE with updated map):")
        for _, n in ipairs(missing) do print("  - "..n) end
    end

    self._enabledMap = enabledMap
end

function CropControlOverride:_loadAndApply()
    local per = ensurePerSaveExists()
    local path = (per and fileExists(per)) and per or ensureTemplateExists()
    local map  = readConfig(path)
    if not next(map) then map = buildDefaultEnabledMap() end
    self:_applyEnabledMap(map)
    print(("CCO: applied AI crop settings from %s"):format(path))
end

---------------------------------------------------------------------------
-- Hook: after map finishes loading (all fruits registered)
---------------------------------------------------------------------------
local origLoadFinished = FSBaseMission.loadMapFinished
FSBaseMission.loadMapFinished = function(mission, ...)
    local r = { origLoadFinished(mission, ...) }
    CropControlOverride:_loadAndApply()
    return unpack(r)
end

---------------------------------------------------------------------------
-- Console: reload at runtime
---------------------------------------------------------------------------
function CropControlOverride:consoleReload()
    self:_loadAndApply()
    print("CCO: reload complete (AI-only)")
end
addConsoleCommand("ccoReload", "Reload CropControlOverride config and reapply (AI only, new-save policy)", "consoleReload", CropControlOverride)
