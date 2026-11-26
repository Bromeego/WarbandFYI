local _, WBF = ...

-- Which game client is running. One build serves both retail and
-- WoW: Forever (game type "camelot": the retail engine with a 1.60+ toc and
-- vanilla content). Retail answers every Supports() query with true, so
-- nothing here changes retail behaviour.
WBF.Client = {}
local Client = WBF.Client

local FOREVER_MIN, FOREVER_MAX = 16001, 19999

-- Content that exists only on retail. Forever skips the tracker outright
-- rather than leaving it to listen for events that never come.
local RETAIL_ONLY = {
    delves = true,
    prey = true,
    housing = true,
    petBattles = true, -- no battle pets in vanilla content
    curatedHunts = true, -- the built-in raid-drop sources are retail items
}

local forever

local function Interface()
    if type(GetBuildInfo) ~= "function" then
        return nil
    end
    return tonumber((select(4, GetBuildInfo())))
end

-- Both signals Forever addons use: its own project ID, and the toc number
-- (which every Forever build reports the same way).
local function Detect()
    if WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then
        return true
    end
    local interface = Interface()
    return interface ~= nil and interface >= FOREVER_MIN and interface <= FOREVER_MAX
end

function Client.IsForever()
    if forever == nil then
        forever = Detect()
    end
    return forever
end

function Client.IsRetail()
    return not Client.IsForever()
end

function Client.Name()
    return Client.IsForever() and "WoW: Forever" or "Retail"
end

function Client.Supports(feature)
    if Client.IsForever() and RETAIL_ONLY[feature] then
        return false
    end
    return true
end

-- The player's display name and realm. On WoW: Forever, UnitName's second
-- value is the character's surname, not the realm, so it is joined onto the
-- name ("Miranora McFreshnton") and the realm comes from GetRealmName.
-- Retail returns exactly what UnitName("player") always gave.
function Client.PlayerName()
    if not Client.IsForever() then
        return UnitName("player")
    end
    local read = UnitNameUnmodified or UnitName
    local name, surname = read("player")
    if type(name) == "string" and type(surname) == "string" and surname ~= "" then
        local consts = Constants and Constants.CharacterNameSeparatorConsts
        local separator = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
        local tail = separator .. surname
        if name:sub(-#tail) ~= tail then
            name = name .. tail
        end
    end
    return name, GetRealmName and GetRealmName() or nil
end

-- Tests only: forget the cached answer so a new client can be simulated.
function Client.ResetForTests()
    forever = nil
end
