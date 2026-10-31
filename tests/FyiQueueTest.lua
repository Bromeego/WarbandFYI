-- The single FYI popup queues a second context instead of replacing the
-- first. Run from the repo root:
--   lua tests/FyiQueueTest.lua

local script = arg and arg[0] or "tests/FyiQueueTest.lua"
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

-- Generic frame double: Get*/Is* calls answer with something harmless, so the
-- popup can be built without the WoW client.
local function double()
    local f = { shown = true, scripts = {} }
    function f:Show()
        self.shown = true
    end
    function f:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then
            self.scripts.OnHide(self)
        end
    end
    function f:IsShown()
        return self.shown
    end
    function f:SetShown(shown)
        if shown then self:Show() else self:Hide() end
    end
    function f:SetScript(event, callback)
        self.scripts[event] = callback
    end
    function f:HookScript(event, callback)
        self.scripts[event] = callback
    end
    return setmetatable(f, { __index = function(_, key)
        if key:match("^Get.*Height$") or key:match("^Get.*Width$") or key:match("^Get.*Scroll") or key:match("^Get.*Range")
            or key:match("^Get.*Level$") or key:match("^Get.*Scale$") or key:match("^GetNum") or key == "GetLeft"
            or key == "GetRight" or key == "GetTop" or key == "GetBottom" then
            return function() return 0 end
        end
        if key:match("^Get") or key:match("^Create") then
            return function() return double() end
        end
        if key:match("^Is") or key:match("^Has") then
            return function() return false end
        end
        return function() end
    end })
end

local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function runTimers()
    local pending = timers
    timers = {}
    for index = 1, #pending do
        pending[index]()
    end
end
local combat = false
InCombatLockdown = function() return combat end
CreateFrame = function(_, name)
    local frame = double()
    if name then
        _G[name] = frame
    end
    return frame
end
UIParent = double()
GameTooltip = double()
UISpecialFrames = {}
WarbandFYI_DB = { config = {} }

local zone = 101
local WBF = {}
WBF.UI = setmetatable({
    Colors = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
}, { __index = function() return function() return double() end end })
WBF.NotebookFyi = {
    VisitZone = function() return zone end,
    ActiveEventGroup = function() return nil end,
    PopupLayout = function() return { shared = nil, pages = {}, pageCount = 0 } end,
    CardActions = function() return {} end,
}

local chunk = assert(loadfile(root .. "/UI/Fyi.lua"))
chunk("WarbandFYI", WBF)
local Fyi = WBF.UI.Fyi

local function group(contextType, title, extra)
    local g = {
        contextType = contextType,
        contextName = title,
        count = 1,
        entries = { { id = title, title = title, targetKind = "page", targetId = title } },
        ids = { title },
    }
    for key, value in pairs(extra or {}) do
        g[key] = value
    end
    return g
end

local ok, err = pcall(Fyi.Show, group("LOGIN", "Character reminders"))
check("login popup renders", ok, tostring(err))

-- The next show uses the same popup frame; find it through ShowQueued's guard.
local zoneGroup = group("ZONE", "Dornogal", { zoneMapID = 101, zoneName = "Dornogal" })
check("a zone FYI waits while the login FYI is open", Fyi.Show(zoneGroup) == true)
check("nothing is pulled from the queue while a popup is open", Fyi.ShowQueued() == false)

local popup = _G.WarbandFYIFyiPopup
check("the popup shows the login FYI", popup and popup:IsShown() and popup.contextType == "LOGIN")

-- Closing the login popup opens the queued zone popup after a short pause.
popup:Hide()
runTimers()
check("closing the login FYI opens the queued zone FYI", popup:IsShown() and popup.contextType == "ZONE")

-- A zone FYI that went stale while waiting is dropped.
popup:Hide()
runTimers()
Fyi.Show(group("LOGIN", "Character reminders"))
Fyi.Show(group("ZONE", "Azj-Kahet", { zoneMapID = 202, zoneName = "Azj-Kahet" }))
popup:Hide()
runTimers()
check("a queued FYI for a zone you have left is dropped", not popup:IsShown())

-- Combat queues the group; the end of combat shows it.
combat = true
check("an FYI raised in combat is not shown yet", Fyi.Show(group("LOGIN", "Character reminders")) == false)
check("the popup stays closed during combat", not popup:IsShown())
combat = false
check("the queued FYI opens after combat", Fyi.ShowQueued() == true and popup.contextType == "LOGIN")

-- The same context still refreshes in place rather than queueing.
check("a second login FYI replaces the first in place", Fyi.Show(group("LOGIN", "Character reminders")) == true
    and popup:IsShown())
popup:Hide()
runTimers()
check("no duplicate login FYI was queued", not popup:IsShown())

-- Collection Hunts joins whichever popup is open instead of queueing behind it.
popup:Hide()
runTimers()
local huntsBuilt = 0
local function huntsCard()
    huntsBuilt = huntsBuilt + 1
    return { title = "Available Collection Hunts", lines = { { text = "Drake of the South Wind" } }, openHunts = true }
end
check("nothing to attach to while no popup is open", Fyi.Attach("hunts", huntsCard) == false)
Fyi.Show(group("WOW_EVENT", "Active events"))
check("the hunts card joins the open events popup", Fyi.Attach("hunts", huntsCard) == true
    and popup.contextType == "WOW_EVENT" and popup.attachedKeys.hunts == true)
check("nothing is queued behind the events popup", Fyi.ShowQueued() == false)
local before = huntsBuilt
Fyi.Show(group("WOW_EVENT", "Active events"))
check("redrawing the popup rebuilds the hunts card", huntsBuilt > before and popup.attachedKeys.hunts == true)
popup:Hide()
runTimers()
Fyi.Show(group("ZONE", "Dornogal", { zoneMapID = 101, zoneName = "Dornogal" }))
check("closing the popup drops the hunts card", popup:IsShown() and not popup.attachedKeys.hunts)
popup:Hide()
runTimers()

check("a popup can hold only the hunts card", Fyi.Show({ contextType = "LOGIN", contextName = "Collection Hunts",
    entries = {}, ids = {}, attach = { hunts = huntsCard } }) == true and popup.attachedKeys.hunts == true)
check("an empty group without attached cards is not shown", (function()
    popup:Hide()
    runTimers()
    return Fyi.Show({ contextType = "LOGIN", entries = {}, ids = {} }) == false and not popup:IsShown()
end)())

if failures > 0 then
    error(failures .. " FYI queue test(s) failed")
end
print("All FYI queue tests passed")
