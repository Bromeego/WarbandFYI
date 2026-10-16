local _, WBF = ...

WBF.Aggregator = {}

local function Overlap(startA, endA, startB, endB)
    local startAt = math.max(startA, startB)
    local endAt = math.min(endA, endB)
    if endAt > startAt then
        return endAt - startAt
    end
    return 0
end

local function EmptyCounts()
    return {
        bosses = 0,
        quests = 0,
        worldQuests = 0,
        curseSurges = 0,
        worldEvents = 0,
        achievements = 0,
        raids = 0,
        dungeons = 0,
        mythicPlus = 0,
        highestKey = 0,
        mounts = 0,
        pets = 0,
        appearances = 0,
        decorAcquired = 0,
        newDecor = 0,
        duplicates = 0,
        houseXP = 0,
        gold = 0,
        reputation = 0,
        renown = 0,
        delves = 0,
        highestDelve = 0,
        professions = 0,
        crafts = 0,
        itemsCrafted = 0,
        concentrationSpent = 0,
        concentrationUsed = 0,
        knowledge = 0,
        knowledgeSpent = 0,
        recipes = 0,
        petBattles = 0,
        petBattlesStarted = 0,
        petWins = 0,
        petLosses = 0,
        petWild = 0,
        petTrainer = 0,
        petPvp = 0,
        petsCaptured = 0,
        petLevels = 0,
        petsLevel25 = 0,
        newPets = 0,
        prey = 0,
        preyStarted = 0,
        practiceRuns = 0,
        preyNormal = 0,
        preyHard = 0,
        preyNightmare = 0,
        journey = 0,
        rares = 0,
        fishing = 0,
        mining = 0,
        herbalism = 0,
        lumber = 0,
        skinning = 0,
    }
end

function WBF.Aggregator.EmptyCounts()
    return EmptyCounts()
end

local function EnsureBucket(bucket)
    local empty = EmptyCounts()
    for key, value in pairs(empty) do
        if bucket[key] == nil then
            bucket[key] = value
        end
    end
    return bucket
end

local MAX_COUNT = {
    highestKey = true,
    highestDelve = true,
    preyRank = true,
}

local AddCount

function WBF.Aggregator.CountEvent(bucket, event)
    if type(bucket) ~= "table" or type(event) ~= "table" or event.sample then
        return
    end
    if WBF.QuestVisibility and WBF.QuestVisibility.IsPlayerActivity and not WBF.QuestVisibility.IsPlayerActivity(event) then
        return
    end
    EnsureBucket(bucket)
    AddCount(bucket, event)
end

function WBF.Aggregator.MergeCounts(into, from)
    if type(into) ~= "table" or type(from) ~= "table" then
        return
    end
    EnsureBucket(into)
    for key, value in pairs(from) do
        if type(value) == "number" then
            if MAX_COUNT[key] then
                if value > (into[key] or 0) then
                    into[key] = value
                    if key == "preyRank" and from.preyHighest then
                        into.preyHighest = from.preyHighest
                    end
                end
            else
                into[key] = (into[key] or 0) + value
            end
        end
    end
end

AddCount = function(bucket, event)
    local kind = event.eventType
    if WBF.Quests and WBF.Quests.EffectiveType then
        kind = WBF.Quests.EffectiveType(event)
    end
    if kind == WBF.EventType.BossKill then
        bucket.bosses = bucket.bosses + 1
    elseif kind == WBF.EventType.Quest then
        if not (event.meta and event.meta.preyHunt) then
            bucket.quests = bucket.quests + 1
        end
    elseif kind == WBF.EventType.WorldQuest then
        bucket.worldQuests = bucket.worldQuests + 1
    elseif kind == WBF.EventType.WorldEvent then
        if WBF.Quests and WBF.Quests.IsCurseSurgeEvent and WBF.Quests.IsCurseSurgeEvent(event) then
            bucket.curseSurges = bucket.curseSurges + 1
        else
            bucket.worldEvents = bucket.worldEvents + 1
        end
    elseif kind == WBF.EventType.Achievement then
        bucket.achievements = bucket.achievements + 1
    elseif kind == WBF.EventType.InstanceEnter then
        local instanceType = event.meta and event.meta.instanceType
        local keystone = event.meta and event.meta.keystone
        if instanceType == "raid" then
            bucket.raids = bucket.raids + 1
        elseif instanceType == "party" and not keystone then
            bucket.dungeons = bucket.dungeons + 1
        end
    elseif kind == WBF.EventType.MythicPlus then
        if event.meta and event.meta.practiceRun then
            bucket.practiceRuns = bucket.practiceRuns + 1
        else
            bucket.mythicPlus = bucket.mythicPlus + 1
            local level = event.meta and event.meta.level or 0
            if type(level) == "number" and level > bucket.highestKey then
                bucket.highestKey = level
            end
        end
    elseif kind == WBF.EventType.Mount then
        bucket.mounts = bucket.mounts + 1
    elseif kind == WBF.EventType.Pet then
        bucket.pets = bucket.pets + 1
        local meta = event.meta or {}
        if meta.captured then
            bucket.petsCaptured = bucket.petsCaptured + 1
        else
            bucket.newPets = bucket.newPets + 1
        end
    elseif kind == WBF.EventType.PetBattle then
        if WBF.PetBattles and WBF.PetBattles.ApplyEvent then
            WBF.PetBattles.ApplyEvent(bucket, event)
        end
    elseif kind == WBF.EventType.Appearance then
        bucket.appearances = bucket.appearances + 1
    elseif kind == WBF.EventType.HousingDecor then
        bucket.newDecor = bucket.newDecor + 1
        bucket.decorAcquired = bucket.decorAcquired + 1
    elseif kind == WBF.EventType.HousingAcquire then
        local copies = event.meta and event.meta.count or 1
        if type(copies) ~= "number" or copies < 1 then
            copies = 1
        end
        bucket.decorAcquired = bucket.decorAcquired + copies
        bucket.duplicates = bucket.duplicates + copies
    elseif kind == WBF.EventType.HousingXP then
        local amount = event.delta or 0
        if type(amount) == "number" and amount > 0 then
            bucket.houseXP = bucket.houseXP + amount
        end
    elseif kind == WBF.EventType.Reputation then
        bucket.reputation = bucket.reputation + (event.delta or 0)
    elseif kind == WBF.EventType.Renown then
        local delta = event.delta
        if type(delta) ~= "number" and type(event.previous) == "number" and type(event.new) == "number" then
            delta = event.new - event.previous
        end
        if delta == nil or delta > 0 then
            bucket.renown = bucket.renown + 1
        end
    elseif kind == WBF.EventType.RareKill then
        bucket.rares = (bucket.rares or 0) + 1
    elseif kind == WBF.EventType.Delve then
        bucket.delves = bucket.delves + 1
        local tier = event.meta and event.meta.tier or 0
        if tier > bucket.highestDelve then
            bucket.highestDelve = tier
        end
    elseif kind == WBF.EventType.Profession then
        if WBF.Professions and WBF.Professions.ApplyEvent then
            WBF.Professions.ApplyEvent(bucket, event)
        else
            bucket.professions = bucket.professions + 1
        end
    elseif kind == (WBF.EventType.Craft or "craft") then
        if WBF.Crafts and WBF.Crafts.ApplyEvent then
            WBF.Crafts.ApplyEvent(bucket, event)
        end
    elseif kind == WBF.EventType.Resource then
        if WBF.ResourceBehaviour and WBF.ResourceBehaviour.ApplyResourceCounts then
            WBF.ResourceBehaviour.ApplyResourceCounts(bucket, event)
        end
    elseif kind == WBF.EventType.Prey then
        local meta = event.meta or {}
        if meta.completed then
            bucket.prey = bucket.prey + 1
            if meta.difficulty == "Normal" then
                bucket.preyNormal = bucket.preyNormal + 1
            elseif meta.difficulty == "Hard" then
                bucket.preyHard = bucket.preyHard + 1
            elseif meta.difficulty == "Nightmare" then
                bucket.preyNightmare = bucket.preyNightmare + 1
            end
            local rank = meta.difficulty == "Nightmare" and 3 or (meta.difficulty == "Hard" and 2 or (meta.difficulty == "Normal" and 1 or 0))
            if rank > (bucket.preyRank or 0) then
                bucket.preyRank = rank
                bucket.preyHighest = meta.difficulty
            end
            if meta.journey and meta.journey > 0 then
                bucket.journey = bucket.journey + meta.journey
            end
        end
    end
end

-- A start only counts as in progress when no completion names that same hunt.
local function RecountPreyStarted(bucket, events, guid)
    local completions = {}
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if (not guid or event.guid == guid) and event.eventType == WBF.EventType.Prey and meta.completed and meta.startedAt then
            completions[#completions + 1] = event
        end
    end
    local started = 0
    for index = 1, #events do
        local event = events[index]
        local meta = event.meta or {}
        if (not guid or event.guid == guid) and event.eventType == WBF.EventType.Prey and not meta.completed and not meta.abandoned and not meta.resolved then
            local matched = false
            for completeIndex = 1, #completions do
                local complete = completions[completeIndex]
                local completeMeta = complete.meta or {}
                local sameCharacter = not complete.guid or not event.guid or complete.guid == event.guid
                local sameId = not completeMeta.questID or not meta.questID or completeMeta.questID == meta.questID
                if sameCharacter and sameId and completeMeta.startedAt == event.at then
                    matched = true
                    break
                end
            end
            if not matched then
                started = started + 1
            end
        end
    end
    bucket.preyStarted = started
end

local function EnsureCharacter(map, guid)
    if not WBF.Characters.IsDiscovered(guid) then
        return nil
    end
    local row = map[guid]
    if row then
        return row
    end
    local stored = WBF.Characters.Get(guid)
    row = {
        guid = guid,
        name = stored and stored.name or "Unknown",
        realm = stored and stored.realm or "",
        classFile = stored and stored.classFile or nil,
        className = stored and stored.className or nil,
        specName = stored and stored.specName or nil,
        role = stored and stored.role or nil,
        playedSeconds = 0,
        levelStart = nil,
        levelEnd = nil,
        ilvlStart = nil,
        ilvlEnd = nil,
        counts = EmptyCounts(),
    }
    map[guid] = row
    return row
end

local function ConsiderBound(currentAt, currentValue, at, value, preferEarlier)
    if value == nil or not at then
        return currentAt, currentValue
    end
    if currentAt == nil then
        return at, value
    end
    if preferEarlier and at < currentAt then
        return at, value
    end
    if not preferEarlier and at >= currentAt then
        return at, value
    end
    return currentAt, currentValue
end

local function ReadProgress(db, guid, field, startAt, endAt, closed)
    local beforeAt, beforeValue
    local firstAt, firstValue
    local lastAt, lastValue
    local snapshots = db.snapshots

    for index = 1, #snapshots do
        local snapshot = snapshots[index]
        if snapshot.guid == guid and snapshot[field] ~= nil then
            if snapshot.at < startAt then
                if not beforeAt or snapshot.at >= beforeAt then
                    beforeAt = snapshot.at
                    beforeValue = snapshot[field]
                end
            elseif snapshot.at <= endAt then
                firstAt, firstValue = ConsiderBound(firstAt, firstValue, snapshot.at, snapshot[field], true)
                lastAt, lastValue = ConsiderBound(lastAt, lastValue, snapshot.at, snapshot[field], false)
            end
        end
    end

    local character = db.characters[guid]
    if character and character[field] ~= nil and character.updatedAt and character.updatedAt >= startAt and character.updatedAt <= endAt then
        lastAt, lastValue = ConsiderBound(lastAt, lastValue, character.updatedAt, character[field], false)
        if not firstAt and not beforeAt then
            firstAt = character.updatedAt
            firstValue = character[field]
        end
    end

    local startValue = beforeValue
    if startValue == nil then
        startValue = firstValue
    end
    if (not startAt or startAt <= 0) and not beforeAt and guid then
        local life = db.lifetime
        local stored = life and life.characters and life.characters[guid]
        local atKey = field .. "At"
        if stored and stored[atKey] and stored[field] ~= nil and (not firstAt or stored[atKey] < firstAt) then
            startValue = stored[field]
        end
    end
    local endValue = lastValue
    if endValue == nil then
        endValue = startValue
    end
    -- A closed month must not present a value observed only before it, or the
    -- character's live item level, as if it were that month's item level.
    if closed and lastAt == nil then
        return nil, nil
    end
    return startValue, endValue
end

local function BestByKind(candidates)
    local best = {}
    for index = 1, #candidates do
        local candidate = candidates[index]
        local current = best[candidate.kind]
        if not current or candidate.score > current.score then
            best[candidate.kind] = candidate
        end
    end
    local list = {}
    for _, candidate in pairs(best) do
        list[#list + 1] = candidate
    end
    table.sort(list, function(a, b)
        if a.score == b.score then
            return a.kind < b.kind
        end
        return a.score > b.score
    end)
    return list
end

local function BuildHighlights(characters, totals, activity, resources)
    local candidates = {}

    for index = 1, #characters do
        local character = characters[index]
        if character.ilvlStart and character.ilvlEnd and character.ilvlEnd - character.ilvlStart >= 3 then
            local delta = character.ilvlEnd - character.ilvlStart
            candidates[#candidates + 1] = {
                kind = "itemLevel:" .. character.guid,
                score = 20 + delta * 2,
                title = (character.name or "Character") .. " gained",
                value = WBF.Format.Signed(delta) .. " item levels",
                detail = WBF.Format.Progression(character.ilvlStart, character.ilvlEnd),
                detailGreen = true,
                classFile = character.classFile,
                atlas = "charactercreate-icon-customize-weapon",
                fallback = "Interface\\Icons\\INV_Sword_39",
                open = "itemLevel",
                characterGUID = character.guid,
            }
        end
        if character.levelStart and character.levelEnd and character.levelEnd > character.levelStart then
            local delta = character.levelEnd - character.levelStart
            candidates[#candidates + 1] = {
                kind = "level:" .. character.guid,
                score = 30 + delta * 5,
                title = (character.name or "Character") .. " leveled",
                value = WBF.Format.Progression(character.levelStart, character.levelEnd),
                detail = delta == 1 and "+1 level" or ("+" .. delta .. " levels"),
                detailGreen = true,
                classFile = character.classFile,
                atlas = character.classFile and ("classicon-" .. character.classFile:lower()) or nil,
                fallback = "Interface\\Icons\\Spell_ChargePositive",
                open = "character",
                characterGUID = character.guid,
            }
        end
    end

    if totals.mounts > 0 then
        local name, icon
        for index = 1, #activity do
            local event = activity[index]
            if event.eventType == WBF.EventType.Mount then
                name = event.text
                icon = event.meta and event.meta.icon
                break
            end
        end
        candidates[#candidates + 1] = {
            kind = "mount",
            score = 90 + totals.mounts,
            title = "New mount collected",
            value = name or "New mount",
            detail = totals.mounts > 1 and (totals.mounts .. " mounts collected") or nil,
            texture = icon,
            fallback = "Interface\\Icons\\Ability_Mount_RidingHorse",
            open = "mounts",
        }
    end

    if totals.pets > 0 then
        local name, icon
        for index = 1, #activity do
            local event = activity[index]
            if event.eventType == WBF.EventType.Pet then
                name = event.text
                icon = event.meta and event.meta.icon
                break
            end
        end
        candidates[#candidates + 1] = {
            kind = "pet",
            score = 72 + totals.pets,
            title = "New battle pet",
            value = name or "New battle pet",
            detail = totals.pets > 1 and (totals.pets .. " pets collected") or nil,
            texture = icon,
            fallback = "Interface\\Icons\\INV_Box_PetCarrier_01",
            open = "pets",
        }
    end

    if (totals.newDecor or 0) > 0 then
        local name, icon, xpNoted
        for index = 1, #activity do
            local event = activity[index]
            if event.eventType == WBF.EventType.HousingDecor then
                name = event.meta and event.meta.name or event.text
                icon = event.meta and event.meta.icon
                break
            end
        end
        if (totals.houseXP or 0) > 0 then
            xpNoted = "+" .. WBF.Format.Number(totals.houseXP) .. " House XP"
        end
        candidates[#candidates + 1] = {
            kind = "housing",
            score = 74 + math.min(totals.newDecor, 20),
            title = "New decor collected",
            value = name or "New decor",
            detail = xpNoted or (totals.newDecor > 1 and (totals.newDecor .. " new decor") or nil),
            texture = icon,
            fallback = "Interface\\Icons\\INV_Misc_Statue_02",
            open = "housing",
        }
    end

    if totals.appearances >= 5 then
        candidates[#candidates + 1] = {
            kind = "appearance",
            score = 40 + math.min(totals.appearances, 40),
            title = "Collections",
            value = WBF.Format.Number(totals.appearances) .. " appearances",
            detail = "Added to your Warband",
            atlas = "transmog-icon-chat",
            fallback = "Interface\\Icons\\INV_Chest_Cloth_17",
            open = "appearances",
        }
    end

    if totals.achievements > 0 then
        local name, icon
        for index = 1, #activity do
            local event = activity[index]
            if event.eventType == WBF.EventType.Achievement then
                name = event.text
                icon = event.meta and event.meta.icon
                break
            end
        end
        candidates[#candidates + 1] = {
            kind = "achievement",
            score = 65,
            title = "Achievement earned",
            value = name or "Achievement",
            detail = totals.achievements > 1 and (totals.achievements .. " achievements") or nil,
            texture = icon,
            fallback = "Interface\\Icons\\Achievement_General",
            open = "achievements",
        }
    end

    if totals.mythicPlus > 0 and totals.highestKey > 0 then
        candidates[#candidates + 1] = {
            kind = "mythicPlus",
            score = 50 + totals.highestKey,
            title = "Mythic+",
            value = "Highest +" .. totals.highestKey,
            detail = totals.mythicPlus == 1 and "1 run completed" or (totals.mythicPlus .. " runs completed"),
            atlas = "challengeMode-icon-chest",
            fallback = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
            open = "mythicPlus",
        }
    end

    if totals.bosses >= 5 then
        candidates[#candidates + 1] = {
            kind = "bosses",
            score = 20 + math.min(totals.bosses, 30),
            title = "Bosses defeated",
            value = WBF.Format.Number(totals.bosses),
            detail = totals.raids > 0 and (totals.raids .. (totals.raids == 1 and " raid" or " raids")) or nil,
            atlas = "DungeonSkull",
            fallback = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
            open = "bosses",
        }
    end

    if totals.delves > 0 then
        local name, tier
        for index = 1, #activity do
            local event = activity[index]
            if event.eventType == WBF.EventType.Delve then
                name = event.meta and event.meta.name
                tier = event.meta and event.meta.tier
                if tier and tier == totals.highestDelve then
                    break
                end
            end
        end
        local value = totals.highestDelve > 0 and ("Tier " .. totals.highestDelve) or (name or "Delve")
        candidates[#candidates + 1] = {
            kind = "delve",
            score = 48 + totals.highestDelve,
            title = "Delve completed",
            value = value,
            detail = totals.delves == 1 and (name or "1 delve") or (totals.delves .. " delves"),
            atlas = "delves-scenario-treasure-chest",
            fallback = "Interface\\Icons\\INV_Misc_Map_01",
            open = "delves",
        }
    end

    if totals.renown > 0 then
        local text
        for index = 1, #activity do
            local event = activity[index]
            if event.eventType == WBF.EventType.Renown then
                text = event.text
                break
            end
        end
        candidates[#candidates + 1] = {
            kind = "renown",
            score = 78,
            title = "Renown increased",
            value = text or "Renown",
            detail = totals.renown > 1 and (totals.renown .. " renown levels") or nil,
            atlas = "MajorFactions_MapIcons_Centaur_Major",
            fallback = "Interface\\Icons\\Achievement_Reputation_01",
            open = "renown",
        }
    end

    if totals.reputation >= 500 or totals.reputation <= -500 then
        candidates[#candidates + 1] = {
            kind = "reputation",
            score = 36 + math.min(math.abs(totals.reputation) / 100, 40),
            title = "Reputation",
            value = WBF.Format.Signed(totals.reputation),
            detail = "Received this period",
            atlas = "MajorFactions_MapIcons_Centaur_Major",
            fallback = "Interface\\Icons\\Achievement_Reputation_01",
            open = "reputation",
        }
    end

    if totals.preyNightmare > 0 then
        local title
        for index = 1, #activity do
            local event = activity[index]
            local meta = event.meta or {}
            if event.eventType == WBF.EventType.Prey and meta.completed and meta.difficulty == "Nightmare" then
                title = meta.title
                break
            end
        end
        candidates[#candidates + 1] = {
            kind = "prey",
            score = 84,
            title = "Nightmare Prey completed",
            value = title or "Nightmare",
            detail = totals.preyNightmare == 1 and "1 Nightmare hunt" or (totals.preyNightmare .. " Nightmare hunts"),
            fallback = "Interface\\Icons\\INV_Misc_MonsterClaw_02",
            open = "prey",
        }
    end

    if totals.journey >= 1000 then
        local journeyName
        for index = 1, #activity do
            local event = activity[index]
            local meta = event.meta or {}
            if event.eventType == WBF.EventType.Prey and meta.journeyName and meta.journeyName ~= "" then
                journeyName = meta.journeyName
                break
            end
        end
        candidates[#candidates + 1] = {
            kind = "journey",
            score = 76,
            title = journeyName or "Prey Journey",
            value = WBF.Format.Signed(totals.journey),
            detail = "Progress recorded this period",
            fallback = "Interface\\Icons\\INV_Misc_MonsterClaw_02",
            open = "prey",
        }
    end

    if totals.professions > 0 then
        local text
        for index = 1, #activity do
            local event = activity[index]
            if event.eventType == WBF.EventType.Profession then
                text = event.text
                break
            end
        end
        candidates[#candidates + 1] = {
            kind = "profession",
            score = 42,
            title = "Profession",
            value = text or "Skill increased",
            detail = totals.professions > 1 and (totals.professions .. " skill changes") or nil,
            atlas = "Professions-ChatIcon-Quality-Tier1",
            fallback = "Interface\\Icons\\INV_Misc_Gear_01",
            open = "professions",
        }
    end

    if WBF.Resources and WBF.Resources.HighlightCandidates then
        local resourceHighlights = WBF.Resources.HighlightCandidates(resources)
        for index = 1, #resourceHighlights do
            candidates[#candidates + 1] = resourceHighlights[index]
        end
    end

    local ranked = BestByKind(candidates)
    local highlights = {}
    for index = 1, math.min(3, #ranked) do
        highlights[index] = ranked[index]
    end
    return highlights
end

local function PlayedByCharacter(startAt, endAt)
    local played = {}
    local includesSample = false
    local liveSegment = nil
    local sessions = WarbandFYI_DB.sessions
    for index = 1, #sessions do
        local session = sessions[index]
        local segments = session.segments or {}
        for segmentIndex = 1, #segments do
            local segment = segments[segmentIndex]
            -- The open segment is added when the dashboard draws, so the
            -- cached summary does not have to be rebuilt to keep play time moving.
            if not segment.endedAt and not session.endedAt and segment.guid then
                liveSegment = {
                    sessionId = session.id,
                    guid = segment.guid,
                    startedAt = segment.startedAt,
                }
                if played[segment.guid] == nil then
                    played[segment.guid] = 0
                end
                if session.sample then
                    includesSample = true
                end
            else
                local segmentEnd = WBF.Sessions.SegmentEnd(session, segment)
                local seconds = Overlap(segment.startedAt, segmentEnd, startAt, endAt)
                if seconds > 0 and segment.guid then
                    played[segment.guid] = (played[segment.guid] or 0) + seconds
                    if session.sample then
                        includesSample = true
                    end
                end
            end
        end
    end
    return played, includesSample, liveSegment
end

function WBF.Aggregator.LivePlay(summary)
    local live = summary and summary.liveSegment
    if type(live) ~= "table" or not WBF.Sessions or not WBF.Sessions.Find then
        return 0, nil
    end
    local session = WBF.Sessions.Find(live.sessionId)
    if not session or type(session.segments) ~= "table" then
        return 0, nil
    end
    local segment = nil
    for index = 1, #session.segments do
        local candidate = session.segments[index]
        if candidate.guid == live.guid and candidate.startedAt == live.startedAt then
            segment = candidate
            break
        end
    end
    if not segment then
        return 0, nil
    end
    local segmentEnd
    if segment.endedAt then
        segmentEnd = segment.endedAt
    elseif session.endedAt then
        segmentEnd = session.endedAt
    else
        segmentEnd = WBF.Sessions.SegmentEnd(session, segment)
    end
    local windowStart = summary.startAt or 0
    local windowEnd = summary.endAt
    local view = summary.view
    -- A closed month keeps its own end. Extending it to "now" would add the next month's play.
    if not summary.closed and (view == "current" or view == "today" or view == "week" or view == "month" or view == "warband") then
        local now = WBF.Time.Now()
        if type(windowEnd) ~= "number" or now > windowEnd then
            windowEnd = now
        end
    end
    if type(segment.startedAt) ~= "number" or type(segmentEnd) ~= "number" or type(windowEnd) ~= "number" then
        return 0, nil
    end
    return Overlap(segment.startedAt, segmentEnd, windowStart, windowEnd), segment.guid
end

function WBF.Aggregator.MonthContextFor(year, month, now, offset)
    now = now or WBF.Time.Now()
    local startAt, endAt, isCurrent, closedEnd = WBF.Time.MonthBounds(year, month, now)
    local title = WBF.Time.MonthTitle(year, month)
    return {
        year = year,
        month = month,
        key = WBF.Time.MonthKey(year, month),
        offset = offset or 0,
        startAt = startAt,
        endAt = endAt,
        closedEnd = closedEnd,
        periodStart = startAt,
        periodEnd = closedEnd,
        isCurrent = isCurrent,
        closed = not isCurrent,
        label = isCurrent and ("This Month — " .. title) or title,
        periodPhrase = isCurrent and "this month" or title,
    }
end

function WBF.Aggregator.MonthContext(offset, now)
    now = now or WBF.Time.Now()
    offset = tonumber(offset) or 0
    if offset > 0 then
        offset = 0
    end
    -- CurrentMonth returns two values, so capture them before passing them on.
    local year, month = WBF.Time.CurrentMonth(now)
    year, month = WBF.Time.AddMonths(year, month, offset)
    return WBF.Aggregator.MonthContextFor(year, month, now, offset)
end

function WBF.Aggregator.Range(view, offset)
    local now = WBF.Time.Now()
    if view == "today" then
        return WBF.Time.StartOfDay(now), now, "Today"
    end
    if view == "week" then
        return WBF.Time.StartOfWeek(now), now, "This Week"
    end
    if view == "month" then
        if WBF.Time.MonthBounds and WBF.Aggregator.MonthContext then
            local ctx = WBF.Aggregator.MonthContext(offset, now)
            return ctx.startAt, ctx.endAt, ctx.label
        end
        return WBF.Time.StartOfMonth(now), now, "This Month"
    end
    if view == "warband" then
        return 0, now, "Warband"
    end
    if view == "current" then
        local session = WBF.Sessions.GetActive()
        if not session then
            return nil, nil, "Current Session", "No active session yet."
        end
        return session.startedAt, now, "Current Session"
    end
    if view == "last" then
        local session = WBF.Sessions.GetLastCompleted()
        if not session then
            return nil, nil, "Last Session", "No completed session yet. A session closes after you have been away for the timeout."
        end
        return session.startedAt, session.endedAt, "Last Session"
    end
    return nil, nil, "WarbandFYI", "This view is not a time range."
end

local function BuildSummary(view, offset, forcedCtx, forceRaw)
    local monthCtx = forcedCtx
    if not monthCtx and view == "month" and WBF.Time.MonthBounds and WBF.Aggregator.MonthContext then
        monthCtx = WBF.Aggregator.MonthContext(offset)
    end
    if monthCtx and monthCtx.closed and not forceRaw and WBF.MonthHistory and WBF.MonthHistory.CoversRaw and not WBF.MonthHistory.CoversRaw(monthCtx.startAt) then
        return WBF.MonthHistory.SummaryFor(monthCtx)
    end
    local startAt, endAt, label, emptyReason
    if monthCtx then
        startAt, endAt, label = monthCtx.startAt, monthCtx.endAt, monthCtx.label
        emptyReason = nil
    else
        startAt, endAt, label, emptyReason = WBF.Aggregator.Range(view, offset)
    end
    local closed = monthCtx and monthCtx.closed or false
    local summary = {
        view = view,
        label = label or "WarbandFYI",
        empty = false,
        emptyReason = emptyReason,
        startAt = startAt,
        endAt = endAt,
        playedSeconds = 0,
        includesSample = false,
        characters = {},
        totals = EmptyCounts(),
        goldNet = 0,
        goldTracked = false,
        highlights = {},
        activity = {},
    }

    if not startAt or not endAt then
        summary.empty = true
        return summary
    end

    local db = WBF.Database.Get()
    local played, samplePlay, liveSegment = PlayedByCharacter(startAt, endAt)
    summary.liveSegment = liveSegment
    summary.includesSample = samplePlay
    local characters = {}

    for guid, seconds in pairs(played) do
        local row = EnsureCharacter(characters, guid)
        if row then
            row.playedSeconds = seconds
            summary.playedSeconds = summary.playedSeconds + seconds
        end
    end

    local activity = {}
    local events = db.events
    for index = 1, #events do
        local event = events[index]
        if event.at and event.at >= startAt and event.at <= endAt and WBF.QuestVisibility.IsPlayerActivity(event) then
            local surfaced = not (WBF.ResourceBehaviour and WBF.ResourceBehaviour.HidesActivity(event))
            if surfaced then
                activity[#activity + 1] = event
            end
            if event.sample then
                summary.includesSample = true
            end
            AddCount(summary.totals, event)
            if event.guid then
                local row = EnsureCharacter(characters, event.guid)
                if row then
                    AddCount(row.counts, event)
                end
            end
        end
    end

    RecountPreyStarted(summary.totals, activity, nil)
    for _, row in pairs(characters) do
        RecountPreyStarted(row.counts, activity, row.guid)
    end

    table.sort(activity, function(a, b)
        if a.at == b.at then
            return (a.id or 0) > (b.id or 0)
        end
        return a.at > b.at
    end)
    summary.activity = activity

    local goldNet, goldTracked, goldByGuid, goldOfflineByGuid = WBF.GoldTracker.Collect(db, startAt, endAt)
    summary.goldNet = goldNet
    summary.goldTracked = goldTracked == true
    summary.totals.gold = goldNet
    summary.goldOfflineByGuid = goldOfflineByGuid or {}
    local offline = 0
    for _, amount in pairs(summary.goldOfflineByGuid) do
        offline = offline + (amount or 0)
    end
    summary.goldOffline = offline
    for guid, amount in pairs(goldByGuid) do
        if amount ~= 0 then
            local row = EnsureCharacter(characters, guid)
            if row then
                row.counts.gold = amount
            end
        end
    end

    for guid, row in pairs(characters) do
        row.levelStart, row.levelEnd = ReadProgress(db, guid, "level", startAt, endAt, closed)
        row.ilvlStart, row.ilvlEnd = ReadProgress(db, guid, "itemLevel", startAt, endAt, closed)
        local stored = db.characters[guid]
        if stored then
            row.name = stored.name or row.name
            row.realm = stored.realm or row.realm
            row.classFile = stored.classFile or row.classFile
            row.className = stored.className or row.className
            row.specName = stored.specName or row.specName
            row.role = stored.role or row.role
        end
    end

    if not startAt or startAt <= 0 then
        local life = db.lifetime
        if type(life) == "table" then
            WBF.Aggregator.MergeCounts(summary.totals, life.totals)
            local storedCharacters = life.characters or {}
            for guid, stored in pairs(storedCharacters) do
                local playedSeconds = stored.playedSeconds or 0
                local hasCounts = type(stored.counts) == "table" and next(stored.counts) ~= nil
                if playedSeconds > 0 or hasCounts or stored.level ~= nil or stored.itemLevel ~= nil then
                    summary.playedSeconds = summary.playedSeconds + playedSeconds
                    local row = EnsureCharacter(characters, guid)
                    if row then
                        row.playedSeconds = (row.playedSeconds or 0) + playedSeconds
                        WBF.Aggregator.MergeCounts(row.counts, stored.counts)
                    end
                end
            end
            local gold = life.gold
            if type(gold) == "table" then
                local net = gold.net or 0
                if net ~= 0 or gold.tracked then
                    summary.goldNet = (summary.goldNet or 0) + net
                    summary.totals.gold = summary.goldNet
                    if gold.tracked then
                        summary.goldTracked = true
                    end
                end
                for guid, amount in pairs(gold.byGuid or {}) do
                    if amount ~= 0 then
                        local row = EnsureCharacter(characters, guid)
                        if row then
                            row.counts.gold = (row.counts.gold or 0) + amount
                        end
                    end
                end
                local offline = summary.goldOffline or 0
                for guid, amount in pairs(gold.offlineByGuid or {}) do
                    offline = offline + (amount or 0)
                    summary.goldOfflineByGuid[guid] = (summary.goldOfflineByGuid[guid] or 0) + (amount or 0)
                end
                summary.goldOffline = offline
            end
        end
    end

    if WBF.WorldActivity and WBF.WorldActivity.Collect then
        local worldTotals, worldByGuid, fishingItems = WBF.WorldActivity.Collect(db, startAt, endAt)
        WBF.Aggregator.MergeCounts(summary.totals, worldTotals)
        for guid, counts in pairs(worldByGuid) do
            local row = EnsureCharacter(characters, guid)
            if row then
                WBF.Aggregator.MergeCounts(row.counts, counts)
            end
        end
        summary.fishingItems = fishingItems
    end

    local list = {}
    for _, row in pairs(characters) do
        list[#list + 1] = row
    end
    table.sort(list, function(a, b)
        if a.playedSeconds == b.playedSeconds then
            return (a.name or "") < (b.name or "")
        end
        return a.playedSeconds > b.playedSeconds
    end)
    summary.characters = list
    local resourceOptions = closed and { closed = true } or nil
    local resourcePack = WBF.Resources and WBF.Resources.ForPeriod(db.events, startAt, endAt, resourceOptions) or nil
    summary.resources = resourcePack and resourcePack.tiles or {}
    if resourcePack then
        for guid, lines in pairs(resourcePack.byGuid) do
            local row = characters[guid]
            if row and lines and #lines > 0 then
                local parts = {}
                for index = 1, math.min(2, #lines) do
                    local line = lines[index]
                    if line.earned > 0 then
                        parts[#parts + 1] = WBF.Format.Signed(line.earned) .. " " .. line.short
                    elseif line.spent > 0 then
                        parts[#parts + 1] = WBF.Format.Signed(-line.spent) .. " " .. line.short
                    end
                end
                if #parts > 0 then
                    row.resourceLine = table.concat(parts, "   ·   ")
                end
            end
        end
    end
    summary.highlights = BuildHighlights(list, summary.totals, activity, summary.resources)
    local worldTotal = (summary.totals.fishing or 0) + (summary.totals.mining or 0) + (summary.totals.herbalism or 0) + (summary.totals.lumber or 0) + (summary.totals.skinning or 0) + (summary.totals.rares or 0)
    if closed then
        local extra = 0
        if summary.liveSegment and WBF.Aggregator.LivePlay then
            local amount = WBF.Aggregator.LivePlay(summary)
            if type(amount) == "number" then
                extra = amount
            end
        end
        if extra <= 0 then
            summary.liveSegment = nil
        end
        local kept = {}
        for index = 1, #list do
            local row = list[index]
            local active = (row.playedSeconds or 0) > 0 or row.ilvlStart ~= nil or row.ilvlEnd ~= nil or row.levelStart ~= nil or row.levelEnd ~= nil
            if not active and type(row.counts) == "table" then
                for _, value in pairs(row.counts) do
                    if type(value) == "number" and value ~= 0 then
                        active = true
                        break
                    end
                end
            end
            if active or (row.resourceLine and row.resourceLine ~= "") then
                kept[#kept + 1] = row
            end
        end
        list = kept
        summary.characters = kept
    end
    summary.hasActivity = summary.playedSeconds > 0 or summary.liveSegment ~= nil or #activity > 0 or #list > 0 or worldTotal > 0 or #(summary.resources or {}) > 0 or (summary.goldNet or 0) ~= 0
    if monthCtx and WBF.MonthHistory and WBF.MonthHistory.ApplyChrome then
        summary.trackedFrom = WBF.MonthHistory.PartialStart(monthCtx)
        WBF.MonthHistory.ApplyChrome(summary, monthCtx)
        if closed and not summary.hasActivity then
            summary.empty = true
            summary.emptyReason = "No WarbandFYI data was recorded for " .. WBF.Time.MonthTitle(monthCtx.year, monthCtx.month) .. "."
            summary.highlights = {}
            summary.characters = {}
            summary.activity = {}
            summary.resources = {}
        end
    end
    summary.closed = closed
    return summary
end

function WBF.Aggregator.BuildClosedMonth(year, month, now)
    local ctx = WBF.Aggregator.MonthContextFor(year, month, now, 0)
    ctx.closed = true
    ctx.isCurrent = false
    ctx.endAt = ctx.closedEnd
    ctx.label = WBF.Time.MonthTitle(year, month)
    ctx.periodPhrase = ctx.label
    return BuildSummary("month", 0, ctx, true)
end

local summaryRevision = 0
local cacheFingerprint = nil
local summaryCache = {}

function WBF.Aggregator.MarkDirty()
    summaryRevision = summaryRevision + 1
end

local function SummaryFingerprint()
    local db = WBF.Database and WBF.Database.Get and WBF.Database.Get() or nil
    local events = db and db.events or {}
    local sessions = db and db.sessions or {}
    local snapshots = db and db.snapshots or {}
    local activeId = db and db.activeSessionId or 0
    return table.concat({
        tostring(summaryRevision),
        tostring(#events),
        tostring(#sessions),
        tostring(#snapshots),
        tostring(activeId or 0),
    }, ":")
end

function WBF.Aggregator.Build(view, offset)
    if view == "month" and WBF.MonthHistory and WBF.MonthHistory.OnClock and WBF.Time.MonthBounds then
        pcall(WBF.MonthHistory.OnClock)
    end
    offset = tonumber(offset) or 0
    if offset > 0 then
        offset = 0
    end
    local cacheKey = view
    if view == "month" then
        cacheKey = "month:" .. tostring(offset)
    end
    local fingerprint = SummaryFingerprint()
    if fingerprint == cacheFingerprint and summaryCache[cacheKey] then
        return summaryCache[cacheKey]
    end
    if fingerprint ~= cacheFingerprint then
        summaryCache = {}
        cacheFingerprint = fingerprint
    end
    local summary = BuildSummary(view, offset)
    summaryCache[cacheKey] = summary
    return summary
end
