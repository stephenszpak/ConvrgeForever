-- Gold module: movable widget + window pages (Session, Zones, History, Settings).

local _, CF = ...
local W = CF.W
local M = CF.modules.gold
local C, GREEN, RED, GREY = W.C, W.GREEN, W.RED, W.GREY
local Money = M.Money

local function SourceLabel(key)
    for _, s in ipairs(M.SOURCES) do if s.key == key then return s.label end end
    return key
end

local function ClassName(s)
    local name = (s.char or "?"):match("^[^-]+") or s.char or "?"
    local c = s.class and C_ClassColor and C_ClassColor.GetClassColor(s.class)
    return c and c:WrapTextInColorCode(name) or name
end

-- Earnings used for per-hour numbers: net gold, plus item value if enabled
local function Earned(gold, value)
    return gold + ((M.DB().countItemValue and value) or 0)
end

local function PerHourText(copper, sec)
    local ph = M.PerHour(copper, sec)
    return ph and (Money(ph) .. C(GREY, "/hr")) or C(GREY, "-")
end

---------------------------------------------------------------------------
-- Widget
---------------------------------------------------------------------------
local widget

function M.CreateWidget()
    if widget then return end
    local db = M.DB()
    local f = CreateFrame("Frame", "ConvrgeGoldWidget", UIParent, "BackdropTemplate")
    f:SetSize(180, 40)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    W.Flat(f, 0.04, 0.04, 0.04, 0.75, 0.2, 0.2, 0.2, 1)
    local edge = W.AccentTexture(f)
    edge:SetWidth(2)
    edge:SetPoint("TOPLEFT", 1, -1)
    edge:SetPoint("BOTTOMLEFT", 1, 1)

    f.line1 = W.Text(f, 13, 1, 1, 1)
    f.line1:SetPoint("TOPLEFT", 10, -6)
    f.line2 = W.Text(f, 11, 0.6, 0.6, 0.6)
    f.line2:SetPoint("TOPLEFT", f.line1, "BOTTOMLEFT", 0, -3)

    local pos = db.widget.pos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("TOP", UIParent, "TOP", 320, -24) end

    f:SetScript("OnDragStart", function(self)
        if db.widget.locked then return end
        self.dragging = true
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        db.widget.pos = { p, rp, x, y }
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if self.dragging then self.dragging = false return end
        if button == "LeftButton" or button == "RightButton" then CF.Open("gold") end
    end)
    f:SetScript("OnEnter", function(self)
        local s = M.Session()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Gold this session")
        GameTooltip:AddDoubleLine("Net", Money(M.Net(s), true), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Time", M.Duration(s.active), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Item value looted", Money(s.lootValue or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(" ")
        for _, src in ipairs(M.SOURCES) do
            local inc, exp = s.income[src.key] or 0, s.expense[src.key] or 0
            if inc > 0 or exp > 0 then
                local txt = (inc > 0 and C(GREEN, "+") .. Money(inc) or "") .. (inc > 0 and exp > 0 and "   " or "")
                    .. (exp > 0 and C(RED, "-") .. Money(exp) or "")
                GameTooltip:AddDoubleLine(src.label, txt, 0.8, 0.8, 0.8, 1, 1, 1)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(db.widget.locked and "Click: open details" or "Click: open details   Drag: move", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    widget = f
    M.UpdateWidget()
end

function M.UpdateWidget()
    if not widget then return end
    local db = M.DB()
    if not db.widget.show then widget:Hide() return end
    widget:Show()

    local s = M.Session()
    local net = M.Net(s)
    local ph = M.PerHour(Earned(net, s.lootValue or 0), s.active)
    widget.line1:SetText(M.Coins(net, true) .. (ph and C(GREY, "   " .. Money(ph) .. "/hr") or ""))

    local h = 26
    if db.widget.showZone then
        local zone = M.CurrentZoneName()
        local z = s.zones[zone]
        local zph = z and M.PerHour(Earned(z.gold, z.value), z.time)
        widget.line2:SetText(zone .. (zph and ("  " .. Money(zph) .. "/hr") or ""))
        widget.line2:Show()
        h = 42
    else
        widget.line2:Hide()
    end
    widget:SetHeight(h)
    widget:SetWidth(math.max(widget.line1:GetStringWidth(), db.widget.showZone and widget.line2:GetStringWidth() or 0) + 22)
end

function M.ResetWidgetPos()
    M.DB().widget.pos = nil
    if widget then
        widget:ClearAllPoints()
        widget:SetPoint("TOP", UIParent, "TOP", 320, -24)
    end
end

---------------------------------------------------------------------------
-- Page: Session
---------------------------------------------------------------------------
local SRC_COLS = { { 220 }, { 130, "RIGHT" }, { 130, "RIGHT" } }

local function BuildSession(p)
    p.tiles = {}
    for i, n in ipairs({ "Net gold", "Per hour", "Time played", "Item value looted" }) do
        local t = CreateFrame("Frame", nil, p, "BackdropTemplate")
        t:SetSize(128, 58)
        t:SetPoint("TOPLEFT", (i - 1) * 137, 0)
        W.Flat(t, 1, 1, 1, 0.03, 1, 1, 1, 0.08)
        t.value = W.Text(t, 16, 1, 1, 1)
        t.value:SetPoint("TOP", 0, -12)
        t.value:SetJustifyH("CENTER")
        t.label = W.Text(t, 11, 0.55, 0.55, 0.55)
        t.label:SetPoint("BOTTOM", 0, 8)
        t.label:SetJustifyH("CENTER")
        t.label:SetText(n)
        p.tiles[i] = t
    end

    W.Header(p, "By source"):SetPoint("TOPLEFT", 0, -72)
    local hdr = W.ListHeader(p, SRC_COLS, { "Source", "Earned", "Spent" })
    hdr:SetPoint("TOPLEFT", 0, -92)
    hdr:SetPoint("RIGHT")
    p.list = W.List(p, SRC_COLS, 20, 8)
    p.list:SetPoint("TOPLEFT", 0, -112)
    p.list:SetPoint("RIGHT")

    p.started = W.Text(p, 11, 0.55, 0.55, 0.55)
    p.started:SetPoint("BOTTOMLEFT", 0, 4)
    local reset = W.Button(p, "Reset session", 120, 24, function()
        M.ResetSession()
        M.UpdateWidget()
        CF.RefreshCurrent()
    end)
    reset:SetPoint("BOTTOMRIGHT", 0, 0)
    W.Tooltip(reset, "Saves this session to History and starts a new one.")
end

local function RefreshSession(p)
    local s = M.Session()
    local net = M.Net(s)
    p.tiles[1].value:SetText(Money(net, true))
    local ph = M.PerHour(Earned(net, s.lootValue or 0), s.active)
    p.tiles[2].value:SetText(ph and Money(ph) or "-")
    p.tiles[3].value:SetText(M.Duration(s.active))
    p.tiles[4].value:SetText(Money(s.lootValue or 0))

    local rows = {}
    for _, src in ipairs(M.SOURCES) do
        local inc, exp = s.income[src.key] or 0, s.expense[src.key] or 0
        if inc > 0 or exp > 0 then
            rows[#rows + 1] = { cols = { src.label, inc > 0 and Money(inc) or C(GREY, "-"), exp > 0 and Money(exp) or C(GREY, "-") } }
        end
    end
    p.list:SetData(rows, "No gold in or out yet this session.")
    p.started:SetText("Started " .. date("%b %d, %H:%M", s.start)
        .. "   ·   per hour " .. (M.DB().countItemValue and "includes item vendor value" or "is gold only"))
end

---------------------------------------------------------------------------
-- Page: Zones
---------------------------------------------------------------------------
local ZONE_COLS = { { 160 }, { 55, "RIGHT" }, { 90, "RIGHT" }, { 90, "RIGHT" }, { 90, "RIGHT" } }

local function BuildZones(p)
    local db = M.DB()
    local choice = W.Choice(p, "Show", { { "session", "Session" }, { "all", "All time" } },
        function() return db.zoneScope end, function(v) db.zoneScope = v end, function() CF.RefreshCurrent() end)
    choice:SetPoint("TOPLEFT", 0, 0)
    p.choice = choice
    p.note = W.Text(p, 11, 0.55, 0.55, 0.55)
    p.note:SetPoint("TOPLEFT", 0, -28)
    p.note:SetWidth(530)

    local hdr = W.ListHeader(p, ZONE_COLS, { "Zone", "Time", "Gold", "Item value", "Per hour" })
    hdr:SetPoint("TOPLEFT", 0, -48)
    hdr:SetPoint("RIGHT")
    p.list = W.List(p, ZONE_COLS, 20, 12)
    p.list:SetPoint("TOPLEFT", 0, -68)
    p.list:SetPoint("RIGHT")
end

local function RefreshZones(p)
    local db = M.DB()
    p.choice.Refresh()
    local source = (db.zoneScope == "all") and db.zones or M.Session().zones
    local here = M.CurrentZoneName()
    local rows = {}
    for zone, z in pairs(source) do
        if z.time > 0 or z.gold > 0 or z.value > 0 then
            local ph = M.PerHour(Earned(z.gold, z.value), z.time)
            rows[#rows + 1] = {
                cols = { zone, M.Duration(z.time), Money(z.gold), Money(z.value), ph and Money(ph) or C(GREY, "-") },
                mark = (zone == here), ph = ph or -1, t = z.time,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.ph ~= b.ph then return a.ph > b.ph end
        return a.t > b.t
    end)
    p.list:SetData(rows, "No zone data yet: go farm!")
    p.note:SetText("Gold counts mobs, chests, lockboxes and quests in that zone. Item value is what your drops "
        .. "sell to a vendor for. Best per hour first; under a minute shows -.")
end

---------------------------------------------------------------------------
-- Page: History
---------------------------------------------------------------------------
local HIST_COLS = { { 100 }, { 120 }, { 60, "RIGHT" }, { 100, "RIGHT" }, { 100, "RIGHT" } }

local function BuildHistory(p)
    local hdr = W.ListHeader(p, HIST_COLS, { "Date", "Character", "Time", "Net", "Per hour" })
    hdr:SetPoint("TOPLEFT", 0, 0)
    hdr:SetPoint("RIGHT")
    p.list = W.List(p, HIST_COLS, 20, 9)
    p.list:SetPoint("TOPLEFT", 0, -20)
    p.list:SetPoint("RIGHT")

    p.detail = W.Text(p, 12, 0.8, 0.8, 0.8)
    p.detail:SetPoint("TOPLEFT", 0, -208)
    p.detail:SetWidth(530)
    p.detail:SetWordWrap(true)
    p.detail:SetJustifyV("TOP")

    p.resetAll = W.Button(p, "Reset all", 140, 24, function(self)
        if p.confirmUntil and GetTime() < p.confirmUntil then
            p.confirmUntil = nil
            p.selected = nil
            M.ResetAll()
            M.UpdateWidget()
            CF.RefreshCurrent()
        else
            p.confirmUntil = GetTime() + 4
            self.text:SetText("Click again to confirm")
            C_Timer.After(4, function() self.text:SetText("Reset all") end)
        end
    end)
    p.resetAll:SetPoint("BOTTOMRIGHT", 0, 0)
    W.Tooltip(p.resetAll, "Deletes every saved session and all-time zone stats.")
    p.count = W.Text(p, 11, 0.55, 0.55, 0.55)
    p.count:SetPoint("BOTTOMLEFT", 0, 4)
end

local function Detail(s)
    local src = {}
    for _, d in ipairs(M.SOURCES) do
        local inc = s.income[d.key] or 0
        if inc > 0 then src[#src + 1] = d.label .. " " .. Money(inc) end
    end
    local zones = {}
    for zone, z in pairs(s.zones or {}) do
        local ph = M.PerHour(Earned(z.gold, z.value), z.time)
        if ph then zones[#zones + 1] = { zone = zone, ph = ph, t = z.time } end
    end
    table.sort(zones, function(a, b) return a.ph > b.ph end)
    local zt = {}
    for i = 1, math.min(3, #zones) do
        zt[#zt + 1] = zones[i].zone .. " " .. Money(zones[i].ph) .. "/hr " .. C(GREY, "(" .. M.Duration(zones[i].t) .. ")")
    end
    local spent = 0
    for _, v in pairs(s.expense) do spent = spent + v end
    return C(GREY, "Earned from: ") .. (#src > 0 and table.concat(src, ", ") or "nothing")
        .. "\n" .. C(GREY, "Spent: ") .. Money(spent)
        .. "   " .. C(GREY, "Item value looted: ") .. Money(s.lootValue or 0)
        .. "\n" .. C(GREY, "Best zones: ") .. (#zt > 0 and table.concat(zt, ",  ") or "-")
end

local function RefreshHistory(p)
    local rows = {}
    for i, s in ipairs(M.DB().history) do
        local net = s.net or M.Net(s)
        local ph = M.PerHour(Earned(net, s.lootValue or 0), s.active)
        rows[#rows + 1] = {
            cols = { date("%b %d %H:%M", s.start), ClassName(s), M.Duration(s.active),
                Money(net, true), ph and Money(ph) or C(GREY, "-") },
            mark = (p.selected == i),
            onClick = function() p.selected = i; CF.RefreshCurrent() end,
        }
    end
    p.list:SetData(rows, "No saved sessions yet. A session is saved when you log out, or with Reset session.")
    local sel = p.selected and M.DB().history[p.selected]
    p.detail:SetText(sel and Detail(sel) or C(GREY, "Click a session to see where the gold came from."))
    p.count:SetText(#rows .. " saved session" .. (#rows == 1 and "" or "s") .. " (keeps the last " .. (M.DB().maxHistory or 100) .. ")")
end

---------------------------------------------------------------------------
-- Page: Settings
---------------------------------------------------------------------------
local function BuildSettings(p)
    local db = M.DB()
    local function changed() M.UpdateWidget(); CF.RefreshCurrent() end
    W.Header(p, "Widget"):SetPoint("TOPLEFT", 0, 0)
    p.items = {
        W.Check(p, "Show gold widget", function() return db.widget.show end,
            function(v) db.widget.show = v end, nil, changed),
        W.Check(p, "Lock position", function() return db.widget.locked end,
            function(v) db.widget.locked = v end, nil, changed),
        W.Check(p, "Show current zone line", function() return db.widget.showZone end,
            function(v) db.widget.showZone = v end, nil, changed),
    }
    for i, w in ipairs(p.items) do w:SetPoint("TOPLEFT", 0, -24 - (i - 1) * 24) end
    local reset = W.Button(p, "Reset widget position", 160, 22, function() M.ResetWidgetPos() end)
    reset:SetPoint("TOPLEFT", 0, -102)

    W.Header(p, "Per hour"):SetPoint("TOPLEFT", 0, -140)
    local v = W.Check(p, "Include vendor value of looted items", function() return db.countItemValue end,
        function(x) db.countItemValue = x end,
        "Counts what your drops would sell for, so zones with good loot rank fairly against zones that drop raw gold.",
        changed)
    v:SetPoint("TOPLEFT", 0, -164)
    p.items[#p.items + 1] = v

    local t = W.Text(p, 11, 0.55, 0.55, 0.55)
    t:SetPoint("TOPLEFT", 0, -200)
    t:SetWidth(530)
    t:SetWordWrap(true)
    t:SetText("A session runs from login to logout (it survives /reload) and is saved to History when you log out "
        .. "or press Reset session. Time while AFK isn't counted. /gold opens this page, /gold reset starts a new session.")
end

local function RefreshSettings(p)
    for _, w in ipairs(p.items) do w.Refresh() end
end

M.pages = {
    { key = "session",  label = "Session",  build = BuildSession,  refresh = RefreshSession, live = true },
    { key = "zones",    label = "Zones",    build = BuildZones,    refresh = RefreshZones,   live = true },
    { key = "history",  label = "History",  build = BuildHistory,  refresh = RefreshHistory },
    { key = "settings", label = "Settings", build = BuildSettings, refresh = RefreshSettings },
}
