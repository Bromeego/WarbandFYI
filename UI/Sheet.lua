local _, WBF = ...

-- Compact window over one notebook page or section. Closing the main
-- window leaves this one up. Reload does not open it again.
WBF.UI.Sheet = {}

local frame
local header
local titleText
local subtitleText
local scroll
local scrollChild
local bar
local footer
local lockButton
local scaleButton
local opacityButton
local hideButton
local hideMark
local grip
local noticeText
local measure
local notice
local applying = false
local pools = {}

local function Shown(text)
    if type(text) ~= "string" then
        return ""
    end
    return (text:gsub("|", "||"))
end

local function Color(widget, color)
    widget:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function Pool(name, factory)
    if not pools[name] then
        pools[name] = WBF.UI.CreatePool(factory)
    end
    return pools[name]
end

local function Release()
    for _, pool in pairs(pools) do
        WBF.UI.ReleasePool(pool)
    end
end

local function Wheel(delta)
    if not scroll then
        return
    end
    local range = scroll:GetVerticalScrollRange()
    if range <= 1 then
        scroll:SetVerticalScroll(0)
        return
    end
    local nextValue = scroll:GetVerticalScroll() - (delta * 36)
    if nextValue < 0 then
        nextValue = 0
    elseif nextValue > range then
        nextValue = range
    end
    scroll:SetVerticalScroll(nextValue)
end

local function BindSheetWheel(widget)
    widget:EnableMouseWheel(true)
    widget:SetScript("OnMouseWheel", function(_, delta)
        Wheel(delta)
    end)
end

local function SaveChrome()
    if not frame or applying or not WBF.NotebookSheet then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    WBF.NotebookSheet.Update({
        point = point,
        relPoint = relativePoint,
        x = x,
        y = y,
        width = frame:GetWidth(),
        height = frame:GetHeight(),
    })
end

local function ApplyChrome()
    local settings = WBF.NotebookSheet and WBF.NotebookSheet.Settings()
    if not frame or not settings then
        return
    end
    applying = true
    frame:SetScale(settings.scale or 1)
    frame:SetAlpha(settings.opacity or 1)
    frame:SetSize(settings.width or 420, settings.height or 520)
    frame:ClearAllPoints()
    if settings.point then
        frame:SetPoint(settings.point, UIParent, settings.relPoint or settings.point, settings.x or 0, settings.y or 0)
    else
        frame:SetPoint("CENTER")
    end
    local locked = settings.locked and true or false
    frame:SetMovable(not locked)
    frame:SetResizable(not locked)
    if grip then
        grip:SetShown(not locked)
    end
    if lockButton and lockButton.Label then
        lockButton.Label:SetText(locked and "Unlock" or "Lock")
    end
    if scaleButton and scaleButton.Label then
        local scaleLabel = WBF.NotebookSheet.ChromeLabel("scale", settings.scale)
        scaleButton.Label:SetText(scaleLabel)
        scaleButton:SetWidth(math.max(76, 12 + (#scaleLabel * 6)))
    end
    if opacityButton and opacityButton.Label then
        local opacityLabel = WBF.NotebookSheet.ChromeLabel("opacity", settings.opacity)
        opacityButton.Label:SetText(opacityLabel)
        opacityButton:SetWidth(math.max(92, 12 + (#opacityLabel * 6)))
    end
    if footer and lockButton and scaleButton and opacityButton and hideButton then
        local wide = (frame:GetWidth() or 420) >= 430
        footer:SetHeight(wide and 22 or 44)
        lockButton:ClearAllPoints()
        scaleButton:ClearAllPoints()
        opacityButton:ClearAllPoints()
        hideButton:ClearAllPoints()
        if wide then
            lockButton:SetPoint("LEFT", footer, "LEFT", 0, 0)
            scaleButton:SetPoint("LEFT", lockButton, "RIGHT", 4, 0)
            opacityButton:SetPoint("LEFT", scaleButton, "RIGHT", 4, 0)
            hideButton:SetPoint("LEFT", opacityButton, "RIGHT", 8, 0)
        else
            lockButton:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
            scaleButton:SetPoint("LEFT", lockButton, "RIGHT", 4, 0)
            opacityButton:SetPoint("LEFT", scaleButton, "RIGHT", 4, 0)
            hideButton:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", 0, 0)
        end
    end
    if hideMark then
        hideMark:SetShown(settings.hideCompleted and true or false)
    end
    applying = false
end

local function UpdateScroll()
    if not scroll or not bar then
        return
    end
    WBF.UI.SyncScrollBar(scroll, bar)
end

local function Wrapped(text, width)
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

local function TextButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 18)
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

local function HeadingPool()
    return Pool("sheetHeading", function(parent)
        local row = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row:SetJustifyH("LEFT")
        row:SetWordWrap(false)
        Color(row, WBF.UI.Colors.gold)
        return row
    end)
end

local function MutedPool()
    return Pool("sheetMuted", function(parent)
        local row = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetJustifyH("LEFT")
        row:SetWordWrap(true)
        Color(row, WBF.UI.Colors.muted)
        return row
    end)
end

local function BlockPool()
    return Pool("sheetBlock", function(parent)
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        card:EnableMouse(true)
        BindSheetWheel(card)
        local text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        local sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(true)
        Color(sub, WBF.UI.Colors.muted)
        local hint = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetJustifyH("LEFT")
        local copy = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        copy:SetJustifyH("LEFT")
        copy:Hide()
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        local barBg = card:CreateTexture(nil, "BACKGROUND")
        barBg:SetHeight(5)
        barBg:SetColorTexture(WBF.UI.Colors.track[1], WBF.UI.Colors.track[2], WBF.UI.Colors.track[3], WBF.UI.Colors.track[4])
        local fill = card:CreateTexture(nil, "ARTWORK")
        fill:SetHeight(5)
        fill:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 1)
        local link = WBF.UI.EditBox(card, nil, 18)
        link:SetFontObject(GameFontHighlightSmall)
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
        BindSheetWheel(link)
        card.Text = text
        card.Sub = sub
        card.Hint = hint
        card.Copy = copy
        card.Icon = icon
        card.Bar = barBg
        card.Fill = fill
        card.Link = link
        card.Criteria, card.CriteriaToggle = WBF.UI.MakeCriteriaWidgets(card)
        return card
    end)
end

local function CheckPool()
    return Pool("sheetCheck", function(parent)
        local row = CreateFrame("Button", nil, parent)
        row:SetHeight(18)
        row:RegisterForClicks("LeftButtonUp")
        BindSheetWheel(row)
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(14, 14)
        box:SetPoint("LEFT", 6, 0)
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
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", box, "RIGHT", 6, 0)
        label:SetPoint("RIGHT", -6, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.Box = box
        row.Mark = mark
        row.Text = label
        return row
    end)
end

local function ResetCard(card)
    if card.PetAdd then card.PetAdd:Hide() end
    for _, row in ipairs(card.PetRows or {}) do row:Hide() end
    card:SetScript("OnMouseUp", nil)
    card:SetScript("OnEnter", nil)
    card:SetScript("OnLeave", nil)
    card.Icon:Hide()
    card.Sub:Hide()
    card.Hint:Hide()
    card.Hint:SetJustifyH("LEFT")
    if card.Copy then
        card.Copy:Hide()
    end
    card.Bar:Hide()
    card.Fill:Hide()
    card.Link:Hide()
    if card.Criteria then
        card.Criteria:Hide()
    end
    if card.CriteriaToggle then
        card.CriteriaToggle:Hide()
    end
    card.Text:SetText("")
    if card.Text.SetMaxLines then
        card.Text:SetMaxLines(4)
    end
end

local function ShowLink(card, url, y, width)
    card.Link._url = url
    card.Link._lock = true
    card.Link:SetText(url)
    card.Link._lock = false
    card.Link:ClearAllPoints()
    card.Link:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -y)
    card.Link:SetWidth(math.max(40, width - 20))
    card.Link:Show()
    card.Copy:ClearAllPoints()
    card.Copy:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -(y + 16))
    card.Copy:SetText("Ctrl+C to copy")
    Color(card.Copy, WBF.UI.Colors.muted)
    card.Copy:Show()
    return y + 32
end

local function DrawBlock(block, x, y, width)
    local card = WBF.UI.Acquire(BlockPool(), scrollChild)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, -y)
    WBF.UI.Paint(card, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    ResetCard(card)
    local textX = 8
    local height = 36
    if block.type == "pet_level_list" then
        local settings = WBF.NotebookSheet.Settings()
        return WBF.UI.NotebookPets.Draw(card, block, width, settings and settings.hideCompleted)
    elseif block.type == "achievement" then
        local progress = WBF.PlanAchievements and WBF.PlanAchievements.Progress and WBF.PlanAchievements.Progress(block.achievementID) or nil
        local name = (progress and progress.name) or ("Achievement " .. tostring(block.achievementID or ""))
        if progress and progress.icon then
            card.Icon:SetTexture(progress.icon)
            card.Icon:ClearAllPoints()
            card.Icon:SetPoint("TOPLEFT", 6, -6)
            card.Icon:Show()
            textX = 32
        end
        local textW = math.max(20, width - textX - 8)
        card.Text:ClearAllPoints()
        card.Text:SetPoint("TOPLEFT", textX, -6)
        card.Text:SetWidth(textW)
        if card.Text.SetMaxLines then
            card.Text:SetMaxLines(1)
        end
        card.Text:SetText(Shown(name))
        Color(card.Text, WBF.UI.Colors.cream)
        local cursor = 22
        local description = progress and progress.description or nil
        if description and description ~= "" then
            card.Sub:ClearAllPoints()
            card.Sub:SetPoint("TOPLEFT", textX, -20)
            card.Sub:SetWidth(textW)
            if card.Sub.SetMaxLines then
                card.Sub:SetMaxLines(2)
            end
            card.Sub:SetText(Shown(description))
            card.Sub:Show()
            cursor = 22 + math.min(28, Wrapped(description, textW))
        end
        local line = progress and WBF.PlanAchievements.ProgressText and WBF.PlanAchievements.ProgressText(progress) or nil
        if line then
            card.Hint:ClearAllPoints()
            card.Hint:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -cursor)
            card.Hint:SetWidth(math.max(20, width - 16))
            card.Hint:SetJustifyH("LEFT")
            card.Hint:SetText(Shown(line))
            Color(card.Hint, WBF.UI.Colors.muted)
            card.Hint:Show()
            cursor = cursor + 14
        end
        if progress and progress.percent and progress.required then
            local barW = math.max(20, width - 16)
            card.Bar:ClearAllPoints()
            card.Bar:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -cursor)
            card.Bar:SetSize(barW, 5)
            card.Bar:Show()
            card.Fill:ClearAllPoints()
            card.Fill:SetPoint("TOPLEFT", card.Bar, "TOPLEFT", 0, 0)
            card.Fill:SetSize(math.max(1, math.floor(barW * math.max(0, math.min(100, progress.percent)) / 100)), 5)
            card.Fill:Show()
            cursor = cursor + 10
        end
        if progress and WBF.PlanAchievements.CriteriaDetail and WBF.NotebookSheet and WBF.NotebookSheet.AchievementDetail and card.Criteria then
            local detail = WBF.NotebookSheet.AchievementDetail(progress, WBF.PlanAchievements.CriteriaExpanded(block.achievementID))
            cursor = WBF.UI.PlaceCriteriaDetail(card, card.Criteria, card.CriteriaToggle, detail, 8, cursor + 2, math.max(20, width - 16), function()
                WBF.PlanAchievements.ToggleCriteria(block.achievementID)
                if WBF.Notebook and WBF.Notebook.RefreshOpen then
                    WBF.Notebook.RefreshOpen()
                end
            end)
        end
        if type(block.sourceURL) == "string" and block.sourceURL ~= "" then
            cursor = ShowLink(card, block.sourceURL, cursor + 2, width)
        end
        height = math.max(40, cursor + 6)
    elseif block.type == "waypoint" then
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
        card.Text:ClearAllPoints()
        card.Text:SetPoint("TOPLEFT", 8, -6)
        card.Text:SetWidth(math.max(20, width - 96))
        if card.Text.SetMaxLines then
            card.Text:SetMaxLines(1)
        end
        card.Text:SetText(Shown(title))
        Color(card.Text, WBF.UI.Colors.cream)
        card.Sub:ClearAllPoints()
        card.Sub:SetPoint("TOPLEFT", 8, -22)
        card.Sub:SetWidth(math.max(20, width - 96))
        card.Sub:SetText(Shown(detail or ""))
        card.Sub:Show()
        card.Hint:ClearAllPoints()
        card.Hint:SetPoint("RIGHT", card, "RIGHT", -8, -4)
        card.Hint:SetJustifyH("RIGHT")
        card.Hint:SetText("Set waypoint")
        Color(card.Hint, WBF.UI.Colors.gold)
        card.Hint:Show()
        height = 42
        card:SetScript("OnMouseUp", function(_, button)
            if button ~= "LeftButton" then
                return
            end
            local ok = WBF.NotebookSheet.Use(block)
            notice = ok and nil or "Couldn't set that waypoint."
            WBF.UI.Sheet.Refresh()
        end)
    elseif block.type == "checklist" then
        local items = WBF.NotebookSheet.VisibleItems(block)
        local savedCount = type(block.items) == "table" and #block.items or 0
        card.Text:ClearAllPoints()
        card.Text:SetPoint("TOPLEFT", 8, -4)
        card.Text:SetWidth(math.max(20, width - 16))
        if #items == 0 and savedCount > 0 then
            card.Text:SetText("All items done")
            Color(card.Text, WBF.UI.Colors.muted)
            height = 24
        else
            card.Text:SetText("")
            local cursor = 4
            for index = 1, #items do
                local item = items[index]
                local row = WBF.UI.Acquire(CheckPool(), card)
                row:SetParent(card)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -cursor)
                row:SetWidth(width)
                row.Mark:SetShown(item.done and true or false)
                row.Text:SetText(Shown(item.text or ""))
                Color(row.Text, item.done and WBF.UI.Colors.muted or WBF.UI.Colors.cream)
                row:SetScript("OnClick", function()
                    WBF.Notebook.ToggleChecklistItem(block.id, item.id)
                end)
                cursor = cursor + 18
            end
            height = math.max(24, cursor + 4)
        end
    elseif block.type == "resource" then
        local view = WBF.Resources and WBF.Resources.NotebookView and WBF.Resources.NotebookView(block.resourceKey) or nil
        local title = (view and view.name) or block.resourceKey or "Resource"
        local detail = "No balance yet"
        if view and view.amount ~= nil then
            local total = WBF.Format.Number(view.amount)
            if view.accountWide then
                detail = total .. "   Warband"
            elseif view.character ~= nil and view.character ~= view.amount then
                detail = "You " .. WBF.Format.Number(view.character) .. "    Warband " .. total
            else
                detail = total
            end
        elseif not view then
            detail = "This resource is no longer tracked."
        end
        if view and view.icon then
            card.Icon:SetTexture(view.icon)
            card.Icon:ClearAllPoints()
            card.Icon:SetPoint("TOPLEFT", 6, -6)
            card.Icon:Show()
            textX = 32
        end
        card.Text:ClearAllPoints()
        card.Text:SetPoint("TOPLEFT", textX, -6)
        card.Text:SetWidth(math.max(20, width - textX - 8))
        if card.Text.SetMaxLines then
            card.Text:SetMaxLines(1)
        end
        card.Text:SetText(Shown(title))
        Color(card.Text, WBF.UI.Colors.cream)
        card.Sub:ClearAllPoints()
        card.Sub:SetPoint("TOPLEFT", textX, -22)
        card.Sub:SetWidth(math.max(20, width - textX - 8))
        card.Sub:SetText(Shown(detail))
        card.Sub:Show()
        height = 42
        if type(block.sourceURL) == "string" and block.sourceURL ~= "" then
            height = ShowLink(card, block.sourceURL, 40, width) + 6
        end
    elseif block.type == "reference" then
        if WBF.NotebookSmart and WBF.NotebookSmart.Prepare then
            WBF.NotebookSmart.Prepare(block)
        end
        local info = (WBF.NotebookSmart and WBF.NotebookSmart.Describe and WBF.NotebookSmart.Describe(block)) or { title = "Link" }
        if info.icon then
            card.Icon:SetTexture(info.icon)
            card.Icon:ClearAllPoints()
            card.Icon:SetPoint("TOPLEFT", 6, -6)
            card.Icon:Show()
            textX = 32
        end
        card.Text:ClearAllPoints()
        card.Text:SetPoint("TOPLEFT", textX, -6)
        card.Text:SetWidth(math.max(20, width - textX - 8))
        if card.Text.SetMaxLines then
            card.Text:SetMaxLines(2)
        end
        card.Text:SetText(Shown(info.title or "Link"))
        Color(card.Text, WBF.UI.Colors.cream)
        local cursor = 24
        if info.detail and info.detail ~= "" then
            card.Sub:ClearAllPoints()
            card.Sub:SetPoint("TOPLEFT", textX, -22)
            card.Sub:SetWidth(math.max(20, width - textX - 8))
            card.Sub:SetText(Shown(info.detail))
            card.Sub:Show()
            cursor = 38
        end
        if info.url then
            cursor = ShowLink(card, info.url, cursor, width)
        end
        height = math.max(36, cursor + 6)
    else
        local body = block.text or ""
        card.Text:ClearAllPoints()
        card.Text:SetPoint("TOPLEFT", 8, -6)
        card.Text:SetWidth(math.max(20, width - 16))
        card.Text:SetText(Shown(body))
        Color(card.Text, WBF.UI.Colors.cream)
        height = math.max(28, math.min(96, Wrapped(body, width - 16)) + 12)
        if body ~= "" then
            card:SetScript("OnEnter", function(owner)
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                GameTooltip:SetText(Shown(body), 1, 0.82, 0.45, 1, true)
                GameTooltip:Show()
            end)
            card:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
    end
    card:SetSize(width, height)
    return height
end

local function Render(view)
    Release()
    local width = scroll:GetWidth()
    if width < 40 then
        width = 280
    end
    local y = 4
    if notice then
        noticeText:ClearAllPoints()
        noticeText:SetParent(scrollChild)
        noticeText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        noticeText:SetWidth(width)
        noticeText:SetText(Shown(notice))
        noticeText:Show()
        y = y + 16
    else
        noticeText:Hide()
    end
    local page = view.page
    local sectionOnly = view.kind == "section"
    if sectionOnly then
        titleText:SetText(Shown(page.title or "Notebook"))
        subtitleText:SetText(Shown(view.sections[1] and view.sections[1].title or ""))
        subtitleText:Show()
    else
        titleText:SetText(Shown(page.title or "Notebook"))
        if WBF.Notebook.ShowsSummary(page, true) then
            subtitleText:SetText(Shown(page.summary))
            subtitleText:Show()
        else
            subtitleText:Hide()
        end
    end
    header:SetHeight(subtitleText:IsShown() and 36 or 24)
    if #view.sections == 0 then
        local empty = WBF.UI.Acquire(MutedPool(), scrollChild)
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        empty:SetWidth(width)
        empty:SetText("Nothing on this page yet.")
        y = y + 18
    end
    for index = 1, #view.sections do
        local section = view.sections[index]
        if not sectionOnly then
            local heading = WBF.UI.Acquire(HeadingPool(), scrollChild)
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            heading:SetWidth(width)
            heading:SetText(Shown(section.title or "Section"))
            y = y + 18
        end
        local blocks = WBF.Notebook.Blocks(section.id)
        if #blocks == 0 then
            local empty = WBF.UI.Acquire(MutedPool(), scrollChild)
            empty:ClearAllPoints()
            empty:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            empty:SetWidth(width)
            empty:SetText("Nothing in this section yet.")
            y = y + 16
        end
        local columns = WBF.NotebookSheet.Columns(width)
        local gap = 6
        local colW = columns == 1 and width or math.floor((width - gap) / 2)
        local colY = { y, y }
        for blockIndex = 1, #blocks do
            local block = blocks[blockIndex]
            local wide = WBF.NotebookSheet.FullWidth(block, columns)
            if wide then
                local top = math.max(colY[1], colY[2])
                local blockHeight = DrawBlock(block, 0, top, width)
                colY[1] = top + blockHeight + gap
                colY[2] = colY[1]
            else
                local col = (columns == 2 and colY[2] < colY[1]) and 2 or 1
                local px = (col - 1) * (colW + gap)
                local blockHeight = DrawBlock(block, px, colY[col], colW)
                colY[col] = colY[col] + blockHeight + gap
            end
        end
        y = math.max(colY[1], colY[2]) + 6
    end
    scrollChild:SetWidth(width)
    scrollChild:SetHeight(math.max(y + 8, scroll:GetHeight()))
    UpdateScroll()
end

function WBF.UI.Sheet.Refresh()
    if not frame or not frame:IsShown() or not WBF.NotebookSheet then
        return
    end
    local view = WBF.NotebookSheet.View()
    if not view then
        frame:Hide()
        return
    end
    local offset = scroll:GetVerticalScroll() or 0
    Render(view)
    local range = scroll:GetVerticalScrollRange() or 0
    if offset > range then
        offset = range
    end
    if offset < 0 then
        offset = 0
    end
    scroll:SetVerticalScroll(offset)
    UpdateScroll()
end

local function ShowSheet()
    ApplyChrome()
    frame:Show()
    WBF.UI.Sheet.Refresh()
end

function WBF.UI.Sheet.OpenPage(pageId)
    if not WBF.NotebookSheet or not WBF.NotebookSheet.Open({ kind = "page", pageId = pageId }) then
        return
    end
    WBF.UI.Sheet.Ensure()
    notice = nil
    ShowSheet()
end

function WBF.UI.Sheet.OpenSection(sectionId)
    if not WBF.NotebookSheet or not WBF.NotebookSheet.Open({ kind = "section", sectionId = sectionId }) then
        return
    end
    WBF.UI.Sheet.Ensure()
    notice = nil
    ShowSheet()
end

function WBF.UI.Sheet.Ensure()
    if frame then
        return frame
    end
    frame = CreateFrame("Frame", "WarbandFYISheet", UIParent, "BackdropTemplate")
    frame:SetSize(420, 520)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(300, 240, 900, 800)
    else
        frame:SetMinResize(300, 240)
        frame:SetMaxResize(900, 800)
    end
    WBF.UI.Paint(frame, WBF.UI.Colors.window, WBF.UI.Colors.windowBorder, 2)
    frame:Hide()
    frame:SetScript("OnHide", function()
        if frame.ready and WBF.NotebookSheet then
            WBF.NotebookSheet.Close()
        end
    end)
    frame:SetScript("OnSizeChanged", function(self)
        if applying or not self:IsShown() then
            return
        end
        WBF.UI.Sheet.Refresh()
    end)

    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 8, -6)
    header:SetPoint("TOPRIGHT", -28, -6)
    header:SetHeight(36)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        local settings = WBF.NotebookSheet.Settings()
        if settings and settings.locked then
            return
        end
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveChrome()
    end)
    BindSheetWheel(header)

    titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", 2, -1)
    titleText:SetPoint("TOPRIGHT", -2, -1)
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    Color(titleText, WBF.UI.Colors.gold)
    subtitleText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -1)
    subtitleText:SetPoint("TOPRIGHT", titleText, "BOTTOMRIGHT", 0, -1)
    subtitleText:SetJustifyH("LEFT")
    subtitleText:SetWordWrap(false)
    Color(subtitleText, WBF.UI.Colors.muted)

    WBF.UI.CloseButton(frame)

    footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", 8, 6)
    footer:SetPoint("BOTTOMRIGHT", -8, 6)
    footer:SetHeight(22)
    BindSheetWheel(footer)

    lockButton = TextButton(footer, "Lock", 58)
    lockButton:SetPoint("LEFT", 0, 0)
    lockButton:SetScript("OnClick", function()
        WBF.NotebookSheet.Toggle("locked")
        ApplyChrome()
    end)
    scaleButton = TextButton(footer, "Scale 100%", 86)
    scaleButton:SetPoint("LEFT", lockButton, "RIGHT", 4, 0)
    scaleButton:SetScript("OnClick", function()
        WBF.NotebookSheet.Cycle("scale", 1)
        ApplyChrome()
    end)
    scaleButton:SetScript("OnEnter", function(self)
        WBF.UI.Paint(self, WBF.UI.Colors.cardHover, WBF.UI.Colors.gold)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Scale", 1, 0.82, 0.45)
        WBF.UI.AddTip(GameTooltip, "Click to step the sheet size.", WBF.UI.Colors.tipText, true)
        GameTooltip:Show()
    end)
    scaleButton:SetScript("OnLeave", function(self)
        WBF.UI.Paint(self, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        GameTooltip:Hide()
    end)
    opacityButton = TextButton(footer, "Opacity 100%", 102)
    opacityButton:SetPoint("LEFT", scaleButton, "RIGHT", 4, 0)
    opacityButton:SetScript("OnClick", function()
        WBF.NotebookSheet.Cycle("opacity", 1)
        ApplyChrome()
    end)
    opacityButton:SetScript("OnEnter", function(self)
        WBF.UI.Paint(self, WBF.UI.Colors.cardHover, WBF.UI.Colors.gold)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Opacity", 1, 0.82, 0.45)
        WBF.UI.AddTip(GameTooltip, "Click to step how solid the sheet is.", WBF.UI.Colors.tipText, true)
        GameTooltip:Show()
    end)
    opacityButton:SetScript("OnLeave", function(self)
        WBF.UI.Paint(self, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        GameTooltip:Hide()
    end)

    hideButton = CreateFrame("Button", nil, footer)
    hideButton:SetSize(92, 18)
    hideButton:SetPoint("LEFT", opacityButton, "RIGHT", 8, 0)
    BindSheetWheel(hideButton)
    local hideBox = hideButton:CreateTexture(nil, "BACKGROUND")
    hideBox:SetSize(12, 12)
    hideBox:SetPoint("LEFT", 0, 0)
    hideBox:SetColorTexture(WBF.UI.Colors.goldDim[1], WBF.UI.Colors.goldDim[2], WBF.UI.Colors.goldDim[3], 1)
    hideMark = hideButton:CreateTexture(nil, "ARTWORK")
    hideMark:SetPoint("TOPLEFT", hideBox, "TOPLEFT", 2, -2)
    hideMark:SetPoint("BOTTOMRIGHT", hideBox, "BOTTOMRIGHT", -2, 2)
    hideMark:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 1)
    local hideLabel = hideButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideLabel:SetPoint("LEFT", hideBox, "RIGHT", 4, 0)
    hideLabel:SetText("Hide done")
    Color(hideLabel, WBF.UI.Colors.cream)
    hideButton:SetScript("OnClick", function()
        WBF.NotebookSheet.Toggle("hideCompleted")
        ApplyChrome()
        WBF.UI.Sheet.Refresh()
    end)

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -12, 6)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        Wheel(delta)
    end)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(280, 40)
    scroll:SetScrollChild(scrollChild)
    BindSheetWheel(scrollChild)

    measure = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    measure:Hide()
    noticeText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noticeText:SetJustifyH("LEFT")
    Color(noticeText, WBF.UI.Colors.muted)
    noticeText:Hide()

    bar = WBF.UI.ScrollBar(scroll, nil, 28)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 10, -2)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 10, 2)
    scroll:SetScript("OnScrollRangeChanged", UpdateScroll)
    scroll:SetScript("OnVerticalScroll", UpdateScroll)

    grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function()
        local settings = WBF.NotebookSheet.Settings()
        if settings and settings.locked then
            return
        end
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveChrome()
        WBF.UI.Sheet.Refresh()
    end)
    local gripMark = grip:CreateTexture(nil, "ARTWORK")
    gripMark:SetSize(10, 10)
    gripMark:SetPoint("CENTER")
    gripMark:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 0.7)

    frame.ready = true
    return frame
end
