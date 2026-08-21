local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G.TodoAddon or {}
end

_G.TodoAddon = addon
addon.addonName = addonName or "Todo"

local function ensureTable(parent, key)
    if type(parent[key]) ~= "table" then
        parent[key] = {}
    end
    return parent[key]
end


local function shallowCopy(source)
    local result = {}
    if type(source) == "table" then
        for key, value in pairs(source) do
            result[key] = value
        end
    end
    return result
end


local function median(values)
    if #values == 0 then
        return nil
    end

    table.sort(values)
    local middle = math.floor((#values + 1) / 2)
    if #values % 2 == 1 then
        return values[middle]
    end
    return (values[middle] + values[middle + 1]) / 2
end


function addon:EnsureDatabase()
    if type(TodoDB) ~= "table" then
        if type(TitanFlowHelloDB) == "table" then
            TodoDB = TitanFlowHelloDB
        else
            TodoDB = {}
        end
    end
    TitanFlowHelloDB = nil

    local database = TodoDB
    local firstV1Migration = type(database.meta) ~= "table" or database.meta.schemaVersion == nil

    if firstV1Migration then
        database.legacyV03 = database.legacyV03 or {
            settings = shallowCopy(database.settings),
            questKnowledge = database.questKnowledge,
            ignoredDailies = database.ignoredDailies,
            characters = database.characters,
        }
    end

    local meta = ensureTable(database, "meta")
    local account = ensureTable(database, "account")
    local ui = ensureTable(account, "uiPreferences")
    ensureTable(account, "rewardBagDistributions")
    ensureTable(database, "markets")
    ensureTable(database, "characters")
    ensureTable(database, "localPendingTasks")

    if firstV1Migration and type(database.settings) == "table" then
        if ui.persistent == nil then
            ui.persistent = database.settings.persistent == true
        end
        if ui.position == nil and type(database.settings.position) == "table" then
            ui.position = shallowCopy(database.settings.position)
        end
    end

    ui.persistent = ui.persistent == true
    ui.hideMinimap = ui.hideMinimap == true
    ui.scale = tonumber(ui.scale) or 1
    meta.schemaVersion = self.SCHEMA_VERSION
    meta.catalogVersion = self.CATALOG_VERSION
    meta.addonVersion = self.ADDON_VERSION
    meta.lastMigration = firstV1Migration and "v0.3-to-v1-preview" or meta.lastMigration
    meta.migrationNotes = type(meta.migrationNotes) == "table" and meta.migrationNotes or {}
    if firstV1Migration then
        meta.migrationNotes[#meta.migrationNotes + 1] = "旧版手动耗时未迁入 v1 预计耗时。"
    end

    if not self.databaseInitializedThisLoad then
        if meta.writeProbe then
            meta.savedVariablesRoundTrip = true
        end
        local now = self.Compat38002:GetNow()
        meta.writeProbe = tostring(now) .. ":" .. tostring(math.random(100000, 999999))
        self.databaseInitializedThisLoad = true
    end

    return database
end


function addon:GetAccountData()
    return self:EnsureDatabase().account
end


function addon:GetUISettings()
    return self:GetAccountData().uiPreferences
end


function addon:GetCharacterData()
    local database = self:EnsureDatabase()
    local key = self.Compat38002:GetCharacterKey()
    local character = database.characters[key]
    if type(character) ~= "table" then
        character = {}
        database.characters[key] = character
    end

    local preferences = ensureTable(character, "preferences")
    if not self:IsValidMode(preferences.mode) then
        local legacyMode = database.legacyV03 and database.legacyV03.settings
            and database.legacyV03.settings.mode
        preferences.mode = self:IsValidMode(legacyMode) and legacyMode or "workday"
    end
    if not tonumber(preferences.hours) or tonumber(preferences.hours) <= 0 then
        local legacyHours = database.legacyV03 and database.legacyV03.settings
            and tonumber(database.legacyV03.settings.hours)
        preferences.hours = legacyHours and legacyHours > 0 and legacyHours or 2
    end
    if not self.REGIONS_BY_ID[preferences.startRegion] then
        preferences.startRegion = "dalaran"
    end
    preferences.minimumGoldPerHour = tonumber(preferences.minimumGoldPerHour)

    ensureTable(character, "tokenValues")
    ensureTable(character, "unlockOverrides")
    ensureTable(character, "cycleStates")
    ensureTable(character, "taskDurations")
    ensureTable(character, "routeDurations")
    ensureTable(character, "raidDurations")
    ensureTable(character, "pendingSamples")
    ensureTable(character, "discoveredQuests")
    ensureTable(character, "activeQuestTimers")
    return character
end


function addon:GetMarketData()
    local database = self:EnsureDatabase()
    local key = self.Compat38002:GetMarketKey()
    local market = database.markets[key]
    if type(market) ~= "table" then
        market = {}
        database.markets[key] = market
    end

    market.marketKey = key
    ensureTable(market, "nativeAuctionPrices")
    ensureTable(market, "externalAuctionPrices")
    ensureTable(market, "manualItemPrices")
    ensureTable(market, "observedQuestRewards")
    ensureTable(market, "taskCorrections")
    if tonumber(market.commissionRate) == nil then
        market.commissionRate = 0.05
        market.commissionSource = "preview-default-unverified"
    end
    return market
end


function addon:GetDailyState()
    local character = self:GetCharacterData()
    local key, source, status = self.Compat38002:GetDailyResetKey()
    local state = character.cycleStates.daily

    if type(state) ~= "table" or state.key ~= key then
        if type(state) == "table" and type(character.activeSession) == "table" then
            character.activeSession.resetInvalidated = true
            if type(self.InvalidateTrackingForReset) == "function" then
                self:InvalidateTrackingForReset("daily-reset")
            end
        end
        state = {
            key = key,
            source = source,
            sourceStatus = status,
            completedTasks = {},
            completedQuestIDs = {},
            manualCompletion = {},
            professionSelections = {},
            discoveredQuestIDs = {},
        }
        character.cycleStates.daily = state
    else
        state.completedTasks = type(state.completedTasks) == "table" and state.completedTasks or {}
        state.completedQuestIDs = type(state.completedQuestIDs) == "table" and state.completedQuestIDs or {}
        state.manualCompletion = type(state.manualCompletion) == "table" and state.manualCompletion or {}
        state.professionSelections = type(state.professionSelections) == "table"
            and state.professionSelections or {}
        state.discoveredQuestIDs = type(state.discoveredQuestIDs) == "table"
            and state.discoveredQuestIDs or {}
    end

    return state
end


function addon:GetWeeklyState()
    local character = self:GetCharacterData()
    local key, source, status = self.Compat38002:GetWeeklyResetKey()
    local state = character.cycleStates.weekly

    if type(state) ~= "table" or state.key ~= key then
        if type(state) == "table" and type(character.activeSession) == "table" then
            character.activeSession.resetInvalidated = true
            if type(self.InvalidateTrackingForReset) == "function" then
                self:InvalidateTrackingForReset("weekly-reset")
            end
        end
        state = {
            key = key,
            source = source,
            sourceStatus = status,
            raidOverrides = {},
            raidStates = {},
        }
        character.cycleStates.weekly = state
    else
        state.raidOverrides = type(state.raidOverrides) == "table" and state.raidOverrides or {}
        state.raidStates = type(state.raidStates) == "table" and state.raidStates or {}
    end

    return state
end


function addon:GetTaskCorrection(taskID)
    local market = self:GetMarketData()
    local correction = market.taskCorrections[taskID]
    return type(correction) == "table" and correction or nil
end


function addon:SetTaskCorrection(taskID, field, value)
    local market = self:GetMarketData()
    local correction = market.taskCorrections[taskID]
    if type(correction) ~= "table" then
        correction = {}
        market.taskCorrections[taskID] = correction
    end
    correction[field] = value
    correction.updatedAt = self.Compat38002:GetNow()
end


function addon:SetTaskCompletion(taskID, value, manual)
    local daily = self:GetDailyState()
    daily.completedTasks[taskID] = value == true and true or nil
    if manual then
        daily.manualCompletion[taskID] = value == nil and nil or value == true
    end
end


function addon:MarkQuestCompleted(questID)
    local daily = self:GetDailyState()
    questID = tonumber(questID)
    if not questID then
        return
    end
    daily.completedQuestIDs[questID] = true
    local task = self.QUEST_TO_TASK[questID]
    if task then
        daily.completedTasks[task.id] = true
    end
end


function addon:SetRaidOverride(raidID, state)
    local weekly = self:GetWeeklyState()
    if state == "not_done" or state == "partial" or state == "complete" then
        weekly.raidOverrides[raidID] = state
    else
        weekly.raidOverrides[raidID] = nil
    end
end


function addon:GetRaidState(raidID)
    local weekly = self:GetWeeklyState()
    if weekly.raidOverrides[raidID] then
        return weekly.raidOverrides[raidID], "manual"
    end
    local state = weekly.raidStates[raidID]
    if type(state) == "table" then
        return state.state or "unknown", state.source or "automatic"
    end
    return "unknown", "unobserved"
end


function addon:UpdateRaidStates(savedInstances)
    local weekly = self:GetWeeklyState()
    local matched = {}

    for _, instance in ipairs(savedInstances or {}) do
        local loweredName = string.lower(tostring(instance.name or ""))
        for _, raid in ipairs(self.RAID_CATALOG) do
            local isMatch = false
            for _, alias in ipairs(raid.aliases or {}) do
                if loweredName == string.lower(alias) then
                    isMatch = true
                    break
                end
            end
            if isMatch then
                local state = "unknown"
                if instance.encounterProgress and instance.numEncounters
                    and instance.numEncounters > 0 then
                    if instance.encounterProgress >= instance.numEncounters then
                        state = "complete"
                    elseif instance.encounterProgress > 0 then
                        state = "partial"
                    else
                        state = "not_done"
                    end
                elseif instance.locked then
                    state = "partial"
                end
                weekly.raidStates[raid.id] = {
                    state = state,
                    source = "GetSavedInstanceInfo",
                    instanceID = instance.instanceID,
                    updatedAt = self.Compat38002:GetNow(),
                    mappingStatus = "name-alias-unverified",
                }
                matched[raid.id] = true
                break
            end
        end
    end

    for _, raid in ipairs(self.RAID_CATALOG) do
        if not matched[raid.id] and type(weekly.raidStates[raid.id]) ~= "table" then
            weekly.raidStates[raid.id] = {
                state = "unknown",
                source = "unmapped",
                mappingStatus = "needs-38002-verification",
            }
        end
    end
end


local function sampleValues(sampleBucket)
    local values = {}
    if type(sampleBucket) == "table" and type(sampleBucket.valid) == "table" then
        for _, sample in ipairs(sampleBucket.valid) do
            local minutes = type(sample) == "table" and tonumber(sample.minutes) or tonumber(sample)
            if minutes and minutes > 0 then
                values[#values + 1] = minutes
            end
        end
    end
    return values
end


function addon:GetSampleMedian(sampleBucket)
    return median(sampleValues(sampleBucket))
end


function addon:GetTaskDuration(task)
    local character = self:GetCharacterData()
    local bucket = character.taskDurations[task.id]
    local learned = self:GetSampleMedian(bucket)
    if learned then
        return learned, "本角色实测中位数", "learned"
    end
    if tonumber(task.builtInMinutes) and task.builtInMinutes > 0 then
        return task.builtInMinutes, "内置参考", "builtin"
    end
    return nil, "缺失", "missing"
end


function addon:GetRouteDuration(fromRegion, toRegion)
    if fromRegion == toRegion then
        return 0, "同一区域", "same-region"
    end
    if fromRegion == "other" then
        return 0, "首段路程未计入", "first-leg-exempt"
    end

    local character = self:GetCharacterData()
    local fromBucket = character.routeDurations[fromRegion]
    local bucket = type(fromBucket) == "table" and fromBucket[toRegion] or nil
    local learned = self:GetSampleMedian(bucket)
    if learned then
        return learned, "本角色实测中位数", "learned"
    end

    local referenceFrom = self.ROUTE_REFERENCES[fromRegion]
    local reference = type(referenceFrom) == "table" and referenceFrom[toRegion] or nil
    if tonumber(reference) and reference >= 0 then
        return reference, "内置参考", "builtin"
    end
    return nil, "缺失", "missing"
end


function addon:GetRaidDuration(raid)
    local character = self:GetCharacterData()
    local learned = self:GetSampleMedian(character.raidDurations[raid.id])
    if learned then
        return learned, "本角色完整清团中位数", "learned"
    end
    return raid.defaultMinutes, "默认值", "default"
end


local function appendLimited(target, value, maximum)
    target[#target + 1] = value
    while #target > maximum do
        table.remove(target, 1)
    end
end


function addon:AddDurationSample(kind, key, minutes, metadata)
    minutes = tonumber(minutes)
    if not minutes or minutes <= 0 then
        return false, "样本耗时无效"
    end

    local character = self:GetCharacterData()
    local root
    local bucket
    if kind == "task" then
        root = character.taskDurations
        root[key] = type(root[key]) == "table" and root[key] or { valid = {}, pending = {} }
        bucket = root[key]
    elseif kind == "raid" then
        root = character.raidDurations
        root[key] = type(root[key]) == "table" and root[key] or { valid = {}, pending = {} }
        bucket = root[key]
    elseif kind == "route" and type(key) == "table" then
        local fromRegion, toRegion = key[1], key[2]
        root = character.routeDurations
        root[fromRegion] = type(root[fromRegion]) == "table" and root[fromRegion] or {}
        root[fromRegion][toRegion] = type(root[fromRegion][toRegion]) == "table"
            and root[fromRegion][toRegion] or { valid = {}, pending = {} }
        bucket = root[fromRegion][toRegion]
    else
        return false, "样本类型无效"
    end

    bucket.valid = type(bucket.valid) == "table" and bucket.valid or {}
    bucket.pending = type(bucket.pending) == "table" and bucket.pending or {}
    local baselineValues = sampleValues(bucket)
    local baseline = median(baselineValues)
    local suspicious = metadata and (metadata.afk or metadata.crossLogin
        or metadata.disconnected or metadata.crossCycle)
    local reason = suspicious and (metadata.crossCycle and "跨服务器重置" or "AFK、掉线或跨登录")
    if not suspicious and #baselineValues >= 3 and baseline then
        if minutes < baseline * 0.25 then
            suspicious = true
            reason = "短于当前中位数的 25%"
        elseif minutes > baseline * 4 then
            suspicious = true
            reason = "长于当前中位数的 400%"
        end
    end

    local sample = {
        minutes = minutes,
        recordedAt = self.Compat38002:GetNow(),
        metadata = metadata,
        reason = reason,
    }
    if suspicious then
        appendLimited(bucket.pending, sample, self.MAX_SAMPLES)
        character.pendingSamples[#character.pendingSamples + 1] = {
            kind = kind,
            key = key,
            sample = sample,
        }
        return true, "pending"
    end

    appendLimited(bucket.valid, sample, self.MAX_SAMPLES)
    return true, "valid"
end


function addon:GetActiveSession()
    return self:GetCharacterData().activeSession
end


function addon:SetActiveSession(session)
    self:GetCharacterData().activeSession = session
end


function addon:ClearActiveSession()
    self:GetCharacterData().activeSession = nil
end


function addon:GetSessionElapsedSeconds(session, now)
    session = session or self:GetActiveSession()
    if type(session) ~= "table" then
        return 0
    end
    now = tonumber(now) or self.Compat38002:GetNow()
    local base = tonumber(session.baseElapsedSeconds) or 0
    local startedAt = tonumber(session.startedAt) or now
    return math.max(0, base + math.max(0, now - startedAt))
end
