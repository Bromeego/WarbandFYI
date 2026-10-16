local _, WBF = ...
WBF.UI.NotebookPets = {}
local dialog, search, status, listing, entries, activeBlock, generation
local function Refresh()
    local f = WBF.UI.frame
    if f and f.Refresh then f:Refresh(false) end
end
local function PetInfo(speciesID)
    local api = C_PetJournal
    if not api then return "Pet " .. tostring(speciesID), nil, nil, nil end
    local name, icon = nil, nil
    if api.GetPetInfoBySpeciesID then
        local ok, n, tex = pcall(api.GetPetInfoBySpeciesID, speciesID)
        if ok then name, icon = n, tex end
    end
    local level, quality, petID
    if api.GetNumPets and api.GetPetInfoByIndex then
        local ok, count = pcall(api.GetNumPets)
        if ok and type(count) == "number" then
            for i = 1, count do
                local worked, id, sid, owned, _, lvl, _, _, _, _, _, _, _, q = pcall(api.GetPetInfoByIndex, i)
                if worked and sid == speciesID and owned and id then
                    local l = tonumber(lvl)
                    if l and (not level or l > level) then level, petID, quality = l, id, q end
                end
            end
        end
    end
    return name or ("Pet " .. tostring(speciesID)), icon, level, petID, quality
end

local function Button(parent, label)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(85, 22)
    WBF.UI.Paint(b, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    local font = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    font:SetPoint("CENTER"); font:SetText(label)
    b.Label = font
    return b
end

function WBF.UI.NotebookPets.Draw(frame, block, width)
    frame.Text:SetText(block.title or "Pets to Level")
    frame.Text:ClearAllPoints()
    frame.Text:SetPoint("TOPLEFT", 9, -10)
    frame.Text:SetWidth(math.max(80, width - 120))
    frame.Text:SetTextColor(1, 0.82, 0.45)
    frame.Sub:Hide(); frame.Hint:Hide()
    if not frame.PetAdd then
        frame.PetAdd = Button(frame, "+ Add pet")
        frame.PetRows = {}
    end
    local add = frame.PetAdd
    add:ClearAllPoints(); add:SetPoint("TOPRIGHT", -36, -7)
    add:SetScript("OnClick", function() WBF.UI.NotebookPets.Open(block.id) end)
    add:Show()
    local species = type(block.species) == "table" and block.species or {}
    local rows, complete = frame.PetRows, 0
    local y = 38
    for i, speciesID in ipairs(species) do
        if i > 60 then break end
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, frame)
            row:SetHeight(29)
            row.Icon = row:CreateTexture(nil, "ARTWORK")
            row.Icon:SetSize(24, 24); row.Icon:SetPoint("LEFT", 8, 0)
            row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 8, 0)
            row.Name:SetJustifyH("LEFT")
            row.Level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.Level:SetPoint("RIGHT", -10, 0)
            rows[i] = row
        end
        local name, icon, level, petID = PetInfo(speciesID)
        if level == 25 then complete = complete + 1 end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        row.Icon:SetTexture(icon or "Interface\\Icons\\INV_Pet_BabyBlizzardBear")
        row.Name:SetText(name)
        row.Name:SetWidth(math.max(60, width - 166))
        row.Level:SetText(level and ("Lv " .. level .. (level >= 25 and "  Done" or "")) or "Not owned")
        local dim = level == 25 and 0.55 or 1
        row.Name:SetTextColor(0.95 * dim, 0.90 * dim, 0.78 * dim)
        row.Level:SetTextColor(level == 25 and 0.45 or 0.95, level == 25 and 0.8 or 0.8, 0.44)
        row:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                WBF.Notebook.RemovePetFromList(block.id, speciesID)
                Refresh()
            elseif WBF.UI.OpenCollectionJournal then
                WBF.UI.OpenCollectionJournal("pet", { meta = {speciesID = speciesID, petID = petID} })

            end
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(name, 1, 0.82, 0.45)
            GameTooltip:AddLine("Current level: " .. (level or "Not owned"), 1, 1, 1)
            GameTooltip:AddLine("Click: Pet Journal  |  Right-click: remove", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Show(); y = y + 29
    end
    for i = #species + 1, #rows do rows[i]:Hide() end
    if #species == 0 then
        frame.Sub:SetPoint("TOPLEFT", 10, -41)
        frame.Sub:SetText("Add pets from your collection; levels update automatically.")
        frame.Sub:Show(); y = 65
    end
    frame.Hint:ClearAllPoints(); frame.Hint:SetPoint("TOPLEFT", 10, -27)
    frame.Hint:SetText(complete .. " / " .. #species .. " at level 25")
    frame.Hint:Show()
    local h = math.max(82, y + 8)
    frame:SetSize(width, h)
    return h
end

local function DrawResults(query)
    if not listing or not listing:IsShown() then return end
    local q = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local found = {}
    if #q >= 2 and C_PetJournal and C_PetJournal.GetNumPets and C_PetJournal.GetPetInfoByIndex then
        local ok, n = pcall(C_PetJournal.GetNumPets)
        if ok and type(n) == "number" then
            local seen = {}
            for i = 1, n do
                local success, petID, sid, owned = pcall(C_PetJournal.GetPetInfoByIndex, i)
                if success and sid and owned and not seen[sid] then
                    seen[sid] = true
                    local name, icon, level = PetInfo(sid)
                    if name:lower():find(q, 1, true) then
                        found[#found + 1] = {id=sid, name=name, icon=icon, level=level}
                    end
                end
            end
        end
    end
    table.sort(found, function(a,b) return a.name < b.name end)
    for i = 1, 8 do
        local row = entries[i]
        local pet = found[i]
        if pet then
            row.Icon:SetTexture(pet.icon)
            row.Text:SetText(pet.name .. "   Lv " .. (pet.level or "?"))
            row:SetScript("OnClick", function()
                if WBF.Notebook.AddPetToList(activeBlock, pet.id) then
                    Refresh()
                    status:SetText("Added " .. pet.name)
                else
                    status:SetText("Already on list (or list is full)")
                end
            end)
            row:Show()
        else row:Hide() end
    end
    status:SetText(#q < 2 and "Type at least 2 letters" or #found == 0 and "No owned pets found" or ("Found " .. #found .. " matching species"))
end

local function EnsureDialog()
    if dialog then return end
    dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dialog:SetSize(410, 390)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(110)
    WBF.UI.Paint(dialog, WBF.UI.Colors.card, WBF.UI.Colors.gold)
    dialog:EnableMouse(true)
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -17); title:SetText("Add pet to levelling list")
    local close = Button(dialog, "Close")
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() dialog:Hide() end)
    search = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    search:SetSize(360, 25); search:SetPoint("TOPLEFT", 21, -55)
    search:SetAutoFocus(false); search:SetFontObject(GameFontHighlight)
    if WBF.UI.KeepKeyboard then WBF.UI.KeepKeyboard(search) end
    search:SetScript("OnEscapePressed", function() dialog:Hide() end)
    search:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        generation = generation + 1
        local token, q = generation, self:GetText()
        C_Timer.After(0.2, function()
            if token == generation and dialog:IsShown() then DrawResults(q) end
        end)
    end)
    status = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", 22, -91)
    listing = CreateFrame("Frame", nil, dialog)
    listing:SetPoint("TOPLEFT", 16, -116); listing:SetSize(375, 263)
    entries = {}
    for i=1,8 do
        local row = CreateFrame("Button", nil, listing, "BackdropTemplate")
        row:SetSize(375, 30)
        row:SetPoint("TOPLEFT", 0, -(i-1)*32)
        WBF.UI.Paint(row, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
        row.Icon = row:CreateTexture(nil,"ARTWORK")
        row.Icon:SetSize(23,23); row.Icon:SetPoint("LEFT",5,0)
        row.Text = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 8, 0)
        row.Text:SetJustifyH("LEFT")
        entries[i]=row
    end
    dialog:Hide()
end

function WBF.UI.NotebookPets.Open(blockId)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "pet_level_list" then return end
    EnsureDialog(); activeBlock=blockId; generation=(generation or 0)+1
    dialog:Show(); search:SetText("")
    DrawResults(""); search:SetFocus()
end
