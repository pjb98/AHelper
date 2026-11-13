-- AHelper: auction house scanning (GetAll full scan, sniper, passive browse checks) and buying
local _, ns = ...
local Scanner = {}
ns.Scanner = Scanner

Scanner.ahOpen = false
Scanner.state = "idle"     -- idle | fullWait | fullProcess | snipeWait | buyWait
Scanner.seen = {}          -- signatures already offered in a popup this session
Scanner.sniper = false

local CHUNK = 400          -- auctions processed per frame during a full scan

local function playerName() return UnitName("player") end

local function status(msg)
    Scanner.statusText = msg
    if ns.UI and ns.UI.SetStatus then ns.UI.SetStatus(msg) end
end
Scanner.Status = status

local function blizzBrowseEvents(enable)
    if not AuctionFrameBrowse then return end
    if enable then
        AuctionFrameBrowse:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    else
        AuctionFrameBrowse:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
    end
end

---------------------------------------------------------------------------
-- Opportunity checks (shared by full scan, sniper and normal browsing)
---------------------------------------------------------------------------
-- Returns a candidate table or nil
function Scanner.Evaluate(index, itemID, count, buyout, owner, vendorUnit, name, link)
    if not itemID or not buyout or buyout <= 0 or not count or count <= 0 then return nil end
    if owner and owner == playerName() then return nil end
    if AHelperDB.ignore[itemID] then return nil end
    local S = ns.settings
    if buyout > S.maxPopupSpend then return nil end

    local unit = buyout / count
    local cand

    -- 1) Vendor flip: guaranteed profit, no AH cut, no risk
    if S.vendorPopup and vendorUnit and vendorUnit > 0 then
        local profit = vendorUnit * count - buyout
        if profit >= S.vendorMinProfit then
            cand = { reason = "vendor", value = vendorUnit * count, profit = profit }
        end
    end

    -- 2) Watchlist price threshold
    local w = AHelperDB.watch[itemID]
    if not cand and w and w.maxPrice and unit <= w.maxPrice then
        local mkt = ns.Data.Market(itemID)
        cand = { reason = "watch", value = (mkt or w.maxPrice) * count,
                 profit = mkt and (mkt * count * (1 - S.ahCut) - buyout) or 0 }
    end

    -- 3) Far below market value
    if not cand and S.dealPopup then
        local mkt, nDays = ns.Data.Market(itemID)
        if mkt and nDays >= S.dealMinSamples and unit <= mkt * S.dealMaxPct / 100 then
            local profit = mkt * count * (1 - S.ahCut) - buyout
            if profit >= S.dealMinProfit then
                cand = { reason = "deal", value = mkt * count, profit = profit }
            end
        end
    end

    if not cand then return nil end
    cand.index, cand.itemID, cand.count, cand.buyout, cand.owner = index, itemID, count, buyout, owner
    cand.name, cand.link = name, link
    cand.sig = (owner or "?") .. ":" .. itemID .. ":" .. count .. ":" .. buyout
    return cand
end

local function offer(cand)
    if not cand or Scanner.seen[cand.sig] then return end
    Scanner.seen[cand.sig] = true
    ns.BuyPopup.Push(cand)
end

local function readAuction(i)
    local name, _, count, quality, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = GetAuctionItemInfo("list", i)
    return name, count, quality, buyout, owner, itemID
end

local function vendorPrice(itemID)
    local _, _, _, vendor = ns.ItemInfo(itemID)
    if vendor then return vendor end
    local rec = ns.RealmDB().items[itemID]
    return rec and rec.v
end

-- Check the currently loaded page of results (normal browsing or sniper)
local function checkCurrentPage()
    local batch = GetNumAuctionItems("list")
    if batch > 50 then return end -- a GetAll result is still loaded; already checked during the scan
    for i = 1, batch do
        local name, count, _, buyout, owner, itemID = readAuction(i)
        if itemID then
            offer(Scanner.Evaluate(i, itemID, count, buyout, owner, vendorPrice(itemID), name,
                GetAuctionItemLink("list", i)))
        end
    end
end

---------------------------------------------------------------------------
-- Full scan (GetAll)
---------------------------------------------------------------------------
function Scanner.StartFullScan()
    if not Scanner.ahOpen then ns.Print("open the auction house first") return end
    if Scanner.state ~= "idle" then ns.Print("busy:", Scanner.state) return end
    local _, canAll = CanSendAuctionQuery()
    if not canAll then
        local last = ns.RealmDB().lastScan or 0
        local wait = math.max(0, 900 - (time() - last))
        ns.Print(string.format("full scan not available yet (server allows one every 15 min, ~%d:%02d left)",
            math.floor(wait / 60), wait % 60))
        return
    end
    if Scanner.sniper then Scanner.ToggleSniper() end
    Scanner.state = "fullWait"
    blizzBrowseEvents(false)
    status("Full scan: waiting for server...")
    QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
end

local function finishFull(agg, total)
    local ts = time()
    local sold = ns.Data.RecordScan(agg, ts)
    Scanner.state = "idle"
    blizzBrowseEvents(true)
    local n = 0
    for _ in pairs(agg) do n = n + 1 end
    status(string.format("Scan done: %d auctions, %d items. Est. %d items sold since last scan.", total, n, sold))
    ns.Print(string.format("scan complete: %d auctions / %d unique items", total, n))
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local function processFull()
    Scanner.state = "fullProcess"
    local total = GetNumAuctionItems("list")
    local agg, i = {}, 1
    local ticker
    local function step()
        if not Scanner.ahOpen then
            ticker:Cancel()
            Scanner.state = "idle"
            blizzBrowseEvents(true)
            status("Scan aborted: auction house closed")
            return
        end
        local stop = math.min(total, i + CHUNK - 1)
        for idx = i, stop do
            local name, count, quality, buyout, owner, itemID = readAuction(idx)
            if itemID and buyout and buyout > 0 and count and count > 0 then
                local a = agg[itemID]
                if not a then
                    a = { name = name, q = quality, v = vendorPrice(itemID), auctions = {} }
                    agg[itemID] = a
                end
                a.name = a.name or name
                table.insert(a.auctions, { buyout / count, count, owner, GetAuctionItemTimeLeft("list", idx) })
                offer(Scanner.Evaluate(idx, itemID, count, buyout, owner, a.v, name, nil))
            end
        end
        i = stop + 1
        status(string.format("Full scan: processing %d / %d", stop, total))
        if i > total then
            ticker:Cancel()
            finishFull(agg, total)
        end
    end
    ticker = C_Timer.NewTicker(0.01, step)
end

---------------------------------------------------------------------------
-- Sniper: cycles exact-match searches for watchlist + farm items, reading the first pages
---------------------------------------------------------------------------
local snipeQueue, snipeIdx, snipePage = {}, 0, 0
local SNIPE_PAGES = 2

local function buildSnipeQueue()
    wipe(snipeQueue)
    local added = {}
    local function add(id)
        if added[id] then return end
        local name = ns.ItemInfo(id)
        if name then table.insert(snipeQueue, name); added[id] = true end
    end
    for id in pairs(AHelperDB.watch) do add(id) end
    for _, e in ipairs(ns.FarmDB) do add(e.id) end
end

local function snipeNext()
    if not Scanner.sniper or not Scanner.ahOpen then return end
    if Scanner.state ~= "idle" and Scanner.state ~= "snipeWait" then
        C_Timer.After(1, snipeNext) return
    end
    if not CanSendAuctionQuery() then C_Timer.After(0.3, snipeNext) return end
    if #snipeQueue == 0 then buildSnipeQueue() end
    if #snipeQueue == 0 then ns.Print("nothing to snipe (watchlist empty, item info not cached yet)") Scanner.ToggleSniper() return end
    if snipePage == 0 then snipeIdx = snipeIdx % #snipeQueue + 1 end
    local name = snipeQueue[snipeIdx]
    Scanner.state = "snipeWait"
    Scanner.snipeName = name
    status(string.format("Sniper: %s (page %d) [%d/%d]", name, snipePage + 1, snipeIdx, #snipeQueue))
    QueryAuctionItems(name, nil, nil, snipePage, nil, nil, false, true, nil)
end

function Scanner.ToggleSniper()
    if not Scanner.sniper and not Scanner.ahOpen then ns.Print("open the auction house first") return end
    Scanner.sniper = not Scanner.sniper
    if Scanner.sniper then
        buildSnipeQueue()
        snipePage = 0
        ns.Print("sniper started:", #snipeQueue, "items in rotation")
        snipeNext()
    else
        if Scanner.state == "snipeWait" then Scanner.state = "idle" end
        status("Sniper stopped")
    end
    if ns.UI and ns.UI.UpdateButtons then ns.UI.UpdateButtons() end
end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------
local function matches(i, cand)
    local _, count, _, buyout, _, itemID = readAuction(i)
    return itemID == cand.itemID and count == cand.count and buyout == cand.buyout
end

-- Must be called from a hardware event (button click). Returns "bought", "searching" or "gone".
function Scanner.TryBuy(cand)
    if not Scanner.ahOpen then ns.Print("auction house is closed") return "gone" end
    if GetMoney() < cand.buyout then ns.Print("not enough gold") return "gone" end
    local idx
    if cand.index and matches(cand.index, cand) then
        idx = cand.index
    else
        local n = GetNumAuctionItems("list")
        for i = 1, n do
            if matches(i, cand) then idx = i break end
        end
    end
    if idx then
        PlaceAuctionBid("list", idx, cand.buyout)
        table.insert(AHelperDB.purchases, { t = time(), id = cand.itemID, c = cand.count, p = cand.buyout,
            r = cand.reason, e = math.floor(cand.profit or 0), realm = ns.RealmKey() })
        while #AHelperDB.purchases > 500 do table.remove(AHelperDB.purchases, 1) end
        return "bought"
    end
    -- not in the current result list: search for it so the next click can buy it
    local name = cand.name or ns.ItemInfo(cand.itemID)
    if name and CanSendAuctionQuery() and Scanner.state == "idle" then
        Scanner.state = "buyWait"
        Scanner.buyCand = cand
        QueryAuctionItems(name, nil, nil, 0, nil, nil, false, true, nil)
        return "searching"
    end
    return "gone"
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
    if Scanner.state ~= "fullProcess" then
        Scanner.state = "idle"
        blizzBrowseEvents(true)
    end
    ns.BuyPopup.Clear()
end)

ns.On("AUCTION_ITEM_LIST_UPDATE", function()
    local st = Scanner.state
    if st == "fullWait" then
        -- small delay lets the client finish filling the list
        Scanner.state = "fullProcess"
        C_Timer.After(0.5, processFull)
    elseif st == "snipeWait" then
        Scanner.state = "idle"
        checkCurrentPage()
        local batch, total = GetNumAuctionItems("list")
        if (snipePage + 1) * 50 < total and snipePage + 1 < SNIPE_PAGES then
            snipePage = snipePage + 1
        else
            snipePage = 0
        end
        C_Timer.After(snipePage > 0 and 0.3 or ns.settings.snipeInterval, snipeNext)
    elseif st == "buyWait" then
        Scanner.state = "idle"
        local cand = Scanner.buyCand
        Scanner.buyCand = nil
        if cand then
            local n = GetNumAuctionItems("list")
            for i = 1, n do
                if matches(i, cand) then
                    cand.index = i
                    ns.BuyPopup.Push(cand, true) -- re-offer at the front: one more click buys it
                    return
                end
            end
            ns.Print("that auction is gone")
        end
    elseif st == "idle" then
        checkCurrentPage() -- normal manual browsing
    end
end)
