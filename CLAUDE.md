# ConvrgeForever

A World of Warcraft addon for **WoW Forever** (TOC `## Interface: 16000`), bundling small modules (Stash, Fishing, Carrot, Gold) under one `/cf` window.

## WoW Forever specifics

- WoW Forever has **rulesets**, not realms: mega-servers grouped by type (PvP, Normal, RP, etc.). Say "ruleset" in anything players see.
- `GetRealmName()` is still what distinguishes them in code, so saved data keyed by "realm" (e.g. Stash's `db.realms[realm][faction][name]`) is really keyed by ruleset. Don't rename those keys; it would orphan existing saved variables.

## Layout

- `Core/Core.lua`: module registry (`CF:NewModule(key, def)`), saved-variable defaults, legacy-addon migration, slash commands. The header comment documents the module fields.
- `Core/Widgets.lua`, `Core/Window.lua`: shared UI widgets (`CF.W`) and the settings window.
- `Modules/<Name>/`: one folder per module. List new files in `ConvrgeForever.toc`.

## Checking changes

There's no WoW client here, so changes can't be run. To at least syntax-check a file:

```bash
pip install -q luaparser && python3 -c "from luaparser import ast; ast.parse(open('Modules/Stash/Stash.lua').read())"
```
