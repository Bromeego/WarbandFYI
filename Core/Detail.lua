local _, WBF = ...

-- Detail pages explain a dashboard total from the same period and character
-- filter the aggregator already used. Rows are built from stored events.
-- Missing fields are left out rather than filled in.

WBF.Detail = {}

local TITLES = {
    appearances = "Appearances",
    raids = "Raids",
    raidRun = "Raid Run",
    bosses = "Bosses",
    bossHistory = "Boss",
    dungeons = "Dungeons",
    dungeonHistory = "Dungeon",
    mythicPlus = "Mythic+",
    mythicHistory = "Mythic+",
    delves = "Delves",
    delveHistory = "Delve",
    quests = "Quests",
    worldQuests = "World Quests",
    curseSurges = "Curse Surges",
    worldEvents = "World Events",
    questsAll = "Quests",
    achievements = "Achievements",
    mounts = "Mounts",
    housing = "Housing",
    pets = "Pets",
    reputation = "Reputation",
    reputationFaction = "Reputation",
    renown = "Renown",
    renownFaction = "Renown",
    gold = "Gold",
    prey = "Prey",
    character = "Character",
    itemLevel = "Item Level",
    professions = "Professions",
    professionHistory = "Profession",
    petBattles = "Pet Battles",
    resource = "Resource",
}

local PREY_DIFFICULTY = {
    Normal = true,
    Hard = true,
    Nightmare = true,
}

local function Push(lines, line)
    if line and line.text and line.text ~= "" then
        lines[#lines + 1] = line
    end
end

local function Muted(text)
    if not text or text == "" then
        return nil
    end
    return { text = text, color = "muted" }
end

local function FindCharacter(summary, guid)
    if not guid then
        return nil
    end
    for index = 1, #summary.characters do
        local character = summary.characters[index]
        if character.guid == guid then
            return character
        end
    end
    return nil
end

local function CharacterName(guid)
    local character = guid and WBF.Characters.Get(guid)
    if not WBF.Characters.IsDiscovered(character) or not character.name or character.name == "" then
        return nil
    end
    local r, g, b = WBF.Format.ClassColor(character.classFile)
    return { text = character.name, r = r, g = g, b = b }
end

local function Subtitle(summary, context, includeCharacter)
    local text = summary.label or ""
    if includeCharacter and context.characterGUID then
        local character = FindCharacter(summary, context.characterGUID) or WBF.Characters.Get(context.characterGUID)
        if WBF.Characters.IsDiscovered(character) and character.name and character.name ~= "" then
            text = text .. "    ·    " .. character.name
        end
    end
    return text
end

local function ContextEvents(summary, context)
    if not context.characterGUID then
        return summary.activity
    end
    local list = {}
    for index = 1, #summary.activity do
        local event = summary.activity[index]
        if event.guid == context.characterGUID then
            list[#list + 1] = event
        end
    end
    return list
end

local function KindOf(event)
    if WBF.Quests and WBF.Quests.EffectiveType then
        return WBF.Quests.EffectiveType(event)
    end
    return event.eventType
end

local function Select(events, kind)
    local list = {}
    for index = 1, #events do
        local event = events[index]
        if KindOf(event) == kind and not (kind == WBF.EventType.Quest and event.meta and event.meta.preyHunt) then
            list[#list + 1] = event
        end
    end
    return list
end

local function SelectCurseSurges(events)
    local list = {}
    local world = Select(events, WBF.EventType.WorldEvent)
    for index = 1, #world do
        local event = world[index]
        if WBF.Quests and WBF.Quests.IsCurseSurgeEvent and WBF.Quests.IsCurseSurgeEvent(event) then
            list[#list + 1] = event
        end
    end
    return list
end

local function SelectWorldEvents(events)
    local list = {}
    local world = Select(events, WBF.EventType.WorldEvent)
    for index = 1, #world do
        local event = world[index]
        if not (WBF.Quests and WBF.Quests.IsCurseSurgeEvent and WBF.Quests.IsCurseSurgeEvent(event)) then
            list[#list + 1] = event
        end
    end
    return list
end

local function Chrono(events)
    local copy = {}
    for index = 1, #events do
        copy[index] = events[index]
    end
    table.sort(copy, function(a, b)
        if a.at == b.at then
            return (a.id or 0) < (b.id or 0)
        end
        return (a.at or 0) < (b.at or 0)
    end)
    return copy
end

local function Stamp(prefix, at)
    if not at then
        return nil
    end
    local delta = WBF.Time.Now() - at
    local when = delta < 86400 and WBF.Time.Clock(at) or date("%A", at)
    return { text = prefix .. " " .. when, color = "muted" }
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

local function Base(summary, context, title, includeCharacter)
    return {
        title = title,
        subtitle = Subtitle(summary, context, includeCharacter),
        summary = nil,
        note = nil,
        empty = nil,
        sections = {},
    }
end

local function CountRows(sections)
    local count = 0
    for index = 1, #sections do
        count = count + #(sections[index].rows or {})
    end
    return count
end

local function Finish(model, emptyText)
    if CountRows(model.sections) == 0 then
        model.empty = model.empty or emptyText or "Nothing recorded for this period."
        model.summary = nil
        model.note = nil
    end
    return model
end

local function AppearanceName(event)
    local meta = event.meta or {}
    if meta.name and meta.name ~= "" then
        return meta.name
    end
    local text = event.text or ""
    text = text:gsub("^New appearance: ", "")
    if text == "" then
        return "Appearance"
    end
    return text
end

local function AppearanceRow(event)
    local meta = event.meta or {}
    local lines = {}
    Push(lines, Muted(meta.instanceName or meta.location))
    Push(lines, CharacterName(event.guid))
    Push(lines, Muted(WBF.Format.Ago(event.at)))
    local ids = {}
    if meta.itemID then
        ids[#ids + 1] = "Item " .. meta.itemID
    end
    if meta.sourceID then
        ids[#ids + 1] = "Appearance " .. meta.sourceID
    end
    if #ids > 0 then
        Push(lines, Muted(table.concat(ids, "    ·    ")))
    end
    local row = {
        title = AppearanceName(event),
        lines = lines,
        event = event,
    }
    if meta.quality ~= nil then
        local r, g, b = WBF.Format.QualityColor(meta.quality)
        row.titleColor = { r, g, b }
    end
    return row
end

local function BossName(event)
    local meta = event.meta or {}
    if meta.encounterName and meta.encounterName ~= "" then
        return meta.encounterName
    end
    local text = event.text or "Boss"
    return (text:gsub(" defeated$", ""))
end

local function BossRow(event)
    local meta = event.meta or {}
    local lines = {}
    Push(lines, Muted(meta.instanceName))
    Push(lines, Muted(meta.difficultyName))
    Push(lines, CharacterName(event.guid))
    Push(lines, Muted(WBF.Format.Ago(event.at)))
    return {
        title = BossName(event),
        lines = lines,
        event = event,
    }
end

local function QuestName(event)
    local meta = event.meta or {}
    if meta.title and meta.title ~= "" then
        return meta.title
    end
    local text = event.text or "Quest"
    text = text:gsub("^World Quest completed: ", "")
    text = text:gsub("^Curse Surge completed: ", "")
    text = text:gsub("^World Event completed: ", "")
    text = text:gsub("^Quest completed: ", "")
    if text == "Curse Surge completed" or text == "World Event completed" then
        return text:gsub(" completed$", "")
    end
    return text
end

local function QuestRow(event)
    local meta = event.meta or {}
    local lines = {}
    if meta.questType and meta.questType ~= "" then
        Push(lines, Muted(meta.questType))
    end
    Push(lines, Muted(meta.zone))
    Push(lines, CharacterName(event.guid))
    Push(lines, Stamp("Completed", event.at))
    return {
        title = QuestName(event),
        lines = lines,
        event = event,
    }
end

local function AchievementRow(event)
    local lines = {}
    local points = event.meta and event.meta.points
    if points and points > 0 then
        Push(lines, Muted(points .. " points"))
    end
    Push(lines, CharacterName(event.guid))
    Push(lines, Stamp("Earned", event.at))
    return {
        title = event.text or "Achievement",
        lines = lines,
        event = event,
    }
end

local function MountRow(event)
    local lines = {}
    Push(lines, CharacterName(event.guid))
    Push(lines, Stamp("Collected", event.at))
    return {
        title = event.text or "Mount",
        lines = lines,
        event = event,
        collectionKind = "mount",
    }
end

local function PetRow(event)
    local meta = event.meta or {}
    local title = event.text or "Battle pet"
    if meta.captured then
        title = title:gsub(" captured$", "")
    end
    local lines = {}
    if meta.captured then
        Push(lines, Muted("Captured"))
    end
    Push(lines, CharacterName(event.guid))
    Push(lines, Stamp("Collected", event.at))
    return {
        title = title,
        lines = lines,
        event = event,
        collectionKind = "pet",
    }
end

local function MythicName(event)
    local meta = event.meta or {}
    local name = meta.name
    if not name or name == "" then
        name = (event.text or ""):match("^(.-) %+%d+") or event.text or "Mythic+"
    end
    return name
end

local function MythicTitle(event)
    local meta = event.meta or {}
    local name = MythicName(event)
    local level = meta.level or event.new
    if level and level > 0 then
        return name .. " +" .. level
    end
    return name
end

local function MythicRow(event)
    local meta = event.meta or {}
    local lines = {}
    if meta.practiceRun then
        Push(lines, Muted("Practice"))
    elseif meta.onTime == true then
        Push(lines, { text = "Timed", color = "green" })
    elseif meta.onTime == false then
        Push(lines, Muted("Untimed"))
    end
    if meta.durationSeconds then
        Push(lines, Muted(WBF.Format.Duration(meta.durationSeconds)))
    end
    Push(lines, CharacterName(event.guid))
    Push(lines, Stamp("Completed", event.at))
    return {
        title = MythicTitle(event),
        lines = lines,
        event = event,
    }
end

local function DelveName(event)
    local meta = event.meta or {}
    local title = meta.name
    if not title or title == "" then
        title = (event.text or "Delve"):gsub("^Delve completed: ", "")
    end
    return title
end

local function DelveRow(event)
    local meta = event.meta or {}
    local lines = {}
    if meta.tier then
        Push(lines, Muted("Tier " .. meta.tier))
    end
    Push(lines, CharacterName(event.guid))
    Push(lines, Stamp("Completed", event.at))
    return {
        title = DelveName(event),
        lines = lines,
        event = event,
    }
end

local function ProfessionName(event)
    local meta = event.meta or {}
    if meta.profession and meta.profession ~= "" then
        return meta.profession
    end
    local text = WBF.Format.DisplayText(event.text or "Profession")
    return text:match("^(.-)%s+%d+%s*[-=]>%s*%d+") or text:match("^Learned%s+(.+)$") or text
end

local function ProfessionRow(event)
    local lines = {}
    Push(lines, CharacterName(event.guid))
    Push(lines, Muted(WBF.Format.Ago(event.at)))
    return {
        title = WBF.Format.DisplayText(event.text or "Profession"),
        lines = lines,
        event = event,
    }
end

local function PreyRow(event)
    local meta = event.meta or {}
    local lines = {}
    if PREY_DIFFICULTY[meta.difficulty] then
        local color = meta.difficulty == "Nightmare" and "gold" or "cream"
        Push(lines, { text = meta.difficulty, color = color })
    end
    Push(lines, CharacterName(event.guid))
    if meta.completed then
        Push(lines, Stamp("Completed", event.at))
    else
        Push(lines, Muted("In progress"))
    end
    if meta.journey and meta.journey > 0 then
        local label = meta.journeyName or "Journey"
        Push(lines, { text = label .. "  " .. WBF.Format.Signed(meta.journey), color = "green" })
    end
    return {
        title = meta.title or event.text or "Prey hunt",
        lines = lines,
        event = event,
    }
end

local function RowsOf(events, builder)
    local rows = {}
    for index = 1, #events do
        rows[index] = builder(events[index])
    end
    return rows
end

local function SimpleList(summary, context, events, category, title, emptyText, summaryText, builder)
    local model = Base(summary, context, title, true)
    local rows = RowsOf(events, builder)
    model.summary = summaryText
    model.sections[1] = { rows = rows }
    return Finish(model, emptyText)
end

local function SplitRaids(events)
    local raids = {}
    local open = {}
    local ordered = Chrono(events)
    for index = 1, #ordered do
        local event = ordered[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.InstanceEnter then
            if meta.instanceType == "raid" then
                local raid = { event = event, bosses = {} }
                raids[#raids + 1] = raid
                if event.guid then
                    open[event.guid] = raid
                end
            elseif event.guid then
                open[event.guid] = nil
            end
        elseif event.eventType == WBF.EventType.BossKill and event.guid and open[event.guid] then
            local raid = open[event.guid]
            local raidName = raid.event.meta and raid.event.meta.instanceName
            local sameName = meta.instanceName and raidName and meta.instanceName == raidName
            local unnamedRaidBoss = (not meta.instanceName or meta.instanceName == "") and meta.instanceType ~= "party" and meta.instanceType ~= "world"
            if sameName or unnamedRaidBoss then
                raid.bosses[#raid.bosses + 1] = event
            end
        end
    end
    return raids
end

local function DungeonEnters(events)
    local list = {}
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.InstanceEnter and meta.instanceType == "party" and not meta.keystone then
            list[#list + 1] = event
        end
    end
    return list
end

local function InstanceTitle(event, fallback)
    local meta = event.meta or {}
    if meta.instanceName and meta.instanceName ~= "" then
        return meta.instanceName
    end
    local text = event.text or fallback
    return (text:gsub("^Entered ", ""))
end

local function EnterRow(event, fallback)
    local meta = event.meta or {}
    local lines = {}
    Push(lines, Muted(meta.difficultyName))
    Push(lines, CharacterName(event.guid))
    Push(lines, Stamp("Entered", event.at))
    return {
        title = InstanceTitle(event, fallback),
        lines = lines,
        event = event,
    }
end

local function LatestEvent(list)
    local latest
    for index = 1, #(list or {}) do
        local event = list[index]
        if not latest or (event.at or 0) > (latest.at or 0) then
            latest = event
        end
    end
    return latest
end

local function RaidModel(summary, context, events)
    local model = Base(summary, context, "Raids", true)
    local raids = SplitRaids(events)
    model.summary = WBF.Format.CountLabel(#raids, "raid")
    local rows = {}
    for index = #raids, 1, -1 do
        local raid = raids[index]
        local meta = raid.event.meta or {}
        local lines = {}
        Push(lines, Muted(meta.difficultyName))
        Push(lines, CharacterName(raid.event.guid))
        local bossCount = #raid.bosses
        local value = bossCount > 0 and WBF.Format.CountLabel(bossCount, "boss", "bosses") or "Entered"
        rows[#rows + 1] = {
            title = InstanceTitle(raid.event, "Raid"),
            value = value,
            lines = lines,
            card = true,
            compact = true,
            iconEvent = raid.event,
            detail = "raidRun",
            detailId = raid.event.id or raid.event.at,
        }
    end
    if #rows > 0 then
        model.sections[1] = { rows = rows }
    end
    return Finish(model, "No raids entered during this period.")
end

local function RaidRunModel(summary, context, events)
    local raids = SplitRaids(events)
    local wanted = context.detailId
    local selected
    for index = 1, #raids do
        local raid = raids[index]
        local id = raid.event.id or raid.event.at
        if wanted == nil or id == wanted then
            selected = raid
            if wanted ~= nil then
                break
            end
        end
    end
    local title = selected and InstanceTitle(selected.event, "Raid") or "Raid Run"
    local model = Base(summary, context, title, true)
    if not selected then
        model.sections[1] = { rows = {} }
        return Finish(model, "That raid run is no longer available in this period.")
    end
    local meta = selected.event.meta or {}
    local bits = {}
    if meta.difficultyName and meta.difficultyName ~= "" then
        bits[#bits + 1] = meta.difficultyName
    end
    bits[#bits + 1] = WBF.Format.CountLabel(#selected.bosses, "boss", "bosses") .. " defeated"
    model.summary = table.concat(bits, "    ·    ")
    model.sections[#model.sections + 1] = { title = "Run", rows = { EnterRow(selected.event, "Raid") } }
    if #selected.bosses > 0 then
        model.sections[#model.sections + 1] = { title = "Bosses", rows = RowsOf(selected.bosses, BossRow) }
    end
    return Finish(model, "No raid details recorded for this run.")
end

local function GroupByName(events, keyFn)
    local map = {}
    local groups = {}
    for index = 1, #events do
        local event = events[index]
        local name = keyFn(event)
        if name and name ~= "" then
            local group = map[name]
            if not group then
                group = { name = name, events = {} }
                map[name] = group
                groups[#groups + 1] = group
            end
            group.events[#group.events + 1] = event
        end
    end
    table.sort(groups, function(a, b)
        if #a.events == #b.events then
            local aLatest = LatestEvent(a.events)
            local bLatest = LatestEvent(b.events)
            return (aLatest and aLatest.at or 0) > (bLatest and bLatest.at or 0)
        end
        return #a.events > #b.events
    end)
    return groups
end

local function BossSummaryRows(events)
    local list = Select(events, WBF.EventType.BossKill)
    local groups = GroupByName(list, BossName)
    local rows = {}
    for index = 1, #groups do
        local group = groups[index]
        local latest = LatestEvent(group.events)
        local lines = {}
        local meta = latest and latest.meta or {}
        Push(lines, Muted(meta.instanceName))
        rows[#rows + 1] = {
            title = group.name,
            value = WBF.Format.CountLabel(#group.events, "kill"),
            lines = lines,
            card = true,
            compact = true,
            iconEvent = latest,
            detail = "bossHistory",
            detailValue = group.name,
        }
    end
    return rows, #list
end

local function BossHistoryModel(summary, context, events)
    local name = context.detailValue or "Boss"
    local list = {}
    for index = 1, #events do
        local event = events[index]
        if event.eventType == WBF.EventType.BossKill and BossName(event) == name then
            list[#list + 1] = event
        end
    end
    local model = Base(summary, context, name, true)
    model.summary = WBF.Format.CountLabel(#list, "kill")
    model.sections[1] = { rows = RowsOf(list, BossRow) }
    return Finish(model, "No kills recorded for " .. name .. " during this period.")
end

local function DungeonSummaryRows(events)
    local list = DungeonEnters(events)
    local groups = GroupByName(list, function(event)
        return InstanceTitle(event, "Dungeon")
    end)
    local rows = {}
    for index = 1, #groups do
        local group = groups[index]
        local latest = LatestEvent(group.events)
        local lines = {}
        local meta = latest and latest.meta or {}
        Push(lines, Muted(meta.difficultyName))
        rows[#rows + 1] = {
            title = group.name,
            value = WBF.Format.CountLabel(#group.events, "run"),
            lines = lines,
            card = true,
            compact = true,
            iconEvent = latest,
            detail = "dungeonHistory",
            detailValue = group.name,
        }
    end
    return rows, #list
end

local function DungeonHistoryModel(summary, context, events)
    local name = context.detailValue or "Dungeon"
    local list = {}
    local entries = DungeonEnters(events)
    for index = 1, #entries do
        if InstanceTitle(entries[index], "Dungeon") == name then
            list[#list + 1] = entries[index]
        end
    end
    local model = Base(summary, context, name, true)
    model.summary = WBF.Format.CountLabel(#list, "run")
    model.sections[1] = { rows = RowsOf(list, function(event) return EnterRow(event, "Dungeon") end) }
    return Finish(model, "No runs recorded for " .. name .. " during this period.")
end

local function MythicSummaryRows(events)
    local list = Select(events, WBF.EventType.MythicPlus)
    local groups = GroupByName(list, MythicName)
    local rows = {}
    for index = 1, #groups do
        local group = groups[index]
        local best = 0
        local timed = 0
        for eventIndex = 1, #group.events do
            local meta = group.events[eventIndex].meta or {}
            local level = tonumber(meta.level or group.events[eventIndex].new) or 0
            if level > best then
                best = level
            end
            if meta.onTime == true and not meta.practiceRun then
                timed = timed + 1
            end
        end
        local lines = {}
        local bits = {}
        if best > 0 then
            bits[#bits + 1] = "Best +" .. best
        end
        if timed > 0 then
            bits[#bits + 1] = WBF.Format.CountLabel(timed, "timed run")
        end
        if #bits > 0 then
            Push(lines, Muted(table.concat(bits, "    ·    ")))
        end
        rows[#rows + 1] = {
            title = group.name,
            value = WBF.Format.CountLabel(#group.events, "run"),
            lines = lines,
            card = true,
            compact = true,
            iconEvent = LatestEvent(group.events),
            detail = "mythicHistory",
            detailValue = group.name,
        }
    end
    return rows, #list
end

local function MythicHistoryModel(summary, context, events)
    local name = context.detailValue or "Mythic+"
    local list = {}
    local all = Select(events, WBF.EventType.MythicPlus)
    for index = 1, #all do
        if MythicName(all[index]) == name then
            list[#list + 1] = all[index]
        end
    end
    local model = Base(summary, context, name, true)
    model.summary = WBF.Format.CountLabel(#list, "run")
    model.sections[1] = { rows = RowsOf(list, MythicRow) }
    return Finish(model, "No Mythic+ runs recorded for " .. name .. " during this period.")
end

local function DelveSummaryRows(events)
    local list = Select(events, WBF.EventType.Delve)
    local groups = GroupByName(list, DelveName)
    local rows = {}
    for index = 1, #groups do
        local group = groups[index]
        local highest = 0
        for eventIndex = 1, #group.events do
            local tier = tonumber((group.events[eventIndex].meta or {}).tier) or 0
            if tier > highest then
                highest = tier
            end
        end
        local lines = {}
        if highest > 0 then
            Push(lines, Muted("Highest tier " .. highest))
        end
        rows[#rows + 1] = {
            title = group.name,
            value = WBF.Format.CountLabel(#group.events, "run"),
            lines = lines,
            card = true,
            compact = true,
            iconEvent = LatestEvent(group.events),
            detail = "delveHistory",
            detailValue = group.name,
        }
    end
    return rows, #list
end

local function DelveHistoryModel(summary, context, events)
    local name = context.detailValue or "Delve"
    local list = {}
    local all = Select(events, WBF.EventType.Delve)
    for index = 1, #all do
        if DelveName(all[index]) == name then
            list[#list + 1] = all[index]
        end
    end
    local model = Base(summary, context, name, true)
    model.summary = WBF.Format.CountLabel(#list, "run")
    model.sections[1] = { rows = RowsOf(list, DelveRow) }
    return Finish(model, "No delve runs recorded for " .. name .. " during this period.")
end

local function ProfessionSummaryRows(events)
    local list = Select(events, WBF.EventType.Profession)
    local visible = {}
    for index = 1, #list do
        if not (list[index].meta and list[index].meta.surface == false) then
            visible[#visible + 1] = list[index]
        end
    end
    local groups = GroupByName(visible, ProfessionName)
    local rows = {}
    for index = 1, #groups do
        local group = groups[index]
        local ordered = Chrono(group.events)
        local startRank
        local endRank
        local learned = 0
        for eventIndex = 1, #ordered do
            local event = ordered[eventIndex]
            local meta = event.meta or {}
            if meta.learned then
                learned = learned + 1
            end
            if startRank == nil and tonumber(event.previous) then
                startRank = tonumber(event.previous)
            end
            if tonumber(event.new) then
                endRank = tonumber(event.new)
                if startRank == nil then
                    startRank = tonumber(event.new)
                end
            end
        end
        local value = WBF.Format.CountLabel(#group.events, "change")
        if startRank and endRank and startRank ~= endRank then
            value = WBF.Format.Progression(startRank, endRank)
        elseif learned > 0 and #group.events == learned then
            value = learned == 1 and "Learned" or WBF.Format.CountLabel(learned, "learn")
        end
        local lines = {}
        Push(lines, Muted(WBF.Format.CountLabel(#group.events, "record")))
        rows[#rows + 1] = {
            title = group.name,
            value = value,
            lines = lines,
            card = true,
            compact = true,
            iconEvent = LatestEvent(group.events),
            detail = "professionHistory",
            detailValue = group.name,
        }
    end
    return rows, #visible
end

local function ProfessionHistoryModel(summary, context, events)
    local name = context.detailValue or "Profession"
    local list = {}
    local all = Select(events, WBF.EventType.Profession)
    for index = 1, #all do
        local event = all[index]
        if not (event.meta and event.meta.surface == false) and ProfessionName(event) == name then
            list[#list + 1] = event
        end
    end
    local model = Base(summary, context, name, true)
    model.summary = WBF.Format.CountLabel(#list, "change")
    model.sections[1] = { rows = RowsOf(list, ProfessionRow) }
    return Finish(model, "No profession changes recorded for " .. name .. " during this period.")
end

local function ReputationRows(events)
    local groups = {}
    local order = {}
    for index = 1, #events do
        local event = events[index]
        if event.eventType == WBF.EventType.Reputation then
            local meta = event.meta or {}
            local name = meta.faction or "Reputation"
            local group = groups[name]
            if not group then
                group = { name = name, delta = 0, events = {}, account = false }
                groups[name] = group
                order[#order + 1] = group
            end
            group.delta = group.delta + (event.delta or 0)
            group.events[#group.events + 1] = event
            if meta.accountWide then
                group.account = true
            end
        end
    end
    table.sort(order, function(a, b)
        return math.abs(a.delta) > math.abs(b.delta)
    end)
    local rows = {}
    local total = 0
    for index = 1, #order do
        local group = order[index]
        total = total + group.delta
        local count = #group.events
        local kind = group.account and "Warband reputation" or "Reputation"
        local lines = {}
        Push(lines, Muted(kind .. "   ·   " .. WBF.Format.CountLabel(count, "change")))
        local color = group.delta > 0 and WBF.UI.Colors.green or (group.delta < 0 and WBF.UI.Colors.red or WBF.UI.Colors.cream)
        rows[#rows + 1] = {
            title = group.name,
            value = WBF.Format.Signed(group.delta),
            valueColor = color,
            lines = lines,
            card = true,
            compact = true,
            fallback = "Interface\\Icons\\Achievement_Reputation_01",
            detail = "reputationFaction",
            reputationFaction = group.name,
        }
    end
    return rows, total
end

local function ReputationChangeRow(event)
    local meta = event.meta or {}
    local lines = {}
    Push(lines, Muted(WBF.Format.Ago(event.at)))
    Push(lines, CharacterName(event.guid))
    if meta.bonus and tonumber(meta.bonus) and tonumber(meta.bonus) ~= 0 then
        Push(lines, Muted("Bonus " .. WBF.Format.Signed(tonumber(meta.bonus))))
    end
    return {
        title = meta.accountWide and "Warband reputation" or "Reputation",
        value = WBF.Format.Signed(event.delta or 0),
        valueColor = (event.delta or 0) > 0 and WBF.UI.Colors.green or ((event.delta or 0) < 0 and WBF.UI.Colors.red or WBF.UI.Colors.cream),
        lines = lines,
        event = event,
        compact = true,
        card = true,
    }
end

local function RenownHistoryRows(events, faction)
    local rows = {}
    for index = 1, #events do
        local event = events[index]
        if event.eventType == WBF.EventType.Renown then
            local meta = event.meta or {}
            if not faction or (meta.faction or "Renown") == faction then
                local lines = {}
                local gained = (event.delta or 0) >= 0
                Push(lines, CharacterName(event.guid))
                if event.at then
                    Push(lines, Muted((gained and "Earned " or "Changed ") .. WBF.Format.Ago(event.at)))
                end
                rows[#rows + 1] = {
                    title = meta.faction or "Renown",
                    value = (event.previous and event.new) and WBF.Format.Progression(event.previous, event.new) or nil,
                    valueColor = gained and WBF.UI.Colors.green or WBF.UI.Colors.red,
                    lines = lines,
                    card = true,
                    compact = true,
                    event = event,
                }
            end
        end
    end
    return rows
end

local function RenownSummaryRows(events)
    local list = Select(events, WBF.EventType.Renown)
    local groups = GroupByName(list, function(event)
        return (event.meta or {}).faction or "Renown"
    end)
    local rows = {}
    for index = 1, #groups do
        local group = groups[index]
        local ordered = Chrono(group.events)
        local first = ordered[1]
        local last = ordered[#ordered]
        local startValue = first and tonumber(first.previous)
        local endValue = last and tonumber(last.new)
        local value = WBF.Format.CountLabel(#group.events, "level")
        if startValue and endValue then
            value = WBF.Format.Progression(startValue, endValue)
        end
        local lines = {}
        Push(lines, Muted(WBF.Format.CountLabel(#group.events, "change")))
        rows[#rows + 1] = {
            title = group.name,
            value = value,
            valueColor = WBF.UI.Colors.green,
            lines = lines,
            card = true,
            compact = true,
            iconEvent = last,
            detail = "renownFaction",
            detailValue = group.name,
        }
    end
    return rows, #list
end

local function RenownFactionModel(summary, context, events)
    local faction = context.detailValue or "Renown"
    local rows = RenownHistoryRows(events, faction)
    local model = Base(summary, context, faction, true)
    model.summary = WBF.Format.CountLabel(#rows, "renown change")
    model.sections[1] = { rows = rows }
    return Finish(model, "No renown changes recorded for " .. faction .. " during this period.")
end

local function ItemLevelEvents(events, guid)
    local list = {}
    for index = 1, #events do
        local event = events[index]
        if event.eventType == WBF.EventType.ItemLevel and (not guid or event.guid == guid) then
            list[#list + 1] = event
        end
    end
    return Chrono(list)
end

local function ItemLevelModel(summary, context, events)
    local guid = context.characterGUID
    local character = FindCharacter(summary, guid)
    local stored = guid and WBF.Characters.Get(guid)
    local name = (character and character.name) or (stored and stored.name) or "Character"
    local model = Base(summary, context, "Item Level", false)
    model.subtitle = (summary.label or "") .. "    ·    " .. name
    local changes = ItemLevelEvents(events, guid)
    local rows = {}
    local startValue = character and character.ilvlStart
    local endValue = character and character.ilvlEnd
    if startValue then
        rows[#rows + 1] = { card = true, title = "Started", value = tostring(startValue) }
    end
    for index = 1, #changes do
        local event = changes[index]
        rows[#rows + 1] = {
            card = true,
            title = date("%A", event.at),
            value = (event.previous and event.new) and WBF.Format.Progression(event.previous, event.new) or (event.text or ""),
            valueColor = (event.delta or 0) >= 0 and WBF.UI.Colors.green or WBF.UI.Colors.red,
            lines = { Muted(WBF.Time.Clock(event.at)) },
            event = event,
        }
    end
    if endValue then
        rows[#rows + 1] = { card = true, title = "Current", value = tostring(endValue) }
    end
    if startValue and endValue then
        local delta = endValue - startValue
        rows[#rows + 1] = {
            card = true,
            title = "Total",
            value = WBF.Format.Signed(delta),
            valueColor = GoldColor(delta),
        }
    end
    if #changes == 0 and startValue and endValue and startValue ~= endValue then
        model.note = "Only the starting and current item levels were recorded."
    end
    model.sections[1] = { rows = rows }
    return Finish(model, "No item level changes recorded during this period.")
end

local function GoldModel(summary, context)
    local model = Base(summary, context, "Gold", true)
    if not summary.goldTracked then
        model.sections[1] = { rows = {} }
        return Finish(model, "No gold readings for this period.")
    end
    local rows = {}
    local offline = 0
    if context.characterGUID then
        local byGuid = summary.goldOfflineByGuid
        offline = byGuid and byGuid[context.characterGUID] or 0
    else
        offline = summary.goldOffline or 0
    end
    if context.characterGUID then
        local character = FindCharacter(summary, context.characterGUID)
        local amount = character and character.counts.gold or 0
        rows[#rows + 1] = {
            card = true,
            title = "Net change",
            value = WBF.Format.Gold(amount, true, "precise"),
            valueColor = GoldColor(amount),
            detail = "goldTrend",
            characterGUID = context.characterGUID,
            period = context.period,
        }
        model.note = "Gold gained or spent while this character was tracked. Gold they already held when first seen is not included."
    else
        rows[#rows + 1] = {
            card = true,
            title = "Net Change",
            value = WBF.Format.Gold(summary.goldNet or 0, true, "precise"),
            valueColor = GoldColor(summary.goldNet or 0),
            detail = "goldTrend",
            period = context.period,
            warband = true,
        }
        for index = 1, #summary.characters do
            local character = summary.characters[index]
            local amount = character.counts and character.counts.gold or 0
            if amount ~= 0 then
                rows[#rows + 1] = {
                    card = true,
                    title = character.name or "Character",
                    value = WBF.Format.Gold(amount, true, "precise"),
                    valueColor = GoldColor(amount),
                    detail = "goldTrend",
                    characterGUID = character.guid,
                    period = context.period,
                }
            end
        end
        model.note = "Net Gold is each character's gains and spending added together. Gold already held when a character is first seen is not counted."
    end
    if offline ~= 0 then
        rows[#rows + 1] = {
            card = true,
            title = "Between sessions",
            value = WBF.Format.Gold(offline, true, "precise"),
            valueColor = GoldColor(offline),
        }
        local extra = " Between sessions is gold that changed while nothing was being tracked. It is included in the net once."
        model.note = (model.note or "") .. extra
    end
    model.sections[1] = { rows = rows }
    return Finish(model, "No gold readings for this period.")
end

local function PreyNote(events)
    local completed = 0
    local known = 0
    local counts = { Normal = 0, Hard = 0, Nightmare = 0 }
    local journey = 0
    local journeyName
    for index = 1, #events do
        local meta = events[index].meta or {}
        if meta.completed then
            completed = completed + 1
            if PREY_DIFFICULTY[meta.difficulty] then
                known = known + 1
                counts[meta.difficulty] = counts[meta.difficulty] + 1
            end
            if meta.journey and meta.journey > 0 then
                journey = journey + meta.journey
                journeyName = meta.journeyName or journeyName
            end
        end
    end
    local parts = {}
    if completed > 0 and known == completed then
        if counts.Normal > 0 then
            parts[#parts + 1] = counts.Normal .. " Normal"
        end
        if counts.Hard > 0 then
            parts[#parts + 1] = counts.Hard .. " Hard"
        end
        if counts.Nightmare > 0 then
            parts[#parts + 1] = counts.Nightmare .. " Nightmare"
        end
    end
    if journey > 0 then
        parts[#parts + 1] = (journeyName or "Journey") .. "  " .. WBF.Format.Signed(journey)
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "    ·    ")
end

local function PreyModel(summary, context, events)
    local model = Base(summary, context, "Prey", true)
    local completed = {}
    local started = {}
    for index = 1, #events do
        local event = events[index]
        if event.eventType == WBF.EventType.Prey then
            local meta = event.meta or {}
            if meta.completed then
                completed[#completed + 1] = event
            elseif not meta.abandoned and not meta.resolved then
                started[#started + 1] = event
            end
        end
    end
    local open = {}
    for index = 1, #started do
        local startEvent = started[index]
        local meta = startEvent.meta or {}
        local matched = false
        for completeIndex = 1, #completed do
            local complete = completed[completeIndex]
            local completeMeta = complete.meta or {}
            local sameCharacter = not complete.guid or not startEvent.guid or complete.guid == startEvent.guid
            local sameId = not completeMeta.questID or not meta.questID or completeMeta.questID == meta.questID
            if sameCharacter and sameId and completeMeta.startedAt == startEvent.at then
                matched = true
                break
            end
        end
        if not matched then
            open[#open + 1] = startEvent
        end
    end
    local summaryBits = {}
    if #completed > 0 then
        summaryBits[#summaryBits + 1] = WBF.Format.CountLabel(#completed, "hunt") .. " completed"
    end
    if #open > 0 then
        summaryBits[#summaryBits + 1] = tostring(#open) .. " in progress"
    end
    if #summaryBits > 0 then
        model.summary = table.concat(summaryBits, "   ·   ")
    end
    model.note = PreyNote(events)
    if #completed > 0 then
        model.sections[#model.sections + 1] = { title = "Completed", rows = RowsOf(completed, PreyRow) }
    end
    if #open > 0 then
        model.sections[#model.sections + 1] = {
            title = "In progress",
            rows = RowsOf(open, PreyRow),
        }
    end
    return Finish(model, "No prey hunts recorded during this period.")
end

local function CollectionRow(title, count, singular, detail, guid, atlases, fallback)
    return {
        card = true,
        title = WBF.Format.CountLabel(count, singular),
        detail = detail,
        characterGUID = guid,
        atlases = atlases,
        fallback = fallback,
    }
end

local function CharacterModel(summary, context, events)
    local guid = context.characterGUID
    local character = FindCharacter(summary, guid)
    local stored = guid and WBF.Characters.Get(guid)
    local name = (character and character.name) or (stored and stored.name) or "Character"
    local model = Base(summary, context, name, false)
    model.subtitle = summary.label
    if not character and #events == 0 then
        model.empty = "Nothing recorded for this character during this period."
        model.sections[1] = { rows = {} }
        return model
    end

    local counts = character and character.counts or {}
    local noteBits = {}
    local levelEnd = character and character.levelEnd
    local levelStart = character and character.levelStart
    if levelStart and levelEnd and levelEnd > levelStart then
        noteBits[#noteBits + 1] = "Level " .. WBF.Format.Progression(levelStart, levelEnd)
    elseif levelEnd or levelStart then
        noteBits[#noteBits + 1] = "Level " .. (levelEnd or levelStart)
    end
    local specName = (character and character.specName) or (stored and stored.specName)
    if specName and specName ~= "" then
        noteBits[#noteBits + 1] = specName
    end
    if #noteBits > 0 then
        model.note = table.concat(noteBits, "    |    ")
    end

    local metrics = {}
    local playedSeconds = character and character.playedSeconds or 0
    if character and WBF.Aggregator.LivePlay then
        local extra, guid = WBF.Aggregator.LivePlay(summary)
        if guid and guid == character.guid then
            playedSeconds = playedSeconds + extra
        end
    end
    metrics[#metrics + 1] = {
        card = true,
        title = "Played",
        value = WBF.Format.Played(playedSeconds),
    }
    if character and character.ilvlStart and character.ilvlEnd and character.ilvlStart ~= character.ilvlEnd then
        local delta = character.ilvlEnd - character.ilvlStart
        metrics[#metrics + 1] = {
            card = true,
            title = "Item Level",
            value = WBF.Format.Progression(character.ilvlStart, character.ilvlEnd),
            lines = { { text = WBF.Format.Signed(delta), color = delta > 0 and "green" or "red" } },
            detail = "itemLevel",
            characterGUID = guid,
        }
    elseif character and (character.ilvlEnd or character.ilvlStart) then
        metrics[#metrics + 1] = {
            card = true,
            title = "Item Level",
            value = tostring(character.ilvlEnd or character.ilvlStart),
        }
    end
    if character and character.counts and character.counts.gold ~= 0 then
        metrics[#metrics + 1] = {
            card = true,
            title = "Gold",
            value = WBF.Format.Gold(character.counts.gold, true, "precise"),
            valueColor = GoldColor(character.counts.gold),
            detail = "gold",
            characterGUID = guid,
        }
    end
    model.sections[#model.sections + 1] = { rows = metrics }

    local raids = SplitRaids(events)
    local dungeons = DungeonEnters(events)
    local instanceRows = {}
    for index = #raids, 1, -1 do
        instanceRows[#instanceRows + 1] = EnterRow(raids[index].event, "Raid")
    end
    for index = 1, #dungeons do
        instanceRows[#instanceRows + 1] = EnterRow(dungeons[index], "Dungeon")
    end
    if #instanceRows > 0 then
        model.sections[#model.sections + 1] = { title = "Instances", rows = instanceRows }
    end

    local bosses = Select(events, WBF.EventType.BossKill)
    if #bosses > 0 then
        model.sections[#model.sections + 1] = { title = "Bosses", rows = RowsOf(bosses, BossRow) }
    end

    local mythic = Select(events, WBF.EventType.MythicPlus)
    if #mythic > 0 then
        model.sections[#model.sections + 1] = { title = "Mythic+", rows = RowsOf(mythic, MythicRow) }
    end

    local delves = Select(events, WBF.EventType.Delve)
    if #delves > 0 then
        model.sections[#model.sections + 1] = { title = "Delves", rows = RowsOf(delves, DelveRow) }
    end

    local quests = Select(events, WBF.EventType.Quest)
    if #quests > 0 then
        model.sections[#model.sections + 1] = { title = "Quests", rows = RowsOf(quests, QuestRow) }
    end

    local worldQuests = Select(events, WBF.EventType.WorldQuest)
    if #worldQuests > 0 then
        model.sections[#model.sections + 1] = { title = "World Quests", rows = RowsOf(worldQuests, QuestRow) }
    end

    local curseSurges = SelectCurseSurges(events)
    if #curseSurges > 0 then
        model.sections[#model.sections + 1] = { title = "Curse Surges", rows = RowsOf(curseSurges, QuestRow) }
    end

    local worldEvents = SelectWorldEvents(events)
    if #worldEvents > 0 then
        model.sections[#model.sections + 1] = { title = "World Events", rows = RowsOf(worldEvents, QuestRow) }
    end

    local achievements = Select(events, WBF.EventType.Achievement)
    if #achievements > 0 then
        model.sections[#model.sections + 1] = { title = "Achievements", rows = RowsOf(achievements, AchievementRow) }
    end

    local collections = {}
    if (counts.appearances or 0) > 0 then
        collections[#collections + 1] = CollectionRow("Appearances", counts.appearances, "Appearance", "appearances", guid, { "transmog-icon-chat" }, "Interface\\Icons\\INV_Chest_Cloth_17")
    end
    if (counts.mounts or 0) > 0 then
        collections[#collections + 1] = CollectionRow("Mounts", counts.mounts, "Mount", "mounts", guid, nil, "Interface\\Icons\\Ability_Mount_RidingHorse")
    end
    if (counts.pets or 0) > 0 then
        collections[#collections + 1] = CollectionRow("Pets", counts.pets, "Pet", "pets", guid, nil, "Interface\\Icons\\INV_Box_PetCarrier_01")
    end
    if (counts.newDecor or 0) > 0 then
        local decor = CollectionRow("New Decor", counts.newDecor, "New Decor", "housing", guid, nil, "Interface\\Icons\\INV_Misc_Statue_02")
        decor.title = WBF.Format.CountLabel(counts.newDecor, "New Decor", "New Decor")
        collections[#collections + 1] = decor
    end
    if #collections > 0 then
        model.sections[#model.sections + 1] = { title = "Collections", rows = collections }
    end

    if (counts.reputation or 0) ~= 0 or (counts.renown or 0) > 0 then
        local lines = {}
        if (counts.renown or 0) > 0 then
            Push(lines, { text = WBF.Format.CountLabel(counts.renown, "renown level"), color = "green" })
        end
        model.sections[#model.sections + 1] = {
            title = "Reputation",
            rows = {
                {
                    card = true,
                    title = "Reputation",
                    value = WBF.Format.Signed(counts.reputation or 0),
                    valueColor = GoldColor(counts.reputation or 0),
                    lines = lines,
                    detail = (counts.reputation or 0) ~= 0 and "reputation" or "renown",
                    characterGUID = guid,
                },
            },
        }
    end

    local professions = Select(events, WBF.EventType.Profession)
    if #professions > 0 then
        model.sections[#model.sections + 1] = { title = "Professions", rows = RowsOf(professions, ProfessionRow) }
    end

    if (counts.prey or 0) > 0 or (counts.preyStarted or 0) > 0 then
        local title
        if (counts.prey or 0) > 0 then
            title = WBF.Format.CountLabel(counts.prey, "Prey Hunt")
            if (counts.preyStarted or 0) > 0 then
                title = title .. "   ·   " .. counts.preyStarted .. " in progress"
            end
        else
            title = WBF.Format.CountLabel(counts.preyStarted, "Prey Hunt") .. " in progress"
        end
        local lines = {}
        if counts.preyHighest then
            Push(lines, { text = "Highest Prey: " .. counts.preyHighest, color = "gold" })
        end
        if (counts.journey or 0) > 0 then
            local journeyName
            for index = 1, #events do
                local meta = events[index].meta or {}
                if meta.journeyName and meta.journeyName ~= "" then
                    journeyName = meta.journeyName
                    break
                end
            end
            Push(lines, { text = (journeyName or "Journey") .. "  " .. WBF.Format.Signed(counts.journey), color = "green" })
        end
        model.sections[#model.sections + 1] = {
            title = "Prey",
            rows = {
                {
                    card = true,
                    title = title,
                    lines = lines,
                    detail = "prey",
                    characterGUID = guid,
                    fallback = "Interface\\Icons\\INV_Misc_MonsterClaw_02",
                },
            },
        }
    end

    if WBF.Resources and WBF.Resources.CharacterCards then
        local cards = WBF.Resources.CharacterCards(events)
        if #cards > 0 then
            local rows = {}
            for index = 1, #cards do
                local card = cards[index]
                local lines = {}
                if card.spent > 0 then
                    Push(lines, { text = "Spent  " .. WBF.Format.Signed(-card.spent), color = "muted" })
                end
                if card.transferred ~= 0 then
                    Push(lines, { text = "Transferred  " .. WBF.Format.Signed(card.transferred), color = "muted" })
                end
                local value = card.earned > 0 and card.earned or (card.spent > 0 and -card.spent or card.transferred)
                rows[#rows + 1] = {
                    card = true,
                    title = card.name,
                    value = WBF.Format.Signed(value),
                    valueColor = GoldColor(value),
                    lines = lines,
                    icon = card.texture,
                    fallback = "Interface\\Icons\\INV_Misc_Coin_01",
                    detail = "resource",
                    resourceKey = card.key,
                    characterGUID = guid,
                }
            end
            model.sections[#model.sections + 1] = { title = "Resources", rows = rows }
        end
    end

    return Finish(model, "Nothing recorded for this character during this period.")
end

local Renderers = {}

Renderers.housing = function(summary, context)
    if WBF.Housing and WBF.Housing.BuildDetail then
        return WBF.Housing.BuildDetail(summary, context)
    end
    local model = Base(summary, context, "Housing", true)
    model.empty = "No housing decor recorded during this period."
    return model
end

Renderers.appearances = function(summary, context, events)
    local list = Select(events, WBF.EventType.Appearance)
    return SimpleList(summary, context, list, "appearances", "Appearances", "No appearances collected during this period.", WBF.Format.CountLabel(#list, "appearance") .. " collected", AppearanceRow)
end

Renderers.bosses = function(summary, context, events)
    local rows, total = BossSummaryRows(events)
    local model = Base(summary, context, "Bosses", true)
    model.summary = WBF.Format.CountLabel(total, "boss", "bosses") .. " defeated    ·    " .. WBF.Format.CountLabel(#rows, "unique boss", "unique bosses")
    model.sections[1] = { rows = rows }
    return Finish(model, "No bosses defeated during this period.")
end

Renderers.bossHistory = BossHistoryModel

Renderers.quests = function(summary, context, events)
    local list = Select(events, WBF.EventType.Quest)
    return SimpleList(summary, context, list, "quests", "Quests", "No quests completed during this period.", WBF.Format.CountLabel(#list, "quest") .. " completed", QuestRow)
end

Renderers.worldQuests = function(summary, context, events)
    local list = Select(events, WBF.EventType.WorldQuest)
    return SimpleList(summary, context, list, "worldQuests", "World Quests", "No world quests completed during this period.", WBF.Format.CountLabel(#list, "world quest") .. " completed", QuestRow)
end

Renderers.curseSurges = function(summary, context, events)
    local list = SelectCurseSurges(events)
    return SimpleList(summary, context, list, "curseSurges", "Curse Surges", "No Curse Surges completed during this period.", WBF.Format.CountLabel(#list, "Curse Surge") .. " completed", QuestRow)
end

Renderers.worldEvents = function(summary, context, events)
    local list = SelectWorldEvents(events)
    return SimpleList(summary, context, list, "worldEvents", "World Events", "No world events completed during this period.", WBF.Format.CountLabel(#list, "world event") .. " completed", QuestRow)
end

Renderers.questsAll = function(summary, context, events)
    local model = Base(summary, context, "Quests", true)
    local quests = Select(events, WBF.EventType.Quest)
    local worldQuests = Select(events, WBF.EventType.WorldQuest)
    local total = #quests + #worldQuests
    model.summary = WBF.Format.CountLabel(total, "quest") .. " completed"
    if #quests > 0 then
        model.sections[#model.sections + 1] = { title = "Quests", rows = RowsOf(quests, QuestRow) }
    end
    if #worldQuests > 0 then
        model.sections[#model.sections + 1] = { title = "World Quests", rows = RowsOf(worldQuests, QuestRow) }
    end
    return Finish(model, "No quests completed during this period.")
end

Renderers.achievements = function(summary, context, events)
    local list = Select(events, WBF.EventType.Achievement)
    return SimpleList(summary, context, list, "achievements", "Achievements", "No achievements earned during this period.", WBF.Format.CountLabel(#list, "achievement") .. " earned", AchievementRow)
end

Renderers.mounts = function(summary, context, events)
    local list = Select(events, WBF.EventType.Mount)
    local model = SimpleList(summary, context, list, "mounts", "Mounts", "No mounts collected during this period.", WBF.Format.CountLabel(#list, "mount") .. " collected", MountRow)
    if #list > 0 then
        model.note = "Hover a mount to preview it. Click the row to open that mount in the Mount Journal."
    end
    return model
end

Renderers.pets = function(summary, context, events)
    local list = Select(events, WBF.EventType.Pet)
    local model = SimpleList(summary, context, list, "pets", "Pets", "No pets collected during this period.", WBF.Format.CountLabel(#list, "pet") .. " collected", PetRow)
    if #list > 0 then
        model.note = "Hover a pet to preview it. Click the row to open that pet in the Pet Journal."
    end
    return model
end

Renderers.mythicPlus = function(summary, context, events)
    local rows, total = MythicSummaryRows(events)
    local model = Base(summary, context, "Mythic+", true)
    model.summary = WBF.Format.CountLabel(total, "run") .. " recorded    ·    " .. WBF.Format.CountLabel(#rows, "dungeon")
    model.sections[1] = { rows = rows }
    return Finish(model, "No Mythic+ runs completed during this period.")
end

Renderers.mythicHistory = MythicHistoryModel

Renderers.delves = function(summary, context, events)
    local rows, total = DelveSummaryRows(events)
    local model = Base(summary, context, "Delves", true)
    model.summary = WBF.Format.CountLabel(total, "run") .. " completed    ·    " .. WBF.Format.CountLabel(#rows, "delve")
    model.sections[1] = { rows = rows }
    return Finish(model, "No delves completed during this period.")
end

Renderers.delveHistory = DelveHistoryModel

Renderers.professions = function(summary, context, events)
    local rows, total = ProfessionSummaryRows(events)
    local model = Base(summary, context, "Professions", true)
    model.summary = WBF.Format.CountLabel(total, "change") .. " recorded    ·    " .. WBF.Format.CountLabel(#rows, "profession")
    model.sections[1] = { rows = rows }
    return Finish(model, "No profession changes recorded during this period.")
end

Renderers.professionHistory = ProfessionHistoryModel

Renderers.dungeons = function(summary, context, events)
    local rows, total = DungeonSummaryRows(events)
    local model = Base(summary, context, "Dungeons", true)
    model.summary = WBF.Format.CountLabel(total, "run") .. " entered    ·    " .. WBF.Format.CountLabel(#rows, "dungeon")
    model.sections[1] = { rows = rows }
    return Finish(model, "No dungeons entered during this period.")
end

Renderers.dungeonHistory = DungeonHistoryModel
Renderers.raids = RaidModel
Renderers.raidRun = RaidRunModel
Renderers.reputation = function(summary, context, events)
    local model = Base(summary, context, "Reputation", true)
    local rows, total = ReputationRows(events)
    if total > 0 then
        model.summary = "Total gained: " .. WBF.Format.Signed(total) .. "    ·    " .. WBF.Format.CountLabel(#rows, "faction")
    elseif total < 0 then
        model.summary = "Total change: " .. WBF.Format.Signed(total) .. "    ·    " .. WBF.Format.CountLabel(#rows, "faction")
    end
    if #rows > 0 then
        model.sections[#model.sections + 1] = { rows = rows }
    end
    local renown = RenownSummaryRows(events)
    if #renown > 0 then
        model.sections[#model.sections + 1] = { title = "Renown", rows = renown }
    end
    return Finish(model, "No reputation recorded during this period.")
end

Renderers.reputationFaction = function(summary, context, events)
    local faction = context.reputationFaction or "Reputation"
    local list = {}
    local total = 0
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.Reputation and meta.faction == faction then
            list[#list + 1] = event
            total = total + (event.delta or 0)
        end
    end
    local model = Base(summary, context, faction, true)
    if #list > 0 then
        local label = total >= 0 and "Total gained: " or "Total change: "
        model.summary = label .. WBF.Format.Signed(total) .. "    ·    " .. WBF.Format.CountLabel(#list, "change")
        model.sections[1] = { title = "Activity", rows = RowsOf(list, ReputationChangeRow) }
    end
    return Finish(model, "No reputation changes recorded for " .. faction .. " during this period.")
end

Renderers.renown = function(summary, context, events)
    local rows, total = RenownSummaryRows(events)
    local model = Base(summary, context, "Renown", true)
    model.summary = WBF.Format.CountLabel(total, "renown change") .. "    ·    " .. WBF.Format.CountLabel(#rows, "faction")
    model.sections[1] = { rows = rows }
    return Finish(model, "No renown levels recorded during this period.")
end

Renderers.renownFaction = RenownFactionModel

Renderers.gold = function(summary, context)
    return GoldModel(summary, context)
end


Renderers.resource = function(summary, context)
    local name = "Resource"
    if context.resourceKey and WBF.Resources and WBF.Resources.Get then
        local definition = WBF.Resources.Get(context.resourceKey)
        if definition then
            name = definition.displayName or definition.name or definition.short or name
        end
    end
    local model = Base(summary, context, name, false)
    model.empty = "Nothing recorded for this resource."
    model.sections[1] = { rows = {} }
    return model
end

Renderers.prey = PreyModel
Renderers.itemLevel = ItemLevelModel
Renderers.character = CharacterModel

local SPECIAL_ROUTES = {
    resource = true,
    goldTrend = true,
    character = true,
    petBattles = true,
}

function WBF.Detail.CanOpen(category)
    if type(category) ~= "string" or category == "" then
        return false
    end
    return SPECIAL_ROUTES[category] == true or type(Renderers[category]) == "function"
end

function WBF.Detail.Build(category, context)
    context = context or {}
    local summary = WBF.Aggregator.Build(context.period or "week", context.monthOffset)
    local title = TITLES[category] or "Detail"
    if summary.empty then
        local model = Base(summary, context, title, category ~= "character")
        model.empty = summary.emptyReason or "Nothing recorded for this period."
        return model
    end
    local renderer = Renderers[category]
    if not renderer then
        local model = Base(summary, context, title, true)
        model.empty = "Nothing to show for this period."
        return model
    end
    return renderer(summary, context, ContextEvents(summary, context))
end

function WBF.Detail.BackLabel(stack)
    if not stack or #stack == 0 then
        return "Back"
    end
    if #stack == 1 then
        local origin = stack[1].origin
        if origin and origin.label and origin.label ~= "" then
            return "Back to " .. origin.label
        end
        local frame = WBF.UI.frame
        if frame and frame.view == "resources" then
            return "Back to Resources"
        end
        local _, _, label = WBF.Aggregator.Range(stack[1].context.period, stack[1].context.monthOffset)
        return "Back to " .. (label or "dashboard")
    end
    local parent = stack[#stack - 1]
    if parent.category == "character" and parent.context.characterGUID then
        local character = WBF.Characters.Get(parent.context.characterGUID)
        if character and character.name and character.name ~= "" then
            return "Back to " .. character.name
        end
    end
    if parent.category == "resource" and parent.context.resourceKey and WBF.Resources and WBF.Resources.Get then
        local definition = WBF.Resources.Get(parent.context.resourceKey)
        if definition then
            return "Back to " .. (definition.short or definition.name)
        end
    end
    return "Back to " .. (TITLES[parent.category] or "dashboard")
end
