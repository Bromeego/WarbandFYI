local _, WBF = ...

WBF.UI.Detail = {}

local root
local titleText
local backButton
local backLabel
local subtitleText
local summaryText
local noteText
local headlineLabel
local headlineText
local footerText

local function ColorOf(color, fallback)
    if type(color) == "table" then
        return color[1], color[2], color[3]
    end
    if type(color) == "string" and WBF.UI.Colors[color] then
        local swatch = WBF.UI.Colors[color]
        return swatch[1], swatch[2], swatch[3]
    end
    local swatch = fallback or WBF.UI.Colors.cream
    return swatch[1], swatch[2], swatch[3]
end

local function RowPool()
    return WBF.UI.Pool("detailRow", function(parent)
        local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
        frame:RegisterForClicks("LeftButtonUp")
        WBF.UI.BindWheel(frame)
        local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.04)
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 8, -8)
        local value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        value:SetPoint("TOPRIGHT", -10, -10)
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(false)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        local lines = {}
        for index = 1, 6 do
            local line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            line:SetJustifyH("LEFT")
            line:SetWordWrap(false)
            line:Hide()
            lines[index] = line
        end
        frame.Icon = icon
        frame.Value = value
        frame.Title = title
        frame.Lines = lines

        frame.Apply = function(self, row, width)
            self:SetWidth(width)
            if row.metric then
                self.Icon:Hide()
                for index = 1, #self.Lines do
                    self.Lines[index]:Hide()
                end
                local hasValue = row.value and row.value ~= ""
                self.Value:ClearAllPoints()
                self.Value:SetPoint("RIGHT", -2, 0)
                if hasValue then
                    self.Value:SetText(row.value)
                    self.Value:SetTextColor(ColorOf(row.valueColor, WBF.UI.Colors.cream))
                    self.Value:Show()
                else
                    self.Value:SetText("")
                    self.Value:Hide()
                end
                self.Title:ClearAllPoints()
                self.Title:SetPoint("LEFT", 2, 0)
                if hasValue then
                    self.Title:SetPoint("RIGHT", self.Value, "LEFT", -12, 0)
                else
                    self.Title:SetPoint("RIGHT", self, "RIGHT", -2, 0)
                end
                self.Title:SetText(row.title or "")
                self.Title:SetTextColor(ColorOf(row.titleColor or "muted", WBF.UI.Colors.muted))
                self:SetHeight(20)
                WBF.UI.Paint(self, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
                self:SetScript("OnEnter", nil)
                self:SetScript("OnLeave", nil)
                self:SetScript("OnMouseDown", nil)
                self:SetScript("OnMouseUp", nil)
                self:SetScript("OnClick", nil)
                return
            end
            local showIcon = row.event or row.iconEvent or row.icon or row.atlases or row.fallback
            if row.event then
                self.Icon:Show()
                WBF.UI.ApplyEventIcon(self.Icon, row.event)
            elseif row.iconEvent then
                self.Icon:Show()
                WBF.UI.ApplyEventIcon(self.Icon, row.iconEvent)
            elseif row.icon then
                self.Icon:Show()
                self.Icon:SetTexture(row.icon)
            elseif row.atlases or row.fallback then
                self.Icon:Show()
                WBF.UI.SetAtlasChain(self.Icon, row.atlases, row.fallback)
            else
                self.Icon:Hide()
            end

            local left = showIcon and 44 or 10
            self.Value:ClearAllPoints()
            self.Value:SetPoint("TOPRIGHT", -10, -10)
            if row.value and row.value ~= "" then
                self.Value:SetText(row.value)
                self.Value:SetTextColor(ColorOf(row.valueColor, WBF.UI.Colors.cream))
                self.Value:Show()
            else
                self.Value:SetText("")
                self.Value:Hide()
            end

            self.Title:ClearAllPoints()
            self.Title:SetPoint("TOPLEFT", left, -10)
            if self.Value:IsShown() then
                self.Title:SetPoint("RIGHT", self.Value, "LEFT", -8, 0)
            else
                self.Title:SetPoint("RIGHT", self, "RIGHT", -10, 0)
            end
            self.Title:SetText(row.title or "")
            self.Title:SetTextColor(ColorOf(row.titleColor, WBF.UI.Colors.cream))

            local shown = 0
            local previous = self.Title
            for index = 1, #self.Lines do
                local line = self.Lines[index]
                local data = row.lines and row.lines[index]
                line:ClearAllPoints()
                if data and data.text and data.text ~= "" then
                    line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -1)
                    line:SetPoint("RIGHT", self, "RIGHT", -10, 0)
                    line:SetText(data.text)
                    if data.r then
                        line:SetTextColor(data.r, data.g, data.b)
                    else
                        line:SetTextColor(ColorOf(data.color, WBF.UI.Colors.muted))
                    end
                    line:Show()
                    previous = line
                    shown = shown + 1
                else
                    line:Hide()
                end
            end

            local height = 16 + 16 + shown * 15
            if row.compact then
                height = 10 + 16 + shown * 14
                if height < 28 then
                    height = 28
                end
            elseif height < 40 then
                height = 40
            end
            self:SetHeight(height)

            if row.card then
                WBF.UI.PaintCard(self, "idle")
            else
                WBF.UI.Paint(self, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
            end

            local collectionKind = row.collectionKind
            local clickable = row.detail ~= nil or collectionKind ~= nil
            self:SetScript("OnEnter", function(owner)
                if row.card and clickable then
                    WBF.UI.PaintCard(owner, "hover")
                end
                if collectionKind and row.event and WBF.UI.ShowCollectionPreview then
                    GameTooltip:Hide()
                    WBF.UI.ShowCollectionPreview(owner, row.event, collectionKind)
                    return
                end
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                if row.event then
                    WBF.UI.EventTooltip(GameTooltip, row.event)
                else
                    GameTooltip:SetText(row.title or "", 1, 0.82, 0.45)
                    if row.value then
                        GameTooltip:AddLine(row.value, 1, 1, 1)
                    end
                    if row.lines then
                        for index = 1, #row.lines do
                            local line = row.lines[index]
                            if line.text then
                                GameTooltip:AddLine(line.text, 0.8, 0.8, 0.8, true)
                            end
                        end
                    end
                end
                if row.detail then
                    GameTooltip:AddLine("Click to see the records.", 0.9, 0.82, 0.45)
                end
                GameTooltip:Show()
            end)
            self:SetScript("OnLeave", function(owner)
                if row.card then
                    WBF.UI.PaintCard(owner, "idle")
                end
                GameTooltip:Hide()
                if collectionKind and WBF.UI.HideCollectionPreview then
                    WBF.UI.HideCollectionPreview()
                end
            end)
            self:SetScript("OnMouseDown", function(owner)
                if row.card and clickable then
                    WBF.UI.PaintCard(owner, "pressed")
                end
            end)
            self:SetScript("OnMouseUp", function(owner)
                if row.card and clickable then
                    WBF.UI.PaintCard(owner, owner:IsMouseOver() and "hover" or "idle")
                end
            end)
            if clickable then
                self:SetScript("OnClick", function()
                    if collectionKind and row.event and WBF.UI.OpenCollectionJournal then
                        WBF.UI.OpenCollectionJournal(collectionKind, row.event)
                        return
                    end
                    if row.detail and WBF.UI.frame then
                        WBF.UI.frame:OpenDetail(row.detail, {
                            characterGUID = row.characterGUID,
                            resourceKey = row.resourceKey,
                            reputationFaction = row.reputationFaction,
                            detailValue = row.detailValue,
                            detailId = row.detailId,
                            period = row.period,
                            warband = row.warband,
                        })
                    end
                end)
            else
                self:SetScript("OnClick", nil)
            end
        end
        return frame
    end)
end

function WBF.UI.Detail.Attach(parent)
    root = parent
    titleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    titleText:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])

    backButton = CreateFrame("Button", nil, root)
    backButton:SetSize(280, 18)
    WBF.UI.BindWheel(backButton)
    backLabel = backButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    backLabel:SetAllPoints()
    backLabel:SetJustifyH("RIGHT")
    backLabel:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    backButton:SetScript("OnClick", function()
        if WBF.UI.frame then
            WBF.UI.frame:BackDetail()
        end
    end)
    backButton:SetScript("OnEnter", function()
        backLabel:SetTextColor(WBF.UI.Colors.bright[1], WBF.UI.Colors.bright[2], WBF.UI.Colors.bright[3])
    end)
    backButton:SetScript("OnLeave", function()
        backLabel:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    end)

    subtitleText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleText:SetJustifyH("LEFT")
    subtitleText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    summaryText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summaryText:SetJustifyH("LEFT")
    summaryText:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])

    noteText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noteText:SetJustifyH("LEFT")
    noteText:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])

    headlineLabel = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    headlineLabel:SetJustifyH("LEFT")
    headlineLabel:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    headlineText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    headlineText:SetJustifyH("LEFT")
    headlineText:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])

    footerText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerText:SetJustifyH("LEFT")
    footerText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
end

function WBF.UI.Detail.HideChrome()
    if titleText then
        titleText:Hide()
    end
    if backButton then
        backButton:Hide()
    end
    if subtitleText then
        subtitleText:Hide()
    end
    if summaryText then
        summaryText:Hide()
    end
    if noteText then
        noteText:Hide()
    end
    if headlineLabel then
        headlineLabel:Hide()
    end
    if headlineText then
        headlineText:Hide()
    end
    if footerText then
        footerText:Hide()
    end
end

function WBF.UI.Detail.Render(model, width)
    if not root then
        return 40
    end
    if WBF.UI.ResourceDetail and WBF.UI.ResourceDetail.Hide then
        WBF.UI.ResourceDetail.Hide()
    end
    if WBF.UI.GoldDetail and WBF.UI.GoldDetail.Hide then
        WBF.UI.GoldDetail.Hide()
    end
    if WBF.UI.CharacterDetail and WBF.UI.CharacterDetail.Hide then
        WBF.UI.CharacterDetail.Hide()
    end
    if WBF.UI.PetBattlesView and WBF.UI.PetBattlesView.Hide then
        WBF.UI.PetBattlesView.Hide()
    end
    WBF.UI.ReleaseAll()

    local y = 4
    backButton:ClearAllPoints()
    backButton:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -y)
    local back = model.backLabel or "Back"
    back = back:gsub("^←%s*", "")
    back = back:gsub("^↩%s*", "")
    back = back:gsub("^<%s*", "")
    backLabel:SetText(back)
    backButton:Show()

    titleText:ClearAllPoints()
    titleText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    titleText:SetPoint("RIGHT", backButton, "LEFT", -12, 0)
    titleText:SetText(model.title or "")
    titleText:Show()
    y = y + 24

    subtitleText:ClearAllPoints()
    subtitleText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    subtitleText:SetWidth(width)
    subtitleText:SetText(model.subtitle or "")
    if model.subtitle and model.subtitle ~= "" then
        subtitleText:Show()
        y = y + 18
    else
        subtitleText:Hide()
    end

    if model.summary and model.summary ~= "" then
        summaryText:ClearAllPoints()
        summaryText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        summaryText:SetWidth(width)
        summaryText:SetText(model.summary)
        summaryText:Show()
        y = y + 22
    else
        summaryText:Hide()
    end

    if model.note and model.note ~= "" then
        noteText:ClearAllPoints()
        noteText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        noteText:SetWidth(width)
        noteText:SetText(model.note)
        noteText:Show()
        y = y + 18
    else
        noteText:Hide()
    end

    if model.headline and model.headline ~= "" then
        headlineLabel:ClearAllPoints()
        headlineLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        headlineLabel:SetWidth(width)
        headlineLabel:SetText(model.headlineLabel or "")
        headlineLabel:Show()
        y = y + 16
        headlineText:ClearAllPoints()
        headlineText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        headlineText:SetWidth(width)
        headlineText:SetText(model.headline)
        headlineText:Show()
        y = y + 32
    else
        headlineLabel:Hide()
        headlineText:Hide()
    end

    local function PlaceRows(rows, x, top, rowWidth)
        local cursor = top
        for rowIndex = 1, #rows do
            local row = WBF.UI.Acquire(RowPool(), root)
            row:SetPoint("TOPLEFT", root, "TOPLEFT", x, -cursor)
            row:Apply(rows[rowIndex], rowWidth)
            cursor = cursor + row:GetHeight() + 4
        end
        return cursor - top
    end

    if model.facts and #model.facts > 0 then
        if model.factsTitle and model.factsTitle ~= "" then
            WBF.UI.AcquireSection(root, model.factsTitle, 0, y, width)
            y = y + 24
        end
        y = y + PlaceRows(model.facts, 0, y, width)
        y = y + 8
    end

    local columns = model.columns or {}
    local columnRows = false
    for index = 1, #columns do
        if #(columns[index].rows or {}) > 0 then
            columnRows = true
            break
        end
    end
    if columnRows then
        local gap = 28
        local sideBySide = width >= 560 and #columns > 1
        local colWidth = sideBySide and math.floor((width - gap * (#columns - 1)) / #columns) or width
        local tallest = 0
        local stacked = y
        for index = 1, #columns do
            local column = columns[index]
            local rows = column.rows or {}
            if #rows > 0 then
                local x = sideBySide and (index - 1) * (colWidth + gap) or 0
                local top = sideBySide and y or stacked
                if column.title and column.title ~= "" then
                    WBF.UI.AcquireSection(root, column.title, x, top, colWidth)
                    top = top + 24
                end
                local used = PlaceRows(rows, x, top, colWidth)
                local columnHeight = (top - (sideBySide and y or stacked)) + used
                if sideBySide then
                    if columnHeight > tallest then
                        tallest = columnHeight
                    end
                else
                    stacked = stacked + columnHeight + 8
                end
            end
        end
        y = sideBySide and (y + tallest + 8) or stacked
    end

    if model.footer and model.footer ~= "" then
        footerText:ClearAllPoints()
        footerText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(y + 6))
        footerText:SetWidth(width)
        footerText:SetText(model.footer)
        footerText:Show()
        y = y + 28
    else
        footerText:Hide()
    end

    local sections = model.sections or {}
    local anyRow = false
    for index = 1, #sections do
        if #(sections[index].rows or {}) > 0 then
            anyRow = true
            break
        end
    end

    local hasBody = anyRow or columnRows or (model.facts and #model.facts > 0) or (model.headline and model.headline ~= "")
    if not hasBody then
        local height = WBF.UI.PlaceEmptyState(root, 0, y + 8, math.min(560, width), "Nothing recorded yet",
            model.empty or "Nothing was recorded for this period. Try a longer period, or check back after you play.")
        return y + 8 + height + 16
    end
    if not anyRow then
        return y + 8
    end

    y = y + 6
    for sectionIndex = 1, #sections do
        local section = sections[sectionIndex]
        local rows = section.rows or {}
        if #rows > 0 then
            if section.title and section.title ~= "" then
                WBF.UI.AcquireSection(root, section.title, 0, y, width)
                y = y + 26
            end
            for rowIndex = 1, #rows do
                local row = WBF.UI.Acquire(RowPool(), root)
                row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
                row:Apply(rows[rowIndex], width)
                y = y + row:GetHeight() + 6
            end
            y = y + 8
        end
    end

    return y + 8
end
