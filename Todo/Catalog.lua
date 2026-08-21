local addonName, addon = ...

if type(addon) ~= "table" then
    addon = _G.TodoAddon or {}
end

_G.TodoAddon = addon
addon.addonName = addonName or "Todo"

addon.ADDON_VERSION = "1.0.0-beta.1"
addon.SCHEMA_VERSION = 1
addon.CATALOG_VERSION = "titan-p5-preview-1"
addon.PLANNING_RATIO = 0.85
addon.MAX_SAMPLES = 20
addon.TARGET_LEVEL = 80

addon.MODES = {
    workday = "工作日",
    holiday = "假期",
}

addon.PROFESSION_NAMES = {
    [129] = "急救",
    [164] = "锻造",
    [165] = "制皮",
    [171] = "炼金",
    [182] = "草药学",
    [185] = "烹饪",
    [186] = "采矿",
    [197] = "裁缝",
    [202] = "工程学",
    [333] = "附魔",
    [356] = "钓鱼",
    [393] = "剥皮",
    [755] = "珠宝加工",
    [773] = "铭文",
}

addon.REGIONS = {
    { id = "other", name = "其他 / 不计算首段路程", hub = true },
    { id = "dalaran", name = "达拉然", hub = true },
    { id = "icecrown", name = "冰冠冰川" },
    { id = "storm_peaks", name = "风暴峭壁" },
    { id = "sholazar", name = "索拉查盆地" },
    { id = "dragonblight", name = "龙骨荒野" },
    { id = "borean_tundra", name = "北风苔原" },
    { id = "howling_fjord", name = "嚎风峡湾" },
    { id = "zuldrak", name = "祖达克" },
    { id = "shattrath", name = "沙塔斯城", hub = true },
    { id = "quel_danas", name = "奎尔丹纳斯岛" },
}

addon.REGIONS_BY_ID = {}
for index, region in ipairs(addon.REGIONS) do
    region.order = index
    addon.REGIONS_BY_ID[region.id] = region
end

-- Route references are intentionally conservative in this preview. A missing edge is not
-- treated as zero. Real character samples can make an edge usable without editing minutes.
addon.ROUTE_REFERENCES = {}

addon.RAID_CATALOG = {
    {
        id = "raid:sw",
        shortName = "SW",
        name = "太阳井高地",
        phase = "P5",
        players = 25,
        defaultMinutes = 120,
        aliases = { "太阳之井高地", "太阳井高地", "Sunwell Plateau" },
    },
    {
        id = "raid:zam",
        shortName = "ZAM",
        name = "祖阿曼",
        phase = "P5",
        players = 25,
        defaultMinutes = 120,
        aliases = { "祖阿曼", "Zul'Aman" },
    },
    {
        id = "raid:toc",
        shortName = "TOC",
        name = "十字军的试炼",
        phase = "P4",
        players = 25,
        defaultMinutes = 120,
        aliases = { "十字军的试炼", "Trial of the Crusader" },
    },
    {
        id = "raid:zg",
        shortName = "ZG",
        name = "祖尔格拉布",
        phase = "P4",
        players = 25,
        defaultMinutes = 120,
        aliases = { "祖尔格拉布", "Zul'Gurub" },
    },
    {
        id = "raid:naxx",
        shortName = "NAXX",
        name = "纳克萨玛斯",
        phase = "P3",
        players = 25,
        defaultMinutes = 120,
        aliases = { "纳克萨玛斯", "Naxxramas" },
    },
    {
        id = "raid:obsidian",
        shortName = "黑曜石圣殿",
        name = "黑曜石圣殿",
        phase = "P3",
        players = 25,
        defaultMinutes = 120,
        aliases = { "黑曜石圣殿", "The Obsidian Sanctum" },
    },
    {
        id = "raid:eye",
        shortName = "永恒之眼",
        name = "永恒之眼",
        phase = "P3",
        players = 25,
        defaultMinutes = 120,
        aliases = { "永恒之眼", "The Eye of Eternity" },
    },
    {
        id = "raid:ssc",
        shortName = "毒蛇神殿",
        name = "毒蛇神殿",
        phase = "P2",
        players = 25,
        defaultMinutes = 120,
        aliases = { "毒蛇神殿", "Serpentshrine Cavern" },
    },
    {
        id = "raid:tk",
        shortName = "风暴要塞",
        name = "风暴要塞",
        phase = "P2",
        players = 25,
        defaultMinutes = 120,
        aliases = { "风暴要塞", "The Eye", "Tempest Keep" },
    },
    {
        id = "raid:mc",
        shortName = "MC",
        name = "熔火之心",
        phase = "P1",
        players = 25,
        defaultMinutes = 120,
        aliases = { "熔火之心", "Molten Core" },
    },
    {
        id = "raid:vault",
        shortName = "宝库",
        name = "宝库",
        phase = "独立",
        players = 21,
        defaultMinutes = 30,
        aliases = { "宝库", "Vault" },
    },
}

addon.RAIDS_BY_ID = {}
for index, raid in ipairs(addon.RAID_CATALOG) do
    raid.order = index
    addon.RAIDS_BY_ID[raid.id] = raid
end

-- This catalog is an identity/reference catalog for the development preview. It deliberately
-- does not invent Titan-specific gold or item rewards. Direct money observed from the client,
-- verified item values and learned durations are layered on top by Store and Valuation.
local activitySeeds = {
    {
        id = "pool:dalaran_cooking_alliance",
        name = "达拉然烹饪日常",
        region = "dalaran",
        faction = "Alliance",
        professionID = 185,
        minProfessionRank = 350,
        builtInMinutes = 15,
        questIDs = { 13100, 13101, 13102, 13103, 13107 },
        activityType = "专业日常",
        pool = true,
    },
    {
        id = "pool:dalaran_cooking_horde",
        name = "达拉然烹饪日常",
        region = "dalaran",
        faction = "Horde",
        professionID = 185,
        minProfessionRank = 350,
        builtInMinutes = 15,
        questIDs = { 13112, 13113, 13114, 13115, 13116 },
        activityType = "专业日常",
        pool = true,
    },
    {
        id = "pool:dalaran_fishing",
        name = "达拉然钓鱼日常",
        region = "dalaran",
        professionID = 356,
        minProfessionRank = 1,
        builtInMinutes = 20,
        questIDs = { 13830, 13832, 13833, 13834, 13836 },
        activityType = "专业日常",
        pool = true,
    },
    {
        id = "pool:dalaran_jewelcrafting",
        name = "达拉然珠宝加工日常",
        region = "dalaran",
        professionID = 755,
        minProfessionRank = 375,
        builtInMinutes = 15,
        questIDs = { 12958, 12959, 12960, 12961, 12962, 12963 },
        activityType = "专业日常",
        pool = true,
    },
    {
        id = "pool:shattrath_cooking",
        name = "沙塔斯烹饪日常",
        region = "shattrath",
        professionID = 185,
        minProfessionRank = 275,
        builtInMinutes = 20,
        questIDs = { 11377, 11379, 11380, 11381 },
        activityType = "专业日常",
        pool = true,
    },
    {
        id = "pool:shattrath_fishing",
        name = "沙塔斯钓鱼日常",
        region = "shattrath",
        professionID = 356,
        minProfessionRank = 1,
        builtInMinutes = 20,
        questIDs = { 11665, 11666, 11667, 11668, 11669 },
        activityType = "专业日常",
        pool = true,
    },
}

local individualSeeds = {
    { "brunnhildar", "布伦希尔达日常", "storm_peaks", { 13422, 13423, 13424, 13425 } },
    { "sons_of_hodir", "霍迪尔之子日常", "storm_peaks", { 12981, 12977, 13006, 12994, 13003, 13046 } },
    { "ebon_blade", "黑锋骑士团日常", "icecrown", { 12995, 13069, 13071, 12813, 12815, 12838 } },
    { "oracles", "神谕者日常", "sholazar", { 12704, 12735, 12736, 12737, 12726, 12761, 12762, 12705 }, "sholazar_faction" },
    { "frenzyheart", "狂心氏族日常", "sholazar", { 12702, 12758, 12734, 12741, 12732, 12703, 12760, 12759 }, "sholazar_faction" },
    { "wyrmrest", "龙眠联军日常", "dragonblight", { 12372 } },
    { "kirin_tor_coldarra", "考达拉肯瑞托日常", "borean_tundra", { 11940, 13414 } },
    { "kaluak_borean", "卡鲁亚克日常", "borean_tundra", { 11945 } },
    { "kaluak_howling", "卡鲁亚克日常", "howling_fjord", { 11472 } },
    { "kaluak_dragonblight", "卡鲁亚克日常", "dragonblight", { 11960 } },
    {
        "quel_danas",
        "奎尔丹纳斯日常",
        "quel_danas",
        { 11523, 11524, 11525, 11532, 11533, 11535, 11536, 11537, 11538, 11539, 11540, 11541, 11542, 11543, 11547, 11548 },
    },
    {
        "argent_tournament",
        "银色比武场日常",
        "icecrown",
        {
            13682, 13788, 13809, 13812, 13789, 13791, 13810, 13813,
            13790, 13793, 13811, 13814, 13861, 13862, 13863, 13864,
            14076, 14092, 14090, 14141, 14112, 14145, 14096, 14142,
            14074, 14143, 14136, 14152, 14080, 14140, 14077, 14144,
            14101, 14102, 14104, 14105, 14107, 14108, 14095,
        },
    },
}

addon.TASK_CATALOG = {}
addon.TASKS_BY_ID = {}
addon.QUEST_TO_TASK = {}

local function addTask(task)
    task.order = #addon.TASK_CATALOG + 1
    task.kind = "task"
    task.activityType = task.activityType or "固定日常"
    task.minLevel = task.minLevel or 80
    task.catalogStatus = task.catalogStatus or "identity-verified"
    task.fixedGoldCopper = task.fixedGoldCopper
    task.requiredCostsKnown = task.requiredCostsKnown ~= false
    task.requiredItems = task.requiredItems or {}
    task.rewardItems = task.rewardItems or {}
    task.choiceRewardItems = task.choiceRewardItems or {}
    task.rewardBags = task.rewardBags or {}
    task.tokens = task.tokens or {}
    addon.TASK_CATALOG[#addon.TASK_CATALOG + 1] = task
    addon.TASKS_BY_ID[task.id] = task
    for _, questID in ipairs(task.questIDs or {}) do
        addon.QUEST_TO_TASK[questID] = task
    end
end

for _, seed in ipairs(activitySeeds) do
    addTask(seed)
end

for _, seed in ipairs(individualSeeds) do
    local prefix, fallbackName, region, questIDs, exclusiveGroup = seed[1], seed[2], seed[3], seed[4], seed[5]
    for _, questID in ipairs(questIDs) do
        addTask({
            id = "quest:" .. tostring(questID),
            name = fallbackName .. " #" .. tostring(questID),
            fallbackName = fallbackName,
            region = region,
            builtInMinutes = 20,
            questIDs = { questID },
            activityType = "固定日常",
            exclusiveGroup = exclusiveGroup,
            exclusiveChoice = exclusiveGroup and prefix or nil,
            catalogGroup = prefix,
        })
    end
end


function addon:IsValidMode(mode)
    return self.MODES[mode] ~= nil
end


function addon:GetModeName(mode)
    return self.MODES[mode] or self.MODES.workday
end


function addon:GetRegionName(regionID)
    local region = self.REGIONS_BY_ID[regionID]
    return region and region.name or tostring(regionID or "未知区域")
end


function addon:NormalizeHours(value)
    local hours = tonumber(value)
    if not hours or hours <= 0 then
        return nil
    end

    return math.floor((hours * 60) + 0.5) / 60
end


function addon:FormatMinutes(minutes)
    minutes = math.max(0, math.floor((tonumber(minutes) or 0) + 0.5))
    local hours = math.floor(minutes / 60)
    local rest = minutes % 60
    if hours == 0 then
        return rest .. "分钟"
    end
    if rest == 0 then
        return hours .. "小时"
    end
    return hours .. "小时" .. rest .. "分钟"
end


function addon:FormatClock(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    return string.format("%d:%02d", hours, minutes)
end


function addon:FormatCopper(copper, compact)
    copper = math.floor((tonumber(copper) or 0) + 0.5)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local bronze = copper % 100

    if compact then
        if gold > 0 then
            return sign .. tostring(gold) .. "金"
        end
        return sign .. tostring(silver) .. "银"
    end

    return string.format("%s%d金 %02d银 %02d铜", sign, gold, silver, bronze)
end
