local _, WBF = ...
WBF.UI.NotebookPets = {}
local dialog, search, status, listing, entries, activeBlock, generation
local page, previous, nextPage = 1
local function Button(parent, label)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(85, 22)
    WBF.UI.Paint(b, WBF.UI.Colors.card, WBF.UI.Colors.goldDim)
    local font = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    font:SetPoint("CENTER"); font:SetText(label)
    b.Label = font
    return b
end

function WBF.UI.NotebookPets.Draw(frame, block, width, hideCompleted)
    frame.Text:SetText(block.title or "Pets to Level")
    frame.Text:ClearAllPoints()
    frame.Text:SetPoint("TOPLEFT", 9, -10)
    frame.Text:SetWidth(math.max(80, width - 140))
    frame.Text:SetMaxLines(1)
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
    local pets, _, summary = WBF.NotebookPets.Progress(block)
    local visible = {}
    for _, pet in ipairs(pets) do
        if not hideCompleted or not pet.complete then visible[#visible + 1] = pet end
    end
    local rows = frame.PetRows
    local y = 46
    for i, pet in ipairs(visible) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, frame)
            row:SetHeight(38)
            row.Icon = row:CreateTexture(nil, "ARTWORK")
            row.Icon:SetSize(24, 24); row.Icon:SetPoint("LEFT", 8, 0)
            row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.Name:SetPoint("TOPLEFT", 40, -3)
            row.Name:SetJustifyH("LEFT")
            row.Name:SetWordWrap(false)
            row.Level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.Level:SetPoint("TOPLEFT", 40, -19)
            rows[i] = row
        end
        local name, icon, level, petID = pet.name, pet.icon, pet.level, pet.petID
        local speciesID = pet.speciesID
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        row.Icon:SetTexture(icon or "Interface\\Icons\\INV_Pet_BabyBlizzardBear")
        row.Name:SetText(WBF.NotebookPets.Label(pet))
        row.Name:SetWidth(math.max(60, width - 50))
        row.Level:SetText(pet.detail)
        if not row.Queue then
            row.Queue = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.Queue:SetPoint("TOPLEFT", 40, -35)
            row.Queue:SetTextColor(0.6, 0.8, 0.65)
        end
        row.Queue:SetText(pet.queueStatus or "")
        row.Queue:SetWidth(math.max(60, width - 50))
        row.Queue:SetShown(pet.queueStatus ~= nil)
        local rowHeight = pet.queueStatus and 54 or 38
        row:SetHeight(rowHeight)
        local dim = level == 25 and 0.55 or 1
        row.Name:SetTextColor(0.95 * dim, 0.90 * dim, 0.78 * dim)
        row.Level:SetTextColor(level == 25 and 0.45 or 0.95, level == 25 and 0.8 or 0.8, 0.44)
        row:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                WBF.Notebook.RemovePetFromList(block.id, petID or speciesID)
            elseif not petID then
                WBF.UI.NotebookPets.Open(block.id)
            elseif WBF.UI.OpenCollectionJournal then
                WBF.UI.OpenCollectionJournal("pet", { meta = {speciesID = speciesID, petID = petID} })

            end
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(name, 1, 0.82, 0.45)
            GameTooltip:AddLine(pet.detail, 1, 1, 1)
            if pet.queueStatus then GameTooltip:AddLine(pet.queueStatus, 0.6, 0.8, 0.65) end
            if petID then GameTooltip:AddLine(petID, 0.7, 0.7, 0.7) end
            if not petID then GameTooltip:AddLine("Add this species again to choose the copy to level.", 1, 1, 1, true) end
            GameTooltip:AddLine("Click: Pet Journal  |  Right-click: remove", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Show(); y = y + rowHeight
    end
    for i = #visible + 1, #rows do rows[i]:Hide() end
    if #visible == 0 then
        frame.Sub:ClearAllPoints()
        frame.Sub:SetPoint("TOPLEFT", 10, -46)
        frame.Sub:SetWidth(math.max(80, width - 20))
        frame.Sub:SetText(#pets == 0 and "Add pets from your collection; levels update automatically." or "All pets done")
        frame.Sub:Show(); y = 65
    end
    frame.Hint:ClearAllPoints(); frame.Hint:SetPoint("TOPLEFT", 10, -27)
    frame.Hint:SetText(summary)
    frame.Hint:Show()
    local h = math.max(82, y + 8)
    frame:SetSize(width, h)
    return h
end

local function DrawResults(query)
    if not listing or not listing:IsShown() then return end
    local q = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local found, filtered = WBF.NotebookPets.Search(q)
    local pages = math.max(1, math.ceil(#found / 8))
    page = math.min(page, pages)
    previous:SetEnabled(page > 1)
    nextPage:SetEnabled(page < pages)
    for i = 1, 8 do
        local row = entries[i]
        local pet = found[(page - 1) * 8 + i]
        if pet then
            row.Icon:SetTexture(pet.icon)
            row.Text:SetText(WBF.NotebookPets.Label(pet) .. "   Lv " .. (pet.level or "?"))
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(pet.name)
                GameTooltip:AddLine(pet.petID, 0.7, 0.7, 0.7)
                GameTooltip:AddLine("Level " .. pet.level .. " / 25", 1, 1, 1)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:SetScript("OnClick", function()
                if WBF.Notebook.AddPetToList(activeBlock, pet.petID) then
                    DrawResults(search:GetText())
                    status:SetText("Added " .. pet.name)
                else
                    status:SetText("Already listed, unavailable, or list full (60 pets)")
                end
            end)
            row:Show()
        else row:Hide() end
    end
    status:SetText(#found .. " pets - page " .. page .. "/" .. pages .. (filtered and " (Journal filters apply)" or ""))
end

local function EnsureDialog()
    if dialog then return end
    dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dialog:SetSize(410, 425)
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
        page = 1
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
    previous = Button(dialog, "Previous")
    previous:SetPoint("BOTTOMLEFT", 16, 12)
    previous:SetScript("OnClick", function() page = page - 1; DrawResults(search:GetText()) end)
    nextPage = Button(dialog, "Next")
    nextPage:SetPoint("BOTTOMRIGHT", -16, 12)
    nextPage:SetScript("OnClick", function() page = page + 1; DrawResults(search:GetText()) end)
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
        row.Text:SetWidth(330)
        row.Text:SetWordWrap(false)
        entries[i]=row
    end
    dialog:Hide()
end

function WBF.UI.NotebookPets.Open(blockId)
    local block = WBF.Notebook.GetBlock(blockId)
    if not block or block.type ~= "pet_level_list" then return end
    EnsureDialog(); activeBlock=blockId; generation=(generation or 0)+1; page=1
    dialog:Show(); search:SetText("")
    DrawResults(""); search:SetFocus()
end

function WBF.UI.NotebookPets.RefreshSearch()
    if dialog and dialog:IsShown() then DrawResults(search:GetText()) end
end
