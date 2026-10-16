local _, WBF = ...

-- One resource tracker for currency-tab currencies and inventory items
-- that behave like currencies. Goals are a later layer: each record already
-- stores the delta and the balance after it, which a goal can compare
-- with a cost. WBF.Resources.Watch can register extra resources later
-- without a new tracker.

WBF.Resources = {}

local GAIN = "gain"
local SPEND = "spend"
local GAIN_OBSERVED = "gain_observed"
local LOSS_OBSERVED = "loss_observed"
local TRANSFER = "transfer"
local BASELINE = "baseline"
local SYNC = "sync"

local registry = {}
local order = {}
local byIdentity = {}
local active = {}
local calendarReady = false
local itemScanPending = false
local itemScanGeneration = 0
local recentClaims = {}
local discoveryCount = 0
local scanRunning = false
local scanQueued = false
local scanWaiting = false
local accountApplyQueued = false
local collapsedHeaders = nil

local EVENTS = {
    {
        key = "brewfest",
        name = "Brewfest",
        cadence = "annual",
        match = { "Brewfest" },
        fallback = { start = { 9, 20 }, finish = { 10, 6 } },
    },
    {
        key = "hallows_end",
        name = "Hallow's End",
        cadence = "annual",
        match = { "Hallow's End", "Hallows End" },
        fallback = { start = { 10, 18 }, finish = { 11, 1 } },
    },
    {
        key = "timewalking",
        name = "Timewalking",
        cadence = "variant",
        match = { "Timewalking", "Turbulent Timeways" },
    },
    {
        key = "darkmoon",
        name = "Darkmoon Faire",
        cadence = "monthly",
        match = { "Darkmoon Faire" },
    },
    {
        key = "winter_veil",
        name = "Winter Veil",
        cadence = "annual",
        match = { "Winter Veil" },
        fallback = { start = { 12, 15 }, finish = { 1, 2 } },
    },
    {
        key = "lunar_festival",
        name = "Lunar Festival",
        cadence = "annual",
        match = { "Lunar Festival" },
        fallback = { start = { 1, 20 }, finish = { 2, 20 } },
    },
    {
        key = "love_air",
        name = "Love is in the Air",
        cadence = "annual",
        match = { "Love is in the Air" },
        fallback = { start = { 2, 3 }, finish = { 2, 17 } },
    },
    {
        key = "noblegarden",
        name = "Noblegarden",
        cadence = "annual",
        match = { "Noblegarden" },
    },
    {
        key = "trial_of_style",
        name = "Trial of Style",
        cadence = "occurrence",
        match = { "Trial of Style" },
    },
    {
        key = "midsummer",
        name = "Midsummer Fire Festival",
        cadence = "annual",
        match = { "Midsummer" },
        fallback = { start = { 6, 21 }, finish = { 7, 5 } },
    },
}

local function Register(definition)
    if type(definition) ~= "table" or not definition.key or not definition.id then
        return
    end
    if definition.trackingType ~= "currency" and definition.trackingType ~= "item" then
        return
    end
    if registry[definition.key] then
        return
    end
    definition.eventKey = definition.eventKey or nil
    if definition.eventKey and not definition.group then
        definition.group = "events"
    end
    if not definition.classification then
        if definition.trackingType == "item" and definition.eventKey then
            definition.classification = "EVENT_ITEM_RESOURCE"
        elseif definition.trackingType == "item" then
            definition.classification = "ITEM_RESOURCE"
        end
    end
    definition.priority = definition.priority or "normal"
    if definition.trackingType == "currency" and type(definition.key) == "string" and not definition.key:match("^currency_%d+$") then
        definition.playerClass = definition.playerClass or "player"
        definition.playerClassReason = definition.playerClassReason or "authored"
    end
    registry[definition.key] = definition
    order[#order + 1] = definition.key
    byIdentity[definition.trackingType .. ":" .. definition.id] = definition
end

function WBF.Resources.Register(definition)
    Register(definition)
end

function WBF.Resources.Get(key)
    return registry[key]
end

function WBF.Resources.ResolveKey(value)
    if type(value) == "string" and registry[value] then
        return value
    end
    local wanted = tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if wanted == "" then
        return nil
    end
    local partial = nil
    for key, definition in pairs(registry) do
        local id = tostring(definition.id or ""):lower()
        local name = tostring(definition.name or ""):lower()
        local short = tostring(definition.short or ""):lower()
        if wanted == key:lower() or wanted == id or wanted == name or wanted == short then
            return key
        end
        if not partial and (name:find(wanted, 1, true) or short:find(wanted, 1, true) or key:lower():find(wanted, 1, true)) then
            partial = key
        end
    end
    return partial
end

function WBF.Resources.Each()
    local list = {}
    for index = 1, #order do
        list[index] = registry[order[index]]
    end
    return list
end

-- Currency 1166 and 515 match the live currency list.
-- Trial of Style is currency 1379 now. Item 151134 is the older token.
Register({
    key = "brewfest_token",
    name = "Brewfest Prize Token",
    short = "Brewfest Tokens",
    trackingType = "item",
    id = 37829,
    eventKey = "brewfest",
    milestones = {
        { amount = 100, scope = "event" },
        { amount = 300, scope = "event" },
        { amount = 600, scope = "event" },
    },
})
Register({
    key = "tricky_treat",
    name = "Tricky Treat",
    short = "Tricky Treats",
    trackingType = "item",
    id = 33226,
    eventKey = "hallows_end",
})
Register({
    key = "timewarped_badge",
    name = "Timewarped Badge",
    short = "Timewarped Badges",
    trackingType = "currency",
    id = 1166,
    eventKey = "timewalking",
    milestones = {
        { amount = 1000, scope = "period" },
    },
})
Register({
    key = "darkmoon_ticket",
    name = "Darkmoon Prize Ticket",
    short = "Darkmoon Tickets",
    trackingType = "currency",
    id = 515,
    eventKey = "darkmoon",
})
Register({
    key = "merry_supplies",
    name = "Merry Supplies",
    short = "Merry Supplies",
    trackingType = "item",
    id = 128659,
    eventKey = "winter_veil",
})
Register({
    key = "coin_of_ancestry",
    name = "Coin of Ancestry",
    short = "Coins of Ancestry",
    trackingType = "item",
    id = 21100,
    eventKey = "lunar_festival",
})
Register({
    key = "love_token",
    name = "Love Token",
    short = "Love Tokens",
    trackingType = "item",
    id = 49927,
    eventKey = "love_air",
})
Register({
    key = "noblegarden_chocolate",
    name = "Noblegarden Chocolate",
    short = "Noblegarden Chocolate",
    trackingType = "item",
    id = 44791,
    eventKey = "noblegarden",
})
Register({
    key = "trial_of_style_token",
    name = "Trial of Style Token",
    short = "Style Tokens",
    trackingType = "currency",
    id = 1379,
    eventKey = "trial_of_style",
})
Register({
    key = "burning_blossom",
    name = "Burning Blossom",
    short = "Burning Blossoms",
    trackingType = "item",
    id = 23247,
    eventKey = "midsummer",
    milestones = {
        { amount = 250, scope = "event" },
    },
})
-- Item 137642 is the current Mark of Honor. It is not currency 121–126 or 321.
Register({
    key = "mark_of_honor",
    name = "Mark of Honor",
    short = "Marks of Honor",
    trackingType = "item",
    id = 137642,
})

-- Confirmed on Wowhead for the live Midnight client. GetCurrencyInfo still
-- has to agree with expectedName before a reading is trusted.
Register({
    key = "voidlight_marl",
    name = "Voidlight Marl",
    short = "Voidlight Marl",
    trackingType = "currency",
    id = 3316,
    group = "expansion",
    priority = "high",
    expansion = "current",
    expectedName = "Voidlight Marl",
    subtitle = "Midnight Currency",
})
Register({
    key = "brimming_arcana",
    name = "Brimming Arcana",
    short = "Brimming Arcana",
    trackingType = "currency",
    id = 3379,
    group = "expansion",
    priority = "high",
    expansion = "current",
    expectedName = "Brimming Arcana",
})
Register({
    key = "field_accolade",
    name = "Field Accolade",
    short = "Field Accolades",
    trackingType = "currency",
    id = 3405,
    group = "expansion",
    priority = "high",
    expansion = "current",
    expectedName = "Field Accolade",
})
Register({
    key = "unalloyed_abundance",
    name = "Unalloyed Abundance",
    short = "Unalloyed Abundance",
    trackingType = "currency",
    id = 3377,
    group = "expansion",
    priority = "high",
    expansion = "current",
    expectedName = "Unalloyed Abundance",
})
Register({
    key = "undercoin",
    name = "Undercoin",
    short = "Undercoin",
    trackingType = "currency",
    id = 2803,
    group = "expansion",
    priority = "normal",
    expansion = "current",
    expectedName = "Undercoin",
})
Register({
    key = "reservoir_anima",
    name = "Reservoir Anima",
    short = "Reservoir Anima",
    trackingType = "currency",
    id = 1813,
    group = "legacy",
    priority = "low",
    expectedName = "Reservoir Anima",
})
Register({
    key = "stygia",
    name = "Stygia",
    short = "Stygia",
    trackingType = "currency",
    id = 1767,
    group = "legacy",
    priority = "low",
    expectedName = "Stygia",
})
Register({
    key = "order_resources",
    name = "Order Resources",
    short = "Order Resources",
    trackingType = "currency",
    id = 1220,
    group = "legacy",
    priority = "low",
    expectedName = "Order Resources",
})
Register({
    key = "dragon_isles_supplies",
    name = "Dragon Isles Supplies",
    short = "Dragon Isles Supplies",
    trackingType = "currency",
    id = 2003,
    group = "legacy",
    priority = "low",
    expectedName = "Dragon Isles Supplies",
})

local function Store()
    local db = WBF.Database.Get()
    if type(db.resources) ~= "table" then
        db.resources = {}
    end
    if type(db.resources.balances) ~= "table" then
        db.resources.balances = {}
    end
    if type(db.resources.watched) ~= "table" then
        db.resources.watched = {}
    end
    if type(db.resources.definitions) ~= "table" then
        db.resources.definitions = {}
    end
    if type(db.resources.watchlist) ~= "table" then
        db.resources.watchlist = {}
    end
    if type(db.resources.scanState) ~= "table" then
        db.resources.scanState = {}
    end
    return db.resources
end

local function LoadWatched()
    if not WBF.Database.IsReady() then
        return
    end
    local store = Store()
    local watched = store.watched
    for index = 1, #watched do
        Register(watched[index])
    end
    for key, saved in pairs(store.definitions) do
        if type(saved) == "table" and saved.key then
            if not registry[saved.key] then
                Register(saved)
            end
            local definition = registry[saved.key]
            if definition then
                if saved.iconFile then
                    definition.iconFile = saved.iconFile
                end
                if saved.displayName then
                    definition.displayName = saved.displayName
                end
                if saved.classification then
                    definition.classification = saved.classification
                end
                if saved.header then
                    definition.header = saved.header
                end
                if saved.group and not definition.group then
                    definition.group = saved.group
                end
                if saved.subtitle then
                    definition.subtitle = saved.subtitle
                end
                if saved.behaviour then
                    definition.behaviour = saved.behaviour
                end
                if saved.maximum then
                    definition.maximum = saved.maximum
                end
                if saved.professionLabel then
                    definition.professionLabel = saved.professionLabel
                end
                if saved.playerClass == "player" or saved.playerClass == "system" or saved.playerClass == "unknown" then
                    definition.playerClass = saved.playerClass
                end
                if type(saved.playerClassReason) == "string" and saved.playerClassReason ~= "" then
                    definition.playerClassReason = saved.playerClassReason
                end
                if WBF.ResourceClassification and WBF.ResourceClassification.Apply and definition.trackingType == "currency" then
                    local info
                    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and definition.id then
                        local ok, result = pcall(C_CurrencyInfo.GetCurrencyInfo, definition.id)
                        if ok and type(result) == "table" then
                            info = result
                        end
                    end
                    if info or definition.playerClass == nil then
                        WBF.ResourceClassification.Apply(definition, info)
                    end
                end
            end
        end
    end
    if WBF.Resources.MigrateOwnedBalances then
        WBF.Resources.MigrateOwnedBalances()
    end
    if RepairHistory then
        RepairHistory(false)
    end
end

function WBF.Resources.Watch(definition)
    if not definition or not definition.key then
        return
    end
    Register(definition)
    if not registry[definition.key] or not WBF.Database.IsReady() then
        return
    end
    local watched = Store().watched
    for index = 1, #watched do
        if watched[index].key == definition.key then
            return
        end
    end
    watched[#watched + 1] = {
        key = definition.key,
        name = definition.name,
        short = definition.short,
        trackingType = definition.trackingType,
        id = definition.id,
        eventKey = definition.eventKey,
    }
end

local function StateFor(key)
    local balances = Store().balances
    local state = balances[key]
    if type(state) ~= "table" then
        state = { characters = {} }
        balances[key] = state
    end
    if type(state.characters) ~= "table" then
        state.characters = {}
    end
    return state
end

local function PersistDefinition(definition)
    if not definition or not definition.key or not WBF.Database.IsReady() then
        return
    end
    local saved = Store().definitions
    saved[definition.key] = {
        key = definition.key,
        name = definition.name,
        displayName = definition.displayName,
        short = definition.short,
        trackingType = definition.trackingType,
        id = definition.id,
        eventKey = definition.eventKey,
        classification = definition.classification,
        group = definition.group,
        header = definition.header,
        iconFile = definition.iconFile,
        priority = definition.priority,
        expansion = definition.expansion,
        subtitle = definition.subtitle,
        expectedName = definition.expectedName,
        behaviour = definition.behaviour,
        maximum = definition.maximum,
        professionLabel = definition.professionLabel,
        playerClass = definition.playerClass,
        playerClassReason = definition.playerClassReason,
    }
end

local function TouchScan(state, guid, source)
    if not guid then
        return
    end
    if type(state.scanned) ~= "table" then
        state.scanned = {}
    end
    if type(state.sources) ~= "table" then
        state.sources = {}
    end
    state.scanned[guid] = WBF.Time.Now()
    if source then
        state.sources[guid] = source
    end
end

local function RememberCharacterName(state, guid, name)
    name = WBF.Format.PlainString(name)
    if not guid or not name or name == "" then
        return
    end
    if type(state.names) ~= "table" then
        state.names = {}
    end
    state.names[guid] = name
end

local function CanonicalBalance(state)
    if type(state) ~= "table" then
        return nil
    end
    if type(state.currentBalance) == "number" then
        return state.currentBalance
    end
    if type(state.accountWide) == "number" then
        return state.accountWide
    end
    return nil
end

local function IsWarbandCurrency(definition)
    return definition and definition.classification == "ACCOUNT_WIDE_CURRENCY"
end

local function TotalOf(state, definition)
    if IsWarbandCurrency(definition) then
        local canonical = CanonicalBalance(state)
        if type(canonical) == "number" then
            return canonical
        end
        return 0
    end
    local sum = state.account or 0
    for _, amount in pairs(state.characters) do
        if type(amount) == "number" then
            sum = sum + amount
        end
    end
    return sum
end

local function HasCharacters(state)
    return next(state.characters) ~= nil
end

local function CurrentGUID()
    local character = WBF.Characters.GetCurrent()
    return character and character.guid or nil
end

local function SameEnum(value, enumValue)
    if value == nil or enumValue == nil then
        return false
    end
    if value == enumValue then
        return true
    end
    local number = WBF.Format.AsNumber(value)
    return number ~= nil and number == enumValue
end

local function IsTransfer(gainSource, destroyReason)
    local source = Enum and Enum.CurrencySource and Enum.CurrencySource.AccountTransfer
    local reason = Enum and Enum.CurrencyDestroyReason and Enum.CurrencyDestroyReason.AccountTransfer
    return SameEnum(gainSource, source) or SameEnum(destroyReason, reason)
end

local function CountsAsEarned(classification)
    return classification == GAIN or classification == GAIN_OBSERVED
end

local function CountsAsSpent(classification)
    return classification == SPEND or classification == LOSS_OBSERVED
end

local function DisplayName(definition)
    return definition.displayName or definition.name or definition.key
end

local function ShortName(definition)
    return definition.short or DisplayName(definition)
end

local function RememberIcon(definition, icon)
    icon = WBF.Format.AsNumber(icon)
    if icon and icon > 0 then
        definition.iconFile = icon
    end
end

local function RememberName(definition, name)
    name = WBF.Format.PlainString(name)
    if name and name ~= "" then
        definition.displayName = name
    end
end

local function ItemCached(itemID)
    if not C_Item or not C_Item.IsItemDataCachedByID then
        return true
    end
    local ok, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
    if ok and not cached then
        if C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
        return false
    end
    return true
end

local function ItemCount(itemID, includeAccountBank)
    if not C_Item or not C_Item.GetItemCount then
        return nil
    end
    local ok, count = pcall(C_Item.GetItemCount, itemID, true, false, true, includeAccountBank and true or false)
    if not ok then
        return nil
    end
    return WBF.Format.AsNumber(count)
end

local function ReadItemParts(itemID)
    if not ItemCached(itemID) then
        return nil, nil
    end
    local personal = ItemCount(itemID, false)
    local combined = ItemCount(itemID, true)
    if not personal or not combined then
        return nil, nil
    end
    local account = combined - personal
    if account < 0 then
        account = 0
    end
    if C_Item.GetItemIconByID then
        return personal, account, C_Item.GetItemIconByID(itemID)
    end
    return personal, account, nil
end

local function ReadCurrency(currencyID)
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then
        return nil
    end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if not ok or type(info) ~= "table" then
        return nil
    end
    return WBF.Format.AsNumber(info.quantity), info.iconFileID, info.name, info
end

local function CompactName(text)
    text = WBF.Format.PlainString(text) or ""
    text = text:lower():gsub("[^%w]+", "")
    return text
end

local function NameClose(expected, actual)
    local left = CompactName(expected)
    local right = CompactName(actual)
    if left == "" or right == "" then
        return true
    end
    if left == right then
        return true
    end
    return left:find(right, 1, true) ~= nil or right:find(left, 1, true) ~= nil
end

-- Forward-declared. The implementations sit with the ledger, after Record.
local MigrateWarband
local CommitObservation
local RepairHistory

-- Warband currencies share one balance. IsAccountWideCurrency is the authority;
-- the list row's boolean is only a hint, and a secret value must not be tested raw.
local function ReadAccountWide(definition, info)
    if info then
        local flagged = WBF.Format.AsBoolean(info.isAccountWide)
        if flagged == true then
            return true
        end
    end
    local currencyID = definition and definition.id
    if C_CurrencyInfo and C_CurrencyInfo.IsAccountWideCurrency and currencyID then
        local ok, wide = pcall(C_CurrencyInfo.IsAccountWideCurrency, currencyID)
        if ok then
            local parsed = WBF.Format.AsBoolean(wide)
            if parsed ~= nil then
                return parsed
            end
        end
    end
    if info then
        local flagged = WBF.Format.AsBoolean(info.isAccountWide)
        if flagged == false then
            return false
        end
    end
    return nil
end

local function ReadTransferable(definition, info)
    if info then
        local flagged = WBF.Format.AsBoolean(info.isAccountTransferable)
        if flagged ~= nil then
            return flagged
        end
    end
    local currencyID = definition and definition.id
    if C_CurrencyInfo and C_CurrencyInfo.IsAccountTransferableCurrency and currencyID then
        local ok, transferable = pcall(C_CurrencyInfo.IsAccountTransferableCurrency, currencyID)
        if ok then
            return WBF.Format.AsBoolean(transferable)
        end
    end
    return nil
end

local function ApplyCurrencyFlags(definition, info)
    if not definition then
        return
    end
    if type(info) == "table" then
        local liveName = WBF.Format.PlainString(info.name)
        if definition.expectedName and liveName and not NameClose(definition.expectedName, liveName) then
            definition.suppressed = true
            WBF.Debug.Log("resource id mismatch", definition.key, definition.id, liveName)
            return
        end
        definition.suppressed = nil
        RememberIcon(definition, info.iconFileID)
        RememberName(definition, liveName)
        if WBF.ResourceBehaviour then
            local classified = WBF.ResourceBehaviour.Classify(info, definition.displayName or definition.name or liveName)
            if classified ~= WBF.ResourceBehaviour.CURRENCY then
                definition.behaviour = classified
            end
            local maxQty = WBF.Format.AsNumber(info.maxQuantity)
            if maxQty and maxQty > 0 and (classified == WBF.ResourceBehaviour.REGENERATING_METER or definition.behaviour == WBF.ResourceBehaviour.REGENERATING_METER) then
                definition.maximum = maxQty
            end
        end
    end
    if definition.trackingType ~= "currency" then
        PersistDefinition(definition)
        return
    end
    local wide = ReadAccountWide(definition, info)
    if wide == true then
        definition.classification = "ACCOUNT_WIDE_CURRENCY"
        definition.ownership = "warband"
        if not definition.group then
            definition.group = "account"
        end
    elseif wide == false and ReadTransferable(definition, info) == true then
        local wasWarband = definition.classification == "ACCOUNT_WIDE_CURRENCY"
        definition.classification = "WARBAND_TRANSFERABLE_CURRENCY"
        definition.ownership = "character"
        if wasWarband and definition.group == "account" then
            definition.group = nil
        end
    elseif wide == false and (not definition.classification or definition.classification == "ACCOUNT_WIDE_CURRENCY") then
        local wasWarband = definition.classification == "ACCOUNT_WIDE_CURRENCY"
        definition.classification = "CHARACTER_CURRENCY"
        definition.ownership = "character"
        if wasWarband and definition.group == "account" then
            definition.group = nil
        end
    end
    if WBF.ResourceClassification and WBF.ResourceClassification.Apply then
        WBF.ResourceClassification.Apply(definition, info)
    end
    PersistDefinition(definition)
    if IsWarbandCurrency(definition) and MigrateWarband then
        MigrateWarband(definition)
    end
end

local function NoteFreshFind(guid, isNew, amount)
    if not isNew or not amount or amount <= 0 or not guid then
        return
    end
    local current = CurrentGUID()
    if guid ~= current then
        return
    end
    discoveryCount = discoveryCount + 1
end

local function TitleMatches(eventInfo, title)
    if not title or title == "" then
        return false
    end
    for index = 1, #eventInfo.match do
        if title:find(eventInfo.match[index], 1, true) then
            return true
        end
    end
    return false
end

-- Nil means the event kind could not be read. Calendar fields are often secret,
-- and comparing them errors while this addon is on the call stack.
local function IsHoliday(dayEvent)
    local calendarType = dayEvent.calendarType
    local eventType = dayEvent.eventType
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
    if kind == nil or kind == "HOLIDAY" then
        return true
    end
    return holiday ~= nil and kind == holiday
end

local function MonthDayNumber(month, day)
    return month * 100 + day
end

local function InFallback(window, now)
    local parts = date("*t", now or WBF.Time.Now())
    local today = MonthDayNumber(parts.month, parts.day)
    local startAt = MonthDayNumber(window.start[1], window.start[2])
    local finish = MonthDayNumber(window.finish[1], window.finish[2])
    if startAt <= finish then
        return today >= startAt and today <= finish
    end
    return today >= startAt or today <= finish
end

local function Slug(text)
    text = tostring(text or ""):lower()
    text = text:gsub("[^%w]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%s+", "_")
    if text == "" then
        return "event"
    end
    return text
end

local function InstanceFromTime(eventInfo, year, month, sourceName)
    local name = eventInfo.name
    if eventInfo.cadence == "monthly" then
        local stamp = time({ year = year, month = month, day = 1, hour = 12 })
        local label = date("%B %Y", stamp)
        return string.format("%s_%d_%02d", eventInfo.key, year, month), eventInfo.name .. " " .. label, sourceName or eventInfo.name
    end
    if eventInfo.cadence == "variant" or eventInfo.cadence == "occurrence" then
        local label = sourceName or name
        return eventInfo.key .. "_" .. year .. "_" .. Slug(label), label, label
    end
    return eventInfo.key .. "_" .. year, name .. " " .. year, sourceName or name
end

local function FallbackInstance(eventInfo, now)
    if not eventInfo.fallback or not InFallback(eventInfo.fallback, now) then
        if eventInfo.key == "darkmoon" then
            local parts = date("*t", now or WBF.Time.Now())
            local first = date("*t", time({ year = parts.year, month = parts.month, day = 1, hour = 12 }))
            local add = (1 - first.wday) % 7
            local startDay = 1 + add
            if parts.day >= startDay and parts.day <= startDay + 6 then
                local id, name, source = InstanceFromTime(eventInfo, parts.year, parts.month, eventInfo.name)
                return { id = id, name = name, sourceName = source, eventKey = eventInfo.key }
            end
        end
        return nil
    end
    local parts = date("*t", now or WBF.Time.Now())
    local year = parts.year
    if eventInfo.fallback.start[1] > eventInfo.fallback.finish[1] and parts.month <= eventInfo.fallback.finish[1] then
        year = year - 1
    end
    local id, name, source = InstanceFromTime(eventInfo, year, parts.month, eventInfo.name)
    return { id = id, name = name, sourceName = source, eventKey = eventInfo.key }
end

local function CalendarOffset()
    if not C_Calendar or not C_DateAndTime or not C_DateAndTime.GetCurrentCalendarTime then
        return nil
    end
    local now = C_DateAndTime.GetCurrentCalendarTime()
    if type(now) ~= "table" or not now.month or not now.year or not now.monthDay then
        return nil
    end
    local offset = 0
    if C_Calendar.GetMonthInfo then
        local ok, shown = pcall(C_Calendar.GetMonthInfo)
        if ok and type(shown) == "table" and shown.month and shown.year then
            offset = (now.year - shown.year) * 12 + (now.month - shown.month)
        end
    end
    if offset < -1 or offset > 1 then
        local open = CalendarFrame and CalendarFrame.IsShown and CalendarFrame:IsShown()
        if open or not C_Calendar.SetAbsMonth then
            return nil
        end
        pcall(C_Calendar.SetAbsMonth, now.month, now.year)
        offset = 0
    end
    return offset, now
end

local function ScanCalendar()
    local offset, now = CalendarOffset()
    if not offset or not C_Calendar.GetNumDayEvents or not C_Calendar.GetDayEvent then
        return false
    end
    local okNum, num = pcall(C_Calendar.GetNumDayEvents, offset, now.monthDay)
    if not okNum or WBF.Format.IsSecret(num) then
        return false
    end
    num = WBF.Format.AsNumber(num) or 0
    local found = {}
    local sawEvent = false
    local readable = false
    for index = 1, num do
        local okEvent, dayEvent = pcall(C_Calendar.GetDayEvent, offset, now.monthDay, index)
        if okEvent and not WBF.Format.IsSecret(dayEvent) and type(dayEvent) == "table" then
            sawEvent = true
            local holiday = IsHoliday(dayEvent)
            if holiday == nil then
                -- Protected event kind. Leave the date fallback in place.
            elseif not holiday then
                readable = true
            elseif WBF.Format.IsSecret(dayEvent.title) then
                -- Kind is a holiday, but the title cannot be matched.
            else
                readable = true
                local title = WBF.Format.PlainString(dayEvent.title)
                for eventIndex = 1, #EVENTS do
                    local eventInfo = EVENTS[eventIndex]
                    if TitleMatches(eventInfo, title) then
                        local start = dayEvent.startTime
                        local year
                        local month
                        if not WBF.Format.IsSecret(start) and type(start) == "table" then
                            year = WBF.Format.AsNumber(start.year)
                            month = WBF.Format.AsNumber(start.month)
                        end
                        year = year or now.year
                        month = month or now.month
                        local id, name, source = InstanceFromTime(eventInfo, year, month, title)
                        found[eventInfo.key] = {
                            id = id,
                            name = name,
                            sourceName = source or title,
                            eventKey = eventInfo.key,
                        }
                    end
                end
            end
        elseif okEvent then
            sawEvent = true
        end
    end
    if sawEvent and not readable then
        return false
    end
    active = found
    calendarReady = true
    return true
end

local function RefreshActive()
    if calendarReady then
        return
    end
    local now = WBF.Time.Now()
    local found = {}
    for index = 1, #EVENTS do
        local eventInfo = EVENTS[index]
        local instance = FallbackInstance(eventInfo, now)
        if instance then
            found[eventInfo.key] = instance
        end
    end
    active = found
end

function WBF.Resources.ActiveInstance(eventKey)
    return active[eventKey]
end

local function Claim(key, balance, delta, classification)
    local id = tostring(key) .. ":" .. tostring(balance) .. ":" .. tostring(delta) .. ":" .. tostring(classification)
    local now = WBF.Time.Now()
    local previous = recentClaims[id]
    if previous and (now - previous) < 3 then
        if WBF.Database and WBF.Database.NoteMaintenanceStat then
            WBF.Database.NoteMaintenanceStat("resourceDuplicateClaims", 1)
        end
        return false
    end
    recentClaims[id] = now
    return true
end

local function SpecialAbsorb(definition, delta, balanceAfter, classification, previous, guid)
    if not WBF.ResourceBehaviour or not definition then
        return false
    end
    local behaviour = definition.behaviour
    if not behaviour or behaviour == WBF.ResourceBehaviour.CURRENCY then
        behaviour = WBF.ResourceBehaviour.Classify(nil, DisplayName(definition))
    end
    if behaviour ~= WBF.ResourceBehaviour.REGENERATING_METER and behaviour ~= WBF.ResourceBehaviour.PROGRESSION then
        return false
    end
    definition.behaviour = behaviour
    local state = StateFor(definition.key)
    if type(balanceAfter) == "number" then
        state.currentBalance = balanceAfter
        state.acceptedBalance = balanceAfter
        state.lastObservedAt = WBF.Time.Now()
    end
    if definition.maximum then
        state.maximum = definition.maximum
    end
    local amount = delta or 0
    if classification == BASELINE or classification == SYNC or amount == 0 then
        return true
    end
    local profession = definition.professionLabel or WBF.ResourceBehaviour.SubjectName(DisplayName(definition))
    if behaviour == WBF.ResourceBehaviour.REGENERATING_METER then
        if amount > 0 then
            return true
        end
        local used = math.abs(amount)
        if not Claim(definition.key, balanceAfter, amount, "meter_use") then
            return true
        end
        WBF.Events.Add({
            guid = guid,
            category = WBF.Category.Profession,
            eventType = WBF.EventType.Profession,
            delta = amount,
            previous = previous,
            new = balanceAfter,
            text = profession .. "  ·  Concentration used: " .. WBF.Format.Number(used),
            meta = {
                behaviour = behaviour,
                concentrationUsed = used,
                profession = profession,
                current = balanceAfter,
                maximum = definition.maximum,
                eventLabel = "Concentration used",
                detail = WBF.Format.Number(used),
                iconAtlas = "Professions-ChatIcon-Quality-Tier1",
            },
        })
        return true
    end
    if amount > 0 then
        if not Claim(definition.key, balanceAfter, amount, "knowledge_gain") then
            return true
        end
        local label = profession
        if not label:lower():find("knowledge", 1, true) then
            label = label .. " Knowledge"
        end
        WBF.Events.Add({
            guid = guid,
            category = WBF.Category.Profession,
            eventType = WBF.EventType.Profession,
            delta = amount,
            previous = previous,
            new = balanceAfter,
            text = label .. "  " .. WBF.Format.Signed(amount),
            meta = {
                behaviour = behaviour,
                knowledge = amount,
                profession = profession,
                available = balanceAfter,
                eventLabel = "Knowledge gained",
                detail = label .. "  " .. WBF.Format.Signed(amount),
                iconAtlas = "Professions-ChatIcon-Quality-Tier1",
            },
        })
        return true
    end
    if not Claim(definition.key, balanceAfter, amount, "knowledge_spend") then
        return true
    end
    WBF.Events.Add({
        guid = guid,
        category = WBF.Category.Profession,
        eventType = WBF.EventType.Profession,
        delta = amount,
        previous = previous,
        new = balanceAfter,
        text = profession .. " knowledge spent",
        meta = {
            behaviour = behaviour,
            knowledgeSpent = math.abs(amount),
            profession = profession,
            available = balanceAfter,
            surface = false,
        },
    })
    return true
end

local function Record(definition, delta, balanceAfter, classification, previous, guid, sourceLabel, counterpart, atTime)
    if WBF.ResourceClassification and WBF.ResourceClassification.HidesFromPlayer(definition) then
        return nil
    end
    if SpecialAbsorb(definition, delta, balanceAfter, classification, previous, guid) then
        return nil
    end
    if classification ~= BASELINE and (not delta or delta == 0) then
        return nil
    end
    if not Claim(definition.key, balanceAfter, delta or 0, classification) then
        return nil
    end
    local instance = definition.eventKey and active[definition.eventKey] or nil
    local name = ShortName(definition)
    local text
    if classification == BASELINE then
        text = name .. " baseline " .. WBF.Format.Number(balanceAfter or 0)
    elseif classification == SYNC then
        text = name .. " already held " .. WBF.Format.Signed(delta or 0)
    elseif classification == TRANSFER then
        text = name .. " transferred " .. WBF.Format.Signed(delta or 0)
        if counterpart and counterpart ~= "" then
            text = (delta or 0) < 0 and (text .. " to " .. counterpart) or (text .. " from " .. counterpart)
        end
    else
        text = name .. " " .. WBF.Format.Signed(delta or 0)
    end
    local warbandDelta = delta or 0
    if classification == TRANSFER or classification == BASELINE then
        warbandDelta = 0
    end
    if classification ~= BASELINE and classification ~= SYNC then
        local state = StateFor(definition.key)
        state.lastChangeAt = WBF.Time.Now()
    end
    local meta = {
        resourceKey = definition.key,
        resourceType = definition.trackingType,
        resourceID = definition.id,
        balanceAfter = balanceAfter,
        warbandDelta = warbandDelta,
        classification = classification,
        eventInstance = instance and instance.id or nil,
        eventName = instance and instance.name or nil,
        sourceName = instance and instance.sourceName or nil,
        sourceLabel = sourceLabel,
        counterpart = counterpart,
        icon = definition.iconFile,
        name = DisplayName(definition),
    }
    if IsWarbandCurrency(definition) then
        meta.ownership = "warband"
        local state = StateFor(definition.key)
        local observer = guid and state.names and state.names[guid] or nil
        if not observer and guid and WBF.Characters.Get then
            local stored = WBF.Characters.Get(guid)
            observer = stored and stored.name or nil
        end
        if observer and observer ~= "" then
            meta.observer = observer
        end
    end
    local event = WBF.Events.Add({
        at = atTime,
        guid = guid,
        category = WBF.Category.Resource,
        eventType = WBF.EventType.Resource,
        delta = delta or 0,
        previous = previous,
        new = balanceAfter,
        text = text,
        meta = meta,
    })
    if event and WBF.Database and WBF.Database.NoteMaintenanceStat then
        WBF.Database.NoteMaintenanceStat("resourceEventsRecorded", 1)
    end
    return event
end

local WARBAND_LEDGER = 1

local function RememberObserver(state, guid)
    if not guid then
        return
    end
    if type(state.observed) ~= "table" then
        state.observed = {}
    end
    state.observed[guid] = WBF.Time.Now()
    state.observedWhilePlayingCharacter = guid
    local current = WBF.Characters.GetCurrent and WBF.Characters.GetCurrent() or nil
    if current and current.guid == guid then
        RememberCharacterName(state, guid, current.name)
    elseif WBF.Characters.Get then
        local stored = WBF.Characters.Get(guid)
        if stored then
            RememberCharacterName(state, guid, stored.name)
        end
    end
end

local function WriteCanonical(state, definition, balance, now)
    state.ownership = "warband"
    state.currencyID = definition.id
    state.currentBalance = balance
    state.accountWide = balance
    state.acceptedBalance = balance
    state.previousBalance = balance
    if state.openingBalance == nil then
        state.openingBalance = balance
    end
    state.firstObservedAt = state.firstObservedAt or now
    state.lastObservedAt = now
    state.characters = {}
end

-- One canonical balance. A missing quantity is not a zero, and seeing the
-- same balance on another character is not a gain or a spend.
CommitObservation = function(key, quantity, guid, sourced)
    local definition = registry[key]
    if not IsWarbandCurrency(definition) then
        return nil
    end
    quantity = WBF.Format.AsNumber(quantity)
    if quantity == nil then
        return nil
    end
    local state = StateFor(key)
    local now = WBF.Time.Now()
    RememberObserver(state, guid)
    TouchScan(state, guid, "warband")
    state.lastObservedAt = now
    state.currencyID = definition.id
    state.ownership = "warband"
    local previous = CanonicalBalance(state)
    if previous == nil then
        WriteCanonical(state, definition, quantity, now)
        state.previousBalance = quantity
        if quantity > 0 then
            Record(definition, 0, quantity, BASELINE, nil, guid)
        end
        return 0
    end
    state.currentBalance = quantity
    state.accountWide = quantity
    state.acceptedBalance = quantity
    state.characters = {}
    if quantity == previous then
        return 0
    end
    local delta = quantity - previous
    state.previousBalance = previous
    local classification
    if sourced then
        classification = delta > 0 and GAIN or SPEND
    else
        classification = delta > 0 and GAIN_OBSERVED or LOSS_OBSERVED
    end
    Record(definition, delta, quantity, classification, previous, guid)
    return delta
end

local function CharacterMode(state)
    local counts = {}
    local best, bestCount, positive = nil, 0, 0
    for _, amount in pairs(state.characters or {}) do
        if type(amount) == "number" and amount > 0 then
            positive = positive + 1
            counts[amount] = (counts[amount] or 0) + 1
            if counts[amount] > bestCount then
                best = amount
                bestCount = counts[amount]
            end
        end
    end
    return best, bestCount, positive
end

local function ResourceEventFor(event, key)
    if not event or event.eventType ~= WBF.EventType.Resource then
        return false
    end
    local meta = event.meta or {}
    return meta.resourceKey == key
end

local function EchoedBalance(events, key)
    local owners = {}
    for index = 1, #events do
        local event = events[index]
        if ResourceEventFor(event, key) then
            local delta = math.abs(event.delta or 0)
            local guid = event.guid
            if delta > 0 and guid then
                local bucket = owners[delta]
                if not bucket then
                    bucket = {}
                    owners[delta] = bucket
                end
                bucket[guid] = true
            end
        end
    end
    local best, bestCount
    for delta, guids in pairs(owners) do
        local count = 0
        for _ in pairs(guids) do
            count = count + 1
        end
        if count >= 2 and (not bestCount or count > bestCount) then
            best = delta
            bestCount = count
        end
    end
    return best
end

local function ChooseShared(state, echoed)
    local mode, modeCount, positive = CharacterMode(state)
    local wide = CanonicalBalance(state)
    if type(wide) == "number" and mode and modeCount >= 2 and positive >= 2 and wide == mode * positive then
        return mode
    end
    if type(wide) == "number" then
        return wide
    end
    if mode and modeCount >= 2 then
        return mode
    end
    return echoed
end

local function MultipleOf(amount, shared)
    if type(amount) ~= "number" or type(shared) ~= "number" or shared <= 0 then
        return false
    end
    if amount <= shared then
        return false
    end
    return amount % shared == 0
end

local function SyntheticWarbandEvent(event, shared, stripEchoes)
    local meta = event.meta or {}
    local classification = meta.classification
    local delta = event.delta or 0
    if classification == SYNC or classification == TRANSFER then
        return true
    end
    if not stripEchoes or not shared or shared <= 0 then
        return false
    end
    if classification ~= BASELINE and math.abs(delta) == shared then
        return true
    end
    if MultipleOf(meta.balanceAfter, shared) then
        return true
    end
    if classification == BASELINE and meta.balanceAfter ~= shared and MultipleOf(meta.balanceAfter, shared) then
        return true
    end
    return false
end

-- Collapses per-character copies of a Warband balance. Other resources'
-- events stay where they are. Runs once per currency.
MigrateWarband = function(definition)
    if not IsWarbandCurrency(definition) or not WBF.Database.IsReady() then
        return
    end
    local state = StateFor(definition.key)
    if state.warbandLedger == WARBAND_LEDGER then
        state.characters = {}
        return
    end
    local db = WBF.Database.Get()
    local events = db.events or {}
    local mode, modeCount = CharacterMode(state)
    local echoed = EchoedBalance(events, definition.key)
    local shared = ChooseShared(state, echoed)
    local stripEchoes = (modeCount >= 2) or (echoed ~= nil and echoed == shared)
    local kept = {}
    local earliest
    local sawBaseline = false
    for index = 1, #events do
        local event = events[index]
        if ResourceEventFor(event, definition.key) then
            if type(event.at) == "number" and (not earliest or event.at < earliest) then
                earliest = event.at
            end
            if event.guid then
                RememberObserver(state, event.guid)
            end
            if SyntheticWarbandEvent(event, shared, stripEchoes) then
                -- Drop the character-switch echo. Leave every other resource alone.
            else
                event.meta = event.meta or {}
                event.meta.ownership = "warband"
                if event.meta.classification == BASELINE and (not shared or event.meta.balanceAfter == shared) then
                    sawBaseline = true
                end
                kept[#kept + 1] = event
            end
        else
            kept[#kept + 1] = event
        end
    end
    db.events = kept
    for guid in pairs(state.characters or {}) do
        RememberObserver(state, guid)
    end
    local now = WBF.Time.Now()
    if type(shared) == "number" then
        local priorOpening = state.openingBalance
        WriteCanonical(state, definition, shared, earliest or now)
        state.previousBalance = shared
        if stripEchoes then
            state.openingBalance = shared
        elseif priorOpening ~= nil then
            state.openingBalance = priorOpening
        end
        if not sawBaseline and shared > 0 then
            Record(definition, 0, shared, BASELINE, nil, state.observedWhilePlayingCharacter, nil, nil, earliest or now)
        end
    else
        state.characters = {}
        state.ownership = "warband"
        state.currencyID = definition.id
    end
    state.warbandLedger = WARBAND_LEDGER
end

function WBF.Resources.CommitObservation(key, quantity, guid, sourced)
    return CommitObservation(key, quantity, guid, sourced)
end

function WBF.Resources.MigrateOwnedBalances()
    if not WBF.Database.IsReady() then
        return
    end
    for index = 1, #order do
        local definition = registry[order[index]]
        if definition and definition.trackingType == "currency" then
            local wide = ReadAccountWide(definition, nil)
            if wide == true then
                definition.classification = "ACCOUNT_WIDE_CURRENCY"
                definition.ownership = "warband"
            end
            if IsWarbandCurrency(definition) then
                MigrateWarband(definition)
            end
        end
    end
end

-- A balance sample is not a transaction until it is a stable, ready reading.
-- Item counts that drop the Warband bank, currency reads taken while entering
-- the world, and any other unready sample stay pending. A later read that
-- returns to the accepted balance rejects the sample. A repeated ready read
-- of the new balance accepts it. Authoritative currency events, which carry
-- a quantityChange that matches the new total, are accepted immediately so a
-- real spend followed quickly by a real gain is kept.
local SETTLE_SECONDS = 2.5
local CONFIRM_SECONDS = 1.25
local settleUntil = 0
local pendingObserve = {}

local function InSettle()
    return WBF.Time.Now() < settleUntil
end

local function CharacterLabel(guid)
    if not guid then
        return "unknown"
    end
    if WBF.Characters and WBF.Characters.Get then
        local stored = WBF.Characters.Get(guid)
        if stored and stored.name and stored.name ~= "" then
            return stored.name
        end
    end
    return guid
end

local function ResourceLog(definition, previous, candidate, eventName, guid, status, reason, rejected)
    if not WBF.Debug or not WBF.Debug.Enabled or not WBF.Debug.Enabled() then
        return
    end
    if not WBF.Debug.Log then
        return
    end
    local function num(value)
        if value == nil then
            return "nil"
        end
        return tostring(value)
    end
    local ownership = "resource"
    if definition then
        if IsWarbandCurrency(definition) then
            ownership = "warband"
        elseif definition.ownership and definition.ownership ~= "" then
            ownership = definition.ownership
        else
            ownership = definition.trackingType or ownership
        end
    end
    local lines = {
        "[WarbandFYI Resource]",
        definition and DisplayName(definition) or "?",
        "id=" .. tostring(definition and definition.id or "?"),
        "ownership=" .. ownership,
        "previous=" .. num(previous),
        "candidate=" .. num(candidate),
        "event=" .. tostring(eventName or "?"),
        "character=" .. CharacterLabel(guid),
        "status=" .. tostring(status),
    }
    if reason and reason ~= "" then
        lines[#lines + 1] = "reason=" .. reason
    end
    if rejected ~= nil then
        lines[#lines + 1] = "rejectedCandidate=" .. num(rejected)
    end
    WBF.Debug.Log(table.concat(lines, "\n"))
end

local function CountRecords(values)
    if type(values) ~= "table" then
        return nil
    end
    if #values > 0 then
        return #values
    end
    local count = 0
    for _ in pairs(values) do
        count = count + 1
    end
    return count
end

local function PurchasedAccountTabs()
    if not C_Bank or not Enum or not Enum.BankType or Enum.BankType.Account == nil then
        return nil
    end
    if C_Bank.FetchPurchasedBankTabIDs then
        local ids = WBF.Format.SafeCall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Account)
        if not WBF.Format.IsSecret(ids) then
            local count = CountRecords(ids)
            if count ~= nil then
                return count
            end
        end
    end
    if C_Bank.FetchPurchasedBankTabData then
        local tabs = WBF.Format.SafeCall(C_Bank.FetchPurchasedBankTabData, Enum.BankType.Account)
        if WBF.Format.IsSecret(tabs) then
            return nil
        end
        return CountRecords(tabs)
    end
    return nil
end

local function AccountBankReady()
    local expected = PurchasedAccountTabs()
    if expected == nil then
        return nil
    end
    if expected <= 0 then
        return true
    end
    if not C_Container or not C_Container.GetContainerNumSlots or not Enum or not Enum.BagIndex then
        return nil
    end
    local loaded = 0
    local known = 0
    for index = 1, 12 do
        local bag = Enum.BagIndex["AccountBankTab_" .. index]
        if bag then
            known = known + 1
            local slots = WBF.Format.AsNumber(WBF.Format.SafeCall(C_Container.GetContainerNumSlots, bag))
            if slots and slots > 0 then
                loaded = loaded + 1
            end
        end
    end
    if known <= 0 then
        return nil
    end
    return loaded >= expected
end

local function ScheduleConfirm(key)
    local held = pendingObserve[key]
    if not held or not C_Timer or not C_Timer.After then
        return
    end
    held.token = (held.token or 0) + 1
    local token = held.token
    C_Timer.After(CONFIRM_SECONDS, function()
        local current = pendingObserve[key]
        if not current or current.token ~= token then
            return
        end
        if WBF.Resources.ConfirmPending then
            WBF.Resources.ConfirmPending(key)
        end
    end)
end

local function HoldObservation(key, candidate, guid, eventName, reason, kind, account)
    local held = pendingObserve[key]
    if held and held.balance == candidate and held.reason == reason then
        held.account = account
        ScheduleConfirm(key)
        return
    end
    pendingObserve[key] = {
        balance = candidate,
        guid = guid,
        event = eventName,
        reason = reason,
        kind = kind,
        account = account,
        at = WBF.Time.Now(),
    }
    ScheduleConfirm(key)
end

local function ItemTotal(state, guid, personal, account)
    local total = account or 0
    for other, amount in pairs(state.characters) do
        if other ~= guid and type(amount) == "number" then
            total = total + amount
        end
    end
    return total + (personal or 0)
end

local function AcceptedItemTotal(state, definition)
    if type(state.acceptedBalance) == "number" then
        return state.acceptedBalance
    end
    if state.account ~= nil or HasCharacters(state) then
        local total = TotalOf(state, definition)
        state.acceptedBalance = total
        return total
    end
    return nil
end

local function WriteItemParts(state, definition, guid, personal, account, total)
    state.account = account
    state.characters[guid] = personal
    state.acceptedBalance = total
    state.lastObservedAt = WBF.Time.Now()
    RememberObserver(state, guid)
    TouchScan(state, guid, "character_scan")
    PersistDefinition(definition)
end

local function CommitItem(definition, state, guid, personal, account, total, accepted)
    local first = accepted == nil
    local discovered = (not first) and state.characters[guid] == nil
    WriteItemParts(state, definition, guid, personal, account, total)
    if first then
        if total > 0 then
            Record(definition, 0, total, BASELINE, nil, guid)
            NoteFreshFind(guid, true, total)
        end
        return
    end
    local delta = total - accepted
    if delta == 0 then
        return
    end
    if discovered then
        Record(definition, delta, total, SYNC, accepted, guid)
        NoteFreshFind(guid, true, personal)
        return
    end
    local classification = delta > 0 and GAIN_OBSERVED or LOSS_OBSERVED
    Record(definition, delta, total, classification, accepted, guid)
end

function WBF.Resources.ObserveItem(key, personal, account, guid, eventName, bankReady)
    local definition = registry[key]
    if not definition or not guid then
        return
    end
    personal = WBF.Format.AsNumber(personal)
    account = WBF.Format.AsNumber(account)
    if personal == nil or account == nil then
        ResourceLog(definition, nil, nil, eventName, guid, "REJECTED_UNREADY", "missing_count")
        return
    end
    if account < 0 then
        account = 0
    end
    local state = StateFor(key)
    RememberObserver(state, guid)
    local total = ItemTotal(state, guid, personal, account)
    local accepted = AcceptedItemTotal(state, definition)
    local held = pendingObserve[key]
    local reason
    local accountDrop = type(state.account) == "number" and account < state.account
    if InSettle() and (accepted == nil or total ~= accepted) then
        reason = "entering_world"
    elseif accountDrop and bankReady ~= true then
        reason = bankReady == false and "account_bank_unready" or "account_bank_incomplete"
    elseif accepted == nil and bankReady ~= true then
        reason = "account_bank_unready"
    elseif accountDrop and bankReady == true and accepted ~= nil and total < accepted then
        local confirming = held and held.reason == "account_bank_drop" and held.balance == total and held.account == account
        if not confirming and C_Timer and C_Timer.After then
            reason = "account_bank_drop"
        end
    end
    if reason then
        if accepted ~= nil and total == accepted then
            if held then
                ResourceLog(definition, accepted, total, eventName, guid, "REJECTED_TRANSIENT", held.reason, held.balance)
                pendingObserve[key] = nil
            end
            -- The total matches, but this split is not trustworthy. Keep the
            -- last accepted bag and bank counts.
            state.lastObservedAt = WBF.Time.Now()
            RememberObserver(state, guid)
            return
        end
        if reason == "account_bank_missing" and held and held.balance == total and held.reason == reason and bankReady ~= false and not InSettle() then
            pendingObserve[key] = nil
            CommitItem(definition, state, guid, personal, account, total, accepted)
            ResourceLog(definition, accepted, total, eventName, guid, "ACCEPTED", "confirmed")
            return
        end
        if not (held and held.balance == total and held.reason == reason) then
            ResourceLog(definition, accepted, total, eventName, guid, "PENDING_VALIDATION", reason)
        end
        HoldObservation(key, total, guid, eventName, reason, "item", account)
        return
    end
    if held then
        if accepted ~= nil and total == accepted then
            ResourceLog(definition, accepted, total, eventName, guid, "REJECTED_TRANSIENT", held.reason, held.balance)
            pendingObserve[key] = nil
            WriteItemParts(state, definition, guid, personal, account, total)
            return
        end
        if total ~= held.balance then
            ResourceLog(definition, accepted, total, eventName, guid, "REJECTED_TRANSIENT", held.reason, held.balance)
        end
        pendingObserve[key] = nil
    end
    if accepted ~= nil and total == accepted then
        WriteItemParts(state, definition, guid, personal, account, total)
        return
    end
    CommitItem(definition, state, guid, personal, account, total, accepted)
    ResourceLog(definition, accepted, total, eventName, guid, "ACCEPTED")
end

local function NoteItem(definition, guid)
    local personal, account, icon = ReadItemParts(definition.id)
    if not personal then
        ResourceLog(definition, nil, nil, "BAG_UPDATE_DELAYED", guid, "REJECTED_UNREADY", "item_not_cached")
        return
    end
    RememberIcon(definition, icon)
    if C_Item and C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, definition.id)
        if ok then
            RememberName(definition, name)
        end
    end
    WBF.Resources.ObserveItem(definition.key, personal, account, guid, "BAG_UPDATE_DELAYED", AccountBankReady())
end

local function KeepSystemReading(definition, quantity, guid)
    quantity = WBF.Format.AsNumber(quantity)
    if not definition or not guid or quantity == nil then
        return
    end
    local state = StateFor(definition.key)
    state.characters[guid] = quantity
    if IsWarbandCurrency(definition) then
        state.currentBalance = quantity
        state.accountWide = quantity
    end
    state.acceptedBalance = IsWarbandCurrency(definition) and quantity or TotalOf(state, definition)
    state.lastObservedAt = WBF.Time.Now()
    TouchScan(state, guid, "system_currency")
end

local function NoteCurrency(definition, quantity, change, gainSource, destroyReason, guidOverride)
    local guid = (type(guidOverride) == "string" and guidOverride ~= "") and guidOverride or CurrentGUID()
    if not guid or not definition or definition.suppressed then
        return
    end
    local qty, icon, name, info = ReadCurrency(definition.id)
    ApplyCurrencyFlags(definition, info)
    if definition.suppressed then
        return
    end
    if WBF.ResourceClassification and WBF.ResourceClassification.HidesFromPlayer(definition) then
        KeepSystemReading(definition, WBF.Format.AsNumber(quantity) or qty, guid)
        return
    end
    RememberIcon(definition, icon)
    RememberName(definition, name)
    quantity = WBF.Format.AsNumber(quantity) or qty
    change = WBF.Format.AsNumber(change)
    if quantity == nil and change == nil then
        return
    end
    local state = StateFor(definition.key)
    local eventName = (gainSource ~= nil or destroyReason ~= nil) and "CURRENCY_DISPLAY_UPDATE" or "CURRENCY_SYNC"
    if IsWarbandCurrency(definition) then
        -- Quantity nil means the API did not answer. It is not a balance of zero.
        if quantity == nil then
            ResourceLog(definition, CanonicalBalance(state), nil, eventName, guid, "REJECTED_UNREADY", "missing_quantity")
            return
        end
        local sourced = gainSource ~= nil or destroyReason ~= nil
        local previousWide = CanonicalBalance(state)
        local authoritative = sourced and previousWide ~= nil and change ~= nil and quantity == previousWide + change
        local held = pendingObserve[definition.key]
        if previousWide ~= nil and quantity == previousWide then
            if held then
                ResourceLog(definition, previousWide, quantity, eventName, guid, "REJECTED_TRANSIENT", held.reason, held.balance)
                pendingObserve[definition.key] = nil
            end
            CommitObservation(definition.key, quantity, guid, false)
            return
        end
        local unsettled = InSettle() and (previousWide == nil or quantity ~= previousWide)
        if unsettled or (previousWide ~= nil and not authoritative) then
            if (not unsettled) and held and held.balance == quantity then
                pendingObserve[definition.key] = nil
                local delta = CommitObservation(definition.key, quantity, guid, sourced)
                ResourceLog(definition, previousWide, quantity, eventName, guid, "ACCEPTED", "confirmed")
                if previousWide == nil and quantity > 0 then
                    NoteFreshFind(guid, true, quantity)
                end
                if delta and delta ~= 0 then
                    return
                end
                return
            end
            local reason = unsettled and "entering_world" or "unconfirmed"
            ResourceLog(definition, previousWide, quantity, eventName, guid, "PENDING_VALIDATION", reason)
            HoldObservation(definition.key, quantity, guid, eventName, reason, "currency")
            return
        end
        if held and held.balance ~= quantity then
            ResourceLog(definition, previousWide, quantity, eventName, guid, "REJECTED_TRANSIENT", held.reason, held.balance)
        end
        pendingObserve[definition.key] = nil
        local delta = CommitObservation(definition.key, quantity, guid, sourced)
        ResourceLog(definition, previousWide, quantity, eventName, guid, "ACCEPTED", authoritative and "authoritative" or nil)
        if previousWide == nil and quantity > 0 then
            NoteFreshFind(guid, true, quantity)
        end
        if delta and delta ~= 0 then
            return
        end
        return
    end
    if quantity == nil then
        ResourceLog(definition, nil, nil, eventName, guid, "REJECTED_UNREADY", "missing_quantity")
        return
    end
    local previous = state.characters[guid]
    if previous ~= nil and quantity == previous then
        local held = pendingObserve[definition.key]
        if held and held.guid == guid then
            ResourceLog(definition, previous, quantity, eventName, guid, "REJECTED_TRANSIENT", held.reason, held.balance)
            pendingObserve[definition.key] = nil
        end
        TouchScan(state, guid, "character_scan")
        state.acceptedBalance = TotalOf(state, definition)
        state.lastObservedAt = WBF.Time.Now()
        return
    end
    if InSettle() and (previous == nil or quantity ~= previous) then
        ResourceLog(definition, previous, quantity, eventName, guid, "PENDING_VALIDATION", "entering_world")
        HoldObservation(definition.key, quantity, guid, eventName, "entering_world", "currency")
        return
    end
    if previous ~= nil and gainSource == nil and destroyReason == nil then
        local held = pendingObserve[definition.key]
        if held and held.balance == quantity and held.guid == guid then
            pendingObserve[definition.key] = nil
            ResourceLog(definition, previous, quantity, eventName, guid, "ACCEPTED", "confirmed")
        else
            ResourceLog(definition, previous, quantity, eventName, guid, "PENDING_VALIDATION", "unconfirmed")
            HoldObservation(definition.key, quantity, guid, eventName, "unconfirmed", "currency")
            return
        end
    end
    if previous == nil then
        if quantity == nil then
            return
        end
        local wasEmpty = state.accountWide == nil and state.account == nil and not HasCharacters(state)
        local previousTotal = TotalOf(state, definition)
        state.characters[guid] = quantity
        TouchScan(state, guid, "character_scan")
        local total = TotalOf(state, definition)
        state.acceptedBalance = total
        state.lastObservedAt = WBF.Time.Now()
        if wasEmpty then
            if total > 0 then
                Record(definition, 0, total, BASELINE, nil, guid)
                NoteFreshFind(guid, true, quantity)
            end
        elseif quantity ~= 0 then
            Record(definition, quantity, total, SYNC, previousTotal, guid)
            NoteFreshFind(guid, true, quantity)
        end
        return
    end
    -- Two stored observations decide the delta. A lone quantityChange is not one.
    if quantity ~= nil and previous ~= nil then
        change = quantity - previous
    elseif change == nil and quantity ~= nil then
        change = quantity - previous
    end
    if not change or change == 0 then
        if quantity ~= nil then
            state.characters[guid] = quantity
            TouchScan(state, guid, "character_scan")
        end
        return
    end
    local previousTotal = TotalOf(state, definition)
    state.characters[guid] = quantity or (previous + change)
    TouchScan(state, guid, "character_scan")
    local total = TotalOf(state, definition)
    state.acceptedBalance = total
    state.lastObservedAt = WBF.Time.Now()
    local sourced = gainSource ~= nil or destroyReason ~= nil
    local classification
    if IsTransfer(gainSource, destroyReason) then
        classification = TRANSFER
    elseif not sourced then
        classification = change > 0 and GAIN_OBSERVED or LOSS_OBSERVED
    elseif change > 0 then
        classification = GAIN
    else
        classification = SPEND
    end
    Record(definition, change, total, classification, previousTotal, guid)
end

local function ScanItems()
    if not WBF.Database.IsReady() then
        return
    end
    local guid = CurrentGUID()
    if not guid then
        return
    end
    RefreshActive()
    for index = 1, #order do
        local definition = registry[order[index]]
        if definition.trackingType == "item" then
            NoteItem(definition, guid)
        end
    end
end

local function ScheduleItemScan()
    if InCombatLockdown and InCombatLockdown() then
        itemScanPending = true
        return
    end
    if not C_Timer or not C_Timer.After then
        ScanItems()
        return
    end
    itemScanGeneration = itemScanGeneration + 1
    local generation = itemScanGeneration
    itemScanPending = true
    C_Timer.After(0.75, function()
        if generation ~= itemScanGeneration then
            return
        end
        itemScanPending = false
        if InCombatLockdown and InCombatLockdown() then
            itemScanPending = true
            return
        end
        ScanItems()
    end)
end

local function SyncCurrencies()
    if not WBF.Database.IsReady() then
        return
    end
    RefreshActive()
    for index = 1, #order do
        local definition = registry[order[index]]
        if definition.trackingType == "currency" then
            local quantity, _, _, info = ReadCurrency(definition.id)
            if not IsWarbandCurrency(definition) then
                ApplyCurrencyFlags(definition, info)
            end
            if quantity == nil then
                -- Unavailable. Leave the last real balance where it is.
            elseif IsWarbandCurrency(definition) then
                NoteCurrency(definition, quantity, nil, nil, nil)
            else
                local guid = CurrentGUID()
                local state = guid and StateFor(definition.key) or nil
                local previous = state and state.characters[guid] or nil
                if previous == nil or previous ~= quantity then
                    local change = previous and (quantity - previous) or nil
                    NoteCurrency(definition, quantity, change, nil, nil)
                end
            end
        end
    end
end

local function FindCurrency(currencyID)
    currencyID = WBF.Format.AsNumber(currencyID)
    if not currencyID then
        return nil
    end
    return byIdentity["currency:" .. currencyID]
end

local SPIKE_WINDOW = 120

local function EventPrevious(event)
    if type(event.previous) == "number" then
        return event.previous
    end
    local meta = event.meta or {}
    if type(meta.balanceAfter) == "number" and type(event.delta) == "number" then
        if meta.classification == BASELINE then
            return meta.balanceAfter
        end
        return meta.balanceAfter - event.delta
    end
    return nil
end

-- A plunge that bounces back to the same balance. One occurrence can be a
-- real spend and a real refund. The same low balance doing it twice is the
-- account-bank cache dropping out and coming back.
local function PlungeGap(earlier, later)
    local loss = earlier.delta or 0
    local gain = later.delta or 0
    if loss >= 0 or gain ~= -loss then
        return nil
    end
    local origin = EventPrevious(earlier)
    local meta = earlier.meta or {}
    local laterMeta = later.meta or {}
    local dip = meta.balanceAfter
    local back = laterMeta.balanceAfter
    if origin == nil or dip == nil or back == nil then
        return nil
    end
    if back ~= origin or dip ~= origin + loss or dip >= origin then
        return nil
    end
    local classA = meta.classification
    local classB = laterMeta.classification
    local movement = {
        [GAIN] = true,
        [GAIN_OBSERVED] = true,
        [SPEND] = true,
        [LOSS_OBSERVED] = true,
    }
    if not movement[classA] or not movement[classB] then
        return nil
    end
    local gap = (later.at or 0) - (earlier.at or 0)
    if gap < 0 or gap > SPIKE_WINDOW then
        return nil
    end
    return gap, dip
end

local function WithoutTransientPairs(list)
    local pairs = {}
    local counts = {}
    for index = 1, #list - 1 do
        local gap, dip = PlungeGap(list[index], list[index + 1])
        if gap and dip ~= nil then
            pairs[#pairs + 1] = { index, index + 1, dip }
            counts[dip] = (counts[dip] or 0) + 1
        end
    end
    if #pairs == 0 then
        return list
    end
    local drop = {}
    local removed = false
    for index = 1, #pairs do
        local pair = pairs[index]
        if counts[pair[3]] >= 2 then
            drop[pair[1]] = true
            drop[pair[2]] = true
            removed = true
        end
    end
    if not removed then
        return list
    end
    local kept = {}
    for index = 1, #list do
        if not drop[index] then
            kept[#kept + 1] = list[index]
        end
    end
    return kept
end

local function ResourceEvents(events, key)
    local list = {}
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.Resource and meta.resourceKey == key then
            list[#list + 1] = event
        end
    end
    table.sort(list, function(a, b)
        if a.at == b.at then
            return (a.id or 0) < (b.id or 0)
        end
        return (a.at or 0) < (b.at or 0)
    end)
    return WithoutTransientPairs(list)
end

local function InWindow(event, startAt, endAt)
    if not event.at then
        return false
    end
    if startAt and event.at < startAt then
        return false
    end
    if endAt and event.at > endAt then
        return false
    end
    return true
end

local function Summarize(records, startAt, endAt, guid, instanceID)
    local earned, spent = 0, 0
    local syncNet = 0
    local transferNet = 0
    local transferIn, transferOut = 0, 0
    local opening, current
    local lastBefore
    local days = {}
    local dayOrder = {}
    local characters = {}
    local sources = {}
    local activity = {}
    local baselines = {}
    for index = 1, #records do
        local event = records[index]
        local meta = event.meta or {}
        local forCharacter = not guid or event.guid == guid
        local forInstance = not instanceID or meta.eventInstance == instanceID
        if forInstance and event.at and startAt and event.at < startAt then
            lastBefore = event
        end
        if forInstance and InWindow(event, startAt, endAt) and meta.balanceAfter ~= nil then
            current = meta.balanceAfter
        end
        local included = forInstance and forCharacter and InWindow(event, startAt, endAt)
        if not guid and forInstance and event.at and startAt and event.at < startAt then
            lastBefore = event
        end
        if included then
            local classification = meta.classification
            local delta = event.delta or 0
            if CountsAsEarned(classification) then
                earned = earned + delta
            elseif CountsAsSpent(classification) then
                spent = spent + math.abs(delta)
            elseif classification == SYNC then
                -- Already held when first counted. It is not income or spending.
                syncNet = syncNet + delta
            elseif classification == TRANSFER then
                transferNet = transferNet + delta
                if delta > 0 then
                    transferIn = transferIn + delta
                else
                    transferOut = transferOut + math.abs(delta)
                end
            end
            if meta.balanceAfter ~= nil then
                current = meta.balanceAfter
            end
            if classification == BASELINE then
                baselines[#baselines + 1] = event
            else
                activity[#activity + 1] = event
            end
            local warbandEvent = meta.ownership == "warband"
            if CountsAsEarned(classification) or CountsAsSpent(classification) then
                local day = WBF.Time.StartOfDay(event.at)
                local row = days[day]
                if not row then
                    row = { at = day, earned = 0, spent = 0 }
                    days[day] = row
                    dayOrder[#dayOrder + 1] = day
                end
                if CountsAsEarned(classification) then
                    row.earned = row.earned + delta
                else
                    row.spent = row.spent + math.abs(delta)
                end
                if not warbandEvent and event.guid and WBF.Characters.IsDiscovered(event.guid) then
                    local character = characters[event.guid]
                    if not character then
                        local stored = WBF.Characters.Get(event.guid)
                        character = {
                            guid = event.guid,
                            name = stored and stored.name or "Character",
                            classFile = stored and stored.classFile or nil,
                            earned = 0,
                            spent = 0,
                            transferred = 0,
                        }
                        characters[event.guid] = character
                    end
                    if CountsAsEarned(classification) then
                        character.earned = character.earned + delta
                    else
                        character.spent = character.spent + math.abs(delta)
                    end
                end
                if meta.sourceName and meta.sourceName ~= "" and CountsAsEarned(classification) then
                    sources[meta.sourceName] = (sources[meta.sourceName] or 0) + delta
                end
            elseif not warbandEvent and classification == TRANSFER and event.guid and WBF.Characters.IsDiscovered(event.guid) then
                local character = characters[event.guid]
                if not character then
                    local stored = WBF.Characters.Get(event.guid)
                    character = {
                        guid = event.guid,
                        name = stored and stored.name or "Character",
                        classFile = stored and stored.classFile or nil,
                        earned = 0,
                        spent = 0,
                        transferred = 0,
                    }
                    characters[event.guid] = character
                end
                character.transferred = character.transferred + delta
            end
        end
    end
    if lastBefore and lastBefore.meta then
        opening = lastBefore.meta.balanceAfter
    end
    if opening == nil then
        for index = 1, #records do
            local event = records[index]
            local meta = event.meta or {}
            if (not instanceID or meta.eventInstance == instanceID) and InWindow(event, startAt, endAt) then
                if meta.classification == BASELINE then
                    opening = meta.balanceAfter
                elseif meta.balanceAfter ~= nil and event.delta ~= nil then
                    local warbandDelta = meta.warbandDelta
                    if warbandDelta == nil then
                        if meta.classification == TRANSFER or meta.classification == BASELINE then
                            warbandDelta = 0
                        else
                            warbandDelta = event.delta
                        end
                    end
                    opening = meta.balanceAfter - warbandDelta
                end
                break
            end
        end
    end
    if current == nil then
        current = opening
    end
    local dayList = {}
    for index = 1, #dayOrder do
        dayList[#dayList + 1] = days[dayOrder[index]]
    end
    table.sort(dayList, function(a, b)
        return a.at > b.at
    end)
    local characterList = {}
    for _, character in pairs(characters) do
        characterList[#characterList + 1] = character
    end
    table.sort(characterList, function(a, b)
        if a.earned == b.earned then
            return (a.name or "") < (b.name or "")
        end
        return a.earned > b.earned
    end)
    local sourceList = {}
    for name, amount in pairs(sources) do
        sourceList[#sourceList + 1] = { name = name, earned = amount }
    end
    table.sort(sourceList, function(a, b)
        return a.earned > b.earned
    end)
    table.sort(activity, function(a, b)
        if a.at == b.at then
            return (a.id or 0) > (b.id or 0)
        end
        return (a.at or 0) > (b.at or 0)
    end)
    if opening ~= nil and current ~= nil then
        local expected = opening + syncNet + earned - spent
        if expected ~= current and WBF.Debug and WBF.Debug.Enabled and WBF.Debug.Enabled() and WBF.Debug.Log then
            WBF.Debug.Log(string.format(
                "[WarbandFYI Resource]\nreconcile mismatch\nopening=%s sync=%s gained=%s spent=%s transfer=%s expected=%s current=%s",
                tostring(opening),
                tostring(syncNet),
                tostring(earned),
                tostring(spent),
                tostring(transferNet),
                tostring(expected),
                tostring(current)
            ))
            for index = 1, #records do
                local event = records[index]
                if InWindow(event, startAt, endAt) then
                    local meta = event.meta or {}
                    WBF.Debug.Log(string.format(
                        "  at=%s class=%s delta=%s previous=%s balance=%s",
                        tostring(event.at),
                        tostring(meta.classification),
                        tostring(event.delta),
                        tostring(event.previous),
                        tostring(meta.balanceAfter)
                    ))
                end
            end
        end
        -- Stock first counted during the period was already held, so it
        -- belongs in the opening figure. Gains and spends then meet the close.
        opening = opening + syncNet
    end
    return {
        opening = opening,
        earned = earned,
        spent = spent,
        net = earned - spent,
        current = current,
        transferred = math.max(transferIn, transferOut),
        days = dayList,
        characters = characterList,
        sources = sourceList,
        activity = activity,
        baselines = baselines,
    }
end

local function DominantInstance(records, startAt, endAt)
    local counts = {}
    local best, bestAmount
    for index = 1, #records do
        local event = records[index]
        local meta = event.meta or {}
        if meta.eventInstance and InWindow(event, startAt, endAt) and CountsAsEarned(meta.classification) then
            counts[meta.eventInstance] = (counts[meta.eventInstance] or 0) + (event.delta or 0)
            if not bestAmount or counts[meta.eventInstance] > bestAmount then
                bestAmount = counts[meta.eventInstance]
                best = meta.eventInstance
            end
        end
    end
    return best
end

local function ObservedNames(state)
    local names = {}
    local seen = {}
    if type(state) ~= "table" or type(state.observed) ~= "table" then
        return names
    end
    for guid in pairs(state.observed) do
        if not seen[guid] then
            seen[guid] = true
            local name = state.names and state.names[guid] or nil
            local stored = WBF.Characters.Get and WBF.Characters.Get(guid) or nil
            if stored and stored.name and stored.name ~= "" then
                name = stored.name
            end
            if name and name ~= "" then
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    return names
end

function WBF.Resources.Report(key, startAt, endAt, guid)
    local definition = registry[key]
    if not definition or not WBF.Database.IsReady() then
        return nil
    end
    local records = ResourceEvents(WBF.Database.Get().events or {}, key)
    local period = Summarize(records, startAt, endAt, guid, nil)
    local instance = active[definition.eventKey]
    local instanceID = instance and instance.id or DominantInstance(records, startAt, endAt)
    local eventSummary
    local eventName
    if instanceID then
        eventSummary = Summarize(records, nil, nil, guid, instanceID)
        eventName = instance and instance.name or nil
        if not eventName then
            for index = 1, #records do
                local meta = records[index].meta or {}
                if meta.eventInstance == instanceID and meta.eventName then
                    eventName = meta.eventName
                    break
                end
            end
        end
    end
    local state = Store().balances[key]
    return {
        key = key,
        name = DisplayName(definition),
        short = ShortName(definition),
        texture = definition.iconFile,
        trackingType = definition.trackingType,
        period = period,
        event = eventSummary,
        eventName = eventName,
        eventID = instanceID,
        milestones = definition.milestones,
        accountWide = IsWarbandCurrency(definition),
        currentBalance = state and CanonicalBalance(state) or period.current,
        observed = state and ObservedNames(state) or {},
    }
end

local function Person(guid, state, observerName)
    local stored = guid and WBF.Characters.Get and WBF.Characters.Get(guid) or nil
    local name = stored and stored.name or nil
    if not name or name == "" then
        name = observerName
    end
    if (not name or name == "") and state and state.names and guid then
        name = state.names[guid]
    end
    if not name or name == "" then
        return nil
    end
    return {
        guid = guid,
        name = name,
        classFile = stored and stored.classFile or nil,
    }
end

local function TypeBadge(definition)
    if IsWarbandCurrency(definition) then
        return "Warband Currency"
    end
    if definition.ownership == "character" and definition.trackingType == "currency" then
        return "Character Currency"
    end
    local era = WBF.ResourceMeta and WBF.ResourceMeta.For and WBF.ResourceMeta.For(definition) or nil
    if definition.eventKey or definition.group == "events" or (era and era.kind == "event") then
        return "Event Currency"
    end
    if era and era.kind == "expansion" then
        return "Expansion Currency"
    end
    if definition.trackingType == "item" then
        return "Item"
    end
    return "Resource"
end

local function SourceLine(definition, badge)
    if definition.eventKey then
        local instance = active[definition.eventKey]
        local name = instance and (instance.name or instance.sourceName) or nil
        if not name or name == "" then
            for index = 1, #EVENTS do
                if EVENTS[index].key == definition.eventKey then
                    name = EVENTS[index].name
                    break
                end
            end
        end
        if name and name ~= "" then
            return "Source: " .. name
        end
    end
    local era = WBF.ResourceMeta and WBF.ResourceMeta.For and WBF.ResourceMeta.For(definition) or nil
    if era and era.kind == "expansion" and era.label and era.id ~= "unknown" and era.id ~= "cross_expansion" then
        return "Expansion: " .. era.label
    end
    if IsWarbandCurrency(definition) and badge ~= "Warband Currency" then
        return "Warband Currency"
    end
    return nil
end

local function RowNote(event)
    local meta = event.meta or {}
    local classification = meta.classification
    -- sourceLabel is set only when a transfer or another caller recorded a
    -- real counterpart. Event membership is context, not a cause.
    if classification == TRANSFER then
        if meta.counterpart and meta.counterpart ~= "" then
            if (event.delta or 0) < 0 then
                return "Transferred to " .. meta.counterpart
            end
            return "Transferred from " .. meta.counterpart
        end
        return "Transferred"
    end
    if meta.sourceLabel and meta.sourceLabel ~= "" then
        return meta.sourceLabel
    end
    if meta.eventName and meta.eventName ~= "" then
        return meta.eventName
    end
    if meta.sourceName and meta.sourceName ~= "" then
        return meta.sourceName
    end
    if classification == BASELINE then
        return "Tracking started"
    end
    return ""
end

local function IsShownActivity(event)
    if WBF.ResourceBehaviour and WBF.ResourceBehaviour.HidesActivity(event) then
        return false
    end
    local meta = event.meta or {}
    local classification = meta.classification
    if classification == SYNC then
        return false
    end
    if classification == BASELINE then
        return true
    end
    if classification == GAIN or classification == GAIN_OBSERVED or classification == SPEND or classification == LOSS_OBSERVED or classification == TRANSFER then
        return (event.delta or 0) ~= 0
    end
    return false
end

-- Observed balance over the selected window. Points are the balance after each
-- real observation. A carried point extends the last known balance to the
-- window edge so the line can be drawn without inventing earnings.
local function BalanceSeries(records, startAt, endAt, state)
    local ordered = {}
    for index = 1, #records do
        local event = records[index]
        local meta = event.meta or {}
        if event.at and meta.balanceAfter ~= nil then
            ordered[#ordered + 1] = event
        end
    end
    table.sort(ordered, function(a, b)
        if a.at == b.at then
            return (a.id or 0) < (b.id or 0)
        end
        return a.at < b.at
    end)
    local points = {}
    local lastBefore
    for index = 1, #ordered do
        local event = ordered[index]
        local meta = event.meta or {}
        if startAt and event.at < startAt then
            lastBefore = event
        elseif not endAt or event.at <= endAt then
            local previous = points[#points]
            local balance = meta.balanceAfter
            if meta.classification == SYNC then
                if previous and previous.opening and not previous.moved then
                    previous.balance = balance
                elseif not previous or previous.balance ~= balance then
                    local person = Person(event.guid, state, meta.observer)
                    points[#points + 1] = {
                        at = event.at,
                        balance = balance,
                        delta = 0,
                        held = true,
                        name = person and person.name or nil,
                        classFile = person and person.classFile or nil,
                        note = RowNote(event),
                    }
                end
            elseif not previous or previous.balance ~= balance then
                local opening = meta.classification == BASELINE
                local person = Person(event.guid, state, meta.observer)
                points[#points + 1] = {
                    at = event.at,
                    balance = balance,
                    delta = opening and 0 or (event.delta or 0),
                    opening = opening,
                    moved = not opening,
                    name = person and person.name or nil,
                    classFile = person and person.classFile or nil,
                    note = RowNote(event),
                }
                if previous then
                    previous.moved = true
                end
            end
        end
    end
    if lastBefore and startAt then
        local balance = lastBefore.meta and lastBefore.meta.balanceAfter
        local first = points[1]
        if balance ~= nil and (not first or first.at > startAt) then
            table.insert(points, 1, {
                at = startAt,
                balance = balance,
                delta = 0,
                carried = true,
            })
        end
    end
    local tail = points[#points]
    if tail and endAt and tail.at < endAt then
        points[#points + 1] = {
            at = endAt,
            balance = tail.balance,
            delta = 0,
            carried = true,
        }
    end
    return points
end

function WBF.Resources.FoldExpired(event)
    if type(event) ~= "table" or event.sample or event.eventType ~= WBF.EventType.Resource then
        return
    end
    local meta = event.meta or {}
    if type(meta.resourceKey) ~= "string" or not WBF.Database.IsReady() then
        return
    end
    local state = StateFor(meta.resourceKey)
    local life = state.lifetime
    if type(life) ~= "table" then
        life = {}
        state.lifetime = life
    end
    if type(event.at) == "number" and (type(life.firstAt) ~= "number" or event.at < life.firstAt) then
        life.firstAt = event.at
    end
    if type(meta.balanceAfter) == "number" and (type(life.highest) ~= "number" or meta.balanceAfter > life.highest) then
        life.highest = meta.balanceAfter
    end
    if CountsAsEarned(meta.classification) then
        life.gained = (life.gained or 0) + (event.delta or 0)
        life.moved = true
    elseif CountsAsSpent(meta.classification) then
        life.spent = (life.spent or 0) + math.abs(event.delta or 0)
        life.moved = true
    end
end

local function LifetimeStats(records, state, current)
    local life = state and state.lifetime
    local firstAt = state and state.firstObservedAt or nil
    if type(life) == "table" and type(life.firstAt) == "number" and (not firstAt or life.firstAt < firstAt) then
        firstAt = life.firstAt
    end
    local highest = current
    if type(life) == "table" and type(life.highest) == "number" and (highest == nil or life.highest > highest) then
        highest = life.highest
    end
    local gained = type(life) == "table" and life.gained or 0
    local spent = type(life) == "table" and life.spent or 0
    local sawMovement = type(life) == "table" and life.moved == true
    for index = 1, #records do
        local event = records[index]
        local meta = event.meta or {}
        if event.at and (not firstAt or event.at < firstAt) then
            firstAt = event.at
        end
        if meta.balanceAfter ~= nil and (highest == nil or meta.balanceAfter > highest) then
            highest = meta.balanceAfter
        end
        if CountsAsEarned(meta.classification) then
            gained = gained + (event.delta or 0)
            sawMovement = true
        elseif CountsAsSpent(meta.classification) then
            spent = spent + math.abs(event.delta or 0)
            sawMovement = true
        end
    end
    if not firstAt and highest == nil and not sawMovement then
        return nil
    end
    return {
        firstAt = firstAt,
        highest = highest,
        gained = sawMovement and gained or (#records > 0 and 0 or nil),
        spent = sawMovement and spent or (#records > 0 and 0 or nil),
    }
end

local function CollectObserved(state, records, definition, current)
    local rows = {}
    local indexByGuid = {}
    local shared = definition and IsWarbandCurrency(definition)

    local function applyAmount(person, guid)
        if not person then
            return
        end
        -- Items and other character-scanned resources can retain a personal
        -- quantity even when the main resource is presented as a combined
        -- total. Warband currencies have one shared balance, so make that
        -- explicit instead of pretending each observer owns a separate copy.
        if state and type(state.characters) == "table" and type(state.characters[guid]) == "number" then
            person.amount = state.characters[guid]
            person.shared = false
        elseif shared and type(current) == "number" then
            person.amount = current
            person.shared = true
        end
    end

    local function touch(guid, at, observer)
        local person = Person(guid, state, observer)
        if not person then
            return
        end
        local row = indexByGuid[guid]
        if not row then
            person.at = type(at) == "number" and at or nil
            applyAmount(person, guid)
            indexByGuid[guid] = person
            rows[#rows + 1] = person
        elseif type(at) == "number" and (not row.at or at > row.at) then
            row.at = at
        end
    end
    if state and type(state.observed) == "table" then
        for guid, at in pairs(state.observed) do
            touch(guid, at, nil)
        end
    end
    for index = 1, #records do
        local event = records[index]
        local meta = event.meta or {}
        if meta.classification ~= SYNC then
            touch(event.guid, event.at, meta.observer)
        end
    end
    table.sort(rows, function(a, b)
        return (a.at or 0) > (b.at or 0)
    end)
    return rows
end

local function CollectHolders(state)
    local rows = {}
    if not state or type(state.characters) ~= "table" then
        return rows
    end
    for guid, amount in pairs(state.characters) do
        if type(amount) == "number" and WBF.Characters.IsDiscovered(guid) then
            local person = Person(guid, state, nil)
            if person then
                person.amount = amount
                rows[#rows + 1] = person
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.amount == b.amount then
            return (a.name or "") < (b.name or "")
        end
        return a.amount > b.amount
    end)
    return rows
end

function WBF.Resources.Board(key, startAt, endAt, periodLabel, guid, closed)
    local definition = key and registry[key] or nil
    local phrase = periodLabel and periodLabel:lower() or "this period"
    if not definition or not WBF.Database.IsReady() then
        return {
            missing = true,
            name = "Resource",
            periodTitle = periodLabel or "This Period",
            emptyActivity = "Nothing recorded for this resource.",
        }
    end
    local accountWide = IsWarbandCurrency(definition)
    local characterOwned = not accountWide and definition.ownership == "character" and definition.trackingType == "currency"
    local records = ResourceEvents(WBF.Database.Get().events or {}, definition.key)
    local period = Summarize(records, startAt, endAt, characterOwned and guid or nil, nil)
    local state = Store().balances[definition.key]
    local current
    if state and type(state.acceptedBalance) == "number" then
        current = state.acceptedBalance
    elseif accountWide then
        current = state and CanonicalBalance(state) or nil
    elseif state then
        current = TotalOf(state, definition)
    end
    local periodEnd = period.current
    if closed then
        current = periodEnd
    elseif current == nil then
        current = periodEnd
    end
    local name = DisplayName(definition)
    local badge = TypeBadge(definition)
    local activity = {}
    for index = 1, #records do
        local event = records[index]
        if InWindow(event, startAt, endAt) and IsShownActivity(event) then
            local meta = event.meta or {}
            local person = Person(event.guid, state, meta.observer)
            local opening = meta.classification == BASELINE
            activity[#activity + 1] = {
                at = event.at,
                delta = opening and 0 or (event.delta or 0),
                balance = meta.balanceAfter,
                opening = opening,
                name = person and person.name or nil,
                classFile = person and person.classFile or nil,
                guid = event.guid,
                note = RowNote(event),
            }
        end
    end
    table.sort(activity, function(a, b)
        if a.at == b.at then
            return false
        end
        return (a.at or 0) > (b.at or 0)
    end)
    if #activity > 200 then
        local trimmed = {}
        for index = 1, 200 do
            trimmed[index] = activity[index]
        end
        activity = trimmed
    end
    return {
        key = definition.key,
        name = name,
        texture = definition.iconFile,
        badge = badge,
        source = SourceLine(definition, badge),
        periodTitle = periodLabel or "This Period",
        current = current,
        closed = closed and true or nil,
        lastObservedAt = (not closed) and state and state.lastObservedAt or nil,
        period = {
            net = period.net or 0,
            earned = period.earned or 0,
            spent = period.spent or 0,
            opening = period.opening,
            current = closed and periodEnd or (period.current or current),
        },
        lifetime = LifetimeStats(records, state, current),
        history = BalanceSeries(records, startAt, endAt, state),
        windowStart = startAt,
        windowEnd = endAt,
        activity = activity,
        peopleMode = characterOwned and "balances" or "observed",
        people = characterOwned and CollectHolders(state) or CollectObserved(state, records, definition, current),
        emptyActivity = "No " .. name .. " balance changes detected " .. phrase .. ".",
    }
end

function WBF.Resources.ForPeriod(events, startAt, endAt, options)
    local closed = type(options) == "table" and options.closed == true
    local tiles = {}
    local byGuid = {}
    for index = 1, #order do
        local definition = registry[order[index]]
        if WBF.ResourceBehaviour and WBF.ResourceBehaviour.SkipsCurrencyBoard(definition) then
            -- Progression and regenerating meters are not currency tiles.
        elseif WBF.ResourceClassification and WBF.ResourceClassification.HidesFromPlayer(definition) then
            -- Internal counters stay in the registry and out of the summary.
        else
        local records = ResourceEvents(events, definition.key)
        local period = Summarize(records, startAt, endAt, nil, nil)
        -- A baseline alone is not period activity. Opening and current can both
        -- be non-zero while earned, spent, and net are all zero.
        local changed = (period.earned or 0) > 0 or (period.spent or 0) > 0 or (period.net or 0) ~= 0
        if changed then
            local instanceID = DominantInstance(records, startAt, endAt)
            local eventEarned = 0
            local eventName
            if instanceID then
                local eventSummary = Summarize(records, nil, nil, nil, instanceID)
                eventEarned = eventSummary.earned
                for recordIndex = 1, #records do
                    local meta = records[recordIndex].meta or {}
                    if meta.eventInstance == instanceID and meta.eventName then
                        eventName = meta.eventName
                        break
                    end
                end
            end
            local periodEnd = period.current
            local current = periodEnd
            if current == nil and not closed and IsWarbandCurrency(definition) then
                current = CanonicalBalance(Store().balances[definition.key])
            end
            tiles[#tiles + 1] = {
                key = definition.key,
                name = DisplayName(definition),
                short = ShortName(definition),
                texture = definition.iconFile,
                earned = period.earned,
                spent = period.spent,
                net = period.net,
                opening = period.opening,
                current = current,
                balanceAtEnd = closed and type(periodEnd) == "number",
                accountWide = IsWarbandCurrency(definition),
                eventEarned = eventEarned,
                eventName = eventName,
                milestones = definition.milestones,
            }
            if not IsWarbandCurrency(definition) then
            for characterIndex = 1, #period.characters do
                local character = period.characters[characterIndex]
                local list = byGuid[character.guid]
                if not list then
                    list = {}
                    byGuid[character.guid] = list
                end
                list[#list + 1] = {
                    key = definition.key,
                    short = ShortName(definition),
                    earned = character.earned,
                    spent = character.spent,
                    transferred = character.transferred,
                }
            end
            end
        end
        end
    end
    return { tiles = tiles, byGuid = byGuid }
end

function WBF.Resources.CharacterCards(events)
    local grouped = {}
    local keys = {}
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        local owned = registry[meta.resourceKey]
        if WBF.ResourceBehaviour and WBF.ResourceBehaviour.SkipsCurrencyBoard(owned or { name = meta.name, displayName = meta.name }) then
            -- Profession knowledge and concentration are not currency cards.
        elseif WBF.ResourceClassification and (WBF.ResourceClassification.HidesFromPlayer(owned) or WBF.ResourceClassification.HidesEvent(event)) then
            -- System counters are not session gains or spends.
        elseif event.eventType == WBF.EventType.Resource and meta.resourceKey and meta.ownership ~= "warband" and not IsWarbandCurrency(owned) then
            local row = grouped[meta.resourceKey]
            if not row then
                local definition = registry[meta.resourceKey]
                row = {
                    key = meta.resourceKey,
                    name = definition and ShortName(definition) or meta.name or meta.resourceKey,
                    texture = meta.icon or (definition and definition.iconFile) or nil,
                    earned = 0,
                    spent = 0,
                    transferred = 0,
                }
                grouped[meta.resourceKey] = row
                keys[#keys + 1] = meta.resourceKey
            end
            if CountsAsEarned(meta.classification) then
                row.earned = row.earned + (event.delta or 0)
            elseif CountsAsSpent(meta.classification) then
                row.spent = row.spent + math.abs(event.delta or 0)
            elseif meta.classification == TRANSFER then
                row.transferred = row.transferred + (event.delta or 0)
            end
        end
    end
    local cards = {}
    for index = 1, #keys do
        local row = grouped[keys[index]]
        if row.earned > 0 or row.spent > 0 or row.transferred ~= 0 then
            cards[#cards + 1] = row
        end
    end
    return cards
end

local function MilestoneHit(report)
    local milestones = report.milestones
    if not milestones then
        return nil
    end
    local best
    for index = 1, #milestones do
        local milestone = milestones[index]
        local amount
        if milestone.scope == "event" then
            amount = report.eventEarned or 0
            if (report.earned or 0) <= 0 then
                amount = 0
            end
        else
            amount = report.earned or 0
        end
        if amount >= milestone.amount and (not best or milestone.amount > best.amount) then
            best = milestone
        end
    end
    return best
end

function WBF.Resources.HighlightCandidates(resources)
    local candidates = {}
    for index = 1, #(resources or {}) do
        local report = resources[index]
        local milestone = MilestoneHit(report)
        if milestone then
            local scope = milestone.scope == "event" and (report.eventName or "This event") or "This period"
            candidates[#candidates + 1] = {
                kind = "resource:" .. report.key,
                score = 74,
                title = report.eventName or report.short,
                value = WBF.Format.Signed(milestone.amount) .. " earned",
                detail = scope,
                texture = report.texture,
                fallback = "Interface\\Icons\\INV_Misc_Coin_01",
                open = "resource",
                resourceKey = report.key,
            }
        end
    end
    return candidates
end

local jobs = {}
local listHeaders = {}
local listIndex = 1
local accountCursor = 1

local function SetStatus(status)
    if not WBF.Database.IsReady() then
        return
    end
    local scanState = Store().scanState
    if scanState.status == status then
        return
    end
    scanState.status = status
    if WBF.UI and WBF.UI.RequestRefresh then
        WBF.UI.RequestRefresh()
    end
end

local function CopyAmounts(state)
    local copy = {}
    for guid, amount in pairs(state.characters or {}) do
        if type(amount) == "number" then
            copy[guid] = amount
        end
    end
    return copy
end

local function RecentTransferCovers(key, guid, delta)
    local events = WBF.Database.Get().events or {}
    for index = #events, 1, -1 do
        local event = events[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.Resource and meta.resourceKey == key and meta.classification == TRANSFER and event.guid == guid and event.delta == delta then
            return true
        end
    end
    return false
end

local function HasUnmatchedOpposite(key, delta)
    local events = WBF.Database.Get().events or {}
    local opposite = -delta
    local matched = false
    for index = #events, 1, -1 do
        local event = events[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.Resource and meta.resourceKey == key and meta.classification == TRANSFER then
            if event.delta == delta then
                return false
            end
            if event.delta == opposite then
                matched = true
            end
        end
    end
    return matched
end

local function ReclassifyOpposite(key, delta, guid)
    local events = WBF.Database.Get().events or {}
    local now = WBF.Time.Now()
    for index = #events, 1, -1 do
        local event = events[index]
        if event.at and (now - event.at) > 7200 then
            break
        end
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.Resource and meta.resourceKey == key and event.guid ~= guid and event.delta == -delta then
            local classification = meta.classification
            if classification == TRANSFER then
                return true
            end
            if classification == SPEND or classification == LOSS_OBSERVED or classification == GAIN or classification == GAIN_OBSERVED then
                meta.classification = TRANSFER
                meta.warbandDelta = 0
                return true
            end
        end
    end
    return false
end

local function EnsureDiscoveredCurrency(currencyID, info, headerName, eventQuantity)
    currencyID = WBF.Format.AsNumber(currencyID)
    if not currencyID or currencyID <= 0 then
        return nil
    end
    local existing = FindCurrency(currencyID)
    if existing then
        ApplyCurrencyFlags(existing, info)
        if headerName and headerName ~= "" then
            existing.header = existing.header or headerName
            if existing.priority == "high" and existing.group == "expansion" then
                Store().scanState.expansionHeader = headerName
            end
        end
        return existing
    end
    local quantity = info and WBF.Format.AsNumber(info.quantity) or 0
    local reported = WBF.Format.AsNumber(eventQuantity)
    if (not quantity or quantity <= 0) and reported and reported > 0 then
        quantity = reported
    end
    if not quantity or quantity <= 0 then
        return nil
    end
    local name = info and WBF.Format.PlainString(info.name) or ("Currency " .. currencyID)
    local definition = {
        key = "currency_" .. currencyID,
        name = name,
        short = name,
        trackingType = "currency",
        id = currencyID,
        priority = "low",
        header = headerName,
    }
    Register(definition)
    ApplyCurrencyFlags(registry[definition.key], info)
    definition = registry[definition.key]
    if definition then
        if definition.classification == "ACCOUNT_WIDE_CURRENCY" and not definition.group then
            definition.group = "account"
        end
        PersistDefinition(definition)
    end
    return definition
end

local function EnsureDynamicCurrencies()
    if not C_CurrencyInfo or not C_CurrencyInfo.GetDragonIslesSuppliesCurrencyID then
        return
    end
    local ok, id = pcall(C_CurrencyInfo.GetDragonIslesSuppliesCurrencyID)
    id = ok and WBF.Format.AsNumber(id) or nil
    if not id then
        return
    end
    local existing = registry.dragon_isles_supplies
    if existing then
        if existing.id ~= id then
            byIdentity["currency:" .. tostring(existing.id)] = nil
            existing.id = id
            existing.suppressed = nil
            byIdentity["currency:" .. id] = existing
        end
        return
    end
    if FindCurrency(id) then
        return
    end
    Register({
        key = "dragon_isles_supplies",
        name = "Dragon Isles Supplies",
        short = "Dragon Isles Supplies",
        trackingType = "currency",
        id = id,
        group = "legacy",
        priority = "low",
        expectedName = "Dragon Isles Supplies",
    })
end

local function ApplyAuthoritative(definition, rows)
    if not definition or definition.suppressed or definition.classification == "ACCOUNT_WIDE_CURRENCY" then
        return
    end
    if WBF.ResourceClassification and WBF.ResourceClassification.HidesFromPlayer(definition) then
        return
    end
    if type(rows) ~= "table" then
        return
    end
    local state = StateFor(definition.key)
    local current = CurrentGUID()
    local localQuantity = current and state.characters[current] or nil
    if #rows == 0 and (localQuantity or 0) > 0 then
        return
    end
    local nextAmounts = {}
    local names = {}
    for index = 1, #rows do
        local row = rows[index]
        if type(row) == "table" and row.characterGUID then
            local amount = WBF.Format.AsNumber(row.quantity)
            local guid = row.characterGUID
            if amount ~= nil then
                nextAmounts[guid] = amount
                local characterName = WBF.Format.PlainString(row.characterName)
                names[guid] = characterName
                -- Account currency names other alts. That is not a login, so it
                -- does not create a roster record.
                RememberCharacterName(state, guid, characterName)
            end
        end
    end
    if current and state.characters[current] ~= nil and state.scanned and state.scanned[current] and state.authority and state.authority.at and state.scanned[current] > state.authority.at then
        nextAmounts[current] = state.characters[current]
    end
    local verified = true
    for guid, amount in pairs(state.characters) do
        if nextAmounts[guid] == nil and type(amount) == "number" and amount ~= 0 then
            nextAmounts[guid] = amount
            verified = false
        end
    end
    local previous = CopyAmounts(state)
    local hadAny = next(previous) ~= nil or state.baselined
    for guid, amount in pairs(nextAmounts) do
        state.characters[guid] = amount
        TouchScan(state, guid, "blizzard_account_data")
    end
    state.authority = {
        verified = verified,
        at = WBF.Time.Now(),
        source = "blizzard_account_data",
    }
    local total = TotalOf(state, definition)
    if not hadAny then
        state.baselined = true
        state.baselinedAt = WBF.Time.Now()
        if total > 0 then
            Record(definition, 0, total, BASELINE, nil)
        end
        return
    end
    local shifts = WBF.ResourceShift and WBF.ResourceShift.Classify(previous, nextAmounts) or {}
    for index = 1, #shifts do
        local shift = shifts[index]
        if (shift.classification == GAIN_OBSERVED or shift.classification == LOSS_OBSERVED or shift.classification == GAIN or shift.classification == SPEND) and (HasUnmatchedOpposite(definition.key, shift.delta) or ReclassifyOpposite(definition.key, shift.delta, shift.guid)) then
            shift.classification = TRANSFER
        end
        local covered = shift.classification ~= SYNC and RecentTransferCovers(definition.key, shift.guid, shift.delta)
        if not covered then
            local counterpart
            if shift.classification == TRANSFER then
                for otherIndex = 1, #shifts do
                    local other = shifts[otherIndex]
                    if other ~= shift and other.classification == TRANSFER and other.delta == -shift.delta then
                        counterpart = names[other.guid] or (state.names and state.names[other.guid])
                        break
                    end
                end
            end
            Record(definition, shift.delta, total, shift.classification, nil, shift.guid, nil, counterpart)
        end
    end
    state.baselined = true
    state.baselinedAt = state.baselinedAt or WBF.Time.Now()
end

local function IngestTransferLog()
    if not C_CurrencyInfo or not C_CurrencyInfo.FetchCurrencyTransferTransactions then
        return
    end
    if C_CurrencyInfo.IsCurrencyTransferTransactionDataReady and not C_CurrencyInfo.IsCurrencyTransferTransactionDataReady() then
        return
    end
    local ok, txns = pcall(C_CurrencyInfo.FetchCurrencyTransferTransactions)
    if not ok or type(txns) ~= "table" then
        return
    end
    local store = Store()
    if type(store.transferSeen) ~= "table" then
        store.transferSeen = {}
    end
    for index = 1, #txns do
        local txn = txns[index]
        local definition = FindCurrency(txn.currencyType)
        local qty = WBF.Format.AsNumber(txn.quantityTransferred) or 0
        local stamp = WBF.Format.AsNumber(txn.timestamp)
        if definition and not definition.suppressed and qty > 0 and stamp then
            local id = table.concat({
                tostring(txn.currencyType),
                tostring(txn.sourceCharacterGUID),
                tostring(txn.destinationCharacterGUID),
                tostring(stamp),
                tostring(qty),
            }, ":")
            if not store.transferSeen[id] then
                local balance = StateFor(definition.key)
                local started = balance.baselinedAt
                if started and stamp >= started - 120 then
                    store.transferSeen[id] = true
                    local already = RecentTransferCovers(definition.key, txn.sourceCharacterGUID, -qty)
                        or RecentTransferCovers(definition.key, txn.destinationCharacterGUID, qty)
                    if not already then
                        local total = TotalOf(balance, definition)
                        RememberCharacterName(balance, txn.sourceCharacterGUID, txn.sourceCharacterName)
                        RememberCharacterName(balance, txn.destinationCharacterGUID, txn.destinationCharacterName)
                        Record(definition, -qty, total, TRANSFER, nil, txn.sourceCharacterGUID, nil, txn.destinationCharacterName, stamp)
                        Record(definition, qty, total, TRANSFER, nil, txn.destinationCharacterGUID, nil, txn.sourceCharacterName, stamp)
                    end
                end
            end
        end
    end
end

local function HeaderFor(depth)
    local best, bestDepth
    for storedDepth, name in pairs(listHeaders) do
        if storedDepth < depth and (not bestDepth or storedDepth > bestDepth) then
            best = name
            bestDepth = storedDepth
        end
    end
    return best
end

local function ExpandStep()
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyListInfo or not C_CurrencyInfo.GetCurrencyListSize then
        listIndex = 1
        return
    end
    local size = C_CurrencyInfo.GetCurrencyListSize() or 0
    for index = 1, size do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, index)
        if ok and type(info) == "table" and info.isHeader and not info.isHeaderExpanded then
            collapsedHeaders = collapsedHeaders or {}
            collapsedHeaders[#collapsedHeaders + 1] = info.name
            pcall(C_CurrencyInfo.ExpandCurrencyList, index, true)
            table.insert(jobs, 1, ExpandStep)
            return
        end
    end
    listIndex = 1
    listHeaders = {}
end

local function ReadStep()
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyListInfo then
        return
    end
    local size = C_CurrencyInfo.GetCurrencyListSize() or 0
    local stopAt = math.min(size, listIndex + 14)
    while listIndex <= stopAt do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, listIndex)
        if ok and type(info) == "table" then
            if info.isHeader then
                local depth = info.currencyListDepth or 0
                listHeaders[depth] = info.name
                for deeper = depth + 1, 8 do
                    listHeaders[deeper] = nil
                end
            else
                local header = HeaderFor(info.currencyListDepth or 1)
                local currencyID = info.currencyID
                if not currencyID and C_CurrencyInfo.GetCurrencyListLink and C_CurrencyInfo.GetCurrencyIDFromLink then
                    local linkOk, link = pcall(C_CurrencyInfo.GetCurrencyListLink, listIndex)
                    if linkOk and type(link) == "string" then
                        local idOk, linked = pcall(C_CurrencyInfo.GetCurrencyIDFromLink, link)
                        if idOk then
                            currencyID = linked
                        end
                    end
                end
                EnsureDiscoveredCurrency(currencyID, info, header)
            end
        end
        listIndex = listIndex + 1
    end
    if listIndex <= size then
        table.insert(jobs, 1, ReadStep)
    end
end

local function RestoreStep()
    if not collapsedHeaders or #collapsedHeaders == 0 or not C_CurrencyInfo then
        collapsedHeaders = nil
        return
    end
    local name = table.remove(collapsedHeaders)
    local size = C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListSize() or 0
    for index = size, 1, -1 do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, index)
        if ok and type(info) == "table" and info.isHeader and info.name == name and info.isHeaderExpanded then
            pcall(C_CurrencyInfo.ExpandCurrencyList, index, false)
            break
        end
    end
    if collapsedHeaders and #collapsedHeaders > 0 then
        table.insert(jobs, 1, RestoreStep)
    else
        collapsedHeaders = nil
    end
end

local function AccountApplyStep()
    if not C_CurrencyInfo or not C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters then
        return
    end
    if C_CurrencyInfo.IsAccountCharacterCurrencyDataReady and not C_CurrencyInfo.IsAccountCharacterCurrencyDataReady() then
        return
    end
    local stopAt = math.min(#order, accountCursor + 7)
    while accountCursor <= stopAt do
        local definition = registry[order[accountCursor]]
        if definition and definition.trackingType == "currency" and not definition.suppressed then
            if not IsWarbandCurrency(definition) and ReadAccountWide(definition, nil) == true then
                definition.classification = "ACCOUNT_WIDE_CURRENCY"
                definition.ownership = "warband"
                MigrateWarband(definition)
            end
            -- This API repeats a Warband balance on every character. Applying it
            -- would store one copy per character and invent gains and spends.
            if not IsWarbandCurrency(definition) then
                local ok, rows = pcall(C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters, definition.id)
                if ok and type(rows) == "table" then
                    ApplyAuthoritative(definition, rows)
                end
            end
        end
        accountCursor = accountCursor + 1
    end
    if accountCursor <= #order then
        table.insert(jobs, 1, AccountApplyStep)
    end
end

local function RequestAccount()
    if C_CurrencyInfo and C_CurrencyInfo.RequestCurrencyDataForAccountCharacters then
        pcall(C_CurrencyInfo.RequestCurrencyDataForAccountCharacters)
    end
end

local function AnnounceDiscovery()
    local count = discoveryCount
    discoveryCount = 0
    if count <= 0 or not WBF.Database.IsReady() then
        return
    end
    local config = WBF.Database.Get().config
    if config and config.resourceNotices == false then
        return
    end
    local character = WBF.Characters.GetCurrent()
    local name = character and character.name or "this character"
    local noun = count == 1 and "resource" or "resources"
    print("|cffd4af37WarbandFYI|r discovered " .. count .. " " .. noun .. " on " .. name .. ".")
end

local function Pump()
    if InCombatLockdown and InCombatLockdown() then
        scanWaiting = true
        SetStatus("paused")
        return
    end
    local job = table.remove(jobs, 1)
    if not job then
        scanRunning = false
        if scanQueued then
            scanQueued = false
            WBF.Resources.QueueFullScan()
            return
        end
        local scanState = Store().scanState
        scanState.lastScan = WBF.Time.Now()
        scanState.status = "up_to_date"
        AnnounceDiscovery()
        if WBF.UI and WBF.UI.RequestRefresh then
            WBF.UI.RequestRefresh()
        end
        return
    end
    job()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, Pump)
    else
        Pump()
    end
end

function WBF.Resources.QueueFullScan()
    if not WBF.Database.IsReady() then
        return
    end
    if scanRunning then
        scanQueued = true
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        scanWaiting = true
        SetStatus("paused")
        return
    end
    discoveryCount = 0
    listHeaders = {}
    listIndex = 1
    collapsedHeaders = {}
    SetStatus("refreshing")
    scanRunning = true
    scanWaiting = false
    jobs = {
        function()
            if C_Calendar and C_Calendar.OpenCalendar then
                pcall(C_Calendar.OpenCalendar)
            end
            if not ScanCalendar() then
                RefreshActive()
            end
        end,
        EnsureDynamicCurrencies,
        RequestAccount,
        ExpandStep,
        ReadStep,
        RestoreStep,
        SyncCurrencies,
        ScanItems,
        function()
            accountCursor = 1
            AccountApplyStep()
        end,
        IngestTransferLog,
    }
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, Pump)
    else
        Pump()
    end
end

function WBF.Resources.Resume()
    if itemScanPending then
        ScheduleItemScan()
    end
    if #jobs > 0 then
        scanWaiting = false
        scanRunning = true
        Pump()
        return
    end
    if scanWaiting then
        scanWaiting = false
        WBF.Resources.QueueFullScan()
    end
end

function WBF.Resources.RefreshBalances()
    if not WBF.Database.IsReady() then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    ScheduleItemScan()
    SyncCurrencies()
end

function WBF.Resources.Refresh()
    WBF.Resources.RefreshBalances()
end

function WBF.Resources.SectionCollapsed(eraId, defaultCollapsed)
    if not eraId or not WBF.Database.IsReady() then
        return defaultCollapsed and true or false
    end
    local saved = WBF.Database.Get().config.resourceSections
    if type(saved) == "table" then
        local value = saved[eraId]
        if value == nil and eraId == "cross_expansion" then
            value = saved.cross
        end
        if value ~= nil then
            return value and true or false
        end
    end
    return defaultCollapsed and true or false
end

function WBF.Resources.SetSectionCollapsed(eraId, collapsed)
    if not eraId or not WBF.Database.IsReady() then
        return
    end
    local config = WBF.Database.Get().config
    if type(config.resourceSections) ~= "table" then
        config.resourceSections = {}
    end
    config.resourceSections[eraId] = collapsed and true or false
end

local function ScannedCount(state)
    local count = 0
    if type(state.scanned) == "table" then
        for _ in pairs(state.scanned) do
            count = count + 1
        end
    end
    return count
end

function WBF.Resources.IsWatched(key)
    if not key or not WBF.Database.IsReady() then
        return false
    end
    return Store().watchlist[key] == true
end

function WBF.Resources.SetWatched(key, enabled)
    if not key or not WBF.Database.IsReady() then
        return
    end
    if enabled then
        Store().watchlist[key] = true
    else
        Store().watchlist[key] = nil
    end
end

local function ActivityLabel(event)
    local meta = event.meta or {}
    if meta.sourceLabel and meta.sourceLabel ~= "" then
        return meta.sourceLabel
    end
    local classification = meta.classification
    if classification == TRANSFER then
        if meta.counterpart and meta.counterpart ~= "" then
            if (event.delta or 0) < 0 then
                return "Transferred to " .. meta.counterpart
            end
            return "Transferred from " .. meta.counterpart
        end
        return "Transferred"
    end
    -- The sign/color of the delta already communicates ordinary gains and
    -- losses. Keep Context for information that adds something useful, such
    -- as transfers or a caller-provided source, rather than repeating
    -- "Observed resource gain/loss" on every row.
    if classification == GAIN or classification == GAIN_OBSERVED then
        return nil
    end
    if classification == SPEND or classification == LOSS_OBSERVED then
        return nil
    end
    if classification == SYNC then
        return "Already held"
    end
    return nil
end

local function CharacterHoldingRows(definition, state)
    local rows = {}
    if definition.classification == "ACCOUNT_WIDE_CURRENCY" then
        return rows, 0
    end
    for guid, amount in pairs(state.characters or {}) do
        if type(amount) == "number" and WBF.Characters.IsDiscovered(guid) then
            local stored = WBF.Characters.Get(guid)
            local scanned = state.scanned and state.scanned[guid] or nil
            rows[#rows + 1] = {
                guid = guid,
                name = (stored and stored.name) or (state.names and state.names[guid]) or "Character",
                classFile = stored and stored.classFile or nil,
                amount = amount,
                lastScanned = scanned,
                bank = false,
            }
        end
    end
    if definition.trackingType == "item" and type(state.account) == "number" and state.account > 0 then
        rows[#rows + 1] = {
            name = "Warband Bank",
            amount = state.account,
            bank = true,
            lastScanned = state.authority and state.authority.at or nil,
        }
    end
    table.sort(rows, function(a, b)
        if a.amount == b.amount then
            return (a.lastScanned or 0) > (b.lastScanned or 0)
        end
        return a.amount > b.amount
    end)
    local visible = {}
    local hiddenZeros = 0
    for index = 1, #rows do
        local row = rows[index]
        if row.amount > 0 then
            visible[#visible + 1] = row
        else
            -- Keep zero snapshots in saved state, but do not surface empty
            -- holders in the breakdown. They answer "was this character
            -- checked?", not "where is the resource?".
            hiddenZeros = hiddenZeros + 1
        end
    end
    return visible, hiddenZeros
end

local function TimewalkingCounts(startAt, endAt)
    local runs, bosses = 0, 0
    local events = WBF.Database.Get().events or {}
    for index = 1, #events do
        local event = events[index]
        if event.at and (not startAt or event.at >= startAt) and (not endAt or event.at <= endAt) then
            local meta = event.meta or {}
            local difficulty = type(meta.difficultyName) == "string" and meta.difficultyName:lower() or ""
            if difficulty:find("timewalking", 1, true) then
                if event.eventType == WBF.EventType.InstanceEnter then
                    runs = runs + 1
                elseif event.eventType == WBF.EventType.BossKill then
                    bosses = bosses + 1
                end
            end
        end
    end
    return runs, bosses
end

local function BuildResource(definition)
    if WBF.ResourceBehaviour and WBF.ResourceBehaviour.SkipsCurrencyBoard(definition) then
        return nil
    end
    if WBF.ResourceClassification and WBF.ResourceClassification.HidesFromPlayer(definition) then
        return nil
    end
    local state = Store().balances[definition.key]
    if type(state) ~= "table" then
        return nil
    end
    local total = TotalOf(state, definition)
    local watched = WBF.Resources.IsWatched(definition.key)
    local instance = definition.eventKey and active[definition.eventKey] or nil
    local present = total > 0 or watched or (definition.priority == "high" and (state.baselined or HasCharacters(state) or state.accountWide ~= nil))
    if not present and instance and (state.baselined or HasCharacters(state) or state.account ~= nil) then
        present = true
    end
    if not present then
        return nil
    end
    local weekStart = WBF.Aggregator and WBF.Aggregator.Range and WBF.Aggregator.Range("week") or nil
    local now = WBF.Time.Now()
    local report = WBF.Resources.Report(definition.key, weekStart, now, nil)
    local period = report and report.period or {}
    local eventStats = report and report.event or nil
    local useEvent = definition.eventKey and eventStats and ((eventStats.earned or 0) > 0 or (eventStats.spent or 0) > 0)
    local earned = useEvent and eventStats.earned or period.earned or 0
    local spent = useEvent and eventStats.spent or period.spent or 0
    local transferred = period.transferred or 0
    local changedRecently = (state.lastChangeAt and (now - state.lastChangeAt) < 7 * 86400) or earned > 0 or spent > 0 or transferred > 0
    local verified = state.authority and state.authority.verified and definition.classification ~= "ACCOUNT_WIDE_CURRENCY"
    local caption = "Known total"
    if definition.trackingType == "item" or definition.group == "events" then
        caption = "Current total"
    elseif definition.classification == "ACCOUNT_WIDE_CURRENCY" then
        caption = "Warband balance"
        verified = CanonicalBalance(state) ~= nil
    elseif verified then
        caption = "Warband total"
    end
    local badge
    if definition.eventKey then
        badge = instance and (active[definition.eventKey].sourceName or definition.eventKey) or "Not active"
        local eventInfoName = instance and instance.name
        if eventInfoName then
            badge = eventInfoName:gsub(" %d%d%d%d$", "")
        end
    elseif changedRecently and (earned > 0 or spent > 0 or transferred > 0 or (state.lastChangeAt and (now - state.lastChangeAt) < 7 * 86400)) then
        badge = "Active"
    end
    local holders = 0
    local freshAt
    for guid, amount in pairs(state.characters or {}) do
        if type(amount) == "number" and amount > 0 and WBF.Characters.IsDiscovered(guid) then
            holders = holders + 1
        end
    end
    if type(state.scanned) == "table" then
        for _, scanned in pairs(state.scanned) do
            if type(scanned) == "number" and (not freshAt or scanned > freshAt) then
                freshAt = scanned
            end
        end
    end
    local era = WBF.ResourceMeta.For(definition)
    return {
        key = definition.key,
        id = definition.id,
        trackingType = definition.trackingType,
        name = DisplayName(definition),
        short = ShortName(definition),
        texture = definition.iconFile,
        era = era.era,
        eraLabel = era.label,
        status = era.status,
        kind = era.kind,
        priority = definition.priority,
        watched = watched,
        amount = total,
        known = type(total) == "number",
        caption = caption,
        verified = verified and true or false,
        earned = earned,
        spent = spent,
        net = (earned or 0) - (spent or 0),
        transferred = transferred,
        accountWide = IsWarbandCurrency(definition),
        periodLabel = useEvent and "this event" or "this week",
        active = changedRecently and true or false,
        badge = badge,
        quiet = earned == 0 and spent == 0 and transferred == 0,
        lastChangeAt = state.lastChangeAt,
        header = definition.header,
        eventName = instance and instance.name or nil,
        classification = definition.classification,
        holders = holders,
        freshAt = freshAt,
        sample = state.sample and true or false,
    }
end

function WBF.Resources.Catalog()
    if not WBF.Database.IsReady() then
        return { resources = {}, discovered = 0, activeCount = 0, status = "waiting" }
    end
    RefreshActive()
    local resources = {}
    local activeCount = 0
    for index = 1, #order do
        local definition = registry[order[index]]
        if definition and not definition.suppressed then
            local card = BuildResource(definition)
            if card then
                resources[#resources + 1] = card
                if card.active then
                    activeCount = activeCount + 1
                end
            end
        end
    end
    table.sort(resources, function(a, b)
        if a.known ~= b.known then
            return a.known
        end
        if a.known and a.amount ~= b.amount then
            return a.amount > b.amount
        end
        local aName = a.name or ""
        local bName = b.name or ""
        if aName ~= bName then
            return aName < bName
        end
        return (a.id or 0) < (b.id or 0)
    end)
    local scanState = Store().scanState
    return {
        resources = resources,
        discovered = #resources,
        activeCount = activeCount,
        lastUpdated = scanState.lastScan,
        status = scanState.status or "waiting",
        expansionHeader = scanState.expansionHeader,
    }
end

function WBF.Resources.Detail(key)
    local definition = key and registry[key] or nil
    if not definition or definition.suppressed or not WBF.Database.IsReady() then
        return nil
    end
    local state = Store().balances[key]
    if type(state) ~= "table" then
        return nil
    end
    local card = BuildResource(definition)
    if not card then
        return nil
    end
    local weekStart = WBF.Aggregator.Range("week")
    local now = WBF.Time.Now()
    local report = WBF.Resources.Report(key, weekStart, now, nil)
    local period = report and report.period or {}
    local rows, hiddenZeros = CharacterHoldingRows(definition, state)
    local activity = {}
    local source = period.activity or {}
    for index = 1, math.min(12, #source) do
        local event = source[index]
        local meta = event.meta or {}
        if meta.classification ~= BASELINE and meta.classification ~= SYNC then
            activity[#activity + 1] = {
                at = event.at,
                delta = event.delta or 0,
                label = ActivityLabel(event),
                classification = meta.classification,
            }
        end
    end
    local tags = {}
    if definition.classification == "WARBAND_TRANSFERABLE_CURRENCY" then
        tags[#tags + 1] = "Warband Transferable"
    elseif definition.classification == "ACCOUNT_WIDE_CURRENCY" then
        tags[#tags + 1] = "Warband shared"
    elseif definition.classification == "EVENT_ITEM_RESOURCE" then
        tags[#tags + 1] = "Event Item"
    elseif definition.classification == "ITEM_RESOURCE" then
        tags[#tags + 1] = "Item"
    end
    local totalLabel = "Known Warband Total"
    local sourceLabel = ScannedCount(state) .. " characters scanned"
    if definition.classification == "ACCOUNT_WIDE_CURRENCY" then
        totalLabel = "Current balance"
        sourceLabel = "Warband shared"
    elseif definition.trackingType == "item" then
        totalLabel = "Current Total"
        sourceLabel = "Bags, bank, and Warband bank"
    elseif card.verified then
        totalLabel = "Warband Total"
        sourceLabel = "Data from Blizzard account characters"
    end
    if state.sample then
        sourceLabel = "Sample history"
    end
    local subtitle = card.eraLabel or WBF.ResourceMeta.Label(card.era)
    local runs, bosses
    if definition.eventKey == "timewalking" then
        runs, bosses = TimewalkingCounts(weekStart, now)
    end
    return {
        key = key,
        id = definition.id,
        trackingType = definition.trackingType,
        name = card.name,
        subtitle = subtitle,
        era = card.era,
        eraLabel = card.eraLabel,
        status = card.status,
        kind = card.kind,
        texture = card.texture,
        tags = tags,
        amount = card.amount,
        totalLabel = totalLabel,
        verified = card.verified,
        sourceLabel = sourceLabel,
        lastUpdated = state.authority and state.authority.at or state.lastChangeAt or (state.scanned and state.scanned[CurrentGUID() or ""]),
        week = {
            earned = period.earned or 0,
            spent = period.spent or 0,
            transferred = period.transferred or 0,
            net = period.net or 0,
            opening = period.opening,
        },
        observed = ObservedNames(state),
        characters = rows,
        hiddenZeros = hiddenZeros,
        activity = activity,
        watched = card.watched,
        accountWide = definition.classification == "ACCOUNT_WIDE_CURRENCY",
        runs = runs,
        bosses = bosses,
        scannedCount = ScannedCount(state),
        sample = state.sample and true or false,
    }
end

local function DebugFlag(value)
    local parsed = WBF.Format.AsBoolean(value)
    if parsed == nil then
        return "?"
    end
    return parsed and "yes" or "no"
end

function WBF.Resources.DebugDump()
    if not WBF.Database.IsReady() then
        print("|cffd4af37WarbandFYI|r resource data is not ready.")
        return
    end
    local rows = {}
    local seen = {}
    local function Add(currencyID, info, definition)
        currencyID = WBF.Format.AsNumber(currencyID)
        if not currencyID or seen[currencyID] then
            return
        end
        seen[currencyID] = true
        info = type(info) == "table" and info or nil
        local name = (info and WBF.Format.PlainString(info.name)) or (definition and (definition.displayName or definition.name)) or ""
        local quantity = info and WBF.Format.AsNumber(info.quantity) or nil
        if quantity == nil and definition then
            local state = Store().balances[definition.key]
            quantity = state and (state.acceptedBalance or state.currentBalance) or nil
        end
        local class, reason
        if definition and definition.playerClass then
            class = definition.playerClass
            reason = definition.playerClassReason
        elseif WBF.ResourceClassification then
            class, reason = WBF.ResourceClassification.ClassifyCurrency(currencyID, info or { name = name, currencyID = currencyID })
        else
            class = "unknown"
        end
        local weekly = "?"
        if info then
            local maxWeekly = WBF.Format.AsNumber(info.maxWeeklyQuantity)
            local canWeek = WBF.Format.AsBoolean(info.canEarnPerWeek)
            local canText = canWeek == nil and "?" or (canWeek and "yes" or "no")
            local maxText = maxWeekly == nil and "?" or tostring(maxWeekly)
            weekly = canText .. "/" .. maxText
        end
        rows[#rows + 1] = {
            id = currencyID,
            class = class or "unknown",
            reason = reason or "",
            quantity = quantity,
            discovered = info and DebugFlag(info.discovered) or "?",
            backpack = info and DebugFlag(info.isShowInBackpack) or "?",
            unused = info and DebugFlag(info.isTypeUnused) or "?",
            weekly = weekly,
            name = name,
        }
    end
    for index = 1, #order do
        local definition = registry[order[index]]
        if definition and definition.trackingType == "currency" then
            local _, _, _, info = ReadCurrency(definition.id)
            Add(definition.id, info, definition)
        end
    end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListInfo and C_CurrencyInfo.GetCurrencyListSize then
        local size = C_CurrencyInfo.GetCurrencyListSize() or 0
        for index = 1, size do
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, index)
            if ok and type(info) == "table" and not info.isHeader then
                Add(info.currencyID, info, info.currencyID and FindCurrency(info.currencyID) or nil)
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.class ~= b.class then
            return a.class < b.class
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.id < b.id
    end)
    print("|cffd4af37WarbandFYI|r resources " .. #rows)
    print("id | class | qty | discovered | backpack | unused | weekly | reason | name")
    for index = 1, #rows do
        local row = rows[index]
        print(table.concat({
            tostring(row.id),
            row.class,
            row.quantity == nil and "?" or tostring(row.quantity),
            row.discovered,
            row.backpack,
            row.unused,
            row.weekly,
            row.reason,
            row.name,
        }, " | "))
    end
end

function WBF.Resources.Status()
    local catalog = WBF.Resources.Catalog()
    local characters = 0
    if WBF.Database.IsReady() and WBF.Characters.List then
        characters = #WBF.Characters.List()
    end
    return {
        discovered = catalog.discovered,
        active = catalog.activeCount,
        lastScan = catalog.lastUpdated,
        status = catalog.status,
        characters = characters,
    }
end

function WBF.Resources.LoadSample(sessionId, now, warrior, miranora)
    if not WBF.Database.IsReady() then
        return
    end
    local store = Store()
    local seeded = {}
    local function Hold(key, guid, amount, verified)
        local state = StateFor(key)
        if next(state.characters) ~= nil and not state.sample then
            return
        end
        if not seeded[key] then
            state.characters = {}
            state.account = 0
            state.accountWide = nil
        end
        seeded[key] = true
        state.sample = true
        state.baselined = true
        state.baselinedAt = now - 20 * 86400
        state.characters[guid] = (state.characters[guid] or 0) + amount
        TouchScan(state, guid, verified and "blizzard_account_data" or "character_scan")
        if verified then
            state.authority = {
                verified = true,
                at = now - 120,
                source = "blizzard_account_data",
            }
        end
    end
    Hold("voidlight_marl", miranora, 20000, true)
    Hold("voidlight_marl", warrior, 5488, true)
    Hold("undercoin", warrior, 8370, true)
    Hold("timewarped_badge", warrior, 14280, false)
    Hold("brewfest_token", miranora, 184, false)
    Hold("dragon_isles_supplies", warrior, 3820, false)

    local db = WBF.Database.Get()
    local function Add(at, guid, key, delta, balance, classification, text, counterpart)
        if not seeded[key] then
            return
        end
        db.events[#db.events + 1] = {
            id = WBF.Database.AllocEventId(),
            at = at,
            sessionId = sessionId,
            guid = guid,
            category = WBF.Category.Resource,
            eventType = WBF.EventType.Resource,
            delta = delta,
            new = balance,
            text = text,
            sample = true,
            meta = {
                resourceKey = key,
                balanceAfter = balance,
                classification = classification,
                warbandDelta = (classification == TRANSFER or classification == BASELINE) and 0 or delta,
                counterpart = counterpart,
                name = key,
            },
        }
    end
    local weekStart = WBF.Time.StartOfWeek(now)
    Add(weekStart - 3600, miranora, "voidlight_marl", 0, 23168, BASELINE, "Voidlight Marl baseline")
    Add(now - 6 * 3600, miranora, "voidlight_marl", 3420, 26588, GAIN_OBSERVED, "Voidlight Marl +3,420")
    Add(now - 4 * 3600, miranora, "voidlight_marl", -1100, 25488, LOSS_OBSERVED, "Voidlight Marl -1,100")
    Add(now - 3 * 86400, warrior, "voidlight_marl", -5000, 25488, TRANSFER, "Voidlight Marl transferred -5,000", "Miranora")
    Add(now - 3 * 86400 + 1, miranora, "voidlight_marl", 5000, 25488, TRANSFER, "Voidlight Marl transferred +5,000", "Warrior")
    local marl = StateFor("voidlight_marl")
    marl.lastChangeAt = now - 4 * 3600
    Add(weekStart - 3600, miranora, "brewfest_token", 0, 128, BASELINE, "Brewfest Prize Token baseline")
    Add(now - 5 * 3600, miranora, "brewfest_token", 96, 224, GAIN_OBSERVED, "Brewfest Prize Token +96")
    Add(now - 2 * 3600, miranora, "brewfest_token", -40, 184, LOSS_OBSERVED, "Brewfest Prize Token -40")
    StateFor("brewfest_token").lastChangeAt = now - 2 * 3600
end

local LEDGER_REPAIR = 1
local FOLD_SECONDS = 20

local function GroupResourceEvents(events)
    local grouped = {}
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.Resource and meta.resourceKey then
            local list = grouped[meta.resourceKey]
            if not list then
                list = {}
                grouped[meta.resourceKey] = list
            end
            list[#list + 1] = event
        end
    end
    for _, list in pairs(grouped) do
        table.sort(list, function(a, b)
            if a.at == b.at then
                return (a.id or 0) < (b.id or 0)
            end
            return (a.at or 0) < (b.at or 0)
        end)
    end
    return grouped
end

RepairHistory = function(force)
    if not WBF.Database.IsReady() then
        return 0
    end
    local store = Store()
    if not force and store.ledgerRepair == LEDGER_REPAIR then
        return 0
    end
    local db = WBF.Database.Get()
    local events = db.events or {}
    local grouped = GroupResourceEvents(events)
    local remove = {}
    local removed = 0
    for key, list in pairs(grouped) do
        local cleaned = WithoutTransientPairs(list)
        if #cleaned ~= #list then
            local survive = {}
            for index = 1, #cleaned do
                survive[cleaned[index]] = true
            end
            for index = 1, #list do
                if not survive[list[index]] then
                    remove[list[index]] = true
                    removed = removed + 1
                end
            end
        end
        local index = 1
        while index <= #cleaned do
            local event = cleaned[index]
            local meta = event.meta or {}
            if meta.classification == BASELINE and not remove[event] then
                local balance = meta.balanceAfter or 0
                local folded = false
                local nextIndex = index + 1
                while nextIndex <= #cleaned do
                    local follower = cleaned[nextIndex]
                    local followerMeta = follower.meta or {}
                    if followerMeta.classification ~= SYNC or remove[follower] then
                        break
                    end
                    if (follower.at or 0) - (event.at or 0) > FOLD_SECONDS then
                        break
                    end
                    balance = followerMeta.balanceAfter or (balance + (follower.delta or 0))
                    remove[follower] = true
                    removed = removed + 1
                    folded = true
                    nextIndex = nextIndex + 1
                end
                if folded then
                    event.meta.balanceAfter = balance
                    event.new = balance
                    event.delta = 0
                end
                index = nextIndex
            else
                index = index + 1
            end
        end
        local last
        for cursor = #cleaned, 1, -1 do
            local event = cleaned[cursor]
            if not remove[event] and event.meta and event.meta.balanceAfter ~= nil then
                last = event
                break
            end
        end
        if last then
            local state = StateFor(key)
            state.acceptedBalance = last.meta.balanceAfter
            local definition = registry[key]
            if definition and IsWarbandCurrency(definition) then
                state.currentBalance = last.meta.balanceAfter
                state.accountWide = last.meta.balanceAfter
                state.previousBalance = last.meta.balanceAfter
            end
        end
    end
    if removed > 0 then
        local kept = {}
        for index = 1, #events do
            if not remove[events[index]] then
                kept[#kept + 1] = events[index]
            end
        end
        db.events = kept
    end
    if not force then
        store.ledgerRepair = LEDGER_REPAIR
    end
    return removed
end

function WBF.Resources.RepairHistory(force)
    return RepairHistory(force and true or false)
end

function WBF.Resources.ConfirmPending(key)
    local held = pendingObserve[key]
    if not held then
        return
    end
    if InSettle() then
        ScheduleConfirm(key)
        return
    end
    local definition = registry[key]
    if not definition then
        pendingObserve[key] = nil
        return
    end
    if definition.trackingType == "item" then
        local personal, account = ReadItemParts(definition.id)
        if personal == nil or account == nil then
            ScheduleConfirm(key)
            return
        end
        WBF.Resources.ObserveItem(definition.key, personal, account, held.guid or CurrentGUID(), held.event or "CONFIRM", AccountBankReady())
        return
    end
    local quantity = ReadCurrency(definition.id)
    if quantity == nil then
        ScheduleConfirm(key)
        return
    end
    NoteCurrency(definition, quantity, nil, nil, nil, held.guid)
end

function WBF.Resources.BeginSettle()
    settleUntil = WBF.Time.Now() + SETTLE_SECONDS
    if not C_Timer or not C_Timer.After then
        return
    end
    C_Timer.After(SETTLE_SECONDS + 0.05, function()
        if InSettle() then
            return
        end
        ScanItems()
        SyncCurrencies()
    end)
end

function WBF.Resources.ByCurrencyID(currencyID)
    return FindCurrency(currencyID)
end

function WBF.Resources.NotebookView(key)
    local definition = type(key) == "string" and registry[key] or nil
    if not definition or definition.suppressed then
        return nil
    end
    local state = nil
    if WBF.Database.IsReady() then
        state = Store().balances[key]
    end
    local amount = nil
    local character = nil
    if type(state) == "table" then
        amount = TotalOf(state, definition)
        if not IsWarbandCurrency(definition) then
            local guid = CurrentGUID()
            if guid and type(state.characters) == "table" and type(state.characters[guid]) == "number" then
                character = state.characters[guid]
            end
        end
    end
    return {
        key = definition.key,
        name = DisplayName(definition),
        icon = definition.iconFile,
        amount = amount,
        character = character,
        accountWide = IsWarbandCurrency(definition) and true or false,
    }
end

function WBF.Resources.SearchNames(text, limit)
    text = WBF.Format.PlainString(text)
    if not text or text == "" then
        return {}
    end
    local needle = text:lower()
    limit = limit or 8
    local list = {}
    for index = 1, #order do
        local definition = registry[order[index]]
        if definition and not definition.suppressed then
            local name = DisplayName(definition)
            local shortName = definition.short or ""
            local idText = tostring(definition.id or "")
            local hay = (name .. " " .. shortName .. " " .. definition.key):lower()
            if hay:find(needle, 1, true) or idText == needle then
                list[#list + 1] = {
                    key = definition.key,
                    name = name,
                    id = definition.id,
                    trackingType = definition.trackingType,
                }
                if #list >= limit then
                    break
                end
            end
        end
    end
    return list
end

function WBF.Resources.Find(text)
    text = WBF.Format.PlainString(text)
    if not text or text == "" then
        return nil
    end
    local needle = text:lower()
    if registry[needle] then
        return registry[needle]
    end
    local matches = {}
    for index = 1, #order do
        local definition = registry[order[index]]
        local name = (definition.name or ""):lower()
        local shortName = (definition.short or ""):lower()
        if definition.key == needle or name == needle or shortName == needle then
            return definition
        end
        if name:find(needle, 1, true) or shortName:find(needle, 1, true) or definition.key:find(needle, 1, true) then
            matches[#matches + 1] = definition
        end
    end
    if #matches == 1 then
        return matches[1]
    end
    return nil, matches
end

function WBF.Resources.ObserveBalance(key, quantity, change, sourced)
    local definition = registry[key]
    if not definition then
        return
    end
    local gain = sourced and 1 or nil
    NoteCurrency(definition, quantity, change, gain, nil)
end

function WBF.Resources.NoteSpecialCurrency(currencyID, behaviour, extra)
    currencyID = WBF.Format.AsNumber(currencyID)
    if not currencyID or currencyID <= 0 then
        return nil
    end
    extra = extra or {}
    local info
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, result = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        if ok and type(result) == "table" then
            info = result
        end
    end
    local definition = FindCurrency(currencyID)
    if not definition then
        local name = (info and WBF.Format.PlainString(info.name)) or extra.name or ("Currency " .. currencyID)
        Register({
            key = "currency_" .. currencyID,
            name = name,
            short = name,
            trackingType = "currency",
            id = currencyID,
            priority = "low",
            behaviour = behaviour,
        })
        definition = FindCurrency(currencyID)
    end
    if not definition then
        return nil
    end
    if behaviour then
        definition.behaviour = behaviour
    end
    if type(extra.profession) == "string" and extra.profession ~= "" then
        definition.professionLabel = extra.profession
    end
    local maxQty = WBF.Format.AsNumber(extra.maximum) or (info and WBF.Format.AsNumber(info.maxQuantity))
    if maxQty and maxQty > 0 then
        definition.maximum = maxQty
    end
    if info then
        RememberIcon(definition, info.iconFileID)
        RememberName(definition, info.name)
        ApplyCurrencyFlags(definition, info)
        if behaviour then
            definition.behaviour = behaviour
        end
    end
    PersistDefinition(definition)
    local quantity = info and WBF.Format.AsNumber(info.quantity) or nil
    definition.meterCurrent = quantity
    if quantity ~= nil then
        local state = StateFor(definition.key)
        state.currentBalance = quantity
        state.acceptedBalance = quantity
        if definition.maximum then
            state.maximum = definition.maximum
        end
        state.lastObservedAt = WBF.Time.Now()
        local guid = CurrentGUID()
        if guid and not IsWarbandCurrency(definition) and state.characters[guid] == nil then
            state.characters[guid] = quantity
            TouchScan(state, guid, "character_scan")
        elseif guid and IsWarbandCurrency(definition) and CanonicalBalance(state) == nil then
            WriteCanonical(state, definition, quantity, WBF.Time.Now())
        end
    end
    return definition
end

function WBF.Resources.ResetHistory(text)
    local definition = WBF.Resources.Find(text)
    if not definition or not WBF.Database.IsReady() then
        return nil
    end
    local db = WBF.Database.Get()
    local kept = {}
    local events = db.events or {}
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if not (event.eventType == WBF.EventType.Resource and meta.resourceKey == definition.key) then
            kept[#kept + 1] = event
        end
    end
    db.events = kept
    local state = StateFor(definition.key)
    state.acceptedBalance = nil
    state.currentBalance = nil
    state.previousBalance = nil
    state.accountWide = nil
    state.openingBalance = nil
    state.account = nil
    state.characters = {}
    state.lastObservedAt = nil
    state.observed = {}
    pendingObserve[definition.key] = nil
    return definition
end

function WBF.Resources.RegisterBus(bus)
    LoadWatched()
    EnsureDynamicCurrencies()
    bus:On("CURRENCY_DISPLAY_UPDATE", function(currencyType, quantity, quantityChange, quantityGainSource, destroyReason)
        local definition = FindCurrency(currencyType)
        if not definition then
            local info
            if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                local ok, result = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyType)
                if ok then
                    info = result
                end
            end
            definition = EnsureDiscoveredCurrency(currencyType, info, nil, quantity)
        end
        if not definition then
            return
        end
        RefreshActive()
        NoteCurrency(definition, quantity, quantityChange, quantityGainSource, destroyReason)
    end)
    bus:On("BAG_UPDATE_DELAYED", function()
        ScheduleItemScan()
    end)
    bus:On("PLAYERBANKSLOTS_CHANGED", function()
        ScheduleItemScan()
    end)
    bus:On("GET_ITEM_INFO_RECEIVED", function()
        ScheduleItemScan()
    end)
    bus:On("CALENDAR_UPDATE_EVENT_LIST", function()
        if not ScanCalendar() then
            RefreshActive()
        end
    end)
    bus:On("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", function()
        accountCursor = 1
        if scanRunning then
            table.insert(jobs, 1, AccountApplyStep)
            return
        end
        jobs = { AccountApplyStep }
        scanRunning = true
        SetStatus("refreshing")
        Pump()
    end)
    bus:On("CURRENCY_TRANSFER_LOG_UPDATE", function()
        IngestTransferLog()
    end)
    bus:On("CURRENCY_TRANSFER_SUCCESS", function()
        RequestAccount()
    end)
    bus:On("PLAYER_ENTERING_WORLD", function()
        WBF.Resources.BeginSettle()
        WBF.Resources.Refresh()
    end)
end
