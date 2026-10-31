local _, WBF = ...

WBF.UI.ResourceDetail = {}

local board
local nameText, sourceText, chip, chipText, backButton, backLabel
local balanceCard, periodCard, lifetimeCard
local historyCard, activityCard, peopleCard
local emptyText
local activityRows = {}
local peopleRows = {}

local function Color(fontString, color)
    if not fontString or not color then
        return
    end
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local FontSize = WBF.UI.SetFontSize

local function AmountColor(amount)
    if amount > 0 then
        return WBF.UI.Colors.green
    end
    if amount < 0 then
        return WBF.UI.Colors.red
    end
    return WBF.UI.Colors.cream
end

local function SignedText(amount)
    if not amount or amount == 0 then
        return "0"
    end
    return WBF.Format.Signed(amount)
end

local function MakeCard(parent)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    WBF.UI.Paint(card, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    WBF.UI.BindWheel(card)
    return card
end

local function EnsureRow(list, index, factory)
    local row = list[index]
    if row then
        return row
    end
    row = factory(index)
    list[index] = row
    return row
end

local function HideFrom(list, first)
    for index = first, #list do
        list[index]:Hide()
    end
end

local function MakeMetricCard(parent)
    local card = MakeCard(parent)
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetJustifyH("LEFT")
    Color(title, WBF.UI.Colors.muted)
    card.Title = title
    card.rows = {}
    for index = 1, 6 do
        local label = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        Color(label, WBF.UI.Colors.cream)
        local value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(false)
        card.rows[index] = { label = label, value = value }
    end
    local rule = card:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], 0.65)
    rule:Hide()
    card.Rule = rule
    return card
end

local function FillMetrics(card, rows, top)
    local cursor = top or 30
    local ruleShown = false
    for index = 1, #card.rows do
        local slot = card.rows[index]
        local row = rows[index]
        if row then
            if row.rule then
                card.Rule:ClearAllPoints()
                card.Rule:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -cursor)
                card.Rule:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -cursor)
                card.Rule:Show()
                ruleShown = true
                cursor = cursor + 8
                slot.label:Hide()
                slot.value:Hide()
            else
                slot.label:ClearAllPoints()
                slot.label:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -cursor)
                slot.label:SetPoint("RIGHT", card, "RIGHT", -96, 0)
                slot.label:SetText(row.label)
                slot.label:Show()
                slot.value:ClearAllPoints()
                slot.value:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -cursor)
                slot.value:SetWidth(88)
                slot.value:SetText(row.value or "")
                if row.big then
                    FontSize(slot.value, GameFontNormalLarge, "value")
                else
                    FontSize(slot.value, GameFontHighlightSmall, "small")
                end
                Color(slot.value, row.color or WBF.UI.Colors.cream)
                slot.value:Show()
                cursor = cursor + (row.big and 22 or 18)
            end
        else
            slot.label:Hide()
            slot.value:Hide()
        end
    end
    if not ruleShown then
        card.Rule:Hide()
    end
end

local function ActivityRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(26)
    WBF.UI.BindWheel(row)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 8, 0)
    local whenText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    whenText:SetJustifyH("LEFT")
    whenText:SetWordWrap(false)
    Color(whenText, WBF.UI.Colors.cream)
    local change = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    change:SetJustifyH("LEFT")
    change:SetWordWrap(false)
    local balance = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    balance:SetJustifyH("RIGHT")
    balance:SetWordWrap(false)
    Color(balance, WBF.UI.Colors.cream)
    local who = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    who:SetJustifyH("LEFT")
    who:SetWordWrap(false)
    local note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetJustifyH("LEFT")
    note:SetWordWrap(false)
    Color(note, WBF.UI.Colors.muted)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 8, 0)
    line:SetPoint("BOTTOMRIGHT", -8, 0)
    line:SetColorTexture(1, 1, 1, 0.06)
    row.Icon = icon
    row.When = whenText
    row.Change = change
    row.Balance = balance
    row.Who = who
    row.Note = note
    return row
end

local function PeopleRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(40)
    WBF.UI.BindWheel(row)
    local portrait = row:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(32, 32)
    portrait:SetPoint("LEFT", 10, 0)
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 8, -2)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    local detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    detail:SetJustifyH("LEFT")
    Color(detail, WBF.UI.Colors.muted)
    local amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    amount:SetPoint("RIGHT", -12, 0)
    amount:SetJustifyH("RIGHT")
    Color(amount, WBF.UI.Colors.cream)
    row.Portrait = portrait
    row.Name = name
    row.Detail = detail
    row.Amount = amount
    return row
end

local function HideGraphics(plot)
    WBF.UI.HideCurve(plot)
    for index = 1, #plot.markers do
        plot.markers[index]:Hide()
    end
    for index = 1, #plot.yLabels do
        plot.yLabels[index]:Hide()
    end
    for index = 1, #plot.xLabels do
        plot.xLabels[index]:Hide()
    end
    for index = 1, #plot.grids do
        plot.grids[index]:Hide()
    end
    plot.guide:Hide()
    if plot.latest then
        plot.latest:Hide()
    end
    if plot.first then
        plot.first:Hide()
    end
end

-- The underlying resource history remains exact. This only prepares a cleaner
-- visual path: observations that share the same timestamp collapse to the final
-- balance at that instant, then a clamped Catmull-Rom curve is sampled between
-- real observations. Clamping keeps the curve inside the two adjacent balances
-- so smoothing can never invent a higher or lower balance than was recorded.
local function PlotPoints(points)
    local compact = {}
    for index = 1, #points do
        local point = points[index]
        local previous = compact[#compact]
        if previous and previous.at == point.at then
            compact[#compact] = point
        else
            compact[#compact + 1] = point
        end
    end
    return compact
end

-- Collapse observations that land almost on top of one another at the current
-- graph scale. The activity ledger and hover markers remain exact; this is only
-- for the visual stroke so a week/month graph does not turn several changes
-- within a few minutes into a jagged vertical staircase.
local function VisualCurvePoints(points, xOf, minPixelGap)
    local compact = PlotPoints(points)
    if #compact <= 2 then
        return compact
    end
    local output = { compact[1] }
    local gap = minPixelGap or 5
    for index = 2, #compact do
        local point = compact[index]
        local previous = output[#output]
        local distance = math.abs(xOf(point.at) - xOf(previous.at))
        if distance < gap and #output > 1 then
            output[#output] = point
        else
            output[#output + 1] = point
        end
    end
    if output[#output] ~= compact[#compact] then
        output[#output + 1] = compact[#compact]
    end
    return output
end

-- Monotone cubic tangents (Fritsch-Carlson style). This gives the balance line
-- a proper flowing curve without overshooting the balances that were actually
-- observed.
local function CurveTangents(xs, ys)
    local count = #xs
    local slopes = {}
    local tangents = {}
    if count < 2 then
        return tangents
    end
    for index = 1, count - 1 do
        local dx = xs[index + 1] - xs[index]
        slopes[index] = dx ~= 0 and ((ys[index + 1] - ys[index]) / dx) or 0
    end
    tangents[1] = slopes[1] or 0
    tangents[count] = slopes[count - 1] or 0
    for index = 2, count - 1 do
        local left = slopes[index - 1] or 0
        local right = slopes[index] or 0
        if left == 0 or right == 0 or (left < 0) ~= (right < 0) then
            tangents[index] = 0
        else
            tangents[index] = (left + right) / 2
        end
    end
    for index = 1, count - 1 do
        local slope = slopes[index] or 0
        if slope == 0 then
            tangents[index] = 0
            tangents[index + 1] = 0
        else
            local a = (tangents[index] or 0) / slope
            local b = (tangents[index + 1] or 0) / slope
            local magnitude = math.sqrt(a * a + b * b)
            if magnitude > 3 then
                local scale = 3 / magnitude
                tangents[index] = scale * a * slope
                tangents[index + 1] = scale * b * slope
            end
        end
    end
    return tangents
end

local function HermiteValue(y0, y1, tangent0, tangent1, span, t)
    local t2 = t * t
    local t3 = t2 * t
    local h00 = 2 * t3 - 3 * t2 + 1
    local h10 = t3 - 2 * t2 + t
    local h01 = -2 * t3 + 3 * t2
    local h11 = t3 - t2
    return h00 * y0 + h10 * span * tangent0 + h01 * y1 + h11 * span * tangent1
end

local function MarkerFrame(plot)
    local marker = CreateFrame("Frame", nil, plot)
    marker:SetSize(10, 10)
    marker:EnableMouse(true)
    WBF.UI.BindWheel(marker)
    local glow = marker:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(WBF.UI.Media.dot)
    glow:SetVertexColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 0.22)
    glow:SetSize(18, 18)
    glow:SetPoint("CENTER")
    glow:Hide()
    -- A dark outline keeps small dots reading as markers rather than as
    -- bumps in the stroke.
    local outline = marker:CreateTexture(nil, "OVERLAY", nil, 1)
    outline:SetTexture(WBF.UI.Media.dot)
    outline:SetVertexColor(0.04, 0.04, 0.05, 0.95)
    outline:SetSize(10, 10)
    outline:SetPoint("CENTER")
    local dot = marker:CreateTexture(nil, "OVERLAY", nil, 2)
    dot:SetTexture(WBF.UI.Media.dot)
    dot:SetSize(8, 8)
    dot:SetPoint("CENTER")
    marker.Ring = glow
    marker.Outline = outline
    marker.Dot = dot
    marker:SetScript("OnLeave", function(self)
        if GameTooltip then
            GameTooltip:Hide()
        end
        self.Outline:SetShown(self.pinned)
        self.Dot:SetShown(self.pinned)
    end)
    return marker
end

local function MarkerPoints(points)
    local rows = {}
    for index = 1, #points do
        local point = points[index]
        if not point.carried then
            local row = rows[#rows]
            if row and row.point.at == point.at then
                row.point = point
                row.count = row.count + 1
                row.delta = row.delta + (tonumber(point.delta) or 0)
                row.opening = row.opening or point.opening
                row.held = row.held or point.held
            else
                rows[#rows + 1] = {
                    point = point,
                    count = 1,
                    delta = tonumber(point.delta) or 0,
                    opening = point.opening,
                    held = point.held,
                }
            end
        end
    end
    return rows
end

local function DrawHistory(plot, model, plotWidth, plotHeight)
    HideGraphics(plot)
    local points = model.history or {}
    if #points == 0 then
        plot.empty:SetText("No balance observations in this period.")
        plot.empty:Show()
        return
    end
    plot.empty:Hide()

    -- The period still controls the report, but the graph viewport follows the
    -- actual observations inside that period. This avoids squeezing a few days
    -- of useful data into the far edge of a month-long chart.
    local realPoints = {}
    for index = 1, #points do
        if not points[index].carried then
            realPoints[#realPoints + 1] = points[index]
        end
    end
    local visiblePoints = #realPoints > 0 and realPoints or points
    local x0, x1
    if #visiblePoints >= 2 then
        local firstAt = visiblePoints[1].at
        local lastAt = visiblePoints[#visiblePoints].at
        local span = math.max(1, lastAt - firstAt)
        local padding = math.max(60, span * 0.045)
        x0 = firstAt - padding
        x1 = lastAt + padding
        if model.windowStart and x0 < model.windowStart then
            x0 = model.windowStart
        end
        if model.windowEnd and x1 > model.windowEnd then
            x1 = model.windowEnd
        end
    else
        local center = visiblePoints[1] and visiblePoints[1].at or model.windowStart or WBF.Time.Now()
        local windowSpan = (model.windowStart and model.windowEnd and model.windowEnd > model.windowStart) and (model.windowEnd - model.windowStart) or 3600
        local half = math.max(300, math.min(windowSpan * 0.08, 3600))
        x0 = center - half
        x1 = center + half
        if model.windowStart and x0 < model.windowStart then
            x0 = model.windowStart
        end
        if model.windowEnd and x1 > model.windowEnd then
            x1 = model.windowEnd
        end
    end
    if not x0 or not x1 or x1 <= x0 then
        x0 = visiblePoints[1] and visiblePoints[1].at or 0
        x1 = x0 + 1
    end

    local dataMin
    local dataMax
    local allowNegative = false
    for index = 1, #visiblePoints do
        local balance = tonumber(visiblePoints[index].balance) or 0
        if not dataMin or balance < dataMin then
            dataMin = balance
        end
        if not dataMax or balance > dataMax then
            dataMax = balance
        end
        if balance < 0 then
            allowNegative = true
        end
    end
    local labelCount = math.min(5, math.max(4, math.floor(plotHeight / 24)))
    local yTicks = WBF.Format.NiceBounds(dataMin, dataMax, labelCount, allowNegative)
    local axisMin = yTicks[1] or 0
    local axisMax = yTicks[#yTicks] or (axisMin + 1)
    if axisMax <= axisMin then
        axisMax = axisMin + 1
    end
    local function xOf(at)
        return (at - x0) / (x1 - x0) * plotWidth
    end
    local function yOf(balance)
        return (balance - axisMin) / (axisMax - axisMin) * plotHeight
    end

    for index = 1, #yTicks do
        local grid = plot.grids[index]
        if not grid then
            grid = plot:CreateTexture(nil, "BACKGROUND")
            grid:SetColorTexture(1, 1, 1, 0.055)
            plot.grids[index] = grid
        end
        local y = yOf(yTicks[index])
        grid:ClearAllPoints()
        grid:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y)
        grid:SetSize(plotWidth, 1)
        grid:Show()
        local label = plot.yLabels[index]
        if not label then
            label = plot:GetParent():CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetJustifyH("RIGHT")
            Color(label, WBF.UI.Colors.muted)
            plot.yLabels[index] = label
        end
        label:ClearAllPoints()
        label:SetPoint("RIGHT", plot, "BOTTOMLEFT", -6, y)
        label:SetText(WBF.Format.Number(yTicks[index]))
        label:Show()
    end

    local timeTicks = WBF.Format.TimeTicks(x0, x1, 5)
    for index = 1, #timeTicks do
        local label = plot.xLabels[index]
        if not label then
            label = plot:GetParent():CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetJustifyH("CENTER")
            Color(label, WBF.UI.Colors.muted)
            plot.xLabels[index] = label
        end
        local tick = timeTicks[index]
        label:ClearAllPoints()
        label:SetPoint("TOP", plot, "BOTTOMLEFT", xOf(tick.at), -4)
        label:SetText(tick.text)
        label:Show()
    end

    -- Render a smooth, monotone balance curve. Dense observations are
    -- visually coalesced first, then a clamped Hermite curve is sampled.
    -- The underlying ledger remains exact; smoothing is presentation only and
    -- cannot overshoot above/below adjacent recorded balances.
    local curvePoints = VisualCurvePoints(visiblePoints, xOf, 5)
    local drawn = 0
    local maxSegments = 520
    local pathXs, pathYs = {}, {}
    if #curvePoints >= 2 then
        local xs = {}
        local ys = {}
        for index = 1, #curvePoints do
            xs[index] = xOf(curvePoints[index].at)
            ys[index] = yOf(tonumber(curvePoints[index].balance) or 0)
        end
        local tangents = CurveTangents(xs, ys)
        pathXs[1], pathYs[1] = xs[1], ys[1]
        for index = 1, #curvePoints - 1 do
            if drawn >= maxSegments then
                break
            end
            local startX = xs[index]
            local endX = xs[index + 1]
            local span = endX - startX
            if span > 0.01 then
                -- Dense sampling keeps the angle between neighbouring segments
                -- small, so the joints vanish under the glow stroke.
                local samples = math.max(4, math.min(34, math.ceil(span / 4)))
                for sample = 1, samples do
                    if drawn >= maxSegments then
                        break
                    end
                    local t = sample / samples
                    local px = startX + span * t
                    local py = HermiteValue(ys[index], ys[index + 1], tangents[index] or 0, tangents[index + 1] or 0, span, t)
                    local lowY = math.min(ys[index], ys[index + 1])
                    local highY = math.max(ys[index], ys[index + 1])
                    if py < lowY then
                        py = lowY
                    elseif py > highY then
                        py = highY
                    end
                    drawn = drawn + 1
                    pathXs[drawn + 1] = px
                    pathYs[drawn + 1] = py
                end
            end
        end
    end
    WBF.UI.DrawCurve(plot, pathXs, pathYs, 0)

    local markerRows = MarkerPoints(visiblePoints)
    local markerCount = 0
    for index = 1, #markerRows do
        if markerCount >= 32 then
            break
        end
        local row = markerRows[index]
        local point = row.point
        markerCount = markerCount + 1
        local marker = plot.markers[markerCount]
        if not marker then
            marker = MarkerFrame(plot)
            plot.markers[markerCount] = marker
        end
        local px = xOf(point.at)
        local py = yOf(point.balance or 0)
        local last = index == #markerRows
        marker:SetSize(last and 13 or 8, last and 13 or 8)
        marker.Ring:SetShown(last)
        marker.Ring:SetSize(last and 18 or 13, last and 18 or 13)
        marker.Outline:SetSize(last and 11 or 9, last and 11 or 9)
        marker.Dot:SetSize(last and 7 or 6, last and 7 or 6)
        -- Only the latest point is drawn at rest; the rest stay invisible
        -- hover targets so clusters of changes don't crowd the line.
        marker.pinned = last
        marker.Outline:SetShown(last)
        marker.Dot:SetShown(last)
        local delta = tonumber(row.delta) or 0
        local markerColor = WBF.UI.Colors.gold
        if delta > 0 then
            markerColor = WBF.UI.Colors.green
        elseif delta < 0 then
            markerColor = WBF.UI.Colors.red
        elseif point.held then
            markerColor = WBF.UI.Colors.muted
        end
        marker.Dot:SetVertexColor(markerColor[1], markerColor[2], markerColor[3], 1)
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", plot, "BOTTOMLEFT", px, py)
        marker.point = point
        marker.stackCount = row.count
        marker.stackDelta = row.delta
        marker.stackOpening = row.opening
        marker.stackHeld = row.held
        marker:SetScript("OnEnter", function(self)
            if not GameTooltip then
                return
            end
            self.Outline:Show()
            self.Dot:Show()
            local hovered = self.point
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.ClearLines then
                GameTooltip:ClearLines()
            end
            WBF.UI.AddTip(GameTooltip, WBF.Format.ObservedAt(hovered.at), WBF.UI.Colors.gold)
            GameTooltip:AddLine("Balance: " .. WBF.Format.Number(hovered.balance or 0), 1, 1, 1)
            if (self.stackCount or 1) > 1 then
                WBF.UI.AddTip(GameTooltip, tostring(self.stackCount) .. " changes at this time", WBF.UI.Colors.tipDetail)
                if self.stackDelta and self.stackDelta ~= 0 then
                    local color = AmountColor(self.stackDelta)
                    GameTooltip:AddLine("Net change: " .. WBF.Format.Signed(self.stackDelta), color[1], color[2], color[3])
                end
            elseif self.stackOpening then
                WBF.UI.AddTip(GameTooltip, "Tracking started", WBF.UI.Colors.tipDetail)
            elseif self.stackHeld then
                WBF.UI.AddTip(GameTooltip, "Already held", WBF.UI.Colors.tipDetail)
            elseif hovered.delta and hovered.delta ~= 0 then
                local color = AmountColor(hovered.delta)
                GameTooltip:AddLine("Change: " .. WBF.Format.Signed(hovered.delta), color[1], color[2], color[3])
            end
            if hovered.name and hovered.name ~= "" then
                local r, g, b = 1, 1, 1
                if hovered.classFile then
                    r, g, b = WBF.Format.ClassColor(hovered.classFile)
                end
                GameTooltip:AddLine(hovered.name, r, g, b)
            end
            if hovered.note and hovered.note ~= "" then
                WBF.UI.AddTip(GameTooltip, hovered.note, WBF.UI.Colors.tipDetail, true)
            end
            GameTooltip:Show()
        end)
        marker:Show()

        if index == 1 and #markerRows > 1 then
            if not plot.first then
                plot.first = plot:GetParent():CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                plot.first:SetJustifyH("LEFT")
                Color(plot.first, WBF.UI.Colors.muted)
            end
            plot.first:ClearAllPoints()
            plot.first:SetText((point.opening and "Opening " or "Start ") .. WBF.Format.Number(point.balance or 0))
            if px < 54 then
                plot.first:SetPoint("LEFT", plot, "BOTTOMLEFT", px + 10, py + 12)
            else
                plot.first:SetPoint("RIGHT", plot, "BOTTOMLEFT", px - 10, py + 12)
            end
            plot.first:Show()
        end

        if last then
            plot.guide:ClearAllPoints()
            plot.guide:SetPoint("BOTTOM", plot, "BOTTOMLEFT", px, 0)
            plot.guide:SetSize(1, plotHeight)
            plot.guide:Show()
            if not plot.latest then
                plot.latest = plot:GetParent():CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                plot.latest:SetJustifyH("LEFT")
                Color(plot.latest, WBF.UI.Colors.cream)
            end
            plot.latest:ClearAllPoints()
            plot.latest:SetText("Ending " .. WBF.Format.Number(point.balance or 0))
            if px > plotWidth - 72 then
                plot.latest:SetJustifyH("RIGHT")
                plot.latest:SetPoint("RIGHT", plot, "BOTTOMLEFT", px - 10, py + 1)
            else
                plot.latest:SetJustifyH("LEFT")
                plot.latest:SetPoint("LEFT", plot, "BOTTOMLEFT", px + 10, py + 1)
            end
            plot.latest:Show()
        end
    end
end

function WBF.UI.ResourceDetail.Attach(parent)
    board = CreateFrame("Frame", nil, parent)
    board:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    board:Hide()
    WBF.UI.BindWheel(board)

    local icon = board:CreateTexture(nil, "ARTWORK")
    icon:SetSize(42, 42)
    icon:SetPoint("TOPLEFT", 0, 0)
    board.Icon = icon

    nameText = board:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    Color(nameText, WBF.UI.Colors.cream)
    FontSize(nameText, GameFontNormalLarge, "heading")

    chip = CreateFrame("Frame", nil, board, "BackdropTemplate")
    WBF.UI.Paint(chip, { 0.12, 0.09, 0.04, 0.95 }, WBF.UI.Colors.gold)
    chipText = chip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    chipText:SetPoint("CENTER")
    Color(chipText, WBF.UI.Colors.gold)

    sourceText = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sourceText:SetJustifyH("LEFT")
    sourceText:SetWordWrap(false)
    Color(sourceText, WBF.UI.Colors.muted)

    backButton = CreateFrame("Button", nil, board)
    backButton:SetHeight(28)
    WBF.UI.BindWheel(backButton)
    backLabel = backButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    backLabel:SetPoint("TOPRIGHT", 0, -4)
    backLabel:SetPoint("BOTTOMRIGHT", 0, 4)
    backLabel:SetJustifyH("RIGHT")
    backLabel:SetJustifyV("MIDDLE")
    Color(backLabel, WBF.UI.Colors.gold)
    FontSize(backLabel, GameFontHighlight, "body")
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

    balanceCard = MakeCard(board)
    local balanceLabel = balanceCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    balanceLabel:SetPoint("TOPLEFT", 14, -12)
    Color(balanceLabel, WBF.UI.Colors.muted)
    balanceLabel:SetText("CURRENT BALANCE")
    local balanceValue = balanceCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    balanceValue:SetPoint("TOPLEFT", 14, -40)
    balanceValue:SetJustifyH("LEFT")
    Color(balanceValue, WBF.UI.Colors.cream)
    FontSize(balanceValue, GameFontNormalHuge, "hero")
    local balanceIcon = balanceCard:CreateTexture(nil, "ARTWORK")
    balanceIcon:SetSize(36, 36)
    balanceIcon:SetPoint("LEFT", balanceValue, "RIGHT", 10, -2)
    local observed = balanceCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    observed:SetJustifyH("LEFT")
    Color(observed, WBF.UI.Colors.muted)
    observed:Hide()
    balanceCard.Value = balanceValue
    balanceCard.Icon = balanceIcon
    balanceCard.Observed = observed

    periodCard = MakeMetricCard(board)
    lifetimeCard = MakeMetricCard(board)

    historyCard = MakeCard(board)
    local historyTitle = historyCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    historyTitle:SetPoint("TOPLEFT", 12, -10)
    historyTitle:SetText("Balance History")
    Color(historyTitle, WBF.UI.Colors.gold)
    local historyLine = historyCard:CreateTexture(nil, "ARTWORK")
    historyLine:SetHeight(1)
    historyLine:SetPoint("LEFT", historyTitle, "RIGHT", 10, 0)
    historyLine:SetPoint("RIGHT", historyCard, "RIGHT", -12, 0)
    historyLine:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], WBF.UI.Colors.line[4])
    local plot = CreateFrame("Frame", nil, historyCard)
    plot.markers = {}
    plot.yLabels = {}
    plot.xLabels = {}
    plot.grids = {}
    plot.guide = plot:CreateTexture(nil, "ARTWORK")
    plot.guide:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 0.24)
    plot.guide:Hide()
    plot.empty = historyCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    plot.empty:SetPoint("CENTER", plot, "CENTER", 0, 0)
    plot.empty:SetJustifyH("CENTER")
    Color(plot.empty, WBF.UI.Colors.muted)
    plot.empty:Hide()
    historyCard.Plot = plot

    activityCard = MakeCard(board)
    local activityTitle = activityCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activityTitle:SetPoint("TOPLEFT", 12, -10)
    activityTitle:SetText("Recent Activity")
    Color(activityTitle, WBF.UI.Colors.gold)
    local activityLine = activityCard:CreateTexture(nil, "ARTWORK")
    activityLine:SetHeight(1)
    activityLine:SetPoint("LEFT", activityTitle, "RIGHT", 10, 0)
    activityLine:SetPoint("RIGHT", activityCard, "RIGHT", -12, 0)
    activityLine:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], WBF.UI.Colors.line[4])
    activityCard.Header = CreateFrame("Frame", nil, activityCard)
    activityCard.Header:SetHeight(18)
    local function headerLabel(text)
        local label = activityCard.Header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetJustifyH("LEFT")
        label:SetText(text)
        Color(label, WBF.UI.Colors.gold)
        return label
    end
    activityCard.HeadWhen = headerLabel("Date / Time")
    activityCard.HeadChange = headerLabel("Change")
    activityCard.HeadBalance = headerLabel("Balance")
    activityCard.HeadWho = headerLabel("Character")
    activityCard.HeadNote = headerLabel("Context")
    activityCard.Empty = activityCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    activityCard.Empty:SetJustifyH("LEFT")
    activityCard.Empty:SetWordWrap(true)
    Color(activityCard.Empty, WBF.UI.Colors.muted)

    peopleCard = MakeCard(board)
    local peopleTitle = peopleCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    peopleTitle:SetPoint("TOPLEFT", 12, -10)
    Color(peopleTitle, WBF.UI.Colors.gold)
    local peopleLine = peopleCard:CreateTexture(nil, "ARTWORK")
    peopleLine:SetHeight(1)
    peopleLine:SetPoint("LEFT", peopleTitle, "RIGHT", 10, 0)
    peopleLine:SetPoint("RIGHT", peopleCard, "RIGHT", -12, 0)
    peopleLine:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], WBF.UI.Colors.line[4])
    local peopleNote = peopleCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    peopleNote:SetPoint("TOPLEFT", 12, -32)
    peopleNote:SetJustifyH("LEFT")
    peopleNote:SetWordWrap(true)
    Color(peopleNote, WBF.UI.Colors.muted)
    peopleCard.Title = peopleTitle
    peopleCard.Note = peopleNote
    peopleCard.ShowZeroes = false
    peopleCard.ResourceKey = nil
    local zeroToggle = CreateFrame("Button", nil, peopleCard)
    zeroToggle:SetHeight(20)
    zeroToggle:EnableMouse(true)
    WBF.UI.BindWheel(zeroToggle)
    local zeroToggleText = zeroToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zeroToggleText:SetPoint("LEFT")
    zeroToggleText:SetJustifyH("LEFT")
    Color(zeroToggleText, WBF.UI.Colors.gold)
    zeroToggle.Text = zeroToggleText
    zeroToggle:SetScript("OnEnter", function()
        Color(zeroToggleText, { 1, 0.95, 0.72 })
    end)
    zeroToggle:SetScript("OnLeave", function()
        Color(zeroToggleText, WBF.UI.Colors.gold)
    end)
    zeroToggle:SetScript("OnClick", function()
        peopleCard.ShowZeroes = not peopleCard.ShowZeroes
        if board and board.LastModel then
            WBF.UI.ResourceDetail.Render(board.LastModel, board.LastWidth, board.LastViewHeight)
        end
    end)
    zeroToggle:Hide()
    peopleCard.ZeroToggle = zeroToggle

    local function MakePaneScroll(parent, step)
        local scroll = CreateFrame("ScrollFrame", nil, parent)
        scroll:EnableMouseWheel(true)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(40, 40)
        scroll:SetScrollChild(child)
        scroll.Child = child
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange()
            if range <= 1 then
                if WBF.UI.ScrollWheel then
                    WBF.UI.ScrollWheel(delta)
                end
                return
            end
            local nextValue = self:GetVerticalScroll() - delta * step
            if nextValue < 0 then
                nextValue = 0
            elseif nextValue > range then
                nextValue = range
            end
            self:SetVerticalScroll(nextValue)
        end)
        return scroll
    end
    activityCard.Scroll = MakePaneScroll(activityCard, 26)
    peopleCard.Scroll = MakePaneScroll(peopleCard, 44)

    emptyText = board:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyText:SetJustifyH("LEFT")
    emptyText:SetWordWrap(true)
    Color(emptyText, WBF.UI.Colors.muted)
    emptyText:Hide()
end

local function PlaceActivityColumns(width)
    local whenX = 28
    local whenW = math.max(96, math.floor(width * 0.24))
    local changeX = whenX + whenW
    local changeW = math.max(108, math.floor(width * 0.22))
    local balanceX = changeX + changeW
    local balanceW = math.max(52, math.floor(width * 0.12))
    local whoX = balanceX + balanceW + 8
    local whoW = math.max(72, math.floor(width * 0.16))
    local noteX = whoX + whoW
    local noteW = math.max(40, width - noteX - 8)
    return whenX, whenW, changeX, changeW, balanceX, balanceW, whoX, whoW, noteX, noteW
end

local function ShowIcon(texture, file)
    if file then
        texture:SetTexture(file)
    else
        texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    texture:Show()
end

function WBF.UI.ResourceDetail.Hide()
    if board then
        board:Hide()
    end
end

local function BackCaption(label)
    label = tostring(label or "Back")
    label = label:gsub("^%s+", "")
    label = label:gsub("^←%s*", "")
    label = label:gsub("^<%s*", "")
    label = label:gsub("^↩%s*", "")
    return "< " .. label
end

local function ObservedPhrase(at)
    if type(at) ~= "number" then
        return nil
    end
    local delta = math.max(0, WBF.Time.Now() - at)
    if delta < 45 then
        return "now"
    end
    return WBF.Format.Ago(at)
end

function WBF.UI.ResourceDetail.Render(model, width, viewHeight)
    if not board then
        return 40
    end
    model = model or {}
    board.LastModel = model
    board.LastWidth = width
    board.LastViewHeight = viewHeight
    if peopleCard and peopleCard.ResourceKey ~= model.key then
        peopleCard.ResourceKey = model.key
        peopleCard.ShowZeroes = false
    end
    WBF.UI.ReleaseAll()
    if WBF.UI.Detail.HideChrome then
        WBF.UI.Detail.HideChrome()
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
    board:Show()
    board:SetWidth(width)

    local back = BackCaption(model.backLabel or "Back")
    backLabel:SetText(back)
    local backWidth = math.max(140, (backLabel:GetStringWidth() or 140) + 8)
    backButton:ClearAllPoints()
    backButton:SetPoint("TOPRIGHT", board, "TOPRIGHT", 0, -2)
    backButton:SetWidth(math.min(backWidth, math.floor(width * 0.42)))

    ShowIcon(board.Icon, model.texture)
    nameText:ClearAllPoints()
    nameText:SetPoint("TOPLEFT", board.Icon, "TOPRIGHT", 10, 2)
    nameText:SetPoint("RIGHT", backButton, "LEFT", -8, 0)
    nameText:SetText(model.name or "Resource")

    local nameWidth = nameText:GetStringWidth() or 0
    if nameWidth < 8 then
        nameWidth = 120
    end
    local badge = model.badge
    local chipOnSecondLine = false
    if badge and badge ~= "" then
        chipText:SetText(badge)
        local chipWidth = math.max(72, (chipText:GetStringWidth() or 80) + 16)
        chip:SetSize(chipWidth, 18)
        chip:ClearAllPoints()
        local chipLeft = 52 + nameWidth + 10
        if chipLeft + chipWidth > width - backWidth - 12 then
            chip:SetPoint("TOPLEFT", board, "TOPLEFT", 52, -28)
            chipOnSecondLine = true
        else
            chip:SetPoint("TOPLEFT", board, "TOPLEFT", chipLeft, -2)
        end
        chip:Show()
    else
        chip:Hide()
    end
    if model.source and model.source ~= "" then
        sourceText:ClearAllPoints()
        if chip:IsShown() and chipOnSecondLine then
            sourceText:SetPoint("LEFT", chip, "RIGHT", 8, 0)
        else
            sourceText:SetPoint("TOPLEFT", board, "TOPLEFT", 52, -26)
        end
        sourceText:SetPoint("RIGHT", board, "RIGHT", -8, 0)
        sourceText:SetText(model.source)
        sourceText:Show()
    else
        sourceText:Hide()
    end

    local y = 64
    if model.missing then
        balanceCard:Hide()
        periodCard:Hide()
        lifetimeCard:Hide()
        historyCard:Hide()
        activityCard:Hide()
        peopleCard:Hide()
        emptyText:ClearAllPoints()
        emptyText:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
        emptyText:SetWidth(width)
        emptyText:SetText(model.emptyActivity or "Nothing recorded for this resource.")
        emptyText:Show()
        board:SetHeight(y + 36)
        return y + 36
    end
    emptyText:Hide()

    local gap = 8
    local cardHeight = 158
    local columns = width >= 640 and 3 or 1
    local cardWidth = columns == 3 and math.floor((width - gap * 2) / 3) or width
    balanceCard:ClearAllPoints()
    balanceCard:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
    balanceCard:SetSize(cardWidth, cardHeight)
    balanceCard:Show()
    balanceCard.Value:ClearAllPoints()
    local phrase = ObservedPhrase(model.lastObservedAt)
    if phrase then
        balanceCard.Value:SetPoint("LEFT", balanceCard, "LEFT", 16, 6)
        balanceCard.Observed:ClearAllPoints()
        balanceCard.Observed:SetPoint("TOPLEFT", balanceCard.Value, "BOTTOMLEFT", 1, -4)
        balanceCard.Observed:SetText("Last observed: " .. phrase)
        balanceCard.Observed:Show()
    else
        balanceCard.Value:SetPoint("LEFT", balanceCard, "LEFT", 16, -4)
        balanceCard.Observed:Hide()
    end
    balanceCard.Value:SetText(model.current ~= nil and WBF.Format.Number(model.current) or "—")
    ShowIcon(balanceCard.Icon, model.texture)

    local period = model.period or {}
    local periodRows = {
        { label = "Net Change", value = SignedText(period.net), color = AmountColor(period.net or 0), big = true },
        { label = "Gained", value = SignedText(period.earned), color = (period.earned or 0) > 0 and WBF.UI.Colors.green or WBF.UI.Colors.cream },
        { label = "Spent / Removed", value = (period.spent or 0) > 0 and WBF.Format.Signed(-(period.spent)) or "0", color = (period.spent or 0) > 0 and WBF.UI.Colors.red or WBF.UI.Colors.cream },
    }
    if period.opening ~= nil or period.current ~= nil then
        periodRows[#periodRows + 1] = { rule = true }
    end
    if period.opening ~= nil then
        periodRows[#periodRows + 1] = { label = "Opening Balance", value = WBF.Format.Number(period.opening), color = WBF.UI.Colors.cream }
    end
    if period.current ~= nil then
        periodRows[#periodRows + 1] = {
            label = model.closed and "Balance at Period End" or "Current Balance",
            value = WBF.Format.Number(period.current),
            color = WBF.UI.Colors.cream,
        }
    end
    periodCard.Title:SetText((model.periodTitle or "This Period"):upper())
    FillMetrics(periodCard, periodRows, 32)

    local lifeRows = {}
    local life = model.lifetime
    if life then
        if life.firstAt then
            lifeRows[#lifeRows + 1] = { label = "First Observed", value = date("%d %b %Y", life.firstAt), color = WBF.UI.Colors.cream }
        end
        if life.highest ~= nil then
            lifeRows[#lifeRows + 1] = { label = "Highest Balance", value = WBF.Format.Number(life.highest), color = WBF.UI.Colors.cream }
        end
        if life.gained ~= nil then
            lifeRows[#lifeRows + 1] = { label = "Total Gained", value = WBF.Format.Number(life.gained), color = WBF.UI.Colors.cream }
        end
        if life.spent ~= nil then
            lifeRows[#lifeRows + 1] = { label = "Total Spent", value = WBF.Format.Number(life.spent), color = WBF.UI.Colors.cream }
        end
    end
    lifetimeCard.Title:SetText("ALL TIME TRACKING")
    FillMetrics(lifetimeCard, lifeRows, 32)

    periodCard:ClearAllPoints()
    lifetimeCard:ClearAllPoints()
    if columns == 3 then
        periodCard:SetPoint("TOPLEFT", balanceCard, "TOPRIGHT", gap, 0)
        lifetimeCard:SetPoint("TOPLEFT", periodCard, "TOPRIGHT", gap, 0)
        periodCard:SetSize(cardWidth, cardHeight)
        lifetimeCard:SetSize(width - cardWidth * 2 - gap * 2, cardHeight)
    else
        periodCard:SetPoint("TOPLEFT", balanceCard, "BOTTOMLEFT", 0, -gap)
        lifetimeCard:SetPoint("TOPLEFT", periodCard, "BOTTOMLEFT", 0, -gap)
        periodCard:SetSize(width, cardHeight)
        lifetimeCard:SetSize(width, cardHeight)
    end
    periodCard:Show()
    lifetimeCard:Show()
    local cardRows = columns == 3 and 1 or 3
    y = y + cardRows * cardHeight + (cardRows - 1) * gap + 10

    local historyHeight = 196
    historyCard:ClearAllPoints()
    historyCard:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
    historyCard:SetSize(width, historyHeight)
    historyCard:Show()
    local plot = historyCard.Plot
    local plotLeft = 48
    local plotWidth = math.max(40, width - plotLeft - 12)
    local plotHeight = 120
    plot:ClearAllPoints()
    plot:SetPoint("TOPLEFT", historyCard, "TOPLEFT", plotLeft, -34)
    plot:SetSize(plotWidth, plotHeight)
    DrawHistory(plot, model, plotWidth, plotHeight)
    y = y + historyHeight + 10

    local split = width >= 640
    local leftWidth = split and math.floor((width - gap) * 0.66) or width
    local rightWidth = split and (width - leftWidth - gap) or width
    local activity = model.activity or {}
    local headerHeight = 22
    local rowHeight = 26
    local activityBody = #activity > 0 and (headerHeight + math.min(#activity, 6) * rowHeight) or 36
    local activityHeight = 36 + activityBody + 12

    activityCard:ClearAllPoints()
    activityCard:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
    activityCard:SetWidth(leftWidth)
    activityCard:Show()
    activityCard.Header:ClearAllPoints()
    activityCard.Header:SetPoint("TOPLEFT", activityCard, "TOPLEFT", 0, -32)
    activityCard.Header:SetWidth(leftWidth)
    local whenX, whenW, changeX, changeW, balanceX, balanceW, whoX, whoW, noteX, noteW = PlaceActivityColumns(leftWidth)
    local function placeHeader(label, x, columnWidth)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", activityCard.Header, "TOPLEFT", x, 0)
        label:SetWidth(columnWidth)
    end
    if #activity > 0 then
        activityCard.Header:Show()
        placeHeader(activityCard.HeadWhen, whenX, whenW)
        placeHeader(activityCard.HeadChange, changeX, changeW)
        placeHeader(activityCard.HeadBalance, balanceX, balanceW)
        placeHeader(activityCard.HeadWho, whoX, whoW)
        placeHeader(activityCard.HeadNote, noteX, noteW)
        activityCard.Empty:Hide()
    else
        activityCard.Header:Hide()
        activityCard.Empty:ClearAllPoints()
        activityCard.Empty:SetPoint("TOPLEFT", activityCard, "TOPLEFT", 12, -36)
        activityCard.Empty:SetWidth(leftWidth - 24)
        activityCard.Empty:SetText(model.emptyActivity or "No balance changes detected in this period.")
        activityCard.Empty:Show()
    end
    local activityScroll = activityCard.Scroll
    local activityChild = activityScroll.Child
    if #activity > 0 then
        activityScroll:Show()
    else
        activityScroll:Hide()
    end
    for index = 1, #activity do
        local entry = activity[index]
        local row = EnsureRow(activityRows, index, function()
            return ActivityRow(activityChild)
        end)
        row:SetParent(activityChild)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            local handler = activityScroll:GetScript("OnMouseWheel")
            if handler then
                handler(activityScroll, delta)
            end
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", activityChild, "TOPLEFT", 0, -((index - 1) * rowHeight))
        row:SetWidth(leftWidth)
        ShowIcon(row.Icon, model.texture)
        row.When:ClearAllPoints()
        row.When:SetPoint("LEFT", row, "LEFT", whenX, 0)
        row.When:SetWidth(whenW)
        row.When:SetText(entry.at and (date("%d %b %H:%M", entry.at)) or "—")
        row.Change:ClearAllPoints()
        row.Change:SetPoint("LEFT", row, "LEFT", changeX, 0)
        row.Change:SetWidth(changeW)
        if entry.opening then
            row.Change:SetText("Tracking started")
            Color(row.Change, WBF.UI.Colors.cream)
        else
            row.Change:SetText(SignedText(entry.delta))
            Color(row.Change, AmountColor(entry.delta or 0))
        end
        row.Balance:ClearAllPoints()
        row.Balance:SetPoint("LEFT", row, "LEFT", balanceX, 0)
        row.Balance:SetWidth(balanceW)
        row.Balance:SetText(entry.balance ~= nil and WBF.Format.Number(entry.balance) or "—")
        row.Who:ClearAllPoints()
        row.Who:SetPoint("LEFT", row, "LEFT", whoX, 0)
        row.Who:SetWidth(whoW)
        row.Who:SetText(entry.name or "—")
        if entry.classFile then
            row.Who:SetTextColor(WBF.Format.ClassColor(entry.classFile))
        else
            Color(row.Who, WBF.UI.Colors.cream)
        end
        row.Note:ClearAllPoints()
        row.Note:SetPoint("LEFT", row, "LEFT", noteX, 0)
        row.Note:SetWidth(noteW)
        row.Note:SetText(entry.note or "")
        row:Show()
    end
    HideFrom(activityRows, #activity + 1)

    local allPeople = model.people or {}
    local balances = model.peopleMode == "balances"
    local hasObservedAmounts = false
    local hasSharedAmounts = false
    for index = 1, #allPeople do
        if type(allPeople[index].amount) == "number" then
            hasObservedAmounts = true
            if allPeople[index].shared then
                hasSharedAmounts = true
            end
        end
    end

    local people = {}
    for index = 1, #allPeople do
        local entry = allPeople[index]
        -- Zero balances are useful internally to prove a character was
        -- observed, but they add noise to the holder/breakdown UI. Keep the
        -- snapshot and simply omit the row from presentation. Shared balances
        -- are not filtered because they represent one Warband pool.
        local hideZero = type(entry.amount) == "number" and entry.amount == 0 and not entry.shared
        if not hideZero then
            people[#people + 1] = entry
        end
    end

    peopleCard.Title:SetText(balances and "Character Balances" or "Observed On")
    if #allPeople == 0 then
        peopleCard.Note:SetText(balances and "No character balances recorded." or "Not observed on a character yet.")
    elseif balances then
        peopleCard.Note:SetText("Last known amount held by each character.")
    elseif hasSharedAmounts then
        peopleCard.Note:SetText("Observed characters. Shared currencies use one Warband balance.")
    elseif hasObservedAmounts then
        peopleCard.Note:SetText("Last known amount on each observed character.")
    else
        peopleCard.Note:SetText("This resource has been observed while playing the following characters:")
    end
    peopleCard.Note:SetWidth(rightWidth - 24)
    local noteHeight = peopleCard.Note:GetStringHeight() or 0
    local noteFloor = (not balances and #allPeople > 0) and 32 or 16
    if noteHeight < noteFloor then
        noteHeight = noteFloor
    end
    local peopleTop = 36 + noteHeight + 6
    local toggleHeight = 0
    local peopleBody = #people > 0 and (math.min(#people, 4) * 44) or 24
    local peopleHeight = peopleTop + peopleBody + toggleHeight + 8
    peopleCard:ClearAllPoints()
    if split then
        peopleCard:SetPoint("TOPLEFT", activityCard, "TOPRIGHT", gap, 0)
    else
        peopleCard:SetPoint("TOPLEFT", activityCard, "BOTTOMLEFT", 0, -gap)
    end
    peopleCard:SetWidth(rightWidth)
    peopleCard:Show()

    local zeroToggle = peopleCard.ZeroToggle
    zeroToggle:Hide()

    local peopleScroll = peopleCard.Scroll
    local peopleChild = peopleScroll.Child
    if #people > 0 then
        peopleScroll:Show()
    else
        peopleScroll:Hide()
    end
    for index = 1, #people do
        local entry = people[index]
        local row = EnsureRow(peopleRows, index, function()
            return PeopleRow(peopleChild)
        end)
        row:SetParent(peopleChild)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            local handler = peopleScroll:GetScript("OnMouseWheel")
            if handler then
                handler(peopleScroll, delta)
            end
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", peopleChild, "TOPLEFT", 0, -((index - 1) * 44))
        row:SetWidth(rightWidth)
        WBF.UI.SetPortrait(row.Portrait, entry.guid, entry.classFile)
        row.Name:SetText(entry.name or "—")
        local hasAmount = type(entry.amount) == "number"
        row.Name:SetPoint("RIGHT", (balances or hasAmount) and -96 or -12, 0)
        if entry.classFile then
            row.Name:SetTextColor(WBF.Format.ClassColor(entry.classFile))
        else
            Color(row.Name, WBF.UI.Colors.cream)
        end
        if balances then
            row.Detail:SetText("")
            row.Detail:Hide()
            row.Amount:SetText(WBF.Format.Number(entry.amount or 0))
            row.Amount:Show()
        else
            if hasAmount then
                if entry.shared then
                    row.Amount:SetText("Shared " .. WBF.Format.Number(entry.amount))
                else
                    row.Amount:SetText(WBF.Format.Number(entry.amount))
                end
                row.Amount:Show()
            else
                row.Amount:Hide()
            end
            if entry.at then
                row.Detail:SetText("Last seen: " .. WBF.Format.Ago(entry.at))
                row.Detail:Show()
            else
                row.Detail:Hide()
            end
        end
        row:Show()
    end
    HideFrom(peopleRows, #people + 1)

    local contentBottom = math.max(activityHeight, peopleHeight)
    local room = 0
    if type(viewHeight) == "number" and viewHeight > y + 120 then
        room = viewHeight - y - 4
    end
    local bottom = math.max(contentBottom, room)
    if split then
        activityCard:SetHeight(bottom)
        peopleCard:SetHeight(bottom)
        y = y + bottom
    else
        local stackedRoom = room > 0 and math.max(activityHeight + gap + peopleHeight, room) or (activityHeight + gap + peopleHeight)
        activityCard:SetHeight(activityHeight)
        peopleCard:SetHeight(math.max(peopleHeight, stackedRoom - activityHeight - gap))
        y = y + activityCard:GetHeight() + gap + peopleCard:GetHeight()
    end
    local scrollKey = (model.key or "") .. ":" .. (model.periodTitle or "")
    if activityCard.ScrollKey ~= scrollKey then
        activityScroll:SetVerticalScroll(0)
        peopleScroll:SetVerticalScroll(0)
        activityCard.ScrollKey = scrollKey
    end
    local function placeScroll(scroll, child, top, paneWidth, rowCount, rowSize, bottomInset)
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", scroll:GetParent(), "TOPLEFT", 0, -top)
        scroll:SetPoint("BOTTOMRIGHT", scroll:GetParent(), "BOTTOMRIGHT", -6, bottomInset or 8)
        local body = math.max(rowCount * rowSize, 1)
        child:SetSize(math.max(paneWidth - 8, 1), body)
    end
    if #activity > 0 then
        placeScroll(activityScroll, activityChild, 32 + headerHeight, leftWidth, #activity, rowHeight)
    end
    if #people > 0 then
        -- Zero-balance rows are filtered above and the old zero-toggle was removed.
        -- Keep a normal bottom inset here; referencing the retired zeroCount local
        -- caused resource detail rendering to abort after v0.1.27.
        placeScroll(peopleScroll, peopleChild, peopleTop, rightWidth, #people, 44, 8)
    end

    board:SetHeight(y + 8)
    return y + 8
end
