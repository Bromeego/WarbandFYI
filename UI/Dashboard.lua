local _, WBF = ...

WBF.UI.Dashboard = {}

local root
local titleText
local rangeText
local sampleText
local noteText
local viewAll
local prevMonth
local nextMonth

local function EnsureChrome()
    if titleText then
        return
    end
    titleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    titleText:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])

    rangeText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rangeText:SetJustifyH("LEFT")
    rangeText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    sampleText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sampleText:SetJustifyH("LEFT")
    sampleText:SetTextColor(0.95, 0.78, 0.35)
    sampleText:SetText("Sample history is mixed into this view. /wbfyi clearsample removes it.")

    noteText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    noteText:SetJustifyH("LEFT")
    noteText:SetWordWrap(true)
    noteText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    viewAll = CreateFrame("Button", nil, root)
    viewAll:SetSize(140, 18)
    WBF.UI.BindWheel(viewAll)
    local viewAllLabel = viewAll:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    viewAllLabel:SetAllPoints()
    viewAllLabel:SetJustifyH("LEFT")
    viewAllLabel:SetText("View all activity")
    viewAllLabel:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    viewAll:SetScript("OnClick", function()
        if WBF.UI.frame then
            WBF.UI.frame:SetView("activity")
        end
    end)

    local function MakeArrow(delta, tip)
        local button = CreateFrame("Button", nil, root)
        button:SetSize(22, 22)
        WBF.UI.BindWheel(button)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        label:SetAllPoints()
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetText(delta < 0 and "<" or ">")
        button.Label = label
        button.delta = delta
        button.tip = tip
        button.allowed = true
        button:SetScript("OnEnter", function(self)
            if self.allowed then
                self.Label:SetTextColor(1, 0.97, 0.82)
            end
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tip or "", 1, 0.82, 0.45)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function(self)
            local color = self.allowed and WBF.UI.Colors.gold or WBF.UI.Colors.muted
            self.Label:SetTextColor(color[1], color[2], color[3])
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        button:SetScript("OnClick", function(self)
            if not self.allowed or not WBF.UI.frame or not WBF.UI.frame.NudgeMonth then
                return
            end
            WBF.UI.frame:NudgeMonth(self.delta)
        end)
        return button
    end

    prevMonth = MakeArrow(-1, "Previous month")
    nextMonth = MakeArrow(1, "Next month")
end

local function StyleArrow(button, allowed)
    if not button then
        return
    end
    button.allowed = allowed == true
    local color = button.allowed and WBF.UI.Colors.gold or { 0.40, 0.42, 0.46 }
    button.Label:SetTextColor(color[1], color[2], color[3])
end

local function HideChrome()
    if not titleText then
        return
    end
    titleText:Hide()
    rangeText:Hide()
    sampleText:Hide()
    noteText:Hide()
    viewAll:Hide()
    if prevMonth then
        prevMonth:Hide()
    end
    if nextMonth then
        nextMonth:Hide()
    end
end

local function RangeLine(summary)
    if not summary.startAt or not summary.endAt then
        return ""
    end
    if summary.rangeText then
        return summary.rangeText
    end
    if summary.view == "current" then
        return "Started " .. WBF.Time.Clock(summary.startAt)
    end
    if summary.view == "last" then
        return "Started " .. WBF.Time.Clock(summary.startAt) .. "   ·   Ended " .. WBF.Time.Clock(summary.endAt)
    end
    if summary.startAt <= 0 then
        return "Everything recorded on this Warband"
    end
    return date("%b %d", summary.startAt) .. "  –  " .. date("%b %d", summary.endAt)
end

local function PreyTooltip(totals, startedOnly)
    local text = startedOnly and "Hunts started." or "Hunts completed."
    local known = (totals.preyNormal or 0) + (totals.preyHard or 0) + (totals.preyNightmare or 0)
    if not startedOnly and totals.prey > 0 and known == totals.prey then
        local bits = {}
        if totals.preyNormal > 0 then
            bits[#bits + 1] = totals.preyNormal .. " Normal"
        end
        if totals.preyHard > 0 then
            bits[#bits + 1] = totals.preyHard .. " Hard"
        end
        if totals.preyNightmare > 0 then
            bits[#bits + 1] = totals.preyNightmare .. " Nightmare"
        end
        if #bits > 0 then
            text = text .. "  " .. table.concat(bits, "  ·  ") .. "."
        end
    end
    if not startedOnly and (totals.preyStarted or 0) > 0 then
        text = text .. "  " .. totals.preyStarted .. " in progress."
    end
    if (totals.journey or 0) > 0 then
        text = text .. "  Journey " .. WBF.Format.Signed(totals.journey) .. "."
    end
    return text
end

local function GoldColor(copper)
    if copper > 0 then
        return WBF.UI.Colors.green
    end
    if copper < 0 then
        return WBF.UI.Colors.red
    end
    return WBF.UI.Colors.cream
end

local function NetText(net)
    if not net or net == 0 then
        return "0 net"
    end
    return WBF.Format.Signed(net)
end

local function ResourceWidgets(summary)
    local widgets = {}
    local resources = summary.resources or {}
    for index = 1, #resources do
        local resource = resources[index]
        local earned = resource.earned or 0
        local spent = resource.spent or 0
        local net = resource.net
        if net == nil then
            net = earned - spent
        end
        local color = WBF.UI.Colors.cream
        if net > 0 then
            color = WBF.UI.Colors.green
        elseif net < 0 then
            color = WBF.UI.Colors.red
        end
        local current = resource.current
        local detail
        local periodName = summary.periodPhrase or (summary.label and summary.label:lower()) or "this period"
        local tooltip = "Net " .. WBF.Format.Signed(net) .. " " .. periodName .. "."
        if type(current) == "number" then
            if summary.closed then
                detail = WBF.Format.Number(current) .. " at period end"
                tooltip = tooltip .. "  Balance at the end of this period " .. WBF.Format.Number(current) .. "."
            else
                detail = WBF.Format.Number(current) .. " current"
                tooltip = tooltip .. "  Current balance " .. WBF.Format.Number(current) .. "."
            end
        end
        local subline
        if earned > 0 and spent > 0 then
            local function tint(color, text)
                return string.format(
                    "|cff%02x%02x%02x%s|r",
                    math.floor(color[1] * 255 + 0.5),
                    math.floor(color[2] * 255 + 0.5),
                    math.floor(color[3] * 255 + 0.5),
                    text
                )
            end
            subline = tint(WBF.UI.Colors.green, WBF.Format.Signed(earned) .. " gained")
                .. "   "
                .. tint(WBF.UI.Colors.red, WBF.Format.Signed(-spent) .. " spent")
        end
        if earned > 0 or spent > 0 then
            tooltip = tooltip .. "  Earned " .. WBF.Format.Signed(earned) .. "."
            if spent > 0 then
                tooltip = tooltip .. "  Spent " .. WBF.Format.Signed(-spent) .. "."
            end
        end
        widgets[#widgets + 1] = {
            label = resource.name or resource.short,
            value = NetText(net),
            detail = detail,
            subline = subline,
            resource = true,
            group = "currency",
            color = color,
            texture = resource.texture,
            fallback = "Interface\\Icons\\INV_Misc_Coin_01",
            tooltip = tooltip,
            open = "resource",
            resourceKey = resource.key,
            -- The Warband dashboard is an all-time aggregate, not a useful
            -- bounded chart window. Resource detail pages already include
            -- lifetime totals, so open Warband resource cards on This Week.
            period = summary.view == "warband" and "week" or summary.view,
        }
    end
    return widgets
end

local livePlay = {
    summary = nil,
    stat = nil,
    character = nil,
    base = 0,
    guid = nil,
}

local function PlayedNow(summary)
    local extra, guid = 0, nil
    if WBF.Aggregator.LivePlay then
        extra, guid = WBF.Aggregator.LivePlay(summary)
    end
    return (summary.playedSeconds or 0) + (extra or 0), extra or 0, guid
end

local function FishingTooltip(summary)
    local text = "Successful fishing loot. A missed or cancelled cast is not counted, and several items from one catch count once."
    local items = summary.fishingItems or {}
    if #items == 0 then
        return text
    end
    local parts = {}
    for index = 1, #items do
        local item = items[index]
        parts[#parts + 1] = tostring(item.qty or 0) .. " " .. (item.name or "item")
    end
    return text .. " " .. table.concat(parts, ", ") .. "."
end

local function GatherDetail(totals)
    local parts = {}
    if (totals.mining or 0) > 0 then
        parts[#parts + 1] = totals.mining .. " Mining"
    end
    if (totals.herbalism or 0) > 0 then
        parts[#parts + 1] = totals.herbalism .. " Herbs"
    end
    if (totals.lumber or 0) > 0 then
        parts[#parts + 1] = totals.lumber .. " Lumber"
    end
    if (totals.skinning or 0) > 0 then
        parts[#parts + 1] = totals.skinning .. " Skinned"
    end
    return table.concat(parts, "  ·  ")
end

local function WorldWidgets(summary)
    local totals = summary.totals or {}
    local widgets = {}
    if (totals.rares or 0) > 0 then
        widgets[#widgets + 1] = {
            label = "Rares",
            value = tostring(totals.rares),
            detail = "defeated",
            fallback = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
            tooltip = "Open-world rares defeated with credit. Ordinary mobs and dungeon or raid bosses are not included.",
        }
    end
    if (totals.fishing or 0) > 0 then
        widgets[#widgets + 1] = {
            label = "Fishing",
            value = tostring(totals.fishing),
            detail = totals.fishing == 1 and "catch" or "catches",
            fallback = "Interface\\Icons\\Trade_Fishing",
            tooltip = FishingTooltip(summary),
        }
    end
    local gathered = (totals.mining or 0) + (totals.herbalism or 0) + (totals.lumber or 0) + (totals.skinning or 0)
    if gathered > 0 then
        local kinds = 0
        if (totals.mining or 0) > 0 then
            kinds = kinds + 1
        end
        if (totals.herbalism or 0) > 0 then
            kinds = kinds + 1
        end
        if (totals.lumber or 0) > 0 then
            kinds = kinds + 1
        end
        if (totals.skinning or 0) > 0 then
            kinds = kinds + 1
        end
        local label = "Gathering"
        local detail = GatherDetail(totals)
        local fallback = "Interface\\Icons\\Trade_Mining"
        if kinds == 1 and (totals.mining or 0) > 0 then
            label = "Mining"
            detail = "nodes"
            fallback = "Interface\\Icons\\Trade_Mining"
        elseif kinds == 1 and (totals.herbalism or 0) > 0 then
            label = "Herbalism"
            detail = "nodes"
            fallback = "Interface\\Icons\\Trade_Herbalism"
        elseif kinds == 1 and (totals.lumber or 0) > 0 then
            label = "Lumber"
            detail = "nodes"
            fallback = "Interface\\Icons\\INV_Axe_01"
        elseif kinds == 1 and (totals.skinning or 0) > 0 then
            label = "Skinning"
            detail = "creatures"
            fallback = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01"
        end
        widgets[#widgets + 1] = {
            label = label,
            value = tostring(gathered),
            detail = detail,
            fallback = fallback,
            tooltip = "Nodes gathered. Several items from one node count once. Mail, vendors, and mob drops are not included.",
        }
    end
    return widgets
end

local function HeaderStats(summary, playedSeconds)
    local totals = summary.totals or {}
    local characters = summary.characters or {}
    local stats = {
        {
            label = "Played",
            value = WBF.Format.Played(playedSeconds),
            livePlay = true,
            atlases = { "auctionhouse-icon-clock" },
            fallback = "Interface\\Icons\\INV_Misc_PocketWatch_01",
            tooltip = "Time spent in tracked sessions. Long AFK gaps are left out.",
        },
    }
    if #characters > 0 then
        stats[#stats + 1] = {
            label = "Characters",
            value = tostring(#characters),
            atlases = { "groupfinder-icon-friend" },
            fallback = "Interface\\Icons\\INV_Misc_GroupNeedMore",
            tooltip = "Characters active during this period.",
        }
    end

    local optional = {}
    if totals.raids > 0 then
        optional[#optional + 1] = {
            label = "Raids",
            value = tostring(totals.raids),
            atlases = { "DungeonSkull" },
            fallback = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
            tooltip = "Raid instances entered, including legacy raids. This is not a full-clear count.",
            open = "raids",
        }
    end
    if totals.mythicPlus > 0 then
        optional[#optional + 1] = {
            label = "Mythic+",
            value = tostring(totals.mythicPlus),
            atlases = { "challengeMode-icon-chest" },
            fallback = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
            tooltip = totals.highestKey > 0 and ("Highest key +" .. totals.highestKey) or "Completed Mythic+ runs.",
            open = "mythicPlus",
        }
    end
    if totals.delves > 0 then
        optional[#optional + 1] = {
            label = "Delves",
            value = tostring(totals.delves),
            atlases = { "delves-scenario-treasure-chest" },
            fallback = "Interface\\Icons\\INV_Misc_Map_01",
            tooltip = totals.highestDelve > 0 and ("Highest tier " .. totals.highestDelve) or "Delves completed.",
            open = "delves",
        }
    end
    if totals.prey > 0 or totals.preyStarted > 0 then
        local startedOnly = totals.prey == 0
        optional[#optional + 1] = {
            label = "Prey",
            value = tostring(startedOnly and totals.preyStarted or totals.prey),
            fallback = "Interface\\Icons\\INV_Misc_MonsterClaw_02",
            tooltip = PreyTooltip(totals, startedOnly),
            open = "prey",
        }
    end
    if totals.bosses > 0 then
        optional[#optional + 1] = {
            label = "Bosses",
            value = tostring(totals.bosses),
            atlases = { "DungeonSkull" },
            fallback = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
            tooltip = "Successful boss encounters.",
            open = "bosses",
        }
    end
    local world = WorldWidgets(summary)
    for index = 1, #world do
        optional[#optional + 1] = world[index]
    end
    if totals.reputation ~= 0 then
        optional[#optional + 1] = {
            label = "Reputation",
            value = WBF.Format.Signed(totals.reputation),
            atlases = { "MajorFactions_MapIcons_Centaur_Major" },
            fallback = "Interface\\Icons\\Achievement_Reputation_01",
            tooltip = "Reputation received during this period, from the gain message at the time it happened.",
            open = "reputation",
        }
    end
    if totals.professions > 0 then
        optional[#optional + 1] = {
            label = "Professions",
            value = tostring(totals.professions),
            atlases = { "Professions-ChatIcon-Quality-Tier1" },
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
            tooltip = "Profession skill rank changes.",
            open = "professions",
        }
    end
    if totals.appearances > 0 then
        optional[#optional + 1] = {
            label = "Appearances",
            value = WBF.Format.Number(totals.appearances),
            atlases = { "transmog-icon-chat" },
            fallback = "Interface\\Icons\\INV_Chest_Cloth_17",
            tooltip = "New appearance sources added to your collection.",
            open = "appearances",
        }
    end
    if WBF.Housing and WBF.Housing.Tile then
        local housing = WBF.Housing.Tile(totals)
        if housing then
            optional[#optional + 1] = housing
        end
    end
    if totals.mounts > 0 then
        optional[#optional + 1] = {
            label = "Mounts",
            value = tostring(totals.mounts),
            fallback = "Interface\\Icons\\Ability_Mount_RidingHorse",
            tooltip = "Mounts collected.",
            open = "mounts",
        }
    end
    if totals.pets > 0 and (totals.petsCaptured or 0) == 0 then
        optional[#optional + 1] = {
            label = "Pets",
            value = tostring(totals.pets),
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
            tooltip = "Battle pets added.",
            open = "pets",
        }
    end
    if (totals.petBattles or 0) > 0 or (totals.petBattlesStarted or 0) > 0 then
        local battles = (totals.petBattles or 0) > 0 and totals.petBattles or totals.petBattlesStarted
        local detail
        if (totals.petWins or 0) + (totals.petLosses or 0) > 0 then
            detail = (totals.petWins or 0) .. "W / " .. (totals.petLosses or 0) .. "L"
        end
        optional[#optional + 1] = {
            label = "Pet Battles",
            value = tostring(battles),
            detail = detail,
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
            tooltip = "Pet battles recorded during this period.",
            open = "petBattles",
            warband = true,
        }
    end
    if (totals.concentrationUsed or 0) > 0 then
        optional[#optional + 1] = {
            label = "Concentration Used",
            value = WBF.Format.Number(totals.concentrationUsed),
            atlases = { "Professions-ChatIcon-Quality-Tier1" },
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
            tooltip = "Profession concentration spent. Passive regeneration is not included.",
            open = "professions",
        }
    end
    if (totals.knowledge or 0) > 0 then
        optional[#optional + 1] = {
            label = "Profession Knowledge",
            value = WBF.Format.Signed(totals.knowledge),
            atlases = { "Professions-ChatIcon-Quality-Tier1" },
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
            tooltip = "Profession knowledge gained during this period.",
            open = "professions",
        }
    end
    if (totals.curseSurges or 0) > 0 then
        optional[#optional + 1] = {
            label = "Curse Surges",
            value = tostring(totals.curseSurges),
            atlases = { "worldquest-tracker-questmarker", "QuestNormal" },
            fallback = "Interface\\Icons\\INV_Misc_Note_01",
            tooltip = "Curse Surges completed. These are rotating public events, separate from quests and world quests.",
            open = "curseSurges",
        }
    end
    if (totals.worldEvents or 0) > 0 then
        optional[#optional + 1] = {
            label = "World Events",
            value = tostring(totals.worldEvents),
            atlases = { "worldquest-tracker-questmarker", "QuestNormal" },
            fallback = "Interface\\Icons\\INV_Misc_Note_01",
            tooltip = "Public world events completed.",
            open = "worldEvents",
        }
    end
    local quests = totals.quests + totals.worldQuests
    if quests > 0 then
        local open = "questsAll"
        if totals.worldQuests == 0 then
            open = "quests"
        elseif totals.quests == 0 then
            open = "worldQuests"
        end
        optional[#optional + 1] = {
            label = "Quests",
            value = tostring(quests),
            atlases = { "QuestNormal" },
            fallback = "Interface\\Icons\\INV_Misc_Note_01",
            tooltip = "Quests and world quests completed.",
            open = open,
        }
    end
    if totals.achievements > 0 then
        optional[#optional + 1] = {
            label = "Achievements",
            value = tostring(totals.achievements),
            fallback = "Interface\\Icons\\Achievement_General",
            tooltip = "Achievements earned for the first time.",
            open = "achievements",
        }
    end
    local resources = ResourceWidgets(summary)
    for index = #resources, 1, -1 do
        if index <= 2 then
            table.insert(optional, 1, resources[index])
        end
    end

    local room = 5
    for index = 1, math.min(room, #optional) do
        stats[#stats + 1] = optional[index]
    end

    stats[#stats + 1] = {
        label = "Net",
        value = WBF.Format.Gold(summary.goldNet, true, "compact"),
        color = GoldColor(summary.goldNet),
        fallback = "Interface\\MoneyFrame\\UI-GoldIcon",
        tooltip = "Gold gained or spent during this period, added across characters. A character's existing balance is not counted when you first see them."
            .. ((summary.goldOffline or 0) ~= 0 and " Includes gold that changed between sessions." or ""),
        open = summary.goldTracked and "gold" or nil,
    }
    return stats
end

local function TilesFor(summary)
    local totals = summary.totals or {}
    local tiles = {}
    local function add(tile)
        tile.group = tile.group or "activity"
        tiles[#tiles + 1] = tile
    end
    if totals.raids > 0 then
        add({
            label = "Raids",
            value = tostring(totals.raids),
            atlases = { "DungeonSkull" },
            fallback = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
            tooltip = "Raid instances entered, including legacy raids.",
            open = "raids",
        })
    end
    if totals.bosses > 0 then
        add({
            label = "Bosses",
            value = tostring(totals.bosses),
            atlases = { "DungeonSkull" },
            fallback = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
            tooltip = "Successful boss encounters.",
            open = "bosses",
        })
    end
    local world = WorldWidgets(summary)
    for index = 1, #world do
        add(world[index])
    end
    if totals.dungeons > 0 then
        add({
            label = "Dungeons",
            value = tostring(totals.dungeons),
            atlases = { "QuestNormal" },
            fallback = "Interface\\Icons\\INV_Misc_Key_10",
            tooltip = "Dungeon instances entered, other than Mythic+.",
            open = "dungeons",
        })
    end
    if totals.mythicPlus > 0 then
        add({
            label = "Mythic+",
            value = tostring(totals.mythicPlus),
            atlases = { "challengeMode-icon-chest" },
            fallback = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
            tooltip = totals.highestKey > 0 and ("Highest +" .. totals.highestKey) or "Completed runs.",
            open = "mythicPlus",
        })
    end
    if totals.delves > 0 then
        add({
            label = "Delves",
            value = tostring(totals.delves),
            atlases = { "delves-scenario-treasure-chest" },
            fallback = "Interface\\Icons\\INV_Misc_Map_01",
            tooltip = totals.highestDelve > 0 and ("Highest tier " .. totals.highestDelve) or "Delves completed.",
            open = "delves",
        })
    end
    if totals.prey > 0 or totals.preyStarted > 0 then
        local startedOnly = totals.prey == 0
        add({
            label = "Prey",
            value = tostring(startedOnly and totals.preyStarted or totals.prey),
            fallback = "Interface\\Icons\\INV_Misc_MonsterClaw_02",
            tooltip = PreyTooltip(totals, startedOnly),
            open = "prey",
        })
    end
    if totals.worldQuests > 0 then
        add({
            label = "World Quests",
            value = tostring(totals.worldQuests),
            atlases = { "worldquest-tracker-questmarker", "QuestNormal" },
            fallback = "Interface\\Icons\\INV_Misc_Note_01",
            tooltip = "World quests turned in.",
            open = "worldQuests",
        })
    end
    if (totals.curseSurges or 0) > 0 then
        add({
            label = "Curse Surges",
            value = tostring(totals.curseSurges),
            atlases = { "worldquest-tracker-questmarker", "QuestNormal" },
            fallback = "Interface\\Icons\\INV_Misc_Note_01",
            tooltip = "Curse Surges completed. These are rotating public events, separate from quests and world quests.",
            open = "curseSurges",
        })
    end
    if (totals.worldEvents or 0) > 0 then
        add({
            label = "World Events",
            value = tostring(totals.worldEvents),
            atlases = { "worldquest-tracker-questmarker", "QuestNormal" },
            fallback = "Interface\\Icons\\INV_Misc_Note_01",
            tooltip = "Public world events completed.",
            open = "worldEvents",
        })
    end
    if totals.quests > 0 then
        add({
            label = "Quests",
            value = tostring(totals.quests),
            atlases = { "QuestNormal" },
            fallback = "Interface\\Icons\\INV_Misc_Note_01",
            tooltip = "Quests turned in, other than world quests and Curse Surges.",
            open = "quests",
        })
    end
    if totals.achievements > 0 then
        add({
            label = "Achievements",
            value = tostring(totals.achievements),
            fallback = "Interface\\Icons\\Achievement_General",
            tooltip = "Achievements earned.",
            open = "achievements",
        })
    end
    if totals.reputation ~= 0 then
        add({
            label = "Reputation",
            value = WBF.Format.Signed(totals.reputation),
            atlases = { "MajorFactions_MapIcons_Centaur_Major" },
            fallback = "Interface\\Icons\\Achievement_Reputation_01",
            tooltip = "Reputation received during this period.",
            open = "reputation",
        })
    end
    if totals.renown > 0 then
        add({
            label = "Renown",
            value = tostring(totals.renown),
            atlases = { "MajorFactions_MapIcons_Centaur_Major" },
            fallback = "Interface\\Icons\\Achievement_Reputation_01",
            tooltip = "Renown levels gained.",
            open = "renown",
        })
    end
    if (totals.concentrationUsed or 0) > 0 then
        add({
            label = "Concentration Used",
            value = WBF.Format.Number(totals.concentrationUsed),
            atlases = { "Professions-ChatIcon-Quality-Tier1" },
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
            tooltip = "Profession concentration spent. Passive regeneration is not included.",
            open = "professions",
            group = "profession",
        })
    end
    if (totals.knowledge or 0) > 0 then
        add({
            label = "Profession Knowledge",
            value = WBF.Format.Signed(totals.knowledge),
            atlases = { "Professions-ChatIcon-Quality-Tier1" },
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
            tooltip = "Profession knowledge gained during this period.",
            open = "professions",
            group = "profession",
        })
    end
    if (totals.recipes or 0) > 0 then
        add({
            label = "Recipes Learned",
            value = tostring(totals.recipes),
            atlases = { "Professions-ChatIcon-Quality-Tier1" },
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
            tooltip = "New recipes learned during this period.",
            open = "professions",
            group = "profession",
        })
    end
    if totals.professions > 0 then
        add({
            label = "Skill Ups",
            value = tostring(totals.professions),
            atlases = { "Professions-ChatIcon-Quality-Tier1" },
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
            tooltip = "Profession skill rank changes.",
            open = "professions",
            group = "profession",
        })
    end
    if totals.mounts > 0 then
        add({
            label = "Mounts",
            value = tostring(totals.mounts),
            fallback = "Interface\\Icons\\Ability_Mount_RidingHorse",
            tooltip = "Mounts collected.",
            open = "mounts",
            group = "collection",
        })
    end
    if totals.pets > 0 and (totals.petsCaptured or 0) == 0 then
        add({
            label = "Pets",
            value = tostring(totals.pets),
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
            tooltip = "Battle pets added.",
            open = "pets",
            group = "collection",
        })
    end
    if (totals.petBattles or 0) > 0 or (totals.petBattlesStarted or 0) > 0 then
        local battles = (totals.petBattles or 0) > 0 and totals.petBattles or totals.petBattlesStarted
        local detail
        if (totals.petWins or 0) + (totals.petLosses or 0) > 0 then
            detail = (totals.petWins or 0) .. "W / " .. (totals.petLosses or 0) .. "L"
        end
        add({
            label = "Pet Battles",
            value = tostring(battles),
            detail = detail,
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
            tooltip = "Pet battles recorded during this period.",
            open = "petBattles",
            warband = true,
            group = "collection",
        })
    end
    if (totals.petLevels or 0) > 0 then
        local detail
        if (totals.petsLevel25 or 0) > 0 then
            detail = totals.petsLevel25 .. " reached level 25"
        end
        add({
            label = "Pet Levels",
            value = WBF.Format.Signed(totals.petLevels),
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
            tooltip = "Levels gained by battle pets during this period.",
            detail = detail,
            open = "petBattles",
            warband = true,
            group = "collection",
        })
    end
    if (totals.petsCaptured or 0) > 0 then
        local detail
        if (totals.newPets or 0) > 0 then
            detail = totals.newPets .. " new"
        end
        add({
            label = "Pets Captured",
            value = tostring(totals.petsCaptured),
            detail = detail,
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
            tooltip = "Battle pets captured during this period.",
            open = "petBattles",
            warband = true,
            group = "collection",
        })
    end
    if totals.appearances > 0 then
        add({
            label = "Appearances",
            value = WBF.Format.Number(totals.appearances),
            atlases = { "transmog-icon-chat" },
            fallback = "Interface\\Icons\\INV_Chest_Cloth_17",
            tooltip = "New appearance sources.",
            open = "appearances",
            group = "collection",
        })
    end
    if WBF.Housing and WBF.Housing.Tile then
        local housing = WBF.Housing.Tile(totals)
        if housing then
            add(housing)
        end
    end
    if summary.goldNet ~= 0 then
        add({
            label = "Net Gold",
            value = WBF.Format.Gold(summary.goldNet, true, "compact"),
            color = GoldColor(summary.goldNet),
            fallback = "Interface\\MoneyFrame\\UI-GoldIcon",
            tooltip = "Gold gained or spent during this period, added across characters.",
            open = "gold",
        })
    end
    local resources = ResourceWidgets(summary)
    for index = 1, #resources do
        add(resources[index])
    end
    return tiles
end

function WBF.UI.Dashboard.TickLivePlay()
    local summary = livePlay.summary
    if not summary or not summary.liveSegment then
        return
    end
    local playedNow, extra, guid = PlayedNow(summary)
    if livePlay.stat then
        livePlay.stat:SetText(WBF.Format.Played(playedNow))
    end
    if livePlay.character and guid and guid == livePlay.guid then
        livePlay.character:SetText(WBF.Format.Played((livePlay.base or 0) + (extra or 0)))
    end
end

function WBF.UI.Dashboard.Attach(parent)
    root = parent
end

local function DrawCharacterFYIs(parent, y, width)
    if not WBF.NotebookFyi or not WBF.NotebookFyi.List then return y end
    local items = {}
    for _, info in ipairs(WBF.NotebookFyi.List()) do
        if info.characterGuid and info.enabled then items[#items + 1] = info end
    end
    if #items == 0 then return y end
    WBF.UI.AcquireSection(parent, "Character FYIs (" .. #items .. ")", 0, y, width)
    y = y + 25
    -- All assigned reminders are listed across the Warband; the pop-up remains character-filtered.
    for index, info in ipairs(items) do
        local row = WBF.UI.Acquire(WBF.UI.Pool("dashboardCharacterFYI", function(owner)
            local button = CreateFrame("Button", nil, owner)
            button:SetHeight(23)
            button:RegisterForClicks("LeftButtonUp")
            local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", 6, 0)
            label:SetPoint("RIGHT", -6, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            button.Label = label
            local highlight = button:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.06)
            return button
        end), parent)
        row:SetWidth(width)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        row.Label:SetText((info.characterName or "Character") .. "  -  " .. (info.title or "FYI"))
        row:SetScript("OnClick", function()
            if WBF.UI.Fyi and WBF.UI.Fyi.OpenSetup then
                WBF.UI.Fyi.OpenSetup(info.targetKind, info.targetId)
            end
        end)
        y = y + 24
    end
    return y + 10
end

local function DrawCollectionHunts(parent, y, width)
    if not WBF.CollectionHunts then return y end
    local active = WBF.CollectionHunts.Active()
    WBF.UI.AcquireSection(parent, "Collection Hunts", 0, y, width)
    local manage = WBF.UI.Acquire(WBF.UI.Pool("dashboardHuntsManage", function(owner)
        local button = CreateFrame("Button", nil, owner, "UIPanelButtonTemplate")
        button:SetSize(135, 22)
        button:SetText("Manage Hunts")
        button:SetScript("OnClick", function() WBF.UI.CollectionHunts.Open() end)
        return button
    end), parent)
    manage:SetPoint("TOPRIGHT", parent, "TOPLEFT", width, -y)
    if #active == 0 then
        y = y + 28
        local empty = WBF.UI.Acquire(WBF.UI.Pool("dashboardHuntsEmpty", function(owner)
            local f = CreateFrame("Frame", nil, owner)
            f.Label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            f.Label:SetAllPoints()
            f.Label:SetJustifyH("LEFT")
            f.Label:SetText("No active hunts. Select Manage Hunts to begin.")
            return f
        end), parent)
        empty:SetSize(width, 22)
        empty:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -y)
        return y + 30
    end
    y = y + 25
    local characters = WBF.Characters.List and WBF.Characters.List() or {}
    for _, hunt in ipairs(active) do
        local available, done, unknown, excluded = 0, 0, 0, 0
        local current = WBF.Characters.GetGuid()
        for _, character in ipairs(characters) do
            if character.guid then
                local status = WBF.CollectionHunts.Status(hunt.key, character.guid)
                if status == "available" then available = available + 1
                elseif status == "done" then done = done + 1
                elseif status == "excluded" or status == "ineligible" then excluded = excluded + 1
                else unknown = unknown + 1 end
            end
        end
        local row = WBF.UI.Acquire(WBF.UI.Pool("dashboardCollectionHunt", function(owner)
            local frame = CreateFrame("Frame", nil, owner)
            frame:SetHeight(24)
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", 6, 0)
            label:SetPoint("RIGHT", -6, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            frame.Label = label
            return frame
        end), parent)
        row:SetWidth(width)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
        local thisStatus = current and WBF.CollectionHunts.Status(hunt.key, current) or "unknown"
        local ownLabels = {available="|cff77e39bReady on this character|r", done="|cffffcf67Attempted this week|r", collected="|cff77e39bCollected|r", unknown="Not yet verified", excluded="Not selected", ineligible="Not eligible"}
        local own = ownLabels[thisStatus] or "Unknown"
        local summary = thisStatus == "collected" and "|cff77e39bGoal achieved|r" or
            ("|cff77e39b" .. available .. " available|r   •   " .. done .. " attempted")
        row.Label:SetText(hunt.info.title .. "   |   " .. own .. "   •   " .. summary)
        y = y + 24
    end
    local note = WBF.UI.Acquire(WBF.UI.Pool("dashboardCollectionHuntNote", function(owner)
        local frame = CreateFrame("Frame", nil, owner)
        frame:SetHeight(20)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("LEFT", 6, 0)
        label:SetPoint("RIGHT", -6, 0)
        label:SetJustifyH("LEFT")
        frame.Label = label
        return frame
    end), parent)
    note:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    note:SetWidth(width)
    note.Label:SetText("Choose Manage Hunts for details, unverified attempts and character settings.")
    return y + 30
end

function WBF.UI.Dashboard.Render(summary, width)
    EnsureChrome()
    HideChrome()
    WBF.UI.ReleaseAll()

    local y = 4
    local monthNav = summary.view == "month" and summary.monthKey ~= nil
    local titleLeft = 0
    titleText:ClearAllPoints()
    if monthNav and prevMonth and nextMonth then
        prevMonth:ClearAllPoints()
        prevMonth:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        prevMonth:Show()
        StyleArrow(prevMonth, summary.canGoBack)
        nextMonth:ClearAllPoints()
        nextMonth:SetPoint("TOPRIGHT", root, "TOPLEFT", width, -y)
        nextMonth:Show()
        StyleArrow(nextMonth, summary.canGoForward)
        titleLeft = 26
        titleText:SetPoint("TOPLEFT", root, "TOPLEFT", titleLeft, -y)
        titleText:SetPoint("RIGHT", nextMonth, "LEFT", -6, 0)
    else
        titleText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
    end
    titleText:SetText(summary.label or "WarbandFYI")
    titleText:Show()
    y = y + 22

    rangeText:ClearAllPoints()
    rangeText:SetPoint("TOPLEFT", root, "TOPLEFT", titleLeft, -y)
    rangeText:SetText(RangeLine(summary))
    rangeText:Show()
    y = y + 18

    if summary.includesSample then
        sampleText:ClearAllPoints()
        sampleText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        sampleText:SetWidth(width)
        sampleText:Show()
        y = y + 18
    end

    livePlay.summary = nil
    livePlay.stat = nil
    livePlay.character = nil
    livePlay.base = 0
    livePlay.guid = nil

    if summary.empty then
        if WBF.UI.Notebook and WBF.UI.Notebook.DrawSummary then
            y = WBF.UI.Notebook.DrawSummary(root, y, width)
        end
        if WBF.UI.ContextFyi and WBF.UI.ContextFyi.DrawReminder then
            y = WBF.UI.ContextFyi.DrawReminder(root, y, width)
        end
        y = DrawCharacterFYIs(root, y, width)
        y = DrawCollectionHunts(root, y, width)
        noteText:ClearAllPoints()
        noteText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(y + 12))
        noteText:SetWidth(math.min(460, width))
        noteText:SetText(summary.emptyReason or "Nothing recorded for this period yet.")
        noteText:Show()
        return y + 80
    end

    local playedNow, _, liveGuid = PlayedNow(summary)
    livePlay.summary = summary
    livePlay.guid = liveGuid
    local stats = HeaderStats(summary, playedNow)
    local gap = 8
    while #stats > 2 do
        local statWidth = math.min(150, math.floor((width - gap * (#stats - 1)) / #stats))
        if statWidth >= 108 and (statWidth * #stats + gap * (#stats - 1)) <= width + 1 then
            break
        end
        table.remove(stats, #stats - 1)
    end
    local statWidth = math.min(150, math.floor((width - gap * (#stats - 1)) / #stats))
    local statHeight = 64
    for index = 1, #stats do
        if stats[index].detail then
            statHeight = 78
            break
        end
    end
    for index = 1, #stats do
        local card = WBF.UI.AcquireStat(root)
        card:SetSize(statWidth, statHeight)
        card:SetPoint("TOPLEFT", root, "TOPLEFT", (index - 1) * (statWidth + gap), -y)
        card:Apply(stats[index])
        if stats[index].livePlay then
            livePlay.stat = card.Value
        end
    end
    y = y + statHeight + 16

    if WBF.UI.Notebook and WBF.UI.Notebook.DrawSummary then
        y = WBF.UI.Notebook.DrawSummary(root, y, width)
    end
    if WBF.UI.ContextFyi and WBF.UI.ContextFyi.DrawReminder then
        y = WBF.UI.ContextFyi.DrawReminder(root, y, width)
    end
    y = DrawCharacterFYIs(root, y, width)
    y = DrawCollectionHunts(root, y, width)

    if #summary.highlights > 0 then
        WBF.UI.AcquireSection(root, "Highlights", 0, y, width)
        y = y + 26
        local columns = 3
        local cardGap = 8
        local cardWidth = math.floor((width - cardGap * (columns - 1)) / columns)
        for index = 1, #summary.highlights do
            local card = WBF.UI.AcquireHighlight(root)
            local column = index - 1
            card:SetSize(cardWidth, 86)
            card:SetPoint("TOPLEFT", root, "TOPLEFT", column * (cardWidth + cardGap), -y)
            card:Apply(summary.highlights[index])
        end
        y = y + 86 + 16
    end

    if #summary.characters > 0 then
        WBF.UI.AcquireSection(root, "Character Progress", 0, y, width)
        y = y + 26
        local columns = 2
        local cardGap = 8
        local cardWidth = math.floor((width - cardGap) / columns)
        local cardHeight = 128
        for index = 1, #summary.characters do
            local card = WBF.UI.AcquireCharacter(root)
            local column = (index - 1) % columns
            local gridRow = math.floor((index - 1) / columns)
            card:SetSize(cardWidth, cardHeight)
            card:SetPoint("TOPLEFT", root, "TOPLEFT", column * (cardWidth + cardGap), -(y + gridRow * (cardHeight + cardGap)))
            local person = summary.characters[index]
            local shown = person.playedSeconds or 0
            if liveGuid and person.guid == liveGuid then
                shown = shown + (playedNow - (summary.playedSeconds or 0))
                livePlay.base = person.playedSeconds or 0
            end
            card:Apply(person, shown)
            if liveGuid and person.guid == liveGuid then
                livePlay.character = card.Played
            end
        end
        local rows = math.ceil(#summary.characters / columns)
        y = y + rows * cardHeight + (rows - 1) * cardGap + 16
    end

    local tiles = TilesFor(summary)
    local activity = summary.activity
    local showTiles = #tiles > 0
    local shownActivity = math.min(6, #activity)
    local showActivity = shownActivity > 0

    if not summary.hasActivity then
        noteText:ClearAllPoints()
        noteText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -y)
        noteText:SetWidth(math.min(520, width))
        noteText:SetText("Nothing recorded for this period yet. Play a session, then check Current Session. /wbfyi sample previews the dashboard.")
        noteText:Show()
        y = y + 48
    end

    if showTiles or showActivity then
        local gap = 16
        local leftWidth = width
        local rightWidth = width
        local split = showTiles and showActivity
        if split then
            leftWidth = math.floor(width * 0.56)
            rightWidth = width - leftWidth - gap
        end

        local leftHeight = 0
        local rightHeight = 0

        if showTiles then
            local tileGap = 8
            local groups = {
                { id = "currency", title = "Currencies" },
                { id = "activity", title = "Activities" },
                { id = "collection", title = "Collections" },
                { id = "profession", title = "Professions" },
            }
            local grouped = {}
            local groupCount = 0
            for index = 1, #tiles do
                local tile = tiles[index]
                local id = tile.group or (tile.resource and "currency" or "activity")
                if not grouped[id] then
                    grouped[id] = {}
                    groupCount = groupCount + 1
                end
                local list = grouped[id]
                list[#list + 1] = tile
            end
            local cursor = y + 4
            if groupCount <= 1 then
                WBF.UI.AcquireSection(root, (summary.label or "Period") .. " Summary", 0, cursor, leftWidth)
                cursor = cursor + 26
            end
            local function tileHeightFor(list)
                local height = 58
                for index = 1, #list do
                    if list[index].resource and list[index].subline then
                        return 92
                    end
                    if list[index].resource or (list[index].detail and list[index].detail ~= "") then
                        height = 74
                    end
                end
                return height
            end
            local function placeTiles(list, top, minWidth, maxColumns, tileHeight)
                if #list == 0 then
                    return top
                end
                local columns = maxColumns
                local tileWidth = leftWidth
                while columns > 1 do
                    tileWidth = math.floor((leftWidth - tileGap * (columns - 1)) / columns)
                    if tileWidth >= minWidth then
                        break
                    end
                    columns = columns - 1
                end
                if columns == 1 then
                    tileWidth = leftWidth
                end
                for index = 1, #list do
                    local tile = WBF.UI.AcquireTile(root)
                    local column = (index - 1) % columns
                    local row = math.floor((index - 1) / columns)
                    tile:SetSize(tileWidth, tileHeight)
                    tile:SetPoint("TOPLEFT", root, "TOPLEFT", column * (tileWidth + tileGap), -(top + row * (tileHeight + tileGap)))
                    tile:Apply(list[index])
                end
                local rows = math.ceil(#list / columns)
                return top + rows * tileHeight + (rows - 1) * tileGap
            end
            for index = 1, #groups do
                local group = groups[index]
                local list = grouped[group.id]
                if list and #list > 0 then
                    if groupCount > 1 then
                        WBF.UI.AcquireSection(root, group.title, 0, cursor, leftWidth)
                        cursor = cursor + 26
                    end
                    local minWidth = group.id == "currency" and 156 or 120
                    local columns = leftWidth >= 440 and 4 or 2
                    cursor = placeTiles(list, cursor, minWidth, columns, tileHeightFor(list))
                    cursor = cursor + 8
                end
            end
            leftHeight = cursor - y
        end

        if showActivity then
            local activityX = split and (leftWidth + gap) or 0
            WBF.UI.AcquireSection(root, "Recent Activity", activityX, y, rightWidth)
            for index = 1, shownActivity do
                local row = WBF.UI.AcquireActivity(root)
                row:SetWidth(rightWidth)
                row:SetPoint("TOPLEFT", root, "TOPLEFT", activityX, -(y + 26 + (index - 1) * 24))
                row:Apply(activity[index])
            end
            rightHeight = 26 + shownActivity * 24
            if #activity > shownActivity and not summary.fromRollup then
                viewAll:ClearAllPoints()
                viewAll:SetPoint("TOPLEFT", root, "TOPLEFT", activityX, -(y + rightHeight + 4))
                viewAll:Show()
                rightHeight = rightHeight + 22
            end
        end

        y = y + math.max(leftHeight, rightHeight) + 8
    end

    return y + 8
end
