-- NodeTooltip.lua: Minimap Node Tooltips: hovering a herb or vein on the minimap adds the skill it needs to its tooltip.
local ns = _G.NaowhForever

local P = ns.Professions
local S = P.Settings
local Style = P.Style
local Scan = P.NodeScan
local C = P.C

local TIER_ORANGE, TIER_YELLOW, TIER_GREEN, TIER_GREY = 0, 1, 2, 3
local EVENTS = { "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD" }
local TEXT_REQUIRES = ns.L("Requires %s %d")
local TEXT_NAMED = "%s: %s"
local TEXT_PROFESSION = { herb = ns.L("Herbalism"), ore = ns.L("Mining") }
local PICK_PX = 9
local SAME_PX = 2
local REACH = 1.5
local RECHECK = 0.1
local ROTATE_CVAR = "rotateMinimap"
local KEY = "%d:%d:%d:%d:%s"
local KEY_PER_YARD = 2

local events, hooked
local found, said, hits = {}, {}, {}
local tracked = {}
local fit = {}
local lastCheck, lastKey = 0, nil

local function On()
    return S.Get("enabled") and S.Get("nodeIcons") and true or false
end

local function Plain(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function Tier(over)
    if over < C.SKILL_ORANGE then return TIER_ORANGE end
    if over < C.SKILL_YELLOW then return TIER_YELLOW end
    if over < C.SKILL_GREEN then return TIER_GREEN end
    return TIER_GREY
end

local function Track()
    wipe(tracked)
    local any = false
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if info and info.active then
            for kind, spell in pairs(C.FIND_SPELL) do
                if info.spellID == spell then tracked[kind], any = true, true end
            end
        end
    end
    return any
end

local function Fit(mapID)
    if fit.mapID == mapID then return fit.ok end
    fit.mapID, fit.ok = mapID, false
    local cont, o = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
    local _, u = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
    local _, v = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
    if not (o and u and v) then return false end
    fit.cont, fit.ox, fit.oy = cont, o:GetXY()
    local ux, uy = u:GetXY()
    local vx, vy = v:GetXY()
    fit.ux, fit.uy, fit.vx, fit.vy = ux - fit.ox, uy - fit.oy, vx - fit.ox, vy - fit.oy
    fit.det = fit.ux * fit.vy - fit.uy * fit.vx
    fit.width, fit.height = C_Map.GetMapWorldSize(mapID)
    fit.ok = fit.det ~= 0 and (fit.width or 0) > 0
    return fit.ok
end

local function Here()
    local wx, wy, _, cont = UnitPosition("player")
    if not Plain(wx) or cont ~= fit.cont then return end
    local rx, ry = wx - fit.ox, wy - fit.oy
    return (rx * fit.vy - ry * fit.vx) / fit.det, (fit.ux * ry - fit.uy * rx) / fit.det
end

local function ByDistance(a, b) return a.d < b.d end

local function Spots(G, mapID)
    if not (G.NODES and G.C and G.Spots and G.Spots.Load()) then return end
    return ns.GlimmerSpots and ns.GlimmerSpots[ns.Shared.Places.SameMap(mapID)]
end

local function Lookup()
    wipe(found)
    wipe(said)
    wipe(hits)
    local G = ns.Glimmer
    if not G then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    local all = mapID and Fit(mapID) and Spots(G, mapID)
    if not all then return end
    local px, py = Here()
    local radius = C_Minimap.GetViewRadius()
    if not px or not radius or radius <= 0 then return end
    local scaleX, scaleY = Minimap:GetWidth() / 2 / radius, Minimap:GetHeight() / 2 / radius
    local facing = C_CVar.GetCVarBool(ROTATE_CVAR) and GetPlayerFacing() or 0
    local sin, cos = math.sin(facing), math.cos(facing)
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local mx, my = Minimap:GetCenter()
    mx, my = cx / scale - mx, cy / scale - my
    local anyTracked = Track()
    local spotScale, reach, pick = G.C.SPOT_SCALE, (radius * REACH) ^ 2, PICK_PX * PICK_PX
    local best = pick
    for i = 1, #all, 3 do
        local node = G.NODES[all[i]]
        local kind = node and node[1]
        if TEXT_PROFESSION[kind] and (not anyTracked or tracked[kind]) then
            local dx = (all[i + 1] / spotScale - px) * fit.width
            local dy = (py - all[i + 2] / spotScale) * fit.height
            if dx * dx + dy * dy <= reach then
                local sx = (dx * cos + dy * sin) * scaleX - mx
                local sy = (dy * cos - dx * sin) * scaleY - my
                local d = sx * sx + sy * sy
                if d <= pick then
                    hits[#hits + 1] = { d = d, node = node }
                    if d < best then best = d end
                end
            end
        end
    end
    if #hits == 0 then return end
    table.sort(hits, ByDistance)
    local limit = (math.sqrt(best) + SAME_PX) ^ 2
    for _, hit in ipairs(hits) do
        if hit.d > limit then break end
        local name = hit.node[3]
        if not said[name] then
            said[name] = true
            found[#found + 1] = hit.node
        end
    end
end

local function AddNeed(tooltip, node, named)
    local kind, need = node[1], node[2]
    local over = Scan.Skill(kind) - need
    local c = over < 0 and Style.RED_RGB or Style.DIFFICULTY_RGB[Tier(over)]
    local text = TEXT_REQUIRES:format(TEXT_PROFESSION[kind], need)
    if named then text = TEXT_NAMED:format(node[3], text) end
    tooltip:AddLine(text, c.r, c.g, c.b)
end

local function OnMinimapTooltip(tooltip)
    if tooltip ~= GameTooltip or not On() then return end
    local now = GetTime()
    local cx, cy = GetCursorPosition()
    local wx, wy = UnitPosition("player")
    local key = Plain(wx) and KEY:format(cx, cy, wx * KEY_PER_YARD, wy * KEY_PER_YARD,
        tostring(C_Minimap.GetViewRadius())) or nil
    if key ~= lastKey or now - lastCheck > RECHECK then
        lastKey, lastCheck = key, now
        Lookup()
    end
    if #found == 0 then return end
    for _, node in ipairs(found) do AddNeed(tooltip, node, #found > 1) end
    tooltip:Show()
end

local function Apply()
    if not On() or not Scan.Usable() then
        if events then events:UnregisterAllEvents() end
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", Scan.ReadSkills)
    end
    if not hooked then
        hooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.MinimapMouseover, OnMinimapTooltip)
    end
    for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
    Scan.ReadSkills()
end

local function OnSettingChanged(key)
    if key == "enabled" or key == "nodeIcons" then Apply() end
end

hooksecurefunc(S, "Set", OnSettingChanged)
ns.OnApply(Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
