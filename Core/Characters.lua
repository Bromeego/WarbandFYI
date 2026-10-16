local _, WBF = ...

-- A character is tracked only after this addon has loaded while logged into
-- them. Account currency data can name other alts, but those records stay
-- undiscovered until a real login. Identity is the player GUID. A name plus
-- realm is only a fallback for older records that were stored without one.

WBF.Characters = {}

local currentGuid = nil

local COPY_FIELDS = {
    "name",
    "realm",
    "className",
    "classFile",
    "raceFile",
    "specName",
    "role",
    "faction",
    "level",
    "itemLevel",
    "money",
}

local function IsPlayerGuid(value)
    return type(value) == "string" and value:sub(1, 7) == "Player-"
end

local function Stamp(value)
    if type(value) == "number" and value > 0 then
        return value
    end
    return nil
end

local function Note(observed, guid, at)
    if type(guid) ~= "string" or guid == "" then
        return
    end
    local stamped = Stamp(at)
    local previous = observed[guid]
    if stamped and (type(previous) ~= "number" or stamped < previous) then
        observed[guid] = stamped
    elseif previous == nil then
        observed[guid] = true
    end
end

local function FillMissing(dest, src)
    for index = 1, #COPY_FIELDS do
        local field = COPY_FIELDS[index]
        if dest[field] == nil or dest[field] == "" then
            dest[field] = src[field]
        end
    end
    local seen = Stamp(src.firstSeen)
    if seen and (not Stamp(dest.firstSeen) or seen < dest.firstSeen) then
        dest.firstSeen = seen
    end
    if src.discovered == true then
        dest.discovered = true
    end
end

local function MoveMapKey(map, fromKey, toKey)
    if type(map) ~= "table" or fromKey == toKey or map[fromKey] == nil then
        return
    end
    if map[toKey] == nil then
        map[toKey] = map[fromKey]
    elseif type(map[toKey]) == "table" and type(map[fromKey]) == "table" and map[toKey].netChange ~= nil then
        map[toKey].netChange = (map[toKey].netChange or 0) + (map[fromKey].netChange or 0)
        if map[toKey].baseline == nil then
            map[toKey].baseline = map[fromKey].baseline
        end
    end
    map[fromKey] = nil
end

local function RewriteGuid(db, fromKey, toGuid)
    if not fromKey or fromKey == toGuid then
        return
    end
    local function swap(guid)
        if guid == fromKey then
            return toGuid
        end
        return guid
    end
    local snapshots = db.snapshots or {}
    for index = 1, #snapshots do
        local snapshot = snapshots[index]
        if type(snapshot) == "table" then
            snapshot.guid = swap(snapshot.guid)
        end
    end
    local events = db.events or {}
    for index = 1, #events do
        local event = events[index]
        if type(event) == "table" then
            event.guid = swap(event.guid)
        end
    end
    local sessions = db.sessions or {}
    for index = 1, #sessions do
        local session = sessions[index]
        if type(session) == "table" then
            local segments = session.segments or {}
            for segmentIndex = 1, #segments do
                local segment = segments[segmentIndex]
                if type(segment) == "table" then
                    segment.guid = swap(segment.guid)
                end
            end
            MoveMapKey(session.goldByCharacter, fromKey, toGuid)
            local ledger = session.goldLedger or {}
            for entryIndex = 1, #ledger do
                local entry = ledger[entryIndex]
                if type(entry) == "table" then
                    entry.guid = swap(entry.guid)
                end
            end
        end
    end
    if type(db.goldLast) == "table" and fromKey ~= toGuid then
        if db.goldLast[toGuid] == nil then
            db.goldLast[toGuid] = db.goldLast[fromKey]
        end
        db.goldLast[fromKey] = nil
    end
    if type(db.resources) == "table" and type(db.resources.balances) == "table" then
        for _, state in pairs(db.resources.balances) do
            if type(state) == "table" then
                MoveMapKey(state.characters, fromKey, toGuid)
                MoveMapKey(state.names, fromKey, toGuid)
                MoveMapKey(state.scanned, fromKey, toGuid)
                MoveMapKey(state.sources, fromKey, toGuid)
            end
        end
    end
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
end

-- One non-GUID record with the same name and realm can be adopted. A second
-- match is ambiguous, and a different player GUID is never merged.
local function FindLegacyKey(db, name, realm, guid)
    if type(name) ~= "string" or name == "" or type(realm) ~= "string" or realm == "" then
        return nil
    end
    local found
    for key, character in pairs(db.characters) do
        if key ~= guid and type(character) == "table" and character.name == name and character.realm == realm then
            local recordGuid = character.guid
            local otherPlayer = (IsPlayerGuid(key) and key ~= guid) or (IsPlayerGuid(recordGuid) and recordGuid ~= guid)
            if not otherPlayer then
                if found then
                    return nil
                end
                found = key
            end
        end
    end
    return found
end

local function AbsorbLegacy(db, guid, name, realm)
    local legacyKey = FindLegacyKey(db, name, realm, guid)
    if not legacyKey then
        return db.characters[guid]
    end
    local legacy = db.characters[legacyKey]
    local character = db.characters[guid]
    if character and character ~= legacy then
        FillMissing(character, legacy)
        db.characters[legacyKey] = nil
        RewriteGuid(db, legacyKey, guid)
        return character
    end
    db.characters[legacyKey] = nil
    db.characters[guid] = legacy
    legacy.guid = guid
    RewriteGuid(db, legacyKey, guid)
    return legacy
end

local function HasObservedFields(character)
    if character.discovered == true then
        return true
    end
    if Stamp(character.firstSeen) or Stamp(character.lastSeenAt) or Stamp(character.updatedAt) then
        return true
    end
    if type(character.level) == "number" or type(character.itemLevel) == "number" or type(character.money) == "number" then
        return true
    end
    if type(character.classFile) == "string" and character.classFile ~= "" then
        return true
    end
    if type(character.raceFile) == "string" and character.raceFile ~= "" then
        return true
    end
    if type(character.faction) == "string" and character.faction ~= "" then
        return true
    end
    if type(character.specName) == "string" and character.specName ~= "" then
        return true
    end
    return false
end

local function MarkDiscovered(character, now)
    local first = Stamp(character.firstSeen) or Stamp(character.lastSeenAt)
    character.discovered = true
    if not Stamp(character.firstSeen) then
        character.firstSeen = first or now
    end
    character.lastSeenAt = now
end

function WBF.Characters.GetCurrent()
    if not currentGuid then
        return nil
    end
    return WarbandFYI_DB.characters[currentGuid]
end

function WBF.Characters.GetGuid()
    return currentGuid
end

function WBF.Characters.Get(guid)
    if not guid or not WarbandFYI_DB or type(WarbandFYI_DB.characters) ~= "table" then
        return nil
    end
    return WarbandFYI_DB.characters[guid]
end

function WBF.Characters.IsDiscovered(characterOrGuid)
    local character = characterOrGuid
    if type(characterOrGuid) ~= "table" then
        character = WBF.Characters.Get(characterOrGuid)
    elseif characterOrGuid.discovered ~= true then
        local stored = WBF.Characters.Get(characterOrGuid.guid)
        if stored then
            character = stored
        end
    end
    return type(character) == "table" and character.discovered == true
end

function WBF.Characters.List()
    local list = {}
    local characters = WarbandFYI_DB and WarbandFYI_DB.characters or {}
    for _, character in pairs(characters) do
        if type(character) == "table" and character.discovered == true then
            list[#list + 1] = character
        end
    end
    return list
end

function WBF.Characters.Migrate(db)
    if type(db) ~= "table" then
        return
    end
    if type(db.characters) ~= "table" then
        db.characters = {}
    end

    local observed = {}
    local snapshots = db.snapshots or {}
    for index = 1, #snapshots do
        local snapshot = snapshots[index]
        if type(snapshot) == "table" then
            Note(observed, snapshot.guid, snapshot.at)
        end
    end

    local sessions = db.sessions or {}
    for index = 1, #sessions do
        local session = sessions[index]
        if type(session) == "table" then
            local segments = session.segments or {}
            for segmentIndex = 1, #segments do
                local segment = segments[segmentIndex]
                if type(segment) == "table" then
                    Note(observed, segment.guid, segment.startedAt)
                end
            end
            if type(session.goldByCharacter) == "table" then
                for guid, state in pairs(session.goldByCharacter) do
                    local at = type(state) == "table" and state.establishedAt or nil
                    Note(observed, guid, at)
                end
            end
            local ledger = session.goldLedger or {}
            for entryIndex = 1, #ledger do
                local entry = ledger[entryIndex]
                if type(entry) == "table" then
                    Note(observed, entry.guid, entry.at)
                end
            end
        end
    end

    local events = db.events or {}
    for index = 1, #events do
        local event = events[index]
        if type(event) == "table" and event.eventType ~= "resource" then
            Note(observed, event.guid, event.at)
        end
    end

    for guid, at in pairs(observed) do
        if type(db.characters[guid]) ~= "table" then
            local created = {
                discovered = true,
                firstSeen = Stamp(at),
            }
            if IsPlayerGuid(guid) then
                created.guid = guid
            end
            db.characters[guid] = created
        end
    end

    for key, character in pairs(db.characters) do
        if type(character) == "table" then
            if IsPlayerGuid(key) and (type(character.guid) ~= "string" or character.guid == "") then
                character.guid = key
            end
            local identity = (type(character.guid) == "string" and character.guid ~= "" and character.guid) or nil
            local genuine = HasObservedFields(character) or (identity and observed[identity] ~= nil) or (type(key) == "string" and observed[key] ~= nil)
            if genuine then
                character.discovered = true
                if not Stamp(character.firstSeen) then
                    local at = (identity and Stamp(observed[identity])) or (type(key) == "string" and Stamp(observed[key])) or nil
                    character.firstSeen = at or Stamp(character.lastSeenAt) or Stamp(character.updatedAt)
                end
            else
                character.discovered = false
            end
        end
    end
end

function WBF.Characters.Update()
    if not UnitExists("player") then
        return nil
    end

    local guid = UnitGUID("player")
    if not guid then
        return nil
    end

    local name, realm = UnitName("player")
    realm = realm or GetRealmName()
    local className, classFile = UnitClass("player")
    local _, raceFile = UnitRace("player")
    local faction
    if UnitFactionGroup then
        faction = UnitFactionGroup("player")
    end
    if WBF.Format and WBF.Format.PlainString then
        faction = WBF.Format.PlainString(faction)
    elseif type(faction) ~= "string" or faction == "" then
        faction = nil
    end

    local specName, role
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex and GetSpecializationInfo then
        local _, spec, _, _, specRole = GetSpecializationInfo(specIndex)
        specName = spec
        role = specRole
    end

    local db = WBF.Database.Get()
    local character = AbsorbLegacy(db, guid, name, realm)
    if not character then
        character = { guid = guid }
        db.characters[guid] = character
    end

    local changed = character.name ~= (name or character.name)
        or character.realm ~= (realm or character.realm)
        or character.classFile ~= (classFile or character.classFile)
        or character.specName ~= (specName or character.specName)
        or (faction and character.faction ~= faction)
    character.guid = guid
    character.name = name or character.name
    character.realm = realm or character.realm
    character.className = className or character.className
    character.classFile = classFile or character.classFile
    character.raceFile = raceFile or character.raceFile
    if faction then
        character.faction = faction
    end
    if specName then
        character.specName = specName
        character.role = role
    end
    MarkDiscovered(character, WBF.Time.Now())
    if changed and WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end

    currentGuid = guid
    return character
end
