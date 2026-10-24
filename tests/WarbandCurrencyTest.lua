-- Warband currency ledger. Run from the repo root:
--   lua tests/WarbandCurrencyTest.lua

local script = arg and arg[0] or "tests/WarbandCurrencyTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

if type(time) ~= "function" then
    time = os.time
end

if type(date) ~= "function" then
    date = os.date
end

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

local WBF = {}
local db
local now
local nextId
local failures = 0

local function resetDb()
    -- Claims ignore a repeat of the same balance within 3 seconds of addon time.
    -- A reset has to move the clock or the next scenario collides with the last.
    now = (now or 1750000000) + 100
    nextId = 1
    db = {
        config = {},
        events = {},
        characters = {
            A = { guid = "A", name = "Miranora", discovered = true },
            B = { guid = "B", name = "Miraqt", discovered = true },
            C = { guid = "C", name = "Taxableyawl", discovered = true },
        },
        resources = nil,
    }
end

WBF.Time = {
    Now = function()
        return now
    end,
    StartOfDay = function(at)
        return at - (at % 86400)
    end,
    StartOfWeek = function(at)
        return at - (at % (7 * 86400))
    end,
    Clock = function()
        return "12:42 PM"
    end,
}
WBF.Debug = { Log = function() end }
WBF.Database = {
    IsReady = function()
        return true
    end,
    Get = function()
        return db
    end,
    AllocEventId = function()
        local id = nextId
        nextId = nextId + 1
        return id
    end,
}
WBF.Characters = {
    GetCurrent = function()
        return db.characters.A
    end,
    Get = function(guid)
        return db.characters[guid]
    end,
    IsDiscovered = function()
        return true
    end,
}
WBF.EventType = { Resource = "resource" }
WBF.Category = { Resource = "resource" }
WBF.Events = {
    Add = function(partial)
        local event = {
            id = WBF.Database.AllocEventId(),
            at = partial.at or now,
            guid = partial.guid,
            category = partial.category,
            eventType = partial.eventType,
            delta = partial.delta,
            previous = partial.previous,
            new = partial.new,
            text = partial.text,
            meta = partial.meta or {},
        }
        db.events[#db.events + 1] = event
        return event
    end,
}
WBF.ResourceMeta = {
    For = function()
        return { era = "cross_expansion", label = "Cross-Expansion / Events", status = "active", kind = "evergreen" }
    end,
    Label = function()
        return "Cross-Expansion / Events"
    end,
}

loadAddon("Utils/Format.lua", WBF)
loadAddon("Tracking/ResourceShift.lua", WBF)
loadAddon("Tracking/Resources.lua", WBF)

local function check(name, condition)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name)
end

local function define(key, id)
    WBF.Resources.Register({
        key = key,
        name = key,
        short = key,
        trackingType = "currency",
        id = id,
    })
    local definition = WBF.Resources.Get(key)
    definition.classification = "ACCOUNT_WIDE_CURRENCY"
    definition.ownership = "warband"
    return definition
end

local function resourceEvents(key)
    local list = {}
    for index = 1, #db.events do
        local event = db.events[index]
        local meta = event.meta or {}
        if meta.resourceKey == key then
            list[#list + 1] = event
        end
    end
    return list
end

local function movementCount(key)
    local count = 0
    for index = 1, #resourceEvents(key) do
        local class = resourceEvents(key)[index].meta.classification
        if class == "gain" or class == "gain_observed" or class == "spend" or class == "loss_observed" then
            count = count + 1
        end
    end
    return count
end

resetDb()
define("tender", 2032)

local function period()
    return WBF.Resources.Report("tender", now - 7 * 86400, now + 10, nil).period
end

WBF.Resources.CommitObservation("tender", 1935, "A", false)
local first = period()
check("first sight is a baseline, not earnings", first.earned == 0 and first.spent == 0 and first.net == 0)
check("opening and current are 1935", first.opening == 1935 and first.current == 1935)
check("one baseline event", #resourceEvents("tender") == 1 and resourceEvents("tender")[1].meta.classification == "baseline")
local quietTiles = WBF.Resources.ForPeriod(db.events, now - 7 * 86400, now + 10).tiles
check("baseline only stays off the period summary", #quietTiles == 0)

local beforeSwitch = #db.events
WBF.Resources.CommitObservation("tender", 1935, "B", false)
WBF.Resources.CommitObservation("tender", 1935, "C", false)
local switched = period()
check("character switches add no events", #db.events == beforeSwitch)
check("three characters still net zero", switched.earned == 0 and switched.spent == 0 and switched.net == 0 and switched.current == 1935)

WBF.Resources.CommitObservation("tender", 2435, "A", false)
local gained = period()
check("gain of 500", gained.current == 2435 and gained.earned == 500 and gained.spent == 0 and gained.net == 500)
check("exactly one movement after the gain", movementCount("tender") == 1)

local beforeAnotherSwitch = #db.events
WBF.Resources.CommitObservation("tender", 2435, "B", false)
check("switching after a gain adds nothing", #db.events == beforeAnotherSwitch)

WBF.Resources.CommitObservation("tender", 2185, "C", false)
local spent = period()
check("spend of 250", spent.current == 2185 and spent.earned == 500 and spent.spent == 250 and spent.net == 250)
check("exactly two movements", movementCount("tender") == 2)
local last = resourceEvents("tender")
local spendEvent = last[#last]
check("spend names the active character", spendEvent.guid == "C" and spendEvent.meta.observer == "Taxableyawl" and spendEvent.meta.ownership == "warband")

local beforeReload = #db.events
WBF.Resources.CommitObservation("tender", 2185, "A", false)
WBF.Resources.CommitObservation("tender", nil, "A", false)
check("reload and a missing quantity add nothing", #db.events == beforeReload and period().current == 2185)

local tile = WBF.Resources.ForPeriod(db.events, now - 7 * 86400, now + 10).tiles
local tenderTile
for index = 1, #tile do
    if tile[index].key == "tender" then
        tenderTile = tile[index]
    end
end
check("week tile uses net and current", tenderTile and tenderTile.net == 250 and tenderTile.current == 2185 and tenderTile.earned == 500)

resetDb()
define("tender", 2032)
WBF.Resources.CommitObservation("tender", 1935, "A", false)
WBF.Resources.CommitObservation("tender", 2435, "A", false)
WBF.Resources.CommitObservation("tender", 1935, "A", false)
local even = WBF.Resources.ForPeriod(db.events, now - 7 * 86400, now + 10).tiles
check("zero net with real activity stays visible", #even == 1 and even[1].net == 0 and even[1].earned == 500 and even[1].spent == 500 and even[1].current == 1935)
local board = WBF.Resources.Board("tender", now - 7 * 86400, now + 10, "This Month")
check("detail opening is the first observation", board.period.opening == 1935 and board.period.earned == 500 and board.period.spent == 500 and board.period.net == 0 and board.current == 1935)
check("shared currency lists observers", board.peopleMode == "observed" and board.badge == "Warband Currency")
local baselineRow
for index = 1, #board.activity do
    if board.activity[index].opening then
        baselineRow = board.activity[index]
    end
end
check("initial observation is not earned", baselineRow and baselineRow.delta == 0 and baselineRow.balance == 1935 and baselineRow.note == "Tracking started")
local peak = board.history[1] and board.history[1].balance or nil
for index = 1, #board.history do
    if board.history[index].balance > peak then
        peak = board.history[index].balance
    end
end
check("history follows the observed balance", peak == 2435 and board.history[#board.history].balance == 1935)
check("all time totals exclude the opening balance", board.lifetime and board.lifetime.gained == 500 and board.lifetime.spent == 500 and board.lifetime.highest == 2435)

-- Duplicate character copies from the account-character API.
resetDb()
define("tender", 2032)
define("keepsake", 999001)
local keepsake = WBF.Resources.Get("keepsake")
keepsake.classification = "CHARACTER_CURRENCY"
keepsake.ownership = "character"
db.resources = {
    balances = {
        tender = {
            characters = { A = 1935, B = 1935, C = 1935 },
            names = { A = "Miranora", B = "Miraqt", C = "Taxableyawl" },
        },
        keepsake = { characters = { A = 40 } },
    },
    definitions = {},
    watched = {},
    watchlist = {},
    scanState = {},
}
local function plant(key, guid, delta, balance, classification)
    db.events[#db.events + 1] = {
        id = WBF.Database.AllocEventId(),
        at = now - 1000,
        guid = guid,
        eventType = "resource",
        delta = delta,
        previous = balance - delta,
        new = balance,
        meta = {
            resourceKey = key,
            classification = classification,
            balanceAfter = balance,
        },
    }
end
plant("tender", "A", 1935, 1935, "gain_observed")
plant("tender", "A", -1935, 0, "loss_observed")
plant("tender", "B", 1935, 1935, "gain_observed")
plant("tender", "B", -1935, 0, "loss_observed")
plant("tender", "C", 1935, 5805, "gain_observed")
plant("tender", "C", -1935, 3870, "loss_observed")
plant("tender", "A", 500, 2435, "gain_observed")
plant("keepsake", "A", 12, 40, "gain_observed")

WBF.Resources.MigrateOwnedBalances()
local echoed = 0
local keptGain = false
local keptOther = false
local baselines = 0
for index = 1, #db.events do
    local event = db.events[index]
    local meta = event.meta or {}
    if meta.resourceKey == "tender" then
        if math.abs(event.delta or 0) == 1935 then
            echoed = echoed + 1
        end
        if event.delta == 500 then
            keptGain = true
        end
        if meta.classification == "baseline" and meta.balanceAfter == 1935 then
            baselines = baselines + 1
        end
    elseif meta.resourceKey == "keepsake" then
        keptOther = event.delta == 12
    end
end
local tenderState = db.resources.balances.tender
check("synthetic full-balance echoes are removed", echoed == 0)
check("a real 500 change is kept", keptGain)
check("unrelated currency history is kept", keptOther)
check("canonical balance is 1935, not 5805", tenderState.currentBalance == 1935 and tenderState.accountWide == 1935)
check("per-character copies are gone", next(tenderState.characters) == nil)
check("one baseline replaces the duplicated history", baselines == 1)
check("other currency balance is untouched", db.resources.balances.keepsake.characters.A == 40)

local afterMigration = #db.events
WBF.Resources.CommitObservation("tender", 1935, "A", false)
WBF.Resources.CommitObservation("tender", 1935, "B", false)
WBF.Resources.CommitObservation("tender", 1935, "C", false)
check("logging across characters after migration is still quiet", #db.events == afterMigration)

local function joined(list, field)
    local parts = {}
    for index = 1, #list do
        local value = field and list[index][field] or list[index]
        parts[index] = tostring(value)
    end
    return table.concat(parts, ",")
end

check("axis 27", joined(WBF.Format.NiceTicks(27, 5)) == "0,10,20,30")
check("axis 258", joined(WBF.Format.NiceTicks(258, 5)) == "0,100,200,300")
check("axis 1935", joined(WBF.Format.NiceTicks(1935, 5)) == "0,500,1000,1500,2000")
check("axis 29833", joined(WBF.Format.NiceTicks(29833, 5)) == "0,10000,20000,30000")

local function boundsFor(values)
    local low = values[1]
    local high = values[1]
    for index = 1, #values do
        if values[index] < low then
            low = values[index]
        end
        if values[index] > high then
            high = values[index]
        end
    end
    return WBF.Format.NiceBounds(low, high, 5, low < 0), low, high
end

local function covers(ticks, low, high)
    return ticks[1] <= low and ticks[#ticks] >= high and ticks[#ticks] > ticks[1]
end

local seriesA, minA, maxA = boundsFor({ 839, 1554, 1559, 1564, 1569, 1574 })
check("series A fills the visible range", joined(seriesA) == "750,1000,1250,1500,1750" and covers(seriesA, minA, maxA))
local seriesB, minB, maxB = boundsFor({ 1550, 1555, 1560, 1565 })
check("series B keeps a small change visible", joined(seriesB) == "1500,1520,1540,1560,1580,1600" and covers(seriesB, minB, maxB))
local seriesC, minC, maxC = boundsFor({ 1574, 1574, 1574 })
check("series C gives a flat line headroom", joined(seriesC) == "1520,1540,1560,1580,1600,1620" and covers(seriesC, minC, maxC))
local seriesD, minD, maxD = boundsFor({ 0, 1, 2, 5 })
check("series D stays small and non-negative", joined(seriesD) == "0,5,10" and seriesD[1] >= 0 and covers(seriesD, minD, maxD))
local seriesE, minE, maxE = boundsFor({ 850000, 875000, 940000 })
check("series E scales around the large balance", joined(seriesE) == "800000,850000,900000,950000,1000000" and covers(seriesE, minE, maxE))
local seriesF, minF, maxF = boundsFor({ 5400000, 5450000, 5500000 })
check("series F zooms to the multimillion range", joined(seriesF) == "5300000,5400000,5500000,5600000" and covers(seriesF, minF, maxF))
local outlier = boundsFor({ 1500, 500000 })
check("outlier stays on the axis", outlier[1] <= 1500 and outlier[#outlier] >= 500000 and outlier[1] >= 0)

local dayStart = time({ year = 2026, month = 9, day = 27, hour = 6, min = 57, sec = 0 })
local dayEnd = time({ year = 2026, month = 9, day = 27, hour = 15, min = 52, sec = 0 })
check("same-day hours", joined(WBF.Format.TimeTicks(dayStart, dayEnd, 5), "text") == "08:00,10:00,12:00,14:00")
local weekStart = time({ year = 2026, month = 9, day = 21, hour = 0, min = 0, sec = 0 })
local weekEnd = time({ year = 2026, month = 9, day = 27, hour = 18, min = 0, sec = 0 })
check("week days", joined(WBF.Format.TimeTicks(weekStart, weekEnd, 8), "text") == "Mon 21,Tue 22,Wed 23,Thu 24,Fri 25,Sat 26,Sun 27")
local monthStart = time({ year = 2026, month = 9, day = 1, hour = 0, min = 0, sec = 0 })
local monthEnd = time({ year = 2026, month = 9, day = 30, hour = 20, min = 0, sec = 0 })
check("month dates", joined(WBF.Format.TimeTicks(monthStart, monthEnd, 8), "text") == "Sep 1,Sep 5,Sep 10,Sep 15,Sep 20,Sep 25,Sep 30")

resetDb()
local token = "brewfest_token"
local function tokenPeriod()
    return WBF.Resources.Board(token, now - 86400, now + 10, "Current Session")
end

WBF.Resources.ObserveItem(token, 29, 229, "A", "BAG_UPDATE_DELAYED", true)
WBF.Resources.ObserveItem(token, 29, 229, "A", "BAG_UPDATE_DELAYED", true)
WBF.Resources.ObserveItem(token, 29, 229, "A", "BAG_UPDATE_DELAYED", true)
check("stable balance adds no movement", movementCount(token) == 0)
check("stable balance stays 258", tokenPeriod().current == 258 and tokenPeriod().period.current == 258)

WBF.Resources.ObserveItem(token, 44, 229, "A", "BAG_UPDATE_DELAYED", true)
local gainedToken = tokenPeriod()
check("legitimate gain is +15", gainedToken.period.earned == 15 and gainedToken.period.spent == 0 and gainedToken.current == 273)
check("legitimate gain is one movement", movementCount(token) == 1)

WBF.Resources.ObserveItem(token, 4, 229, "A", "BAG_UPDATE_DELAYED", true)
local spentToken = tokenPeriod()
check("legitimate spend is -40", spentToken.period.spent == 40 and spentToken.current == 233)
check("spend is a second movement", movementCount(token) == 2)
check("period reconciles after spend", spentToken.period.opening + spentToken.period.earned - spentToken.period.spent == spentToken.period.current)

local beforePlunge = #db.events
WBF.Resources.ObserveItem(token, 29, 0, "A", "BAG_UPDATE_DELAYED", false)
WBF.Resources.ObserveItem(token, 4, 229, "A", "BAG_UPDATE_DELAYED", true)
check("transient bank dropout is not recorded", #db.events == beforePlunge and movementCount(token) == 2)
check("balance stays 233 after the dropout", tokenPeriod().current == 233)

local beforeSwitch = #db.events
WBF.Resources.ObserveItem(token, 0, 229, "B", "BAG_UPDATE_DELAYED", true)
check("character switch adds no transaction", #db.events == beforeSwitch)
local sawB = false
local switched = tokenPeriod()
for index = 1, #switched.people do
    if switched.people[index].name == "Miraqt" then
        sawB = true
    end
end
check("switched character is observed", sawB)

WBF.Resources.BeginSettle()
local beforeReload = #db.events
WBF.Resources.ObserveItem(token, 29, 0, "A", "PLAYER_ENTERING_WORLD", false)
check("reload flicker is not recorded", #db.events == beforeReload)
now = now + 4
WBF.Resources.ObserveItem(token, 4, 229, "A", "BAG_UPDATE_DELAYED", true)
check("reload settles on the same balance", #db.events == beforeReload and tokenPeriod().current == 233)

local logs = {}
WBF.Debug.Enabled = function()
    return true
end
WBF.Debug.Log = function(message)
    logs[#logs + 1] = message
end
WBF.Resources.ObserveItem(token, 29, 0, "A", "BAG_UPDATE_DELAYED", false)
local pendingLog = logs[#logs] or ""
check("debug names the pending read", pendingLog:find("PENDING_VALIDATION", 1, true) and pendingLog:find("previous=233", 1, true) and pendingLog:find("candidate=29", 1, true))
WBF.Resources.ObserveItem(token, 4, 229, "A", "BAG_UPDATE_DELAYED", true)
local rejectedLog = logs[#logs] or ""
check("debug names the rejected transient", rejectedLog:find("REJECTED_TRANSIENT", 1, true) and rejectedLog:find("rejectedCandidate=29", 1, true))
WBF.Debug.Enabled = function()
    return false
end

resetDb()
define("tender", 2032)
WBF.Resources.ObserveBalance("tender", 250, nil, false)
WBF.Resources.ObserveBalance("tender", 250, nil, false)
local beforeRapid = movementCount("tender")
WBF.Resources.ObserveBalance("tender", 200, -50, true)
WBF.Resources.ObserveBalance("tender", 250, 50, true)
check("authoritative spend and gain are both kept", movementCount("tender") == beforeRapid + 2)
local rapid = WBF.Resources.Board("tender", now - 86400, now + 10, "Current Session")
check("rapid pair still reconciles", rapid.period.opening + rapid.period.earned - rapid.period.spent == rapid.period.current)

resetDb()
local function plant(key, at, delta, balance, classification)
    db.events[#db.events + 1] = {
        id = WBF.Database.AllocEventId(),
        at = at,
        guid = "A",
        eventType = "resource",
        delta = delta,
        previous = balance - delta,
        new = balance,
        meta = {
            resourceKey = key,
            classification = classification,
            balanceAfter = balance,
            eventName = "Brewfest 2026",
        },
    }
end
plant(token, now - 400, 0, 76, "baseline")
plant(token, now - 200, 157, 233, "sync")
plant(token, now - 70, -204, 29, "loss_observed")
plant(token, now - 69, 204, 233, "gain_observed")
plant(token, now - 60, 10, 243, "gain_observed")
plant(token, now - 50, -214, 29, "loss_observed")
plant(token, now - 49, 214, 243, "gain_observed")
plant(token, now - 40, 15, 258, "gain_observed")
local reconciled = WBF.Resources.Board(token, now - 86400, now + 10, "Current Session")
check("opening includes stock that was already held", reconciled.period.opening == 233)
check("mirrored bank dropouts leave the totals", reconciled.period.earned == 25 and reconciled.period.spent == 0 and reconciled.period.net == 25)
check("opening plus net equals close", reconciled.period.opening + reconciled.period.net == reconciled.period.current and reconciled.period.current == 258)
local plunged = false
local contextOk = false
local claimedCause = false
for index = 1, #reconciled.activity do
    local row = reconciled.activity[index]
    if row.balance == 29 then
        plunged = true
    end
    if row.note == "Brewfest 2026" then
        contextOk = true
    end
    if row.note and row.note:find("World event", 1, true) then
        claimedCause = true
    end
end
for index = 1, #reconciled.history do
    if reconciled.history[index].balance == 29 and not reconciled.history[index].carried then
        plunged = true
    end
end
check("graph and activity skip the transient 29", not plunged)
check("context names the event", contextOk)
check("context does not claim a world event cause", not claimedCause)

local removed = WBF.Resources.RepairHistory(true)
check("repair deletes the repeated plunges", removed == 4)
local still29 = false
for index = 1, #db.events do
    local meta = db.events[index].meta or {}
    if meta.resourceKey == token and meta.balanceAfter == 29 then
        still29 = true
    end
end
check("saved history no longer contains the plunge", not still29)
local afterRepair = WBF.Resources.Board(token, now - 86400, now + 10, "Current Session")
check("repaired history still reconciles", afterRepair.period.opening + afterRepair.period.earned - afterRepair.period.spent == afterRepair.period.current)

resetDb()
plant(token, now - 30, 0, 250, "baseline")
plant(token, now - 20, -50, 200, "loss_observed")
plant(token, now - 19, 50, 250, "gain_observed")
local keptRoundTrip = WBF.Resources.RepairHistory(true)
check("one real round trip is not deleted", keptRoundTrip == 0 and movementCount(token) == 2)

local cleared = WBF.Resources.ResetHistory("brewfest prize token")
check("reset finds the resource", cleared and cleared.key == token)
check("reset removes that resource only", movementCount(token) == 0)
WBF.Resources.ObserveItem(token, 10, 90, "A", "BAG_UPDATE_DELAYED", true)
check("reset baselines on the next observation", movementCount(token) == 0 and tokenPeriod().current == 100 and tokenPeriod().period.opening == 100)

-- transferSeen forgets ids after 90 days. A transaction that old must not be
-- ingested again just because the client log still lists it.
resetDb()
local relay = "relay"
define(relay, 9901)
db.resources = { balances = {} }
db.resources.balances[relay] = {
    characters = { A = 100, B = 0 },
    baselined = true,
    baselinedAt = now - 200 * 86400,
}
local transferLog = {
    { currencyType = 9901, sourceCharacterGUID = "A", destinationCharacterGUID = "B", sourceCharacterName = "Miranora", destinationCharacterName = "Miraqt", quantityTransferred = 30, timestamp = now - 120 * 86400 },
    { currencyType = 9901, sourceCharacterGUID = "A", destinationCharacterGUID = "B", sourceCharacterName = "Miranora", destinationCharacterName = "Miraqt", quantityTransferred = 20, timestamp = now - 86400 },
}
C_CurrencyInfo = {
    IsCurrencyTransferTransactionDataReady = function()
        return true
    end,
    FetchCurrencyTransferTransactions = function()
        return transferLog
    end,
}
local handlers = {}
WBF.Resources.RegisterBus({
    On = function(_, event, callback)
        handlers[event] = callback
    end,
})
local function transferDeltas()
    local deltas = {}
    for index = 1, #db.events do
        local event = db.events[index]
        local meta = event.meta or {}
        if meta.resourceKey == relay and meta.classification == "transfer" then
            deltas[#deltas + 1] = event.delta
        end
    end
    return deltas
end
handlers.CURRENCY_TRANSFER_LOG_UPDATE()
local firstPass = transferDeltas()
check("recent transfer is recorded on both sides", #firstPass == 2 and firstPass[1] == -20 and firstPass[2] == 20)
handlers.CURRENCY_TRANSFER_LOG_UPDATE()
check("transfers past the seen window are never ingested", #transferDeltas() == 2)
local keptOld = false
for id in pairs(db.resources.transferSeen or {}) do
    if id:find(":30$") then
        keptOld = true
    end
end
check("an old transfer is not remembered as seen", not keptOld)

-- The same amount moved between the same two characters twice is two transfers.
local function countDeltas(target)
    local count = 0
    local deltas = transferDeltas()
    for index = 1, #deltas do
        if deltas[index] == target then
            count = count + 1
        end
    end
    return count
end
resetDb()
db.resources = { balances = {} }
db.resources.balances[relay] = {
    characters = { A = 100, B = 0 },
    baselined = true,
    baselinedAt = now - 30 * 86400,
}
transferLog = {
    { currencyType = 9901, sourceCharacterGUID = "A", destinationCharacterGUID = "B", sourceCharacterName = "Miranora", destinationCharacterName = "Miraqt", quantityTransferred = 20, timestamp = now - 3 * 86400 },
    { currencyType = 9901, sourceCharacterGUID = "A", destinationCharacterGUID = "B", sourceCharacterName = "Miranora", destinationCharacterName = "Miraqt", quantityTransferred = 20, timestamp = now - 86400 },
}
handlers.CURRENCY_TRANSFER_LOG_UPDATE()
check("two identical transfers on different days are both recorded", countDeltas(-20) == 2 and countDeltas(20) == 2)
handlers.CURRENCY_TRANSFER_LOG_UPDATE()
check("reading the log again adds nothing", countDeltas(-20) == 2 and countDeltas(20) == 2)

-- A transfer already recorded live is not recorded again from the log, and an
-- older identical transfer does not stand in for a newer one.
resetDb()
db.resources = { balances = {} }
db.resources.balances[relay] = {
    characters = { A = 60, B = 40 },
    baselined = true,
    baselinedAt = now - 30 * 86400,
}
local function plantTransfer(at, guid, delta)
    db.events[#db.events + 1] = {
        id = WBF.Database.AllocEventId(),
        at = at,
        guid = guid,
        eventType = "resource",
        delta = delta,
        meta = { resourceKey = relay, classification = "transfer", balanceAfter = 100, warbandDelta = 0 },
    }
end
plantTransfer(now - 5 * 86400, "A", -20)
plantTransfer(now - 5 * 86400 + 30, "B", 20)
plantTransfer(now - 86400 + 5, "A", -20)
transferLog = {
    { currencyType = 9901, sourceCharacterGUID = "A", destinationCharacterGUID = "B", sourceCharacterName = "Miranora", destinationCharacterName = "Miraqt", quantityTransferred = 20, timestamp = now - 86400 },
}
handlers.CURRENCY_TRANSFER_LOG_UPDATE()
check("the live sending side is not recorded twice", countDeltas(-20) == 2)
check("the receiving side of the newer transfer is recorded", countDeltas(20) == 2)
C_CurrencyInfo = nil

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All warband currency checks passed")
