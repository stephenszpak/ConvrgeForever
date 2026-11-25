-- Sixty module data: level 60 checklist, default pre-raid wishlists and every
-- string the module shows. Edit freely: adding a class/spec list or changing
-- wording should only ever need changes here.
--
-- Item IDs are Classic Era values and are NOT verified for WoW Forever. The
-- module checks each ID's name before trusting it, falls back to an exact name
-- match, and saves any ID it learns in ConvrgeForeverDB.sixty.itemIDs.

local _, CF = ...

local D = {}
CF.SIXTY = D

---------------------------------------------------------------------------
-- Checklist: one-time unlocks detected by an item in bags, keyring, bank or
-- worn. short = column label in the per-character overview.
---------------------------------------------------------------------------
D.CHECKLIST = {
    { key = "onyxia", label = "Onyxia attunement", short = "Ony", item = "Drakefire Amulet", id = 16309,
      hint = "Starts with \"Dragonkin Menace\" from Helendis Riverhorn, Morgan's Vigil, Burning Steppes. "
          .. "Ends with General Drakkisath in UBRS." },
    { key = "ubrs", label = "UBRS key", short = "UBRS", item = "Seal of Ascension", id = 12344,
      hint = "Unadorned Seal from LBRS mobs, talk to Vaelan, gems from Voone, Omokk and Wyrmthalak, "
          .. "forge in Dustwallow Marsh." },
    { key = "diremaul", label = "Dire Maul key", short = "DM", item = "Crescent Key", id = 18249,
      hint = "Opens Dire Maul West and North." },
    { key = "brd", label = "BRD key", short = "BRD", item = "Shadowforge Key", id = 11000 },
    { key = "scholo", label = "Scholomance key", short = "Scholo", item = "Skeleton Key", id = 13704 },
    { key = "strat", label = "Stratholme key", short = "Strat", item = "Key to the City", id = 12382 },
}

-- Tick boxes for things the addon can't detect yet (saved per character).
-- weekly = cleared at the weekly reset when the client reports reset times.
D.MANUAL = {
    { key = "riding", label = "Journeyman Riding trained" },
    { key = "epicmount", label = "Epic mount bought" },
    { key = "dualspec", label = "Dual Specialization bought" },
    { key = "hyjalbag", label = "Mount Hyjal bag quest (Mending Communications) done" },
    { key = "pix", label = "Weekly quest from Pix Xizzix picked up", weekly = true },
}

---------------------------------------------------------------------------
-- Gear slots. inv = inventory slots the piece can be worn in.
---------------------------------------------------------------------------
D.SLOTS = {
    { key = "weapon",   label = "Weapon",    inv = { 16, 17 } },
    { key = "head",     label = "Head",      inv = { 1 } },
    { key = "neck",     label = "Neck",      inv = { 2 } },
    { key = "shoulder", label = "Shoulder",  inv = { 3 } },
    { key = "back",     label = "Back",      inv = { 15 } },
    { key = "chest",    label = "Chest",     inv = { 5 } },
    { key = "wrist",    label = "Wrist",     inv = { 9 } },
    { key = "hands",    label = "Hands",     inv = { 10 } },
    { key = "waist",    label = "Waist",     inv = { 6 } },
    { key = "legs",     label = "Legs",      inv = { 7 } },
    { key = "feet",     label = "Feet",      inv = { 8 } },
    { key = "ring1",    label = "Ring 1",    inv = { 11, 12 } },
    { key = "ring2",    label = "Ring 2",    inv = { 11, 12 } },
    { key = "trinket1", label = "Trinket 1", inv = { 13, 14 } },
    { key = "trinket2", label = "Trinket 2", inv = { 13, 14 } },
}

---------------------------------------------------------------------------
-- Default wishlists: WISHLISTS[CLASS][Spec] = { name, slots = { [slot] = { target, fallback } } }
-- CLASS is the game's English class token (UnitClass 2nd return). Each item:
--   name    exact item name (required)
--   source  where it comes from; the part before the first comma, minus a
--           trailing "craft" or "quest", is the "Where to go next" group
--   group   optional: overrides that group
--   id      optional item ID; leave out unless verified in WoW Forever
-- Characters copy their list on first login and can edit it in game.
---------------------------------------------------------------------------
D.WISHLISTS = {
    SHAMAN = {
        Enhancement = {
            name = "Enhancement Shaman",
            slots = {
                weapon   = { target   = { name = "Forest Defender's Axe", source = "Blacksmithing craft" },
                             fallback = { name = "Flameslash Crescent", source = "Blackmaw Hold, Impaan" } },
                head     = { target   = { name = "Mask of the Unforgiven", source = "Stratholme, The Unforgiven" },
                             fallback = { name = "Black Dragonscale Helm", source = "Leatherworking craft" } },
                neck     = { target   = { name = "Beads of Ogre Might", source = "Dire Maul quest, Falrin's Vendetta" },
                             fallback = { name = "Nacreous Shell Necklace", source = "Stratholme, Cannon Master Willey" } },
                shoulder = { target   = { name = "Spiritcaller Mantle", source = "Leatherworking craft" },
                             fallback = { name = "Savage Gladiator Shoulders", source = "Blackrock Depths, Grizzle" } },
                back     = { target   = { name = "Cape of the Black Baron", source = "Stratholme, Baron Rivendare" },
                             fallback = { name = "Shroud of Domination", source = "Blackrock Spire, Lord Valthalak" } },
                chest    = { target   = { name = "Dawn Armor", source = "Leatherworking craft" },
                             fallback = { name = "Timbermaw Tunic", source = "Leatherworking craft" } },
                wrist    = { target   = { name = "Slashclaw Bracers", source = "Blackrock Spire, Halycon" },
                             fallback = { name = "Blackmist Armguards", source = "Blackrock Spire, The Beast" } },
                hands    = { target   = { name = "Devilsaur Gauntlets", source = "Leatherworking craft" },
                             fallback = { name = "Spiritcaller Gloves", source = "Leatherworking craft" } },
                waist    = { target   = { name = "Might of the Timbermaw", source = "Leatherworking craft" },
                             fallback = { name = "Warpwood Binding", source = "Dire Maul, Tendris Warpwood" } },
                legs     = { target   = { name = "Devilsaur Leggings", source = "Leatherworking craft" },
                             fallback = { name = "Spiritcaller Kilt", source = "Leatherworking craft" } },
                feet     = { target   = { name = "Spiritcaller Treads", source = "Leatherworking craft" },
                             fallback = { name = "Windreaver Greaves", source = "Scholomance, Kirtonos the Herald" } },
                ring1    = { target   = { name = "The Postmaster's Seal", source = "Stratholme, Postmaster Malown" },
                             fallback = { name = "Ring of Demonic Guile", source = "Dire Maul, Alzzin the Wildshaper" } },
                ring2    = { target   = { name = "Blackstone Ring", source = "Maraudon, Princess Theradras" },
                             fallback = { name = "Magni's Will", source = "Blackrock Depths quest" } },
                trinket1 = { target   = { name = "Smolderweb's Eye", source = "Blackrock Spire, Mother Smolderweb" },
                             fallback = { name = "Frozen Heart of the Mountain", source = "Enchanting craft" } },
                trinket2 = { target   = { name = "Cleansed Vilebranch Medallion", source = "Hinterlands quest, Saving Sharpbeak" },
                             fallback = { name = "Scalding Flamehoof", source = "Blackmaw Hold, Varrox Bleakhoof" } },
            },
        },
    },
}

-- List used by a class with no list of its own.
D.DEFAULT_LIST = { class = "SHAMAN", spec = "Enhancement" }

---------------------------------------------------------------------------
-- Strings
---------------------------------------------------------------------------
D.L = {
    title = "Sixty",
    description = "Level 60 attunement and key checklist, plus a pre-raid gear wishlist with tooltip tags and loot alerts.",

    -- Page
    headChecklist = "Checklist",
    headAlts = "Your characters",
    headWishlist = "Wishlist",
    headWhere = "Where to go next",
    optTooltip = "Tag wishlist items in tooltips",
    optLoot = "Chat alert when a wishlist item drops",
    optSound = "Play a sound with the alert",
    optAlts = "Show your other characters",
    colSlot = "Slot",
    colItem = "Item",
    colStatus = "Status",
    done = "done",
    missing = "missing",
    noHint = "Not found in your bags, keyring, bank or gear.",
    foundIn = "in %s",
    weeklyAuto = "  (clears at the weekly reset)",
    weeklyManual = "  (untick it yourself after the weekly reset)",
    altsNeedStash = "Turn on the Stash module to see your other characters and your bank.",
    altsNone = "No other characters saved yet. Log into each one once with Stash on.",
    altBankUnknown = "bank not scanned",
    you = "this character",
    wishlistFor = "%s list",
    wishlistOther = "%s list (no list for your class yet)",
    statusEquipped = "Equipped",
    statusOwned = "Owned: %s",
    statusFallback = "Fallback: %s",
    statusNeeded = "Needed: %s",
    unknownSource = "Unknown source",
    craft = "(craft)",
    whereDone = "Nothing left to get. Every slot has its target or fallback.",
    whereRow = "%s: %d (%s)",
    inCombat = "Updates after combat.",
    paused = "Sixty is paused (/cf sixty on to resume).",
    locBags = "bags",
    locKeyring = "keyring",
    locBank = "bank",
    locWorn = "worn",
    locWarband = "Warband bank",
    locAlt = "%s (%s)",
    more = " +%d more",
    tipTarget = "Target",
    tipFallback = "Fallback",
    tipID = "Item ID %d",
    tipNoID = "Item ID not learned yet: equip, loot or hover the item once.",
    tipEdit = "Change with /cf sixty want|fallback <slot> <shift-click item> [source]",

    -- Tooltip tag and loot alert
    tagTarget = "|cff4fc3f7ConvrgeForever|r: wishlist target (%s)",
    tagFallback = "|cff4fc3f7ConvrgeForever|r: wishlist fallback (%s)",
    kindTarget = "target",
    kindFallback = "fallback",
    lootAlert = "%s is on your wishlist (%s).",

    -- Slash
    help = {
        "commands:",
        "   /cf sixty  - open the Sixty page (also /sixty)",
        "   /cf sixty want <slot> <item link> [source]  - set a slot's target",
        "   /cf sixty fallback <slot> <item link> [source]  - set a slot's fallback",
        "   /cf sixty reset  - put this character's wishlist back to the defaults",
        "   /cf sixty list [CLASS Spec]  - show or switch default lists",
        "   /cf sixty on|off  - pause or resume tooltip tags, alerts and refreshes",
        "   slots: weapon head neck shoulder back chest wrist hands waist legs feet ring1 ring2 trinket1 trinket2",
    },
    badSlot = "unknown slot \"%s\". Slots: weapon head neck shoulder back chest wrist hands waist legs feet ring1 ring2 trinket1 trinket2.",
    needLink = "shift-click an item into the command, e.g. /cf sixty want head [Mask of the Unforgiven].",
    setDone = "%s %s set to %s.",
    resetDone = "wishlist reset to the %s defaults.",
    listCurrent = "this character uses the %s list. Available:",
    listRow = "   %s %s",
    listUnknown = "no list for %s %s. /cf sixty list shows the available ones.",
    listSet = "switched to the %s list (your edits to the old list were replaced).",
    onOff = "%s.",
    on = "resumed",
    off = "paused",
}
