local _, WBF = ...

-- Integrated Collection Hunts page. No modal, global key capture or chat-command UI.
WBF.UI.CollectionHunts = {}
local Page = WBF.UI.CollectionHunts
local root, selectedKey, controls = nil, nil, {}
local pendingRemove = nil
local confirmedOwnedInput = nil
local adding, editingCharacters, showAllCharacters = false, false, false
local showCompletedSettings = false
local showUnknownAttempts = false
local mountSearchResults = {}
local goals = {"achievement", "appearance", "item", "pet"}

local function HuntIcon(info)
    return info.mountIcon or (info.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.itemID))
        or (info.itemID and GetItemIcon and GetItemIcon(info.itemID))
        or (info.achievementID and GetAchievementInfo and select(10, GetAchievementInfo(info.achievementID)))
        or (info.petSpeciesID and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID and select(2, C_PetJournal.GetPetInfoBySpeciesID(info.petSpeciesID)))
end
local SUCCESS = WBF.UI.Hex(WBF.UI.Colors.success)
local WARNING = WBF.UI.Hex(WBF.UI.Colors.warning)
local MUTED = WBF.UI.Hex(WBF.UI.Colors.muted)
local FAINT = WBF.UI.Hex(WBF.UI.Colors.faint)
local GOLD = WBF.UI.Hex(WBF.UI.Colors.gold)

local function Button(parent, width, height, caption, click)
    local b = WBF.UI.Button(parent, caption, width, height)
    b:SetScript("OnClick", click)
    return b
end
-- Dropdown-style button: caption on the left, a down arrow on the right.
local function SetDropdown(button, caption)
    if not button.Arrow then
        button.Arrow = button:CreateTexture(nil, "OVERLAY")
        button.Arrow:SetSize(12, 12)
        button.Arrow:SetPoint("RIGHT", -9, 0)
        WBF.UI.SetAtlasChain(button.Arrow, { "friendslist-categorybutton-arrow-down", "common-dropdown-icon-down" },
            "Interface\\ChatFrame\\ChatFrameExpandArrow")
        local label = button:GetFontString()
        if label then
            label:ClearAllPoints()
            label:SetPoint("LEFT", 10, 0)
            label:SetPoint("RIGHT", -26, 0)
            label:SetJustifyH("LEFT")
        end
    end
    button:SetText(caption)
end
-- A battlepet link for a Journal pet: Blizzard's own for an owned pet, or
-- one built from the species for a pet not yet collected.
local function PetLink(speciesID, petID)
    if petID and C_PetJournal and C_PetJournal.GetBattlePetLink then
        local link = WBF.Format.PlainString(WBF.Format.SafeCall(C_PetJournal.GetBattlePetLink, petID))
        if link then return link end
    end
    if type(speciesID) ~= "number" or speciesID <= 0 then return nil end
    local name
    if C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        name = WBF.Format.PlainString((WBF.Format.SafeCall(C_PetJournal.GetPetInfoBySpeciesID, speciesID)))
    end
    return string.format("|cffffd200|Hbattlepet:%d:1:0:0:0:0:0000000000000000|h[%s]|h|r", speciesID, name or ("Pet #" .. speciesID))
end
local function Label(parent, font, text)
    local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    f:SetJustifyH("LEFT")
    f:SetText(text or "")
    return f
end
local function RefreshMain()
    if WBF.UI.RequestRefresh then WBF.UI.RequestRefresh() end
end
local function SortedCharacters()
    local result = WBF.Characters.List() or {}
    table.sort(result, function(a,b)
        return ((a.name or "")..(a.realm or "")):lower() < ((b.name or "")..(b.realm or "")):lower()
    end)
    return result
end
local function Dropdown(anchor, options)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(anchor, function(_, menu)
        for _, entry in ipairs(options) do
            menu:CreateButton(entry.label, entry.action)
        end
    end)
end
local function Build(parent)
    root = parent
    root.controls = controls
    controls.Heading = Label(root, "GameFontNormalLarge", "Collection Hunts")
    controls.Heading:SetPoint("TOPLEFT", 12, -12)
    controls.Intro = Label(root, "GameFontHighlightSmall", "Track a target once; see the farming status of each character. Settings save automatically.")
    controls.Intro:SetPoint("TOPLEFT", 12, -39)
    controls.Intro:SetText("Choose a hunt to see available runs and manage its settings.")

    controls.ListHeading = Label(root, "GameFontNormal", "Your hunts")
    controls.ListHeading:SetPoint("TOPLEFT", 12, -102)
    controls.HuntButtons = {}
    controls.ActiveHeading = Label(root, "GameFontNormal", "ACTIVE")
    controls.DoneHeading = Label(root, "GameFontNormal", "COLLECTED")
    controls.TargetHeading = Label(root, "GameFontNormalLarge", "")
    controls.TargetIcon = root:CreateTexture(nil, "ARTWORK")
    controls.TargetIcon:SetSize(38, 38)
    controls.TargetIconBorder = root:CreateTexture(nil, "OVERLAY")
    controls.TargetIconBorder:SetColorTexture(WBF.UI.Colors.goldDim[1], WBF.UI.Colors.goldDim[2], WBF.UI.Colors.goldDim[3], .85)
    controls.TargetIconBorder:SetSize(40, 1)
    controls.Source = Label(root, "GameFontHighlightSmall", "")

    controls.Toggle = Button(root, 160, 28, "", function()
        if not selectedKey then return end
        WBF.CollectionHunts.SetEnabled(selectedKey, not WBF.CollectionHunts.IsEnabled(selectedKey))
        Page.Refresh()
    end)
    controls.Remove = Button(root, 160, 28, "Remove hunt", function()
        if not selectedKey then return end
        if pendingRemove ~= selectedKey then
            pendingRemove = selectedKey
            Page.Refresh()
            return
        end
        WBF.CollectionHunts.Remove(selectedKey)
        selectedKey = nil
        pendingRemove = nil
        controls.Feedback:SetText("Hunt removed. Preset hunts can be restored below.")
        Page.Refresh()
        RefreshMain()
    end)
    controls.CancelRemove = Button(root, 90, 28, "Cancel", function()
        pendingRemove = nil
        Page.Refresh()
    end)
    controls.Complete = Button(root, 160, 27, "Mark complete", function()
        if not selectedKey then return end
        local complete, method = WBF.CollectionHunts.Completion(selectedKey)
        -- Auto-detected completion cannot be overridden: the source of truth is WoW.
        if complete and method ~= "manual" then return end
        WBF.CollectionHunts.SetCompleted(selectedKey, not complete)
        Page.Refresh()
        RefreshMain()
    end)
    controls.Complete:SetSize(140, 28)
    controls.Restore = Button(root, 252, 28, "Restore preset hunt", function(self)
        local hunts = WBF.CollectionHunts
        local catalog, ordered = hunts.Catalog()
        local opts = {}
        for _, key in ipairs(ordered) do
            if hunts.IsHidden(key) then
                local restoreKey = key
                opts[#opts+1] = {label=catalog[key].title, action=function()
                    hunts.Restore(restoreKey)
                    selectedKey = restoreKey
                    Page.Refresh()
                    RefreshMain()
                end}
            end
        end
        if #opts > 0 then Dropdown(self, opts) end
    end)
    controls.Restore:SetPoint("TOPLEFT", 12, -172)
    SetDropdown(controls.Restore, "Restore preset hunt")

    controls.GoalLabel = Label(root, "GameFontNormal", "Collection goal")
    controls.Goal = Button(root, 200, 28, "", function(self)
        local info = WBF.CollectionHunts.Catalog()[selectedKey]
        if not info or info.defaultGoal == "mount" then return end
        local options = {}
        for _, goal in ipairs(goals) do
            local choice = goal
            options[#options+1] = {label=choice:sub(1,1):upper()..choice:sub(2), action=function()
                WBF.CollectionHunts.Settings(selectedKey).goal = choice
                Page.Refresh()
                RefreshMain()
            end}
        end
        Dropdown(self, options)
    end)
    controls.Explain = Label(root, "GameFontHighlightSmall", "")
    controls.Explain:SetWordWrap(true)
    controls.CompletedNote = Label(root, "GameFontHighlight", "")
    controls.CompletedNote:SetWordWrap(true)
    controls.CompletedSettings = Button(root, 235, 27, "Show hunt settings", function()
        showCompletedSettings = not showCompletedSettings
        Page.Refresh()
    end)
    controls.ModeLabel = Label(root, "GameFontNormal", "Farming characters")
    controls.Mode = Button(root, 236, 28, "", function(self)
        if not selectedKey then return end
        Dropdown(self, {
            {label="All eligible characters", action=function() WBF.CollectionHunts.Settings(selectedKey).characterMode="all"; Page.Refresh(); RefreshMain() end},
            {label="Selected characters", action=function() WBF.CollectionHunts.Settings(selectedKey).characterMode="selected"; Page.Refresh(); RefreshMain() end},
        })
    end)
    controls.CharHeading = Label(root, "GameFontHighlightSmall", "")
    controls.CharButtons = {}
    controls.AttemptHeadings = {}
    for i=1,3 do
        local h=Label(root, "GameFontNormal", "")
        controls.AttemptHeadings[i]=h
    end
    controls.UnknownToggle = Button(root, 206, 25, "Show unverified characters", function()
        showUnknownAttempts = not showUnknownAttempts
        Page.Refresh()
    end)

    controls.AddHeading = Label(root, "GameFontNormal", "Add a hunt")
    -- One target box. Typing searches the Mount Journal; Shift-clicking a bag
    -- item, Pet Journal pet or achievement drops its link in; a number is an
    -- item ID. A picked mount shows its name while the hunt is added by ID.
    controls.TargetLabel = Label(root, "GameFontNormal", "What are you hunting?")
    controls.AddHint = Label(root, "GameFontHighlightSmall", "")
    controls.Picked = nil
    local function ShowSource(sourceKey, fallback)
        controls.SourceKey = sourceKey
        if sourceKey then
            local source = WBF.CollectionHunts.Source(sourceKey)
            SetDropdown(controls.SourceSelect, source.instance .. " - " .. source.boss)
            return "Recognised farming source: " .. source.instance .. "."
        end
        SetDropdown(controls.SourceSelect, "Choose raid / boss")
        return fallback
    end
    local function PickMount(mount)
        controls.Picked = { text = mount.name, target = "mount:" .. mount.id }
        controls.Input:SetText(mount.name)
        controls.Input:SetCursorPosition(#mount.name)
        controls.Input:ClearFocus()
        controls.Feedback:SetText(ShowSource(WBF.CollectionHunts.MountSourceKey(mount.id),
            "Mount selected. Confirm a supported raid source manually; the Journal source text is not a verified boss ID."))
        confirmedOwnedInput = nil
        controls.Add:SetText("Add Hunt")
        Page.Refresh()
    end
    controls.MountResults = {}
    for i=1,6 do
        local b = Button(root, 410, 27, "", function(self)
            if self.mount then PickMount(self.mount) end
        end)
        b.Icon = b:CreateTexture(nil, "OVERLAY")
        b.Icon:SetSize(19, 19)
        b.Icon:SetPoint("LEFT", 5, 0)
        b.Owned = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.Owned:SetPoint("RIGHT", -10, 0)
        b.Owned:SetText(SUCCESS .. "Owned|r")
        local label = b:GetFontString()
        if label then
            label:ClearAllPoints()
            label:SetPoint("LEFT", 31, 0)
            label:SetPoint("RIGHT", -60, 0)
            label:SetJustifyH("LEFT")
        end
        controls.MountResults[i] = b
    end
    controls.Input = WBF.UI.EditBox(root, 240, 25)
    controls.Input:SetMaxLetters(300)
    controls.Input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    controls.Input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    controls.Input:SetScript("OnTextChanged", function(self, userInput)
        Page.TargetChanged(userInput)
    end)
    -- One button for whatever is selected in an open window: the Mount
    -- Journal, the Pet Journal, or the Achievements window.
    local function SelectionTargets()
        local found = {}
        if MountJournal and MountJournal:IsVisible() then
            local entry = type(MountJournal.selectedMountID) == "number" and WBF.CollectionHunts.Mount(MountJournal.selectedMountID)
            found[#found + 1] = { window = "Mount Journal", mount = entry or nil }
        end
        if PetJournal and PetJournal:IsVisible() then
            local card = PetJournalPetCard
            local species = card and WBF.Format.AsNumber(card.speciesID)
            local link = card and PetLink(species, card.petID)
            found[#found + 1] = { window = "Pet Journal", link = link }
        end
        if AchievementFrame and AchievementFrame:IsVisible() then
            local id
            if type(AchievementFrameAchievements_GetSelectedAchievementId) == "function" then
                id = AchievementFrameAchievements_GetSelectedAchievementId()
            end
            local link
            if type(id) == "number" and id > 0 then
                link = (GetAchievementLink and GetAchievementLink(id)) or ("achievement:" .. id)
            end
            found[#found + 1] = { window = "Achievements window", link = link }
        end
        return found
    end
    controls.UseSelection = Button(root, 430, 27, "Use Current Selection", function()
        local found = SelectionTargets()
        if #found == 0 then
            controls.Feedback:SetText("Open the Mount Journal, Pet Journal or Achievements window and select something first.")
            return
        end
        if #found > 1 then
            local names = {}
            for _, entry in ipairs(found) do names[#names + 1] = entry.window end
            controls.Feedback:SetText("Both the " .. table.concat(names, " and the ") .. " are open. Close one so it's clear which to use.")
            return
        end
        local pick = found[1]
        if pick.mount then
            PickMount(pick.mount)
        elseif pick.link then
            controls.Input:SetText(pick.link)
            controls.Input:SetCursorPosition(#pick.link)
            Page.TargetChanged(false)
            Page.Refresh()
        else
            controls.Feedback:SetText("Nothing is selected in the " .. pick.window .. ". Select an entry there first.")
        end
    end)
    WBF.UI.Tooltip(controls.UseSelection, function(tip)
        tip:SetText("Use Current Selection", 1, 0.82, 0.45)
        WBF.UI.AddTip(tip, "Fills the box with what's selected in the open Mount Journal, Pet Journal or Achievements window.", WBF.UI.Colors.tipText, true)
    end)
    controls.SourceLabel = Label(root, "GameFontNormal", "Where does it drop?")
    controls.SourceKey = nil
    controls.SourceSelect = Button(root, 252, 28, "", function(self)
        local opts={}
        for _, source in ipairs(WBF.CollectionHunts.Sources()) do
            local sourceKey=source.key
            local caption=source.instance.." - "..source.boss
            local label=source.note and (caption.." ("..source.note..")") or caption
            opts[#opts+1]={label=label, action=function()
                controls.SourceKey=sourceKey
                confirmedOwnedInput=nil
                if controls.Add then controls.Add:SetText("Add Hunt") end
                SetDropdown(controls.SourceSelect, caption)
            end}
        end
        Dropdown(self, opts)
    end)
    SetDropdown(controls.SourceSelect, "Choose raid / boss")
    controls.Add = Button(root, 252, 29, "Add Hunt", function()
        local input = Page.ResolvedTarget()
        local journalID = tonumber(input:match("^%s*mount:(%d+)%s*$"))
        local journal = journalID and WBF.CollectionHunts.Mount(journalID)
        local preview = journal and {collected=journal.collected} or WBF.CollectionHunts.Preview(input)
        local signature = tostring(input) .. "|" .. tostring(controls.SourceKey)
        if preview and preview.collected == true and confirmedOwnedInput ~= signature then
            confirmedOwnedInput = signature
            controls.Add:SetText("Add Anyway")
            controls.Feedback:SetText("This mount is already collected. Click Add Anyway to keep tracking it.")
            return
        end
        confirmedOwnedInput = nil
        controls.Add:SetText("Add Hunt")
        local key, err = WBF.CollectionHunts.AddTarget(input, controls.SourceKey)
        if key then
            selectedKey=key
            controls.Input:SetText("")
            controls.Picked = nil
            controls.Feedback:SetText("Added hunt. Verify the raid source and farming eligibility.")
            Page.Refresh()
            RefreshMain()
        else
            controls.Feedback:SetText(err or "Unable to add item hunt.")
        end
    end)
    controls.Feedback=Label(root, "GameFontHighlightSmall", "")
    controls.Feedback:SetWordWrap(true)
    controls.Caution=Label(root, "GameFontDisableSmall", "Known item drops select their source automatically. For other items and achievements, choose the correct raid/boss manually. Achievement completion can be detected; class eligibility is unverified.")
    controls.Caution:SetWordWrap(true)
    controls.NewHunt = Button(root, 252, 30, "+ Add Hunt", function()
        adding = true
        editingCharacters = false
        pendingRemove = nil
        Page.Refresh()
    end)
    controls.NewHunt:SetPoint("TOPLEFT", 12, -66)
    controls.Back = Button(root, 120, 26, "Back to Hunts", function()
        adding = false
        Page.Refresh()
    end)
    controls.EditCharacters = Button(root, 235, 27, "Edit farming characters", function()
        editingCharacters = not editingCharacters
        showAllCharacters = false
        Page.Refresh()
    end)
    controls.ShowAll = Button(root, 190, 26, "Show all characters", function()
        showAllCharacters = not showAllCharacters
        Page.Refresh()
    end)
    controls.StatusHeading = Label(root, "GameFontNormal", "This week's attempts")
    controls.StatusText = Label(root, "GameFontHighlightSmall", "")
    controls.StatusText:SetWordWrap(true)
    controls.StatusRows = {}
    local divider = root:CreateTexture(nil,"ARTWORK")
    divider:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], WBF.UI.Colors.line[4])
    divider:SetPoint("TOPLEFT",278,-75)
    divider:SetSize(1,670)
    local FillInput
    local function InsertLink(link)
        -- Bag/item links may pass through HandleModifiedItemClick without ever
        -- reaching ChatEdit_InsertLink (particularly when chat is closed).
        -- Do not steal links unless the user is editing this field on this page.
        if not (root and root:IsVisible() and controls.Input and controls.Input:HasFocus()) then return end
        FillInput(link)
    end
    function FillInput(link)
        if type(link) ~= "string" then return end
        -- Pet Journal Shift-clicks arrive as battlepet links.
        if not (link:find("|Hitem:", 1, true) or link:find("|Hachievement:", 1, true) or link:find("|Hbattlepet:", 1, true)
            or link:match("^item:%d+") or link:match("^achievement:%d+")) then return end
        controls.Input:SetText(link)
        controls.Input:SetCursorPosition(#link)
        Page.TargetChanged(false)
        if WBF.CollectionHunts.KnownSource(link) then
            controls.Feedback:SetText("Recognised item source; check it before adding.")
        end
    end
    -- Items are routed through modified-item-click. Achievements are different:
    -- the Blizzard Achievement UI usually handles its own button click and
    -- only generates a chat link if the chat box is open. Capture the click
    -- directly rather than relying on the chat-link callback.
    local achievementHooked = false
    local function HookAchievementButtons()
        if achievementHooked or not hooksecurefunc then return end
        if type(AchievementButton_OnClick) ~= "function" then return end
        hooksecurefunc("AchievementButton_OnClick", function(button)
            if not (root and root:IsVisible() and controls.Input and controls.Input:HasFocus()) then return end
            if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
            local id = button and (button.id or (button.GetID and button:GetID()))
            if type(id) ~= "number" or id <= 0 then return end
            local link = GetAchievementLink and GetAchievementLink(id)
            InsertLink(link or ("achievement:" .. id))
        end)
        achievementHooked = true
    end
    -- Pet Journal Shift-clicks only make a chat link for owned pets, and newer
    -- clients send it through ChatFrameUtil.InsertLink. Uncollected pets, the
    -- usual hunt target, produce no link at all. Read the species straight
    -- from the clicked list button or pet card instead.
    -- Clicking around the Pet Journal can take focus from the hunt box, and an
    -- uncollected pet has no chat link to compete with. Take the pet whenever
    -- the Add Hunt box is on screen, unless the player is typing in chat.
    local function ChatOpen()
        local active = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and WBF.Format.SafeCall(ChatFrameUtil.GetActiveWindow))
            or (ChatEdit_GetActiveWindow and WBF.Format.SafeCall(ChatEdit_GetActiveWindow))
        return active ~= nil and active ~= false
    end
    local function TakePetClick(button)
        if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        if not (root and root:IsVisible() and controls.Input and controls.Input:IsVisible()) then
            if WBF.Debug then WBF.Debug.Log("Pet Shift-click ignored: Add Hunt box not on screen.") end
            return
        end
        if not controls.Input:HasFocus() and ChatOpen() then
            if WBF.Debug then WBF.Debug.Log("Pet Shift-click left for chat: chat box is open.") end
            return
        end
        if type(button) ~= "table" then return end
        -- The icon is a child button (dragButton on list rows, PetInfo on the
        -- card) that keeps the pet on its parent.
        local owner = button
        for _ = 1, 2 do
            if owner.petID or owner.speciesID or not owner.GetParent then break end
            local parent = owner:GetParent()
            if type(parent) ~= "table" then break end
            owner = parent
        end
        local petID = owner.petID
        local speciesID = WBF.Format.AsNumber(owner.speciesID)
        if not speciesID and petID and C_PetJournal and C_PetJournal.GetPetInfoByPetID then
            speciesID = WBF.Format.AsNumber((WBF.Format.SafeCall(C_PetJournal.GetPetInfoByPetID, petID)))
        end
        local link = PetLink(speciesID, petID)
        if WBF.Debug then WBF.Debug.Log("Pet Shift-click: species", tostring(speciesID), "petID", tostring(petID), link and "linked" or "no link") end
        if link then
            FillInput(link)
            controls.Input:SetFocus()
        end
    end
    local petHooked = {}
    local function HookPetButton(button)
        if type(button) ~= "table" or petHooked[button] or not button.HookScript then return end
        if pcall(button.HookScript, button, "OnClick", TakePetClick) then
            petHooked[button] = true
        end
        HookPetButton(button.dragButton)
        HookPetButton(button.PetInfo)
    end
    local petListHooked = false
    local function HookPetJournal()
        if petListHooked or not PetJournal then return end
        petListHooked = true
        HookPetButton(PetJournalPetCard)
        HookPetButton(PetJournalPetCardPetInfo)
        local scrollBox = PetJournal.ScrollBox
        if scrollBox then
            if scrollBox.ForEachFrame then
                pcall(scrollBox.ForEachFrame, scrollBox, HookPetButton)
            end
            if scrollBox.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnAcquiredFrame then
                pcall(scrollBox.RegisterCallback, scrollBox, ScrollBoxListMixin.Event.OnAcquiredFrame, function(_, frame)
                    HookPetButton(frame)
                end, root)
            end
        end
    end
    if hooksecurefunc then
        if type(HandleModifiedItemClick) == "function" then
            hooksecurefunc("HandleModifiedItemClick", InsertLink)
        end
        if ChatFrameUtil and type(ChatFrameUtil.InsertLink) == "function" then
            hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLink)
        end
        if type(ChatEdit_InsertLink) == "function" then
            hooksecurefunc("ChatEdit_InsertLink", InsertLink)
        end
    end
    HookAchievementButtons()
    HookPetJournal()
    -- Blizzard_AchievementUI is load-on-demand. Installing its hook only at
    -- Collection Hunts page creation misses it when achievements open later.
    local loadWatcher = CreateFrame("Frame")
    loadWatcher:RegisterEvent("ADDON_LOADED")
    loadWatcher:SetScript("OnEvent", function(_, _, addonName)
        if addonName == "Blizzard_AchievementUI" then HookAchievementButtons() end
        if addonName == "Blizzard_Collections" then HookPetJournal() end
    end)
    -- When a user opens achievements after this page was built, the click
    -- handler is then installed even when no achievement window existed yet.

end

function Page.Attach(parent)
    if root then return end
    Build(parent)
end

local function Place(widget, x, y)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", x, -y)
end

local LIST_X, DETAIL_X = 12, 290
local pageWidth

-- Running vertical layout for the right-hand column. Each call places a
-- widget at the cursor, shows it and moves the cursor below it, so sections
-- stack without overlapping however the text wraps.
local function Flow(x, y, width)
    local flow = { x = x, y = y, width = width }
    function flow:Put(widget, height, gap, dx)
        Place(widget, self.x + (dx or 0), self.y)
        widget:Show()
        self.y = self.y + height + (gap or 8)
    end
    function flow:Text(fontString, gap)
        fontString:SetWidth(self.width)
        Place(fontString, self.x, self.y)
        fontString:Show()
        local height = math.ceil(fontString:GetStringHeight() or 0)
        self.y = self.y + math.max(14, height) + (gap or 8)
    end
    -- Widgets side by side on one line; each item is { widget, width }.
    function flow:Row(items, height, gap)
        local x = self.x
        for _, item in ipairs(items) do
            Place(item[1], x, self.y)
            item[1]:Show()
            x = x + item[2] + 9
        end
        self.y = self.y + height + (gap or 8)
    end
    return flow
end

local function FormatStatus(status, daily)
    local labels = {available=SUCCESS .. "Available|r", done=daily and WARNING .. "Done today|r" or WARNING .. "Completed this week|r",
        unknown=MUTED .. "Unverified|r", collected=SUCCESS .. "Collected|r",
        excluded="Excluded", ineligible="Ineligible", closed=MUTED .. "Event not running|r"}
    return labels[status] or status
end

-- Every widget in the right-hand column. Refresh hides them all, then the
-- flow shows the ones the current view needs.
local DETAIL_WIDGETS = {"AddHeading", "Back", "TargetLabel", "UseSelection", "AddHint", "Input",
    "SourceLabel", "SourceSelect", "Add", "Feedback", "Caution",
    "TargetHeading", "Source", "TargetIcon", "TargetIconBorder", "Toggle", "Remove", "CancelRemove", "Complete",
    "CompletedNote", "CompletedSettings", "GoalLabel", "Goal", "Explain", "ModeLabel", "Mode", "EditCharacters",
    "ShowAll", "StatusHeading", "StatusText", "CharHeading", "UnknownToggle"}

local function DrawAddForm(width)
    local flow = Flow(DETAIL_X, 91, width)
    controls.AddHeading:SetText("Add Collection Hunt")
    Place(controls.Back, DETAIL_X + width - 120, 88)
    controls.Back:Show()
    flow:Put(controls.AddHeading, 20, 25)
    flow:Put(controls.TargetLabel, 14, 9)
    controls.AddHint:SetText("Type a mount name and pick it below, Shift-click a bag item or Pet Journal pet, enter an item ID, or use what's selected in the Mount Journal, Pet Journal or Achievements window.")
    flow:Text(controls.AddHint, 8)
    controls.Input:SetWidth(width - 5)
    flow:Put(controls.Input, 25, 6, 5)
    local matches = Page.MountMatches()
    for i, b in ipairs(controls.MountResults) do
        local entry = matches[i]
        b.mount = entry
        if entry then
            b:SetText(entry.name)
            b.Icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.Owned:SetShown(entry.collected == true)
            b:SetWidth(width - 5)
            flow:Put(b, 27, 2)
        end
    end
    flow.y = flow.y + 6
    controls.UseSelection:SetWidth(width - 5)
    flow:Put(controls.UseSelection, 27, 18)
    flow:Text(controls.SourceLabel, 6)
    controls.SourceSelect:SetWidth(width - 5)
    flow:Put(controls.SourceSelect, 28, 18)
    controls.Add:SetWidth(width - 5)
    controls.Add:SetEnabled((controls.Input:GetText() or ""):match("%S") ~= nil)
    flow:Put(controls.Add, 29, 14)
    flow:Text(controls.Feedback, 14)
    controls.Caution:SetText("The Mount Journal supplies names and collection status. Raid and boss data comes from the curated registry or your manual selection; unverified sources aren't guessed.")
    flow:Text(controls.Caution, 0)
    return flow.y
end

local function DrawNoHunts(width)
    local empty = controls.Empty
    if not empty then
        empty = WBF.UI.EmptyState(root)
        controls.Empty = empty
    end
    empty:Set("No hunts yet", "Choose + Add Hunt to track a mount, pet, item or achievement across your characters.",
        { "QuestNormal" }, "Interface\\Icons\\INV_Misc_Spyglass_03")
    Place(empty, DETAIL_X, 101)
    empty:Show()
    return 101 + empty:Layout(width)
end

-- The target Add Hunt uses: a picked mount's ID while its name is still in
-- the box, an exact mount name typed in full, or the box text as entered.
function Page.ResolvedTarget()
    local text = controls.Input and controls.Input:GetText() or ""
    local picked = controls.Picked
    if picked and text == picked.text then return picked.target end
    if not WBF.CollectionHunts.TargetKind(text) then
        local wanted = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
        for _, entry in ipairs(WBF.CollectionHunts.FindMounts(wanted, 50)) do
            if entry.name:lower() == wanted then return "mount:" .. entry.id end
        end
    end
    return text
end

-- Mount suggestions only while the box holds plain typed text.
function Page.MountMatches()
    local text = controls.Input and controls.Input:GetText() or ""
    if controls.Picked and text == controls.Picked.text then return {} end
    if text:find("|H", 1, true) or WBF.CollectionHunts.TargetKind(text) then return {} end
    return WBF.CollectionHunts.FindMounts(text, 6)
end

local KIND_LABELS = { mount = "Mount", pet = "Pet", achievement = "Achievement", item = "Item" }

-- Shows what the box holds, carries a recognised source over, and resets the
-- owned-mount confirmation whenever the target changes.
function Page.TargetChanged(userInput)
    local text = controls.Input:GetText()
    if controls.Picked and text ~= controls.Picked.text then controls.Picked = nil end
    confirmedOwnedInput = nil
    if controls.Add then controls.Add:SetText("Add Hunt") end
    local target = Page.ResolvedTarget()
    local kind, id = WBF.CollectionHunts.TargetKind(target)
    local message = ""
    if kind == "mount" then
        local journal = WBF.CollectionHunts.Mount(id)
        if journal and journal.collected == true then
            message = "Already collected in your Mount Journal. You can still add this hunt if you want to."
        elseif journal then
            message = "Mount: " .. journal.name
        end
    elseif kind then
        local preview = WBF.CollectionHunts.Preview(target)
        if preview and preview.collected == true then
            message = "Already collected in your Mount Journal. You can still add this hunt if you want to."
        else
            local name = text:match("|h%[(.-)%]|h")
            if name then
                message = KIND_LABELS[kind] .. ": " .. name
            else
                message = KIND_LABELS[kind] .. " ID " .. id
            end
        end
    end
    local sourceKey = kind == "mount" and WBF.CollectionHunts.MountSourceKey and WBF.CollectionHunts.MountSourceKey(id)
        or WBF.CollectionHunts.KnownSource(target)
    local journalKey, journalLines
    if kind and WBF.CollectionHunts.JournalSource then
        journalKey, journalLines = WBF.CollectionHunts.JournalSource(kind, id)
    end
    sourceKey = sourceKey or journalKey
    if journalLines and #journalLines > 0 then
        local parts = {}
        for _, line in ipairs(journalLines) do
            parts[#parts + 1] = line.label and (line.label .. ": " .. line.value) or line.value
        end
        local notes = { message ~= "" and message or nil }
        notes[#notes + 1] = MUTED .. "Journal: " .. table.concat(parts, ", ") .. "|r"
        if sourceKey then
            notes[#notes + 1] = SUCCESS .. "Source chosen automatically. Check it before adding.|r"
        else
            notes[#notes + 1] = WARNING .. "This source isn't supported yet. Choose one below if it fits.|r"
        end
        message = table.concat(notes, "\n")
    end
    if controls.Feedback then controls.Feedback:SetText(message) end
    if controls.Add then controls.Add:SetEnabled(text:match("%S") ~= nil) end
    -- A new target never inherits the previous target's source. A source the
    -- player chose by hand stays while the target itself is unchanged.
    local identity = kind and (kind .. ":" .. id) or nil
    local targetChanged = identity ~= controls.LastTarget
    controls.LastTarget = identity
    if sourceKey and controls.SourceSelect then
        controls.SourceKey = sourceKey
        local source = WBF.CollectionHunts.Source(sourceKey)
        SetDropdown(controls.SourceSelect, source.instance .. " - " .. source.boss)
    elseif targetChanged and controls.SourceSelect then
        controls.SourceKey = nil
        SetDropdown(controls.SourceSelect, "Choose raid / boss")
    end
    if userInput then Page.Refresh() end
end

function Page.Refresh()
    if not root then return end
    local hunts = WBF.CollectionHunts
    local catalog, ordered = hunts.Catalog()
    local visible, hiddenCount = {}, 0
    for _,key in ipairs(ordered) do
        if hunts.IsHidden(key) then hiddenCount = hiddenCount + 1
        else visible[#visible+1] = key end
    end
    if not selectedKey or not catalog[selectedKey] or hunts.IsHidden(selectedKey) then
        selectedKey = visible[1]
        pendingRemove = nil
    end
    controls.NewHunt:SetText(adding and "Adding a hunt..." or "+ Add Hunt")
    controls.NewHunt:SetEnabled(not adding)
    controls.ListHeading:SetText("Your hunts ("..#visible..")")
    -- Present actionable hunts first, completed ones second. Keep all data unchanged.
    local active, complete = {}, {}
    for _, key in ipairs(visible) do
        if hunts.Completion(key) then complete[#complete+1]=key
        else active[#active+1]=key end
    end
    local y = 127
    local row = 0
    local function DrawGroup(group, heading)
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", LIST_X, -y)
        heading:SetText(group == active and ("ACTIVE  ("..#group..")") or ("COLLECTED  ("..#group..")"))
        heading:Show()
        y = y + 23
        for _,key in ipairs(group) do
            row = row + 1
            local b = controls.HuntButtons[row]
            if not b then
                b = Button(root, 254, 40, "", function(self)
                    selectedKey = self.huntKey
                    adding = false
                    editingCharacters = false
                    showCompletedSettings = false
                    pendingRemove = nil
                    Page.Refresh()
                end)
                -- OVERLAY keeps the icon above the button's ARTWORK fill.
                b.Icon = b:CreateTexture(nil, "OVERLAY")
                b.Icon:SetSize(28, 28)
                b.Icon:SetPoint("LEFT", 7, 0)
                b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                b.Text:SetPoint("LEFT", b.Icon, "RIGHT", 8, 0)
                b.Text:SetWidth(204)
                b.Text:SetJustifyH("LEFT")
                b.Text:SetWordWrap(false)
                controls.HuntButtons[row] = b
            end
            b.huntKey = key
            Place(b, LIST_X, y)
            local info = catalog[key]
            local icon = HuntIcon(info)
            b.Icon:SetTexture(icon or 134400)
            b:SetText("")
            b.Text:SetText((group == complete and SUCCESS or not hunts.IsEnabled(key) and FAINT or GOLD)..info.title.."|r")
            if selectedKey == key and not adding then b:LockHighlight() else b:UnlockHighlight() end
            b:Show()
            y = y + 44
        end
        y = y + 13
    end
    DrawGroup(active, controls.ActiveHeading)
    DrawGroup(complete, controls.DoneHeading)
    for i=row+1,#controls.HuntButtons do controls.HuntButtons[i]:Hide() end
    local restoreY=math.max(177, y + 6)
    Place(controls.Restore, LIST_X, restoreY)
    controls.Restore:SetShown(hiddenCount>0)
    local listBottom = restoreY + 65

    for _, name in ipairs(DETAIL_WIDGETS) do controls[name]:Hide() end
    for _, b in ipairs(controls.MountResults) do b:Hide() end
    for _, b in ipairs(controls.CharButtons) do b:Hide() end
    for _, h in ipairs(controls.AttemptHeadings) do h:Hide() end
    if controls.Empty then controls.Empty:Hide() end
    local width = math.max(440, (pageWidth or 760) - DETAIL_X - 12)

    -- The add form is its own view; no controls or long character list underneath the overview.
    if adding then
        local bottom = DrawAddForm(math.min(width, 440))
        root:SetHeight(math.max(bottom + 40, listBottom))
        return
    end
    local info = selectedKey and catalog[selectedKey]
    if not info then
        root:SetHeight(math.max(610, DrawNoHunts(math.min(width, 520)) + 40, listBottom))
        return
    end
    local settings=hunts.Settings(selectedKey)
    -- Holiday bosses reset daily, raids weekly; the wording follows the source.
    local source = info.sourceKey and hunts.Source(info.sourceKey)
    local daily = source and source.daily or false
    local finished, completionMethod = hunts.Completion(selectedKey)

    Place(controls.TargetIcon, DETAIL_X, 101)
    controls.TargetIcon:SetTexture(HuntIcon(info) or 134400)
    controls.TargetIcon:Show()
    Place(controls.TargetIconBorder, DETAIL_X - 1, 100)
    controls.TargetIconBorder:Show()
    controls.TargetHeading:SetText(info.title)
    controls.TargetHeading:SetWidth(width - 48)
    Place(controls.TargetHeading, DETAIL_X + 48, 104)
    controls.TargetHeading:Show()
    controls.Source:SetText(info.instance.."  —  "..info.boss)
    controls.Source:SetWidth(width - 48)
    Place(controls.Source, DETAIL_X + 48, 130)
    controls.Source:Show()

    local flow = Flow(DETAIL_X, 167, width)
    controls.Toggle:SetText(hunts.IsEnabled(selectedKey) and "Pause tracking" or "Resume tracking")
    controls.Remove:SetText(pendingRemove == selectedKey and "Confirm remove?" or "Remove hunt")
    controls.Complete:SetText(finished and "Reopen hunt" or "Mark complete")
    controls.Complete:SetEnabled(not (finished and completionMethod ~= "manual"))
    -- While a remove is pending, Cancel takes the third slot.
    flow:Row({
        { controls.Toggle, 160 },
        { controls.Remove, 160 },
        pendingRemove == selectedKey and { controls.CancelRemove, 90 } or { controls.Complete, 140 },
    }, 28, 18)

    if finished then
        controls.CompletedNote:SetText(SUCCESS .. "GOAL ACHIEVED|r\n" ..
            (completionMethod == "manual" and "Marked complete manually. You can reopen this hunt." or
                "Confirmed by WoW. This collection is no longer included in farming reminders."))
        flow:Text(controls.CompletedNote, 10)
        controls.CompletedSettings:SetText(showCompletedSettings and "Hide hunt settings" or "Show hunt settings")
        flow:Put(controls.CompletedSettings, 27, 18)
    end
    local showSettings = not finished or showCompletedSettings
    if not showSettings then
        root:SetHeight(math.max(610, flow.y + 40, listBottom))
        return
    end

    flow:Put(controls.GoalLabel, 14, 6)
    controls.Goal:SetEnabled(info.defaultGoal~="mount")
    SetDropdown(controls.Goal, ((settings.goal or "item"):gsub("^%l",string.upper)))
    flow:Put(controls.Goal, 28, 8)
    controls.Explain:SetText(finished and
        (completionMethod == "manual" and "Marked complete manually. Reopen if needed." or "Collection goal confirmed by WoW. No further runs required.") or
        selectedKey=="thoridal" and settings.goal=="achievement" and
        "Feat of Strength: Hunters, Warriors and Rogues can equip Thori'dal." or
        daily and "The daily loot bag is tracked per character and resets each day." or
        settings.goal=="mount" and "Available raid attempts are tracked per character." or
        "Eligibility is unverified for this goal unless WarbandFYI has an explicit rule.")
    flow:Text(controls.Explain, 18)
    flow:Put(controls.ModeLabel, 14, 6)
    SetDropdown(controls.Mode, settings.characterMode=="selected" and "Selected characters" or "All eligible characters")
    flow:Put(controls.Mode, 28, 8)
    controls.EditCharacters:SetText(editingCharacters and "Done editing characters" or "Edit farming characters")
    controls.ShowAll:SetText(showAllCharacters and "Show relevant only" or "Show all characters")
    local editRow = { { controls.EditCharacters, 235 } }
    if editingCharacters then editRow[2] = { controls.ShowAll, 190 } end
    flow:Row(editRow, 27, 22)

    -- Show actionable characters, successful attempts and unverified counts separately.
    local available, done, unknown, closed = {}, {}, {}, 0
    local characters = SortedCharacters()
    for _,char in ipairs(characters) do
        if char.guid then
            local status = hunts.Status(selectedKey, char.guid)
            if status=="available" then available[#available+1]=char
            elseif status=="done" then done[#done+1]=char
            elseif status=="unknown" then unknown[#unknown+1]=char
            elseif status=="closed" then closed=closed+1 end
        end
    end
    controls.StatusHeading:SetText(finished and "Collection complete" or (daily and "Today's attempts" or "This week's attempts"))
    flow:Put(controls.StatusHeading, 14, 6)
    controls.StatusText:SetText(finished and SUCCESS .. "Goal achieved|r  - farming reminders stopped" or
        (closed>0 and #available==0 and #done==0 and #unknown==0) and (MUTED..info.instance.." is not running right now|r") or
        (SUCCESS..#available.." available|r   •   "..#done..(daily and " done today" or " attempted").."   •   "..#unknown.." unverified"))
    flow:Text(controls.StatusText, 18)

    -- Character lists run in two columns below the status line.
    local listY = flow.y
    local colWidth = math.floor((width - 9) / 2)
    local col2X = DETAIL_X + colWidth + 9
    local candidates = {}
    local rowSpacing = 32
    local maxBottom = listY
    local function AddRow(char, status, x, y, rowWidth)
        candidates[#candidates+1]={char=char,status=status,x=x,y=y,width=rowWidth}
        maxBottom = math.max(maxBottom, y+rowSpacing)
    end
    if editingCharacters then
        controls.CharHeading:SetText(settings.characterMode=="selected" and "Select farming characters" or "Switch to Selected characters to edit the roster")
        Place(controls.CharHeading, DETAIL_X, listY)
        controls.CharHeading:Show()
        local eligible = {}
        for _,char in ipairs(characters) do
            if char.guid then
                local status = hunts.Status(selectedKey, char.guid)
                if showAllCharacters or (status~="ineligible" and status~="excluded") or settings.selected[char.guid] then
                    eligible[#eligible+1]={char=char,status=status}
                end
            end
        end
        for i,entry in ipairs(eligible) do
            local col=(i-1)%2
            local listRow=math.floor((i-1)/2)
            AddRow(entry.char,entry.status,col==0 and DETAIL_X or col2X,listY+30+listRow*rowSpacing,colWidth)
        end
        if #eligible==0 then controls.CharHeading:SetText("No matching characters") end
    elseif not finished then
        -- The first two groups are always useful; unverified alts are opt-in.
        local groups={
            {label="AVAILABLE  ("..#available..")",items=available,color=SUCCESS,x=DETAIL_X},
            {label=(daily and "DONE TODAY  (" or "ATTEMPTED THIS WEEK  (")..#done..")",items=done,color=WARNING,x=col2X},
        }
        local biggest=0
        for i,group in ipairs(groups) do
            local heading=controls.AttemptHeadings[i]
            heading:SetText(group.color..group.label.."|r")
            Place(heading,group.x,listY)
            heading:Show()
            for j,char in ipairs(group.items) do
                AddRow(char,i==1 and "available" or "done",group.x,listY+30+(j-1)*rowSpacing,colWidth)
            end
            biggest=math.max(biggest,#group.items)
        end
        local unknownY=listY+39+math.max(1,biggest)*rowSpacing
        controls.UnknownToggle:SetText((showUnknownAttempts and "Hide" or "Show").." unverified ("..#unknown..")")
        Place(controls.UnknownToggle,DETAIL_X,unknownY)
        controls.UnknownToggle:SetShown(#unknown>0)
        maxBottom=math.max(maxBottom,unknownY+30)
        if showUnknownAttempts and #unknown>0 then
            local h=controls.AttemptHeadings[3]
            h:SetText((daily and MUTED .. "NOT YET VERIFIED — log in on each character today to check its bag|r" or MUTED .. "NOT YET VERIFIED — visit each character to update its lockout|r"))
            Place(h,DETAIL_X,unknownY+38)
            h:Show()
            for i,char in ipairs(unknown) do
                local col=(i-1)%2
                local listRow=math.floor((i-1)/2)
                AddRow(char,"unknown",col==0 and DETAIL_X or col2X,unknownY+68+listRow*rowSpacing,colWidth)
            end
        end
    else
        controls.CharHeading:SetText("Collection complete — no further runs needed")
        Place(controls.CharHeading,DETAIL_X,listY)
        controls.CharHeading:Show()
        maxBottom = listY + 20
    end
    for i,entry in ipairs(candidates) do
        local char,status=entry.char,entry.status
        local b=controls.CharButtons[i]
        if not b then
            b=Button(root,245,28,"",function(self)
                if not editingCharacters then return end
                local setting=hunts.Settings(selectedKey)
                if setting.characterMode~="selected" then return end
                setting.selected[self.characterGuid]=not setting.selected[self.characterGuid] or nil
                Page.Refresh()
                RefreshMain()
            end)
            controls.CharButtons[i]=b
        end
        b.characterGuid=char.guid
        b:SetSize(entry.width,28)
        Place(b,entry.x,entry.y)
        local prefix=editingCharacters and (settings.selected[char.guid] and "[x] " or "[ ] ") or ""
        local name=(char.name or "Unknown")
        local realm=(char.realm and char.realm~="") and (" - "..char.realm) or ""
        -- Keep status legible without truncating the name on narrow columns.
        b:SetText(prefix..name..realm.."  "..FormatStatus(status, daily))
        b:SetEnabled(editingCharacters and settings.characterMode=="selected")
        b:Show()
    end
    root:SetHeight(math.max(620, maxBottom+55, listBottom))
end
function Page.Render(width)
    pageWidth = width
    Page.Refresh()
    return root and root:GetHeight() or 800
end
function Page.Open()
    if WBF.UI.frame and WBF.UI.frame.SetView then
        WBF.UI.frame:SetView("hunts")
    end
end
