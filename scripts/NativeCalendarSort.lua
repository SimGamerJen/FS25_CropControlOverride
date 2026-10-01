-- Internal native Crop Calendar sorting for Crop Control Override.
-- Presentation-only: never mutates fruit definitions or seasonal growth data.

CCO_NativeCalendarSort = CCO_NativeCalendarSort or {}
local Sort = CCO_NativeCalendarSort

Sort.VERSION = 1
Sort.DEFAULT_MODE = "native"
Sort.currentMode = Sort.DEFAULT_MODE
Sort._settingsLoaded = false

Sort.MODE_NATIVE = "native"
Sort.MODE_AZ = "az"
Sort.MODE_PLANTABLE_AZ = "plantableAz"
Sort.MODE_PLANTING_START = "plantingStart"
Sort.MODE_HARVEST_START = "harvestStart"
Sort.MODE_PLANT_NOW = "plantNow"
Sort.MODE_HARVEST_NOW = "harvestNow"
Sort.MODE_NEXT_PLANTING = "nextPlanting"
Sort.MODE_NEXT_HARVEST = "nextHarvest"

Sort.MODES = {
    { id = Sort.MODE_NATIVE,         key = "cco_calendar_sort_native",         fallback = "Native Order" },
    { id = Sort.MODE_AZ,             key = "cco_calendar_sort_az",             fallback = "Alphabetical A-Z" },
    { id = Sort.MODE_PLANTABLE_AZ,   key = "cco_calendar_sort_plantable_az",   fallback = "Plantable A-Z" },
    { id = Sort.MODE_PLANTING_START, key = "cco_calendar_sort_planting_start", fallback = "Planting Start" },
    { id = Sort.MODE_HARVEST_START,  key = "cco_calendar_sort_harvest_start",  fallback = "Harvest Start" },
    { id = Sort.MODE_PLANT_NOW,      key = "cco_calendar_sort_plant_now",      fallback = "Plant Now" },
    { id = Sort.MODE_HARVEST_NOW,    key = "cco_calendar_sort_harvest_now",    fallback = "Harvest Now" },
    { id = Sort.MODE_NEXT_PLANTING,  key = "cco_calendar_sort_next_planting",  fallback = "Next Planting" },
    { id = Sort.MODE_NEXT_HARVEST,   key = "cco_calendar_sort_next_harvest",   fallback = "Next Harvest" },
}

local SETTINGS_FOLDER = "FS25_CropControlOverride/"
local SETTINGS_FILE = "calendarSort.xml"
local SETTINGS_ROOT = "cropControlCalendarSort"

local function debug(message)
    if CCO_Debug ~= nil and CCO_Debug.debug ~= nil then
        CCO_Debug:debug("[CalendarSort] " .. tostring(message))
    end
end

local function localize(key, fallback)
    if g_i18n ~= nil and g_i18n.getText ~= nil then
        local ok, value = pcall(function() return g_i18n:getText(key) end)
        local text = tostring(value or "")
        if ok and text ~= "" and text ~= key and text:find("^Missing '") == nil then
            return text
        end
    end
    return fallback
end

local function copyArray(values)
    local result = {}
    for index, value in ipairs(values or {}) do
        result[index] = value
    end
    return result
end

local function normalizedText(value)
    local text = tostring(value or "")
    if utf8ToLower ~= nil then
        local ok, lowered = pcall(utf8ToLower, text)
        if ok and lowered ~= nil then return tostring(lowered) end
    end
    return string.lower(text)
end

function Sort:getModeDefinition(modeId)
    for index, mode in ipairs(self.MODES) do
        if mode.id == modeId then return mode, index end
    end
    return self.MODES[1], 1
end

function Sort:isValidMode(modeId)
    for _, mode in ipairs(self.MODES) do
        if mode.id == modeId then return true end
    end
    return false
end

function Sort:getModeLabel(modeId)
    local mode = self:getModeDefinition(modeId)
    return localize(mode.key, mode.fallback)
end

function Sort:getButtonText()
    local template = localize("cco_calendar_sort_button", "SORT: %s")
    return string.format(template, string.upper(self:getModeLabel(self.currentMode)))
end

function Sort:getDisplayName(fruitType)
    if fruitType == nil then return "" end

    if g_fruitTypeManager ~= nil
        and g_fruitTypeManager.getFillTypeByFruitTypeIndex ~= nil
        and fruitType.index ~= nil then
        local ok, fillType = pcall(
            g_fruitTypeManager.getFillTypeByFruitTypeIndex,
            g_fruitTypeManager,
            fruitType.index
        )
        if ok and fillType ~= nil and fillType.title ~= nil and tostring(fillType.title) ~= "" then
            return tostring(fillType.title)
        end
    end

    return tostring(fruitType.name or "")
end

function Sort:isPlantable(fruitType)
    return fruitType ~= nil and fruitType.allowsSeeding == true
end

function Sort:getSeasonalGrowthData(fruitType)
    if fruitType == nil then return nil end

    if fruitType.getSeasonalGrowthData ~= nil then
        local ok, data = pcall(fruitType.getSeasonalGrowthData, fruitType)
        if ok and type(data) == "table" and type(data.periods) == "table" then return data end
    end

    if type(fruitType.growthDataSeasonal) == "table"
        and type(fruitType.growthDataSeasonal.periods) == "table" then
        return fruitType.growthDataSeasonal
    end

    if type(fruitType.data) == "table"
        and type(fruitType.data.growthDataSeasonal) == "table"
        and type(fruitType.data.growthDataSeasonal.periods) == "table" then
        return fruitType.data.growthDataSeasonal
    end

    return nil
end

function Sort:getFirstSeasonalPeriod(fruitType, propertyName)
    local seasonalData = self:getSeasonalGrowthData(fruitType)
    if seasonalData == nil then return 999 end

    for period = 1, 12 do
        local periodInfo = seasonalData.periods[period]
        if type(periodInfo) == "table" and periodInfo[propertyName] == true then
            return period
        end
    end

    return 999
end

function Sort:getCurrentSeasonalPeriod()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local period = nil

    if env ~= nil then
        period = env.currentPeriod or env.period or env.currentSeasonPeriod

        if period == nil and env.getCurrentPeriod ~= nil then
            local ok, result = pcall(function() return env:getCurrentPeriod() end)
            if ok then period = result end
        end

        if period == nil and env.getPeriod ~= nil then
            local ok, result = pcall(function() return env:getPeriod() end)
            if ok then period = result end
        end

        if period == nil then
            period = env.currentMonth or env.month
        end
    end

    period = tonumber(period)
    if period == nil then return nil end

    period = math.floor(period)
    if period < 1 or period > 12 then return nil end
    return period
end

function Sort:isSeasonalPropertyActive(fruitType, propertyName, period)
    if period == nil then return false end
    local seasonalData = self:getSeasonalGrowthData(fruitType)
    if seasonalData == nil then return false end
    local periodInfo = seasonalData.periods[period]
    return type(periodInfo) == "table" and periodInfo[propertyName] == true
end

function Sort:getNextSeasonalDistance(fruitType, propertyName, currentPeriod)
    if currentPeriod == nil then return 999 end

    local seasonalData = self:getSeasonalGrowthData(fruitType)
    if seasonalData == nil then return 999 end

    for offset = 0, 11 do
        local period = ((currentPeriod - 1 + offset) % 12) + 1
        local periodInfo = seasonalData.periods[period]
        if type(periodInfo) == "table" and periodInfo[propertyName] == true then
            return offset
        end
    end

    return 999
end

local function compareDisplayName(a, b)
    local aDisplay = normalizedText(Sort:getDisplayName(a))
    local bDisplay = normalizedText(Sort:getDisplayName(b))
    if aDisplay ~= bDisplay then return aDisplay < bDisplay end
    return normalizedText(a ~= nil and a.name or "") < normalizedText(b ~= nil and b.name or "")
end

function Sort:sortFruitTypes(fruitTypes, modeId)
    local sorted = copyArray(fruitTypes)
    local mode = self:isValidMode(modeId) and modeId or self.DEFAULT_MODE

    if mode == self.MODE_NATIVE then return sorted end

    if mode == self.MODE_AZ then
        table.sort(sorted, compareDisplayName)
        return sorted
    end

    if mode == self.MODE_PLANTABLE_AZ then
        table.sort(sorted, function(a, b)
            local aPlantable = self:isPlantable(a)
            local bPlantable = self:isPlantable(b)
            if aPlantable ~= bPlantable then return aPlantable end
            return compareDisplayName(a, b)
        end)
        return sorted
    end

    if mode == self.MODE_PLANT_NOW or mode == self.MODE_HARVEST_NOW then
        local currentPeriod = self:getCurrentSeasonalPeriod()
        if currentPeriod == nil then
            table.sort(sorted, compareDisplayName)
            return sorted
        end

        local propertyName = mode == self.MODE_HARVEST_NOW and "isHarvestable" or "plantingAllowed"
        table.sort(sorted, function(a, b)
            local aActive = self:isSeasonalPropertyActive(a, propertyName, currentPeriod)
            local bActive = self:isSeasonalPropertyActive(b, propertyName, currentPeriod)
            if aActive ~= bActive then return aActive end
            return compareDisplayName(a, b)
        end)
        return sorted
    end

    if mode == self.MODE_NEXT_PLANTING or mode == self.MODE_NEXT_HARVEST then
        local currentPeriod = self:getCurrentSeasonalPeriod()
        if currentPeriod == nil then
            table.sort(sorted, compareDisplayName)
            return sorted
        end

        local propertyName = mode == self.MODE_NEXT_HARVEST and "isHarvestable" or "plantingAllowed"
        table.sort(sorted, function(a, b)
            local aDistance = self:getNextSeasonalDistance(a, propertyName, currentPeriod)
            local bDistance = self:getNextSeasonalDistance(b, propertyName, currentPeriod)
            if aDistance ~= bDistance then return aDistance < bDistance end
            return compareDisplayName(a, b)
        end)
        return sorted
    end

    local propertyName = mode == self.MODE_HARVEST_START and "isHarvestable" or "plantingAllowed"
    table.sort(sorted, function(a, b)
        local aPeriod = self:getFirstSeasonalPeriod(a, propertyName)
        local bPeriod = self:getFirstSeasonalPeriod(b, propertyName)
        if aPeriod ~= bPeriod then return aPeriod < bPeriod end
        return compareDisplayName(a, b)
    end)

    return sorted
end

function Sort:getSettingsPath()
    if g_modSettingsDirectory == nil or g_modSettingsDirectory == "" then return nil end
    local directory = g_modSettingsDirectory .. SETTINGS_FOLDER
    if createFolder ~= nil then pcall(createFolder, directory) end
    return directory .. SETTINGS_FILE
end

function Sort:loadSettings()
    if self._settingsLoaded == true then return true end
    self._settingsLoaded = true
    self.currentMode = self.DEFAULT_MODE

    local path = self:getSettingsPath()
    if path == nil or XMLFile == nil or XMLFile.loadIfExists == nil then return false end

    local xmlFile = XMLFile.loadIfExists("CCO_CalendarSortSettings", path, SETTINGS_ROOT)
    if xmlFile == nil then return false end

    local mode = xmlFile:getString(SETTINGS_ROOT .. "#mode", self.DEFAULT_MODE)
    xmlFile:delete()

    if self:isValidMode(mode) then self.currentMode = mode end
    debug("loaded native calendar sort mode " .. tostring(self.currentMode))
    return true
end

function Sort:saveSettings()
    local path = self:getSettingsPath()
    if path == nil or XMLFile == nil or XMLFile.create == nil then return false end

    local xmlFile = XMLFile.create("CCO_CalendarSortSettings", path, SETTINGS_ROOT)
    if xmlFile == nil then return false end

    xmlFile:setString(SETTINGS_ROOT .. "#mode", self.currentMode)
    xmlFile:setInt(SETTINGS_ROOT .. "#version", self.VERSION)
    xmlFile:save()
    xmlFile:delete()
    debug("saved native calendar sort mode " .. tostring(self.currentMode))
    return true
end

function Sort:ensureSettingsLoaded()
    if self._settingsLoaded ~= true then self:loadSettings() end
end

function Sort:setMode(modeId)
    if not self:isValidMode(modeId) then return false end
    self.currentMode = modeId
    self:saveSettings()
    return true
end

function Sort:showDialog(frame, onChanged)
    self:ensureSettingsLoaded()

    local options = {}
    for index, mode in ipairs(self.MODES) do
        options[index] = localize(mode.key, mode.fallback)
    end

    local _, currentIndex = self:getModeDefinition(self.currentMode)
    local promptTemplate = localize(
        "cco_calendar_sort_prompt",
        "Current: %s - Choose how crops are ordered in the calendar."
    )
    local title = localize("cco_calendar_sort_title", "Crop Calendar Sort")

    local callbackArgs = { frame, onChanged }
    local callback = function(target, selectedOption, args)
        if type(selectedOption) ~= "number" or selectedOption <= 0 then return end

        local mode = Sort.MODES[selectedOption]
        if mode == nil then return end

        if Sort:setMode(mode.id) then
            local changedCallback = type(args) == "table" and args[2] or nil
            local selectedFrame = type(args) == "table" and args[1] or frame
            if type(changedCallback) == "function" then
                pcall(changedCallback, selectedFrame, mode.id)
            end
        end
    end

    if OptionDialog == nil or OptionDialog.createFromExistingGui == nil then
        debug("OptionDialog unavailable")
        return false
    end

    local ok, err = pcall(function()
        OptionDialog.createFromExistingGui({
            options = options,
            optionText = string.format(promptTemplate, self:getModeLabel(self.currentMode)),
            optionTitle = title,
            callbackFunc = callback,
        }, "FS25_CropControlOverrideCalendarSortDialog")

        local dialog = OptionDialog.INSTANCE
        if dialog == nil then error("OptionDialog.INSTANCE unavailable") end

        if dialog.optionElement ~= nil and dialog.optionElement.setState ~= nil then
            dialog.optionElement:setState(currentIndex or 1)
        end

        if dialog.setCallback ~= nil then
            dialog:setCallback(callback, self, callbackArgs)
        end
    end)

    if not ok then
        debug("OptionDialog failed: " .. tostring(err))
        return false
    end

    return true
end
