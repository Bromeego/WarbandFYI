local _, WBF = ...

-- One reference sheet. It points at a page or a section. The rows stay
-- in the notebook. Reload keeps the window chrome and leaves the sheet closed.
WBF.NotebookSheet = {}

local MIN_WIDTH = 300
local MIN_HEIGHT = 240
local MAX_WIDTH = 900
local MAX_HEIGHT = 800
local DEFAULT_WIDTH = 420
local DEFAULT_HEIGHT = 520
local SCALES = { 0.8, 0.9, 1, 1.1, 1.25 }
local OPACITIES = { 1, 0.9, 0.75, 0.6 }
local POINTS = {
    CENTER = true,
    TOP = true,
    BOTTOM = true,
    LEFT = true,
    RIGHT = true,
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}

local target = nil

local function Clamp(value, low, high, fallback)
    local number = tonumber(value)
    if not number or number ~= number then
        return fallback
    end
    if number < low then
        return low
    end
    if number > high then
        return high
    end
    return number
end

local function Snap(value, list, fallback)
    local number = tonumber(value)
    if not number or number ~= number then
        return fallback
    end
    local best = fallback
    local gap = math.huge
    for index = 1, #list do
        local distance = math.abs(list[index] - number)
        if distance < gap then
            best = list[index]
            gap = distance
        end
    end
    return best
end

local function Config()
    if not WBF.Database or not WBF.Database.Get then
        return nil
    end
    local db = WBF.Database.Get()
    if type(db) ~= "table" then
        return nil
    end
    if type(db.config) ~= "table" then
        db.config = {}
    end
    return db.config
end

function WBF.NotebookSheet.Settings()
    local config = Config()
    if not config then
        return nil
    end
    if type(config.notebookSheet) ~= "table" then
        config.notebookSheet = {}
    end
    local saved = config.notebookSheet
    saved.width = Clamp(saved.width, MIN_WIDTH, MAX_WIDTH, DEFAULT_WIDTH)
    saved.height = Clamp(saved.height, MIN_HEIGHT, MAX_HEIGHT, DEFAULT_HEIGHT)
    saved.scale = Snap(saved.scale, SCALES, 1)
    saved.opacity = Snap(saved.opacity, OPACITIES, 1)
    saved.locked = saved.locked and true or false
    saved.hideCompleted = saved.hideCompleted and true or false
    if type(saved.point) ~= "string" or not POINTS[saved.point] then
        saved.point = nil
    end
    if type(saved.relPoint) ~= "string" or not POINTS[saved.relPoint] then
        saved.relPoint = saved.point
    end
    saved.x = Clamp(saved.x, -4000, 4000, 0)
    saved.y = Clamp(saved.y, -4000, 4000, 0)
    saved.open = nil
    saved.pageId = nil
    saved.sectionId = nil
    saved.pages = nil
    saved.blocks = nil
    return saved
end

function WBF.NotebookSheet.Update(partial)
    local saved = WBF.NotebookSheet.Settings()
    if not saved or type(partial) ~= "table" then
        return saved
    end
    if partial.width ~= nil then
        saved.width = partial.width
    end
    if partial.height ~= nil then
        saved.height = partial.height
    end
    if partial.scale ~= nil then
        saved.scale = partial.scale
    end
    if partial.opacity ~= nil then
        saved.opacity = partial.opacity
    end
    if partial.locked ~= nil then
        saved.locked = partial.locked and true or false
    end
    if partial.hideCompleted ~= nil then
        saved.hideCompleted = partial.hideCompleted and true or false
    end
    if partial.point ~= nil then
        saved.point = partial.point
    end
    if partial.relPoint ~= nil then
        saved.relPoint = partial.relPoint
    end
    if partial.x ~= nil then
        saved.x = partial.x
    end
    if partial.y ~= nil then
        saved.y = partial.y
    end
    return WBF.NotebookSheet.Settings()
end

function WBF.NotebookSheet.Cycle(field, direction)
    local saved = WBF.NotebookSheet.Settings()
    if not saved then
        return nil
    end
    local list = field == "opacity" and OPACITIES or SCALES
    local key = field == "opacity" and "opacity" or "scale"
    local current = saved[key]
    local index = 1
    for cursor = 1, #list do
        if list[cursor] == current then
            index = cursor
            break
        end
    end
    direction = tonumber(direction) or 1
    if direction >= 0 then
        direction = 1
    else
        direction = -1
    end
    index = index + direction
    if index > #list then
        index = 1
    elseif index < 1 then
        index = #list
    end
    saved[key] = list[index]
    return WBF.NotebookSheet.Settings()
end

function WBF.NotebookSheet.Toggle(field)
    local saved = WBF.NotebookSheet.Settings()
    if not saved then
        return nil
    end
    if field == "locked" then
        saved.locked = not saved.locked
    elseif field == "hideCompleted" then
        saved.hideCompleted = not saved.hideCompleted
    end
    return WBF.NotebookSheet.Settings()
end

function WBF.NotebookSheet.OnLoad()
    target = nil
end

function WBF.NotebookSheet.Close()
    target = nil
end

function WBF.NotebookSheet.IsOpen()
    return target ~= nil
end

function WBF.NotebookSheet.Open(spec)
    if type(spec) ~= "table" or not WBF.Notebook then
        return nil
    end
    if spec.kind == "page" then
        local page = WBF.Notebook.GetPage(spec.pageId)
        if not page then
            return nil
        end
        target = { kind = "page", pageId = page.id }
        return target
    end
    if spec.kind == "section" then
        local section = WBF.Notebook.GetSection(spec.sectionId)
        local page = section and WBF.Notebook.GetPage(section.pageId) or nil
        if not section or not page then
            return nil
        end
        target = { kind = "section", sectionId = section.id, pageId = page.id }
        return target
    end
    return nil
end

function WBF.NotebookSheet.View()
    if not target or not WBF.Notebook then
        target = nil
        return nil
    end
    if target.kind == "page" then
        local page = WBF.Notebook.GetPage(target.pageId)
        if not page then
            target = nil
            return nil
        end
        return {
            kind = "page",
            page = page,
            sections = WBF.Notebook.Sections(page.id),
        }
    end
    local section = WBF.Notebook.GetSection(target.sectionId)
    local page = section and WBF.Notebook.GetPage(section.pageId) or nil
    if not section or not page then
        target = nil
        return nil
    end
    return {
        kind = "section",
        page = page,
        sections = { section },
    }
end

function WBF.NotebookSheet.Columns(width)
    if (tonumber(width) or 0) >= 460 then
        return 2
    end
    return 1
end

function WBF.NotebookSheet.ChromeLabel(kind, value)
    local percent = math.floor(((tonumber(value) or 1) * 100) + 0.5)
    if kind == "opacity" then
        return "Opacity " .. percent .. "%"
    end
    return "Scale " .. percent .. "%"
end

function WBF.NotebookSheet.FullWidth(block, columns)
    if (tonumber(columns) or 1) < 2 then
        return true
    end
    return type(block) == "table" and (block.type == "checklist" or block.type == "pet_level_list")
end

function WBF.NotebookSheet.VisibleItems(block)
    local items = type(block) == "table" and block.items or nil
    local list = {}
    if type(items) ~= "table" then
        return list
    end
    local settings = WBF.NotebookSheet.Settings()
    local hide = settings and settings.hideCompleted
    for index = 1, #items do
        local item = items[index]
        if type(item) == "table" and (not hide or not item.done) then
            list[#list + 1] = item
        end
    end
    return list
end

function WBF.NotebookSheet.AchievementDetail(progress, expanded)
    if not WBF.PlanAchievements or not WBF.PlanAchievements.CriteriaDetail then
        return nil
    end
    return WBF.PlanAchievements.CriteriaDetail(progress, expanded)
end

function WBF.NotebookSheet.Use(block)
    if type(block) ~= "table" or block.type ~= "waypoint" then
        return false
    end
    if not WBF.NotebookSmart or not WBF.NotebookSmart.Track then
        return false
    end
    return WBF.NotebookSmart.Track(block) and true or false
end
