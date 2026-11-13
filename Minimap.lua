-- AHelper: minimap button (no libraries). Left-click: open window. Right-click: full scan / sniper menu. Drag to move.
local _, ns = ...
local MM = {}
ns.Minimap = MM

local btn

local function position()
    local angle = math.rad(ns.settings.minimapAngle or 220)
    local radius = (Minimap:GetWidth() / 2) + 10
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    position()
end

local function build()
    btn = CreateFrame("Button", "AHelperMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 7, -6)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if not ns.Scanner.ahOpen then
                ns.Print("open the auction house to scan or snipe")
            elseif IsShiftKeyDown() then
                ns.Scanner.ToggleSniper()
            else
                ns.Scanner.StartFullScan()
            end
        else
            ns.UI.Toggle()
        end
    end)
    btn:SetScript("OnDragStart", function(self)
        icon:SetTexCoord(0, 1, 0, 1)
        self:SetScript("OnUpdate", onDragUpdate)
    end)
    btn:SetScript("OnDragStop", function(self)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        self:SetScript("OnUpdate", nil)
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff33ff99AHelper|r")
        local realm = ns.RealmDB()
        if realm.lastScan and realm.lastScan > 0 then
            GameTooltip:AddLine("Last full scan: " .. date("%a %H:%M", realm.lastScan), 0.8, 0.8, 0.8)
        end
        if ns.Scanner.sniper then GameTooltip:AddLine("Sniper running", 0.4, 1, 0.4) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
        GameTooltip:AddLine("Right-click: full scan (at AH)", 1, 1, 1)
        GameTooltip:AddLine("Shift-right-click: start / stop sniper", 1, 1, 1)
        GameTooltip:AddLine("Drag: move button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    position()
end

function MM.Update()
    if not btn then build() end
    btn:SetShown(ns.settings.minimap)
end

ns.RegisterInit(MM.Update)
