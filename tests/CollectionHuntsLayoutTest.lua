-- The Collection Hunts detail column stacks without overlaps in every view.
-- Run from the repo root:
--   lua tests/CollectionHuntsLayoutTest.lua

local script = arg and arg[0] or "tests/CollectionHuntsLayoutTest.lua"
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

-- Frame double that remembers where it was placed and how big it is.
local function double(width, height)
    local f = { shown = true, x = 0, y = 0, width = width or 0, height = height or 14, text = "", scripts = {} }
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetShown(shown) self.shown = shown and true or false end
    function f:SetPoint(_, a, b, c, d)
        -- Place() uses SetPoint("TOPLEFT", x, -y).
        if type(a) == "number" then
            self.x, self.y = a, -b
        elseif type(c) == "number" then
            self.x, self.y = c, -d
        end
    end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:GetHeight() return self.height end
    function f:GetStringHeight() return 14 end
    function f:SetText(text) self.text = text or "" end
    function f:GetText() return self.text end
    function f:SetScript(event, callback)
        self.scripts[event] = callback
    end
    function f:Click()
        if self.scripts.OnClick then
            self.scripts.OnClick(self)
        end
    end
    function f:CreateTexture() return double(0, 0) end
    function f:CreateFontString() return double(0, 14) end
    return setmetatable(f, { __index = function() return function() end end })
end

CreateFrame = function() return double() end
local page = double(600, 0)

local WBF = {}
WBF.UI = {
    Colors = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
    Hex = function() return "|cffffffff" end,
    Tooltip = function() end,
    AddTip = function() end,
    Button = function(_, text, width, height)
        local b = double(width or 100, height or 22)
        b.text = text or ""
        return b
    end,
    EditBox = function(_, width, height) return double(width or 120, height or 22) end,
    EmptyState = function()
        local e = double(0, 0)
        function e:Set() return self end
        function e:Layout(width)
            self.width, self.height = width, 90
            return 90
        end
        return e
    end,
}

local catalog = {
    drake = { title = "Drake of the South Wind", instance = "Throne of the Four Winds", boss = "Al'Akir",
        defaultGoal = "mount", sourceKey = "alakir" },
    reins = { title = "Invincible's Reins", instance = "Icecrown Citadel", boss = "The Lich King",
        defaultGoal = "mount", sourceKey = "lichking" },
}
local ordered = { "drake", "reins" }
local completion = {}
local settings = {}
local statuses = {}
local characters = {}
for index = 1, 6 do
    local guid = "Player-" .. index
    characters[index] = { guid = guid, name = "Alt" .. index, realm = "Realm" }
    statuses[guid] = index <= 2 and "available" or index == 3 and "done" or "unknown"
end

WBF.CollectionHunts = {
    Catalog = function() return catalog, ordered end,
    IsHidden = function() return false end,
    Completion = function(key)
        if completion[key] then
            return true, completion[key]
        end
        return false
    end,
    IsEnabled = function() return true end,
    Settings = function(key)
        settings[key] = settings[key] or { goal = "mount", characterMode = "selected", selected = {} }
        return settings[key]
    end,
    Source = function() return { daily = false, instance = "Raid", boss = "Boss" } end,
    Status = function(_, guid) return statuses[guid] end,
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
    KnownSource = function() return nil end,
    FindMounts = function()
        return { { id = 1, name = "Drake" }, { id = 2, name = "Reins", collected = true } }
    end,
    Sources = function() return {} end,
}
WBF.Characters = { List = function() return characters end }

local chunk = assert(loadfile(root .. "/UI/CollectionHunts.lua"))
chunk("WarbandFYI", WBF)
local Page = WBF.UI.CollectionHunts
Page.Attach(page)
local controls = page.controls

local function shownRightColumn()
    local list = {}
    local function add(name, widget)
        if widget and widget.shown and widget.x >= 285 then
            list[#list + 1] = { name = name, widget = widget }
        end
    end
    for name, widget in pairs(controls) do
        if type(widget) == "table" and widget.shown ~= nil then
            add(name, widget)
        end
    end
    for _, group in ipairs({ "CharButtons", "AttemptHeadings", "MountResults" }) do
        for index, widget in ipairs(controls[group] or {}) do
            add(group .. index, widget)
        end
    end
    return list
end

-- The icon border is a 1px line that sits on the icon's top edge by design.
local OVERLAY_PAIRS = { TargetIcon = "TargetIconBorder" }

local function overlaps()
    local items = shownRightColumn()
    local found = {}
    for i = 1, #items do
        for j = i + 1, #items do
            local a, b = items[i], items[j]
            local paired = OVERLAY_PAIRS[a.name] == b.name or OVERLAY_PAIRS[b.name] == a.name
            local wa, wb = a.widget, b.widget
            local width_a = wa.width > 0 and wa.width or 100
            local width_b = wb.width > 0 and wb.width or 100
            local xOverlap = wa.x < wb.x + width_b and wb.x < wa.x + width_a
            local yOverlap = wa.y < wb.y + wb.height and wb.y < wa.y + wa.height
            if not paired and xOverlap and yOverlap then
                found[#found + 1] = a.name .. " / " .. b.name
            end
        end
    end
    table.sort(found)
    return found
end

local function render(name)
    local ok, err = pcall(Page.Render, 760)
    check(name .. " renders", ok, tostring(err))
    local found = overlaps()
    check(name .. " has no overlapping widgets", #found == 0, table.concat(found, ", "))
end

render("an active hunt")
check("the status heading sits below the farming-character controls",
    controls.StatusHeading.y > controls.EditCharacters.y)
check("character lists start below the status line",
    controls.AttemptHeadings[1].y > controls.StatusText.y)

controls.UnknownToggle:Click()
render("an active hunt with unverified characters shown")

controls.EditCharacters:Click()
render("an active hunt while editing characters")
controls.EditCharacters:Click()

controls.Remove:Click()
render("an active hunt confirming removal")
check("Cancel takes the third action slot while confirming", controls.CancelRemove.shown and not controls.Complete.shown)
controls.CancelRemove:Click()

completion.drake = "auto"
render("a completed hunt")
check("a completed hunt hides its settings", not controls.GoalLabel.shown and not controls.Mode.shown)

controls.CompletedSettings:Click()
render("a completed hunt with settings open")
check("settings follow the completed note", controls.GoalLabel.shown and controls.GoalLabel.y > controls.CompletedNote.y)
controls.CompletedSettings:Click()
completion.drake = nil

controls.NewHunt:Click()
render("the add form")
check("the add form shows the mount results", controls.MountResults[1].shown and controls.MountResults[2].shown)
controls.Back:Click()

catalog, ordered = {}, {}
render("no hunts")
check("the empty state shows when there are no hunts", controls.Empty and controls.Empty.shown)

if failures > 0 then
    error(failures .. " Collection Hunts layout test(s) failed")
end
print("All Collection Hunts layout tests passed")
