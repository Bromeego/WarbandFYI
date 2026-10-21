local _, WBF = ...

WBF.UI.Settings = {}

local TIMEOUTS = {
    { seconds = 1800, label = "30 min" },
    { seconds = 3600, label = "60 min" },
    { seconds = 5400, label = "90 min" },
    { seconds = 7200, label = "120 min" },
}

local root
local debugCheck
local noticeCheck
local fyiCheck
local legacyFyiCheck
local resourceStatus
local fyiStatus
local diagnosticsStatus
local copyDialog
local timeoutButtons = {}

local function Color(widget, color)
    widget:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function PaintTimeout(button, selected)
    if selected then
        WBF.UI.Paint(button, WBF.UI.Colors.blue, WBF.UI.Colors.gold)
        button.Label:SetTextColor(1, 0.95, 0.85)
    else
        WBF.UI.Paint(button, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        Color(button.Label, WBF.UI.Colors.cream)
    end
end

local function Heading(text, y, width)
    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, -y)
    title:SetText(text)
    Color(title, WBF.UI.Colors.gold)
    local line = root:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], WBF.UI.Colors.line[4])
    line:SetPoint("LEFT", title, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", root, "LEFT", width, 0)
    return y + 26
end

local function Body(text, y, width, font)
    local line = root:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", 0, -y)
    line:SetWidth(width)
    line:SetJustifyH("LEFT")
    line:SetWordWrap(true)
    line:SetText(text)
    Color(line, WBF.UI.Colors.muted)
    local h = line:GetStringHeight() or 14
    if h < 14 then h = 14 end
    return line, y + h + 8
end

local function Button(text, width, x, y, onClick)
    local button = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetPoint("TOPLEFT", x, -y)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function Check(text, x, y, onClick)
    local check = CreateFrame("CheckButton", nil, root)
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, -y)
    check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetScript("OnClick", onClick)
    local label = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 6, 0)
    label:SetText(text)
    Color(label, WBF.UI.Colors.cream)
    check.Label = label
    return check
end

local function ShowCopyDialog(titleText, value)
    value = tostring(value or "")
    if not copyDialog then
        local dialog = CreateFrame("Frame", "WarbandFYICopyDialog", UIParent, "BackdropTemplate")
        dialog:SetSize(700, 480)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("DIALOG")
        dialog:SetFrameLevel(220)
        dialog:SetClampedToScreen(true)
        dialog:EnableMouse(true)
        WBF.UI.Paint(dialog, WBF.UI.Colors.window, WBF.UI.Colors.goldDim, 2)

        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 18, -16)
        Color(title, WBF.UI.Colors.gold)
        dialog.Title = title

        local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        hint:SetText("Text is selected automatically. Press Ctrl+C to copy it, then keep it somewhere safe.")
        Color(hint, WBF.UI.Colors.muted)

        local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)

        local panel = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
        panel:SetPoint("TOPLEFT", 16, -62)
        panel:SetPoint("BOTTOMRIGHT", -16, 46)
        WBF.UI.Paint(panel, { 0.025, 0.03, 0.04, 0.98 }, WBF.UI.Colors.goldDim)

        local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 8, -8)
        scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

        local edit = CreateFrame("EditBox", nil, scrollFrame)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(620)
        edit:SetHeight(10000)
        edit:SetTextInsets(4, 4, 4, 4)
        edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
        edit:SetScript("OnTextChanged", function(self)
            scrollFrame:UpdateScrollChildRect()
        end)
        scrollFrame:SetScrollChild(edit)
        dialog.Edit = edit

        local done = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        done:SetSize(90, 24)
        done:SetPoint("BOTTOMRIGHT", -16, 14)
        done:SetText("Close")
        done:SetScript("OnClick", function() dialog:Hide() end)

        copyDialog = dialog
        local listed = false
        if UISpecialFrames then
            for index = 1, #UISpecialFrames do
                if UISpecialFrames[index] == "WarbandFYICopyDialog" then
                    listed = true
                    break
                end
            end
            if not listed then
                table.insert(UISpecialFrames, "WarbandFYICopyDialog")
            end
        end
    end
    copyDialog.Title:SetText(titleText or "Copy")
    copyDialog.Edit:SetText(value)
    copyDialog.Edit:SetCursorPosition(0)
    copyDialog:Show()
    copyDialog:Raise()
    copyDialog.Edit:SetFocus()
    copyDialog.Edit:HighlightText()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if copyDialog and copyDialog:IsShown() then
                copyDialog.Edit:SetFocus()
                copyDialog.Edit:HighlightText()
            end
        end)
    end
end

local function ResetMainWindow()
    local frame = WBF.UI.frame
    if not frame then
        return
    end
    WarbandFYI_DB.config.window = nil
    frame.applyingSize = true
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    frame:SetSize(1040, 680)
    frame.applyingSize = false
    frame:Refresh(true)
end

function WBF.UI.Settings.Attach(parent)
    root = parent
    local width = 720
    local y = 4

    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, -y)
    title:SetText("Settings")
    Color(title, WBF.UI.Colors.gold)
    y = y + 30

    local intro
    intro, y = Body("Settings control how WarbandFYI behaves and explain the features it exposes. Your Notebook remains your content; WarbandFYI only decides when and how to surface it.", y, width, "GameFontHighlight")
    local searchHelp
    searchHelp, y = Body("Global search — use the Search WarbandFYI box in the window header to find resources, Notebook content, characters, and recorded activity from anywhere in the addon. Press Enter to open the best match, or use /wbfyi search <text>.", y + 4, width)
    Color(intro, WBF.UI.Colors.cream)
    y = y + 6

    y = Heading("GENERAL", y, width)

    local timeoutLabel = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timeoutLabel:SetPoint("TOPLEFT", 0, -y)
    timeoutLabel:SetText("Session timeout")
    Color(timeoutLabel, WBF.UI.Colors.cream)
    y = y + 24

    for index = 1, #TIMEOUTS do
        local info = TIMEOUTS[index]
        local button = CreateFrame("Button", nil, root, "BackdropTemplate")
        button:SetSize(88, 26)
        button:SetPoint("TOPLEFT", (index - 1) * 96, -y)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER")
        label:SetText(info.label)
        button.Label = label
        button.seconds = info.seconds
        button:SetScript("OnClick", function(self)
            WarbandFYI_DB.config.sessionTimeoutSeconds = self.seconds
            WBF.UI.Settings.Refresh()
        end)
        timeoutButtons[#timeoutButtons + 1] = button
    end
    y = y + 36

    local weekNote
    weekNote, y = Body("This Week starts Monday at local midnight. A session stays open across character swaps and closes after the timeout above.", y, width)

    noticeCheck = Check("Mention newly discovered resources", 0, y, function(self)
        WarbandFYI_DB.config.resourceNotices = self:GetChecked() and true or false
    end)
    y = y + 32

    y = Heading("FYIs & REMINDERS", y + 4, width)

    local motto = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    motto:SetPoint("TOPLEFT", 0, -y)
    motto:SetText("WarbandFYI knows the context. You provide the content.")
    Color(motto, WBF.UI.Colors.cream)
    y = y + 24

    local explain
    explain, y = Body("An FYI is a trigger attached to existing Notebook content. Notes, checklists, resources and tracked items stay in the Notebook; the FYI simply surfaces that content when it becomes relevant.", y, width)

    fyiCheck = Check("Enable Notebook FYI reminders", 0, y, function(self)
        local enabled = self:GetChecked() and true or false
        if WBF.NotebookFyi and WBF.NotebookFyi.SetEnabled then
            WBF.NotebookFyi.SetEnabled(enabled)
        else
            WarbandFYI_DB.config.notebookFyi = enabled
        end
    end)
    y = y + 34

    Button("Manage FYIs", 100, 0, y, function()
        if WBF.UI.Fyi and WBF.UI.Fyi.OpenManage then
            WBF.UI.Fyi.OpenManage()
        end
    end)
    Button("Show active FYIs", 120, 108, y, function()
        local shown = WBF.UI.Fyi and WBF.UI.Fyi.ShowActiveEvents and WBF.UI.Fyi.ShowActiveEvents(true)
        if fyiStatus then
            fyiStatus:SetText(shown and "Active FYIs reopened." or "No active event FYIs right now.")
        end
    end)
    Button("Reset FYI popup", 116, 236, y, function()
        if WBF.UI.Fyi and WBF.UI.Fyi.ResetPopupPosition then
            WBF.UI.Fyi.ResetPopupPosition()
        end
        if fyiStatus then
            fyiStatus:SetText("FYI popup position reset.")
        end
    end)
    y = y + 30

    fyiStatus = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fyiStatus:SetPoint("TOPLEFT", 0, -y)
    fyiStatus:SetWidth(width)
    fyiStatus:SetJustifyH("LEFT")
    Color(fyiStatus, WBF.UI.Colors.gold)
    y = y + 20

    local how = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    how:SetPoint("TOPLEFT", 0, -y)
    how:SetText("Triggers")
    Color(how, WBF.UI.Colors.gold)
    y = y + 22

    local eventText
    eventText, y = Body("WoW Event — shows the attached Notebook section or node while a recognised Blizzard calendar event is active. The event provides timing only; WarbandFYI does not supply your task list.", y, width)
    local zoneText
    zoneText, y = Body("Zone — shows attached Notebook content when you enter the configured zone.", y, width)

    local behaviour = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    behaviour:SetPoint("TOPLEFT", 0, -y)
    behaviour:SetText("Checklist behaviour")
    Color(behaviour, WBF.UI.Colors.gold)
    y = y + 22
    local eachText
    eachText, y = Body("Each event — completion resets when the next occurrence begins.    Keep — completion remains until you change it.    Linked progress — reads a tracked item's live count, for example 5 / 12.", y, width)

    local popupHelp = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popupHelp:SetPoint("TOPLEFT", 0, -y)
    popupHelp:SetText("Popup controls")
    Color(popupHelp, WBF.UI.Colors.gold)
    y = y + 22
    local popupText
    popupText, y = Body("X dismisses the reminder for this session. Hide this occurrence suppresses it until the next event occurrence. Show active FYIs above (or /wbfyi fyi) brings currently relevant reminders back.", y, width)

    local eventsTitle = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    eventsTitle:SetPoint("TOPLEFT", 0, -y)
    eventsTitle:SetText("Recognised WoW events")
    Color(eventsTitle, WBF.UI.Colors.gold)
    y = y + 24

    local catalog = WBF.EventTriggers and WBF.EventTriggers.Catalog and WBF.EventTriggers.Catalog() or {}
    local rowHeight = 24
    local colWidth = 340
    for index = 1, #catalog do
        local info = catalog[index]
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local x = col * colWidth
        local yy = y + row * rowHeight
        local icon = root:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", x, -yy)
        local texture = WBF.EventTriggers and WBF.EventTriggers.Icon and WBF.EventTriggers.Icon(info.key) or nil
        icon:SetTexture(texture or "Interface\\Calendar\\UI-Calendar-Button")
        icon:SetTexCoord(0, 1, 0, 1)
        local label = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
        label:SetText(info.name)
        Color(label, WBF.UI.Colors.cream)
    end
    y = y + math.ceil(#catalog / 2) * rowHeight + 8

    local eventNote
    eventNote, y = Body("These names are event detection infrastructure, not built-in goals. Your Brewfest, Darkmoon Faire, or other tasks only come from what you put into the Notebook.", y, width)

    y = Heading("TRACKING & DATA", y + 4, width)

    resourceStatus = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resourceStatus:SetPoint("TOPLEFT", 0, -y)
    resourceStatus:SetWidth(width)
    resourceStatus:SetJustifyH("LEFT")
    resourceStatus:SetWordWrap(true)
    Color(resourceStatus, WBF.UI.Colors.muted)
    y = y + 30

    local limits
    limits, y = Body("WarbandFYI records meaningful game events rather than every low-level API change. Examples: pet battles record battles/captures/level-ups rather than every round; gathering counts nodes rather than every material; reputation records gains as they arrive; passive concentration regeneration is not activity.", y, width)

    y = Heading("DATA SAFETY & DIAGNOSTICS", y + 4, width)
    local safety
    safety, y = Body("0.2.0-dev keeps a full automatic pre-migration safety copy in WarbandFYI_Backup before changing the database schema. Configuration export below contains your Notebook, FYIs, settings, and custom resource/watchlist configuration without dumping all tracking history.", y, width)

    diagnosticsStatus = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    diagnosticsStatus:SetPoint("TOPLEFT", 0, -y)
    diagnosticsStatus:SetWidth(width)
    diagnosticsStatus:SetJustifyH("LEFT")
    diagnosticsStatus:SetWordWrap(true)
    Color(diagnosticsStatus, WBF.UI.Colors.cream)
    y = y + 48

    Button("Copy config backup", 142, 0, y, function()
        if WBF.Maintenance and WBF.Maintenance.ExportConfiguration then
            ShowCopyDialog("WarbandFYI Configuration Backup", WBF.Maintenance.ExportConfiguration())
        end
    end)
    Button("Copy diagnostics", 126, 150, y, function()
        if WBF.Maintenance and WBF.Maintenance.DiagnosticsText then
            ShowCopyDialog("WarbandFYI Diagnostics", WBF.Maintenance.DiagnosticsText())
        end
    end)
    Button("Refresh", 82, 284, y, function()
        WBF.UI.Settings.Refresh()
    end)
    y = y + 34

    local safetyNote
    safetyNote, y = Body("The configuration backup is intentionally copy-only in this development build. It gives you a human-readable recovery copy before we add import/restore controls later in the 0.2.0 cycle.", y, width)

    debugCheck = Check("Debug logging", 0, y, function(self)
        WarbandFYI_DB.config.debug = self:GetChecked() and true or false
    end)
    y = y + 34

    Button("Reset main window", 132, 0, y, ResetMainWindow)
    y = y + 34

    local commands
    commands, y = Body("Useful commands: /wbfyi opens WarbandFYI; /wbfyi fyi reopens active FYIs; /wbfyi notebook opens the Notebook. Debug commands remain available through /wbfyi debug for troubleshooting.", y, width)

    y = Heading("LEGACY", y + 4, width)
    legacyFyiCheck = Check("Legacy standalone FYI notices", 0, y, function(self)
        local enabled = self:GetChecked() and true or false
        if WBF.ContextFyi and WBF.ContextFyi.SetNoticesEnabled then
            WBF.ContextFyi.SetNoticesEnabled(enabled)
        else
            WarbandFYI_DB.config.contextFyiNotices = enabled
        end
    end)
    y = y + 30
    local legacy
    legacy, y = Body("Only affects FYIs created with the older separate FYI editor. New reminders should be attached directly to Notebook content.", y, width)

    root._settingsHeight = y + 24
end

function WBF.UI.Settings.Refresh()
    if not root then
        return
    end
    if debugCheck then
        debugCheck:SetChecked(WarbandFYI_DB.config.debug == true)
    end
    if noticeCheck then
        noticeCheck:SetChecked(WarbandFYI_DB.config.resourceNotices ~= false)
    end
    if fyiCheck then
        local enabled = WarbandFYI_DB.config.notebookFyi ~= false
        if WBF.NotebookFyi and WBF.NotebookFyi.Enabled then
            enabled = WBF.NotebookFyi.Enabled()
        end
        fyiCheck:SetChecked(enabled)
    end
    if legacyFyiCheck then
        local enabled = WarbandFYI_DB.config.contextFyiNotices ~= false
        if WBF.ContextFyi and WBF.ContextFyi.NoticesEnabled then
            enabled = WBF.ContextFyi.NoticesEnabled()
        end
        legacyFyiCheck:SetChecked(enabled)
    end
    if resourceStatus and WBF.Resources and WBF.Resources.Status then
        local status = WBF.Resources.Status()
        local fresh = "not yet"
        if status.lastScan and WBF.Format and WBF.Format.Ago then
            fresh = WBF.Format.Ago(status.lastScan)
        end
        resourceStatus:SetText("Warband resources: " .. (status.discovered or 0) .. " discovered, " .. (status.active or 0) .. " active recently. Last scan " .. fresh .. ".")
    end
    if diagnosticsStatus and WBF.Maintenance and WBF.Maintenance.Diagnostics then
        local d = WBF.Maintenance.Diagnostics()
        local size = WBF.Maintenance.HumanBytes and WBF.Maintenance.HumanBytes(d.approximateBytes) or tostring(d.approximateBytes or 0)
        local backup = d.migrationBackupAt and ("migration backup schema " .. tostring(d.migrationBackupFrom) .. " -> " .. tostring(d.migrationBackupTarget)) or "no migration backup needed yet"
        diagnosticsStatus:SetText("Schema " .. tostring(d.schemaVersion) .. " · approx " .. size .. " · " .. tostring(d.events) .. " events · " .. tostring(d.snapshots) .. " snapshots · " .. tostring(d.monthHistory) .. " month rollups · " .. backup .. ".")
    end
    local selected = WarbandFYI_DB.config.sessionTimeoutSeconds or 3600
    for index = 1, #timeoutButtons do
        local button = timeoutButtons[index]
        PaintTimeout(button, button.seconds == selected)
    end
end

function WBF.UI.Settings.HideCopy()
    if copyDialog then
        copyDialog:Hide()
    end
end

function WBF.UI.Settings.Height()
    return (root and root._settingsHeight) or 980
end
