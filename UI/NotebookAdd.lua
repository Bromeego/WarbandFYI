local _, WBF = ...

-- Add flow for achievement, waypoint, item, link, and resource blocks.
-- Text, checklist, and section stay on the page itself.
WBF.UI.NotebookAdd = {}

local dialog
local state
local rows = {}
local choices = {}
local zoneRows = {}
local searchBox
local pasteBox
local xBox
local yBox
local labelBox
local urlBox
local titleText
local statusText
local hintText
local previewIcon
local previewTitle
local previewDetail
local previewProgress
local previewBar
local previewFill
local zoneLabel
local xLabel
local yLabel
local labelCaption
local pasteCaption
local backButton
local cancelButton
local nextButton
local searchTicket = 0
local searchArmed = false
local searchPending = false
local painting = false
local focusedBox = nil
local focusedCursor = nil

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Shown(text)
    if type(text) ~= "string" then
        return ""
    end
    return (text:gsub("|", "||"))
end

local function Color(widget, color)
    widget:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function Status(text)
    state.status = text
    if statusText then
        statusText:SetText(Shown(text or ""))
        statusText:SetShown(text ~= nil and text ~= "")
    end
end

local function SectionFor()
    if not state then
        return nil
    end
    if state.sectionId and WBF.Notebook.GetSection(state.sectionId) then
        return state.sectionId
    end
    local section = WBF.Notebook.CreateSection(state.pageId, "Notes")
    if not section then
        return nil
    end
    state.sectionId = section.id
    return section.id
end

local function RefreshNotebook()
    local frame = WBF.UI and WBF.UI.frame
    if frame and frame.Refresh then
        frame:Refresh(false)
    end
end

function WBF.UI.NotebookAdd.Close()
    if not dialog then
        return
    end
    searchArmed = false
    searchPending = false
    searchTicket = searchTicket + 1
    dialog:Hide()
    if WBF.PlanAchievements and WBF.PlanAchievements.ClearSearch then
        WBF.PlanAchievements.ClearSearch()
    end
end

local function Finish(block)
    if not block then
        Status("Couldn't add that.")
        return
    end
    WBF.UI.NotebookAdd.Close()
    RefreshNotebook()
end

local function HoldKeys(edit)
    if edit.SetPropagateKeyboardInput then
        edit:SetPropagateKeyboardInput(false)
    end
end

local function Box(parent, width)
    local edit = WBF.UI.EditBox(parent, width, 22)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
    WBF.UI.BindWheel(edit)
    if WBF.UI.KeepKeyboard then
        WBF.UI.KeepKeyboard(edit)
    end
    edit:SetScript("OnEditFocusGained", function(self)
        HoldKeys(self)
    end)
    edit:SetScript("OnKeyDown", function(self)
        HoldKeys(self)
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return edit
end

local function ActionButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 22)
    WBF.UI.BindWheel(button)
    WBF.UI.Paint(button, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    Color(text, WBF.UI.Colors.gold)
    button.Label = text
    button:SetScript("OnEnter", function(self)
        WBF.UI.Paint(self, { 0.11, 0.12, 0.15, 0.98 }, WBF.UI.Colors.gold)
    end)
    button:SetScript("OnLeave", function(self)
        WBF.UI.Paint(self, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    end)
    return button
end

local function MakeRow(parent)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(42)
    button:RegisterForClicks("LeftButtonUp")
    WBF.UI.BindWheel(button)
    WBF.UI.Paint(button, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", 8, 0)
    local title = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 44, -6)
    title:SetPoint("TOPRIGHT", -8, -6)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    Color(title, WBF.UI.Colors.cream)
    local detail = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail:SetPoint("BOTTOMLEFT", 44, 6)
    detail:SetPoint("BOTTOMRIGHT", -8, 6)
    detail:SetJustifyH("LEFT")
    detail:SetWordWrap(false)
    Color(detail, WBF.UI.Colors.muted)
    local add = CreateFrame("Button", nil, button, "BackdropTemplate")
    add:SetSize(40, 18)
    add:SetPoint("RIGHT", -6, 0)
    WBF.UI.Paint(add, WBF.UI.Colors.card, WBF.UI.Colors.gold)
    local addLabel = add:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addLabel:SetPoint("CENTER")
    addLabel:SetText("Add")
    Color(addLabel, WBF.UI.Colors.gold)
    add:SetScript("OnEnter", function(self)
        WBF.UI.Paint(self, { 0.11, 0.1, 0.06, 0.98 }, WBF.UI.Colors.gold)
    end)
    add:SetScript("OnLeave", function(self)
        WBF.UI.Paint(self, WBF.UI.Colors.card, WBF.UI.Colors.gold)
    end)
    add:Hide()
    button.Icon = icon
    button.Title = title
    button.Detail = detail
    button.Add = add
    button:Hide()
    return button
end

local function MakeChoice(parent, label, detail)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(36)
    button:RegisterForClicks("LeftButtonUp")
    WBF.UI.BindWheel(button)
    local mark = button:CreateTexture(nil, "ARTWORK")
    mark:SetSize(10, 10)
    mark:SetPoint("LEFT", 10, 0)
    mark:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 1)
    local title = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 28, -4)
    title:SetJustifyH("LEFT")
    title:SetText(label)
    Color(title, WBF.UI.Colors.cream)
    local sub = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("BOTTOMLEFT", 28, 4)
    sub:SetJustifyH("LEFT")
    sub:SetText(detail)
    Color(sub, WBF.UI.Colors.muted)
    button.Mark = mark
    button:Hide()
    return button
end

local function HideEdit(edit)
    if edit and not edit:HasFocus() then
        edit:Hide()
    end
end

local function HideBody()
    HideEdit(searchBox)
    HideEdit(pasteBox)
    HideEdit(xBox)
    HideEdit(yBox)
    HideEdit(labelBox)
    HideEdit(urlBox)
    hintText:Hide()
    previewIcon:Hide()
    previewTitle:Hide()
    previewDetail:Hide()
    previewProgress:Hide()
    previewBar:Hide()
    previewFill:Hide()
    zoneLabel:Hide()
    xLabel:Hide()
    yLabel:Hide()
    labelCaption:Hide()
    pasteCaption:Hide()
    backButton:Hide()
    for index = 1, #rows do
        rows[index]:Hide()
    end
    for index = 1, #choices do
        choices[index]:Hide()
    end
    for index = 1, #zoneRows do
        zoneRows[index]:Hide()
    end
end

local function ShowChoices()
    local selected = state.choice or "player"
    local specs = {
        { id = "player", title = "My current position" },
        { id = "target", title = "Target + current position" },
        { id = "manual", title = "Manual location" },
    }
    for index = 1, #choices do
        local button = choices[index]
        local spec = specs[index]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -36 - ((index - 1) * 42))
        button:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -36 - ((index - 1) * 42))
        if spec.id == selected then
            WBF.UI.Paint(button, { 0.11, 0.1, 0.06, 0.98 }, WBF.UI.Colors.gold)
            button.Mark:Show()
        else
            WBF.UI.Paint(button, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
            button.Mark:Hide()
        end
        button:SetScript("OnClick", function()
            state.choice = spec.id
            Status(nil)
            ShowChoices()
        end)
        button:Show()
    end
end

local function FillRow(button, y, title, detail, icon, onClick, onAdd)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -y)
    button:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -y)
    button.Title:SetText(Shown(title or ""))
    button.Detail:SetText(Shown(detail or ""))
    button.Title:ClearAllPoints()
    button.Detail:ClearAllPoints()
    local right = onAdd and -52 or -8
    if icon then
        button.Icon:SetTexture(icon)
        button.Icon:Show()
        button.Title:SetPoint("TOPLEFT", 44, -6)
        button.Detail:SetPoint("BOTTOMLEFT", 44, 6)
    else
        button.Icon:Hide()
        button.Title:SetPoint("TOPLEFT", 8, -6)
        button.Detail:SetPoint("BOTTOMLEFT", 8, 6)
    end
    button.Title:SetPoint("TOPRIGHT", right, -6)
    button.Detail:SetPoint("BOTTOMRIGHT", right, 6)
    button:SetScript("OnClick", onClick or function()
    end)
    if button.Add then
        if onAdd then
            button.Add:SetScript("OnClick", onAdd)
            button.Add:Show()
        else
            button.Add:Hide()
        end
    end
    button:Show()
end

local PaintAchievementResults

local function QueueAchievementSearch(text)
    searchArmed = false
    searchTicket = searchTicket + 1
    local ticket = searchTicket
    local query = Trim(text or "")
    local numeric = tonumber(query) ~= nil
    searchPending = query ~= "" and (numeric or #query >= 2)
    local function run()
        if ticket ~= searchTicket or not dialog:IsShown() or not state or state.screen ~= "achievement" then
            return
        end
        if query == "" or (not numeric and #query < 2) then
            searchPending = false
            state.results = {}
            if PaintAchievementResults then
                PaintAchievementResults()
            end
            return
        end
        searchArmed = true
        state.results = (WBF.PlanAchievements and WBF.PlanAchievements.Search and WBF.PlanAchievements.Search(query)) or {}
        searchPending = false
        if state.screen == "achievement" and PaintAchievementResults then
            PaintAchievementResults()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.32, run)
    else
        run()
    end
end

local function RememberZone(zone)
    state.draft = state.draft or {}
    state.draft.mapID = zone.mapID
    state.draft.zone = zone.name
    state.query = zone.name
end

local function ManualPoint()
    local draft = state.draft or {}
    return WBF.NotebookSmart.CleanPoint({
        mapID = draft.mapID,
        x = xBox:GetText(),
        y = yBox:GetText(),
        zone = draft.zone,
        label = labelBox:GetText(),
        source = "manual",
    })
end

local function ApplyPaste(text)
    local parsed = WBF.NotebookSmart.ParseWaypoint(text)
    if not parsed then
        return
    end
    xBox:SetText(string.format("%.1f", parsed.x))
    yBox:SetText(string.format("%.1f", parsed.y))
    state.draft = state.draft or {}
    state.draft.x = parsed.x
    state.draft.y = parsed.y
    state.draft.source = "manual"
    if parsed.mapID and parsed.zone then
        state.draft.mapID = parsed.mapID
        state.draft.zone = parsed.zone
        state.query = parsed.zone
        if searchBox:GetText() ~= parsed.zone then
            painting = true
            searchBox:SetText(parsed.zone)
            painting = false
        end
        Status(nil)
    elseif parsed.zone then
        Status("Choose a zone. That name could not be resolved.")
    end
    if not painting then
        WBF.UI.NotebookAdd.Paint()
    end
end

local function ShowPreviewCopy(url, y)
    if not url or url == "" then
        return y
    end
    urlBox._url = url
    urlBox._lock = true
    urlBox:SetText(url)
    urlBox._lock = false
    urlBox:ClearAllPoints()
    urlBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 28, -y)
    urlBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -y)
    urlBox:Show()
    hintText:ClearAllPoints()
    hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -(y + 22))
    hintText:SetText("Ctrl+C to copy")
    hintText:Show()
    return y + 40
end

PaintAchievementResults = function()
    if not dialog or not state or state.screen ~= "achievement" then
        return
    end
    for index = 1, #rows do
        rows[index]:Hide()
    end
    hintText:Hide()

    local query = Trim(state.query or "")
    local results = state.results or {}
    if query == "" then
        hintText:ClearAllPoints()
        hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -72)
        hintText:SetText("Search by achievement name or ID.")
        hintText:Show()
    elseif tonumber(query) == nil and #query < 2 then
        hintText:ClearAllPoints()
        hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -72)
        hintText:SetText("Type at least 2 characters to search.")
        hintText:Show()
    elseif searchPending then
        hintText:ClearAllPoints()
        hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -72)
        hintText:SetText("Searching...")
        hintText:Show()
    elseif #results == 0 then
        hintText:ClearAllPoints()
        hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -72)
        hintText:SetText("No achievements match that.")
        hintText:Show()
    end

    local y = 72
    local visible = math.min(#rows, #results)
    for index = 1, visible do
        local info = results[index]
        FillRow(rows[index], y, info.name, info.description, info.icon, function()
            state.selected = info
            state.screen = "achievement-preview"
            state.focus = false
            WBF.UI.NotebookAdd.Paint()
        end, function()
            local sectionId = SectionFor()
            Finish(sectionId and WBF.Notebook.AddAchievement(sectionId, info.id))
        end)
        y = y + 46
    end

    if results.capped then
        hintText:ClearAllPoints()
        hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -448)
        hintText:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -448)
        hintText:SetText("Showing the first " .. tostring(#rows) .. " matches.")
        hintText:Show()
    end
end

local function PaintAchievement()
    titleText:SetText("Add Achievement")
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 22, -40)
    searchBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -40)
    searchBox:Show()
    local query = state.query or ""
    if searchBox:GetText() ~= query then
        searchBox:SetText(query)
    end

    -- Keep this dialog stable while search results change. Re-sizing it on
    -- every ACHIEVEMENT_SEARCH_UPDATED was what made typing feel like the
    -- editor was jumping around.
    dialog:SetHeight(500)
    PaintAchievementResults()
    nextButton:Hide()
    if state.focus then
        state.focus = false
        searchBox:SetFocus()
    end
end

local function PaintAchievementPreview()
    titleText:SetText("Add Achievement")
    local selected = state.selected or {}
    local id = selected.id or selected.achievementID
    local progress = WBF.PlanAchievements and WBF.PlanAchievements.Progress and WBF.PlanAchievements.Progress(id) or nil
    local name = (progress and progress.name) or selected.name or ("Achievement " .. tostring(id or ""))
    local description = (progress and progress.description) or selected.description or ""
    local icon = (progress and progress.icon) or selected.icon
    if icon then
        previewIcon:SetTexture(icon)
        previewIcon:Show()
    end
    previewTitle:SetText(Shown(name))
    previewTitle:Show()
    if description ~= "" then
        previewDetail:SetText(Shown(description))
        previewDetail:Show()
    end
    local line = progress and WBF.PlanAchievements.ProgressText and WBF.PlanAchievements.ProgressText(progress) or nil
    local y = description ~= "" and 118 or 96
    if line then
        previewProgress:ClearAllPoints()
        previewProgress:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -y)
        previewProgress:SetText(Shown(line))
        previewProgress:Show()
        y = y + 18
    end
    if progress and progress.percent and progress.required then
        previewBar:ClearAllPoints()
        previewBar:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -y)
        previewBar:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -y)
        previewBar:Show()
        local width = 408
        previewFill:ClearAllPoints()
        previewFill:SetPoint("TOPLEFT", previewBar, "TOPLEFT", 0, 0)
        previewFill:SetSize(math.max(1, math.floor(width * progress.percent / 100)), 6)
        previewFill:Show()
        y = y + 16
    end
    local url = selected.url or selected.sourceURL
    y = ShowPreviewCopy(url, y + 6)
    dialog:SetHeight(math.max(220, y + 56))
    backButton:Show()
    nextButton.Label:SetText("Add to Page")
    nextButton:Show()
    nextButton:SetScript("OnClick", function()
        if WBF.PlanAchievements and WBF.PlanAchievements.IsTrackable and not WBF.PlanAchievements.IsTrackable(id) then
            Status("That achievement isn't available.")
            return
        end
        local sectionId = SectionFor()
        Finish(sectionId and WBF.Notebook.AddAchievement(sectionId, id, url))
    end)
end

local function PaintWaypoint()
    titleText:SetText(state.blockId and "Edit Waypoint" or "Add Waypoint")
    ShowChoices()
    dialog:SetHeight(250)
    nextButton.Label:SetText("Next")
    nextButton:Show()
    nextButton:SetScript("OnClick", function()
        local choice = state.choice or "player"
        if choice == "manual" then
            state.screen = "waypoint-manual"
            state.focus = true
            state.query = ""
            state.draft = { source = "manual" }
            xBox:SetText("")
            yBox:SetText("")
            labelBox:SetText("")
            pasteBox:SetText("")
            WBF.UI.NotebookAdd.Paint()
            return
        end
        local here, reason
        if choice == "target" then
            here, reason = WBF.NotebookSmart.TargetLocation()
        else
            here, reason = WBF.NotebookSmart.PlayerLocation()
        end
        if not here then
            if reason == "target" then
                Status("Select a target first.")
            else
                Status("Your location isn't available on this map. Choose Manual location.")
            end
            return
        end
        state.draft = here
        state.screen = "waypoint-preview"
        state.focus = true
        WBF.UI.NotebookAdd.Paint()
    end)
end

local function PaintWaypointPreview()
    titleText:SetText(state.blockId and "Edit Waypoint" or "Add Waypoint")
    local draft = state.draft or {}
    local line = WBF.NotebookSmart.PlaceLine(draft) or "Location unavailable"
    previewTitle:SetText(Shown(draft.label or draft.zone or "Waypoint"))
    previewTitle:Show()
    previewDetail:SetText(Shown(line))
    previewDetail:Show()
    labelCaption:ClearAllPoints()
    labelCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -96)
    labelCaption:SetText("Optional label")
    labelCaption:Show()
    labelBox:ClearAllPoints()
    labelBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 22, -114)
    labelBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -114)
    labelBox:Show()
    local label = draft.label or ""
    if state.focus then
        labelBox:SetText(label)
    end
    dialog:SetHeight(230)
    backButton:Show()
    nextButton.Label:SetText(state.blockId and "Save" or "Add Waypoint")
    nextButton:Show()
    nextButton:SetScript("OnClick", function()
        local point = WBF.NotebookSmart.CleanPoint({
            mapID = draft.mapID,
            x = draft.x,
            y = draft.y,
            zone = draft.zone,
            label = labelBox:GetText(),
            source = draft.source,
        })
        if not point then
            Status("That location could not be saved.")
            return
        end
        if state.blockId then
            Finish(WBF.Notebook.SetWaypoint(state.blockId, point))
            return
        end
        local sectionId = SectionFor()
        Finish(sectionId and WBF.Notebook.AddWaypoint(sectionId, point))
    end)
    if state.focus then
        state.focus = false
        if draft.source == "manual" then
            labelBox:SetFocus()
        end
    end
end

local function PaintManual()
    titleText:SetText(state.blockId and "Edit Waypoint" or "Add Waypoint")
    zoneLabel:Show()
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 22, -56)
    searchBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -56)
    searchBox:Show()
    local query = state.query or ""
    if searchBox:GetText() ~= query then
        searchBox:SetText(query)
    end
    local zones = WBF.NotebookSmart.Zones(query, 6)
    local y = 86
    if #zones == 0 then
        hintText:ClearAllPoints()
        hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -y)
        hintText:SetText("Type a zone name.")
        hintText:Show()
        y = y + 18
    end
    for index = 1, math.min(#zoneRows, #zones) do
        local zone = zones[index]
        local row = zoneRows[index]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -y)
        row:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -y)
        row.Title:SetText(Shown(zone.name))
        row.Detail:SetText("")
        row.Icon:Hide()
        row.Title:SetPoint("TOPLEFT", 8, -12)
        row:SetScript("OnClick", function()
            RememberZone(zone)
            Status(nil)
            WBF.UI.NotebookAdd.Paint()
        end)
        if state.draft and state.draft.mapID == zone.mapID then
            WBF.UI.Paint(row, { 0.11, 0.1, 0.06, 0.98 }, WBF.UI.Colors.gold)
        else
            WBF.UI.Paint(row, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        end
        row:Show()
        y = y + 32
    end
    xLabel:ClearAllPoints()
    xLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -(y + 6))
    xLabel:Show()
    yLabel:ClearAllPoints()
    yLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 150, -(y + 6))
    yLabel:Show()
    xBox:ClearAllPoints()
    xBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 22, -(y + 22))
    xBox:SetWidth(110)
    xBox:Show()
    yBox:ClearAllPoints()
    yBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 156, -(y + 22))
    yBox:SetWidth(110)
    yBox:Show()
    labelCaption:ClearAllPoints()
    labelCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -(y + 50))
    labelCaption:Show()
    labelBox:ClearAllPoints()
    labelBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 22, -(y + 66))
    labelBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -(y + 66))
    labelBox:Show()
    pasteCaption:ClearAllPoints()
    pasteCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -(y + 96))
    pasteCaption:Show()
    pasteBox:ClearAllPoints()
    pasteBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 22, -(y + 112))
    pasteBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -(y + 112))
    pasteBox:Show()
    dialog:SetHeight(y + 200)
    backButton:Show()
    nextButton.Label:SetText("Next")
    nextButton:Show()
    nextButton:SetScript("OnClick", function()
        local point = ManualPoint()
        if not point then
            if not state.draft or not state.draft.mapID then
                Status("Choose a zone the client can resolve.")
            else
                Status("Enter coordinates between 0 and 100.")
            end
            return
        end
        state.draft = point
        state.screen = "waypoint-preview"
        state.focus = true
        WBF.UI.NotebookAdd.Paint()
    end)
    if state.focus then
        state.focus = false
        searchBox:SetFocus()
    end
end

local function PaintItem()
    titleText:SetText("Track Item")
    hintText:ClearAllPoints()
    hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -40)
    hintText:SetText("Shift-click an item from your bags/bank, paste an item link, or enter an item ID.")
    hintText:Show()
    pasteCaption:ClearAllPoints()
    pasteCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -68)
    pasteCaption:SetText("Item")
    pasteCaption:Show()
    pasteBox:ClearAllPoints()
    pasteBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 22, -84)
    pasteBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -84)
    pasteBox:Show()

    local text = pasteBox:GetText() or ""
    local itemID = WBF.NotebookSmart and WBF.NotebookSmart.ItemID and WBF.NotebookSmart.ItemID(text) or nil
    if itemID then
        local described = WBF.NotebookSmart.Describe({ refType = "item", refID = itemID })
        previewTitle:ClearAllPoints()
        previewTitle:SetPoint("TOPLEFT", 60, -124)
        previewTitle:SetPoint("TOPRIGHT", -16, -124)
        previewTitle:SetText(Shown(described.title or ("Item " .. tostring(itemID))))
        previewTitle:Show()
        previewDetail:ClearAllPoints()
        previewDetail:SetPoint("TOPLEFT", 60, -146)
        previewDetail:SetPoint("TOPRIGHT", -16, -146)
        previewDetail:SetText(Shown(described.detail or ("Item " .. tostring(itemID))))
        previewDetail:Show()
        if described.icon then
            previewIcon:ClearAllPoints()
            previewIcon:SetPoint("TOPLEFT", 16, -122)
            previewIcon:SetTexture(described.icon)
            previewIcon:Show()
        end
        nextButton.Label:SetText("Add to Page")
        nextButton:Show()
        nextButton:SetScript("OnClick", function()
            local sectionId = SectionFor()
            Finish(sectionId and WBF.Notebook.AddReference(sectionId, {
                refType = "item",
                refID = itemID,
                -- Keep the resolved item name as a friendly fallback. The live
                -- item API remains authoritative and refreshes when available.
                label = described and described.resolved and described.title or nil,
            }))
        end)
        Status(nil)
    else
        nextButton:Hide()
        if Trim(text) ~= "" then
            Status("Shift-click an item or paste a valid item link / item ID.")
        else
            Status(nil)
        end
    end
    dialog:SetHeight(238)
    if state.focus then
        state.focus = false
        pasteBox:SetFocus()
    end
end

local function PaintLink()
    titleText:SetText("Add Link / Wowhead")
    hintText:ClearAllPoints()
    hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -40)
    hintText:SetText("Paste a Wowhead link. Other web addresses are kept as links.")
    hintText:Show()
    pasteBox:ClearAllPoints()
    pasteBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 22, -68)
    pasteBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -68)
    pasteBox:Show()
    dialog:SetHeight(190)
    nextButton.Label:SetText("Next")
    nextButton:Show()
    nextButton:SetScript("OnClick", function()
        local parsed = WBF.NotebookSmart.ParseLink(pasteBox:GetText() or "")
        if not parsed then
            Status("Paste a Wowhead link or a web address.")
            return
        end
        if parsed.kind == "achievement" then
            if WBF.PlanAchievements and WBF.PlanAchievements.IsTrackable and not WBF.PlanAchievements.IsTrackable(parsed.id) then
                Status("That achievement isn't available.")
                return
            end
            local info = WBF.PlanAchievements and WBF.PlanAchievements.Info and WBF.PlanAchievements.Info(parsed.id) or nil
            state.selected = {
                id = parsed.id,
                url = parsed.url,
                name = info and info.name or nil,
                description = info and info.description or nil,
                icon = info and info.icon or nil,
            }
            state.screen = "achievement-preview"
            WBF.UI.NotebookAdd.Paint()
            return
        end
        state.selected = parsed
        state.screen = parsed.kind == "resource" and "resource-preview" or "link-preview"
        WBF.UI.NotebookAdd.Paint()
    end)
    if state.focus then
        state.focus = false
        pasteBox:SetFocus()
    end
end

local function PaintLinkPreview()
    titleText:SetText("Add Link / Wowhead")
    local selected = state.selected or {}
    local described = WBF.NotebookSmart.Describe({
        refType = selected.refType,
        refID = selected.refID or selected.id,
        url = selected.url,
        label = selected.label,
    })
    previewTitle:SetText(Shown(described.title or "Link"))
    previewTitle:Show()
    if described.detail and described.detail ~= "" then
        previewDetail:SetText(Shown(described.detail))
        previewDetail:Show()
    end
    if described.icon then
        previewIcon:SetTexture(described.icon)
        previewIcon:Show()
    end
    local y = ShowPreviewCopy(described.url or selected.url, described.detail and 110 or 90)
    dialog:SetHeight(math.max(200, y + 56))
    backButton:Show()
    nextButton.Label:SetText("Add to Page")
    nextButton:Show()
    nextButton:SetScript("OnClick", function()
        local sectionId = SectionFor()
        Finish(sectionId and WBF.Notebook.AddReference(sectionId, {
            refType = selected.refType,
            refID = selected.refID or selected.id,
            url = selected.url,
            label = selected.label,
        }))
    end)
end

local function PaintResource()
    titleText:SetText("Add Resource")
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 22, -40)
    searchBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -40)
    searchBox:Show()
    local query = state.query or ""
    if searchBox:GetText() ~= query then
        searchBox:SetText(query)
    end
    local results = {}
    if Trim(query) ~= "" and WBF.Resources and WBF.Resources.SearchNames then
        results = WBF.Resources.SearchNames(query, 8)
    end
    state.results = results
    if Trim(query) == "" then
        hintText:ClearAllPoints()
        hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -72)
        hintText:SetText("Search currencies and resources WarbandFYI already tracks.")
        hintText:Show()
    elseif #results == 0 then
        hintText:ClearAllPoints()
        hintText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -72)
        hintText:SetText("No tracked resource matches that.")
        hintText:Show()
    end
    local y = 72
    for index = 1, math.min(#rows, #results) do
        local info = results[index]
        local view = WBF.Resources.NotebookView and WBF.Resources.NotebookView(info.key) or nil
        local detail = info.trackingType == "item" and "Item" or "Currency"
        if view and view.amount ~= nil then
            detail = WBF.Format.Number(view.amount)
        end
        FillRow(rows[index], y, info.name, detail, view and view.icon or nil, nil, function()
            local sectionId = SectionFor()
            Finish(sectionId and WBF.Notebook.AddResource(sectionId, info.key))
        end)
        y = y + 46
    end
    dialog:SetHeight(math.max(220, y + 56))
    nextButton:Hide()
    if state.focus then
        state.focus = false
        searchBox:SetFocus()
    end
end

local function PaintResourcePreview()
    titleText:SetText("Add Resource")
    local selected = state.selected or {}
    local view = WBF.Resources and WBF.Resources.NotebookView and WBF.Resources.NotebookView(selected.resourceKey) or nil
    local name = (view and view.name) or selected.resourceKey or "Resource"
    previewTitle:SetText(Shown(name))
    previewTitle:Show()
    local detail = "No balance yet"
    if view and view.amount ~= nil then
        detail = WBF.Format.Number(view.amount)
        if view.accountWide then
            detail = detail .. "   Warband"
        end
    end
    previewDetail:SetText(Shown(detail))
    previewDetail:Show()
    local y = ShowPreviewCopy(selected.url, 100)
    dialog:SetHeight(math.max(200, y + 56))
    backButton:Show()
    nextButton.Label:SetText("Add to Page")
    nextButton:Show()
    nextButton:SetScript("OnClick", function()
        local sectionId = SectionFor()
        Finish(sectionId and WBF.Notebook.AddResource(sectionId, selected.resourceKey, selected.url))
    end)
end

function WBF.UI.NotebookAdd.Paint()
    if not dialog or not state or painting then
        return
    end
    focusedBox = nil
    focusedCursor = nil
    local boxes = { searchBox, pasteBox, xBox, yBox, labelBox, urlBox }
    for index = 1, #boxes do
        local box = boxes[index]
        if box:HasFocus() then
            focusedBox = box
            focusedCursor = box:GetCursorPosition()
            break
        end
    end
    painting = true
    HideBody()
    statusText:ClearAllPoints()
    statusText:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 40)
    statusText:SetPoint("BOTTOMRIGHT", nextButton, "BOTTOMLEFT", -8, 0)
    statusText:SetText(Shown(state.status or ""))
    statusText:SetShown(state.status ~= nil and state.status ~= "")
    cancelButton:Show()
    local screen = state.screen
    if screen == "achievement" then
        PaintAchievement()
    elseif screen == "achievement-preview" then
        PaintAchievementPreview()
    elseif screen == "waypoint" then
        PaintWaypoint()
    elseif screen == "waypoint-preview" then
        PaintWaypointPreview()
    elseif screen == "waypoint-manual" then
        PaintManual()
    elseif screen == "item" then
        PaintItem()
    elseif screen == "link" then
        PaintLink()
    elseif screen == "link-preview" then
        PaintLinkPreview()
    elseif screen == "resource-preview" then
        PaintResourcePreview()
    else
        PaintResource()
    end
    painting = false
    if focusedBox and focusedBox:IsShown() then
        local box = focusedBox
        local cursor = focusedCursor
        local function restore()
            if not box:IsShown() or not state then
                return
            end
            box:SetFocus()
            if cursor then
                box:SetCursorPosition(cursor)
            end
            HoldKeys(box)
        end
        restore()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, restore)
        end
    end
    focusedBox = nil
end

function WBF.UI.NotebookAdd.OnSearchUpdated()
    if not dialog or not dialog:IsShown() or not state or state.screen ~= "achievement" or not searchArmed then
        return
    end
    if not WBF.PlanAchievements or not WBF.PlanAchievements.ReadLatest then
        return
    end
    state.results = WBF.PlanAchievements.ReadLatest() or {}
    if PaintAchievementResults then
        PaintAchievementResults()
    end
end

local function Back()
    if not state then
        return
    end
    Status(nil)
    if state.screen == "achievement-preview" and state.kind == "link" then
        state.screen = "link"
    elseif state.screen == "achievement-preview" then
        state.screen = "achievement"
    elseif state.screen == "waypoint-preview" and state.draft and state.draft.source == "manual" then
        state.screen = "waypoint-manual"
        state.focus = true
    elseif state.screen == "waypoint-preview" or state.screen == "waypoint-manual" then
        state.screen = "waypoint"
    elseif state.screen == "link-preview" or state.screen == "resource-preview" then
        state.screen = "link"
    end
    WBF.UI.NotebookAdd.Paint()
end

function WBF.UI.NotebookAdd.Open(kind, pageId, sectionId, block)
    if not dialog or not WBF.Notebook or not WBF.Notebook.GetPage(pageId) then
        return
    end
    state = {
        kind = kind,
        pageId = pageId,
        sectionId = sectionId,
        screen = kind,
        choice = "player",
        draft = {},
        query = "",
        results = {},
        focus = true,
    }
    local editing = kind == "waypoint" and type(block) == "table" and block.type == "waypoint"
    if editing then
        state.blockId = block.id
        state.screen = "waypoint-manual"
        state.choice = "manual"
        state.query = block.zone or ""
        state.draft = {
            mapID = block.mapID,
            zone = block.zone,
            x = block.x,
            y = block.y,
            label = block.label,
            source = block.source or "manual",
        }
        state.focus = true
    end
    searchBox:SetText(state.query or "")
    pasteBox:SetText("")
    if editing then
        xBox:SetText(string.format("%.1f", block.x or 0))
        yBox:SetText(string.format("%.1f", block.y or 0))
        labelBox:SetText(block.label or "")
    else
        xBox:SetText("")
        yBox:SetText("")
        labelBox:SetText("")
    end
    dialog:Show()
    WBF.UI.NotebookAdd.Paint()
end

function WBF.UI.NotebookAdd.OnItemData(itemID)
    if not dialog or not dialog:IsShown() or not state or state.screen ~= "item" then
        return
    end
    local current = WBF.NotebookSmart and WBF.NotebookSmart.ItemID and WBF.NotebookSmart.ItemID(pasteBox:GetText() or "") or nil
    if not itemID or not current or tonumber(itemID) == tonumber(current) then
        WBF.UI.NotebookAdd.Paint()
    end
end

function WBF.UI.NotebookAdd.Attach()
    if dialog then
        return
    end
    local parent = UIParent
    dialog = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dialog:SetSize(440, 280)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetToplevel(true)
    dialog:Hide()
    WBF.UI.Paint(dialog, WBF.UI.Colors.window, WBF.UI.Colors.gold)
    dialog:SetScript("OnHide", function()
        searchArmed = false
        searchPending = false
        searchTicket = searchTicket + 1
    end)

    titleText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", 16, -12)
    titleText:SetJustifyH("LEFT")
    Color(titleText, WBF.UI.Colors.gold)

    local close = CreateFrame("Button", nil, dialog)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -8, -8)
    WBF.UI.BindWheel(close)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    closeText:SetPoint("CENTER")
    closeText:SetText("x")
    Color(closeText, WBF.UI.Colors.gold)
    close:SetScript("OnClick", function()
        WBF.UI.NotebookAdd.Close()
    end)

    searchBox = Box(dialog, 200)
    pasteBox = Box(dialog, 200)
    xBox = Box(dialog, 110)
    yBox = Box(dialog, 110)
    labelBox = Box(dialog, 200)
    urlBox = Box(dialog, 200)
    urlBox:SetScript("OnTextChanged", function(self)
        if self._lock then
            return
        end
        if self._url and self:GetText() ~= self._url then
            self._lock = true
            self:SetText(self._url)
            self:HighlightText()
            self._lock = false
        end
    end)
    urlBox:SetScript("OnEditFocusGained", function(self)
        HoldKeys(self)
        self:HighlightText()
    end)

    searchBox:SetScript("OnTextChanged", function(self)
        if painting or not state then
            return
        end
        state.query = self:GetText() or ""
        if state.screen == "achievement" then
            searchArmed = false
            state.results = {}
            QueueAchievementSearch(state.query)
            if PaintAchievementResults then
                PaintAchievementResults()
            end
        elseif state.screen == "resource" then
            WBF.UI.NotebookAdd.Paint()
        elseif state.screen == "waypoint-manual" then
            if not state.draft or state.draft.zone ~= state.query then
                if state.draft then
                    state.draft.mapID = nil
                    state.draft.zone = nil
                end
            end
            WBF.UI.NotebookAdd.Paint()
        end
    end)
    pasteBox:SetScript("OnTextChanged", function(self)
        if painting or not state then
            return
        end
        if state.screen == "waypoint-manual" then
            ApplyPaste(self:GetText() or "")
        elseif state.screen == "item" then
            WBF.UI.NotebookAdd.Paint()
        end
    end)

    hintText = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintText:SetJustifyH("LEFT")
    hintText:SetWordWrap(true)
    hintText:SetWidth(400)
    Color(hintText, WBF.UI.Colors.muted)

    statusText = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(false)
    Color(statusText, WBF.UI.Colors.muted)

    previewIcon = dialog:CreateTexture(nil, "ARTWORK")
    previewIcon:SetSize(36, 36)
    previewIcon:SetPoint("TOPLEFT", 16, -44)
    previewTitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewTitle:SetPoint("TOPLEFT", 60, -44)
    previewTitle:SetPoint("TOPRIGHT", -16, -44)
    previewTitle:SetJustifyH("LEFT")
    previewTitle:SetWordWrap(true)
    Color(previewTitle, WBF.UI.Colors.cream)
    previewDetail = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewDetail:SetPoint("TOPLEFT", 60, -66)
    previewDetail:SetPoint("TOPRIGHT", -16, -66)
    previewDetail:SetJustifyH("LEFT")
    previewDetail:SetWordWrap(true)
    Color(previewDetail, WBF.UI.Colors.muted)
    previewProgress = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewProgress:SetJustifyH("LEFT")
    Color(previewProgress, WBF.UI.Colors.cream)
    previewBar = dialog:CreateTexture(nil, "BACKGROUND")
    previewBar:SetHeight(6)
    previewBar:SetColorTexture(WBF.UI.Colors.track[1], WBF.UI.Colors.track[2], WBF.UI.Colors.track[3], WBF.UI.Colors.track[4])
    previewFill = dialog:CreateTexture(nil, "ARTWORK")
    previewFill:SetHeight(6)
    previewFill:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 1)

    zoneLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    zoneLabel:SetPoint("TOPLEFT", 16, -40)
    zoneLabel:SetText("Zone")
    Color(zoneLabel, WBF.UI.Colors.muted)
    xLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    xLabel:SetText("X")
    Color(xLabel, WBF.UI.Colors.muted)
    yLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    yLabel:SetText("Y")
    Color(yLabel, WBF.UI.Colors.muted)
    labelCaption = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    labelCaption:SetText("Optional label")
    Color(labelCaption, WBF.UI.Colors.muted)
    pasteCaption = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pasteCaption:SetText("Or paste /way command or coordinates")
    Color(pasteCaption, WBF.UI.Colors.muted)

    for index = 1, 8 do
        rows[index] = MakeRow(dialog)
    end
    choices[1] = MakeChoice(dialog, "My current position", "Where you are standing")
    choices[2] = MakeChoice(dialog, "Target + current position", "Target name, your location")
    choices[3] = MakeChoice(dialog, "Manual location", "Zone and coordinates")
    for index = 1, 6 do
        zoneRows[index] = MakeRow(dialog)
        zoneRows[index]:SetHeight(28)
    end

    backButton = ActionButton(dialog, "Back", 64)
    backButton:SetPoint("BOTTOMLEFT", 12, 12)
    backButton:SetScript("OnClick", Back)
    cancelButton = ActionButton(dialog, "Cancel", 72)
    nextButton = ActionButton(dialog, "Next", 110)
    nextButton:SetPoint("BOTTOMRIGHT", -12, 12)
    cancelButton:SetPoint("RIGHT", nextButton, "LEFT", -8, 0)
    cancelButton:SetScript("OnClick", function()
        WBF.UI.NotebookAdd.Close()
    end)

    if hooksecurefunc and type(ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if not dialog:IsShown() or not state or state.screen ~= "item" or type(link) ~= "string" then
                return
            end
            local itemID = WBF.NotebookSmart and WBF.NotebookSmart.ItemID and WBF.NotebookSmart.ItemID(link) or nil
            if not itemID then
                return
            end
            pasteBox:SetText(link)
            pasteBox:SetCursorPosition(#link)
            pasteBox:SetFocus()
        end)
    end
end
