local _, WBF = ...

-- Collection Hunts: opt-in legacy raid targets. No external item database, no
-- automatic loot-eligibility claims and no synthetic FYI/Notebook entries.
WBF.CollectionHunts = {}
local Hunts = WBF.CollectionHunts

local catalog = {
    thoridal = { title = "Thori'dal, the Stars' Fury", instance = "Sunwell Plateau", boss = "Kil'jaeden", itemID = 34334, achievementID = 725, defaultGoal = "achievement", equipClasses = { HUNTER = true, WARRIOR = true, ROGUE = true } },
    onyxian = { title = "Onyxian Drake", instance = "Onyxia's Lair", boss = "Onyxia", itemID = 49636, mountSpellID = 69395, defaultGoal = "mount" },
    southwind = { title = "Drake of the South Wind", instance = "Throne of the Four Winds", boss = "Al'Akir", itemID = 63041, mountSpellID = 88744, defaultGoal = "mount" },
}
local ordered = { "thoridal", "onyxian", "southwind" }
-- Curated source registry is maintained in Tracking/CollectionSources.lua.
-- Registry entries define source, collection type, completion and restrictions.
-- Collection Hunts remains responsible for saved state and per-character lockouts.
local sourceRegistry = WBF.CollectionSources.Entries
local sourceKeys = WBF.CollectionSources.Keys
local scanReady = false

-- Mount Journal is the authoritative source for discovery and ownership.
-- Index once per session; search only this local cache, never scan on each keystroke.
local mountIndex, mountByID
local function MountIndex()
    if mountIndex then return mountIndex end
    if not (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID) then return {} end
    local ids = C_MountJournal.GetMountIDs()
    if type(ids) ~= "table" then return {} end
    local index, byID = {}, {}
    for _, id in ipairs(ids) do
        local name, spellID, icon, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(id)
        if type(name) == "string" and type(spellID) == "number" then
            local sourceText = C_MountJournal.GetMountInfoExtraByID and select(3, C_MountJournal.GetMountInfoExtraByID(id)) or nil
            local entry = {id=id, name=name, spellID=spellID, icon=icon, collected=collected == true, sourceText=sourceText}
            index[#index+1] = entry
            byID[id] = entry
        end
    end
    table.sort(index, function(a,b) return a.name:lower() < b.name:lower() end)
    mountIndex, mountByID = index, byID
    return index
end
function Hunts.RefreshMountJournal() mountIndex, mountByID = nil, nil end
function Hunts.Mount(id)
    MountIndex()
    return mountByID and mountByID[tonumber(id)]
end
function Hunts.FindMounts(query, limit)
    query = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if #query < 2 then return {} end
    local found = {}
    for _, entry in ipairs(MountIndex()) do
        if entry.name:lower():find(query, 1, true) then
            found[#found+1] = entry
            if #found >= (limit or 8) then break end
        end
    end
    return found
end
function Hunts.MountSourceKey(mountID)
    local entry = Hunts.Mount(mountID)
    if not entry then return nil end
    for _, key in ipairs(sourceKeys) do
        if sourceRegistry[key].mountSpellID == entry.spellID then return key end
    end
end

local function ItemName(itemID)
    local getter = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return WBF.Format.PlainString((WBF.Format.SafeCall(getter, itemID)))
end

local function Store()
    local db = WBF.Database.Get()
    if type(db.collectionHunts) ~= "table" then db.collectionHunts = {} end
    local data = db.collectionHunts
    if type(data.enabled) ~= "table" then data.enabled = {} end
    if type(data.lockouts) ~= "table" then data.lockouts = {} end
    if type(data.settings) ~= "table" then data.settings = {} end
    if type(data.custom) ~= "table" then data.custom = {} end
    if type(data.hidden) ~= "table" then data.hidden = {} end
    if type(data.completed) ~= "table" then data.completed = {} end
    if type(data.daily) ~= "table" then data.daily = {} end
    if type(data.sources) ~= "table" then data.sources = {} end
    for key, entry in pairs(data.sources) do
        if type(key) == "string" and type(entry) == "table" and type(entry.instance) == "string" and type(entry.boss) == "string" then
            Hunts.RegisterSource(key, entry)
        end
    end
    for key, target in pairs(data.custom) do
        if type(target) == "table" then
            -- Migrate older custom item hunts for explicitly known mount drops.
            -- Do not alter unrelated items or player-selected appearance/achievement goals.
            if type(target.itemID) == "number" then
                for _, sourceKey in ipairs(sourceKeys) do
                    local source = sourceRegistry[sourceKey]
                    for _, knownID in ipairs(source.itemIDs or {}) do
                        if knownID == target.itemID and source.mountSpellID and source.instance == target.instance and source.boss == target.boss then
                            target.mountSpellID = source.mountSpellID
                            target.defaultGoal = "mount"
                            local opts = data.settings[key]
                            if type(opts) == "table" and opts.goal == "item" then
                                opts.goal = "mount"
                            end
                            break
                        end
                    end
                end
            end
            if type(target.mountID) == "number" and Hunts.Mount(target.mountID) then
                local mount = Hunts.Mount(target.mountID)
                target.title, target.mountSpellID, target.mountIcon = mount.name, mount.spellID, mount.icon
            elseif type(target.itemID) == "number" then
                local name = ItemName(target.itemID)
                if name then target.title = name end
            elseif type(target.achievementID) == "number" and GetAchievementInfo then
                local _, name = GetAchievementInfo(target.achievementID)
                if type(name) == "string" then target.title = name end
            end
        end
        if type(key) == "string" and type(target) == "table" and type(target.title) == "string" and (target.goalOnly == true or (type(target.instance) == "string" and type(target.boss) == "string")) and (type(target.itemID) == "number" or type(target.achievementID) == "number" or type(target.mountID) == "number" or type(target.petSpeciesID) == "number") and not catalog[key] then
            catalog[key] = target
            ordered[#ordered + 1] = key
        end
    end
    return data
end

function Hunts.Source(key)
    return sourceRegistry[key]
end
function Hunts.Sources()
    local options = {}
    for _, key in ipairs(sourceKeys) do
        local entry = sourceRegistry[key]
        options[#options+1] = { key=key, instance=entry.instance, boss=entry.boss, note=entry.note, difficulty=entry.difficulty, collectionType=entry.collectionType, daily=entry.daily }
    end
    return options
end

-- Accept exact known collectible names/aliases. Do not guess a match from
-- partial names: mistaking an unrelated item for a mount would be misleading.
local function NormalizeName(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end
function Hunts.ResolveKnownName(value)
    local wanted = NormalizeName(value)
    if wanted == "" then return nil end
    for _, key in ipairs(sourceKeys) do
        local source = sourceRegistry[key]
        if NormalizeName(source.title) == wanted then return source.itemIDs and source.itemIDs[1], key end
        for _, alias in ipairs(source.aliases or {}) do
            if NormalizeName(alias) == wanted then return source.itemIDs and source.itemIDs[1], key end
        end
    end
end

-- Automatic boss selection only happens for explicitly curated item IDs.
-- An achievement or unknown item must have its source chosen manually.
function Hunts.KnownSource(link)
    local id = tonumber(tostring(link or ""):match("item:(%d+)")) or tonumber(tostring(link or ""):match("^%s*(%d+)%s*$"))
    if not id then local _, key = Hunts.ResolveKnownName(link); return key end
    for _, key in ipairs(sourceKeys) do
        for _, itemID in ipairs(sourceRegistry[key].itemIDs or {}) do
            if itemID == id then return key end
        end
    end
end

-- Uses the learned state from the Mount Journal, not the mount item in bags.
-- nil means no reliable Journal result is available yet.
local function MountCollected(spellID)
    if type(spellID) ~= "number" or not (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID) then return nil end
    for _, entry in ipairs(MountIndex()) do
        if entry.spellID == spellID then
            local _, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(entry.id)
            return collected == true
        end
    end
    return nil
end

-- Pet Journal ownership, by species. nil means the Journal gave no answer.
local function PetCollected(speciesID)
    if type(speciesID) ~= "number" or not (C_PetJournal and C_PetJournal.GetNumCollectedInfo) then return nil end
    local owned = WBF.Format.SafeCall(C_PetJournal.GetNumCollectedInfo, speciesID)
    if type(owned) ~= "number" then return nil end
    return owned > 0
end
-- A caged or learnable pet item names its species; other items return nil.
local function PetSpeciesForItem(itemID)
    if type(itemID) ~= "number" or not (C_PetJournal and C_PetJournal.GetPetInfoByItemID) then return nil end
    local speciesID = select(13, WBF.Format.SafeCall(C_PetJournal.GetPetInfoByItemID, itemID))
    return type(speciesID) == "number" and speciesID > 0 and speciesID or nil
end
local function PetName(speciesID)
    if not (C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID) then return nil end
    return WBF.Format.PlainString((WBF.Format.SafeCall(C_PetJournal.GetPetInfoBySpeciesID, speciesID)))
end

function Hunts.Preview(link)
    local id = tonumber(tostring(link or ""):match("item:(%d+)")) or tonumber(tostring(link or ""):match("^%s*(%d+)%s*$"))
    if not id then id = Hunts.ResolveKnownName(link) end
    if not id then return nil end
    local key = Hunts.KnownSource(link)
    local source = key and sourceRegistry[key]
    if not source or not source.mountSpellID then return nil end
    return { mount = true, collected = MountCollected(source.mountSpellID), sourceKey = key }
end

local function ParseTarget(link)
    local text = tostring(link or "")
    local mount = tonumber(text:match("^%s*mount:(%d+)%s*$"))
    if mount then return "mount", mount end
    -- Shift-clicking a pet in the Pet Journal gives a battlepet link.
    local pet = tonumber(text:match("battlepet:(%d+)"))
    if pet then return "pet", pet end
    local achievement = tonumber(text:match("achievement:(%d+)"))
    if achievement then return "achievement", achievement end
    local item = tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
    if item then return "item", item end
    local knownID = Hunts.ResolveKnownName(text)
    if knownID then return "item", knownID end
end

-- The Journal's own "where it comes from" text, for a mount, a pet, or an
-- item that teaches one. Same text as the Journal tooltip, e.g.
-- "|cFFFFD200Drop:|r Headless Horseman|n|cFFFFD200Zone:|r Scarlet Monastery".
local function JournalSourceText(kind, id)
    if kind == "item" then
        local species = PetSpeciesForItem(id)
        if species then
            kind, id = "pet", species
        elseif C_MountJournal and C_MountJournal.GetMountFromItem then
            local mountID = WBF.Format.AsNumber((WBF.Format.SafeCall(C_MountJournal.GetMountFromItem, id)))
            if not mountID then return nil end
            kind, id = "mount", mountID
        else
            return nil
        end
    end
    if kind == "mount" then
        local mount = Hunts.Mount(id)
        return mount and WBF.Format.PlainString(mount.sourceText)
    end
    if kind == "pet" and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        return WBF.Format.PlainString((select(5, WBF.Format.SafeCall(C_PetJournal.GetPetInfoBySpeciesID, id))))
    end
end

-- Journal source text as { label, value } lines with colours and icons removed.
function Hunts.SourceLines(text)
    local lines = {}
    text = WBF.Format.PlainString(text)
    if not text then return lines end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|n", "\n")
    for line in text:gmatch("[^\n]+") do
        local label, value = line:match("^%s*(.-)%s*:%s*(.-)%s*$")
        if label and value ~= "" then
            lines[#lines + 1] = { label = label, value = value }
        elseif line:match("%S") then
            lines[#lines + 1] = { value = line:gsub("^%s+", ""):gsub("%s+$", "") }
        end
    end
    return lines
end

-- Match Journal source text to a curated source by boss name, preferring one
-- whose instance also appears. Only curated sources are returned: a boss the
-- registry does not know is reported, never guessed.
function Hunts.SourceFromText(text)
    local lines = Hunts.SourceLines(text)
    local values = {}
    for _, line in ipairs(lines) do values[NormalizeName(line.value)] = true end
    local best, bestScore, tied = nil, 0, false
    for _, key in ipairs(sourceKeys) do
        local source = sourceRegistry[key]
        local placed = values[NormalizeName(source.instance)]
        -- A source found in the Encounter Journal needs its raid named too.
        if values[NormalizeName(source.boss)] and (placed or not source.fromJournal) then
            local score = placed and 2 or 1
            if score > bestScore then
                best, bestScore, tied = key, score, false
            elseif score == bestScore then
                tied = true
            end
        end
    end
    if tied then best = nil end
    return best, lines
end

-- Adds a source to the registry for this session. Curated entries are never
-- replaced.
function Hunts.RegisterSource(key, entry)
    if sourceRegistry[key] then return key end
    sourceRegistry[key] = entry
    sourceKeys[#sourceKeys + 1] = key
    return key
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return WBF.Format.SafeCall(fn, ...)
end

-- Looks a boss up in the Encounter Journal inside the named raid or
-- dungeon. Both names must match a real journal instance and encounter, so a
-- source is never invented from loose text. The journal's selected tier is
-- restored afterwards.
function Hunts.FindEncounter(bossName, instanceName)
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex) then return nil end
    local wantedBoss, wantedInstance = NormalizeName(bossName), NormalizeName(instanceName)
    if wantedBoss == "" or wantedInstance == "" then return nil end
    local tiers = WBF.Format.AsNumber(Call(EJ_GetNumTiers)) or 0
    local previous = WBF.Format.AsNumber(Call(EJ_GetCurrentTier))
    local found
    for tier = tiers, 1, -1 do
        Call(EJ_SelectTier, tier)
        for _, isRaid in ipairs({ true, false }) do
            for index = 1, 200 do
                local instanceID, name = Call(EJ_GetInstanceByIndex, index, isRaid)
                if not instanceID then break end
                if NormalizeName(name) == wantedInstance then
                    for encounterIndex = 1, 40 do
                        local encounterName, _, encounterID = Call(EJ_GetEncounterInfoByIndex, encounterIndex, instanceID)
                        if not encounterName then break end
                        if NormalizeName(encounterName) == wantedBoss then
                            found = { instance = name, boss = encounterName, journalInstanceID = instanceID,
                                journalEncounterID = encounterID, isRaid = isRaid }
                            break
                        end
                    end
                end
                if found then break end
            end
            if found then break end
        end
        if found then break end
    end
    if previous then Call(EJ_SelectTier, previous) end
    return found
end

-- A source for Journal source lines that the Encounter Journal confirms: one
-- line names a boss and another names the raid or dungeon it is in.
local function EncounterFromLines(lines)
    for _, bossLine in ipairs(lines) do
        for _, placeLine in ipairs(lines) do
            if placeLine ~= bossLine then
                local found = Hunts.FindEncounter(bossLine.value, placeLine.value)
                if found then return found end
            end
        end
    end
end

-- Source for a target, read from the Journal's source text. A curated source
-- wins (it carries special rules such as a required difficulty); otherwise
-- an Encounter Journal match becomes a source of its own. Returns the source
-- key (or nil) and the Journal's source lines.
function Hunts.JournalSource(kind, id)
    local text = JournalSourceText(kind, id)
    if not text then return nil, {} end
    local key, lines = Hunts.SourceFromText(text)
    if key then return key, lines end
    local found = EncounterFromLines(lines)
    if not found then return nil, lines end
    key = "ej" .. tostring(found.journalEncounterID or (NormalizeName(found.instance) .. NormalizeName(found.boss)))
    Hunts.RegisterSource(key, {
        instance = found.instance, boss = found.boss, isRaid = found.isRaid,
        journalInstanceID = found.journalInstanceID, journalEncounterID = found.journalEncounterID,
        fromJournal = true, note = "From the Encounter Journal; difficulty not verified",
    })
    return key, lines
end

-- What a typed or Shift-clicked target is: "mount", "pet", "achievement" or
-- "item", and its ID. nil when the text is none of these.
Hunts.TargetKind = ParseTarget

-- Explicit source selection: an item link alone cannot establish its drop source.
-- The source key for a hunt with no boss: a quest reward, vendor item, world
-- drop or secret. It is tracked until collected and has no weekly lockout.
Hunts.GOAL = "goal"

-- "Vendor: Breanni, Zone: Dalaran" from the Journal, or nil.
function Hunts.WhereText(kind, id)
    local text = kind and JournalSourceText(kind, id)
    if not text then return nil end
    local parts = {}
    for _, line in ipairs(Hunts.SourceLines(text)) do
        parts[#parts + 1] = line.label and (line.label .. ": " .. line.value) or line.value
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

function Hunts.AddTarget(link, sourceKey, where)
    local kind, id = ParseTarget(link)
    local goalOnly = sourceKey == Hunts.GOAL
    local source = not goalOnly and sourceRegistry[sourceKey] or nil
    if not id then return nil, "Search for a mount and pick it from the list, enter an item ID, or Shift-click an item or pet (or use Use Current Selection)." end
    if not source and not goalOnly then return nil, "Choose where it drops, or choose Not a boss drop to track it as a goal." end
    local data = Store()
    if source and source.fromJournal then data.sources[sourceKey] = source end
    local key = kind .. id .. "_" .. sourceKey
    if not catalog[key] then
        local title
        local petSpeciesID = kind == "pet" and id or (kind == "item" and PetSpeciesForItem(id)) or nil
        if kind == "pet" then
            title = PetName(id) or ("Pet #" .. id)
        elseif kind == "mount" then
            local mount = Hunts.Mount(id)
            if not mount then return nil, "Mount not found in the Mount Journal." end
            title = mount.name
        elseif kind == "achievement" then
            if GetAchievementInfo then local achievementID, name = GetAchievementInfo(id); title = name end
            if type(title) ~= "string" or title == "" then title = "Achievement #" .. id end
        else
            title = ItemName(id) or (petSpeciesID and PetName(petSpeciesID)) or ("Item #" .. id)
        end
        local knownMount = kind == "item" and Hunts.Preview(link)
        local journalMount = kind == "mount" and Hunts.Mount(id)
        data.custom[key] = { title=title, itemID=kind == "item" and id or nil,
            mountID=journalMount and id or nil, mountIcon=journalMount and journalMount.icon or nil,
            mountSpellID=(journalMount and journalMount.spellID) or (knownMount and source and sourceKey == knownMount.sourceKey and source.mountSpellID or nil),
            achievementID=kind == "achievement" and id or nil,
            petSpeciesID=petSpeciesID,
            instance=source and source.instance or nil, boss=source and source.boss or nil,
            goalOnly=goalOnly or nil,
            where=goalOnly and (type(where) == "string" and where:match("%S") and where or Hunts.WhereText(kind, id)) or nil,
            defaultGoal=(kind == "mount" and "mount") or (kind == "achievement" and "achievement") or (petSpeciesID and "pet") or (knownMount and source and sourceKey == knownMount.sourceKey and "mount" or "item"),
            custom=true, sourceKey=not goalOnly and sourceKey or nil, sourceNote=source and source.note or nil }
        catalog[key] = data.custom[key]
        ordered[#ordered + 1] = key
    end
    data.enabled[key] = true
    data.hidden[key] = nil
    return key
end
Hunts.AddItem = Hunts.AddTarget -- preserve older callers

-- Achievement completion is account-level where Blizzard flags it as such.
-- Raid lockout attempts remain a separate, per-character measurement.
function Hunts.AchievementComplete(key)
    Store()
    local entry = catalog[key]
    if not entry or not entry.achievementID or not GetAchievementInfo then return false end
    local _, _, _, completed = GetAchievementInfo(entry.achievementID)
    return completed == true
end

-- Collection completion is distinct from having attempted a raid this week.
-- The known legendary Feat of Strength is 725. Mount checks use the Mount
-- Journal's collected flag, not inventory possession of a mount item.
function Hunts.Completion(key)
    local data = Store()
    local target = catalog[key]
    if not target then return false end
    if data.completed[key] == true then return true, "manual" end
    local goal
    local setting = data.settings[key]
    goal = (type(setting) == "table" and setting.goal) or target.defaultGoal
    if goal == "achievement" and target.achievementID and GetAchievementInfo then
        local _, _, _, complete = GetAchievementInfo(target.achievementID)
        if complete == true then return true, "achievement" end
    end
    if goal == "mount" and target.mountSpellID and MountCollected(target.mountSpellID) == true then
        return true, "mount"
    end
    if goal == "pet" and target.petSpeciesID and PetCollected(target.petSpeciesID) == true then
        return true, "pet"
    end
    if goal == "appearance" and target.itemID and C_TransmogCollection and C_TransmogCollection.PlayerHasTransmog
        and WBF.Format.SafeCall(C_TransmogCollection.PlayerHasTransmog, target.itemID) == true then
        return true, "appearance"
    end
    return false
end
function Hunts.SetCompleted(key, completed)
    local data = Store()
    if not catalog[key] then return false end
    data.completed[key] = completed and true or nil
    if WBF.UI and WBF.UI.RequestRefresh then WBF.UI.RequestRefresh() end
    return true
end

-- Removing a preset only hides it from the user's list; custom entries are deleted.
-- Both operations clean up per-hunt settings but retain raid scan data for other hunts.
function Hunts.IsHidden(key)
    return Store().hidden[key] == true
end
function Hunts.Remove(key)
    local data = Store()
    if not catalog[key] then return false end
    data.enabled[key] = nil
    data.settings[key] = nil
    data.completed[key] = nil
    if data.custom[key] then
        data.custom[key] = nil
        catalog[key] = nil
        for i = #ordered, 1, -1 do
            if ordered[i] == key then table.remove(ordered, i) end
        end
        data.hidden[key] = nil
    else
        data.hidden[key] = true
    end
    return true
end
function Hunts.Restore(key)
    local data = Store()
    if not catalog[key] or data.custom[key] then return false end
    data.hidden[key] = nil
    data.enabled[key] = true
    return true
end
function Hunts.Catalog() Store(); return catalog, ordered end
function Hunts.IsEnabled(key) Store(); return catalog[key] and Store().enabled[key] == true end
function Hunts.SetEnabled(key, enabled)
    Store()
    if not catalog[key] then return false end
    Store().enabled[key] = enabled and true or nil
    if WBF.UI and WBF.UI.RequestRefresh then WBF.UI.RequestRefresh() end
    return true
end
function Hunts.Active()
    Store()
    local enabled = Store().enabled
    local result = {}
    for _, key in ipairs(ordered) do
        if enabled[key] then result[#result + 1] = { key = key, info = catalog[key] } end
    end
    return result
end

local validGoals = { achievement = true, appearance = true, item = true, mount = true, pet = true }
local function Settings(key)
    local data = Store()
    if type(data.settings[key]) ~= "table" then data.settings[key] = {} end
    local setting = data.settings[key]
    if not validGoals[setting.goal] then setting.goal = catalog[key].defaultGoal end
    if setting.characterMode ~= "selected" then setting.characterMode = "all" end
    if type(setting.selected) ~= "table" then setting.selected = {} end
    return setting
end
function Hunts.Settings(key)
    Store()
    if not catalog[key] then return nil end
    return Settings(key)
end

-- This is an explicit, conservative rule set, not a general-purpose loot database.
-- For non-mount items with no established class rule, mark as unverified.
function Hunts.Eligibility(key, guid)
    Store()
    local target = catalog[key]
    if not target then return "unknown" end
    local setting = Settings(key)
    if setting.characterMode == "selected" and not setting.selected[guid] then return "excluded" end
    local character = WBF.Characters and WBF.Characters.Get and WBF.Characters.Get(guid)
    if not character then return "unknown" end
    -- Every character gets its own daily bag, whatever the class.
    local source = target.sourceKey and sourceRegistry[target.sourceKey]
    if source and source.daily then return "eligible" end
    local class = character.classFile
    -- Battle pet drops have no class or armour restriction.
    if setting.goal == "pet" and target.petSpeciesID then return "eligible" end
    if setting.goal == "mount" then
        if target.mountSpellID then return "eligible" end
        return "unknown"
    end
    if key == "thoridal" and setting.goal == "achievement" then
        if not class or class == "" then return "unknown" end
        return target.equipClasses[class] and "eligible" or "ineligible"
    end
    -- A manually chosen character represents the user's chosen farming roster,
    -- not proof of loot or achievement eligibility. Keep status unverified.
    -- An appearance may be learnable without equipping in modern Retail.
    -- We cannot prove eligibility for generic item/appearance goals here.
    return "unknown"
end

local function Norm(s)
    if type(s) ~= "string" then return "" end
    return s:lower():gsub("[^%w]", "")
end

-- A saved instance can have multiple difficulty records. Do not combine their
-- defeated bosses, especially for mounts restricted to a specific difficulty.
-- 6 is Blizzard's 25-player Heroic difficulty ID for Icecrown Citadel.
local REQUIRED_DIFFICULTY = { invincible = 6 }
local function SourceForHunt(key, target)
    local source = target.sourceKey and sourceRegistry[target.sourceKey]
    if source then return source, target.sourceKey end
    if sourceRegistry[key] then return sourceRegistry[key], key end
    if type(target.itemID) == "number" then
        for _, sourceKey in ipairs(sourceKeys) do
            local candidate = sourceRegistry[sourceKey]
            if candidate.instance == target.instance and candidate.boss == target.boss then
                for _, itemID in ipairs(candidate.itemIDs or {}) do
                    if itemID == target.itemID then return candidate, sourceKey end
                end
            end
        end
    end
    return nil, nil
end

local function EventRunning(eventKey)
    if not eventKey then return true end
    if not (WBF.EventTriggers and WBF.EventTriggers.Active) then return nil end
    for _, event in ipairs(WBF.EventTriggers.Active()) do
        if event.eventKey == eventKey then return true end
    end
    return false
end

-- A daily boss reads "done" until the next daily reset. An unseen character,
-- or one last seen before the reset, stays unverified rather than available.
-- Start of the current weekly reset period, or nil when the client cannot say.
local WEEK = 7 * 86400
local function LastWeeklyReset(now)
    if not (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset) then return nil end
    local left = WBF.Format.AsNumber(WBF.Format.SafeCall(C_DateAndTime.GetSecondsUntilWeeklyReset))
    if not left or left <= 0 or left > WEEK then return nil end
    return now + left - WEEK
end

-- A character's record stays true until the reset it was taken in has passed:
-- the bag can only be looted by playing that character, which records it.
-- Once that reset has passed, today's bag is waiting again.
local function DailyStatus(data, sourceKey, source, guid)
    local running = EventRunning(source.eventKey)
    if running == false then return "closed" end
    local seen = data.daily[guid] and data.daily[guid][sourceKey]
    if type(seen) ~= "table" or type(seen.checkedAt) ~= "number" then return "unknown" end
    local now = time()
    if now < seen.checkedAt then return "unknown" end
    if running == nil then return "unknown" end
    if seen.expiresAt and seen.expiresAt <= now then return "available" end
    if seen.done then return "done" end
    return "available"
end

-- Only a successfully completed saved-instance scan can prove an available
-- attempt. Each character's scan is kept and trusted until the weekly reset.
function Hunts.Status(key, guid)
    local data = Store()
    local target = catalog[key]
    if not data.enabled[key] or not target then return "off" end
    if Hunts.Completion(key) then return "collected" end
    -- No lockout to read: a goal is open until it is collected.
    if target.goalOnly then return "goal" end
    local eligibility = Hunts.Eligibility(key, guid)
    if eligibility == "excluded" or eligibility == "ineligible" then return eligibility end
    if eligibility == "unknown" then return "unknown" end
    local dailySource = target.sourceKey and sourceRegistry[target.sourceKey]
    if dailySource and dailySource.daily then
        return DailyStatus(data, target.sourceKey, dailySource, guid)
    end
    local char = data.lockouts[guid]
    local raid = char and char[Norm(target.instance)]
    if not raid or not raid.checkedAt or not raid.verified then return "unknown" end
    local now = time()
    if now < raid.checkedAt then return "unknown" end
    -- A raid lockout only changes when that character plays, and playing
    -- rescans it, so a snapshot holds until the weekly reset. A snapshot from
    -- before the latest reset recorded lockouts that have all expired since.
    if now - raid.checkedAt > 86400 then
        local lastReset = LastWeeklyReset(now)
        if not lastReset then return "unknown" end
        if raid.checkedAt < lastReset then
            if type(raid.saves) ~= "table" then return "unknown" end
            return "available"
        end
    end
    if type(raid.saves) ~= "table" and raid.expiresAt and raid.expiresAt <= now then return "unknown" end

    local source, sourceKey = SourceForHunt(key, target)
    local needed = sourceKey and REQUIRED_DIFFICULTY[sourceKey]
    local ignored = source and source.ignoreDifficulties
    local bossKey = Norm(target.boss)
    local saves = raid.saves
    -- Legacy snapshots combined kills from all difficulties. A prior kill can
    -- still indicate an attempt, but cannot establish the required difficulty
    -- or separate a Raid Finder kill from a real mount attempt.
    if type(saves) ~= "table" then
        if needed or ignored then return "unknown" end
        if raid.bosses and raid.bosses[bossKey] then return "done" end
        return "available"
    end
    local sawOtherDifficulty = false
    for _, saved in ipairs(saves) do
        if type(saved) == "table" and type(saved.expiresAt) == "number" and saved.expiresAt > now then
            local skipped = ignored and ignored[saved.difficultyID]
            local matching = not skipped and (not needed or saved.difficultyID == needed)
            if matching and saved.bosses and saved.bosses[bossKey] then return "done" end
            if needed and not matching and not skipped then sawOtherDifficulty = true end
        end
    end
    -- An ICC lockout on another difficulty may block a 25 Heroic run.
    -- Never advertise it as available merely because the heroic record is absent.
    if needed and sawOtherDifficulty then return "unknown" end
    -- Special loot conditions (e.g. zero Keepers) are not inferred from a
    -- killed boss. The UI's source note remains the player's requirement.
    return "available"
end

function Hunts.Sync()
    Store()
    local guid = WBF.Characters and WBF.Characters.GetGuid and WBF.Characters.GetGuid()
    if not guid or not GetNumSavedInstances or not GetSavedInstanceInfo then return end
    local count = GetNumSavedInstances()
    if type(count) ~= "number" or count < 0 then return end
    local now = time()
    local snapshot = {}
    local function AddInstance(name)
        local normalized = Norm(name)
        if normalized ~= "" and not snapshot[normalized] then
            snapshot[normalized] = { checkedAt = now, verified = true, bosses = {}, saves = {} }
        end
    end
    for _, sourceKey in ipairs(sourceKeys) do AddInstance(sourceRegistry[sourceKey].instance) end
    for _, key in ipairs(ordered) do AddInstance(catalog[key].instance) end
    for i = 1, count do
        local name, _, reset, difficulty, locked, _, _, isRaid, _, _, numEncounters = GetSavedInstanceInfo(i)
        local raid = snapshot[Norm(name)]
        if raid and locked and isRaid then
            local expires = type(reset) == "number" and reset > 0 and (now + reset) or nil
            if expires then
                local save = { difficultyID = difficulty, expiresAt = expires, bosses = {} }
                raid.saves[#raid.saves + 1] = save
                raid.expiresAt = math.max(raid.expiresAt or 0, expires)
                if type(numEncounters) == "number" and GetSavedInstanceEncounterInfo then
                    for j = 1, numEncounters do
                        local bossName, _, killed = GetSavedInstanceEncounterInfo(i, j)
                        if killed == true and type(bossName) == "string" then
                            local bossKey = Norm(bossName)
                            save.bosses[bossKey] = true
                            raid.bosses[bossKey] = true -- compatibility with prior readers
                        end
                    end
                end
            else
                raid.verified = false
            end
        end
    end
    Store().lockouts[guid] = snapshot
    scanReady = true
    if WBF.UI and WBF.UI.RequestRefresh then WBF.UI.RequestRefresh() end
end

-- Daily holiday bosses report whether today's reward was already looted.
-- The LFG data is only filled after RequestLFDPlayerLockInfo answers.
function Hunts.DailyDone(sourceKey)
    local source = sourceRegistry[sourceKey]
    if not (source and source.daily and source.lfgDungeonID and GetLFGDungeonRewards) then return nil end
    local doneToday = WBF.Format.SafeCall(GetLFGDungeonRewards, source.lfgDungeonID)
    if type(doneToday) ~= "boolean" then return nil end
    return doneToday
end

local function SecondsUntilDailyReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local seconds = WBF.Format.SafeCall(C_DateAndTime.GetSecondsUntilDailyReset)
        if type(seconds) == "number" and seconds > 0 then return seconds end
    end
    if GetQuestResetTime then
        local seconds = WBF.Format.SafeCall(GetQuestResetTime)
        if type(seconds) == "number" and seconds > 0 then return seconds end
    end
end

function Hunts.SyncDaily()
    local data = Store()
    local guid = WBF.Characters and WBF.Characters.GetGuid and WBF.Characters.GetGuid()
    if not guid then return end
    local untilReset = SecondsUntilDailyReset()
    -- Without the reset time a "done" read cannot know when it expires.
    if not untilReset then return end
    local now = time()
    local seen = data.daily[guid] or {}
    local changed = false
    for _, sourceKey in ipairs(sourceKeys) do
        local done = Hunts.DailyDone(sourceKey)
        if done ~= nil then
            seen[sourceKey] = { done = done, checkedAt = now, expiresAt = now + untilReset }
            changed = true
        end
    end
    if changed then
        data.daily[guid] = seen
        if WBF.UI and WBF.UI.RequestRefresh then WBF.UI.RequestRefresh() end
    end
end

local function RequestDailyInfo()
    if RequestLFDPlayerLockInfo then WBF.Format.SafeCall(RequestLFDPlayerLockInfo) end
end

-- Snapshot known mount hunt state at login. Never celebrate previously collected
-- mounts during migration, initialisation or UI refresh.
local observedMounts = nil
local function SnapshotMounts()
    local state = {}
    for _, key in ipairs(sourceKeys) do
        local entry = sourceRegistry[key]
        if entry.mountSpellID then state[entry.mountSpellID] = MountCollected(entry.mountSpellID) end
    end
    return state
end
local function CheckNewlyCollected()
    if not observedMounts then return end
    local current = SnapshotMounts()
    for spellID, collected in pairs(current) do
        if collected == true and observedMounts[spellID] == false then
            local found
            for _, hunt in ipairs(Hunts.Active()) do
                if hunt.info.mountSpellID == spellID and Hunts.Settings(hunt.key).goal == "mount" then
                    found = hunt.info.title
                    break
                end
            end
            if found then
                print("|cff33ff99WarbandFYI - Collection Complete!|r " .. found .. " has been added to your collection!")
            end
        end
    end
    observedMounts = current
    if WBF.UI and WBF.UI.RequestRefresh then WBF.UI.RequestRefresh() end
end

function Hunts.Register(bus)
    -- Mount Journal is updated asynchronously on learning a mount.
    bus:On("COMPANION_LEARNED", function()
        if C_Timer and C_Timer.After then C_Timer.After(1, CheckNewlyCollected) end
    end)
    bus:On("UPDATE_INSTANCE_INFO", function() Hunts.Sync() end)
    -- Saved encounters can change after a boss kill. Request an updated
    -- Blizzard snapshot rather than assuming ENCOUNTER_END means a lockout.
    bus:On("ENCOUNTER_END", function(_, _, _, _, success)
        if success == 1 and RequestRaidInfo then RequestRaidInfo() end
    end)
    bus:On("PLAYER_ENTERING_WORLD", function()
        if RequestRaidInfo then RequestRaidInfo() end
        RequestDailyInfo()
    end)
    bus:On("LFG_UPDATE_RANDOM_INFO", function() Hunts.SyncDaily() end)
    -- Looting a holiday boss bag marks the reward as done for today.
    bus:On("LFG_COMPLETION_REWARD", function()
        if C_Timer and C_Timer.After then C_Timer.After(2, RequestDailyInfo) else RequestDailyInfo() end
    end)
end

function Hunts.OnLogin()
    observedMounts = SnapshotMounts()
    scanReady = false
    if RequestRaidInfo then RequestRaidInfo() end
    RequestDailyInfo()
    if C_Timer and C_Timer.After then
        C_Timer.After(4, function() Hunts.Sync() end)
    end
end


-- Build a read-only, consolidated FYI. Only verified, eligible, currently
-- available attempts are advertised; unknowns stay on the Hunts dashboard.
-- Characters that can make an attempt at a hunt now, this character first.
function Hunts.AvailableCharacters(key)
    local current = WBF.Characters and WBF.Characters.GetGuid and WBF.Characters.GetGuid()
    local names = {}
    local list = WBF.Characters and WBF.Characters.List and WBF.Characters.List() or {}
    for _, character in ipairs(list) do
        if character.guid and Hunts.Status(key, character.guid) == "available" then
            local entry = { guid = character.guid, name = character.name or "?", current = character.guid == current }
            if entry.current then table.insert(names, 1, entry) else names[#names + 1] = entry end
        end
    end
    return names
end

function Hunts.Icon(info)
    if type(info) ~= "table" then return nil end
    return info.mountIcon or (info.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.itemID))
        or (info.itemID and GetItemIcon and GetItemIcon(info.itemID))
        or (info.achievementID and GetAchievementInfo and select(10, GetAchievementInfo(info.achievementID)))
        or (info.petSpeciesID and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID
            and select(2, C_PetJournal.GetPetInfoBySpeciesID(info.petSpeciesID)))
        or nil
end

-- A short nudge for the character being played: each hunt it can make an
-- attempt at right now, and where. Alts stay on the Collection Hunts page.
function Hunts.LoginEntry()
    if not scanReady then return nil end
    local guid = WBF.Characters and WBF.Characters.GetGuid and WBF.Characters.GetGuid()
    if not guid then return nil end
    local lines = {}
    for _, hunt in ipairs(Hunts.Active()) do
        if Hunts.Status(hunt.key, guid) == "available" then
            local info = hunt.info
            local source = info.sourceKey and sourceRegistry[info.sourceKey]
            local where = source and source.daily and (info.boss .. " daily bag")
                or (info.instance .. " - " .. info.boss)
            lines[#lines + 1] = { text = info.title, icon = Hunts.Icon(info) or "Interface\\Icons\\INV_Misc_QuestionMark" }
            lines[#lines + 1] = { text = where, indent = true, muted = true }
        end
    end
    if #lines == 0 then return nil end
    local count = #lines / 2
    return { context = "Collection Hunts",
        title = count == 1 and "You can make an attempt" or ("You can make " .. count .. " attempts"),
        lines = lines, triggerType = "LOGIN", attachKey = "hunts", openHunts = true }
end

local function Notify()
    if WBF.UI and WBF.UI.RequestRefresh then WBF.UI.RequestRefresh() end
end
local function Say(message)
    print("|cffd4af37WarbandFYI|r " .. message)
end
local function FindCharacter(input)
    local wanted = Norm(input)
    if wanted == "" then return nil, "Enter a character name." end
    local matches = {}
    for _, character in ipairs(WBF.Characters.List()) do
        if Norm(character.name) == wanted or Norm((character.name or "") .. (character.realm or "")) == wanted then
            matches[#matches + 1] = character
        end
    end
    if #matches == 1 then return matches[1] end
    if #matches > 1 then return nil, "Multiple characters have that name. Use Name-Realm." end
    return nil, "Character not found. Log in with it first."
end

function Hunts.Slash(raw)
    if type(raw) ~= "string" then return false end
    local lower = raw:lower()
    -- "hunt" is a whole command. Do not swallow "hunter" or "hundred".
    if lower ~= "hunt" and lower ~= "hunts" and not lower:match("^hunts?%s") then return false end
    local cmd, target, rest = lower:match("^hunts?%s+(%w+)%s*(%w*)%s*(.-)%s*$")
    local data = Store()
    if cmd == "add" or cmd == "remove" then
        if not catalog[target] then Say("Hunt keys: thoridal, onyxian, southwind"); return true end
        data.enabled[target] = cmd == "add" or nil
        Say((cmd == "add" and "Tracking " or "Stopped tracking ") .. catalog[target].title)
        Notify()
    elseif cmd == "goal" then
        if not catalog[target] or not validGoals[rest] then
            Say("Usage: /wbfyi hunt goal <key> achievement|appearance|item|mount|pet")
            return true
        end
        if target ~= "thoridal" and rest ~= "mount" then
            Say("This preset is a mount; only the mount goal is supported.")
            return true
        end
        Settings(target).goal = rest
        Say(catalog[target].title .. " goal: " .. rest .. ". Unknown eligibility remains unverified.")
        Notify()
    elseif cmd == "chars" then
        if not catalog[target] or (rest ~= "all" and rest ~= "selected") then
            Say("Usage: /wbfyi hunt chars <key> all|selected")
            return true
        end
        Settings(target).characterMode = rest
        Say(catalog[target].title .. " character selection: " .. rest)
        Notify()
    elseif cmd == "include" or cmd == "exclude" then
        if not catalog[target] then Say("Usage: /wbfyi hunt include|exclude <key> Character[-Realm]"); return true end
        local character, err = FindCharacter(rest)
        if not character then Say(err); return true end
        local setting = Settings(target)
        setting.characterMode = "selected"
        setting.selected[character.guid] = cmd == "include" or nil
        Say((cmd == "include" and "Included " or "Excluded ") .. character.name .. " for " .. catalog[target].title)
        Notify()
    elseif cmd == "fyi" then
        if WBF.NotebookFyi and WBF.NotebookFyi.ShowHunts then WBF.NotebookFyi.ShowHunts() end
    else
        Say("Collection Hunts commands:")
        Say("/wbfyi hunt fyi  - show the hunts this character can attempt now")
        Say("/wbfyi hunt add|remove <thoridal|onyxian|southwind>")
        Say("/wbfyi hunt goal <key> achievement|appearance|item|mount|pet")
        Say("/wbfyi hunt chars <key> all|selected")
        Say("/wbfyi hunt include|exclude <key> Character[-Realm]")
        Say("/wbfyi hunt list")
        for _, entry in ipairs(Hunts.Active()) do
            local setting = Settings(entry.key)
            local guid = WBF.Characters.GetGuid()
            Say(entry.info.title .. " | " .. setting.goal .. " | " .. setting.characterMode .. " | " .. Hunts.Status(entry.key, guid))
        end
    end
    return true
end
