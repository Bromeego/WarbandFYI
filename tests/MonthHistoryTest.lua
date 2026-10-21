-- Historical month browsing. Run from the repo root:
--   lua tests/MonthHistoryTest.lua

local script = arg and arg[0] or "tests/MonthHistoryTest.lua"
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

local function stamp(year, month, day, hour, min, sec)
    return os.time({
        year = year,
        month = month,
        day = day,
        hour = hour or 12,
        min = min or 0,
        sec = sec or 0,
    })
end

local function parts(at)
    return os.date("*t", at)
end

local WBF = {}
local now = stamp(2026, 9, 30, 15)
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

local function freshDb()
    WarbandFYI_DB = {
        schemaVersion = 5,
        config = { retentionDays = 120, sessionTimeoutSeconds = 3600 },
        nextIds = { session = 10, event = 10 },
        activeSessionId = nil,
        sessions = {},
        characters = {},
        snapshots = {},
        events = {},
        dedupe = {},
        goldLast = {},
        monthHistory = {},
        resources = { balances = {} },
    }
    WBF.Database.ready = true
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
end

local function offsetOf(year, month)
    local currentYear, currentMonth = WBF.Time.CurrentMonth(now)
    return (year * 12 + (month - 1)) - (currentYear * 12 + (currentMonth - 1))
end

local function resource(summary, key)
    local tiles = summary and summary.resources or {}
    for index = 1, #tiles do
        if tiles[index].key == key then
            return tiles[index]
        end
    end
    return nil
end

local function highlightCount(summary, text)
    local count = 0
    local highlights = summary and summary.highlights or {}
    for index = 1, #highlights do
        if highlights[index].value == text then
            count = count + 1
        end
    end
    return count
end

local function hasText(list, text)
    for index = 1, #(list or {}) do
        if list[index].text == text or list[index].value == text then
            return true
        end
    end
    return false
end

local function containsNumber(value, target, seen)
    seen = seen or {}
    if type(value) ~= "table" then
        return value == target
    end
    if seen[value] then
        return false
    end
    seen[value] = true
    for _, item in pairs(value) do
        if containsNumber(item, target, seen) then
            return true
        end
    end
    return false
end

local function approxBytes(value, seen)
    seen = seen or {}
    local kind = type(value)
    if kind ~= "table" then
        return #tostring(value) + 8
    end
    if seen[value] then
        return 0
    end
    seen[value] = true
    local total = 0
    for key, item in pairs(value) do
        total = total + approxBytes(key, seen) + approxBytes(item, seen)
    end
    return total
end

local startAt, _, isCurrent, closedEnd = WBF.Time.MonthBounds(2026, 9, now)
local startParts = parts(startAt)
local endParts = parts(closedEnd)
check("September starts on the 1st", startParts.year == 2026 and startParts.month == 9 and startParts.day == 1)
check("September has 30 days", endParts.year == 2026 and endParts.month == 9 and endParts.day == 30)
check("September is the open month on Sep 30", isCurrent == true)

local aprilStart, _, _, aprilEnd = WBF.Time.MonthBounds(2026, 4, stamp(2026, 5, 2, 9))
local aprilClosed = parts(aprilEnd)
check("April has 30 days", parts(aprilStart).day == 1 and aprilClosed.month == 4 and aprilClosed.day == 30)

local marchStart, _, _, marchEnd = WBF.Time.MonthBounds(2026, 3, stamp(2026, 4, 2, 9))
local marchClosed = parts(marchEnd)
check("March has 31 days", parts(marchStart).day == 1 and marchClosed.month == 3 and marchClosed.day == 31)

local leapStart, _, _, leapEnd = WBF.Time.MonthBounds(2024, 2, stamp(2024, 3, 10, 12))
local leapClosed = parts(leapEnd)
check("leap-year February has 29 days", parts(leapStart).month == 2 and leapClosed.year == 2024 and leapClosed.month == 2 and leapClosed.day == 29)

local plainStart, _, _, plainEnd = WBF.Time.MonthBounds(2025, 2, stamp(2025, 3, 10, 12))
check("ordinary February has 28 days", parts(plainStart).day == 1 and parts(plainEnd).day == 28 and parts(plainEnd).month == 2)

local backYear, backMonth = WBF.Time.AddMonths(2027, 1, -1)
check("January steps back to December", backYear == 2026 and backMonth == 12)
local decStart, _, decCurrent, decEnd = WBF.Time.MonthBounds(2026, 12, stamp(2027, 1, 15, 12))
check("December 2026 is a previous month in January 2027", parts(decStart).year == 2026 and parts(decStart).month == 12 and parts(decStart).day == 1 and parts(decEnd).day == 31 and decCurrent == false)
check("future months cannot be selected", WBF.MonthHistory.CanSelect(2026, 10, now) == false)
check("the open month can be selected", WBF.MonthHistory.CanSelect(2026, 9, now) == true)

freshDb()
WBF.Resources.Register({
    key = "tender",
    name = "Garrison Resources",
    short = "Garrison",
    trackingType = "currency",
    classification = "ACCOUNT_WIDE_CURRENCY",
    id = 900001,
})
WBF.Resources.Register({
    key = "residual",
    name = "Residual",
    short = "Residual",
    trackingType = "currency",
    classification = "ACCOUNT_WIDE_CURRENCY",
    id = 900002,
})

local sepSessionStart = stamp(2026, 9, 10, 10)
local octSessionStart = stamp(2026, 10, 3, 10)
WarbandFYI_DB.characters[GUID] = {
    guid = GUID,
    name = "Miranora",
    realm = "Area 52",
    classFile = "MAGE",
    className = "Mage",
    specName = "Frost",
    discovered = true,
    level = 80,
    itemLevel = 340,
    updatedAt = stamp(2026, 10, 2, 12),
}
WarbandFYI_DB.snapshots = {
    { at = stamp(2026, 9, 1, 0, 10), guid = GUID, level = 80, itemLevel = 281 },
    { at = stamp(2026, 9, 20, 12), guid = GUID, level = 80, itemLevel = 310 },
    { at = stamp(2026, 10, 2, 12), guid = GUID, level = 80, itemLevel = 340 },
}
WarbandFYI_DB.sessions = {
    {
        id = 1,
        startedAt = sepSessionStart,
        endedAt = sepSessionStart + 7200,
        segments = {
            { guid = GUID, startedAt = sepSessionStart, endedAt = sepSessionStart + 7200 },
        },
        goldByCharacter = {},
        goldLedger = {},
    },
    {
        id = 2,
        startedAt = octSessionStart,
        endedAt = octSessionStart + 100,
        segments = {
            { guid = GUID, startedAt = octSessionStart, endedAt = octSessionStart + 100 },
        },
        goldByCharacter = {},
        goldLedger = {},
    },
}
WarbandFYI_DB.events = {
    {
        id = 1,
        at = stamp(2026, 9, 12, 19),
        guid = GUID,
        eventType = "instanceEnter",
        text = "Nerub-ar Palace",
        meta = { instanceType = "raid" },
    },
    {
        id = 2,
        at = stamp(2026, 9, 14, 15),
        guid = GUID,
        eventType = "resource",
        delta = 1361,
        text = "+1,361 Garrison Resources",
        meta = { resourceKey = "tender", classification = "gain", balanceAfter = 15402 },
    },
    {
        id = 3,
        at = stamp(2026, 9, 15, 15),
        guid = GUID,
        eventType = "resource",
        delta = 5,
        text = "Residual gain",
        meta = { resourceKey = "residual", classification = "gain" },
    },
    {
        id = 4,
        at = stamp(2026, 9, 16, 11),
        guid = GUID,
        eventType = "profession",
        text = "Tailoring increased",
    },
    {
        id = 5,
        at = stamp(2026, 9, 18, 17),
        guid = GUID,
        eventType = "quest",
        text = "A September Quest",
    },
    {
        id = 6,
        at = stamp(2026, 9, 22, 18),
        guid = GUID,
        eventType = "mount",
        text = "Brewfest Bomber",
        meta = { icon = 12345 },
    },
    {
        id = 7,
        at = stamp(2026, 10, 2, 13),
        guid = GUID,
        eventType = "quest",
        text = "An October Quest",
    },
    {
        id = 8,
        at = stamp(2026, 10, 2, 14),
        guid = GUID,
        eventType = "resource",
        delta = 560,
        text = "October gain",
        meta = { resourceKey = "tender", classification = "gain", balanceAfter = 15962 },
    },
}
WarbandFYI_DB.resources.balances = {
    tender = { currentBalance = 20000, accountWide = 20000 },
    residual = { currentBalance = 99999, accountWide = 99999 },
}

local clockBefore = WBF.MonthHistory.OnClock()
check("the open month is not finalized", clockBefore == 0 and WarbandFYI_DB.monthHistory["2026-09"] == nil, "made=" .. tostring(clockBefore))

local september = WBF.Aggregator.Build("month", 0)
local garrison = resource(september, "tender")
local residual = resource(september, "residual")
local person = september.characters and september.characters[1]
check("current month keeps the This Month label", september.label == "This Month — September 2026", tostring(september.label))
check("current month shows the calendar span", september.rangeText and september.rangeText:find("Sep 1", 1, true) and september.rangeText:find("Sep 30", 1, true), tostring(september.rangeText))
check("current month is not closed", september.closed ~= true and september.canGoForward ~= true)
check("September play time is kept", september.playedSeconds == 7200, "played=" .. tostring(september.playedSeconds))
check("September records the raid, quest, and profession", september.totals.raids == 1 and september.totals.quests == 1 and september.totals.professions == 1 and september.totals.mounts == 1)
check("Brewfest Bomber is a September highlight", highlightCount(september, "Brewfest Bomber") == 1)
check("September balance follows the last observation in the open month", garrison and garrison.earned == 1361 and garrison.net == 1361 and garrison.current == 15402, "current=" .. tostring(garrison and garrison.current))
check("the open month may show a live balance when the period never recorded one", residual and residual.current == 99999, "current=" .. tostring(residual and residual.current))
check("September item level is the month's own progress", person and person.name == "Miranora" and person.ilvlStart == 281 and person.ilvlEnd == 310, "start=" .. tostring(person and person.ilvlStart) .. " end=" .. tostring(person and person.ilvlEnd))
check("future offsets stay on the open month", WBF.Aggregator.Build("month", 4).monthKey == "2026-09")

local august = WBF.Aggregator.Build("month", -1)
check("an empty earlier month does not invent a dashboard", august.empty == true and august.emptyReason == "No WarbandFYI data was recorded for August 2026.", tostring(august.emptyReason))
check("the empty month has no zero-value cards", #(august.characters or {}) == 0 and #(august.highlights or {}) == 0 and #(august.resources or {}) == 0)
check("previous month stops at the month before recorded data", august.canGoBack ~= true and september.canGoBack == true)
check("July is not selectable", WBF.MonthHistory.CanSelect(2026, 7, now) == false)

now = stamp(2026, 10, 5, 9)
local made = WBF.MonthHistory.OnClock()
local saved = WarbandFYI_DB.monthHistory["2026-09"]
check("a later login finalizes the missed month", made == 1 and saved and saved.finalized == true, "made=" .. tostring(made))
check("finalizing does not require the midnight boundary", parts(saved.finalizedAt).month == 10 and parts(saved.finalizedAt).day == 5)
check("the open October month is not finalized", WarbandFYI_DB.monthHistory["2026-10"] == nil)
check("the same clock does not finalize again", WBF.MonthHistory.OnClock() == 0)
check("finalizing again does not rewrite September", WBF.MonthHistory.FinalizeCompleted() == 0 and WarbandFYI_DB.monthHistory["2026-09"] == saved)

local october = WBF.Aggregator.Build("month", 0)
local octoberGarrison = resource(october, "tender")
check("October is the current month", october.label == "This Month — October 2026" and october.closed ~= true, tostring(october.label))
check("October does not keep the Brewfest highlight", highlightCount(october, "Brewfest Bomber") == 0)
check("October shows its own quest and play time", october.totals.quests == 1 and october.playedSeconds == 100 and hasText(october.activity, "An October Quest"))
check("October currency is October's movement", octoberGarrison and octoberGarrison.earned == 560 and octoberGarrison.current == 15962, "earned=" .. tostring(octoberGarrison and octoberGarrison.earned))

local previous = WBF.Aggregator.Build("month", -1)
local previousGarrison = resource(previous, "tender")
local previousPerson = previous.characters and previous.characters[1]
check("previous month is September 2026", previous.label == "September 2026" and previous.closed == true and previous.canGoForward == true, tostring(previous.label))
check("September still shows Brewfest Bomber once", highlightCount(previous, "Brewfest Bomber") == 1)
check("September totals stay intact", previous.playedSeconds == 7200 and previous.totals.raids == 1 and previous.totals.mounts == 1 and previous.totals.quests == 1 and previous.totals.professions == 1)
check("October activity is not mixed into September", not hasText(previous.activity, "An October Quest") and previous.totals.quests == 1)
check("September currency does not become the October or live balance", previousGarrison and previousGarrison.earned == 1361 and previousGarrison.current == 15402 and previousGarrison.balanceAtEnd == true, "current=" .. tostring(previousGarrison and previousGarrison.current))
check("September does not borrow a live balance the month never recorded", resource(previous, "residual") and resource(previous, "residual").current == nil)
check("September item level does not become October's item level", previousPerson and previousPerson.ilvlStart == 281 and previousPerson.ilvlEnd == 310, "end=" .. tostring(previousPerson and previousPerson.ilvlEnd))
check("returning forward reaches the live month", WBF.Aggregator.Build("month", 0).label == "This Month — October 2026")

WarbandFYI_DB.events[#WarbandFYI_DB.events + 1] = {
    id = 9,
    at = stamp(2026, 9, 28, 12),
    guid = GUID,
    eventType = "mount",
    text = "Second Mount",
}
WBF.Aggregator.MarkDirty()
check("a second finalize leaves the completed month unchanged", WBF.MonthHistory.FinalizeCompleted() == 0 and WarbandFYI_DB.monthHistory["2026-09"] == saved)
check("the stored highlight is not duplicated or replaced", highlightCount({ highlights = saved.highlights }, "Brewfest Bomber") == 1 and not hasText(saved.highlights, "Second Mount"))
check("the rollup does not store the live wallet or the October balance", not containsNumber(saved, 20000) and not containsNumber(saved, 99999) and not containsNumber(saved, 15962) and not containsNumber(saved, 340))

local rollupBytes = approxBytes(saved)
print(string.format("BYTES  September rollup about %d bytes", rollupBytes))
check("a month rollup stays compact", rollupBytes < 8000, "bytes=" .. tostring(rollupBytes))

WBF.Database.Init()
check("reloading keeps the finalized September summary", WarbandFYI_DB.monthHistory["2026-09"] == saved and saved.finalized == true)

now = stamp(2027, 1, 20, 12)
check("January no longer has complete September rows", WBF.MonthHistory.CoversRaw(WBF.Time.MonthStart(2026, 9), now) == false)
WBF.Database.Init()
local retained = WBF.Aggregator.Build("month", offsetOf(2026, 9))
local retainedGarrison = resource(retained, "tender")
check("September is drawn from the rollup after retention", retained.fromRollup == true and retained.label == "September 2026", tostring(retained.label))
check("Brewfest Bomber survives retention", highlightCount(retained, "Brewfest Bomber") == 1 and not hasText(retained.highlights, "Second Mount"))
check("September totals survive retention", retained.playedSeconds == 7200 and retained.totals.mounts == 1 and retained.totals.raids == 1 and retained.totals.quests == 1)
check("retention does not substitute the live balance", retainedGarrison and retainedGarrison.current == 15402 and retainedGarrison.current ~= 20000, "current=" .. tostring(retainedGarrison and retainedGarrison.current))
check("the finalized object was not replaced", WarbandFYI_DB.monthHistory["2026-09"] == saved)

WarbandFYI_DB.monthHistory["2026-09"] = nil
WBF.Aggregator.MarkDirty()
local unrolled = WBF.Aggregator.Build("month", offsetOf(2026, 9))
check("a month missed past retention shows its retained rows", unrolled and not unrolled.fromRollup and hasText(unrolled.highlights, "Second Mount"))
WarbandFYI_DB.monthHistory["2026-09"] = saved
WBF.Aggregator.MarkDirty()

WarbandFYI_DB.monthHistory["2026-07"] = { finalized = true }
WarbandFYI_DB.monthHistory.bad = "nope"
local ok, malformed = pcall(function()
    return WBF.Aggregator.Build("month", offsetOf(2026, 7))
end)
check("malformed history does not break the dashboard", ok and type(malformed) == "table" and malformed.empty == true, tostring(malformed))
local oddOk, odd = pcall(function()
    return WBF.MonthHistory.ToSummary({
        finalized = true,
        year = 2026,
        month = 8,
        highlights = "nope",
        characters = { "bad" },
        playedSeconds = "lots",
    }, WBF.Aggregator.MonthContextFor(2026, 8, now, -5))
end)
check("a broken rollup becomes an empty month", oddOk and type(odd) == "table" and odd.view == "month", tostring(odd))

freshDb()
now = stamp(2026, 9, 30, 18)
WarbandFYI_DB.characters[GUID] = {
    guid = GUID,
    name = "Miranora",
    classFile = "MAGE",
    discovered = true,
}
WarbandFYI_DB.events = {
    {
        id = 1,
        at = stamp(2026, 9, 14, 9),
        guid = GUID,
        eventType = "quest",
        text = "Started late",
    },
}
local partial = WBF.Aggregator.Build("month", 0)
check("a mid-month start is labeled from the first record", partial.rangeText and partial.rangeText:find("Tracked", 1, true) and partial.rangeText:find("Sep 14", 1, true) and partial.rangeText:find("Sep 30", 1, true), tostring(partial.rangeText))

freshDb()
now = stamp(2026, 8, 20, 12)
WarbandFYI_DB.characters[GUID] = {
    guid = GUID,
    name = "Miranora",
    classFile = "MAGE",
    discovered = true,
}
WarbandFYI_DB.events = {
    {
        id = 1,
        at = stamp(2026, 8, 10, 12),
        guid = GUID,
        eventType = "quest",
        text = "An August Quest",
    },
}
now = stamp(2026, 10, 8, 12)
local missed = WBF.MonthHistory.FinalizeCompleted()
check("a month missed while logged out is finalized on the next login", missed >= 1 and WarbandFYI_DB.monthHistory["2026-08"] and WarbandFYI_DB.monthHistory["2026-08"].finalized == true, "made=" .. tostring(missed))
check("a month with no records is not fabricated", WarbandFYI_DB.monthHistory["2026-09"] == nil)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All month history checks passed")
