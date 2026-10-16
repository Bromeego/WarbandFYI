local _, WBF = ...

WBF.UI.PetBattlesView = {}

local board
local parentFrame
local backButton
local backLabel
local icon
local titleText
local subText

-- Metric cards double as quick filters for the recent-activity table.  The
-- filter is intentionally view-local: switching period/character clears it.
local activeActivityFilter = nil
local activityFilterScope = nil

local function Color(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function BackCaption(label)
    label = tostring(label or "Back")
    label = label:gsub("^%s+", "")
    label = label:gsub("^←%s*", "")
    label = label:gsub("^<%s*", "")
    label = label:gsub("^↩%s*", "")
    return "< " .. label
end

local function CharacterName(guid)
    local character = guid and WBF.Characters.Get(guid) or nil
    if character and character.name and character.name ~= "" then
        return character.name
    end
    return nil
end

function WBF.UI.PetBattlesView.Attach(parent)
    parentFrame = parent
    board = CreateFrame("Frame", nil, parent)
    board:SetSize(400, 40)
    board:Hide()
    WBF.UI.BindWheel(board)

    icon = board:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 0, 0)

    titleText = board:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetJustifyH("LEFT")
    Color(titleText, WBF.UI.Colors.gold)

    subText = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subText:SetJustifyH("LEFT")
    Color(subText, WBF.UI.Colors.muted)

    local emptyText = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetJustifyH("LEFT")
    emptyText:SetWordWrap(true)
    Color(emptyText, WBF.UI.Colors.muted)
    emptyText:Hide()
    board.EmptyText = emptyText

    backButton = CreateFrame("Button", nil, board)
    backButton:SetSize(180, 22)
    WBF.UI.BindWheel(backButton)
    backLabel = backButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    backLabel:SetAllPoints()
    backLabel:SetJustifyH("RIGHT")
    Color(backLabel, WBF.UI.Colors.gold)
    backButton:SetScript("OnClick", function()
        if WBF.UI.frame then
            WBF.UI.frame:BackDetail()
        end
    end)
    backButton:SetScript("OnEnter", function()
        Color(backLabel, { 1, 0.95, 0.72 })
    end)
    backButton:SetScript("OnLeave", function()
        Color(backLabel, WBF.UI.Colors.gold)
    end)
end

function WBF.UI.PetBattlesView.Hide()
    if board then
        board:Hide()
    end
end

local function TablePool()
    return WBF.UI.Pool("petTable", function(parent)
        local frame = CreateFrame("Button", nil, parent)
        frame:SetHeight(22)
        frame:RegisterForClicks("LeftButtonUp")
        WBF.UI.BindWheel(frame)
        local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.035)
        local timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeText:SetPoint("LEFT", 0, 0)
        timeText:SetWidth(58)
        timeText:SetJustifyH("LEFT")
        timeText:SetWordWrap(false)
        Color(timeText, WBF.UI.Colors.muted)
        local eventText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        eventText:SetJustifyH("LEFT")
        eventText:SetWordWrap(false)
        Color(eventText, WBF.UI.Colors.cream)
        local detailText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detailText:SetJustifyH("LEFT")
        detailText:SetWordWrap(false)
        Color(detailText, WBF.UI.Colors.muted)
        local who = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        who:SetJustifyH("RIGHT")
        who:SetWordWrap(false)
        frame.Apply = function(self, row, rowWidth)
            self:SetWidth(rowWidth)
            timeText:SetText(row.time or "")
            local whoWidth = row.who and 110 or 0
            who:ClearAllPoints()
            eventText:ClearAllPoints()
            detailText:ClearAllPoints()
            eventText:SetPoint("LEFT", 64, 0)
            eventText:SetWidth(math.max(88, math.floor(rowWidth * 0.28)))
            eventText:SetText(row.event or "")
            if whoWidth > 0 then
                who:SetPoint("RIGHT", 0, 0)
                who:SetWidth(whoWidth)
                who:SetText(row.who or "")
                who:SetTextColor(WBF.Format.ClassColor(row.classFile))
                who:Show()
                detailText:SetPoint("LEFT", eventText, "RIGHT", 8, 0)
                detailText:SetPoint("RIGHT", who, "LEFT", -8, 0)
            else
                who:Hide()
                detailText:SetPoint("LEFT", eventText, "RIGHT", 8, 0)
                detailText:SetPoint("RIGHT", -4, 0)
            end
            detailText:SetText(row.detail or "")
            local collectionEvent = row.collectionEvent
            if collectionEvent then
                self:SetScript("OnEnter", function(owner)
                    if WBF.UI.ShowCollectionPreview then
                        WBF.UI.ShowCollectionPreview(owner, collectionEvent, "pet")
                    end
                end)
                self:SetScript("OnLeave", function()
                    if WBF.UI.HideCollectionPreview then
                        WBF.UI.HideCollectionPreview()
                    end
                end)
                self:SetScript("OnClick", function()
                    if WBF.UI.OpenCollectionJournal then
                        WBF.UI.OpenCollectionJournal("pet", collectionEvent)
                    end
                end)
            else
                self:SetScript("OnEnter", nil)
                self:SetScript("OnLeave", nil)
                self:SetScript("OnClick", nil)
            end
        end
        return frame
    end)
end

local function ChartPool()
    return WBF.UI.Pool("petChart", function(parent)
        local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        WBF.UI.BindWheel(frame)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        Color(title, WBF.UI.Colors.gold)
        title:SetText("Battle Results")
        local slots = {}
        for index = 1, 8 do
            local slot = CreateFrame("Frame", nil, frame)
            slot:EnableMouse(true)
            WBF.UI.BindWheel(slot)
            slot:SetScript("OnEnter", function(self)
                local day = self.Day
                if not day then
                    return
                end
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetText(day.label or "Battle results", 1, 0.82, 0.45)
                GameTooltip:AddDoubleLine("Wins", tostring(day.wins or 0),
                    WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3],
                    WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3])
                GameTooltip:AddDoubleLine("Losses", tostring(day.losses or 0),
                    WBF.UI.Colors.red[1], WBF.UI.Colors.red[2], WBF.UI.Colors.red[3],
                    WBF.UI.Colors.red[1], WBF.UI.Colors.red[2], WBF.UI.Colors.red[3])
                GameTooltip:AddDoubleLine("Battles", tostring((day.wins or 0) + (day.losses or 0)),
                    0.9, 0.9, 0.9, 0.9, 0.9, 0.9)
                GameTooltip:Show()
            end)
            slot:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            local loss = slot:CreateTexture(nil, "ARTWORK")
            loss:SetColorTexture(WBF.UI.Colors.red[1], WBF.UI.Colors.red[2], WBF.UI.Colors.red[3], 0.9)
            local win = slot:CreateTexture(nil, "ARTWORK")
            win:SetColorTexture(WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3], 0.9)
            local label = slot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetJustifyH("CENTER")
            Color(label, WBF.UI.Colors.muted)
            slots[index] = { slot = slot, win = win, loss = loss, label = label }
        end
        frame.Apply = function(self, days, panelWidth)
            self:SetWidth(panelWidth)
            self:SetHeight(148)
            local count = math.min(#days, #slots)
            local gap = 8
            local usable = panelWidth - 24
            local colWidth = math.max(18, math.floor((usable - gap * (count - 1)) / math.max(count, 1)))
            local maxValue = 1
            for index = 1, count do
                maxValue = math.max(maxValue, (days[index].wins or 0) + (days[index].losses or 0))
            end
            for index = 1, #slots do
                local column = slots[index]
                if index <= count then
                    local day = days[index]
                    column.slot.Day = day
                    local total = (day.wins or 0) + (day.losses or 0)
                    local barHeight = math.max(4, math.floor(78 * total / maxValue))
                    local lossHeight = total > 0 and math.floor(barHeight * (day.losses or 0) / total) or 0
                    local winHeight = barHeight - lossHeight
                    local x = 12 + (index - 1) * (colWidth + gap)
                    column.slot:ClearAllPoints()
                    column.slot:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 22)
                    column.slot:SetSize(colWidth, 86)
                    column.loss:ClearAllPoints()
                    column.win:ClearAllPoints()
                    if lossHeight > 0 then
                        column.loss:SetPoint("BOTTOMLEFT", column.slot, "BOTTOMLEFT", 0, 0)
                        column.loss:SetSize(colWidth, lossHeight)
                        column.loss:Show()
                    else
                        column.loss:Hide()
                    end
                    if winHeight > 0 then
                        column.win:SetPoint("BOTTOMLEFT", column.slot, "BOTTOMLEFT", 0, lossHeight)
                        column.win:SetSize(colWidth, winHeight)
                        column.win:Show()
                    else
                        column.win:Hide()
                    end
                    column.label:ClearAllPoints()
                    column.label:SetPoint("TOP", column.slot, "BOTTOM", 0, -2)
                    column.label:SetText(day.label or "")
                    column.slot:Show()
                    column.label:Show()
                else
                    column.slot.Day = nil
                    column.slot:Hide()
                    column.label:Hide()
                end
            end
        end
        return frame
    end)
end

local function TypesPool()
    return WBF.UI.Pool("petTypes", function(parent)
        local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        WBF.UI.BindWheel(frame)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        Color(title, WBF.UI.Colors.gold)
        title:SetText("Battle Types")
        local rows = {}
        for index = 1, 3 do
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetJustifyH("LEFT")
            Color(label, WBF.UI.Colors.cream)
            local value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            value:SetJustifyH("RIGHT")
            Color(value, WBF.UI.Colors.cream)
            local back = frame:CreateTexture(nil, "BACKGROUND")
            back:SetHeight(8)
            back:SetColorTexture(0.14, 0.12, 0.08, 1)
            local fill = frame:CreateTexture(nil, "ARTWORK")
            fill:SetHeight(8)
            rows[index] = { label = label, value = value, back = back, fill = fill }
        end
        frame.Apply = function(self, types, panelWidth)
            self:SetWidth(panelWidth)
            local shown = 0
            local total = 0
            for index = 1, #types do
                total = total + (types[index].count or 0)
            end
            if total <= 0 then
                total = 1
            end
            local y = 36
            for index = 1, #rows do
                local row = rows[index]
                local entry = types[index]
                if entry and entry.count > 0 then
                    shown = shown + 1
                    row.label:ClearAllPoints()
                    row.value:ClearAllPoints()
                    row.label:SetPoint("TOPLEFT", 12, -y)
                    row.value:SetPoint("TOPRIGHT", -12, -y)
                    row.label:SetText(entry.label)
                    row.value:SetText(tostring(entry.count))
                    row.label:Show()
                    row.value:Show()
                    y = y + 16
                    row.back:ClearAllPoints()
                    row.back:SetPoint("TOPLEFT", 12, -y)
                    row.back:SetPoint("RIGHT", self, "RIGHT", -12, 0)
                    row.back:Show()
                    local fraction = entry.count / total
                    row.fill:ClearAllPoints()
                    row.fill:SetPoint("TOPLEFT", row.back, "TOPLEFT", 0, 0)
                    row.fill:SetSize(math.max(4, math.floor((panelWidth - 24) * fraction)), 8)
                    row.fill:SetColorTexture(entry.color[1], entry.color[2], entry.color[3], 0.95)
                    row.fill:Show()
                    y = y + 16
                else
                    row.label:Hide()
                    row.value:Hide()
                    row.back:Hide()
                    row.fill:Hide()
                end
            end
            self:SetHeight(math.max(72, y + 8))
            return shown
        end
        return frame
    end)
end

local function SidePool()
    return WBF.UI.Pool("petSide", function(parent)
        local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        WBF.UI.BindWheel(frame)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetPoint("RIGHT", -12, 0)
        title:SetJustifyH("LEFT")
        Color(title, WBF.UI.Colors.gold)
        local lines = {}
        for index = 1, 6 do
            local left = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            left:SetJustifyH("LEFT")
            left:SetWordWrap(false)
            Color(left, WBF.UI.Colors.cream)
            local right = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            right:SetJustifyH("RIGHT")
            Color(right, WBF.UI.Colors.green)
            lines[index] = { left = left, right = right }
        end
        frame.Apply = function(self, heading, entries, panelWidth)
            self:SetWidth(panelWidth)
            title:SetText(heading)
            local y = 36
            local shown = 0
            for index = 1, #lines do
                local line = lines[index]
                local entry = entries[index]
                if entry then
                    shown = shown + 1
                    line.left:ClearAllPoints()
                    line.right:ClearAllPoints()
                    line.left:SetPoint("TOPLEFT", 12, -y)
                    line.left:SetPoint("RIGHT", self, "RIGHT", -64, 0)
                    line.right:SetPoint("TOPRIGHT", -12, -y)
                    line.left:SetText(entry.label or "")
                    line.right:SetText(entry.value or "")
                    Color(line.right, entry.color or WBF.UI.Colors.green)
                    line.left:Show()
                    line.right:Show()
                    y = y + 20
                else
                    line.left:Hide()
                    line.right:Hide()
                end
            end
            self:SetHeight(math.max(48, y + 8))
            return shown > 0
        end
        return frame
    end)
end

local function MetricCards(report)
    local cards = {}
    local function add(label, value, color, detail, filterKey)
        if not value or value == 0 then
            return
        end
        cards[#cards + 1] = {
            label = label,
            value = type(value) == "number" and (label == "Pet Levels" and WBF.Format.Signed(value) or tostring(value)) or value,
            color = color,
            detail = detail,
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
            filterKey = filterKey,
        }
    end
    local battles = report.completed > 0 and report.completed or report.started
    add("Battles", battles, nil, nil, "battles")
    add("Wins", report.wins, WBF.UI.Colors.green, nil, "wins")
    add("Losses", report.losses, WBF.UI.Colors.red, nil, "losses")
    add("Pets Captured", report.captured, nil, nil, "captured")
    add("Pet Levels", report.levels, nil, report.level25 > 0 and (report.level25 .. " reached 25") or nil, "levels")
    add("Reached Level 25", report.level25, nil, nil, "level25")
    add("New Pets", report.newPets, nil, nil, "newPets")
    return cards
end

local FILTER_LABELS = {
    battles = "Battles",
    wins = "Wins",
    losses = "Losses",
    captured = "Pets Captured",
    levels = "Pet Levels",
    level25 = "Reached Level 25",
    newPets = "New Pets",
}

local function IsPetEvent(event)
    if not event then
        return false
    end
    if WBF.EventType and event.eventType == WBF.EventType.Pet then
        return true
    end
    return event.eventType == "pet"
end

local function MatchesActivityFilter(event, filterKey)
    if not filterKey then
        return true
    end
    local meta = event and event.meta or {}
    if filterKey == "battles" then
        return meta.kind == "battle"
    elseif filterKey == "wins" then
        return meta.kind == "battle" and meta.outcome == "win"
    elseif filterKey == "losses" then
        return meta.kind == "battle" and meta.outcome ~= "win"
    elseif filterKey == "captured" then
        return meta.kind == "capture" or (IsPetEvent(event) and meta.captured == true)
    elseif filterKey == "levels" then
        return meta.kind == "level"
    elseif filterKey == "level25" then
        return meta.kind == "level" and meta.reached25 == true
    elseif filterKey == "newPets" then
        return (meta.kind == "capture" and meta.newSpecies == true) or (IsPetEvent(event) and meta.captured ~= true)
    end
    return true
end

local function BindMetricFilter(card, data, selected, onToggle)
    if not card or not data or not data.filterKey then
        return
    end
    local function paint(state)
        if state == "hover" then
            WBF.UI.PaintCard(card, "hover")
        elseif selected then
            WBF.UI.PaintCard(card, "pressed")
        else
            WBF.UI.PaintCard(card, "idle")
        end
    end
    paint("idle")
    card:SetScript("OnEnter", function(self)
        paint("hover")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(data.label, 1, 0.82, 0.45)
        if selected then
            GameTooltip:AddLine("Filtering Recent Pet Activity. Click to clear the filter.", 0.9, 0.9, 0.9, true)
        else
            GameTooltip:AddLine("Click to show only these records in Recent Pet Activity.", 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function()
        paint("idle")
        GameTooltip:Hide()
    end)
    card:SetScript("OnMouseDown", function()
        WBF.UI.PaintCard(card, "pressed")
    end)
    card:SetScript("OnMouseUp", function(self)
        if self:IsMouseOver() then
            paint("hover")
        else
            paint("idle")
        end
    end)
    card:SetScript("OnClick", function()
        GameTooltip:Hide()
        if onToggle then
            onToggle(data.filterKey)
        end
    end)
end

function WBF.UI.PetBattlesView.Render(summary, context, width)
    if not board then
        return 40
    end
    if WBF.UI.CharacterDetail and WBF.UI.CharacterDetail.Hide then
        WBF.UI.CharacterDetail.Hide()
    end
    WBF.UI.ReleaseAll()
    board:Show()
    board:ClearAllPoints()
    board:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, 0)
    board:SetWidth(width)

    context = context or {}
    summary = summary or {}
    local guid = context.characterGUID
    local events = WBF.PetBattles.EventsFor(summary.startAt, summary.endAt, guid)
    local report = WBF.PetBattles.Collect(events)
    local periodLabel = summary.label or "This Week"
    local scopeKey = table.concat({ tostring(summary.startAt or ""), tostring(summary.endAt or ""), tostring(guid or "warband") }, ":")
    if activityFilterScope ~= scopeKey then
        activityFilterScope = scopeKey
        activeActivityFilter = nil
    end

    WBF.UI.SetAtlasChain(icon, { "WildBattlePet" }, "Interface\\Icons\\INV_Box_PetCarrier_01")
    titleText:ClearAllPoints()
    titleText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    titleText:SetText("Pet Battles")
    local who = guid and CharacterName(guid) or nil
    if who then
        subText:SetText(who .. "  ·  " .. periodLabel .. "  ·  Activity while this character was active")
    else
        subText:SetText("Warband Activity  ·  " .. periodLabel)
    end
    subText:ClearAllPoints()
    subText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
    subText:SetPoint("RIGHT", board, "RIGHT", -180, 0)

    local back = BackCaption(WBF.Detail.BackLabel(WBF.UI.frame and WBF.UI.frame.detailStack))
    backLabel:SetText(back)
    backButton:ClearAllPoints()
    backButton:SetPoint("TOPRIGHT", board, "TOPRIGHT", 0, -8)
    backButton:SetWidth(math.max(150, (backLabel:GetStringWidth() or 150) + 8))

    local y = 52
    board.EmptyText:Hide()
    local cards = MetricCards(report)
    if #cards == 0 then
        board.EmptyText:ClearAllPoints()
        board.EmptyText:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
        board.EmptyText:SetWidth(math.min(460, width))
        board.EmptyText:SetText("No pet battle activity in this period yet.")
        board.EmptyText:Show()
        board:SetHeight(y + 40)
        return y + 40
    end

    local gap = 8
    local columns = math.max(1, math.min(#cards, math.floor((width + gap) / 108)))
    local cardWidth = math.floor((width - gap * (columns - 1)) / columns)
    local cardHeight = 64
    for index = 1, #cards do
        if cards[index].detail and cards[index].detail ~= "" then
            cardHeight = 78
            break
        end
    end
    for index = 1, #cards do
        local card = WBF.UI.AcquireStat(board)
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        card:SetSize(cardWidth, cardHeight)
        card:SetPoint("TOPLEFT", board, "TOPLEFT", column * (cardWidth + gap), -(y + row * (cardHeight + gap)))
        card:Apply(cards[index])
        BindMetricFilter(card, cards[index], activeActivityFilter == cards[index].filterKey, function(filterKey)
            if activeActivityFilter == filterKey then
                activeActivityFilter = nil
            else
                activeActivityFilter = filterKey
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    WBF.UI.PetBattlesView.Render(summary, context, width)
                end)
            else
                WBF.UI.PetBattlesView.Render(summary, context, width)
            end
        end)
    end
    local cardRows = math.ceil(#cards / columns)
    y = y + cardRows * cardHeight + (cardRows - 1) * gap + 14

    local types = {}
    if report.wild > 0 then
        types[#types + 1] = { label = "Wild Battles", count = report.wild, color = WBF.UI.Colors.green }
    end
    if report.trainer > 0 then
        types[#types + 1] = { label = "Trainer Battles", count = report.trainer, color = WBF.UI.Colors.gold }
    end
    if report.pvp > 0 then
        types[#types + 1] = { label = "PvP Battles", count = report.pvp, color = { 0.45, 0.65, 0.95 } }
    end
    local showChart = #report.days >= 2
    local showTypes = #types > 0
    if showChart or showTypes then
        local split = showChart and showTypes and width >= 640
        local leftWidth = split and math.floor((width - 8) * 0.58) or width
        local rightWidth = split and (width - leftWidth - 8) or width
        local leftBottom = y
        local rightBottom = y
        if showChart then
            local chart = WBF.UI.Acquire(ChartPool(), board)
            chart:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
            chart:Apply(report.days, leftWidth)
            leftBottom = y + chart:GetHeight()
        end
        if showTypes then
            local panel = WBF.UI.Acquire(TypesPool(), board)
            local panelX = split and (leftWidth + 8) or 0
            local panelY = split and y or leftBottom + 8
            panel:SetPoint("TOPLEFT", board, "TOPLEFT", panelX, -panelY)
            panel:Apply(types, split and rightWidth or width)
            rightBottom = panelY + panel:GetHeight()
        end
        y = math.max(leftBottom, rightBottom) + 14
    end

    local sideEntries = {}
    local sideTitle
    if #report.topPets > 0 then
        sideTitle = "Top Pets by Levels Gained"
        for index = 1, #report.topPets do
            local pet = report.topPets[index]
            sideEntries[#sideEntries + 1] = { label = pet.name, value = WBF.Format.Signed(pet.levels), color = WBF.UI.Colors.green }
        end
    elseif #report.captures > 0 then
        sideTitle = "Recently Captured"
        for index = 1, #report.captures do
            local capture = report.captures[index]
            sideEntries[#sideEntries + 1] = {
                label = capture.detail or capture.name or "Battle pet",
                value = "",
                color = WBF.UI.Colors.cream,
            }
        end
    end

    local showSide = sideTitle ~= nil and width >= 680
    local tableWidth = showSide and math.floor(width * 0.64) or width
    local activityHeading = "Recent Pet Activity"
    if activeActivityFilter and FILTER_LABELS[activeActivityFilter] then
        activityHeading = activityHeading .. " — " .. FILTER_LABELS[activeActivityFilter]
    end
    WBF.UI.AcquireSection(board, activityHeading, 0, y, tableWidth)
    local tableY = y + 26
    local rows = {}
    local sessionDetails = WBF.PetBattles.SessionLevelDetails(WBF.Database.Get().events)
    table.sort(events, function(a, b)
        if a.at == b.at then
            return (a.id or 0) > (b.id or 0)
        end
        return (a.at or 0) > (b.at or 0)
    end)
    local showWho = not guid
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if meta.surface ~= false and meta.kind ~= "battleStart" and MatchesActivityFilter(event, activeActivityFilter) and (meta.kind == "battle" or meta.kind == "level" or meta.kind == "capture" or event.eventType == WBF.EventType.Pet) then
            local name = CharacterName(event.guid)
            local character = event.guid and WBF.Characters.Get(event.guid) or nil
            rows[#rows + 1] = {
                time = WBF.Format.Ago(event.at),
                event = meta.eventLabel or (event.eventType == WBF.EventType.Pet and "New pet" or "Pet battle"),
                detail = sessionDetails[event] or meta.detail or event.text or "",
                who = showWho and name or nil,
                classFile = character and character.classFile or nil,
                collectionEvent = (meta.kind == "capture" or event.eventType == WBF.EventType.Pet) and meta.speciesID and event or nil,
            }
        end
    end
    local header = WBF.UI.Acquire(TablePool(), board)
    header:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -tableY)
    header:Apply({ time = "Time", event = "Event", detail = "Details", who = showWho and "Character" or nil }, tableWidth)
    tableY = tableY + 22
    local shown = math.min(12, #rows)
    if shown == 0 then
        board.EmptyText:ClearAllPoints()
        board.EmptyText:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -tableY)
        board.EmptyText:SetWidth(tableWidth)
        board.EmptyText:SetText("No pet activity in this period.")
        board.EmptyText:Show()
        tableY = tableY + 22
    else
        for index = 1, shown do
            local line = WBF.UI.Acquire(TablePool(), board)
            line:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -tableY)
            line:Apply(rows[index], tableWidth)
            tableY = tableY + 22
        end
    end

    local sideBottom = y
    if showSide then
        local side = WBF.UI.Acquire(SidePool(), board)
        local sideWidth = width - tableWidth - 8
        side:SetPoint("TOPLEFT", board, "TOPLEFT", tableWidth + 8, -y)
        side:Apply(sideTitle, sideEntries, sideWidth)
        sideBottom = y + side:GetHeight()
    elseif sideTitle and not showSide then
        local side = WBF.UI.Acquire(SidePool(), board)
        side:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -(tableY + 12))
        side:Apply(sideTitle, sideEntries, width)
        tableY = tableY + 12 + side:GetHeight()
    end

    y = math.max(tableY, sideBottom) + 8
    board:SetHeight(y)
    return y
end
