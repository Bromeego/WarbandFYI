-- Noisy game events: batched Notebook refreshes, the throttled quest log
-- scan, and rare checks on health ticks. Run from the repo root:
--   lua tests/EventThrottleTest.lua

local script = arg and arg[0] or "tests/EventThrottleTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

local failures = 0
local function check(name, condition, detail)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  " .. detail) or ""))
end

-- Timers run only when the test says so.
local timers = {}
C_Timer = {
    After = function(_, callback)
        timers[#timers + 1] = callback
    end,
}
local function runTimers()
    local due = timers
    timers = {}
    for index = 1, #due do
        due[index]()
    end
end

local inCombat = false
InCombatLockdown = function()
    return inCombat
end
local clock = 100
GetTime = function()
    return clock
end

local WBF = {}
loadAddon("Utils/Format.lua", WBF)
loadAddon("Utils/Time.lua", WBF)
loadAddon("Utils/Debug.lua", WBF)
WBF.Time.Now = function()
    return 1750000000
end

------------------------------------------------------------------------
-- Notebook: event-driven refreshes are batched.

loadAddon("Core/Notebook.lua", WBF)
local windowRefreshes = 0
local fyiRefreshes = 0
WBF.UI = {
    frame = {
        IsShown = function()
            return true
        end,
        Refresh = function()
            windowRefreshes = windowRefreshes + 1
        end,
    },
    Fyi = {
        Refresh = function()
            fyiRefreshes = fyiRefreshes + 1
        end,
    },
}

for _ = 1, 40 do
    WBF.Notebook.RequestRefreshOpen()
end
check("a burst waits for the timer", windowRefreshes == 0)
runTimers()
check("a burst of 40 requests redraws the window once", windowRefreshes == 1, tostring(windowRefreshes))
check("the FYI is refreshed once with it", fyiRefreshes == 1, tostring(fyiRefreshes))

windowRefreshes, fyiRefreshes = 0, 0
WBF.Notebook.RequestRefreshOpen(false)
WBF.Notebook.RequestRefreshOpen(false)
runTimers()
check("FYI-only requests leave the window alone", windowRefreshes == 0 and fyiRefreshes == 1)

windowRefreshes, fyiRefreshes = 0, 0
WBF.Notebook.RequestRefreshOpen(false)
WBF.Notebook.RequestRefreshOpen()
runTimers()
check("one window request in the burst redraws the window", windowRefreshes == 1)

windowRefreshes, fyiRefreshes = 0, 0
inCombat = true
WBF.Notebook.RequestRefreshOpen()
runTimers()
check("nothing redraws during combat", windowRefreshes == 0 and fyiRefreshes == 0)
inCombat = false
WBF.Notebook.OnRegen()
check("the held refresh runs when combat ends", windowRefreshes == 1)
WBF.Notebook.OnRegen()
check("and only once", windowRefreshes == 1)

windowRefreshes = 0
WBF.Notebook.RefreshOpen()
check("RefreshOpen for the player's own edits is still instant", windowRefreshes == 1)

------------------------------------------------------------------------
-- QuestVisibility: QUEST_LOG_UPDATE scans at most once a second.

local scans = 0
C_QuestLog = {
    GetNumQuestLogEntries = function()
        scans = scans + 1
        return 1
    end,
    GetInfo = function()
        return { questID = 77, title = "Plain quest" }
    end,
}
loadAddon("Tracking/QuestVisibility.lua", WBF)
local questHandlers = {}
WBF.QuestVisibility.Register({
    On = function(_, event, callback)
        questHandlers[event] = callback
    end,
})
timers = {}
scans = 0
clock = 200
questHandlers.QUEST_LOG_UPDATE()
check("the first update scans straight away", scans == 1)
for _ = 1, 30 do
    questHandlers.QUEST_LOG_UPDATE()
end
check("the rest of the burst waits", scans == 1)
check("one trailing scan is queued", #timers == 1, tostring(#timers))
clock = 201
runTimers()
check("the trailing scan reads the last update", scans == 2)
clock = 203
questHandlers.QUEST_LOG_UPDATE()
check("an update after the interval scans straight away", scans == 3)
C_QuestLog = nil

------------------------------------------------------------------------
-- WorldActivity: health ticks re-check only units known to be rares.

local units = {
    target = { guid = "Creature-0-0-0-0-1001-0", classification = "normal", name = "Boar" },
}
local classifications = 0
UnitExists = function(unit)
    return units[unit] ~= nil
end
UnitGUID = function(unit)
    return units[unit] and units[unit].guid
end
UnitClassification = function(unit)
    classifications = classifications + 1
    return units[unit] and units[unit].classification
end
UnitName = function(unit)
    return units[unit] and units[unit].name
end
UnitIsDead = function()
    return false
end
UnitIsTapDenied = function()
    return false
end

loadAddon("Tracking/WorldActivity.lua", WBF)
local activity = {}
WBF.WorldActivity.Register({
    On = function(_, event, callback)
        activity[event] = callback
    end,
})

activity.PLAYER_TARGET_CHANGED()
classifications = 0
for _ = 1, 20 do
    activity.UNIT_HEALTH("target")
end
check("health ticks on an ordinary target are skipped", classifications == 0, tostring(classifications))

units.target = { guid = "Creature-0-0-0-0-2002-0", classification = "rare", name = "Old Grizzle" }
activity.PLAYER_TARGET_CHANGED()
classifications = 0
activity.UNIT_HEALTH("target")
check("health ticks on a rare target are still inspected", classifications == 1)

units.target = { guid = "Creature-0-0-0-0-1003-0", classification = "normal", name = "Wolf" }
activity.PLAYER_TARGET_CHANGED()
classifications = 0
activity.UNIT_HEALTH("target")
activity.UNIT_HEALTH("target")
check("switching from a rare to an ordinary target stops the checks", classifications == 0, tostring(classifications))

units.nameplate3 = { guid = "Creature-0-0-0-0-2004-0", classification = "rareelite", name = "Skyfang" }
activity.NAME_PLATE_UNIT_ADDED("nameplate3")
classifications = 0
activity.UNIT_HEALTH("nameplate3")
check("a rare nameplate is still followed", classifications == 1)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All event throttle checks passed")
