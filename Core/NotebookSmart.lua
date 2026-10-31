local _, WBF = ...

-- Parsers and live lookups for notebook blocks. Nothing here writes
-- achievement progress, resource balances, or a guessed map.
WBF.NotebookSmart = {}

local zoneOverride = nil
local zoneCache = nil
local requestedItems = {}
local requestedSpells = {}

local KNOWN_LINK = {
    achievement = "achievement",
    item = "item",
    quest = "quest",
    npc = "npc",
    spell = "spell",
    currency = "currency",
    mount = "mount",
    ["battle-pet"] = "battlepet",
    battlepet = "battlepet",
}

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

local function WholeID(value)
    local id = tonumber(value)
    if not id or id ~= math.floor(id) or id < 1 then
        return nil
    end
    return id
end

local function Coord(value)
    local number = tonumber(value)
    if not number or number ~= number or number < 0 or number > 100 then
        return nil
    end
    return math.floor(number * 10 + 0.5) / 10
end

function WBF.NotebookSmart.UseZones(list)
    if type(list) ~= "table" then
        zoneOverride = nil
        return
    end
    zoneOverride = list
end

local function MapTypeAllowed(mapType)
    local enum = Enum and Enum.UIMapType
    if enum then
        return mapType == enum.Zone or mapType == enum.Micro or mapType == enum.Dungeon or mapType == enum.Continent
    end
    return mapType == 2 or mapType == 3 or mapType == 4 or mapType == 5
end

local function BuildZones()
    local list = {}
    local seen = {}
    if not (C_Map and C_Map.GetMapChildrenInfo) then
        return list
    end
    local function take(info)
        if type(info) ~= "table" then
            return
        end
        local mapID = WholeID(info.mapID)
        local name = WBF.Format.PlainString(info.name)
        if not mapID or not name or seen[mapID] or not MapTypeAllowed(info.mapType) then
            return
        end
        seen[mapID] = true
        list[#list + 1] = { mapID = mapID, name = name, mapType = info.mapType }
    end
    local roots = { 946 }
    if C_Map.GetFallbackWorldMapID then
        local fallback = WholeID(WBF.Format.SafeCall(C_Map.GetFallbackWorldMapID))
        if fallback then
            roots[#roots + 1] = fallback
        end
    end
    for index = 1, #roots do
        local children = WBF.Format.SafeCall(C_Map.GetMapChildrenInfo, roots[index], nil, true)
        if type(children) == "table" then
            for childIndex = 1, #children do
                take(children[childIndex])
            end
        end
    end
    table.sort(list, function(a, b)
        if a.name == b.name then
            return a.mapID < b.mapID
        end
        return a.name < b.name
    end)
    return list
end

local function ZoneList()
    if zoneOverride then
        return zoneOverride
    end
    if not zoneCache then
        zoneCache = BuildZones()
    end
    return zoneCache
end

function WBF.NotebookSmart.ZoneRecords()
    return ZoneList()
end

function WBF.NotebookSmart.Zones(query, limit)
    limit = limit or 8
    local needle = Trim(query):lower()
    local source = ZoneList()
    local list = {}
    for index = 1, #source do
        local zone = source[index]
        local name = type(zone.name) == "string" and zone.name or ""
        if needle == "" or name:lower():find(needle, 1, true) then
            list[#list + 1] = zone
            if #list >= limit then
                break
            end
        end
    end
    return list
end

function WBF.NotebookSmart.ResolveZoneName(name)
    name = Trim(name)
    if name == "" then
        return nil, nil
    end
    local needle = name:lower()
    local exact = nil
    local partial = {}
    local source = ZoneList()
    for index = 1, #source do
        local zone = source[index]
        local lower = (zone.name or ""):lower()
        if lower == needle then
            exact = zone
            break
        end
        if lower:find(needle, 1, true) then
            partial[#partial + 1] = zone
        end
    end
    local chosen = exact
    if not chosen and #partial == 1 then
        chosen = partial[1]
    end
    if not chosen or not chosen.mapID or not chosen.name then
        return nil, nil
    end
    return chosen.mapID, chosen.name
end

local function StripCommand(text)
    local body = Trim(text)
    body = body:gsub("^/+%s*[Ww][Aa][Yy]%s*", "")
    body = body:gsub("^[Ww][Aa][Yy]%s+", "")
    return Trim(body)
end

local function NumberToken(token)
    if type(token) ~= "string" then
        return nil
    end
    if not token:match("^%d+%.?%d*$") and not token:match("^%d*%.%d+$") then
        return nil
    end
    return Coord(token)
end

function WBF.NotebookSmart.ParseWaypoint(text, resolve)
    if type(text) ~= "string" then
        return nil
    end
    local body = StripCommand(text)
    if body == "" then
        return nil
    end
    local tokens = {}
    for token in body:gmatch("[%d%.]+") do
        tokens[#tokens + 1] = token
    end
    if #tokens ~= 2 then
        return nil
    end
    local x = NumberToken(tokens[1])
    local y = NumberToken(tokens[2])
    if not x or not y then
        return nil
    end
    local zone = body:gsub("%s*[%d%.]+%s*,%s*[%d%.]+%s*$", "")
    zone = zone:gsub("%s*[%d%.]+%s+[%d%.]+%s*$", "")
    zone = Trim(zone)
    if zone == "" then
        zone = nil
    elseif zone:find("%d") then
        return nil
    end
    local parsed = {
        x = x,
        y = y,
        zone = zone,
        mapID = nil,
        source = "manual",
    }
    if zone then
        resolve = resolve or WBF.NotebookSmart.ResolveZoneName
        local mapID, resolved = resolve(zone)
        if mapID and resolved then
            parsed.mapID = mapID
            parsed.zone = resolved
        end
    end
    return parsed
end

function WBF.NotebookSmart.CleanPoint(point)
    if type(point) ~= "table" then
        return nil
    end
    local mapID = WholeID(point.mapID)
    local x = Coord(point.x)
    local y = Coord(point.y)
    local zone = Clip(point.zone or "", 80)
    if not mapID or not x or not y or zone == "" then
        return nil
    end
    local label = Clip(point.label or "", 80)
    if label == "" then
        label = nil
    end
    local source = point.source
    if source ~= "player" and source ~= "target" and source ~= "manual" then
        source = nil
    end
    return {
        mapID = mapID,
        x = x,
        y = y,
        zone = zone,
        label = label,
        source = source,
    }
end

function WBF.NotebookSmart.PlaceLine(point)
    if type(point) ~= "table" or type(point.zone) ~= "string" or point.zone == "" then
        return nil
    end
    if type(point.x) ~= "number" or type(point.y) ~= "number" then
        return nil
    end
    return string.format("%s  •  %.1f, %.1f", point.zone, point.x, point.y)
end

local function ReadXY(position)
    if type(position) ~= "table" then
        return nil, nil
    end
    local x, y = position.x, position.y
    if type(x) ~= "number" and type(position.GetXY) == "function" then
        x, y = WBF.Format.SafeCall(position.GetXY, position)
    end
    if WBF.Format.IsSecret(x) or WBF.Format.IsSecret(y) or type(x) ~= "number" or type(y) ~= "number" then
        return nil, nil
    end
    return x, y
end

function WBF.NotebookSmart.PlayerLocation()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetMapInfo) then
        return nil, "unavailable"
    end
    local mapID = WholeID(WBF.Format.SafeCall(C_Map.GetBestMapForUnit, "player"))
    if not mapID then
        return nil, "unavailable"
    end
    local position = WBF.Format.SafeCall(C_Map.GetPlayerMapPosition, mapID, "player")
    local rawX, rawY = ReadXY(position)
    if not rawX or not rawY or (rawX == 0 and rawY == 0) then
        return nil, "unavailable"
    end
    local info = WBF.Format.SafeCall(C_Map.GetMapInfo, mapID)
    local zone = type(info) == "table" and WBF.Format.PlainString(info.name) or nil
    if not zone then
        return nil, "unavailable"
    end
    local x = Coord(rawX * 100)
    local y = Coord(rawY * 100)
    if not x or not y then
        return nil, "unavailable"
    end
    return {
        mapID = mapID,
        zone = zone,
        x = x,
        y = y,
        source = "player",
    }
end

local function TargetName()
    if type(UnitExists) ~= "function" or not UnitExists("target") then
        return nil
    end
    if type(UnitName) ~= "function" then
        return nil
    end
    return WBF.Format.PlainString(UnitName("target"))
end

function WBF.NotebookSmart.TargetLocation()
    local name = TargetName()
    if not name then
        return nil, "target"
    end
    local here, reason = WBF.NotebookSmart.PlayerLocation()
    if not here then
        return nil, reason or "unavailable"
    end
    here.label = name
    here.source = "target"
    return here
end

function WBF.NotebookSmart.Track(block)
    local point = WBF.NotebookSmart.CleanPoint(block)
    if not point then
        return false
    end
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function") then
        return false
    end
    if C_Map.CanSetUserWaypointOnMap then
        local allowed = WBF.Format.SafeCall(C_Map.CanSetUserWaypointOnMap, point.mapID)
        if allowed == false then
            return false
        end
    end
    local pin = WBF.Format.SafeCall(UiMapPoint.CreateFromCoordinates, point.mapID, point.x / 100, point.y / 100)
    if type(pin) ~= "table" then
        return false
    end
    WBF.Format.SafeCall(C_Map.SetUserWaypoint, pin)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        WBF.Format.SafeCall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return true
end

local function LooksLikeURL(text)
    local lower = text:lower()
    if lower:find("://", 1, true) then
        return true
    end
    if lower:find("wowhead.com", 1, true) then
        return true
    end
    if lower:match("^www%.") then
        return true
    end
    return false
end

local function LinkToken(text)
    local kind, id = text:match("([%a%-]+)=(%d+)")
    if not kind then
        kind, id = text:match("/([%a%-]+)/(%d+)")
    end
    if not kind or not id then
        return nil, nil
    end
    return kind:lower(), WholeID(id)
end

function WBF.NotebookSmart.CleanURL(text)
    text = Trim(text)
    if text == "" then
        return nil
    end
    return Clip(text, 400)
end

function WBF.NotebookSmart.ItemID(text)
    text = Trim(text or "")
    if text == "" then
        return nil
    end
    local id = text:match("|Hitem:(%d+):") or text:match("item:(%d+)")
    if not id and text:match("^%d+$") then
        id = text
    end
    id = WholeID(id)
    if id then
        return id
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local itemID = WBF.Format.SafeCall(C_Item.GetItemInfoInstant, text)
        return WholeID(itemID)
    end
    return nil
end

function WBF.NotebookSmart.ItemCounts(itemID)
    itemID = WholeID(itemID)
    if not itemID or not C_Item or not C_Item.GetItemCount then
        return nil
    end
    local function read(includeAccountBank)
        local ok, value = pcall(C_Item.GetItemCount, itemID, true, false, true, includeAccountBank and true or false)
        if not ok then
            return nil
        end
        return WBF.Format.AsNumber(value)
    end
    local character = read(false)
    local combined = read(true)
    if character == nil and combined == nil then
        return nil
    end
    character = character or 0
    combined = combined or character
    local accountBank = math.max(0, combined - character)
    return {
        character = character,
        accountBank = accountBank,
        combined = combined,
    }
end

function WBF.NotebookSmart.ChecklistProgress(item)
    local progress = type(item) == "table" and item.progress or nil
    if type(progress) ~= "table" then
        return nil
    end
    local target = tonumber(progress.target)
    if not target or target ~= math.floor(target) or target < 1 then
        return nil
    end
    local source = type(progress.blockId) == "string" and WBF.Notebook and WBF.Notebook.GetBlock and WBF.Notebook.GetBlock(progress.blockId) or nil

    if progress.kind == "item" then
        local itemID = source and source.type == "reference" and source.refType == "item" and WholeID(source.refID) or WholeID(progress.itemID)
        if not itemID then
            return nil
        end
        local counts = WBF.NotebookSmart.ItemCounts(itemID) or { character = 0, accountBank = 0, combined = 0 }
        local title = nil
        local icon = nil
        if source then
            local described = WBF.NotebookSmart.Describe(source)
            title = described and described.title or nil
            icon = described and described.icon or nil
        end
        if not title then
            local described = WBF.NotebookSmart.Describe({ refType = "item", refID = itemID })
            title = described and described.title or ("Item " .. tostring(itemID))
            icon = described and described.icon or nil
        end
        return {
            kind = "item",
            blockId = source and source.id or progress.blockId,
            itemID = itemID,
            title = title,
            icon = icon,
            current = counts.combined or counts.character or 0,
            character = counts.character or 0,
            accountBank = counts.accountBank or 0,
            target = target,
        }
    end

    if progress.kind == "resource" then
        local resourceKey = source and source.type == "resource" and source.resourceKey or progress.resourceKey
        if type(resourceKey) ~= "string" or resourceKey == "" then
            return nil
        end
        local view = WBF.Resources and WBF.Resources.NotebookView and WBF.Resources.NotebookView(resourceKey) or nil
        if not view then
            return nil
        end
        return {
            kind = "resource",
            blockId = source and source.id or progress.blockId,
            resourceKey = resourceKey,
            title = view.name or resourceKey,
            icon = view.icon,
            current = tonumber(view.amount) or 0,
            character = tonumber(view.character),
            accountWide = view.accountWide and true or false,
            target = target,
        }
    end

    return nil
end

function WBF.NotebookSmart.ParseLink(text)
    text = Trim(text)
    if text == "" then
        return nil
    end
    local token, id = LinkToken(text)
    local known = token and KNOWN_LINK[token] or nil
    local url = LooksLikeURL(text) and WBF.NotebookSmart.CleanURL(text) or nil
    if known == "achievement" and id then
        return { kind = "achievement", id = id, url = url }
    end
    if known == "currency" and id then
        local definition = WBF.Resources and WBF.Resources.ByCurrencyID and WBF.Resources.ByCurrencyID(id) or nil
        if definition and definition.key then
            return { kind = "resource", resourceKey = definition.key, id = id, url = url }
        end
        return { kind = "reference", refType = "currency", refID = id, url = url }
    end
    if known and id then
        return { kind = "reference", refType = known, refID = id, url = url }
    end
    if token and id and url then
        return { kind = "reference", refType = token, refID = id, url = url }
    end
    if url then
        return { kind = "reference", refType = "link", url = url }
    end
    return nil
end

function WBF.NotebookSmart.CleanReference(spec)
    if type(spec) ~= "table" then
        return nil
    end
    local url = WBF.NotebookSmart.CleanURL(spec.url or "")
    local label = Clip(spec.label or "", 80)
    if label == "" then
        label = nil
    end
    local refType = spec.refType
    if refType == "battle-pet" then
        refType = "battlepet"
    end
    if type(refType) == "string" then
        refType = refType:lower()
    else
        refType = nil
    end
    if refType and (not refType:match("^[%a][%a%-]*$") or #refType > 24) then
        refType = nil
    end
    local refID = WholeID(spec.refID)
    if not refType or refType == "link" or not refID then
        if not url then
            return nil
        end
        return { refType = "link", url = url, label = label }
    end
    return {
        refType = refType,
        refID = refID,
        url = url,
        label = label,
    }
end

local function KindLabel(refType)
    if refType == "battlepet" then
        return "Battle Pet"
    end
    if refType == "npc" then
        return "NPC"
    end
    if type(refType) ~= "string" or refType == "" or refType == "link" then
        return "Link"
    end
    return (refType:gsub("^%l", string.upper):gsub("%-(%l)", function(letter)
        return " " .. letter:upper()
    end))
end

function WBF.NotebookSmart.Prepare(block)
    if type(block) ~= "table" then
        return
    end
    local id = WholeID(block.refID)
    if not id then
        return
    end
    if block.refType == "item" and not requestedItems[id] and C_Item and C_Item.RequestLoadItemDataByID then
        requestedItems[id] = true
        WBF.Format.SafeCall(C_Item.RequestLoadItemDataByID, id)
    elseif block.refType == "spell" and not requestedSpells[id] and C_Spell and C_Spell.RequestLoadSpellData then
        requestedSpells[id] = true
        WBF.Format.SafeCall(C_Spell.RequestLoadSpellData, id)
    end
end

function WBF.NotebookSmart.Describe(block)
    local spec = WBF.NotebookSmart.CleanReference(block or {})
    if spec and WBF.NotebookSmart.Prepare then
        -- FYI popups and link menus can ask for a reference description before
        -- the Notebook page itself has ever rendered. Request item/spell data
        -- here as well so we resolve names/icons instead of leaking raw IDs.
        WBF.NotebookSmart.Prepare(spec)
    end
    local title = nil
    local detail = nil
    local icon = nil
    local resolved = false
    -- Item counts as separate label/value rows, for views that list them
    -- one per line instead of reading the joined detail text.
    local countRows = nil
    local note = nil
    if not spec then
        return { title = "Reference", resolved = false }
    end
    local id = spec.refID
    local kind = spec.refType
    if kind == "item" and id then
        local name, texture
        if C_Item and C_Item.GetItemInfo then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = WBF.Format.SafeCall(C_Item.GetItemInfo, id)
            name = WBF.Format.PlainString(itemName)
            texture = WBF.Format.AsNumber(itemTexture)
        elseif type(GetItemInfo) == "function" then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = WBF.Format.SafeCall(GetItemInfo, id)
            name = WBF.Format.PlainString(itemName)
            texture = WBF.Format.AsNumber(itemTexture)
        end
        if name then
            title = name
            icon = texture
            resolved = true
        end
        local counts = WBF.NotebookSmart.ItemCounts(id)
        if counts then
            local countText = "You " .. tostring(counts.character or 0)
            countRows = { { label = "You", value = counts.character or 0 } }
            if (counts.accountBank or 0) > 0 then
                countText = countText .. "  ·  Warband bank " .. tostring(counts.accountBank)
                countRows[#countRows + 1] = { label = "Warband bank", value = counts.accountBank }
            end
            -- Tracked items (event tokens) know what every alt holds, so the
            -- warband total covers more than this character plus the bank.
            -- The alts come from their last scan; this character and the bank
            -- are live, so a spend shows before the tracker rescans.
            local tracked = WBF.Resources and WBF.Resources.ByItemID and WBF.Resources.ByItemID(id) or nil
            local view = tracked and tracked.key and WBF.Resources.NotebookView and WBF.Resources.NotebookView(tracked.key) or nil
            local others = view and tonumber(view.others) or nil
            local total
            if others then
                total = others + (counts.combined or 0)
            else
                total = math.max(view and tonumber(view.amount) or 0, counts.combined or 0)
            end
            if total > (counts.character or 0) then
                countText = countText .. "  ·  Total " .. tostring(total)
                countRows[#countRows + 1] = { label = "Total", value = total }
            end
            detail = countText
        end
    elseif kind == "spell" and id then
        if C_Spell and C_Spell.GetSpellInfo then
            local info = WBF.Format.SafeCall(C_Spell.GetSpellInfo, id)
            if type(info) == "table" then
                title = WBF.Format.PlainString(info.name)
                icon = WBF.Format.AsNumber(info.iconID or info.icon)
            else
                local spellName, _, spellIcon = WBF.Format.SafeCall(C_Spell.GetSpellInfo, id)
                title = WBF.Format.PlainString(spellName)
                icon = WBF.Format.AsNumber(spellIcon)
            end
        elseif type(GetSpellInfo) == "function" then
            local spellName, _, spellIcon = WBF.Format.SafeCall(GetSpellInfo, id)
            title = WBF.Format.PlainString(spellName)
            icon = WBF.Format.AsNumber(spellIcon)
        end
        if title then
            resolved = true
        end
    elseif kind == "quest" and id and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = WBF.Format.PlainString(WBF.Format.SafeCall(C_QuestLog.GetTitleForQuestID, id))
        resolved = title ~= nil
    elseif kind == "mount" and id and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local name, _, mountIcon = WBF.Format.SafeCall(C_MountJournal.GetMountInfoByID, id)
        title = WBF.Format.PlainString(name)
        icon = WBF.Format.AsNumber(mountIcon)
        resolved = title ~= nil
    elseif kind == "battlepet" and id and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local name, petIcon = WBF.Format.SafeCall(C_PetJournal.GetPetInfoBySpeciesID, id)
        title = WBF.Format.PlainString(name)
        icon = WBF.Format.AsNumber(petIcon)
        resolved = title ~= nil
    end
    if spec.label and spec.label ~= "" then
        if not title then
            title = spec.label
        elseif title ~= spec.label then
            note = spec.label
            if detail and detail ~= "" then
                detail = detail .. "  ·  " .. spec.label
            else
                detail = spec.label
            end
        end
    end
    if not title then
        if kind == "item" and id then
            -- Item data can arrive a frame or two after login. Do not flash a
            -- raw item ID in the FYI/Notebook while the client resolves it.
            title = spec.label or "Tracked item"
        elseif kind ~= "link" and id then
            title = KindLabel(kind) .. " " .. id
        else
            title = "Link"
        end
    end
    if not resolved and kind ~= "link" and id and kind ~= "item" then
        local stamp = KindLabel(kind) .. " " .. id
        if detail and detail ~= stamp then
            detail = stamp .. "  ·  " .. detail
        else
            detail = stamp
        end
    end
    return {
        title = title,
        detail = detail,
        countRows = countRows,
        note = note,
        icon = icon,
        url = spec.url,
        resolved = resolved,
        refType = kind,
        refID = id,
    }
end

function WBF.NotebookSmart.Register(bus)
    local function refresh(id, bucket)
        if id and bucket and not bucket[id] then
            return
        end
        -- A linked checklist can be visible in the floating FYI while the
        -- main WarbandFYI window is closed, so keep that live too.
        if WBF.UI and WBF.UI.Fyi and WBF.UI.Fyi.Refresh then
            WBF.UI.Fyi.Refresh()
        end
        local window = WBF.UI and WBF.UI.frame
        if not window or not window.IsShown or not window:IsShown() or window.view ~= "notebook" then
            return
        end
        if WBF.Notebook and WBF.Notebook.RefreshOpen then
            WBF.Notebook.RefreshOpen()
        end
    end
    bus:On("ITEM_DATA_LOAD_RESULT", function(itemID)
        refresh(itemID, requestedItems)
        if WBF.UI and WBF.UI.NotebookAdd and WBF.UI.NotebookAdd.OnItemData then
            WBF.UI.NotebookAdd.OnItemData(itemID)
        end
    end)
    bus:On("BAG_UPDATE_DELAYED", function()
        refresh()
    end)
    -- Currency/resource-linked checklist goals should move live just like
    -- item-linked goals, including while only the floating FYI is visible.
    bus:On("CURRENCY_DISPLAY_UPDATE", function()
        refresh()
    end)
    bus:On("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", function()
        refresh()
    end)
    bus:On("CURRENCY_TRANSFER_SUCCESS", function()
        refresh()
    end)
    bus:On("SPELL_DATA_LOAD_RESULT", function(spellID)
        refresh(spellID, requestedSpells)
    end)
end
