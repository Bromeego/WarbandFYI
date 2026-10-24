-- The last month played before a long break must still be rolled up when the
-- player returns, before retention removes its rows. Run from the repo root:
--   lua tests/MonthHistoryGapTest.lua

local script = arg and arg[0] or "tests/MonthHistoryGapTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

function date(fmt, ts)
    return os.date(fmt, ts)
end

function time(parts)
    if type(parts) == "table" then
        return os.time(parts)
    end
    return os.time()
end

local function stamp(year, month, day, hour)
    return os.time({ year = year, month = month, day = day, hour = hour or 12, min = 0, sec = 0 })
end

local WBF = {}
local now = stamp(2026, 9, 25, 20)
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
loadAddon("Core/MonthHistory.lua", WBF)
loadAddon("Core/Database.lua", WBF)
loadAddon("Tracking/QuestVisibility.lua", WBF)
loadAddon("Tracking/Gold.lua", WBF)
loadAddon("Tracking/ResourceShift.lua", WBF)
loadAddon("Tracking/ResourceBehaviour.lua", WBF)
loadAddon("Tracking/Resources.lua", WBF)

WBF.Time.Now = function()
    return now
end

local GUID = "Player-1-A"

local function quest(id, at, text)
    return { id = id, at = at, guid = GUID, eventType = "quest", category = "quest", text = text, meta = {} }
end

local function freshDb()
    WarbandFYI_DB = {
        schemaVersion = 7,
        config = { retentionDays = 120, sessionTimeoutSeconds = 3600 },
        nextIds = { session = 10, event = 10 },
        activeSessionId = nil,
        sessions = {},
        characters = {
            [GUID] = { guid = GUID, name = "Miranora", classFile = "MAGE", discovered = true },
        },
        snapshots = {},
        events = {
            quest(1, stamp(2026, 9, 2), "Early September"),
            quest(2, stamp(2026, 9, 10), "Mid September"),
            quest(3, stamp(2026, 9, 25), "Late September"),
        },
        dedupe = {},
        goldLast = {},
        monthHistory = {},
        resources = { balances = {} },
    }
    WBF.Database.ready = true
    WBF.Aggregator.MarkDirty()
end

local function offsetOf(year, month)
    local currentYear, currentMonth = WBF.Time.CurrentMonth(now)
    return (year * 12 + (month - 1)) - (currentYear * 12 + (currentMonth - 1))
end

-- Last login was in late September; that login pruned with its own cutoff.
freshDb()
WBF.Database.Init()
check("September is still the open month on the last login", WarbandFYI_DB.monthHistory["2026-09"] == nil)
check("the last login kept every September row", #WarbandFYI_DB.events == 3)

-- Back about three and a half months later. Retention's cutoff now falls inside
-- September, but nothing has removed September rows yet.
now = stamp(2027, 1, 8, 18)
WBF.Database.Init()
local rollup = WarbandFYI_DB.monthHistory["2026-09"]
check("returning after a long break rolls up the last month played", rollup and rollup.finalized == true)
check("the rollup counts the whole month, not only the retained tail", rollup and rollup.totals and rollup.totals.quests == 3, "quests=" .. tostring(rollup and rollup.totals and rollup.totals.quests))
check("retention still removed the expired rows afterwards", #WarbandFYI_DB.events == 1, "events=" .. tostring(#WarbandFYI_DB.events))

local september = WBF.Aggregator.Build("month", offsetOf(2026, 9))
check("September shows all three quests after the break", september and september.totals and september.totals.quests == 3, "quests=" .. tostring(september and september.totals and september.totals.quests))

-- Weeks later every September row has aged out; the month is still there.
now = stamp(2027, 2, 20, 18)
WBF.Database.Init()
WBF.Aggregator.MarkDirty()
local later = WBF.Aggregator.Build("month", offsetOf(2026, 9))
check("September survives once all its rows have aged out", later and later.fromRollup == true and later.totals.quests == 3, "quests=" .. tostring(later and later.totals and later.totals.quests))
check("the finalized month was written once", WarbandFYI_DB.monthHistory["2026-09"] == rollup)

-- Saves from before prunedThrough existed only know when the last prune ran.
freshDb()
now = stamp(2026, 9, 25, 20)
WBF.Database.Init()
WarbandFYI_DB.prunedThrough = nil
check("an older save carries only the last prune time", type(WarbandFYI_DB.lastPruneAt) == "number")
now = stamp(2027, 1, 8, 18)
WBF.Database.Init()
local legacy = WarbandFYI_DB.monthHistory["2026-09"]
check("an older save still rolls up the month before the break", legacy and legacy.totals and legacy.totals.quests == 3, "quests=" .. tostring(legacy and legacy.totals and legacy.totals.quests))

-- A month whose earliest rows retention already removed must not be frozen as
-- if it were complete.
freshDb()
now = stamp(2026, 9, 25, 20)
WBF.Database.Init()
now = stamp(2027, 1, 8, 18)
WarbandFYI_DB.events[1] = nil
for index = 1, 2 do
    WarbandFYI_DB.events[index] = WarbandFYI_DB.events[index + 1]
end
WarbandFYI_DB.events[3] = nil
WarbandFYI_DB.prunedThrough = stamp(2026, 9, 5)
check("a month already partly pruned is not rolled up", WBF.MonthHistory.FinalizeCompleted() == 0 and WarbandFYI_DB.monthHistory["2026-09"] == nil)

-- Count trimming also removes rows. A closed month that lost rows that way
-- reads its complete rollup instead of the surviving rows.
freshDb()
now = stamp(2026, 10, 3, 12)
WBF.Database.Init()
local saved = WarbandFYI_DB.monthHistory["2026-09"]
check("October finalizes September from complete rows", saved and saved.totals.quests == 3)
table.remove(WarbandFYI_DB.events, 1)
WarbandFYI_DB.prunedThrough = stamp(2026, 9, 2)
WBF.Aggregator.MarkDirty()
local trimmed = WBF.Aggregator.Build("month", offsetOf(2026, 9))
check("a closed month with trimmed rows reads its rollup", trimmed and trimmed.fromRollup == true and trimmed.totals.quests == 3, "quests=" .. tostring(trimmed and trimmed.totals and trimmed.totals.quests))

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All month history gap checks passed")
