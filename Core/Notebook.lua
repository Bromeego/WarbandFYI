local _, WBF = ...

-- Pages hold sections. Sections hold blocks. Quick notes sit beside pages
-- until the player files them. Order is the arrays, not the map iteration.
WBF.Notebook = {}

local MAX_PAGES = 80
local MAX_SECTIONS = 20
local MAX_BLOCKS = 60
local MAX_ITEMS = 30
local MAX_NOTES = 80
local MAX_TITLE = 80
local MAX_SUMMARY = 160
local MAX_TEXT = 800

local refreshing = false

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Clip(value, max)
    value = Trim(value)
    if #value > max then
        value = value:sub(1, max)
    end
    return value
end

local function Now()
    return WBF.Time.Now()
end

local function Say(text)
    print("|cffd4af37WarbandFYI|r " .. text)
end

function WBF.Notebook.Root()
    if not WBF.Database or not WBF.Database.Get then
        return nil
    end
    return WBF.Database.EnsureNotebook(WBF.Database.Get())
end

function WBF.Notebook.RefreshOpen()
    if refreshing then
        return
    end
    refreshing = true
    local frame = WBF.UI and WBF.UI.frame
    if frame and frame.Refresh and frame.IsShown and frame:IsShown() then
        local ok, err = pcall(frame.Refresh, frame, false)
        if not ok and WBF.Debug and WBF.Debug.Log then
            WBF.Debug.Log("Notebook refresh failed", err)
        end
    end
    if WBF.UI and WBF.UI.Sheet and WBF.UI.Sheet.Refresh then
        local ok, err = pcall(WBF.UI.Sheet.Refresh)
        if not ok and WBF.Debug and WBF.Debug.Log then
            WBF.Debug.Log("Sheet refresh failed", err)
        end
    end
    if WBF.UI and WBF.UI.Fyi and WBF.UI.Fyi.Refresh then
        local ok, err = pcall(WBF.UI.Fyi.Refresh)
        if not ok and WBF.Debug and WBF.Debug.Log then
            WBF.Debug.Log("FYI refresh failed", err)
        end
    end
    refreshing = false
end

local function Save(value)
    WBF.Notebook.RefreshOpen()
    return value
end

local function Touch(row)
    if row then
        row.updatedAt = Now()
    end
end

local function Alloc(kind)
    local root = WBF.Notebook.Root()
    local db = WBF.Database.Get()
    local fields = {
        page = { "notebookPage", "p", root.pages },
        section = { "notebookSection", "s", root.sections },
        block = { "notebookBlock", "b", root.blocks },
        note = { "notebookNote", "q", root.quickNotes },
    }
    local spec = fields[kind]
    local field, prefix, map = spec[1], spec[2], spec[3]
    local id = math.floor(tonumber(db.nextIds[field]) or 1)
    if id < 1 then
        id = 1
    end
    local key = prefix .. id
    while map[key] do
        id = id + 1
        key = prefix .. id
    end
    db.nextIds[field] = id + 1
    return key
end

local function AllocItem()
    local root = WBF.Notebook.Root()
    local db = WBF.Database.Get()
    local id = math.floor(tonumber(db.nextIds.notebookItem) or 1)
    if id < 1 then
        id = 1
    end
    local function taken(candidate)
        for _, block in pairs(root.blocks) do
            if type(block) == "table" and type(block.items) == "table" then
                for index = 1, #block.items do
                    local item = block.items[index]
                    if type(item) == "table" and item.id == candidate then
                        return true
                    end
                end
            end
        end
        return false
    end
    local key = "c" .. id
    while taken(key) do
        id = id + 1
        key = "c" .. id
    end
    db.nextIds.notebookItem = id + 1
    return key
end

local function RemoveId(list, id)
    if type(list) ~= "table" then
        return
    end
    for index = #list, 1, -1 do
        if list[index] == id then
            table.remove(list, index)
        end
    end
end

local function InsertAfter(list, id, afterId)
    if type(afterId) ~= "string" then
        list[#list + 1] = id
        return
    end
    for index = 1, #list do
        if list[index] == afterId then
            table.insert(list, index + 1, id)
            return
        end
    end
    list[#list + 1] = id
end

local function MoveId(list, id, delta)
    local index = nil
    for cursor = 1, #list do
        if list[cursor] == id then
            index = cursor
            break
        end
    end
    if not index then
        return false
    end
    local target = index + delta
    if target < 1 or target > #list then
        return false
    end
    list[index], list[target] = list[target], list[index]
    return true
end

local function Ordered(map, order, accept)
    local list = {}
    if type(map) ~= "table" or type(order) ~= "table" then
        return list
    end
    for index = 1, #order do
        local row = map[order[index]]
        if type(row) == "table" and (not accept or accept(row)) then
            list[#list + 1] = row
        end
    end
    return list
end

function WBF.Notebook.GetPage(id)
    local root = WBF.Notebook.Root()
    if not root or type(id) ~= "string" then
        return nil
    end
    local page = root.pages[id]
    if type(page) ~= "table" then
        return nil
    end
    return page
end

function WBF.Notebook.GetSection(id)
    local root = WBF.Notebook.Root()
    if not root or type(id) ~= "string" then
        return nil
    end
    local section = root.sections[id]
    if type(section) ~= "table" then
        return nil
    end
    return section
end

function WBF.Notebook.GetBlock(id)
    local root = WBF.Notebook.Root()
    if not root or type(id) ~= "string" then
        return nil
    end
    local block = root.blocks[id]
    if type(block) ~= "table" then
        return nil
    end
    return block
end

function WBF.Notebook.GetNote(id)
    local root = WBF.Notebook.Root()
    if not root or type(id) ~= "string" then
        return nil
    end
    local note = root.quickNotes[id]
    if type(note) ~= "table" then
        return nil
    end
    return note
end

function WBF.Notebook.Pages()
    local root = WBF.Notebook.Root()
    if not root then
        return {}
    end
    return Ordered(root.pages, root.pageOrder)
end

function WBF.Notebook.PinnedPages()
    local list = {}
    local pages = WBF.Notebook.Pages()
    for index = 1, #pages do
        if pages[index].pinned then
            list[#list + 1] = pages[index]
        end
    end
    return list
end

local function SeenAt(page)
    local updated = type(page.updatedAt) == "number" and page.updatedAt or 0
    local opened = type(page.openedAt) == "number" and page.openedAt or 0
    if opened > updated then
        return opened
    end
    return updated
end

function WBF.Notebook.TouchOpened(id)
    local page = WBF.Notebook.GetPage(id)
    if not page then
        return nil
    end
    page.openedAt = Now()
    return Save(page)
end

function WBF.Notebook.RecentPages(limit)
    local list = WBF.Notebook.Pages()
    table.sort(list, function(a, b)
        local left = SeenAt(a)
        local right = SeenAt(b)
        if left == right then
            return a.id < b.id
        end
        return left > right
    end)
    local recent = {}
    local cap = tonumber(limit)
    for index = 1, #list do
        if not list[index].pinned then
            recent[#recent + 1] = list[index]
            if cap and cap > 0 and #recent >= cap then
                break
            end
        end
    end
    return recent
end

function WBF.Notebook.ChecklistItems(block)
    local list = {}
    if type(block) ~= "table" or type(block.items) ~= "table" then
        if type(block) == "table" and block.type == "checklist" and block.items ~= nil and type(block.items) ~= "table" and WBF.Debug and WBF.Debug.Log then
            WBF.Debug.Log("Notebook checklist skipped", block.id)
        end
        return list
    end
    for index = 1, #block.items do
        local item = block.items[index]
        if type(item) == "table" then
            list[#list + 1] = item
        end
    end
    return list
end

function WBF.Notebook.Sections(pageId)
    local root = WBF.Notebook.Root()
    local page = WBF.Notebook.GetPage(pageId)
    if not root or not page then
        return {}
    end
    return Ordered(root.sections, page.sectionOrder, function(section)
        return section.pageId == pageId
    end)
end

function WBF.Notebook.Blocks(sectionId)
    local root = WBF.Notebook.Root()
    local section = WBF.Notebook.GetSection(sectionId)
    if not root or not section then
        return {}
    end
    return Ordered(root.blocks, section.blockOrder, function(block)
        return block.sectionId == sectionId
    end)
end

function WBF.Notebook.QuickNotes()
    local root = WBF.Notebook.Root()
    if not root then
        return {}
    end
    return Ordered(root.quickNotes, root.quickNoteOrder)
end

function WBF.Notebook.BlockCount(pageId)
    local total = 0
    local sections = WBF.Notebook.Sections(pageId)
    for index = 1, #sections do
        local blocks = WBF.Notebook.Blocks(sections[index].id)
        total = total + #blocks
    end
    return total
end

local function FindItem(block, itemId)
    if type(block) ~= "table" or type(block.items) ~= "table" or type(itemId) ~= "string" then
        return nil
    end
    for index = 1, #block.items do
        local item = block.items[index]
        if type(item) == "table" and item.id == itemId then
            return item, index
        end
    end
    return nil
end

function WBF.Notebook.CreatePage(title, summary)
    local root = WBF.Notebook.Root()
    if not root or #root.pageOrder >= MAX_PAGES then
        return nil
    end
    title = Clip(title, MAX_TITLE)
    if title == "" then
        return nil
    end
    summary = Clip(summary or "", MAX_SUMMARY)
    local now = Now()
    local page = {
        id = Alloc("page"),
        title = title,
        summary = summary ~= "" and summary or nil,
        pinned = false,
        sectionOrder = {},
        createdAt = now,
        updatedAt = now,
    }
    root.pages[page.id] = page
    root.pageOrder[#root.pageOrder + 1] = page.id
    return Save(page)
end

function WBF.Notebook.SetPage(id, title, summary)
    local page = WBF.Notebook.GetPage(id)
    if not page then
        return nil
    end
    title = Clip(title, MAX_TITLE)
    if title == "" then
        return nil
    end
    summary = Clip(summary or "", MAX_SUMMARY)
    local stored = summary ~= "" and summary or nil
    if page.title == title and page.summary == stored then
        return page
    end
    page.title = title
    page.summary = stored
    Touch(page)
    return Save(page)
end

function WBF.Notebook.SetPinned(id, pinned)
    local page = WBF.Notebook.GetPage(id)
    if not page then
        return nil
    end
    local flag = pinned and true or false
    if page.pinned == flag then
        return page
    end
    page.pinned = flag
    return Save(page)
end

function WBF.Notebook.DeletePage(id)
    local root = WBF.Notebook.Root()
    local page = WBF.Notebook.GetPage(id)
    if not root or not page then
        return false
    end
    if WBF.NotebookFyi and WBF.NotebookFyi.Forget then
        WBF.NotebookFyi.Forget("page", id)
    end
    local sections = {}
    for index = 1, #page.sectionOrder do
        sections[index] = page.sectionOrder[index]
    end
    for index = 1, #sections do
        WBF.Notebook.DeleteSection(sections[index])
    end
    root.pages[id] = nil
    RemoveId(root.pageOrder, id)
    Save(nil)
    return true
end

function WBF.Notebook.CreateSection(pageId, title, afterId)
    local root = WBF.Notebook.Root()
    local page = WBF.Notebook.GetPage(pageId)
    if not root or not page or #page.sectionOrder >= MAX_SECTIONS then
        return nil
    end
    title = Clip(title, MAX_TITLE)
    if title == "" then
        return nil
    end
    local now = Now()
    local section = {
        id = Alloc("section"),
        pageId = page.id,
        title = title,
        collapsed = false,
        blockOrder = {},
        createdAt = now,
        updatedAt = now,
    }
    root.sections[section.id] = section
    InsertAfter(page.sectionOrder, section.id, afterId)
    Touch(page)
    return Save(section)
end

function WBF.Notebook.RenameSection(id, title)
    local section = WBF.Notebook.GetSection(id)
    if not section then
        return nil
    end
    title = Clip(title, MAX_TITLE)
    if title == "" then
        return nil
    end
    if section.title == title then
        return section
    end
    section.title = title
    Touch(section)
    Touch(WBF.Notebook.GetPage(section.pageId))
    return Save(section)
end

function WBF.Notebook.SetCollapsed(id, collapsed)
    local section = WBF.Notebook.GetSection(id)
    if not section then
        return nil
    end
    local flag = collapsed and true or false
    if section.collapsed == flag then
        return section
    end
    section.collapsed = flag
    return Save(section)
end

function WBF.Notebook.MoveSection(id, delta)
    local section = WBF.Notebook.GetSection(id)
    local page = section and WBF.Notebook.GetPage(section.pageId) or nil
    if not section or not page then
        return nil
    end
    if not MoveId(page.sectionOrder, id, delta) then
        return section
    end
    Touch(page)
    return Save(section)
end

function WBF.Notebook.DeleteSection(id)
    local root = WBF.Notebook.Root()
    local section = WBF.Notebook.GetSection(id)
    if not root or not section then
        return false
    end
    if WBF.NotebookFyi and WBF.NotebookFyi.Forget then
        WBF.NotebookFyi.Forget("section", id)
    end
    local blocks = {}
    for index = 1, #section.blockOrder do
        blocks[index] = section.blockOrder[index]
    end
    for index = 1, #blocks do
        local blockId = blocks[index]
        root.blocks[blockId] = nil
    end
    local page = WBF.Notebook.GetPage(section.pageId)
    if page then
        RemoveId(page.sectionOrder, id)
        Touch(page)
    end
    root.sections[id] = nil
    Save(nil)
    return true
end

local function PlaceBlock(section, block, afterId)
    local root = WBF.Notebook.Root()
    root.blocks[block.id] = block
    InsertAfter(section.blockOrder, block.id, afterId)
    Touch(section)
    Touch(WBF.Notebook.GetPage(section.pageId))
    return Save(block)
end

function WBF.Notebook.AddText(sectionId, text, afterId)
    local section = WBF.Notebook.GetSection(sectionId)
    if not section or #section.blockOrder >= MAX_BLOCKS then
        return nil
    end
    text = Clip(text, MAX_TEXT)
    if text == "" then
        return nil
    end
    local now = Now()
    return PlaceBlock(section, {
        id = Alloc("block"),
        sectionId = section.id,
        type = "text",
        text = text,
        createdAt = now,
        updatedAt = now,
    }, afterId)
end

function WBF.Notebook.SetText(id, text)
    local block = WBF.Notebook.GetBlock(id)
    if not block or block.type ~= "text" then
        return nil
    end
    text = Clip(text, MAX_TEXT)
    if text == "" then
        return nil
    end
    if block.text == text then
        return block
    end
    block.text = text
    Touch(block)
    local section = WBF.Notebook.GetSection(block.sectionId)
    Touch(section)
    if section then
        Touch(WBF.Notebook.GetPage(section.pageId))
    end
    return Save(block)
end

function WBF.Notebook.AddChecklist(sectionId, text, afterId)
    local section = WBF.Notebook.GetSection(sectionId)
    if not section or #section.blockOrder >= MAX_BLOCKS then
        return nil
    end
    text = Clip(text, MAX_TEXT)
    if text == "" then
        return nil
    end
    local now = Now()
    return PlaceBlock(section, {
        id = Alloc("block"),
        sectionId = section.id,
        type = "checklist",
        items = {
            { id = AllocItem(), text = text, done = false },
        },
        createdAt = now,
        updatedAt = now,
    }, afterId)
end

local function TouchBlock(block)
    Touch(block)
    local section = WBF.Notebook.GetSection(block.sectionId)
    Touch(section)
    if section then
        Touch(WBF.Notebook.GetPage(section.pageId))
    end
end

function WBF.Notebook.DeleteLabel(kind, title)
    local prompts = {
        text = "Delete this note?",
        note = "Delete this note?",
        checklist = "Delete this checklist?",
        achievement = "Delete this achievement?",
        waypoint = "Delete this waypoint?",
        resource = "Delete this resource?",
        reference = "Delete this reference?",
        section = "Delete this section?",
        page = "Delete this page?",
    }
    local label = prompts[kind] or "Delete this?"
    title = Trim(title or "")
    title = title:gsub("[\r\n]+", " ")
    if #title > 48 then
        title = title:sub(1, 45) .. "..."
    end
    if title ~= "" then
        return label .. " " .. title
    end
    return label
end

function WBF.Notebook.ChecklistCapture(blockId, text)
    if Trim(text) == "" then
        return nil, "blank"
    end
    local item = WBF.Notebook.AddChecklistItem(blockId, text)
    if not item then
        return nil, "failed"
    end
    return item, "next"
end

function WBF.Notebook.AddChecklistItem(blockId, text)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "checklist" then
        return nil
    end
    if type(block.items) ~= "table" then
        block.items = {}
    end
    if #block.items >= MAX_ITEMS then
        return nil
    end
    text = Clip(text, MAX_TEXT)
    if text == "" then
        return nil
    end
    local item = { id = AllocItem(), text = text, done = false }
    block.items[#block.items + 1] = item
    TouchBlock(block)
    Save(block)
    return item
end

function WBF.Notebook.SetChecklistItem(blockId, itemId, text)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "checklist" then
        return nil
    end
    local item, index = FindItem(block, itemId)
    if not item then
        return nil
    end
    text = Clip(text, MAX_TEXT)
    if text == "" then
        table.remove(block.items, index)
        TouchBlock(block)
        return Save(block)
    end
    if item.text == text then
        return item
    end
    item.text = text
    TouchBlock(block)
    Save(block)
    return item
end

function WBF.Notebook.SetChecklistCompletionMode(blockId, itemId, mode)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "checklist" then
        return nil
    end
    local item = FindItem(block, itemId)
    if not item then
        return nil
    end
    local wanted = mode == "PERMANENT" and "PERMANENT" or nil
    if item.completionMode == wanted then
        return item
    end
    item.completionMode = wanted
    TouchBlock(block)
    Save(block)
    return item
end

function WBF.Notebook.GetChecklistItem(blockId, itemId)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "checklist" then
        return nil
    end
    return FindItem(block, itemId)
end

function WBF.Notebook.SetChecklistProgress(blockId, itemId, sourceBlockId, target)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "checklist" then
        return nil
    end
    local item = FindItem(block, itemId)
    local source = WBF.Notebook.GetBlock(sourceBlockId)
    target = tonumber(target)
    if not item or not source or source.sectionId ~= block.sectionId then
        return nil
    end
    if not target or target ~= math.floor(target) or target < 1 or target > 999999999 then
        return nil
    end

    if source.type == "reference" and source.refType == "item" then
        local itemID = tonumber(source.refID)
        if not itemID or itemID < 1 then
            return nil
        end
        item.progress = {
            kind = "item",
            blockId = source.id,
            itemID = itemID,
            target = target,
        }
    elseif source.type == "resource" and type(source.resourceKey) == "string" and source.resourceKey ~= "" then
        if not WBF.Resources or not WBF.Resources.Get or not WBF.Resources.Get(source.resourceKey) then
            return nil
        end
        item.progress = {
            kind = "resource",
            blockId = source.id,
            resourceKey = source.resourceKey,
            target = target,
        }
    else
        return nil
    end

    TouchBlock(block)
    Save(block)
    return item
end

function WBF.Notebook.ClearChecklistProgress(blockId, itemId)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "checklist" then
        return nil
    end
    local item = FindItem(block, itemId)
    if not item then
        return nil
    end
    item.progress = nil
    TouchBlock(block)
    Save(block)
    return item
end

function WBF.Notebook.ToggleChecklistItem(blockId, itemId)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "checklist" then
        return nil
    end
    local item = FindItem(block, itemId)
    if not item then
        return nil
    end
    item.done = not item.done
    TouchBlock(block)
    Save(block)
    return item
end

function WBF.Notebook.RemoveChecklistItem(blockId, itemId)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "checklist" then
        return nil
    end
    local _, index = FindItem(block, itemId)
    if not index then
        return nil
    end
    table.remove(block.items, index)
    TouchBlock(block)
    return Save(block)
end

local function PositiveID(value)
    local id = tonumber(value)
    if not id or id ~= math.floor(id) or id < 1 then
        return nil
    end
    return id
end

local function CleanURL(value)
    if WBF.NotebookSmart and WBF.NotebookSmart.CleanURL then
        return WBF.NotebookSmart.CleanURL(value)
    end
    value = Trim(value)
    if value == "" then
        return nil
    end
    return Clip(value, 400)
end

function WBF.Notebook.AddAchievement(sectionId, achievementID, sourceURL)
    local section = WBF.Notebook.GetSection(sectionId)
    if not section or #section.blockOrder >= MAX_BLOCKS then
        return nil
    end
    achievementID = PositiveID(achievementID)
    if not achievementID then
        return nil
    end
    if WBF.PlanAchievements and WBF.PlanAchievements.IsTrackable and not WBF.PlanAchievements.IsTrackable(achievementID) then
        return nil
    end
    local now = Now()
    local block = {
        id = Alloc("block"),
        sectionId = section.id,
        type = "achievement",
        achievementID = achievementID,
        createdAt = now,
        updatedAt = now,
    }
    local url = CleanURL(sourceURL)
    if url then
        block.sourceURL = url
    end
    return PlaceBlock(section, block)
end

function WBF.Notebook.AddWaypoint(sectionId, point)
    local section = WBF.Notebook.GetSection(sectionId)
    if not section or #section.blockOrder >= MAX_BLOCKS then
        return nil
    end
    if not WBF.NotebookSmart or not WBF.NotebookSmart.CleanPoint then
        return nil
    end
    point = WBF.NotebookSmart.CleanPoint(point)
    if not point then
        return nil
    end
    local now = Now()
    return PlaceBlock(section, {
        id = Alloc("block"),
        sectionId = section.id,
        type = "waypoint",
        mapID = point.mapID,
        x = point.x,
        y = point.y,
        zone = point.zone,
        label = point.label,
        source = point.source,
        createdAt = now,
        updatedAt = now,
    })
end

function WBF.Notebook.SetWaypoint(blockId, point)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "waypoint" then
        return nil
    end
    if not WBF.NotebookSmart or not WBF.NotebookSmart.CleanPoint then
        return nil
    end
    point = WBF.NotebookSmart.CleanPoint(point)
    if not point then
        return nil
    end
    block.mapID = point.mapID
    block.x = point.x
    block.y = point.y
    block.zone = point.zone
    block.label = point.label
    block.source = point.source or block.source
    TouchBlock(block)
    return Save(block)
end

function WBF.Notebook.AddResource(sectionId, resourceKey, sourceURL)
    local section = WBF.Notebook.GetSection(sectionId)
    if not section or #section.blockOrder >= MAX_BLOCKS then
        return nil
    end
    if type(resourceKey) ~= "string" or resourceKey == "" then
        return nil
    end
    if not WBF.Resources or not WBF.Resources.Get or not WBF.Resources.Get(resourceKey) then
        return nil
    end
    local now = Now()
    return PlaceBlock(section, {
        id = Alloc("block"),
        sectionId = section.id,
        type = "resource",
        resourceKey = resourceKey,
        sourceURL = CleanURL(sourceURL),
        createdAt = now,
        updatedAt = now,
    })
end

function WBF.Notebook.AddReference(sectionId, spec)
    local section = WBF.Notebook.GetSection(sectionId)
    if not section or #section.blockOrder >= MAX_BLOCKS then
        return nil
    end
    if not WBF.NotebookSmart or not WBF.NotebookSmart.CleanReference then
        return nil
    end
    spec = WBF.NotebookSmart.CleanReference(spec)
    if not spec then
        return nil
    end
    local now = Now()
    return PlaceBlock(section, {
        id = Alloc("block"),
        sectionId = section.id,
        type = "reference",
        refType = spec.refType,
        refID = spec.refID,
        label = spec.label,
        url = spec.url,
        createdAt = now,
        updatedAt = now,
    })
end

-- A pet levelling roster stores species IDs, never hand-entered levels.
function WBF.Notebook.AddPetLevelList(sectionId, title)
    local section = WBF.Notebook.GetSection(sectionId)
    if not section or #section.blockOrder >= MAX_BLOCKS then return nil end
    local now = Now()
    return PlaceBlock(section, {
        id = Alloc("block"), sectionId = section.id, type = "pet_level_list",
        title = Clip(title or "Pets to Level", 80), species = {},
        createdAt = now, updatedAt = now,
    })
end

function WBF.Notebook.AddPetToList(blockId, speciesID)
    local block = WBF.Notebook.GetBlock(blockId)
    speciesID = tonumber(speciesID)
    if not block or block.type ~= "pet_level_list" or not speciesID or speciesID < 1 then return false end
    block.species = type(block.species) == "table" and block.species or {}
    for _, existing in ipairs(block.species) do
        if existing == speciesID then return false end
    end
    if #block.species >= 60 then return false end
    table.insert(block.species, speciesID)
    TouchBlock(block)
    return true
end

function WBF.Notebook.RemovePetFromList(blockId, speciesID)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "pet_level_list" then return false end
    for index, id in ipairs(block.species or {}) do
        if id == tonumber(speciesID) then
            table.remove(block.species, index)
            TouchBlock(block)
            return true
        end
    end
    return false
end

function WBF.Notebook.MoveBlock(id, delta)
    local block = WBF.Notebook.GetBlock(id)
    local section = block and WBF.Notebook.GetSection(block.sectionId) or nil
    if not block or not section then
        return nil
    end
    if not MoveId(section.blockOrder, id, delta) then
        return block
    end
    Touch(section)
    Touch(WBF.Notebook.GetPage(section.pageId))
    return Save(block)
end

function WBF.Notebook.DuplicateBlock(id)
    local source = WBF.Notebook.GetBlock(id)
    local section = source and WBF.Notebook.GetSection(source.sectionId) or nil
    if not source or not section or #section.blockOrder >= MAX_BLOCKS then
        return nil
    end
    local now = Now()
    local block = {
        id = Alloc("block"),
        sectionId = section.id,
        type = source.type,
        createdAt = now,
        updatedAt = now,
    }
    if source.type == "text" then
        block.text = source.text
    elseif source.type == "checklist" then
        block.items = {}
        local items = source.items or {}
        for index = 1, #items do
            local item = items[index]
            if type(item) == "table" then
                local copy = {
                    id = AllocItem(),
                    text = item.text or "",
                    done = item.done and true or false,
                    completionMode = item.completionMode,
                }
                if type(item.progress) == "table" and item.progress.kind == "item" then
                    copy.progress = {
                        kind = "item",
                        blockId = item.progress.blockId,
                        itemID = item.progress.itemID,
                        target = item.progress.target,
                    }
                end
                block.items[#block.items + 1] = copy
            end
        end
    elseif source.type == "achievement" then
        block.achievementID = source.achievementID
        block.sourceURL = source.sourceURL
    elseif source.type == "waypoint" then
        block.mapID = source.mapID
        block.x = source.x
        block.y = source.y
        block.zone = source.zone
        block.label = source.label
        block.source = source.source
    elseif source.type == "pet_level_list" then
        block.title = source.title
        block.species = {}
        for _, id in ipairs(source.species or {}) do block.species[#block.species + 1] = id end
    elseif source.type == "resource" then
        block.resourceKey = source.resourceKey
        block.sourceURL = source.sourceURL
    elseif source.type == "reference" then
        block.refType = source.refType
        block.refID = source.refID
        block.label = source.label
        block.url = source.url
    else
        return nil
    end
    return PlaceBlock(section, block, source.id)
end

function WBF.Notebook.DeleteBlock(id)
    local root = WBF.Notebook.Root()
    local block = WBF.Notebook.GetBlock(id)
    if not root or not block then
        return false
    end
    if WBF.NotebookFyi and WBF.NotebookFyi.Forget then
        WBF.NotebookFyi.Forget("block", id)
    end
    local section = WBF.Notebook.GetSection(block.sectionId)
    if section then
        RemoveId(section.blockOrder, id)
        Touch(section)
        Touch(WBF.Notebook.GetPage(section.pageId))
    end
    root.blocks[id] = nil
    Save(nil)
    return true
end

function WBF.Notebook.AddQuickNote(text)
    local root = WBF.Notebook.Root()
    if not root or #root.quickNoteOrder >= MAX_NOTES then
        return nil
    end
    text = Clip(text, MAX_TEXT)
    if text == "" then
        return nil
    end
    local now = Now()
    local note = {
        id = Alloc("note"),
        text = text,
        type = "REFERENCE",
        trigger = nil,
        createdAt = now,
        updatedAt = now,
    }
    root.quickNotes[note.id] = note
    table.insert(root.quickNoteOrder, 1, note.id)
    return Save(note)
end

function WBF.Notebook.SetQuickNote(id, text)
    local note = WBF.Notebook.GetNote(id)
    if not note then
        return nil
    end
    text = Clip(text, MAX_TEXT)
    if text == "" then
        return nil
    end
    if note.text == text then
        return note
    end
    note.text = text
    Touch(note)
    return Save(note)
end

function WBF.Notebook.MoveQuickNote(id, delta)
    local root = WBF.Notebook.Root()
    local note = WBF.Notebook.GetNote(id)
    if not root or not note then
        return nil
    end
    if not MoveId(root.quickNoteOrder, id, delta) then
        return note
    end
    return Save(note)
end

function WBF.Notebook.DeleteQuickNote(id)
    local root = WBF.Notebook.Root()
    if not root or not WBF.Notebook.GetNote(id) then
        return false
    end
    root.quickNotes[id] = nil
    RemoveId(root.quickNoteOrder, id)
    Save(nil)
    return true
end

function WBF.Notebook.FileQuickNote(noteId, sectionId)
    local note = WBF.Notebook.GetNote(noteId)
    local section = WBF.Notebook.GetSection(sectionId)
    if not note or not section then
        return nil
    end
    local block = WBF.Notebook.AddText(sectionId, note.text)
    if not block then
        return nil
    end
    WBF.Notebook.DeleteQuickNote(noteId)
    return block
end

function WBF.Notebook.HasAchievement()
    local root = WBF.Notebook.Root()
    if not root then
        return false
    end
    for _, block in pairs(root.blocks) do
        if type(block) == "table" and block.type == "achievement" then
            return true
        end
    end
    return false
end

function WBF.Notebook.FindAchievement(achievementID)
    achievementID = tonumber(achievementID)
    local root = WBF.Notebook.Root()
    if not achievementID or not root then
        return nil
    end
    for _, block in pairs(root.blocks) do
        if type(block) == "table" and block.type == "achievement" and block.achievementID == achievementID then
            return block
        end
    end
    return nil
end

local function Contains(haystack, needle)
    if needle == "" then
        return true
    end
    if type(haystack) ~= "string" then
        return false
    end
    return haystack:lower():find(needle, 1, true) ~= nil
end

local MAX_HITS = 24

local function AchievementName(achievementID)
    if not (WBF.PlanAchievements and WBF.PlanAchievements.Info) then
        return nil
    end
    local info = WBF.PlanAchievements.Info(achievementID)
    if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
        return info.name
    end
    return nil
end

function WBF.Notebook.HitContext(pageTitle, sectionTitle, kind)
    local parts = {}
    local function add(value)
        if type(value) == "string" and value ~= "" then
            parts[#parts + 1] = value
        end
    end
    add(pageTitle)
    add(sectionTitle)
    local labels = {
        achievement = "Achievement",
        waypoint = "Waypoint",
        resource = "Resource",
        reference = "Reference",
    }
    add(labels[kind])
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, " · ")
end

function WBF.Notebook.ShowsSummary(page, ignoreCollapse)
    if type(page) ~= "table" then
        return false
    end
    local summary = Trim(page.summary or "")
    if summary == "" then
        return false
    end
    local sections = WBF.Notebook.Sections(page.id)
    local section = sections[1]
    if not section then
        return true
    end
    local blocks = WBF.Notebook.Blocks(section.id)
    local block = blocks[1]
    if section.collapsed and not ignoreCollapse then
        return true
    end
    if type(block) == "table" and block.type == "text" and Trim(block.text or ""):gsub("%s+", " ") == summary:gsub("%s+", " ") then
        return false
    end
    return true
end

local function BlockHit(block, needle)
    if type(block) ~= "table" then
        return nil
    end
    if Contains(block.text, needle) then
        return { title = block.text, kind = "text" }
    end
    local items = WBF.Notebook.ChecklistItems(block)
    for index = 1, #items do
        if Contains(items[index].text, needle) then
            return { title = items[index].text, kind = "checklist" }
        end
    end
    local achievementName = block.achievementID and AchievementName(block.achievementID) or nil
    if (block.achievementID and Contains(tostring(block.achievementID), needle)) or Contains(achievementName, needle) then
        return { title = achievementName or ("Achievement " .. tostring(block.achievementID)), kind = "achievement" }
    end
    if Contains(block.label, needle) or Contains(block.zone, needle) then
        local title = block.label
        if type(title) ~= "string" or title == "" then
            title = block.zone or "Waypoint"
        end
        return { title = title, kind = block.type == "reference" and "reference" or "waypoint" }
    end
    if Contains(block.url, needle) or Contains(block.sourceURL, needle) or Contains(block.resourceKey, needle) or (block.refID and Contains(tostring(block.refID), needle)) then
        local title = block.label
        if type(title) ~= "string" or title == "" then
            title = block.resourceKey or block.url or block.sourceURL or "Reference"
        end
        return { title = title, kind = block.type == "resource" and "resource" or "reference" }
    end
    return nil
end

function WBF.Notebook.Search(query)
    local needle = Trim(query):lower()
    local pages = WBF.Notebook.Pages()
    local notes = WBF.Notebook.QuickNotes()
    if needle == "" then
        return { pages = pages, notes = notes, hits = {}, active = false }
    end
    local matchedPages = {}
    local hits = {}
    local function addHit(hit)
        if #hits < MAX_HITS then
            hits[#hits + 1] = hit
        end
    end
    for index = 1, #pages do
        local page = pages[index]
        local matched = false
        if Contains(page.title, needle) or Contains(page.summary, needle) then
            matched = true
            addHit({
                kind = "page",
                pageId = page.id,
                title = page.title or "Page",
                detail = page.summary,
            })
        end
        local sections = WBF.Notebook.Sections(page.id)
        for sectionIndex = 1, #sections do
            local section = sections[sectionIndex]
            if Contains(section.title, needle) then
                matched = true
                addHit({
                    kind = "section",
                    pageId = page.id,
                    sectionId = section.id,
                    title = section.title or "Section",
                    detail = page.title,
                })
            end
            local blocks = WBF.Notebook.Blocks(section.id)
            for blockIndex = 1, #blocks do
                local block = blocks[blockIndex]
                local found = BlockHit(block, needle)
                if found then
                    matched = true
                    addHit({
                        kind = "block",
                        pageId = page.id,
                        sectionId = section.id,
                        blockId = block.id,
                        title = found.title or "Note",
                        detail = WBF.Notebook.HitContext(page.title, section.title, found.kind),
                    })
                end
            end
        end
        if matched then
            matchedPages[#matchedPages + 1] = page
        end
    end
    local matchedNotes = {}
    for index = 1, #notes do
        local note = notes[index]
        if Contains(note.text, needle) then
            matchedNotes[#matchedNotes + 1] = note
            addHit({
                kind = "note",
                noteId = note.id,
                title = note.text or "Note",
                detail = "Quick note",
            })
        end
    end
    return { pages = matchedPages, notes = matchedNotes, hits = hits, active = true }
end

function WBF.Notebook.Summary()
    local lines = {}
    local function countLabel(count)
        if count == 1 then
            return "1 block"
        end
        return tostring(count) .. " blocks"
    end
    local function add(label, value)
        if #lines >= 3 or type(label) ~= "string" or label == "" then
            return
        end
        lines[#lines + 1] = { label = label, value = value or "" }
    end
    local pinned = WBF.Notebook.PinnedPages()
    for index = 1, #pinned do
        local page = pinned[index]
        add(page.title, countLabel(WBF.Notebook.BlockCount(page.id)))
    end
    if #lines < 3 then
        local recent = WBF.Notebook.RecentPages()
        for index = 1, #recent do
            if #lines >= 3 then
                break
            end
            local page = recent[index]
            if not page.pinned then
                add(page.title, countLabel(WBF.Notebook.BlockCount(page.id)))
            end
        end
    end
    if #lines < 3 then
        local notes = WBF.Notebook.QuickNotes()
        for index = 1, #notes do
            add(notes[index].text, "Note")
        end
    end
    return {
        pages = #WBF.Notebook.Pages(),
        notes = #WBF.Notebook.QuickNotes(),
        lines = lines,
    }
end

local function OpenNotebook()
    local frame = WBF.UI and WBF.UI.frame
    if frame and frame.SetView then
        frame:SetView("notebook")
        if frame.IsShown and not frame:IsShown() and frame.Show then
            frame:Show()
        end
    end
end

function WBF.Notebook.HandleSlash(raw)
    if type(raw) ~= "string" then
        return false
    end
    local command, rest = Trim(raw):match("^(%S+)%s*(.*)$")
    if not command then
        return false
    end
    command = command:lower()
    rest = Trim(rest or "")
    if command == "note" then
        if rest == "" then
            Say("Usage: /wbfyi note <text>")
            return true
        end
        if WBF.Notebook.AddQuickNote(rest) then
            Say("Noted.")
        end
        return true
    end
    if command == "notebook" or command == "plans" then
        OpenNotebook()
        return true
    end
    if command == "task" then
        Say("Add a checklist on a page, or save a loose note with /wbfyi note.")
        return true
    end
    if command == "achieve" or command == "achievement" then
        Say("Use + Add on a notebook page to track an achievement.")
        return true
    end
    if command == "debug" and rest == "notebook" then
        WBF.Notebook.Debug()
        return true
    end
    return false
end

function WBF.Notebook.Debug()
    local root = WBF.Notebook.Root()
    local db = WBF.Database.Get()
    if not root then
        Say("Notebook is not ready.")
        return
    end
    local blocks = 0
    for _ in pairs(root.blocks) do
        blocks = blocks + 1
    end
    Say(string.format(
        "%d pages, %d sections, %d blocks, %d quick notes, schema %s",
        #root.pageOrder,
        (function()
            local total = 0
            for _ in pairs(root.sections) do
                total = total + 1
            end
            return total
        end)(),
        blocks,
        #root.quickNoteOrder,
        tostring(db and db.schemaVersion or "?")
    ))
end
