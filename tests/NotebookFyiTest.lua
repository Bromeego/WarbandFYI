-- Opt-in notebook FYI triggers. Run from the repo root:
--   lua tests/NotebookFyiTest.lua

local script = arg and arg[0] or "tests/NotebookFyiTest.lua"
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
loadAddon("Core/NotebookFyi.lua", WBF)
loadAddon("Tracking/PlanAchievements.lua", WBF)

WBF.Time.Now = function()
    return now
end

local MAPS = {
    [100] = { mapID = 100, name = "Stormwind City", mapType = 3 },
    [539] = { mapID = 539, name = "Shadowmoon Valley", mapType = 3 },
    [534] = { mapID = 534, name = "Tanaan Jungle", mapType = 3 },
    [540] = { mapID = 540, name = "Embaari Village", mapType = 5, parentMapID = 539 },
    [541] = { mapID = 541, name = "Shadowmoon Cave", mapType = 4, parentMapID = 539 },
    [999] = { mapID = 999, name = "A Cave", mapType = 5 },
}

local function fresh()
    now = 1700000000
    WarbandFYI_DB = nil
    WBF.Database.ready = false
    WBF.Database.Init()
    WBF.NotebookFyi.UseMaps(MAPS)
    WBF.NotebookFyi.UsePlayerMap(100)
    WBF.NotebookSmart.UseZones({
        { mapID = 100, name = "Stormwind City", mapType = 3 },
        { mapID = 539, name = "Shadowmoon Valley", mapType = 3 },
        { mapID = 534, name = "Tanaan Jungle", mapType = 3 },
        { mapID = 550, name = "Nagrand Valley", mapType = 3 },
    })
end

fresh()
check("FYIs start enabled and empty", WBF.NotebookFyi.Enabled() == true and #WBF.NotebookFyi.List() == 0)

local page = WBF.Notebook.CreatePage("Draenor", "Pets and treasures")
local pets = WBF.Notebook.CreateSection(page.id, "Pet Stuff")
local raids = WBF.Notebook.CreateSection(page.id, "Draenor Raids")
local note = WBF.Notebook.AddText(pets.id, "Bring a leveling team.")
local waypoint = WBF.Notebook.AddWaypoint(pets.id, {
    mapID = 539,
    x = 50.2,
    y = 31.4,
    zone = "Shadowmoon Valley",
    label = "Ashlei",
    source = "manual",
})
local achievement = WBF.Notebook.AddAchievement(pets.id, 9463)
local other = WBF.Notebook.AddWaypoint(raids.id, {
    mapID = 534,
    x = 56.4,
    y = 42.7,
    zone = "Tanaan Jungle",
    label = "Cave",
    source = "manual",
})

check("a note with no location is not guessed", WBF.NotebookFyi.Suggest("block", note.id) == nil)
check("a waypoint suggests its zone", WBF.NotebookFyi.Suggest("block", waypoint.id).mapID == 539)
check("a section with one zone suggests it", WBF.NotebookFyi.Suggest("section", pets.id).name == "Shadowmoon Valley")
check("a page with two zones is not guessed", WBF.NotebookFyi.Suggest("page", page.id) == nil)
check("saving without a zone does nothing", WBF.NotebookFyi.Save({ kind = "block", id = note.id }, nil, nil) == nil and WBF.NotebookFyi.ForTarget("block", note.id) == nil)

local micro = WBF.Notebook.AddWaypoint(pets.id, {
    mapID = 540,
    x = 40,
    y = 20,
    zone = "Embaari Village",
    label = "Village",
    source = "manual",
})
check("a micro waypoint suggests the parent zone", WBF.NotebookFyi.Suggest("block", micro.id).mapID == 539)
check("a micro map cannot be saved as the zone", WBF.NotebookFyi.Save({ kind = "block", id = micro.id }, 540, "Embaari Village") == nil)
WBF.Notebook.DeleteBlock(micro.id)

local ambiguous = WBF.Notebook.AddWaypoint(raids.id, {
    mapID = 999,
    x = 10,
    y = 10,
    zone = "Valley",
    label = "Unclear",
    source = "manual",
})
check("an ambiguous zone name is not guessed", WBF.NotebookFyi.Suggest("block", ambiguous.id) == nil)
WBF.Notebook.DeleteBlock(ambiguous.id)

local trigger = WBF.NotebookFyi.Save({ kind = "block", id = achievement.id }, 539, "Shadowmoon Valley")
local again = WBF.NotebookFyi.Save({ kind = "block", id = achievement.id }, 539, "Shadowmoon Valley")
check("one target keeps one trigger", trigger and again and again.id == trigger.id and #WBF.NotebookFyi.List() == 1)
check("a trigger does not copy the notebook row", trigger.text == nil and trigger.current == nil and trigger.percent == nil and trigger.pages == nil)

local wayTrigger = WBF.NotebookFyi.Save({ kind = "block", id = waypoint.id }, 539, "Shadowmoon Valley")
local pageTrigger = WBF.NotebookFyi.Save({ kind = "page", id = page.id }, 534, "Tanaan Jungle")
check("a page can carry its own trigger", pageTrigger and pageTrigger.targetKind == "page")

check("the first zone after load does not alert", WBF.NotebookFyi.Observe(539, false) == nil)
local entered = WBF.NotebookFyi.Observe(100, false)
check("leaving the anchored zone without a trigger stays quiet", entered == nil)
entered = WBF.NotebookFyi.Observe(539, false)
check("entering the zone shows one group", entered and entered.count == 2 and entered.zoneName == "Shadowmoon Valley" and #entered.entries == 2)
check("the group is one payload", entered.entries[1].triggerId ~= entered.entries[2].triggerId)
local repeated = WBF.NotebookFyi.Observe(539, false)
check("the same zone does not show again", repeated == nil)
local subzone = WBF.NotebookFyi.Observe(540, false)
check("a subzone stays in the same visit", subzone == nil and WBF.NotebookFyi.VisitZone() == 539)
local indoors = WBF.NotebookFyi.Observe(541, false)
check("a cave in the zone does not show again", indoors == nil and WBF.NotebookFyi.VisitZone() == 539)
check("a phase of the same map does not show again", WBF.NotebookFyi.Observe(539, false) == nil)

local ids = { trigger.id, wayTrigger.id }
check("hide this visit keeps the notes", WBF.NotebookFyi.HideVisit(ids) and WBF.Notebook.GetBlock(achievement.id) ~= nil and WBF.Notebook.GetBlock(waypoint.id) ~= nil)
check("hide this visit stays quiet in the zone", WBF.NotebookFyi.Observe(540, false) == nil and WBF.NotebookFyi.Observe(539, false) == nil)
check("leaving the zone clears the visit", WBF.NotebookFyi.Observe(100, false) == nil and WBF.NotebookFyi.VisitZone() == 100)
local returned = WBF.NotebookFyi.Observe(539, false)
check("re-entering the zone shows the FYIs again", returned and returned.count == 2)

check("remove trigger leaves the block", WBF.NotebookFyi.Remove(wayTrigger.id) and WBF.Notebook.GetBlock(waypoint.id) ~= nil and WBF.NotebookFyi.ForTarget("block", waypoint.id) == nil)
WBF.NotebookFyi.Observe(100, false)
local afterRemove = WBF.NotebookFyi.Observe(539, false)
check("a removed trigger is absent from the group", afterRemove and afterRemove.count == 1 and afterRemove.entries[1].triggerId == trigger.id)

WBF.NotebookFyi.Observe(100, false)
WBF.NotebookFyi.UsePlayerMap(539)
local combat = WBF.NotebookFyi.Observe(539, true)
check("combat queues the zone FYI", combat == nil and WBF.NotebookFyi.Seen(trigger.id) == false)
check("a subzone during combat does not show it", WBF.NotebookFyi.Observe(540, true) == nil)
local flushed = WBF.NotebookFyi.Flush()
check("leaving combat shows the queued FYI", flushed and flushed.count == 1 and flushed.zoneMapID == 539)
check("the queue does not show twice", WBF.NotebookFyi.Flush() == nil and WBF.NotebookFyi.Observe(540, false) == nil)

WBF.NotebookFyi.Observe(100, false)
WBF.NotebookFyi.UsePlayerMap(539)
check("a new combat entry queues again", WBF.NotebookFyi.Observe(539, true) == nil)
WBF.NotebookFyi.UsePlayerMap(100)
check("leaving during combat drops the queue", WBF.NotebookFyi.Observe(100, true) == nil and WBF.NotebookFyi.Flush() == nil)
WBF.NotebookFyi.UsePlayerMap(539)
local afterLeave = WBF.NotebookFyi.Observe(539, false)
check("the dropped combat FYI shows on the next real entry", afterLeave and afterLeave.count == 1)

WBF.NotebookFyi.SetEnabled(false)
check("disabling keeps the trigger", WBF.NotebookFyi.ForTarget("block", achievement.id) ~= nil and WBF.NotebookFyi.Enabled() == false)
WBF.NotebookFyi.Observe(100, false)
local silenced = WBF.NotebookFyi.Observe(539, false)
check("a disabled global shows nothing", silenced == nil and WBF.NotebookFyi.Seen(trigger.id) == true)
WBF.NotebookFyi.SetEnabled(true)
check("turning FYIs back on does not replay the current visit", WBF.NotebookFyi.Observe(539, false) == nil)
WBF.NotebookFyi.Observe(100, false)
local restored = WBF.NotebookFyi.Observe(539, false)
check("the next visit shows again after FYIs are enabled", restored and restored.count == 1)

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
WBF.PlanAchievements.InvalidateProgress()
local described = WBF.NotebookFyi.Describe(WBF.NotebookFyi.ForTarget("block", achievement.id))
check("achievement progress stays live", described and described.title == "Draenic Pet Battler" and described.lines[1].text:find("16 / 150", 1, true) and WBF.Notebook.GetBlock(achievement.id).current == nil)

WBF.Notebook.SetPage(page.id, "Draenor Revised", "Still pets")
WBF.Notebook.RenameSection(pets.id, "Pet Plans")
described = WBF.NotebookFyi.Describe(WBF.NotebookFyi.ForTarget("block", achievement.id))
check("a renamed page and section show the new names", described and described.context == "Draenor Revised · Pet Plans")
MAPS[539].name = "Shadowmoon Expanse"
local listed = WBF.NotebookFyi.List()
local listedZone = nil
for index = 1, #listed do
    if listed[index].id == trigger.id then
        listedZone = listed[index].zoneName
    end
end
check("a renamed zone keeps the same map", listedZone == "Shadowmoon Expanse" and WBF.NotebookFyi.ForTarget("block", achievement.id).zoneMapID == 539)
MAPS[539].name = "Shadowmoon Valley"

local sectionTrigger = WBF.NotebookFyi.Save({ kind = "section", id = pets.id }, 539, "Shadowmoon Valley")
local sectionView = WBF.NotebookFyi.Describe(sectionTrigger)
check("a section FYI uses the section title", sectionView and sectionView.title == "Pet Plans" and sectionView.context == "Draenor Revised")
local secondWay = WBF.Notebook.AddWaypoint(pets.id, {
    mapID = 539,
    x = 12,
    y = 34,
    zone = "Shadowmoon Valley",
    label = "Second",
    source = "manual",
})
sectionView = WBF.NotebookFyi.Describe(sectionTrigger)
check("several waypoints do not collapse into one button", sectionView and sectionView.waypoint == nil and secondWay ~= nil)

WBF.Notebook.DeleteBlock(achievement.id)
check("deleting the block removes its trigger and keeps the page", WBF.Notebook.GetBlock(achievement.id) == nil and WBF.NotebookFyi.ForTarget("block", achievement.id) == nil and WBF.Notebook.GetPage(page.id) ~= nil)

local doomed = WBF.Notebook.CreatePage("Karazhan", "Mounts")
local doomedSection = WBF.Notebook.CreateSection(doomed.id, "Attunement")
local doomedTrigger = WBF.NotebookFyi.Save({ kind = "page", id = doomed.id }, 100, "Stormwind City")
check("the doomed page trigger exists", doomedTrigger ~= nil)
WBF.Notebook.DeletePage(doomed.id)
check("deleting the page removes its trigger", WBF.Notebook.GetPage(doomed.id) == nil and WBF.NotebookFyi.ForTarget("page", doomed.id) == nil and WBF.Notebook.GetSection(doomedSection.id) == nil)

WBF.NotebookFyi.Observe(100, false)
WBF.NotebookFyi.Observe(539, false)
check("the section trigger is shown before reload", WBF.NotebookFyi.Seen(sectionTrigger.id) == true)
local keptId = sectionTrigger.id
local keptZone = sectionTrigger.zoneMapID
WBF.Database.Init()
WBF.NotebookFyi.UseMaps(MAPS)
WBF.NotebookFyi.UsePlayerMap(539)
check("reload keeps the trigger", WBF.NotebookFyi.ForTarget("section", pets.id) and WBF.NotebookFyi.ForTarget("section", pets.id).id == keptId and WBF.NotebookFyi.ForTarget("section", pets.id).zoneMapID == keptZone)
check("reload does not pop the current zone", WBF.NotebookFyi.Observe(539, false) == nil and WBF.NotebookFyi.Seen(keptId) == true)
check("reload still has the global switch", WBF.NotebookFyi.Enabled() == true)
WBF.NotebookFyi.UsePlayerMap(100)
WBF.NotebookFyi.Observe(100, false)
local afterReload = WBF.NotebookFyi.Observe(539, false)
check("a later zone entry still works after reload", afterReload and afterReload.count >= 1)

local shows = 0
local opened = false
WBF.UI = {
    Fyi = {
        Show = function()
            shows = shows + 1
        end,
    },
    Sheet = {
        OpenPage = function()
            opened = true
        end,
        OpenSection = function()
            opened = true
        end,
    },
}
WBF.NotebookFyi.UsePlayerMap(100)
WBF.NotebookFyi.Observe(100, false)
WBF.NotebookFyi.UsePlayerMap(539)
WBF.NotebookFyi.OnZone()
check("one zone entry opens one popup", shows == 1)
check("the popup does not open a sheet", opened == false)
WBF.NotebookFyi.OnZone()
check("a repeated zone event does not open another popup", shows == 1)

local seen = {}
WBF.NotebookFyi.Register({
    On = function(_, event)
        seen[event] = true
    end,
})
check("zone entry listens to the map events", seen.ZONE_CHANGED_NEW_AREA and seen.ZONE_CHANGED and seen.ZONE_CHANGED_INDOORS and seen.PLAYER_ENTERING_WORLD)
check("combat release is not a second zone event", seen.PLAYER_REGEN_ENABLED == nil)

local otherStill = WBF.Notebook.GetBlock(other.id)
check("the other zone waypoint is still a notebook block", otherStill and otherStill.zone == "Tanaan Jungle" and pageTrigger.targetKind == "page")

WBF.NotebookSmart.UseZones({
    { mapID = 100, name = "Stormwind City", mapType = 3 },
    { mapID = 539, name = "Shadowmoon Valley", mapType = 3 },
    { mapID = 534, name = "Tanaan Jungle", mapType = 3 },
    { mapID = 550, name = "Nagrand Valley", mapType = 3 },
})
check("an inferred zone shows no result list", #WBF.NotebookFyi.ZoneMatches("Shadowmoon Valley", "Shadowmoon Valley") == 0)
check("an empty zone field shows no results", #WBF.NotebookFyi.ZoneMatches("", nil) == 0)
check("a blank field does not guess from a previous name", #WBF.NotebookFyi.ZoneMatches("   ", "Shadowmoon Valley") == 0)
local typedZone = WBF.NotebookFyi.ZoneMatches("tanaan", nil)
check("typing a zone lists that match", #typedZone == 1 and typedZone[1].mapID == 534 and typedZone[1].name == "Tanaan Jungle")
check("the next-entry hint is explicit", WBF.NotebookFyi.SetupHint() == "Appears the next time you enter this zone.")

local samePage = {
    { pageId = "p1", sectionId = "s1", waypoint = { mapID = 539 } },
    { pageId = "p1", sectionId = "s1" },
    { pageId = "p1", sectionId = "s1", waypoint = { mapID = 534 } },
}
local sameLayout = WBF.NotebookFyi.PopupLayout(samePage)
check("one page shares page actions", sameLayout.shared and sameLayout.shared.pageId == "p1" and sameLayout.shared.sectionId == "s1" and sameLayout.pageCount == 1)
check("waypoint actions stay on waypoint rows", WBF.NotebookFyi.CardActions(samePage[1], sameLayout, 1).waypoint == true and WBF.NotebookFyi.CardActions(samePage[2], sameLayout, 2).waypoint == false and WBF.NotebookFyi.CardActions(samePage[1], sameLayout, 1).page == false)
local mixedPage = {
    { pageId = "p1", sectionId = "s1" },
    { pageId = "p1", sectionId = "s1" },
    { pageId = "p2", sectionId = "s9", waypoint = { mapID = 1 } },
}
local mixedLayout = WBF.NotebookFyi.PopupLayout(mixedPage)
local mixedFirst = WBF.NotebookFyi.CardActions(mixedPage[1], mixedLayout, 1)
local mixedSecond = WBF.NotebookFyi.CardActions(mixedPage[2], mixedLayout, 2)
local mixedThird = WBF.NotebookFyi.CardActions(mixedPage[3], mixedLayout, 3)
check("different pages keep separate navigation", mixedLayout.shared == nil and mixedLayout.pageCount == 2 and mixedFirst.page == true and mixedSecond.page == false and mixedThird.page == true and mixedThird.waypoint == true and mixedFirst.waypoint == false)

fresh()
local quietPage = WBF.Notebook.CreatePage("Quiet", nil)
local quietSection = WBF.Notebook.CreateSection(quietPage.id, "Notes")
local quietNote = WBF.Notebook.AddText(quietSection.id, "Already here")
check("the current zone anchors without a popup", WBF.NotebookFyi.Observe(539, false) == nil)
local quietTrigger = WBF.NotebookFyi.Save({ kind = "block", id = quietNote.id }, 539, "Shadowmoon Valley")
check("saving an FYI inside its zone does not pop", quietTrigger and WBF.NotebookFyi.Observe(539, false) == nil)
check("the saved FYI still waits for the next entry", WBF.NotebookFyi.Observe(100, false) == nil and WBF.NotebookFyi.Observe(539, false) ~= nil)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All FYI checks passed")
