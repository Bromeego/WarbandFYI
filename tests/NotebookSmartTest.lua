-- Smart notebook blocks: achievements, waypoints, links, and resources.
-- Run from the repo root:
--   lua tests/NotebookSmartTest.lua

local script = arg and arg[0] or "tests/NotebookSmartTest.lua"
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
loadAddon("Tracking/ResourceShift.lua", WBF)
loadAddon("Tracking/Resources.lua", WBF)

WBF.Time.Now = function()
    return now
end

local function fresh()
    now = 1700000000
    WarbandFYI_DB = nil
    WBF.Database.ready = false
    WBF.Database.Init()
    WBF.PlanAchievements.InvalidateProgress()
end

fresh()
local page = WBF.Notebook.CreatePage("Draenor", "Pets and treasures")
local section = WBF.Notebook.CreateSection(page.id, "Pet Stuff")

GetAchievementInfo = function(id)
    if id == 9463 then
        return 9463, "Draenic Pet Battler", 10, false, nil, nil, nil, "Win 150 pet battles in Draenor.", 0, 321, nil, false, false, nil, false
    end
    if id == 1000 then
        return 1000, "Jungle Treasure Master", 10, false, nil, nil, nil, "Discover the treasures in Tanaan Jungle.", 0, 222, nil, false, false, nil, false
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
    if id == 1000 then
        return 4
    end
    return 0
end
GetAchievementCriteriaInfo = function(id, index)
    if id == 9463 then
        return "Win pet battles in Draenor", 0, false, 16, 150
    end
    if id == 1000 then
        local done = index <= 2
        return "Treasure " .. index, 0, done, done and 1 or 0, 1
    end
    return nil
end

local progress = WBF.PlanAchievements.Progress(9463)
check("valid achievement reads live progress", progress and progress.name == "Draenic Pet Battler" and progress.current == 16 and progress.required == 150 and progress.percent == 11)
check("invalid statistic is rejected", WBF.PlanAchievements.IsTrackable(88) == false)
check("unknown achievement is rejected", WBF.PlanAchievements.IsTrackable(999) == false)
local criteria = WBF.PlanAchievements.Progress(1000)
check("multi-criteria progress counts completed rows", criteria and criteria.kind == "criteria" and criteria.current == 2 and criteria.required == 4 and criteria.percent == 50)

local achievement = WBF.Notebook.AddAchievement(section.id, 9463, "https://www.wowhead.com/achievement=9463")
check("achievement block stores the id", achievement and achievement.achievementID == 9463 and achievement.type == "achievement")
check("achievement block keeps the source url", achievement.sourceURL == "https://www.wowhead.com/achievement=9463")
check("achievement progress is not stored", achievement.current == nil and achievement.required == nil and achievement.percent == nil and achievement.criteria == nil and achievement.completed == nil)
check("invalid achievement is not stored", WBF.Notebook.AddAchievement(section.id, 88) == nil and WBF.Notebook.AddAchievement(section.id, 999) == nil)
WBF.PlanAchievements.Progress(9463)
check("reading progress still leaves the block alone", WBF.Notebook.GetBlock(achievement.id).current == nil and WBF.Notebook.GetBlock(achievement.id).percent == nil)

WBF.NotebookSmart.UseZones({
    { mapID = 534, name = "Tanaan Jungle" },
    { mapID = 539, name = "Shadowmoon Valley" },
    { mapID = 554, name = "Valley of the Four Winds" },
})

local function parsed(text)
    return WBF.NotebookSmart.ParseWaypoint(text)
end

local jungle = parsed("/way Tanaan Jungle 85 58")
check("slash way with a zone resolves one map", jungle and jungle.mapID == 534 and jungle.zone == "Tanaan Jungle" and jungle.x == 85 and jungle.y == 58)
local decimals = parsed("85.0 58.0")
check("bare coordinates parse without a zone", decimals and decimals.mapID == nil and decimals.x == 85 and decimals.y == 58)
local comma = parsed("Tanaan Jungle 85,58")
check("comma coordinates parse", comma and comma.mapID == 534 and comma.x == 85 and comma.y == 58)
local spaced = parsed("/way Tanaan Jungle 85, 58")
check("spaced comma coordinates parse", spaced and spaced.mapID == 534 and spaced.y == 58)
local partial = parsed("tanaan 56.4 42.7")
check("a unique partial zone name resolves", partial and partial.mapID == 534 and partial.zone == "Tanaan Jungle" and partial.x == 56.4)
local ambiguous = parsed("Valley 10 20")
check("an ambiguous zone is not guessed", ambiguous and ambiguous.mapID == nil and ambiguous.zone == "Valley" and ambiguous.x == 10)
check("coordinates past 100 are rejected", parsed("101, 5") == nil)
check("a single number is rejected", parsed("85") == nil)
check("three numbers are rejected", parsed("10, 20, 30") == nil)
check("trailing junk is rejected", parsed("/way Tanaan Jungle 85 58 please") == nil)

local calls = {}
C_Map = {
    GetBestMapForUnit = function(unit)
        calls[#calls + 1] = "map:" .. tostring(unit)
        return 539
    end,
    GetPlayerMapPosition = function(mapID, unit)
        calls[#calls + 1] = "pos:" .. tostring(unit)
        return { x = 0.502, y = 0.314 }
    end,
    GetMapInfo = function(mapID)
        if mapID == 539 then
            return { mapID = 539, name = "Shadowmoon Valley" }
        end
        return nil
    end,
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
UnitExists = function(unit)
    return unit == "player"
end
UnitName = function()
    return nil
end

local here = WBF.NotebookSmart.PlayerLocation()
check("current position uses the player map", here and here.mapID == 539 and here.zone == "Shadowmoon Valley" and here.x == 50.2 and here.y == 31.4 and here.source == "player")
check("current position asks for the player", calls[1] == "map:player" and calls[2] == "pos:player")

C_Map.GetBestMapForUnit = function()
    return nil
end
check("a missing map is not guessed", WBF.NotebookSmart.PlayerLocation() == nil)
C_Map.GetBestMapForUnit = function()
    return 539
end
C_Map.GetPlayerMapPosition = function()
    return { x = 0, y = 0 }
end
check("a zero position is not guessed", WBF.NotebookSmart.PlayerLocation() == nil)
C_Map.GetPlayerMapPosition = function(mapID, unit)
    calls[#calls + 1] = "pos:" .. tostring(unit)
    return { x = 0.502, y = 0.314 }
end
C_Map.GetMapInfo = function()
    return { name = "" }
end
check("a nameless map is not guessed", WBF.NotebookSmart.PlayerLocation() == nil)
C_Map.GetMapInfo = function(mapID)
    if mapID == 539 then
        return { mapID = 539, name = "Shadowmoon Valley" }
    end
    return nil
end

local missingTarget = WBF.NotebookSmart.TargetLocation()
check("target waypoint requires a target", missingTarget == nil)
UnitExists = function(unit)
    return unit == "player" or unit == "target"
end
UnitName = function(unit)
    if unit == "target" then
        return "Ashlei"
    end
    return "Miranora"
end
local before = #calls
local target = WBF.NotebookSmart.TargetLocation()
check("target waypoint stores the target name and the player position", target and target.label == "Ashlei" and target.mapID == 539 and target.x == 50.2 and target.y == 31.4 and target.source == "target")
local askedTarget = false
for index = before + 1, #calls do
    if calls[index] == "pos:target" then
        askedTarget = true
    end
end
check("target waypoint does not ask for target coordinates", askedTarget == false)

local savedHere = WBF.Notebook.AddWaypoint(section.id, here)
check("current waypoint stores map and coordinates", savedHere and savedHere.mapID == 539 and savedHere.x == 50.2 and savedHere.y == 31.4 and savedHere.zone == "Shadowmoon Valley")
local savedTarget = WBF.Notebook.AddWaypoint(section.id, target)
check("target waypoint stores the label", savedTarget and savedTarget.label == "Ashlei" and savedTarget.x == 50.2)
check("waypoint rejects a missing map", WBF.Notebook.AddWaypoint(section.id, { x = 10, y = 20, zone = "Tanaan Jungle" }) == nil)
check("waypoint rejects coordinates past 100", WBF.Notebook.AddWaypoint(section.id, { mapID = 534, x = 140, y = 10, zone = "Tanaan Jungle" }) == nil)
local manual = WBF.Notebook.AddWaypoint(section.id, { mapID = 534, x = 56.4, y = 42.7, zone = "Tanaan Jungle", label = "Cave", source = "manual" })
check("manual waypoint stores the chosen zone", manual and manual.mapID == 534 and manual.label == "Cave" and manual.source == "manual")

local tracked = WBF.NotebookSmart.Track(savedTarget)
check("tracking uses a user waypoint", tracked == true and calls.pin and calls.pin.mapID == 539 and math.abs(calls.pin.x - 0.502) < 0.001 and math.abs(calls.pin.y - 0.314) < 0.001 and calls.super == true)
check("tracking does not rewrite the block", savedTarget.x == 50.2 and savedTarget.label == "Ashlei")
C_Map.CanSetUserWaypointOnMap = function()
    return false
end
calls.pin = nil
check("a map that cannot take a waypoint is refused", WBF.NotebookSmart.Track(savedTarget) == false and calls.pin == nil)
C_Map.SetUserWaypoint = nil
check("missing waypoint api is refused", WBF.NotebookSmart.Track(savedHere) == false)

local badge = WBF.Resources.Get("timewarped_badge")
check("timewarped badge is a known resource", badge and badge.key == "timewarped_badge" and badge.id == 1166)
badge.classification = "ACCOUNT_WIDE_CURRENCY"
WarbandFYI_DB.resources = {
    balances = {
        timewarped_badge = {
            currentBalance = 12450,
            accountWide = 12450,
            characters = {},
        },
        darkmoon_ticket = {
            characters = { ["Player-1-A"] = 12, ["Player-9-B"] = 4 },
            account = 1,
        },
    },
}
local emptyView = WBF.Resources.NotebookView("order_resources")
check("a resource with no balance stays empty", emptyView and emptyView.name == "Order Resources" and emptyView.amount == nil)
local badgeView = WBF.Resources.NotebookView("timewarped_badge")
check("resource view reads the tracked warband balance", badgeView and badgeView.amount == 12450 and badgeView.accountWide == true and badgeView.character == nil)
UnitExists = function(unit)
    return unit == "player"
end
UnitGUID = function()
    return "Player-1-A"
end
UnitName = function()
    return "Miranora"
end
UnitClass = function()
    return "Mage", "MAGE"
end
UnitRace = function()
    return "Human", "Human"
end
GetRealmName = function()
    return "Area 52"
end
WBF.Characters.Update()
local ticketView = WBF.Resources.NotebookView("darkmoon_ticket")
check("resource view separates character and warband totals", ticketView and ticketView.character == 12 and ticketView.amount == 17 and ticketView.accountWide == false)
WarbandFYI_DB.resources.balances.tricky_treat = {
    characters = { ["Player-1-A"] = 5, ["Player-9-B"] = 155 },
    account = 23,
}
local savedItem = C_Item
C_Item = {
    GetItemCount = function(itemID, _, _, _, includeAccountBank)
        if itemID ~= 33226 then
            return 0
        end
        return includeAccountBank and 28 or 5
    end,
}
local treat = WBF.NotebookSmart.Describe({ refType = "item", refID = 33226 })
check("tracked item line shows the warband total", treat and treat.detail and treat.detail:find("You 5", 1, true) and treat.detail:find("Warband bank 23", 1, true) and treat.detail:find("Total 183", 1, true), treat and treat.detail)
local untracked = WBF.NotebookSmart.Describe({ refType = "item", refID = 99999 })
check("untracked item with nothing held shows no total", untracked and untracked.detail == "You 0", untracked and untracked.detail)
C_Item = savedItem
local foundResources = WBF.Resources.SearchNames("timewarp", 8)
check("resource search uses the tracker names", foundResources[1] and foundResources[1].key == "timewarped_badge")
check("unknown resource search stays empty", #WBF.Resources.SearchNames("not-a-real-currency", 8) == 0)
local resource = WBF.Notebook.AddResource(section.id, "timewarped_badge", "https://www.wowhead.com/currency=1166")
check("resource block stores the key", resource and resource.resourceKey == "timewarped_badge" and resource.type == "resource")
check("resource block does not copy the balance", resource.amount == nil and resource.currentBalance == nil and resource.quantity == nil)
check("unknown resource is not stored", WBF.Notebook.AddResource(section.id, "not-a-real-currency") == nil)

local function link(text)
    return WBF.NotebookSmart.ParseLink(text)
end

local achievementLink = link("https://www.wowhead.com/achievement=9418/draenic-pet-battler")
check("wowhead achievement url extracts the id", achievementLink and achievementLink.kind == "achievement" and achievementLink.id == 9418 and achievementLink.url:find("achievement=9418", 1, true))
local itemLink = link("https://www.wowhead.com/wotlk/item=12345")
check("wowhead item url extracts the id", itemLink and itemLink.kind == "reference" and itemLink.refType == "item" and itemLink.refID == 12345)
local pathLink = link("https://www.wowhead.com/item/12345/some-item")
check("wowhead path url extracts the id", pathLink and pathLink.refType == "item" and pathLink.refID == 12345)
local petLink = link("https://www.wowhead.com/battle-pet=708")
check("wowhead battle pet url extracts the id", petLink and petLink.refType == "battlepet" and petLink.refID == 708)
check("wowhead spell url extracts the id", link("https://ptr.wowhead.com/spell=99").refType == "spell" and link("https://ptr.wowhead.com/spell=99").refID == 99)
check("wowhead quest url extracts the id", link("https://classic.wowhead.com/quest=12").refID == 12 and link("https://classic.wowhead.com/quest=12").refType == "quest")
check("wowhead npc url extracts the id", link("https://www.wowhead.com/npc=34/ashlei").refType == "npc" and link("https://www.wowhead.com/npc=34/ashlei").refID == 34)
local currencyLink = link("https://www.wowhead.com/currency=1166")
check("known wowhead currency becomes a resource", currencyLink and currencyLink.kind == "resource" and currencyLink.resourceKey == "timewarped_badge")
local unknownCurrency = link("https://www.wowhead.com/currency=999999")
check("unknown wowhead currency stays a reference", unknownCurrency and unknownCurrency.kind == "reference" and unknownCurrency.refType == "currency" and unknownCurrency.refID == 999999)
local objectLink = link("https://www.wowhead.com/object=9")
check("unsupported wowhead type keeps the id and url", objectLink and objectLink.kind == "reference" and objectLink.refType == "object" and objectLink.refID == 9 and objectLink.url:find("object=9", 1, true))
local otherSite = link("https://example.com/notes")
check("unknown url is kept as a link", otherSite and otherSite.kind == "reference" and otherSite.refType == "link" and otherSite.url == "https://example.com/notes")
check("plain text is not stored as a link", link("hello there") == nil)

local described = WBF.NotebookSmart.Describe({
    refType = "item",
    refID = 12345,
    url = "https://www.wowhead.com/item=12345",
    label = "Menagerie book",
})
check("missing client data keeps the type, id, label, and url", described and described.resolved == false and described.title == "Menagerie book" and described.refType == "item" and described.refID == 12345 and described.url == "https://www.wowhead.com/item=12345")
check("an unresolved item does not flash its raw id", described and described.detail == nil)
local npc = WBF.NotebookSmart.Describe({ refType = "npc", refID = 34, url = "https://www.wowhead.com/npc=34/ashlei" })
check("an npc id is preserved when the client cannot name it", npc and npc.resolved == false and npc.title == "NPC 34" and npc.url:find("npc=34", 1, true))

local itemBlock = WBF.Notebook.AddReference(section.id, itemLink)
check("reference block stores the url", itemBlock and itemBlock.refType == "item" and itemBlock.refID == 12345 and itemBlock.url == itemLink.url)
local looseLink = WBF.Notebook.AddReference(section.id, otherSite)
check("unknown url block stores the original address", looseLink and looseLink.refType == "link" and looseLink.url == "https://example.com/notes" and looseLink.refID == nil)
check("a reference without an id or url is rejected", WBF.Notebook.AddReference(section.id, { refType = "item" }) == nil)

local copy = WBF.Notebook.DuplicateBlock(savedTarget.id)
check("duplicated waypoint keeps the location", copy and copy.id ~= savedTarget.id and copy.mapID == 539 and copy.label == "Ashlei" and copy.x == 50.2)

local achievementID = achievement.id
local waypointID = savedTarget.id
local resourceID = resource.id
local itemID = itemBlock.id
WBF.Database.Init()
local loadedAchievement = WBF.Notebook.GetBlock(achievementID)
local loadedWaypoint = WBF.Notebook.GetBlock(waypointID)
local loadedResource = WBF.Notebook.GetBlock(resourceID)
local loadedItem = WBF.Notebook.GetBlock(itemID)
check("reload keeps the achievement id", loadedAchievement and loadedAchievement.achievementID == 9463 and loadedAchievement.current == nil and loadedAchievement.percent == nil)
check("reload keeps the waypoint", loadedWaypoint and loadedWaypoint.mapID == 539 and loadedWaypoint.x == 50.2 and loadedWaypoint.y == 31.4 and loadedWaypoint.label == "Ashlei")
check("reload keeps the resource key", loadedResource and loadedResource.resourceKey == "timewarped_badge" and loadedResource.amount == nil and loadedResource.sourceURL:find("currency=1166", 1, true))
check("reload keeps the reference url", loadedItem and loadedItem.refID == 12345 and loadedItem.url == itemLink.url)

local function criteriaProgress(rows, current, required, completed)
    return {
        kind = "criteria",
        current = current,
        required = required,
        percent = required and required > 0 and math.floor((current / required) * 100 + 0.5) or nil,
        completed = completed and true or false,
        criteria = rows,
    }
end

local counter = WBF.PlanAchievements.CriteriaDetail(WBF.PlanAchievements.Progress(9463), false)
check("counter-only achievement keeps aggregate progress", counter and #counter.lines == 0 and #counter.completedLines == 0 and counter.more == 0 and counter.toggle == nil and counter.heading == nil and counter.summary and counter.summary:find("16 / 150", 1, true))

local namedLive = WBF.PlanAchievements.CriteriaDetail(WBF.PlanAchievements.Progress(1000), false)
check("named criteria lists incomplete objectives", namedLive and namedLive.heading == "Missing:" and #namedLive.lines == 2 and namedLive.lines[1].mark == "○" and namedLive.lines[1].text == "Treasure 3" and namedLive.lines[2].text == "Treasure 4" and namedLive.summary and namedLive.summary:find("2 / 4", 1, true))

local oneMissing = WBF.PlanAchievements.CriteriaDetail(criteriaProgress({
    { name = "Ashlei", completed = true, current = 1, required = 1 },
    { name = "Vesharr", completed = false, current = 0, required = 1 },
}, 1, 2, false), false)
check("one missing criterion is shown", oneMissing and #oneMissing.lines == 1 and oneMissing.lines[1].text == "Vesharr" and oneMissing.lines[1].mark == "○" and oneMissing.more == 0 and #oneMissing.completedLines == 0)

local threeMissing = WBF.PlanAchievements.CriteriaDetail(criteriaProgress({
    { name = "Ashlei", completed = false, current = 0, required = 1 },
    { name = "Vesharr", completed = false, current = 0, required = 1 },
    { name = "Tarr the Terrible", completed = false, current = 0, required = 1 },
}, 0, 3, false), false)
check("three missing criteria are all shown", threeMissing and #threeMissing.lines == 3 and threeMissing.more == 0 and threeMissing.toggle == nil and threeMissing.lines[1].text == "Ashlei" and threeMissing.lines[3].text == "Tarr the Terrible")

local many = criteriaProgress({
    { name = "Ashlei", completed = false, current = 0, required = 1 },
    { name = "Vesharr", completed = false, current = 0, required = 1 },
    { name = "Tarr the Terrible", completed = false, current = 0, required = 1 },
    { name = "Gargra", completed = false, current = 0, required = 1 },
}, 0, 4, false)
local compactMany = WBF.PlanAchievements.CriteriaDetail(many, false)
check("more than three missing criteria stay compact", compactMany and #compactMany.lines == 3 and compactMany.more == 1 and compactMany.toggle == "Show all" and compactMany.lines[3].text == "Tarr the Terrible" and compactMany.lines[1].text ~= "Gargra")
local openMany = WBF.PlanAchievements.CriteriaDetail(many, true)
check("show all reveals the remaining criteria", openMany and #openMany.lines == 4 and openMany.more == 0 and openMany.toggle == "Show less" and openMany.lines[4].text == "Gargra")

local finished = criteriaProgress({
    { name = "Ashlei", completed = true, current = 1, required = 1 },
    { name = "Vesharr", completed = true, current = 1, required = 1 },
    { name = "Gargra", completed = true, current = 1, required = 1 },
}, 3, 3, true)
local finishedCompact = WBF.PlanAchievements.CriteriaDetail(finished, false)
check("completed criteria stay hidden until expanded", finishedCompact and #finishedCompact.lines == 0 and finishedCompact.heading == nil and finishedCompact.toggle == "Show all" and finishedCompact.summary and finishedCompact.summary:find("Complete", 1, true))
local finishedOpen = WBF.PlanAchievements.CriteriaDetail(finished, true)
check("expanded criteria show completed marks", finishedOpen and #finishedOpen.lines == 0 and #finishedOpen.completedLines == 3 and finishedOpen.completedLines[1].mark == "✓" and finishedOpen.completedLines[1].text == "Ashlei" and finishedOpen.toggle == "Show less")

local partial = WBF.PlanAchievements.CriteriaDetail(criteriaProgress({
    { name = "Collect widgets", completed = false, current = 7, required = 10 },
}, 0, 1, false), false)
check("a criterion shows its own numeric progress", partial and #partial.lines == 1 and partial.lines[1].text == "Collect widgets  7 / 10" and partial.lines[1].mark == "○")

local blank = WBF.PlanAchievements.CriteriaDetail(criteriaProgress({
    { name = "", completed = false, current = 0, required = 1 },
    { name = nil, completed = false, current = 0, required = 1 },
    { name = "Progress", completed = false, current = 0, required = 1 },
    { name = "Criterion", completed = false, current = 0, required = 1 },
    { name = "???", completed = false, current = 0, required = 1 },
    { name = "12 / 40", completed = false, current = 0, required = 1 },
    { name = "Ash\1lei", completed = false, current = 0, required = 1 },
}, 1, 6, false), false)
check("blank or generic criterion names fall back to overall progress", blank and #blank.lines == 0 and blank.heading == nil and blank.toggle == nil and blank.summary and blank.summary:find("1 / 6", 1, true))

local secretToken = {}
local previousSecret = issecretvalue
issecretvalue = function(value)
    return value == secretToken
end
local secretView = WBF.PlanAchievements.CriteriaDetail(criteriaProgress({
    { name = secretToken, completed = false, current = secretToken, required = secretToken },
    { name = "Collect widgets", completed = secretToken, current = 7, required = 10 },
    { name = "Collect widgets", completed = false, current = secretToken, required = secretToken },
}, 0, 3, false), false)
issecretvalue = previousSecret
check("secret criterion values are not shown", secretView and #secretView.lines == 1 and secretView.lines[1].text == "Collect widgets" and secretView.lines[1].text:find("7", 1, true) == nil)

GetAchievementInfo = function(id)
    if id == 5150 then
        return 5150, "Unnamed Goals", 10, false, nil, nil, nil, "No listed objectives.", 0, 1, nil, false, false, nil, false
    end
    return nil
end
GetAchievementNumCriteria = function(id)
    if id == 5150 then
        return 2
    end
    return 0
end
GetAchievementCriteriaInfo = function(id)
    if id == 5150 then
        return "", 0, false, nil, nil
    end
    return nil
end
local unnamed = WBF.PlanAchievements.Progress(5150)
local unnamedView = WBF.PlanAchievements.CriteriaDetail(unnamed, false)
check("an empty criterion name is not invented", unnamed and unnamed.criteria[1].name == nil and #unnamedView.lines == 0 and unnamedView.summary and unnamedView.summary:find("0 / 2", 1, true))
local storedAfterDetail = WBF.Notebook.GetBlock(achievement.id)
WBF.PlanAchievements.ToggleCriteria(9463)
check("criteria detail stays out of the saved block", storedAfterDetail and storedAfterDetail.criteria == nil and storedAfterDetail.current == nil and storedAfterDetail.percent == nil and storedAfterDetail.criteriaExpanded == nil)
check("show all is remembered only in memory", WBF.PlanAchievements.CriteriaExpanded(9463) == true and WBF.PlanAchievements.ToggleCriteria(9463) == false)

if failures > 0 then
    print(failures .. " failed")
    os.exit(1)
end
print("All smart notebook checks passed")
