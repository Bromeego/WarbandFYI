local _, WBF = ...

-- Collection Source Registry: curated sources, never automatically activated.
-- A mountSpellID is the spell learned by the mount, NOT its loot item ID or
-- Mount Journal ID. Add new sources only after verifying the encounter.
-- Keep difficulty metadata separate from the instance/boss used for lockouts.
WBF.CollectionSources = {
    Entries = {
        thoridal = {
            instance = "Sunwell Plateau", boss = "Kil'jaeden", itemIDs = {34334},
            collectionType = "achievement", achievementID = 725,
            restrictions = {equipClasses = {"HUNTER", "WARRIOR", "ROGUE"}},
        },
        onyxian = {
            instance = "Onyxia's Lair", boss = "Onyxia", itemIDs = {49636},
            collectionType = "mount", mountSpellID = 69395,
        },
        southwind = {
            instance = "Throne of the Four Winds", boss = "Al'Akir", itemIDs = {63041},
            collectionType = "mount", mountSpellID = 88744,
        },
        ashes = {
            instance = "The Eye", boss = "Kael'thas Sunstrider", itemIDs = {32458},
            collectionType = "mount", mountSpellID = 40192,
        },
        invincible = {
            instance = "Icecrown Citadel", boss = "The Lich King", itemIDs = {50818},
            collectionType = "mount", mountSpellID = 72286,
            difficulty = "25-player Heroic", note = "Requires 25-player Heroic",
        },
        jikun = {
            instance = "Throne of Thunder", boss = "Ji-Kun", itemIDs = {95059},
            title = "Clutch of Ji-Kun", aliases = {"Ji-Kun", "Ji Kun", "Clutch of Ji Kun"},
            collectionType = "mount", mountSpellID = 139448,
            note = "Normal/Heroic; not Raid Finder",
            -- 7 is the legacy Raid Finder difficulty. 17 is the modern one.
            -- Neither lockout spends a Normal or Heroic Ji-Kun attempt.
            ignoreDifficulties = { [7] = true, [17] = true },
        },
        mimiron = {
            instance = "Ulduar", boss = "Yogg-Saron", itemIDs = {45693},
            collectionType = "mount", mountSpellID = 63796,
            difficulty = "Zero Keepers", note = "Zero Keeper assistance for normal drop",
        },
    },
    Keys = {"thoridal", "onyxian", "southwind", "ashes", "invincible", "mimiron", "jikun"},
}
