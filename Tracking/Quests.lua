local _, WBF = ...

WBF.Quests = {}

-- Curse Surges are rotating public events on the Coiled Isle. Blizzard tracks
-- them with hidden quests, and the generic completion (96935, "Curse Surge")
-- is what QUEST_TURNED_IN reports. Each variant also has its own quest id,
-- stored on AreaPOI 8936-8940 in the same field that other event markers use
-- for their quest. Those five rows exist in QuestV2 and have no public quest
-- page. Identification uses these ids and the scheduler's areaPoiID, not the
-- localized quest name.
--
-- Other AreaPOI quest links were checked and left as quests. 96995 is the
-- weekly Turn Back the Surge. 83240 is The Theater Troupe. 90661 and 92418
-- are the public Dastardly Duos and Abundance quests. Several other markers
-- point at unrelated quests (Gearing Up for Trouble, Lost Legends, and so
-- on). None of those have the hidden-completion evidence 96935 has.

local COILED_ISLE = 2512
local SURGE_PAIR_SECONDS = 20

local CURSE_SURGE_POI = {
    [8936] = { areaPoiID = 8936, questID = 93718, variant = "The Looming Mutagenitor" },
    [8937] = { areaPoiID = 8937, questID = 93722, variant = "Siege at the Whispering Marsh" },
    [8938] = { areaPoiID = 8938, questID = 93676, variant = "The Broodmother's Nest" },
    [8939] = { areaPoiID = 8939, questID = 93715, variant = "Mlurkkr Massacre" },
    [8940] = { areaPoiID = 8940, questID = 93673, variant = "The Malformed Leviathan" },
}

local CURSE_SURGE_QUEST = {
    [96935] = { generic = true },
    [93718] = CURSE_SURGE_POI[8936],
    [93722] = CURSE_SURGE_POI[8937],
    [93676] = CURSE_SURGE_POI[8938],
    [93715] = CURSE_SURGE_POI[8939],
    [93673] = CURSE_SURGE_POI[8940],
}

local recentSurge = nil

local function IsWorldQuest(questID)
    if C_QuestLog and C_QuestLog.IsWorldQuest then
        if WBF.Format.SafeBoolean(C_QuestLog.IsWorldQuest, questID) == true then
            return true
        end
    end
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local tag = WBF.Format.SafeCall(C_QuestLog.GetQuestTagInfo, questID)
        if WBF.Format.IsSecret(tag) or type(tag) ~= "table" then
            return false
        end
        local worldType = tag.worldQuestType
        if WBF.Format.IsSecret(worldType) then
            return false
        end
        if worldType ~= nil then
            return true
        end
    end
    return false
end

local function QuestType(questID)
    if not (C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification and Enum and Enum.QuestClassification) then
        return nil
    end
    local value = WBF.Format.SafeCall(C_QuestInfoSystem.GetQuestClassification, questID)
    if WBF.Format.IsSecret(value) or value == nil then
        return nil
    end
    local kinds = Enum.QuestClassification
    if kinds.Campaign and value == kinds.Campaign then
        return "Campaign"
    end
    if kinds.Calling and value == kinds.Calling then
        return "Calling"
    end
    if kinds.Recurring and value == kinds.Recurring then
        return "Recurring"
    end
    if kinds.Legendary and value == kinds.Legendary then
        return "Legendary"
    end
    if kinds.Questline and value == kinds.Questline then
        return "Questline"
    end
    if kinds.Important and value == kinds.Important then
        return "Important"
    end
    if kinds.Meta and value == kinds.Meta then
        return "Meta"
    end
    return nil
end

local function PlayerZone()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetMapInfo then
        return nil
    end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    mapID = ok and WBF.Format.AsNumber(mapID) or nil
    if not mapID then
        return nil
    end
    local okInfo, info = pcall(C_Map.GetMapInfo, mapID)
    if okInfo and type(info) == "table" then
        return WBF.Format.PlainString(info.name)
    end
    return nil
end

local function QuestTitle(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local title = WBF.Format.PlainString(WBF.Format.SafeCall(C_QuestLog.GetTitleForQuestID, questID))
        if title then
            return title
        end
    end
    return "Quest " .. tostring(questID)
end

local function PlaceholderTitle(title, questID)
    return title == ("Quest " .. tostring(questID))
end

function WBF.Quests.CurseSurgeInfo(questID)
    questID = WBF.Format.AsNumber(questID)
    if not questID then
        return nil
    end
    return CURSE_SURGE_QUEST[questID]
end

function WBF.Quests.IsCurseSurgeQuest(questID)
    return WBF.Quests.CurseSurgeInfo(questID) ~= nil
end

function WBF.Quests.EffectiveType(event)
    if type(event) ~= "table" then
        return nil
    end
    local meta = type(event.meta) == "table" and event.meta or nil
    local questID = meta and WBF.Format.AsNumber(meta.questID)
    if WBF.Quests.IsCurseSurgeQuest(questID) or (meta and meta.worldEvent == "curseSurge") then
        return WBF.EventType.WorldEvent
    end
    if meta and meta.worldEvent and meta.worldEvent ~= "" then
        return WBF.EventType.WorldEvent
    end
    return event.eventType
end

function WBF.Quests.IsCurseSurgeEvent(event)
    if WBF.Quests.EffectiveType(event) ~= WBF.EventType.WorldEvent then
        return false
    end
    local meta = type(event.meta) == "table" and event.meta or nil
    if meta and meta.worldEvent == "curseSurge" then
        return true
    end
    local questID = meta and WBF.Format.AsNumber(meta.questID)
    return WBF.Quests.IsCurseSurgeQuest(questID)
end

local function PoiName(areaPoiID)
    if not areaPoiID or not C_AreaPoiInfo or not C_AreaPoiInfo.GetAreaPOIInfo then
        return nil
    end
    local maps = {}
    if C_EventScheduler and C_EventScheduler.GetEventUiMapID then
        local mapID = WBF.Format.AsNumber(WBF.Format.SafeCall(C_EventScheduler.GetEventUiMapID, areaPoiID))
        if mapID then
            maps[#maps + 1] = mapID
        end
    end
    maps[#maps + 1] = COILED_ISLE
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = WBF.Format.AsNumber(WBF.Format.SafeCall(C_Map.GetBestMapForUnit, "player"))
        if mapID then
            maps[#maps + 1] = mapID
        end
    end
    for index = 1, #maps do
        local info = WBF.Format.SafeCall(C_AreaPoiInfo.GetAreaPOIInfo, maps[index], areaPoiID)
        if type(info) == "table" then
            local name = WBF.Format.PlainString(info.name)
            if name then
                return name
            end
        end
    end
    return nil
end

local function ConsiderScheduled(raw, now, best)
    if type(raw) ~= "table" then
        return best
    end
    local areaPoiID = WBF.Format.AsNumber(raw.areaPoiID)
    local known = areaPoiID and CURSE_SURGE_POI[areaPoiID]
    if not known then
        return best
    end
    local startAt = WBF.Format.AsNumber(raw.startTime)
    local endAt = WBF.Format.AsNumber(raw.endTime)
    if startAt and now < startAt then
        return best
    end
    if endAt and now >= endAt then
        return best
    end
    if not best or (startAt and (not best.startAt or startAt > best.startAt)) then
        return { info = known, startAt = startAt }
    end
    return best
end

-- The surge that is up right now, from the event scheduler. Nil when the
-- client has no schedule loaded. The quest id still identifies a Curse Surge.
local function ActiveCurseSurge()
    if not C_EventScheduler then
        return nil
    end
    local now = WBF.Time.Now()
    local best = nil
    if C_EventScheduler.GetOngoingEvents then
        local ongoing = WBF.Format.SafeCall(C_EventScheduler.GetOngoingEvents)
        if type(ongoing) == "table" then
            for index = 1, #ongoing do
                best = ConsiderScheduled(ongoing[index], now, best)
            end
        end
    end
    if not best and C_EventScheduler.GetScheduledEvents then
        local scheduled = WBF.Format.SafeCall(C_EventScheduler.GetScheduledEvents)
        if type(scheduled) == "table" then
            for index = 1, #scheduled do
                best = ConsiderScheduled(scheduled[index], now, best)
            end
        end
    end
    return best and best.info or nil
end

local function SurgeTitle(questID, info, questTitle, poiName)
    if poiName and poiName ~= "" then
        return poiName
    end
    local usable = questTitle and not PlaceholderTitle(questTitle, questID)
    if info and info.variant then
        if usable and questTitle ~= "Curse Surge" then
            return questTitle
        end
        return "Curse Surge: " .. info.variant
    end
    if usable then
        return questTitle
    end
    return "Curse Surge"
end

local function CompletedText(title)
    if not title or title == "" or title == "Curse Surge" then
        return "Curse Surge completed"
    end
    local variant = title:match("^Curse Surge:%s*(.+)$")
    if variant and variant ~= "" then
        return "Curse Surge completed: " .. variant
    end
    return "Curse Surge completed: " .. title
end

function WBF.Quests.ActivityText(event)
    local text = type(event) == "table" and type(event.text) == "string" and event.text or ""
    if text == "" and type(event) ~= "table" then
        return ""
    end
    local marker = "   —   "
    local markerAt = text:find(marker, 1, true)
    local body = text
    local suffix = ""
    if markerAt then
        body = text:sub(1, markerAt - 1)
        suffix = text:sub(markerAt)
    end
    if body:sub(1, #"Curse Surge completed") == "Curse Surge completed" or body:sub(1, #"World Event completed") == "World Event completed" then
        return text
    end
    if not WBF.Quests.IsCurseSurgeEvent(event) then
        return text
    end
    local meta = type(event.meta) == "table" and event.meta or nil
    local title = meta and WBF.Format.PlainString(meta.title) or nil
    if not title then
        title = body:match("^Quest completed:%s*(.+)$") or body:match("^World Quest completed:%s*(.+)$")
    end
    return CompletedText(title) .. suffix
end

local function CurrentGUID()
    if not WBF.Characters or not WBF.Characters.GetCurrent then
        return nil
    end
    local character = WBF.Characters.GetCurrent()
    if type(character) ~= "table" then
        return nil
    end
    return character.guid
end

-- A variant quest and the generic 96935 completion can both turn in for one
-- surge. Keep one record and prefer the variant. A later generic completion
-- on its own still counts, so phasing into another surge is not collapsed.
local function SurgeDecision(guid, specific)
    local now = WBF.Time.Now()
    if recentSurge and recentSurge.guid == guid and (now - recentSurge.at) <= SURGE_PAIR_SECONDS then
        if specific and not recentSurge.specific and recentSurge.event then
            recentSurge.at = now
            recentSurge.specific = true
            return "upgrade"
        end
        if not specific and recentSurge.specific then
            recentSurge.at = now
            return "skip"
        end
    end
    recentSurge = { at = now, guid = guid, specific = specific, event = nil }
    return "record"
end

local function RememberSurge(event)
    if recentSurge and event then
        recentSurge.event = event
    end
end

local function PublishSurge(partial, decision)
    if decision == "upgrade" and recentSurge and recentSurge.event then
        recentSurge.event.text = partial.text
        recentSurge.event.meta = partial.meta
        if WBF.Aggregator and WBF.Aggregator.MarkDirty then
            WBF.Aggregator.MarkDirty()
        end
        if WBF.UI and WBF.UI.RequestRefresh then
            WBF.UI.RequestRefresh()
        end
        return
    end
    RememberSurge(WBF.Events.Add(partial))
end

local function RecordCurseSurge(questID, info, title)
    local active = nil
    if info.generic then
        active = ActiveCurseSurge()
    end
    local variantInfo = active or (info.variant and info or nil)
    local poiName = variantInfo and variantInfo.areaPoiID and PoiName(variantInfo.areaPoiID) or nil
    local display = SurgeTitle(questID, variantInfo, title, poiName)
    local guid = CurrentGUID()
    local decision = SurgeDecision(guid, info.variant ~= nil)
    if decision == "skip" then
        return
    end
    PublishSurge({
        category = WBF.Category.Quest,
        eventType = WBF.EventType.WorldEvent,
        text = CompletedText(display),
        meta = {
            questID = questID,
            title = display,
            worldEvent = "curseSurge",
            questType = display ~= "Curse Surge" and "Curse Surge" or nil,
            variant = variantInfo and variantInfo.variant or nil,
            areaPoiID = variantInfo and variantInfo.areaPoiID or nil,
            zone = PlayerZone(),
            iconAtlas = "worldquest-tracker-questmarker",
        },
    }, decision)
end

function WBF.Quests.Register(bus)
    bus:On("QUEST_TURNED_IN", function(questID)
        questID = WBF.Format.AsNumber(questID)
        if not questID then
            return
        end
        if WBF.Prey and WBF.Prey.ObserveTurnIn and WBF.Prey.ObserveTurnIn(questID) then
            return
        end
        if WBF.Prey and WBF.Prey.Owns and WBF.Prey.Owns(questID) then
            return
        end
        local title = QuestTitle(questID)
        local surge = WBF.Quests.CurseSurgeInfo(questID)
        if surge then
            RecordCurseSurge(questID, surge, title)
            return
        end
        local playerFacing, reason = WBF.QuestVisibility.IsPlayerFacing(questID, title)
        if not playerFacing then
            WBF.Debug.Log("system quest", questID, reason, title)
            return
        end
        local world = IsWorldQuest(questID)
        local questType = world and nil or QuestType(questID)
        WBF.Events.Add({
            category = WBF.Category.Quest,
            eventType = world and WBF.EventType.WorldQuest or WBF.EventType.Quest,
            text = world and ("World Quest completed: " .. title) or ("Quest completed: " .. title),
            meta = {
                questID = questID,
                title = title,
                worldQuest = world,
                questType = questType,
                zone = PlayerZone(),
                iconAtlas = world and "worldquest-tracker-questmarker" or "QuestNormal",
            },
        })
    end)
end
