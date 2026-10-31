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
ChatFrameUtil = { InsertLink = function() end }

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
    FindMounts = function() return {} end,
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
check("an unfocused box is left alone", input.text == "", input.text)
focused = true

if failures > 0 then
    print(failures .. " pet journal link test(s) failed")
    os.exit(1)
end
print("All pet journal link tests passed")
