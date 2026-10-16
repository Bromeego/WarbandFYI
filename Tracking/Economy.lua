local _, WBF = ...

WBF.Economy = {}

-- PLAYER_MONEY reports the logged-in character's personal gold. GoldTracker
-- records that against the same character's session baseline. The first
-- reading is not a transaction.

local lastSnapshotAt = 0

function WBF.Economy.Register(bus)
    bus:On("PLAYER_MONEY", function()
        if not GetMoney then
            return
        end
        local money = WBF.Format.AsNumber(GetMoney())
        if money == nil then
            return
        end
        local character = WBF.Characters.GetCurrent()
        if not character then
            return
        end
        if money == 0 and not WBF.Economy.trustMoney and (character.money == nil or character.money > 0) then
            return
        end
        if money > 0 then
            WBF.Economy.trustMoney = true
        end
        local previous = character.money
        WBF.CharacterTrack.NoteMoney(money)
        WBF.GoldTracker.Observe(character.guid, money)
        if previous == money then
            return
        end
        local now = WBF.Time.Now()
        if (now - lastSnapshotAt) >= 60 then
            lastSnapshotAt = now
            WBF.Database.AddSnapshot({
                at = now,
                sessionId = WBF.Sessions.GetActiveId(),
                guid = character.guid,
                reason = "money",
                level = character.level,
                itemLevel = character.itemLevel,
                money = money,
            })
        end
        if WBF.UI and WBF.UI.RequestRefresh then
            WBF.UI.RequestRefresh()
        end
    end)
end
