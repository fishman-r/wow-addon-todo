local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G.TodoAddon or {}
end

_G.TodoAddon = addon
addon.addonName = addonName or "Todo"

local function activeCount(activeTasks)
    local count = 0
    for _, timer in pairs(activeTasks or {}) do
        if type(timer) == "table" and timer.active then count = count + 1 end
    end
    return count
end


local function findPlanRow(session, candidateID)
    if type(session) ~= "table" or type(session.plan) ~= "table" then return nil end
    for _, row in ipairs(session.plan.rows or {}) do
        if row.candidateID == candidateID or row.id == candidateID then return row end
    end
    return nil
end


function addon:GetTrackingState()
    local session = self:GetActiveSession()
    if not session then return nil end
    session.tracking = type(session.tracking) == "table" and session.tracking or {}
    session.tracking.activeTasks = type(session.tracking.activeTasks) == "table"
        and session.tracking.activeTasks or {}
    return session.tracking
end


function addon:FlushTaskTime(now)
    local tracking = self:GetTrackingState()
    if not tracking then return end
    now = tonumber(now) or self.Compat38002:GetNow()
    local last = tonumber(tracking.lastSliceAt) or now
    local delta = math.max(0, now - last)
    tracking.lastSliceAt = now
    if tracking.moving or delta <= 0 then return end

    local count = activeCount(tracking.activeTasks)
    if count == 0 then return end
    local share = delta / count
    for _, timer in pairs(tracking.activeTasks) do
        if type(timer) == "table" and timer.active then
            timer.allocatedSeconds = (tonumber(timer.allocatedSeconds) or 0) + share
        end
    end
end


function addon:StartTaskTracking(candidateID, source)
    local session = self:GetActiveSession()
    local tracking = self:GetTrackingState()
    if not session or not tracking then return false, "请先生成本次计划" end
    local row = findPlanRow(session, candidateID)
    if not row or row.kind ~= "task" then return false, "任务不在本次计划中" end

    local now = self.Compat38002:GetNow()
    self:FlushTaskTime(now)
    local timer = tracking.activeTasks[candidateID]
    if type(timer) ~= "table" then
        timer = {
            candidateID = candidateID,
            allocatedSeconds = 0,
            startedAt = now,
            source = source or "manual",
            originalEstimatedMinutes = row.originalDurationMinutes or row.durationMinutes,
        }
        tracking.activeTasks[candidateID] = timer
    end
    timer.active = true
    timer.lastStartedAt = now
    tracking.lastSliceAt = now
    session.inProgressIDs[candidateID] = true
    row.inProgress = true
    return true
end


function addon:StopTaskTracking(candidateID, completed, metadata)
    local session = self:GetActiveSession()
    local tracking = self:GetTrackingState()
    if not session or not tracking then return false, "当前没有会话" end
    local timer = tracking.activeTasks[candidateID]
    if type(timer) ~= "table" then return false, "该任务尚未开始计时" end

    self:FlushTaskTime()
    timer.active = false
    tracking.activeTasks[candidateID] = nil
    session.inProgressIDs[candidateID] = nil
    local row = findPlanRow(session, candidateID)
    if row then row.inProgress = false end

    if completed then
        local sampleMetadata = {
            source = metadata and metadata.source or timer.source,
            afk = timer.hadAFK == true,
            crossLogin = timer.crossLogin == true,
            disconnected = timer.disconnected == true,
        }
        self:AddDurationSample("task", candidateID, (timer.allocatedSeconds or 0) / 60, sampleMetadata)
        self:SetPlanRowCompleted(candidateID, true)
    end
    return true, timer.allocatedSeconds or 0
end


function addon:StartRouteTracking(fromRegion, toRegion, rowID)
    local tracking = self:GetTrackingState()
    if not tracking then return false, "请先生成本次计划" end
    if not self.REGIONS_BY_ID[fromRegion] or not self.REGIONS_BY_ID[toRegion]
        or fromRegion == "other" or toRegion == "other" or fromRegion == toRegion then
        return false, "路线无效"
    end
    local now = self.Compat38002:GetNow()
    self:FlushTaskTime(now)
    tracking.moving = true
    tracking.route = {
        fromRegion = fromRegion,
        toRegion = toRegion,
        rowID = rowID,
        startedAt = now,
    }
    tracking.lastSliceAt = now
    return true
end


function addon:EndRouteTracking(metadata)
    local tracking = self:GetTrackingState()
    if not tracking or type(tracking.route) ~= "table" then
        return false, "当前没有移动计时"
    end
    local now = self.Compat38002:GetNow()
    local route = tracking.route
    local seconds = math.max(0, now - (tonumber(route.startedAt) or now))
    tracking.route = nil
    tracking.moving = nil
    tracking.lastSliceAt = now
    local sampleMetadata = {
        source = metadata and metadata.source or "manual-arrival",
        afk = route.hadAFK == true,
        crossLogin = route.crossLogin == true,
        disconnected = route.disconnected == true,
    }
    self:AddDurationSample("route", { route.fromRegion, route.toRegion }, seconds / 60, sampleMetadata)
    return true, seconds
end


function addon:StartRaidTracking(raidID)
    local tracking = self:GetTrackingState()
    if not tracking then return false, "请先生成本次计划" end
    if tracking.raid then return false, "已有团本正在计时" end
    local raid = self.RAIDS_BY_ID[raidID]
    if not raid then return false, "团本无效" end
    local state = self:GetRaidState(raidID)
    tracking.raid = {
        raidID = raidID,
        startedAt = self.Compat38002:GetNow(),
        startedFromZero = state == "not_done",
        stateAtStart = state,
    }
    return true
end


function addon:EndRaidTracking(fullClear)
    local tracking = self:GetTrackingState()
    if not tracking or type(tracking.raid) ~= "table" then
        return false, "当前没有团本计时"
    end
    local timer = tracking.raid
    tracking.raid = nil
    local now = self.Compat38002:GetNow()
    local seconds = math.max(0, now - (tonumber(timer.startedAt) or now))
    if fullClear then
        self:SetRaidOverride(timer.raidID, "complete")
        self:SetPlanRowCompleted(timer.raidID, true)
        if timer.startedFromZero then
            self:AddDurationSample("raid", timer.raidID, seconds / 60, {
                source = "manual-full-clear",
                afk = timer.hadAFK == true,
                crossLogin = timer.crossLogin == true,
                disconnected = timer.disconnected == true,
            })
            return true, seconds, "valid"
        end
        return true, seconds, "not-recorded"
    end
    self:SetRaidOverride(timer.raidID, "partial")
    return true, seconds, "not-recorded"
end


function addon:UpdateAFKState()
    local tracking = self:GetTrackingState()
    if not tracking then return end
    local now = self.Compat38002:GetNow()
    if self.Compat38002:IsAFK() then
        tracking.afkStartedAt = tracking.afkStartedAt or now
        if now - tracking.afkStartedAt >= 300 then
            for _, timer in pairs(tracking.activeTasks) do
                if type(timer) == "table" and timer.active then timer.hadAFK = true end
            end
            if tracking.route then tracking.route.hadAFK = true end
            if tracking.raid then tracking.raid.hadAFK = true end
        end
        return
    end

    if tracking.afkStartedAt and now - tracking.afkStartedAt >= 300 then
        for _, timer in pairs(tracking.activeTasks) do
            if type(timer) == "table" and timer.active then timer.hadAFK = true end
        end
        if tracking.route then tracking.route.hadAFK = true end
        if tracking.raid then tracking.raid.hadAFK = true end
    end
    tracking.afkStartedAt = nil
end


function addon:MarkTrackingCrossLogin()
    local tracking = self:GetTrackingState()
    if not tracking then return end
    for _, timer in pairs(tracking.activeTasks) do
        if type(timer) == "table" and timer.active then timer.crossLogin = true end
    end
    if tracking.route then tracking.route.crossLogin = true end
    if tracking.raid then tracking.raid.crossLogin = true end
end


function addon:InvalidateTrackingForReset(reason)
    local session = self:GetActiveSession()
    local tracking = self:GetTrackingState()
    if not session or not tracking then return end
    local now = self.Compat38002:GetNow()
    self:FlushTaskTime(now)
    for taskID, timer in pairs(tracking.activeTasks) do
        if type(timer) == "table" and timer.active and (tonumber(timer.allocatedSeconds) or 0) > 0 then
            self:AddDurationSample("task", taskID, timer.allocatedSeconds / 60, {
                crossCycle = true,
                source = reason,
            })
        end
        session.inProgressIDs[taskID] = nil
        local row = findPlanRow(session, taskID)
        if row then row.inProgress = false end
    end
    tracking.activeTasks = {}
    if tracking.route then
        local route = tracking.route
        local seconds = math.max(0, now - (tonumber(route.startedAt) or now))
        if seconds > 0 then
            self:AddDurationSample("route", { route.fromRegion, route.toRegion }, seconds / 60, {
                crossCycle = true,
                source = reason,
            })
        end
    end
    if tracking.raid then
        local raid = tracking.raid
        local seconds = math.max(0, now - (tonumber(raid.startedAt) or now))
        if seconds > 0 then
            self:AddDurationSample("raid", raid.raidID, seconds / 60, {
                crossCycle = true,
                source = reason,
            })
        end
    end
    tracking.route = nil
    tracking.raid = nil
    tracking.moving = nil
    tracking.lastSliceAt = now
end


function addon:ScanKnownDailies()
    if not self.Compat38002:IsSupportedCharacter() then return 0 end
    local entries = self.Compat38002:ScanQuestLog()
    local daily = self:GetDailyState()
    local database = self:EnsureDatabase()
    local found = 0
    for _, entry in ipairs(entries or {}) do
        if entry.isDaily then
            found = found + 1
            daily.discoveredQuestIDs[entry.questID] = true
            local task = self.QUEST_TO_TASK[entry.questID]
            if task then
                if task.pool then daily.professionSelections[task.id] = entry.questID end
                if entry.rewardMoney ~= nil then
                    self:RecordObservedQuestReward(entry.questID, entry.rewardMoney, {
                        source = "quest-log-preview",
                    })
                end
            else
                database.localPendingTasks[entry.questID] = database.localPendingTasks[entry.questID] or {
                    questID = entry.questID,
                    name = entry.title,
                    firstSeenAt = self.Compat38002:GetNow(),
                    status = "待确认固定/非限时/可单人",
                }
            end
        end
    end
    return found
end


function addon:ScanGossipDailies()
    if not self.Compat38002:IsSupportedCharacter() then return 0 end
    local quests = self.Compat38002:GetGossipAvailableQuests()
    local daily = self:GetDailyState()
    local database = self:EnsureDatabase()
    local found = 0
    for _, quest in ipairs(quests or {}) do
        if quest.isDaily then
            found = found + 1
            daily.discoveredQuestIDs[quest.questID] = true
            local task = self.QUEST_TO_TASK[quest.questID]
            if task and task.pool then daily.professionSelections[task.id] = quest.questID end
            if not task then
                database.localPendingTasks[quest.questID] = database.localPendingTasks[quest.questID] or {
                    questID = quest.questID,
                    name = quest.title,
                    firstSeenAt = self.Compat38002:GetNow(),
                    status = "待确认固定/非限时/可单人",
                }
            end
        end
    end
    return found
end


function addon:HandleQuestAccepted(questIndex, questID)
    if not self.Compat38002:IsSupportedCharacter() then return false end
    questID = tonumber(questID)
    local task = questID and self.QUEST_TO_TASK[questID]
    if not task then
        self:ScanKnownDailies()
        return false
    end
    local daily = self:GetDailyState()
    daily.discoveredQuestIDs[questID] = true
    if task.pool then daily.professionSelections[task.id] = questID end

    local session = self:GetActiveSession()
    local row = session and findPlanRow(session, task.id)
    if row then
        local tracking = self:GetTrackingState()
        if tracking and tracking.route and tracking.route.toRegion == row.region then
            self:EndRouteTracking({ source = "target-task-accepted" })
        end
        self:StartTaskTracking(task.id, "QUEST_ACCEPTED")
    end
    return true
end


function addon:HandleQuestTurnedIn(questID, moneyReward)
    if not self.Compat38002:IsSupportedCharacter() then return false end
    questID = tonumber(questID)
    if not questID then return false end
    local task = self.QUEST_TO_TASK[questID]
    self:MarkQuestCompleted(questID)
    if tonumber(moneyReward) ~= nil then
        self:RecordObservedQuestReward(questID, tonumber(moneyReward), {
            source = "QUEST_TURNED_IN",
        })
    end
    if task then
        local session = self:GetActiveSession()
        if session and findPlanRow(session, task.id) then
            self:StopTaskTracking(task.id, true, { source = "QUEST_TURNED_IN" })
            self:SetPlanRowCompleted(task.id, true)
        elseif session then
            session.outsideCompleted = type(session.outsideCompleted) == "table" and session.outsideCompleted or {}
            session.outsideCompleted[task.id] = {
                completedAt = self.Compat38002:GetNow(),
                directCopper = tonumber(moneyReward) or 0,
            }
        end
    else
        local pending = self:EnsureDatabase().localPendingTasks[questID]
        if pending then
            pending.completedAt = self.Compat38002:GetNow()
            pending.directCopper = tonumber(moneyReward)
        end
    end
    return task ~= nil
end


function addon:GetTrackingSummary()
    local tracking = self:GetTrackingState()
    if not tracking then return "无当前会话" end
    local active = activeCount(tracking.activeTasks)
    local parts = { "并行任务 " .. tostring(active) .. "项" }
    if tracking.moving and tracking.route then
        parts[#parts + 1] = "正在移动：" .. self:GetRegionName(tracking.route.fromRegion)
            .. "→" .. self:GetRegionName(tracking.route.toRegion)
    end
    if tracking.raid then parts[#parts + 1] = "团本计时中" end
    return table.concat(parts, " · ")
end
