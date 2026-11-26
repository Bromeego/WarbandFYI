-- Dying in a dungeon and running back in from the graveyard is one run, not
-- two. Run from the repo root:
--   lua tests/InstanceRejoinTest.lua

local script = arg and arg[0] or "tests/InstanceRejoinTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

INSTANCE_RESET_SUCCESS = "%s has been reset."

local WBF = {}
local now = 1795600000
local failures = 0
local db = { events = {} }
local where = "world"
local lockout = nil

local function check(name, condition, detail)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  " .. detail) or ""))
end

loadAddon("Utils/Format.lua", WBF)
WBF.Time = { Now = function() return now end }
WBF.Debug = { Log = function() end }
WBF.Database = { Get = function() return db end }
WBF.Sessions = { GetActive = function() return nil end }
WBF.Characters = { GetGuid = function() return "Player-1-A" end }
WBF.EventType = { InstanceEnter = "instanceEnter" }
WBF.Category = { Instance = "instance" }
WBF.Events = {
    Add = function(event)
        event.at = now
        db.events[#db.events + 1] = event
    end,
}

function GetInstanceInfo()
    if where == "world" then
        return "Wetlands", "none", 0, "", 5, 0, false, 0
    end
    local mapID = where == "dig" and 2900 or 2901
    return where == "dig" and "Excavation Site: Wetlands" or "Other Dungeon", "party", 1, "Normal", 5, 0, false, mapID
end
function GetNumSavedInstances()
    return lockout and 1 or 0
end
function GetSavedInstanceInfo()
    return "Excavation Site: Wetlands", lockout, 0, 1, true, false, 0, false, 5, "Normal", 3, 1, false, 2900
end

loadAddon("Tracking/Instances.lua", WBF)
WBF.Instances.Settle()

local function go(place, minutes)
    now = now + (minutes or 1) * 60
    where = place
    WBF.Instances.HandleEnteringWorld(false)
end

local function entries()
    local count = 0
    for index = 1, #db.events do
        if db.events[index].eventType == "instanceEnter" then
            count = count + 1
        end
    end
    return count
end

go("dig")
check("entering records a run", entries() == 1)
lockout = 777 -- a boss died, so the instance is now saved
go("world", 10) -- died and released to the graveyard
go("dig", 3) -- ran back in
check("running back in after dying is the same run", entries() == 1, "entries=" .. entries())

go("world", 5)
go("dig", 31)
check("coming back after the instance would reset is a new run", entries() == 2, "entries=" .. entries())

go("world", 5)
go("other", 1)
go("world", 5)
go("dig", 1)
check("another dungeon in between starts a new run", entries() == 4, "entries=" .. entries())

go("world", 5)
lockout = 888 -- a different saved instance id: a fresh copy
go("dig", 2)
check("a different lockout is a new run", entries() == 5, "entries=" .. entries())

lockout = nil -- normal dungeons have no lockout id
go("world", 5)
go("dig", 1)
local before = entries()
go("world", 10)
WBF.Instances.FromSystemChat("Someone else's message.")
go("dig", 1)
check("an unrelated system message keeps the run", entries() == before, "entries=" .. entries())
go("world", 10)
WBF.Instances.FromSystemChat("Excavation Site: Wetlands has been reset.")
go("dig", 1)
check("resetting instances makes the next entry a new run", entries() == before + 1, "entries=" .. entries())

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("all passed")
