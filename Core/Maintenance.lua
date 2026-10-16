local _, WBF = ...

WBF.Maintenance = {}

local function CountMap(value)
    if type(value) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function CountArray(value)
    return type(value) == "table" and #value or 0
end

local function EstimateBytes(value, seen)
    local kind = type(value)
    if kind == "nil" then
        return 1
    elseif kind == "boolean" then
        return 1
    elseif kind == "number" then
        return 8
    elseif kind == "string" then
        return #value + 8
    elseif kind ~= "table" then
        return 0
    end
    seen = seen or {}
    if seen[value] then
        return 0
    end
    seen[value] = true
    local bytes = 32
    for key, item in pairs(value) do
        bytes = bytes + EstimateBytes(key, seen) + EstimateBytes(item, seen) + 12
    end
    return bytes
end

local function OldestTimestamp(rows, field)
    local oldest
    if type(rows) ~= "table" then
        return nil
    end
    for _, row in pairs(rows) do
        if type(row) == "table" then
            local stamp = row[field or "at"]
            if type(stamp) == "number" and (not oldest or stamp < oldest) then
                oldest = stamp
            end
        end
    end
    return oldest
end

local function MonthCount(history)
    local count = 0
    if type(history) ~= "table" then
        return count
    end
    for _, year in pairs(history) do
        if type(year) == "table" then
            for _, month in pairs(year) do
                if type(month) == "table" then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function NotebookCounts(notebook)
    local result = {
        pages = 0,
        sections = 0,
        blocks = 0,
        checklistItems = 0,
        quickNotes = 0,
        contextFyis = 0,
    }
    if type(notebook) ~= "table" then
        return result
    end
    result.pages = CountMap(notebook.pages)
    result.sections = CountMap(notebook.sections)
    result.blocks = CountMap(notebook.blocks)
    result.quickNotes = CountMap(notebook.quickNotes)
    result.contextFyis = CountMap(notebook.contextFyis)
    if type(notebook.blocks) == "table" then
        for _, block in pairs(notebook.blocks) do
            if type(block) == "table" and type(block.items) == "table" then
                result.checklistItems = result.checklistItems + #block.items
            end
        end
    end
    return result
end

local function ResourceCounts(resources)
    local result = {
        balances = 0,
        watched = 0,
        definitions = 0,
        watchlist = 0,
    }
    if type(resources) ~= "table" then
        return result
    end
    result.balances = CountMap(resources.balances)
    result.watched = CountArray(resources.watched)
    result.definitions = CountMap(resources.definitions)
    result.watchlist = CountMap(resources.watchlist)
    return result
end

function WBF.Maintenance.Diagnostics()
    local db = WBF.Database and WBF.Database.Get and WBF.Database.Get() or WarbandFYI_DB
    db = type(db) == "table" and db or {}
    local notebook = NotebookCounts(db.notebook)
    local resources = ResourceCounts(db.resources)
    local maintenance = type(db.maintenance) == "table" and db.maintenance or {}
    local backup = type(WarbandFYI_Backup) == "table" and WarbandFYI_Backup or nil
    return {
        addonVersion = WBF.VERSION or "?",
        schemaVersion = db.schemaVersion or 0,
        approximateBytes = EstimateBytes(db),
        sessions = CountArray(db.sessions),
        events = CountArray(db.events),
        snapshots = CountArray(db.snapshots),
        characters = CountMap(db.characters),
        dedupeKeys = CountMap(db.dedupe),
        monthHistory = MonthCount(db.monthHistory),
        notebook = notebook,
        resources = resources,
        retentionDays = WBF.Database and WBF.Database.RetentionDays and WBF.Database.RetentionDays() or nil,
        oldestEventAt = OldestTimestamp(db.events, "at"),
        oldestSnapshotAt = OldestTimestamp(db.snapshots, "at"),
        lastPruneAt = db.lastPruneAt,
        lastPruneRemoved = maintenance.lastPruneRemoved or 0,
        totalPruned = maintenance.totalPruned or 0,
        resourceDuplicateClaims = maintenance.resourceDuplicateClaims or 0,
        resourceEventsRecorded = maintenance.resourceEventsRecorded or 0,
        invalidRoutesBlocked = maintenance.invalidRoutesBlocked or 0,
        migrationBackupAt = backup and backup.createdAt or nil,
        migrationBackupFrom = backup and backup.fromSchema or nil,
        migrationBackupTarget = backup and backup.targetSchema or nil,
    }
end

local function HumanBytes(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1024 * 1024 then
        return string.format("%.2f MB", bytes / (1024 * 1024))
    end
    if bytes >= 1024 then
        return string.format("%.1f KB", bytes / 1024)
    end
    return tostring(math.floor(bytes)) .. " B"
end

local function When(stamp)
    if type(stamp) ~= "number" then
        return "not available"
    end
    if date then
        return date("%Y-%m-%d %H:%M:%S", stamp)
    end
    return tostring(stamp)
end

function WBF.Maintenance.DiagnosticsText()
    local d = WBF.Maintenance.Diagnostics()
    local n = d.notebook
    local r = d.resources
    local lines = {
        "WarbandFYI diagnostics",
        "Addon version: " .. tostring(d.addonVersion),
        "Schema version: " .. tostring(d.schemaVersion),
        "Approx database size: " .. HumanBytes(d.approximateBytes),
        "Retention: " .. (d.retentionDays and (tostring(d.retentionDays) .. " days") or "unlimited"),
        "Sessions: " .. tostring(d.sessions),
        "Events: " .. tostring(d.events),
        "Snapshots: " .. tostring(d.snapshots),
        "Characters: " .. tostring(d.characters),
        "Dedupe keys: " .. tostring(d.dedupeKeys),
        "Completed month rollups: " .. tostring(d.monthHistory),
        "Notebook: " .. tostring(n.pages) .. " pages, " .. tostring(n.sections) .. " sections, " .. tostring(n.blocks) .. " blocks, " .. tostring(n.checklistItems) .. " checklist items, " .. tostring(n.contextFyis) .. " FYIs",
        "Resources: " .. tostring(r.balances) .. " balances, " .. tostring(r.watched) .. " watched definitions, " .. tostring(r.watchlist) .. " watchlist entries",
        "Oldest retained event: " .. When(d.oldestEventAt),
        "Last prune: " .. When(d.lastPruneAt) .. " (removed " .. tostring(d.lastPruneRemoved) .. ")",
        "Lifetime pruned records: " .. tostring(d.totalPruned),
        "Resource duplicate writes suppressed: " .. tostring(d.resourceDuplicateClaims),
        "Resource events recorded: " .. tostring(d.resourceEventsRecorded),
        "Invalid navigation routes blocked: " .. tostring(d.invalidRoutesBlocked),
    }
    if d.migrationBackupAt then
        lines[#lines + 1] = "Automatic migration backup: " .. When(d.migrationBackupAt) .. " (schema " .. tostring(d.migrationBackupFrom) .. " -> " .. tostring(d.migrationBackupTarget) .. ")"
    else
        lines[#lines + 1] = "Automatic migration backup: none"
    end
    return table.concat(lines, "\n")
end

local function Copy(value, seen)
    if type(value) ~= "table" then
        if type(value) == "function" or type(value) == "userdata" or type(value) == "thread" then
            return nil
        end
        return value
    end
    seen = seen or {}
    if seen[value] then
        return nil
    end
    seen[value] = true
    local out = {}
    for key, item in pairs(value) do
        local copiedKey = Copy(key, seen)
        local copiedItem = Copy(item, seen)
        if copiedKey ~= nil and copiedItem ~= nil then
            out[copiedKey] = copiedItem
        end
    end
    seen[value] = nil
    return out
end

local function SortedKeys(value)
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then
            if ta == "number" then
                return a < b
            end
            return tostring(a) < tostring(b)
        end
        return ta < tb
    end)
    return keys
end

local function Serialize(value, indent, seen)
    local kind = type(value)
    if kind == "nil" then
        return "nil"
    elseif kind == "boolean" or kind == "number" then
        return tostring(value)
    elseif kind == "string" then
        return string.format("%q", value)
    elseif kind ~= "table" then
        return "nil"
    end
    seen = seen or {}
    if seen[value] then
        return "nil --[[cycle]]"
    end
    seen[value] = true
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local childPad = string.rep("  ", indent + 1)
    local parts = { "{" }
    local keys = SortedKeys(value)
    for index = 1, #keys do
        local key = keys[index]
        local item = value[key]
        local keyText
        if type(key) == "string" and key:match("^[%a_][%w_]*$") then
            keyText = key
        else
            keyText = "[" .. Serialize(key, 0, seen) .. "]"
        end
        parts[#parts + 1] = "\n" .. childPad .. keyText .. " = " .. Serialize(item, indent + 1, seen) .. ","
    end
    if #keys > 0 then
        parts[#parts + 1] = "\n" .. pad
    end
    parts[#parts + 1] = "}"
    seen[value] = nil
    return table.concat(parts)
end

function WBF.Maintenance.ExportConfiguration()
    local db = WBF.Database and WBF.Database.Get and WBF.Database.Get() or WarbandFYI_DB
    db = type(db) == "table" and db or {}
    local resources = type(db.resources) == "table" and db.resources or {}
    local export = {
        format = "WarbandFYI-configuration-backup-v1",
        exportedAt = WBF.Time and WBF.Time.Now and WBF.Time.Now() or time(),
        addonVersion = WBF.VERSION,
        schemaVersion = db.schemaVersion,
        config = Copy(db.config or {}),
        nextIds = Copy(db.nextIds or {}),
        notebook = Copy(db.notebook or {}),
        resources = {
            watched = Copy(resources.watched or {}),
            definitions = Copy(resources.definitions or {}),
            watchlist = Copy(resources.watchlist or {}),
        },
    }
    return "-- WarbandFYI configuration backup\n-- Copy and keep this text somewhere safe.\nreturn " .. Serialize(export, 0, {})
end

function WBF.Maintenance.HumanBytes(bytes)
    return HumanBytes(bytes)
end
