-- Discovery-based character roster. Run from the repo root:
--   lua tests/CharacterDiscoveryTest.lua

local script = arg and arg[0] or "tests/CharacterDiscoveryTest.lua"
local root = script:gsub("[/\\][Tt]ests[/\\]CharacterDiscoveryTest%.lua$", "")
if root == "" or root == script then
    root = "."
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
local player

local function loadCore()
    loadAddon("Utils/Format.lua", WBF)
    loadAddon("Core/Events.lua", WBF)
    loadAddon("Core/Characters.lua", WBF)
    loadAddon("Core/Aggregator.lua", WBF)
end

WBF.Time = {
    Now = function()
        return now
    end,
    StartOfDay = function()
        return now - 86400
    end,
    StartOfWeek = function()
        return now - 7 * 86400
    end,
    StartOfMonth = function()
        return now - 31 * 86400
    end,
}
WBF.Debug = { Log = function() end }
WBF.Database = {
    Get = function()
        return db
    end,
    IsReady = function()
        return true
    end,
}
WBF.Sessions = {
    GetActive = function()
        return db.sessions[#db.sessions]
    end,
    GetLastCompleted = function()
        return db.sessions[#db.sessions]
    end,
    SegmentEnd = function(_, segment)
        return segment.endedAt or now
    end,
}
WBF.QuestVisibility = {
    IsPlayerActivity = function()
        return true
    end,
}
WBF.GoldTracker = {
    Collect = function()
        return 0, false, {}
    end,
}

loadCore()

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

local function reset()
    now = 1700000000
    db = {
        characters = {},
        snapshots = {},
        events = {},
        sessions = {},
    }
    WarbandFYI_DB = db
    player = nil
end

local function installPlayerApi()
    function UnitExists()
        return player ~= nil
    end
    function UnitGUID()
        return player and player.guid or nil
    end
    function UnitName()
        if not player then
            return nil, nil
        end
        return player.name, player.realm
    end
    function GetRealmName()
        return player and player.realm or nil
    end
    function UnitClass()
        if not player then
            return nil, nil
        end
        return player.className, player.classFile
    end
    function UnitRace()
        return "Human", "Human"
    end
    function UnitFactionGroup()
        return player and player.faction or nil
    end
end

installPlayerApi()

local function login(guid, name, realm, className, classFile)
    now = now + 10
    player = {
        guid = guid,
        name = name,
        realm = realm,
        className = className or "Warrior",
        classFile = classFile or "WARRIOR",
        faction = "Alliance",
    }
    return WBF.Characters.Update()
end

local function namesOf(list)
    local names = {}
    for index = 1, #list do
        names[#names + 1] = list[index].name or "?"
    end
    table.sort(names)
    return table.concat(names, ",")
end

local function summaryNames(view)
    local summary = WBF.Aggregator.Build(view)
    local names = {}
    for index = 1, #summary.characters do
        names[#names + 1] = summary.characters[index].name or "?"
    end
    table.sort(names)
    return table.concat(names, ","), summary
end

local function play(guid, startedAt, endedAt)
    db.sessions[#db.sessions + 1] = {
        id = #db.sessions + 1,
        startedAt = startedAt,
        endedAt = endedAt,
        lastActivityAt = endedAt,
        segments = {
            { guid = guid, startedAt = startedAt, endedAt = endedAt },
        },
    }
end

reset()

login("Player-1-A", "Aldren", "Area 52")
check("fresh install tracks the logged-in character", #WBF.Characters.List() == 1)
local current = WBF.Characters.Get("Player-1-A")
check("fresh install stores guid", current and current.guid == "Player-1-A")
check("fresh install stores name and realm", current and current.name == "Aldren" and current.realm == "Area 52")
check("fresh install stores class", current and current.classFile == "WARRIOR" and current.className == "Warrior")
check("fresh install stores faction", current and current.faction == "Alliance")
check("fresh install marks discovered", current and current.discovered == true)
check("fresh install records firstSeen", current and current.firstSeen == current.lastSeenAt)
check("summary row counts as discovered via its guid", WBF.Characters.IsDiscovered({ guid = "Player-1-A", name = "Aldren" }))
play("Player-1-A", now - 60, now)
local weekNames = summaryNames("week")
check("fresh install week shows only the logged-in character", weekNames == "Aldren", weekNames)

login("Player-2-B", "Bryn", "Area 52", "Mage", "MAGE")
check("second login keeps both characters", namesOf(WBF.Characters.List()) == "Aldren,Bryn", namesOf(WBF.Characters.List()))
play("Player-2-B", now - 30, now)
weekNames = summaryNames("week")
check("week shows both discovered characters", weekNames == "Aldren,Bryn", weekNames)

for index = 3, 26 do
    local guid = "Player-9-" .. index
    db.characters[guid] = {
        guid = guid,
        name = "Alt" .. index,
        discoveredVia = "currency",
    }
    db.events[#db.events + 1] = {
        guid = guid,
        eventType = "resource",
        at = now - 20,
        text = "currency",
    }
end
WBF.GoldTracker.Collect = function()
    local gold = { ["Player-1-A"] = 50 }
    gold["Player-9-3"] = 80
    return 130, true, gold
end
WBF.Characters.Migrate(db)
check("unseen account alts stay out of the roster", namesOf(WBF.Characters.List()) == "Aldren,Bryn", namesOf(WBF.Characters.List()))
check("placeholder record is kept", db.characters["Player-9-3"] ~= nil)
check("placeholder is not discovered", db.characters["Player-9-3"].discovered == false)
local views = { "today", "week", "month", "warband", "last", "current" }
for index = 1, #views do
    local view = views[index]
    local shown = summaryNames(view)
    check(view .. " hides unseen alts", shown == "Aldren,Bryn", shown)
end

local firstSeen = WBF.Characters.Get("Player-1-A").firstSeen
WBF.Characters.Migrate(db)
check("reload keeps discovered characters", namesOf(WBF.Characters.List()) == "Aldren,Bryn")
check("reload keeps firstSeen", WBF.Characters.Get("Player-1-A").firstSeen == firstSeen)

reset()
db.characters["Player-4-OLD"] = {
    guid = "Player-4-OLD",
    name = "Oldrin",
    realm = "Area 52",
    level = 80,
    lastSeenAt = now - 5000,
}
db.snapshots[#db.snapshots + 1] = {
    guid = "Player-4-OLD",
    at = now - 8000,
    level = 70,
}
db.characters["Player-4-EMPTY"] = {
    guid = "Player-4-EMPTY",
    name = "Empty",
    realm = "Area 52",
    discoveredVia = "currency",
}
db.events[#db.events + 1] = {
    guid = "Player-4-EMPTY",
    eventType = "resource",
    at = now - 100,
}
db.events[#db.events + 1] = {
    guid = "Player-4-QUEST",
    eventType = "quest",
    at = now - 900,
    text = "A real quest",
}
WBF.Characters.Migrate(db)
check("history character stays discovered", WBF.Characters.IsDiscovered("Player-4-OLD"))
check("history firstSeen uses the earliest snapshot", WBF.Characters.Get("Player-4-OLD").firstSeen == now - 8000)
check("empty placeholder is hidden", WBF.Characters.IsDiscovered("Player-4-EMPTY") == false)
check("empty placeholder is not deleted", db.characters["Player-4-EMPTY"] ~= nil)
check("resource events do not discover a character", WBF.Characters.Get("Player-4-EMPTY").discovered == false)
check("quest history discovers a missing record", WBF.Characters.IsDiscovered("Player-4-QUEST"))
check("quest history keeps a firstSeen", WBF.Characters.Get("Player-4-QUEST").firstSeen == now - 900)
check("name alone does not discover", WBF.Characters.IsDiscovered("Player-4-EMPTY") == false)

reset()
db.characters["legacy-a52"] = {
    name = "Bob",
    realm = "Area 52",
    level = 70,
    itemLevel = 400,
    lastSeenAt = now - 50,
}
db.characters["legacy-storm"] = {
    name = "Bob",
    realm = "Stormrage",
    level = 60,
    itemLevel = 300,
    lastSeenAt = now - 40,
}
db.snapshots[#db.snapshots + 1] = { guid = "legacy-a52", at = now - 50, level = 70 }
db.sessions[#db.sessions + 1] = {
    id = 1,
    startedAt = now - 50,
    endedAt = now - 45,
    segments = { { guid = "legacy-a52", startedAt = now - 50, endedAt = now - 45 } },
    goldByCharacter = {
        ["legacy-a52"] = { baseline = 10, lastMoney = 12, netChange = 2, establishedAt = now - 50 },
    },
    goldLedger = { { at = now - 48, guid = "legacy-a52", delta = 2 } },
}
local earliestLevelAt = now - 9000
db.lifetime = {
    totals = {},
    characters = {
        ["legacy-a52"] = {
            playedSeconds = 3600,
            counts = { quests = 5 },
            level = 60,
            levelAt = earliestLevelAt,
            crafting = { professions = { Alchemy = { crafts = 3, items = 6, concentrationSpent = 0 } } },
        },
        ["Player-8-A52"] = { playedSeconds = 60, counts = { quests = 1 }, level = 65, levelAt = now - 100 },
        ["legacy-storm"] = { playedSeconds = 99, counts = { quests = 9 } },
    },
    gold = { byGuid = { ["legacy-a52"] = 500, ["legacy-storm"] = 7 }, offlineByGuid = { ["legacy-a52"] = 40 } },
}
WBF.Characters.Migrate(db)
login("Player-8-A52", "Bob", "Area 52")
local life = db.lifetime
local lifeRow = life.characters["Player-8-A52"]
check("lifetime row merges into the adopted guid", lifeRow and lifeRow.playedSeconds == 3660 and lifeRow.counts.quests == 6 and life.characters["legacy-a52"] == nil)
check("lifetime keeps the earliest level", lifeRow and lifeRow.level == 60 and lifeRow.levelAt == earliestLevelAt)
check("lifetime crafting follows the guid", lifeRow and lifeRow.crafting and lifeRow.crafting.professions.Alchemy.crafts == 3)
check("lifetime gold follows the guid", life.gold.byGuid["Player-8-A52"] == 500 and life.gold.byGuid["legacy-a52"] == nil and life.gold.offlineByGuid["Player-8-A52"] == 40)
check("other realm lifetime is untouched", life.characters["legacy-storm"].playedSeconds == 99 and life.gold.byGuid["legacy-storm"] == 7)
local adopted = WBF.Characters.Get("Player-8-A52")
local other = WBF.Characters.Get("legacy-storm")
check("same name on another realm stays separate", other and other.guid ~= "Player-8-A52" and other.level == 60 and other.realm == "Stormrage")
check("login adopts the matching realm record", adopted and adopted.level == 70 and adopted.itemLevel == 400 and adopted.realm == "Area 52")
check("legacy key is removed after adopt", db.characters["legacy-a52"] == nil)
check("adopted history follows the guid", db.snapshots[1].guid == "Player-8-A52" and db.sessions[1].segments[1].guid == "Player-8-A52")
check("adopted gold follows the guid", db.sessions[1].goldByCharacter["Player-8-A52"] ~= nil and db.sessions[1].goldLedger[1].guid == "Player-8-A52")
check("other realm gold was not rewritten", db.sessions[1].goldByCharacter["legacy-storm"] == nil)

reset()
db.characters["Player-7-A"] = {
    guid = "Player-7-A",
    name = "Bob",
    realm = "Area 52",
    level = 80,
    classFile = "WARRIOR",
    discovered = true,
    firstSeen = now - 100,
    lastSeenAt = now - 100,
}
db.characters["Player-7-B"] = {
    guid = "Player-7-B",
    name = "Bob",
    realm = "Stormrage",
    level = 10,
    classFile = "MAGE",
    discovered = true,
    firstSeen = now - 90,
    lastSeenAt = now - 90,
}
login("Player-7-A", "Bob", "Area 52")
check("player guids with the same name are not merged", WBF.Characters.Get("Player-7-B").level == 10 and WBF.Characters.Get("Player-7-B").classFile == "MAGE")
check("logged-in guid keeps its own level", WBF.Characters.Get("Player-7-A").level == 80)

reset()
local shellSeen = now - 20
db.characters["legacy-shell"] = {
    name = "Bob",
    realm = "Area 52",
    level = 70,
    itemLevel = 400,
    lastSeenAt = now - 50,
}
db.characters["Player-8-SHELL"] = {
    guid = "Player-8-SHELL",
    discovered = true,
    firstSeen = shellSeen,
}
login("Player-8-SHELL", "Bob", "Area 52")
local merged = WBF.Characters.Get("Player-8-SHELL")
check("guid shell absorbs the name-realm record", merged and merged.level == 70 and merged.itemLevel == 400 and db.characters["legacy-shell"] == nil)
check("absorbed shell keeps the earlier firstSeen", merged and merged.firstSeen == shellSeen)

reset()
db.characters["legacy-1"] = { name = "Bob", realm = "Area 52", level = 11, lastSeenAt = now - 10 }
db.characters["legacy-2"] = { name = "Bob", realm = "Area 52", level = 22, lastSeenAt = now - 9 }
login("Player-6-C", "Bob", "Area 52", "Rogue", "ROGUE")
check("ambiguous name-realm records are not merged", db.characters["legacy-1"].level == 11 and db.characters["legacy-2"].level == 22)
check("ambiguous login creates its own guid record", WBF.Characters.Get("Player-6-C").classFile == "ROGUE" and WBF.Characters.Get("Player-6-C").level == nil)

reset()
db.characters["Player-5-PLACE"] = {
    guid = "Player-5-PLACE",
    name = "Aldren",
    realm = "Area 52",
    discoveredVia = "currency",
}
login("Player-5-PLACE", "Aldren", "Area 52")
local upgraded = WBF.Characters.Get("Player-5-PLACE")
check("login upgrades a placeholder instead of copying it", upgraded and upgraded.discovered == true and upgraded.classFile == "WARRIOR")
local copies = 0
for _, character in pairs(db.characters) do
    if character.name == "Aldren" then
        copies = copies + 1
    end
end
check("placeholder login does not duplicate the character", copies == 1, tostring(copies))

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("all passed")
