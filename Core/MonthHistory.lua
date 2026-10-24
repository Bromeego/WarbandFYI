local _, WBF = ...

-- Compact summaries of completed calendar months. Raw journal rows still
-- rebuild a month while retention keeps them. Once those rows age out, the
-- dashboard reads the rollup instead. A finalized month is written once.

WBF.MonthHistory = {}

local RECENT_ACTIVITY = 6
local seenMonth = nil

local function Database()
    return WBF.Database and WBF.Database.Get and WBF.Database.Get() or nil
end

local function History()
    local db = Database()
    if type(db) ~= "table" then
        return nil
    end
    if type(db.monthHistory) ~= "table" then
        db.monthHistory = {}
    end
    return db.monthHistory
end

local function NoteStamp(earliest, at)
    if type(at) ~= "number" then
        return earliest
    end
    if not earliest or at < earliest then
        return at
    end
    return earliest
end

local function EarliestStamp(db)
    if type(db) ~= "table" then
        return nil
    end
    local earliest = nil
    local events = db.events or {}
    for index = 1, #events do
        local event = events[index]
        if type(event) == "table" and not event.sample then
            earliest = NoteStamp(earliest, event.at)
        end
    end
    local sessions = db.sessions or {}
    for index = 1, #sessions do
        local session = sessions[index]
        if type(session) == "table" and not session.sample then
            earliest = NoteStamp(earliest, session.startedAt)
        end
    end
    local snapshots = db.snapshots or {}
    for index = 1, #snapshots do
        local snapshot = snapshots[index]
        if type(snapshot) == "table" and not snapshot.sample then
            earliest = NoteStamp(earliest, snapshot.at)
        end
    end
    return earliest
end

local function SessionEnd(session)
    if type(session.endedAt) == "number" then
        return session.endedAt
    end
    return WBF.Time.Now()
end

local function InRange(at, startAt, endAt)
    return type(at) == "number" and at >= startAt and at <= endAt
end

function WBF.MonthHistory.HasRecords(startAt, endAt)
    local db = Database()
    if type(db) ~= "table" or type(startAt) ~= "number" or type(endAt) ~= "number" then
        return false
    end
    local events = db.events or {}
    for index = 1, #events do
        local event = events[index]
        if type(event) == "table" and not event.sample and InRange(event.at, startAt, endAt) then
            return true
        end
    end
    local snapshots = db.snapshots or {}
    for index = 1, #snapshots do
        local snapshot = snapshots[index]
        if type(snapshot) == "table" and not snapshot.sample and InRange(snapshot.at, startAt, endAt) then
            return true
        end
    end
    local sessions = db.sessions or {}
    for index = 1, #sessions do
        local session = sessions[index]
        if type(session) == "table" and not session.sample and type(session.startedAt) == "number" then
            local ended = SessionEnd(session)
            if ended > startAt and session.startedAt <= endAt then
                return true
            end
        end
    end
    return false
end

function WBF.MonthHistory.CoversRaw(startAt, now)
    if type(startAt) ~= "number" then
        return false
    end
    if not WBF.Database or not WBF.Database.RetentionCutoff then
        return true
    end
    local cutoff = WBF.Database.RetentionCutoff(now)
    if not cutoff then
        return true
    end
    return startAt >= cutoff
end

-- True while nothing from startAt onwards has been removed. Retention's cutoff
-- can pass a month's start long before any prune runs, such as after a long
-- break, and those rows can still be rolled up.
function WBF.MonthHistory.RowsIntact(startAt, now)
    if type(startAt) ~= "number" then
        return false
    end
    if not WBF.Database or not WBF.Database.PrunedThrough then
        return WBF.MonthHistory.CoversRaw(startAt, now)
    end
    local through = WBF.Database.PrunedThrough(now)
    if type(through) ~= "number" then
        return true
    end
    return startAt > through
end

function WBF.MonthHistory.PartialStart(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    local earliest = EarliestStamp(Database())
    if not earliest or type(ctx.startAt) ~= "number" or earliest < ctx.startAt then
        return nil
    end
    local parts = date("*t", earliest)
    if parts.year == ctx.year and parts.month == ctx.month and parts.day > 1 then
        return earliest
    end
    return nil
end

local function FloorMonth(now)
    local year, month = WBF.Time.CurrentMonth(now)
    local found = false
    local earliest = EarliestStamp(Database())
    if earliest then
        local parts = date("*t", earliest)
        year, month = parts.year, parts.month
        found = true
    end
    local history = History()
    if history then
        for _, row in pairs(history) do
            if type(row) == "table" and row.finalized == true and type(row.year) == "number" and type(row.month) == "number" then
                if not found or row.year < year or (row.year == year and row.month < month) then
                    year, month = row.year, row.month
                    found = true
                end
            end
        end
    end
    if not found then
        return nil, nil
    end
    return WBF.Time.AddMonths(year, month, -1)
end

function WBF.MonthHistory.CanSelect(year, month, now)
    if type(year) ~= "number" or type(month) ~= "number" or month < 1 or month > 12 then
        return false
    end
    now = now or WBF.Time.Now()
    local currentYear, currentMonth = WBF.Time.CurrentMonth(now)
    if year > currentYear or (year == currentYear and month > currentMonth) then
        return false
    end
    local floorYear, floorMonth = FloorMonth(now)
    if not floorYear then
        return year == currentYear and month == currentMonth
    end
    if year < floorYear or (year == floorYear and month < floorMonth) then
        return false
    end
    return true
end

function WBF.MonthHistory.ApplyChrome(summary, ctx, now)
    if type(summary) ~= "table" or type(ctx) ~= "table" then
        return summary
    end
    now = now or WBF.Time.Now()
    summary.view = "month"
    summary.monthKey = ctx.key
    summary.monthYear = ctx.year
    summary.monthIndex = ctx.month
    summary.monthOffset = ctx.offset or 0
    summary.closed = ctx.closed and true or false
    summary.label = ctx.label
    summary.periodPhrase = ctx.periodPhrase
    summary.periodStart = ctx.periodStart
    summary.periodEnd = ctx.periodEnd
    if type(summary.startAt) ~= "number" then
        summary.startAt = ctx.startAt
    end
    if type(summary.endAt) ~= "number" then
        summary.endAt = ctx.endAt
    end
    local tracked = summary.trackedFrom
    if type(tracked) == "number" and type(ctx.periodStart) == "number" and tracked > ctx.periodStart then
        summary.rangeText = "Tracked " .. WBF.Time.FormatDay(tracked) .. "  –  " .. WBF.Time.FormatDay(ctx.periodEnd)
    else
        summary.rangeText = WBF.Time.FormatDay(ctx.periodStart) .. "  –  " .. WBF.Time.FormatDay(ctx.periodEnd)
    end
    local prevYear, prevMonth = WBF.Time.AddMonths(ctx.year, ctx.month, -1)
    summary.canGoBack = WBF.MonthHistory.CanSelect(prevYear, prevMonth, now) == true
    summary.canGoForward = not ctx.isCurrent
    return summary
end

function WBF.MonthHistory.EmptySummary(ctx)
    local summary = {
        view = "month",
        empty = true,
        emptyReason = "No WarbandFYI data was recorded for " .. WBF.Time.MonthTitle(ctx.year, ctx.month) .. ".",
        playedSeconds = 0,
        characters = {},
        totals = WBF.Aggregator.EmptyCounts(),
        goldNet = 0,
        highlights = {},
        activity = {},
        resources = {},
        hasActivity = false,
        closed = true,
    }
    return WBF.MonthHistory.ApplyChrome(summary, ctx)
end

function WBF.MonthHistory.Get(key)
    local history = History()
    if not history or type(key) ~= "string" then
        return nil
    end
    local row = history[key]
    if type(row) ~= "table" or row.finalized ~= true then
        return nil
    end
    if type(row.year) ~= "number" or type(row.month) ~= "number" then
        return nil
    end
    if row.month < 1 or row.month > 12 then
        return nil
    end
    return row
end

local function CopyScalars(source)
    local out = {}
    if type(source) ~= "table" then
        return out
    end
    for key, value in pairs(source) do
        local kind = type(value)
        if type(key) == "string" and (kind == "number" or kind == "string" or kind == "boolean") then
            out[key] = value
        end
    end
    return out
end

local function ListOfTables(value)
    local out = {}
    if type(value) ~= "table" then
        return out
    end
    for index = 1, #value do
        if type(value[index]) == "table" then
            out[#out + 1] = value[index]
        end
    end
    return out
end

local function FillCounts(source)
    local counts = WBF.Aggregator.EmptyCounts()
    if type(source) ~= "table" then
        return counts
    end
    for key, value in pairs(source) do
        if type(value) == "number" then
            counts[key] = value
        elseif type(value) == "string" then
            counts[key] = value
        end
    end
    return counts
end

local function CopyActivity(activity)
    local out = {}
    local list = ListOfTables(activity)
    local limit = math.min(RECENT_ACTIVITY, #list)
    for index = 1, limit do
        local event = list[index]
        local copy = CopyScalars(event)
        if type(event.meta) == "table" then
            copy.meta = CopyScalars(event.meta)
        end
        out[#out + 1] = copy
    end
    return out
end

local function CopyCharacters(characters)
    local out = {}
    local list = ListOfTables(characters)
    for index = 1, #list do
        local row = list[index]
        local copy = CopyScalars(row)
        copy.counts = CopyScalars(row.counts)
        if type(copy.guid) == "string" then
            out[#out + 1] = copy
        end
    end
    return out
end

local function CopyResources(resources)
    local out = {}
    local list = ListOfTables(resources)
    for index = 1, #list do
        local row = list[index]
        out[#out + 1] = {
            key = row.key,
            name = row.name,
            short = row.short,
            texture = type(row.texture) == "number" and row.texture or (type(row.texture) == "string" and row.texture or nil),
            earned = row.earned or 0,
            spent = row.spent or 0,
            net = row.net or 0,
            opening = row.opening,
            current = row.current,
            balanceAtEnd = row.balanceAtEnd == true,
            accountWide = row.accountWide == true,
        }
    end
    return out
end

local function CopyHighlights(highlights)
    local out = {}
    local list = ListOfTables(highlights)
    for index = 1, #list do
        out[#out + 1] = CopyScalars(list[index])
    end
    return out
end

local function CopyFishing(items)
    local out = {}
    local list = ListOfTables(items)
    for index = 1, math.min(8, #list) do
        local item = list[index]
        out[#out + 1] = {
            name = item.name,
            qty = item.qty,
        }
    end
    return out
end

local function FoldLivePlay(summary)
    if type(summary) ~= "table" then
        return
    end
    if summary.liveSegment and WBF.Aggregator.LivePlay then
        local extra, guid = WBF.Aggregator.LivePlay(summary)
        if type(extra) == "number" and extra > 0 then
            summary.playedSeconds = (summary.playedSeconds or 0) + extra
            local characters = summary.characters or {}
            for index = 1, #characters do
                if characters[index].guid == guid then
                    characters[index].playedSeconds = (characters[index].playedSeconds or 0) + extra
                    break
                end
            end
            summary.hasActivity = true
        end
    end
    summary.liveSegment = nil
end

local function ActiveSummary(summary)
    if type(summary) ~= "table" or summary.empty then
        return false
    end
    if (summary.playedSeconds or 0) > 0 or (summary.goldNet or 0) ~= 0 then
        return true
    end
    if #(summary.activity or {}) > 0 or #(summary.characters or {}) > 0 or #(summary.highlights or {}) > 0 or #(summary.resources or {}) > 0 then
        return true
    end
    return false
end

local function Capture(year, month, now)
    if not WBF.Aggregator or not WBF.Aggregator.BuildClosedMonth then
        return nil
    end
    local summary = WBF.Aggregator.BuildClosedMonth(year, month, now)
    if type(summary) ~= "table" then
        return nil
    end
    FoldLivePlay(summary)
    if not ActiveSummary(summary) then
        return nil
    end
    local ctx = WBF.Aggregator.MonthContextFor(year, month, now, 0)
    return {
        version = 1,
        finalized = true,
        finalizedAt = now,
        key = ctx.key,
        year = year,
        month = month,
        startAt = ctx.periodStart,
        endAt = ctx.closedEnd,
        trackedFrom = summary.trackedFrom,
        playedSeconds = summary.playedSeconds or 0,
        goldNet = summary.goldNet or 0,
        goldTracked = summary.goldTracked == true,
        goldOffline = summary.goldOffline or 0,
        includesSample = summary.includesSample == true,
        totals = CopyScalars(summary.totals),
        fishingItems = CopyFishing(summary.fishingItems),
        resources = CopyResources(summary.resources),
        characters = CopyCharacters(summary.characters),
        highlights = CopyHighlights(summary.highlights),
        activity = CopyActivity(summary.activity),
    }
end

function WBF.MonthHistory.ToSummary(rollup, ctx)
    local summary = {
        view = "month",
        fromRollup = true,
        empty = false,
        playedSeconds = type(rollup.playedSeconds) == "number" and rollup.playedSeconds or 0,
        goldNet = type(rollup.goldNet) == "number" and rollup.goldNet or 0,
        goldTracked = rollup.goldTracked == true,
        goldOffline = type(rollup.goldOffline) == "number" and rollup.goldOffline or 0,
        includesSample = rollup.includesSample == true,
        trackedFrom = type(rollup.trackedFrom) == "number" and rollup.trackedFrom or nil,
        totals = FillCounts(rollup.totals),
        fishingItems = CopyFishing(rollup.fishingItems),
        resources = CopyResources(rollup.resources),
        highlights = CopyHighlights(rollup.highlights),
        activity = CopyActivity(rollup.activity),
        liveSegment = nil,
        startAt = rollup.startAt,
        endAt = rollup.endAt,
    }
    local characters = {}
    local stored = ListOfTables(rollup.characters)
    for index = 1, #stored do
        local row = stored[index]
        local copy = CopyScalars(row)
        copy.counts = FillCounts(row.counts)
        if type(copy.guid) == "string" then
            characters[#characters + 1] = copy
        end
    end
    summary.characters = characters
    summary.hasActivity = ActiveSummary(summary)
    if not summary.hasActivity then
        summary.empty = true
        summary.emptyReason = "No WarbandFYI data was recorded for " .. WBF.Time.MonthTitle(rollup.year, rollup.month) .. "."
        summary.highlights = {}
        summary.characters = {}
        summary.activity = {}
        summary.resources = {}
    end
    if type(ctx) == "table" then
        WBF.MonthHistory.ApplyChrome(summary, ctx)
    end
    summary.closed = true
    summary.fromRollup = true
    return summary
end

function WBF.MonthHistory.SummaryFor(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    local rollup = WBF.MonthHistory.Get(ctx.key)
    if rollup and rollup.year == ctx.year and rollup.month == ctx.month then
        local ok, summary = pcall(WBF.MonthHistory.ToSummary, rollup, ctx)
        if ok and type(summary) == "table" then
            return summary
        end
    end
    return WBF.MonthHistory.EmptySummary(ctx)
end

function WBF.MonthHistory.FinalizeCompleted(now)
    now = now or (WBF.Time and WBF.Time.Now and WBF.Time.Now()) or nil
    if type(now) ~= "number" or not WBF.Time.CurrentMonth or not WBF.Time.MonthBounds then
        return 0
    end
    local history = History()
    if not history then
        return 0
    end
    local earliest = EarliestStamp(Database())
    if not earliest then
        return 0
    end
    local parts = date("*t", earliest)
    local year, month = parts.year, parts.month
    local currentYear, currentMonth = WBF.Time.CurrentMonth(now)
    local made = 0
    local guard = 0
    while guard < 360 do
        guard = guard + 1
        if year > currentYear or (year == currentYear and month >= currentMonth) then
            break
        end
        local key = WBF.Time.MonthKey(year, month)
        local existing = history[key]
        if not (type(existing) == "table" and existing.finalized == true) then
            local startAt, _, _, closedEnd = WBF.Time.MonthBounds(year, month, now)
            if WBF.MonthHistory.RowsIntact(startAt, now) and WBF.MonthHistory.HasRecords(startAt, closedEnd) then
                local rollup = Capture(year, month, now)
                if rollup then
                    history[key] = rollup
                    made = made + 1
                end
            end
        end
        year, month = WBF.Time.AddMonths(year, month, 1)
    end
    if made > 0 and WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
    return made
end

function WBF.MonthHistory.OnClock(now)
    if not WBF.Time.CurrentMonth or not WBF.Time.MonthKey then
        return 0
    end
    now = now or WBF.Time.Now()
    local year, month = WBF.Time.CurrentMonth(now)
    local key = WBF.Time.MonthKey(year, month)
    if key == seenMonth then
        return 0
    end
    local made = WBF.MonthHistory.FinalizeCompleted(now)
    seenMonth = key
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
    return made or 0
end
