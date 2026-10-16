-- Profession meters and pet battle aggregation.
--   lua tests/ProfessionPetTest.lua

local script = arg and arg[0] or "tests/ProfessionPetTest.lua"
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
local nextId
local failures = 0

local function resetDb()
    now = (now or 1750000000) + 100
    nextId = 1
    db = {
        config = {},
        events = {},
        characters = {
            A = { guid = "A", name = "Miranora", discovered = true },
        },
        resources = nil,
    }
end

WBF.Time = {
    Now = function()
        return now
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
WBF.EventType = { Resource = "resource", Profession = "profession", PetBattle = "petBattle", Pet = "pet" }
WBF.Category = { Resource = "resource", Profession = "profession", Collection = "collection" }
WBF.Events = {
    Add = function(partial)
        local event = {
            id = WBF.Database.AllocEventId(),
            at = partial.at or now,
            guid = partial.guid or "A",
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

loadAddon("Utils/Format.lua", WBF)
loadAddon("Tracking/ResourceBehaviour.lua", WBF)
loadAddon("Tracking/ResourceShift.lua", WBF)
loadAddon("Tracking/Resources.lua", WBF)
loadAddon("Tracking/PetBattles.lua", WBF)
loadAddon("Tracking/Professions.lua", WBF)

local function check(name, condition)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name)
end

local function countWhere(predicate)
    local count = 0
    for index = 1, #db.events do
        if predicate(db.events[index]) then
            count = count + 1
        end
    end
    return count
end

resetDb()

check("concentration name is a regenerating meter", WBF.ResourceBehaviour.Classify(nil, "Enchanting Concentration") == WBF.ResourceBehaviour.REGENERATING_METER)
check("recharge info is a regenerating meter", WBF.ResourceBehaviour.Classify({ rechargingCycleDurationMS = 1000 }, "Spark") == WBF.ResourceBehaviour.REGENERATING_METER)
check("profession knowledge is progression", WBF.ResourceBehaviour.Classify(nil, "Enchanting Knowledge") == WBF.ResourceBehaviour.PROGRESSION)
check("tower knowledge stays a currency", WBF.ResourceBehaviour.Classify(nil, "Tower Knowledge") == WBF.ResourceBehaviour.CURRENCY)
check("brewfest stays a currency", WBF.ResourceBehaviour.Classify(nil, "Brewfest Prize Token") == WBF.ResourceBehaviour.CURRENCY)

WBF.Resources.Register({
    key = "enchanting_concentration",
    name = "Enchanting Concentration",
    short = "Enchanting Concentration",
    trackingType = "currency",
    id = 99001,
})
local concentration = WBF.Resources.Get("enchanting_concentration")
concentration.classification = "CHARACTER_CURRENCY"
concentration.ownership = "character"
concentration.behaviour = WBF.ResourceBehaviour.REGENERATING_METER
concentration.maximum = 1000
concentration.professionLabel = "Midnight Enchanting"

local function balance()
    local state = db.resources and db.resources.balances and db.resources.balances.enchanting_concentration
    return state and state.currentBalance
end

WBF.Resources.ObserveBalance("enchanting_concentration", 800, nil, true)
WBF.Resources.ObserveBalance("enchanting_concentration", 801, 1, true)
WBF.Resources.ObserveBalance("enchanting_concentration", 802, 1, true)
WBF.Resources.ObserveBalance("enchanting_concentration", 803, 1, true)

check("passive regen stores 803", balance() == 803)
check("passive regen creates no activity", #db.events == 0)

local period = WBF.Resources.ForPeriod(db.events, 0, now + 10)
check("passive regen is not a currency tile", #period.tiles == 0)

WBF.Resources.ObserveBalance("enchanting_concentration", 553, -250, true)
local used = countWhere(function(event)
    return event.meta and event.meta.concentrationUsed == 250
end)
check("craft records concentration used", used == 1)
check("craft leaves the meter at 553", balance() == 553)
check("craft does not create a currency event", countWhere(function(event)
    return event.eventType == "resource"
end) == 0)

WBF.Resources.ObserveBalance("enchanting_concentration", 554, 1, true)
WBF.Resources.ObserveBalance("enchanting_concentration", 555, 1, true)
check("regen after a craft adds no events", countWhere(function(event)
    return event.meta and event.meta.concentrationUsed
end) == 1)
check("regen after a craft updates state", balance() == 555)
check("session summary would not earn the regen", WBF.ResourceBehaviour.HidesActivity({
    eventType = "resource",
    delta = 1,
    text = "Enchanting Concentration +1",
    meta = { name = "Enchanting Concentration" },
}))

resetDb()
WBF.Resources.Register({
    key = "enchanting_knowledge",
    name = "Enchanting Knowledge",
    short = "Enchanting Knowledge",
    trackingType = "currency",
    id = 99002,
})
local knowledge = WBF.Resources.Get("enchanting_knowledge")
knowledge.classification = "CHARACTER_CURRENCY"
knowledge.ownership = "character"
knowledge.professionLabel = "Midnight Enchanting"
WBF.Resources.ObserveBalance("enchanting_knowledge", 4, nil, true)
WBF.Resources.ObserveBalance("enchanting_knowledge", 8, 4, true)
check("knowledge gain is a profession event", countWhere(function(event)
    return event.eventType == "profession" and event.meta and event.meta.knowledge == 4
end) == 1)
check("knowledge gain is not a currency tile", #WBF.Resources.ForPeriod(db.events, 0, now + 10).tiles == 0)

local folded = WBF.PetBattles.FoldLevels("Mechanical Pandaren Dragonling", 10, 13)
check("multi level is one span", folded and folded.levels == 3 and folded.fromLevel == 10 and folded.toLevel == 13)
check("reaching 25 is marked once", WBF.PetBattles.FoldLevels("Snaplasher", 24, 25).reached25 == true)

local levels = {}
WBF.PetBattles.NoteLevel(levels, "pet-1", "Mechanical Pandaren Dragonling", 11, 10)
WBF.PetBattles.NoteLevel(levels, "pet-1", "Mechanical Pandaren Dragonling", 12, 11)
WBF.PetBattles.NoteLevel(levels, "pet-1", "Mechanical Pandaren Dragonling", 13, 12)
check("several level ticks stay one pet", levels["pet-1"].from == 10 and levels["pet-1"].to == 13)

local capture = WBF.PetBattles.DescribeCapture("Darkmoon Glowfly", 4, 18, true)
check("capture names quality and new species", capture.newSpecies and capture.detail:find("Rare", 1, true) and capture.detail:find("New species", 1, true))
check("wild and trainer kinds", WBF.PetBattles.BattleKind(true, false) == "wild" and WBF.PetBattles.BattleKind(false, true) == "trainer" and WBF.PetBattles.BattleKind(false, false) == "pvp")

local report = WBF.PetBattles.Collect({
    { id = 1, at = 10, eventType = "petBattle", guid = "A", meta = { kind = "battleStart", battleType = "wild", surface = false } },
    { id = 2, at = 20, eventType = "petBattle", guid = "A", meta = { kind = "battle", outcome = "win", battleType = "wild" } },
    { id = 3, at = 20, eventType = "petBattle", guid = "A", meta = { kind = "level", levels = 3, fromLevel = 10, toLevel = 13, petKey = "pet-1", petName = "Mechanical Pandaren Dragonling", reached25 = false } },
    { id = 4, at = 21, eventType = "petBattle", guid = "A", meta = { kind = "capture", newSpecies = true, petName = "Darkmoon Glowfly" } },
})
check("battle started once", report.started == 1)
check("battle completed and won once", report.completed == 1 and report.wins == 1 and report.wild == 1)
check("levels aggregate to 3", report.levels == 3 and report.topPets[1].levels == 3)
check("capture counts captured and new", report.captured == 1 and report.newPets == 1)

local stats = WBF.Professions.PeriodStats("A", 0, now + 10, "Midnight Enchanting")
check("period stats see the knowledge gain", stats.knowledge == 4)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("all passed")
