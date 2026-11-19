-- ConvrgeForever window: sidebar with General + one entry per module,
-- each module's pages shown as tabs. Also the minimap button and the
-- EllesmereUI skin registration.

local _, CF = ...
local W = CF.W
local C, GREY, GREEN, YELLOW = W.C, W.GREY, W.GREEN, W.YELLOW

local frame
local sections = {}      -- key -> { nav, host, tabs, pages, defs, current }
local sectionOrder = {}
local currentSection

---------------------------------------------------------------------------
-- General page
---------------------------------------------------------------------------
local function BuildGeneral(p)
    local db = CF.db
    local y = 0
    W.Header(p, "Modules"):SetPoint("TOPLEFT", 0, -y)
    y = y + 24

    p.moduleRows = {}
    for _, key in ipairs(CF.moduleOrder) do
        local m = CF.modules[key]
        local check = W.Check(p, m.title,
            function() return db.modules[key] ~= false end,
            function(v) db.modules[key] = v end,
            nil,
            function() CF.RefreshCurrent() end)
        check:SetPoint("TOPLEFT", 0, -y)
        local desc = W.Text(p, 11, 0.55, 0.55, 0.55)
        desc:SetPoint("TOPLEFT", 22, -y - 20)
        desc:SetWidth(500)
        desc:SetText(m.description or "")
        local status = W.Text(p, 11)
        status:SetPoint("LEFT", check.label, "RIGHT", 10, 0)
        p.moduleRows[#p.moduleRows + 1] = { key = key, check = check, status = status }
        y = y + 44
    end

    local note = W.Text(p, 11, 0.55, 0.55, 0.55)
    note:SetPoint("TOPLEFT", 0, -y)
    note:SetText("Turning a module on or off takes effect after a reload.")
    local reload = W.Button(p, "Reload UI", 100, 22, function() ReloadUI() end)
    reload:SetPoint("LEFT", note, "RIGHT", 12, 0)
    y = y + 40

    W.Header(p, "Appearance"):SetPoint("TOPLEFT", 0, -y)
    y = y + 24
    p.minimapCheck = W.Check(p, "Show minimap button",
        function() return not db.general.minimap.hide end,
        function(v) db.general.minimap.hide = not v end,
        nil, function() CF.UpdateMinimapButton() end)
    p.minimapCheck:SetPoint("TOPLEFT", 0, -y)
    y = y + 28

    p.accentLabel = W.Text(p, 12)
    p.accentLabel:SetPoint("TOPLEFT", 0, -y - 3)
    p.swatches = {}
    for i, c in ipairs(W.ACCENT_PRESETS) do
        local s = CreateFrame("Button", nil, p, "BackdropTemplate")
        s:SetSize(18, 18)
        s:SetPoint("TOPLEFT", 100 + (i - 1) * 24, -y)
        W.Flat(s, c[1], c[2], c[3], 1, 0, 0, 0, 1)
        s:SetScript("OnClick", function()
            db.general.accent = { c[1], c[2], c[3] }
            W.ApplyAccent()
        end)
        p.swatches[i] = s
    end
    y = y + 40

    W.Header(p, "About"):SetPoint("TOPLEFT", 0, -y)
    local about = W.Text(p, 12, 0.7, 0.7, 0.7)
    about:SetPoint("TOPLEFT", 0, -y - 24)
    about:SetText("ConvrgeForever " .. CF.version .. "   ·   /cf opens this window   ·   /cf help for commands")
end

local function RefreshGeneral(p)
    for _, row in ipairs(p.moduleRows) do
        local m = CF.modules[row.key]
        row.check.Refresh()
        local wanted = CF.db.modules[row.key] ~= false
        if m.blockedByLegacy then
            row.status:SetText(C(YELLOW, "paused: disable " .. m.legacyAddon .. " and reload"))
        elseif wanted ~= (m.running and true or false) then
            row.status:SetText(C(YELLOW, "reload to apply"))
        elseif m.running then
            row.status:SetText(C(GREEN, "running"))
        else
            row.status:SetText(C(GREY, "off"))
        end
    end
    p.minimapCheck.Refresh()
    local themed = W.EUI()
    p.accentLabel:SetText(themed and C(GREY, "Colors follow your EllesmereUI theme.") or "Accent color")
    for _, s in ipairs(p.swatches) do s:SetShown(not themed) end
end

---------------------------------------------------------------------------
-- Sections (General + modules), each with optional tabs
---------------------------------------------------------------------------
local function SelectTab(sec, key)
    for _, t in ipairs(sec.tabs) do
        local on = (t.key == key)
        t.bar:SetShown(on)
        local c = on and 1 or 0.55
        t.text:SetTextColor(c, c, c)
    end
end

local function ShowPage(sec, key)
    for _, def in ipairs(sec.defs) do
        local p = sec.pages[def.key]
        if def.key == key then
            if not p.built then def.build(p); p.built = true end
            p:Show()
            def.refresh(p)
            sec.current = def
        else
            p:Hide()
        end
    end
    SelectTab(sec, key)
    W.ApplySkin(frame)   -- skins widgets the page just created (idempotent)
end

local function BuildSection(key, title, defs, offMessage)
    local sec = { key = key, title = title, defs = defs, tabs = {}, pages = {} }
    local host = CreateFrame("Frame", nil, frame)
    host:SetPoint("TOPLEFT", 168, -40)
    host:SetPoint("BOTTOMRIGHT", -18, 16)
    host:Hide()
    sec.host = host

    local top = 0
    if #defs > 1 then
        local prev
        for _, def in ipairs(defs) do
            local t = CreateFrame("Button", nil, host)
            t:SetSize(96, 28)
            if prev then t:SetPoint("LEFT", prev, "RIGHT", 2, 0) else t:SetPoint("TOPLEFT", -8, 0) end
            t.text = W.Text(t, 13)
            t.text:SetPoint("CENTER")
            t.text:SetJustifyH("CENTER")
            t.text:SetText(def.label)
            t.bar = W.AccentTexture(t)
            t.bar:SetHeight(2)
            t.bar:SetPoint("BOTTOMLEFT", 8, 0)
            t.bar:SetPoint("BOTTOMRIGHT", -8, 0)
            local hl = t:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.04)
            t.key = def.key
            t:SetScript("OnClick", function() ShowPage(sec, def.key) end)
            sec.tabs[#sec.tabs + 1] = t
            prev = t
        end
        local line = W.Divider(host)
        line:SetPoint("TOPLEFT", -18, -28)
        line:SetPoint("TOPRIGHT", 18, -28)
        top = 40
    end

    for _, def in ipairs(defs) do
        local p = CreateFrame("Frame", nil, host)
        p:SetPoint("TOPLEFT", 0, -top)
        p:SetPoint("BOTTOMRIGHT")
        p:Hide()
        sec.pages[def.key] = p
    end

    if offMessage then
        sec.off = W.Text(host, 13, 0.6, 0.6, 0.6)
        sec.off:SetPoint("TOPLEFT", 0, -top)
        sec.off:SetWidth(520)
        sec.off:SetWordWrap(true)
    end
    sections[key] = sec
    sectionOrder[#sectionOrder + 1] = key
    return sec
end

local function UpdateNav()
    for _, key in ipairs(sectionOrder) do
        local sec = sections[key]
        local on = (key == currentSection)
        sec.nav.bar:SetShown(on)
        sec.nav.bg:SetShown(on)
        local m = CF.modules[key]
        local dim = m and not m.running
        local c = on and 1 or (dim and 0.4 or 0.7)
        sec.nav.text:SetTextColor(c, c, c)
    end
end

function CF.ShowSection(key, pageKey)
    if not frame then return end
    local sec = sections[key]
    if not sec then return end
    currentSection = key
    for k, s in pairs(sections) do s.host:SetShown(k == key) end

    local m = CF.modules[key]
    local running = (not m) or m.running
    if sec.off then
        sec.off:SetShown(not running)
        if not running then
            sec.off:SetText(m.blockedByLegacy
                and ("The " .. m.title .. " module is paused while " .. m.legacyAddon .. " is enabled. Disable " .. m.legacyAddon .. " in your AddOns list and reload.")
                or ("The " .. m.title .. " module is off. Turn it on under General, then reload."))
        end
    end
    for _, t in ipairs(sec.tabs) do t:SetShown(running) end
    if running then
        ShowPage(sec, pageKey or (sec.current and sec.current.key) or sec.defs[1].key)
    else
        for _, p in pairs(sec.pages) do p:Hide() end
    end
    UpdateNav()
end

function CF.RefreshCurrent()
    if not frame or not frame:IsShown() or not currentSection then return end
    local sec = sections[currentSection]
    local m = CF.modules[currentSection]
    if sec.current and ((not m) or m.running) then sec.current.refresh(sec.pages[sec.current.key]) end
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local function CreateWindow()
    local f = CreateFrame("Frame", "ConvrgeForeverFrame", UIParent, "BackdropTemplate")
    f:SetSize(730, 460)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    W.Flat(f, 0.067, 0.067, 0.067, 0.94, 0.18, 0.18, 0.18, 1)
    tinsert(UISpecialFrames, "ConvrgeForeverFrame")   -- Escape closes it
    frame = f

    local title = CreateFrame("Frame", nil, f, "BackdropTemplate")
    title:SetPoint("TOPLEFT", 1, -1)
    title:SetPoint("TOPRIGHT", -1, -1)
    title:SetHeight(30)
    title:SetBackdrop({ bgFile = W.WHITE })
    title:SetBackdropColor(0, 0, 0, 0.35)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() f:StartMoving() end)
    title:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local name = W.Text(title, 14, 1, 1, 1)
    name:SetPoint("LEFT", 12, 0)
    name:SetText("Convrge")
    local name2 = W.AccentText(title, 14)
    name2:SetPoint("LEFT", name, "RIGHT", 0, 0)
    name2:SetText("Forever")
    local ver = W.Text(title, 11, 0.45, 0.45, 0.45)
    ver:SetPoint("LEFT", name2, "RIGHT", 8, -1)
    ver:SetText(CF.version)

    local close = CreateFrame("Button", nil, title)
    close:SetSize(30, 30)
    close:SetPoint("RIGHT")
    close.text = W.Text(close, 14, 0.6, 0.6, 0.6)
    close.text:SetPoint("CENTER")
    close.text:SetText("x")
    close:SetScript("OnEnter", function() close.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function() close.text:SetTextColor(0.6, 0.6, 0.6) end)
    close:SetScript("OnClick", function() f:Hide() end)
    f.close = close

    -- Sidebar
    local side = CreateFrame("Frame", nil, f, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 1, -31)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(150)
    side:SetBackdrop({ bgFile = W.WHITE })
    side:SetBackdropColor(0, 0, 0, 0.2)
    local sideLine = side:CreateTexture(nil, "ARTWORK")
    sideLine:SetColorTexture(1, 1, 1, 0.06)
    sideLine:SetWidth(1)
    sideLine:SetPoint("TOPRIGHT")
    sideLine:SetPoint("BOTTOMRIGHT")

    BuildSection("general", "General", { { key = "general", label = "General", build = BuildGeneral, refresh = RefreshGeneral } })
    for _, key in ipairs(CF.moduleOrder) do
        local m = CF.modules[key]
        if m.pages then BuildSection(key, m.title, m.pages, true) end
    end

    for i, key in ipairs(sectionOrder) do
        local sec = sections[key]
        local b = CreateFrame("Button", nil, side)
        b:SetHeight(30)
        b:SetPoint("TOPLEFT", 0, -10 - (i - 1) * 32)
        b:SetPoint("RIGHT", -1, 0)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(1, 1, 1, 0.05)
        b.bar = W.AccentTexture(b)
        b.bar:SetWidth(2)
        b.bar:SetPoint("TOPLEFT")
        b.bar:SetPoint("BOTTOMLEFT")
        b.text = W.Text(b, 13)
        b.text:SetPoint("LEFT", 16, 0)
        b.text:SetText(sec.title)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.04)
        b:SetScript("OnClick", function() CF.ShowSection(key) end)
        sec.nav = b
    end

    -- Live refresh for pages marked live
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        local sec = currentSection and sections[currentSection]
        if sec and sec.current and sec.current.live then CF.RefreshCurrent() end
    end)
    f:SetScript("OnShow", CF.RefreshCurrent)

    -- Open on the first running module, else General
    local first = "general"
    for _, key in ipairs(CF.moduleOrder) do
        if CF.modules[key].running and sections[key] then first = key; break end
    end
    CF.ShowSection(first)
    f:Hide()
end

function CF.ToggleUI()
    if not CF.db then return end
    if not frame then CreateWindow() end
    frame:SetShown(not frame:IsShown())
end

-- Open the window on a module (and optionally one of its pages)
function CF.Open(key, pageKey)
    if not CF.db then return end
    if not frame then CreateWindow() end
    frame:Show()
    CF.ShowSection(key, pageKey)
end

function ConvrgeForever_Toggle() CF.ToggleUI() end   -- addon compartment entry

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local minimapButton

local function PositionMinimapButton()
    local a = math.rad(CF.db.general.minimap.angle or 200)
    local r = (Minimap:GetWidth() / 2) + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "ConvrgeForeverMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            for _, key in ipairs(CF.moduleOrder) do
                local m = CF.modules[key]
                if m.running and m.OnMinimapRightClick then m:OnMinimapRightClick(); return end
            end
        end
        CF.ToggleUI()
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            CF.db.general.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PositionMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("ConvrgeForever")
        GameTooltip:AddLine("Left-click: open window", 0.8, 0.8, 0.8)
        for _, key in ipairs(CF.moduleOrder) do
            local m = CF.modules[key]
            if m.running and m.minimapRightClickText then
                GameTooltip:AddLine("Right-click: " .. m.minimapRightClickText, 0.8, 0.8, 0.8)
                break
            end
        end
        GameTooltip:AddLine("Drag: move", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    minimapButton = b
    PositionMinimapButton()
end

function CF.UpdateMinimapButton()
    if not Minimap or not CF.db then return end
    if not minimapButton then CreateMinimapButton() end
    minimapButton:SetShown(not CF.db.general.minimap.hide)
end

---------------------------------------------------------------------------
-- Startup + EllesmereUI skin
---------------------------------------------------------------------------
function CF.InitWindow()
    CF.UpdateMinimapButton()
end

W.onAccent = function()
    if currentSection then UpdateNav() end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin("ConvrgeForever", function(S)
        W.skin = S
        if S.OnLooksChanged then S.OnLooksChanged(W.ApplyAccent) end
        if frame then W.ApplySkin(frame) end
    end)
end
