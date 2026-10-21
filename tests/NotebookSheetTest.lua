-- Reference sheet: one view over notebook pages and sections.
-- Run from the repo root:
--   lua tests/NotebookSheetTest.lua

local script = arg and arg[0] or "tests/NotebookSheetTest.lua"
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
loadAddon("Core/NotebookSheet.lua", WBF)
loadAddon("Tracking/PlanAchievements.lua", WBF)

WBF.Time.Now = function()
    return now
end

local function fresh()
    now = 1700000000
    WarbandFYI_DB = nil
    WBF.Database.ready = false
    WBF.Database.Init()
end

fresh()
check("a reload starts with the sheet closed", WBF.NotebookSheet.IsOpen() == false)

local page = WBF.Notebook.CreatePage("Draenor", "Pets, treasures, raids and random grinds.")
local pets = WBF.Notebook.CreateSection(page.id, "Pet Stuff")
local raids = WBF.Notebook.CreateSection(page.id, "Draenor Raids")
local note = WBF.Notebook.AddText(pets.id, "Focus on the easier rare spawns first.")
local list = WBF.Notebook.AddChecklist(pets.id, "Capture missing Draenor Safari pets")
local done = WBF.Notebook.AddChecklistItem(list.id, "Work on Tiny Terrors")
WBF.Notebook.ToggleChecklistItem(list.id, list.items[1].id)
local achievement = WBF.Notebook.AddAchievement(pets.id, 9463)
local waypoint = WBF.Notebook.AddWaypoint(pets.id, {
    mapID = 534,
    x = 56.4,
    y = 42.7,
    zone = "Tanaan Jungle",
    label = "Cave",
    source = "manual",
})

check("missing page does not open a sheet", WBF.NotebookSheet.Open({ kind = "page", pageId = "missing" }) == nil and WBF.NotebookSheet.IsOpen() == false)
local opened = WBF.NotebookSheet.Open({ kind = "page", pageId = page.id })
check("a page opens as the sheet", opened and opened.kind == "page" and WBF.NotebookSheet.IsOpen())
local pageView = WBF.NotebookSheet.View()
check("a page sheet lists every section", pageView and pageView.kind == "page" and #pageView.sections == 2 and pageView.sections[1].id == pets.id and pageView.sections[2].id == raids.id)
check("a second open replaces the first", WBF.NotebookSheet.Open({ kind = "section", sectionId = pets.id }) and WBF.NotebookSheet.View().kind == "section" and #WBF.NotebookSheet.View().sections == 1)
check("a bad open leaves the current sheet", WBF.NotebookSheet.Open({ kind = "page", pageId = "missing" }) == nil and WBF.NotebookSheet.View().kind == "section")

check("a narrow sheet uses one column", WBF.NotebookSheet.Columns(320) == 1 and WBF.NotebookSheet.Columns(459) == 1)
check("a wide sheet uses two columns", WBF.NotebookSheet.Columns(460) == 2)
check("checklists stay full width", WBF.NotebookSheet.FullWidth(list, 2) == true and WBF.NotebookSheet.FullWidth(note, 2) == false and WBF.NotebookSheet.FullWidth(note, 1) == true)

local tiny = WBF.NotebookSheet.Update({ width = 100, height = 40, scale = 1.12, opacity = 0.8, locked = true, hideCompleted = true, point = "TOPLEFT", relPoint = "TOPLEFT", x = 40, y = -25 })
check("resize clamps to the sheet bounds", tiny and tiny.width == 300 and tiny.height == 240)
local fitted = WBF.NotebookSheet.Update({ width = 2000, height = 2000 })
check("resize clamps the upper bound", fitted and fitted.width == 900 and fitted.height == 800)
local chrome = WBF.NotebookSheet.Update({ width = 480, height = 360, scale = 1.1, opacity = 0.9, locked = true, hideCompleted = true, point = "CENTER", relPoint = "CENTER", x = 12, y = -8 })
check("scale snaps to a step", chrome and chrome.scale == 1.1)
check("opacity snaps to a step", chrome.opacity == 0.9)
check("lock is stored", chrome.locked == true)
local stepped = WBF.NotebookSheet.Cycle("scale", 1)
check("scale cycles upward", stepped and stepped.scale == 1.25)
stepped = WBF.NotebookSheet.Cycle("scale", 1)
check("scale wraps", stepped and stepped.scale == 0.8)
WBF.NotebookSheet.Update({ scale = 1, opacity = 1, locked = false })
local unlocked = WBF.NotebookSheet.Toggle("locked")
check("lock toggles", unlocked and unlocked.locked == true)
WBF.NotebookSheet.Toggle("locked")

local visible = WBF.NotebookSheet.VisibleItems(WBF.Notebook.GetBlock(list.id))
check("hide completed drops checked rows from the view", #visible == 1 and visible[1].id == done.id)
check("hide completed keeps the saved row", #WBF.Notebook.GetBlock(list.id).items == 2)
WBF.Notebook.ToggleChecklistItem(list.id, done.id)
visible = WBF.NotebookSheet.VisibleItems(WBF.Notebook.GetBlock(list.id))
check("a check in the sheet data updates the notebook", WBF.Notebook.GetBlock(list.id).items[2].done == true and #visible == 0)
WBF.NotebookSheet.Toggle("hideCompleted")
check("showing completed rows restores both", #WBF.NotebookSheet.VisibleItems(WBF.Notebook.GetBlock(list.id)) == 2)

GetAchievementInfo = function(id)
    if id == 9463 then
        return 9463, "Draenic Pet Battler", 10, false, nil, nil, nil, "Win 150 pet battles in Draenor.", 0, 321, nil, false, false, nil, false
    end
    return nil
end
GetAchievementNumCriteria = function()
    return 1
end
GetAchievementCriteriaInfo = function()
    return "Win pet battles in Draenor", 0, false, 16, 150
end
local progress = WBF.PlanAchievements.Progress(9463)
local viewed = WBF.Notebook.GetBlock(achievement.id)
check("sheet achievement progress stays live", progress and progress.current == 16 and progress.percent == 11 and viewed.current == nil and viewed.percent == nil and viewed.criteria == nil)
local counterDetail = WBF.NotebookSheet.AchievementDetail(progress, false)
local sameDetail = WBF.PlanAchievements.CriteriaDetail(progress, false)
check("sheet counter achievement stays aggregate", counterDetail and #counterDetail.lines == 0 and counterDetail.summary == sameDetail.summary and counterDetail.summary:find("16 / 150", 1, true))
local namedProgress = {
    kind = "criteria",
    current = 2,
    required = 6,
    percent = 33,
    completed = false,
    criteria = {
        { name = "Ashlei", completed = false, current = 0, required = 1 },
        { name = "Vesharr", completed = false, current = 0, required = 1 },
        { name = "Tarr the Terrible", completed = false, current = 0, required = 1 },
        { name = "Gargra", completed = false, current = 0, required = 1 },
        { name = "Progress", completed = false, current = 0, required = 1 },
    },
}
local sheetNamed = WBF.NotebookSheet.AchievementDetail(namedProgress, false)
local planNamed = WBF.PlanAchievements.CriteriaDetail(namedProgress, false)
check("sheet renders the same missing criteria", sheetNamed and planNamed and sheetNamed.heading == planNamed.heading and sheetNamed.more == planNamed.more and sheetNamed.toggle == planNamed.toggle and #sheetNamed.lines == #planNamed.lines and sheetNamed.lines[1].text == "Ashlei" and sheetNamed.lines[3].text == "Tarr the Terrible" and sheetNamed.more == 1 and sheetNamed.lines[1].text ~= "Gargra")
check("sheet criteria detail is not written onto the block", viewed.criteria == nil and viewed.current == nil)

local calls = {}
C_Map = {
    CanSetUserWaypointOnMap = function()
        return true
    end,
    SetUserWaypoint = function(pin)
        calls.pin = pin
        return true
    end,
}
UiMapPoint = {
    CreateFromCoordinates = function(mapID, x, y)
        return { mapID = mapID, x = x, y = y }
    end,
}
C_SuperTrack = {
    SetSuperTrackedUserWaypoint = function(enabled)
        calls.super = enabled
    end,
}
check("a sheet waypoint click sets the user waypoint", WBF.NotebookSheet.Use(waypoint) == true and calls.pin and calls.pin.mapID == 534 and math.abs(calls.pin.x - 0.564) < 0.001)
check("a waypoint click does not copy the pin onto the block", waypoint.pin == nil and waypoint.x == 56.4)
check("other blocks are not waypoint clicks", WBF.NotebookSheet.Use(note) == false)

WBF.Notebook.DeleteBlock(note.id)
local afterBlock = WBF.NotebookSheet.View()
local stillThere = false
local blocks = WBF.Notebook.Blocks(pets.id)
for index = 1, #blocks do
    if blocks[index].id == note.id then
        stillThere = true
    end
end
check("deleting a block leaves the sheet on the section", afterBlock and afterBlock.kind == "section" and stillThere == false and WBF.NotebookSheet.IsOpen())

WBF.Notebook.DeleteSection(pets.id)
check("deleting the open section closes the sheet", WBF.NotebookSheet.View() == nil and WBF.NotebookSheet.IsOpen() == false)

local again = WBF.Notebook.CreatePage("Karazhan", "Mount runs")
local hall = WBF.Notebook.CreateSection(again.id, "Attunement")
WBF.NotebookSheet.Open({ kind = "page", pageId = again.id })
WBF.Notebook.DeleteSection(hall.id)
local pageAfter = WBF.NotebookSheet.View()
check("deleting one section keeps a page sheet open", pageAfter and pageAfter.kind == "page" and #pageAfter.sections == 0 and WBF.NotebookSheet.IsOpen())
WBF.Notebook.DeletePage(again.id)
check("deleting the open page closes the sheet", WBF.NotebookSheet.View() == nil and WBF.NotebookSheet.IsOpen() == false)

WBF.NotebookSheet.Update({
    width = 510,
    height = 400,
    scale = 0.9,
    opacity = 0.75,
    locked = true,
    hideCompleted = true,
    point = "BOTTOMRIGHT",
    relPoint = "BOTTOMRIGHT",
    x = -20,
    y = 30,
})
WBF.NotebookSheet.Open({ kind = "page", pageId = page.id })
check("the sheet can be open before a reload", WBF.NotebookSheet.IsOpen())
WBF.Database.Init()
local kept = WBF.NotebookSheet.Settings()
check("reload keeps the sheet size", kept and kept.width == 510 and kept.height == 400)
check("reload keeps scale, opacity, and lock", kept.scale == 0.9 and kept.opacity == 0.75 and kept.locked == true and kept.hideCompleted == true)
check("reload keeps the sheet position", kept.point == "BOTTOMRIGHT" and kept.x == -20 and kept.y == 30)
check("reload leaves the sheet closed", WBF.NotebookSheet.IsOpen() == false and kept.open == nil and kept.pageId == nil and kept.pages == nil and kept.blocks == nil)
check("scale label names the control", WBF.NotebookSheet.ChromeLabel("scale", 1) == "Scale 100%")
check("opacity label names the control", WBF.NotebookSheet.ChromeLabel("opacity", 1) == "Opacity 100%")
check("opacity label uses the saved step", WBF.NotebookSheet.ChromeLabel("opacity", 0.75) == "Opacity 75%")

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All sheet checks passed")
