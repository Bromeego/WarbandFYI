local _, WBF = ...

WBF.Database = {}

local CURRENT_SCHEMA_VERSION = 7
local MAX_EVENTS = 8000
local MAX_SNAPSHOTS = 4000
local TRIM_EVENTS_TO = 7000
local TRIM_SNAPSHOTS_TO = 3200
local MAX_RETENTION_DAYS = 3650

-- Permanent keys stay boolean true. Transient keys may be a unix timestamp
-- so retention can drop them. Unknown booleans are kept.
-- Collection identities stay for good: dropping "mount:123" would let the
-- same mount be recorded again the next time the client announces it.
local PERMANENT_DEDUPE = {
    mount = true,
    pet = true,
    petcapture = true,
    achievement = true,
    appearance = true,
    housing = true,
    ["prey-complete"] = true,
    recipe = true,
    profspec = true,
}

local function Defaults()
    return {
        schemaVersion = CURRENT_SCHEMA_VERSION,
        config = {
            sessionTimeoutSeconds = 3600,
            debug = false,
            welcomed = false,
            lastView = "week",
            retentionDays = 120,
            resourceNotices = true,
            notebookFyi = true,
            contextFyiNotices = true,
            resourceSections = {},
            window = nil,
            fyiPopup = nil,
        },
        nextIds = {
            session = 1,
            event = 1,
            notebookPage = 1,
            notebookSection = 1,
            notebookBlock = 1,
            notebookItem = 1,
            notebookNote = 1,
            contextFyi = 1,
            contextItem = 1,
        },
        activeSessionId = nil,
        sessions = {},
        characters = {},
        snapshots = {},
        events = {},
        dedupe = {},
        goldLast = {},
        monthHistory = {},
        currentInstance = nil,
        maintenance = {
            resourceDuplicateClaims = 0,
            resourceEventsRecorded = 0,
            invalidRoutesBlocked = 0,
            totalPruned = 0,
            lastPruneRemoved = 0,
        },
        notebook = {
            pages = {},
            pageOrder = {},
            sections = {},
            blocks = {},
            quickNotes = {},
            quickNoteOrder = {},
        },
    }
end

-- Reminders live beside the journal. Retention never deletes them.
-- Legacy plan maps still exist until Migrations[3] folds them into notebook.
function WBF.Database.EnsurePlans(db)
    db = db or WarbandFYI_DB
    if type(db) ~= "table" then
        return nil
    end
    if type(db.plans) ~= "table" then
        db.plans = {}
    end
    if type(db.plans.entries) ~= "table" then
        db.plans.entries = {}
    end
    if type(db.plans.groups) ~= "table" then
        db.plans.groups = {}
    end
    if type(db.nextIds) ~= "table" then
        db.nextIds = {}
    end
    if type(db.nextIds.planEntry) ~= "number" or db.nextIds.planEntry < 1 then
        db.nextIds.planEntry = 1
    end
    if type(db.nextIds.planGroup) ~= "number" or db.nextIds.planGroup < 1 then
        db.nextIds.planGroup = 1
    end
    return db.plans
end

local function NotebookNumber(nextIds, field)
    local value = math.floor(tonumber(nextIds[field]) or 1)
    if value < 1 then
        value = 1
    end
    return value
end

local function HighestId(map, prefix, floor)
    local nextValue = floor
    if type(map) ~= "table" then
        return nextValue
    end
    for key in pairs(map) do
        local number = tonumber(tostring(key):match("^" .. prefix .. "(%d+)$"))
        if number and number >= nextValue then
            nextValue = number + 1
        end
    end
    return nextValue
end

-- Pages, sections, blocks, and loose notes. Retention never deletes them.
function WBF.Database.EnsureNotebook(db)
    db = db or WarbandFYI_DB
    if type(db) ~= "table" then
        return nil
    end
    if type(db.notebook) ~= "table" then
        db.notebook = {}
    end
    local notebook = db.notebook
    if type(notebook.pages) ~= "table" then
        notebook.pages = {}
    end
    if type(notebook.sections) ~= "table" then
        notebook.sections = {}
    end
    if type(notebook.blocks) ~= "table" then
        notebook.blocks = {}
    end
    if type(notebook.quickNotes) ~= "table" then
        notebook.quickNotes = {}
    end
    if type(notebook.pageOrder) ~= "table" then
        notebook.pageOrder = {}
    end
    if type(notebook.quickNoteOrder) ~= "table" then
        notebook.quickNoteOrder = {}
    end
    if type(db.nextIds) ~= "table" then
        db.nextIds = {}
    end

    for id, section in pairs(notebook.sections) do
        if type(section) ~= "table" or type(section.pageId) ~= "string" or type(notebook.pages[section.pageId]) ~= "table" then
            notebook.sections[id] = nil
        elseif type(section.blockOrder) ~= "table" then
            section.blockOrder = {}
        end
    end
    for id, block in pairs(notebook.blocks) do
        if type(block) ~= "table" or type(block.sectionId) ~= "string" or type(notebook.sections[block.sectionId]) ~= "table" then
            notebook.blocks[id] = nil
        end
    end

    local function keepOrder(order, map, accept)
        local seen = {}
        local fresh = {}
        for index = 1, #order do
            local id = order[index]
            local row = type(id) == "string" and map[id] or nil
            if row and not seen[id] and (not accept or accept(row)) then
                seen[id] = true
                fresh[#fresh + 1] = id
            end
        end
        for id, row in pairs(map) do
            if type(id) == "string" and type(row) == "table" and not seen[id] and (not accept or accept(row)) then
                seen[id] = true
                fresh[#fresh + 1] = id
            end
        end
        return fresh, seen
    end

    for id, page in pairs(notebook.pages) do
        if type(page) ~= "table" then
            notebook.pages[id] = nil
        end
    end
    for id, note in pairs(notebook.quickNotes) do
        if type(note) ~= "table" then
            notebook.quickNotes[id] = nil
        elseif note.type ~= "REFERENCE" and note.type ~= "TASK" and note.type ~= "RECURRING" then
            -- A note saved before recurring FYIs is persistent information.
            note.type = "REFERENCE"
            note.trigger = nil
        end
    end
    notebook.pageOrder = keepOrder(notebook.pageOrder, notebook.pages)
    notebook.quickNoteOrder = keepOrder(notebook.quickNoteOrder, notebook.quickNotes)
    for _, page in pairs(notebook.pages) do
        if type(page.sectionOrder) ~= "table" then
            page.sectionOrder = {}
        end
        page.sectionOrder = keepOrder(page.sectionOrder, notebook.sections, function(section)
            return section.pageId == page.id
        end)
        page.pinned = page.pinned and true or false
    end
    for _, section in pairs(notebook.sections) do
        section.collapsed = section.collapsed and true or false
        section.blockOrder = keepOrder(section.blockOrder, notebook.blocks, function(block)
            return block.sectionId == section.id
        end)
    end

    db.nextIds.notebookPage = HighestId(notebook.pages, "p", NotebookNumber(db.nextIds, "notebookPage"))
    db.nextIds.notebookSection = HighestId(notebook.sections, "s", NotebookNumber(db.nextIds, "notebookSection"))
    db.nextIds.notebookBlock = HighestId(notebook.blocks, "b", NotebookNumber(db.nextIds, "notebookBlock"))
    db.nextIds.notebookNote = HighestId(notebook.quickNotes, "q", NotebookNumber(db.nextIds, "notebookNote"))
    local itemNext = NotebookNumber(db.nextIds, "notebookItem")
    for _, block in pairs(notebook.blocks) do
        if type(block.items) == "table" then
            for index = 1, #block.items do
                local item = block.items[index]
                local number = type(item) == "table" and tonumber(tostring(item.id):match("^c(%d+)$"))
                if number and number >= itemNext then
                    itemNext = number + 1
                end
            end
        end
    end
    db.nextIds.notebookItem = itemNext
    return notebook
end

-- Recurring FYIs live beside quick notes. Retention never deletes them.
function WBF.Database.EnsureContextFyis(db)
    db = db or WarbandFYI_DB
    local notebook = WBF.Database.EnsureNotebook(db)
    if type(notebook) ~= "table" then
        return nil
    end
    if type(notebook.contextFyis) ~= "table" then
        notebook.contextFyis = {}
    end
    if type(notebook.contextFyiOrder) ~= "table" then
        notebook.contextFyiOrder = {}
    end
    if type(notebook.fyiHistory) ~= "table" then
        notebook.fyiHistory = {}
    end
    if type(notebook.fyiNotice) ~= "table" then
        notebook.fyiNotice = {}
    end
    if type(notebook.fyiNotice.seen) ~= "table" then
        notebook.fyiNotice.seen = {}
    end
    if type(notebook.fyiTextures) ~= "table" then
        notebook.fyiTextures = {}
    end
    if type(db.nextIds) ~= "table" then
        db.nextIds = {}
    end
    if type(db.nextIds.contextFyi) ~= "number" or db.nextIds.contextFyi < 1 then
        db.nextIds.contextFyi = 1
    end
    if type(db.nextIds.contextItem) ~= "number" or db.nextIds.contextItem < 1 then
        db.nextIds.contextItem = 1
    end
    local seen = {}
    local fresh = {}
    for index = 1, #notebook.contextFyiOrder do
        local id = notebook.contextFyiOrder[index]
        if type(id) == "string" and type(notebook.contextFyis[id]) == "table" and not seen[id] then
            seen[id] = true
            fresh[#fresh + 1] = id
        end
    end
    for id, row in pairs(notebook.contextFyis) do
        if type(row) ~= "table" then
            notebook.contextFyis[id] = nil
        elseif type(id) == "string" and not seen[id] then
            seen[id] = true
            fresh[#fresh + 1] = id
        end
    end
    notebook.contextFyiOrder = fresh
    local nextFyi = math.floor(tonumber(db.nextIds.contextFyi) or 1)
    for id in pairs(notebook.contextFyis) do
        local number = tonumber(tostring(id):match("^y(%d+)$"))
        if number and number >= nextFyi then
            nextFyi = number + 1
        end
    end
    db.nextIds.contextFyi = nextFyi
    local nextItem = math.floor(tonumber(db.nextIds.contextItem) or 1)
    for _, entry in pairs(notebook.contextFyis) do
        if type(entry.items) == "table" then
            for index = 1, #entry.items do
                local item = entry.items[index]
                local number = type(item) == "table" and tonumber(tostring(item.id):match("^i(%d+)$"))
                if number and number >= nextItem then
                    nextItem = number + 1
                end
            end
        end
    end
    db.nextIds.contextItem = nextItem
    return notebook
end

local function MarkSummaryDirty()
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
end

local function DedupePrefix(key)
    if type(key) ~= "string" then
        return nil
    end
    return key:match("^([^:]+)")
end

local function EmbeddedStamp(key)
    if type(key) ~= "string" then
        return nil
    end
    local stamp = tonumber(key:match(":(%d+)$"))
    if stamp and stamp > 1000000000 and stamp < 4000000000 then
        return stamp
    end
    return nil
end

local function SeedGoldLast(db)
    if type(db.goldLast) ~= "table" then
        db.goldLast = {}
    end
    if type(db.maintenance) ~= "table" then
        db.maintenance = {}
    end
    local sessions = db.sessions or {}
    for index = #sessions, 1, -1 do
        local session = sessions[index]
        local byCharacter = session and not session.sample and session.goldByCharacter
        if type(byCharacter) == "table" then
            for guid, state in pairs(byCharacter) do
                if db.goldLast[guid] == nil and type(state) == "table" and type(state.lastMoney) == "number" then
                    db.goldLast[guid] = state.lastMoney
                end
            end
        end
    end
    local characters = db.characters or {}
    for guid, character in pairs(characters) do
        if db.goldLast[guid] == nil and type(character) == "table" and type(character.money) == "number" and not character.sample then
            db.goldLast[guid] = character.money
        end
    end
end

local function MigrateDedupe(db)
    if type(db.dedupe) ~= "table" then
        db.dedupe = {}
        return
    end
    for key, value in pairs(db.dedupe) do
        if value == true then
            local prefix = DedupePrefix(key)
            if prefix and not PERMANENT_DEDUPE[prefix] then
                local stamp = EmbeddedStamp(key)
                if stamp then
                    db.dedupe[key] = stamp
                end
            end
        end
    end
end

local function MigrationTrim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function MigrationClip(value, max)
    value = MigrationTrim(value)
    if #value > max then
        value = value:sub(1, max)
    end
    return value
end

local function MigrationContext(entry)
    local bits = {}
    if type(entry.character) == "string" and entry.character ~= "" then
        local name = nil
        if WBF.Characters and WBF.Characters.Get then
            local character = WBF.Characters.Get(entry.character)
            name = character and character.name or nil
        end
        if type(name) == "string" and name ~= "" then
            bits[#bits + 1] = name
        else
            bits[#bits + 1] = "Character"
        end
    end
    local keys = { "expansion", "zone", "category" }
    for index = 1, #keys do
        local value = MigrationTrim(entry[keys[index]])
        if value ~= "" then
            bits[#bits + 1] = value
        end
    end
    if #bits == 0 then
        return nil
    end
    return table.concat(bits, " · ")
end

local function MigrationSort(list, descending)
    table.sort(list, function(a, b)
        local left = a.createdAt or 0
        local right = b.createdAt or 0
        if left == right then
            return (a.id or "") < (b.id or "")
        end
        if descending then
            return left > right
        end
        return left < right
    end)
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then
        if type(value) == "function" or type(value) == "userdata" then
            return nil
        end
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        if type(key) ~= "function" and type(item) ~= "function" then
            copy[DeepCopy(key, seen)] = DeepCopy(item, seen)
        end
    end
    return copy
end

-- Plans become pages, sections, blocks, and loose notes. The original plans
-- table is kept under notebookLegacy so fields the notebook does not show
-- are not thrown away. One pass, then plans is cleared so a later login
-- cannot convert them again.
local function MigratePlansToNotebook(db)
    local notebook = {
        pages = {},
        pageOrder = {},
        sections = {},
        blocks = {},
        quickNotes = {},
        quickNoteOrder = {},
    }
    local nextPage, nextSection, nextBlock, nextItem, nextNote = 1, 1, 1, 1, 1
    local plans = type(db.plans) == "table" and db.plans or {}
    local links = {}
    if type(db.plans) == "table" then
        db.notebookLegacy = {
            source = "plans",
            plans = DeepCopy(db.plans),
            converted = true,
            links = links,
        }
    end
    local groups = type(plans.groups) == "table" and plans.groups or {}
    local entries = type(plans.entries) == "table" and plans.entries or {}

    local function pageId()
        local id = "p" .. nextPage
        nextPage = nextPage + 1
        return id
    end
    local function sectionId()
        local id = "s" .. nextSection
        nextSection = nextSection + 1
        return id
    end
    local function blockId()
        local id = "b" .. nextBlock
        nextBlock = nextBlock + 1
        return id
    end
    local function itemId()
        local id = "c" .. nextItem
        nextItem = nextItem + 1
        return id
    end

    local function addPage(name, summary, createdAt, updatedAt)
        local title = MigrationClip(name, 80)
        if title == "" then
            title = "Page"
        end
        local description = MigrationClip(summary or "", 160)
        local now = createdAt or 0
        local id = pageId()
        notebook.pages[id] = {
            id = id,
            title = title,
            summary = description ~= "" and description or nil,
            pinned = false,
            sectionOrder = {},
            createdAt = now,
            updatedAt = updatedAt or now,
        }
        notebook.pageOrder[#notebook.pageOrder + 1] = id
        return notebook.pages[id]
    end

    local function addSection(page, createdAt)
        local id = sectionId()
        local section = {
            id = id,
            pageId = page.id,
            title = "Notes",
            collapsed = false,
            blockOrder = {},
            createdAt = createdAt or page.createdAt or 0,
            updatedAt = createdAt or page.updatedAt or 0,
        }
        notebook.sections[id] = section
        page.sectionOrder[#page.sectionOrder + 1] = id
        return section
    end

    local function stamp(row, fallback)
        local created = row.createdAt
        if type(created) ~= "number" then
            created = fallback or 0
        end
        local updated = row.updatedAt
        if type(updated) ~= "number" then
            updated = created
        end
        return created, updated
    end

    local function addBlock(section, entry)
        local created, updated = stamp(entry, section.createdAt)
        local id = blockId()
        local block = {
            id = id,
            sectionId = section.id,
            createdAt = created,
            updatedAt = updated,
        }
        if entry.type == "achievement" then
            local achievementID = tonumber(entry.achievementID)
            if not achievementID or achievementID ~= math.floor(achievementID) or achievementID < 1 then
                return
            end
            block.type = "achievement"
            block.achievementID = achievementID
        elseif entry.type == "task" or entry.type == "recurring" then
            local text = MigrationClip(entry.text, 800)
            local context = MigrationContext(entry)
            if context then
                if text ~= "" then
                    text = text .. " · " .. context
                else
                    text = context
                end
            end
            if text == "" then
                return
            end
            if #text > 800 then
                text = text:sub(1, 800)
            end
            local done = false
            if entry.type == "task" and (entry.status == "completed" or entry.archivedFrom == "completed") then
                done = true
            end
            block.type = "checklist"
            block.items = {
                { id = itemId(), text = text, done = done },
            }
        else
            local text = MigrationClip(entry.text, 800)
            local context = MigrationContext(entry)
            if context then
                if text ~= "" then
                    text = text .. "\n" .. context
                else
                    text = context
                end
            end
            if text == "" then
                return
            end
            if #text > 800 then
                text = text:sub(1, 800)
            end
            block.type = "text"
            block.text = text
        end
        notebook.blocks[id] = block
        section.blockOrder[#section.blockOrder + 1] = id
        if type(entry.id) == "string" then
            links[entry.id] = id
        end
        if updated > (section.updatedAt or 0) then
            section.updatedAt = updated
        end
        local page = notebook.pages[section.pageId]
        if page and updated > (page.updatedAt or 0) then
            page.updatedAt = updated
        end
        return id
    end

    local groupList = {}
    for _, group in pairs(groups) do
        if type(group) == "table" and type(group.id) == "string" then
            groupList[#groupList + 1] = group
        end
    end
    MigrationSort(groupList, false)

    local function belongs(entry, groupId)
        if groupId == nil then
            return type(entry.planID) ~= "string" or type(groups[entry.planID]) ~= "table"
        end
        return entry.planID == groupId
    end

    local function collect(groupId)
        local list = {}
        for _, entry in pairs(entries) do
            if type(entry) == "table" and belongs(entry, groupId) then
                list[#list + 1] = entry
            end
        end
        MigrationSort(list, false)
        return list
    end

    local function addIntro(section, text, created, updated)
        text = MigrationClip(text, 800)
        if text == "" then
            return nil
        end
        local id = blockId()
        notebook.blocks[id] = {
            id = id,
            sectionId = section.id,
            type = "text",
            text = text,
            createdAt = created or 0,
            updatedAt = updated or created or 0,
        }
        section.blockOrder[#section.blockOrder + 1] = id
        return id
    end

    for index = 1, #groupList do
        local group = groupList[index]
        local page = addPage(group.name, group.description, group.createdAt, group.updatedAt)
        if type(group.id) == "string" then
            links[group.id] = page.id
        end
        local owned = collect(group.id)
        if #owned > 0 or page.summary then
            local section = addSection(page, page.createdAt)
            if page.summary then
                addIntro(section, page.summary, page.createdAt, page.updatedAt)
            end
            for entryIndex = 1, #owned do
                addBlock(section, owned[entryIndex])
            end
            if #section.blockOrder == 0 then
                notebook.sections[section.id] = nil
                page.sectionOrder = {}
            end
        end
    end

    local loose = collect(nil)
    local looseAchievements = {}
    local looseNotes = {}
    for index = 1, #loose do
        local entry = loose[index]
        if entry.type == "achievement" then
            looseAchievements[#looseAchievements + 1] = entry
        else
            looseNotes[#looseNotes + 1] = entry
        end
    end
    MigrationSort(looseNotes, true)
    for index = 1, #looseNotes do
        local entry = looseNotes[index]
        local text = MigrationClip(entry.text, 800)
        local context = MigrationContext(entry)
        if context then
            if text ~= "" then
                text = text .. "\n" .. context
            else
                text = context
            end
        end
        if #text > 800 then
            text = text:sub(1, 800)
        end
        if text ~= "" then
            local created, updated = stamp(entry, 0)
            local id = "q" .. nextNote
            nextNote = nextNote + 1
            notebook.quickNotes[id] = {
                id = id,
                text = text,
                createdAt = created,
                updatedAt = updated,
            }
            notebook.quickNoteOrder[#notebook.quickNoteOrder + 1] = id
            if type(entry.id) == "string" then
                links[entry.id] = id
            end
        end
    end
    if #looseAchievements > 0 then
        local page = addPage("Notes", nil, looseAchievements[1].createdAt, looseAchievements[1].updatedAt)
        local section = addSection(page, page.createdAt)
        for index = 1, #looseAchievements do
            addBlock(section, looseAchievements[index])
        end
        if #section.blockOrder == 0 then
            notebook.sections[section.id] = nil
            notebook.pages[page.id] = nil
            notebook.pageOrder[#notebook.pageOrder] = nil
        end
    end

    db.notebook = notebook
    db.plans = nil
    if type(db.nextIds) ~= "table" then
        db.nextIds = {}
    end
    db.nextIds.notebookPage = nextPage
    db.nextIds.notebookSection = nextSection
    db.nextIds.notebookBlock = nextBlock
    db.nextIds.notebookItem = nextItem
    db.nextIds.notebookNote = nextNote
    if type(db.config) == "table" and db.config.lastView == "plans" then
        db.config.lastView = "notebook"
    end
end

-- Migrations[n] upgrades a database whose schemaVersion is n.
-- The stored version is advanced only after the step returns.
local Migrations = {}

Migrations[1] = function(db)
    SeedGoldLast(db)
    if db.currentInstance ~= nil and type(db.currentInstance) ~= "table" then
        db.currentInstance = nil
    end
    MigrateDedupe(db)
end

Migrations[2] = function(db)
    WBF.Database.EnsurePlans(db)
end

Migrations[3] = function(db)
    MigratePlansToNotebook(db)
end

-- Schema 4 already converted plans and cleared them. If a plans table is
-- still present beside a filled notebook, keep it in the backup and leave
-- the notebook alone. An empty notebook can still be converted once.
Migrations[4] = function(db)
    if type(db.notebookLegacy) == "table" then
        db.plans = nil
        return
    end
    if type(db.plans) ~= "table" then
        return
    end
    local notebook = type(db.notebook) == "table" and db.notebook or nil
    local occupied = false
    if notebook then
        if type(notebook.pageOrder) == "table" and #notebook.pageOrder > 0 then
            occupied = true
        end
        if type(notebook.quickNoteOrder) == "table" and #notebook.quickNoteOrder > 0 then
            occupied = true
        end
    end
    if occupied then
        db.notebookLegacy = {
            source = "plans",
            plans = DeepCopy(db.plans),
            converted = false,
        }
        db.plans = nil
        return
    end
    MigratePlansToNotebook(db)
end

-- Legacy quick notes gain a Reference type. The new FYI maps start empty.
Migrations[5] = function(db)
    local notebook = WBF.Database.EnsureNotebook(db)
    if type(notebook) == "table" and type(notebook.quickNotes) == "table" then
        for _, note in pairs(notebook.quickNotes) do
            if type(note) == "table" and note.type ~= "REFERENCE" and note.type ~= "TASK" and note.type ~= "RECURRING" then
                note.type = "REFERENCE"
                note.trigger = nil
            end
        end
    end
    WBF.Database.EnsureContextFyis(db)
end

-- Schema 7 introduces maintenance/diagnostic counters only. It does not
-- rewrite user content or tracking history.
Migrations[6] = function(db)
    if type(db.maintenance) ~= "table" then
        db.maintenance = {}
    end
    local maintenance = db.maintenance
    maintenance.resourceDuplicateClaims = tonumber(maintenance.resourceDuplicateClaims) or 0
    maintenance.resourceEventsRecorded = tonumber(maintenance.resourceEventsRecorded) or 0
    maintenance.invalidRoutesBlocked = tonumber(maintenance.invalidRoutesBlocked) or 0
    maintenance.totalPruned = tonumber(maintenance.totalPruned) or 0
    maintenance.lastPruneRemoved = tonumber(maintenance.lastPruneRemoved) or 0
end

local function ApplyMigrations(db)
    local version = db.schemaVersion
    if type(version) ~= "number" or version < 1 then
        version = 1
    end

    -- Keep one full pre-migration snapshot in its own SavedVariable. This is
    -- intentionally outside WarbandFYI_DB so migration code cannot mutate the
    -- safety copy while upgrading the live database.
    if version < CURRENT_SCHEMA_VERSION then
        -- A step that failed on an earlier login leaves a partly upgraded db.
        -- Keep the older snapshot rather than replacing it with that state.
        local shouldBackup = type(WarbandFYI_Backup) ~= "table"
            or WarbandFYI_Backup.targetSchema ~= CURRENT_SCHEMA_VERSION
            or type(WarbandFYI_Backup.fromSchema) ~= "number"
            or WarbandFYI_Backup.fromSchema > version
        if shouldBackup then
            WarbandFYI_Backup = {
                createdAt = WBF.Time and WBF.Time.Now and WBF.Time.Now() or time(),
                addonVersion = WBF.VERSION,
                fromSchema = version,
                targetSchema = CURRENT_SCHEMA_VERSION,
                data = DeepCopy(db),
            }
        end
    end

    while version < CURRENT_SCHEMA_VERSION do
        local step = Migrations[version]
        if type(step) ~= "function" then
            WBF.Debug.Log("Database migration missing for schema", version)
            return
        end
        local ok, err = pcall(step, db)
        if not ok then
            WBF.Debug.Log("Database migration failed", version, err)
            return
        end
        version = version + 1
        db.schemaVersion = version
    end
end

local function FillConfig(config, defaults)
    for key, value in pairs(defaults) do
        if config[key] == nil then
            config[key] = value
        end
    end
end

function WBF.Database.IsReady()
    return WBF.Database.ready == true
end

function WBF.Database.Get()
    return WarbandFYI_DB
end

function WBF.Database.Init()
    if type(WarbandFYI_DB) ~= "table" then
        WarbandFYI_DB = Defaults()
    end

    local db = WarbandFYI_DB
    if type(db.config) ~= "table" then
        db.config = {}
    end
    FillConfig(db.config, Defaults().config)

    if type(db.nextIds) ~= "table" then
        db.nextIds = { session = 1, event = 1 }
    end
    db.nextIds.session = db.nextIds.session or 1
    db.nextIds.event = db.nextIds.event or 1
    local function highestId(list)
        local highest = 0
        if type(list) ~= "table" then
            return highest
        end
        for index = 1, #list do
            local row = list[index]
            local id = type(row) == "table" and tonumber(row.id) or nil
            if id and id > highest then
                highest = id
            end
        end
        return highest
    end
    local function raise(field, highest)
        local current = math.floor(tonumber(db.nextIds[field]) or 1)
        if current < 1 then
            current = 1
        end
        if highest >= current then
            db.nextIds[field] = math.floor(highest) + 1
        else
            db.nextIds[field] = current
        end
    end
    raise("session", highestId(db.sessions))
    raise("event", highestId(db.events))

    if type(db.sessions) ~= "table" then
        db.sessions = {}
    end
    if type(db.characters) ~= "table" then
        db.characters = {}
    end
    if type(db.snapshots) ~= "table" then
        db.snapshots = {}
    end
    if type(db.events) ~= "table" then
        db.events = {}
    end
    if type(db.dedupe) ~= "table" then
        db.dedupe = {}
    end
    if type(db.goldLast) ~= "table" then
        db.goldLast = {}
    end
    if type(db.housing) ~= "table" then
        db.housing = {}
    end
    if type(db.housing.collected) ~= "table" then
        db.housing.collected = {}
    end
    if type(db.housing.favor) ~= "table" then
        db.housing.favor = {}
    end
    if WBF.Characters and WBF.Characters.Migrate then
        WBF.Characters.Migrate(db)
    end

    ApplyMigrations(db)
    WBF.Database.EnsureNotebook(db)
    if WBF.NotebookSheet and WBF.NotebookSheet.OnLoad then
        WBF.NotebookSheet.OnLoad()
    end
    if WBF.NotebookFyi and WBF.NotebookFyi.OnLoad then
        WBF.NotebookFyi.OnLoad()
    end
    WBF.Database.EnsureContextFyis(db)
    if WBF.ContextFyi and WBF.ContextFyi.OnLoad then
        WBF.ContextFyi.OnLoad()
    end
    if type(db.monthHistory) ~= "table" then
        db.monthHistory = {}
    end
    WBF.Database.ready = true
    -- Freeze completed months before retention deletes the rows they were built from.
    if WBF.MonthHistory and WBF.MonthHistory.FinalizeCompleted then
        local ok, err = pcall(WBF.MonthHistory.FinalizeCompleted)
        if not ok then
            WBF.Debug.Log("Month finalize failed", err)
        end
    end
    WBF.Database.Prune(true)
    WBF.Debug.Log("Database ready, schema", db.schemaVersion)
end

function WBF.Database.AllocSessionId()
    local db = WarbandFYI_DB
    local id = db.nextIds.session
    db.nextIds.session = id + 1
    return id
end

function WBF.Database.AllocEventId()
    local db = WarbandFYI_DB
    local id = db.nextIds.event
    db.nextIds.event = id + 1
    return id
end

-- Lifetime totals outlive the rows retention deletes. They start empty and
-- only grow by the records about to be removed, so a later scan of what
-- remains cannot count those records again.
local function LifetimeRoot(db)
    if type(db.lifetime) ~= "table" then
        db.lifetime = {}
    end
    local life = db.lifetime
    if type(life.totals) ~= "table" then
        life.totals = {}
    end
    if type(life.characters) ~= "table" then
        life.characters = {}
    end
    if type(life.gold) ~= "table" then
        life.gold = {}
    end
    if type(life.gold.byGuid) ~= "table" then
        life.gold.byGuid = {}
    end
    if type(life.gold.offlineByGuid) ~= "table" then
        life.gold.offlineByGuid = {}
    end
    return life
end

local function LifetimeCharacter(life, guid)
    local row = life.characters[guid]
    if type(row) ~= "table" then
        row = { playedSeconds = 0, counts = {} }
        life.characters[guid] = row
    end
    if type(row.counts) ~= "table" then
        row.counts = {}
    end
    if type(row.playedSeconds) ~= "number" then
        row.playedSeconds = 0
    end
    return row
end

local function NoteEarliest(row, field, at, value)
    if type(at) ~= "number" or value == nil then
        return
    end
    local atKey = field .. "At"
    if row[atKey] == nil or at < row[atKey] then
        row[atKey] = at
        row[field] = value
    end
end

function WBF.Database.FoldDiscardedEvent(event)
    if type(event) ~= "table" or event.sample then
        return
    end
    if type(event.meta) == "table" and event.meta.simulated then
        return
    end
    local db = WarbandFYI_DB
    if type(db) ~= "table" then
        return
    end
    local life = LifetimeRoot(db)
    if WBF.Aggregator and WBF.Aggregator.CountEvent then
        WBF.Aggregator.CountEvent(life.totals, event)
        if type(event.guid) == "string" then
            local row = LifetimeCharacter(life, event.guid)
            WBF.Aggregator.CountEvent(row.counts, event)
        end
    end
    if WBF.Crafts and WBF.Crafts.FoldEvent then
        WBF.Crafts.FoldEvent(life, event)
    end
    if WBF.Resources and WBF.Resources.FoldExpired then
        WBF.Resources.FoldExpired(event)
    end
end

function WBF.Database.FoldDiscardedSnapshot(snapshot)
    if type(snapshot) ~= "table" or snapshot.sample or type(snapshot.guid) ~= "string" then
        return
    end
    local db = WarbandFYI_DB
    if type(db) ~= "table" then
        return
    end
    local row = LifetimeCharacter(LifetimeRoot(db), snapshot.guid)
    NoteEarliest(row, "level", snapshot.at, snapshot.level)
    NoteEarliest(row, "itemLevel", snapshot.at, snapshot.itemLevel)
end

function WBF.Database.FoldDiscardedSession(session)
    if type(session) ~= "table" or session.sample then
        return
    end
    local db = WarbandFYI_DB
    if type(db) ~= "table" then
        return
    end
    if session.id ~= nil and session.id == db.activeSessionId then
        return
    end
    local life = LifetimeRoot(db)
    local segments = session.segments or {}
    for index = 1, #segments do
        local segment = segments[index]
        local started = segment.startedAt
        local ended = segment.endedAt or session.endedAt
        if type(segment.guid) == "string" and type(started) == "number" and type(ended) == "number" and ended > started then
            local row = LifetimeCharacter(life, segment.guid)
            row.playedSeconds = row.playedSeconds + (ended - started)
        end
    end
    if type(session.goldLedger) == "table" then
        for index = 1, #session.goldLedger do
            local entry = session.goldLedger[index]
            if type(entry) == "table" and type(entry.guid) == "string" then
                local delta = entry.delta or 0
                life.gold.net = (life.gold.net or 0) + delta
                life.gold.byGuid[entry.guid] = (life.gold.byGuid[entry.guid] or 0) + delta
                life.gold.tracked = true
                if entry.source == "betweenSessions" then
                    life.gold.offlineByGuid[entry.guid] = (life.gold.offlineByGuid[entry.guid] or 0) + delta
                end
            end
        end
    elseif type(session.goldByCharacter) == "table" then
        for guid, state in pairs(session.goldByCharacter) do
            if type(guid) == "string" and type(state) == "table" then
                local delta = state.netChange or 0
                if delta ~= 0 then
                    life.gold.net = (life.gold.net or 0) + delta
                    life.gold.byGuid[guid] = (life.gold.byGuid[guid] or 0) + delta
                    life.gold.tracked = true
                end
            end
        end
    end
    if WBF.WorldActivity and WBF.WorldActivity.FoldSession then
        WBF.WorldActivity.FoldSession(life, session)
    end
end

local function TrimArray(field, limit, keep, fold)
    local db = WarbandFYI_DB
    local source = db[field]
    if #source <= limit then
        return
    end
    local fresh = {}
    local startAt = #source - keep + 1
    for index = 1, startAt - 1 do
        if fold then
            fold(source[index])
        end
    end
    for index = startAt, #source do
        fresh[#fresh + 1] = source[index]
    end
    db[field] = fresh
end

function WBF.Database.AddSnapshot(fields)
    local db = WarbandFYI_DB
    if not fields.level and not fields.itemLevel and not fields.money then
        return nil
    end

    local snapshot = {
        at = fields.at or WBF.Time.Now(),
        sessionId = fields.sessionId,
        guid = fields.guid,
        reason = fields.reason,
        level = fields.level,
        itemLevel = fields.itemLevel,
        money = fields.money,
        sample = fields.sample,
    }

    local snapshots = db.snapshots
    for index = #snapshots, 1, -1 do
        local previous = snapshots[index]
        if previous.guid == snapshot.guid then
            local sameValues = previous.level == snapshot.level
                and previous.itemLevel == snapshot.itemLevel
                and previous.money == snapshot.money
            local previousAt = type(previous.at) == "number" and previous.at or nil
            local snapshotAt = type(snapshot.at) == "number" and snapshot.at or nil
            if sameValues and previousAt and snapshotAt and (snapshotAt - previousAt) < 180 and not snapshot.sample then
                return nil
            end
            break
        end
    end

    snapshots[#snapshots + 1] = snapshot
    TrimArray("snapshots", MAX_SNAPSHOTS, TRIM_SNAPSHOTS_TO, WBF.Database.FoldDiscardedSnapshot)
    MarkSummaryDirty()
    return snapshot
end

function WBF.Database.HasDedupe(key)
    local value = WarbandFYI_DB.dedupe[key]
    return value == true or type(value) == "number"
end

function WBF.Database.MarkDedupe(key, at)
    if not key then
        return
    end
    if at ~= nil then
        if WarbandFYI_DB.dedupe[key] == true then
            return
        end
        if type(at) == "number" then
            WarbandFYI_DB.dedupe[key] = at
        end
        return
    end
    WarbandFYI_DB.dedupe[key] = true
end

function WBF.Database.SeenWithin(key, seconds)
    local value = WarbandFYI_DB.dedupe[key]
    if type(value) ~= "number" or type(seconds) ~= "number" or seconds <= 0 then
        return false
    end
    local now = WBF.Time.Now()
    if value > now then
        return false
    end
    return (now - value) < seconds
end

function WBF.Database.NoteMaintenanceStat(key, amount)
    local db = WarbandFYI_DB
    if type(db) ~= "table" or type(key) ~= "string" or key == "" then
        return
    end
    if type(db.maintenance) ~= "table" then
        db.maintenance = {}
    end
    local value = tonumber(db.maintenance[key]) or 0
    db.maintenance[key] = value + (tonumber(amount) or 1)
end

function WBF.Database.RetentionDays()
    local config = WarbandFYI_DB and WarbandFYI_DB.config
    local days = config and config.retentionDays
    if type(days) ~= "number" or days ~= days or days == math.huge or days == -math.huge then
        return 120
    end
    if days < 1 then
        return nil
    end
    if days > MAX_RETENTION_DAYS then
        return MAX_RETENTION_DAYS
    end
    return math.floor(days)
end

function WBF.Database.RetentionCutoff(now)
    local days = WBF.Database.RetentionDays()
    if not days then
        return nil
    end
    return (now or WBF.Time.Now()) - (days * 86400)
end

local function SessionExpired(session, cutoff, activeId)
    if type(session) ~= "table" or session.endedAt == nil then
        return false
    end
    if session.id ~= nil and session.id == activeId then
        return false
    end
    if type(session.endedAt) ~= "number" or session.endedAt >= cutoff then
        return false
    end
    local started = session.startedAt
    if type(started) == "number" and started >= cutoff then
        return false
    end
    return true
end

local function KeepTimestamped(record, cutoff, activeId)
    if type(record) ~= "table" then
        return false
    end
    if activeId ~= nil and record.sessionId == activeId then
        return true
    end
    if type(record.at) ~= "number" then
        return true
    end
    return record.at >= cutoff
end

function WBF.Database.Prune(force)
    local db = WarbandFYI_DB
    if type(db) ~= "table" then
        return 0
    end
    local activeId = db.activeSessionId
    if not force and db.lastPruneSession == (activeId or 0) then
        return 0
    end
    local cutoff = WBF.Database.RetentionCutoff()
    db.lastPruneSession = activeId or 0
    db.lastPruneAt = WBF.Time.Now()
    if not cutoff then
        return 0
    end

    local removed = 0
    local sessions = {}
    for index = 1, #db.sessions do
        local session = db.sessions[index]
        if SessionExpired(session, cutoff, activeId) then
            WBF.Database.FoldDiscardedSession(session)
            removed = removed + 1
        else
            sessions[#sessions + 1] = session
        end
    end
    db.sessions = sessions

    local events = {}
    for index = 1, #db.events do
        local event = db.events[index]
        if KeepTimestamped(event, cutoff, activeId) then
            events[#events + 1] = event
        else
            WBF.Database.FoldDiscardedEvent(event)
            removed = removed + 1
        end
    end
    db.events = events

    local snapshots = {}
    for index = 1, #db.snapshots do
        local snapshot = db.snapshots[index]
        if KeepTimestamped(snapshot, cutoff, activeId) then
            snapshots[#snapshots + 1] = snapshot
        else
            WBF.Database.FoldDiscardedSnapshot(snapshot)
            removed = removed + 1
        end
    end
    db.snapshots = snapshots

    for key, value in pairs(db.dedupe) do
        local prefix = DedupePrefix(key)
        if not (prefix and PERMANENT_DEDUPE[prefix]) and value ~= true then
            local stamp = type(value) == "number" and value or EmbeddedStamp(key)
            if stamp and stamp < cutoff then
                db.dedupe[key] = nil
                removed = removed + 1
            end
        elseif not (prefix and PERMANENT_DEDUPE[prefix]) and value == true then
            local stamp = EmbeddedStamp(key)
            if stamp and stamp < cutoff then
                db.dedupe[key] = nil
                removed = removed + 1
            end
        end
    end

    if type(db.maintenance) ~= "table" then
        db.maintenance = {}
    end
    db.maintenance.lastPruneRemoved = removed
    db.maintenance.totalPruned = (tonumber(db.maintenance.totalPruned) or 0) + removed
    if removed > 0 then
        MarkSummaryDirty()
        WBF.Debug.Log("Retention removed", removed, "old records")
    end
    return removed
end

function WBF.Database.SaveWindow(frame)
    if not frame or frame:GetWidth() < 100 then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    WarbandFYI_DB.config.window = {
        point = point,
        relPoint = relativePoint,
        x = x,
        y = y,
        width = frame:GetWidth(),
        height = frame:GetHeight(),
    }
end

function WBF.Database.ClearSample()
    local db = WarbandFYI_DB
    local sessions = {}
    for index = 1, #db.sessions do
        if not db.sessions[index].sample then
            sessions[#sessions + 1] = db.sessions[index]
        end
    end
    db.sessions = sessions

    local snapshots = {}
    for index = 1, #db.snapshots do
        if not db.snapshots[index].sample then
            snapshots[#snapshots + 1] = db.snapshots[index]
        end
    end
    db.snapshots = snapshots

    local events = {}
    for index = 1, #db.events do
        if not db.events[index].sample then
            events[#events + 1] = db.events[index]
        end
    end
    db.events = events

    for guid in pairs(db.characters) do
        if type(guid) == "string" and guid:find("Player-0-SAMPLE", 1, true) then
            db.characters[guid] = nil
        end
    end

    if type(db.housing) == "table" and type(db.housing.collected) == "table" then
        for key, row in pairs(db.housing.collected) do
            if type(row) == "table" and row.sample then
                db.housing.collected[key] = nil
            end
        end
    end

    if type(db.resources) == "table" and type(db.resources.balances) == "table" then
        for key, balance in pairs(db.resources.balances) do
            if type(balance) == "table" and balance.sample then
                db.resources.balances[key] = nil
            end
        end
    end
    MarkSummaryDirty()
end
