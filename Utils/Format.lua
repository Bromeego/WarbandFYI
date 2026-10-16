local _, WBF = ...

WBF.Format = {}

local secretWarned = false

-- Secret checks have to run before any comparison or boolean test. Those
-- operations error while this addon is on the call stack.
function WBF.Format.IsSecret(value)
    return issecretvalue and issecretvalue(value) and true or false
end

-- Midnight can hand combat-adjacent values back as secrets. Money and item
-- level should be plain numbers; if they are not, skip that reading.
function WBF.Format.AsNumber(value)
    if WBF.Format.IsSecret(value) then
        if not secretWarned then
            secretWarned = true
            print("|cffd4af37WarbandFYI|r skipped a protected value, so one reading was not recorded.")
        end
        return nil
    end
    if value == nil then
        return nil
    end
    if type(value) == "number" then
        return value
    end
    return tonumber(value)
end

function WBF.Format.PlainString(value)
    if WBF.Format.IsSecret(value) then
        return nil
    end
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

-- Nil means the boolean could not be read. Callers should treat that as unknown.
function WBF.Format.AsBoolean(value)
    if WBF.Format.IsSecret(value) or value == nil then
        return nil
    end
    return value and true or false
end

-- Runs func and returns its results. A throw or a missing function yields
-- nothing, so one protected API cannot abort the caller. Returned values may
-- still be secret; callers must pass them through AsNumber, AsBoolean, or
-- PlainString before comparing them.
function WBF.Format.SafeCall(func, ...)
    if type(func) ~= "function" then
        return
    end
    local ok, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16 = pcall(func, ...)
    if not ok then
        return
    end
    return r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14, r15, r16
end

-- Nil when the call failed or the result could not be read. False is a real
-- false, not an unknown.
function WBF.Format.SafeBoolean(func, ...)
    return WBF.Format.AsBoolean(WBF.Format.SafeCall(func, ...))
end

function WBF.Format.Duration(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 1 then
        return nil
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remain = seconds % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, remain)
    end
    return string.format("%d:%02d", minutes, remain)
end

function WBF.Format.Round(value)
    local number = WBF.Format.AsNumber(value)
    if not number then
        return nil
    end
    return math.floor(number + 0.5)
end

function WBF.Format.Number(value)
    local number = math.floor(tonumber(value) or 0)
    local negative = number < 0
    local digits = tostring(math.abs(number))
    while true do
        local replaced, count = digits:gsub("^(%d+)(%d%d%d)", "%1,%2")
        digits = replaced
        if count == 0 then
            break
        end
    end
    if negative then
        return "-" .. digits
    end
    return digits
end

function WBF.Format.Signed(value)
    local number = math.floor(tonumber(value) or 0)
    if number > 0 then
        return "+" .. WBF.Format.Number(number)
    end
    return WBF.Format.Number(number)
end

local function GoldParts(absolute)
    local gold = math.floor(absolute / 10000)
    local silver = math.floor((absolute % 10000) / 100)
    local copper = absolute % 100
    return gold, silver, copper
end

local function AbbreviateGold(gold)
    local function scaled(divisor, suffix)
        local tenths = math.floor(gold / math.floor(divisor / 10))
        local whole = math.floor(tenths / 10)
        local tenth = tenths % 10
        if tenth == 0 then
            return WBF.Format.Number(whole) .. suffix
        end
        return WBF.Format.Number(whole) .. "." .. tenth .. suffix
    end
    if gold >= 1000000 then
        return scaled(1000000, "m")
    end
    return scaled(1000, "k")
end

-- copper is a money amount in copper. signed prefixes a plus on gains.
-- mode "compact" is for large dashboard figures (1g, 42g, 12.4k).
-- mode "precise" keeps silver and copper for rows and gold detail (1g 99s).
-- The default stays the historical compact form without the k/m abbreviation.
function WBF.Format.Gold(copper, signed, mode)
    local value = math.floor(tonumber(copper) or 0)
    local negative = value < 0
    local absolute = math.abs(value)
    local gold, silver, copperRem = GoldParts(absolute)
    local text
    if mode == "precise" then
        if gold > 0 then
            text = WBF.Format.Number(gold) .. "g"
            if silver > 0 or copperRem > 0 then
                text = text .. " " .. silver .. "s"
            end
            if copperRem > 0 then
                text = text .. " " .. copperRem .. "c"
            end
        elseif silver > 0 then
            text = silver .. "s"
            if copperRem > 0 then
                text = text .. " " .. copperRem .. "c"
            end
        else
            text = copperRem .. "c"
        end
    elseif mode == "compact" and gold >= 10000 then
        text = AbbreviateGold(gold)
    elseif absolute == 0 or absolute >= 10000 then
        text = WBF.Format.Number(gold) .. "g"
    elseif silver > 0 then
        text = silver .. "s"
    else
        text = copperRem .. "c"
    end
    if negative then
        return "-" .. text
    end
    if signed and value > 0 then
        return "+" .. text
    end
    return text
end

function WBF.Format.Played(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds > 0 and seconds < 60 then
        return "<1m"
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    end
    return string.format("%dm", minutes)
end

function WBF.Format.Ago(timestamp, now)
    local delta = math.max(0, (now or WBF.Time.Now()) - (timestamp or 0))
    if delta < 45 then
        return "just now"
    end
    if delta < 3600 then
        return math.floor(delta / 60) .. "m ago"
    end
    if delta < 86400 then
        return math.floor(delta / 3600) .. "h ago"
    end
    if delta < 86400 * 7 then
        return math.floor(delta / 86400) .. "d ago"
    end
    return date("%b %d", timestamp)
end

function WBF.Format.ClassColor(classFile)
    local colors = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
    if colors then
        return colors.r, colors.g, colors.b
    end
    return 0.93, 0.90, 0.82
end

function WBF.Format.QualityColor(quality)
    local colors = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
    if colors then
        return colors.r, colors.g, colors.b
    end
    return 0.93, 0.90, 0.82
end

-- The client font does not draw a Unicode arrow, so progression uses a
-- stock atlas when the client has one, then a stock button texture.
local arrowMarkup
local ASCII_ARROW = ">"

local function ArrowMarkup()
    if arrowMarkup then
        return arrowMarkup
    end
    if not (C_Texture and C_Texture.GetAtlasInfo) then
        return "|TInterface\\Buttons\\UI-SpellbookIcon-NextPage-Up:12:12:0:0|t"
    end
    if C_Texture.GetAtlasInfo("common-icon-forwardarrow") then
        arrowMarkup = "|A:common-icon-forwardarrow:12:12:0:0|a"
    else
        arrowMarkup = "|TInterface\\Buttons\\UI-SpellbookIcon-NextPage-Up:12:12:0:0|t"
    end
    return arrowMarkup
end

function WBF.Format.Progression(oldValue, newValue)
    local arrow = ArrowMarkup()
    if not arrow or arrow == "" then
        arrow = ASCII_ARROW
    end
    return tostring(oldValue) .. "  " .. arrow .. "  " .. tostring(newValue)
end

function WBF.Format.Arrow(previous, current)
    return WBF.Format.Progression(previous, current)
end

-- Saved event text from earlier builds still contains the Unicode arrow.
function WBF.Format.DisplayText(text)
    if type(text) ~= "string" then
        return text
    end
    if not text:find("→", 1, true) then
        return text
    end
    return (text:gsub("→", ArrowMarkup()))
end

-- Turns a localized GlobalString such as "Reputation with %s increased by %d."
-- into a Lua pattern. Capture order follows the string; each capture is tagged
-- with the format argument index so "%2$d ... %1$s" still lines up.
function WBF.Format.CompileGlobal(globalName)
    local text = _G[globalName]
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local pieces = {}
    local args = {}
    local pos = 1
    while pos <= #text do
        local startAt, endAt, token = text:find("%%(%d*%$?[%d%.]*[sdif])", pos)
        if not startAt then
            pieces[#pieces + 1] = (text:sub(pos):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
            break
        end
        if startAt > pos then
            pieces[#pieces + 1] = (text:sub(pos, startAt - 1):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
        end
        local indexPart, body = token:match("^(%d+)%$(.+)$")
        if not body then
            body = token
        end
        local kind = "string"
        if body:find("d", 1, true) or body:find("i", 1, true) or body:find("f", 1, true) then
            kind = "number"
            pieces[#pieces + 1] = "(%-?%d+%.?%d*)"
        else
            pieces[#pieces + 1] = "(.+)"
        end
        args[#args + 1] = {
            kind = kind,
            arg = indexPart and tonumber(indexPart) or nil,
        }
        pos = endAt + 1
    end

    local used = {}
    for index = 1, #args do
        if args[index].arg then
            used[args[index].arg] = true
        end
    end
    local nextArg = 1
    for index = 1, #args do
        if not args[index].arg then
            while used[nextArg] do
                nextArg = nextArg + 1
            end
            args[index].arg = nextArg
            used[nextArg] = true
            nextArg = nextArg + 1
        end
    end

    return {
        pattern = "^" .. table.concat(pieces) .. "$",
        args = args,
    }
end

function WBF.Format.MatchGlobal(message, compiled)
    if type(message) ~= "string" or not compiled then
        return nil
    end
    local captures = { message:match(compiled.pattern) }
    if captures[1] == nil then
        return nil
    end
    local values = {}
    for index = 1, #compiled.args do
        local spec = compiled.args[index]
        local value = captures[index]
        if spec.kind == "number" then
            value = tonumber(value)
        end
        values[spec.arg] = value
    end
    return values
end

function WBF.Format.CountLabel(count, singular, plural)
    if count == 1 then
        return "1 " .. singular
    end
    return WBF.Format.Number(count) .. " " .. (plural or (singular .. "s"))
end

function WBF.Format.ActivityLine(counts, gold)
    local parts = {}
    local function add(text)
        parts[#parts + 1] = text
    end
    if counts.raids > 0 then
        add(WBF.Format.CountLabel(counts.raids, "Raid"))
    end
    if counts.dungeons > 0 then
        add(WBF.Format.CountLabel(counts.dungeons, "Dungeon"))
    end
    if counts.mythicPlus > 0 then
        local text = WBF.Format.CountLabel(counts.mythicPlus, "Mythic+", "Mythic+")
        if counts.highestKey > 0 then
            text = text .. "  ·  Highest +" .. counts.highestKey
        end
        add(text)
    end
    if counts.bosses > 0 then
        add(WBF.Format.CountLabel(counts.bosses, "Boss", "Bosses"))
    end
    if counts.delves > 0 then
        local text = WBF.Format.CountLabel(counts.delves, "Delve")
        if counts.highestDelve > 0 then
            text = text .. "  ·  Highest tier " .. counts.highestDelve
        end
        add(text)
    end
    if (counts.rares or 0) > 0 then
        add(WBF.Format.CountLabel(counts.rares, "Rare"))
    end
    if (counts.fishing or 0) > 0 then
        add(WBF.Format.CountLabel(counts.fishing, "Fishing Catch", "Fishing Catches"))
    end
    if (counts.mining or 0) > 0 then
        add(WBF.Format.CountLabel(counts.mining, "Mining Node"))
    end
    if (counts.herbalism or 0) > 0 then
        add(WBF.Format.CountLabel(counts.herbalism, "Herb Node", "Herb Nodes"))
    end
    if (counts.lumber or 0) > 0 then
        add(WBF.Format.CountLabel(counts.lumber, "Lumber", "Lumber"))
    end
    if (counts.skinning or 0) > 0 then
        add(WBF.Format.CountLabel(counts.skinning, "Creature Skinned", "Creatures Skinned"))
    end
    if (counts.curseSurges or 0) > 0 then
        add(WBF.Format.CountLabel(counts.curseSurges, "Curse Surge"))
    end
    if (counts.worldEvents or 0) > 0 then
        add(WBF.Format.CountLabel(counts.worldEvents, "World Event"))
    end
    if counts.quests > 0 then
        add(WBF.Format.CountLabel(counts.quests, "Quest"))
    end
    if counts.worldQuests > 0 then
        add(WBF.Format.CountLabel(counts.worldQuests, "World Quest"))
    end
    if counts.achievements > 0 then
        add(WBF.Format.CountLabel(counts.achievements, "Achievement"))
    end
    if counts.appearances > 0 then
        add(WBF.Format.CountLabel(counts.appearances, "Appearance"))
    end
    if (counts.newDecor or 0) > 0 then
        add(WBF.Format.CountLabel(counts.newDecor, "New Decor", "New Decor"))
    end
    if counts.mounts > 0 then
        add(WBF.Format.CountLabel(counts.mounts, "Mount"))
    end
    if counts.pets > 0 then
        add(WBF.Format.CountLabel(counts.pets, "Pet"))
    end
    if (counts.petBattles or 0) > 0 or (counts.petBattlesStarted or 0) > 0 then
        local battles = (counts.petBattles or 0) > 0 and counts.petBattles or counts.petBattlesStarted
        local text = WBF.Format.CountLabel(battles, "Pet Battle")
        if (counts.petWins or 0) + (counts.petLosses or 0) > 0 then
            text = text .. "  ·  " .. (counts.petWins or 0) .. "W / " .. (counts.petLosses or 0) .. "L"
        end
        add(text)
    end
    if (counts.petsCaptured or 0) > 0 then
        add(WBF.Format.CountLabel(counts.petsCaptured, "Pet Captured", "Pets Captured"))
    end
    if (counts.petLevels or 0) > 0 then
        add("Pet Levels " .. WBF.Format.Signed(counts.petLevels))
    end
    if (counts.prey or 0) > 0 then
        local text = WBF.Format.CountLabel(counts.prey, "Prey Hunt")
        if (counts.preyStarted or 0) > 0 then
            text = text .. "  ·  " .. counts.preyStarted .. " in progress"
        end
        add(text)
    elseif (counts.preyStarted or 0) > 0 then
        add(WBF.Format.CountLabel(counts.preyStarted, "Prey Hunt") .. " in progress")
    end
    if counts.reputation ~= 0 then
        add("Reputation " .. WBF.Format.Signed(counts.reputation))
    end
    if counts.renown > 0 then
        add(WBF.Format.CountLabel(counts.renown, "Renown level"))
    end
    if counts.professions > 0 then
        add(WBF.Format.CountLabel(counts.professions, "Profession rank"))
    end
    if (counts.concentrationUsed or 0) > 0 then
        add("Concentration used " .. WBF.Format.Number(counts.concentrationUsed))
    end
    if (counts.knowledge or 0) > 0 then
        add("Knowledge " .. WBF.Format.Signed(counts.knowledge))
    end
    if (counts.recipes or 0) > 0 then
        add(WBF.Format.CountLabel(counts.recipes, "Recipe"))
    end
    if gold and gold ~= 0 then
        add(WBF.Format.Gold(gold, true, "precise"))
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "    ·    ")
end

local WEEKDAY = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MONTH = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- WoW Lua 5.1's math.log is natural log and ignores a base argument.
local function Log10(value)
    return math.log(value) / math.log(10)
end

local function NiceStep(rough)
    if not rough or rough <= 0 then
        return 1
    end
    local exponent = math.floor(Log10(rough))
    local magnitude = 10 ^ exponent
    local fraction = rough / magnitude
    local nice = 10
    if fraction <= 1 then
        nice = 1
    elseif fraction <= 2 then
        nice = 2
    elseif fraction <= 5 then
        nice = 5
    end
    return nice * magnitude
end

-- Smallest 1-2-2.5-5-10 step that is at least `rough`.
-- 2.5 stays off the ones place so a tiny balance is not labeled 2.5.
local function NiceStepAtLeast(rough)
    if not rough or rough <= 0 then
        return 1
    end
    local exponent = math.floor(Log10(rough))
    if exponent < 0 then
        exponent = 0
    end
    local magnitude = 10 ^ exponent
    local fraction = rough / magnitude
    local choices = magnitude >= 10 and { 1, 2, 2.5, 5, 10 } or { 1, 2, 5, 10 }
    for index = 1, #choices do
        if fraction <= choices[index] + 1e-9 then
            return choices[index] * magnitude
        end
    end
    return 10 * magnitude
end

local function CoarserStep(step)
    local exponent = math.floor(Log10(step))
    if exponent < 0 then
        exponent = 0
    end
    local magnitude = 10 ^ exponent
    local fraction = step / magnitude
    if fraction < 1.5 then
        return 2 * magnitude
    elseif magnitude >= 10 and fraction < 2.25 then
        return 2.5 * magnitude
    elseif fraction < 3.5 then
        return 5 * magnitude
    elseif fraction < 7.5 then
        return 10 * magnitude
    end
    return 20 * magnitude
end

-- Axis ticks on a 1-2-5 grid, always including 0 for a non-negative balance.
-- maxLabels is the preferred count, not a hard cap of one extra step.
-- Line charts that should follow a narrow balance range use NiceBounds.
function WBF.Format.NiceTicks(high, maxLabels)
    high = tonumber(high) or 0
    if high < 0 then
        high = 0
    end
    maxLabels = maxLabels or 5
    if maxLabels < 2 then
        maxLabels = 2
    end
    if high == 0 then
        return { 0, 1 }
    end
    local rough = high / (maxLabels - 1)
    local step = NiceStep(rough)
    local function build(stepSize)
        local top = math.ceil((high - 1e-9) / stepSize) * stepSize
        if top < high then
            top = high
        end
        local ticks = {}
        local value = 0
        local guard = 0
        while value <= top + stepSize * 0.001 and guard < 24 do
            guard = guard + 1
            ticks[#ticks + 1] = math.floor(value + 0.5)
            value = value + stepSize
        end
        return ticks
    end
    local ticks = build(step)
    local guard = 0
    while #ticks > maxLabels + 1 and guard < 8 do
        guard = guard + 1
        local exponent = math.floor(Log10(step))
        local magnitude = 10 ^ exponent
        local fraction = step / magnitude
        if fraction < 1.5 then
            step = 2 * magnitude
        elseif fraction < 3.5 then
            step = 5 * magnitude
        elseif fraction < 7.5 then
            step = 10 * magnitude
        else
            step = 20 * magnitude
        end
        ticks = build(step)
    end
    return ticks
end

-- Bounds for a balance-over-time line. The axis follows the visible min and
-- max, with padding, and does not start at zero unless the values sit there.
-- A flat or tiny span gets headroom scaled to the balance so the range cannot
-- collapse. The lower bound stays at 0 unless allowNegative is set.
-- Returns the tick list. The first tick is the axis minimum and the last is
-- the axis maximum.
function WBF.Format.NiceBounds(minValue, maxValue, maxLabels, allowNegative)
    minValue = tonumber(minValue) or 0
    maxValue = tonumber(maxValue) or 0
    if minValue > maxValue then
        minValue, maxValue = maxValue, minValue
    end
    maxLabels = maxLabels or 5
    if maxLabels < 2 then
        maxLabels = 2
    end
    allowNegative = allowNegative and true or false

    local span = maxValue - minValue
    local magnitude = math.max(math.abs(minValue), math.abs(maxValue))
    -- Five percent of the balance, and at least 10. Wide enough that a flat
    -- series is not a zero-height axis, tight enough that a small real move
    -- still uses the plot.
    local minimumWindow = math.max(10, magnitude * 0.05)
    local low, high
    if span < minimumWindow then
        local mid = (minValue + maxValue) / 2
        local half = minimumWindow / 2
        low = mid - half
        high = mid + half
    else
        local pad = span * 0.12
        low = minValue - pad
        high = maxValue + pad
    end
    if not allowNegative and low < 0 then
        low = 0
    end
    if high < maxValue then
        high = maxValue
    end
    if high - low < minimumWindow then
        high = low + minimumWindow
    end
    if high <= low then
        high = low + minimumWindow
    end

    local function build(stepSize)
        local niceLow = math.floor(low / stepSize + 1e-9) * stepSize
        local niceHigh = math.ceil(high / stepSize - 1e-9) * stepSize
        if not allowNegative and niceLow < 0 then
            niceLow = 0
        end
        if niceLow > minValue then
            niceLow = niceLow - stepSize
            if not allowNegative and niceLow < 0 then
                niceLow = 0
            end
        end
        if niceHigh < maxValue then
            niceHigh = niceHigh + stepSize
        end
        if niceHigh <= niceLow then
            niceHigh = niceLow + stepSize
        end
        local ticks = {}
        local value = niceLow
        local guard = 0
        while value <= niceHigh + stepSize * 0.001 and guard < 24 do
            guard = guard + 1
            local units = math.floor(value / stepSize + 0.5)
            ticks[#ticks + 1] = math.floor(units * stepSize + 0.5)
            value = value + stepSize
        end
        return ticks
    end

    local step = NiceStepAtLeast((high - low) / (maxLabels - 1))
    local ticks = build(step)
    local guard = 0
    while #ticks > maxLabels + 1 and guard < 8 do
        guard = guard + 1
        step = CoarserStep(step)
        ticks = build(step)
    end
    return ticks
end

function WBF.Format.ObservedAt(timestamp)
    local parts = date("*t", timestamp)
    local month = MONTH[parts.month] or ""
    return string.format("%d %s %d %02d:%02d", parts.day, month, parts.year, parts.hour, parts.min)
end

-- Readable axis labels. Same-day ranges snap to clock hours. A week uses
-- weekday and date. A month uses the 1st and multiples of 5.
function WBF.Format.TimeTicks(startAt, endAt, maxLabels)
    local ticks = {}
    if type(startAt) ~= "number" or type(endAt) ~= "number" or endAt <= startAt then
        return ticks
    end
    maxLabels = maxLabels or 5
    local span = endAt - startAt
    if span <= 36 * 3600 then
        local hourSteps = { 1, 2, 3, 4, 6, 12 }
        local stepHours = hourSteps[#hourSteps]
        for index = 1, #hourSteps do
            if span / (hourSteps[index] * 3600) <= maxLabels then
                stepHours = hourSteps[index]
                break
            end
        end
        local parts = date("*t", startAt)
        local firstHour = math.ceil(parts.hour / stepHours) * stepHours
        if not (parts.min == 0 and parts.sec == 0) and parts.hour % stepHours == 0 then
            firstHour = parts.hour + stepHours
        end
        local dayShift = 0
        if firstHour >= 24 then
            dayShift = math.floor(firstHour / 24)
            firstHour = firstHour % 24
        end
        parts.hour = firstHour
        parts.min = 0
        parts.sec = 0
        parts.day = parts.day + dayShift
        local cursor = time(parts)
        local nudge = 0
        while cursor < startAt and nudge < 4 do
            nudge = nudge + 1
            local shown = date("*t", cursor)
            shown.hour = shown.hour + stepHours
            shown.min = 0
            shown.sec = 0
            cursor = time(shown)
        end
        local guard = 0
        while cursor <= endAt and guard < 12 do
            guard = guard + 1
            local shown = date("*t", cursor)
            ticks[#ticks + 1] = {
                at = cursor,
                text = string.format("%02d:00", shown.hour),
            }
            shown.hour = shown.hour + stepHours
            shown.min = 0
            shown.sec = 0
            cursor = time(shown)
        end
        return ticks
    end
    if span <= 10 * 86400 then
        local parts = date("*t", startAt)
        parts.hour = 0
        parts.min = 0
        parts.sec = 0
        local cursor = time(parts)
        local guard = 0
        while cursor <= endAt and guard < 12 do
            guard = guard + 1
            local shown = date("*t", cursor)
            local labelAt = cursor
            if labelAt < startAt then
                labelAt = startAt
            end
            ticks[#ticks + 1] = {
                at = labelAt,
                text = (WEEKDAY[shown.wday] or "") .. " " .. shown.day,
            }
            shown.day = shown.day + 1
            shown.hour = 0
            shown.min = 0
            shown.sec = 0
            cursor = time(shown)
        end
        return ticks
    end
    local parts = date("*t", startAt)
    parts.hour = 0
    parts.min = 0
    parts.sec = 0
    local cursor = time(parts)
    local guard = 0
    while cursor <= endAt and guard < 400 do
        guard = guard + 1
        local shown = date("*t", cursor)
        if shown.day == 1 or shown.day % 5 == 0 then
            local labelAt = cursor
            if labelAt < startAt then
                labelAt = startAt
            end
            if labelAt <= endAt then
                ticks[#ticks + 1] = {
                    at = labelAt,
                    text = (MONTH[shown.month] or "") .. " " .. shown.day,
                }
            end
        end
        shown.day = shown.day + 1
        shown.hour = 0
        shown.min = 0
        shown.sec = 0
        cursor = time(shown)
    end
    return ticks
end
