-- Minimap button: left-click opens the dex, drag moves it around the
-- minimap's edge (the angle is saved). /petdex minimap shows or hides it.
local _, ns = ...

local ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"
local DEFAULT_ANGLE = 200 -- degrees, counter-clockwise from the right

local button

local function Position()
    local angle = math.rad(ns.db.settings.minimapAngle or DEFAULT_ANGLE)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- While dragging, follow the cursor around the minimap's centre.
local function OnDragUpdate()
    local centerX, centerY = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local dx, dy = cursorX / scale - centerX, cursorY / scale - centerY
    ns.db.settings.minimapAngle = math.deg(math.atan2(dy, dx)) % 360
    Position()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("PetDex")
    local stats = ns:GetStats()
    GameTooltip:AddLine(("Documented %d / %d beasts"):format(stats.seen, stats.total), 1, 1, 1)
    GameTooltip:AddLine(("Tamed %d"):format(stats.tamed), 1, 1, 1)
    if ns.GetScore then
        local score = ns:GetScore()
        GameTooltip:AddLine(("Rank %d  %s  ·  %d points"):format(score.rank, ns.RankTitle(score.rank), score.total),
            1, 0.82, 0)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to open the dex", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Drag to move this button", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreateButton()
    button = CreateFrame("Button", "PetDexMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- The standard round minimap button look: background, icon, gold ring.
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("CENTER")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if button.CreateMaskTexture then
        local mask = button:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function()
        ns:ToggleDex()
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns:UpdateMinimapButton()
    if not Minimap then return end
    if not button then
        if not self.db.settings.minimap then return end
        CreateButton()
    end
    Position()
    button:SetShown(self.db.settings.minimap)
end

ns:On("PLAYER_LOGIN", function()
    ns:UpdateMinimapButton()
end)
