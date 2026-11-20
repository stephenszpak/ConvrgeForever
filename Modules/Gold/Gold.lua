-- Gold module: tracks gold earned and spent, by source and by zone, per
-- session. Sessions are saved to a history so you can compare farming runs.
--
-- Every money change is tagged with what you were doing when it happened:
--   loot (mobs), chests (world objects), containers (lockboxes, clams...),
--   quests, vendor, repair, trade, auction (sales come by mail), mail,
--   travel (flight paths), other.
-- Item drops are also valued at their vendor price, per zone, so a zone
-- with lots of sellable loot ranks fairly against raw-gold zones.

local _, CF = ...
local W = CF.W

local M = CF:NewModule("gold", {
    title = "Gold",
    description = "Movable gold tracker: session earnings, gold per hour, best farming zones and session history.",
    defaults = {
        widget = { show = true, locked = false, showZone = true },
        countItemValue = true,     -- include vendor value of looted items in per-hour numbers
        zoneScope = "session",
        zones = {},                -- all-time, account-wide: [zone] = { time, gold, value }
        history = {},              -- archived sessions, newest first
        maxHistory = 100,
    },
    charDefaults = {
        -- session = { ... } current session for this character
    },
})

M.SOURCES = {
    { key = "loot",       label = "Mobs" },
    { key = "chests",     label = "Chests" },
    { key = "containers", label = "Lockboxes & containers" },
    { key = "quests",     label = "Quests" },
    { key = "vendor",     label = "Vendor" },
    { key = "repair",     label = "Repairs" },
    { key = "trade",      label = "Trades" },
    { key = "auction",    label = "Auction house" },
    { key = "mail",       label = "Mail" },
    { key = "travel",     label = "Flight paths" },
    { key = "other",      label = "Other" },
}
local FARM_SOURCES = { loot = true, chests = true, containers = true, quests = true }

local db, charDB
local lastMoney
local playerKey, playerClass

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
local GOLD_C, SILVER_C, COPPER_C = "ffd700", "c7c7cf", "eda55f"

-- Compact text: 12g 34s / 5s 10c / 7c
function M.Money(c, signed)
    c = math.floor(c or 0)
    local sign = ""
    if c < 0 then sign = "-"; c = -c elseif signed and c > 0 then sign = "+" end
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local t
    if g > 0 then
        t = BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)
        t = t .. "|cff" .. GOLD_C .. "g|r " .. s .. "|cff" .. SILVER_C .. "s|r"
    elseif s > 0 then
        t = s .. "|cff" .. SILVER_C .. "s|r " .. cp .. "|cff" .. COPPER_C .. "c|r"
    else
        t = cp .. "|cff" .. COPPER_C .. "c|r"
    end
    return sign .. t
end

-- With coin icons, for the widget
function M.Coins(c, signed)
    c = math.floor(c or 0)
    local sign = ""
    if c < 0 then sign = "-"; c = -c elseif signed and c > 0 then sign = "+" end
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return sign .. (f and f(c) or M.Money(c))
end

function M.Duration(sec)
    sec = math.floor(sec or 0)
    local h, m = math.floor(sec / 3600), math.floor(sec / 60) % 60
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(m)
end

-- Copper per hour, or nil if under a minute of data
function M.PerHour(copper, sec)
    if not sec or sec < 60 then return nil end
    return copper / sec * 3600
end

---------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------
local function NewSession()
    charDB.session = {
        start = time(), char = playerKey, class = playerClass,
        active = 0, income = {}, expense = {}, lootValue = 0, zones = {},
    }
    return charDB.session
end

local function Session() return charDB.session or NewSession() end
M.Session = Session

function M.Net(s)
    local n = 0
    for _, v in pairs(s.income) do n = n + v end
    for _, v in pairs(s.expense) do n = n - v end
    return n
end

local function Meaningful(s)
    if s.active >= 60 or (s.lootValue or 0) > 0 then return true end
    for _ in pairs(s.income) do return true end
    for _ in pairs(s.expense) do return true end
    return false
end

local function Archive()
    local s = charDB.session
    if not s or not Meaningful(s) then return end
    s.stop = time()
    s.net = M.Net(s)
    table.insert(db.history, 1, s)
    while #db.history > (db.maxHistory or 100) do table.remove(db.history) end
end

function M.ResetSession()
    Archive()
    NewSession()
    lastMoney = GetMoney()
    CF.Print("session saved to history; new session started.", "Gold")
end

function M.ResetAll()
    db.history = {}
    db.zones = {}
    NewSession()
    lastMoney = GetMoney()
    CF.Print("all gold history cleared.", "Gold")
end

local function ZoneEntry(t, zone)
    local z = t[zone]
    if not z then z = { time = 0, gold = 0, value = 0 }; t[zone] = z end
    return z
end

local function CurrentZoneName()
    local z = GetRealZoneText()
    return (z and z ~= "") and z or "Unknown"
end
M.CurrentZoneName = CurrentZoneName

---------------------------------------------------------------------------
-- Source context: what were you doing when the money changed?
-- "base" comes from open windows (vendor, mailbox, AH...); "override" is a
-- short-lived tag from a specific action (taking mail money, a quest reward).
---------------------------------------------------------------------------
local base, baseUntil = nil, 0
local override, overrideUntil = nil, 0

local function OpenBase(kind) base, baseUntil = kind, math.huge end
local function CloseBase(kind, grace)
    if base == kind then baseUntil = GetTime() + (grace or 2) end
end
local function Override(kind, secs) override, overrideUntil = kind, GetTime() + (secs or 2) end

local function CurrentSource()
    local now = GetTime()
    if override and now <= overrideUntil then return override end
    if base and now <= baseUntil then return base end
    return "other"
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnMoney()
    local now = GetMoney()
    if not lastMoney then lastMoney = now return end
    local delta = now - lastMoney
    lastMoney = now
    if delta == 0 then return end

    local s = Session()
    local src = CurrentSource()
    if delta > 0 then
        s.income[src] = (s.income[src] or 0) + delta
        if FARM_SOURCES[src] then
            local zone = CurrentZoneName()
            ZoneEntry(s.zones, zone).gold = ZoneEntry(s.zones, zone).gold + delta
            ZoneEntry(db.zones, zone).gold = ZoneEntry(db.zones, zone).gold + delta
        end
    else
        s.expense[src] = (s.expense[src] or 0) - delta
    end
    if M.UpdateWidget then M.UpdateWidget() end
end

local function GuidKind(guid)
    local kind = guid and strsplit("-", guid)
    if kind == "GameObject" then return "chests" end
    if kind == "Item" then return "containers" end
    return "loot"
end

local function OnLootOpened()
    -- Where is the loot from? Use the first slot's source.
    local kind = "loot"
    if IsFishingLoot and IsFishingLoot() then
        kind = "loot"
    elseif GetLootSourceInfo and GetNumLootItems() > 0 then
        kind = GuidKind((GetLootSourceInfo(1)))
    end
    OpenBase(kind)

    -- Vendor value of item drops, per zone
    local value = 0
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        if link then
            local _, _, qty = GetLootSlotInfo(i)
            local price = select(11, C_Item.GetItemInfo(link))
            if price and price > 0 then value = value + price * (qty or 1) end
        end
    end
    if value > 0 then
        local s = Session()
        local zone = CurrentZoneName()
        s.lootValue = (s.lootValue or 0) + value
        ZoneEntry(s.zones, zone).value = ZoneEntry(s.zones, zone).value + value
        ZoneEntry(db.zones, zone).value = ZoneEntry(db.zones, zone).value + value
    end
end

-- One second of play: counts toward session and zone time unless AFK.
local function Tick()
    if UnitIsAFK("player") then return end
    local s = Session()
    s.active = s.active + 1
    local zone = CurrentZoneName()
    ZoneEntry(s.zones, zone).time = ZoneEntry(s.zones, zone).time + 1
    ZoneEntry(db.zones, zone).time = ZoneEntry(db.zones, zone).time + 1
end

local function HookMail()
    local function tagMail(index)
        local invoiceType = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
        Override((invoiceType == "seller") and "auction" or "mail", 3)
    end
    if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", tagMail) end
    if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", tagMail) end
    if RepairAllItems then hooksecurefunc("RepairAllItems", function() Override("repair", 3) end) end
end

-- WoW Forever reports the player's name as UNKNOWNOBJECT ("Unknown") early in
-- loading, sometimes still at PLAYER_LOGIN, which tagged sessions as
-- "Unknown-<ruleset>". Wait for the real name before setting playerKey.
local function IsUnknownName(n)
    return not n or n == "" or n == UNKNOWNOBJECT or n == "Unknown"
end

local function IsUnknownKey(k)
    return not k or IsUnknownName(k:match("^[^-]*"))
end

-- Sets playerKey once the name is known and fills in the current session if
-- it was started before then; returns true when done.
local function RegisterCharacter()
    if playerKey then return true end
    local name = UnitName("player")
    if IsUnknownName(name) then return false end
    playerKey = name .. "-" .. GetRealmName()
    playerClass = playerClass or select(2, UnitClass("player"))
    local s = charDB.session
    if s and IsUnknownKey(s.char) then
        s.char = playerKey
        s.class = s.class or playerClass
    end
    return true
end

function M:OnLogin()
    db, charDB = self.db, self.char
    playerClass = select(2, UnitClass("player"))
    RegisterCharacter()
    lastMoney = GetMoney()

    HookMail()
    if M.CreateWidget then M.CreateWidget() end

    local opens = {
        MERCHANT_SHOW = "vendor", MAIL_SHOW = "mail", TRADE_SHOW = "trade",
        AUCTION_HOUSE_SHOW = "auction", TAXIMAP_OPENED = "travel", QUEST_COMPLETE = "quests",
    }
    local closes = {
        MERCHANT_CLOSED = { "vendor", 2 }, MAIL_CLOSED = { "mail", 3 }, TRADE_CLOSED = { "trade", 4 },
        AUCTION_HOUSE_CLOSED = { "auction", 2 }, TAXIMAP_CLOSED = { "travel", 3 }, QUEST_FINISHED = { "quests", 2 },
        LOOT_CLOSED = false,   -- handled below (closes whichever loot kind is open)
    }

    local f = CreateFrame("Frame")
    for e in pairs(opens) do f:RegisterEvent(e) end
    for e in pairs(closes) do f:RegisterEvent(e) end
    for _, e in ipairs({ "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "LOOT_OPENED", "QUEST_TURNED_IN",
                         "ZONE_CHANGED_NEW_AREA" }) do
        f:RegisterEvent(e)
    end
    if not playerKey then f:RegisterUnitEvent("UNIT_NAME_UPDATE", "player") end
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_MONEY" then
            OnMoney()
        elseif opens[event] then
            OpenBase(opens[event])
        elseif event == "LOOT_CLOSED" then
            if base == "loot" or base == "chests" or base == "containers" then baseUntil = GetTime() + 1 end
        elseif closes[event] then
            CloseBase(closes[event][1], closes[event][2])
        elseif event == "LOOT_OPENED" then
            OnLootOpened()
        elseif event == "QUEST_TURNED_IN" then
            Override("quests", 2)
        elseif event == "UNIT_NAME_UPDATE" then
            if RegisterCharacter() then f:UnregisterEvent("UNIT_NAME_UPDATE") end
        elseif event == "PLAYER_ENTERING_WORLD" then
            if RegisterCharacter() then f:UnregisterEvent("UNIT_NAME_UPDATE") end
            local isInitialLogin = ...
            if isInitialLogin then
                Archive()        -- last time's session goes to history
                NewSession()
            end
            lastMoney = GetMoney()
            if M.UpdateWidget then M.UpdateWidget() end
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            if M.UpdateWidget then M.UpdateWidget() end
        end
    end)

    C_Timer.NewTicker(1, function()
        Tick()
        if M.UpdateWidget then M.UpdateWidget() end
    end)

    SLASH_CFGOLD1 = "/gold"
    SlashCmdList.CFGOLD = function(msg) M:slash(msg) end
end

function M:slash(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "reset" then
        M.ResetSession()
    elseif msg == "show" or msg == "hide" then
        db.widget.show = (msg == "show")
        M.UpdateWidget()
    else
        CF.Open("gold")
    end
end

function M.DB() return db end
