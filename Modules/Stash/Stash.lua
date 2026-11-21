-- Stash module: item counts across your characters' bags, equipped gear,
-- character bank and Warband bank, shown in item tooltips. Covers every
-- saved character, or only the current ruleset + faction if allCharacters
-- is off. (Formerly the StashCount addon.)
--
-- WoW Forever has rulesets (PvP, Normal, RP...) instead of realms;
-- GetRealmName() is what tells them apart, so "realm" below means ruleset.

local _, CF = ...
local W = CF.W
local C, GREY, GREEN, RED = W.C, W.GREY, W.GREEN, W.RED

local M = CF:NewModule("stash", {
    title = "Stash",
    description = "Counts of every item across your characters' bags, banks and Warband bank, in item tooltips.",
    legacyAddon = "StashCount",
    defaults = {
        realms = {},           -- [realm][faction][name] = { class, bags, bank, equipped, bankScanned, lastSeen }
        warband = {},          -- [itemID] = count
        tooltip = true,
        includeEquipped = true,
        showWarband = true,
        allCharacters = true,
    },
})

local playerName, playerRealm, playerFaction, playerClass
local charData
local bankOpen = false

local function Print(msg) CF.Print(msg, "Stash") end

---------------------------------------------------------------------------
-- Migration from StashCount
---------------------------------------------------------------------------
function M:Migrate()
    local old = _G.StashCountDB
    if self.db.importedLegacy or type(old) ~= "table" or not old.realms then return end
    self.db.realms = CF.DeepCopy(old.realms)
    self.db.warband = CF.DeepCopy(old.warband or {})
    self.db.importedLegacy = true
    Print("imported your StashCount data.")
end

---------------------------------------------------------------------------
-- Containers
---------------------------------------------------------------------------
-- WoW Forever has a keyring, and its character bank is a set of tabs
-- (CharacterBankTab_N) rather than the old bank + bank bags.
local BAGS, BANK, WARBAND = {}, {}, {}
local IN_BAGS, IN_BANK, IN_WARBAND = {}, {}, {}
local bankIsTabs = false

local function BuildContainerLists()
    local E = Enum and Enum.BagIndex
    if not E then
        for i = 0, 4 do BAGS[#BAGS + 1] = i end
        BANK[#BANK + 1] = -1
        for i = 5, 11 do BANK[#BANK + 1] = i end
    else
        local tabs, legacy = {}, {}
        for key, id in pairs(E) do
            if key == "Backpack" or key:match("^Bag_%d+$") or key == "ReagentBag" or key == "Keyring" then
                BAGS[#BAGS + 1] = id
            elseif key:match("^CharacterBankTab_%d+$") then
                tabs[#tabs + 1] = id
            elseif key == "Bank" or key:match("^BankBag_%d+$") or key == "Reagentbank" then
                legacy[#legacy + 1] = id
            elseif key:match("^AccountBankTab_%d+$") then
                WARBAND[#WARBAND + 1] = id
            end
        end
        -- Bank tabs replace the old bank; don't read both.
        bankIsTabs = #tabs > 0
        for _, id in ipairs(bankIsTabs and tabs or legacy) do BANK[#BANK + 1] = id end
    end
    table.sort(BAGS); table.sort(BANK); table.sort(WARBAND)
    for _, id in ipairs(BAGS) do IN_BAGS[id] = true end
    for _, id in ipairs(BANK) do IN_BANK[id] = true end
    for _, id in ipairs(WARBAND) do IN_WARBAND[id] = true end
end

local function NumSlots(bag)
    if Enum.BagIndex and bag == Enum.BagIndex.Keyring and GetKeyRingSize then
        return GetKeyRingSize() or 0
    end
    return C_Container.GetContainerNumSlots(bag) or 0
end

-- Whether the Warband bank can be read right now. It can be locked, or not
-- exist at all (WoW Forever), even while a banker is open. The character
-- bank is always readable while open; ScanContainer copes with empty tabs.
local function CanSeeBank(kind)
    if kind == "Character" then return true end
    local T = Enum.BankType
    if not (C_Bank and T and T.Account) then return false end
    if C_Bank.FetchBankLockedReason then return C_Bank.FetchBankLockedReason(T.Account) == nil end
    if C_Bank.CanViewBank then return C_Bank.CanViewBank(T.Account) and true or false end
    return true
end

-- Counts one container. Returns nil if any item in it hasn't loaded yet
-- (we keep the old counts and try again instead of dropping the item).
local waitingForItems = false
local function ScanContainer(bag, force)
    local counts = {}
    local complete = true
    for slot = 1, NumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then
            counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
        else
            local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
            if loc and C_Item.DoesItemExist(loc) then
                local id = C_Item.GetItemID(loc)
                local n = C_Item.GetStackCount and C_Item.GetStackCount(loc)
                if id and n then
                    counts[id] = (counts[id] or 0) + n
                else
                    complete = false
                    if id and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
                end
            end
        end
    end
    if not complete and not force then
        waitingForItems = true
        return nil
    end
    return counts
end

local function Merge(parts, list)
    local total = {}
    for _, bag in ipairs(list) do
        local c = parts[bag]
        if c then for id, n in pairs(c) do total[id] = (total[id] or 0) + n end end
    end
    return total
end

-- Everything worn, plus the ammo slot (0) on WoW Forever. Bags aren't counted.
local function ScanEquipped()
    local counts = {}
    local last = C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(1)
    last = (last or 20) - 1
    for slot = 0, last do
        local id = GetInventoryItemID("player", slot)
        if id then
            local n = slot == 0 and GetInventoryItemCount("player", slot) or 1
            counts[id] = (counts[id] or 0) + math.max(n or 1, 1)
        end
    end
    return counts
end

---------------------------------------------------------------------------
-- Scanning: events mark containers as dirty, one pass on the next frame
-- rescans just those. Bank containers only count while the bank is open
-- (or right after crafting, which can use reagents from the bank).
---------------------------------------------------------------------------
local pending = { bags = {}, bank = {}, warband = {}, equipped = false }
local scanner = CreateFrame("Frame")
local lastCraft = 0
local retries, MAX_RETRIES = 0, 10
local CRAFT_WINDOW = 2

-- Bank tabs stay readable after a craft that used bank reagents; the old
-- bank can only be read while it's open.
local function BankReadable()
    return bankOpen or (bankIsTabs and GetTime() - lastCraft < CRAFT_WINDOW)
end

local function Flush()
    scanner:SetScript("OnUpdate", nil)
    if not charData then return end   -- not registered yet; pending stays queued
    waitingForItems = false
    local force = retries >= MAX_RETRIES
    local retry = { bags = {}, bank = {}, warband = {} }

    if next(pending.bags) then
        charData.bagParts = charData.bagParts or {}
        for bag in pairs(pending.bags) do
            local c = ScanContainer(bag, force)
            if c then charData.bagParts[bag] = c else retry.bags[bag] = true end
        end
        -- Until every bag has been read once, keep the counts we already had.
        local all = true
        for _, bag in ipairs(BAGS) do if not charData.bagParts[bag] then all = false end end
        if all then charData.bags = Merge(charData.bagParts, BAGS) end
    end

    if next(pending.bank) then
        local first = not charData.bankParts
        local parts = charData.bankParts or {}
        local seen = false
        for bag in pairs(pending.bank) do
            if NumSlots(bag) > 0 then
                local c = ScanContainer(bag, force)
                if c then parts[bag] = c; seen = true else retry.bank[bag] = true end
            end
        end
        -- Don't replace a bank recorded the old way until we've read it properly.
        if seen and (not first or bankOpen) then
            charData.bankParts = parts
            charData.bank = Merge(parts, BANK)
            charData.bankScanned = true
        end
    end

    if next(pending.warband) then
        local parts = M.db.warbandParts or {}
        local seen = false
        for bag in pairs(pending.warband) do
            if NumSlots(bag) > 0 then
                local c = ScanContainer(bag, force)
                if c then parts[bag] = c; seen = true else retry.warband[bag] = true end
            end
        end
        if seen and (M.db.warbandParts or bankOpen) then
            M.db.warbandParts = parts
            M.db.warband = Merge(parts, WARBAND)
        end
    end

    if pending.equipped then charData.equipped = ScanEquipped() end
    charData.lastSeen = time()

    pending.bags, pending.bank, pending.warband, pending.equipped = {}, {}, {}, false
    if not waitingForItems then
        retries = 0
    else
        -- Some items hadn't loaded; look again shortly (after a few tries,
        -- take what we have).
        retries = retries + 1
        C_Timer.After(0.5, function()
            for k in pairs(retry.bags) do pending.bags[k] = true end
            if bankOpen then
                for k in pairs(retry.bank) do pending.bank[k] = true end
                for k in pairs(retry.warband) do pending.warband[k] = true end
            end
            scanner:SetScript("OnUpdate", Flush)
        end)
    end
end

local function Queue() scanner:SetScript("OnUpdate", Flush) end

local function QueueAll(list, set)
    for _, bag in ipairs(list) do set[bag] = true end
end

local function QueueBank()
    if not BankReadable() then return end
    if CanSeeBank("Character") then QueueAll(BANK, pending.bank) end
    if CanSeeBank("Account") then QueueAll(WARBAND, pending.warband) end
    Queue()
end

local function OnBankOpened()
    bankOpen = true
    QueueBank()
    -- Tabs can arrive a moment after the bank opens.
    C_Timer.After(1, QueueBank)
end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------
local function ClassColored(name, class)
    local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
    return c and c:WrapTextInColorCode(name) or name
end

local FACTION_TAG = { Alliance = "|cff4a8cff[A]|r", Horde = "|cffe03c3c[H]|r" }

-- Calls fn(name, realm, faction, data) for every saved character in scope:
-- all rulesets and factions, or only the current ones when allCharacters is off.
local function ForEachChar(fn)
    local all = M.db.allCharacters
    for realm, factions in pairs(M.db.realms) do
        if all or realm == playerRealm then
            for faction, chars in pairs(factions) do
                if all or faction == playerFaction then
                    for name, d in pairs(chars) do fn(name, realm, faction, d) end
                end
            end
        end
    end
end

local function CharLabel(name, realm, faction, class)
    local s = ClassColored(name, class)
    if realm ~= playerRealm then s = s .. C(GREY, " (" .. realm .. ")") end
    if faction ~= playerFaction and FACTION_TAG[faction] then s = s .. " " .. FACTION_TAG[faction] end
    return s
end

-- Returns array of { label, bags, bank, equipped, total }, warbandCount, grandTotal
local function GetCounts(itemID)
    local results, grand = {}, 0
    local withEquipped = M.db.includeEquipped
    ForEachChar(function(name, realm, faction, d)
        local b = d.bags and d.bags[itemID] or 0
        local k = d.bank and d.bank[itemID] or 0
        local e = withEquipped and d.equipped and d.equipped[itemID] or 0
        local t = b + k + e
        if t > 0 then
            results[#results + 1] = { label = CharLabel(name, realm, faction, d.class),
                bags = b, bank = k, equipped = e, total = t }
            grand = grand + t
        end
    end)
    table.sort(results, function(a, b) return a.total > b.total end)
    local wb = M.db.showWarband and M.db.warband[itemID] or 0
    return results, wb, grand + wb
end

local function Breakdown(r)
    local parts = {}
    if r.bags > 0 then parts[#parts + 1] = "Bags " .. r.bags end
    if r.bank > 0 then parts[#parts + 1] = "Bank " .. r.bank end
    if r.equipped > 0 then parts[#parts + 1] = "Equipped " .. r.equipped end
    return table.concat(parts, ", ")
end

-- Every item ID you have on any character in scope, plus Warband
local function AllItemIDs()
    local ids = {}
    ForEachChar(function(_, _, _, d)
        for _, t in ipairs({ d.bags, d.bank, d.equipped }) do
            if t then for id in pairs(t) do ids[id] = true end end
        end
    end)
    for id in pairs(M.db.warband) do ids[id] = true end
    return ids
end

-- How many of an item (matched by exact name) your characters hold, plus its item ID if one is found.
function M.CountByName(name)
    local total, foundID = 0, nil
    for id in pairs(AllItemIDs()) do
        local n = C_Item.GetItemNameByID(id)
        if n == name then
            foundID = id
            local _, _, grand = GetCounts(id)
            total = total + grand
        elseif not n and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    return total, foundID
end

local function FindItemByName(query)
    query = query:lower()
    for id in pairs(AllItemIDs()) do
        local name = C_Item.GetItemNameByID(id)
        if name and name:lower():find(query, 1, true) then return id end
    end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function AddToTooltip(tooltip, itemID)
    if not itemID or not M.db.tooltip then return end
    local results, wb, grand = GetCounts(itemID)
    if grand == 0 then return end
    tooltip:AddLine(" ")
    for _, r in ipairs(results) do
        tooltip:AddDoubleLine(r.label,
            r.total .. " |cff999999(" .. Breakdown(r) .. ")|r", 1, 1, 1, 1, 1, 1)
    end
    if wb > 0 then tooltip:AddDoubleLine("|cff00ccffWarband Bank|r", wb, 1, 1, 1, 1, 1, 1) end
    if #results + (wb > 0 and 1 or 0) > 1 then
        tooltip:AddDoubleLine("|cffffd100Total|r", "|cffffd100" .. grand .. "|r")
    end
    tooltip:Show()
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
-- Characters
---------------------------------------------------------------------------
local function ForgetChar(realm, faction, name)
    if name == playerName and realm == playerRealm then
        return false, "Can't forget the character you're logged in on."
    end
    local factions = M.db.realms[realm]
    local chars = factions and factions[faction]
    if not (chars and chars[name]) then return false, "That character isn't saved." end
    chars[name] = nil
    if not next(chars) then factions[faction] = nil end
    if not next(factions) then M.db.realms[realm] = nil end
    return true, "Forgot " .. name .. " (" .. realm .. ")."
end

-- Accepts "Name" or "Name-Ruleset"; searches every ruleset and faction.
local function DeleteChar(query)
    local qName, qRealm = query:match("^([^%-]+)%-(.+)$")
    qName = (qName or query):lower()
    qRealm = qRealm and qRealm:lower()
    local found = {}
    for realm, factions in pairs(M.db.realms) do
        for faction, chars in pairs(factions) do
            for name, d in pairs(chars) do
                local first = d.firstName and d.firstName:lower()
                if (name:lower() == qName or first == qName) and (not qRealm or realm:lower() == qRealm) then
                    found[#found + 1] = { realm, faction, name }
                end
            end
        end
    end
    if #found == 0 then return false, "No saved character named \"" .. query .. "\"." end
    if #found > 1 then return false, "More than one saved character is named that; use Name-Ruleset, e.g. Bob-PvP." end
    return ForgetChar(found[1][1], found[1][2], found[1][3])
end

---------------------------------------------------------------------------
-- Slash: /cf stash ...  (and /stash)
---------------------------------------------------------------------------
local function CmdLookup(msg)
    local id = tonumber(msg:match("item:(%d+)")) or tonumber(msg) or FindItemByName(msg)
    if not id then Print("no tracked item matches \"" .. msg .. "\".") return end
    local link = select(2, C_Item.GetItemInfo(id)) or ("item " .. id)
    local results, wb, grand = GetCounts(id)
    if grand == 0 then Print(link .. ": none found.") return end
    Print(link .. " - total " .. grand)
    for _, r in ipairs(results) do
        print("   " .. r.label .. ": " .. r.total .. " (" .. Breakdown(r) .. ")")
    end
    if wb > 0 then print("   |cff00ccffWarband Bank|r: " .. wb) end
end

function M:slash(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower()
    if msg == "" then
        CF.Open("stash")
    elseif cmd == "help" then
        Print("commands:")
        print("   /stash  - open the Stash window")
        print("   /stash <item link, ID or name>  - print counts")
        print("   /stash delete <name or name-ruleset>  - forget a character")
    elseif cmd == "delete" and rest ~= "" then
        local _, text = DeleteChar(rest)
        Print(text)
    else
        CmdLookup(msg)
    end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
-- WoW Forever reports the player's name as UNKNOWNOBJECT ("Unknown") early in
-- loading, sometimes still at PLAYER_LOGIN. Recording the character then
-- saved every alt under the same "Unknown" entry, each login overwriting the
-- last, so no other character was ever shown.
local function IsUnknownName(n)
    return not n or n == "" or n == UNKNOWNOBJECT or n == "Unknown"
end

-- Drop entries written before the game knew the name.
local function PurgeUnknown(db)
    for realm, factions in pairs(db.realms) do
        for faction, chars in pairs(factions) do
            for name in pairs(chars) do
                if IsUnknownName(name) then chars[name] = nil end
            end
            if not next(chars) then factions[faction] = nil end
        end
        if not next(factions) then db.realms[realm] = nil end
    end
end

-- WoW Forever names are unique per region as first name + surname, so two
-- characters can share a first name. Key by the full name when there is one.
local function FullName()
    local name, surname = UnitName("player")
    if IsUnknownName(name) then return nil end
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() and surname and surname ~= "" then
        local sep = Constants and Constants.CharacterNameSeparatorConsts
            and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
        return name .. sep .. surname, name
    end
    return name, name
end

-- Records the current character once its name is known; returns true when done.
local function RegisterCharacter(db)
    local key, firstName = FullName()
    if not key then return false end
    playerName = key
    playerRealm = GetRealmName()
    playerFaction = UnitFactionGroup("player") or "Neutral"
    playerClass = select(2, UnitClass("player"))

    PurgeUnknown(db)
    local realm = db.realms[playerRealm] or {}
    db.realms[playerRealm] = realm
    realm[playerFaction] = realm[playerFaction] or {}
    local chars = realm[playerFaction]
    if playerFaction ~= "Neutral" and realm.Neutral then
        realm.Neutral[playerName] = nil
        realm.Neutral[firstName] = nil
        if not next(realm.Neutral) then realm.Neutral = nil end
    end
    -- Data saved under the first name alone, before surnames were used.
    if key ~= firstName and chars[firstName] and not chars[key] then
        chars[key], chars[firstName] = chars[firstName], nil
    end

    charData = chars[key] or { bags = {}, bank = {}, equipped = {} }
    charData.class = playerClass
    charData.firstName = firstName
    chars[key] = charData

    QueueAll(BAGS, pending.bags)
    pending.equipped = true
    Queue()
    return true
end

function M:OnLogin()
    BuildContainerLists()
    if not RegisterCharacter(self.db) then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_ENTERING_WORLD")
        w:RegisterUnitEvent("UNIT_NAME_UPDATE", "player")
        w:SetScript("OnEvent", function(frame)
            if RegisterCharacter(M.db) then frame:UnregisterAllEvents() end
        end)
    end

    HookTooltips()

    SLASH_CFSTASH1 = "/stash"
    SlashCmdList.CFSTASH = function(msg) M:slash(msg) end

    local f = CreateFrame("Frame")
    local function Try(ev)
        if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(ev) then
            pcall(f.RegisterEvent, f, ev)
        end
    end
    for _, ev in ipairs({
        "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE",
        "PLAYER_EQUIPMENT_CHANGED",
        "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
        "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED",
        "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED",
        "TRADE_SKILL_ITEM_CRAFTED_RESULT",
        "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    }) do Try(ev) end
    f:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")

    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "BAG_UPDATE" then
            if IN_BAGS[arg1] then
                pending.bags[arg1] = true
            elseif IN_BANK[arg1] and BankReadable() and CanSeeBank("Character") then
                pending.bank[arg1] = true
            elseif IN_WARBAND[arg1] and BankReadable() and CanSeeBank("Account") then
                pending.warband[arg1] = true
            end
            Queue()
        elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_CONTAINER_UPDATE" then
            QueueAll(BAGS, pending.bags)
            Queue()
            if event == "BAG_CONTAINER_UPDATE" and bankOpen then QueueBank() end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" then
            pending.equipped = true
            Queue()
        elseif event == "BANKFRAME_OPENED" then
            OnBankOpened()
        elseif event == "BANKFRAME_CLOSED" then
            bankOpen = false
        elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            local T = Enum.PlayerInteractionType
            if T and (arg1 == T.Banker or arg1 == T.AccountBanker) then bankOpen = false end
        elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
            lastCraft = GetTime()
        else
            -- Bank slots or tabs changed (or a craft took reagents from the bank).
            QueueBank()
        end
    end)
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local SEARCH_COLS = { { 230 }, { 50, "RIGHT" }, { 230 } }

local function BuildSearch(p)
    p.box = W.EditBox(p, 300, "Search your items by name...", function()
        p.offset = 0
        CF.RefreshCurrent()
    end)
    p.box:SetPoint("TOPLEFT", 0, 0)
    p.count = W.Text(p, 11, 0.55, 0.55, 0.55)
    p.count:SetPoint("LEFT", p.box, "RIGHT", 12, 0)

    local hdr = W.ListHeader(p, SEARCH_COLS, { "Item", "Total", "Where" })
    hdr:SetPoint("TOPLEFT", 0, -34)
    hdr:SetPoint("RIGHT")
    p.list = W.List(p, SEARCH_COLS, 20, 13)
    p.list:SetPoint("TOPLEFT", 0, -54)
    p.list:SetPoint("RIGHT")

    local hint = W.Text(p, 11, 0.55, 0.55, 0.55)
    hint:SetPoint("BOTTOMLEFT", 0, 0)
    hint:SetText("Hover a row for the full breakdown. Bank counts update each time you visit a banker.")
end

local function RefreshSearch(p)
    local q = strtrim(p.box:GetText() or ""):lower()
    if #q < 2 then
        p.list:SetData({}, "Type at least 2 letters.")
        p.count:SetText("")
        return
    end
    local rows, missing = {}, 0
    for id in pairs(AllItemIDs()) do
        local name = C_Item.GetItemNameByID(id)
        if not name then
            missing = missing + 1
            if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        elseif name:lower():find(q, 1, true) then
            local results, wb, grand = GetCounts(id)
            if grand > 0 then
                local where = {}
                for _, r in ipairs(results) do where[#where + 1] = r.label .. " " .. r.total end
                if wb > 0 then where[#where + 1] = "|cff00ccffWarband|r " .. wb end
                rows[#rows + 1] = { cols = { W.ItemName(id), tostring(grand), table.concat(where, ", ") },
                    itemID = id, sortName = name }
            end
        end
    end
    table.sort(rows, function(a, b) return a.sortName < b.sortName end)
    p.list:SetData(rows, "No items match.")
    p.count:SetText(#rows .. " item" .. (#rows == 1 and "" or "s")
        .. (missing > 0 and C(GREY, "  (loading " .. missing .. " names, search again in a moment)") or ""))
end

local CHAR_COLS = { { 250 }, { 60, "RIGHT" }, { 60, "RIGHT" }, { 140 } }

local function BuildChars(p)
    p.title = W.Text(p, 12)
    p.title:SetPoint("TOPLEFT", 0, 0)
    local hdr = W.ListHeader(p, CHAR_COLS, { "Character", "Bags", "Bank", "Status" })
    hdr:SetPoint("TOPLEFT", 0, -22)
    hdr:SetPoint("RIGHT")
    p.list = W.List(p, CHAR_COLS, 20, 12)
    p.list:SetPoint("TOPLEFT", 0, -42)
    p.list:SetPoint("RIGHT")

    p.forget = W.Button(p, "Forget selected", 140, 24, function()
        local s = p.selected
        if not s then return end
        local ok, text = ForgetChar(s.realm, s.faction, s.name)
        Print(text)
        if ok then p.selected = nil end
        CF.RefreshCurrent()
    end)
    p.forget:SetPoint("BOTTOMLEFT", 0, 0)
    p.note = W.Text(p, 11, 0.55, 0.55, 0.55)
    p.note:SetPoint("LEFT", p.forget, "RIGHT", 12, 0)
    p.note:SetText("Use this for characters you've deleted, renamed or transferred.")
end

local function CountStacks(t)
    local n = 0
    if t then for _, c in pairs(t) do n = n + c end end
    return n
end

local function RefreshChars(p)
    if M.db.allCharacters then
        p.title:SetText("All rulesets and factions")
    else
        p.title:SetText((playerRealm or "") .. C(GREY, "  ·  " .. (playerFaction or "")))
    end
    local rows = {}
    local sel = p.selected
    ForEachChar(function(name, realm, faction, d)
        local isMe = name == playerName and realm == playerRealm
        local status
        if isMe then status = C(GREEN, "logged in")
        elseif not d.bankScanned then status = C(RED, "visit a banker")
        else status = C(GREY, d.lastSeen and date("seen %b %d", d.lastSeen) or "") end
        rows[#rows + 1] = {
            cols = { CharLabel(name, realm, faction, d.class), tostring(CountStacks(d.bags)),
                d.bankScanned and tostring(CountStacks(d.bank)) or "-", status },
            mark = sel and sel.name == name and sel.realm == realm and sel.faction == faction,
            sortKey = realm .. "\1" .. name,
            onClick = function()
                p.selected = { name = name, realm = realm, faction = faction }
                CF.RefreshCurrent()
            end,
        }
    end)
    table.sort(rows, function(a, b) return a.sortKey < b.sortKey end)
    p.list:SetData(rows)
    local canForget = sel and not (sel.name == playerName and sel.realm == playerRealm)
    p.forget:SetAlpha(canForget and 1 or 0.4)
end

local function BuildSettings(p)
    local db = M.db
    W.Header(p, "Tooltips"):SetPoint("TOPLEFT", 0, 0)
    p.items = {
        W.Check(p, "Show item counts in tooltips", function() return db.tooltip end,
            function(v) db.tooltip = v end),
        W.Check(p, "Include equipped items", function() return db.includeEquipped end,
            function(v) db.includeEquipped = v end, "Count gear your characters are wearing, not just bags and banks."),
        W.Check(p, "Show Warband bank", function() return db.showWarband end,
            function(v) db.showWarband = v end, "The Warband bank is shared by your whole account."),
        W.Check(p, "Include characters on other rulesets and factions", function() return db.allCharacters end,
            function(v) db.allCharacters = v end,
            "When off, only characters on your current ruleset (PvP, Normal, RP...) and faction are counted."),
    }
    for i, w in ipairs(p.items) do w:SetPoint("TOPLEFT", 0, -24 - (i - 1) * 24) end

    W.Header(p, "How it works"):SetPoint("TOPLEFT", 0, -144)
    local t = W.Text(p, 12, 0.7, 0.7, 0.7)
    t:SetPoint("TOPLEFT", 0, -168)
    t:SetWidth(520)
    t:SetWordWrap(true)
    t:SetText("Log into each character once to record its bags, and open a banker once to record its bank. "
        .. "Characters on another ruleset show it in brackets, e.g. (PvP), and other-faction characters show [A] or [H]. "
        .. "Data saves on logout or /reload.")
end

local function RefreshSettings(p)
    for _, w in ipairs(p.items) do w.Refresh() end
end

M.pages = {
    { key = "search",   label = "Search",     build = BuildSearch,   refresh = RefreshSearch },
    { key = "chars",    label = "Characters", build = BuildChars,    refresh = RefreshChars },
    { key = "settings", label = "Settings",   build = BuildSettings, refresh = RefreshSettings },
}
