local _, WBF = ...

-- Meaningful world activity: open-world rare kills, fishing catches, and
-- gathering nodes. Ordinary mobs, missed fishing casts, and materials that
-- arrive from mail, vendors, banks, or mob drops are not counted.
--
-- Midnight does not give addons COMBAT_LOG_EVENT_UNFILTERED. A rare is
-- counted only when its identity was read from a visible unit token
-- (nameplate, target, focus, or mouseover) as rare or rareelite, and credit
-- is then established by a tap that is explicitly not denied or by unlocked
-- loot from that same spawn GUID. Unknown credit is not a kill.
--
-- A fishing catch is one loot window where IsFishingLoot() is true. Items
-- inside that window belong to the same catch.
--
-- A mining, herbalism, or skinning node requires the player's own successful
-- cast to be reported as that gathering profession, plus a matching loot
-- source GUID (object for mining and herbalism, creature for skinning).
-- Lumber is not a profession. A lumber node is one GameObject loot source
-- that contains at least one registered lumber item. A gathering cast is
-- not required, and other items in that loot do not cancel the node. The
-- first loot read keeps that GameObject source if a later autoloot read
-- loses GetLootSourceInfo().
-- Skinning is not inferred from leather. If the profession APIs do not
-- classify the cast, the skinning count stays at zero.

WBF.WorldActivity = {}

local SOURCE_TTL = 600
local COALESCE_SECONDS = 60
local MAX_ROWS = 2500
local MAX_SOURCES = 100
local FISH_FINGERPRINT_TTL = 5
local GATHER_WINDOW = 3
local RARE_TTL = 180
local MAX_SEEN = 40
local MAX_FISH_ITEMS = 16
local MAX_NODE_ITEMS = 8
local ENCOUNTER_TAIL = 20

local KINDS = {
    fishing = true,
    mining = true,
    herbalism = true,
    lumber = true,
    skinning = true,
}

-- Housing lumber, one item per expansion family. A new lumber type is added
-- here; it is never inferred from the word "lumber" in an item name.
local LUMBER_ITEMS = {
    [245586] = true, -- Ironwood Lumber
    [242691] = true, -- Olemba Lumber
    [251762] = true, -- Coldwind Lumber
    [251764] = true, -- Ashwood Lumber
    [251763] = true, -- Bamboo Lumber
    [251766] = true, -- Shadowmoon Lumber
    [251767] = true, -- Fel-Touched Lumber
    [251768] = true, -- Darkpine Lumber
    [251772] = true, -- Arden Lumber
    [251773] = true, -- Dragonpine Lumber
    [248012] = true, -- Dornic Fir Lumber
    [256963] = true, -- Thalassian Lumber
}

WBF.WorldActivity.LumberItems = LUMBER_ITEMS

local seenRares = {}
local watched = {}
local pendingCast = nil
local openLoot = nil
local windowOpen = false
local encounterUntil = 0
local tracedRare = {}
local lastNote = {}

local function Now()
    return WBF.Time.Now()
end

local function IsPlainTable(value)
    if WBF.Format.IsSecret(value) then
        return false
    end
    if issecrettable and issecrettable(value) then
        return false
    end
    return type(value) == "table"
end

local function Packed(func, ...)
    if type(func) ~= "function" then
        return nil
    end
    local ok, values = pcall(function(...)
        return { func(...) }
    end, ...)
    if not ok or not IsPlainTable(values) then
        return nil
    end
    return values
end

function WBF.WorldActivity.SourceKind(guid)
    if type(guid) ~= "string" then
        return nil
    end
    if guid:sub(1, 9) == "Creature-" or guid:sub(1, 8) == "Vehicle-" then
        return "creature"
    end
    if guid:sub(1, 11) == "GameObject-" then
        return "object"
    end
    if guid:sub(1, 5) == "Item-" then
        return "item"
    end
    return nil
end

function WBF.WorldActivity.NpcID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local id = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)")
        or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    return tonumber(id)
end

function WBF.WorldActivity.ItemIDFromLink(link)
    if type(link) ~= "string" then
        return nil
    end
    return tonumber(link:match("item:(%d+)"))
end

function WBF.WorldActivity.IsLumber(itemID)
    itemID = tonumber(itemID)
    return itemID ~= nil and LUMBER_ITEMS[itemID] == true
end

function WBF.WorldActivity.ProfessionKind(professionID)
    professionID = tonumber(professionID)
    if not professionID then
        return nil
    end
    local enum = Enum and Enum.Profession
    if enum then
        if professionID == enum.Herbalism then
            return "herbalism"
        end
        if professionID == enum.Mining then
            return "mining"
        end
        if professionID == enum.Skinning then
            return "skinning"
        end
        return nil
    end
    if professionID == 4 then
        return "herbalism"
    end
    if professionID == 6 then
        return "mining"
    end
    if professionID == 11 then
        return "skinning"
    end
    return nil
end

function WBF.WorldActivity.KindFromName(name)
    if type(name) ~= "string" then
        return nil
    end
    local lower = name:lower()
    if lower:find("herbalism", 1, true) then
        return "herbalism"
    end
    if lower:find("mining", 1, true) then
        return "mining"
    end
    if lower:find("skinning", 1, true) then
        return "skinning"
    end
    return nil
end

-- Tradegoods subclasses used only after a cast has already been confirmed as
-- a gathering operation and the profession id itself was not readable.
-- Leather is intentionally absent: skinning is never inferred from items.
function WBF.WorldActivity.ItemGatherKind(classID, subClassID)
    classID = tonumber(classID)
    subClassID = tonumber(subClassID)
    if classID ~= 7 then
        return nil
    end
    if subClassID == 7 then
        return "mining"
    end
    if subClassID == 9 then
        return "herbalism"
    end
    return nil
end

function WBF.WorldActivity.DecideRare(observation)
    observation = type(observation) == "table" and observation or {}
    if observation.blockedInstance or observation.encounterBlocked or observation.alreadyCounted then
        return false, "blocked"
    end
    if observation.classification ~= "rare" and observation.classification ~= "rareelite" then
        return false, "classification"
    end
    if WBF.WorldActivity.SourceKind(observation.guid) ~= "creature" then
        return false, "source"
    end
    if observation.lootCredit == true then
        return true, "loot"
    end
    if observation.dead == true and observation.tapDenied == false then
        return true, "credit"
    end
    return false, "credit"
end

local function FirstGuid(slot)
    local list = slot and slot.sources
    if type(list) ~= "table" then
        return nil
    end
    local found = nil
    for index = 1, #list do
        local guid = list[index] and list[index].guid
        if type(guid) == "string" and guid ~= "" then
            if found and found ~= guid then
                return nil
            end
            found = guid
        end
    end
    return found
end

local function SourceFresh(sources, guid, now)
    local at = sources and sources[guid]
    return type(at) == "number" and at <= now and (now - at) < SOURCE_TTL
end

local function CopyItem(slot)
    local quantity = slot.quantity
    if type(quantity) ~= "number" or quantity < 1 then
        quantity = 1
    end
    return {
        itemID = slot.itemID,
        name = slot.name,
        quantity = quantity,
        quality = slot.quality,
        classID = slot.classID,
        subClassID = slot.subClassID,
    }
end

local function GroupSlots(slots)
    local groups = {}
    for index = 1, #slots do
        local slot = slots[index]
        if type(slot) == "table" and not slot.money and slot.itemID then
            local guid = FirstGuid(slot)
            if guid then
                local group = groups[guid]
                if not group then
                    group = { items = {} }
                    groups[guid] = group
                end
                group.items[#group.items + 1] = CopyItem(slot)
            end
        end
    end
    return groups
end

local function HasLumber(items)
    for index = 1, #items do
        if WBF.WorldActivity.IsLumber(items[index].itemID) then
            return true
        end
    end
    return false
end

local function LumberOnly(items)
    local kept = {}
    for index = 1, #items do
        if WBF.WorldActivity.IsLumber(items[index].itemID) then
            kept[#kept + 1] = items[index]
        end
    end
    return kept
end

local function HasAnySource(slots)
    if type(slots) ~= "table" then
        return false
    end
    for index = 1, #slots do
        if FirstGuid(slots[index]) then
            return true
        end
    end
    return false
end

-- Autoloot can clear GetLootSourceInfo() before LOOT_OPENED. Keep the source
-- GUIDs captured on the earlier read for that same loot window.
function WBF.WorldActivity.PreserveLootSources(previous, fresh)
    if type(fresh) ~= "table" then
        return type(previous) == "table" and previous or fresh
    end
    if type(previous) ~= "table" then
        return fresh
    end
    if fresh.fishing ~= true then
        fresh.fishing = previous.fishing == true
    end
    local freshSlots = type(fresh.slots) == "table" and fresh.slots or {}
    local previousSlots = type(previous.slots) == "table" and previous.slots or {}
    fresh.slots = freshSlots
    if #freshSlots == 0 and #previousSlots > 0 then
        fresh.slots = previousSlots
        return fresh
    end
    if not HasAnySource(freshSlots) and HasAnySource(previousSlots) then
        fresh.slots = previousSlots
    end
    return fresh
end

local function AgreedItemKind(items)
    local kind = nil
    for index = 1, #items do
        local itemKind = WBF.WorldActivity.ItemGatherKind(items[index].classID, items[index].subClassID)
        if itemKind then
            if kind and kind ~= itemKind then
                return nil
            end
            kind = itemKind
        end
    end
    return kind
end

local function Signature(items)
    local parts = {}
    for index = 1, #items do
        local item = items[index]
        parts[#parts + 1] = tostring(item.itemID or 0) .. "x" .. tostring(item.quantity or 1)
    end
    table.sort(parts)
    if #parts == 0 then
        return "none"
    end
    return table.concat(parts, "|")
end

local function ItemList(items)
    local parts = {}
    for index = 1, #items do
        local item = items[index]
        local name = type(item.name) == "string" and item.name ~= "" and item.name or "?"
        parts[#parts + 1] = tostring(item.itemID or "?") .. " " .. name .. " x" .. tostring(item.quantity or 1)
    end
    if #parts == 0 then
        return "none"
    end
    return table.concat(parts, ", ")
end

local function SourceTypeLabel(sourceKind)
    if sourceKind == "object" then
        return "GameObject"
    end
    if sourceKind == "creature" then
        return "Creature"
    end
    if sourceKind == "item" then
        return "Item"
    end
    return "none"
end

local function CastLabel(pending, pendingAge)
    if type(pending) ~= "table" or type(pendingAge) ~= "number" or pendingAge > GATHER_WINDOW then
        return "none"
    end
    if pending.spellID then
        local label = "spell " .. tostring(pending.spellID)
        if pending.kind then
            label = label .. " " .. pending.kind
        end
        return label
    end
    if pending.kind then
        return pending.kind
    end
    if pending.gathering then
        return "gathering"
    end
    return "yes"
end

local function LumberCandidate(guid, sourceKind, items, pending, pendingAge, recorded, reason)
    local matched = HasLumber(items)
    local lines = {
        "Gathering candidate",
        "Source: " .. (guid or "none"),
        "Type: " .. SourceTypeLabel(sourceKind),
        "Items: " .. ItemList(items),
        "Lumber match: " .. (matched and "yes" or "no"),
        "Recent gather cast: " .. CastLabel(pending, pendingAge),
        "Classification: " .. (recorded and "LUMBER" or "rejected"),
    }
    if not recorded then
        lines[#lines + 1] = "Reason: " .. (reason or "ignored")
    end
    if recorded then
        lines[#lines + 1] = "Dedupe: new"
    elseif reason == "already recorded" then
        lines[#lines + 1] = "Dedupe: duplicate"
    else
        lines[#lines + 1] = "Dedupe: rejected"
    end
    lines[#lines + 1] = "Node recorded: " .. (recorded and "yes" or "no")
    return table.concat(lines, "\n")
end

local function LumberCopies(slots)
    local items = {}
    if type(slots) ~= "table" then
        return items
    end
    for index = 1, #slots do
        local slot = slots[index]
        if type(slot) == "table" and not slot.money and WBF.WorldActivity.IsLumber(slot.itemID) then
            items[#items + 1] = CopyItem(slot)
        end
    end
    return items
end

function WBF.WorldActivity.DecideLoot(loot, state)
    local result = { fishing = nil, nodes = {}, notes = {} }
    if type(loot) ~= "table" then
        return result
    end
    state = type(state) == "table" and state or {}
    local now = state.now or 0
    local slots = type(loot.slots) == "table" and loot.slots or {}

    if loot.fishing == true then
        if #slots < 1 then
            result.notes[#result.notes + 1] = "Fishing catch: items=0 counted=false"
            return result
        end
        local guid = nil
        local items = {}
        for index = 1, #slots do
            local slot = slots[index]
            if type(slot) == "table" then
                local slotGuid = FirstGuid(slot)
                if not guid and slotGuid then
                    guid = slotGuid
                end
                if slot.itemID and not slot.money then
                    items[#items + 1] = CopyItem(slot)
                end
            end
        end
        if guid and SourceFresh(state.sources, guid, now) then
            result.notes[#result.notes + 1] = "Fishing catch: sourceGUID=" .. guid .. " counted=false"
            return result
        end
        local signature = Signature(items)
        if not guid and state.fishingKey == signature and type(state.fishingAt) == "number" and state.fishingAt <= now and (now - state.fishingAt) < FISH_FINGERPRINT_TTL then
            result.notes[#result.notes + 1] = "Fishing catch: duplicate counted=false"
            return result
        end
        result.fishing = { sourceGUID = guid, items = items, signature = signature }
        result.notes[#result.notes + 1] = "Fishing catch: items=" .. tostring(#items) .. " counted=true"
        return result
    end

    local pending = state.pending
    local pendingAge = nil
    if type(pending) == "table" and type(pending.at) == "number" and pending.at <= now then
        pendingAge = now - pending.at
    end
    local pendingKind = nil
    if pendingAge and pendingAge <= GATHER_WINDOW then
        pendingKind = pending.kind or pending.itemKind
    end

    if loot.fromItem == true then
        local carried = LumberCopies(slots)
        if #carried > 0 then
            result.notes[#result.notes + 1] = LumberCandidate(nil, nil, carried, pending, pendingAge, false, "item container")
        else
            result.notes[#result.notes + 1] = "Gather detected: type=none counted=false"
        end
        return result
    end

    local groups = GroupSlots(slots)
    for guid, group in pairs(groups) do
        local sourceKind = WBF.WorldActivity.SourceKind(guid)
        local kind = nil
        local itemCount = #group.items
        local seen = SourceFresh(state.sources, guid, now)
        if seen then
            kind = nil
        elseif pendingKind == "mining" or pendingKind == "herbalism" then
            if sourceKind == "object" then
                kind = pendingKind
            end
        elseif pendingKind == "skinning" then
            if sourceKind == "creature" then
                kind = "skinning"
            end
        elseif pendingAge and pendingAge <= GATHER_WINDOW and state.allowItemKind and not pendingKind and sourceKind == "object" then
            kind = AgreedItemKind(group.items)
        end
        if not kind and not seen and sourceKind == "object" and HasLumber(group.items) then
            kind = "lumber"
        end
        local lumber = HasLumber(group.items)
        if kind == "lumber" or (lumber and not kind) then
            local reason = nil
            if kind ~= "lumber" then
                if seen then
                    reason = "already recorded"
                else
                    reason = "not a GameObject"
                end
            end
            result.notes[#result.notes + 1] = LumberCandidate(guid, sourceKind, group.items, pending, pendingAge, kind == "lumber", reason)
        end
        if kind then
            result.nodes[#result.nodes + 1] = {
                kind = kind,
                sourceGUID = guid,
                items = kind == "lumber" and LumberOnly(group.items) or nil,
                itemCount = itemCount,
            }
            if kind ~= "lumber" then
                result.notes[#result.notes + 1] = "Gather detected: type=" .. kind .. " sourceGUID=" .. guid .. " items=" .. tostring(itemCount) .. " counted=true"
            end
        elseif pendingKind and not lumber then
            result.notes[#result.notes + 1] = "Gather detected: type=" .. tostring(pendingKind) .. " sourceGUID=" .. guid .. " items=" .. tostring(itemCount) .. " counted=false"
        end
    end
    local loose = {}
    for index = 1, #slots do
        local slot = slots[index]
        if type(slot) == "table" and not slot.money and WBF.WorldActivity.IsLumber(slot.itemID) and not FirstGuid(slot) then
            loose[#loose + 1] = CopyItem(slot)
        end
    end
    if #loose > 0 then
        result.notes[#result.notes + 1] = LumberCandidate(nil, nil, loose, pending, pendingAge, false, "no GameObject loot source")
    end
    return result
end

local function Ensure(session)
    if type(session.world) ~= "table" then
        session.world = {}
    end
    local world = session.world
    if type(world.rows) ~= "table" then
        world.rows = {}
    end
    if type(world.sources) ~= "table" then
        world.sources = {}
    end
    return world
end

local function MergeStoredItems(row, items, limit)
    if type(items) ~= "table" then
        return
    end
    row.items = row.items or {}
    for index = 1, #items do
        local item = items[index]
        local id = item and item.itemID
        local qty = item and item.quantity or 1
        if type(id) == "number" and id > 0 and type(qty) == "number" and qty > 0 then
            local existing = row.items[id]
            if existing then
                existing.q = (existing.q or 0) + qty
                if type(item.name) == "string" and item.name ~= "" then
                    existing.name = item.name
                end
            else
                local count = 0
                for _ in pairs(row.items) do
                    count = count + 1
                end
                if count >= limit then
                    row.other = (row.other or 0) + qty
                else
                    row.items[id] = {
                        name = item.name,
                        q = qty,
                        quality = item.quality,
                    }
                end
            end
        end
    end
end

local function FindOpenRow(rows, guid, kind, now)
    for index = #rows, 1, -1 do
        local row = rows[index]
        if row.guid == guid and row.kind == kind and type(row.at) == "number" and row.at <= now and (now - row.at) < COALESCE_SECONDS then
            return row
        end
    end
    return nil
end

function WBF.WorldActivity.RememberSource(session, guid, now)
    if type(session) ~= "table" or type(guid) ~= "string" or guid == "" or type(now) ~= "number" then
        return false
    end
    local world = Ensure(session)
    local sources = world.sources
    if SourceFresh(sources, guid, now) then
        return false
    end
    sources[guid] = now
    local keys = {}
    for key, at in pairs(sources) do
        if type(at) ~= "number" or at > now or (now - at) >= SOURCE_TTL then
            sources[key] = nil
        else
            keys[#keys + 1] = key
        end
    end
    if #keys > MAX_SOURCES then
        table.sort(keys, function(a, b)
            return (sources[a] or 0) < (sources[b] or 0)
        end)
        local extra = #keys - MAX_SOURCES
        for index = 1, extra do
            if keys[index] ~= guid then
                sources[keys[index]] = nil
            end
        end
    end
    return true
end

function WBF.WorldActivity.AddCount(session, characterGUID, now, kind, items, mapID, quiet)
    if type(session) ~= "table" or not KINDS[kind] or type(now) ~= "number" then
        return false
    end
    if type(characterGUID) ~= "string" or characterGUID == "" then
        return false
    end
    local world = Ensure(session)
    local rows = world.rows
    local row = FindOpenRow(rows, characterGUID, kind, now)
    if not row and #rows >= MAX_ROWS then
        for index = #rows, 1, -1 do
            local candidate = rows[index]
            if candidate.guid == characterGUID and candidate.kind == kind then
                row = candidate
                break
            end
        end
    end
    if not row then
        row = { at = now, guid = characterGUID, kind = kind, n = 0 }
        rows[#rows + 1] = row
    end
    row.n = (row.n or 0) + 1
    if type(mapID) == "number" then
        row.mapID = mapID
    end
    local limit = kind == "fishing" and MAX_FISH_ITEMS or MAX_NODE_ITEMS
    if kind == "fishing" or kind == "lumber" then
        MergeStoredItems(row, items, limit)
    end
    if not quiet and WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
    if not quiet and WBF.UI and WBF.UI.RequestRefresh then
        WBF.UI.RequestRefresh()
    end
    return true
end

function WBF.WorldActivity.Collect(db, startAt, endAt)
    local totals = {
        fishing = 0,
        mining = 0,
        herbalism = 0,
        lumber = 0,
        skinning = 0,
    }
    local byGuid = {}
    local fish = {}
    local fishOther = 0
    if type(db) ~= "table" or type(startAt) ~= "number" or type(endAt) ~= "number" then
        return totals, byGuid, {}
    end
    local sessions = db.sessions or {}
    for index = 1, #sessions do
        local session = sessions[index]
        local world = type(session) == "table" and not session.sample and session.world or nil
        if type(world) == "table" and not world.folded and type(world.rows) == "table" then
            for rowIndex = 1, #world.rows do
                local row = world.rows[rowIndex]
                if type(row) == "table" and KINDS[row.kind] and type(row.n) == "number" and row.n > 0 and type(row.at) == "number" and row.at >= startAt and row.at <= endAt then
                    totals[row.kind] = totals[row.kind] + row.n
                    if type(row.guid) == "string" then
                        local bucket = byGuid[row.guid]
                        if not bucket then
                            bucket = {}
                            byGuid[row.guid] = bucket
                        end
                        bucket[row.kind] = (bucket[row.kind] or 0) + row.n
                    end
                    if row.kind == "fishing" then
                        if type(row.items) == "table" then
                            for id, info in pairs(row.items) do
                                local qty = type(info) == "table" and info.q or 0
                                if type(qty) == "number" and qty > 0 then
                                    local key = tonumber(id) or id
                                    local stored = fish[key]
                                    if not stored then
                                        stored = { itemID = tonumber(id), name = type(info) == "table" and info.name or nil, qty = 0 }
                                        fish[key] = stored
                                    end
                                    stored.qty = stored.qty + qty
                                    if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
                                        stored.name = info.name
                                    end
                                end
                            end
                        end
                        if type(row.other) == "number" and row.other > 0 then
                            fishOther = fishOther + row.other
                        end
                    end
                end
            end
        end
    end
    local list = {}
    for _, info in pairs(fish) do
        list[#list + 1] = info
    end
    if fishOther > 0 then
        list[#list + 1] = { name = "Other", qty = fishOther }
    end
    table.sort(list, function(a, b)
        if a.qty == b.qty then
            return (a.name or "") < (b.name or "")
        end
        return a.qty > b.qty
    end)
    if #list > 8 then
        local trimmed = {}
        for index = 1, 8 do
            trimmed[index] = list[index]
        end
        list = trimmed
    end
    return totals, byGuid, list
end

function WBF.WorldActivity.FoldSession(life, session)
    if type(life) ~= "table" or type(session) ~= "table" or session.sample then
        return
    end
    local world = session.world
    if type(world) ~= "table" or world.folded or type(world.rows) ~= "table" then
        return
    end
    world.folded = true
    if type(life.totals) ~= "table" then
        life.totals = {}
    end
    if type(life.characters) ~= "table" then
        life.characters = {}
    end
    for index = 1, #world.rows do
        local row = world.rows[index]
        if type(row) == "table" and KINDS[row.kind] and type(row.n) == "number" and row.n ~= 0 then
            life.totals[row.kind] = (life.totals[row.kind] or 0) + row.n
            if type(row.guid) == "string" then
                local character = life.characters[row.guid]
                if type(character) ~= "table" then
                    character = { playedSeconds = 0, counts = {} }
                    life.characters[row.guid] = character
                end
                if type(character.counts) ~= "table" then
                    character.counts = {}
                end
                character.counts[row.kind] = (character.counts[row.kind] or 0) + row.n
            end
        end
    end
end

local function ChannelOn(key)
    if not (WBF.Database and WBF.Database.IsReady and WBF.Database.IsReady()) then
        return false
    end
    local db = WBF.Database.Get()
    return type(db) == "table" and type(db.config) == "table" and db.config[key] == true
end

local function PrintLines(message)
    for line in string.gmatch(tostring(message), "[^\n]+") do
        print("|cffd4af37WarbandFYI|r", line)
    end
end

local function Trace(channel, message)
    lastNote[channel] = message
    if ChannelOn(channel) then
        PrintLines(message)
    end
end

local function Dirty()
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
    if WBF.UI and WBF.UI.RequestRefresh then
        WBF.UI.RequestRefresh()
    end
end

local function MapID()
    if not (C_Map and C_Map.GetBestMapForUnit) then
        return nil
    end
    return WBF.Format.AsNumber(WBF.Format.SafeCall(C_Map.GetBestMapForUnit, "player"))
end

local function MapName(mapID)
    if not mapID or not (C_Map and C_Map.GetMapInfo) then
        return nil
    end
    local info = WBF.Format.SafeCall(C_Map.GetMapInfo, mapID)
    if not IsPlainTable(info) then
        return nil
    end
    return WBF.Format.PlainString(info.name)
end

local function InstanceBlocked()
    if not GetInstanceInfo then
        return true
    end
    local _, instanceType = WBF.Format.SafeCall(GetInstanceInfo)
    instanceType = WBF.Format.PlainString(instanceType)
    if instanceType == "none" then
        return false
    end
    return true
end

local function ExpireRares(now)
    local count = 0
    for guid, entry in pairs(seenRares) do
        if type(entry) ~= "table" or type(entry.lastSeen) ~= "number" or (now - entry.lastSeen) > RARE_TTL then
            seenRares[guid] = nil
        else
            count = count + 1
        end
    end
    if count <= MAX_SEEN then
        return
    end
    local list = {}
    for guid, entry in pairs(seenRares) do
        list[#list + 1] = { guid = guid, at = entry.lastSeen or 0 }
    end
    table.sort(list, function(a, b)
        return a.at < b.at
    end)
    local extra = #list - MAX_SEEN
    for index = 1, extra do
        seenRares[list[index].guid] = nil
    end
end

local function CommitRare(entry, observation)
    if type(entry) ~= "table" or entry.counted or type(entry.guid) ~= "string" then
        return false
    end
    local key = "rarekill:" .. entry.guid
    local already = WBF.Database and WBF.Database.HasDedupe and WBF.Database.HasDedupe(key) == true
    if already then
        entry.counted = true
        return false
    end
    local lootCredit = type(observation) == "table" and observation.lootCredit == true
    local dead = type(observation) == "table" and observation.dead == true
    local tapDenied = nil
    if type(observation) == "table" and observation.tapDenied ~= nil then
        tapDenied = observation.tapDenied == true
    end
    local accepted, reason = WBF.WorldActivity.DecideRare({
        guid = entry.guid,
        classification = entry.classification,
        blockedInstance = InstanceBlocked(),
        encounterBlocked = Now() < encounterUntil,
        alreadyCounted = false,
        lootCredit = lootCredit,
        dead = dead,
        tapDenied = tapDenied,
    })
    local eligible = tapDenied == false and "true" or (tapDenied == true and "false" or "unknown")
    if not accepted then
        if reason == "blocked" or reason == "credit" then
            Trace("debugRares", "Rare candidate: NPC ID=" .. tostring(entry.npcID or "?") .. " name=" .. tostring(entry.name or "?") .. " classification=" .. tostring(entry.classification or "?") .. " eligible=" .. eligible .. " counted=false")
        end
        return false
    end
    local name = entry.name
    local text = (type(name) == "string" and name ~= "") and ("Rare defeated: " .. name) or "Rare defeated"
    local mapID = entry.mapID or MapID()
    local event = WBF.Events and WBF.Events.Add and WBF.Events.Add({
        category = WBF.Category and WBF.Category.Progress or "progress",
        eventType = WBF.EventType and WBF.EventType.RareKill or "rareKill",
        dedupeKey = key,
        dedupeTransient = true,
        text = text,
        meta = {
            npcID = entry.npcID,
            name = name,
            mapID = mapID,
            mapName = MapName(mapID),
            classification = entry.classification,
            eventLabel = text,
            detail = entry.classification,
        },
    })
    if event or (WBF.Database and WBF.Database.HasDedupe and WBF.Database.HasDedupe(key)) then
        entry.counted = true
        Trace("debugRares", "Rare candidate: NPC ID=" .. tostring(entry.npcID or "?") .. " name=" .. tostring(name or "?") .. " classification=" .. tostring(entry.classification or "?") .. " eligible=" .. eligible .. " counted=true")
        return true
    end
    return false
end

local function RememberRare(unit, guid, name, classification, dead, tapDenied)
    local now = Now()
    ExpireRares(now)
    local entry = seenRares[guid]
    if type(entry) ~= "table" then
        entry = { guid = guid }
        seenRares[guid] = entry
    end
    entry.npcID = WBF.WorldActivity.NpcID(guid)
    entry.classification = classification
    entry.lastSeen = now
    entry.mapID = MapID() or entry.mapID
    if type(name) == "string" and name ~= "" then
        entry.name = name
    end
    if type(unit) == "string" then
        watched[unit] = guid
    end
    if not tracedRare[guid] then
        tracedRare[guid] = true
        local eligible = tapDenied == false and "true" or (tapDenied == true and "false" or "unknown")
        Trace("debugRares", "Rare candidate: NPC ID=" .. tostring(entry.npcID or "?") .. " name=" .. tostring(entry.name or "?") .. " classification=" .. classification .. " eligible=" .. eligible)
    end
    if dead == true then
        CommitRare(entry, { dead = true, tapDenied = tapDenied, lootCredit = false })
    end
end

local function Inspect(unit)
    if WBF.Format.IsSecret(unit) or type(unit) ~= "string" or not UnitExists then
        return
    end
    if WBF.Format.SafeBoolean(UnitExists, unit) ~= true then
        watched[unit] = nil
        return
    end
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret and WBF.Format.SafeBoolean(C_Secrets.ShouldUnitIdentityBeSecret, unit) == true then
        return
    end
    local guid = WBF.Format.PlainString(WBF.Format.SafeCall(UnitGUID, unit))
    local classification = WBF.Format.PlainString(WBF.Format.SafeCall(UnitClassification, unit))
    if not guid or (classification ~= "rare" and classification ~= "rareelite") then
        return
    end
    local name = WBF.Format.PlainString(WBF.Format.SafeCall(UnitName, unit))
    local dead = WBF.Format.SafeBoolean(UnitIsDead, unit)
    local tapDenied = WBF.Format.SafeBoolean(UnitIsTapDenied, unit)
    RememberRare(unit, guid, name, classification, dead, tapDenied)
end

local function UnlockedFor(loot, guid)
    local slots = loot and loot.slots or {}
    for index = 1, #slots do
        local slot = slots[index]
        if type(slot) == "table" and FirstGuid(slot) == guid and slot.locked == false then
            return true
        end
    end
    return false
end

local function CreditLootRares(loot)
    local seen = {}
    local slots = loot and loot.slots or {}
    for index = 1, #slots do
        local guid = FirstGuid(slots[index])
        if guid and not seen[guid] and UnlockedFor(loot, guid) then
            seen[guid] = true
            local entry = seenRares[guid]
            if entry then
                CommitRare(entry, { lootCredit = true, dead = false, tapDenied = nil })
            end
        end
    end
end

local function LootState(session, now)
    local world = session and session.world or {}
    local pending = pendingCast
    local age = pending and type(pending.at) == "number" and (now - pending.at) or nil
    if age and (age < 0 or age > GATHER_WINDOW) then
        pending = nil
    end
    return {
        now = now,
        pending = pending,
        allowItemKind = pending and pending.gathering == true and not pending.kind or false,
        sources = type(world) == "table" and world.sources or {},
        fishingAt = type(world) == "table" and world.fishingAt or nil,
        fishingKey = type(world) == "table" and world.fishingKey or nil,
    }
end

local function CommitLoot(loot)
    if type(loot) ~= "table" or not (WBF.Database and WBF.Database.IsReady and WBF.Database.IsReady()) then
        return false
    end
    if not (WBF.Sessions and WBF.Sessions.Touch and WBF.Characters and WBF.Characters.GetGuid) then
        return false
    end
    local session = WBF.Sessions.Touch()
    local guid = WBF.Characters.GetGuid()
    if not session or not guid then
        return false
    end
    local now = Now()
    local decision = WBF.WorldActivity.DecideLoot(loot, LootState(session, now))
    local changed = false
    if decision.fishing then
        local accept = true
        if decision.fishing.sourceGUID then
            accept = WBF.WorldActivity.RememberSource(session, decision.fishing.sourceGUID, now)
        end
        if accept and WBF.WorldActivity.AddCount(session, guid, now, "fishing", decision.fishing.items, MapID(), true) then
            local world = Ensure(session)
            world.fishingAt = now
            world.fishingKey = decision.fishing.signature
            changed = true
        end
    end
    for index = 1, #decision.nodes do
        local node = decision.nodes[index]
        if WBF.WorldActivity.RememberSource(session, node.sourceGUID, now) and WBF.WorldActivity.AddCount(session, guid, now, node.kind, node.items, MapID(), true) then
            changed = true
        end
    end
    if changed then
        Dirty()
    end
    for index = 1, #decision.notes do
        local note = decision.notes[index]
        if note:find("Fishing", 1, true) then
            Trace("debugFishing", note)
        else
            Trace("debugGathering", note)
        end
    end
    CreditLootRares(loot)
    return changed
end

local function ReadLoot(fromItem)
    local loot = {
        fishing = IsFishingLoot and WBF.Format.SafeBoolean(IsFishingLoot) == true or false,
        fromItem = fromItem == true,
        slots = {},
    }
    local count = WBF.Format.AsNumber(WBF.Format.SafeCall(GetNumLootItems))
    if not count or count < 1 then
        return loot
    end
    if count > 40 then
        count = 40
    end
    for slot = 1, count do
        local info = Packed(GetLootSlotInfo, slot)
        local link = WBF.Format.PlainString(WBF.Format.SafeCall(GetLootSlotLink, slot))
        local rawSources = Packed(GetLootSourceInfo, slot) or {}
        local sources = {}
        local cursor = 1
        while cursor <= #rawSources do
            local sourceGuid = WBF.Format.PlainString(rawSources[cursor])
            local quantity = WBF.Format.AsNumber(rawSources[cursor + 1])
            if sourceGuid then
                sources[#sources + 1] = { guid = sourceGuid, quantity = quantity }
            end
            cursor = cursor + 2
        end
        local itemID = WBF.WorldActivity.ItemIDFromLink(link)
        local classID, subClassID = nil, nil
        if itemID and C_Item and C_Item.GetItemInfoInstant then
            local instant = Packed(C_Item.GetItemInfoInstant, itemID)
            if instant then
                classID = WBF.Format.AsNumber(instant[6])
                subClassID = WBF.Format.AsNumber(instant[7])
            end
        end
        local quantity = info and WBF.Format.AsNumber(info[3]) or nil
        if not quantity or quantity < 1 then
            quantity = 1
        end
        local isCoin = info and WBF.Format.AsBoolean(info[10]) == true
        loot.slots[#loot.slots + 1] = {
            itemID = itemID,
            name = info and WBF.Format.PlainString(info[2]) or nil,
            quantity = isCoin and 0 or quantity,
            quality = info and WBF.Format.AsNumber(info[5]) or nil,
            locked = info and WBF.Format.AsBoolean(info[6]) or nil,
            money = isCoin,
            classID = classID,
            subClassID = subClassID,
            sources = sources,
        }
    end
    return loot
end

local function NoteSpell(spellID)
    spellID = WBF.Format.AsNumber(spellID)
    if not spellID or spellID <= 0 then
        return
    end
    local gathering = false
    local professionID = nil
    if C_TradeSkillUI and C_TradeSkillUI.GetGatheringOperationInfo then
        local info = WBF.Format.SafeCall(C_TradeSkillUI.GetGatheringOperationInfo, spellID)
        if IsPlainTable(info) then
            gathering = true
        end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local recipe = WBF.Format.SafeCall(C_TradeSkillUI.GetRecipeInfo, spellID)
        if IsPlainTable(recipe) and WBF.Format.AsBoolean(recipe.isGatheringRecipe) == true then
            gathering = true
        end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoByRecipeID then
        local info = WBF.Format.SafeCall(C_TradeSkillUI.GetProfessionInfoByRecipeID, spellID)
        if IsPlainTable(info) then
            professionID = WBF.Format.AsNumber(info.profession)
        end
    end
    local kind = nil
    if gathering then
        kind = WBF.WorldActivity.ProfessionKind(professionID)
    end
    pendingCast = {
        at = Now(),
        spellID = spellID,
        kind = kind,
        gathering = gathering,
    }
    if windowOpen and openLoot then
        CommitLoot(openLoot)
    end
end

function WBF.WorldActivity.OnRegen()
    Inspect("target")
    Inspect("focus")
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        return
    end
    local plates = WBF.Format.SafeCall(C_NamePlate.GetNamePlates)
    if not IsPlainTable(plates) then
        return
    end
    for index = 1, #plates do
        local plate = plates[index]
        if IsPlainTable(plate) then
            local unit = plate.namePlateUnitToken or plate.unit
            if type(unit) == "string" and not WBF.Format.IsSecret(unit) then
                Inspect(unit)
            end
        end
    end
end

local function SessionTotals()
    local session = WBF.Sessions and WBF.Sessions.GetActive and WBF.Sessions.GetActive() or nil
    if not session then
        return "no active session"
    end
    local now = Now()
    local totals = WBF.WorldActivity.Collect({ sessions = { session } }, 0, now + 1)
    return "fishing=" .. totals.fishing .. " mining=" .. totals.mining .. " herbalism=" .. totals.herbalism .. " lumber=" .. totals.lumber .. " skinning=" .. totals.skinning
end

function WBF.WorldActivity.Debug(channel)
    local key = channel == "gathering" and "debugGathering" or channel == "fishing" and "debugFishing" or channel == "rares" and "debugRares" or nil
    if not key or not (WBF.Database and WBF.Database.Get) then
        return
    end
    local db = WBF.Database.Get()
    if type(db.config) ~= "table" then
        db.config = {}
    end
    db.config[key] = not db.config[key]
    print("|cffd4af37WarbandFYI|r", channel, "debug", db.config[key] and "on" or "off")
    if not db.config[key] then
        return
    end
    if lastNote[key] then
        PrintLines(lastNote[key])
    end
    print("|cffd4af37WarbandFYI|r", SessionTotals())
end

function WBF.WorldActivity.Register(bus)
    bus:On("NAME_PLATE_UNIT_ADDED", function(unit)
        Inspect(unit)
    end)
    bus:On("NAME_PLATE_UNIT_REMOVED", function(unit)
        Inspect(unit)
        if type(unit) == "string" then
            watched[unit] = nil
        end
    end)
    bus:On("PLAYER_TARGET_CHANGED", function()
        Inspect("target")
    end)
    bus:On("PLAYER_FOCUS_CHANGED", function()
        Inspect("focus")
    end)
    bus:On("UPDATE_MOUSEOVER_UNIT", function()
        Inspect("mouseover")
    end)
    bus:On("PLAYER_SOFT_INTERACT_CHANGED", function()
        Inspect("softinteract")
    end)
    bus:On("UNIT_HEALTH", function(unit)
        if WBF.Format.IsSecret(unit) or type(unit) ~= "string" then
            return
        end
        if watched[unit] or unit == "target" or unit == "focus" or unit == "mouseover" then
            Inspect(unit)
        end
    end)
    bus:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
        if WBF.Format.IsSecret(unit) or unit ~= "player" or WBF.Format.IsSecret(spellID) then
            return
        end
        if C_Secrets and C_Secrets.ShouldUnitSpellCastBeSecret and WBF.Format.SafeBoolean(C_Secrets.ShouldUnitSpellCastBeSecret, unit) == true then
            return
        end
        NoteSpell(spellID)
    end)
    bus:On("LOOT_READY", function()
        windowOpen = true
        openLoot = ReadLoot(false)
        if openLoot.fishing then
            CommitLoot(openLoot)
        end
        local token = Now()
        openLoot.token = token
        if C_Timer and C_Timer.After then
            C_Timer.After(0.3, function()
                if windowOpen and openLoot and openLoot.token == token then
                    CommitLoot(openLoot)
                    openLoot.token = nil
                end
            end)
        elseif openLoot then
            CommitLoot(openLoot)
        end
    end)
    bus:On("LOOT_OPENED", function(_, isFromItem)
        local fromItem = WBF.Format.AsBoolean(isFromItem) == true
        windowOpen = true
        local fresh = ReadLoot(fromItem)
        if not openLoot then
            openLoot = fresh
        else
            openLoot = WBF.WorldActivity.PreserveLootSources(openLoot, fresh)
        end
        openLoot.fromItem = fromItem
        openLoot.token = nil
        CommitLoot(openLoot)
    end)
    bus:On("LOOT_CLOSED", function()
        local loot = openLoot
        windowOpen = false
        openLoot = nil
        if loot then
            CommitLoot(loot)
        end
    end)
    bus:On("ENCOUNTER_START", function()
        encounterUntil = Now() + 3600
    end)
    bus:On("ENCOUNTER_END", function()
        encounterUntil = Now() + ENCOUNTER_TAIL
    end)
end
