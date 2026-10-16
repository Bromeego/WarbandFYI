local _, WBF = ...

WBF.Prey = {}

-- Prey hunts are the quest C_QuestLog.GetActivePreyQuest reports.
-- Difficulty is taken only when that quest id is an achievement criterion
-- on a known Prey mode achievement. Stages stay as the quest objective
-- text Blizzard returns. They are never turned into a percent.
-- Journey progress is the change in the Preyhunter currency observed
-- after the hunt turns in. A quest tooltip amount is not used, because
-- the weekly award can be smaller than the amount the quest displays.
-- Completing a hunt must be saved before a new hunt replaces it. Turn-in,
-- a Prey quest title, and a short grace after the quest leaves the log
-- are all completion signals. The same hunt is written once.

local DIFFICULTIES = {
    { id = 42701, label = "Normal" },
    { id = 42702, label = "Hard" },
    { id = 42703, label = "Nightmare" },
    { id = 63451, label = "Nightmare" },
    { id = 63452, label = "Nightmare" },
}

local active
local retained = {}
local recentTurnIn = {}
local finishedQuestAt = {}
local announcedTurnIn = {}
local finishedKeys = {}
local difficultyByQuest = {}
local journeyCurrencyID
local journeyCurrencyName
local UNKNOWN = {}

local DIFFICULTY_LABEL = {
    Normal = true,
    Hard = true,
    Nightmare = true,
}

local function ActiveQuestID()
    if not C_QuestLog or not C_QuestLog.GetActivePreyQuest then
        return nil
    end
    local ok, questID = pcall(C_QuestLog.GetActivePreyQuest)
    if not ok then
        return nil
    end
    return WBF.Format.AsNumber(questID)
end

local function QuestTitle(questID)
    if not C_QuestLog or not C_QuestLog.GetTitleForQuestID then
        return nil
    end
    local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
    if not ok then
        return nil
    end
    if type(title) == "table" then
        title = title.title
    end
    return WBF.Format.PlainString(title)
end

local function IsJourneyName(name)
    if not name then
        return false
    end
    if name:find("Preyhunter", 1, true) then
        return true
    end
    return name:find("Prey", 1, true) ~= nil and name:find("Journey", 1, true) ~= nil
end

local function ConsiderJourney(id, name, quantity)
    if not IsJourneyName(name) or not quantity then
        return false
    end
    if id then
        journeyCurrencyID = id
    end
    journeyCurrencyName = name
    return true
end

local function ReadJourney()
    if journeyCurrencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, journeyCurrencyID)
        if ok and type(info) == "table" then
            local quantity = WBF.Format.AsNumber(info.quantity)
            local name = WBF.Format.PlainString(info.name) or journeyCurrencyName
            if quantity and name then
                return quantity, name
            end
        end
    end

    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyListSize or not C_CurrencyInfo.GetCurrencyListInfo then
        return nil, nil
    end
    local okSize, size = pcall(C_CurrencyInfo.GetCurrencyListSize)
    size = okSize and WBF.Format.AsNumber(size) or nil
    if not size or size < 1 then
        return nil, nil
    end

    for index = 1, size do
        local okInfo, info, _, _, _, _, quantity = pcall(C_CurrencyInfo.GetCurrencyListInfo, index)
        if okInfo then
            local name, amount, id, header
            if type(info) == "table" then
                header = info.isHeader
                name = WBF.Format.PlainString(info.name)
                amount = WBF.Format.AsNumber(info.quantity)
                id = WBF.Format.AsNumber(info.currencyID or info.currencyTypesID)
            elseif type(info) == "string" then
                name = WBF.Format.PlainString(info)
                amount = WBF.Format.AsNumber(quantity)
            end
            if not id and C_CurrencyInfo.GetCurrencyListLink then
                local okLink, link = pcall(C_CurrencyInfo.GetCurrencyListLink, index)
                if okLink and type(link) == "string" then
                    id = tonumber(link:match("currency:(%d+)"))
                end
            end
            if not header and ConsiderJourney(id, name, amount) then
                return amount, name
            end
        end
    end
    return nil, nil
end

local function DifficultyFor(questID)
    local cached = difficultyByQuest[questID]
    if cached == UNKNOWN then
        return nil
    end
    if cached then
        return cached
    end
    if not GetAchievementNumCriteria or not GetAchievementCriteriaInfo then
        difficultyByQuest[questID] = UNKNOWN
        return nil
    end

    for index = 1, #DIFFICULTIES do
        local mode = DIFFICULTIES[index]
        local okNum, num = pcall(GetAchievementNumCriteria, mode.id)
        num = okNum and WBF.Format.AsNumber(num) or 0
        if num and num > 0 then
            for criteriaIndex = 1, num do
                local okInfo, _, _, _, _, _, _, _, assetID = pcall(GetAchievementCriteriaInfo, mode.id, criteriaIndex)
                if okInfo and WBF.Format.AsNumber(assetID) == questID then
                    difficultyByQuest[questID] = mode.label
                    return mode.label
                end
            end
        end
    end

    difficultyByQuest[questID] = UNKNOWN
    return nil
end

local function ObjectiveText(questID)
    if not C_QuestLog or not C_QuestLog.GetQuestObjectives then
        return nil
    end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table" then
        return nil
    end
    local parts = {}
    for index = 1, #objectives do
        local objective = objectives[index]
        local text = type(objective) == "table" and WBF.Format.PlainString(objective.text) or nil
        if text then
            parts[#parts + 1] = text
        end
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, " ")
end

local function UpdateObserved(hunt)
    local title = QuestTitle(hunt.questID)
    if title then
        hunt.title = title
    end
    if not hunt.difficulty then
        hunt.difficulty = DifficultyFor(hunt.questID)
    end
    local objective = ObjectiveText(hunt.questID)
    if objective then
        hunt.objective = objective
    end
    if hunt.journeyQuantity == nil then
        local quantity, name = ReadJourney()
        if quantity then
            hunt.journeyQuantity = quantity
            hunt.journeyName = name
        end
    end
end

local function PreyLog(message)
    print("|cffd4af37[WarbandFYI]|r " .. message)
end

local function SplitTarget(title)
    if not title or title == "" then
        return nil, nil
    end
    title = title:gsub("^Quest completed:%s*", "")
    title = title:gsub("^Prey hunt started:%s*", "")
    title = title:gsub("^Prey hunt completed:%s*", "")
    title = title:gsub("^Prey:%s*", "")
    title = title:gsub("^%s+", ""):gsub("%s+$", "")
    local name, difficulty = title:match("^(.-)%s*%(([^%)]+)%)%s*$")
    if name and DIFFICULTY_LABEL[difficulty] then
        name = name:gsub("%s+$", "")
        if name == "" then
            return nil, difficulty
        end
        return name, difficulty
    end
    if title == "" then
        return nil, nil
    end
    return title, nil
end

local function SameTarget(left, right)
    local a = SplitTarget(left)
    local b = SplitTarget(right)
    if not a or not b then
        return false
    end
    return a:lower() == b:lower()
end

local function Display(title, difficulty)
    local name, parsed = SplitTarget(title)
    name = name or "Prey hunt"
    difficulty = difficulty or parsed
    if difficulty and DIFFICULTY_LABEL[difficulty] then
        return name .. " (" .. difficulty .. ")"
    end
    return name
end

local function DisplayHunt(hunt)
    return Display(hunt and hunt.title, hunt and hunt.difficulty)
end

local function IsPreyQuestTitle(title)
    if not title or title:sub(1, 5) ~= "Prey:" then
        return false
    end
    local _, difficulty = SplitTarget(title)
    return difficulty ~= nil
end

local function Remember(hunt)
    if not hunt then
        return
    end
    for index = 1, #retained do
        if retained[index] == hunt then
            return
        end
    end
    retained[#retained + 1] = hunt
end

local function Forget(hunt)
    for index = #retained, 1, -1 do
        if retained[index] == hunt then
            table.remove(retained, index)
        end
    end
end

local function FindHunt(questID, includeAbandoned)
    if active and active.questID == questID and not active.finished then
        if includeAbandoned or not active.abandoned then
            return active
        end
    end
    for index = #retained, 1, -1 do
        local hunt = retained[index]
        if hunt.questID == questID and not hunt.finished then
            if includeAbandoned or not hunt.abandoned then
                return hunt
            end
        end
    end
    return nil
end

local function FindHuntByTitle(title)
    if not title then
        return nil
    end
    if active and not active.finished and not active.abandoned and SameTarget(active.title, title) then
        return active
    end
    for index = #retained, 1, -1 do
        local hunt = retained[index]
        if not hunt.finished and not hunt.abandoned and SameTarget(hunt.title, title) then
            return hunt
        end
    end
    if active and not active.finished and SameTarget(active.title, title) then
        return active
    end
    for index = #retained, 1, -1 do
        local hunt = retained[index]
        if not hunt.finished and SameTarget(hunt.title, title) then
            return hunt
        end
    end
    return nil
end

local function CompletionKey(hunt, completedAt)
    local started = hunt.startedAt or completedAt or 0
    return tostring(hunt.questID or "none") .. ":" .. tostring(started)
end

local function WriteStart(hunt)
    local name, parsed = SplitTarget(hunt.title)
    hunt.title = name or hunt.title or "Prey hunt"
    hunt.difficulty = hunt.difficulty or parsed
    local label = DisplayHunt(hunt)
    hunt.startEvent = WBF.Events.Add({
        category = WBF.Category.Prey,
        eventType = WBF.EventType.Prey,
        at = hunt.startedAt,
        guid = hunt.guid,
        sessionId = hunt.sessionId,
        text = "Prey hunt started: " .. label,
        meta = {
            questID = hunt.questID,
            title = hunt.title,
            difficulty = hunt.difficulty,
            completed = false,
            objective = hunt.objective,
        },
    })
    if hunt.startEvent then
        PreyLog("Prey started: " .. label)
    end
end

local function CurrentIdentity()
    local character = WBF.Characters.GetCurrent()
    local session = WBF.Sessions.GetActive and WBF.Sessions.GetActive() or nil
    return character and character.guid or nil, session and session.id or nil
end

local function ReleaseActive()
    local hunt = active
    if not hunt then
        return
    end
    active = nil
    if hunt.finished then
        return
    end
    Remember(hunt)
    if WBF.Debug and WBF.Debug.Log then
        WBF.Debug.Log("Prey", "retaining unresolved hunt", DisplayHunt(hunt))
    end
end

local function Begin(questID, fromAccept)
    if active and active.questID == questID and not active.finished and not active.abandoned then
        if fromAccept and not active.fromAccept then
            active.fromAccept = true
            active.startedAt = WBF.Time.Now()
        end
        UpdateObserved(active)
        if fromAccept and not active.startWritten then
            active.startWritten = true
            WriteStart(active)
        end
        return
    end

    if active then
        ReleaseActive()
    end

    local guid, sessionId = CurrentIdentity()
    active = {
        questID = questID,
        fromAccept = fromAccept and true or false,
        startedAt = fromAccept and WBF.Time.Now() or nil,
        startWritten = false,
        guid = guid,
        sessionId = sessionId,
    }
    UpdateObserved(active)
    if fromAccept then
        active.startWritten = true
        WriteStart(active)
    end
end

local function ScheduleJourney(event, before, fallbackName)
    if not event or not before or not C_Timer or not C_Timer.After then
        return
    end
    C_Timer.After(0.6, function()
        local after, name = ReadJourney()
        if after and after > before then
            event.meta.journey = after - before
            event.meta.journeyName = name or fallbackName
            if WBF.UI and WBF.UI.RequestRefresh then
                WBF.UI.RequestRefresh()
            end
        end
    end)
end

local function LinkStoredStart(hunt, completedAt)
    if hunt.startWritten or not WBF.Database.IsReady() then
        return
    end
    local db = WBF.Database.Get()
    local events = db and db.events
    if type(events) ~= "table" then
        return
    end
    local best
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.Prey and not meta.completed and not meta.abandoned and event.at and event.at <= completedAt then
            local sameQuest = hunt.questID and meta.questID and meta.questID == hunt.questID
            local sameName = SameTarget(hunt.title, meta.title or event.text)
            local sameCharacter = not hunt.guid or not event.guid or hunt.guid == event.guid
            if sameCharacter and (sameQuest or sameName) and (not best or event.at >= best.at) then
                best = event
            end
        end
    end
    if not best then
        return
    end
    local bestMeta = best.meta or {}
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.Prey and meta.completed and meta.startedAt == best.at then
            local sameQuest = bestMeta.questID and meta.questID and meta.questID == bestMeta.questID
            local sameName = SameTarget(meta.title or event.text, bestMeta.title or best.text)
            if sameQuest or sameName then
                return
            end
        end
    end
    hunt.startWritten = true
    hunt.startedAt = best.at
    hunt.startEvent = best
    hunt.guid = hunt.guid or best.guid
    hunt.sessionId = hunt.sessionId or best.sessionId
    hunt.objective = hunt.objective or bestMeta.objective
    hunt.difficulty = hunt.difficulty or bestMeta.difficulty
    if not hunt.title then
        hunt.title = bestMeta.title
    end
    if best.meta and hunt.questID and not best.meta.questID then
        best.meta.questID = hunt.questID
    end
end

local function CompleteHunt(hunt, completedAt, live)
    if not hunt or hunt.finished then
        return nil
    end
    if not hunt.startWritten then
        LinkStoredStart(hunt, completedAt or WBF.Time.Now())
    end
    local key = CompletionKey(hunt, completedAt)
    if finishedKeys[key] then
        hunt.finished = true
        if active == hunt then
            active = nil
        end
        Forget(hunt)
        return nil
    end

    UpdateObserved(hunt)
    local name, parsed = SplitTarget(hunt.title)
    hunt.title = name or hunt.title or "Prey hunt"
    hunt.difficulty = hunt.difficulty or parsed
    local startedAt = hunt.startWritten and hunt.startedAt or nil
    local now = completedAt or WBF.Time.Now()
    local duration
    if startedAt and now >= startedAt then
        duration = math.floor(now - startedAt)
    end
    local label = DisplayHunt(hunt)
    if hunt.startEvent and hunt.startEvent.meta then
        hunt.startEvent.meta.abandoned = nil
        if hunt.questID and not hunt.startEvent.meta.questID then
            hunt.startEvent.meta.questID = hunt.questID
        end
    end

    PreyLog("Reconciling active hunt as completed")
    finishedKeys[key] = true
    hunt.finished = true
    if hunt.questID then
        finishedQuestAt[hunt.questID] = WBF.Time.Now()
    end

    local event = WBF.Events.Add({
        category = WBF.Category.Prey,
        eventType = WBF.EventType.Prey,
        at = now,
        guid = hunt.guid,
        sessionId = hunt.sessionId,
        dedupeKey = "prey-complete:" .. key,
        text = "Prey hunt completed: " .. label,
        meta = {
            questID = hunt.questID,
            title = hunt.title,
            difficulty = hunt.difficulty,
            completed = true,
            startedAt = startedAt,
            duration = duration,
            objective = hunt.objective,
            journeyName = hunt.journeyName,
        },
    })
    hunt.completionEvent = event
    if active == hunt then
        active = nil
    end
    Forget(hunt)
    if event then
        PreyLog("Prey completed: " .. label)
        if live then
            ScheduleJourney(event, hunt.journeyQuantity, hunt.journeyName)
        end
    end
    return event
end

local function ClaimedRecently(questID)
    local now = WBF.Time.Now()
    local seen = recentTurnIn[questID]
    if seen and (now - seen) < 5 then
        return true
    end
    local finished = finishedQuestAt[questID]
    return finished ~= nil and (now - finished) < 5
end

function WBF.Prey.ObserveTurnIn(questID)
    questID = WBF.Format.AsNumber(questID)
    if not questID then
        return false
    end
    if ClaimedRecently(questID) and finishedQuestAt[questID] and (WBF.Time.Now() - finishedQuestAt[questID]) < 5 then
        recentTurnIn[questID] = WBF.Time.Now()
        return true
    end

    local title = QuestTitle(questID)
    local hunt = FindHunt(questID, true) or FindHuntByTitle(title)
    local prefix = title and title:sub(1, 5) == "Prey:"
    local known = hunt ~= nil or ActiveQuestID() == questID or IsPreyQuestTitle(title) or (prefix and DifficultyFor(questID) ~= nil)
    if not known then
        return false
    end

    local announced = announcedTurnIn[questID]
    if not announced or (WBF.Time.Now() - announced) > 5 then
        announcedTurnIn[questID] = WBF.Time.Now()
        PreyLog("Prey quest completed: " .. questID)
    end
    recentTurnIn[questID] = WBF.Time.Now()

    if not hunt then
        local guid, sessionId = CurrentIdentity()
        local name, parsed = SplitTarget(title)
        hunt = {
            questID = questID,
            title = name or title,
            difficulty = DifficultyFor(questID) or parsed,
            fromAccept = false,
            startWritten = false,
            guid = guid,
            sessionId = sessionId,
        }
    elseif hunt.abandoned and hunt.startEvent and hunt.startEvent.meta then
        hunt.startEvent.meta.abandoned = nil
        hunt.abandoned = nil
    end
    if hunt.questID ~= questID then
        hunt.questID = hunt.questID or questID
    end
    CompleteHunt(hunt, WBF.Time.Now(), true)
    return true
end

function WBF.Prey.Owns(questID)
    questID = WBF.Format.AsNumber(questID)
    if not questID then
        return false
    end
    if FindHunt(questID, false) then
        return true
    end
    return ClaimedRecently(questID)
end

local function Abandon(hunt)
    if not hunt or hunt.finished or hunt.abandoned then
        return
    end
    hunt.abandoned = true
    if hunt.startEvent and hunt.startEvent.meta then
        hunt.startEvent.meta.abandoned = true
    end
    if active == hunt then
        active = nil
    end
    PreyLog("Prey abandoned: " .. DisplayHunt(hunt))
    if WBF.UI and WBF.UI.RequestRefresh then
        WBF.UI.RequestRefresh()
    end
end

local function LooksLikePreyQuest(event)
    local meta = event.meta or {}
    local title = meta.title or ""
    local text = event.text or ""
    if title:sub(1, 5) == "Prey:" then
        return true
    end
    return text:sub(1, 22) == "Quest completed: Prey:"
end

local function AlreadyCompleted(events, startEvent)
    local startMeta = startEvent.meta or {}
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.Prey and meta.completed then
            local sameStart = meta.startedAt and startEvent.at and meta.startedAt == startEvent.at
            local sameQuest = startMeta.questID and meta.questID and meta.questID == startMeta.questID
            local sameName = SameTarget(meta.title or event.text, startMeta.title or startEvent.text)
            if sameStart and (sameQuest or sameName) then
                return true
            end
        end
    end
    return false
end

local function InsertHistorical(partial)
    if partial.dedupeKey and WBF.Database.HasDedupe(partial.dedupeKey) then
        return nil
    end
    local db = WBF.Database.Get()
    local event = {
        id = WBF.Database.AllocEventId(),
        at = partial.at,
        sessionId = partial.sessionId,
        guid = partial.guid,
        category = partial.category,
        eventType = partial.eventType,
        text = partial.text or "",
        meta = partial.meta or {},
    }
    local placed = false
    for index = 1, #db.events do
        local at = db.events[index].at or 0
        if event.at < at then
            table.insert(db.events, index, event)
            placed = true
            break
        end
    end
    if not placed then
        db.events[#db.events + 1] = event
    end
    if partial.dedupeKey then
        WBF.Database.MarkDedupe(partial.dedupeKey)
    end
    return event
end

-- Recover a completed hunt only when a stored start and a stored
-- "Prey:" quest completion name the same target. Nothing else is inferred.
local function ReconcileStored()
    if not WBF.Database.IsReady() then
        return
    end
    local db = WBF.Database.Get()
    local events = db.events
    if type(events) ~= "table" then
        return
    end

    local starts = {}
    local quests = {}
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if event.eventType == WBF.EventType.Prey and not meta.completed then
            starts[#starts + 1] = event
        elseif event.eventType == WBF.EventType.Quest and LooksLikePreyQuest(event) then
            quests[#quests + 1] = event
        end
    end

    local used = {}
    for questIndex = 1, #quests do
        local questEvent = quests[questIndex]
        local questMeta = questEvent.meta or {}
        local best
        local bestAt = -1
        for startIndex = 1, #starts do
            local startEvent = starts[startIndex]
            if not used[startEvent] and startEvent.at and questEvent.at and startEvent.at <= questEvent.at then
                local startMeta = startEvent.meta or {}
                local sameQuest = questMeta.questID and startMeta.questID and questMeta.questID == startMeta.questID
                local sameName = SameTarget(questMeta.title or questEvent.text, startMeta.title or startEvent.text)
                local sameCharacter = not questEvent.guid or not startEvent.guid or questEvent.guid == startEvent.guid
                if sameCharacter and (sameQuest or sameName) and startEvent.at >= bestAt then
                    best = startEvent
                    bestAt = startEvent.at
                end
            end
        end
        if best then
            used[best] = true
            questMeta.preyHunt = true
            questEvent.meta = questMeta
            if not AlreadyCompleted(events, best) then
                local startMeta = best.meta or {}
                local title = startMeta.title or questMeta.title
                local name, parsed = SplitTarget(title)
                local difficulty = startMeta.difficulty or parsed
                local _, questDifficulty = SplitTarget(questMeta.title or questEvent.text)
                difficulty = difficulty or questDifficulty
                local label = Display(name or title, difficulty)
                local duration
                if questEvent.at >= best.at then
                    duration = math.floor(questEvent.at - best.at)
                end
                local questID = startMeta.questID or questMeta.questID
                if best.meta and questID and not best.meta.questID then
                    best.meta.questID = questID
                end
                local key = tostring(questID or "none") .. ":" .. tostring(best.at)
                if best.meta then
                    best.meta.abandoned = nil
                end
                local event = InsertHistorical({
                    at = questEvent.at,
                    sessionId = best.sessionId or questEvent.sessionId,
                    guid = best.guid or questEvent.guid,
                    category = WBF.Category.Prey,
                    eventType = WBF.EventType.Prey,
                    dedupeKey = "prey-complete:" .. key,
                    text = "Prey hunt completed: " .. label,
                    meta = {
                        questID = questID,
                        title = name or title,
                        difficulty = difficulty,
                        completed = true,
                        startedAt = best.at,
                        duration = duration,
                        objective = startMeta.objective,
                        reconciled = true,
                    },
                })
                if event then
                    finishedKeys[key] = true
                    PreyLog("Reconciling active hunt as completed")
                    PreyLog("Prey completed: " .. label)
                end
            end
        end
    end
end

local questLogSeen = false
local staleAllowed = false
local staleClosed = false
local staleDeferrals = 0
local staleRetryPending = false
local STALE_RETRY_DELAYS = { 2, 2, 3 }

local function PreyQuestState()
    if not C_QuestLog or not C_QuestLog.GetActivePreyQuest then
        return nil, false
    end
    local ok, questID = pcall(C_QuestLog.GetActivePreyQuest)
    if not ok or WBF.Format.IsSecret(questID) then
        return nil, false
    end
    return WBF.Format.AsNumber(questID), true
end

local function QuestLogCount()
    if not questLogSeen or not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then
        return nil
    end
    return WBF.Format.AsNumber(WBF.Format.SafeCall(C_QuestLog.GetNumQuestLogEntries))
end

-- nil means the quest log cannot prove the hunt either way.
-- true means it is still the active hunt. false means it is not.
local function HuntStillActive(event, activeID)
    local meta = event.meta or {}
    if activeID and meta.questID and meta.questID == activeID then
        return true
    end
    if activeID and not meta.questID and SameTarget(QuestTitle(activeID), meta.title or event.text) then
        return true
    end
    if meta.questID and C_QuestLog and C_QuestLog.IsOnQuest then
        local onQuest = WBF.Format.SafeBoolean(C_QuestLog.IsOnQuest, meta.questID)
        if onQuest == nil then
            return nil
        end
        return onQuest
    end
    if activeID then
        return false
    end
    local count = QuestLogCount()
    if count == nil or count <= 0 then
        return nil
    end
    return false
end

local CloseStaleHunts

local function ScheduleStaleRetry()
    if staleClosed or staleRetryPending or not C_Timer or not C_Timer.After then
        return
    end
    if staleDeferrals >= #STALE_RETRY_DELAYS then
        return
    end
    staleDeferrals = staleDeferrals + 1
    local delay = STALE_RETRY_DELAYS[staleDeferrals]
    staleRetryPending = true
    C_Timer.After(delay, function()
        staleRetryPending = false
        CloseStaleHunts()
    end)
end

CloseStaleHunts = function()
    if staleClosed or not staleAllowed or not WBF.Database.IsReady() then
        return
    end
    local count = QuestLogCount()
    local activeID, ready = PreyQuestState()
    if count == nil or not ready or (count <= 0 and activeID == nil) then
        ScheduleStaleRetry()
        return
    end
    local db = WBF.Database.Get()
    local events = db and db.events
    if type(events) ~= "table" then
        staleClosed = true
        return
    end
    local changed = false
    local unknown = false
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta
        if type(meta) ~= "table" then
            meta = {}
            event.meta = meta
        end
        if event.eventType == WBF.EventType.Prey and not meta.completed and not meta.abandoned and not meta.resolved then
            local key = tostring(meta.questID or "none") .. ":" .. tostring(event.at or 0)
            if AlreadyCompleted(events, event) or (WBF.Database.HasDedupe and WBF.Database.HasDedupe("prey-complete:" .. key)) then
                meta.resolved = true
                changed = true
            else
                local still = HuntStillActive(event, activeID)
                if still == nil then
                    unknown = true
                elseif not still then
                    meta.abandoned = true
                    changed = true
                    if WBF.Debug and WBF.Debug.Log then
                        WBF.Debug.Log("Prey", "closed stale hunt", meta.title or event.text)
                    end
                end
            end
        end
    end
    if unknown then
        ScheduleStaleRetry()
    else
        staleClosed = true
    end
    if changed and WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
    if changed and WBF.UI and WBF.UI.RequestRefresh then
        WBF.UI.RequestRefresh()
    end
end

function WBF.Prey.AllowStaleClose()
    staleAllowed = true
    CloseStaleHunts()
end

function WBF.Prey.Refresh()
    CloseStaleHunts()
    local questID = ActiveQuestID()
    if not questID then
        return
    end
    if active and active.questID == questID and not active.finished and not active.abandoned then
        UpdateObserved(active)
        return
    end
    Begin(questID, false)
end

local function AcceptQuest(questID)
    local activeID = ActiveQuestID()
    if activeID and (not questID or questID == activeID) then
        Begin(activeID, true)
        return
    end
    if not questID or not C_Timer or not C_Timer.After then
        return
    end
    C_Timer.After(0.2, function()
        local id = ActiveQuestID()
        if id and (id == questID or not questID) then
            Begin(id, true)
        end
    end)
end

function WBF.Prey.Register(bus)
    ReconcileStored()

    bus:On("QUEST_ACCEPTED", function(questID)
        questID = WBF.Format.AsNumber(questID)
        local function Go()
            AcceptQuest(questID)
        end
        local incoming = questID or ActiveQuestID()
        local replacing = active and not active.finished and not active.abandoned and incoming and incoming ~= active.questID
        if replacing and C_Timer and C_Timer.After then
            C_Timer.After(0, Go)
            return
        end
        Go()
    end)

    bus:On("QUEST_TURNED_IN", function(questID)
        WBF.Prey.ObserveTurnIn(questID)
    end)

    bus:On("QUEST_REMOVED", function(questID)
        questID = WBF.Format.AsNumber(questID)
        local hunt = FindHunt(questID, false)
        if not hunt then
            return
        end
        hunt.removed = true
        local function Decide()
            if hunt.finished or hunt.abandoned then
                return
            end
            if ClaimedRecently(questID) then
                return
            end
            Abandon(hunt)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(2, Decide)
        else
            Decide()
        end
    end)

    bus:On("PLAYER_ENTERING_WORLD", function()
        WBF.Prey.Refresh()
    end)

    bus:On("QUEST_LOG_UPDATE", function()
        local firstSight = not questLogSeen
        questLogSeen = true
        if firstSight then
            staleDeferrals = 0
        end
        CloseStaleHunts()
    end)
end
