local _, WBF = ...

WBF.GoldTracker = {}

-- Personal gold (GetMoney) is tracked per character, keyed by UnitGUID.
-- The first balance seen for a character in a session is a baseline only.
-- Later readings are compared with that same character's last balance.
-- Session Net Gold is the sum of those per-character deltas.
--
-- State lives on the session so a /reload keeps the baseline and the net.
-- goldByCharacter[guid] = { baseline, lastMoney, netChange, establishedAt }
-- goldLedger = { { at, guid, delta, source? }, ... }  -- real changes only, no baselines
-- db.goldLast[guid] remembers the last observed balance across sessions.
-- A gap before the next session is one betweenSessions ledger line.
--
-- A missing goldByCharacter table is older session data. It is rebuilt from
-- that session's own per-character money snapshots. An empty table means this
-- session already started tracking and must not be rebuilt.

local BETWEEN_SESSIONS = "betweenSessions"

local lastObservedGuid = nil

local function Log(message)
    if WBF.Debug and WBF.Debug.Log then
        WBF.Debug.Log(message)
    end
end

local function MoneyText(copper, signed)
    if WBF.Format and WBF.Format.Gold then
        return WBF.Format.Gold(copper, signed)
    end
    return tostring(copper)
end

local function CharacterName(guid)
    local character = WBF.Characters and WBF.Characters.Get and WBF.Characters.Get(guid)
    if character and type(character.name) == "string" and character.name ~= "" then
        return character.name
    end
    return "character"
end

local function ValidGuid(guid)
    return type(guid) == "string" and guid ~= ""
end

local function ValidMoney(money)
    return type(money) == "number"
end

local function Database()
    local db = WBF.Database and WBF.Database.Get and WBF.Database.Get()
    if type(db) ~= "table" then
        return { snapshots = {}, sessions = {} }
    end
    return db
end

local function ActiveSession()
    if not WBF.Sessions or not WBF.Sessions.GetActive then
        return nil
    end
    return WBF.Sessions.GetActive()
end

local function InRange(at, startAt, endAt)
    return type(at) == "number" and at >= startAt and at <= endAt
end

local function Overlaps(session, startAt, endAt)
    local sessionStart = session.startedAt or 0
    local sessionEnd = session.endedAt or endAt
    if sessionEnd < sessionStart then
        sessionEnd = sessionStart
    end
    return sessionEnd >= startAt and sessionStart <= endAt
end

local function SnapshotBelongs(snapshot, session)
    if snapshot.money == nil or snapshot.sessionId ~= session.id or not snapshot.guid then
        return false
    end
    if session.sample then
        return snapshot.sample == true
    end
    return not snapshot.sample
end

local function Derive(session, db)
    local grouped = {}
    local snapshots = db.snapshots or {}
    for index = 1, #snapshots do
        local snapshot = snapshots[index]
        if SnapshotBelongs(snapshot, session) then
            local list = grouped[snapshot.guid]
            if not list then
                list = {}
                grouped[snapshot.guid] = list
            end
            list[#list + 1] = { snapshot = snapshot, index = index }
        end
    end

    for guid, list in pairs(grouped) do
        table.sort(list, function(a, b)
            if a.snapshot.at == b.snapshot.at then
                return a.index < b.index
            end
            return (a.snapshot.at or 0) < (b.snapshot.at or 0)
        end)
        local first = list[1].snapshot
        local state = {
            baseline = first.money,
            lastMoney = first.money,
            netChange = 0,
            establishedAt = first.at,
        }
        session.goldByCharacter[guid] = state
        for index = 2, #list do
            local point = list[index].snapshot
            local delta = point.money - state.lastMoney
            if delta ~= 0 then
                state.netChange = state.netChange + delta
                state.lastMoney = point.money
                session.goldLedger[#session.goldLedger + 1] = {
                    at = point.at,
                    guid = guid,
                    delta = delta,
                }
            end
        end
    end
end

-- Nil goldByCharacter is pre-fix session data and is rebuilt once.
-- A table, even an empty one, means this session is already tracking.
local function MarkSummaryDirty()
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
end

local function GoldMemory()
    local db = Database()
    if type(db.goldLast) ~= "table" then
        db.goldLast = {}
    end
    return db.goldLast
end

local function RememberedMoney(guid)
    local money = GoldMemory()[guid]
    if type(money) ~= "number" then
        return nil
    end
    return money
end

local function RememberMoney(guid, money)
    if ValidGuid(guid) and ValidMoney(money) then
        GoldMemory()[guid] = money
    end
end

local function Prepare(session, db)
    if session.goldByCharacter then
        if not session.goldLedger then
            session.goldLedger = {}
        end
        return
    end
    session.goldByCharacter = {}
    session.goldLedger = {}
    Derive(session, db)
end

local function HasRealMoney(db)
    local snapshots = db.snapshots or {}
    for index = 1, #snapshots do
        local snapshot = snapshots[index]
        if snapshot.money ~= nil and not snapshot.sample then
            return true
        end
    end
    local sessions = db.sessions or {}
    for index = 1, #sessions do
        local session = sessions[index]
        if session and not session.sample and session.goldByCharacter and next(session.goldByCharacter) then
            return true
        end
    end
    if WBF.Characters and WBF.Characters.GetCurrent then
        local live = WBF.Characters.GetCurrent()
        if live and live.money ~= nil and not live.sample then
            return true
        end
    end
    return false
end

function WBF.GoldTracker.InitializeCharacter(guid, money)
    local session = ActiveSession()
    if not session or not ValidGuid(guid) or not ValidMoney(money) then
        return nil
    end
    Prepare(session, Database())
    local state = session.goldByCharacter[guid]
    if state then
        return state
    end
    local now = WBF.Time.Now()
    local remembered = RememberedMoney(guid)
    if remembered ~= nil and remembered ~= money then
        local delta = money - remembered
        state = {
            baseline = remembered,
            lastMoney = money,
            netChange = delta,
            establishedAt = now,
        }
        session.goldByCharacter[guid] = state
        session.goldLedger[#session.goldLedger + 1] = {
            at = now,
            guid = guid,
            delta = delta,
            source = BETWEEN_SESSIONS,
        }
        lastObservedGuid = guid
        RememberMoney(guid, money)
        MarkSummaryDirty()
        Log("[Gold] " .. CharacterName(guid) .. " between sessions: " .. MoneyText(delta, true))
        return state
    end
    state = {
        baseline = money,
        lastMoney = money,
        netChange = 0,
        establishedAt = now,
    }
    session.goldByCharacter[guid] = state
    lastObservedGuid = guid
    RememberMoney(guid, money)
    Log("[Gold] Established baseline for " .. CharacterName(guid) .. ": " .. MoneyText(money))
    return state
end

function WBF.GoldTracker.HandleMoneyChanged(guid, money)
    local session = ActiveSession()
    if not session or not ValidGuid(guid) or not ValidMoney(money) then
        return 0
    end
    Prepare(session, Database())
    if not session.goldByCharacter[guid] then
        local state = WBF.GoldTracker.InitializeCharacter(guid, money)
        return state and state.netChange or 0
    end
    if lastObservedGuid ~= guid then
        lastObservedGuid = guid
        Log("[Gold] Resuming " .. CharacterName(guid) .. " baseline")
    end
    local state = session.goldByCharacter[guid]
    local delta = money - state.lastMoney
    if delta == 0 then
        RememberMoney(guid, money)
        return 0
    end
    state.netChange = (state.netChange or 0) + delta
    state.lastMoney = money
    session.goldLedger[#session.goldLedger + 1] = {
        at = WBF.Time.Now(),
        guid = guid,
        delta = delta,
    }
    RememberMoney(guid, money)
    MarkSummaryDirty()
    Log("[Gold] " .. CharacterName(guid) .. " change: " .. MoneyText(delta, true))
    return delta
end

function WBF.GoldTracker.Observe(guid, money)
    local session = ActiveSession()
    if not session or not ValidGuid(guid) or not ValidMoney(money) then
        return 0
    end
    Prepare(session, Database())
    -- Entering the world can report 0 gold, including just after /reload when
    -- trustMoney has been cleared. That reading is not a spend when a positive
    -- balance is already known. A real empty wallet still baselines at 0.
    if money == 0 and not (WBF.Economy and WBF.Economy.trustMoney) then
        local state = session.goldByCharacter[guid]
        local knownPositive = state and (state.lastMoney or 0) > 0
        if not knownPositive then
            local character = WBF.Characters and WBF.Characters.Get and WBF.Characters.Get(guid)
            knownPositive = character and (character.money or 0) > 0
        end
        if knownPositive then
            return 0
        end
    end
    if not session.goldByCharacter[guid] then
        local state = WBF.GoldTracker.InitializeCharacter(guid, money)
        return state and state.netChange or 0
    end
    return WBF.GoldTracker.HandleMoneyChanged(guid, money)
end

function WBF.GoldTracker.Reconcile()
    if not GetMoney or not WBF.Characters or not WBF.Characters.GetGuid then
        return 0
    end
    local guid = WBF.Characters.GetGuid()
    local money = WBF.Format and WBF.Format.AsNumber and WBF.Format.AsNumber(GetMoney()) or nil
    if not ValidGuid(guid) or not ValidMoney(money) then
        return 0
    end
    return WBF.GoldTracker.Observe(guid, money)
end

function WBF.GoldTracker.GetCharacterNet(guid)
    local session = ActiveSession()
    if not session or not ValidGuid(guid) then
        return 0
    end
    Prepare(session, Database())
    local state = session.goldByCharacter[guid]
    return state and state.netChange or 0
end

function WBF.GoldTracker.GetSessionNet()
    local session = ActiveSession()
    if not session then
        return 0
    end
    Prepare(session, Database())
    local net = 0
    for _, state in pairs(session.goldByCharacter) do
        net = net + (state.netChange or 0)
    end
    return net
end

-- Period totals and per-character rows both come from goldLedger, so they
-- cannot drift. Baselines contribute nothing. Sample gold is left out once
-- any real balance exists, so a preview cannot invent a gain or a loss.
function WBF.GoldTracker.Collect(db, startAt, endAt)
    local byGuid = {}
    local offlineByGuid = {}
    local net = 0
    local tracked = false
    if type(db) ~= "table" or type(startAt) ~= "number" or type(endAt) ~= "number" then
        return net, tracked, byGuid, offlineByGuid
    end
    local real = HasRealMoney(db)
    local sessions = db.sessions or {}
    for index = 1, #sessions do
        local session = sessions[index]
        if session and Overlaps(session, startAt, endAt) and not (session.sample and real) then
            Prepare(session, db)
            for _, state in pairs(session.goldByCharacter) do
                if InRange(state.establishedAt, startAt, endAt) then
                    tracked = true
                end
            end
            local ledger = session.goldLedger or {}
            for entryIndex = 1, #ledger do
                local entry = ledger[entryIndex]
                if entry and InRange(entry.at, startAt, endAt) and entry.guid then
                    tracked = true
                    local delta = entry.delta or 0
                    net = net + delta
                    byGuid[entry.guid] = (byGuid[entry.guid] or 0) + delta
                    if entry.source == BETWEEN_SESSIONS then
                        offlineByGuid[entry.guid] = (offlineByGuid[entry.guid] or 0) + delta
                    end
                end
            end
        end
    end
    return net, tracked, byGuid, offlineByGuid
end

-- Return exact gold ledger changes for a bounded period. The graph built from
-- these rows is cumulative *net change*, not the character's absolute wallet;
-- baselines are intentionally excluded so first observation never looks like
-- income.
local function TrendLedger(db, startAt, endAt, guid)
    local rows = {}
    if type(db) ~= "table" or type(startAt) ~= "number" or type(endAt) ~= "number" then
        return rows
    end
    local real = HasRealMoney(db)
    local sessions = db.sessions or {}
    local sequence = 0
    for index = 1, #sessions do
        local session = sessions[index]
        if session and Overlaps(session, startAt, endAt) and not (session.sample and real) then
            Prepare(session, db)
            local ledger = session.goldLedger or {}
            for entryIndex = 1, #ledger do
                local entry = ledger[entryIndex]
                if entry and InRange(entry.at, startAt, endAt) and entry.guid and (not guid or entry.guid == guid) then
                    sequence = sequence + 1
                    local stored = WBF.Characters and WBF.Characters.Get and WBF.Characters.Get(entry.guid) or nil
                    rows[#rows + 1] = {
                        at = entry.at,
                        guid = entry.guid,
                        delta = entry.delta or 0,
                        source = entry.source,
                        name = stored and stored.name or CharacterName(entry.guid),
                        classFile = stored and stored.classFile or nil,
                        sequence = sequence,
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.at == b.at then
            return (a.sequence or 0) < (b.sequence or 0)
        end
        return (a.at or 0) < (b.at or 0)
    end)
    return rows
end

local function TrendFromRows(rows, startAt, endAt, guid, title, allTime)
    local running = 0
    local earned = 0
    local spent = 0
    local points = {}
    local activity = {}
    for index = 1, #rows do
        local row = rows[index]
        local delta = tonumber(row.delta) or 0
        running = running + delta
        if delta > 0 then
            earned = earned + delta
        elseif delta < 0 then
            spent = spent - delta
        end
        points[#points + 1] = {
            at = row.at,
            value = running,
            delta = delta,
            name = row.name,
            classFile = row.classFile,
            source = row.source,
            label = row.label,
            monthly = row.monthly,
        }
        activity[#activity + 1] = {
            at = row.at,
            delta = delta,
            running = running,
            name = row.name,
            classFile = row.classFile,
            source = row.source,
            label = row.label,
            monthly = row.monthly,
        }
    end
    return {
        characterGUID = guid,
        title = title,
        allTime = allTime == true,
        startAt = startAt,
        endAt = endAt,
        net = running,
        earned = earned,
        spent = spent,
        changes = #rows,
        points = points,
        activity = activity,
    }
end

function WBF.GoldTracker.Trend(startAt, endAt, guid, title)
    local db = Database()
    local rows = TrendLedger(db, startAt, endAt, guid)
    return TrendFromRows(rows, startAt, endAt, guid, title, false)
end

local function RollupGoldForGuid(rollup, guid)
    if not guid then
        return type(rollup.goldNet) == "number" and rollup.goldNet or 0
    end
    local characters = rollup.characters or {}
    for index = 1, #characters do
        local row = characters[index]
        if row and row.guid == guid then
            local counts = row.counts or {}
            return type(counts.gold) == "number" and counts.gold or 0
        end
    end
    return 0
end

-- All-time gold uses one compact point per finalized month, then the current
-- month's live ledger. This stays small even if WarbandFYI is used for years:
-- roughly 12 historical points per year instead of every PLAYER_MONEY event.
function WBF.GoldTracker.AllTimeTrend(guid)
    local db = Database()
    local now = WBF.Time.Now()
    local rows = {}
    local history = type(db.monthHistory) == "table" and db.monthHistory or {}
    for _, rollup in pairs(history) do
        if type(rollup) == "table" and rollup.finalized == true and rollup.goldTracked == true then
            local delta = RollupGoldForGuid(rollup, guid)
            rows[#rows + 1] = {
                at = rollup.endAt or rollup.startAt or now,
                delta = delta,
                label = (type(rollup.year) == "number" and type(rollup.month) == "number") and WBF.Time.MonthTitle(rollup.year, rollup.month) or "Month",
                monthly = true,
            }
        end
    end
    table.sort(rows, function(a, b)
        return (a.at or 0) < (b.at or 0)
    end)

    local currentStart = WBF.Time.StartOfMonth(now)
    local net, tracked, byGuid = WBF.GoldTracker.Collect(db, currentStart, now)
    local currentDelta = guid and (byGuid[guid] or 0) or net
    if tracked or currentDelta ~= 0 then
        local currentYear, currentMonth = WBF.Time.CurrentMonth(now)
        rows[#rows + 1] = {
            at = now,
            delta = currentDelta,
            label = WBF.Time.MonthTitle(currentYear, currentMonth),
            monthly = true,
        }
    end

    local startAt = rows[1] and rows[1].at or currentStart
    local model = TrendFromRows(rows, startAt, now, guid, "All Time", true)
    model.months = #rows
    model.firstAt = rows[1] and rows[1].at or nil

    -- Keep the activity list useful: show recent exact ledger changes while raw
    -- retention still has them, rather than pretending monthly rollups are
    -- individual transactions.
    local cutoff = WBF.Database and WBF.Database.RetentionCutoff and WBF.Database.RetentionCutoff(now) or currentStart
    local recent = TrendLedger(db, cutoff or currentStart, now, guid)
    model.recentActivity = recent
    return model
end
