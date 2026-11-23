# ConvrgeForever

A World of Warcraft addon for **WoW Forever** (TOC `## Interface: 16000`), bundling small modules (Stash, Fishing, Carrot, Gold) under one `/cf` window.

## WoW Forever specifics

- WoW Forever has **rulesets**, not realms: mega-servers grouped by type (PvP, Normal, RP, etc.). Say "ruleset" in anything players see.
- `GetRealmName()` is still what distinguishes them in code, so saved data keyed by "realm" (e.g. Stash's `db.realms[realm][faction][name]`) is really keyed by ruleset. Don't rename those keys; it would orphan existing saved variables.

## Layout

- `Core/Core.lua`: module registry (`CF:NewModule(key, def)`), saved-variable defaults, legacy-addon migration, slash commands. The header comment documents the module fields.
- `Core/Widgets.lua`, `Core/Window.lua`: shared UI widgets (`CF.W`) and the settings window.
- `Modules/<Name>/`: one folder per module. List new files in `ConvrgeForever.toc`.
- Group Finder (`Modules/LFG/`): Classic-style UI (`LFGListingFrame`) over `C_LFGList`. Quests aren't linked to activities (`GetActivityIDForQuestID` is nil); Quests & Zones (category 116) has one activity per zone and Dungeons (category 2) one per dungeon, so match by quest log header. Group quests are found by `C_QuestLog.GetQuestTagInfo` tag (1 Elite, 81 Dungeon); `suggestedGroup` is always 0. `C_LFGList.Search` needs a click. Only `C_QuestLog` exists, not the old quest log globals.
- WoW Forever uses the modern auction house API (`C_AuctionHouse`, commodities): search, `StartCommoditiesPurchase` for the price, `ConfirmCommoditiesPurchase` on a click.

## Pull requests

- Claude may merge its own pull requests into `main` without asking, as long as the PR has no merge conflicts and its checks (if any) pass. Share the PR link after merging.

## Checking changes

There's no WoW client here, so changes can't be run. To at least syntax-check a file:

```bash
pip install -q luaparser && python3 -c "from luaparser import ast; ast.parse(open('Modules/Stash/Stash.lua').read())"
```
