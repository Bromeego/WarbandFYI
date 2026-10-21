-- Run from addon root: lua tests/PetSessionProgressTest.lua
local WBF = {}
assert(loadfile("Utils/Format.lua"))("WarbandFYI", WBF)
assert(loadfile("Tracking/PetBattles.lua"))("WarbandFYI", WBF)
local P = WBF.PetBattles
local checks = 0
local function eq(actual, expected)
    checks = checks + 1
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function level(id, session, pet, first, last, guid)
    local folded = P.FoldLevels("Boneshard", first, last)
    return { id = id, at = 100, sessionId = session, guid = guid or "A",
        eventType = "petBattle", text = "original",
        meta = { kind = "level", petKey = pet, petName = "Boneshard",
            fromLevel = first, toLevel = last, levels = last - first,
            reached25 = last == 25, detail = folded.detail } }
end
local a, b, c = level(1, 1, "p", 1, 10), level(2, 1, "p", 10, 24), level(3, 1, "p", 24, 25)
local events = { c, a, b }
local details = P.SessionLevelDetails(events)
eq(details[c], "Boneshard  1 -> 25 (session)")
eq(details[b], "Boneshard  1 -> 24 (session)")
eq(details[a], nil)
eq(events[1], c) -- Input order and event payloads remain untouched.
eq(c.meta.fromLevel, 24)
eq(c.meta.levels, 1)
eq(c.meta.detail, "Boneshard  24 -> 25")
eq(c.text, "original")
local report = P.Collect(events)
eq(report.levels, 24)
eq(report.topPets[1].levels, 24)
eq(report.level25, 1)

local d, e = level(4, 2, "p", 23, 24), level(5, 2, "p", 24, 25, "B")
details = P.SessionLevelDetails({ a, b, c, d, e })
eq(details[e], "Boneshard  23 -> 25 (session)") -- Resumed session / alt.
eq(details[d], nil) -- Separate session, even with identical timestamps.
local sameName = level(6, 2, "other-pet", 24, 25)
eq(P.SessionLevelDetails({ d, sameName })[sameName], nil)
local legacy = level(7, nil, "p", 24, 25)
eq(P.SessionLevelDetails({ a, b, legacy })[legacy], nil)
local noKey = level(8, 1, nil, 24, 25)
eq(P.SessionLevelDetails({ a, b, noKey })[noKey], nil)
eq(P.SessionLevelDetails({ a, c })[c], nil) -- Missing intervening history.
eq(P.SessionLevelDetails({ c })[c], nil) -- Pruned history never assumes level 1.
local invalid = level(2, 1, "p", 10, 24)
invalid.meta.fromLevel = nil
eq(P.SessionLevelDetails({ a, invalid, c })[c], nil)
eq(next(P.SessionLevelDetails(nil)), nil)

-- Real tracker callbacks: opening snapshots, multi-level ticks and duplicate close.
local handlers, recorded, current = {}, {}, 1
WBF.Category = { Collection = "collection" }
WBF.EventType = { PetBattle = "petBattle" }
WBF.Time = { Now = function() return 100 end }
WBF.Events = { Add = function(event)
    event.sessionId = 1
    event.id = #recorded + 1
    event.at = 100
    recorded[#recorded + 1] = event
    return event
end }
C_PetJournal = {
    GetPetLoadOutInfo = function(slot) if slot == 1 then return "p" end end,
    GetPetInfoByPetID = function() return 1, "Boneshard", current end,
}
P.Register({ On = function(_, name, callback) handlers[name] = callback end })
local function battle(to)
    handlers.PET_BATTLE_OPENING_START()
    current = to
    handlers.PET_BATTLE_LEVEL_CHANGED(1, 1, to)
    handlers.PET_BATTLE_LEVEL_CHANGED(1, 1, to) -- Duplicate notification.
    handlers.PET_BATTLE_CLOSE()
    handlers.PET_BATTLE_CLOSE()
end
battle(24)
battle(25)
eq(P.Collect(recorded).levels, 24)
eq(P.Collect(recorded).level25, 1)
eq(P.SessionLevelDetails(recorded)[recorded[#recorded]], "Boneshard  1 -> 25 (session)")
eq(recorded[#recorded].meta.fromLevel, 24)
-- Unknown initial levels must not fabricate a 24 -> 25 gain.
current = nil
local before = P.Collect(recorded).levels
battle(25)
eq(P.Collect(recorded).levels, before)
print("PASS " .. checks .. " pet session progression checks")
