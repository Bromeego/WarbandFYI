-- Day, week, and month starts stay on local midnight across a daylight-saving flag.
--   lua tests/TimeBoundaryTest.lua

local function utc(year, month, day, hour, minute, second)
    local y = month <= 2 and year - 1 or year
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
    local days = era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
    return days * 86400 + (hour or 0) * 3600 + (minute or 0) * 60 + (second or 0)
end

local function daysIn(year, month)
    local lengths = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 and (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) then
        return 29
    end
    return lengths[month]
end

-- A copied isdst=true flag pulls midnight back an hour, the same way Lua's
-- time() does when the flag does not match the date being built.
function time(parts)
    if type(parts) ~= "table" then
        return utc(2026, 10, 7, 15, 0, 0)
    end
    local year, month, day = parts.year, parts.month, parts.day
    while day < 1 do
        month = month - 1
        if month < 1 then
            month = 12
            year = year - 1
        end
        day = day + daysIn(year, month)
    end
    while day > daysIn(year, month) do
        day = day - daysIn(year, month)
        month = month + 1
        if month > 12 then
            month = 1
            year = year + 1
        end
    end
    local stamp = utc(year, month, day, parts.hour, parts.min, parts.sec)
    if parts.isdst == true then
        stamp = stamp - 3600
    end
    return stamp
end

function date(fmt, ts)
    local parts = os.date("!*t", ts or time())
    if fmt == "*t" then
        parts.isdst = true
        return parts
    end
    return os.date("!" .. fmt, ts)
end

local WBF = {}
assert(loadfile("Utils/Time.lua"))("WarbandFYI", WBF)

local failures = 0
local function check(name, condition, detail)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  " .. tostring(detail)) or ""))
end

local wednesday = utc(2026, 10, 7, 15, 0, 0)
local dayStart = WBF.Time.StartOfDay(wednesday)
local dayParts = date("*t", dayStart)
check("start of day is midnight", dayParts.hour == 0 and dayParts.min == 0 and dayParts.day == 7 and dayParts.month == 10, dayParts.hour)

local weekStart = WBF.Time.StartOfWeek(wednesday)
local weekParts = date("*t", weekStart)
check("week starts monday at midnight", weekParts.wday == 2 and weekParts.hour == 0 and weekParts.day == 5 and weekParts.month == 10, weekParts.day)

local sunday = utc(2026, 10, 4, 12, 0, 0)
local fromSunday = date("*t", WBF.Time.StartOfWeek(sunday))
check("sunday still belongs to the previous monday", fromSunday.wday == 2 and fromSunday.hour == 0 and fromSunday.day == 28 and fromSunday.month == 9, fromSunday.day)

local monthStart = date("*t", WBF.Time.MonthStart(2026, 10))
check("month starts on the first at midnight", monthStart.day == 1 and monthStart.hour == 0 and monthStart.month == 10)
local same = date("*t", WBF.Time.StartOfMonth(wednesday))
check("start of month matches month start", same.day == 1 and same.hour == 0 and same.month == 10)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All time boundary checks passed")
