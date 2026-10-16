local _, WBF = ...

WBF.CharacterTrack = {}

local ScheduleItemLevelCommit

local function ReadyLevel(level)
    return level and level > 0
end

local function ReadyItemLevel(itemLevel, level)
    if not itemLevel or itemLevel <= 0 then
        if level and level >= 10 then
            return false
        end
    end
    return itemLevel ~= nil and itemLevel > 0
end

function WBF.CharacterTrack.ReadLive()
    local level = WBF.Format.AsNumber(UnitLevel("player"))
    local equipped
    if GetAverageItemLevel then
        local _, equippedAverage = GetAverageItemLevel()
        equipped = WBF.Format.Round(equippedAverage)
    end
    local money = nil
    if GetMoney then
        money = WBF.Format.AsNumber(GetMoney())
    end
    return level, equipped, money
end

function WBF.CharacterTrack.Capture(reason)
    local character = WBF.Characters.GetCurrent()
    if not character then
        character = WBF.Characters.Update()
    end
    if not character then
        return
    end

    local level, itemLevel, money = WBF.CharacterTrack.ReadLive()
    local now = WBF.Time.Now()
    character.lastSeenAt = now
    character.updatedAt = now

    local previousLevel = character.level
    local previousItemLevel = character.itemLevel

    if ReadyLevel(level) then
        character.level = level
        if previousLevel and level > previousLevel then
            WBF.Events.Add({
                category = WBF.Category.Progress,
                eventType = WBF.EventType.Level,
                previous = previousLevel,
                new = level,
                delta = level - previousLevel,
                text = "Reached level " .. level,
                meta = { iconAtlas = "charactercreate-icon-customize-body" },
            })
        end
    end

    if ReadyItemLevel(itemLevel, level or character.level) then
        if not previousItemLevel then
            character.itemLevel = itemLevel
        elseif itemLevel ~= previousItemLevel then
            ScheduleItemLevelCommit()
        end
    end

    -- GetMoney can briefly report 0 while the character is still entering the
    -- world, at any level. Ignore that reading so it is not stored as a drop.
    -- Observe runs before the balance is overwritten so a known wallet is still
    -- visible if a zero slips through.
    if money == 0 and not WBF.Economy.trustMoney and (character.money == nil or character.money > 0) then
        money = nil
    end
    if money ~= nil and money > 0 then
        WBF.Economy.trustMoney = true
    end
    if money ~= nil then
        WBF.GoldTracker.Observe(character.guid, money)
        character.money = money
    end

    WBF.Database.AddSnapshot({
        at = now,
        sessionId = WBF.Sessions.GetActiveId(),
        guid = character.guid,
        reason = reason,
        level = character.level,
        itemLevel = character.itemLevel,
        money = character.money,
    })
end

function WBF.CharacterTrack.NoteMoney(money)
    local character = WBF.Characters.GetCurrent()
    if not character or money == nil then
        return
    end
    character.money = money
    character.updatedAt = WBF.Time.Now()
    character.lastSeenAt = character.updatedAt
end

local ILVL_CONFIRM_SECONDS = 1.5
local ilvlChangedAt = 0
local ilvlWaiting = false

local function MonoTime()
    if GetTime then
        return GetTime()
    end
    return WBF.Time.Now()
end

local function CommitItemLevel()
    ilvlWaiting = false
    local character = WBF.Characters.GetCurrent()
    if not character then
        return
    end
    local level, itemLevel = WBF.CharacterTrack.ReadLive()
    if not ReadyItemLevel(itemLevel, level or character.level) then
        return
    end
    local previous = character.itemLevel
    if not previous or itemLevel == previous then
        return
    end
    local increased = itemLevel > previous
    character.itemLevel = itemLevel
    character.updatedAt = WBF.Time.Now()
    WBF.Events.Add({
        category = WBF.Category.Progress,
        eventType = WBF.EventType.ItemLevel,
        previous = previous,
        new = itemLevel,
        delta = itemLevel - previous,
        text = increased and ("Item level increased to " .. itemLevel) or ("Item level changed to " .. itemLevel),
        meta = {
            decreased = not increased,
            iconAtlas = "charactercreate-icon-customize-weapon",
        },
    })
    if WBF.Database and WBF.Database.AddSnapshot then
        WBF.Database.AddSnapshot({
            sessionId = WBF.Sessions and WBF.Sessions.GetActiveId and WBF.Sessions.GetActiveId() or nil,
            guid = character.guid,
            reason = "itemLevel",
            level = character.level,
            itemLevel = itemLevel,
            money = character.money,
        })
    end
end

local function PumpItemLevel()
    local remain = ILVL_CONFIRM_SECONDS - (MonoTime() - ilvlChangedAt)
    if remain > 0.05 and C_Timer and C_Timer.After then
        C_Timer.After(remain, PumpItemLevel)
        return
    end
    CommitItemLevel()
end

function ScheduleItemLevelCommit()
    ilvlChangedAt = MonoTime()
    if ilvlWaiting then
        return
    end
    ilvlWaiting = true
    if C_Timer and C_Timer.After then
        C_Timer.After(ILVL_CONFIRM_SECONDS, PumpItemLevel)
        return
    end
    CommitItemLevel()
end

function WBF.CharacterTrack.ScheduleItemLevelCheck()
    WBF.CharacterTrack.Capture("equipment")
end

function WBF.CharacterTrack.Register(bus)
    bus:On("PLAYER_LEVEL_UP", function()
        WBF.CharacterTrack.Capture("level")
    end)
    bus:On("PLAYER_EQUIPMENT_CHANGED", function()
        WBF.CharacterTrack.ScheduleItemLevelCheck()
    end)
    bus:On("PLAYER_AVG_ITEM_LEVEL_UPDATE", function()
        WBF.CharacterTrack.ScheduleItemLevelCheck()
    end)
    bus:On("PLAYER_SPECIALIZATION_CHANGED", function(unit)
        if not unit or unit == "player" then
            WBF.Characters.Update()
        end
    end)
end
