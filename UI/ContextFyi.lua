local _, WBF = ...

-- Event FYIs use the same clinical notebook language: gold headers,
-- muted secondary lines, compact rows, no extra chrome.
WBF.UI = WBF.UI or {}
WBF.UI.ContextFyi = {}

local mode = "home"
local focusKey = nil
local editor = nil
local host = nil
local board = nil
local widgets = {}
local rows = {}
local itemBoxes = {}
local itemModes = {}
local itemRemoves = {}
local toast = nil
local reminder = nil
local painting = false

local function Shown(text)
    if type(text) ~= "string" then
        return ""
    end
    return (text:gsub("|", "||"))
end

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Color(widget, color)
    if widget and color then
        widget:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function Track(widget)
    widgets[#widgets + 1] = widget
    return widget
end

local function HideOwned()
    for index = 1, #widgets do
        widgets[index]:Hide()
    end
end

local function PaintButton(button)
    WBF.UI.Paint(button, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    if button.Label then
        Color(button.Label, WBF.UI.Colors.cream)
    end
end

local function Button(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height or 20)
    WBF.UI.BindWheel(button)
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
    return Track(button)
end

local function Font(parent, fontObject)
    local text = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:Hide()
    return Track(text)
end

local captions = {}
local captionIndex = 0

local function ResetCaptions()
    captionIndex = 0
end

local function Caption(text, x, y, width)
    captionIndex = captionIndex + 1
    local font = captions[captionIndex]
    if not font then
        font = Font(board, "GameFontDisableSmall")
        captions[captionIndex] = font
    end
    font:ClearAllPoints()
    font:SetPoint("TOPLEFT", board, "TOPLEFT", x, -y)
    if width then
        font:SetWidth(width)
    end
    font:SetText(text)
    Color(font, WBF.UI.Colors.muted)
    font:Show()
    return font
end

local function Box(parent, width)
    local edit = WBF.UI.EditBox(parent, width, 22)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
    WBF.UI.BindWheel(edit)
    if WBF.UI.KeepKeyboard then
        WBF.UI.KeepKeyboard(edit)
    end
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    edit:Hide()
    return Track(edit)
end

local function EnsureBoard(parent)
    if board then
        if parent and board:GetParent() ~= parent then
            board:SetParent(parent)
        end
        return board
    end
    board = CreateFrame("Frame", nil, parent)
    board:SetSize(40, 40)
    host = parent

    board.Back = Button(board, "< Notebook", 110, 20)
    board.Heading = Font(board, "GameFontNormalLarge")
    board.Sub = Font(board, "GameFontHighlightSmall")
    board.Status = Font(board, "GameFontDisableSmall")
    board.TitleBox = Box(board, 240)
    board.TypeButton = Button(board, "Reference", 140, 20)
    board.EventButton = Button(board, "Darkmoon Faire", 180, 20)
    board.RepeatText = Font(board, "GameFontDisableSmall")
    board.MoreButton = Button(board, "More", 64, 20)
    board.AchButton = Button(board, "Achievement", 120, 20)
    board.AchBox = Box(board, 80)
    board.CurButton = Button(board, "Currency", 100, 20)
    board.CurBox = Box(board, 80)
    board.NotesHolder = CreateFrame("Frame", nil, board, "BackdropTemplate")
    Track(board.NotesHolder)
    WBF.UI.Paint(board.NotesHolder, { 0.04, 0.045, 0.06, 1 }, WBF.UI.Colors.goldDim)
    board.NotesBox = CreateFrame("EditBox", nil, board.NotesHolder)
    board.NotesBox:SetMultiLine(true)
    board.NotesBox:SetAutoFocus(false)
    board.NotesBox:SetFontObject(GameFontHighlightSmall)
    board.NotesBox:SetMaxLetters(800)
    board.NotesBox:SetPoint("TOPLEFT", 6, -6)
    board.NotesBox:SetPoint("BOTTOMRIGHT", -6, 6)
    board.NotesBox:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
    WBF.UI.KeepKeyboard(board.NotesBox)
    WBF.UI.BindWheel(board.NotesBox)
    board.NotesBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    board.AddItem = Button(board, "Add item", 80, 20)
    board.Save = Button(board, "Save", 64, 20)
    board.Cancel = Button(board, "Cancel", 72, 20)
    board.Delete = Button(board, "Delete", 64, 20)
    board.Done = Button(board, "Done for this occurrence", 180, 20)
    board.Permanent = Button(board, "Complete permanently", 160, 20)
    board.Archive = Button(board, "Archive FYI", 100, 20)
    for index = 1, 8 do
        itemBoxes[index] = Box(board, 220)
        itemModes[index] = Button(board, "Each time", 88, 20)
        itemRemoves[index] = Button(board, "Remove", 64, 20)
    end
    return board
end

local function Row(index)
    local row = rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, board, "BackdropTemplate")
    row:SetHeight(36)
    row:RegisterForClicks("LeftButtonUp")
    WBF.UI.BindWheel(row)
    WBF.UI.Paint(row, { 0.05, 0.055, 0.07, 0.92 }, WBF.UI.Colors.goldDim)
    local mark = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mark:SetPoint("LEFT", 8, 0)
    mark:SetWidth(16)
    Color(mark, WBF.UI.Colors.gold)
    local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 28, -5)
    title:SetPoint("RIGHT", -8, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    Color(title, WBF.UI.Colors.cream)
    local detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail:SetPoint("BOTTOMLEFT", 28, 4)
    detail:SetPoint("RIGHT", -8, 0)
    detail:SetJustifyH("LEFT")
    detail:SetWordWrap(false)
    Color(detail, WBF.UI.Colors.muted)
    row.Mark = mark
    row.Title = title
    row.Detail = detail
    row:SetScript("OnEnter", function(self)
        WBF.UI.Paint(self, { 0.11, 0.12, 0.15, 0.98 }, WBF.UI.Colors.gold)
        if self.tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tipTitle or "", 1, 0.82, 0.45)
            GameTooltip:AddLine(self.tip, 0.75, 0.75, 0.75, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        WBF.UI.Paint(self, { 0.05, 0.055, 0.07, 0.92 }, WBF.UI.Colors.goldDim)
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    rows[index] = row
    Track(row)
    return row
end

local function HideRows(from)
    for index = from, #rows do
        rows[index]:Hide()
    end
end

local actions = {}

local function Action(index, text, width)
    local button = actions[index]
    if not button then
        button = Button(board, text, width, 20)
        actions[index] = button
    end
    button.Label:SetText(text)
    button:SetWidth(width)
    return button
end

function WBF.UI.ContextFyi.Attach(parent)
    host = parent
    EnsureBoard(parent)
    board:Hide()
end

function WBF.UI.ContextFyi.Hide()
    if board then
        board:Hide()
    end
end

function WBF.UI.ContextFyi.Mode()
    return mode
end

local function Repaint()
    if WBF.Notebook and WBF.Notebook.RefreshOpen then
        WBF.Notebook.RefreshOpen()
    elseif WBF.UI.RequestRefresh then
        WBF.UI.RequestRefresh()
    end
end

local function OpenNotebook()
    local frame = WBF.UI.frame
    if frame and frame.SetView then
        frame:SetView("notebook")
    end
    if frame and frame.Show and frame.IsShown and not frame:IsShown() then
        frame:Show()
    end
    Repaint()
end

function WBF.UI.ContextFyi.OpenFocus(eventKey)
    focusKey = eventKey
    editor = nil
    mode = "focus"
    OpenNotebook()
end

local function BlankEditor()
    return {
        id = nil,
        title = "",
        fyiType = "REFERENCE",
        notes = "",
        eventKey = "darkmoon",
        more = false,
        achievementOn = false,
        achievementID = "",
        currencyOn = false,
        currencyID = "",
        itemsOn = false,
        items = {},
    }
end

function WBF.UI.ContextFyi.OpenEditor(id)
    local draft = BlankEditor()
    local entry = id and WBF.ContextFyi and WBF.ContextFyi.Get and WBF.ContextFyi.Get(id) or nil
    if entry then
        draft.id = entry.id
        draft.title = entry.title or ""
        draft.fyiType = entry.type or "REFERENCE"
        draft.notes = entry.notes or ""
        draft.eventKey = entry.trigger and entry.trigger.eventKey or draft.eventKey
        draft.achievementOn = entry.achievementID ~= nil
        draft.achievementID = entry.achievementID and tostring(entry.achievementID) or ""
        draft.currencyOn = entry.currencyID ~= nil
        draft.currencyID = entry.currencyID and tostring(entry.currencyID) or ""
        draft.more = draft.achievementOn or draft.currencyOn
        draft.items = {}
        local items = entry.items or {}
        for index = 1, #items do
            draft.items[index] = {
                id = items[index].id,
                text = items[index].text or "",
                completionMode = items[index].completionMode or "OCCURRENCE",
            }
        end
        draft.itemsOn = #draft.items > 0
    end
    editor = draft
    mode = "editor"
    OpenNotebook()
end

function WBF.UI.ContextFyi.CloseSpecial()
    mode = "home"
    editor = nil
    focusKey = nil
    Repaint()
end

local function TypeLabel(kind)
    if kind == "TASK" then
        return "Task"
    end
    if kind == "RECURRING" then
        return "Recurring FYI"
    end
    return "Reference"
end

local function EventName(key)
    local info = WBF.EventTriggers and WBF.EventTriggers.FindCatalog and WBF.EventTriggers.FindCatalog(key) or nil
    return info and info.name or key or "Event"
end

local function CycleType()
    if not editor then
        return
    end
    if editor.fyiType == "REFERENCE" then
        editor.fyiType = "TASK"
    elseif editor.fyiType == "TASK" then
        editor.fyiType = "RECURRING"
    else
        editor.fyiType = "REFERENCE"
    end
    Repaint()
end

local function CycleEvent()
    if not editor or not WBF.EventTriggers or not WBF.EventTriggers.Catalog then
        return
    end
    local catalog = WBF.EventTriggers.Catalog()
    local nextIndex = 1
    for index = 1, #catalog do
        if catalog[index].key == editor.eventKey then
            nextIndex = index + 1
            break
        end
    end
    if nextIndex > #catalog then
        nextIndex = 1
    end
    if catalog[nextIndex] then
        editor.eventKey = catalog[nextIndex].key
    end
    Repaint()
end

local function ReadBoxes()
    if not editor or not board or painting then
        return
    end
    editor.title = board.TitleBox:GetText() or ""
    editor.notes = board.NotesBox:GetText() or ""
    editor.achievementID = board.AchBox:GetText() or ""
    editor.currencyID = board.CurBox:GetText() or ""
    if editor.itemsOn then
        for index = 1, #editor.items do
            if itemBoxes[index] then
                editor.items[index].text = itemBoxes[index]:GetText() or ""
            end
        end
    end
end

local function Commit()
    if not editor or not WBF.ContextFyi or not WBF.ContextFyi.Save then
        return
    end
    ReadBoxes()
    local items = {}
    if editor.itemsOn then
        for index = 1, #editor.items do
            local item = editor.items[index]
            if Trim(item.text or "") ~= "" then
                items[#items + 1] = {
                    id = item.id,
                    text = item.text,
                    completionMode = item.completionMode == "PERMANENT" and "PERMANENT" or "OCCURRENCE",
                }
            end
        end
    end
    local saved = WBF.ContextFyi.Save({
        id = editor.id,
        type = editor.fyiType,
        title = editor.title,
        notes = editor.notes,
        trigger = editor.fyiType == "RECURRING" and {
            type = "WOW_EVENT",
            eventKey = editor.eventKey,
            eventName = EventName(editor.eventKey),
        } or nil,
        items = items,
        achievementID = editor.achievementOn and tonumber(editor.achievementID) or nil,
        currencyID = editor.currencyOn and tonumber(editor.currencyID) or nil,
    })
    if not saved then
        if board and board.Status then
            board.Status:SetText("Add a title. A recurring FYI also needs an event.")
            board.Status:Show()
        end
        return
    end
    local key = saved.trigger and saved.trigger.eventKey or nil
    if key and WBF.ContextFyi.Focus and WBF.ContextFyi.Focus(key) then
        WBF.UI.ContextFyi.OpenFocus(key)
        return
    end
    WBF.UI.ContextFyi.CloseSpecial()
end

local function Place(widget, x, y, width)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", board, "TOPLEFT", x, -y)
    if width and widget.SetWidth then
        widget:SetWidth(width)
    end
    widget:Show()
end

local function AchievementLine(achievement)
    if type(achievement) ~= "table" then
        return nil
    end
    if achievement.missing then
        return achievement.name
    end
    if achievement.completed then
        return "✓ " .. (achievement.name or "Achievement") .. " completed"
    end
    if achievement.current and achievement.required then
        return (achievement.name or "Achievement") .. "  " .. achievement.current .. " / " .. achievement.required
    end
    if achievement.text and achievement.text ~= "" then
        return (achievement.name or "Achievement") .. "  " .. achievement.text
    end
    return achievement.name
end

local function CurrencyLine(currency, eventName)
    if type(currency) ~= "table" or currency.amount == nil then
        if currency and currency.missing then
            return nil
        end
        return nil
    end
    local amount = WBF.Format and WBF.Format.Number and WBF.Format.Number(currency.amount) or tostring(currency.amount)
    if currency.gained and currency.gained > 0 then
        local gained = WBF.Format and WBF.Format.Number and WBF.Format.Number(currency.gained) or tostring(currency.gained)
        local eventLabel = eventName or currency.eventName or "event"
        return (currency.name or "Currency") .. "  " .. amount .. " available  +" .. gained .. " this " .. eventLabel
    end
    return (currency.name or "Currency") .. ": " .. amount
end

local function DrawEditor(width)
    local draft = editor
    local y = 0
    ResetCaptions()
    Place(board.Back, 0, y, 110)
    board.Back.Label:SetText("< Notebook")
    board.Back:SetScript("OnClick", function()
        WBF.UI.ContextFyi.CloseSpecial()
    end)
    y = y + 28
    Place(board.Heading, 0, y, width)
    board.Heading:SetFontObject("GameFontNormalLarge")
    board.Heading:SetText(draft.id and "Edit FYI" or "New FYI")
    Color(board.Heading, WBF.UI.Colors.gold)
    y = y + 26
    Caption("Title", 0, y, width)
    y = y + 16
    painting = true
    Place(board.TitleBox, 8, y, math.max(120, width - 16))
    board.TitleBox:SetText(draft.title or "")
    y = y + 28
    Caption("Type", 0, y, 70)
    Place(board.TypeButton, 76, y - 2, 150)
    board.TypeButton.Label:SetText(TypeLabel(draft.fyiType))
    board.TypeButton:SetScript("OnClick", CycleType)
    y = y + 28
    if draft.fyiType == "RECURRING" then
        Caption("Show when", 0, y, 70)
        local whenButton = board.EventButton
        Place(whenButton, 76, y - 2, math.max(140, math.min(220, width - 90)))
        whenButton.Label:SetText(EventName(draft.eventKey))
        whenButton:SetScript("OnClick", CycleEvent)
        WBF.UI.Tooltip(whenButton, function(tip)
            tip:AddLine("WoW event", 1, 0.82, 0.45)
            tip:AddLine("Click to choose another holiday. The FYI returns each time that event starts.", 0.9, 0.9, 0.9, true)
        end)
        y = y + 26
        Place(board.RepeatText, 76, y, width - 80)
        board.RepeatText:SetText("Repeat  ·  Every occurrence")
        Color(board.RepeatText, WBF.UI.Colors.muted)
        y = y + 20
    end
    Place(board.MoreButton, 0, y, 72)
    board.MoreButton.Label:SetText(draft.more and "Less" or "More")
    board.MoreButton:SetScript("OnClick", function()
        ReadBoxes()
        draft.more = not draft.more
        Repaint()
    end)
    y = y + 26
    if draft.more then
        Place(board.AchButton, 0, y, 120)
        board.AchButton.Label:SetText(draft.achievementOn and "Achievement on" or "Achievement")
        board.AchButton:SetScript("OnClick", function()
            ReadBoxes()
            draft.achievementOn = not draft.achievementOn
            Repaint()
        end)
        if draft.achievementOn then
            Place(board.AchBox, 128, y, 90)
            board.AchBox:SetText(draft.achievementID or "")
        end
        y = y + 26
        Place(board.CurButton, 0, y, 100)
        board.CurButton.Label:SetText(draft.currencyOn and "Currency on" or "Currency")
        board.CurButton:SetScript("OnClick", function()
            ReadBoxes()
            draft.currencyOn = not draft.currencyOn
            Repaint()
        end)
        if draft.currencyOn then
            Place(board.CurBox, 128, y, 90)
            board.CurBox:SetText(draft.currencyID or "")
        end
        y = y + 26
    end
    Place(board.AddItem, 0, y, 88)
    board.AddItem.Label:SetText(draft.itemsOn and "Add item" or "Checklist")
    board.AddItem:SetScript("OnClick", function()
        ReadBoxes()
        draft.itemsOn = true
        draft.items[#draft.items + 1] = { text = "", completionMode = "OCCURRENCE" }
        Repaint()
    end)
    y = y + 26
    if draft.itemsOn then
        for index = 1, #draft.items do
            if index > #itemBoxes then
                break
            end
            local item = draft.items[index]
            Place(itemBoxes[index], 0, y, math.max(80, width - 170))
            itemBoxes[index]:SetText(item.text or "")
            Place(itemModes[index], width - 160, y, 88)
            itemModes[index].Label:SetText(item.completionMode == "PERMANENT" and "Keep" or "Each time")
            itemModes[index]:SetScript("OnClick", function()
                ReadBoxes()
                if item.completionMode == "PERMANENT" then
                    item.completionMode = "OCCURRENCE"
                else
                    item.completionMode = "PERMANENT"
                end
                Repaint()
            end)
            Place(itemRemoves[index], width - 66, y, 64)
            itemRemoves[index]:SetScript("OnClick", function()
                ReadBoxes()
                table.remove(draft.items, index)
                if #draft.items == 0 then
                    draft.itemsOn = false
                end
                Repaint()
            end)
            y = y + 26
        end
    end
    Caption("Notes", 0, y, width)
    y = y + 16
    board.NotesHolder:ClearAllPoints()
    board.NotesHolder:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
    board.NotesHolder:SetSize(math.max(80, width), 72)
    board.NotesHolder:Show()
    board.NotesBox:SetText(draft.notes or "")
    board.NotesBox:Show()
    y = y + 80
    Place(board.Save, 0, y, 64)
    board.Save:SetScript("OnClick", Commit)
    Place(board.Cancel, 72, y, 72)
    board.Cancel:SetScript("OnClick", function()
        WBF.UI.ContextFyi.CloseSpecial()
    end)
    if draft.id then
        Place(board.Delete, 152, y, 64)
        board.Delete:SetScript("OnClick", function()
            if WBF.ContextFyi and WBF.ContextFyi.Delete then
                WBF.ContextFyi.Delete(draft.id)
            end
            WBF.UI.ContextFyi.CloseSpecial()
        end)
    end
    painting = false
    y = y + 28
    return y
end

local function DrawFocus(width)
    local group = focusKey and WBF.ContextFyi and WBF.ContextFyi.Focus and WBF.ContextFyi.Focus(focusKey) or nil
    local y = 0
    Place(board.Back, 0, y, 110)
    board.Back.Label:SetText("< Notebook")
    board.Back:SetScript("OnClick", function()
        WBF.UI.ContextFyi.CloseSpecial()
    end)
    y = y + 28
    if not group then
        Place(board.Heading, 0, y, width)
        board.Heading:SetFontObject("GameFontNormalLarge")
        board.Heading:SetText("No active event")
        Color(board.Heading, WBF.UI.Colors.gold)
        y = y + 24
        Place(board.Sub, 0, y, width)
        board.Sub:SetFontObject("GameFontHighlightSmall")
        board.Sub:SetText("Nothing you saved is relevant right now.")
        Color(board.Sub, WBF.UI.Colors.muted)
        return y + 24
    end
    Place(board.Heading, 0, y, width)
        board.Heading:SetFontObject("GameFontNormalLarge")
        board.Heading:SetText(Shown(group.eventName or "Event"))
    Color(board.Heading, WBF.UI.Colors.gold)
    y = y + 24
    Place(board.Sub, 0, y, width)
    board.Sub:SetFontObject("GameFontHighlightSmall")
    local count = group.count or 0
    local countText = count == 1 and "1 FYI" or (tostring(count) .. " FYIs")
    board.Sub:SetText("Active now  ·  " .. countText)
    Color(board.Sub, WBF.UI.Colors.muted)
    y = y + 22
    local rowIndex = 1
    local fyis = group.fyis or {}
    for index = 1, #fyis do
        local fyi = fyis[index]
        if #fyis > 1 or fyi.title ~= group.eventName then
            local row = Row(rowIndex)
            rowIndex = rowIndex + 1
            Place(row, 0, y, width)
            row:SetHeight(32)
            row.Mark:SetText("")
            row.Title:SetText(Shown(fyi.title or "FYI"))
            Color(row.Title, WBF.UI.Colors.gold)
            row.Detail:SetText(fyi.doneForOccurrence and "Done for this occurrence" or (fyi.type == "REFERENCE" and "Reference" or ""))
            row.tip = fyi.notes
            row.tipTitle = fyi.title
            row:SetScript("OnClick", function()
                WBF.UI.ContextFyi.OpenEditor(fyi.id)
            end)
            y = y + 36
        end
        local achievement = AchievementLine(fyi.achievement)
        local currency = CurrencyLine(fyi.currency, group.eventName)
        if achievement or currency or (fyi.notes and fyi.notes ~= "") then
            local row = Row(rowIndex)
            rowIndex = rowIndex + 1
            Place(row, 0, y, width)
            row.Mark:SetText("")
            row.Title:SetText(Shown(achievement or currency or fyi.notes))
            row.Detail:SetText(Shown(achievement and currency or ""))
            row:SetScript("OnClick", nil)
            y = y + 40
        end
        local items = fyi.items or {}
        for itemIndex = 1, #items do
            local item = items[itemIndex]
            local row = Row(rowIndex)
            rowIndex = rowIndex + 1
            local extra = AchievementLine(item.achievement) or CurrencyLine(item.currency, group.eventName) or ""
            if item.completionMode == "PERMANENT" and extra == "" then
                extra = "Stays completed"
            elseif item.completionMode == "PERMANENT" and extra ~= "" then
                extra = extra .. "  ·  Stays completed"
            end
            Place(row, 0, y, width)
            row:SetHeight(extra ~= "" and 40 or 28)
            row.Mark:SetText(item.done and "✓" or "☐")
            Color(row.Mark, item.done and WBF.UI.Colors.green or WBF.UI.Colors.gold)
            row.Title:SetText(Shown(item.text or ""))
            row.Detail:SetText(Shown(extra))
            row.tip = extra ~= "" and extra or nil
            row.tipTitle = item.text
            row:SetScript("OnClick", function()
                if WBF.ContextFyi and WBF.ContextFyi.SetItemDone then
                    WBF.ContextFyi.SetItemDone(fyi.id, item.id, not item.done)
                end
            end)
            y = y + (extra ~= "" and 44 or 32)
        end
        local actionIndex = (index - 1) * 3
        if fyi.achievement and fyi.achievement.completed and not fyi.permanent then
            local archive = Action(actionIndex + 1, "Archive FYI", 110)
            Place(archive, 0, y, 110)
            archive:SetScript("OnClick", function()
                if WBF.ContextFyi and WBF.ContextFyi.CompletePermanent then
                    WBF.ContextFyi.CompletePermanent(fyi.id)
                end
            end)
            y = y + 26
        end
        if fyi.type == "RECURRING" and not fyi.permanent and not fyi.doneForOccurrence then
            local done = Action(actionIndex + 2, "Done for this occurrence", 180)
            local permanent = Action(actionIndex + 3, "Complete permanently", 160)
            Place(done, 0, y, 180)
            done:SetScript("OnClick", function()
                if WBF.ContextFyi and WBF.ContextFyi.CompleteOccurrence then
                    WBF.ContextFyi.CompleteOccurrence(fyi.id)
                end
            end)
            Place(permanent, 188, y, 160)
            permanent:SetScript("OnClick", function()
                if WBF.ContextFyi and WBF.ContextFyi.CompletePermanent then
                    WBF.ContextFyi.CompletePermanent(fyi.id)
                end
            end)
            y = y + 28
        end
    end
    HideRows(rowIndex)
    if group.last then
        y = y + 8
        Place(board.Status, 0, y, width)
        local last = group.last
        local line = "Last " .. (group.eventName or "event")
        if last.label and last.label ~= "" then
            line = line .. "  ·  " .. last.label
        end
        line = line .. "  ·  " .. tostring(last.completed or 0) .. "/" .. tostring(last.total or 0) .. " FYIs completed"
        if (last.unfinished or 0) > 0 then
            line = line .. "  ·  " .. tostring(last.unfinished) .. " left unfinished"
        end
        board.Status:SetText(Shown(line))
        Color(board.Status, WBF.UI.Colors.muted)
        y = y + 20
    end
    return y
end

local function DrawHome(width)
    -- Standalone Context FYIs were the first event-FYI implementation.
    -- New FYIs now attach a trigger to existing Notebook content instead,
    -- so keep this area only as a compatibility surface for records the
    -- player already created.
    local summaries = WBF.ContextFyi and WBF.ContextFyi.Summaries and WBF.ContextFyi.Summaries() or {}
    if #summaries == 0 then
        HideRows(1)
        return 0
    end

    local y = 0
    local rowIndex = 1
    Place(board.Sub, 0, y, width)
    board.Sub:SetFontObject("GameFontNormal")
    board.Sub:SetText("STANDALONE FYIS (OLDER)")
    Color(board.Sub, WBF.UI.Colors.muted)
    board.AddItem:Hide()
    y = y + 22

    Place(board.Status, 0, y, width)
    board.Status:SetText("These were created with the older separate FYI editor. New FYIs are attached directly to Notebook pages, sections, or blocks.")
    Color(board.Status, WBF.UI.Colors.muted)
    y = y + 34

    for index = 1, #summaries do
        local summary = summaries[index]
        local row = Row(rowIndex)
        rowIndex = rowIndex + 1
        Place(row, 0, y, width)
        row:SetHeight(36)
        row.Mark:SetText(summary.permanent and "✓" or (summary.active and "●" or ""))
        Color(row.Mark, summary.active and WBF.UI.Colors.gold or WBF.UI.Colors.muted)
        row.Title:SetText(Shown(summary.title or "FYI"))
        Color(row.Title, summary.active and WBF.UI.Colors.cream or WBF.UI.Colors.muted)
        row.Detail:SetText(Shown(summary.detail or ""))
        row.tip = summary.detail
        row.tipTitle = summary.title
        row:SetScript("OnClick", function()
            WBF.UI.ContextFyi.OpenEditor(summary.id)
        end)
        y = y + 40
    end
    HideRows(rowIndex)
    return y + 6
end

local function RenderInto(parent, y, width, drawer)
    EnsureBoard(parent)
    HideOwned()
    board:SetParent(parent)
    board:ClearAllPoints()
    board:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    board:SetWidth(math.max(80, width))
    board:Show()
    local height = drawer(math.max(80, width))
    board:SetHeight(math.max(20, height))
    return y + height
end

function WBF.UI.ContextFyi.Draw(parent, y, width)
    if mode == "editor" and editor then
        return RenderInto(parent, y, width, DrawEditor)
    end
    if mode == "focus" then
        return RenderInto(parent, y, width, DrawFocus)
    end
    return y
end

function WBF.UI.ContextFyi.DrawHome(parent, y, width)
    if mode ~= "home" then
        return y
    end
    return RenderInto(parent, y, width, DrawHome)
end

local function EnsureReminder(parent)
    if reminder then
        if parent and reminder:GetParent() ~= parent then
            reminder:SetParent(parent)
        end
        return reminder
    end
    reminder = CreateFrame("Button", nil, parent)
    reminder:RegisterForClicks("LeftButtonUp")
    WBF.UI.BindWheel(reminder)
    local header = reminder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetText("SINCE YOU WERE LAST HERE")
    Color(header, WBF.UI.Colors.gold)
    local body = reminder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 0, -18)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    Color(body, WBF.UI.Colors.cream)
    reminder.Header = header
    reminder.Body = body
    reminder:SetScript("OnClick", function(self)
        if self.eventKey then
            WBF.UI.ContextFyi.OpenFocus(self.eventKey)
        end
    end)
    return reminder
end

function WBF.UI.ContextFyi.DrawReminder(parent, y, width)
    if not WBF.ContextFyi or not WBF.ContextFyi.SinceLastHere then
        return y
    end
    local since = WBF.ContextFyi.SinceLastHere()
    local line = since and since.lines and since.lines[1] or nil
    if not line then
        if reminder then
            reminder:Hide()
        end
        return y
    end
    local block = EnsureReminder(parent)
    local text = line.headline .. "\n" .. line.detail
    if line.last and line.last.completed and line.last.total then
        text = text .. "\nLast time: " .. tostring(line.last.completed) .. "/" .. tostring(line.last.total) .. " FYIs completed"
    end
    block.Body:SetWidth(math.max(80, width))
    block.Body:SetText(Shown(text))
    block.eventKey = line.eventKey
    local height = 18 + 14 * 3
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    block:SetSize(math.max(80, width), height)
    block:Show()
    return y + height + 8
end

local function EnsureToast()
    if toast then
        return toast
    end
    toast = CreateFrame("Frame", "WarbandFYIContextToast", UIParent, "BackdropTemplate")
    toast:SetSize(320, 180)
    toast:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -380)
    toast:SetFrameStrata("HIGH")
    toast:SetClampedToScreen(true)
    toast:Hide()
    WBF.UI.Paint(toast, WBF.UI.Colors.window, WBF.UI.Colors.windowBorder, 1)
    local title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetPoint("TOPRIGHT", -12, -10)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    Color(title, WBF.UI.Colors.gold)
    local sub = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", 12, -30)
    sub:SetPoint("TOPRIGHT", -12, -30)
    sub:SetJustifyH("LEFT")
    Color(sub, WBF.UI.Colors.muted)
    local body = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 12, -50)
    body:SetPoint("TOPRIGHT", -12, -50)
    body:SetJustifyH("LEFT")
    body:SetWordWrap(true)
    Color(body, WBF.UI.Colors.cream)
    local open = Button(toast, "Open FYIs", 90, 20)
    open:SetPoint("BOTTOMLEFT", 12, 12)
    local later = Button(toast, "Later", 64, 20)
    later:SetPoint("LEFT", open, "RIGHT", 8, 0)
    toast.Title = title
    toast.Sub = sub
    toast.Body = body
    toast.Open = open
    toast.Later = later
    open:SetScript("OnClick", function()
        local key = toast.eventKey
        local signature = toast.signature
        if WBF.ContextFyi and WBF.ContextFyi.Acknowledge then
            WBF.ContextFyi.Acknowledge(signature)
        end
        toast:Hide()
        if key then
            WBF.UI.ContextFyi.OpenFocus(key)
        end
    end)
    later:SetScript("OnClick", function()
        if WBF.ContextFyi and WBF.ContextFyi.Acknowledge then
            WBF.ContextFyi.Acknowledge(toast.signature)
        end
        toast:Hide()
    end)
    return toast
end

function WBF.UI.ContextFyi.ShowNotice(notice)
    if type(notice) ~= "table" or type(notice.primary) ~= "table" then
        return false
    end
    local frame = EnsureToast()
    local primary = notice.primary
    local count = primary.count or 0
    frame.Title:SetText(Shown("FYI — " .. (primary.eventName or "Event") .. " is active"))
    frame.Sub:SetText(Shown("You have " .. count .. (count == 1 and " FYI" or " FYIs") .. " for this event."))
    local lines = {}
    local source = primary.lines or {}
    for index = 1, #source do
        lines[#lines + 1] = "•  " .. source[index]
    end
    if notice.groups and #notice.groups > 1 then
        local extra = {}
        for index = 2, #notice.groups do
            extra[#extra + 1] = notice.groups[index].eventName or "Event"
        end
        lines[#lines + 1] = "Also active: " .. table.concat(extra, ", ")
    end
    frame.Body:SetText(Shown(table.concat(lines, "\n")))
    frame.signature = notice.signature
    frame.eventKey = primary.eventKey
    local height = 92 + math.min(4, #lines) * 16
    frame:SetHeight(math.max(120, height))
    frame:Show()
    return true
end
