local _, WBF = ...

WBF.Sample = {}

local function AddCharacter(db, guid, info, now)
    db.characters[guid] = {
        guid = guid,
        name = info.name,
        realm = info.realm,
        className = info.className,
        classFile = info.classFile,
        specName = info.specName,
        role = info.role,
        level = info.levelEnd,
        itemLevel = info.ilvlEnd,
        money = info.moneyEnd,
        lastSeenAt = now,
        updatedAt = now,
        discovered = true,
        firstSeen = now,
        sample = true,
    }
end

function WBF.Sample.Load(force)
    local db = WBF.Database.Get()
    local realEvents = 0
    for index = 1, #db.events do
        if not db.events[index].sample then
            realEvents = realEvents + 1
        end
    end
    if realEvents > 0 and not force then
        print("|cffd4af37WarbandFYI|r sample data was not added because real history already exists. Use /wbfyi sample force to mix in an example.")
        return
    end

    WBF.Database.ClearSample()

    local now = WBF.Time.Now()
    local dayStart = WBF.Time.StartOfDay(now)
    local miranoraEnd = math.max(dayStart + 120, now - 60)
    local startedAt = now - 80 * 60
    if startedAt < dayStart then
        startedAt = dayStart + 30
    end
    if miranoraEnd <= startedAt + 120 then
        startedAt = dayStart
        miranoraEnd = math.max(now, startedAt + 120)
    end
    local function At(fraction)
        return startedAt + math.floor((miranoraEnd - startedAt) * fraction)
    end
    local warriorEnd = At(0.55)
    local sessionId = WBF.Database.AllocSessionId()

    db.sessions[#db.sessions + 1] = {
        id = sessionId,
        startedAt = startedAt,
        endedAt = miranoraEnd,
        lastActivityAt = miranoraEnd,
        sample = true,
        segments = {
            { guid = "Player-0-SAMPLE-WARRIOR", startedAt = startedAt, endedAt = warriorEnd },
            { guid = "Player-0-SAMPLE-MIRANORA", startedAt = At(0.58), endedAt = miranoraEnd },
        },
    }

    -- Each character keeps their own gold. The first balance is a baseline.
    -- Net gold is only the later change on that character.
    local warriorBaseline = 38542 * 10000
    local warriorGold = 12000 * 10000
    local miranoraBaseline = 244201 * 10000
    local miranoraGold = 18300 * 10000
    local sampleSession = db.sessions[#db.sessions]
    sampleSession.goldByCharacter = {
        ["Player-0-SAMPLE-WARRIOR"] = {
            baseline = warriorBaseline,
            lastMoney = warriorBaseline + warriorGold,
            netChange = warriorGold,
            establishedAt = startedAt,
        },
        ["Player-0-SAMPLE-MIRANORA"] = {
            baseline = miranoraBaseline,
            lastMoney = miranoraBaseline + miranoraGold,
            netChange = miranoraGold,
            establishedAt = At(0.58),
        },
    }
    sampleSession.goldLedger = {
        { at = warriorEnd, guid = "Player-0-SAMPLE-WARRIOR", delta = warriorGold },
        { at = miranoraEnd, guid = "Player-0-SAMPLE-MIRANORA", delta = miranoraGold },
    }

    AddCharacter(db, "Player-0-SAMPLE-WARRIOR", {
        name = "Warrior",
        realm = "Azgalor",
        className = "Warrior",
        classFile = "WARRIOR",
        specName = "Protection",
        role = "TANK",
        levelEnd = 70,
        ilvlEnd = 290,
        moneyEnd = warriorBaseline + warriorGold,
    }, warriorEnd)

    AddCharacter(db, "Player-0-SAMPLE-MIRANORA", {
        name = "Miranora",
        realm = "Azgalor",
        className = "Druid",
        classFile = "DRUID",
        specName = "Balance",
        role = "DAMAGER",
        levelEnd = 70,
        ilvlEnd = 305,
        moneyEnd = miranoraBaseline + miranoraGold,
    }, miranoraEnd)

    local function Snapshot(at, guid, level, itemLevel, money)
        db.snapshots[#db.snapshots + 1] = {
            at = at,
            sessionId = sessionId,
            guid = guid,
            reason = "sample",
            level = level,
            itemLevel = itemLevel,
            money = money,
            sample = true,
        }
    end

    Snapshot(startedAt, "Player-0-SAMPLE-WARRIOR", 70, 260, warriorBaseline)
    Snapshot(warriorEnd, "Player-0-SAMPLE-WARRIOR", 70, 290, warriorBaseline + warriorGold)
    Snapshot(At(0.58), "Player-0-SAMPLE-MIRANORA", 70, 302, miranoraBaseline)
    Snapshot(miranoraEnd, "Player-0-SAMPLE-MIRANORA", 70, 305, miranoraBaseline + miranoraGold)

    local function Event(at, guid, eventType, category, text, meta, previous, newValue, delta)
        db.events[#db.events + 1] = {
            id = WBF.Database.AllocEventId(),
            at = at,
            sessionId = sessionId,
            guid = guid,
            category = category,
            eventType = eventType,
            previous = previous,
            new = newValue,
            delta = delta,
            text = text,
            meta = meta or {},
            sample = true,
        }
    end

    local warrior = "Player-0-SAMPLE-WARRIOR"
    local miranora = "Player-0-SAMPLE-MIRANORA"

    Event(At(0.04), warrior, WBF.EventType.InstanceEnter, WBF.Category.Instance, "Entered Firelands", {
        instanceName = "Firelands",
        instanceType = "raid",
        difficultyName = "25 Player (Heroic)",
        iconAtlas = "DungeonSkull",
    })

    local bosses = { "Beth'tilac", "Lord Rhyolith", "Shannox", "Alysrazor", "Baleroc", "Majordomo Staghelm", "Ragnaros" }
    for index = 1, #bosses do
        Event(At(0.08 + index * 0.05), warrior, WBF.EventType.BossKill, WBF.Category.Instance, bosses[index] .. " defeated", {
            encounterName = bosses[index],
            instanceName = "Firelands",
            instanceType = "raid",
            difficultyName = "25 Player (Heroic)",
            iconAtlas = "DungeonSkull",
        })
    end

    Event(At(0.36), warrior, WBF.EventType.Reputation, WBF.Category.Reputation, "Reputation with the Avengers of Hyjal +500", {
        faction = "Avengers of Hyjal",
        iconAtlas = "MajorFactions_MapIcons_Centaur_Major",
    }, nil, nil, 500)
    Event(At(0.42), warrior, WBF.EventType.Renown, WBF.Category.Reputation, "Renown with the Avengers of Hyjal  " .. WBF.Format.Progression(6, 7), {
        faction = "Avengers of Hyjal",
        iconAtlas = "MajorFactions_MapIcons_Centaur_Major",
    }, 6, 7, 1)
    Event(At(0.48), warrior, WBF.EventType.Delve, WBF.Category.Instance, "Delve completed: Earthcrawl Mines (Tier 8)", {
        name = "Earthcrawl Mines",
        tier = 8,
        iconAtlas = "delves-scenario-treasure-chest",
    }, nil, 8, nil)
    Event(At(0.52), warrior, WBF.EventType.ItemLevel, WBF.Category.Progress, "Item level increased to 290", {}, 260, 290, 30)
    Event(At(0.56), warrior, WBF.EventType.Profession, WBF.Category.Profession, "Blacksmithing  " .. WBF.Format.Progression(72, 81), {
        profession = "Blacksmithing",
        iconAtlas = "Professions-ChatIcon-Quality-Tier1",
    }, 72, 81, 9)
    Event(At(0.18), warrior, WBF.EventType.Quest, WBF.Category.Quest, "Quest completed: Legacy of the Firelords", {
        title = "Legacy of the Firelords",
        iconAtlas = "QuestNormal",
    })
    Event(At(0.24), warrior, WBF.EventType.WorldQuest, WBF.Category.Quest, "World Quest completed: Molten Front Supplies", {
        title = "Molten Front Supplies",
        worldQuest = true,
        iconAtlas = "worldquest-tracker-questmarker",
    })
    Event(At(0.32), warrior, WBF.EventType.Achievement, WBF.Category.Achievement, "Firelands", {
        achievementID = 5802,
        icon = "Interface\\Icons\\Achievement_Boss_Ragnaros",
    })

    local appearances = { "Mantle of the Molten Brood", "Cinderweb Leggings", "Flickering Shoulders", "Breastplate of the Incendiary Soul", "Helm of Blazing Glory", "Cowl of the Clicking Menace" }
    for index = 1, #appearances do
        Event(At(0.12 + index * 0.04), warrior, WBF.EventType.Appearance, WBF.Category.Collection, "New appearance: " .. appearances[index], {
            name = appearances[index],
            quality = 4,
            instanceName = "Firelands",
            iconAtlas = "transmog-icon-chat",
        })
    end

    Event(At(0.6), miranora, WBF.EventType.HousingDecor, WBF.Category.Collection, "New decor: Amani Ritual Totem", {
        decorID = 9001,
        name = "Amani Ritual Totem",
        firstTime = true,
        houseXP = 10,
        icon = "Interface\\Icons\\INV_Misc_Statue_02",
    })
    Event(At(0.62), miranora, WBF.EventType.HousingDecor, WBF.Category.Collection, "New decor: Amani Worship Candle", {
        decorID = 9002,
        name = "Amani Worship Candle",
        firstTime = true,
        houseXP = 10,
        icon = "Interface\\Icons\\INV_Misc_Statue_02",
    })
    Event(At(0.63), miranora, WBF.EventType.HousingAcquire, WBF.Category.Collection, "", {
        decorID = 9001,
        name = "Amani Ritual Totem",
        count = 3,
        duplicate = true,
        surface = false,
        icon = "Interface\\Icons\\INV_Misc_Statue_02",
    })
    Event(At(0.63), miranora, WBF.EventType.HousingXP, WBF.Category.Collection, "", {
        surface = false,
        houseXP = 20,
    }, nil, nil, 20)
    if type(db.housing) ~= "table" then
        db.housing = { collected = {}, favor = {} }
    end
    db.housing.collected = db.housing.collected or {}
    db.housing.collected["9001"] = {
        decorID = 9001,
        name = "Amani Ritual Totem",
        firstAt = At(0.6),
        guid = miranora,
        houseXP = 10,
        sample = true,
        icon = "Interface\\Icons\\INV_Misc_Statue_02",
    }
    db.housing.collected["9002"] = {
        decorID = 9002,
        name = "Amani Worship Candle",
        firstAt = At(0.62),
        guid = miranora,
        houseXP = 10,
        sample = true,
        icon = "Interface\\Icons\\INV_Misc_Statue_02",
    }

    Event(At(0.64), miranora, WBF.EventType.Mount, WBF.Category.Collection, "Ashes of Al'ar", {
        icon = "Interface\\Icons\\INV_Misc_SummerFest_BrazierOrange",
    })
    Event(At(0.72), miranora, WBF.EventType.Pet, WBF.Category.Collection, "Core Hound Pup captured", {
        captured = true,
        icon = "Interface\\Icons\\INV_Box_PetCarrier_01",
    })
    Event(At(0.8), miranora, WBF.EventType.InstanceEnter, WBF.Category.Instance, "Entered The Everbloom", {
        instanceName = "The Everbloom",
        instanceType = "party",
        keystone = true,
        difficultyName = "Mythic Keystone",
        iconAtlas = "QuestNormal",
    })
    Event(At(0.9), miranora, WBF.EventType.MythicPlus, WBF.Category.Instance, "The Everbloom +6 completed", {
        level = 6,
        onTime = true,
        timedText = "timed",
        iconAtlas = "challengeMode-icon-chest",
    }, nil, 6)
    Event(At(0.96), miranora, WBF.EventType.ItemLevel, WBF.Category.Progress, "Item level increased to 305", {}, 302, 305, 3)
    Event(At(0.88), miranora, WBF.EventType.Prey, WBF.Category.Prey, "Prey hunt completed: Sample Quarry (Nightmare)", {
        title = "Sample Quarry",
        difficulty = "Nightmare",
        completed = true,
        duration = 18 * 60,
        journey = 1000,
        journeyName = "Preyhunter's Journey",
    }, nil, nil, 1000)

    if WBF.Resources and WBF.Resources.LoadSample then
        WBF.Resources.LoadSample(sessionId, now, warrior, miranora)
    end

    print("|cffd4af37WarbandFYI|r loaded sample history. Remove it with /wbfyi clearsample.")
    local window = WBF.UI and WBF.UI.frame
    if window then
        window:SetView("week")
        if not window:IsShown() then
            window:Show()
        end
    end
end
