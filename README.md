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

## Notes

- WoW Forever has rulesets instead of realms; anything that says "ruleset" means the PvP, Normal, RP etc. server you're on.
- Settings are saved account-wide in `ConvrgeForeverDB`, with a few per-character ones in `ConvrgeForeverCharDB`.
