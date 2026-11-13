-- AHelper: price history storage and statistics
local _, ns = ...
local Data = {}
ns.Data = Data

-- Session-only snapshot of the most recent full scan:
-- Data.current[itemID] = { min = unit copper, qty = n, n = auctions, auctions = { {unit, count, owner}, ... } sorted }
Data.current = {}
Data.currentTime = 0
Data.prevSigs = nil   -- signatures from the previous full scan (for sale estimation)
Data.prevTime = 0

local MARKET_FRACTION = 0.15 -- market value = weighted avg of cheapest 15% of listed quantity

---------------------------------------------------------------------------
-- Market value of one scan's listings for an item
---------------------------------------------------------------------------
local function scanMarket(auctions, totalQty)
    -- auctions sorted by unit price ascending
    local want = math.max(1, math.floor(totalQty * MARKET_FRACTION + 0.5))
    local got, sum = 0, 0
    for _, a in ipairs(auctions) do
        local take = math.min(a[2], want - got)
        sum = sum + a[1] * take
        got = got + take
        if got >= want then break end
    end
    local mkt = got > 0 and (sum / got) or nil
    -- drop obvious outliers: if cheapest listing is < 20% of the next-cheapest bracket, ignore it for market purposes
    return mkt
end

---------------------------------------------------------------------------
-- Record a full scan.
-- agg[itemID] = { name, q, v, auctions = { {unit, count, owner, timeLeft}, ... } }
---------------------------------------------------------------------------
function Data.RecordScan(agg, ts)
    local realm = ns.RealmDB()
    local items = realm.items
    local day = ns.DayNumber(ts)
    local hour = ns.Hour(ts)
    local sigs = {}
    local gapOK = Data.prevSigs and (ts - Data.prevTime) <= 7200
    local soldTotal = 0

    wipe(Data.current)
    for itemID, a in pairs(agg) do
        table.sort(a.auctions, function(x, y) return x[1] < y[1] end)
        local qty = 0
        for _, au in ipairs(a.auctions) do qty = qty + au[2] end
        local minUnit = a.auctions[1][1]
        local mkt = scanMarket(a.auctions, qty)

        Data.current[itemID] = { min = minUnit, qty = qty, n = #a.auctions, auctions = a.auctions, mkt = mkt }

        local rec = items[itemID]
        if not rec then
            rec = { d = {}, h = {} }
            items[itemID] = rec
        end
        rec.name = a.name or rec.name
        rec.q = a.q or rec.q
        rec.v = a.v or rec.v

        -- reference market before adding this scan, for time-of-day ratios
        local ref = Data.Market(itemID)

        -- daily bucket
        local d = rec.d[day]
        if not d then d = { m = 0, n = 0, q = 0, mn = minUnit, s = 0 }; rec.d[day] = d end
        d.m = d.m + mkt
        d.n = d.n + 1
        d.q = d.q + qty
        if minUnit < d.mn then d.mn = minUnit end

        -- hourly bucket (relative to the item's own reference price, so trends don't masquerade as hour effects)
        local h = rec.h[hour]
        if not h then h = { n = 0, r = 0, r2 = 0, p = 0, q = 0 }; rec.h[hour] = h end
        if ref and ref > 0 then
            local ratio = mkt / ref
            if ratio > 0.2 and ratio < 5 then -- ignore wild outliers
                h.n = h.n + 1
                h.r = h.r + ratio
                h.r2 = h.r2 + ratio * ratio
                h.p = h.p + mkt
                h.q = h.q + qty
            end
        end

        rec.last = { t = ts, min = minUnit, mkt = mkt, qty = qty, n = #a.auctions }

        -- signatures for sale estimation
        local s = {}
        for _, au in ipairs(a.auctions) do
            local key = (au[3] or "?") .. ":" .. au[2] .. ":" .. au[1]
            local e = s[key]
            if e then e.n = e.n + 1; if (au[4] or 0) > e.tl then e.tl = au[4] or 0 end
            else s[key] = { n = 1, tl = au[4] or 0, c = au[2] } end
        end
        sigs[itemID] = s

        -- auctions that were Long/Very Long last scan and are gone now were (very likely) bought
        if gapOK then
            local prev = Data.prevSigs[itemID]
            if prev then
                local sold = 0
                for key, e in pairs(prev) do
                    if e.tl >= 3 then
                        local now = s[key]
                        local missing = e.n - (now and now.n or 0)
                        if missing > 0 then sold = sold + missing * e.c end
                    end
                end
                d.s = d.s + sold
                soldTotal = soldTotal + sold
            end
        end
    end

    -- items that vanished completely from the AH since last scan
    if gapOK then
        for itemID, prev in pairs(Data.prevSigs) do
            if not agg[itemID] and items[itemID] then
                local sold = 0
                for _, e in pairs(prev) do if e.tl >= 3 then sold = sold + e.n * e.c end end
                if sold > 0 then
                    local rec = items[itemID]
                    local d = rec.d[day]
                    if not d then
                        d = { m = 0, n = 0, q = 0, mn = rec.last and rec.last.min or 0, s = 0 }
                        rec.d[day] = d
                    end
                    d.s = d.s + sold
                end
            end
        end
    end

    Data.prevSigs = sigs
    Data.prevTime = ts
    Data.currentTime = ts
    realm.scans = (realm.scans or 0) + 1
    realm.lastScan = ts
    realm.scanDays = realm.scanDays or {}
    realm.scanDays[day] = (realm.scanDays[day] or 0) + 1
    return soldTotal
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
-- Market value: recency-weighted average of daily market values over the last `days` days.
function Data.Market(itemID, days, realmKey)
    local rec = ns.RealmDB(realmKey).items[itemID]
    days = days or 14
    local own, ownDays = nil, 0
    if rec and rec.d then
        local today = ns.DayNumber()
        local wsum, sum, nDays = 0, 0, 0
        for day, d in pairs(rec.d) do
            local age = today - day
            if age >= 0 and age < days and d.n > 0 and d.m > 0 then
                local w = 1 / (1 + age * 0.15)
                sum = sum + (d.m / d.n) * w
                wsum = wsum + w
                nDays = nDays + 1
            end
        end
        if wsum > 0 then own, ownDays = sum / wsum, nDays end
    end
    -- Not enough of our own history yet: use TSM's realm market value (only for the default lookup on this realm)
    local trust = ns.settings.dealMinSamples or 3
    if ownDays < trust and not realmKey and days == 14 and ns.TSM then
        local t = ns.TSM.Market(itemID)
        if t then return t, trust, "tsm" end
    end
    if own then return own, ownDays end
    if ns.settings.useAuctionator and Auctionator and Auctionator.API and Auctionator.API.v1 then
        local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "AHelper", itemID)
        if ok and price and price > 0 then return price, 0, "auctionator" end
    end
    return nil, 0
end

-- Average number of items estimated sold per day (only counting days where we scanned at least twice).
function Data.SoldPerDay(itemID, days)
    -- TSM's region sales data is far more reliable than our vanished-listing estimate
    if ns.TSM then
        local t = ns.TSM.SoldPerDay(itemID)
        if t then return t, 99, "tsm" end
    end
    local realm = ns.RealmDB()
    local rec = realm.items[itemID]
    if not rec then return 0, 0 end
    days = days or 14
    local today = ns.DayNumber()
    local total, nDays = 0, 0
    for day, cnt in pairs(realm.scanDays or {}) do
        if today - day < days and cnt >= 2 then
            nDays = nDays + 1
            local d = rec.d[day]
            if d then total = total + (d.s or 0) end
        end
    end
    if nDays == 0 then return 0, 0 end
    return total / nDays, nDays
end

-- Average quantity listed per scan
function Data.AvgQty(itemID, days)
    local rec = ns.RealmDB().items[itemID]
    if not rec then return 0 end
    days = days or 14
    local today = ns.DayNumber()
    local q, n = 0, 0
    for day, d in pairs(rec.d) do
        if today - day < days and d.n > 0 then q = q + d.q; n = n + d.n end
    end
    return n > 0 and q / n or 0
end

-- Average of daily minimum prices across `days`
function Data.AvgMin(itemID, days)
    local rec = ns.RealmDB().items[itemID]
    if not rec then return nil end
    local today = ns.DayNumber()
    local s, n = 0, 0
    for day, d in pairs(rec.d) do
        if today - day < days and d.mn and d.mn > 0 then s = s + d.mn; n = n + 1 end
    end
    return n > 0 and s / n or nil
end

-- Hour-of-day profile: returns table [hour] = { mean ratio, stddev, n, avgPrice, avgQty }
function Data.HourProfile(itemID)
    local rec = ns.RealmDB().items[itemID]
    if not rec or not rec.h then return nil end
    local out = {}
    for hour, h in pairs(rec.h) do
        if h.n > 0 then
            local mean = h.r / h.n
            local var = math.max(0, h.r2 / h.n - mean * mean)
            out[hour] = { mean = mean, sd = math.sqrt(var), n = h.n, price = h.p / h.n, qty = h.q / h.n }
        end
    end
    return out
end

-- Median of market values seen on OTHER realms/factions (own scans from alts + external data file)
function Data.CrossRealm(itemID)
    local here = ns.RealmKey()
    local vals, sources = {}, {}
    for key, realm in pairs(AHelperDB.realms) do
        if key ~= here then
            local rec = realm.items[itemID]
            if rec and rec.last and (time() - rec.last.t) < 14 * 86400 then
                local m = Data.Market(itemID, 14, key)
                if m then table.insert(vals, m); table.insert(sources, key) end
            end
        end
    end
    local ext = AHelper_External and AHelper_External.realms
    if ext then
        for key, items in pairs(ext) do
            if key ~= here and not AHelperDB.realms[key] then
                local e = items[itemID]
                if e and e[1] and e[1] > 0 then table.insert(vals, e[1]); table.insert(sources, key) end
            end
        end
    end
    if #vals == 0 then return nil, 0 end
    table.sort(vals)
    local mid = math.floor((#vals + 1) / 2)
    local median = (#vals % 2 == 1) and vals[mid] or (vals[mid] + vals[mid + 1]) / 2
    return median, #vals, sources
end

---------------------------------------------------------------------------
-- Housekeeping
---------------------------------------------------------------------------
function Data.Prune()
    local keep = ns.settings.historyDays or 45
    local today = ns.DayNumber()
    for _, realm in pairs(AHelperDB.realms) do
        for itemID, rec in pairs(realm.items) do
            local any = false
            for day in pairs(rec.d or {}) do
                if today - day > keep then rec.d[day] = nil else any = true end
            end
            if not any and (not rec.last or today - ns.DayNumber(rec.last.t) > keep) then
                realm.items[itemID] = nil
            end
        end
        for day in pairs(realm.scanDays or {}) do
            if today - day > keep then realm.scanDays[day] = nil end
        end
    end
end
