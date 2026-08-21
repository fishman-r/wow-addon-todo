local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G.TodoAddon or {}
end

_G.TodoAddon = addon
addon.addonName = addonName or "Todo"

local Compat = {}
addon.Compat38002 = Compat

local function safeCall(callable, ...)
    if type(callable) ~= "function" then
        return false
    end

    return pcall(callable, ...)
end


function Compat:Call(callable, ...)
    return safeCall(callable, ...)
end


function Compat:GetBuild()
    local ok, version, build, buildDate, interfaceVersion = safeCall(GetBuildInfo)
    if not ok then
        return {
            version = "unknown",
            build = "unknown",
            buildDate = "unknown",
            interface = 0,
        }
    end

    return {
        version = tostring(version or "unknown"),
        build = tostring(build or "unknown"),
        buildDate = tostring(buildDate or "unknown"),
        interface = tonumber(interfaceVersion) or 0,
    }
end


function Compat:GetNow()
    local ok, value = safeCall(GetServerTime)
    if ok and type(value) == "number" then
        return value, "GetServerTime"
    end

    if type(C_DateAndTime) == "table" then
        ok, value = safeCall(C_DateAndTime.GetServerTimeLocal)
        if ok and type(value) == "number" then
            return value, "C_DateAndTime.GetServerTimeLocal"
        end
    end

    ok, value = safeCall(time)
    if ok and type(value) == "number" then
        return value, "time"
    end

    return 0, "unavailable"
end


function Compat:GetMonotonicNow()
    local ok, value = safeCall(GetTime)
    if ok and type(value) == "number" then
        return value, "GetTime"
    end

    return self:GetNow()
end


function Compat:GetPlayerLevel()
    local ok, level = safeCall(UnitLevel, "player")
    return ok and tonumber(level) or 0
end


function Compat:IsSupportedCharacter()
    return self:GetPlayerLevel() == 80
end


function Compat:GetFaction()
    local ok, faction = safeCall(UnitFactionGroup, "player")
    return ok and faction or "UnknownFaction"
end


function Compat:GetRealmName()
    local ok, realm = safeCall(GetRealmName)
    if ok and type(realm) == "string" and realm ~= "" then
        return realm
    end

    return "unknown-realm"
end


function Compat:GetCharacterKey()
    local realm = self:GetRealmName()
    local faction = self:GetFaction()
    local ok, guid = safeCall(UnitGUID, "player")
    if ok and type(guid) == "string" and guid ~= "" then
        return table.concat({ realm, faction, guid }, ":")
    end

    local name
    ok, name = safeCall(UnitFullName, "player")
    if not ok or type(name) ~= "string" or name == "" then
        ok, name = safeCall(UnitName, "player")
    end

    return table.concat({ realm, faction, tostring(name or "unknown-character") }, ":")
end


function Compat:GetMarketKey()
    -- Until the Titan auction topology is verified, faction markets remain isolated.
    return table.concat({ self:GetRealmName(), self:GetFaction() }, ":")
end


function Compat:GetLocale()
    local ok, locale = safeCall(GetLocale)
    return ok and tostring(locale) or "unknown"
end


function Compat:GetDailyResetInfo()
    local seconds
    local ok

    if type(C_DateAndTime) == "table" then
        ok, seconds = safeCall(C_DateAndTime.GetSecondsUntilDailyReset)
        if ok and type(seconds) == "number" and seconds >= 0 then
            return seconds, "C_DateAndTime", "available"
        end
    end

    ok, seconds = safeCall(GetQuestResetTime)
    if ok and type(seconds) == "number" and seconds >= 0 then
        return seconds, "GetQuestResetTime", "degraded"
    end

    return nil, "unavailable", "unavailable"
end


function Compat:GetWeeklyResetInfo()
    local seconds
    local ok

    if type(C_DateAndTime) == "table" then
        ok, seconds = safeCall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and type(seconds) == "number" and seconds >= 0 then
            return seconds, "C_DateAndTime", "available"
        end
    end

    ok, seconds = safeCall(GetRaidResetTime)
    if ok and type(seconds) == "number" and seconds >= 0 then
        return seconds, "GetRaidResetTime", "degraded"
    end

    return nil, "unavailable", "unavailable"
end


local function resetKey(prefix, now, seconds)
    if type(now) ~= "number" or type(seconds) ~= "number" then
        return nil
    end

    return prefix .. tostring(math.floor((now + seconds + 30) / 60))
end


function Compat:GetDailyResetKey()
    local now = self:GetNow()
    local seconds, source, status = self:GetDailyResetInfo()
    local key = resetKey("daily-", now, seconds)
    if key then
        return key, source, status
    end

    if type(date) == "function" then
        local ok, today = safeCall(date, "%Y-%m-%d")
        if ok and type(today) == "string" then
            return "calendar-" .. today, "date", "degraded"
        end
    end

    return "session-unknown", "unavailable", "unavailable"
end


function Compat:GetWeeklyResetKey()
    local now = self:GetNow()
    local seconds, source, status = self:GetWeeklyResetInfo()
    local key = resetKey("weekly-", now, seconds)
    if key then
        return key, source, status
    end

    return "weekly-unknown", "unavailable", "unavailable"
end


function Compat:IsInCombat()
    local ok, value = safeCall(InCombatLockdown)
    return ok and value == true
end


function Compat:IsAFK()
    local ok, value = safeCall(UnitIsAFK, "player")
    return ok and value == true
end


function Compat:GetQuestTitle(questID, fallback)
    if type(C_QuestLog) == "table" then
        local ok, title = safeCall(C_QuestLog.GetQuestInfo, tonumber(questID))
        if ok and type(title) == "string" and title ~= "" then
            return title, "C_QuestLog"
        end
    end

    return fallback or ("任务 " .. tostring(questID)), "fallback"
end


function Compat:IsQuestCompleted(questID)
    if type(C_QuestLog) ~= "table"
        or type(C_QuestLog.IsQuestFlaggedCompleted) ~= "function" then
        return nil, "unavailable"
    end

    local ok, completed = safeCall(C_QuestLog.IsQuestFlaggedCompleted, tonumber(questID))
    if not ok then
        return nil, "failed"
    end

    return completed == true, "C_QuestLog"
end


function Compat:IsQuestOnLog(questID)
    if type(C_QuestLog) == "table" and type(C_QuestLog.IsOnQuest) == "function" then
        local ok, value = safeCall(C_QuestLog.IsOnQuest, tonumber(questID))
        if ok then
            return value == true, "C_QuestLog"
        end
    end

    for _, entry in ipairs(self:ScanQuestLog()) do
        if tonumber(entry.questID) == tonumber(questID) then
            return true, "quest-log-scan"
        end
    end

    return nil, "unavailable"
end


function Compat:ScanQuestLog()
    local entries = {}
    if type(GetNumQuestLogEntries) ~= "function" or type(GetQuestLogTitle) ~= "function" then
        return entries, "unavailable"
    end

    local ok, count = safeCall(GetNumQuestLogEntries)
    if not ok or type(count) ~= "number" then
        return entries, "failed"
    end

    local dailyFrequency = type(LE_QUEST_FREQUENCY_DAILY) == "number" and LE_QUEST_FREQUENCY_DAILY or 1
    if type(Enum) == "table" and type(Enum.QuestFrequency) == "table"
        and type(Enum.QuestFrequency.Daily) == "number" then
        dailyFrequency = Enum.QuestFrequency.Daily
    end

    for index = 1, count do
        local readOK, title, level, _, isHeader, _, isComplete, frequency, questID = safeCall(
            GetQuestLogTitle,
            index
        )
        if readOK and not isHeader and tonumber(questID) then
            local rewardMoney
            local moneyOK, money = safeCall(GetQuestLogRewardMoney, index)
            if moneyOK and type(money) == "number" then
                rewardMoney = money
            end

            entries[#entries + 1] = {
                index = index,
                questID = tonumber(questID),
                title = title,
                level = tonumber(level),
                isComplete = isComplete == true or isComplete == 1,
                frequency = frequency,
                isDaily = tonumber(frequency) == tonumber(dailyFrequency),
                rewardMoney = rewardMoney,
            }
        end
    end

    return entries, "quest-log-scan"
end


function Compat:GetGossipAvailableQuests()
    local quests = {}
    if type(C_GossipInfo) ~= "table" or type(C_GossipInfo.GetAvailableQuests) ~= "function" then
        return quests, "unavailable"
    end

    local ok, values = safeCall(C_GossipInfo.GetAvailableQuests)
    if not ok or type(values) ~= "table" then
        return quests, "failed"
    end

    for _, info in ipairs(values) do
        if type(info) == "table" and tonumber(info.questID) then
            quests[#quests + 1] = {
                questID = tonumber(info.questID),
                title = info.title,
                isDaily = info.frequency == 1 or info.isDaily == true,
            }
        end
    end

    return quests, "C_GossipInfo"
end


function Compat:GetProfessions()
    local professions = {}
    local byID = {}

    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return professions, byID, "unavailable"
    end

    local ok, first, second, archaeology, fishing, cooking, firstAid = safeCall(GetProfessions)
    if not ok then
        return professions, byID, "failed"
    end

    local slots = {}
    slots[1] = first
    slots[2] = second
    slots[3] = archaeology
    slots[4] = fishing
    slots[5] = cooking
    slots[6] = firstAid
    for index = 1, 6 do
        local professionIndex = slots[index]
        if type(professionIndex) == "number" then
            local infoOK, name, _, rank, maximum, _, _, skillLineID = safeCall(
                GetProfessionInfo,
                professionIndex
            )
            if infoOK and tonumber(skillLineID) then
                local info = {
                    id = tonumber(skillLineID),
                    name = name or ("专业 " .. tostring(skillLineID)),
                    rank = tonumber(rank),
                    maximum = tonumber(maximum),
                }
                professions[#professions + 1] = info
                byID[info.id] = info
            end
        end
    end

    table.sort(professions, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)
    return professions, byID, "GetProfessions"
end


function Compat:GetItemInfo(itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return nil, "invalid"
    end

    if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
        local ok, name, link, quality, itemLevel, requiredLevel, itemType, itemSubType,
            stackCount, equipLoc, texture, vendorPrice, classID, subclassID, bindType = safeCall(
                C_Item.GetItemInfo,
                itemID
            )
        if ok and name then
            return {
                itemID = itemID,
                name = name,
                link = link,
                vendorPrice = tonumber(vendorPrice) or 0,
                bindType = bindType,
                stackCount = stackCount,
                classID = classID,
                subclassID = subclassID,
            }, "C_Item"
        end
    end

    local ok, name, link, quality, itemLevel, requiredLevel, itemType, itemSubType,
        stackCount, equipLoc, texture, vendorPrice, classID, subclassID, bindType = safeCall(
            GetItemInfo,
            itemID
        )
    if ok and name then
        return {
            itemID = itemID,
            name = name,
            link = link,
            vendorPrice = tonumber(vendorPrice) or 0,
            bindType = bindType,
            stackCount = stackCount,
            classID = classID,
            subclassID = subclassID,
        }, "GetItemInfo"
    end

    return nil, "cache-miss"
end


function Compat:RequestRaidInfo()
    local ok = safeCall(RequestRaidInfo)
    return ok, ok and "requested" or "unavailable"
end


function Compat:GetSavedInstances()
    local instances = {}
    if type(GetNumSavedInstances) ~= "function" or type(GetSavedInstanceInfo) ~= "function" then
        return instances, "unavailable"
    end

    local ok, count = safeCall(GetNumSavedInstances)
    if not ok or type(count) ~= "number" then
        return instances, "failed"
    end

    for index = 1, count do
        local readOK, name, instanceID, reset, difficultyID, locked, extended,
            instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters,
            encounterProgress = safeCall(GetSavedInstanceInfo, index)
        if readOK and name then
            instances[#instances + 1] = {
                name = name,
                instanceID = tonumber(instanceID),
                reset = tonumber(reset),
                difficultyID = difficultyID,
                locked = locked == true,
                extended = extended == true,
                isRaid = isRaid == true,
                maxPlayers = tonumber(maxPlayers),
                difficultyName = difficultyName,
                numEncounters = tonumber(numEncounters),
                encounterProgress = tonumber(encounterProgress),
            }
        end
    end

    return instances, "GetSavedInstanceInfo"
end


function Compat:GetAddonVersion(addonID)
    if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
        local ok, version = safeCall(C_AddOns.GetAddOnMetadata, addonID, "Version")
        if ok then
            return tostring(version or "unknown")
        end
    end

    local ok, version = safeCall(GetAddOnMetadata, addonID, "Version")
    return ok and tostring(version or "unknown") or "unknown"
end


function Compat:ReadLegacyAuctionListings(requiredItemIDs)
    local result = {}
    if type(GetNumAuctionItems) ~= "function" or type(GetAuctionItemInfo) ~= "function"
        or type(GetAuctionItemLink) ~= "function" then
        return result, "unavailable"
    end
    local ok, count = safeCall(GetNumAuctionItems, "list")
    if not ok or type(count) ~= "number" then return result, "failed" end
    for index = 1, count do
        local linkOK, link = safeCall(GetAuctionItemLink, "list", index)
        local itemID = tonumber(linkOK and type(link) == "string" and link:match("item:(%d+)") or nil)
        if itemID and requiredItemIDs[itemID] then
            local infoOK, _, _, quantity, _, _, _, _, _, buyout = safeCall(GetAuctionItemInfo, "list", index)
            quantity = tonumber(quantity)
            buyout = tonumber(buyout)
            if infoOK and quantity and quantity > 0 and buyout and buyout > 0 then
                result[itemID] = result[itemID] or {}
                result[itemID][#result[itemID] + 1] = buyout / quantity
            end
        end
    end
    return result, "legacy-read-only"
end


function Compat:IsAddonLoaded(addonID)
    if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, loaded = safeCall(C_AddOns.IsAddOnLoaded, addonID)
        return ok and loaded == true
    end

    local ok, loaded = safeCall(IsAddOnLoaded, addonID)
    return ok and loaded == true
end


function Compat:GetCapabilities()
    local build = self:GetBuild()
    local dailySeconds, dailySource, dailyStatus = self:GetDailyResetInfo()
    local weeklySeconds, weeklySource, weeklyStatus = self:GetWeeklyResetInfo()
    local auctionBranch = "unavailable"

    if type(C_AuctionHouse) == "table" then
        auctionBranch = "C_AuctionHouse-read-only-unverified"
    elseif type(GetNumAuctionItems) == "function" and type(GetAuctionItemInfo) == "function" then
        auctionBranch = "legacy-read-only"
    end

    return {
        build = build,
        level = self:GetPlayerLevel(),
        characterKey = self:GetCharacterKey(),
        marketKey = self:GetMarketKey(),
        locale = self:GetLocale(),
        dailyReset = {
            seconds = dailySeconds,
            source = dailySource,
            status = dailyStatus,
        },
        weeklyReset = {
            seconds = weeklySeconds,
            source = weeklySource,
            status = weeklyStatus,
        },
        questCompletion = type(C_QuestLog) == "table"
            and type(C_QuestLog.IsQuestFlaggedCompleted) == "function",
        gossip = type(C_GossipInfo) == "table"
            and type(C_GossipInfo.GetAvailableQuests) == "function",
        item = (type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function")
            or type(GetItemInfo) == "function",
        raid = type(RequestRaidInfo) == "function" and type(GetNumSavedInstances) == "function",
        auctionBranch = auctionBranch,
        auctionNeverQueries = true,
        timer = type(C_Timer) == "table" and type(C_Timer.After) == "function",
    }
end
