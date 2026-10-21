-- Curse Surge completions are public events, not quests. Run from the repo root:
--   lua tests/QuestClassificationTest.lua

local script = arg and arg[0] or "tests/QuestClassificationTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

local WBF = {}
local now = 100000
local added = {}
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
loadAddon("Tracking/QuestVisibility.lua", WBF)
loadAddon("Tracking/Quests.lua", WBF)
loadAddon("Core/Aggregator.lua", WBF)

WBF.Time.Now = function()
    return now
end

WBF.Events.Add = function(partial)
    local event = {
        eventType = partial.eventType,
        text = partial.text,
        meta = partial.meta,
        category = partial.category,
    }
    added[#added + 1] = event
    return event
end

local handlers = {}
WBF.Quests.Register({
    On = function(_, eventName, handler)
        handlers[eventName] = handler
    end,
})

local function turnIn(questID)
    local before = #added
    handlers.QUEST_TURNED_IN(questID)
    return added[#added], #added - before
end

now = 100000
local generic, genericAdded = turnIn(96935)
check("generic Curse Surge is a world event", generic and generic.eventType == WBF.EventType.WorldEvent and genericAdded == 1)
check("generic Curse Surge is not a quest", generic and generic.eventType ~= WBF.EventType.Quest)
check("generic Curse Surge text", generic and generic.text == "Curse Surge completed", generic and generic.text)
check("generic Curse Surge meta", generic and generic.meta.worldEvent == "curseSurge" and generic.meta.questID == 96935)

now = 100100
local looming, loomingAdded = turnIn(93718)
check("Looming Mutagenitor quest is a Curse Surge", loomingAdded == 1 and looming.meta.worldEvent == "curseSurge")
check("Looming Mutagenitor keeps its variant", looming and looming.text == "Curse Surge completed: The Looming Mutagenitor", looming and looming.text)
check("Looming Mutagenitor poi id", looming and looming.meta.areaPoiID == 8936 and looming.meta.questID == 93718)

now = 100200
local marsh = turnIn(93722)
check("Whispering Marsh variant", marsh and marsh.text == "Curse Surge completed: Siege at the Whispering Marsh", marsh and marsh.text)

now = 100300
local nest = turnIn(93676)
check("Broodmother variant", nest and nest.meta.variant == "The Broodmother's Nest")

now = 100400
local massacre = turnIn(93715)
check("Mlurkkr Massacre variant", massacre and massacre.meta.variant == "Mlurkkr Massacre")

now = 100500
local leviathan = turnIn(93673)
check("Malformed Leviathan variant", leviathan and leviathan.meta.variant == "The Malformed Leviathan")

now = 100600
local weekly, weeklyAdded = turnIn(96995)
check("weekly Turn Back the Surge stays a quest", weeklyAdded == 1 and weekly.eventType == WBF.EventType.Quest and weekly.meta.questID == 96995)

now = 100700
local urge = turnIn(86775)
check("Urge to Surge stays a quest", urge and urge.eventType == WBF.EventType.Quest and urge.meta.worldEvent == nil)

now = 100800
local beforePair = #added
local firstGeneric = turnIn(96935)
now = 100810
local secondAdded = select(2, turnIn(93718))
check("variant turn-in upgrades the generic completion", secondAdded == 0 and #added == beforePair + 1)
check("upgraded record uses the variant", firstGeneric.text == "Curse Surge completed: The Looming Mutagenitor" and firstGeneric.meta.questID == 93718, firstGeneric.text)

now = 100900
local brood = turnIn(93676)
now = 100910
local followGeneric = select(2, turnIn(96935))
check("generic completion after a variant is not a second surge", followGeneric == 0 and brood.meta.questID == 93676)

now = 101000
local beforeRepeat = #added
turnIn(96935)
now = 101010
turnIn(96935)
check("two generic completions both count", #added == beforeRepeat + 2)

local stored = {
    eventType = "quest",
    text = "Quest completed: Curse Surge",
    meta = { questID = 96935, title = "Curse Surge" },
}
check("saved quest row reads as a Curse Surge", WBF.Quests.EffectiveType(stored) == WBF.EventType.WorldEvent)
check("saved quest row text", WBF.Quests.ActivityText(stored) == "Curse Surge completed")
check("activity suffix is kept", WBF.Quests.ActivityText({
    eventType = "quest",
    text = "Quest completed: Curse Surge   —   Miranora",
    meta = { questID = 96935, title = "Curse Surge" },
}) == "Curse Surge completed   —   Miranora")

local bucket = {}
WBF.Aggregator.CountEvent(bucket, stored)
WBF.Aggregator.CountEvent(bucket, { eventType = "quest", meta = { questID = 100, title = "A Real Quest" } })
WBF.Aggregator.CountEvent(bucket, { eventType = "worldQuest", meta = { questID = 200, worldQuest = true } })
WBF.Aggregator.CountEvent(bucket, { eventType = "worldEvent", meta = { worldEvent = "curseSurge", questID = 93718 } })
WBF.Aggregator.CountEvent(bucket, { eventType = "worldEvent", meta = { worldEvent = "other", title = "Night Market" } })
check("saved Curse Surge does not increment quests", bucket.quests == 1, tostring(bucket.quests))
check("world quests stay separate", bucket.worldQuests == 1, tostring(bucket.worldQuests))
check("curse surge count", bucket.curseSurges == 2, tostring(bucket.curseSurges))
check("other world events stay separate", bucket.worldEvents == 1, tostring(bucket.worldEvents))

local line = WBF.Format.ActivityLine({
    raids = 0,
    dungeons = 0,
    mythicPlus = 0,
    bosses = 0,
    delves = 0,
    curseSurges = 1,
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
}, 0)
check("session line says Curse Surge", line == "1 Curse Surge", line)

C_EventScheduler = {
    GetOngoingEvents = function()
        return {
            { areaPoiID = 8938 },
            { areaPoiID = 42, startTime = now + 1000, endTime = now + 2000 },
        }
    end,
    GetScheduledEvents = function()
        return {
            { areaPoiID = 8940, startTime = now + 5000, endTime = now + 8000 },
        }
    end,
}
C_AreaPoiInfo = {
    GetAreaPOIInfo = function(_, areaPoiID)
        if areaPoiID == 8938 then
            return { name = "Curse Surge: The Broodmother's Nest" }
        end
    end,
}
C_Map = {
    GetBestMapForUnit = function()
        return 2512
    end,
    GetMapInfo = function()
        return { name = "The Coiled Isle" }
    end,
}
now = 103000
local named = turnIn(96935)
check("active surge names the generic completion", named and named.text == "Curse Surge completed: The Broodmother's Nest", named and named.text)
check("active surge records the poi", named and named.meta.areaPoiID == 8938 and named.meta.zone == "The Coiled Isle")
C_EventScheduler = nil
C_AreaPoiInfo = nil
C_Map = nil

C_QuestLog = {
    GetTitleForQuestID = function()
        return "<DNT> Scenario Advance"
    end,
}
now = 102000
local beforeHidden = #added
turnIn(424242)
C_QuestLog = nil
check("authoring quests are still dropped", #added == beforeHidden)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("all passed")
