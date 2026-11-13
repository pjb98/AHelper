-- AHelper: TSM-style "% of market value" label on every auction house listing row.
-- Colors: blue < 50%, green < 80%, yellow up to 105%, orange up to 150%, red above. "VENDOR" = cheaper than vendor price.
local _, ns = ...
local P = {}
ns.MarketPct = P

local function color(pct)
    if pct < 50 then return "|cff40c0ff" end
    if pct < 80 then return "|cff40ff40" end
    if pct <= 105 then return "|cffffff80" end
    if pct <= 150 then return "|cffff9933" end
    return "|cffff4040"
end

-- Text for a listing of itemID at a per-unit price
function P.Text(itemID, unit)
    if not itemID or not unit or unit <= 0 then return "" end
    local _, _, _, vendor = ns.ItemInfo(itemID)
    if vendor and vendor > 0 and unit < vendor then return "|cff00ff96VENDOR|r" end
    local mkt = ns.Data.Market(itemID)
    if not mkt or mkt <= 0 then return "" end
    local pct = unit / mkt * 100
    return color(pct) .. (pct >= 999 and ">999" or tostring(math.floor(pct + 0.5))) .. "%|r"
end

local function label(frame)
    local fs = frame.AHelperPct
    if not fs then
        fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("RIGHT")
        frame.AHelperPct = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", frame, "RIGHT", ns.settings.pctOffset or -4, 0)
    return fs
end

---------------------------------------------------------------------------
-- Modern auction house (AuctionHouseFrame item lists)
---------------------------------------------------------------------------
local function rowInfo(list, frame, elementData)
    local d = frame.rowData
    if type(d) ~= "table" then
        if type(elementData) == "table" then
            d = elementData
        elseif elementData ~= nil and list.getEntry then
            local ok, r = pcall(list.getEntry, elementData)
            d = ok and r or nil
        end
    end
    if type(d) ~= "table" then return nil end
    -- commodity rows: unitPrice; item rows: buyoutAmount (price of ONE item); browse rows: minPrice
    local price = d.unitPrice or d.buyoutAmount or d.minPrice
    local id = d.itemID or (d.itemKey and d.itemKey.itemID)
    return id, price
end

local function decorate(list, frame, elementData)
    if not ns.settings.showPct then
        if frame.AHelperPct then frame.AHelperPct:SetText("") end
        return
    end
    local id, price = rowInfo(list, frame, elementData)
    label(frame):SetText(P.Text(id, price))
end

local hooked = {}
local function hookList(list)
    if not list or hooked[list] or not list.ScrollBox then return end
    hooked[list] = true
    local sb = list.ScrollBox
    local function refresh()
        if not sb.ForEachFrame then return end
        sb:ForEachFrame(function(frame, elementData)
            pcall(decorate, list, frame, elementData)
        end)
    end
    if sb.Update then hooksecurefunc(sb, "Update", refresh) end
    if list.RefreshScrollFrame then hooksecurefunc(list, "RefreshScrollFrame", refresh) end
end

---------------------------------------------------------------------------
-- Old Classic auction UI (BrowseButton1..8)
---------------------------------------------------------------------------
local function classicUpdate()
    local offset = (FauxScrollFrame_GetOffset and BrowseScrollFrame) and FauxScrollFrame_GetOffset(BrowseScrollFrame) or 0
    for i = 1, (NUM_BROWSE_TO_DISPLAY or 8) do
        local btn = _G["BrowseButton" .. i]
        if btn then
            local text = ""
            if ns.settings.showPct then
                local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = GetAuctionItemInfo("list", offset + i)
                if id and buyout and buyout > 0 and count and count > 0 then text = P.Text(id, buyout / count) end
            end
            label(btn):SetText(text)
        end
    end
end

ns.On("AUCTION_HOUSE_SHOW", function()
    local AHF = AuctionHouseFrame
    if AHF then
        local lists = {
            AHF.BrowseResultsFrame and AHF.BrowseResultsFrame.ItemList or false,
            AHF.CommoditiesBuyFrame and AHF.CommoditiesBuyFrame.ItemList or false,
            AHF.ItemBuyFrame and AHF.ItemBuyFrame.ItemList or false,
            AHF.CommoditiesSellList or false,
            AHF.ItemSellList or false,
        }
        for _, list in ipairs(lists) do
            if list then pcall(hookList, list) end
        end
    elseif AuctionFrameBrowse_Update and not P.classicHooked then
        P.classicHooked = true
        hooksecurefunc("AuctionFrameBrowse_Update", classicUpdate)
    end
end)
