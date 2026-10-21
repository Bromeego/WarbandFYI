-- Housing decor separates a first-time collection from repeated copies,
-- and House XP is an observed favor change counted once across houses.
-- Run from the repo root:
--   lua tests/HousingDecorTest.lua

local script = arg and arg[0] or "tests/HousingDecorTest.lua"
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
local now = 1750000000
local failures = 0
local current = "A"

local function check(name, condition, detail)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  " .. detail) or ""))
end

loadAddon("Utils/Format.lua", WBF)
loadAddon("Utils/Time.lua", WBF)
loadAddon("Utils/Debug.lua", WBF)
loadAddon("Core/Events.lua", WBF)
loadAddon("Core/Characters.lua", WBF)
loadAddon("Core/Sessions.lua", WBF)
loadAddon("Core/Aggregator.lua", WBF)
loadAddon("Core/Database.lua", WBF)
loadAddon("Tracking/QuestVisibility.lua", WBF)
loadAddon("Tracking/Gold.lua", WBF)
loadAddon("Tracking/ResourceBehaviour.lua", WBF)
loadAddon("Tracking/Collections.lua", WBF)
loadAddon("Tracking/Housing.lua", WBF)

WBF.Time.Now = function()
    return now
end

WBF.Characters.GetGuid = function()
    return current
end

WBF.Characters.GetCurrent = function()
    return WarbandFYI_DB.characters[current]
end

local function freshDb()
    WarbandFYI_DB = {
        schemaVersion = 2,
        config = { retentionDays = 120, sessionTimeoutSeconds = 3600 },
        nextIds = { session = 2, event = 1 },
        activeSessionId = 1,
        sessions = {
            {
                id = 1,
                startedAt = now - 10,
                endedAt = nil,
                lastActivityAt = now,
                segments = {},
                goldByCharacter = {},
                goldLedger = {},
            },
        },
        characters = {
            A = { guid = "A", name = "Miranora", discovered = true, classFile = "MAGE" },
            B = { guid = "B", name = "Arren", discovered = true, classFile = "WARRIOR" },
        },
        snapshots = {},
        events = {},
        dedupe = {},
        goldLast = {},
        housing = { collected = {}, favor = {} },
    }
    WBF.Database.ready = true
    current = "A"
    WBF.Housing.ResetRuntime()
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
end

local function counts()
    return WBF.Aggregator.Build("week").totals
end

local function surfaced()
    local summary = WBF.Aggregator.Build("week")
    local list = {}
    for index = 1, #summary.activity do
        local event = summary.activity[index]
        if event.eventType == WBF.EventType.HousingDecor or event.eventType == WBF.EventType.HousingAcquire then
            list[#list + 1] = event
        end
    end
    return list
end

local function acquireCount(decorID)
    local rows = WBF.Housing.Acquisitions(WBF.Housing.EventsBetween(0, now + 1, nil))
    for index = 1, #rows do
        if rows[index].decorID == decorID then
            return rows[index].count
        end
    end
    return 0
end

freshDb()
local first = WBF.Housing.NoteAcquisition({
    decorGUID = "Decor-1",
    decorID = 501,
    owned = 1,
    name = "Amani Ritual Totem",
    itemID = 240001,
    icon = 134414,
    bonus = 10,
    source = "Zul'Aman",
})
check("first copy is a new collection", first == "new", tostring(first))
check("first copy counts as acquired and new", counts().decorAcquired == 1 and counts().newDecor == 1 and counts().duplicates == 0)
check("first copy is one activity row", #surfaced() == 1 and surfaced()[1].text == "New decor: Amani Ritual Totem")

WBF.Housing.NoteFavor({ houseGUID = "House-1", houseLevel = 2, houseFavor = 100 })
WBF.Housing.NoteFavor({ houseGUID = "House-2", houseLevel = 2, houseFavor = 40 })
check("the first favor reading is a baseline", WBF.Housing.FlushFavor() == 0 and counts().houseXP == 0)
WBF.Housing.NoteFavor({ houseGUID = "House-1", houseLevel = 2, houseFavor = 110 })
WBF.Housing.NoteFavor({ houseGUID = "House-2", houseLevel = 2, houseFavor = 50 })
check("the same bonus on every house counts once", WBF.Housing.FlushFavor() == 10, "xp=" .. tostring(counts().houseXP))
check("house XP is ten, not twenty", counts().houseXP == 10)
local newEvent = surfaced()[1]
check("the observed bonus is stored on the new decor", newEvent and newEvent.meta.houseXP == 10)

local again = WBF.Housing.NoteAcquisition({
    decorGUID = "Decor-1",
    decorID = 501,
    owned = 1,
    name = "Amani Ritual Totem",
})
check("the same chest record is not recorded twice", again == "ignored" and counts().decorAcquired == 1 and counts().newDecor == 1)

for copy = 2, 5 do
    WBF.Housing.NoteAcquisition({
        decorGUID = "Decor-" .. copy,
        decorID = 501,
        owned = copy,
        name = "Amani Ritual Totem",
    })
end
check("four more copies are duplicates", counts().decorAcquired == 5 and counts().newDecor == 1 and counts().duplicates == 4)
check("repeated copies stay one aggregate", acquireCount(501) == 5)
check("repeated copies do not add activity rows", #surfaced() == 1)

current = "B"
local onB = WBF.Housing.NoteAcquisition({
    decorGUID = "Decor-B",
    decorID = 501,
    owned = 6,
    name = "Amani Ritual Totem",
})
check("another character does not collect it again", onB == "duplicate" and counts().newDecor == 1)
local owners = 0
for index = 1, #WarbandFYI_DB.events do
    local event = WarbandFYI_DB.events[index]
    if event.eventType == WBF.EventType.HousingDecor then
        owners = owners + 1
        check("the first collection stays on character A", event.guid == "A")
    end
end
check("there is still one first-time event", owners == 1)
check("the collection record stays account-wide", WarbandFYI_DB.housing.collected["501"].guid == "A")

freshDb()
for copy = 1, 5 do
    WBF.Housing.NoteAcquisition({
        decorGUID = "Owned-" .. copy,
        decorID = 77,
        owned = 8,
        name = "Amani Drum",
    })
end
check("an already collected decor is not new", counts().newDecor == 0 and counts().duplicates == 5 and counts().decorAcquired == 5)
check("five copies collapse to one row", acquireCount(77) == 5 and #surfaced() == 0)

freshDb()
local unknown = WBF.Housing.NoteAcquisition({
    decorGUID = "Unknown-1",
    decorID = 88,
    name = "Unreadable Decor",
})
check("an unreadable catalog is not called new", unknown == "duplicate" and counts().newDecor == 0 and counts().decorAcquired == 1)

freshDb()
WBF.Housing.NoteFavor({ houseGUID = "House-1", houseLevel = 3, houseFavor = 20 })
WBF.Housing.NoteFavor({ houseGUID = "House-2", houseLevel = 3, houseFavor = 20 })
WBF.Housing.NoteFavor({ houseGUID = "House-1", houseLevel = 3, houseFavor = 30 })
WBF.Housing.NoteFavor({ houseGUID = "House-2", houseLevel = 3, houseFavor = 45 })
check("disagreeing house favor changes are not invented as XP", WBF.Housing.FlushFavor() == 0 and counts().houseXP == 0)

freshDb()
local old = now
WBF.Housing.NoteAcquisition({
    decorGUID = "Keep-1",
    decorID = 321,
    owned = 1,
    name = "Amani Worship Candle",
    bonus = 10,
})
WBF.Housing.NoteFavor({ houseGUID = "House-1", houseLevel = 2, houseFavor = 0 })
WBF.Housing.NoteFavor({ houseGUID = "House-1", houseLevel = 2, houseFavor = 10 })
WBF.Housing.FlushFavor()
WBF.Housing.NoteAcquisition({
    decorGUID = "Keep-2",
    decorID = 321,
    owned = 2,
    name = "Amani Worship Candle",
})
local session = WarbandFYI_DB.sessions[1]
session.endedAt = old + 5
session.lastActivityAt = old + 5
WarbandFYI_DB.activeSessionId = nil
now = old + (200 * 86400)
local removed = WBF.Database.Prune(true)
check("old housing detail is trimmed", removed > 0 and #WarbandFYI_DB.events == 0, "removed=" .. tostring(removed) .. " left=" .. tostring(#WarbandFYI_DB.events))
local lifetime = WBF.Aggregator.Build("warband").totals
check("lifetime new decor survives retention", lifetime.newDecor == 1 and lifetime.decorAcquired == 2 and lifetime.duplicates == 1)
check("lifetime house XP survives retention", lifetime.houseXP == 10)
check("the collection name survives retention", WarbandFYI_DB.housing.collected["321"].name == "Amani Worship Candle")
local detail = WBF.Housing.BuildDetail(WBF.Aggregator.Build("warband"), {})
local titles = {}
for index = 1, #detail.sections do
    if detail.sections[index].title then
        titles[#titles + 1] = detail.sections[index].title
    end
end
check("all-time detail still has the collection", titles[#titles] == "Collection")

freshDb()
WBF.Housing.NoteAcquisition({
    decorGUID = "Week-1",
    decorID = 11,
    owned = 1,
    name = "Amani Ritual Totem",
    bonus = 10,
})
WBF.Housing.NoteAcquisition({
    decorGUID = "Week-2",
    decorID = 12,
    owned = 1,
    name = "Amani Worship Candle",
    bonus = 10,
})
WBF.Housing.NoteFavor({ houseGUID = "House-1", houseLevel = 4, houseFavor = 1000 })
WBF.Housing.NoteFavor({ houseGUID = "House-1", houseLevel = 4, houseFavor = 1020 })
WBF.Housing.FlushFavor()
for copy = 1, 6 do
    WBF.Housing.NoteAcquisition({
        decorGUID = "Week-dup-" .. copy,
        decorID = copy < 4 and 11 or 15,
        owned = 4,
        name = copy < 4 and "Amani Ritual Totem" or "Revantusk Cooking Pot",
    })
end
local week = counts()
check("a week separates new decor from duplicates", week.decorAcquired == 8 and week.newDecor == 2 and week.duplicates == 6 and week.houseXP == 20)
local model = WBF.Housing.BuildDetail(WBF.Aggregator.Build("week"), {})
local foundNew, foundAll, foundXP
for index = 1, #model.sections do
    local section = model.sections[index]
    if section.title == "New Decor" then
        foundNew = #section.rows == 2
    elseif section.title == "All Acquisitions" then
        foundAll = #section.rows == 3
    end
    for rowIndex = 1, #(section.rows or {}) do
        local row = section.rows[rowIndex]
        if row.title == "House XP gained" and row.value == "+20" then
            foundXP = true
        end
    end
end
check("the detail lists new decor, every acquisition, and house XP", foundNew and foundAll and foundXP)

local line = WBF.Format.ActivityLine({
    raids = 0, dungeons = 0, mythicPlus = 0, highestKey = 0, bosses = 0, delves = 0, highestDelve = 0,
    quests = 0, worldQuests = 0, achievements = 0, appearances = 3, mounts = 0, pets = 0, reputation = 0,
    renown = 0, professions = 0, newDecor = 2,
}, 0)
check("character progress names new decor", line:find("3 Appearances", 1, true) ~= nil and line:find("2 New Decor", 1, true) ~= nil, line)
check("character progress omits duplicate decor", line:find("Duplicate", 1, true) == nil)

local tile = WBF.Housing.Tile({ newDecor = 2, houseXP = 20, duplicates = 6, decorAcquired = 8 })
check("the dashboard tile leads with new decor", tile and tile.label == "New Decor" and tile.value == "2" and tile.detail == "+20 House XP")
check("duplicates alone do not create a tile", WBF.Housing.Tile({ newDecor = 0, duplicates = 6, decorAcquired = 6 }) == nil)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All housing decor checks passed")
