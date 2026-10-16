local _, WBF = ...

-- Opt-in zone reminders over notebook pages, sections, and blocks.
-- Nothing here alerts unless the player saved a trigger. The visit
-- record remembers that a zone was already handled. It does not copy
-- notebook rows.
WBF.NotebookFyi = {}

local MAX_TRIGGERS = 40
local MAX_NAME = 80
local ZONE_TYPE = 3

local anchored = false
local pending = nil
local maps = nil
local playerMap = nil
local sessionEventShown = {}

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

local function Whole(value)
    local id = tonumber(value)
    if not id or id ~= math.floor(id) or id < 1 then
        return nil
    end
    return id
end

local function IsZoneType(mapType)
    if mapType == nil then
        return true
    end
    local enum = Enum and Enum.UIMapType
    if enum and enum.Zone ~= nil then
        return mapType == enum.Zone
    end
    return mapType == ZONE_TYPE
end

function WBF.NotebookFyi.UseMaps(list)
    maps = nil
    if type(list) ~= "table" then
        return
    end
    maps = {}
    for key, info in pairs(list) do
        if type(info) == "table" then
            local id = Whole(info.mapID) or Whole(key)
            if id then
                maps[id] = info
            end
        end
    end
end

function WBF.NotebookFyi.UsePlayerMap(mapID)
    if mapID == nil then
        playerMap = nil
        return
    end
    playerMap = Whole(mapID)
end

local function MapInfo(mapID)
    mapID = Whole(mapID)
    if not mapID then
        return nil
    end
    if maps and maps[mapID] then
        return maps[mapID]
    end
    if C_Map and C_Map.GetMapInfo then
        local info = WBF.Format.SafeCall(C_Map.GetMapInfo, mapID)
        if type(info) == "table" then
            return info
        end
    end
    return nil
end

function WBF.NotebookFyi.LogicalZone(mapID)
    mapID = Whole(mapID)
    if not mapID then
        return nil
    end
    local seen = {}
    local current = mapID
    for _ = 1, 8 do
        if seen[current] then
            return nil
        end
        seen[current] = true
        local info = MapInfo(current)
        if type(info) ~= "table" then
            return nil
        end
        local name = WBF.Format.PlainString(info.name)
        local id = Whole(info.mapID) or current
        if IsZoneType(info.mapType) and name then
            return { mapID = id, name = name }
        end
        local parent = Whole(info.parentMapID)
        if not parent or parent == current then
            return nil
        end
        current = parent
    end
    return nil
end

function WBF.NotebookFyi.ZoneName(mapID, fallback)
    local zone = WBF.NotebookFyi.LogicalZone(mapID)
    if zone and zone.name then
        return zone.name
    end
    fallback = Trim(fallback or "")
    if fallback ~= "" then
        return fallback
    end
    return "Zone"
end

local function Store()
    local root = WBF.Notebook and WBF.Notebook.Root and WBF.Notebook.Root() or nil
    if not root then
        return nil
    end
    if type(root.fyi) ~= "table" then
        root.fyi = {}
    end
    local fyi = root.fyi
    if type(fyi.triggers) ~= "table" then
        fyi.triggers = {}
    end
    if type(fyi.order) ~= "table" then
        fyi.order = {}
    end
    return fyi
end

local function Visit()
    local root = WBF.Notebook and WBF.Notebook.Root and WBF.Notebook.Root() or nil
    if not root then
        return nil
    end
    if type(root.fyiVisit) ~= "table" then
        root.fyiVisit = {}
    end
    local visit = root.fyiVisit
    visit.zoneMapID = Whole(visit.zoneMapID)
    if type(visit.seen) ~= "table" then
        visit.seen = {}
    end
    return visit
end

local function TargetAlive(kind, id)
    if kind == "page" then
        return WBF.Notebook.GetPage(id) ~= nil
    end
    if kind == "section" then
        return WBF.Notebook.GetSection(id) ~= nil
    end
    if kind == "block" then
        return WBF.Notebook.GetBlock(id) ~= nil
    end
    return false
end

-- An absent assignee means Warband-wide (legacy FYIs remain unchanged).
function WBF.NotebookFyi.CharacterChoices()
    local choices = { { guid = nil, label = "Warband (all characters)" } }
    local characters = WBF.Characters and WBF.Characters.List and WBF.Characters.List() or {}
    table.sort(characters, function(a, b)
        return ((a.name or "") .. (a.realm or "")):lower() < ((b.name or "") .. (b.realm or "")):lower()
    end)
    for _, character in ipairs(characters) do
        if type(character.guid) == "string" and character.guid:sub(1, 7) == "Player-" then
            choices[#choices + 1] = {
                guid = character.guid,
                label = (character.name or "Unknown") .. (character.realm and (" - " .. character.realm) or ""),
            }
        end
    end
    return choices
end

function WBF.NotebookFyi.AssigneeName(guid)
    if not guid then return "Warband" end
    for _, choice in ipairs(WBF.NotebookFyi.CharacterChoices()) do
        if choice.guid == guid then return choice.label end
    end
    return "Unknown character"
end

function WBF.NotebookFyi.VisibleOnCurrent(trigger)
    if not trigger or not trigger.characterGuid then return true end
    return WBF.Characters and WBF.Characters.GetGuid and
        WBF.Characters.GetGuid() == trigger.characterGuid
end

local function CleanTrigger(trigger)
    if type(trigger) ~= "table" then
        return nil
    end
    local kind = trigger.targetKind
    if kind ~= "page" and kind ~= "section" and kind ~= "block" then
        return nil
    end
    if type(trigger.targetId) ~= "string" or not TargetAlive(kind, trigger.targetId) then
        return nil
    end

    -- Triggers saved before event FYIs were zone-only and had no type field.
    local triggerType = trigger.triggerType
    if triggerType ~= "WOW_EVENT" and triggerType ~= "LOGIN" then
        triggerType = "ZONE"
    end
    trigger.triggerType = triggerType

    if triggerType == "LOGIN" then
        trigger.zoneMapID = nil
        trigger.zoneName = nil
        trigger.eventKey = nil
        trigger.eventName = nil
    elseif triggerType == "WOW_EVENT" then
        local info = WBF.EventTriggers and WBF.EventTriggers.FindCatalog and
            WBF.EventTriggers.FindCatalog(trigger.eventKey or trigger.eventName) or nil
        if not info then
            return nil
        end
        trigger.eventKey = info.key
        trigger.eventName = info.name
        trigger.zoneMapID = nil
        trigger.zoneName = nil
        if type(trigger.preparedOccurrenceKey) ~= "string" then
            trigger.preparedOccurrenceKey = nil
        end
        if type(trigger.seenOccurrenceKey) ~= "string" then
            trigger.seenOccurrenceKey = nil
        end
        if type(trigger.hiddenOccurrenceKey) ~= "string" then
            trigger.hiddenOccurrenceKey = nil
        end
    else
        local mapID = Whole(trigger.zoneMapID)
        if not mapID then
            return nil
        end
        trigger.zoneMapID = mapID
        trigger.zoneName = Clip(trigger.zoneName or "", MAX_NAME)
        trigger.eventKey = nil
        trigger.eventName = nil
        trigger.preparedOccurrenceKey = nil
        trigger.seenOccurrenceKey = nil
        trigger.hiddenOccurrenceKey = nil
    end
    if type(trigger.characterGuid) ~= "string" or trigger.characterGuid:sub(1, 7) ~= "Player-" then
        trigger.characterGuid = nil
    end
    trigger.enabled = trigger.enabled ~= false
    return trigger
end

function WBF.NotebookFyi.Ensure()
    local fyi = Store()
    if not fyi then
        return nil
    end
    local db = WBF.Database.Get()
    local kept = {}
    local seenTarget = {}
    local fresh = {}
    local function take(id)
        local trigger = fyi.triggers[id]
        trigger = CleanTrigger(trigger)
        if not trigger or seenTarget[trigger.targetKind .. "\0" .. trigger.targetId] then
            fyi.triggers[id] = nil
            return
        end
        trigger.id = id
        fyi.triggers[id] = trigger
        seenTarget[trigger.targetKind .. "\0" .. trigger.targetId] = true
        kept[id] = true
        fresh[#fresh + 1] = id
    end
    for index = 1, #fyi.order do
        local id = fyi.order[index]
        if type(id) == "string" and not kept[id] then
            take(id)
        end
    end
    for id in pairs(fyi.triggers) do
        if not kept[id] then
            take(id)
        end
    end
    fyi.order = fresh
    local nextId = math.floor(tonumber(db.nextIds.notebookFyi) or 1)
    if nextId < 1 then
        nextId = 1
    end
    for id in pairs(fyi.triggers) do
        local number = tonumber(tostring(id):match("^f(%d+)$"))
        if number and number >= nextId then
            nextId = number + 1
        end
    end
    db.nextIds.notebookFyi = nextId
    Visit()
    return fyi
end

function WBF.NotebookFyi.OnLoad()
    anchored = false
    pending = nil
    WBF.NotebookFyi.Ensure()
end

function WBF.NotebookFyi.Enabled()
    local db = WBF.Database.Get()
    return not (db and db.config and db.config.notebookFyi == false)
end

function WBF.NotebookFyi.SetEnabled(value)
    local db = WBF.Database.Get()
    if not db then
        return false
    end
    if type(db.config) ~= "table" then
        db.config = {}
    end
    db.config.notebookFyi = value and true or false
    return db.config.notebookFyi
end

local function AllocId(fyi)
    local db = WBF.Database.Get()
    local id = math.floor(tonumber(db.nextIds.notebookFyi) or 1)
    if id < 1 then
        id = 1
    end
    local key = "f" .. id
    while fyi.triggers[key] do
        id = id + 1
        key = "f" .. id
    end
    db.nextIds.notebookFyi = id + 1
    return key
end

function WBF.NotebookFyi.ForTarget(kind, id)
    local fyi = WBF.NotebookFyi.Ensure()
    if not fyi or type(id) ~= "string" then
        return nil
    end
    for index = 1, #fyi.order do
        local trigger = fyi.triggers[fyi.order[index]]
        if trigger and trigger.targetKind == kind and trigger.targetId == id then
            return trigger
        end
    end
    return nil
end

function WBF.NotebookFyi.EventTriggerForBlock(blockId)
    local block = WBF.Notebook and WBF.Notebook.GetBlock and WBF.Notebook.GetBlock(blockId) or nil
    if not block then
        return nil
    end
    local direct = WBF.NotebookFyi.ForTarget("block", block.id)
    if direct and direct.triggerType == "WOW_EVENT" then
        return direct
    end
    local section = WBF.Notebook.GetSection(block.sectionId)
    local sectionTrigger = section and WBF.NotebookFyi.ForTarget("section", section.id) or nil
    if sectionTrigger and sectionTrigger.triggerType == "WOW_EVENT" then
        return sectionTrigger
    end
    -- Event recurrence is intentionally scoped to the node or its section.
    -- A page such as "Events" can contain Brewfest, Darkmoon Faire, etc.;
    -- inheriting one page trigger into every section would cross-reset them.
    return nil
end

local function DropTarget(kind, id)
    local fyi = Store()
    if not fyi or type(id) ~= "string" then
        return
    end
    for triggerId, trigger in pairs(fyi.triggers) do
        if type(trigger) == "table" and trigger.targetKind == kind and trigger.targetId == id then
            fyi.triggers[triggerId] = nil
        end
    end
    local fresh = {}
    for index = 1, #fyi.order do
        local triggerId = fyi.order[index]
        if fyi.triggers[triggerId] then
            fresh[#fresh + 1] = triggerId
        end
    end
    fyi.order = fresh
end

function WBF.NotebookFyi.Forget(kind, id)
    if type(id) ~= "string" then
        return
    end
    if kind == "page" then
        local page = WBF.Notebook.GetPage(id)
        if page and type(page.sectionOrder) == "table" then
            for index = 1, #page.sectionOrder do
                WBF.NotebookFyi.Forget("section", page.sectionOrder[index])
            end
        end
        DropTarget("page", id)
        return
    end
    if kind == "section" then
        local section = WBF.Notebook.GetSection(id)
        if section and type(section.blockOrder) == "table" then
            for index = 1, #section.blockOrder do
                DropTarget("block", section.blockOrder[index])
            end
        end
        DropTarget("section", id)
        return
    end
    if kind == "block" then
        DropTarget("block", id)
    end
end

local function BlocksOf(kind, id)
    local blocks = {}
    local function add(block)
        if type(block) == "table" then
            blocks[#blocks + 1] = block
        end
    end
    if kind == "block" then
        add(WBF.Notebook.GetBlock(id))
    elseif kind == "section" then
        local list = WBF.Notebook.Blocks(id) or {}
        for index = 1, #list do
            add(list[index])
        end
    elseif kind == "page" then
        local sections = WBF.Notebook.Sections(id) or {}
        for sectionIndex = 1, #sections do
            local list = WBF.Notebook.Blocks(sections[sectionIndex].id) or {}
            for index = 1, #list do
                add(list[index])
            end
        end
    end
    return blocks
end

local function ZoneFromWaypoint(block)
    if type(block) ~= "table" or block.type ~= "waypoint" then
        return nil
    end
    if block.mapID then
        local zone = WBF.NotebookFyi.LogicalZone(block.mapID)
        if zone then
            return zone
        end
    end
    if type(block.zone) == "string" and WBF.NotebookSmart and WBF.NotebookSmart.ResolveZoneName then
        local mapID = WBF.NotebookSmart.ResolveZoneName(block.zone)
        local zone = WBF.NotebookFyi.LogicalZone(mapID)
        if zone then
            return zone
        end
    end
    return nil
end

function WBF.NotebookFyi.Suggest(kind, id)
    if not TargetAlive(kind, id) then
        return nil
    end
    local found = {}
    local blocks = BlocksOf(kind, id)
    for index = 1, #blocks do
        local zone = ZoneFromWaypoint(blocks[index])
        if zone then
            found[zone.mapID] = zone
        end
    end
    local only = nil
    for _, zone in pairs(found) do
        if only then
            return nil
        end
        only = zone
    end
    return only
end

local function EventCandidate(kind, id)
    if not WBF.EventTriggers or not WBF.EventTriggers.FindCatalog then
        return nil
    end
    if kind == "section" then
        local section = WBF.Notebook.GetSection(id)
        return section and WBF.EventTriggers.FindCatalog(section.title) or nil
    end
    if kind == "page" then
        local page = WBF.Notebook.GetPage(id)
        local direct = page and WBF.EventTriggers.FindCatalog(page.title) or nil
        if direct then
            return direct
        end
        local found = nil
        local sections = page and WBF.Notebook.Sections(page.id) or {}
        for index = 1, #sections do
            local info = WBF.EventTriggers.FindCatalog(sections[index].title)
            if info then
                if found and found.key ~= info.key then
                    return nil
                end
                found = info
            end
        end
        return found
    end
    if kind == "block" then
        local block = WBF.Notebook.GetBlock(id)
        local section = block and WBF.Notebook.GetSection(block.sectionId) or nil
        return section and WBF.EventTriggers.FindCatalog(section.title) or nil
    end
    return nil
end

function WBF.NotebookFyi.SuggestEvent(kind, id)
    local info = TargetAlive(kind, id) and EventCandidate(kind, id) or nil
    if not info then
        return nil
    end
    return { key = info.key, name = info.name }
end

function WBF.NotebookFyi.EventChoices(query, limit)
    limit = limit or 6
    local needle = Trim(query or ""):lower()
    local source = WBF.EventTriggers and WBF.EventTriggers.Catalog and WBF.EventTriggers.Catalog() or {}
    local list = {}
    for index = 1, #source do
        local info = source[index]
        local name = type(info) == "table" and info.name or nil
        local key = type(info) == "table" and info.key or nil
        if type(name) == "string" and type(key) == "string" then
            local matches = needle == "" or name:lower():find(needle, 1, true) or key:lower():find(needle, 1, true)
            if matches then
                list[#list + 1] = { key = key, name = name }
                if #list >= limit then
                    break
                end
            end
        end
    end
    return list
end

function WBF.NotebookFyi.EventMatches(query, chosenName)
    local text = Trim(query or "")
    if text == "" then
        return WBF.NotebookFyi.EventChoices("", 6)
    end
    if type(chosenName) == "string" and text == chosenName then
        return {}
    end
    return WBF.NotebookFyi.EventChoices(text, 6)
end

function WBF.NotebookFyi.ZoneChoices(query, limit)
    limit = limit or 6
    local source = {}
    if WBF.NotebookSmart and WBF.NotebookSmart.ZoneRecords then
        source = WBF.NotebookSmart.ZoneRecords() or {}
    end
    local needle = Trim(query or ""):lower()
    local list = {}
    for index = 1, #source do
        local zone = source[index]
        if type(zone) == "table" and Whole(zone.mapID) and type(zone.name) == "string" then
            local name = zone.name
            local matches = needle == "" or name:lower():find(needle, 1, true)
            if matches and (zone.mapType == nil or IsZoneType(zone.mapType)) then
                list[#list + 1] = { mapID = Whole(zone.mapID), name = name }
                if #list >= limit then
                    break
                end
            end
        end
    end
    return list
end

function WBF.NotebookFyi.ZoneMatches(query, chosenName)
    local text = Trim(query or "")
    if text == "" then
        return {}
    end
    if type(chosenName) == "string" and text == chosenName then
        return {}
    end
    return WBF.NotebookFyi.ZoneChoices(text, 6)
end

function WBF.NotebookFyi.SetupHint(triggerType)
    if triggerType == "WOW_EVENT" then
        return "Appears when that WoW event is active, once per occurrence."
    end
    return "Appears the next time you enter this zone."
end

function WBF.NotebookFyi.PopupLayout(entries)
    local pages = {}
    local order = {}
    if type(entries) ~= "table" then
        return { shared = nil, pages = pages, pageCount = 0 }
    end
    for index = 1, #entries do
        local entry = entries[index]
        if type(entry) == "table" then
            local key = entry.pageId or ""
            local bucket = pages[key]
            if not bucket then
                pages[key] = {
                    pageId = entry.pageId,
                    sectionId = entry.sectionId,
                    first = index,
                }
                order[#order + 1] = key
            elseif bucket.sectionId ~= entry.sectionId then
                bucket.sectionId = nil
            end
        end
    end
    local shared = nil
    if #order == 1 then
        shared = pages[order[1]]
    end
    return { shared = shared, pages = pages, pageCount = #order }
end

function WBF.NotebookFyi.CardActions(entry, layout, index)
    local waypoint = type(entry) == "table" and type(entry.waypoint) == "table"
    local page = false
    if layout and not layout.shared and type(entry) == "table" and entry.pageId then
        local bucket = layout.pages[entry.pageId]
        page = bucket ~= nil and bucket.first == index
    end
    return { waypoint = waypoint, page = page, sheet = page }
end

function WBF.NotebookFyi.SaveZone(target, zoneMapID, zoneName)
    local fyi = WBF.NotebookFyi.Ensure()
    if not fyi or type(target) ~= "table" then
        return nil
    end
    local kind = target.kind
    local id = target.id
    if not TargetAlive(kind, id) then
        return nil
    end
    local zone = WBF.NotebookFyi.LogicalZone(zoneMapID)
    if not zone or zone.mapID ~= Whole(zoneMapID) then
        return nil
    end
    zoneName = Clip(zoneName or zone.name or "", MAX_NAME)
    if zoneName == "" then
        zoneName = zone.name
    end
    local trigger = WBF.NotebookFyi.ForTarget(kind, id)
    if not trigger then
        if #fyi.order >= MAX_TRIGGERS then
            return nil
        end
        local key = AllocId(fyi)
        trigger = {
            id = key,
            targetKind = kind,
            targetId = id,
            enabled = true,
        }
        fyi.triggers[key] = trigger
        fyi.order[#fyi.order + 1] = key
    end
    trigger.triggerType = "ZONE"
    trigger.zoneMapID = zone.mapID
    trigger.zoneName = zoneName
    trigger.eventKey = nil
    trigger.eventName = nil
    trigger.preparedOccurrenceKey = nil
    trigger.seenOccurrenceKey = nil
    trigger.enabled = trigger.enabled ~= false
    return trigger
end

-- Backwards-compatible name for the original zone-only API.
function WBF.NotebookFyi.Save(target, zoneMapID, zoneName)
    return WBF.NotebookFyi.SaveZone(target, zoneMapID, zoneName)
end

local function EventContext(trigger)
    if type(trigger) ~= "table" or trigger.triggerType ~= "WOW_EVENT" or not WBF.Triggers then
        return nil
    end
    local providerTrigger = {
        type = "WOW_EVENT",
        eventKey = trigger.eventKey,
        eventName = trigger.eventName,
    }
    if WBF.Triggers.GetDisplayContext then
        return WBF.Triggers.GetDisplayContext(providerTrigger)
    end
    return nil
end

function WBF.NotebookFyi.SaveEvent(target, eventKey, eventName)
    local fyi = WBF.NotebookFyi.Ensure()
    if not fyi or type(target) ~= "table" then
        return nil
    end
    local kind = target.kind
    local id = target.id
    if not TargetAlive(kind, id) then
        return nil
    end
    local info = WBF.EventTriggers and WBF.EventTriggers.FindCatalog and
        WBF.EventTriggers.FindCatalog(eventKey or eventName) or nil
    if not info then
        return nil
    end
    local trigger = WBF.NotebookFyi.ForTarget(kind, id)
    if not trigger then
        if #fyi.order >= MAX_TRIGGERS then
            return nil
        end
        local key = AllocId(fyi)
        trigger = {
            id = key,
            targetKind = kind,
            targetId = id,
            enabled = true,
        }
        fyi.triggers[key] = trigger
        fyi.order[#fyi.order + 1] = key
    end
    local previousEventKey = trigger.eventKey
    trigger.triggerType = "WOW_EVENT"
    trigger.eventKey = info.key
    trigger.eventName = info.name
    trigger.zoneMapID = nil
    trigger.zoneName = nil
    trigger.enabled = trigger.enabled ~= false
    if previousEventKey ~= info.key then
        trigger.hiddenOccurrenceKey = nil
        trigger.seenOccurrenceKey = nil
        sessionEventShown[trigger.id] = nil
    end

    -- Creating or editing a reminder during an active occurrence should not
    -- unexpectedly clear checklist progress the player has already made.
    local context = EventContext(trigger)
    if context and context.active and context.occurrenceKey then
        trigger.preparedOccurrenceKey = context.occurrenceKey
    end
    return trigger
end

function WBF.NotebookFyi.SaveLogin(target)
    local fyi = WBF.NotebookFyi.Ensure()
    if not fyi or type(target) ~= "table" or not TargetAlive(target.kind, target.id) then return nil end
    local trigger = WBF.NotebookFyi.ForTarget(target.kind, target.id)
    if not trigger then
        if #fyi.order >= MAX_TRIGGERS then return nil end
        local key = AllocId(fyi)
        trigger = { id = key, targetKind = target.kind, targetId = target.id, enabled = true }
        fyi.triggers[key] = trigger
        fyi.order[#fyi.order + 1] = key
    end
    trigger.triggerType = "LOGIN"
    trigger.zoneMapID, trigger.zoneName = nil, nil
    trigger.eventKey, trigger.eventName = nil, nil
    return trigger
end

function WBF.NotebookFyi.ShowLoginFYIs()
    if not WBF.NotebookFyi.Enabled() then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return end
    local fyi = WBF.NotebookFyi.Ensure()
    if not fyi then return end
    local entries, ids = {}, {}
    for _, id in ipairs(fyi.order) do
        local trigger = fyi.triggers[id]
        if trigger and trigger.enabled and trigger.triggerType == "LOGIN" and WBF.NotebookFyi.VisibleOnCurrent(trigger) then
            local described = WBF.NotebookFyi.Describe(trigger)
            if described then
                entries[#entries + 1], ids[#ids + 1] = described, id
            end
        end
    end
    if WBF.CollectionHunts and WBF.CollectionHunts.LoginEntry then
        local huntEntry = WBF.CollectionHunts.LoginEntry()
        if huntEntry then entries[#entries + 1] = huntEntry end
    end
    if #entries > 0 and WBF.UI and WBF.UI.Fyi and WBF.UI.Fyi.Show then
        WBF.UI.Fyi.Show({ contextType = "LOGIN", contextName = "Character reminders", count = #entries, entries = entries, ids = ids })
    end
end

function WBF.NotebookFyi.Remove(id)
    local fyi = Store()
    if not fyi or type(id) ~= "string" or not fyi.triggers[id] then
        return false
    end
    fyi.triggers[id] = nil
    local fresh = {}
    for index = 1, #fyi.order do
        if fyi.order[index] ~= id then
            fresh[#fresh + 1] = fyi.order[index]
        end
    end
    fyi.order = fresh
    return true
end

function WBF.NotebookFyi.RemoveTarget(kind, id)
    local trigger = WBF.NotebookFyi.ForTarget(kind, id)
    if not trigger then
        return false
    end
    return WBF.NotebookFyi.Remove(trigger.id)
end

function WBF.NotebookFyi.SetTriggerEnabled(id, value)
    local fyi = WBF.NotebookFyi.Ensure()
    local trigger = fyi and type(id) == "string" and fyi.triggers[id] or nil
    if not trigger then
        return nil
    end
    trigger.enabled = value and true or false
    return trigger
end

local function FirstLine(text)
    text = Trim(text or "")
    local line = text:match("^[^\r\n]+") or text
    return Clip(line, MAX_NAME)
end

local function LinesFor(block)
    local lines = {}
    if block.type == "text" then
        local text = FirstLine(block.text)
        if text ~= "" then
            lines[1] = { text = text, blockId = block.id }
        end
        return lines
    end
    if block.type == "checklist" then
        local items = type(block.items) == "table" and block.items or {}
        for index = 1, #items do
            local item = items[index]
            if type(item) == "table" then
                local text = FirstLine(item.text or "")
                if text ~= "" then
                    local detail = nil
                    local itemID = nil
                    local icon = nil
                    if WBF.NotebookSmart and WBF.NotebookSmart.ChecklistProgress then
                        local progress = WBF.NotebookSmart.ChecklistProgress(item)
                        if progress then
                            detail = tostring(progress.current or 0) .. " / " .. tostring(progress.target or 0)
                            itemID = progress.kind == "item" and progress.itemID or nil
                            icon = progress.icon
                        end
                    end
                    lines[#lines + 1] = {
                        text = text,
                        detail = detail,
                        blockId = block.id,
                        itemId = item.id,
                        completed = item.done and true or false,
                        itemID = itemID,
                        icon = icon,
                    }
                end
            end
        end
        if #lines == 0 then
            lines[1] = { text = "Checklist", blockId = block.id }
        end
        return lines
    end
    if block.type == "achievement" then
        local progress = WBF.PlanAchievements and WBF.PlanAchievements.Progress(block.achievementID) or nil
        local text = progress and progress.name or ("Achievement " .. tostring(block.achievementID or ""))
        local detail = nil
        if progress and WBF.PlanAchievements.ProgressText then
            detail = WBF.PlanAchievements.ProgressText(progress)
        end
        lines[1] = { text = text, detail = detail, blockId = block.id }
        return lines
    end
    if block.type == "waypoint" then
        local text = FirstLine(block.label or "")
        if text == "" then
            text = FirstLine(block.zone or "Waypoint")
        end
        local detail = nil
        if type(block.x) == "number" and type(block.y) == "number" then
            detail = string.format("%.1f, %.1f", block.x, block.y)
        end
        lines[1] = { text = text, detail = detail, waypoint = block, blockId = block.id }
        return lines
    end
    if block.type == "resource" then
        local view = WBF.Resources and WBF.Resources.NotebookView and WBF.Resources.NotebookView(block.resourceKey) or nil
        local text = view and view.name or FirstLine(block.resourceKey or "Resource")
        local detail = nil
        if view and type(view.amount) == "number" then
            detail = tostring(view.amount)
        end
        lines[1] = {
            text = text,
            detail = detail,
            blockId = block.id,
            icon = view and view.icon or nil,
        }
        return lines
    end
    if block.type == "reference" then
        local described = WBF.NotebookSmart and WBF.NotebookSmart.Describe and WBF.NotebookSmart.Describe(block) or nil
        local text = described and FirstLine(described.title or "") or FirstLine(block.label or "")
        if text == "" then
            text = FirstLine((block.refType or "Reference") .. " " .. tostring(block.refID or ""))
        end
        local itemID = block.refType == "item" and Whole(block.refID) or nil
        lines[1] = {
            text = text,
            detail = described and described.detail or nil,
            blockId = block.id,
            icon = described and described.icon or nil,
            itemID = itemID,
        }
        return lines
    end
    return lines
end

local function LineFor(block)
    local lines = LinesFor(block)
    return lines[1]
end

local function PlaceOf(kind, id)
    local pageId = nil
    local sectionId = nil
    local title = ""
    local context = nil
    if kind == "page" then
        local page = WBF.Notebook.GetPage(id)
        if not page then
            return nil
        end
        pageId = page.id
        title = page.title or "Page"
        context = page.summary
    elseif kind == "section" then
        local section = WBF.Notebook.GetSection(id)
        local page = section and WBF.Notebook.GetPage(section.pageId) or nil
        if not section or not page then
            return nil
        end
        pageId = page.id
        sectionId = section.id
        title = section.title or "Section"
        context = page.title
    elseif kind == "block" then
        local block = WBF.Notebook.GetBlock(id)
        local section = block and WBF.Notebook.GetSection(block.sectionId) or nil
        local page = section and WBF.Notebook.GetPage(section.pageId) or nil
        if not block or not section or not page then
            return nil
        end
        pageId = page.id
        sectionId = section.id
        local line = LineFor(block)
        title = line and line.text or "Note"
        context = (page.title or "Page") .. " · " .. (section.title or "Section")
    else
        return nil
    end
    return {
        pageId = pageId,
        sectionId = sectionId,
        title = title,
        context = context,
    }
end

function WBF.NotebookFyi.Describe(trigger)
    trigger = CleanTrigger(trigger)
    if not trigger then
        return nil
    end
    local place = PlaceOf(trigger.targetKind, trigger.targetId)
    if not place then
        return nil
    end
    local blocks = BlocksOf(trigger.targetKind, trigger.targetId)
    local lines = {}
    local waypoints = {}
    for index = 1, #blocks do
        local block = blocks[index]
        if block.type == "waypoint" then
            waypoints[#waypoints + 1] = block
        end
        local blockLines = LinesFor(block)
        for lineIndex = 1, #blockLines do
            lines[#lines + 1] = blockLines[lineIndex]
        end
    end
    if trigger.targetKind == "block" then
        lines = {}
        local line = blocks[1] and LineFor(blocks[1]) or nil
        if line and line.detail then
            lines[1] = { text = line.detail, blockId = line.blockId or trigger.targetId, itemId = line.itemId }
        end
    end
    local zoneName = nil
    if trigger.triggerType == "ZONE" then
        zoneName = WBF.NotebookFyi.ZoneName(trigger.zoneMapID, trigger.zoneName)
    end
    return {
        triggerId = trigger.id,
        targetKind = trigger.targetKind,
        targetId = trigger.targetId,
        pageId = place.pageId,
        sectionId = place.sectionId,
        title = place.title,
        context = place.context,
        lines = lines,
        waypoint = #waypoints == 1 and waypoints[1] or nil,
        triggerType = trigger.triggerType,
        zoneMapID = trigger.zoneMapID,
        zoneName = zoneName,
        eventKey = trigger.eventKey,
        eventName = trigger.eventName,
        characterGuid = trigger.characterGuid,
        characterName = WBF.NotebookFyi.AssigneeName(trigger.characterGuid),
        eventIcon = trigger.triggerType == "WOW_EVENT" and WBF.EventTriggers and WBF.EventTriggers.Icon and WBF.EventTriggers.Icon(trigger.eventKey) or nil,
    }
end

function WBF.NotebookFyi.List()
    local fyi = WBF.NotebookFyi.Ensure()
    local list = {}
    if not fyi then
        return list
    end
    for index = 1, #fyi.order do
        local trigger = fyi.triggers[fyi.order[index]]
        local described = trigger and WBF.NotebookFyi.Describe(trigger) or nil
        if described then
            list[#list + 1] = {
                id = trigger.id,
                targetKind = trigger.targetKind,
                targetId = trigger.targetId,
                enabled = trigger.enabled and true or false,
                triggerType = trigger.triggerType,
                zoneMapID = trigger.zoneMapID,
                zoneName = described.zoneName,
                eventKey = trigger.eventKey,
                eventName = trigger.eventName,
                characterGuid = trigger.characterGuid,
                characterName = described.characterName,
                title = described.title,
                context = described.context,
                pageId = described.pageId,
                sectionId = described.sectionId,
            }
        end
    end
    return list
end

local function Matching(zoneMapID)
    local fyi = WBF.NotebookFyi.Ensure()
    local list = {}
    if not fyi then
        return list
    end
    for index = 1, #fyi.order do
        local trigger = fyi.triggers[fyi.order[index]]
        if trigger and trigger.enabled and WBF.NotebookFyi.VisibleOnCurrent(trigger) and trigger.triggerType == "ZONE" and trigger.zoneMapID == zoneMapID then
            list[#list + 1] = trigger
        end
    end
    return list
end

local function Group(zone, triggers)
    local entries = {}
    for index = 1, #triggers do
        local described = WBF.NotebookFyi.Describe(triggers[index])
        if described then
            entries[#entries + 1] = described
        end
    end
    if #entries == 0 then
        return nil
    end
    return {
        zoneMapID = zone.mapID,
        zoneName = zone.name,
        count = #entries,
        entries = entries,
    }
end

local function Reveal(zone)
    local visit = Visit()
    if not visit then
        return nil
    end
    local matches = Matching(zone.mapID)
    local unseen = {}
    for index = 1, #matches do
        local trigger = matches[index]
        if visit.seen[trigger.id] ~= true then
            visit.seen[trigger.id] = true
            unseen[#unseen + 1] = trigger
        end
    end
    if not WBF.NotebookFyi.Enabled() or #unseen == 0 then
        return nil
    end
    return Group(zone, unseen)
end

local function ResetEventChecklist(trigger, occurrenceKey)
    if not trigger or trigger.triggerType ~= "WOW_EVENT" or not occurrenceKey then
        return false
    end
    if trigger.preparedOccurrenceKey == occurrenceKey then
        return false
    end
    local changed = false
    local blocks = BlocksOf(trigger.targetKind, trigger.targetId)
    for index = 1, #blocks do
        local block = blocks[index]
        if block.type == "checklist" and type(block.items) == "table" then
            for itemIndex = 1, #block.items do
                local item = block.items[itemIndex]
                if type(item) == "table" and item.completionMode ~= "PERMANENT" and item.done then
                    item.done = false
                    changed = true
                end
            end
        end
    end
    trigger.preparedOccurrenceKey = occurrenceKey
    if changed and WBF.Notebook and WBF.Notebook.RefreshOpen then
        WBF.Notebook.RefreshOpen()
    end
    return changed
end

local function EventGroup(options)
    options = type(options) == "table" and options or {}
    local fyi = WBF.NotebookFyi.Ensure()
    if not fyi then
        return nil
    end
    local noticesEnabled = options.ignoreNoticeSetting or WBF.NotebookFyi.Enabled()
    local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown() or false
    local entries = {}
    local ids = {}
    local names = {}
    local nameSeen = {}
    for index = 1, #fyi.order do
        local trigger = fyi.triggers[fyi.order[index]]
        if trigger and trigger.enabled and WBF.NotebookFyi.VisibleOnCurrent(trigger) and trigger.triggerType == "WOW_EVENT" then
            local context = EventContext(trigger)
            if context and context.active and context.occurrenceKey then
                ResetEventChecklist(trigger, context.occurrenceKey)
                local hidden = trigger.hiddenOccurrenceKey == context.occurrenceKey
                local shownThisSession = sessionEventShown[trigger.id] == context.occurrenceKey
                local eligible = noticesEnabled and not inCombat and
                    (options.includeHidden or not hidden) and
                    (options.force or not shownThisSession)
                if eligible then
                    local described = WBF.NotebookFyi.Describe(trigger)
                    if described then
                        described.eventName = context.eventName or trigger.eventName
                        described.occurrenceKey = context.occurrenceKey
                        described.startStamp = context.startStamp
                        described.endStamp = context.endStamp
                        entries[#entries + 1] = described
                        ids[#ids + 1] = trigger.id
                        local eventName = context.eventName or trigger.eventName or "WoW event"
                        if not nameSeen[eventName] then
                            nameSeen[eventName] = true
                            names[#names + 1] = eventName
                        end
                        sessionEventShown[trigger.id] = context.occurrenceKey
                        -- kept for backwards compatibility/debug visibility; automatic
                        -- suppression now resets each UI reload and explicit hiding uses
                        -- hiddenOccurrenceKey instead.
                        trigger.seenOccurrenceKey = context.occurrenceKey
                    end
                end
            end
        end
    end
    if #entries == 0 then
        return nil
    end
    local title = #names == 1 and names[1] or "Active events"
    return {
        contextType = "WOW_EVENT",
        contextName = title,
        contextIcon = #names == 1 and WBF.EventTriggers and WBF.EventTriggers.Icon and WBF.EventTriggers.Icon(entries[1] and entries[1].eventKey) or nil,
        count = #entries,
        entries = entries,
        ids = ids,
    }
end

function WBF.NotebookFyi.ActiveEventGroup(includeHidden)
    return EventGroup({
        force = true,
        includeHidden = includeHidden and true or false,
        ignoreNoticeSetting = true,
    })
end

function WBF.NotebookFyi.HideOccurrence(ids)
    local fyi = WBF.NotebookFyi.Ensure()
    if not fyi or type(ids) ~= "table" then
        return false
    end
    local changed = false
    for index = 1, #ids do
        local trigger = fyi.triggers[ids[index]]
        if trigger and trigger.triggerType == "WOW_EVENT" then
            local context = EventContext(trigger)
            if context and context.active and context.occurrenceKey then
                trigger.hiddenOccurrenceKey = context.occurrenceKey
                sessionEventShown[trigger.id] = context.occurrenceKey
                changed = true
            end
        end
    end
    return changed
end

function WBF.NotebookFyi.OnEventsChanged()
    -- If the floating event window is already open, keep it as a live view of
    -- what is active *now*. This is separate from notification suppression:
    -- events that were already shown this session still need to disappear at
    -- their exact end time while other events remain visible.
    if WBF.UI and WBF.UI.Fyi and WBF.UI.Fyi.SyncActiveEvents and WBF.UI.Fyi.SyncActiveEvents() then
        return
    end
    local group = EventGroup()
    if group and WBF.UI and WBF.UI.Fyi and WBF.UI.Fyi.Show then
        WBF.UI.Fyi.Show(group)
    end
end

local function CurrentMap()
    if playerMap ~= nil then
        return playerMap
    end
    if C_Map and C_Map.GetBestMapForUnit then
        return Whole(WBF.Format.SafeCall(C_Map.GetBestMapForUnit, "player"))
    end
    return nil
end

local function InCombat(flag)
    if flag ~= nil then
        return flag and true or false
    end
    return type(InCombatLockdown) == "function" and InCombatLockdown() or false
end

function WBF.NotebookFyi.Observe(mapID, inCombat)
    local zone = WBF.NotebookFyi.LogicalZone(mapID)
    if not zone then
        return nil
    end
    local visit = Visit()
    if not visit then
        return nil
    end
    local combat = InCombat(inCombat)
    if not anchored then
        anchored = true
        if visit.zoneMapID ~= zone.mapID then
            visit.zoneMapID = zone.mapID
            visit.seen = {}
        end
        pending = nil
        return nil
    end
    if visit.zoneMapID ~= zone.mapID then
        visit.zoneMapID = zone.mapID
        visit.seen = {}
        pending = nil
        if combat then
            pending = zone.mapID
            return nil
        end
        return Reveal(zone)
    end
    if pending == zone.mapID and not combat then
        pending = nil
        return Reveal(zone)
    end
    return nil
end

function WBF.NotebookFyi.Flush()
    if not pending then
        return nil
    end
    local wanted = pending
    pending = nil
    local zone = WBF.NotebookFyi.LogicalZone(CurrentMap())
    if not zone or zone.mapID ~= wanted then
        return nil
    end
    local visit = Visit()
    if visit and visit.zoneMapID ~= zone.mapID then
        visit.zoneMapID = zone.mapID
        visit.seen = {}
    end
    return Reveal(zone)
end

function WBF.NotebookFyi.HideVisit(ids)
    local visit = Visit()
    if not visit or type(ids) ~= "table" then
        return false
    end
    for index = 1, #ids do
        local id = ids[index]
        if type(id) == "string" then
            visit.seen[id] = true
        end
    end
    return true
end

function WBF.NotebookFyi.Seen(id)
    local visit = Visit()
    return visit and visit.seen[id] == true or false
end

function WBF.NotebookFyi.VisitZone()
    local visit = Visit()
    return visit and visit.zoneMapID or nil
end

local function Deliver(group)
    if not group then
        return
    end
    if WBF.UI and WBF.UI.Fyi and WBF.UI.Fyi.Show then
        WBF.UI.Fyi.Show(group)
    end
end

function WBF.NotebookFyi.OnZone()
    Deliver(WBF.NotebookFyi.Observe(CurrentMap()))
end

function WBF.NotebookFyi.OnRegen()
    Deliver(WBF.NotebookFyi.Flush())
    WBF.NotebookFyi.OnEventsChanged()
end

function WBF.NotebookFyi.Register(bus)
    if not bus or not bus.On then
        return
    end
    local function onZone()
        WBF.NotebookFyi.OnZone()
    end
    bus:On("ZONE_CHANGED_NEW_AREA", onZone)
    bus:On("ZONE_CHANGED", onZone)
    bus:On("ZONE_CHANGED_INDOORS", onZone)
    bus:On("PLAYER_ENTERING_WORLD", onZone)
    local loginShown = false
    bus:On("PLAYER_ENTERING_WORLD", function()
        if loginShown then return end
        loginShown = true
        if C_Timer and C_Timer.After then
            C_Timer.After(6, function() WBF.NotebookFyi.ShowLoginFYIs() end)
        else
            WBF.NotebookFyi.ShowLoginFYIs()
        end
    end)
end
