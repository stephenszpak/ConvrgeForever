-- ConvrgeForever core: module registry, saved variables, migration, slash commands.
--
-- A module is registered with CF:NewModule(key, def). Fields a module can set:
--   title, description         shown in the window and on the General page
--   defaults, charDefaults     account-wide / per-character saved settings
--   legacyAddon                name of the standalone addon this module replaces
--   Migrate(self)              copy data from the legacy addon's saved variables (runs once)
--   OnLogin(self)              start the module (hooks, events); only called when enabled
--   pages                      { { key, label, build(page), refresh(page), live } ... }
--   slash(self, args)          handler for "/cf <key> ..."
-- After login, module.db and module.char point at its saved tables.

local ADDON, CF = ...
_G.ConvrgeForever = CF   -- lets you poke at it with /dump ConvrgeForever

CF.name = ADDON
CF.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "1.0.0"
CF.modules, CF.moduleOrder = {}, {}

function CF.Print(msg, tag)
    print("|cff4fc3f7Convrge|r" .. (tag and ("|cff888888 · " .. tag .. "|r") or "") .. ": " .. msg)
end

function CF:NewModule(key, def)
    def.key = key
    self.modules[key] = def
    self.moduleOrder[#self.moduleOrder + 1] = key
    return def
end

function CF:IsModuleEnabled(key)
    return self.db and self.db.modules[key] ~= false
end

-- A module is "running" when it was started this session.
function CF:IsModuleRunning(key)
    local m = self.modules[key]
    return m and m.running
end

---------------------------------------------------------------------------
-- Saved variable helpers
---------------------------------------------------------------------------
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x) end
    return t
end
CF.DeepCopy = DeepCopy

local function ApplyDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then
            t[k] = DeepCopy(v)
        elseif type(v) == "table" and type(t[k]) == "table" then
            ApplyDefaults(t[k], v)
        end
    end
end

local GENERAL_DEFAULTS = {
    minimap = { hide = false, angle = 200 },
    -- accent = { r, g, b }   (only used when EllesmereUI isn't theming the window)
}

local function AddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    return _G.IsAddOnLoaded and _G.IsAddOnLoaded(name)
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    ConvrgeForeverDB = ConvrgeForeverDB or {}
    ConvrgeForeverCharDB = ConvrgeForeverCharDB or {}
    local db, char = ConvrgeForeverDB, ConvrgeForeverCharDB
    db.general = db.general or {}
    db.modules = db.modules or {}
    ApplyDefaults(db.general, GENERAL_DEFAULTS)
    CF.db, CF.char = db, char

    for _, key in ipairs(CF.moduleOrder) do
        local m = CF.modules[key]
        db[key] = db[key] or {}
        char[key] = char[key] or {}
        ApplyDefaults(db[key], m.defaults or {})
        ApplyDefaults(char[key], m.charDefaults or {})
        m.db, m.char = db[key], char[key]

        if m.Migrate then m:Migrate() end

        if m.legacyAddon and AddOnLoaded(m.legacyAddon) then
            -- Running both would double up tooltips, hooks and buttons.
            m.blockedByLegacy = true
            CF.Print(("%s is still enabled, so the %s module is paused. Its data has been imported: "
                .. "disable %s in your AddOns list and /reload."):format(m.legacyAddon, m.title, m.legacyAddon))
        elseif CF:IsModuleEnabled(key) and m.OnLogin then
            m.running = true
            m:OnLogin()
        end
    end

    if CF.InitWindow then CF.InitWindow() end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_CONVRGEFOREVER1 = "/cf"
SLASH_CONVRGEFOREVER2 = "/convrge"
SlashCmdList.CONVRGEFOREVER = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        if CF.ToggleUI then CF.ToggleUI() end
        return
    end
    local m = CF.modules[cmd]
    if m and m.slash then
        if m.running then m:slash(rest or "") else CF.Print(m.title .. " module is off (enable it in /cf > General).") end
        return
    end
    CF.Print("commands:")
    print("   /cf  - open the window")
    for _, key in ipairs(CF.moduleOrder) do
        local mod = CF.modules[key]
        if mod.slash then print("   /cf " .. key .. " help  - " .. mod.title .. " commands") end
    end
end
