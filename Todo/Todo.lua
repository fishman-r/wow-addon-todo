local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G.TodoAddon or {}
end

_G.TodoAddon = addon
addon.addonName = addonName or "Todo"
addon.prefix = "|cff1785d1[Todo]|r "

local eventFrame = CreateFrame("Frame")
addon.eventFrame = eventFrame


function addon:Print(message)
    print(self.prefix .. tostring(message))
end


local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end


local function showHelp()
    addon:Print("/todo 打开窗口；help 帮助；doctor 自检；work/holiday <小时> 预填参数；replan 重新规划；extend <分钟> 延长；stay 切换常驻。")
end


SLASH_TODO1 = "/todo"
SLASH_TODO2 = "/td"
SlashCmdList.TODO = function(message)
    local normalized = trim(message)
    local command, rest = normalized:match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")
    rest = rest or ""

    if command == "" then
        addon:TogglePlanner()
        return
    end
    if command == "help" then
        showHelp()
        return
    end
    if command == "ping" then
        addon:Print("pong；核心已加载。")
        return
    end
    if command == "doctor" then
        for _, line in ipairs(addon:GetDoctorLines()) do addon:Print(line) end
        addon:ShowPlanner(false, false)
        addon:SelectTab("settings")
        return
    end
    if command == "info" then
        local capabilities = addon.Compat38002:GetCapabilities()
        addon:Print(string.format(
            "Todo %s；客户端 %s build %s；Interface %s；角色等级 %d；当前状态不代表已经通过 38002 真机验收。",
            addon.ADDON_VERSION,
            capabilities.build.version,
            capabilities.build.build,
            capabilities.build.interface,
            capabilities.level
        ))
        return
    end
    if command == "stay" then
        local settings = addon:GetUISettings()
        settings.persistent = not settings.persistent
        addon:Print(settings.persistent and "已开启常驻显示。" or "已关闭常驻显示；窗口在最后一次有效操作 60 秒后收起。")
        addon:TouchWindow()
        addon:RefreshAllUI()
        return
    end
    if command == "replan" then
        local session, reason = addon:ReplanSession()
        addon:Print(session and "已按真实剩余时间重新规划。" or tostring(reason))
        addon:ShowPlanner(false, false)
        addon:RefreshAllUI()
        return
    end
    if command == "extend" then
        local minutes = tonumber(rest)
        if not minutes or minutes <= 0 then
            addon:Print("用法：/todo extend 30")
            return
        end
        if addon:ExtendSession(minutes) then
            addon:ReplanSession()
            addon:Print("预设本次可玩时长已设为当前累计用时 + " .. tostring(minutes) .. " 分钟。")
            addon:ShowPlanner(false, false)
        else
            addon:Print("当前没有可延长的会话。")
        end
        return
    end
    if command == "work" or command == "workday" or command == "holiday" then
        local mode = command == "holiday" and "holiday" or "workday"
        local hours = rest ~= "" and addon:NormalizeHours(rest) or nil
        if rest ~= "" and not hours then
            addon:Print("时长必须是大于 0 的小时数，例如 1.5。")
            return
        end
        local preferences = addon:GetCharacterData().preferences
        preferences.mode = mode
        if hours then preferences.hours = hours end
        addon:ShowPlanner(false, false)
        addon:ShowSetup(false, addon:GetActiveSession() ~= nil)
        local setup = addon.mainFrame and addon.mainFrame.setup
        if setup then
            setup.mode = mode
            setup.considerRaids = mode == "holiday"
            if hours then setup.hours:SetText(tostring(hours)) end
            addon:RefreshSetup()
        end
        return
    end
    local hours = addon:NormalizeHours(command)
    if hours and rest == "" then
        addon:GetCharacterData().preferences.hours = hours
        addon:ShowPlanner(false, false)
        addon:ShowSetup(false, addon:GetActiveSession() ~= nil)
        if addon.mainFrame and addon.mainFrame.setup then
            addon.mainFrame.setup.hours:SetText(tostring(hours))
            addon:RefreshSetup()
        end
        return
    end
    showHelp()
end


function addon:ScheduleResetChecks()
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    self.resetTimerToken = (self.resetTimerToken or 0) + 1
    local token = self.resetTimerToken
    local dailySeconds = self.Compat38002:GetDailyResetInfo()
    local weeklySeconds = self.Compat38002:GetWeeklyResetInfo()
    local nextCheck
    if type(dailySeconds) == "number" then nextCheck = dailySeconds + 2 end
    if type(weeklySeconds) == "number" and (not nextCheck or weeklySeconds < nextCheck) then
        nextCheck = weeklySeconds + 2
    end
    if not nextCheck or nextCheck < 1 or nextCheck > (8 * 86400) then return end
    C_Timer.After(nextCheck, function()
        if addon.resetTimerToken ~= token then return end
        addon:GetDailyState()
        addon:GetWeeklyState()
        addon:ScanKnownDailies()
        addon:RefreshAllUI()
        addon:ScheduleResetChecks()
    end)
end


local function showLoginWindow(isInitialLogin, isReloadingUi)
    if addon.Compat38002:IsInCombat() then
        addon.pendingLoginWindow = {
            initial = isInitialLogin,
            reload = isReloadingUi,
        }
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    if not addon.Compat38002:IsSupportedCharacter() then
        addon:ShowPlanner(false, false)
        return
    end

    local session = addon:GetActiveSession()
    if isReloadingUi and session then
        addon:ShowPlanner(false, false)
        addon:SetStatusMessage("已识别 /reload，继续当前冻结计划和墙钟计时。", "success")
    else
        -- A true login always asks for confirmation. A prior session is shown only as an
        -- explicit continue choice; it is never silently resumed.
        addon:ShowPlanner(true, session ~= nil and not isInitialLogin)
    end
end


eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then return end
        addon:EnsureDatabase()
        self:UnregisterEvent("ADDON_LOADED")

        local events = {
            "QUEST_ACCEPTED",
            "QUEST_TURNED_IN",
            "QUEST_LOG_UPDATE",
            "GOSSIP_SHOW",
            "UPDATE_INSTANCE_INFO",
            "PLAYER_FLAGS_CHANGED",
            "PLAYER_LEVEL_CHANGED",
            "SKILL_LINES_CHANGED",
            "AUCTION_ITEM_LIST_UPDATE",
            "ITEM_SEARCH_RESULTS_UPDATED",
            "COMMODITY_SEARCH_RESULTS_UPDATED",
            "AUCTION_HOUSE_CLOSED",
            "BAG_UPDATE_DELAYED",
        }
        for _, eventName in ipairs(events) do pcall(self.RegisterEvent, self, eventName) end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if addon.Compat38002:IsSupportedCharacter() then
            addon:GetDailyState()
            addon:GetWeeklyState()
            if isInitialLogin then addon:MarkTrackingCrossLogin() end
            addon:ScanKnownDailies()
            addon.Compat38002:RequestRaidInfo()
            addon:ScheduleResetChecks()
        end
        addon:CreateMinimapButton()
        local shouldPrompt = isInitialLogin == true or isReloadingUi == true or not addon.enteredWorldOnce
        addon.enteredWorldOnce = true
        if shouldPrompt then showLoginWindow(isInitialLogin == true, isReloadingUi == true) end
        return
    end

    if event == "PLAYER_LOGOUT" then
        if addon.Compat38002:IsSupportedCharacter() then
            addon:FlushTaskTime()
            addon:MarkTrackingCrossLogin()
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" and addon.pendingLoginWindow then
        local pending = addon.pendingLoginWindow
        addon.pendingLoginWindow = nil
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        showLoginWindow(pending.initial, pending.reload)
        return
    end

    if not addon.Compat38002:IsSupportedCharacter() then
        if event == "PLAYER_LEVEL_CHANGED" then addon:RefreshAllUI() end
        return
    end

    if event == "QUEST_ACCEPTED" then
        local questIndex, questID = ...
        addon:HandleQuestAccepted(questIndex, questID)
        addon:RefreshAllUI()
        return
    end
    if event == "QUEST_TURNED_IN" then
        local questID, xpReward, moneyReward = ...
        addon:HandleQuestTurnedIn(questID, moneyReward)
        addon:RefreshAllUI()
        return
    end
    if event == "QUEST_LOG_UPDATE" then
        addon:ScanKnownDailies()
        addon:RefreshAllUI()
        return
    end
    if event == "GOSSIP_SHOW" then
        addon:ScanGossipDailies()
        addon:RefreshAllUI()
        return
    end
    if event == "UPDATE_INSTANCE_INFO" then
        local instances = addon.Compat38002:GetSavedInstances()
        addon:UpdateRaidStates(instances)
        addon:RefreshAllUI()
        return
    end
    if event == "AUCTION_ITEM_LIST_UPDATE" then
        local saved, status = addon:CaptureLegacyAuctionResults()
        local market = addon:GetMarketData()
        market.lastNativeObservation = market.lastNativeObservation or {
            status = status,
            saved = saved,
            at = addon.Compat38002:GetNow(),
        }
        if saved > 0 then
            addon:RefreshCurrentPlanValues()
            addon:RefreshAllUI()
        end
        return
    end
    if event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        -- The modern result getters are observable without issuing a query, but their Titan
        -- per-listing semantics still need true-client verification. Do not turn an aggregate
        -- minimum or a price bucket into a fake "20 listings" sample.
        addon:GetMarketData().lastNativeObservation = {
            status = "skipped-modern-results-unverified",
            event = event,
            at = addon.Compat38002:GetNow(),
        }
        return
    end
    if event == "PLAYER_FLAGS_CHANGED" then
        addon:UpdateAFKState()
        return
    end
    if event == "PLAYER_LEVEL_CHANGED" or event == "SKILL_LINES_CHANGED" then
        addon:RefreshAllUI()
        return
    end
    if event == "BAG_UPDATE_DELAYED" then
        -- Reward-bag recording stays disabled until a known bag and an unambiguous batch
        -- attribution window exist. Merely observing a bag update never writes a sample.
        return
    end
end)
