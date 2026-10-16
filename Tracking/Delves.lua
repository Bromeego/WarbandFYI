local _, WBF = ...

WBF.Delves = {}

-- A finished delve is C_PartyInfo.IsDelveComplete, fired with the scenario
-- completion event. The tier comes from C_DelvesUI.GetActiveDelveTier (12.0.5+).
-- The name and tier are cached while the delve is in progress because both
-- can clear at the same moment the completion flag appears. Abandoned runs
-- are not recorded.

local active = nil
local lastKey = nil
local lastAt = 0
local waiting = false

local function InDelve()
    return C_PartyInfo and WBF.Format.SafeBoolean(C_PartyInfo.IsDelveInProgress) == true
end

local function DelveComplete()
    return C_PartyInfo and WBF.Format.SafeBoolean(C_PartyInfo.IsDelveComplete) == true
end

function WBF.Delves.ConsumesBossKill()
    if InDelve() then
        return true
    end
    if lastAt <= 0 or (WBF.Time.Now() - lastAt) > 8 then
        return false
    end
    -- The delve's own encounter can land just after the scenario flag clears.
    -- A raid, dungeon, or battleground the player is already in is not that kill.
    if IsInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "raid" or instanceType == "party" or instanceType == "pvp" or instanceType == "arena") then
            return false
        end
    end
    return true
end

local function ReadName()
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo then
        local ok, info = pcall(C_ScenarioInfo.GetScenarioInfo)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    if C_Scenario and C_Scenario.GetInfo then
        local ok, name = pcall(C_Scenario.GetInfo)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

local function ReadTier()
    if not C_DelvesUI or not C_DelvesUI.GetActiveDelveTier then
        return nil
    end
    local ok, info = pcall(C_DelvesUI.GetActiveDelveTier)
    if not ok or info == nil then
        return nil
    end
    local tier = info
    if type(info) == "table" then
        tier = info.tier
    end
    tier = WBF.Format.AsNumber(tier)
    if tier and tier > 0 then
        return math.floor(tier + 0.5)
    end
    return nil
end

local function Remember()
    if not InDelve() then
        if active and not active.leftAt then
            active.leftAt = WBF.Time.Now()
        end
        if active and active.leftAt and WBF.Time.Now() - active.leftAt > 20 then
            active = nil
        end
        return
    end

    active = active or {}
    active.leftAt = nil
    local name = ReadName()
    local tier = ReadTier()
    if name then
        active.name = name
    end
    if tier then
        active.tier = tier
    end
end

local function CacheFresh()
    if not active then
        return false
    end
    if not active.leftAt then
        return true
    end
    return WBF.Time.Now() - active.leftAt <= 20
end

local function Commit()
    local name = (CacheFresh() and active and active.name) or ReadName() or "Delve"
    local tier = (CacheFresh() and active and active.tier) or ReadTier()
    local key = name .. ":" .. tostring(tier or 0)
    local now = WBF.Time.Now()
    active = nil
    waiting = false
    if key == lastKey and now - lastAt < 5 then
        return
    end
    lastKey = key
    lastAt = now

    local text = "Delve completed: " .. name
    if tier then
        text = text .. " (Tier " .. tier .. ")"
    end
    WBF.Events.Add({
        category = WBF.Category.Instance,
        eventType = WBF.EventType.Delve,
        text = text,
        new = tier,
        meta = {
            name = name,
            tier = tier,
            iconAtlas = "delves-scenario-treasure-chest",
        },
    })
end

local function TryComplete(delayed)
    Remember()
    if not DelveComplete() then
        if not delayed and CacheFresh() and not waiting and C_Timer and C_Timer.After then
            waiting = true
            C_Timer.After(0.25, function()
                waiting = false
                if DelveComplete() then
                    Commit()
                end
            end)
        end
        return
    end
    Commit()
end

function WBF.Delves.Refresh()
    Remember()
end

function WBF.Delves.Register(bus)
    bus:On("SCENARIO_UPDATE", Remember)
    bus:On("SCENARIO_CRITERIA_UPDATE", Remember)
    bus:On("ACTIVE_DELVE_DATA_UPDATE", Remember)
    bus:On("WALK_IN_DATA_UPDATE", Remember)
    bus:On("PLAYER_ENTERING_WORLD", Remember)
    bus:On("SCENARIO_COMPLETED", function()
        TryComplete(false)
    end)
end
