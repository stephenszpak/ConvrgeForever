-- LFG module: find a group for an elite or dungeon quest, like Retail's eye
-- button next to group quests.
--
-- What WoW Forever gives us (checked in game):
--   * No quest is linked to a group finder activity
--     (C_LFGList.GetActivityIDForQuestID returns nil for every quest), so we
--     match by place instead. Quests & Zones (category 116) has one activity
--     per zone, Dungeons (category 2) one per dungeon. The quest log header a
--     quest sits under names its zone or dungeon.
--   * C_QuestLog.GetInfo's suggestedGroup is always 0. The quest tag is what
--     marks group quests: 1 "Elite", 81 "Dungeon", 41 "PvP".
--   * C_LFGList.Search needs a hardware event, so every search starts from a
--     click (a quest row, the quest log eye, or "Search again").
--   * The old quest log globals (GetQuestLogSelection, ...) don't exist; only
--     C_QuestLog does.

local _, CF = ...
local W = CF.W
local C, GREEN, YELLOW, RED, GREY = W.C, W.GREEN, W.YELLOW, W.RED, W.GREY

local M = CF:NewModule("lfg", {
    title = "LFG",
    description = "Finds groups in the Group Finder for your elite and dungeon quests, with an eye button in the quest log.",
    defaults = {
        questLogButtons = true,
        whisper = true,   -- prefill a short whisper when you click a group
    },
})

local db

local CAT_QUESTS, CAT_DUNGEONS = 116, 2

-- Quest tag ID -> kind. Tags 62/88/89 are raid tags in Blizzard's data;
-- they haven't been seen on Forever yet but cost nothing to handle.
local KIND = { [1] = "elite", [81] = "dungeon", [62] = "raid", [88] = "raid", [89] = "raid" }
local KIND_LABEL = { elite = "Elite", dungeon = "Dungeon", raid = "Raid" }

-- Names that differ between the quest log header and the group finder.
-- Keys and values are normalized (see Norm).
local ALIASES = {
    sunkentemple = "templeofatalhakkar",
    templeofatalhakkar = "sunkentemple",
}

local function Secret(v) return issecretvalue and issecretvalue(v) end

-- Readable value or nil (secret values can't be tested or concatenated).
local function Plain(v)
    if Secret(v) then return nil end
    return v
end

local function Norm(s)
    s = Plain(s)
    if type(s) ~= "string" then return "" end
    s = s:lower():gsub("^the ", "")
    return (s:gsub("[%s%p]", ""))
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
local function KindOf(questID)
    if not (questID and C_QuestLog and C_QuestLog.GetQuestTagInfo) then return end
    local ok, t = pcall(C_QuestLog.GetQuestTagInfo, questID)
    if ok and type(t) == "table" then return KIND[t.tagID] end
end

-- Your elite/dungeon/raid quests, each with the header it sits under.
-- Quests under a collapsed header aren't returned by the game.
local function GroupQuests()
    local out, header = {}, nil
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local q = C_QuestLog.GetInfo(i)
        if q then
            if q.isHeader then
                header = q.title
            elseif q.questID then
                local kind = KindOf(q.questID)
                if kind then
                    out[#out + 1] = { questID = q.questID, title = q.title or ("quest " .. q.questID),
                        level = q.level, header = header, kind = kind, complete = q.isComplete }
                end
            end
        end
    end
    return out
end

local function FindQuest(questID)
    for _, q in ipairs(GroupQuests()) do
        if q.questID == questID then return q end
    end
end

---------------------------------------------------------------------------
-- Group finder activities
---------------------------------------------------------------------------
local activities    -- { { id, cat, name, short, keys = {..} }, ... }, built on first use
local activityByID = {}

local function BuildIndex()
    activities = {}
    local cats, seen = {}, {}
    local function add(c) if c and not seen[c] then seen[c] = true; cats[#cats + 1] = c end end
    add(CAT_QUESTS); add(CAT_DUNGEONS)
    if C_LFGList.GetAvailableCategories then
        local ok, list = pcall(C_LFGList.GetAvailableCategories)
        if ok and type(list) == "table" then for _, c in ipairs(list) do add(c) end end
    end
    for _, cat in ipairs(cats) do
        local ok, ids = pcall(C_LFGList.GetAvailableActivities, cat)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do
                local info = C_LFGList.GetActivityInfoTable(id)
                if info and not activityByID[id] then
                    local a = { id = id, cat = info.categoryID or cat,
                        name = Plain(info.fullName) or Plain(info.shortName) or ("activity " .. id),
                        short = Plain(info.shortName) or Plain(info.fullName) or ("activity " .. id),
                        max = info.maxNumPlayers,
                        keys = { Norm(info.fullName), Norm(info.shortName) } }
                    activities[#activities + 1] = a
                    activityByID[id] = a
                end
            end
        end
    end
end

local function Activities()
    if not activities or #activities == 0 then BuildIndex() end
    return activities
end

-- Which categories fit a quest kind. Raids: anything that isn't quests/dungeons.
local function CatFits(kind, cat)
    if kind == "elite" then return cat == CAT_QUESTS end
    if kind == "dungeon" then return cat == CAT_DUNGEONS end
    return cat ~= CAT_QUESTS and cat ~= CAT_DUNGEONS
end

-- Activities matching the first of `places` that matches anything.
-- Exact name (or alias) beats a partial one, so "Dire Maul" finds all three
-- wings but "Stratholme" doesn't drag in something merely containing it.
local function MatchPlaces(places, kind)
    for _, place in ipairs(places) do
        local key = Norm(place)
        if #key >= 3 then
            local alias = ALIASES[key]
            local exact, partial, seen = {}, {}, {}
            for _, a in ipairs(Activities()) do
                if CatFits(kind, a.cat) and not seen[a.id] then
                    for _, k in ipairs(a.keys) do
                        if k ~= "" then
                            if k == key or k == alias then
                                exact[#exact + 1] = a; seen[a.id] = true; break
                            elseif #key >= 4 and #k >= 4 and (k:find(key, 1, true) or key:find(k, 1, true)) then
                                partial[#partial + 1] = a; seen[a.id] = true; break
                            end
                        end
                    end
                end
            end
            if #exact > 0 then return exact, place end
            if #partial > 0 then return partial, place end
        end
    end
end

-- Turns a quest into a search: { quest, cat, ids = {...} or nil, set, label, note }
local function TargetFor(q)
    local places = { q.header }
    local zone = GetRealZoneText and GetRealZoneText()
    if zone and zone ~= "" then places[#places + 1] = zone end
    local found, place = MatchPlaces(places, q.kind)

    local t = { quest = q }
    if found then
        t.cat = found[1].cat
        t.ids, t.set = {}, {}
        local names = {}
        for _, a in ipairs(found) do
            if a.cat == t.cat then
                t.ids[#t.ids + 1] = a.id
                t.set[a.id] = true
                names[#names + 1] = a.short
            end
        end
        t.label = table.concat(names, ", ")
        if place ~= q.header then
            t.note = "matched your current zone (" .. place .. "), not the quest log heading"
        end
    else
        t.cat = (q.kind == "dungeon") and CAT_DUNGEONS or CAT_QUESTS
        t.label = (q.kind == "dungeon") and "all dungeons" or "all zones"
        t.note = "couldn't match \"" .. tostring(q.header or "?") .. "\" to a Group Finder entry, so this shows everything"
    end
    return t
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
local target         -- last search
local results = {}   -- rows for the page
local status = ""

local function Refresh() CF.RefreshCurrent() end

-- Must run from a click: C_LFGList.Search needs a hardware event.
local function DoSearch(t)
    target, results = t, {}
    -- One call per click: a click allows a single protected call, and a
    -- failed call uses it up. Forever takes the Retail-style signature
    -- (a table as the second argument is rejected), so search the whole
    -- category and filter by activity in CollectResults.
    local ok, err = pcall(C_LFGList.Search, t.cat)
    status = ok and C(YELLOW, "Searching...") or C(RED, "Search failed: " .. tostring(err))
    Refresh()
end

function M.FindFor(questID)
    local q = FindQuest(questID)
    if not q then CF.Print("that quest isn't an elite or dungeon quest in your log.", "LFG") return end
    CF.Open("lfg")
    DoSearch(TargetFor(q))
end

local function Text(v)
    if Secret(v) then return C(GREY, "(hidden)") end
    if v == nil then return "" end
    return tostring(v)
end

local function Age(sec)
    sec = Plain(sec)
    if type(sec) ~= "number" then return "" end
    if sec < 60 then return "now" end
    if sec < 3600 then return math.floor(sec / 60) .. "m" end
    return math.floor(sec / 3600) .. "h"
end

local function Whisper(name, quest)
    if not name then return end
    local text = "/w " .. name .. " "
    if db.whisper and quest then text = text .. "Hi, room for one more on " .. quest .. "?" end
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(text)
    elseif ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(text)
    end
end

local function CollectResults()
    if not target then return end
    local _, list = C_LFGList.GetSearchResults()
    local rows = {}
    local questKey = (target.quest.title or ""):lower()
    for _, rid in ipairs(list or {}) do
        local info = C_LFGList.GetSearchResultInfo(rid)
        if info and not Plain(info.isDelisted) then
            local ids = Plain(info.activityIDs) or { Plain(info.activityID) }
            local where
            for _, id in ipairs(ids) do
                if not target.set or target.set[id] then where = id; break end
            end
            if where then
                local a = activityByID[where]
                local comment = Plain(info.comment)
                local title = Plain(info.name)
                local mentions = false
                for _, s in ipairs({ comment, title }) do
                    if type(s) == "string" and questKey ~= "" and s:lower():find(questKey, 1, true) then mentions = true end
                end
                local leader = Plain(info.leaderName)
                local n = Plain(info.numMembers)
                local size = n and ((a and a.max and a.max > 0) and (n .. "/" .. a.max) or tostring(n)) or ""
                local note = info.comment
                if Plain(note) == nil or Plain(note) == "" then note = info.name end
                rows[#rows + 1] = {
                    cols = { leader and Text(leader) or C(GREY, "(hidden)"), size, a and a.short or "", Text(note), Age(info.age) },
                    mark = mentions,
                    mentions = mentions,
                    age = Plain(info.age) or 0,
                    onClick = function() Whisper(leader, target.quest.title) end,
                    tip = function(tt)
                        tt:SetText(leader or "Group", 1, 1, 1)
                        if a then tt:AddLine(a.name, 0.7, 0.7, 0.7) end
                        if title and title ~= "" then tt:AddLine(title, 1, 0.82, 0, true) end
                        if comment and comment ~= "" then tt:AddLine(comment, 0.9, 0.9, 0.9, true) end
                        if mentions then tt:AddLine("Mentions your quest", 0.4, 0.87, 0.4) end
                        tt:AddLine(leader and "Click to whisper the leader." or "Leader's name is hidden, so it can't be whispered.",
                            0.55, 0.55, 0.55)
                    end,
                }
            end
        end
    end
    table.sort(rows, function(x, y)
        if x.mentions ~= y.mentions then return x.mentions end
        return x.age < y.age
    end)
    results = rows
    local mentioning = 0
    for _, r in ipairs(rows) do if r.mentions then mentioning = mentioning + 1 end end
    status = (#rows == 0) and C(GREY, "No groups listed right now.")
        or C(GREEN, #rows .. " group" .. (#rows == 1 and "" or "s"))
            .. (mentioning > 0 and C(GREY, ", " .. mentioning .. " mention your quest (highlighted)") or "")
    Refresh()
end

---------------------------------------------------------------------------
-- Quest log eye buttons (Retail-style QuestScrollFrame, or Classic QuestLogTitle1..N)
---------------------------------------------------------------------------
local eyes = {}
M.questLogHooked = false

local function Eye(btn)
    local e = eyes[btn]
    if e then return e end
    e = CreateFrame("Button", nil, btn)
    e:SetSize(16, 16)
    e:SetFrameLevel(btn:GetFrameLevel() + 2)
    local tex = e:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\LFGFrame\\LFG-Eye")
    tex:SetTexCoord(0, 0.125, 0, 0.25)
    local hl = e:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\LFGFrame\\LFG-Eye")
    hl:SetTexCoord(0, 0.125, 0, 0.25)
    hl:SetBlendMode("ADD")
    e:SetScript("OnClick", function(self) if self.questID then M.FindFor(self.questID) end end)
    e:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Find a group", 1, 1, 1)
        GameTooltip:AddLine("Search the Group Finder for this quest.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    e:SetScript("OnLeave", GameTooltip_Hide)
    eyes[btn] = e
    return e
end

local function PlaceEye(b, questID, anchor)
    local e = Eye(b)
    e.questID = questID
    e:ClearAllPoints()
    if anchor then
        e:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
    else
        e:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    end
    e:Show()
end

-- Retail-style quest log (what Forever has): quest titles are pooled
-- Buttons somewhere under QuestScrollFrame, each with a .questID. Headers
-- and objective lines aren't Buttons with a questID, so they're skipped.
local function ForEachRetailTitle(fn)
    local function walk(f, depth)
        for _, c in ipairs({ f:GetChildren() }) do
            local id = Plain(c.questID)
            if type(id) == "number" and c:GetObjectType() == "Button" then
                fn(c, id)
            elseif depth < 5 then
                walk(c, depth + 1)
            end
        end
    end
    if QuestScrollFrame then walk(QuestScrollFrame, 0) end
end

local function UpdateEyes()
    -- Hide everything first: pooled buttons get reused for other quests.
    for _, e in pairs(eyes) do e:Hide() end
    if not db.questLogButtons then return end

    -- Classic-style quest log: QuestLogTitle1..N, ID = quest log index.
    for i = 1, (QUESTS_DISPLAYED or 27) do
        local b = _G["QuestLogTitle" .. i]
        if not b then break end
        local idx = b:IsShown() and b:GetID()
        local q = idx and idx > 0 and C_QuestLog.GetInfo(idx)
        if q and not q.isHeader and KindOf(q.questID) then
            local tag = _G[b:GetName() .. "Tag"]
            PlaceEye(b, q.questID, (tag and tag:IsShown() and (tag:GetText() or "") ~= "") and tag or nil)
        end
    end

    ForEachRetailTitle(function(b, questID)
        if b:IsShown() and KindOf(questID) then
            -- Right after the quest name, like Retail: the right edge holds
            -- the tracking checkmark and the "(Elite)" tag.
            -- Only the button showing the quest name: other buttons in the
            -- row (the quest icon on the left) also carry the questID.
            local text = b.Text or b:GetFontString()
            if text and (text:GetText() or "") ~= "" then
                local e = Eye(b)
                e.questID = questID
                e:ClearAllPoints()
                local w = math.min(text:GetStringWidth() or 0, text:GetWidth() or 0)
                e:SetPoint("LEFT", text, "LEFT", w + 3, 0)
                e:Show()
            end
        end
    end)
end

local pending
local function QueueEyes()
    if pending then return end
    pending = true
    C_Timer.After(0, function() pending = false; UpdateEyes() end)
end

local function HookQuestLog()
    if M.questLogHooked then return end
    local hooked = false
    if type(QuestLog_Update) == "function" then
        hooksecurefunc("QuestLog_Update", QueueEyes); hooked = true
    end
    if type(QuestLogQuests_Update) == "function" then
        hooksecurefunc("QuestLogQuests_Update", QueueEyes); hooked = true
    end
    if QuestScrollFrame then
        QuestScrollFrame:HookScript("OnShow", QueueEyes)
        local box = QuestScrollFrame.ScrollBox
        if box and box.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
            box:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, QueueEyes, M)
        end
        hooked = true
    end
    M.questLogHooked = hooked
end

---------------------------------------------------------------------------
-- Group Finder window (to list your own group)
---------------------------------------------------------------------------
local function OpenGroupFinder()
    if ToggleLFGParentFrame then ToggleLFGParentFrame() return true end
    if LFGParentFrame then ShowUIPanel(LFGParentFrame) return true end
    if PVEFrame_ToggleFrame then PVEFrame_ToggleFrame() return true end
    return false
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
function M:OnLogin()
    db = self.db
    HookQuestLog()

    local f = CreateFrame("Frame")
    f:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    f:RegisterEvent("LFG_LIST_SEARCH_FAILED")
    f:RegisterEvent("QUEST_LOG_UPDATE")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
            CollectResults()
        elseif event == "LFG_LIST_SEARCH_FAILED" then
            if target then
                status = C(RED, "Search failed" .. (arg1 and (" (" .. tostring(arg1) .. ")") or "")
                    .. ". Wait a few seconds and press Search again.")
                Refresh()
            end
        elseif event == "QUEST_LOG_UPDATE" then
            Refresh()
            if QuestScrollFrame and QuestScrollFrame:IsVisible() then QueueEyes() end
        elseif event == "ADDON_LOADED" then
            HookQuestLog()   -- in case the quest log is load-on-demand
        end
    end)
end

function M:slash(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "debug" then
        local acts = Activities()
        local cats = {}
        for _, a in ipairs(acts) do cats[a.cat] = (cats[a.cat] or 0) + 1 end
        local parts = {}
        for c, n in pairs(cats) do parts[#parts + 1] = "cat " .. c .. ": " .. n end
        CF.Print("activities: " .. #acts .. " (" .. table.concat(parts, ", ") .. ")", "LFG")
        local titles, shown = 0, 0
        ForEachRetailTitle(function(b) titles = titles + 1 end)
        for _, e in pairs(eyes) do if e:IsShown() then shown = shown + 1 end end
        CF.Print(("quest log: %s, %d quest title buttons found, %d eyes showing (open the quest log first)")
            :format(M.questLogHooked and "hooked" or "not found", titles, shown), "LFG")
        for _, q in ipairs(GroupQuests()) do
            local t = TargetFor(q)
            print(("   %s [%s] under \"%s\" -> %s"):format(q.title, q.kind, tostring(q.header), t.label))
        end
    else
        CF.Open("lfg")
    end
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local QUEST_COLS = { { 240 }, { 60 }, { 210 } }
local GROUP_COLS = { { 100 }, { 34, "RIGHT" }, { 110 }, { 230 }, { 26, "RIGHT" } }

local function BuildPage(p)
    W.Header(p, "Your group quests"):SetPoint("TOPLEFT", 0, 0)
    local qh = W.ListHeader(p, QUEST_COLS, { "Quest", "Type", "Searches" })
    qh:SetPoint("TOPLEFT", 0, -18)
    qh:SetPoint("RIGHT")
    p.quests = W.List(p, QUEST_COLS, 20, 5)
    p.quests:SetPoint("TOPLEFT", 0, -36)
    p.quests:SetPoint("RIGHT")

    p.groupsHeader = W.Header(p, "Groups")
    p.groupsHeader:SetPoint("TOPLEFT", 0, -148)
    p.status = W.Text(p, 11)
    p.status:SetPoint("TOPLEFT", 0, -166)
    p.status:SetWidth(330)

    p.again = W.Button(p, "Search again", 100, 20, function() if target then DoSearch(TargetFor(target.quest)) end end)
    p.again:SetPoint("TOPRIGHT", 0, -146)
    p.finder = W.Button(p, "Group Finder", 100, 20, function()
        if not OpenGroupFinder() then CF.Print("couldn't find the Group Finder window; use the green eye.", "LFG") end
    end)
    p.finder:SetPoint("RIGHT", p.again, "LEFT", -6, 0)
    W.Tooltip(p.finder, "Opens the game's Group Finder, to list your own group. Put the quest name in the note so others can find it.")

    local gh = W.ListHeader(p, GROUP_COLS, { "Leader", "Size", "Where", "Note", "Age" })
    gh:SetPoint("TOPLEFT", 0, -184)
    gh:SetPoint("RIGHT")
    p.groups = W.List(p, GROUP_COLS, 20, 6)
    p.groups:SetPoint("TOPLEFT", 0, -202)
    p.groups:SetPoint("RIGHT")

    p.eyeCheck = W.Check(p, "Eye button on group quests in the quest log", function() return db.questLogButtons end,
        function(v) db.questLogButtons = v end, nil, UpdateEyes)
    p.eyeCheck:SetPoint("BOTTOMLEFT", 0, 0)
    p.eyeCheck:SetWidth(280)
    p.whisperCheck = W.Check(p, "Prefill a whisper when I click a group", function() return db.whisper end,
        function(v) db.whisper = v end)
    p.whisperCheck:SetPoint("BOTTOMLEFT", 290, 0)
end

local function RefreshPage(p)
    p.eyeCheck.Refresh()
    p.whisperCheck.Refresh()

    local rows = {}
    for _, q in ipairs(GroupQuests()) do
        local t = TargetFor(q)
        local selected = target and target.quest.questID == q.questID
        rows[#rows + 1] = {
            cols = { (q.level and C(GREY, "[" .. q.level .. "] ") or "") .. q.title .. (q.complete and C(GREEN, "  done") or ""),
                KIND_LABEL[q.kind], t.ids and t.label or C(YELLOW, t.label) },
            mark = selected,
            onClick = function() DoSearch(TargetFor(q)) end,
            tip = function(tt)
                tt:SetText(q.title, 1, 1, 1)
                tt:AddLine("Quest log heading: " .. tostring(q.header or "none"), 0.7, 0.7, 0.7)
                tt:AddLine("Searches: " .. t.label, 0.7, 0.7, 0.7, true)
                if t.note then tt:AddLine(t.note, 1, 0.8, 0.2, true) end
                tt:AddLine("Click to search the Group Finder.", 0.55, 0.55, 0.55)
            end,
        }
    end
    p.quests:SetData(rows, "No elite or dungeon quests in your log (expand collapsed headings).")

    if target then
        p.groupsHeader:SetText("Groups for " .. target.quest.title)
        p.status:SetText(status)
        p.groups:SetData(results, "")
    else
        p.groupsHeader:SetText("Groups")
        p.status:SetText(C(GREY, "Click a quest above to search."))
        p.groups:SetData({}, "")
    end
    p.again:SetShown(target ~= nil)
end

M.pages = {
    { key = "lfg", label = "LFG", build = BuildPage, refresh = RefreshPage },
}
