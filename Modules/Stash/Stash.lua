-- Stash module: item counts across your characters' bags, equipped gear,
-- character bank and Warband bank. Counts show in item tooltips for
-- characters on the same realm + faction. (Formerly the StashCount addon.)

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
local BAGS, BANK, WARBAND = {}, {}, {}

local function BuildContainerLists()
    local E = Enum and Enum.BagIndex
    if not E then
        for i = 0, 4 do BAGS[#BAGS + 1] = i end
        BANK[#BANK + 1] = -1
        for i = 5, 11 do BANK[#BANK + 1] = i end
        return
    end
    for key, id in pairs(E) do
        if key == "Backpack" or key:match("^Bag_%d+$") or key == "ReagentBag" then
            BAGS[#BAGS + 1] = id
        elseif key:match("^CharacterBankTab_%d+$") or key == "Bank"
            or key:match("^BankBag_%d+$") or key == "Reagentbank" then
            BANK[#BANK + 1] = id
        elseif key:match("^AccountBankTab_%d+$") then
            WARBAND[#WARBAND + 1] = id
        end
    end
end

local function ScanContainers(list)
    local counts, slots = {}, 0
    for _, bag in ipairs(list) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        slots = slots + n
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return counts, slots
end

local function ScanEquipped()
    local counts = {}
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then counts[id] = (counts[id] or 0) + 1 end
    end
    return counts
end

local function ScanBags()
    if not charData then return end
    charData.bags = ScanContainers(BAGS)
    charData.equipped = ScanEquipped()
    charData.lastSeen = time()
end

local function ScanBank()
    if not charData or not bankOpen then return end
    local counts, slots = ScanContainers(BANK)
    if slots > 0 then
        charData.bank = counts
        charData.bankScanned = true
    end
    local wb, wbSlots = ScanContainers(WARBAND)
    if wbSlots > 0 then M.db.warband = wb end
end

local function OnBankOpened()
    bankOpen = true
    ScanBank()
    C_Timer.After(0.5, ScanBank)
end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------
local function ClassColored(name, class)
    local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
    return c and c:WrapTextInColorCode(name) or name
end

local function MyChars()
    local realm = M.db.realms[playerRealm]
    return realm and realm[playerFaction] or {}
end

-- Returns array of { name, class, bags, bank, equipped, total }, warbandCount, grandTotal
local function GetCounts(itemID)
    local results, grand = {}, 0
    local withEquipped = M.db.includeEquipped
    for name, d in pairs(MyChars()) do
        local b = d.bags and d.bags[itemID] or 0
        local k = d.bank and d.bank[itemID] or 0
        local e = withEquipped and d.equipped and d.equipped[itemID] or 0
        local t = b + k + e
        if t > 0 then
            results[#results + 1] = { name = name, class = d.class, bags = b, bank = k, equipped = e, total = t }
            grand = grand + t
        end
    end
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

-- Every item ID you have anywhere (this realm + faction, plus Warband)
local function AllItemIDs()
    local ids = {}
    for _, d in pairs(MyChars()) do
        for _, t in ipairs({ d.bags, d.bank, d.equipped }) do
            if t then for id in pairs(t) do ids[id] = true end end
        end
    end
    for id in pairs(M.db.warband) do ids[id] = true end
    return ids
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
        tooltip:AddDoubleLine(ClassColored(r.name, r.class),
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
local function DeleteChar(name)
    local chars = MyChars()
    for stored in pairs(chars) do
        if stored:lower() == name:lower() then
            if stored == playerName then return false, "Can't forget the character you're logged in on." end
            chars[stored] = nil
            return true, "Forgot " .. stored .. "."
        end
    end
    return false, "No character named \"" .. name .. "\" on this realm/faction."
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
        print("   " .. ClassColored(r.name, r.class) .. ": " .. r.total .. " (" .. Breakdown(r) .. ")")
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
        print("   /stash delete <name>  - forget a character")
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
function M:OnLogin()
    playerName = UnitName("player")
    playerRealm = GetRealmName()
    playerFaction = UnitFactionGroup("player") or "Neutral"
    playerClass = select(2, UnitClass("player"))

    local realm = self.db.realms[playerRealm] or {}
    self.db.realms[playerRealm] = realm
    realm[playerFaction] = realm[playerFaction] or {}
    if playerFaction ~= "Neutral" and realm.Neutral then realm.Neutral[playerName] = nil end

    charData = realm[playerFaction][playerName] or { bags = {}, bank = {}, equipped = {} }
    charData.class = playerClass
    realm[playerFaction][playerName] = charData

    BuildContainerLists()
    HookTooltips()
    ScanBags()

    SLASH_CFSTASH1 = "/stash"
    SlashCmdList.CFSTASH = function(msg) M:slash(msg) end

    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("BANKFRAME_OPENED")
    f:RegisterEvent("BANKFRAME_CLOSED")
    f:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    if C_EventUtils and C_EventUtils.IsEventValid then
        for _, ev in ipairs({ "PLAYERREAGENTBANKSLOTS_CHANGED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
                              "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
            if C_EventUtils.IsEventValid(ev) then f:RegisterEvent(ev) end
        end
    end
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "BAG_UPDATE_DELAYED" then
            ScanBags()
            if bankOpen then ScanBank() end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            charData.equipped = ScanEquipped()
        elseif event == "BANKFRAME_OPENED" then
            OnBankOpened()
        elseif event == "BANKFRAME_CLOSED" then
            bankOpen = false
        elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERREAGENTBANKSLOTS_CHANGED" then
            ScanBank()
        else
            local kind = ...
            local T = Enum.PlayerInteractionType
            if T and (kind == T.Banker or kind == T.AccountBanker) then
                if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then OnBankOpened() else bankOpen = false end
            end
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
                for _, r in ipairs(results) do where[#where + 1] = ClassColored(r.name, r.class) .. " " .. r.total end
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

local CHAR_COLS = { { 170 }, { 60, "RIGHT" }, { 60, "RIGHT" }, { 140 } }

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
        if not p.selected then return end
        local ok, text = DeleteChar(p.selected)
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
    p.title:SetText(playerRealm .. C(GREY, "  ·  " .. playerFaction))
    local rows = {}
    for name, d in pairs(MyChars()) do
        local status
        if name == playerName then status = C(GREEN, "logged in")
        elseif not d.bankScanned then status = C(RED, "visit a banker")
        else status = C(GREY, d.lastSeen and date("seen %b %d", d.lastSeen) or "") end
        rows[#rows + 1] = {
            cols = { ClassColored(name, d.class), tostring(CountStacks(d.bags)),
                d.bankScanned and tostring(CountStacks(d.bank)) or "-", status },
            mark = (name == p.selected), sortName = name,
            onClick = function() p.selected = name; CF.RefreshCurrent() end,
        }
    end
    table.sort(rows, function(a, b) return a.sortName < b.sortName end)
    p.list:SetData(rows)
    local canForget = p.selected and p.selected ~= playerName
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
    }
    for i, w in ipairs(p.items) do w:SetPoint("TOPLEFT", 0, -24 - (i - 1) * 24) end

    W.Header(p, "How it works"):SetPoint("TOPLEFT", 0, -120)
    local t = W.Text(p, 12, 0.7, 0.7, 0.7)
    t:SetPoint("TOPLEFT", 0, -144)
    t:SetWidth(520)
    t:SetWordWrap(true)
    t:SetText("Log into each character once to record its bags, and open a banker once to record its bank. "
        .. "Counts cover characters on your current realm and faction. Data saves on logout or /reload.")
end

local function RefreshSettings(p)
    for _, w in ipairs(p.items) do w.Refresh() end
end

M.pages = {
    { key = "search",   label = "Search",     build = BuildSearch,   refresh = RefreshSearch },
    { key = "chars",    label = "Characters", build = BuildChars,    refresh = RefreshChars },
    { key = "settings", label = "Settings",   build = BuildSettings, refresh = RefreshSettings },
}
