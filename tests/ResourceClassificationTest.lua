-- Resource classification. Run from the repo root:
--   lua tests/ResourceClassificationTest.lua

local script = arg and arg[0] or "tests/ResourceClassificationTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

if type(time) ~= "function" then
    time = os.time
end

if type(date) ~= "function" then
    date = os.date
end

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

local WBF = {}
local db
local now = 1750000000
local nextId = 1
local failures = 0
local currencyInfo = {}

local function resetDb()
    now = now + 30
    nextId = 1
    db = {
        config = {},
        events = {},
        characters = {
            A = { guid = "A", name = "Miranora", discovered = true },
        },
        resources = nil,
    }
end

loadAddon("Utils/Time.lua", WBF)
WBF.Time.Now = function() return now end
WBF.Debug = { Log = function() end }
WBF.Database = {
    IsReady = function() return true end,
    Get = function() return db end,
    AllocEventId = function()
        local id = nextId
        nextId = nextId + 1
        return id
    end,
}
WBF.Characters = {
    GetCurrent = function() return db.characters.A end,
    Get = function(guid) return db.characters[guid] end,
    IsDiscovered = function() return true end,
}
WBF.EventType = { Resource = "resource" }
WBF.Category = { Resource = "resource" }
WBF.Events = {
    Add = function(partial)
        local event = {
            id = WBF.Database.AllocEventId(),
            at = partial.at or now,
            guid = partial.guid or "A",
            eventType = partial.eventType,
            delta = partial.delta,
            previous = partial.previous,
            new = partial.new,
            text = partial.text,
            meta = partial.meta or {},
        }
        db.events[#db.events + 1] = event
        return event
    end,
}

loadAddon("Utils/Format.lua", WBF)
loadAddon("Tracking/ResourceMeta.lua", WBF)
loadAddon("Tracking/ResourceClassification.lua", WBF)
loadAddon("Tracking/ResourceBehaviour.lua", WBF)
loadAddon("Tracking/ResourceShift.lua", WBF)
loadAddon("Tracking/Resources.lua", WBF)

C_CurrencyInfo = {
    GetCurrencyInfo = function(currencyID)
        return currencyInfo[currencyID]
    end,
}

local function check(name, condition)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name)
end

local PLAYER = WBF.ResourceClassification.PLAYER
local SYSTEM = WBF.ResourceClassification.SYSTEM
local UNKNOWN = WBF.ResourceClassification.UNKNOWN
local Classify = WBF.ResourceClassification.ClassifyCurrency

local function classOf(id, info)
    return Classify(id, info)
end

check("voidlight in the registry stays a player resource", classOf(3316, {
    name = "Voidlight Marl",
    discovered = true,
    isTypeUnused = true,
    isShowInBackpack = false,
}) == PLAYER)

check("a normal discovered currency is a player resource", classOf(424242, {
    name = "Mistcrests",
    discovered = true,
    isShowInBackpack = false,
    description = "A crest currency.",
}) == PLAYER)

check("tracker in an ordinary name is not discarded", classOf(424243, {
    name = "Bounty Tracker Token",
    discovered = false,
    isTypeUnused = true,
    isShowInBackpack = false,
}) == PLAYER)

check("weekly cap in an ordinary name is not discarded", classOf(424244, {
    name = "Weekly Cap Token",
    discovered = true,
    canEarnPerWeek = true,
    maxWeeklyQuantity = 4,
    description = "Spend this.",
}) == PLAYER)

check("an uninspected new name stays unknown", classOf(424245, { name = "Gilded Star" }) == UNKNOWN)

check("the seasonal affix counter is system", classOf(424246, {
    name = "11.0 Delves - System - Seasonal Affix - Events Active",
}) == SYSTEM)

check("the mislaid curiosity cap is system", classOf(424247, {
    name = "EVERGREEN Delves - Tracker - Mislaid Curiosity - Weekly Cap",
}) == SYSTEM)

check("a similar uninspected bookkeeping name stays unknown", classOf(424248, {
    name = "EVERGREEN Delves - Tracker - Other Curiosity - Weekly Cap",
}) == UNKNOWN)

check("a similar bookkeeping name with tracker flags is system", classOf(424248, {
    name = "EVERGREEN Delves - Tracker - Other Curiosity - Weekly Cap",
    discovered = true,
    isShowInBackpack = false,
    isTypeUnused = false,
    description = "",
    canEarnPerWeek = true,
    maxWeeklyQuantity = 4,
}) == SYSTEM)

local storageFields = {
    discovered = false,
    isShowInBackpack = false,
    isTypeUnused = false,
    description = "",
}
local function storage(name)
    local info = { name = name }
    for key, value in pairs(storageFields) do
        info[key] = value
    end
    return info
end

check("a race quest ID store is system", classOf(424250,
    storage("Dragon Racing - Temp Storage - Race Quest ID")) == SYSTEM)
check("a race time scoreboard is system", classOf(424251,
    storage("Dragon Racing - Scoreboard - Race Complete Time MS")) == SYSTEM)
check("a housing route record is system", classOf(424252,
    storage("Housing - Going Postal - Personal Best Record - Alliance - Rt2")) == SYSTEM)
check("an uninspected storage name stays unknown", classOf(424253, {
    name = "Dragon Racing - Scoreboard - Race Complete Time MS",
}) == UNKNOWN)
check("a storage word leading the name is not a role", classOf(424254, {
    name = "Scoreboard - Tokens",
    discovered = true,
    description = "Spend this.",
}) == PLAYER)

check("bookkeeping name shown in the backpack is kept", classOf(424249, {
    name = "12.0 Delves - System - Seasonal Affix - Events Active",
    discovered = true,
    isShowInBackpack = true,
    description = "Shown to the player.",
}) == UNKNOWN)

check("known system event is hidden from activity", WBF.ResourceBehaviour.HidesActivity({
    eventType = "resource",
    delta = 1,
    meta = {
        name = "11.0 Delves - System - Seasonal Affix - Events Active",
        resourceID = 424246,
    },
}))

check("voidlight activity stays visible", not WBF.ResourceBehaviour.HidesActivity({
    eventType = "resource",
    delta = 2,
    meta = { name = "Voidlight Marl", resourceID = 3316 },
}))

resetDb()
currencyInfo[88001] = {
    name = "EVERGREEN Delves - Tracker - Mislaid Curiosity - Weekly Cap",
    quantity = 4,
    discovered = false,
    isShowInBackpack = false,
    isTypeUnused = false,
    description = "",
    canEarnPerWeek = true,
    maxWeeklyQuantity = 4,
    currencyID = 88001,
}
WBF.Resources.Register({
    key = "currency_88001",
    name = currencyInfo[88001].name,
    short = currencyInfo[88001].name,
    trackingType = "currency",
    id = 88001,
})
WBF.Resources.ObserveBalance("currency_88001", 4, nil, true)
now = now + 10
currencyInfo[88001].quantity = 1
WBF.Resources.ObserveBalance("currency_88001", 1, -3, true)
local systemEvents = 0
for index = 1, #db.events do
    local meta = db.events[index].meta or {}
    if meta.resourceKey == "currency_88001" then
        systemEvents = systemEvents + 1
    end
end
check("system counter changes do not create activity", systemEvents == 0)
local systemDefinition = WBF.Resources.Get("currency_88001")
check("system counter is classified", systemDefinition and systemDefinition.playerClass == SYSTEM)
db.events[#db.events + 1] = {
    id = 900,
    at = now,
    guid = "A",
    eventType = "resource",
    delta = -3,
    text = "old system spend",
    meta = {
        resourceKey = "currency_88001",
        resourceID = 88001,
        name = currencyInfo[88001].name,
        classification = "loss_observed",
        balanceAfter = 1,
    },
}
local kept = #db.events
local pack = WBF.Resources.ForPeriod(db.events, now - 100, now + 10)
local systemTile = false
for index = 1, #pack.tiles do
    if pack.tiles[index].key == "currency_88001" then
        systemTile = true
    end
end
check("system history remains stored", #db.events == kept)
check("system history is omitted from the period summary", not systemTile)
check("system history is omitted from activity", WBF.ResourceBehaviour.HidesActivity(db.events[#db.events]))
local catalog = WBF.Resources.Catalog()
local listed = false
for index = 1, #catalog.resources do
    if catalog.resources[index].key == "currency_88001" then
        listed = true
    end
end
check("system counter is omitted from the resource list", not listed)

resetDb()
currencyInfo[3316] = {
    name = "Voidlight Marl",
    quantity = 10,
    discovered = true,
    isShowInBackpack = false,
    isTypeUnused = true,
    description = "A real currency.",
    currencyID = 3316,
}
WBF.Resources.Register({
    key = "currency_3316",
    name = "Voidlight Marl",
    short = "Voidlight Marl",
    trackingType = "currency",
    id = 3316,
})
WBF.Resources.ObserveBalance("currency_3316", 10, nil, true)
now = now + 10
currencyInfo[3316].quantity = 12
WBF.Resources.ObserveBalance("currency_3316", 12, 2, true)
local playerPack = WBF.Resources.ForPeriod(db.events, now - 100, now + 10)
local playerTile
for index = 1, #playerPack.tiles do
    if playerPack.tiles[index].key == "currency_3316" then
        playerTile = playerPack.tiles[index]
    end
end
check("voidlight still records a gain", playerTile and playerTile.earned == 2)
check("voidlight is not classified as system", WBF.Resources.Get("currency_3316").playerClass == PLAYER)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All resource classification tests passed")
