-- Overview tab: your totals, recent discoveries, and every family's progress
-- laid out like the character window's Reputation pane (click a family to
-- open it in the Dex).
local _, ns = ...

local SUMMARY_WIDTH = 320
local RECENT_COUNT = 6
local RECENT_ROW_HEIGHT = 32
local FAMILY_ROW_HEIGHT = 26
local FAMILY_NAME_WIDTH = 104
local GOLD = { 0.9, 0.7, 0.15 }
local GREEN = { 0.25, 0.7, 0.25 }
local QUEST_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local TAMED_ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"

local function TimeAgo(timestamp)
    local seconds = time() - timestamp
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return ("%d min ago"):format(seconds / 60) end
    if seconds < 86400 then return ("%d h ago"):format(seconds / 3600) end
    return ("%d days ago"):format(seconds / 86400)
end

-- Looks documented most recently, newest first (by first sighting).
local function RecentDiscoveries(limit)
    local found, seenLook = {}, {}
    for npcID, record in pairs(ns.db.beasts) do
        local discovered = ns.db.discovered[npcID]
        local inDex = ns.Beasts[npcID] or (discovered and discovered.verified)
        if record.seen and inDex then
            for _, lookID in ipairs(ns:GetLooks(npcID)) do
                if ns:GetLookStatus(lookID) then
                    table.insert(found, { lookID = lookID, time = record.seen })
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.time > b.time end)
    local result = {}
    for _, entry in ipairs(found) do
        if not seenLook[entry.lookID] then
            seenLook[entry.lookID] = true
            table.insert(result, entry)
            if #result >= limit then break end
        end
    end
    return result
end

local function CreateRow(parent, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(height)
    row:SetHighlightTexture(QUEST_HIGHLIGHT, "ADD")
    return row
end

local function Create(parent)
    local ui = ns.DexUI
    local Skin = ns.Skin
    local view = CreateFrame("Frame", nil, parent)

    -- Left: totals and recent discoveries.
    local summary = Skin.CreateInset(view)
    summary:SetPoint("TOPLEFT", view, "TOPLEFT", ui.INSET.left, -ui.BODY_TOP)
    summary:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", ui.INSET.left, ui.INSET.bottom)
    summary:SetWidth(SUMMARY_WIDTH)
    view.summary = summary

    local title = Skin.CreateHeading(summary, "Your PetDex", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", ui.PAD, -ui.PAD)
    title.divider:SetPoint("RIGHT", summary, "RIGHT", -ui.PAD, 0)

    view.bigNumber = summary:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    view.bigNumber:SetTextColor(1, 1, 1)
    view.bigNumber:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -18)
    view.bigLabel = summary:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.bigLabel:SetPoint("BOTTOMLEFT", view.bigNumber, "BOTTOMRIGHT", 8, 2)
    view.bigLabel:SetText("documented")

    local function LabelledBar(label, color, anchor, gap)
        local text = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
        text:SetText(label)
        local bar = Skin.CreateSkillBar(summary, 20, color)
        bar:SetPoint("TOPLEFT", text, "BOTTOMLEFT", -2, -3)
        bar:SetPoint("RIGHT", summary, "RIGHT", -ui.PAD, 0)
        return bar
    end
    view.seenBar = LabelledBar("Documented", GOLD, view.bigNumber, 12)
    view.tamedBar = LabelledBar("Tamed", GREEN, view.seenBar, 8)
    view.rareBar = LabelledBar("Rare beasts documented", ns.RARITY_COLORS.rare, view.tamedBar, 8)
    view.uniqueBar = LabelledBar("Unique beasts documented", ns.RARITY_COLORS.unique, view.rareBar, 8)

    local recentTitle = Skin.CreateHeading(summary, "Recent discoveries")
    recentTitle:SetPoint("TOPLEFT", view.uniqueBar, "BOTTOMLEFT", 2, -20)
    recentTitle.divider:SetPoint("RIGHT", summary, "RIGHT", -ui.PAD, 0)
    view.recentEmpty = summary:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.recentEmpty:SetPoint("TOPLEFT", recentTitle, "BOTTOMLEFT", 0, -16)
    view.recentEmpty:SetText("Target beasts in the wild to document them.")

    view.recent = {}
    for i = 1, RECENT_COUNT do
        local row = CreateRow(summary, RECENT_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", recentTitle, "BOTTOMLEFT", -6, -14 - (i - 1) * RECENT_ROW_HEIGHT)
        row:SetPoint("RIGHT", summary, "RIGHT", -ui.PAD + 6, 0)
        Skin.Stripe(row, i)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 6, -3)
        row.when = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.when:SetPoint("TOPRIGHT", -6, -4)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row:SetScript("OnClick", function(self)
            Skin.PlaySound("select")
            ns:OpenDexAt(self.lookID)
        end)
        view.recent[i] = row
    end

    -- Right: every family's progress, like the Reputation pane.
    local familyPanel = Skin.CreateInset(view)
    familyPanel:SetPoint("TOPLEFT", summary, "TOPRIGHT", 4, 0)
    familyPanel:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -ui.INSET.right, ui.INSET.bottom)
    view.familyPanel = familyPanel
    local familiesTitle = Skin.CreateHeading(familyPanel, "Families", "GameFontNormalLarge")
    familiesTitle:SetPoint("TOPLEFT", ui.PAD, -ui.PAD)
    familiesTitle.divider:SetPoint("RIGHT", familyPanel, "RIGHT", -ui.PAD, 0)
    local hint = familyPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", familiesTitle.divider, "TOPRIGHT", 0, 2)
    hint:SetText("Click a family to open it in the Dex")
    view.familyRows = {}
    return view
end

local function FamilyRow(view, index)
    local row = view.familyRows[index]
    if row then return row end
    row = CreateRow(view.familyPanel, FAMILY_ROW_HEIGHT)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetWidth(FAMILY_NAME_WIDTH)
    row.name:SetJustifyH("LEFT")
    -- Tamed count with the Beast Taming icon, at the right.
    row.tamed = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.tamed:SetPoint("RIGHT", -6, 0)
    row.tamed:SetWidth(22)
    row.tamed:SetJustifyH("RIGHT")
    row.tamedIcon = row:CreateTexture(nil, "ARTWORK")
    row.tamedIcon:SetSize(14, 14)
    row.tamedIcon:SetPoint("RIGHT", row.tamed, "LEFT", -2, 0)
    row.tamedIcon:SetTexture(TAMED_ICON)
    row.tamedIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.bar = ns.Skin.CreateSkillBar(row, 20, GOLD)
    row.bar:SetPoint("LEFT", FAMILY_NAME_WIDTH + 10, 0)
    row.bar:SetPoint("RIGHT", row.tamedIcon, "LEFT", -6, 0)
    row:SetScript("OnClick", function(self)
        ns.Skin.PlaySound("tab")
        ns:OpenDexFamily(self.familyName)
    end)
    view.familyRows[index] = row
    return row
end

local function Refresh(view)
    local ui = ns.DexUI
    local families = ns:GetDexFamilies()

    -- Totals.
    local total, seen, tamed = 0, 0, 0
    local byRarity = {}
    for _, family in ipairs(families) do
        total, seen, tamed = total + family.total, seen + family.seen, tamed + family.tamed
        for _, group in ipairs(family.models) do
            for _, info in ipairs(group.looks) do
                local counts = byRarity[info.rarity] or { total = 0, seen = 0 }
                byRarity[info.rarity] = counts
                counts.total = counts.total + 1
                if info.status then counts.seen = counts.seen + 1 end
            end
        end
    end
    view.bigNumber:SetText(("%d / %d"):format(seen, total))
    view.seenBar:SetProgress(seen, total, ("%d / %d  (%d%%)"):format(seen, total,
        total > 0 and math.floor(seen / total * 100) or 0))
    view.tamedBar:SetProgress(tamed, total)
    local rare = byRarity.rare or { total = 0, seen = 0 }
    local unique = byRarity.unique or { total = 0, seen = 0 }
    view.rareBar:SetProgress(rare.seen, rare.total)
    view.uniqueBar:SetProgress(unique.seen, unique.total)

    -- Recent discoveries.
    local recent = RecentDiscoveries(RECENT_COUNT)
    view.recentEmpty:SetShown(#recent == 0)
    for i, row in ipairs(view.recent) do
        local entry = recent[i]
        local info = entry and ns:GetLookInfo(entry.lookID)
        if info then
            row.lookID = entry.lookID
            row.name:SetText(info.label)
            local color = ns.RARITY_COLORS[info.rarity] or ns.RARITY_COLORS.common
            row.name:SetTextColor(color[1], color[2], color[3])
            local zone = ns:GetBeastZone(info.beast)
            row.sub:SetText(zone and (info.family .. "  ·  " .. zone) or info.family)
            row.when:SetText(TimeAgo(entry.time))
            -- In a short window, drop rows that would hang below the panel.
            local bottom, panelBottom = row:GetBottom(), view.summary:GetBottom()
            row:SetShown(not (bottom and panelBottom and bottom < panelBottom + 4))
        else
            row:Hide()
        end
    end

    -- Families, in one or two columns depending on the width.
    local panelWidth = view.familyPanel:GetWidth()
    local columns = panelWidth > 520 and 2 or 1
    local columnWidth = (panelWidth - ui.PAD * (columns + 1)) / columns
    local rowsPerColumn = math.ceil(#families / columns)
    for index, family in ipairs(families) do
        local row = FamilyRow(view, index)
        local column = math.floor((index - 1) / rowsPerColumn)
        local line = (index - 1) % rowsPerColumn
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", view.familyPanel, "TOPLEFT", ui.PAD + column * (columnWidth + ui.PAD),
            -(ui.PAD + 40 + line * (FAMILY_ROW_HEIGHT + 4)))
        row:SetWidth(columnWidth)
        ns.Skin.Stripe(row, line + 1)
        row.familyName = family.name
        row.name:SetText(family.name)
        row.bar:SetProgress(family.seen, family.total)
        row.tamed:SetText(family.tamed)
        row:Show()
    end
    for i = #families + 1, #view.familyRows do
        view.familyRows[i]:Hide()
    end
end

ns.DexViews.overview = { Create = Create, Refresh = Refresh }
