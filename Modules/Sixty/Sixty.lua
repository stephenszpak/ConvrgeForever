-- Sixty module: getting a fresh level 60 raid-ready.
--   * Checklist: attunement and dungeon keys (detected from bags, keyring,
--     gear and Stash's bank data), manual tick boxes, and a row per character.
--   * Wishlist: a target and a fallback per gear slot, with status (Equipped,
--     Owned + where, Fallback, Needed), tooltip tags, loot alerts and a
--     "Where to go next" summary grouped by source.
--
-- All data and strings live in Data.lua (CF.SIXTY).
--
-- Display-only: no secure actions. Everything that reads the game (bags,
-- gear, Stash data) runs out of combat; events in combat only queue a
-- refresh for PLAYER_REGEN_ENABLED. Alts and bank contents come from the
-- Stash module's saved data; this module never stores an inventory itself.

local _, CF = ...
local W = CF.W
local D = CF.SIXTY
local L = D.L
local C, GREEN, YELLOW, RED, GREY = W.C, W.GREEN, W.YELLOW, W.RED, W.GREY

local M = CF:NewModule("sixty", {
    title = L.title,
    description = L.description,
    defaults = {
        enabled = true,        -- /cf sixty on|off: pauses tags, alerts and refreshes
        tooltipTag = true,
        lootAlert = true,
        lootSound = true,
        showAlts = true,
        itemIDs = {},          -- [exact item name] = item ID learned in game
    },
    charDefaults = {
        -- list = { class = "SHAMAN", spec = "Enhancement" }   default list this character copied
        -- wishlist = { [slotKey] = { target = { name, id?, source, group? }, fallback = {...} } }
        manual = {},           -- [manual entry key] = true when ticked
        weeklyExpires = {},    -- [manual entry key] = time() the weekly tick clears
    },
})

local db, charDB
local playerClass

local function Print(msg) CF.Print(msg, "Sixty") end
local function Secret(v) return issecretvalue and issecretvalue(v) end

local SLOT_BY_KEY = {}
for _, s in ipairs(D.SLOTS) do
    SLOT_BY_KEY[s.key] = s
    SLOT_BY_KEY[s.label:lower():gsub("%s+", "")] = s
end

---------------------------------------------------------------------------
-- Item names and IDs
---------------------------------------------------------------------------
local requested = {}   -- item IDs we asked the client to load

local function NameOf(id)
    if not id then return nil end
    local n = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not n and C_Item.RequestLoadItemDataByID and not requested[id] then
        requested[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
    return n
end

-- wanted[name] = { { kind = "check"|"target"|"fallback", entry = checklistEntry, slot = slotDef }, ... }
-- dataID[name] = the ID written in Data.lua / the wishlist entry (unverified)
-- byID[id]     = name, for every ID we trust for a wanted name
local wanted, dataID, byID = {}, {}, {}

local function BuildIndex()
    wanted, dataID, byID = {}, {}, {}
    local function add(item, info)
        local name = item and item.name
        if not name or name == "" then return end
        wanted[name] = wanted[name] or {}
        table.insert(wanted[name], info)
        if item.id then dataID[name] = item.id; byID[item.id] = name end
        local learned = db.itemIDs[name]
        if learned then byID[learned] = name end
    end
    for _, e in ipairs(D.CHECKLIST) do add({ name = e.item, id = e.id }, { kind = "check", entry = e }) end
    for _, s in ipairs(D.SLOTS) do
        local w = charDB.wishlist[s.key]
        if w then
            add(w.target, { kind = "target", slot = s })
            add(w.fallback, { kind = "fallback", slot = s })
        end
    end
end

-- Saves the ID an item was seen with, when it differs from the one in the data.
local function Learn(id, name)
    if not id or not name or not wanted[name] or InCombatLockdown() then return end
    byID[id] = name
    if dataID[name] ~= id and db.itemIDs[name] ~= id then db.itemIDs[name] = id end
end

-- IDs that count as this item: the data ID (unless the client says it's a
-- different item) plus any learned one.
local function IDsFor(name, id)
    local t = {}
    if id then
        local n = NameOf(id)
        if n == nil or n == name then t[#t + 1] = id end
    end
    local learned = name and db.itemIDs[name]
    if learned and learned ~= id then t[#t + 1] = learned end
    return t
end

local function Resolved(name)
    if db.itemIDs[name] then return true end
    local id = dataID[name]
    return id and NameOf(id) == name
end

---------------------------------------------------------------------------
-- Current character: bags, keyring and gear, read live (nothing stored)
---------------------------------------------------------------------------
local live = { bags = {}, keyring = {}, worn = {} }

local function KeyringID() return Enum and Enum.BagIndex and Enum.BagIndex.Keyring end

local function BagList()
    local t = {}
    for i = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do t[#t + 1] = i end
    if KeyringID() then t[#t + 1] = KeyringID() end
    return t
end

local function SlotCount(bag)
    if bag == KeyringID() then return (GetKeyRingSize and GetKeyRingSize()) or 0 end
    return C_Container.GetContainerNumSlots(bag) or 0
end

local function ReadLive()
    live.bags, live.keyring, live.worn = {}, {}, {}
    for _, bag in ipairs(BagList()) do
        local target = (bag == KeyringID()) and live.keyring or live.bags
        for slot = 1, SlotCount(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id then
                target[id] = true
                local n = NameOf(id)
                if n and wanted[n] then Learn(id, n) end
            end
        end
    end
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then
            live.worn[slot] = id
            local n = NameOf(id)
            if n and wanted[n] then Learn(id, n) end
        end
    end
end

local function AnyIn(set, ids)
    if not set then return false end
    for _, id in ipairs(ids) do
        local v = set[id]
        if v and v ~= 0 then return true end
    end
    return false
end

local function WornIn(invSlots, ids)
    for _, slot in ipairs(invSlots) do
        local w = live.worn[slot]
        for _, id in ipairs(ids) do if w == id then return true end end
    end
    return false
end

local ALL_SLOTS = {}
for i = 1, 19 do ALL_SLOTS[i] = i end

---------------------------------------------------------------------------
-- Stash data (alts, bank, Warband bank)
---------------------------------------------------------------------------
local function Stash()
    local s = CF.modules.stash
    if s and s.running and s.Current and s.ForEachChar then return s end
end

-- Names we still have no trustworthy ID for get matched against every item
-- Stash has seen. Unloaded names are requested a few at a time.
local function LearnFromStash(S)
    local unresolved, any = {}, false
    for name in pairs(wanted) do
        if not Resolved(name) then unresolved[name], any = true, true end
    end
    if not any then return end
    local seen, budget = {}, 200
    local function check(t)
        if not t then return end
        for id in pairs(t) do
            if not seen[id] then
                seen[id] = true
                local n = C_Item.GetItemNameByID(id)
                if n then
                    if unresolved[n] then Learn(id, n) end
                elseif budget > 0 and not requested[id] and C_Item.RequestLoadItemDataByID then
                    budget = budget - 1
                    requested[id] = true
                    C_Item.RequestLoadItemDataByID(id)
                end
            end
        end
    end
    S.ForEachChar(function(_, _, _, d) check(d.bags); check(d.bank); check(d.equipped) end)
    check(S.Warband())
end

-- Everywhere outside this character's bags/gear that holds one of ids.
local function StashLocations(S, ids, out)
    local cur = S.Current()
    if cur and AnyIn(cur.bank, ids) then out[#out + 1] = L.locBank end
    if AnyIn(S.Warband(), ids) then out[#out + 1] = L.locWarband end
    local alts = {}
    S.ForEachChar(function(name, realm, faction, d)
        if d == cur then return end
        local where = (AnyIn(d.equipped, ids) and L.locWorn) or (AnyIn(d.bags, ids) and L.locBags)
            or (AnyIn(d.bank, ids) and L.locBank)
        if where then
            alts[#alts + 1] = { sort = realm .. "\1" .. name,
                text = L.locAlt:format(S.CharLabel(name, realm, faction, d.class), where) }
        end
    end)
    table.sort(alts, function(a, b) return a.sort < b.sort end)
    for _, a in ipairs(alts) do out[#out + 1] = a.text end
end

---------------------------------------------------------------------------
-- Weekly reset for weekly tick boxes
---------------------------------------------------------------------------
local function WeeklyResetIn()
    local f = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
    local s = f and f()
    if type(s) == "number" and not Secret(s) and s > 0 then return s end
end

local function ExpireWeekly()
    local now = time()
    for key, at in pairs(charDB.weeklyExpires) do
        if now >= at then
            charDB.manual[key] = nil
            charDB.weeklyExpires[key] = nil
        end
    end
end

local function SetManual(e, v)
    charDB.manual[e.key] = v and true or nil
    charDB.weeklyExpires[e.key] = nil
    if v and e.weekly then
        local s = WeeklyResetIn()
        if s then charDB.weeklyExpires[e.key] = time() + s end
    end
end

---------------------------------------------------------------------------
-- Wishlist lists
---------------------------------------------------------------------------
local function ListDef(class, spec)
    return D.WISHLISTS[class] and D.WISHLISTS[class][spec]
end

local function DefaultListFor(class)
    local byClass = D.WISHLISTS[class]
    if byClass then
        local specs = {}
        for k in pairs(byClass) do specs[#specs + 1] = k end
        table.sort(specs)
        return class, specs[1]
    end
    return D.DEFAULT_LIST.class, D.DEFAULT_LIST.spec
end

local function CurrentList()
    local l = charDB.list
    return l and ListDef(l.class, l.spec)
end

local function ResetWishlist()
    charDB.wishlist = CF.DeepCopy(CurrentList().slots)
    BuildIndex()
end

local function GroupOf(item)
    if not item then return L.unknownSource end
    if item.group and item.group ~= "" then return item.group end
    local head = strtrim((item.source or ""):match("^([^,]*)") or "")
    local prof = head:match("^(.-)%s+[Cc]raft$")
    if prof then return prof .. " " .. L.craft end
    head = strtrim((head:gsub("%s+[Qq]uest$", "")))
    return head ~= "" and head or L.unknownSource
end

---------------------------------------------------------------------------
-- State (computed out of combat only)
---------------------------------------------------------------------------
local state = { checks = {}, alts = {}, slots = {}, where = {}, at = nil, stash = false }
M.state = state   -- read-only, for /dump ConvrgeForever.modules.sixty.state
local pending = false

local function Compute()
    if InCombatLockdown() then pending = true return false end
    pending = false
    ExpireWeekly()
    ReadLive()
    local S = Stash()
    if S then LearnFromStash(S) end
    state.stash = S and true or false
    local cur = S and S.Current()

    -- Checklist (this character)
    local checkIDs = {}
    for i, e in ipairs(D.CHECKLIST) do
        local ids = IDsFor(e.item, e.id)
        checkIDs[i] = ids
        local where
        if WornIn(ALL_SLOTS, ids) then where = L.locWorn
        elseif AnyIn(live.keyring, ids) then where = L.locKeyring
        elseif AnyIn(live.bags, ids) then where = L.locBags
        elseif cur and AnyIn(cur.bank, ids) then where = L.locBank end
        state.checks[i] = { done = where ~= nil, where = where }
    end

    -- Per-character overview
    state.alts = {}
    if S then
        S.ForEachChar(function(name, realm, faction, d)
            local isMe = (d == cur)
            local marks = {}
            for i in ipairs(D.CHECKLIST) do
                if isMe then
                    marks[i] = state.checks[i].done
                else
                    local ids = checkIDs[i]
                    marks[i] = AnyIn(d.bags, ids) or AnyIn(d.bank, ids) or AnyIn(d.equipped, ids)
                end
            end
            state.alts[#state.alts + 1] = { label = S.CharLabel(name, realm, faction, d.class), marks = marks,
                isMe = isMe, bankScanned = d.bankScanned, sort = (isMe and "\0" or "") .. realm .. "\1" .. name }
        end)
        table.sort(state.alts, function(a, b) return a.sort < b.sort end)
    end

    -- Wishlist
    local groups = {}
    for i, s in ipairs(D.SLOTS) do
        local w = charDB.wishlist[s.key] or {}
        local t, f = w.target, w.fallback
        local tids = t and IDsFor(t.name, t.id) or {}
        local fids = f and IDsFor(f.name, f.id) or {}
        local st
        if t and WornIn(s.inv, tids) then
            st = { kind = "equipped" }
        else
            local locs = {}
            if t and AnyIn(live.bags, tids) then locs[#locs + 1] = L.locBags end
            if t and S then StashLocations(S, tids, locs) end
            if #locs > 0 then
                st = { kind = "owned", locs = locs }
            elseif f and WornIn(s.inv, fids) then
                st = { kind = "fallback" }
            else
                st = { kind = "needed" }
                local g = GroupOf(t)
                groups[g] = groups[g] or { name = g, slots = {} }
                table.insert(groups[g].slots, s.label)
            end
        end
        state.slots[i] = st
    end
    state.where = {}
    for _, g in pairs(groups) do state.where[#state.where + 1] = g end
    table.sort(state.where, function(a, b)
        if #a.slots ~= #b.slots then return #a.slots > #b.slots end
        return a.name < b.name
    end)

    state.at = GetTime()
    return true
end

---------------------------------------------------------------------------
-- Refresh scheduling: at most one recompute per half second, none in combat
---------------------------------------------------------------------------
local page
local timerQueued = false

local function Redraw()
    if page and page:IsVisible() then CF.RefreshCurrent() end
end

local function RefreshNow()
    timerQueued = false
    if not db.enabled then return end
    if Compute() then Redraw() end
end

local function QueueRefresh()
    if InCombatLockdown() then pending = true return end
    if timerQueued then return end
    timerQueued = true
    C_Timer.After(0.5, RefreshNow)
end

---------------------------------------------------------------------------
-- Tooltip tag
---------------------------------------------------------------------------
local function TagTooltip(tt, id)
    if not db.enabled or not db.tooltipTag or not id then return end
    local name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or byID[id]
    local list = name and wanted[name]
    if not list then return end
    local added = false
    for _, info in ipairs(list) do
        if info.kind == "target" or info.kind == "fallback" then
            tt:AddLine((info.kind == "target" and L.tagTarget or L.tagFallback):format(info.slot.label), 1, 1, 1)
            added = true
        end
    end
    if added then
        Learn(id, name)
        tt:Show()
    end
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            local id = data and data.id
            if id == nil or Secret(id) then return end
            TagTooltip(tooltip, id)
        end)
        return
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HasScript and tt:HasScript("OnTooltipSetItem") then
            tt:HookScript("OnTooltipSetItem", function(self)
                local _, link = self:GetItem()
                if link and not Secret(link) then TagTooltip(self, tonumber(link:match("item:(%d+)"))) end
            end)
        end
    end
end

---------------------------------------------------------------------------
-- Loot alert: only item links are read. Unreadable (secret) text is skipped;
-- text that arrives in combat is held until combat ends.
---------------------------------------------------------------------------
local lootQueue, lastAlert = {}, {}

local function AlertLink(id, name)
    local n = name or (id and byID[id])
    local list = n and wanted[n]
    if not list then return end
    local parts = {}
    for _, info in ipairs(list) do
        if info.kind == "target" or info.kind == "fallback" then
            parts[#parts + 1] = info.slot.label .. ", " .. (info.kind == "target" and L.kindTarget or L.kindFallback)
        end
    end
    if #parts == 0 then return end
    if lastAlert[n] and GetTime() - lastAlert[n] < 60 then return end   -- roll, need and won lines repeat it
    lastAlert[n] = GetTime()
    Learn(id, n)
    local link = id and select(2, C_Item.GetItemInfo(id)) or ("[" .. n .. "]")
    Print(L.lootAlert:format(link, table.concat(parts, "; ")))
    if db.lootSound and PlaySound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end
end

local function HandleLootText(text)
    if type(text) ~= "string" or Secret(text) then return end
    local found = {}
    local ok = pcall(function()
        for id, name in text:gmatch("|Hitem:(%d+)[^|]*|h%[(.-)%]|h") do
            found[#found + 1] = { tonumber(id), strtrim((name:gsub("|A.-|a", ""))) }
        end
    end)
    if not ok then return end
    for _, f in ipairs(found) do AlertLink(f[1], f[2]) end
end

local function OnLootText(text)
    if not db.enabled or not db.lootAlert then return end
    if type(text) ~= "string" or Secret(text) then return end
    if InCombatLockdown() then
        if #lootQueue < 20 then lootQueue[#lootQueue + 1] = text end
        return
    end
    HandleLootText(text)
end

local function FlushLootQueue()
    local q = lootQueue
    lootQueue = {}
    for _, text in ipairs(q) do HandleLootText(text) end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
function M:OnLogin()
    db, charDB = self.db, self.char
    playerClass = select(2, UnitClass("player"))

    if not CurrentList() then
        local class, spec = DefaultListFor(playerClass)
        charDB.list = { class = class, spec = spec }
        charDB.wishlist = nil
    end
    if type(charDB.wishlist) ~= "table" then ResetWishlist() else BuildIndex() end

    HookTooltips()

    SLASH_CFSIXTY1 = "/sixty"
    SlashCmdList.CFSIXTY = function(msg) M:slash(msg) end

    local f = CreateFrame("Frame")
    local function Try(ev)
        if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(ev) then
            pcall(f.RegisterEvent, f, ev)
        end
    end
    for _, ev in ipairs({
        "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_REGEN_ENABLED", "BANKFRAME_CLOSED", "GET_ITEM_INFO_RECEIVED",
        "CHAT_MSG_LOOT", "START_LOOT_ROLL",
    }) do Try(ev) end

    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "CHAT_MSG_LOOT" then
            OnLootText(arg1)
        elseif event == "START_LOOT_ROLL" then
            if db.enabled and db.lootAlert and GetLootRollItemLink and not Secret(arg1) then
                local ok, link = pcall(GetLootRollItemLink, arg1)
                if ok then OnLootText(link) end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if db.enabled then FlushLootQueue() end
            if pending then QueueRefresh() end
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            -- Only names we asked for matter (Stash items being matched by name).
            if arg1 and not Secret(arg1) and requested[arg1] then QueueRefresh() end
        else
            QueueRefresh()
        end
    end)
    QueueRefresh()
end

---------------------------------------------------------------------------
-- Slash: /cf sixty ...  (and /sixty)
---------------------------------------------------------------------------
local function SetFromLink(kind, slotArg, rest)
    local slot = slotArg and SLOT_BY_KEY[slotArg:lower()]
    if not slot then Print(L.badSlot:format(slotArg or "")) return end
    local id = tonumber(rest:match("|Hitem:(%d+)"))
    local name = rest:match("|h%[(.-)%]|h")
    if not (id and name) then Print(L.needLink) return end
    name = strtrim((name:gsub("|A.-|a", "")))
    local source = rest:gsub("|c[^|]*", ""):gsub("|H.-|h.-|h", ""):gsub("|r", "")
    source = strtrim(source)

    local w = charDB.wishlist[slot.key] or {}
    charDB.wishlist[slot.key] = w
    local old = w[kind]
    if source == "" then source = (old and old.name == name and old.source) or L.unknownSource end
    w[kind] = { name = name, id = id, source = source }
    BuildIndex()
    Print(L.setDone:format(slot.label, kind == "target" and L.kindTarget or L.kindFallback,
        select(2, C_Item.GetItemInfo(id)) or ("[" .. name .. "]")))
    QueueRefresh()
end

function M:slash(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        CF.Open("sixty")
    elseif cmd == "want" or cmd == "fallback" then
        local slotArg, linkPart = rest:match("^(%S+)%s*(.-)$")
        SetFromLink(cmd == "want" and "target" or "fallback", slotArg, linkPart or "")
    elseif cmd == "reset" then
        ResetWishlist()
        Print(L.resetDone:format(CurrentList().name))
        QueueRefresh()
    elseif cmd == "list" then
        local class, spec = rest:match("^(%S+)%s+(.+)$")
        if class then
            class = class:upper()
            local def = ListDef(class, strtrim(spec))
            if not def then Print(L.listUnknown:format(class, spec)) return end
            charDB.list = { class = class, spec = strtrim(spec) }
            ResetWishlist()
            Print(L.listSet:format(def.name))
            QueueRefresh()
        else
            Print(L.listCurrent:format(CurrentList().name))
            for c, specs in pairs(D.WISHLISTS) do
                for s in pairs(specs) do print(L.listRow:format(c, s)) end
            end
        end
    elseif cmd == "on" or cmd == "off" then
        db.enabled = (cmd == "on")
        Print(L.onOff:format(db.enabled and L.on or L.off))
        if db.enabled then QueueRefresh() end
        CF.RefreshCurrent()
    else
        for i, line in ipairs(L.help) do
            if i == 1 then Print(line) else print(line) end
        end
    end
end

---------------------------------------------------------------------------
-- Page: one scrolling page with Checklist, Wishlist and Where to go next
---------------------------------------------------------------------------
local ROW_H = 18
local WISH_COLS = { { 70 }, { 200 }, { 240 } }
local ALT_NAME_W, ALT_MARK_W = 170, 46

local function ItemText(item)
    if not item then return C(GREY, "-") end
    local ids = IDsFor(item.name, item.id)
    local id = ids[1]
    local quality = id and select(3, C_Item.GetItemInfo(id))
    if quality and C_Item.GetItemQualityColor then
        local _, _, _, hex = C_Item.GetItemQualityColor(quality)
        if hex then return "|c" .. hex .. item.name .. "|r" end
    end
    return item.name
end

local function ItemTipLines(tt, label, item)
    if not item then return end
    tt:AddDoubleLine(label, item.name, 0.55, 0.55, 0.55, 1, 1, 1)
    tt:AddLine(item.source or L.unknownSource, 0.7, 0.7, 0.7)
    local id = IDsFor(item.name, item.id)[1]
    if id then tt:AddLine(L.tipID:format(id), 0.45, 0.45, 0.45) else tt:AddLine(L.tipNoID, 0.45, 0.45, 0.45, true) end
end

local function BuildPage(p)
    page = p
    local sf = CreateFrame("ScrollFrame", nil, p)
    sf:SetPoint("TOPLEFT")
    sf:SetPoint("BOTTOMRIGHT", -10, 0)
    local c = CreateFrame("Frame", nil, sf)
    c:SetSize(math.max(sf:GetWidth(), 520), 10)
    sf:SetScrollChild(c)
    sf:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then c:SetWidth(w) end end)
    p.sf, p.c = sf, c

    local track = p:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT")
    track:SetPoint("BOTTOMRIGHT")
    track:SetWidth(3)
    track:SetColorTexture(1, 1, 1, 0.05)
    local thumb = p:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(1, 1, 1, 0.45)
    p.UpdateThumb = function()
        local viewH, contentH = sf:GetHeight(), c:GetHeight()
        local maxOff = math.max(0, contentH - viewH)
        if maxOff <= 0 or viewH <= 0 then
            thumb:Hide(); track:Hide()
            sf:SetVerticalScroll(0)
            return
        end
        if sf:GetVerticalScroll() > maxOff then sf:SetVerticalScroll(maxOff) end
        local th = math.max(16, viewH * viewH / contentH)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", 0, -(viewH - th) * sf:GetVerticalScroll() / maxOff)
        thumb:Show(); track:Show()
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxOff = math.max(0, c:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxOff, self:GetVerticalScroll() - delta * 40)))
        p.UpdateThumb()
    end)

    local function changed() CF.RefreshCurrent() end
    p.note = W.Text(c, 12, 1, 0.8, 0.2)

    -- Options (no header: they sit above the three sections)
    p.opts = {
        W.Check(c, L.optTooltip, function() return db.tooltipTag end, function(v) db.tooltipTag = v end, nil, changed),
        W.Check(c, L.optLoot, function() return db.lootAlert end, function(v) db.lootAlert = v end, nil, changed),
        W.Check(c, L.optSound, function() return db.lootSound end, function(v) db.lootSound = v end, nil, changed),
        W.Check(c, L.optAlts, function() return db.showAlts end, function(v) db.showAlts = v end, nil, changed),
    }

    -- Checklist
    p.hCheck = W.Header(c, L.headChecklist)
    p.checkRows = {}
    for i in ipairs(D.CHECKLIST) do
        local r = {}
        r.status = W.Text(c, 12)
        r.status:SetWidth(56)
        r.label = W.Text(c, 12)
        r.label:SetWidth(150)
        r.detail = W.Text(c, 11, 0.6, 0.6, 0.6)
        r.detail:SetWordWrap(true)
        p.checkRows[i] = r
    end
    local weeklySuffix = WeeklyResetIn() and L.weeklyAuto or L.weeklyManual
    p.manual = {}
    for i, e in ipairs(D.MANUAL) do
        p.manual[i] = W.Check(c, e.label .. (e.weekly and C(GREY, weeklySuffix) or ""),
            function() return charDB.manual[e.key] and true or false end,
            function(v) SetManual(e, v) end, nil, changed)
    end

    p.hAlts = W.Text(c, 12, 0.55, 0.55, 0.55)
    p.hAlts:SetText(L.headAlts)
    p.altCols = {}
    for i, e in ipairs(D.CHECKLIST) do
        local t = W.Text(c, 11, 0.55, 0.55, 0.55)
        t:SetWidth(ALT_MARK_W)
        t:SetText(e.short)
        p.altCols[i] = t
    end
    p.altMsg = W.Text(c, 11, 0.55, 0.55, 0.55)
    p.altRows = {}

    -- Wishlist
    p.hWish = W.Header(c, L.headWishlist)
    p.wishSub = W.Text(c, 11, 0.55, 0.55, 0.55)
    p.wishHdr = W.ListHeader(c, WISH_COLS, { L.colSlot, L.colItem, L.colStatus })
    p.wishRows = {}
    for i, s in ipairs(D.SLOTS) do
        local row = CreateFrame("Button", nil, c)
        row:SetHeight(ROW_H)
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        row.cols = {}
        local x = 8
        for k, col in ipairs(WISH_COLS) do
            local fs = W.Text(row, 12)
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(col[1])
            row.cols[k] = fs
            x = x + col[1] + 6
        end
        row.cols[1]:SetText(s.label)
        row:SetScript("OnEnter", function(self)
            local w = charDB.wishlist[s.key] or {}
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(s.label, 1, 1, 1)
            ItemTipLines(GameTooltip, L.tipTarget, w.target)
            ItemTipLines(GameTooltip, L.tipFallback, w.fallback)
            GameTooltip:AddLine(L.tipEdit, 0.45, 0.45, 0.45, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        p.wishRows[i] = row
    end

    -- Where to go next
    p.hWhere = W.Header(c, L.headWhere)
    p.whereRows = {}
end

local function Place(region, parent, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    region:Show()
end

local function AltRow(p, i)
    local r = p.altRows[i]
    if r then return r end
    p.newWidgets = true
    r = { name = W.Text(p.c, 12), marks = {}, note = W.Text(p.c, 10, 0.45, 0.45, 0.45) }
    r.name:SetWidth(ALT_NAME_W)
    for k in ipairs(D.CHECKLIST) do
        r.marks[k] = W.Text(p.c, 11)
        r.marks[k]:SetWidth(ALT_MARK_W)
    end
    p.altRows[i] = r
    return r
end

local function WhereRow(p, i)
    local r = p.whereRows[i]
    if r then return r end
    p.newWidgets = true
    r = W.Text(p.c, 12)
    p.whereRows[i] = r
    return r
end

local function StatusCell(st, w)
    local k = st and st.kind
    if k == "equipped" then return C(GREEN, L.statusEquipped), GREEN end
    if k == "owned" then
        local s = st.locs[1]
        if #st.locs > 1 then s = s .. L.more:format(#st.locs - 1) end
        return C(YELLOW, L.statusOwned:format(s)), YELLOW
    end
    if k == "fallback" then
        return C(YELLOW, L.statusFallback:format(w.fallback and w.fallback.name or "?")), YELLOW
    end
    if k == "needed" then
        return C(RED, L.statusNeeded:format(w.target and w.target.source or L.unknownSource)), RED
    end
    return C(GREY, "-"), GREY
end

local function RefreshPage(p)
    if db.enabled and not InCombatLockdown() and (not state.at or GetTime() - state.at > 0.25) then Compute() end
    local c = p.c
    local width = c:GetWidth()
    local y = 0

    local note
    if not db.enabled then note = L.paused elseif InCombatLockdown() then note = L.inCombat end
    if note then
        p.note:SetText(note)
        Place(p.note, c, 0, y)
        y = y + 20
    else
        p.note:Hide()
    end

    for i, w in ipairs(p.opts) do
        w.Refresh()
        Place(w, c, ((i - 1) % 2) * 270, y + math.floor((i - 1) / 2) * 22)
    end
    y = y + 52

    -- Checklist
    Place(p.hCheck, c, 0, y)
    y = y + 22
    for i, e in ipairs(D.CHECKLIST) do
        local r, st = p.checkRows[i], state.checks[i]
        local done = st and st.done
        r.status:SetText(st and (done and C(GREEN, L.done) or C(RED, L.missing)) or C(GREY, "-"))
        r.label:SetText(e.label)
        r.detail:SetWidth(math.max(120, width - 220))
        if done then
            r.detail:SetText(L.foundIn:format(st.where))
        else
            r.detail:SetText(e.hint or L.noHint)
        end
        Place(r.status, c, 0, y + 1)
        Place(r.label, c, 60, y + 1)
        Place(r.detail, c, 216, y + 2)
        y = y + math.max(ROW_H, math.ceil(r.detail:GetStringHeight() or 0) + 6)
    end
    y = y + 4
    for _, w in ipairs(p.manual) do
        w.Refresh()
        Place(w, c, 0, y)
        y = y + 22
    end

    -- Characters
    for _, r in ipairs(p.altRows) do
        r.name:Hide(); r.note:Hide()
        for _, m in ipairs(r.marks) do m:Hide() end
    end
    p.altMsg:Hide()
    if db.showAlts then
        y = y + 8
        Place(p.hAlts, c, 0, y)
        for i, t in ipairs(p.altCols) do Place(t, c, ALT_NAME_W + (i - 1) * ALT_MARK_W, y + 1) end
        y = y + 20
        if not state.stash then
            p.altMsg:SetText(L.altsNeedStash)
            Place(p.altMsg, c, 0, y)
            y = y + 18
        else
            if #state.alts <= 1 then
                p.altMsg:SetText(L.altsNone)
            end
            for i, a in ipairs(state.alts) do
                local r = AltRow(p, i)
                r.name:SetText(a.label)
                Place(r.name, c, 0, y)
                for k, e in ipairs(D.CHECKLIST) do
                    r.marks[k]:SetText(a.marks[k] and C(GREEN, e.short) or C(GREY, e.short))
                    Place(r.marks[k], c, ALT_NAME_W + (k - 1) * ALT_MARK_W, y + 1)
                end
                local n = a.isMe and L.you or (not a.bankScanned and L.altBankUnknown) or ""
                r.note:SetText(n)
                Place(r.note, c, ALT_NAME_W + #D.CHECKLIST * ALT_MARK_W, y + 2)
                y = y + ROW_H
            end
            if #state.alts <= 1 then
                Place(p.altMsg, c, 0, y)
                y = y + 18
            end
        end
    else
        p.hAlts:Hide()
        for _, t in ipairs(p.altCols) do t:Hide() end
    end

    -- Wishlist
    y = y + 12
    Place(p.hWish, c, 0, y)
    local list = CurrentList()
    local listName = list and list.name or "?"
    local own = charDB.list and charDB.list.class == playerClass
    p.wishSub:SetText((own and L.wishlistFor or L.wishlistOther):format(listName))
    p.wishSub:ClearAllPoints()
    p.wishSub:SetPoint("LEFT", p.hWish, "RIGHT", 10, 0)
    y = y + 22
    Place(p.wishHdr, c, 0, y)
    p.wishHdr:SetPoint("RIGHT", c, "RIGHT")
    y = y + 20
    for i, s in ipairs(D.SLOTS) do
        local row = p.wishRows[i]
        local w = charDB.wishlist[s.key] or {}
        local st = state.slots[i]
        row.cols[2]:SetText(ItemText(w.target))
        row.cols[3]:SetText((StatusCell(st, w)))
        Place(row, c, 0, y)
        row:SetPoint("RIGHT", c, "RIGHT")
        y = y + ROW_H
    end

    -- Where to go next
    y = y + 12
    Place(p.hWhere, c, 0, y)
    y = y + 22
    for _, r in ipairs(p.whereRows) do r:Hide() end
    if #state.where == 0 then
        local r = WhereRow(p, 1)
        r:SetText(C(GREEN, state.at and L.whereDone or "-"))
        Place(r, c, 0, y)
        y = y + ROW_H
    else
        for i, g in ipairs(state.where) do
            local r = WhereRow(p, i)
            r:SetWidth(math.max(200, width - 10))
            r:SetText(L.whereRow:format(C(RED, g.name), #g.slots, table.concat(g.slots, ", ")))
            Place(r, c, 0, y)
            y = y + ROW_H
        end
    end

    c:SetHeight(y + 10)
    p.UpdateThumb()
    if p.newWidgets then
        p.newWidgets = false
        W.ApplySkin()   -- skins rows created since the page was built (idempotent)
    end
end

M.pages = {
    { key = "sixty", label = L.title, build = BuildPage, refresh = RefreshPage },
}
