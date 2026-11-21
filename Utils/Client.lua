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

-- Tests only: forget the cached answer so a new client can be simulated.
function Client.ResetForTests()
    forever = nil
end
