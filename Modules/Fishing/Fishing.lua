-- Fishing module (formerly the FishFriend addon).
--   * Double right-click to cast (applies your best lure first if the pole has none)
--   * Keybind / slash command to swap between fishing pole and your weapons
--   * Small info line: zone, skill needed, your effective skill, lure timer
--   * /ff where  - zones you can fish without getaways at your skill
--   * /ff spots  - your own catch log per subzone (best spots, learned over time)

local _, CF = ...

local M = CF:NewModule("fishing", {
    title = "Fishing",
    description = "Double-click casting, auto-lures, pole and gear swap, zone skill guide, catch log and session stats.",
    legacyAddon = "FishFriend",
    defaults = {
        doubleClick = true,
        autoLure    = true,
        lureMode    = "best",   -- "best" = strongest usable lure, "smart" = smallest lure that prevents getaways
        showInfo    = true,
        swapGear    = true,     -- also swap hat/boots/gloves etc. that have a Fishing bonus
        showSessionOnInfo = true,
        spots       = {},
        learned     = {},
    },
    charDefaults = {},
})

local db, charDB   -- set in M:OnLogin
local FISHING_POLE_SUBCLASS = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20
local WEAPON_CLASS = (Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local MAINHAND, OFFHAND = 16, 17

local function Print(msg) CF.Print(msg, "Fishing") end

---------------------------------------------------------------------------
-- Basic queries
---------------------------------------------------------------------------
local function IsPole(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    return classID == WEAPON_CLASS and subclassID == FISHING_POLE_SUBCLASS
end

local function PoleEquipped()
    return IsPole(GetInventoryItemID("player", MAINHAND))
end

-- returns active (bool), msLeft
local function LureActive()
    local has, ms = GetWeaponEnchantInfo()
    return (has and PoleEquipped()) and true or false, ms
end

-- returns base rank, modifier (pole + lure + gear), name   (nil if Fishing not learned)
local function GetFishingSkill()
    local _, _, _, fishing = GetProfessions()
    if not fishing then return nil end
    local name, _, rank, maxRank, _, _, _, mod = GetProfessionInfo(fishing)
    return rank or 0, mod or 0, name, maxRank
end

local function FishingSpellName()
    local _, _, name = GetFishingSkill()
    return name or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(7620)) or "Fishing"
end

local function BagIDs()
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    local t = {}
    for i = 0, last do t[#t + 1] = i end
    return t
end

-- Calls fn(itemID, count, bag, slot, info) for every stack in your bags
local function ForEachBagItem(fn)
    for _, bag in ipairs(BagIDs()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then fn(info.itemID, info.stackCount or 1, bag, slot, info) end
        end
    end
end

---------------------------------------------------------------------------
-- Zone data
---------------------------------------------------------------------------
-- Returns dataName, data, zoneName, subzoneName
local function CurrentZone()
    local zone = GetRealZoneText() or GetZoneText() or ""
    local sub = GetSubZoneText() or ""
    if sub ~= "" and CF.FISH_ZONES[sub] then return sub, CF.FISH_ZONES[sub], zone, sub end
    return zone, CF.FISH_ZONES[zone], zone, sub
end

-- Skill needed for no getaways: table value, raised if you've personally
-- seen a fish escape at or above it.
local function SkillNeeded(dataName, data)
    local need = data and data.skill
    local learned = db.learned[dataName]
    if learned and (not need or learned >= need) then need = learned + 1 end
    return need
end

local function SpotKey(zone, sub)
    return (sub ~= "" and sub ~= zone) and (zone .. " - " .. sub) or zone
end

---------------------------------------------------------------------------
-- Lures and poles
---------------------------------------------------------------------------
-- Returns list of { id, name, bonus, req, count } for usable lures in bags
local function UsableLures()
    local rank = GetFishingSkill() or 0
    local found = {}
    ForEachBagItem(function(id, count)
        local name = C_Item.GetItemNameByID(id)
        local data = name and CF.FISH_LURES[name]
        if data and data.req <= rank then
            if found[id] then
                found[id].count = found[id].count + count
            else
                found[id] = { id = id, name = name, bonus = data.bonus, req = data.req, count = count }
            end
        end
    end)
    local list = {}
    for _, l in pairs(found) do list[#list + 1] = l end
    table.sort(list, function(a, b) return a.bonus > b.bonus end)
    return list
end

local function ChooseLure()
    local lures = UsableLures()
    if #lures == 0 then return nil end
    if db.lureMode ~= "smart" then return lures[1] end

    local rank, mod = GetFishingSkill()
    local dataName, data = CurrentZone()
    local need = SkillNeeded(dataName, data)
    if not need or not rank then return lures[1] end
    local deficit = need - (rank + mod)
    if deficit <= 0 then return nil end
    for i = #lures, 1, -1 do            -- smallest first
        if lures[i].bonus >= deficit then return lures[i] end
    end
    return lures[1]                      -- nothing is enough: use the strongest
end

local function BestPoleInBags()
    local best, bestBonus
    ForEachBagItem(function(id)
        if IsPole(id) then
            local bonus = CF.FISH_POLES[id] or 0
            if not best or bonus > bestBonus then best, bestBonus = id, bonus end
        end
    end)
    return best
end

---------------------------------------------------------------------------
-- Secure cast button (double-click and optional keybind)
---------------------------------------------------------------------------
local castBtn = CreateFrame("Button", "ConvrgeFishCastButton", UIParent, "SecureActionButtonTemplate")
castBtn:SetSize(1, 1)
castBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
castBtn:EnableMouse(false)
castBtn:RegisterForClicks("AnyUp", "AnyDown")
castBtn:SetAttribute("type", "macro")
castBtn:SetAttribute("macrotext", "/cast Fishing")

local lastLureMsg = 0
local function BuildCastMacro()
    if db.autoLure and PoleEquipped() and not LureActive() then
        local lure = ChooseLure()
        if lure then
            if GetTime() - lastLureMsg > 2 then
                lastLureMsg = GetTime()
                Print("applying " .. lure.name .. " (+" .. lure.bonus .. ", " .. (lure.count - 1) .. " left)")
            end
            return "/use item:" .. lure.id .. "\n/use " .. MAINHAND
        end
    end
    return "/cast " .. FishingSpellName()
end

castBtn:SetScript("PreClick", function(self)
    if db and not InCombatLockdown() then self:SetAttribute("macrotext", BuildCastMacro()) end
end)

-- Double-click: after a quick right-click on the world, BUTTON2 is bound to the
-- cast button for a short window, so a second right-click casts.
local DOUBLE_CLICK_WINDOW = 0.4
local bindOwner = CreateFrame("Frame")
local bindingArmed, armToken = false, 0
local rightDownAt, rightDownOK = 0, false
local lastCastAt = 0

local function Disarm()
    if bindingArmed and not InCombatLockdown() then
        ClearOverrideBindings(bindOwner)
        bindingArmed = false
    end
end

castBtn:SetScript("PostClick", function(_, _, down)
    -- Clear once the click has actually fired (down or up depending on the CVar).
    if down == GetCVarBool("ActionButtonUseKeyDown") then
        lastCastAt = GetTime()
        Disarm()
    end
end)

local function HookDoubleClick()
WorldFrame:HookScript("OnMouseDown", function(_, button)
    if button ~= "RightButton" then return end
    rightDownAt = GetTime()
    rightDownOK = db.doubleClick and not InCombatLockdown() and PoleEquipped()
        and not IsMounted() and not UnitExists("mouseover")
end)

WorldFrame:HookScript("OnMouseUp", function(_, button)
    if button ~= "RightButton" or not rightDownOK then return end
    rightDownOK = false
    if GetTime() - rightDownAt > 0.3 then return end   -- was a camera drag, not a click
    if GetTime() - lastCastAt < 0.5 then return end     -- this click was the cast itself
    if InCombatLockdown() then return end
    castBtn:SetAttribute("macrotext", BuildCastMacro())
    SetOverrideBindingClick(bindOwner, true, "BUTTON2", "ConvrgeFishCastButton")
    bindingArmed = true
    armToken = armToken + 1
    local token = armToken
    C_Timer.After(DOUBLE_CLICK_WINDOW, function()
        if token == armToken then Disarm() end
    end)
end)
end

---------------------------------------------------------------------------
-- Pole / weapon swap
---------------------------------------------------------------------------
local swapBtn = CreateFrame("Button", "ConvrgeFishSwapButton", UIParent, "SecureActionButtonTemplate")
swapBtn:SetSize(1, 1)
swapBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
swapBtn:EnableMouse(false)
swapBtn:RegisterForClicks("AnyUp", "AnyDown")
swapBtn:SetAttribute("type", "macro")

local function SnapshotWeapons()
    local mh = GetInventoryItemID("player", MAINHAND)
    if mh and not IsPole(mh) then
        charDB.mh = mh
        charDB.oh = GetInventoryItemID("player", OFFHAND)
    end
end

---------------------------------------------------------------------------
-- Fishing gear (hat, boots, enchanted gloves, ...), found by reading tooltips
---------------------------------------------------------------------------
local GEAR_SLOT_FOR = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
    INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10,
    INVTYPE_CLOAK = 15,
}
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 15 }

-- Fishing bonus on an item, from tooltip lines like "Increased Fishing +5" or a
-- "Fishing +2" glove enchant. Cached per item link (links include enchants).
local bonusCache = {}
local function FishingBonus(link, getTooltipData)
    if not link then return 0 end
    if bonusCache[link] then return bonusCache[link] end
    local data = getTooltipData()
    local lines = data and data.lines
    if not lines then return 0 end
    local total = 0
    for _, line in ipairs(lines) do
        local t = line.leftText
        if type(t) == "string" and not t:find("^Requires") then
            local n = t:match("Fishing[^%d]*(%d+)")
            if n then total = total + tonumber(n) end
        end
    end
    if #lines >= 2 then bonusCache[link] = total end  -- don't cache half-loaded tooltips
    return total
end

-- Returns { [slot] = { id, bonus } } with the best fishing item per slot
-- among what you're wearing and what's in your bags.
local function FindFishingGear()
    local best = {}
    local function consider(slot, id, bonus)
        if bonus > 0 and (not best[slot] or bonus > best[slot].bonus) then
            best[slot] = { id = id, bonus = bonus }
        end
    end
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            consider(slot, GetInventoryItemID("player", slot),
                FishingBonus(link, function() return C_TooltipInfo.GetInventoryItem("player", slot) end))
        end
    end
    ForEachBagItem(function(id, _, bag, bagSlot, bagInfo)
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(id)
        local slot = equipLoc and GEAR_SLOT_FOR[equipLoc]
        if slot and bagInfo.hyperlink then
            consider(slot, id,
                FishingBonus(bagInfo.hyperlink, function() return C_TooltipInfo.GetBagItem(bag, bagSlot) end))
        end
    end)
    return best
end

-- Fishing gear that isn't on yet: list of { slot, id }
local function GearToPutOn()
    local list = {}
    if not db.swapGear then return list end
    for slot, g in pairs(FindFishingGear()) do
        if GetInventoryItemID("player", slot) ~= g.id then
            list[#list + 1] = { slot = slot, id = g.id }
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Swap macros
---------------------------------------------------------------------------
-- Back to normal: weapons + whatever fishing gear replaced.
local function BuildBackMacro()
    local lines = {}
    if charDB.mh then
        lines[#lines + 1] = "/equipslot " .. MAINHAND .. " item:" .. charDB.mh
        if charDB.oh then lines[#lines + 1] = "/equipslot " .. OFFHAND .. " item:" .. charDB.oh end
    end
    for slot, id in pairs(charDB.gearSaved or {}) do
        lines[#lines + 1] = "/equipslot " .. slot .. " item:" .. id
    end
    return table.concat(lines, "\n")
end

-- To fishing: pole + fishing gear. With remember=true, records what the gear replaces.
local function BuildFishMacro(remember)
    local lines = {}
    local pole = BestPoleInBags()
    if pole then lines[1] = "/equip item:" .. pole end
    if remember then charDB.gearSaved = {} end
    for _, g in ipairs(GearToPutOn()) do
        lines[#lines + 1] = "/equipslot " .. g.slot .. " item:" .. g.id
        if remember then charDB.gearSaved[g.slot] = GetInventoryItemID("player", g.slot) end
    end
    return table.concat(lines, "\n")
end

local function UpdateSwapButton()
    if InCombatLockdown() then return end
    -- Only the "back" direction needs to be ready ahead of time (for combat);
    -- the "to fishing" direction is built fresh in PreClick.
    swapBtn:SetAttribute("macrotext", PoleEquipped() and BuildBackMacro() or "")
end

swapBtn:SetScript("PreClick", function(self)
    if not db or InCombatLockdown() then return end   -- in combat, the prepared macro (back to weapons) is used
    if PoleEquipped() then
        self:SetAttribute("macrotext", BuildBackMacro())
    else
        SnapshotWeapons()
        self:SetAttribute("macrotext", BuildFishMacro(true))
    end
end)

local function SwapNow()
    if InCombatLockdown() then
        Print("in combat: use the keybind (Options > Keybindings > AddOns) to swap.")
        return
    end
    local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if PoleEquipped() then
        if not charDB.mh then Print("no saved weapons yet; equip them once.") return end
        equip(charDB.mh, MAINHAND)
        if charDB.oh then equip(charDB.oh, OFFHAND) end
        for slot, id in pairs(charDB.gearSaved or {}) do equip(id, slot) end
    else
        local pole = BestPoleInBags()
        if not pole then Print("no fishing pole in your bags.") return end
        SnapshotWeapons()
        local gear = GearToPutOn()
        charDB.gearSaved = {}
        for _, g in ipairs(gear) do charDB.gearSaved[g.slot] = GetInventoryItemID("player", g.slot) end
        equip(pole, MAINHAND)
        for _, g in ipairs(gear) do equip(g.id, g.slot) end
    end
end

local SLOT_NAMES = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist",
    [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [15] = "Back" }

local function CmdGear(arg)
    if arg == "on" or arg == "off" then
        db.swapGear = (arg == "on")
        Print("fishing gear swap " .. arg)
        return
    end
    local gear = FindFishingGear()
    Print("fishing gear found (swap " .. (db.swapGear and "on" or "off") .. "):")
    local any = false
    for _, slot in ipairs(GEAR_SLOTS) do
        local g = gear[slot]
        if g then
            any = true
            local link = select(2, C_Item.GetItemInfo(g.id)) or ("item " .. g.id)
            print("   " .. SLOT_NAMES[slot] .. ": " .. link .. " |cff66ff66+" .. g.bonus .. "|r")
        end
    end
    if not any then print("   none: items need a Fishing bonus on their tooltip") end
end

---------------------------------------------------------------------------
-- Session stats (reset on each fresh login, kept through /reload)
---------------------------------------------------------------------------
local lastActionAt   -- GetTime() of the previous catch/getaway

local function NewSession()
    local rank = GetFishingSkill()
    charDB.session = { catches = 0, getaways = 0, fish = {}, active = 0,
        startRank = rank, lastRank = rank, gains = 0, catchesAtLastGain = 0 }
    lastActionAt = nil
end

local function Session()
    if not charDB.session then NewSession() end
    return charDB.session
end

-- Counts time spent fishing: gaps over 60s (travel, AFK) only count as 60s.
local function SessionTick(s)
    local now = GetTime()
    s.active = s.active + (lastActionAt and math.min(now - lastActionAt, 60) or 20)
    lastActionAt = now
end

local function SessionCatch(items)
    local s = Session()
    SessionTick(s)
    s.catches = s.catches + 1
    for id, n in pairs(items) do s.fish[id] = (s.fish[id] or 0) + n end
end

local function SessionGetaway()
    local s = Session()
    SessionTick(s)
    s.getaways = s.getaways + 1
end

local function SessionSkillCheck()
    local rank = GetFishingSkill()
    if not rank or not charDB then return end
    local s = Session()
    s.startRank = s.startRank or rank
    if s.lastRank and rank > s.lastRank then
        s.gains = s.gains + (rank - s.lastRank)
        s.catchesAtLastGain = s.catches
    end
    s.lastRank = rank
end

-- Returns a table of derived numbers for display
local function SessionNumbers()
    local s = Session()
    local rank, _, _, maxRank = GetFishingSkill()
    local n = {
        perHour = s.active > 0 and math.floor(s.catches / s.active * 3600 + 0.5) or 0,
        skill = (rank and s.startRank) and (rank - s.startRank) or 0,
        capped = rank and maxRank and rank >= maxRank,
    }
    if s.gains > 0 and not n.capped then
        n.perPoint = s.catchesAtLastGain / s.gains
        n.toNext = math.max(0, math.ceil(n.perPoint) - (s.catches - s.catchesAtLastGain))
    end
    return s, n
end

local function SessionLine()
    if not charDB then return nil end
    local s, n = SessionNumbers()
    if s.catches == 0 then return nil end
    local parts = { s.catches .. " fish", n.perHour .. "/hr" }
    if n.skill > 0 then parts[#parts + 1] = "|cff66ff66+" .. n.skill .. " skill|r" end
    if n.capped then
        parts[#parts + 1] = "|cffffd100skill capped|r"
    elseif n.perPoint then
        parts[#parts + 1] = ("~%.1f/pt, ~%d to go"):format(n.perPoint, n.toNext)
    end
    return "Session: " .. table.concat(parts, "  ·  ")
end

local function CmdSession(arg)
    if arg == "reset" then
        NewSession()
        Print("session reset.")
        return
    end
    local s, n = SessionNumbers()
    local total = s.catches + s.getaways
    local mins = math.floor(s.active / 60)
    Print(("session: %d catches, %d getaways (%d%%), ~%d min fishing, %d/hr"):format(
        s.catches, s.getaways, total > 0 and math.floor(s.getaways / total * 100 + 0.5) or 0, mins, n.perHour))
    local rank = GetFishingSkill()
    if rank and s.startRank then
        local line = ("   skill %d -> %d (+%d)"):format(s.startRank, rank, n.skill)
        if n.capped then
            line = line .. "  |cffffd100capped: train the next rank|r"
        elseif n.perPoint then
            line = line .. ("  ~%.1f catches per point, ~%d to next"):format(n.perPoint, n.toNext)
        end
        print(line)
    end
    local fish = {}
    for id, c in pairs(s.fish) do fish[#fish + 1] = { id = id, c = c } end
    table.sort(fish, function(a, b) return a.c > b.c end)
    for i = 1, math.min(5, #fish) do
        local link = select(2, C_Item.GetItemInfo(fish[i].id)) or ("item " .. fish[i].id)
        print("   " .. link .. " x" .. fish[i].c)
    end
end

---------------------------------------------------------------------------
-- Info line
---------------------------------------------------------------------------
local info = CreateFrame("Frame", "ConvrgeFishInfo", UIParent, "BackdropTemplate")
info:SetSize(260, 36)
info:SetPoint("TOP", UIParent, "TOP", 0, -140)
info:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
info:SetBackdropColor(0, 0, 0, 0.45)
info:SetMovable(true)
info:EnableMouse(true)
info:RegisterForDrag("LeftButton")
info:SetClampedToScreen(true)
info:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
info:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.infoPos = { p, rp, x, y }
end)
info:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and not IsShiftKeyDown() then CF.Open("fishing") end
end)
info:Hide()

local function ResetInfoPos()
    db.infoPos = nil
    info:ClearAllPoints()
    info:SetPoint("TOP", UIParent, "TOP", 0, -140)
end

local line1 = info:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
line1:SetPoint("TOP", 0, -5)
local line2 = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
line2:SetPoint("TOP", line1, "BOTTOM", 0, -3)
local line3 = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
line3:SetPoint("TOP", line2, "BOTTOM", 0, -3)

local function UpdateInfo()
    if not db or not db.showInfo or not PoleEquipped() then info:Hide() return end
    info:Show()

    local dataName, data = CurrentZone()
    local need = SkillNeeded(dataName, data)
    local rank, mod = GetFishingSkill()
    local eff = rank and (rank + mod)

    local lvl = data and data.lvl and ("  |cff999999(" .. data.lvl .. ")|r") or ""
    line1:SetText(dataName .. lvl .. "  ·  need " .. (need or "?"))

    local skillTxt
    if not rank then
        skillTxt = "|cffff6666Fishing not learned|r"
    else
        local color = (not need) and "ffffff" or (eff >= need and "66ff66" or "ff6666")
        skillTxt = ("Skill |cff%s%d|r"):format(color, eff) .. (mod ~= 0 and (" |cff999999(" .. rank .. "+" .. mod .. ")|r") or "")
    end

    local active, ms = LureActive()
    local lureTxt
    if active then
        local secs = math.floor((ms or 0) / 1000)
        lureTxt = ("Lure |cff66ff66%d:%02d|r"):format(math.floor(secs / 60), secs % 60)
    else
        local lures = UsableLures()
        lureTxt = (#lures > 0) and ("|cffffd100No lure|r (" .. lures[1].name .. " x" .. lures[1].count .. ")")
            or "|cff999999No lures|r"
    end
    line2:SetText(skillTxt .. "  ·  " .. lureTxt)

    local sess = db.showSessionOnInfo and SessionLine() or nil
    line3:SetText(sess or "")
    line3:SetShown(sess ~= nil)
    info:SetHeight(sess and 50 or 36)
    info:SetWidth(math.max(line1:GetStringWidth(), line2:GetStringWidth(),
        sess and line3:GetStringWidth() or 0) + 20)
end

local elapsed = 0
info:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed > 1 then elapsed = 0; UpdateInfo() end
end)

---------------------------------------------------------------------------
-- Catch log
---------------------------------------------------------------------------
local function Spot()
    local _, _, zone, sub = CurrentZone()
    local key = SpotKey(zone, sub)
    local s = db.spots[key]
    if not s then
        s = { zone = zone, catches = 0, getaways = 0, items = {} }
        db.spots[key] = s
    end
    return s
end

local function OnFishingLoot()
    local s = Spot()
    s.catches = s.catches + 1
    local caught = {}
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local _, _, qty = GetLootSlotInfo(i)
            s.items[id] = (s.items[id] or 0) + (qty or 1)
            caught[id] = (caught[id] or 0) + (qty or 1)
        end
    end
    SessionCatch(caught)
end

local function OnFishEscaped()
    local s = Spot()
    s.getaways = s.getaways + 1
    SessionGetaway()
    local rank, mod = GetFishingSkill()
    if rank then
        local dataName = CurrentZone()
        local eff = rank + mod
        if not db.learned[dataName] or eff > db.learned[dataName] then
            db.learned[dataName] = eff
        end
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function ZoneLine(name, d)
    local tag = d.dungeon and " |cffa335ee[dungeon]|r" or ""
    return name .. " |cff999999(" .. (d.lvl or "?") .. ")|r" .. tag
end

local function CmdWhere()
    local rank, mod = GetFishingSkill()
    if not rank then Print("you haven't learned Fishing.") return end
    local eff = rank + mod
    local lures = UsableLures()
    local active = LureActive()
    local withLure = eff + ((not active and lures[1]) and lures[1].bonus or 0)
    local faction = UnitFactionGroup("player")

    local now, lure = {}, {}
    local bestNow = 0
    for name, d in pairs(CF.FISH_ZONES) do
        if not d.faction or d.faction == faction then
            local need = SkillNeeded(name, d)
            if need <= eff then
                if need > bestNow then bestNow = need end
                now[#now + 1] = { name = name, d = d, need = need }
            elseif need <= withLure then
                lure[#lure + 1] = { name = name, d = d, need = need }
            end
        end
    end
    local function sorted(t) table.sort(t, function(a, b) return a.name < b.name end) return t end

    Print(("effective skill %d (base %d). Catches give the same skill-ups anywhere without getaways."):format(eff, rank))
    if bestNow > 0 then
        print("|cff66ff66No getaways (best zones, need " .. bestNow .. "):|r")
        for _, z in ipairs(sorted(now)) do
            if z.need == bestNow then print("   " .. ZoneLine(z.name, z.d)) end
        end
    end
    if #lure > 0 then
        print("|cffffd100With your " .. lures[1].name .. ":|r")
        for _, z in ipairs(sorted(lure)) do print("   " .. ZoneLine(z.name, z.d) .. " need " .. z.need) end
    end
end

local function CmdSpots(zoneFilter)
    local _, _, zone = CurrentZone()
    zoneFilter = (zoneFilter ~= "" and zoneFilter) or zone
    local list = {}
    for key, s in pairs(db.spots) do
        if s.zone:lower() == zoneFilter:lower() then list[#list + 1] = { key = key, s = s } end
    end
    if #list == 0 then Print("no catches logged in " .. zoneFilter .. " yet.") return end
    table.sort(list, function(a, b) return a.s.catches > b.s.catches end)
    Print("your spots in " .. zoneFilter .. ":")
    for _, e in ipairs(list) do
        local s = e.s
        local total = s.catches + s.getaways
        local pct = total > 0 and math.floor(s.getaways / total * 100 + 0.5) or 0
        local items = {}
        for id, n in pairs(s.items) do items[#items + 1] = { id = id, n = n } end
        table.sort(items, function(a, b) return a.n > b.n end)
        local top = {}
        for i = 1, math.min(3, #items) do
            top[#top + 1] = (C_Item.GetItemNameByID(items[i].id) or ("item " .. items[i].id)) .. " x" .. items[i].n
        end
        print(("   %s: %d catches, %d%% getaways  |cff999999%s|r"):format(e.key, s.catches, pct, table.concat(top, ", ")))
    end
end

local function CmdZone()
    local dataName, data = CurrentZone()
    local need = SkillNeeded(dataName, data)
    Print(dataName .. ": " .. (need and ("need " .. need .. " for no getaways") or "no data for this zone"))
    if db.learned[dataName] then
        print("   you've had a fish escape here at effective skill " .. db.learned[dataName])
    end
    CmdSpots("")
end

local function OnOff(v, current)
    if v == "on" then return true elseif v == "off" then return false end
    return not current
end

function M:slash(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    if cmd == "where" then CmdWhere()
    elseif cmd == "zone" then CmdZone()
    elseif cmd == "spots" then CmdSpots(rest)
    elseif cmd == "swap" then SwapNow()
    elseif cmd == "gear" then CmdGear(rest:lower())
    elseif cmd == "session" then CmdSession(rest:lower())
    elseif cmd == "lure" then
        local v = rest:lower()
        if v == "best" or v == "smart" then db.lureMode = v; db.autoLure = true
        elseif v == "off" then db.autoLure = false
        elseif v == "on" then db.autoLure = true end
        Print("auto-lure " .. (db.autoLure and ("on, mode: " .. db.lureMode) or "off"))
    elseif cmd == "dbl" then
        db.doubleClick = OnOff(rest:lower(), db.doubleClick)
        Print("double-click cast " .. (db.doubleClick and "on" or "off"))
    elseif cmd == "info" then
        if rest:lower() == "reset" then
            ResetInfoPos()
        else
            db.showInfo = OnOff(rest:lower(), db.showInfo)
        end
        UpdateInfo()
        Print("info line " .. (db.showInfo and "on (shift-drag to move)" or "off"))
    elseif cmd == "" then
        CF.Open("fishing")
    else
        Print("commands (/ff or /cf fishing; just /ff opens the window):")
        print("   /ff where  - best zones for your skill")
        print("   /ff zone  - current zone details + your spots")
        print("   /ff spots [zone]  - your catch log per subzone")
        print("   /ff swap  - swap pole + fishing gear <-> weapons + normal gear")
        print("   /ff gear [on|off]  - list detected fishing gear / toggle gear swap")
        print("   /ff session [reset]  - session stats")
        print("   /ff lure best|smart|off  - auto-lure (now: " .. (db.autoLure and db.lureMode or "off") .. ")")
        print("   /ff dbl on|off  - double right-click to cast (now: " .. (db.doubleClick and "on" or "off") .. ")")
        print("   /ff info on|off|reset  - info line")
    end
end

-- Keybinding labels (Options > Keybindings > AddOns > ConvrgeForever)
BINDING_HEADER_CONVRGEFOREVER = "ConvrgeForever"
_G["BINDING_NAME_CLICK ConvrgeFishSwapButton:LeftButton"] = "Fishing: swap pole / weapons"
_G["BINDING_NAME_CLICK ConvrgeFishCastButton:LeftButton"] = "Fishing: cast (applies lure if needed)"

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local snapToken = 0

-- Copies FishFriend's saved data the first time (FishFriend must be enabled for that login).
function M:Migrate()
    local old, oldChar = _G.FishFriendDB, _G.FishFriendCharDB
    if type(old) == "table" and not self.db.importedLegacy then
        for _, k in ipairs({ "doubleClick", "autoLure", "lureMode", "showInfo", "swapGear",
                             "showSessionOnInfo", "spots", "learned", "infoPos" }) do
            if old[k] ~= nil then self.db[k] = CF.DeepCopy(old[k]) end
        end
        if old.minimap then CF.db.general.minimap = CF.DeepCopy(old.minimap) end
        if old.accent then CF.db.general.accent = CF.DeepCopy(old.accent) end
        self.db.importedLegacy = true
        Print("imported your FishFriend settings and catch log.")
    end
    if type(oldChar) == "table" and not self.char.importedLegacy then
        for k, v in pairs(oldChar) do self.char[k] = CF.DeepCopy(v) end
        self.char.importedLegacy = true
    end
end

M.minimapRightClickText = "toggle fishing info bar"
function M:OnMinimapRightClick()
    db.showInfo = not db.showInfo
    UpdateInfo()
    CF.RefreshCurrent()
end

function M:OnLogin()
    db, charDB = self.db, self.char
    if db.infoPos then
        info:ClearAllPoints()
        info:SetPoint(db.infoPos[1], UIParent, db.infoPos[2], db.infoPos[3], db.infoPos[4])
    end

    HookDoubleClick()
    SnapshotWeapons()
    UpdateSwapButton()
    UpdateInfo()

    SLASH_CFFISH1 = "/ff"
    SlashCmdList.CFFISH = function(msg) M:slash(msg) end

    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ZONE_CHANGED",
        "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED", "LOOT_OPENED",
        "UI_ERROR_MESSAGE", "UI_INFO_MESSAGE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        ev:RegisterEvent(e)
    end
end

ev:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Remember your real weapons once the swap settles.
        snapToken = snapToken + 1
        local token = snapToken
        C_Timer.After(0.3, function()
            if token ~= snapToken then return end
            SnapshotWeapons()
            UpdateSwapButton()
            UpdateInfo()
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin = ...
        if isInitialLogin then NewSession() end
        SessionSkillCheck()

    elseif event == "BAG_UPDATE_DELAYED" then
        UpdateSwapButton()

    elseif event == "SKILL_LINES_CHANGED" then
        SessionSkillCheck()
        UpdateInfo()

    elseif event == "LOOT_OPENED" then
        if IsFishingLoot() then OnFishingLoot() end

    elseif event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" then
        local _, message = ...
        if message == ERR_FISH_ESCAPED then OnFishEscaped() end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Last chance before lockdown: drop any armed double-click binding.
        Disarm()

    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateSwapButton()

    else -- zone / skill changes
        UpdateInfo()
    end
end)

---------------------------------------------------------------------------
-- Shared with FishingUI.lua
---------------------------------------------------------------------------
M.Print           = Print
M.GetFishingSkill = GetFishingSkill
M.CurrentZone     = CurrentZone
M.SkillNeeded     = SkillNeeded
M.UsableLures     = UsableLures
M.LureActive      = LureActive
M.PoleEquipped    = PoleEquipped
M.BestPoleInBags  = BestPoleInBags
M.FindFishingGear = FindFishingGear
M.GEAR_SLOTS      = GEAR_SLOTS
M.SLOT_NAMES      = SLOT_NAMES
M.SessionNumbers  = SessionNumbers
M.NewSession      = NewSession
M.SwapNow         = SwapNow
M.UpdateInfo      = UpdateInfo
M.ResetInfoPos    = ResetInfoPos
