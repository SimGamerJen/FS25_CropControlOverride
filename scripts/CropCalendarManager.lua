-- FS25_CropControlOverride
-- Crop calendar discovery, baseline snapshot, validation and guarded lifecycle shifting.
--
-- Calendar overrides are stored as small period offsets. The live lifecycle is
-- always rebuilt from the captured map default, so CCO never serialises or
-- replaces a map author's growth-state graph.

CCO_CropCalendar = CCO_CropCalendar or {
    PERIOD_COUNT = 12,
    baselineByFruit = {},
    rows = {},
    summary = nil,
    captured = false,
    captureGeneration = 0,
    configuredShifts = {},
    configuredCustomOverrides = {},
    appliedShifts = {},
    appliedCustomOverrides = {},
    lastPreview = nil,
}

local Calendar = CCO_CropCalendar

local PERIOD_LABELS = {
    [1] = "MAR", [2] = "APR", [3] = "MAY", [4] = "JUN",
    [5] = "JUL", [6] = "AUG", [7] = "SEP", [8] = "OCT",
    [9] = "NOV", [10] = "DEC", [11] = "JAN", [12] = "FEB",
}

local MONTH_LABELS = {
    [1] = "JAN", [2] = "FEB", [3] = "MAR", [4] = "APR",
    [5] = "MAY", [6] = "JUN", [7] = "JUL", [8] = "AUG",
    [9] = "SEP", [10] = "OCT", [11] = "NOV", [12] = "DEC",
}

local PERIOD_TO_MONTH = {
    [1] = 3, [2] = 4, [3] = 5, [4] = 6,
    [5] = 7, [6] = 8, [7] = 9, [8] = 10,
    [9] = 11, [10] = 12, [11] = 1, [12] = 2,
}

local function upper(value)
    return value ~= nil and string.upper(tostring(value)) or nil
end

local function sortedFruitTypes()
    local fruits = {}
    if g_fruitTypeManager ~= nil and type(g_fruitTypeManager.fruitTypes) == "table" then
        for _, fruitType in pairs(g_fruitTypeManager.fruitTypes) do
            if type(fruitType) == "table" and fruitType.name ~= nil then
                fruits[#fruits + 1] = fruitType
            end
        end
    end

    table.sort(fruits, function(a, b)
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    return fruits
end

local function normalizeShift(value)
    local shift = tonumber(value) or 0
    shift = math.floor(shift)
    if shift < -6 then shift = -6 end
    if shift > 6 then shift = 6 end
    return shift
end

local function shiftedPeriodIndex(period, shift)
    local source = ((tonumber(period) or 1) - 1 - normalizeShift(shift)) % Calendar.PERIOD_COUNT
    return source + 1
end

local function normalizePeriodMask(value)
    if type(value) == "table" then
        local chars = {}
        for period = 1, Calendar.PERIOD_COUNT do
            chars[period] = value[period] == true and "1" or "0"
        end
        return table.concat(chars)
    end
    local text = tostring(value or ""):gsub("[^01]", "")
    if #text < Calendar.PERIOD_COUNT then
        text = text .. string.rep("0", Calendar.PERIOD_COUNT - #text)
    end
    return text:sub(1, Calendar.PERIOD_COUNT)
end

local function periodSetFromMask(mask)
    local normalized = normalizePeriodMask(mask)
    local result = {}
    for period = 1, Calendar.PERIOD_COUNT do
        result[period] = normalized:sub(period, period) == "1"
    end
    return result
end

local function periodListFromMask(mask)
    local set = periodSetFromMask(mask)
    local result = {}
    for period = 1, Calendar.PERIOD_COUNT do
        if set[period] == true then result[#result + 1] = period end
    end
    return result
end

local function periodMaskFromPeriods(periods)
    local set = {}
    for _, period in ipairs(periods or {}) do
        local p = tonumber(period)
        if p ~= nil and p >= 1 and p <= Calendar.PERIOD_COUNT then set[math.floor(p)] = true end
    end
    return normalizePeriodMask(set)
end

local MONTH_TO_PERIOD = {
    JAN = 11, FEB = 12, MAR = 1, APR = 2, MAY = 3, JUN = 4,
    JUL = 5, AUG = 6, SEP = 7, OCT = 8, NOV = 9, DEC = 10,
}

local function parseMonthExpression(expression)
    local selected = {}
    local text = upper(expression or "") or ""
    text = text:gsub("%s+", "")
    if text == "" or text == "-" or text == "NONE" then return normalizePeriodMask(selected) end
    if text == "ALL" or text == "ALLYEAR" or text == "ALL_YEAR" then
        for period = 1, Calendar.PERIOD_COUNT do selected[period] = true end
        return normalizePeriodMask(selected)
    end

    local calendarMonths = {"JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"}
    local monthIndex = {}
    for index, label in ipairs(calendarMonths) do monthIndex[label] = index end
    for token in (text .. ","):gmatch("(.-),") do
        if token ~= "" then
            local first, last = token:match("^([A-Z][A-Z][A-Z])%-([A-Z][A-Z][A-Z])$")
            if first ~= nil and monthIndex[first] ~= nil and monthIndex[last] ~= nil then
                local index = monthIndex[first]
                for _ = 1, 12 do
                    selected[MONTH_TO_PERIOD[calendarMonths[index]]] = true
                    if calendarMonths[index] == last then break end
                    index = (index % 12) + 1
                end
            elseif MONTH_TO_PERIOD[token] ~= nil then
                selected[MONTH_TO_PERIOD[token]] = true
            end
        end
    end
    return normalizePeriodMask(selected)
end

local function normalizeCustomOverride(value)
    if type(value) ~= "table" then return nil end
    local planting = normalizePeriodMask(value.planting or value.plantingMask)
    local harvest = normalizePeriodMask(value.harvest or value.harvestMask)
    if not planting:find("1", 1, true) or not harvest:find("1", 1, true) then return nil end
    return {
        planting = planting,
        harvest = harvest,
        strategy = tostring(value.strategy or "phaseWarpV1"),
    }
end

local function customOverridesEqual(a, b)
    local aa = normalizeCustomOverride(a)
    local bb = normalizeCustomOverride(b)
    if aa == nil or bb == nil then return aa == nil and bb == nil end
    return aa.planting == bb.planting and aa.harvest == bb.harvest and aa.strategy == bb.strategy
end

local function getFruitTypeByName(name)
    local wanted = upper(name)
    for _, fruitType in ipairs(sortedFruitTypes()) do
        if upper(fruitType.name) == wanted then return fruitType end
    end
    return nil
end

local function addSeasonalSource(sources, seen, data, name)
    if type(data) ~= "table" or seen[data] == true then return end
    seen[data] = true
    sources[#sources + 1] = { data = data, name = name }
end

local function getSeasonalSources(fruitType)
    local sources = {}
    local seen = {}
    if fruitType == nil then return sources end

    if fruitType.getSeasonalGrowthData ~= nil then
        local ok, data = pcall(fruitType.getSeasonalGrowthData, fruitType)
        if ok then addSeasonalSource(sources, seen, data, "getSeasonalGrowthData") end
    end

    addSeasonalSource(sources, seen, fruitType.growthDataSeasonal, "growthDataSeasonal")
    if type(fruitType.data) == "table" then
        addSeasonalSource(sources, seen, fruitType.data.growthDataSeasonal, "data.growthDataSeasonal")
    end

    return sources
end

local function getSeasonalData(fruitType)
    local sources = getSeasonalSources(fruitType)
    local primary = nil

    for _, source in ipairs(sources) do
        if type(source.data.periods) == "table" then
            primary = source
            break
        end
    end
    if primary == nil then primary = sources[1] end
    if primary == nil then return nil, nil, nil, nil end

    local initialState = primary.data.initialState
    local initialSource = initialState ~= nil and primary.name or nil
    if initialState == nil then
        for _, source in ipairs(sources) do
            if source.data.initialState ~= nil then
                initialState = source.data.initialState
                initialSource = source.name
                break
            end
        end
    end

    return primary.data, primary.name, initialState, initialSource
end

local function getMapping(periodInfo)
    if type(periodInfo) ~= "table" then return nil, "growthMapping" end
    if type(periodInfo.growthMapping) == "table" then
        return periodInfo.growthMapping, "growthMapping"
    end
    if type(periodInfo.mapping) == "table" then
        return periodInfo.mapping, "mapping"
    end
    return nil, periodInfo.mapping ~= nil and "mapping" or "growthMapping"
end

local function getMappingValue(mapping, state)
    if type(mapping) ~= "table" or state == nil then return nil end
    local value = mapping[state]
    if value == nil then value = mapping[tostring(state)] end
    return value
end

local function copyMapping(mapping)
    local result = {}
    if type(mapping) == "table" then
        for startState, endState in pairs(mapping) do
            result[startState] = endState
        end
    end
    return result
end

local function countTableEntries(value)
    local count = 0
    if type(value) == "table" then
        for _, _ in pairs(value) do count = count + 1 end
    end
    return count
end

local function valueEquals(a, b)
    if a == b then return true end
    if tonumber(a) ~= nil and tonumber(b) ~= nil then
        return tonumber(a) == tonumber(b)
    end
    return false
end

local function mappingsEqual(a, b)
    if countTableEntries(a) ~= countTableEntries(b) then return false end
    for startState, endState in pairs(a or {}) do
        if not valueEquals(endState, (b or {})[startState]) then return false end
    end
    return true
end

local function snapshotSeasonalData(fruitType, seasonalData, source, initialState, initialSource)
    local snapshot = {
        name = upper(fruitType.name),
        index = fruitType.index,
        source = source,
        initialState = initialState,
        initialSource = initialSource,
        periods = {},
    }

    for period = 1, Calendar.PERIOD_COUNT do
        local periodInfo = type(seasonalData.periods) == "table" and seasonalData.periods[period] or nil
        if type(periodInfo) == "table" then
            local mapping, mappingKey = getMapping(periodInfo)
            snapshot.periods[period] = {
                exists = true,
                plantingAllowed = periodInfo.plantingAllowed,
                isHarvestable = periodInfo.isHarvestable,
                mappingKey = mappingKey,
                mapping = copyMapping(mapping),
            }
        else
            snapshot.periods[period] = { exists = false, mapping = {} }
        end
    end

    return snapshot
end

local function getKnownStateIndices(fruitType)
    local known = {}
    if type(fruitType) ~= "table" then return known end

    if type(fruitType.nameToGrowthState) == "table" then
        for _, stateIndex in pairs(fruitType.nameToGrowthState) do
            if tonumber(stateIndex) ~= nil then known[tonumber(stateIndex)] = true end
        end
    end

    local foliageStateCount = tonumber(fruitType.numFoliageStates)
    if foliageStateCount ~= nil and foliageStateCount > 0 then
        for stateIndex = 0, math.floor(foliageStateCount) do
            known[stateIndex] = true
        end
    end

    local numericFields = {
        fruitType.cutState,
        fruitType.witheredState,
        fruitType.harvestReadyState,
        fruitType.minHarvestingGrowthState,
        fruitType.maxHarvestingGrowthState,
        fruitType.minPreparingGrowthState,
        fruitType.maxPreparingGrowthState,
    }
    for _, stateIndex in ipairs(numericFields) do
        if tonumber(stateIndex) ~= nil then known[tonumber(stateIndex)] = true end
    end

    return known
end

local function addNumericState(target, value)
    local number = tonumber(value)
    if number ~= nil then target[number] = true end
end

local function addNumericRange(target, firstValue, lastValue)
    local firstNumber = tonumber(firstValue)
    local lastNumber = tonumber(lastValue)
    if firstNumber == nil or lastNumber == nil then return end
    firstNumber = math.floor(firstNumber)
    lastNumber = math.floor(lastNumber)
    if firstNumber > lastNumber then firstNumber, lastNumber = lastNumber, firstNumber end
    for state = firstNumber, lastNumber do target[state] = true end
end

local function getLifecycleTargets(fruitType)
    local harvest = {}
    local terminal = {}

    addNumericState(harvest, fruitType.harvestReadyState)
    addNumericRange(harvest, fruitType.minHarvestingGrowthState, fruitType.maxHarvestingGrowthState)
    addNumericState(terminal, fruitType.cutState)
    addNumericState(terminal, fruitType.witheredState)

    if type(fruitType.nameToGrowthState) == "table" then
        for stateName, stateIndex in pairs(fruitType.nameToGrowthState) do
            local nameU = upper(stateName or "") or ""
            if nameU:find("WITHER", 1, true) ~= nil or nameU:find("DEAD", 1, true) ~= nil or nameU:find("CUT", 1, true) ~= nil then
                addNumericState(terminal, stateIndex)
            elseif nameU:find("HARVEST", 1, true) ~= nil or nameU:find("READY", 1, true) ~= nil then
                addNumericState(harvest, stateIndex)
            end
        end
    end

    return harvest, terminal
end

local function classifyFruitType(fruitType)
    local nameU = upper(fruitType.name or "") or ""
    local allowsSeeding = fruitType.allowsSeeding == true
    local allowsHarvesting = fruitType.allowsHarvesting == true

    if nameU == "HUMUSACTIVE" or nameU == "MEADOW" then
        return "TECHNICAL", "technical/intermediate map lifecycle"
    end
    if nameU == "GRAPE" or nameU == "OLIVE" or nameU == "POPLAR" then
        return "PERENNIAL", "recognised permanent-crop lifecycle"
    end
    if not allowsSeeding and not allowsHarvesting then
        return "TECHNICAL", "neither seedable nor harvestable"
    end
    if fruitType.needsSeeding == false and allowsHarvesting then
        return "PERENNIAL", "harvestable without normal reseeding"
    end
    if allowsSeeding then
        return "FIELD", "seedable field lifecycle"
    end
    return "SPECIAL", "harvestable special lifecycle"
end

local function addIssue(row, severity, text)
    row.issues[#row.issues + 1] = tostring(text)
    if severity == "ERROR" then
        row.errorCount = row.errorCount + 1
    else
        row.warningCount = row.warningCount + 1
    end
end

local function addNote(row, text)
    row.notes[#row.notes + 1] = tostring(text)
    row.infoCount = row.infoCount + 1
end

local function periodListText(periods)
    local labels = {}
    for _, period in ipairs(periods or {}) do
        labels[#labels + 1] = PERIOD_LABELS[period] or ("P" .. tostring(period))
    end
    if #labels == 0 then return "-" end
    return table.concat(labels, ",")
end

local function windowListText(periods)
    local active = {}
    local activeCount = 0
    for _, period in ipairs(periods or {}) do
        local month = PERIOD_TO_MONTH[tonumber(period)]
        if month ~= nil and active[month] ~= true then
            active[month] = true
            activeCount = activeCount + 1
        end
    end

    if activeCount == 0 then return "-" end
    if activeCount == 12 then return "ALL YEAR" end

    local ranges = {}
    local month = 1
    while month <= 12 do
        if active[month] == true then
            local first = month
            local last = month
            while last < 12 and active[last + 1] == true do last = last + 1 end
            ranges[#ranges + 1] = { first = first, last = last }
            month = last + 1
        else
            month = month + 1
        end
    end

    if #ranges > 1 and ranges[1].first == 1 and ranges[#ranges].last == 12 then
        local merged = { first = ranges[#ranges].first, last = ranges[1].last, wraps = true }
        table.remove(ranges, #ranges)
        table.remove(ranges, 1)
        table.insert(ranges, 1, merged)
    end

    local labels = {}
    for _, range in ipairs(ranges) do
        if range.wraps == true then
            labels[#labels + 1] = MONTH_LABELS[range.first] .. "-" .. MONTH_LABELS[range.last]
        elseif range.first == range.last then
            labels[#labels + 1] = MONTH_LABELS[range.first]
        else
            labels[#labels + 1] = MONTH_LABELS[range.first] .. "-" .. MONTH_LABELS[range.last]
        end
    end
    return table.concat(labels, ",")
end

local function compareWithBaseline(row, seasonalData, resolvedInitialState)
    local baseline = Calendar.baselineByFruit[row.name]
    if baseline == nil or type(seasonalData) ~= "table" then return nil end

    if not valueEquals(baseline.initialState, resolvedInitialState) then return true end

    for period = 1, Calendar.PERIOD_COUNT do
        local currentInfo = type(seasonalData.periods) == "table" and seasonalData.periods[period] or nil
        local baseInfo = baseline.periods[period]
        if (type(currentInfo) == "table") ~= (baseInfo ~= nil and baseInfo.exists == true) then
            return true
        end
        if type(currentInfo) == "table" and baseInfo ~= nil then
            if currentInfo.plantingAllowed ~= baseInfo.plantingAllowed then return true end
            if currentInfo.isHarvestable ~= baseInfo.isHarvestable then return true end
            local currentMapping = getMapping(currentInfo)
            if not mappingsEqual(currentMapping or {}, baseInfo.mapping or {}) then return true end
        end
    end

    return false
end

local function canReachTarget(graph, startState, targets)
    if targets[startState] == true then return true end
    local queue = { startState }
    local visited = { [startState] = true }
    local cursor = 1

    while cursor <= #queue do
        local state = queue[cursor]
        cursor = cursor + 1
        for nextState, _ in pairs(graph[state] or {}) do
            if targets[nextState] == true then return true end
            if visited[nextState] ~= true then
                visited[nextState] = true
                queue[#queue + 1] = nextState
            end
        end
    end
    return false
end

local function simulateSeasonalPath(seasonalData, initialState, plantingPeriods, harvestTargets)
    local startState = tonumber(initialState)
    if startState == nil or countTableEntries(harvestTargets) == 0 or #plantingPeriods == 0 then
        return nil, nil, nil
    end

    for _, plantingPeriod in ipairs(plantingPeriods) do
        local state = startState
        for step = 0, 35 do
            if harvestTargets[state] == true then return true, plantingPeriod, step end
            local period = ((plantingPeriod - 1 + step) % Calendar.PERIOD_COUNT) + 1
            local periodInfo = type(seasonalData.periods) == "table" and seasonalData.periods[period] or nil
            local mapping = getMapping(periodInfo)
            local nextState = tonumber(getMappingValue(mapping, state))
            if nextState ~= nil then state = nextState end
        end
        if harvestTargets[state] == true then return true, plantingPeriod, 36 end
    end

    return false, nil, nil
end

local function analyseLifecycle(row, fruitType, seasonalData)
    local graph = {}
    local sourceStates = {}
    local endStates = {}

    for period = 1, Calendar.PERIOD_COUNT do
        local periodInfo = type(seasonalData.periods) == "table" and seasonalData.periods[period] or nil
        local mapping = getMapping(periodInfo)
        if type(mapping) == "table" then
            for startState, endState in pairs(mapping) do
                local startNumber = tonumber(startState)
                local endNumber = tonumber(endState)
                if startNumber ~= nil and endNumber ~= nil then
                    graph[startNumber] = graph[startNumber] or {}
                    graph[startNumber][endNumber] = true
                    sourceStates[startNumber] = true
                    endStates[endNumber] = true
                end
            end
        end
    end

    local harvestTargets, terminalTargets = getLifecycleTargets(fruitType)
    local allTargets = {}
    for state, _ in pairs(harvestTargets) do allTargets[state] = true end
    for state, _ in pairs(terminalTargets) do allTargets[state] = true end

    row.harvestTargetCount = countTableEntries(harvestTargets)
    row.terminalTargetCount = countTableEntries(terminalTargets)
    row.lifecycleTargetCount = countTableEntries(allTargets)
    row.lifecycleSourceStateCount = countTableEntries(sourceStates)

    if row.transitionCount == 0 then
        row.lifecycleStatus = "NO MOVES"
        return
    end

    if row.lifecycleTargetCount == 0 then
        row.lifecycleStatus = "TARGET ?"
        addNote(row, "No explicit harvest-ready or terminal state indices are exposed; lifecycle reachability cannot be proven.")
        return
    end

    local reachable = 0
    local unreachable = {}
    for state, _ in pairs(sourceStates) do
        if canReachTarget(graph, state, allTargets) then
            reachable = reachable + 1
        else
            unreachable[#unreachable + 1] = state
        end
    end
    table.sort(unreachable)
    row.lifecycleReachableStateCount = reachable
    row.lifecycleUnreachableStates = unreachable

    local deadEnds = {}
    for state, _ in pairs(endStates) do
        if graph[state] == nil and allTargets[state] ~= true then deadEnds[#deadEnds + 1] = state end
    end
    table.sort(deadEnds)
    row.lifecycleDeadEndStates = deadEnds

    if #unreachable == 0 then
        row.lifecycleStatus = "GRAPH OK"
    elseif reachable == 0 then
        row.lifecycleStatus = "REVIEW"
        addNote(row, ("No mapped source state can reach an exposed harvest-ready or terminal state (%d source states checked)."):format(
            row.lifecycleSourceStateCount or 0))
    else
        row.lifecycleStatus = "PARTIAL"
        addNote(row, ("%d of %d mapped source states cannot reach an exposed harvest-ready or terminal state in the union graph."):format(
            #unreachable, row.lifecycleSourceStateCount or 0))
    end

    if #deadEnds > 0 then
        addNote(row, ("%d mapped end state(s) have no outgoing transition and are not recognised as harvest-ready or terminal."):format(#deadEnds))
    end

    local pathFound, plantingPeriod, steps = simulateSeasonalPath(seasonalData, row.initialState, row.plantingPeriods, harvestTargets)
    row.seasonalPathFound = pathFound
    if pathFound == true then
        row.lifecycleStatus = "PATH OK"
        row.seasonalPathPlantingPeriod = plantingPeriod
        row.seasonalPathSteps = steps
    elseif pathFound == false then
        addNote(row, "No simple planting-to-harvest path was reproduced within 36 seasonal periods from the exposed initialState; review before future editing.")
        if row.lifecycleStatus == "GRAPH OK" then row.lifecycleStatus = "GRAPH ONLY" end
    end
end

local function inspectFruit(fruitType, seasonalOverride, sourceOverride, initialOverride, initialSourceOverride)
    local category, categoryReason = classifyFruitType(fruitType)
    local row = {
        name = upper(fruitType.name),
        index = fruitType.index,
        allowsSeeding = fruitType.allowsSeeding == true,
        allowsHarvesting = fruitType.allowsHarvesting == true,
        category = category,
        categoryReason = categoryReason,
        editability = "BLOCKED",
        configuredShift = normalizeShift(Calendar.configuredShifts[upper(fruitType.name)]),
        configuredCustom = normalizeCustomOverride(Calendar.configuredCustomOverrides[upper(fruitType.name)]),
        configuredMode = Calendar:getConfiguredMode(upper(fruitType.name)),
        seasonal = false,
        source = nil,
        initialState = nil,
        initialSource = nil,
        initialStateDisplay = "INFERRED",
        periodCount = 0,
        missingPeriods = {},
        plantingPeriods = {},
        harvestPeriods = {},
        transitionCount = 0,
        warningCount = 0,
        errorCount = 0,
        infoCount = 0,
        issues = {},
        notes = {},
        changedFromBaseline = nil,
        lifecycleStatus = "UNKNOWN",
    }

    local seasonalData, source, initialState, initialSource
    if seasonalOverride ~= nil then
        seasonalData = seasonalOverride
        source = sourceOverride or "calendarPreview"
        initialState = initialOverride
        initialSource = initialSourceOverride
    else
        seasonalData, source, initialState, initialSource = getSeasonalData(fruitType)
    end
    if seasonalData == nil then
        row.status = "NO DATA"
        addIssue(row, "WARN", "No seasonal growth data is exposed by this fruit type.")
        row.plantingText = "-"
        row.harvestText = "-"
        return row
    end

    row.seasonal = true
    row.source = source
    row.initialState = initialState
    row.initialSource = initialSource
    row.initialStateDisplay = initialState ~= nil and tostring(initialState) or "INFERRED"

    if initialState == nil then
        addNote(row, "Seasonal initialState is not explicitly exposed; the game/map provides a working lifecycle without it.")
    elseif initialSource ~= source then
        addNote(row, ("Seasonal initialState was backfilled from %s while periods came from %s."):format(
            tostring(initialSource), tostring(source)))
    end

    if type(seasonalData.periods) ~= "table" then
        addIssue(row, "ERROR", "Seasonal periods table is missing.")
        row.status = "ERROR"
        row.plantingText = "-"
        row.harvestText = "-"
        return row
    end

    local knownStates = getKnownStateIndices(fruitType)
    local knownStateCount = countTableEntries(knownStates)

    for period = 1, Calendar.PERIOD_COUNT do
        local periodInfo = seasonalData.periods[period]
        if type(periodInfo) ~= "table" then
            row.missingPeriods[#row.missingPeriods + 1] = period
        else
            row.periodCount = row.periodCount + 1
            if periodInfo.plantingAllowed == true then
                row.plantingPeriods[#row.plantingPeriods + 1] = period
            end
            if periodInfo.isHarvestable == true then
                row.harvestPeriods[#row.harvestPeriods + 1] = period
            end

            local mapping = getMapping(periodInfo)
            if type(mapping) == "table" then
                for startState, endState in pairs(mapping) do
                    row.transitionCount = row.transitionCount + 1
                    local startNumber = tonumber(startState)
                    local endNumber = tonumber(endState)
                    if startNumber == nil or endNumber == nil then
                        addIssue(row, "ERROR", ("Period %d has a non-numeric growth transition."):format(period))
                    elseif knownStateCount > 0 and (knownStates[startNumber] ~= true or knownStates[endNumber] ~= true) then
                        addIssue(row, "WARN", ("Period %d references an unrecognised state (%s -> %s)."):format(
                            period, tostring(startState), tostring(endState)))
                    end
                end
            end
        end
    end

    if #row.missingPeriods > 0 then
        addIssue(row, "ERROR", "Missing seasonal period definitions: " .. periodListText(row.missingPeriods))
    end
    if row.allowsSeeding and #row.plantingPeriods == 0 then
        addIssue(row, "WARN", "Crop allows seeding but has no plantingAllowed period.")
    end
    if row.allowsHarvesting and #row.harvestPeriods == 0 then
        addIssue(row, "WARN", "Crop allows harvesting but has no isHarvestable period.")
    end
    if row.transitionCount == 0 and (row.allowsSeeding or row.allowsHarvesting) then
        addIssue(row, "WARN", "Seasonal calendar contains no growth transitions.")
    end

    analyseLifecycle(row, fruitType, seasonalData)

    row.changedFromBaseline = compareWithBaseline(row, seasonalData, initialState)
    row.plantingText = windowListText(row.plantingPeriods)
    row.harvestText = windowListText(row.harvestPeriods)

    if row.errorCount > 0 then
        row.status = "ERROR"
        row.editability = "BLOCKED"
    elseif row.warningCount > 0 then
        row.status = "WARN"
        row.editability = "REVIEW"
    elseif row.changedFromBaseline == true then
        row.status = "MODIFIED"
        row.editability = row.category == "FIELD" and "CANDIDATE" or "REVIEW"
    else
        row.status = "OK"
        row.editability = row.category == "FIELD" and "CANDIDATE" or "REVIEW"
    end

    return row
end

function Calendar:reset()
    self.baselineByFruit = {}
    self.rows = {}
    self.summary = nil
    self.captured = false
    self.configuredShifts = {}
    self.configuredCustomOverrides = {}
    self.appliedShifts = {}
    self.appliedCustomOverrides = {}
    self.lastPreview = nil
end

function Calendar:hasConfiguredShifts()
    for _, shift in pairs(self.configuredShifts or {}) do
        if normalizeShift(shift) ~= 0 then return true end
    end
    return false
end

function Calendar:hasConfiguredCustomOverrides()
    return next(self.configuredCustomOverrides or {}) ~= nil
end

function Calendar:hasConfiguredOverrides()
    return self:hasConfiguredShifts() or self:hasConfiguredCustomOverrides()
end

function Calendar:setConfiguredShifts(shifts)
    local normalized = {}
    for name, shift in pairs(shifts or {}) do
        local nameU = upper(name)
        local value = normalizeShift(shift)
        if nameU ~= nil and nameU ~= "" and value ~= 0 then normalized[nameU] = value end
    end
    self.configuredShifts = normalized
    self.summary = nil
    return normalized
end

function Calendar:setConfiguredCustomOverrides(overrides)
    local normalized = {}
    for name, value in pairs(overrides or {}) do
        local nameU = upper(name)
        local custom = normalizeCustomOverride(value)
        if nameU ~= nil and nameU ~= "" and custom ~= nil then normalized[nameU] = custom end
    end
    self.configuredCustomOverrides = normalized
    self.summary = nil
    return normalized
end

function Calendar:getConfiguredShifts()
    local copy = {}
    for name, shift in pairs(self.configuredShifts or {}) do copy[name] = normalizeShift(shift) end
    return copy
end

function Calendar:getConfiguredCustomOverrides()
    local copy = {}
    for name, value in pairs(self.configuredCustomOverrides or {}) do
        local custom = normalizeCustomOverride(value)
        if custom ~= nil then copy[name] = custom end
    end
    return copy
end

function Calendar:getConfiguredShift(cropName)
    return normalizeShift((self.configuredShifts or {})[upper(cropName)])
end

function Calendar:getConfiguredCustomOverride(cropName)
    return normalizeCustomOverride((self.configuredCustomOverrides or {})[upper(cropName)])
end

function Calendar:getConfiguredMode(cropName)
    local nameU = upper(cropName)
    if self:getConfiguredCustomOverride(nameU) ~= nil then return "CUSTOM" end
    if self:getConfiguredShift(nameU) ~= 0 then return "SHIFT" end
    return "DEFAULT"
end

function Calendar:parseMonthExpression(expression)
    return parseMonthExpression(expression)
end

function Calendar:maskToWindowText(mask)
    return windowListText(periodListFromMask(mask))
end

function Calendar:captureMapDefaults(force)
    if force == true and self:hasConfiguredOverrides() then
        return false, "Cannot recapture the map baseline while calendar overrides are active. Restore map defaults first."
    end
    if force == true then
        self.baselineByFruit = {}
        self.rows = {}
        self.summary = nil
        self.captured = false
        self.lastPreview = nil
    end

    local fruits = sortedFruitTypes()
    local captured = 0
    for _, fruitType in ipairs(fruits) do
        local nameU = upper(fruitType.name)
        if self.baselineByFruit[nameU] == nil then
            local seasonalData, source, initialState, initialSource = getSeasonalData(fruitType)
            if seasonalData ~= nil then
                self.baselineByFruit[nameU] = snapshotSeasonalData(
                    fruitType, seasonalData, source, initialState, initialSource)
                captured = captured + 1
            end
        end
    end

    self.captured = true
    if captured > 0 or force == true then
        self.captureGeneration = (tonumber(self.captureGeneration) or 0) + 1
    end
    self:refresh()
    if captured == 0 then
        return false, "Calendar baseline already contains every currently loaded fruit type."
    end
    return true, ("Captured map-default calendar data for %d additional fruit type(s); baseline=%d loaded=%d."):format(
        captured, countTableEntries(self.baselineByFruit), #fruits)
end

function Calendar:refresh()
    local rows = {}
    local summary = {
        loaded = 0,
        seasonal = 0,
        noData = 0,
        ok = 0,
        modified = 0,
        warnings = 0,
        errors = 0,
        information = 0,
        warningCrops = 0,
        errorCrops = 0,
        fieldCrops = 0,
        perennialCrops = 0,
        specialCrops = 0,
        technicalCrops = 0,
        candidates = 0,
        review = 0,
        blocked = 0,
        lifecycleReview = 0,
        captured = self.captured == true,
        baselineCount = countTableEntries(self.baselineByFruit),
        activeShifts = countTableEntries(self.configuredShifts),
        activeCustom = countTableEntries(self.configuredCustomOverrides),
        activeOverrides = countTableEntries(self.configuredShifts) + countTableEntries(self.configuredCustomOverrides),
    }

    for _, fruitType in ipairs(sortedFruitTypes()) do
        local row = inspectFruit(fruitType)
        rows[#rows + 1] = row
        summary.loaded = summary.loaded + 1
        if row.seasonal then summary.seasonal = summary.seasonal + 1 else summary.noData = summary.noData + 1 end
        if row.status == "OK" then summary.ok = summary.ok + 1 end
        if row.status == "MODIFIED" then summary.modified = summary.modified + 1 end
        if row.warningCount > 0 then summary.warningCrops = summary.warningCrops + 1 end
        if row.errorCount > 0 then summary.errorCrops = summary.errorCrops + 1 end
        summary.warnings = summary.warnings + row.warningCount
        summary.errors = summary.errors + row.errorCount
        summary.information = summary.information + row.infoCount

        if row.category == "FIELD" then summary.fieldCrops = summary.fieldCrops + 1 end
        if row.category == "PERENNIAL" then summary.perennialCrops = summary.perennialCrops + 1 end
        if row.category == "SPECIAL" then summary.specialCrops = summary.specialCrops + 1 end
        if row.category == "TECHNICAL" then summary.technicalCrops = summary.technicalCrops + 1 end
        if row.editability == "CANDIDATE" then summary.candidates = summary.candidates + 1 end
        if row.editability == "REVIEW" then summary.review = summary.review + 1 end
        if row.editability == "BLOCKED" then summary.blocked = summary.blocked + 1 end
        if row.lifecycleStatus == "REVIEW" or row.lifecycleStatus == "PARTIAL" or row.lifecycleStatus == "GRAPH ONLY" then
            summary.lifecycleReview = summary.lifecycleReview + 1
        end
    end

    self.rows = rows
    self.summary = summary
    return rows, summary
end

local function seasonalDataFromSnapshot(snapshot, shift)
    if snapshot == nil then return nil end
    local result = { initialState = snapshot.initialState, periods = {} }
    for period = 1, Calendar.PERIOD_COUNT do
        local sourcePeriod = shiftedPeriodIndex(period, shift)
        local baseInfo = snapshot.periods[sourcePeriod]
        if baseInfo ~= nil and baseInfo.exists == true then
            result.periods[period] = {
                plantingAllowed = baseInfo.plantingAllowed,
                isHarvestable = baseInfo.isHarvestable,
            }
            result.periods[period][baseInfo.mappingKey or "growthMapping"] = copyMapping(baseInfo.mapping)
        end
    end
    return result
end

local function collectSnapshotStates(snapshot)
    local states = {}
    if snapshot == nil then return states end
    if tonumber(snapshot.initialState) ~= nil then states[tonumber(snapshot.initialState)] = true end
    for period = 1, Calendar.PERIOD_COUNT do
        local info = snapshot.periods[period]
        for startState, endState in pairs(info ~= nil and info.mapping or {}) do
            if tonumber(startState) ~= nil then states[tonumber(startState)] = true end
            if tonumber(endState) ~= nil then states[tonumber(endState)] = true end
        end
    end
    return states
end

local function segmentSourcePeriod(startPeriod, consumed)
    return ((startPeriod - 1 + consumed) % Calendar.PERIOD_COUNT) + 1
end

local function segmentCost(snapshot, startPeriod, consumed, count, desiredPlant, desiredHarvest)
    local sourcePlant, sourceHarvest = false, false
    for offset = 0, count - 1 do
        local info = snapshot.periods[segmentSourcePeriod(startPeriod, consumed + offset)]
        sourcePlant = sourcePlant or (info ~= nil and info.plantingAllowed == true)
        sourceHarvest = sourceHarvest or (info ~= nil and info.isHarvestable == true)
    end
    local cost = math.abs(count - 1) * 2
    if sourcePlant ~= desiredPlant then cost = cost + 18 end
    if sourceHarvest ~= desiredHarvest then cost = cost + 18 end
    if count == 0 then
        cost = cost + 2
        if desiredPlant or desiredHarvest then cost = cost + 8 end
    end
    return cost
end

local function findBestPhaseWarp(snapshot, plantingMask, harvestMask)
    local desiredPlant = periodSetFromMask(plantingMask)
    local desiredHarvest = periodSetFromMask(harvestMask)
    local best = nil
    for startPeriod = 1, Calendar.PERIOD_COUNT do
        local dp = { [0] = { cost = 0, counts = {} } }
        for targetPeriod = 1, Calendar.PERIOD_COUNT do
            local nextDp = {}
            for consumed, state in pairs(dp) do
                local maxCount = math.min(4, Calendar.PERIOD_COUNT - consumed)
                for count = 0, maxCount do
                    local nextConsumed = consumed + count
                    local cost = state.cost + segmentCost(snapshot, startPeriod, consumed, count,
                        desiredPlant[targetPeriod] == true, desiredHarvest[targetPeriod] == true)
                    local existing = nextDp[nextConsumed]
                    if existing == nil or cost < existing.cost then
                        local counts = {}
                        for i, v in ipairs(state.counts) do counts[i] = v end
                        counts[targetPeriod] = count
                        nextDp[nextConsumed] = { cost = cost, counts = counts }
                    end
                end
            end
            dp = nextDp
        end
        local candidate = dp[Calendar.PERIOD_COUNT]
        if candidate ~= nil and (best == nil or candidate.cost < best.cost) then
            best = { cost = candidate.cost, counts = candidate.counts, startPeriod = startPeriod }
        end
    end
    return best
end

local function composeSegmentMapping(snapshot, startPeriod, consumed, count, states)
    local result = {}
    for state, _ in pairs(states or {}) do
        local current = state
        for offset = 0, count - 1 do
            local info = snapshot.periods[segmentSourcePeriod(startPeriod, consumed + offset)]
            local nextState = tonumber(getMappingValue(info ~= nil and info.mapping or nil, current))
            if nextState ~= nil then current = nextState end
        end
        result[state] = current
    end
    return result
end

local function seasonalDataFromCustom(snapshot, plantingMask, harvestMask)
    if snapshot == nil then return nil, nil, "No baseline snapshot." end
    local normalizedPlanting = normalizePeriodMask(plantingMask)
    local normalizedHarvest = normalizePeriodMask(harvestMask)
    if not normalizedPlanting:find("1", 1, true) then return nil, nil, "At least one planting month is required." end
    if not normalizedHarvest:find("1", 1, true) then return nil, nil, "At least one harvest month is required." end

    local plan = findBestPhaseWarp(snapshot, normalizedPlanting, normalizedHarvest)
    if plan == nil then return nil, nil, "No compatible phase-warp plan could be generated." end
    local states = collectSnapshotStates(snapshot)
    local planting = periodSetFromMask(normalizedPlanting)
    local harvest = periodSetFromMask(normalizedHarvest)
    local result = { initialState = snapshot.initialState, periods = {} }
    local consumed = 0
    local planParts = {}
    for targetPeriod = 1, Calendar.PERIOD_COUNT do
        local count = tonumber(plan.counts[targetPeriod] or 0) or 0
        local mappingKey = "growthMapping"
        if count > 0 then
            local firstInfo = snapshot.periods[segmentSourcePeriod(plan.startPeriod, consumed)]
            mappingKey = firstInfo ~= nil and firstInfo.mappingKey or mappingKey
        end
        local info = {
            plantingAllowed = planting[targetPeriod] == true,
            isHarvestable = harvest[targetPeriod] == true,
        }
        info[mappingKey] = composeSegmentMapping(snapshot, plan.startPeriod, consumed, count, states)
        result.periods[targetPeriod] = info
        planParts[#planParts + 1] = tostring(count)
        consumed = consumed + count
    end
    return result, {
        planting = normalizedPlanting,
        harvest = normalizedHarvest,
        strategy = "phaseWarpV1",
        sourceStart = plan.startPeriod,
        sourceCounts = table.concat(planParts, ","),
        cost = plan.cost,
    }, nil
end

local function simulateCustomPlantingPaths(fruitType, seasonalData, initialState, plantingMask)
    local startState = tonumber(initialState)
    if startState == nil then return false, {}, "Custom editing requires an explicit seasonal initialState in Alpha 14." end
    local harvestTargets = getLifecycleTargets(fruitType)
    if countTableEntries(harvestTargets) == 0 then return false, {}, "No exposed harvest-ready states are available for validation." end
    local failed = {}
    for _, plantingPeriod in ipairs(periodListFromMask(plantingMask)) do
        local state = startState
        local success = false
        for step = 0, 47 do
            local period = ((plantingPeriod - 1 + step) % Calendar.PERIOD_COUNT) + 1
            local periodInfo = seasonalData.periods[period]
            if harvestTargets[state] == true and periodInfo ~= nil and periodInfo.isHarvestable == true then
                success = true
                break
            end
            local mapping = getMapping(periodInfo)
            local nextState = tonumber(getMappingValue(mapping, state))
            if nextState ~= nil then state = nextState end
        end
        if not success then failed[#failed + 1] = plantingPeriod end
    end
    if #failed > 0 then
        return false, failed, "One or more selected planting months cannot reach a harvest-ready state inside the selected harvest window."
    end
    return true, failed, "ok"
end

local function applySeasonalDataToLiveTarget(target, seasonalData)
    if type(target) ~= "table" or type(seasonalData) ~= "table" or type(seasonalData.periods) ~= "table" then return false end
    target.periods = target.periods or {}
    if seasonalData.initialState ~= nil or target.initialState ~= nil then target.initialState = seasonalData.initialState end
    for period = 1, Calendar.PERIOD_COUNT do
        local sourceInfo = seasonalData.periods[period]
        if type(sourceInfo) ~= "table" then
            target.periods[period] = nil
        else
            local targetInfo = target.periods[period]
            if type(targetInfo) ~= "table" then targetInfo = {}; target.periods[period] = targetInfo end
            targetInfo.plantingAllowed = sourceInfo.plantingAllowed == true
            targetInfo.isHarvestable = sourceInfo.isHarvestable == true
            local mapping, mappingKey = getMapping(sourceInfo)
            local hasGrowthMapping = targetInfo.growthMapping ~= nil
            local hasMapping = targetInfo.mapping ~= nil
            local mappingCopy = copyMapping(mapping)
            if hasGrowthMapping then targetInfo.growthMapping = mappingCopy end
            if hasMapping then targetInfo.mapping = mappingCopy end
            if not hasGrowthMapping and not hasMapping then targetInfo[mappingKey or "growthMapping"] = mappingCopy end
        end
    end
    return true
end

local function applySnapshotToSeasonalData(target, snapshot, shift)
    if type(target) ~= "table" or snapshot == nil then return false end
    target.periods = target.periods or {}
    if snapshot.initialState ~= nil or target.initialState ~= nil then
        target.initialState = snapshot.initialState
    end
    for period = 1, Calendar.PERIOD_COUNT do
        local sourcePeriod = shiftedPeriodIndex(period, shift)
        local baseInfo = snapshot.periods[sourcePeriod]
        if baseInfo ~= nil and baseInfo.exists == true then
            local targetInfo = target.periods[period]
            if type(targetInfo) ~= "table" then
                targetInfo = {}
                target.periods[period] = targetInfo
            end
            targetInfo.plantingAllowed = baseInfo.plantingAllowed
            targetInfo.isHarvestable = baseInfo.isHarvestable
            local hasGrowthMapping = targetInfo.growthMapping ~= nil
            local hasMapping = targetInfo.mapping ~= nil
            local mappingCopy = copyMapping(baseInfo.mapping)
            if hasGrowthMapping then targetInfo.growthMapping = mappingCopy end
            if hasMapping then targetInfo.mapping = mappingCopy end
            if not hasGrowthMapping and not hasMapping then
                targetInfo[baseInfo.mappingKey or "growthMapping"] = mappingCopy
            end
        else
            target.periods[period] = nil
        end
    end
    return true
end

function Calendar:applyShiftToFruit(cropName, shift)
    local nameU = upper(cropName)
    local fruitType = getFruitTypeByName(nameU)
    local baseline = self.baselineByFruit[nameU]
    if fruitType == nil then return false, "Crop is not loaded: " .. tostring(nameU) end
    if baseline == nil then return false, "No map-default calendar baseline exists for " .. tostring(nameU) end

    local applied = 0
    for _, source in ipairs(getSeasonalSources(fruitType)) do
        if type(source.data.periods) == "table" and applySnapshotToSeasonalData(source.data, baseline, shift) then
            applied = applied + 1
        end
    end
    if applied == 0 then return false, "No writable seasonal calendar source is exposed for " .. tostring(nameU) end
    self.appliedShifts = self.appliedShifts or {}
    local normalized = normalizeShift(shift)
    if normalized == 0 then self.appliedShifts[nameU] = nil else self.appliedShifts[nameU] = normalized end
    self.appliedCustomOverrides[nameU] = nil
    return true, ("Applied %d-period calendar shift to %s across %d live source table(s)."):format(
        normalized, nameU, applied)
end

function Calendar:applyCustomToFruit(cropName, customOverride)
    local nameU = upper(cropName)
    local fruitType = getFruitTypeByName(nameU)
    local baseline = self.baselineByFruit[nameU]
    local custom = normalizeCustomOverride(customOverride)
    if fruitType == nil then return false, "Crop is not loaded: " .. tostring(nameU) end
    if baseline == nil then return false, "No map-default calendar baseline exists for " .. tostring(nameU) end
    if custom == nil then return false, "Custom planting and harvest windows are incomplete." end
    local generated, derivation, reason = seasonalDataFromCustom(baseline, custom.planting, custom.harvest)
    if generated == nil then return false, reason end
    local applied = 0
    for _, source in ipairs(getSeasonalSources(fruitType)) do
        if type(source.data.periods) == "table" and applySeasonalDataToLiveTarget(source.data, generated) then applied = applied + 1 end
    end
    if applied == 0 then return false, "No writable seasonal calendar source is exposed for " .. tostring(nameU) end
    self.appliedCustomOverrides[nameU] = custom
    self.appliedShifts[nameU] = nil
    return true, ("Applied custom calendar windows to %s across %d live source table(s)."):format(nameU, applied), derivation
end

function Calendar:applyConfiguredShifts()
    if not self.captured then self:captureMapDefaults(false) end
    local targets = {}
    for nameU, _ in pairs(self.appliedShifts or {}) do targets[nameU] = true end
    for nameU, _ in pairs(self.appliedCustomOverrides or {}) do targets[nameU] = true end
    for nameU, _ in pairs(self.configuredShifts or {}) do targets[nameU] = true end
    for nameU, _ in pairs(self.configuredCustomOverrides or {}) do targets[nameU] = true end

    local applied, restored, skipped = 0, 0, 0
    local names = {}
    for nameU, _ in pairs(targets) do names[#names + 1] = nameU end
    table.sort(names)

    for _, nameU in ipairs(names) do
        local custom = self:getConfiguredCustomOverride(nameU)
        local targetShift = normalizeShift((self.configuredShifts or {})[nameU])
        local fruitType = getFruitTypeByName(nameU)
        local row = fruitType ~= nil and inspectFruit(fruitType) or nil
        local wasApplied = normalizeShift((self.appliedShifts or {})[nameU]) ~= 0
            or normalizeCustomOverride((self.appliedCustomOverrides or {})[nameU]) ~= nil
        local mayApply = row ~= nil and row.category == "FIELD" and row.editability == "CANDIDATE"
        if custom ~= nil and mayApply and row.initialState ~= nil then
            local ok = self:applyCustomToFruit(nameU, custom)
            if ok then applied = applied + 1 else skipped = skipped + 1 end
        elseif custom == nil and targetShift ~= 0 and mayApply then
            local ok = self:applyShiftToFruit(nameU, targetShift)
            if ok then
                self.appliedCustomOverrides[nameU] = nil
                applied = applied + 1
            else skipped = skipped + 1 end
        elseif custom == nil and targetShift == 0 and wasApplied then
            local ok = self:applyShiftToFruit(nameU, 0)
            if ok then
                self.appliedCustomOverrides[nameU] = nil
                restored = restored + 1
            else skipped = skipped + 1 end
        elseif custom ~= nil or targetShift ~= 0 then
            skipped = skipped + 1
        end
    end
    self:refresh()
    return true, ("Applied configured calendar overrides: applied=%d restored=%d skipped=%d."):format(applied, restored, skipped)
end

local function getFieldFruitName(field)
    if field == nil or field.fieldState == nil then return nil end
    local fruitIndex = field.fieldState.fruitTypeIndex
    if fruitIndex == nil or fruitIndex == 0 or g_fruitTypeManager == nil then return nil end
    local fruitType = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    return fruitType ~= nil and upper(fruitType.name) or nil
end

local function getImpactFieldId(field, fallback)
    if field ~= nil and field.farmland ~= nil and field.farmland.id ~= nil then return field.farmland.id end
    return fallback or "?"
end

local function getMissionFruitName(mission)
    if mission == nil then return nil end
    if mission.fruitType ~= nil and mission.fruitType.name ~= nil then return upper(mission.fruitType.name) end
    local index = mission.fruitTypeIndex or mission.fruitIndex
    if index ~= nil and g_fruitTypeManager ~= nil then
        local fruitType = g_fruitTypeManager:getFruitTypeByIndex(index)
        if fruitType ~= nil then return upper(fruitType.name) end
    end
    return nil
end

local function missionIsActive(mission)
    if mission == nil then return false end
    if mission.getWasStarted ~= nil then
        local ok, value = pcall(mission.getWasStarted, mission)
        if ok and value == true then return true end
    end
    return mission.farmId ~= nil or mission.activeMissionId ~= nil
end

function Calendar:scanImpact(cropName)
    local wanted = upper(cropName)
    local impact = {
        fields = 0, npcFields = 0, playerFields = 0, fieldIds = {},
        missions = 0, activeMissions = 0, availableMissions = 0,
    }
    if g_fieldManager ~= nil and g_fieldManager.getFields ~= nil then
        for index, field in pairs(g_fieldManager:getFields() or {}) do
            if getFieldFruitName(field) == wanted then
                impact.fields = impact.fields + 1
                local farmId = field ~= nil and field.farmland ~= nil and field.farmland.farmId or 0
                if farmId == 0 then impact.npcFields = impact.npcFields + 1 else impact.playerFields = impact.playerFields + 1 end
                if #impact.fieldIds < 12 then impact.fieldIds[#impact.fieldIds + 1] = tostring(getImpactFieldId(field, index)) end
            end
        end
    end
    if g_missionManager ~= nil and g_missionManager.getMissions ~= nil then
        for _, mission in ipairs(g_missionManager:getMissions() or {}) do
            if getMissionFruitName(mission) == wanted then
                impact.missions = impact.missions + 1
                if missionIsActive(mission) then impact.activeMissions = impact.activeMissions + 1
                else impact.availableMissions = impact.availableMissions + 1 end
            end
        end
    end
    return impact
end

function Calendar:previewShift(cropName, shift)
    if not self.captured then self:captureMapDefaults(false) end
    self:refresh()
    local nameU = upper(cropName)
    local fruitType = getFruitTypeByName(nameU)
    local currentRow = self:getRow(nameU)
    local baseline = self.baselineByFruit[nameU]
    local normalizedShift = normalizeShift(shift)
    if fruitType == nil or currentRow == nil then return nil, "Crop is not loaded: " .. tostring(nameU) end
    if baseline == nil then return nil, "No map-default calendar baseline exists for " .. tostring(nameU) end

    local proposedData = seasonalDataFromSnapshot(baseline, normalizedShift)
    local proposedRow = inspectFruit(fruitType, proposedData, "mapDefaultShiftPreview", baseline.initialState, baseline.initialSource)
    local defaultRow = inspectFruit(fruitType, seasonalDataFromSnapshot(baseline, 0), "mapDefaultPreview", baseline.initialState, baseline.initialSource)
    local impact = self:scanImpact(nameU)
    local applyAllowed = currentRow.category == "FIELD"
        and currentRow.editability == "CANDIDATE"
        and proposedRow.errorCount == 0
        and proposedRow.warningCount == 0
    local reason = nil
    if currentRow.category ~= "FIELD" then reason = "Only ordinary FIELD crops may be changed in Alpha 14."
    elseif currentRow.editability ~= "CANDIDATE" then reason = "This crop requires lifecycle review before writable editing."
    elseif proposedRow.errorCount > 0 or proposedRow.warningCount > 0 then reason = "The shifted lifecycle did not pass structural validation." end

    local preview = {
        kind = "SHIFT", crop = nameU, shift = normalizedShift, currentShift = self:getConfiguredShift(nameU),
        current = currentRow, default = defaultRow, proposed = proposedRow, impact = impact,
        applyAllowed = applyAllowed, blockReason = reason,
    }
    self.lastPreview = preview
    return preview, "ok"
end

function Calendar:previewCustom(cropName, plantingMask, harvestMask)
    if not self.captured then self:captureMapDefaults(false) end
    self:refresh()
    local nameU = upper(cropName)
    local fruitType = getFruitTypeByName(nameU)
    local currentRow = self:getRow(nameU)
    local baseline = self.baselineByFruit[nameU]
    local custom = normalizeCustomOverride({ planting = plantingMask, harvest = harvestMask })
    if fruitType == nil or currentRow == nil then return nil, "Crop is not loaded: " .. tostring(nameU) end
    if baseline == nil then return nil, "No map-default calendar baseline exists for " .. tostring(nameU) end
    if custom == nil then return nil, "Select at least one planting month and one harvest month." end

    local proposedData, derivation, deriveReason = seasonalDataFromCustom(baseline, custom.planting, custom.harvest)
    if proposedData == nil then return nil, deriveReason end
    local proposedRow = inspectFruit(fruitType, proposedData, "customPhaseWarpPreview", baseline.initialState, baseline.initialSource)
    local defaultRow = inspectFruit(fruitType, seasonalDataFromSnapshot(baseline, 0), "mapDefaultPreview", baseline.initialState, baseline.initialSource)
    local impact = self:scanImpact(nameU)
    local pathOk, failedPeriods, pathReason = simulateCustomPlantingPaths(fruitType, proposedData, baseline.initialState, custom.planting)
    local applyAllowed = currentRow.category == "FIELD"
        and currentRow.editability == "CANDIDATE"
        and baseline.initialState ~= nil
        and proposedRow.errorCount == 0
        and proposedRow.warningCount == 0
        and pathOk == true
    local reason = nil
    if currentRow.category ~= "FIELD" then reason = "Only ordinary FIELD crops may use custom windows in Alpha 14."
    elseif currentRow.editability ~= "CANDIDATE" then reason = "This crop requires lifecycle review before writable editing."
    elseif baseline.initialState == nil then reason = "Custom editing requires an explicit seasonal initialState in Alpha 14; whole-lifecycle shifting remains available."
    elseif proposedRow.errorCount > 0 or proposedRow.warningCount > 0 then reason = "The generated lifecycle did not pass structural validation."
    elseif pathOk ~= true then reason = pathReason end

    local preview = {
        kind = "CUSTOM", crop = nameU, custom = custom,
        currentShift = self:getConfiguredShift(nameU), currentCustom = self:getConfiguredCustomOverride(nameU),
        current = currentRow, default = defaultRow, proposed = proposedRow, impact = impact,
        derivation = derivation, failedPlantingPeriods = failedPeriods,
        applyAllowed = applyAllowed, blockReason = reason,
    }
    self.lastPreview = preview
    return preview, "ok"
end

function Calendar:hasMatchingCustomPreview(cropName, plantingMask, harvestMask)
    local preview = self.lastPreview
    local custom = normalizeCustomOverride({ planting = plantingMask, harvest = harvestMask })
    if preview == nil or preview.kind ~= "CUSTOM" or custom == nil then return false end
    return preview.crop == upper(cropName)
        and customOverridesEqual(preview.custom, custom)
        and preview.applyAllowed == true
end

function Calendar:hasMatchingPreview(cropName, shift)
    local preview = self.lastPreview
    if preview == nil then return false end
    return preview.crop == upper(cropName)
        and tonumber(preview.shift or 0) == normalizeShift(shift)
        and preview.applyAllowed == true
end

function Calendar:buildPreviewText(preview)
    if preview == nil then return "No calendar preview is available." end
    local impact = preview.impact or {}
    local boardActive = tonumber(preview.contractBoard ~= nil and preview.contractBoard.active or 0) or 0
    local boardAvailable = tonumber(preview.contractBoard ~= nil and preview.contractBoard.available or 0) or 0
    local boardTotal = tonumber(preview.contractBoard ~= nil and preview.contractBoard.total or 0) or 0
    local resultLine = preview.applyAllowed
        and ("APPLY ELIGIBLE. Field states stay unchanged; %d available contract(s) will be rebuilt."):format(boardAvailable)
        or ("PREVIEW ONLY: " .. tostring(preview.blockReason or "not eligible"))

    local lines = {}
    if preview.kind == "CUSTOM" then
        lines[#lines + 1] = ("CUSTOM CALENDAR PREVIEW: %s"):format(preview.crop)
        lines[#lines + 1] = ("Default: P=%s H=%s"):format(preview.default.plantingText or "-", preview.default.harvestText or "-")
        lines[#lines + 1] = ("Current: P=%s H=%s -> Proposed: P=%s H=%s"):format(
            preview.current.plantingText or "-", preview.current.harvestText or "-",
            preview.proposed.plantingText or "-", preview.proposed.harvestText or "-")
        lines[#lines + 1] = ("Validation: %s / %s | phase-warp cost=%s"):format(
            preview.proposed.status or "UNKNOWN", preview.proposed.lifecycleStatus or "UNKNOWN",
            tostring(preview.derivation ~= nil and preview.derivation.cost or "?"))
    else
        lines[#lines + 1] = ("CALENDAR SHIFT PREVIEW: %s %+d PERIOD(S)"):format(preview.crop, preview.shift or 0)
        lines[#lines + 1] = ("Default: P=%s H=%s"):format(preview.default.plantingText or "-", preview.default.harvestText or "-")
        lines[#lines + 1] = ("Current: P=%s H=%s -> Proposed: P=%s H=%s"):format(
            preview.current.plantingText or "-", preview.current.harvestText or "-",
            preview.proposed.plantingText or "-", preview.proposed.harvestText or "-")
        lines[#lines + 1] = ("Validation: %s / %s"):format(preview.proposed.status or "UNKNOWN", preview.proposed.lifecycleStatus or "UNKNOWN")
    end
    lines[#lines + 1] = ("Impact: fields=%d (player=%d NPC=%d) | crop contracts=%d (active=%d available=%d)"):format(
        impact.fields or 0, impact.playerFields or 0, impact.npcFields or 0,
        impact.missions or 0, impact.activeMissions or 0, impact.availableMissions or 0)
    lines[#lines + 1] = ("Contract board: active=%d | rebuild=%d | total=%d"):format(boardActive, boardAvailable, boardTotal)
    lines[#lines + 1] = resultLine
    return table.concat(lines, "\n")
end

function Calendar:commitShift(cropName, shift)
    local preview, message = self:previewShift(cropName, shift)
    if preview == nil then return false, message end
    if not preview.applyAllowed then return false, preview.blockReason or "Calendar shift is preview-only for this crop.", preview end
    if (preview.impact.activeMissions or 0) > 0 then
        return false, "Calendar apply blocked because this crop has an accepted/active contract.", preview
    end
    local ok, applyMessage = self:applyShiftToFruit(preview.crop, preview.shift)
    if not ok then return false, applyMessage, preview end
    if preview.shift == 0 then
        self.configuredShifts[preview.crop] = nil
        self.configuredCustomOverrides[preview.crop] = nil
    else
        self.configuredShifts[preview.crop] = preview.shift
        self.configuredCustomOverrides[preview.crop] = nil
    end
    self.lastPreview = nil
    self:refresh()
    return true, applyMessage, preview
end

function Calendar:commitCustom(cropName, plantingMask, harvestMask)
    local preview, message = self:previewCustom(cropName, plantingMask, harvestMask)
    if preview == nil then return false, message end
    if not preview.applyAllowed then return false, preview.blockReason or "Custom calendar preview is not eligible.", preview end
    if (preview.impact.activeMissions or 0) > 0 then
        return false, "Calendar apply blocked because this crop has an accepted/active contract.", preview
    end
    local ok, applyMessage = self:applyCustomToFruit(preview.crop, preview.custom)
    if not ok then return false, applyMessage, preview end
    self.configuredCustomOverrides[preview.crop] = preview.custom
    self.configuredShifts[preview.crop] = nil
    self.lastPreview = nil
    self:refresh()
    return true, applyMessage, preview
end

function Calendar:getDefaultMasks(cropName)
    local baseline = self.baselineByFruit[upper(cropName)]
    if baseline == nil then return normalizePeriodMask(nil), normalizePeriodMask(nil) end
    local planting, harvest = {}, {}
    for period = 1, Calendar.PERIOD_COUNT do
        local info = baseline.periods[period]
        if info ~= nil and info.plantingAllowed == true then planting[#planting + 1] = period end
        if info ~= nil and info.isHarvestable == true then harvest[#harvest + 1] = period end
    end
    return periodMaskFromPeriods(planting), periodMaskFromPeriods(harvest)
end

function Calendar:getRows()
    if self.summary == nil then self:refresh() end
    return self.rows or {}
end

function Calendar:getSummary()
    if self.summary == nil then self:refresh() end
    return self.summary or {}
end

function Calendar:getRow(cropName)
    local wanted = upper(cropName)
    for _, row in ipairs(self:getRows()) do
        if row.name == wanted then return row end
    end
    return nil
end

function Calendar:buildGuiText()
    self:refresh()
    local summary = self:getSummary()
    local lines = {
        "CROP CALENDAR LIFECYCLE SHIFTS",
        "",
        ("Loaded / seasonal:       %d / %d"):format(summary.loaded or 0, summary.seasonal or 0),
        ("Warnings / errors:       %d / %d"):format(summary.warnings or 0, summary.errors or 0),
        ("Candidate / review:      %d / %d"):format(summary.candidates or 0, summary.review or 0),
        ("Field / perennial:       %d / %d"):format(summary.fieldCrops or 0, summary.perennialCrops or 0),
        ("Special / technical:     %d / %d"):format(summary.specialCrops or 0, summary.technicalCrops or 0),
        ("Map-default snapshots:   %d"):format(summary.baselineCount or 0),
        ("Active shifts / custom:   %d / %d"):format(summary.activeShifts or 0, summary.activeCustom or 0),
        "",
        string.format("%-14s %-9s %-13s %-13s %-9s %-8s", "Crop", "Type", "Plant", "Harvest", "Lifecycle", "Status"),
        string.rep("-", 78),
    }

    local maxRows = 22
    local rows = self:getRows()
    for index, row in ipairs(rows) do
        if index > maxRows then
            lines[#lines + 1] = ("... %d more crop(s). Run ccoCalendarReport for the full list."):format(#rows - maxRows)
            break
        end
        lines[#lines + 1] = string.format("%-14s %-9s %-13s %-13s %-9s %-8s",
            tostring(row.name):sub(1, 14),
            tostring(row.category or "UNKNOWN"):sub(1, 9),
            tostring(row.plantingText or "-"):sub(1, 13),
            tostring(row.harvestText or "-"):sub(1, 13),
            tostring(row.lifecycleStatus or "UNKNOWN"):sub(1, 9),
            tostring(row.status or "UNKNOWN"))
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Select a FIELD crop, choose SHIFT or CUSTOM WINDOWS, run PREVIEW, then APPLY."
    lines[#lines + 1] = "Custom windows use a validated phase-warp of the captured map lifecycle; inferred-initial crops remain shift-only in Alpha 14."
    return table.concat(lines, "\n")
end

function Calendar:printReport(cropName)
    self:refresh()
    local wanted = upper(cropName)
    local summary = self:getSummary()
    print(("CCO CALENDAR: loaded=%d seasonal=%d noData=%d warningCrops=%d errorCrops=%d candidates=%d review=%d baseline=%d"):format(
        summary.loaded or 0, summary.seasonal or 0, summary.noData or 0,
        summary.warningCrops or 0, summary.errorCrops or 0,
        summary.candidates or 0, summary.review or 0, summary.baselineCount or 0))

    local found = false
    for _, row in ipairs(self:getRows()) do
        if wanted == nil or wanted == "" or row.name == wanted then
            found = true
            print(("CCO CALENDAR: %-16s planting=%-20s harvest=%-20s periods=%d transitions=%d initial=%s initialSource=%s source=%s category=%s edit=%s lifecycle=%s status=%s mode=%s shift=%+d baselineChanged=%s"):format(
                row.name,
                row.plantingText or "-",
                row.harvestText or "-",
                row.periodCount or 0,
                row.transitionCount or 0,
                tostring(row.initialStateDisplay),
                tostring(row.initialSource or "inferred"),
                tostring(row.source),
                tostring(row.category),
                tostring(row.editability),
                tostring(row.lifecycleStatus),
                tostring(row.status),
                tostring(row.configuredMode or "DEFAULT"),
                tonumber(row.configuredShift or 0) or 0,
                tostring(row.changedFromBaseline)))
            for _, issue in ipairs(row.issues or {}) do
                print("CCO CALENDAR:   - " .. tostring(issue))
            end
            if wanted ~= nil and wanted ~= "" then
                print("CCO CALENDAR:   categoryEvidence=" .. tostring(row.categoryReason))
                print(("CCO CALENDAR:   lifecycleTargets harvest=%d terminal=%d sourceStates=%d reachable=%d deadEnds=%d"):format(
                    row.harvestTargetCount or 0,
                    row.terminalTargetCount or 0,
                    row.lifecycleSourceStateCount or 0,
                    row.lifecycleReachableStateCount or 0,
                    #(row.lifecycleDeadEndStates or {})))
                for _, note in ipairs(row.notes or {}) do
                    print("CCO CALENDAR:   info: " .. tostring(note))
                end
            end
        end
    end

    if wanted ~= nil and wanted ~= "" and not found then
        print("CCO CALENDAR: crop not found: " .. tostring(wanted))
    end
end
