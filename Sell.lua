-- AHelper: posting helper on the Auctions tab (suggested price + one-click fill)
local _, ns = ...
local Sell = {}
ns.Sell = Sell

local btn, label

-- Suggested unit price for an item: undercut the cheapest competitor, but never dump far below market
function Sell.Suggest(itemID)
    local S = ns.settings
    local Data = ns.Data
    local mkt = Data.Market(itemID)
    local cur = Data.current[itemID]
    local _, _, _, vendor = ns.ItemInfo(itemID)
    local me = UnitName("player")
    local lowest
    if cur then
        for _, a in ipairs(cur.auctions) do
            if a[3] ~= me then lowest = a[1] break end
        end
    end
    local price, why
    if lowest and mkt then
        if lowest >= mkt * 0.8 then
            price, why = lowest - S.undercut, "undercut lowest"
        else
            price, why = mkt * 0.95, "lowest is a dump, priced near market"
        end
    elseif lowest then
        price, why = lowest - S.undercut, "undercut lowest"
    elseif mkt then
        price, why = mkt * 1.05, "none listed, above market"
    end
    if price and vendor and vendor > 0 and price * (1 - S.ahCut) < vendor then
        return vendor, "|cffff5555vendor it instead|r", true
    end
    return price and math.max(1, math.floor(price)), why
end

local function sellItem()
    local name, _, count, _, _, _, _, _, _, itemID = GetAuctionSellItemInfo()
    if not name then return nil end
    if not itemID and GetAuctionSellItemLink then itemID = ns.ItemIDFromLink(GetAuctionSellItemLink()) end
    return itemID, count or 1
end

local function update()
    if not btn then return end
    local itemID, count = sellItem()
    if not itemID then label:SetText("") btn:Disable() return end
    local unit, why, vendorIt = Sell.Suggest(itemID)
    if not unit then label:SetText("AHelper: no price data") btn:Disable() return end
    label:SetText("AHelper: " .. ns.Money(unit) .. " ea (" .. why .. ")")
    btn.unit = unit
    if vendorIt then btn:Disable() else btn:Enable() end
end

local function apply()
    local itemID, count = sellItem()
    if not itemID or not btn.unit then return end
    local stack = count
    if AuctionsStackSizeEntry and AuctionsStackSizeEntry:IsShown() then
        stack = AuctionsStackSizeEntry:GetNumber()
        if not stack or stack < 1 then stack = count end
    end
    local perUnit = AuctionFrameAuctions and AuctionFrameAuctions.priceType == 1
    local buyout = perUnit and btn.unit or btn.unit * stack
    local start = math.max(1, math.floor(buyout * 0.95))
    if MoneyInputFrame_SetCopper then
        if StartPrice then MoneyInputFrame_SetCopper(StartPrice, start) end
        if BuyoutPrice then MoneyInputFrame_SetCopper(BuyoutPrice, buyout) end
    end
end

local function build()
    if btn or not AuctionFrameAuctions then return end
    btn = CreateFrame("Button", "AHelperSellButton", AuctionFrameAuctions, "UIPanelButtonTemplate")
    btn:SetSize(110, 22)
    if AuctionsCreateAuctionButton then
        btn:SetPoint("BOTTOM", AuctionsCreateAuctionButton, "TOP", 0, 4)
    else
        btn:SetPoint("TOPLEFT", AuctionFrameAuctions, "TOPLEFT", 30, -300)
    end
    btn:SetText("AHelper price")
    btn:SetScript("OnClick", apply)
    btn:Disable()
    label = AuctionFrameAuctions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOM", btn, "TOP", 0, 3)
end

ns.On("AUCTION_HOUSE_SHOW", function() build() update() end)
ns.On("NEW_AUCTION_UPDATE", function()
    build()
    update()
    -- fill automatically the moment an item is dropped in, user can still edit
    if btn and btn:IsEnabled() then C_Timer.After(0.05, apply) end
end)
