-- AHelper: Buy popup for vendor flips, watchlist hits and below-market deals
local _, ns = ...
local Popup = {}
ns.BuyPopup = Popup

local queue = {}
local f

local REASONS = {
    vendor = "|cff00ff00Below vendor price|r - buy and sell to any vendor",
    watch  = "|cff66ccffWatchlist price hit|r",
    deal   = "|cffffcc00Far below market value|r - buy and relist",
}

local function sound()
    if not ns.settings.popupSound then return end
    local id = SOUNDKIT and (SOUNDKIT.AUCTION_WINDOW_OPEN or SOUNDKIT.RAID_WARNING) or 8959
    PlaySound(id, "Master")
end

local function build()
    f = CreateFrame("Frame", "AHelperBuyPopup", UIParent, "BackdropTemplate")
    f:SetSize(340, 170)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    f.reason = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.reason:SetPoint("TOP", 0, -18)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(36, 36)
    f.icon:SetPoint("TOPLEFT", 22, -42)

    local iconBtn = CreateFrame("Frame", nil, f)
    iconBtn:SetAllPoints(f.icon)
    iconBtn:EnableMouse(true)
    iconBtn:SetScript("OnEnter", function(self)
        if not f.cand then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. f.cand.itemID)
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", GameTooltip_Hide)

    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 0)
    f.name:SetPoint("RIGHT", -20, 0)
    f.name:SetJustifyH("LEFT")

    f.line1 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.line1:SetPoint("TOPLEFT", f.icon, "BOTTOMLEFT", 0, -6)
    f.line1:SetJustifyH("LEFT")
    f.line2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.line2:SetPoint("TOPLEFT", f.line1, "BOTTOMLEFT", 0, -3)
    f.line2:SetJustifyH("LEFT")
    f.line3 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.line3:SetPoint("TOPLEFT", f.line2, "BOTTOMLEFT", 0, -3)
    f.line3:SetJustifyH("LEFT")

    f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.counter:SetPoint("TOPRIGHT", -20, -20)

    local function button(label, x, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(95, 24)
        b:SetPoint("BOTTOMLEFT", x, 16)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end

    f.buy = button("Buy", 20, function()
        local cand = f.cand
        if not cand then return end
        local res = ns.Scanner.TryBuy(cand)
        if res == "bought" then
            ns.Print(string.format("bought %s x%d for %s (expected profit %s)",
                cand.link or cand.name or cand.itemID, cand.count, ns.Money(cand.buyout), ns.Money(cand.profit)))
            Popup.Next()
        elseif res == "searching" then
            -- the result list changed; the auction is re-offered (one more click) once the search finds it
            ns.Print("relocating auction, it will pop up again in a moment...")
            Popup.Next()
        else
            Popup.Next()
        end
    end)
    button("Skip", 122, function() Popup.Next() end)
    button("Ignore item", 224, function()
        if f.cand then
            AHelperDB.ignore[f.cand.itemID] = true
            ns.Print("ignoring", f.cand.name or f.cand.itemID, "(/ahh ignore again to undo)")
            local id = f.cand.itemID
            for i = #queue, 1, -1 do if queue[i].itemID == id then table.remove(queue, i) end end
            f.cand = nil
            Popup.Show()
        end
    end)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() Popup.Clear() end)
    f:Hide()
end

function Popup.Show()
    if not f then build() end
    local cand = queue[1]
    f.cand = cand
    if not cand then f:Hide() return end
    local name, link, quality = ns.ItemInfo(cand.itemID)
    cand.name = cand.name or name
    cand.link = cand.link or link
    local tex = GetItemIcon and GetItemIcon(cand.itemID) or select(10, GetItemInfo(cand.itemID))
    f.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    f.name:SetText((color and color.hex or "|cffffffff") .. (cand.name or ("item " .. cand.itemID)) .. "|r x" .. cand.count)
    f.reason:SetText(REASONS[cand.reason] or cand.reason)
    f.line1:SetText("Buyout: " .. ns.Money(cand.buyout) .. "   (" .. ns.Money(cand.buyout / cand.count) .. " each)")
    if cand.reason == "vendor" then
        f.line2:SetText("Vendor value: " .. ns.Money(cand.value))
    else
        f.line2:SetText("Market value: " .. ns.Money(cand.value))
    end
    f.line3:SetText("Profit: " .. ns.Money(cand.profit) .. (cand.owner and ("   seller: " .. cand.owner) or ""))
    f.counter:SetText(#queue > 1 and ("1 of " .. #queue) or "")
    f.buy:Enable()
    f.buy:SetText("Buy")
    if not f:IsShown() then sound() end
    f:Show()
end

function Popup.Push(cand, front)
    -- highest profit first, but keep the shown one on top
    if front then
        table.insert(queue, 1, cand)
    else
        local pos = #queue + 1
        for i = 2, #queue do
            if (cand.profit or 0) > (queue[i].profit or 0) then pos = i break end
        end
        if #queue == 0 then pos = 1 end
        table.insert(queue, pos, cand)
    end
    if #queue > 200 then table.remove(queue) end
    Popup.Show()
end

function Popup.Next()
    table.remove(queue, 1)
    Popup.Show()
end

function Popup.Clear()
    wipe(queue)
    if f then f.cand = nil; f:Hide() end
end
