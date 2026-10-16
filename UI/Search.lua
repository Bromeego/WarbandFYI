local _, WBF = ...

WBF.UI.Search = {}

local attached = false
local box
local placeholder
local resultsFrame
local catcher
local rows = {}
local generation = 0
local activeResults = {}

local MAX_RESULTS = 12
local ACTIVITY_RESULTS = 4

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Lower(value)
    return tostring(value or ""):lower()
end

local function Tokens(query)
    local list = {}
    for token in Lower(query):gmatch("[%w_%-]+") do
        if token ~= "" then
            list[#list + 1] = token
        end
    end
    return list
end

local function SearchScore(query, ...)
    local needle = Lower(Trim(query))
    if needle == "" then
        return nil
    end
    local fields = { ... }
    local hay = {}
    for index = 1, #fields do
        local text = Lower(fields[index])
        if text ~= "" then
            hay[#hay + 1] = text
        end
    end
    local joined = table.concat(hay, "  ")
    if joined == "" then
        return nil
    end
    local score = 0
    local phraseAt = joined:find(needle, 1, true)
    if phraseAt then
        score = score + 160 - math.min(80, phraseAt - 1)
    end
    local tokens = Tokens(query)
    if #tokens == 0 then
        return phraseAt and score or nil
    end
    for index = 1, #tokens do
        local token = tokens[index]
        local at = joined:find(token, 1, true)
        if not at then
            return nil
        end
        score = score + 22
        if at == 1 then
            score = score + 8
        end
    end
    return score
end

local function KindWeight(kind)
    if kind == "Resource" then
        return 40
    end
    if kind == "Notebook" then
        return 30
    end
    if kind == "Character" then
        return 20
    end
    return 10
end

local function ResultKey(result)
    return table.concat({
        result.kind or "",
        result.key or "",
        result.title or "",
        result.detail or "",
    }, "|")
end

local function AddResult(results, seen, result)
    if type(result) ~= "table" or type(result.title) ~= "string" or result.title == "" then
        return
    end
    local key = ResultKey(result)
    if seen[key] then
        return
    end
    seen[key] = true
    result.score = (tonumber(result.score) or 0) + KindWeight(result.kind)
    results[#results + 1] = result
end

local function ResourceResults(query, results, seen, window)
    if not WBF.Resources or not WBF.Resources.Catalog then
        return
    end
    local catalog = WBF.Resources.Catalog()
    local resources = catalog and catalog.resources or {}
    for index = 1, #resources do
        local card = resources[index]
        local score = SearchScore(query, card.name, card.short, card.key, card.id, card.eraLabel, card.eventName, card.kind, card.status)
        if score then
            local amount = card.known and WBF.Format.Number(card.amount or 0) or "Not observed yet"
            local context = card.eventName or card.eraLabel or card.status
            local detail = "Resource  ·  " .. tostring(amount)
            if context and context ~= "" then
                detail = detail .. "  ·  " .. tostring(context)
            end
            AddResult(results, seen, {
                kind = "Resource",
                key = card.key,
                title = card.name or card.short or card.key,
                detail = detail,
                icon = card.texture,
                score = score + 80,
                action = function()
                    if window and window.OpenResource then
                        window:OpenResource(card.key, "week")
                    end
                end,
            })
        end
    end
end

local function NotebookResults(query, results, seen)
    if not WBF.Notebook or not WBF.Notebook.Search then
        return
    end
    local gathered = {}
    local function collect(searchQuery)
        local found = WBF.Notebook.Search(searchQuery)
        for index = 1, #(found.hits or {}) do
            local hit = found.hits[index]
            local key = table.concat({ hit.kind or "", hit.pageId or "", hit.sectionId or "", hit.blockId or "", hit.noteId or "", hit.title or "" }, "|")
            gathered[key] = hit
        end
    end
    collect(query)
    local tokens = Tokens(query)
    if #tokens > 1 then
        for index = 1, #tokens do
            collect(tokens[index])
        end
    end
    for _, hit in pairs(gathered) do
        local score = SearchScore(query, hit.title, hit.detail)
        if score then
            local action
            if hit.kind == "note" and hit.noteId then
                action = function()
                    if WBF.UI.Notebook and WBF.UI.Notebook.OpenNote then
                        WBF.UI.Notebook.OpenNote(hit.noteId)
                    end
                end
            elseif hit.pageId then
                action = function()
                    if WBF.UI.Notebook and WBF.UI.Notebook.ShowPage then
                        WBF.UI.Notebook.ShowPage(hit.pageId, {
                            sectionId = hit.sectionId,
                            blockId = hit.blockId,
                        })
                    end
                end
            end
            AddResult(results, seen, {
                kind = "Notebook",
                key = hit.blockId or hit.sectionId or hit.pageId or hit.noteId,
                title = hit.title or "Notebook",
                detail = hit.detail or "Notebook",
                icon = "Interface\\Icons\\INV_Misc_Book_09",
                score = score + 30,
                action = action,
            })
        end
    end
end

local function CharacterResults(query, results, seen, window)
    if not WBF.Characters or not WBF.Characters.List then
        return
    end
    local characters = WBF.Characters.List()
    for index = 1, #characters do
        local character = characters[index]
        local score = SearchScore(query, character.name, character.realm, character.className, character.classFile, character.specName)
        if score then
            local detail = character.specName or character.className or "Character"
            if character.realm and character.realm ~= "" then
                detail = detail .. "  ·  " .. character.realm
            end
            AddResult(results, seen, {
                kind = "Character",
                key = character.guid,
                title = character.name or "Character",
                detail = detail,
                atlas = character.classFile and ("classicon-" .. character.classFile:lower()) or nil,
                icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
                score = score,
                action = function()
                    if window and window.OpenDetail then
                        window:OpenDetail("character", { period = "warband", characterGUID = character.guid })
                    end
                end,
            })
        end
    end
end

local function EventHaystack(event)
    local meta = event.meta or {}
    return table.concat({
        tostring(event.text or ""),
        tostring(meta.name or ""),
        tostring(meta.resourceKey or ""),
        tostring(meta.instanceName or meta.instance or ""),
        tostring(meta.professionName or meta.profession or ""),
        tostring(meta.zone or ""),
        tostring(meta.source or ""),
    }, "  ")
end

local function ActivityResults(query, results, seen, window)
    if #Trim(query) < 3 or not WarbandFYI_DB or type(WarbandFYI_DB.events) ~= "table" then
        return
    end
    local events = WarbandFYI_DB.events
    local added = 0
    local localSeen = {}
    for index = #events, 1, -1 do
        local event = events[index]
        if type(event) == "table" then
            local score = SearchScore(query, EventHaystack(event))
            if score then
                local category = WBF.UI.DetailCategory and WBF.UI.DetailCategory(event) or nil
                if category then
                    local title = WBF.Format.DisplayText and WBF.Format.DisplayText(event.text or "Activity") or (event.text or "Activity")
                    local key = tostring(category) .. "|" .. tostring(title)
                    if not localSeen[key] then
                        localSeen[key] = true
                        local character = event.guid and WBF.Characters and WBF.Characters.Get and WBF.Characters.Get(event.guid) or nil
                        local detail = "History  ·  " .. (WBF.Format.Ago and WBF.Format.Ago(event.at) or "recorded")
                        if character and character.name then
                            detail = detail .. "  ·  " .. character.name
                        end
                        AddResult(results, seen, {
                            kind = "History",
                            key = tostring(event.id or index),
                            title = title,
                            detail = detail,
                            icon = event.meta and event.meta.icon or nil,
                            score = score - 10,
                            action = function()
                                if category == "resource" and event.meta and event.meta.resourceKey and window.OpenResource then
                                    window:OpenResource(event.meta.resourceKey, "warband")
                                    return
                                end
                                if window and window.OpenDetail then
                                    window:OpenDetail(category, {
                                        period = "warband",
                                        characterGUID = event.guid,
                                        resourceKey = event.meta and event.meta.resourceKey or nil,
                                        warband = category == "petBattles" and not event.guid or nil,
                                    })
                                end
                            end,
                        })
                        added = added + 1
                        if added >= ACTIVITY_RESULTS then
                            return
                        end
                    end
                end
            end
        end
    end
end

local function BuildResults(query, window)
    local results = {}
    local seen = {}
    ResourceResults(query, results, seen, window)
    NotebookResults(query, results, seen)
    CharacterResults(query, results, seen, window)
    ActivityResults(query, results, seen, window)
    table.sort(results, function(a, b)
        if a.score == b.score then
            if a.kind == b.kind then
                return Lower(a.title) < Lower(b.title)
            end
            return KindWeight(a.kind) > KindWeight(b.kind)
        end
        return a.score > b.score
    end)
    local trimmed = {}
    for index = 1, math.min(MAX_RESULTS, #results) do
        trimmed[index] = results[index]
    end
    return trimmed
end

local function HideResults()
    activeResults = {}
    if resultsFrame then
        resultsFrame:Hide()
    end
    if catcher then
        catcher:Hide()
    end
end

local function ApplyIcon(texture, result)
    texture:SetTexCoord(0, 1, 0, 1)
    if result.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(result.atlas) then
        texture:SetAtlas(result.atlas)
    elseif result.icon then
        texture:SetTexture(result.icon)
    else
        texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

local function RenderResults(query, window)
    activeResults = BuildResults(query, window)
    for index = 1, #rows do
        rows[index]:Hide()
    end
    if #activeResults == 0 then
        local row = rows[1]
        row.Icon:Hide()
        row.Title:SetText("No matches")
        row.Detail:SetText("Try a resource, Notebook task, character, mount, pet, or activity name.")
        row.Kind:SetText("")
        row._action = nil
        row:Show()
        resultsFrame:SetHeight(54)
    else
        for index = 1, #activeResults do
            local result = activeResults[index]
            local row = rows[index]
            row.Icon:Show()
            ApplyIcon(row.Icon, result)
            row.Title:SetText(result.title)
            row.Detail:SetText(result.detail or "")
            row.Kind:SetText(result.kind or "")
            row._action = result.action
            row:Show()
        end
        resultsFrame:SetHeight(10 + (#activeResults * 46))
    end
    resultsFrame:Show()
    catcher:Show()
end

function WBF.UI.Search.Attach(window, header)
    if attached or not window or not header then
        return
    end
    attached = true

    local holder = CreateFrame("Frame", nil, header, "BackdropTemplate")
    holder:SetSize(292, 26)
    holder:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    WBF.UI.Paint(holder, { 0.025, 0.03, 0.04, 0.96 }, { 0.34, 0.30, 0.20, 0.9 })
    holder:SetFrameLevel(window:GetFrameLevel() + 31)

    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(15, 15)
    icon:SetPoint("LEFT", 7, 0)
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetVertexColor(0.75, 0.75, 0.78)

    box = CreateFrame("EditBox", nil, holder)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlightSmall)
    box:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    box:SetPoint("RIGHT", holder, "RIGHT", -24, 0)
    box:SetHeight(22)
    box:SetTextInsets(0, 0, 0, 0)
    WBF.UI.KeepKeyboard(box)

    placeholder = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", box, "LEFT", 0, 0)
    placeholder:SetText("Search WarbandFYI...")
    placeholder:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3], 0.9)

    local clear = CreateFrame("Button", nil, holder)
    clear:SetSize(18, 18)
    clear:SetPoint("RIGHT", -4, 0)
    local clearText = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clearText:SetAllPoints()
    clearText:SetText("x")
    clearText:SetTextColor(0.7, 0.7, 0.72)
    clear:SetScript("OnClick", function()
        box:SetText("")
        box:SetFocus()
    end)

    catcher = CreateFrame("Button", nil, window)
    catcher:SetAllPoints(window)
    catcher:SetFrameLevel(window:GetFrameLevel() + 28)
    catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    catcher:SetScript("OnClick", function()
        HideResults()
        if box then
            box:ClearFocus()
        end
    end)
    catcher:Hide()

    resultsFrame = CreateFrame("Frame", nil, window, "BackdropTemplate")
    resultsFrame:SetWidth(520)
    resultsFrame:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -5)
    resultsFrame:SetFrameLevel(window:GetFrameLevel() + 32)
    WBF.UI.Paint(resultsFrame, { 0.025, 0.03, 0.04, 0.99 }, WBF.UI.Colors.goldDim)
    resultsFrame:Hide()

    for index = 1, MAX_RESULTS do
        local row = CreateFrame("Button", nil, resultsFrame)
        row:SetHeight(44)
        row:SetPoint("TOPLEFT", resultsFrame, "TOPLEFT", 6, -(5 + ((index - 1) * 46)))
        row:SetPoint("TOPRIGHT", resultsFrame, "TOPRIGHT", -6, -(5 + ((index - 1) * 46)))
        row:RegisterForClicks("LeftButtonUp")
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.05)
        local rowIcon = row:CreateTexture(nil, "ARTWORK")
        rowIcon:SetSize(28, 28)
        rowIcon:SetPoint("LEFT", 4, 0)
        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOPLEFT", rowIcon, "TOPRIGHT", 8, -4)
        title:SetPoint("RIGHT", -88, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        local detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        detail:SetPoint("BOTTOMLEFT", rowIcon, "BOTTOMRIGHT", 8, 3)
        detail:SetPoint("RIGHT", -88, 0)
        detail:SetJustifyH("LEFT")
        detail:SetWordWrap(false)
        detail:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
        local kind = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        kind:SetPoint("RIGHT", -6, 0)
        kind:SetJustifyH("RIGHT")
        kind:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
        row.Icon = rowIcon
        row.Title = title
        row.Detail = detail
        row.Kind = kind
        row:SetScript("OnClick", function(self)
            local action = self._action
            HideResults()
            box:ClearFocus()
            if action then
                action()
            end
        end)
        rows[index] = row
    end

    local function schedule()
        generation = generation + 1
        local current = generation
        local query = Trim(box:GetText() or "")
        placeholder:SetShown(query == "")
        if query == "" then
            HideResults()
            return
        end
        local function run()
            if current ~= generation or not box or Trim(box:GetText() or "") ~= query then
                return
            end
            RenderResults(query, window)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.12, run)
        else
            run()
        end
    end

    box:SetScript("OnTextChanged", schedule)
    box:SetScript("OnEditFocusGained", function()
        WBF.UI.Paint(holder, { 0.025, 0.03, 0.04, 0.98 }, WBF.UI.Colors.gold)
        local query = Trim(box:GetText() or "")
        if query ~= "" then
            RenderResults(query, window)
        end
    end)
    box:SetScript("OnEditFocusLost", function()
        WBF.UI.Paint(holder, { 0.025, 0.03, 0.04, 0.96 }, { 0.34, 0.30, 0.20, 0.9 })
    end)
    box:SetScript("OnEscapePressed", function(self)
        HideResults()
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self)
        if activeResults[1] and activeResults[1].action then
            local action = activeResults[1].action
            HideResults()
            self:ClearFocus()
            action()
        end
    end)

    WBF.UI.Search.Focus = function(text)
        if type(text) == "string" then
            box:SetText(text)
        end
        box:SetFocus()
        if box.HighlightText and type(text) ~= "string" then
            box:HighlightText()
        end
    end

    WBF.UI.Search.Hide = HideResults
end
