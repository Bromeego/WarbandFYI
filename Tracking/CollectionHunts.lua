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
            elseif type(target.itemID) == "number" and GetItemInfo then
                local name = GetItemInfo(target.itemID)
                if name then target.title = name end
            elseif type(target.achievementID) == "number" and GetAchievementInfo then
                local _, name = GetAchievementInfo(target.achievementID)
                if type(name) == "string" then target.title = name end
            end
        end
        if type(key) == "string" and type(target) == "table" and type(target.title) == "string" and type(target.instance) == "string" and type(target.boss) == "string" and (type(target.itemID) == "number" or type(target.achievementID) == "number" or type(target.mountID) == "number") and not catalog[key] then
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
        options[#options+1] = { key=key, instance=entry.instance, boss=entry.boss, note=entry.note, difficulty=entry.difficulty, collectionType=entry.collectionType }
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
    local achievement = tonumber(text:match("achievement:(%d+)"))
    if achievement then return "achievement", achievement end
    local item = tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
    if item then return "item", item end
    local knownID = Hunts.ResolveKnownName(text)
    if knownID then return "item", knownID end
end

-- Explicit source selection: an item link alone cannot establish its drop source.
function Hunts.AddTarget(link, sourceKey)
    local kind, id = ParseTarget(link)
    local source = sourceRegistry[sourceKey]
    if not id then return nil, "Enter a known mount name, an item ID, or Shift-click an item (use the achievement picker for achievements)." end
    if not source then return nil, "Choose a supported raid source." end
    local data = Store()
    local key = kind .. id .. "_" .. sourceKey
    if not catalog[key] then
        local title
        if kind == "mount" then
            local mount = Hunts.Mount(id)
            if not mount then return nil, "Mount not found in the Mount Journal." end
            title = mount.name
        elseif kind == "achievement" then
            if GetAchievementInfo then local achievementID, name = GetAchievementInfo(id); title = name end
            if type(title) ~= "string" or title == "" then title = "Achievement #" .. id end
        else
            title = GetItemInfo and GetItemInfo(id) or nil
            if type(title) ~= "string" or title == "" then title = "Item #" .. id end
        end
        local knownMount = kind == "item" and Hunts.Preview(link)
        local journalMount = kind == "mount" and Hunts.Mount(id)
        data.custom[key] = { title=title, itemID=kind == "item" and id or nil,
            mountID=journalMount and id or nil, mountIcon=journalMount and journalMount.icon or nil,
            mountSpellID=(journalMount and journalMount.spellID) or (knownMount and sourceKey == knownMount.sourceKey and source.mountSpellID or nil),
            achievementID=kind == "achievement" and id or nil,
            instance=source.instance, boss=source.boss,
            defaultGoal=(kind == "mount" and "mount") or (kind == "achievement" and "achievement") or (knownMount and sourceKey == knownMount.sourceKey and "mount" or "item"), custom=true, sourceKey=sourceKey, sourceNote=source.note }
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

local validGoals = { achievement = true, appearance = true, item = true, mount = true }
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
    local class = character.classFile
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

-- Only a fresh, successfully completed saved-instance scan can prove an
-- available attempt. A scan of an alt never refreshes its snapshot.
function Hunts.Status(key, guid)
    local data = Store()
    local target = catalog[key]
    if not data.enabled[key] or not target then return "off" end
    if Hunts.Completion(key) then return "collected" end
    local eligibility = Hunts.Eligibility(key, guid)
    if eligibility == "excluded" or eligibility == "ineligible" then return eligibility end
    if eligibility == "unknown" then return "unknown" end
    local char = data.lockouts[guid]
    local raid = char and char[Norm(target.instance)]
    if not raid or not raid.checkedAt or not raid.verified then return "unknown" end
    local now = time()
    -- Snapshot freshness is deliberately conservative for characters not
    -- presently logged in, including snapshots with no lockout information.
    if now - raid.checkedAt > 86400 or now < raid.checkedAt then return "unknown" end
    if raid.expiresAt and raid.expiresAt <= now then return "unknown" end

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
    end)
end

function Hunts.OnLogin()
    observedMounts = SnapshotMounts()
    scanReady = false
    if RequestRaidInfo then RequestRaidInfo() end
    if C_Timer and C_Timer.After then
        C_Timer.After(4, function() Hunts.Sync() end)
    end
end


-- Build a read-only, consolidated FYI. Only verified, eligible, currently
-- available attempts are advertised; unknowns stay on the Hunts dashboard.
function Hunts.LoginEntry()
    if not scanReady then return nil end
    local guid = WBF.Characters and WBF.Characters.GetGuid and WBF.Characters.GetGuid()
    if not guid then return nil end
    local lines = {}
    for _, hunt in ipairs(Hunts.Active()) do
        if Hunts.Status(hunt.key, guid) == "available" then
            lines[#lines + 1] = { text = hunt.info.title, detail = hunt.info.instance .. " - " .. hunt.info.boss }
        end
    end
    if #lines == 0 then return nil end
    return { title = "Available Collection Hunts", context = "Ready on this character",
        lines = lines, triggerType = "LOGIN" }
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
            Say("Usage: /wbfyi hunt goal <key> achievement|appearance|item|mount")
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
    else
        Say("Collection Hunts commands:")
        Say("/wbfyi hunt add|remove <thoridal|onyxian|southwind>")
        Say("/wbfyi hunt goal <key> achievement|appearance|item|mount")
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
