local _, WBF = ...

-- Reminders the player asked WarbandFYI to hold. Not a task manager:
-- no priorities, no dependencies, and unsorted notes are a finished state.
WBF.Plans = {}

local DAY = 86400
local WEEK = 7 * DAY
local MAX_TEXT = 400
local MAX_NAME = 80
local refreshing = false

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Now()
    return WBF.Time.Now()
end

local function Say(text)
    print("|cffd4af37WarbandFYI|r " .. text)
end

function WBF.Plans.Root()
    if not WBF.Database or not WBF.Database.Get then
        return nil
    end
    return WBF.Database.EnsurePlans(WBF.Database.Get())
end

function WBF.Plans.RefreshOpen()
    if refreshing then
        return
    end
    local frame = WBF.UI and WBF.UI.frame
    if not frame or not frame.Refresh or not frame.IsShown or not frame:IsShown() then
        return
    end
    refreshing = true
    local ok, err = pcall(frame.Refresh, frame, false)
    refreshing = false
    if not ok and WBF.Debug and WBF.Debug.Log then
        WBF.Debug.Log("Plans refresh failed", err)
    end
end

local function Changed(entry)
    if entry then
        entry.updatedAt = Now()
    end
    WBF.Plans.RefreshOpen()
    return entry
end

local function Alloc(kind)
    local root = WBF.Plans.Root()
    local db = WBF.Database.Get()
    local field = kind == "group" and "planGroup" or "planEntry"
    local prefix = kind == "group" and "g" or "e"
    local map = kind == "group" and root.groups or root.entries
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

function WBF.Plans.Get(id)
    local root = WBF.Plans.Root()
    if not root or type(id) ~= "string" then
        return nil
    end
    local entry = root.entries[id]
    if type(entry) ~= "table" then
        return nil
    end
    return entry
end

function WBF.Plans.GetGroup(id)
    local root = WBF.Plans.Root()
    if not root or type(id) ~= "string" then
        return nil
    end
    local group = root.groups[id]
    if type(group) ~= "table" then
        return nil
    end
    return group
end

local function CleanPlanID(planID)
    if type(planID) ~= "string" or planID == "" then
        return nil
    end
    if WBF.Plans.GetGroup(planID) then
        return planID
    end
    return nil
end

local function AsAchievementID(value)
    local id = tonumber(value)
    if not id or id ~= math.floor(id) or id < 1 or id > 10000000 then
        return nil
    end
    return id
end

function WBF.Plans.Entries()
    local root = WBF.Plans.Root()
    local list = {}
    if not root then
        return list
    end
    for _, entry in pairs(root.entries) do
        if type(entry) == "table" and type(entry.id) == "string" then
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b)
        if a.createdAt == b.createdAt then
            return a.id < b.id
        end
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)
    return list
end

function WBF.Plans.Groups()
    local root = WBF.Plans.Root()
    local list = {}
    if not root then
        return list
    end
    for _, group in pairs(root.groups) do
        if type(group) == "table" and type(group.id) == "string" then
            list[#list + 1] = group
        end
    end
    table.sort(list, function(a, b)
        if a.createdAt == b.createdAt then
            return a.id < b.id
        end
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)
    return list
end

function WBF.Plans.FindAchievement(achievementID)
    achievementID = AsAchievementID(achievementID)
    local root = WBF.Plans.Root()
    if not achievementID or not root then
        return nil
    end
    local archived = nil
    for _, entry in pairs(root.entries) do
        if type(entry) == "table" and entry.type == "achievement" and entry.achievementID == achievementID then
            if entry.status ~= "archived" then
                return entry
            end
            archived = archived or entry
        end
    end
    return archived
end

function WBF.Plans.HasAchievement()
    local root = WBF.Plans.Root()
    if not root then
        return false
    end
    for _, entry in pairs(root.entries) do
        if type(entry) == "table" and entry.type == "achievement" and entry.status ~= "archived" then
            return true
        end
    end
    return false
end

function WBF.Plans.Add(partial)
    local root = WBF.Plans.Root()
    if not root or type(partial) ~= "table" then
        return nil
    end
    local kind = partial.type or "note"
    if kind ~= "note" and kind ~= "task" and kind ~= "recurring" and kind ~= "achievement" then
        return nil
    end
    local text = Trim(partial.text or "")
    local achievementID = nil
    if kind == "achievement" then
        achievementID = AsAchievementID(partial.achievementID)
        if not achievementID then
            return nil
        end
        text = nil
    elseif text == "" then
        return nil
    else
        if #text > MAX_TEXT then
            text = text:sub(1, MAX_TEXT)
        end
    end

    local now = Now()
    local entry = {
        id = Alloc("entry"),
        type = kind,
        text = text,
        achievementID = achievementID,
        status = "active",
        recurring = nil,
        planID = CleanPlanID(partial.planID),
        scope = "warband",
        character = type(partial.character) == "string" and partial.character ~= "" and partial.character or nil,
        expansion = type(partial.expansion) == "string" and Trim(partial.expansion) ~= "" and Trim(partial.expansion) or nil,
        zone = type(partial.zone) == "string" and Trim(partial.zone) ~= "" and Trim(partial.zone) or nil,
        category = type(partial.category) == "string" and Trim(partial.category) ~= "" and Trim(partial.category) or nil,
        createdAt = now,
        updatedAt = now,
        completedAt = nil,
    }
    if kind == "recurring" then
        local preset = partial.recurring and partial.recurring.preset or "weekly"
        if preset ~= "daily" and preset ~= "weekly" and preset ~= "custom" then
            preset = "weekly"
        end
        entry.recurring = { preset = preset }
        if preset == "custom" then
            local days = math.floor(tonumber(partial.recurring and partial.recurring.intervalDays) or 7)
            if days < 1 then
                days = 1
            elseif days > 365 then
                days = 365
            end
            entry.recurring.intervalDays = days
        end
    end
    root.entries[entry.id] = entry
    return Changed(entry)
end

function WBF.Plans.AddAchievement(achievementID, extra)
    extra = extra or {}
    achievementID = AsAchievementID(achievementID)
    if not achievementID then
        return nil, "invalid"
    end
    if WBF.PlanAchievements and WBF.PlanAchievements.IsTrackable and not WBF.PlanAchievements.IsTrackable(achievementID) then
        return nil, "invalid"
    end
    local existing = WBF.Plans.FindAchievement(achievementID)
    if existing then
        if existing.status == "archived" then
            existing.archivedFrom = nil
            existing.status = "active"
            local planID = CleanPlanID(extra.planID)
            if planID then
                existing.planID = planID
            end
            return Changed(existing), "restored"
        end
        return existing, "exists"
    end
    local entry = WBF.Plans.Add({
        type = "achievement",
        achievementID = achievementID,
        planID = extra.planID,
        character = extra.character,
        expansion = extra.expansion,
        zone = extra.zone,
        category = extra.category,
    })
    if not entry then
        return nil, "invalid"
    end
    return entry, "added"
end

function WBF.Plans.SetText(id, text)
    local entry = WBF.Plans.Get(id)
    if not entry or entry.type == "achievement" then
        return nil
    end
    text = Trim(text)
    if text == "" then
        return nil, "empty"
    end
    if #text > MAX_TEXT then
        text = text:sub(1, MAX_TEXT)
    end
    if entry.text == text then
        return entry
    end
    entry.text = text
    return Changed(entry)
end

local META = {
    character = true,
    expansion = true,
    zone = true,
    category = true,
}

function WBF.Plans.SetMeta(id, meta)
    local entry = WBF.Plans.Get(id)
    if not entry or type(meta) ~= "table" then
        return nil
    end
    local touched = false
    for key in pairs(META) do
        if meta[key] ~= nil then
            local value = meta[key]
            if value == false or value == "" then
                if entry[key] ~= nil then
                    entry[key] = nil
                    touched = true
                end
            elseif type(value) == "string" then
                value = Trim(value)
                if value == "" then
                    if entry[key] ~= nil then
                        entry[key] = nil
                        touched = true
                    end
                elseif entry[key] ~= value then
                    entry[key] = value
                    touched = true
                end
            end
        end
    end
    if not touched then
        return entry
    end
    return Changed(entry)
end

function WBF.Plans.Archive(id)
    local entry = WBF.Plans.Get(id)
    if not entry or entry.status == "archived" then
        return entry
    end
    entry.archivedFrom = entry.status
    entry.status = "archived"
    return Changed(entry)
end

function WBF.Plans.Restore(id)
    local entry = WBF.Plans.Get(id)
    if not entry or entry.status ~= "archived" then
        return entry
    end
    local previous = entry.archivedFrom
    entry.archivedFrom = nil
    if entry.type == "task" and previous == "completed" then
        entry.status = "completed"
    else
        entry.status = "active"
    end
    return Changed(entry)
end

function WBF.Plans.Delete(id)
    local root = WBF.Plans.Root()
    local entry = WBF.Plans.Get(id)
    if not root or not entry then
        return false
    end
    root.entries[id] = nil
    Changed(nil)
    return true
end

function WBF.Plans.ToggleComplete(id, now)
    local entry = WBF.Plans.Get(id)
    if not entry or entry.type == "note" or entry.type == "achievement" or entry.status == "archived" then
        return entry
    end
    now = now or Now()
    if entry.type == "recurring" then
        local cycle = WBF.Plans.Cycle(entry, now)
        if cycle.done then
            entry.completedAt = nil
        else
            entry.completedAt = now
        end
    elseif entry.status == "completed" then
        entry.status = "active"
        entry.completedAt = nil
    else
        entry.status = "completed"
        entry.completedAt = now
    end
    return Changed(entry)
end

function WBF.Plans.ConvertToTask(id)
    local entry = WBF.Plans.Get(id)
    if not entry or entry.type == "achievement" then
        return nil
    end
    entry.type = "task"
    entry.recurring = nil
    if entry.status ~= "archived" and entry.status ~= "completed" then
        entry.status = "active"
    end
    return Changed(entry)
end

function WBF.Plans.SetRecurring(id, preset, intervalDays)
    local entry = WBF.Plans.Get(id)
    if not entry or entry.type == "achievement" then
        return nil
    end
    if preset == "once" or preset == nil then
        if entry.type == "recurring" then
            entry.type = "task"
        end
        entry.recurring = nil
        if entry.status ~= "archived" then
            entry.status = "active"
        end
        return Changed(entry)
    end
    if preset ~= "daily" and preset ~= "weekly" and preset ~= "custom" then
        return nil
    end
    entry.type = "recurring"
    if entry.status ~= "archived" then
        entry.status = "active"
    end
    entry.recurring = { preset = preset }
    if preset == "custom" then
        local days = math.floor(tonumber(intervalDays) or 0)
        if days < 1 then
            days = 1
        elseif days > 365 then
            days = 365
        end
        entry.recurring.intervalDays = days
    end
    return Changed(entry)
end

function WBF.Plans.LinkAchievement(id, achievementID)
    local entry = WBF.Plans.Get(id)
    achievementID = AsAchievementID(achievementID)
    if not entry or not achievementID then
        return nil, "invalid"
    end
    if WBF.PlanAchievements and WBF.PlanAchievements.IsTrackable and not WBF.PlanAchievements.IsTrackable(achievementID) then
        return nil, "invalid"
    end
    local existing = WBF.Plans.FindAchievement(achievementID)
    if existing and existing.id ~= id then
        if existing.status ~= "archived" then
            return existing, "exists"
        end
        local root = WBF.Plans.Root()
        if root then
            root.entries[existing.id] = nil
        end
    end
    entry.type = "achievement"
    entry.achievementID = achievementID
    entry.text = nil
    entry.recurring = nil
    if entry.status ~= "archived" then
        entry.status = "active"
    end
    entry.completedAt = nil
    return Changed(entry), "linked"
end

function WBF.Plans.AssignPlan(id, planID)
    local entry = WBF.Plans.Get(id)
    if not entry then
        return nil
    end
    if planID == nil or planID == false or planID == "" then
        if entry.planID == nil then
            return entry
        end
        entry.planID = nil
        return Changed(entry)
    end
    planID = CleanPlanID(planID)
    if not planID then
        return nil
    end
    if entry.planID == planID then
        return entry
    end
    entry.planID = planID
    return Changed(entry)
end

function WBF.Plans.CreateGroup(name, description)
    local root = WBF.Plans.Root()
    if not root then
        return nil
    end
    name = Trim(name)
    if name == "" then
        return nil
    end
    if #name > MAX_NAME then
        name = name:sub(1, MAX_NAME)
    end
    description = Trim(description or "")
    if #description > MAX_TEXT then
        description = description:sub(1, MAX_TEXT)
    end
    local now = Now()
    local group = {
        id = Alloc("group"),
        name = name,
        description = description ~= "" and description or nil,
        status = "active",
        createdAt = now,
        updatedAt = now,
    }
    root.groups[group.id] = group
    return Changed(group)
end

function WBF.Plans.RenameGroup(id, name)
    local group = WBF.Plans.GetGroup(id)
    if not group then
        return nil
    end
    name = Trim(name)
    if name == "" then
        return nil
    end
    if #name > MAX_NAME then
        name = name:sub(1, MAX_NAME)
    end
    if group.name == name then
        return group
    end
    group.name = name
    return Changed(group)
end

function WBF.Plans.SetGroupDescription(id, description)
    local group = WBF.Plans.GetGroup(id)
    if not group then
        return nil
    end
    description = Trim(description or "")
    if #description > MAX_TEXT then
        description = description:sub(1, MAX_TEXT)
    end
    local stored = description ~= "" and description or nil
    if group.description == stored then
        return group
    end
    group.description = stored
    return Changed(group)
end

function WBF.Plans.ArchiveGroup(id)
    local group = WBF.Plans.GetGroup(id)
    if not group or group.status == "archived" then
        return group
    end
    group.status = "archived"
    return Changed(group)
end

function WBF.Plans.RestoreGroup(id)
    local group = WBF.Plans.GetGroup(id)
    if not group or group.status ~= "archived" then
        return group
    end
    group.status = "active"
    return Changed(group)
end

function WBF.Plans.DeleteGroup(id)
    local root = WBF.Plans.Root()
    local group = WBF.Plans.GetGroup(id)
    if not root or not group then
        return false
    end
    root.groups[id] = nil
    for _, entry in pairs(root.entries) do
        if type(entry) == "table" and entry.planID == id then
            entry.planID = nil
            entry.updatedAt = Now()
        end
    end
    Changed(nil)
    return true
end

function WBF.Plans.InPlan(planID)
    local list = {}
    if type(planID) ~= "string" then
        return list
    end
    local entries = WBF.Plans.Entries()
    for index = 1, #entries do
        local entry = entries[index]
        if entry.planID == planID and entry.status ~= "archived" then
            list[#list + 1] = entry
        end
    end
    return list
end

-- Clock is replaceable in tests. Live values come from the Retail reset APIs.
WBF.Plans.Clock = {}

function WBF.Plans.Clock.WeeklyStart(now)
    now = now or Now()
    if C_DateAndTime and C_DateAndTime.GetWeeklyResetStartTime then
        local startAt = WBF.Format.AsNumber(WBF.Format.SafeCall(C_DateAndTime.GetWeeklyResetStartTime))
        if startAt and startAt > 0 and startAt <= now + 120 then
            return startAt
        end
    end
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local seconds = WBF.Format.AsNumber(WBF.Format.SafeCall(C_DateAndTime.GetSecondsUntilWeeklyReset))
        if seconds and seconds >= 0 and seconds <= 8 * DAY then
            return now + seconds - WEEK
        end
    end
    return nil
end

function WBF.Plans.Clock.WeeklyNext(now)
    now = now or Now()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local seconds = WBF.Format.AsNumber(WBF.Format.SafeCall(C_DateAndTime.GetSecondsUntilWeeklyReset))
        if seconds and seconds >= 0 and seconds <= 8 * DAY then
            return now + seconds
        end
    end
    local startAt = WBF.Plans.Clock.WeeklyStart(now)
    if startAt then
        return startAt + WEEK
    end
    return nil
end

function WBF.Plans.Clock.DailyStart(now)
    now = now or Now()
    local seconds = nil
    if GetQuestResetTime then
        seconds = WBF.Format.AsNumber(WBF.Format.SafeCall(GetQuestResetTime))
    end
    if (not seconds or seconds < 0 or seconds > 2 * DAY) and C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        seconds = WBF.Format.AsNumber(WBF.Format.SafeCall(C_DateAndTime.GetSecondsUntilDailyReset))
    end
    if seconds and seconds >= 0 and seconds <= 2 * DAY then
        return now + seconds - DAY
    end
    return nil
end

function WBF.Plans.Clock.DailyNext(now)
    now = now or Now()
    local seconds = nil
    if GetQuestResetTime then
        seconds = WBF.Format.AsNumber(WBF.Format.SafeCall(GetQuestResetTime))
    end
    if (not seconds or seconds < 0 or seconds > 2 * DAY) and C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        seconds = WBF.Format.AsNumber(WBF.Format.SafeCall(C_DateAndTime.GetSecondsUntilDailyReset))
    end
    if seconds and seconds >= 0 and seconds <= 2 * DAY then
        return now + seconds
    end
    local startAt = WBF.Plans.Clock.DailyStart(now)
    if startAt then
        return startAt + DAY
    end
    return nil
end

function WBF.Plans.Cycle(entry, now)
    now = now or Now()
    local recurring = type(entry) == "table" and entry.recurring or nil
    local preset = recurring and recurring.preset or "weekly"
    if preset == "custom" then
        local days = math.floor(tonumber(recurring and recurring.intervalDays) or 1)
        if days < 1 then
            days = 1
        end
        if not entry.completedAt then
            return { done = false, nextAt = nil, preset = preset }
        end
        local nextAt = entry.completedAt + days * DAY
        return { done = now < nextAt, nextAt = nextAt, preset = preset }
    end

    local startAt
    local nextAt
    if preset == "daily" then
        startAt = WBF.Plans.Clock.DailyStart(now)
        nextAt = WBF.Plans.Clock.DailyNext(now)
    else
        preset = "weekly"
        startAt = WBF.Plans.Clock.WeeklyStart(now)
        nextAt = WBF.Plans.Clock.WeeklyNext(now)
    end
    if not startAt then
        local span = preset == "daily" and DAY or WEEK
        if entry.completedAt then
            local fallbackNext = entry.completedAt + span
            return {
                done = now < fallbackNext,
                nextAt = fallbackNext,
                preset = preset,
                fallback = true,
            }
        end
        return { done = false, nextAt = nil, preset = preset, fallback = true }
    end
    if not nextAt or nextAt <= startAt then
        nextAt = startAt + (preset == "daily" and DAY or WEEK)
    end
    local done = entry.completedAt and entry.completedAt >= startAt and entry.completedAt < nextAt
    return {
        done = done and true or false,
        nextAt = nextAt,
        start = startAt,
        preset = preset,
    }
end

function WBF.Plans.DisplayState(entry, now)
    if type(entry) ~= "table" then
        return "active"
    end
    if entry.status == "archived" then
        return "archived"
    end
    if entry.type == "recurring" then
        if WBF.Plans.Cycle(entry, now).done then
            return "doneCycle"
        end
        return "due"
    end
    if entry.type == "task" and entry.status == "completed" then
        return "completed"
    end
    if entry.type == "achievement" and WBF.PlanAchievements and WBF.PlanAchievements.Progress then
        local progress = WBF.PlanAchievements.Progress(entry.achievementID)
        if progress and progress.completed then
            return "completed"
        end
    end
    return "active"
end

local function DateText(timestamp)
    if type(timestamp) ~= "number" then
        return ""
    end
    if type(date) == "function" then
        return date("%b %d", timestamp)
    end
    return tostring(timestamp)
end

local function ResetText(cycle, now)
    if not cycle or type(cycle.nextAt) ~= "number" then
        return nil
    end
    local remain = math.floor(cycle.nextAt - now)
    if remain < 60 then
        return "Resets in <1m"
    end
    if remain < 3600 then
        return "Resets in " .. math.floor(remain / 60) .. "m"
    end
    if remain < DAY then
        return "Resets in " .. math.floor(remain / 3600) .. "h"
    end
    local days = math.floor(remain / DAY)
    if days < 1 then
        days = 1
    end
    return "Resets in " .. days .. "d"
end

function WBF.Plans.Title(entry, progress)
    if type(entry) ~= "table" then
        return ""
    end
    if entry.type == "achievement" then
        if type(progress) == "table" and type(progress.name) == "string" and progress.name ~= "" then
            return progress.name
        end
        if WBF.PlanAchievements and WBF.PlanAchievements.Info then
            local info = WBF.PlanAchievements.Info(entry.achievementID)
            if info and info.name then
                return info.name
            end
        end
        return "Achievement " .. tostring(entry.achievementID or "")
    end
    return entry.text or ""
end

function WBF.Plans.ContextText(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local bits = {}
    if type(entry.character) == "string" and entry.character ~= "" then
        local name = nil
        if WBF.Characters and WBF.Characters.Get then
            local character = WBF.Characters.Get(entry.character)
            name = character and character.name or nil
        end
        bits[#bits + 1] = name or "Character"
    end
    if type(entry.expansion) == "string" and entry.expansion ~= "" then
        bits[#bits + 1] = entry.expansion
    end
    if type(entry.zone) == "string" and entry.zone ~= "" then
        bits[#bits + 1] = entry.zone
    end
    if type(entry.category) == "string" and entry.category ~= "" then
        bits[#bits + 1] = entry.category
    end
    if #bits == 0 then
        return nil
    end
    return table.concat(bits, " · ")
end

function WBF.Plans.StatusLine(entry, now)
    if type(entry) ~= "table" then
        return nil
    end
    now = now or Now()
    local state = WBF.Plans.DisplayState(entry, now)
    local parts = {}
    if entry.type == "recurring" and state ~= "archived" then
        local cycle = WBF.Plans.Cycle(entry, now)
        if state == "due" then
            parts[#parts + 1] = "Due"
        elseif state == "doneCycle" then
            parts[#parts + 1] = "Completed this reset"
        end
        if entry.completedAt then
            parts[#parts + 1] = "Last completed: " .. DateText(entry.completedAt)
        end
        local reset = ResetText(cycle, now)
        if reset then
            parts[#parts + 1] = reset
        end
    elseif state == "completed" then
        parts[#parts + 1] = "Completed"
        if entry.completedAt then
            parts[#parts + 1] = DateText(entry.completedAt)
        end
    elseif state == "archived" then
        parts[#parts + 1] = "Archived"
    end
    local context = WBF.Plans.ContextText(entry)
    if context then
        parts[#parts + 1] = context
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, " · ")
end

function WBF.Plans.ObjectiveCount(planID, now)
    now = now or Now()
    local done = 0
    local total = 0
    local entries = WBF.Plans.InPlan(planID)
    for index = 1, #entries do
        local entry = entries[index]
        if entry.type ~= "note" then
            total = total + 1
            local state = WBF.Plans.DisplayState(entry, now)
            if state == "completed" or state == "doneCycle" then
                done = done + 1
            end
        end
    end
    return done, total
end

local function OwnsPlan(entry)
    if type(entry.planID) ~= "string" then
        return false
    end
    return WBF.Plans.GetGroup(entry.planID) ~= nil
end

function WBF.Plans.Buckets(now)
    now = now or Now()
    local due = {}
    local notes = {}
    local done = {}
    local plans = {}
    local donePlans = {}
    local groups = WBF.Plans.Groups()
    for index = 1, #groups do
        local group = groups[index]
        if group.status == "archived" then
            donePlans[#donePlans + 1] = group
        else
            plans[#plans + 1] = group
        end
    end
    local entries = WBF.Plans.Entries()
    for index = 1, #entries do
        local entry = entries[index]
        local state = WBF.Plans.DisplayState(entry, now)
        if state == "due" then
            due[#due + 1] = entry
        elseif state == "completed" or state == "archived" or state == "doneCycle" then
            done[#done + 1] = entry
        elseif not OwnsPlan(entry) then
            notes[#notes + 1] = entry
        end
    end
    table.sort(due, function(a, b)
        local left = WBF.Plans.Cycle(a, now).nextAt or math.huge
        local right = WBF.Plans.Cycle(b, now).nextAt or math.huge
        if left == right then
            return a.id < b.id
        end
        return left < right
    end)
    return {
        due = due,
        notes = notes,
        done = done,
        plans = plans,
        donePlans = donePlans,
    }
end

local function ProgressOf(entry)
    if entry.type ~= "achievement" or not WBF.PlanAchievements or not WBF.PlanAchievements.Progress then
        return nil
    end
    return WBF.PlanAchievements.Progress(entry.achievementID)
end

function WBF.Plans.Summary(now)
    now = now or Now()
    if WBF.PlanAchievements and WBF.PlanAchievements.InvalidateProgress then
        WBF.PlanAchievements.InvalidateProgress()
    end
    local lines = {}
    local active = 0
    local due = 0
    local total = 0
    local dueShown = 0

    local function addLine(label, value)
        if #lines >= 3 or type(label) ~= "string" or label == "" then
            return
        end
        lines[#lines + 1] = { label = label, value = value or "" }
    end

    local entries = WBF.Plans.Entries()
    for index = 1, #entries do
        local entry = entries[index]
        total = total + 1
        local state = WBF.Plans.DisplayState(entry, now)
        if state == "due" then
            due = due + 1
            active = active + 1
            if dueShown < 2 then
                addLine(WBF.Plans.Title(entry), "Due")
                dueShown = dueShown + 1
            end
        elseif state == "active" or state == "doneCycle" then
            active = active + 1
        end
    end

    for index = 1, #entries do
        local entry = entries[index]
        if #lines >= 3 then
            break
        end
        if entry.type == "achievement" and entry.status ~= "archived" then
            local progress = ProgressOf(entry)
            if not (progress and progress.completed) then
                local value = "Tracked"
                if WBF.PlanAchievements and WBF.PlanAchievements.ProgressText then
                    value = WBF.PlanAchievements.ProgressText(progress) or value
                end
                addLine(WBF.Plans.Title(entry, progress), value)
            end
        end
    end

    if #lines < 3 then
        for index = 1, #entries do
            local entry = entries[index]
            if #lines >= 3 then
                break
            end
            if WBF.Plans.DisplayState(entry, now) == "doneCycle" then
                addLine(WBF.Plans.Title(entry), "This reset")
            end
        end
    end

    if #lines < 3 then
        for index = 1, #entries do
            local entry = entries[index]
            if #lines >= 3 then
                break
            end
            local state = WBF.Plans.DisplayState(entry, now)
            if state == "active" and (entry.type == "note" or entry.type == "task") then
                addLine(WBF.Plans.Title(entry), entry.type == "task" and "Task" or "Note")
            end
        end
    end

    if #lines == 0 and total > 0 then
        addLine("Archived reminders", "")
    end

    return {
        total = total,
        active = active,
        due = due,
        lines = lines,
    }
end

function WBF.Plans.SuggestedZone()
    if WBF.Collections and WBF.Collections.CollectedWhere then
        local instanceName, zoneName = WBF.Collections.CollectedWhere()
        if type(zoneName) == "string" and zoneName ~= "" then
            return zoneName
        end
        if type(instanceName) == "string" and instanceName ~= "" then
            return instanceName
        end
    end
    return nil
end

local function AchievementLabel(achievementID)
    if WBF.PlanAchievements and WBF.PlanAchievements.Info then
        local info = WBF.PlanAchievements.Info(achievementID)
        if info and info.name then
            return info.name
        end
    end
    return "achievement " .. tostring(achievementID)
end

function WBF.Plans.HandleSlash(raw)
    if type(raw) ~= "string" then
        return false
    end
    local command, rest = Trim(raw):match("^(%S+)%s*(.*)$")
    if not command then
        return false
    end
    command = command:lower()
    rest = Trim(rest or "")
    if command == "note" or command == "task" then
        if rest == "" then
            Say("Usage: /wbfyi " .. command .. " <text>")
            return true
        end
        local entry = WBF.Plans.Add({
            type = command == "task" and "task" or "note",
            text = rest,
        })
        if entry then
            Say(command == "task" and "Task saved." or "Noted.")
        end
        return true
    end
    if command == "achieve" or command == "achievement" then
        local achievementID = tonumber(rest:match("^(%d+)"))
        if not achievementID then
            Say("Usage: /wbfyi achieve <id>")
            return true
        end
        local entry, reason = WBF.Plans.AddAchievement(achievementID)
        if not entry then
            Say("Couldn't track that achievement.")
            return true
        end
        local label = AchievementLabel(entry.achievementID)
        if reason == "exists" then
            Say("Already tracking " .. label .. ".")
        else
            Say("Tracking " .. label .. ".")
        end
        return true
    end
    if command == "plans" or command == "plan" then
        local frame = WBF.UI and WBF.UI.frame
        if frame and frame.SetView then
            frame:SetView("plans")
            if frame.IsShown and not frame:IsShown() and frame.Show then
                frame:Show()
            end
        end
        return true
    end
    return false
end

function WBF.Plans.Debug()
    local root = WBF.Plans.Root()
    local db = WBF.Database.Get()
    if not root then
        Say("Plans are not ready.")
        return
    end
    local summary = WBF.Plans.Summary()
    local groups = 0
    for _ in pairs(root.groups) do
        groups = groups + 1
    end
    Say(string.format(
        "%d entries, %d plans, %d active, %d due, schema %s",
        summary.total,
        groups,
        summary.active,
        summary.due,
        tostring(db and db.schemaVersion or "?")
    ))
end
