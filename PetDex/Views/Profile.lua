-- Profile tab: your hunter rank, points and where they come from, the
-- 40-rank track, and every achievement with its progress.
local _, ns = ...

local LEFT_WIDTH = 340
local NODE_SIZE = 28
local NODES_PER_ROW = 8
local ROW_HEIGHT = 44
local TOP = 78 -- heading and summary above the achievement list
local PAGER_HEIGHT = 40
local GOLD = { 0.9, 0.7, 0.15 }
local ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"
local ACHIEVEMENT_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function Round(parent, size, texture)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexture(texture)
    if parent.CreateMaskTexture then
        local mask = parent:CreateMaskTexture()
        mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end
    return icon
end

-- Achievements to show first: closest to done, then earned (newest first).
local function SortAchievements(list)
    table.sort(list, function(a, b)
        if (a.earned ~= nil) ~= (b.earned ~= nil) then return a.earned == nil end
        if a.earned then return a.earned > b.earned end
        local pa = a.target > 0 and a.current / a.target or 0
        local pb = b.target > 0 and b.current / b.target or 0
        if pa ~= pb then return pa > pb end
        return a.def.name < b.def.name
    end)
end

local function Create(parent)
    local ui = ns.DexUI
    local Skin = ns.Skin
    local view = CreateFrame("Frame", nil, parent)
    view.rows, view.page = {}, 1

    -- Left: rank, points and the rank track.
    local left = Skin.CreateInset(view)
    left:SetPoint("TOPLEFT", view, "TOPLEFT", ui.INSET.left, -ui.BODY_TOP)
    left:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", ui.INSET.left, ui.INSET.bottom)
    left:SetWidth(LEFT_WIDTH)

    local emblem = Round(left, 64, ICON)
    emblem:SetPoint("TOPLEFT", ui.PAD + 4, -ui.PAD - 4)
    local ring = left:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(108, 108)
    ring:SetPoint("TOPLEFT", emblem, "TOPLEFT", -9, 9)

    view.rank = left:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    view.rank:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 16, -6)
    view.title = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    view.title:SetPoint("TOPLEFT", view.rank, "BOTTOMLEFT", 0, -4)
    view.points = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.points:SetPoint("TOPLEFT", view.title, "BOTTOMLEFT", 0, -4)

    view.nextBar = Skin.CreateSkillBar(left, 20, GOLD)
    view.nextBar:SetPoint("TOPLEFT", emblem, "BOTTOMLEFT", -4, -16)
    view.nextBar:SetPoint("RIGHT", left, "RIGHT", -ui.PAD, 0)

    view.breakdown = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.breakdown:SetPoint("TOPLEFT", view.nextBar, "BOTTOMLEFT", 4, -10)
    view.breakdown:SetJustifyH("LEFT")
    view.breakdown:SetSpacing(3)

    local trackTitle = Skin.CreateHeading(left, "Rank track")
    trackTitle:SetPoint("TOPLEFT", view.breakdown, "BOTTOMLEFT", 0, -18)
    trackTitle.divider:SetPoint("RIGHT", left, "RIGHT", -ui.PAD, 0)

    -- 40 nodes; every fifth (a new title) is larger.
    view.nodes = {}
    local spacing = (LEFT_WIDTH - 2 * ui.PAD) / NODES_PER_ROW
    for rank = 1, ns.MAX_RANK do
        local node = CreateFrame("Frame", nil, left)
        node:SetSize(spacing, spacing)
        local index = rank - 1
        node:SetPoint("TOPLEFT", trackTitle, "BOTTOMLEFT",
            -4 + (index % NODES_PER_ROW) * spacing, -16 - math.floor(index / NODES_PER_ROW) * spacing)
        local milestone = ns.RANK_TITLES[rank] ~= nil
        node.fill = Round(node, milestone and NODE_SIZE or NODE_SIZE - 8, "Interface\\Buttons\\WHITE8X8")
        node.fill:SetPoint("CENTER")
        node.label = node:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        node.label:SetPoint("CENTER", 0, 0)
        node.label:SetText(rank)
        node.rank = rank
        node:EnableMouse(true)
        node:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(("Rank %d  ·  %s"):format(self.rank, ns.RankTitle(self.rank)))
            GameTooltip:AddLine(("%d points"):format(ns.RankThreshold(self.rank)), 1, 1, 1)
            if ns.RANK_TITLES[self.rank] and self.rank > 1 then
                GameTooltip:AddLine("A new title", 0.4, 0.8, 1)
            end
            GameTooltip:Show()
        end)
        node:SetScript("OnLeave", function() GameTooltip:Hide() end)
        view.nodes[rank] = node
    end

    -- Right: achievements.
    local right = Skin.CreateInset(view)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 4, 0)
    right:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -ui.INSET.right, ui.INSET.bottom)
    view.right = right
    local achievementsTitle = Skin.CreateHeading(right, "Achievements", "GameFontNormalLarge")
    achievementsTitle:SetPoint("TOPLEFT", ui.PAD, -ui.PAD)
    achievementsTitle.divider:SetPoint("RIGHT", right, "RIGHT", -ui.PAD, 0)
    view.summary = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.summary:SetPoint("BOTTOMRIGHT", achievementsTitle.divider, "TOPRIGHT", 0, 2)

    view.pageText = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.pageText:SetPoint("BOTTOM", 0, 14)
    view.prev = Skin.CreatePageButton(right, "Prev")
    view.prev:SetPoint("RIGHT", view.pageText, "LEFT", -10, 0)
    view.next = Skin.CreatePageButton(right, "Next")
    view.next:SetPoint("LEFT", view.pageText, "RIGHT", 10, 0)
    local function Turn(delta)
        local before = view.page
        view.page = math.max(1, math.min(view.pages or 1, view.page + delta))
        if view.page ~= before then
            Skin.PlaySound("page")
            ns.DexViews.profile.Refresh(view)
        end
    end
    view.prev:SetScript("OnClick", function() Turn(-1) end)
    view.next:SetScript("OnClick", function() Turn(1) end)
    right:EnableMouseWheel(true)
    right:SetScript("OnMouseWheel", function(_, delta) Turn(-delta) end)
    return view
end

local function Row(view, index)
    local row = view.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, view.right)
    row:SetHeight(ROW_HEIGHT - 4)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexture(ACHIEVEMENT_ICON)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.points = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.points:SetPoint("RIGHT", -10, 0)
    row.points:SetWidth(40)
    row.points:SetJustifyH("RIGHT")
    row.bar = ns.Skin.CreateSkillBar(row, 18, GOLD)
    row.bar:SetPoint("RIGHT", row.points, "LEFT", -12, 0)
    row.bar:SetWidth(170)
    view.rows[index] = row
    return row
end

local function Refresh(view)
    local ui = ns.DexUI
    local score = ns:GetScore()

    -- Rank and points.
    view.rank:SetText(("Rank %d"):format(score.rank))
    view.title:SetText(ns.RankTitle(score.rank))
    view.points:SetText(("%d points"):format(score.total))
    if score.rank < ns.MAX_RANK then
        local low, high = ns.RankThreshold(score.rank), ns.RankThreshold(score.rank + 1)
        view.nextBar:SetProgress(score.total - low, high - low,
            ("%d / %d to rank %d"):format(score.total, high, score.rank + 1))
    else
        view.nextBar:SetProgress(1, 1, "The highest rank")
    end
    view.breakdown:SetText(("Documenting beasts:  %d points\nTaming beasts:  %d points\nAchievements:  %d points")
        :format(score.documenting, score.taming, score.achievements))

    for rank, node in ipairs(view.nodes) do
        if rank < score.rank then
            node.fill:SetVertexColor(0.55, 0.42, 0.1)
            node.label:SetTextColor(1, 0.9, 0.6)
        elseif rank == score.rank then
            node.fill:SetVertexColor(1, 0.82, 0)
            node.label:SetTextColor(0, 0, 0)
        else
            node.fill:SetVertexColor(0.18, 0.18, 0.2)
            node.label:SetTextColor(0.55, 0.55, 0.55)
        end
    end

    -- Achievements, paged.
    local list = ns:GetAchievements(score.stats)
    SortAchievements(list)
    local earned, earnedPoints = 0, 0
    for _, entry in ipairs(list) do
        if entry.earned then
            earned, earnedPoints = earned + 1, earnedPoints + entry.def.points
        end
    end
    view.summary:SetText(("%d of %d earned  ·  %d points"):format(earned, #list, earnedPoints))

    local perPage = math.max(1, math.floor((view.right:GetHeight() - TOP - PAGER_HEIGHT) / ROW_HEIGHT))
    view.pages = math.max(1, math.ceil(#list / perPage))
    view.page = math.min(view.page, view.pages)
    local first = (view.page - 1) * perPage
    local shown = 0
    for i = 1, perPage do
        local entry = list[first + i]
        if not entry then break end
        shown = i
        local row = Row(view, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", view.right, "TOPLEFT", ui.PAD - 6, -(TOP + (i - 1) * ROW_HEIGHT))
        row:SetPoint("RIGHT", view.right, "RIGHT", -ui.PAD + 6, 0)
        ns.Skin.Stripe(row, i)
        row.name:SetText(entry.def.name)
        row.desc:SetText(entry.def.desc)
        row.points:SetText(entry.def.points)
        if entry.earned then
            row.icon:SetDesaturated(false)
            row.icon:SetVertexColor(1, 1, 1)
            row.name:SetTextColor(1, 0.82, 0)
            row.bar:SetProgress(1, 1, "Earned " .. date("%d %b %Y", entry.earned))
        else
            row.icon:SetDesaturated(true)
            row.icon:SetVertexColor(0.6, 0.6, 0.6)
            row.name:SetTextColor(0.65, 0.65, 0.65)
            row.bar:SetProgress(entry.current, math.max(entry.target, 1))
        end
        row:Show()
    end
    for i = shown + 1, #view.rows do
        view.rows[i]:Hide()
    end
    view.pageText:SetText(view.pages > 1 and ("Page %d / %d"):format(view.page, view.pages) or "")
    view.prev:SetShown(view.pages > 1)
    view.next:SetShown(view.pages > 1)
    view.prev:SetEnabled(view.page > 1)
    view.next:SetEnabled(view.page < view.pages)
end

ns.DexViews.profile = { Create = Create, Refresh = Refresh }
