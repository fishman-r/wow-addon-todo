local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G.TodoAddon or {}
end

_G.TodoAddon = addon
addon.addonName = addonName or "Todo"

local function copyArray(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end


local function copyMap(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end


local function countMap(source)
    local count = 0
    for _ in pairs(source or {}) do count = count + 1 end
    return count
end


local function roundedTimeKey(minutes)
    return math.floor(((tonumber(minutes) or 0) * 10) + 0.5)
end


local function normalizeSearch(value)
    value = string.lower(tostring(value or ""))
    value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return value
end


local function selectionSignature(selected)
    local ids = {}
    for _, candidate in ipairs(selected or {}) do
        ids[#ids + 1] = candidate.id
    end
    table.sort(ids)
    return table.concat(ids, ",")
end


local function recordBetter(left, right)
    if not right then return true end
    if left.valueCopper ~= right.valueCopper then
        return left.valueCopper > right.valueCopper
    end
    if math.abs(left.minutes - right.minutes) > 0.0001 then
        return left.minutes < right.minutes
    end
    if (left.regionCount or 0) ~= (right.regionCount or 0) then
        return (left.regionCount or 0) < (right.regionCount or 0)
    end
    if (left.incompleteCount or 0) ~= (right.incompleteCount or 0) then
        return (left.incompleteCount or 0) < (right.incompleteCount or 0)
    end
    if (left.orderScore or 0) ~= (right.orderScore or 0) then
        return (left.orderScore or 0) < (right.orderScore or 0)
    end
    return selectionSignature(left.selected) < selectionSignature(right.selected)
end


local function choicesCompatible(existing, candidate)
    if not candidate.exclusiveGroup then
        return true
    end
    local current = existing[candidate.exclusiveGroup]
    local choice = candidate.exclusiveChoice or candidate.id
    return current == nil or current == choice
end


local function addChoice(existing, candidate)
    local result = copyMap(existing)
    if candidate.exclusiveGroup then
        result[candidate.exclusiveGroup] = candidate.exclusiveChoice or candidate.id
    end
    return result
end


local function choiceSignature(choices)
    local values = {}
    for group, choice in pairs(choices or {}) do
        values[#values + 1] = tostring(group) .. "=" .. tostring(choice)
    end
    table.sort(values)
    return table.concat(values, ";")
end


local function pruneStateMap(records)
    local grouped = {}
    for _, record in pairs(records or {}) do
        local signature = choiceSignature(record.choices)
        grouped[signature] = grouped[signature] or {}
        grouped[signature][#grouped[signature] + 1] = record
    end
    local result = {}
    for signature, values in pairs(grouped) do
        table.sort(values, function(left, right)
            if left.minutes ~= right.minutes then return left.minutes < right.minutes end
            return recordBetter(left, right)
        end)
        local bestValue = -math.huge
        for _, record in ipairs(values) do
            if record.valueCopper > bestValue then
                bestValue = record.valueCopper
                result[roundedTimeKey(record.minutes) .. "|" .. signature] = record
            end
        end
    end
    return result
end


local function candidateCompleted(addonObject, task, daily)
    local manual = daily.manualCompletion[task.id]
    if manual ~= nil then
        return manual == true, "手动"
    end
    if daily.completedTasks[task.id] then
        return true, "本周期记录"
    end
    for _, questID in ipairs(task.questIDs or {}) do
        if daily.completedQuestIDs[questID] then
            return true, "交付事件"
        end
        local completed, source = addonObject.Compat38002:IsQuestCompleted(questID)
        if completed == true then
            return true, source
        end
    end
    return false, "未确认"
end


local function findSelectedQuest(addonObject, task, daily)
    local selected = daily.professionSelections[task.id]
    if selected then
        return tonumber(selected), "手动选择"
    end
    for _, questID in ipairs(task.questIDs or {}) do
        local onLog = addonObject.Compat38002:IsQuestOnLog(questID)
        if onLog == true then
            return questID, "任务日志"
        end
    end
    for _, questID in ipairs(task.questIDs or {}) do
        if daily.discoveredQuestIDs[questID] then
            return questID, "当前 NPC"
        end
    end
    return nil, "未识别具体任务"
end


local function resolveUnlock(addonObject, task, context, selectedQuestID)
    local character = addonObject:GetCharacterData()
    local override = character.unlockOverrides[task.id]
    if override ~= nil then
        return override == true and "yes" or "no", "手动"
    end
    if context.level ~= 80 then
        return "no", "等级不是 80"
    end
    if task.faction and context.faction and task.faction ~= context.faction then
        return "no", "阵营不匹配"
    end
    if task.professionID then
        local profession = context.professionsByID[task.professionID]
        if not profession then
            return "no", "未学习" .. (addonObject.PROFESSION_NAMES[task.professionID] or "对应专业")
        end
        if profession.rank and profession.rank < (task.minProfessionRank or 0) then
            return "no", "专业技能不足"
        end
        return "yes", "专业自动识别"
    end
    if selectedQuestID then
        return "yes", "任务日志或当前 NPC"
    end
    return "unknown", "前置/声望状态未知"
end


function addon:GetPlanningContext(override)
    override = type(override) == "table" and override or {}
    local professions, professionsByID = self.Compat38002:GetProfessions()
    return {
        level = override.level or self.Compat38002:GetPlayerLevel(),
        faction = override.faction or self.Compat38002:GetFaction(),
        professions = override.professions or professions,
        professionsByID = override.professionsByID or professionsByID,
        mode = override.mode,
        startRegion = override.startRegion,
    }
end


function addon:BuildTaskCandidate(task, context)
    context = context or self:GetPlanningContext()
    local daily = self:GetDailyState()
    local correction = self:GetTaskCorrection(task.id) or {}
    local selectedQuestID, selectionSource = findSelectedQuest(self, task, daily)
    local completed, completionSource = candidateCompleted(self, task, daily)
    local unlock, unlockSource = resolveUnlock(self, task, context, selectedQuestID)
    local duration, durationSource, durationSourceType = self:GetTaskDuration(task)
    local valuation = self:GetTaskValuation(task, selectedQuestID)
    local region = correction.region or task.region
    local title = task.name
    local titleSource = "目录"
    if selectedQuestID then
        title, titleSource = self.Compat38002:GetQuestTitle(selectedQuestID, title)
    elseif not task.pool and task.questIDs and #task.questIDs == 1 then
        title, titleSource = self.Compat38002:GetQuestTitle(task.questIDs[1], title)
    end

    local efficiency
    if valuation.netCopper and duration and duration > 0 then
        efficiency = valuation.netCopper / 10000 * 60 / duration
    end
    local preference = self:GetCharacterData().preferences
    local threshold = tonumber(preference.minimumGoldPerHour)
    local belowThreshold = valuation.netCopper ~= nil
        and (valuation.netCopper <= 0 or (threshold and efficiency and efficiency < threshold))
    local status
    local statusReason
    if completed then
        status = "completed"
        statusReason = "今日已完成（" .. completionSource .. "）"
    elseif unlock == "no" then
        status = "locked"
        statusReason = unlockSource
    elseif not duration then
        status = "incomplete"
        statusReason = "任务耗时数据缺失"
    elseif not valuation.costsKnown then
        status = "incomplete"
        statusReason = "必需成本未知"
    elseif belowThreshold then
        status = "below_threshold"
        statusReason = valuation.netCopper <= 0 and "明确净价值不大于 0" or "低于当前角色收益门槛"
    elseif unlock == "yes" and (selectedQuestID or completionSource == "手动") then
        status = "executable"
        statusReason = "当前明确可执行"
    elseif unlock == "yes" and task.professionID then
        status = "unknown"
        statusReason = "专业符合；今天具体任务/完成状态未知"
    else
        status = "unknown"
        statusReason = "解锁或今日完成状态未知"
    end

    local mode = context.mode or preference.mode
    local modeAllowed = not (mode == "workday" and duration and duration > 30)
    local autoEligible = (status == "executable" or status == "unknown")
        and valuation.netCopper ~= nil
        and valuation.netCopper > 0
        and modeAllowed
        and not belowThreshold

    local questIDText = {}
    for _, questID in ipairs(task.questIDs or {}) do questIDText[#questIDText + 1] = tostring(questID) end
    local professionName = task.professionID and self.PROFESSION_NAMES[task.professionID] or ""
    local activityType = task.activityType or "固定日常"
    local searchText = normalizeSearch(table.concat({
        title,
        task.name,
        self:GetRegionName(region),
        professionName,
        activityType,
        table.concat(questIDText, " "),
    }, " "))

    return {
        id = task.id,
        kind = "task",
        catalog = task,
        title = title,
        titleSource = titleSource,
        region = region,
        regionName = self:GetRegionName(region),
        activityType = activityType,
        professionName = professionName,
        questIDs = task.questIDs,
        selectedQuestID = selectedQuestID,
        selectionSource = selectionSource,
        durationMinutes = duration,
        durationSource = durationSource,
        durationSourceType = durationSourceType,
        valuation = valuation,
        netCopper = valuation.netCopper,
        efficiencyGoldPerHour = efficiency,
        status = status,
        statusReason = statusReason,
        unlock = unlock,
        unlockSource = unlockSource,
        autoEligible = autoEligible,
        modeAllowed = modeAllowed,
        order = task.order,
        searchText = searchText,
        exclusiveGroup = task.exclusiveGroup,
        exclusiveChoice = task.exclusiveChoice,
    }
end


function addon:BuildRaidCandidate(raid)
    local state, stateSource = self:GetRaidState(raid.id)
    local duration, durationSource, durationSourceType = self:GetRaidDuration(raid)
    return {
        id = raid.id,
        kind = "raid",
        catalog = raid,
        title = raid.shortName .. "（" .. raid.name .. "）",
        activityType = "团本",
        regionName = "团本时间块",
        durationMinutes = duration,
        durationSource = durationSource,
        durationSourceType = durationSourceType,
        state = state,
        stateSource = stateSource,
        status = state == "complete" and "completed" or "raid",
        statusReason = state == "complete" and "本周已完成" or (
            state == "partial" and "部分进度；耗时为保守估计" or "本周状态" .. (state == "unknown" and "未知" or "未完成")
        ),
        order = raid.order,
        searchText = normalizeSearch(table.concat({
            raid.shortName, raid.name, raid.phase, "团本", tostring(raid.players),
        }, " ")),
    }
end


function addon:BuildAllCandidates(contextOverride)
    local context = self:GetPlanningContext(contextOverride)
    local candidates = {}
    for _, task in ipairs(self.TASK_CATALOG) do
        candidates[#candidates + 1] = self:BuildTaskCandidate(task, context)
    end
    for _, raid in ipairs(self.RAID_CATALOG) do
        candidates[#candidates + 1] = self:BuildRaidCandidate(raid)
    end

    table.sort(candidates, function(left, right)
        local groupOrder = {
            executable = 1,
            unknown = 2,
            below_threshold = 3,
            raid = 4,
            incomplete = 5,
            locked = 6,
            completed = 7,
        }
        local leftGroup = groupOrder[left.status] or 99
        local rightGroup = groupOrder[right.status] or 99
        if leftGroup ~= rightGroup then return leftGroup < rightGroup end
        if left.kind == "task" and right.kind == "task" then
            local leftEfficiency = left.efficiencyGoldPerHour or -math.huge
            local rightEfficiency = right.efficiencyGoldPerHour or -math.huge
            if leftEfficiency ~= rightEfficiency then return leftEfficiency > rightEfficiency end
        end
        return (left.order or 9999) < (right.order or 9999)
    end)
    return candidates
end


function addon:FilterCandidates(candidates, query)
    query = normalizeSearch(query)
    if query == "" then
        return copyArray(candidates), 0
    end
    local terms = {}
    for term in query:gmatch("[^%s]+") do terms[#terms + 1] = term end
    local result = {}
    for _, candidate in ipairs(candidates or {}) do
        local matches = true
        for _, term in ipairs(terms) do
            if not candidate.searchText:find(term, 1, true) then
                matches = false
                break
            end
        end
        if matches then result[#result + 1] = candidate end
    end
    return result, #result
end


local function buildRegionOptions(candidates, requiredIDs, maximumMinutes)
    local required = {}
    local optional = {}
    for _, candidate in ipairs(candidates) do
        if requiredIDs[candidate.id] then
            required[#required + 1] = candidate
        else
            optional[#optional + 1] = candidate
        end
    end

    local base = {
        minutes = 0,
        valueCopper = 0,
        selected = {},
        selectedIDs = {},
        choices = {},
        incompleteCount = 0,
        orderScore = 0,
    }
    for _, candidate in ipairs(required) do
        if not choicesCompatible(base.choices, candidate) then
            return {}, "required-conflict"
        end
        base.minutes = base.minutes + candidate.durationMinutes
        base.valueCopper = base.valueCopper + (candidate.netCopper or 0)
        base.selected[#base.selected + 1] = candidate
        base.selectedIDs[candidate.id] = true
        base.choices = addChoice(base.choices, candidate)
        base.incompleteCount = base.incompleteCount + (candidate.netCopper == nil and 1 or 0)
        base.orderScore = base.orderScore + (candidate.order or 9999)
    end
    if base.minutes > maximumMinutes + 0.0001 then
        return {}, "required-over-budget"
    end

    local states = {}
    local baseKey = roundedTimeKey(base.minutes) .. "|" .. choiceSignature(base.choices)
    states[baseKey] = base
    for _, candidate in ipairs(optional) do
        local snapshot = {}
        for _, record in pairs(states) do snapshot[#snapshot + 1] = record end
        for _, record in ipairs(snapshot) do
            if choicesCompatible(record.choices, candidate) then
                local newMinutes = record.minutes + candidate.durationMinutes
                if newMinutes <= maximumMinutes + 0.0001 then
                    local nextRecord = {
                        minutes = newMinutes,
                        valueCopper = record.valueCopper + (candidate.netCopper or 0),
                        selected = copyArray(record.selected),
                        selectedIDs = copyMap(record.selectedIDs),
                        choices = addChoice(record.choices, candidate),
                        incompleteCount = record.incompleteCount + (candidate.netCopper == nil and 1 or 0),
                        orderScore = record.orderScore + (candidate.order or 9999),
                    }
                    nextRecord.selected[#nextRecord.selected + 1] = candidate
                    nextRecord.selectedIDs[candidate.id] = true
                    local key = roundedTimeKey(newMinutes) .. "|" .. choiceSignature(nextRecord.choices)
                    if recordBetter(nextRecord, states[key]) then states[key] = nextRecord end
                end
            end
        end
    end

    states = pruneStateMap(states)
    local options = {}
    for _, record in pairs(states) do
        if #record.selected > 0 then options[#options + 1] = record end
    end
    table.sort(options, function(left, right)
        if left.minutes ~= right.minutes then return left.minutes < right.minutes end
        return recordBetter(left, right)
    end)
    return options
end


function addon:OptimizeTaskRoute(candidates, budgetMinutes, startRegion, requiredIDs)
    budgetMinutes = math.max(0, tonumber(budgetMinutes) or 0)
    requiredIDs = type(requiredIDs) == "table" and requiredIDs or {}
    local byRegion = {}
    local regionIDs = {}
    local requiredRegion = {}

    for _, candidate in ipairs(candidates or {}) do
        if candidate.kind == "task" and candidate.durationMinutes then
            local region = candidate.region
            if not byRegion[region] then
                byRegion[region] = {}
                regionIDs[#regionIDs + 1] = region
            end
            byRegion[region][#byRegion[region] + 1] = candidate
            if requiredIDs[candidate.id] then requiredRegion[region] = true end
        end
    end

    table.sort(regionIDs, function(left, right)
        local leftOrder = self.REGIONS_BY_ID[left] and self.REGIONS_BY_ID[left].order or 999
        local rightOrder = self.REGIONS_BY_ID[right] and self.REGIONS_BY_ID[right].order or 999
        return leftOrder < rightOrder
    end)

    if #regionIDs == 0 then
        if countMap(requiredIDs) > 0 then return nil, "required-task-missing" end
        return {
            minutes = 0,
            taskMinutes = 0,
            routeMinutes = 0,
            valueCopper = 0,
            selected = {},
            selectedIDs = {},
            regions = {},
            edges = {},
            incompleteCount = 0,
            orderScore = 0,
            regionCount = 0,
        }
    end

    local optionsByRegion = {}
    local requiredMask = 0
    for index, region in ipairs(regionIDs) do
        local bit = 2 ^ (index - 1)
        if requiredRegion[region] then requiredMask = requiredMask + bit end
        local options, reason = buildRegionOptions(byRegion[region], requiredIDs, budgetMinutes)
        if #options == 0 and requiredRegion[region] then return nil, reason end
        optionsByRegion[index] = options
    end

    local states = {}
    local function setState(mask, lastIndex, record)
        states[mask] = states[mask] or {}
        states[mask][lastIndex] = states[mask][lastIndex] or {}
        local key = roundedTimeKey(record.minutes) .. "|" .. choiceSignature(record.choices)
        local current = states[mask][lastIndex][key]
        if recordBetter(record, current) then states[mask][lastIndex][key] = record end
    end

    for index, region in ipairs(regionIDs) do
        local travel, travelSource, travelSourceType = self:GetRouteDuration(startRegion, region)
        if travel ~= nil then
            for _, option in ipairs(optionsByRegion[index]) do
                local minutes = travel + option.minutes
                if minutes <= budgetMinutes + 0.0001 then
                    setState(2 ^ (index - 1), index, {
                        minutes = minutes,
                        taskMinutes = option.minutes,
                        routeMinutes = travel,
                        valueCopper = option.valueCopper,
                        selected = copyArray(option.selected),
                        selectedIDs = copyMap(option.selectedIDs),
                        choices = copyMap(option.choices),
                        incompleteCount = option.incompleteCount,
                        orderScore = option.orderScore,
                        regionCount = 1,
                        regions = { region },
                        edges = {
                            {
                                fromRegion = startRegion,
                                toRegion = region,
                                minutes = travel,
                                source = travelSource,
                                sourceType = travelSourceType,
                            },
                        },
                    })
                end
            end
        end
    end

    local maximumMask = (2 ^ #regionIDs) - 1
    for mask = 1, maximumMask do
        local byLast = states[mask]
        if byLast then
            for lastIndex, byTime in pairs(byLast) do
                byTime = pruneStateMap(byTime)
                byLast[lastIndex] = byTime
                local snapshot = {}
                for _, record in pairs(byTime) do snapshot[#snapshot + 1] = record end
                for nextIndex, region in ipairs(regionIDs) do
                    local bit = 2 ^ (nextIndex - 1)
                    local visited = math.floor(mask / bit) % 2 == 1
                    if not visited then
                        local fromRegion = regionIDs[lastIndex]
                        local travel, travelSource, travelSourceType = self:GetRouteDuration(fromRegion, region)
                        if travel ~= nil then
                            for _, record in ipairs(snapshot) do
                                for _, option in ipairs(optionsByRegion[nextIndex]) do
                                    local compatible = true
                                    for group, choice in pairs(option.choices or {}) do
                                        if record.choices[group] and record.choices[group] ~= choice then
                                            compatible = false
                                            break
                                        end
                                    end
                                    local minutes = record.minutes + travel + option.minutes
                                    if compatible and minutes <= budgetMinutes + 0.0001 then
                                        local nextRecord = {
                                            minutes = minutes,
                                            taskMinutes = record.taskMinutes + option.minutes,
                                            routeMinutes = record.routeMinutes + travel,
                                            valueCopper = record.valueCopper + option.valueCopper,
                                            selected = copyArray(record.selected),
                                            selectedIDs = copyMap(record.selectedIDs),
                                            choices = copyMap(record.choices),
                                            incompleteCount = record.incompleteCount + option.incompleteCount,
                                            orderScore = record.orderScore + option.orderScore,
                                            regionCount = record.regionCount + 1,
                                            regions = copyArray(record.regions),
                                            edges = copyArray(record.edges),
                                        }
                                        for _, selected in ipairs(option.selected) do
                                            nextRecord.selected[#nextRecord.selected + 1] = selected
                                            nextRecord.selectedIDs[selected.id] = true
                                        end
                                        for group, choice in pairs(option.choices or {}) do
                                            nextRecord.choices[group] = choice
                                        end
                                        nextRecord.regions[#nextRecord.regions + 1] = region
                                        nextRecord.edges[#nextRecord.edges + 1] = {
                                            fromRegion = fromRegion,
                                            toRegion = region,
                                            minutes = travel,
                                            source = travelSource,
                                            sourceType = travelSourceType,
                                        }
                                        setState(mask + bit, nextIndex, nextRecord)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local best
    for mask, byLast in pairs(states) do
        local includesRequired = math.floor(mask / math.max(1, requiredMask)) >= 0
        if requiredMask > 0 then
            includesRequired = true
            for index = 1, #regionIDs do
                local bit = 2 ^ (index - 1)
                if math.floor(requiredMask / bit) % 2 == 1 and math.floor(mask / bit) % 2 == 0 then
                    includesRequired = false
                    break
                end
            end
        end
        if includesRequired then
            for _, byTime in pairs(byLast) do
                for _, record in pairs(byTime) do
                    local hasAllRequired = true
                    for requiredID in pairs(requiredIDs) do
                        if not record.selectedIDs[requiredID] then
                            hasAllRequired = false
                            break
                        end
                    end
                    if hasAllRequired and recordBetter(record, best) then best = record end
                end
            end
        end
    end
    return best, best and nil or "no-complete-route"
end


local function candidateMap(candidates)
    local result = {}
    for _, candidate in ipairs(candidates or {}) do result[candidate.id] = candidate end
    return result
end


function addon:SelectAutomaticRaid(mode, declaredMinutes, availableBudget, candidates, excludedIDs)
    if mode ~= "holiday" then return nil end
    local allowedAll = declaredMinutes >= 180
    for _, raid in ipairs(self.RAID_CATALOG) do
        local candidate = candidates[raid.id]
        local allowed = allowedAll or raid.id == "raid:vault"
        if allowed and candidate and candidate.state ~= "complete"
            and not excludedIDs[raid.id]
            and candidate.durationMinutes <= availableBudget + 0.0001 then
            return candidate
        end
    end
    return nil
end


local function makePlanRows(addonObject, route, raidCandidates, sourceByID)
    local rows = {}
    for _, raid in ipairs(raidCandidates or {}) do
        rows[#rows + 1] = {
            id = raid.id,
            candidateID = raid.id,
            kind = "raid",
            title = raid.title,
            durationMinutes = raid.durationMinutes,
            durationSource = raid.durationSource,
            source = sourceByID[raid.id] or "automatic",
            generatedNetCopper = 0,
            currentNetCopper = 0,
            completed = false,
            skipped = false,
        }
    end

    if route then
        local byRegion = {}
        for _, candidate in ipairs(route.selected or {}) do
            byRegion[candidate.region] = byRegion[candidate.region] or {}
            byRegion[candidate.region][#byRegion[candidate.region] + 1] = candidate
        end
        for index, region in ipairs(route.regions or {}) do
            local edge = route.edges[index]
            if edge and edge.fromRegion ~= edge.toRegion then
                rows[#rows + 1] = {
                    id = "route:" .. tostring(index) .. ":" .. edge.fromRegion .. ":" .. edge.toRegion,
                    kind = "route",
                    title = "前往" .. addonObject:GetRegionName(edge.toRegion),
                    fromRegion = edge.fromRegion,
                    toRegion = edge.toRegion,
                    durationMinutes = edge.minutes,
                    durationSource = edge.source,
                    durationSourceType = edge.sourceType,
                    source = "route",
                    generatedNetCopper = 0,
                    currentNetCopper = 0,
                }
            end
            table.sort(byRegion[region] or {}, function(left, right)
                return (left.order or 9999) < (right.order or 9999)
            end)
            for _, candidate in ipairs(byRegion[region] or {}) do
                rows[#rows + 1] = {
                    id = candidate.id,
                    candidateID = candidate.id,
                    kind = "task",
                    title = candidate.title,
                    region = candidate.region,
                    regionName = candidate.regionName,
                    questIDs = candidate.questIDs,
                    selectedQuestID = candidate.selectedQuestID,
                    durationMinutes = candidate.durationMinutes,
                    originalDurationMinutes = candidate.originalDurationMinutes or candidate.durationMinutes,
                    durationSource = candidate.durationSource,
                    durationSourceType = candidate.durationSourceType,
                    inProgressOverdue = candidate.inProgressOverdue,
                    source = sourceByID[candidate.id] or "automatic",
                    generatedNetCopper = candidate.netCopper,
                    currentNetCopper = candidate.netCopper,
                    generatedValuation = candidate.valuation,
                    statusAtGeneration = candidate.status,
                    completed = false,
                    skipped = false,
                }
            end
        end
    end
    return rows
end


local function summarizeRows(rows)
    local summary = {
        plannedMinutes = 0,
        taskMinutes = 0,
        routeMinutes = 0,
        raidMinutes = 0,
        generatedNetCopper = 0,
        currentNetCopper = 0,
        incompleteValueCount = 0,
    }
    for _, row in ipairs(rows or {}) do
        summary.plannedMinutes = summary.plannedMinutes + (row.durationMinutes or 0)
        if row.kind == "task" then
            summary.taskMinutes = summary.taskMinutes + (row.durationMinutes or 0)
            if row.generatedNetCopper == nil then
                summary.incompleteValueCount = summary.incompleteValueCount + 1
            else
                summary.generatedNetCopper = summary.generatedNetCopper + row.generatedNetCopper
            end
            if row.currentNetCopper ~= nil then
                summary.currentNetCopper = summary.currentNetCopper + row.currentNetCopper
            end
        elseif row.kind == "route" then
            summary.routeMinutes = summary.routeMinutes + (row.durationMinutes or 0)
        elseif row.kind == "raid" then
            summary.raidMinutes = summary.raidMinutes + (row.durationMinutes or 0)
        end
    end
    return summary
end


function addon:BuildPlan(input)
    local mode = self:IsValidMode(input.mode) and input.mode or "workday"
    local declaredMinutes = tonumber(input.declaredMinutes) or 0
    local elapsedMinutes = math.max(0, tonumber(input.elapsedMinutes) or 0)
    local remaining = math.max(0, declaredMinutes - elapsedMinutes)
    local budget = remaining * self.PLANNING_RATIO
    local context = self:GetPlanningContext({ mode = mode, startRegion = input.startRegion })
    local allCandidates = self:BuildAllCandidates(context)
    local byID = candidateMap(allCandidates)
    for candidateID, remainingMinutes in pairs(input.remainingDurationOverrides or {}) do
        local candidate = byID[candidateID]
        if candidate and candidate.kind == "task" then
            candidate.originalDurationMinutes = input.originalDurationOverrides
                and input.originalDurationOverrides[candidateID] or candidate.durationMinutes
            candidate.durationMinutes = math.max(0, tonumber(remainingMinutes) or 0)
            candidate.durationSource = "进行中剩余（原预计减有效计时）"
            candidate.durationSourceType = "in-progress"
            candidate.inProgressOverdue = candidate.durationMinutes <= 0
        end
    end
    local excludedIDs = type(input.excludedIDs) == "table" and input.excludedIDs or {}
    local fixedIDs = type(input.fixedTaskIDs) == "table" and input.fixedTaskIDs or {}
    local confirmedRaidIDs = type(input.confirmedRaidIDs) == "table" and input.confirmedRaidIDs or {}
    local sourceByID = type(input.sourceByID) == "table" and copyMap(input.sourceByID) or {}
    local fixedTasks = {}
    local fixedTaskMap = {}
    local fixedRaids = {}
    local fixedRaidMinutes = 0

    for taskID in pairs(fixedIDs) do
        local candidate = byID[taskID]
        if candidate and candidate.kind == "task" and not excludedIDs[taskID]
            and candidate.status ~= "completed" and candidate.durationMinutes then
            fixedTasks[#fixedTasks + 1] = candidate
            fixedTaskMap[taskID] = true
            sourceByID[taskID] = sourceByID[taskID] or "manual"
        end
    end
    for raidID in pairs(confirmedRaidIDs) do
        local candidate = byID[raidID]
        if candidate and candidate.kind == "raid" and not excludedIDs[raidID]
            and candidate.state ~= "complete" then
            fixedRaids[#fixedRaids + 1] = candidate
            fixedRaidMinutes = fixedRaidMinutes + candidate.durationMinutes
            sourceByID[raidID] = sourceByID[raidID] or "confirmed"
        end
    end
    table.sort(fixedRaids, function(left, right) return left.order < right.order end)

    local fixedRoute
    if #fixedTasks > 0 then
        fixedRoute = self:OptimizeTaskRoute(fixedTasks, 100000, input.startRegion, fixedTaskMap)
    else
        fixedRoute = self:OptimizeTaskRoute({}, 0, input.startRegion, {})
    end
    local fixedMinutes = fixedRaidMinutes + (fixedRoute and fixedRoute.minutes or 0)
    local stopAutomatic = input.blockAutomatic == true
        or fixedMinutes > budget + 0.0001 or fixedRoute == nil
    local raids = copyArray(fixedRaids)
    local taskBudget = math.max(0, budget - fixedRaidMinutes)

    if not stopAutomatic and input.disableAutomaticRaid ~= true then
        local automaticRaid = self:SelectAutomaticRaid(
            mode,
            declaredMinutes,
            math.max(0, budget - fixedMinutes),
            byID,
            excludedIDs
        )
        if automaticRaid and not confirmedRaidIDs[automaticRaid.id] then
            raids[#raids + 1] = automaticRaid
            sourceByID[automaticRaid.id] = "automatic"
            taskBudget = math.max(0, taskBudget - automaticRaid.durationMinutes)
        end
    end

    local known = copyArray(fixedTasks)
    local unknown = {}
    if not stopAutomatic then
        for _, candidate in ipairs(allCandidates) do
            if candidate.kind == "task" and candidate.autoEligible and not fixedTaskMap[candidate.id]
                and not excludedIDs[candidate.id] then
                if candidate.status == "executable" then
                    known[#known + 1] = candidate
                elseif candidate.status == "unknown" then
                    unknown[#unknown + 1] = candidate
                end
            end
        end
    end

    local route, routeReason = self:OptimizeTaskRoute(known, taskBudget, input.startRegion, fixedTaskMap)
    if not route then route = fixedRoute end
    if route and not stopAutomatic and #unknown > 0 then
        local selectedKnown = copyMap(fixedTaskMap)
        local combined = {}
        for _, candidate in ipairs(route.selected or {}) do
            combined[#combined + 1] = candidate
            selectedKnown[candidate.id] = true
        end
        for _, candidate in ipairs(unknown) do combined[#combined + 1] = candidate end
        local supplemented = self:OptimizeTaskRoute(combined, taskBudget, input.startRegion, selectedKnown)
        if supplemented then route = supplemented end
    end

    local rows = makePlanRows(self, route, raids, sourceByID)
    local summary = summarizeRows(rows)
    summary.budgetMinutes = budget
    summary.remainingMinutes = remaining
    summary.fixedMinutes = fixedMinutes
    summary.overBudget = summary.plannedMinutes > budget + 0.0001
    summary.routeReason = routeReason
    summary.inProgressOverdue = input.blockAutomatic == true
    summary.firstLegExcluded = input.startRegion == "other" and route and #route.regions > 0

    if #rows == 0 then
        local nearest
        for _, candidate in ipairs(allCandidates) do
            if candidate.kind == "task" and candidate.autoEligible and candidate.durationMinutes then
                local travel = self:GetRouteDuration(input.startRegion, candidate.region)
                if travel ~= nil then
                    local total = travel + candidate.durationMinutes
                    local over = total - taskBudget
                    if over > 0 and (not nearest or over < nearest.overMinutes
                        or (over == nearest.overMinutes and candidate.order < nearest.candidate.order)) then
                        nearest = { candidate = candidate, overMinutes = over, totalMinutes = total }
                    end
                end
            end
        end
        summary.nearestCandidate = nearest
    end
    return {
        rows = rows,
        summary = summary,
        candidates = allCandidates,
        input = {
            mode = mode,
            declaredMinutes = declaredMinutes,
            elapsedMinutes = elapsedMinutes,
            startRegion = input.startRegion,
        },
    }
end


function addon:CreateSession(input)
    if not self.Compat38002:IsSupportedCharacter() then
        return nil, "Todo 仅支持 80 级角色"
    end
    local hours = self:NormalizeHours(input.hours)
    if not hours then return nil, "至少可玩时长必须大于 0" end
    if not self:IsValidMode(input.mode) then return nil, "模式无效" end
    if not self.REGIONS_BY_ID[input.startRegion] then return nil, "必须手选开始区域" end

    local now = self.Compat38002:GetNow()
    local confirmedRaidIDs = {}
    for raidID, selected in pairs(input.confirmedRaidIDs or {}) do
        if selected then confirmedRaidIDs[raidID] = true end
    end
    local plan = self:BuildPlan({
        mode = input.mode,
        declaredMinutes = hours * 60,
        elapsedMinutes = 0,
        startRegion = input.startRegion,
        confirmedRaidIDs = confirmedRaidIDs,
        disableAutomaticRaid = input.considerRaids == false,
    })
    local session = {
        id = tostring(now) .. ":" .. self.Compat38002:GetCharacterKey(),
        startedAt = now,
        baseElapsedSeconds = 0,
        declaredMinutes = hours * 60,
        mode = input.mode,
        startRegion = input.startRegion,
        confirmedRaidIDs = confirmedRaidIDs,
        considerRaids = input.considerRaids ~= false,
        manualTaskIDs = {},
        skippedIDs = {},
        inProgressIDs = {},
        sourceByID = {},
        plan = plan,
        generatedAt = now,
        dailyResetKey = self:GetDailyState().key,
        weeklyResetKey = self:GetWeeklyState().key,
        tracking = { activeTasks = {} },
    }
    local character = self:GetCharacterData()
    character.preferences.mode = input.mode
    character.preferences.hours = hours
    character.preferences.startRegion = input.startRegion
    self:SetActiveSession(session)
    return session
end


function addon:PreviewSession(input)
    local hours = self:NormalizeHours(input.hours)
    if not hours or not self:IsValidMode(input.mode) or not self.REGIONS_BY_ID[input.startRegion] then
        return nil
    end
    return self:BuildPlan({
        mode = input.mode,
        declaredMinutes = hours * 60,
        elapsedMinutes = 0,
        startRegion = input.startRegion,
        confirmedRaidIDs = input.confirmedRaidIDs or {},
        disableAutomaticRaid = input.considerRaids == false,
    })
end


function addon:ReplanSession()
    local session = self:GetActiveSession()
    if not session then return nil, "当前没有计划" end
    if type(self.FlushTaskTime) == "function" then self:FlushTaskTime() end
    local elapsedMinutes = self:GetSessionElapsedSeconds(session) / 60
    local fixed = copyMap(session.manualTaskIDs)
    local remainingDurationOverrides = {}
    local originalDurationOverrides = {}
    local blockAutomatic = false
    for taskID in pairs(session.inProgressIDs or {}) do fixed[taskID] = true end
    for taskID in pairs(session.inProgressIDs or {}) do
        local originalMinutes
        for _, row in ipairs(session.plan.rows or {}) do
            if row.candidateID == taskID then originalMinutes = row.durationMinutes break end
        end
        local timer = session.tracking and session.tracking.activeTasks
            and session.tracking.activeTasks[taskID]
        originalMinutes = timer and tonumber(timer.originalEstimatedMinutes) or originalMinutes
        local allocatedMinutes = timer and (tonumber(timer.allocatedSeconds) or 0) / 60 or 0
        if originalMinutes then
            remainingDurationOverrides[taskID] = math.max(0, originalMinutes - allocatedMinutes)
            originalDurationOverrides[taskID] = originalMinutes
            if remainingDurationOverrides[taskID] <= 0 then blockAutomatic = true end
        end
    end
    local plan = self:BuildPlan({
        mode = session.mode,
        declaredMinutes = session.declaredMinutes,
        elapsedMinutes = elapsedMinutes,
        startRegion = session.startRegion,
        confirmedRaidIDs = session.confirmedRaidIDs,
        disableAutomaticRaid = session.considerRaids == false,
        fixedTaskIDs = fixed,
        excludedIDs = session.skippedIDs,
        sourceByID = session.sourceByID,
        remainingDurationOverrides = remainingDurationOverrides,
        originalDurationOverrides = originalDurationOverrides,
        blockAutomatic = blockAutomatic,
    })
    session.plan = plan
    session.replannedAt = self.Compat38002:GetNow()
    session.resetInvalidated = nil
    return session
end


function addon:UpdateSessionDeclaredMinutes(minutes)
    local session = self:GetActiveSession()
    minutes = tonumber(minutes)
    if not session or not minutes or minutes <= 0 then return false end
    session.declaredMinutes = minutes
    self:GetCharacterData().preferences.hours = minutes / 60
    return true
end


function addon:ExtendSession(extraMinutes)
    local session = self:GetActiveSession()
    extraMinutes = tonumber(extraMinutes)
    if not session or not extraMinutes or extraMinutes <= 0 then return false end
    session.declaredMinutes = (self:GetSessionElapsedSeconds(session) / 60) + extraMinutes
    self:GetCharacterData().preferences.hours = session.declaredMinutes / 60
    return true
end


local function findPlanRow(session, candidateID)
    for index, row in ipairs(session.plan.rows or {}) do
        if row.candidateID == candidateID or row.id == candidateID then
            return row, index
        end
    end
    return nil
end


function addon:AddCandidateToSession(candidateID)
    local session = self:GetActiveSession()
    if not session then return false, "请先生成本次计划" end
    if findPlanRow(session, candidateID) then return false, "该事项已在计划中" end
    local candidates = candidateMap(self:BuildAllCandidates({ mode = session.mode }))
    local candidate = candidates[candidateID]
    if not candidate or candidate.status == "completed" or candidate.status == "locked" then
        return false, "该事项当前不可加入"
    end
    if candidate.exclusiveGroup then
        for _, existingRow in ipairs(session.plan.rows or {}) do
            local existing = existingRow.candidateID and candidates[existingRow.candidateID]
            if not existingRow.skipped and existing and existing.kind == "task"
                and existing.exclusiveGroup == candidate.exclusiveGroup
                and (existing.exclusiveChoice or existing.id) ~= (candidate.exclusiveChoice or candidate.id) then
                return false, "与“" .. existing.title .. "”互斥；请先将已有项标记本次跳过后再加入"
            end
        end
    end

    if candidate.kind == "raid" then
        session.confirmedRaidIDs[candidateID] = true
        session.sourceByID[candidateID] = "manual"
        local row = makePlanRows(self, nil, { candidate }, session.sourceByID)[1]
        session.plan.rows[#session.plan.rows + 1] = row
        session.plan.summary = summarizeRows(session.plan.rows)
        session.plan.summary.budgetMinutes = math.max(0,
            (session.declaredMinutes - self:GetSessionElapsedSeconds(session) / 60) * self.PLANNING_RATIO
        )
        session.plan.summary.overBudget = session.plan.summary.plannedMinutes > session.plan.summary.budgetMinutes
        return true
    end

    if not candidate.durationMinutes then return false, "任务耗时数据缺失，不能手动绕过" end
    local tailRegion = session.startRegion
    local lastRegionIndex
    for index, row in ipairs(session.plan.rows) do
        if row.kind == "task" then
            tailRegion = row.region
            if row.region == candidate.region then lastRegionIndex = index end
        elseif row.kind == "route" then
            tailRegion = row.toRegion
        end
    end

    local newRows = {}
    if not lastRegionIndex and tailRegion ~= candidate.region then
        local travel, source, sourceType = self:GetRouteDuration(tailRegion, candidate.region)
        if travel == nil then return false, "必需移动耗时缺失，不能手动绕过" end
        newRows[#newRows + 1] = {
            id = "route:manual:" .. tostring(self.Compat38002:GetNow()),
            kind = "route",
            title = "前往" .. candidate.regionName,
            fromRegion = tailRegion,
            toRegion = candidate.region,
            durationMinutes = travel,
            durationSource = source,
            durationSourceType = sourceType,
            source = "manual-route",
            generatedNetCopper = 0,
            currentNetCopper = 0,
        }
    end
    local taskRow = makePlanRows(self, {
        selected = { candidate },
        regions = { candidate.region },
        edges = {},
    }, {}, { [candidate.id] = "manual" })[1]
    if not taskRow or taskRow.kind ~= "task" then
        taskRow = {
            id = candidate.id,
            candidateID = candidate.id,
            kind = "task",
            title = candidate.title,
            region = candidate.region,
            regionName = candidate.regionName,
            durationMinutes = candidate.durationMinutes,
            durationSource = candidate.durationSource,
            source = "manual",
            generatedNetCopper = candidate.netCopper,
            currentNetCopper = candidate.netCopper,
            generatedValuation = candidate.valuation,
        }
    end
    newRows[#newRows + 1] = taskRow

    local insertion = lastRegionIndex or #session.plan.rows
    for offset, row in ipairs(newRows) do
        table.insert(session.plan.rows, insertion + offset, row)
    end
    session.manualTaskIDs[candidate.id] = true
    session.sourceByID[candidate.id] = "manual"
    session.plan.summary = summarizeRows(session.plan.rows)
    session.plan.summary.budgetMinutes = math.max(0,
        (session.declaredMinutes - self:GetSessionElapsedSeconds(session) / 60) * self.PLANNING_RATIO
    )
    session.plan.summary.overBudget = session.plan.summary.plannedMinutes > session.plan.summary.budgetMinutes
    return true
end


function addon:SetPlanRowCompleted(candidateID, completed)
    local session = self:GetActiveSession()
    if not session then return false end
    local row = findPlanRow(session, candidateID)
    if not row then return false end
    row.completed = completed == true
    if row.kind == "task" then self:SetTaskCompletion(candidateID, completed, true) end
    return true
end


function addon:SetPlanRowSkipped(candidateID, skipped)
    local session = self:GetActiveSession()
    if not session then return false end
    local row = findPlanRow(session, candidateID)
    if not row then return false end
    row.skipped = skipped == true
    session.skippedIDs[candidateID] = skipped and true or nil
    return true
end


function addon:RefreshCurrentPlanValues()
    local session = self:GetActiveSession()
    if not session or not session.plan then return end
    local candidates = candidateMap(self:BuildAllCandidates({ mode = session.mode }))
    for _, row in ipairs(session.plan.rows or {}) do
        if row.kind == "task" then
            local candidate = candidates[row.candidateID]
            row.currentNetCopper = candidate and candidate.netCopper or nil
            row.valueChanged = row.currentNetCopper ~= row.generatedNetCopper
        end
    end
    local previous = session.plan.summary
    session.plan.summary = summarizeRows(session.plan.rows)
    session.plan.summary.budgetMinutes = previous.budgetMinutes
    session.plan.summary.remainingMinutes = previous.remainingMinutes
    session.plan.summary.overBudget = previous.overBudget
    session.plan.summary.firstLegExcluded = previous.firstLegExcluded
    session.plan.summary.nearestCandidate = previous.nearestCandidate
    session.plan.summary.inProgressOverdue = previous.inProgressOverdue
    session.plan.summary.routeReason = previous.routeReason
    session.plan.summary.fixedMinutes = previous.fixedMinutes
end


function addon:GetCandidateGroups(candidates)
    local definitions = {
        { id = "executable", name = "可执行" },
        { id = "unknown", name = "状态未知" },
        { id = "below_threshold", name = "低于门槛" },
        { id = "raid", name = "团本" },
        { id = "incomplete", name = "数据不完整" },
        { id = "locked", name = "未解锁" },
        { id = "completed", name = "今日 / 本周已完成" },
    }
    local grouped = {}
    for _, definition in ipairs(definitions) do
        grouped[definition.id] = { id = definition.id, name = definition.name, items = {} }
    end
    for _, candidate in ipairs(candidates or {}) do
        local groupID = candidate.status
        grouped[groupID] = grouped[groupID] or { id = groupID, name = groupID, items = {} }
        grouped[groupID].items[#grouped[groupID].items + 1] = candidate
    end
    local result = {}
    for _, definition in ipairs(definitions) do
        if #grouped[definition.id].items > 0 then result[#result + 1] = grouped[definition.id] end
    end
    return result
end
