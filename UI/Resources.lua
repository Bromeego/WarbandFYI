local _, WBF = ...

WBF.UI.Resources = {}

local MUTED = WBF.UI.Hex(WBF.UI.Colors.muted)
local GREEN = WBF.UI.Hex(WBF.UI.Colors.green)
local RED = WBF.UI.Hex(WBF.UI.Colors.red)

local root
local panel
local titleText
local detailText
local statusText
local updatedText
local emptyText
local refreshButton
local searchBox
local searchHint
local overviewButton
local tableButton
local filterButtons = {}
local historyButton
local watchButton

local FILTERS = {
    { id = "active", label = "Active" },
    { id = "events", label = "Events" },
    { id = "account", label = "Account" },
    { id = "retired", label = "Retired" },
    { id = "unknown", label = "Unknown" },
    { id = "all", label = "All" },
}

local function LongAgo(timestamp)
    if not timestamp then
        return "not yet"
    end
    local delta = math.max(0, WBF.Time.Now() - timestamp)
    if delta < 45 then
        return "just now"
    end
    if delta < 3600 then
        local minutes = math.max(1, math.floor(delta / 60))
        return minutes == 1 and "1 minute ago" or (minutes .. " minutes ago")
    end
    if delta < 86400 then
        local hours = math.floor(delta / 3600)
        return hours == 1 and "1 hour ago" or (hours .. " hours ago")
    end
    local days = math.floor(delta / 86400)
    if days < 14 then
        return days == 1 and "1 day ago" or (days .. " days ago")
    end
    return date("%b %d", timestamp)
end

local function ShortAgo(timestamp)
    if not timestamp then
        return "Never scanned"
    end
    if WBF.Time.Now() - timestamp < 90 then
        return "Now"
    end
    return WBF.Format.Ago(timestamp)
end

local function PaintChoice(button, selected)
    if selected then
        WBF.UI.Paint(button, WBF.UI.Colors.blue, WBF.UI.Colors.gold)
        button.Label:SetTextColor(WBF.UI.Colors.bright[1], WBF.UI.Colors.bright[2], WBF.UI.Colors.bright[3])
    else
        WBF.UI.Paint(button, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        WBF.UI.SetColor(button.Label, WBF.UI.Colors.choiceText)
    end
end

local function MakeChoice(parent, text)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetHeight(22)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    button.Label = label
    button:SetScript("OnClick", function(self)
        if self.OnChoice then
            self:OnChoice()
        end
    end)
    return button
end

local function CardPool()
    return WBF.UI.Pool("resourceCard", function(parent)
        local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
        frame:SetHeight(118)
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 8, -8)
        local name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
        name:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        local amount = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        amount:SetPoint("TOPLEFT", 8, -44)
        local caption = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        caption:SetPoint("TOPLEFT", amount, "BOTTOMLEFT", 0, -1)
        local earned = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        earned:SetPoint("BOTTOMLEFT", 8, 8)
        local spent = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        spent:SetPoint("LEFT", earned, "RIGHT", 12, 0)
        local quiet = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        quiet:SetPoint("BOTTOMLEFT", 8, 8)
        quiet:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        quiet:SetJustifyH("LEFT")
        local badge = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        badge:SetPoint("BOTTOMRIGHT", -8, 8)
        frame.Icon = icon
        frame.Name = name
        frame.Amount = amount
        frame.Caption = caption
        frame.Earned = earned
        frame.Spent = spent
        frame.Quiet = quiet
        frame.Badge = badge
        return frame
    end)
end

local function RowPool(kind, height)
    return WBF.UI.Pool(kind, function(parent)
        local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
        frame:SetHeight(height)
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", 8, 0)
        text:SetJustifyH("LEFT")
        frame.Text = text
        return frame
    end)
end

local function TablePool()
    return WBF.UI.Pool("resourceTableRow", function(parent)
        local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
        frame:SetHeight(26)
        local function Column(justify)
            local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetJustifyH(justify)
            return text
        end
        frame.Name = Column("LEFT")
        frame.Total = Column("RIGHT")
        frame.Week = Column("RIGHT")
        frame.Spent = Column("RIGHT")
        frame.Holders = Column("RIGHT")
        frame.Updated = Column("RIGHT")
        return frame
    end)
end

local function LayoutTableRow(frame, width)
    local columns = { 0, 0.36, 0.52, 0.66, 0.78, 0.88, 1 }
    local fields = { frame.Name, frame.Total, frame.Week, frame.Spent, frame.Holders, frame.Updated }
    for index = 1, #fields do
        local text = fields[index]
        text:ClearAllPoints()
        text:SetPoint("LEFT", frame, "LEFT", math.floor(width * columns[index]) + 8, 0)
        text:SetPoint("RIGHT", frame, "LEFT", math.floor(width * columns[index + 1]) - 6, 0)
    end
end

local function NotePool()
    return WBF.UI.Pool("resourceNote", function(parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetHeight(16)
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        text:SetPoint("LEFT", 0, 0)
        text:SetJustifyH("LEFT")
        frame.Text = text
        return frame
    end)
end

local function HeaderPool()
    return WBF.UI.Pool("resourceEraHeader", function(parent)
        local frame = CreateFrame("Button", nil, parent)
        frame:SetHeight(22)
        frame:RegisterForClicks("LeftButtonUp")
        local mark = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mark:SetPoint("LEFT", 0, 0)
        mark:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", mark, "RIGHT", 6, 0)
        title:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
        local count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        count:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        count:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", title, "RIGHT", 10, 0)
        line:SetPoint("RIGHT", count, "LEFT", -10, 0)
        line:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], WBF.UI.Colors.line[4])
        frame.Mark = mark
        frame.Title = title
        frame.Count = count
        return frame
    end)
end

local function TooltipHasLines()
    return GameTooltip and (GameTooltip:NumLines() or 0) > 0
end

local function TryTooltip(method, ...)
    if not GameTooltip or type(method) ~= "function" then
        return false
    end
    GameTooltip:ClearLines()
    local ok = pcall(method, GameTooltip, ...)
    return ok and TooltipHasLines()
end

local function ShowNativeTooltip(owner, trackingType, resourceId)
    if not owner or not GameTooltip or not resourceId then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if trackingType == "item" then
        shown = TryTooltip(GameTooltip.SetItemByID, resourceId)
        if not shown and C_Item and C_Item.GetItemInfo then
            local ok, _, link = pcall(C_Item.GetItemInfo, resourceId)
            if ok and type(link) == "string" and link ~= "" then
                shown = TryTooltip(GameTooltip.SetHyperlink, link)
            end
        end
    else
        shown = TryTooltip(GameTooltip.SetCurrencyByID, resourceId)
        if not shown and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink then
            local ok, link = pcall(C_CurrencyInfo.GetCurrencyLink, resourceId)
            if ok and type(link) == "string" and link ~= "" then
                shown = TryTooltip(GameTooltip.SetHyperlink, link)
            end
        end
        if not shown then
            shown = TryTooltip(GameTooltip.SetCurrencyTokenByID, resourceId)
        end
    end
    if shown then
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

local function HideTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function BindNativeTooltip(frame, trackingType, resourceId)
    frame.trackingType = trackingType
    frame.resourceId = resourceId
    frame:SetScript("OnEnter", function(self)
        ShowNativeTooltip(self, self.trackingType, self.resourceId)
    end)
    frame:SetScript("OnLeave", HideTooltip)
end

local function ApplyCard(frame, card, selected)
    if card.texture then
        frame.Icon:SetTexture(card.texture)
    else
        frame.Icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    end
    frame.Name:SetText(card.name)
    frame.Name:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
    frame.Amount:SetText(WBF.Format.Number(card.amount or 0))
    frame.Amount:SetTextColor(WBF.UI.Colors.bright[1], WBF.UI.Colors.bright[2], WBF.UI.Colors.bright[3])
    frame.Caption:SetText(card.caption or "")
    frame.Caption:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    local earned = card.earned or 0
    local spent = card.spent or 0
    local net = card.net
    if net == nil then
        net = earned - spent
    end
    if earned > 0 or spent > 0 then
        frame.Quiet:Hide()
        frame.Earned:Show()
        local weekValue = net == 0 and "0 net" or WBF.Format.Signed(net)
        frame.Earned:SetText(weekValue .. "  " .. (card.periodLabel or "this week"))
        local weekColor = WBF.UI.Colors.cream
        if net > 0 then
            weekColor = WBF.UI.Colors.green
        elseif net < 0 then
            weekColor = WBF.UI.Colors.red
        end
        frame.Earned:SetTextColor(weekColor[1], weekColor[2], weekColor[3])
        if spent > 0 then
            frame.Spent:Show()
            frame.Spent:SetText(WBF.Format.Signed(-spent) .. "  spent")
            frame.Spent:SetTextColor(WBF.UI.Colors.red[1], WBF.UI.Colors.red[2], WBF.UI.Colors.red[3])
        else
            frame.Spent:Hide()
        end
    else
        frame.Earned:Hide()
        frame.Spent:Hide()
        frame.Quiet:Show()
        frame.Quiet:ClearAllPoints()
        frame.Quiet:SetPoint("BOTTOMLEFT", 8, 8)
        if card.badge and card.badge ~= "" then
            frame.Quiet:SetPoint("RIGHT", frame.Badge, "LEFT", -6, 0)
        else
            frame.Quiet:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        end
        if card.quiet and card.lastChangeAt then
            frame.Quiet:SetText("No recent activity    Last change: " .. LongAgo(card.lastChangeAt))
        elseif card.quiet then
            frame.Quiet:SetText("No recent activity")
        else
            frame.Quiet:SetText("")
        end
        frame.Quiet:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    end
    if card.badge and card.badge ~= "" then
        frame.Badge:Show()
        frame.Badge:SetText(card.badge)
        if card.badge == "Active" then
            frame.Badge:SetTextColor(WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3])
        else
            frame.Badge:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
        end
    else
        frame.Badge:Hide()
    end
    if selected then
        WBF.UI.Paint(frame, WBF.UI.Colors.cardPressed, WBF.UI.Colors.gold)
    else
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    end
end

local function PassesFilter(card, filterId)
    if not filterId or filterId == "overview" or filterId == "all" then
        return true
    end
    if filterId == "active" then
        return card.active
    end
    if filterId == "events" then
        return card.kind == "event" or card.kind == "timewalking"
    end
    if filterId == "account" then
        return card.classification == "ACCOUNT_WIDE_CURRENCY"
    end
    if filterId == "retired" then
        return card.status == "retired"
    end
    if filterId == "unknown" then
        return card.status == "unknown"
    end
    return true
end

local function Matches(card, filterId, search)
    if search and search ~= "" then
        local haystack = string.lower((card.name or "") .. " " .. (card.eraLabel or "") .. " " .. (card.status or "") .. " " .. (card.kind or "") .. " " .. (card.header or "") .. " " .. (card.eventName or "") .. " " .. (card.badge or ""))
        if not string.find(haystack, string.lower(search), 1, true) then
            return false
        end
    end
    return PassesFilter(card, filterId)
end

local function CountGroup(resources, filterId)
    local count = 0
    for index = 1, #resources do
        if PassesFilter(resources[index], filterId) then
            count = count + 1
        end
    end
    return count
end

local function KeepSelection(matching)
    local selected = WBF.UI.resourceSelection
    for index = 1, #matching do
        if matching[index].key == selected then
            return selected
        end
    end
    if matching[1] then
        WBF.UI.resourceSelection = matching[1].key
        return matching[1].key
    end
    WBF.UI.resourceSelection = nil
    return nil
end

local function DefaultCollapsed(eraId, cards)
    if eraId == WBF.ResourceMeta.CurrentEra() or eraId == "cross_expansion" then
        return false
    end
    for index = 1, #cards do
        if cards[index].active then
            return false
        end
    end
    return true
end

local function GroupResources(resources, filterId, search)
    local eras = WBF.ResourceMeta.Ordered()
    local buckets = {}
    for index = 1, #eras do
        buckets[eras[index].id] = {}
    end
    local matching = {}
    for index = 1, #resources do
        local card = resources[index]
        if Matches(card, filterId, search) then
            matching[#matching + 1] = card
            local eraId = buckets[card.era] and card.era or "unknown"
            local bucket = buckets[eraId]
            bucket[#bucket + 1] = card
        end
    end
    local sections = {}
    for index = 1, #eras do
        local era = eras[index]
        local cards = buckets[era.id]
        if #cards > 0 then
            sections[#sections + 1] = {
                id = era.id,
                label = era.label,
                cards = cards,
            }
        end
    end
    return sections, matching
end

local function SelectCard(key)
    if WBF.UI.resourcePanelMode then
        WBF.UI.resourceSelection = key
        if WBF.UI.frame then
            WBF.UI.frame:Refresh(false)
        end
        return
    end
    if WBF.UI.frame then
        WBF.UI.frame:OpenDetail("resource", { resourceKey = key, period = "week" })
    end
end

local function HidePanelFields()
    if not panel then
        return
    end
    local fields = panel.fields
    if not fields then
        return
    end
    fields.icon:Hide()
    fields.name:Hide()
    fields.subtitle:Hide()
    fields.totalLabel:Hide()
    fields.totalValue:Hide()
    fields.weekLine:Hide()
    fields.updated:Hide()
    fields.source:Hide()
    fields.breakdown:Hide()
    fields.weekTitle:Hide()
    fields.activityTitle:Hide()
    fields.extra:Hide()
    fields.empty:Show()
    if fields.tip then
        fields.tip:Hide()
        fields.tip.trackingType = nil
        fields.tip.resourceId = nil
    end
    for index = 1, #fields.tags do
        fields.tags[index]:Hide()
    end
    for index = 1, #fields.metrics do
        fields.metrics[index]:Hide()
    end
    historyButton:Hide()
    watchButton:Hide()
end

local function RenderPanel(detail)
    if not panel or not panel:IsShown() then
        return
    end
    WBF.UI.ReleasePool(RowPool("resourceHolder", 18))
    WBF.UI.ReleasePool(RowPool("resourceActivity", 16))
    local fields = panel.fields
    if not detail then
        HidePanelFields()
        fields.empty:SetText("Select a resource.")
        return
    end
    fields.empty:Hide()
    fields.icon:Show()
    if fields.tip then
        fields.tip:Show()
        fields.tip:SetWidth(math.max(160, panel:GetWidth() - 24))
        fields.tip.trackingType = detail.trackingType
        fields.tip.resourceId = detail.id
    end
    if detail.texture then
        fields.icon:SetTexture(detail.texture)
    else
        fields.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    end
    fields.name:Show()
    fields.name:SetText(detail.name or "Resource")
    fields.subtitle:Show()
    fields.subtitle:SetText(detail.subtitle or "")
    local tagX = 12
    for index = 1, #fields.tags do
        local tag = fields.tags[index]
        local text = detail.tags and detail.tags[index] or nil
        if text then
            tag:Show()
            tag.Label:SetText(text)
            tag:SetWidth(math.max(48, tag.Label:GetStringWidth() + 12))
            tag:ClearAllPoints()
            tag:SetPoint("TOPLEFT", panel, "TOPLEFT", tagX, -78)
            tagX = tagX + tag:GetWidth() + 6
        else
            tag:Hide()
        end
    end
    fields.totalLabel:Show()
    fields.totalLabel:SetText(detail.totalLabel or "Total")
    fields.totalValue:Show()
    fields.totalValue:SetText(WBF.Format.Number(detail.amount or 0))
    local week = detail.week or {}
    fields.weekLine:Show()
    local weekNet = week.net
    if weekNet == nil then
        weekNet = (week.earned or 0) - (week.spent or 0)
    end
    local weekText = (weekNet == 0 and "0 net" or WBF.Format.Signed(weekNet)) .. " this week"
    fields.weekLine:SetText(weekText)
    if weekNet > 0 then
        fields.weekLine:SetTextColor(WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3])
    elseif weekNet < 0 then
        fields.weekLine:SetTextColor(WBF.UI.Colors.red[1], WBF.UI.Colors.red[2], WBF.UI.Colors.red[3])
    else
        fields.weekLine:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    end
    fields.updated:Show()
    fields.updated:SetText("Last updated:  " .. LongAgo(detail.lastUpdated))
    fields.source:Show()
    local observed = detail.observed or {}
    if detail.accountWide then
        if #observed > 0 then
            fields.source:SetText("Observed on  " .. table.concat(observed, "  ·  "))
        else
            fields.source:SetText("Warband shared")
        end
        fields.source:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    elseif detail.verified and not detail.sample then
        fields.source:SetText("Data from Blizzard account characters")
        fields.source:SetTextColor(WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3])
    else
        fields.source:SetText(detail.sourceLabel or "")
        fields.source:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    end

    local panelHeight = panel:GetHeight()
    if panelHeight < 200 then
        panelHeight = 640
    end
    local y = 196
    if detail.accountWide then
        fields.breakdown:Hide()
    else
        fields.breakdown:Show()
        fields.breakdown:SetText("Breakdown by Character")
        fields.breakdown:ClearAllPoints()
        fields.breakdown:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -y)
        y = y + 22
        local rows = detail.characters or {}
        local room = math.min(#rows, 6)
        for index = 1, room do
            if y > panelHeight - 210 then
                break
            end
            local row = rows[index]
            local line = WBF.UI.Acquire(RowPool("resourceHolder", 18), panel)
            line:SetWidth(panel:GetWidth() - 24)
            line:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -y)
            WBF.UI.Paint(line, WBF.UI.Colors.clear, WBF.UI.Colors.clear)
            local r, g, b = WBF.Format.ClassColor(row.classFile)
            local when = row.bank and "" or ("   " .. ShortAgo(row.lastScanned))
            line.Text:SetText(row.name .. "    " .. WBF.Format.Number(row.amount) .. when)
            line.Text:SetTextColor(r, g, b)
            y = y + 18
        end
    end

    y = y + 8
    fields.weekTitle:Show()
    fields.weekTitle:ClearAllPoints()
    fields.weekTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -y)
    y = y + 20
    local metrics
    if detail.accountWide then
        metrics = {
            { "Net Change", weekNet == 0 and "0" or WBF.Format.Signed(weekNet), weekNet },
            { "Opening", week.opening ~= nil and WBF.Format.Number(week.opening) or "—", 0 },
            { "Gained", WBF.Format.Number(week.earned or 0), week.earned or 0 },
            { "Removed", WBF.Format.Number(week.spent or 0), (week.spent or 0) > 0 and -1 or 0 },
        }
    else
        metrics = {
            { "Earned", WBF.Format.Signed(week.earned or 0), week.earned or 0 },
            { "Spent", WBF.Format.Signed(-(week.spent or 0)), -(week.spent or 0) },
            { "Transfers", WBF.Format.Number(week.transferred or 0), 0 },
            { "Net", WBF.Format.Signed(week.net or 0), week.net or 0 },
        }
    end
    local metricWidth = math.floor((panel:GetWidth() - 24) / 4)
    for index = 1, #fields.metrics do
        local box = fields.metrics[index]
        local metric = metrics[index]
        box:Show()
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", 12 + (index - 1) * metricWidth, -y)
        box:SetWidth(metricWidth - 4)
        box.Label:SetText(metric[1])
        box.Value:SetText(metric[2])
        if metric[3] > 0 then
            box.Value:SetTextColor(WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3])
        elseif metric[3] < 0 then
            box.Value:SetTextColor(WBF.UI.Colors.red[1], WBF.UI.Colors.red[2], WBF.UI.Colors.red[3])
        else
            box.Value:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
        end
    end
    y = y + 40
    if (detail.runs or 0) > 0 or (detail.bosses or 0) > 0 then
        fields.extra:Show()
        fields.extra:ClearAllPoints()
        fields.extra:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -y)
        fields.extra:SetText("Runs " .. (detail.runs or 0) .. "    Bosses " .. (detail.bosses or 0))
        y = y + 18
    else
        fields.extra:Hide()
    end
    fields.activityTitle:Show()
    fields.activityTitle:ClearAllPoints()
    fields.activityTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -y)
    y = y + 18
    local activity = detail.activity or {}
    local limit = math.min(#activity, 8)
    for index = 1, limit do
        if y > panelHeight - 78 then
            break
        end
        local entry = activity[index]
        local line = WBF.UI.Acquire(RowPool("resourceActivity", 16), panel)
        line:SetWidth(panel:GetWidth() - 24)
        line:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -y)
        WBF.UI.Paint(line, WBF.UI.Colors.clear, WBF.UI.Colors.clear)
        local delta = entry.delta or 0
        local color = MUTED
        if delta > 0 and entry.classification ~= "transfer" then
            color = GREEN
        elseif delta < 0 and entry.classification ~= "transfer" then
            color = RED
        end
        line.Text:SetText(ShortAgo(entry.at) .. "   " .. color .. WBF.Format.Signed(delta) .. "|r   " .. (entry.label or ""))
        line.Text:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
        y = y + 16
    end

    historyButton:Show()
    watchButton:Show()
    watchButton:SetText(detail.watched and "On Watchlist" or "Add to Watchlist")
    historyButton.resourceKey = detail.key
    watchButton.resourceKey = detail.key
    watchButton.watched = detail.watched
end

function WBF.UI.Resources.Attach(parent, sidePanel)
    root = parent
    panel = sidePanel

    titleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetText("Resources")
    titleText:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])

    detailText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailText:SetText("Currencies and event resources across your Warband.")
    detailText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    statusText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetJustifyH("LEFT")
    statusText:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])

    updatedText = root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    updatedText:SetJustifyH("RIGHT")

    refreshButton = WBF.UI.Button(root, "Refresh Now", 108, 22)
    refreshButton:SetScript("OnClick", function()
        if WBF.Resources.QueueFullScan then
            WBF.Resources.QueueFullScan()
        end
    end)

    overviewButton = MakeChoice(root, "Overview")
    overviewButton:SetScript("OnClick", function()
        WBF.UI.resourceMode = "overview"
        if WBF.UI.frame then
            WBF.UI.frame:Refresh(false)
        end
    end)
    tableButton = MakeChoice(root, "Table")
    tableButton:SetScript("OnClick", function()
        WBF.UI.resourceMode = "table"
        if WBF.UI.frame then
            WBF.UI.frame:Refresh(false)
        end
    end)

    for index = 1, #FILTERS do
        local info = FILTERS[index]
        local button = MakeChoice(root, info.label)
        button.filterId = info.id
        button:SetScript("OnClick", function(self)
            if WBF.UI.resourceFilter == self.filterId then
                WBF.UI.resourceFilter = "all"
            else
                WBF.UI.resourceFilter = self.filterId
            end
            if WBF.UI.frame then
                WBF.UI.frame:Refresh(false)
            end
        end)
        filterButtons[#filterButtons + 1] = button
    end

    searchBox = CreateFrame("EditBox", nil, root, "BackdropTemplate")
    searchBox:SetSize(150, 22)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    if WBF.UI.KeepKeyboard then
        WBF.UI.KeepKeyboard(searchBox)
    end
    searchBox:SetTextInsets(8, 6, 0, 0)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        searchHint:SetShown(self:GetText() == "")
        if not userInput then
            return
        end
        WBF.UI.resourceSearch = self:GetText() or ""
        if WBF.UI.frame then
            WBF.UI.frame:Refresh(false)
        end
    end)
    searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 8, 0)
    searchHint:SetText("Search")

    emptyText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyText:SetJustifyH("LEFT")
    emptyText:SetWordWrap(true)
    emptyText:SetText("WarbandFYI learns resources after you log in. A scan starts a few seconds later and stays out of the way during combat.")
    emptyText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    emptyText:Hide()

    if not panel then
        return
    end
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 12, -12)
    local name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    name:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    name:SetJustifyH("LEFT")
    name:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    subtitle:SetJustifyH("LEFT")
    local tags = {}
    for index = 1, 3 do
        local tag = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        tag:SetHeight(18)
        local label = tag:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("CENTER")
        tag.Label = label
        WBF.UI.Paint(tag, WBF.UI.Colors.track, WBF.UI.Colors.goldDim)
        label:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
        tags[index] = tag
    end
    local totalLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    totalLabel:SetPoint("TOPLEFT", 12, -104)
    totalLabel:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    local totalValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    totalValue:SetPoint("TOPLEFT", totalLabel, "BOTTOMLEFT", 0, -2)
    totalValue:SetTextColor(WBF.UI.Colors.bright[1], WBF.UI.Colors.bright[2], WBF.UI.Colors.bright[3])
    local weekLine = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    weekLine:SetPoint("TOPLEFT", totalValue, "BOTTOMLEFT", 0, -2)
    local updated = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    updated:SetPoint("TOPLEFT", weekLine, "BOTTOMLEFT", 0, -6)
    local source = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    source:SetPoint("TOPLEFT", updated, "BOTTOMLEFT", 0, -2)
    source:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    source:SetJustifyH("LEFT")
    local breakdown = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    breakdown:SetText("Breakdown by Character")
    breakdown:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    local weekTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    weekTitle:SetText("This Week")
    weekTitle:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    local metrics = {}
    for index = 1, 4 do
        local box = CreateFrame("Frame", nil, panel)
        box:SetHeight(36)
        local label = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", 0, 0)
        label:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
        local value = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
        box.Label = label
        box.Value = value
        metrics[index] = box
    end
    local extra = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    extra:SetTextColor(WBF.UI.Colors.cream[1], WBF.UI.Colors.cream[2], WBF.UI.Colors.cream[3])
    local activityTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activityTitle:SetText("Recent Activity")
    activityTitle:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("TOPLEFT", 12, -16)
    empty:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    local tip = CreateFrame("Frame", nil, panel)
    tip:SetPoint("TOPLEFT", 8, -8)
    tip:SetSize(220, 46)
    tip:EnableMouse(true)
    tip:SetFrameLevel(panel:GetFrameLevel() + 5)
    BindNativeTooltip(tip, nil, nil)
    tip:Hide()
    panel.fields = {
        icon = icon,
        name = name,
        subtitle = subtitle,
        tags = tags,
        totalLabel = totalLabel,
        totalValue = totalValue,
        weekLine = weekLine,
        updated = updated,
        source = source,
        breakdown = breakdown,
        weekTitle = weekTitle,
        metrics = metrics,
        extra = extra,
        activityTitle = activityTitle,
        empty = empty,
        tip = tip,
    }

    historyButton = WBF.UI.Button(panel, nil, nil, 22)
    historyButton:SetPoint("BOTTOMLEFT", 12, 36)
    historyButton:SetPoint("BOTTOMRIGHT", -12, 36)
    historyButton:SetText("View Full History")
    historyButton:SetScript("OnClick", function(self)
        if self.resourceKey and WBF.UI.frame then
            WBF.UI.frame:OpenDetail("resource", { resourceKey = self.resourceKey, period = "week" })
        end
    end)
    watchButton = WBF.UI.Button(panel, nil, nil, 22)
    watchButton:SetPoint("BOTTOMLEFT", 12, 10)
    watchButton:SetPoint("BOTTOMRIGHT", -12, 10)
    watchButton:SetText("Add to Watchlist")
    watchButton:SetScript("OnClick", function(self)
        if not self.resourceKey then
            return
        end
        WBF.Resources.SetWatched(self.resourceKey, not self.watched)
        if WBF.UI.frame then
            WBF.UI.frame:Refresh(false)
        end
    end)
end

local function PlaceEraHeader(eraId, label, cards, y, width)
    local collapsed = WBF.Resources.SectionCollapsed(eraId, DefaultCollapsed(eraId, cards))
    local header = WBF.UI.Acquire(HeaderPool(), root)
    header:SetWidth(width)
    header:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    header.Mark:SetText(collapsed and "+" or "-")
    header.Title:SetText(label)
    local count = #cards
    header.Count:SetText(count == 1 and "1 resource" or (count .. " resources"))
    header.Title:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    header:SetScript("OnClick", function()
        WBF.Resources.SetSectionCollapsed(eraId, not collapsed)
        HideTooltip()
        if WBF.UI.frame then
            WBF.UI.frame:Refresh(false)
        end
    end)
    header:SetScript("OnEnter", function(self)
        self.Title:SetTextColor(WBF.UI.Colors.bright[1], WBF.UI.Colors.bright[2], WBF.UI.Colors.bright[3])
    end)
    header:SetScript("OnLeave", function(self)
        self.Title:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    end)
    return collapsed, y + 26
end

function WBF.UI.Resources.Render(width)
    local searchCursor = nil
    if searchBox and searchBox:HasFocus() then
        searchCursor = searchBox:GetCursorPosition()
    end
    WBF.UI.ReleaseAll()
    local catalog = WBF.Resources.Catalog()
    local resources = catalog.resources or {}
    local filterId = WBF.UI.resourceFilter or "all"
    local mode = WBF.UI.resourceMode or "overview"
    local search = WBF.UI.resourceSearch or ""

    titleText:ClearAllPoints()
    titleText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
    detailText:ClearAllPoints()
    detailText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
    statusText:ClearAllPoints()
    statusText:SetPoint("TOPLEFT", detailText, "BOTTOMLEFT", 0, -8)
    local status = catalog.discovered .. " resources discovered"
    if (catalog.activeCount or 0) > 0 then
        status = status .. "   ·   " .. catalog.activeCount .. " active recently"
    end
    if catalog.status == "refreshing" then
        status = status .. "   ·   Refreshing"
    elseif catalog.status == "paused" then
        status = status .. "   ·   Paused during combat"
    end
    statusText:SetText(status)
    refreshButton:ClearAllPoints()
    refreshButton:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -28)
    updatedText:ClearAllPoints()
    updatedText:SetPoint("RIGHT", refreshButton, "LEFT", -10, 0)
    updatedText:SetText("Last updated:  " .. LongAgo(catalog.lastUpdated))

    local y = 78
    overviewButton:ClearAllPoints()
    overviewButton:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    overviewButton:SetWidth(88)
    tableButton:ClearAllPoints()
    tableButton:SetPoint("LEFT", overviewButton, "RIGHT", 6, 0)
    tableButton:SetWidth(64)
    PaintChoice(overviewButton, mode ~= "table")
    PaintChoice(tableButton, mode == "table")

    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -y)
    if not searchCursor then
        WBF.UI.Paint(searchBox, WBF.UI.Colors.well, WBF.UI.Colors.goldDim)
    end
    y = y + 30

    local chipX = 0
    for index = 1, #filterButtons do
        local button = filterButtons[index]
        local info = FILTERS[index]
        local count
        if info.id == "all" then
            count = #resources
        else
            count = CountGroup(resources, info.id)
        end
        local show = info.id == "all" or count > 0
        if show then
            button:Show()
            button.Label:SetText(info.label .. " (" .. count .. ")")
            button:SetWidth(button.Label:GetStringWidth() + 16)
            if chipX > 0 and chipX + button:GetWidth() > width then
                chipX = 0
                y = y + 26
            end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", root, "TOPLEFT", chipX, -y)
            PaintChoice(button, filterId == info.id)
            chipX = chipX + button:GetWidth() + 6
        else
            button:Hide()
        end
    end
    y = y + 32

    local sections, matching = GroupResources(resources, filterId, search)
    local selected = KeepSelection(matching)

    if #matching == 0 then
        if (catalog.discovered or 0) == 0 and not catalog.lastUpdated then
            emptyText:SetText("WarbandFYI learns resources after you log in. A scan starts a few seconds later and stays out of the way during combat.")
        else
            emptyText:SetText("No resources match this view.")
        end
        emptyText:Show()
        emptyText:ClearAllPoints()
        emptyText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        emptyText:SetWidth(width)
        HidePanelFields()
        return y + 48
    end
    emptyText:Hide()

    if mode == "table" then
        local header = WBF.UI.Acquire(TablePool(), root)
        header:SetWidth(width)
        header:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        LayoutTableRow(header, width)
        WBF.UI.Paint(header, { 0.05, 0.05, 0.07, 0.4 }, WBF.UI.Colors.goldDim)
        header.Name:SetText("Resource")
        header.Total:SetText("Total")
        header.Week:SetText("This Week")
        header.Spent:SetText("Spent")
        header.Holders:SetText("Characters")
        header.Updated:SetText("Updated")
        local gold = WBF.UI.Colors.gold
        header.Name:SetTextColor(gold[1], gold[2], gold[3])
        header.Total:SetTextColor(gold[1], gold[2], gold[3])
        header.Week:SetTextColor(gold[1], gold[2], gold[3])
        header.Spent:SetTextColor(gold[1], gold[2], gold[3])
        header.Holders:SetTextColor(gold[1], gold[2], gold[3])
        header.Updated:SetTextColor(gold[1], gold[2], gold[3])
        header:SetScript("OnClick", nil)
        header:SetScript("OnEnter", nil)
        header:SetScript("OnLeave", nil)
        y = y + 28
        for sectionIndex = 1, #sections do
            local section = sections[sectionIndex]
            local collapsed
            collapsed, y = PlaceEraHeader(section.id, section.label, section.cards, y, width)
            if not collapsed then
                for index = 1, #section.cards do
                    local card = section.cards[index]
                    local row = WBF.UI.Acquire(TablePool(), root)
                    row:SetWidth(width)
                    row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
                    LayoutTableRow(row, width)
                    row.Name:SetText(card.name)
                    row.Total:SetText(WBF.Format.Number(card.amount))
                    local earned = card.earned or 0
                    local spent = card.spent or 0
                    local net = card.net
                    if net == nil then
                        net = earned - spent
                    end
                    row.Week:SetText(net ~= 0 and WBF.Format.Signed(net) or "0")
                    row.Spent:SetText(spent > 0 and WBF.Format.Signed(-spent) or "0")
                    row.Holders:SetText(card.accountWide and "Shared" or tostring(card.holders or 0))
                    row.Updated:SetText(ShortAgo(card.freshAt or card.lastChangeAt))
                    local cream = WBF.UI.Colors.cream
                    row.Name:SetTextColor(cream[1], cream[2], cream[3])
                    row.Total:SetTextColor(cream[1], cream[2], cream[3])
                    if net > 0 then
                        row.Week:SetTextColor(WBF.UI.Colors.green[1], WBF.UI.Colors.green[2], WBF.UI.Colors.green[3])
                    elseif net < 0 then
                        row.Week:SetTextColor(WBF.UI.Colors.red[1], WBF.UI.Colors.red[2], WBF.UI.Colors.red[3])
                    else
                        row.Week:SetTextColor(cream[1], cream[2], cream[3])
                    end
                    if spent > 0 then
                        row.Spent:SetTextColor(WBF.UI.Colors.red[1], WBF.UI.Colors.red[2], WBF.UI.Colors.red[3])
                    else
                        row.Spent:SetTextColor(cream[1], cream[2], cream[3])
                    end
                    row.Holders:SetTextColor(cream[1], cream[2], cream[3])
                    row.Updated:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
                    if card.key == selected then
                        WBF.UI.Paint(row, WBF.UI.Colors.cardPressed, WBF.UI.Colors.gold)
                    else
                        WBF.UI.Paint(row, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
                    end
                    row:SetScript("OnClick", function()
                        SelectCard(card.key)
                    end)
                    row:SetScript("OnEnter", function(self)
                        ShowNativeTooltip(self, card.trackingType, card.id)
                        if card.key ~= selected then
                            WBF.UI.Paint(self, WBF.UI.Colors.cardHover, WBF.UI.Colors.cardHoverEdge)
                        end
                    end)
                    row:SetScript("OnLeave", function(self)
                        HideTooltip()
                        if card.key == selected then
                            WBF.UI.Paint(self, WBF.UI.Colors.cardPressed, WBF.UI.Colors.gold)
                        else
                            WBF.UI.Paint(self, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
                        end
                    end)
                    y = y + 28
                end
            end
            y = y + 6
        end
    else
        local gap = 8
        local columns = math.max(1, math.floor((width + gap) / 208))
        local cardWidth = math.floor((width - gap * (columns - 1)) / columns)
        for sectionIndex = 1, #sections do
            local section = sections[sectionIndex]
            local cards = section.cards
            local collapsed
            collapsed, y = PlaceEraHeader(section.id, section.label, cards, y, width)
            if not collapsed then
                for index = 1, #cards do
                    local card = cards[index]
                    local column = (index - 1) % columns
                    local row = math.floor((index - 1) / columns)
                    local widget = WBF.UI.Acquire(CardPool(), root)
                    widget:SetWidth(cardWidth)
                    widget:SetPoint("TOPLEFT", root, "TOPLEFT", column * (cardWidth + gap), -(y + row * 126))
                    ApplyCard(widget, card, card.key == selected)
                    widget:SetScript("OnClick", function()
                        SelectCard(card.key)
                    end)
                    widget:SetScript("OnEnter", function(self)
                        if card.key ~= selected then
                            WBF.UI.Paint(self, WBF.UI.Colors.cardHover, WBF.UI.Colors.cardHoverEdge)
                        end
                        ShowNativeTooltip(self, card.trackingType, card.id)
                    end)
                    widget:SetScript("OnLeave", function(self)
                        HideTooltip()
                        ApplyCard(self, card, card.key == selected)
                    end)
                end
                local rows = math.ceil(#cards / columns)
                y = y + rows * 126 + 8
            else
                y = y + 8
            end
        end
    end

    if WBF.UI.resourcePanelMode then
        RenderPanel(selected and WBF.Resources.Detail(selected) or nil)
    end
    if searchCursor and searchBox:IsShown() then
        local cursor = searchCursor
        local function restore()
            if searchBox:IsShown() then
                searchBox:SetFocus()
                searchBox:SetCursorPosition(cursor)
            end
        end
        restore()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, restore)
        end
    end
    return y + 8
end
