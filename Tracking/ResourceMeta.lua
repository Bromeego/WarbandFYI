local _, WBF = ...

-- `era` describes the resource's actual expansion or system ownership.
-- It does not necessarily match Blizzard's current Currency tab category.
-- Recurring, event, and evergreen resources that span expansions belong under
-- cross_expansion even if Blizzard currently displays them in the current expansion UI.
--
-- `status` describes confirmed current earnability.
--
-- active:
--   A normal earning path is confirmed to still exist.
--
-- retired:
--   No normal earning path remains.
--
-- unknown:
--   The resource is identified and classified, but current
--   earnability has not yet been confirmed.
--
-- An ID with no ResourceMeta entry is different: it is
-- unregistered/unclassified and is displayed under Unknown / Other.
-- A registered resource with status "unknown" stays in its era section.
--
-- `review` is an unresolved question. Only a non-empty review belongs in
-- Needs Review. `note` is established context and does not.
--
-- Old does not mean retired. An expansion currency stays in that era with
-- status "active" while its original content still awards it. A current-era
-- resource can later become "retired" without changing era.
-- Example: { era = "battle_for_azeroth", status = "active", kind = "expansion" }
-- Example: { era = "legion", status = "active", kind = "expansion" }
-- Example: { era = "midnight", status = "retired", kind = "expansion" }
-- `kind` describes the system: expansion, event, timewalking, profession, pvp,
-- evergreen, or miscellaneous. Kind does not choose the section.
--
-- Lookup is by currency or item id. Unknown ids stay visible under Unknown / Other.
-- To support a new expansion, add one era row and classify its currencies here.
-- CURRENT_EXPANSION_FALLBACK is only used when GetExpansionLevel is unavailable.

WBF.ResourceMeta = {}

local CURRENT_EXPANSION_FALLBACK = 11

local function BlizzardExpansion(names, fallback)
    for index = 1, #names do
        local value = _G[names[index]]
        if type(value) == "number" then
            return value
        end
    end
    return fallback
end

local ERA_DEFS = {
    { id = "midnight", label = "Midnight", expansion = BlizzardExpansion({ "LE_EXPANSION_MIDNIGHT" }, 11) },
    { id = "war_within", label = "War Within", expansion = BlizzardExpansion({ "LE_EXPANSION_WAR_WITHIN", "LE_EXPANSION_THE_WAR_WITHIN" }, 10) },
    { id = "dragonflight", label = "Dragonflight", expansion = BlizzardExpansion({ "LE_EXPANSION_DRAGONFLIGHT" }, 9) },
    { id = "shadowlands", label = "Shadowlands", expansion = BlizzardExpansion({ "LE_EXPANSION_SHADOWLANDS" }, 8) },
    { id = "battle_for_azeroth", label = "Battle for Azeroth", expansion = BlizzardExpansion({ "LE_EXPANSION_BATTLE_FOR_AZEROTH" }, 7) },
    { id = "legion", label = "Legion", expansion = BlizzardExpansion({ "LE_EXPANSION_LEGION" }, 6) },
    { id = "warlords_of_draenor", label = "Warlords of Draenor", expansion = BlizzardExpansion({ "LE_EXPANSION_WARLORDS_OF_DRAENOR" }, 5) },
    { id = "mists_of_pandaria", label = "Mists of Pandaria", expansion = BlizzardExpansion({ "LE_EXPANSION_MISTS_OF_PANDARIA" }, 4) },
    { id = "cataclysm", label = "Cataclysm", expansion = BlizzardExpansion({ "LE_EXPANSION_CATACLYSM" }, 3) },
    { id = "wrath_of_the_lich_king", label = "Wrath of the Lich King", expansion = BlizzardExpansion({ "LE_EXPANSION_WRATH_OF_THE_LICH_KING" }, 2) },
    { id = "burning_crusade", label = "Burning Crusade", expansion = BlizzardExpansion({ "LE_EXPANSION_BURNING_CRUSADE" }, 1) },
    { id = "classic", label = "Classic", expansion = BlizzardExpansion({ "LE_EXPANSION_CLASSIC" }, 0) },
    { id = "cross_expansion", label = "Cross-Expansion / Events", order = -1 },
    { id = "unknown", label = "Unknown / Other", order = -2 },
}

local erasById = {}
local eraByExpansion = {}
local ordered = {}

for index = 1, #ERA_DEFS do
    local era = ERA_DEFS[index]
    if era.order == nil then
        era.order = era.expansion or 0
    end
    erasById[era.id] = era
    if type(era.expansion) == "number" then
        eraByExpansion[era.expansion] = era.id
    end
    ordered[index] = era
end

table.sort(ordered, function(a, b)
    if a.order == b.order then
        return a.id < b.id
    end
    return a.order > b.order
end)

local currencies = {}
local items = {}

local function Add(store, id, era, status, kind, extra)
    if not erasById[era] then
        return
    end
    local row = { era = era, status = status, kind = kind }
    if type(extra) == "table" then
        if type(extra.note) == "string" and extra.note ~= "" then
            row.note = extra.note
        end
        if type(extra.review) == "string" and extra.review ~= "" then
            row.review = extra.review
        end
    end
    store[id] = row
end

local function AddCurrencies(era, status, kind, ids)
    for index = 1, #ids do
        Add(currencies, ids[index], era, status, kind)
    end
end

local function AddItems(era, status, kind, ids)
    for index = 1, #ids do
        Add(items, ids[index], era, status, kind)
    end
end

-- Midnight expansion content. Not every currency shown in the Midnight tab belongs here.
AddCurrencies("midnight", "active", "expansion", {
    3310, -- Coffer Key Shards. Current Midnight currency, not the retired War Within shard item.
    3316, -- Voidlight Marl
    3377, -- Unalloyed Abundance
    3379, -- Brimming Arcana
    3405, -- Field Accolade
})
AddCurrencies("midnight", "active", "profession", {
    3256, -- Artisan Alchemist's Moxie
    3257, -- Artisan Blacksmith's Moxie
    3258, -- Artisan Enchanter's Moxie
    3259, -- Artisan Engineer's Moxie
    3260, -- Artisan Herbalist's Moxie
    3261, -- Artisan Scribe's Moxie
    3262, -- Artisan Jewelcrafter's Moxie
    3263, -- Artisan Leatherworker's Moxie
    3264, -- Artisan Miner's Moxie
    3265, -- Artisan Skinner's Moxie
    3266, -- Artisan Tailor's Moxie
})

-- War Within. These stay here even though some are still earned and spent.
AddCurrencies("war_within", "active", "expansion", {
    2815, -- Resonance Crystals
    3056, -- Kej
    3090, -- Flame-Blessed Iron. Siren Isle, patch 11.0.7.
})
AddCurrencies("war_within", "retired", "expansion", {
    3008, -- Valorstones. Removed in Midnight.
})
Add(currencies, 3089, "war_within", "retired", "expansion", {
    note = "Currency from the limited-time Radiant Echoes pre-expansion event.",
})

-- Dragonflight world currencies are still awarded by that content.
AddCurrencies("dragonflight", "active", "expansion", {
    2003, -- Dragon Isles Supplies
    2118, -- Elemental Overflow
    2594, -- Paracausal Flakes. Dragonflight Time Rifts, not the Timewalking badge.
    2650, -- Emerald Dewdrop
    2777, -- Dream Infusion
})
Add(currencies, 2134, "dragonflight", "active", "miscellaneous", {
    note = "Grants Cobalt Assembly reputation; treated as miscellaneous rather than a spend wallet.",
})
AddCurrencies("dragonflight", "active", "expansion", {
    2105, -- Purified Arcane Energy
    2122, -- Storm Sigil
})
Add(currencies, 2011, "dragonflight", "unknown", "expansion", {
    review = "Confirm whether players can currently earn Effigy Adornments from Dragonflight Major Hunts.",
})
Add(currencies, 2045, "dragonflight", "retired", "expansion", {
    note = "Dragonriding talent currency replaced by the Skyriding Proficiency system in The War Within.",
})
Add(currencies, 2245, "dragonflight", "retired", "expansion", {
    note = "Dragonflight gear-upgrade currency removed in patch 11.0.2.",
})

AddCurrencies("shadowlands", "active", "expansion", {
    1767, -- Stygia
    1813, -- Reservoir Anima
    1816, -- Sinstone Fragments
    1820, -- Infused Ruby
    1828, -- Soul Ash
    1885, -- Grateful Offering
    1904, -- Tower Knowledge
    1906, -- Soul Cinders
    1931, -- Cataloged Research
    1977, -- Stygian Ember
    1979, -- Cyphers of the First Ones
    2009, -- Cosmic Flux
})
Add(currencies, 1754, "shadowlands", "retired", "expansion", {
    note = "Currency from the limited-time Shadowlands Death's Rising pre-expansion event.",
})

AddCurrencies("battle_for_azeroth", "active", "expansion", {
    1560, -- War Resources. Still awarded by Battle for Azeroth world content.
    1710, -- Seafarer's Dubloon. Island Expeditions, including solo queue.
    1716, -- Honorbound Service Medal. Arathi and Darkshore world quests.
    1717, -- 7th Legion Service Medal. Arathi and Darkshore world quests.
    1580, -- Seal of Wartorn Fate
    1721, -- Prismatic Manapearl
})
Add(currencies, 1719, "battle_for_azeroth", "active", "expansion", {
    note = "Original Battle for Azeroth currency, still earned from original BFA content. Distinct from Displaced Corrupted Mementos.",
})
Add(currencies, 1755, "battle_for_azeroth", "active", "expansion", {
    note = "Original Battle for Azeroth Horrific Visions currency, still earned from original BFA content.",
})
Add(currencies, 1803, "battle_for_azeroth", "active", "expansion", {
    note = "Original Battle for Azeroth currency, still earned from original BFA content.",
})
Add(currencies, 1565, "battle_for_azeroth", "retired", "expansion", {
    note = "Planned Island Expedition currency implementation did not survive the Battle for Azeroth beta.",
})
Add(currencies, 1718, "battle_for_azeroth", "retired", "expansion", {
    note = "Remaining balances were converted to silver when Shadowlands launched.",
})

AddCurrencies("legion", "active", "expansion", {
    1149, -- Sightless Eye
    1155, -- Ancient Mana
    1220, -- Order Resources
    1226, -- Nethershard
    1268, -- Timeworn Artifact
    1275, -- Curious Coin
    1314, -- Lingering Soul Fragment
    1342, -- Legionfall War Supplies
    1416, -- Coins of Air
    1508, -- Veiled Argunite
    1533, -- Wakening Essence
})
Add(currencies, 1273, "legion", "active", "expansion") -- Seal of Broken Fate

AddCurrencies("warlords_of_draenor", "active", "expansion", {
    823,  -- Apexis Crystal
    824,  -- Garrison Resources
    944,  -- Artifact Fragment
    980,  -- Dingy Iron Coins
    1101, -- Oil
})
AddCurrencies("warlords_of_draenor", "active", "expansion", {
    994,  -- Seal of Tempered Fate
    1129, -- Seal of Inevitable Fate
})

AddCurrencies("mists_of_pandaria", "active", "expansion", {
    697, -- Elder Charm of Good Fortune
    738, -- Lesser Charm of Good Fortune
    777, -- Timeless Coin
    810, -- Black Iron Fragment
})
Add(currencies, 789, "mists_of_pandaria", "active", "pvp") -- Bloody Coin. Timeless Isle.
Add(currencies, 402, "mists_of_pandaria", "active", "profession") -- Ironpaw Token. Halfhill cooking.
Add(currencies, 752, "mists_of_pandaria", "unknown", "expansion", {
    review = "Verify in current Retail whether Mistweaver Ai still sells Mogu Rune of Fate for Timeless Coins.",
})
Add(currencies, 776, "mists_of_pandaria", "active", "expansion") -- Warforged Seal
Add(currencies, 698, "mists_of_pandaria", "retired", "profession", {
    note = "Planned Mists of Pandaria Jewelcrafting currency that was never implemented in the live game.",
})

AddCurrencies("cataclysm", "active", "expansion", {
    416, -- Mark of the World Tree
    614, -- Mote of Darkness
    615, -- Essence of Corrupted Deathwing
})
Add(currencies, 391, "cataclysm", "active", "pvp") -- Tol Barad Commendation
Add(currencies, 361, "cataclysm", "retired", "profession") -- Illustrious Jewelcrafter's Token

Add(currencies, 241, "wrath_of_the_lich_king", "active", "expansion") -- Champion's Seal. Argent Tournament.
AddCurrencies("wrath_of_the_lich_king", "retired", "expansion", {
    101, -- Emblem of Heroism
    102, -- Emblem of Valor
    221, -- Emblem of Conquest
    301, -- Emblem of Triumph
    341, -- Emblem of Frost
})
Add(currencies, 61, "wrath_of_the_lich_king", "retired", "profession") -- Dalaran Jewelcrafter's Token
Add(currencies, 81, "wrath_of_the_lich_king", "active", "profession") -- Epicurean's Award
AddCurrencies("wrath_of_the_lich_king", "retired", "pvp", {
    103, -- Arena Points. Removed.
    104, -- Honor Points. Deprecated.
    124, -- Strand of the Ancients Mark of Honor. Historical currency, not item 137642.
    126, -- Wintergrasp Mark of Honor. Historical currency, not item 137642.
    181, -- Honor Points. Deprecated.
    321, -- Isle of Conquest Mark of Honor. Historical currency, not item 137642.
})

Add(currencies, 1704, "burning_crusade", "active", "expansion", {
    note = "Burning Crusade content. The currency ID was added in 8.0.1.",
})
Add(currencies, 123, "burning_crusade", "retired", "pvp") -- Eye of the Storm Mark of Honor. Historical currency, not item 137642.

-- Classic battleground currencies. Historical marks, not the modern Mark of Honor item.
AddCurrencies("classic", "retired", "pvp", {
    121, -- Alterac Valley Mark of Honor
    122, -- Arathi Basin Mark of Honor
    125, -- Warsong Gulch Mark of Honor
})

-- Archaeology fragments belong to the expansion that added that fragment, not to one shared bucket.
AddCurrencies("cataclysm", "active", "profession", {
    384, -- Dwarf Archaeology Fragment
    385, -- Troll Archaeology Fragment
    393, -- Fossil Archaeology Fragment
    394, -- Night Elf Archaeology Fragment
    397, -- Orc Archaeology Fragment
    398, -- Draenei Archaeology Fragment
    399, -- Vrykul Archaeology Fragment
    400, -- Nerubian Archaeology Fragment
    401, -- Tol'vir Archaeology Fragment
})
AddCurrencies("mists_of_pandaria", "active", "profession", {
    676, -- Pandaren Archaeology Fragment
    677, -- Mogu Archaeology Fragment
})
Add(currencies, 754, "mists_of_pandaria", "active", "profession", {
    note = "Mists of Pandaria archaeology content; the currency ID itself was added in 6.0.1.",
})
AddCurrencies("warlords_of_draenor", "active", "profession", {
    821, -- Draenor Clans Archaeology Fragment
    828, -- Ogre Archaeology Fragment
    829, -- Arakkoa Archaeology Fragment
})
AddCurrencies("legion", "active", "profession", {
    1172, -- Highborne Archaeology Fragment
    1173, -- Highmountain Tauren Archaeology Fragment
    1174, -- Demonic Archaeology Fragment
})
AddCurrencies("battle_for_azeroth", "active", "profession", {
    1534, -- Zandalari Archaeology Fragment
    1535, -- Drust Archaeology Fragment
})

-- Same currency or system across expansions. Do not file these under the current expansion tab.
AddCurrencies("cross_expansion", "active", "evergreen", {
    2032, -- Trader's Tender
    2803, -- Undercoin. War Within Delves currency, still the Midnight Delves currency.
    3028, -- Restored Coffer Key. Used in War Within and Midnight Delves.
    3363, -- Community Coupons. Player Housing / Neighborhood Endeavors.
})
Add(currencies, 1166, "cross_expansion", "active", "timewalking") -- Timewarped Badge
Add(currencies, 515, "cross_expansion", "active", "event") -- Darkmoon Prize Ticket
Add(currencies, 1379, "cross_expansion", "active", "event") -- Trial of Style Token
Add(currencies, 1299, "cross_expansion", "active", "event") -- Brawler's Gold. Recurring guild, back in Retail in 11.2.7.
Add(currencies, 2588, "cross_expansion", "active", "event") -- Riders of Azeroth Badge. Skyriding Cup.
AddCurrencies("cross_expansion", "active", "pvp", {
    1602, -- Conquest
    1792, -- Honor
    2123, -- Bloody Tokens
})
Add(items, 137642, "cross_expansion", "active", "pvp") -- Mark of Honor. Current Retail item, distinct from the old battleground currencies.

AddItems("cross_expansion", "active", "event", {
    37829,  -- Brewfest Prize Token
    33226,  -- Tricky Treat
    128659, -- Merry Supplies
    21100,  -- Coin of Ancestry
    49927,  -- Love Token
    44791,  -- Noblegarden Chocolate
    23247,  -- Burning Blossom
})

local function ClientExpansionLevel()
    if type(GetExpansionLevel) == "function" then
        local ok, value = pcall(GetExpansionLevel)
        if ok and type(value) == "number" then
            return value
        end
    end
    return CURRENT_EXPANSION_FALLBACK
end

local function Describe(eraId, status, kind)
    local era = erasById[eraId] or erasById.unknown
    return {
        era = era.id,
        label = era.label,
        status = status or "unknown",
        kind = kind or "miscellaneous",
    }
end

function WBF.ResourceMeta.Ordered()
    return ordered
end

function WBF.ResourceMeta.CurrentEra()
    return eraByExpansion[ClientExpansionLevel()]
end

function WBF.ResourceMeta.Label(eraId)
    local era = erasById[eraId]
    return era and era.label or erasById.unknown.label
end

function WBF.ResourceMeta.KnowsCurrency(currencyID)
    local id = tonumber(currencyID)
    return id ~= nil and currencies[id] ~= nil
end

function WBF.ResourceMeta.For(definition)
    if type(definition) ~= "table" then
        return Describe("unknown", "unknown", "miscellaneous")
    end
    local id = tonumber(definition.id)
    local store = definition.trackingType == "item" and items or currencies
    local row = id and store[id] or nil
    if row and erasById[row.era] then
        return Describe(row.era, row.status, row.kind)
    end
    if definition.eventKey then
        return Describe("cross_expansion", "active", "event")
    end
    -- No registry row. Era "unknown" is the Unknown / Other section.
    -- That is separate from a registered resource whose status is "unknown".
    return Describe("unknown", "unknown", "miscellaneous")
end
