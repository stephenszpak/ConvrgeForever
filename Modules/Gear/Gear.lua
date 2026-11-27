-- Gear module: situational gear sets that go on top of whatever you're wearing.
--
-- A set only covers the slots it names. Putting one on remembers what each of
-- those slots held, and taking it off puts that back. Kinds:
--   onuse    an item you equip to press (an AoE trinket). It comes off after
--            you use it, once combat ends, and you're told when it's ready again.
--   custom   anything else (Fire Res, a farming set). Comes off when you say so,
--            or after combat if you pick that.
--   slayer   items with extra damage against one mob type (Slayer.lua builds
--            these from your items' tooltips).
-- Main sets stay in the game's equipment manager; the bar can equip those too.
--
-- Gear can't change in combat or while casting, so every swap is a request
-- that's retried until the game shows the item in the slot.
--
-- Saved per character (ConvrgeForeverCharDB.gear):
--   sets[i]      = { id, name, kind, restore, slots = { [slot] = itemID }, kindAuto, mob? }
--   saved[slot]  = { id = itemID or 0 (empty), by = set id }   what a set replaced
--   active[id]   = { used, combat }                            sets we put on
--   picks[cat]   = set id (or equipment set ID for "main") shown on the bar

local _, CF = ...
local W = CF.W
local C, GREEN, YELLOW, RED, GREY = W.C, W.GREEN, W.YELLOW, W.RED, W.GREY

local M = CF:NewModule("gear", {
    title = "Gear",
    description = "Situational gear sets on a small bar: equip an on-use trinket for a big pull and your normal gear goes back on after combat.",
    defaults = {
        bar = { show = true, locked = false, up = true },
        alertChat = true,
        alertSound = true,
        alertScreen = true,
        alertInstanceOnly = false,
        slayerLootAlert = true,   -- chat line when you loot a new slayer item
        slayerGlow = true,        -- bar glows when your target matches a slayer set
        items = {},               -- [itemID] = { v, slayer = { [mob type] = multiplier } }, from tooltips
        mobs = {},                -- [npcID] = mob type you taught
    },
    charDefaults = {
        sets = {},
        nextID = 1,
        saved = {},
        active = {},
        picks = {},
    },
})

local db, charDB
local status = ""

local function Say(msg)
    status = msg
    CF.Print(msg, "Gear")
end

---------------------------------------------------------------------------
-- Slots and items
---------------------------------------------------------------------------
local SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" },
    { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { 11, "Ring 1" }, { 12, "Ring 2" },
    { 13, "Trinket 1" }, { 14, "Trinket 2" }, { 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged" },
}
local SLOT_NAME = {}
for _, s in ipairs(SLOTS) do SLOT_NAME[s[1]] = s[2] end

local TOP_TRINKET = INVSLOT_TRINKET1 or 13

-- Which slots an item can go in, by its equip location.
local FITS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function Fits(itemID, slot)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    for _, s in ipairs(equipLoc and FITS[equipLoc] or {}) do
        if s == slot then return true end
    end
    return false
end

local GetItemSpell = (C_Item and C_Item.GetItemSpell) or _G.GetItemSpell
local GetItemCooldown = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
local GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
local EquipItem = (C_Item and C_Item.EquipItemByName) or _G.EquipItemByName

-- The spell an item casts when you use it (nil for items with no "Use:").
local function UseSpell(itemID)
    if not itemID or not GetItemSpell then return end
    local name, spellID = GetItemSpell(itemID)
    if name then return spellID or true end
end

local function ItemIcon(itemID)
    return itemID and C_Item.GetItemIconByID(itemID) or 134400   -- question mark
end

-- Item cooldown: start, duration (0, 0 when ready).
local function Cooldown(itemID)
    if not GetItemCooldown then return 0, 0 end
    local start, duration = GetItemCooldown(itemID)
    return start or 0, duration or 0
end

-- The equip lock on a freshly equipped on-use item is about 30 seconds.
-- Anything longer is a real cooldown from using it.
local EQUIP_LOCK = 30.5

---------------------------------------------------------------------------
-- Sets
---------------------------------------------------------------------------
local function SetByID(id)
    for _, s in ipairs(charDB.sets) do
        if s.id == id then return s end
    end
end

local function SetsOf(kind)
    local t = {}
    for _, s in ipairs(charDB.sets) do
        if s.kind == kind then t[#t + 1] = s end
    end
    return t
end

local function CountSlots(s)
    local n = 0
    for _ in pairs(s.slots) do n = n + 1 end
    return n
end

-- For on-use sets: the slot holding the item you press (trinkets first).
local function UseSlot(s)
    for _, slot in ipairs({ 13, 14 }) do
        if s.slots[slot] and UseSpell(s.slots[slot]) then return slot end
    end
    for _, e in ipairs(SLOTS) do
        local id = s.slots[e[1]]
        if id and UseSpell(id) then return e[1] end
    end
end

local function UseItem(s)
    local slot = UseSlot(s)
    return slot and s.slots[slot], slot
end

local function SetIcon(s)
    local id = UseItem(s)
    if not id then
        for _, e in ipairs(SLOTS) do
            if s.slots[e[1]] then id = s.slots[e[1]]; break end
        end
    end
    return ItemIcon(id)
end

-- Every item in the set is on, in its slot.
local function IsWorn(s)
    if not next(s.slots) then return false end
    for slot, id in pairs(s.slots) do
        if GetInventoryItemID("player", slot) ~= id then return false end
    end
    return true
end

-- Kind follows the items until you pick one yourself: a set with a "Use:"
-- item is an on-use set.
local function AutoKind(s)
    if not s.kindAuto then return end
    local kind = UseSlot(s) and "onuse" or "custom"
    if kind ~= s.kind then
        s.kind = kind
        s.restore = (kind == "onuse") and "use" or "manual"
    end
end

local function NewSet()
    local s = { id = charDB.nextID, name = "Set " .. charDB.nextID, kind = "custom",
                restore = "manual", slots = {}, kindAuto = true }
    charDB.nextID = charDB.nextID + 1
    charDB.sets[#charDB.sets + 1] = s
    return s
end

local TakeOff   -- defined below

-- Deleting a set that's on puts your gear back first.
local function DeleteSet(s)
    TakeOff(s)
    for i, x in ipairs(charDB.sets) do
        if x == s then table.remove(charDB.sets, i) break end
    end
    for cat, id in pairs(charDB.picks) do
        if cat ~= "main" and id == s.id then charDB.picks[cat] = nil end
    end
end

---------------------------------------------------------------------------
-- Where is an item? (Stash knows the bank and your other characters.)
---------------------------------------------------------------------------
local function Where(itemID)
    local S = CF.modules.stash
    if not (S and S.running and S.Current and S.ForEachChar) then return "" end
    local d = S.Current()
    if d and d.bank and (d.bank[itemID] or 0) > 0 then return ": it's in your bank" end
    local wb = S.Warband and S.Warband()
    if wb and (wb[itemID] or 0) > 0 then return ": it's in your Warband bank" end
    local who
    S.ForEachChar(function(name, realm, faction, data)
        if who or data == d then return end
        for _, k in ipairs({ "bags", "bank", "equipped" }) do
            if data[k] and (data[k][itemID] or 0) > 0 then
                who = S.CharLabel(name, realm, faction, data.class)
                return
            end
        end
    end)
    return who and (": " .. who .. " has it") or ""
end

---------------------------------------------------------------------------
-- Carrot hand-off
--
-- Carrot keeps your real top trinket while the carrot is on. If we change the
-- top slot while that's happening, the two modules agree on one "real" trinket.
---------------------------------------------------------------------------
local function Carrot()
    local m = CF.modules.carrot
    return m and m.running and m.char and m.IsMountTrinket and m or nil
end

-- The item to remember for this slot before we cover it.
local function OriginalFor(slot)
    local cur = GetInventoryItemID("player", slot)
    local carrot = Carrot()
    if slot == TOP_TRINKET and carrot and carrot.IsMountTrinket(cur) and carrot.char.savedTrinket then
        local real = carrot.char.savedTrinket
        carrot.char.savedTrinket, carrot.char.carrotByUs = nil, nil
        return real
    end
    return cur or 0
end

-- Putting an item back in the top slot while mounted with the carrot on:
-- let Carrot put it back when you dismount instead.
local function CarrotTakes(slot, itemID)
    local carrot = Carrot()
    if slot ~= TOP_TRINKET or not carrot or itemID == 0 then return false end
    if not IsMounted() or not carrot.IsMountTrinket(GetInventoryItemID("player", slot)) then return false end
    carrot.char.savedTrinket = itemID
    return true
end

---------------------------------------------------------------------------
-- Swaps
---------------------------------------------------------------------------
local want = {}            -- [slot] = itemID (0 = take it off)
local attempts, busyUntil = 0, 0
local MAX_ATTEMPTS = 8

local function BlockedBy()
    if InCombatLockdown() then return "combat" end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return "casting" end
    if CursorHasItem() or (GetCursorInfo and GetCursorInfo()) then return "cursor" end
    if UnitIsDeadOrGhost("player") then return "dead" end
end
M.BlockedBy = BlockedBy

local function Swapping() return next(want) ~= nil end
M.Swapping = Swapping

local function Unequip(slot)
    local ToInv = (C_Container and C_Container.ContainerIDToInventoryID) or _G.ContainerIDToInventoryID
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if (free or 0) > 0 and (family or 0) == 0 then
            PickupInventoryItem(slot)
            if bag == 0 then PutItemInBackpack() else PutItemInBag(ToInv(bag)) end
            if CursorHasItem() then ClearCursor() end
            return true
        end
    end
    Say("no bag space to take off your " .. SLOT_NAME[slot]:lower() .. " item.")
    return false
end

local Changed   -- defined below: refreshes the bar and page

local function Reconcile()
    if not next(want) then return end
    for slot, id in pairs(want) do
        local cur = GetInventoryItemID("player", slot)
        if (id == 0 and not cur) or cur == id then want[slot] = nil end
    end
    if not next(want) then
        attempts = 0
        Changed()
        return
    end
    if GetTime() < busyUntil or BlockedBy() then return end
    if attempts >= MAX_ATTEMPTS then
        local names = {}
        for slot in pairs(want) do names[#names + 1] = SLOT_NAME[slot]:lower() end
        Say("couldn't change your " .. table.concat(names, ", ") .. "; giving up.")
        wipe(want)
        attempts = 0
        Changed()
        return
    end
    attempts = attempts + 1
    busyUntil = GetTime() + 1
    for slot, id in pairs(want) do
        if CarrotTakes(slot, id) then
            want[slot] = nil
        elseif id == 0 then
            if not Unequip(slot) then want[slot] = nil end
        elseif (GetItemCount(id) or 0) == 0 then
            Say(W.ItemName(id) .. " isn't in your bags" .. Where(id) .. ".")
            want[slot] = nil
            local saved = charDB.saved[slot]
            if saved and GetInventoryItemID("player", slot) == (saved.id ~= 0 and saved.id or nil) then
                charDB.saved[slot] = nil   -- nothing was covered after all
            end
        else
            EquipItem(id, slot)
        end
    end
end

local function Request(slots)
    for slot, id in pairs(slots) do want[slot] = id end
    attempts, busyUntil = 0, 0
    Reconcile()
    Changed()
end

---------------------------------------------------------------------------
-- Putting sets on and taking them off
---------------------------------------------------------------------------
local function IsActive(s) return charDB.active[s.id] ~= nil end

local function PutOn(s)
    if not next(s.slots) then Say(s.name .. " has no items yet.") return end
    if InCombatLockdown() then Say("can't change gear in combat.") return end
    local req = {}
    for slot, id in pairs(s.slots) do
        if GetInventoryItemID("player", slot) ~= id then
            local saved = charDB.saved[slot]
            if saved then
                saved.by = s.id                 -- keep the first original
            else
                charDB.saved[slot] = { id = OriginalFor(slot), by = s.id }
            end
            req[slot] = id
        end
    end
    -- Another set that shares a slot with this one is now partly covered.
    for otherID in pairs(charDB.active) do
        if otherID ~= s.id then
            local still = false
            for _, saved in pairs(charDB.saved) do
                if saved.by == otherID then still = true break end
            end
            if not still then charDB.active[otherID] = nil end
        end
    end
    charDB.active[s.id] = { used = false, combat = false, at = GetTime() }
    local item = UseItem(s)
    if s.kind == "onuse" and item then
        local start, duration = Cooldown(item)
        local left = start + duration - GetTime()
        if duration > EQUIP_LOCK and left > 0 then
            Say(("%s is still on cooldown: ready in %d:%02d."):format(W.ItemName(item), left / 60, left % 60))
        end
    end
    charDB.picks[s.kind] = s.id
    if next(req) then Request(req) else Changed() end
end

-- Puts back what the set covered. Other sets' slots are left alone.
TakeOff = function(s)
    local req = {}
    for slot, saved in pairs(charDB.saved) do
        if saved.by == s.id then
            req[slot] = saved.id
            charDB.saved[slot] = nil
        end
    end
    charDB.active[s.id] = nil
    if next(req) then
        Request(req)
    else
        if IsWorn(s) then Say("nothing saved to put back over " .. s.name .. "; change those slots yourself.") end
        Changed()
    end
end

-- Takes off every set, including ones you deleted while they were on.
local function TakeOffAll()
    local req = {}
    for slot, saved in pairs(charDB.saved) do req[slot] = saved.id end
    wipe(charDB.saved)
    wipe(charDB.active)
    if next(req) then Request(req) else Changed() end
end

local function Toggle(s)
    if IsActive(s) or IsWorn(s) then TakeOff(s) else PutOn(s) end
end

-- After you change a covered slot yourself (or a main set does), that slot
-- isn't ours to put back any more.
local function ForgetReplacedSlots()
    if Swapping() then return end
    local carrot = Carrot()
    for slot, saved in pairs(charDB.saved) do
        local s = SetByID(saved.by)
        local cur = GetInventoryItemID("player", slot)
        local ours = s and s.slots[slot] == cur
        local carrotOn = carrot and slot == TOP_TRINKET and carrot.IsMountTrinket(cur)
        if s and not ours and not carrotOn then charDB.saved[slot] = nil end
    end
    for id in pairs(charDB.active) do
        local any = false
        for _, saved in pairs(charDB.saved) do
            if saved.by == id then any = true break end
        end
        local s = SetByID(id)
        if not any and not (s and IsWorn(s)) then charDB.active[id] = nil end
    end
end

-- Takes sets off when their time comes: after use, or after combat.
local function CheckRestores()
    if InCombatLockdown() or Swapping() then return end
    for id, a in pairs(charDB.active) do
        local s = SetByID(id)
        if s then
            local due = (s.restore == "use" and a.used) or (s.restore == "combat" and a.combat)
            if due then
                TakeOff(s)
                Say(s.name .. (a.used and " used" or "") .. ": your gear is back on.")
                return   -- one at a time; the next check picks up the rest
            end
        end
    end
end

---------------------------------------------------------------------------
-- Main sets (the game's equipment manager)
---------------------------------------------------------------------------
local pendingMain

local function MainSets()
    local list = {}
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs) then return list end
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name, icon, setID, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
        if name then list[#list + 1] = { id = setID or id, name = name, icon = icon, equipped = isEquipped } end
    end
    return list
end

local function EquipMain(id)
    charDB.picks.main = id
    if InCombatLockdown() then
        pendingMain = id
        Say("main set goes on after combat.")
        Changed()
        return
    end
    pendingMain = nil
    C_EquipmentSet.UseEquipmentSet(id)
    Changed()
end

---------------------------------------------------------------------------
-- Ready alerts for on-use items
---------------------------------------------------------------------------
local cdEnd = {}       -- [itemID] = GetTime() when its cooldown ends

local function Alert(itemID)
    if db.alertInstanceOnly and not IsInInstance() then return end
    local msg = W.ItemName(itemID) .. " is ready."
    if db.alertChat then CF.Print(msg, "Gear") end
    if db.alertSound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.RAID_WARNING or 8959, "Master") end
    if db.alertScreen and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.8, b = 0.2 })
    end
end

local function WatchCooldowns(silent)
    local now = GetTime()
    for _, s in ipairs(SetsOf("onuse")) do
        local id = UseItem(s)
        if id then
            local start, duration = Cooldown(id)
            if duration > EQUIP_LOCK and start > 0 then
                cdEnd[id] = start + duration
            elseif cdEnd[id] and now >= cdEnd[id] - 0.5 then
                cdEnd[id] = nil
                if not silent then Alert(id) end
            end
        end
    end
end

-- Marks on-use sets as used: by the item's spell going off, or failing that,
-- by a real (longer than the equip lock) cooldown starting on its slot.
local function CheckUsed(spellID)
    for id, a in pairs(charDB.active) do
        local s = SetByID(id)
        if s and s.kind == "onuse" and not a.used then
            local item, slot = UseItem(s)
            if item then
                local sid = UseSpell(item)
                if spellID and sid == spellID then
                    a.used = true
                elseif GetInventoryItemID("player", slot) == item then
                    -- A cooldown that started before you put it on isn't a use.
                    local start, duration = GetInventoryItemCooldown("player", slot)
                    if (duration or 0) > EQUIP_LOCK and (start or 0) >= (a.at or 0) - 1 then a.used = true end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Refresh hooks (the bar lives in GearBar.lua)
---------------------------------------------------------------------------
Changed = function()
    if M.RefreshBar then M.RefreshBar() end
    CF.RefreshCurrent()
end

---------------------------------------------------------------------------
-- Shared with GearBar.lua
---------------------------------------------------------------------------
M.SLOTS, M.SLOT_NAME = SLOTS, SLOT_NAME
M.SetByID, M.SetsOf, M.UseSlot, M.UseItem, M.SetIcon = SetByID, SetsOf, UseSlot, UseItem, SetIcon
M.IsWorn, M.IsActive, M.PutOn, M.TakeOff, M.Toggle = IsWorn, IsActive, PutOn, TakeOff, Toggle
M.MainSets, M.EquipMain, M.Cooldown, M.ItemIcon = MainSets, EquipMain, Cooldown, ItemIcon
M.Say = Say
M.FITS, M.NewSet, M.Changed = FITS, NewSet, function() Changed() end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
function M:OnLogin()
    db, charDB = self.db, self.char

    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED",
        "BAG_UPDATE_COOLDOWN" }) do
        f:RegisterEvent(e)
    end
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")

    local settleToken = 0
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            for _, a in pairs(charDB.active) do a.combat = true end
            Changed()
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingMain then EquipMain(pendingMain) end
            C_Timer.After(0.2, function()
                Reconcile()
                CheckRestores()
                Changed()
            end)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local _, _, spellID = ...
            CheckUsed(spellID)
            if not InCombatLockdown() then C_Timer.After(0.3, CheckRestores) end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            busyUntil = 0
            settleToken = settleToken + 1
            local token = settleToken
            C_Timer.After(0.3, function()
                if token ~= settleToken then return end
                Reconcile()
                ForgetReplacedSlots()
                Changed()
            end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            WatchCooldowns(true)
            C_Timer.After(1, function()
                ForgetReplacedSlots()
                CheckRestores()
                Changed()
            end)
        elseif event == "BAG_UPDATE_COOLDOWN" then
            CheckUsed()
            if M.RefreshBar then M.RefreshBar() end
        else
            -- cast finished, bags changed, sets changed: anything waiting can go now
            C_Timer.After(0.2, function()
                Reconcile()
                Changed()
            end)
        end
    end)

    -- Retries swaps, takes sets off when due, and watches cooldowns.
    C_Timer.NewTicker(1, function()
        Reconcile()
        CheckUsed()
        CheckRestores()
        WatchCooldowns()
    end)

    if M.InitSlayer then M.InitSlayer() end
    if M.InitBar then M.InitBar() end
end

function M:slash(msg)
    msg = strtrim(msg or "")
    local lower = msg:lower()
    if lower == "" then
        CF.Open("gear")
    elseif lower == "bar" then
        db.bar.show = not db.bar.show
        Changed()
        CF.Print("bar " .. (db.bar.show and "shown" or "hidden"), "Gear")
    elseif lower == "off" then
        TakeOffAll()
    elseif lower == "help" then
        CF.Print("commands:", "Gear")
        print("   /cf gear  - open the Gear page")
        print("   /cf gear <set name>  - put a set on, or take it off")
        print("   /cf gear off  - take off every set")
        print("   /cf gear bar  - show or hide the bar")
        print("   /cf gear teach <mob type>  - remember your target as that type (Naga, Ogre...)")
        print("   /cf gear forget  - forget what your target was taught as")
    elseif lower:match("^teach%s") and M.Teach then
        M.Teach(strtrim(msg:sub(6)))
    elseif lower == "forget" and M.Teach then
        M.Teach(nil)
    else
        for _, s in ipairs(charDB.sets) do
            if s.name:lower() == lower then Toggle(s) return end
        end
        CF.Print("no set called \"" .. msg .. "\".", "Gear")
    end
end

-- Keybinding labels (Options > Keybindings > AddOns > ConvrgeForever)
_G["BINDING_NAME_CLICK ConvrgeGearUseButton:LeftButton"] = "Gear: put on / use on-use set"

---------------------------------------------------------------------------
-- Sets page
---------------------------------------------------------------------------
local selected     -- set being edited
local deleteArmed

local RESTORE_TEXT = { use = "after use", combat = "after combat", manual = "when you say" }

local function SetLabel(s)
    local tag = IsWorn(s) and C(GREEN, " on") or (IsActive(s) and C(YELLOW, " going on") or "")
    return s.name .. tag
end

local function BuildSets(p)
    local function refresh() CF.RefreshCurrent() end

    -- List of sets
    W.Header(p, "Your sets"):SetPoint("TOPLEFT", 0, 0)
    local cols = { { 150 } }
    p.list = W.List(p, cols, 22, 14)
    p.list:SetPoint("TOPLEFT", 0, -22)
    p.list:SetWidth(170)
    p.new = W.Button(p, "New set", 80, 22, function()
        selected = NewSet()
        deleteArmed = nil
        Changed()
    end)
    p.new:SetPoint("TOPLEFT", 0, -338)
    p.offAll = W.Button(p, "Take off all", 86, 22, function() TakeOffAll() end)
    p.offAll:SetPoint("LEFT", p.new, "RIGHT", 4, 0)
    W.Tooltip(p.offAll, "Puts back everything any set covered.")

    -- Editor
    local ed = CreateFrame("Frame", nil, p)
    ed:SetPoint("TOPLEFT", 190, 0)
    ed:SetPoint("BOTTOMRIGHT")
    p.ed = ed

    p.name = W.EditBox(ed, 200, "Set name", function(text)
        if selected and strtrim(text) ~= "" and text ~= selected.name then
            selected.name = strtrim(text)
            if M.RefreshBar then M.RefreshBar() end
            p.list:SetData(p.listData or {})
        end
    end)
    p.name:SetPoint("TOPLEFT", 0, 0)

    p.kind = W.Choice(ed, "Kind", { { "onuse", "On-use" }, { "custom", "Custom" }, { "slayer", "Slayer" } },
        function() return selected and selected.kind end,
        function(v)
            selected.kind, selected.kindAuto = v, false
            if v ~= "onuse" and selected.restore == "use" then selected.restore = "manual" end
            if v == "onuse" then selected.restore = "use" end
        end, function() Changed() end)
    p.kind:SetPoint("TOPLEFT", 0, -32)

    p.restore = W.Choice(ed, "Take off", { { "use", "After use" }, { "combat", "Combat" }, { "manual", "Manual" } },
        function() return selected and selected.restore end,
        function(v)
            if v == "use" and selected.kind ~= "onuse" then return end
            selected.restore = v
        end, function() Changed() end)
    p.restore:SetPoint("TOPLEFT", 0, -58)

    local hint = W.Text(ed, 11, 0.55, 0.55, 0.55)
    hint:SetPoint("TOPLEFT", 0, -86)
    hint:SetText("Click a slot to use what you're wearing there. Drop an item on it from your bags. Right-click clears.")
    hint:SetWidth(340)
    hint:SetWordWrap(true)

    -- Slot grid: two columns
    p.cells = {}
    for i, e in ipairs(SLOTS) do
        local slot = e[1]
        local cell = CreateFrame("Button", nil, ed, "BackdropTemplate")
        cell:SetSize(168, 20)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        cell:SetPoint("TOPLEFT", col * 174, -114 - row * 22)
        W.Flat(cell, 0.08, 0.08, 0.08, 1, 0.2, 0.2, 0.2, 1)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(16, 16)
        cell.icon:SetPoint("LEFT", 2, 0)
        cell.label = W.Text(cell, 11, 0.55, 0.55, 0.55)
        cell.label:SetPoint("LEFT", 22, 0)
        cell.label:SetWidth(140)
        local hl = cell:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local function drop()
            local kind, itemID = GetCursorInfo()
            if kind ~= "item" or not itemID then return false end
            if Fits(itemID, slot) then
                selected.slots[slot] = itemID
                AutoKind(selected)
            else
                Say(W.ItemName(itemID) .. " doesn't go in the " .. e[2]:lower() .. " slot.")
            end
            ClearCursor()
            Changed()
            return true
        end
        cell:SetScript("OnReceiveDrag", function() if selected then drop() end end)
        cell:SetScript("OnClick", function(_, button)
            if not selected then return end
            if drop() then return end
            if button == "RightButton" then
                selected.slots[slot] = nil
            else
                local cur = GetInventoryItemID("player", slot)
                if selected.slots[slot] == cur or not cur then
                    selected.slots[slot] = nil
                else
                    selected.slots[slot] = cur
                end
            end
            AutoKind(selected)
            Changed()
        end)
        cell:SetScript("OnEnter", function(self)
            local id = selected and selected.slots[slot]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if id then GameTooltip:SetItemByID(id) else GameTooltip:SetText(e[2] .. ": not in this set", 1, 1, 1) end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", GameTooltip_Hide)
        cell.slot, cell.slotName = slot, e[2]
        p.cells[i] = cell
    end

    p.toggle = W.Button(ed, "Put on", 90, 22, function()
        if selected then Toggle(selected) end
    end)
    p.toggle:SetPoint("TOPLEFT", 0, -318)

    p.delete = W.Button(ed, "Delete", 90, 22, function()
        if not selected then return end
        if deleteArmed ~= selected then
            deleteArmed = selected
            refresh()
            return
        end
        DeleteSet(selected)
        selected, deleteArmed = nil, nil
        Changed()
    end)
    p.delete:SetPoint("LEFT", p.toggle, "RIGHT", 4, 0)

    p.info = W.Text(ed, 12)
    p.info:SetPoint("TOPLEFT", 0, -350)
    p.info:SetWidth(340)
    p.info:SetWordWrap(true)
    p.info:SetJustifyV("TOP")

    p.status = W.Text(p, 11, 0.55, 0.55, 0.55)
    p.status:SetPoint("BOTTOMLEFT", 0, 0)
    p.status:SetWidth(520)

    p.empty = W.Text(ed, 12, 0.55, 0.55, 0.55)
    p.empty:SetPoint("TOPLEFT", 0, 0)
    p.empty:SetWidth(340)
    p.empty:SetWordWrap(true)
    p.empty:SetText("Make a set with \"New set\". An on-use set is one item you press, like an AoE trinket: "
        .. "the bar puts it on, the same button uses it, and your old item goes back after combat.")
end

local function RefreshSets(p)
    if selected and not SetByID(selected.id) then selected = nil end
    if not selected then selected = charDB.sets[1] end

    local data = {}
    for _, s in ipairs(charDB.sets) do
        local set = s
        data[#data + 1] = {
            cols = { "|T" .. SetIcon(s) .. ":14|t " .. SetLabel(s) },
            mark = (s == selected),
            onClick = function()
                selected, deleteArmed = set, nil
                CF.RefreshCurrent()
            end,
        }
    end
    p.listData = data
    p.list:SetData(data, "No sets yet.")

    local has = selected ~= nil
    for _, child in ipairs({ p.name, p.kind, p.restore, p.toggle, p.delete, p.info }) do child:SetShown(has) end
    for _, cell in ipairs(p.cells) do cell:SetShown(has) end
    p.empty:SetShown(not has)
    if has then
        if not p.name:HasFocus() and p.name:GetText() ~= selected.name then p.name:SetText(selected.name) end
        p.kind.Refresh()
        p.restore.Refresh()
        for _, cell in ipairs(p.cells) do
            local id = selected.slots[cell.slot]
            if id then
                cell.icon:SetTexture(ItemIcon(id))
                cell.icon:Show()
                cell.label:SetText(W.ItemName(id))
            else
                cell.icon:Hide()
                cell.label:SetText(C(GREY, cell.slotName))
            end
        end
        local worn = IsWorn(selected)
        p.toggle.text:SetText((worn or IsActive(selected)) and "Take off" or "Put on")
        p.delete.text:SetText(deleteArmed == selected and C(RED, "Click to confirm") or "Delete")
        p.delete:SetWidth(deleteArmed == selected and 120 or 90)

        local lines = {}
        if selected.kind == "onuse" then
            local item, slot = UseItem(selected)
            if item then
                local start, duration = Cooldown(item)
                local left = (start > 0 and duration > 0) and (start + duration - GetTime()) or 0
                lines[#lines + 1] = "Use: " .. W.ItemName(item) .. C(GREY, " (" .. SLOT_NAME[slot]:lower() .. ")")
                    .. (left > 0 and C(YELLOW, ("  ready in %d:%02d"):format(left / 60, left % 60)) or C(GREEN, "  ready"))
            else
                lines[#lines + 1] = C(YELLOW, "No item with a \"Use:\" effect in this set yet.")
            end
        end
        if selected.kind == "slayer" then
            lines[#lines + 1] = selected.mob and ("Slayer set for " .. selected.mob .. C(GREY, " (rebuild it on the Slayer tab)"))
                or C(YELLOW, "Not tied to a mob type: build slayer sets on the Slayer tab.")
        end
        lines[#lines + 1] = C(GREY, ("%d slot%s · comes off %s"):format(CountSlots(selected),
            CountSlots(selected) == 1 and "" or "s", RESTORE_TEXT[selected.restore] or "manually"))
        p.info:SetText(table.concat(lines, "\n"))
    end

    local why = Swapping() and BlockedBy()
    local reasons = { combat = "after combat", casting = "after your cast", cursor = "once your cursor is empty", dead = "once you're alive" }
    p.status:SetText(why and C(YELLOW, "Gear change waiting: goes through " .. reasons[why] .. ".")
        or (status ~= "" and status or ""))
end

---------------------------------------------------------------------------
-- Options page
---------------------------------------------------------------------------
local function BuildOptions(p)
    local function changed() Changed() end
    W.Header(p, "Bar"):SetPoint("TOPLEFT", 0, 0)
    p.items = {
        W.Check(p, "Show the gear bar", function() return db.bar.show end,
            function(v) db.bar.show = v end, "Showing or hiding the bar waits until combat ends.", changed),
        W.Check(p, "Lock the bar", function() return db.bar.locked end,
            function(v) db.bar.locked = v end, "Unlocked, Shift-drag a button to move the bar.", changed),
    }
    p.dir = W.Choice(p, "Menus open", { { true, "Up" }, { false, "Down" } },
        function() return db.bar.up end, function(v) db.bar.up = v end, changed)

    p.alerts = {
        W.Check(p, "Chat message", function() return db.alertChat end, function(v) db.alertChat = v end, nil, changed),
        W.Check(p, "Sound", function() return db.alertSound end, function(v) db.alertSound = v end, nil, changed),
        W.Check(p, "On-screen message", function() return db.alertScreen end, function(v) db.alertScreen = v end, nil, changed),
        W.Check(p, "Only in dungeons and raids", function() return db.alertInstanceOnly end,
            function(v) db.alertInstanceOnly = v end, nil, changed),
    }

    p.items[1]:SetPoint("TOPLEFT", 0, -24)
    p.items[2]:SetPoint("TOPLEFT", 0, -48)
    p.dir:SetPoint("TOPLEFT", 0, -76)
    local h2 = W.Header(p, "Ready alerts for on-use items")
    h2:SetPoint("TOPLEFT", 0, -120)
    for i, w in ipairs(p.alerts) do w:SetPoint("TOPLEFT", 0, -144 - (i - 1) * 24) end

    local note = W.Text(p, 11, 0.55, 0.55, 0.55)
    note:SetPoint("TOPLEFT", 0, -250)
    note:SetWidth(520)
    note:SetWordWrap(true)
    note:SetText("Bar: hover a button to pick a set. On-use button: click to put the set on, click again to use it "
        .. "(works in combat), Shift-click to take it off. A freshly equipped trinket can't be used for about 30 seconds; "
        .. "the button shows that countdown.\n\nKeybind: Options > Keybindings > AddOns > ConvrgeForever > "
        .. "\"Gear: put on / use on-use set\".\n\nGear can't change in combat. A swap you ask for in combat goes through "
        .. "when combat ends.")
end

local function RefreshOptions(p)
    for _, w in ipairs(p.items) do w.Refresh() end
    for _, w in ipairs(p.alerts) do w.Refresh() end
    p.dir.Refresh()
end

M.pages = {
    { key = "sets", label = "Sets", build = BuildSets, refresh = RefreshSets, live = true },
    { key = "options", label = "Options", build = BuildOptions, refresh = RefreshOptions },
}
