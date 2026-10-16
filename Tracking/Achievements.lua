local _, WBF = ...

WBF.Achievements = {}

function WBF.Achievements.Register(bus)
    bus:On("ACHIEVEMENT_EARNED", function(achievementID, alreadyEarned)
        achievementID = tonumber(achievementID)
        if not achievementID then
            return
        end
        if alreadyEarned == true or alreadyEarned == 1 then
            return
        end

        local _, name, points, _, _, _, _, _, _, icon, _, _, _, _, isStatistic = GetAchievementInfo(achievementID)
        if isStatistic then
            return
        end
        if not name or name == "" then
            name = "Achievement " .. achievementID
        end

        WBF.Events.Add({
            category = WBF.Category.Achievement,
            eventType = WBF.EventType.Achievement,
            dedupeKey = "achievement:" .. achievementID,
            text = name,
            meta = {
                achievementID = achievementID,
                points = points,
                icon = icon,
            },
        })
    end)
end
