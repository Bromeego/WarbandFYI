local _, WBF = ...

-- Pure balance-shift classification. Transfers are not earnings and not spending.
-- A character seen for the first time is a sync, never fabricated history.

WBF.ResourceShift = {}

local SYNC = "sync"
local TRANSFER = "transfer"
local GAIN = "gain_observed"
local LOSS = "loss_observed"

function WBF.ResourceShift.Classify(previous, nextAmounts)
    previous = previous or {}
    nextAmounts = nextAmounts or {}
    local result = {}
    local pending = {}
    local net = 0
    local seen = {}

    local function Consider(guid)
        if seen[guid] then
            return
        end
        seen[guid] = true
        local oldAmount = previous[guid]
        local newAmount = nextAmounts[guid]
        if oldAmount == nil then
            if type(newAmount) == "number" and newAmount ~= 0 then
                result[#result + 1] = {
                    guid = guid,
                    delta = newAmount,
                    classification = SYNC,
                }
            end
            return
        end
        if type(newAmount) ~= "number" then
            return
        end
        local delta = newAmount - oldAmount
        if delta == 0 then
            return
        end
        net = net + delta
        pending[#pending + 1] = { guid = guid, delta = delta }
    end

    for guid in pairs(nextAmounts) do
        Consider(guid)
    end
    for guid in pairs(previous) do
        Consider(guid)
    end

    table.sort(pending, function(a, b)
        if a.guid == b.guid then
            return a.delta < b.delta
        end
        return tostring(a.guid) < tostring(b.guid)
    end)

    if #pending == 0 then
        return result, net
    end

    if net == 0 then
        for index = 1, #pending do
            local row = pending[index]
            result[#result + 1] = {
                guid = row.guid,
                delta = row.delta,
                classification = TRANSFER,
            }
        end
        return result, net
    end

    if #pending == 1 then
        local row = pending[1]
        result[#result + 1] = {
            guid = row.guid,
            delta = row.delta,
            classification = row.delta > 0 and GAIN or LOSS,
        }
        return result, net
    end

    local positive, negative = 0, 0
    for index = 1, #pending do
        local delta = pending[index].delta
        if delta > 0 then
            positive = positive + delta
        else
            negative = negative - delta
        end
    end

    local overlap = math.min(positive, negative)
    local remainPositive = overlap
    local remainNegative = overlap
    for index = 1, #pending do
        local row = pending[index]
        if row.delta > 0 then
            local transferPart = math.min(row.delta, remainPositive)
            remainPositive = remainPositive - transferPart
            local progress = row.delta - transferPart
            if transferPart ~= 0 then
                result[#result + 1] = {
                    guid = row.guid,
                    delta = transferPart,
                    classification = TRANSFER,
                }
            end
            if progress ~= 0 then
                result[#result + 1] = {
                    guid = row.guid,
                    delta = progress,
                    classification = GAIN,
                }
            end
        else
            local magnitude = -row.delta
            local transferPart = math.min(magnitude, remainNegative)
            remainNegative = remainNegative - transferPart
            local progress = magnitude - transferPart
            if transferPart ~= 0 then
                result[#result + 1] = {
                    guid = row.guid,
                    delta = -transferPart,
                    classification = TRANSFER,
                }
            end
            if progress ~= 0 then
                result[#result + 1] = {
                    guid = row.guid,
                    delta = -progress,
                    classification = LOSS,
                }
            end
        end
    end
    return result, net
end
