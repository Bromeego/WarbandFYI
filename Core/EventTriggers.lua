local _, WBF = ...

-- WoW holiday detection for recurring FYIs.
--
-- Retail calendar notes (checked against current C_Calendar docs):
--   C_Calendar.OpenCalendar() asks the client to fill calendar data.
--   That data is not reliable during ADDON_LOADED. Scan after
--   PLAYER_ENTERING_WORLD, then again on CALENDAR_UPDATE_EVENT_LIST.
--   C_Calendar.GetDayEvent(monthOffset, monthDay, index) returns a
--   CalendarDayEvent: title, eventID, calendarType, sequenceType,
--   eventType, startTime, endTime, iconTexture, numSequenceDays.
--   C_Calendar.GetHolidayInfo(monthOffset, monthDay, index) returns a
--   CalendarHolidayInfo: name, description, texture, startTime, endTime.
--   The wiki documents GetHolidayInfo offsets of 0 and 1 only.
--   GetMonthInfo() describes the month the calendar UI is showing, not
--   an arbitrary offset. Day queries use an offset from that month.
--   eventID identifies one calendar row. It is not a stable holiday type.
--   Holiday texture file IDs are the best non-localized hint Blizzard
--   exposes. They are not a published holiday id, so a title match can
--   remember a texture for next time. Until then, matching uses the
--   English catalog names below.
--
-- Localisation: calendar titles arrive in the client locale. The catalog
-- is English. A non-English client will not match a holiday by name until
-- that holiday's texture has been learned (or an alias is added here).
-- Name matching stays inside this provider so the FYI store never sees it.
--
-- A simulated event is layered on top of the cache for /wbfyi debug
-- simulateevent. It does not write calendar state.

WBF.EventTriggers = {}

local CATALOG = {
    { key = "brewfest", name = "Brewfest", titles = { "Brewfest" } },
    { key = "hallows_end", name = "Hallow's End", titles = { "Hallow's End", "Hallows End" } },
    { key = "timewalking", name = "Timewalking", titles = { "Turbulent Timeways", "Timewalking" } },
    { key = "darkmoon", name = "Darkmoon Faire", titles = { "Darkmoon Faire" } },
    { key = "winter_veil", name = "Winter Veil", titles = { "Winter Veil" } },
    { key = "lunar_festival", name = "Lunar Festival", titles = { "Lunar Festival" } },
    { key = "love_air", name = "Love is in the Air", titles = { "Love is in the Air" } },
    { key = "noblegarden", name = "Noblegarden", titles = { "Noblegarden" } },
    { key = "trial_of_style", name = "Trial of Style", titles = { "Trial of Style" } },
    { key = "midsummer", name = "Midsummer Fire Festival", titles = { "Midsummer" } },
}

local cache = nil
local ready = false
local simulated = nil
local injected = nil
local refreshQueued = false
local opened = false
local attempts = 0
local worldHandled = false
local boundaryGeneration = 0

local function Say(text)
    print("|cffd4af37WarbandFYI|r " .. tostring(text))
end

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Lower(value)
    return Trim(value):lower()
end

local function Whole(value)
    local id = WBF.Format.AsNumber(value)
    if not id or id ~= math.floor(id) or id < 1 then
        return nil
    end
    return id
end

local function ByKey(key)
    if type(key) ~= "string" then
        return nil
    end
    local needle = Lower(key)
    for index = 1, #CATALOG do
        local info = CATALOG[index]
        if info.key == key or info.key == needle then
            return info
        end
    end
    return nil
end

local function ByName(name)
    local needle = Lower(name)
    if needle == "" or needle == "off" or needle == "clear" then
        return nil
    end
    for index = 1, #CATALOG do
        local info = CATALOG[index]
        if Lower(info.name) == needle or Lower(info.key) == needle then
            return info
        end
    end
    local best = nil
    local bestLen = 0
    for index = 1, #CATALOG do
        local info = CATALOG[index]
        local titles = info.titles or {}
        for titleIndex = 1, #titles do
            local alias = titles[titleIndex]
            local aliasLower = Lower(alias)
            if needle:find(aliasLower, 1, true) or aliasLower:find(needle, 1, true) then
                if #alias > bestLen then
                    best = info
                    bestLen = #alias
                end
            end
        end
    end
    return best
end

function WBF.EventTriggers.Catalog()
    local list = {}
    for index = 1, #CATALOG do
        local info = CATALOG[index]
        list[index] = { key = info.key, name = info.name }
    end
    return list
end

function WBF.EventTriggers.FindCatalog(name)
    return ByKey(name) or ByName(name)
end

function WBF.EventTriggers.Normalize(trigger)
    if type(trigger) ~= "table" or trigger.type ~= "WOW_EVENT" then
        return nil
    end
    local info = ByKey(trigger.eventKey) or ByName(trigger.eventName) or ByName(trigger.eventKey)
    if not info then
        return nil
    end
    return {
        type = "WOW_EVENT",
        eventKey = info.key,
        eventName = info.name,
    }
end

function WBF.EventTriggers.OccurrenceKey(eventKey, startStamp)
    if type(eventKey) ~= "string" or eventKey == "" or type(startStamp) ~= "number" then
        return nil
    end
    return string.format("EVENT:%s:%d", eventKey:upper(), math.floor(startStamp))
end

function WBF.EventTriggers.Label(startStamp)
    if type(startStamp) ~= "number" or type(date) ~= "function" then
        return nil
    end
    local parts = date("*t", startStamp)
    if type(parts) ~= "table" or not parts.year or not parts.month then
        return nil
    end
    if WBF.Time and WBF.Time.MonthTitle then
        return WBF.Time.MonthTitle(parts.year, parts.month)
    end
    return tostring(parts.year)
end

-- Blizzard calendar event times are realm wall-clock values. Lua's time()/date()
-- use the PLAYER's local timezone, so time(calendarTime) shifts event boundaries
-- for players in different timezones (particularly OCE realms). Convert using
-- the current realm calendar clock as an anchor instead, with no fixed UTC
-- offset: this also works across timezones and changes in local DST.
local function CalendarDayNumber(year, month, day)
    -- Gregorian civil date -> stable integer day index, independent of timezone.
    if month <= 2 then year = year - 1 end
    local era = math.floor(year / 400)
    local yoe = year - era * 400
    local adjustedMonth = month + (month > 2 and -3 or 9)
    local doy = math.floor((153 * adjustedMonth + 2) / 5) + day - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe
end

local function CalendarSeconds(value)
    if type(value) ~= "table" or WBF.Format.IsSecret(value) then
        return nil
    end
    local year = WBF.Format.AsNumber(value.year)
    local month = WBF.Format.AsNumber(value.month)
    local day = WBF.Format.AsNumber(value.monthDay)
    local hour = WBF.Format.AsNumber(value.hour) or 0
    local minute = WBF.Format.AsNumber(value.minute) or 0
    if not year or not month or not day or month < 1 or month > 12
        or day < 1 or day > 31 or hour < 0 or hour > 23
        or minute < 0 or minute > 59 then
        return nil
    end
    return CalendarDayNumber(year, month, day) * 86400 + hour * 3600 + minute * 60
end

local function Stamp(calendarTime)
    local targetSeconds = CalendarSeconds(calendarTime)
    if not targetSeconds or not (C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime) then
        return nil
    end
    local realmNow = WBF.Format.SafeCall(C_DateAndTime.GetCurrentCalendarTime)
    local realmSeconds = CalendarSeconds(realmNow)
    if not realmSeconds then return nil end
    local now = (type(GetServerTime) == "function" and GetServerTime())
        or (type(time) == "function" and time())
    if type(now) ~= "number" then return nil end
    -- CalendarTime has minute resolution, so now - realmSeconds carries 0-59
    -- stray seconds. Occurrence keys embed the exact stamp, so snap the offset
    -- to the 15-minute grid every realm timezone uses; the same holiday must
    -- produce the same stamp on every scan and reload.
    local offset = math.floor((now - realmSeconds) / 900 + 0.5) * 900
    return targetSeconds + offset
end

local function Textures()
    local root = WBF.Notebook and WBF.Notebook.Root and WBF.Notebook.Root() or nil
    if not root then
        return nil
    end
    if type(root.fyiTextures) ~= "table" then
        root.fyiTextures = {}
    end
    return root.fyiTextures
end

local function RememberTexture(texture, eventKey)
    texture = Whole(texture)
    if not texture or type(eventKey) ~= "string" then
        return
    end
    local map = Textures()
    if not map then
        return
    end
    map[tostring(texture)] = eventKey
    local count = 0
    for textureText, key in pairs(map) do
        if not ByKey(key) then
            map[textureText] = nil
        else
            count = count + 1
        end
    end
    local keep = tostring(texture)
    while count > 32 do
        local dropped = nil
        for textureText in pairs(map) do
            if textureText ~= keep then
                dropped = textureText
                break
            end
        end
        if not dropped then
            break
        end
        map[dropped] = nil
        count = count - 1
    end
end

local function TextureKey(texture)
    texture = Whole(texture)
    if not texture then
        return nil
    end
    local map = Textures()
    local key = map and map[tostring(texture)] or nil
    if type(key) == "string" then
        return ByKey(key)
    end
    return nil
end

local function TitleKey(title)
    local hay = Lower(title or "")
    if hay == "" then
        return nil
    end
    local best = nil
    local bestLen = 0
    for index = 1, #CATALOG do
        local info = CATALOG[index]
        local titles = info.titles or {}
        for titleIndex = 1, #titles do
            local alias = titles[titleIndex]
            if hay:find(Lower(alias), 1, true) and #alias > bestLen then
                best = info
                bestLen = #alias
            end
        end
    end
    return best
end

-- Nil means the holiday kind could not be read. Secret comparisons throw
-- while this addon is on the call stack, so unread fields stay unknown.
local function IsHoliday(row)
    if type(row) ~= "table" then
        return false
    end
    local calendarType = row.calendarType
    local eventType = row.eventType
    local calendarSecret = WBF.Format.IsSecret(calendarType)
    local eventSecret = WBF.Format.IsSecret(eventType)
    local holiday = Enum and Enum.CalendarEventType and Enum.CalendarEventType.Holiday
    if calendarSecret then
        if eventSecret or eventType == nil then
            return nil
        end
        return holiday ~= nil and eventType == holiday
    end
    local kind = calendarType
    if kind == nil then
        if eventSecret then
            return nil
        end
        kind = eventType
    end
    if kind == nil then
        return nil
    end
    if kind == "HOLIDAY" then
        return true
    end
    return holiday ~= nil and kind == holiday
end

local function PlainTitle(row)
    local title = WBF.Format.PlainString(row.title)
    if title then
        return title
    end
    return WBF.Format.PlainString(row.holidayName)
end

local function RowTexture(row)
    return Whole(row.holidayTexture) or Whole(row.iconTexture)
end

local function MatchRow(row)
    local byTexture = TextureKey(RowTexture(row))
    if byTexture then
        return byTexture, true
    end
    local title = PlainTitle(row)
    local byTitle = TitleKey(title)
    if byTitle then
        RememberTexture(RowTexture(row), byTitle.key)
        return byTitle, false
    end
    return nil, false
end

local function Notify()
    if WBF.NotebookFyi and WBF.NotebookFyi.OnEventsChanged then
        WBF.NotebookFyi.OnEventsChanged()
    end
    if WBF.ContextFyi and WBF.ContextFyi.OnEventsChanged then
        WBF.ContextFyi.OnEventsChanged()
    end
end

local function IsActiveAt(event, now)
    if type(event) ~= "table" then
        return false
    end
    now = now or (WBF.Time and WBF.Time.Now and WBF.Time.Now()) or (type(time) == "function" and time()) or 0
    local startStamp = WBF.Format.AsNumber(event.startStamp)
    local endStamp = WBF.Format.AsNumber(event.endStamp)
    -- Calendar rows can remain present for the rest of the calendar day even
    -- after their exact end time. Treat the timestamp window as authoritative
    -- so an FYI disappears when the event actually ends, not at midnight.
    if startStamp and now < startStamp then
        return false
    end
    if endStamp and now >= endStamp then
        return false
    end
    return true
end

local function AddActive(map, source, now)
    if type(source) ~= "table" then
        return
    end
    for key, event in pairs(source) do
        if IsActiveAt(event, now) then
            map[key] = event
        end
    end
end

local function ActiveMap()
    local map = {}
    local now = (WBF.Time and WBF.Time.Now and WBF.Time.Now()) or (type(time) == "function" and time()) or 0
    AddActive(map, cache, now)
    AddActive(map, simulated, now)
    return map
end

local function NextBoundary(now)
    now = now or (WBF.Time and WBF.Time.Now and WBF.Time.Now()) or (type(time) == "function" and time()) or 0
    local nextAt = nil
    local function consider(source)
        if type(source) ~= "table" then
            return
        end
        for _, event in pairs(source) do
            if type(event) == "table" then
                local startStamp = WBF.Format.AsNumber(event.startStamp)
                local endStamp = WBF.Format.AsNumber(event.endStamp)
                if startStamp and startStamp > now and (not nextAt or startStamp < nextAt) then
                    nextAt = startStamp
                end
                if endStamp and endStamp > now and (not nextAt or endStamp < nextAt) then
                    nextAt = endStamp
                end
            end
        end
    end
    consider(cache)
    consider(simulated)
    return nextAt
end

local function ScheduleBoundaryCheck()
    boundaryGeneration = boundaryGeneration + 1
    local generation = boundaryGeneration
    if not (C_Timer and C_Timer.After) then
        return
    end
    local now = (WBF.Time and WBF.Time.Now and WBF.Time.Now()) or (type(time) == "function" and time()) or 0
    local nextAt = NextBoundary(now)
    if not nextAt then
        return
    end
    -- Wake at the exact boundary where practical, but never leave an event
    -- cache unattended for more than a minute. The short heartbeat also
    -- protects us from clock/calendar drift without polling every frame.
    local delay = math.max(0.1, math.min(60, (nextAt - now) + 0.25))
    C_Timer.After(delay, function()
        if generation ~= boundaryGeneration then
            return
        end
        local current = (WBF.Time and WBF.Time.Now and WBF.Time.Now()) or (type(time) == "function" and time()) or 0
        if current + 0.05 >= nextAt then
            -- ActiveMap() will now exclude an ended event (or include one that
            -- has just started). Re-render FYIs immediately; calendar refresh
            -- can follow independently if Blizzard emits one.
            Notify()
        end
        ScheduleBoundaryCheck()
    end)
end

-- Calendar holiday artwork is frequently a wide banner. Forcing those files
-- into a square FYI slot makes them look squashed, so the normal FYI icon
-- prefers the square icon of a tracked event resource (ticket/token/etc.).
-- CalendarArtwork remains available when a caller actually wants the raw
-- Blizzard holiday artwork.
local function ResourceIcon(eventKey)
    if not (WBF.Resources and WBF.Resources.Each) then
        return nil
    end
    local list = WBF.Resources.Each() or {}
    for index = 1, #list do
        local definition = list[index]
        if definition and definition.eventKey == eventKey then
            local icon = Whole(definition.iconFile)
            if not icon and definition.trackingType == "currency" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                local currency = WBF.Format.SafeCall(C_CurrencyInfo.GetCurrencyInfo, definition.id)
                if type(currency) == "table" then
                    icon = Whole(currency.iconFileID)
                end
            elseif not icon and definition.trackingType == "item" and C_Item then
                if C_Item.GetItemIconByID then
                    icon = Whole(WBF.Format.SafeCall(C_Item.GetItemIconByID, definition.id))
                elseif C_Item.GetItemInfoInstant then
                    local _, _, _, _, itemIcon = WBF.Format.SafeCall(C_Item.GetItemInfoInstant, definition.id)
                    icon = Whole(itemIcon)
                end
            end
            if icon then
                return icon
            end
        end
    end
    return nil
end

function WBF.EventTriggers.CalendarArtwork(eventKey)
    local info = ByKey(eventKey) or ByName(eventKey)
    if not info then
        return nil
    end
    local active = ActiveMap()[info.key]
    local texture = active and Whole(active.texture) or nil
    if texture then
        return texture
    end
    local learned = Textures()
    if type(learned) == "table" then
        for textureText, key in pairs(learned) do
            if key == info.key then
                texture = Whole(textureText)
                if texture then
                    return texture
                end
            end
        end
    end
    return nil
end

function WBF.EventTriggers.Icon(eventKey)
    local info = ByKey(eventKey) or ByName(eventKey)
    if not info then
        return nil
    end
    return ResourceIcon(info.key)
end

local function Describe(info, startStamp, endStamp, row, fromSimulation)
    local key = WBF.EventTriggers.OccurrenceKey(info.key, startStamp)
    return {
        eventKey = info.key,
        eventName = info.name,
        title = row and PlainTitle(row) or info.name,
        occurrenceKey = key,
        startStamp = startStamp,
        endStamp = endStamp,
        label = WBF.EventTriggers.Label(startStamp) or info.name,
        texture = row and RowTexture(row) or nil,
        eventID = row and Whole(row.eventID) or nil,
        simulated = fromSimulation and true or false,
    }
end

local function FindStart(reader, info, row, offset, day)
    local holidayStart = Stamp(row.holidayStart)
    local holidayEnd = Stamp(row.holidayEnd)
    if holidayStart then
        return holidayStart, holidayEnd
    end
    local sequence = WBF.Format.PlainString(row.sequenceType) or ""
    if sequence == "START" or sequence == "" then
        return Stamp(row.startTime), Stamp(row.endTime)
    end
    local cursorOffset, cursorDay = offset, day
    for _ = 1, 21 do
        local previousOffset, previousDay = reader:Shift(cursorOffset, cursorDay, -1)
        if not previousOffset then
            break
        end
        cursorOffset, cursorDay = previousOffset, previousDay
        local list = reader:Events(cursorOffset, cursorDay)
        if list then
            for index = 1, #list do
                local earlier = list[index]
                if earlier and IsHoliday(earlier) == true then
                    local matched = MatchRow(earlier)
                    local earlierSequence = WBF.Format.PlainString(earlier.sequenceType) or ""
                    if matched and matched.key == info.key and (earlierSequence == "START" or earlierSequence == "") then
                        local startStamp = Stamp(earlier.holidayStart) or Stamp(earlier.startTime)
                        local endStamp = Stamp(earlier.holidayEnd) or Stamp(earlier.endTime) or holidayEnd
                        if startStamp then
                            return startStamp, endStamp
                        end
                    end
                end
            end
        end
    end
    return Stamp(row.startTime), Stamp(row.endTime) or holidayEnd
end

local function Collect(reader)
    local offset, day = reader:Today()
    if not offset or not day then
        return nil
    end
    local events = reader:Events(offset, day)
    if not events then
        return nil
    end
    local saw = false
    local readable = false
    local found = {}
    for index = 1, #events do
        local row = events[index]
        if type(row) == "table" then
            saw = true
            local holiday = IsHoliday(row)
            if holiday == nil then
                -- Protected event kind. Keep the previous cache.
            elseif not holiday then
                readable = true
            else
                readable = true
                local info = MatchRow(row)
                if info then
                    local startStamp, endStamp = FindStart(reader, info, row, offset, day)
                    if startStamp then
                        found[info.key] = Describe(info, startStamp, endStamp, row, false)
                    end
                end
            end
        end
    end
    if saw and not readable then
        return nil
    end
    return found
end

local function LiveReader()
    local reader = {}

    function reader:Today()
        if not C_Calendar or not C_DateAndTime or not C_DateAndTime.GetCurrentCalendarTime then
            return nil
        end
        local now = WBF.Format.SafeCall(C_DateAndTime.GetCurrentCalendarTime)
        if type(now) ~= "table" or WBF.Format.IsSecret(now) then
            return nil
        end
        local year = WBF.Format.AsNumber(now.year)
        local month = WBF.Format.AsNumber(now.month)
        local day = WBF.Format.AsNumber(now.monthDay)
        if not year or not month or not day then
            return nil
        end
        local offset = 0
        if C_Calendar.GetMonthInfo then
            local shown = WBF.Format.SafeCall(C_Calendar.GetMonthInfo)
            if type(shown) == "table" and not WBF.Format.IsSecret(shown) then
                local shownMonth = WBF.Format.AsNumber(shown.month)
                local shownYear = WBF.Format.AsNumber(shown.year)
                if shownMonth and shownYear then
                    offset = (year - shownYear) * 12 + (month - shownMonth)
                end
            end
        end
        if offset < -1 or offset > 1 then
            local open = CalendarFrame and CalendarFrame.IsShown and CalendarFrame:IsShown()
            if open or not C_Calendar.SetAbsMonth then
                return nil
            end
            pcall(C_Calendar.SetAbsMonth, month, year)
            offset = 0
        end
        self.now = { year = year, month = month, monthDay = day }
        self.baseOffset = offset
        return offset, day
    end

    function reader:Events(offset, day)
        if not C_Calendar.GetNumDayEvents or not C_Calendar.GetDayEvent then
            return nil
        end
        if type(offset) ~= "number" or offset < -1 or offset > 1 then
            return {}
        end
        local count = WBF.Format.SafeCall(C_Calendar.GetNumDayEvents, offset, day)
        if count == nil or WBF.Format.IsSecret(count) then
            return nil
        end
        count = WBF.Format.AsNumber(count) or 0
        local list = {}
        for index = 1, count do
            local row = WBF.Format.SafeCall(C_Calendar.GetDayEvent, offset, day, index)
            if type(row) == "table" and not WBF.Format.IsSecret(row) then
                local copy = {
                    title = row.title,
                    calendarType = row.calendarType,
                    eventType = row.eventType,
                    sequenceType = row.sequenceType,
                    eventID = row.eventID,
                    iconTexture = row.iconTexture,
                    startTime = row.startTime,
                    endTime = row.endTime,
                }
                if C_Calendar.GetHolidayInfo and offset >= 0 and offset <= 1 then
                    local holiday = WBF.Format.SafeCall(C_Calendar.GetHolidayInfo, offset, day, index)
                    if type(holiday) == "table" and not WBF.Format.IsSecret(holiday) then
                        copy.holidayName = holiday.name
                        copy.holidayTexture = holiday.texture
                        copy.holidayStart = holiday.startTime
                        copy.holidayEnd = holiday.endTime
                    end
                end
                list[#list + 1] = copy
            end
        end
        return list
    end

    function reader:Shift(offset, day, delta)
        local now = self.now
        if not now or delta ~= -1 or type(time) ~= "function" or type(date) ~= "function" then
            return nil
        end
        local monthDelta = offset - (self.baseOffset or 0)
        local year = now.year
        local month = now.month + monthDelta
        while month < 1 do
            month = month + 12
            year = year - 1
        end
        while month > 12 do
            month = month - 12
            year = year + 1
        end
        local stamp = time({ year = year, month = month, day = day, hour = 12, min = 0, sec = 0 })
        if type(stamp) ~= "number" then
            return nil
        end
        local parts = date("*t", stamp - 86400)
        if type(parts) ~= "table" then
            return nil
        end
        local nextOffset = (self.baseOffset or 0) + ((parts.year - now.year) * 12 + (parts.month - now.month))
        if nextOffset < -1 or nextOffset > 1 then
            return nil
        end
        return nextOffset, parts.day
    end

    return reader
end

local function InjectedReader()
    local source = injected
    local reader = {}

    function reader:Today()
        local now = source.now
        if type(now) ~= "table" or not now.monthDay then
            return nil
        end
        self.now = now
        self.baseOffset = 0
        return 0, now.monthDay
    end

    function reader:Events(offset, day)
        local months = source.months or {}
        local month = months[offset]
        if type(month) ~= "table" then
            return {}
        end
        local days = month.days or {}
        local list = days[day]
        if list == nil then
            return {}
        end
        if type(list) ~= "table" then
            return nil
        end
        return list
    end

    function reader:Shift(offset, day, delta)
        if delta ~= -1 then
            return nil
        end
        if day > 1 then
            return offset, day - 1
        end
        local months = source.months or {}
        local previous = months[offset - 1]
        if type(previous) ~= "table" or type(previous.numDays) ~= "number" then
            return nil
        end
        return offset - 1, previous.numDays
    end

    return reader
end

local function Scan()
    if injected then
        return Collect(InjectedReader())
    end
    if not C_Calendar then
        return nil
    end
    return Collect(LiveReader())
end

function WBF.EventTriggers.UseCalendar(source)
    if source == nil then
        injected = nil
    elseif type(source) == "table" then
        injected = source
    end
    cache = nil
    ready = false
end

function WBF.EventTriggers.Refresh()
    local found = Scan()
    if found then
        cache = found
        ready = true
        attempts = 0
    end
    ScheduleBoundaryCheck()
    Notify()
    return found ~= nil
end

local function Attempt()
    if WBF.EventTriggers.Refresh() then
        return
    end
    attempts = attempts + 1
    if attempts < 3 and C_Timer and C_Timer.After then
        C_Timer.After(2, Attempt)
    end
end

function WBF.EventTriggers.RequestRefresh()
    if refreshQueued then
        return
    end
    refreshQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.4, function()
            refreshQueued = false
            WBF.EventTriggers.Refresh()
        end)
    else
        refreshQueued = false
        WBF.EventTriggers.Refresh()
    end
end

function WBF.EventTriggers.OnWorld(initialLogin, reloadingUi)
    if worldHandled and not initialLogin and not reloadingUi then
        return
    end
    worldHandled = true
    if C_Calendar and C_Calendar.OpenCalendar and (initialLogin or reloadingUi or not opened) then
        pcall(C_Calendar.OpenCalendar)
        opened = true
    end
    attempts = 0
    if C_Timer and C_Timer.After then
        C_Timer.After(1, Attempt)
    else
        Attempt()
    end
end

function WBF.EventTriggers.Simulate(name)
    local text = Trim(name or "")
    if text == "" or Lower(text) == "off" or Lower(text) == "clear" then
        simulated = nil
        Notify()
        return false
    end
    local info = ByName(text) or ByKey(text)
    if not info then
        return nil
    end
    local now = WBF.Time.Now()
    local parts = type(date) == "function" and date("*t", now) or nil
    local startStamp = now
    if type(parts) == "table" and type(time) == "function" then
        startStamp = time({
            year = parts.year,
            month = parts.month,
            day = parts.day,
            hour = 0,
            min = 0,
            sec = 0,
        }) or now
    end
    simulated = simulated or {}
    simulated[info.key] = Describe(info, startStamp, startStamp + (6 * 86400), nil, true)
    ScheduleBoundaryCheck()
    Notify()
    return info
end

function WBF.EventTriggers.ClearSimulation()
    simulated = nil
    ScheduleBoundaryCheck()
    Notify()
end

function WBF.EventTriggers.OnLoad()
    cache = nil
    ready = false
    simulated = nil
    worldHandled = false
    attempts = 0
    refreshQueued = false
    boundaryGeneration = boundaryGeneration + 1
end

local function FindActive(trigger)
    if type(trigger) ~= "table" then
        return nil
    end
    local info = ByKey(trigger.eventKey) or ByName(trigger.eventName)
    if not info then
        return nil
    end
    return ActiveMap()[info.key]
end

local provider = {}

function provider:IsAvailable()
    if simulated and next(simulated) then
        return true
    end
    return ready
end

function provider:IsActive(trigger)
    return FindActive(trigger) ~= nil
end

function provider:GetOccurrenceKey(trigger)
    local event = FindActive(trigger)
    if not event then
        return nil
    end
    return event.occurrenceKey
end

function provider:GetDisplayContext(trigger)
    local info = type(trigger) == "table" and (ByKey(trigger.eventKey) or ByName(trigger.eventName)) or nil
    local event = FindActive(trigger)
    if not event then
        return {
            active = false,
            type = "WOW_EVENT",
            eventKey = info and info.key or (trigger and trigger.eventKey) or nil,
            eventName = info and info.name or (trigger and trigger.eventName) or nil,
            occurrenceKey = nil,
        }
    end
    return {
        active = true,
        type = "WOW_EVENT",
        eventKey = event.eventKey,
        eventName = event.eventName,
        occurrenceKey = event.occurrenceKey,
        startStamp = event.startStamp,
        endStamp = event.endStamp,
        label = event.label,
        texture = event.texture,
        simulated = event.simulated and true or false,
    }
end

WBF.Triggers.Register("WOW_EVENT", provider)

function WBF.EventTriggers.Active()
    local list = {}
    local map = ActiveMap()
    for _, event in pairs(map) do
        list[#list + 1] = event
    end
    table.sort(list, function(a, b)
        return (a.eventName or "") < (b.eventName or "")
    end)
    return list
end

function WBF.EventTriggers.Debug()
    local list = WBF.EventTriggers.Active()
    if #list == 0 then
        Say("No active WoW events.")
        return
    end
    for index = 1, #list do
        local event = list[index]
        local texture = event.texture and (" texture " .. tostring(event.texture)) or ""
        local flag = event.simulated and " simulated" or ""
        Say(string.format(
            "%s  %s  %s%s%s",
            event.eventName or event.eventKey,
            event.occurrenceKey or "no occurrence",
            event.label or "",
            texture,
            flag
        ))
    end
end

function WBF.EventTriggers.Register(bus)
    if not bus or not bus.On then
        return
    end
    bus:On("PLAYER_ENTERING_WORLD", function(initialLogin, reloadingUi)
        WBF.EventTriggers.OnWorld(initialLogin and true or false, reloadingUi and true or false)
    end)
    bus:On("CALENDAR_UPDATE_EVENT_LIST", function()
        WBF.EventTriggers.RequestRefresh()
    end)
end
