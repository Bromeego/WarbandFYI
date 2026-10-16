local _, WBF = ...

WBF.Events = {}

WBF.EventType = {
    ItemLevel = "itemLevel",
    Level = "level",
    BossKill = "bossKill",
    InstanceEnter = "instanceEnter",
    Quest = "quest",
    WorldQuest = "worldQuest",
    WorldEvent = "worldEvent",
    Achievement = "achievement",
    Mount = "mount",
    Pet = "pet",
    PetBattle = "petBattle",
    Appearance = "appearance",
    HousingDecor = "housingDecor",
    HousingAcquire = "housingAcquire",
    HousingXP = "housingXP",
    MythicPlus = "mythicPlus",
    Reputation = "reputation",
    Renown = "renown",
    Delve = "delve",
    Profession = "profession",
    Prey = "prey",
    Resource = "resource",
    RareKill = "rareKill",
}

WBF.Category = {
    Progress = "progress",
    Instance = "instance",
    Quest = "quest",
    Achievement = "achievement",
    Collection = "collection",
    Reputation = "reputation",
    Profession = "profession",
    Prey = "prey",
    Resource = "resource",
}

local MAX_EVENTS = 8000
local TRIM_TO = 7000

function WBF.Events.Add(partial)
    if not WBF.Database.IsReady() then
        return nil
    end

    if partial.dedupeKey and WBF.Database.HasDedupe(partial.dedupeKey) then
        return nil
    end

    local character = WBF.Characters.GetCurrent()
    local session = WBF.Sessions.Touch()
    local db = WBF.Database.Get()

    local event = {
        id = WBF.Database.AllocEventId(),
        at = partial.at or WBF.Time.Now(),
        sessionId = partial.sessionId or (session and session.id) or nil,
        guid = partial.guid or (character and character.guid) or nil,
        category = partial.category,
        eventType = partial.eventType,
        previous = partial.previous,
        new = partial.new,
        delta = partial.delta,
        text = partial.text or "",
        meta = partial.meta or {},
        sample = partial.sample,
    }

    db.events[#db.events + 1] = event
    if partial.dedupeKey then
        if partial.dedupeTransient then
            WBF.Database.MarkDedupe(partial.dedupeKey, event.at or WBF.Time.Now())
        else
            WBF.Database.MarkDedupe(partial.dedupeKey)
        end
    end

    if #db.events > MAX_EVENTS then
        local fresh = {}
        local startAt = #db.events - TRIM_TO + 1
        for index = 1, startAt - 1 do
            if WBF.Database.FoldDiscardedEvent then
                WBF.Database.FoldDiscardedEvent(db.events[index])
            end
        end
        for index = startAt, #db.events do
            fresh[#fresh + 1] = db.events[index]
        end
        db.events = fresh
    end

    WBF.Debug.Log(event.eventType, event.text)
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
    if WBF.UI and WBF.UI.RequestRefresh then
        WBF.UI.RequestRefresh()
    end
    return event
end
