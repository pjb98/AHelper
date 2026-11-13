-- AHelper: main window
local _, ns = ...
local UI = {}
ns.UI = UI

local ROWS, ROW_H = 18, 18
local frame, list, header, tabs, statusText, scanBtn, snipeBtn, hourChart, settingsPanel, watchPanel, infoText
local currentTab = 1
local data, offset = {}, 0
local sortKey, sortAsc = nil, false

---------------------------------------------------------------------------
-- Formatters
---------------------------------------------------------------------------
local fmt = {}
function fmt.money(v) return ns.Money(v, true) end
function fmt.pct(v) return v and ns.Pct(v) or "-" end
function fmt.num(v) if not v then return "-" end if v >= 10 then return tostring(math.floor(v + 0.5)) end return string.format("%.1f", v) end
function fmt.hour(v) return v and string.format("%02d:00", v) or "-" end
function fmt.text(v) return v and tostring(v) or "" end
function fmt.trend(v)
    if not v then return "-" end
    local c = v > 5 and "|cff40ff40" or v < -5 and "|cffff5050" or "|cffcccccc"
    return string.format("%s%+d%%|r", c, math.floor(v + 0.5))
end
function fmt.kind(v)
    local c = { vendor = "|cff40ff40", market = "|cffffcc00", dip = "|cff66ccff", ["cross-realm"] = "|cffff80ff" }
    return (c[v] or "") .. (v or "") .. "|r"
end
function fmt.z(v)
    if not v then return "-" end
    if v >= 4 then return "|cff40ff40strong|r" elseif v >= 3 then return "|cffffcc00good|r" end
    return "|cffccccccweak|r"
end

---------------------------------------------------------------------------
-- Tab definitions
---------------------------------------------------------------------------
local TABS = {
    {
        name = "Deals",
        info = "Listings from your last full scan that are below vendor price or far below market. Buy them from the popup, or click a row to search it.",
        rows = function() return ns.Analysis.Deals() end,
        sort = "profit",
        cols = {
            { key = "name", label = "Item", w = 190, f = "text", align = "LEFT" },
            { key = "kind", label = "Type", w = 60, f = "kind" },
            { key = "min", label = "Lowest", w = 85, f = "money" },
            { key = "mkt", label = "Market", w = 85, f = "money" },
            { key = "vendor", label = "Vendor", w = 70, f = "money" },
            { key = "units", label = "Units", w = 45, f = "num" },
            { key = "spend", label = "Cost", w = 85, f = "money" },
            { key = "profit", label = "Profit", w = 85, f = "money" },
        },
    },
    {
        name = "Flips",
        info = "Buy everything under 80% of market, relist at ~97%. 'Days' = how many days of normal sales it takes to sell what you'd buy (lower = safer).",
        rows = function() return ns.Analysis.Flips() end,
        sort = "profit",
        cols = {
            { key = "name", label = "Item", w = 180, f = "text", align = "LEFT" },
            { key = "buyUnder", label = "Buy under", w = 80, f = "money" },
            { key = "sellAt", label = "Sell at", w = 80, f = "money" },
            { key = "units", label = "Units", w = 45, f = "num" },
            { key = "spend", label = "Cost", w = 80, f = "money" },
            { key = "profit", label = "Profit", w = 80, f = "money" },
            { key = "roi", label = "ROI", w = 50, f = "pct" },
            { key = "sold", label = "Sold/d", w = 50, f = "num" },
            { key = "days", label = "Days", w = 40, f = "num" },
        },
    },
    {
        name = "Farming",
        info = "Open-world farmables. 'Gold/day' = estimated sales per day x market price: how much gold the market absorbs daily. Toggle 'all items' to rank everything.",
        rows = function() return ns.Analysis.Farming(UI.farmAll) end,
        sort = "turnover",
        cols = {
            { key = "name", label = "Item", w = 150, f = "text", align = "LEFT" },
            { key = "cat", label = "Type", w = 60, f = "text" },
            { key = "mkt", label = "Market", w = 75, f = "money" },
            { key = "stack", label = "Stack", w = 70, f = "money" },
            { key = "sold", label = "Sold/d", w = 50, f = "num" },
            { key = "turnover", label = "Gold/day", w = 70, f = "money" },
            { key = "trend", label = "7d vs 30d", w = 60, f = "trend" },
            { key = "where", label = "Where", w = 170, f = "text", align = "LEFT" },
        },
    },
    {
        name = "Time of Day",
        info = "Items whose price is consistently different by hour (server-local hours of YOUR clock). Buy at the cheap hour, post at the expensive one. Needs scans at many different hours over several days.",
        rows = function() return ns.Analysis.TimeOfDay() end,
        sort = "spread",
        topHeight = 70,
        cols = {
            { key = "name", label = "Item", w = 190, f = "text", align = "LEFT" },
            { key = "buyHour", label = "Buy at", w = 60, f = "hour" },
            { key = "loPrice", label = "Price", w = 85, f = "money" },
            { key = "sellHour", label = "Sell at", w = 60, f = "hour" },
            { key = "hiPrice", label = "Price", w = 85, f = "money" },
            { key = "spread", label = "Spread", w = 60, f = "pct" },
            { key = "z", label = "Consistency", w = 80, f = "z" },
            { key = "samples", label = "Samples", w = 60, f = "num" },
        },
    },
    {
        name = "Investments",
        info = "cross-realm: cheaper here than the median of other realms (your alts' scans + tools/fetch_prices.py data). dip: well below its own 30-day average while still selling.",
        rows = function() return ns.Analysis.Investments() end,
        sort = "upside",
        cols = {
            { key = "name", label = "Item", w = 190, f = "text", align = "LEFT" },
            { key = "kind", label = "Type", w = 80, f = "kind" },
            { key = "now", label = "Now", w = 85, f = "money" },
            { key = "ref", label = "Reference", w = 85, f = "money" },
            { key = "upside", label = "Upside", w = 60, f = "pct" },
            { key = "sold", label = "Sold/d", w = 55, f = "num" },
            { key = "note", label = "Basis", w = 100, f = "text" },
        },
    },
    {
        name = "Watchlist",
        info = "Items the sniper always checks. A listing at or below Max price triggers the buy popup. Right-click a row (any tab) to add/remove.",
        rows = function()
            local rows = {}
            for id, w in pairs(AHelperDB.watch) do
                local cur = ns.Data.current[id]
                table.insert(rows, { id = id, name = ns.Analysis.ItemName(id), maxPrice = w.maxPrice,
                    mkt = ns.Data.Market(id), min = cur and cur.min, sold = ns.Data.SoldPerDay(id) })
            end
            return rows
        end,
        sort = "name",
        bottomHeight = 34,
        cols = {
            { key = "name", label = "Item", w = 220, f = "text", align = "LEFT" },
            { key = "maxPrice", label = "Max price", w = 100, f = "money" },
            { key = "min", label = "Lowest now", w = 100, f = "money" },
            { key = "mkt", label = "Market", w = 100, f = "money" },
            { key = "sold", label = "Sold/d", w = 60, f = "num" },
        },
    },
    { name = "Settings", settings = true },
}

---------------------------------------------------------------------------
-- List rendering
---------------------------------------------------------------------------
local function sortData()
    if not sortKey then return end
    table.sort(data, function(a, b)
        local x, y = a[sortKey], b[sortKey]
        if x == nil and y == nil then return (a.name or "") < (b.name or "") end
        if x == nil then return false end
        if y == nil then return true end
        if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
        if x == y then return (a.name or "") < (b.name or "") end
        if sortAsc then return x < y else return x > y end
    end)
end

local function renderRows()
    local tab = TABS[currentTab]
    if tab.settings then return end
    local maxOff = math.max(0, #data - ROWS)
    if offset > maxOff then offset = maxOff end
    for i = 1, ROWS do
        local row = list.rows[i]
        local r = data[i + offset]
        if r then
            row.data = r
            for c, col in ipairs(tab.cols) do
                local fs = row.cells[c]
                local v = r[col.key]
                local text = fmt[col.f](v)
                if col.key == "name" then
                    local _, _, q = ns.ItemInfo(r.id)
                    local color = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
                    if color then text = color.hex .. text .. "|r" end
                    if AHelperDB.watch[r.id] then text = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t" .. text end
                end
                fs:SetText(text)
            end
            row:Show()
        else
            row.data = nil
            row:Hide()
        end
    end
    list.count:SetText(#data > 0 and string.format("%d-%d of %d", offset + 1, math.min(#data, offset + ROWS), #data) or "no results")
end

local function layoutColumns()
    local tab = TABS[currentTab]
    for _, h in ipairs(header.btns) do h:Hide() end
    for _, row in ipairs(list.rows) do for _, c in ipairs(row.cells) do c:Hide() end end
    if tab.settings then return end
    local x = 0
    for c, col in ipairs(tab.cols) do
        local h = header.btns[c]
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", header, "TOPLEFT", x, 0)
        h:SetWidth(col.w)
        h.text:SetText(col.label .. (sortKey == col.key and (sortAsc and " ^" or " v") or ""))
        h.text:SetJustifyH(col.align or "RIGHT")
        h.key = col.key
        h:Show()
        for _, row in ipairs(list.rows) do
            local fs = row.cells[c]
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", row, "LEFT", x + 2, 0)
            fs:SetWidth(col.w - 4)
            fs:SetJustifyH(col.align or "RIGHT")
            fs:Show()
        end
        x = x + col.w
    end
end

local function drawHourChart()
    if not hourChart then return end
    local hours = ns.Analysis.MarketHours()
    local lo, hi
    for h = 0, 23 do
        local v = hours[h]
        if v then lo = math.min(lo or v, v); hi = math.max(hi or v, v) end
    end
    for h = 0, 23 do
        local bar = hourChart.bars[h]
        local v = hours[h]
        if v and lo and hi and hi > lo then
            local t = (v - lo) / (hi - lo)
            bar:SetHeight(4 + t * 36)
            bar:SetColorTexture(0.2 + 0.8 * t, 1 - 0.7 * t, 0.2, 0.9)
            bar.v = v
        else
            bar:SetHeight(2)
            bar:SetColorTexture(0.4, 0.4, 0.4, 0.6)
            bar.v = v
        end
    end
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    local tab = TABS[currentTab]
    infoText:SetText(tab.info or "")
    hourChart:SetShown(tab.topHeight ~= nil)
    watchPanel:SetShown(tab.name == "Watchlist")
    UI.farmToggle:SetShown(tab.name == "Farming")
    settingsPanel:SetShown(tab.settings == true)
    list:SetShown(not tab.settings)
    header:SetShown(not tab.settings)
    if tab.settings then settingsPanel.Refresh() return end
    local top = -86 - (tab.topHeight or 0)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, top)
    header:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    if tab.topHeight then drawHourChart() end
    data = tab.rows() or {}
    sortData()
    layoutColumns()
    renderRows()
end

function UI.SetStatus(msg)
    if statusText then statusText:SetText(msg or "") end
end

function UI.UpdateButtons()
    if not frame then return end
    snipeBtn:SetText(ns.Scanner.sniper and "Stop sniper" or "Start sniper")
    local enabled = ns.Scanner.ahOpen
    scanBtn:SetEnabled(enabled)
    snipeBtn:SetEnabled(enabled)
end

local function selectTab(i)
    currentTab = i
    for j, t in ipairs(tabs) do
        if j == i then t:LockHighlight() else t:UnlockHighlight() end
    end
    sortKey = TABS[i].sort
    sortAsc = (sortKey == "name")
    offset = 0
    UI.Refresh()
end

---------------------------------------------------------------------------
-- Row actions
---------------------------------------------------------------------------
local function searchAH(id)
    local name = ns.ItemInfo(id) or (ns.RealmDB().items[id] or {}).name
    if not name or not AuctionFrame or not AuctionFrame:IsShown() then return end
    if AuctionFrameTab1 and AuctionFrameTab_OnClick then AuctionFrameTab_OnClick(AuctionFrameTab1) end
    if BrowseName then
        BrowseName:SetText(name)
        if ExactMatchCheckButton then ExactMatchCheckButton:SetChecked(true) end
        if AuctionFrameBrowse_Search then AuctionFrameBrowse_Search() end
    end
end

local function rowClick(self, button)
    local r = self.data
    if not r then return end
    if button == "RightButton" then
        if AHelperDB.watch[r.id] then
            AHelperDB.watch[r.id] = nil
            ns.Print("removed from watchlist:", r.name)
        else
            AHelperDB.watch[r.id] = {}
            ns.Print("added to watchlist:", r.name, "(set a max price on the Watchlist tab)")
        end
        UI.Refresh()
    elseif IsShiftKeyDown() then
        local _, link = ns.ItemInfo(r.id)
        if link then ChatEdit_InsertLink(link) end
    elseif IsControlKeyDown() then
        AHelperDB.ignore[r.id] = not AHelperDB.ignore[r.id] or nil
        ns.Print(AHelperDB.ignore[r.id] and "ignoring" or "unignored", r.name)
        UI.Refresh()
    else
        if TABS[currentTab].name == "Watchlist" then
            watchPanel.item:SetText(r.name)
            watchPanel.price:SetText(r.maxPrice and string.format("%.2f", r.maxPrice / 10000) or "")
        end
        searchAH(r.id)
    end
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------
local SETTINGS = {
    { key = "vendorPopup", label = "Popup: auctions cheaper than vendor price", type = "bool" },
    { key = "vendorMinProfit", label = "  Min vendor-flip profit (copper)", type = "num" },
    { key = "dealPopup", label = "Popup: auctions far below market value", type = "bool" },
    { key = "dealMaxPct", label = "  Max % of market to count as a deal", type = "num" },
    { key = "dealMinProfit", label = "  Min deal profit (copper)", type = "num" },
    { key = "dealMinSamples", label = "  Days of data needed before trusting market", type = "num" },
    { key = "maxPopupSpend", label = "Never offer a buy above (copper)", type = "num" },
    { key = "popupSound", label = "Play sound on popup", type = "bool" },
    { key = "snipeInterval", label = "Sniper delay between items (sec)", type = "num" },
    { key = "investMinPct", label = "Investment: min % below reference", type = "num" },
    { key = "hourMinSamples", label = "Time of day: samples per hour needed", type = "num" },
    { key = "hourMinSpreadPct", label = "Time of day: min spread %", type = "num" },
    { key = "undercut", label = "Undercut by (copper)", type = "num" },
    { key = "historyDays", label = "Days of history to keep", type = "num" },
    { key = "tooltip", label = "Show prices in item tooltips", type = "bool" },
    { key = "useAuctionator", label = "Use Auctionator prices when AHelper has none", type = "bool" },
    { key = "minimap", label = "Show minimap button", type = "bool", onChange = function() ns.Minimap.Update() end },
}

local function buildSettings()
    settingsPanel = CreateFrame("Frame", nil, frame)
    settingsPanel:SetPoint("TOPLEFT", 20, -90)
    settingsPanel:SetPoint("BOTTOMRIGHT", -20, 40)
    settingsPanel.widgets = {}
    for i, s in ipairs(SETTINGS) do
        local col = (i > 9) and 1 or 0
        local y = -((i - 1) % 9) * 30
        local x = col * 370
        if s.type == "bool" then
            local cb = CreateFrame("CheckButton", nil, settingsPanel, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("TOPLEFT", x, y)
            local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            t:SetText(s.label)
            cb:SetScript("OnClick", function(self)
                ns.settings[s.key] = self:GetChecked() and true or false
                if s.onChange then s.onChange() end
            end)
            cb.refresh = function() cb:SetChecked(ns.settings[s.key]) end
            settingsPanel.widgets[i] = cb
        else
            local eb = CreateFrame("EditBox", nil, settingsPanel, "InputBoxTemplate")
            eb:SetSize(70, 20)
            eb:SetPoint("TOPLEFT", x + 6, y - 2)
            eb:SetAutoFocus(false)
            local t = eb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            t:SetPoint("LEFT", eb, "RIGHT", 8, 0)
            t:SetText(s.label)
            local function commit(self)
                local v = tonumber(self:GetText())
                if v then ns.settings[s.key] = v end
                self:SetText(tostring(ns.settings[s.key]))
                self:ClearFocus()
            end
            eb:SetScript("OnEnterPressed", commit)
            eb:SetScript("OnEditFocusLost", commit)
            eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            eb.refresh = function() eb:SetText(tostring(ns.settings[s.key])) end
            settingsPanel.widgets[i] = eb
        end
    end
    local note = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 0, 0)
    note:SetPoint("RIGHT", 0, 0)
    note:SetJustifyH("LEFT")
    note:SetText("1g = 10000 copper. Purchases made through AHelper are logged in AHelperDB.purchases. /ahh for chat commands.")
    settingsPanel.Refresh = function()
        for _, w in pairs(settingsPanel.widgets) do w.refresh() end
    end
end

---------------------------------------------------------------------------
-- Watchlist editor
---------------------------------------------------------------------------
local function buildWatchPanel()
    watchPanel = CreateFrame("Frame", nil, frame)
    watchPanel:SetPoint("BOTTOMLEFT", 16, 34)
    watchPanel:SetPoint("BOTTOMRIGHT", -16, 34)
    watchPanel:SetHeight(28)
    local l1 = watchPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l1:SetPoint("LEFT", 0, 0)
    l1:SetText("Item:")
    local item = CreateFrame("EditBox", nil, watchPanel, "InputBoxTemplate")
    item:SetSize(220, 20)
    item:SetPoint("LEFT", l1, "RIGHT", 10, 0)
    item:SetAutoFocus(false)
    watchPanel.item = item
    local l2 = watchPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l2:SetPoint("LEFT", item, "RIGHT", 12, 0)
    l2:SetText("Max price (gold, blank = none):")
    local price = CreateFrame("EditBox", nil, watchPanel, "InputBoxTemplate")
    price:SetSize(70, 20)
    price:SetPoint("LEFT", l2, "RIGHT", 10, 0)
    price:SetAutoFocus(false)
    watchPanel.price = price
    local add = CreateFrame("Button", nil, watchPanel, "UIPanelButtonTemplate")
    add:SetSize(90, 22)
    add:SetPoint("LEFT", price, "RIGHT", 10, 0)
    add:SetText("Add / update")
    add:SetScript("OnClick", function()
        local text = item:GetText()
        local id = ns.ItemIDFromLink(text) or tonumber(text)
        if not id then
            local _, link = GetItemInfo(text)
            id = ns.ItemIDFromLink(link)
        end
        if not id then
            for itemID, rec in pairs(ns.RealmDB().items) do
                if rec.name and rec.name:lower() == text:lower() then id = itemID break end
            end
        end
        if not id then ns.Print("unknown item (try shift-clicking a link into the box)") return end
        local g = tonumber(price:GetText())
        AHelperDB.watch[id] = { maxPrice = g and math.floor(g * 10000) or nil }
        item:SetText("") price:SetText("")
        item:ClearFocus() price:ClearFocus()
        UI.Refresh()
    end)
    -- shift-click item links into the box
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if item:HasFocus() and link then item:SetText(link) end
    end)
end

---------------------------------------------------------------------------
-- Build main frame
---------------------------------------------------------------------------
local function build()
    frame = CreateFrame("Frame", "AHelperFrame", UIParent, "BackdropTemplate")
    frame:SetSize(780, 580)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetScript("OnShow", function() UI.UpdateButtons() UI.Refresh() end)
    table.insert(UISpecialFrames, "AHelperFrame")
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText("AHelper |cff888888v" .. ns.version .. "|r")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    scanBtn:SetSize(100, 22)
    scanBtn:SetPoint("TOPRIGHT", -40, -14)
    scanBtn:SetText("Full scan")
    scanBtn:SetScript("OnClick", function() ns.Scanner.StartFullScan() end)

    snipeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    snipeBtn:SetSize(100, 22)
    snipeBtn:SetPoint("RIGHT", scanBtn, "LEFT", -6, 0)
    snipeBtn:SetScript("OnClick", function() ns.Scanner.ToggleSniper() end)

    -- tabs
    tabs = {}
    local x = 16
    for i, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetHeight(22)
        b:SetText(t.name)
        b:SetWidth(b:GetFontString():GetStringWidth() + 24)
        b:SetPoint("TOPLEFT", x, -42)
        x = x + b:GetWidth() + 2
        b:SetScript("OnClick", function() selectTab(i) end)
        tabs[i] = b
    end

    infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    infoText:SetPoint("TOPLEFT", 18, -68)
    infoText:SetPoint("RIGHT", -18, 0)
    infoText:SetJustifyH("LEFT")
    infoText:SetHeight(14)

    UI.farmToggle = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    UI.farmToggle:SetSize(20, 20)
    UI.farmToggle:SetPoint("BOTTOMRIGHT", -110, 36)
    local ft = UI.farmToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ft:SetPoint("LEFT", UI.farmToggle, "RIGHT", 2, 0)
    ft:SetText("all items")
    UI.farmToggle:SetScript("OnClick", function(self) UI.farmAll = self:GetChecked() UI.Refresh() end)

    -- hour chart (Time of Day tab)
    hourChart = CreateFrame("Frame", nil, frame)
    hourChart:SetPoint("TOPLEFT", 16, -86)
    hourChart:SetPoint("RIGHT", -16, 0)
    hourChart:SetHeight(64)
    local hl = hourChart:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hl:SetPoint("TOPLEFT", 0, 0)
    hl:SetText("Whole market by hour (green = cheap, red = expensive):")
    hourChart.bars = {}
    for h = 0, 23 do
        local bar = hourChart:CreateTexture(nil, "ARTWORK")
        bar:SetWidth(22)
        bar:SetPoint("BOTTOMLEFT", hourChart, "BOTTOMLEFT", 4 + h * 30, 12)
        bar:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        bar:SetHeight(2)
        hourChart.bars[h] = bar
        local lbl = hourChart:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        lbl:SetPoint("TOP", bar, "BOTTOM", 0, -1)
        lbl:SetText(h)
    end

    -- header & list
    header = CreateFrame("Frame", nil, frame)
    header:SetHeight(18)
    header.btns = {}
    for c = 1, 10 do
        local h = CreateFrame("Button", nil, header)
        h:SetHeight(18)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h.text:SetPoint("LEFT", 2, 0)
        h.text:SetPoint("RIGHT", -2, 0)
        h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        h:SetScript("OnClick", function(self)
            if sortKey == self.key then sortAsc = not sortAsc else sortKey = self.key; sortAsc = (self.key == "name") end
            sortData() layoutColumns() renderRows()
        end)
        header.btns[c] = h
    end

    list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    list:SetHeight(ROWS * ROW_H)
    list.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.04)
        end
        row.cells = {}
        for c = 1, 10 do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetWordWrap(false)
            row.cells[c] = fs
        end
        row:SetScript("OnClick", rowClick)
        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.data.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click: search AH   Shift: link   Right: watchlist   Ctrl: ignore", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        list.rows[i] = row
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 3)
        renderRows()
    end)
    list.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    list.count:SetPoint("BOTTOMRIGHT", -20, 20)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", 20, 20)
    statusText:SetPoint("RIGHT", list.count, "LEFT", -10, 0)
    statusText:SetJustifyH("LEFT")
    local realm = ns.RealmDB()
    statusText:SetText(realm.lastScan and realm.lastScan > 0
        and ("Last full scan: " .. date("%a %H:%M", realm.lastScan) .. " (" .. (realm.scans or 0) .. " total)")
        or "No scans yet - open the AH and press Full scan.")

    buildSettings()
    buildWatchPanel()
    selectTab(1)
end

function UI.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

function UI.OnAHShow()
    if not frame then build() end
    UI.UpdateButtons()
    -- small launcher button on the auction frame
    if AuctionFrame and not UI.ahButton then
        local b = CreateFrame("Button", nil, AuctionFrame, "UIPanelButtonTemplate")
        b:SetSize(80, 20)
        b:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -60, -14)
        b:SetText("AHelper")
        b:SetScript("OnClick", UI.Toggle)
        UI.ahButton = b
    end
end

ns.On("AUCTION_HOUSE_CLOSED", function() if frame then UI.UpdateButtons() end end)
