local _, WBF = ...

WBF.UI = WBF.UI or {}

WBF.UI.Colors = {
    window = { 0.035, 0.040, 0.052, 0.96 },
    windowBorder = { 0.78, 0.64, 0.32, 1 },
    nav = { 0.020, 0.024, 0.032, 0.98 },
    card = { 0.075, 0.082, 0.098, 0.96 },
    gold = { 0.96, 0.80, 0.42 },
    goldDim = { 0.55, 0.45, 0.24, 1 },
    cream = { 0.94, 0.91, 0.84 },
    muted = { 0.62, 0.64, 0.70 },
    green = { 0.35, 0.95, 0.48 },
    red = { 0.95, 0.38, 0.32 },
    blue = { 0.11, 0.34, 0.72, 0.96 },
    white = { 1, 1, 1 },
    line = { 0.72, 0.58, 0.30, 0.55 },
    -- Status text: success for available/collected, warning for done or
    -- attempted, faint for switched-off entries.
    success = { 0.47, 0.89, 0.61 },
    warning = { 1.00, 0.81, 0.40 },
    faint = { 0.53, 0.53, 0.56 },
    bright = { 1.00, 0.95, 0.85 },
    -- Progress bar tracks and recessed panels.
    track = { 0.08, 0.09, 0.12, 1 },
    trackGold = { 0.14, 0.12, 0.08, 1 },
    well = { 0.04, 0.045, 0.06, 1 },
    button = { 0.12, 0.12, 0.145, 1 },
    buttonPressed = { 0.14, 0.11, 0.07, 1 },
    buttonHover = { 0.96, 0.80, 0.42, 0.12 },
    buttonDisabled = { 0.07, 0.07, 0.08, 0.9 },
    edgeDisabled = { 0.30, 0.30, 0.32, 0.8 },
}

-- "|cffrrggbb" for a palette color, for text built with inline color codes.
function WBF.UI.Hex(color)
    return string.format(
        "|cff%02x%02x%02x",
        math.floor(color[1] * 255 + 0.5),
        math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5)
    )
end

function WBF.UI.ColorText(color, text)
    return WBF.UI.Hex(color) .. tostring(text) .. "|r"
end

local pools = {}

local function Color(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

function WBF.UI.PaintCard(frame, state)
    if state == "pressed" then
        WBF.UI.Paint(frame, { 0.14, 0.11, 0.07, 0.98 }, WBF.UI.Colors.gold)
    elseif state == "hover" then
        WBF.UI.Paint(frame, { 0.11, 0.12, 0.15, 0.98 }, { 0.96, 0.84, 0.50, 0.95 })
    else
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    end
end

function WBF.UI.BindCard(frame, data, tooltipBuilder)
    local clickable = data and data.open ~= nil
    WBF.UI.PaintCard(frame, "idle")
    frame:SetScript("OnEnter", function(self)
        if clickable then
            WBF.UI.PaintCard(self, "hover")
        end
        if tooltipBuilder then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            tooltipBuilder(GameTooltip, self)
            if clickable then
                GameTooltip:AddLine("Click to see the records.", 0.9, 0.82, 0.45)
            end
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(self)
        if clickable then
            WBF.UI.PaintCard(self, "idle")
        end
        GameTooltip:Hide()
    end)
    frame:SetScript("OnMouseDown", function(self)
        if clickable then
            WBF.UI.PaintCard(self, "pressed")
        end
    end)
    frame:SetScript("OnMouseUp", function(self)
        if not clickable then
            return
        end
        if self:IsMouseOver() then
            WBF.UI.PaintCard(self, "hover")
        else
            WBF.UI.PaintCard(self, "idle")
        end
    end)
    if clickable then
        frame:SetScript("OnClick", function()
            if not WBF.UI.frame then
                return
            end
            if data.open == "resource" and WBF.UI.frame.OpenResource then
                local key = data.resourceKey
                if (not key or key == "") and WBF.Resources and WBF.Resources.ResolveKey then
                    key = WBF.Resources.ResolveKey(data.label)
                end
                if key and WBF.UI.frame:OpenResource(key, data.period) then
                    return
                end
            end
            WBF.UI.frame:OpenDetail(data.open, {
                characterGUID = data.characterGUID,
                period = data.period,
                resourceKey = data.resourceKey,
                tab = data.tab,
                warband = data.warband,
            })
        end)
    else
        frame:SetScript("OnClick", nil)
    end
end

function WBF.UI.Paint(frame, background, border, edgeSize)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = edgeSize or 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local fill = background or WBF.UI.Colors.card
    local edge = border or WBF.UI.Colors.goldDim
    frame:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1)
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

local WHITE = "Interface\\Buttons\\WHITE8x8"

local function ButtonFont(name, color)
    local font = _G[name]
    if not font then
        font = CreateFont(name)
        font:SetFontObject(GameFontHighlight)
        font:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    return font
end

local function StateFill(button, setter, getter, color)
    button[setter](button, WHITE)
    local texture = button[getter](button)
    texture:ClearAllPoints()
    texture:SetAllPoints()
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return texture
end

-- One physical pixel in UI units. A plain 1-unit edge rounds to zero pixels
-- on some sides at fractional UI scales, which made borders vanish.
local function OnePixel(region)
    if PixelUtil and PixelUtil.GetNearestPixelSize and region.GetEffectiveScale then
        return PixelUtil.GetNearestPixelSize(1, region:GetEffectiveScale(), 1)
    end
    return 1
end

-- Four edge textures drawn above the fill, so no inset rounding can cover
-- them. leftOverhang extends the box past the frame's left edge.
local function PixelBorder(frame, layer, leftOverhang)
    local px = OnePixel(frame)
    local left = -(leftOverhang or 0)
    local top = frame:CreateTexture(nil, layer)
    top:SetPoint("TOPLEFT", left, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(px)
    local bottom = frame:CreateTexture(nil, layer)
    bottom:SetPoint("BOTTOMLEFT", left, 0)
    bottom:SetPoint("BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(px)
    local leftEdge = frame:CreateTexture(nil, layer)
    leftEdge:SetPoint("TOPLEFT", left, 0)
    leftEdge:SetPoint("BOTTOMLEFT", left, 0)
    leftEdge:SetWidth(px)
    local rightEdge = frame:CreateTexture(nil, layer)
    rightEdge:SetPoint("TOPRIGHT", 0, 0)
    rightEdge:SetPoint("BOTTOMRIGHT", 0, 0)
    rightEdge:SetWidth(px)
    return { top, bottom, leftEdge, rightEdge }
end

local function PaintBorder(edges, color)
    for index = 1, #edges do
        edges[index]:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
end

local function PaintButtonEdge(button)
    PaintBorder(button.Border, button:IsEnabled() and WBF.UI.Colors.goldDim or WBF.UI.Colors.edgeDisabled)
end

-- Themed replacement for UIPanelButtonTemplate. The button's own state
-- textures and font objects carry hover, pressed and disabled, so callers can
-- still SetScript OnEnter/OnLeave for tooltips without losing the styling.
function WBF.UI.Button(parent, text, width, height)
    local colors = WBF.UI.Colors
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 100, height or 22)
    -- The state fills draw in ARTWORK; the border sits above them.
    button.Border = PixelBorder(button, "OVERLAY")
    StateFill(button, "SetNormalTexture", "GetNormalTexture", colors.button)
    StateFill(button, "SetPushedTexture", "GetPushedTexture", colors.buttonPressed)
    StateFill(button, "SetDisabledTexture", "GetDisabledTexture", colors.buttonDisabled)
    StateFill(button, "SetHighlightTexture", "GetHighlightTexture", colors.buttonHover):SetBlendMode("ADD")
    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER", 0, 0)
    button:SetFontString(label)
    button:SetNormalFontObject(ButtonFont("WarbandFYIButtonFont", colors.cream))
    button:SetHighlightFontObject(ButtonFont("WarbandFYIButtonFontHover", colors.gold))
    button:SetDisabledFontObject(ButtonFont("WarbandFYIButtonFontOff", colors.faint))
    button:SetPushedTextOffset(1, -1)
    button:HookScript("OnEnable", PaintButtonEdge)
    button:HookScript("OnDisable", PaintButtonEdge)
    PaintButtonEdge(button)
    if text then
        button:SetText(text)
    end
    return button
end

-- Themed replacement for InputBoxTemplate. The frame sits 5px left of the
-- drawn box like the stock template, so existing anchors line up unchanged.
function WBF.UI.EditBox(parent, width, height)
    local colors = WBF.UI.Colors
    local edit = CreateFrame("EditBox", nil, parent)
    edit:SetSize(width or 120, height or 22)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextInsets(0, 4, 0, 0)
    local fill = edit:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", -5, 0)
    fill:SetPoint("BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(colors.well[1], colors.well[2], colors.well[3], colors.well[4] or 1)
    edit.Fill = fill
    edit.Border = PixelBorder(edit, "BORDER", 5)
    PaintBorder(edit.Border, colors.goldDim)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
    end)
    return edit
end

-- Thin gold scrollbar for a ScrollFrame. Keep it in step with
-- WBF.UI.SyncScrollBar whenever the scroll range or offset changes.
function WBF.UI.ScrollBar(scroll, parent, thumbHeight)
    local colors = WBF.UI.Colors
    local bar = CreateFrame("Slider", nil, parent or scroll)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(8)
    bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then
        bar:SetObeyStepOnDrag(true)
    end
    bar:SetMinMaxValues(0, 1)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP", 0, 0)
    track:SetPoint("BOTTOM", 0, 0)
    track:SetWidth(2)
    track:SetColorTexture(colors.line[1], colors.line[2], colors.line[3], 0.45)
    bar.Track = track
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(colors.gold[1], colors.gold[2], colors.gold[3], 0.85)
    thumb:SetSize(8, thumbHeight or 36)
    bar:SetThumbTexture(thumb)
    bar.Thumb = thumb
    bar:SetScript("OnValueChanged", function(self, value)
        if self.updating then
            return
        end
        scroll:SetVerticalScroll(value)
    end)
    bar:Hide()
    return bar
end

function WBF.UI.SyncScrollBar(scroll, bar)
    local range = scroll:GetVerticalScrollRange()
    if range <= 1 then
        bar:Hide()
        scroll:SetVerticalScroll(0)
        return
    end
    bar:Show()
    bar.updating = true
    bar:SetMinMaxValues(0, range)
    local value = math.min(scroll:GetVerticalScroll(), range)
    bar:SetValue(value)
    bar.updating = false
end

local function StringHeight(fontString)
    local height = fontString:GetStringHeight() or 0
    return math.max(12, math.ceil(height))
end

-- A page or panel with nothing to show: an icon, a heading and a hint that
-- says what to do next. Pooled pages use WBF.UI.Pool("emptyState", WBF.UI.EmptyState).
function WBF.UI.EmptyState(parent)
    local colors = WBF.UI.Colors
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    WBF.UI.Paint(frame, colors.card, colors.line)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetAlpha(0.85)
    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetJustifyH("CENTER")
    heading:SetTextColor(colors.gold[1], colors.gold[2], colors.gold[3])
    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetJustifyH("CENTER")
    body:SetWordWrap(true)
    body:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
    frame.Icon = icon
    frame.Heading = heading
    frame.Body = body

    function frame:Set(headingText, bodyText, atlases, fallback)
        self.Heading:SetText(headingText or "")
        self.Body:SetText(bodyText or "")
        self.hasIcon = atlases ~= nil or fallback ~= nil
        if self.hasIcon then
            WBF.UI.SetAtlasChain(self.Icon, atlases, fallback)
        end
        self.Icon:SetShown(self.hasIcon)
        return self
    end

    -- Sizes the block to width and returns its height.
    function frame:Layout(width)
        local textWidth = math.max(80, math.min(width - 32, 460))
        local y = 16
        self.Icon:ClearAllPoints()
        if self.hasIcon then
            self.Icon:SetPoint("TOP", self, "TOP", 0, -y)
            y = y + 28 + 8
        end
        self.Heading:ClearAllPoints()
        self.Heading:SetPoint("TOP", self, "TOP", 0, -y)
        self.Heading:SetWidth(textWidth)
        y = y + StringHeight(self.Heading)
        local hasBody = (self.Body:GetText() or "") ~= ""
        self.Body:ClearAllPoints()
        self.Body:SetShown(hasBody)
        if hasBody then
            self.Body:SetPoint("TOP", self, "TOP", 0, -(y + 6))
            self.Body:SetWidth(textWidth)
            y = y + 6 + StringHeight(self.Body)
        end
        y = y + 16
        self:SetSize(width, y)
        return y
    end

    return frame
end

-- Pooled empty state at (x, y) in parent; released with WBF.UI.ReleaseAll.
-- Returns its height.
function WBF.UI.PlaceEmptyState(parent, x, y, width, heading, body, atlases, fallback)
    local state = WBF.UI.Acquire(WBF.UI.Pool("emptyState", WBF.UI.EmptyState), parent)
    state:Set(heading, body, atlases, fallback)
    state:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    return state:Layout(width)
end

function WBF.UI.SetAtlasChain(texture, atlases, fallback)
    if atlases and C_Texture and C_Texture.GetAtlasInfo then
        for index = 1, #atlases do
            local atlas = atlases[index]
            if atlas and C_Texture.GetAtlasInfo(atlas) then
                texture:SetAtlas(atlas)
                return
            end
        end
    end
    texture:SetTexture(fallback or "Interface\\Icons\\INV_Misc_QuestionMark")
end

function WBF.UI.MakeCriteriaWidgets(parent)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:Hide()
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetHeight(16)
    toggle:EnableMouse(true)
    local label = toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT")
    label:SetJustifyH("LEFT")
    toggle.Label = label
    toggle:Hide()
    return text, toggle
end

local CRITERIA_CHECK = "|TInterface\\AchievementFrame\\UI-Achievement-Criteria-Check:12:12:0:-1|t"

local function CriteriaRow(line)
    local done = line.done == true or line.mark == "✓"
    if done then
        return CRITERIA_CHECK .. "  " .. WBF.UI.ColorText(WBF.UI.Colors.green, line.text)
    end
    return "-  " .. line.text
end

function WBF.UI.PlaceCriteriaDetail(parent, text, toggle, detail, x, y, width, onToggle)
    if text then
        text:Hide()
    end
    if toggle then
        toggle:Hide()
        toggle:SetScript("OnMouseDown", nil)
    end
    if type(detail) ~= "table" or not text then
        return y
    end
    local rows = {}
    if type(detail.heading) == "string" and detail.heading ~= "" then
        rows[#rows + 1] = detail.heading
    end
    local lines = detail.lines
    if type(lines) == "table" then
        for index = 1, #lines do
            local line = lines[index]
            if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                rows[#rows + 1] = CriteriaRow(line)
            end
        end
    end
    if type(detail.more) == "number" and detail.more > 0 then
        rows[#rows + 1] = "+ " .. detail.more .. " more"
    end
    local finished = detail.completedLines
    if type(finished) == "table" then
        for index = 1, #finished do
            local line = finished[index]
            if type(line) == "table" and type(line.text) == "string" and line.text ~= "" then
                rows[#rows + 1] = CriteriaRow(line)
            end
        end
    end
    if #rows > 0 then
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        text:SetWidth(math.max(20, width))
        text:SetText(table.concat(rows, "\n"))
        local muted = WBF.UI.Colors and WBF.UI.Colors.muted
        if muted then
            text:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
        end
        text:Show()
        local height = 14 * #rows
        if text.GetStringHeight then
            local measured = text:GetStringHeight()
            if type(measured) == "number" and measured > 8 then
                height = measured
            end
        end
        y = y + height + 2
    end
    if toggle and type(detail.toggle) == "string" and detail.toggle ~= "" then
        toggle:ClearAllPoints()
        toggle:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        toggle.Label:SetText(detail.toggle)
        local gold = WBF.UI.Colors and WBF.UI.Colors.gold
        if gold then
            toggle.Label:SetTextColor(gold[1], gold[2], gold[3], gold[4] or 1)
        end
        toggle:SetWidth(math.max(64, #detail.toggle * 7))
        toggle:SetHeight(16)
        toggle:Show()
        toggle:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and onToggle then
                onToggle()
            end
        end)
        y = y + 18
    end
    return y
end

function WBF.UI.KeepKeyboard(edit)
    if not edit or edit._wbfKeys then
        return
    end
    edit._wbfKeys = true
    local function hold(self)
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        if self.SetPropagateKeyboardInput then
            pcall(self.SetPropagateKeyboardInput, self, false)
        end
    end
    if edit.HookScript then
        edit:HookScript("OnEditFocusGained", hold)
        edit:HookScript("OnKeyDown", hold)
    else
        edit:SetScript("OnEditFocusGained", hold)
        edit:SetScript("OnKeyDown", hold)
    end
end

function WBF.UI.BindWheel(frame)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        if WBF.UI.ScrollWheel then
            WBF.UI.ScrollWheel(delta)
        end
    end)
end

function WBF.UI.Tooltip(owner, builder)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        builder(GameTooltip, self)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function Enlarge(fontString, object, delta)
    local font, size = object:GetFont()
    if font and size then
        fontString:SetFont(font, size + delta, "")
    end
    fontString:SetShadowColor(0, 0, 0, 0.8)
    fontString:SetShadowOffset(1, -1)
end

function WBF.UI.CreatePool(factory)
    return {
        factory = factory,
        free = {},
        used = {},
    }
end

function WBF.UI.Pool(name, factory)
    if not pools[name] then
        pools[name] = WBF.UI.CreatePool(factory)
    end
    return pools[name]
end

function WBF.UI.Acquire(pool, parent)
    local frame = table.remove(pool.free)
    if not frame then
        frame = pool.factory(parent)
    end
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:Show()
    pool.used[#pool.used + 1] = frame
    return frame
end

function WBF.UI.ReleasePool(pool)
    for index = #pool.used, 1, -1 do
        local frame = pool.used[index]
        frame:Hide()
        frame:ClearAllPoints()
        pool.free[#pool.free + 1] = frame
        pool.used[index] = nil
    end
end

function WBF.UI.ReleaseAll()
    for _, pool in pairs(pools) do
        WBF.UI.ReleasePool(pool)
    end
end

function WBF.UI.SetPortrait(texture, guid, classFile)
    if guid and UnitGUID and UnitGUID("player") == guid and SetPortraitTexture then
        SetPortraitTexture(texture, "player")
        return
    end
    local atlas = classFile and ("classicon-" .. classFile:lower()) or nil
    WBF.UI.SetAtlasChain(texture, { atlas }, "Interface\\Icons\\INV_Misc_QuestionMark")
end

local function EventAtlases(event)
    local meta = event.meta or {}
    local atlases = {}
    if meta.iconAtlas then
        atlases[#atlases + 1] = meta.iconAtlas
    end
    local fallback = "Interface\\Icons\\INV_Misc_QuestionMark"
    local kind = event.eventType
    if WBF.Quests and WBF.Quests.EffectiveType then
        kind = WBF.Quests.EffectiveType(event)
    end
    if kind == WBF.EventType.BossKill then
        atlases[#atlases + 1] = "DungeonSkull"
        fallback = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
    elseif kind == WBF.EventType.InstanceEnter then
        atlases[#atlases + 1] = "QuestNormal"
    elseif kind == WBF.EventType.WorldQuest or kind == WBF.EventType.WorldEvent then
        atlases[#atlases + 1] = "worldquest-tracker-questmarker"
        atlases[#atlases + 1] = "QuestNormal"
    elseif kind == WBF.EventType.Quest then
        atlases[#atlases + 1] = "QuestNormal"
    elseif kind == WBF.EventType.Achievement then
        fallback = "Interface\\Icons\\Achievement_General"
    elseif kind == WBF.EventType.Mount then
        fallback = "Interface\\Icons\\Ability_Mount_RidingHorse"
    elseif kind == WBF.EventType.Pet or kind == WBF.EventType.PetBattle then
        fallback = "Interface\\Icons\\INV_Box_PetCarrier_01"
    elseif kind == WBF.EventType.Appearance then
        atlases[#atlases + 1] = "transmog-icon-chat"
        fallback = "Interface\\Icons\\INV_Chest_Cloth_17"
    elseif kind == WBF.EventType.HousingDecor or kind == WBF.EventType.HousingAcquire or kind == WBF.EventType.HousingXP then
        fallback = "Interface\\Icons\\INV_Misc_Statue_02"
    elseif kind == WBF.EventType.MythicPlus then
        atlases[#atlases + 1] = "challengeMode-icon-chest"
        fallback = "Interface\\Icons\\Achievement_ChallengeMode_Gold"
    elseif kind == WBF.EventType.ItemLevel then
        atlases[#atlases + 1] = "charactercreate-icon-customize-weapon"
        fallback = "Interface\\Icons\\INV_Sword_39"
    elseif kind == WBF.EventType.Level then
        atlases[#atlases + 1] = "charactercreate-icon-customize-body"
        fallback = "Interface\\Icons\\Spell_ChargePositive"
    elseif kind == WBF.EventType.Reputation or kind == WBF.EventType.Renown then
        atlases[#atlases + 1] = "MajorFactions_MapIcons_Centaur_Major"
        fallback = "Interface\\Icons\\Achievement_Reputation_01"
    elseif kind == WBF.EventType.Delve then
        atlases[#atlases + 1] = "delves-scenario-treasure-chest"
        fallback = "Interface\\Icons\\INV_Misc_Map_01"
    elseif kind == WBF.EventType.Profession then
        atlases[#atlases + 1] = "Professions-ChatIcon-Quality-Tier1"
        fallback = "Interface\\Icons\\INV_Misc_Gear_01"
    elseif kind == WBF.EventType.Prey then
        fallback = "Interface\\Icons\\INV_Misc_MonsterClaw_02"
    elseif kind == WBF.EventType.RareKill then
        fallback = "Interface\\Icons\\INV_Misc_Head_Dragon_Black"
    end
    return atlases, fallback
end

function WBF.UI.ApplyEventIcon(texture, event)
    local meta = event.meta or {}
    if meta.icon then
        texture:SetTexture(meta.icon)
        return
    end
    local atlases, fallback = EventAtlases(event)
    WBF.UI.SetAtlasChain(texture, atlases, fallback)
end

function WBF.UI.EventTooltip(tooltip, event)
    local meta = event.meta or {}
    local native = false
    if meta.achievementID and tooltip.SetAchievementByID then
        tooltip:SetAchievementByID(meta.achievementID)
        native = true
    elseif event.eventType == WBF.EventType.Mount and meta.spellID and tooltip.SetSpellByID then
        tooltip:SetSpellByID(meta.spellID)
        native = true
    elseif meta.itemID and tooltip.SetItemByID then
        tooltip:SetItemByID(meta.itemID)
        native = true
    end

    if not native then
        local label = event.text or "Activity"
        if WBF.Quests and WBF.Quests.ActivityText then
            label = WBF.Quests.ActivityText(event)
        end
        tooltip:SetText(WBF.Format.DisplayText(label), 1, 0.82, 0.45)
    end
    local character = event.guid and WBF.Characters.Get(event.guid)
    if WBF.Characters.IsDiscovered(character) and character.name then
        local r, g, b = WBF.Format.ClassColor(character.classFile)
        local who = character.name
        if character.realm and character.realm ~= "" then
            who = who .. " - " .. character.realm
        end
        tooltip:AddLine(who, r, g, b)
    end
    if meta.difficultyName and meta.difficultyName ~= "" then
        tooltip:AddLine(meta.difficultyName, 0.8, 0.8, 0.8)
    end
    if meta.instanceName and meta.instanceName ~= "" and event.eventType == WBF.EventType.BossKill then
        tooltip:AddLine(meta.instanceName, 0.8, 0.8, 0.8)
    end
    if meta.timedText then
        tooltip:AddLine(meta.timedText == "timed" and "Timed" or "Untimed", 0.8, 0.8, 0.8)
    end
    if event.previous and event.new and (event.eventType == WBF.EventType.ItemLevel or event.eventType == WBF.EventType.Profession or event.eventType == WBF.EventType.Renown) then
        tooltip:AddLine(WBF.Format.Progression(event.previous, event.new), 0.35, 0.95, 0.48)
    end
    if event.eventType == WBF.EventType.Reputation and event.delta then
        tooltip:AddLine(WBF.Format.Signed(event.delta) .. " reputation", 0.35, 0.95, 0.48)
        if meta.accountWide then
            tooltip:AddLine("Warband reputation", 0.8, 0.8, 0.8)
        end
    end
    if meta.tier and event.eventType == WBF.EventType.Delve then
        tooltip:AddLine("Tier " .. meta.tier, 0.8, 0.8, 0.8)
    end
    if event.eventType == WBF.EventType.RareKill then
        if meta.mapName and meta.mapName ~= "" then
            tooltip:AddLine(meta.mapName, 0.8, 0.8, 0.8)
        end
        if meta.classification and meta.classification ~= "" then
            tooltip:AddLine(meta.classification, 0.8, 0.8, 0.8)
        end
    end
    if event.eventType == WBF.EventType.HousingDecor then
        if meta.houseXP and meta.houseXP > 0 then
            tooltip:AddLine("+" .. WBF.Format.Number(meta.houseXP) .. " House XP", 0.35, 0.95, 0.48)
        end
        if meta.source and meta.source ~= "" then
            tooltip:AddLine(meta.source, 0.8, 0.8, 0.8)
        elseif meta.location and meta.location ~= "" then
            tooltip:AddLine(meta.location, 0.8, 0.8, 0.8)
        end
    end
    if event.eventType == WBF.EventType.Appearance then
        if meta.sourceID then
            tooltip:AddLine("Appearance " .. meta.sourceID, 0.8, 0.8, 0.8)
        end
        if meta.instanceName or meta.location then
            tooltip:AddLine(meta.instanceName or meta.location, 0.8, 0.8, 0.8)
        end
    end
    if event.eventType == WBF.EventType.Prey then
        if meta.difficulty and meta.difficulty ~= "" then
            tooltip:AddLine(meta.difficulty, 0.96, 0.8, 0.42)
        end
        if meta.completed == false then
            tooltip:AddLine("In progress", 0.8, 0.8, 0.8)
        end
        if meta.journey and meta.journey > 0 then
            tooltip:AddLine((meta.journeyName or "Journey") .. " " .. WBF.Format.Signed(meta.journey), 0.35, 0.95, 0.48)
        end
        if meta.duration and meta.duration > 0 then
            local duration = WBF.Format.Duration(meta.duration)
            if duration then
                tooltip:AddLine(duration, 0.8, 0.8, 0.8)
            end
        end
        if meta.objective and meta.objective ~= "" then
            tooltip:AddLine(meta.objective, 0.8, 0.8, 0.8, true)
        end
    end
    if event.eventType == WBF.EventType.Resource then
        local classification = meta.classification
        if classification == "transfer" then
            tooltip:AddLine("Transferred. Not counted as earned or spent.", 0.8, 0.8, 0.8, true)
        elseif classification == "baseline" then
            tooltip:AddLine("Balance when tracking started. Not counted as earned.", 0.8, 0.8, 0.8, true)
        elseif classification == "sync" then
            tooltip:AddLine("Already held on another character. Not counted as earned.", 0.8, 0.8, 0.8, true)
        elseif classification == "gain_observed" or classification == "loss_observed" then
            tooltip:AddLine("Change in the total held, including the Warband bank. The source was not recorded.", 0.8, 0.8, 0.8, true)
        end
        if meta.balanceAfter ~= nil then
            tooltip:AddLine("Balance " .. WBF.Format.Number(meta.balanceAfter), 0.8, 0.8, 0.8)
        end
        if meta.eventName and meta.eventName ~= "" then
            tooltip:AddLine(meta.eventName, 0.96, 0.8, 0.42)
        end
    end
    if event.at then
        tooltip:AddLine(WBF.Time.FormatStamp(event.at), 0.62, 0.64, 0.70)
    end
    if event.sample then
        tooltip:AddLine("Sample history", 0.9, 0.75, 0.35)
    end
end


-- Mount and pet rows use a lightweight, reusable 3D preview instead of
-- rebuilding Blizzard's collection journal while the mouse is merely passing
-- over a list.  The preview is delayed slightly so scrolling the list does not
-- churn model loads.
local collectionPreview
local collectionPreviewToken = 0

local PET_QUALITY_NAMES = {
    [0] = "Poor",
    [1] = "Poor",
    [2] = "Common",
    [3] = "Uncommon",
    [4] = "Rare",
    [5] = "Epic",
    [6] = "Legendary",
}

local function ResolveMountID(event)
    local meta = event and event.meta or {}
    local mountID = tonumber(meta.mountID)
    if mountID then
        return mountID
    end
    if meta.spellID and C_MountJournal and C_MountJournal.GetMountFromSpell then
        local ok, found = pcall(C_MountJournal.GetMountFromSpell, meta.spellID)
        if ok then
            return tonumber(found)
        end
    end
    return nil
end

local function ResolveSpeciesID(event)
    local meta = event and event.meta or {}
    local speciesID = tonumber(meta.speciesID)
    if speciesID then
        return speciesID
    end
    if meta.petID and C_PetJournal and C_PetJournal.GetPetInfoByPetID then
        local ok, found = pcall(C_PetJournal.GetPetInfoByPetID, meta.petID)
        if ok then
            return tonumber(found)
        end
    end
    return nil
end

local function FirstMountDisplayID(mountID)
    if not mountID or not C_MountJournal then
        return nil
    end
    if C_MountJournal.GetMountInfoExtraByID then
        local ok, displayID = pcall(C_MountJournal.GetMountInfoExtraByID, mountID)
        if ok and tonumber(displayID) then
            return tonumber(displayID)
        end
    end
    if C_MountJournal.GetMountAllCreatureDisplayInfoByID then
        local ok, entries = pcall(C_MountJournal.GetMountAllCreatureDisplayInfoByID, mountID)
        if ok and type(entries) == "table" then
            local first = entries[1]
            if type(first) == "table" then
                return tonumber(first.creatureDisplayInfoID or first.creatureDisplayID or first.displayID)
            end
            return tonumber(first)
        end
    end
    return nil
end

local function PetCurrentSummary(speciesID, preferredPetID)
    if not speciesID or not C_PetJournal then
        return nil, nil, nil
    end
    local owned, limit
    if C_PetJournal.GetNumCollectedInfo then
        local ok, count, maxCount = pcall(C_PetJournal.GetNumCollectedInfo, speciesID)
        if ok then
            owned = tonumber(count)
            limit = tonumber(maxCount)
        end
    end

    local bestLevel, bestQuality
    local function ConsiderPet(petID)
        if not petID or not C_PetJournal.GetPetInfoByPetID then
            return
        end
        local ok, foundSpecies, _, level = pcall(C_PetJournal.GetPetInfoByPetID, petID)
        if not ok or tonumber(foundSpecies) ~= speciesID then
            return
        end
        level = tonumber(level) or 0
        local quality
        if C_PetJournal.GetPetStats then
            local okStats, _, _, _, _, rarity = pcall(C_PetJournal.GetPetStats, petID)
            if okStats then
                quality = tonumber(rarity)
            end
        end
        if not bestLevel or level > bestLevel or (level == bestLevel and (quality or 0) > (bestQuality or 0)) then
            bestLevel = level
            bestQuality = quality
        end
    end

    ConsiderPet(preferredPetID)
    if C_PetJournal.GetOwnedPetIDs then
        local results = { pcall(C_PetJournal.GetOwnedPetIDs) }
        if results[1] then
            if type(results[2]) == "table" then
                for _, petID in ipairs(results[2]) do
                    ConsiderPet(petID)
                end
            else
                for index = 2, #results do
                    ConsiderPet(results[index])
                end
            end
        end
    end
    return owned, limit, bestLevel, bestQuality
end

local function EnsureCollectionPreview()
    if collectionPreview then
        return collectionPreview
    end

    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(318, 330)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    WBF.UI.Paint(frame, { 0.025, 0.030, 0.040, 0.985 }, { 0.96, 0.80, 0.42, 0.95 })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -11)
    title:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])

    local kind = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    kind:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    kind:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    kind:SetJustifyH("LEFT")
    kind:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    local modelBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    modelBox:SetPoint("TOPLEFT", 10, -48)
    modelBox:SetPoint("TOPRIGHT", -10, -48)
    modelBox:SetHeight(174)
    WBF.UI.Paint(modelBox, { 0.008, 0.010, 0.014, 0.95 }, { 0.55, 0.45, 0.24, 0.72 })

    local model = CreateFrame("PlayerModel", nil, modelBox)
    model:SetPoint("TOPLEFT", 2, -2)
    model:SetPoint("BOTTOMRIGHT", -2, 2)
    model:SetFacing(-0.35)
    if model.SetCamDistanceScale then
        model:SetCamDistanceScale(0.78)
    end

    local details = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    details:SetPoint("TOPLEFT", modelBox, "BOTTOMLEFT", 4, -8)
    details:SetPoint("TOPRIGHT", modelBox, "BOTTOMRIGHT", -4, -8)
    details:SetJustifyH("LEFT")
    details:SetJustifyV("TOP")
    details:SetWordWrap(true)
    details:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])

    local source = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    source:SetPoint("TOPLEFT", details, "BOTTOMLEFT", 0, -5)
    source:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    source:SetJustifyH("LEFT")
    source:SetJustifyV("TOP")
    source:SetWordWrap(true)
    source:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", 14, 10)
    footer:SetPoint("BOTTOMRIGHT", -14, 10)
    footer:SetJustifyH("LEFT")
    footer:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])

    frame.Title = title
    frame.Kind = kind
    frame.Model = model
    frame.Details = details
    frame.Source = source
    frame.Footer = footer
    frame:Hide()
    collectionPreview = frame
    return frame
end

local function PositionCollectionPreview(frame)
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    x = x / scale
    y = y / scale
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    local width = frame:GetWidth()
    local height = frame:GetHeight()
    local left = x + 18
    if left + width > screenWidth - 8 then
        left = x - width - 18
    end
    if left < 8 then
        left = 8
    end
    local bottom = y - height + 28
    if bottom < 8 then
        bottom = 8
    elseif bottom + height > screenHeight - 8 then
        bottom = screenHeight - height - 8
    end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
end

local function SetPreviewModel(model, displayID, distance)
    if model.ClearModel then
        model:ClearModel()
    end
    if displayID and model.SetDisplayInfo then
        local ok = pcall(model.SetDisplayInfo, model, displayID)
        if ok then
            if model.SetCamDistanceScale then
                model:SetCamDistanceScale(distance or 0.78)
            end
            if model.SetFacing then
                model:SetFacing(-0.35)
            end
            return true
        end
    end
    return false
end

local function MountPreviewData(event)
    local mountID = ResolveMountID(event)
    if not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoByID then
        return nil
    end
    local ok, name, spellID, icon, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountID)
    if not ok then
        return nil
    end
    local displayID, description, source
    if C_MountJournal.GetMountInfoExtraByID then
        local okExtra, d, desc, src = pcall(C_MountJournal.GetMountInfoExtraByID, mountID)
        if okExtra then
            displayID, description, source = tonumber(d), desc, src
        end
    end
    displayID = displayID or FirstMountDisplayID(mountID)
    return {
        id = mountID,
        name = name or event.text or "Mount",
        displayID = displayID,
        description = WBF.Format.PlainString(description),
        source = WBF.Format.PlainString(source),
        collected = isCollected == true,
        spellID = spellID,
        icon = icon,
    }
end

local function PetPreviewData(event)
    local meta = event.meta or {}
    local speciesID = ResolveSpeciesID(event)
    if not speciesID or not C_PetJournal or not C_PetJournal.GetPetInfoBySpeciesID then
        return nil
    end
    local ok, name, icon, petType, _, sourceText, description, isWild, canBattle, _, _, _, displayID = pcall(C_PetJournal.GetPetInfoBySpeciesID, speciesID)
    if not ok then
        return nil
    end
    local owned, limit, bestLevel, bestQuality = PetCurrentSummary(speciesID, meta.petID)
    return {
        id = speciesID,
        petID = meta.petID,
        name = name or event.text or "Battle pet",
        displayID = tonumber(displayID),
        source = WBF.Format.PlainString(sourceText),
        description = WBF.Format.PlainString(description),
        isWild = isWild == true,
        canBattle = canBattle == true,
        owned = owned,
        limit = limit,
        bestLevel = bestLevel,
        bestQuality = bestQuality,
        capturedLevel = tonumber(meta.capturedLevel or meta.level),
        capturedQuality = tonumber(meta.capturedQuality or meta.quality),
        icon = icon,
        petType = petType,
    }
end

function WBF.UI.HideCollectionPreview()
    collectionPreviewToken = collectionPreviewToken + 1
    if collectionPreview then
        collectionPreview:Hide()
        if collectionPreview.Model and collectionPreview.Model.ClearModel then
            collectionPreview.Model:ClearModel()
        end
    end
end

function WBF.UI.ShowCollectionPreview(owner, event, kind)
    collectionPreviewToken = collectionPreviewToken + 1
    local token = collectionPreviewToken
    if not C_Timer or not C_Timer.After then
        return
    end
    C_Timer.After(0.18, function()
        if token ~= collectionPreviewToken or not owner or not owner.IsMouseOver or not owner:IsMouseOver() then
            return
        end
        local data = kind == "mount" and MountPreviewData(event) or PetPreviewData(event)
        if not data then
            return
        end
        local preview = EnsureCollectionPreview()
        preview.Title:SetText(data.name or (kind == "mount" and "Mount" or "Battle pet"))
        preview.Kind:SetText(kind == "mount" and "Mount" or "Battle pet")
        local modelShown = SetPreviewModel(preview.Model, data.displayID, kind == "mount" and 0.82 or 0.64)
        preview.Model:SetShown(modelShown)

        local detailBits = {}
        if kind == "mount" then
            detailBits[#detailBits + 1] = data.collected and "Collected" or "Mount"
            if data.description and data.description ~= "" then
                detailBits[#detailBits + 1] = data.description
            end
            preview.Footer:SetText("Click to open this mount in the Mount Journal")
        else
            if data.owned ~= nil then
                local ownedText = "Owned: " .. tostring(data.owned)
                if data.limit and data.limit > 0 then
                    ownedText = ownedText .. " / " .. tostring(data.limit)
                end
                detailBits[#detailBits + 1] = ownedText
            end
            if data.bestLevel and data.bestLevel > 0 then
                local best = "Best: Level " .. data.bestLevel
                if data.bestQuality then
                    best = best .. " · " .. (PET_QUALITY_NAMES[data.bestQuality] or ("Quality " .. data.bestQuality))
                end
                detailBits[#detailBits + 1] = best
            end
            if data.capturedLevel or data.capturedQuality then
                local captured = "When recorded:"
                if data.capturedLevel then
                    captured = captured .. " Level " .. data.capturedLevel
                end
                if data.capturedQuality then
                    captured = captured .. " · " .. (PET_QUALITY_NAMES[data.capturedQuality] or ("Quality " .. data.capturedQuality))
                end
                detailBits[#detailBits + 1] = captured
            end
            if data.description and data.description ~= "" then
                detailBits[#detailBits + 1] = data.description
            end
            preview.Footer:SetText("Click to open this pet in the Pet Journal")
        end
        preview.Details:SetText(table.concat(detailBits, "\n"))
        if data.source and data.source ~= "" then
            preview.Source:SetText("Source: " .. data.source)
            preview.Source:Show()
        else
            preview.Source:SetText("")
            preview.Source:Hide()
        end
        PositionCollectionPreview(preview)
        preview:Show()
    end)
end

local function CollectionOpenError(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(text, 1, 0.35, 0.25)
    elseif print then
        print("WarbandFYI: " .. text)
    end
end

local function OpenCollectionsTab(tab)
    if InCombatLockdown and InCombatLockdown() then
        CollectionOpenError("Collections cannot be opened while in combat.")
        return false
    end
    if not CollectionsJournal and CollectionsJournal_LoadUI then
        pcall(CollectionsJournal_LoadUI)
    end
    if not CollectionsJournal then
        CollectionOpenError("The Collections Journal is not available yet.")
        return false
    end
    if CollectionsJournal:IsShown() then
        if CollectionsJournal_SetTab then
            pcall(CollectionsJournal_SetTab, CollectionsJournal, tab)
        end
    elseif ToggleCollectionsJournal then
        pcall(ToggleCollectionsJournal, tab)
        if CollectionsJournal:IsShown() and CollectionsJournal_SetTab then
            pcall(CollectionsJournal_SetTab, CollectionsJournal, tab)
        end
    elseif ShowUIPanel then
        pcall(ShowUIPanel, CollectionsJournal)
        if CollectionsJournal_SetTab then
            pcall(CollectionsJournal_SetTab, CollectionsJournal, tab)
        end
    end
    return CollectionsJournal:IsShown()
end

function WBF.UI.OpenCollectionJournal(kind, event)
    WBF.UI.HideCollectionPreview()
    if not event then
        return
    end
    if kind == "mount" then
        local mountID = ResolveMountID(event)
        if not mountID then
            CollectionOpenError("This older mount record does not contain a mount ID.")
            return
        end
        if not OpenCollectionsTab(1) then
            return
        end
        if WBF.UI.frame and WBF.UI.frame.Hide then
            WBF.UI.frame:Hide()
        end
        if MountJournal_SelectByMountID then
            local ok = pcall(MountJournal_SelectByMountID, mountID)
            if ok then
                return
            end
        end
        local name = C_MountJournal and C_MountJournal.GetMountInfoByID and select(1, C_MountJournal.GetMountInfoByID(mountID))
        if name and C_MountJournal and C_MountJournal.SetSearch then
            pcall(C_MountJournal.SetSearch, name)
        end
        return
    end

    if kind == "pet" then
        local speciesID = ResolveSpeciesID(event)
        if not speciesID then
            CollectionOpenError("This older pet record does not contain a species ID.")
            return
        end
        if not OpenCollectionsTab(2) then
            return
        end
        if WBF.UI.frame and WBF.UI.frame.Hide then
            WBF.UI.frame:Hide()
        end
        local meta = event.meta or {}
        if meta.petID and PetJournal_SelectPet and PetJournal then
            local ok = pcall(PetJournal_SelectPet, PetJournal, meta.petID)
            if ok then
                return
            end
        end
        if PetJournal_SelectSpecies and PetJournal then
            local ok = pcall(PetJournal_SelectSpecies, PetJournal, speciesID)
            if ok then
                return
            end
        end
        if C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID and C_PetJournal.SetSearchFilter then
            local ok, name = pcall(C_PetJournal.GetPetInfoBySpeciesID, speciesID)
            if ok and name then
                pcall(C_PetJournal.SetSearchFilter, name)
            end
        end
    end
end

function WBF.UI.DetailCategory(event)
    local kind = event and event.eventType
    if kind == WBF.EventType.BossKill then
        return "bosses"
    end
    if kind == WBF.EventType.InstanceEnter then
        local meta = event.meta or {}
        if meta.instanceType == "raid" then
            return "raids"
        end
        if meta.instanceType == "party" and not meta.keystone then
            return "dungeons"
        end
        return nil
    end
    if WBF.Quests and WBF.Quests.EffectiveType then
        kind = WBF.Quests.EffectiveType(event)
    end
    if kind == WBF.EventType.Quest then
        return "quests"
    end
    if kind == WBF.EventType.WorldQuest then
        return "worldQuests"
    end
    if kind == WBF.EventType.WorldEvent then
        if WBF.Quests and WBF.Quests.IsCurseSurgeEvent and WBF.Quests.IsCurseSurgeEvent(event) then
            return "curseSurges"
        end
        return "worldEvents"
    end
    if kind == WBF.EventType.Achievement then
        return "achievements"
    end
    if kind == WBF.EventType.Mount then
        return "mounts"
    end
    if kind == WBF.EventType.Pet or kind == WBF.EventType.PetBattle then
        return "petBattles"
    end
    if kind == WBF.EventType.Appearance then
        return "appearances"
    end
    if kind == WBF.EventType.HousingDecor or kind == WBF.EventType.HousingAcquire or kind == WBF.EventType.HousingXP then
        return "housing"
    end
    if kind == WBF.EventType.MythicPlus then
        return "mythicPlus"
    end
    if kind == WBF.EventType.Reputation then
        return "reputation"
    end
    if kind == WBF.EventType.Renown then
        return "renown"
    end
    if kind == WBF.EventType.Delve then
        return "delves"
    end
    if kind == WBF.EventType.Profession then
        return "professions"
    end
    if kind == WBF.EventType.ItemLevel then
        return "itemLevel"
    end
    if kind == WBF.EventType.Level then
        return "character"
    end
    if kind == WBF.EventType.Prey then
        return "prey"
    end
    if kind == WBF.EventType.Resource then
        return "resource"
    end
    return nil
end

function WBF.UI.EventTextColor(event)
    local meta = event.meta or {}
    if meta.quality then
        return WBF.Format.QualityColor(meta.quality)
    end
    if event.eventType == WBF.EventType.ItemLevel and (event.delta or 0) > 0 then
        return WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3]
    end
    if event.eventType == WBF.EventType.Renown and (event.delta or 0) < 0 then
        return WBF.UI.Colors.red[1], WBF.UI.Colors.red[2], WBF.UI.Colors.red[3]
    end
    if event.eventType == WBF.EventType.Level or event.eventType == WBF.EventType.Renown then
        return WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3]
    end
    if event.eventType == WBF.EventType.Reputation and (event.delta or 0) > 0 then
        return WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3]
    end
    if event.eventType == WBF.EventType.Profession and (event.delta or 0) >= 0 then
        return WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3]
    end
    if event.eventType == WBF.EventType.Resource and (event.delta or 0) > 0 then
        local classification = event.meta and event.meta.classification
        if classification ~= "transfer" and classification ~= "sync" and classification ~= "baseline" then
            return WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3]
        end
    end
    if event.eventType == WBF.EventType.Resource and (event.delta or 0) < 0 then
        local classification = event.meta and event.meta.classification
        if classification ~= "transfer" then
            return WBF.UI.Colors.red[1], WBF.UI.Colors.red[2], WBF.UI.Colors.red[3]
        end
    end
    return WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3]
end

local function SectionPool()
    return WBF.UI.Pool("section", function(parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetHeight(20)
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", 0, 0)
        Color(text, WBF.UI.Colors.gold)
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", text, "RIGHT", 10, 0)
        line:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        line:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], WBF.UI.Colors.line[4])
        frame.Text = text
        frame.SetTitle = function(self, title)
            self.Text:SetText(title)
        end
        return frame
    end)
end

function WBF.UI.AcquireSection(parent, title, x, y, width)
    local frame = WBF.UI.Acquire(SectionPool(), parent)
    frame:SetWidth(width)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    frame:SetTitle(title)
    return frame
end

local function StatPool()
    return WBF.UI.Pool("stat", function(parent)
        local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
        frame:RegisterForClicks("LeftButtonUp")
        frame:SetHeight(64)
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        WBF.UI.BindWheel(frame)
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("LEFT", 10, 0)
        local value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        value:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 6)
        value:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        value:SetJustifyH("LEFT")
        value:SetWordWrap(false)
        Enlarge(value, GameFontNormalLarge, 1)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -2)
        label:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        Color(label, WBF.UI.Colors.muted)
        local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detail:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
        detail:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        detail:SetJustifyH("LEFT")
        detail:SetWordWrap(false)
        Color(detail, WBF.UI.Colors.muted)
        detail:Hide()
        frame.Icon = icon
        frame.Value = value
        frame.Label = label
        frame.Detail = detail
        frame.Apply = function(self, data)
            if data.texture then
                self.Icon:SetTexture(data.texture)
            else
                WBF.UI.SetAtlasChain(self.Icon, data.atlases, data.fallback)
            end
            self.Value:SetText(data.value)
            Color(self.Value, data.color or WBF.UI.Colors.cream)
            self.Label:SetText(data.label)
            if data.detail and data.detail ~= "" then
                self.Detail:SetText(data.detail)
                self.Detail:Show()
            else
                self.Detail:Hide()
            end
            WBF.UI.BindCard(self, data, function(tooltip)
                tooltip:SetText(data.label, 1, 0.82, 0.45)
                if data.tooltip then
                    tooltip:AddLine(data.tooltip, 0.9, 0.9, 0.9, true)
                end
            end)
        end
        return frame
    end)
end

function WBF.UI.AcquireStat(parent)
    return WBF.UI.Acquire(StatPool(), parent)
end

local function HighlightPool()
    return WBF.UI.Pool("highlight", function(parent)
        local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
        frame:RegisterForClicks("LeftButtonUp")
        frame:SetHeight(86)
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        WBF.UI.BindWheel(frame)
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(36, 36)
        icon:SetPoint("LEFT", 12, 2)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", 58, -14)
        title:SetPoint("RIGHT", -10, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        local value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        value:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        value:SetPoint("RIGHT", -10, 0)
        value:SetJustifyH("LEFT")
        value:SetWordWrap(false)
        value:SetHeight(22)
        Enlarge(value, GameFontNormalLarge, 0)
        local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detail:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -2)
        detail:SetPoint("RIGHT", -10, 0)
        detail:SetJustifyH("LEFT")
        detail:SetWordWrap(false)
        frame.Icon = icon
        frame.Title = title
        frame.Value = value
        frame.Detail = detail
        frame.Apply = function(self, data)
            if data.texture then
                self.Icon:SetTexture(data.texture)
            else
                WBF.UI.SetAtlasChain(self.Icon, { data.atlas }, data.fallback)
            end
            self.Title:SetText(data.title or "")
            if data.classFile then
                self.Title:SetTextColor(WBF.Format.ClassColor(data.classFile))
            else
                Color(self.Title, WBF.UI.Colors.muted)
            end
            self.Value:SetText(data.value or "")
            Color(self.Value, WBF.UI.Colors.cream)
            if data.detail and data.detail ~= "" then
                self.Detail:SetText(data.detail)
                self.Detail:Show()
                Color(self.Detail, data.detailGreen and WBF.UI.Colors.green or WBF.UI.Colors.gold)
            else
                self.Detail:SetText("")
                self.Detail:Hide()
            end
            WBF.UI.BindCard(self, data, function(tooltip)
                tooltip:SetText(data.title or "", 1, 0.82, 0.45)
                if data.value then
                    tooltip:AddLine(data.value, 1, 1, 1)
                end
                if data.detail then
                    tooltip:AddLine(data.detail, 0.8, 0.8, 0.8)
                end
            end)
        end
        return frame
    end)
end

function WBF.UI.AcquireHighlight(parent)
    return WBF.UI.Acquire(HighlightPool(), parent)
end

local function CharacterPool()
    return WBF.UI.Pool("character", function(parent)
        local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
        frame:RegisterForClicks("LeftButtonUp")
        frame:SetHeight(128)
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        WBF.UI.BindWheel(frame)
        local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.04)

        local holder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        holder:SetSize(50, 50)
        holder:SetPoint("TOPLEFT", 10, -10)
        WBF.UI.Paint(holder, { 0.02, 0.02, 0.03, 1 }, WBF.UI.Colors.gold)
        local portrait = holder:CreateTexture(nil, "ARTWORK")
        portrait:SetPoint("TOPLEFT", 1, -1)
        portrait:SetPoint("BOTTOMRIGHT", -1, -1)

        local played = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        played:SetPoint("TOPRIGHT", -12, -14)
        Color(played, WBF.UI.Colors.muted)
        frame.Played = played

        local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        name:SetPoint("TOPLEFT", holder, "TOPRIGHT", 10, -2)
        name:SetPoint("RIGHT", played, "LEFT", -8, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)

        local spec = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        spec:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
        spec:SetPoint("RIGHT", -12, 0)
        spec:SetJustifyH("LEFT")
        spec:SetWordWrap(false)
        Color(spec, WBF.UI.Colors.muted)

        local ilvlLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ilvlLabel:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -8)
        Color(ilvlLabel, WBF.UI.Colors.gold)
        ilvlLabel:SetText("Item Level")

        local ilvl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ilvl:SetPoint("TOPLEFT", ilvlLabel, "BOTTOMLEFT", 0, -1)
        Color(ilvl, WBF.UI.Colors.cream)

        local delta = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        delta:SetPoint("LEFT", ilvl, "RIGHT", 8, 0)

        local line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("BOTTOMLEFT", 12, 10)
        line:SetPoint("BOTTOMRIGHT", -12, 10)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        Color(line, WBF.UI.Colors.cream)

        frame.Apply = function(self, data, playedSeconds)
            WBF.UI.SetPortrait(portrait, data.guid, data.classFile)
            name:SetText(data.name or "Unknown")
            name:SetTextColor(WBF.Format.ClassColor(data.classFile))
            if playedSeconds == nil then
                playedSeconds = data.playedSeconds or 0
            end
            played:SetText(WBF.Format.Played(playedSeconds))

            local level = data.levelEnd or data.levelStart
            local levelText = level and ("Level " .. level) or "Level unknown"
            if data.levelStart and data.levelEnd and data.levelEnd > data.levelStart then
                levelText = "Level " .. WBF.Format.Progression(data.levelStart, data.levelEnd)
            end
            if data.specName and data.specName ~= "" then
                spec:SetText(levelText .. "   |   " .. data.specName)
            elseif data.className then
                spec:SetText(levelText .. "   |   " .. data.className)
            else
                spec:SetText(levelText)
            end

            if data.ilvlStart and data.ilvlEnd and data.ilvlStart ~= data.ilvlEnd then
                ilvl:SetText(WBF.Format.Progression(data.ilvlStart, data.ilvlEnd))
                local gain = data.ilvlEnd - data.ilvlStart
                delta:SetText(WBF.Format.Signed(gain))
                Color(delta, gain > 0 and WBF.UI.Colors.green or WBF.UI.Colors.red)
                delta:Show()
            elseif data.ilvlEnd or data.ilvlStart then
                ilvl:SetText(tostring(data.ilvlEnd or data.ilvlStart))
                delta:Hide()
            else
                ilvl:SetText("—")
                delta:Hide()
            end

            local summary = WBF.Format.ActivityLine(data.counts or {}, data.counts and data.counts.gold or 0)
            if data.resourceLine and data.resourceLine ~= "" then
                summary = summary and (summary .. "    ·    " .. data.resourceLine) or data.resourceLine
            end
            if summary then
                line:SetText(summary)
                line:Show()
            else
                line:Hide()
            end

            local payload = {}
            for key, value in pairs(data) do
                payload[key] = value
            end
            payload.open = "character"
            payload.characterGUID = data.guid
            WBF.UI.BindCard(self, payload, function(tooltip)
                tooltip:SetText(data.name or "Character", WBF.Format.ClassColor(data.classFile))
                if data.realm and data.realm ~= "" then
                    tooltip:AddLine(data.realm, 0.7, 0.7, 0.7)
                end
            end)
        end
        return frame
    end)
end

function WBF.UI.AcquireCharacter(parent)
    return WBF.UI.Acquire(CharacterPool(), parent)
end

local function TilePool()
    return WBF.UI.Pool("tile", function(parent)
        local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
        frame:RegisterForClicks("LeftButtonUp")
        frame:SetHeight(58)
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        WBF.UI.BindWheel(frame)
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", 10, -8)
        local value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        value:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        value:SetPoint("RIGHT", -8, 0)
        value:SetJustifyH("LEFT")
        value:SetWordWrap(false)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("BOTTOMLEFT", 10, 8)
        label:SetPoint("RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        Color(label, WBF.UI.Colors.muted)
        local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        detail:SetJustifyH("LEFT")
        detail:SetWordWrap(false)
        Color(detail, WBF.UI.Colors.muted)
        detail:Hide()
        local subline = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        subline:SetJustifyH("LEFT")
        subline:SetJustifyV("TOP")
        -- Resource cards put gained and spent on separate lines.
        subline:SetWordWrap(true)
        subline:SetSpacing(1)
        subline:Hide()
        local chevron = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chevron:SetText(">")
        Color(chevron, WBF.UI.Colors.gold)
        chevron:Hide()
        frame.Apply = function(self, data)
            if data.texture then
                icon:SetTexture(data.texture)
            else
                WBF.UI.SetAtlasChain(icon, data.atlases, data.fallback)
            end
            value:SetText(data.value)
            Color(value, data.color or WBF.UI.Colors.cream)
            label:SetText(data.label)
            icon:ClearAllPoints()
            value:ClearAllPoints()
            label:ClearAllPoints()
            detail:ClearAllPoints()
            subline:ClearAllPoints()
            chevron:ClearAllPoints()
            if data.resource then
                icon:SetSize(26, 26)
                icon:SetPoint("LEFT", 8, 0)
                chevron:SetPoint("RIGHT", -8, 0)
                chevron:Show()
                value:SetPoint("TOPLEFT", 40, -8)
                value:SetPoint("RIGHT", -18, 0)
                Enlarge(value, GameFontNormalLarge, 1)
                label:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -1)
                label:SetPoint("RIGHT", -18, 0)
                Color(label, WBF.UI.Colors.cream)
                local anchor = label
                if data.subline and data.subline ~= "" then
                    subline:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
                    subline:SetPoint("RIGHT", -18, 0)
                    subline:SetText(data.subline)
                    subline:Show()
                    anchor = subline
                else
                    subline:Hide()
                end
                if data.detail and data.detail ~= "" then
                    detail:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -1)
                    detail:SetPoint("RIGHT", -18, 0)
                    detail:SetText(data.detail)
                    detail:Show()
                else
                    detail:Hide()
                end
            else
                icon:SetSize(18, 18)
                icon:SetPoint("TOPLEFT", 10, -8)
                Enlarge(value, GameFontNormalLarge, 0)
                value:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                value:SetPoint("RIGHT", -8, 0)
                chevron:Hide()
                subline:Hide()
                Color(label, WBF.UI.Colors.muted)
                if data.detail and data.detail ~= "" then
                    label:SetPoint("BOTTOMLEFT", 10, 22)
                    label:SetPoint("RIGHT", -8, 0)
                    detail:SetPoint("BOTTOMLEFT", 10, 6)
                    detail:SetPoint("RIGHT", -8, 0)
                    detail:SetText(data.detail)
                    detail:Show()
                else
                    label:SetPoint("BOTTOMLEFT", 10, 8)
                    label:SetPoint("RIGHT", -8, 0)
                    detail:Hide()
                end
            end
            WBF.UI.BindCard(self, data, function(tooltip)
                tooltip:SetText(data.label, 1, 0.82, 0.45)
                if data.tooltip then
                    tooltip:AddLine(data.tooltip, 0.9, 0.9, 0.9, true)
                end
            end)
        end
        return frame
    end)
end

function WBF.UI.AcquireTile(parent)
    return WBF.UI.Acquire(TilePool(), parent)
end

local function ActivityPool()
    return WBF.UI.Pool("activity", function(parent)
        local frame = CreateFrame("Button", nil, parent)
        frame:RegisterForClicks("LeftButtonUp")
        frame:SetHeight(24)
        WBF.UI.BindWheel(frame)
        local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.04)
        local timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeText:SetPoint("LEFT", 0, 0)
        timeText:SetWidth(58)
        timeText:SetJustifyH("LEFT")
        timeText:SetWordWrap(false)
        Color(timeText, WBF.UI.Colors.muted)
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", timeText, "RIGHT", 4, 0)
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        text:SetPoint("RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        frame.Apply = function(self, event)
            timeText:SetText(WBF.Format.Ago(event.at))
            WBF.UI.ApplyEventIcon(icon, event)
            local shown = event.text or ""
            if WBF.Quests and WBF.Quests.ActivityText then
                shown = WBF.Quests.ActivityText(event)
            end
            text:SetText(WBF.Format.DisplayText(shown))
            text:SetTextColor(WBF.UI.EventTextColor(event))
            local category = WBF.UI.DetailCategory(event)
            WBF.UI.Tooltip(self, function(tooltip)
                WBF.UI.EventTooltip(tooltip, event)
                if category then
                    tooltip:AddLine("Click to see the records.", 0.9, 0.82, 0.45)
                end
            end)
            if category then
                self:SetScript("OnClick", function()
                    if not WBF.UI.frame then
                        return
                    end
                    local guid = nil
                    if WBF.UI.frame.view == "activity" then
                        guid = WBF.UI.characterFilter
                    end
                    if category == "itemLevel" or category == "character" then
                        guid = event.guid or guid
                    end
                    local tab = nil
                    if event.eventType == WBF.EventType.Profession then
                        local professionGuid = event.guid or guid
                        if professionGuid then
                            category = "character"
                            guid = professionGuid
                            tab = "professions"
                        end
                    end
                    WBF.UI.frame:OpenDetail(category, {
                        characterGUID = guid,
                        resourceKey = event.meta and event.meta.resourceKey or nil,
                        tab = tab,
                        warband = category == "petBattles" and not guid or nil,
                    })
                end)
            else
                self:SetScript("OnClick", nil)
            end
        end
        return frame
    end)
end

function WBF.UI.AcquireActivity(parent)
    return WBF.UI.Acquire(ActivityPool(), parent)
end

local function RosterPool()
    return WBF.UI.Pool("roster", function(parent)
        local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
        frame:RegisterForClicks("LeftButtonUp")
        frame:SetHeight(54)
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        WBF.UI.BindWheel(frame)
        local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.04)
        local holder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        holder:SetSize(40, 40)
        holder:SetPoint("LEFT", 8, 0)
        WBF.UI.Paint(holder, { 0.02, 0.02, 0.03, 1 }, WBF.UI.Colors.gold)
        local portrait = holder:CreateTexture(nil, "ARTWORK")
        portrait:SetPoint("TOPLEFT", 1, -1)
        portrait:SetPoint("BOTTOMRIGHT", -1, -1)
        local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("TOPLEFT", holder, "TOPRIGHT", 10, -4)
        name:SetJustifyH("LEFT")
        local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detail:SetPoint("BOTTOMLEFT", holder, "BOTTOMRIGHT", 10, 4)
        detail:SetJustifyH("LEFT")
        Color(detail, WBF.UI.Colors.muted)
        local right = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        right:SetPoint("RIGHT", -12, 6)
        right:SetJustifyH("RIGHT")
        local seen = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        seen:SetPoint("RIGHT", -12, -10)
        seen:SetJustifyH("RIGHT")
        Color(seen, WBF.UI.Colors.muted)
        frame.Apply = function(self, character)
            WBF.UI.SetPortrait(portrait, character.guid, character.classFile)
            name:SetText(character.name or "Unknown")
            name:SetTextColor(WBF.Format.ClassColor(character.classFile))
            local bits = {}
            if character.className then
                bits[#bits + 1] = character.className
            end
            if character.specName and character.specName ~= "" then
                bits[#bits + 1] = character.specName
            end
            if character.realm and character.realm ~= "" then
                bits[#bits + 1] = character.realm
            end
            detail:SetText(table.concat(bits, "   ·   "))
            local progress = {}
            if character.level then
                progress[#progress + 1] = "Level " .. character.level
            end
            if character.itemLevel then
                progress[#progress + 1] = "ilvl " .. character.itemLevel
            end
            right:SetText(table.concat(progress, "   "))
            Color(right, WBF.UI.Colors.cream)
            if character.lastSeenAt then
                seen:SetText(WBF.Format.Ago(character.lastSeenAt))
            else
                seen:SetText("")
            end
            WBF.UI.BindCard(self, {
                open = "character",
                characterGUID = character.guid,
                period = "warband",
            }, function(tooltip)
                tooltip:SetText(character.name or "Character", WBF.Format.ClassColor(character.classFile))
            end)
        end
        return frame
    end)
end

function WBF.UI.AcquireRoster(parent)
    return WBF.UI.Acquire(RosterPool(), parent)
end

-- History curves. Callers pass an already-sampled polyline in plot coordinates;
-- this draws a soft gradient fill down to the baseline, a faint glow and a crisp
-- core stroke. Pixel snapping is disabled so the many short, slightly rotated
-- segments blend into one continuous line instead of a stepped, dotted one.
local UPPER_LEFT_VERTEX, LOWER_LEFT_VERTEX, UPPER_RIGHT_VERTEX, LOWER_RIGHT_VERTEX = 1, 2, 3, 4

-- Line.tga is white with feathered top/bottom rows, so a stroke drawn with it
-- is anti-aliased; a flat colour texture leaves sloped lines stair-stepped.
-- Dot.tga is an anti-aliased disc for chart markers.
WBF.UI.Media = {
    line = "Interface\\AddOns\\WarbandFYI\\Media\\Line.tga",
    dot = "Interface\\AddOns\\WarbandFYI\\Media\\Dot.tga",
}

local function Unsnap(region)
    if region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
    end
    if region.SetTexelSnappingBias then
        region:SetTexelSnappingBias(0)
    end
end

local function CurvePool(plot)
    local pool = plot.wbfCurve
    if not pool then
        pool = { fills = {}, glows = {}, cores = {} }
        plot.wbfCurve = pool
    end
    return pool
end

local function CurveStroke(plot, list, index, thickness, alpha, subLevel, xA, yA, xB, yB)
    local line = list[index]
    if not line then
        line = plot:CreateLine(nil, "ARTWORK", nil, subLevel)
        line:SetTexture(WBF.UI.Media.line, "CLAMP", "CLAMP", "TRILINEAR")
        Unsnap(line)
        list[index] = line
    end
    local gold = WBF.UI.Colors.gold
    line:SetVertexColor(gold[1], gold[2], gold[3], alpha)
    line:SetThickness(thickness)
    line:ClearAllPoints()
    line:SetStartPoint("BOTTOMLEFT", plot, xA, yA)
    line:SetEndPoint("BOTTOMLEFT", plot, xB, yB)
    line:Show()
end

-- One trapezoid column between the curve and the baseline. Both ends must sit
-- on the same side of the baseline; DrawCurve splits segments that cross it.
local function CurveFill(plot, pool, index, xA, yA, xB, yB, base)
    local fill = pool.fills[index]
    if not fill then
        fill = plot:CreateTexture(nil, "BACKGROUND", nil, 2)
        fill:SetColorTexture(1, 1, 1, 1)
        Unsnap(fill)
        pool.fills[index] = fill
    end
    local above = yA + yB >= 2 * base
    local edge = above and math.max(yA, yB) or math.min(yA, yB)
    local height = math.abs(edge - base)
    if height < 0.5 or xB - xA < 0.01 or not fill.SetVertexOffset then
        fill:Hide()
        return
    end
    for vertex = 1, 4 do
        fill:SetVertexOffset(vertex, 0, 0)
    end
    local gold = WBF.UI.Colors.gold
    local strong = CreateColor(gold[1], gold[2], gold[3], 0.2)
    local faint = CreateColor(gold[1], gold[2], gold[3], 0)
    fill:ClearAllPoints()
    fill:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", xA, above and base or edge)
    fill:SetSize(xB - xA, height)
    if above then
        fill:SetGradient("VERTICAL", faint, strong)
        fill:SetVertexOffset(UPPER_LEFT_VERTEX, 0, yA - edge)
        fill:SetVertexOffset(UPPER_RIGHT_VERTEX, 0, yB - edge)
    else
        fill:SetGradient("VERTICAL", strong, faint)
        fill:SetVertexOffset(LOWER_LEFT_VERTEX, 0, yA - edge)
        fill:SetVertexOffset(LOWER_RIGHT_VERTEX, 0, yB - edge)
    end
    fill:Show()
end

function WBF.UI.HideCurve(plot)
    local pool = plot.wbfCurve
    if not pool then
        return
    end
    for _, list in pairs(pool) do
        for index = 1, #list do
            list[index]:Hide()
        end
    end
end

-- Douglas-Peucker: drop samples that sit within `tolerance` pixels of the
-- straight line between their neighbours. Every joint between two stroke
-- segments leaves a small kink, so gentle stretches read far cleaner as one
-- long segment than as dozens of 4px ones.
local function SimplifyPath(xs, ys, tolerance)
    local count = #xs
    if count <= 2 then
        return xs, ys
    end
    local keep = { [1] = true, [count] = true }
    local stack = { { 1, count } }
    while #stack > 0 do
        local range = table.remove(stack)
        local first, last = range[1], range[2]
        local ax, ay = xs[first], ys[first]
        local dx, dy = xs[last] - ax, ys[last] - ay
        local length = math.sqrt(dx * dx + dy * dy)
        local worst, worstIndex = 0, nil
        for index = first + 1, last - 1 do
            local distance
            if length < 0.0001 then
                distance = math.sqrt((xs[index] - ax) ^ 2 + (ys[index] - ay) ^ 2)
            else
                distance = math.abs(dy * (xs[index] - ax) - dx * (ys[index] - ay)) / length
            end
            if distance > worst then
                worst, worstIndex = distance, index
            end
        end
        if worstIndex and worst > tolerance then
            keep[worstIndex] = true
            stack[#stack + 1] = { first, worstIndex }
            stack[#stack + 1] = { worstIndex, last }
        end
    end
    local outXs, outYs = {}, {}
    for index = 1, count do
        if keep[index] then
            outXs[#outXs + 1] = xs[index]
            outYs[#outYs + 1] = ys[index]
        end
    end
    return outXs, outYs
end

function WBF.UI.DrawCurve(plot, xs, ys, base)
    WBF.UI.HideCurve(plot)
    local pool = CurvePool(plot)
    base = base or 0
    xs, ys = SimplifyPath(xs, ys, 0.35)
    local fills = 0
    local strokes = 0
    for index = 1, #xs - 1 do
        local xA, yA, xB, yB = xs[index], ys[index], xs[index + 1], ys[index + 1]
        if (yA - base) * (yB - base) < 0 then
            local crossX = xA + (xB - xA) * (base - yA) / (yB - yA)
            fills = fills + 1
            CurveFill(plot, pool, fills, xA, yA, crossX, base, base)
            fills = fills + 1
            CurveFill(plot, pool, fills, crossX, base, xB, yB, base)
        else
            fills = fills + 1
            CurveFill(plot, pool, fills, xA, yA, xB, yB, base)
        end
        local dx, dy = xB - xA, yB - yA
        if dx * dx + dy * dy >= 0.01 then
            strokes = strokes + 1
            CurveStroke(plot, pool.glows, strokes, 9, 0.16, 1, xA, yA, xB, yB)
            CurveStroke(plot, pool.cores, strokes, 4, 1, 3, xA, yA, xB, yB)
        end
    end
end
