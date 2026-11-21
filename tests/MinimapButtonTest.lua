-- The minimap button shows by default, hides and returns on request, sits on
-- the minimap edge at its saved angle, and routes clicks.
--   lua tests/MinimapButtonTest.lua

local failures = 0
local function check(name, ok, detail)
    if ok then
        print("ok   " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local function Region()
    local region = { shown = true, scripts = {} }
    local mt = {}
    mt.__index = function(_, key)
        return function() end
    end
    setmetatable(region, mt)
    function region:SetScript(name, fn) self.scripts[name] = fn end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:CreateTexture() return Region() end
    function region:ClearAllPoints() self.point = nil end
    function region:SetPoint(...) self.point = { ... } end
    return region
end

Minimap = Region()
function Minimap:GetWidth() return 140 end
function Minimap:GetHeight() return 140 end
CreateFrame = function() return Region() end
GameTooltip = Region()
GetMinimapShape = function() return "ROUND" end
WarbandFYI_DB = { config = {} }

local toggled, view = 0, nil
local requestedAtlas, requestedFallback
local WBF = {
    UI = {
        Colors = { gold = { 1, 1, 1 }, cream = { 1, 1, 1 }, tipText = { 1, 1, 1 } },
        AddTip = function() end,
        SetAtlasChain = function(_, atlases, fallback) requestedAtlas, requestedFallback = atlases[1], fallback end,
        AddTipRows = function() end,
        frame = {
            view = "week",
            Toggle = function() toggled = toggled + 1 end,
            SetView = function(self, id) self.view = id; view = id end,
            IsShown = function() return true end,
            Show = function() end,
        },
    },
    Database = { IsReady = function() return true end },
}
assert(loadfile("UI/MinimapButton.lua"))("WarbandFYI", WBF)
local Button = WBF.UI.MinimapButton

check("shown by default", Button.IsShown() == true)
Button.Init()
local created = WarbandFYI_DB.config.minimap
check("settings created with a default angle", type(created) == "table" and created.angle == 200, created and created.angle)

Button.SetShown(false)
check("hide is saved", WarbandFYI_DB.config.minimap.hide == true)
check("reports hidden", Button.IsShown() == false)
Button.SetShown(true)
check("show is saved", WarbandFYI_DB.config.minimap.hide == false)

-- Angle 0 on a round 140px minimap sits 80px right of centre (70 + padding).
WarbandFYI_DB.config.minimap.angle = 0
local placed
local realCreate = CreateFrame
CreateFrame = function()
    placed = realCreate()
    return placed
end
assert(loadfile("UI/MinimapButton.lua"))("WarbandFYI", WBF)
WBF.UI.MinimapButton.Init()
local point = placed and placed.point
check("placed on the edge at the saved angle", point and math.abs(point[4] - 80) < 0.01 and math.abs(point[5]) < 0.01,
    point and (tostring(point[4]) .. "," .. tostring(point[5])))
check("button is shown", placed and placed.shown == true)
check("icon is the window crest", requestedAtlas == "warbands-icon" and requestedFallback == "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", requestedAtlas)

placed.scripts.OnClick(placed, "LeftButton")
check("left-click toggles the window", toggled == 1, toggled)
placed.scripts.OnClick(placed, "RightButton")
check("right-click opens settings", view == "settings", view)

WarbandFYI_OnAddonCompartmentClick("WarbandFYI", "LeftButton")
check("compartment click toggles the window", toggled == 2, toggled)

WBF.UI.MinimapButton.SetShown(false)
check("hiding hides the button", placed.shown == false)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All minimap button checks passed")
