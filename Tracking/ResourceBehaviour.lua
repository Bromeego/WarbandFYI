local _, WBF = ...

-- Record state for accuracy. Surface events for meaning.
-- Currencies keep a ledger. Progression is advancement. A regenerating meter
-- updates its current value without turning passive ticks into activity.
-- Collectibles stay on the collection events, not the currency ledger.

WBF.ResourceBehaviour = {
    CURRENCY = "currency",
    PROGRESSION = "progression",
    REGENERATING_METER = "regenerating_meter",
    COLLECTIBLE = "collectible",
}

local PROFESSION_WORDS = {
    "alchemy",
    "blacksmithing",
    "enchanting",
    "engineering",
    "herbalism",
    "inscription",
    "jewelcrafting",
    "leatherworking",
    "mining",
    "skinning",
    "tailoring",
    "cooking",
    "fishing",
}

local function AsText(value)
    if type(value) ~= "string" then
        return ""
    end
    return value
end

local function Recharge(info)
    if type(info) ~= "table" then
        return false
    end
    local cycle = tonumber(info.rechargingCycleDurationMS) or tonumber(info.rechargingCycleDuration) or 0
    local perCycle = tonumber(info.rechargingAmountPerCycle) or tonumber(info.rechargingAmount) or 0
    return cycle > 0 or perCycle > 0
end

function WBF.ResourceBehaviour.Classify(info, name)
    if Recharge(info) then
        return WBF.ResourceBehaviour.REGENERATING_METER
    end
    local lower = AsText(name):lower()
    if lower:find("concentration", 1, true) then
        return WBF.ResourceBehaviour.REGENERATING_METER
    end
    if lower:find("knowledge", 1, true) then
        for index = 1, #PROFESSION_WORDS do
            if lower:find(PROFESSION_WORDS[index], 1, true) then
                return WBF.ResourceBehaviour.PROGRESSION
            end
        end
    end
    return WBF.ResourceBehaviour.CURRENCY
end

function WBF.ResourceBehaviour.SubjectName(name)
    name = AsText(name)
    if name == "" then
        return "Profession"
    end
    local stripped = name:gsub("%s+[Cc]oncentration$", ""):gsub("%s+[Kk]nowledge$", "")
    if stripped == "" then
        return name
    end
    return stripped
end

local function DefinitionName(definition, event)
    if type(definition) == "table" then
        if type(definition.displayName) == "string" and definition.displayName ~= "" then
            return definition.displayName
        end
        if type(definition.name) == "string" and definition.name ~= "" then
            return definition.name
        end
    end
    local meta = event and event.meta or nil
    if type(meta) == "table" then
        if type(meta.name) == "string" and meta.name ~= "" then
            return meta.name
        end
    end
    return event and event.text or ""
end

function WBF.ResourceBehaviour.Of(definition, event)
    if type(definition) == "table" and type(definition.behaviour) == "string" and definition.behaviour ~= "" and definition.behaviour ~= WBF.ResourceBehaviour.CURRENCY then
        return definition.behaviour
    end
    local meta = event and event.meta or nil
    if type(meta) == "table" and type(meta.behaviour) == "string" and meta.behaviour ~= "" and meta.behaviour ~= WBF.ResourceBehaviour.CURRENCY then
        return meta.behaviour
    end
    local classified = WBF.ResourceBehaviour.Classify(nil, DefinitionName(definition, event))
    if classified ~= WBF.ResourceBehaviour.CURRENCY then
        return classified
    end
    if type(definition) == "table" and definition.behaviour == WBF.ResourceBehaviour.CURRENCY then
        return WBF.ResourceBehaviour.CURRENCY
    end
    return WBF.ResourceBehaviour.CURRENCY
end

function WBF.ResourceBehaviour.SkipsCurrencyBoard(definition)
    local behaviour = WBF.ResourceBehaviour.Of(definition, nil)
    return behaviour == WBF.ResourceBehaviour.REGENERATING_METER or behaviour == WBF.ResourceBehaviour.PROGRESSION
end

local function IsResourceEvent(event)
    if type(event) ~= "table" then
        return false
    end
    if WBF.EventType and event.eventType == WBF.EventType.Resource then
        return true
    end
    return event.eventType == "resource"
end

function WBF.ResourceBehaviour.HidesActivity(event)
    if type(event) ~= "table" then
        return false
    end
    if WBF.ResourceClassification and WBF.ResourceClassification.HidesEvent(event) then
        return true
    end
    if type(event.meta) == "table" and event.meta.surface == false then
        return true
    end
    if not IsResourceEvent(event) then
        return false
    end
    local definition
    if WBF.Resources and WBF.Resources.Get and type(event.meta) == "table" then
        definition = WBF.Resources.Get(event.meta.resourceKey)
    end
    local behaviour = WBF.ResourceBehaviour.Of(definition, event)
    if behaviour == WBF.ResourceBehaviour.REGENERATING_METER then
        return true
    end
    if behaviour == WBF.ResourceBehaviour.PROGRESSION and (event.delta or 0) <= 0 then
        return true
    end
    return false
end

function WBF.ResourceBehaviour.ApplyResourceCounts(bucket, event)
    if not IsResourceEvent(event) or type(bucket) ~= "table" then
        return false
    end
    local definition
    if WBF.Resources and WBF.Resources.Get and type(event.meta) == "table" then
        definition = WBF.Resources.Get(event.meta.resourceKey)
    end
    local behaviour = WBF.ResourceBehaviour.Of(definition, event)
    local delta = event.delta or 0
    if behaviour == WBF.ResourceBehaviour.PROGRESSION and delta > 0 then
        bucket.knowledge = (bucket.knowledge or 0) + delta
        return true
    end
    if behaviour == WBF.ResourceBehaviour.REGENERATING_METER and delta < 0 then
        bucket.concentrationUsed = (bucket.concentrationUsed or 0) + math.abs(delta)
        return true
    end
    return false
end
