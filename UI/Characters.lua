local _, WBF = ...

WBF.UI.CharactersView = {}

local root
local titleText
local detailText
local emptyText

function WBF.UI.CharactersView.Attach(parent)
    root = parent
    titleText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -4)
    titleText:SetText("Characters")
    titleText:SetTextColor(WBF.UI.Colors.gold[1], WBF.UI.Colors.gold[2], WBF.UI.Colors.gold[3])

    detailText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    detailText:SetText("Everyone this addon has seen on the Warband. Click a character for their progress.")
    detailText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])

    emptyText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyText:SetPoint("TOPLEFT", detailText, "BOTTOMLEFT", 0, -16)
    emptyText:SetText("Characters appear here after you log in with them.")
    emptyText:SetTextColor(WBF.UI.Colors.muted[1], WBF.UI.Colors.muted[2], WBF.UI.Colors.muted[3])
    emptyText:Hide()
end

function WBF.UI.CharactersView.Render(width)
    WBF.UI.ReleaseAll()
    local list = WBF.Characters.List()
    table.sort(list, function(a, b)
        local aSeen = a.lastSeenAt or 0
        local bSeen = b.lastSeenAt or 0
        if aSeen == bSeen then
            return (a.name or "") < (b.name or "")
        end
        return aSeen > bSeen
    end)

    if #list == 0 then
        emptyText:Show()
        return 80
    end
    emptyText:Hide()

    for index = 1, #list do
        local row = WBF.UI.AcquireRoster(root)
        row:SetWidth(width)
        row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(40 + (index - 1) * 60))
        row:Apply(list[index])
    end
    return 48 + #list * 60
end
