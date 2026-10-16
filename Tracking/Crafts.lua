local _, WBF = ...

-- One logical craft per recipe that actually finishes.
-- TRADE_SKILL_CRAFT_BEGIN remembers the recipe. TRADE_SKILL_ITEM_CRAFTED_RESULT
-- can also fire for bonus resources, first-craft rewards, and returned
-- reagents, so a result packet is not itself a craft.
--
-- The primary packet is the one whose item matches the recipe output. When
-- that id is unavailable, the first packet for the pending craft that is not
-- a first-craft reward becomes the craft, and later packets for that same
-- operation do not. A result with no live pending craft is ignored.
--
-- quantity is the awarded amount on that packet. multicraft is stored and
-- is not added to it: the API does not say that quantity excludes the
-- multicraft amount. A later packet of the same output item adds its own
-- quantity to the same craft instead of starting another one.
--
-- Pending crafts are memory only. They expire so a cancelled cast cannot
-- match a result that arrives much later.

WBF.Crafts = {}

local PENDING_TTL = 15
local CACHE_LIMIT = 40

local pending = nil
local closed = nil
local recipeCache = {}
local cacheCount = 0

local function Clock()
    if GetTime then
        local value = WBF.Format.AsNumber(WBF.Format.SafeCall(GetTime))
        if value then
            return value
        end
    end
    return 0
end

local function PlainTable(value)
    if WBF.Format.IsSecret(value) then
        return false
    end
    if issecrettable and issecrettable(value) then
        return false
    end
    return type(value) == "table"
end

local function Positive(value)
    value = WBF.Format.AsNumber(value)
    if not value or value <= 0 then
        return nil
    end
    return value
end

local function Whole(value)
    value = WBF.Format.AsNumber(value)
    if not value or value <= 0 then
        return 0
    end
    return math.floor(value)
end

local function Flag(value)
    return WBF.Format.AsBoolean(value) == true
end

local function Expired(row, clock)
    if type(row) ~= "table" or type(row.startedAt) ~= "number" or type(clock) ~= "number" then
        return true
    end
    if clock < row.startedAt then
        return true
    end
    return (clock - row.startedAt) > PENDING_TTL
end

local function ChannelOn()
    if not (WBF.Database and WBF.Database.IsReady and WBF.Database.IsReady()) then
        return false
    end
    local db = WBF.Database.Get()
    return type(db) == "table" and type(db.config) == "table" and db.config.debugCrafts == true
end

local function Trace(message)
    if not ChannelOn() then
        return
    end
    for line in string.gmatch(tostring(message), "[^\n]+") do
        print("|cffd4af37WarbandFYI|r", line)
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

local function LineName(info)
    if not PlainTable(info) then
        return nil
    end
    local name = WBF.Format.PlainString(info.professionName) or WBF.Format.PlainString(info.parentProfessionName)
    if not name then
        return nil
    end
    local expansion = WBF.Format.PlainString(info.expansionName)
    if expansion and not name:find(expansion, 1, true) then
        name = expansion .. " " .. name
    end
    return name
end

local function ItemName(link, itemID)
    if type(link) == "string" then
        local fromLink = link:match("%[(.-)%]")
        if type(fromLink) == "string" and fromLink ~= "" then
            return fromLink
        end
    end
    if itemID and C_Item and C_Item.GetItemNameByID then
        local name = WBF.Format.PlainString(WBF.Format.SafeCall(C_Item.GetItemNameByID, itemID))
        if name then
            return name
        end
    end
    if itemID and C_Item and C_Item.GetItemInfo then
        local name = WBF.Format.PlainString(WBF.Format.SafeCall(C_Item.GetItemInfo, itemID))
        if name then
            return name
        end
    end
    return nil
end

local function ReadOrder(recipeID)
    local api = C_CraftingOrders
    if type(api) ~= "table" or type(api.GetClaimedOrder) ~= "function" then
        return nil
    end
    local order = WBF.Format.SafeCall(api.GetClaimedOrder)
    if not PlainTable(order) then
        return nil
    end
    local orderRecipe = Positive(order.spellID or order.recipeID or order.recipeSpellID)
    local orderID = Positive(order.orderID)
    if not orderRecipe or not orderID or orderRecipe ~= recipeID then
        return nil
    end
    return orderID
end

local function ReadSchematic(recipeID, isRecraft)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
        return nil
    end
    local schematic = WBF.Format.SafeCall(C_TradeSkillUI.GetRecipeSchematic, recipeID, isRecraft == true)
    if not PlainTable(schematic) then
        return nil
    end
    return schematic
end

local function Lookup(recipeID)
    local cached = recipeCache[recipeID]
    if cached then
        return cached
    end
    local info = {
        recipeID = recipeID,
        recipeName = nil,
        professionName = nil,
        recipeType = nil,
        expectedOutputItemID = nil,
        expectedOutputLink = nil,
        isRecraft = false,
        source = "craft",
        orderID = nil,
    }
    local schematic = ReadSchematic(recipeID, false)
    if schematic and not Positive(schematic.outputItemID) then
        local recraft = ReadSchematic(recipeID, true)
        if recraft and (Positive(recraft.outputItemID) or Flag(recraft.isRecraft)) then
            schematic = recraft
        end
    end
    if schematic then
        info.recipeName = WBF.Format.PlainString(schematic.name)
        info.recipeType = Positive(schematic.recipeType) or WBF.Format.PlainString(schematic.recipeType)
        info.expectedOutputItemID = Positive(schematic.outputItemID)
        info.isRecraft = Flag(schematic.isRecraft)
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeOutputItemData then
        local output = WBF.Format.SafeCall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
        if PlainTable(output) then
            local itemID = Positive(output.itemID)
            if itemID then
                info.expectedOutputItemID = itemID
            end
            local link = WBF.Format.PlainString(output.hyperlink)
            if link then
                info.expectedOutputLink = link
            end
        end
    end
    if not info.recipeName and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local recipe = WBF.Format.SafeCall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if PlainTable(recipe) then
            info.recipeName = WBF.Format.PlainString(recipe.name)
        end
    end
    if not info.recipeName and C_Spell and C_Spell.GetSpellName then
        info.recipeName = WBF.Format.PlainString(WBF.Format.SafeCall(C_Spell.GetSpellName, recipeID))
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoByRecipeID then
        info.professionName = LineName(WBF.Format.SafeCall(C_TradeSkillUI.GetProfessionInfoByRecipeID, recipeID))
    end
    local orderID = ReadOrder(recipeID)
    if orderID then
        info.source = "crafting_order"
        info.orderID = orderID
    end
    if info.recipeName or info.expectedOutputItemID or info.professionName then
        if cacheCount >= CACHE_LIMIT then
            recipeCache = {}
            cacheCount = 0
        end
        recipeCache[recipeID] = info
        cacheCount = cacheCount + 1
    end
    return info
end

local function CopyResult(data)
    if not PlainTable(data) then
        return nil
    end
    local itemID = Positive(data.itemID)
    return {
        itemID = itemID,
        quantity = WBF.Format.AsNumber(data.quantity),
        hyperlink = WBF.Format.PlainString(data.hyperlink),
        craftingQuality = Positive(data.craftingQuality),
        multicraft = Whole(data.multicraft),
        operationID = Positive(data.operationID),
        firstCraftReward = Flag(data.firstCraftReward),
        isEnchant = Flag(data.isEnchant),
        hasIngenuityProc = Flag(data.hasIngenuityProc),
        concentrationCurrencyID = Positive(data.concentrationCurrencyID),
        concentrationSpent = Whole(data.concentrationSpent),
        ingenuityRefund = Whole(data.ingenuityRefund),
        bonusCraft = Flag(data.bonusCraft),
    }
end

-- Awarded stack on this packet. multicraft is not included again.
local function AwardedQuantity(result)
    return Whole(result and result.quantity)
end

local function StateFrom(row)
    return {
        recorded = row.recorded == true,
        expectedItemID = row.expectedOutputItemID,
        primaryItemID = row.primaryItemID,
        operationID = row.operationID,
        lastQuantity = row.lastQuantity,
        lastBonus = row.lastBonus == true,
    }
end

-- primary: this packet is the craft.
-- extra: more of the same output from the craft already recorded.
-- duplicate: the same packet seen again.
-- secondary: another reward from the operation, not a craft.
function WBF.Crafts.Classify(state, result)
    state = type(state) == "table" and state or {}
    result = type(result) == "table" and result or {}
    local itemID = result.itemID
    local expected = state.expectedItemID
    local sameItem = itemID and state.primaryItemID and itemID == state.primaryItemID

    if state.recorded and sameItem then
        local sameOperation = not state.operationID or not result.operationID or state.operationID == result.operationID
        if sameOperation and result.quantity == state.lastQuantity and result.bonusCraft == state.lastBonus then
            return "duplicate", "duplicate result"
        end
        if sameOperation then
            return "extra", "additional output of the same craft"
        end
        return "secondary", "different operation"
    end

    if state.recorded then
        return "secondary", "secondary output"
    end

    if result.firstCraftReward and (not expected or not itemID or itemID ~= expected) then
        return "secondary", "first craft reward"
    end

    if expected and itemID and itemID == expected then
        return "primary", "expected output"
    end

    if result.isEnchant and (not expected or not itemID or itemID == expected) then
        return "primary", "enchant"
    end

    if expected and (not itemID or itemID ~= expected) then
        return "secondary", "not the expected output"
    end

    -- Output item id was not available. The first non-reward packet correlated
    -- with the pending craft is the craft. Later packets stay secondary
    -- unless they are more of that same item.
    if not expected and itemID and not result.firstCraftReward then
        return "primary", "fallback pending craft"
    end

    return "secondary", "unmatched"
end

local function QualityAtlas(quality)
    if type(quality) == "number" and quality >= 1 and quality <= 5 then
        return "Professions-ChatIcon-Quality-Tier" .. math.floor(quality)
    end
    return "Professions-ChatIcon-Quality-Tier1"
end

local function CraftLabel(itemName, recipeName, isEnchant)
    if type(itemName) == "string" and itemName ~= "" then
        return itemName
    end
    if type(recipeName) == "string" and recipeName ~= "" then
        return recipeName
    end
    if isEnchant then
        return "Enchant"
    end
    return "Item"
end

local function ApplyText(event)
    local meta = event.meta or {}
    local label = CraftLabel(meta.itemName, meta.recipeName, meta.isEnchant == true)
    if (meta.quantity or 0) > 1 then
        label = label .. " x" .. tostring(meta.quantity)
    end
    event.text = "Crafted: " .. label
    meta.eventLabel = event.text
end

local function DetailText(profession, spent)
    local detail = type(profession) == "string" and profession or ""
    if type(spent) == "number" and spent > 0 then
        local bit = WBF.Format.Number(spent) .. " concentration"
        if detail ~= "" then
            detail = detail .. "  ·  " .. bit
        else
            detail = bit
        end
    end
    return detail
end

local function FindEvent(id)
    if not id or not (WBF.Database and WBF.Database.Get) then
        return nil
    end
    local db = WBF.Database.Get()
    local events = db and db.events
    if type(events) ~= "table" then
        return nil
    end
    for index = #events, 1, -1 do
        if events[index].id == id then
            return events[index]
        end
    end
    return nil
end

local function Snapshot(row)
    return {
        recorded = true,
        recipeID = row.recipeID,
        recipeName = row.recipeName,
        professionName = row.professionName,
        expectedOutputItemID = row.expectedOutputItemID,
        primaryItemID = row.primaryItemID,
        operationID = row.operationID,
        lastQuantity = row.lastQuantity,
        lastBonus = row.lastBonus == true,
        eventId = row.eventId,
        startedAt = row.startedAt,
        simulated = row.simulated == true,
    }
end

local function Record(row, result)
    local quantity = AwardedQuantity(result)
    local itemName = ItemName(result.hyperlink, result.itemID)
    local spent = result.concentrationSpent or 0
    local meta = {
        recipeID = row.recipeID,
        recipeName = row.recipeName,
        itemID = result.itemID,
        itemLink = result.hyperlink,
        itemName = itemName,
        quantity = quantity,
        craftingQuality = result.craftingQuality,
        profession = row.professionName,
        operationID = result.operationID or row.operationID,
        isEnchant = result.isEnchant == true,
        isRecraft = row.isRecraft == true,
        multicraft = result.multicraft or 0,
        concentrationSpent = spent,
        concentrationCurrencyID = result.concentrationCurrencyID,
        ingenuityProc = result.hasIngenuityProc == true,
        ingenuityRefund = result.ingenuityRefund or 0,
        firstCraftReward = result.firstCraftReward == true,
        source = row.source or "craft",
        orderID = row.orderID,
        iconAtlas = QualityAtlas(result.craftingQuality),
        detail = DetailText(row.professionName, spent),
    }
    if row.simulated then
        meta.simulated = true
    end
    local event = WBF.Events and WBF.Events.Add and WBF.Events.Add({
        category = WBF.Category and WBF.Category.Profession or "profession",
        eventType = WBF.EventType and WBF.EventType.Craft or "craft",
        text = "Crafted",
        meta = meta,
    })
    if event then
        ApplyText(event)
    end
    return event
end

local function AddExtra(row, result)
    local event = FindEvent(row.eventId)
    local quantity = AwardedQuantity(result)
    if not event or type(event.meta) ~= "table" or quantity <= 0 then
        Trace("Craft result ignored as secondary output\nitem=" .. tostring(result.itemID or "?") .. "\noperation=" .. tostring(result.operationID or "?"))
        return false
    end
    local meta = event.meta
    meta.quantity = (meta.quantity or 0) + quantity
    if (result.multicraft or 0) > (meta.multicraft or 0) then
        meta.multicraft = result.multicraft
    end
    if not meta.itemName then
        meta.itemName = ItemName(result.hyperlink, result.itemID)
    end
    ApplyText(event)
    row.lastQuantity = result.quantity
    row.lastBonus = result.bonusCraft == true
    Dirty()
    Trace("Craft result\nrecipe=" .. tostring(row.recipeID or "?") .. "\nitem=" .. tostring(result.itemID or "?") .. "\nqty=" .. tostring(quantity) .. "\nquality=" .. tostring(result.craftingQuality or "?") .. "\noperation=" .. tostring(result.operationID or "?") .. "\nconcentration=0\nprimary=false\n\nCraft recorded\ncrafts=1\nitems=" .. tostring(meta.quantity))
    return true
end

local function AcceptPrimary(row, result, event)
    row.recorded = true
    row.primaryItemID = result.itemID
    row.operationID = result.operationID or row.operationID
    row.lastQuantity = result.quantity
    row.lastBonus = result.bonusCraft == true
    row.eventId = event.id
    closed = Snapshot(row)
end

function WBF.Crafts.Reset()
    pending = nil
    closed = nil
    recipeCache = {}
    cacheCount = 0
end

function WBF.Crafts.HasPending(clock)
    clock = clock or Clock()
    if pending and Expired(pending, clock) then
        pending = nil
    end
    return pending ~= nil
end

function WBF.Crafts.Begin(recipeSpellID, clock, info)
    clock = clock or Clock()
    recipeSpellID = Positive(recipeSpellID)
    if not recipeSpellID then
        return nil
    end
    if pending and pending.recorded then
        closed = Snapshot(pending)
    end
    if pending and Expired(pending, clock) then
        pending = nil
    end
    if not PlainTable(info) then
        info = Lookup(recipeSpellID)
    end
    pending = {
        recipeID = recipeSpellID,
        startedAt = clock,
        expectedOutputItemID = Positive(info.expectedOutputItemID),
        expectedOutputLink = WBF.Format.PlainString(info.expectedOutputLink),
        recipeName = WBF.Format.PlainString(info.recipeName),
        professionName = WBF.Format.PlainString(info.professionName),
        recipeType = info.recipeType,
        isRecraft = info.isRecraft == true,
        source = info.source == "crafting_order" and "crafting_order" or "craft",
        orderID = Positive(info.orderID),
        simulated = info.simulated == true,
        recorded = false,
        primaryItemID = nil,
        operationID = nil,
        lastQuantity = nil,
        lastBonus = false,
        eventId = nil,
    }
    Trace("Craft begin\nrecipe=" .. tostring(recipeSpellID) .. "\nname=" .. tostring(pending.recipeName or "?") .. "\nexpectedItem=" .. tostring(pending.expectedOutputItemID or "?"))
    return pending
end

function WBF.Crafts.Result(data, clock)
    clock = clock or Clock()
    local result = CopyResult(data)
    if not result then
        Trace("Craft result ignored\nreason=unreadable")
        return "ignore"
    end
    if pending and Expired(pending, clock) then
        pending = nil
    end
    if closed and Expired(closed, clock) then
        closed = nil
    end

    local row = nil
    if pending and not pending.recorded and closed and result.operationID and closed.operationID and result.operationID == closed.operationID then
        row = closed
    elseif pending then
        row = pending
    elseif closed and result.operationID and closed.operationID and result.operationID == closed.operationID then
        row = closed
    end
    if not row then
        Trace("Craft result ignored\nreason=no pending craft\nitem=" .. tostring(result.itemID or "?") .. "\noperation=" .. tostring(result.operationID or "?"))
        return "ignore"
    end

    local role, reason = WBF.Crafts.Classify(StateFrom(row), result)
    if role == "primary" then
        local event = Record(row, result)
        if not event then
            Trace("Craft result ignored\nreason=not recorded")
            return "ignore"
        end
        AcceptPrimary(row, result, event)
        local quantity = event.meta and event.meta.quantity or 0
        Trace("Craft result\nrecipe=" .. tostring(row.recipeID or "?") .. "\nitem=" .. tostring(result.itemID or "?") .. "\nqty=" .. tostring(quantity) .. "\nquality=" .. tostring(result.craftingQuality or "?") .. "\noperation=" .. tostring(result.operationID or "?") .. "\nconcentration=" .. tostring(result.concentrationSpent or 0) .. "\nprimary=true\n\nCraft recorded\ncrafts=1\nitems=" .. tostring(quantity))
        return "primary"
    end
    if role == "extra" then
        if AddExtra(row, result) then
            if row == pending then
                closed = Snapshot(pending)
            end
            return "extra"
        end
        return "secondary"
    end
    Trace("Craft result ignored as secondary output\nitem=" .. tostring(result.itemID or "?") .. "\noperation=" .. tostring(result.operationID or "?") .. "\nreason=" .. tostring(reason))
    return role == "duplicate" and "duplicate" or "secondary"
end

function WBF.Crafts.ApplyEvent(bucket, event)
    if type(bucket) ~= "table" or type(event) ~= "table" or event.sample then
        return false
    end
    local kind = WBF.EventType and WBF.EventType.Craft or "craft"
    if event.eventType ~= kind then
        return false
    end
    local meta = event.meta or {}
    local quantity = meta.quantity
    if type(quantity) ~= "number" or quantity < 0 then
        quantity = 0
    end
    local spent = meta.concentrationSpent
    if type(spent) ~= "number" or spent < 0 then
        spent = 0
    end
    bucket.crafts = (bucket.crafts or 0) + 1
    bucket.itemsCrafted = (bucket.itemsCrafted or 0) + quantity
    bucket.concentrationSpent = (bucket.concentrationSpent or 0) + spent
    return true
end

local function AddProfession(map, name, crafts, items, spent)
    if type(crafts) ~= "number" or crafts == 0 then
        return
    end
    if type(name) ~= "string" or name == "" then
        name = "Profession"
    end
    local row = map[name]
    if not row then
        row = { name = name, crafts = 0, items = 0, concentrationSpent = 0 }
        map[name] = row
    end
    row.crafts = row.crafts + crafts
    row.items = row.items + (type(items) == "number" and items or 0)
    row.concentrationSpent = row.concentrationSpent + (type(spent) == "number" and spent or 0)
end

local function ProfessionList(map)
    local list = {}
    for _, row in pairs(map) do
        list[#list + 1] = row
    end
    table.sort(list, function(a, b)
        if a.crafts == b.crafts then
            return (a.name or "") < (b.name or "")
        end
        return a.crafts > b.crafts
    end)
    return list
end

local function FoldProfession(map, name, items, spent)
    if type(map) ~= "table" then
        return
    end
    if type(name) ~= "string" or name == "" then
        name = "Profession"
    end
    local row = map[name]
    if type(row) ~= "table" then
        row = { crafts = 0, items = 0, concentrationSpent = 0 }
        map[name] = row
    end
    row.crafts = (row.crafts or 0) + 1
    row.items = (row.items or 0) + (type(items) == "number" and items or 0)
    row.concentrationSpent = (row.concentrationSpent or 0) + (type(spent) == "number" and spent or 0)
end

function WBF.Crafts.FoldEvent(life, event)
    if type(life) ~= "table" or type(event) ~= "table" or event.sample then
        return
    end
    if type(event.meta) == "table" and event.meta.simulated then
        return
    end
    local kind = WBF.EventType and WBF.EventType.Craft or "craft"
    if event.eventType ~= kind then
        return
    end
    local meta = event.meta or {}
    if type(life.crafting) ~= "table" then
        life.crafting = {}
    end
    if type(life.crafting.professions) ~= "table" then
        life.crafting.professions = {}
    end
    FoldProfession(life.crafting.professions, meta.profession, meta.quantity, meta.concentrationSpent)
    if type(event.guid) == "string" and type(life.characters) == "table" then
        local character = life.characters[event.guid]
        if type(character) == "table" then
            if type(character.crafting) ~= "table" then
                character.crafting = {}
            end
            if type(character.crafting.professions) ~= "table" then
                character.crafting.professions = {}
            end
            FoldProfession(character.crafting.professions, meta.profession, meta.quantity, meta.concentrationSpent)
        end
    end
end

function WBF.Crafts.Collect(db, startAt, endAt, guid)
    local map = {}
    local crafts, items, spent = 0, 0, 0
    local function take(name, nCrafts, nItems, nSpent)
        AddProfession(map, name, nCrafts, nItems, nSpent)
        crafts = crafts + (nCrafts or 0)
        items = items + (type(nItems) == "number" and nItems or 0)
        spent = spent + (type(nSpent) == "number" and nSpent or 0)
    end
    local events = type(db) == "table" and db.events or {}
    local kind = WBF.EventType and WBF.EventType.Craft or "craft"
    for index = 1, #events do
        local event = events[index]
        local at = event.at or 0
        local meta = event.meta or {}
        local inRange = (not startAt or at >= startAt) and (not endAt or at <= endAt)
        if inRange and event.eventType == kind and not event.sample and (not guid or event.guid == guid) then
            take(meta.profession, 1, meta.quantity, meta.concentrationSpent)
        end
    end
    if (not startAt or startAt <= 0) and type(db) == "table" and type(db.lifetime) == "table" then
        local stored = nil
        if guid then
            local character = db.lifetime.characters and db.lifetime.characters[guid]
            stored = character and character.crafting
        else
            stored = db.lifetime.crafting
        end
        local professions = stored and stored.professions
        if type(professions) == "table" then
            for name, row in pairs(professions) do
                if type(row) == "table" then
                    take(type(name) == "string" and name or row.name, row.crafts or 0, row.items, row.concentrationSpent)
                end
            end
        end
    end
    return {
        crafts = crafts,
        items = items,
        concentrationSpent = spent,
        professions = ProfessionList(map),
    }
end

function WBF.Crafts.Attach(summary, db)
    if type(summary) ~= "table" then
        return
    end
    summary.crafting = WBF.Crafts.Collect(db, summary.startAt, summary.endAt, nil)
    local characters = summary.characters or {}
    for index = 1, #characters do
        local row = characters[index]
        row.crafting = WBF.Crafts.Collect(db, summary.startAt, summary.endAt, row.guid)
    end
end

function WBF.Crafts.PeriodStats(guid, startAt, endAt, professionLabel)
    local db = WBF.Database and WBF.Database.Get and WBF.Database.Get() or nil
    local collected = WBF.Crafts.Collect(db, startAt, endAt, guid)
    if not professionLabel then
        return {
            crafts = collected.crafts,
            items = collected.items,
            concentrationSpent = collected.concentrationSpent,
        }
    end
    local list = collected.professions or {}
    for index = 1, #list do
        if list[index].name == professionLabel then
            return list[index]
        end
    end
    if WBF.Professions and WBF.Professions.Same then
        local hits = {}
        for index = 1, #list do
            if WBF.Professions.Same(professionLabel, list[index].name or "") then
                hits[#hits + 1] = list[index]
            end
        end
        if #hits == 1 then
            return hits[1]
        end
    end
    return { crafts = 0, items = 0, concentrationSpent = 0 }
end

local function SimulateOne(recipeID, info, result, clock)
    info.simulated = true
    WBF.Crafts.Begin(recipeID, clock, info)
    return WBF.Crafts.Result(result, clock + 1)
end

function WBF.Crafts.Simulate()
    if not (WBF.Database and WBF.Database.IsReady and WBF.Database.IsReady()) then
        return 0
    end
    local clock = Clock()
    local cases = {
        {
            recipeID = 900001,
            info = { recipeName = "Simulated Signet", professionName = "Enchanting", expectedOutputItemID = 900101 },
            result = { itemID = 900101, quantity = 1, hyperlink = "|cff1eff00|Hitem:900101|h[Simulated Signet]|h|r", craftingQuality = 3, operationID = 1 },
        },
        {
            recipeID = 900002,
            info = { recipeName = "Simulated Potion", professionName = "Alchemy", expectedOutputItemID = 900102 },
            result = { itemID = 900102, quantity = 5, hyperlink = "|cffffffff|Hitem:900102|h[Simulated Potion]|h|r", operationID = 2 },
        },
        {
            recipeID = 900003,
            info = { recipeName = "Simulated Concentration", professionName = "Enchanting", expectedOutputItemID = 900103 },
            result = { itemID = 900103, quantity = 1, hyperlink = "|cffffffff|Hitem:900103|h[Simulated Concentration]|h|r", concentrationSpent = 75, operationID = 3 },
        },
        {
            recipeID = 900004,
            info = { recipeName = "Simulated Multicraft", professionName = "Alchemy", expectedOutputItemID = 900104 },
            result = { itemID = 900104, quantity = 4, multicraft = 2, hyperlink = "|cffffffff|Hitem:900104|h[Simulated Multicraft]|h|r", operationID = 4 },
        },
        {
            recipeID = 900005,
            info = { recipeName = "Simulated Enchant", professionName = "Enchanting", expectedOutputItemID = nil },
            result = { isEnchant = true, operationID = 5 },
        },
        {
            recipeID = 900006,
            info = { recipeName = "Simulated Reward Craft", professionName = "Alchemy", expectedOutputItemID = 900106 },
            result = { itemID = 900106, quantity = 1, hyperlink = "|cffffffff|Hitem:900106|h[Simulated Reward Craft]|h|r", operationID = 6 },
            extra = { itemID = 900199, quantity = 1, firstCraftReward = true, operationID = 6 },
        },
    }
    local recorded = 0
    for index = 1, #cases do
        local row = cases[index]
        local role = SimulateOne(row.recipeID, row.info, row.result, clock)
        clock = clock + 2
        if role == "primary" then
            recorded = recorded + 1
        end
        if row.extra then
            WBF.Crafts.Result(row.extra, clock)
            clock = clock + 1
        end
    end
    print("|cffd4af37WarbandFYI|r", "recorded", recorded, "simulated crafts. /wbfyi debug crafts clear removes them.")
    return recorded
end

function WBF.Crafts.ClearSimulated()
    if not (WBF.Database and WBF.Database.Get) then
        return 0
    end
    local db = WBF.Database.Get()
    local events = db and db.events
    if type(events) ~= "table" then
        return 0
    end
    local kept = {}
    local removed = 0
    local kind = WBF.EventType and WBF.EventType.Craft or "craft"
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta
        if event.eventType == kind and type(meta) == "table" and meta.simulated then
            removed = removed + 1
        else
            kept[#kept + 1] = event
        end
    end
    db.events = kept
    if removed > 0 then
        Dirty()
    end
    return removed
end

function WBF.Crafts.Debug()
    if not (WBF.Database and WBF.Database.Get) then
        return
    end
    local db = WBF.Database.Get()
    if type(db.config) ~= "table" then
        db.config = {}
    end
    db.config.debugCrafts = not db.config.debugCrafts
    print("|cffd4af37WarbandFYI|r", "crafts debug", db.config.debugCrafts and "on" or "off")
end

function WBF.Crafts.Register(bus)
    bus:On("TRADE_SKILL_CRAFT_BEGIN", function(recipeSpellID)
        if WBF.Format.IsSecret(recipeSpellID) then
            return
        end
        WBF.Crafts.Begin(recipeSpellID)
    end)
    bus:On("TRADE_SKILL_ITEM_CRAFTED_RESULT", function(data)
        WBF.Crafts.Result(data)
    end)
end
