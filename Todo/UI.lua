local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G.TodoAddon or {}
end

_G.TodoAddon = addon
addon.addonName = addonName or "Todo"

local WINDOW_WIDTH = 780
local WINDOW_HEIGHT = 620
local AUTO_HIDE_SECONDS = 60
local ROW_HEIGHT = 48

local COLORS = {
    background = { 0.063, 0.063, 0.063, 0.98 },
    panel = { 0.102, 0.102, 0.102, 1 },
    panelAlt = { 0.133, 0.133, 0.133, 1 },
    border = { 0, 0, 0, 1 },
    innerBorder = { 0.20, 0.20, 0.20, 1 },
    blue = { 0.09, 0.52, 0.82, 1 },
    blueDark = { 0.06, 0.32, 0.50, 1 },
    green = { 0.20, 0.72, 0.36, 1 },
    yellow = { 0.95, 0.76, 0.20, 1 },
    red = { 0.88, 0.25, 0.25, 1 },
    gray = { 0.38, 0.38, 0.38, 1 },
    text = { 0.90, 0.90, 0.90, 1 },
    muted = { 0.60, 0.60, 0.60, 1 },
    gold = { 0.95, 0.82, 0.45, 1 },
}

local function setColor(texture, color)
    if texture.SetColorTexture then
        texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    else
        texture:SetTexture(color[1], color[2], color[3], color[4] or 1)
    end
end


local function createTexture(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    setColor(texture, color)
    return texture
end


local function setShown(region, shown)
    if shown then region:Show() else region:Hide() end
end


local function createLabel(parent, fontObject, text)
    local label = parent:CreateFontString(nil, "OVERLAY", fontObject or GameFontNormalSmall)
    label:SetText(text or "")
    label:SetJustifyH("LEFT")
    label:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
    return label
end


local function createPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel.background = createTexture(panel, "BACKGROUND", COLORS.panel)
    panel.background:SetAllPoints()
    panel.top = createTexture(panel, "BORDER", COLORS.innerBorder)
    panel.top:SetPoint("TOPLEFT", 0, 0)
    panel.top:SetPoint("TOPRIGHT", 0, 0)
    panel.top:SetHeight(1)
    panel.bottom = createTexture(panel, "BORDER", COLORS.border)
    panel.bottom:SetPoint("BOTTOMLEFT", 0, 0)
    panel.bottom:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.bottom:SetHeight(1)
    panel.left = createTexture(panel, "BORDER", COLORS.border)
    panel.left:SetPoint("TOPLEFT", 0, 0)
    panel.left:SetPoint("BOTTOMLEFT", 0, 0)
    panel.left:SetWidth(1)
    panel.right = createTexture(panel, "BORDER", COLORS.border)
    panel.right:SetPoint("TOPRIGHT", 0, 0)
    panel.right:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.right:SetWidth(1)
    return panel
end


local function createButton(parent, width, height, text, primary)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.background = createTexture(button, "BACKGROUND", primary and COLORS.blueDark or COLORS.panelAlt)
    button.background:SetAllPoints()
    button.edge = createTexture(button, "BORDER", COLORS.innerBorder)
    button.edge:SetPoint("TOPLEFT", 0, 0)
    button.edge:SetPoint("TOPRIGHT", 0, 0)
    button.edge:SetHeight(1)
    button.label = createLabel(button, GameFontNormalSmall, text)
    button.label:SetPoint("CENTER", 0, 0)
    button.label:SetJustifyH("CENTER")
    button.primary = primary == true

    button:SetScript("OnEnter", function(self)
        setColor(self.background, self.primary and COLORS.blue or COLORS.gray)
    end)
    button:SetScript("OnLeave", function(self)
        setColor(self.background, self.active and COLORS.blue or (self.primary and COLORS.blueDark or COLORS.panelAlt))
    end)

    function button:SetActive(active)
        self.active = active == true
        setColor(self.background, self.active and COLORS.blue or (self.primary and COLORS.blueDark or COLORS.panelAlt))
    end

    function button:SetLabel(value)
        self.label:SetText(value or "")
    end

    return button
end


local function createEdit(parent, width, height, placeholder)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, height)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetTextInsets(7, 7, 0, 0)
    edit.background = createTexture(edit, "BACKGROUND", COLORS.panelAlt)
    edit.background:SetAllPoints()
    edit.placeholder = placeholder
    return edit
end


local function createScrollArea(parent)
    local viewport = createPanel(parent)
    if viewport.SetClipsChildren then viewport:SetClipsChildren(true) end
    local scroll = CreateFrame("ScrollFrame", nil, viewport)
    scroll:SetPoint("TOPLEFT", 2, -2)
    scroll:SetPoint("BOTTOMRIGHT", -2, 2)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll.offset = 0
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maximum = math.max(0, (self.contentHeight or 0) - (self.viewportHeight or 0))
        self.offset = math.max(0, math.min(maximum, (self.offset or 0) - (delta * 42)))
        self:SetVerticalScroll(self.offset)
    end)
    return viewport, scroll, child
end


local function applySavedPosition(frame)
    local settings = addon:GetUISettings()
    local position = settings.position
    if type(position) == "table" then
        frame:ClearAllPoints()
        frame:SetPoint(
            position.point or "CENTER",
            UIParent,
            position.relativePoint or "CENTER",
            position.x or 0,
            position.y or 0
        )
    end
end


function addon:TouchWindow()
    local frame = self.mainFrame
    if not frame then return end
    if self:GetUISettings().persistent then
        frame.autoHideDeadline = nil
        if frame.autoHideText then frame.autoHideText:SetText("常驻") end
    else
        local now = self.Compat38002:GetMonotonicNow()
        frame.autoHideDeadline = now + AUTO_HIDE_SECONDS
    end
end


local function showTooltip(row, candidate)
    if not GameTooltip or not candidate then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(candidate.title or "Todo", 1, 1, 1)
    GameTooltip:AddLine((candidate.regionName or "") .. " · " .. (candidate.activityType or ""), 0.7, 0.7, 0.7)
    if candidate.durationMinutes then
        GameTooltip:AddLine("预计耗时：" .. addon:FormatMinutes(candidate.durationMinutes)
            .. "（" .. tostring(candidate.durationSource) .. "）", 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine("预计耗时：缺失，无法加入", 1, 0.35, 0.35)
    end
    if candidate.netCopper ~= nil then
        GameTooltip:AddLine("明确净价值：" .. addon:FormatCopper(candidate.netCopper), 0.95, 0.82, 0.45)
    else
        GameTooltip:AddLine("明确净价值：成本或数据不完整", 1, 0.75, 0.25)
    end
    GameTooltip:AddLine(candidate.statusReason or "", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("预计耗时只读；计时只形成以后使用的样本。", 0.45, 0.75, 1, true)
    GameTooltip:Show()
end


local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end


local function createPlanPage(frame)
    local page = CreateFrame("Frame", nil, frame.content)
    page:SetAllPoints()

    page.header = createPanel(page)
    page.header:SetPoint("TOPLEFT", 8, -8)
    page.header:SetPoint("TOPRIGHT", -8, -8)
    page.header:SetHeight(112)
    page.title = createLabel(page.header, GameFontNormal, "尚未生成计划")
    page.title:SetPoint("TOPLEFT", 12, -10)
    page.title:SetWidth(320)
    page.time = createLabel(page.header, GameFontNormalLarge, "0:00 / 0:00")
    page.time:SetPoint("TOPLEFT", 12, -36)
    page.time:SetTextColor(COLORS.blue[1], COLORS.blue[2], COLORS.blue[3])
    page.metrics = createLabel(page.header, GameFontNormalSmall, "")
    page.metrics:SetPoint("TOPLEFT", 12, -67)
    page.metrics:SetWidth(510)
    page.value = createLabel(page.header, GameFontNormalSmall, "")
    page.value:SetPoint("TOPLEFT", 12, -88)
    page.value:SetWidth(520)

    page.parameters = createButton(page.header, 104, 26, "修改参数")
    page.parameters:SetPoint("TOPRIGHT", -12, -10)
    page.replan = createButton(page.header, 104, 26, "重新规划", true)
    page.replan:SetPoint("TOPRIGHT", -12, -43)
    page.extend = createButton(page.header, 104, 26, "再玩 30 分")
    page.extend:SetPoint("TOPRIGHT", -12, -76)

    page.notice = createLabel(page, GameFontNormalSmall, "")
    page.notice:SetPoint("TOPLEFT", 12, -129)
    page.notice:SetPoint("TOPRIGHT", -12, -129)
    page.notice:SetHeight(20)

    page.listPanel, page.scroll, page.scrollChild = createScrollArea(page)
    page.listPanel:SetPoint("TOPLEFT", 8, -153)
    page.listPanel:SetPoint("BOTTOMRIGHT", -8, 8)
    page.rows = {}

    page.parameters:SetScript("OnClick", function()
        addon:ShowSetup(false, true)
        addon:TouchWindow()
    end)
    page.replan:SetScript("OnClick", function()
        local result, message = addon:ReplanSession()
        if not result then addon:SetStatusMessage(message, "error") end
        addon:RefreshAllUI()
        addon:TouchWindow()
    end)
    page.extend:SetScript("OnClick", function()
        addon:ExtendSession(30)
        addon:ReplanSession()
        addon:RefreshAllUI()
        addon:TouchWindow()
    end)
    frame.pages.plan = page
end


local function ensurePlanRow(page, index)
    if page.rows[index] then return page.rows[index] end
    local row = CreateFrame("Frame", nil, page.scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row.background = createTexture(row, "BACKGROUND", index % 2 == 0 and COLORS.panelAlt or COLORS.panel)
    row.background:SetAllPoints()
    row.icon = createLabel(row, GameFontNormal, "")
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetSize(22, 22)
    row.icon:SetJustifyH("CENTER")
    row.title = createLabel(row, GameFontNormalSmall, "")
    row.title:SetPoint("TOPLEFT", 36, -7)
    row.title:SetWidth(350)
    row.subtitle = createLabel(row, GameFontHighlightSmall, "")
    row.subtitle:SetPoint("BOTTOMLEFT", 36, 7)
    row.subtitle:SetWidth(430)
    row.subtitle:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
    row.primary = createButton(row, 86, 24, "")
    row.primary:SetPoint("RIGHT", -100, 0)
    row.secondary = createButton(row, 86, 24, "")
    row.secondary:SetPoint("RIGHT", -8, 0)
    row.hit = CreateFrame("Button", nil, row)
    row.hit:SetPoint("TOPLEFT", 0, 0)
    row.hit:SetPoint("BOTTOMRIGHT", row.primary, "BOTTOMLEFT", -4, 0)
    row.hit:SetScript("OnEnter", function()
        if row.candidate then showTooltip(row, row.candidate) end
    end)
    row.hit:SetScript("OnLeave", hideTooltip)
    row.hit:SetScript("OnClick", function()
        if row.candidate then addon:ShowCandidateDetails(row.candidate) end
    end)
    page.rows[index] = row
    return row
end


local function createCandidatesPage(frame)
    local page = CreateFrame("Frame", nil, frame.content)
    page:SetAllPoints()
    page.title = createLabel(page, GameFontNormal, "全部候选")
    page.title:SetPoint("TOPLEFT", 12, -14)
    page.search = createEdit(page, 420, 28, "搜索任务名、区域、专业、活动类型或 questID")
    page.search:SetPoint("TOPLEFT", 110, -8)
    page.search:SetMaxLetters(80)
    page.clear = createButton(page, 70, 26, "清空")
    page.clear:SetPoint("LEFT", page.search, "RIGHT", 8, 0)
    page.match = createLabel(page, GameFontHighlightSmall, "")
    page.match:SetPoint("LEFT", page.clear, "RIGHT", 10, 0)
    page.match:SetWidth(130)

    page.listPanel, page.scroll, page.scrollChild = createScrollArea(page)
    page.listPanel:SetPoint("TOPLEFT", 8, -48)
    page.listPanel:SetPoint("BOTTOMRIGHT", -8, 8)
    page.rows = {}

    page.search:SetScript("OnTextChanged", function(self, userInput)
        if userInput then addon:TouchWindow() end
        addon:RefreshCandidatePage()
    end)
    page.search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        addon:TouchWindow()
    end)
    page.clear:SetScript("OnClick", function()
        page.search:SetText("")
        page.search:ClearFocus()
        addon:RefreshCandidatePage()
        addon:TouchWindow()
    end)
    frame.pages.candidates = page
end


local function ensureCandidateRow(page, index)
    if page.rows[index] then return page.rows[index] end
    local row = CreateFrame("Frame", nil, page.scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row.background = createTexture(row, "BACKGROUND", index % 2 == 0 and COLORS.panelAlt or COLORS.panel)
    row.background:SetAllPoints()
    row.title = createLabel(row, GameFontNormalSmall, "")
    row.title:SetPoint("TOPLEFT", 10, -7)
    row.title:SetWidth(470)
    row.subtitle = createLabel(row, GameFontHighlightSmall, "")
    row.subtitle:SetPoint("BOTTOMLEFT", 10, 7)
    row.subtitle:SetWidth(550)
    row.subtitle:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
    row.action = createButton(row, 112, 25, "加入本次计划")
    row.action:SetPoint("RIGHT", -10, 0)
    row.hit = CreateFrame("Button", nil, row)
    row.hit:SetPoint("TOPLEFT", 0, 0)
    row.hit:SetPoint("BOTTOMRIGHT", row.action, "BOTTOMLEFT", -4, 0)
    row.hit:SetScript("OnEnter", function()
        if row.candidate then showTooltip(row, row.candidate) end
    end)
    row.hit:SetScript("OnLeave", hideTooltip)
    row.hit:SetScript("OnClick", function()
        if row.candidate then addon:ShowCandidateDetails(row.candidate) end
    end)
    page.rows[index] = row
    return row
end


local function createValuesPage(frame)
    local page = CreateFrame("Frame", nil, frame.content)
    page:SetAllPoints()
    page.title = createLabel(page, GameFontNormal, "估值数据")
    page.title:SetPoint("TOPLEFT", 12, -12)
    page.provider = createLabel(page, GameFontNormalSmall, "")
    page.provider:SetPoint("TOPLEFT", 12, -38)
    page.provider:SetWidth(480)
    page.import = createButton(page, 150, 26, "导入所需物品价格", true)
    page.import:SetPoint("TOPRIGHT", -12, -10)

    page.itemLabel = createLabel(page, GameFontNormalSmall, "手动税前单位价")
    page.itemLabel:SetPoint("TOPLEFT", 12, -70)
    page.itemID = createEdit(page, 95, 26, "itemID")
    page.itemID:SetPoint("TOPLEFT", 120, -62)
    page.itemID:SetMaxLetters(10)
    page.gold = createEdit(page, 95, 26, "金币")
    page.gold:SetPoint("LEFT", page.itemID, "RIGHT", 8, 0)
    page.save = createButton(page, 86, 26, "保存")
    page.save:SetPoint("LEFT", page.gold, "RIGHT", 8, 0)

    page.tokenLabel = createLabel(page, GameFontNormalSmall, "专业代币估值")
    page.tokenLabel:SetPoint("LEFT", page.save, "RIGHT", 18, 0)
    page.tokenID = createEdit(page, 86, 26, "代币ID")
    page.tokenID:SetPoint("LEFT", page.tokenLabel, "RIGHT", 8, 0)
    page.tokenGold = createEdit(page, 70, 26, "金币")
    page.tokenGold:SetPoint("LEFT", page.tokenID, "RIGHT", 8, 0)
    page.tokenSave = createButton(page, 60, 26, "保存")
    page.tokenSave:SetPoint("LEFT", page.tokenGold, "RIGHT", 8, 0)

    page.status = createLabel(page, GameFontHighlightSmall, "")
    page.status:SetPoint("TOPLEFT", 12, -101)
    page.status:SetWidth(730)
    page.listPanel, page.scroll, page.scrollChild = createScrollArea(page)
    page.listPanel:SetPoint("TOPLEFT", 8, -124)
    page.listPanel:SetPoint("BOTTOMRIGHT", -8, 8)
    page.rows = {}

    page.import:SetScript("OnClick", function()
        local report = addon:ImportAuctionatorPrices()
        page.status:SetText(string.format(
            "Auctionator：成功 %d · 缺失 %d · 跳过 %d · 错误 %d；旧记录不会因失败被清空。",
            report.success, report.missing, report.skipped, report.errors
        ))
        addon:RefreshCurrentPlanValues()
        addon:RefreshValuesPage()
        addon:TouchWindow()
    end)
    page.save:SetScript("OnClick", function()
        local itemID = tonumber(page.itemID:GetText())
        local gold = tonumber(page.gold:GetText())
        local success, message = addon:SetManualItemPrice(itemID, gold and gold * 10000)
        page.status:SetText(success and "手动备用价已保存；已有市场价时仍优先使用市场价。" or tostring(message))
        addon:RefreshCurrentPlanValues()
        addon:RefreshValuesPage()
        addon:TouchWindow()
    end)
    page.tokenSave:SetScript("OnClick", function()
        local success = addon:SetTokenValue(page.tokenID:GetText(), (tonumber(page.tokenGold:GetText()) or -1) * 10000)
        page.status:SetText(success and "当前角色的专业代币单价已保存。" or "代币 ID 或价格无效。")
        addon:RefreshCurrentPlanValues()
        addon:RefreshValuesPage()
        addon:TouchWindow()
    end)
    frame.pages.values = page
end


local function ensureValueRow(page, index)
    if page.rows[index] then return page.rows[index] end
    local row = CreateFrame("Frame", nil, page.scrollChild)
    row:SetHeight(42)
    row.background = createTexture(row, "BACKGROUND", index % 2 == 0 and COLORS.panelAlt or COLORS.panel)
    row.background:SetAllPoints()
    row.name = createLabel(row, GameFontNormalSmall, "")
    row.name:SetPoint("LEFT", 10, 0)
    row.name:SetWidth(300)
    row.price = createLabel(row, GameFontNormalSmall, "")
    row.price:SetPoint("LEFT", 320, 0)
    row.price:SetWidth(150)
    row.source = createLabel(row, GameFontHighlightSmall, "")
    row.source:SetPoint("LEFT", 480, 0)
    row.source:SetWidth(245)
    row.source:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
    page.rows[index] = row
    return row
end


local function cycleRegion(button, direction)
    local currentIndex = 1
    for index, region in ipairs(addon.REGIONS) do
        if region.id == button.regionID then currentIndex = index break end
    end
    currentIndex = currentIndex + (direction or 1)
    if currentIndex > #addon.REGIONS then currentIndex = 1 end
    if currentIndex < 1 then currentIndex = #addon.REGIONS end
    button.regionID = addon.REGIONS[currentIndex].id
    button:SetLabel(addon.REGIONS[currentIndex].name)
end


local function createDangerButton(page, x, y, text, callback)
    local button = createButton(page, 156, 26, text)
    button:SetPoint("TOPLEFT", x, y)
    button.originalLabel = text
    button:SetScript("OnClick", function(self)
        local now = addon.Compat38002:GetMonotonicNow()
        if not self.confirmUntil or now > self.confirmUntil then
            self.confirmUntil = now + 5
            self:SetLabel("再次点击确认")
            addon:TouchWindow()
            return
        end
        self.confirmUntil = nil
        self:SetLabel(self.originalLabel)
        callback()
        addon:RefreshAllUI()
        addon:TouchWindow()
    end)
    return button
end


local function createSettingsPage(frame)
    local page = CreateFrame("Frame", nil, frame.content)
    page:SetAllPoints()
    page.title = createLabel(page, GameFontNormal, "设置")
    page.title:SetPoint("TOPLEFT", 12, -12)

    page.persistentLabel = createLabel(page, GameFontNormalSmall, "窗口行为")
    page.persistentLabel:SetPoint("TOPLEFT", 12, -50)
    page.persistent = createButton(page, 150, 26, "")
    page.persistent:SetPoint("TOPLEFT", 110, -42)
    page.minimap = createButton(page, 150, 26, "")
    page.minimap:SetPoint("LEFT", page.persistent, "RIGHT", 8, 0)

    page.thresholdLabel = createLabel(page, GameFontNormalSmall, "最低净金币/小时")
    page.thresholdLabel:SetPoint("TOPLEFT", 12, -89)
    page.threshold = createEdit(page, 90, 26, "留空")
    page.threshold:SetPoint("TOPLEFT", 140, -81)
    page.thresholdSave = createButton(page, 70, 26, "保存")
    page.thresholdSave:SetPoint("LEFT", page.threshold, "RIGHT", 8, 0)

    page.commissionLabel = createLabel(page, GameFontNormalSmall, "拍卖手续费 %")
    page.commissionLabel:SetPoint("TOPLEFT", 340, -89)
    page.commission = createEdit(page, 70, 26, "5")
    page.commission:SetPoint("TOPLEFT", 445, -81)
    page.commissionSave = createButton(page, 70, 26, "保存")
    page.commissionSave:SetPoint("LEFT", page.commission, "RIGHT", 8, 0)
    page.commissionHint = createLabel(page, GameFontHighlightSmall, "当前默认 5% 尚待时光服真机核实")
    page.commissionHint:SetPoint("TOPLEFT", 340, -115)
    page.commissionHint:SetTextColor(COLORS.yellow[1], COLORS.yellow[2], COLORS.yellow[3])

    page.routeTitle = createLabel(page, GameFontNormal, "路线耗时学习（只计时，不填写分钟）")
    page.routeTitle:SetPoint("TOPLEFT", 12, -150)
    page.routeFrom = createButton(page, 210, 28, "达拉然")
    page.routeFrom:SetPoint("TOPLEFT", 12, -177)
    page.routeFrom.regionID = "dalaran"
    page.arrow = createLabel(page, GameFontNormal, "→")
    page.arrow:SetPoint("LEFT", page.routeFrom, "RIGHT", 10, 0)
    page.routeTo = createButton(page, 210, 28, "冰冠冰川")
    page.routeTo:SetPoint("LEFT", page.arrow, "RIGHT", 10, 0)
    page.routeTo.regionID = "icecrown"
    page.routeAction = createButton(page, 124, 28, "开始路线计时", true)
    page.routeAction:SetPoint("LEFT", page.routeTo, "RIGHT", 10, 0)
    page.routeStatus = createLabel(page, GameFontHighlightSmall, "")
    page.routeStatus:SetPoint("TOPLEFT", 12, -214)
    page.routeStatus:SetWidth(730)

    page.dataTitle = createLabel(page, GameFontNormal, "数据清理（首次点击后 5 秒内再次点击确认）")
    page.dataTitle:SetPoint("TOPLEFT", 12, -258)
    createDangerButton(page, 12, -288, "结束当前会话", function() addon:ClearActiveSession() end)
    createDangerButton(page, 180, -288, "清理角色学习数据", function()
        local character = addon:GetCharacterData()
        character.taskDurations = {}
        character.routeDurations = {}
        character.raidDurations = {}
        character.pendingSamples = {}
    end)
    createDangerButton(page, 348, -288, "清理当前市场价格", function()
        local market = addon:GetMarketData()
        market.nativeAuctionPrices = {}
        market.externalAuctionPrices = {}
        market.manualItemPrices = {}
        market.activeExternalProvider = nil
    end)
    createDangerButton(page, 516, -288, "清理奖励袋样本", function()
        addon:GetAccountData().rewardBagDistributions = {}
    end)
    createDangerButton(page, 12, -324, "恢复任务自动值", function()
        local character = addon:GetCharacterData()
        character.unlockOverrides = {}
        addon:GetMarketData().taskCorrections = {}
        local daily = addon:GetDailyState()
        daily.manualCompletion = {}
        daily.professionSelections = {}
        addon:GetWeeklyState().raidOverrides = {}
    end)
    createDangerButton(page, 180, -324, "清除全部 Todo 数据", function()
        TodoDB = nil
        addon.databaseInitializedThisLoad = nil
        addon:EnsureDatabase()
        addon:ShowSetup(false)
    end)

    page.doctorTitle = createLabel(page, GameFontNormal, "兼容性摘要")
    page.doctorTitle:SetPoint("TOPLEFT", 12, -382)
    page.doctor = createLabel(page, GameFontHighlightSmall, "")
    page.doctor:SetPoint("TOPLEFT", 12, -410)
    page.doctor:SetWidth(730)
    page.doctor:SetHeight(120)

    page.persistent:SetScript("OnClick", function()
        local settings = addon:GetUISettings()
        settings.persistent = not settings.persistent
        addon:RefreshSettingsPage()
        addon:TouchWindow()
    end)
    page.minimap:SetScript("OnClick", function()
        local settings = addon:GetUISettings()
        settings.hideMinimap = not settings.hideMinimap
        if addon.minimapButton then setShown(addon.minimapButton, not settings.hideMinimap) end
        addon:RefreshSettingsPage()
        addon:TouchWindow()
    end)
    page.thresholdSave:SetScript("OnClick", function()
        local text = page.threshold:GetText()
        local value = text == "" and nil or tonumber(text)
        if text ~= "" and (not value or value < 0) then
            addon:SetStatusMessage("收益门槛必须留空或填写非负数字", "error")
        else
            addon:GetCharacterData().preferences.minimumGoldPerHour = value
            addon:SetStatusMessage("收益门槛已保存；当前计划不会自动重排。", "success")
        end
        addon:TouchWindow()
    end)
    page.commissionSave:SetScript("OnClick", function()
        local percent = tonumber(page.commission:GetText())
        if not percent or percent < 0 or percent > 100 then
            addon:SetStatusMessage("手续费必须是 0 到 100 的百分比", "error")
        else
            local market = addon:GetMarketData()
            market.commissionRate = percent / 100
            market.commissionSource = "manual"
            addon:RefreshCurrentPlanValues()
            addon:SetStatusMessage("手续费已保存；当前计划成员和顺序保持不变。", "success")
        end
        addon:TouchWindow()
    end)
    page.routeFrom:SetScript("OnClick", function(self, mouseButton)
        cycleRegion(self, mouseButton == "RightButton" and -1 or 1)
        addon:TouchWindow()
    end)
    page.routeTo:SetScript("OnClick", function(self, mouseButton)
        cycleRegion(self, mouseButton == "RightButton" and -1 or 1)
        addon:TouchWindow()
    end)
    page.routeAction:SetScript("OnClick", function()
        local tracking = addon:GetTrackingState()
        if tracking and tracking.route then
            local success, seconds = addon:EndRouteTracking({ source = "settings-arrival" })
            page.routeStatus:SetText(success and ("已记录 " .. addon:FormatClock(seconds) .. "，重新规划后采用中位数。") or tostring(seconds))
        else
            local success, message = addon:StartRouteTracking(page.routeFrom.regionID, page.routeTo.regionID)
            page.routeStatus:SetText(success and "路线计时中；到达后再次点击。" or tostring(message))
        end
        addon:RefreshSettingsPage()
        addon:TouchWindow()
    end)
    frame.pages.settings = page
end


local function createSetup(frame)
    local setup = CreateFrame("Frame", nil, frame)
    setup:SetPoint("TOPLEFT", 74, -70)
    setup:SetPoint("BOTTOMRIGHT", -74, 42)
    setup:SetFrameLevel(frame:GetFrameLevel() + 20)
    setup.background = createTexture(setup, "BACKGROUND", COLORS.background)
    setup.background:SetAllPoints()
    setup.border = createTexture(setup, "BORDER", COLORS.blueDark)
    setup.border:SetPoint("TOPLEFT", 0, 0)
    setup.border:SetPoint("TOPRIGHT", 0, 0)
    setup.border:SetHeight(2)
    setup.title = createLabel(setup, GameFontNormalLarge, "生成本次计划")
    setup.title:SetPoint("TOPLEFT", 18, -18)
    setup.subtitle = createLabel(setup, GameFontHighlightSmall, "预计耗时由系统自动推算，所有分钟数只读。")
    setup.subtitle:SetPoint("TOPLEFT", 18, -48)
    setup.subtitle:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    setup.modeLabel = createLabel(setup, GameFontNormalSmall, "模式")
    setup.modeLabel:SetPoint("TOPLEFT", 18, -88)
    setup.workday = createButton(setup, 150, 38, "工作日")
    setup.workday:SetPoint("TOPLEFT", 92, -77)
    setup.holiday = createButton(setup, 150, 38, "假期")
    setup.holiday:SetPoint("LEFT", setup.workday, "RIGHT", 8, 0)

    setup.hoursLabel = createLabel(setup, GameFontNormalSmall, "至少可玩时长")
    setup.hoursLabel:SetPoint("TOPLEFT", 18, -140)
    setup.hours = createEdit(setup, 92, 30, "小时")
    setup.hours:SetPoint("TOPLEFT", 120, -131)
    setup.hours:SetMaxLetters(8)
    setup.hoursSuffix = createLabel(setup, GameFontNormalSmall, "小时")
    setup.hoursSuffix:SetPoint("LEFT", setup.hours, "RIGHT", 8, 0)

    setup.regionLabel = createLabel(setup, GameFontNormalSmall, "手选开始区域")
    setup.regionLabel:SetPoint("TOPLEFT", 300, -140)
    setup.region = createButton(setup, 220, 30, "达拉然")
    setup.region:SetPoint("TOPLEFT", 400, -131)
    setup.region.regionID = "dalaran"
    setup.regionHint = createLabel(setup, GameFontHighlightSmall, "左键下一个，右键上一个；不会读取当前位置")
    setup.regionHint:SetPoint("TOPLEFT", 400, -164)
    setup.regionHint:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    setup.raidToggle = createButton(setup, 208, 30, "自动考虑团本：开启")
    setup.raidToggle:SetPoint("TOPLEFT", 18, -196)
    setup.raidSelect = createButton(setup, 208, 30, "手动预留团本：0")
    setup.raidSelect:SetPoint("LEFT", setup.raidToggle, "RIGHT", 8, 0)
    setup.raidHint = createLabel(setup, GameFontHighlightSmall, "工作日不会自动推荐；假期不足 3 小时只可能自动选择宝库。")
    setup.raidHint:SetPoint("TOPLEFT", 18, -232)
    setup.raidHint:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])

    setup.previewPanel = createPanel(setup)
    setup.previewPanel:SetPoint("TOPLEFT", 18, -266)
    setup.previewPanel:SetPoint("TOPRIGHT", -18, -266)
    setup.previewPanel:SetHeight(104)
    setup.previewTitle = createLabel(setup.previewPanel, GameFontNormal, "预计计划")
    setup.previewTitle:SetPoint("TOPLEFT", 12, -10)
    setup.preview = createLabel(setup.previewPanel, GameFontNormalSmall, "填写完整后预演")
    setup.preview:SetPoint("TOPLEFT", 12, -37)
    setup.preview:SetWidth(560)
    setup.preview:SetHeight(58)

    setup.validation = createLabel(setup, GameFontNormalSmall, "")
    setup.validation:SetPoint("TOPLEFT", 18, -383)
    setup.validation:SetWidth(600)
    setup.validation:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])
    setup.generate = createButton(setup, 160, 34, "生成本次计划", true)
    setup.generate:SetPoint("BOTTOMRIGHT", -18, 18)
    setup.continue = createButton(setup, 160, 34, "继续上次计划")
    setup.continue:SetPoint("RIGHT", setup.generate, "LEFT", -8, 0)
    setup.cancel = createButton(setup, 100, 34, "取消")
    setup.cancel:SetPoint("BOTTOMLEFT", 18, 18)

    setup.raidPopup = createPanel(setup)
    setup.raidPopup:SetPoint("TOPLEFT", 18, -238)
    setup.raidPopup:SetPoint("BOTTOMRIGHT", -18, 54)
    setup.raidPopup:SetFrameLevel(setup:GetFrameLevel() + 10)
    setup.raidPopup:Hide()
    setup.raidPopup.title = createLabel(setup.raidPopup, GameFontNormal, "手动预留团本（允许超时）")
    setup.raidPopup.title:SetPoint("TOPLEFT", 12, -10)
    setup.raidPopup.close = createButton(setup.raidPopup, 72, 24, "完成")
    setup.raidPopup.close:SetPoint("TOPRIGHT", -10, -8)
    setup.raidButtons = {}
    for index, raid in ipairs(addon.RAID_CATALOG) do
        local column = (index - 1) % 2
        local line = math.floor((index - 1) / 2)
        local button = createButton(setup.raidPopup, 270, 27, "")
        button:SetPoint("TOPLEFT", 12 + (column * 282), -42 - (line * 31))
        button.raidID = raid.id
        button:SetScript("OnClick", function(self)
            setup.confirmedRaidIDs[self.raidID] = not setup.confirmedRaidIDs[self.raidID] or nil
            addon:RefreshSetup()
            addon:TouchWindow()
        end)
        setup.raidButtons[index] = button
    end
    setup.raidPopup.close:SetScript("OnClick", function()
        setup.raidPopup:Hide()
        addon:RefreshSetup()
        addon:TouchWindow()
    end)

    local function setMode(mode)
        setup.mode = mode
        setup.considerRaids = mode == "holiday"
        addon:RefreshSetup()
        addon:TouchWindow()
    end
    setup.workday:SetScript("OnClick", function() setMode("workday") end)
    setup.holiday:SetScript("OnClick", function() setMode("holiday") end)
    setup.hours:SetScript("OnTextChanged", function(_, userInput)
        if userInput then addon:TouchWindow() end
        addon:RefreshSetupPreview()
    end)
    setup.hours:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        addon:GenerateFromSetup()
    end)
    setup.hours:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    setup.region:SetScript("OnClick", function(self, mouseButton)
        cycleRegion(self, mouseButton == "RightButton" and -1 or 1)
        addon:RefreshSetupPreview()
        addon:TouchWindow()
    end)
    setup.raidToggle:SetScript("OnClick", function()
        setup.considerRaids = not setup.considerRaids
        addon:RefreshSetup()
        addon:TouchWindow()
    end)
    setup.raidSelect:SetScript("OnClick", function()
        setup.raidPopup:Show()
        addon:TouchWindow()
    end)
    setup.generate:SetScript("OnClick", function()
        addon:GenerateFromSetup()
        addon:TouchWindow()
    end)
    setup.continue:SetScript("OnClick", function()
        setup:Hide()
        addon:SelectTab("plan")
        addon:RefreshAllUI()
        addon:TouchWindow()
    end)
    setup.cancel:SetScript("OnClick", function()
        setup:Hide()
        addon:TouchWindow()
    end)
    setup:Hide()
    frame.setup = setup
end


local function createCandidateDetail(frame)
    local detail = createPanel(frame)
    detail:SetPoint("TOPLEFT", 92, -92)
    detail:SetPoint("BOTTOMRIGHT", -92, 72)
    detail:SetFrameLevel(frame:GetFrameLevel() + 40)
    detail.background:SetAllPoints()
    detail.title = createLabel(detail, GameFontNormalLarge, "候选详情")
    detail.title:SetPoint("TOPLEFT", 18, -16)
    detail.close = createButton(detail, 28, 24, "×")
    detail.close:SetPoint("TOPRIGHT", -10, -10)
    detail.info = createLabel(detail, GameFontNormalSmall, "")
    detail.info:SetPoint("TOPLEFT", 18, -56)
    detail.info:SetWidth(560)
    detail.info:SetHeight(112)

    detail.unlockLabel = createLabel(detail, GameFontNormalSmall, "解锁状态")
    detail.unlockLabel:SetPoint("TOPLEFT", 18, -181)
    detail.unlock = createButton(detail, 170, 28, "")
    detail.unlock:SetPoint("TOPLEFT", 108, -172)
    detail.completionLabel = createLabel(detail, GameFontNormalSmall, "今日完成")
    detail.completionLabel:SetPoint("TOPLEFT", 310, -181)
    detail.completion = createButton(detail, 170, 28, "")
    detail.completion:SetPoint("TOPLEFT", 390, -172)

    detail.regionLabel = createLabel(detail, GameFontNormalSmall, "所属区域")
    detail.regionLabel:SetPoint("TOPLEFT", 18, -222)
    detail.region = createButton(detail, 170, 28, "")
    detail.region:SetPoint("TOPLEFT", 108, -213)
    detail.costLabel = createLabel(detail, GameFontNormalSmall, "固定成本（金币）")
    detail.costLabel:SetPoint("TOPLEFT", 310, -222)
    detail.cost = createEdit(detail, 92, 28, "0")
    detail.cost:SetPoint("TOPLEFT", 428, -213)
    detail.costSave = createButton(detail, 70, 28, "保存")
    detail.costSave:SetPoint("LEFT", detail.cost, "RIGHT", 8, 0)

    detail.questLabel = createLabel(detail, GameFontNormalSmall, "今日具体 questID")
    detail.questLabel:SetPoint("TOPLEFT", 18, -263)
    detail.quest = createEdit(detail, 120, 28, "可留空")
    detail.quest:SetPoint("TOPLEFT", 142, -254)
    detail.questSave = createButton(detail, 70, 28, "保存")
    detail.questSave:SetPoint("LEFT", detail.quest, "RIGHT", 8, 0)
    detail.hint = createLabel(detail, GameFontHighlightSmall,
        "预计耗时只能来自本角色有效样本中位数或内置参考；此处没有分钟输入框。")
    detail.hint:SetPoint("TOPLEFT", 18, -303)
    detail.hint:SetWidth(560)
    detail.hint:SetTextColor(COLORS.yellow[1], COLORS.yellow[2], COLORS.yellow[3])

    detail.restore = createButton(detail, 156, 30, "恢复本项自动值")
    detail.restore:SetPoint("BOTTOMLEFT", 18, 18)
    detail.done = createButton(detail, 100, 30, "完成", true)
    detail.done:SetPoint("BOTTOMRIGHT", -18, 18)

    detail.close:SetScript("OnClick", function() detail:Hide() addon:TouchWindow() end)
    detail.done:SetScript("OnClick", function() detail:Hide() addon:TouchWindow() end)
    detail.unlock:SetScript("OnClick", function()
        local candidate = detail.candidate
        if not candidate then return end
        if candidate.kind == "raid" then
            local weekly = addon:GetWeeklyState()
            local current = weekly.raidOverrides[candidate.id]
            local nextValue = current == nil and "not_done"
                or (current == "not_done" and "partial"
                    or (current == "partial" and "complete" or nil))
            addon:SetRaidOverride(candidate.id, nextValue)
        else
            local overrides = addon:GetCharacterData().unlockOverrides
            local current = overrides[candidate.id]
            overrides[candidate.id] = current == nil and true or (current == true and false or nil)
        end
        addon:RefreshCandidateDetail()
        addon:RefreshAllUI()
        addon:TouchWindow()
    end)
    detail.completion:SetScript("OnClick", function()
        local candidate = detail.candidate
        if not candidate or candidate.kind ~= "task" then return end
        local daily = addon:GetDailyState()
        local current = daily.manualCompletion[candidate.id]
        local nextValue = current == nil and true or (current == true and false or nil)
        daily.manualCompletion[candidate.id] = nextValue
        daily.completedTasks[candidate.id] = nextValue == true and true or nil
        addon:RefreshCandidateDetail()
        addon:RefreshAllUI()
        addon:TouchWindow()
    end)
    detail.region:SetScript("OnClick", function(self, mouseButton)
        local candidate = detail.candidate
        if not candidate or candidate.kind ~= "task" then return end
        cycleRegion(self, mouseButton == "RightButton" and -1 or 1)
        addon:SetTaskCorrection(candidate.id, "region", self.regionID)
        addon:RefreshCandidateDetail()
        addon:RefreshAllUI()
        addon:TouchWindow()
    end)
    detail.costSave:SetScript("OnClick", function()
        local candidate = detail.candidate
        local gold = tonumber(detail.cost:GetText())
        if not candidate or candidate.kind ~= "task" or not gold or gold < 0 then
            addon:SetStatusMessage("固定成本必须是非负金币数", "error")
            return
        end
        addon:SetTaskCorrection(candidate.id, "fixedCostCopper", math.floor(gold * 10000 + 0.5))
        addon:SetTaskCorrection(candidate.id, "requiredCostsKnown", true)
        addon:SetStatusMessage("固定成本修正已保存；当前计划不会自动重排。", "success")
        addon:RefreshCandidateDetail()
        addon:RefreshAllUI()
        addon:TouchWindow()
    end)
    detail.questSave:SetScript("OnClick", function()
        local candidate = detail.candidate
        if not candidate or candidate.kind ~= "task" then return end
        local value = detail.quest:GetText()
        local questID = value == "" and nil or tonumber(value)
        local valid = questID == nil
        for _, allowed in ipairs(candidate.questIDs or {}) do
            if tonumber(allowed) == questID then valid = true break end
        end
        if not valid then
            addon:SetStatusMessage("questID 不属于这个目录任务池", "error")
            return
        end
        addon:GetDailyState().professionSelections[candidate.id] = questID
        addon:RefreshCandidateDetail()
        addon:RefreshAllUI()
        addon:TouchWindow()
    end)
    detail.restore:SetScript("OnClick", function()
        local candidate = detail.candidate
        if not candidate then return end
        if candidate.kind == "raid" then
            addon:SetRaidOverride(candidate.id, nil)
        else
            addon:GetCharacterData().unlockOverrides[candidate.id] = nil
            local daily = addon:GetDailyState()
            daily.manualCompletion[candidate.id] = nil
            daily.completedTasks[candidate.id] = nil
            daily.professionSelections[candidate.id] = nil
            addon:GetMarketData().taskCorrections[candidate.id] = nil
        end
        addon:RefreshCandidateDetail()
        addon:RefreshAllUI()
        addon:TouchWindow()
    end)
    detail:Hide()
    frame.candidateDetail = detail
end


local function createLevelBlock(frame)
    local block = CreateFrame("Frame", nil, frame)
    block:SetPoint("TOPLEFT", 0, -38)
    block:SetPoint("BOTTOMRIGHT", 0, 0)
    block:SetFrameLevel(frame:GetFrameLevel() + 30)
    block.background = createTexture(block, "BACKGROUND", COLORS.background)
    block.background:SetAllPoints()
    block.title = createLabel(block, GameFontNormalLarge, "Todo 仅支持 80 级角色")
    block.title:SetPoint("CENTER", 0, 20)
    block.title:SetJustifyH("CENTER")
    block.message = createLabel(block, GameFontHighlightSmall, "当前角色不会推荐、计时、采集拍卖价格或奖励袋样本。")
    block.message:SetPoint("TOP", block.title, "BOTTOM", 0, -14)
    block.message:SetJustifyH("CENTER")
    block:Hide()
    frame.levelBlock = block
end


function addon:CreateMainWindow()
    if self.mainFrame then return self.mainFrame end
    local frame = CreateFrame("Frame", "TodoMainFrame", UIParent)
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 15)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(20)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:Hide()
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "TodoMainFrame" end

    frame.background = createTexture(frame, "BACKGROUND", COLORS.background)
    frame.background:SetAllPoints()
    frame.titleBar = createTexture(frame, "BORDER", COLORS.panelAlt)
    frame.titleBar:SetPoint("TOPLEFT", 0, 0)
    frame.titleBar:SetPoint("TOPRIGHT", 0, 0)
    frame.titleBar:SetHeight(38)
    frame.accent = createTexture(frame, "ARTWORK", COLORS.blue)
    frame.accent:SetPoint("TOPLEFT", 0, 0)
    frame.accent:SetPoint("BOTTOMLEFT", frame.titleBar, "BOTTOMLEFT", 0, 0)
    frame.accent:SetWidth(3)
    frame.title = createLabel(frame, GameFontNormal, "Todo")
    frame.title:SetPoint("TOPLEFT", 14, -11)
    frame.version = createLabel(frame, GameFontHighlightSmall, "v" .. self.ADDON_VERSION .. " · 38002 开发预览")
    frame.version:SetPoint("LEFT", frame.title, "RIGHT", 10, 0)
    frame.version:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
    frame.status = createLabel(frame, GameFontHighlightSmall, "")
    frame.status:SetPoint("TOP", 0, -12)
    frame.status:SetWidth(360)
    frame.status:SetJustifyH("CENTER")
    frame.autoHideText = createLabel(frame, GameFontHighlightSmall, "")
    frame.autoHideText:SetPoint("TOPRIGHT", -44, -12)
    frame.autoHideText:SetWidth(130)
    frame.autoHideText:SetJustifyH("RIGHT")
    frame.close = createButton(frame, 28, 24, "×")
    frame.close:SetPoint("TOPRIGHT", -6, -7)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.tabs = {}
    frame.pages = {}
    local tabs = {
        { id = "plan", name = "本次计划" },
        { id = "candidates", name = "全部候选" },
        { id = "values", name = "估值数据" },
        { id = "settings", name = "设置" },
    }
    for index, tab in ipairs(tabs) do
        local button = createButton(frame, 122, 30, tab.name)
        button:SetPoint("TOPLEFT", 8 + ((index - 1) * 126), -41)
        button.tabID = tab.id
        button:SetScript("OnClick", function(self)
            addon:SelectTab(self.tabID)
            addon:TouchWindow()
        end)
        frame.tabs[tab.id] = button
    end

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", 0, -73)
    frame.content:SetPoint("BOTTOMRIGHT", 0, 0)
    createPlanPage(frame)
    createCandidatesPage(frame)
    createValuesPage(frame)
    createSettingsPage(frame)
    createSetup(frame)
    createCandidateDetail(frame)
    createLevelBlock(frame)

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
        addon:TouchWindow()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        addon:GetUISettings().position = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
        addon:TouchWindow()
    end)
    frame:SetScript("OnShow", function()
        addon:TouchWindow()
        addon:RefreshAllUI()
    end)
    frame.elapsedAccumulator = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsedAccumulator = self.elapsedAccumulator + elapsed
        local now = addon.Compat38002:GetMonotonicNow()
        if self.autoHideDeadline then
            local remaining = self.autoHideDeadline - now
            if remaining <= 0 then
                self.autoHideDeadline = nil
                self:Hide()
                return
            end
            self.autoHideText:SetText(math.ceil(remaining) .. "秒后收起")
        elseif addon:GetUISettings().persistent then
            self.autoHideText:SetText("常驻")
        end
        if self.elapsedAccumulator >= 1 then
            self.elapsedAccumulator = 0
            addon:RefreshSessionClock()
            addon:UpdateAFKState()
        end
    end)

    self.mainFrame = frame
    self.uiState = self.uiState or { selectedTab = "plan", collapsed = { completed = true } }
    applySavedPosition(frame)
    self:SelectTab(self.uiState.selectedTab)
    return frame
end


function addon:SetStatusMessage(message, kind)
    local frame = self:CreateMainWindow()
    frame.status:SetText(message or "")
    local color = kind == "error" and COLORS.red or (kind == "success" and COLORS.green or COLORS.yellow)
    frame.status:SetTextColor(color[1], color[2], color[3])
end


function addon:SelectTab(tabID)
    local frame = self:CreateMainWindow()
    if not frame.pages[tabID] then tabID = "plan" end
    self.uiState = self.uiState or { collapsed = {} }
    self.uiState.selectedTab = tabID
    for id, page in pairs(frame.pages) do setShown(page, id == tabID) end
    for id, button in pairs(frame.tabs) do button:SetActive(id == tabID) end
    frame.setup:Hide()
    frame.candidateDetail:Hide()
    if tabID == "candidates" then self:RefreshCandidatePage() end
    if tabID == "values" then self:RefreshValuesPage() end
    if tabID == "settings" then self:RefreshSettingsPage() end
end


function addon:RefreshSessionClock()
    local frame = self.mainFrame
    if not frame then return end
    local page = frame.pages.plan
    local session = self:GetActiveSession()
    if not session then
        page.time:SetText("0:00 / 0:00")
        return
    end
    local elapsed = self:GetSessionElapsedSeconds(session)
    page.time:SetText(self:FormatClock(elapsed) .. " / " .. self:FormatClock(session.declaredMinutes * 60))
    if elapsed > session.declaredMinutes * 60 then
        page.time:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])
        page.notice:SetText("已超出 " .. self:FormatMinutes((elapsed / 60) - session.declaredMinutes)
            .. "；计时继续，计划不会自动清空。")
        page.notice:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])
    else
        page.time:SetTextColor(COLORS.blue[1], COLORS.blue[2], COLORS.blue[3])
    end
end


function addon:RefreshPlanPage()
    local frame = self:CreateMainWindow()
    local page = frame.pages.plan
    local session = self:GetActiveSession()
    if not session or not session.plan then
        page.title:SetText("尚未生成本次计划")
        page.metrics:SetText("点击“修改参数”输入模式、至少可玩时长和手选开始区域。")
        page.value:SetText("")
        page.notice:SetText("")
        for _, row in ipairs(page.rows) do row:Hide() end
        return
    end
    self:RefreshCurrentPlanValues()
    local summary = session.plan.summary
    local completedRows = 0
    local completableRows = 0
    for _, planRow in ipairs(session.plan.rows or {}) do
        if planRow.kind == "task" or planRow.kind == "raid" then
            completableRows = completableRows + 1
            if planRow.completed then completedRows = completedRows + 1 end
        end
    end
    local outsideCompleted = 0
    for _ in pairs(session.outsideCompleted or {}) do outsideCompleted = outsideCompleted + 1 end
    page.title:SetText(self:GetModeName(session.mode) .. "计划 · 从" .. self:GetRegionName(session.startRegion) .. "出发")
    page.metrics:SetText(string.format(
        "85%% 自动预算 %s · 已规划 %s · 收益路线总计 %s · 完成 %d/%d（计划外 %d）",
        self:FormatMinutes(summary.budgetMinutes or 0),
        self:FormatMinutes(summary.plannedMinutes or 0),
        self:FormatMinutes((summary.taskMinutes or 0) + (summary.routeMinutes or 0)),
        completedRows,
        completableRows,
        outsideCompleted
    ))
    local valueRate = summary.plannedMinutes > 0
        and ((summary.currentNetCopper or 0) / 10000 * 60 / summary.plannedMinutes) or 0
    local routeOccupied = (summary.taskMinutes or 0) + (summary.routeMinutes or 0)
    local routeRate = routeOccupied > 0
        and ((summary.currentNetCopper or 0) / 10000 * 60 / routeOccupied) or 0
    page.value:SetText(string.format(
        "明确净价值：生成时 %s · 当前 %s · 路线 %.0f 金/时 · 本次下限 %.0f 金/时%s",
        self:FormatCopper(summary.generatedNetCopper or 0, true),
        self:FormatCopper(summary.currentNetCopper or 0, true),
        routeRate,
        valueRate,
        (summary.incompleteValueCount or 0) > 0 and (" · 另有 " .. summary.incompleteValueCount .. " 项价值不完整") or ""
    ))
    if summary.inProgressOverdue then
        page.notice:SetText("进行中项目已超过系统预计耗时；项目结束前重新规划不会自动填充新事项。")
        page.notice:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])
    elseif session.resetInvalidated then
        page.notice:SetText("服务器已重置；当前计划仍保持冻结，重新规划后才采用新周期状态。")
        page.notice:SetTextColor(COLORS.yellow[1], COLORS.yellow[2], COLORS.yellow[3])
    elseif summary.overBudget then
        page.notice:SetText("固定保留项或手动加入内容已超出 85% 自动预算；系统未擅自删除。")
        page.notice:SetTextColor(COLORS.yellow[1], COLORS.yellow[2], COLORS.yellow[3])
    elseif summary.nearestCandidate then
        page.notice:SetText("没有候选能完整放入；最接近项还需 "
            .. self:FormatMinutes(summary.nearestCandidate.overMinutes) .. "。")
        page.notice:SetTextColor(COLORS.yellow[1], COLORS.yellow[2], COLORS.yellow[3])
    elseif summary.firstLegExcluded then
        page.notice:SetText("首段路程未计入；后续跨区移动仍按系统耗时计算。")
        page.notice:SetTextColor(COLORS.yellow[1], COLORS.yellow[2], COLORS.yellow[3])
    else
        local changed = false
        for _, planRow in ipairs(session.plan.rows or {}) do changed = changed or planRow.valueChanged end
        page.notice:SetText(changed and "估值数据已变化；计划成员和顺序保持不变。" or "计划已冻结；只有“重新规划”会改变成员、顺序或路线。")
        page.notice:SetTextColor(changed and COLORS.yellow[1] or COLORS.muted[1], changed and COLORS.yellow[2] or COLORS.muted[2], changed and COLORS.yellow[3] or COLORS.muted[3])
    end

    local tracking = self:GetTrackingState()
    for index, planRow in ipairs(session.plan.rows or {}) do
        local row = ensurePlanRow(page, index)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", -1, -((index - 1) * ROW_HEIGHT))
        row.planRow = planRow
        local candidate
        if planRow.candidateID then
            for _, item in ipairs(session.plan.candidates or {}) do
                if item.id == planRow.candidateID then candidate = item break end
            end
        end
        row.candidate = candidate
        row.title:SetText((planRow.completed and "|cff66bb77✓ |r"
            or (planRow.skipped and "|cff999999— |r"
                or (planRow.inProgressOverdue and "|cffff5555! |r" or ""))) .. planRow.title)
        if planRow.completed or planRow.skipped then
            row.title:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
        else
            row.title:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
        end

        if planRow.kind == "task" then
            row.icon:SetText("任")
            row.icon:SetTextColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
            local valueText = planRow.currentNetCopper ~= nil and self:FormatCopper(planRow.currentNetCopper, true) or "价值不完整"
            local efficiencyText = planRow.currentNetCopper ~= nil and planRow.durationMinutes > 0
                and string.format(" · %.0f金/时", planRow.currentNetCopper / 10000 * 60 / planRow.durationMinutes)
                or ""
            row.subtitle:SetText(planRow.regionName .. " · " .. valueText .. " · "
                .. self:FormatMinutes(planRow.durationMinutes) .. efficiencyText
                .. "（" .. tostring(planRow.durationSource) .. "）")
            local timer = tracking and tracking.activeTasks[planRow.candidateID]
            if planRow.completed then
                row.primary:SetLabel("已完成")
                row.primary:SetScript("OnClick", function()
                    addon:SetPlanRowCompleted(planRow.candidateID, false)
                    addon:RefreshPlanPage()
                    addon:TouchWindow()
                end)
            elseif timer and timer.active then
                row.primary:SetLabel("完成并结束")
                row.primary:SetScript("OnClick", function()
                    addon:StopTaskTracking(planRow.candidateID, true, { source = "manual-complete" })
                    addon:RefreshAllUI()
                    addon:TouchWindow()
                end)
            else
                row.primary:SetLabel("开始计时")
                row.primary:SetScript("OnClick", function()
                    local success, message = addon:StartTaskTracking(planRow.candidateID, "manual")
                    if not success then addon:SetStatusMessage(message, "error") end
                    addon:RefreshPlanPage()
                    addon:TouchWindow()
                end)
            end
            row.secondary:SetLabel(planRow.skipped and "撤销跳过" or "本次跳过")
            row.secondary:SetScript("OnClick", function()
                if tracking and tracking.activeTasks[planRow.candidateID] then
                    addon:StopTaskTracking(planRow.candidateID, false, { source = "skip" })
                end
                addon:SetPlanRowSkipped(planRow.candidateID, not planRow.skipped)
                addon:RefreshPlanPage()
                addon:TouchWindow()
            end)
            row.secondary:Show()
        elseif planRow.kind == "route" then
            row.icon:SetText("→")
            row.icon:SetTextColor(COLORS.blue[1], COLORS.blue[2], COLORS.blue[3])
            row.subtitle:SetText("移动 · " .. self:FormatMinutes(planRow.durationMinutes) .. "（" .. tostring(planRow.durationSource) .. "）")
            local isActive = tracking and tracking.route and tracking.route.rowID == planRow.id
            row.primary:SetLabel(isActive and "已到达" or "开始前往")
            row.primary:SetScript("OnClick", function()
                local success, message
                if isActive then
                    success, message = addon:EndRouteTracking({ source = "plan-arrival" })
                else
                    success, message = addon:StartRouteTracking(planRow.fromRegion, planRow.toRegion, planRow.id)
                end
                if not success then addon:SetStatusMessage(message, "error") end
                addon:RefreshAllUI()
                addon:TouchWindow()
            end)
            row.secondary:Hide()
        else
            row.icon:SetText("团")
            row.icon:SetTextColor(COLORS.red[1], COLORS.red[2], COLORS.red[3])
            row.subtitle:SetText("团本时间块 · " .. self:FormatMinutes(planRow.durationMinutes)
                .. "（" .. tostring(planRow.durationSource) .. "）")
            local activeRaid = tracking and tracking.raid and tracking.raid.raidID == planRow.candidateID
            row.primary:SetLabel(activeRaid and "完整结束" or "开始团本")
            row.primary:SetScript("OnClick", function()
                local success, message
                if activeRaid then success, message = addon:EndRaidTracking(true)
                else success, message = addon:StartRaidTracking(planRow.candidateID) end
                if not success then addon:SetStatusMessage(message, "error") end
                addon:RefreshAllUI()
                addon:TouchWindow()
            end)
            row.secondary:SetLabel(activeRaid and "部分结束" or "本次跳过")
            row.secondary:SetScript("OnClick", function()
                if activeRaid then addon:EndRaidTracking(false)
                else addon:SetPlanRowSkipped(planRow.candidateID, not planRow.skipped) end
                addon:RefreshAllUI()
                addon:TouchWindow()
            end)
            row.secondary:Show()
        end
        row:Show()
    end
    for index = #(session.plan.rows or {}) + 1, #page.rows do page.rows[index]:Hide() end
    local contentHeight = math.max(1, #(session.plan.rows or {}) * ROW_HEIGHT)
    page.scrollChild:SetSize(744, contentHeight)
    page.scroll.contentHeight = contentHeight
    page.scroll.viewportHeight = math.max(1, page.listPanel:GetHeight() - 4)
    self:RefreshSessionClock()
end


function addon:RefreshCandidatePage()
    local frame = self:CreateMainWindow()
    local page = frame.pages.candidates
    local query = page.search:GetText() or ""
    local all = self:BuildAllCandidates({
        mode = self:GetActiveSession() and self:GetActiveSession().mode or self:GetCharacterData().preferences.mode,
    })
    local filtered = self:FilterCandidates(all, query)
    local groups = self:GetCandidateGroups(filtered)
    local display = {}
    for _, group in ipairs(groups) do
        display[#display + 1] = { header = true, group = group }
        local collapsed = self.uiState.collapsed[group.id]
        if query ~= "" then collapsed = false end
        if not collapsed then
            for _, candidate in ipairs(group.items) do display[#display + 1] = { candidate = candidate } end
        end
    end
    page.match:SetText(query ~= "" and ("匹配 " .. #filtered .. " / " .. #all) or ("共 " .. #all .. " 项"))
    if #filtered == 0 then
        page.match:SetText("没有找到候选")
        display[1] = { empty = true }
    end

    for index, item in ipairs(display) do
        local row = ensureCandidateRow(page, index)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", -1, -((index - 1) * ROW_HEIGHT))
        row.candidate = item.candidate
        if item.header then
            setColor(row.background, COLORS.panelAlt)
            row.title:SetText((self.uiState.collapsed[item.group.id] and "▶ " or "▼ ")
                .. item.group.name .. "  " .. #item.group.items)
            row.title:SetTextColor(COLORS.blue[1], COLORS.blue[2], COLORS.blue[3])
            row.subtitle:SetText("")
            row.action:SetLabel("展开 / 折叠")
            row.action:SetScript("OnClick", function()
                addon.uiState.collapsed[item.group.id] = not addon.uiState.collapsed[item.group.id]
                addon:RefreshCandidatePage()
                addon:TouchWindow()
            end)
        elseif item.empty then
            row.title:SetText("没有找到候选")
            row.subtitle:SetText("可清空搜索词恢复完整列表。")
            row.action:SetLabel("清空搜索")
            row.action:SetScript("OnClick", function()
                page.search:SetText("")
                addon:RefreshCandidatePage()
                addon:TouchWindow()
            end)
        else
            local candidate = item.candidate
            setColor(row.background, index % 2 == 0 and COLORS.panelAlt or COLORS.panel)
            row.title:SetText("[" .. (candidate.regionName or candidate.activityType) .. "] " .. candidate.title)
            row.title:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3])
            local duration = candidate.durationMinutes and self:FormatMinutes(candidate.durationMinutes) or "耗时缺失"
            local value = candidate.netCopper ~= nil and self:FormatCopper(candidate.netCopper, true) or "价值不完整"
            local efficiency = candidate.efficiencyGoldPerHour and string.format(" · %.0f金/时", candidate.efficiencyGoldPerHour) or ""
            row.subtitle:SetText(value .. " · " .. duration .. efficiency .. " · " .. candidate.statusReason)
            local inPlan = false
            local session = self:GetActiveSession()
            for _, planRow in ipairs(session and session.plan and session.plan.rows or {}) do
                if planRow.candidateID == candidate.id then inPlan = true break end
            end
            row.action:SetLabel(inPlan and "已在计划" or "加入本次计划")
            row.action:SetScript("OnClick", function()
                if inPlan then return end
                local success, message = addon:AddCandidateToSession(candidate.id)
                addon:SetStatusMessage(success and "已追加；原计划顺序保持不变。" or message, success and "success" or "error")
                addon:RefreshAllUI()
                addon:TouchWindow()
            end)
        end
        row:Show()
    end
    for index = #display + 1, #page.rows do page.rows[index]:Hide() end
    local contentHeight = math.max(1, #display * ROW_HEIGHT)
    page.scrollChild:SetSize(744, contentHeight)
    page.scroll.contentHeight = contentHeight
    page.scroll.viewportHeight = math.max(1, page.listPanel:GetHeight() - 4)
end


function addon:RefreshValuesPage()
    local frame = self:CreateMainWindow()
    local page = frame.pages.values
    local providers = self:GetAuctionProviders()
    local providerParts = {}
    for _, provider in ipairs(providers) do
        providerParts[#providerParts + 1] = provider.name .. "="
            .. (provider.apiAvailable and ("公开 API 可用，" .. provider.verification)
                or (provider.loaded and "已加载但此版本无已验证适配器" or "未加载"))
    end
    page.provider:SetText(table.concat(providerParts, " · "))
    local rows = self:GetValuationRows()
    if #rows == 0 then
        page.status:SetText("当前目录尚无待估值物品；可输入 itemID 和手动备用价，或在任务数据补齐后导入。")
    end
    for index, value in ipairs(rows) do
        local row = ensureValueRow(page, index)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 42))
        row:SetPoint("TOPRIGHT", -1, -((index - 1) * 42))
        row.name:SetText(value.name .. "  #" .. value.itemID)
        row.price:SetText(value.unitCopper and self:FormatCopper(value.unitCopper) or "缺价")
        row.source:SetText(tostring(value.source) .. (value.sampleCount and (" · " .. value.sampleCount .. "条") or ""))
        row:Show()
    end
    for index = #rows + 1, #page.rows do page.rows[index]:Hide() end
    local contentHeight = math.max(1, #rows * 42)
    page.scrollChild:SetSize(744, contentHeight)
    page.scroll.contentHeight = contentHeight
    page.scroll.viewportHeight = math.max(1, page.listPanel:GetHeight() - 4)
end


function addon:GetDoctorLines()
    local capabilities = self.Compat38002:GetCapabilities()
    local meta = self:EnsureDatabase().meta
    local session = self:GetActiveSession()
    local lines = {
        string.format("客户端 %s build %s · Interface %s · locale %s",
            capabilities.build.version, capabilities.build.build, capabilities.build.interface, capabilities.locale),
        string.format("Todo %s · 目录 %s · schema %s · SavedVariables 往返 %s",
            self.ADDON_VERSION, self.CATALOG_VERSION, meta.schemaVersion,
            meta.savedVariablesRoundTrip and "已观察" or "尚未观察"),
        string.format("等级 %d · 角色键 %s · 市场键 %s", capabilities.level,
            capabilities.characterKey, capabilities.marketKey),
        string.format("任务完成=%s · Gossip=%s · 物品=%s · 团本=%s · 拍卖=%s（永不主动查询）",
            capabilities.questCompletion and "可用未实测" or "不可用",
            capabilities.gossip and "可用未实测" or "不可用",
            capabilities.item and "可用未实测" or "不可用",
            capabilities.raid and "可用未实测" or "不可用",
            capabilities.auctionBranch),
        string.format("日重置=%s/%s · 周重置=%s/%s",
            capabilities.dailyReset.status, capabilities.dailyReset.source,
            capabilities.weeklyReset.status, capabilities.weeklyReset.source),
        session and string.format("会话 T=%s · E=%s · R=%s · B=%s · %s",
            self:FormatMinutes(session.declaredMinutes),
            self:FormatMinutes(self:GetSessionElapsedSeconds(session) / 60),
            self:FormatMinutes(math.max(0, session.declaredMinutes - self:GetSessionElapsedSeconds(session) / 60)),
            self:FormatMinutes(math.max(0, session.declaredMinutes - self:GetSessionElapsedSeconds(session) / 60) * self.PLANNING_RATIO),
            self:GetTrackingSummary()) or "会话：未生成",
    }
    return lines
end


function addon:RefreshSettingsPage()
    local frame = self:CreateMainWindow()
    local page = frame.pages.settings
    local ui = self:GetUISettings()
    page.persistent:SetLabel(ui.persistent and "常驻：开启" or "常驻：关闭")
    page.minimap:SetLabel(ui.hideMinimap and "小地图入口：隐藏" or "小地图入口：显示")
    local preference = self:GetCharacterData().preferences
    page.threshold:SetText(preference.minimumGoldPerHour and tostring(preference.minimumGoldPerHour) or "")
    page.commission:SetText(tostring((self:GetMarketData().commissionRate or 0) * 100))
    local tracking = self:GetTrackingState()
    page.routeAction:SetLabel(tracking and tracking.route and "已到达" or "开始路线计时")
    page.doctor:SetText(table.concat(self:GetDoctorLines(), "\n"))
end


function addon:RefreshSetupPreview()
    local setup = self.mainFrame and self.mainFrame.setup
    if not setup or not setup:IsShown() then return end
    local preview
    local hours = self:NormalizeHours(setup.hours:GetText())
    local activeSession = setup.editingSession and self:GetActiveSession() or nil
    if activeSession and hours then
        local fixed = {}
        for taskID in pairs(activeSession.manualTaskIDs or {}) do fixed[taskID] = true end
        for taskID in pairs(activeSession.inProgressIDs or {}) do fixed[taskID] = true end
        preview = self:BuildPlan({
            mode = setup.mode,
            declaredMinutes = hours * 60,
            elapsedMinutes = self:GetSessionElapsedSeconds(activeSession) / 60,
            startRegion = setup.region.regionID,
            confirmedRaidIDs = setup.confirmedRaidIDs,
            disableAutomaticRaid = setup.considerRaids == false,
            fixedTaskIDs = fixed,
            excludedIDs = activeSession.skippedIDs,
            sourceByID = activeSession.sourceByID,
        })
    else
        preview = self:PreviewSession({
            mode = setup.mode,
            hours = setup.hours:GetText(),
            startRegion = setup.region.regionID,
            confirmedRaidIDs = setup.confirmedRaidIDs,
            considerRaids = setup.considerRaids,
        })
    end
    if not preview then
        setup.preview:SetText("请输入大于 0 的至少可玩时长，并确认开始区域。")
        return
    end
    local summary = preview.summary
    setup.preview:SetText(string.format(
        "自动预算 %s · 系统预计计划用时 %s · %d 个时间块\n明确净价值下限 %s%s",
        self:FormatMinutes(summary.budgetMinutes),
        self:FormatMinutes(summary.plannedMinutes),
        #preview.rows,
        self:FormatCopper(summary.generatedNetCopper, true),
        summary.nearestCandidate and (" · 最接近候选仍超出 " .. self:FormatMinutes(summary.nearestCandidate.overMinutes)) or ""
    ))
end


function addon:RefreshSetup()
    local setup = self.mainFrame and self.mainFrame.setup
    if not setup then return end
    setup.workday:SetActive(setup.mode == "workday")
    setup.holiday:SetActive(setup.mode == "holiday")
    setup.raidToggle:SetLabel("自动考虑团本：" .. (setup.considerRaids and "开启" or "关闭"))
    local count = 0
    for _, selected in pairs(setup.confirmedRaidIDs or {}) do if selected then count = count + 1 end end
    setup.raidSelect:SetLabel("手动预留团本：" .. count)
    for index, raid in ipairs(self.RAID_CATALOG) do
        local button = setup.raidButtons[index]
        button:SetLabel((setup.confirmedRaidIDs[raid.id] and "✓ " or "") .. raid.phase .. " · "
            .. raid.shortName .. " · " .. self:FormatMinutes(self:GetRaidDuration(raid)))
        button:SetActive(setup.confirmedRaidIDs[raid.id] == true)
    end
    setShown(setup.continue, setup.resumeAvailable == true and self:GetActiveSession() ~= nil)
    self:RefreshSetupPreview()
end


function addon:ShowSetup(resumeAvailable, editCurrent)
    local frame = self:CreateMainWindow()
    if not self.Compat38002:IsSupportedCharacter() then
        frame.levelBlock:Show()
        frame.setup:Hide()
        return
    end
    frame.levelBlock:Hide()
    frame.candidateDetail:Hide()
    local preferences = self:GetCharacterData().preferences
    local session = self:GetActiveSession()
    local setup = frame.setup
    setup.editingSession = editCurrent == true and session ~= nil
    setup.title:SetText(setup.editingSession and "修改本次参数" or "生成本次计划")
    setup.generate:SetLabel(setup.editingSession and "保存并重新规划" or "生成本次计划")
    setup.mode = session and session.mode or preferences.mode
    setup.hours:SetText(tostring(session and (session.declaredMinutes / 60) or preferences.hours))
    setup.region.regionID = session and session.startRegion or preferences.startRegion
    setup.region:SetLabel(self:GetRegionName(setup.region.regionID))
    setup.considerRaids = session and session.considerRaids ~= false or setup.mode == "holiday"
    setup.confirmedRaidIDs = {}
    for raidID, selected in pairs(session and session.confirmedRaidIDs or {}) do
        if selected then setup.confirmedRaidIDs[raidID] = true end
    end
    setup.resumeAvailable = not setup.editingSession and resumeAvailable == true
    setShown(setup.continue, resumeAvailable == true and session ~= nil)
    setup.validation:SetText("")
    setup:Show()
    self:RefreshSetup()
end


function addon:GenerateFromSetup()
    local setup = self.mainFrame.setup
    local session
    local message
    if setup.editingSession and self:GetActiveSession() then
        local hours = self:NormalizeHours(setup.hours:GetText())
        if not hours then
            message = "至少可玩时长必须大于 0"
        elseif not self:IsValidMode(setup.mode) or not self.REGIONS_BY_ID[setup.region.regionID] then
            message = "模式或开始区域无效"
        else
            session = self:GetActiveSession()
            session.mode = setup.mode
            session.startRegion = setup.region.regionID
            session.considerRaids = setup.considerRaids
            session.confirmedRaidIDs = {}
            for raidID, selected in pairs(setup.confirmedRaidIDs or {}) do
                if selected then session.confirmedRaidIDs[raidID] = true end
            end
            self:UpdateSessionDeclaredMinutes(hours * 60)
            local preferences = self:GetCharacterData().preferences
            preferences.mode = session.mode
            preferences.startRegion = session.startRegion
            session, message = self:ReplanSession()
        end
    else
        session, message = self:CreateSession({
            mode = setup.mode,
            hours = setup.hours:GetText(),
            startRegion = setup.region.regionID,
            confirmedRaidIDs = setup.confirmedRaidIDs,
            considerRaids = setup.considerRaids,
        })
    end
    if not session then
        setup.validation:SetText(message or "无法生成计划")
        return false
    end
    setup:Hide()
    self:SelectTab("plan")
    self:SetStatusMessage("计划已生成；预计耗时只读，计时从现在开始。", "success")
    self:RefreshAllUI()
    return true
end


function addon:RefreshCandidateDetail()
    local frame = self.mainFrame
    local detail = frame and frame.candidateDetail
    if not detail or not detail.candidateID then return end
    local current
    local mode = self:GetActiveSession() and self:GetActiveSession().mode or self:GetCharacterData().preferences.mode
    for _, candidate in ipairs(self:BuildAllCandidates({ mode = mode })) do
        if candidate.id == detail.candidateID then current = candidate break end
    end
    if not current then
        detail:Hide()
        return
    end
    detail.candidate = current
    detail.title:SetText(current.title)
    local valueText = current.netCopper ~= nil and self:FormatCopper(current.netCopper) or "价值不完整"
    local questParts = {}
    for _, questID in ipairs(current.questIDs or {}) do questParts[#questParts + 1] = tostring(questID) end
    detail.info:SetText(table.concat({
        (current.regionName or "团本时间块") .. " · " .. (current.activityType or ""),
        "预计耗时 " .. self:FormatMinutes(current.durationMinutes or 0) .. " · 来源：" .. tostring(current.durationSource),
        "明确净价值 " .. valueText .. (current.valuation and current.valuation.lowerBound and "（已知下限）" or ""),
        "当前状态：" .. tostring(current.statusReason or current.state or "未知"),
        #questParts > 0 and ("questID：" .. table.concat(questParts, ", ")) or "团本映射需在 38002 真机核实",
    }, "\n"))

    if current.kind == "raid" then
        detail.unlockLabel:SetText("本周状态")
        local override = self:GetWeeklyState().raidOverrides[current.id]
        local labels = { not_done = "未打", partial = "部分进度", complete = "已完成" }
        detail.unlock:SetLabel(override and ("手动：" .. labels[override]) or "自动 / 未观察")
        detail.completionLabel:Hide()
        detail.completion:Hide()
        detail.regionLabel:Hide()
        detail.region:Hide()
        detail.costLabel:Hide()
        detail.cost:Hide()
        detail.costSave:Hide()
        detail.questLabel:Hide()
        detail.quest:Hide()
        detail.questSave:Hide()
    else
        detail.unlockLabel:SetText("解锁状态")
        local unlockOverride = self:GetCharacterData().unlockOverrides[current.id]
        detail.unlock:SetLabel(unlockOverride == nil and "自动" or (unlockOverride and "手动：是" or "手动：否"))
        local manualCompletion = self:GetDailyState().manualCompletion[current.id]
        detail.completion:SetLabel(manualCompletion == nil and "自动"
            or (manualCompletion and "手动：已完成" or "手动：未完成"))
        detail.completionLabel:Show()
        detail.completion:Show()
        detail.regionLabel:Show()
        detail.region:Show()
        detail.costLabel:Show()
        detail.cost:Show()
        detail.costSave:Show()
        detail.questLabel:Show()
        detail.quest:Show()
        detail.questSave:Show()
        local correction = self:GetTaskCorrection(current.id) or {}
        detail.region.regionID = correction.region or current.region
        detail.region:SetLabel(self:GetRegionName(detail.region.regionID))
        detail.cost:SetText(tostring((tonumber(correction.fixedCostCopper) or 0) / 10000))
        local selectedQuest = self:GetDailyState().professionSelections[current.id]
        detail.quest:SetText(selectedQuest and tostring(selectedQuest) or "")
    end
end


function addon:ShowCandidateDetails(candidate)
    local frame = self:CreateMainWindow()
    frame.setup:Hide()
    frame.candidateDetail.candidateID = candidate.id
    frame.candidateDetail:Show()
    self:RefreshCandidateDetail()
    self:TouchWindow()
end


function addon:RefreshAllUI()
    if not self.mainFrame then return end
    if not self.Compat38002:IsSupportedCharacter() then
        self.mainFrame.levelBlock:Show()
        self.mainFrame.candidateDetail:Hide()
        return
    end
    self.mainFrame.levelBlock:Hide()
    self:RefreshPlanPage()
    if self.uiState.selectedTab == "candidates" then self:RefreshCandidatePage() end
    if self.uiState.selectedTab == "values" then self:RefreshValuesPage() end
    if self.uiState.selectedTab == "settings" then self:RefreshSettingsPage() end
end


function addon:ShowPlanner(showSetup, resumeAvailable)
    local frame = self:CreateMainWindow()
    applySavedPosition(frame)
    frame:Show()
    if not self.Compat38002:IsSupportedCharacter() then
        frame.levelBlock:Show()
        frame.setup:Hide()
        frame.candidateDetail:Hide()
    elseif showSetup or not self:GetActiveSession() then
        self:ShowSetup(resumeAvailable, false)
    else
        frame.levelBlock:Hide()
        self:SelectTab(self.uiState.selectedTab or "plan")
        self:RefreshAllUI()
    end
    self:TouchWindow()
end


function addon:TogglePlanner()
    local frame = self:CreateMainWindow()
    if frame:IsShown() then frame:Hide() else self:ShowPlanner(not self:GetActiveSession(), false) end
end


function addon:CreateMinimapButton()
    if self.minimapButton or not Minimap then return self.minimapButton end
    local button = CreateFrame("Button", "TodoMinimapButton", Minimap)
    button:SetSize(30, 30)
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -2, -2)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.background = createTexture(button, "BACKGROUND", COLORS.panelAlt)
    button.background:SetAllPoints()
    button.label = createLabel(button, GameFontNormal, "T")
    button.label:SetPoint("CENTER")
    button.label:SetTextColor(COLORS.blue[1], COLORS.blue[2], COLORS.blue[3])
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            addon:ShowPlanner(false, false)
            addon:SelectTab("settings")
        else
            addon:TogglePlanner()
        end
    end)
    button:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Todo")
            GameTooltip:AddLine("左键：开关窗口", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("右键：打开设置", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", hideTooltip)
    setShown(button, not self:GetUISettings().hideMinimap)
    self.minimapButton = button
    return button
end
