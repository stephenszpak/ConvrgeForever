# ConvrgeForever

A pack of small quality-of-life addons for **WoW Forever**, all in one `/cf` window. Each module does one niche job and can be switched off on its own.

## Install

1. Download **[ConvrgeForever.zip](https://github.com/stephenszpak/ConvrgeForever/releases/latest/download/ConvrgeForever.zip)** (always the latest version).
2. Unzip it into your WoW Forever client's `Interface/AddOns` folder. The folder is already named `ConvrgeForever`.
3. Restart the game or `/reload`.

Use the release zip above rather than GitHub's green **Code → Download ZIP** button: that one names the folder `ConvrgeForever-main`, which WoW won't load until you rename it.

### Auto-update on Windows

`tools/Install-AutoUpdate.ps1` adds a scheduled task that checks for a new release at logon and every 10 minutes, then replaces the addon folder when one is out. Your settings are kept. Run it from an Administrator PowerShell in the `tools` folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-AutoUpdate.ps1
```

Pass `-AddonDir "<path>\Interface\AddOns\ConvrgeForever"` if your game isn't in `C:\Program Files (x86)\World of Warcraft\_forever_`, `-Minutes 5` to change the interval, or `-Uninstall` to remove the task. The log is in `%LOCALAPPDATA%\ConvrgeForever-Sync\sync.log`.

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

### Gear
Situational gear sets on a small bar. A set covers only the slots it needs and goes on top of whatever you're wearing; taking it off puts back what was there.

- **On-use sets** (an AoE trinket, say): click the bar's Use button to put it on, click again to use it (works in combat). Your old item goes back once combat ends, and you get a chat message, sound and on-screen alert when the item is ready again. A freshly equipped trinket can't be used for about 30 seconds; the button shows that countdown.
- **Custom sets** (Fire Res, a farming set): click to put on or take off, or have them come off after combat.
- **Main sets** from the game's equipment manager are on the bar too.
- Hover a bar button to pick another set; Shift-drag to move the bar; right-click takes a set off.
- Make sets on the Gear page: click a slot to use what you're wearing there, or drop an item on it from your bags.
- If an item isn't in your bags, it tells you whether it's in your bank or on another character (from Stash).
- Works alongside Carrot: the two agree on which trinket is your real one.

Commands: `/cf gear` opens the page; `/cf gear <set name>` puts a set on or takes it off; `/cf gear off` takes every set off; `/cf gear bar` shows or hides the bar. Keybind: **Options → Keybindings → AddOns → ConvrgeForever → Gear: put on / use on-use set**.

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
