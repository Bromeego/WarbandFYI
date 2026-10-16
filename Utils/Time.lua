local _, WBF = ...

WBF.Time = {}

-- time() and date() share one clock, so day and week boundaries stay aligned.
function WBF.Time.Now()
    return time()
end

function WBF.Time.StartOfDay(now)
    local parts = date("*t", now or WBF.Time.Now())
    parts.hour = 0
    parts.min = 0
    parts.sec = 0
    return time(parts)
end

function WBF.Time.StartOfMonth(now)
    local parts = date("*t", now or WBF.Time.Now())
    parts.day = 1
    parts.hour = 0
    parts.min = 0
    parts.sec = 0
    return time(parts)
end

-- Calendar week, Monday 00:00 local time. This is a journal week, not a raid reset.
function WBF.Time.StartOfWeek(now)
    local parts = date("*t", now or WBF.Time.Now())
    local daysSinceMonday = (parts.wday + 5) % 7
    parts.day = parts.day - daysSinceMonday
    parts.hour = 0
    parts.min = 0
    parts.sec = 0
    return time(parts)
end

function WBF.Time.Clock(timestamp)
    local parts = date("*t", timestamp)
    local hour = parts.hour % 12
    if hour == 0 then
        hour = 12
    end
    local suffix = parts.hour >= 12 and "PM" or "AM"
    return string.format("%d:%02d %s", hour, parts.min, suffix)
end

function WBF.Time.FormatStamp(timestamp)
    local parts = date("*t", timestamp)
    return date("%A, %b ", timestamp) .. parts.day .. ", " .. WBF.Time.Clock(timestamp)
end

local MONTHS = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}

local MONTHS_SHORT = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

function WBF.Time.CurrentMonth(now)
    local parts = date("*t", now or WBF.Time.Now())
    return parts.year, parts.month
end

-- Month arithmetic stays on the same local calendar as StartOfMonth.
function WBF.Time.AddMonths(year, month, delta)
    local index = (year * 12 + (month - 1)) + (delta or 0)
    local newYear = math.floor(index / 12)
    local newMonth = index - (newYear * 12) + 1
    return newYear, newMonth
end

function WBF.Time.MonthStart(year, month)
    return time({
        year = year,
        month = month,
        day = 1,
        hour = 0,
        min = 0,
        sec = 0,
    })
end

-- startAt, endAt, isCurrent, closedEnd.
-- endAt is "now" for the open month and the last second of the month otherwise.
function WBF.Time.MonthBounds(year, month, now)
    now = now or WBF.Time.Now()
    local startAt = WBF.Time.MonthStart(year, month)
    local nextYear, nextMonth = WBF.Time.AddMonths(year, month, 1)
    local closedEnd = WBF.Time.MonthStart(nextYear, nextMonth) - 1
    local currentYear, currentMonth = WBF.Time.CurrentMonth(now)
    local isCurrent = year == currentYear and month == currentMonth
    local endAt = closedEnd
    if isCurrent then
        endAt = now
        if endAt < startAt then
            endAt = startAt
        end
    end
    return startAt, endAt, isCurrent, closedEnd
end

function WBF.Time.MonthKey(year, month)
    return string.format("%04d-%02d", year, month)
end

function WBF.Time.MonthTitle(year, month)
    return (MONTHS[month] or "Month") .. " " .. tostring(year)
end

function WBF.Time.FormatDay(timestamp)
    if type(timestamp) ~= "number" then
        return ""
    end
    local parts = date("*t", timestamp)
    return (MONTHS_SHORT[parts.month] or "") .. " " .. tostring(parts.day)
end
