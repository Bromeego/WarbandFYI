local _, WBF = ...

WBF.UI.Navigation = {}

local ITEMS = {
    { id = "current", label = "Current Session", atlases = { "auctionhouse-icon-clock" }, fallback = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    { id = "last", label = "Last Session", atlases = { "UI-RefreshButton" }, fallback = "Interface\\Icons\\Spell_Holy_BorrowedTime" },
    { id = "today", label = "Today", atlases = { "questlog-questtypeicon-daily", "QuestNormal" }, fallback = "Interface\\Icons\\INV_Misc_Note_01" },
    { id = "week", label = "This Week", atlases = { "questlog-questtypeicon-weekly", "QuestNormal" }, fallback = "Interface\\Icons\\INV_Misc_Note_03" },
    { id = "month", label = "This Month", atlases = { "questlog-questtypeicon-campaign", "QuestNormal" }, fallback = "Interface\\Icons\\INV_Misc_Note_05" },
    { id = "sep" },
    { id = "warband", label = "Warband", atlases = { "warbands-icon", "warbands-charselect-icon" }, fallback = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend" },
    { id = "characters", label = "Characters", atlases = { "groupfinder-icon-friend" }, fallback = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
    { id = "resources", label = "Resources", atlases = { "auctionhouse-icon-coin" }, fallback = "Interface\\Icons\\INV_Misc_Coin_02" },
    { id = "activity", label = "Activity", atlases = { "QuestNormal" }, fallback = "Interface\\Icons\\INV_Misc_Book_09" },
    { id = "sep" },
    { id = "notebook", label = "Notebook", atlases = { "questlog-questtypeicon-story", "QuestNormal" }, fallback = "Interface\\Icons\\INV_Misc_Book_09" },
    { id = "hunts", label = "Collection Hunts", atlases = { "QuestNormal" }, fallback = "Interface\\Icons\\INV_Misc_Spyglass_03" },
}

local buttons = {}

local LABELS = {
    current = "Current Session",
    last = "Last Session",
    today = "Today",
    week = "This Week",
    month = "This Month",
    warband = "Warband",
    characters = "Characters",
    resources = "Resources",
    activity = "Activity",
    notebook = "Notebook",
    hunts = "Collection Hunts",
    settings = "Settings",
}

function WBF.UI.Navigation.LabelFor(view, monthOffset)
    if view == "month" and WBF.Aggregator and WBF.Aggregator.Range then
        local _, _, label = WBF.Aggregator.Range("month", monthOffset or 0)
        if label and label ~= "" then
            return label
        end
    end
    return LABELS[view] or "WarbandFYI"
end

local function PaintNav(button)
    if button.selected then
        button.Background:SetColorTexture(WBF.UI.Colors.blue[1], WBF.UI.Colors.blue[2], WBF.UI.Colors.blue[3], 0.95)
        button.Bar:Show()
        button.Label:SetTextColor(1, 0.95, 0.85)
        button.Icon:SetVertexColor(1, 0.9, 0.65)
    elseif button.hovered then
        button.Background:SetColorTexture(1, 1, 1, 0.06)
        button.Bar:Hide()
        button.Label:SetTextColor(0.9, 0.88, 0.82)
        button.Icon:SetVertexColor(0.85, 0.85, 0.88)
    else
        button.Background:SetColorTexture(0, 0, 0, 0)
        button.Bar:Hide()
        button.Label:SetTextColor(0.72, 0.74, 0.78)
        button.Icon:SetVertexColor(0.7, 0.72, 0.76)
    end
end

function WBF.UI.Navigation.Build(parent, onSelect)
    local y = 8
    for index = 1, #ITEMS do
        local item = ITEMS[index]
        if item.id == "sep" then
            local line = parent:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -y - 6)
            line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, -y - 6)
            line:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], 0.7)
            y = y + 16
        else
            local button = CreateFrame("Button", nil, parent)
            button:SetHeight(34)
            button:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -y)
            button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -y)
            button.viewId = item.id

            local background = button:CreateTexture(nil, "BACKGROUND")
            background:SetAllPoints()
            local bar = button:CreateTexture(nil, "ARTWORK")
            bar:SetWidth(3)
            bar:SetPoint("TOPLEFT", 0, -3)
            bar:SetPoint("BOTTOMLEFT", 0, 3)
            bar:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 1)
            bar:Hide()
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("LEFT", 10, 0)
            WBF.UI.SetAtlasChain(icon, item.atlases, item.fallback)
            local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            label:SetText(item.label)
            label:SetJustifyH("LEFT")

            button.Background = background
            button.Bar = bar
            button.Icon = icon
            button.Label = label
            button:SetScript("OnEnter", function(self)
                self.hovered = true
                PaintNav(self)
            end)
            button:SetScript("OnLeave", function(self)
                self.hovered = false
                PaintNav(self)
            end)
            button:SetScript("OnClick", function()
                onSelect(item.id)
            end)
            PaintNav(button)
            buttons[#buttons + 1] = button
            y = y + 36
        end
    end

    local version = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 16, 12)
    version:SetText("v" .. (WBF.VERSION or "0.1.2"))
end

function WBF.UI.Navigation.SetSelected(view)
    for index = 1, #buttons do
        local button = buttons[index]
        button.selected = button.viewId == view
        PaintNav(button)
    end
end
