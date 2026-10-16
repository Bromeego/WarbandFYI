local _, WBF = ...

WBF.Reputation = {}

-- Reputation chat was made readable again in 12.0.7. The localized standing
-- strings carry the faction and the amount at the moment the gain happens.
-- Combat text is a second source for the same gain, so the two are collapsed
-- when they arrive together. Renown rank changes come from their own event.

local SPECS = {
    { global = "FACTION_STANDING_INCREASED_ACH_BONUS_ACCOUNT_WIDE", name = 1, amount = 2, bonus = 3, account = true },
    { global = "FACTION_STANDING_INCREASED_ACH_BONUS", name = 1, amount = 2, bonus = 3 },
    { global = "FACTION_STANDING_INCREASED_ACCOUNT_WIDE", name = 1, amount = 2, account = true },
    { global = "FACTION_STANDING_INCREASED", name = 1, amount = 2 },
    { global = "FACTION_STANDING_DECREASED_ACCOUNT_WIDE", name = 1, amount = 2, account = true, loss = true },
    { global = "FACTION_STANDING_DECREASED", name = 1, amount = 2, loss = true },
}

local compiled = nil
local recent = {}
local factionAt = {}

local function Patterns()
    if compiled then
        return compiled
    end
    compiled = {}
    for index = 1, #SPECS do
        local spec = SPECS[index]
        local built = WBF.Format.CompileGlobal(spec.global)
        if built then
            compiled[#compiled + 1] = { spec = spec, built = built }
        end
    end
    return compiled
end

local function Plain(text)
    if type(text) ~= "string" then
        return nil
    end
    if issecretvalue and issecretvalue(text) then
        return nil
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return strtrim(text)
end

local function AlreadySeen(faction, amount)
    local now = WBF.Time.Now()
    local key = faction .. ":" .. tostring(amount)
    local seen = recent[key]
    recent[key] = now
    factionAt[faction] = now
    local count = 0
    for _ in pairs(recent) do
        count = count + 1
    end
    if count > 40 then
        for other, at in pairs(recent) do
            if now - at > 10 then
                recent[other] = nil
            end
        end
    end
    return seen and now - seen < 3
end

local function Record(faction, amount, account, bonus)
    if type(faction) ~= "string" or faction == "" then
        return
    end
    amount = tonumber(amount)
    if not amount or amount == 0 then
        return
    end
    amount = math.floor(amount + 0.5)
    if AlreadySeen(faction, amount) then
        return
    end

    local prefix = account and "Warband reputation with " or "Reputation with "
    WBF.Events.Add({
        category = WBF.Category.Reputation,
        eventType = WBF.EventType.Reputation,
        text = prefix .. faction .. " " .. WBF.Format.Signed(amount),
        delta = amount,
        meta = {
            faction = faction,
            accountWide = account and true or false,
            bonus = bonus,
            iconAtlas = "MajorFactions_MapIcons_Centaur_Major",
        },
    })
end

local function FromChat(text)
    text = Plain(text)
    if not text or text == "" then
        return
    end
    local patterns = Patterns()
    for index = 1, #patterns do
        local row = patterns[index]
        local values = WBF.Format.MatchGlobal(text, row.built)
        if values then
            local spec = row.spec
            local amount = values[spec.amount]
            if spec.loss and amount and amount > 0 then
                amount = -amount
            end
            Record(values[spec.name], amount, spec.account, values[spec.bonus])
            return
        end
    end
end

-- Renown identity is the major faction ID. Display names are labels only.
-- A missing or generic "Renown" name must not collapse several tracks into
-- one baseline. The event payload's old and new levels are not compared
-- across factions; each ID is compared with its own stored level.
WBF.Reputation.CONFIRM_SECONDS = 3
local SETTLE_SECONDS = 10
local settleStart
local settleUntil
local confirmScheduled = {}
local confirmAttempts = {}

local function UsableName(name)
    name = WBF.Format.PlainString(name)
    if not name then
        return nil
    end
    if name:lower() == "renown" then
        return nil
    end
    return name
end

local function RenownRoot()
    local db = WBF.Database.Get()
    local raw = db.renown
    if type(raw) == "table" and raw.version == 1 and type(raw.byFaction) == "table" then
        return raw
    end
    local byFaction = {}
    if type(raw) == "table" then
        local function Keep(key, value)
            local id = tonumber(key)
            if id and type(value) == "table" and type(value.level) == "number" then
                byFaction[id] = value
                if value.establishedAt == nil then
                    value.establishedAt = 0
                end
            end
        end
        if type(raw.byFaction) == "table" then
            for key, value in pairs(raw.byFaction) do
                Keep(key, value)
            end
        end
        for key, value in pairs(raw) do
            if key ~= "byFaction" and key ~= "version" and key ~= "expansion" then
                Keep(key, value)
            end
        end
    end
    db.renown = {
        version = 1,
        byFaction = byFaction,
        expansion = type(raw) == "table" and raw.expansion or nil,
    }
    return db.renown
end

local function FactionRow(root, majorFactionID)
    local row = root.byFaction[majorFactionID]
    if type(row) ~= "table" then
        return nil
    end
    return row
end

local function RememberName(row, snapshot)
    local raw = WBF.Format.PlainString(snapshot.name)
    if raw then
        row.rawName = raw
    end
    local usable = UsableName(snapshot.name)
    if usable then
        row.name = usable
    end
end

local function RememberMeta(row, snapshot)
    RememberName(row, snapshot)
    if snapshot.maxLevel ~= nil then
        row.maxLevel = snapshot.maxLevel
    end
    if snapshot.accountWide ~= nil then
        row.accountWide = snapshot.accountWide
    end
    if snapshot.unlocked ~= nil then
        row.unlocked = snapshot.unlocked
    end
    if snapshot.expansionID ~= nil then
        row.expansionID = snapshot.expansionID
    end
    row.reputationFactionID = snapshot.reputationFactionID or row.reputationFactionID
end

local function Settling(now, row)
    return settleStart ~= nil and settleUntil ~= nil and now <= settleUntil and row.establishedAt ~= nil and row.establishedAt >= settleStart
end

local function Emit(majorFactionID, row, previous, newLevel)
    if not row.name or previous == nil or newLevel == nil or previous == newLevel then
        return false
    end
    row.reported = newLevel
    if not WBF.Events or not WBF.Events.Add then
        return true
    end
    WBF.Events.Add({
        category = WBF.Category.Reputation,
        eventType = WBF.EventType.Renown,
        text = "Renown with " .. row.name .. "  " .. WBF.Format.Progression(previous, newLevel),
        previous = previous,
        new = newLevel,
        delta = newLevel - previous,
        meta = {
            faction = row.name,
            majorFactionID = majorFactionID,
            accountWide = row.accountWide,
            confirmed = newLevel < previous or nil,
            iconAtlas = "MajorFactions_MapIcons_Centaur_Major",
        },
    })
    return true
end

local function PresentIfNamed(majorFactionID, row)
    if not row.name or row.pending or row.reported == nil or row.reported == row.level then
        return false
    end
    return Emit(majorFactionID, row, row.reported, row.level)
end

function WBF.Reputation.BeginSettle()
    local now = WBF.Time.Now()
    if settleUntil and now <= settleUntil then
        return
    end
    settleStart = now
    settleUntil = now + SETTLE_SECONDS
end

function WBF.Reputation.Observe(majorFactionID, snapshot, now)
    majorFactionID = WBF.Format.AsNumber(majorFactionID)
    if not majorFactionID or type(snapshot) ~= "table" or not WBF.Database.IsReady() then
        return nil
    end
    local level = WBF.Format.AsNumber(snapshot.level)
    if level == nil then
        return nil
    end
    level = math.floor(level)
    now = now or WBF.Time.Now()
    local root = RenownRoot()
    local row = FactionRow(root, majorFactionID)
    if not row then
        row = {
            majorFactionID = majorFactionID,
            level = level,
            reported = level,
            establishedAt = now,
        }
        RememberMeta(row, snapshot)
        root.byFaction[majorFactionID] = row
        return { action = "baseline", majorFactionID = majorFactionID, level = level, present = false }
    end
    row.majorFactionID = majorFactionID
    RememberMeta(row, snapshot)
    if Settling(now, row) then
        row.level = level
        row.reported = level
        row.pending = nil
        return { action = "baseline", majorFactionID = majorFactionID, level = level, present = false }
    end
    if level == row.level then
        row.pending = nil
        local presented = PresentIfNamed(majorFactionID, row)
        return {
            action = presented and "increase" or "unchanged",
            majorFactionID = majorFactionID,
            level = level,
            present = presented,
        }
    end
    if level > row.level then
        row.level = level
        row.pending = nil
        local presented = PresentIfNamed(majorFactionID, row)
        return {
            action = presented and "increase" or "deferred",
            majorFactionID = majorFactionID,
            level = level,
            present = presented,
        }
    end
    local pending = row.pending
    if type(pending) == "table" and pending.level == level and (now - (pending.since or now)) >= WBF.Reputation.CONFIRM_SECONDS then
        row.level = level
        row.pending = nil
        local presented = PresentIfNamed(majorFactionID, row)
        return {
            action = presented and "decrease" or "deferred",
            majorFactionID = majorFactionID,
            level = level,
            present = presented,
        }
    end
    if type(pending) ~= "table" or pending.level ~= level then
        row.pending = { level = level, since = now }
    end
    return { action = "pending", majorFactionID = majorFactionID, level = row.level, present = false }
end

local function MaxRenown(majorFactionID, data)
    local highest
    if type(data) == "table" then
        highest = WBF.Format.AsNumber(data.renownLevelMax) or WBF.Format.AsNumber(data.maxLevel)
    end
    if not C_MajorFactions or not C_MajorFactions.GetRenownLevels then
        return highest
    end
    local ok, levels = pcall(C_MajorFactions.GetRenownLevels, majorFactionID)
    if not ok or type(levels) ~= "table" then
        return highest
    end
    local found = highest or 0
    for index = 1, #levels do
        local entry = levels[index]
        local level = type(entry) == "table" and WBF.Format.AsNumber(entry.level) or nil
        if level and level > found then
            found = level
        end
    end
    if found > 0 then
        return found
    end
    if #levels > 0 and not highest then
        return #levels
    end
    return highest
end

local function ReadSnapshot(majorFactionID)
    if not C_MajorFactions or not C_MajorFactions.GetMajorFactionData then
        return nil
    end
    local ok, data = pcall(C_MajorFactions.GetMajorFactionData, majorFactionID)
    if not ok or type(data) ~= "table" then
        return nil
    end
    local level = WBF.Format.AsNumber(data.renownLevel)
    if level == nil then
        return nil
    end
    local reputationID = WBF.Format.AsNumber(data.factionID)
    return {
        level = level,
        name = data.name,
        maxLevel = MaxRenown(majorFactionID, data),
        accountWide = WBF.Format.AsBoolean(data.isAccountWide),
        unlocked = WBF.Format.AsBoolean(data.isUnlocked),
        expansionID = WBF.Format.AsNumber(data.expansionID),
        reputationFactionID = reputationID ~= majorFactionID and reputationID or nil,
        journey = WBF.Format.AsBoolean(data.isJourney),
    }
end

local function ScheduleRefresh(majorFactionID)
    if confirmScheduled[majorFactionID] then
        return
    end
    confirmAttempts[majorFactionID] = (confirmAttempts[majorFactionID] or 0) + 1
    if confirmAttempts[majorFactionID] > 4 then
        return
    end
    if not C_Timer or not C_Timer.After then
        return
    end
    confirmScheduled[majorFactionID] = true
    C_Timer.After(WBF.Reputation.CONFIRM_SECONDS, function()
        confirmScheduled[majorFactionID] = nil
        WBF.Reputation.RefreshFaction(majorFactionID)
    end)
end

function WBF.Reputation.RefreshFaction(majorFactionID)
    majorFactionID = WBF.Format.AsNumber(majorFactionID)
    if not majorFactionID or not WBF.Database.IsReady() then
        return nil
    end
    local snapshot = ReadSnapshot(majorFactionID)
    if not snapshot then
        ScheduleRefresh(majorFactionID)
        return nil
    end
    confirmAttempts[majorFactionID] = nil
    local result = WBF.Reputation.Observe(majorFactionID, snapshot, WBF.Time.Now())
    if result and result.action == "pending" then
        ScheduleRefresh(majorFactionID)
    end
    return result
end

local function FactionIDs()
    local ids = {}
    local seen = {}
    local function Add(value)
        local id = WBF.Format.AsNumber(value)
        if id and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    local function Take(list)
        if type(list) ~= "table" then
            return
        end
        for index = 1, #list do
            Add(list[index])
        end
    end
    if not C_MajorFactions or not C_MajorFactions.GetMajorFactionIDs then
        return ids
    end
    local ok, list = pcall(C_MajorFactions.GetMajorFactionIDs)
    if ok then
        Take(list)
    end
    if #ids == 0 then
        for expansion = 0, 15 do
            local expandedOK, expanded = pcall(C_MajorFactions.GetMajorFactionIDs, expansion)
            if expandedOK then
                Take(expanded)
            end
        end
    end
    return ids
end

function WBF.Reputation.Scan()
    if not WBF.Database.IsReady() then
        return
    end
    local root = RenownRoot()
    if type(GetExpansionLevel) == "function" then
        local ok, expansion = pcall(GetExpansionLevel)
        if ok and type(expansion) == "number" then
            root.expansion = expansion
        end
    end
    local ids = FactionIDs()
    local now = WBF.Time.Now()
    for index = 1, #ids do
        local snapshot = ReadSnapshot(ids[index])
        if snapshot then
            local result = WBF.Reputation.Observe(ids[index], snapshot, now)
            if result and result.action == "pending" then
                ScheduleRefresh(ids[index])
            end
        end
    end
end

-- The event arguments are not the source of truth. A burst of updates can
-- report one track's previous rank against another track. Read this faction
-- and compare it only with the baseline stored for this ID.
function WBF.Reputation.OnRenownChanged(majorFactionID)
    return WBF.Reputation.RefreshFaction(majorFactionID)
end

local function DebugFactionLine(majorFactionID, snapshot, row)
    local name = snapshot and WBF.Format.PlainString(snapshot.name) or (row and (row.rawName or row.name)) or ""
    local level = snapshot and snapshot.level or (row and row.level)
    local maxLevel = (snapshot and snapshot.maxLevel) or (row and row.maxLevel)
    local account = snapshot and snapshot.accountWide
    if account == nil and row then
        account = row.accountWide
    end
    local unlocked = snapshot and snapshot.unlocked
    if unlocked == nil and row then
        unlocked = row.unlocked
    end
    local journey = snapshot and snapshot.journey
    local function Flag(value)
        if value == nil then
            return "?"
        end
        return value and "yes" or "no"
    end
    print(table.concat({
        tostring(majorFactionID),
        name ~= "" and name or "(unnamed)",
        level == nil and "?" or tostring(level),
        maxLevel == nil and "?" or tostring(maxLevel),
        Flag(account),
        Flag(unlocked),
        Flag(journey),
        row and tostring(row.level) or "-",
    }, " | "))
end

function WBF.Reputation.DebugDump()
    if not WBF.Database.IsReady() then
        print("|cffd4af37WarbandFYI|r renown data is not ready.")
        return
    end
    local root = RenownRoot()
    local seen = {}
    local ids = FactionIDs()
    print("|cffd4af37WarbandFYI|r renown")
    print("factionID | api name | level | max | account | unlocked | journey | stored")
    for index = 1, #ids do
        local id = ids[index]
        seen[id] = true
        DebugFactionLine(id, ReadSnapshot(id), root.byFaction[id])
    end
    local stored = {}
    for id in pairs(root.byFaction) do
        if not seen[id] then
            stored[#stored + 1] = id
        end
    end
    table.sort(stored)
    for index = 1, #stored do
        DebugFactionLine(stored[index], nil, root.byFaction[stored[index]])
    end
end

function WBF.Reputation.Register(bus)
    bus:On("CHAT_MSG_COMBAT_FACTION_CHANGE", function(text)
        FromChat(text)
    end)

    bus:On("COMBAT_TEXT_UPDATE", function(combatType)
        if combatType ~= "FACTION" then
            return
        end
        local faction, amount
        if C_CombatText and C_CombatText.GetCurrentEventInfo then
            faction, amount = C_CombatText.GetCurrentEventInfo()
        elseif GetCurrentCombatTextEventInfo then
            faction, amount = GetCurrentCombatTextEventInfo()
        end
        if issecretvalue and ((faction and issecretvalue(faction)) or (amount and issecretvalue(amount))) then
            return
        end
        if type(faction) ~= "string" then
            return
        end
        local seenAt = factionAt[faction]
        if seenAt and WBF.Time.Now() - seenAt < 3 then
            return
        end
        Record(faction, tonumber(amount), false, nil)
    end)

    bus:On("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", function(majorFactionID)
        WBF.Reputation.OnRenownChanged(majorFactionID)
    end)

    bus:On("MAJOR_FACTION_UNLOCKED", function(majorFactionID)
        WBF.Reputation.RefreshFaction(majorFactionID)
    end)

    bus:On("PLAYER_ENTERING_WORLD", function()
        WBF.Reputation.BeginSettle()
        WBF.Reputation.Scan()
    end)
end
