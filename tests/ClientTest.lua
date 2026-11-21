-- Retail keeps every feature; WoW: Forever drops only the retail-only ones,
-- and the event bus skips events the client does not know.
--   lua tests/ClientTest.lua

local failures = 0
local function check(name, ok, detail)
    if ok then
        print("ok   " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local WBF = {}
assert(loadfile("Utils/Client.lua"))("WarbandFYI", WBF)
local Client = WBF.Client

local function Simulate(interface, projectID, camelotID)
    GetBuildInfo = function()
        return "x", "1", "Nov 1 2026", interface
    end
    WOW_PROJECT_ID = projectID
    WOW_PROJECT_CAMELOT = camelotID
    Client.ResetForTests()
end

local FEATURES = { "delves", "prey", "housing", "curatedHunts", "collections", "reputation", "gold" }

-- Retail 12.1.5: mainline project, no Camelot project defined.
Simulate(120105, 1, nil)
check("retail is not forever", Client.IsForever() == false)
check("retail name", Client.Name() == "Retail", Client.Name())
for _, feature in ipairs(FEATURES) do
    check("retail supports " .. feature, Client.Supports(feature) == true)
end

-- Retail on a build that defines the Camelot project constant.
Simulate(120105, 1, 99)
check("retail with camelot constant is not forever", Client.IsForever() == false)

-- Forever by project ID.
Simulate(120105, 99, 99)
check("forever detected by project id", Client.IsForever() == true)

-- Forever by toc number alone.
Simulate(16001, 1, nil)
check("forever detected by toc", Client.IsForever() == true)
check("forever name", Client.Name() == "WoW: Forever", Client.Name())
check("forever drops delves", Client.Supports("delves") == false)
check("forever drops prey", Client.Supports("prey") == false)
check("forever drops housing", Client.Supports("housing") == false)
check("forever drops curated hunts", Client.Supports("curatedHunts") == false)
check("forever keeps collections", Client.Supports("collections") == true)
check("forever keeps gold", Client.Supports("gold") == true)

-- Classic Era must not be mistaken for Forever.
Simulate(11508, 2, nil)
check("classic era is not forever", Client.IsForever() == false)

-- No build info at all (tests, other harnesses) reads as retail.
GetBuildInfo = nil
WOW_PROJECT_ID, WOW_PROJECT_CAMELOT = nil, nil
Client.ResetForTests()
check("missing build info reads as retail", Client.IsForever() == false)

-- Guarded trackers do nothing on Forever and still start on retail.
local function LoadDelves()
    local addon = {
        Client = Client,
        Debug = { Log = function() end },
        Format = { AsNumber = tonumber },
        Time = { Now = function() return 0 end },
    }
    assert(loadfile("Tracking/Delves.lua"))("WarbandFYI", addon)
    local registered = {}
    local bus = { On = function(_, event) registered[#registered + 1] = event end }
    addon.Delves.Register(bus)
    return #registered
end

Simulate(16001, 1, nil)
check("forever skips delve events", LoadDelves() == 0)
Simulate(120105, 1, nil)
check("retail still registers delve events", LoadDelves() > 0)

-- Forever starts with no curated retail raid drops; retail keeps them all.
local function CuratedCounts()
    local addon = { Client = Client }
    assert(loadfile("Tracking/CollectionSources.lua"))("WarbandFYI", addon)
    assert(loadfile("Tracking/CollectionHunts.lua"))("WarbandFYI", addon)
    local sources = 0
    for _ in pairs(addon.CollectionSources.Entries) do sources = sources + 1 end
    return #addon.CollectionSources.Keys, sources
end

Simulate(16001, 1, nil)
local foreverKeys, foreverSources = CuratedCounts()
check("forever has no curated hunt sources", foreverKeys == 0 and foreverSources == 0, foreverKeys)
Simulate(120105, 1, nil)
local retailKeys = CuratedCounts()
check("retail keeps curated hunt sources", retailKeys > 0, retailKeys)

-- Player names: Forever joins the surname and reads the realm separately;
-- retail returns UnitName("player") untouched.
GetRealmName = function() return "Mankrik" end
UnitNameUnmodified = nil

Simulate(120105, 1, nil)
UnitName = function() return "Miranora", nil end
local name, realm = Client.PlayerName()
check("retail name untouched", name == "Miranora" and realm == nil, tostring(name) .. "/" .. tostring(realm))

Simulate(16001, 1, nil)
UnitName = function() return "Miranora", "McFreshnton" end
name, realm = Client.PlayerName()
check("forever joins the surname", name == "Miranora McFreshnton", name)
check("forever realm is not the surname", realm == "Mankrik", realm)

UnitName = function() return "Miranora McFreshnton", "McFreshnton" end
name = Client.PlayerName()
check("forever does not repeat a surname already present", name == "Miranora McFreshnton", name)

UnitName = function() return "Miranora", nil end
name, realm = Client.PlayerName()
check("forever without a surname keeps the first name", name == "Miranora" and realm == "Mankrik", name)

UnitName = function() return "Miranora", nil end
UnitNameUnmodified = function() return "Miranora", "McFreshnton" end
name = Client.PlayerName()
check("forever prefers the unmodified name", name == "Miranora McFreshnton", name)
UnitNameUnmodified = nil

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All client checks passed")
