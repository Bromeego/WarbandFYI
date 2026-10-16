local _, WBF = ...

WBF.UI.Activity = {}

local root
local titleText
local detailText
local emptyText

function WBF.UI.Activity.Attach(parent)
    root = parent
    titleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
    titleText:SetText("Recent Activity")
    titleText:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])

    detailText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    detailText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    local petButton = CreateFrame("Button", nil, root)
    petButton:SetSize(120, 18)
    petButton:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -4)
    WBF.UI.BindWheel(petButton)
    local petLabel = petButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    petLabel:SetAllPoints()
    petLabel:SetJustifyH("RIGHT")
    petLabel:SetText("Pet Battles")
    petLabel:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])
    petButton:SetScript("OnClick", function()
        if WBF.UI.frame then
            local period = WBF.UI.frame.view
            if period ~= "current" and period ~= "last" and period ~= "today" and period ~= "week" and period ~= "month" and period ~= "warband" then
                period = "week"
            end
            WBF.UI.frame:OpenDetail("petBattles", { period = period, warband = true })
        end
    end)

    emptyText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyText:SetPoint("TOPLEFT", detailText, "BOTTOMLEFT", 0, -16)
    emptyText:SetWidth(460)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetWordWrap(true)
    emptyText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    emptyText:Hide()
end

function WBF.UI.Activity.Render(width)
    WBF.UI.ReleaseAll()
    local filter = WBF.UI.characterFilter
    local character = filter and WBF.Characters.Get(filter)
    if character and character.name then
        detailText:SetText(character.name .. "  ·  Click Activity in the sidebar to show everyone.")
    else
        detailText:SetText("The latest progress recorded for this Warband.")
    end

    local db = WBF.Database.Get()
    local events = db and db.events or {}
    local list = {}
    for index = 1, #events do
        local event = events[index]
        if (not filter or event.guid == filter) and WBF.QuestVisibility.IsPlayerActivity(event) and not (WBF.ResourceBehaviour and WBF.ResourceBehaviour.HidesActivity(event)) then
            list[#list + 1] = event
        end
    end
    table.sort(list, function(a, b)
        local aAt = a.at or 0
        local bAt = b.at or 0
        if aAt == bAt then
            return (a.id or 0) > (b.id or 0)
        end
        return aAt > bAt
    end)

    local limit = math.min(150, #list)
    if limit == 0 then
        emptyText:SetText("No activity recorded yet.")
        emptyText:Show()
        return 80
    end
    emptyText:Hide()

    for index = 1, limit do
        local event = list[index]
        local display = event
        if not filter and event.guid then
            local owner = WBF.Characters.Get(event.guid)
            if WBF.Characters.IsDiscovered(owner) and owner.name then
                display = {
                    at = event.at,
                    guid = event.guid,
                    eventType = event.eventType,
                    text = (event.text or "") .. "   —   " .. owner.name,
                    meta = event.meta,
                    previous = event.previous,
                    new = event.new,
                    delta = event.delta,
                    sample = event.sample,
                }
            end
        end
        local row = WBF.UI.AcquireActivity(root)
        row:SetWidth(width)
        row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(36 + (index - 1) * 24))
        row:Apply(display)
    end

    local extra = ""
    if #list > limit then
        extra = "Showing the latest " .. limit .. "."
    end
    if extra ~= "" then
        detailText:SetText(detailText:GetText() .. "  " .. extra)
    end
    return 44 + limit * 24
end
