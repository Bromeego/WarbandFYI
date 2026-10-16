local _, WBF = ...

WBF.UI.MainWindow = {}

local PERIOD = {
    current = true,
    last = true,
    today = true,
    week = true,
    month = true,
    warband = true,
}

local function UpdateScrollBar(scroll, bar)
    local range = scroll:GetVerticalScrollRange()
    if range <= 1 then
        bar:Hide()
        scroll:SetVerticalScroll(0)
        return
    end
    bar:Show()
    bar.updating = true
    bar:SetMinMaxValues(0, range)
    local value = math.min(scroll:GetVerticalScroll(), range)
    bar:SetValue(value)
    bar.updating = false
end

function WBF.UI.MainWindow.Create()
    if WBF.UI.frame then
        return WBF.UI.frame
    end

    local frame = CreateFrame("Frame", "WarbandFYIFrame", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(1040, 680)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(80)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(920, 560, 1400, 980)
    else
        frame:SetMinResize(920, 560)
        frame:SetMaxResize(1400, 980)
    end
    WBF.UI.Paint(frame, WBF.UI.Colors.window, WBF.UI.Colors.windowBorder, 2)

    local saved = WarbandFYI_DB.config.window
    if saved and saved.point then
        frame.applyingSize = true
        frame:ClearAllPoints()
        frame:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
        if saved.width and saved.height then
            frame:SetSize(saved.width, saved.height)
        end
        frame.applyingSize = false
    end

    local view = WarbandFYI_DB.config.lastView or "week"
    if view == "plans" then
        view = "notebook"
    end
    if not PERIOD[view] and view ~= "characters" and view ~= "activity" and view ~= "resources" and view ~= "notebook" and view ~= "hunts" then
        view = "week"
    end
    frame.view = view

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 12, -8)
    header:SetPoint("TOPRIGHT", -36, -8)
    header:SetHeight(52)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        WBF.Database.SaveWindow(frame)
    end)

    local crest = header:CreateTexture(nil, "ARTWORK")
    crest:SetSize(42, 42)
    crest:SetPoint("LEFT", 6, 0)
    WBF.UI.SetAtlasChain(crest, { "warbands-icon", "warbands-charselect-icon" }, "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", crest, "TOPRIGHT", 10, -2)
    title:SetText("WarbandFYI")
    title:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])

    local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText("See what your Warband's been up to.")
    subtitle:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 10, -64)
    rule:SetPoint("TOPRIGHT", -10, -64)
    rule:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], WBF.UI.Colors.line[4])

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    local nav = CreateFrame("Frame", nil, frame)
    nav:SetPoint("TOPLEFT", 8, -70)
    nav:SetPoint("BOTTOMLEFT", 8, 10)
    nav:SetWidth(176)
    local navBg = nav:CreateTexture(nil, "BACKGROUND")
    navBg:SetAllPoints()
    navBg:SetColorTexture(WBF.UI.Colors.nav[1], WBF.UI.Colors.nav[2], WBF.UI.Colors.nav[3], WBF.UI.Colors.nav[4])

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", 0, 0)
    divider:SetColorTexture(WBF.UI.Colors.line[1], WBF.UI.Colors.line[2], WBF.UI.Colors.line[3], 0.45)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 12, 0)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 18)

    local buttons = CreateFrame("Frame", nil, content)
    buttons:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    buttons:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    buttons:SetHeight(28)

    local settingsButton = CreateFrame("Button", nil, buttons, "UIPanelButtonTemplate")
    settingsButton:SetSize(100, 22)
    settingsButton:SetPoint("BOTTOMRIGHT", buttons, "BOTTOMRIGHT", 0, 0)
    settingsButton:SetText("Settings")

    local warbandButton = CreateFrame("Button", nil, buttons, "UIPanelButtonTemplate")
    warbandButton:SetSize(100, 22)
    warbandButton:SetPoint("RIGHT", settingsButton, "LEFT", -8, 0)
    warbandButton:SetText("Warband")

    local sessionButton = CreateFrame("Button", nil, buttons, "UIPanelButtonTemplate")
    sessionButton:SetSize(120, 22)
    sessionButton:SetPoint("RIGHT", warbandButton, "LEFT", -8, 0)
    sessionButton:SetText("View Session")

    local scroll = CreateFrame("ScrollFrame", nil, content)
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", buttons, "TOPRIGHT", 0, 8)
    scroll:EnableMouseWheel(true)
    WBF.UI.BindWheel(scroll)

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(400, 400)
    scroll:SetScrollChild(scrollChild)

    local bar = CreateFrame("Slider", nil, scroll)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(8)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -2)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 2)
    bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then
        bar:SetObeyStepOnDrag(true)
    end
    bar:SetMinMaxValues(0, 1)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3], 0.85)
    thumb:SetSize(8, 36)
    bar:SetThumbTexture(thumb)
    bar:Hide()
    bar:SetScript("OnValueChanged", function(self, value)
        if self.updating then
            return
        end
        scroll:SetVerticalScroll(value)
    end)

    local function MakeRoot()
        local child = CreateFrame("Frame", nil, scrollChild)
        child:SetSize(400, 40)
        child:Hide()
        return child
    end

    local dashboardRoot = MakeRoot()
    local activityRoot = MakeRoot()
    local charactersRoot = MakeRoot()
    local resourcesRoot = MakeRoot()
    local notebookRoot = MakeRoot()
    local huntsRoot = MakeRoot()
    local settingsRoot = MakeRoot()
    local detailRoot = MakeRoot()

    local resourcePanel = CreateFrame("Frame", nil, content, "BackdropTemplate")
    resourcePanel:SetWidth(292)
    resourcePanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    resourcePanel:SetPoint("BOTTOM", buttons, "TOP", 0, 8)
    resourcePanel:Hide()
    WBF.UI.Paint(resourcePanel, { 0.045, 0.05, 0.065, 0.98 }, WBF.UI.Colors.goldDim)

    WBF.UI.BindWheel(scrollChild)
    WBF.UI.BindWheel(dashboardRoot)
    WBF.UI.BindWheel(activityRoot)
    WBF.UI.BindWheel(charactersRoot)
    WBF.UI.BindWheel(resourcesRoot)
    WBF.UI.BindWheel(notebookRoot)
    WBF.UI.BindWheel(huntsRoot)
    WBF.UI.BindWheel(settingsRoot)
    WBF.UI.BindWheel(detailRoot)
    WBF.UI.BindWheel(resourcePanel)
    WBF.UI.Dashboard.Attach(dashboardRoot)
    WBF.UI.Activity.Attach(activityRoot)
    WBF.UI.CharactersView.Attach(charactersRoot)
    WBF.UI.Resources.Attach(resourcesRoot, resourcePanel)
    WBF.UI.Notebook.Attach(notebookRoot)
    WBF.UI.CollectionHunts.Attach(huntsRoot)
    WBF.UI.Settings.Attach(settingsRoot)
    WBF.UI.Detail.Attach(detailRoot)
    WBF.UI.ResourceDetail.Attach(detailRoot)
    WBF.UI.GoldDetail.Attach(detailRoot)
    WBF.UI.CharacterDetail.Attach(detailRoot)
    WBF.UI.PetBattlesView.Attach(detailRoot)
    if WBF.UI.Search and WBF.UI.Search.Attach then
        WBF.UI.Search.Attach(frame, header)
    end

    frame.detailStack = {}

    local function ShowRoot(active, height, width)
        local roots = { dashboardRoot, activityRoot, charactersRoot, resourcesRoot, notebookRoot, huntsRoot, settingsRoot, detailRoot }
        for index = 1, #roots do
            local item = roots[index]
            item:ClearAllPoints()
            if item == active then
                item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -4)
                item:SetWidth(width)
                item:SetHeight(math.max(height, 1))
                item:Show()
            else
                item:Hide()
            end
        end
        scrollChild:SetWidth(width + 28)
        scrollChild:SetHeight(math.max(height + 12, 1))
    end

    -- Detail renderers rebuild substantial parts of the shared UI. If one of
    -- them errors mid-render, pooled rows may already have been released and
    -- the user can be left looking at an apparently blank page. Keep reporting
    -- the original error to WoW/BugGrabber, but unwind the failed detail route
    -- and restore the previous screen on the next frame.
    local function RenderDetailSafely(owner, label, renderFn)
        local function OnError(err)
            local handler = geterrorhandler and geterrorhandler() or nil
            if type(handler) == "function" then
                handler(err)
            end
            return err
        end

        local ok, result = xpcall(renderFn, OnError)
        if ok then
            return true, result
        end

        if WBF.Database and WBF.Database.NoteMaintenanceStat then
            WBF.Database.NoteMaintenanceStat("detailRenderFailures", 1)
        end
        if WBF.Debug and WBF.Debug.Log then
            WBF.Debug.Log("Recovered failed detail render", tostring(label or "detail"))
        end

        if owner.detailStack and #owner.detailStack > 0 then
            table.remove(owner.detailStack)
        end

        if not owner.detailRecoveryPending then
            owner.detailRecoveryPending = true
            local function Recover()
                owner.detailRecoveryPending = false
                if owner:IsShown() then
                    owner:Refresh(true)
                end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, Recover)
            else
                Recover()
            end
        end
        return false, nil
    end

    function frame:Refresh(resetScroll)
        if not self:IsShown() then
            return
        end
        local base = content:GetWidth()
        if base < 240 then
            if not self.waitingForLayout then
                self.waitingForLayout = true
                C_Timer.After(0, function()
                    self.waitingForLayout = false
                    if self:IsShown() then
                        self:Refresh(resetScroll)
                    end
                end)
            end
            return
        end

        local view = self.view or "week"
        local top = self.detailStack and self.detailStack[#self.detailStack]
        local usePanel = not top and view == "resources" and (base - 28) >= 760
        WBF.UI.resourcePanelMode = usePanel
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        if usePanel then
            resourcePanel:Show()
            scroll:SetPoint("BOTTOMRIGHT", buttons, "TOPRIGHT", -304, 8)
        else
            resourcePanel:Hide()
            scroll:SetPoint("BOTTOMRIGHT", buttons, "TOPRIGHT", 0, 8)
        end
        local width = base - 28 - (usePanel and 304 or 0)
        if width < 200 then
            return
        end

        if resetScroll then
            scroll:SetVerticalScroll(0)
        end

        WBF.UI.Navigation.SetSelected(view)
        local height
        if top then
            local ok
            ok, height = RenderDetailSafely(self, top.category, function()
                local periodOffset = nil
                if top.context and top.context.period == "month" then
                    periodOffset = top.context.monthOffset or self.monthOffset or 0
                end
                if top.category == "resource" and WBF.Resources.Board and WBF.UI.ResourceDetail then
                    local startAt, endAt, label = WBF.Aggregator.Range(top.context.period or "week", periodOffset)
                    local closed = top.context.period == "month" and (periodOffset or 0) < 0
                    local model = WBF.Resources.Board(top.context.resourceKey, startAt, endAt, label, top.context.characterGUID, closed)
                    model.backLabel = WBF.Detail.BackLabel(self.detailStack)
                    return WBF.UI.ResourceDetail.Render(model, width, scroll:GetHeight())
                elseif top.category == "goldTrend" and WBF.UI.GoldDetail and WBF.GoldTracker then
                    local guid = top.context.characterGUID
                    local model
                    if top.context.period == "warband" then
                        model = WBF.GoldTracker.AllTimeTrend(guid)
                        model.periodTitle = "All Time"
                    else
                        local startAt, endAt, label = WBF.Aggregator.Range(top.context.period or "week", periodOffset)
                        model = WBF.GoldTracker.Trend(startAt, endAt, guid, label)
                        model.periodTitle = label
                    end
                    local character = guid and WBF.Characters and WBF.Characters.Get and WBF.Characters.Get(guid) or nil
                    model.displayTitle = character and ((character.name or "Character") .. " Gold") or "Warband Gold"
                    model.backLabel = WBF.Detail.BackLabel(self.detailStack)
                    return WBF.UI.GoldDetail.Render(model, width)
                elseif top.category == "character" and WBF.UI.CharacterDetail then
                    if WBF.UI.Detail.HideChrome then
                        WBF.UI.Detail.HideChrome()
                    end
                    if WBF.UI.ResourceDetail and WBF.UI.ResourceDetail.Hide then
                        WBF.UI.ResourceDetail.Hide()
                    end
                    if WBF.UI.GoldDetail and WBF.UI.GoldDetail.Hide then
                        WBF.UI.GoldDetail.Hide()
                    end
                    if WBF.UI.PetBattlesView and WBF.UI.PetBattlesView.Hide then
                        WBF.UI.PetBattlesView.Hide()
                    end
                    local summary = WBF.Aggregator.Build(top.context.period or "week", periodOffset)
                    return WBF.UI.CharacterDetail.Render(summary, top.context, width)
                elseif top.category == "petBattles" and WBF.UI.PetBattlesView then
                    if WBF.UI.Detail.HideChrome then
                        WBF.UI.Detail.HideChrome()
                    end
                    if WBF.UI.ResourceDetail and WBF.UI.ResourceDetail.Hide then
                        WBF.UI.ResourceDetail.Hide()
                    end
                    if WBF.UI.GoldDetail and WBF.UI.GoldDetail.Hide then
                        WBF.UI.GoldDetail.Hide()
                    end
                    if WBF.UI.CharacterDetail and WBF.UI.CharacterDetail.Hide then
                        WBF.UI.CharacterDetail.Hide()
                    end
                    local summary = WBF.Aggregator.Build(top.context.period or "week", periodOffset)
                    return WBF.UI.PetBattlesView.Render(summary, top.context, width)
                else
                    local model = WBF.Detail.Build(top.category, top.context)
                    model.backLabel = WBF.Detail.BackLabel(self.detailStack)
                    return WBF.UI.Detail.Render(model, width)
                end
            end)
            if not ok then
                return
            end
            ShowRoot(detailRoot, height or 40, width)
        elseif view == "settings" then
            WBF.UI.Settings.Refresh()
            height = WBF.UI.Settings.Height()
            ShowRoot(settingsRoot, height, width)
        elseif view == "characters" then
            height = WBF.UI.CharactersView.Render(width)
            ShowRoot(charactersRoot, height, width)
        elseif view == "resources" then
            height = WBF.UI.Resources.Render(width)
            ShowRoot(resourcesRoot, height, width)
        elseif view == "activity" then
            height = WBF.UI.Activity.Render(width)
            ShowRoot(activityRoot, height, width)
        elseif view == "hunts" then
            height = WBF.UI.CollectionHunts.Render(width)
            ShowRoot(huntsRoot, height, width)
        elseif view == "notebook" then
            height = WBF.UI.Notebook.Render(width)
            ShowRoot(notebookRoot, height, width)
        else
            local monthOffset = nil
            if view == "month" then
                monthOffset = self.monthOffset or 0
            end
            local summary = WBF.Aggregator.Build(view, monthOffset)
            height = WBF.UI.Dashboard.Render(summary, width)
            ShowRoot(dashboardRoot, height, width)
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if scroll:IsShown() then
                    UpdateScrollBar(scroll, bar)
                end
            end)
        else
            UpdateScrollBar(scroll, bar)
        end
    end

    function frame:SetView(id)
        self.detailStack = {}
        if id ~= "settings" then
            self.previousView = self.view
            WarbandFYI_DB.config.lastView = id
        end
        self.view = id
        if self:IsShown() then
            self:Refresh(true)
        end
    end

    function frame:OpenResource(resourceKey, period)
        local key = resourceKey
        if WBF.Resources and WBF.Resources.ResolveKey then
            key = WBF.Resources.ResolveKey(resourceKey) or resourceKey
        end
        if type(key) ~= "string" or key == "" or not (WBF.Resources and WBF.Resources.Get and WBF.Resources.Get(key)) then
            return false
        end
        local wanted = period
        if not PERIOD[wanted] then
            wanted = PERIOD[self.view] and self.view or "week"
        end
        -- "warband" is the dashboard's all-time aggregation scope. Feeding
        -- that synthetic range into the resource history/detail renderer can
        -- leave the dashboard stripped while the detail refresh aborts. A
        -- resource page already exposes lifetime totals separately, so use a
        -- normal bounded report window when opened from Warband.
        if wanted == "warband" then
            wanted = "week"
        end
        self:OpenDetail("resource", { resourceKey = key, period = wanted })
        return true
    end

    function frame:OpenDetail(category, extra)
        extra = extra or {}
        if WBF.Detail and WBF.Detail.CanOpen and not WBF.Detail.CanOpen(category) then
            if WBF.Database and WBF.Database.NoteMaintenanceStat then
                WBF.Database.NoteMaintenanceStat("invalidRoutesBlocked", 1)
            end
            if WBF.Debug and WBF.Debug.Log then
                WBF.Debug.Log("Blocked invalid detail route", tostring(category))
            end
            return false
        end
        local period = extra.period
        if not PERIOD[period] then
            if PERIOD[self.view] then
                period = self.view
            else
                period = "warband"
            end
        end
        -- Resource rows can also be opened through generic activity/detail
        -- navigation. Keep those off the Warband aggregate for the same reason
        -- as OpenResource above.
        if category == "resource" and period == "warband" then
            period = "week"
        end
        if not self.detailStack then
            self.detailStack = {}
        end
        local origin
        if #self.detailStack == 0 then
            local label = WBF.UI.Navigation and WBF.UI.Navigation.LabelFor and WBF.UI.Navigation.LabelFor(self.view, self.monthOffset) or "WarbandFYI"
            origin = {
                view = self.view,
                monthOffset = self.monthOffset,
                scroll = scroll:GetVerticalScroll(),
                label = label,
            }
        end
        local guid = extra.characterGUID
        if guid == nil and not extra.warband then
            local parent = self.detailStack[#self.detailStack]
            if parent and parent.context then
                guid = parent.context.characterGUID
            end
        end
        if extra.warband then
            guid = nil
        end
        local reputationFaction = extra.reputationFaction
        if category == "reputationFaction" and reputationFaction == nil then
            local parent = self.detailStack[#self.detailStack]
            if parent and parent.context then
                reputationFaction = parent.context.reputationFaction
            end
        end
        local resourceKey = extra.resourceKey
        if category == "resource" and resourceKey == nil then
            local parent = self.detailStack[#self.detailStack]
            if parent and parent.context then
                resourceKey = parent.context.resourceKey
            end
        end
        if category == "resource" then
            if WBF.Resources and WBF.Resources.ResolveKey then
                resourceKey = WBF.Resources.ResolveKey(resourceKey) or resourceKey
            end
            if type(resourceKey) ~= "string" or resourceKey == "" or not (WBF.Resources and WBF.Resources.Get and WBF.Resources.Get(resourceKey)) then
                return false
            end
        end
        local detailValue = extra.detailValue
        local detailId = extra.detailId
        local monthOffset = nil
        if period == "month" then
            if type(extra.monthOffset) == "number" then
                monthOffset = extra.monthOffset
            else
                monthOffset = self.monthOffset or 0
            end
        end
        local current = self.detailStack[#self.detailStack]
        if current and current.category == category and current.context.period == period and current.context.characterGUID == guid and current.context.resourceKey == resourceKey and current.context.reputationFaction == reputationFaction and current.context.detailValue == detailValue and current.context.detailId == detailId and current.context.monthOffset == monthOffset then
            if extra.tab and current.context.tab ~= extra.tab then
                current.context.tab = extra.tab
                if self:IsShown() then
                    self:Refresh(false)
                end
            end
            return
        end
        self.detailStack[#self.detailStack + 1] = {
            category = category,
            origin = origin,
            context = {
                period = period,
                characterGUID = guid,
                resourceKey = category == "resource" and resourceKey or nil,
                reputationFaction = category == "reputationFaction" and reputationFaction or nil,
                detailValue = detailValue,
                detailId = detailId,
                tab = extra.tab,
                monthOffset = monthOffset,
            },
        }
        if self:IsShown() then
            self:Refresh(true)
        else
            self:Show()
        end
        return true
    end

    function frame:SetCharacterTab(tab)
        local top = self.detailStack and self.detailStack[#self.detailStack]
        if not top then
            return
        end
        top.context.tab = tab
        if self:IsShown() then
            self:Refresh(false)
        end
    end

    function frame:BackDetail()
        if not self.detailStack or #self.detailStack == 0 then
            return
        end
        local rootOrigin = self.detailStack[1] and self.detailStack[1].origin or nil
        table.remove(self.detailStack)
        if #self.detailStack == 0 and rootOrigin then
            self.view = rootOrigin.view or self.view
            self.monthOffset = rootOrigin.monthOffset
        end
        if self:IsShown() then
            self:Refresh(true)
            if #self.detailStack == 0 and rootOrigin and type(rootOrigin.scroll) == "number" and C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if frame:IsShown() and (not frame.detailStack or #frame.detailStack == 0) then
                        local range = scroll:GetVerticalScrollRange() or 0
                        scroll:SetVerticalScroll(math.min(math.max(rootOrigin.scroll, 0), range))
                        UpdateScrollBar(scroll, bar)
                    end
                end)
            end
        end
    end

    function frame:ShowActivityFor(guid)
        WBF.UI.characterFilter = guid
        self:SetView("activity")
        if not self:IsShown() then
            self:Show()
        end
    end

    function frame:NudgeMonth(delta)
        if self.view ~= "month" or type(delta) ~= "number" or not WBF.Time.AddMonths or not WBF.MonthHistory or not WBF.MonthHistory.CanSelect then
            return
        end
        local offset = (self.monthOffset or 0) + delta
        if offset > 0 then
            return
        end
        local year, month = WBF.Time.CurrentMonth()
        year, month = WBF.Time.AddMonths(year, month, offset)
        if not WBF.MonthHistory.CanSelect(year, month) then
            return
        end
        self.monthOffset = offset
        self.detailStack = {}
        if self:IsShown() then
            self:Refresh(true)
        end
    end

    function frame:Toggle()
        if self:IsShown() then
            self:Hide()
        else
            self:Show()
        end
    end

    sessionButton:SetScript("OnClick", function()
        frame:SetView("current")
    end)
    warbandButton:SetScript("OnClick", function()
        frame:SetView("warband")
    end)
    settingsButton:SetScript("OnClick", function()
        if frame.view == "settings" then
            frame:SetView(frame.previousView or "week")
        else
            frame.previousView = frame.view
            frame:SetView("settings")
        end
    end)

    WBF.UI.Navigation.Build(nav, function(id)
        if id == "activity" then
            WBF.UI.characterFilter = nil
        end
        frame:SetView(id)
    end)

    WBF.UI.ScrollWheel = function(delta)
        local range = scroll:GetVerticalScrollRange()
        local current = scroll:GetVerticalScroll()
        local nextValue = math.min(range, math.max(0, current - delta * 36))
        scroll:SetVerticalScroll(nextValue)
        UpdateScrollBar(scroll, bar)
    end

    -- Used by views such as Notebook when navigating to a specific result/FYI
    -- source.  Apply again on the next frame because ScrollFrame range can
    -- settle only after the child has been laid out.
    WBF.UI.ScrollToContent = function(value)
        local wanted = math.max(0, tonumber(value) or 0)
        local function apply()
            if not scroll or not scroll:IsShown() then
                return
            end
            local range = scroll:GetVerticalScrollRange()
            scroll:SetVerticalScroll(math.min(range, wanted))
            UpdateScrollBar(scroll, bar)
        end
        apply()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, apply)
        end
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        WBF.Database.SaveWindow(frame)
    end)

    frame:SetScript("OnSizeChanged", function(self)
        if self.applyingSize or self:GetWidth() < 100 then
            return
        end
        self.reflowGen = (self.reflowGen or 0) + 1
        local generation = self.reflowGen
        C_Timer.After(0.12, function()
            if self.reflowGen ~= generation then
                return
            end
            if self:IsShown() then
                WBF.Database.SaveWindow(self)
                self:Refresh(false)
            end
        end)
    end)

    frame.playTick = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.playTick = (self.playTick or 0) + (elapsed or 0)
        if self.playTick < 1 then
            return
        end
        self.playTick = 0
        if not WBF.UI.Dashboard.TickLivePlay then
            return
        end
        if self.detailStack and #self.detailStack > 0 then
            return
        end
        local view = self.view
        if view == "settings" or view == "characters" or view == "resources" or view == "activity" or view == "notebook" then
            return
        end
        WBF.UI.Dashboard.TickLivePlay()
    end)

    frame:SetScript("OnShow", function(self)
        self.monthOffset = 0
        local top = self.detailStack and self.detailStack[#self.detailStack]
        if top and top.context and top.context.period == "month" and (top.context.monthOffset or 0) ~= 0 then
            self.detailStack = {}
        end
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN and PlaySound then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        end
        self:Refresh(true)
    end)
    frame:SetScript("OnHide", function()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE and PlaySound then
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        end
        GameTooltip:Hide()
        if WBF.UI.Search and WBF.UI.Search.Hide then
            WBF.UI.Search.Hide()
        end
        if WBF.UI.HideCollectionPreview then
            WBF.UI.HideCollectionPreview()
        end
    end)

    local listed = false
    for index = 1, #UISpecialFrames do
        if UISpecialFrames[index] == "WarbandFYIFrame" then
            listed = true
            break
        end
    end
    if not listed then
        table.insert(UISpecialFrames, "WarbandFYIFrame")
    end

    WBF.UI.frame = frame
    return frame
end
