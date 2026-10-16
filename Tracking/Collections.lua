local _, WBF = ...

WBF.Collections = {}

-- Mounts, pets, and appearance sources are recorded from the collection-added
-- events. Those events identify the new record. We do not scan the entire
-- collection, because a scan cannot tell "new this session" from "already owned".
-- Toys are intentionally not tracked in this version.

function WBF.Collections.CollectedWhere()
    if GetInstanceInfo then
        local ok, name, instanceType = pcall(GetInstanceInfo)
        name = ok and WBF.Format.PlainString(name) or nil
        if name and (instanceType == "raid" or instanceType == "party" or instanceType == "scenario") then
            return name, nil
        end
    end
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetMapInfo then
        return nil, nil
    end
    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    mapID = okMap and WBF.Format.AsNumber(mapID) or nil
    if not mapID then
        return nil, nil
    end
    local okInfo, info = pcall(C_Map.GetMapInfo, mapID)
    if okInfo and type(info) == "table" then
        return nil, WBF.Format.PlainString(info.name)
    end
    return nil, nil
end

local function ItemIcon(itemID)
    if not itemID or not GetItemInfoInstant then
        return nil
    end
    local _, _, _, _, icon = GetItemInfoInstant(itemID)
    return icon
end

function WBF.Collections.Register(bus)
    bus:On("NEW_MOUNT_ADDED", function(mountID)
        mountID = tonumber(mountID)
        if not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoByID then
            return
        end
        local name, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
        WBF.Events.Add({
            category = WBF.Category.Collection,
            eventType = WBF.EventType.Mount,
            dedupeKey = "mount:" .. mountID,
            text = name or "New mount",
            meta = {
                mountID = mountID,
                spellID = spellID,
                icon = icon,
            },
        })
    end)

    bus:On("NEW_PET_ADDED", function(petID)
        if petID == nil or not C_PetJournal or not C_PetJournal.GetPetInfoByPetID then
            return
        end
        local speciesID, _, level, _, _, _, _, name, icon, petType, _, _, _, isWild = C_PetJournal.GetPetInfoByPetID(petID)
        local quality
        if C_PetJournal.GetPetStats then
            local okStats, _, _, _, _, rarity = pcall(C_PetJournal.GetPetStats, petID)
            if okStats then
                quality = rarity
            end
        end
        local info = {
            speciesID = speciesID,
            name = name,
            icon = icon,
            level = level,
            quality = quality,
            petType = petType,
        }
        if WBF.PetBattles and WBF.PetBattles.ClaimAdded and WBF.PetBattles.ClaimAdded(petID, info) then
            return
        end
        local label = name or "New battle pet"
        if isWild then
            label = (name or "Battle pet") .. " captured"
        end
        WBF.Events.Add({
            category = WBF.Category.Collection,
            eventType = WBF.EventType.Pet,
            dedupeKey = "pet:" .. tostring(petID),
            text = label,
            meta = {
                petID = petID,
                speciesID = speciesID,
                icon = icon,
                captured = isWild and true or false,
                capturedLevel = tonumber(level),
                capturedQuality = tonumber(quality),
                petType = petType,
            },
        })
    end)

    bus:On("TRANSMOG_COLLECTION_SOURCE_ADDED", function(sourceID)
        sourceID = tonumber(sourceID)
        if not sourceID then
            return
        end
        local name, quality, itemID, icon
        if C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
            local info = C_TransmogCollection.GetSourceInfo(sourceID)
            if info then
                name = info.name
                quality = info.quality
                itemID = info.itemID
                icon = ItemIcon(info.itemID)
            end
        end
        local text = name and ("New appearance: " .. name) or "New appearance collected"
        local instanceName, location = WBF.Collections.CollectedWhere()
        WBF.Events.Add({
            category = WBF.Category.Collection,
            eventType = WBF.EventType.Appearance,
            dedupeKey = "appearance:" .. sourceID,
            text = text,
            meta = {
                sourceID = sourceID,
                name = name,
                itemID = itemID,
                quality = quality,
                icon = icon,
                instanceName = instanceName,
                location = location,
                iconAtlas = icon and nil or "transmog-icon-chat",
            },
        })
    end)
end
