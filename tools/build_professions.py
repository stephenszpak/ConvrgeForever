#!/usr/bin/env python3
"""Builds Modules/Professions/Data.lua from the WoW Forever leveling guides on wow-professions.com.

Usage: python3 tools/build_professions.py [--cache DIR]
With --cache, guide pages are read from (and saved to) DIR instead of being downloaded every time.
"""
import argparse
import html
import os
import re
import sys
import urllib.request

BASE = "https://www.wow-professions.com/forever/{}-leveling-guide"
PROFESSIONS = [
    ("alchemy", "Alchemy"),
    ("blacksmithing", "Blacksmithing"),
    ("cooking", "Cooking"),
    ("enchanting", "Enchanting"),
    ("engineering", "Engineering"),
    ("first-aid", "First Aid"),
    ("leatherworking", "Leatherworking"),
    ("tailoring", "Tailoring"),
]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Modules", "Professions", "Data.lua")

RANGE_RE = re.compile(r'<div class="route-range">\s*(\d+)\s*-\s*(\d+)\s*</div>')
RECIPE_RE = re.compile(r'^(\d+)x\s*<a[^>]*spell=(\d+)[^>]*>(?:<img[^>]*>)?(.*?)</a>\s*-\s*(.*)$', re.S)
RANK_RE = re.compile(r'<h[23][^>]*>([^<]*\((\d+)-(\d+)\)[^<]*)</h[23]>\s*<p>(.*?)</p>', re.S)
MAT_RE = re.compile(r'^(\d+)x?\s+(.+)$')
CELL_RECIPE_RE = re.compile(r'^\s*(\d+)x\s*<a[^>]*spell=(\d+)[^>]*>(?:<img[^>]*>)?(.*?)</a>\s*$', re.S)
TAB_RE = re.compile(r'<div class="tab-content( active)?" id="tab\d+-(\d+)-(\d+)">')


def text(fragment):
    t = re.sub(r"<[^>]+>", "", fragment)
    return re.sub(r"\s+", " ", html.unescape(t)).strip()


def fetch(slug, cache):
    path = cache and os.path.join(cache, slug + ".html")
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return f.read()
    req = urllib.request.Request(BASE.format(slug), headers={"User-Agent": "ConvrgeForever-data-builder"})
    with urllib.request.urlopen(req, timeout=30) as r:
        page = r.read().decode("utf-8")
    if path:
        os.makedirs(cache, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(page)
    return page


def parse_mats(s):
    mats = []
    for part in text(s).rstrip(".").split(","):
        m = MAT_RE.match(part.strip())
        if not m:
            raise ValueError("can't read material: %r" % part)
        name = re.sub(r"\s*\(.*\)$", "", m.group(2).strip())
        mats.append((name, int(m.group(1))))
    return mats


def parse_recipe(p):
    m = RECIPE_RE.match(p.strip())
    if not m:
        return None
    return {"count": int(m.group(1)), "spell": int(m.group(2)), "name": text(m.group(3)),
            "mats": parse_mats(m.group(4))}


def in_hidden_tab(page, pos, lo, hi):
    """True for a step inside a route tab the guide doesn't show by default (Mithril Spurs vs Heavy Mithril)."""
    tab = None
    for m in TAB_RE.finditer(page, 0, pos):
        tab = m
    if not tab or re.search(r"<h2[ >]", page[tab.end():pos]):
        return False
    return not tab.group(1) and int(tab.group(2)) <= lo and hi <= int(tab.group(3))


def split_steps(page):
    """Each route-step box on the default route, sliced from its opening tag to the next step or heading."""
    starts = [m.start() for m in re.finditer(r'<div class="route-step">', page)]
    out = []
    for i, s in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(page)
        chunk = page[s:end]
        h = re.search(r"<h[123][ >]", chunk)
        chunk = chunk[:h.start()] if h else chunk
        r = RANGE_RE.search(chunk)
        if not in_hidden_tab(page, s, int(r.group(1)), int(r.group(2))):
            out.append(chunk)
    return out


def table_recipes(tables, lo, hi):
    """Pick-one tables: rows of recipe, materials and where the recipe comes from."""
    out = []
    for row in re.finditer(r"<tr>(.*?)</tr>", tables, re.S):
        cells = re.findall(r"<td[^>]*>(.*?)</td>", row.group(1), re.S)
        if cells and re.fullmatch(r"\d+\s*-\s*\d+", text(cells[0])):
            if text(cells[0]).replace(" ", "") != "%d-%d" % (lo, hi):
                continue
            cells = cells[1:]
        m = len(cells) >= 2 and CELL_RECIPE_RE.match(cells[0])
        if not m:
            continue
        try:
            mats = parse_mats(cells[1])
        except ValueError:
            continue
        recipe = {"count": int(m.group(1)), "spell": int(m.group(2)), "name": text(m.group(3)), "mats": mats}
        out.append((recipe, text(" ".join(cells[2:])) if len(cells) > 2 else ""))
    return out


def parse_step(chunk):
    r = RANGE_RE.search(chunk)
    step = {"lo": int(r.group(1)), "hi": int(r.group(2)), "main": [], "notes": [], "alts": []}
    alt = None
    tables = "".join(re.findall(r"<table.*?</table>", chunk, re.S))
    body = re.sub(r"<table.*?</table>", "", chunk, flags=re.S)
    for m in re.finditer(r"<h4[^>]*>(.*?)</h4>|<(?:p|li)>(.*?)</(?:p|li)>", body, re.S):
        if m.group(1) is not None:
            alt = {"note": "", "recipes": []}
            step["alts"].append(alt)
            continue
        recipe = parse_recipe(m.group(2))
        if recipe:
            (alt["recipes"] if alt else step["main"]).append(recipe)
        elif alt is not None:
            alt["note"] = (alt["note"] + " " + text(m.group(2))).strip()
        else:
            step["notes"].append(text(m.group(2)))
    step["alts"] = [a for a in step["alts"] if a["recipes"]]
    rows = table_recipes(tables, step["lo"], step["hi"])
    if rows and not step["main"]:
        first, source = rows.pop(0)
        step["main"].append(first)
        if source:
            step["notes"].append("Recipe: " + source)
    step["alts"] += [{"note": source, "recipes": [r]} for r, source in rows]
    return step


def parse_guide(page):
    steps = [parse_step(c) for c in split_steps(page)]
    steps = [s for s in steps if s["main"]]
    ranks = []
    for m in RANK_RE.finditer(page):
        body = text(m.group(4))
        cap = re.search(r"past (\d+)", body)
        ranks.append({"at": int(cap.group(1)) if cap else int(m.group(2)), "title": text(m.group(1)), "text": body})
    return steps, ranks


# Crafted by a guide step for skill, but later steps need far more than that, and players buy or skin it.
BUY_NOT_MAKE = {"Light Leather", "Heavy Leather"}


def intermediates(steps):
    """Materials a guide step crafts and a later step uses, with what one craft costs."""
    used, recipe_for = set(), {}
    for s in steps:
        for r in s["main"]:
            recipe_for.setdefault(r["name"], r)
            used.update(name for name, _ in r["mats"])
    out = {}
    for name in used:
        r = recipe_for.get(name)
        if r and name not in BUY_NOT_MAKE:
            out[name] = {"spell": r["spell"], "mats": [(m, q / r["count"]) for m, q in r["mats"]]}
    return out


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_num(x):
    return str(int(x)) if float(x).is_integer() else ("%.4f" % x).rstrip("0")


def lua_recipe(r):
    mats = ", ".join("{ %s, %d }" % (lua_str(n), q) for n, q in r["mats"])
    return "{ spell = %d, name = %s, count = %d, mats = { %s } }" % (r["spell"], lua_str(r["name"]), r["count"], mats)


def write_lua(guides, out):
    L = ["-- Generated by tools/build_professions.py from the WoW Forever leveling guides on",
         "-- wow-professions.com. Don't edit by hand: re-run the script.",
         "", "local _, CF = ...", "", "CF.ProfessionGuides = {"]
    for key, name, steps, ranks, inter in guides:
        L.append("    [%s] = {" % lua_str(key))
        L.append("        name = %s," % lua_str(name))
        L.append("        max = %d," % max(s["hi"] for s in steps))
        L.append("        ranks = {")
        for r in ranks:
            L.append("            { at = %d, title = %s, text = %s }," % (r["at"], lua_str(r["title"]), lua_str(r["text"])))
        L.append("        },")
        L.append("        made = {")
        for mname in sorted(inter):
            i = inter[mname]
            mats = ", ".join("{ %s, %s }" % (lua_str(n), lua_num(q)) for n, q in i["mats"])
            L.append("            [%s] = { spell = %d, mats = { %s } }," % (lua_str(mname), i["spell"], mats))
        L.append("        },")
        L.append("        steps = {")
        for s in steps:
            L.append("            { lo = %d, hi = %d," % (s["lo"], s["hi"]))
            L.append("                main = { %s }," % ", ".join(lua_recipe(r) for r in s["main"]))
            if s["notes"]:
                L.append("                notes = { %s }," % ", ".join(lua_str(n) for n in s["notes"]))
            if s["alts"]:
                L.append("                alts = {")
                for a in s["alts"]:
                    L.append("                    { note = %s, recipes = { %s } }," % (
                        lua_str(a["note"]), ", ".join(lua_recipe(r) for r in a["recipes"])))
                L.append("                },")
            L.append("            },")
        L.append("        },")
        L.append("    },")
    L.append("}")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", help="folder to keep downloaded guide pages in")
    args = ap.parse_args()
    guides = []
    for slug, name in PROFESSIONS:
        steps, ranks = parse_guide(fetch(slug, args.cache))
        if not steps:
            print("%-15s skipped: no fixed recipe steps (pick-any tables aren't supported)" % name)
            continue
        inter = intermediates(steps)
        key = slug.replace("-", "")
        guides.append((key, name, steps, ranks, inter))
        print("%-15s %3d steps, %d rank notes, made: %s" % (name, len(steps), len(ranks), ", ".join(sorted(inter)) or "-"))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    write_lua(guides, OUT)
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
