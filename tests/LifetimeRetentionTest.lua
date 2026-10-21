-- Lifetime totals must survive retention, and an open session's play time
-- is computed at display time. Run from the repo root:
--   lua tests/LifetimeRetentionTest.lua

local script = arg and arg[0] or "tests/LifetimeRetentionTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

local WBF = {}
local now = 1750000000
local failures = 0

local function check(name, condition, detail)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  " .. detail) or ""))
end

loadAddon("Utils/Format.lua", WBF)
loadAddon("Utils/Time.lua", WBF)
loadAddon("Utils/Debug.lua", WBF)
loadAddon("Core/Events.lua", WBF)
loadAddon("Core/Characters.lua", WBF)
loadAddon("Core/Sessions.lua", WBF)
loadAddon("Core/Aggregator.lua", WBF)
loadAddon("Core/Database.lua", WBF)
loadAddon("Tracking/QuestVisibility.lua", WBF)
loadAddon("Tracking/Gold.lua", WBF)
loadAddon("Tracking/ResourceShift.lua", WBF)
loadAddon("Tracking/ResourceBehaviour.lua", WBF)
loadAddon("Tracking/Resources.lua", WBF)
loadAddon("Tracking/Prey.lua", WBF)

WBF.Time.Now = function()
    return now
end
WBF.Time.StartOfDay = function(at)
    return (at or now) - ((at or now) % 86400)
end
WBF.Time.StartOfWeek = function(at)
    return (at or now) - (7 * 86400)
end
WBF.Time.StartOfMonth = function(at)
    return (at or now) - (31 * 86400)
end

local function freshDb()
    WarbandFYI_DB = {
        schemaVersion = 2,
        config = { retentionDays = 120, sessionTimeoutSeconds = 3600 },
        nextIds = { session = 10, event = 10 },
        activeSessionId = nil,
        sessions = {},
        characters = {
            A = { guid = "A", name = "Miranora", discovered = true, classFile = "MAGE" },
        },
        snapshots = {},
        events = {},
        dedupe = {},
        goldLast = {},
    }
    WBF.Database.ready = true
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
end

freshDb()
local old = now - (200 * 86400)
WarbandFYI_DB.events = {
    {
        id = 1,
        at = old,
        guid = "A",
        eventType = "mythicPlus",
        text = "Old key",
        meta = { level = 12 },
    },
    {
        id = 2,
        at = old,
        guid = "A",
        eventType = "resource",
        delta = 40,
        text = "Old gain",
        meta = { resourceKey = "tender", classification = "gain", balanceAfter = 900 },
    },
}
WarbandFYI_DB.sessions = {
    {
        id = 1,
        startedAt = old,
        endedAt = old + 1000,
        segments = {
            { guid = "A", startedAt = old, endedAt = old + 1000 },
        },
        goldByCharacter = {},
        goldLedger = {
            { at = old + 10, guid = "A", delta = 50000 },
        },
    },
}
WarbandFYI_DB.snapshots = {
    { at = old, guid = "A", level = 70, itemLevel = 400 },
}
WBF.Resources.Register({
    key = "tender",
    name = "Tender",
    short = "Tender",
    trackingType = "currency",
    id = 1,
})

local removed = WBF.Database.Prune(true)
check("retention removes the expired rows", removed == 4, "removed=" .. tostring(removed))
check("expired mythic run is gone", #WarbandFYI_DB.events == 0)
check("lifetime keeps the mythic run", WarbandFYI_DB.lifetime.totals.mythicPlus == 1 and WarbandFYI_DB.lifetime.totals.highestKey == 12)
check("lifetime keeps played time", WarbandFYI_DB.lifetime.characters.A.playedSeconds == 1000)
check("lifetime keeps gold", WarbandFYI_DB.lifetime.gold.net == 50000)
check("lifetime keeps the resource gain", WarbandFYI_DB.resources.balances.tender.lifetime.gained == 40)
check("lifetime keeps the resource peak", WarbandFYI_DB.resources.balances.tender.lifetime.highest == 900)

local removedAgain = WBF.Database.Prune(true)
check("a second prune does not count the same history twice", removedAgain == 0 and WarbandFYI_DB.lifetime.totals.mythicPlus == 1 and WarbandFYI_DB.lifetime.gold.net == 50000 and WarbandFYI_DB.resources.balances.tender.lifetime.gained == 40)

WarbandFYI_DB.events[#WarbandFYI_DB.events + 1] = {
    id = 3,
    at = now - 3600,
    guid = "A",
    eventType = "mythicPlus",
    text = "Recent key",
    meta = { level = 5 },
}
WarbandFYI_DB.events[#WarbandFYI_DB.events + 1] = {
    id = 4,
    at = now - 3000,
    guid = "A",
    eventType = "resource",
    delta = 7,
    text = "Recent gain",
    meta = { resourceKey = "tender", classification = "gain", balanceAfter = 50 },
}
WBF.Aggregator.MarkDirty()
local warband = WBF.Aggregator.Build("warband")
local week = WBF.Aggregator.Build("week")
check("warband totals keep the pruned run", warband.totals.mythicPlus == 2 and warband.totals.highestKey == 12, "runs=" .. tostring(warband.totals.mythicPlus) .. " key=" .. tostring(warband.totals.highestKey))
check("this week does not include the pruned run", week.totals.mythicPlus == 1 and week.totals.highestKey == 5)
check("warband play time keeps the pruned session", warband.playedSeconds == 1000, "played=" .. tostring(warband.playedSeconds))
check("warband gold keeps the pruned session", warband.goldNet == 50000, "gold=" .. tostring(warband.goldNet))
check("this week gold ignores the pruned session", week.goldNet == 0)

local board = WBF.Resources.Board("tender", 0, now + 10, "Warband")
check("all time resource gain keeps pruned and current movement", board.lifetime and board.lifetime.gained == 47 and board.lifetime.highest == 900, "gained=" .. tostring(board.lifetime and board.lifetime.gained) .. " high=" .. tostring(board.lifetime and board.lifetime.highest))
local weekBoard = WBF.Resources.Board("tender", now - 7 * 86400, now + 10, "This Week")
check("week resource card still shows only this week", weekBoard.period.earned == 7, "earned=" .. tostring(weekBoard.period.earned))

freshDb()
WBF.Resources.Register({
    key = "tender",
    name = "Tender",
    short = "Tender",
    trackingType = "currency",
    id = 1,
})
WarbandFYI_DB.activeSessionId = 2
WarbandFYI_DB.sessions = {
    {
        id = 2,
        startedAt = now - 500,
        endedAt = nil,
        lastActivityAt = now,
        segments = {
            { guid = "A", startedAt = now - 400, endedAt = now - 250 },
            { guid = "A", startedAt = now - 80, endedAt = nil },
        },
        goldByCharacter = {},
        goldLedger = {},
    },
}
local current = WBF.Aggregator.Build("current")
local cached = current.playedSeconds
local live = WBF.Aggregator.LivePlay(current)
check("closed time stays in the cache", cached == 150, "cached=" .. tostring(cached))
check("open time is outside the cache", live == 80, "live=" .. tostring(live))
local again = WBF.Aggregator.Build("current")
check("reading play time does not rebuild the summary", again == current and current.playedSeconds == 150)
now = now + 25
check("open time advances without a new summary", WBF.Aggregator.LivePlay(current) == 105 and current.playedSeconds == 150, "live=" .. tostring(WBF.Aggregator.LivePlay(current)))

freshDb()
WarbandFYI_DB.events = {
    {
        id = 1,
        at = now - 50,
        eventType = "prey",
        text = "Prey: Plainswalker",
        meta = { questID = 99, title = "Prey: Plainswalker" },
    },
}
local timers = {}
C_Timer = {
    After = function(delay, fn)
        timers[#timers + 1] = fn
    end,
}
local questCount = nil
local onQuest = nil
C_QuestLog = {
    GetActivePreyQuest = function()
        return nil
    end,
    GetNumQuestLogEntries = function()
        return questCount
    end,
    IsOnQuest = function()
        return onQuest
    end,
}
local handlers = {}
WBF.Prey.Register({
    On = function(_, eventName, fn)
        handlers[eventName] = fn
    end,
})
WBF.Prey.AllowStaleClose()
check("an unread quest log does not abandon the hunt", WarbandFYI_DB.events[1].meta.abandoned ~= true)
local guard = 0
while timers[1] and guard < 6 do
    guard = guard + 1
    local fn = table.remove(timers, 1)
    fn()
end
check("retries still leave an unknown hunt open", WarbandFYI_DB.events[1].meta.abandoned ~= true, "abandoned=" .. tostring(WarbandFYI_DB.events[1].meta.abandoned))
questCount = 0
handlers.QUEST_LOG_UPDATE()
check("an empty quest log is not proof the hunt ended", WarbandFYI_DB.events[1].meta.abandoned ~= true)
onQuest = nil
questCount = 6
handlers.QUEST_LOG_UPDATE()
check("an unknown IsOnQuest result stays unresolved", WarbandFYI_DB.events[1].meta.abandoned ~= true)
onQuest = false
handlers.QUEST_LOG_UPDATE()
check("a definite quest-log miss marks the hunt abandoned", WarbandFYI_DB.events[1].meta.abandoned == true)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All lifetime retention checks passed")
