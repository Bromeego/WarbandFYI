-- World activity: rares, fishing catches, and gathering nodes.
--   lua tests/WorldActivityTest.lua

local script = arg and arg[0] or "tests/WorldActivityTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

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
loadAddon("Tracking/ResourceShift.lua", WBF)
loadAddon("Tracking/ResourceBehaviour.lua", WBF)
loadAddon("Tracking/Resources.lua", WBF)
loadAddon("Tracking/WorldActivity.lua", WBF)

WBF.Time.Now = function()
    return now
end
WBF.Time.StartOfDay = function(at)
    return (at or now) - ((at or now) % 86400)
end
WBF.Time.StartOfWeek = function(at)
    return (at or now) - (7 * 86400)
end
WBF.Time.StartOfMonth = function(at)
    return (at or now) - (31 * 86400)
end

local function freshDb()
    WarbandFYI_DB = {
        schemaVersion = 2,
        config = { retentionDays = 120, sessionTimeoutSeconds = 3600 },
        nextIds = { session = 10, event = 10 },
        activeSessionId = nil,
        sessions = {},
        characters = {
            A = { guid = "A", name = "Miranora", discovered = true, classFile = "MAGE" },
            B = { guid = "B", name = "Taxableyawl", discovered = true, classFile = "WARRIOR" },
        },
        snapshots = {},
        events = {},
        dedupe = {},
        goldLast = {},
    }
    WBF.Database.ready = true
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
end

local rareGuid = "Creature-0-1-2-3-999-ABC"
local rareGuid2 = "Creature-0-1-2-3-999-DEF"
local objectGuid = "GameObject-0-1-2-3-50-NODE"
local objectGuid2 = "GameObject-0-1-2-3-51-NODE"
local mobGuid = "Creature-0-1-2-3-20-MOB"
local itemGuid = "Item-0-1-2-3-4"

check("npc id comes from the spawn guid", WBF.WorldActivity.NpcID(rareGuid) == 999)
check("a new spawn is a different guid", WBF.WorldActivity.NpcID(rareGuid2) == 999 and rareGuid ~= rareGuid2)
check("lumber registry knows thalassian and ironwood", WBF.WorldActivity.IsLumber(256963) and WBF.WorldActivity.IsLumber(245586) and not WBF.WorldActivity.IsLumber(12345))
check("lumber registry knows shadowmoon", WBF.WorldActivity.IsLumber(251766) == true)
check("mining profession id", WBF.WorldActivity.ProfessionKind(6) == "mining")
check("herbalism profession id", WBF.WorldActivity.ProfessionKind(4) == "herbalism")
check("skinning profession id", WBF.WorldActivity.ProfessionKind(11) == "skinning")
check("profession name fallback", WBF.WorldActivity.KindFromName("Khaz Algar Mining") == "mining")

Enum = { Profession = { Herbalism = 4, Mining = 6, Skinning = 11 } }
check("enum profession is preferred", WBF.WorldActivity.ProfessionKind(Enum.Profession.Skinning) == "skinning")
check("an unknown profession is not gathering", WBF.WorldActivity.ProfessionKind(3) == nil)

local function rare(fields)
    local observation = {
        guid = rareGuid,
        classification = "rare",
        dead = false,
        tapDenied = nil,
        lootCredit = false,
        blockedInstance = false,
        encounterBlocked = false,
        alreadyCounted = false,
    }
    for key, value in pairs(fields or {}) do
        observation[key] = value
    end
    return WBF.WorldActivity.DecideRare(observation)
end

check("ordinary mob is not a rare", not rare({ classification = "normal", dead = true, tapDenied = false }))
check("elite is not a rare", not rare({ classification = "elite", dead = true, tapDenied = false }))
check("world boss is not a rare", not rare({ classification = "worldboss", lootCredit = true }))
check("rare with unknown credit is not counted", not rare({ dead = true, tapDenied = nil }))
check("rare denied tap is not counted", not rare({ dead = true, tapDenied = true }))
check("rare with explicit credit is counted", rare({ dead = true, tapDenied = false }) == true)
check("rareelite loot credit is counted", rare({ classification = "rareelite", lootCredit = true }) == true)
check("nearby rare without credit is not counted", not rare({ dead = true, tapDenied = true, lootCredit = false }))
check("the same spawn is not counted twice", not rare({ lootCredit = true, alreadyCounted = true }))
check("a later spawn can count", rare({ guid = rareGuid2, lootCredit = true }) == true)
check("a dungeon or raid rare is left to the boss tracker", not rare({ lootCredit = true, blockedInstance = true }))
check("an active encounter is not a rare kill", not rare({ lootCredit = true, encounterBlocked = true }))

local function loot(fields)
    local state = fields.state or { now = now, sources = {} }
    fields.state = nil
    return WBF.WorldActivity.DecideLoot(fields, state)
end

local function slot(itemID, name, quantity, guid, extra)
    local row = { itemID = itemID, name = name, quantity = quantity, sources = guid and { { guid = guid } } or {} }
    for key, value in pairs(extra or {}) do
        row[key] = value
    end
    return row
end

local caught = loot({
    fishing = true,
    slots = {
        slot(1, "Midnight Salmon", 2, objectGuid),
        slot(2, "Silvergill", 1, objectGuid),
        slot(3, "Bonus", 1, objectGuid),
    },
})
check("one fishing window is one catch", caught.fishing ~= nil and #caught.nodes == 0)
check("catch keeps every item", caught.fishing and #caught.fishing.items == 3)

local again = loot({
    fishing = true,
    slots = { slot(1, "Midnight Salmon", 2, objectGuid) },
    state = { now = now, sources = { [objectGuid] = now - 5 } },
})
check("the same bobber is not a second catch", again.fishing == nil)

local missed = loot({ fishing = false, slots = { slot(1, "Midnight Salmon", 1, objectGuid) } })
check("a normal loot window is not fishing", missed.fishing == nil and #missed.nodes == 0)

local mined = loot({
    slots = {
        slot(10, "Ore", 5, objectGuid),
        slot(11, "Stone", 2, objectGuid),
        slot(12, "Rare reagent", 1, objectGuid),
    },
    state = { now = now, pending = { at = now, kind = "mining" }, sources = {} },
})
check("several mining items are one node", #mined.nodes == 1 and mined.nodes[1].kind == "mining" and mined.nodes[1].itemCount == 3)

local minedAgain = loot({
    slots = { slot(10, "Ore", 5, objectGuid) },
    state = { now = now, pending = { at = now, kind = "mining" }, sources = { [objectGuid] = now - 1 } },
})
check("the same node guid is not counted twice", #minedAgain.nodes == 0)

local mobOre = loot({
    slots = { slot(10, "Ore", 5, mobGuid, { classID = 7, subClassID = 7 }) },
    state = { now = now, allowItemKind = true, pending = { at = now }, sources = {} },
})
check("ore on a creature is not a mining node", #mobOre.nodes == 0)

local mailed = loot({
    fromItem = true,
    slots = { slot(10, "Ore", 5, objectGuid) },
    state = { now = now, pending = { at = now, kind = "mining" }, sources = {} },
})
check("item-container loot is not a node", #mailed.nodes == 0)

local herb = loot({
    slots = {
        slot(20, "Herb", 2, objectGuid2),
        slot(21, "Petal", 1, objectGuid2),
    },
    state = { now = now, pending = { at = now - 1, kind = "herbalism" }, sources = {} },
})
check("an herb node counts once", #herb.nodes == 1 and herb.nodes[1].kind == "herbalism")

local lateHerb = loot({
    slots = { slot(20, "Herb", 1, objectGuid2) },
    state = { now = now, pending = { at = now - 10, kind = "herbalism" }, sources = {} },
})
check("a stale herbalism cast does not count", #lateHerb.nodes == 0)

local lumber = loot({
    slots = { slot(256963, "Thalassian Lumber", 2, objectGuid) },
    state = { now = now, pending = { at = now }, sources = {} },
})
check("thalassian lumber is one lumber node", #lumber.nodes == 1 and lumber.nodes[1].kind == "lumber")

local otherLumber = loot({
    slots = { slot(245586, "Ironwood Lumber", 1, objectGuid2) },
    state = { now = now, pending = { at = now }, sources = {} },
})
check("a second lumber type is also lumber", #otherLumber.nodes == 1 and otherLumber.nodes[1].kind == "lumber")

local function noteHas(result, text)
    for index = 1, #(result.notes or {}) do
        if type(result.notes[index]) == "string" and result.notes[index]:find(text, 1, true) then
            return true
        end
    end
    return false
end

local function applyNodes(session, decision, at)
    local added = 0
    for index = 1, #decision.nodes do
        local node = decision.nodes[index]
        if WBF.WorldActivity.RememberSource(session, node.sourceGUID, at) and WBF.WorldActivity.AddCount(session, "A", at, node.kind, node.items, nil, true) then
            added = added + 1
        end
    end
    return added
end

local shadowmoonGuid = "GameObject-0-1-2-3-80-TREE"
local shadowmoon = slot(251766, "Shadowmoon Lumber", 3, shadowmoonGuid)

local noCast = loot({
    slots = { shadowmoon },
    state = { now = now, sources = {} },
})
check("shadowmoon lumber without a cast is one node", #noCast.nodes == 1 and noCast.nodes[1].kind == "lumber" and noCast.nodes[1].items[1].quantity == 3)
check("lumber debug names the gameobject and the item", noteHas(noCast, "Source: " .. shadowmoonGuid) and noteHas(noCast, "Type: GameObject") and noteHas(noCast, "251766 Shadowmoon Lumber x3") and noteHas(noCast, "Lumber match: yes") and noteHas(noCast, "Recent gather cast: none") and noteHas(noCast, "Classification: LUMBER") and noteHas(noCast, "Dedupe: new") and noteHas(noCast, "Node recorded: yes"))

local withCast = loot({
    slots = { shadowmoon },
    state = { now = now, pending = { at = now, spellID = 1259765 }, sources = {} },
})
check("shadowmoon lumber with a cast is still one node", #withCast.nodes == 1 and withCast.nodes[1].kind == "lumber")
check("lumber debug keeps the recent cast", noteHas(withCast, "Recent gather cast: spell 1259765") and noteHas(withCast, "Classification: LUMBER"))

local bonus = loot({
    slots = {
        shadowmoon,
        slot(99, "Green BoE", 1, shadowmoonGuid),
    },
    state = { now = now, sources = {} },
})
check("bonus loot on a lumber node still counts once", #bonus.nodes == 1 and bonus.nodes[1].kind == "lumber" and #bonus.nodes[1].items == 1 and bonus.nodes[1].items[1].itemID == 251766)

local harvest = { world = nil }
local ready = { slots = { shadowmoon } }
local opened = WBF.WorldActivity.PreserveLootSources(ready, {
    slots = { { itemID = 251766, name = "Shadowmoon Lumber", quantity = 3, sources = {} } },
})
check("a later read keeps the cached gameobject source", opened.slots[1].sources[1].guid == shadowmoonGuid)
local firstPass = applyNodes(harvest, WBF.WorldActivity.DecideLoot(ready, { now = now, sources = {} }), now)
local secondPass = applyNodes(harvest, WBF.WorldActivity.DecideLoot(opened, { now = now, sources = harvest.world.sources }), now)
local chatPass = applyNodes(harvest, WBF.WorldActivity.DecideLoot(ready, { now = now + 1, sources = harvest.world.sources }), now + 1)
local harvested = WBF.WorldActivity.Collect({ sessions = { harvest } }, 0, now + 10)
check("one tree recorded through ready, opened, and a repeat is lumber +1", firstPass == 1 and secondPass == 0 and chatPass == 0 and harvested.lumber == 1)

local duplicate = loot({
    slots = { shadowmoon },
    state = { now = now + 2, sources = harvest.world.sources },
})
check("the same tree is rejected as a duplicate", #duplicate.nodes == 0 and noteHas(duplicate, "Classification: rejected") and noteHas(duplicate, "Reason: already recorded") and noteHas(duplicate, "Dedupe: duplicate") and noteHas(duplicate, "Node recorded: no"))

local reloaded = loot({
    slots = { shadowmoon },
    state = { now = now + 30, sources = harvest.world.sources },
})
local reloadAdded = applyNodes(harvest, reloaded, now + 30)
local afterReload = WBF.WorldActivity.Collect({ sessions = { harvest } }, 0, now + 40)
check("reload does not record the harvested tree again", #reloaded.nodes == 0 and reloadAdded == 0 and afterReload.lumber == 1)

local vendor = loot({
    slots = { { itemID = 251766, name = "Shadowmoon Lumber", quantity = 3, sources = {} } },
    state = { now = now, sources = {} },
})
check("vendor lumber without a gameobject source is not a node", #vendor.nodes == 0 and noteHas(vendor, "Reason: no GameObject loot source"))

local mailed = loot({
    fromItem = true,
    slots = { shadowmoon },
    state = { now = now, sources = {} },
})
check("mail lumber from an item container is not a node", #mailed.nodes == 0 and noteHas(mailed, "Reason: item container"))

local bankLumber = loot({
    slots = { slot(251766, "Shadowmoon Lumber", 1, itemGuid) },
    state = { now = now, sources = {} },
})
check("bank lumber from an item guid is not a node", #bankLumber.nodes == 0 and noteHas(bankLumber, "Reason: not a GameObject") and noteHas(bankLumber, "Type: Item"))

local warbandBank = loot({
    slots = { slot(251766, "Shadowmoon Lumber", 5, "Item-0-9-9-9-9") },
    state = { now = now, sources = {} },
})
check("warband bank lumber is not a node", #warbandBank.nodes == 0 and noteHas(warbandBank, "Reason: not a GameObject"))

local creatureLumber = loot({
    slots = { slot(251766, "Shadowmoon Lumber", 1, mobGuid) },
    state = { now = now, sources = {} },
})
check("creature loot containing lumber is not a node", #creatureLumber.nodes == 0 and noteHas(creatureLumber, "Type: Creature") and noteHas(creatureLumber, "Reason: not a GameObject"))

local bareOre = loot({
    slots = { slot(10, "Ore", 5, objectGuid, { classID = 7, subClassID = 7 }) },
    state = { now = now, sources = {} },
})
check("ore without a mining cast is not a node", #bareOre.nodes == 0)

local skinned = loot({
    slots = { slot(40, "Leather", 3, mobGuid) },
    state = { now = now, pending = { at = now, kind = "skinning" }, sources = {} },
})
check("a skinning cast on a creature counts once", #skinned.nodes == 1 and skinned.nodes[1].kind == "skinning")

local leatherDrop = loot({
    slots = { slot(40, "Leather", 3, mobGuid) },
    state = { now = now, sources = {} },
})
check("leather without a skinning cast is not skinning", #leatherDrop.nodes == 0)

local classOre = loot({
    slots = { slot(10, "Ore", 4, objectGuid, { classID = 7, subClassID = 7 }) },
    state = { now = now, allowItemKind = true, pending = { at = now, gathering = true }, sources = {} },
})
check("a confirmed gather cast can use ore item class", #classOre.nodes == 1 and classOre.nodes[1].kind == "mining")

local twoNodes = loot({
    slots = {
        slot(10, "Ore", 1, objectGuid),
        slot(10, "Ore", 1, objectGuid2),
    },
    state = { now = now, pending = { at = now, kind = "mining" }, sources = {} },
})
check("two source guids are two nodes", #twoNodes.nodes == 2)

freshDb()
local session = { id = 1, startedAt = now - 100, endedAt = nil, world = nil }
for _ = 1, 25 do
    WBF.WorldActivity.AddCount(session, "A", now, "fishing", { { itemID = 1, name = "Midnight Salmon", quantity = 2 } }, 42, true)
end
check("a burst of catches stays one row", #session.world.rows == 1 and session.world.rows[1].n == 25)
check("catch items add up inside the row", session.world.rows[1].items[1].q == 50)
check("fishing does not create activity events", #WarbandFYI_DB.events == 0)

WBF.WorldActivity.AddCount(session, "A", now + 120, "mining", nil, 42, true)
WBF.WorldActivity.AddCount(session, "B", now + 130, "lumber", { { itemID = 256963, name = "Thalassian Lumber", quantity = 1 } }, 42, true)
local totals, byGuid = WBF.WorldActivity.Collect({ sessions = { session } }, now - 10, now + 200)
check("session totals keep each kind", totals.fishing == 25 and totals.mining == 1 and totals.lumber == 1, "fishing=" .. tostring(totals.fishing))
check("characters do not share counts", byGuid.A.fishing == 25 and byGuid.A.mining == 1 and byGuid.B.lumber == 1 and byGuid.B.fishing == nil)

local seen = WBF.WorldActivity.RememberSource(session, objectGuid, now)
local seenAgain = WBF.WorldActivity.RememberSource(session, objectGuid, now + 5)
check("source dedupe survives in the session", seen == true and seenAgain == false)

local life = { totals = {}, characters = {} }
WBF.WorldActivity.FoldSession(life, session)
local foldedAgain = life.totals.fishing
WBF.WorldActivity.FoldSession(life, session)
check("folding a session once keeps the fishing total", life.totals.fishing == 25 and life.totals.mining == 1 and life.totals.lumber == 1)
check("a second fold does not add the session again", life.totals.fishing == foldedAgain and life.characters.A.counts.fishing == 25 and life.characters.B.counts.lumber == 1)
local afterFold = WBF.WorldActivity.Collect({ sessions = { session } }, 0, now + 500)
check("a folded session is not collected again", afterFold.fishing == 0 and afterFold.mining == 0)

freshDb()
local old = now - (200 * 86400)
WarbandFYI_DB.sessions = {
    {
        id = 1,
        startedAt = old,
        endedAt = old + 1000,
        segments = { { guid = "A", startedAt = old, endedAt = old + 1000 } },
        goldByCharacter = {},
        goldLedger = {},
        world = {
            rows = {
                { at = old + 10, guid = "A", kind = "fishing", n = 4 },
                { at = old + 20, guid = "A", kind = "mining", n = 2 },
            },
        },
    },
}
WarbandFYI_DB.events = {
    {
        id = 1,
        at = old + 30,
        guid = "A",
        eventType = "rareKill",
        text = "Rare defeated: Doomhowl",
        meta = { name = "Doomhowl", classification = "rare" },
    },
}
local removed = WBF.Database.Prune(true)
check("retention removes the old session and rare", removed >= 2, "removed=" .. tostring(removed))
check("lifetime keeps fishing and mining", WarbandFYI_DB.lifetime.totals.fishing == 4 and WarbandFYI_DB.lifetime.totals.mining == 2)
check("lifetime keeps the rare", WarbandFYI_DB.lifetime.totals.rares == 1)
local removedAgain = WBF.Database.Prune(true)
check("pruning again does not double world totals", removedAgain == 0 and WarbandFYI_DB.lifetime.totals.fishing == 4 and WarbandFYI_DB.lifetime.totals.rares == 1)

WarbandFYI_DB.activeSessionId = 2
WarbandFYI_DB.sessions = {
    {
        id = 2,
        startedAt = now - 500,
        endedAt = nil,
        segments = { { guid = "A", startedAt = now - 500, endedAt = nil } },
        goldByCharacter = {},
        goldLedger = {},
        world = {
            rows = {
                { at = now - 100, guid = "A", kind = "fishing", n = 3 },
                { at = now - 90, guid = "B", kind = "herbalism", n = 1 },
            },
        },
    },
}
WBF.Aggregator.MarkDirty()
local warband = WBF.Aggregator.Build("warband")
local week = WBF.Aggregator.Build("week")
check("all time keeps pruned and current fishing", warband.totals.fishing == 7, "fishing=" .. tostring(warband.totals.fishing))
check("all time keeps the pruned rare", warband.totals.rares == 1, "rares=" .. tostring(warband.totals.rares))
check("this week does not include pruned fishing", week.totals.fishing == 3 and week.totals.mining == 0, "fishing=" .. tostring(week.totals.fishing))
check("this week attributes herbalism to the other character", week.totals.herbalism == 1)

local line = WBF.Format.ActivityLine({
    raids = 0,
    dungeons = 0,
    mythicPlus = 0,
    bosses = 0,
    delves = 1,
    highestDelve = 0,
    rares = 7,
    fishing = 23,
    mining = 18,
    herbalism = 0,
    lumber = 11,
    skinning = 0,
    curseSurges = 0,
    worldEvents = 0,
    quests = 0,
    worldQuests = 0,
    achievements = 0,
    appearances = 0,
    mounts = 0,
    pets = 0,
    reputation = 0,
    renown = 0,
    professions = 0,
}, 4350000)
check("progress line includes rares, fishing, mining, and lumber", line and line:find("7 Rares", 1, true) and line:find("23 Fishing Catches", 1, true) and line:find("18 Mining Nodes", 1, true) and line:find("11 Lumber", 1, true), line)

if failures > 0 then
    print(failures .. " world activity checks failed")
    os.exit(1)
end
print("All world activity checks passed")
