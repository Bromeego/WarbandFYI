local _, WBF = ...

-- Live achievement reads for reminders the player explicitly tracked.
-- Progress is never written into the saved variables.
WBF.PlanAchievements = {}

local metaCache = {}
local progressCache = {}
local lastQuery = nil
local SEARCH_LIMIT = 12

local function AchievementID(value)
    local id = tonumber(value)
    if not id or id ~= math.floor(id) or id < 1 then
        return nil
    end
    return id
end

function WBF.PlanAchievements.InvalidateProgress()
    progressCache = {}
end

function WBF.PlanAchievements.Available()
    if type(GetAchievementInfo) == "function" then
        return true
    end
    return type(C_AchievementInfo) == "table" and type(C_AchievementInfo.GetAchievementInfo) == "function"
end

local function ReadInfo(achievementID)
    if type(C_AchievementInfo) == "table" and type(C_AchievementInfo.GetAchievementInfo) == "function" then
        local result = WBF.Format.SafeCall(C_AchievementInfo.GetAchievementInfo, achievementID)
        if type(result) == "table" then
            local name = WBF.Format.PlainString(result.name)
            if name then
                return {
                    id = WBF.Format.AsNumber(result.achievementID or result.id) or achievementID,
                    name = name,
                    description = WBF.Format.PlainString(result.description),
                    points = WBF.Format.AsNumber(result.points),
                    icon = WBF.Format.AsNumber(result.icon),
                    isStatistic = result.isStatistic and true or false,
                }
            end
        end
    end
    if type(GetAchievementInfo) ~= "function" then
        return nil
    end
    local _, name, points, _, _, _, _, description, _, icon, _, _, _, _, isStatistic =
        WBF.Format.SafeCall(GetAchievementInfo, achievementID)
    name = WBF.Format.PlainString(name)
    if not name then
        return nil
    end
    return {
        id = achievementID,
        name = name,
        description = WBF.Format.PlainString(description),
        points = WBF.Format.AsNumber(points),
        icon = WBF.Format.AsNumber(icon),
        isStatistic = isStatistic and true or false,
    }
end

function WBF.PlanAchievements.Info(achievementID)
    achievementID = AchievementID(achievementID)
    if not achievementID then
        return nil
    end
    local cached = metaCache[achievementID]
    if cached then
        return cached
    end
    local info = ReadInfo(achievementID)
    if not info then
        return nil
    end
    metaCache[achievementID] = info
    return info
end

function WBF.PlanAchievements.IsTrackable(achievementID)
    achievementID = AchievementID(achievementID)
    if not achievementID then
        return false
    end
    if not WBF.PlanAchievements.Available() then
        return true
    end
    if type(C_AchievementInfo) == "table" and type(C_AchievementInfo.IsValidAchievement) == "function" then
        local valid = WBF.Format.SafeBoolean(C_AchievementInfo.IsValidAchievement, achievementID)
        if valid == false then
            return false
        end
    end
    local info = WBF.PlanAchievements.Info(achievementID)
    return info ~= nil and not info.isStatistic
end

local function CompletedNow(achievementID)
    if type(GetAchievementInfo) == "function" then
        local _, _, _, completed = WBF.Format.SafeCall(GetAchievementInfo, achievementID)
        local flag = WBF.Format.AsBoolean(completed)
        if flag ~= nil then
            return flag
        end
    end
    if type(C_AchievementInfo) == "table" and type(C_AchievementInfo.GetAchievementInfo) == "function" then
        local result = WBF.Format.SafeCall(C_AchievementInfo.GetAchievementInfo, achievementID)
        if type(result) == "table" then
            local flag = WBF.Format.AsBoolean(result.completed)
            if flag ~= nil then
                return flag
            end
        end
    end
    return false
end

local function ReadCriteria(achievementID)
    local list = {}
    local count = 0
    if type(GetAchievementNumCriteria) == "function" then
        count = WBF.Format.AsNumber(WBF.Format.SafeCall(GetAchievementNumCriteria, achievementID)) or 0
    end
    if count < 1 then
        return list
    end
    for index = 1, count do
        local criteriaString, _, completed, quantity, reqQuantity
        if type(GetAchievementCriteriaInfo) == "function" then
            criteriaString, _, completed, quantity, reqQuantity =
                WBF.Format.SafeCall(GetAchievementCriteriaInfo, achievementID, index)
        end
        if criteriaString == nil and quantity == nil and completed == nil then
            -- This index did not resolve. Keep going in case later rows do.
        else
            local name = nil
            if not WBF.Format.IsSecret(criteriaString) then
                name = WBF.Format.PlainString(criteriaString)
            end
            local known = nil
            if not WBF.Format.IsSecret(completed) then
                known = completed and true or false
            end
            list[#list + 1] = {
                name = name,
                completed = known,
                current = WBF.Format.AsNumber(quantity),
                required = WBF.Format.AsNumber(reqQuantity),
            }
        end
    end
    return list
end

local function QuantityPair(criterion)
    local required = criterion and criterion.required or nil
    local current = criterion and criterion.current or nil
    if type(required) == "number" and required > 1 and type(current) == "number" then
        return current, required
    end
    return nil, nil
end

function WBF.PlanAchievements.Progress(achievementID)
    achievementID = AchievementID(achievementID)
    if not achievementID then
        return nil
    end
    local cached = progressCache[achievementID]
    if cached then
        return cached
    end
    local info = WBF.PlanAchievements.Info(achievementID)
    if not info and WBF.PlanAchievements.Available() then
        return nil
    end
    local name = info and info.name or ("Achievement " .. achievementID)
    local completed = false
    if WBF.PlanAchievements.Available() then
        completed = CompletedNow(achievementID) and true or false
    end
    local criteria = ReadCriteria(achievementID)
    local progress = {
        id = achievementID,
        name = name,
        description = info and info.description or nil,
        icon = info and info.icon or nil,
        completed = completed,
        kind = "simple",
        current = nil,
        required = nil,
        percent = nil,
        criteria = criteria,
    }
    local current, required = QuantityPair(criteria[1])
    if #criteria == 1 and current then
        progress.kind = "quantity"
        progress.current = current
        progress.required = required
    elseif #criteria > 1 then
        local done = 0
        for index = 1, #criteria do
            if criteria[index].completed == true then
                done = done + 1
            end
        end
        progress.kind = "criteria"
        progress.current = done
        progress.required = #criteria
    elseif #criteria == 1 then
        progress.completed = completed or criteria[1].completed
    end
    if progress.kind == "quantity" and progress.required and progress.required > 0 then
        local percent = math.floor((progress.current / progress.required) * 100 + 0.5)
        if percent < 0 then
            percent = 0
        elseif percent > 100 then
            percent = 100
        end
        progress.percent = percent
        if completed or progress.current >= progress.required then
            progress.completed = true
            if progress.current > progress.required then
                progress.current = progress.required
            end
        end
    elseif progress.kind == "criteria" and progress.required and progress.required > 0 then
        local percent = math.floor((progress.current / progress.required) * 100 + 0.5)
        if percent < 0 then
            percent = 0
        elseif percent > 100 then
            percent = 100
        end
        progress.percent = percent
        if progress.current == progress.required then
            progress.completed = true
        end
    end
    if completed then
        progress.completed = true
    end
    progressCache[achievementID] = progress
    return progress
end

function WBF.PlanAchievements.ProgressText(progress)
    if type(progress) ~= "table" then
        return nil
    end
    if progress.kind == "quantity" and progress.current and progress.required then
        local text = progress.current .. " / " .. progress.required
        if progress.percent then
            text = text .. " · " .. progress.percent .. "%"
        end
        if progress.completed then
            return "Complete · " .. text
        end
        return text
    end
    if progress.kind == "criteria" and progress.current and progress.required then
        local text = progress.current .. " / " .. progress.required
        if progress.percent then
            text = text .. " · " .. progress.percent .. "%"
        end
        if progress.completed then
            return "Complete · " .. text
        end
        return text
    end
    if progress.completed then
        return "Complete"
    end
    return nil
end

function WBF.PlanAchievements.CriterionText(criterion)
    if type(criterion) ~= "table" then
        return nil
    end
    local current, required = QuantityPair(criterion)
    local name = type(criterion.name) == "string" and criterion.name or nil
    if current then
        if name then
            return name .. "  " .. current .. " / " .. required
        end
        return current .. " / " .. required
    end
    if not name then
        return nil
    end
    if criterion.completed == true then
        return name .. "  done"
    end
    return name
end

local COMPACT_CRITERIA = 3

local GENERIC_CRITERION = {
    progress = true,
    criterion = true,
    criteria = true,
    objective = true,
    objectives = true,
    complete = true,
    completed = true,
    incomplete = true,
    unknown = true,
    hidden = true,
    secret = true,
    none = true,
    ["n/a"] = true,
    ["???"] = true,
    ["?"] = true,
}

local function MeaningfulName(value)
    if WBF.Format.IsSecret(value) then
        return nil
    end
    local name = WBF.Format.PlainString(value)
    if not name then
        return nil
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or GENERIC_CRITERION[name:lower()] then
        return nil
    end
    if name:match("^[%d%s%./%-%+]+$") then
        return nil
    end
    for index = 1, #name do
        local byte = name:byte(index)
        if byte < 32 then
            return nil
        end
    end
    if #name > 120 then
        return nil
    end
    return name
end

local function PartialLabel(name, criterion)
    if WBF.Format.IsSecret(criterion.current) or WBF.Format.IsSecret(criterion.required) then
        return name
    end
    local current, required = QuantityPair(criterion)
    if not current or current < 0 or current > required then
        return name
    end
    return name .. "  " .. current .. " / " .. required
end

local criteriaExpanded = {}

function WBF.PlanAchievements.CriteriaExpanded(achievementID)
    achievementID = AchievementID(achievementID)
    return achievementID and criteriaExpanded[achievementID] == true or false
end

function WBF.PlanAchievements.ToggleCriteria(achievementID)
    achievementID = AchievementID(achievementID)
    if not achievementID then
        return false
    end
    criteriaExpanded[achievementID] = not criteriaExpanded[achievementID]
    return criteriaExpanded[achievementID] == true
end

function WBF.PlanAchievements.CriteriaDetail(progress, expanded)
    local detail = {
        summary = nil,
        heading = nil,
        lines = {},
        completedLines = {},
        more = 0,
        toggle = nil,
    }
    if type(progress) ~= "table" then
        return detail
    end
    detail.summary = WBF.PlanAchievements.ProgressText(progress)
    if progress.kind == "quantity" or type(progress.criteria) ~= "table" then
        return detail
    end
    local incomplete = {}
    local complete = {}
    for index = 1, #progress.criteria do
        local row = progress.criteria[index]
        local name = type(row) == "table" and MeaningfulName(row.name) or nil
        if name and row.completed == true then
            complete[#complete + 1] = {
                done = true,
                mark = "✓",
                text = PartialLabel(name, row),
            }
        elseif name and row.completed == false then
            incomplete[#incomplete + 1] = {
                done = false,
                mark = "○",
                text = PartialLabel(name, row),
            }
        end
    end
    if #incomplete == 0 and #complete == 0 then
        return detail
    end
    if expanded then
        for index = 1, #incomplete do
            detail.lines[#detail.lines + 1] = incomplete[index]
        end
        for index = 1, #complete do
            detail.completedLines[#detail.completedLines + 1] = complete[index]
        end
        if #incomplete > 0 then
            detail.heading = "Missing:"
        end
        if #incomplete > COMPACT_CRITERIA or #complete > 0 then
            detail.toggle = "Show less"
        end
        return detail
    end
    local shown = math.min(COMPACT_CRITERIA, #incomplete)
    for index = 1, shown do
        detail.lines[#detail.lines + 1] = incomplete[index]
    end
    if #incomplete > COMPACT_CRITERIA then
        detail.more = #incomplete - COMPACT_CRITERIA
    end
    if #incomplete > 0 then
        detail.heading = "Missing:"
    end
    if detail.more > 0 or #complete > 0 then
        detail.toggle = "Show all"
    end
    return detail
end

local function FilteredCount()
    if type(GetNumFilteredAchievements) == "function" then
        return WBF.Format.AsNumber(WBF.Format.SafeCall(GetNumFilteredAchievements)) or 0
    end
    if type(GetAchievementSearchSize) == "function" then
        return WBF.Format.AsNumber(WBF.Format.SafeCall(GetAchievementSearchSize)) or 0
    end
    return 0
end

local function FilteredID(index)
    if type(GetFilteredAchievementID) == "function" then
        return AchievementID(WBF.Format.SafeCall(GetFilteredAchievementID, index))
    end
    return nil
end

local function Collect(query, setString)
    local results = {}
    local seen = {}
    local function add(id)
        id = AchievementID(id)
        if not id or seen[id] or #results >= SEARCH_LIMIT then
            return
        end
        local info = WBF.PlanAchievements.Info(id)
        if not info or info.isStatistic then
            return
        end
        seen[id] = true
        results[#results + 1] = info
    end

    local numeric = query and query:match("^(%d+)$")
    if numeric then
        add(tonumber(numeric))
    end
    if setString and type(SetAchievementSearchString) == "function" and query and query ~= "" then
        WBF.Format.SafeCall(SetAchievementSearchString, query)
    end
    local count = FilteredCount()
    local limit = count
    if limit > 40 then
        limit = 40
    end
    for index = 1, limit do
        if #results >= SEARCH_LIMIT then
            if index <= limit then
                results.capped = true
            end
            break
        end
        add(FilteredID(index))
    end
    return results
end

function WBF.PlanAchievements.Search(text)
    if type(text) ~= "string" then
        lastQuery = nil
        return {}
    end
    text = (text:gsub("^%s+", ""):gsub("%s+$", ""))
    lastQuery = text
    if text == "" then
        return {}
    end
    return Collect(text, true)
end

function WBF.PlanAchievements.ReadLatest()
    if not lastQuery or lastQuery == "" then
        return {}
    end
    return Collect(lastQuery, false)
end

function WBF.PlanAchievements.ClearSearch()
    lastQuery = nil
    if type(SetAchievementSearchString) == "function" then
        WBF.Format.SafeCall(SetAchievementSearchString, "")
    end
end

local nextCriteriaRefresh = 0

function WBF.PlanAchievements.Register(bus)
    bus:On("CRITERIA_UPDATE", function()
        if not WBF.Notebook or not WBF.Notebook.HasAchievement() then
            return
        end
        local now = WBF.Time.Now()
        if now < nextCriteriaRefresh then
            return
        end
        local sheetOpen = WBF.NotebookSheet and WBF.NotebookSheet.IsOpen and WBF.NotebookSheet.IsOpen()
        local window = WBF.UI and WBF.UI.frame
        local windowShown = window and window.IsShown and window:IsShown()
        if not sheetOpen then
            if not windowShown then
                return
            end
            local view = window.view
            local dashboard = view == "current" or view == "last" or view == "today" or view == "week" or view == "month" or view == "warband"
            local showingNotebook = view == "notebook"
            if not showingNotebook and not dashboard then
                return
            end
            if not showingNotebook and window.detailStack and #window.detailStack > 0 then
                return
            end
        end
        nextCriteriaRefresh = now + 1
        WBF.PlanAchievements.InvalidateProgress()
        if WBF.Notebook.RequestRefreshOpen then
            WBF.Notebook.RequestRefreshOpen()
        end
    end)

    bus:On("ACHIEVEMENT_SEARCH_UPDATED", function()
        if WBF.UI and WBF.UI.NotebookAdd and WBF.UI.NotebookAdd.OnSearchUpdated then
            WBF.UI.NotebookAdd.OnSearchUpdated()
        end
    end)

    bus:On("ACHIEVEMENT_EARNED", function(achievementID)
        achievementID = tonumber(achievementID)
        WBF.PlanAchievements.InvalidateProgress()
        if achievementID and WBF.Notebook and WBF.Notebook.FindAchievement(achievementID) and WBF.Notebook.RequestRefreshOpen then
            WBF.Notebook.RequestRefreshOpen()
        end
    end)
end
