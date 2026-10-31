local _, WBF = ...

WBF.UI.Notebook = {}

local root
local selectedPage = nil
local focusTarget = nil
local focusGeneration = 0
local query = ""
local searchGen = 0
local composer = nil
local wantFocus = false
local notice = nil
local pending = nil
local progressPending = nil

local homeTitle, homeSubtitle
local newPageButton, quickButton
local searchBox, searchPlaceholder
local backButton, pageTitleText, pageSummaryText, pageMore, pageFyiButton, editButton, emptyAdd
local titleBox, titlePlaceholder, summaryBox, summaryPlaceholder
local lineBox, linePlaceholder, areaHolder, areaBox
local saveButton, cancelButton, noticeText, measure
local menu, catcher
local menuButtons = {}

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

local function RefreshView(reset)
    local frame = WBF.UI.frame
    if frame and frame.IsShown and frame:IsShown() and frame.Refresh then
        frame:Refresh(reset and true or false)
    end
end

function WBF.UI.Notebook.ShowPage(pageId, focus)
    if not WBF.Notebook.GetPage(pageId) then
        return false
    end
    selectedPage = pageId
    composer = nil
    focusGeneration = focusGeneration + 1
    local generation = focusGeneration
    focusTarget = type(focus) == "table" and focus or nil
    if focusTarget then
        focusTarget._scrollRequested = nil
    end
    if WBF.Notebook.TouchOpened then
        WBF.Notebook.TouchOpened(pageId)
    end
    local frame = WBF.UI.frame
    if frame and frame.Show and frame.IsShown and not frame:IsShown() then
        frame:Show()
    end
    if frame and frame.SetView then
        frame:SetView("notebook")
    end
    if frame and frame.IsShown and frame:IsShown() and frame.Refresh then
        frame:Refresh(true)
    end
    -- Focus from search/FYI navigation is a temporary locator, not a permanent
    -- state.  Fade it back to the normal Notebook styling after a moment.
    if focusTarget and C_Timer and C_Timer.After then
        C_Timer.After(2.8, function()
            if generation ~= focusGeneration then
                return
            end
            focusTarget = nil
            RefreshView(false)
        end)
    end
    return true
end

function WBF.UI.Notebook.Note(text)
    notice = text
    RefreshView(false)
end

local function HideMenu()
    if menu then
        menu:Hide()
    end
    if catcher then
        catcher:Hide()
    end
end

local function ClearFocus()
    if searchBox then
        searchBox:ClearFocus()
    end
    if titleBox then
        titleBox:ClearFocus()
    end
    if summaryBox then
        summaryBox:ClearFocus()
    end
    if lineBox then
        lineBox:ClearFocus()
    end
    if areaBox then
        areaBox:ClearFocus()
    end
end

local function IndexOf(list, id)
    for index = 1, #list do
        if list[index].id == id then
            return index
        end
    end
    return nil
end

local function CountLabel(count)
    if count == 1 then
        return "1 block"
    end
    return tostring(count) .. " blocks"
end

local function Ago(timestamp)
    if WBF.Format and WBF.Format.Ago then
        return WBF.Format.Ago(timestamp)
    end
    return ""
end

local function Confirm(text, onAccept)
    HideMenu()
    pending = onAccept
    if StaticPopup_Show then
        StaticPopup_Show("WARBANDFYI_NOTEBOOK_DELETE", text)
    end
end

local function AchievementCopyName(block)
    local id = block and block.achievementID
    local progress = WBF.PlanAchievements and WBF.PlanAchievements.Progress and WBF.PlanAchievements.Progress(id) or nil
    local name = progress and progress.name or nil
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function CopyAchievementName(block)
    local name = AchievementCopyName(block)
    if not name or not StaticPopup_Show then
        return
    end
    HideMenu()
    StaticPopup_Show("WARBANDFYI_NOTEBOOK_COPY", nil, nil, name)
end

if type(StaticPopupDialogs) == "table" then
    StaticPopupDialogs["WARBANDFYI_NOTEBOOK_DELETE"] = {
        text = "%s",
        button1 = "Delete",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function()
            local fn = pending
            pending = nil
            if fn then
                fn()
            end
        end,
        OnCancel = function()
            pending = nil
        end,
    }
    StaticPopupDialogs["WARBANDFYI_NOTEBOOK_COPY"] = {
        text = "Ctrl+C to copy",
        button1 = "Close",
        hasEditBox = true,
        maxLetters = 255,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(dialog, data)
            local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
            if not box then
                return
            end
            box:SetText(type(data) == "string" and data or "")
            if WBF.UI.KeepKeyboard then
                WBF.UI.KeepKeyboard(box)
            end
            box:SetFocus()
            box:HighlightText()
        end,
    }
    StaticPopupDialogs["WARBANDFYI_NOTEBOOK_PROGRESS_TARGET"] = {
        text = "Target count for %s",
        button1 = "Link",
        button2 = "Cancel",
        hasEditBox = true,
        maxLetters = 9,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(dialog)
            local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
            if not box then
                return
            end
            if box.SetNumeric then
                box:SetNumeric(true)
            end
            local value = progressPending and tostring(progressPending.target or "") or ""
            box:SetText(value)
            if WBF.UI.KeepKeyboard then
                WBF.UI.KeepKeyboard(box)
            end

            local function FocusTargetBox()
                if not dialog:IsShown() or not box:IsShown() then
                    return
                end
                box:SetFocus()
                if value ~= "" then
                    box:HighlightText()
                elseif box.SetCursorPosition then
                    box:SetCursorPosition(0)
                end
            end

            -- StaticPopup can finish laying itself out after OnShow, and some UI
            -- skins will otherwise steal focus back from an empty edit box. Focus
            -- it now and again on the next frame so the caret is immediately visible.
            FocusTargetBox()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, FocusTargetBox)
            end
        end,
        OnAccept = function(dialog)
            local box = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
            local target = box and tonumber(box:GetText() or "") or nil
            local current = progressPending
            progressPending = nil
            if current and target and target >= 1 and target == math.floor(target) then
                WBF.Notebook.SetChecklistProgress(current.blockId, current.itemId, current.sourceBlockId, target)
            end
        end,
        OnCancel = function()
            progressPending = nil
        end,
    }
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
    WBF.UI.SetColor(highlight, WBF.UI.Colors.highlight)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 8, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    local detail = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail:SetPoint("BOTTOMLEFT", 8, 3)
    detail:SetPoint("BOTTOMRIGHT", -8, 3)
    detail:SetJustifyH("LEFT")
    detail:SetWordWrap(false)
    detail:Hide()
    button.Label = label
    button.Detail = detail
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
    for index = 1, #menuButtons do
        menuButtons[index]:Hide()
    end
    local tall = false
    for index = 1, #items do
        if items[index].detail then
            tall = true
            break
        end
    end
    local rowH = tall and 34 or 20
    local width = tall and 236 or 210
    for index = 1, #items do
        local item = items[index]
        local button = MenuButton(index)
        button:SetHeight(rowH)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -((index - 1) * rowH) - 4)
        button:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -((index - 1) * rowH) - 4)
        button.Label:ClearAllPoints()
        if item.detail then
            button.Label:SetPoint("TOPLEFT", 8, -3)
            button.Label:SetPoint("TOPRIGHT", -8, -3)
            button.Detail:SetText(Shown(item.detail))
            button.Detail:Show()
        else
            button.Label:SetPoint("LEFT", 8, 0)
            button.Label:SetPoint("RIGHT", -8, 0)
            button.Detail:Hide()
        end
        button.Label:SetText(Shown(item.label))
        if item.muted then
            Color(button.Label, WBF.UI.Colors.muted)
        else
            Color(button.Label, WBF.UI.Colors.cream)
        end
        button.Action = item.muted and nil or item.action
        button:Show()
    end
    menu:SetSize(width, #items * rowH + 8)
    menu:ClearAllPoints()
    menu:SetClampedToScreen(true)
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    catcher:Show()
    catcher:SetFrameLevel(80)
    menu:SetFrameLevel(90)
    menu:Show()
    local bottom = menu:GetBottom()
    if bottom and bottom < 12 then
        menu:ClearAllPoints()
        menu:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
    end
    local left = menu:GetLeft()
    if left and left < 12 then
        local _, _, relativePoint = menu:GetPoint(1)
        menu:ClearAllPoints()
        if type(relativePoint) == "string" and relativePoint:find("TOP", 1, true) then
            menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
        else
            menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        end
    end
end

local function Begin(nextComposer, reset)
    composer = nextComposer
    wantFocus = true
    notice = nil
    HideMenu()
    RefreshView(reset)
end

function WBF.UI.Notebook.OpenNote(noteId)
    local note = WBF.Notebook and WBF.Notebook.GetNote and WBF.Notebook.GetNote(noteId) or nil
    if not note then
        return false
    end
    selectedPage = nil
    local frame = WBF.UI.frame
    if frame and frame.SetView then
        frame:SetView("notebook")
    end
    Begin({ kind = "note-edit", noteId = note.id, draft = note.text or "" }, true)
    return true
end

local function Cancel()
    composer = nil
    notice = nil
    ClearFocus()
    RefreshView(false)
end

local function Commit()
    if not composer then
        return
    end
    local kind = composer.kind
    local function fail(message)
        notice = message
        RefreshView(false)
    end
    if kind == "page-new" or kind == "page-edit" then
        local title = titleBox:GetText() or ""
        local summary = summaryBox:GetText() or ""
        if Trim(title) == "" then
            fail("Add a title first.")
            return
        end
        if kind == "page-new" then
            composer = nil
            local page = WBF.Notebook.CreatePage(title, summary)
            if not page then
                composer = { kind = "page-new", draft = title, summary = summary }
                fail("Couldn't add that page.")
                return
            end
            selectedPage = page.id
            ClearFocus()
            RefreshView(true)
            return
        end
        local pageId = composer.pageId
        composer = nil
        if not WBF.Notebook.SetPage(pageId, title, summary) then
            composer = { kind = "page-edit", pageId = pageId, draft = title, summary = summary }
            fail("Couldn't save that page.")
            return
        end
        ClearFocus()
        RefreshView(false)
        return
    end

    local text
    if areaHolder:IsShown() then
        text = areaBox:GetText() or ""
    else
        text = lineBox:GetText() or ""
    end
    if kind == "item-new" and Trim(text) == "" then
        return
    end
    if kind ~= "item-edit" and Trim(text) == "" then
        fail("Write something first.")
        return
    end

    if kind == "note-new" then
        composer = nil
        if not WBF.Notebook.AddQuickNote(text) then
            composer = { kind = "note-new", draft = text }
            fail("Couldn't save that note.")
            return
        end
    elseif kind == "note-edit" then
        local noteId = composer.noteId
        composer = nil
        if not WBF.Notebook.SetQuickNote(noteId, text) then
            composer = { kind = "note-edit", noteId = noteId, draft = text }
            fail("Couldn't save that note.")
            return
        end
    elseif kind == "section-new" then
        local pageId = composer.pageId
        local afterId = composer.afterId
        composer = nil
        if not WBF.Notebook.CreateSection(pageId, text, afterId) then
            composer = { kind = "section-new", pageId = pageId, afterId = afterId, draft = text }
            fail("Couldn't add that section.")
            return
        end
    elseif kind == "section-rename" then
        local sectionId = composer.sectionId
        composer = nil
        if not WBF.Notebook.RenameSection(sectionId, text) then
            composer = { kind = "section-rename", sectionId = sectionId, draft = text }
            fail("Couldn't rename that section.")
            return
        end
    elseif kind == "list-rename" then
        local blockId = composer.blockId
        composer = nil
        if not WBF.Notebook.RenamePetLevelList(blockId, text) then
            composer = { kind = "list-rename", blockId = blockId, draft = text }
            fail("Couldn't rename that list.")
            return
        end
    elseif kind == "text-new" or kind == "check-new" then
        local pageId = composer.pageId
        local sectionId = composer.sectionId
        composer = nil
        if not sectionId then
            local section = WBF.Notebook.CreateSection(pageId, "Notes")
            sectionId = section and section.id or nil
        end
        local block = nil
        if sectionId and kind == "text-new" then
            block = WBF.Notebook.AddText(sectionId, text)
        elseif sectionId then
            block = WBF.Notebook.AddChecklist(sectionId, text)
        end
        if not block then
            composer = { kind = kind, pageId = pageId, sectionId = sectionId, draft = text }
            fail("Couldn't add that.")
            return
        end
        if kind == "check-new" then
            composer = { kind = "item-new", blockId = block.id, draft = "" }
            wantFocus = true
            RefreshView(false)
            return
        end
    elseif kind == "text-edit" then
        local blockId = composer.blockId
        composer = nil
        if not WBF.Notebook.SetText(blockId, text) then
            composer = { kind = "text-edit", blockId = blockId, draft = text }
            fail("Couldn't save that note.")
            return
        end
    elseif kind == "item-new" then
        local blockId = composer.blockId
        composer = nil
        local _, outcome = WBF.Notebook.ChecklistCapture(blockId, text)
        if outcome == "blank" then
            composer = { kind = "item-new", blockId = blockId, draft = "" }
            wantFocus = true
            return
        end
        if outcome ~= "next" then
            composer = { kind = "item-new", blockId = blockId, draft = text }
            fail("Couldn't add that item.")
            return
        end
        composer = { kind = "item-new", blockId = blockId, draft = "" }
        wantFocus = true
        RefreshView(false)
        return
    elseif kind == "item-edit" then
        local blockId = composer.blockId
        local itemId = composer.itemId
        composer = nil
        WBF.Notebook.SetChecklistItem(blockId, itemId, text)
    end
    ClearFocus()
    RefreshView(false)
end

local function BlockDeleteLabel(block)
    local title = nil
    if block.type == "text" or block.type == "reference" or block.type == "waypoint" then
        title = block.text or block.label or block.zone
    elseif block.type == "checklist" then
        local items = WBF.Notebook.ChecklistItems(block)
        title = items[1] and items[1].text or nil
    elseif block.type == "achievement" then
        local info = WBF.PlanAchievements and WBF.PlanAchievements.Info and WBF.PlanAchievements.Info(block.achievementID) or nil
        title = info and info.name or nil
    elseif block.type == "resource" then
        local view = WBF.Resources and WBF.Resources.NotebookView and WBF.Resources.NotebookView(block.resourceKey) or nil
        title = (view and view.name) or block.resourceKey
    elseif block.type == "pet_level_list" then
        title = block.title
    end
    return WBF.Notebook.DeleteLabel(block.type, title)
end

local OpenPageMenu
local OpenSectionMenu
local OpenBlockMenu
local OpenNoteMenu
local OpenAddMenu

local function AddFyi(add, kind, id)
    local existing = WBF.NotebookFyi and WBF.NotebookFyi.ForTarget(kind, id) or nil
    add(existing and "Edit FYI..." or "Show as FYI...", function()
        HideMenu()
        if WBF.UI.Fyi and WBF.UI.Fyi.OpenSetup then
            WBF.UI.Fyi.OpenSetup(kind, id)
        end
    end)
    if existing then
        add(existing.enabled == false and "Enable FYI" or "Disable FYI", function()
            HideMenu()
            WBF.NotebookFyi.SetTriggerEnabled(existing.id, existing.enabled == false)
            if WBF.Notebook and WBF.Notebook.RefreshOpen then
                WBF.Notebook.RefreshOpen()
            end
        end)
        add("Remove FYI", function()
            HideMenu()
            WBF.NotebookFyi.RemoveTarget(kind, id)
            if WBF.Notebook and WBF.Notebook.RefreshOpen then
                WBF.Notebook.RefreshOpen()
            end
        end)
    end
end

local function ChecklistProgressSources(block)
    local list = {}
    if not block or not WBF.Notebook or not WBF.Notebook.Blocks then
        return list
    end
    local blocks = WBF.Notebook.Blocks(block.sectionId)
    for index = 1, #blocks do
        local source = blocks[index]
        if source.type == "reference" and source.refType == "item" and tonumber(source.refID) then
            if WBF.NotebookSmart and WBF.NotebookSmart.Prepare then
                WBF.NotebookSmart.Prepare(source)
            end
            local described = WBF.NotebookSmart and WBF.NotebookSmart.Describe and WBF.NotebookSmart.Describe(source) or nil
            local counts = WBF.NotebookSmart and WBF.NotebookSmart.ItemCounts and WBF.NotebookSmart.ItemCounts(source.refID) or nil
            list[#list + 1] = {
                kind = "item",
                block = source,
                title = described and described.title or source.label or "Tracked item",
                count = counts and (counts.combined or counts.character or 0) or 0,
                detail = "Item",
            }
        elseif source.type == "resource" and type(source.resourceKey) == "string" then
            local view = WBF.Resources and WBF.Resources.NotebookView and WBF.Resources.NotebookView(source.resourceKey) or nil
            if view then
                local count = tonumber(view.amount) or 0
                local detail = "Currency / resource"
                if view.character ~= nil and tonumber(view.character) ~= count then
                    detail = detail .. "  ·  You " .. tostring(view.character) .. "  ·  Warband " .. tostring(count)
                else
                    detail = detail .. "  ·  Current " .. tostring(count)
                end
                list[#list + 1] = {
                    kind = "resource",
                    block = source,
                    title = view.name or source.resourceKey or "Tracked resource",
                    count = count,
                    detail = detail,
                }
            end
        end
    end
    return list
end

local function PromptChecklistProgress(block, item, source)
    if not block or not item or not source or not StaticPopup_Show then
        return
    end
    local existing = type(item.progress) == "table" and item.progress or nil
    local defaultTarget = existing and tonumber(existing.target) or nil
    local title = nil
    if source.type == "resource" then
        local view = WBF.Resources and WBF.Resources.NotebookView and WBF.Resources.NotebookView(source.resourceKey) or nil
        title = view and view.name or source.resourceKey
    else
        local described = WBF.NotebookSmart and WBF.NotebookSmart.Describe and WBF.NotebookSmart.Describe(source) or nil
        title = described and described.title or nil
    end
    progressPending = {
        blockId = block.id,
        itemId = item.id,
        sourceBlockId = source.id,
        target = defaultTarget,
    }
    StaticPopup_Show("WARBANDFYI_NOTEBOOK_PROGRESS_TARGET", title or "tracked progress")
end

local function OpenChecklistProgressMenu(block, item, anchor)
    if not block or not item or not anchor then
        return
    end
    local sources = ChecklistProgressSources(block)
    local items = {}
    for index = 1, #sources do
        local source = sources[index]
        local sourceBlock = source.block
        local sourceTitle = source.title
        local sourceCount = source.count
        local linked = type(item.progress) == "table" and item.progress.kind == source.kind and item.progress.blockId == sourceBlock.id
        local sourceDetail = source.detail or (source.kind == "resource" and "Currency / resource" or "Item")
        items[#items + 1] = {
            label = (linked and "Linked: " or "Link: ") .. tostring(sourceTitle),
            detail = sourceDetail .. "  ·  Current " .. tostring(sourceCount) .. (linked and ("  ·  target " .. tostring(item.progress.target or "?")) or ""),
            action = function()
                HideMenu()
                PromptChecklistProgress(block, item, sourceBlock)
            end,
        }
    end
    if #sources == 0 then
        items[#items + 1] = {
            label = "No tracked items or resources in this section",
            detail = "Use + Add > Item or add a tracked currency/resource first, then link it here.",
            muted = true,
        }
    end
    if type(item.progress) == "table" then
        items[#items + 1] = {
            label = "Unlink progress",
            action = function()
                HideMenu()
                WBF.Notebook.ClearChecklistProgress(block.id, item.id)
            end,
        }
    end
    ShowMenu(anchor, items)
end

local function MoveActions(list, id, move, add)
    local index = IndexOf(list, id) or 1
    add("Move Up", function()
        move(id, -1)
    end, index == 1)
    add("Move Down", function()
        move(id, 1)
    end, index == #list)
end

OpenPageMenu = function(pageId, anchor)
    local page = WBF.Notebook.GetPage(pageId)
    if not page or not anchor then
        HideMenu()
        return
    end
    local items = {
        {
            label = "Open as Sheet",
            action = function()
                HideMenu()
                if WBF.UI.Sheet then
                    WBF.UI.Sheet.OpenPage(pageId)
                end
            end,
        },
    }
    local function add(label, action, muted)
        items[#items + 1] = { label = label, action = action, muted = muted }
    end
    local pageFyi = WBF.NotebookFyi and WBF.NotebookFyi.ForTarget and WBF.NotebookFyi.ForTarget("page", pageId) or nil
    if pageFyi then
        AddFyi(add, "page", pageId)
    end
    add("Edit", function()
        selectedPage = pageId
        Begin({
            kind = "page-edit",
            pageId = pageId,
            draft = page.title or "",
            summary = page.summary or "",
        }, true)
    end)
    add(page.pinned and "Unpin" or "Pin", function()
        WBF.Notebook.SetPinned(pageId, not page.pinned)
    end)
    add("Delete", function()
        Confirm(WBF.Notebook.DeleteLabel("page", page.title), function()
            if selectedPage == pageId then
                selectedPage = nil
                composer = nil
            end
            WBF.Notebook.DeletePage(pageId)
        end)
    end)
    ShowMenu(anchor, items)
end

OpenSectionMenu = function(sectionId, anchor)
    local section = WBF.Notebook.GetSection(sectionId)
    if not section or not anchor then
        HideMenu()
        return
    end
    local sections = WBF.Notebook.Sections(section.pageId)
    local items = {}
    local function add(label, action, muted)
        items[#items + 1] = { label = label, action = action, muted = muted }
    end
    add("Open as Sheet", function()
        HideMenu()
        if WBF.UI.Sheet then
            WBF.UI.Sheet.OpenSection(sectionId)
        end
    end)
    AddFyi(add, "section", sectionId)
    add("Rename", function()
        Begin({ kind = "section-rename", sectionId = sectionId, draft = section.title or "" }, false)
    end)
    add(section.collapsed and "Expand" or "Collapse", function()
        WBF.Notebook.SetCollapsed(sectionId, not section.collapsed)
    end)
    MoveActions(sections, sectionId, WBF.Notebook.MoveSection, add)
    add("Delete", function()
        Confirm(WBF.Notebook.DeleteLabel("section", section.title), function()
            WBF.Notebook.DeleteSection(sectionId)
        end)
    end)
    ShowMenu(anchor, items)
end

OpenBlockMenu = function(blockId, anchor)
    local block = WBF.Notebook.GetBlock(blockId)
    local section = block and WBF.Notebook.GetSection(block.sectionId) or nil
    if not block or not section or not anchor then
        HideMenu()
        return
    end
    local blocks = WBF.Notebook.Blocks(section.id)
    local items = {}
    local function add(label, action, muted)
        items[#items + 1] = { label = label, action = action, muted = muted }
    end
    if block.type == "achievement" then
        add("Copy name", function()
            CopyAchievementName(block)
        end)
    end
    if block.type == "text" then
        add("Edit", function()
            Begin({ kind = "text-edit", blockId = blockId, draft = block.text or "" }, false)
        end)
    elseif block.type == "checklist" then
        add("Add item", function()
            Begin({ kind = "item-new", blockId = blockId, draft = "" }, false)
        end)
    elseif block.type == "pet_level_list" then
        add("Rename", function()
            Begin({ kind = "list-rename", blockId = blockId, draft = block.title or "" }, false)
        end)
        add("Add pet", function()
            if WBF.UI.NotebookPets then WBF.UI.NotebookPets.Open(block.id) end
        end)
    elseif block.type == "waypoint" then
        add("Edit", function()
            HideMenu()
            if WBF.UI.NotebookAdd and WBF.UI.NotebookAdd.Open then
                WBF.UI.NotebookAdd.Open("waypoint", section.pageId, section.id, block)
            end
        end)
    end
    if block.type == "text" or block.type == "checklist" or block.type == "achievement" or block.type == "waypoint" or block.type == "resource" or block.type == "reference" or block.type == "pet_level_list" then
        add("Duplicate", function()
            WBF.Notebook.DuplicateBlock(blockId)
        end)
    end
    MoveActions(blocks, blockId, WBF.Notebook.MoveBlock, add)
    AddFyi(add, "block", blockId)
    add("Delete", function()
        Confirm(BlockDeleteLabel(block), function()
            WBF.Notebook.DeleteBlock(blockId)
        end)
    end)
    ShowMenu(anchor, items)
end

OpenNoteMenu = function(noteId, anchor, page)
    local note = WBF.Notebook.GetNote(noteId)
    if not note or not anchor then
        HideMenu()
        return
    end
    page = page or "root"
    local items = {}
    local function add(label, action, muted)
        items[#items + 1] = { label = label, action = action, muted = muted }
    end
    local function back(target)
        add("Back", function()
            OpenNoteMenu(noteId, anchor, target or "root")
        end)
    end
    if page == "file" then
        local pages = WBF.Notebook.Pages()
        if #pages == 0 then
            add("Create a page first", nil, true)
        end
        local limit = math.min(24, #pages)
        for index = 1, limit do
            local candidate = pages[index]
            add(candidate.title or "Page", function()
                OpenNoteMenu(noteId, anchor, "page:" .. candidate.id)
            end)
        end
        if #pages > limit then
            add("Some pages are hidden", nil, true)
        end
        back("root")
        ShowMenu(anchor, items)
        return
    end
    local filed = page:match("^page:(.+)$")
    if filed then
        local sections = WBF.Notebook.Sections(filed)
        if #sections == 0 then
            add("Notes", function()
                local section = WBF.Notebook.CreateSection(filed, "Notes")
                if section then
                    WBF.Notebook.FileQuickNote(noteId, section.id)
                end
            end)
        else
            for index = 1, #sections do
                local section = sections[index]
                add(section.title or "Section", function()
                    WBF.Notebook.FileQuickNote(noteId, section.id)
                end)
            end
        end
        back("file")
        ShowMenu(anchor, items)
        return
    end
    add("Edit", function()
        Begin({ kind = "note-edit", noteId = noteId, draft = note.text or "" }, true)
    end)
    add("Move to page", function()
        OpenNoteMenu(noteId, anchor, "file")
    end)
    MoveActions(WBF.Notebook.QuickNotes(), noteId, WBF.Notebook.MoveQuickNote, add)
    add("Delete", function()
        Confirm(WBF.Notebook.DeleteLabel("note", note.text), function()
            WBF.Notebook.DeleteQuickNote(noteId)
        end)
    end)
    ShowMenu(anchor, items)
end

OpenAddMenu = function(anchor, sectionId)
    if not anchor or not selectedPage then
        HideMenu()
        return
    end
    local pageId = selectedPage
    ShowMenu(anchor, {
        {
            label = "Text",
            detail = "A note",
            action = function()
                Begin({ kind = "text-new", pageId = pageId, sectionId = sectionId, draft = "" }, false)
            end,
        },
        {
            label = "Checklist",
            detail = "A list of checks",
            action = function()
                Begin({ kind = "check-new", pageId = pageId, sectionId = sectionId, draft = "" }, false)
            end,
        },
        {
            label = "Pet Level List",
            detail = "Live levels from your Pet Journal",
            action = function()
                HideMenu()
                local targetSection = sectionId
                if not targetSection then
                    local section = WBF.Notebook.CreateSection(pageId, "Notes")
                    targetSection = section and section.id or nil
                end
                local block = targetSection and WBF.Notebook.AddPetLevelList(targetSection, "Pets to Level") or nil
                if block and WBF.UI.NotebookPets and WBF.UI.NotebookPets.Open then
                    WBF.UI.NotebookPets.Open(block.id)
                end
            end,
        },
        {
            label = "Achievement",
            detail = "Track an achievement",
            action = function()
                HideMenu()
                if WBF.UI.NotebookAdd then
                    WBF.UI.NotebookAdd.Open("achievement", pageId, sectionId)
                end
            end,
        },
        {
            label = "Waypoint",
            detail = "A map location",
            action = function()
                HideMenu()
                if WBF.UI.NotebookAdd then
                    WBF.UI.NotebookAdd.Open("waypoint", pageId, sectionId)
                end
            end,
        },
        {
            label = "Link / Wowhead",
            detail = "Paste a link",
            action = function()
                HideMenu()
                if WBF.UI.NotebookAdd then
                    WBF.UI.NotebookAdd.Open("link", pageId, sectionId)
                end
            end,
        },
        {
            label = "Item",
            detail = "Track an item count",
            action = function()
                HideMenu()
                if WBF.UI.NotebookAdd then
                    WBF.UI.NotebookAdd.Open("item", pageId, sectionId)
                end
            end,
        },
        {
            label = "Resource",
            detail = "A tracked currency",
            action = function()
                HideMenu()
                if WBF.UI.NotebookAdd then
                    WBF.UI.NotebookAdd.Open("resource", pageId, sectionId)
                end
            end,
        },
        {
            label = "Section",
            detail = "A new section",
            action = function()
                Begin({ kind = "section-new", pageId = pageId, afterId = sectionId, draft = "" }, false)
            end,
        },
    })
end

local function MoreButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(28, 18)
    button:RegisterForClicks("LeftButtonUp")
    WBF.UI.BindWheel(button)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetAllPoints()
    label:SetJustifyH("RIGHT")
    label:SetText("...")
    Color(label, WBF.UI.Colors.gold)
    button.Label = label
    return button
end

local function HeadingPool()
    return WBF.UI.Pool("notebookHeading", function(parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetHeight(20)
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", 0, 0)
        Color(text, WBF.UI.Colors.gold)
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], WBF.UI.Colors.line[4])
        local link = CreateFrame("Button", nil, frame)
        link:SetSize(88, 18)
        link:SetPoint("RIGHT", 0, 0)
        WBF.UI.BindWheel(link)
        local linkText = link:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        linkText:SetAllPoints()
        linkText:SetJustifyH("RIGHT")
        Color(linkText, WBF.UI.Colors.gold)
        frame.Text = text
        frame.Line = line
        frame.Link = link
        frame.LinkText = linkText
        return frame
    end)
end

local function MutedPool()
    return WBF.UI.Pool("notebookMuted", function(parent)
        local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetJustifyH("LEFT")
        Color(text, WBF.UI.Colors.muted)
        return text
    end)
end

local function CardPool(name)
    return WBF.UI.Pool(name, function(parent)
        local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
        frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        WBF.UI.BindWheel(frame)
        local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        WBF.UI.SetColor(highlight, WBF.UI.Colors.highlight)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetJustifyH("LEFT")
        title:SetWordWrap(true)
        if title.SetMaxLines then
            title:SetMaxLines(2)
        end
        local detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detail:SetJustifyH("LEFT")
        detail:SetWordWrap(true)
        if detail.SetMaxLines then
            detail:SetMaxLines(2)
        end
        Color(detail, WBF.UI.Colors.muted)
        local meta = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        meta:SetJustifyH("RIGHT")
        Color(meta, WBF.UI.Colors.gold)
        frame.More = MoreButton(frame)
        frame.Title = title
        frame.Detail = detail
        frame.Meta = meta
        return frame
    end)
end

local function SectionBoxPool()
    return WBF.UI.Pool("notebookSectionBox", function(parent)
        local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        return frame
    end)
end

local function SectionHeadPool()
    return WBF.UI.Pool("notebookSectionHead", function(parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetHeight(22)
        local arrow = CreateFrame("Button", nil, frame)
        arrow:SetSize(16, 18)
        arrow:SetPoint("LEFT", 0, 0)
        WBF.UI.BindWheel(arrow)
        local arrowText = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        arrowText:SetAllPoints()
        arrowText:SetJustifyH("LEFT")
        Color(arrowText, WBF.UI.Colors.gold)
        local title = CreateFrame("Button", nil, frame)
        title:SetHeight(18)
        WBF.UI.BindWheel(title)
        local titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetAllPoints()
        titleText:SetJustifyH("LEFT")
        titleText:SetWordWrap(false)
        Color(titleText, WBF.UI.Colors.gold)
        local add = CreateFrame("Button", nil, frame)
        add:SetSize(52, 18)
        add:SetPoint("RIGHT", 0, 0)
        WBF.UI.BindWheel(add)
        local addText = add:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        addText:SetAllPoints()
        addText:SetJustifyH("RIGHT")
        addText:SetText("+ Add")
        Color(addText, WBF.UI.Colors.gold)

        local more = MoreButton(frame)
        more:SetPoint("RIGHT", add, "LEFT", -2, 0)

        local fyi = CreateFrame("Button", nil, frame)
        fyi:SetSize(100, 30)
        fyi:SetPoint("RIGHT", more, "LEFT", -4, 0)
        WBF.UI.BindWheel(fyi)
        local fyiIcon = fyi:CreateTexture(nil, "ARTWORK")
        fyiIcon:SetSize(28, 28)
        fyiIcon:SetPoint("LEFT", 0, 0)
        fyiIcon:Hide()
        local fyiText = fyi:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fyiText:SetPoint("LEFT", 0, 0)
        fyiText:SetPoint("RIGHT", 0, 0)
        fyiText:SetJustifyH("RIGHT")
        fyiText:SetText("FYI")
        Color(fyiText, WBF.UI.Colors.gold)
        fyi:Hide()

        title:SetPoint("LEFT", arrow, "RIGHT", 2, 0)
        title:SetPoint("RIGHT", more, "LEFT", -6, 0)
        frame.Arrow = arrow
        frame.ArrowText = arrowText
        frame.Title = title
        frame.TitleText = titleText
        frame.Add = add
        frame.More = more
        frame.Fyi = fyi
        frame.FyiIcon = fyiIcon
        frame.FyiText = fyiText
        return frame
    end)
end

local function BlockPool()
    return WBF.UI.Pool("notebookBlock", function(parent)
        local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        frame:EnableMouse(true)
        WBF.UI.BindWheel(frame)
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        Color(text, WBF.UI.Colors.cream)
        local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetJustifyH("LEFT")
        Color(sub, WBF.UI.Colors.muted)
        frame.More = MoreButton(frame)
        frame.Fyi = CreateFrame("Button", nil, frame)
        frame.Fyi:SetSize(26, 26)
        WBF.UI.BindWheel(frame.Fyi)
        frame.Fyi.Icon = frame.Fyi:CreateTexture(nil, "ARTWORK")
        frame.Fyi.Icon:SetAllPoints()
        frame.Fyi:Hide()
        frame.Text = text
        frame.Sub = sub
        frame.Icon = frame:CreateTexture(nil, "ARTWORK")
        frame.Icon:SetSize(16, 16)
        local bar = frame:CreateTexture(nil, "BACKGROUND")
        bar:SetColorTexture(WBF.UI.Colors.track[1], WBF.UI.Colors.track[2], WBF.UI.Colors.track[3], WBF.UI.Colors.track[4])
        bar:Hide()
        local fill = frame:CreateTexture(nil, "ARTWORK")
        fill:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 1)
        fill:Hide()
        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetJustifyH("LEFT")
        hint:Hide()
        local copy = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        copy:SetJustifyH("LEFT")
        copy:Hide()
        local link = WBF.UI.EditBox(frame, nil, 18)
        link:SetFontObject(GameFontHighlightSmall)
        link:Hide()
        WBF.UI.BindWheel(link)
        link:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        link:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
        link:SetScript("OnTextChanged", function(self)
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
        frame.Bar = bar
        frame.Fill = fill
        frame.Hint = hint
        frame.Copy = copy
        frame.Link = link
        frame.Criteria, frame.CriteriaToggle = WBF.UI.MakeCriteriaWidgets(frame)
        return frame
    end)
end

local function CheckPool()
    return WBF.UI.Pool("notebookCheck", function(parent)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(20)
        row:EnableMouse(true)
        WBF.UI.BindWheel(row)
        local focus = row:CreateTexture(nil, "BACKGROUND")
        focus:SetAllPoints()
        focus:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 0.10)
        focus:Hide()
        local box = CreateFrame("Button", nil, row)
        box:SetSize(14, 14)
        box:SetPoint("LEFT", 8, 0)
        box:RegisterForClicks("LeftButtonUp")
        WBF.UI.BindWheel(box)
        local edge = box:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints()
        edge:SetColorTexture(WBF.UI.Colors.goldDim[1], WBF.UI.Colors.goldDim[2], WBF.UI.Colors.goldDim[3], 1)
        local fill = box:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(WBF.UI.Colors.well[1], WBF.UI.Colors.well[2], WBF.UI.Colors.well[3], WBF.UI.Colors.well[4])
        local mark = box:CreateTexture(nil, "ARTWORK")
        mark:SetPoint("TOPLEFT", 3, -3)
        mark:SetPoint("BOTTOMRIGHT", -3, 3)
        mark:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 1)
        local mode = CreateFrame("Button", nil, row, "BackdropTemplate")
        mode:SetSize(70, 18)
        mode:SetPoint("RIGHT", -4, 0)
        WBF.UI.BindWheel(mode)
        local modeText = mode:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        modeText:SetAllPoints()
        modeText:SetJustifyH("RIGHT")
        Color(modeText, WBF.UI.Colors.muted)
        mode.Text = modeText
        mode:Hide()

        local edit = CreateFrame("Button", nil, row)
        edit:SetSize(36, 18)
        edit:RegisterForClicks("LeftButtonUp")
        WBF.UI.BindWheel(edit)
        local editText = edit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        editText:SetAllPoints()
        editText:SetJustifyH("RIGHT")
        editText:SetText("Edit")
        Color(editText, WBF.UI.Colors.gold)
        edit:Hide()

        local progress = CreateFrame("Button", nil, row)
        progress:SetSize(82, 18)
        progress:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        WBF.UI.BindWheel(progress)
        local progressText = progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        progressText:SetAllPoints()
        progressText:SetJustifyH("RIGHT")
        Color(progressText, WBF.UI.Colors.gold)
        progress.Text = progressText
        progress:Hide()

        local label = CreateFrame("Button", nil, row)
        label:SetPoint("LEFT", box, "RIGHT", 6, 0)
        label:SetPoint("RIGHT", -4, 0)
        label:SetHeight(18)
        label:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        WBF.UI.BindWheel(label)
        local text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetAllPoints()
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        row.Box = box
        row.Mark = mark
        row.Label = label
        row.Text = text
        row.Mode = mode
        row.Edit = edit
        row.Progress = progress
        row.Focus = focus

        local function showEdit()
            if row._editable then
                row.Edit:Show()
                row.Progress:Show()
            end
        end
        local function maybeHideEdit()
            local function check()
                if not row:IsShown() then
                    return
                end
                if MouseIsOver and MouseIsOver(row) then
                    return
                end
                row.Edit:Hide()
                if not row._linkedProgress then
                    row.Progress:Hide()
                end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0.04, check)
            else
                check()
            end
        end
        for _, widget in ipairs({ row, box, label, mode, edit, progress }) do
            widget:HookScript("OnEnter", showEdit)
            widget:HookScript("OnLeave", maybeHideEdit)
        end
        return row
    end)
end

local function AddItemPool()
    return WBF.UI.Pool("notebookAddItem", function(parent)
        local button = CreateFrame("Button", nil, parent)
        button:SetHeight(18)
        button:RegisterForClicks("LeftButtonUp")
        WBF.UI.BindWheel(button)
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", 8, 0)
        text:SetJustifyH("LEFT")
        text:SetText("+ Add item")
        Color(text, WBF.UI.Colors.gold)
        return button
    end)
end

local function PlaceHeading(title, y, width, linkLabel, onClick)
    local frame = WBF.UI.Acquire(HeadingPool(), root)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    frame:SetWidth(width)
    frame.Text:SetText(title)
    frame.Line:ClearAllPoints()
    frame.Line:SetPoint("LEFT", frame.Text, "RIGHT", 10, 0)
    frame.Line:SetHeight(1)
    if linkLabel then
        frame.LinkText:SetText(linkLabel)
        frame.Link:SetScript("OnClick", onClick)
        frame.Link:Show()
        frame.Line:SetPoint("RIGHT", frame.Link, "LEFT", -8, 0)
    else
        frame.Link:Hide()
        frame.Line:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    end
    return y + 24
end

local function MutedLine(text, x, y, width)
    local line = WBF.UI.Acquire(MutedPool(), root)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    line:SetWidth(math.max(40, width))
    line:SetText(Shown(text))
    return y + 18
end

local function WrappedHeight(text, width)
    if not measure then
        return 14
    end
    measure:SetWidth(math.max(20, width))
    measure:SetText(text or "")
    local height = measure:GetStringHeight() or 0
    if height < 8 then
        local per = math.max(12, math.floor(math.max(20, width) / 6.5))
        local lines = math.max(1, math.ceil(math.max(1, #(text or "")) / per))
        height = lines * 14
    end
    return height
end

local function HideEditors()
    titleBox:Hide()
    summaryBox:Hide()
    lineBox:Hide()
    areaHolder:Hide()
    saveButton:Hide()
    cancelButton:Hide()
end

local function FillBox(box, placeholder, text)
    if wantFocus or not box:HasFocus() then
        local current = box:GetText() or ""
        if current ~= (text or "") then
            box:SetText(text or "")
        end
    end
    local shown = Trim(box:GetText() or "") == ""
    placeholder:SetShown(shown)
end

local function PlaceActions(x, y)
    saveButton:ClearAllPoints()
    saveButton:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    saveButton:Show()
    cancelButton:ClearAllPoints()
    cancelButton:SetPoint("TOPLEFT", saveButton, "TOPRIGHT", 8, 0)
    cancelButton:Show()
end

local function ShowTitleBoxes(draft, summary, x, y, width)
    titleBox:ClearAllPoints()
    titleBox:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    titleBox:SetWidth(math.max(80, width))
    titleBox:SetMaxLetters(80)
    titlePlaceholder:SetText("Title")
    FillBox(titleBox, titlePlaceholder, draft)
    titleBox:Show()
    y = y + 28
    summaryBox:ClearAllPoints()
    summaryBox:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    summaryBox:SetWidth(math.max(80, width))
    summaryBox:SetMaxLetters(160)
    summaryPlaceholder:SetText("Description (optional)")
    FillBox(summaryBox, summaryPlaceholder, summary)
    summaryBox:Show()
    y = y + 28
    PlaceActions(x, y)
    return y + 24
end

local function ShowLineEditor(draft, placeholder, maxLetters, x, y, width)
    lineBox:ClearAllPoints()
    lineBox:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    lineBox:SetWidth(math.max(80, width))
    lineBox:SetMaxLetters(maxLetters or 800)
    linePlaceholder:SetText(placeholder or "")
    FillBox(lineBox, linePlaceholder, draft)
    lineBox:Show()
    y = y + 30
    PlaceActions(x, y)
    return y + 24
end

local function ShowAreaEditor(draft, x, y, width)
    areaHolder:ClearAllPoints()
    areaHolder:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    areaHolder:SetSize(math.max(80, width), 72)
    areaHolder:Show()
    if wantFocus or not areaBox:HasFocus() then
        local current = areaBox:GetText() or ""
        if current ~= (draft or "") then
            areaBox:SetText(draft or "")
        end
    end
    y = y + 80
    PlaceActions(x, y)
    return y + 24
end

local function PaintCard(frame)
    WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    frame:SetFrameLevel(root:GetFrameLevel() + 2)
end

local function BindTip(frame, title, body)
    frame:SetScript("OnEnter", function(owner)
        if not title or title == "" then
            return
        end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(Shown(title), 1, 0.82, 0.45)
        if body and body ~= "" and body ~= title then
            WBF.UI.AddTip(GameTooltip, Shown(body), WBF.UI.Colors.tipText, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function PlacePinned(page, x, y, width, height)
    local card = WBF.UI.Acquire(CardPool("notebookPin"), root)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    card:SetSize(width, height)
    PaintCard(card)
    card.More:ClearAllPoints()
    card.More:SetPoint("TOPRIGHT", -6, -6)
    card.Title:ClearAllPoints()
    card.Title:SetPoint("TOPLEFT", 10, -8)
    card.Title:SetPoint("TOPRIGHT", card.More, "TOPLEFT", -6, -8)
    card.Title:SetText(Shown(page.title))
    Color(card.Title, WBF.UI.Colors.cream)
    card.Detail:ClearAllPoints()
    card.Detail:SetPoint("TOPLEFT", 10, -30)
    card.Detail:SetPoint("TOPRIGHT", -10, -30)
    card.Detail:SetText(Shown(page.summary or ""))
    card.Detail:SetShown(page.summary ~= nil and page.summary ~= "")
    card.Meta:ClearAllPoints()
    card.Meta:SetPoint("BOTTOMLEFT", 10, 8)
    card.Meta:SetText(CountLabel(WBF.Notebook.BlockCount(page.id)))
    card.Meta:Show()
    card.More:SetScript("OnClick", function()
        OpenPageMenu(page.id, card.More)
    end)
    card:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            OpenPageMenu(page.id, card)
            return
        end
        WBF.UI.Notebook.ShowPage(page.id)
    end)
    BindTip(card, page.title, page.summary)
end

local function PlaceRecent(page, y, width)
    local height = (page.summary and page.summary ~= "") and 48 or 32
    local card = WBF.UI.Acquire(CardPool("notebookRecent"), root)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    card:SetSize(width, height)
    PaintCard(card)
    card.More:ClearAllPoints()
    card.More:SetPoint("RIGHT", -8, 0)
    card.Meta:ClearAllPoints()
    card.Meta:SetPoint("RIGHT", card.More, "LEFT", -8, 0)
    local seenAt = page.updatedAt or 0
    if type(page.openedAt) == "number" and page.openedAt > seenAt then
        seenAt = page.openedAt
    end
    local updated = Ago(seenAt)
    local meta = CountLabel(WBF.Notebook.BlockCount(page.id))
    if updated ~= "" then
        meta = meta .. " · " .. updated
    end
    card.Meta:SetWidth(168)
    card.Meta:SetWordWrap(false)
    card.Meta:SetText(meta)
    card.Meta:Show()
    card.Title:ClearAllPoints()
    card.Title:SetPoint("LEFT", 10, height > 36 and 8 or 0)
    card.Title:SetPoint("RIGHT", card.Meta, "LEFT", -8, 0)
    if card.Title.SetMaxLines then
        card.Title:SetMaxLines(1)
    end
    card.Title:SetText(Shown(page.title))
    Color(card.Title, WBF.UI.Colors.cream)
    card.Detail:ClearAllPoints()
    card.Detail:SetPoint("BOTTOMLEFT", 10, 6)
    card.Detail:SetPoint("BOTTOMRIGHT", card.Meta, "BOTTOMLEFT", -8, 6)
    card.Detail:SetText(Shown(page.summary or ""))
    card.Detail:SetShown(height > 36)
    card.More:SetScript("OnClick", function()
        OpenPageMenu(page.id, card.More)
    end)
    card:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            OpenPageMenu(page.id, card)
            return
        end
        WBF.UI.Notebook.ShowPage(page.id)
    end)
    BindTip(card, page.title, page.summary)
    return y + height + 6
end

local function PlaceNote(note, x, y, width, height)
    local card = WBF.UI.Acquire(CardPool("notebookNote"), root)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    card:SetSize(width, height)
    PaintCard(card)
    card.More:ClearAllPoints()
    card.More:SetPoint("TOPRIGHT", -6, -6)
    card.Title:ClearAllPoints()
    card.Title:SetPoint("TOPLEFT", 10, -8)
    card.Title:SetPoint("TOPRIGHT", card.More, "TOPLEFT", -6, 0)
    if card.Title.SetMaxLines then
        card.Title:SetMaxLines(3)
    end
    card.Title:SetText(Shown(note.text))
    Color(card.Title, WBF.UI.Colors.cream)
    card.Detail:Hide()
    card.Meta:ClearAllPoints()
    card.Meta:SetPoint("BOTTOMLEFT", 10, 8)
    card.Meta:SetText(Ago(note.updatedAt or note.createdAt))
    card.Meta:Show()
    card.More:SetScript("OnClick", function()
        OpenNoteMenu(note.id, card.More, "root")
    end)
    card:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            OpenNoteMenu(note.id, card, "root")
            return
        end
        Begin({ kind = "note-edit", noteId = note.id, draft = note.text or "" }, true)
    end)
    BindTip(card, note.text, nil)
end

local function Grid(list, y, width, height, draw)
    if #list == 0 then
        return y
    end
    local gap = 8
    local cols = math.floor((width + gap) / 208)
    if cols < 1 then
        cols = 1
    elseif cols > 3 then
        cols = 3
    end
    local cardW = math.floor((width - gap * (cols - 1)) / cols)
    for index = 1, #list do
        local col = (index - 1) % cols
        local row = math.floor((index - 1) / cols)
        draw(list[index], col * (cardW + gap), y + row * (height + gap), cardW, height)
    end
    local rows = math.ceil(#list / cols)
    return y + rows * height + (rows - 1) * gap
end

local function PlaceHit(hit, y, width)
    local card = WBF.UI.Acquire(CardPool("notebookHit"), root)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    card:SetSize(width, 40)
    PaintCard(card)
    card.More:Hide()
    card.Title:ClearAllPoints()
    card.Title:SetPoint("TOPLEFT", 10, -6)
    card.Title:SetPoint("TOPRIGHT", -10, -6)
    if card.Title.SetMaxLines then
        card.Title:SetMaxLines(1)
    end
    card.Title:SetText(Shown(hit.title or "Note"))
    Color(card.Title, WBF.UI.Colors.cream)
    card.Detail:ClearAllPoints()
    card.Detail:SetPoint("BOTTOMLEFT", 10, 6)
    card.Detail:SetPoint("BOTTOMRIGHT", -10, 6)
    card.Detail:SetWordWrap(false)
    if card.Detail.SetMaxLines then
        card.Detail:SetMaxLines(1)
    end
    card.Detail:SetText(Shown(hit.detail or ""))
    card.Detail:SetShown(hit.detail ~= nil and hit.detail ~= "")
    card.Meta:Hide()
    card:SetScript("OnClick", function()
        if hit.kind == "note" and hit.noteId then
            local note = WBF.Notebook.GetNote(hit.noteId)
            if note then
                Begin({ kind = "note-edit", noteId = note.id, draft = note.text or "" }, true)
            end
            return
        end
        if hit.pageId then
            WBF.UI.Notebook.ShowPage(hit.pageId, {
                sectionId = hit.sectionId,
                blockId = hit.blockId,
            })
        end
    end)
    return y + 46
end

local function ShowCopyField(frame, url, y, width)
    frame.Link._url = url
    frame.Link._lock = true
    frame.Link:SetText(url)
    frame.Link._lock = false
    frame.Link:ClearAllPoints()
    frame.Link:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -y)
    frame.Link:SetWidth(math.max(40, width - 24))
    frame.Link:Show()
    frame.Copy:ClearAllPoints()
    frame.Copy:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(y + 18))
    frame.Copy:SetText("Ctrl+C to copy")
    Color(frame.Copy, WBF.UI.Colors.muted)
    frame.Copy:Show()
    return y + 34
end

local function DrawSmart(frame, block, width)
    local kind = block.type
    if kind ~= "achievement" and kind ~= "waypoint" and kind ~= "resource" and kind ~= "reference" then
        return nil
    end
    local textX = 8
    frame.Icon:SetSize(28, 28)
    if kind == "achievement" then
        local progress = WBF.PlanAchievements and WBF.PlanAchievements.Progress and WBF.PlanAchievements.Progress(block.achievementID) or nil
        local name = (progress and progress.name) or ("Achievement " .. tostring(block.achievementID or ""))
        local description = progress and progress.description or nil
        if progress and progress.icon then
            frame.Icon:SetTexture(progress.icon)
            frame.Icon:ClearAllPoints()
            frame.Icon:SetPoint("TOPLEFT", 8, -8)
            frame.Icon:Show()
            textX = 44
        end
        local textW = math.max(20, width - textX - (frame._rightReserve or 28))
        frame.Text:ClearAllPoints()
        frame.Text:SetPoint("TOPLEFT", textX, -8)
        frame.Text:SetWidth(textW)
        if frame.Text.SetMaxLines then
            frame.Text:SetMaxLines(2)
        end
        frame.Text:SetText(Shown(name))
        Color(frame.Text, WBF.UI.Colors.cream)
        local y = 26
        if description and description ~= "" then
            frame.Sub:ClearAllPoints()
            frame.Sub:SetPoint("TOPLEFT", textX, -26)
            frame.Sub:SetWidth(textW)
            frame.Sub:SetWordWrap(true)
            if frame.Sub.SetMaxLines then
                frame.Sub:SetMaxLines(2)
            end
            frame.Sub:SetText(Shown(description))
            frame.Sub:Show()
            y = 26 + math.min(28, WrappedHeight(description, textW)) + 2
        end
        local line = progress and WBF.PlanAchievements.ProgressText and WBF.PlanAchievements.ProgressText(progress) or nil
        if line then
            frame.Hint:ClearAllPoints()
            frame.Hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -y)
            frame.Hint:SetWidth(math.max(20, width - 16))
            frame.Hint:SetText(Shown(line))
            Color(frame.Hint, WBF.UI.Colors.muted)
            frame.Hint:Show()
            y = y + 16
        end
        local percent = progress and progress.percent or nil
        if percent and progress.required then
            local barW = math.max(20, width - 16)
            frame.Bar:ClearAllPoints()
            frame.Bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -y)
            frame.Bar:SetSize(barW, 6)
            frame.Bar:Show()
            local fillW = math.max(1, math.floor(barW * math.max(0, math.min(100, percent)) / 100))
            frame.Fill:ClearAllPoints()
            frame.Fill:SetPoint("TOPLEFT", frame.Bar, "TOPLEFT", 0, 0)
            frame.Fill:SetSize(fillW, 6)
            frame.Fill:Show()
            y = y + 12
        end
        if progress and WBF.PlanAchievements.CriteriaDetail and frame.Criteria then
            local detail = WBF.PlanAchievements.CriteriaDetail(progress, WBF.PlanAchievements.CriteriaExpanded(block.achievementID))
            y = WBF.UI.PlaceCriteriaDetail(frame, frame.Criteria, frame.CriteriaToggle, detail, 8, y + 2, math.max(20, width - 16), function()
                WBF.PlanAchievements.ToggleCriteria(block.achievementID)
                if WBF.Notebook and WBF.Notebook.RefreshOpen then
                    WBF.Notebook.RefreshOpen()
                end
            end)
        end
        if type(block.sourceURL) == "string" and block.sourceURL ~= "" then
            y = ShowCopyField(frame, block.sourceURL, y + 4, width)
        end
        local height = math.max(44, y + 8)
        frame:SetSize(width, height)
        frame:SetScript("OnEnter", function(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(Shown(name), 1, 0.82, 0.45)
            if line then
                WBF.UI.AddTip(GameTooltip, Shown(line), WBF.UI.Colors.tipText, true)
            end
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        frame:SetScript("OnMouseUp", function(self, button)
            if button ~= "RightButton" or (self.More and self.More:IsMouseOver()) then
                return
            end
            OpenBlockMenu(block.id, self)
        end)
        return height
    end
    if kind == "waypoint" then
        local titled = type(block.label) == "string" and block.label ~= ""
        local title = titled and block.label or block.zone or "Waypoint"
        local detail
        if titled and WBF.NotebookSmart and WBF.NotebookSmart.PlaceLine then
            detail = WBF.NotebookSmart.PlaceLine(block)
        elseif type(block.x) == "number" and type(block.y) == "number" then
            detail = string.format("%.1f, %.1f", block.x, block.y)
        else
            detail = "Location unavailable"
        end
        frame.Text:ClearAllPoints()
        frame.Text:SetPoint("TOPLEFT", 8, -8)
        frame.Text:SetWidth(math.max(20, width - 36))
        if frame.Text.SetMaxLines then
            frame.Text:SetMaxLines(1)
        end
        frame.Text:SetText(Shown(title))
        Color(frame.Text, WBF.UI.Colors.cream)
        frame.Sub:ClearAllPoints()
        frame.Sub:SetPoint("TOPLEFT", 8, -26)
        frame.Sub:SetWidth(math.max(20, width - 120))
        frame.Sub:SetText(Shown(detail or ""))
        frame.Sub:Show()
        frame.Hint:ClearAllPoints()
        frame.Hint:SetText("Set waypoint")
        Color(frame.Hint, WBF.UI.Colors.gold)
        frame.Hint:Show()
        local cardH = 52
        if width < 240 then
            frame.Sub:SetWidth(math.max(20, width - 16))
            frame.Hint:SetPoint("TOPLEFT", 8, -42)
            cardH = 64
        else
            frame.Hint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
        end
        frame:SetSize(width, cardH)
        frame:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or (self.More and self.More:IsMouseOver()) then
                return
            end
            local ok = WBF.NotebookSmart and WBF.NotebookSmart.Track(block)
            if WBF.UI.Notebook.Note then
                WBF.UI.Notebook.Note(ok and "Waypoint set." or "Couldn't set that waypoint.")
            end
        end)
        frame:SetScript("OnEnter", function(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(Shown(title), 1, 0.82, 0.45)
            WBF.UI.AddTip(GameTooltip, "Click to set a waypoint.", WBF.UI.Colors.tipText, true)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        return cardH
    end
    if kind == "resource" then
        local view = WBF.Resources and WBF.Resources.NotebookView and WBF.Resources.NotebookView(block.resourceKey) or nil
        local title = (view and view.name) or block.resourceKey or "Resource"
        local detail = "No balance yet"
        local twoLines = false
        if view and view.amount ~= nil then
            local total = WBF.Format.Number(view.amount)
            if view.accountWide then
                detail = total .. "   Warband"
            elseif view.character ~= nil and view.character ~= view.amount then
                detail = "You " .. WBF.Format.Number(view.character) .. "\nWarband " .. total
                twoLines = true
            else
                detail = total
            end
        elseif not view then
            detail = "This resource is no longer tracked."
        end
        if view and view.icon then
            frame.Icon:SetTexture(view.icon)
            frame.Icon:ClearAllPoints()
            frame.Icon:SetPoint("TOPLEFT", 8, -8)
            frame.Icon:Show()
            textX = 44
        end
        frame.Text:ClearAllPoints()
        frame.Text:SetPoint("TOPLEFT", textX, -8)
        frame.Text:SetWidth(math.max(20, width - textX - (frame._rightReserve or 28)))
        if frame.Text.SetMaxLines then
            frame.Text:SetMaxLines(1)
        end
        frame.Text:SetText(Shown(title))
        Color(frame.Text, WBF.UI.Colors.cream)
        frame.Sub:ClearAllPoints()
        frame.Sub:SetPoint("TOPLEFT", textX, -26)
        frame.Sub:SetWidth(math.max(20, width - textX - 12))
        frame.Sub:SetWordWrap(true)
        if frame.Sub.SetMaxLines then
            frame.Sub:SetMaxLines(2)
        end
        frame.Sub:SetText(Shown(detail))
        frame.Sub:Show()
        local y = twoLines and 56 or 44
        if type(block.sourceURL) == "string" and block.sourceURL ~= "" then
            y = ShowCopyField(frame, block.sourceURL, y, width)
        end
        local height = math.max(twoLines and 64 or 48, y + 8)
        frame:SetSize(width, height)
        frame:SetScript("OnEnter", function(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(Shown(title), 1, 0.82, 0.45)
            WBF.UI.AddTip(GameTooltip, Shown(detail), WBF.UI.Colors.tipText, true)
            WBF.UI.AddTip(GameTooltip, "Click to open this resource. Right-click for Notebook options.", WBF.UI.Colors.tipFaint, true)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        frame:SetScript("OnMouseUp", function(self, button)
            if self.More and self.More:IsMouseOver() then
                return
            end
            if button == "RightButton" then
                OpenBlockMenu(block.id, self)
                return
            end
            if button == "LeftButton" and WBF.UI.frame and WBF.UI.frame.OpenResource then
                WBF.UI.frame:OpenResource(block.resourceKey, "week")
            end
        end)
        return height
    end
    if WBF.NotebookSmart and WBF.NotebookSmart.Prepare then
        WBF.NotebookSmart.Prepare(block)
    end
    local info = (WBF.NotebookSmart and WBF.NotebookSmart.Describe and WBF.NotebookSmart.Describe(block)) or { title = "Link" }
    if info.icon then
        frame.Icon:SetTexture(info.icon)
        frame.Icon:ClearAllPoints()
        frame.Icon:SetPoint("TOPLEFT", 8, -8)
        frame.Icon:Show()
        textX = 44
    end
    frame.Text:ClearAllPoints()
    frame.Text:SetPoint("TOPLEFT", textX, -8)
    frame.Text:SetWidth(math.max(20, width - textX - (frame._rightReserve or 28)))
    if frame.Text.SetMaxLines then
        frame.Text:SetMaxLines(2)
    end
    frame.Text:SetText(Shown(info.title or "Link item"))
    Color(frame.Text, WBF.UI.Colors.cream)
    local y = 28
    if info.detail and info.detail ~= "" then
        frame.Sub:ClearAllPoints()
        frame.Sub:SetPoint("TOPLEFT", textX, -26)
        frame.Sub:SetWidth(math.max(20, width - textX - 12))
        frame.Sub:SetText(Shown(info.detail))
        frame.Sub:Show()
        y = 44
    end
    if info.url then
        y = ShowCopyField(frame, info.url, y, width)
    end
    local height = math.max(40, y + 8)
    frame:SetSize(width, height)
    return height
end

local function DrawBlock(block, x, y, width)
    local frame = WBF.UI.Acquire(BlockPool(), root)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    frame:SetFrameLevel(root:GetFrameLevel() + 2)
    if focusTarget and focusTarget.blockId == block.id then
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.gold)
        if not focusTarget._scrollRequested and WBF.UI.ScrollToContent then
            focusTarget._scrollRequested = true
            local targetY = math.max(0, (y or 0) - 70)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if focusTarget and focusTarget.blockId == block.id and WBF.UI.ScrollToContent then
                        WBF.UI.ScrollToContent(targetY)
                    end
                end)
            else
                WBF.UI.ScrollToContent(targetY)
            end
        end
    else
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    end
    frame.More:ClearAllPoints()
    frame.More:SetPoint("TOPRIGHT", -6, -6)
    frame.More:SetScript("OnClick", function()
        OpenBlockMenu(block.id, frame.More)
    end)
    local directFyi = WBF.NotebookFyi and WBF.NotebookFyi.ForTarget and WBF.NotebookFyi.ForTarget("block", block.id) or nil
    frame.Fyi:ClearAllPoints()
    frame.Fyi:SetPoint("TOPRIGHT", frame.More, "TOPLEFT", -2, 0)
    if directFyi then
        local directIcon = directFyi.triggerType == "WOW_EVENT" and WBF.EventTriggers and WBF.EventTriggers.Icon and WBF.EventTriggers.Icon(directFyi.eventKey) or nil
        if directFyi.triggerType == "WOW_EVENT" and not directIcon then
            directIcon = "Interface\\Calendar\\UI-Calendar-Button"
        end
        frame.Fyi.Icon:SetTexture(directIcon or "Interface\\Icons\\INV_Misc_Map_01")
        frame.Fyi:SetAlpha(directFyi.enabled == false and 0.4 or 1)
        frame.Fyi:SetScript("OnClick", function()
            if WBF.UI.Fyi and WBF.UI.Fyi.OpenSetup then
                WBF.UI.Fyi.OpenSetup("block", block.id)
            end
        end)
        if WBF.UI.Tooltip then
            WBF.UI.Tooltip(frame.Fyi, function(tip)
                WBF.UI.AddTip(tip, directFyi.enabled == false and "FYI disabled" or "FYI reminder", WBF.UI.Colors.gold)
                if directFyi.triggerType == "WOW_EVENT" then
                    WBF.UI.AddTip(tip, "Show this node during " .. tostring(directFyi.eventName or "the event") .. ".", WBF.UI.Colors.tipText, true)
                else
                    WBF.UI.AddTip(tip, "This node has its own FYI trigger.", WBF.UI.Colors.tipText, true)
                end
            end)
        end
        frame.Fyi:Show()
        frame._rightReserve = 54
    else
        frame.Fyi:Hide()
        frame.Fyi:SetScript("OnClick", nil)
        frame.Fyi:SetScript("OnEnter", nil)
        frame.Fyi:SetScript("OnLeave", nil)
        frame._rightReserve = 28
    end
    if frame.PetAdd then frame.PetAdd:Hide() end
    if frame.PetRows then
        for _, petRow in ipairs(frame.PetRows) do petRow:Hide() end
    end
    frame.Icon:Hide()
    frame.Icon:SetSize(16, 16)
    frame.Sub:Hide()
    frame.Hint:Hide()
    frame.Copy:Hide()
    frame.Link:Hide()
    frame.Bar:Hide()
    frame.Fill:Hide()
    if frame.Criteria then
        frame.Criteria:Hide()
    end
    if frame.CriteriaToggle then
        frame.CriteriaToggle:Hide()
    end
    frame:SetScript("OnMouseUp", nil)
    frame.More:SetFrameLevel(frame:GetFrameLevel() + 3)
    if block.type == "pet_level_list" and WBF.UI.NotebookPets then
        return WBF.UI.NotebookPets.Draw(frame, block, width)
    end
    local smartHeight = DrawSmart(frame, block, width)
    if smartHeight then
        return smartHeight
    end
    local textW = width - (frame._rightReserve or 28) - 12
    local body = block.text or ""
    local sub = nil
    local bodyH = math.min(200, WrappedHeight(body, textW))
    local height = math.max(36, bodyH + 16 + (sub and 14 or 0))
    frame:SetSize(width, height)
    frame.Text:ClearAllPoints()
    if frame.Icon:IsShown() then
        frame.Text:SetPoint("TOPLEFT", frame.Icon, "TOPRIGHT", 6, 0)
    else
        frame.Text:SetPoint("TOPLEFT", 8, -8)
    end
    frame.Text:SetWidth(math.max(20, textW))
    if frame.Text.SetMaxLines then
        frame.Text:SetMaxLines(12)
    end
    frame.Text:SetText(Shown(body))
    Color(frame.Text, WBF.UI.Colors.cream)
    if sub then
        frame.Sub:ClearAllPoints()
        frame.Sub:SetPoint("BOTTOMLEFT", 8, 6)
        frame.Sub:SetText(sub)
        frame.Sub:Show()
    end
    if body ~= "" then
        frame:SetScript("OnEnter", function(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(Shown(body), 1, 0.82, 0.45)
            if block.text and block.text ~= body then
                WBF.UI.AddTip(GameTooltip, Shown(block.text), WBF.UI.Colors.tipText, true)
            end
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    else
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
    end
    if block.type == "checklist" then
        local items = WBF.Notebook.ChecklistItems and WBF.Notebook.ChecklistItems(block) or {}
        local rowH = 22
        local header = 20
        local eventTrigger = WBF.NotebookFyi and WBF.NotebookFyi.EventTriggerForBlock and
            WBF.NotebookFyi.EventTriggerForBlock(block.id) or nil
        height = header + (#items * rowH) + 22
        frame:SetSize(width, height)
        frame.Text:SetText("")
        frame.Sub:Hide()
        frame.Icon:Hide()
        for index = 1, #items do
            local item = items[index]
            local row = WBF.UI.Acquire(CheckPool(), root)
            row:SetParent(frame)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -header - ((index - 1) * rowH))
            row:SetWidth(width)
            row:SetFrameLevel(frame:GetFrameLevel() + 2)
            row.Mark:SetShown(item.done and true or false)
            row.Focus:SetShown(focusTarget and focusTarget.blockId == block.id and focusTarget.itemId == item.id)
            row._editable = true
            row.Edit:Hide()
            row.Progress:Hide()
            row._linkedProgress = false
            row.Text:SetText(Shown(item.text or ""))
            if item.done then
                Color(row.Text, WBF.UI.Colors.muted)
            else
                Color(row.Text, WBF.UI.Colors.cream)
            end

            local linkedProgress = WBF.NotebookSmart and WBF.NotebookSmart.ChecklistProgress and WBF.NotebookSmart.ChecklistProgress(item) or nil
            row._linkedProgress = linkedProgress ~= nil
            row.Progress.Text:SetText(linkedProgress and (tostring(linkedProgress.current or 0) .. " / " .. tostring(linkedProgress.target or 0)) or "Link")
            if linkedProgress and (linkedProgress.current or 0) >= (linkedProgress.target or 1) then
                Color(row.Progress.Text, WBF.UI.Colors.green)
            elseif linkedProgress then
                Color(row.Progress.Text, WBF.UI.Colors.gold)
            else
                Color(row.Progress.Text, WBF.UI.Colors.gold)
            end
            row.Progress:SetShown(linkedProgress ~= nil)

            row.Label:ClearAllPoints()
            row.Edit:ClearAllPoints()
            row.Progress:ClearAllPoints()
            row.Label:SetPoint("LEFT", row.Box, "RIGHT", 6, 0)
            if eventTrigger then
                row.Edit:SetPoint("RIGHT", row.Mode, "LEFT", -4, 0)
                row.Progress:SetPoint("RIGHT", row.Edit, "LEFT", -4, 0)
                row.Label:SetPoint("RIGHT", row.Progress, "LEFT", -6, 0)
                row.Mode.Text:SetText(item.completionMode == "PERMANENT" and "Keep" or "Each event")
                row.Mode:Show()
                row.Mode:SetScript("OnClick", function()
                    local nextMode = item.completionMode == "PERMANENT" and nil or "PERMANENT"
                    WBF.Notebook.SetChecklistCompletionMode(block.id, item.id, nextMode)
                end)
                if WBF.UI.Tooltip then
                    WBF.UI.Tooltip(row.Mode, function(tip)
                        if item.completionMode == "PERMANENT" then
                            WBF.UI.AddTip(tip, "Keep completed", WBF.UI.Colors.gold)
                            WBF.UI.AddTip(tip, "This stays checked when the next " .. tostring(eventTrigger.eventName or "event") .. " occurrence starts.", WBF.UI.Colors.tipText, true)
                        else
                            WBF.UI.AddTip(tip, "Each event", WBF.UI.Colors.gold)
                            WBF.UI.AddTip(tip, "This resets when the next " .. tostring(eventTrigger.eventName or "event") .. " occurrence starts.", WBF.UI.Colors.tipText, true)
                        end
                    end)
                end
            else
                row.Edit:SetPoint("RIGHT", -4, 0)
                row.Progress:SetPoint("RIGHT", row.Edit, "LEFT", -4, 0)
                row.Label:SetPoint("RIGHT", row.Progress, "LEFT", -6, 0)
                row.Mode:Hide()
                row.Mode:SetScript("OnClick", nil)
                row.Mode:SetScript("OnEnter", nil)
                row.Mode:SetScript("OnLeave", nil)
            end

            row.Box:SetScript("OnClick", function()
                WBF.Notebook.ToggleChecklistItem(block.id, item.id)
            end)
            row.Edit:SetScript("OnClick", function()
                Begin({
                    kind = "item-edit",
                    blockId = block.id,
                    itemId = item.id,
                    draft = item.text or "",
                }, false)
            end)
            row.Progress:SetScript("OnClick", function(_, button)
                if linkedProgress and linkedProgress.kind == "resource" and button ~= "RightButton" then
                    if WBF.UI.frame and WBF.UI.frame.OpenResource and WBF.UI.frame:OpenResource(linkedProgress.resourceKey, "week") then
                        HideMenu()
                        return
                    end
                end
                OpenChecklistProgressMenu(block, item, row.Progress)
            end)
            if WBF.UI.Tooltip then
                WBF.UI.Tooltip(row.Progress, function(tip)
                    if linkedProgress then
                        WBF.UI.AddTip(tip, "Linked progress", WBF.UI.Colors.gold)
                        WBF.UI.AddTip(tip, tostring(linkedProgress.title or "Tracked progress") .. ": " .. tostring(linkedProgress.current or 0) .. " / " .. tostring(linkedProgress.target or 0), WBF.UI.Colors.tipText, true)
                        if linkedProgress.kind == "item" and (linkedProgress.accountBank or 0) > 0 then
                            WBF.UI.AddTip(tip, "Includes " .. tostring(linkedProgress.accountBank) .. " in the Warband bank.", WBF.UI.Colors.tipFaint, true)
                        elseif linkedProgress.kind == "resource" and linkedProgress.character ~= nil and linkedProgress.character ~= linkedProgress.current then
                            WBF.UI.AddTip(tip, "You " .. tostring(linkedProgress.character) .. "  ·  Warband " .. tostring(linkedProgress.current), WBF.UI.Colors.tipFaint, true)
                        end
                        WBF.UI.AddTip(tip, linkedProgress.kind == "resource" and "Click to open the resource. Right-click to change or unlink." or "Click to change or unlink.", WBF.UI.Colors.tipFaint, true)
                    else
                        WBF.UI.AddTip(tip, "Link progress", WBF.UI.Colors.gold)
                        WBF.UI.AddTip(tip, "Use a tracked Item or currency/resource in this section as live checklist progress.", WBF.UI.Colors.tipText, true)
                    end
                end)
                WBF.UI.Tooltip(row.Label, function(tip)
                    WBF.UI.AddTip(tip, "Checklist item", WBF.UI.Colors.gold)
                    WBF.UI.AddTip(tip, "Click to edit. Right-click to remove.", WBF.UI.Colors.tipText, true)
                end)
            end
            row.Label:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    Confirm("Remove this item?", function()
                        WBF.Notebook.RemoveChecklistItem(block.id, item.id)
                    end)
                    return
                end
                Begin({
                    kind = "item-edit",
                    blockId = block.id,
                    itemId = item.id,
                    draft = item.text or "",
                }, false)
            end)
        end
        local add = WBF.UI.Acquire(AddItemPool(), root)
        add:SetParent(frame)
        add:ClearAllPoints()
        add:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -header - (#items * rowH))
        add:SetWidth(width)
        add:SetFrameLevel(frame:GetFrameLevel() + 2)
        frame.More:SetFrameLevel(frame:GetFrameLevel() + 3)
        add:SetScript("OnClick", function()
            Begin({ kind = "item-new", blockId = block.id, draft = "" }, false)
        end)
    end
    return height
end

local function LinkButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 18)
    WBF.UI.BindWheel(button)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetAllPoints()
    text:SetJustifyH("LEFT")
    text:SetText(label)
    Color(text, WBF.UI.Colors.gold)
    button.Label = text
    return button
end

local function GoldButton(parent, label, width)
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
        WBF.UI.Paint(self, WBF.UI.Colors.cardHover, WBF.UI.Colors.gold)
    end)
    button:SetScript("OnLeave", function(self)
        WBF.UI.Paint(self, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    end)
    return button
end

local function LineEdit(parent)
    local box = WBF.UI.EditBox(parent, nil, 22)
    box:SetFontObject(GameFontHighlightSmall)
    WBF.UI.KeepKeyboard(box)
    WBF.UI.BindWheel(box)
    local placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", box, "LEFT", 8, 0)
    box.Placeholder = placeholder
    return box, placeholder
end

function WBF.UI.Notebook.Attach(parent)
    root = parent
    root:SetScript("OnHide", function()
        HideMenu()
        composer = nil
        ClearFocus()
        if WBF.UI.NotebookAdd and WBF.UI.NotebookAdd.Close then
            WBF.UI.NotebookAdd.Close()
        end
    end)

    homeTitle = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    homeTitle:SetJustifyH("LEFT")
    homeTitle:SetText("Notebook")
    Color(homeTitle, WBF.UI.Colors.gold)

    homeSubtitle = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    homeSubtitle:SetJustifyH("LEFT")
    homeSubtitle:SetText("Remember what you were doing.")
    Color(homeSubtitle, WBF.UI.Colors.muted)

    newPageButton = GoldButton(root, "+ New Page", 96)
    newPageButton:SetScript("OnClick", function()
        Begin({ kind = "page-new", draft = "", summary = "" }, true)
    end)
    quickButton = GoldButton(root, "Quick Note", 96)
    quickButton:SetScript("OnClick", function()
        Begin({ kind = "note-new", draft = "" }, true)
    end)

    searchBox, searchPlaceholder = LineEdit(root)
    searchBox:SetMaxLetters(80)
    searchPlaceholder:SetText("Search pages, notes, or content...")
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if Trim(self:GetText() or "") == "" then
            searchPlaceholder:Show()
        else
            searchPlaceholder:Hide()
        end
        if not userInput then
            return
        end
        query = self:GetText() or ""
        searchGen = searchGen + 1
        local generation = searchGen
        if C_Timer and C_Timer.After then
            C_Timer.After(0.12, function()
                if generation ~= searchGen then
                    return
                end
                RefreshView(false)
            end)
        else
            RefreshView(false)
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    backButton = LinkButton(root, "< Notebook", 120)
    backButton:SetScript("OnClick", function()
        selectedPage = nil
        focusTarget = nil
        composer = nil
        ClearFocus()
        RefreshView(true)
    end)

    pageTitleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pageTitleText:SetJustifyH("LEFT")
    pageTitleText:SetWordWrap(false)
    Color(pageTitleText, WBF.UI.Colors.gold)

    pageSummaryText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageSummaryText:SetJustifyH("LEFT")
    pageSummaryText:SetWordWrap(true)
    Color(pageSummaryText, WBF.UI.Colors.muted)

    pageMore = MoreButton(root)
    pageMore:SetScript("OnClick", function()
        if selectedPage then
            OpenPageMenu(selectedPage, pageMore)
        end
    end)
    pageFyiButton = GoldButton(root, "+ FYI", 58)
    pageFyiButton:SetScript("OnClick", function()
        if selectedPage and WBF.UI.Fyi and WBF.UI.Fyi.OpenSetup then
            WBF.UI.Fyi.OpenSetup("page", selectedPage, "WOW_EVENT")
        end
    end)
    editButton = GoldButton(root, "Edit Page", 84)
    editButton:SetScript("OnClick", function()
        local page = selectedPage and WBF.Notebook.GetPage(selectedPage) or nil
        if not page then
            return
        end
        Begin({
            kind = "page-edit",
            pageId = page.id,
            draft = page.title or "",
            summary = page.summary or "",
        }, false)
    end)
    emptyAdd = GoldButton(root, "+ Add", 64)
    emptyAdd:SetScript("OnClick", function()
        OpenAddMenu(emptyAdd, nil)
    end)

    titleBox, titlePlaceholder = LineEdit(root)
    summaryBox, summaryPlaceholder = LineEdit(root)
    lineBox, linePlaceholder = LineEdit(root)
    titleBox:SetScript("OnTextChanged", function(self)
        if composer and (composer.kind == "page-new" or composer.kind == "page-edit") then
            composer.draft = self:GetText() or ""
        end
        titlePlaceholder:SetShown(Trim(self:GetText() or "") == "")
    end)
    summaryBox:SetScript("OnTextChanged", function(self)
        if composer and (composer.kind == "page-new" or composer.kind == "page-edit") then
            composer.summary = self:GetText() or ""
        end
        summaryPlaceholder:SetShown(Trim(self:GetText() or "") == "")
    end)
    lineBox:SetScript("OnTextChanged", function(self)
        if composer and composer.kind ~= "page-new" and composer.kind ~= "page-edit" then
            composer.draft = self:GetText() or ""
        end
        linePlaceholder:SetShown(Trim(self:GetText() or "") == "")
    end)
    titleBox:SetScript("OnEnterPressed", function()
        if summaryBox:IsShown() then
            summaryBox:SetFocus()
        else
            Commit()
        end
    end)
    summaryBox:SetScript("OnEnterPressed", Commit)
    lineBox:SetScript("OnEnterPressed", Commit)
    titleBox:SetScript("OnEscapePressed", Cancel)
    summaryBox:SetScript("OnEscapePressed", Cancel)
    lineBox:SetScript("OnEscapePressed", Cancel)

    areaHolder = CreateFrame("Frame", nil, root, "BackdropTemplate")
    WBF.UI.Paint(areaHolder, WBF.UI.Colors.well, WBF.UI.Colors.goldDim)
    areaBox = CreateFrame("EditBox", nil, areaHolder)
    areaBox:SetMultiLine(true)
    areaBox:SetAutoFocus(false)
    areaBox:SetFontObject(GameFontHighlightSmall)
    areaBox:SetMaxLetters(800)
    areaBox:SetPoint("TOPLEFT", 6, -6)
    areaBox:SetPoint("BOTTOMRIGHT", -6, 6)
    areaBox:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
    WBF.UI.KeepKeyboard(areaBox)
    WBF.UI.BindWheel(areaBox)
    areaBox:SetScript("OnEscapePressed", Cancel)
    areaBox:SetScript("OnTextChanged", function(self)
        if composer then
            composer.draft = self:GetText() or ""
        end
    end)

    saveButton = GoldButton(root, "Save", 64)
    saveButton:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            Commit()
        end
    end)
    cancelButton = GoldButton(root, "Cancel", 72)
    cancelButton:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            Cancel()
        end
    end)

    noticeText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noticeText:SetJustifyH("LEFT")
    Color(noticeText, WBF.UI.Colors.muted)

    measure = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    measure:Hide()

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
    if WBF.UI.NotebookAdd and WBF.UI.NotebookAdd.Attach then
        WBF.UI.NotebookAdd.Attach()
    end
    if WBF.UI.ContextFyi and WBF.UI.ContextFyi.Attach then
        WBF.UI.ContextFyi.Attach(root)
    end
end

local function HideChrome()
    homeTitle:Hide()
    homeSubtitle:Hide()
    newPageButton:Hide()
    quickButton:Hide()
    if selectedPage or not searchBox:HasFocus() then
        searchBox:Hide()
    end
    backButton:Hide()
    pageTitleText:Hide()
    pageSummaryText:Hide()
    pageMore:Hide()
    pageFyiButton:Hide()
    editButton:Hide()
    emptyAdd:Hide()
    noticeText:Hide()
    HideEditors()
end

local function FocusComposer()
    if not wantFocus then
        return
    end
    wantFocus = false
    if titleBox:IsShown() then
        titleBox:SetFocus()
        if titleBox.HighlightText then
            titleBox:HighlightText()
        end
    elseif areaHolder:IsShown() then
        areaBox:SetFocus()
    elseif lineBox:IsShown() then
        lineBox:SetFocus()
        if lineBox.HighlightText and composer and composer.kind ~= "item-new" and composer.kind ~= "text-new" and composer.kind ~= "check-new" and composer.kind ~= "note-new" and composer.kind ~= "section-new" then
            lineBox:HighlightText()
        end
    end
end

local function RenderHome(width)
    local y = 4
    homeTitle:ClearAllPoints()
    homeTitle:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    homeTitle:Show()
    quickButton:ClearAllPoints()
    newPageButton:ClearAllPoints()
    if width < 420 then
        homeTitle:SetWidth(math.max(80, width))
        y = y + 28
        newPageButton:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        quickButton:SetPoint("LEFT", newPageButton, "RIGHT", 8, 0)
    else
        homeTitle:SetWidth(math.max(80, width - 210))
        quickButton:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -y)
        newPageButton:SetPoint("RIGHT", quickButton, "LEFT", -8, 0)
    end
    quickButton:Show()
    newPageButton:Show()
    y = y + 26
    homeSubtitle:ClearAllPoints()
    homeSubtitle:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    homeSubtitle:Show()
    y = y + 20
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -y)
    searchBox:SetPoint("TOPRIGHT", root, "TOPRIGHT", -8, -y)
    searchBox:Show()
    if Trim(searchBox:GetText() or "") == "" then
        searchPlaceholder:Show()
    end
    y = y + 32

    local contextMode = WBF.UI.ContextFyi and WBF.UI.ContextFyi.Mode and WBF.UI.ContextFyi.Mode() or "home"
    if contextMode ~= "home" then
        searchBox:Hide()
        searchPlaceholder:Hide()
        quickButton:Hide()
        newPageButton:Hide()
        homeTitle:Hide()
        homeSubtitle:Hide()
        return WBF.UI.ContextFyi.Draw(root, 4, width)
    end

    if notice then
        noticeText:ClearAllPoints()
        noticeText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        noticeText:SetText(Shown(notice))
        noticeText:Show()
        y = y + 18
    end
    if composer and composer.kind == "page-new" then
        y = ShowTitleBoxes(composer.draft or "", composer.summary or "", 8, y, width - 16)
        y = y + 8
    elseif composer and (composer.kind == "note-new" or composer.kind == "note-edit") then
        y = ShowLineEditor(composer.draft or "", "Write it down", 800, 8, y, width - 16)
        y = y + 8
    end

    if WBF.UI.ContextFyi and WBF.UI.ContextFyi.DrawHome then
        y = WBF.UI.ContextFyi.DrawHome(root, y, width)
    end

    local found = WBF.Notebook.Search(query)
    if found.active then
        y = PlaceHeading("RESULTS", y, width, nil, nil)
        local hits = found.hits or {}
        if #hits == 0 then
            y = MutedLine("No matches.", 0, y, width)
        else
            for index = 1, #hits do
                y = PlaceHit(hits[index], y, width)
            end
        end
        return y + 12
    end

    local pages = WBF.Notebook.Pages()
    local pinned = {}
    for index = 1, math.min(6, #WBF.Notebook.PinnedPages()) do
        pinned[index] = WBF.Notebook.PinnedPages()[index]
    end
    if #pages > 0 then
        y = PlaceHeading("PINNED PAGES", y, width, nil, nil)
        if #pinned == 0 then
            y = MutedLine("Nothing pinned yet.", 0, y, width)
        else
            y = Grid(pinned, y, width, 86, PlacePinned)
            if #WBF.Notebook.PinnedPages() > #pinned then
                y = MutedLine("Showing 6 pinned pages.", 0, y + 6, width)
            end
        end
        y = y + 14
    end

    local recent = WBF.Notebook.RecentPages(8)
    y = PlaceHeading("RECENT PAGES", y, width, nil, nil)
    if #pages == 0 then
        y = MutedLine("No pages yet.", 0, y, width)
        y = MutedLine("Create a page for something you want to come back to.", 0, y, width)
    elseif #recent == 0 then
        y = MutedLine("Pinned pages are listed above.", 0, y, width)
    else
        for index = 1, #recent do
            y = PlaceRecent(recent[index], y, width)
        end
    end
    y = y + 14

    y = PlaceHeading("QUICK NOTES", y, width, "New Note", function()
        Begin({ kind = "note-new", draft = "" }, true)
    end)
    if #found.notes == 0 then
        y = MutedLine("No quick notes.", 0, y, width)
    else
        y = Grid(found.notes, y, width, 72, PlaceNote)
    end
    return y + 12
end

local function RenderPage(page, width)
    local y = 4
    backButton:ClearAllPoints()
    backButton:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    backButton:Show()
    editButton:ClearAllPoints()
    editButton:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -y)
    editButton:Show()
    pageFyiButton:ClearAllPoints()
    local pageFyi = WBF.NotebookFyi and WBF.NotebookFyi.ForTarget and WBF.NotebookFyi.ForTarget("page", page.id) or nil
    pageMore:ClearAllPoints()
    if pageFyi then
        pageFyiButton:SetPoint("RIGHT", editButton, "LEFT", -6, 0)
        pageFyiButton.Label:SetText(pageFyi.enabled == false and "Page FYI OFF" or "Page FYI")
        pageFyiButton:SetWidth(pageFyi.enabled == false and 92 or 72)
        pageFyiButton:Show()
        pageMore:SetPoint("RIGHT", pageFyiButton, "LEFT", -6, 0)
    else
        pageFyiButton:Hide()
        pageMore:SetPoint("RIGHT", editButton, "LEFT", -6, 0)
    end
    pageMore:Show()
    y = y + 26

    local editing = composer and composer.kind == "page-edit" and composer.pageId == page.id
    if editing then
        y = ShowTitleBoxes(composer.draft or page.title or "", composer.summary or page.summary or "", 8, y, width - 16)
        y = y + 8
    else
        pageTitleText:ClearAllPoints()
        pageTitleText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        pageTitleText:SetWidth(math.max(40, width - 8))
        pageTitleText:SetText(Shown(page.title))
        pageTitleText:Show()
        y = y + 24
        if WBF.Notebook.ShowsSummary(page) then
            pageSummaryText:ClearAllPoints()
            pageSummaryText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
            pageSummaryText:SetWidth(math.max(40, width))
            pageSummaryText:SetText(Shown(page.summary))
            pageSummaryText:Show()
            local summaryH = WrappedHeight(page.summary, width)
            if summaryH > 36 then
                summaryH = 36
            end
            y = y + summaryH + 6
        end
    end
    if notice then
        noticeText:ClearAllPoints()
        noticeText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        noticeText:SetText(Shown(notice))
        noticeText:Show()
        y = y + 18
    end

    local sections = WBF.Notebook.Sections(page.id)
    if #sections == 0 then
        emptyAdd:ClearAllPoints()
        emptyAdd:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        emptyAdd:Show()
        y = y + 28
        y = MutedLine("Use + Add to put something on this page.", 0, y, width)
        if composer and composer.kind == "section-new" and composer.pageId == page.id and not composer.afterId then
            y = ShowLineEditor(composer.draft or "", "Section title", 80, 8, y, width - 16)
        elseif composer and (composer.kind == "text-new" or composer.kind == "check-new") and composer.pageId == page.id and not composer.sectionId then
            if composer.kind == "text-new" then
                y = ShowAreaEditor(composer.draft or "", 8, y, width - 16)
            else
                y = ShowLineEditor(composer.draft or "", "First item", 800, 8, y, width - 16)
            end
        end
        return y + 12
    end

    for index = 1, #sections do
        local section = sections[index]
        if focusTarget and focusTarget.sectionId == section.id and section.collapsed then
            WBF.Notebook.SetCollapsed(section.id, false)
            section = WBF.Notebook.GetSection(section.id) or section
        end
        local top = y
        local box = WBF.UI.Acquire(SectionBoxPool(), root)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -top)
        box:SetWidth(width)
        box:SetFrameLevel(root:GetFrameLevel())
        if focusTarget and focusTarget.sectionId == section.id and not focusTarget.blockId then
            WBF.UI.Paint(box, WBF.UI.Colors.selected, WBF.UI.Colors.gold)
        else
            WBF.UI.Paint(box, WBF.UI.Colors.row, WBF.UI.Colors.goldDim)
        end
        y = y + 8
        local head = WBF.UI.Acquire(SectionHeadPool(), root)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -y)
        head:SetWidth(math.max(40, width - 16))
        head:SetFrameLevel(root:GetFrameLevel() + 4)
        head.ArrowText:SetText(section.collapsed and ">" or "v")
        head.TitleText:SetText(Shown(section.title))
        local function toggle()
            WBF.Notebook.SetCollapsed(section.id, not section.collapsed)
        end
        head.Arrow:SetScript("OnClick", toggle)
        head.Title:SetScript("OnClick", toggle)
        head.More:SetScript("OnClick", function()
            OpenSectionMenu(section.id, head.More)
        end)
        head.Add:SetScript("OnClick", function()
            OpenAddMenu(head.Add, section.id)
        end)

        local fyiTrigger = WBF.NotebookFyi and WBF.NotebookFyi.ForTarget and WBF.NotebookFyi.ForTarget("section", section.id) or nil
        local eventSuggestion = WBF.NotebookFyi and WBF.NotebookFyi.SuggestEvent and WBF.NotebookFyi.SuggestEvent("section", section.id) or nil
        -- FYI is a capability of existing Notebook content, not a separate content type.
        -- Always expose it on section headers; title matching only supplies a helpful default.
        head.Fyi:Show()
        head.Title:ClearAllPoints()
        head.Title:SetPoint("LEFT", head.Arrow, "RIGHT", 2, 0)
        head.Title:SetPoint("RIGHT", head.Fyi, "LEFT", -6, 0)
        local fyiIcon = fyiTrigger and fyiTrigger.triggerType == "WOW_EVENT" and WBF.EventTriggers and WBF.EventTriggers.Icon and WBF.EventTriggers.Icon(fyiTrigger.eventKey) or nil
        if fyiTrigger and fyiTrigger.triggerType == "WOW_EVENT" and not fyiIcon then
            fyiIcon = "Interface\\Calendar\\UI-Calendar-Button"
        end
        if fyiIcon then
            head.FyiIcon:SetTexture(fyiIcon)
            head.FyiIcon:Show()
            head.FyiText:ClearAllPoints()
            head.FyiText:SetPoint("LEFT", head.FyiIcon, "RIGHT", 3, 0)
            head.FyiText:SetPoint("RIGHT", 0, 0)
        else
            head.FyiIcon:Hide()
            head.FyiText:ClearAllPoints()
            head.FyiText:SetPoint("LEFT", 0, 0)
            head.FyiText:SetPoint("RIGHT", 0, 0)
        end
        if fyiTrigger then
            head.FyiText:SetText(fyiTrigger.enabled == false and "FYI OFF" or "FYI")
            Color(head.FyiText, fyiTrigger.enabled == false and WBF.UI.Colors.muted or WBF.UI.Colors.cream)
        else
            head.FyiText:SetText("+ FYI")
            Color(head.FyiText, WBF.UI.Colors.gold)
        end
        head.Fyi:SetScript("OnClick", function()
            if WBF.UI.Fyi and WBF.UI.Fyi.OpenSetup then
                -- A visible + FYI on Notebook content is primarily the event/holiday flow.
                -- Existing zone FYIs still reopen in their saved mode.
                WBF.UI.Fyi.OpenSetup("section", section.id, "WOW_EVENT")
            end
        end)
        if WBF.UI.Tooltip then
            WBF.UI.Tooltip(head.Fyi, function(tip)
                if fyiTrigger and fyiTrigger.triggerType == "WOW_EVENT" then
                    WBF.UI.AddTip(tip, "FYI — " .. tostring(fyiTrigger.eventName or "WoW event"), WBF.UI.Colors.gold)
                    WBF.UI.AddTip(tip, "This section is shown when the event is active. Click to edit.", WBF.UI.Colors.tipText, true)
                elseif fyiTrigger then
                    WBF.UI.AddTip(tip, "FYI reminder", WBF.UI.Colors.gold)
                    WBF.UI.AddTip(tip, "This section already has an FYI trigger. Click to edit.", WBF.UI.Colors.tipText, true)
                elseif eventSuggestion then
                    WBF.UI.AddTip(tip, "Show during " .. tostring(eventSuggestion.name), WBF.UI.Colors.gold)
                    WBF.UI.AddTip(tip, "Use this existing Notebook section as the FYI. Click to confirm or choose another event.", WBF.UI.Colors.tipText, true)
                else
                    WBF.UI.AddTip(tip, "Show as an FYI", WBF.UI.Colors.gold)
                    WBF.UI.AddTip(tip, "Choose a WoW event such as Brewfest or Darkmoon Faire. No duplicate note is created.", WBF.UI.Colors.tipText, true)
                end
            end)
        end
        y = y + 32
        if composer and composer.kind == "section-rename" and composer.sectionId == section.id then
            y = ShowLineEditor(composer.draft or section.title or "", "Section title", 80, 16, y, width - 32)
            y = y + 4
        end
        if not section.collapsed then
            local blocks = WBF.Notebook.Blocks(section.id)
            local innerX = 8
            local innerW = math.max(40, width - 16)
            local focused = false
            if composer then
                if composer.sectionId == section.id and (composer.kind == "text-new" or composer.kind == "check-new") then
                    focused = true
                elseif composer.blockId then
                    local owner = WBF.Notebook.GetBlock(composer.blockId)
                    focused = owner ~= nil and owner.sectionId == section.id
                end
            end
            if #blocks == 0 and not focused then
                y = MutedLine("Nothing in this section yet.", innerX, y, innerW)
            end
            local columns = (not focused and innerW >= 560) and 2 or 1
            local gap = 8
            local colW = columns == 1 and innerW or math.floor((innerW - gap) / 2)
            local colY = { y, y }
            local function takeColumn()
                if columns == 2 and colY[2] < colY[1] then
                    return 2
                end
                return 1
            end
            for blockIndex = 1, #blocks do
                local block = blocks[blockIndex]
                local span = WBF.NotebookSheet and WBF.NotebookSheet.FullWidth and WBF.NotebookSheet.FullWidth(block, columns) and columns > 1
                local col, px, drawW
                if span then
                    local top = math.max(colY[1], colY[2])
                    colY[1], colY[2] = top, top
                    col = 1
                    px = innerX
                    drawW = innerW
                else
                    col = takeColumn()
                    px = innerX + (col - 1) * (colW + gap)
                    drawW = colW
                end
                if composer and composer.kind == "text-edit" and composer.blockId == block.id then
                    local nextY = ShowAreaEditor(composer.draft or "", px, colY[col], drawW)
                    colY[col] = nextY + gap
                elseif composer and composer.kind == "list-rename" and composer.blockId == block.id then
                    local nextY = ShowLineEditor(composer.draft or block.title or "", "List title", 80, px, colY[col], drawW)
                    colY[col] = nextY + gap
                else
                    local ok, height = pcall(DrawBlock, block, px, colY[col], drawW)
                    if not ok then
                        if WBF.Debug and WBF.Debug.Log then
                            WBF.Debug.Log("Notebook block skipped", block and block.id, height)
                        end
                        colY[col] = MutedLine("A block on this page could not be shown.", px, colY[col], drawW) + gap
                    else
                        colY[col] = colY[col] + height + gap
                    end
                    if composer and composer.blockId == block.id and (composer.kind == "item-new" or composer.kind == "item-edit") then
                        local placeholder = "Checklist item"
                        local nextY = ShowLineEditor(composer.draft or "", placeholder, 800, px, colY[col], drawW)
                        colY[col] = nextY + gap
                    end
                end
                if span then
                    local bottom = math.max(colY[1], colY[2])
                    colY[1], colY[2] = bottom, bottom
                end
            end
            y = math.max(colY[1], colY[2])
            if composer and composer.sectionId == section.id and composer.kind == "text-new" then
                y = ShowAreaEditor(composer.draft or "", innerX, y, innerW)
            elseif composer and composer.sectionId == section.id and composer.kind == "check-new" then
                y = ShowLineEditor(composer.draft or "", "First item", 800, innerX, y, innerW)
            end
        end
        y = y + 8
        box:SetHeight(math.max(36, y - top))
        y = y + 8
        if composer and composer.kind == "section-new" and composer.afterId == section.id then
            y = ShowLineEditor(composer.draft or "", "Section title", 80, 8, y, width - 16)
            y = y + 8
        end
    end
    return y + 8
end

function WBF.UI.Notebook.Render(width)
    if not root or not WBF.Notebook or not WBF.Notebook.Root then
        return 40
    end

    -- The main window is refreshed by live trackers while it is open.  A full
    -- Notebook repaint temporarily hides the editor controls, which makes WoW
    -- drop keyboard focus and lets normal action-bar keybinds fire.  Preserve
    -- the active editor/cursor across those passive refreshes instead.
    local focusedEditor = nil
    local focusedCursor = nil
    local editors = { searchBox, titleBox, summaryBox, lineBox, areaBox }
    for index = 1, #editors do
        local box = editors[index]
        if box and box.HasFocus and box:HasFocus() then
            focusedEditor = box
            if box.GetCursorPosition then
                focusedCursor = box:GetCursorPosition()
            end
            break
        end
    end

    -- Custom Notebook menus are also interactive state.  Do not tear one down
    -- just because a currency/item/achievement tracker requested a repaint.
    -- User actions that genuinely change context already call HideMenu().
    local keepMenuOpen = menu and menu.IsShown and menu:IsShown()

    WBF.UI.ReleaseAll()
    if not keepMenuOpen then
        HideMenu()
    end
    HideChrome()
    if WBF.UI.ContextFyi and WBF.UI.ContextFyi.Hide then
        WBF.UI.ContextFyi.Hide()
    end
    if selectedPage and not WBF.Notebook.GetPage(selectedPage) then
        selectedPage = nil
    end
    if composer then
        local gone = (composer.pageId and not WBF.Notebook.GetPage(composer.pageId))
            or (composer.sectionId and not WBF.Notebook.GetSection(composer.sectionId))
            or (composer.blockId and not WBF.Notebook.GetBlock(composer.blockId))
            or (composer.noteId and not WBF.Notebook.GetNote(composer.noteId))
            or (composer.itemId and composer.blockId and WBF.Notebook.GetChecklistItem and not WBF.Notebook.GetChecklistItem(composer.blockId, composer.itemId))
        if gone then
            composer = nil
            notice = nil
        end
    end
    if not selectedPage and WBF.UI.NotebookAdd and WBF.UI.NotebookAdd.Close then
        WBF.UI.NotebookAdd.Close()
    end
    local height
    if selectedPage then
        height = RenderPage(WBF.Notebook.GetPage(selectedPage), width)
    else
        height = RenderHome(width)
    end
    FocusComposer()

    -- If this was a passive/background repaint, put the keyboard exactly back
    -- where the player was typing.  Run once immediately and once next frame;
    -- some EditBoxes only settle their focus after the frame layout completes.
    if focusedEditor and focusedEditor.IsShown and focusedEditor:IsShown() then
        local box = focusedEditor
        local cursor = focusedCursor
        local function restore()
            if not box or not box.IsShown or not box:IsShown() then
                return
            end
            box:SetFocus()
            if cursor ~= nil and box.SetCursorPosition then
                local text = box.GetText and (box:GetText() or "") or ""
                box:SetCursorPosition(math.min(cursor, #text))
            end
            if WBF.UI.KeepKeyboard then
                WBF.UI.KeepKeyboard(box)
            elseif box.SetPropagateKeyboardInput then
                box:SetPropagateKeyboardInput(false)
            end
        end
        restore()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, restore)
        end
    end
    return height
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
    WBF.UI.SetColor(highlight, WBF.UI.Colors.highlight)
    local header = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 0, -2)
    header:SetText("NOTEBOOK")
    Color(header, WBF.UI.Colors.gold)
    block.Lines = {}
    for index = 1, 3 do
        local label = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        Color(label, WBF.UI.Colors.cream)
        local value = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(false)
        Color(value, WBF.UI.Colors.gold)
        block.Lines[index] = { label = label, value = value }
    end
    local footer = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetJustifyH("LEFT")
    Color(footer, WBF.UI.Colors.muted)
    block.Footer = footer
    block:SetScript("OnClick", function()
        if WBF.UI.frame and WBF.UI.frame.SetView then
            WBF.UI.frame:SetView("notebook")
        end
    end)
    block:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("Notebook", 1, 0.82, 0.45)
        WBF.UI.AddTip(GameTooltip, "Open your pages.", WBF.UI.Colors.tipText)
        GameTooltip:Show()
    end)
    block:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    summaryBlock = block
    return block
end

function WBF.UI.Notebook.DrawSummary(parent, y, width)
    if not WBF.Notebook or not WBF.Notebook.Summary then
        return y
    end
    local summary = WBF.Notebook.Summary()
    if not summary or ((summary.pages or 0) < 1 and (summary.notes or 0) < 1) then
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
    local footer = (summary.pages or 0) .. ((summary.pages or 0) == 1 and " page" or " pages")
    if (summary.notes or 0) > 0 then
        footer = footer .. " · " .. summary.notes .. (summary.notes == 1 and " note" or " notes")
    end
    block.Footer:ClearAllPoints()
    block.Footer:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(18 + lineCount * 16))
    block.Footer:SetText(footer)
    return y + height + 8
end
