local _, WBF = ...

-- Saved rows identify a pet; levels and completion always come from the journal.
WBF.NotebookPets = {}
local P = WBF.NotebookPets

-- Optional, read-only integration. Never load Rematch or copy its queue.
function P.RematchQueued(petID)
    local queue = type(Rematch) == "table" and Rematch.queue
    if type(petID) ~= "string" or type(queue) ~= "table"
        or type(queue.IsPetLeveling) ~= "function" then return false end
    local ok, queued = pcall(queue.IsPetLeveling, queue, petID)
    return ok and queued == true
end

local function Call(name, ...)
    local fn = C_PetJournal and C_PetJournal[name]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

function P.Read(petID)
    if type(petID) ~= "string" or petID == "" then return nil end
    local info = Call("GetPetInfoTableByPetID", petID)
    if not info and C_PetJournal and C_PetJournal.GetPetInfoByPetID then
        local ok, sid, custom, level, _, _, _, _, name, icon, _, _, _, _, _, canBattle =
            pcall(C_PetJournal.GetPetInfoByPetID, petID)
        if ok and sid then
            info = { speciesID = sid, customName = custom, petLevel = level,
                name = name, icon = icon, canBattle = canBattle }
        end
    end
    if type(info) ~= "table" or not info.speciesID then return nil end
    local level = tonumber(info.petLevel)
    if level and (level ~= level or level < 1 or level > 25) then level = nil end
    return { petID = petID, speciesID = info.speciesID,
        name = info.customName and info.customName ~= "" and info.customName or info.name,
        speciesName = info.name, icon = info.icon, level = level, canBattle = info.canBattle }
end

function P.Entries(block)
    if type(block) ~= "table" or block.type ~= "pet_level_list" then return {} end
    if type(block.pets) ~= "table" then
        block.pets = {}
        -- Never guess which copy an older species-only entry meant.
        for _, sid in ipairs(type(block.species) == "table" and block.species or {}) do
            if type(sid) == "number" and sid > 0 and sid == math.floor(sid) then
                block.pets[#block.pets + 1] = { speciesID = sid }
            end
        end
        block.species = nil
    end
    return block.pets
end

function P.View(entry)
    local live = P.Read(entry.petID)
    if live and live.speciesID ~= entry.speciesID then live = nil end
    local species = Call("GetPetInfoTableBySpeciesID", entry.speciesID)
    local row = live or { petID = entry.petID, speciesID = entry.speciesID }
    row.name = row.name or entry.name or (species and species.name) or ("Pet " .. tostring(entry.speciesID))
    row.icon = row.icon or entry.icon or (species and species.icon)
    row.complete = live ~= nil and row.level ~= nil and row.level >= 25
    row.queueStatus = live and not row.complete and P.RematchQueued(entry.petID)
        and "Queued in Rematch" or nil
    row.detail = not entry.petID and "Choose a copy" or not live and "Pet unavailable"
        or not row.level and "Level unavailable" or ("Lv " .. row.level .. " / 25" .. (row.complete and "  Done" or ""))
    return row
end

function P.Label(row)
    -- The stable suffix also distinguishes identical names and levels.
    return row.name .. (row.petID and (" [" .. row.petID:sub(-6) .. "]") or "")
end

function P.Progress(block)
    local rows, complete = {}, 0
    for _, entry in ipairs(P.Entries(block)) do
        if type(entry) == "table" then
            local row = P.View(entry)
            rows[#rows + 1] = row
            if row.complete then complete = complete + 1 end
        end
    end
    return rows, complete, complete .. " / " .. #rows .. " at level 25"
end

function P.Search(query)
    local ids = Call("GetOwnedPetIDs")
    local filtered = type(ids) ~= "table"
    if filtered then
        ids = {}
        local count = Call("GetNumPets") or 0
        for index = 1, count do
            local id = Call("GetPetInfoByIndex", index)
            if id then ids[#ids + 1] = id end
        end
    end
    local rows, seen = {}, {}
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    for _, id in ipairs(ids) do
        local row = not seen[id] and P.Read(id) or nil
        seen[id] = true
        if row and row.canBattle ~= false and row.level then
            row.name = row.name or ("Pet " .. row.speciesID)
            local text = (row.name .. " " .. (row.speciesName or "") .. " " .. id):lower()
            if text:find(query, 1, true) then rows[#rows + 1] = row end
        end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if a.level ~= b.level then return a.level < b.level end
        return a.petID < b.petID
    end)
    return rows, filtered
end

function P.Register(bus)
    local queued = false
    local hooked = {}
    local function refresh()
        if queued then return end
        queued = true
        local function run()
            queued = false
            WBF.Notebook.RefreshOpen()
            if WBF.UI and WBF.UI.NotebookPets and WBF.UI.NotebookPets.RefreshSearch then
                WBF.UI.NotebookPets.RefreshSearch()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.1, run) else run() end
    end
    for _, event in ipairs({ "PET_JOURNAL_LIST_UPDATE", "PET_JOURNAL_PET_DELETED",
        "NEW_PET_ADDED", "PET_BATTLE_CLOSE", "PLAYER_ENTERING_WORLD" }) do
        bus:On(event, refresh)
    end
    local function connect()
        local queue = type(Rematch) == "table" and Rematch.queue
        if type(queue) ~= "table" or hooked[queue] or type(queue.Update) ~= "function"
            or type(queue.IsPetLeveling) ~= "function" or type(hooksecurefunc) ~= "function" then return end
        -- Update rebuilds Rematch's membership lookup after queue edits.
        -- A post-hook observes the finished update without changing its behavior.
        local ok = pcall(hooksecurefunc, queue, "Update", refresh)
        if ok then hooked[queue] = true; refresh() end
    end
    bus:On("ADDON_LOADED", connect)
    bus:On("PLAYER_ENTERING_WORLD", connect)
    connect()
end
