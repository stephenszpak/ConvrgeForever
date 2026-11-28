-- Gear extras:
--   * Shaman weapon imbues: a set (or a main set) names its imbue; after a swap
--     leaves your weapon without one, the bar's imbue button glows and casts it.
--   * Item tooltips say which of your sets an item is in, so you don't vendor it.
--   * Group roles: when the group gives you a role, offers the main set you
--     picked for it (Healer -> Resto).
--   * Slayer sets can go on by themselves when you target a match (out of
--     combat), and come off after combat once nothing you target wants them.

local _, CF = ...
local W = CF.W
local D = CF.GEAR
local M = CF.modules.gear
local C, GREY = W.C, W.GREY

local db, charDB

---------------------------------------------------------------------------
-- Shaman weapon imbues
---------------------------------------------------------------------------
local function IsShaman()
    return select(2, UnitClass("player")) == "SHAMAN"
end
M.IsShaman = IsShaman

-- none -> Rockbiter -> Flametongue -> Frostbrand -> Windfury -> none
function M.NextImbue(cur)
    if not cur then return D.IMBUES[1] end
    for i, name in ipairs(D.IMBUES) do
        if name == cur then return D.IMBUES[i + 1] end
    end
end

function M.ImbueShort(name)
    if not name then return "none" end
    return (name:gsub(" Weapon$", ""))
end

-- The imbue that should be on your weapon: from a set you put on that covers
-- your weapons, else from the main set you're wearing.
local function WantedImbue()
    if not charDB or not IsShaman() then return end
    for id in pairs(charDB.active) do
        local s = M.SetByID(id)
        if s and s.imbue and (s.slots[16] or s.slots[17]) and M.IsWorn(s) then return s.imbue end
    end
    for _, ms in ipairs(M.MainSets()) do
        if ms.equipped and charDB.mainImbues[ms.id] then return charDB.mainImbues[ms.id] end
    end
end
M.WantedImbue = WantedImbue

local WEAPON = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
                 INVTYPE_WEAPONOFFHAND = true }

local function IsWeapon(slot)
    local id = GetInventoryItemID("player", slot)
    if not id then return false end
    local _, _, _, loc = C_Item.GetItemInfoInstant(id)
    return WEAPON[loc] or false
end

-- A weapon you're holding has no temporary enchant on it.
function M.ImbueMissing()
    if not GetWeaponEnchantInfo then return false end
    local hasMH, _, _, _, hasOH = GetWeaponEnchantInfo()
    if IsWeapon(16) and not hasMH then return true end
    if IsWeapon(17) and not hasOH then return true end
    return false
end

local function ImbueReminder()
    if InCombatLockdown() then return end
    local want = WantedImbue()
    if want and M.ImbueMissing() then
        M.Say(want .. " isn't on your weapon: click the imbue button on the bar.")
    end
end

---------------------------------------------------------------------------
-- Tooltips: "Gear: Naga slayer, AoE"
---------------------------------------------------------------------------
local function SetsWith(id)
    local names = {}
    for _, s in ipairs(charDB.sets) do
        for _, x in pairs(s.slots) do
            if x == id then names[#names + 1] = s.name break end
        end
    end
    return names
end

local function AddToTooltip(tt, id)
    if not db.tooltipTag or not id or not charDB then return end
    local names = SetsWith(id)
    if #names == 0 then return end
    local r, g, b = W.Accent()
    tt:AddLine("Gear: " .. table.concat(names, ", "), r, g, b, true)
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
-- Group roles
---------------------------------------------------------------------------
local ROLES = { { "TANK", "Tank" }, { "HEALER", "Healer" }, { "DAMAGER", "Damage" } }
local ROLE_TEXT = { TANK = "tank", HEALER = "healer", DAMAGER = "damage dealer" }
local lastRole

StaticPopupDialogs["CONVRGE_GEAR_ROLE"] = {
    text = "%s",
    button1 = "Equip",
    button2 = "Not now",
    OnAccept = function(_, data) if data then M.EquipMain(data) end end,
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function MainSetByID(id)
    for _, ms in ipairs(M.MainSets()) do
        if ms.id == id then return ms end
    end
end

local function CheckRole()
    if not IsInGroup() then lastRole = nil return end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if role ~= nil and issecretvalue and issecretvalue(role) then return end   -- not readable by addons
    if not role or role == "NONE" or role == lastRole then return end
    lastRole = role
    if not db.rolesOffer then return end
    local ms = charDB.roleSets[role] and MainSetByID(charDB.roleSets[role])
    if ms and not ms.equipped then
        StaticPopup_Show("CONVRGE_GEAR_ROLE",
            ("You're the %s in this group. Equip %s?"):format(ROLE_TEXT[role], ms.name), nil, ms.id)
    end
end

---------------------------------------------------------------------------
-- Slayer sets that go on by themselves
---------------------------------------------------------------------------
function M.OnTargetTypes()
    if not db or not db.slayerAuto or InCombatLockdown() or M.Swapping() then return end
    local s = M.TargetSlayerSet and M.TargetSlayerSet()
    if not s or M.IsWorn(s) or M.IsActive(s) then return end
    M.PutOn(s)
    local a = charDB.active[s.id]
    if a then
        a.auto = true
        M.Say(s.name .. " on for your target.")
    end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
function M.InitExtras()
    db, charDB = M.db, M.char
    HookTooltips()

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    f:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    f:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    local token = 0
    f:SetScript("OnEvent", function(_, event, slot)
        if event == "PLAYER_EQUIPMENT_CHANGED" and slot ~= 16 and slot ~= 17 then return end
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
            C_Timer.After(1, CheckRole)
            return
        end
        if M.RefreshBar then M.RefreshBar() end
        if event == "UNIT_INVENTORY_CHANGED" then return end
        -- weapons changed: remind once things settle
        token = token + 1
        local mine = token
        C_Timer.After(1.5, function()
            if mine == token then ImbueReminder() end
        end)
    end)
end

-- Keybinding label (Options > Keybindings > AddOns > ConvrgeForever)
_G["BINDING_NAME_CLICK ConvrgeGearImbueKey:LeftButton"] = "Gear: weapon imbue"

---------------------------------------------------------------------------
-- Extras page
---------------------------------------------------------------------------
-- A button that cycles through choices: get() / set(v), values = { {v, label}, ... }
local function Cycler(parent, width, values, get, set)
    local b = W.Button(parent, "", width, 20, nil)
    b:SetScript("OnClick", function()
        local list, cur = values(), get()
        local nextV = list[1] and list[1][1]
        for i, v in ipairs(list) do
            if v[1] == cur then nextV = list[i + 1] and list[i + 1][1] or nil break end
        end
        set(nextV)
        M.Changed()
    end)
    b.Refresh = function()
        local cur, label = get(), "none"
        for _, v in ipairs(values()) do
            if v[1] == cur then label = v[2] end
        end
        b.text:SetText(label)
    end
    return b
end

local function MainSetValues()
    local t = {}
    for _, ms in ipairs(M.MainSets()) do t[#t + 1] = { ms.id, ms.name } end
    return t
end

local function ImbueValues()
    local t = {}
    for _, name in ipairs(D.IMBUES) do t[#t + 1] = { name, M.ImbueShort(name) } end
    return t
end

local MAX_MAIN = 6

local function BuildExtras(p)
    local function changed() M.Changed() end
    W.Header(p, "Item tooltips"):SetPoint("TOPLEFT", 0, 0)
    p.checks = {
        W.Check(p, "Show which of your sets an item is in", function() return db.tooltipTag end,
            function(v) db.tooltipTag = v end, "Adds \"Gear: <set names>\" to item tooltips, so you don't vendor a set piece.", changed),
        W.Check(p, "Put the slayer set on by itself when you target a match", function() return db.slayerAuto end,
            function(v) db.slayerAuto = v end,
            "Only out of combat. It comes off after combat unless your new target is the same type.", changed),
        W.Check(p, "Offer my main set for the role the group gives me", function() return db.rolesOffer end,
            function(v) db.rolesOffer = v end, "Pick a main set per role below.", changed),
    }
    p.checks[1]:SetPoint("TOPLEFT", 0, -22)
    W.Header(p, "Slayer"):SetPoint("TOPLEFT", 0, -54)
    p.checks[2]:SetPoint("TOPLEFT", 0, -76)
    p.checks[2]:SetWidth(420)
    W.Header(p, "Group roles"):SetPoint("TOPLEFT", 0, -108)
    p.checks[3]:SetPoint("TOPLEFT", 0, -130)
    p.checks[3]:SetWidth(420)

    p.roles = {}
    for i, r in ipairs(ROLES) do
        local role = r[1]
        local label = W.Text(p, 12)
        label:SetPoint("TOPLEFT", 0, -156 - (i - 1) * 24)
        label:SetText(r[2])
        local b = Cycler(p, 180, MainSetValues,
            function() return charDB.roleSets[role] end,
            function(v) charDB.roleSets[role] = v end)
        b:SetPoint("TOPLEFT", 80, -153 - (i - 1) * 24)
        p.roles[i] = b
    end

    p.imbueHeader = W.Header(p, "Weapon imbues for main sets")
    p.imbueHeader:SetPoint("TOPLEFT", 0, -236)
    p.imbueRows = {}
    for i = 1, MAX_MAIN do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(300, 22)
        row:SetPoint("TOPLEFT", 0, -258 - (i - 1) * 24)
        row.label = W.Text(row, 12)
        row.label:SetPoint("LEFT")
        row.label:SetWidth(140)
        row.button = Cycler(row, 140, ImbueValues,
            function() return row.setID and charDB.mainImbues[row.setID] end,
            function(v) if row.setID then charDB.mainImbues[row.setID] = v end end)
        row.button:SetPoint("LEFT", 150, 0)
        p.imbueRows[i] = row
    end
    p.imbueNote = W.Text(p, 11, 0.55, 0.55, 0.55)
    p.imbueNote:SetWidth(520)
    p.imbueNote:SetWordWrap(true)
end

local function RefreshExtras(p)
    for _, c in ipairs(p.checks) do c.Refresh() end
    for _, b in ipairs(p.roles) do b.Refresh() end

    local shaman = IsShaman()
    local sets = M.MainSets()
    p.imbueHeader:SetShown(shaman)
    for i, row in ipairs(p.imbueRows) do
        local ms = shaman and sets[i]
        row:SetShown(ms and true or false)
        if ms then
            row.setID = ms.id
            row.label:SetText("|T" .. (ms.icon or 134400) .. ":14|t " .. ms.name)
            row.button.Refresh()
        end
    end
    p.imbueNote:ClearAllPoints()
    p.imbueNote:SetPoint("TOPLEFT", 0, -262 - math.min(#sets, MAX_MAIN) * 24)
    p.imbueNote:SetShown(shaman)
    p.imbueNote:SetText(#sets == 0 and "Save sets in the game's equipment manager to give them an imbue."
        or "Sets you make here pick their imbue in the set editor. The bar's imbue button glows when your weapon is missing it.")
end

table.insert(M.pages, #M.pages, { key = "extras", label = "Extras", build = BuildExtras, refresh = RefreshExtras, live = true })
