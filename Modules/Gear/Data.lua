-- Gear data: how slayer items word their bonus, and the mob types we know.
-- Adding new wording found in game is a one-line change here.

local _, CF = ...
CF.GEAR = CF.GEAR or {}
local D = CF.GEAR

-- Bump when the patterns change, so cached tooltip reads are redone.
D.SCAN_VERSION = 1

-- A tooltip line counts as a slayer bonus when it has one of these words...
D.BONUS_WORDS = { "damage", "attack power", "critical", "fighting", "slay" }

-- ...and one of these phrases, followed by the mob list. The capture is cut at
-- the first word in LIST_ENDS, then split on ", ", " and ", " or ".
--   "Deals 2 times as much damage to Naga and Satyrs."
--   "+60 Attack Power when fighting Undead."
--   "Increases damage done to Demons by magical spells and effects by up to 20."
--   "Does triple damage to Ogres."
D.LIST_STARTS = {
    "damage to (.+)",
    "damage against (.+)",
    "damage done to (.+)",
    "damage dealt to (.+)",
    "when fighting (.+)",
    "while fighting (.+)",
    "against (.+)",
    "versus (.+)",
    "vs%.? (.+)",
}
D.LIST_ENDS = { "%.", ";", "%(", " by ", " for ", " up to ", " when ", " while ", " with ", " that ", " in " }

-- Multiplier words; "N times" is read as a number.
D.MULTIPLIERS = { twice = 2, double = 2, triple = 3, quadruple = 4 }

-- Plural or other forms that tooltips use -> the type name we show.
-- Anything not listed loses a trailing "s" (Gnolls -> Gnoll), "ies" -> "y".
D.FORMS = {
    Naga = "Naga", Undead = "Undead", Dragonkin = "Dragonkin", Mechanical = "Mechanical",
    Centaur = "Centaur", Centaurs = "Centaur", Quilboar = "Quilboar", Harpies = "Harpy",
    Dwarves = "Dwarf", Elves = "Elf", Wolves = "Wolf", Demons = "Demon", Beasts = "Beast",
    Dragons = "Dragonkin", Elementals = "Elemental", Giants = "Giant", Humanoids = "Humanoid",
}

-- Words that look like a list but aren't mob types.
D.NOT_TYPES = {
    Target = true, Targets = true, Enemy = true, Enemies = true, All = true, Nearby = true,
    Your = true, You = true, Attackers = true, Them = true, It = true, Self = true,
}

-- Shown on the Slayer page even with no items yet, so you can see the gaps.
-- The first group are real creature types: the game tells us those directly.
D.CREATURE_TYPES = { "Beast", "Demon", "Dragonkin", "Elemental", "Giant", "Humanoid", "Mechanical", "Undead" }
D.COMMON_TYPES = {
    "Centaur", "Furbolg", "Gnoll", "Harpy", "Kobold", "Murloc", "Naga", "Ogre", "Quilboar",
    "Satyr", "Trogg", "Troll",
}

-- Mob IDs known to be a type, for dungeons where names don't say it.
-- Empty for now: teach mobs in game (target, then the Slayer tab or
-- "/cf gear teach Naga"); taught mobs are saved for every character.
D.KNOWN_MOBS = {
    -- [npcID] = "Naga",
}
