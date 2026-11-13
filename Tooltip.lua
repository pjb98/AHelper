-- AHelper: item tooltip price lines
local _, ns = ...

local function hourLabel(h) return string.format("%02d:00", h) end

local function addLines(tt, itemID)
    if not ns.settings or not ns.settings.tooltip or not itemID then return end
    local Data = ns.Data
    local mkt, nDays = Data.Market(itemID)
    local rec = ns.RealmDB().items[itemID]
    if not mkt and not rec then return end
    tt:AddLine(" ")
    tt:AddDoubleLine("|cff33ff99AHelper|r market" .. (nDays > 0 and (" (" .. nDays .. "d)") or ""), ns.Money(mkt), 1, 1, 1, 1, 1, 1)
    if rec and rec.last then
        local age = time() - rec.last.t
        local ageTxt = age < 3600 and (math.floor(age / 60) .. "m") or age < 86400 and (math.floor(age / 3600) .. "h") or (math.floor(age / 86400) .. "d")
        tt:AddDoubleLine("  Lowest (" .. ageTxt .. " ago), " .. rec.last.qty .. " listed", ns.Money(rec.last.min), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local sold = Data.SoldPerDay(itemID)
    if sold > 0 then
        tt:AddDoubleLine("  Est. sold per day", string.format("%.1f", sold), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local ref, n = Data.CrossRealm(itemID)
    if ref then
        tt:AddDoubleLine("  Other realms (" .. n .. ")", ns.Money(ref), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local st = ns.Analysis.HourStats(itemID)
    if st and st.spread >= ns.settings.hourMinSpreadPct and st.z >= 2 then
        tt:AddDoubleLine("  Cheapest / priciest hour",
            hourLabel(st.lo) .. " / " .. hourLabel(st.hi) .. string.format(" (+%d%%)", st.spread), 0.8, 0.8, 0.8, 0.4, 1, 0.4)
    end
    local _, _, _, vendor = ns.ItemInfo(itemID)
    if vendor and vendor > 0 and mkt and mkt * (1 - ns.settings.ahCut) < vendor then
        tt:AddLine("  |cffff5555Worth more at a vendor than on the AH|r")
    end
    tt:Show()
end

local function onTooltip(tt)
    if tt.AHelperDone then return end
    local _, link = tt:GetItem()
    local id = ns.ItemIDFromLink(link)
    if id then
        tt.AHelperDone = true
        addLines(tt, id)
    end
end

local function clear(tt) tt.AHelperDone = nil end

ns.RegisterInit(function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
            if tt == GameTooltip or tt == ItemRefTooltip then onTooltip(tt) end
        end)
    else
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            tt:HookScript("OnTooltipSetItem", onTooltip)
        end
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        tt:HookScript("OnTooltipCleared", clear)
    end
end)
