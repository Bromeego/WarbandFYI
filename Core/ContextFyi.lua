local _, WBF = ...

-- Recurring FYIs. The player decides what matters. This module remembers
-- it and says so again when the saved trigger is relevant.
-- Reference notes are never completed. Tasks complete once. Recurring
-- FYIs complete for one occurrence and return on the next one.
WBF.ContextFyi = {}

local MAX_FYIS = 80
local MAX_ITEMS = 12
local MAX_TITLE = 80
local MAX_NOTES = 800
local MAX_ITEM = 120
local MAX_HISTORY = 48
local MAX_HISTORY_EVENT = 6
local MAX_OCCURRENCES = 12
local MAX_NOTICES = 80
local MAX_LINES = 4

local TYPES = {
    REFERENCE = true,
    TASK = true,
    RECURRING = true,
}

local currencyReader = nil
local watch = nil
local noticeQueued = false

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Clip(value, max)
    value = Trim(value)
    if #value > max then
        value = value:sub(1, max)
    end
    return value
end

local function Now()
    return WBF.Time.Now()
end

local function Whole(value)
    local id = tonumber(value)
    if not id or id ~= math.floor(id) or id < 1 then
        return nil
    end
    return id
end

local function Say(text)
    print("|cffd4af37WarbandFYI|r " .. tostring(text))
end

function WBF.ContextFyi.UseCurrency(reader)
    if reader == nil or type(reader) == "function" then
        currencyReader = reader
    end
end

local function Notebook()
    if WBF.Database and WBF.Database.EnsureContextFyis and WBF.Database.Get then
        return WBF.Database.EnsureContextFyis(WBF.Database.Get())
    end
    return nil
end

local function Alloc(map, field, prefix)
    local db = WBF.Database.Get()
    local id = math.floor(tonumber(db.nextIds[field]) or 1)
    if id < 1 then
        id = 1
    end
    local key = prefix .. id
    while map[key] do
        id = id + 1
        key = prefix .. id
    end
    db.nextIds[field] = id + 1
    return key
end

local function AllocItem(notebook)
    local db = WBF.Database.Get()
    local id = math.floor(tonumber(db.nextIds.contextItem) or 1)
    if id < 1 then
        id = 1
    end
    local function taken(candidate)
        for _, entry in pairs(notebook.contextFyis) do
            if type(entry) == "table" and type(entry.items) == "table" then
                for index = 1, #entry.items do
                    local item = entry.items[index]
                    if type(item) == "table" and item.id == candidate then
                        return true
                    end
                end
            end
        end
        return false
    end
    local key = "i" .. id
    while taken(key) do
        id = id + 1
        key = "i" .. id
    end
    db.nextIds.contextItem = id + 1
    return key
end

local function CleanTrigger(trigger)
    if type(trigger) ~= "table" or type(trigger.type) ~= "string" or trigger.type == "" then
        return nil
    end
    if trigger.type == "WOW_EVENT" and WBF.EventTriggers and WBF.EventTriggers.Normalize then
        local normal = WBF.EventTriggers.Normalize(trigger)
        if normal then
            return normal
        end
    end
    if trigger.type == "WOW_EVENT" and type(trigger.eventKey) == "string" and trigger.eventKey ~= "" then
        return {
            type = "WOW_EVENT",
            eventKey = trigger.eventKey,
            eventName = type(trigger.eventName) == "string" and trigger.eventName or trigger.eventKey,
        }
    end
    if trigger.type ~= "WOW_EVENT" then
        return {
            type = trigger.type,
            eventKey = type(trigger.eventKey) == "string" and trigger.eventKey or nil,
            eventName = type(trigger.eventName) == "string" and trigger.eventName or nil,
        }
    end
    return nil
end

local function CleanItems(items, notebook, keepIds)
    local list = {}
    if type(items) ~= "table" then
        return list
    end
    local seen = {}
    for index = 1, #items do
        if #list >= MAX_ITEMS then
            break
        end
        local item = items[index]
        if type(item) == "table" then
            local text = Clip(item.text or "", MAX_ITEM)
            if text ~= "" then
                local id = type(item.id) == "string" and item.id or nil
                if not id or seen[id] or not keepIds then
                    id = AllocItem(notebook)
                end
                if not seen[id] then
                    seen[id] = true
                    local mode = item.completionMode == "PERMANENT" and "PERMANENT" or "OCCURRENCE"
                    list[#list + 1] = {
                        id = id,
                        text = text,
                        completionMode = mode,
                        achievementID = Whole(item.achievementID),
                        currencyID = Whole(item.currencyID),
                    }
                end
            end
        end
    end
    return list
end

local function CleanOccurrences(map)
    local fresh = {}
    if type(map) ~= "table" then
        return fresh
    end
    for key, row in pairs(map) do
        if type(key) == "string" and type(row) == "table" then
            local items = {}
            if type(row.items) == "table" then
                for itemId, at in pairs(row.items) do
                    if type(itemId) == "string" and type(at) == "number" then
                        items[itemId] = at
                    end
                end
            end
            fresh[key] = {
                completedAt = type(row.completedAt) == "number" and row.completedAt or nil,
                items = items,
            }
        end
    end
    return fresh
end

local function PruneOccurrences(map, keepKey)
    local rows = {}
    for key, row in pairs(map) do
        if key ~= keepKey then
            rows[#rows + 1] = { key = key, at = row.completedAt or 0 }
        end
    end
    if #rows <= MAX_OCCURRENCES then
        return
    end
    table.sort(rows, function(a, b)
        return a.at < b.at
    end)
    while #rows > MAX_OCCURRENCES do
        map[rows[1].key] = nil
        table.remove(rows, 1)
    end
end

local function CleanStampMap(map)
    local fresh = {}
    if type(map) ~= "table" then
        return fresh
    end
    for key, at in pairs(map) do
        if type(key) == "string" and type(at) == "number" then
            fresh[key] = at
        end
    end
    return fresh
end

local function Normalize(entry, notebook)
    if type(entry) ~= "table" then
        return nil
    end
    local kind = entry.type
    if not TYPES[kind] then
        kind = "REFERENCE"
    end
    entry.type = kind
    entry.title = Clip(entry.title or "", MAX_TITLE)
    entry.notes = Clip(entry.notes or "", MAX_NOTES)
    if entry.title == "" and entry.notes ~= "" then
        entry.title = Clip(entry.notes, MAX_TITLE)
    end
    if entry.title == "" then
        return nil
    end
    entry.trigger = CleanTrigger(entry.trigger)
    if entry.type ~= "RECURRING" then
        entry.trigger = nil
    end
    entry.repeatMode = entry.type == "RECURRING" and "EVERY_OCCURRENCE" or nil
    entry.items = CleanItems(entry.items, notebook, true)
    entry.achievementID = Whole(entry.achievementID)
    entry.currencyID = Whole(entry.currencyID)
    entry.completedAt = type(entry.completedAt) == "number" and entry.completedAt or nil
    entry.permanentAt = type(entry.permanentAt) == "number" and entry.permanentAt or nil
    entry.completedOccurrences = CleanOccurrences(entry.completedOccurrences)
    entry.permanentItems = CleanStampMap(entry.permanentItems)
    entry.createdAt = type(entry.createdAt) == "number" and entry.createdAt or Now()
    entry.updatedAt = type(entry.updatedAt) == "number" and entry.updatedAt or entry.createdAt
    return entry
end

function WBF.ContextFyi.Ensure()
    local notebook = Notebook()
    if not notebook then
        return nil
    end
    for index = 1, #notebook.contextFyiOrder do
        local id = notebook.contextFyiOrder[index]
        local entry = notebook.contextFyis[id]
        if type(entry) == "table" then
            entry.id = id
            if not Normalize(entry, notebook) then
                notebook.contextFyis[id] = nil
            end
        end
    end
    local fresh = {}
    for index = 1, #notebook.contextFyiOrder do
        local id = notebook.contextFyiOrder[index]
        if notebook.contextFyis[id] then
            fresh[#fresh + 1] = id
        end
    end
    notebook.contextFyiOrder = fresh
    return notebook
end

function WBF.ContextFyi.OnLoad()
    watch = nil
    noticeQueued = false
    if WBF.EventTriggers and WBF.EventTriggers.OnLoad then
        WBF.EventTriggers.OnLoad()
    end
    WBF.ContextFyi.Ensure()
end

function WBF.ContextFyi.NoticesEnabled()
    local db = WBF.Database.Get()
    return not (db and db.config and db.config.contextFyiNotices == false)
end

function WBF.ContextFyi.SetNoticesEnabled(value)
    local db = WBF.Database.Get()
    if not db then
        return false
    end
    if type(db.config) ~= "table" then
        db.config = {}
    end
    db.config.contextFyiNotices = value and true or false
    return db.config.contextFyiNotices
end

local function Refresh()
    if WBF.Notebook and WBF.Notebook.RefreshOpen then
        WBF.Notebook.RefreshOpen()
    end
end

function WBF.ContextFyi.Get(id)
    local notebook = WBF.ContextFyi.Ensure()
    if not notebook or type(id) ~= "string" then
        return nil
    end
    return notebook.contextFyis[id]
end

function WBF.ContextFyi.List()
    local notebook = WBF.ContextFyi.Ensure()
    local list = {}
    if not notebook then
        return list
    end
    for index = 1, #notebook.contextFyiOrder do
        local entry = notebook.contextFyis[notebook.contextFyiOrder[index]]
        if entry then
            list[#list + 1] = entry
        end
    end
    return list
end

local function Occurrence(entry)
    if not entry or not entry.trigger then
        return nil
    end
    return WBF.Triggers.GetOccurrenceKey(entry.trigger)
end

local function OccurrenceRow(entry, key, create)
    if not key then
        return nil
    end
    if type(entry.completedOccurrences) ~= "table" then
        entry.completedOccurrences = {}
    end
    local row = entry.completedOccurrences[key]
    if not row and create then
        row = { items = {} }
        entry.completedOccurrences[key] = row
    end
    if row and type(row.items) ~= "table" then
        row.items = {}
    end
    return row
end

local function ItemById(entry, itemId)
    local items = entry and entry.items or {}
    for index = 1, #items do
        if items[index].id == itemId then
            return items[index]
        end
    end
    return nil
end

function WBF.ContextFyi.ItemDone(entry, item, occurrenceKey)
    if type(entry) ~= "table" or type(item) ~= "table" then
        return false
    end
    if item.completionMode == "PERMANENT" then
        return type(entry.permanentItems) == "table" and entry.permanentItems[item.id] ~= nil
    end
    if not occurrenceKey then
        return false
    end
    local row = type(entry.completedOccurrences) == "table" and entry.completedOccurrences[occurrenceKey] or nil
    if not row then
        return false
    end
    if row.completedAt then
        return true
    end
    return type(row.items) == "table" and row.items[item.id] ~= nil
end

local function OccurrenceUnits(entry)
    local units = {}
    local items = entry.items or {}
    for index = 1, #items do
        if items[index].completionMode ~= "PERMANENT" then
            units[#units + 1] = items[index]
        end
    end
    if #units == 0 then
        units[1] = { id = entry.id, text = entry.title, whole = true }
    end
    return units
end

local function OccurrenceSettled(entry, occurrenceKey)
    if not occurrenceKey then
        return false
    end
    local row = type(entry.completedOccurrences) == "table" and entry.completedOccurrences[occurrenceKey] or nil
    if row and row.completedAt then
        return true
    end
    local units = OccurrenceUnits(entry)
    if units[1] and units[1].whole then
        return false
    end
    for index = 1, #units do
        if not WBF.ContextFyi.ItemDone(entry, units[index], occurrenceKey) then
            return false
        end
    end
    return #units > 0
end

local function MarkSettled(entry, occurrenceKey)
    if OccurrenceSettled(entry, occurrenceKey) then
        local row = OccurrenceRow(entry, occurrenceKey, true)
        if row and not row.completedAt then
            row.completedAt = Now()
            local units = OccurrenceUnits(entry)
            for index = 1, #units do
                if not units[index].whole and not row.items[units[index].id] then
                    row.items[units[index].id] = row.completedAt
                end
            end
        end
    end
end

function WBF.ContextFyi.IsActionable(entry)
    if type(entry) == "string" then
        entry = WBF.ContextFyi.Get(entry)
    end
    if type(entry) ~= "table" or entry.permanentAt then
        return false
    end
    if entry.type == "TASK" then
        return entry.completedAt == nil
    end
    if entry.type ~= "RECURRING" or not entry.trigger then
        return false
    end
    if not WBF.Triggers.IsActive(entry.trigger) then
        return false
    end
    local key = Occurrence(entry)
    if not key or OccurrenceSettled(entry, key) then
        return false
    end
    return true
end

function WBF.ContextFyi.State(id)
    local entry = type(id) == "table" and id or WBF.ContextFyi.Get(id)
    if not entry then
        return nil
    end
    local context = entry.trigger and WBF.Triggers.GetDisplayContext(entry.trigger) or nil
    local key = context and context.occurrenceKey or nil
    return {
        id = entry.id,
        type = entry.type,
        title = entry.title,
        triggerType = entry.trigger and entry.trigger.type or nil,
        triggerTarget = entry.trigger and (entry.trigger.eventKey or entry.trigger.eventName) or nil,
        active = WBF.ContextFyi.IsActionable(entry),
        occurrenceKey = key,
        completedThisOccurrence = key and OccurrenceSettled(entry, key) or false,
        permanent = entry.permanentAt ~= nil,
    }
end

local function DefaultCurrency(currencyID, startStamp)
    if not WBF.Resources or not WBF.Resources.ByCurrencyID then
        return nil
    end
    local definition = WBF.Resources.ByCurrencyID(currencyID)
    if type(definition) ~= "table" then
        return nil
    end
    local view = WBF.Resources.NotebookView and WBF.Resources.NotebookView(definition.key) or nil
    local amount = view and view.amount or nil
    local name = (view and view.name) or definition.name or definition.short
    local gained = nil
    if startStamp and WBF.Resources.Report then
        local report = WBF.Resources.Report(definition.key, startStamp, Now())
        local period = report and report.period or nil
        if type(period) == "table" and type(period.earned) == "number" and period.earned > 0 then
            gained = period.earned
        end
    end
    return {
        id = currencyID,
        key = definition.key,
        name = name,
        amount = amount,
        gained = gained,
    }
end

function WBF.ContextFyi.DescribeCurrency(currencyID, startStamp, eventName)
    currencyID = Whole(currencyID)
    if not currencyID then
        return nil
    end
    local described = nil
    if currencyReader then
        described = currencyReader(currencyID, startStamp, eventName)
    end
    if described == nil then
        described = DefaultCurrency(currencyID, startStamp)
    end
    if type(described) ~= "table" then
        return {
            id = currencyID,
            missing = true,
            name = "Currency " .. currencyID,
            amount = nil,
            gained = nil,
        }
    end
    described.id = described.id or currencyID
    described.missing = described.missing and true or false
    if type(described.name) ~= "string" or described.name == "" then
        described.name = "Currency " .. currencyID
    end
    if type(described.amount) ~= "number" then
        described.amount = nil
    end
    if type(described.gained) ~= "number" or described.gained <= 0 then
        described.gained = nil
    end
    described.eventName = eventName
    return described
end

function WBF.ContextFyi.DescribeAchievement(achievementID)
    achievementID = Whole(achievementID)
    if not achievementID then
        return nil
    end
    local progress = nil
    if WBF.PlanAchievements and WBF.PlanAchievements.Progress then
        local ok, result = pcall(WBF.PlanAchievements.Progress, achievementID)
        if ok then
            progress = result
        end
    end
    if type(progress) ~= "table" then
        return {
            id = achievementID,
            missing = true,
            name = "Achievement " .. achievementID,
            completed = false,
        }
    end
    local text = nil
    if WBF.PlanAchievements.ProgressText then
        text = WBF.PlanAchievements.ProgressText(progress)
    end
    return {
        id = achievementID,
        missing = false,
        name = progress.name or ("Achievement " .. achievementID),
        current = progress.current,
        required = progress.required,
        completed = progress.completed and true or false,
        text = text,
    }
end

local function PresentItem(entry, item, occurrenceKey, eventName, startStamp)
    return {
        id = item.id,
        text = item.text,
        completionMode = item.completionMode,
        done = WBF.ContextFyi.ItemDone(entry, item, occurrenceKey),
        achievement = WBF.ContextFyi.DescribeAchievement(item.achievementID),
        currency = WBF.ContextFyi.DescribeCurrency(item.currencyID, startStamp, eventName),
    }
end

local function PresentEntry(entry, context)
    local key = context and context.occurrenceKey or nil
    local items = {}
    for index = 1, #(entry.items or {}) do
        items[index] = PresentItem(entry, entry.items[index], key, context and context.eventName or nil, context and context.startStamp or nil)
    end
    local openLines = {}
    if entry.type == "RECURRING" and not entry.permanentAt then
        local units = OccurrenceUnits(entry)
        for index = 1, #units do
            local unit = units[index]
            if not WBF.ContextFyi.ItemDone(entry, unit, key) then
                openLines[#openLines + 1] = unit.text
            end
        end
    elseif entry.type == "TASK" and not entry.completedAt and not entry.permanentAt then
        openLines[1] = entry.title
    end
    return {
        id = entry.id,
        type = entry.type,
        title = entry.title,
        notes = entry.notes,
        active = WBF.ContextFyi.IsActionable(entry),
        permanent = entry.permanentAt ~= nil,
        occurrenceKey = key,
        doneForOccurrence = key and OccurrenceSettled(entry, key) or false,
        items = items,
        openLines = openLines,
        achievement = WBF.ContextFyi.DescribeAchievement(entry.achievementID),
        currency = WBF.ContextFyi.DescribeCurrency(entry.currencyID, context and context.startStamp or nil, context and context.eventName or nil),
    }
end

local function HistoryRows()
    local notebook = Notebook()
    if not notebook then
        return nil
    end
    return notebook.fyiHistory
end

local function PruneHistory(rows)
    local perEvent = {}
    for index = #rows, 1, -1 do
        local row = rows[index]
        local key = row.eventKey or ""
        perEvent[key] = (perEvent[key] or 0) + 1
        if perEvent[key] > MAX_HISTORY_EVENT then
            table.remove(rows, index)
        end
    end
    while #rows > MAX_HISTORY do
        table.remove(rows, 1)
    end
end

function WBF.ContextFyi.RememberHistory(eventKey, occurrenceKey, label, completed, total)
    if type(eventKey) ~= "string" or type(occurrenceKey) ~= "string" then
        return nil
    end
    completed = math.max(0, math.floor(tonumber(completed) or 0))
    total = math.max(0, math.floor(tonumber(total) or 0))
    if total < 1 then
        return nil
    end
    if completed > total then
        completed = total
    end
    local rows = HistoryRows()
    if not rows then
        return nil
    end
    local found = nil
    for index = 1, #rows do
        if rows[index].occurrenceKey == occurrenceKey then
            found = rows[index]
            break
        end
    end
    if not found then
        found = { occurrenceKey = occurrenceKey }
        rows[#rows + 1] = found
    end
    found.eventKey = eventKey
    found.label = type(label) == "string" and label or found.label
    found.completed = completed
    found.total = total
    found.unfinished = total - completed
    found.at = Now()
    PruneHistory(rows)
    return found
end

local function HistoryFor(eventKey, exceptKey)
    local rows = HistoryRows() or {}
    local found = nil
    for index = 1, #rows do
        local row = rows[index]
        if row.eventKey == eventKey and row.occurrenceKey ~= exceptKey then
            if not found or (row.at or 0) >= (found.at or 0) then
                found = row
            end
        end
    end
    return found
end

local function Tally(eventKey, occurrenceKey)
    local completed, total = 0, 0
    local list = WBF.ContextFyi.List()
    for index = 1, #list do
        local entry = list[index]
        if entry.type == "RECURRING" and not entry.permanentAt and entry.trigger and entry.trigger.eventKey == eventKey then
            local units = OccurrenceUnits(entry)
            for unitIndex = 1, #units do
                total = total + 1
                if WBF.ContextFyi.ItemDone(entry, units[unitIndex], occurrenceKey) then
                    completed = completed + 1
                end
            end
        end
    end
    return completed, total
end

local function Snapshot(eventKey, context)
    if not context or not context.occurrenceKey then
        return
    end
    local completed, total = Tally(eventKey, context.occurrenceKey)
    WBF.ContextFyi.RememberHistory(eventKey, context.occurrenceKey, context.label, completed, total)
end

function WBF.ContextFyi.Relevance()
    local events = {}
    local byKey = {}
    local active = WBF.EventTriggers and WBF.EventTriggers.Active and WBF.EventTriggers.Active() or {}
    for index = 1, #active do
        local event = active[index]
        local group = {
            eventKey = event.eventKey,
            eventName = event.eventName,
            occurrenceKey = event.occurrenceKey,
            label = event.label,
            startStamp = event.startStamp,
            endStamp = event.endStamp,
            simulated = event.simulated and true or false,
            fyis = {},
            lines = {},
            count = 0,
        }
        events[#events + 1] = group
        byKey[event.eventKey] = group
    end
    local tasks = {}
    local list = WBF.ContextFyi.List()
    for index = 1, #list do
        local entry = list[index]
        if entry.type == "TASK" and WBF.ContextFyi.IsActionable(entry) then
            tasks[#tasks + 1] = PresentEntry(entry, nil)
        elseif entry.trigger and entry.trigger.type == "WOW_EVENT" and not entry.permanentAt then
            local group = byKey[entry.trigger.eventKey]
            if group and (entry.type == "RECURRING" or entry.type == "REFERENCE") then
                local context = {
                    eventName = group.eventName,
                    occurrenceKey = group.occurrenceKey,
                    startStamp = group.startStamp,
                    label = group.label,
                }
                local view = PresentEntry(entry, context)
                group.fyis[#group.fyis + 1] = view
                if entry.type == "RECURRING" then
                    for lineIndex = 1, #view.openLines do
                        if #group.lines < MAX_LINES then
                            group.lines[#group.lines + 1] = view.openLines[lineIndex]
                        end
                        group.count = group.count + 1
                    end
                end
            end
        end
    end
    local visible = {}
    for index = 1, #events do
        local group = events[index]
        if #group.fyis > 0 then
            group.last = HistoryFor(group.eventKey, group.occurrenceKey)
            visible[#visible + 1] = group
        end
    end
    return { events = visible, tasks = tasks }
end

function WBF.ContextFyi.SinceLastHere()
    local relevance = WBF.ContextFyi.Relevance()
    local lines = {}
    for index = 1, #relevance.events do
        local group = relevance.events[index]
        if group.count > 0 then
            lines[#lines + 1] = {
                eventKey = group.eventKey,
                eventName = group.eventName,
                headline = group.eventName .. " has returned.",
                detail = "You left yourself " .. group.count .. (group.count == 1 and " FYI." or " FYIs."),
                items = group.lines,
                last = group.last,
                occurrenceKey = group.occurrenceKey,
            }
        end
    end
    return { lines = lines, events = relevance.events }
end

function WBF.ContextFyi.Focus(eventKey)
    local relevance = WBF.ContextFyi.Relevance()
    for index = 1, #relevance.events do
        if relevance.events[index].eventKey == eventKey then
            return relevance.events[index]
        end
    end
    return nil
end

local function NoticeStore()
    local notebook = Notebook()
    if not notebook then
        return nil
    end
    return notebook.fyiNotice
end

local function Signature(groups)
    local parts = {}
    for index = 1, #groups do
        local group = groups[index]
        local ids = {}
        for fyiIndex = 1, #group.fyis do
            local fyi = group.fyis[fyiIndex]
            if fyi.type == "RECURRING" and fyi.active then
                ids[#ids + 1] = fyi.id
            end
        end
        table.sort(ids)
        parts[#parts + 1] = (group.occurrenceKey or "") .. "|" .. table.concat(ids, ",")
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

local function PruneNotices(seen)
    local rows = {}
    for key, row in pairs(seen) do
        rows[#rows + 1] = { key = key, at = type(row) == "table" and row.at or 0 }
    end
    if #rows <= MAX_NOTICES then
        return
    end
    table.sort(rows, function(a, b)
        return a.at < b.at
    end)
    while #rows > MAX_NOTICES do
        seen[rows[1].key] = nil
        table.remove(rows, 1)
    end
end

function WBF.ContextFyi.ConsiderNotice()
    if not WBF.ContextFyi.NoticesEnabled() then
        return nil
    end
    local store = NoticeStore()
    if not store then
        return nil
    end
    local relevance = WBF.ContextFyi.Relevance()
    local groups = {}
    for index = 1, #relevance.events do
        if relevance.events[index].count > 0 then
            groups[#groups + 1] = relevance.events[index]
        end
    end
    if #groups == 0 then
        return nil
    end
    local signature = Signature(groups)
    if signature == "" or store.seen[signature] then
        return nil
    end
    return {
        signature = signature,
        primary = groups[1],
        groups = groups,
    }
end

function WBF.ContextFyi.NotePresented(signature)
    local store = NoticeStore()
    if not store or type(signature) ~= "string" or signature == "" then
        return false
    end
    local row = store.seen[signature]
    if type(row) ~= "table" then
        row = {}
    end
    row.at = Now()
    if row.acknowledged == nil then
        row.acknowledged = false
    end
    store.seen[signature] = row
    PruneNotices(store.seen)
    return true
end

function WBF.ContextFyi.Acknowledge(signature)
    local store = NoticeStore()
    if not store or type(signature) ~= "string" or signature == "" then
        return false
    end
    store.seen[signature] = {
        at = Now(),
        acknowledged = true,
    }
    PruneNotices(store.seen)
    return true
end

local function DeliverNotice()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        noticeQueued = true
        return
    end
    noticeQueued = false
    local notice = WBF.ContextFyi.ConsiderNotice()
    if not notice then
        return
    end
    local ui = WBF.UI and WBF.UI.ContextFyi or nil
    if not ui or type(ui.ShowNotice) ~= "function" then
        return
    end
    local shown = ui.ShowNotice(notice)
    if shown ~= false then
        WBF.ContextFyi.NotePresented(notice.signature)
    end
end

function WBF.ContextFyi.OnRegen()
    if noticeQueued then
        DeliverNotice()
    end
end

function WBF.ContextFyi.OnEventsChanged()
    local relevance = WBF.ContextFyi.Relevance()
    local parts = {}
    for index = 1, #relevance.events do
        local group = relevance.events[index]
        parts[#parts + 1] = (group.occurrenceKey or "") .. ":" .. tostring(group.count)
        Snapshot(group.eventKey, group)
    end
    table.sort(parts)
    local signature = table.concat(parts, "|")
    if signature == watch then
        return
    end
    watch = signature
    DeliverNotice()
    Refresh()
end

local function TouchHistory(entry)
    if not entry or not entry.trigger or entry.trigger.type ~= "WOW_EVENT" then
        return
    end
    local context = WBF.Triggers.GetDisplayContext(entry.trigger)
    if context and context.active then
        Snapshot(entry.trigger.eventKey, context)
    end
end

function WBF.ContextFyi.Save(draft)
    local notebook = WBF.ContextFyi.Ensure()
    if not notebook or type(draft) ~= "table" then
        return nil
    end
    local kind = draft.type
    if not TYPES[kind] then
        kind = "REFERENCE"
    end
    local title = Clip(draft.title or "", MAX_TITLE)
    local notes = Clip(draft.notes or draft.text or "", MAX_NOTES)
    if title == "" then
        title = Clip(notes, MAX_TITLE)
    end
    if title == "" then
        return nil
    end
    local trigger = nil
    if kind == "RECURRING" then
        trigger = CleanTrigger(draft.trigger)
        if not trigger or trigger.type ~= "WOW_EVENT" then
            return nil
        end
    end
    local entry = nil
    if type(draft.id) == "string" then
        entry = notebook.contextFyis[draft.id]
    end
    local now = Now()
    if not entry then
        if #notebook.contextFyiOrder >= MAX_FYIS then
            return nil
        end
        local id = Alloc(notebook.contextFyis, "contextFyi", "y")
        entry = {
            id = id,
            createdAt = now,
            completedOccurrences = {},
            permanentItems = {},
        }
        notebook.contextFyis[id] = entry
        notebook.contextFyiOrder[#notebook.contextFyiOrder + 1] = id
    end
    entry.type = kind
    entry.title = title
    entry.notes = notes
    entry.trigger = trigger
    entry.repeatMode = kind == "RECURRING" and "EVERY_OCCURRENCE" or nil
    entry.items = CleanItems(draft.items, notebook, true)
    entry.achievementID = Whole(draft.achievementID)
    entry.currencyID = Whole(draft.currencyID)
    entry.updatedAt = now
    if not Normalize(entry, notebook) then
        return nil
    end
    Refresh()
    return entry
end

function WBF.ContextFyi.Delete(id)
    local notebook = WBF.ContextFyi.Ensure()
    if not notebook or not notebook.contextFyis[id] then
        return false
    end
    notebook.contextFyis[id] = nil
    local fresh = {}
    for index = 1, #notebook.contextFyiOrder do
        if notebook.contextFyiOrder[index] ~= id then
            fresh[#fresh + 1] = notebook.contextFyiOrder[index]
        end
    end
    notebook.contextFyiOrder = fresh
    Refresh()
    return true
end

function WBF.ContextFyi.SetItemDone(id, itemId, done)
    local entry = WBF.ContextFyi.Get(id)
    local item = entry and ItemById(entry, itemId) or nil
    if not item or entry.permanentAt then
        return nil
    end
    local now = Now()
    if item.completionMode == "PERMANENT" then
        if done then
            entry.permanentItems[itemId] = now
        else
            entry.permanentItems[itemId] = nil
        end
    else
        local key = Occurrence(entry)
        if not key then
            return nil
        end
        local row = OccurrenceRow(entry, key, true)
        if done then
            row.items[itemId] = now
            MarkSettled(entry, key)
        else
            row.items[itemId] = nil
            row.completedAt = nil
        end
        PruneOccurrences(entry.completedOccurrences, key)
    end
    entry.updatedAt = now
    TouchHistory(entry)
    Refresh()
    return entry
end

function WBF.ContextFyi.CompleteOccurrence(id)
    local entry = WBF.ContextFyi.Get(id)
    if not entry or entry.type ~= "RECURRING" or entry.permanentAt then
        return nil
    end
    local key = Occurrence(entry)
    if not key then
        return nil
    end
    local now = Now()
    local row = OccurrenceRow(entry, key, true)
    row.completedAt = now
    local units = OccurrenceUnits(entry)
    for index = 1, #units do
        if not units[index].whole then
            row.items[units[index].id] = row.items[units[index].id] or now
        end
    end
    PruneOccurrences(entry.completedOccurrences, key)
    entry.updatedAt = now
    TouchHistory(entry)
    Refresh()
    return entry
end

function WBF.ContextFyi.CompletePermanent(id)
    local entry = WBF.ContextFyi.Get(id)
    if not entry or entry.permanentAt then
        return entry
    end
    local now = Now()
    entry.permanentAt = now
    if entry.type == "TASK" then
        entry.completedAt = entry.completedAt or now
    end
    entry.updatedAt = now
    Refresh()
    return entry
end

function WBF.ContextFyi.CompleteTask(id)
    local entry = WBF.ContextFyi.Get(id)
    if not entry or entry.type ~= "TASK" then
        return nil
    end
    entry.completedAt = Now()
    entry.updatedAt = entry.completedAt
    Refresh()
    return entry
end

function WBF.ContextFyi.Summaries()
    local list = WBF.ContextFyi.List()
    local rows = {}
    for index = 1, #list do
        local entry = list[index]
        local state = WBF.ContextFyi.State(entry)
        local detail = nil
        if entry.permanentAt then
            detail = "Completed"
        elseif entry.type == "RECURRING" then
            if state and state.active then
                detail = "Active now"
            elseif entry.trigger and entry.trigger.eventName then
                detail = "When " .. entry.trigger.eventName .. " is active"
            end
        elseif entry.type == "TASK" then
            detail = entry.completedAt and "Completed" or "Task"
        else
            detail = "Reference"
        end
        rows[#rows + 1] = {
            id = entry.id,
            title = entry.title,
            type = entry.type,
            active = state and state.active or false,
            permanent = entry.permanentAt ~= nil,
            eventName = entry.trigger and entry.trigger.eventName or nil,
            eventKey = entry.trigger and entry.trigger.eventKey or nil,
            detail = detail,
        }
    end
    return rows
end

function WBF.ContextFyi.Debug()
    local list = WBF.ContextFyi.List()
    if #list == 0 then
        Say("No FYIs.")
        return
    end
    for index = 1, #list do
        local state = WBF.ContextFyi.State(list[index])
        Say(string.format(
            "%s  %s  %s  %s  %s  %s  occurrence %s  permanent %s",
            state.id,
            state.type,
            state.triggerType or "-",
            state.triggerTarget or "-",
            state.active and "active" or "inactive",
            state.occurrenceKey or "-",
            state.completedThisOccurrence and "yes" or "no",
            state.permanent and "yes" or "no"
        ))
    end
end

function WBF.ContextFyi.Register(bus)
    if WBF.EventTriggers and WBF.EventTriggers.Register then
        WBF.EventTriggers.Register(bus)
    end
end
