local _, WBF = ...

WBF.Instances = {}

-- Raids and dungeons, including legacy raids, are recorded when you enter
-- them and when a boss encounter succeeds. "Raids" means instances entered.
-- A full clear is not claimed: Blizzard does not give a reliable boss-list
-- completion signal for arbitrary legacy raids.
--
-- Delves are recorded in Tracking/Delves.lua from the delve completion flag
-- and the active tier, not from this raid/dungeon enter path.
-- Mythic+ completions use CHALLENGE_MODE_COMPLETED plus the challenge-mode
-- completion info, which is the supported source for key level and timing.

local currentKey = nil
local pendingBoss = {}
local mythicPending = false
local lastMythicKey = nil
local lastMythicAt = 0
local settled = false
local BOSS_DEDUPE_SECONDS = 8

local function DifficultyInfo(difficultyID)
    difficultyID = WBF.Format.AsNumber(difficultyID)
    if not difficultyID or not GetDifficultyInfo then
        return nil, false
    end
    local name, _, _, isChallengeMode = WBF.Format.SafeCall(GetDifficultyInfo, difficultyID)
    local challenge = WBF.Format.AsBoolean(isChallengeMode) == true
    return WBF.Format.PlainString(name), challenge
end

local function InstanceKey(info)
    local mapID = info.mapID or info.lfgDungeonID or 0
    return tostring(mapID) .. ":" .. tostring(info.difficultyID or 0) .. ":" .. tostring(info.instanceType or "")
end

local function MatchingLockout(mapID, difficultyID)
    if not mapID or not GetNumSavedInstances or not GetSavedInstanceInfo then
        return nil
    end
    local count = WBF.Format.AsNumber(WBF.Format.SafeCall(GetNumSavedInstances))
    if not count or count < 1 then
        return nil
    end
    for index = 1, count do
        local _, lockoutId, _, difficulty, _, _, _, _, _, _, _, _, _, instanceId = WBF.Format.SafeCall(GetSavedInstanceInfo, index)
        local savedMap = WBF.Format.AsNumber(instanceId)
        local savedDifficulty = WBF.Format.AsNumber(difficulty)
        local savedLock = WBF.Format.AsNumber(lockoutId)
        if savedLock and savedMap == mapID and (not difficultyID or savedDifficulty == difficultyID) then
            return savedLock
        end
    end
    return nil
end

local function ReadInstance()
    if not GetInstanceInfo then
        return nil
    end
    local instanceName, instanceType, difficultyID, difficultyName, _, _, _, mapID, _, lfgDungeonID = WBF.Format.SafeCall(GetInstanceInfo)
    instanceType = WBF.Format.PlainString(instanceType)
    if not instanceType then
        return nil
    end
    mapID = WBF.Format.AsNumber(mapID)
    difficultyID = WBF.Format.AsNumber(difficultyID)
    return {
        name = WBF.Format.PlainString(instanceName),
        instanceType = instanceType,
        difficultyID = difficultyID,
        difficultyName = WBF.Format.PlainString(difficultyName),
        mapID = mapID,
        lfgDungeonID = WBF.Format.AsNumber(lfgDungeonID),
        lockoutID = MatchingLockout(mapID, difficultyID),
    }
end

local function SameInstance(saved, live)
    if type(saved) ~= "table" or type(live) ~= "table" then
        return false
    end
    if saved.instanceType ~= live.instanceType then
        return false
    end
    if (saved.difficultyID or 0) ~= (live.difficultyID or 0) then
        return false
    end
    if saved.mapID and live.mapID and saved.mapID ~= live.mapID then
        return false
    end
    if not saved.mapID and not live.mapID then
        if (saved.lfgDungeonID or 0) ~= (live.lfgDungeonID or 0) then
            return false
        end
    elseif not saved.mapID or not live.mapID then
        return false
    end
    if saved.lockoutID and live.lockoutID and saved.lockoutID ~= live.lockoutID then
        return false
    end
    local guid = WBF.Characters and WBF.Characters.GetGuid and WBF.Characters.GetGuid() or nil
    if saved.guid and guid and saved.guid ~= guid then
        return false
    end
    return true
end

local function StoreInstance(info)
    local db = WBF.Database.Get()
    local session = WBF.Sessions.GetActive and WBF.Sessions.GetActive() or nil
    local stored = {
        mapID = info.mapID,
        difficultyID = info.difficultyID,
        instanceType = info.instanceType,
        lockoutID = info.lockoutID,
        lfgDungeonID = info.lfgDungeonID,
        name = info.name,
        sessionId = session and session.id or nil,
        guid = WBF.Characters and WBF.Characters.GetGuid and WBF.Characters.GetGuid() or nil,
    }
    db.currentInstance = stored
    if session then
        session.instance = stored
    end
    currentKey = InstanceKey(info)
end

local function ClearInstance()
    local db = WBF.Database.Get()
    db.currentInstance = nil
    local session = WBF.Sessions.GetActive and WBF.Sessions.GetActive() or nil
    if session then
        session.instance = nil
    end
    currentKey = nil
end

function WBF.Instances.Settle()
    settled = true
end

function WBF.Instances.HandleEnteringWorld(isReload)
    local live = ReadInstance()
    if not live then
        return
    end
    if live.instanceType ~= "raid" and live.instanceType ~= "party" then
        if isReload or not settled then
            return
        end
        if currentKey ~= nil or (WBF.Database.Get().currentInstance ~= nil) then
            ClearInstance()
        end
        return
    end

    local saved = WBF.Database.Get().currentInstance
    local key = InstanceKey(live)
    if key == currentKey or SameInstance(saved, live) then
        currentKey = key
        StoreInstance(live)
        return
    end

    StoreInstance(live)
    local difficultyName = live.difficultyName
    local keystone
    local lookedUp, challenge = DifficultyInfo(live.difficultyID)
    keystone = challenge
    if not difficultyName or difficultyName == "" then
        difficultyName = lookedUp
    end

    local text = "Entered " .. (live.name or "an instance")
    WBF.Events.Add({
        category = WBF.Category.Instance,
        eventType = WBF.EventType.InstanceEnter,
        text = text,
        meta = {
            instanceName = live.name,
            instanceType = live.instanceType,
            instanceID = live.mapID,
            difficultyID = live.difficultyID,
            difficultyName = difficultyName,
            lockoutID = live.lockoutID,
            keystone = keystone,
            iconAtlas = live.instanceType == "raid" and "DungeonSkull" or "QuestNormal",
        },
    })
end

local function MapName(mapID)
    if not mapID or not C_ChallengeMode or not C_ChallengeMode.GetMapUIInfo then
        return nil
    end
    local info = WBF.Format.SafeCall(C_ChallengeMode.GetMapUIInfo, mapID)
    if type(info) == "table" then
        return info.name
    end
    if type(info) == "string" then
        return info
    end
    return nil
end

local function MythicLevel(info)
    if WBF.Format.IsSecret(info) or type(info) ~= "table" then
        return nil
    end
    return WBF.Format.AsNumber(info.level)
end

local function ReadMythicPlus()
    if not C_ChallengeMode then
        return nil
    end
    local info
    if C_ChallengeMode.GetChallengeCompletionInfo then
        info = WBF.Format.SafeCall(C_ChallengeMode.GetChallengeCompletionInfo)
    end
    local level = MythicLevel(info)
    if not level or level == 0 then
        info = nil
    end
    if not info and C_ChallengeMode.GetCompletionInfo then
        local mapID, rawLevel, timeMS, onTime, upgrades, practice = WBF.Format.SafeCall(C_ChallengeMode.GetCompletionInfo)
        local parsed = WBF.Format.AsNumber(rawLevel)
        if parsed and parsed > 0 and not WBF.Format.IsSecret(mapID) then
            info = {
                mapChallengeModeID = WBF.Format.AsNumber(mapID),
                level = parsed,
                time = timeMS,
                onTime = onTime,
                keystoneUpgradeLevels = upgrades,
                practiceRun = practice,
            }
        end
    end
    if not MythicLevel(info) or MythicLevel(info) == 0 then
        return nil
    end
    return info
end

local function RecordMythicPlus()
    mythicPending = false
    local info = ReadMythicPlus()
    if not info then
        return
    end
    local level = MythicLevel(info)
    if not level then
        return
    end
    local mapID = WBF.Format.AsNumber(info.mapChallengeModeID) or 0
    local timeValue = WBF.Format.AsNumber(info.time) or 0
    local key = tostring(mapID) .. ":" .. tostring(timeValue) .. ":" .. tostring(level)
    local now = WBF.Time.Now()
    if key == lastMythicKey and (now - lastMythicAt) < 10 then
        return
    end
    lastMythicKey = key
    lastMythicAt = now
    local name = WBF.Format.PlainString(MapName(mapID > 0 and mapID or nil)) or "Mythic+"
    local onTime = WBF.Format.AsBoolean(info.onTime)
    local practiceRaw = info.practiceRun
    local practiceRun = false
    if practiceRaw ~= nil and not WBF.Format.IsSecret(practiceRaw) then
        practiceRun = WBF.Format.AsBoolean(practiceRaw) == true
    end
    local timed = onTime == true and "timed" or "untimed"
    local timeMS = WBF.Format.AsNumber(info.time)
    local durationSeconds
    if timeMS and timeMS >= 10000 then
        local seconds = math.floor(timeMS / 1000)
        if seconds >= 10 and seconds <= 7200 then
            durationSeconds = seconds
        end
    end
    WBF.Events.Add({
        category = WBF.Category.Instance,
        eventType = WBF.EventType.MythicPlus,
        dedupeKey = "mplus:" .. key .. ":" .. now,
        dedupeTransient = true,
        text = string.format("%s +%d completed", name, level),
        new = level,
        meta = {
            mapID = mapID,
            name = name,
            level = level,
            onTime = onTime == true,
            timedText = timed,
            durationSeconds = durationSeconds,
            practiceRun = practiceRun,
            upgrades = info.keystoneUpgradeLevels,
            iconAtlas = "challengeMode-icon-chest",
        },
    })
end

function WBF.Instances.Register(bus)
    if not (C_Timer and C_Timer.After) then
        settled = true
    end
    bus:On("PLAYER_ENTERING_WORLD", function(_, isReload)
        WBF.Instances.HandleEnteringWorld(isReload and true or false)
    end)

    bus:On("ENCOUNTER_END", function(encounterID, encounterName, difficultyID, groupSize, success)
        if WBF.Format.IsSecret(success) or WBF.Format.IsSecret(encounterName) then
            return
        end
        if success ~= 1 and success ~= true then
            return
        end
        encounterName = WBF.Format.PlainString(encounterName)
        if not encounterName then
            return
        end
        if WBF.Delves and WBF.Delves.ConsumesBossKill and WBF.Delves.ConsumesBossKill() then
            return
        end

        local live = ReadInstance()
        local instanceName = live and live.name or nil
        local instanceType = live and live.instanceType or nil
        local instanceDifficultyID = live and live.difficultyID or nil
        local difficultyName = live and live.difficultyName or nil
        local instanceID = live and live.mapID or nil
        encounterID = WBF.Format.AsNumber(encounterID)
        difficultyID = WBF.Format.AsNumber(difficultyID)
        groupSize = WBF.Format.AsNumber(groupSize)
        local keystone = false
        if not difficultyName or difficultyName == "" then
            difficultyName, keystone = DifficultyInfo(difficultyID or instanceDifficultyID)
        else
            _, keystone = DifficultyInfo(difficultyID or instanceDifficultyID)
        end
        if instanceType ~= "raid" and instanceType ~= "party" then
            instanceType = "world"
        end

        local dedupeKey = "boss:" .. tostring(encounterID or 0) .. ":" .. tostring(instanceID or 0) .. ":" .. tostring(difficultyID or instanceDifficultyID or 0)
        if pendingBoss[dedupeKey] or WBF.Database.SeenWithin(dedupeKey, BOSS_DEDUPE_SECONDS) then
            return
        end
        pendingBoss[dedupeKey] = true
        local function CommitBoss()
            pendingBoss[dedupeKey] = nil
            if WBF.Delves and WBF.Delves.ConsumesBossKill and WBF.Delves.ConsumesBossKill() then
                return
            end
            if WBF.Database.SeenWithin(dedupeKey, BOSS_DEDUPE_SECONDS) then
                return
            end
            WBF.Database.MarkDedupe(dedupeKey, WBF.Time.Now())
            WBF.Events.Add({
                category = WBF.Category.Instance,
                eventType = WBF.EventType.BossKill,
                text = encounterName .. " defeated",
                meta = {
                    encounterID = encounterID,
                    encounterName = encounterName,
                    difficultyID = difficultyID,
                    difficultyName = difficultyName,
                    groupSize = groupSize,
                    instanceName = instanceName,
                    instanceType = instanceType,
                    instanceID = instanceID,
                    keystone = keystone,
                    iconAtlas = "DungeonSkull",
                },
            })
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.6, CommitBoss)
        else
            CommitBoss()
        end
    end)

    bus:On("CHALLENGE_MODE_COMPLETED", function()
        if mythicPending then
            return
        end
        mythicPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, RecordMythicPlus)
        else
            RecordMythicPlus()
        end
    end)
end
