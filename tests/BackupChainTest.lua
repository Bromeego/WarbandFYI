-- Every pre-migration backup is kept; a schema upgrade never replaces an
-- older safety copy. Run from the repo root:
--   lua tests/BackupChainTest.lua
--
-- The addon is at schema 7 with no pending upgrade, so these tests load
-- Database.lua with a test-only target schema and no-op migrations patched
-- in at load time. The shipped file is not changed by the test.

local script = arg and arg[0] or "tests/BackupChainTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local failures = 0
local function check(name, condition, detail)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  " .. detail) or ""))
end

local function readFile(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local now = 1790000000

-- Fresh addon namespace whose Database.lua targets `target`. Schemas from 7
-- up to target - 1 get a migration that only counts itself, and fails once
-- when the database asks it to.
local function loadAddon(target)
    local WBF = {}
    local function run(path, source)
        local chunk = assert(loadstring(source or readFile(path), "@" .. path))
        chunk("WarbandFYI", WBF)
    end
    run("Utils/Format.lua")
    run("Utils/Time.lua")
    run("Utils/Debug.lua")
    run("Core/Characters.lua")
    local source = readFile("Core/Database.lua")
    if target and target > 7 then
        local replaced
        source, replaced = source:gsub("(local CURRENT_SCHEMA_VERSION = )7(%s)", "%1" .. target .. "%2", 1)
        assert(replaced == 1, "schema constant not found")
        local hook = string.format([[
for step = 7, %d do
    Migrations[step] = function(db)
        if db.failNextUpgrade then
            db.failNextUpgrade = nil
            error("test migration failure")
        end
        db.testUpgrades = (db.testUpgrades or 0) + 1
    end
end

local function ApplyMigrations(db)]], target - 1)
        source, replaced = source:gsub("local function ApplyMigrations%(db%)", function()
            return hook
        end, 1)
        assert(replaced == 1, "ApplyMigrations not found")
    end
    run("Core/Database.lua", source)
    run("Core/Maintenance.lua")
    WBF.Time.Now = function()
        return now
    end
    WBF.VERSION = "test"
    return WBF
end

local function deepEqual(a, b, seen)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    seen = seen or {}
    if seen[a] == b then
        return true
    end
    seen[a] = b
    for key, value in pairs(a) do
        if not deepEqual(value, b[key], seen) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Every value in `original` is present and unchanged in `copied`. Init adds
-- missing config defaults before it takes the backup (existing behaviour),
-- so a backup may hold extra keys but must never lose or change one.
local function keepsEverything(original, copied)
    if type(original) ~= "table" then
        return original == copied
    end
    if type(copied) ~= "table" then
        return false
    end
    for key, value in pairs(original) do
        if not keepsEverything(value, copied[key]) then
            return false
        end
    end
    return true
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, item in pairs(value) do
        out[copy(key)] = copy(item)
    end
    return out
end

local function chain()
    return type(WarbandFYI_Backup) == "table" and type(WarbandFYI_Backup.previous) == "table" and WarbandFYI_Backup.previous or {}
end

local function entry(index)
    return chain()[index] or {}
end

-- A schema 7 save as a real install has it, with some history.
local function schema7Save()
    return {
        schemaVersion = 7,
        config = { retentionDays = 120, sessionTimeoutSeconds = 3600, lastView = "week" },
        nextIds = { session = 3, event = 4 },
        sessions = {
            { id = 1, startedAt = now - 7200, endedAt = now - 3600, segments = { { guid = "Player-1-A", startedAt = now - 7200, endedAt = now - 3600 } }, goldByCharacter = {}, goldLedger = {} },
        },
        characters = { ["Player-1-A"] = { guid = "Player-1-A", name = "Miranora", realm = "Area 52", discovered = true, firstSeen = now - 86400 } },
        snapshots = { { at = now - 7000, guid = "Player-1-A", level = 80, itemLevel = 640, money = 123456 } },
        events = {
            { id = 1, at = now - 7100, guid = "Player-1-A", eventType = "quest", category = "quest", text = "A quest", meta = { questID = 90001 } },
            { id = 2, at = now - 7000, guid = "Player-1-A", eventType = "resource", delta = 5, meta = { resourceKey = "tender", balanceAfter = 905, classification = "gain" } },
        },
        dedupe = {},
        goldLast = { ["Player-1-A"] = 123456 },
        monthHistory = {},
        notebook = { pages = {}, pageOrder = {}, sections = {}, blocks = {}, quickNotes = {}, quickNoteOrder = {} },
    }
end

-- The backup a schema 5 -> 7 upgrade left behind on a real install.
local function existingBackup()
    return {
        createdAt = now - 30 * 86400,
        addonVersion = "0.2.0-dev.2b",
        fromSchema = 5,
        targetSchema = 7,
        data = { schemaVersion = 5, events = { { id = 1, at = now - 40 * 86400, eventType = "quest", text = "Old" } }, config = {} },
        keptByOlderVersion = "unknown fields stay",
    }
end

-- 1. An upgrade keeps the existing backup unchanged in `previous`.
WarbandFYI_DB = schema7Save()
WarbandFYI_Backup = existingBackup()
local original = WarbandFYI_Backup
local originalCopy = copy(original)
local before = copy(WarbandFYI_DB)
local WBF = loadAddon(8)
WBF.Database.Init()
check("an upgrade still writes a new top-level backup", WarbandFYI_Backup.fromSchema == 7 and WarbandFYI_Backup.targetSchema == 8)
check("the new backup keeps every value of the save as it was before the upgrade", keepsEverything(before, WarbandFYI_Backup.data))
check("the older backup is kept, not replaced", type(WarbandFYI_Backup.previous) == "table" and #chain() == 1)
check("the older backup is the same table it was", WarbandFYI_Backup.previous and entry(1) == original)
check("the older backup is unchanged, unknown fields included", WarbandFYI_Backup.previous and deepEqual(entry(1), originalCopy))
check("the older backup does not hold a chain of its own", WarbandFYI_Backup.previous and entry(1).previous == nil)
check("the new backup's data does not contain any backup", WarbandFYI_Backup.data.previous == nil and WarbandFYI_Backup.data.data == nil)
check("the upgrade itself ran", WarbandFYI_DB.schemaVersion == 8 and WarbandFYI_DB.testUpgrades == 1)

-- 2. Further upgrades add to the chain, oldest first, without touching it.
local afterFirst = WarbandFYI_Backup
local firstCopy = copy(afterFirst)
WBF = loadAddon(9)
WBF.Database.Init()
check("a second upgrade keeps both older backups", type(WarbandFYI_Backup.previous) == "table" and #chain() == 2)
check("the chain is oldest first", entry(1) == original and entry(2).targetSchema == 8)
check("the moved backup keeps its own fields", deepEqual(entry(2).data, firstCopy.data) and entry(2).fromSchema == 7)
check("the moved backup does not carry the chain inside it", entry(2).previous == nil)
check("the oldest backup is still unchanged", deepEqual(entry(1), originalCopy))
WBF = loadAddon(10)
WBF.Database.Init()
check("a third upgrade keeps all three older backups", #chain() == 3 and entry(3).targetSchema == 9 and WarbandFYI_Backup.targetSchema == 10)

-- 3. A failed upgrade retried later does not add a second backup.
WarbandFYI_DB = schema7Save()
WarbandFYI_DB.failNextUpgrade = true
WarbandFYI_Backup = existingBackup()
original = WarbandFYI_Backup
WBF = loadAddon(8)
WBF.Database.Init()
local afterFailure = WarbandFYI_Backup
check("a failed upgrade still took its backup first", afterFailure.fromSchema == 7 and afterFailure.previous and (afterFailure.previous or {})[1] == original)
check("the failed upgrade left the schema where it was", WarbandFYI_DB.schemaVersion == 7)
WBF = loadAddon(8)
WBF.Database.Init()
check("retrying keeps the same backup", WarbandFYI_Backup == afterFailure and #chain() == 1)
check("the retry completes the upgrade", WarbandFYI_DB.schemaVersion == 8 and WarbandFYI_DB.testUpgrades == 1)

-- 4. A save without a backup gets one exactly as today.
WarbandFYI_DB = schema7Save()
WarbandFYI_Backup = nil
before = copy(WarbandFYI_DB)
WBF = loadAddon(8)
WBF.Database.Init()
check("a first backup is written as before", type(WarbandFYI_Backup) == "table" and WarbandFYI_Backup.fromSchema == 7 and keepsEverything(before, WarbandFYI_Backup.data))
check("a first backup has no chain", WarbandFYI_Backup.previous == nil)
local keys = {}
for key in pairs(WarbandFYI_Backup) do
    keys[#keys + 1] = key
end
table.sort(keys)
check("a first backup has exactly today's fields", table.concat(keys, ",") == "addonVersion,createdAt,data,fromSchema,targetSchema", table.concat(keys, ","))

-- 5. A backup value that is not a table is kept, not overwritten.
WarbandFYI_DB = schema7Save()
WarbandFYI_Backup = "damaged backup text"
WBF = loadAddon(8)
WBF.Database.Init()
check("an unreadable backup is kept in the chain", WarbandFYI_Backup.previous and entry(1) and entry(1).unreadable == "damaged backup text")

-- A damaged chain is kept as found, beside the backup it belonged to.
WarbandFYI_DB = schema7Save()
WarbandFYI_Backup = existingBackup()
WarbandFYI_Backup.previous = "damaged chain"
WBF = loadAddon(8)
WBF.Database.Init()
local kept = WarbandFYI_Backup.previous and entry(1)
check("a damaged chain value is kept with its backup", kept and kept.fromSchema == 5 and kept.previous == "damaged chain")

-- An empty table is not worth an entry; nothing else is skipped.
WarbandFYI_DB = schema7Save()
WarbandFYI_Backup = {}
WBF = loadAddon(8)
WBF.Database.Init()
check("an empty backup table adds no chain entry", WarbandFYI_Backup.previous == nil and WarbandFYI_Backup.fromSchema == 7)

-- 6. The upgraded database is the same whatever backups exist.
WarbandFYI_DB = schema7Save()
WarbandFYI_Backup = nil
WBF = loadAddon(8)
WBF.Database.Init()
local withoutBackup = copy(WarbandFYI_DB)
WarbandFYI_DB = schema7Save()
WarbandFYI_Backup = existingBackup()
WBF = loadAddon(8)
WBF.Database.Init()
check("the database after an upgrade does not depend on older backups", deepEqual(WarbandFYI_DB, withoutBackup))

-- 7. No upgrade, no change: the shipped schema 7 code leaves every backup alone.
WarbandFYI_DB = schema7Save()
WarbandFYI_Backup = existingBackup()
WarbandFYI_Backup.previous = { { fromSchema = 3, targetSchema = 5, data = { schemaVersion = 3 } } }
original = WarbandFYI_Backup
originalCopy = copy(original)
WBF = loadAddon(nil)
WBF.Database.Init()
check("a current save keeps its backup table", WarbandFYI_Backup == original)
check("a current save keeps its backup unchanged", deepEqual(WarbandFYI_Backup, originalCopy))

-- 8. Maintenance reports the newest backup as before, and how many are kept.
local diagnostics = WBF.Maintenance.Diagnostics()
check("Maintenance still reports the newest backup", diagnostics.migrationBackupFrom == 5 and diagnostics.migrationBackupTarget == 7)
check("Maintenance counts every kept backup", diagnostics.migrationBackupsKept == 2, tostring(diagnostics.migrationBackupsKept))
check("the diagnostics text names the kept count", WBF.Maintenance.DiagnosticsText():find("2 kept", 1, true) ~= nil)
WarbandFYI_Backup = nil
check("no backup reports none kept", WBF.Maintenance.Diagnostics().migrationBackupsKept == 0)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All backup chain checks passed")
