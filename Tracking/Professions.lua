local _, WBF = ...

WBF.Professions = {}

-- Skill ranks are read from the profession skill lines and compared with the
-- last rank stored for this character. The skill-up chat line triggers that
-- check at the moment it happens. If that line is protected, the same check
-- runs on the regular tick, so the change is still recorded.
-- Unlocking a profession specialization is its own event. Spending a
-- knowledge point does not name the perk, so those spends are not listed.

local CHAT_SPECS = {
    { global = "ERR_SKILL_UP_SI", name = 1, rank = 2 },
    { global = "ERR_SKILL_GAINED_S", name = 1, learned = true },
}

local chatPatterns = nil
local recent = {}
local listenAt = 0

local function ChatPatterns()
    if chatPatterns then
        return chatPatterns
    end
    chatPatterns = {}
    for index = 1, #CHAT_SPECS do
        local spec = CHAT_SPECS[index]
        local built = WBF.Format.CompileGlobal(spec.global)
        if built then
            chatPatterns[#chatPatterns + 1] = { spec = spec, built = built }
        end
    end
    return chatPatterns
end

local function LineName(info)
    local name = info.professionName or info.parentProfessionName or "Profession"
    if type(info.expansionName) == "string" and info.expansionName ~= "" then
        if not name:find(info.expansionName, 1, true) then
            name = info.expansionName .. " " .. name
        end
    end
    return name
end

local function Note(name, rank)
    recent[#recent + 1] = { name = name, rank = rank, at = WBF.Time.Now() }
    if #recent > 20 then
        local kept = {}
        local now = WBF.Time.Now()
        for index = 1, #recent do
            if now - recent[index].at < 10 then
                kept[#kept + 1] = recent[index]
            end
        end
        recent = kept
    end
end

local function WasNoted(name, rank)
    local now = WBF.Time.Now()
    for index = 1, #recent do
        local row = recent[index]
        if row.name == name and row.rank == rank and now - row.at < 8 then
            return true
        end
    end
    return false
end

local function RecordRank(name, previous, rank)
    if WasNoted(name, rank) then
        return false
    end
    Note(name, rank)
    local text
    if previous then
        text = name .. "  " .. WBF.Format.Progression(previous, rank)
    else
        text = name .. " increased to " .. rank
    end
    WBF.Events.Add({
        category = WBF.Category.Profession,
        eventType = WBF.EventType.Profession,
        text = text,
        previous = previous,
        new = rank,
        delta = previous and (rank - previous) or nil,
        meta = {
            profession = name,
            skillUp = true,
            eventLabel = name .. " increased",
            detail = previous and (tostring(previous) .. " -> " .. tostring(rank)) or tostring(rank),
            iconAtlas = "Professions-ChatIcon-Quality-Tier1",
        },
    })
    return true
end

local function RecordLearned(name)
    if WasNoted(name, 0) then
        return
    end
    Note(name, 0)
    WBF.Events.Add({
        category = WBF.Category.Profession,
        eventType = WBF.EventType.Profession,
        text = "Learned " .. name,
        meta = {
            profession = name,
            learned = true,
            iconAtlas = "Professions-ChatIcon-Quality-Tier1",
        },
    })
end

local function CallCurrencyID(owner, method, skillLineID)
    if not owner or type(owner[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(owner[method], skillLineID)
    value = ok and tonumber(value) or nil
    if value and value > 0 then
        return value
    end
    return nil
end

local function FindNamedCurrency(professionName, token)
    if not professionName or not WBF.Resources or not WBF.Resources.Each then
        return nil
    end
    local needle = professionName:lower()
    local list = WBF.Resources.Each()
    for index = 1, #list do
        local definition = list[index]
        if definition.trackingType == "currency" then
            local name = (definition.displayName or definition.name or ""):lower()
            if name:find(token, 1, true) and name:find(needle, 1, true) then
                return definition.id
            end
        end
    end
    return nil
end

local function ConcentrationCurrency(skillLineID, info, professionName)
    local id = CallCurrencyID(C_TradeSkillUI, "GetConcentrationCurrencyID", skillLineID)
    if id then
        return id
    end
    id = type(info) == "table" and tonumber(info.concentrationCurrencyID) or nil
    if id and id > 0 then
        return id
    end
    return FindNamedCurrency(professionName, "concentration")
end

local function KnowledgeCurrency(skillLineID, info, professionName)
    local id = CallCurrencyID(C_TradeSkillUI, "GetProfessionKnowledgeCurrencyID", skillLineID)
        or CallCurrencyID(C_Professions, "GetProfessionKnowledgeCurrencyID", skillLineID)
    if id then
        return id
    end
    if type(info) == "table" then
        id = tonumber(info.knowledgeCurrencyID or info.professionCurrencyID)
        if id and id > 0 then
            return id
        end
    end
    return FindNamedCurrency(professionName, "knowledge")
end

local function ProfessionIcon(skillLineID, info)
    if type(info) == "table" then
        local icon = tonumber(info.professionIcon or info.icon)
        if icon and icon > 0 then
            return icon
        end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
        local ok, tex = pcall(C_TradeSkillUI.GetTradeSkillTexture, skillLineID)
        tex = ok and tonumber(tex) or nil
        if tex and tex > 0 then
            return tex
        end
    end
    return nil
end

local function RememberSnapshot(character, skillLineID, info, name, rank, maxRank)
    character.professions = character.professions or {}
    local root = info.professionName or info.parentProfessionName or name
    local expansion = type(info.expansionName) == "string" and info.expansionName ~= "" and info.expansionName or nil
    local label = name
    if expansion and root and not tostring(root):find(expansion, 1, true) then
        label = expansion .. " " .. root
    end
    local snap = {
        skillLineID = skillLineID,
        name = root,
        expansionName = expansion,
        label = label,
        skill = rank,
        maxSkill = maxRank,
        icon = ProfessionIcon(skillLineID, info),
        isPrimary = info.isPrimaryProfession ~= false,
        professionEnum = WBF.Format.AsNumber(info.profession),
        updatedAt = WBF.Time.Now(),
    }
    if WBF.Resources and WBF.Resources.NoteSpecialCurrency and WBF.ResourceBehaviour then
        local concentrationID = ConcentrationCurrency(skillLineID, info, root)
        if concentrationID then
            local definition = WBF.Resources.NoteSpecialCurrency(concentrationID, WBF.ResourceBehaviour.REGENERATING_METER, {
                profession = label,
            })
            if definition and definition.meterCurrent ~= nil then
                snap.concentration = {
                    current = definition.meterCurrent,
                    max = definition.maximum,
                }
            end
        end
        local knowledgeID = KnowledgeCurrency(skillLineID, info, root)
        if knowledgeID then
            local definition = WBF.Resources.NoteSpecialCurrency(knowledgeID, WBF.ResourceBehaviour.PROGRESSION, {
                profession = label,
            })
            if definition and definition.meterCurrent ~= nil then
                snap.knowledge = {
                    available = definition.meterCurrent,
                }
            end
        end
    end
    character.professions[skillLineID] = snap
    return snap
end

function WBF.Professions.Same(left, right)
    if type(left) ~= "string" or type(right) ~= "string" then
        return false
    end
    local a = left:lower()
    local b = right:lower()
    if a == "" or b == "" then
        return false
    end
    return a == b or a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

function WBF.Professions.Snapshots(character)
    local list = {}
    local stored = character and character.professions or nil
    if type(stored) ~= "table" then
        return list
    end
    for _, snap in pairs(stored) do
        if type(snap) == "table" and snap.label then
            list[#list + 1] = snap
        end
    end
    table.sort(list, function(a, b)
        if a.isPrimary ~= b.isPrimary then
            return a.isPrimary and true or false
        end
        return (a.label or "") < (b.label or "")
    end)
    return list
end

function WBF.Professions.ApplyEvent(bucket, event)
    if type(bucket) ~= "table" or type(event) ~= "table" or event.eventType ~= WBF.EventType.Profession then
        return false
    end
    local meta = event.meta or {}
    if meta.concentrationUsed then
        bucket.concentrationUsed = (bucket.concentrationUsed or 0) + meta.concentrationUsed
        return true
    end
    if meta.knowledge and meta.surface ~= false then
        bucket.knowledge = (bucket.knowledge or 0) + meta.knowledge
        return true
    end
    if meta.knowledgeSpent then
        bucket.knowledgeSpent = (bucket.knowledgeSpent or 0) + meta.knowledgeSpent
        return true
    end
    if meta.recipe then
        bucket.recipes = (bucket.recipes or 0) + 1
        return true
    end
    if meta.surface == false then
        return true
    end
    bucket.professions = (bucket.professions or 0) + 1
    return true
end

function WBF.Professions.PeriodStats(guid, startAt, endAt, professionLabel)
    local stats = {
        used = 0,
        knowledge = 0,
        knowledgeSpent = 0,
        recipes = 0,
        ranks = 0,
    }
    if not WBF.Database or not WBF.Database.Get then
        return stats
    end
    local events = WBF.Database.Get().events or {}
    for index = 1, #events do
        local event = events[index]
        local at = event.at or 0
        local inRange = (not startAt or at >= startAt) and (not endAt or at <= endAt)
        if inRange and event.eventType == WBF.EventType.Profession and (not guid or event.guid == guid) then
            local meta = event.meta or {}
            local matches = not professionLabel or WBF.Professions.Same(professionLabel, meta.profession or "")
            if meta.concentrationUsed and matches then
                stats.used = stats.used + meta.concentrationUsed
            elseif meta.knowledge and meta.surface ~= false and matches then
                stats.knowledge = stats.knowledge + meta.knowledge
            elseif meta.knowledgeSpent and matches then
                stats.knowledgeSpent = stats.knowledgeSpent + meta.knowledgeSpent
            elseif meta.recipe then
                if not professionLabel or matches then
                    stats.recipes = stats.recipes + 1
                end
            elseif meta.surface ~= false and not meta.concentrationUsed and not meta.knowledge and not meta.recipe and matches then
                stats.ranks = stats.ranks + 1
            end
        end
    end
    return stats
end

local function EachLine(visitor)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines and C_TradeSkillUI.GetProfessionInfoBySkillLineID) then
        return false
    end
    local ok, lines = pcall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if not ok or type(lines) ~= "table" then
        return false
    end
    for index = 1, #lines do
        local lineOK, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, lines[index])
        if lineOK and type(info) == "table" then
            visitor(lines[index], info)
        end
    end
    return true
end

function WBF.Professions.Scan()
    local character = WBF.Characters.GetCurrent()
    if not character then
        return 0
    end
    character.professionRanks = character.professionRanks or {}
    character.professionNames = character.professionNames or {}
    character.professionByName = character.professionByName or {}

    local recorded = 0
    local found = EachLine(function(skillLineID, info)
        local rank = WBF.Format.AsNumber(info.skillLevel)
        local maxRank = WBF.Format.AsNumber(info.maxSkillLevel)
        if rank == nil or maxRank == nil or maxRank <= 0 then
            return
        end
        rank = math.floor(rank + 0.5)
        local key = tostring(skillLineID)
        local name = LineName(info)
        RememberSnapshot(character, skillLineID, info, name, rank, maxRank)
        local previous = character.professionRanks[key]
        character.professionNames[key] = name

        local absorbed = false
        for chatName, chatRank in pairs(character.professionByName) do
            if chatRank == rank and WBF.Professions.Same(chatName, name) then
                character.professionByName[chatName] = nil
                absorbed = true
                break
            end
        end
        if absorbed then
            character.professionRanks[key] = rank
            return
        end
        if previous ~= nil and rank > previous and not WasNoted(name, rank) then
            if RecordRank(name, previous, rank) then
                recorded = recorded + 1
            end
        end
        character.professionRanks[key] = rank
    end)

    if not found then
        return recorded
    end
    return recorded
end

function WBF.Professions.FromChat(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
        return
    end
    text = strtrim(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    local patterns = ChatPatterns()
    for index = 1, #patterns do
        local row = patterns[index]
        local values = WBF.Format.MatchGlobal(text, row.built)
        if values then
            local spec = row.spec
            local name = values[spec.name]
            if type(name) ~= "string" or name == "" then
                return
            end
            if spec.learned then
                RecordLearned(name)
                return
            end
            local rank = tonumber(values[spec.rank])
            if not rank then
                return
            end
            rank = math.floor(rank + 0.5)
            local character = WBF.Characters.GetCurrent()
            if not character then
                RecordRank(name, nil, rank)
                return
            end
            character.professionRanks = character.professionRanks or {}
            character.professionNames = character.professionNames or {}
            character.professionByName = character.professionByName or {}

            local matched = false
            for key, storedName in pairs(character.professionNames) do
                if storedName == name then
                    matched = true
                    local previous = character.professionRanks[key]
                    if (previous == nil or rank > previous) and not WasNoted(name, rank) then
                        RecordRank(name, previous, rank)
                    end
                    character.professionRanks[key] = rank
                end
            end
            if not matched then
                local previous = character.professionByName[name]
                if previous ~= rank and not WasNoted(name, rank) then
                    RecordRank(name, previous, rank)
                end
                character.professionByName[name] = rank
            end
            return
        end
    end
end

local function ProfessionLabel(skillLineID, tradeSkillID)
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID and skillLineID then
        local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        if ok and type(info) == "table" then
            local name = LineName(info)
            if name and name ~= "" and name ~= "Profession" then
                return name
            end
        end
    end
    if C_Spell and C_Spell.GetSpellName and tradeSkillID then
        local name = C_Spell.GetSpellName(tradeSkillID)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

function WBF.Professions.Arm()
    -- Specialization unlock can be replayed as login data. Ignore it until
    -- the session has actually started.
    listenAt = WBF.Time.Now() + 5
end

function WBF.Professions.Register(bus)
    bus:On("CHAT_MSG_SKILL", function(text)
        if WBF.Professions.Scan() > 0 then
            return
        end
        WBF.Professions.FromChat(text)
    end)

    bus:On("TRADE_SKILL_LIST_UPDATE", function()
        WBF.Professions.Scan()
    end)

    bus:On("SKILL_LINES_CHANGED", function()
        WBF.Professions.Scan()
    end)

    bus:On("NEW_RECIPE_LEARNED", function(recipeID)
        recipeID = tonumber(recipeID)
        if not recipeID then
            return
        end
        local name, profession
        if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
            local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
            if ok and type(info) == "table" then
                name = info.name
                if type(info.skillLineID) == "number" and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                    local lineOK, line = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, info.skillLineID)
                    if lineOK and type(line) == "table" then
                        profession = LineName(line)
                    end
                end
            end
        end
        local text = name and ("New recipe learned: " .. name) or "New recipe learned"
        WBF.Events.Add({
            category = WBF.Category.Profession,
            eventType = WBF.EventType.Profession,
            dedupeKey = "recipe:" .. recipeID,
            text = text,
            meta = {
                recipe = true,
                recipeID = recipeID,
                recipeName = name,
                profession = profession,
                eventLabel = "Recipe learned",
                detail = name or "New recipe",
                iconAtlas = "Professions-ChatIcon-Quality-Tier1",
            },
        })
    end)

    bus:On("SKILL_LINE_SPECS_UNLOCKED", function(skillLineID, tradeSkillID)
        if WBF.Time.Now() < listenAt then
            return
        end
        local name = ProfessionLabel(skillLineID, tradeSkillID)
        local text = name and ("Unlocked " .. name .. " specialization") or "Unlocked a profession specialization"
        WBF.Events.Add({
            category = WBF.Category.Profession,
            eventType = WBF.EventType.Profession,
            text = text,
            dedupeKey = "profspec:" .. tostring(skillLineID or tradeSkillID or text),
            meta = {
                profession = name,
                skillLineID = skillLineID,
                specialization = true,
                iconAtlas = "Professions-ChatIcon-Quality-Tier1",
            },
        })
    end)
end
