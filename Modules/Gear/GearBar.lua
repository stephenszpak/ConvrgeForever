-- Gear bar: a small movable bar with one button per kind of set.
--
--   [ Main ]   your equipment manager sets
--   [ Use  ]   on-use sets: click to put on, click again to use (secure, works
--              in combat), right-click to take off
--   [ Set  ]   custom sets: click to put on or take off
--
-- Hovering a button opens a menu of the sets of that kind, up or down like the
-- totem bar. Shift-drag a button to move the bar.
--
-- The Use button is a secure button so it can use your item in combat. Its
-- action is set out of combat only; the rest of the bar is ordinary frames.

local _, CF = ...
local W = CF.W
local M = CF.modules.gear
local C, GREEN, GREY = W.C, W.GREEN, W.GREY

local SIZE, GAP = 36, 4
local db, charDB
local layoutPending = true

local bar = CreateFrame("Frame", "ConvrgeGearBar", UIParent)
bar:SetSize(SIZE, SIZE)
bar:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:Hide()

local function SavePosition()
    bar:StopMovingOrSizing()
    local p, _, rp, x, y = bar:GetPoint()
    db.bar.point = { p, rp, x, y }
end

-- Secure clicks can arrive twice (key down and key up). Only the pass the game
-- acts on counts.
local function ActionPass(down)
    if down == nil then return true end
    local onDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    return down == (onDown and true or false)
end

---------------------------------------------------------------------------
-- Picks: which set each button shows
---------------------------------------------------------------------------
local function PickedSet(cat)
    local s = charDB.picks[cat] and M.SetByID(charDB.picks[cat])
    if s and s.kind == cat then return s end
    return M.SetsOf(cat)[1]
end

local function PickedMain()
    local sets = M.MainSets()
    for _, s in ipairs(sets) do
        if s.id == charDB.picks.main then return s end
    end
    for _, s in ipairs(sets) do
        if s.equipped then return s end
    end
    return sets[1]
end

-- On-use: the item and slot to press, and whether it's in that slot now.
local function UseState()
    local s = PickedSet("onuse")
    if not s then return end
    local item, slot = M.UseItem(s)
    local ready = item and GetInventoryItemID("player", slot) == item
    return s, item, slot, ready
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function Style(b)
    b:SetSize(SIZE, SIZE)
    W.Flat(b, 0, 0, 0, 0.6, 0.25, 0.25, 0.25, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
end

local function SetBorder(b, on)
    if on then
        local r, g, bl = W.Accent()
        b:SetBackdropBorderColor(r, g, bl, 1)
    else
        b:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
end

local function Movable(b)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
        if not db.bar.locked and IsShiftKeyDown() and not InCombatLockdown() then bar:StartMoving() end
    end)
    b:SetScript("OnDragStop", SavePosition)
end

local buttons = {}

local main = CreateFrame("Button", nil, bar, "BackdropTemplate")
Style(main)
Movable(main)
main:RegisterForClicks("LeftButtonUp")
main:SetScript("OnClick", function()
    if IsShiftKeyDown() then return end
    local s = PickedMain()
    if s then M.EquipMain(s.id) end
end)
main.cat = "main"
buttons[#buttons + 1] = main

local use = CreateFrame("Button", "ConvrgeGearOnUseButton", bar, "SecureActionButtonTemplate,BackdropTemplate")
Style(use)
Movable(use)
use.cat = "onuse"
buttons[#buttons + 1] = use

local custom = CreateFrame("Button", nil, bar, "BackdropTemplate")
Style(custom)
Movable(custom)
custom:RegisterForClicks("LeftButtonUp", "RightButtonUp")
custom:SetScript("OnClick", function(_, button)
    if IsShiftKeyDown() then return end
    local s = PickedSet("custom")
    if not s then CF.Open("gear") return end
    if button == "RightButton" then M.TakeOff(s) else M.Toggle(s) end
end)
custom.cat = "custom"
buttons[#buttons + 1] = custom

-- Hidden 1x1 copy of the Use button for the keybinding, so it works even with
-- the bar hidden.
local key = CreateFrame("Button", "ConvrgeGearUseButton", UIParent, "SecureActionButtonTemplate")
key:SetSize(1, 1)
key:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
key:EnableMouse(false)

-- Left: use the item if it's on, otherwise put the set on. Right: take it off.
-- Shift does nothing (Shift-drag moves the bar).
for _, b in ipairs({ use, key }) do
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "")
    -- Right-click and Shift never use the item, in combat either.
    b:SetAttribute("macrotext2", "")
    b:SetAttribute("shift-macrotext*", "")
    b:SetScript("PreClick", function(self, button)
        if InCombatLockdown() then return end
        local _, _, slot, ready = UseState()
        local act = button ~= "RightButton" and not IsShiftKeyDown() and ready
        self:SetAttribute("macrotext", act and ("/use " .. slot) or "")
    end)
    b:SetScript("PostClick", function(_, button, down)
        if not ActionPass(down) or IsShiftKeyDown() then return end
        local s, item, _, ready = UseState()
        if not s then CF.Open("gear") return end
        if button == "RightButton" then
            M.TakeOff(s)
        elseif not ready then
            if InCombatLockdown() then
                M.Say("can't put " .. (item and W.ItemName(item) or s.name) .. " on in combat.")
            else
                M.PutOn(s)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Flyout menu
---------------------------------------------------------------------------
local fly = CreateFrame("Frame", nil, bar)
fly:SetFrameStrata("DIALOG")
fly:Hide()
fly.entries = {}
local flyOwner

local function Entry(i)
    local e = fly.entries[i]
    if e then return e end
    e = CreateFrame("Button", nil, fly, "BackdropTemplate")
    Style(e)
    e:SetSize(SIZE - 4, SIZE - 4)
    e:RegisterForClicks("LeftButtonUp")
    e:SetScript("OnClick", function(self)
        if self.onClick then self.onClick() end
        fly:Hide()
    end)
    e:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.title or "", 1, 1, 1)
        if self.lines then
            for _, l in ipairs(self.lines) do GameTooltip:AddLine(l, 0.8, 0.8, 0.8) end
        end
        GameTooltip:Show()
    end)
    e:SetScript("OnLeave", GameTooltip_Hide)
    fly.entries[i] = e
    return e
end

local function SetLines(s)
    local lines = {}
    for _, slot in ipairs(M.SLOTS) do
        local id = s.slots[slot[1]]
        if id then lines[#lines + 1] = C(GREY, slot[2] .. ": ") .. W.ItemName(id) end
    end
    return lines
end

-- Menu entries for a button: { icon, title, lines, on, onClick }
local function EntriesFor(cat)
    local list = {}
    if cat == "main" then
        for _, s in ipairs(M.MainSets()) do
            local id = s.id
            list[#list + 1] = { icon = s.icon, title = s.name, on = s.equipped,
                lines = { s.equipped and C(GREEN, "equipped") or "Click to equip" },
                onClick = function() M.EquipMain(id) end }
        end
    else
        for _, s in ipairs(M.SetsOf(cat)) do
            local set = s
            local lines = SetLines(s)
            lines[#lines + 1] = " "
            lines[#lines + 1] = (cat == "onuse") and "Click to put it on; then use it from the bar."
                or (M.IsWorn(s) and "Click to take it off." or "Click to put it on.")
            list[#list + 1] = { icon = M.SetIcon(s), title = s.name, on = M.IsWorn(s), lines = lines,
                onClick = function()
                    charDB.picks[cat] = set.id
                    if cat == "onuse" then
                        if not M.IsWorn(set) then M.PutOn(set) else M.RefreshBar() end
                    else
                        M.Toggle(set)
                    end
                end }
        end
    end
    list[#list + 1] = { icon = "Interface\\Icons\\INV_Misc_Gear_01", title = "Gear page",
        lines = { "Make and edit sets." }, onClick = function() CF.Open("gear", "sets") end }
    return list
end

local function OpenFlyout(b, keepIdle)
    local list = EntriesFor(b.cat)
    flyOwner = b
    fly:ClearAllPoints()
    local up = db.bar.up
    if up then fly:SetPoint("BOTTOM", b, "TOP", 0, GAP) else fly:SetPoint("TOP", b, "BOTTOM", 0, -GAP) end
    fly:SetSize(SIZE, #list * SIZE)
    for i, item in ipairs(list) do
        local e = Entry(i)
        e:ClearAllPoints()
        local off = (i - 1) * SIZE
        if up then e:SetPoint("BOTTOM", fly, "BOTTOM", 0, off) else e:SetPoint("TOP", fly, "TOP", 0, -off) end
        e.icon:SetTexture(item.icon)
        e.title, e.lines, e.onClick = item.title, item.lines, item.onClick
        SetBorder(e, item.on)
        e:Show()
    end
    for i = #list + 1, #fly.entries do fly.entries[i]:Hide() end
    if not keepIdle then fly.idle = 0 end
    fly:Show()
end

fly:SetScript("OnUpdate", function(self, dt)
    if (flyOwner and flyOwner:IsMouseOver()) or self:IsMouseOver() then
        self.idle = 0
    else
        self.idle = (self.idle or 0) + dt
        if self.idle > 0.3 then self:Hide() end
    end
end)

local TIPS = {
    main = { "Main set", "Click: equip it. Hover: pick another." },
    onuse = { "On-use", "Click: put it on, then click again to use it.\nRight-click: take it off. Hover: pick another." },
    custom = { "Set", "Click: put it on or take it off.\nRight-click: take it off. Hover: pick another." },
}

for _, b in ipairs(buttons) do
    b:HookScript("OnEnter", function(self)
        OpenFlyout(self)
        local t = TIPS[self.cat]
        local name
        if self.cat == "main" then
            local s = PickedMain()
            name = s and s.name
        else
            local s = PickedSet(self.cat)
            name = s and s.name
        end
        GameTooltip:SetOwner(self, db.bar.up and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
        GameTooltip:SetText(t[1] .. (name and (": " .. name) or ""), 1, 1, 1)
        GameTooltip:AddLine(t[2], 0.8, 0.8, 0.8, true)
        if not db.bar.locked then GameTooltip:AddLine("Shift-drag: move the bar.", 0.55, 0.55, 0.55) end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- Layout and refresh
---------------------------------------------------------------------------
-- Shows only the buttons that have something in them. Protected while in
-- combat (the Use button is secure), so it waits for combat to end.
local function Layout()
    if InCombatLockdown() then layoutPending = true return end
    layoutPending = false
    local shown = {
        main = #M.MainSets() > 0,
        onuse = #M.SetsOf("onuse") > 0,
        custom = #M.SetsOf("custom") > 0,
    }
    local n = 0
    for _, b in ipairs(buttons) do
        if shown[b.cat] then
            b:ClearAllPoints()
            b:SetPoint("LEFT", bar, "LEFT", n * (SIZE + GAP), 0)
            b:Show()
            n = n + 1
        else
            b:Hide()
        end
    end
    bar:SetWidth(math.max(SIZE, n * (SIZE + GAP) - GAP))
    bar:SetShown(db.bar.show and n > 0)
    if not bar:IsShown() then fly:Hide() end
end

-- What can change at any time, combat included: icons, borders, cooldowns.
function M.RefreshBar()
    if not db then return end
    Layout()

    local m = PickedMain()
    main.icon:SetTexture(m and m.icon or 134400)
    SetBorder(main, m and m.equipped)

    local s, item, _, ready = UseState()
    use.icon:SetTexture(s and M.SetIcon(s) or 134400)
    use.icon:SetDesaturated(s ~= nil and not ready)
    SetBorder(use, ready)
    local start, duration = 0, 0
    if item then start, duration = M.Cooldown(item) end
    if duration > 0 then
        use.cd:SetCooldown(start, duration)
    elseif use.cd.Clear then
        use.cd:Clear()
    else
        use.cd:Hide()
    end

    local c = PickedSet("custom")
    custom.icon:SetTexture(c and M.SetIcon(c) or 134400)
    SetBorder(custom, c and M.IsWorn(c))

    -- The Use button's action follows the picked set (out of combat only).
    if not InCombatLockdown() then
        local _, _, slot, isReady = UseState()
        local text = isReady and ("/use " .. slot) or ""
        use:SetAttribute("macrotext", text)
        key:SetAttribute("macrotext", text)
    end

    if fly:IsShown() and flyOwner then OpenFlyout(flyOwner, true) end
end

function M.InitBar()
    db, charDB = M.db, M.char
    local pt = db.bar.point
    if pt then
        bar:ClearAllPoints()
        bar:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    end
    M.RefreshBar()
end
