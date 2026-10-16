local _, WBF = ...

-- Housing decor is a collection. First-time unlocks come from the housing
-- catalog's stored, redeemable, and placed counts. Copies already in that
-- collection are aggregated. House XP is the change in HouseLevelFavor, and
-- the same bonus is counted once when every owned house receives it.
--
-- Chat text is not used. A chest add, a storage refresh, and a toast for the
-- same decorGUID collapse into one acquisition.

WBF.Housing = {}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Statue_02"
local RESOLVE_ATTEMPTS = 5
local MATCH_SECONDS = 8

local pending = {}
local resolved = {}
local favorDeltas = {}
local favorFlushQueued = false
local recentToast = nil
local unclaimedXP = {}

local function Now()
    return WBF.Time.Now()
end

local function Number(value)
    return WBF.Format.AsNumber(value)
end

local function Text(value)
    return WBF.Format.PlainString(value)
end

local function DecorType()
    if Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor ~= nil then
        return Enum.HousingCatalogEntryType.Decor
    end
    return nil
end

local function ToastDecorType()
    if Enum and Enum.HousingItemToastType and Enum.HousingItemToastType.Decor ~= nil then
        return Enum.HousingItemToastType.Decor
    end
    return nil
end

function WBF.Housing.Root()
    local db = WBF.Database.Get()
    if type(db.housing) ~= "table" then
        db.housing = {}
    end
    if type(db.housing.collected) ~= "table" then
        db.housing.collected = {}
    end
    if type(db.housing.favor) ~= "table" then
        db.housing.favor = {}
    end
    return db.housing
end

function WBF.Housing.ResetRuntime()
    pending = {}
    resolved = {}
    favorDeltas = {}
    favorFlushQueued = false
    recentToast = nil
    unclaimedXP = {}
end

local function Key(decorID)
    return tostring(decorID)
end

local function Collected(decorID)
    local root = WBF.Housing.Root()
    return root.collected[Key(decorID)]
end

local function CurrentGuid(explicit)
    if type(explicit) == "string" and explicit ~= "" then
        return explicit
    end
    local character = WBF.Characters and WBF.Characters.GetCurrent and WBF.Characters.GetCurrent()
    return character and character.guid or nil
end

local function SessionId()
    local session = WBF.Sessions and WBF.Sessions.Touch and WBF.Sessions.Touch()
    if not session and WBF.Sessions and WBF.Sessions.GetActive then
        session = WBF.Sessions.GetActive()
    end
    return session and session.id or nil
end

local function MarkDirty()
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
    if WBF.UI and WBF.UI.RequestRefresh then
        WBF.UI.RequestRefresh()
    end
end

local function CopySeen(decorGUID)
    if not decorGUID then
        return false
    end
    if resolved[decorGUID] then
        return true
    end
    return WBF.Database.HasDedupe("housingcopy:" .. decorGUID)
end

local function RememberCopy(decorGUID, at)
    if not decorGUID then
        return
    end
    resolved[decorGUID] = true
    WBF.Database.MarkDedupe("housingcopy:" .. decorGUID, at or Now())
end

local function OwnedCount(info)
    if type(info) ~= "table" then
        return nil
    end
    local stored = Number(info.totalNumStored)
    local redeemable = Number(info.remainingRedeemable)
    local placed = Number(info.totalNumPlaced)
    if stored == nil or redeemable == nil or placed == nil then
        return nil
    end
    return stored + redeemable + placed
end

local function CatalogInfo(decorID)
    if not C_HousingCatalog or not C_HousingCatalog.GetCatalogEntryInfoByRecordID then
        return nil
    end
    local entryType = DecorType()
    if entryType == nil or not decorID then
        return nil
    end
    local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByRecordID, entryType, decorID)
    if ok and type(info) == "table" then
        return info
    end
    return nil
end

local function DecorName(decorID)
    if not C_HousingDecor or not C_HousingDecor.GetDecorName or not decorID then
        return nil
    end
    local ok, name = pcall(C_HousingDecor.GetDecorName, decorID)
    if ok then
        return Text(name)
    end
    return nil
end

local function DecorIcon(decorID)
    if not C_HousingDecor or not C_HousingDecor.GetDecorIcon or not decorID then
        return nil
    end
    local ok, icon = pcall(C_HousingDecor.GetDecorIcon, decorID)
    if ok then
        return Number(icon)
    end
    return nil
end

local function IconFields(info, decorID)
    local icon, iconAtlas
    if type(info) == "table" then
        icon = Number(info.iconTexture) or Text(info.iconTexture)
        iconAtlas = Text(info.iconAtlas)
    end
    if not icon then
        icon = DecorIcon(decorID)
    end
    if not icon and not iconAtlas and recentToast and (Now() - (recentToast.at or 0)) <= MATCH_SECONDS then
        icon = recentToast.icon
    end
    return icon, iconAtlas
end

local function DisplayName(info, decorID)
    local name = type(info) == "table" and Text(info.name) or nil
    if not name then
        name = DecorName(decorID)
    end
    if not name and recentToast and (Now() - (recentToast.at or 0)) <= MATCH_SECONDS then
        name = recentToast.name
    end
    return name or "Decor"
end

local function FindDuplicate(decorID, sessionId, guid)
    local events = WBF.Database.Get().events or {}
    for index = #events, 1, -1 do
        local event = events[index]
        if sessionId and event.sessionId and event.sessionId ~= sessionId then
            break
        end
        local meta = event.meta
        if event.eventType == WBF.EventType.HousingAcquire and event.sessionId == sessionId and event.guid == guid and type(meta) == "table" and meta.decorID == decorID then
            return event
        end
    end
    return nil
end

local function RecordDuplicate(spec, name, icon, iconAtlas)
    local guid = CurrentGuid(spec.guid)
    local sessionId = SessionId()
    local existing = FindDuplicate(spec.decorID, sessionId, guid)
    if existing then
        existing.meta.count = (existing.meta.count or 1) + 1
        if name and (not existing.meta.name or existing.meta.name == "" or existing.meta.name == "Decor") then
            existing.meta.name = name
        end
        if icon and not existing.meta.icon then
            existing.meta.icon = icon
        end
        if iconAtlas and not existing.meta.iconAtlas then
            existing.meta.iconAtlas = iconAtlas
        end
        MarkDirty()
        return existing
    end
    return WBF.Events.Add({
        at = spec.at,
        guid = guid,
        category = WBF.Category.Collection,
        eventType = WBF.EventType.HousingAcquire,
        text = "",
        meta = {
            decorID = spec.decorID,
            itemID = spec.itemID,
            name = name,
            icon = icon,
            iconAtlas = iconAtlas,
            count = 1,
            duplicate = true,
            surface = false,
        },
    })
end

local function RecentUnassigned()
    local events = WBF.Database.Get().events or {}
    local now = Now()
    local list = {}
    for index = #events, 1, -1 do
        local event = events[index]
        if type(event.at) == "number" and (now - event.at) > MATCH_SECONDS then
            break
        end
        local meta = event.meta
        if event.eventType == WBF.EventType.HousingDecor and type(meta) == "table" and meta.houseXP == nil then
            list[#list + 1] = event
        end
    end
    return list
end

local function AssignXP(event, amount)
    if not event or not event.meta or type(amount) ~= "number" or amount <= 0 then
        return
    end
    event.meta.houseXP = amount
    local row = Collected(event.meta.decorID)
    if row and row.houseXP == nil then
        row.houseXP = amount
    end
end

local function TryMatchXP()
    local decor = RecentUnassigned()
    if #decor == 0 or #unclaimedXP == 0 then
        return
    end
    local now = Now()
    local index = 1
    while index <= #unclaimedXP do
        local gain = unclaimedXP[index]
        if gain.claimed or type(gain.at) ~= "number" or (now - gain.at) > MATCH_SECONDS then
            table.remove(unclaimedXP, index)
        else
            local matched = false
            for decorIndex = 1, #decor do
                local event = decor[decorIndex]
                local bonus = event.meta and Number(event.meta.bonus)
                if event.meta and event.meta.houseXP == nil and bonus and bonus > 0 and bonus == gain.amount then
                    AssignXP(event, gain.amount)
                    gain.claimed = true
                    matched = true
                    break
                end
            end
            if not matched and #decor > 1 then
                local sum = 0
                local usable = true
                for decorIndex = 1, #decor do
                    local event = decor[decorIndex]
                    local bonus = event.meta and event.meta.houseXP == nil and Number(event.meta.bonus) or nil
                    if not bonus or bonus <= 0 then
                        usable = false
                        break
                    end
                    sum = sum + bonus
                end
                if usable and sum == gain.amount then
                    for decorIndex = 1, #decor do
                        local event = decor[decorIndex]
                        if event.meta.houseXP == nil then
                            AssignXP(event, Number(event.meta.bonus))
                        end
                    end
                    gain.claimed = true
                    matched = true
                end
            end
            if gain.claimed then
                table.remove(unclaimedXP, index)
                MarkDirty()
            else
                index = index + 1
            end
        end
    end
end

local function RememberCollected(spec, name, icon, iconAtlas)
    local root = WBF.Housing.Root()
    local key = Key(spec.decorID)
    local row = root.collected[key]
    if row then
        return row
    end
    row = {
        decorID = spec.decorID,
        itemID = spec.itemID,
        name = name,
        icon = icon,
        iconAtlas = iconAtlas,
        source = spec.source,
        firstAt = spec.at or Now(),
        guid = CurrentGuid(spec.guid),
        sample = spec.sample,
    }
    root.collected[key] = row
    return row
end

-- spec.owned is the catalog total after the copy landed.
-- 1 and not already collected: first time.
-- greater than 1, or already collected: another copy.
-- nil: the catalog could not be read, so this is not treated as new.
-- 0: the catalog has not caught up yet.
function WBF.Housing.NoteAcquisition(spec)
    if type(spec) ~= "table" or not Number(spec.decorID) then
        return "ignored"
    end
    spec.decorID = Number(spec.decorID)
    spec.itemID = Number(spec.itemID)
    spec.owned = Number(spec.owned)
    spec.bonus = Number(spec.bonus)
    if spec.decorGUID ~= nil then
        spec.decorGUID = Text(spec.decorGUID) or (type(spec.decorGUID) == "string" and spec.decorGUID ~= "" and spec.decorGUID or nil)
    end
    if spec.owned == 0 then
        return "pending"
    end
    if CopySeen(spec.decorGUID) then
        return "ignored"
    end

    local infoName = spec.name
    local name = Text(infoName) or DisplayName(nil, spec.decorID)
    local icon = spec.icon
    local iconAtlas = Text(spec.iconAtlas)
    if icon ~= nil then
        icon = Number(icon) or Text(icon)
    end
    local already = Collected(spec.decorID) or WBF.Database.HasDedupe("housing:" .. spec.decorID)
    local firstTime = spec.owned == 1 and not already
    if spec.owned == nil then
        firstTime = false
    end

    RememberCopy(spec.decorGUID, spec.at)

    if firstTime then
        local instanceName, location = nil, nil
        if WBF.Collections and WBF.Collections.CollectedWhere then
            instanceName, location = WBF.Collections.CollectedWhere()
        end
        RememberCollected(spec, name, icon, iconAtlas)
        local event = WBF.Events.Add({
            at = spec.at,
            guid = CurrentGuid(spec.guid),
            category = WBF.Category.Collection,
            eventType = WBF.EventType.HousingDecor,
            dedupeKey = "housing:" .. spec.decorID,
            text = "New decor: " .. name,
            meta = {
                decorID = spec.decorID,
                itemID = spec.itemID,
                name = name,
                icon = icon,
                iconAtlas = iconAtlas,
                source = Text(spec.source),
                instanceName = instanceName,
                location = location,
                quality = Number(spec.quality),
                bonus = spec.bonus,
                firstTime = true,
            },
        })
        if event then
            TryMatchXP()
            return "new"
        end
    end

    RecordDuplicate(spec, name, icon, iconAtlas)
    return "duplicate"
end

function WBF.Housing.NoteFavor(info)
    if type(info) ~= "table" then
        return 0
    end
    local favor = Number(info.houseFavor)
    local level = Number(info.houseLevel)
    local houseGUID = Text(info.houseGUID)
    if not favor or not houseGUID then
        return 0
    end
    local root = WBF.Housing.Root()
    local state = root.favor[houseGUID]
    if type(state) ~= "table" then
        root.favor[houseGUID] = { level = level, favor = favor }
        return 0
    end
    local previous = Number(state.favor) or favor
    state.favor = favor
    if level then
        state.level = level
    end
    local delta = favor - previous
    if delta > 0 then
        favorDeltas[houseGUID] = (favorDeltas[houseGUID] or 0) + delta
    end
    return delta
end

function WBF.Housing.FlushFavor()
    local amount = nil
    local disagreed = false
    for _, delta in pairs(favorDeltas) do
        if type(delta) == "number" and delta > 0 then
            if amount == nil then
                amount = delta
            elseif amount ~= delta then
                disagreed = true
            end
        end
    end
    favorDeltas = {}
    favorFlushQueued = false
    if disagreed or not amount or amount <= 0 then
        return 0
    end
    WBF.Events.Add({
        category = WBF.Category.Collection,
        eventType = WBF.EventType.HousingXP,
        delta = amount,
        text = "",
        meta = {
            surface = false,
            houseXP = amount,
        },
    })
    unclaimedXP[#unclaimedXP + 1] = { amount = amount, at = Now() }
    TryMatchXP()
    return amount
end

local function QueueFavorFlush()
    if favorFlushQueued then
        return
    end
    favorFlushQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if WBF.Database.IsReady() then
                WBF.Housing.FlushFavor()
            end
        end)
        return
    end
    WBF.Housing.FlushFavor()
end

local function Describe(decorID, info)
    local icon, iconAtlas = IconFields(info, decorID)
    return {
        decorID = decorID,
        owned = OwnedCount(info),
        name = DisplayName(info, decorID),
        itemID = type(info) == "table" and Number(info.itemID) or nil,
        icon = icon,
        iconAtlas = iconAtlas,
        source = type(info) == "table" and Text(info.sourceText) or nil,
        quality = type(info) == "table" and Number(info.quality) or nil,
        bonus = type(info) == "table" and Number(info.firstAcquisitionBonus) or nil,
    }
end

local function ResolvePending(decorGUID)
    local item = pending[decorGUID]
    if not item or not WBF.Database.IsReady() then
        return
    end
    local info = CatalogInfo(item.decorID)
    local owned = OwnedCount(info)
    if owned == nil or owned == 0 then
        item.attempts = (item.attempts or 0) + 1
        if item.attempts < RESOLVE_ATTEMPTS and C_Timer and C_Timer.After then
            C_Timer.After(0.2 * item.attempts, function()
                ResolvePending(decorGUID)
            end)
            return
        end
    end
    pending[decorGUID] = nil
    local spec = Describe(item.decorID, info)
    spec.decorGUID = decorGUID
    if spec.owned == 0 then
        spec.owned = nil
    end
    WBF.Housing.NoteAcquisition(spec)
end

local function AcceptChest(decorGUID, decorID)
    decorGUID = Text(decorGUID)
    decorID = Number(decorID)
    if not decorGUID or not decorID or not WBF.Database.IsReady() then
        return
    end
    if CopySeen(decorGUID) or pending[decorGUID] then
        return
    end
    pending[decorGUID] = { decorID = decorID, attempts = 0 }
    ResolvePending(decorGUID)
end

local function RefreshPending()
    for decorGUID in pairs(pending) do
        ResolvePending(decorGUID)
    end
end

local function RequestFavor(houseGUID)
    houseGUID = Text(houseGUID)
    if not houseGUID or not C_Housing or not C_Housing.GetCurrentHouseLevelFavor then
        return
    end
    pcall(C_Housing.GetCurrentHouseLevelFavor, houseGUID)
end

local function RequestHouses(houseInfos)
    if type(houseInfos) ~= "table" then
        return
    end
    if houseInfos.houseGUID then
        RequestFavor(houseInfos.houseGUID)
        return
    end
    for _, info in pairs(houseInfos) do
        if type(info) == "table" and info.houseGUID then
            RequestFavor(info.houseGUID)
        end
    end
end

local function RequestKnownHouses()
    if not C_Housing then
        return
    end
    if C_Housing.GetPlayerOwnedHouses then
        pcall(C_Housing.GetPlayerOwnedHouses)
    end
    if C_Housing.GetTrackedHouseGuid then
        local ok, houseGUID = pcall(C_Housing.GetTrackedHouseGuid)
        if ok then
            RequestFavor(houseGUID)
        end
    end
end

function WBF.Housing.NoteToast(itemType, itemName, icon)
    local decorType = ToastDecorType()
    if decorType == nil or itemType ~= decorType then
        return
    end
    recentToast = {
        name = Text(itemName),
        icon = Number(icon),
        at = Now(),
    }
end

function WBF.Housing.Register(bus)
    bus:On("HOUSE_DECOR_ADDED_TO_CHEST", AcceptChest)
    bus:On("HOUSING_STORAGE_UPDATED", RefreshPending)
    bus:On("HOUSING_STORAGE_ENTRY_UPDATED", RefreshPending)
    bus:On("NEW_HOUSING_ITEM_ACQUIRED", function(itemType, itemName, icon)
        WBF.Housing.NoteToast(itemType, itemName, icon)
    end)
    bus:On("HOUSE_LEVEL_FAVOR_UPDATED", function(houseLevelFavor)
        WBF.Housing.NoteFavor(houseLevelFavor)
        QueueFavorFlush()
    end)
    bus:On("PLAYER_HOUSE_LIST_UPDATED", RequestHouses)
    bus:On("CURRENT_HOUSE_INFO_RECIEVED", function(houseInfo)
        if type(houseInfo) == "table" then
            RequestFavor(houseInfo.houseGUID)
        end
    end)
    bus:On("CURRENT_HOUSE_INFO_UPDATED", function(houseInfo)
        if type(houseInfo) == "table" then
            RequestFavor(houseInfo.houseGUID)
        end
    end)
    bus:On("TRACKED_HOUSE_CHANGED", RequestFavor)
    bus:On("PLAYER_ENTERING_WORLD", function()
        RequestKnownHouses()
    end)
end

function WBF.Housing.Tile(totals)
    totals = totals or {}
    local newDecor = totals.newDecor or 0
    local houseXP = totals.houseXP or 0
    if newDecor > 0 then
        local tile = {
            label = "New Decor",
            value = WBF.Format.Number(newDecor),
            fallback = FALLBACK_ICON,
            tooltip = "Decor added to your House Chest for the first time. Another copy of decor you already have is not listed here.",
            open = "housing",
            group = "collection",
        }
        if houseXP > 0 then
            tile.detail = "+" .. WBF.Format.Number(houseXP) .. " House XP"
        end
        return tile
    end
    if houseXP > 0 then
        return {
            label = "House XP",
            value = "+" .. WBF.Format.Number(houseXP),
            fallback = FALLBACK_ICON,
            tooltip = "House XP observed from house favor. When every house receives the same bonus, it is counted once.",
            open = "housing",
            group = "collection",
        }
    end
    return nil
end

local function InWindow(at, startAt, endAt)
    if type(at) ~= "number" then
        return false
    end
    if startAt and startAt > 0 and at < startAt then
        return false
    end
    if endAt and at > endAt then
        return false
    end
    return true
end

function WBF.Housing.EventsBetween(startAt, endAt, guid)
    local list = {}
    local events = WBF.Database.Get().events or {}
    for index = 1, #events do
        local event = events[index]
        local kind = event.eventType
        local housing = kind == WBF.EventType.HousingDecor or kind == WBF.EventType.HousingAcquire or kind == WBF.EventType.HousingXP
        if housing and InWindow(event.at, startAt, endAt) and (not guid or event.guid == guid) then
            list[#list + 1] = event
        end
    end
    return list
end

function WBF.Housing.Acquisitions(events)
    local rows = {}
    local indexByID = {}
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        local decorID = meta.decorID
        local count = 0
        if event.eventType == WBF.EventType.HousingDecor then
            count = 1
        elseif event.eventType == WBF.EventType.HousingAcquire then
            count = meta.count or 1
        end
        if decorID and count > 0 then
            local slot = indexByID[decorID]
            if not slot then
                slot = {
                    decorID = decorID,
                    name = meta.name or "Decor",
                    icon = meta.icon,
                    iconAtlas = meta.iconAtlas,
                    count = 0,
                }
                indexByID[decorID] = slot
                rows[#rows + 1] = slot
            end
            slot.count = slot.count + count
            if meta.name and meta.name ~= "" and (slot.name == "Decor" or slot.name == "") then
                slot.name = meta.name
            end
            if meta.icon and not slot.icon then
                slot.icon = meta.icon
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.count == b.count then
            return (a.name or "") < (b.name or "")
        end
        return a.count > b.count
    end)
    return rows
end

local function CollectedWhen(at)
    if type(at) ~= "number" then
        return nil
    end
    local now = Now()
    if math.abs(now - at) < 86400 then
        return "First collected " .. WBF.Time.Clock(at)
    end
    if WBF.Time.FormatStamp then
        return "First collected " .. WBF.Time.FormatStamp(at)
    end
    return "First collected " .. WBF.Time.Clock(at)
end

local function DecorRow(title, icon, iconAtlas, lines, value)
    return {
        title = title or "Decor",
        value = value,
        icon = icon,
        atlases = (not icon and iconAtlas) and { iconAtlas } or nil,
        fallback = FALLBACK_ICON,
        lines = lines,
    }
end

function WBF.Housing.BuildDetail(summary, context)
    context = context or {}
    summary = summary or {}
    local guid = context.characterGUID
    local totals = summary.totals or {}
    if guid and summary.characters then
        for index = 1, #summary.characters do
            local character = summary.characters[index]
            if character.guid == guid then
                totals = character.counts or {}
                break
            end
        end
    end

    local model = {
        title = "Housing",
        subtitle = summary.label,
        sections = {},
    }
    if guid and WBF.Characters and WBF.Characters.Get then
        local character = WBF.Characters.Get(guid)
        if character and character.name and character.name ~= "" then
            model.subtitle = (model.subtitle or "Housing") .. "    ·    " .. character.name
        end
    end

    local acquired = totals.decorAcquired or 0
    local newDecor = totals.newDecor or 0
    local duplicates = totals.duplicates or 0
    local houseXP = totals.houseXP or 0
    local metrics = {}
    if acquired > 0 then
        metrics[#metrics + 1] = { title = "Decor acquired", value = WBF.Format.Number(acquired), compact = true }
    end
    if newDecor > 0 then
        metrics[#metrics + 1] = { title = "New to collection", value = WBF.Format.Number(newDecor), compact = true }
    end
    if duplicates > 0 then
        metrics[#metrics + 1] = { title = "Duplicates", value = WBF.Format.Number(duplicates), compact = true }
    end
    if houseXP > 0 then
        metrics[#metrics + 1] = { title = "House XP gained", value = "+" .. WBF.Format.Number(houseXP), compact = true, valueColor = "green" }
    end
    if #metrics > 0 then
        model.sections[#model.sections + 1] = { rows = metrics }
    end

    local events = WBF.Housing.EventsBetween(summary.startAt, summary.endAt, guid)
    local fresh = {}
    for index = 1, #events do
        if events[index].eventType == WBF.EventType.HousingDecor then
            fresh[#fresh + 1] = events[index]
        end
    end
    table.sort(fresh, function(a, b)
        return (a.at or 0) > (b.at or 0)
    end)
    if #fresh > 0 then
        local rows = {}
        for index = 1, #fresh do
            local event = fresh[index]
            local meta = event.meta or {}
            local lines = {}
            local when = CollectedWhen(event.at)
            if when then
                lines[#lines + 1] = { text = when, color = "muted" }
            end
            if type(meta.houseXP) == "number" and meta.houseXP > 0 then
                lines[#lines + 1] = { text = "+" .. WBF.Format.Number(meta.houseXP) .. " House XP", color = "green" }
            end
            if meta.source and meta.source ~= "" then
                lines[#lines + 1] = { text = meta.source, color = "muted" }
            elseif meta.instanceName or meta.location then
                lines[#lines + 1] = { text = meta.instanceName or meta.location, color = "muted" }
            end
            local row = DecorRow(meta.name, meta.icon, meta.iconAtlas, lines)
            row.event = event
            if meta.quality ~= nil and WBF.Format.QualityColor then
                local r, g, b = WBF.Format.QualityColor(meta.quality)
                row.titleColor = { r, g, b }
            end
            rows[#rows + 1] = row
        end
        model.sections[#model.sections + 1] = { title = "New Decor", rows = rows }
    end

    local acquisitions = WBF.Housing.Acquisitions(events)
    if #acquisitions > 0 then
        local rows = {}
        for index = 1, #acquisitions do
            local entry = acquisitions[index]
            rows[#rows + 1] = DecorRow(entry.name, entry.icon, entry.iconAtlas, nil, "×" .. WBF.Format.Number(entry.count))
        end
        model.sections[#model.sections + 1] = { title = "All Acquisitions", rows = rows }
    end

    local root = WBF.Housing.Root()
    local collection = {}
    for _, row in pairs(root.collected) do
        if type(row) == "table" and InWindow(row.firstAt, summary.startAt, summary.endAt) and (not guid or row.guid == guid) then
            collection[#collection + 1] = row
        end
    end
    table.sort(collection, function(a, b)
        return (a.firstAt or 0) > (b.firstAt or 0)
    end)
    if #collection > 0 then
        local rows = {}
        for index = 1, #collection do
            local entry = collection[index]
            local lines = {}
            local when = CollectedWhen(entry.firstAt)
            if when then
                lines[#lines + 1] = { text = when, color = "muted" }
            end
            if type(entry.houseXP) == "number" and entry.houseXP > 0 then
                lines[#lines + 1] = { text = "+" .. WBF.Format.Number(entry.houseXP) .. " House XP", color = "green" }
            end
            rows[#rows + 1] = DecorRow(entry.name, entry.icon, entry.iconAtlas, lines)
        end
        model.sections[#model.sections + 1] = { title = "Collection", rows = rows }
    end

    if #model.sections == 0 then
        model.empty = "No housing decor recorded during this period."
    end
    return model
end
