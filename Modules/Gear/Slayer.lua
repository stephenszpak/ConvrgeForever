-- Gear: slayer sets.
--
-- Reads every equippable item you have (bags, equipped, and through Stash your
-- bank, Warband bank and other characters) for bonus lines like
--   "Deals 2 times as much damage to Naga and Satyrs."
-- and groups them by mob type. The Slayer tab lists each type with the items
-- you have for it and builds a slayer set from them in one click.
--
-- Your target is recognized as a mob type by, in order: mobs you taught
-- (saved by mob ID for every character), the game's creature type (Undead,
-- Demon, Beast...), and the type's name in the mob's name ("Boulderfist Ogre").
-- When it matches a slayer set, the bar's Slayer button glows.
--
-- Tooltips are only read out of combat, a few items at a time, and cached in
-- ConvrgeForeverDB.gear.items. Taught mobs are in ConvrgeForeverDB.gear.mobs.

local _, CF = ...
local W = CF.W
local D = CF.GEAR
local M = CF.modules.gear
local C, GREEN, YELLOW, GREY = W.C, W.GREEN, W.YELLOW, W.GREY

local db
local GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
local IsEquippedItem = (C_Item and C_Item.IsEquippedItem) or _G.IsEquippedItem

local function Stash()
    local S = CF.modules.stash
    if S and S.running and S.Current and S.ForEachChar then return S end
end

---------------------------------------------------------------------------
-- Reading bonus lines
---------------------------------------------------------------------------
-- "Satyrs" -> "Satyr", "Harpies" -> "Harpy", "Blackrock Orcs" -> "Blackrock Orc"
local function Normalize(name)
    if D.FORMS[name] then return D.FORMS[name] end
    local last = name:match("(%S+)$") or name
    local prefix = name:sub(1, #name - #last)
    local one
    if D.FORMS[last] then
        one = D.FORMS[last]
    elseif last:match("ies$") then
        one = last:sub(1, -4) .. "y"
    elseif last:match("[^s]s$") then
        one = last:sub(1, -2)
    else
        one = last
    end
    return prefix .. one
end

-- "Naga, satyrs" -> "Naga, Satyrs" (for typed input)
local function Capitalize(s)
    return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b:lower() end))
end

-- Returns { [mob type] = multiplier } for one tooltip line, or nil.
local function ParseLine(text)
    local lower = text:lower()
    local bonus = false
    for _, w in ipairs(D.BONUS_WORDS) do
        if lower:find(w, 1, true) then bonus = true break end
    end
    if not bonus then return end

    local list
    for _, pat in ipairs(D.LIST_STARTS) do
        list = text:match(pat)
        if list then break end
    end
    if not list then return end
    local cut = #list + 1
    for _, e in ipairs(D.LIST_ENDS) do
        local i = list:find(e)
        if i and i < cut then cut = i end
    end
    list = list:sub(1, cut - 1)
    list = list:gsub(",? and ", ","):gsub(",? or ", ",")

    local mult = tonumber(lower:match("(%d+) times"))
    if not mult then
        for word, n in pairs(D.MULTIPLIERS) do
            if lower:find(word, 1, true) then mult = n break end
        end
    end

    local found
    for raw in list:gmatch("[^,]+") do
        local part = strtrim(raw)
        local first = part:match("^(%S+)")
        local words = select(2, part:gsub("%S+", ""))
        if first and part:match("^%u[%a%-' ]*$") and not D.NOT_TYPES[first] and words <= 3 then
            found = found or {}
            found[Normalize(part)] = mult or 1
        end
    end
    return found
end
M.ParseLine = ParseLine   -- for /dump testing: ConvrgeForever.modules.gear.ParseLine("...")

---------------------------------------------------------------------------
-- Scanning items (out of combat, a few per tick)
---------------------------------------------------------------------------
local queue, queued, tries, fresh = {}, {}, {}, {}
local initialDone = false
local index, indexDirty = nil, true

local function Equippable(id)
    local _, _, _, loc = C_Item.GetItemInfoInstant(id)
    return loc and M.FITS[loc] ~= nil
end

local function NeedsScan(id)
    local c = db.items[id]
    return not c or c.v ~= D.SCAN_VERSION
end

local function Queue(id, maybeNew)
    if not id or queued[id] or not NeedsScan(id) or not Equippable(id) then return end
    if maybeNew and initialDone and db.items[id] == nil then fresh[id] = true end
    queued[id] = true
    queue[#queue + 1] = id
end

local function TypesText(slayer)
    local t = {}
    for mob in pairs(slayer) do t[#t + 1] = mob end
    table.sort(t)
    return table.concat(t, ", ")
end

-- Reads one item. False means its data isn't loaded yet: try again later.
local function ScanOne(id)
    if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(id) then
        C_Item.RequestLoadItemDataByID(id)
        return false
    end
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID(id)
    if not data or not data.lines or #data.lines < 2 then return false end
    local slayer
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and text ~= "" then
            local found = ParseLine(text)
            if found then
                slayer = slayer or {}
                for mob, mult in pairs(found) do slayer[mob] = math.max(slayer[mob] or 0, mult) end
            end
        end
    end
    db.items[id] = { v = D.SCAN_VERSION, slayer = slayer }
    if slayer then
        indexDirty = true
        if fresh[id] and db.slayerLootAlert then
            CF.Print("new slayer item: " .. W.ItemName(id) .. C(GREY, " (" .. TypesText(slayer) .. ")"), "Gear")
        end
    end
    return true
end

local function Work()
    if InCombatLockdown() or #queue == 0 then return end
    for _ = 1, 15 do
        local id = table.remove(queue, 1)
        if not id then break end
        if ScanOne(id) then
            queued[id], fresh[id], tries[id] = nil, nil, nil
        else
            tries[id] = (tries[id] or 0) + 1
            if tries[id] < 20 then queue[#queue + 1] = id else queued[id], fresh[id] = nil, nil end
        end
    end
    if #queue == 0 and indexDirty then M.Changed() end
end

local function GatherBags(maybeNew)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then Queue(info.itemID, maybeNew) end
        end
    end
    for slot = 1, 19 do Queue(GetInventoryItemID("player", slot)) end
end

local function GatherStash()
    local S = Stash()
    if not S then return end
    S.ForEachChar(function(_, _, _, d)
        for _, k in ipairs({ "bags", "bank", "equipped" }) do
            for id in pairs(d[k] or {}) do Queue(id) end
        end
    end)
    for id in pairs(S.Warband() or {}) do Queue(id) end
end

-- [mob type] = { { id, mult }, ... }, biggest bonus first
local function Index()
    if index and not indexDirty then return index end
    index = {}
    for id, c in pairs(db.items) do
        if c.slayer then
            for mob, mult in pairs(c.slayer) do
                index[mob] = index[mob] or {}
                table.insert(index[mob], { id = id, mult = mult })
            end
        end
    end
    for _, list in pairs(index) do
        table.sort(list, function(a, b)
            if a.mult ~= b.mult then return a.mult > b.mult end
            return a.id < b.id
        end)
    end
    indexDirty = false
    return index
end

---------------------------------------------------------------------------
-- Where an item is
---------------------------------------------------------------------------
-- Returns kind ("here", "bank", "warband", "alt" or nil) and a label.
local function Locate(id)
    if (GetItemCount(id) or 0) > 0 then
        return "here", (IsEquippedItem and IsEquippedItem(id)) and "equipped" or "bags"
    end
    local S = Stash()
    if not S then
        if (GetItemCount(id, true) or 0) > 0 then return "bank", "bank" end
        return nil, "not seen"
    end
    local d = S.Current()
    if (d and d.bank and (d.bank[id] or 0) > 0) or (GetItemCount(id, true) or 0) > 0 then return "bank", "bank" end
    local wb = S.Warband()
    if wb and (wb[id] or 0) > 0 then return "warband", "Warband bank" end
    local who
    S.ForEachChar(function(name, realm, faction, data)
        if who or data == d then return end
        for _, k in ipairs({ "bags", "bank", "equipped" }) do
            if data[k] and (data[k][id] or 0) > 0 then
                who = S.CharLabel(name, realm, faction, data.class)
                return
            end
        end
    end)
    if who then return "alt", who end
    return nil, "not seen"
end

---------------------------------------------------------------------------
-- Building slayer sets
---------------------------------------------------------------------------
local function SlayerSetFor(mob)
    for _, s in ipairs(M.SetsOf("slayer")) do
        if s.mob == mob then return s end
    end
end
M.SlayerSetFor = SlayerSetFor

-- Puts the best item per slot into the mob's slayer set (made if needed).
-- Only items on this character (bags, equipped, bank) go in.
local function BuildSet(mob)
    local slots, twoHand, n = {}, false, 0
    local left = {}
    for _, e in ipairs(Index()[mob] or {}) do
        local where = Locate(e.id)
        if where == "here" or where == "bank" then
            local _, _, _, loc = C_Item.GetItemInfoInstant(e.id)
            local placed = false
            for _, slot in ipairs(M.FITS[loc] or {}) do
                local blocked = (slot == 17 and twoHand) or (loc == "INVTYPE_2HWEAPON" and slots[17])
                if not slots[slot] and not blocked then
                    slots[slot] = e.id
                    if loc == "INVTYPE_2HWEAPON" then twoHand = true end
                    placed, n = true, n + 1
                    break
                end
            end
            if not placed then left[#left + 1] = W.ItemName(e.id) end
        end
    end
    if n == 0 then
        M.Say("no " .. mob .. " items on this character.")
        return
    end
    local s = SlayerSetFor(mob)
    if not s then
        s = M.NewSet()
        s.kind, s.kindAuto, s.restore, s.mob, s.name = "slayer", false, "manual", mob, mob .. " slayer"
    end
    s.slots = slots
    M.Say(("%s: %d slot%s."):format(s.name, n, n == 1 and "" or "s")
        .. (#left > 0 and (" Left out, slot already taken: " .. table.concat(left, ", ") .. ".") or ""))
    M.Changed()
    return s
end

---------------------------------------------------------------------------
-- Recognizing your target
---------------------------------------------------------------------------
local targetTypes = {}     -- [mob type] = "taught" | "type" | "name"
local formsCache = {}

-- The game can hand addons "secret" unit values (GUID, name...) that can't be
-- read or compared. Treat those as unknown: the step that needs them is skipped.
local IsSecret = issecretvalue or function() return false end
local function Plain(v)
    if v ~= nil and IsSecret(v) then return nil end
    return v
end

-- Calls a unit API and returns its first result, or nil plus true if secret.
local function Ask(fn, ...)
    if not fn then return nil end
    local v = fn(...)
    if v ~= nil and IsSecret(v) then return nil, true end
    return v
end

local function TargetName()
    return Plain(UnitName("target"))
end

local function NpcID(unit)
    local guid = Ask(UnitGUID, unit)
    if type(guid) ~= "string" then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- Every type we could match by name: ones with items, plus the shipped list.
local function KnownTypes()
    local t = {}
    for mob in pairs(Index()) do t[mob] = true end
    for _, mob in ipairs(D.COMMON_TYPES) do t[mob] = true end
    for _, mob in ipairs(D.CREATURE_TYPES) do t[mob] = true end
    return t
end

-- Lowercase words that name a type in a mob's name: "ogre", "ogres", ...
local function FormsOf(mob)
    if formsCache[mob] then return formsCache[mob] end
    local f = { mob:lower(), mob:lower() .. "s" }
    if mob:match("y$") then f[#f + 1] = mob:lower():sub(1, -2) .. "ies" end
    for form, to in pairs(D.FORMS) do
        if to == mob then f[#f + 1] = form:lower() end
    end
    formsCache[mob] = f
    return f
end

local function Recognize(unit)
    local found = {}
    local exists, s1 = Ask(UnitExists, unit)
    local isPlayer, s2 = Ask(UnitIsPlayer, unit)
    local dead, s3 = Ask(UnitIsDead, unit)
    local attackable, s4 = Ask(UnitCanAttack, "player", unit)
    if s1 or s2 or s3 or s4 then return found end   -- can't tell what it is
    if not exists or isPlayer or dead or not attackable then return found end
    local npc = NpcID(unit)
    local rawName = Ask(UnitName, unit)
    local nameKey = type(rawName) == "string" and ("name:" .. rawName:lower()) or nil
    local taught = (npc and (db.mobs[npc] or D.KNOWN_MOBS[npc])) or (nameKey and db.mobs[nameKey])
    if taught then found[taught] = "taught" end
    local ct = Ask(UnitCreatureType, unit)
    if type(ct) == "string" and ct ~= "" then
        local mob = Normalize(ct)
        found[mob] = found[mob] or "type"
    end
    if not taught and type(rawName) == "string" then
        local name = " " .. rawName:lower() .. " "
        for mob in pairs(KnownTypes()) do
            if not found[mob] then
                for _, form in ipairs(FormsOf(mob)) do
                    if name:find("[^%a]" .. form .. "[^%a]") then found[mob] = "name" break end
                end
            end
        end
        for mob, hints in pairs(D.NAME_HINTS) do
            if not found[mob] then
                for _, hint in ipairs(hints) do
                    if name:find("[^%a]" .. hint .. "[^%a]") then found[mob] = "name" break end
                end
            end
        end
    end
    return found
end

local function RecheckTarget()
    targetTypes = Recognize("target")
    if M.OnTargetTypes then M.OnTargetTypes() end
    if M.RefreshBar then M.RefreshBar() end
    CF.RefreshCurrent()
end

function M.TargetTypes() return targetTypes end

-- True while your (living) target still matches this slayer set.
function M.TargetWants(s)
    if not s or s.kind ~= "slayer" or not s.mob then return false end
    targetTypes = Recognize("target")
    return targetTypes[s.mob] ~= nil
end

-- The slayer set for your target, if you have one: taught first, then the
-- creature type, then a name match.
function M.TargetSlayerSet()
    for _, how in ipairs({ "taught", "type", "name" }) do
        for mob, h in pairs(targetTypes) do
            if h == how then
                local s = SlayerSetFor(mob)
                if s and next(s.slots) then return s, mob end
            end
        end
    end
end

-- Remembers your target as a mob type, or forgets it with nil.
function M.Teach(mob)
    -- Saved by mob ID; when the game won't tell addons the ID, by the mob's name.
    local name = TargetName()
    local key = NpcID("target") or (name and ("name:" .. name:lower()))
    if not key then M.Say("target a mob first (some targets can't be read by addons, e.g. in combat).") return end
    name = name or "your target"
    if not mob or mob == "" then
        db.mobs[key] = nil
        if name ~= "your target" then db.mobs["name:" .. name:lower()] = nil end
        M.Say("forgot what " .. name .. " is.")
    else
        mob = Normalize(Capitalize(mob))
        db.mobs[key] = mob
        M.Say(name .. " is a " .. mob .. " from now on.")
    end
    RecheckTarget()
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
function M.InitSlayer()
    db = M.db
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_OPENED",
        "PLAYER_TARGET_CHANGED", "UNIT_CLASSIFICATION_CHANGED" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "BAG_UPDATE_DELAYED" then
            GatherBags(true)
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            GatherBags()
        elseif event == "BANKFRAME_OPENED" then
            C_Timer.After(2, GatherStash)    -- after Stash has read the bank
        elseif event == "PLAYER_TARGET_CHANGED" then
            RecheckTarget()
        elseif event == "UNIT_CLASSIFICATION_CHANGED" and unit == "target" then
            RecheckTarget()
        end
    end)
    C_Timer.After(3, function()
        GatherBags()
        GatherStash()
        initialDone = true
    end)
    C_Timer.NewTicker(0.25, Work)
end

---------------------------------------------------------------------------
-- Slayer page
---------------------------------------------------------------------------
local selType

local function Summary(list)
    local here, bank, other = 0, 0, 0
    for _, e in ipairs(list or {}) do
        local where = Locate(e.id)
        if where == "here" then here = here + 1
        elseif where == "bank" then bank = bank + 1
        else other = other + 1 end
    end
    local parts = {}
    if here > 0 then parts[#parts + 1] = C(GREEN, here .. " here") end
    if bank > 0 then parts[#parts + 1] = bank .. " in bank" end
    if other > 0 then parts[#parts + 1] = C(GREY, other .. " elsewhere") end
    return #parts > 0 and table.concat(parts, C(GREY, " · ")) or C(GREY, "none yet")
end

local function TypeRows()
    local idx = Index()
    local seen, types = {}, {}
    local function add(mob)
        if not seen[mob] then seen[mob] = true; types[#types + 1] = mob end
    end
    for mob in pairs(idx) do add(mob) end
    for _, mob in ipairs(D.COMMON_TYPES) do add(mob) end
    for _, mob in ipairs(D.CREATURE_TYPES) do add(mob) end
    local function rank(mob)
        if targetTypes[mob] then return 0 end
        if idx[mob] then return 1 end
        return 2
    end
    table.sort(types, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    return types, idx
end

local HOW = { taught = "taught", type = "creature type", name = "name" }

local function BuildSlayer(p)
    W.Header(p, "Slayer sets"):SetPoint("TOPLEFT", 0, 0)
    local hint = W.Text(p, 11, 0.55, 0.55, 0.55)
    hint:SetPoint("TOPLEFT", 0, -18)
    hint:SetWidth(520)
    hint:SetText("Items with extra damage against a mob type, read from their tooltips. Pick a type, then Build set.")

    local cols = { { 110 }, { 230 }, { 130 } }
    local head = W.ListHeader(p, cols, { "Mob type", "Items", "Set" })
    head:SetPoint("TOPLEFT", 0, -38)
    head:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    p.list = W.List(p, cols, 20, 10)
    p.list:SetPoint("TOPLEFT", 0, -58)
    p.list:SetPoint("RIGHT", p, "RIGHT", 0, 0)

    p.detail = W.Text(p, 12)
    p.detail:SetPoint("TOPLEFT", 0, -266)
    p.detail:SetWidth(520)
    p.detail:SetWordWrap(true)
    p.detail:SetJustifyV("TOP")

    p.build = W.Button(p, "Build set", 110, 22, function()
        if selType then BuildSet(selType) end
    end)
    p.build:SetPoint("TOPLEFT", 0, -366)
    W.Tooltip(p.build, "Makes (or remakes) the slayer set from the items on this character, biggest bonus first per slot.")

    p.wear = W.Button(p, "Put on", 90, 22, function()
        local s = selType and SlayerSetFor(selType)
        if s then M.Toggle(s) end
    end)
    p.wear:SetPoint("LEFT", p.build, "RIGHT", 4, 0)

    p.teach = W.Button(p, "Teach target", 150, 22, function()
        if selType then M.Teach(selType) end
    end)
    p.teach:SetPoint("LEFT", p.wear, "RIGHT", 4, 0)

    p.forget = W.Button(p, "Forget target", 100, 22, function() M.Teach(nil) end)
    p.forget:SetPoint("LEFT", p.teach, "RIGHT", 4, 0)
    W.Tooltip(p.forget, "Forgets what you taught your target is.")

    p.target = W.Text(p, 12)
    p.target:SetPoint("TOPLEFT", 0, -400)
    p.target:SetWidth(520)

    p.opts = {
        W.Check(p, "Chat message when you loot a new slayer item", function() return db.slayerLootAlert end,
            function(v) db.slayerLootAlert = v end),
        W.Check(p, "Bar glows when your target matches a slayer set", function() return db.slayerGlow end,
            function(v) db.slayerGlow = v end, nil, function() if M.RefreshBar then M.RefreshBar() end end),
    }
    p.opts[1]:SetPoint("TOPLEFT", 0, -422)
    p.opts[1]:SetWidth(300)
    p.opts[2]:SetPoint("TOPLEFT", 300, -422)
    p.opts[2]:SetWidth(320)
end

local function RefreshSlayer(p)
    local types, idx = TypeRows()
    selType = selType or types[1]

    local data = {}
    for _, mob in ipairs(types) do
        local s = SlayerSetFor(mob)
        local setText = s and (M.IsWorn(s) and C(GREEN, "on") or "made") or ""
        local label = mob .. (targetTypes[mob] and C(YELLOW, "  target") or "")
        data[#data + 1] = {
            cols = { label, Summary(idx[mob]), setText },
            mark = (mob == selType),
            onClick = function()
                selType = mob
                CF.RefreshCurrent()
            end,
        }
    end
    p.list:SetData(data)

    -- Items for the selected type
    local lines = {}
    local list = selType and idx[selType]
    if list then
        for i, e in ipairs(list) do
            if i > 4 then
                lines[#lines + 1] = C(GREY, ("and %d more"):format(#list - 4))
                break
            end
            local _, label = Locate(e.id)
            lines[#lines + 1] = "|T" .. M.ItemIcon(e.id) .. ":14|t " .. W.ItemName(e.id)
                .. C(GREY, ("  x%s  · %s"):format(e.mult, label))
        end
    elseif selType then
        lines[1] = C(GREY, "No " .. selType .. " items seen yet. Items are read from your bags, bank and (with Stash) other characters.")
    end
    p.detail:SetText(table.concat(lines, "\n"))

    local s = selType and SlayerSetFor(selType)
    p.build.text:SetText(s and "Rebuild set" or "Build set")
    p.build:SetEnabled(list ~= nil)
    p.wear:SetShown(s ~= nil)
    if s then p.wear.text:SetText((M.IsWorn(s) or M.IsActive(s)) and "Take off" or "Put on") end
    p.teach.text:SetText(selType and ("Target is a " .. selType) or "Teach target")

    -- Your target
    local exists, isPlayer = Plain(UnitExists("target")), Plain(UnitIsPlayer("target"))
    if exists and not isPlayer then
        local parts = {}
        for mob, how in pairs(targetTypes) do parts[#parts + 1] = mob .. C(GREY, " (" .. HOW[how] .. ")") end
        table.sort(parts)
        p.target:SetText("Target: " .. (TargetName() or "?") .. "  "
            .. (#parts > 0 and table.concat(parts, ", ") or C(GREY, "no type recognized")))
    else
        p.target:SetText(C(GREY, "Target a mob to see what it's recognized as, or to teach it."))
    end
    local tName = TargetName()
    local npc = NpcID("target")
    local nameKey = tName and ("name:" .. tName:lower())
    local canTeach = exists and not isPlayer and (npc or nameKey) ~= nil
    p.teach:SetEnabled(canTeach and selType ~= nil)
    p.forget:SetEnabled(canTeach and ((npc and db.mobs[npc]) or (nameKey and db.mobs[nameKey])) ~= nil)
    for _, o in ipairs(p.opts) do o.Refresh() end
end

table.insert(M.pages, 2, { key = "slayer", label = "Slayer", build = BuildSlayer, refresh = RefreshSlayer, live = true })
