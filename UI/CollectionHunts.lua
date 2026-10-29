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
local gold = {1, .79, .27}

local function Button(parent, width, height, caption, click)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height)
    b:SetText(caption)
    b:SetScript("OnClick", click)
    return b
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
    controls.HuntHint = Label(root, "GameFontDisableSmall", "Select a hunt to view its status.")
    controls.HuntHint:SetPoint("TOPLEFT", 12, -87)
    controls.TargetHeading = Label(root, "GameFontNormalLarge", "")
    controls.TargetHeading:SetPoint("TOPLEFT", 338, -104)
    controls.TargetIcon = root:CreateTexture(nil, "ARTWORK")
    controls.TargetIcon:SetSize(38, 38)
    controls.TargetIcon:SetPoint("TOPLEFT", 290, -101)
    controls.TargetIconBorder = root:CreateTexture(nil, "OVERLAY")
    controls.TargetIconBorder:SetColorTexture(.65, .49, .21, .85)
    controls.TargetIconBorder:SetSize(40, 1)
    controls.TargetIconBorder:SetPoint("TOPLEFT", 289, -100)
    controls.TargetHeading:SetWidth(440)
    controls.Source = Label(root, "GameFontHighlightSmall", "")
    controls.Source:SetPoint("TOPLEFT", 338, -130)
    controls.Source:SetWidth(440)

    controls.Toggle = Button(root, 160, 28, "", function()
        if not selectedKey then return end
        WBF.CollectionHunts.SetEnabled(selectedKey, not WBF.CollectionHunts.IsEnabled(selectedKey))
        Page.Refresh()
    end)
    controls.Toggle:SetPoint("TOPLEFT", 290, -167)
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
    controls.Remove:SetPoint("TOPLEFT", 459, -167)
    controls.CancelRemove = Button(root, 90, 28, "Cancel", function()
        pendingRemove = nil
        Page.Refresh()
    end)
    controls.CancelRemove:SetPoint("TOPLEFT", 630, -202)
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
    controls.Complete:SetPoint("TOPLEFT", 630, -167)
    controls.Restore = Button(root, 252, 28, "Restore preset hunt  v", function(self)
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

    controls.GoalLabel = Label(root, "GameFontNormal", "Collection goal")
    controls.GoalLabel:SetPoint("TOPLEFT", 290, -217)
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
    controls.Goal:SetPoint("TOPLEFT", 290, -238)
    controls.Explain = Label(root, "GameFontHighlightSmall", "")
    controls.Explain:SetPoint("TOPLEFT", 290, -276)
    controls.Explain:SetWidth(430)
    controls.Explain:SetWordWrap(true)
    controls.CompletedNote = Label(root, "GameFontHighlight", "")
    controls.CompletedNote:SetPoint("TOPLEFT", 290, -325)
    controls.CompletedNote:SetWidth(440)
    controls.CompletedNote:SetWordWrap(true)
    controls.CompletedSettings = Button(root, 235, 27, "Show hunt settings", function()
        showCompletedSettings = not showCompletedSettings
        Page.Refresh()
    end)
    controls.CompletedSettings:SetPoint("TOPLEFT", 290, -392)
    controls.ModeLabel = Label(root, "GameFontNormal", "Farming characters")
    controls.ModeLabel:SetPoint("TOPLEFT", 290, -338)
    controls.Mode = Button(root, 236, 28, "", function(self)
        if not selectedKey then return end
        Dropdown(self, {
            {label="All eligible characters", action=function() WBF.CollectionHunts.Settings(selectedKey).characterMode="all"; Page.Refresh(); RefreshMain() end},
            {label="Selected characters", action=function() WBF.CollectionHunts.Settings(selectedKey).characterMode="selected"; Page.Refresh(); RefreshMain() end},
        })
    end)
    controls.Mode:SetPoint("TOPLEFT", 290, -360)
    controls.CharHeading = Label(root, "GameFontHighlightSmall", "")
    controls.CharHeading:SetPoint("TOPLEFT", 290, -448)
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
    controls.UnknownToggle:SetPoint("TOPLEFT", 290, -505)

    controls.AddHeading = Label(root, "GameFontNormal", "Add a hunt")
    controls.MountSearchLabel = Label(root, "GameFontNormal", "Find a mount in your Mount Journal")
    controls.MountSearch = CreateFrame("EditBox", nil, root, "InputBoxTemplate")
    controls.MountSearch:SetAutoFocus(false)
    controls.MountSearch:SetSize(390, 26)
    controls.MountSearch:SetMaxLetters(100)
    controls.MountSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    controls.MountSearch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    controls.MountResults = {}
    for i=1,6 do
        local b = Button(root, 410, 27, "", function(self)
            local mount = self.mount
            if not mount then return end
            controls.Input:SetText("mount:" .. mount.id)
            controls.MountSearch:SetText(mount.name)
            controls.MountSearch:ClearFocus()
            local sourceKey = WBF.CollectionHunts.MountSourceKey(mount.id)
            controls.SourceKey = sourceKey
            if sourceKey then
                local source = WBF.CollectionHunts.Source(sourceKey)
                controls.SourceSelect:SetText(source.instance .. " - " .. source.boss .. "  v")
                controls.Feedback:SetText("Recognised farming source: " .. source.instance .. ".")
            else
                controls.SourceSelect:SetText("Choose raid / boss  v")
                controls.Feedback:SetText("Mount selected. Confirm a supported raid source manually; the Journal source text is not a verified boss ID.")
            end
            confirmedOwnedInput = nil
            controls.Add:SetText("Add Hunt")
            Page.Refresh()
        end)
        controls.MountResults[i] = b
    end
    controls.MountSearch:SetScript("OnTextChanged", function(self, userInput)
        if userInput then Page.Refresh() end
    end)
    controls.UseMount = Button(root, 252, 27, "Use Selected Mount", function()
        local selected = MountJournal and MountJournal.selectedMountID
        if type(selected) ~= "number" then
            controls.Feedback:SetText("Could not read the selected Mount Journal entry. Search for the mount above instead.")
            return
        end
        local entry = WBF.CollectionHunts.Mount(selected)
        if not entry then controls.Feedback:SetText("Selected mount is not available in the journal index."); return end
        controls.MountSearch:SetText(entry.name)
        controls.Input:SetText("mount:" .. selected)
        local sourceKey = WBF.CollectionHunts.MountSourceKey(selected)
        controls.SourceKey = sourceKey
        if sourceKey then
            local source = WBF.CollectionHunts.Source(sourceKey)
            controls.SourceSelect:SetText(source.instance .. " - " .. source.boss .. "  v")
        else controls.SourceSelect:SetText("Choose raid / boss  v") end
        Page.Refresh()
    end)
    controls.AddHeading:SetPoint("TOPLEFT", 12, -305)
    controls.AddHint = Label(root, "GameFontHighlightSmall", "Mounts: search the Journal above. Items: Shift-click a bag item. Pets: Shift-click one in the Pet Journal. Achievements: use selected achievement.")
    controls.AddHint:SetPoint("TOPLEFT", 12, -330)
    controls.AddHint:SetWidth(258)
    controls.Input = CreateFrame("EditBox", nil, root, "InputBoxTemplate")
    controls.Input:SetPoint("TOPLEFT", 19, -353)
    controls.Input:SetSize(240, 25)
    controls.Input:SetAutoFocus(false)
    controls.Input:SetMaxLetters(300)
    controls.Input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    controls.Input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    controls.Input:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        confirmedOwnedInput = nil
        if controls.Add then controls.Add:SetText("Add Hunt") end
        local journalID = tonumber(self:GetText():match("^%s*mount:(%d+)%s*$"))
        local journal = journalID and WBF.CollectionHunts.Mount(journalID)
        local preview = journal and {collected=journal.collected} or WBF.CollectionHunts.Preview(self:GetText())
        if preview and preview.collected == true and controls.Feedback then
            controls.Feedback:SetText("Already collected in your Mount Journal. You can still add this hunt if you want to.")
        elseif controls.Feedback then
            controls.Feedback:SetText("")
        end
        local sourceKey = WBF.CollectionHunts.KnownSource(self:GetText())
        if sourceKey then
            controls.SourceKey = sourceKey
            local source = WBF.CollectionHunts.Source(sourceKey)
            if controls.SourceSelect then controls.SourceSelect:SetText(source.instance.." - "..source.boss.."  v") end
        end
    end)
    -- Retail achievement Shift-click can toggle Blizzard's own tracking instead
    -- of inserting a chat link. Use Blizzard's current selection explicitly.
    controls.UseAchievement = Button(root, 252, 27, "Use Selected Achievement", function()
        local id
        if type(AchievementFrameAchievements_GetSelectedAchievementId) == "function" then
            id = AchievementFrameAchievements_GetSelectedAchievementId()
        end
        if type(id) ~= "number" or id <= 0 then
            controls.Feedback:SetText("Select an achievement in WoW's Achievements window first, then click here.")
            return
        end
        local link = GetAchievementLink and GetAchievementLink(id)
        controls.Input:SetText(link or ("achievement:" .. id))
        controls.Input:SetCursorPosition(#controls.Input:GetText())
        controls.Feedback:SetText("Achievement selected. Confirm the raid source and click Add Hunt.")
    end)
    controls.UseAchievement:SetPoint("TOPLEFT", 12, -388)
    controls.SourceLabel = Label(root, "GameFontHighlightSmall", "Choose the raid / boss source (holiday bosses included):")
    controls.SourceLabel:SetPoint("TOPLEFT", 12, -427)
    controls.SourceKey = nil
    controls.SourceSelect = Button(root, 252, 28, "Choose raid / boss  v", function(self)
        local opts={}
        for _, source in ipairs(WBF.CollectionHunts.Sources()) do
            local sourceKey=source.key
            local caption=source.instance.." - "..source.boss
            local label=source.note and (caption.." ("..source.note..")") or caption
            opts[#opts+1]={label=label, action=function()
                controls.SourceKey=sourceKey
                confirmedOwnedInput=nil
                if controls.Add then controls.Add:SetText("Add Hunt") end
                controls.SourceSelect:SetText(caption.."  v")
            end}
        end
        Dropdown(self, opts)
    end)
    controls.SourceSelect:SetPoint("TOPLEFT", 12, -447)
    controls.Add = Button(root, 252, 29, "Add Hunt", function()
        local input = controls.Input:GetText()
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
        local key, err = WBF.CollectionHunts.AddTarget(controls.Input:GetText(), controls.SourceKey)
        if key then
            selectedKey=key
            controls.Input:SetText("")
            controls.Feedback:SetText("Added hunt. Verify the raid source and farming eligibility.")
            Page.Refresh()
            RefreshMain()
        else
            controls.Feedback:SetText(err or "Unable to add item hunt.")
        end
    end)
    controls.Add:SetPoint("TOPLEFT", 12, -488)
    controls.Feedback=Label(root, "GameFontHighlightSmall", "")
    controls.Feedback:SetPoint("TOPLEFT", 12, -527)
    controls.Feedback:SetWidth(258)
    controls.Feedback:SetWordWrap(true)
    controls.Caution=Label(root, "GameFontDisableSmall", "Known item drops select their source automatically. For other items and achievements, choose the correct raid/boss manually. Achievement completion can be detected; class eligibility is unverified.")
    controls.Caution:SetPoint("TOPLEFT", 12, -593)
    controls.Caution:SetWidth(258)
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
    controls.EditCharacters:SetPoint("TOPLEFT", 290, -401)
    controls.ShowAll = Button(root, 190, 26, "Show all characters", function()
        showAllCharacters = not showAllCharacters
        Page.Refresh()
    end)
    controls.ShowAll:SetPoint("TOPLEFT", 530, -401)
    controls.StatusHeading = Label(root, "GameFontNormal", "This week's attempts")
    controls.StatusHeading:SetPoint("TOPLEFT", 290, -322)
    controls.StatusText = Label(root, "GameFontHighlightSmall", "")
    controls.StatusText:SetPoint("TOPLEFT", 290, -346)
    controls.StatusText:SetWidth(445)
    controls.StatusText:SetWordWrap(true)
    controls.StatusRows = {}
    local divider = root:CreateTexture(nil,"ARTWORK")
    divider:SetColorTexture(.55,.42,.17,.55)
    divider:SetPoint("TOPLEFT",278,-75)
    divider:SetSize(1,670)
    local function InsertLink(link)
        -- Bag/item links may pass through HandleModifiedItemClick without ever
        -- reaching ChatEdit_InsertLink (particularly when chat is closed).
        -- Do not steal links unless the user is editing this field on this page.
        if not (root and root:IsVisible() and controls.Input and controls.Input:HasFocus()) then return end
        if type(link) ~= "string" then return end
        -- Pet Journal Shift-clicks arrive as battlepet links.
        if not (link:find("|Hitem:", 1, true) or link:find("|Hachievement:", 1, true) or link:find("|Hbattlepet:", 1, true)
            or link:match("^item:%d+") or link:match("^achievement:%d+")) then return end
        controls.Input:SetText(link)
        controls.Input:SetCursorPosition(#link)
        local sourceKey = WBF.CollectionHunts.KnownSource(link)
        if sourceKey then
            controls.SourceKey = sourceKey
            local source = WBF.CollectionHunts.Source(sourceKey)
            controls.SourceSelect:SetText(source.instance.." - "..source.boss.."  v")
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
    if hooksecurefunc then
        if type(HandleModifiedItemClick) == "function" then
            hooksecurefunc("HandleModifiedItemClick", InsertLink)
        end
        if type(ChatEdit_InsertLink) == "function" then
            hooksecurefunc("ChatEdit_InsertLink", InsertLink)
        end
    end
    HookAchievementButtons()
    -- Blizzard_AchievementUI is load-on-demand. Installing its hook only at
    -- Collection Hunts page creation misses it when achievements open later.
    local loadWatcher = CreateFrame("Frame")
    loadWatcher:RegisterEvent("ADDON_LOADED")
    loadWatcher:SetScript("OnEvent", function(_, _, addonName)
        if addonName == "Blizzard_AchievementUI" then HookAchievementButtons() end
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
local function FormatStatus(status, daily)
    local labels = {available="|cff61df90Available|r", done=daily and "|cffdfbb66Done today|r" or "|cffdfbb66Completed this week|r",
        unknown="|cffaaaaaaUnverified|r", collected="|cff61df90Collected|r",
        excluded="Excluded", ineligible="Ineligible", closed="|cffaaaaaaEvent not running|r"}
    return labels[status] or status
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
        heading:SetPoint("TOPLEFT", 12, -y)
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
                b.Icon = b:CreateTexture(nil, "ARTWORK")
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
            Place(b, 12, y)
            local info = catalog[key]
            local icon = HuntIcon(info)
            b.Icon:SetTexture(icon or 134400)
            b:SetText("")
            b.Text:SetText((group == complete and "|cff7ee5a0" or not hunts.IsEnabled(key) and "|cff888888" or "|cffffd16d")..info.title.."|r")
            b:SetAlpha(selectedKey == key and 1 or .83)
            b:Show()
            y = y + 44
        end
        y = y + 13
    end
    DrawGroup(active, controls.ActiveHeading)
    DrawGroup(complete, controls.DoneHeading)
    for i=row+1,#controls.HuntButtons do controls.HuntButtons[i]:Hide() end
    local restoreY=math.max(177, y + 6)
    Place(controls.Restore, 12, restoreY)
    controls.Restore:SetShown(hiddenCount>0)
    -- The add form is its own view; no controls or long character list underneath the overview.
    local addWidgets = {"MountSearchLabel", "MountSearch", "UseMount", "AddHeading", "AddHint", "Input", "UseAchievement", "SourceLabel", "SourceSelect", "Add", "Feedback", "Caution"}
    for _,name in ipairs(addWidgets) do controls[name]:SetShown(adding) end
    for _, b in ipairs(controls.MountResults) do b:Hide() end
    controls.Back:SetShown(adding)
    local detailWidgets={"TargetHeading","Source","Toggle","Remove","CancelRemove","Complete","GoalLabel","Goal","Explain","ModeLabel","Mode","EditCharacters","ShowAll","StatusHeading","StatusText","CharHeading","TargetIcon","TargetIconBorder","CompletedNote","CompletedSettings"}
    for _,name in ipairs(detailWidgets) do controls[name]:SetShown(not adding and selectedKey~=nil) end
    for _,b in ipairs(controls.CharButtons) do b:Hide() end
    for _,h in ipairs(controls.AttemptHeadings) do h:Hide() end
    controls.UnknownToggle:Hide()
    for _,b in ipairs(controls.StatusRows) do b:Hide() end
    if adding then
        controls.AddHeading:SetText("Add Collection Hunt")
        Place(controls.AddHeading, 290, 91)
        Place(controls.Back, 608, 91)
        Place(controls.MountSearchLabel, 290, 136)
        Place(controls.MountSearch, 300, 159)
        local matches = WBF.CollectionHunts.FindMounts(controls.MountSearch:GetText(), 6)
        for i,b in ipairs(controls.MountResults) do
            local entry = matches[i]
            b.mount = entry
            if entry then
                b:SetText((entry.collected and "[Owned] " or "") .. entry.name)
                Place(b, 290, 192 + (i-1)*29)
                b:Show()
            end
        end
        local searchBottom = 192 + #matches * 29
        Place(controls.UseMount, 290, searchBottom+8)
        controls.AddHint:SetText("Or Shift-click a bag item or Pet Journal pet, enter an item ID, or use the selected achievement.")
        controls.AddHint:SetWidth(440)
        Place(controls.AddHint, 290, searchBottom+49)
        controls.Input:SetWidth(410)
        Place(controls.Input, 300, searchBottom+83)
        Place(controls.UseAchievement, 290, searchBottom+120)
        Place(controls.SourceLabel, 290, searchBottom+166)
        controls.SourceSelect:SetWidth(340)
        Place(controls.SourceSelect, 290, searchBottom+187)
        Place(controls.Add, 290, searchBottom+233)
        controls.Feedback:SetWidth(425)
        Place(controls.Feedback, 290, searchBottom+277)
        controls.Caution:SetWidth(425)
        controls.Caution:SetText("The Mount Journal supplies names and collection status. Raid and boss data comes from the curated registry or your manual selection; unverified sources aren't guessed.")
        Place(controls.Caution, 290, searchBottom+344)
        root:SetHeight(math.max(searchBottom+450, restoreY+65))
        return
    end
    local info = selectedKey and catalog[selectedKey]
    if not info then
        controls.StatusHeading:Show()
        controls.StatusHeading:SetText("No hunts yet")
        controls.StatusText:Show()
        controls.StatusText:SetText("Choose + Add Hunt to start tracking a collectible.")
        root:SetHeight(610)
        return
    end
    local settings=hunts.Settings(selectedKey)
    -- Holiday bosses reset daily, raids weekly; the wording follows the source.
    local source = info.sourceKey and hunts.Source(info.sourceKey)
    local daily = source and source.daily or false
    local finished, completionMethod = hunts.Completion(selectedKey)
    controls.TargetHeading:SetText(info.title)
    local icon = HuntIcon(info)
    controls.TargetIcon:SetTexture(icon or 134400)
    controls.CompletedNote:SetShown(finished)
    controls.CompletedSettings:SetShown(finished)
    controls.CompletedSettings:SetText(showCompletedSettings and "Hide hunt settings" or "Show hunt settings")
    controls.CompletedNote:SetText(finished and ("|cff7ee5a0GOAL ACHIEVED|r\n" ..
        (completionMethod == "manual" and "Marked complete manually. You can reopen this hunt." or
            "Confirmed by WoW. This collection is no longer included in farming reminders.")) or "")
    local showSettings = not finished or showCompletedSettings
    controls.GoalLabel:SetShown(showSettings)
    controls.Goal:SetShown(showSettings)
    controls.Explain:SetShown(showSettings)
    controls.ModeLabel:SetShown(showSettings)
    controls.Mode:SetShown(showSettings)
    controls.EditCharacters:SetShown(showSettings)
    controls.StatusHeading:SetShown(showSettings)
    controls.StatusText:SetShown(showSettings)
    controls.CharHeading:SetShown(showSettings)
    controls.Complete:SetText(finished and "Reopen hunt" or "Mark complete")
    controls.Complete:SetEnabled(not (finished and completionMethod ~= "manual"))
    controls.Complete:SetShown(not adding and selectedKey ~= nil)
    controls.Source:SetText(info.instance.."  —  "..info.boss)
    controls.Toggle:SetText(hunts.IsEnabled(selectedKey) and "Pause tracking" or "Resume tracking")
    controls.CancelRemove:SetShown(pendingRemove == selectedKey)
    controls.Remove:SetText(pendingRemove == selectedKey and "Confirm remove?" or "Remove hunt")
    controls.Goal:SetEnabled(info.defaultGoal~="mount")
    controls.Goal:SetText((settings.goal or "item"):gsub("^%l",string.upper).."  v")
    controls.Mode:SetText((settings.characterMode=="selected" and "Selected characters" or "All eligible characters").."  v")
    controls.Explain:SetText(finished and
        (completionMethod == "manual" and "Marked complete manually. Reopen if needed." or "Collection goal confirmed by WoW. No further runs required.") or
        selectedKey=="thoridal" and settings.goal=="achievement" and
        "Feat of Strength: Hunters, Warriors and Rogues can equip Thori'dal." or
        daily and "The daily loot bag is tracked per character and resets each day." or
        settings.goal=="mount" and "Available raid attempts are tracked per character." or
        "Eligibility is unverified for this goal unless WarbandFYI has an explicit rule.")
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
    Place(controls.StatusHeading, 290, 325)
    controls.StatusText:SetText(finished and "|cff77e39bGoal achieved|r  - farming reminders stopped" or
        (closed>0 and #available==0 and #done==0 and #unknown==0) and ("|cffaaaaaa"..info.instance.." is not running right now|r") or
        ("|cff6ee29a"..#available.." available|r   •   "..#done..(daily and " done today" or " attempted").."   •   "..#unknown.." unverified"))
    Place(controls.StatusText, 290, 349)
    -- Compact non-editing preview: never list excluded/ineligible characters.
    controls.EditCharacters:SetText(editingCharacters and "Done editing characters" or "Edit farming characters")
    controls.EditCharacters:SetShown(showSettings)
    controls.ShowAll:SetShown(showSettings and editingCharacters)
    controls.ShowAll:SetText(showAllCharacters and "Show relevant only" or "Show all characters")
    local listY = 450
    local candidates = {}
    local rowSpacing = 32
    local maxBottom = listY
    local function AddRow(char, status, x, y, width)
        candidates[#candidates+1]={char=char,status=status,x=x,y=y,width=width}
        maxBottom = math.max(maxBottom, y+rowSpacing)
    end
    if showSettings and editingCharacters then
        controls.CharHeading:SetText(settings.characterMode=="selected" and "Select farming characters" or "Switch to Selected characters to edit the roster")
        controls.CharHeading:Show()
        Place(controls.CharHeading, 290, listY)
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
            local row=math.floor((i-1)/2)
            AddRow(entry.char,entry.status,290+col*254,listY+30+row*rowSpacing,245)
        end
        if #eligible==0 then controls.CharHeading:SetText("No matching characters") end
    elseif not finished then
        controls.CharHeading:Hide()
        -- The first two groups are always useful; unverified alts are opt-in.
        local groups={
            {label="AVAILABLE  ("..#available..")",items=available,color="|cff77e39b",x=290},
            {label=(daily and "DONE TODAY  (" or "ATTEMPTED THIS WEEK  (")..#done..")",items=done,color="|cffdfbb66",x=557},
        }
        local biggest=0
        for i,group in ipairs(groups) do
            local heading=controls.AttemptHeadings[i]
            heading:SetText(group.color..group.label.."|r")
            Place(heading,group.x,listY)
            heading:Show()
            for j,char in ipairs(group.items) do
                AddRow(char,i==1 and "available" or "done",group.x,listY+30+(j-1)*rowSpacing,255)
            end
            biggest=math.max(biggest,#group.items)
        end
        local unknownY=listY+39+math.max(1,biggest)*rowSpacing
        controls.UnknownToggle:SetText((showUnknownAttempts and "Hide" or "Show").." unverified ("..#unknown..")")
        Place(controls.UnknownToggle,290,unknownY)
        controls.UnknownToggle:SetShown(#unknown>0)
        maxBottom=math.max(maxBottom,unknownY+30)
        if showUnknownAttempts and #unknown>0 then
            local h=controls.AttemptHeadings[3]
            h:SetText((daily and "|cffaaaaaaNOT YET VERIFIED — log in on each character today to check its bag|r" or "|cffaaaaaaNOT YET VERIFIED — visit each character to update its lockout|r"))
            Place(h,290,unknownY+38)
            h:Show()
            for i,char in ipairs(unknown) do
                local col=(i-1)%2
                local row=math.floor((i-1)/2)
                AddRow(char,"unknown",290+col*254,unknownY+68+row*rowSpacing,245)
            end
        end
    else
        controls.CharHeading:SetText("Collection complete — no further runs needed")
        Place(controls.CharHeading,290,listY)
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
    for i=#candidates+1,#controls.CharButtons do controls.CharButtons[i]:Hide() end
    root:SetHeight(math.max(620, (finished and not showCompletedSettings) and 610 or maxBottom+55, restoreY+65))
end
function Page.Render(width)
    Page.Refresh()
    return root and root:GetHeight() or 800
end
function Page.Open()
    if WBF.UI.frame and WBF.UI.frame.SetView then
        WBF.UI.frame:SetView("hunts")
    end
end
