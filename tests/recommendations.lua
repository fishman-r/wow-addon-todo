local addon = {}
assert(loadfile("Todo/Catalog.lua"))("Todo", addon)

local now = 1800000000
local level = 80
local onQuest = {}
local completed = {}
addon.Compat38002 = {
    GetNow = function() return now, "mock" end,
    GetCharacterKey = function() return "realm:Alliance:character" end,
    GetMarketKey = function() return "realm:Alliance" end,
    GetDailyResetKey = function() return "daily-1", "mock", "available" end,
    GetWeeklyResetKey = function() return "weekly-1", "mock", "available" end,
    GetPlayerLevel = function() return level end,
    IsSupportedCharacter = function() return level == 80 end,
    GetFaction = function() return "Alliance" end,
    GetProfessions = function()
        local values = {
            { id = 185, name = "烹饪", rank = 450 },
            { id = 356, name = "钓鱼", rank = 450 },
            { id = 755, name = "珠宝加工", rank = 450 },
        }
        return values, {
            [185] = values[1],
            [356] = values[2],
            [755] = values[3],
        }, "mock"
    end,
    IsQuestCompleted = function(_, questID) return completed[questID] == true, "mock" end,
    IsQuestOnLog = function(_, questID) return onQuest[questID] == true, "mock" end,
    GetQuestTitle = function(_, questID, fallback) return fallback or ("任务 " .. questID), "mock" end,
    GetItemInfo = function(_, itemID) return { itemID = itemID, name = "物品 " .. itemID, vendorPrice = 0 }, "mock" end,
}

assert(loadfile("Todo/Store.lua"))("Todo", addon)
assert(loadfile("Todo/Valuation.lua"))("Todo", addon)
assert(loadfile("Todo/Planner.lua"))("Todo", addon)

TodoDB = nil
addon:EnsureDatabase()

local function task(id, region, minutes, value, order)
    return {
        id = id,
        kind = "task",
        title = id,
        region = region,
        regionName = region,
        durationMinutes = minutes,
        durationSource = "test",
        netCopper = value,
        valuation = { netCopper = value },
        autoEligible = true,
        status = "executable",
        order = order,
    }
end

local originalRoute = addon.GetRouteDuration
function addon:GetRouteDuration(fromRegion, toRegion)
    if fromRegion == toRegion or fromRegion == "other" then return 0, "test", "test" end
    return nil, "missing", "missing"
end

local exact = {
    task("a", "zone", 60, 1000000, 1),
    task("b", "zone", 30, 600000, 2),
    task("c", "zone", 30, 600000, 3),
}
local route = assert(addon:OptimizeTaskRoute(exact, 60, "other", {}))
assert(route.valueCopper == 1200000, "优化器没有选择总价值更高的组合")
assert(route.selectedIDs.b and route.selectedIDs.c and not route.selectedIDs.a, "优化器退化成按单项顺序选择")

local unlimited = {}
for index = 1, 8 do
    unlimited[#unlimited + 1] = task("u" .. index, "zone", 5, 10000 + index, index)
end
route = assert(addon:OptimizeTaskRoute(unlimited, 40, "other", {}))
assert(#route.selected == 8, "推荐仍存在固定数量上限")

function addon:GetRouteDuration(fromRegion, toRegion)
    if fromRegion == toRegion or fromRegion == "other" then return 0, "test", "test" end
    if fromRegion == "one" and toRegion == "two" then return 15, "test", "test" end
    if fromRegion == "two" and toRegion == "one" then return 20, "test", "test" end
    return nil, "missing", "missing"
end
route = assert(addon:OptimizeTaskRoute({
    task("one", "one", 20, 500000, 1),
    task("two", "two", 20, 500000, 2),
}, 55, "other", {}))
assert(route.routeMinutes == 15 and #route.selected == 2, "有向跨区移动没有参与预算")

local searchable = {
    { id = "q1", searchText = "达拉然 烹饪 专业日常 13100" },
    { id = "q2", searchText = "冰冠冰川 固定日常 12995" },
}
local filtered = addon:FilterCandidates(searchable, "达拉然   专业")
assert(#filtered == 1 and filtered[1].id == "q1", "多关键词 AND 检索错误")

addon.GetRouteDuration = originalRoute

local workday = addon:CreateSession({
    mode = "workday",
    hours = 4,
    startRegion = "other",
    considerRaids = true,
})
assert(workday, "工作日会话未生成")
for _, row in ipairs(workday.plan.rows) do
    assert(row.kind ~= "raid", "工作日自动推荐了团本")
end

local holiday = addon:CreateSession({
    mode = "holiday",
    hours = 4,
    startRegion = "other",
    considerRaids = true,
})
assert(holiday.plan.rows[1] and holiday.plan.rows[1].candidateID == "raid:sw", "假期团本没有按 P5 到 P1 顺序选择")
assert(holiday.plan.rows[1].durationMinutes == 120, "25 人团本默认耗时不是 120 分钟")

local shortHoliday = addon:CreateSession({
    mode = "holiday",
    hours = 2,
    startRegion = "other",
    considerRaids = true,
})
assert(shortHoliday.plan.rows[1] and shortHoliday.plan.rows[1].candidateID == "raid:vault", "少于 3 小时没有只考虑宝库")
assert(shortHoliday.plan.rows[1].durationMinutes == 30, "宝库默认耗时不是 30 分钟")

local timed = addon:CreateSession({
    mode = "workday",
    hours = 2,
    startRegion = "other",
    considerRaids = false,
})
now = now + 1800
addon:ReplanSession()
assert(math.abs(timed.plan.summary.budgetMinutes - 76.5) < 0.001, "重新规划没有使用真实剩余时间的 85%")
addon:ExtendSession(30)
assert(math.abs(timed.declaredMinutes - 60) < 0.001, "再玩 30 分钟没有设置 T=E+30")
now = now + 3600
assert(addon:GetSessionElapsedSeconds(timed) > timed.declaredMinutes * 60, "实际累计计时不允许超过 T")
assert(timed.plan ~= nil, "超过 T 后计划被清空")

now = now + 10
onQuest[13830] = true
addon:RecordObservedQuestReward(13830, 200000)
local running = addon:CreateSession({
    mode = "workday",
    hours = 1,
    startRegion = "dalaran",
    considerRaids = false,
})
local runningID = "pool:dalaran_fishing"
local foundRunning = false
for _, row in ipairs(running.plan.rows) do
    if row.candidateID == runningID then foundRunning = true end
end
assert(foundRunning, "实测且已接的专业日常没有进入计划")
running.inProgressIDs[runningID] = true
running.tracking.activeTasks[runningID] = {
    active = true,
    allocatedSeconds = 600,
    originalEstimatedMinutes = 20,
}
addon:ReplanSession()
local remainingRow
for _, row in ipairs(running.plan.rows) do
    if row.candidateID == runningID then remainingRow = row end
end
assert(remainingRow and math.abs(remainingRow.durationMinutes - 10) < 0.001,
    "进行中项目没有使用原预计减有效计时作为剩余耗时")
running.tracking.activeTasks[runningID].allocatedSeconds = 1300
addon:ReplanSession()
assert(running.plan.summary.inProgressOverdue == true, "进行中项目超出预计后没有停止自动填充")

level = 79
local blocked, reason = addon:CreateSession({ mode = "workday", hours = 1, startRegion = "other" })
assert(blocked == nil and reason:find("80"), "非 80 级没有被硬拦截")

print("规划与会话测试通过")
