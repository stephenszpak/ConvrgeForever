# ConvrgeForever

A pack of small quality-of-life addons for **WoW Forever**, all in one `/cf` window. Each module does one niche job and can be switched off on its own.

## Install

1. Download **[ConvrgeForever.zip](https://github.com/stephenszpak/ConvrgeForever/releases/latest/download/ConvrgeForever.zip)** (always the latest version).
2. Unzip it into your WoW Forever client's `Interface/AddOns` folder. The folder is already named `ConvrgeForever`.
3. Restart the game or `/reload`.

Use the release zip above rather than GitHub's green **Code → Download ZIP** button: that one names the folder `ConvrgeForever-main`, which WoW won't load until you rename it.

## Getting around

- `/cf` (or `/convrge`) opens the window. The minimap button and the AddOn compartment menu open it too.
- Each module has its own section in the window. Turn modules on or off on the **General** page.
- **EllesmereUI is optional.** With it installed, the window follows your EllesmereUI theme, accent color and font; without it, the addon uses its own dark style and you pick an accent color on the General page.

## Modules

### Stash
Item counts across all your characters in the item tooltip: bags, equipped gear, character bank and Warband bank. Shows every character, or only the current ruleset and faction.

- `/stash` opens the Stash page
- `/stash <item link, ID or name>` prints counts in chat
- `/stash delete <name or name-ruleset>` forgets a character

Replaces the standalone **StashCount** addon and imports its data.

### Fishing
- Double right-click to cast; applies your best lure first if the pole has none
- One key swaps between your fishing pole and fishing gear and your weapons and normal gear
- Info line with zone, skill needed, your effective skill and lure timer
- Zone guide for where you can fish without getaways, a catch log per subzone, and session stats

Commands: `/ff` opens the window; `/ff help` lists the rest (`where`, `zone`, `spots`, `swap`, `gear`, `session`, `lure`, `dbl`, `info`).
Keybinds are under **Options → Keybindings → AddOns → ConvrgeForever**.

Replaces the standalone **FishFriend** addon and imports its data.

### Carrot
Puts **Carrot on a Stick** in your top trinket slot when you mount and puts your trinket back when you dismount. Swaps wait until you're out of combat and done casting. Can skip dungeons and raids. `/cf carrot on|off`.

### Gold
A movable widget with gold earned this session and gold per hour. Earnings are broken down by source (mobs, chests, quests, vendor, auction house, repairs, flight paths...) and by zone, with your best farming zones and a history of past sessions. Looted items can count at vendor value.

- `/gold` opens the Gold page
- `/gold reset` starts a new session
- `/gold show|hide` shows or hides the widget

### Salt
Tracks the **Salt Shaker** cooldown (Deeprock Salt → Refined Deeprock Salt) on every character.

- The Salt page lists each character's time left, when it'll be ready, and their Deeprock and Refined Deeprock Salt
- Chat message and sound when a shaker comes off cooldown, and a list of ready shakers when you log in
- Timers on the Salt Shaker tooltip
- `/cf salt` prints the timers in chat

Each character shows up after it logs in once with the shaker. The timer updates while the shaker is in your bags.

### LFG
Find a group for your elite and dungeon quests. The LFG page lists your group quests; click one to search the Group Finder for its zone or dungeon. There's also an eye button next to group quests in the quest log. Open it with `/cf lfg`.

### Sixty
Getting a fresh level 60 raid-ready, on one page:

- **Checklist**: Onyxia attunement and the UBRS, Dire Maul, BRD, Scholomance and Stratholme keys, detected from your bags, keyring, gear and bank, with a hint for anything missing. Tick boxes for riding, epic mount, dual spec, the Hyjal bag quest and Pix Xizzix's weekly (which clears itself at the weekly reset). With Stash on, a row per character shows who has which key.
- **Wishlist**: a target and fallback item per slot (Enhancement Shaman by default), each marked Equipped, Owned (with where: bags, bank, Warband bank or an alt), Fallback or Needed.
- **Where to go next**: the dungeons and professions that hold the most pieces you still need.
- Wishlist items get a tag in their tooltip, and a chat alert (with optional sound) when one drops.

Commands (also `/sixty`):
- `/cf sixty` opens the Sixty page
- `/cf sixty want <slot> <item link> [source]` sets a slot's target (shift-click the item)
- `/cf sixty fallback <slot> <item link> [source]` sets a slot's fallback
- `/cf sixty reset` puts your wishlist back to the defaults
- `/cf sixty list [CLASS Spec]` shows or switches the default list
- `/cf sixty on|off` pauses tooltip tags, alerts and refreshes

Slots: `weapon head neck shoulder back chest wrist hands waist legs feet ring1 ring2 trinket1 trinket2`. Alts and bank contents come from Stash, so log into each character and visit a banker once with Stash on.

## Notes

- WoW Forever has rulesets instead of realms; anything that says "ruleset" means the PvP, Normal, RP etc. server you're on.
- Settings are saved account-wide in `ConvrgeForeverDB`, with a few per-character ones in `ConvrgeForeverCharDB`.
