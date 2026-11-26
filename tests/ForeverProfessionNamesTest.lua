-- WoW: Forever reports Classic-era skill lines with the expansion "Unknown".
-- That must not become "Unknown Leatherworking", and records already saved
-- under that name are cleaned up once. Run from the repo root:
--   lua tests/ForeverProfessionNamesTest.lua

local script = arg and arg[0] or "tests/ForeverProfessionNamesTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

function date(fmt, ts)
    return os.date(fmt, ts)
end

function time(parts)
    if type(parts) == "table" then
        return os.time(parts)
    end
    return os.time()
end

function strtrim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

ERR_SKILL_UP_SI = "Your skill in %s has increased to %d."
ERR_SKILL_GAINED_S = "You have gained the %s skill."

local WBF = {}
local now = os.time({ year = 2026, month = 11, day = 26, hour = 12 })
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
loadAddon("Core/MonthHistory.lua", WBF)
loadAddon("Core/Database.lua", WBF)
loadAddon("Tracking/Professions.lua", WBF)

WBF.Time.Now = function()
    return now
end

local GUID = "Player-1-A"

local function skillUp(id, at, name, previous, new)
    return {
        id = id, at = at, guid = GUID, eventType = "profession", category = "profession",
        text = name .. "  " .. previous .. " -> " .. new,
        previous = previous, new = new, delta = new - previous,
        meta = { profession = name, skillUp = true, eventLabel = name .. " increased" },
    }
end

-- Expansion names ------------------------------------------------------------

check("Unknown is not an expansion", WBF.Professions.ExpansionName({ expansionName = "Unknown" }) == nil)
check("blank is not an expansion", WBF.Professions.ExpansionName({ expansionName = "  " }) == nil)
check("a real tier is kept", WBF.Professions.ExpansionName({ expansionName = "Khaz Algar" }) == "Khaz Algar")

-- One-time cleanup -------------------------------------------------------------

WarbandFYI_DB = {
    schemaVersion = 7,
    config = { retentionDays = 120, sessionTimeoutSeconds = 3600 },
    nextIds = { session = 10, event = 10 },
    sessions = {},
    characters = {
        [GUID] = {
            guid = GUID, name = "Miranora", classFile = "DRUID", discovered = true,
            professionNames = { ["165"] = "Unknown Leatherworking", ["393"] = "Unknown Skinning" },
            professions = {
                [165] = { skillLineID = 165, name = "Leatherworking", expansionName = "Unknown", label = "Unknown Leatherworking", skill = 153, maxSkill = 225 },
            },
        },
    },
    snapshots = {},
    events = {
        skillUp(1, now - 600, "Leatherworking", 126, 127),
        skillUp(2, now - 598, "Unknown Leatherworking", 126, 127),
        skillUp(3, now - 300, "Leatherworking", 127, 128),
        skillUp(4, now - 299, "Unknown Leatherworking", 127, 128),
        -- Retail: the parent's twin is the Classic tier.
        skillUp(6, now - 200, "Classic Mining", 299, 300),
        skillUp(7, now - 199, "Unknown Mining", 299, 300),
        -- Only the scan saw this one: kept, renamed.
        skillUp(5, now - 100, "Unknown Skinning", 206, 225),
    },
    dedupe = {},
    goldLast = {},
    monthHistory = {},
    resources = { balances = {} },
}
WBF.Database.ready = true
WBF.Database.Init()

local db = WarbandFYI_DB
local names = {}
for index = 1, #db.events do
    local event = db.events[index]
    if event.eventType == "profession" then
        names[#names + 1] = event.meta.profession
    end
end
check("schema advanced to 8", db.schemaVersion == 8, "schema=" .. tostring(db.schemaVersion))
check("duplicate Unknown records removed", #names == 4, "profession events=" .. #names)
for index = 1, #names do
    check("no Unknown name left: " .. names[index], names[index]:find("Unknown", 1, true) == nil)
end
local skinning
for index = 1, #db.events do
    if db.events[index].id == 5 then
        skinning = db.events[index]
    end
end
check("scan-only record is kept and renamed", skinning and skinning.meta.profession == "Skinning"
    and skinning.text == "Skinning  206 -> 225" and skinning.meta.eventLabel == "Skinning increased")
local character = db.characters[GUID]
check("stored names lose the prefix", character.professionNames["165"] == "Leatherworking" and character.professionNames["393"] == "Skinning")
check("snapshot label loses the prefix", character.professions[165].label == "Leatherworking" and character.professions[165].expansionName == nil)

-- Live scan --------------------------------------------------------------------

local rank = 153
local LINES = {
    [165] = { professionName = "Leatherworking", expansionName = "Unknown", profession = 2 },
    [2945] = { professionName = "Leatherworking", expansionName = "Leatherworking", profession = 2 },
}
C_TradeSkillUI = {
    GetAllProfessionTradeSkillLines = function()
        return { 165, 2945 }
    end,
    GetProfessionInfoBySkillLineID = function(id)
        local line = LINES[id]
        return { professionName = line.professionName, expansionName = line.expansionName, profession = line.profession,
            skillLevel = rank, maxSkillLevel = 225, isPrimaryProfession = true }
    end,
}
WBF.Characters.GetCurrent = function()
    return character
end

-- Saved before parent lines were skipped: both cards stored.
local stale = {
    professions = {
        [165] = { skillLineID = 165, name = "Leatherworking", label = "Leatherworking", professionEnum = 2, isPrimary = true },
        [2945] = { skillLineID = 2945, name = "Leatherworking", expansionName = "Leatherworking", label = "Leatherworking", professionEnum = 2, isPrimary = true },
        [393] = { skillLineID = 393, name = "Skinning", label = "Skinning", professionEnum = 11, isPrimary = true },
    },
}
local shown = WBF.Professions.Snapshots(stale)
check("a stored parent beside its tier is hidden", #shown == 2 and shown[1].skillLineID ~= 165 and shown[2].skillLineID ~= 165)

local before = #db.events
WBF.Professions.Scan()
check("scan stores the tier under its plain name", character.professionNames["2945"] == "Leatherworking")
check("scan drops the parent line", character.professions[165] == nil and character.professionNames["165"] == nil)
check("one Leatherworking card", #WBF.Professions.Snapshots(character) == 1, "cards=" .. #WBF.Professions.Snapshots(character))

rank = 154
WBF.Professions.FromChat("Your skill in Leatherworking has increased to 154.")
WBF.Professions.Scan()
local added = {}
for index = before + 1, #db.events do
    added[#added + 1] = db.events[index].meta.profession
end
check("chat and scan record one skill-up together", #added == 1 and added[1] == "Leatherworking",
    "added=" .. table.concat(added, ","))

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("all passed")
