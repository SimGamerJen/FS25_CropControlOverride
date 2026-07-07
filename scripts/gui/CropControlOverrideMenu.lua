-- FS25_CropControlOverride
-- Custom GUI screen using FS25-style SmoothList table layout.

local CCO_GUI_MOD_DIRECTORY = g_currentModDirectory or ""

CropControlOverrideMenu = {}

local CropControlOverrideMenu_mt = Class(CropControlOverrideMenu, ScreenElement)

function CropControlOverrideMenu.new(target, customMt)
    local self = ScreenElement.new(target, customMt or CropControlOverrideMenu_mt)
    self.returnScreenName = ""
    self.pendingTitle = "Crop Control Override"
    self.pendingBody = ""
    self.currentTopic = "rules"
    self.currentPage = 1
    self.ruleRows = {}
    self.selectedRowIndex = nil
    self.selectedRow = nil
    self.stagedRule = nil
    self.stagedDirty = false
    self.forceApplyArmed = false
    self.resetConfirmArmed = false
    self.resetMode = "cultivated"
    self.resetScopeIndex = 1
    self.resetScopes = {"ALL"}
    self.tableTopic = false
    self.showNotLoaded = false
    self.menuBackEventId = nil
    self.suppressTabCallback = false
    self.suppressSelectorCallbacks = false
    self.editControlsInitialised = false
    self.defaultResetNpcFields = true
    return self
end

function CropControlOverrideMenu.register(modDirectory)
    if g_gui == nil then
        print("CCO GUI: g_gui is not available; cannot register custom screen")
        return nil
    end

    if CropControlOverrideMenu.INSTANCE ~= nil then
        return CropControlOverrideMenu.INSTANCE
    end

    local controller = CropControlOverrideMenu.new()

    local baseDir = modDirectory
    if baseDir == nil or baseDir == "" then
        baseDir = CCO_GUI_MOD_DIRECTORY
    end
    if (baseDir == nil or baseDir == "") and CropControlOverride ~= nil then
        baseDir = CropControlOverride.MOD_DIRECTORY
    end
    if baseDir == nil then
        baseDir = ""
    end

    local lastChar = baseDir:sub(-1)
    if baseDir ~= "" and lastChar ~= "/" and lastChar ~= "\\" then
        baseDir = baseDir .. "/"
    end

    local profiles = baseDir .. "gui/guiProfiles.xml"
    if fileExists == nil or fileExists(profiles) then
        pcall(function() g_gui:loadProfiles(profiles) end)
    end

    local filename = baseDir .. "gui/CropControlOverrideMenu.xml"
    print("CCO GUI: loading custom screen from " .. tostring(filename))

    if fileExists ~= nil and not fileExists(filename) then
        print("CCO GUI: XML file does not exist at " .. tostring(filename))
        return nil
    end

    local ok, result = pcall(function()
        return g_gui:loadGui(filename, "CropControlOverrideMenu", controller)
    end)

    if not ok then
        print("CCO GUI: failed to load custom screen: " .. tostring(result))
        return nil
    end

    if g_gui.guis == nil or g_gui.guis.CropControlOverrideMenu == nil then
        print("CCO GUI: loadGui returned but screen was not registered")
        return nil
    end

    CropControlOverrideMenu.INSTANCE = controller
    print("CCO GUI: registered custom screen CropControlOverrideMenu")
    return controller
end

function CropControlOverrideMenu.show(title, body, modDirectory, topic, page)
    local controller = CropControlOverrideMenu.INSTANCE or CropControlOverrideMenu.register(modDirectory)
    if controller == nil then
        return false
    end

    controller.currentTopic = topic or controller.currentTopic or "status"
    controller.currentPage = tonumber(page or controller.currentPage or 1) or 1
    controller:setContent(title, body, topic)

    local ok, result = pcall(function()
        return g_gui:showGui("CropControlOverrideMenu")
    end)

    if not ok then
        print("CCO GUI: failed to show custom screen: " .. tostring(result))
        return false
    end

    return true
end

local TABLE_TOPICS = {
    rules = true,
    disabled = true,
    limited = true,
    blockedrules = true,
    ["blocked-rules"] = true,
    undiscovered = true,
}

local TAB_TOPIC_INDEX = {
    rules = 1,
    disabled = 2,
    blockedrules = 3,
    ["blocked-rules"] = 3,
    limited = 4,
    blocked = 5,
    validation = 5,
    status = 6,
    help = 7,
}

local TAB_INDEX_TOPIC = {
    [1] = "rules",
    [2] = "disabled",
    [3] = "blockedrules",
    [4] = "limited",
    [5] = "blocked",
    [6] = "status",
    [7] = "help",
}

local TAB_TEXTS = {
    "ALL RULES",
    "DISABLED",
    "NPC DISABLED",
    "SIZE LIMITED",
    "VALIDATION",
    "SUMMARY",
    "HELP",
}


local function guiModeFromTopic(topic)
    topic = topic ~= nil and tostring(topic):lower() or "rules"
    if topic == "disabled" then return "disabled" end
    if topic == "limited" then return "limited" end
    if topic == "blockedrules" or topic == "blocked-rules" then return "blockedrules" end
    if topic == "undiscovered" then return "undiscovered" end
    return "rules"
end

function buildTopicContent(topic, page)
    topic = topic ~= nil and tostring(topic):lower() or "rules"
    if CropControlOverride == nil then
        return "Crop Control Override", "CropControlOverride backend is not available.", "status", 1
    end

    if topic == "status" then
        return "Crop Control Override - Summary", CropControlOverride:buildGuiStatusText(), "status", 1
    elseif topic == "rules" then
        return "Crop Control Override - Configured Rules", CropControlOverride:buildGuiRuleListText("rules", page), "rules", page or 1
    elseif topic == "disabled" then
        return "Crop Control Override - Disabled Crops", CropControlOverride:buildGuiRuleListText("disabled", page), "disabled", page or 1
    elseif topic == "limited" then
        return "Crop Control Override - Size-Limited Crops", CropControlOverride:buildGuiRuleListText("limited", page), "limited", page or 1
    elseif topic == "blockedrules" or topic == "blocked-rules" then
        return "Crop Control Override - NPC Disabled Rules", CropControlOverride:buildGuiRuleListText("blockedrules", page), "blockedrules", page or 1
    elseif topic == "blocked" or topic == "validation" then
        return "Crop Control Override - Validation", CropControlOverride:buildGuiBlockedText(), "blocked", 1
    elseif topic == "undiscovered" then
        return "Crop Control Override - Undiscovered Rules", CropControlOverride:buildGuiRuleListText("undiscovered", page), "undiscovered", page or 1
    elseif topic == "help" then
        return "Crop Control Override - Help", CropControlOverride:buildGuiHelpText(), "help", 1
    end

    return "Crop Control Override - Help", "Unknown topic: " .. tostring(topic) .. "\n\n" .. CropControlOverride:buildGuiHelpText(), "help", 1
end


local function splitLines(text)
    local lines = {}
    text = tostring(text or "")
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    return lines
end


local HA_TO_ACRES = 2.47105

local function formatHaAcCompact(ha)
    local n = tonumber(ha or 0) or 0
    return string.format("%.1fha/%.1fac", n, n * HA_TO_ACRES)
end

local function numericFromHaAc(value)
    local text = tostring(value or "")
    local n = tonumber(text:match("^%s*([%d%.%-]+)"))
    return n or tonumber(value or 0) or 0
end

local function parseRuleRows(text)
    local rows = {}
    for _, line in ipairs(splitLines(text)) do
        local crop, enabled, npc, maxHa, loaded, status

        -- Alpha.47 changed NPC policy display from "mapDefault" to "Map Default".
        -- The GUI table is still populated from the text report, so support this
        -- multi-word display value explicitly instead of dropping those rows.
        crop, enabled, npc, maxHa, loaded, status = line:match("^(%S+)%s+(%S+)%s+(Map Default)%s+(%S+)%s+(%S+)%s+(.+)$")

        if crop == nil then
            crop, enabled, npc, maxHa, loaded, status = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.+)$")
        end

        if crop ~= nil
            and crop ~= "Crop"
            and crop ~= "Crop Type"
            and crop ~= "All"
            and crop ~= "Disabled"
            and crop ~= "Size-limited"
            and crop ~= "NPC-disabled"
            and crop ~= "Configured"
            and crop ~= "Page"
            and crop ~= "Shown"
            and crop ~= "Read-only"
            and crop ~= "Read%-only"
            and (enabled == "Yes" or enabled == "No" or enabled == "ON" or enabled == "OFF")
            and (loaded == "Yes" or loaded == "No")
            and not line:find("^%-+$") then
            table.insert(rows, {
                crop = crop,
                enabled = enabled,
                npc = npc,
                maxHa = maxHa,
                loaded = loaded,
                status = tostring(status or ""):match("^%s*(.-)%s*$"),
            })
        end
    end
    return rows
end


local function filterRuleRows(rows, showNotLoaded)
    if showNotLoaded == true then
        return rows or {}
    end

    local filtered = {}
    for _, row in ipairs(rows or {}) do
        if tostring(row.loaded or "") ~= "No" then
            table.insert(filtered, row)
        end
    end
    return filtered
end


function CropControlOverrideMenu:getActiveTabIndex()
    local topic = self.currentTopic or "rules"
    return TAB_TOPIC_INDEX[topic] or 1
end

function CropControlOverrideMenu:setupTabs()
    local idx = self:getActiveTabIndex()

    self.suppressTabCallback = true
    -- The old fs25_subCategorySelectorTabbed MultiTextOption caused a TextElement
    -- stack overflow on some FS25 builds when this screen opened from a mod.
    -- The explicit tab buttons above remain the supported navigation path.
    if self.subCategoryPaging ~= nil then
        pcall(function() self.subCategoryPaging:setVisible(false) end)
    end
    self.suppressTabCallback = false

    if self.subCategoryTabs ~= nil then
        for i, tab in pairs(self.subCategoryTabs) do
            if tab ~= nil then
                tab:setVisible(true)
                local bg = tab.getDescendantByName ~= nil and tab:getDescendantByName("background") or nil
                if bg ~= nil then
                    bg.getIsSelected = function()
                        return i == self:getActiveTabIndex()
                    end
                end
                tab.getIsSelected = function()
                    return i == self:getActiveTabIndex()
                end
            end
        end
    end

    if self.subCategoryBox ~= nil then
        self.subCategoryBox:invalidateLayout()
    end
end

function CropControlOverrideMenu:updateTabs()
    local idx = self:getActiveTabIndex()

    if self.subCategoryPaging ~= nil then
        pcall(function() self.subCategoryPaging:setVisible(false) end)
    end

    if self.subCategoryTabs ~= nil then
        for _, tab in pairs(self.subCategoryTabs) do
            if tab ~= nil and tab.invalidateLayout ~= nil then
                tab:invalidateLayout()
            end
        end
    end
end

function CropControlOverrideMenu:updateSubCategoryPages(subCategoryIndex)
    if self.suppressTabCallback then
        return
    end

    local idx = tonumber(subCategoryIndex)
    if idx == nil and self.subCategoryPaging ~= nil and self.subCategoryPaging.getState ~= nil then
        idx = self.subCategoryPaging:getState()
    end
    idx = idx or self:getActiveTabIndex()

    local topic = TAB_INDEX_TOPIC[idx] or "rules"
    self:showTopic(topic, 1)
end

function CropControlOverrideMenu:onCreate()
end

function CropControlOverrideMenu:onGuiSetupFinished()
    CropControlOverrideMenu:superClass().onGuiSetupFinished(self)

    self:setupTabs()

    if self.ruleList ~= nil then
        self.ruleList:setDataSource(self)
        self.ruleList:setDelegate(self)
    end

    self:updateContent()
end


function CropControlOverrideMenu:initialiseEditControls()
    if self.editControlsInitialised == true then
        return
    end

    self.suppressSelectorCallbacks = true

    if self.editEnabledOption ~= nil then
        if self.editEnabledOption.setTexts ~= nil then
            self.editEnabledOption:setTexts({"OFF", "ON"})
        end
        if self.editEnabledOption.setState ~= nil then
            self.editEnabledOption:setState(1, true)
        end
        if self.editEnabledOption.setDisabled ~= nil then
            self.editEnabledOption:setDisabled(true)
        end
    end

    if self.editResetOption ~= nil then
        if self.editResetOption.setTexts ~= nil then
            self.editResetOption:setTexts({"OFF", "ON"})
        end
        if self.editResetOption.setState ~= nil then
            self.editResetOption:setState(1, true)
        end
        if self.editResetOption.setDisabled ~= nil then
            self.editResetOption:setDisabled(true)
        end
    end

    if self.editNpcOption ~= nil then
        if self.editNpcOption.setTexts ~= nil then
            self.editNpcOption:setTexts({"Map Default", "ON", "OFF"})
        end
        if self.editNpcOption.setState ~= nil then
            self.editNpcOption:setState(1, true)
        end
        if self.editNpcOption.setDisabled ~= nil then
            self.editNpcOption:setDisabled(true)
        end
    end

    self.suppressSelectorCallbacks = false
    self.editControlsInitialised = true
end

function CropControlOverrideMenu:setEnabledSelectorState(enabled, disabled)
    local option = self.editEnabledOption
    if option == nil then
        return
    end

    self.suppressSelectorCallbacks = true

    local state = enabled == true and 2 or 1
    local currentState = nil
    if option.getState ~= nil then
        local ok, result = pcall(function()
            return option:getState()
        end)
        if ok then
            currentState = tonumber(result)
        end
    end

    if option.setState ~= nil and currentState ~= state then
        option:setState(state, true)
    end

    if option.setDisabled ~= nil then
        option:setDisabled(disabled == true)
    end

    self.suppressSelectorCallbacks = false
end

function CropControlOverrideMenu:setResetSelectorState(enabled, disabled)
    local option = self.editResetOption
    if option == nil then
        return
    end

    self.suppressSelectorCallbacks = true

    local state = enabled == true and 2 or 1
    local currentState = nil
    if option.getState ~= nil then
        local ok, result = pcall(function()
            return option:getState()
        end)
        if ok then
            currentState = tonumber(result)
        end
    end

    if option.setState ~= nil and currentState ~= state then
        option:setState(state, true)
    end

    if option.setDisabled ~= nil then
        option:setDisabled(disabled == true)
    end

    self.suppressSelectorCallbacks = false
end

function CropControlOverrideMenu:setNpcSelectorState(npcValue, disabled)
    local option = self.editNpcOption
    if option == nil then
        return
    end

    self.suppressSelectorCallbacks = true

    local state = 1
    if npcValue == "yes" then
        state = 2
    elseif npcValue == "no" then
        state = 3
    end

    local currentState = nil
    if option.getState ~= nil then
        local ok, result = pcall(function()
            return option:getState()
        end)
        if ok then
            currentState = tonumber(result)
        end
    end

    if option.setState ~= nil and currentState ~= state then
        option:setState(state, true)
    end

    if option.setDisabled ~= nil then
        option:setDisabled(disabled == true)
    end

    self.suppressSelectorCallbacks = false
end

function CropControlOverrideMenu:onOpen()
    CropControlOverrideMenu:superClass().onOpen(self)
    self:registerBackAction()
    self:setupTabs()
    self:initialiseEditControls()
    self:updateContent()
end

function CropControlOverrideMenu:onClose()
    self:removeBackAction()
    CropControlOverrideMenu:superClass().onClose(self)
end

function CropControlOverrideMenu:registerBackAction()
    if self.menuBackEventId ~= nil then
        return
    end

    if g_inputBinding ~= nil and InputAction ~= nil and InputAction.MENU_BACK ~= nil then
        local ok, result1, result2 = pcall(function()
            return g_inputBinding:registerActionEvent(InputAction.MENU_BACK, self, self.onMenuBackAction, false, true, false, true)
        end)

        -- GIANTS builds/mod examples differ here: some return (success, eventId), others effectively return eventId.
        local eventId = nil
        if ok then
            if type(result2) == "number" then
                eventId = result2
            elseif type(result1) == "number" then
                eventId = result1
            end
        end

        if eventId ~= nil then
            self.menuBackEventId = eventId
            if g_inputBinding.setActionEventTextVisibility ~= nil then
                g_inputBinding:setActionEventTextVisibility(eventId, false)
            end
            if CropControlOverride ~= nil and CropControlOverride.debug then print("CCO GUI: MENU_BACK action registered for custom screen") end
        else
            if CropControlOverride ~= nil and CropControlOverride.debug then print("CCO GUI: MENU_BACK action registration did not return an event id; using GUI close fallback only") end
        end
    end
end

function CropControlOverrideMenu:removeBackAction()
    if self.menuBackEventId ~= nil and g_inputBinding ~= nil and g_inputBinding.removeActionEvent ~= nil then
        pcall(function()
            g_inputBinding:removeActionEvent(self.menuBackEventId)
        end)
    end
    self.menuBackEventId = nil
end

function CropControlOverrideMenu:onMenuBackAction(actionName, inputValue, callbackState, isAnalog)
    self:onClickBack()
end

function CropControlOverrideMenu:setContent(title, body, topic)
    self.pendingTitle = title or "Crop Control Override"
    self.pendingBody = body or ""
    self.tableTopic = TABLE_TOPICS[topic or self.currentTopic or ""] == true
    local parsedRows = {}
    if self.tableTopic then
        if CropControlOverride ~= nil and CropControlOverride.getGuiRuleRows ~= nil then
            parsedRows = CropControlOverride:getGuiRuleRows(guiModeFromTopic(topic or self.currentTopic or "rules"))
        else
            parsedRows = parseRuleRows(self.pendingBody)
        end
    end
    self.ruleRows = self.tableTopic and filterRuleRows(parsedRows, self.showNotLoaded) or {}
    self.selectedRowIndex = nil
    self.selectedRow = nil
    self.stagedRule = nil
    self.stagedDirty = false
    self.forceApplyArmed = false
    self:updateContent()
end


function CropControlOverrideMenu:getEmptyStateText()
    local topic = self.currentTopic or ""
    if topic == "limited" then
        return "No size-limited crops are configured for this save."
    elseif topic == "disabled" then
        return "No disabled crops are configured for this save."
    elseif topic == "blockedrules" then
        return "No crops are currently disabled for NPC use."
    elseif topic == "undiscovered" then
        return "All configured crops are currently loaded on this map/save."
    end
    return "No configured crop rules match this view."
end



local function ccoValueToBool(value)
    local s = tostring(value or ""):lower()
    return s == "yes" or s == "true" or s == "1" or s == "on"
end

local function ccoBoolText(value)
    return value and "ON" or "OFF"
end

local function ccoNpcToStage(value)
    local s = tostring(value or ""):lower()
    if s == "map default" or s == "mapdefault" then
        return "mapDefault"
    elseif s == "yes" or s == "true" or s == "1" or s == "on" then
        return "yes"
    elseif s == "no" or s == "false" or s == "0" or s == "off" then
        return "no"
    end
    return "no"
end

local function ccoNpcStageText(value)
    if value == "mapDefault" then return "Map Default" end
    if value == "yes" then return "ON" end
    return "OFF"
end

local function ccoGuiCanEditRules()
    if CropControlOverride ~= nil and CropControlOverride.canEditRules ~= nil then
        return CropControlOverride:canEditRules()
    end
    return true
end

function CropControlOverrideMenu:createStagedRuleFromRow(row)
    if row == nil then
        self.stagedRule = nil
        self.stagedDirty = false
        return
    end

    self.stagedRule = {
        crop = row.crop,
        enabled = row.enabledBool ~= nil and row.enabledBool == true or ccoValueToBool(row.enabled),
        npc = row.npcValue ~= nil and row.npcValue or ccoNpcToStage(row.npc),
        maxHa = tonumber(row.maxHa or 0) or numericFromHaAc(row.maxHaDisplay),
        resetNpcFields = self.defaultResetNpcFields ~= false,
    }
    self.stagedDirty = false
    self.forceApplyArmed = false
end

function CropControlOverrideMenu:updateStagedButtons()
    local staged = self.stagedRule
    local readOnly = not ccoGuiCanEditRules()

    local function setButton(button, value, disabled)
        if button ~= nil then
            if button.setText ~= nil then
                button:setText(tostring(value or "-"))
            end
            if button.setDisabled ~= nil then
                button:setDisabled(disabled == true)
            end
        end
    end

    local function setText(element, value)
        if element ~= nil and element.setText ~= nil then
            element:setText(tostring(value or "-"))
        end
    end

    if staged == nil then
        self:setEnabledSelectorState(false, true)
        self:setNpcSelectorState("mapDefault", true)
        setButton(self.editMaxDownButton, "-1", true)
        setButton(self.editMaxUpButton, "+1", true)
        self:setResetSelectorState(false, true)
        setButton(self.editApplyButton, "APPLY", true)
        setButton(self.editDiscardButton, "DISCARD", true)
        setText(self.editMaxHaText, "-")
        setText(self.selectedDirtyText, "No crop selected.")
        return
    end

    self:setEnabledSelectorState(staged.enabled == true, readOnly)
    self:setNpcSelectorState(staged.npc, readOnly)
    setButton(self.editMaxDownButton, "-1", readOnly)
    setButton(self.editMaxUpButton, "+1", readOnly)
    self:setResetSelectorState(staged.resetNpcFields == true, readOnly)
    setButton(self.editApplyButton, self.forceApplyArmed and "FORCE APPLY" or "APPLY", readOnly or not self.stagedDirty)
    setButton(self.editDiscardButton, "DISCARD", readOnly or not self.stagedDirty)
    setText(self.editMaxHaText, string.format("%.2f", tonumber(staged.maxHa or 0) or 0))

    if readOnly then
        setText(self.selectedDirtyText, "Read-only server rules. Only the server/host can change CCO settings.")
    elseif self.stagedDirty then
        setText(self.selectedDirtyText, "Staged changes ready. Apply will save XML.")
    else
        setText(self.selectedDirtyText, "No staged changes.")
    end
end

function CropControlOverrideMenu:updateSelectedDetails()
    local row = self.selectedRow

    local function set(element, value)
        if element ~= nil and element.setText ~= nil then
            element:setText(tostring(value or "-"))
        end
    end

    if not self.tableTopic then
        row = nil
    end

    if row == nil then
        set(self.selectedCropText, "No crop selected")
        set(self.selectedLoadedText, "-")
        set(self.selectedStatusText, "-")
        set(self.selectedInfoText, "Select a crop row, then use the selector/value controls to stage changes.")
        self:createStagedRuleFromRow(nil)
        self:updateStagedButtons()
        return
    end

    if self.stagedRule == nil or self.stagedRule.crop ~= row.crop then
        self:createStagedRuleFromRow(row)
    end

    set(self.selectedCropText, row.crop)
    set(self.selectedLoadedText, row.loaded)
    set(self.selectedStatusText, row.status)
    if ccoGuiCanEditRules() then
        set(self.selectedInfoText, "Use the selector/value controls to stage changes, then APPLY.")
    else
        set(self.selectedInfoText, "Viewing server-side CCO rules. Remote clients cannot edit or write local XML in multiplayer.")
    end
    self:updateStagedButtons()
end

function CropControlOverrideMenu:updateContent()
    if self.titleElement ~= nil and self.titleElement.setText ~= nil then
        self.titleElement:setText(tostring(self.pendingTitle or "Crop Control Override"))
    end

    self:updateTabs()

    if self.ruleTableContainer ~= nil then
        self.ruleTableContainer:setVisible(self.tableTopic)
    end
    if self.notLoadedToggleButton ~= nil then
        self.notLoadedToggleButton:setVisible(self.tableTopic)
        if self.notLoadedToggleButton.setText ~= nil then
            self.notLoadedToggleButton:setText(self.showNotLoaded and "NOT LOADED: SHOWN" or "NOT LOADED: HIDDEN")
        end
    end
    if self.bodyTextElement ~= nil then
        self.bodyTextElement:setVisible(not self.tableTopic)
        if not self.tableTopic then
            self.bodyTextElement:setText(tostring(self.pendingBody or ""))
        end
    end

    local showResetControls = (self.currentTopic == "blocked" or self.currentTopic == "validation") and not self.tableTopic

    if showResetControls then
        self:refreshResetScopes()
    end

    if self.resetScopeButton ~= nil then
        self.resetScopeButton:setVisible(showResetControls)
        self:updateResetScopeButton()
    end

    if self.resetModeButton ~= nil then
        self.resetModeButton:setVisible(showResetControls)
        self:updateResetModeButton()
    end

    if self.resetBlockedDryRunButton ~= nil then
        self.resetBlockedDryRunButton:setVisible(showResetControls)
        if self.resetBlockedDryRunButton.setDisabled ~= nil then
            local disabled = false
            if showResetControls and CropControlOverride ~= nil then
                local scope = self:getCurrentResetScope()
                if CropControlOverride.getBlockedCountForGuiScope ~= nil then
                    disabled = (tonumber(CropControlOverride:getBlockedCountForGuiScope(scope) or 0) or 0) == 0
                elseif CropControlOverride.buildFieldSummary ~= nil then
                    local summary = CropControlOverride:buildFieldSummary(nil)
                    disabled = (tonumber(summary.offending or 0) or 0) == 0
                end
            end
            self.resetBlockedDryRunButton:setDisabled(disabled)
        end
    end

    if self.confirmBlockedResetButton ~= nil then
        local showConfirmReset = showResetControls and self.resetConfirmArmed == true
        self.confirmBlockedResetButton:setVisible(showConfirmReset)
    end

    if self.tableTopic then
        local hasRows = #self.ruleRows > 0
        if hasRows then
            self.selectedRowIndex = self.selectedRowIndex or 1
            self.selectedRow = self.ruleRows[self.selectedRowIndex]
        end
        if self.ruleList ~= nil then
            self.ruleList:reloadData()
            if hasRows and self.ruleList.setSelectedIndex ~= nil then
                pcall(function() self.ruleList:setSelectedIndex(self.selectedRowIndex or 1, true) end)
            end
        end
        if self.emptyStateText ~= nil then
            self.emptyStateText:setVisible(not hasRows)
            if self.emptyStateText.setText ~= nil then
                self.emptyStateText:setText(self:getEmptyStateText())
            end
        end
        if self.ruleList ~= nil then
            self.ruleList:setVisible(hasRows)
        end
        if self.ruleListSliderBox ~= nil then
            self.ruleListSliderBox:setVisible(#self.ruleRows > 14)
        end
    end

    self:updateSelectedDetails()
end

-- SmoothList data source / delegate ---------------------------------------
function CropControlOverrideMenu:getNumberOfSections()
    return 1
end

function CropControlOverrideMenu:getNumberOfItemsInSection(list, section)
    return #self.ruleRows
end

function CropControlOverrideMenu:getTitleForSectionHeader(list, section)
    return nil
end

function CropControlOverrideMenu:getSectionHeaderHeight(list, section)
    return 0
end

function CropControlOverrideMenu:populateCellForItemInSection(list, section, index, cell)
    local row = self.ruleRows[index]
    if row == nil or cell == nil then
        return
    end

    local COLOR_DEFAULT = {0.88, 0.90, 0.86, 1.00}
    local COLOR_GREEN   = {0.55, 0.90, 0.25, 1.00}
    local COLOR_RED     = {0.95, 0.22, 0.18, 1.00}
    local COLOR_YELLOW  = {1.00, 0.78, 0.20, 1.00}

    local function applyTextColor(element, color)
        if element == nil or color == nil then
            return
        end

        if element.setTextColor ~= nil then
            element:setTextColor(color[1], color[2], color[3], color[4])
        elseif element.applyProfile ~= nil then
            -- Safe fallback: keep the existing profile if direct runtime colour is unavailable.
            -- Profile-based colouring can be added later if any FS25 build lacks setTextColor.
        end
    end

    local function set(name, value, color)
        local element = cell.getDescendantByName ~= nil and cell:getDescendantByName(name) or nil
        if element ~= nil then
            if element.setText ~= nil then
                element:setText(tostring(value or ""))
            end
            applyTextColor(element, color or COLOR_DEFAULT)
        end
    end

    local function valueColor(value)
        local text = tostring(value or ""):upper()

        if text == "YES" or text == "ON" or text == "ALLOWED" or text == "MAP DEFAULT" or text == "PASS" then
            return COLOR_GREEN
        end

        if text == "NO" or text == "OFF" or text == "DISABLED" or text == "NPC DISABLED" or text == "FAILED" then
            return COLOR_RED
        end

        if text == "SIZE LIMITED" then
            return COLOR_YELLOW
        end

        return COLOR_DEFAULT
    end

    local function maxHaColor(value)
        local n = numericFromHaAc(value)
        if n > 0 then
            return COLOR_YELLOW
        end
        return COLOR_DEFAULT
    end

    set("cellCrop", row.crop, COLOR_DEFAULT)
    set("cellEnabled", row.enabled, valueColor(row.enabled))
    set("cellNpc", row.npc, valueColor(row.npc))
    set("cellMaxHa", row.maxHaDisplay or formatHaAcCompact(row.maxHa), maxHaColor(row.maxHa))
    set("cellLoaded", row.loaded, valueColor(row.loaded))
    set("cellStatus", row.status, valueColor(row.status))
end

function CropControlOverrideMenu:onListSelectionChanged(list, section, index)
    local row = self.ruleRows[index]
    if row ~= nil then
        self.selectedRowIndex = index
        self.selectedRow = row
        self:updateSelectedDetails()
    end
end


function CropControlOverrideMenu:showTopic(topic, page)
    local title, body, normalizedTopic, normalizedPage = buildTopicContent(topic, page)
    self.currentTopic = normalizedTopic or topic or "status"
    self.currentPage = tonumber(normalizedPage or page or 1) or 1
    self:setContent(title, body, self.currentTopic)
end

-- Actions -----------------------------------------------------------------
function CropControlOverrideMenu:openTopic(topic)
    self:showTopic(topic, 1)
end

function CropControlOverrideMenu:onPageNext()
    local idx = self:getActiveTabIndex() + 1
    if idx > #TAB_TEXTS then
        idx = 1
    end
    self:updateSubCategoryPages(idx)
end

function CropControlOverrideMenu:onPagePrevious()
    local idx = self:getActiveTabIndex() - 1
    if idx < 1 then
        idx = #TAB_TEXTS
    end
    self:updateSubCategoryPages(idx)
end



function CropControlOverrideMenu:onClickToggleNotLoaded()
    self.showNotLoaded = not self.showNotLoaded
    local title, body, normalizedTopic, normalizedPage = buildTopicContent(self.currentTopic or "rules", self.currentPage or 1)
    self.currentTopic = normalizedTopic or self.currentTopic or "rules"
    self.currentPage = tonumber(normalizedPage or self.currentPage or 1) or 1
    self:setContent(title, body, self.currentTopic)
end


function CropControlOverrideMenu:onClickEnabledOption(state, optionElement)
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO rules are read-only for remote multiplayer clients.") end
        self:updateStagedButtons()
        return
    end
    if self.suppressSelectorCallbacks == true then
        return
    end

    if self.stagedRule ~= nil then
        local s = tonumber(state)
        if s ~= nil then
            local newValue = s == 2
            if self.stagedRule.enabled ~= newValue then
                self.stagedRule.enabled = newValue
                self.stagedDirty = true
                self.forceApplyArmed = false
                self:updateStagedButtons()
            end
        end
    end
end

function CropControlOverrideMenu:onClickToggleEnabled()
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO rules are read-only for remote multiplayer clients.") end
        return
    end
    if self.stagedRule ~= nil then
        self.stagedRule.enabled = not self.stagedRule.enabled
        self.stagedDirty = true
        self.forceApplyArmed = false
        self:updateStagedButtons()
    end
end

function CropControlOverrideMenu:onClickNpcOption(state, optionElement)
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO rules are read-only for remote multiplayer clients.") end
        self:updateStagedButtons()
        return
    end
    if self.suppressSelectorCallbacks == true then
        return
    end

    if self.stagedRule ~= nil then
        local s = tonumber(state)
        if s ~= nil then
            local newValue = "mapDefault"
            if s == 2 then
                newValue = "yes"
            elseif s == 3 then
                newValue = "no"
            end

            if self.stagedRule.npc ~= newValue then
                self.stagedRule.npc = newValue
                self.stagedDirty = true
                self.forceApplyArmed = false
                self:updateStagedButtons()
            end
        end
    end
end

function CropControlOverrideMenu:onClickToggleNpc()
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO rules are read-only for remote multiplayer clients.") end
        return
    end
    if self.stagedRule ~= nil then
        if self.stagedRule.npc == "mapDefault" then
            self.stagedRule.npc = "yes"
        elseif self.stagedRule.npc == "yes" then
            self.stagedRule.npc = "no"
        else
            self.stagedRule.npc = "mapDefault"
        end
        self.stagedDirty = true
        self.forceApplyArmed = false
        self:updateStagedButtons()
    end
end

function CropControlOverrideMenu:onClickMaxDown()
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO rules are read-only for remote multiplayer clients.") end
        return
    end
    if self.stagedRule ~= nil then
        local value = tonumber(self.stagedRule.maxHa or 0) or 0
        value = math.max(0, value - 1)
        self.stagedRule.maxHa = value
        self.stagedDirty = true
        self.forceApplyArmed = false
        self:updateStagedButtons()
    end
end

function CropControlOverrideMenu:onClickMaxUp()
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO rules are read-only for remote multiplayer clients.") end
        return
    end
    if self.stagedRule ~= nil then
        local value = tonumber(self.stagedRule.maxHa or 0) or 0
        value = math.min(999, value + 1)
        self.stagedRule.maxHa = value
        self.stagedDirty = true
        self.forceApplyArmed = false
        self:updateStagedButtons()
    end
end

function CropControlOverrideMenu:onClickResetOption(state, optionElement)
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO rules are read-only for remote multiplayer clients.") end
        self:updateStagedButtons()
        return
    end
    if self.suppressSelectorCallbacks == true then
        return
    end

    if self.stagedRule ~= nil then
        local s = tonumber(state)
        if s ~= nil then
            local newValue = s == 2
            if self.stagedRule.resetNpcFields ~= newValue then
                self.stagedRule.resetNpcFields = newValue
                self.defaultResetNpcFields = newValue
                self.stagedDirty = true
                self.forceApplyArmed = false
                self:updateStagedButtons()
            end
        end
    end
end

function CropControlOverrideMenu:onClickToggleReset()
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO rules are read-only for remote multiplayer clients.") end
        return
    end
    if self.stagedRule ~= nil then
        self.stagedRule.resetNpcFields = not self.stagedRule.resetNpcFields
        self.defaultResetNpcFields = self.stagedRule.resetNpcFields
        self.stagedDirty = true
        self.forceApplyArmed = false
        self:updateStagedButtons()
    end
end


function CropControlOverrideMenu:buildStagedRuleText()
    local staged = self.stagedRule
    if staged == nil then
        return "No staged rule selected."
    end

    return string.format(
        "crop=%s enabled=%s npcAllowed=%s npcMaxHa=%.2f resetNpcFields=%s",
        tostring(staged.crop or "-"),
        tostring(staged.enabled == true),
        tostring(ccoNpcStageText(staged.npc)),
        tonumber(staged.maxHa or 0) or 0,
        tostring(staged.resetNpcFields == true)
    )
end

function CropControlOverrideMenu:onClickApplyDryRun()
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO rules are read-only for remote multiplayer clients.") end
        return
    end
    if self.stagedRule == nil or not self.stagedDirty then
        return
    end

    if CropControlOverride == nil or CropControlOverride.applyGuiStagedRule == nil then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then
            self.selectedDirtyText:setText("Apply failed: CCO backend unavailable.")
        end
        return
    end

    local cropName = tostring(self.stagedRule.crop or "")
    local ok, msg, canForce = CropControlOverride:applyGuiStagedRule(self.stagedRule, self.forceApplyArmed == true)
    local resultText = tostring(msg or "")

    if ok then
        self.stagedDirty = false
        self.forceApplyArmed = false

        local validationFailed = resultText:lower():find("validation failed", 1, true) ~= nil
        local offending = resultText:match("offendingNpcFields=(%d+)") or resultText:match("offending NPC field%(s%)=(%d+)")

        local dirtyMessage = "Rule saved. Validation passed."
        local infoMessage = "The selected crop rule was saved to the active CCO XML and rules were reapplied."

        if validationFailed then
            dirtyMessage = "Rule saved. Validation warning."
            if offending ~= nil then
                infoMessage = ("Validation found %s blocked NPC field(s). Review the VALIDATION tab before using ccoResetBlocked dryrun."):format(tostring(offending))
            else
                infoMessage = "Validation found blocked NPC fields. Review the VALIDATION tab before using ccoResetBlocked dryrun."
            end
        end

        -- Refresh the active table/view from the newly written rule set.
        local topic = self.currentTopic or "rules"
        self:showTopic(topic, self.currentPage or 1)

        -- Restore selection to the crop that was just applied where possible.
        for i, row in ipairs(self.ruleRows or {}) do
            if row.crop == cropName then
                self.selectedRowIndex = i
                self.selectedRow = row
                self:createStagedRuleFromRow(row)
                self:updateSelectedDetails()
                if self.ruleList ~= nil and self.ruleList.setSelectedIndex ~= nil then
                    pcall(function() self.ruleList:setSelectedIndex(i, true) end)
                end
                break
            end
        end

        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then
            self.selectedDirtyText:setText(dirtyMessage)
        end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then
            self.selectedInfoText:setText(infoMessage)
        end
    else
        local message = tostring(msg or "Failed to save rule.")
        local blocked = message:lower():find("apply blocked", 1, true) ~= nil or message:lower():find("blocked npc field", 1, true) ~= nil
        if blocked and canForce == true then
            self.forceApplyArmed = true
        end
        self:updateStagedButtons()
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then
            self.selectedDirtyText:setText(blocked and "Apply blocked. Rule not saved." or "Apply failed.")
        end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then
            if blocked and canForce == true then
                self.selectedInfoText:setText(message .. " Click FORCE APPLY to save anyway.")
            else
                self.selectedInfoText:setText(message)
            end
        end
    end
end

function CropControlOverrideMenu:onClickDiscardStaged()
    if self.selectedRow ~= nil then
        self:createStagedRuleFromRow(self.selectedRow)
    else
        self:createStagedRuleFromRow(nil)
    end
    self:updateSelectedDetails()
end

function CropControlOverrideMenu:onClickStatus()
    self:openTopic("status")
end

function CropControlOverrideMenu:onClickRules()
    self:showTopic("rules", 1)
end

function CropControlOverrideMenu:onClickDisabled()
    self:showTopic("disabled", 1)
end

function CropControlOverrideMenu:onClickLimited()
    self:showTopic("limited", 1)
end

function CropControlOverrideMenu:onClickBlockedRules()
    self:showTopic("blockedrules", 1)
end

function CropControlOverrideMenu:onClickPrevPage()
    local topic = self.currentTopic or "rules"
    local page = tonumber(self.currentPage or 1) or 1
    if CropControlOverride ~= nil and CropControlOverride.openGui ~= nil then
        CropControlOverride:openGui(topic, math.max(1, page - 1))
    end
end

function CropControlOverrideMenu:onClickNextPage()
    local topic = self.currentTopic or "rules"
    local page = tonumber(self.currentPage or 1) or 1
    if CropControlOverride ~= nil and CropControlOverride.openGui ~= nil then
        CropControlOverride:openGui(topic, page + 1)
    end
end



function CropControlOverrideMenu:keyEvent(unicode, sym, modifier, isDown)
    if not isDown then
        return false
    end

    local input = rawget(_G, "Input")
    local keyboard = rawget(_G, "Keyboard")
    local escCodes = {input and input.KEY_esc, input and input.KEY_ESCAPE, keyboard and keyboard.KEY_esc, keyboard and keyboard.KEY_ESCAPE, 27}

    for _, code in ipairs(escCodes) do
        if code ~= nil and sym == code then
            self:onClickBack()
            return true
        end
    end

    local super = CropControlOverrideMenu:superClass()
    if super ~= nil and super.keyEvent ~= nil then
        return super.keyEvent(self, unicode, sym, modifier, isDown)
    end
    return false
end

function CropControlOverrideMenu:onClickHelp()
    self:openTopic("help")
end

function CropControlOverrideMenu:onClickReload()
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO defaults are read-only for remote multiplayer clients.") end
        return
    end
    if CropControlOverride ~= nil and CropControlOverride.loadTemplateDefaultsIntoCurrentSave ~= nil then
        local ok, resultOk, msg = pcall(function()
            return CropControlOverride:loadTemplateDefaultsIntoCurrentSave()
        end)

        if not ok then
            CropControlOverride._guiNotice = "Load Defaults failed: " .. tostring(resultOk)
            print("CCO GUI: load defaults action failed: " .. tostring(resultOk))
        elseif resultOk ~= true then
            CropControlOverride._guiNotice = tostring(msg or "Load Defaults failed.")
        end
    end
    self:showTopic("status", 1)
end

function CropControlOverrideMenu:onClickValidate()
    self:showTopic("blocked", 1)
end

function CropControlOverrideMenu:onClickBlocked()
    self:onClickValidate()
end


function CropControlOverrideMenu:onClickSaveDefaults()
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO defaults are read-only for remote multiplayer clients.") end
        return
    end
    if CropControlOverride ~= nil and CropControlOverride.saveCurrentRulesToTemplateConfig ~= nil then
        local ok, resultOk, msg = pcall(function()
            return CropControlOverride:saveCurrentRulesToTemplateConfig()
        end)

        if not ok then
            msg = tostring(resultOk)
            resultOk = false
            print("CCO GUI: save defaults action failed: " .. tostring(msg))
        end

        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then
            self.selectedDirtyText:setText(resultOk and "Saved defaults." or "Save defaults failed.")
        end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then
            self.selectedInfoText:setText(tostring(msg or "Template config updated."))
        end

        CropControlOverride._guiNotice = tostring(msg or "")
    end
end



function CropControlOverrideMenu:refreshResetScopes()
    local scopes = {
        { mode = "all", label = "ALL" }
    }

    if CropControlOverride ~= nil and CropControlOverride.getBlockedResetScopeList ~= nil then
        local ok, result = pcall(function()
            return CropControlOverride:getBlockedResetScopeList()
        end)
        if ok and type(result) == "table" and #result > 0 then
            scopes = result
        end
    elseif CropControlOverride ~= nil and CropControlOverride.getBlockedCropList ~= nil then
        local ok, crops = pcall(function()
            return CropControlOverride:getBlockedCropList()
        end)
        if ok and type(crops) == "table" then
            for _, crop in ipairs(crops) do
                table.insert(scopes, { mode = "crop", crop = tostring(crop), label = "CROP: " .. tostring(crop) })
            end
        end
    end

    self.resetScopes = scopes
    if self.resetScopeIndex == nil or self.resetScopeIndex < 1 or self.resetScopeIndex > #self.resetScopes then
        self.resetScopeIndex = 1
    end
end

function CropControlOverrideMenu:getCurrentResetScope()
    self:refreshResetScopes()
    local value = self.resetScopes[self.resetScopeIndex or 1] or { mode = "all", label = "ALL" }
    local label = type(value) == "table" and tostring(value.label or "ALL") or tostring(value or "ALL")
    if type(value) == "table" then
        return value, label
    end
    if value == "ALL" then
        return { mode = "all", label = "ALL" }, "ALL"
    end
    return { mode = "crop", crop = tostring(value), label = tostring(value) }, tostring(value)
end

function CropControlOverrideMenu:updateResetScopeButton()
    if self.resetScopeButton ~= nil then
        self:refreshResetScopes()
        local value = self.resetScopes[self.resetScopeIndex or 1] or { label = "ALL" }
        local label = type(value) == "table" and tostring(value.label or "ALL") or tostring(value or "ALL")
        if self.resetScopeButton.setText ~= nil then
            self.resetScopeButton:setText("RESET SCOPE: " .. label)
        end
        if self.resetScopeButton.setDisabled ~= nil then
            self.resetScopeButton:setDisabled(#(self.resetScopes or {}) <= 1)
        end
    end
end

function CropControlOverrideMenu:getResetModeLabel()
    if self.resetMode == "reseedSeasonal" then
        return "RESEED SEASONAL"
    end
    return "CULTIVATED"
end

function CropControlOverrideMenu:updateResetModeButton()
    if self.resetModeButton ~= nil then
        if self.resetModeButton.setText ~= nil then
            self.resetModeButton:setText("RESET MODE: " .. self:getResetModeLabel())
        end
        if self.resetModeButton.setDisabled ~= nil then
            self.resetModeButton:setDisabled(false)
        end
    end
end

function CropControlOverrideMenu:onClickResetMode()
    if self.resetMode == "reseedSeasonal" then
        self.resetMode = "cultivated"
    else
        self.resetMode = "reseedSeasonal"
    end
    self.resetConfirmArmed = false
    self:updateResetModeButton()
    self:updateContent()
end

function CropControlOverrideMenu:onClickResetScope()
    self:refreshResetScopes()
    if #(self.resetScopes or {}) > 1 then
        self.resetScopeIndex = (self.resetScopeIndex or 1) + 1
        if self.resetScopeIndex > #self.resetScopes then
            self.resetScopeIndex = 1
        end
        self.resetConfirmArmed = false
        self:updateResetScopeButton()
        self:updateContent()
    end
end

function CropControlOverrideMenu:onClickResetBlockedDryRun()
    if CropControlOverride == nil or CropControlOverride.resetBlockedFieldsDryRunFromGui == nil then
        return
    end

    local scopeCrop, scopeText = self:getCurrentResetScope()

    local ok, result, wouldQueue = pcall(function()
        return CropControlOverride:resetBlockedFieldsDryRunFromGui(scopeCrop, self.resetMode)
    end)

    local msg = ok and tostring(result or "Dry-run complete.") or ("Dry-run failed: " .. tostring(result))
    self.resetConfirmArmed = ccoGuiCanEditRules() and ok and (tonumber(wouldQueue or 0) or 0) > 0

    local body = ""
    if CropControlOverride.buildGuiBlockedText ~= nil then
        body = CropControlOverride:buildGuiBlockedText()
    end

    local confirmHint = ""
    if self.resetConfirmArmed then
        confirmHint = "\n\nCONFIRM RESET is now available for scope=" .. tostring(scopeText or "ALL") .. " resetMode=" .. self:getResetModeLabel() .. ". It will apply the selected reset mode."
    elseif not ccoGuiCanEditRules() then
        confirmHint = "\n\nRemote multiplayer clients are read-only. Reset actions can only be run by the server/host."
    end

    self.pendingTitle = "Crop Control Override - Validation"
    self.pendingBody = tostring(body or "") .. "\n\nDRY-RUN RESULT\n" .. msg .. confirmHint
    self.currentTopic = "blocked"
    self.tableTopic = false
    self:updateContent()
end

function CropControlOverrideMenu:onClickConfirmBlockedReset()
    if not ccoGuiCanEditRules() then
        if self.selectedDirtyText ~= nil and self.selectedDirtyText.setText ~= nil then self.selectedDirtyText:setText("Read-only") end
        if self.selectedInfoText ~= nil and self.selectedInfoText.setText ~= nil then self.selectedInfoText:setText("CCO reset is read-only for remote multiplayer clients.") end
        return
    end
    if self.resetConfirmArmed ~= true then
        return
    end
    if CropControlOverride == nil or CropControlOverride.resetBlockedFieldsFromGui == nil then
        return
    end

    local scopeCrop = self:getCurrentResetScope()

    local ok, result = pcall(function()
        return CropControlOverride:resetBlockedFieldsFromGui(scopeCrop, self.resetMode)
    end)

    local msg = ok and tostring(result or "Reset complete.") or ("Reset failed: " .. tostring(result))
    self.resetConfirmArmed = false
    self:refreshResetScopes()

    local body = ""
    if CropControlOverride.buildGuiBlockedText ~= nil then
        body = CropControlOverride:buildGuiBlockedText()
    end

    self.pendingTitle = "Crop Control Override - Validation"
    self.pendingBody = tostring(body or "") .. "\n\nRESET RESULT\n" .. msg
    self.currentTopic = "blocked"
    self.tableTopic = false
    self:updateContent()
end

function CropControlOverrideMenu:onClickBack()
    -- Prefer the native ScreenElement close path. This is more reliable than showGui("") for MENU_BACK/ESC.
    if self.close ~= nil then
        self:close()
        return
    end

    if self.changeScreen ~= nil then
        self:changeScreen(nil)
        return
    end

    if g_gui ~= nil then
        g_gui:showGui("")
    end
end

function CropControlOverrideMenu:onButtonBack()
    self:onClickBack()
end

function CropControlOverrideMenu:onClickClose()
    self:onClickBack()
end
