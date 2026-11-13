-- AHelper: scanning and buying for clients with the modern auction house API (C_AuctionHouse), e.g. WoW Forever.
--
-- Full scan  : C_AuctionHouse.ReplicateItems()  (server allows one every 15 minutes)
-- Searches   : C_AuctionHouse.SendSearchQuery() for one item; results arrive as COMMODITY_ / ITEM_SEARCH_RESULTS_UPDATED
-- Buying     : commodities (stackables) -> StartCommoditiesPurchase + ConfirmCommoditiesPurchase (buys the cheapest units)
--              items (gear etc.)        -> PlaceBid(auctionID, buyout)
-- Purchases need a real click, so the popup "prepares" a purchase in the background and the Buy click completes it.
local _, ns = ...
if QueryAuctionItems or not C_AuctionHouse then return end

local AH = C_AuctionHouse
local Scanner = {}
ns.Scanner = Scanner

Scanner.modern = true
Scanner.ahOpen = false
Scanner.state = "idle"   -- idle | replicate | replProcess
Scanner.seen = {}
Scanner.sniper = false

local CHUNK = 1000

local function status(msg)
    Scanner.statusText = msg
    if ns.UI and ns.UI.SetStatus then ns.UI.SetStatus(msg) end
end
Scanner.Status = status

local function refreshPopup(cand)
    if ns.BuyPopup and ns.BuyPopup.Refresh then ns.BuyPopup.Refresh(cand) end
end

---------------------------------------------------------------------------
-- Item keys / sorting
---------------------------------------------------------------------------
local keyCache = {}
local function itemKey(id)
    local k = keyCache[id]
    if k then return k end
    local equippable = (C_Item and C_Item.IsEquippableItem and C_Item.IsEquippableItem(id))
        or (IsEquippableItem and IsEquippableItem(id))
    if equippable then
        local ilvl = select(4, GetItemInfo(id))
        if not ilvl then return AH.MakeItemKey(id) end -- not cached yet, don't cache this key
        k = AH.MakeItemKey(id, ilvl)
    else
        k = AH.MakeItemKey(id)
    end
    keyCache[id] = k
    return k
end

local SORTS
local function sorts()
    if not SORTS then
        local price = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
        SORTS = { { sortOrder = price, reverseSort = false } }
    end
    return SORTS
end

local function vendorPrice(id)
    local _, _, _, vendor = ns.ItemInfo(id)
    if vendor then return vendor end
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    local rec = ns.RealmDB().items[id]
    return rec and rec.v
end

---------------------------------------------------------------------------
-- Opportunity rules
---------------------------------------------------------------------------
-- Is a unit price a buying opportunity? Returns reason, value per unit, net profit per unit.
local function judge(id, unit)
    if AHelperDB.ignore[id] then return nil end
    local S = ns.settings
    local vendor = vendorPrice(id)
    if S.vendorPopup and vendor and vendor > 0 and unit < vendor then
        return "vendor", vendor, vendor - unit
    end
    local w = AHelperDB.watch[id]
    local mkt, nDays = ns.Data.Market(id)
    if w and w.maxPrice and unit <= w.maxPrice then
        return "watch", mkt or w.maxPrice, mkt and (mkt * (1 - S.ahCut) - unit) or 0
    end
    if S.dealPopup and mkt and nDays >= S.dealMinSamples and unit <= mkt * S.dealMaxPct / 100 then
        return "deal", mkt, mkt * (1 - S.ahCut) - unit
    end
end

local function passesMin(reason, profit)
    local S = ns.settings
    if reason == "vendor" then return profit >= S.vendorMinProfit end
    if reason == "deal" then return profit >= S.dealMinProfit end
    return reason == "watch"
end

local function budget()
    return math.min(ns.settings.maxPopupSpend, GetMoney())
end

-- rows: { {unit, qty}, ... } ascending. Returns one aggregated candidate (or nil).
local function aggregate(id, rows)
    local count, spend, profit, value, maxUnit, reason = 0, 0, 0, 0, nil, nil
    local cap = budget()
    for _, r in ipairs(rows) do
        local why, val, net = judge(id, r.unit)
        if not why then break end
        local take = r.qty
        if spend + take * r.unit > cap then take = math.floor((cap - spend) / r.unit) end
        if take <= 0 then break end
        reason = reason or why
        count = count + take
        spend = spend + take * r.unit
        profit = profit + take * net
        value = value + take * val
        maxUnit = r.unit
        if take < r.qty then break end
    end
    if count == 0 or not passesMin(reason, profit) then return nil end
    return { itemID = id, count = count, buyout = math.floor(spend + 0.5), profit = profit, value = value,
             reason = reason, maxUnit = maxUnit }
end

local function offer(cand)
    if not cand or Scanner.seen[cand.sig] then return end
    Scanner.seen[cand.sig] = true
    cand.name = cand.name or ns.ItemInfo(cand.itemID)
    ns.BuyPopup.Push(cand)
end

---------------------------------------------------------------------------
-- Search queue (one search in flight, respects the server throttle)
---------------------------------------------------------------------------
local queue, waiting, inflight, inflightAt = {}, {}, nil, 0
local pump

local function finish(id, kind)
    if inflight == id then inflight = nil end
    local cbs = waiting[id]
    waiting[id] = nil
    if cbs then for _, cb in ipairs(cbs) do cb(kind, id) end end
    C_Timer.After(0.05, pump)
end

function pump()
    if inflight or #queue == 0 then return end
    if not Scanner.ahOpen then
        -- AH closed: fail everything that is waiting
        while #queue > 0 do finish(table.remove(queue, 1), nil) end
        return
    end
    if Scanner.state ~= "idle" then C_Timer.After(1, pump) return end
    if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
        C_Timer.After(0.5, pump) -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY also pumps
        return
    end
    local id = table.remove(queue, 1)
    inflight, inflightAt = id, GetTime()
    AH.SendSearchQuery(itemKey(id), sorts(), true)
    C_Timer.After(6, function()
        if inflight == id and GetTime() - inflightAt >= 5.9 then finish(id, nil) end
    end)
end

-- Search one item; cb(kind, itemID) where kind = "commodity" | "item" | nil (failed / timed out)
function Scanner.Search(id, cb)
    local first = not waiting[id]
    waiting[id] = waiting[id] or {}
    if cb then table.insert(waiting[id], cb) end
    if first and inflight ~= id then table.insert(queue, id) end
    pump()
end

local function commodityRows(id)
    local rows = {}
    local n = AH.GetNumCommoditySearchResults(id) or 0
    for i = 1, n do
        local r = AH.GetCommoditySearchResultInfo(id, i)
        if r and r.unitPrice and r.unitPrice > 0 then
            local qty = (r.quantity or 0) - (r.numOwnerItems or 0)
            if qty > 0 then rows[#rows + 1] = { unit = r.unitPrice, qty = qty } end
        end
    end
    table.sort(rows, function(a, b) return a.unit < b.unit end)
    return rows
end

local function itemRows(id)
    local rows = {}
    local key = itemKey(id)
    local n = AH.GetNumItemSearchResults(key) or 0
    for i = 1, n do
        local r = AH.GetItemSearchResultInfo(key, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
            -- Be conservative: a search row can represent several identical listings (quantity > 1),
            -- but one PlaceBid buys ONE of them for buyoutAmount. Never divide the price by the quantity.
            rows[#rows + 1] = { auctionID = r.auctionID, buyout = r.buyoutAmount, qty = 1,
                                unit = r.buyoutAmount, link = r.itemLink, listed = r.quantity,
                                owner = r.owners and r.owners[1] }
        end
    end
    table.sort(rows, function(a, b) return a.unit < b.unit end)
    return rows
end

-- Individual item auctions that qualify, as ready-to-buy candidates
local function itemCandidates(id, rows)
    local out, cap = {}, budget()
    for _, r in ipairs(rows) do
        local why, val, net = judge(id, r.unit)
        if not why then break end
        if r.buyout <= cap and passesMin(why, net * r.qty) then
            out[#out + 1] = { mode = "item", itemID = id, auctionID = r.auctionID, count = r.qty, buyout = r.buyout,
                              profit = net * r.qty, value = val * r.qty, reason = why, link = r.link,
                              owner = r.owner, sig = "a" .. tostring(r.auctionID) }
        end
    end
    return out
end

local function commodityCandidate(id)
    local c = aggregate(id, commodityRows(id))
    if c then
        c.mode = "commodity"
        c.sig = "c" .. id .. ":" .. c.count .. ":" .. c.buyout
    end
    return c
end

-- Offer everything that qualifies in the current search results for an item
local function offerFromResults(id, kind)
    if kind == "commodity" then
        offer(commodityCandidate(id))
    elseif kind == "item" then
        for _, c in ipairs(itemCandidates(id, itemRows(id))) do offer(c) end
    end
end

---------------------------------------------------------------------------
-- Popup purchase flow
---------------------------------------------------------------------------
local activeCommodity

local function startCommodity(cand)
    if activeCommodity and activeCommodity ~= cand then AH.CancelCommoditiesPurchase() end
    activeCommodity = cand
    cand.quoting, cand.ready = true, false
    AH.StartCommoditiesPurchase(cand.itemID, cand.count)
end

local function copyInto(dst, src)
    for k, v in pairs(src) do if k ~= "sig" then dst[k] = v end end
end

-- Called by the popup when a candidate becomes the one on screen
function Scanner.Prepare(cand)
    if cand.prepared then
        if cand.mode == "commodity" and activeCommodity ~= cand and not cand.gone then startCommodity(cand) end
        return
    end
    cand.prepared = true
    if cand.mode == "item" then
        cand.ready = true
    elseif cand.mode == "commodity" then
        startCommodity(cand)
    else
        -- came from a full scan: find out what kind of item it is and get live listings first
        cand.loading = true
        Scanner.Search(cand.itemID, function(kind, id)
            cand.loading = false
            if kind == "commodity" then
                local c = commodityCandidate(id)
                if c then copyInto(cand, c) startCommodity(cand) else cand.gone = true end
            elseif kind == "item" then
                local list = itemCandidates(id, itemRows(id))
                if #list > 0 then
                    copyInto(cand, list[1])
                    cand.ready = true
                    Scanner.seen[list[1].sig] = true
                    for i = 2, #list do offer(list[i]) end
                else
                    cand.gone = true
                end
            else
                cand.gone = true
            end
            refreshPopup(cand)
        end)
    end
end

-- Called by the popup when a candidate leaves the screen
function Scanner.Release(cand)
    if cand and activeCommodity == cand then
        AH.CancelCommoditiesPurchase()
        activeCommodity = nil
        cand.ready = false
    end
end

local function logPurchase(cand)
    table.insert(AHelperDB.purchases, { t = time(), id = cand.itemID, c = cand.count, p = cand.buyout,
        r = cand.reason, e = math.floor(cand.profit or 0), realm = ns.RealmKey() })
    while #AHelperDB.purchases > 500 do table.remove(AHelperDB.purchases, 1) end
end

-- Must be called from a click. Returns "bought", "wait" or "gone".
function Scanner.TryBuy(cand)
    if not Scanner.ahOpen then ns.Print("auction house is closed") return "gone" end
    if cand.gone then return "gone" end
    if GetMoney() < cand.buyout then ns.Print("not enough gold") return "gone" end
    if cand.mode == "commodity" and cand.ready and activeCommodity == cand then
        AH.ConfirmCommoditiesPurchase(cand.itemID, cand.count)
        activeCommodity = nil
        logPurchase(cand)
        return "bought"
    elseif cand.mode == "item" and cand.auctionID then
        AH.PlaceBid(cand.auctionID, cand.buyout)
        logPurchase(cand)
        return "bought"
    end
    return "wait"
end

---------------------------------------------------------------------------
-- Full scan (ReplicateItems)
---------------------------------------------------------------------------
local uncachedRetry = {}

-- Look through the latest full scan for opportunities; actual purchase details are fetched when the popup shows them
local function evaluateScan(onlyIDs)
    local n = 0
    for id, cur in pairs(ns.Data.current) do
        if not onlyIDs or onlyIDs[id] then
            if not vendorPrice(id) and not onlyIDs then uncachedRetry[id] = true end
            local rows = {}
            for _, a in ipairs(cur.auctions) do rows[#rows + 1] = { unit = a[1], qty = a[2] } end
            local c = aggregate(id, rows)
            if c then
                c.sig = "r" .. id .. ":" .. c.count .. ":" .. c.buyout
                offer(c)
                n = n + 1
            end
        end
    end
    return n
end

function Scanner.StartFullScan()
    if not Scanner.ahOpen then ns.Print("open the auction house first") return end
    if Scanner.state ~= "idle" then ns.Print("busy:", Scanner.state) return end
    if Scanner.sniper then Scanner.ToggleSniper() end
    local last = ns.RealmDB().lastScan or 0
    if time() - last < 900 then
        local wait = 900 - (time() - last)
        ns.Print(string.format("note: the server only allows a full scan every 15 min (~%d:%02d left). Trying anyway...",
            math.floor(wait / 60), wait % 60))
    end
    Scanner.state = "replicate"
    status("Full scan: waiting for server...")
    AH.ReplicateItems()
    local started = GetTime()
    C_Timer.After(60, function()
        if Scanner.state == "replicate" and GetTime() - started >= 59 then
            Scanner.state = "idle"
            status("Full scan got no response - the server allows one every 15 minutes.")
            ns.Print("full scan got no response (only allowed every 15 minutes)")
        end
    end)
end

local function processReplicate()
    Scanner.state = "replProcess"
    local total = AH.GetNumReplicateItems()
    local agg, i = {}, 0
    local ticker
    ticker = C_Timer.NewTicker(0.01, function()
        if not Scanner.ahOpen then
            ticker:Cancel()
            Scanner.state = "idle"
            status("Scan aborted: auction house closed")
            return
        end
        local stop = math.min(total - 1, i + CHUNK - 1)
        for idx = i, stop do
            local name, _, count, quality, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID =
                AH.GetReplicateItemInfo(idx)
            if itemID and buyout and buyout > 0 and count and count > 0 then
                local a = agg[itemID]
                if not a then
                    a = { name = name, q = quality, v = vendorPrice(itemID), auctions = {} }
                    agg[itemID] = a
                end
                a.name = a.name or name
                local tl = AH.GetReplicateItemTimeLeft and AH.GetReplicateItemTimeLeft(idx)
                -- modern time-left bands are 0..3, classic 1..4; Data expects classic
                table.insert(a.auctions, { buyout / count, count, owner, tl and (tl + 1) or 4 })
            end
        end
        i = stop + 1
        status(string.format("Full scan: processing %d / %d", i, total))
        if i >= total then
            ticker:Cancel()
            local sold = ns.Data.RecordScan(agg, time())
            Scanner.state = "idle"
            local n = 0
            for _ in pairs(agg) do n = n + 1 end
            local deals = evaluateScan()
            status(string.format("Scan done: %d auctions, %d items, %d opportunities. Est. %d sold since last scan.",
                total, n, deals, sold))
            ns.Print(string.format("scan complete: %d auctions / %d unique items", total, n))
            if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
            -- vendor prices for items the client hadn't cached yet: check again once they load
            if next(uncachedRetry) then
                local ids = uncachedRetry
                uncachedRetry = {}
                C_Timer.After(5, function() evaluateScan(ids) end)
            end
            pump()
        end
    end)
end

---------------------------------------------------------------------------
-- Sniper: searches watchlist + farm items one at a time
---------------------------------------------------------------------------
local snipeList, snipeIdx = {}, 0

local function buildSnipeList()
    wipe(snipeList)
    local added = {}
    for id in pairs(AHelperDB.watch) do if not added[id] then table.insert(snipeList, id); added[id] = true end end
    for _, e in ipairs(ns.FarmDB) do if not added[e.id] then table.insert(snipeList, e.id); added[e.id] = true end end
end

local function snipeNext()
    if not Scanner.sniper or not Scanner.ahOpen then return end
    if #snipeList == 0 then buildSnipeList() end
    if #snipeList == 0 then ns.Print("nothing to snipe") Scanner.ToggleSniper() return end
    snipeIdx = snipeIdx % #snipeList + 1
    local id = snipeList[snipeIdx]
    status(string.format("Sniper: %s [%d/%d]", ns.ItemInfo(id) or ("item " .. id), snipeIdx, #snipeList))
    Scanner.Search(id, function(kind)
        offerFromResults(id, kind)
        if Scanner.sniper then C_Timer.After(ns.settings.snipeInterval, snipeNext) end
    end)
end

function Scanner.ToggleSniper()
    if not Scanner.sniper and not Scanner.ahOpen then ns.Print("open the auction house first") return end
    Scanner.sniper = not Scanner.sniper
    if Scanner.sniper then
        buildSnipeList()
        ns.Print("sniper started:", #snipeList, "items in rotation")
        snipeNext()
    else
        status("Sniper stopped")
    end
    if ns.UI and ns.UI.UpdateButtons then ns.UI.UpdateButtons() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.On("AUCTION_HOUSE_SHOW", function()
    Scanner.ahOpen = true
    if ns.UI and ns.UI.OnAHShow then ns.UI.OnAHShow() end
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
    Scanner.ahOpen = false
    if Scanner.sniper then Scanner.ToggleSniper() end
    if Scanner.state == "replicate" then Scanner.state = "idle" end
    activeCommodity = nil
    inflight = nil
    pump()
    ns.BuyPopup.Clear()
end)

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
    if Scanner.state == "replicate" then
        Scanner.state = "replProcess"
        C_Timer.After(0.5, processReplicate)
    end
end)

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function() pump() end)

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, id)
    if waiting[id] then
        finish(id, "commodity")
    elseif id and Scanner.state == "idle" then
        offerFromResults(id, "commodity") -- you searched it yourself in the AH
    end
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, key)
    local id = type(key) == "table" and key.itemID
    if not id then return end
    if waiting[id] then
        finish(id, "item")
    elseif Scanner.state == "idle" then
        offerFromResults(id, "item")
    end
end)

-- Normal browsing: if a browse row's lowest price qualifies, look it up properly
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if not AH.GetBrowseResults then return end
    local results = AH.GetBrowseResults()
    if not results then return end
    local looked = 0
    for _, r in ipairs(results) do
        local id = r.itemKey and r.itemKey.itemID
        if id and r.minPrice and r.minPrice > 0 and not r.containsOwnerItem and judge(id, r.minPrice) and looked < 10 then
            looked = looked + 1
            Scanner.Search(id, function(kind) offerFromResults(id, kind) end)
        end
    end
end)

ns.On("COMMODITY_PRICE_UPDATED", function(_, unitPrice, totalPrice)
    local c = activeCommodity
    if not c then return end
    c.quoting, c.ready = false, true
    if totalPrice and totalPrice ~= c.buyout then
        c.profit = (c.profit or 0) - (totalPrice - c.buyout) -- price moved since we looked
        c.buyout = totalPrice
        c.priceChanged = true
    end
    refreshPopup(c)
end)

ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
    local c = activeCommodity
    if not c then return end
    activeCommodity = nil
    c.quoting, c.ready, c.gone = false, false, true
    refreshPopup(c)
end)

ns.On("COMMODITY_PURCHASE_FAILED", function()
    ns.Print("|cffff5555commodity purchase failed|r (price changed or the hold expired)")
end)
