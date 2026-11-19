-- ConvrgeForever widget kit: flat dark style modeled on EllesmereUI.
-- When EllesmereUI is installed, everything made here is handed to its
-- Skinning API so it follows your EUI theme, accent color and font live.

local _, CF = ...
local W = {}
CF.W = W

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FALLBACK_FONT = "Fonts\\ARIALN.TTF"
W.WHITE = WHITE

W.ACCENT_PRESETS = {
    { 0.31, 0.76, 0.97 },  -- lake blue (default)
    { 0.05, 0.82, 0.62 },  -- teal
    { 0.98, 0.76, 0.18 },  -- gold
    { 0.95, 0.42, 0.30 },  -- coral
    { 0.67, 0.49, 0.98 },  -- violet
    { 0.55, 0.85, 0.35 },  -- green
}

W.skin = nil   -- EllesmereUI skin API (S), set at login if available
local fontStrings, buttons, editBoxes, accentTextures, accentTexts = {}, {}, {}, {}, {}

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------
function W.EUI() return W.skin and W.skin.IsEnabled and W.skin.IsEnabled() end

function W.Accent()
    if W.EUI() then return W.skin.GetAccentColor() end
    local a = (CF.db and CF.db.general.accent) or W.ACCENT_PRESETS[1]
    return a[1], a[2], a[3]
end

local function FontPath()
    if W.EUI() then
        local p, flags = W.skin.GetFont()
        return p or FALLBACK_FONT, flags or ""
    end
    return FALLBACK_FONT, ""
end

function W.ApplyAccent()
    local r, g, b = W.Accent()
    for _, t in ipairs(accentTextures) do t:SetColorTexture(r, g, b) end
    for _, fs in ipairs(accentTexts) do fs:SetTextColor(r, g, b) end
    if W.onAccent then W.onAccent() end
end

-- Hands everything created so far to EllesmereUI (each primitive is idempotent).
function W.ApplySkin(shell)
    if not W.EUI() then return end
    local S = W.skin
    if shell then
        S.Shell(shell)
        if shell.close and S.CloseButton then S.CloseButton(shell.close) end
    end
    for _, b in ipairs(buttons) do S.Button(b, { "bar" }) end   -- keep our accent underline
    for _, e in ipairs(editBoxes) do S.EditBox(e, { padInput = true }) end
    for _, fs in ipairs(fontStrings) do S.Font(fs) end
    W.ApplyAccent()
end

W.GREEN, W.YELLOW, W.RED, W.GREY = "66dd66", "ffcc33", "ff6666", "8a8a8a"
function W.C(hex, s) return "|cff" .. hex .. tostring(s) .. "|r" end

---------------------------------------------------------------------------
-- Basic pieces
---------------------------------------------------------------------------
function W.Flat(f, r, g, b, a, br, bg, bb, ba)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(r, g, b, a)
    f:SetBackdropBorderColor(br or 0, bg or 0, bb or 0, ba or 1)
end

function W.Text(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local path, flags = FontPath()
    fs:SetFont(path, size, flags)
    fs:SetTextColor(r or 0.9, g or 0.9, b or 0.9)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fontStrings[#fontStrings + 1] = fs
    return fs
end

function W.AccentText(parent, size)
    local fs = W.Text(parent, size)
    fs:SetTextColor(W.Accent())
    accentTexts[#accentTexts + 1] = fs
    return fs
end

function W.AccentTexture(parent, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetColorTexture(W.Accent())
    accentTextures[#accentTextures + 1] = t
    return t
end

function W.Header(parent, text)
    local fs = W.AccentText(parent, 13)
    fs:SetText(text)
    return fs
end

function W.Divider(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 0.08)
    t:SetHeight(1)
    return t
end

function W.Tooltip(widget, text)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", GameTooltip_Hide)
end

function W.ItemName(id)
    local name, _, quality = C_Item.GetItemInfo(id)
    name = name or C_Item.GetItemNameByID(id) or ("item " .. id)
    if quality and C_Item.GetItemQualityColor then
        local _, _, _, hex = C_Item.GetItemQualityColor(quality)
        if hex then return "|c" .. hex .. name .. "|r" end
    end
    return name
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
function W.Button(parent, label, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h or 22)
    W.Flat(b, 0.12, 0.12, 0.12, 1, 0.24, 0.24, 0.24, 1)
    b.text = W.Text(b, 12, 1, 1, 1)
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    b.text:SetText(label)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b:SetScript("OnClick", onClick)
    buttons[#buttons + 1] = b
    return b
end

-- Checkbox: get() returns bool, set(v) stores it, onChange() after a click
function W.Check(parent, label, get, set, tip, onChange)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(260, 20)
    local box = CreateFrame("Frame", nil, c, "BackdropTemplate")
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    W.Flat(box, 0.05, 0.05, 0.05, 1, 0.3, 0.3, 0.3, 1)
    local mark = W.AccentTexture(box)
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    c.label = W.Text(c, 12)
    c.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    c.label:SetText(label)
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", box, "TOPLEFT")
    hl:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT")
    hl:SetColorTexture(1, 1, 1, 0.1)
    c.Refresh = function() mark:SetShown(get() and true or false) end
    c:SetScript("OnClick", function()
        set(not get())
        c.Refresh()
        if onChange then onChange() end
    end)
    if tip then W.Tooltip(c, tip) end
    c.Refresh()
    return c
end

-- Segmented choice: options = { { value, label }, ... }
function W.Choice(parent, label, options, get, set, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 22)
    local l = W.Text(f, 12)
    l:SetPoint("LEFT")
    l:SetText(label)
    local segs, prev = {}, nil
    for _, o in ipairs(options) do
        local b = W.Button(f, o[2], 64, 20, function()
            set(o[1])
            f.Refresh()
            if onChange then onChange() end
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", l, "RIGHT", 10, 0) end
        b.bar = W.AccentTexture(b)
        b.bar:SetHeight(2)
        b.bar:SetPoint("BOTTOMLEFT", 1, 1)
        b.bar:SetPoint("BOTTOMRIGHT", -1, 1)
        b.value = o[1]
        segs[#segs + 1] = b
        prev = b
    end
    f.Refresh = function()
        for _, b in ipairs(segs) do
            local on = (get() == b.value)
            b.bar:SetShown(on)
            local c = on and 1 or 0.55
            b.text:SetTextColor(c, c, c)
        end
    end
    f.Refresh()
    return f
end

function W.EditBox(parent, width, placeholder, onChange)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(width, 24)
    e:SetAutoFocus(false)
    W.Flat(e, 0.04, 0.04, 0.04, 1, 0.26, 0.26, 0.26, 1)
    local path, flags = FontPath()
    e:SetFont(path, 13, flags)
    e:SetTextColor(1, 1, 1)
    e:SetTextInsets(8, 8, 0, 0)
    e.placeholder = W.Text(e, 12, 0.45, 0.45, 0.45)
    e.placeholder:SetPoint("LEFT", 8, 0)
    e.placeholder:SetText(placeholder or "")
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "")
        if onChange then onChange(self:GetText()) end
    end)
    editBoxes[#editBoxes + 1] = e
    return e
end

---------------------------------------------------------------------------
-- Scrolling list with columns. columns = { { width, justify }, ... }
-- Items: { cols = { ... }, r, g, b, mark = bool, onClick = fn, itemID = n }
-- Rows with itemID show the item tooltip on hover.
---------------------------------------------------------------------------
function W.List(parent, columns, rowH, nRows)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(rowH * nRows)
    f.rows, f.data, f.offset = {}, {}, 0

    for i = 1, nRows do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        row:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
        row.mark = W.AccentTexture(row, "BACKGROUND")
        row.mark:SetAllPoints()
        row.mark:SetAlpha(0.18)
        row.markBar = W.AccentTexture(row, "ARTWORK")
        row.markBar:SetWidth(2)
        row.markBar:SetPoint("TOPLEFT")
        row.markBar:SetPoint("BOTTOMLEFT")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        row.cols = {}
        local x = 8
        for c, col in ipairs(columns) do
            local fs = W.Text(row, 12)
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(col[1])
            fs:SetJustifyH(col[2] or "LEFT")
            row.cols[c] = fs
            x = x + col[1] + 6
        end
        row:SetScript("OnClick", function(self)
            if self.item and self.item.onClick then self.item.onClick() end
        end)
        row:SetScript("OnEnter", function(self)
            if self.item and self.item.itemID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.item.itemID)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        f.rows[i] = row
    end

    local track = f:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT")
    track:SetPoint("BOTTOMRIGHT")
    track:SetWidth(3)
    track:SetColorTexture(1, 1, 1, 0.05)
    local thumb = f:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(1, 1, 1, 0.45)

    f.empty = W.Text(f, 12, 0.55, 0.55, 0.55)
    f.empty:SetPoint("TOP", 0, -20)

    function f:Refresh()
        local n = #self.data
        for i, row in ipairs(self.rows) do
            local item = self.data[i + self.offset]
            row.item = item
            if item then
                for c, fs in ipairs(row.cols) do
                    fs:SetText(item.cols[c] or "")
                    fs:SetTextColor(item.r or 0.9, item.g or 0.9, item.b or 0.9)
                end
                row.mark:SetShown(item.mark and true or false)
                row.markBar:SetShown(item.mark and true or false)
                row:Show()
            else
                row:Hide()
            end
        end
        local visible = #self.rows
        if n > visible then
            local h = self:GetHeight()
            local th = math.max(16, h * visible / n)
            thumb:SetHeight(th)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", 0, -(h - th) * self.offset / (n - visible))
            thumb:Show(); track:Show()
        else
            thumb:Hide(); track:Hide()
        end
        self.empty:SetShown(n == 0)
    end

    function f:SetData(data, emptyText)
        self.data = data
        self.offset = math.max(0, math.min(self.offset, #data - #self.rows))
        self.empty:SetText(emptyText or "")
        self:Refresh()
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local maxOff = math.max(0, #self.data - #self.rows)
        self.offset = math.max(0, math.min(maxOff, self.offset - delta * 3))
        self:Refresh()
    end)
    return f
end

function W.ListHeader(parent, columns, labels)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(18)
    local x = 8
    for c, col in ipairs(columns) do
        local fs = W.Text(f, 11, 0.55, 0.55, 0.55)
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(col[1])
        fs:SetJustifyH(col[2] or "LEFT")
        fs:SetText(labels[c])
        x = x + col[1] + 6
    end
    local line = W.Divider(f)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    return f
end
