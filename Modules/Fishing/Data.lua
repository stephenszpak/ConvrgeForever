-- Fishing module data. Edit freely: this file is yours.
--
-- skill   = effective Fishing skill at which fish stop getting away
--           (base skill + pole + lure + gear). Source: timesaver.gg WoW Forever
--           fishing table, Nov 2026. Forever may still tweak these; the addon
--           also learns from your own "fish got away" messages (see /ff zone).
-- lvl     = rough character level range of the zone (Classic values; Forever may differ).
-- faction = only show in /ff where for this faction (nil = both).
-- dungeon = true for instances.

local _, CF = ...

CF.FISH_ZONES = {
    -- 25
    ["Dun Morogh"]          = { skill = 25,  lvl = "1-10",  faction = "Alliance" },
    ["Elwynn Forest"]       = { skill = 25,  lvl = "1-10",  faction = "Alliance" },
    ["Teldrassil"]          = { skill = 25,  lvl = "1-10",  faction = "Alliance" },
    ["Durotar"]             = { skill = 25,  lvl = "1-10",  faction = "Horde" },
    ["Mulgore"]             = { skill = 25,  lvl = "1-10",  faction = "Horde" },
    ["Tirisfal Glades"]     = { skill = 25,  lvl = "1-10",  faction = "Horde" },

    -- 75
    ["Darkshore"]           = { skill = 75,  lvl = "10-20" },
    ["Loch Modan"]          = { skill = 75,  lvl = "10-20" },
    ["Silverpine Forest"]   = { skill = 75,  lvl = "10-20" },
    ["The Barrens"]         = { skill = 75,  lvl = "10-25" },
    ["Westfall"]            = { skill = 75,  lvl = "10-20" },
    ["Stormwind City"]      = { skill = 75,  lvl = "city", faction = "Alliance" },
    ["Ironforge"]           = { skill = 75,  lvl = "city", faction = "Alliance" },
    ["Darnassus"]           = { skill = 75,  lvl = "city", faction = "Alliance" },
    ["Orgrimmar"]           = { skill = 75,  lvl = "city", faction = "Horde" },
    ["Thunder Bluff"]       = { skill = 75,  lvl = "city", faction = "Horde" },
    ["Undercity"]           = { skill = 75,  lvl = "city", faction = "Horde" },
    ["Blackfathom Deeps"]   = { skill = 75,  lvl = "24-32", dungeon = true },
    ["Wailing Caverns"]     = { skill = 75,  lvl = "17-24", dungeon = true },
    ["The Deadmines"]       = { skill = 75,  lvl = "17-26", dungeon = true },

    -- 150
    ["Ashenvale"]           = { skill = 150, lvl = "18-30" },
    ["Duskwood"]            = { skill = 150, lvl = "18-30" },
    ["Hillsbrad Foothills"] = { skill = 150, lvl = "20-30" },
    ["Redridge Mountains"]  = { skill = 150, lvl = "15-25" },
    ["Stonetalon Mountains"]= { skill = 150, lvl = "15-27" },
    ["Wetlands"]            = { skill = 150, lvl = "20-30" },

    -- 225
    ["Alterac Mountains"]   = { skill = 225, lvl = "30-40" },
    ["Arathi Highlands"]    = { skill = 225, lvl = "30-40" },
    ["Desolace"]            = { skill = 225, lvl = "30-40" },
    ["Dustwallow Marsh"]    = { skill = 225, lvl = "35-45" },
    ["Stranglethorn Vale"]  = { skill = 225, lvl = "30-45" },
    ["Swamp of Sorrows"]    = { skill = 225, lvl = "35-45" },
    ["Thousand Needles"]    = { skill = 225, lvl = "25-35" },
    ["Scarlet Monastery"]   = { skill = 225, lvl = "26-45", dungeon = true },

    -- 300
    ["Azshara"]             = { skill = 300, lvl = "45-55" },
    ["Felwood"]             = { skill = 300, lvl = "48-55" },
    ["Feralas"]             = { skill = 300, lvl = "40-50" },
    ["Jaguero Isle"]        = { skill = 300, lvl = "30-45" },
    ["Moonglade"]           = { skill = 300, lvl = "any" },
    ["Tanaris"]             = { skill = 300, lvl = "40-50" },
    ["The Hinterlands"]     = { skill = 300, lvl = "40-50" },
    ["Un'Goro Crater"]      = { skill = 300, lvl = "48-55" },
    ["Western Plaguelands"] = { skill = 300, lvl = "51-58" },
    ["Maraudon"]            = { skill = 300, lvl = "46-55", dungeon = true },
    ["Sunken Temple"]       = { skill = 300, lvl = "50-60", dungeon = true },

    -- 425 (needs +125 over 300: lure + hat + good pole)
    ["Burning Steppes"]     = { skill = 425, lvl = "50-58" },
    ["Deadwind Pass"]       = { skill = 425, lvl = "55-60" },
    ["Eastern Plaguelands"] = { skill = 425, lvl = "53-60" },
    ["Silithus"]            = { skill = 425, lvl = "55-60" },
    ["Winterspring"]        = { skill = 425, lvl = "55-60" },
    ["Bay of Storms"]       = { skill = 425, lvl = "45-55" },
    ["Hetaera's Clutch"]    = { skill = 425 },
    ["Jademir Lake"]        = { skill = 425, lvl = "40-50" },
    ["Scalebeard's Cave"]   = { skill = 425, lvl = "45-55" },
    ["Scholomance"]         = { skill = 425, lvl = "58-60", dungeon = true },
    ["Stratholme"]          = { skill = 425, lvl = "58-60", dungeon = true },
    ["Zul'Gurub"]           = { skill = 425, lvl = "60",    dungeon = true },
}

-- Lures, matched by item name. bonus = skill added, req = Fishing skill needed to use.
-- "Secret" Bait is new in Forever; its requirement is a guess (0).
CF.FISH_LURES = {
    ["Shiny Bauble"]               = { bonus = 25,  req = 0 },
    ["\"Secret\" Bait"]            = { bonus = 25,  req = 0 },
    ["Nightcrawlers"]              = { bonus = 50,  req = 0 },
    ["Aquadynamic Fish Lens"]      = { bonus = 50,  req = 50 },
    ["Bright Baubles"]             = { bonus = 75,  req = 100 },
    ["Flesh Eating Worm"]          = { bonus = 75,  req = 100 },
    ["Aquadynamic Fish Attractor"] = { bonus = 100, req = 100 },
}

-- Known poles and their bonus, by item ID (used to pick the best pole in your bags).
-- Any other fishing pole still works; it just counts as +0 when choosing.
CF.FISH_POLES = {
    [6256]  = 0,   -- Fishing Pole
    [12225] = 3,   -- Blump Family Fishing Pole
    [6365]  = 5,   -- Strong Fishing Pole
    [6366]  = 15,  -- Darkwood Fishing Pole
    [6367]  = 20,  -- Big Iron Fishing Pole
    [19022] = 25,  -- Nat Pagle's Extreme Angler FC-5000
    [19970] = 35,  -- Arcanite Fishing Pole
}
