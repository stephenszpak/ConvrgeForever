-- Fishing module pages: Overview, Zones, Spots, Session, Settings.

local _, CF = ...
local W = CF.W
local M = CF.modules.fishing
local C, GREEN, YELLOW, RED, GREY = W.C, W.GREEN, W.YELLOW, W.RED, W.GREY

-- After any change made in the window
local function Changed()
    M.UpdateInfo()
    CF.RefreshCurrent()
end
local function Check(p, label, get, set, tip) return W.Check(p, label, get, set, tip, Changed) end
local function Choice(p, label, options, get, set) return W.Choice(p, label, options, get, set, Changed) end
local ItemName = W.ItemName

---------------------------------------------------------------------------
-- Page: Overview
---------------------------------------------------------------------------
local function BuildOverview(p)
    local h1 = W.Header(p, "Where you are")
    h1:SetPoint("TOPLEFT", 0, 0)

    local labels = { "Zone", "No getaways at", "Your skill", "Status", "Lure", "Pole" }
    p.vals = {}
    for i, l in ipairs(labels) do
        local k = W.Text(p, 12, 0.55, 0.55, 0.55)
        k:SetPoint("TOPLEFT", 0, -6 - i * 20)
        k:SetText(l)
        local v = W.Text(p, 12)
        v:SetPoint("TOPLEFT", 110, -6 - i * 20)
        v:SetWidth(200)
        p.vals[i] = v
    end

    local h2 = W.Header(p, "Fishing gear")
    h2:SetPoint("TOPLEFT", 330, 0)
    p.gear = {}
    for i = 1, 7 do
        local fs = W.Text(p, 12)
        fs:SetPoint("TOPLEFT", 330, -6 - i * 20)
        fs:SetWidth(210)
        p.gear[i] = fs
    end

    local line = W.Divider(p)
    line:SetPoint("TOPLEFT", 0, -180)
    line:SetPoint("TOPRIGHT", 0, -180)

    local swap = W.Button(p, "Swap pole & gear", 150, 26, function() M.SwapNow() end)
    swap:SetPoint("TOPLEFT", 0, -196)
    W.Tooltip(swap, "Out of combat only. Bind a key in Options > Keybindings > AddOns > FishFriend to swap in combat too.")

    local where = W.Button(p, "Where should I fish?", 150, 26, function() CF.Open("fishing", "zones") end)
    where:SetPoint("LEFT", swap, "RIGHT", 8, 0)

    local spots = W.Button(p, "My spots here", 150, 26, function() CF.Open("fishing", "spots") end)
    spots:SetPoint("LEFT", where, "RIGHT", 8, 0)

    local hint = W.Text(p, 11, 0.55, 0.55, 0.55)
    hint:SetPoint("TOPLEFT", 0, -238)
    hint:SetWidth(540)
    hint:SetWordWrap(true)
    hint:SetText("Double right-click the water to cast; a lure is applied first if your pole has none. "
        .. "Keybinds for cast and swap: Options > Keybindings > AddOns > FishFriend.")

    p.gearTick = 0
    p.live = true
end

local function RefreshOverview(p)
    local dataName, data = M.CurrentZone()
    local need = M.SkillNeeded(dataName, data)
    local rank, mod = M.GetFishingSkill()
    local eff = rank and (rank + mod)

    p.vals[1]:SetText(dataName .. (data and data.lvl and C(GREY, "  (" .. data.lvl .. ")") or ""))
    local learned = M.db.learned[dataName]
    p.vals[2]:SetText(need and (need .. (learned and C(GREY, "  (learned)") or "")) or C(GREY, "no data"))

    if not rank then
        p.vals[3]:SetText(C(RED, "Fishing not learned"))
        p.vals[4]:SetText("")
    else
        p.vals[3]:SetText(eff .. C(GREY, ("  (%d base + %d)"):format(rank, mod)))
        if not need then
            p.vals[4]:SetText(C(GREY, "unknown"))
        elseif eff >= need then
            p.vals[4]:SetText(C(GREEN, "No getaways"))
        else
            p.vals[4]:SetText(C(RED, "Fish will get away") .. C(GREY, "  (need +" .. (need - eff) .. ")"))
        end
    end

    local active, ms = M.LureActive()
    if active then
        local secs = math.floor((ms or 0) / 1000)
        p.vals[5]:SetText(C(GREEN, ("Active  %d:%02d"):format(math.floor(secs / 60), secs % 60)))
    else
        local lures = M.UsableLures()
        p.vals[5]:SetText(#lures > 0
            and (C(YELLOW, "None") .. C(GREY, "  (" .. lures[1].name .. " x" .. lures[1].count .. ", +" .. lures[1].bonus .. ")"))
            or C(GREY, "None in bags"))
    end

    if M.PoleEquipped() then
        p.vals[6]:SetText(C(GREEN, "Equipped"))
    else
        local pole = M.BestPoleInBags()
        p.vals[6]:SetText(pole and (W.ItemName(pole) .. C(GREY, "  in bags")) or C(RED, "None"))
    end

    -- Gear scan is heavier; refresh every 5s
    p.gearTick = p.gearTick - 1
    if p.gearTick <= 0 then
        p.gearTick = 5
        local gear = M.FindFishingGear()
        local i = 0
        for _, slot in ipairs(M.GEAR_SLOTS) do
            local g = gear[slot]
            if g and i < #p.gear then
                i = i + 1
                local worn = GetInventoryItemID("player", slot) == g.id
                p.gear[i]:SetText(C(GREY, M.SLOT_NAMES[slot] .. ": ") .. W.ItemName(g.id)
                    .. C(GREEN, " +" .. g.bonus) .. (worn and "" or C(GREY, "  (bags)")))
            end
        end
        if i == 0 then
            i = 1
            p.gear[1]:SetText(C(GREY, "No items with a Fishing bonus found"))
        end
        for j = i + 1, #p.gear do p.gear[j]:SetText("") end
    end
end

---------------------------------------------------------------------------
-- Page: Zones
---------------------------------------------------------------------------
local ZONE_COLS = { { 190 }, { 70, "CENTER" }, { 60, "CENTER" }, { 170 } }

local function BuildZones(p)
    p.summary = W.Text(p, 12)
    p.summary:SetPoint("TOPLEFT", 0, 0)
    p.summary:SetWidth(540)

    local db = M.db
    local f1 = Check(p, "Show other faction", function() return db.zonesAllFactions end,
        function(v) db.zonesAllFactions = v end)
    f1:SetPoint("TOPLEFT", 0, -22)
    f1:SetWidth(160)
    local f2 = Check(p, "Show dungeons", function() return db.zonesDungeons ~= false end,
        function(v) db.zonesDungeons = v end)
    f2:SetPoint("LEFT", f1, "RIGHT", 10, 0)
    f2:SetWidth(140)
    p.checks = { f1, f2 }

    local hdr = W.ListHeader(p, ZONE_COLS, { "Zone", "Levels", "Need", "For you" })
    hdr:SetPoint("TOPLEFT", 0, -48)
    hdr:SetPoint("RIGHT")
    p.list = W.List(p, ZONE_COLS, 20, 13)
    p.list:SetPoint("TOPLEFT", 0, -68)
    p.list:SetPoint("RIGHT")
end

local function RefreshZones(p)
    local db = M.db
    local rank, mod = M.GetFishingSkill()
    local eff = rank and (rank + mod) or 0
    local active = M.LureActive()
    local lures = M.UsableLures()
    local best = (not active and lures[1]) and lures[1] or nil
    local withLure = eff + (best and best.bonus or 0)
    local faction = UnitFactionGroup("player")
    local here = M.CurrentZone()

    if rank then
        p.summary:SetText(("Your skill %s"):format(C("ffffff", eff))
            .. (best and ("   ·   with " .. best.name .. " " .. C("ffffff", withLure)) or "")
            .. C(GREY, "   ·   catches give the same skill-ups anywhere you don't lose fish"))
    else
        p.summary:SetText(C(RED, "You haven't learned Fishing yet."))
    end

    local rows = {}
    for name, d in pairs(CF.FISH_ZONES) do
        local factionOK = db.zonesAllFactions or not d.faction or d.faction == faction
        local dungeonOK = db.zonesDungeons ~= false or not d.dungeon
        if factionOK and dungeonOK then
            local need = M.SkillNeeded(name, d)
            local status, r, g, b
            if not rank then status, r, g, b = "", 0.6, 0.6, 0.6
            elseif need <= eff then status, r, g, b = "No getaways", 0.4, 0.87, 0.4
            elseif need <= withLure then status, r, g, b = "With " .. best.name, 1, 0.8, 0.2
            else status, r, g, b = "Getaways (need +" .. (need - eff) .. ")", 1, 0.4, 0.4 end
            local label = name .. (d.dungeon and C("a335ee", "  dungeon") or "")
            rows[#rows + 1] = { cols = { label, d.lvl or "?", tostring(need), status },
                r = r, g = g, b = b, mark = (name == here), sortNeed = need, name = name }
        end
    end
    table.sort(rows, function(a, b)
        if a.sortNeed ~= b.sortNeed then return a.sortNeed < b.sortNeed end
        return a.name < b.name
    end)
    p.list:SetData(rows)
    for _, c in ipairs(p.checks) do c.Refresh() end
end

---------------------------------------------------------------------------
-- Page: Spots
---------------------------------------------------------------------------
local ZONELIST_COLS = { { 120 }, { 40, "RIGHT" } }
local SPOT_COLS = { { 140 }, { 46, "RIGHT" }, { 50, "RIGHT" }, { 120 } }

local function BuildSpots(p)
    local hdrL = W.ListHeader(p, ZONELIST_COLS, { "Zone", "Fish" })
    hdrL:SetPoint("TOPLEFT", 0, 0)
    hdrL:SetWidth(190)
    p.zones = W.List(p, ZONELIST_COLS, 20, 15)
    p.zones:SetPoint("TOPLEFT", 0, -20)
    p.zones:SetWidth(190)

    local hdrR = W.ListHeader(p, SPOT_COLS, { "Spot", "Fish", "Lost", "Top catches" })
    hdrR:SetPoint("TOPLEFT", 200, 0)
    hdrR:SetPoint("RIGHT")
    p.spots = W.List(p, SPOT_COLS, 20, 15)
    p.spots:SetPoint("TOPLEFT", 200, -20)
    p.spots:SetPoint("RIGHT")
end

local function RefreshSpots(p)
    local db = M.db
    local _, _, zoneHere = M.CurrentZone()

    local zoneTotals = {}
    for _, s in pairs(db.spots) do
        zoneTotals[s.zone] = (zoneTotals[s.zone] or 0) + s.catches
    end
    if not p.selected or not zoneTotals[p.selected] then
        p.selected = zoneTotals[zoneHere] and zoneHere or nil
    end

    local zrows = {}
    for zone, n in pairs(zoneTotals) do
        if not p.selected then p.selected = zone end
        zrows[#zrows + 1] = { cols = { zone, tostring(n) }, mark = (zone == p.selected), n = n,
            onClick = function() p.selected = zone; RefreshSpots(p) end }
    end
    table.sort(zrows, function(a, b) return a.n > b.n end)
    p.zones:SetData(zrows, "No catches yet.")

    local srows = {}
    for key, s in pairs(db.spots) do
        if s.zone == p.selected then
            local total = s.catches + s.getaways
            local pct = total > 0 and math.floor(s.getaways / total * 100 + 0.5) or 0
            local items = {}
            for id, n in pairs(s.items) do items[#items + 1] = { id = id, n = n } end
            table.sort(items, function(a, b) return a.n > b.n end)
            local top = {}
            for i = 1, math.min(2, #items) do top[#top + 1] = W.ItemName(items[i].id) end
            local spotName = key:match(" %- (.+)$") or key
            srows[#srows + 1] = { cols = { spotName, tostring(s.catches), pct .. "%", table.concat(top, ", ") },
                n = s.catches, r = pct > 20 and 1 or nil, g = pct > 20 and 0.6 or nil, b = pct > 20 and 0.6 or nil }
        end
    end
    table.sort(srows, function(a, b) return a.n > b.n end)
    p.spots:SetData(srows, "Go fish! Catches are logged here by subzone.")
end

---------------------------------------------------------------------------
-- Page: Session
---------------------------------------------------------------------------
local TOP_COLS = { { 380 }, { 60, "RIGHT" } }

local function BuildSession(p)
    p.tiles = {}
    local names = { "Catches", "Per hour", "Skill gained", "To next point" }
    for i, n in ipairs(names) do
        local t = CreateFrame("Frame", nil, p, "BackdropTemplate")
        t:SetSize(128, 58)
        t:SetPoint("TOPLEFT", (i - 1) * 137, 0)
        W.Flat(t, 1, 1, 1, 0.03, 1, 1, 1, 0.08)
        t.value = W.AccentText(t, 22)
        t.value:SetPoint("TOP", 0, -9)
        t.value:SetJustifyH("CENTER")
        t.label = W.Text(t, 11, 0.55, 0.55, 0.55)
        t.label:SetPoint("BOTTOM", 0, 8)
        t.label:SetJustifyH("CENTER")
        t.label:SetText(n)
        p.tiles[i] = t
    end

    p.detail = W.Text(p, 12)
    p.detail:SetPoint("TOPLEFT", 0, -72)
    p.detail:SetWidth(540)

    local h = W.Header(p, "Top catches")
    h:SetPoint("TOPLEFT", 0, -100)
    p.list = W.List(p, TOP_COLS, 20, 9)
    p.list:SetPoint("TOPLEFT", 0, -120)
    p.list:SetPoint("RIGHT")

    local reset = W.Button(p, "Reset session", 120, 24, function()
        M.NewSession()
        Changed()
    end)
    reset:SetPoint("BOTTOMRIGHT", 0, 0)
    p.live = true
end

local function RefreshSession(p)
    local s, n = M.SessionNumbers()
    p.tiles[1].value:SetText(s.catches)
    p.tiles[2].value:SetText(n.perHour)
    p.tiles[3].value:SetText("+" .. n.skill)
    p.tiles[4].value:SetText(n.capped and "capped" or (n.toNext and ("~" .. n.toNext) or "-"))

    local total = s.catches + s.getaways
    local rank = M.GetFishingSkill()
    local parts = {
        ("%d getaways (%d%%)"):format(s.getaways, total > 0 and math.floor(s.getaways / total * 100 + 0.5) or 0),
        ("~%d min fishing"):format(math.floor(s.active / 60)),
    }
    if rank and s.startRank then parts[#parts + 1] = ("skill %d -> %d"):format(s.startRank, rank) end
    if n.perPoint then parts[#parts + 1] = ("~%.1f catches per point"):format(n.perPoint) end
    if n.capped then parts[#parts + 1] = C(YELLOW, "train the next Fishing rank") end
    p.detail:SetText(table.concat(parts, C(GREY, "   ·   ")))

    local fish = {}
    for id, c in pairs(s.fish) do fish[#fish + 1] = { cols = { W.ItemName(id), "x" .. c }, c = c } end
    table.sort(fish, function(a, b) return a.c > b.c end)
    p.list:SetData(fish, "Nothing caught this session yet.")
end

---------------------------------------------------------------------------
-- Page: Settings
---------------------------------------------------------------------------
local function BuildSettings(p)
    local db = M.db
    local y = 0
    local function place(w, gap)
        w:SetPoint("TOPLEFT", 0, -y)
        y = y + (gap or 24)
    end

    place(W.Header(p, "Casting"), 22)
    p.items = {}
    local function add(w, gap) place(w, gap); p.items[#p.items + 1] = w end

    add(Check(p, "Double right-click to cast", function() return db.doubleClick end,
        function(v) db.doubleClick = v end, "Only with a fishing pole equipped, out of combat, not mounted."))
    add(Check(p, "Apply a lure automatically", function() return db.autoLure end,
        function(v) db.autoLure = v end, "When your pole has no lure, the cast applies one from your bags first."))
    add(Choice(p, "Lure choice", { { "best", "Best" }, { "smart", "Smart" } },
        function() return db.lureMode end, function(v) db.lureMode = v end), 30)

    place(W.Header(p, "Swapping"), 22)
    add(Check(p, "Also swap fishing gear (hat, boots, gloves...)", function() return db.swapGear end,
        function(v) db.swapGear = v end, "Any item whose tooltip shows a Fishing bonus is put on with the pole."), 30)

    place(W.Header(p, "Display"), 22)
    add(Check(p, "Show info bar while fishing", function() return db.showInfo end,
        function(v) db.showInfo = v end, "Shift-drag to move. Click it to open this window."))
    add(Check(p, "Show session stats on info bar", function() return db.showSessionOnInfo end,
        function(v) db.showSessionOnInfo = v end))

    local reset = W.Button(p, "Reset info bar position", 170, 22, function() M.ResetInfoPos() end)
    place(reset, 32)

    -- Right column: keybind help
    local h = W.Header(p, "Keybinds")
    h:SetPoint("TOPLEFT", 330, 0)
    local kb = W.Text(p, 12, 0.7, 0.7, 0.7)
    kb:SetPoint("TOPLEFT", 330, -24)
    kb:SetWidth(210)
    kb:SetWordWrap(true)
    kb:SetText("Options > Keybindings > AddOns > ConvrgeForever:\n\n"
        .. "|cffffffffSwap fishing pole / weapons|r\nworks in combat when going back to weapons.\n\n"
        .. "|cffffffffCast|r\nsame as double-click, lure included.\n\n"
        .. "Lure choice:\n|cffffffffBest|r uses your strongest lure.\n|cffffffffSmart|r uses the smallest lure that stops getaways in the current zone.")
end

local function RefreshSettings(p)
    for _, w in ipairs(p.items) do if w.Refresh then w.Refresh() end end
end


M.pages = {
    { key = "overview", label = "Overview", build = BuildOverview, refresh = RefreshOverview, live = true },
    { key = "zones",    label = "Zones",    build = BuildZones,    refresh = RefreshZones },
    { key = "spots",    label = "Spots",    build = BuildSpots,    refresh = RefreshSpots },
    { key = "session",  label = "Session",  build = BuildSession,  refresh = RefreshSession, live = true },
    { key = "settings", label = "Settings", build = BuildSettings, refresh = RefreshSettings },
}
