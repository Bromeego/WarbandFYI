local _, WBF = ...

WBF.UI.GoldDetail = {}

local board
local titleText, subtitleText, backButton, backLabel, allTimeButton, allTimeLabel
local netCard, gainedCard, spentCard, historyCard, activityCard
local activityRows = {}

local function Color(fontString, color)
    if fontString and color then
        fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function PaintCard(frame)
    WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    WBF.UI.BindWheel(frame)
end

local function Money(value, signed)
    return WBF.Format.Gold(value or 0, signed == true, "precise")
end

local function CompactMoney(value)
    return WBF.Format.Gold(value or 0, false, "compact")
end

local function AmountColor(amount)
    if (amount or 0) > 0 then
        return WBF.UI.Colors.green
    elseif (amount or 0) < 0 then
        return WBF.UI.Colors.red
    end
    return WBF.UI.Colors.cream
end

local function MakeMetric(parent, heading)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    PaintCard(card)
    local label = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", 12, -10)
    label:SetText(heading)
    Color(label, WBF.UI.Colors.muted)
    local value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    value:SetPoint("LEFT", 14, -2)
    value:SetJustifyH("LEFT")
    Color(value, WBF.UI.Colors.cream)
    card.Label = label
    card.Value = value
    return card
end

local function Marker(plot)
    local marker = CreateFrame("Frame", nil, plot)
    marker:SetSize(9, 9)
    marker:EnableMouse(true)
    WBF.UI.BindWheel(marker)
    local outline = marker:CreateTexture(nil, "OVERLAY", nil, 1)
    outline:SetTexture(WBF.UI.Media.dot)
    outline:SetVertexColor(0.04, 0.04, 0.05, 0.95)
    outline:SetSize(9, 9)
    outline:SetPoint("CENTER")
    local dot = marker:CreateTexture(nil, "OVERLAY", nil, 2)
    dot:SetTexture(WBF.UI.Media.dot)
    dot:SetSize(6, 6)
    dot:SetPoint("CENTER")
    marker.Outline = outline
    marker.Dot = dot
    -- Dots are invisible hover targets until pointed at, so clusters of
    -- changes don't crowd the line.
    outline:Hide()
    dot:Hide()
    marker:SetScript("OnLeave", function(self)
        if GameTooltip then
            GameTooltip:Hide()
        end
        self.Outline:Hide()
        self.Dot:Hide()
    end)
    return marker
end

local function HidePlot(plot)
    WBF.UI.HideCurve(plot)
    for index = 1, #plot.markers do plot.markers[index]:Hide() end
    for index = 1, #plot.yLabels do plot.yLabels[index]:Hide() end
    for index = 1, #plot.xLabels do plot.xLabels[index]:Hide() end
    for index = 1, #plot.grids do plot.grids[index]:Hide() end
end

local function Tangents(xs, ys)
    local count = #xs
    local slopes, tangents = {}, {}
    if count < 2 then return tangents end
    for i = 1, count - 1 do
        local dx = xs[i + 1] - xs[i]
        slopes[i] = dx ~= 0 and ((ys[i + 1] - ys[i]) / dx) or 0
    end
    tangents[1] = slopes[1] or 0
    tangents[count] = slopes[count - 1] or 0
    for i = 2, count - 1 do
        local a, b = slopes[i - 1] or 0, slopes[i] or 0
        if a == 0 or b == 0 or (a < 0) ~= (b < 0) then
            tangents[i] = 0
        else
            tangents[i] = (a + b) / 2
        end
    end
    for i = 1, count - 1 do
        local slope = slopes[i] or 0
        if slope == 0 then
            tangents[i], tangents[i + 1] = 0, 0
        else
            local a = (tangents[i] or 0) / slope
            local b = (tangents[i + 1] or 0) / slope
            local magnitude = math.sqrt(a * a + b * b)
            if magnitude > 3 then
                local scale = 3 / magnitude
                tangents[i] = scale * a * slope
                tangents[i + 1] = scale * b * slope
            end
        end
    end
    return tangents
end

local function Hermite(y0, y1, m0, m1, span, t)
    local t2, t3 = t * t, t * t * t
    return (2 * t3 - 3 * t2 + 1) * y0
        + (t3 - 2 * t2 + t) * span * m0
        + (-2 * t3 + 3 * t2) * y1
        + (t3 - t2) * span * m1
end

local function DrawGraph(plot, model, width, height)
    HidePlot(plot)
    local points = model.points or {}
    if #points == 0 then
        plot.Empty:SetText("No gold changes recorded for this range.")
        plot.Empty:Show()
        return
    end
    plot.Empty:Hide()

    local firstAt = points[1].at or model.startAt or WBF.Time.Now()
    local lastAt = points[#points].at or model.endAt or firstAt + 1
    local span = math.max(1, lastAt - firstAt)
    local x0 = firstAt - math.max(60, span * 0.04)
    local x1 = lastAt + math.max(60, span * 0.04)
    if model.allTime and #points > 1 then
        x0, x1 = firstAt, lastAt
    end
    if x1 <= x0 then x1 = x0 + 1 end

    local low, high = 0, 0
    for i = 1, #points do
        local value = tonumber(points[i].value) or 0
        if value < low then low = value end
        if value > high then high = value end
    end
    local ticks = WBF.Format.NiceBounds(low, high, 5, true)
    local y0 = ticks[1] or low
    local y1 = ticks[#ticks] or high
    if y1 <= y0 then y1 = y0 + 10000 end
    local function xOf(at) return (at - x0) / (x1 - x0) * width end
    local function yOf(value) return (value - y0) / (y1 - y0) * height end

    for i = 1, #ticks do
        local grid = plot.grids[i]
        if not grid then
            grid = plot:CreateTexture(nil, "BACKGROUND")
            grid:SetColorTexture(1, 1, 1, 0.055)
            plot.grids[i] = grid
        end
        local py = yOf(ticks[i])
        grid:ClearAllPoints()
        grid:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, py)
        grid:SetSize(width, 1)
        grid:Show()
        local label = plot.yLabels[i]
        if not label then
            label = plot:GetParent():CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetJustifyH("RIGHT")
            Color(label, WBF.UI.Colors.muted)
            plot.yLabels[i] = label
        end
        label:ClearAllPoints()
        label:SetPoint("RIGHT", plot, "BOTTOMLEFT", -6, py)
        label:SetText(CompactMoney(ticks[i]))
        label:Show()
    end

    local timeTicks = WBF.Format.TimeTicks(x0, x1, 5)
    for i = 1, #timeTicks do
        local label = plot.xLabels[i]
        if not label then
            label = plot:GetParent():CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetJustifyH("CENTER")
            Color(label, WBF.UI.Colors.muted)
            plot.xLabels[i] = label
        end
        local tick = timeTicks[i]
        label:ClearAllPoints()
        label:SetPoint("TOP", plot, "BOTTOMLEFT", xOf(tick.at), -4)
        label:SetText(tick.text)
        label:Show()
    end

    local xs, ys = {}, {}
    for i = 1, #points do
        xs[i] = xOf(points[i].at)
        ys[i] = yOf(points[i].value or 0)
    end
    local tangents = Tangents(xs, ys)
    local pathXs, pathYs = { xs[1] }, { ys[1] }
    for i = 1, #points - 1 do
        local sx, ex = xs[i], xs[i + 1]
        local pixelSpan = ex - sx
        local samples = math.max(3, math.min(30, math.ceil(math.max(1, pixelSpan) / 4)))
        for sample = 1, samples do
            local t = sample / samples
            local nx = sx + pixelSpan * t
            local ny = Hermite(ys[i], ys[i + 1], tangents[i] or 0, tangents[i + 1] or 0, pixelSpan, t)
            local minY, maxY = math.min(ys[i], ys[i + 1]), math.max(ys[i], ys[i + 1])
            if ny < minY then ny = minY elseif ny > maxY then ny = maxY end
            pathXs[#pathXs + 1] = nx
            pathYs[#pathYs + 1] = ny
        end
    end
    -- Net gold can go negative, so the fill hangs off the zero line.
    WBF.UI.DrawCurve(plot, pathXs, pathYs, math.max(0, math.min(height, yOf(0))))

    local maxMarkers = 36
    local step = math.max(1, math.ceil(#points / maxMarkers))
    local markerCount = 0
    for i = 1, #points, step do
        local point = points[i]
        markerCount = markerCount + 1
        local marker = plot.markers[markerCount]
        if not marker then
            marker = Marker(plot)
            plot.markers[markerCount] = marker
        end
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", plot, "BOTTOMLEFT", xOf(point.at), yOf(point.value or 0))
        local color = AmountColor(point.delta or 0)
        marker.Dot:SetVertexColor(color[1], color[2], color[3], 1)
        marker.Point = point
        marker:SetScript("OnEnter", function(self)
            self.Outline:Show()
            self.Dot:Show()
            if not GameTooltip then return end
            local p = self.Point
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(p.label or WBF.Format.ObservedAt(p.at), 1, 0.82, 0.45)
            GameTooltip:AddLine("Net position: " .. Money(p.value, true), 1, 1, 1)
            if (p.delta or 0) ~= 0 then
                local c = AmountColor(p.delta)
                GameTooltip:AddLine("Change: " .. Money(p.delta, true), c[1], c[2], c[3])
            end
            if p.name and p.name ~= "" then
                GameTooltip:AddLine(p.name, 0.85, 0.85, 0.85)
            end
            if p.source == "betweenSessions" then
                GameTooltip:AddLine("Changed between sessions", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        marker:Show()
    end
end

local function ActivityRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(24)
    WBF.UI.BindWheel(row)
    local when = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local change = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local running = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local who = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local context = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    when:SetJustifyH("LEFT")
    change:SetJustifyH("LEFT")
    running:SetJustifyH("RIGHT")
    who:SetJustifyH("LEFT")
    context:SetJustifyH("LEFT")
    row.When, row.Change, row.Running, row.Who, row.Context = when, change, running, who, context
    return row
end

function WBF.UI.GoldDetail.Attach(parent)
    board = CreateFrame("Frame", nil, parent)
    board:SetSize(400, 40)
    board:Hide()
    WBF.UI.BindWheel(board)

    titleText = board:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 0, -4)
    Color(titleText, WBF.UI.Colors.gold)
    subtitleText = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -3)
    Color(subtitleText, WBF.UI.Colors.muted)

    backButton = CreateFrame("Button", nil, board)
    backButton:SetSize(220, 18)
    backButton:SetPoint("TOPRIGHT", board, "TOPRIGHT", 0, -4)
    WBF.UI.BindWheel(backButton)
    backLabel = backButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    backLabel:SetAllPoints()
    backLabel:SetJustifyH("RIGHT")
    Color(backLabel, WBF.UI.Colors.gold)
    backButton:SetScript("OnClick", function()
        if WBF.UI.frame then WBF.UI.frame:BackDetail() end
    end)

    allTimeButton = WBF.UI.Button(board, "View All Time", 98, 22)
    allTimeButton:SetPoint("TOPRIGHT", board, "TOPRIGHT", 0, -30)
    allTimeLabel = allTimeButton:GetFontString()
    allTimeButton:SetScript("OnClick", function()
        if not board.LastModel or not WBF.UI.frame then return end
        WBF.UI.frame:OpenDetail("goldTrend", {
            period = "warband",
            characterGUID = board.LastModel.characterGUID,
            warband = board.LastModel.characterGUID == nil,
        })
    end)

    netCard = MakeMetric(board, "NET CHANGE")
    gainedCard = MakeMetric(board, "GAINED")
    spentCard = MakeMetric(board, "SPENT")

    historyCard = CreateFrame("Frame", nil, board, "BackdropTemplate")
    PaintCard(historyCard)
    local historyTitle = historyCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    historyTitle:SetPoint("TOPLEFT", 12, -10)
    historyTitle:SetText("Net Gold History")
    Color(historyTitle, WBF.UI.Colors.gold)
    local plot = CreateFrame("Frame", nil, historyCard)
    plot.markers, plot.yLabels, plot.xLabels, plot.grids = {}, {}, {}, {}
    local empty = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("CENTER")
    Color(empty, WBF.UI.Colors.muted)
    plot.Empty = empty
    historyCard.Plot = plot

    activityCard = CreateFrame("Frame", nil, board, "BackdropTemplate")
    PaintCard(activityCard)
    local activityTitle = activityCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activityTitle:SetPoint("TOPLEFT", 12, -10)
    activityTitle:SetText("Recent Gold Changes")
    Color(activityTitle, WBF.UI.Colors.gold)
    activityCard.Empty = activityCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    activityCard.Empty:SetPoint("TOPLEFT", 12, -40)
    Color(activityCard.Empty, WBF.UI.Colors.muted)
end

function WBF.UI.GoldDetail.Hide()
    if board then board:Hide() end
end

local function BackCaption(text)
    text = tostring(text or "Back"):gsub("^%s+", ""):gsub("^<%s*", ""):gsub("^←%s*", "")
    return "< " .. text
end

function WBF.UI.GoldDetail.Render(model, width)
    if not board then return 40 end
    model = model or {}
    board.LastModel = model
    WBF.UI.ReleaseAll()
    if WBF.UI.Detail and WBF.UI.Detail.HideChrome then WBF.UI.Detail.HideChrome() end
    if WBF.UI.ResourceDetail and WBF.UI.ResourceDetail.Hide then WBF.UI.ResourceDetail.Hide() end
    if WBF.UI.CharacterDetail and WBF.UI.CharacterDetail.Hide then WBF.UI.CharacterDetail.Hide() end
    if WBF.UI.PetBattlesView and WBF.UI.PetBattlesView.Hide then WBF.UI.PetBattlesView.Hide() end
    board:Show()
    board:SetWidth(width)

    titleText:SetText(model.displayTitle or "Gold")
    subtitleText:SetText(model.periodTitle or (model.allTime and "All Time" or ""))
    backLabel:SetText(BackCaption(model.backLabel))
    allTimeButton:SetShown(not model.allTime)

    local y = 64
    local gap = 8
    local cardHeight = 92
    local cardWidth = math.floor((width - gap * 2) / 3)
    netCard:ClearAllPoints(); netCard:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y); netCard:SetSize(cardWidth, cardHeight)
    gainedCard:ClearAllPoints(); gainedCard:SetPoint("TOPLEFT", netCard, "TOPRIGHT", gap, 0); gainedCard:SetSize(cardWidth, cardHeight)
    spentCard:ClearAllPoints(); spentCard:SetPoint("TOPLEFT", gainedCard, "TOPRIGHT", gap, 0); spentCard:SetSize(width - cardWidth * 2 - gap * 2, cardHeight)
    netCard.Label:SetText("NET CHANGE")
    netCard.Value:SetText(Money(model.net, true)); Color(netCard.Value, AmountColor(model.net))
    if model.allTime then
        gainedCard.Label:SetText("MONTHS TRACKED")
        gainedCard.Value:SetText(tostring(model.months or 0)); Color(gainedCard.Value, WBF.UI.Colors.cream)
        spentCard.Label:SetText("SINCE")
        spentCard.Value:SetText(model.firstAt and date("%b %Y", model.firstAt) or "—"); Color(spentCard.Value, WBF.UI.Colors.cream)
    else
        gainedCard.Label:SetText("GAINED")
        gainedCard.Value:SetText(Money(model.earned, true)); Color(gainedCard.Value, WBF.UI.Colors.green)
        spentCard.Label:SetText("SPENT")
        spentCard.Value:SetText((model.spent or 0) > 0 and Money(-(model.spent), true) or Money(0, false)); Color(spentCard.Value, (model.spent or 0) > 0 and WBF.UI.Colors.red or WBF.UI.Colors.cream)
    end
    netCard:Show(); gainedCard:Show(); spentCard:Show()

    y = y + cardHeight + 10
    local historyHeight = 230
    historyCard:ClearAllPoints(); historyCard:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y); historyCard:SetSize(width, historyHeight); historyCard:Show()
    local plot = historyCard.Plot
    local plotLeft = 86
    local plotWidth = math.max(60, width - plotLeft - 14)
    local plotHeight = 150
    plot:ClearAllPoints(); plot:SetPoint("TOPLEFT", historyCard, "TOPLEFT", plotLeft, -40); plot:SetSize(plotWidth, plotHeight)
    DrawGraph(plot, model, plotWidth, plotHeight)

    y = y + historyHeight + 10
    local activity = model.allTime and (model.recentActivity or {}) or (model.activity or {})
    local shown = math.min(#activity, 10)
    local activityHeight = 52 + math.max(1, shown) * 24
    activityCard:ClearAllPoints(); activityCard:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y); activityCard:SetSize(width, activityHeight); activityCard:Show()
    if shown == 0 then
        activityCard.Empty:SetText("No recent gold changes available.")
        activityCard.Empty:Show()
    else
        activityCard.Empty:Hide()
    end

    local left = 12
    local colWhen = math.max(110, math.floor(width * 0.18))
    local colChange = math.max(120, math.floor(width * 0.18))
    local colRunning = math.max(130, math.floor(width * 0.18))
    local colWho = math.max(100, math.floor(width * 0.18))
    for i = 1, shown do
        local entry = activity[#activity - i + 1] or activity[i]
        local row = activityRows[i]
        if not row then
            row = ActivityRow(activityCard)
            activityRows[i] = row
        end
        row:SetParent(activityCard)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", activityCard, "TOPLEFT", 0, -(34 + (i - 1) * 24)); row:SetWidth(width)
        row.When:ClearAllPoints(); row.When:SetPoint("LEFT", row, "LEFT", left, 0); row.When:SetWidth(colWhen); row.When:SetText(entry.at and date("%d %b %H:%M", entry.at) or "—"); Color(row.When, WBF.UI.Colors.cream)
        row.Change:ClearAllPoints(); row.Change:SetPoint("LEFT", row, "LEFT", left + colWhen, 0); row.Change:SetWidth(colChange); row.Change:SetText(Money(entry.delta, true)); Color(row.Change, AmountColor(entry.delta))
        row.Running:ClearAllPoints(); row.Running:SetPoint("LEFT", row, "LEFT", left + colWhen + colChange, 0); row.Running:SetWidth(colRunning); row.Running:SetText(entry.running and Money(entry.running, true) or ""); Color(row.Running, WBF.UI.Colors.cream)
        row.Who:ClearAllPoints(); row.Who:SetPoint("LEFT", row, "LEFT", left + colWhen + colChange + colRunning, 0); row.Who:SetWidth(colWho); row.Who:SetText(entry.name or ""); if entry.classFile then row.Who:SetTextColor(WBF.Format.ClassColor(entry.classFile)) else Color(row.Who, WBF.UI.Colors.cream) end
        row.Context:ClearAllPoints(); row.Context:SetPoint("LEFT", row, "LEFT", left + colWhen + colChange + colRunning + colWho, 0); row.Context:SetWidth(math.max(40, width - (left + colWhen + colChange + colRunning + colWho) - 12)); row.Context:SetText(entry.source == "betweenSessions" and "Between sessions" or (entry.label or "")); Color(row.Context, WBF.UI.Colors.muted)
        row:Show()
    end
    for i = shown + 1, #activityRows do activityRows[i]:Hide() end

    y = y + activityHeight + 12
    board:SetHeight(y)
    return y
end
