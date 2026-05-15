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
    self.currentTopic = "status"
    self.currentPage = 1
    self.ruleRows = {}
    self.tableTopic = false
    self.menuBackEventId = nil
    self.suppressTabCallback = false
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
    status = 1,
    rules = 2,
    disabled = 3,
    limited = 4,
    blockedrules = 5,
    ["blocked-rules"] = 5,
    blocked = 6,
    validation = 6,
}

local TAB_INDEX_TOPIC = {
    [1] = "status",
    [2] = "rules",
    [3] = "disabled",
    [4] = "limited",
    [5] = "blockedrules",
    [6] = "blocked",
}

local TAB_TEXTS = {
    "STATUS",
    "ALL RULES",
    "DISABLED",
    "LIMITED",
    "NPC BLOCKED",
    "VALIDATION",
}


local function buildTopicContent(topic, page)
    topic = topic ~= nil and tostring(topic):lower() or "status"
    if CropControlOverride == nil then
        return "Crop Control Override", "CropControlOverride backend is not available.", "status", 1
    end

    if topic == "status" then
        return "Crop Control Override - Status", CropControlOverride:buildGuiStatusText(), "status", 1
    elseif topic == "rules" then
        return "Crop Control Override - Configured Rules", CropControlOverride:buildGuiRuleListText("rules", page), "rules", page or 1
    elseif topic == "disabled" then
        return "Crop Control Override - Disabled Crops", CropControlOverride:buildGuiRuleListText("disabled", page), "disabled", page or 1
    elseif topic == "limited" then
        return "Crop Control Override - Size-Limited Crops", CropControlOverride:buildGuiRuleListText("limited", page), "limited", page or 1
    elseif topic == "blockedrules" or topic == "blocked-rules" then
        return "Crop Control Override - NPC Blocked Rules", CropControlOverride:buildGuiRuleListText("blockedrules", page), "blockedrules", page or 1
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

local function parseRuleRows(text)
    local rows = {}
    for _, line in ipairs(splitLines(text)) do
        local crop, enabled, npc, maxHa, loaded, status

        -- Alpha.47 changed NPC policy display from "mapDefault" to "Map Default".
        -- The GUI table is still populated from the text report, so support this
        -- multi-word display value explicitly instead of dropping those rows.
        crop, enabled, npc, maxHa, loaded, status = line:match("^(%S+)%s+(%S+)%s+(Map Default)%s+([%d%.%-]+)%s+(%S+)%s+(.+)$")

        if crop == nil then
            crop, enabled, npc, maxHa, loaded, status = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+([%d%.%-]+)%s+(%S+)%s+(.+)$")
        end

        if crop ~= nil
            and crop ~= "Crop"
            and crop ~= "Crop Type"
            and crop ~= "Page"
            and crop ~= "Shown"
            and crop ~= "Read%-only"
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


function CropControlOverrideMenu:getActiveTabIndex()
    local topic = self.currentTopic or "status"
    return TAB_TOPIC_INDEX[topic] or 1
end

function CropControlOverrideMenu:setupTabs()
    local idx = self:getActiveTabIndex()

    self.suppressTabCallback = true
    if self.subCategoryPaging ~= nil then
        if self.subCategoryPaging.setTexts ~= nil then
            self.subCategoryPaging:setTexts(TAB_TEXTS)
        end
        if self.subCategoryBox ~= nil and self.subCategoryBox.invalidateLayout ~= nil then
            self.subCategoryBox:invalidateLayout()
        end
        if self.subCategoryPaging.setSize ~= nil and self.subCategoryBox ~= nil and self.subCategoryBox.maxFlowSize ~= nil then
            self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * (g_pixelSizeScaledX or 1))
        end
        if self.subCategoryPaging.setState ~= nil then
            self.subCategoryPaging:setState(idx, true)
        end
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

    if self.subCategoryPaging ~= nil and self.subCategoryPaging.getState ~= nil then
        local state = self.subCategoryPaging:getState()
        if state ~= idx and self.subCategoryPaging.setState ~= nil then
            self.suppressTabCallback = true
            self.subCategoryPaging:setState(idx, true)
            self.suppressTabCallback = false
        end
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

    local topic = TAB_INDEX_TOPIC[idx] or "status"
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

function CropControlOverrideMenu:onOpen()
    CropControlOverrideMenu:superClass().onOpen(self)
    self:registerBackAction()
    self:setupTabs()
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
    self.ruleRows = self.tableTopic and parseRuleRows(self.pendingBody) or {}
    self:updateContent()
end


function CropControlOverrideMenu:getEmptyStateText()
    local topic = self.currentTopic or ""
    if topic == "limited" then
        return "No size-limited crops are configured for this save."
    elseif topic == "disabled" then
        return "No disabled crops are configured for this save."
    elseif topic == "blockedrules" then
        return "No crops are disabled or explicitly blocked for NPC use."
    elseif topic == "undiscovered" then
        return "All configured crops are currently loaded on this map/save."
    end
    return "No configured crop rules match this view."
end

function CropControlOverrideMenu:updateContent()
    if self.titleElement ~= nil and self.titleElement.setText ~= nil then
        self.titleElement:setText(tostring(self.pendingTitle or "Crop Control Override"))
    end

    self:updateTabs()

    if self.ruleTableContainer ~= nil then
        self.ruleTableContainer:setVisible(self.tableTopic)
    end
    if self.bodyTextElement ~= nil then
        self.bodyTextElement:setVisible(not self.tableTopic)
        if not self.tableTopic then
            self.bodyTextElement:setText(tostring(self.pendingBody or ""))
        end
    end

    if self.tableTopic then
        if self.ruleList ~= nil then
            self.ruleList:reloadData()
        end
        local hasRows = #self.ruleRows > 0
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

    local function set(name, value)
        local element = cell.getDescendantByName ~= nil and cell:getDescendantByName(name) or nil
        if element ~= nil and element.setText ~= nil then
            element:setText(tostring(value or ""))
        end
    end

    set("cellCrop", row.crop)
    set("cellEnabled", row.enabled)
    set("cellNpc", row.npc)
    set("cellMaxHa", row.maxHa)
    set("cellLoaded", row.loaded)
    set("cellStatus", row.status)
end

function CropControlOverrideMenu:onListSelectionChanged(list, section, index)
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
    if CropControlOverride ~= nil and CropControlOverride.consoleReload ~= nil then
        local ok, err = pcall(function()
            CropControlOverride:consoleReload()
        end)
        if ok then
            CropControlOverride._guiNotice = "Config reloaded from GUI."
        else
            CropControlOverride._guiNotice = "Reload failed: " .. tostring(err)
            print("CCO GUI: reload action failed: " .. tostring(err))
        end
    end
    self:showTopic("status", 1)
end

function CropControlOverrideMenu:onClickValidate()
    self:showTopic("blocked", 1)
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
