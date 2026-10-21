local _, WBF = ...

-- Battle pet activity for the Warband. State is kept while a fight is open so
-- several level-ups become one record. Rounds, abilities, and damage are ignored.

WBF.PetBattles = {}

local QUALITY = {
    [1] = "Poor",
    [2] = "Common",
    [3] = "Uncommon",
    [4] = "Rare",
    [5] = "Epic",
    [6] = "Legendary",
}

local battle = nil
local pendingCapture = nil
local pendingPet = nil
local flushedCapture = false
local recentBattleUntil = 0

local function AllyOwner()
    if Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Ally then
        return Enum.BattlePetOwner.Ally
    end
    return 1
end

local function EnemyOwner()
    if Enum and Enum.BattlePetOwner and Enum.BattlePetOwner.Enemy then
        return Enum.BattlePetOwner.Enemy
    end
    return 2
end

local function SameOwner(value, owner)
    if WBF.Format.IsSecret(value) then
        return false
    end
    if value == owner then
        return true
    end
    local number = tonumber(value)
    return number ~= nil and number == owner
end

function WBF.PetBattles.QualityName(quality)
    if type(quality) == "string" and quality ~= "" then
        return quality
    end
    return QUALITY[tonumber(quality)]
end

function WBF.PetBattles.BattleKind(isWild, isNpc)
    if isWild then
        return "wild"
    end
    if isNpc then
        return "trainer"
    end
    return "pvp"
end

function WBF.PetBattles.FoldLevels(name, fromLevel, toLevel)
    fromLevel = tonumber(fromLevel)
    toLevel = tonumber(toLevel)
    if not fromLevel or not toLevel or toLevel <= fromLevel then
        return nil
    end
    local petName = (type(name) == "string" and name ~= "") and name or "Pet"
    return {
        name = petName,
        fromLevel = fromLevel,
        toLevel = toLevel,
        levels = toLevel - fromLevel,
        reached25 = fromLevel < 25 and toLevel >= 25 or false,
        eventLabel = "Pet level up",
        detail = petName .. "  " .. fromLevel .. " -> " .. toLevel,
    }
end

function WBF.PetBattles.NoteLevel(bucket, petKey, name, newLevel, previousLevel)
    newLevel = tonumber(newLevel)
    if type(bucket) ~= "table" or petKey == nil or not newLevel then
        return nil
    end
    local row = bucket[petKey]
    if not row then
        row = {
            name = name,
            -- An unavailable opening snapshot does not prove a one-level gain.
            from = tonumber(previousLevel),
            to = newLevel,
        }
        bucket[petKey] = row
        return row
    end
    if name and name ~= "" then
        row.name = name
    end
    if newLevel > (row.to or 0) then
        row.to = newLevel
    end
    return row
end

function WBF.PetBattles.DescribeCapture(name, quality, level, isNew)
    local petName = (type(name) == "string" and name ~= "") and name or "Battle pet"
    local bits = {}
    local qualityName = WBF.PetBattles.QualityName(quality)
    if qualityName then
        bits[#bits + 1] = qualityName
    end
    level = tonumber(level)
    if level then
        bits[#bits + 1] = "Level " .. level
    end
    if isNew then
        bits[#bits + 1] = "New species"
    end
    local detail = petName
    if #bits > 0 then
        detail = detail .. "  ·  " .. table.concat(bits, "  ·  ")
    end
    return {
        eventLabel = "Pet captured",
        detail = detail,
        captured = 1,
        newSpecies = isNew and true or false,
    }
end

local function EmptyReport()
    return {
        started = 0,
        completed = 0,
        wins = 0,
        losses = 0,
        wild = 0,
        trainer = 0,
        pvp = 0,
        captured = 0,
        levels = 0,
        level25 = 0,
        newPets = 0,
        days = {},
        topPets = {},
        captures = {},
    }
end

local function DayParts(at)
    if type(at) ~= "number" then
        return "0", ""
    end
    if type(date) == "function" then
        return date("%Y-%m-%d", at), date("%b %d", at)
    end
    local key = tostring(math.floor(at / 86400))
    return key, key
end

local function IsPetBattle(event)
    if WBF.EventType and event.eventType == WBF.EventType.PetBattle then
        return true
    end
    return event.eventType == "petBattle"
end

local function IsPet(event)
    if WBF.EventType and event.eventType == WBF.EventType.Pet then
        return true
    end
    return event.eventType == "pet"
end

-- Presentation only: retain every battle event and its original delta. Build
-- from retained history before UI filters/limits, including resumed sessions.
-- Missing IDs or a gap in levels cannot safely establish session progression.
function WBF.PetBattles.SessionLevelDetails(events)
    local ordered, sessions, details = {}, {}, {}
    for index, event in ipairs(events or {}) do
        if IsPetBattle(event) and (event.meta or {}).kind == "level" then
            ordered[#ordered + 1] = { event = event, index = index }
        end
    end
    table.sort(ordered, function(a, b)
        local x, y = a.event, b.event
        if (x.at or 0) ~= (y.at or 0) then
            return (x.at or 0) < (y.at or 0)
        end
        if (x.id or 0) ~= (y.id or 0) then
            return (x.id or 0) < (y.id or 0)
        end
        return a.index < b.index
    end)
    for _, entry in ipairs(ordered) do
        local event = entry.event
        local meta = event.meta
        local first, last = tonumber(meta.fromLevel), tonumber(meta.toLevel)
        if event.sessionId ~= nil and meta.petKey and meta.petKey ~= "" then
            local session = sessions[event.sessionId]
            if not session then
                session = {}
                sessions[event.sessionId] = session
            end
            local prior = session[meta.petKey]
            if first and last and first >= 1 and last <= 25 and last > first then
                local start = prior and prior.to == first and prior.from or first
                session[meta.petKey] = { from = start, to = last }
                if start < first then
                    local folded = WBF.PetBattles.FoldLevels(meta.petName, start, last)
                    details[event] = folded.detail .. " (session)"
                end
            else
                session[meta.petKey] = nil
            end
        end
    end
    return details
end

function WBF.PetBattles.ApplyEvent(bucket, event)
    if type(bucket) ~= "table" or type(event) ~= "table" or not IsPetBattle(event) then
        return false
    end
    local meta = event.meta or {}
    if meta.kind == "battleStart" then
        bucket.petBattlesStarted = (bucket.petBattlesStarted or 0) + 1
        return true
    end
    if meta.kind == "battle" then
        bucket.petBattles = (bucket.petBattles or 0) + 1
        if meta.outcome == "win" then
            bucket.petWins = (bucket.petWins or 0) + 1
        else
            bucket.petLosses = (bucket.petLosses or 0) + 1
        end
        if meta.battleType == "wild" then
            bucket.petWild = (bucket.petWild or 0) + 1
        elseif meta.battleType == "pvp" then
            bucket.petPvp = (bucket.petPvp or 0) + 1
        else
            bucket.petTrainer = (bucket.petTrainer or 0) + 1
        end
        return true
    end
    if meta.kind == "level" then
        bucket.petLevels = (bucket.petLevels or 0) + (meta.levels or 0)
        if meta.reached25 then
            bucket.petsLevel25 = (bucket.petsLevel25 or 0) + 1
        end
        return true
    end
    if meta.kind == "capture" then
        bucket.petsCaptured = (bucket.petsCaptured or 0) + 1
        if meta.newSpecies then
            bucket.newPets = (bucket.newPets or 0) + 1
        end
        return true
    end
    return true
end

function WBF.PetBattles.Collect(events)
    local report = EmptyReport()
    local dayOrder = {}
    local dayMap = {}
    local pets = {}
    local petOrder = {}
    events = events or {}
    for index = 1, #events do
        local event = events[index]
        if IsPetBattle(event) then
            local meta = event.meta or {}
            if meta.kind == "battleStart" then
                report.started = report.started + 1
            elseif meta.kind == "battle" then
                report.completed = report.completed + 1
                if meta.outcome == "win" then
                    report.wins = report.wins + 1
                else
                    report.losses = report.losses + 1
                end
                if meta.battleType == "wild" then
                    report.wild = report.wild + 1
                elseif meta.battleType == "pvp" then
                    report.pvp = report.pvp + 1
                else
                    report.trainer = report.trainer + 1
                end
                local key, label = DayParts(event.at)
                local day = dayMap[key]
                if not day then
                    day = { key = key, label = label, wins = 0, losses = 0, at = event.at or 0 }
                    dayMap[key] = day
                    dayOrder[#dayOrder + 1] = day
                end
                if meta.outcome == "win" then
                    day.wins = day.wins + 1
                else
                    day.losses = day.losses + 1
                end
            elseif meta.kind == "level" then
                local levels = meta.levels or 0
                report.levels = report.levels + levels
                if meta.reached25 then
                    report.level25 = report.level25 + 1
                end
                local petKey = meta.petKey or meta.petName or meta.detail or index
                local row = pets[petKey]
                if not row then
                    row = { name = meta.petName or "Pet", levels = 0 }
                    pets[petKey] = row
                    petOrder[#petOrder + 1] = row
                end
                if meta.petName and meta.petName ~= "" then
                    row.name = meta.petName
                end
                row.levels = row.levels + levels
            elseif meta.kind == "capture" then
                report.captured = report.captured + 1
                if meta.newSpecies then
                    report.newPets = report.newPets + 1
                end
                report.captures[#report.captures + 1] = {
                    at = event.at,
                    name = meta.petName,
                    detail = meta.detail,
                    text = event.text,
                }
            end
        elseif IsPet(event) then
            local meta = event.meta or {}
            if meta.captured then
                report.captured = report.captured + 1
            else
                report.newPets = report.newPets + 1
            end
        end
    end
    table.sort(dayOrder, function(a, b)
        return (a.at or 0) < (b.at or 0)
    end)
    report.days = dayOrder
    table.sort(petOrder, function(a, b)
        if a.levels == b.levels then
            return (a.name or "") < (b.name or "")
        end
        return a.levels > b.levels
    end)
    local top = {}
    for index = 1, math.min(5, #petOrder) do
        if petOrder[index].levels > 0 then
            top[#top + 1] = petOrder[index]
        end
    end
    report.topPets = top
    table.sort(report.captures, function(a, b)
        return (a.at or 0) > (b.at or 0)
    end)
    if #report.captures > 6 then
        local trimmed = {}
        for index = 1, 6 do
            trimmed[index] = report.captures[index]
        end
        report.captures = trimmed
    end
    return report
end

function WBF.PetBattles.EventsFor(startAt, endAt, guid)
    if not WBF.Database or not WBF.Database.Get then
        return {}
    end
    local source = WBF.Database.Get().events or {}
    local list = {}
    for index = 1, #source do
        local event = source[index]
        local at = event.at or 0
        local inRange = (not startAt or at >= startAt) and (not endAt or at <= endAt)
        local same = (not guid or event.guid == guid)
        if inRange and same and (IsPetBattle(event) or IsPet(event)) then
            list[#list + 1] = event
        end
    end
    return list
end

local function AddBattleEvent(partial)
    partial.category = partial.category or WBF.Category.Collection
    partial.eventType = partial.eventType or WBF.EventType.PetBattle
    return WBF.Events.Add(partial)
end

local function ReadPet(petID)
    if not petID or not C_PetJournal or not C_PetJournal.GetPetInfoByPetID then
        return nil
    end
    local ok, speciesID, customName, level, _, _, _, _, name, icon = pcall(C_PetJournal.GetPetInfoByPetID, petID)
    if not ok then
        return nil
    end
    level = tonumber(level)
    local display = customName
    if type(display) ~= "string" or display == "" then
        display = name
    end
    if type(display) ~= "string" or display == "" then
        display = nil
    end
    return {
        petID = petID,
        speciesID = tonumber(speciesID),
        name = display,
        level = level,
        icon = icon,
    }
end

local function SpeciesIsNew(speciesID)
    speciesID = tonumber(speciesID)
    if not speciesID or not C_PetJournal or not C_PetJournal.GetNumCollectedInfo then
        return false
    end
    local ok, num = pcall(C_PetJournal.GetNumCollectedInfo, speciesID)
    num = ok and tonumber(num) or nil
    return num == 1
end

local function SnapshotLoadout(state)
    if not C_PetJournal or not C_PetJournal.GetPetLoadOutInfo then
        return
    end
    for slot = 1, 3 do
        local ok, first = pcall(C_PetJournal.GetPetLoadOutInfo, slot)
        local petID = first
        if type(first) == "table" then
            petID = first.petID
        end
        if ok and type(petID) == "string" and petID ~= "" then
            local info = ReadPet(petID)
            if info then
                state.pets[petID] = info
                state.slotPet[slot] = petID
            end
        end
    end
end

local function DetectType(state)
    local wild, npc = false, false
    if C_PetBattles and C_PetBattles.IsWildBattle then
        local ok, value = pcall(C_PetBattles.IsWildBattle)
        wild = ok and value and true or false
    end
    if C_PetBattles and C_PetBattles.IsPlayerNPC then
        local ok, value = pcall(C_PetBattles.IsPlayerNPC, EnemyOwner())
        npc = ok and value and true or false
    end
    state.battleType = WBF.PetBattles.BattleKind(wild, npc)
    if state.battleType == "trainer" and UnitName then
        local ok, name = pcall(UnitName, "target")
        if ok and type(name) == "string" and name ~= "" then
            state.trainer = name
        end
    end
end

local function BattleDetail(state)
    if state.battleType == "trainer" then
        if state.trainer and state.trainer ~= "" then
            return "Trainer: " .. state.trainer
        end
        return "Trainer Battle"
    end
    if state.battleType == "pvp" then
        return "PvP Battle"
    end
    return "Wild Battle"
end

local function EmitLevels(state)
    for petID, snap in pairs(state.pets) do
        local pending = state.levels[petID]
        local current = ReadPet(petID)
        local fromLevel = pending and pending.from or snap.level
        local toLevel = pending and pending.to or nil
        if current and current.level and (not toLevel or current.level > toLevel) then
            toLevel = current.level
        end
        local folded = WBF.PetBattles.FoldLevels(snap.name, fromLevel, toLevel)
        if folded then
            AddBattleEvent({
                text = folded.eventLabel .. "  ·  " .. folded.detail,
                meta = {
                    kind = "level",
                    petKey = petID,
                    petName = folded.name,
                    speciesID = snap.speciesID,
                    fromLevel = folded.fromLevel,
                    toLevel = folded.toLevel,
                    levels = folded.levels,
                    reached25 = folded.reached25,
                    eventLabel = folded.eventLabel,
                    detail = folded.detail,
                    icon = snap.icon,
                },
            })
        end
    end
end

local function EmitCapture(force)
    if flushedCapture then
        return
    end
    if not pendingCapture and not pendingPet then
        return
    end
    if not force and not pendingCapture then
        return
    end
    if not force and battle and battle.open and not pendingPet then
        return
    end
    flushedCapture = true
    local cap = pendingCapture or {}
    local pet = pendingPet or {}
    local name = cap.name or pet.name
    local quality = cap.quality or pet.quality
    local level = cap.level or pet.level
    local speciesID = cap.speciesID or pet.speciesID
    local isNew = pet.isNew
    if isNew == nil then
        isNew = SpeciesIsNew(speciesID)
    end
    local described = WBF.PetBattles.DescribeCapture(name, quality, level, isNew)
    AddBattleEvent({
        text = described.eventLabel .. "  ·  " .. described.detail,
        dedupeKey = pet.petID and ("petcapture:" .. tostring(pet.petID)) or nil,
        meta = {
            kind = "capture",
            petName = name,
            petID = pet.petID,
            speciesID = speciesID,
            quality = WBF.PetBattles.QualityName(quality),
            level = tonumber(level),
            capturedLevel = tonumber(level),
            capturedQuality = tonumber(quality),
            newSpecies = described.newSpecies,
            eventLabel = described.eventLabel,
            detail = described.detail,
            icon = pet.icon,
        },
    })
    pendingCapture = nil
    pendingPet = nil
end

local function InCaptureWindow()
    if battle and battle.open then
        return true
    end
    return WBF.Time.Now() <= recentBattleUntil
end

local function EnemyPet(index)
    if not C_PetBattles or not C_PetBattles.GetName then
        return {}
    end
    index = tonumber(index) or 1
    local owner = EnemyOwner()
    local name, speciesID, level, quality
    local okName, readName = pcall(C_PetBattles.GetName, owner, index)
    if okName and type(readName) == "string" then
        name = readName
    end
    if C_PetBattles.GetPetSpeciesID then
        local okSpecies, readSpecies = pcall(C_PetBattles.GetPetSpeciesID, owner, index)
        speciesID = okSpecies and tonumber(readSpecies) or nil
    end
    if C_PetBattles.GetLevel then
        local okLevel, readLevel = pcall(C_PetBattles.GetLevel, owner, index)
        level = okLevel and tonumber(readLevel) or nil
    end
    if C_PetBattles.GetBreedQuality then
        local okQuality, readQuality = pcall(C_PetBattles.GetBreedQuality, owner, index)
        quality = okQuality and readQuality or nil
    end
    return {
        name = name,
        speciesID = speciesID,
        level = level,
        quality = quality,
    }
end

local function ActiveEnemyIndex()
    if C_PetBattles and C_PetBattles.GetActivePet then
        local ok, index = pcall(C_PetBattles.GetActivePet, EnemyOwner())
        index = ok and tonumber(index) or nil
        if index and index > 0 then
            return index
        end
    end
    return 1
end

function WBF.PetBattles.ClaimAdded(petID, info)
    info = info or {}
    if flushedCapture then
        return true
    end
    if not InCaptureWindow() and not pendingCapture then
        return false
    end
    info.petID = petID
    if info.isNew == nil then
        info.isNew = SpeciesIsNew(info.speciesID)
    end
    pendingPet = info
    EmitCapture(false)
    return true
end

function WBF.PetBattles.Register(bus)
    bus:On("PET_BATTLE_OPENING_START", function()
        if battle and battle.open then
            return
        end
        battle = {
            open = true,
            started = false,
            finished = false,
            battleType = "wild",
            trainer = nil,
            outcome = nil,
            pets = {},
            slotPet = {},
            levels = {},
        }
        pendingCapture = nil
        pendingPet = nil
        flushedCapture = false
        SnapshotLoadout(battle)
        DetectType(battle)
        if not battle.started then
            battle.started = true
            AddBattleEvent({
                text = "Pet battle started",
                meta = {
                    kind = "battleStart",
                    battleType = battle.battleType,
                    surface = false,
                    started = 1,
                },
            })
        end
    end)

    bus:On("PET_BATTLE_OPENING_DONE", function()
        if battle and battle.open then
            DetectType(battle)
        end
    end)

    bus:On("PET_BATTLE_LEVEL_CHANGED", function(owner, petIndex, newLevel)
        if not battle or not battle.open then
            return
        end
        if not SameOwner(owner, AllyOwner()) then
            return
        end
        petIndex = tonumber(petIndex)
        newLevel = tonumber(newLevel)
        if not petIndex or not newLevel then
            return
        end
        local petID = battle.slotPet[petIndex]
        if not petID then
            return
        end
        local snap = battle.pets[petID]
        WBF.PetBattles.NoteLevel(battle.levels, petID, snap and snap.name, newLevel, snap and snap.level)
    end)

    bus:On("PET_BATTLE_CAPTURED", function()
        if not InCaptureWindow() and not (battle and battle.open) then
            return
        end
        pendingCapture = EnemyPet(ActiveEnemyIndex())
        EmitCapture(false)
    end)

    bus:On("PET_BATTLE_FINAL_ROUND", function(winner)
        if not battle or battle.finished then
            return
        end
        battle.finished = true
        battle.outcome = SameOwner(winner, AllyOwner()) and "win" or "loss"
    end)

    bus:On("PET_BATTLE_CLOSE", function()
        if not battle then
            EmitCapture(true)
            return
        end
        local state = battle
        state.open = false
        recentBattleUntil = WBF.Time.Now() + 8
        EmitLevels(state)
        EmitCapture(true)
        if state.outcome and not state.completed then
            state.completed = true
            local label = state.outcome == "win" and "Battle won" or "Battle lost"
            local detail = BattleDetail(state)
            AddBattleEvent({
                text = label .. "  ·  " .. detail,
                meta = {
                    kind = "battle",
                    outcome = state.outcome,
                    battleType = state.battleType,
                    trainer = state.trainer,
                    eventLabel = label,
                    detail = detail,
                    completed = 1,
                },
            })
        end
        battle = nil
    end)
end
