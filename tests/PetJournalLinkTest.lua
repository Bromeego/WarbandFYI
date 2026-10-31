-- Shift-clicking a Pet Journal pet fills the Collection Hunts target box,
-- for owned and uncollected pets, through either chat-link route.
-- Run from the repo root:
--   lua tests/PetJournalLinkTest.lua

local script = arg and arg[0] or "tests/PetJournalLinkTest.lua"
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

local function double(parent)
    local f = { shown = true, text = "", scripts = {}, hooks = {}, parent = parent }
    function f:GetParent() return self.parent end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown end
    function f:SetText(text) self.text = text or "" end
    function f:GetText() return self.text end
    function f:SetScript(event, callback) self.scripts[event] = callback end
    function f:HookScript(event, callback)
        self.hooks[event] = self.hooks[event] or {}
        table.insert(self.hooks[event], callback)
    end
    function f:Click()
        if self.scripts.OnClick then self.scripts.OnClick(self) end
        for _, hook in ipairs(self.hooks.OnClick or {}) do hook(self) end
    end
    function f:CreateTexture() return double() end
    function f:CreateFontString() return double() end
    return setmetatable(f, { __index = function(_, key)
        -- Data fields are nil unless a test sets them, as on real frames.
        if key == "petID" or key == "speciesID" or key == "dragButton" or key == "PetInfo" then return nil end
        return function() end
    end })
end

local function loadAddon(path, wbf)
    local chunk = assert(loadfile(root .. "/" .. path))
    chunk("WarbandFYI", wbf)
end

-- Blizzard globals ------------------------------------------------------------

local shift = true
local focused = true
IsShiftKeyDown = function() return shift end

local globalHooks = {}
hooksecurefunc = function(a, b, c)
    local name, fn = a, b
    if type(a) == "table" then name, fn = b, c end
    globalHooks[name] = globalHooks[name] or {}
    table.insert(globalHooks[name], fn)
end
local function fire(name, ...)
    for _, fn in ipairs(globalHooks[name] or {}) do fn(...) end
end
HandleModifiedItemClick = function() end
chatOpen = false
ChatFrameUtil = {
    InsertLink = function() end,
    GetActiveWindow = function() return chatOpen and {} or nil end,
}

local PETS = { [4321] = "Arfus", [55] = "Corefire Imp" }
C_PetJournal = {
    GetPetInfoBySpeciesID = function(speciesID) return PETS[speciesID] end,
    GetPetInfoByPetID = function(petID) if petID == "BattlePet-0-OWNED" then return 55 end end,
    GetBattlePetLink = function(petID)
        if petID == "BattlePet-0-OWNED" then
            return "|cff0070dd|Hbattlepet:55:11:3:672:0:0:BattlePet-0-OWNED|h[Corefire Imp]|h|r"
        end
    end,
}

CreateFrame = function() return double() end

-- Pet Journal with one list button already on screen and one acquired later.
local acquired
ScrollBoxListMixin = { Event = { OnAcquiredFrame = "OnAcquiredFrame" } }
local existingButton = double()
existingButton.dragButton = double(existingButton)
PetJournal = {
    IsVisible = function() return false end,
    ScrollBox = {
        ForEachFrame = function(_, fn) fn(existingButton) end,
        RegisterCallback = function(_, event, fn, owner)
            if event == "OnAcquiredFrame" then acquired = function(frame) fn(owner, frame) end end
        end,
    },
}
PetJournalPetCard = double()
PetJournalPetCard.PetInfo = double(PetJournalPetCard)

-- Addon -------------------------------------------------------------------------

local WBF = {}
loadAddon("Utils/Format.lua", WBF)
WBF.UI = {
    Colors = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
    Hex = function() return "|cffffffff" end,
    Tooltip = function() end,
    AddTip = function() end,
    Button = function() return double() end,
    EditBox = function()
        local box = double()
        function box:HasFocus() return focused end
        return box
    end,
    EmptyState = function()
        local e = double()
        function e:Set() return self end
        function e:Layout() return 90 end
        return e
    end,
}
WBF.CollectionHunts = {
    Catalog = function() return {}, {} end,
    IsHidden = function() return false end,
    Completion = function() return false end,
    IsEnabled = function() return true end,
    Settings = function() return { selected = {} } end,
    Source = function() return {} end,
    Sources = function() return {} end,
    TargetKind = function(text)
        text = tostring(text or "")
        local mount = tonumber(text:match("^%s*mount:(%d+)%s*$")); if mount then return "mount", mount end
        local pet = tonumber(text:match("battlepet:(%d+)")); if pet then return "pet", pet end
        local ach = tonumber(text:match("achievement:(%d+)")); if ach then return "achievement", ach end
        local item = tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$")); if item then return "item", item end
    end,
    Preview = function() return nil end,
    MountSourceKey = function() return nil end,
    Mount = function() return nil end,
    FindMounts = function(query)
        local all = { { id = 363, name = "Invincible's Reins" }, { id = 364, name = "Invincible's Reins of Glory" } }
        local found = {}
        query = tostring(query or ""):lower()
        if #query < 2 then return found end
        for _, entry in ipairs(all) do
            if entry.name:lower():find(query, 1, true) then found[#found + 1] = entry end
        end
        return found
    end,
    KnownSource = function() return nil end,
}
WBF.Characters = { List = function() return {} end }
loadAddon("UI/CollectionHunts.lua", WBF)

local page = double()
WBF.UI.CollectionHunts.Attach(page)
local input = page.controls.Input

local function speciesIn(text)
    return tonumber(tostring(text):match("battlepet:(%d+)"))
end

-- An uncollected pet in the list has a species but no petID.
existingButton.speciesID = 4321
existingButton:Click()
check("an uncollected list pet fills the box", speciesIn(input.text) == 4321, input.text)
check("the uncollected pet link shows its name", input.text:find("[Arfus]", 1, true) ~= nil, input.text)

-- Clicking the pet's icon on the row reads the pet from the row.
input:SetText("")
existingButton.dragButton:Click()
check("the list icon fills the box", speciesIn(input.text) == 4321, input.text)

-- An owned pet uses Blizzard's own battlepet link.
input:SetText("")
local later = double()
acquired(later)
later.petID = "BattlePet-0-OWNED"
later:Click()
check("an owned pet acquired later fills the box", speciesIn(input.text) == 55, input.text)
check("an owned pet keeps Blizzard's link", input.text:find("BattlePet-0-OWNED", 1, true) ~= nil, input.text)

-- The pet card on the right of the journal.
input:SetText("")
PetJournalPetCard.speciesID = 4321
PetJournalPetCard:Click()
check("the pet card fills the box", speciesIn(input.text) == 4321, input.text)

input:SetText("")
PetJournalPetCard.PetInfo:Click()
check("the pet card icon fills the box", speciesIn(input.text) == 4321, input.text)

-- Newer clients send chat links through ChatFrameUtil.InsertLink.
input:SetText("")
fire("InsertLink", "|cff0070dd|Hbattlepet:55:11:3:672:0:0:x|h[Corefire Imp]|h|r")
check("a ChatFrameUtil.InsertLink battlepet link fills the box", speciesIn(input.text) == 55, input.text)

-- Ignored unless Shift is held and the hunt box has focus.
input:SetText("")
shift = false
existingButton:Click()
check("a plain click does not fill the box", input.text == "", input.text)
shift = true
focused = false
existingButton:Click()
check("an unfocused box still takes the pet", speciesIn(input.text) == 4321, input.text)

input:SetText("")
chatOpen = true
existingButton:Click()
check("an unfocused box leaves the pet to an open chat box", input.text == "", input.text)
chatOpen = false
focused = true

input:SetText("")
input.shown = false
existingButton:Click()
check("a hidden hunt box is left alone", input.text == "", input.text)
input.shown = true

-- One box for every kind of target --------------------------------------------

local Page = WBF.UI.CollectionHunts
local feedback = page.controls.Feedback

input:SetText("")
existingButton:Click()
check("a Shift-clicked pet is named in the detection line", feedback.text == "Pet: Arfus", feedback.text)
check("a pet link is added as the pet", speciesIn(Page.ResolvedTarget()) == 4321, Page.ResolvedTarget())
check("a pet link shows no mount suggestions", #Page.MountMatches() == 0)

input:SetText("invincible")
check("typed text suggests mounts", #Page.MountMatches() == 2)
check("partial text is not yet a target", Page.ResolvedTarget() == "invincible")

input:SetText("Invincible's Reins")
check("a mount's full name resolves to that mount", Page.ResolvedTarget() == "mount:363", Page.ResolvedTarget())

input:SetText("inv")
page.controls.MountResults[2].mount = { id = 364, name = "Invincible's Reins of Glory" }
page.controls.MountResults[2]:Click()
check("picking a suggestion shows the mount name", input.text == "Invincible's Reins of Glory", input.text)
check("a picked mount is added by its ID", Page.ResolvedTarget() == "mount:364", Page.ResolvedTarget())
check("a picked mount hides the suggestions", #Page.MountMatches() == 0)
input:SetText("Invincible's Reins of Glor")
Page.TargetChanged(true)
check("editing the picked name drops the pick", Page.ResolvedTarget() == "Invincible's Reins of Glor", Page.ResolvedTarget())

input:SetText("49636")
Page.TargetChanged(false)
check("a number is read as an item ID", feedback.text == "Item ID 49636", feedback.text)

-- Use Current Selection reads whichever window is open ----------------------------

local use = page.controls.UseSelection
local function windowDouble(shown)
    local w = double()
    w.shown = shown
    return w
end
input:SetText("")
use:Click()
check("with no window open the selection button explains itself", feedback.text:find("Open the Mount Journal", 1, true) ~= nil, feedback.text)

PetJournal.IsVisible = function() return true end
PetJournalPetCard.speciesID = 4321
use:Click()
check("the Pet Journal selection fills the box", speciesIn(input.text) == 4321, input.text)

AchievementFrame = windowDouble(true)
AchievementFrameAchievements_GetSelectedAchievementId = function() return 725 end
use:Click()
check("two open windows are not guessed between", feedback.text:find("Close one", 1, true) ~= nil, feedback.text)

PetJournal.IsVisible = function() return false end
input:SetText("")
use:Click()
check("the Achievements selection fills the box", input.text == "achievement:725", input.text)

AchievementFrame = nil
MountJournal = windowDouble(true)
MountJournal.selectedMountID = 364
WBF.CollectionHunts.Mount = function(id) if id == 364 then return { id = 364, name = "Invincible's Reins of Glory" } end end
use:Click()
check("the Mount Journal selection picks the mount by name", input.text == "Invincible's Reins of Glory" and Page.ResolvedTarget() == "mount:364", input.text)
MountJournal = nil

if failures > 0 then
    print(failures .. " pet journal link test(s) failed")
    os.exit(1)
end
print("All pet journal link tests passed")
