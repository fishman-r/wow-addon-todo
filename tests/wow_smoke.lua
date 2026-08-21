local createdFrames = {}
local monotonic = 1000

local function createRegion()
    local region = { shown = true, text = "", width = 0, height = 0 }
    function region:SetAllPoints() end
    function region:SetColorTexture() end
    function region:SetTexture() end
    function region:SetSize(width, height) self.width = width or 0 self.height = height or 0 end
    function region:SetPoint() end
    function region:SetHeight(value) self.height = value or 0 end
    function region:SetWidth(value) self.width = value or 0 end
    function region:GetHeight() return self.height end
    function region:GetWidth() return self.width end
    function region:SetJustifyH() end
    function region:SetText(value) self.text = value or "" end
    function region:GetText() return self.text end
    function region:SetTextColor() end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetShown(value) self.shown = value == true end
    return region
end

local function createFrameObject(name, parent)
    local frame = {
        name = name,
        parent = parent,
        scripts = {},
        events = {},
        shown = true,
        text = "",
        point = { "CENTER", nil, "CENTER", 0, 0 },
        focused = false,
        width = 400,
        height = 400,
        frameLevel = 1,
    }
    function frame:SetSize(width, height) self.width = width self.height = height end
    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        self.point = { point, relativeTo, relativePoint, x, y }
    end
    function frame:GetPoint() return unpack(self.point) end
    function frame:ClearAllPoints() end
    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetFrameLevel(value) self.frameLevel = value end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetMovable() end
    function frame:EnableMouse() end
    function frame:EnableMouseWheel() end
    function frame:RegisterForDrag() end
    function frame:RegisterForClicks() end
    function frame:SetClampedToScreen() end
    function frame:SetClipsChildren() end
    function frame:SetAutoFocus() end
    function frame:SetMaxLetters() end
    function frame:SetTextInsets() end
    function frame:SetFontObject() end
    function frame:SetWidth(value) self.width = value end
    function frame:SetHeight(value) self.height = value end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetJustifyH() end
    function frame:SetText(value)
        self.text = value or ""
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
    end
    function frame:GetText() return self.text end
    function frame:SetTextColor() end
    function frame:SetFocus() self.focused = true end
    function frame:ClearFocus() self.focused = false end
    function frame:HasFocus() return self.focused end
    function frame:HighlightText() end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:CreateTexture() return createRegion() end
    function frame:CreateFontString() return createRegion() end
    function frame:SetScript(scriptName, callback) self.scripts[scriptName] = callback end
    function frame:RegisterEvent(eventName) self.events[eventName] = true end
    function frame:UnregisterEvent(eventName) self.events[eventName] = nil end
    function frame:SetScrollChild(child) self.scrollChild = child end
    function frame:SetVerticalScroll(offset) self.scrollOffset = offset end
    function frame:IsShown() return self.shown end
    function frame:Hide() self.shown = false end
    function frame:Show()
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:SetShown(value)
        if value then self:Show() else self:Hide() end
    end
    return frame
end

function CreateFrame(_, name, parent)
    local frame = createFrameObject(name, parent)
    createdFrames[#createdFrames + 1] = frame
    return frame
end

UIParent = createFrameObject("UIParent")
Minimap = createFrameObject("Minimap", UIParent)
GameFontNormal = {}
GameFontNormalLarge = {}
GameFontNormalSmall = {}
GameFontHighlight = {}
GameFontHighlightSmall = {}
ChatFontNormal = {}
UISpecialFrames = {}
SlashCmdList = {}

GameTooltip = {
    SetOwner = function() end,
    SetText = function() end,
    AddLine = function() end,
    Show = function() end,
    Hide = function() end,
}

local serverTime = 2000000000
local level = 80
function GetTime() return monotonic end
function GetServerTime() return serverTime end
function GetBuildInfo() return "3.80.2", "69137", "Aug 2026", 38002 end
function GetLocale() return "zhCN" end
function UnitLevel() return level end
function UnitFactionGroup() return "Alliance" end
function UnitGUID() return "Player-1-00000001" end
function UnitFullName() return "测试角色", "测试服务器" end
function UnitName() return "测试角色" end
function GetRealmName() return "测试服务器" end
function InCombatLockdown() return false end
function UnitIsAFK() return false end
function IsAddOnLoaded() return false end
function GetAddOnMetadata() return nil end

C_DateAndTime = {
    GetSecondsUntilDailyReset = function() return 3600 end,
    GetSecondsUntilWeeklyReset = function() return 7200 end,
}
C_Timer = {
    After = function(_, callback)
        -- Scheduling is recorded by production state; callbacks are deliberately not run here.
        C_Timer.lastCallback = callback
    end,
}
C_Item = {
    GetItemInfo = function(itemID)
        return "物品 " .. itemID, "item:" .. itemID, 1, 1, 1, "杂项", "", 1, "", 1, 100, 15, 0, 0
    end,
}

function GetProfessions() return 1, nil, nil, 2, 3, nil end
function GetProfessionInfo(index)
    if index == 1 then return "珠宝加工", nil, 450, 450, 0, 0, 755 end
    if index == 2 then return "钓鱼", nil, 450, 450, 0, 0, 356 end
    if index == 3 then return "烹饪", nil, 450, 450, 0, 0, 185 end
end

Enum = { QuestFrequency = { Daily = 1 } }
LE_QUEST_FREQUENCY_DAILY = 1
local questActive = true
function GetNumQuestLogEntries() return questActive and 1 or 0 end
function GetQuestLogTitle(index)
    if index == 1 and questActive then
        return "幽灵鱼", 80, nil, false, false, false, 1, 13830
    end
end
function GetQuestLogRewardMoney() return 200000 end
C_QuestLog = {
    GetQuestInfo = function(questID) return questID == 13830 and "幽灵鱼" or ("任务 " .. questID) end,
    IsOnQuest = function(questID) return questActive and questID == 13830 end,
    IsQuestFlaggedCompleted = function() return false end,
}
C_GossipInfo = { GetAvailableQuests = function() return {} end }

function RequestRaidInfo() end
function GetNumSavedInstances() return 0 end
function GetSavedInstanceInfo() return nil end

TodoDB = nil
local addon = {}
assert(loadfile("Todo/Compat38002.lua"))("Todo", addon)
assert(loadfile("Todo/Catalog.lua"))("Todo", addon)
assert(loadfile("Todo/Store.lua"))("Todo", addon)
assert(loadfile("Todo/Valuation.lua"))("Todo", addon)
assert(loadfile("Todo/Planner.lua"))("Todo", addon)
assert(loadfile("Todo/Tracking.lua"))("Todo", addon)
assert(loadfile("Todo/UI.lua"))("Todo", addon)
assert(loadfile("Todo/Todo.lua"))("Todo", addon)

local eventFrame = addon.eventFrame
assert(eventFrame and eventFrame.scripts.OnEvent, "核心事件框架未创建")
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "Todo")
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD", true, false)

assert(addon.mainFrame and addon.mainFrame:IsShown(), "首次登录没有显示 Todo")
assert(addon.mainFrame.setup:IsShown(), "真正登录没有要求确认本次参数")
assert(addon.mainFrame.pages.plan and addon.mainFrame.pages.candidates
    and addon.mainFrame.pages.values and addon.mainFrame.pages.settings, "四个固定页签未创建")

local setup = addon.mainFrame.setup
setup.mode = "holiday"
setup.considerRaids = true
setup.hours:SetText("4")
setup.region.regionID = "other"
setup.region:SetLabel(addon:GetRegionName("other"))
addon:RefreshSetup()
assert(addon:GenerateFromSetup(), "参数完整时没有生成会话")
local session = addon:GetActiveSession()
assert(session and session.plan.rows[1] and session.plan.rows[1].candidateID == "raid:sw", "假期四小时 UI 流程没有生成 SW 时间块")
assert(not addon.mainFrame.setup:IsShown(), "生成后参数面板没有关闭")

addon:SelectTab("candidates")
local search = addon.mainFrame.pages.candidates.search
search:SetText("达拉然 专业")
search.scripts.OnTextChanged(search, true)
assert(addon.mainFrame.pages.candidates.match:GetText():find("匹配"), "全部候选搜索没有刷新匹配数")

addon:SelectTab("plan")
local deadline = addon.mainFrame.autoHideDeadline
addon.mainFrame.tabs.plan.scripts.OnEnter(addon.mainFrame.tabs.plan)
assert(addon.mainFrame.autoHideDeadline == deadline, "鼠标悬停重置或暂停了倒计时")
monotonic = monotonic + 61
addon.mainFrame.scripts.OnUpdate(addon.mainFrame, 61)
assert(not addon.mainFrame:IsShown(), "非常驻窗口没有在 60 秒后收起")
SlashCmdList.TODO("")
assert(addon.mainFrame:IsShown(), "/todo 没有重新打开窗口")

serverTime = serverTime + (5 * 3600)
monotonic = monotonic + (5 * 3600)
addon:RefreshSessionClock()
assert(addon.mainFrame.pages.plan.time:GetText():find("5:00 / 4:00", 1, true),
    "E 超过 T 后没有继续累计显示：" .. addon.mainFrame.pages.plan.time:GetText())
assert(addon:GetActiveSession().plan ~= nil, "E 超过 T 后计划被清空")

local originalStartedAt = addon:GetActiveSession().startedAt
addon:ShowSetup(false, true)
addon.mainFrame.setup.hours:SetText("6")
assert(addon:GenerateFromSetup(), "修改本次参数后没有重新规划")
assert(addon:GetActiveSession().startedAt == originalStartedAt, "修改 T 时错误地重置了会话计时")
assert(addon:GetSessionElapsedSeconds() == 5 * 3600, "修改 T 时实际累计计时 E 被重置")
assert(addon:GetActiveSession().declaredMinutes == 360, "修改后的预设时长 T 未保存")

SlashCmdList.TODO("doctor")
assert(addon.mainFrame.pages.settings.doctor:GetText():find("Interface 38002", 1, true), "doctor 没有展示 Interface")
assert(addon.minimapButton, "小地图入口未创建")

level = 79
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_LEVEL_CHANGED")
assert(addon.mainFrame.levelBlock:IsShown(), "非 80 级没有显示硬拦截")

print("WoW UI 与事件烟雾测试通过")
