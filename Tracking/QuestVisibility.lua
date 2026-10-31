local _, WBF = ...

-- Quest turn-ins include scaffolding Blizzard uses to advance scenarios,
-- delves, world events, Timewalking, and other systems. Those quests are
-- still detected here, and they are kept out of activity history.
-- Curse Surge completions are an exception: Quests.lua records them as
-- public events before this filter can drop a hidden quest.
--
-- A quest is internal when any of these is true:
--   the quest log marks it internal-only
--   its tag is a hidden/system tag (Hidden Quest, Hidden NYI)
--   its title carries an authoring marker such as <DNT>, <NYI>, or [PH]
--
-- Nothing here is specific to a zone or a feature. isHidden is not used on
-- its own: world quests and bonus objectives are hidden in the quest log
-- and are still content the player completes.

WBF.QuestVisibility = {}

local internalIDs = {}
local tagChecked = {}

local SYSTEM_TAG_IDS = {
    [265] = true, -- Hidden Quest
    [291] = true, -- Hidden NYI
}

local TITLE_TOKENS = {
    "<DNT>", "[DNT]", "(DNT)", "{DNT}",
    "<NYI>", "[NYI]", "(NYI)", "{NYI}",
    "<PH>", "[PH]", "(PH)", "{PH}",
    "<UNUSED>", "[UNUSED]", "(UNUSED)",
    "<DEPRECATED>", "[DEPRECATED]", "(DEPRECATED)",
    "<INTERNAL>", "[INTERNAL]", "(INTERNAL)",
}

local TITLE_PREFIXES = {
    "^DNT[%s:%-]",
    "^NYI[%s:%-]",
    "^PH[%s:%-]",
    "^UNUSED[%s:%-]",
    "^DEPRECATED[%s:%-]",
    "^INTERNAL[%s:%-]",
    "^DO NOT TRANSLATE$",
    "^DO NOT TRANSLATE[%s]*[-:]",
    "^DO NOT USE$",
    "^DO NOT USE[%s]*[-:]",
}

local function AbsorbEnumTags()
    local tags = Enum and Enum.QuestTag
    if type(tags) ~= "table" then
        return
    end
    if tags.Hidden then
        SYSTEM_TAG_IDS[tags.Hidden] = true
    end
    if tags.HiddenNYI then
        SYSTEM_TAG_IDS[tags.HiddenNYI] = true
    end
end

local function Remember(questID, reason)
    questID = WBF.Format.AsNumber(questID)
    if questID and questID > 0 and not internalIDs[questID] then
        internalIDs[questID] = reason or "internal-only"
    end
end

local function HasInternalTitle(title)
    if type(title) ~= "string" or title == "" then
        return false
    end
    if issecretvalue and issecretvalue(title) then
        return false
    end
    local upper = title:upper()
    for index = 1, #TITLE_TOKENS do
        if upper:find(TITLE_TOKENS[index], 1, true) then
            return true
        end
    end
    for index = 1, #TITLE_PREFIXES do
        if upper:match(TITLE_PREFIXES[index]) then
            return true
        end
    end
    return false
end

local function IsSystemTag(tagID)
    tagID = WBF.Format.AsNumber(tagID)
    return tagID ~= nil and SYSTEM_TAG_IDS[tagID] == true
end

local function QuestTagID(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetQuestTagInfo then
        return nil
    end
    local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, questID)
    if not ok or tag == nil then
        return nil
    end
    if type(tag) == "table" then
        return WBF.Format.AsNumber(tag.tagID)
    end
    return WBF.Format.AsNumber(tag)
end

local function LogInfo(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetLogIndexForQuestID or not C_QuestLog.GetInfo then
        return nil
    end
    local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
    index = ok and WBF.Format.AsNumber(index) or nil
    if not index or index < 1 then
        return nil
    end
    local okInfo, info = pcall(C_QuestLog.GetInfo, index)
    if okInfo and type(info) == "table" then
        return info
    end
    return nil
end

local function Flag(info, field)
    if type(info) ~= "table" then
        return false
    end
    local value = info[field]
    if issecretvalue and issecretvalue(value) then
        return false
    end
    return value == true
end

local function ScanLog()
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not C_QuestLog.GetInfo then
        return
    end
    local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
    count = ok and WBF.Format.AsNumber(count) or nil
    if not count or count < 1 then
        return
    end
    for index = 1, count do
        local okInfo, info = pcall(C_QuestLog.GetInfo, index)
        if okInfo and type(info) == "table" and not Flag(info, "isHeader") then
            local questID = WBF.Format.AsNumber(info.questID)
            if questID and questID > 0 then
                if Flag(info, "isInternalOnly") then
                    Remember(questID, "internal-only")
                elseif HasInternalTitle(WBF.Format.PlainString(info.title)) then
                    Remember(questID, "title")
                elseif Flag(info, "isHidden") and not tagChecked[questID] then
                    -- Hidden in the log is not itself enough. It only means the
                    -- tag is worth reading while the quest is still present.
                    local tagID = QuestTagID(questID)
                    if tagID then
                        tagChecked[questID] = true
                        if IsSystemTag(tagID) then
                            Remember(questID, "hidden-tag:" .. tostring(tagID))
                        end
                    end
                end
            end
        end
    end
end

-- True when this quest should appear as something the player completed.
-- The second return is a short reason when it should not.
function WBF.QuestVisibility.IsPlayerFacing(questID, title)
    questID = WBF.Format.AsNumber(questID)
    title = WBF.Format.PlainString(title)
    local info = LogInfo(questID)
    local logTitle = info and WBF.Format.PlainString(info.title) or nil
    local reason = nil

    if Flag(info, "isInternalOnly") then
        Remember(questID, "internal-only")
        reason = "internal-only"
    end

    local tagID = QuestTagID(questID)
    if IsSystemTag(tagID) then
        Remember(questID, "hidden-tag:" .. tostring(tagID))
        reason = reason or ("hidden-tag:" .. tostring(tagID))
    end

    if HasInternalTitle(title) or HasInternalTitle(logTitle) then
        Remember(questID, "title")
        reason = reason or "title"
    end

    if not reason and questID and internalIDs[questID] then
        reason = internalIDs[questID]
    end

    if reason then
        return false, reason
    end
    return true
end

local function StoredLooksInternal(event)
    local meta = type(event.meta) == "table" and event.meta or nil
    if HasInternalTitle(meta and meta.title) or HasInternalTitle(event.text) then
        return true
    end
    if type(event.text) ~= "string" or (issecretvalue and issecretvalue(event.text)) then
        return false
    end
    local stripped = event.text:gsub("^World Quest completed:%s*", "")
    stripped = stripped:gsub("^Quest completed:%s*", "")
    return stripped ~= event.text and HasInternalTitle(stripped)
end

-- Saved quest rows from before this filter still carry authoring titles.
-- Counts and activity lists skip those, and anything classified this session.
-- Curse Surge completions are public events recorded on purpose, including
-- rows saved earlier as ordinary quests.
function WBF.QuestVisibility.IsPlayerActivity(event)
    if type(event) ~= "table" then
        return false
    end
    local meta = type(event.meta) == "table" and event.meta or nil
    local questID = meta and WBF.Format.AsNumber(meta.questID)
    if WBF.Quests and WBF.Quests.IsCurseSurgeQuest and WBF.Quests.IsCurseSurgeQuest(questID) then
        return true
    end
    if meta and meta.worldEvent == "curseSurge" then
        return true
    end
    local kind = event.eventType
    if kind ~= WBF.EventType.Quest and kind ~= WBF.EventType.WorldQuest then
        return true
    end
    if questID and internalIDs[questID] then
        return false
    end
    if StoredLooksInternal(event) then
        return false
    end
    return true
end

-- QUEST_LOG_UPDATE fires many times a second while questing. Scan straight
-- away, then at most once per interval, with one trailing scan so the last
-- update in a burst is still read.
local SCAN_INTERVAL = 1
local lastScanAt = nil
local trailingQueued = false

local function ThrottledScan()
    local clock = type(GetTime) == "function" and GetTime() or nil
    if not clock or not (C_Timer and C_Timer.After) then
        ScanLog()
        return
    end
    if not lastScanAt or (clock - lastScanAt) >= SCAN_INTERVAL then
        lastScanAt = clock
        ScanLog()
        return
    end
    if trailingQueued then
        return
    end
    trailingQueued = true
    C_Timer.After(SCAN_INTERVAL - (clock - lastScanAt), function()
        trailingQueued = false
        lastScanAt = type(GetTime) == "function" and GetTime() or nil
        ScanLog()
    end)
end

function WBF.QuestVisibility.Register(bus)
    AbsorbEnumTags()
    bus:On("QUEST_LOG_UPDATE", function()
        ThrottledScan()
    end)
    ScanLog()
end

AbsorbEnumTags()
