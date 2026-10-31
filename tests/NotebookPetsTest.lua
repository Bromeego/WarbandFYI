-- Run from addon root: lua tests/NotebookPetsTest.lua
local WBF = { Time = { Now = function() return 100 end } }
local function load(path) assert(loadfile(path))("WarbandFYI", WBF) end
load("Utils/Format.lua")
load("Core/Database.lua")
WarbandFYI_DB = { nextIds = {}, config = {} }
load("Core/Notebook.lua")
load("Core/NotebookPets.lua")
load("Core/NotebookSheet.lua")
load("Core/NotebookFyi.lua")
local N, P = WBF.Notebook, WBF.NotebookPets
local checks = 0
local function eq(a, b)
    checks = checks + 1
    assert(a == b, tostring(a) .. " ~= " .. tostring(b))
end
local pets = {
    ["BattlePet-000001"] = { speciesID = 1, name = "Cat", petLevel = 3, canBattle = true },
    ["BattlePet-000002"] = { speciesID = 1, name = "Cat", petLevel = 25, canBattle = true },
    ["BattlePet-000003"] = { speciesID = 2, name = "Toy", petLevel = 1, canBattle = false },
}
C_PetJournal = {
    GetOwnedPetIDs = function() return { "BattlePet-000002", "BattlePet-000001", "BattlePet-000003" } end,
    GetPetInfoTableByPetID = function(id) return pets[id] end,
    GetPetInfoTableBySpeciesID = function() return { name = "Cat" } end,
    -- Filters exclude everything. Modern lookup must never depend on these.
    GetNumPets = function() return 0 end,
    SetSearchFilter = function() error("Do not change journal filters") end,
}
local page = N.CreatePage("Pets")
local section = N.CreateSection(page.id, "Level goals")
local block = N.AddPetLevelList(section.id)
eq(N.RenamePetLevelList(block.id, "  "), nil)
eq(N.RenamePetLevelList(block.id, "Safari") ~= nil, true)
eq(N.GetBlock(block.id).title, "Safari")
eq(N.AddPetToList(block.id, "BattlePet-000001"), true)
eq(N.AddPetToList(block.id, "BattlePet-000001"), false)
eq(N.AddPetToList(block.id, "BattlePet-000002"), true)
eq(N.AddPetToList(block.id, "BattlePet-000003"), false)
eq(N.AddPetToList(block.id, "missing"), false)
eq(N.AddPetToList(block.id, 1), false)
local rows, done, summary = P.Progress(block)
eq(rows[1].level, 3)
eq(done, 1)
eq(summary, "1 / 2 at level 25")
eq(block.pets[1].level, nil)
eq(block.pets[1].complete, nil)
eq(P.Label(rows[1]), "Cat [000001]")
local found, filtered = P.Search("cat")
eq(#found, 2)
eq(found[1].petID, "BattlePet-000001")
eq(filtered, false)
eq(#P.Search("000002"), 1)
pets["BattlePet-000001"].customName = "Mittens"
eq(P.Progress(block)[1].name, "Mittens")
eq(#P.Search("Cat"), 2) -- Species still searchable after renaming.
pets["BattlePet-000001"].petLevel = 25
rows, done = P.Progress(block)
eq(done, 2)
local copy = N.DuplicateBlock(block.id)
eq(copy.pets[1] == block.pets[1], false)
eq(N.RemovePetFromList(copy.id, "BattlePet-000001"), true)
eq(#block.pets, 2)
eq(#copy.pets, 1)
-- Reload modules and normalize the actual SavedVariables root.
load("Core/Notebook.lua"); load("Core/NotebookPets.lua")
N, P = WBF.Notebook, WBF.NotebookPets
WBF.Database.EnsureNotebook(WarbandFYI_DB)
eq(N.GetBlock(block.id).pets[1].petID, "BattlePet-000001")
pets["BattlePet-000001"] = nil
rows, done = P.Progress(block)
eq(done, 1)
eq(rows[1].detail, "Pet unavailable")
eq(#block.pets, 2) -- Missing/caged pet retained, never replaced by its sibling.
local api = C_PetJournal
C_PetJournal = nil
rows, done = P.Progress(block)
eq(done, 0)
eq(rows[2].detail, "Pet unavailable")
C_PetJournal = api
local legacy = N.AddPetLevelList(section.id)
legacy.pets = nil; legacy.species = { 1 }
rows, done = P.Progress(legacy)
eq(rows[1].detail, "Choose a copy")
eq(done, 0)
eq(N.AddPetToList(legacy.id, "BattlePet-000002"), true)
eq(#legacy.pets, 1)
eq(legacy.species, nil)
eq(legacy.pets[1].petID, "BattlePet-000002")
eq(WBF.NotebookSheet.FullWidth(block, 2), true)
-- FYI block, page and section targets all include live pet progress.
for kind, id in pairs({ block = block.id, page = page.id, section = section.id }) do
    local view = WBF.NotebookFyi.Describe({ targetKind = kind, targetId = id, triggerType = "LOGIN" })
    eq(view.lines[1].detail, "1 / 2 at level 25")
    eq(view.lines[2].detail, "Pet unavailable")
    eq(view.lines[3].completed, true)
end
local handlers, timers, refreshes = {}, {}, 0
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
N.RefreshOpen = function() refreshes = refreshes + 1 end
P.Register({ On = function(_, event, callback) handlers[event] = callback end })
handlers.PET_JOURNAL_LIST_UPDATE(); handlers.NEW_PET_ADDED(); handlers.PET_BATTLE_CLOSE()
eq(#timers, 1)
timers[1]()
eq(refreshes, 1)
-- Older-client fallback reports that the picker is filtered; saved GUIDs still work.
C_PetJournal.GetOwnedPetIDs = nil
found, filtered = P.Search("")
eq(#found, 0); eq(filtered, true)
eq(P.Progress(block)[2].level, 25)
-- Full lists can still resolve a legacy entry without silently dropping it.
local full = N.AddPetLevelList(section.id)
for i = 1, 60 do full.pets[i] = { speciesID = i } end
eq(N.AddPetToList(full.id, "BattlePet-000002"), true)
eq(#full.pets, 60)
full.pets[1].petID = "different"
eq(N.AddPetToList(full.id, "BattlePet-000002"), false)
-- Exercise the actual picker and row callbacks with lightweight frame doubles.
local frames = {}
local function frame(parent)
    local f = { parent = parent, scripts = {}, shown = true, text = "" }
    function f:SetScript(event, callback) self.scripts[event] = callback end
    function f:SetText(text) self.text = text end
    function f:GetText() return self.text end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown and (not rawget(self, "parent") or self.parent:IsShown()) end
    function f:SetEnabled(enabled) self.enabled = enabled end
    function f:CreateFontString() return frame(self) end
    function f:CreateTexture() return frame(self) end
    function f:SetShown(shown) self.shown = shown end
    setmetatable(f, { __index = function(_, key)
        if key == "Queue" then return nil end
        return function() end
    end })
    frames[#frames + 1] = f
    return f
end
CreateFrame = function(_, _, parent) return frame(parent) end
UIParent = frame()
WBF.UI = {
    Paint = function() end,
    Colors = { gold = { 1, 0.8, 0.4 }, success = { 0.47, 0.89, 0.61 }, tipFaint = { 0.7, 0.7, 0.7 } },
    SetColor = function() end,
    AddTip = function() end,
    Button = function(parent, text)
        local b = frame(parent)
        b:SetText(text)
        return b
    end,
    EditBox = function(parent) return frame(parent) end,
}
load("UI/NotebookPets.lua")
local ids = {}
for i = 1, 12 do
    local id = string.format("BattlePet-%06d", i)
    ids[i] = id
    pets[id] = { speciesID = 1, name = "Cat", petLevel = i, canBattle = true }
end
C_PetJournal.GetOwnedPetIDs = function() return ids end
local uiBlock = N.AddPetLevelList(section.id)
WBF.UI.NotebookPets.Open(uiBlock.id)
local nextButton, resultRows
resultRows = {}
for _, f in ipairs(frames) do
    if rawget(f, "text") == "Next" then nextButton = f end
    if type(rawget(f, "Text")) == "table" and rawget(f, "Icon") then resultRows[#resultRows + 1] = f end
end
eq(nextButton.enabled, true)
nextButton.scripts.OnClick()
eq(nextButton.enabled, false)
eq(resultRows[1].Text.text, "Cat [000009]   Lv 9")
eq(resultRows[5]:IsShown(), false)
resultRows[1].scripts.OnClick()
eq(uiBlock.pets[1].petID, "BattlePet-000009")
local card = frame()
-- Avoid the permissive double inventing optional pooled widgets.
card.PetAdd = false
card.Text, card.Sub, card.Hint = frame(card), frame(card), frame(card)
WBF.UI.NotebookPets.Draw(card, uiBlock, 300)
eq(card.PetRows[1].Level.text, "Lv 9 / 25")
-- Optional Rematch membership uses the exact GUID and is never persisted.
eq(P.View(uiBlock.pets[1]).queueStatus, nil)
local membership = { [ids[9]] = true }
local queue = { IsPetLeveling = function(_, id) return membership[id] or false end,
    Update = function() end }
Rematch = { queue = queue }
eq(P.View(uiBlock.pets[1]).queueStatus, "Queued in Rematch")
eq(P.View({ petID = ids[8], speciesID = 1 }).queueStatus, nil)
eq(P.View({ speciesID = 1 }).queueStatus, nil)
eq(uiBlock.pets[1].queueStatus, nil)
WBF.UI.NotebookPets.Draw(card, uiBlock, 300)
eq(card.PetRows[1].Queue.text, "Queued in Rematch")
eq(card.PetRows[1].Queue:IsShown(), true)
local fyi = WBF.NotebookFyi.Describe({ targetKind = "block", targetId = uiBlock.id, triggerType = "LOGIN" })
eq(fyi.lines[2].detail, "Lv 9 / 25 - Queued in Rematch")
membership[ids[9]] = nil
WBF.UI.NotebookPets.Draw(card, uiBlock, 300)
eq(card.PetRows[1].Queue:IsShown(), false)
queue.IsPetLeveling = function() error("incompatible addon") end
eq(P.View(uiBlock.pets[1]).queueStatus, nil)
Rematch = { queue = {} }
eq(P.View(uiBlock.pets[1]).queueStatus, nil)
-- Late loading and repeated addon events install only one read-only post-hook.
Rematch = nil
local callbacks, hooks, pending = {}, {}, {}
hooksecurefunc = function(target, method, callback)
    hooks[#hooks + 1] = { target, method, callback }
end
C_Timer.After = function(_, callback) pending[#pending + 1] = callback end
P.Register({ On = function(_, event, callback) callbacks[event] = callback end })
eq(#hooks, 0)
Rematch = { queue = queue }
queue.IsPetLeveling = function(_, id) return membership[id] == true end
callbacks.ADDON_LOADED(); callbacks.ADDON_LOADED()
eq(#hooks, 1)
eq(hooks[1][1], queue)
eq(hooks[1][2], "Update")
pending[1]()
local before = refreshes
membership[ids[9]] = true
hooks[1][3](); hooks[1][3]()
eq(#pending, 2)
pending[2]()
eq(refreshes, before + 1)
pets[ids[9]].petLevel = 25
eq(P.View(uiBlock.pets[1]).queueStatus, nil)
Rematch = nil
eq(P.View(uiBlock.pets[1]).queueStatus, nil)
WBF.UI.NotebookPets.Draw(card, uiBlock, 300, true)
eq(card.Hint.text, "1 / 1 at level 25")
eq(card.PetRows[1]:IsShown(), false)
eq(card.Sub.text, "All pets done")
WBF.UI.NotebookPets.Draw(card, uiBlock, 300)
card.PetRows[1].scripts.OnClick(nil, "RightButton")
eq(#uiBlock.pets, 0)
print("NotebookPetsTest: " .. checks .. " checks passed")
