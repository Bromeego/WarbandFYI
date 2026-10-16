local _, WBF = ...

WBF.UI.Plans = {}

local root
local titleText
local trackButton
local subtitleText
local addBox
local addPlaceholder
local suggestButton
local noticeText
local backButton
local planTitle
local renameButton
local archiveButton
local deleteButton
local descBox
local descPlaceholder
local objectiveText
local pickerLabel
local pickerBox
local pickerPlaceholder
local emptyText
local tabButtons = {}
local menu
local catcher
local menuButtons = {}

local selectedPlan = nil
local selectedTab = "overview"
local pickerOpen = false
local searchResults = {}
local searchGeneration = 0
local lastPickerText = nil
local armedZone = false
local editingID = nil
local linkEntryID = nil
local notice = nil
local pending = nil

local TABS = {
    { id = "overview", label = "Overview", width = 84 },
    { id = "achievements", label = "Achievements", width = 110 },
    { id = "tasks", label = "Tasks", width = 64 },
    { id = "notes", label = "Notes", width = 64 },
}

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

local function RefreshView()
    local frame = WBF.UI.frame
    if frame and frame.IsShown and frame:IsShown() and frame.Refresh then
        frame:Refresh(false)
    end
end

local function HideMenu()
    if menu then
        menu:Hide()
    end
    if catcher then
        catcher:Hide()
    end
end

local function Consume(text)
    if not pending then
        return
    end
    local fn = pending.onAccept
    pending = nil
    if fn then
        fn(text or "")
    end
end

local function PopupEditText(dialog)
    if not dialog then
        return ""
    end
    local box = dialog.editBox
    if not box and dialog.GetEditBox then
        box = dialog:GetEditBox()
    end
    if box and box.GetText then
        return box:GetText() or ""
    end
    if dialog.GetText and dialog.editBox == nil and dialog.GetParent then
        return dialog:GetText() or ""
    end
    return ""
end

local function Prompt(text, initial, onAccept, maxLetters)
    HideMenu()
    pending = {
        initial = initial or "",
        max = maxLetters or 80,
        onAccept = onAccept,
    }
    if StaticPopup_Show then
        StaticPopup_Show("WARBANDFYI_PLAN_TEXT", text)
    end
end

local function Confirm(text, onAccept)
    HideMenu()
    pending = { onAccept = onAccept }
    if StaticPopup_Show then
        StaticPopup_Show("WARBANDFYI_PLAN_DELETE", text)
    end
end

if type(StaticPopupDialogs) == "table" then
    StaticPopupDialogs["WARBANDFYI_PLAN_TEXT"] = {
        text = "%s",
        button1 = "Save",
        button2 = "Cancel",
        hasEditBox = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self)
            local box = self.editBox or (self.GetEditBox and self:GetEditBox())
            if box and pending then
                if box.SetMaxLetters then
                    box:SetMaxLetters(pending.max or 80)
                end
                box:SetText(pending.initial or "")
                if box.HighlightText then
                    box:HighlightText()
                end
                box:SetFocus()
            end
        end,
        OnAccept = function(self)
            Consume(PopupEditText(self))
        end,
        EditBoxOnEnterPressed = function(self)
            local text = ""
            if self.GetText then
                text = self:GetText() or ""
            else
                text = PopupEditText(self)
            end
            Consume(text)
            if StaticPopup_Hide then
                StaticPopup_Hide("WARBANDFYI_PLAN_TEXT")
            end
        end,
        OnCancel = function()
            pending = nil
        end,
    }

    StaticPopupDialogs["WARBANDFYI_PLAN_DELETE"] = {
        text = "%s",
        button1 = "Delete",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function()
            Consume("")
        end,
        OnCancel = function()
            pending = nil
        end,
    }
end

local function Characters()
    local list = {}
    if not WBF.Characters or not WBF.Characters.List then
        return list
    end
    local found = WBF.Characters.List()
    for index = 1, #found do
        list[#list + 1] = found[index]
    end
    table.sort(list, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return list
end

local function MenuButton(index)
    local button = menuButtons[index]
    if button then
        return button
    end
    button = CreateFrame("Button", nil, menu)
    button:SetHeight(20)
    button:RegisterForClicks("LeftButtonUp")
    WBF.UI.BindWheel(button)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 8, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    button.Label = label
    button:SetScript("OnClick", function(self)
        if self.Action then
            self.Action()
        end
    end)
    menuButtons[index] = button
    return button
end

local function ShowMenu(anchor, items)
    if not menu or not items or #items == 0 then
        HideMenu()
        return
    end
    local width = 210
    for index = 1, #menuButtons do
        menuButtons[index]:Hide()
    end
    for index = 1, #items do
        local item = items[index]
        local button = MenuButton(index)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -((index - 1) * 20) - 4)
        button:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -((index - 1) * 20) - 4)
        button.Label:SetText(Shown(item.label))
        if item.muted then
            button.Label:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
        else
            button.Label:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
        end
        button.Action = item.action
        button:Show()
    end
    menu:SetSize(width, #items * 20 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    catcher:Show()
    catcher:SetFrameLevel(80)
    menu:SetFrameLevel(90)
    menu:Show()
end

local OpenEntryMenu
local OpenPlanMenu

local function RowPool()
    return WBF.UI.Pool("planRow", function(parent)
        local row = CreateFrame("Button", nil, parent)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        WBF.UI.BindWheel(row)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.05)

        local box = CreateFrame("Button", nil, row)
        box:SetSize(14, 14)
        box:RegisterForClicks("LeftButtonUp")
        WBF.UI.BindWheel(box)
        local boxEdge = box:CreateTexture(nil, "BACKGROUND")
        boxEdge:SetAllPoints()
        boxEdge:SetColorTexture(WBF.UI.Colors.goldDim[1], WBF.UI.Colors.goldDim[2], WBF.UI.Colors.goldDim[3], 1)
        local boxFill = box:CreateTexture(nil, "BORDER")
        boxFill:SetPoint("TOPLEFT", 1, -1)
        boxFill:SetPoint("BOTTOMRIGHT", -1, 1)
        boxFill:SetColorTexture(0.04, 0.045, 0.06, 1)
        local boxMark = box:CreateTexture(nil, "ARTWORK")
        boxMark:SetPoint("TOPLEFT", 3, -3)
        boxMark:SetPoint("BOTTOMRIGHT", -3, 3)
        boxMark:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 1)
        box.Mark = boxMark

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)

        local more = CreateFrame("Button", nil, row)
        more:SetSize(28, 18)
        more:RegisterForClicks("LeftButtonUp")
        WBF.UI.BindWheel(more)
        local moreText = more:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        moreText:SetAllPoints()
        moreText:SetJustifyH("RIGHT")

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        local detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detail:SetJustifyH("LEFT")
        detail:SetWordWrap(false)
        detail:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

        row.Apply = function(self, data)
            data = data or {}
            local showCheck = data.check ~= nil
            local showIcon = not showCheck and data.icon ~= nil
            local showMore = data.button ~= nil
            box:ClearAllPoints()
            box:SetPoint("LEFT", 0, data.detail and 6 or 0)
            if showCheck then
                box:Show()
                box.Mark:SetShown(data.check == "on")
            else
                box:Hide()
            end
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", 0, data.detail and 6 or 0)
            if showIcon then
                icon:SetTexture(data.icon)
                icon:Show()
            else
                icon:Hide()
            end
            if showMore then
                more:Show()
                more:SetWidth(data.button == "Track" and 52 or 28)
                moreText:SetText(data.button == "Track" and "Track" or "...")
                moreText:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
            else
                more:Hide()
            end

            local left = 0
            if showCheck then
                left = 20
            elseif showIcon then
                left = 22
            end
            title:ClearAllPoints()
            detail:ClearAllPoints()
            more:ClearAllPoints()
            more:SetPoint("RIGHT", -2, 0)
            if data.detail and data.detail ~= "" then
                title:SetPoint("TOPLEFT", row, "TOPLEFT", left, -3)
                if showMore then
                    title:SetPoint("TOPRIGHT", more, "TOPLEFT", -6, -3)
                else
                    title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -3)
                end
                detail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, 3)
                if showMore then
                    detail:SetPoint("BOTTOMRIGHT", more, "BOTTOMLEFT", -6, 3)
                else
                    detail:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 3)
                end
                detail:SetText(Shown(data.detail))
                detail:Show()
            else
                title:SetPoint("LEFT", row, "LEFT", left, 0)
                if showMore then
                    title:SetPoint("RIGHT", more, "LEFT", -6, 0)
                else
                    title:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                end
                detail:Hide()
                detail:SetText("")
            end
            title:SetText(Shown(data.title or ""))
            if data.kind == "muted" or data.kind == "criterion" or data.muted then
                title:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
            else
                title:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
            end

            box:SetScript("OnClick", function()
                if data.id and (data.check == "on" or data.check == "off") then
                    WBF.Plans.ToggleComplete(data.id)
                end
            end)
            more:SetScript("OnClick", function()
                if data.button == "Track" and data.action then
                    data.action()
                elseif data.kind == "plan" then
                    OpenPlanMenu(data.id, more)
                elseif data.id then
                    OpenEntryMenu(data.id, more)
                end
            end)
            self:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    if data.kind == "plan" then
                        OpenPlanMenu(data.id, self)
                    elseif data.id and data.button == "..." then
                        OpenEntryMenu(data.id, self)
                    end
                    return
                end
                if data.kind == "plan" and data.id then
                    selectedPlan = data.id
                    selectedTab = "overview"
                    HideMenu()
                    RefreshView()
                elseif data.button == "Track" and data.action then
                    data.action()
                end
            end)
            self:SetScript("OnEnter", function(owner)
                if not data.title or data.title == "" then
                    return
                end
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                GameTooltip:SetText(Shown(data.title), 1, 0.82, 0.45)
                if data.detail and data.detail ~= "" then
                    GameTooltip:AddLine(Shown(data.detail), 0.75, 0.75, 0.75, true)
                end
                if data.tip and data.tip ~= "" then
                    GameTooltip:AddLine(Shown(data.tip), 0.9, 0.9, 0.9, true)
                end
                GameTooltip:Show()
            end)
            self:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
        return row
    end)
end

local function PlaceRow(data, y, width)
    local row = WBF.UI.Acquire(RowPool(), root)
    local height = 22
    if data.detail and data.detail ~= "" then
        height = 36
    end
    if data.kind == "muted" or data.kind == "criterion" then
        height = 18
    end
    local indent = data.indent or 0
    row:SetWidth(math.max(40, width - indent))
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", root, "TOPLEFT", indent, -y)
    row:Apply(data)
    return y + height
end

local function EntryRow(entry)
    local progress = nil
    if entry.type == "achievement" and WBF.PlanAchievements and WBF.PlanAchievements.Progress then
        progress = WBF.PlanAchievements.Progress(entry.achievementID)
    end
    local state = WBF.Plans.DisplayState(entry)
    local check = nil
    if (entry.type == "task" or entry.type == "recurring") and state ~= "archived" then
        check = (state == "completed" or state == "doneCycle") and "on" or "off"
    end
    local detail = WBF.Plans.StatusLine(entry)
    if entry.type == "achievement" and WBF.PlanAchievements and WBF.PlanAchievements.ProgressText then
        local progressText = WBF.PlanAchievements.ProgressText(progress)
        if progressText and detail then
            detail = progressText .. " · " .. detail
        elseif progressText then
            detail = progressText
        end
    end
    return {
        kind = "entry",
        id = entry.id,
        title = WBF.Plans.Title(entry, progress),
        detail = detail,
        tip = progress and progress.description or nil,
        check = check,
        icon = progress and progress.icon or nil,
        muted = state == "completed" or state == "archived",
        button = "...",
        criteria = progress and progress.kind == "criteria" and progress.criteria or nil,
    }
end

local function PlaceEntry(entry, y, width, showCriteria)
    local data = EntryRow(entry)
    y = PlaceRow(data, y, width)
    if showCriteria and data.criteria and WBF.PlanAchievements and WBF.PlanAchievements.CriterionText then
        local limit = math.min(6, #data.criteria)
        for index = 1, limit do
            y = PlaceRow({
                kind = "criterion",
                title = WBF.PlanAchievements.CriterionText(data.criteria[index]),
                indent = 22,
            }, y, width)
        end
        if #data.criteria > limit then
            y = PlaceRow({
                kind = "muted",
                title = "+" .. (#data.criteria - limit) .. " more",
                indent = 22,
            }, y, width)
        end
    end
    return y
end

local function PlanLine(group)
    local entries = WBF.Plans.InPlan(group.id)
    local objectives = {}
    for index = 1, #entries do
        local entry = entries[index]
        if entry.type ~= "note" then
            objectives[#objectives + 1] = entry
        end
    end
    if #objectives == 1 and objectives[1].type == "achievement" and WBF.PlanAchievements then
        local progress = WBF.PlanAchievements.Progress(objectives[1].achievementID)
        local text = WBF.PlanAchievements.ProgressText(progress)
        if text then
            return text
        end
    end
    if #objectives == 1 and objectives[1].type == "recurring" and WBF.Plans.DisplayState(objectives[1]) == "due" then
        return "Due"
    end
    local done, total = WBF.Plans.ObjectiveCount(group.id)
    if total > 0 then
        return done .. " / " .. total .. " objectives"
    end
    local notes = 0
    for index = 1, #entries do
        if entries[index].type == "note" then
            notes = notes + 1
        end
    end
    if notes > 0 then
        return notes == 1 and "1 note" or (notes .. " notes")
    end
    return nil
end

local function TrackResult(info)
    local id = info.id
    local zone = nil
    if armedZone then
        zone = WBF.Plans.SuggestedZone()
    end
    pickerOpen = false
    searchResults = {}
    if WBF.PlanAchievements and WBF.PlanAchievements.ClearSearch then
        WBF.PlanAchievements.ClearSearch()
    end
    local reason
    if linkEntryID then
        local entryID = linkEntryID
        linkEntryID = nil
        _, reason = WBF.Plans.LinkAchievement(entryID, id)
    else
        _, reason = WBF.Plans.AddAchievement(id, {
            planID = selectedPlan,
            zone = zone,
        })
    end
    if reason == "exists" then
        notice = "Already tracking that achievement."
    end
    RefreshView()
end

local function QueueSearch(text)
    searchGeneration = searchGeneration + 1
    local generation = searchGeneration
    local function run()
        if generation ~= searchGeneration or not pickerOpen then
            return
        end
        searchResults = WBF.PlanAchievements.Search(text)
        RefreshView()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, run)
    else
        run()
    end
end

function WBF.UI.Plans.OnSearchUpdated()
    if not pickerOpen or not WBF.PlanAchievements or not WBF.PlanAchievements.ReadLatest then
        return
    end
    searchResults = WBF.PlanAchievements.ReadLatest()
    RefreshView()
end

local function MenuItemsFor(page, entry)
    local items = {}
    local function add(label, action, muted)
        items[#items + 1] = { label = label, action = action, muted = muted }
    end
    local function back()
        add("Back", function()
            OpenEntryMenu(entry.id, menu.anchor, "root")
        end)
    end

    if page == "recurring" then
        add("Once", function()
            WBF.Plans.SetRecurring(entry.id, "once")
        end)
        add("Daily", function()
            WBF.Plans.SetRecurring(entry.id, "daily")
        end)
        add("Weekly", function()
            WBF.Plans.SetRecurring(entry.id, "weekly")
        end)
        add("Custom...", function()
            local id = entry.id
            Prompt("Repeat every how many days?", "7", function(text)
                local days = tonumber(text)
                if not days or days < 1 then
                    return
                end
                WBF.Plans.SetRecurring(id, "custom", days)
            end, 3)
        end)
        back()
        return items
    end

    if page == "character" then
        add("Warband", function()
            WBF.Plans.SetMeta(entry.id, { character = false })
        end)
        local people = Characters()
        local limit = math.min(24, #people)
        for index = 1, limit do
            local person = people[index]
            add(person.name or "Character", function()
                WBF.Plans.SetMeta(entry.id, { character = person.guid })
            end)
        end
        if #people > limit then
            add("Some characters are hidden", nil, true)
        end
        back()
        return items
    end

    if page == "plan" then
        if entry.planID then
            add("Remove from plan", function()
                WBF.Plans.AssignPlan(entry.id, nil)
            end)
        end
        local groups = WBF.Plans.Groups()
        for index = 1, #groups do
            local group = groups[index]
            if group.status ~= "archived" then
                add(group.name, function()
                    WBF.Plans.AssignPlan(entry.id, group.id)
                end)
            end
        end
        add("New plan...", function()
            local id = entry.id
            Prompt("Plan name", "", function(text)
                local group = WBF.Plans.CreateGroup(text)
                if not group then
                    return
                end
                selectedPlan = group.id
                selectedTab = "overview"
                WBF.Plans.AssignPlan(id, group.id)
            end, 80)
        end)
        back()
        return items
    end

    if page == "context" then
        local zone = WBF.Plans.SuggestedZone()
        if zone then
            add("Use zone: " .. zone, function()
                WBF.Plans.SetMeta(entry.id, { zone = zone })
            end)
        end
        add("Set zone...", function()
            local id = entry.id
            Prompt("Zone", entry.zone or "", function(text)
                WBF.Plans.SetMeta(id, { zone = Trim(text) == "" and false or text })
            end, 80)
        end)
        add("Set expansion...", function()
            local id = entry.id
            Prompt("Expansion", entry.expansion or "", function(text)
                WBF.Plans.SetMeta(id, { expansion = Trim(text) == "" and false or text })
            end, 80)
        end)
        add("Set category...", function()
            local id = entry.id
            Prompt("Category", entry.category or "", function(text)
                WBF.Plans.SetMeta(id, { category = Trim(text) == "" and false or text })
            end, 80)
        end)
        if entry.character or entry.zone or entry.expansion or entry.category then
            add("Clear context", function()
                WBF.Plans.SetMeta(entry.id, {
                    character = false,
                    zone = false,
                    expansion = false,
                    category = false,
                })
            end)
        end
        back()
        return items
    end

    if entry.type ~= "achievement" then
        add("Edit", function()
            editingID = entry.id
            HideMenu()
            addBox:SetText(entry.text or "")
            RefreshView()
            addBox:SetFocus()
        end)
    end
    if entry.type == "note" or entry.type == "recurring" then
        add("Convert to task", function()
            WBF.Plans.ConvertToTask(entry.id)
        end)
    end
    if entry.type ~= "achievement" then
        add("Make recurring", function()
            OpenEntryMenu(entry.id, menu.anchor, "recurring")
        end)
        add("Link achievement", function()
            linkEntryID = entry.id
            pickerOpen = true
            searchResults = {}
            HideMenu()
            RefreshView()
            if pickerBox then
                pickerBox:SetFocus()
            end
        end)
    end
    add("Assign character", function()
        OpenEntryMenu(entry.id, menu.anchor, "character")
    end)
    add("Add to plan", function()
        OpenEntryMenu(entry.id, menu.anchor, "plan")
    end)
    add("Context", function()
        OpenEntryMenu(entry.id, menu.anchor, "context")
    end)
    if entry.status == "archived" then
        add("Restore", function()
            WBF.Plans.Restore(entry.id)
        end)
    else
        add("Archive", function()
            WBF.Plans.Archive(entry.id)
        end)
    end
    add("Delete", function()
        local id = entry.id
        Confirm("Delete this reminder?", function()
            WBF.Plans.Delete(id)
        end)
    end)
    return items
end

OpenEntryMenu = function(entryID, anchor, page)
    local entry = WBF.Plans.Get(entryID)
    if not entry or not anchor then
        HideMenu()
        return
    end
    menu.anchor = anchor
    ShowMenu(anchor, MenuItemsFor(page or "root", entry))
end

OpenPlanMenu = function(groupID, anchor)
    local group = WBF.Plans.GetGroup(groupID)
    if not group or not anchor then
        HideMenu()
        return
    end
    local items = {
        {
            label = "Rename",
            action = function()
                local id = group.id
                Prompt("Rename plan", group.name, function(text)
                    WBF.Plans.RenameGroup(id, text)
                end, 80)
            end,
        },
        {
            label = group.status == "archived" and "Restore" or "Archive",
            action = function()
                if group.status == "archived" then
                    WBF.Plans.RestoreGroup(group.id)
                else
                    WBF.Plans.ArchiveGroup(group.id)
                end
            end,
        },
        {
            label = "Delete",
            action = function()
                local id = group.id
                Confirm("Delete this plan? Notes and tasks stay in Quick Notes.", function()
                    if selectedPlan == id then
                        selectedPlan = nil
                    end
                    WBF.Plans.DeleteGroup(id)
                end)
            end,
        },
    }
    ShowMenu(anchor, items)
end

local function TextButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 16)
    WBF.UI.BindWheel(button)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetAllPoints()
    text:SetJustifyH("LEFT")
    text:SetText(label)
    text:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    button.Label = text
    return button
end

function WBF.UI.Plans.Attach(parent)
    root = parent
    root:SetScript("OnHide", function()
        HideMenu()
        if pickerOpen and WBF.PlanAchievements and WBF.PlanAchievements.ClearSearch then
            WBF.PlanAchievements.ClearSearch()
        end
        pickerOpen = false
        searchResults = {}
        linkEntryID = nil
    end)

    titleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetJustifyH("LEFT")
    titleText:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    titleText:SetText("Plans & Notes")

    trackButton = TextButton(root, "Track Achievement", 140)
    trackButton.Label:SetJustifyH("RIGHT")
    trackButton:SetScript("OnClick", function()
        pickerOpen = not pickerOpen
        linkEntryID = nil
        searchResults = {}
        lastPickerText = nil
        if not pickerOpen and WBF.PlanAchievements and WBF.PlanAchievements.ClearSearch then
            WBF.PlanAchievements.ClearSearch()
        end
        RefreshView()
        if pickerOpen and pickerBox then
            local text = pickerBox:GetText() or ""
            if Trim(text) ~= "" then
                QueueSearch(text)
            end
            pickerBox:SetFocus()
        end
    end)

    subtitleText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleText:SetJustifyH("LEFT")
    subtitleText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    addBox = CreateFrame("EditBox", nil, root, "InputBoxTemplate")
    addBox:SetAutoFocus(false)
    addBox:SetHeight(22)
    addBox:SetFontObject(GameFontHighlightSmall)
    addBox:SetMaxLetters(400)
    if addBox.SetTextInsets then
        addBox:SetTextInsets(6, 6, 0, 0)
    end
    WBF.UI.BindWheel(addBox)
    addPlaceholder = addBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    addPlaceholder:SetPoint("LEFT", addBox, "LEFT", 8, 0)
    addPlaceholder:SetText("Add note or task...")
    addBox:SetScript("OnTextChanged", function(self)
        if Trim(self:GetText() or "") == "" then
            addPlaceholder:Show()
        else
            addPlaceholder:Hide()
            if notice then
                notice = nil
                noticeText:Hide()
            end
        end
    end)
    addBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText() or ""
        if editingID then
            local id = editingID
            if Trim(text) == "" then
                return
            end
            editingID = nil
            self:SetText("")
            self:ClearFocus()
            WBF.Plans.SetText(id, text)
            return
        end
        local zone = nil
        if armedZone then
            zone = WBF.Plans.SuggestedZone()
        end
        self:SetText("")
        WBF.Plans.Add({
            type = "note",
            text = text,
            planID = selectedPlan,
            zone = zone,
        })
    end)
    addBox:SetScript("OnEscapePressed", function(self)
        editingID = nil
        self:SetText("")
        self:ClearFocus()
    end)
    addBox:SetScript("OnEditFocusLost", function(self)
        if Trim(self:GetText() or "") == "" then
            editingID = nil
        end
    end)

    suggestButton = TextButton(root, "Suggested", 360)
    suggestButton:SetScript("OnClick", function()
        armedZone = not armedZone
        RefreshView()
    end)

    noticeText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noticeText:SetJustifyH("LEFT")
    noticeText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    backButton = TextButton(root, "< Plans & Notes", 160)
    backButton:SetScript("OnClick", function()
        selectedPlan = nil
        selectedTab = "overview"
        RefreshView()
    end)

    planTitle = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    planTitle:SetJustifyH("LEFT")
    planTitle:SetWordWrap(false)
    planTitle:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])

    renameButton = TextButton(root, "Rename", 52)
    archiveButton = TextButton(root, "Archive", 58)
    deleteButton = TextButton(root, "Delete", 48)
    renameButton:SetScript("OnClick", function()
        local id = selectedPlan
        local group = WBF.Plans.GetGroup(id)
        if not group then
            return
        end
        Prompt("Rename plan", group.name, function(text)
            WBF.Plans.RenameGroup(id, text)
        end, 80)
    end)
    archiveButton:SetScript("OnClick", function()
        local group = WBF.Plans.GetGroup(selectedPlan)
        if not group then
            return
        end
        if group.status == "archived" then
            WBF.Plans.RestoreGroup(group.id)
        else
            WBF.Plans.ArchiveGroup(group.id)
        end
    end)
    deleteButton:SetScript("OnClick", function()
        local id = selectedPlan
        Confirm("Delete this plan? Notes and tasks stay in Quick Notes.", function()
            if selectedPlan == id then
                selectedPlan = nil
            end
            WBF.Plans.DeleteGroup(id)
        end)
    end)

    descBox = CreateFrame("EditBox", nil, root, "InputBoxTemplate")
    descBox:SetAutoFocus(false)
    descBox:SetHeight(22)
    descBox:SetFontObject(GameFontHighlightSmall)
    descBox:SetMaxLetters(400)
    WBF.UI.BindWheel(descBox)
    descPlaceholder = descBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    descPlaceholder:SetPoint("LEFT", descBox, "LEFT", 8, 0)
    descPlaceholder:SetText("Description (optional)")
    descBox:SetScript("OnTextChanged", function(self)
        if Trim(self:GetText() or "") == "" then
            descPlaceholder:Show()
        else
            descPlaceholder:Hide()
        end
    end)
    descBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    descBox:SetScript("OnEditFocusLost", function(self)
        if selectedPlan then
            WBF.Plans.SetGroupDescription(selectedPlan, self:GetText() or "")
        end
    end)
    descBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    for index = 1, #TABS do
        local spec = TABS[index]
        local button = TextButton(root, spec.label, spec.width)
        button.tabId = spec.id
        button:SetScript("OnClick", function()
            selectedTab = spec.id
            RefreshView()
        end)
        tabButtons[index] = button
    end

    objectiveText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    objectiveText:SetJustifyH("LEFT")
    objectiveText:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])

    pickerLabel = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pickerLabel:SetJustifyH("LEFT")
    pickerLabel:SetText("Search by name or id")
    pickerLabel:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    pickerBox = CreateFrame("EditBox", nil, root, "InputBoxTemplate")
    pickerBox:SetAutoFocus(false)
    pickerBox:SetHeight(22)
    pickerBox:SetFontObject(GameFontHighlightSmall)
    pickerBox:SetMaxLetters(80)
    WBF.UI.BindWheel(pickerBox)
    pickerPlaceholder = pickerBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pickerPlaceholder:SetPoint("LEFT", pickerBox, "LEFT", 8, 0)
    pickerPlaceholder:SetText("Draenic Pet Battler")
    pickerBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if Trim(text) == "" then
            pickerPlaceholder:Show()
        else
            pickerPlaceholder:Hide()
        end
        if pickerOpen and text ~= lastPickerText then
            lastPickerText = text
            QueueSearch(text)
        else
            lastPickerText = text
        end
    end)
    pickerBox:SetScript("OnEnterPressed", function(self)
        searchResults = WBF.PlanAchievements.Search(self:GetText() or "")
        RefreshView()
    end)
    pickerBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        pickerOpen = false
        if WBF.PlanAchievements and WBF.PlanAchievements.ClearSearch then
            WBF.PlanAchievements.ClearSearch()
        end
        RefreshView()
    end)

    emptyText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetJustifyH("LEFT")
    emptyText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    emptyText:SetText("Nothing saved yet. Type a reminder and press Enter.")

    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    catcher:SetScript("OnClick", HideMenu)
    catcher:Hide()

    menu = CreateFrame("Frame", nil, catcher, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:Hide()
    WBF.UI.Paint(menu, WBF.UI.Colors.window, WBF.UI.Colors.goldDim)
    menu:SetScript("OnHide", function()
        if catcher then
            catcher:Hide()
        end
    end)
end

local function HideOptional()
    suggestButton:Hide()
    noticeText:Hide()
    backButton:Hide()
    planTitle:Hide()
    renameButton:Hide()
    archiveButton:Hide()
    deleteButton:Hide()
    if not descBox:HasFocus() then
        descBox:Hide()
    end
    objectiveText:Hide()
    if not pickerOpen then
        pickerLabel:Hide()
        pickerBox:Hide()
    end
    emptyText:Hide()
    for index = 1, #tabButtons do
        tabButtons[index]:Hide()
    end
end

local function PlaceEntryList(entries, y, width, showCriteria)
    if #entries == 0 then
        return PlaceRow({ kind = "muted", title = "None" }, y, width)
    end
    for index = 1, #entries do
        y = PlaceEntry(entries[index], y, width, showCriteria)
    end
    return y
end

function WBF.UI.Plans.Render(width)
    if WBF.PlanAchievements and WBF.PlanAchievements.InvalidateProgress then
        WBF.PlanAchievements.InvalidateProgress()
    end
    WBF.UI.ReleaseAll()
    HideMenu()
    HideOptional()

    if selectedPlan and not WBF.Plans.GetGroup(selectedPlan) then
        selectedPlan = nil
    end

    local y = 4
    local group = selectedPlan and WBF.Plans.GetGroup(selectedPlan) or nil

    if group then
        backButton:ClearAllPoints()
        backButton:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        backButton:Show()
        trackButton:ClearAllPoints()
        trackButton:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -y)
        trackButton:Show()
        y = y + 18

        deleteButton:ClearAllPoints()
        deleteButton:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -y)
        deleteButton:Show()
        archiveButton:ClearAllPoints()
        archiveButton:SetPoint("RIGHT", deleteButton, "LEFT", -8, 0)
        archiveButton.Label:SetText(group.status == "archived" and "Restore" or "Archive")
        archiveButton:Show()
        renameButton:ClearAllPoints()
        renameButton:SetPoint("RIGHT", archiveButton, "LEFT", -8, 0)
        renameButton:Show()
        planTitle:ClearAllPoints()
        planTitle:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        planTitle:SetPoint("TOPRIGHT", renameButton, "TOPLEFT", -8, 0)
        planTitle:SetText(Shown(group.name))
        planTitle:Show()
        y = y + 22

        if not descBox:HasFocus() then
            descBox:SetText(group.description or "")
        end
        descBox:ClearAllPoints()
        descBox:SetPoint("TOPLEFT", root, "TOPLEFT", 6, -y)
        descBox:SetPoint("TOPRIGHT", root, "TOPRIGHT", -4, -y)
        descBox:Show()
        if Trim(descBox:GetText() or "") == "" then
            descPlaceholder:Show()
        else
            descPlaceholder:Hide()
        end
        y = y + 28

        local x = 0
        for index = 1, #tabButtons do
            local button = tabButtons[index]
            local spec = TABS[index]
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
            button:Show()
            if spec.id == selectedTab then
                button.Label:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
            else
                button.Label:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
            end
            x = x + spec.width
        end
        y = y + 20
        titleText:Hide()
        subtitleText:Hide()
    else
        titleText:ClearAllPoints()
        titleText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        titleText:Show()
        trackButton:ClearAllPoints()
        trackButton:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -(y + 2))
        trackButton:Show()
        y = y + 22
        subtitleText:ClearAllPoints()
        subtitleText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        subtitleText:SetText("Things you want to come back to.")
        subtitleText:Show()
        if descBox:HasFocus() then
            descBox:ClearFocus()
        end
        descBox:Hide()
        y = y + 18
    end

    addPlaceholder:SetText(editingID and "Edit reminder..." or "Add note or task...")
    addBox:ClearAllPoints()
    addBox:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -y)
    addBox:SetPoint("TOPRIGHT", root, "TOPRIGHT", -8, -y)
    addBox:Show()
    if Trim(addBox:GetText() or "") == "" then
        addPlaceholder:Show()
    end
    y = y + 28

    local zone = WBF.Plans.SuggestedZone()
    if zone and not group then
        suggestButton.Label:SetText((armedZone and "Using: " or "Suggested: ") .. zone)
        if armedZone then
            suggestButton.Label:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
        else
            suggestButton.Label:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
        end
        suggestButton:ClearAllPoints()
        suggestButton:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        suggestButton:Show()
        y = y + 18
    end

    if notice then
        noticeText:ClearAllPoints()
        noticeText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        noticeText:SetText(Shown(notice))
        noticeText:Show()
        y = y + 16
    end

    if pickerOpen then
        pickerLabel:ClearAllPoints()
        pickerLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        pickerLabel:Show()
        y = y + 16
        pickerBox:ClearAllPoints()
        pickerBox:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -y)
        pickerBox:SetPoint("TOPRIGHT", root, "TOPRIGHT", -8, -y)
        pickerBox:Show()
        y = y + 26
        if #searchResults == 0 then
            local query = Trim(pickerBox:GetText() or "")
            if query ~= "" then
                y = PlaceRow({ kind = "muted", title = "No matches." }, y, width)
            end
        else
            for index = 1, #searchResults do
                local info = searchResults[index]
                y = PlaceRow({
                    kind = "search",
                    title = info.name,
                    detail = info.description,
                    icon = info.icon,
                    button = "Track",
                    action = function()
                        TrackResult(info)
                    end,
                }, y, width)
            end
        end
        y = y + 8
    end

    if group then
        local entries = WBF.Plans.InPlan(group.id)
        local achievements = {}
        local tasks = {}
        local notes = {}
        for index = 1, #entries do
            local entry = entries[index]
            if entry.type == "achievement" then
                achievements[#achievements + 1] = entry
            elseif entry.type == "task" or entry.type == "recurring" then
                tasks[#tasks + 1] = entry
            else
                notes[#notes + 1] = entry
            end
        end
        if selectedTab == "overview" then
            local done, total = WBF.Plans.ObjectiveCount(group.id)
            objectiveText:ClearAllPoints()
            objectiveText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
            if total > 0 then
                objectiveText:SetText(done .. " / " .. total .. " objectives complete")
            else
                objectiveText:SetText("No objectives yet")
            end
            objectiveText:Show()
            y = y + 20
            if #achievements > 0 then
                WBF.UI.AcquireSection(root, "Achievements", 0, y, width)
                y = y + 22
                y = PlaceEntryList(achievements, y, width, true)
                y = y + 8
            end
            if #tasks > 0 then
                WBF.UI.AcquireSection(root, "Tasks", 0, y, width)
                y = y + 22
                y = PlaceEntryList(tasks, y, width, false)
                y = y + 8
            end
            if #notes > 0 then
                WBF.UI.AcquireSection(root, "Notes", 0, y, width)
                y = y + 22
                y = PlaceEntryList(notes, y, width, false)
                y = y + 8
            end
            if #achievements == 0 and #tasks == 0 and #notes == 0 then
                emptyText:ClearAllPoints()
                emptyText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
                emptyText:SetText("Nothing in this plan yet.")
                emptyText:Show()
                y = y + 20
            end
        else
            local list = notes
            local showCriteria = false
            if selectedTab == "achievements" then
                list = achievements
                showCriteria = true
            elseif selectedTab == "tasks" then
                list = tasks
            end
            if #list == 0 then
                emptyText:ClearAllPoints()
                emptyText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
                emptyText:SetText("None in this tab.")
                emptyText:Show()
                y = y + 20
            else
                y = PlaceEntryList(list, y, width, showCriteria)
            end
        end
        return y + 12
    end

    local buckets = WBF.Plans.Buckets()
    local any = #buckets.due + #buckets.notes + #buckets.done + #buckets.plans + #buckets.donePlans > 0
    if not any then
        emptyText:ClearAllPoints()
        emptyText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        emptyText:Show()
        return y + 36
    end

    WBF.UI.AcquireSection(root, "Due / Reset Soon", 0, y, width)
    y = y + 22
    if #buckets.due == 0 then
        y = PlaceRow({ kind = "muted", title = "None" }, y, width)
    else
        for index = 1, #buckets.due do
            y = PlaceEntry(buckets.due[index], y, width, false)
        end
    end
    y = y + 10

    WBF.UI.AcquireSection(root, "Active", 0, y, width)
    y = y + 22
    if #buckets.plans == 0 and #buckets.notes == 0 then
        y = PlaceRow({ kind = "muted", title = "None" }, y, width)
    else
        for index = 1, #buckets.plans do
            local plan = buckets.plans[index]
            y = PlaceRow({
                kind = "plan",
                id = plan.id,
                title = plan.name,
                detail = PlanLine(plan),
                button = "...",
            }, y, width)
        end
        if #buckets.plans > 0 and #buckets.notes > 0 then
            y = y + 6
            WBF.UI.AcquireSection(root, "Quick Notes", 0, y, width)
            y = y + 22
        end
        for index = 1, #buckets.notes do
            y = PlaceEntry(buckets.notes[index], y, width, false)
        end
    end
    y = y + 10

    WBF.UI.AcquireSection(root, "Completed / Archived", 0, y, width)
    y = y + 22
    if #buckets.done == 0 and #buckets.donePlans == 0 then
        y = PlaceRow({ kind = "muted", title = "None" }, y, width)
    else
        for index = 1, #buckets.donePlans do
            local plan = buckets.donePlans[index]
            y = PlaceRow({
                kind = "plan",
                id = plan.id,
                title = plan.name,
                detail = "Archived",
                muted = true,
                button = "...",
            }, y, width)
        end
        for index = 1, #buckets.done do
            y = PlaceEntry(buckets.done[index], y, width, false)
        end
    end

    return y + 12
end

local summaryBlock

local function EnsureSummary(parent)
    if summaryBlock then
        summaryBlock:SetParent(parent)
        return summaryBlock
    end
    local block = CreateFrame("Button", nil, parent)
    block:RegisterForClicks("LeftButtonUp")
    WBF.UI.BindWheel(block)
    local highlight = block:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.04)
    local header = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 0, -2)
    header:SetText("PLANS")
    header:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    block.Header = header
    block.Lines = {}
    for index = 1, 3 do
        local label = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
        local value = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(false)
        value:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
        block.Lines[index] = { label = label, value = value }
    end
    local footer = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetJustifyH("LEFT")
    footer:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    block.Footer = footer
    block:SetScript("OnClick", function()
        if WBF.UI.frame and WBF.UI.frame.SetView then
            WBF.UI.frame:SetView("plans")
        end
    end)
    WBF.UI.Tooltip(block, function(tooltip)
        tooltip:SetText("Plans & Notes", 1, 0.82, 0.45)
        tooltip:AddLine("Open reminders.", 0.9, 0.9, 0.9)
    end)
    summaryBlock = block
    return block
end

function WBF.UI.Plans.DrawSummary(parent, y, width)
    if not WBF.Plans or not WBF.Plans.Summary then
        return y
    end
    local summary = WBF.Plans.Summary()
    if not summary or (summary.total or 0) < 1 then
        if summaryBlock then
            summaryBlock:Hide()
        end
        return y
    end
    local block = EnsureSummary(parent)
    local lineCount = #summary.lines
    local height = 20 + (lineCount * 16) + 16
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    block:SetSize(math.max(120, width), height)
    block:Show()
    local labelWidth = math.max(80, width - 120)
    for index = 1, 3 do
        local line = block.Lines[index]
        local data = summary.lines[index]
        if data then
            line.label:ClearAllPoints()
            line.label:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(18 + (index - 1) * 16))
            line.label:SetWidth(labelWidth)
            line.label:SetText(Shown(data.label))
            line.label:Show()
            line.value:ClearAllPoints()
            line.value:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -(18 + (index - 1) * 16))
            line.value:SetWidth(110)
            line.value:SetText(Shown(data.value or ""))
            line.value:Show()
        else
            line.label:Hide()
            line.value:Hide()
        end
    end
    local footer = summary.active .. " active"
    if summary.due > 0 then
        footer = footer .. " · " .. summary.due .. " due"
    end
    block.Footer:ClearAllPoints()
    block.Footer:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(18 + lineCount * 16))
    block.Footer:SetText(footer)
    return y + height + 8
end
