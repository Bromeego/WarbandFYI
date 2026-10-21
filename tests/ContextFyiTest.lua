-- Recurring FYIs: activation, occurrence completion, permanence, migration, notices.
-- Run from the repo root:
--   lua tests/ContextFyiTest.lua

local script = arg and arg[0] or "tests/ContextFyiTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

if type(time) ~= "function" then
    function time(parts)
        if type(parts) == "table" then
            return os.time(parts)
        end
        return os.time()
    end
end

if type(date) ~= "function" then
    function date(fmt, ts)
        return os.date(fmt, ts)
    end
end

-- The test realm runs on UTC so stamps do not depend on the machine's
-- timezone or DST.
local function stamp(year, month, day, hour, minute)
    local y = month <= 2 and year - 1 or year
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
    local days = era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
    return days * 86400 + (hour or 0) * 3600 + (minute or 0) * 60
end

local WBF = {}
local now = stamp(2026, 10, 5, 12, 0)

-- Seconds past the minute exercise the realm-clock rounding in Stamp().
local drift = 37

function GetServerTime()
    return now + drift
end

C_DateAndTime = {
    GetCurrentCalendarTime = function()
        local parts = os.date("!*t", now + drift)
        return { year = parts.year, month = parts.month, monthDay = parts.day, hour = parts.hour, minute = parts.min }
    end,
}
local failures = 0

local function check(name, condition, detail)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  " .. tostring(detail)) or ""))
end

loadAddon("Utils/Format.lua", WBF)
loadAddon("Utils/Time.lua", WBF)
loadAddon("Utils/Debug.lua", WBF)
loadAddon("Core/Characters.lua", WBF)
loadAddon("Core/Database.lua", WBF)
loadAddon("Core/NotebookSmart.lua", WBF)
loadAddon("Core/Notebook.lua", WBF)
loadAddon("Core/Triggers.lua", WBF)
loadAddon("Core/EventTriggers.lua", WBF)
loadAddon("Core/ContextFyi.lua", WBF)
loadAddon("Tracking/PlanAchievements.lua", WBF)

WBF.Time.Now = function()
    return now
end

local function holiday(title, year, month, day, texture)
    return {
        title = title,
        calendarType = "HOLIDAY",
        sequenceType = "START",
        eventID = texture,
        iconTexture = texture,
        startTime = { year = year, month = month, monthDay = day, hour = 0, minute = 0 },
        endTime = { year = year, month = month, monthDay = day + 6, hour = 23, minute = 0 },
        holidayName = title,
        holidayTexture = texture,
        holidayStart = { year = year, month = month, monthDay = day, hour = 0, minute = 0 },
        holidayEnd = { year = year, month = month, monthDay = day + 6, hour = 23, minute = 0 },
    }
end

local function calendar(year, month, day, rows)
    return {
        now = { year = year, month = month, monthDay = day, hour = 12, minute = 0 },
        months = {
            [0] = {
                year = year,
                month = month,
                numDays = 31,
                days = {
                    [day] = rows,
                },
            },
        },
    }
end

local function fresh()
    now = stamp(2026, 10, 5, 12, 0)
    WarbandFYI_DB = nil
    WBF.Database.ready = false
    WBF.Database.Init()
    WBF.EventTriggers.UseCalendar(calendar(2026, 10, 5, {}))
    WBF.EventTriggers.Refresh()
end

local function use(year, month, day, rows)
    now = stamp(year, month, day, 12, 0)
    WBF.EventTriggers.UseCalendar(calendar(year, month, day, rows))
    WBF.EventTriggers.Refresh()
end

fresh()
check("trigger provider is registered", WBF.Triggers.Known("WOW_EVENT") == true)
check("unregistered kinds stay inactive", WBF.Triggers.IsActive({ type = "ZONE", eventKey = "tanaan" }) == false)

local quiet = WBF.ContextFyi.Save({
    type = "RECURRING",
    title = "Brewfest",
    trigger = { type = "WOW_EVENT", eventKey = "brewfest", eventName = "Brewfest" },
    items = {
        { text = "Queue Coren Direbrew" },
        { text = "Check Brewfest Prize Tokens" },
    },
})
check("brewfest fyi is saved", quiet and quiet.id ~= nil and quiet.type == "RECURRING")
check("fyi is inactive when the event is absent", WBF.ContextFyi.IsActionable(quiet) == false)
local absent = WBF.ContextFyi.State(quiet.id)
check("absent state has no occurrence", absent and absent.active == false and absent.occurrenceKey == nil and absent.permanent == false)

use(2026, 9, 22, { holiday("Brewfest", 2026, 9, 20, 1801) })
local brewKey = "EVENT:BREWFEST:" .. stamp(2026, 9, 20, 0, 0)
local active = WBF.ContextFyi.State(quiet.id)
check("fyi activates when Brewfest occurs", active and active.active == true)
check("occurrence key uses the event and start", active and active.occurrenceKey == brewKey, active and active.occurrenceKey)
for _, seconds in ipairs({ 0, 59 }) do
    drift = seconds
    use(2026, 9, 22, { holiday("Brewfest", 2026, 9, 20, 1801) })
    local rescanned = WBF.ContextFyi.State(quiet.id)
    check("occurrence key is stable at :" .. seconds .. " past the minute", rescanned and rescanned.occurrenceKey == brewKey, rescanned and rescanned.occurrenceKey)
end
drift = 37

-- Scenario A. Complete this Brewfest. It stays dormant, then returns next time.
check("completing this occurrence succeeds", WBF.ContextFyi.CompleteOccurrence(quiet.id) ~= nil)
check("completed occurrence is dormant", WBF.ContextFyi.IsActionable(quiet.id) == false)
local stored = WBF.ContextFyi.Get(quiet.id)
check("occurrence completion is stored", stored.completedOccurrences[brewKey] and stored.completedOccurrences[brewKey].completedAt ~= nil)
check("occurrence items were marked done", stored.completedOccurrences[brewKey].items[stored.items[1].id] ~= nil)

WBF.Database.ready = false
WBF.Database.Init()
use(2026, 9, 22, { holiday("Brewfest", 2026, 9, 20, 1801) })
local reloaded = WBF.ContextFyi.Get(quiet.id)
check("same occurrence stays completed after reload", reloaded and reloaded.completedOccurrences[brewKey] and reloaded.completedOccurrences[brewKey].completedAt ~= nil)
check("reload does not reactivate the same Brewfest", WBF.ContextFyi.IsActionable(quiet.id) == false)

use(2027, 9, 22, { holiday("Brewfest", 2027, 9, 20, 1801) })
local nextKey = "EVENT:BREWFEST:" .. stamp(2027, 9, 20, 0, 0)
local returned = WBF.ContextFyi.State(quiet.id)
check("a later Brewfest uses a new occurrence", returned and returned.occurrenceKey == nextKey and returned.occurrenceKey ~= brewKey)
check("the same FYI reactivates next Brewfest", returned and returned.active == true)
check("checklist items reset next Brewfest", WBF.ContextFyi.ItemDone(reloaded, reloaded.items[1], nextKey) == false)
check("previous occurrence record is kept", reloaded.completedOccurrences[brewKey] ~= nil)

-- Scenario B and C. Darkmoon checklist with one permanent collectible.
fresh()
local faire = WBF.ContextFyi.Save({
    type = "RECURRING",
    title = "Darkmoon Faire cleanup",
    notes = "Tickets and pets.",
    trigger = { type = "WOW_EVENT", eventKey = "darkmoon" },
    items = {
        { text = "Finish Darkmoon Despoiler", completionMode = "OCCURRENCE" },
        { text = "Battle Jeremy Feasel", completionMode = "OCCURRENCE" },
        { text = "Check pets", completionMode = "OCCURRENCE" },
        { text = "Spend Darkmoon Prize Tickets", completionMode = "OCCURRENCE", currencyID = 515 },
        { text = "Obtain Darkmoon Dancing Bear", completionMode = "PERMANENT" },
    },
})
check("darkmoon fyi keeps mixed items", faire and #faire.items == 5 and faire.items[5].completionMode == "PERMANENT")
check("darkmoon fyi is inactive in an empty month", WBF.ContextFyi.IsActionable(faire) == false)
use(2026, 10, 5, { holiday("Darkmoon Faire", 2026, 10, 4, 235448) })
local faireKey = "EVENT:DARKMOON:" .. stamp(2026, 10, 4, 0, 0)
check("darkmoon fyi activates for this faire", WBF.ContextFyi.State(faire.id).occurrenceKey == faireKey and WBF.ContextFyi.IsActionable(faire.id))
local bear = faire.items[5]
check("permanent item can be completed", WBF.ContextFyi.SetItemDone(faire.id, bear.id, true) ~= nil)
check("permanent item is done this faire", WBF.ContextFyi.ItemDone(faire, bear, faireKey) == true)
check("recurring items are still open", WBF.ContextFyi.ItemDone(faire, faire.items[1], faireKey) == false)
check("one finished permanent item does not settle the fyi", WBF.ContextFyi.IsActionable(faire.id) == true)
for index = 1, 4 do
    WBF.ContextFyi.SetItemDone(faire.id, faire.items[index].id, true)
end
check("finishing recurring items settles this faire", WBF.ContextFyi.IsActionable(faire.id) == false)
use(2026, 11, 4, { holiday("Darkmoon Faire", 2026, 11, 1, 235448) })
local nextFaire = "EVENT:DARKMOON:" .. stamp(2026, 11, 1, 0, 0)
check("next faire is a different occurrence", WBF.ContextFyi.State(faire.id).occurrenceKey == nextFaire)
check("recurring item resets next faire", WBF.ContextFyi.ItemDone(faire, faire.items[1], nextFaire) == false)
check("permanent item stays completed next faire", WBF.ContextFyi.ItemDone(faire, bear, nextFaire) == true)
check("fyi is active again next faire", WBF.ContextFyi.IsActionable(faire.id) == true)

check("permanent completion archives the fyi", WBF.ContextFyi.CompletePermanent(faire.id) ~= nil)
check("archived fyi does not reactivate", WBF.ContextFyi.IsActionable(faire.id) == false)
check("archive keeps occurrence history", WBF.ContextFyi.Get(faire.id).completedOccurrences[faireKey] ~= nil)
use(2027, 1, 3, { holiday("Darkmoon Faire", 2027, 1, 3, 235448) })
check("archived fyi stays inactive on a future faire", WBF.ContextFyi.IsActionable(faire.id) == false)
check("archived fyi is not deleted", WBF.ContextFyi.Get(faire.id) ~= nil and WBF.ContextFyi.Get(faire.id).permanentAt ~= nil)

-- Reference notes are not reminders. Tasks complete once.
local reference = WBF.ContextFyi.Save({ type = "REFERENCE", title = "Vendor sells the transmog set.", notes = "Remember that." })
check("reference fyi has no trigger", reference and reference.type == "REFERENCE" and reference.trigger == nil)
check("reference fyi is not an active reminder", WBF.ContextFyi.IsActionable(reference) == false)
local task = WBF.ContextFyi.Save({ type = "TASK", title = "Finish the Algalon pet battle." })
check("task starts open", task and WBF.ContextFyi.IsActionable(task) == true)
WBF.ContextFyi.CompleteTask(task.id)
check("completed task stays done", WBF.ContextFyi.IsActionable(task.id) == false)

-- Migration. A schema 5 quick note becomes a Reference and is not discarded.
WarbandFYI_DB = {
    schemaVersion = 5,
    config = { retentionDays = 120, debug = false },
    nextIds = { session = 3, event = 4, notebookNote = 2 },
    sessions = {},
    characters = {},
    snapshots = {},
    events = {},
    dedupe = {},
    notebook = {
        pages = {},
        pageOrder = {},
        sections = {},
        blocks = {},
        quickNotes = {
            q1 = { id = "q1", text = "Remember the vendor.", createdAt = now, updatedAt = now },
        },
        quickNoteOrder = { "q1" },
    },
}
WBF.Database.ready = false
WBF.Database.Init()
local legacy = WarbandFYI_DB.notebook.quickNotes.q1
check("schema 5 migrates to 7", WarbandFYI_DB.schemaVersion == 7)
check("old note survives the schema change", legacy and legacy.text == "Remember the vendor.")
check("old note becomes a reference fyi", legacy and legacy.type == "REFERENCE" and legacy.trigger == nil)
check("migration adds fyi storage", type(WarbandFYI_DB.notebook.contextFyis) == "table" and type(WarbandFYI_DB.notebook.fyiHistory) == "table")

-- Notices. First login can speak. Reload and acknowledgement stay quiet.
fresh()
use(2026, 10, 5, { holiday("Darkmoon Faire", 2026, 10, 4, 235448) })
local noted = WBF.ContextFyi.Save({
    type = "RECURRING",
    title = "Darkmoon Faire cleanup",
    trigger = { type = "WOW_EVENT", eventKey = "darkmoon" },
    items = {
        { text = "Finish Darkmoon Despoiler" },
        { text = "Battle Jeremy Feasel" },
    },
})
local first = WBF.ContextFyi.ConsiderNotice()
check("first relevant login can notify", first and first.primary and first.primary.count == 2 and first.primary.lines[1] == "Finish Darkmoon Despoiler")
check("presenting the notice is recorded", WBF.ContextFyi.NotePresented(first.signature) == true)
check("reload does not notify again", WBF.ContextFyi.ConsiderNotice() == nil)
WBF.Database.ready = false
WBF.Database.Init()
use(2026, 10, 5, { holiday("Darkmoon Faire", 2026, 10, 4, 235448) })
check("saved acknowledgement survives reload", WBF.ContextFyi.ConsiderNotice() == nil)

use(2026, 11, 4, { holiday("Darkmoon Faire", 2026, 11, 1, 235448) })
local again = WBF.ContextFyi.ConsiderNotice()
check("a new occurrence can notify", again and again.signature ~= first.signature)
check("acknowledgement suppresses that notice", WBF.ContextFyi.Acknowledge(again.signature) == true and WBF.ContextFyi.ConsiderNotice() == nil)
WBF.ContextFyi.SetNoticesEnabled(false)
use(2027, 2, 7, { holiday("Darkmoon Faire", 2027, 2, 7, 235448) })
check("disabled notices stay quiet", WBF.ContextFyi.ConsiderNotice() == nil)
WBF.ContextFyi.SetNoticesEnabled(true)

-- Currency. Registered amount, gain when observed, current amount when not.
WBF.Resources = {
    ByCurrencyID = function(currencyID)
        if currencyID == 515 then
            return { key = "darkmoon_ticket", name = "Darkmoon Prize Ticket" }
        end
        if currencyID == 37829 then
            return { key = "brewfest_token", name = "Brewfest Prize Token" }
        end
        return nil
    end,
    NotebookView = function(key)
        if key == "darkmoon_ticket" then
            return { name = "Darkmoon Prize Ticket", amount = 143 }
        end
        if key == "brewfest_token" then
            return { name = "Brewfest Prize Token", amount = 184 }
        end
        return nil
    end,
    Report = function(key)
        if key == "darkmoon_ticket" then
            return { period = { earned = 76 } }
        end
        return { period = { earned = 0 } }
    end,
}
local tickets = WBF.ContextFyi.DescribeCurrency(515, stamp(2026, 10, 4, 0, 0), "Darkmoon Faire")
check("registered currency shows the current amount", tickets and tickets.amount == 143 and tickets.name == "Darkmoon Prize Ticket")
check("observed gain is reported for this occurrence", tickets and tickets.gained == 76)
local tokens = WBF.ContextFyi.DescribeCurrency(37829, stamp(2026, 9, 20, 0, 0), "Brewfest")
check("missing gain falls back to the current amount", tokens and tokens.amount == 184 and tokens.gained == nil)
local unknown = WBF.ContextFyi.DescribeCurrency(999999, nil, "Brewfest")
check("unknown currency does not throw", unknown and unknown.missing == true and unknown.amount == nil)
check("saved fyi still resolves with a currency attached", noted and WBF.ContextFyi.Get(noted.id) ~= nil)

-- Achievements. Progress, completion, and a bad id.
local progressCalls = 0
WBF.PlanAchievements.Progress = function(achievementID)
    progressCalls = progressCalls + 1
    if achievementID == 6030 then
        return { id = 6030, name = "Darkmoon Despoiler", current = 7, required = 9, completed = false, kind = "criteria" }
    end
    if achievementID == 6019 then
        return { id = 6019, name = "Darkmoon Dancing Bear", completed = true, kind = "simple" }
    end
    return nil
end
WBF.PlanAchievements.ProgressText = function(progress)
    if progress and progress.current and progress.required then
        return progress.current .. " / " .. progress.required
    end
    if progress and progress.completed then
        return "Complete"
    end
    return nil
end
local despoiler = WBF.ContextFyi.DescribeAchievement(6030)
check("achievement progress is displayed", despoiler and despoiler.name == "Darkmoon Despoiler" and despoiler.current == 7 and despoiler.required == 9 and despoiler.completed == false)
local bearAchievement = WBF.ContextFyi.DescribeAchievement(6019)
check("completed achievement is detected", bearAchievement and bearAchievement.completed == true)
local broken = WBF.ContextFyi.DescribeAchievement(42)
check("invalid achievement does not break the description", broken and broken.missing == true and broken.completed == false)
local linked = WBF.ContextFyi.Save({
    type = "RECURRING",
    title = "Despoiler",
    trigger = { type = "WOW_EVENT", eventKey = "darkmoon" },
    achievementID = 6030,
    items = { { text = "Finish criteria", achievementID = 42 } },
})
local view = nil
local relevance = WBF.ContextFyi.Relevance()
for index = 1, #relevance.events do
    local group = relevance.events[index]
    for fyiIndex = 1, #group.fyis do
        if group.fyis[fyiIndex].id == linked.id then
            view = group.fyis[fyiIndex]
        end
    end
end
check("focus view keeps a bad achievement id", view and view.items[1].achievement and view.items[1].achievement.missing == true)
check("focus view shows live achievement progress", view and view.achievement and view.achievement.current == 7)

-- History stays bounded and can describe the previous occurrence.
fresh()
for index = 1, 8 do
    WBF.ContextFyi.RememberHistory("darkmoon", "EVENT:DARKMOON:" .. (1700000000 + index), "Month " .. index, index, 4)
end
local history = WarbandFYI_DB.notebook.fyiHistory
local darkmoonRows = 0
for index = 1, #history do
    if history[index].eventKey == "darkmoon" then
        darkmoonRows = darkmoonRows + 1
    end
end
check("history prunes to six rows per event", darkmoonRows == 6 and #history <= 48)

-- Simulation does not replace a real calendar reading for other events.
use(2026, 9, 22, { holiday("Brewfest", 2026, 9, 20, 1801) })
local simulated = WBF.EventTriggers.Simulate("Darkmoon Faire")
local both = WBF.EventTriggers.Active()
local sawBrewfest, sawFaire = false, false
for index = 1, #both do
    if both[index].eventKey == "brewfest" then
        sawBrewfest = true
    end
    if both[index].eventKey == "darkmoon" and both[index].simulated then
        sawFaire = true
    end
end
check("simulation adds an event without dropping the calendar", simulated and simulated.name == "Darkmoon Faire" and sawBrewfest and sawFaire)
check("simulation can be turned off", WBF.EventTriggers.Simulate("off") == false)
local after = WBF.EventTriggers.Active()
local stillFaire = false
for index = 1, #after do
    if after[index].eventKey == "darkmoon" then
        stillFaire = true
    end
end
check("turning simulation off leaves the calendar event", stillFaire == false and #after == 1)

-- Since you were last here reads the same relevance state as the notice.
use(2026, 10, 5, { holiday("Darkmoon Faire", 2026, 10, 4, 235448) })
WBF.ContextFyi.Save({
    type = "RECURRING",
    title = "Darkmoon Faire cleanup",
    trigger = { type = "WOW_EVENT", eventName = "Darkmoon Faire" },
    items = { { text = "Spend Darkmoon Prize Tickets" } },
})
local since = WBF.ContextFyi.SinceLastHere()
check("since you were last here names the returning event", since and since.lines[1] and since.lines[1].headline == "Darkmoon Faire has returned.")
check("since you were last here lists the saved fyi", since.lines[1].items[1] == "Spend Darkmoon Prize Tickets")

-- A simple note does not require a trigger.
local simple = WBF.Notebook.AddQuickNote("Remember that this vendor sells the transmog set.")
check("a simple note stays a reference", simple and simple.type == "REFERENCE" and simple.trigger == nil and simple.text == "Remember that this vendor sells the transmog set.")

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All context FYI checks passed")
