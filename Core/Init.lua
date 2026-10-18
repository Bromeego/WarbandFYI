local addonName, WBF = ...

WBF.VERSION = "0.2.0-dev.2c"
WarbandFYI = WBF

local frame = CreateFrame("Frame")
local handlers = {}
local started = false
local loggedIn = false

local function Dispatch(event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    for index = 1, #list do
        list[index](...)
    end
end

local bus = {}

function bus:On(event, callback)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    local list = handlers[event]
    list[#list + 1] = callback
end

local function OnLogin()
    if loggedIn then
        return
    end
    loggedIn = true
    WBF.Characters.Update()
    WBF.Sessions.HandleLogin()
    WBF.CharacterTrack.Capture("login")
    WBF.Instances.HandleEnteringWorld()
    WBF.CollectionHunts.OnLogin()
    WBF.Professions.Arm()

    if not WarbandFYI_DB.config.welcomed then
        WarbandFYI_DB.config.welcomed = true
        print("|cffd4af37WarbandFYI|r loaded. Type /wbfyi to see what your Warband has been up to.")
    end

    if not WBF.ticker and C_Timer and C_Timer.NewTicker then
        WBF.ticker = C_Timer.NewTicker(15, function()
            if not WBF.Database.IsReady() or not UnitExists("player") then
                return
            end
            if WBF.MonthHistory and WBF.MonthHistory.OnClock then
                WBF.MonthHistory.OnClock()
            end
            WBF.Characters.Update()
            if WBF.Sessions.PlayerIsAFK() then
                WBF.Sessions.CloseIfTimedOut()
            else
                WBF.Sessions.Touch()
                WBF.CharacterTrack.Capture("tick")
                WBF.Delves.Refresh()
                WBF.Prey.Refresh()
                if WBF.Reputation.Scan then
                    WBF.Reputation.Scan()
                end
                if WBF.Resources.RefreshBalances then
                    WBF.Resources.RefreshBalances()
                else
                    WBF.Resources.Refresh()
                end
                WBF.Professions.Scan()
            end
            if WBF.UI.RequestRefresh then
                WBF.UI.RequestRefresh()
            end
        end)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(1.5, function()
            if not UnitExists("player") then
                return
            end
            WBF.Characters.Update()
            local session = WBF.Sessions.GetActive()
            if session then
                WBF.Sessions.BeginSegment(session, WBF.Characters.GetGuid(), WBF.Time.Now())
            end
            WBF.CharacterTrack.Capture("login-delay")
            if WBF.Instances.Settle then
                WBF.Instances.Settle()
            end
            WBF.Instances.HandleEnteringWorld()
            WBF.Delves.Refresh()
            if WBF.Prey.AllowStaleClose then
                WBF.Prey.AllowStaleClose()
            end
            WBF.Prey.Refresh()
            if WBF.Reputation.BeginSettle then
                WBF.Reputation.BeginSettle()
            end
            if WBF.Reputation.Scan then
                WBF.Reputation.Scan()
            end
            if WBF.Resources.RefreshBalances then
                WBF.Resources.RefreshBalances()
            else
                WBF.Resources.Refresh()
            end
            WBF.Professions.Scan()
        end)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(8, function()
            if not UnitExists("player") then
                return
            end
            if WBF.Reputation.Scan then
                WBF.Reputation.Scan()
            end
            if WBF.Resources.QueueFullScan then
                WBF.Resources.QueueFullScan()
            end
        end)
    end
end

local function OnLogout()
    if not WBF.Database.IsReady() then
        return
    end
    if UnitExists("player") then
        WBF.Characters.Update()
        WBF.CharacterTrack.Capture("logout")
    end
    WBF.Sessions.HandleLogout()
end

local function Startup()
    if started then
        return
    end
    started = true
    WBF.Database.Init()
    WBF.NotebookPets.Register(bus)
    WBF.CharacterTrack.Register(bus)
    WBF.Economy.Register(bus)
    WBF.Instances.Register(bus)
    WBF.CollectionHunts.Register(bus)
    WBF.Prey.Register(bus)
    WBF.QuestVisibility.Register(bus)
    WBF.Quests.Register(bus)
    WBF.Achievements.Register(bus)
    if WBF.PlanAchievements and WBF.PlanAchievements.Register then
        WBF.PlanAchievements.Register(bus)
    end
    if WBF.NotebookSmart and WBF.NotebookSmart.Register then
        WBF.NotebookSmart.Register(bus)
    end
    if WBF.NotebookFyi and WBF.NotebookFyi.Register then
        WBF.NotebookFyi.Register(bus)
    end
    if WBF.ContextFyi and WBF.ContextFyi.Register then
        WBF.ContextFyi.Register(bus)
    end
    WBF.Collections.Register(bus)
    WBF.Housing.Register(bus)
    WBF.PetBattles.Register(bus)
    WBF.Reputation.Register(bus)
    WBF.Delves.Register(bus)
    WBF.Professions.Register(bus)
    if WBF.Crafts and WBF.Crafts.Register then
        WBF.Crafts.Register(bus)
    end
    WBF.WorldActivity.Register(bus)
    WBF.Resources.RegisterBus(bus)
    WBF.UI.MainWindow.Create()
    if IsLoggedIn and IsLoggedIn() then
        OnLogin()
    end
end

function WBF.UI.RequestRefresh()
    local window = WBF.UI.frame
    if not window or not window:IsShown() then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        WBF.UI.pendingRefresh = true
        return
    end
    if WBF.UI.refreshQueued then
        return
    end
    WBF.UI.refreshQueued = true
    C_Timer.After(0.15, function()
        WBF.UI.refreshQueued = false
        if window:IsShown() then
            window:Refresh(false)
        end
    end)
end

local function Slash(message)
    if not WBF.Database.IsReady() then
        print("|cffd4af37WarbandFYI|r is still loading.")
        return
    end
    local raw = strtrim(message or "")
    if WBF.Notebook and WBF.Notebook.HandleSlash(raw) then
        return
    end
    if WBF.CollectionHunts and WBF.CollectionHunts.Slash(raw) then return end
    local text = raw:lower()
    local searchText
    if raw:match("^[Ss]earch$") then
        searchText = ""
    else
        searchText = raw:match("^[Ss]earch%s+(.*)$")
    end
    if searchText and WBF.UI and WBF.UI.Search and WBF.UI.Search.Focus then
        if WBF.UI.frame and not WBF.UI.frame:IsShown() then
            WBF.UI.frame:Show()
        end
        WBF.UI.Search.Focus(strtrim(searchText or ""))
        return
    end
    local db = WBF.Database.Get()
    local simulated = raw:match("^[Dd]ebug%s+[Ss]imulateevent%s*(.*)$")
    if simulated and WBF.EventTriggers and WBF.EventTriggers.Simulate then
        simulated = (simulated:gsub("^%s+", ""):gsub("%s+$", ""))
        local quoted = simulated:match('^"(.*)"$') or simulated:match("^'(.*)'$")
        if quoted then
            simulated = quoted
        end
        if simulated == "" then
            print("|cffd4af37WarbandFYI|r Usage: /wbfyi debug simulateevent \"Darkmoon Faire\"  |  /wbfyi debug simulateevent off")
            return
        end
        local info = WBF.EventTriggers.Simulate(simulated)
        if info == nil then
            print("|cffd4af37WarbandFYI|r no catalog event matches that name.")
        elseif info then
            print("|cffd4af37WarbandFYI|r simulating " .. info.name .. ". This does not change the calendar.")
        else
            print("|cffd4af37WarbandFYI|r event simulation off.")
        end
        return
    end
    if text == "fyi" or text == "fyis" then
        if WBF.UI and WBF.UI.Fyi and WBF.UI.Fyi.ShowActiveEvents and WBF.UI.Fyi.ShowActiveEvents(true) then
            return
        end
        print("|cffd4af37WarbandFYI|r no active event FYIs to show right now.")
        return
    elseif text == "debug resources" then
        if WBF.Resources.DebugDump then
            WBF.Resources.DebugDump()
        end
    elseif text == "debug renown" then
        if WBF.Reputation.DebugDump then
            WBF.Reputation.DebugDump()
        end
    elseif text == "debug events" then
        if WBF.EventTriggers and WBF.EventTriggers.Debug then
            WBF.EventTriggers.Debug()
        end
    elseif text == "debug fyis" then
        if WBF.ContextFyi and WBF.ContextFyi.Debug then
            WBF.ContextFyi.Debug()
        end
    elseif text == "debug gathering" or text == "debug fishing" or text == "debug rares" then
        if WBF.WorldActivity.Debug then
            WBF.WorldActivity.Debug(text:match("^debug%s+(.+)$"))
        end
    elseif text == "debug" then
        db.config.debug = not db.config.debug
        print("|cffd4af37WarbandFYI|r debug", db.config.debug and "on" or "off")
        if WBF.UI.Settings.Refresh then
            WBF.UI.Settings.Refresh()
        end
    elseif text == "sample" then
        WBF.Sample.Load(false)
        WBF.UI.RequestRefresh()
    elseif text == "sample force" then
        WBF.Sample.Load(true)
        WBF.UI.RequestRefresh()
    elseif text == "clearsample" then
        WBF.Database.ClearSample()
        print("|cffd4af37WarbandFYI|r removed sample history.")
        WBF.UI.RequestRefresh()
    elseif text == "reset" then
        db.config.window = nil
        local window = WBF.UI.frame
        if window then
            window.applyingSize = true
            window:ClearAllPoints()
            window:SetPoint("CENTER")
            window:SetSize(1040, 680)
            window.applyingSize = false
        end
        print("|cffd4af37WarbandFYI|r window position reset.")
    elseif text == "status" then
        local session = WBF.Sessions.GetActive()
        if session then
            print("|cffd4af37WarbandFYI|r session", session.id, "active since", WBF.Time.Clock(session.startedAt))
        else
            print("|cffd4af37WarbandFYI|r no active session.")
        end
        local characters = #WBF.Characters.List()
        print("|cffd4af37WarbandFYI|r", #db.events, "events,", #db.snapshots, "snapshots,", characters, "characters.")
    elseif text:match("^resetresource%s+") then
        local name = text:match("^resetresource%s+(.+)$")
        local definition, matches = WBF.Resources.Find(name)
        if not definition then
            if type(matches) == "table" and #matches > 1 then
                print("|cffd4af37WarbandFYI|r more than one resource matches that name.")
            else
                print("|cffd4af37WarbandFYI|r no resource matches that name.")
            end
            return
        end
        WBF.Resources.ResetHistory(definition.key)
        print("|cffd4af37WarbandFYI|r cleared tracking history for " .. definition.name .. ". The next observation starts a new baseline.")
        WBF.UI.RequestRefresh()
    elseif text == "help" then
        print("|cffd4af37WarbandFYI|r /wbfyi | /wbfyi fyi | /wbfyi debug | /wbfyi debug resources | /wbfyi debug renown | /wbfyi debug gathering | /wbfyi debug fishing | /wbfyi debug rares | /wbfyi sample | /wbfyi clearsample | /wbfyi reset | /wbfyi resetresource <name> | /wbfyi status")
        print("|cffd4af37WarbandFYI|r /wbfyi search <text> | /wbfyi note <text> | /wbfyi notebook | /wbfyi hunt list | /wbfyi debug notebook | /wbfyi debug events | /wbfyi debug fyis | /wbfyi debug simulateevent \"Darkmoon Faire\"")
    elseif text == "hide" then
        if WBF.UI.frame then
            WBF.UI.frame:Hide()
        end
    else
        if WBF.UI.frame then
            WBF.UI.frame:Toggle()
        end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName then
            return
        end
        Startup()
        return
    end
    if event == "PLAYER_LOGIN" then
        if not started then
            Startup()
        end
        OnLogin()
        return
    end
    if event == "PLAYER_LOGOUT" then
        OnLogout()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if WBF.Resources and WBF.Resources.Resume then
            WBF.Resources.Resume()
        end
        if WBF.WorldActivity and WBF.WorldActivity.OnRegen then
            WBF.WorldActivity.OnRegen()
        end
        if WBF.NotebookFyi and WBF.NotebookFyi.OnRegen then
            WBF.NotebookFyi.OnRegen()
        end
        if WBF.ContextFyi and WBF.ContextFyi.OnRegen then
            WBF.ContextFyi.OnRegen()
        end
        if WBF.UI.pendingRefresh and WBF.UI.RequestRefresh then
            WBF.UI.pendingRefresh = false
            WBF.UI.RequestRefresh()
        end
        return
    end
    if not WBF.Database.IsReady() then
        return
    end
    Dispatch(event, ...)
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

SLASH_WARBANDFYI1 = "/wbfyi"
SLASH_WARBANDFYI2 = "/warbandfyi"
SlashCmdList.WARBANDFYI = Slash
