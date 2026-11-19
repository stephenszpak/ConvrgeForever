-- Professions buyer: a small window at the auction house that works through the shopping list.
-- For each material it searches the auction house, shows the cheapest total, and buys it in two
-- clicks: Buy asks the auction house for the final price, Confirm pays it. Buying needs a click
-- each time; addons can't buy on their own.
--
-- The guides name materials but don't give item IDs, so an unknown material is first looked up
-- with a name search, and its ID kept for next time.

local _, CF = ...
local W = CF.W
local C, GREY, RED, YELLOW = W.C, W.GREY, W.RED, W.YELLOW
local M = CF.modules.professions

local SEARCH_TIMEOUT, BUY_TIMEOUT = 8, 12
local EVENTS = {
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED",
    "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED",
}
local RETRY = { none = true, noanswer = true, unavailable = true, failed = true, unconfirmed = true }

local frame, events
local ahOpen = false
local b = {}           -- the buyer's state: queue, index, state, itemID, found, estimate, unit, total, bought
local gen = 0

local function Money(copper)
    if GetMoneyString then return GetMoneyString(copper, true) end
    return GetCoinTextureString(copper)
end

local function PriceSort()
    return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
end

function M.AuctionHouseOpen() return ahOpen end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------
local Render, Start

local function Watch(seconds, state, onLate)
    gen = gen + 1
    local myGen = gen
    C_Timer.After(seconds, function()
        if myGen == gen and b.state == state then onLate() end
    end)
end

local function Late(state)
    return function() b.state = state; Render() end
end

local function Item() return b.queue and b.queue[b.index] end

local function CancelQuote()
    if b.state == "quoting" or b.state == "quoted" then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
end

local function CommoditySearch(id)
    b.itemID = id
    b.state = "searching"
    Watch(SEARCH_TIMEOUT, "searching", Late("noanswer"))
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(id), PriceSort(), true)
end

local function NameSearch(name)
    b.itemID = nil
    b.state = "finding"
    Watch(SEARCH_TIMEOUT, "finding", Late("noanswer"))
    C_AuctionHouse.SendBrowseQuery({ searchString = name, sorts = PriceSort(), filters = {} })
end

Start = function()
    local item = Item()
    if not item then
        b.state = "done"
        return Render()
    end
    local id = M.ItemID(item.name)
    if id then CommoditySearch(id) else NameSearch(item.name) end
    Render()
end

local function NextItem()
    CancelQuote()
    b.index = b.index + 1
    Start()
end

local function ReadBrowse()
    local item = Item()
    for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        local id = r.itemKey and r.itemKey.itemID
        local info = id and C_AuctionHouse.GetItemKeyInfo(r.itemKey)
        local name = (info and info.itemName) or (id and C_Item.GetItemNameByID(id))
        if name == item.name then
            M.LearnID(item.name, id)
            return CommoditySearch(id)
        end
    end
    if not C_AuctionHouse.HasFullBrowseResults() then
        C_AuctionHouse.RequestMoreBrowseResults()
        return
    end
    b.state = "none"
end

local function ReadListings()
    local item = Item()
    local want, have, total = item.qty, 0, 0
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(b.itemID) or 0 do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(b.itemID, i)
        if r then
            local n = math.min((r.quantity or 0) - (r.numOwnerItems or 0), want - have)
            if n > 0 then have, total = have + n, total + n * r.unitPrice end
            if have >= want then break end
        end
    end
    if have < want and not C_AuctionHouse.HasFullCommoditySearchResults(b.itemID) then
        C_AuctionHouse.RequestMoreCommoditySearchResults(b.itemID)
        return
    end
    b.found, b.estimate = have, total
    b.state = have > 0 and "listed" or "none"
end

local function Quote()
    b.buyQty = math.min(Item().qty, b.found)
    b.state = "quoting"
    Watch(SEARCH_TIMEOUT, "quoting", function()
        pcall(C_AuctionHouse.CancelCommoditiesPurchase)
        b.state = "unavailable"
        Render()
    end)
    C_AuctionHouse.StartCommoditiesPurchase(b.itemID, b.buyQty)
end

local function Confirm()
    b.state = "buying"
    Watch(BUY_TIMEOUT, "buying", Late("unconfirmed"))
    C_AuctionHouse.ConfirmCommoditiesPurchase(b.itemID, b.buyQty)
end

local function ShowInAuctionHouse(name)
    local ah = _G.AuctionHouseFrame
    if not (ah and ah.SearchBar) then return end
    if ah.SetDisplayMode and _G.AuctionHouseFrameDisplayMode then
        pcall(ah.SetDisplayMode, ah, _G.AuctionHouseFrameDisplayMode.Buy)
    end
    ah.SearchBar:SetSearchText(name)
    ah.SearchBar:StartSearch()
end

local function Close()
    if not frame then return end
    CancelQuote()
    gen = gen + 1
    b.state = nil
    events:UnregisterAllEvents()
    frame:Hide()
    CF.RefreshCurrent()
end

local function Primary()
    local s = b.state
    if s == "done" then return Close() end
    if s == "single" then return ShowInAuctionHouse(Item().name) end
    if s == "listed" then
        Quote()
    elseif s == "quoted" then
        Confirm()
    elseif RETRY[s] then
        return Start()
    end
    Render()
end

local function OnEvent(_, event, a, c)
    local item = Item()
    if not item then return end
    local s = b.state
    if (event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
        and s == "finding" then
        ReadBrowse()
    elseif (event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED")
        and s == "searching" and a == b.itemID then
        ReadListings()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and s == "searching"
        and type(a) == "table" and a.itemID == b.itemID then
        b.state = "single"
    elseif event == "COMMODITY_PRICE_UPDATED" and s == "quoting" then
        b.state, b.unit, b.total = "quoted", a, c
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" and s == "quoting" then
        b.state = "unavailable"
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" and (s == "buying" or s == "unconfirmed") then
        M.Bought(item.name, b.buyQty)
        b.bought = b.bought + 1
        return NextItem()
    elseif event == "COMMODITY_PURCHASE_FAILED" and s == "buying" then
        b.state = "failed"
    else
        return
    end
    Render()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function StateText(item)
    local s = b.state
    if s == "finding" then return "Looking it up...", "", nil end
    if s == "searching" then return "Searching the auction house...", "", nil end
    if s == "listed" then
        local n = math.min(item.qty, b.found)
        local short = b.found < item.qty and C(YELLOW, "Only " .. b.found .. " listed right now. ") or ""
        if GetMoney() < b.estimate then
            return ("%d cost %s"):format(n, Money(b.estimate)), C(RED, "You don't have enough gold."), nil
        end
        return ("Cheapest %d cost %s  (%s each)"):format(n, Money(b.estimate), Money(math.floor(b.estimate / n))),
            short .. C(GREY, "Buy asks for the final price before you pay."), "Buy " .. n
    end
    if s == "quoting" then return "Getting the final price...", "", nil end
    if s == "quoted" then
        local line1 = ("Final price %s  (%s each)"):format(Money(b.total), Money(b.unit))
        if GetMoney() < b.total then return line1, C(RED, "You don't have enough gold."), nil end
        local up = b.estimate > 0 and b.total > b.estimate * 1.1
        return line1, up and C(YELLOW, "That's more than the search showed; someone bought the cheapest ones.") or "",
            "Confirm"
    end
    if s == "buying" then return "Buying...", "", nil end
    if s == "none" then return "None listed right now.", C(GREY, "Skip it, or try again later."), "Try again" end
    if s == "single" then
        return "Sold as single items, not by amount.", C(GREY, "Show it in the auction house to buy by hand."), "Show in AH"
    end
    if s == "unavailable" then return "The auction house has no price for it right now.", "", "Try again" end
    if s == "noanswer" then
        return "No answer from the auction house.", C(GREY, "Searches are limited to a few a second."), "Try again"
    end
    if s == "failed" then return C(RED, "The purchase failed; the price may have changed."), "", "Try again" end
    if s == "unconfirmed" then
        return "No answer to the purchase yet.", C(GREY, "Check your bags before trying again."), "Try again"
    end
    return "", "", nil
end

Render = function()
    if not frame then return end
    local done = b.state == "done"
    local n = #b.queue
    frame.skip:SetShown(not done)
    if done then
        frame.title:SetText("Shopping list")
        frame.icon:Hide()
        frame.name:SetText(n == 0 and "Nothing to buy at the auction house."
            or ("Bought %d of %d items."):format(b.bought, n))
        frame.line1:SetText("")
        frame.line2:SetText("")
        frame.primary.text:SetText("Close")
        frame.primary:Enable()
        frame.primary:SetAlpha(1)
        return
    end
    local item = Item()
    frame.title:SetText(("Shopping list  (%d/%d)"):format(b.index, n))
    local icon = b.itemID and C_Item.GetItemIconByID(b.itemID)
    frame.icon:SetTexture(icon or 134400)
    frame.icon:Show()
    frame.name:SetText(item.qty .. " x " .. item.name)
    local line1, line2, label = StateText(item)
    frame.line1:SetText(line1)
    frame.line2:SetText(line2)
    frame.primary.text:SetText(label or "Buy")
    frame.primary:SetEnabled(label ~= nil)
    frame.primary:SetAlpha(label and 1 or 0.4)
    frame.skip:SetEnabled(b.state ~= "buying")
end

local function SavePosition()
    local point, _, _, x, y = frame:GetPoint()
    M.db.buyerPos = { point, x, y }
end

local function Build()
    frame = CreateFrame("Frame", "ConvrgeForeverBuyer", UIParent, "BackdropTemplate")
    frame:SetSize(330, 150)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); SavePosition() end)
    local pos = M.db.buyerPos
    if pos then frame:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else frame:SetPoint("CENTER", 300, 120) end
    W.Flat(frame, 0.067, 0.067, 0.067, 0.96, 0.18, 0.18, 0.18, 1)

    frame.title = W.AccentText(frame, 13)
    frame.title:SetPoint("TOPLEFT", 12, -10)
    local close = W.Button(frame, "x", 22, 20, Close)
    close:SetPoint("TOPRIGHT", -6, -6)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(32, 32)
    frame.icon:SetPoint("TOPLEFT", 12, -34)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.name = W.Text(frame, 14, 1, 1, 1)
    frame.name:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0)
    frame.name:SetPoint("RIGHT", -12, 0)
    frame.line1 = W.Text(frame, 12)
    frame.line1:SetPoint("TOPLEFT", frame.icon, "BOTTOMLEFT", 0, -8)
    frame.line1:SetPoint("RIGHT", -12, 0)
    frame.line2 = W.Text(frame, 11)
    frame.line2:SetPoint("TOPLEFT", frame.line1, "BOTTOMLEFT", 0, -4)
    frame.line2:SetPoint("RIGHT", -12, 0)
    frame.line2:SetWordWrap(true)

    frame.primary = W.Button(frame, "Buy", 120, 24, Primary)
    frame.primary:SetPoint("BOTTOMLEFT", 10, 10)
    frame.skip = W.Button(frame, "Skip", 80, 24, NextItem)
    frame.skip:SetPoint("BOTTOMRIGHT", -10, 10)

    events = CreateFrame("Frame")
    events:SetScript("OnEvent", OnEvent)
    W.ApplySkin()
end

-- Opens the buyer on the shopping list's auction house items. Returns false when it can't.
function M.OpenBuyer()
    if not ahOpen then return false end
    local queue = M.BuyQueue()
    if not frame then Build() end
    b.queue, b.index, b.bought, b.state = queue, 1, 0, nil
    for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
    frame:Show()
    Start()
    return true
end

function M.StartBuyer()
    local f = CreateFrame("Frame")
    f:RegisterEvent("AUCTION_HOUSE_SHOW")
    f:RegisterEvent("AUCTION_HOUSE_CLOSED")
    f:SetScript("OnEvent", function(_, event)
        if event == "AUCTION_HOUSE_SHOW" then
            ahOpen = true
            if M.db.popup and #M.BuyQueue() > 0 then
                -- Give the auction house a moment: searches sent as it opens are often ignored.
                C_Timer.After(0.5, function() if ahOpen then M.OpenBuyer() end end)
            end
        else
            ahOpen = false
            Close()
        end
        CF.RefreshCurrent()
    end)
end
