-- NodeScan.lua: the herbs and veins of Data/GatherNodes.lua, and your Herbalism and Mining (P.NodeScan).
local ns = _G.NaowhForever

local GetProfessions, GetProfessionInfo = GetProfessions, GetProfessionInfo

local P = ns.Professions
local NODES = P.GatherNodes

local PROFESSION_LINE = { herb = 182, ore = 186 }
local KIND, NEED, ITEM = 1, 2, 3
local ENGLISH_CLIENTS = { enUS = true, enGB = true }

local unlockNeed = {}
local skills = {}

local function AddSkill(index)
    if not index then return end
    local _, _, rank, _, _, _, line, modifier = GetProfessionInfo(index)
    for kind, id in pairs(PROFESSION_LINE) do
        if line == id then skills[kind] = (rank or 0) + (modifier or 0) end
    end
end

local Scan = {}
P.NodeScan = Scan

function Scan.Usable()
    return ENGLISH_CLIENTS[GetLocale()] == true
end

function Scan.Node(name)
    return NODES[name]
end

function Scan.Kind(node)
    return node[KIND]
end

function Scan.Need(node)
    return node[NEED]
end

function Scan.Item(node)
    return node[ITEM]
end

function Scan.ReadSkills()
    wipe(skills)
    local first, second = GetProfessions()
    AddSkill(first)
    AddSkill(second)
end

function Scan.Skill(kind)
    return skills[kind] or 0
end

local function ByNeed(a, b)
    if unlockNeed[a] ~= unlockNeed[b] then return unlockNeed[a] < unlockNeed[b] end
    return a < b
end

function Scan.Unlocked(kind, from, to, out)
    wipe(out)
    for name, node in pairs(NODES) do
        if node[KIND] == kind and node[NEED] > from and node[NEED] <= to then
            out[#out + 1] = name
            unlockNeed[name] = node[NEED]
        end
    end
    table.sort(out, ByNeed)
    return out
end
