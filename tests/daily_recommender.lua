local addon = {}
assert(loadfile("Todo/Catalog.lua"))("Todo", addon)

local now = 1900000000
addon.Compat38002 = {
    GetNow = function() return now, "mock" end,
    GetCharacterKey = function() return "realm:Horde:tracker" end,
    GetMarketKey = function() return "realm:Horde" end,
    GetDailyResetKey = function() return "daily-a", "mock", "available" end,
    GetWeeklyResetKey = function() return "weekly-a", "mock", "available" end,
    GetPlayerLevel = function() return 80 end,
    IsSupportedCharacter = function() return true end,
    GetFaction = function() return "Horde" end,
    GetProfessions = function() return {}, {}, "mock" end,
    IsQuestCompleted = function() return false, "mock" end,
    IsQuestOnLog = function() return false, "mock" end,
    GetQuestTitle = function(_, questID, fallback) return fallback or tostring(questID), "mock" end,
    GetItemInfo = function(_, itemID)
        return { itemID = itemID, name = "测试物品", vendorPrice = 1000 }, "mock"
    end,
    IsAddonLoaded = function(_, addonID) return addonID == "Auctionator" end,
    GetAddonVersion = function() return "test-version" end,
}

assert(loadfile("Todo/Store.lua"))("Todo", addon)
assert(loadfile("Todo/Valuation.lua"))("Todo", addon)
assert(loadfile("Todo/Planner.lua"))("Todo", addon)
assert(loadfile("Todo/Tracking.lua"))("Todo", addon)

TodoDB = nil
local market = addon:GetMarketData()
market.commissionRate = 0.05

assert(addon:SetManualItemPrice(100, 2000))
local value, detail = addon:GetItemValue(100)
assert(value == 1900 and detail.source == "manual", "手动税后价没有与商店价比较")

market.externalAuctionPrices.Auctionator = {
    [100] = { itemID = 100, unitCopper = 3000, source = "Auctionator", priceMetric = "external" },
}
market.activeExternalProvider = "Auctionator"
value, detail = addon:GetItemValue(100)
assert(value == 2850 and detail.source == "Auctionator", "外部提供方没有优先于手动价")

market.nativeAuctionPrices[100] = {
    itemID = 100,
    unitCopper = 4000,
    source = "TodoNative",
    priceMetric = "native",
}
value, detail = addon:GetItemValue(100)
assert(value == 3800 and detail.source == "TodoNative", "Todo 原生缓存没有最高优先级")

local oldRecord = market.nativeAuctionPrices[100]
local success = addon:RecordNativeAuctionPrice(100, {})
assert(success == false and market.nativeAuctionPrices[100] == oldRecord, "空拍卖结果清空了旧缓存")

local prices = {}
for index = 1, 30 do prices[index] = index * 100 end
success = addon:RecordNativeAuctionPrice(100, prices, { apiBranch = "test" })
assert(success, "有效拍卖结果没有写入")
assert(market.nativeAuctionPrices[100].unitCopper == 1050, "没有取最低 20 条的中位数")
assert(market.nativeAuctionPrices[100].sampleCount == 20, "拍卖样本数错误")

local auctionatorCalls = 0
Auctionator = {
    API = {
        v1 = {
            GetAuctionPriceByItemID = function(callerID, itemID)
                auctionatorCalls = auctionatorCalls + 1
                assert(callerID == "Todo" and (itemID == 100 or itemID == 101), "Auctionator API 参数错误")
                return itemID == 100 and 5555 or nil
            end,
        },
    },
}
local originalRequired = addon.GetRequiredItemIDs
market.externalAuctionPrices.Auctionator[101] = {
    itemID = 101,
    unitCopper = 4444,
    source = "Auctionator",
}
function addon:GetRequiredItemIDs() return { 100, 101 } end
assert(auctionatorCalls == 0, "检测提供方时读取了价格库")
local report = addon:ImportAuctionatorPrices()
assert(report.success == 1 and report.missing == 1 and auctionatorCalls == 2, "显式导入没有精确读取所需 itemID")
assert(market.externalAuctionPrices.Auctionator[100].unitCopper == 5555, "外部导入未保存独立快照")
assert(market.externalAuctionPrices.Auctionator[101].unitCopper == 4444, "外部缺失项错误地清除了旧记录")
assert(market.externalAuctionPrices.Auctionator[100].sourceDataAt == nil, "用导入时间伪造了来源数据时间")
addon.GetRequiredItemIDs = originalRequired

assert(addon:GetRewardBagValue(900) == 0, "无样本奖励袋默认值不是 0")
assert(addon:RecordRewardBagBatch(900, 1, 10000, { [100] = 2 }))
local bagValue, bagDetail = addon:GetRewardBagValue(900)
assert(bagValue > 0 and bagDetail.sampleCount == 1 and bagDetail.lowSample, "首个奖励袋样本没有立即参与估值")

local function makeSession(ids)
    local rows = {}
    for _, id in ipairs(ids) do
        rows[#rows + 1] = {
            id = id,
            candidateID = id,
            kind = "task",
            title = id,
            durationMinutes = 20,
            generatedNetCopper = 10000,
            currentNetCopper = 10000,
        }
    end
    return {
        startedAt = now,
        baseElapsedSeconds = 0,
        declaredMinutes = 120,
        mode = "workday",
        startRegion = "other",
        manualTaskIDs = {},
        skippedIDs = {},
        inProgressIDs = {},
        confirmedRaidIDs = {},
        sourceByID = {},
        tracking = { activeTasks = {} },
        plan = { rows = rows, candidates = {}, summary = {} },
    }
end

local session = makeSession({ "t1", "t2", "t3" })
addon:SetActiveSession(session)
assert(addon:StartTaskTracking("t1"))
assert(addon:StartTaskTracking("t2"))
assert(addon:StartTaskTracking("t3"))
now = now + 900
addon:FlushTaskTime()
assert(math.floor(session.tracking.activeTasks.t1.allocatedSeconds + 0.5) == 300, "三个并行任务没有平均分配 15 分钟")
assert(addon:StopTaskTracking("t1", true))
now = now + 600
assert(addon:StopTaskTracking("t2", true))
assert(addon:StopTaskTracking("t3", true))
local character = addon:GetCharacterData()
assert(math.floor(addon:GetSampleMedian(character.taskDurations.t1) + 0.5) == 5, "第一个并行任务样本错误")
assert(math.floor(addon:GetSampleMedian(character.taskDurations.t2) + 0.5) == 10, "并行集合变化后没有重新分母")
assert(math.floor(addon:GetSampleMedian(character.taskDurations.t3) + 0.5) == 10, "最后一个并行任务样本错误")

session = makeSession({ "move-task" })
addon:SetActiveSession(session)
assert(addon:StartTaskTracking("move-task"))
now = now + 300
assert(addon:StartRouteTracking("dalaran", "icecrown"))
now = now + 600
assert(addon:EndRouteTracking())
now = now + 300
assert(addon:StopTaskTracking("move-task", true))
assert(math.floor(addon:GetSampleMedian(character.taskDurations["move-task"]) + 0.5) == 10, "移动时间重复分配给任务")
assert(math.floor(addon:GetSampleMedian(character.routeDurations.dalaran.icecrown) + 0.5) == 10, "路线学习样本错误")

addon:AddDurationSample("task", "anomaly", 10)
addon:AddDurationSample("task", "anomaly", 10)
addon:AddDurationSample("task", "anomaly", 10)
local _, status = addon:AddDurationSample("task", "anomaly", 100)
assert(status == "pending", "超过中位数 400% 的异常样本没有进入待确认")
assert(addon:GetSampleMedian(character.taskDurations.anomaly) == 10, "待确认样本污染了中位数")

print("估值与学习计时测试通过")
