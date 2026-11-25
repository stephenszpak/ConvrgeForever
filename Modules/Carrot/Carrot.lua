-- Carrot module: puts Carrot on a Stick in your top trinket slot when you
-- mount, and puts your previous trinket back when you dismount.
--
-- It never puts the carrot on in dungeons, raids, battlegrounds or arenas.
--
-- Equipping gear is blocked in combat, so a swap that comes due in combat
-- waits until combat ends.

local _, CF = ...
local W = CF.W
local C, GREEN, YELLOW, RED, GREY = W.C, W.GREEN, W.YELLOW, W.RED, W.GREY

local M = CF:NewModule("carrot", {
    title = "Carrot",
    description = "Equips Carrot on a Stick in your top trinket slot while mounted, then puts your trinket back.",
    defaults = {
        enabled = true,
        announce = true,
    },
    charDefaults = {
        -- savedTrinket = itemID that was in the top slot before the carrot went on
    },
})

local TOP_TRINKET = INVSLOT_TRINKET1 or 13
local BOTTOM_TRINKET = INVSLOT_TRINKET2 or 14

-- Mount-speed trinkets, by item ID. Name match below is a fallback.
local MOUNT_TRINKETS = {
    [11122] = true,   -- Carrot on a Stick
}
local MOUNT_TRINKET_NAMES = {
    ["Carrot on a Stick"] = true,
}

local db, charDB
local wasMounted
local status = ""      -- last thing that happened, for the page

local function Print(msg)
    status = msg
    if db and db.announce then CF.Print(msg, "Carrot") end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function IsMountTrinket(id)
    if not id then return false end
    if MOUNT_TRINKETS[id] then return true end
    local name = C_Item.GetItemNameByID(id)
    return name and MOUNT_TRINKET_NAMES[name] or false
end

-- Returns bag, slot of the first matching item in your bags
local function FindInBags(match)
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and match(info.itemID) then return bag, slot, info.itemID end
        end
    end
end

local function CarrotEquipped()
    return IsMountTrinket(GetInventoryItemID("player", TOP_TRINKET))
        or IsMountTrinket(GetInventoryItemID("player", BOTTOM_TRINKET))
end

-- The carrot never goes on in dungeons, raids, battlegrounds or arenas.
-- Putting your trinket back still works there.
local SKIPPED_INSTANCES = { party = true, raid = true, pvp = true, arena = true }

local function InSkippedInstance()
    local inInstance, kind = IsInInstance()
    return inInstance and SKIPPED_INSTANCES[kind] or false
end

-- Moves the item at bag/slot into the top trinket slot; the old trinket goes
-- back to that bag slot.
local function EquipFromBag(bag, slot)
    if CursorHasItem() or (GetCursorInfo and GetCursorInfo()) then return false end
    C_Container.PickupContainerItem(bag, slot)
    PickupInventoryItem(TOP_TRINKET)
    if CursorHasItem() then ClearCursor() end   -- swap didn't take: put it back
    return true
end

local function ItemLink(id)
    return (id and select(2, C_Item.GetItemInfo(id))) or (id and ("item " .. id)) or "nothing"
end

---------------------------------------------------------------------------
-- Swaps
--
-- A swap is only "done" once the game shows the new item in the slot.
-- Until then it is retried, waiting out anything that blocks gear changes
-- (combat, casting e.g. opening a chest, an item on the cursor, being dead).
---------------------------------------------------------------------------
local want            -- nil | "carrot" | "restore": what we're trying to do
local issued          -- { expect = itemID, prev = itemID } for the swap in flight
local attempts = 0
local busyUntil = 0
local MAX_ATTEMPTS = 10

local function BlockedBy()
    if InCombatLockdown() then return "combat" end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return "casting" end
    if CursorHasItem() or (GetCursorInfo and GetCursorInfo()) then return "cursor" end
    if UnitIsDeadOrGhost("player") then return "dead" end
end
M.BlockedBy = BlockedBy

-- Remember the last non-carrot trinket you wore up top, for recovery.
local function TrackTopTrinket()
    local top = GetInventoryItemID("player", TOP_TRINKET)
    if top and not IsMountTrinket(top) then charDB.lastTrinket = top end
end

local function Done(msg)
    want, issued, attempts = nil, nil, 0
    if msg then Print(msg) end
    CF.RefreshCurrent()
end

local function TrySwap(bag, slot, expect, prev)
    if attempts >= MAX_ATTEMPTS then
        Done(want == "carrot" and "couldn't equip your carrot, giving up until your next mount."
            or ("couldn't put " .. ItemLink(charDB.savedTrinket) .. " back; it will retry when you next dismount."))
        return
    end
    attempts = attempts + 1
    issued = { expect = expect, prev = prev }
    busyUntil = GetTime() + 1   -- give the game a moment before checking again
    EquipFromBag(bag, slot)
end

local function Reconcile()
    if not want or not db or not db.enabled then return end
    if GetTime() < busyUntil then return end
    local top = GetInventoryItemID("player", TOP_TRINKET)

    if want == "carrot" then
        if not IsMounted() then Done() return end
        if issued and top == issued.expect then
            charDB.savedTrinket = issued.prev
            charDB.carrotByUs = true
            Done("mounted: " .. ItemLink(top) .. " on, " .. ItemLink(issued.prev) .. " saved.")
            return
        end
        if CarrotEquipped() then Done() return end      -- already wearing one
        local bag, slot, id = FindInBags(IsMountTrinket)
        if not bag then Done() return end
        if BlockedBy() then return end
        TrySwap(bag, slot, id, top)

    elseif want == "restore" then
        if IsMounted() then Done() return end           -- got back on: keep the saved trinket
        local saved = charDB.savedTrinket
        if not saved and charDB.carrotByUs then saved = charDB.lastTrinket end
        if not saved then Done() return end
        if top == saved then
            charDB.savedTrinket, charDB.carrotByUs = nil, nil
            Done(issued and ("dismounted: " .. ItemLink(saved) .. " back on.") or nil)
            return
        end
        if not IsMountTrinket(top) then
            -- You put something else in the top slot yourself: leave it.
            charDB.savedTrinket, charDB.carrotByUs = nil, nil
            Done()
            return
        end
        local bag, slot = FindInBags(function(id) return id == saved end)
        if not bag then
            Done("couldn't find " .. ItemLink(saved) .. " in your bags to put back.")
            return
        end
        if BlockedBy() then return end
        TrySwap(bag, slot, saved, top)
    end
end

local function Check()
    if not db or not db.enabled then return end
    local mounted = IsMounted() and true or false
    if mounted ~= wasMounted then
        wasMounted = mounted
        want, issued, attempts, busyUntil = nil, nil, 0, 0
        if mounted then
            if not InSkippedInstance() then want = "carrot" end
        elseif charDB.savedTrinket or charDB.carrotByUs then
            want = "restore"
        end
    end
    Reconcile()
end

-- Manual recovery: put your last normal trinket back over the carrot.
function M.RestoreNow()
    if IsMounted() then CF.Print("dismount first.", "Carrot") return end
    if not charDB.savedTrinket then charDB.savedTrinket = charDB.lastTrinket end
    if not charDB.savedTrinket then CF.Print("no saved trinket to put back.", "Carrot") return end
    want, issued, attempts, busyUntil = "restore", nil, 0, 0
    Reconcile()
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
function M:OnLogin()
    db, charDB = self.db, self.char
    TrackTopTrinket()

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            -- Logged out on a mount last time? Put the trinket back.
            wasMounted = IsMounted() and true or false
            if not wasMounted and (charDB.savedTrinket or charDB.carrotByUs) then
                want, attempts = "restore", 0
                C_Timer.After(1, Reconcile)
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            TrackTopTrinket()
            busyUntil = 0          -- the swap landed (or something changed): check now
            C_Timer.After(0.1, Reconcile)
        elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
            C_Timer.After(0.1, Check)
        else
            -- combat ended or a cast finished: anything waiting can go now
            C_Timer.After(0.2, Reconcile)
        end
    end)

    -- Catches missed mount events and retries swaps: twice a second.
    C_Timer.NewTicker(0.5, Check)
end

function M:slash(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "on" or msg == "off" then
        db.enabled = (msg == "on")
        CF.Print("auto-swap " .. msg, "Carrot")
    else
        CF.Open("carrot")
    end
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local function BuildPage(p)
    local function changed() CF.RefreshCurrent() end
    W.Header(p, "Carrot on a Stick"):SetPoint("TOPLEFT", 0, 0)
    p.items = {
        W.Check(p, "Swap automatically when mounting and dismounting", function() return db.enabled end,
            function(v) db.enabled = v end, nil, changed),
        W.Check(p, "Chat message on each swap", function() return db.announce end,
            function(v) db.announce = v end, nil, changed),
    }
    for i, w in ipairs(p.items) do w:SetPoint("TOPLEFT", 0, -24 - (i - 1) * 24) end

    W.Header(p, "Status"):SetPoint("TOPLEFT", 0, -88)
    local labels = { "Carrot", "Top trinket", "Saved trinket", "Last swap" }
    p.vals = {}
    for i, l in ipairs(labels) do
        local k = W.Text(p, 12, 0.55, 0.55, 0.55)
        k:SetPoint("TOPLEFT", 0, -92 - i * 20)
        k:SetText(l)
        local v = W.Text(p, 12)
        v:SetPoint("TOPLEFT", 110, -92 - i * 20)
        v:SetWidth(420)
        p.vals[i] = v
    end

    p.restore = W.Button(p, "Put my trinket back", 160, 24, function()
        M.RestoreNow()
        CF.RefreshCurrent()
    end)
    p.restore:SetPoint("TOPLEFT", 0, -202)
    W.Tooltip(p.restore, "Swaps the carrot out for your saved trinket (or the last trinket you wore up top). Use it if the carrot ever gets stuck on.")

    local note = W.Text(p, 11, 0.55, 0.55, 0.55)
    note:SetPoint("TOPLEFT", 0, -238)
    note:SetWidth(520)
    note:SetWordWrap(true)
    note:SetText("The carrot never goes on in dungeons, raids, battlegrounds or arenas. "
        .. "Gear can't be changed in combat or while casting (opening a chest, gathering...), so a swap waits "
        .. "until you're free and only counts once the trinket is actually on. If you change your top trinket "
        .. "yourself while mounted, it's left alone when you dismount.")
end

local function RefreshPage(p)
    for _, w in ipairs(p.items) do w.Refresh() end

    local carrotText
    if CarrotEquipped() then
        carrotText = C(GREEN, "equipped")
    else
        local bag, _, id = FindInBags(IsMountTrinket)
        carrotText = bag and (W.ItemName(id) .. C(GREY, "  in bags")) or C(RED, "not found in your bags")
    end
    p.vals[1]:SetText(carrotText)

    local top = GetInventoryItemID("player", TOP_TRINKET)
    p.vals[2]:SetText(top and W.ItemName(top) or C(GREY, "empty"))
    local waiting = ""
    if want then
        local why = BlockedBy()
        local reasons = { combat = "after combat", casting = "after your cast", cursor = "once your cursor is empty", dead = "once you're alive" }
        waiting = C(YELLOW, "  (" .. (want == "restore" and "goes back " or "carrot goes on ")
            .. (why and reasons[why] or "now") .. ")")
    end
    p.vals[3]:SetText((charDB.savedTrinket and W.ItemName(charDB.savedTrinket) or C(GREY, "none")) .. waiting)

    local stuck = not IsMounted() and IsMountTrinket(top) and (charDB.savedTrinket or charDB.lastTrinket)
    p.restore:SetShown(stuck and true or false)
    p.vals[4]:SetText(status ~= "" and status or C(GREY, "nothing yet this session"))
end

M.pages = {
    { key = "carrot", label = "Carrot", build = BuildPage, refresh = RefreshPage, live = true },
}
