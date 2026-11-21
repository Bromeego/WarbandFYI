local _, WBF = ...

-- Minimap button: left-click toggles the window, right-click opens Settings,
-- drag moves it around the minimap edge. Its angle and visibility live in
-- WarbandFYI_DB.config.minimap. Also wires the Addon Compartment entry
-- (the TOC's AddonCompartmentFunc) to the same actions.
WBF.UI.MinimapButton = {}
local MinimapButton = WBF.UI.MinimapButton

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local DEFAULT_ANGLE = 200
local RADIUS_PADDING = 10

-- Which quadrants of each minimap shape are rounded (LibDBIcon's table),
-- indexed 1 bottom-right, 2 bottom-left, 3 top-right, 4 top-left.
local SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local button

local function Settings()
    local config = WarbandFYI_DB and WarbandFYI_DB.config
    if not config then
        return {}
    end
    if type(config.minimap) ~= "table" then
        config.minimap = { hide = false, angle = DEFAULT_ANGLE }
    end
    return config.minimap
end

local function Place(angle)
    if not button then
        return
    end
    local radians = math.rad(angle or DEFAULT_ANGLE)
    local x, y = math.cos(radians), math.sin(radians)
    local quadrant = 1
    if x < 0 then quadrant = quadrant + 1 end
    if y > 0 then quadrant = quadrant + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local rounded = (SHAPES[shape] or SHAPES.ROUND)[quadrant]
    local w = (Minimap:GetWidth() / 2) + RADIUS_PADDING
    local h = (Minimap:GetHeight() / 2) + RADIUS_PADDING
    if rounded then
        x, y = x * w, y * h
    else
        -- Square corner: push out to the edge, clamped to the box.
        local diagW = math.sqrt(2 * w * w) - RADIUS_PADDING
        local diagH = math.sqrt(2 * h * h) - RADIUS_PADDING
        x = math.max(-w, math.min(x * diagW, w))
        y = math.max(-h, math.min(y * diagH, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CursorAngle()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    return math.deg(math.atan2(cy - my, cx - mx)) % 360
end

local function ToggleWindow()
    if not (WBF.Database and WBF.Database.IsReady and WBF.Database.IsReady()) then
        print("|cffd4af37WarbandFYI|r is still loading.")
        return
    end
    if WBF.UI.frame then
        WBF.UI.frame:Toggle()
    end
end

local function OpenSettings()
    local window = WBF.UI.frame
    if not window then
        return
    end
    if window.view ~= "settings" then
        window.previousView = window.view
    end
    window:SetView("settings")
    if not window:IsShown() then
        window:Show()
    end
end

local function HandleClick(mouse)
    if mouse == "RightButton" then
        OpenSettings()
    else
        ToggleWindow()
    end
end

local function ShowTooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
    local colors = WBF.UI.Colors
    WBF.UI.AddTip(GameTooltip, "WarbandFYI", colors.gold)
    WBF.UI.AddTip(GameTooltip, "See what your Warband's been up to.", colors.tipText or colors.cream, true)
    GameTooltip:AddLine(" ")
    WBF.UI.AddTipRows(GameTooltip, {
        { label = "Left-click", value = "Open or close", color = colors.gold },
        { label = "Right-click", value = "Settings", color = colors.gold },
        { label = "Drag", value = "Move this button", color = colors.gold },
    })
    GameTooltip:Show()
end

local function Create()
    if button or not Minimap then
        return button
    end
    button = CreateFrame("Button", "WarbandFYIMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, mouse)
        HandleClick(mouse)
    end)
    button:SetScript("OnMouseDown", function()
        icon:SetPoint("TOPLEFT", 8, -7)
    end)
    button:SetScript("OnMouseUp", function()
        icon:SetPoint("TOPLEFT", 7, -6)
    end)
    button:SetScript("OnEnter", function(self)
        ShowTooltip(self, "ANCHOR_LEFT")
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local angle = CursorAngle()
            Settings().angle = angle
            Place(angle)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        icon:SetPoint("TOPLEFT", 7, -6)
    end)
    return button
end

function MinimapButton.IsShown()
    return Settings().hide ~= true
end

function MinimapButton.Refresh()
    local settings = Settings()
    if settings.hide then
        if button then
            button:Hide()
        end
        return
    end
    if Create() then
        Place(settings.angle)
        button:Show()
    end
end

function MinimapButton.SetShown(shown)
    Settings().hide = not shown
    MinimapButton.Refresh()
end

function MinimapButton.Init()
    MinimapButton.Refresh()
end

-- Addon Compartment (the minimap's addon list). Named in the TOC.
function WarbandFYI_OnAddonCompartmentClick(_, mouse)
    HandleClick(mouse)
end

function WarbandFYI_OnAddonCompartmentEnter(_, menuButton)
    ShowTooltip(menuButton, "ANCHOR_LEFT")
end

function WarbandFYI_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
