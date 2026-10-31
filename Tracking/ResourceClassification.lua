local _, WBF = ...

-- Player resources are shown. System trackers are Blizzard bookkeeping and
-- stay out of the dashboard, activity, and resource history. Unknown stays
-- visible so a new currency is not dropped just because it is unregistered.
--
-- A name that merely contains "Tracker", "System", or "Weekly Cap" is not
-- enough. System requires a known id, a known internal name, or an internal
-- bookkeeping name corroborated by currency API fields.

WBF.ResourceClassification = {
    PLAYER = "player",
    SYSTEM = "system",
    UNKNOWN = "unknown",
}

local KNOWN_SYSTEM_IDS = {
    -- Add a currency ID here once a live client confirms it.
}

-- Exact internal names seen in live currency data. This list is an extension
-- point, not the classifier. Similar names are still judged from structure
-- plus API fields.
local KNOWN_SYSTEM_NAMES = {
    ["11.0 delves - system - seasonal affix - events active"] = true,
    ["11.0 delves - system - seasonal affix - events maximum"] = true,
    ["11.0 delves - bountiful tracker - delver's journey cap"] = true,
    ["11.0 delves - personal tracker - s1 weekly elise turn-in(hidden)"] = true,
    ["11.0 delves - reputation score"] = true,
    ["11.0 delves - score inside"] = true,
    ["11.0 delves - vendor - bountiful key tracker - cap"] = true,
    ["evergreen delves - tracker - mislaid curiosity - weekly cap"] = true,
}

local INSPECTED = {
    "discovered",
    "isTypeUnused",
    "isShowInBackpack",
    "description",
    "canEarnPerWeek",
    "maxWeeklyQuantity",
}

local function Plain(value)
    if not WBF.Format or not WBF.Format.PlainString then
        if type(value) ~= "string" or value == "" then
            return nil
        end
        return value
    end
    return WBF.Format.PlainString(value)
end

local function Number(value)
    if WBF.Format and WBF.Format.AsNumber then
        return WBF.Format.AsNumber(value)
    end
    return tonumber(value)
end

local function Boolean(value)
    if WBF.Format and WBF.Format.AsBoolean then
        return WBF.Format.AsBoolean(value)
    end
    if value == nil then
        return nil
    end
    return value and true or false
end

local function NormalizeName(name)
    name = Plain(name)
    if not name then
        return ""
    end
    name = name:lower():gsub("%s+", " ")
    return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function FieldsProvided(info)
    for index = 1, #INSPECTED do
        if info[INSPECTED[index]] ~= nil then
            return true
        end
    end
    return false
end

local function Description(info)
    local text = Plain(info.description)
    if not text then
        return nil
    end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text
end

local function WeeklyCap(info)
    if Boolean(info.canEarnPerWeek) == true then
        return true
    end
    local maxWeekly = Number(info.maxWeeklyQuantity)
    return maxWeekly ~= nil and maxWeekly > 0
end

local function Segments(name)
    local parts = {}
    local startAt = 1
    while true do
        local dash = name:find(" - ", startAt, true)
        if not dash then
            local tail = name:sub(startAt):gsub("^%s+", ""):gsub("%s+$", "")
            if tail ~= "" then
                parts[#parts + 1] = tail
            end
            break
        end
        local head = name:sub(startAt, dash - 1):gsub("^%s+", ""):gsub("%s+$", "")
        if head ~= "" then
            parts[#parts + 1] = head
        end
        startAt = dash + 3
    end
    return parts
end

local function RoleSegment(segment)
    local lower = segment:lower()
    if lower == "system" or lower == "tracker" or lower == "score" or lower == "cap" then
        return true
    end
    if lower:find("tracker", 1, true) or lower:find("score", 1, true) then
        return true
    end
    if lower:find("weekly cap", 1, true) or lower:find(" cap", 1, true) then
        return true
    end
    if lower == "events active" or lower == "events maximum" or lower:find("(hidden)", 1, true) then
        return true
    end
    return false
end

-- Segments Blizzard uses for currencies that only store data, such as a race
-- quest ID, a best time in milliseconds or a route record.
local STORAGE_ROLES = {
    ["temp storage"] = true,
    ["scoreboard"] = true,
    ["personal best record"] = true,
}

-- Versioned or evergreen counters, or a dash-separated System/Tracker or
-- storage role. "Bounty Tracker" and "Weekly Cap Token" do not match.
local function BookkeepingName(name)
    if name == "" or not name:find(" - ", 1, true) then
        return false
    end
    local parts = Segments(name)
    if #parts < 2 then
        return false
    end
    local scoped = name:match("^%d+%.%d+") ~= nil or name:match("^evergreen%s") ~= nil or name:match("^evergreen%-") ~= nil
    local roles = 0
    for index = 1, #parts do
        if RoleSegment(parts[index]) then
            roles = roles + 1
        end
    end
    if scoped and roles > 0 then
        return true
    end
    for index = 2, #parts do
        local lower = parts[index]:lower()
        if lower == "system" or lower == "tracker" or STORAGE_ROLES[lower] then
            return true
        end
    end
    return false
end

-- Backpack display, or a discovered currency with a real description that is
-- not an internal weekly counter. isTypeUnused alone is not player evidence:
-- players can mark a real currency unused, and that flag is read elsewhere.
local function PlayerEvidence(info)
    if Boolean(info.isShowInBackpack) == true then
        return true
    end
    local discovered = Boolean(info.discovered)
    local unused = Boolean(info.isTypeUnused)
    local backpack = Boolean(info.isShowInBackpack)
    if discovered == true and unused ~= true and Description(info) and backpack ~= false and not WeeklyCap(info) then
        return true
    end
    return false
end

function WBF.ResourceClassification.ClassifyCurrency(currencyID, info)
    info = type(info) == "table" and info or {}
    local id = Number(currencyID) or Number(info.currencyID)
    local name = NormalizeName(info.name)

    if id and WBF.ResourceMeta and WBF.ResourceMeta.KnowsCurrency and WBF.ResourceMeta.KnowsCurrency(id) then
        return WBF.ResourceClassification.PLAYER, "registry"
    end
    if WBF.Format and WBF.Format.HasInternalMarker and WBF.Format.HasInternalMarker(info.name) then
        return WBF.ResourceClassification.SYSTEM, "internal-marker"
    end
    if id and KNOWN_SYSTEM_IDS[id] then
        return WBF.ResourceClassification.SYSTEM, "known-system-id"
    end
    if name ~= "" and KNOWN_SYSTEM_NAMES[name] then
        return WBF.ResourceClassification.SYSTEM, "known-system-name"
    end

    if not BookkeepingName(name) then
        if Boolean(info.discovered) == true or Boolean(info.isShowInBackpack) == true then
            return WBF.ResourceClassification.PLAYER, "player-currency"
        end
        if name ~= "" and not FieldsProvided(info) then
            return WBF.ResourceClassification.UNKNOWN, "uninspected"
        end
        if name ~= "" then
            return WBF.ResourceClassification.PLAYER, "player-currency"
        end
        return WBF.ResourceClassification.UNKNOWN, "uninspected"
    end

    if not FieldsProvided(info) then
        return WBF.ResourceClassification.UNKNOWN, "bookkeeping-uninspected"
    end
    if PlayerEvidence(info) then
        return WBF.ResourceClassification.UNKNOWN, "bookkeeping-kept"
    end
    return WBF.ResourceClassification.SYSTEM, "bookkeeping-corroborated"
end

local function View(definition, info)
    local view = {
        name = definition and (definition.displayName or definition.name) or nil,
        currencyID = definition and definition.id or nil,
    }
    if type(info) ~= "table" then
        return view
    end
    if Plain(info.name) then
        view.name = Plain(info.name)
    end
    for index = 1, #INSPECTED do
        local key = INSPECTED[index]
        if info[key] ~= nil then
            view[key] = info[key]
        end
    end
    if info.currencyID ~= nil then
        view.currencyID = info.currencyID
    end
    return view
end

function WBF.ResourceClassification.Apply(definition, info)
    if type(definition) ~= "table" or definition.trackingType ~= "currency" then
        return nil
    end
    local key = definition.key
    if type(key) == "string" and not key:match("^currency_%d+$") then
        definition.playerClass = WBF.ResourceClassification.PLAYER
        definition.playerClassReason = "authored"
        return definition.playerClass
    end
    local class, reason = WBF.ResourceClassification.ClassifyCurrency(definition.id, View(definition, info))
    definition.playerClass = class
    definition.playerClassReason = reason
    return class
end

function WBF.ResourceClassification.HidesFromPlayer(definition)
    if type(definition) ~= "table" or definition.trackingType ~= "currency" then
        return false
    end
    if definition.playerClass == WBF.ResourceClassification.SYSTEM then
        return true
    end
    if definition.playerClass == WBF.ResourceClassification.PLAYER or definition.playerClass == WBF.ResourceClassification.UNKNOWN then
        return false
    end
    local key = definition.key
    if type(key) == "string" and not key:match("^currency_%d+$") then
        return false
    end
    local class = WBF.ResourceClassification.ClassifyCurrency(definition.id, {
        name = definition.displayName or definition.name,
        currencyID = definition.id,
    })
    return class == WBF.ResourceClassification.SYSTEM
end

function WBF.ResourceClassification.HidesEvent(event)
    if type(event) ~= "table" then
        return false
    end
    local kind = event.eventType
    local resource = WBF.EventType and WBF.EventType.Resource or "resource"
    if kind ~= resource then
        return false
    end
    local meta = event.meta or {}
    if meta.playerClass == WBF.ResourceClassification.SYSTEM then
        return true
    end
    local definition
    if WBF.Resources and WBF.Resources.Get and meta.resourceKey then
        definition = WBF.Resources.Get(meta.resourceKey)
    end
    if definition then
        return WBF.ResourceClassification.HidesFromPlayer(definition)
    end
    local class = WBF.ResourceClassification.ClassifyCurrency(meta.resourceID, {
        name = meta.name,
        currencyID = meta.resourceID,
    })
    return class == WBF.ResourceClassification.SYSTEM
end
