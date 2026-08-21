local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G.TodoAddon or {}
end

_G.TodoAddon = addon
addon.addonName = addonName or "Todo"

local function tableCount(values)
    local count = 0
    for _ in pairs(values or {}) do
        count = count + 1
    end
    return count
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


function addon:SetManualItemPrice(itemID, unitCopper)
    itemID = tonumber(itemID)
    unitCopper = tonumber(unitCopper)
    if not itemID or itemID <= 0 or not unitCopper or unitCopper < 0 then
        return false, "itemID 或价格无效"
    end

    local market = self:GetMarketData()
    if unitCopper == 0 then
        market.manualItemPrices[itemID] = nil
        return true, "deleted"
    end
    market.manualItemPrices[itemID] = {
        itemID = itemID,
        unitCopper = math.floor(unitCopper + 0.5),
        source = "manual",
        priceMetric = "用户税前单位价",
        marketKey = market.marketKey,
        updatedAt = self.Compat38002:GetNow(),
    }
    return true, "saved"
end


function addon:SetTokenValue(tokenID, unitCopper)
    tokenID = tostring(tokenID or "")
    unitCopper = tonumber(unitCopper)
    if tokenID == "" or not unitCopper or unitCopper < 0 then
        return false
    end
    local character = self:GetCharacterData()
    character.tokenValues[tokenID] = unitCopper == 0 and nil or math.floor(unitCopper + 0.5)
    return true
end


function addon:RecordNativeAuctionPrice(itemID, unitPrices, metadata)
    if not self.Compat38002:IsSupportedCharacter() then
        return false, "Todo 仅在 80 级记录价格"
    end

    itemID = tonumber(itemID)
    if not itemID or type(unitPrices) ~= "table" then
        return false, "搜索结果无法对应明确 itemID"
    end

    local valid = {}
    for _, price in ipairs(unitPrices) do
        price = tonumber(price)
        if price and price > 0 then
            valid[#valid + 1] = math.floor(price + 0.5)
        end
    end
    if #valid == 0 then
        return false, "空结果；旧缓存已保留"
    end

    table.sort(valid)
    local lowest = {}
    for index = 1, math.min(20, #valid) do
        lowest[#lowest + 1] = valid[index]
    end
    local price = median(lowest)
    local market = self:GetMarketData()
    market.nativeAuctionPrices[itemID] = {
        itemID = itemID,
        unitCopper = math.floor(price + 0.5),
        source = "TodoNative",
        priceMetric = "最低 20 条有效挂单中位数",
        marketKey = market.marketKey,
        sourceDataAt = metadata and metadata.sourceDataAt,
        capturedAt = self.Compat38002:GetNow(),
        sampleCount = #lowest,
        availableResultCount = #valid,
        lowSample = #lowest < 20,
        apiBranch = metadata and metadata.apiBranch,
    }
    market.lastNativeObservation = {
        itemID = itemID,
        status = "saved",
        sampleCount = #lowest,
        at = self.Compat38002:GetNow(),
        apiBranch = metadata and metadata.apiBranch,
    }
    return true, market.nativeAuctionPrices[itemID]
end


function addon:GetEffectiveMarketPrice(itemID)
    itemID = tonumber(itemID)
    local market = self:GetMarketData()
    local native = market.nativeAuctionPrices[itemID]
    if type(native) == "table" and tonumber(native.unitCopper) and native.unitCopper > 0 then
        return native
    end

    local provider = market.activeExternalProvider
    local providerPrices = provider and market.externalAuctionPrices[provider]
    local external = type(providerPrices) == "table" and providerPrices[itemID] or nil
    if type(external) == "table" and tonumber(external.unitCopper) and external.unitCopper > 0 then
        return external
    end

    local manual = market.manualItemPrices[itemID]
    if type(manual) == "table" and tonumber(manual.unitCopper) and manual.unitCopper > 0 then
        return manual
    end
    return nil
end


function addon:GetItemValue(itemID, options)
    options = type(options) == "table" and options or {}
    local itemInfo, itemSource = self.Compat38002:GetItemInfo(itemID)
    local vendorCopper = tonumber(options.vendorCopper)
        or (itemInfo and tonumber(itemInfo.vendorPrice))
    local vendorKnown = vendorCopper ~= nil
    vendorCopper = math.max(0, vendorCopper or 0)

    if options.bound == true then
        return vendorCopper, {
            known = vendorKnown,
            source = vendorKnown and "vendor" or "unknown",
            sourceLabel = vendorKnown and "商店售价" or "缺价",
            itemInfoSource = itemSource,
            vendorCopper = vendorCopper,
        }
    end

    local marketPrice = self:GetEffectiveMarketPrice(itemID)
    local commission = tonumber(self:GetMarketData().commissionRate) or 0
    commission = math.max(0, math.min(1, commission))
    local marketNet = marketPrice and math.floor((marketPrice.unitCopper * (1 - commission)) + 0.5) or nil
    local value = vendorCopper
    local source = vendorKnown and "vendor" or "unknown"
    local sourceLabel = vendorKnown and "商店售价" or "缺价"
    if marketNet and marketNet > value then
        value = marketNet
        source = marketPrice.source
        sourceLabel = marketPrice.priceMetric or marketPrice.source
    end

    return value, {
        known = vendorKnown or marketPrice ~= nil,
        source = source,
        sourceLabel = sourceLabel,
        marketRecord = marketPrice,
        vendorCopper = vendorCopper,
        marketNetCopper = marketNet,
        commissionRate = commission,
        itemName = itemInfo and itemInfo.name,
        itemInfoSource = itemSource,
    }
end


function addon:GetRewardBagValue(itemID)
    local distribution = self:GetAccountData().rewardBagDistributions[tonumber(itemID)]
    if type(distribution) ~= "table" or (tonumber(distribution.bagCount) or 0) <= 0 then
        return 0, {
            sampleCount = 0,
            lowSample = true,
            unknownItemCount = 0,
        }
    end

    local bags = distribution.bagCount
    local total = tonumber(distribution.directCopper) or 0
    local unknown = 0
    for contentItemID, quantity in pairs(distribution.items or {}) do
        local value, detail = self:GetItemValue(contentItemID)
        if not detail.known then
            unknown = unknown + 1
        end
        total = total + (value * (tonumber(quantity) or 0))
    end
    return total / bags, {
        sampleCount = bags,
        lowSample = bags < 5,
        unknownItemCount = unknown,
    }
end


function addon:RecordRewardBagBatch(itemID, bagCount, directCopper, items, metadata)
    if not self.Compat38002:IsSupportedCharacter() then
        return false, "Todo 仅在 80 级记录奖励袋"
    end
    itemID = tonumber(itemID)
    bagCount = tonumber(bagCount)
    if not itemID or not bagCount or bagCount <= 0 or type(items) ~= "table"
        or (metadata and metadata.ambiguous) then
        return false, "开袋批次来源不明确，整批作废"
    end

    local account = self:GetAccountData()
    local distribution = account.rewardBagDistributions[itemID]
    if type(distribution) ~= "table" then
        distribution = { bagCount = 0, directCopper = 0, items = {} }
        account.rewardBagDistributions[itemID] = distribution
    end
    distribution.bagCount = distribution.bagCount + bagCount
    distribution.directCopper = distribution.directCopper + (tonumber(directCopper) or 0)
    for contentItemID, quantity in pairs(items) do
        contentItemID = tonumber(contentItemID)
        quantity = tonumber(quantity)
        if contentItemID and quantity and quantity > 0 then
            distribution.items[contentItemID] = (distribution.items[contentItemID] or 0) + quantity
        end
    end
    distribution.updatedAt = self.Compat38002:GetNow()
    return true, distribution
end


function addon:RecordObservedQuestReward(questID, directCopper, metadata)
    if not self.Compat38002:IsSupportedCharacter() then
        return false
    end
    questID = tonumber(questID)
    directCopper = tonumber(directCopper)
    if not questID or directCopper == nil or directCopper < 0 then
        return false
    end
    local market = self:GetMarketData()
    market.observedQuestRewards[questID] = {
        questID = questID,
        directCopper = math.floor(directCopper + 0.5),
        source = "QUEST_TURNED_IN",
        observedAt = self.Compat38002:GetNow(),
        metadata = metadata,
    }
    return true
end


local function getObservedDirectCopper(addonObject, task, selectedQuestID)
    local observed = addonObject:GetMarketData().observedQuestRewards
    if selectedQuestID and type(observed[selectedQuestID]) == "table" then
        return observed[selectedQuestID].directCopper, "本服务器实测", selectedQuestID, true
    end

    local total = 0
    local count = 0
    for _, questID in ipairs(task.questIDs or {}) do
        local record = observed[questID]
        if type(record) == "table" and tonumber(record.directCopper) then
            total = total + record.directCopper
            count = count + 1
        end
    end
    if count > 0 then
        return total / count, count == 1 and "本服务器实测" or "池内实测均值", nil, true
    end
    return tonumber(task.fixedGoldCopper) or 0,
        task.fixedGoldCopper and "内置奖励" or "无明确直接金币",
        nil,
        task.fixedGoldCopper ~= nil
end


local function valueItemList(addonObject, items, allowUnknown)
    local total = 0
    local unknown = 0
    local details = {}
    for _, item in ipairs(items or {}) do
        local value, detail = addonObject:GetItemValue(item.itemID, item)
        local quantity = tonumber(item.quantity) or 1
        total = total + (value * quantity)
        if not detail.known then
            unknown = unknown + 1
        end
        details[#details + 1] = {
            itemID = item.itemID,
            quantity = quantity,
            unitValue = value,
            detail = detail,
        }
    end
    return total, unknown, details, allowUnknown or unknown == 0
end


function addon:GetTaskValuation(task, selectedQuestID)
    local correction = self:GetTaskCorrection(task.id) or {}
    local directCopper, directSource, sourceQuestID, directKnown = getObservedDirectCopper(self, task, selectedQuestID)
    local rewardItems = correction.rewardItems or task.rewardItems
    local rewardItemValue, rewardUnknown, rewardDetails = valueItemList(self, rewardItems, true)

    local choiceValue = 0
    local choiceDetail
    local choiceUnknown = 0
    for _, choice in ipairs(correction.choiceRewardItems or task.choiceRewardItems or {}) do
        local value, detail = self:GetItemValue(choice.itemID, choice)
        value = value * (tonumber(choice.quantity) or 1)
        if not detail.known then
            choiceUnknown = choiceUnknown + 1
        end
        if value > choiceValue or choiceDetail == nil then
            choiceValue = value
            choiceDetail = { item = choice, value = value, detail = detail }
        end
    end

    local bagValue = 0
    local bagDetails = {}
    for _, bag in ipairs(task.rewardBags or {}) do
        local unitValue, detail = self:GetRewardBagValue(bag.itemID)
        local quantity = tonumber(bag.quantity) or 1
        bagValue = bagValue + (unitValue * quantity)
        bagDetails[#bagDetails + 1] = {
            itemID = bag.itemID,
            quantity = quantity,
            unitValue = unitValue,
            detail = detail,
        }
    end

    local tokenValue = 0
    local tokenMissing = 0
    local tokenDetails = {}
    local character = self:GetCharacterData()
    for _, token in ipairs(task.tokens or {}) do
        local tokenID = tostring(token.tokenID)
        local unitValue = tonumber(character.tokenValues[tokenID]) or 0
        if unitValue == 0 then
            tokenMissing = tokenMissing + 1
        end
        local quantity = tonumber(token.quantity) or 0
        tokenValue = tokenValue + (unitValue * quantity)
        tokenDetails[#tokenDetails + 1] = {
            tokenID = tokenID,
            quantity = quantity,
            unitValue = unitValue,
        }
    end

    local costItems = correction.requiredItems or task.requiredItems
    local costValue, costUnknown, costDetails = valueItemList(self, costItems, false)
    local fixedCost = tonumber(correction.fixedCostCopper)
    if fixedCost == nil then
        fixedCost = tonumber(task.fixedCostCopper) or 0
    end
    local costsKnown = correction.requiredCostsKnown
    if costsKnown == nil then
        costsKnown = task.requiredCostsKnown ~= false
    end
    costsKnown = costsKnown and costUnknown == 0

    local gross = directCopper + rewardItemValue + choiceValue + bagValue + tokenValue
    local net = costsKnown and (gross - costValue - fixedCost) or nil
    local unknownRewards = rewardUnknown + choiceUnknown
    return {
        directCopper = directCopper,
        directSource = directSource,
        directSourceQuestID = sourceQuestID,
        directKnown = directKnown,
        rewardItemValue = rewardItemValue,
        rewardDetails = rewardDetails,
        choiceValue = choiceValue,
        choiceDetail = choiceDetail,
        bagValue = bagValue,
        bagDetails = bagDetails,
        tokenValue = tokenValue,
        tokenDetails = tokenDetails,
        tokenMissing = tokenMissing,
        grossCopper = gross,
        costCopper = costValue + fixedCost,
        costDetails = costDetails,
        costsKnown = costsKnown,
        netCopper = net,
        lowerBound = not directKnown or unknownRewards > 0 or tokenMissing > 0,
        unknownRewardCount = unknownRewards,
    }
end


function addon:GetRequiredItemIDs()
    local required = {}
    local function add(itemID)
        itemID = tonumber(itemID)
        if itemID then
            required[itemID] = true
        end
    end

    for _, task in ipairs(self.TASK_CATALOG) do
        for _, item in ipairs(task.rewardItems or {}) do add(item.itemID) end
        for _, item in ipairs(task.choiceRewardItems or {}) do add(item.itemID) end
        for _, item in ipairs(task.requiredItems or {}) do add(item.itemID) end
        for _, item in ipairs(task.rewardBags or {}) do add(item.itemID) end
    end
    for bagItemID, distribution in pairs(self:GetAccountData().rewardBagDistributions) do
        add(bagItemID)
        for contentItemID in pairs(distribution.items or {}) do add(contentItemID) end
    end
    for itemID in pairs(self:GetMarketData().manualItemPrices) do add(itemID) end

    local result = {}
    for itemID in pairs(required) do
        result[#result + 1] = itemID
    end
    table.sort(result)
    return result
end


function addon:GetAuctionProviders()
    local providers = {}
    local auctionatorAPI = type(Auctionator) == "table"
        and type(Auctionator.API) == "table"
        and type(Auctionator.API.v1) == "table"
        and Auctionator.API.v1.GetAuctionPriceByItemID
    providers[#providers + 1] = {
        id = "Auctionator",
        name = "Auctionator",
        loaded = self.Compat38002:IsAddonLoaded("Auctionator") or type(Auctionator) == "table",
        apiAvailable = type(auctionatorAPI) == "function",
        version = self.Compat38002:GetAddonVersion("Auctionator"),
        adapterVersion = "auctionator-v1-1",
        verification = "38002 待真机验证",
        priceMetric = "Auctionator 最近扫描最低单位价",
    }
    providers[#providers + 1] = {
        id = "TradeSkillMaster",
        name = "TradeSkillMaster",
        loaded = self.Compat38002:IsAddonLoaded("TradeSkillMaster"),
        apiAvailable = false,
        version = self.Compat38002:GetAddonVersion("TradeSkillMaster"),
        adapterVersion = "reserved",
        verification = "未验证兼容槽",
        priceMetric = "未配置",
    }
    providers[#providers + 1] = {
        id = "Auctioneer",
        name = "Auctioneer",
        loaded = self.Compat38002:IsAddonLoaded("Auc-Advanced")
            or self.Compat38002:IsAddonLoaded("Auctioneer"),
        apiAvailable = false,
        version = self.Compat38002:GetAddonVersion("Auc-Advanced"),
        adapterVersion = "reserved",
        verification = "未验证兼容槽",
        priceMetric = "未配置",
    }
    return providers
end


function addon:ImportAuctionatorPrices()
    local provider
    for _, candidate in ipairs(self:GetAuctionProviders()) do
        if candidate.id == "Auctionator" then
            provider = candidate
            break
        end
    end
    if not provider or not provider.apiAvailable then
        return {
            provider = "Auctionator",
            success = 0,
            missing = 0,
            skipped = 0,
            errors = 1,
            details = { "公开 API 不存在或插件未加载" },
        }
    end

    local requiredItemIDs = self:GetRequiredItemIDs()
    local temporary = {}
    local report = {
        provider = "Auctionator",
        success = 0,
        missing = 0,
        skipped = 0,
        errors = 0,
        details = {},
    }
    local api = Auctionator.API.v1.GetAuctionPriceByItemID
    for _, itemID in ipairs(requiredItemIDs) do
        local ok, price = pcall(api, "Todo", itemID)
        if not ok then
            report.errors = report.errors + 1
            report.details[#report.details + 1] = tostring(itemID) .. "：API 调用失败"
        elseif price == nil then
            report.missing = report.missing + 1
            report.details[#report.details + 1] = tostring(itemID) .. "：提供方无价格"
        elseif type(price) ~= "number" or price <= 0 then
            report.skipped = report.skipped + 1
            report.details[#report.details + 1] = tostring(itemID) .. "：单位价语义无效"
        else
            temporary[itemID] = {
                itemID = itemID,
                unitCopper = math.floor(price + 0.5),
                source = "Auctionator",
                provider = "Auctionator",
                providerVersion = provider.version,
                priceMetric = provider.priceMetric,
                marketKey = self.Compat38002:GetMarketKey(),
                sourceDataAt = nil,
                importedAt = self.Compat38002:GetNow(),
                adapterVersion = provider.adapterVersion,
                verification = provider.verification,
            }
            report.success = report.success + 1
        end
    end

    local market = self:GetMarketData()
    if report.success > 0 then
        local committed = {}
        for itemID, record in pairs(market.externalAuctionPrices.Auctionator or {}) do
            committed[itemID] = record
        end
        for itemID, record in pairs(temporary) do committed[itemID] = record end
        market.externalAuctionPrices.Auctionator = committed
        market.activeExternalProvider = "Auctionator"
        market.lastExternalImport = report
    end
    return report
end


function addon:CaptureLegacyAuctionResults()
    if not self.Compat38002:IsSupportedCharacter() then
        return 0, "level-blocked"
    end
    local required = {}
    for _, itemID in ipairs(self:GetRequiredItemIDs()) do required[itemID] = true end
    if tableCount(required) == 0 then
        return 0, "no-required-items"
    end

    local prices, branch = self.Compat38002:ReadLegacyAuctionListings(required)
    if branch == "unavailable" or branch == "failed" then return 0, branch end

    local saved = 0
    for itemID, unitPrices in pairs(prices) do
        local success = self:RecordNativeAuctionPrice(itemID, unitPrices, {
            apiBranch = branch,
        })
        if success then saved = saved + 1 end
    end
    return saved, saved > 0 and "saved" or "no-matching-results"
end


function addon:GetValuationRows()
    local market = self:GetMarketData()
    local required = self:GetRequiredItemIDs()
    local rows = {}
    local represented = {}
    for _, itemID in ipairs(required) do
        represented[itemID] = true
        local effective = self:GetEffectiveMarketPrice(itemID)
        local itemInfo = self.Compat38002:GetItemInfo(itemID)
        rows[#rows + 1] = {
            itemID = itemID,
            name = itemInfo and itemInfo.name or ("物品 " .. tostring(itemID)),
            unitCopper = effective and effective.unitCopper,
            source = effective and effective.source or "缺价",
            metric = effective and effective.priceMetric,
            sampleCount = effective and effective.sampleCount,
            sourceDataAt = effective and effective.sourceDataAt,
            writtenAt = effective and (effective.capturedAt or effective.importedAt or effective.updatedAt),
            manual = market.manualItemPrices[itemID],
        }
    end
    for itemID, manual in pairs(market.manualItemPrices) do
        itemID = tonumber(itemID)
        if itemID and not represented[itemID] then
            local itemInfo = self.Compat38002:GetItemInfo(itemID)
            rows[#rows + 1] = {
                itemID = itemID,
                name = itemInfo and itemInfo.name or ("物品 " .. tostring(itemID)),
                unitCopper = manual.unitCopper,
                source = "manual",
                metric = manual.priceMetric,
                writtenAt = manual.updatedAt,
                manual = manual,
            }
        end
    end
    table.sort(rows, function(left, right) return left.itemID < right.itemID end)
    return rows
end
