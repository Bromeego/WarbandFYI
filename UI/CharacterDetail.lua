local _, WBF = ...

WBF.UI.CharacterDetail = {}

local board
local parentFrame
local backButton
local backLabel
local portrait
local nameText
local subText

local TABS = {
    { id = "overview", label = "Overview" },
    { id = "professions", label = "Professions" },
    { id = "petBattles", label = "Pet Battles" },
    { id = "collections", label = "Collections" },
    { id = "activity", label = "Activity" },
}

local USED_LABEL = {
    current = "Used this session",
    last = "Used last session",
    today = "Used today",
    week = "Used this week",
    month = "Used this month",
    warband = "Used",
}

local KNOWLEDGE_LABEL = {
    current = "Knowledge gained this session",
    last = "Knowledge gained last session",
    today = "Knowledge gained today",
    week = "Knowledge gained this week",
    month = "Knowledge gained this month",
    warband = "Knowledge gained",
}

local GATHER_LABEL = {
    mining = {
        current = "Nodes gathered (session)",
        last = "Nodes gathered last session",
        today = "Nodes gathered today",
        week = "Nodes gathered this week",
        month = "Nodes gathered this month",
        warband = "Nodes gathered",
    },
    herbalism = {
        current = "Herbs gathered (session)",
        last = "Herbs gathered last session",
        today = "Herbs gathered today",
        week = "Herbs gathered this week",
        month = "Herbs gathered this month",
        warband = "Herbs gathered",
    },
    skinning = {
        current = "Creatures skinned (session)",
        last = "Creatures skinned last session",
        today = "Creatures skinned today",
        week = "Creatures skinned this week",
        month = "Creatures skinned this month",
        warband = "Creatures skinned",
    },
}

local RECIPE_LABEL = {
    current = "Recipes learned this session",
    last = "Recipes learned last session",
    today = "Recipes learned today",
    week = "Recipes learned this week",
    month = "Recipes learned this month",
    warband = "Recipes learned",
}

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

local function FindRow(summary, guid)
    if not summary or not guid then
        return nil
    end
    local characters = summary.characters or {}
    for index = 1, #characters do
        if characters[index].guid == guid then
            return characters[index]
        end
    end
    return nil
end

local function EventsFor(summary, guid, kind)
    local list = {}
    local activity = summary and summary.activity or {}
    for index = 1, #activity do
        local event = activity[index]
        if (not guid or event.guid == guid) and (not kind or event.eventType == kind) then
            list[#list + 1] = event
        end
    end
    return list
end

function WBF.UI.CharacterDetail.Attach(parent)
    parentFrame = parent
    board = CreateFrame("Frame", nil, parent)
    board:SetSize(400, 40)
    board:Hide()
    WBF.UI.BindWheel(board)

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

    local holder = CreateFrame("Frame", nil, board, "BackdropTemplate")
    holder:SetSize(54, 54)
    WBF.UI.Paint(holder, { 0.02, 0.02, 0.03, 1 }, WBF.UI.Colors.gold)
    board.Holder = holder
    portrait = holder:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("TOPLEFT", 1, -1)
    portrait:SetPoint("BOTTOMRIGHT", -1, 1)

    nameText = board:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetJustifyH("LEFT")
    subText = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subText:SetJustifyH("LEFT")
    Color(subText, WBF.UI.Colors.muted)

    local warbandLink = CreateFrame("Button", nil, board)
    warbandLink:SetSize(200, 18)
    WBF.UI.BindWheel(warbandLink)
    local warbandText = warbandLink:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warbandText:SetAllPoints()
    warbandText:SetJustifyH("LEFT")
    warbandText:SetText("Warband Pet Battles")
    Color(warbandText, WBF.UI.Colors.gold)
    warbandLink:Hide()
    board.WarbandLink = warbandLink
end

function WBF.UI.CharacterDetail.Hide()
    if board then
        board:Hide()
    end
end

local function TabPool()
    return WBF.UI.Pool("characterTab", function(parent)
        local frame = CreateFrame("Button", nil, parent)
        frame:SetHeight(26)
        WBF.UI.BindWheel(frame)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", 2, 0)
        label:SetJustifyH("LEFT")
        local line = frame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(2)
        line:SetPoint("BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", 0, 0)
        line:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 1)
        line:Hide()
        frame.Apply = function(self, tab, selected, click)
            label:SetText(tab.label)
            self:SetWidth(math.max(72, (label:GetStringWidth() or 72) + 16))
            if selected then
                Color(label, WBF.UI.Colors.gold)
                line:Show()
            else
                Color(label, WBF.UI.Colors.muted)
                line:Hide()
            end
            self:SetScript("OnClick", click)
        end
        return frame
    end)
end

local function ProfessionPool()
    return WBF.UI.Pool("professionCard", function(parent)
        local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        WBF.UI.Paint(frame, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        WBF.UI.BindWheel(frame)
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 12, -12)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        title:SetPoint("RIGHT", -12, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        Color(title, WBF.UI.Colors.gold)
        local skill = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        skill:SetPoint("TOPLEFT", 12, -48)
        skill:SetJustifyH("LEFT")
        Color(skill, WBF.UI.Colors.cream)
        local barBack = frame:CreateTexture(nil, "BACKGROUND")
        barBack:SetPoint("TOPLEFT", 12, -76)
        barBack:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
        barBack:SetHeight(8)
        barBack:SetColorTexture(0.14, 0.12, 0.08, 1)
        local bar = frame:CreateTexture(nil, "ARTWORK")
        bar:SetPoint("TOPLEFT", barBack, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", barBack, "BOTTOMLEFT", 0, 0)
        bar:SetColorTexture(0.86, 0.64, 0.24, 1)
        local rows = {}
        for index = 1, 6 do
            local left = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            left:SetJustifyH("LEFT")
            Color(left, WBF.UI.Colors.muted)
            local right = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            right:SetJustifyH("RIGHT")
            Color(right, WBF.UI.Colors.cream)
            rows[index] = { left = left, right = right }
        end
        frame.Apply = function(self, data, cardWidth)
            self:SetWidth(cardWidth)
            if data.icon then
                icon:SetTexture(data.icon)
            else
                WBF.UI.SetAtlasChain(icon, { "Professions-ChatIcon-Quality-Tier1" }, "Interface\\Icons\\INV_Misc_Gear_01")
            end
            title:SetText(data.label or data.name or "Profession")
            local current = data.skill or 0
            local maximum = data.maxSkill or 0
            if maximum > 0 then
                skill:SetText(WBF.Format.Number(current) .. " / " .. WBF.Format.Number(maximum))
            else
                skill:SetText(WBF.Format.Number(current))
            end
            local fraction = 0
            if maximum > 0 then
                fraction = math.min(1, current / maximum)
            end
            bar:SetWidth(math.max(2, math.floor((cardWidth - 24) * fraction)))
            local y = 94
            local shown = 0
            local lines = data.rows or {}
            for index = 1, #lines do
                if shown < #rows then
                    shown = shown + 1
                    local line = rows[shown]
                    line.left:ClearAllPoints()
                    line.right:ClearAllPoints()
                    line.left:SetPoint("TOPLEFT", 12, -y)
                    line.right:SetPoint("TOPRIGHT", -12, -y)
                    line.left:SetText(lines[index].label)
                    line.right:SetText(lines[index].value)
                    if lines[index].color then
                        Color(line.right, lines[index].color)
                    else
                        Color(line.right, WBF.UI.Colors.cream)
                    end
                    line.left:Show()
                    line.right:Show()
                    y = y + 18
                end
            end
            for index = shown + 1, #rows do
                rows[index].left:Hide()
                rows[index].right:Hide()
            end
            local height = math.max(108, y + 8)
            self:SetHeight(height)
            return height
        end
        return frame
    end)
end

local function TablePool()
    return WBF.UI.Pool("characterTable", function(parent)
        local frame = CreateFrame("Button", nil, parent)
        frame:SetHeight(22)
        WBF.UI.BindWheel(frame)
        local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.04)
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
        frame.Apply = function(self, row, rowWidth)
            self:SetWidth(rowWidth)
            timeText:SetText(row.time or "")
            eventText:ClearAllPoints()
            detailText:ClearAllPoints()
            eventText:SetPoint("LEFT", 64, 0)
            eventText:SetWidth(math.max(90, math.floor(rowWidth * 0.34)))
            eventText:SetText(row.event or "")
            detailText:SetPoint("LEFT", eventText, "RIGHT", 8, 0)
            detailText:SetPoint("RIGHT", -4, 0)
            detailText:SetText(row.detail or "")
        end
        return frame
    end)
end

local function NotePool()
    return WBF.UI.Pool("characterNote", function(parent)
        local frame = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame:SetJustifyH("LEFT")
        frame:SetWordWrap(true)
        Color(frame, WBF.UI.Colors.muted)
        return frame
    end)
end

local function ProgressPool()
    return WBF.UI.Pool("characterProgress", function(parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetHeight(20)
        WBF.UI.BindWheel(frame)
        local left = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        left:SetPoint("LEFT", 0, 0)
        left:SetJustifyH("LEFT")
        Color(left, WBF.UI.Colors.muted)
        local right = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        right:SetPoint("RIGHT", 0, 0)
        right:SetJustifyH("RIGHT")
        Color(right, WBF.UI.Colors.cream)
        frame.Apply = function(self, row, rowWidth)
            self:SetWidth(rowWidth)
            left:SetText(row.label)
            right:SetText(row.value)
            if row.color then
                Color(right, row.color)
            else
                Color(right, WBF.UI.Colors.cream)
            end
        end
        return frame
    end)
end

local function ProfessionRows(snap, stats, period, counts)
    local rows = {}
    if snap.concentration and snap.concentration.current ~= nil then
        local current = WBF.Format.Number(snap.concentration.current)
        local maximum = snap.concentration.max
        local value = current
        if maximum and maximum > 0 then
            value = current .. " / " .. WBF.Format.Number(maximum)
        end
        rows[#rows + 1] = { label = "Concentration", value = value }
    end
    if stats.used > 0 then
        rows[#rows + 1] = { label = USED_LABEL[period] or "Used", value = WBF.Format.Number(stats.used) }
    end
    if snap.knowledge and snap.knowledge.available ~= nil then
        rows[#rows + 1] = { label = "Knowledge available", value = WBF.Format.Number(snap.knowledge.available) }
    end
    if stats.knowledge > 0 then
        rows[#rows + 1] = {
            label = KNOWLEDGE_LABEL[period] or "Knowledge gained",
            value = WBF.Format.Signed(stats.knowledge),
            color = WBF.UI.Colors.green,
        }
    end
    if stats.recipes > 0 then
        rows[#rows + 1] = { label = RECIPE_LABEL[period] or "Recipes learned", value = tostring(stats.recipes) }
    end
    local gatherKind = nil
    if WBF.WorldActivity then
        gatherKind = WBF.WorldActivity.ProfessionKind(snap.professionEnum)
            or WBF.WorldActivity.KindFromName(snap.label)
            or WBF.WorldActivity.KindFromName(snap.name)
    end
    local gathered = gatherKind and counts and counts[gatherKind] or 0
    if gathered > 0 then
        local labels = GATHER_LABEL[gatherKind] or {}
        rows[#rows + 1] = { label = labels[period] or labels.warband or "Nodes gathered", value = tostring(gathered) }
    end
    return rows
end

local function ActivityRow(event)
    local meta = event.meta or {}
    return {
        time = WBF.Format.Ago(event.at),
        event = meta.eventLabel or event.text or "",
        detail = meta.detail or "",
    }
end

local function OtherProgress(counts)
    counts = counts or {}
    local rows = {}
    local function add(label, value, color)
        rows[#rows + 1] = { label = label, value = value, color = color }
    end
    if (counts.renown or 0) > 0 then
        add("Renown", tostring(counts.renown))
    end
    if (counts.reputation or 0) ~= 0 then
        add("Reputation", WBF.Format.Signed(counts.reputation), (counts.reputation or 0) > 0 and WBF.UI.Colors.green or WBF.UI.Colors.red)
    end
    if (counts.worldQuests or 0) > 0 then
        add("World Quests", tostring(counts.worldQuests))
    end
    if (counts.curseSurges or 0) > 0 then
        add("Curse Surges", tostring(counts.curseSurges))
    end
    if (counts.worldEvents or 0) > 0 then
        add("World Events", tostring(counts.worldEvents))
    end
    if (counts.quests or 0) > 0 then
        add("Quests", tostring(counts.quests))
    end
    if (counts.dungeons or 0) > 0 then
        add("Dungeons", tostring(counts.dungeons))
    end
    if (counts.raids or 0) > 0 then
        add("Raids", tostring(counts.raids))
    end
    if (counts.delves or 0) > 0 then
        add("Delves", tostring(counts.delves))
    end
    if (counts.rares or 0) > 0 then
        add("Rares", tostring(counts.rares))
    end
    if (counts.fishing or 0) > 0 then
        add("Fishing Catches", tostring(counts.fishing))
    end
    if (counts.mining or 0) > 0 then
        add("Mining Nodes", tostring(counts.mining))
    end
    if (counts.herbalism or 0) > 0 then
        add("Herb Nodes", tostring(counts.herbalism))
    end
    if (counts.lumber or 0) > 0 then
        add("Lumber", tostring(counts.lumber))
    end
    if (counts.skinning or 0) > 0 then
        add("Creatures Skinned", tostring(counts.skinning))
    end
    if (counts.bosses or 0) > 0 then
        add("Bosses", tostring(counts.bosses))
    end
    if (counts.knowledge or 0) > 0 then
        add("Profession Knowledge", WBF.Format.Signed(counts.knowledge), WBF.UI.Colors.green)
    end
    if (counts.concentrationUsed or 0) > 0 then
        add("Concentration Used", WBF.Format.Number(counts.concentrationUsed))
    end
    if (counts.recipes or 0) > 0 then
        add("Recipes Learned", tostring(counts.recipes))
    end
    return rows
end

local function PlaceStats(parent, stats, x, y, width, openTab)
    if #stats == 0 then
        return y
    end
    local gap = 8
    local columns = math.max(1, math.min(#stats, math.floor((width + gap) / 116)))
    local statWidth = math.floor((width - gap * (columns - 1)) / columns)
    local height = 64
    for index = 1, #stats do
        if stats[index].detail and stats[index].detail ~= "" then
            height = 78
            break
        end
    end
    for index = 1, #stats do
        local card = WBF.UI.AcquireStat(parent)
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        card:SetSize(statWidth, height)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", x + column * (statWidth + gap), -(y + row * (height + gap)))
        local data = stats[index]
        card:Apply(data)
        if openTab then
            card:SetScript("OnClick", function()
                if WBF.UI.frame and WBF.UI.frame.SetCharacterTab then
                    WBF.UI.frame:SetCharacterTab(openTab)
                end
            end)
        end
    end
    local rows = math.ceil(#stats / columns)
    return y + rows * height + (rows - 1) * gap
end

local function PlaceTable(parent, rows, x, y, width, limit)
    local shown = math.min(limit or #rows, #rows)
    if shown == 0 then
        local note = WBF.UI.Acquire(NotePool(), parent)
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        note:SetWidth(width)
        note:SetText("No activity in this period.")
        return y + 22
    end
    local header = WBF.UI.Acquire(TablePool(), parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    header:Apply({ time = "Time", event = "Event", detail = "Details" }, width)
    y = y + 20
    for index = 1, shown do
        local row = WBF.UI.Acquire(TablePool(), parent)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        row:Apply(rows[index], width)
        y = y + 22
    end
    return y
end

local function SummaryCards(counts, periodStats)
    local cards = {}
    counts = counts or {}
    if (counts.petBattles or 0) > 0 or (counts.petBattlesStarted or 0) > 0 then
        local battles = (counts.petBattles or 0) > 0 and counts.petBattles or counts.petBattlesStarted
        local detail
        if (counts.petWins or 0) + (counts.petLosses or 0) > 0 then
            detail = (counts.petWins or 0) .. "W / " .. (counts.petLosses or 0) .. "L"
        end
        cards[#cards + 1] = {
            label = "Pet Battles",
            value = tostring(battles),
            detail = detail,
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
            tooltip = "Battles recorded while this character was active.",
        }
    end
    if (counts.petLevels or 0) > 0 then
        cards[#cards + 1] = {
            label = "Pet Levels",
            value = WBF.Format.Signed(counts.petLevels),
            detail = (counts.petsLevel25 or 0) > 0 and (counts.petsLevel25 .. " reached level 25") or nil,
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
        }
    end
    if (counts.petsCaptured or 0) > 0 then
        cards[#cards + 1] = {
            label = "Pets Captured",
            value = tostring(counts.petsCaptured),
            detail = (counts.newPets or 0) > 0 and (counts.newPets .. " new") or nil,
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
        }
    end
    if periodStats.used > 0 then
        cards[#cards + 1] = {
            label = "Concentration Used",
            value = WBF.Format.Number(periodStats.used),
            atlases = { "Professions-ChatIcon-Quality-Tier1" },
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
        }
    end
    if periodStats.knowledge > 0 then
        cards[#cards + 1] = {
            label = "Profession Knowledge",
            value = WBF.Format.Signed(periodStats.knowledge),
            atlases = { "Professions-ChatIcon-Quality-Tier1" },
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
        }
    end
    if periodStats.recipes > 0 then
        cards[#cards + 1] = {
            label = "Recipes Learned",
            value = tostring(periodStats.recipes),
            atlases = { "Professions-ChatIcon-Quality-Tier1" },
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
        }
    end
    return cards
end

function WBF.UI.CharacterDetail.Render(summary, context, width)
    if not board then
        return 40
    end
    if WBF.UI.PetBattlesView and WBF.UI.PetBattlesView.Hide then
        WBF.UI.PetBattlesView.Hide()
    end
    WBF.UI.ReleaseAll()
    board:Show()
    board.WarbandLink:Hide()
    board:ClearAllPoints()
    board:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, 0)
    board:SetWidth(width)

    context = context or {}
    summary = summary or {}
    local guid = context.characterGUID
    local stored = guid and WBF.Characters.Get(guid) or nil
    local row = FindRow(summary, guid)
    local counts = row and row.counts or {}
    local period = context.period or summary.view or "week"
    local periodStats = WBF.Professions.PeriodStats(guid, summary.startAt, summary.endAt, nil)
    local snapshots = WBF.Professions.Snapshots(stored)
    local cards = {}
    for index = 1, #snapshots do
        if snapshots[index].isPrimary ~= false then
            cards[#cards + 1] = snapshots[index]
        end
    end
    if #cards == 0 then
        cards = snapshots
    end

    local tab = context.tab
    if not tab or tab == "" then
        tab = (#cards > 0 or periodStats.used > 0 or periodStats.knowledge > 0 or periodStats.recipes > 0) and "professions" or "overview"
    end

    local y = 0
    local back = BackCaption(WBF.Detail.BackLabel(WBF.UI.frame and WBF.UI.frame.detailStack))
    backLabel:SetText(back)
    backButton:ClearAllPoints()
    backButton:SetPoint("TOPRIGHT", board, "TOPRIGHT", 0, -y)
    backButton:SetWidth(math.max(150, (backLabel:GetStringWidth() or 150) + 8))

    board.Holder:ClearAllPoints()
    board.Holder:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
    WBF.UI.SetPortrait(portrait, guid, (row and row.classFile) or (stored and stored.classFile))
    local displayName = (row and row.name) or (stored and stored.name) or "Character"
    nameText:ClearAllPoints()
    nameText:SetPoint("TOPLEFT", board.Holder, "TOPRIGHT", 12, -4)
    nameText:SetPoint("RIGHT", backButton, "LEFT", -12, 0)
    nameText:SetText(displayName)
    nameText:SetTextColor(WBF.Format.ClassColor((row and row.classFile) or (stored and stored.classFile)))

    local bits = {}
    local closed = summary.closed == true
    local level = row and row.levelEnd or nil
    if level == nil and not closed then
        level = stored and stored.level or nil
    end
    if level then
        bits[#bits + 1] = "Level " .. level
    end
    local specName = (row and row.specName) or (stored and stored.specName)
    local className = (row and row.className) or (stored and stored.className)
    if specName and specName ~= "" and className and className ~= "" then
        bits[#bits + 1] = specName .. " " .. className
    elseif className and className ~= "" then
        bits[#bits + 1] = className
    end
    local ilvl = row and row.ilvlEnd or nil
    if ilvl == nil and not closed then
        ilvl = stored and stored.itemLevel or nil
    end
    if ilvl then
        bits[#bits + 1] = "Item Level " .. ilvl
    end
    subText:ClearAllPoints()
    subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
    subText:SetPoint("RIGHT", backButton, "LEFT", -12, 0)
    subText:SetText(table.concat(bits, "   |   "))
    y = 62

    local tabX = 0
    for index = 1, #TABS do
        local button = WBF.UI.Acquire(TabPool(), board)
        button:SetPoint("TOPLEFT", board, "TOPLEFT", tabX, -y)
        button:Apply(TABS[index], TABS[index].id == tab, function()
            if WBF.UI.frame and WBF.UI.frame.SetCharacterTab then
                WBF.UI.frame:SetCharacterTab(TABS[index].id)
            end
        end)
        tabX = tabX + button:GetWidth()
    end
    y = y + 34

    local function section(title)
        WBF.UI.AcquireSection(board, title, 0, y, width)
        y = y + 26
    end

    if tab == "professions" then
        section("Professions")
        if #cards == 0 then
            local note = WBF.UI.Acquire(NotePool(), board)
            note:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
            note:SetWidth(width)
            note:SetText("Profession details appear after this character is seen with a profession open.")
            y = y + 36
        else
            local columns = (width >= 640 and #cards > 1) and 2 or 1
            local cardWidth = columns == 2 and math.floor((width - 8) / 2) or width
            local cursor = y
            local prepared = {}
            local rowHeights = {}
            for index = 1, #cards do
                local snap = cards[index]
                local stats = WBF.Professions.PeriodStats(guid, summary.startAt, summary.endAt, snap.label or snap.name)
                snap.rows = ProfessionRows(snap, stats, period, counts)
                local card = WBF.UI.Acquire(ProfessionPool(), board)
                local height = card:Apply(snap, cardWidth)
                local cardRow = math.floor((index - 1) / columns)
                prepared[#prepared + 1] = {
                    card = card,
                    column = (index - 1) % columns,
                    row = cardRow,
                }
                rowHeights[cardRow] = math.max(rowHeights[cardRow] or 0, height)
            end
        local offset = {}
        local running = 0
        local rowIndex = 0
        while rowHeights[rowIndex] do
            offset[rowIndex] = running
            running = running + rowHeights[rowIndex] + 8
            rowIndex = rowIndex + 1
        end
        for index = 1, #prepared do
            local item = prepared[index]
            item.card:SetPoint("TOPLEFT", board, "TOPLEFT", item.column * (cardWidth + 8), -(cursor + (offset[item.row] or 0)))
        end
        y = cursor + math.max(0, running - 8)
        end
        y = y + 14

        local petCards = {}
        local function petCard(label, value, color)
            petCards[#petCards + 1] = {
                label = label,
                value = value,
                color = color,
                atlases = { "WildBattlePet" },
                fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
            }
        end
        if (counts.petBattles or 0) > 0 or (counts.petBattlesStarted or 0) > 0 then
            local battles = (counts.petBattles or 0) > 0 and counts.petBattles or counts.petBattlesStarted
            petCard("Battles", tostring(battles))
        end
        if (counts.petWins or 0) + (counts.petLosses or 0) > 0 then
            petCard("Wins / Losses", (counts.petWins or 0) .. " / " .. (counts.petLosses or 0))
        end
        if (counts.petsCaptured or 0) > 0 then
            petCard("Pets Captured", tostring(counts.petsCaptured))
        end
        if (counts.petLevels or 0) > 0 then
            petCard("Pet Levels", WBF.Format.Signed(counts.petLevels), WBF.UI.Colors.green)
        end
        if (counts.petsLevel25 or 0) > 0 then
            petCard("Reached Level 25", tostring(counts.petsLevel25))
        end
        if (counts.newPets or 0) > 0 then
            petCard("New Pets", tostring(counts.newPets))
        end

        local progress = OtherProgress(counts)
        local split = width >= 680 and #petCards > 0 and #progress > 0
        local leftWidth = split and math.floor(width * 0.62) or width
        local rightWidth = split and (width - leftWidth - 12) or width
        local periodName = summary.label
        local petTitle = periodName and periodName ~= "" and ("Pet Battle Activity (" .. periodName .. ")") or "Pet Battle Activity"
        if split then
            WBF.UI.AcquireSection(board, petTitle, 0, y, leftWidth)
            local petBottom = PlaceStats(board, petCards, 0, y + 26, leftWidth, "petBattles")
            WBF.UI.AcquireSection(board, "Other Character Progress", leftWidth + 12, y, rightWidth)
            local rightY = y + 26
            for index = 1, #progress do
                local line = WBF.UI.Acquire(ProgressPool(), board)
                line:SetPoint("TOPLEFT", board, "TOPLEFT", leftWidth + 12, -rightY)
                line:Apply(progress[index], rightWidth)
                rightY = rightY + 22
            end
            y = math.max(petBottom, rightY) + 14
        else
            if #petCards > 0 then
                section(petTitle)
                y = PlaceStats(board, petCards, 0, y, width, "petBattles") + 14
            end
            if #progress > 0 then
                section("Other Character Progress")
                for index = 1, #progress do
                    local line = WBF.UI.Acquire(ProgressPool(), board)
                    line:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
                    line:Apply(progress[index], math.min(360, width))
                    y = y + 22
                end
                y = y + 14
            end
        end

        section("Recent Profession Activity")
        local professionEvents = EventsFor(summary, guid, WBF.EventType.Profession)
        local professionRows = {}
        for index = 1, #professionEvents do
            local event = professionEvents[index]
            if not (event.meta and event.meta.surface == false) then
                professionRows[#professionRows + 1] = ActivityRow(event)
            end
        end
        y = PlaceTable(board, professionRows, 0, y, width, 8) + 8
    elseif tab == "petBattles" then
        local note = WBF.UI.Acquire(NotePool(), board)
        note:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
        note:SetWidth(width)
        note:SetText("Activity while " .. displayName .. " was active. The pet collection stays Warband-wide.")
        y = y + 28
        local petCards = {}
        local function pet(label, value, color)
            if value and value ~= 0 then
                petCards[#petCards + 1] = {
                    label = label,
                    value = type(value) == "number" and tostring(value) or value,
                    color = color,
                    fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
                }
            end
        end
        pet("Battles", (counts.petBattles or 0) > 0 and counts.petBattles or ((counts.petBattlesStarted or 0) > 0 and counts.petBattlesStarted or nil))
        pet("Wins", counts.petWins, WBF.UI.Colors.green)
        pet("Losses", counts.petLosses, WBF.UI.Colors.red)
        pet("Pets Captured", counts.petsCaptured)
        pet("Pet Levels", (counts.petLevels or 0) > 0 and WBF.Format.Signed(counts.petLevels) or nil)
        pet("Reached Level 25", counts.petsLevel25)
        pet("New Pets", counts.newPets)
        if #petCards == 0 then
            local empty = WBF.UI.Acquire(NotePool(), board)
            empty:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
            empty:SetWidth(width)
            empty:SetText("No pet battle activity for this character in this period.")
            y = y + 28
        else
            y = PlaceStats(board, petCards, 0, y, width, nil) + 12
        end
        WBF.UI.AcquireSection(board, "Recent Pet Activity", 0, y, width)
        y = y + 26
        local petEvents = WBF.PetBattles.EventsFor(summary.startAt, summary.endAt, guid)
        local petRows = {}
        for index = 1, #petEvents do
            local event = petEvents[index]
            local meta = event.meta or {}
            if meta.surface ~= false and meta.kind ~= "battleStart" then
                petRows[#petRows + 1] = ActivityRow(event)
            end
        end
        y = PlaceTable(board, petRows, 0, y, width, 10) + 8
        board.WarbandLink:ClearAllPoints()
        board.WarbandLink:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
        board.WarbandLink:SetScript("OnClick", function()
            if WBF.UI.frame then
                WBF.UI.frame:OpenDetail("petBattles", { period = period, warband = true })
            end
        end)
        board.WarbandLink:Show()
        y = y + 28
    elseif tab == "collections" then
        local rows = {}
        local function take(kind, title)
            local events = EventsFor(summary, guid, kind)
            for index = 1, #events do
                local event = events[index]
                rows[#rows + 1] = {
                    time = WBF.Format.Ago(event.at),
                    event = title,
                    detail = event.text or "",
                }
            end
        end
        take(WBF.EventType.Mount, "Mount")
        take(WBF.EventType.Pet, "Pet")
        take(WBF.EventType.Appearance, "Appearance")
        if #rows == 0 then
            local note = WBF.UI.Acquire(NotePool(), board)
            note:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
            note:SetWidth(width)
            note:SetText("Nothing collected while this character was active during this period.")
            y = y + 28
        else
            y = PlaceTable(board, rows, 0, y, width, 16)
        end
    elseif tab == "activity" then
        local rows = {}
        local events = EventsFor(summary, guid, nil)
        for index = 1, #events do
            local event = events[index]
            if not (event.meta and event.meta.surface == false) then
                local meta = event.meta or {}
                rows[#rows + 1] = {
                    time = WBF.Format.Ago(event.at),
                    event = meta.eventLabel or (event.text or ""),
                    detail = meta.detail or "",
                }
            end
        end
        y = PlaceTable(board, rows, 0, y, width, 24)
    else
        local cardsForSummary = SummaryCards(counts, periodStats)
        if #cardsForSummary > 0 then
            y = PlaceStats(board, cardsForSummary, 0, y, width, nil) + 14
        end
        local progress = OtherProgress(counts)
        if #progress > 0 then
            WBF.UI.AcquireSection(board, "Character Progress", 0, y, width)
            y = y + 26
            for index = 1, #progress do
                local line = WBF.UI.Acquire(ProgressPool(), board)
                line:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -y)
                line:Apply(progress[index], math.min(360, width))
                y = y + 22
            end
            y = y + 8
        end
        WBF.UI.AcquireSection(board, "Recent Activity", 0, y, width)
        y = y + 26
        local rows = {}
        local events = EventsFor(summary, guid, nil)
        for index = 1, math.min(8, #events) do
            local event = events[index]
            local meta = event.meta or {}
            rows[#rows + 1] = {
                time = WBF.Format.Ago(event.at),
                event = meta.eventLabel or event.text or "",
                detail = meta.detail or "",
            }
        end
        y = PlaceTable(board, rows, 0, y, width, 8)
    end

    board:SetHeight(math.max(y + 8, 1))
    return y + 8
end
