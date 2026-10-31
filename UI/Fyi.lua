local _, WBF = ...

-- Compact zone reminder. It never opens a page or a sheet on its own.
WBF.UI.Fyi = {}

local popup
local popupTitle
local popupIcons
local popupCount
local popupScroll
local popupChild
local popupBar
local popupHide
local popupHideNote
local popupPage
local popupSheet
local popupCards
local popupHunts
-- Cards that join whichever popup is on screen instead of waiting for their
-- own, such as the warband Collection Hunts list. Each is a builder so the
-- card stays current while the popup is redrawn. Closing the popup drops them.
local attached = {}
local attachedOrder = {}
local setup
local setupHeading
local setupTitle
local setupHint
local setupSearch
local setupPlaceholder
local setupStatus
local setupRows
local setupSave
local setupTarget
local setupExisting
local setupEnabled
local setupRemove
local setupMode
local setupChoice
local setupEventButton
local setupZoneButton
local setupContextLabel
local setupCharacterButton
local setupCharacterGuid
local setupLoginButton
local manage
local manageRows
local manageEmpty
local rowMenu
local rowMenuCatcher
local popupCountdownGeneration = 0
local Color

local function Now()
    if WBF.Time and WBF.Time.Now then
        return WBF.Time.Now()
    end
    if type(time) == "function" then
        return time()
    end
    return 0
end

local function CountdownText(endStamp, now)
    endStamp = tonumber(endStamp)
    if not endStamp then
        return nil, nil, false
    end
    now = now or Now()
    local remaining = endStamp - now
    if remaining <= 0 then
        return nil, nil, false
    end

    local unit
    local value
    local boundary
    if remaining >= 86400 then
        unit = "day"
        value = math.ceil(remaining / 86400)
        boundary = (value - 1) * 86400
    elseif remaining >= 3600 then
        unit = "hour"
        value = math.ceil(remaining / 3600)
        boundary = (value - 1) * 3600
    elseif remaining >= 60 then
        unit = "min"
        value = math.ceil(remaining / 60)
        boundary = (value - 1) * 60
    else
        return "Ending soon", math.max(1, remaining + 0.2), true
    end

    local suffix = unit
    if unit ~= "min" and value ~= 1 then
        suffix = unit .. "s"
    end
    local delay = math.max(1, (remaining - boundary) + 0.2)
    return string.format("Ends in %d %s", value, suffix), delay, remaining <= 3600
end

local function ScheduleCountdownRefresh()
    popupCountdownGeneration = popupCountdownGeneration + 1
    local generation = popupCountdownGeneration
    if not (popup and popup:IsShown() and popup.contextType == "WOW_EVENT") then
        return
    end

    local now = Now()
    local nextDelay = nil
    for index = 1, #(popupCards or {}) do
        local card = popupCards[index]
        if card and card:IsShown() and card.Ends then
            local text, delay, urgent = CountdownText(card.endStamp, now)
            card.Ends:SetText(text or "")
            card.Ends:SetShown(text and text ~= "" or false)
            if text then
                Color(card.Ends, urgent and WBF.UI.Colors.gold or WBF.UI.Colors.muted)
            end
            if delay and (not nextDelay or delay < nextDelay) then
                nextDelay = delay
            end
        end
    end

    if nextDelay and C_Timer and C_Timer.After then
        C_Timer.After(nextDelay, function()
            if generation ~= popupCountdownGeneration then
                return
            end
            if popup and popup:IsShown() and popup.contextType == "WOW_EVENT" then
                ScheduleCountdownRefresh()
            end
        end)
    end
end

local function UpdatePopupScrollBar()
    if not popupScroll or not popupBar then
        return
    end
    local range = popupScroll:GetVerticalScrollRange() or 0
    if range <= 1 then
        popupBar:Hide()
        popupScroll:SetVerticalScroll(0)
        return
    end
    popupBar:Show()
    popupBar.updating = true
    popupBar:SetMinMaxValues(0, range)
    local value = math.min(popupScroll:GetVerticalScroll() or 0, range)
    popupBar:SetValue(value)
    popupBar.updating = false

    if popupBar.Thumb and popupScroll.GetHeight and popupChild and popupChild.GetHeight then
        local visible = math.max(popupScroll:GetHeight() or 0, 1)
        local total = math.max(popupChild:GetHeight() or visible, visible)
        local thumbHeight = math.floor(math.max(28, math.min(72, visible * (visible / total))))
        popupBar.Thumb:SetHeight(thumbHeight)
    end
end

local function ScrollPopup(delta)
    if not popupScroll then
        return
    end
    local range = popupScroll:GetVerticalScrollRange() or 0
    if range <= 0 then
        popupScroll:SetVerticalScroll(0)
        UpdatePopupScrollBar()
        return
    end
    local nextValue = (popupScroll:GetVerticalScroll() or 0) - ((delta or 0) * 32)
    if nextValue < 0 then
        nextValue = 0
    elseif nextValue > range then
        nextValue = range
    end
    popupScroll:SetVerticalScroll(nextValue)
    UpdatePopupScrollBar()
end

local function BindPopupWheel(frame)
    if not frame then
        return
    end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        ScrollPopup(delta)
    end)
end

local function Shown(text)
    if type(text) ~= "string" then
        return ""
    end
    return (text:gsub("|", "||"))
end

Color = function(widget, color)
    widget:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function PaintButton(button)
    if button._selected then
        WBF.UI.Paint(button, WBF.UI.Colors.blue, WBF.UI.Colors.gold)
    else
        WBF.UI.Paint(button, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    end
    Color(button.Label, WBF.UI.Colors.cream)
end

local function MakeButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 20)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    button.Label = label
    PaintButton(button)
    button:SetScript("OnEnter", function(self)
        WBF.UI.Paint(self, WBF.UI.Colors.blue, WBF.UI.Colors.gold)
    end)
    button:SetScript("OnLeave", function(self)
        PaintButton(self)
    end)
    return button
end

local function CloseRowMenu()
    if rowMenu then
        rowMenu:Hide()
    end
    if rowMenuCatcher then
        rowMenuCatcher:Hide()
    end
end

local function EnsurePopup()
    if popup then
        return
    end
    popup = CreateFrame("Frame", "WarbandFYIFyiPopup", UIParent, "BackdropTemplate")
    popup:SetSize(320, 180)
    popup:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -160)
    popup:SetFrameStrata("HIGH")
    popup:SetToplevel(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:SetClampedToScreen(true)

    local saved = WarbandFYI_DB and WarbandFYI_DB.config and WarbandFYI_DB.config.fyiPopup
    if type(saved) == "table" and saved.point then
        popup:ClearAllPoints()
        popup:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
    end

    popup:Hide()
    popup:SetScript("OnHide", function()
        CloseRowMenu()
        attached, attachedOrder = {}, {}
        popupCountdownGeneration = popupCountdownGeneration + 1
        -- A short pause so the next queued FYI reads as a new popup.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function() WBF.UI.Fyi.ShowQueued() end)
        else
            WBF.UI.Fyi.ShowQueued()
        end
    end)
    WBF.UI.Paint(popup, WBF.UI.Colors.window, WBF.UI.Colors.windowBorder, 1)

    -- The popup should stay out of the player's UI, not permanently live beside the minimap.
    -- Use a dedicated header drag surface so buttons/cards remain fully interactive.
    local drag = CreateFrame("Frame", nil, popup)
    drag:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -30, 0)
    drag:SetHeight(52)
    drag:SetFrameLevel(popup:GetFrameLevel() + 1)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        CloseRowMenu()
        popup:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        popup:StopMovingOrSizing()
        local point, _, relativePoint, x, y = popup:GetPoint(1)
        if WarbandFYI_DB and WarbandFYI_DB.config then
            WarbandFYI_DB.config.fyiPopup = {
                point = point,
                relPoint = relativePoint,
                x = x,
                y = y,
            }
        end
    end)
    popup.DragHeader = drag

    local close = WBF.UI.CloseButton(popup)
    close:SetFrameLevel(drag:GetFrameLevel() + 1)
    close:SetScript("OnClick", function()
        CloseRowMenu()
        popup:Hide()
    end)

    -- Event icons in the FYI header use ordinary square item/currency icons.
    -- Do not use the raw Calendar button texture here: that Blizzard asset is
    -- a sprite sheet and renders as several squeezed images when used directly.
    popupIcons = {}
    for index = 1, 3 do
        local icon = popup:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:Hide()
        popupIcons[index] = icon
    end

    popupTitle = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popupTitle:SetPoint("TOPLEFT", 12, -10)
    popupTitle:SetPoint("TOPRIGHT", -28, -10)
    popupTitle:SetJustifyH("LEFT")
    popupTitle:SetWordWrap(false)
    Color(popupTitle, WBF.UI.Colors.gold)

    popupCount = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popupCount:SetPoint("TOPLEFT", 12, -28)
    popupCount:SetJustifyH("LEFT")
    Color(popupCount, WBF.UI.Colors.muted)

    popupScroll = CreateFrame("ScrollFrame", nil, popup)
    popupScroll:SetPoint("TOPLEFT", 8, -54)
    popupScroll:SetPoint("BOTTOMRIGHT", -14, 32)
    popupChild = CreateFrame("Frame", nil, popupScroll)
    popupChild:SetSize(294, 40)
    popupScroll:SetScrollChild(popupChild)
    BindPopupWheel(popupScroll)
    BindPopupWheel(popupChild)

    -- A visible scrollbar makes long FYI lists discoverable. The popup grows
    -- with its content first, then this bar appears once the screen-height cap
    -- is reached.
    popupBar = WBF.UI.ScrollBar(popupScroll, popup)
    popupBar:SetPoint("TOPLEFT", popupScroll, "TOPRIGHT", 2, -2)
    popupBar:SetPoint("BOTTOMLEFT", popupScroll, "BOTTOMRIGHT", 2, 2)

    local function hideContext()
        local ids = popup.ids or {}
        if popup.contextType == "ZONE" and WBF.NotebookFyi and WBF.NotebookFyi.HideVisit then
            WBF.NotebookFyi.HideVisit(ids)
        elseif popup.contextType == "WOW_EVENT" and WBF.NotebookFyi and WBF.NotebookFyi.HideOccurrence then
            WBF.NotebookFyi.HideOccurrence(ids)
        end
        CloseRowMenu()
        popup:Hide()
    end
    popupPage = MakeButton(popup, "Open Page", 72)
    popupPage:SetPoint("BOTTOMLEFT", 10, 48)
    popupPage:Hide()
    popupPage:SetScript("OnClick", function(self)
        if self.pageId and WBF.UI.Notebook and WBF.UI.Notebook.ShowPage then
            WBF.UI.Notebook.ShowPage(self.pageId, self.focus)
            popup:Hide()
        end
    end)
    popupSheet = MakeButton(popup, "Open Sheet", 76)
    popupSheet:SetPoint("LEFT", popupPage, "RIGHT", 6, 0)
    popupSheet:Hide()
    popupSheet:SetScript("OnClick", function(self)
        if not WBF.UI.Sheet then
            return
        end
        if self.sectionId and WBF.UI.Sheet.OpenSection then
            WBF.UI.Sheet.OpenSection(self.sectionId)
        elseif self.pageId and WBF.UI.Sheet.OpenPage then
            WBF.UI.Sheet.OpenPage(self.pageId)
        end
    end)
    popupHide = MakeButton(popup, "Hide this visit", 118)
    popupHide:SetPoint("BOTTOMLEFT", 10, 22)
    popupHide:SetScript("OnClick", hideContext)
    popupHideNote = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popupHideNote:SetPoint("BOTTOMLEFT", 12, 8)
    popupHideNote:SetPoint("BOTTOMRIGHT", -12, 8)
    popupHideNote:SetJustifyH("LEFT")
    popupHideNote:SetWordWrap(false)
    popupHideNote:SetText("Hidden until you leave this zone and return.")
    Color(popupHideNote, WBF.UI.Colors.muted)
    popupHunts = MakeButton(popup, "Collection Hunts", 112)
    popupHunts:SetPoint("BOTTOMRIGHT", -12, 22)
    popupHunts:Hide()
    popupHunts:SetScript("OnClick", function()
        if WBF.NotebookFyi and WBF.NotebookFyi.ShowHunts then
            WBF.NotebookFyi.ShowHunts()
        end
    end)
    popupHunts:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText("Collection Hunts", 1, 0.82, 0.45)
        WBF.UI.AddTip(GameTooltip, "Add the characters that can make an attempt at each hunt right now.", WBF.UI.Colors.tipText, true)
        GameTooltip:Show()
    end)
    popupHunts:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    popupCards = {}

    -- Click-away surface for the small per-FYI options menu.  Keep it above
    -- the reminder itself but below the menu, so clicking anywhere outside
    -- the menu dismisses it without leaving a modal-looking orphan behind.
    rowMenuCatcher = CreateFrame("Button", nil, popup)
    rowMenuCatcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    rowMenuCatcher:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    rowMenuCatcher:SetFrameLevel(popup:GetFrameLevel() + 15)
    rowMenuCatcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rowMenuCatcher:SetScript("OnClick", CloseRowMenu)
    rowMenuCatcher:Hide()

    rowMenu = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    rowMenu:SetSize(196, 28)
    rowMenu:SetFrameLevel(popup:GetFrameLevel() + 20)
    rowMenu:Hide()
    WBF.UI.Paint(rowMenu, WBF.UI.Colors.card, WBF.UI.Colors.gold)
    local stop = MakeButton(rowMenu, "Stop showing this FYI here", 184)
    stop:SetPoint("CENTER")
    rowMenu.Stop = stop
end

local function Card(index)
    local card = popupCards[index]
    if card then
        return card
    end
    card = CreateFrame("Frame", nil, popupChild, "BackdropTemplate")
    WBF.UI.Paint(card, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    card.Context = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.Context:SetPoint("TOPLEFT", 8, -6)
    card.Context:SetPoint("TOPRIGHT", -28, -6)
    card.Context:SetJustifyH("LEFT")
    card.Context:SetWordWrap(false)
    Color(card.Context, WBF.UI.Colors.muted)
    card.Title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.Title:SetPoint("TOPLEFT", 8, -20)
    card.Title:SetPoint("TOPRIGHT", -28, -20)
    card.Title:SetJustifyH("LEFT")
    card.Title:SetWordWrap(false)
    Color(card.Title, WBF.UI.Colors.cream)
    card.Ends = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.Ends:SetWidth(92)
    card.Ends:SetJustifyH("RIGHT")
    card.Ends:SetWordWrap(false)
    card.Ends:Hide()
    Color(card.Ends, WBF.UI.Colors.muted)
    card.lines = {}
    card.EnsureLine = function(self, lineIndex)
        local line = self.lines[lineIndex]
        if line then
            return line
        end
        line = CreateFrame("Button", nil, self)
        line:SetHeight(18)
        line:RegisterForClicks("LeftButtonUp")
        BindPopupWheel(line)
        local hover = line:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 0.08)
        local icon = line:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", 0, -1)
        icon:Hide()
        line.Icon = icon
        -- Item lines carry "You · Warband bank · Total" counts that outgrow
        -- the card, so they wrap instead of clipping the total.
        local text = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        text:SetPoint("TOPLEFT", 0, -3)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("TOP")
        text:SetWordWrap(true)
        Color(text, WBF.UI.Colors.cream)
        line.Text = text
        -- Keep FYI rows lightweight. Item tooltips can become extremely large when
        -- equipment/tooltip addons decorate GameTooltip, so the popup only uses its
        -- subtle hover highlight. Clicking a row still jumps to its Notebook source.
        line:SetScript("OnEnter", nil)
        line:SetScript("OnLeave", nil)
        line:SetScript("OnClick", function(owner)
            if owner.pageId and owner.blockId and WBF.UI.Notebook and WBF.UI.Notebook.ShowPage then
                WBF.UI.Notebook.ShowPage(owner.pageId, {
                    sectionId = owner.sectionId,
                    blockId = owner.blockId,
                    itemId = owner.itemId,
                })
                popup:Hide()
            end
        end)
        line:Hide()
        self.lines[lineIndex] = line
        return line
    end
    card.Way = MakeButton(card, "Waypoint", 72)
    card.Page = MakeButton(card, "Open Page", 72)
    card.Sheet = MakeButton(card, "Open Sheet", 76)
    card.Hunts = MakeButton(card, "Open Hunts", 76)
    card.Hunts:SetScript("OnClick", function()
        local frame = WBF.UI.frame
        if frame and not frame:IsShown() then
            frame:Show()
        end
        if WBF.UI.CollectionHunts and WBF.UI.CollectionHunts.Open then
            WBF.UI.CollectionHunts.Open()
        end
    end)
    card.More = CreateFrame("Button", nil, card)
    card.More:SetSize(24, 20)
    BindPopupWheel(card)
    BindPopupWheel(card.Way)
    BindPopupWheel(card.Page)
    BindPopupWheel(card.Sheet)
    BindPopupWheel(card.Hunts)
    BindPopupWheel(card.More)
    local moreLabel = card.More:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moreLabel:SetPoint("CENTER")
    moreLabel:SetText("...")
    Color(moreLabel, WBF.UI.Colors.muted)
    card.More:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("FYI options", 1, 0.82, 0.45)
        WBF.UI.AddTip(GameTooltip, "Manage or stop showing this FYI.", WBF.UI.Colors.tipText, true)
        GameTooltip:Show()
    end)
    card.More:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    card.Way:SetScript("OnClick", function(self)
        local block = self.block
        if block and WBF.NotebookSheet and WBF.NotebookSheet.Use then
            WBF.NotebookSheet.Use(block)
        elseif block and WBF.NotebookSmart and WBF.NotebookSmart.Track then
            WBF.NotebookSmart.Track(block)
        end
    end)
    card.Page:SetScript("OnClick", function(self)
        if self.pageId and WBF.UI.Notebook and WBF.UI.Notebook.ShowPage then
            WBF.UI.Notebook.ShowPage(self.pageId, self.focus)
            popup:Hide()
        end
    end)
    card.Sheet:SetScript("OnClick", function(self)
        if not WBF.UI.Sheet then
            return
        end
        if self.sectionId and WBF.UI.Sheet.OpenSection then
            WBF.UI.Sheet.OpenSection(self.sectionId)
        elseif self.pageId and WBF.UI.Sheet.OpenPage then
            WBF.UI.Sheet.OpenPage(self.pageId)
        end
    end)
    card.More:SetScript("OnClick", function(self)
        if not rowMenu then
            return
        end
        rowMenu.Stop:SetScript("OnClick", function()
            CloseRowMenu()
            if self.triggerId and WBF.NotebookFyi then
                WBF.NotebookFyi.Remove(self.triggerId)
            end
            WBF.UI.Fyi.Refresh()
        end)
        rowMenu:ClearAllPoints()
        rowMenu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -2)
        if rowMenuCatcher then
            rowMenuCatcher:Show()
        end
        rowMenu:Show()
    end)
    popupCards[index] = card
    return card
end

local function RenderPopup(group, preserveScroll)
    local previousScroll = 0
    if preserveScroll and popupScroll then
        previousScroll = popupScroll:GetVerticalScroll() or 0
    end
    EnsurePopup()
    CloseRowMenu()
    popup.group = group
    local contextType = (group.contextType == "WOW_EVENT" or group.contextType == "LOGIN") and group.contextType or "ZONE"
    local contextName = group.contextName or group.zoneName or (contextType == "WOW_EVENT" and "WoW event" or "Zone")
    local headerIcons = {}
    local seenIcons = {}
    local function addHeaderIcon(icon)
        if not icon or seenIcons[tostring(icon)] or #headerIcons >= #popupIcons then
            return
        end
        seenIcons[tostring(icon)] = true
        headerIcons[#headerIcons + 1] = icon
    end
    if contextType == "WOW_EVENT" then
        for index = 1, #(group.entries or {}) do
            addHeaderIcon(group.entries[index] and group.entries[index].eventIcon)
        end
        addHeaderIcon(group.contextIcon)
        if #headerIcons == 0 then
            -- Safe square icon fallback. The old UI-Calendar-Button texture is
            -- a multi-state sprite sheet, which is what produced the squashed
            -- pair of calendar-looking shapes in the header.
            addHeaderIcon("Interface\\Icons\\INV_Misc_Note_01")
        end
    elseif group.contextIcon then
        addHeaderIcon(group.contextIcon)
    end

    popupTitle:ClearAllPoints()
    popupCount:ClearAllPoints()
    for index = 1, #popupIcons do
        local icon = popupIcons[index]
        local file = headerIcons[index]
        icon:ClearAllPoints()
        if file then
            icon:SetTexture(file)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:SetPoint("TOPLEFT", 10 + ((index - 1) * 30), -10)
            icon:Show()
        else
            icon:Hide()
        end
    end
    if #headerIcons > 0 then
        local left = 14 + (#headerIcons * 30)
        popupTitle:SetPoint("TOPLEFT", left, -9)
        popupCount:SetPoint("TOPLEFT", left, -28)
    else
        popupTitle:SetPoint("TOPLEFT", 12, -10)
        popupCount:SetPoint("TOPLEFT", 12, -28)
    end
    popupTitle:SetPoint("TOPRIGHT", -28, -10)
    popupTitle:SetText(Shown(contextName))
    for key, build in pairs(type(group.attach) == "table" and group.attach or {}) do
        if type(build) == "function" then
            if not attached[key] then
                attachedOrder[#attachedOrder + 1] = key
            end
            attached[key] = build
        end
    end
    local entries = {}
    local seenAttach = {}
    for index = 1, #(group.entries or {}) do
        local entry = group.entries[index]
        entries[#entries + 1] = entry
        if entry and entry.attachKey then seenAttach[entry.attachKey] = true end
    end
    for _, key in ipairs(attachedOrder) do
        local build = attached[key]
        local entry = not seenAttach[key] and build and build() or nil
        if entry then
            entry.attachKey = key
            entries[#entries + 1] = entry
            seenAttach[key] = true
        end
    end
    popup.attachedKeys = seenAttach
    local count = #entries
    local noun
    if contextType == "WOW_EVENT" then
        noun = count == 1 and "FYI now" or "FYIs now"
        popupHide.Label:SetText("Hide this occurrence")
        popupHideNote:SetText("Hidden until the next occurrence.")
    elseif contextType == "LOGIN" then
        noun = count == 1 and "FYI for this character" or "FYIs for this character"
        popupHide.Label:SetText("Dismiss")
        popupHideNote:SetText("Shown again next time you log in.")
    else
        noun = count == 1 and "FYI here" or "FYIs here"
        popupHide.Label:SetText("Hide this visit")
        popupHideNote:SetText("Hidden until you leave this zone and return.")
    end
    popupCount:SetText(count .. " " .. noun)
    local ids = {}
    for index = 1, #popupCards do
        popupCards[index].endStamp = nil
        if popupCards[index].Ends then
            popupCards[index].Ends:Hide()
        end
        popupCards[index]:Hide()
    end
    local layout = WBF.NotebookFyi and WBF.NotebookFyi.PopupLayout(entries) or { shared = nil, pages = {} }
    local y = 4
    local width = 294
    for index = 1, #entries do
        local entry = entries[index]
        ids[#ids + 1] = entry.triggerId
        local actions = WBF.NotebookFyi and WBF.NotebookFyi.CardActions(entry, layout, index) or {}
        local card = Card(index)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", popupChild, "TOPLEFT", 0, -y)
        card:SetWidth(width)
        card.Context:SetText(Shown(entry.context or ""))
        card.Context:SetShown(entry.context and entry.context ~= "")
        card.Title:SetText(Shown(entry.title or "Note"))
        card.endStamp = contextType == "WOW_EVENT" and entry.endStamp or nil
        local countdownText, _, countdownUrgent = CountdownText(card.endStamp)
        card.Ends:ClearAllPoints()
        card.Ends:SetText(countdownText or "")
        card.Ends:SetShown(countdownText and countdownText ~= "" or false)
        if countdownText then
            Color(card.Ends, countdownUrgent and WBF.UI.Colors.gold or WBF.UI.Colors.muted)
        end
        local titleRight = countdownText and -132 or -28
        local lineY = entry.context and entry.context ~= "" and -34 or -22
        if not entry.context or entry.context == "" then
            card.Title:ClearAllPoints()
            card.Title:SetPoint("TOPLEFT", 8, -6)
            card.Title:SetPoint("TOPRIGHT", titleRight, -6)
            if countdownText then
                card.Ends:SetPoint("TOPRIGHT", -34, -6)
            end
            lineY = -22
        else
            card.Title:ClearAllPoints()
            card.Title:SetPoint("TOPLEFT", 8, -20)
            card.Title:SetPoint("TOPRIGHT", titleRight, -20)
            if countdownText then
                card.Ends:SetPoint("TOPRIGHT", -34, -20)
            end
        end
        local lines = entry.lines or {}
        for lineIndex = 1, #lines do
            local line = card:EnsureLine(lineIndex)
            local info = lines[lineIndex]
            local lineText = nil
            if info then
                if info.text and info.text ~= "" and info.detail and info.detail ~= "" and info.text ~= info.detail then
                    lineText = info.text .. "  " .. info.detail
                else
                    lineText = info.detail or info.text
                end
            end
            if lineText and lineText ~= "" then
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", 8, lineY)
                line:SetPoint("TOPRIGHT", -8, lineY)
                line.Text:ClearAllPoints()
                local textWidth = width - 16
                if info and info.icon then
                    line.Icon:SetTexture(info.icon)
                    line.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    line.Icon:Show()
                    line.Text:SetPoint("TOPLEFT", line.Icon, "TOPRIGHT", 5, -2)
                    textWidth = textWidth - 21
                elseif info and info.indent then
                    -- Count lines sit indented under the item's name.
                    line.Icon:Hide()
                    line.Text:SetPoint("TOPLEFT", 33, -1)
                    textWidth = textWidth - 33
                else
                    line.Icon:Hide()
                    line.Text:SetPoint("TOPLEFT", 0, -3)
                end
                line.Text:SetWidth(textWidth)
                line.Text:SetText(Shown(lineText))
                local minHeight = info and info.indent and 14 or 18
                local padding = info and info.indent and 2 or 6
                local lineHeight = math.max(minHeight, math.ceil((line.Text:GetStringHeight() or 0) + padding))
                line:SetHeight(lineHeight)
                Color(line.Text, info and info.completed and WBF.UI.Colors.muted or WBF.UI.Colors.cream)
                line.pageId = entry.pageId
                line.sectionId = entry.sectionId
                line.blockId = info and info.blockId or nil
                line.itemId = info and info.itemId or nil
                line.itemID = info and info.itemID or nil
                line:EnableMouse(line.blockId and true or false)
                line:Show()
                lineY = lineY - lineHeight
            else
                line.pageId = nil
                line.sectionId = nil
                line.blockId = nil
                line.itemId = nil
                line.itemID = nil
                line.Icon:Hide()
                line:Hide()
            end
        end
        for lineIndex = #lines + 1, #card.lines do
            local line = card.lines[lineIndex]
            line.pageId = nil
            line.sectionId = nil
            line.blockId = nil
            line.itemId = nil
            line.itemID = nil
            line.Icon:Hide()
            line:Hide()
        end
        local buttonY = lineY - 4
        local bucket = layout.pages and layout.pages[entry.pageId or ""] or nil
        card.Way.block = entry.waypoint
        card.Way:SetShown(actions.waypoint and true or false)
        card.Page.pageId = entry.pageId
        local firstLine = lines[1]
        card.Page.focus = {
            sectionId = entry.sectionId,
            blockId = firstLine and firstLine.blockId or nil,
            itemId = firstLine and firstLine.itemId or nil,
        }
        card.Sheet.pageId = entry.pageId
        card.Sheet.sectionId = bucket and bucket.sectionId or entry.sectionId
        card.Page:SetShown(actions.page and true or false)
        card.Sheet:SetShown(actions.sheet and true or false)
        card.More.triggerId = entry.triggerId
        card.More:SetShown(entry.triggerId ~= nil)
        card.Hunts:ClearAllPoints()
        card.Hunts:SetShown(entry.openHunts and true or false)
        card.Way:ClearAllPoints()
        card.Page:ClearAllPoints()
        card.Sheet:ClearAllPoints()
        card.More:ClearAllPoints()
        local x = 8
        if actions.waypoint then
            card.Way:SetPoint("TOPLEFT", x, buttonY)
            x = x + 76
        end
        if actions.page then
            card.Page:SetPoint("TOPLEFT", x, buttonY)
            card.Sheet:SetPoint("TOPLEFT", x + 76, buttonY)
            x = x + 152
        end
        if entry.openHunts then
            card.Hunts:SetPoint("TOPLEFT", x, buttonY)
        end
        card.More:SetPoint("TOPRIGHT", -6, -4)
        local height = (actions.waypoint or actions.page or entry.openHunts) and (-buttonY + 26) or (-lineY + 12)
        card:SetHeight(height)
        card:Show()
        y = y + height + 6
    end
    popup.ids = ids
    popup.contextType = contextType
    popup.contextName = contextName
    popup.zoneMapID = contextType == "ZONE" and group.zoneMapID or nil
    local huntsOffered = WBF.NotebookFyi and WBF.NotebookFyi.HuntsOffered and WBF.NotebookFyi.HuntsOffered()
    popupHunts:SetShown(huntsOffered and not seenAttach.hunts or false)
    local shared = layout.shared
    if shared and shared.pageId then
        popupPage.pageId = shared.pageId
        local firstEntry = entries[1]
        local firstLine = firstEntry and firstEntry.lines and firstEntry.lines[1] or nil
        popupPage.focus = {
            sectionId = (firstEntry and firstEntry.sectionId) or shared.sectionId,
            blockId = firstLine and firstLine.blockId or nil,
            itemId = firstLine and firstLine.itemId or nil,
        }
        popupSheet.pageId = shared.pageId
        popupSheet.sectionId = shared.sectionId
        popupPage:Show()
        popupSheet:Show()
    else
        popupPage.focus = nil
        popupPage:Hide()
        popupSheet:Hide()
    end
    local footer = shared and shared.pageId and 72 or 48
    popupScroll:ClearAllPoints()
    popupScroll:SetPoint("TOPLEFT", 8, -54)
    popupScroll:SetPoint("BOTTOMRIGHT", -14, footer)
    popupChild:SetHeight(math.max(y, 1))
    popupScroll:SetVerticalScroll(previousScroll)

    -- Grow naturally for ordinary FYIs, but stop before the reminder consumes
    -- the whole screen. Longer content remains available through the visible
    -- scrollbar and mouse wheel.
    local screenHeight = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
    local maxBody = math.min(520, math.max(220, screenHeight - 190))
    local body = math.min(math.max(y, 48), maxBody)
    popup:SetHeight(54 + body + footer)

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if popup and popup:IsShown() then
                local range = popupScroll:GetVerticalScrollRange() or 0
                if popupScroll:GetVerticalScroll() > range then
                    popupScroll:SetVerticalScroll(range)
                end
                UpdatePopupScrollBar()
            end
        end)
    else
        UpdatePopupScrollBar()
    end

    if contextType == "WOW_EVENT" then
        ScheduleCountdownRefresh()
    else
        popupCountdownGeneration = popupCountdownGeneration + 1
    end
end

function WBF.UI.Fyi.ResetPopupPosition()
    if WarbandFYI_DB and WarbandFYI_DB.config then
        WarbandFYI_DB.config.fyiPopup = nil
    end
    if popup then
        popup:StopMovingOrSizing()
        popup:ClearAllPoints()
        popup:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -160)
    end
end

-- There is one popup. A group that arrives while a different FYI is on screen,
-- or during combat, waits here instead of replacing it: callers mark their
-- reminders as shown, so a replaced group would not come back this session.
local queued = {}

local function SameContext(contextType, zoneMapID, group)
    if contextType ~= group.contextType then
        return false
    end
    return contextType ~= "ZONE" or zoneMapID == group.zoneMapID
end

local function Enqueue(group)
    for index = 1, #queued do
        if SameContext(queued[index].contextType, queued[index].zoneMapID, group) then
            queued[index] = group
            return
        end
    end
    queued[#queued + 1] = group
end

-- Zone and event groups can go stale while they wait.
local function Current(group)
    if group.contextType == "ZONE" then
        local zone = WBF.NotebookFyi and WBF.NotebookFyi.VisitZone and WBF.NotebookFyi.VisitZone()
        return zone == group.zoneMapID and group or nil
    end
    if group.contextType == "WOW_EVENT" then
        return WBF.NotebookFyi and WBF.NotebookFyi.ActiveEventGroup and WBF.NotebookFyi.ActiveEventGroup(false) or nil
    end
    return group
end

function WBF.UI.Fyi.Show(group)
    if type(group) ~= "table" or type(group.entries) ~= "table" then
        return false
    end
    -- A group can be only attached cards, such as the Collection Hunts list.
    if #group.entries == 0 and not (type(group.attach) == "table" and next(group.attach)) then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        Enqueue(group)
        return false
    end
    if popup and popup:IsShown() and not SameContext(popup.contextType, popup.zoneMapID, group) then
        Enqueue(group)
        return true
    end
    RenderPopup(group, false)
    popup:Show()
    if group.contextType == "WOW_EVENT" then
        ScheduleCountdownRefresh()
    end
    return true
end

function WBF.UI.Fyi.IsShown()
    return popup ~= nil and popup:IsShown() and true or false
end

-- Adds a card to the popup on screen, whatever its context, and keeps it there
-- through redraws until the popup closes. build returns the entry, or nil when
-- there is nothing to show. True when the card is now on screen.
function WBF.UI.Fyi.Attach(key, build)
    if type(key) ~= "string" or type(build) ~= "function" or not WBF.UI.Fyi.IsShown() or not popup.group then
        return false
    end
    if not attached[key] then
        attachedOrder[#attachedOrder + 1] = key
    end
    attached[key] = build
    RenderPopup(popup.group, true)
    return popup.attachedKeys and popup.attachedKeys[key] == true or false
end

function WBF.UI.Fyi.ShowQueued()
    if (popup and popup:IsShown()) or (InCombatLockdown and InCombatLockdown()) then
        return false
    end
    while #queued > 0 do
        local group = Current(table.remove(queued, 1))
        if group and WBF.UI.Fyi.Show(group) then
            return true
        end
    end
    return false
end

function WBF.UI.Fyi.SyncActiveEvents()
    if not popup or not popup:IsShown() or popup.contextType ~= "WOW_EVENT" then
        return false
    end
    if not WBF.NotebookFyi or not WBF.NotebookFyi.ActiveEventGroup then
        return false
    end
    local group = WBF.NotebookFyi.ActiveEventGroup(false)
    if not group then
        CloseRowMenu()
        popup:Hide()
        return true
    end
    RenderPopup(group, true)
    return true
end

function WBF.UI.Fyi.ShowActiveEvents(includeHidden)
    if not WBF.NotebookFyi or not WBF.NotebookFyi.ActiveEventGroup then
        return false
    end
    local group = WBF.NotebookFyi.ActiveEventGroup(includeHidden and true or false)
    if not group then
        return false
    end
    return WBF.UI.Fyi.Show(group)
end

function WBF.UI.Fyi.Refresh()
    if not popup or not popup:IsShown() or not WBF.NotebookFyi then
        return
    end
    if popup.contextType == "WOW_EVENT" then
        WBF.UI.Fyi.SyncActiveEvents()
        return
    end
    local root = WBF.Notebook.Root()
    local stored = root and root.fyi and root.fyi.triggers or {}
    local ids = popup.ids or {}
    local entries = {}
    for index = 1, #ids do
        local described = WBF.NotebookFyi.Describe(stored[ids[index]])
        if described then
            entries[#entries + 1] = described
        end
    end
    if popup.contextType == "LOGIN" then
        -- Login cards may have been removed, while attached cards such as
        -- Collection Hunts still hold the popup open.
        RenderPopup({ contextType = "LOGIN", contextName = popup.contextName, entries = entries }, true)
        if popup.ids and #popup.ids == 0 and not next(popup.attachedKeys or {}) then
            CloseRowMenu()
            popup:Hide()
        end
        return
    end
    if #entries == 0 then
        CloseRowMenu()
        popup:Hide()
        return
    end
    local zoneName = entries[1].zoneName
    if popup.zoneMapID and WBF.NotebookFyi.ZoneName then
        zoneName = WBF.NotebookFyi.ZoneName(popup.zoneMapID, zoneName)
    end
    RenderPopup({
        contextType = "ZONE",
        contextName = zoneName,
        zoneMapID = popup.zoneMapID,
        zoneName = zoneName,
        count = #entries,
        entries = entries,
    }, true)
end

local function SetSetupMode(mode, useSuggestion)
    setupMode = (mode == "WOW_EVENT" or mode == "LOGIN") and mode or "ZONE"
    setupChoice = nil
    if useSuggestion and setupTarget and WBF.NotebookFyi then
        if setupMode == "WOW_EVENT" and WBF.NotebookFyi.SuggestEvent then
            setupChoice = WBF.NotebookFyi.SuggestEvent(setupTarget.kind, setupTarget.id)
        elseif setupMode == "ZONE" and WBF.NotebookFyi.Suggest then
            setupChoice = WBF.NotebookFyi.Suggest(setupTarget.kind, setupTarget.id)
        end
    end
    if setupSearch then
        setupSearch._lock = true
        setupSearch:SetText(setupChoice and setupChoice.name or "")
        setupSearch._lock = nil
    end
    WBF.UI.Fyi.PaintSetup()
end

local function EnsureSetup()
    if setup then
        return
    end
    setup = CreateFrame("Frame", "WarbandFYIFyiSetup", UIParent, "BackdropTemplate")
    setup:SetSize(380, 300)
    setup:SetPoint("CENTER")
    setup:SetFrameStrata("DIALOG")
    setup:SetToplevel(true)
    setup:Hide()
    WBF.UI.Paint(setup, WBF.UI.Colors.window, WBF.UI.Colors.windowBorder, 1)
    setup:EnableMouse(true)
    setup:SetScript("OnMouseDown", function()
    end)

    local close = WBF.UI.CloseButton(setup)
    close:SetScript("OnClick", function()
        setup:Hide()
    end)

    setupHeading = setup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    setupHeading:SetPoint("TOPLEFT", 14, -12)
    setupHeading:SetText("Show as FYI")
    Color(setupHeading, WBF.UI.Colors.gold)

    setupTitle = setup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    setupTitle:SetPoint("TOPLEFT", 14, -34)
    setupTitle:SetPoint("TOPRIGHT", -14, -34)
    setupTitle:SetJustifyH("LEFT")
    setupTitle:SetWordWrap(false)
    Color(setupTitle, WBF.UI.Colors.cream)

    local whenLabel = setup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    whenLabel:SetPoint("TOPLEFT", 14, -58)
    whenLabel:SetText("Show this FYI when")
    Color(whenLabel, WBF.UI.Colors.muted)

    setupEnabled = CreateFrame("CheckButton", nil, setup)
    setupEnabled:SetSize(18, 18)
    setupEnabled:SetPoint("TOPRIGHT", -74, -54)
    setupEnabled:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    setupEnabled:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    setupEnabled:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    setupEnabled:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local enabledLabel = setup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    enabledLabel:SetPoint("LEFT", setupEnabled, "RIGHT", 2, 0)
    enabledLabel:SetText("Enabled")
    Color(enabledLabel, WBF.UI.Colors.cream)

    setupEventButton = MakeButton(setup, "WoW event", 88)
    setupEventButton:SetPoint("TOPLEFT", 14, -74)
    setupEventButton:SetScript("OnClick", function()
        SetSetupMode("WOW_EVENT", true)
    end)

    setupZoneButton = MakeButton(setup, "Zone", 62)
    setupZoneButton:SetPoint("LEFT", setupEventButton, "RIGHT", 6, 0)
    setupZoneButton:SetScript("OnClick", function()
        SetSetupMode("ZONE", true)
    end)

    setupLoginButton = MakeButton(setup, "Login", 62)
    setupLoginButton:SetPoint("LEFT", setupZoneButton, "RIGHT", 6, 0)
    setupLoginButton:SetScript("OnClick", function()
        SetSetupMode("LOGIN", false)
    end)

    local assignedLabel = setup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    assignedLabel:SetPoint("BOTTOMLEFT", 14, 87)
    assignedLabel:SetText("Assigned to")
    Color(assignedLabel, WBF.UI.Colors.muted)
    setupCharacterButton = MakeButton(setup, "Warband", 200)
    setupCharacterButton:SetPoint("LEFT", assignedLabel, "RIGHT", 8, 0)
    setupCharacterButton:SetScript("OnClick", function()
        local choices = WBF.NotebookFyi.CharacterChoices()
        local current = 1
        for index, choice in ipairs(choices) do
            if choice.guid == setupCharacterGuid then current = index; break end
        end
        setupCharacterGuid = choices[(current % #choices) + 1].guid
        setupCharacterButton.Label:SetText(Shown(WBF.NotebookFyi.AssigneeName(setupCharacterGuid)))
    end)

    setupContextLabel = setup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    setupContextLabel:SetPoint("TOPLEFT", 14, -102)
    setupContextLabel:SetText("Event")
    Color(setupContextLabel, WBF.UI.Colors.muted)

    setupSearch = WBF.UI.EditBox(setup, 270, 20)
    setupSearch:SetPoint("TOPLEFT", 18, -118)
    if WBF.UI.KeepKeyboard then
        WBF.UI.KeepKeyboard(setupSearch)
    end
    setupPlaceholder = setup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    setupPlaceholder:SetPoint("LEFT", setupSearch, "LEFT", 4, 0)
    setupPlaceholder:SetText("Search for an event...")
    Color(setupPlaceholder, WBF.UI.Colors.muted)
    setupSearch:SetScript("OnTextChanged", function(self)
        if self._lock then
            return
        end
        if setupChoice and setupChoice.name ~= self:GetText() then
            setupChoice = nil
        end
        WBF.UI.Fyi.PaintSetup()
    end)

    setupRows = {}
    for index = 1, 6 do
        local row = CreateFrame("Button", nil, setup, "BackdropTemplate")
        row:SetSize(348, 22)
        row:SetPoint("TOPLEFT", 16, -144 - ((index - 1) * 24))
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 8, 0)
        label:SetPoint("RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.Label = label
        row:SetScript("OnClick", function(self)
            if not self.choice then
                return
            end
            setupChoice = {}
            for key, value in pairs(self.choice) do
                setupChoice[key] = value
            end
            setupSearch._lock = true
            setupSearch:SetText(setupChoice.name or "")
            setupSearch._lock = nil
            WBF.UI.Fyi.PaintSetup()
        end)
        row:Hide()
        setupRows[index] = row
    end

    setupHint = setup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    setupHint:SetPoint("BOTTOMLEFT", 14, 40)
    setupHint:SetPoint("BOTTOMRIGHT", -14, 40)
    setupHint:SetJustifyH("LEFT")
    setupHint:SetWordWrap(true)
    Color(setupHint, WBF.UI.Colors.muted)

    setupStatus = setup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    setupStatus:SetPoint("BOTTOMLEFT", 14, 14)
    setupStatus:SetWidth(180)
    setupStatus:SetJustifyH("LEFT")
    Color(setupStatus, WBF.UI.Colors.gold)

    setupRemove = MakeButton(setup, "Remove FYI", 82)
    setupRemove:SetPoint("BOTTOMLEFT", 14, 12)
    setupRemove:SetScript("OnClick", function()
        if setupTarget and WBF.NotebookFyi then
            WBF.NotebookFyi.RemoveTarget(setupTarget.kind, setupTarget.id)
        end
        setupExisting = nil
        setup:Hide()
        if WBF.Notebook and WBF.Notebook.RefreshOpen then
            WBF.Notebook.RefreshOpen()
        end
    end)
    setupRemove:Hide()

    local cancel = MakeButton(setup, "Cancel", 72)
    cancel:SetPoint("BOTTOMRIGHT", -96, 12)
    cancel:SetScript("OnClick", function()
        setup:Hide()
    end)
    setupSave = MakeButton(setup, "Save FYI", 76)
    setupSave:SetPoint("BOTTOMRIGHT", -14, 12)
    setupSave:SetScript("OnClick", function()
        if not setupTarget or (setupMode ~= "LOGIN" and not setupChoice) or not WBF.NotebookFyi then
            setupStatus:SetText(setupMode == "WOW_EVENT" and "Choose an event." or "Choose a zone.")
            return
        end
        local saved
        if setupMode == "LOGIN" then
            saved = WBF.NotebookFyi.SaveLogin(setupTarget)
        elseif setupMode == "WOW_EVENT" then
            saved = WBF.NotebookFyi.SaveEvent(setupTarget, setupChoice.key, setupChoice.name)
        else
            saved = WBF.NotebookFyi.SaveZone(setupTarget, setupChoice.mapID, setupChoice.name)
        end
        if not saved then
            setupStatus:SetText(setupMode == "WOW_EVENT" and "Choose an event." or "Choose a zone.")
            return
        end
        saved.characterGuid = setupCharacterGuid
        saved.enabled = setupEnabled and setupEnabled:GetChecked() and true or false
        setup:Hide()
        if WBF.Notebook and WBF.Notebook.RefreshOpen then
            WBF.Notebook.RefreshOpen()
        end
    end)
end

function WBF.UI.Fyi.PaintSetup()
    if not setup or not setup:IsShown() then
        return
    end
    setupStatus:ClearAllPoints()
    if setupRemove and setupRemove:IsShown() then
        setupStatus:SetPoint("BOTTOMLEFT", 104, 14)
        setupStatus:SetWidth(96)
    else
        setupStatus:SetPoint("BOTTOMLEFT", 14, 14)
        setupStatus:SetWidth(180)
    end
    local searchCursor = nil
    if setupSearch:HasFocus() then
        searchCursor = setupSearch:GetCursorPosition()
    end
    local query = setupSearch:GetText() or ""
    local chosen = setupChoice and setupChoice.name or nil
    local choices = {}
    if setupMode == "LOGIN" then
        setupContextLabel:SetText("On character login")
        setupPlaceholder:SetText("No event or zone required")
    elseif setupMode == "WOW_EVENT" then
        if WBF.NotebookFyi and WBF.NotebookFyi.EventMatches then
            choices = WBF.NotebookFyi.EventMatches(query, chosen)
        end
        setupContextLabel:SetText("Event")
        setupPlaceholder:SetText("Search for an event...")
    else
        if WBF.NotebookFyi and WBF.NotebookFyi.ZoneMatches then
            choices = WBF.NotebookFyi.ZoneMatches(query, chosen)
        end
        setupContextLabel:SetText("Zone")
        setupPlaceholder:SetText("Search for a zone...")
    end
    setupEventButton._selected = setupMode == "WOW_EVENT"
    setupZoneButton._selected = setupMode == "ZONE"
    setupLoginButton._selected = setupMode == "LOGIN"
    PaintButton(setupLoginButton)
    setupSearch:SetShown(setupMode ~= "LOGIN")
    PaintButton(setupEventButton)
    PaintButton(setupZoneButton)
    if setupPlaceholder then
        setupPlaceholder:SetShown(query == "" and setupMode ~= "LOGIN")
    end
    for index = 1, #setupRows do
        local row = setupRows[index]
        local choice = choices[index]
        row.choice = choice
        if choice then
            row.Label:SetText(Shown(choice.name))
            WBF.UI.Paint(row, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
            Color(row.Label, WBF.UI.Colors.cream)
            row:Show()
        else
            row:Hide()
        end
    end
    setup:SetHeight(math.max(340, 285 + (#choices * 24)))
    local hint = WBF.NotebookFyi and WBF.NotebookFyi.SetupHint and WBF.NotebookFyi.SetupHint(setupMode) or ""
    if setupChoice or setupMode == "LOGIN" then
        setupHint:SetText(setupMode == "LOGIN" and "Shows after login on the assigned character. Warband assignment shows on every character." or hint)
        setupStatus:SetText("")
    else
        local choiceText = setupMode == "WOW_EVENT" and "an event" or "a zone"
        setupHint:SetText(hint .. " Choose " .. choiceText .. ". WarbandFYI will not guess.")
        setupStatus:SetText("Choose " .. choiceText .. ".")
    end
    if searchCursor then
        setupSearch:SetFocus()
        setupSearch:SetCursorPosition(searchCursor)
    end
end

function WBF.UI.Fyi.OpenSetup(kind, id, preferredMode)
    if not WBF.NotebookFyi or not WBF.Notebook or not id then
        return
    end
    EnsureSetup()
    local existing = WBF.NotebookFyi.ForTarget(kind, id)
    local described
    if existing then
        described = WBF.NotebookFyi.Describe(existing)
    else
        described = WBF.NotebookFyi.Describe({
            id = "draft",
            targetKind = kind,
            targetId = id,
            triggerType = "ZONE",
            zoneMapID = 1,
            zoneName = "",
            enabled = true,
        })
    end
    if not described then
        return
    end

    setupTarget = { kind = kind, id = id }
    setupCharacterGuid = existing and existing.characterGuid or nil
    setupCharacterButton.Label:SetText(Shown(WBF.NotebookFyi.AssigneeName(setupCharacterGuid)))
    setupExisting = existing
    setupTitle:SetText(Shown(described.title or "Note"))
    if setupHeading then
        setupHeading:SetText(existing and "Edit FYI" or "Show as FYI")
    end
    if setupEnabled then
        setupEnabled:SetChecked(not existing or existing.enabled ~= false)
    end
    if setupRemove then
        setupRemove:SetShown(existing and true or false)
    end

    local suggestion
    if existing and existing.triggerType == "LOGIN" then
        setupMode = "LOGIN"
        suggestion = nil
    elseif existing and existing.triggerType == "WOW_EVENT" then
        setupMode = "WOW_EVENT"
        suggestion = {
            key = existing.eventKey,
            name = existing.eventName or (described and described.eventName),
        }
    elseif existing then
        setupMode = "ZONE"
        suggestion = {
            mapID = existing.zoneMapID,
            name = WBF.NotebookFyi.ZoneName(existing.zoneMapID, existing.zoneName),
        }
    else
        if preferredMode == "WOW_EVENT" then
            setupMode = "WOW_EVENT"
            suggestion = WBF.NotebookFyi.SuggestEvent and WBF.NotebookFyi.SuggestEvent(kind, id) or nil
        elseif preferredMode == "ZONE" then
            setupMode = "ZONE"
            suggestion = WBF.NotebookFyi.Suggest and WBF.NotebookFyi.Suggest(kind, id) or nil
        else
            suggestion = WBF.NotebookFyi.SuggestEvent and WBF.NotebookFyi.SuggestEvent(kind, id) or nil
            if suggestion then
                setupMode = "WOW_EVENT"
            else
                setupMode = "ZONE"
                suggestion = WBF.NotebookFyi.Suggest and WBF.NotebookFyi.Suggest(kind, id) or nil
            end
        end
    end

    setupChoice = suggestion
    setupSearch._lock = true
    setupSearch:SetText(suggestion and suggestion.name or "")
    setupSearch._lock = nil
    setup:Show()
    WBF.UI.Fyi.PaintSetup()
end

local function EnsureManage()
    if manage then
        return
    end
    manage = CreateFrame("Frame", "WarbandFYIFyiManage", UIParent, "BackdropTemplate")
    manage:SetSize(460, 280)
    manage:SetPoint("CENTER")
    manage:SetFrameStrata("DIALOG")
    manage:SetToplevel(true)
    manage:Hide()
    WBF.UI.Paint(manage, WBF.UI.Colors.window, WBF.UI.Colors.windowBorder, 1)
    local close = WBF.UI.CloseButton(manage)
    close:SetScript("OnClick", function()
        manage:Hide()
    end)
    local heading = manage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 14, -12)
    heading:SetText("FYI reminders")
    Color(heading, WBF.UI.Colors.gold)
    local columns = manage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    columns:SetPoint("TOPLEFT", 14, -36)
    columns:SetText("Content")
    Color(columns, WBF.UI.Colors.muted)
    local zoneHead = manage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    zoneHead:SetPoint("TOPLEFT", 190, -36)
    zoneHead:SetText("When")
    Color(zoneHead, WBF.UI.Colors.muted)
    manageEmpty = manage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manageEmpty:SetPoint("TOPLEFT", 14, -64)
    manageEmpty:SetWidth(420)
    manageEmpty:SetJustifyH("LEFT")
    manageEmpty:SetText("No FYI reminders yet. Use FYI or Show as FYI on Notebook content.")
    Color(manageEmpty, WBF.UI.Colors.muted)
    manageRows = {}
end

local function ManageRow(index)
    local row = manageRows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, manage)
    row:SetSize(432, 26)
    row.Title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Title:SetPoint("LEFT", 0, 0)
    row.Title:SetWidth(170)
    row.Title:SetJustifyH("LEFT")
    row.Title:SetWordWrap(false)
    Color(row.Title, WBF.UI.Colors.cream)
    row.Zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Zone:SetPoint("LEFT", 176, 0)
    row.Zone:SetWidth(110)
    row.Zone:SetJustifyH("LEFT")
    row.Zone:SetWordWrap(false)
    Color(row.Zone, WBF.UI.Colors.cream)
    row.Check = CreateFrame("CheckButton", nil, row)
    row.Check:SetSize(18, 18)
    row.Check:SetPoint("LEFT", 290, 0)
    row.Check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    row.Check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    row.Check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    row.Check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.Edit = MakeButton(row, "Edit", 40)
    row.Edit:SetPoint("LEFT", 316, 0)
    row.Remove = MakeButton(row, "Remove", 58)
    row.Remove:SetPoint("LEFT", 360, 0)
    manageRows[index] = row
    return row
end

function WBF.UI.Fyi.PaintManage()
    if not manage or not manage:IsShown() or not WBF.NotebookFyi then
        return
    end
    local list = WBF.NotebookFyi.List()
    manageEmpty:ClearAllPoints()
    if #list == 0 then
        manageEmpty:SetPoint("TOPLEFT", 14, -64)
        manageEmpty:SetText("No FYI reminders yet. Use FYI or Show as FYI on Notebook content.")
        manageEmpty:Show()
    elseif #list > 8 then
        manageEmpty:SetPoint("BOTTOMLEFT", 14, 10)
        manageEmpty:SetText("Showing 8 of " .. #list .. ".")
        manageEmpty:Show()
    else
        manageEmpty:Hide()
    end
    for index = 1, #manageRows do
        manageRows[index]:Hide()
    end
    local shown = math.min(#list, 8)
    for index = 1, shown do
        local info = list[index]
        local row = ManageRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 14, -56 - ((index - 1) * 28))
        row.Title:SetText(Shown(info.title or "Note"))
        row.Zone:SetText(Shown((info.triggerType == "LOGIN" and "Login" or (info.triggerType == "WOW_EVENT" and (info.eventName or "Event") or (info.zoneName or ""))) .. (info.characterGuid and (" / " .. (info.characterName or "")) or "")))
        row.Check:SetChecked(info.enabled)
        row.Check:SetScript("OnClick", function(self)
            WBF.NotebookFyi.SetTriggerEnabled(info.id, self:GetChecked())
        end)
        row.Edit:SetScript("OnClick", function()
            manage:Hide()
            WBF.UI.Fyi.OpenSetup(info.targetKind, info.targetId)
        end)
        row.Remove:SetScript("OnClick", function()
            WBF.NotebookFyi.Remove(info.id)
            WBF.UI.Fyi.PaintManage()
            WBF.UI.Fyi.Refresh()
        end)
        row:Show()
    end
    manage:SetHeight(80 + math.max(shown, 1) * 28)
end

function WBF.UI.Fyi.OpenManage()
    EnsureManage()
    manage:Show()
    WBF.UI.Fyi.PaintManage()
end
