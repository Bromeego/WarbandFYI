local _, WBF = ...

-- Trigger kinds share one interface. Only WOW_EVENT is registered in this
-- phase. Later kinds plug in here without a new FYI store.
--
--   :IsAvailable()
--   :IsActive(trigger)
--   :GetOccurrenceKey(trigger)
--   :GetDisplayContext(trigger)
WBF.Triggers = {}

local providers = {}

function WBF.Triggers.Register(kind, provider)
    if type(kind) ~= "string" or kind == "" or type(provider) ~= "table" then
        return false
    end
    providers[kind] = provider
    return true
end

function WBF.Triggers.Provider(kind)
    if type(kind) ~= "string" then
        return nil
    end
    return providers[kind]
end

function WBF.Triggers.Known(kind)
    return providers[kind] ~= nil
end

local function Provider(trigger)
    if type(trigger) ~= "table" or type(trigger.type) ~= "string" then
        return nil
    end
    return providers[trigger.type]
end

function WBF.Triggers.IsAvailable(trigger)
    local provider = Provider(trigger)
    if not provider then
        return false
    end
    if type(provider.IsAvailable) ~= "function" then
        return true
    end
    return provider:IsAvailable() and true or false
end

function WBF.Triggers.IsActive(trigger)
    local provider = Provider(trigger)
    if not provider or type(provider.IsActive) ~= "function" then
        return false
    end
    return provider:IsActive(trigger) and true or false
end

function WBF.Triggers.GetOccurrenceKey(trigger)
    local provider = Provider(trigger)
    if not provider or type(provider.GetOccurrenceKey) ~= "function" then
        return nil
    end
    local key = provider:GetOccurrenceKey(trigger)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    return key
end

function WBF.Triggers.GetDisplayContext(trigger)
    local provider = Provider(trigger)
    if not provider or type(provider.GetDisplayContext) ~= "function" then
        return {
            active = false,
            type = type(trigger) == "table" and trigger.type or nil,
        }
    end
    local context = provider:GetDisplayContext(trigger)
    if type(context) ~= "table" then
        return { active = false, type = trigger.type }
    end
    return context
end
