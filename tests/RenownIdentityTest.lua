-- Renown identity. Run from the repo root:
--   lua tests/RenownIdentityTest.lua

local script = arg and arg[0] or "tests/RenownIdentityTest.lua"
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
local now = 5000
local failures = 0
local factions = {}

local function resetDb()
    now = now + 100
    db = {
        config = {},
        events = {},
        characters = {
            A = { guid = "A", name = "Miranora", discovered = true },
        },
        nextIds = { event = 1 },
    }
    factions = {}
end

WBF.Time = { Now = function() return now end }
WBF.Debug = { Log = function() end }
WBF.Database = {
    IsReady = function() return true end,
    Get = function() return db end,
    AllocEventId = function()
        local id = db.nextIds.event
        db.nextIds.event = id + 1
        return id
    end,
}
WBF.Characters = {
    GetCurrent = function() return db.characters.A end,
}
WBF.EventType = { Renown = "renown", Reputation = "reputation" }
WBF.Category = { Reputation = "reputation" }
WBF.Events = {
    Add = function(partial)
        db.events[#db.events + 1] = {
            eventType = partial.eventType,
            text = partial.text,
            previous = partial.previous,
            new = partial.new,
            delta = partial.delta,
            meta = partial.meta or {},
        }
        return db.events[#db.events]
    end,
}

loadAddon("Utils/Format.lua", WBF)
loadAddon("Tracking/Reputation.lua", WBF)

C_MajorFactions = {
    GetMajorFactionData = function(majorFactionID)
        return factions[majorFactionID]
    end,
    GetMajorFactionIDs = function()
        local ids = {}
        for id in pairs(factions) do
            ids[#ids + 1] = id
        end
        table.sort(ids)
        return ids
    end,
}

local function check(name, condition)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name)
end

local function events()
    return #db.events
end

local function levelOf(id)
    local row = db.renown and db.renown.byFaction and db.renown.byFaction[id]
    return row and row.level
end

resetDb()
WBF.Reputation.Observe(10, { level = 6, name = "Renown" }, now)
WBF.Reputation.Observe(11, { level = 5, name = "Renown" }, now)
check("generic names baseline separately", levelOf(10) == 6 and levelOf(11) == 5 and events() == 0)
WBF.Reputation.Observe(10, { level = 7, name = "Renown" }, now + 1)
check("one generic track does not move the other", levelOf(10) == 7 and levelOf(11) == 5)
check("generic renown is not presented", events() == 0)

resetDb()
WBF.Reputation.Observe(21, { level = 6, name = "Seasonal Journey" }, now)
WBF.Reputation.Observe(22, { level = 6, name = "Seasonal Journey" }, now)
WBF.Reputation.Observe(21, { level = 7, name = "Seasonal Journey" }, now + 1)
check("same display name keeps separate baselines", levelOf(21) == 7 and levelOf(22) == 6)
check("only the changed faction is presented", events() == 1 and db.events[1].meta.majorFactionID == 21 and db.events[1].meta.faction == "Seasonal Journey")
check("presented text is not a bare renown bucket", db.events[1].text:find("Seasonal Journey", 1, true) ~= nil and db.events[1].previous == 6 and db.events[1].new == 7)

resetDb()
WBF.Reputation.Observe(30, { level = 9, name = nil }, now)
WBF.Reputation.Observe(30, { level = 10, name = "Renown" }, now + 1)
check("unnamed increase waits for a real name", levelOf(30) == 10 and events() == 0)
WBF.Reputation.Observe(30, { level = 10, name = "Delves: Season 2" }, now + 2)
check("named later as Delves: Season 2", events() == 1 and db.events[1].previous == 9 and db.events[1].new == 10 and db.events[1].meta.faction == "Delves: Season 2")

resetDb()
WBF.Reputation.Observe(40, { level = 6, name = "Preyhunter's Journey" }, now)
WBF.Reputation.Observe(40, { level = 7, name = "Preyhunter's Journey" }, now + 1)
check("preyhunter increase is immediate", events() == 1 and db.events[1].previous == 6 and db.events[1].new == 7)

resetDb()
WBF.Reputation.Observe(50, { level = 6, name = "Preyhunter's Journey" }, now)
WBF.Reputation.Observe(50, { level = 5, name = "Preyhunter's Journey" }, now + 1)
check("decrease is not immediate", events() == 0 and levelOf(50) == 6)
WBF.Reputation.Observe(50, { level = 6, name = "Preyhunter's Journey" }, now + 2)
check("reverted decrease is dropped", events() == 0 and levelOf(50) == 6)
WBF.Reputation.Observe(50, { level = 5, name = "Preyhunter's Journey" }, now + 10)
WBF.Reputation.Observe(50, { level = 5, name = "Preyhunter's Journey" }, now + 10 + WBF.Reputation.CONFIRM_SECONDS)
check("confirmed decrease is recorded once", events() == 1 and db.events[1].previous == 6 and db.events[1].new == 5 and db.events[1].delta == -1)

resetDb()
db.renown = { Renown = { level = 9, name = "Renown" } }
WBF.Reputation.Observe(60, { level = 4, name = "Delves: Season 2" }, now)
check("name-keyed baseline is not reused", events() == 0 and levelOf(60) == 4 and db.renown.Renown == nil and db.renown.version == 1)

resetDb()
factions[8] = { name = "Delves: Season 2", renownLevel = 10, factionID = 8, isAccountWide = true, isUnlocked = true }
factions[9] = { name = "Preyhunter's Journey", renownLevel = 6, factionID = 9, isAccountWide = true, isUnlocked = true }
WBF.Reputation.Scan()
check("scan baselines by faction id", events() == 0 and levelOf(8) == 10 and levelOf(9) == 6)
WBF.Reputation.OnRenownChanged(8)
check("a stale event payload does not move a faction", events() == 0 and levelOf(8) == 10 and levelOf(9) == 6)
factions[8].renownLevel = 11
WBF.Reputation.OnRenownChanged(8)
check("api increase uses that faction only", events() == 1 and db.events[1].meta.majorFactionID == 8 and db.events[1].previous == 10 and db.events[1].new == 11 and levelOf(9) == 6)

resetDb()
factions[8] = { name = "Delves: Season 2", renownLevel = 10, factionID = 8, isAccountWide = true }
factions[9] = { name = "Preyhunter's Journey", renownLevel = 6, factionID = 9, isAccountWide = true }
WBF.Reputation.Scan()
local before = events()
factions[8].renownLevel = 10
factions[9].renownLevel = 6
WBF.Reputation.Scan()
check("reload keeps faction baselines", events() == before and levelOf(8) == 10 and levelOf(9) == 6)
WBF.Reputation.Scan()
check("character switch does not invent renown", events() == before and levelOf(8) == 10 and levelOf(9) == 6)

resetDb()
now = 8000
WBF.Reputation.BeginSettle()
WBF.Reputation.Observe(70, { level = 5, name = "Delves: Season 2" }, now)
WBF.Reputation.Observe(70, { level = 6, name = "Delves: Season 2" }, now + 1)
WBF.Reputation.Observe(70, { level = 4, name = "Delves: Season 2" }, now + 2)
check("login settle absorbs the first readings", events() == 0 and levelOf(70) == 4)
WBF.Reputation.Observe(70, { level = 5, name = "Delves: Season 2" }, now + 20)
check("increase after settle is presented from the settled baseline", events() == 1 and db.events[1].previous == 4 and db.events[1].new == 5)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All renown identity tests passed")
