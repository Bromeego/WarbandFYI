-- Notebook: pages, sections, blocks, quick notes, and plans migration.
-- Run from the repo root:
--   lua tests/NotebookTest.lua

local script = arg and arg[0] or "tests/NotebookTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

local WBF = {}
local now = 1700000000
local failures = 0

local function check(name, condition, detail)
    if condition then
        print("PASS  " .. name)
        return
    end
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  " .. detail) or ""))
end

loadAddon("Utils/Format.lua", WBF)
loadAddon("Utils/Time.lua", WBF)
loadAddon("Utils/Debug.lua", WBF)
loadAddon("Core/Characters.lua", WBF)
loadAddon("Core/Database.lua", WBF)
loadAddon("Core/NotebookSmart.lua", WBF)
loadAddon("Core/Notebook.lua", WBF)
loadAddon("Tracking/PlanAchievements.lua", WBF)

WBF.Time.Now = function()
    return now
end

local function ids(list)
    local out = {}
    for index = 1, #list do
        out[index] = list[index].id
    end
    return table.concat(out, ",")
end

local function fresh()
    now = 1700000000
    WarbandFYI_DB = nil
    WBF.Database.ready = false
    WBF.Database.Init()
end

fresh()
check("default database is schema 7", WarbandFYI_DB.schemaVersion == 7)
check("default database has notebook maps", WarbandFYI_DB.notebook and type(WarbandFYI_DB.notebook.pages) == "table" and type(WarbandFYI_DB.notebook.pageOrder) == "table" and type(WarbandFYI_DB.notebook.quickNotes) == "table")
check("default database does not keep plans", WarbandFYI_DB.plans == nil)

WarbandFYI_DB = {
    schemaVersion = 2,
    config = { retentionDays = 120, debug = false },
    nextIds = { session = 4, event = 8 },
    sessions = {},
    characters = {},
    snapshots = {},
    events = {
        { id = 1, at = now, eventType = "level", text = "Keep me" },
    },
    dedupe = {},
}
WBF.Database.Init()
check("schema 2 migrates to 7", WarbandFYI_DB.schemaVersion == 7)
check("migration keeps existing events", WarbandFYI_DB.events[1] and WarbandFYI_DB.events[1].text == "Keep me")
check("migration keeps session ids", WarbandFYI_DB.nextIds.session == 4)
check("migration adds notebook storage", type(WarbandFYI_DB.notebook.pages) == "table" and WarbandFYI_DB.plans == nil)

WarbandFYI_DB = {
    schemaVersion = 7,
    config = { retentionDays = 120, debug = false },
    nextIds = { session = 1, event = 2 },
    sessions = { { id = 12, startedAt = now, endedAt = now } },
    characters = {},
    snapshots = {},
    events = { { id = 40, at = now, eventType = "level", text = "Restored" } },
    dedupe = {},
}
WBF.Database.ready = false
WBF.Database.Init()
check("event ids stay ahead of restored rows", WarbandFYI_DB.nextIds.event == 41)
check("session ids stay ahead of restored rows", WarbandFYI_DB.nextIds.session == 13)

WarbandFYI_DB = {
    schemaVersion = 3,
    config = { retentionDays = 120, debug = false, lastView = "plans" },
    nextIds = { session = 2, event = 3, planEntry = 20, planGroup = 4 },
    sessions = {},
    characters = {
        ["Player-1-A"] = { guid = "Player-1-A", name = "Miranora", discovered = true },
    },
    snapshots = {},
    events = {
        { id = 1, at = now, eventType = "level", text = "Keep me" },
    },
    dedupe = {},
    plans = {
        groups = {
            g1 = {
                id = "g1",
                name = "Draenor",
                description = "Pets, treasures, raids and random grinds.",
                status = "active",
                createdAt = 100,
                updatedAt = 180,
            },
            g2 = {
                id = "g2",
                name = "Old Project",
                description = "Archived plan",
                status = "archived",
                createdAt = 50,
                updatedAt = 70,
            },
        },
        entries = {
            e1 = {
                id = "e1",
                type = "note",
                text = "Bring a leveling team",
                status = "active",
                planID = "g1",
                zone = "Tanaan Jungle",
                createdAt = 110,
                updatedAt = 110,
            },
            e2 = {
                id = "e2",
                type = "task",
                text = "Capture pets",
                status = "completed",
                planID = "g1",
                createdAt = 120,
                completedAt = 125,
            },
            e3 = {
                id = "e3",
                type = "recurring",
                text = "Weekly check",
                status = "active",
                planID = "g1",
                recurring = { preset = "weekly" },
                completedAt = 130,
                createdAt = 130,
            },
            e4 = {
                id = "e4",
                type = "achievement",
                achievementID = 9463,
                status = "active",
                planID = "g1",
                createdAt = 140,
            },
            e5 = {
                id = "e5",
                type = "note",
                text = "Loose hearth",
                status = "active",
                createdAt = 200,
            },
            e6 = {
                id = "e6",
                type = "note",
                text = "Archived loose",
                status = "archived",
                createdAt = 210,
            },
            e7 = {
                id = "e7",
                type = "note",
                text = "Inside old project",
                status = "active",
                planID = "g2",
                createdAt = 60,
            },
            e8 = {
                id = "e8",
                type = "task",
                text = "Loose task",
                status = "active",
                createdAt = 190,
            },
        },
    },
}
WBF.Database.Init()
check("plans view opens notebook", WarbandFYI_DB.config.lastView == "notebook")
check("plans maps are removed", WarbandFYI_DB.plans == nil)
check("journal event survives plans migration", WarbandFYI_DB.events[1].text == "Keep me")

local pages = WBF.Notebook.Pages()
check("migrated pages keep creation order", #pages == 2 and pages[1].title == "Old Project" and pages[2].title == "Draenor")
check("migrated page keeps its description", pages[2].summary == "Pets, treasures, raids and random grinds.")
check("archived plans become ordinary pages", pages[1].pinned == false and pages[1].status == nil)
local draenorSections = WBF.Notebook.Sections(pages[2].id)
check("a plan becomes one section", #draenorSections == 1 and draenorSections[1].title == "Notes")
local migratedBlocks = WBF.Notebook.Blocks(draenorSections[1].id)
check("plan entries keep written order", #migratedBlocks == 5)
check("a plan description becomes an introductory note", migratedBlocks[1].type == "text" and migratedBlocks[1].text == pages[2].summary)
check("note migrates to text", migratedBlocks[2].type == "text" and migratedBlocks[2].text:find("Bring a leveling team", 1, true) and migratedBlocks[2].text:find("Tanaan Jungle", 1, true))
check("completed task migrates to a checked item", migratedBlocks[3].type == "checklist" and migratedBlocks[3].items[1].done == true and migratedBlocks[3].items[1].text == "Capture pets")
check("recurring work becomes an unchecked item", migratedBlocks[4].type == "checklist" and migratedBlocks[4].items[1].done == false and migratedBlocks[4].recurring == nil and migratedBlocks[4].items[1].text == "Weekly check")
check("achievement id is kept without progress", migratedBlocks[5].type == "achievement" and migratedBlocks[5].achievementID == 9463 and migratedBlocks[5].criteria == nil and migratedBlocks[5].current == nil)
local legacy = WarbandFYI_DB.notebookLegacy
check("plans are kept in the migration backup", legacy and legacy.converted == true and legacy.plans and legacy.plans.groups.g1.name == "Draenor" and legacy.plans.entries.e3.recurring.preset == "weekly")
check("migration records which note came from which entry", legacy.links and legacy.links.e4 == migratedBlocks[5].id and legacy.links.g1 == pages[2].id)
local oldSections = WBF.Notebook.Sections(pages[1].id)
local oldBlocks = WBF.Notebook.Blocks(oldSections[1].id)
check("archived plan content is kept", #oldSections == 1 and oldBlocks[1].text == "Archived plan" and oldBlocks[2].text == "Inside old project")
local notes = WBF.Notebook.QuickNotes()
check("loose reminders become quick notes", #notes == 3)
check("newest loose note is first", notes[1].text == "Archived loose" and notes[2].text == "Loose hearth" and notes[3].text == "Loose task")
local beforeReload = #WBF.Notebook.Pages()
WBF.Database.Init()
check("reload does not convert notebook twice", #WBF.Notebook.Pages() == beforeReload and WarbandFYI_DB.plans == nil and WBF.Notebook.Blocks(WBF.Notebook.Sections(WBF.Notebook.Pages()[2].id)[1].id)[5].achievementID == 9463 and WarbandFYI_DB.notebookLegacy.plans.groups.g1.name == "Draenor")

WarbandFYI_DB = {
    schemaVersion = 4,
    config = { retentionDays = 120, debug = false },
    nextIds = { session = 1, event = 1, notebookPage = 2, notebookSection = 1, notebookBlock = 1, notebookItem = 1, notebookNote = 1 },
    sessions = {},
    characters = {},
    snapshots = {},
    events = {},
    dedupe = {},
    notebook = {
        pages = {
            p1 = { id = "p1", title = "Kept", pinned = false, sectionOrder = {}, createdAt = 1, updatedAt = 1 },
        },
        pageOrder = { "p1" },
        sections = {},
        blocks = {},
        quickNotes = {},
        quickNoteOrder = {},
    },
    plans = {
        groups = {
            g9 = { id = "g9", name = "Stray", createdAt = 1, updatedAt = 1 },
        },
        entries = {},
    },
}
WBF.Database.ready = false
WBF.Database.Init()
check("a filled notebook is not rebuilt from leftover plans", WBF.Notebook.Pages()[1].title == "Kept" and #WBF.Notebook.Pages() == 1 and WarbandFYI_DB.plans == nil and WarbandFYI_DB.notebookLegacy.converted == false and WarbandFYI_DB.notebookLegacy.plans.groups.g9.name == "Stray")

fresh()
check("blank page title is rejected", WBF.Notebook.CreatePage("   ") == nil and #WBF.Notebook.Pages() == 0)
local page = WBF.Notebook.CreatePage("Draenor", "Pets, treasures, raids and random grinds.")
check("page stores title and description", page and page.title == "Draenor" and page.summary == "Pets, treasures, raids and random grinds.")
check("page starts unpinned", page.pinned == false)
check("page order is explicit", WarbandFYI_DB.notebook.pageOrder[1] == page.id)
local second = WBF.Notebook.CreatePage("Brewfest", "Event checklist")
check("new pages append", ids(WBF.Notebook.Pages()) == page.id .. "," .. second.id)
WBF.Notebook.SetPinned(page.id, true)
check("pin sticks", WBF.Notebook.GetPage(page.id).pinned == true and WBF.Notebook.PinnedPages()[1].id == page.id)
WBF.Notebook.SetPinned(page.id, false)
check("unpin sticks", WBF.Notebook.GetPage(page.id).pinned == false and #WBF.Notebook.PinnedPages() == 0)
WBF.Notebook.SetPage(page.id, "Draenor", "Pets and treasures")
check("page edit keeps the id", WBF.Notebook.GetPage(page.id).summary == "Pets and treasures" and WBF.Notebook.GetPage(page.id).title == "Draenor")

local pets = WBF.Notebook.CreateSection(page.id, "Pet Stuff")
local tanaan = WBF.Notebook.CreateSection(page.id, "Tanaan Treasure")
local garrison = WBF.Notebook.CreateSection(page.id, "Garrison", pets.id)
check("section inserts after the chosen section", ids(WBF.Notebook.Sections(page.id)) == pets.id .. "," .. garrison.id .. "," .. tanaan.id)
check("blank section title is rejected", WBF.Notebook.CreateSection(page.id, "  ") == nil)
WBF.Notebook.MoveSection(tanaan.id, -1)
check("section move uses the order array", ids(WBF.Notebook.Sections(page.id)) == pets.id .. "," .. tanaan.id .. "," .. garrison.id)
check("first section cannot move up", ids(WBF.Notebook.Sections(page.id)) == pets.id .. "," .. tanaan.id .. "," .. garrison.id)
WBF.Notebook.MoveSection(pets.id, -1)
check("failed move leaves order alone", WarbandFYI_DB.notebook.pages[page.id].sectionOrder[1] == pets.id)
WBF.Notebook.SetCollapsed(garrison.id, true)
check("collapse is stored", WBF.Notebook.GetSection(garrison.id).collapsed == true)
WBF.Notebook.RenameSection(pets.id, "Pets")
check("section rename keeps the id", WBF.Notebook.GetSection(pets.id).title == "Pets")

local text = WBF.Notebook.AddText(pets.id, "Don't deliberately grind the 150.")
check("text block stores the note", text and text.type == "text" and text.text == "Don't deliberately grind the 150.")
check("blank text is rejected", WBF.Notebook.AddText(pets.id, "   ") == nil)
WBF.Notebook.SetText(text.id, "Do Safari and let the wins accumulate.")
check("text edit replaces the note", WBF.Notebook.GetBlock(text.id).text == "Do Safari and let the wins accumulate.")
local list = WBF.Notebook.AddChecklist(pets.id, "Capture missing Draenor Safari pets")
local tiny = WBF.Notebook.AddChecklistItem(list.id, "Work on Tiny Terrors")
local bought = WBF.Notebook.AddChecklistItem(list.id, "Buy Menagerie Level 2 blueprint")
check("checklist keeps item order", list and list.items[1].text == "Capture missing Draenor Safari pets" and tiny.text == "Work on Tiny Terrors" and bought.text == "Buy Menagerie Level 2 blueprint")
check("new checklist items are open", list.items[1].done == false and tiny.done == false)
WBF.Notebook.ToggleChecklistItem(list.id, bought.id)
check("checklist item toggles", WBF.Notebook.GetBlock(list.id).items[3].done == true)
WBF.Notebook.ToggleChecklistItem(list.id, bought.id)
check("checklist item toggles back", WBF.Notebook.GetBlock(list.id).items[3].done == false)
WBF.Notebook.SetChecklistItem(list.id, tiny.id, "Work on Tiny Terrors again")
check("checklist item text edits", WBF.Notebook.GetBlock(list.id).items[2].text == "Work on Tiny Terrors again")
local removedId = list.items[2].id
WBF.Notebook.SetChecklistItem(list.id, removedId, "   ")
check("empty checklist text removes the item", #WBF.Notebook.GetBlock(list.id).items == 2)
local extra = WBF.Notebook.AddText(pets.id, "Second note")
check("blocks append", ids(WBF.Notebook.Blocks(pets.id)) == text.id .. "," .. list.id .. "," .. extra.id)
WBF.Notebook.MoveBlock(extra.id, -1)
check("block move uses the order array", ids(WBF.Notebook.Blocks(pets.id)) == text.id .. "," .. extra.id .. "," .. list.id)
local copy = WBF.Notebook.DuplicateBlock(text.id)
check("duplicate inserts after the source", copy and copy.id ~= text.id and copy.text == text.text and ids(WBF.Notebook.Blocks(pets.id)) == text.id .. "," .. copy.id .. "," .. extra.id .. "," .. list.id)
list.items[1].progress = { kind = "resource", blockId = "b1", resourceKey = "darkmoon_ticket", target = 20 }
local copiedList = WBF.Notebook.DuplicateBlock(list.id)
check("duplicated checklist copies checks and new item ids", copiedList and copiedList.items[1].id ~= list.items[1].id and copiedList.items[1].text == list.items[1].text)
check("duplicated checklist keeps a resource link", copiedList.items[1].progress and copiedList.items[1].progress.kind == "resource" and copiedList.items[1].progress.resourceKey == "darkmoon_ticket" and copiedList.items[1].progress.target == 20)
WBF.Notebook.DeleteBlock(copy.id)
check("block delete removes it from the order", WBF.Notebook.GetBlock(copy.id) == nil and ids(WBF.Notebook.Blocks(pets.id)):find(copy.id, 1, true) == nil)

local note = WBF.Notebook.AddQuickNote("Hearth to Ashran")
check("quick note does not need a page", note and note.text == "Hearth to Ashran" and note.id:sub(1, 1) == "q")
local later = WBF.Notebook.AddQuickNote("Buy Menagerie vendor")
check("newer quick notes are first", ids(WBF.Notebook.QuickNotes()) == later.id .. "," .. note.id)
check("blank quick note is rejected", WBF.Notebook.AddQuickNote("  ") == nil)
WBF.Notebook.SetQuickNote(note.id, "Hearth to Ashran tomorrow")
check("quick note edits", WBF.Notebook.GetNote(note.id).text == "Hearth to Ashran tomorrow")
WBF.Notebook.MoveQuickNote(later.id, 1)
check("quick note move uses its order array", WarbandFYI_DB.notebook.quickNoteOrder[1] == note.id)
local filed = WBF.Notebook.FileQuickNote(note.id, tanaan.id)
check("filing a quick note creates a text block", filed and filed.type == "text" and filed.sectionId == tanaan.id and filed.text == "Hearth to Ashran tomorrow")
check("filed quick note leaves the loose list", WBF.Notebook.GetNote(note.id) == nil)

local found = WBF.Notebook.Search("safari")
check("search matches checklist text", #found.pages == 1 and found.pages[1].id == page.id and found.active == true)
local checklistHit = nil
for index = 1, #(found.hits or {}) do
    if found.hits[index].blockId == list.id then
        checklistHit = found.hits[index]
    end
end
check("search can open the matching block", checklistHit and checklistHit.kind == "block" and checklistHit.pageId == page.id and checklistHit.sectionId == pets.id)
check("empty search returns everything", WBF.Notebook.Search("").active == false and #WBF.Notebook.Search("  ").pages == #WBF.Notebook.Pages() and #WBF.Notebook.Search("").hits == 0)

GetAchievementInfo = function(id)
    if id == 9463 then
        return 9463, "Draenic Pet Battler", 10, false, nil, nil, nil, "Win 150 pet battles in Draenor.", 0, 321, nil, false, false, nil, false
    end
    return nil
end
local named = WBF.Notebook.AddAchievement(pets.id, 9463)
if WBF.PlanAchievements.InvalidateProgress then
    WBF.PlanAchievements.InvalidateProgress()
end
local namedHits = WBF.Notebook.Search("draenic pet")
check("search matches a resolved achievement name", named and namedHits.active == true and namedHits.hits[1] and namedHits.hits[1].blockId == named.id)

local rootBlocks = WBF.Notebook.Root()
rootBlocks.blocks.bad = { id = "bad", sectionId = pets.id, type = "checklist", items = "nope" }
rootBlocks.sections[pets.id].blockOrder[#rootBlocks.sections[pets.id].blockOrder + 1] = "bad"
check("a broken checklist does not stop search", WBF.Notebook.Search("safari").active == true and #WBF.Notebook.ChecklistItems(rootBlocks.blocks.bad) == 0)

local openedStamp = page.updatedAt
now = now + 80
WBF.Notebook.TouchOpened(page.id)
check("opening a page does not rewrite its edit time", WBF.Notebook.GetPage(page.id).openedAt == now and WBF.Notebook.GetPage(page.id).updatedAt == openedStamp)
WBF.Notebook.SetPinned(second.id, true)
check("recent pages leave out pins", WBF.Notebook.RecentPages(8)[1].id == page.id)
WBF.Notebook.SetPinned(second.id, false)

local summary = WBF.Notebook.Summary()
check("summary counts pages and notes", summary.pages == 2 and summary.notes == 1 and summary.lines[1].label == "Draenor")

local pageCount = #WBF.Notebook.Pages()
local blockText = WBF.Notebook.GetBlock(text.id).text
local collapsed = WBF.Notebook.GetSection(garrison.id).collapsed
WBF.Database.Init()
check("reload keeps pages", #WBF.Notebook.Pages() == pageCount)
check("reload keeps block text", WBF.Notebook.GetBlock(text.id).text == blockText)
check("reload keeps collapse", WBF.Notebook.GetSection(garrison.id).collapsed == collapsed)
check("reload keeps checklist state", WBF.Notebook.GetBlock(list.id).items[1].text == "Capture missing Draenor Safari pets")
check("reload keeps section order", ids(WBF.Notebook.Sections(page.id)) == pets.id .. "," .. tanaan.id .. "," .. garrison.id)

WBF.Notebook.DeleteSection(garrison.id)
check("deleting a section removes it", WBF.Notebook.GetSection(garrison.id) == nil and ids(WBF.Notebook.Sections(page.id)) == pets.id .. "," .. tanaan.id)
WBF.Notebook.DeletePage(second.id)
check("deleting a page removes it", WBF.Notebook.GetPage(second.id) == nil and #WBF.Notebook.Pages() == 1)
WBF.Notebook.DeletePage(page.id)
check("deleting a page removes its sections and blocks", WBF.Notebook.GetSection(pets.id) == nil and WBF.Notebook.GetBlock(text.id) == nil and #WBF.Notebook.Pages() == 0)

local beforeSlash = #WBF.Notebook.QuickNotes()
WBF.Notebook.HandleSlash("note    ")
check("empty slash note adds nothing", #WBF.Notebook.QuickNotes() == beforeSlash)
WBF.Notebook.HandleSlash("note Do Draenor pet battles")
local slashed = WBF.Notebook.QuickNotes()[1]
check("slash note keeps the player's casing", slashed and slashed.text == "Do Draenor pet battles")
local beforeTask = #WBF.Notebook.QuickNotes()
check("slash task does not create a task", WBF.Notebook.HandleSlash("task Capture pets") == true and #WBF.Notebook.QuickNotes() == beforeTask)
check("slash achieve does not create a block", WBF.Notebook.HandleSlash("achieve 9463") == true and WBF.Notebook.HasAchievement() == false)
check("unrelated slash commands stay untouched", WBF.Notebook.HandleSlash("status") == false)
check("plans command is handled", WBF.Notebook.HandleSlash("plans") == true)
check("notebook command is handled", WBF.Notebook.HandleSlash("notebook") == true)

GetAchievementInfo = function(id)
    if id == 9463 then
        return 9463, "Draenic Pet Battler", 10, false, nil, nil, nil, "Win 150 pet battles in Draenor.", 0, 321, nil, false, false, nil, false
    end
    if id == 88 then
        return 88, "Health", 0, false, nil, nil, nil, "A statistic", 0, 5, nil, false, false, nil, true
    end
    return nil
end
GetAchievementNumCriteria = function(id)
    if id == 9463 then
        return 1
    end
    return 0
end
GetAchievementCriteriaInfo = function(id)
    if id == 9463 then
        return "Win pet battles in Draenor", 0, false, 16, 150
    end
    return nil
end
check("statistics stay untracked", WBF.PlanAchievements.IsTrackable(88) == false)
local progress = WBF.PlanAchievements.Progress(9463)
check("achievement progress is still read live", progress and progress.current == 16 and progress.required == 150 and progress.percent == 11)
local remembered = WBF.Notebook.CreatePage("Safari", nil)
local section = WBF.Notebook.CreateSection(remembered.id, "Notes")
local stored = WBF.Notebook.AddText(section.id, "Achievement 9463")
WBF.PlanAchievements.Progress(9463)
check("live progress is not written onto notebook rows", stored.current == nil and stored.percent == nil and stored.criteria == nil)

check("delete copy names a note", WBF.Notebook.DeleteLabel("text", "Bring bait") == "Delete this note? Bring bait")
check("delete copy names an achievement", WBF.Notebook.DeleteLabel("achievement", "Draenic Pet Battler") == "Delete this achievement? Draenic Pet Battler")
check("delete copy names a waypoint", WBF.Notebook.DeleteLabel("waypoint", "Ashlei") == "Delete this waypoint? Ashlei")
check("delete copy names a resource", WBF.Notebook.DeleteLabel("resource", "Timewarped Badge") == "Delete this resource? Timewarped Badge")
check("delete copy names a reference", WBF.Notebook.DeleteLabel("reference", "Wowhead") == "Delete this reference? Wowhead")
check("delete copy names a section", WBF.Notebook.DeleteLabel("section", "Pet Stuff") == "Delete this section? Pet Stuff")
check("delete copy names a page", WBF.Notebook.DeleteLabel("page", "Draenor") == "Delete this page? Draenor")

local copied = WBF.Notebook.CreatePage("Copied", "Same words")
local copiedSection = WBF.Notebook.CreateSection(copied.id, "Notes")
local copiedIntro = WBF.Notebook.AddText(copiedSection.id, "Same words")
local copiedLater = WBF.Notebook.AddText(copiedSection.id, "A different note")
check("a matching first note is not shown beside the summary", WBF.Notebook.ShowsSummary(copied) == false and copiedIntro.text == "Same words")
check("a different following note stays", copiedLater.text == "A different note" and WBF.Notebook.GetBlock(copiedLater.id) ~= nil)
WBF.Notebook.SetCollapsed(copiedSection.id, true)
check("a collapsed section still shows the summary", WBF.Notebook.ShowsSummary(WBF.Notebook.GetPage(copied.id)) == true)
WBF.Notebook.SetCollapsed(copiedSection.id, false)
local unique = WBF.Notebook.CreatePage("Unique", "Header")
local uniqueSection = WBF.Notebook.CreateSection(unique.id, "Notes")
WBF.Notebook.AddText(uniqueSection.id, "Body")
check("a different first note keeps the summary", WBF.Notebook.ShowsSummary(unique) == true)

local capturePage = WBF.Notebook.CreatePage("Draenor", "Pets and treasures")
local captureSection = WBF.Notebook.CreateSection(capturePage.id, "Pet Stuff")
local captureList = WBF.Notebook.AddChecklist(captureSection.id, "Capture missing Draenor Safari pets")
local beforeItems = #WBF.Notebook.GetBlock(captureList.id).items
local captured, captureState = WBF.Notebook.ChecklistCapture(captureList.id, "Fourth row")
check("checklist capture adds the typed row", captured and captureState == "next" and captured.text == "Fourth row")
local _, blankState = WBF.Notebook.ChecklistCapture(captureList.id, "   ")
check("a blank checklist row is rejected", blankState == "blank" and #WBF.Notebook.GetBlock(captureList.id).items == beforeItems + 1)
local again = WBF.Notebook.ChecklistCapture(captureList.id, "Fifth row")
check("the next checklist row appends", again and again.text == "Fifth row" and #WBF.Notebook.GetBlock(captureList.id).items == beforeItems + 2)
WBF.Database.Init()
check("checklist rows survive reload", WBF.Notebook.GetBlock(captureList.id).items[beforeItems + 1].text == "Fourth row" and WBF.Notebook.GetBlock(captureList.id).items[beforeItems + 2].text == "Fifth row")

local safari = WBF.Notebook.Search("safari")
local safariHit = nil
for index = 1, #(safari.hits or {}) do
    if safari.hits[index].blockId == captureList.id then
        safariHit = safari.hits[index]
    end
end
check("search names the page and section", safariHit and safariHit.detail == "Draenor · Pet Stuff" and safariHit.pageId == capturePage.id and safariHit.sectionId == captureSection.id)
local ashlei = WBF.Notebook.AddWaypoint(captureSection.id, { mapID = 534, x = 10, y = 20, zone = "Tanaan Jungle", label = "Ashlei", source = "manual" })
local ashleiHits = WBF.Notebook.Search("ashlei")
local ashleiHit = nil
for index = 1, #(ashleiHits.hits or {}) do
    if ashleiHits.hits[index].blockId == ashlei.id then
        ashleiHit = ashleiHits.hits[index]
    end
end
check("search names a waypoint location", ashleiHit and ashleiHit.detail == "Draenor · Pet Stuff · Waypoint" and ashleiHit.pageId == capturePage.id)

local beforeBlocks = #WBF.Notebook.Blocks(captureSection.id)
local addedAchievement = WBF.Notebook.AddAchievement(captureSection.id, 9463)
check("one achievement add inserts one block", addedAchievement and #WBF.Notebook.Blocks(captureSection.id) == beforeBlocks + 1)
local previousGet = WBF.Resources and WBF.Resources.Get or nil
WBF.Resources = WBF.Resources or {}
WBF.Resources.Get = function(key)
    if key == "timewarped" then
        return { key = key, name = "Timewarped Badge" }
    end
    if previousGet then
        return previousGet(key)
    end
    return nil
end
local beforeResource = #WBF.Notebook.Blocks(captureSection.id)
local addedResource = WBF.Notebook.AddResource(captureSection.id, "timewarped")
check("one resource add inserts one block", addedResource and addedResource.type == "resource" and #WBF.Notebook.Blocks(captureSection.id) == beforeResource + 1)
if previousGet then
    WBF.Resources.Get = previousGet
end

local previousInfo = GetAchievementInfo
GetNumFilteredAchievements = function()
    return 20
end
GetFilteredAchievementID = function(index)
    return 2000 + index
end
SetAchievementSearchString = function()
end
GetAchievementInfo = function(id)
    if id >= 2001 and id <= 2020 then
        return id, "Pet Match " .. id, 10, false, nil, nil, nil, "A pet achievement.", 0, 10, nil, false, false, nil, false
    end
    if previousInfo then
        return previousInfo(id)
    end
    return nil
end
local many = WBF.PlanAchievements.Search("pet")
check("capped achievement search reports more matches", #many == 12 and many.capped == true)
GetNumFilteredAchievements = function()
    return 3
end
local few = WBF.PlanAchievements.Search("pet")
check("a short achievement search is not marked capped", #few == 3 and few.capped ~= true)
GetAchievementInfo = previousInfo
GetNumFilteredAchievements = nil
GetFilteredAchievementID = nil
SetAchievementSearchString = nil

local waypointCount = #WBF.Notebook.Blocks(captureSection.id)
local edited = WBF.Notebook.SetWaypoint(ashlei.id, { mapID = 534, x = 12.5, y = 40, zone = "Tanaan Jungle", label = "Ashlei camp", source = "manual" })
check("editing a waypoint keeps the same block", edited and edited.id == ashlei.id and edited.label == "Ashlei camp" and edited.x == 12.5 and edited.y == 40)
check("editing a waypoint does not add another", #WBF.Notebook.Blocks(captureSection.id) == waypointCount)

GetAchievementInfo = nil
GetAchievementNumCriteria = nil
GetAchievementCriteriaInfo = nil

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All notebook checks passed")
