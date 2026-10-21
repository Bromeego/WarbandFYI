-- Per-character session gold. Run from the repo root:
--   lua Tests/GoldTrackerTest.lua

local script = arg and arg[0] or "tests/GoldTrackerTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

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
local active
local logs
local eventAdds

local function loadGold()
    loadAddon("Tracking/Gold.lua", WBF)
end

WBF.Time = {
    Now = function()
        return now
    end,
}
WBF.Debug = {
    Enabled = function()
        return db and db.config and db.config.debug == true
    end,
    Log = function(message)
        if not WBF.Debug.Enabled() then
            return
        end
        logs[#logs + 1] = message
    end,
}
WBF.Sessions = {
    GetActive = function()
        return active
    end,
}
WBF.Database = {
    Get = function()
        return db
    end,
}
WBF.Characters = {
    Get = function(guid)
        return db.characters[guid]
    end,
    GetCurrent = function()
        return nil
    end,
}
WBF.Events = {
    Add = function()
        eventAdds = eventAdds + 1
    end,
}
WBF.Economy = { trustMoney = true }

loadAddon("Utils/Format.lua", WBF)
loadGold()

local failures = 0

local function check(name, condition, detail)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    if detail then
        print("FAIL  " .. name .. "  " .. detail)
    else
        print("FAIL  " .. name)
    end
end

local function g(gold)
    return gold * 10000
end

local function reset()
    now = 1700000000
    logs = {}
    eventAdds = 0
    db = {
        config = { debug = false },
        sessions = {},
        snapshots = {},
        characters = {},
        events = {},
    }
    active = nil
    WBF.Economy.trustMoney = true
end

local function character(guid, name, money)
    db.characters[guid] = {
        guid = guid,
        name = name,
        money = money,
    }
end

local function beginSession(fresh, keepMoney)
    if active and not active.endedAt then
        active.endedAt = now
    end
    now = now + 1
    local session = {
        id = #db.sessions + 1,
        startedAt = now,
        endedAt = nil,
        lastActivityAt = now,
        segments = {},
    }
    if fresh ~= false then
        session.goldByCharacter = {}
        session.goldLedger = {}
    end
    if not keepMoney then
        db.goldLast = {}
    end
    db.sessions[#db.sessions + 1] = session
    active = session
    return session
end

local function observe(guid, money)
    now = now + 1
    return WBF.GoldTracker.Observe(guid, money)
end

local function ledgerCount(session)
    return #(session.goldLedger or {})
end

local function collect(session)
    local startAt = session.startedAt
    local endAt = now + 1
    return WBF.GoldTracker.Collect(db, startAt, endAt)
end

local function sumGuid(byGuid)
    local total = 0
    for _, amount in pairs(byGuid) do
        total = total + amount
    end
    return total
end

reset()
character("A", "Taxableyawl", g(1))
character("B", "Miranora", nil)
character("C", "Alt", nil)

-- Test 1. First character login is a baseline, not income.
local session = beginSession(true)
local beforeLedger = ledgerCount(session)
local beforeEvents = #db.events
observe("A", g(10000))
check("test 1 session net is 0", WBF.GoldTracker.GetSessionNet() == 0, "net=" .. tostring(WBF.GoldTracker.GetSessionNet()))
check("test 1 character net is 0", WBF.GoldTracker.GetCharacterNet("A") == 0)
check("test 1 baseline stored", session.goldByCharacter.A.baseline == g(10000))
check("test 1 last money stored", session.goldByCharacter.A.lastMoney == g(10000))
check("test 1 no ledger entry", ledgerCount(session) == beforeLedger)
check("test 1 no activity event", eventAdds == 0 and #db.events == beforeEvents)
local net, tracked, byGuid = collect(session)
check("test 1 period net is 0", net == 0)
check("test 1 period is tracked", tracked == true)
check("test 1 stored balance is not income", (byGuid.A or 0) == 0)
check("test 1 saved character gold is not income", WBF.GoldTracker.GetSessionNet() == 0)

-- A saved balance on the character record must not become the comparison value.
session = beginSession(true)
db.characters.B.money = g(244201)
observe("B", g(244201))
check("saved balance is not a delta", WBF.GoldTracker.GetCharacterNet("B") == 0)

-- Test 2. Legitimate gain.
session = beginSession(true)
observe("A", g(10000))
observe("A", g(10250))
check("test 2 session net +250", WBF.GoldTracker.GetSessionNet() == g(250), "net=" .. tostring(WBF.GoldTracker.GetSessionNet()))
check("test 2 character net +250", WBF.GoldTracker.GetCharacterNet("A") == g(250))
net, tracked, byGuid = collect(session)
check("test 2 period matches character", net == g(250) and byGuid.A == g(250))

-- Test 3. Gain then spend.
session = beginSession(true)
observe("A", g(10000))
observe("A", g(10250))
observe("A", g(9750))
check("test 3 session net -250", WBF.GoldTracker.GetSessionNet() == g(-250), "net=" .. tostring(WBF.GoldTracker.GetSessionNet()))
check("test 3 character net -250", WBF.GoldTracker.GetCharacterNet("A") == g(-250))
check("test 3 two ledger entries", ledgerCount(session) == 2)

-- Test 4. Character swap must not treat the new balance as income.
session = beginSession(true)
observe("A", g(10000))
observe("B", g(250000))
check("test 4 session net is 0", WBF.GoldTracker.GetSessionNet() == 0, "net=" .. tostring(WBF.GoldTracker.GetSessionNet()))
check("test 4 character A is 0", WBF.GoldTracker.GetCharacterNet("A") == 0)
check("test 4 character B is 0", WBF.GoldTracker.GetCharacterNet("B") == 0)
check("test 4 no ledger entries", ledgerCount(session) == 0)
net, tracked, byGuid = collect(session)
check("test 4 period net is 0", net == 0 and sumGuid(byGuid) == 0)

-- The reported bug: Miranora's existing gold compared with Taxableyawl.
session = beginSession(true)
observe("A", g(38542))
observe("B", g(244201))
check("login onto a richer character is not income", WBF.GoldTracker.GetSessionNet() == 0)

-- Test 5. Several characters, one session total.
session = beginSession(true)
observe("A", g(10000))
observe("A", g(10500))
observe("B", g(250000))
observe("B", g(249750))
check("test 5 character A +500", WBF.GoldTracker.GetCharacterNet("A") == g(500))
check("test 5 character B -250", WBF.GoldTracker.GetCharacterNet("B") == g(-250))
check("test 5 session net +250", WBF.GoldTracker.GetSessionNet() == g(250), "net=" .. tostring(WBF.GoldTracker.GetSessionNet()))
net, tracked, byGuid = collect(session)
check("test 5 period matches the sum", net == g(250) and byGuid.A == g(500) and byGuid.B == g(-250) and sumGuid(byGuid) == net)

-- Test 6. Returning to a character continues that character's own balance.
session = beginSession(true)
observe("A", g(10000))
observe("A", g(10500))
observe("B", g(250000))
observe("B", g(249000))
local delta = observe("A", g(10600))
observe("C", g(999999))
check("test 6 return delta is +100", delta == g(100), "delta=" .. tostring(delta))
check("test 6 character A is +600", WBF.GoldTracker.GetCharacterNet("A") == g(600))
check("test 6 character B is -1000", WBF.GoldTracker.GetCharacterNet("B") == g(-1000))
check("test 6 character C is 0", WBF.GoldTracker.GetCharacterNet("C") == 0)
check("test 6 session net ignores C's balance", WBF.GoldTracker.GetSessionNet() == g(-400))
check("test 6 A last money is A's own", session.goldByCharacter.A.lastMoney == g(10600))
check("test 6 B last money is B's own", session.goldByCharacter.B.lastMoney == g(249000))
net, tracked, byGuid = collect(session)
check("test 6 period agrees with session", net == WBF.GoldTracker.GetSessionNet() and byGuid.A == g(600) and byGuid.C == nil)

-- A -> B -> A -> C keeps separate baselines.
session = beginSession(true)
observe("A", g(10000))
observe("B", g(250000))
observe("A", g(10000))
observe("C", g(12))
check("swap cycle adds no gold", WBF.GoldTracker.GetSessionNet() == 0)
check("swap cycle keeps three baselines", session.goldByCharacter.A.baseline == g(10000) and session.goldByCharacter.B.baseline == g(250000) and session.goldByCharacter.C.baseline == g(12))

-- Large legitimate transactions are recorded. Nothing is dropped for being large.
session = beginSession(true)
observe("A", g(10000))
local sale = observe("A", g(510000))
check("large sale counts", sale == g(500000), "sale=" .. tostring(sale))
local purchase = observe("A", g(1000))
check("large purchase counts", purchase == g(-509000), "purchase=" .. tostring(purchase))
check("large transactions remain in the net", WBF.GoldTracker.GetSessionNet() == g(-9000))

-- /reload keeps the baseline and the net already recorded.
session = beginSession(true)
observe("A", g(100000))
observe("A", g(100500))
check("before reload net +500", WBF.GoldTracker.GetCharacterNet("A") == g(500))
loadGold()
observe("A", g(100500))
check("reload keeps baseline", session.goldByCharacter.A.baseline == g(100000))
check("reload keeps net", WBF.GoldTracker.GetCharacterNet("A") == g(500))
check("reload does not add a ledger entry", ledgerCount(session) == 1)
observe("A", g(100600))
check("after reload a new gain still counts", WBF.GoldTracker.GetCharacterNet("A") == g(600))

-- A new session baselines again and does not inherit the previous net.
local kept = session
local previousNet = WBF.GoldTracker.GetCharacterNet("A")
session = beginSession(true)
observe("A", g(100600))
check("new session net is 0", WBF.GoldTracker.GetSessionNet() == 0)
check("new session baselines at the current balance", session.goldByCharacter.A.baseline == g(100600))
active = kept
check("previous session net unchanged", WBF.GoldTracker.GetCharacterNet("A") == previousNet and previousNet == g(600))
active = session

-- Untrusted 0 while entering the world is not a spend.
session = beginSession(true)
WBF.Economy.trustMoney = true
observe("A", g(100000))
observe("A", g(100500))
WBF.Economy.trustMoney = false
observe("A", 0)
check("untrusted zero keeps net", WBF.GoldTracker.GetCharacterNet("A") == g(500))
check("untrusted zero keeps last money", session.goldByCharacter.A.lastMoney == g(100500))
WBF.Economy.trustMoney = true
observe("A", g(100500))
check("real balance after reload still +500", WBF.GoldTracker.GetCharacterNet("A") == g(500))

-- Initialize does not reset a baseline. Handle compares with that character.
session = beginSession(true)
WBF.GoldTracker.InitializeCharacter("A", g(10000))
WBF.GoldTracker.InitializeCharacter("A", g(999999))
check("second initialize keeps baseline", session.goldByCharacter.A.baseline == g(10000))
check("handle records the real delta", WBF.GoldTracker.HandleMoneyChanged("A", g(10100)) == g(100))

-- Older sessions without gold tables rebuild per character, not across characters.
session = beginSession(false)
local rebuiltAt = session.startedAt
db.snapshots[#db.snapshots + 1] = { at = rebuiltAt, sessionId = session.id, guid = "A", money = g(10000) }
db.snapshots[#db.snapshots + 1] = { at = rebuiltAt + 5, sessionId = session.id, guid = "A", money = g(10500) }
db.snapshots[#db.snapshots + 1] = { at = rebuiltAt + 10, sessionId = session.id, guid = "B", money = g(250000) }
db.snapshots[#db.snapshots + 1] = { at = rebuiltAt + 15, sessionId = session.id, guid = "B", money = g(249750) }
now = rebuiltAt + 15
net, tracked, byGuid = collect(session)
check("rebuilt character A +500", (byGuid.A or 0) == g(500), "A=" .. tostring(byGuid.A))
check("rebuilt character B -250", (byGuid.B or 0) == g(-250), "B=" .. tostring(byGuid.B))
check("rebuilt session net +250", net == g(250), "net=" .. tostring(net))
check("rebuilt net matches GetSessionNet", WBF.GoldTracker.GetSessionNet() == g(250))
local ledgerAfterRebuild = ledgerCount(session)
collect(session)
collect(session)
check("rebuild runs once", ledgerCount(session) == ledgerAfterRebuild and WBF.GoldTracker.GetSessionNet() == g(250))
now = rebuiltAt + 20
observe("A", g(10600))
check("play continues from rebuilt last money", WBF.GoldTracker.GetCharacterNet("A") == g(600))
check("continued play does not retake B's balance", WBF.GoldTracker.GetCharacterNet("B") == g(-250))

-- The cross-character spike in stored snapshots is not replayed.
session = beginSession(false)
local spikeAt = session.startedAt
db.snapshots[#db.snapshots + 1] = { at = spikeAt, sessionId = session.id, guid = "A", money = g(38542) }
db.snapshots[#db.snapshots + 1] = { at = spikeAt + 30, sessionId = session.id, guid = "B", money = g(244201) }
now = spikeAt + 30
net = WBF.GoldTracker.Collect(db, spikeAt, now)
check("old cross-character snapshots net 0", net == 0, "net=" .. tostring(net))

-- Deltas outside the requested range stay out of that period.
session = beginSession(true)
observe("A", g(10000))
observe("A", g(10500))
local early = now
now = now + 100
observe("A", g(10600))
local periodNet = WBF.GoldTracker.Collect(db, early + 1, now + 1)
check("later period contains only the later delta", periodNet == g(100), "net=" .. tostring(periodNet))
check("full session still has both deltas", WBF.GoldTracker.GetSessionNet() == g(600))

-- Two sessions in one range add their own deltas.
local first = beginSession(true)
observe("A", g(10000))
observe("A", g(10500))
first.endedAt = now
local second = beginSession(true)
observe("A", g(20000))
observe("A", g(20200))
local rangeNet, rangeTracked, rangeBy = WBF.GoldTracker.Collect(db, first.startedAt, now + 1)
check("week sums both sessions", rangeNet == g(700), "net=" .. tostring(rangeNet))
check("week character total sums both sessions", rangeBy.A == g(700))
check("active session net is only its own delta", WBF.GoldTracker.GetSessionNet() == g(200))
check("both sessions were tracked", rangeTracked == true)

-- Sample gold stays out of the total once a real character has been seen.
reset()
character("A", "Taxableyawl")
character("S", "Sample")
local sampleSession = beginSession(true)
sampleSession.sample = true
sampleSession.goldByCharacter = {
    S = {
        baseline = g(1),
        lastMoney = g(999999),
        netChange = g(999998),
        establishedAt = sampleSession.startedAt,
    },
}
sampleSession.goldLedger = {
    { at = sampleSession.startedAt + 1, guid = "S", delta = g(999998) },
}
local sampleOnly = WBF.GoldTracker.Collect(db, sampleSession.startedAt, now + 5)
check("sample gold counts when it is the only history", sampleOnly == g(999998), "net=" .. tostring(sampleOnly))
local realSession = beginSession(true)
observe("A", g(10000))
local mixed = WBF.GoldTracker.Collect(db, sampleSession.startedAt, now + 5)
check("sample gold is excluded once real gold exists", mixed == 0, "net=" .. tostring(mixed))
check("real baseline is still tracked", select(2, WBF.GoldTracker.Collect(db, realSession.startedAt, now + 5)) == true)

-- Gold that changes after a session ends is reconciled once on the next session.
reset()
character("A", "Taxableyawl")
local ended = beginSession(true)
observe("A", g(10000))
observe("A", g(10500))
ended.endedAt = now
local resumed = beginSession(true, true)
local gap = observe("A", g(10800))
check("offline gap is recorded once", gap == g(300), "gap=" .. tostring(gap))
check("offline ledger source", resumed.goldLedger[1] and resumed.goldLedger[1].source == "betweenSessions")
check("offline session net includes the gap", WBF.GoldTracker.GetSessionNet() == g(300))
observe("A", g(10800))
check("repeating the same balance adds nothing", WBF.GoldTracker.GetSessionNet() == g(300) and ledgerCount(resumed) == 1)
local weekNet = WBF.GoldTracker.Collect(db, ended.startedAt, now + 1)
check("week includes the offline gap once", weekNet == g(800), "net=" .. tostring(weekNet))
beginSession(true, true)
observe("A", g(10800))
check("unchanged balance does not invent a gap", WBF.GoldTracker.GetSessionNet() == 0)

-- Debug lines, and silence when debug is off.
loadGold()
reset()
character("A", "Taxableyawl")
character("B", "Miranora")
session = beginSession(true)
db.config.debug = false
observe("B", g(244201))
check("debug off is silent", #logs == 0)
db.config.debug = true
loadGold()
session = beginSession(true)
logs = {}
observe("A", g(38542))
observe("B", g(244201))
observe("B", g(244284))
observe("A", g(38542))
observe("A", g(38542))
check("debug established baseline", logs[2] == "[Gold] Established baseline for Miranora: " .. WBF.Format.Gold(g(244201)), tostring(logs[2]))
check("debug records the change", logs[3] == "[Gold] Miranora change: " .. WBF.Format.Gold(g(83), true), tostring(logs[3]))
check("debug resumes the other character", logs[4] == "[Gold] Resuming Taxableyawl baseline", tostring(logs[4]))
check("debug does not log an unchanged tick", #logs == 4, "logs=" .. tostring(#logs))

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All gold tracker tests passed")
