-- Collection hunt lockouts and slash routing.
--   lua tests/CollectionHuntsTest.lua

local script = arg and arg[0] or "tests/CollectionHuntsTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

local now = 1700000000
function time()
    return now
end

local WBF = {}
local db = {}
local failures = 0
local said = {}

function print(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring(select(index, ...))
    end
    said[#said + 1] = table.concat(parts, " ")
end

local function report(line)
    io.write(line .. "\n")
end

local function check(name, condition, detail)
    if condition then
        report("PASS  " .. name)
        return
    end
    failures = failures + 1
    report("FAIL  " .. name .. (detail and ("  " .. tostring(detail)) or ""))
end

WBF.Database = {
    Get = function()
        return db
    end,
}
WBF.Characters = {
    GetGuid = function()
        return "A"
    end,
    Get = function()
        return { guid = "A", name = "Mira", realm = "Area 52", classFile = "HUNTER" }
    end,
    List = function()
        return { { guid = "A", name = "Mira", realm = "Area 52" } }
    end,
}
WBF.UI = {}

loadAddon("Utils/Format.lua", WBF)
loadAddon("Tracking/CollectionSources.lua", WBF)
loadAddon("Tracking/CollectionHunts.lua", WBF)

local function reset()
    db = {}
    said = {}
end

local function lockout(instanceKey, saves, bosses)
    db.collectionHunts.lockouts = {
        A = {
            [instanceKey] = {
                checkedAt = now,
                verified = true,
                expiresAt = now + 3600,
                bosses = bosses or {},
                saves = saves,
            },
        },
    }
end

local function save(difficultyID, bossKey)
    return {
        difficultyID = difficultyID,
        expiresAt = now + 3600,
        bosses = { [bossKey] = true },
    }
end

reset()
local jikun = WBF.CollectionHunts.AddTarget("95059", "jikun")
check("jikun item becomes a hunt", type(jikun) == "string")
lockout("throneofthunder", { save(7, "jikun") })
check("raid finder ji-kun is still available", WBF.CollectionHunts.Status(jikun, "A") == "available")
lockout("throneofthunder", { save(17, "jikun") })
check("modern raid finder ji-kun is still available", WBF.CollectionHunts.Status(jikun, "A") == "available")
lockout("throneofthunder", { save(7, "jikun"), save(3, "jikun") })
check("normal ji-kun lockout is done", WBF.CollectionHunts.Status(jikun, "A") == "done")
lockout("throneofthunder", nil, { jikun = true })
check("combined legacy ji-kun snapshot stays unverified", WBF.CollectionHunts.Status(jikun, "A") == "unknown")

reset()
local invincible = WBF.CollectionHunts.AddTarget("50818", "invincible")
check("invincible item becomes a hunt", type(invincible) == "string")
lockout("icecrowncitadel", { save(4, "thelichking") })
check("25 normal lich king is not a heroic clear", WBF.CollectionHunts.Status(invincible, "A") == "unknown")
lockout("icecrowncitadel", { save(6, "thelichking") })
check("25 heroic lich king is done", WBF.CollectionHunts.Status(invincible, "A") == "done")

-- Daily holiday boss bags: done today per character, cleared at reset.
local doneToday = false
local petsOwned = 0
local hallowsEnd = true
function GetLFGDungeonRewards(id)
    return id == 285 and doneToday or false
end
C_DateAndTime = { GetSecondsUntilDailyReset = function() return 3600 end }
C_PetJournal = {
    GetPetInfoByItemID = function(itemID)
        if itemID == 70000 then return "Arfus", 1, 2, nil, nil, nil, nil, nil, nil, nil, nil, nil, 4321 end
    end,
    GetPetInfoBySpeciesID = function(speciesID)
        if speciesID == 4321 then
            return "Arfus", 12345, 4, nil, "|cFFFFD200Drop:|r Headless Horseman|n|cFFFFD200Zone:|r Scarlet Monastery"
        end
        if speciesID == 99 then return "Lost Kitten", 1, 1, nil, "|cFFFFD200Vendor:|r Breanni|n|cFFFFD200Zone:|r Dalaran" end
    end,
    GetNumCollectedInfo = function() return petsOwned, 3 end,
}
WBF.EventTriggers = {
    Active = function()
        return hallowsEnd and { { eventKey = "hallows_end" } } or {}
    end,
}

reset()
local arfus = WBF.CollectionHunts.AddTarget("70000", "headless")
local arfusInfo = arfus and WBF.CollectionHunts.Catalog()[arfus]
check("a pet cage item becomes a pet hunt", arfusInfo and arfusInfo.petSpeciesID == 4321 and arfusInfo.title == "Arfus" and WBF.CollectionHunts.Settings(arfus).goal == "pet")
local fromJournal = WBF.CollectionHunts.AddTarget("|cff0070dd|Hbattlepet:4321:1:3:150:10:10:0000000000000000|h[Arfus]|h|r", "headless")
check("a pet journal link becomes a pet hunt", fromJournal and WBF.CollectionHunts.Catalog()[fromJournal].petSpeciesID == 4321)
check("an unseen character is unverified", WBF.CollectionHunts.Status(arfus, "A") == "unknown")
WBF.CollectionHunts.SyncDaily()
check("an unlooted daily bag is available", WBF.CollectionHunts.Status(arfus, "A") == "available")
doneToday = true
WBF.CollectionHunts.SyncDaily()
check("a looted daily bag is done today", WBF.CollectionHunts.Status(arfus, "A") == "done")
now = now + 3601
check("the daily reset clears done to unverified", WBF.CollectionHunts.Status(arfus, "A") == "unknown")
doneToday = false
WBF.CollectionHunts.SyncDaily()
hallowsEnd = false
check("the boss is closed outside the event", WBF.CollectionHunts.Status(arfus, "A") == "closed")
hallowsEnd = true
petsOwned = 1
check("owning the pet completes the hunt", WBF.CollectionHunts.Status(arfus, "A") == "collected")
petsOwned = 0

-- Journal source text picks a curated source.
local Hunts = WBF.CollectionHunts
local lines = Hunts.SourceLines("|cFFFFD200Drop:|r Headless Horseman|n|cFFFFD200Zone:|r Scarlet Monastery")
check("source text splits into labelled lines", #lines == 2 and lines[1].label == "Drop" and lines[1].value == "Headless Horseman"
    and lines[2].label == "Zone" and lines[2].value == "Scarlet Monastery")
check("a pet's Journal source picks the Headless Horseman", (Hunts.JournalSource("pet", 4321)) == "headless")
check("a pet cage item reads its pet's source", (Hunts.JournalSource("item", 70000)) == "headless")
local key, vendorLines = Hunts.JournalSource("pet", 99)
check("an uncurated source is reported, not guessed", key == nil and #vendorLines == 2 and vendorLines[1].value == "Breanni")
check("a boss and its instance pick that source", (Hunts.SourceFromText("Drop: Onyxia\nZone: Onyxia's Lair")) == "onyxian")
check("a boss name with odd punctuation still matches", (Hunts.SourceFromText("Drop: Al'Akir")) == "southwind")
check("a zone alone does not pick a boss", Hunts.SourceFromText("Zone: Icecrown Citadel") == nil)
check("no source text gives nothing", Hunts.JournalSource("pet", 12) == nil)

reset()
check("hunter is not a hunt command", WBF.CollectionHunts.Slash("hunter") == false)
check("hunter prints nothing", #said == 0)
check("hunt list is handled", WBF.CollectionHunts.Slash("hunt list") == true)
check("exact hunt is handled", WBF.CollectionHunts.Slash("hunt") == true)
check("hunts is handled", WBF.CollectionHunts.Slash("hunts") == true)

if failures > 0 then
    report(failures .. " failed")
    os.exit(1)
end
report("all passed")
