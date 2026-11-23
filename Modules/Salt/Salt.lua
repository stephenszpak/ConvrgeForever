-- Salt module: tracks the Salt Shaker cooldown (turns Deeprock Salt into
-- Refined Deeprock Salt) on every character, so you can see from any
-- character which shakers are ready.
--
-- The cooldown comes from the game (GetItemCooldown) and is stored as a
-- wall-clock time (time()), so it stays right after you log out. It's only
-- read while the shaker is in your bags: a banked shaker reports no cooldown.

local _, CF = ...
local W = CF.W
local C, GREEN, YELLOW, GREY = W.C, W.GREEN, W.YELLOW, W.GREY

local M = CF:NewModule("salt", {
    title = "Salt",
    description = "Salt Shaker cooldown for all your characters, with a reminder when one is ready.",
    defaults = {
        announce = true,     -- chat message when a shaker comes off cooldown
        sound = true,        -- play a sound with it
        loginList = true,    -- on login, list characters whose shaker is ready
        tooltip = true,      -- timers on the Salt Shaker tooltip
        chars = {},          -- ["Name-Ruleset"] = { class, readyAt, salt, refined, seen }
    },
})

local SHAKER = 15846           -- Salt Shaker
local SALT = 8150              -- Deeprock Salt
local REFINED = 15409          -- Refined Deeprock Salt

local db
local playerKey

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function ItemCooldown(id)
    local f = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
    if not f then return 0, 0 end
    local start, duration = f(id)
    return start or 0, duration or 0
end

local function Count(id, bank)
    return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, bank)) or GetItemCount(id, bank) or 0
end

function M.Duration(sec)
    sec = math.max(0, math.floor(sec))
    local d, h, m = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60
    if d > 0 then return ("%dd %dh %02dm"):format(d, h, m) end
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(math.max(1, m))
end

local function CharName(key, e)
    local name, realm = key:match("^(.-)%-(.+)$")
    name = name or key
    local c = e.class and C_ClassColor and C_ClassColor.GetClassColor(e.class)
    name = c and c:WrapTextInColorCode(name) or name
    if realm and realm ~= GetRealmName() then name = name .. C(GREY, " (" .. realm .. ")") end
    return name
end

local function IsReady(e) return (e.readyAt or 0) <= time() end

local function StatusText(e)
    if IsReady(e) then return C(GREEN, "Ready") end
    return C(YELLOW, M.Duration(e.readyAt - time()))
end

-- Characters with a shaker, ready ones first, then by time left
local function Sorted()
    local list = {}
    for key, e in pairs(db.chars) do list[#list + 1] = { key = key, e = e } end
    table.sort(list, function(a, b)
        local ra, rb = math.max(a.e.readyAt or 0, 0), math.max(b.e.readyAt or 0, 0)
        if IsReady(a.e) and IsReady(b.e) then return a.key < b.key end
        if ra ~= rb then return ra < rb end
        return a.key < b.key
    end)
    return list
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------
local alerted = {}   -- [key] = readyAt we already announced, this session

local started   -- false until cooldowns have had time to load after login

local function Scan()
    if not started then return end
    local inBags = Count(SHAKER, false) > 0
    local owned = inBags or Count(SHAKER, true) > 0
    if not owned then
        db.chars[playerKey] = nil
        return
    end
    local e = db.chars[playerKey] or {}
    db.chars[playerKey] = e
    e.class = select(2, UnitClass("player"))
    e.salt, e.refined = Count(SALT, true), Count(REFINED, true)
    e.seen = time()
    if inBags then
        local start, duration = ItemCooldown(SHAKER)
        if start > 0 and duration > 2 then          -- ignore the global cooldown
            e.readyAt = math.floor(time() + (start + duration - GetTime()) + 0.5)
        else
            e.readyAt = e.readyAt and math.min(e.readyAt, time()) or time()
        end
    end
    e.readyAt = e.readyAt or 0
end

local function Names(keys)
    local t = {}
    for i, k in ipairs(keys) do t[i] = CharName(k, db.chars[k]) end
    return table.concat(t, ", ")
end

local function Announce(keys)
    if #keys == 0 then return end
    CF.Print("Salt Shaker ready on " .. Names(keys) .. ".", "Salt")
    if db.sound and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING or 8959, "Master") end
end

-- Once a minute: announce shakers that came off cooldown while you're online.
local function Tick()
    if not db.announce then return end
    local now, ready = time(), {}
    for key, e in pairs(db.chars) do
        local at = e.readyAt or 0
        if at <= now and at > 0 and alerted[key] ~= at then
            alerted[key] = at
            ready[#ready + 1] = key
        end
    end
    table.sort(ready)
    Announce(ready)
end

local function LoginList()
    -- Anything already ready counts as announced, so Tick doesn't repeat it.
    local ready = {}
    for key, e in pairs(db.chars) do
        if IsReady(e) then
            alerted[key] = e.readyAt or 0
            ready[#ready + 1] = key
        end
    end
    table.sort(ready)
    if db.loginList and #ready > 0 then
        CF.Print("Salt Shaker ready on " .. Names(ready) .. ".", "Salt")
    end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function AddToTooltip(tt, id)
    if id ~= SHAKER or not db.tooltip or not next(db.chars) then return end
    tt:AddLine(" ")
    for _, row in ipairs(Sorted()) do
        tt:AddDoubleLine(CharName(row.key, row.e), StatusText(row.e), 1, 1, 1, 1, 1, 1)
    end
    tt:Show()
end

local function HookTooltips()
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            local id = data and data.id
            if id == nil or (issecretvalue and issecretvalue(id)) then return end
            AddToTooltip(tooltip, id)
        end)
    else
        local function hook(tt)
            tt:HookScript("OnTooltipSetItem", function(self)
                local _, link = self:GetItem()
                AddToTooltip(self, link and tonumber(link:match("item:(%d+)")))
            end)
        end
        hook(GameTooltip)
        hook(ItemRefTooltip)
    end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
function M:OnLogin()
    db = self.db
    playerKey = UnitName("player") .. "-" .. GetRealmName()
    HookTooltips()

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("BAG_UPDATE_COOLDOWN")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("BANKFRAME_OPENED")
    f:RegisterEvent("BANKFRAME_CLOSED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            f:UnregisterEvent("PLAYER_ENTERING_WORLD")
            -- Item cooldowns can arrive a moment after login.
            C_Timer.After(3, function()
                started = true
                Scan()
                LoginList()
            end)
        else
            Scan()
        end
    end)
    C_Timer.NewTicker(60, Tick)
end

function M:slash(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "help" then
        CF.Print("/cf salt  - Salt Shaker timers in chat;  /cf salt window  - open the Salt page", "Salt")
        return
    elseif msg == "window" then
        CF.Open("salt")
        return
    end
    Scan()
    local list = Sorted()
    if #list == 0 then CF.Print("no characters with a Salt Shaker yet.", "Salt") return end
    for _, row in ipairs(list) do
        print("   " .. CharName(row.key, row.e) .. ": " .. StatusText(row.e))
    end
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local COLS = { { 170 }, { 110 }, { 110 }, { 60, "RIGHT" }, { 60, "RIGHT" } }

local function BuildPage(p)
    W.Header(p, "Salt Shaker timers"):SetPoint("TOPLEFT", 0, 0)
    local hdr = W.ListHeader(p, COLS, { "Character", "Status", "Ready at", "Salt", "Refined" })
    hdr:SetPoint("TOPLEFT", 0, -22)
    hdr:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    p.list = W.List(p, COLS, 20, 8)
    p.list:SetPoint("TOPLEFT", 0, -42)
    p.list:SetPoint("RIGHT", p, "RIGHT", 0, 0)

    W.Header(p, "Reminders"):SetPoint("TOPLEFT", 0, -218)
    p.items = {
        W.Check(p, "Chat message when a shaker is ready", function() return db.announce end,
            function(v) db.announce = v end, "Checked once a minute while you're logged in, for every character."),
        W.Check(p, "Play a sound with it", function() return db.sound end, function(v) db.sound = v end),
        W.Check(p, "List ready shakers when you log in", function() return db.loginList end,
            function(v) db.loginList = v end),
        W.Check(p, "Show timers on the Salt Shaker tooltip", function() return db.tooltip end,
            function(v) db.tooltip = v end),
    }
    for i, w in ipairs(p.items) do w:SetPoint("TOPLEFT", 0, -240 - (i - 1) * 24) end

    local note = W.Text(p, 11, 0.55, 0.55, 0.55)
    note:SetPoint("TOPLEFT", 0, -344)
    note:SetWidth(520)
    note:SetWordWrap(true)
    note:SetText("A character shows up here once you log in with a Salt Shaker in its bags or bank. "
        .. "The timer updates while the shaker is in your bags; one kept in the bank keeps its last known time. "
        .. "Salt and Refined count bags and bank.")
end

local function RefreshPage(p)
    for _, w in ipairs(p.items) do w.Refresh() end
    local data = {}
    for _, row in ipairs(Sorted()) do
        local e = row.e
        data[#data + 1] = {
            cols = {
                CharName(row.key, e),
                StatusText(e),
                IsReady(e) and C(GREY, "-") or date("%a %H:%M", e.readyAt),
                tostring(e.salt or 0),
                tostring(e.refined or 0),
            },
            mark = row.key == playerKey,
        }
    end
    p.list:SetData(data, "No Salt Shaker found yet. Log in on a character that has one.")
end

M.pages = {
    { key = "salt", label = "Salt", build = BuildPage, refresh = RefreshPage, live = true },
}
