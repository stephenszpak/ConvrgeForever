# ConvrgeForever

A World of Warcraft addon for **WoW Forever** (TOC `## Interface: 16001`), bundling small modules (Stash, Fishing, Carrot, Gear, Gold, Salt, LFG, Sixty) under one `/cf` window.

## WoW Forever specifics

- WoW Forever has **rulesets**, not realms: mega-servers grouped by type (PvP, Normal, RP, etc.). Say "ruleset" in anything players see.
- `GetRealmName()` is still what distinguishes them in code, so saved data keyed by "realm" (e.g. Stash's `db.realms[realm][faction][name]`) is really keyed by ruleset. Don't rename those keys; it would orphan existing saved variables.

## Layout

- `Core/Core.lua`: module registry (`CF:NewModule(key, def)`), saved-variable defaults, legacy-addon migration, slash commands. The header comment documents the module fields.
- `Core/Widgets.lua`, `Core/Window.lua`: shared UI widgets (`CF.W`) and the settings window.
- `Modules/<Name>/`: one folder per module. List new files in `ConvrgeForever.toc`.
- Group Finder (`Modules/LFG/`): Classic-style UI (`LFGListingFrame`) over `C_LFGList`. Quests aren't linked to activities (`GetActivityIDForQuestID` is nil); Quests & Zones (category 116) has one activity per zone and Dungeons (category 2) one per dungeon, so match by quest log header. Group quests are found by `C_QuestLog.GetQuestTagInfo` tag (1 Elite, 81 Dungeon); `suggestedGroup` is always 0. `C_LFGList.Search` needs a click. Only `C_QuestLog` exists, not the old quest log globals.
- Sixty (`Modules/Sixty/`) is **hidden**: its files are commented out in `ConvrgeForever.toc` until there's a plan for it. Its saved data is left alone. Uncomment the two TOC lines (and restore its README section from git history) to bring it back.
- Sixty details: `Data.lua` holds every string, the checklist (`CF.SIXTY.CHECKLIST`, `MANUAL`), gear slots and default wishlists (`WISHLISTS[CLASS][Spec]`), so a new class list is data only; `Sixty.lua` is the logic and page. Item IDs in the data are Classic Era and unverified: the module checks an ID's name before trusting it, falls back to exact name, and learns IDs into `ConvrgeForeverDB.sixty.itemIDs[name]`. Per character: `ConvrgeForeverCharDB.sixty.list`, `.wishlist[slot] = { target, fallback }` (each `{ name, id?, source, group? }`), `.manual[key]`, `.weeklyExpires[key]`. Account options: `enabled, tooltipTag, lootAlert, lootSound, showAlts`. Alts and bank come from Stash's read-only exports (`ForEachChar`, `CharLabel`, `Current`, `Warband`); never add a second inventory scanner. All reads happen out of combat; in combat events only queue a refresh.
- Gear (`Modules/Gear/`): situational sets as overlays on top of the game's equipment manager (`C_EquipmentSet`, which WoW Forever has). `Gear.lua` is the logic and pages, `GearBar.lua` the bar. Per character: `ConvrgeForeverCharDB.gear.sets[i] = { id, name, kind = "onuse"|"custom", restore = "use"|"combat"|"manual", slots = { [slot] = itemID } }`, `.saved[slot] = { id, by }` (what a set covered; 0 = empty), `.active[id]`, `.picks[cat]`. Swaps are requests retried until the item shows in the slot, never in combat. The on-use bar button and the `ConvrgeGearUseButton` keybind button are secure; set their attributes out of combat only. Gear and Carrot share the top trinket: Gear takes Carrot's `savedTrinket` as the original and hands it back while you're mounted (Carrot exports `IsMountTrinket`). Slayer sets (`Slayer.lua`, wording patterns and mob type lists in `Data.lua`): tooltips are read with `C_TooltipInfo.GetItemByID` out of combat, a few per tick, and cached in `ConvrgeForeverDB.gear.items[itemID] = { v = SCAN_VERSION, slayer = { [type] = mult } }` (bump `SCAN_VERSION` when patterns change). Slayer sets are `kind = "slayer"` with `mob`. Target recognition: taught mobs (`ConvrgeForeverDB.gear.mobs[npcID]`), then `UnitCreatureType`, then the type in the mob's name; most types (Naga is Humanoid, Satyr is Demon) aren't creature types. `ParseLine` can be tested outside the game with `lupa.lua51` by loading `Data.lua` and `Slayer.lua` with stubs.
- WoW Forever uses the modern auction house API (`C_AuctionHouse`, commodities): search, `StartCommoditiesPurchase` for the price, `ConfirmCommoditiesPurchase` on a click.

## Pull requests

- Claude may merge its own pull requests into `main` without asking, as long as the PR has no merge conflicts and its checks (if any) pass. Share the PR link after merging.

## Checking changes

There's no WoW client here, so changes can't be run. To at least syntax-check a file:

```bash
pip install -q luaparser && python3 -c "from luaparser import ast; ast.parse(open('Modules/Stash/Stash.lua').read())"
```
