-- Overview tab: your totals, recent discoveries, and every family's progress
-- (click a family to open it in the Dex).
local _, ns = ...

local SUMMARY_WIDTH = 330
local RECENT_COUNT = 6
local RECENT_ROW_HEIGHT = 34
local FAMILY_ROW_HEIGHT = 38
local GOLD = { 1, 0.82, 0 }
local GREEN = { 0.25, 0.75, 0.25 }
local QUEST_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"

local function TimeAgo(timestamp)
    local seconds = time() - timestamp
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return ("%d min ago"):format(seconds / 60) end
    if seconds < 86400 then return ("%d h ago"):format(seconds / 3600) end
    return ("%d days ago"):format(seconds / 86400)
end

local function ColorCode(color)
    return ("|cff%02x%02x%02x"):format(math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
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
    local view = CreateFrame("Frame", nil, parent)

    -- Left: totals and recent discoveries.
    local summary = ns.Skin.CreateInset(view)
    summary:SetPoint("TOPLEFT", view, "TOPLEFT", ui.INSET.left, -ui.BODY_TOP)
    summary:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", ui.INSET.left, ui.INSET.bottom)
    summary:SetWidth(SUMMARY_WIDTH)
    view.summary = summary

    local title = summary:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", ui.PAD, -ui.PAD)
    title:SetText("Your PetDex")

    view.bigNumber = summary:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    view.bigNumber:SetTextColor(1, 1, 1)
    view.bigNumber:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    view.bigLabel = summary:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    view.bigLabel:SetPoint("BOTTOMLEFT", view.bigNumber, "BOTTOMRIGHT", 8, 3)
    view.bigLabel:SetText("beasts documented")

    view.seenBar = ns.Skin.CreateBar(summary, 14, GOLD)
    view.seenBar:SetPoint("TOPLEFT", view.bigNumber, "BOTTOMLEFT", 0, -10)
    view.seenBar:SetPoint("RIGHT", summary, "RIGHT", -ui.PAD, 0)
    view.seenText = view.seenBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.seenText:SetPoint("CENTER")

    view.tamedBar = ns.Skin.CreateBar(summary, 14, GREEN)
    view.tamedBar:SetPoint("TOPLEFT", view.seenBar, "BOTTOMLEFT", 0, -8)
    view.tamedBar:SetPoint("RIGHT", summary, "RIGHT", -ui.PAD, 0)
    view.tamedText = view.tamedBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.tamedText:SetPoint("CENTER")

    view.rarities = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    view.rarities:SetPoint("TOPLEFT", view.tamedBar, "BOTTOMLEFT", 0, -12)
    view.rarities:SetJustifyH("LEFT")
    view.rarities:SetSpacing(4)

    local recentTitle = summary:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    recentTitle:SetPoint("TOPLEFT", view.rarities, "BOTTOMLEFT", 0, -18)
    recentTitle:SetText("Recent discoveries")
    view.recentEmpty = summary:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.recentEmpty:SetPoint("TOPLEFT", recentTitle, "BOTTOMLEFT", 0, -8)
    view.recentEmpty:SetText("Target beasts in the wild to document them.")

    view.recent = {}
    for i = 1, RECENT_COUNT do
        local row = CreateRow(summary, RECENT_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", recentTitle, "BOTTOMLEFT", -6, -4 - (i - 1) * RECENT_ROW_HEIGHT)
        row:SetPoint("RIGHT", summary, "RIGHT", -ui.PAD + 6, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 6, -3)
        row.when = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.when:SetPoint("TOPRIGHT", -6, -4)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row:SetScript("OnClick", function(self)
            ns.Skin.PlaySound("select")
            ns:OpenDexAt(self.lookID)
        end)
        view.recent[i] = row
    end

    -- Right: every family's progress.
    local familyPanel = ns.Skin.CreateInset(view)
    familyPanel:SetPoint("TOPLEFT", summary, "TOPRIGHT", 4, 0)
    familyPanel:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -ui.INSET.right, ui.INSET.bottom)
    view.familyPanel = familyPanel
    local familiesTitle = familyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    familiesTitle:SetPoint("TOPLEFT", ui.PAD, -ui.PAD)
    familiesTitle:SetText("Families")
    local hint = familyPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", familiesTitle, "RIGHT", 10, -1)
    hint:SetText("Click a family to open it in the Dex")
    view.familyRows = {}
    return view
end

local function FamilyRow(view, index)
    local row = view.familyRows[index]
    if row then return row end
    row = CreateRow(view.familyPanel, FAMILY_ROW_HEIGHT)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 6, -4)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("TOPRIGHT", -6, -5)
    row.bar = ns.Skin.CreateBar(row, 6, GOLD)
    row.bar:SetPoint("BOTTOMLEFT", 6, 8)
    row.bar:SetPoint("BOTTOMRIGHT", -6, 8)
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
    view.seenBar:SetValue(total > 0 and seen / total or 0)
    view.seenText:SetText(("Documented  %d%%"):format(total > 0 and math.floor(seen / total * 100) or 0))
    view.tamedBar:SetValue(total > 0 and tamed / total or 0)
    view.tamedText:SetText(("Tamed  %d / %d"):format(tamed, total))
    local rarityLines = {}
    for _, rarity in ipairs({ "rare", "unique" }) do
        local counts = byRarity[rarity] or { total = 0, seen = 0 }
        table.insert(rarityLines, ("%s%s|r documented  %d / %d"):format(ColorCode(ns.RARITY_COLORS[rarity]),
            ui.RARITY_LABELS[rarity], counts.seen, counts.total))
    end
    view.rarities:SetText(table.concat(rarityLines, "\n"))

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
            row:Show()
        else
            row:Hide()
        end
    end

    -- Families, in two columns.
    local panelWidth = view.familyPanel:GetWidth()
    local columns = panelWidth > 400 and 2 or 1
    local columnWidth = (panelWidth - ui.PAD * (columns + 1)) / columns
    local rowsPerColumn = math.ceil(#families / columns)
    for index, family in ipairs(families) do
        local row = FamilyRow(view, index)
        local column = math.floor((index - 1) / rowsPerColumn)
        local line = (index - 1) % rowsPerColumn
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", view.familyPanel, "TOPLEFT", ui.PAD + column * (columnWidth + ui.PAD),
            -(ui.PAD + 34 + line * FAMILY_ROW_HEIGHT))
        row:SetWidth(columnWidth)
        row.familyName = family.name
        row.name:SetText(family.name)
        row.count:SetText(("%d / %d   |cff40c040%d tamed|r"):format(family.seen, family.total, family.tamed))
        row.bar:SetValue(family.total > 0 and family.seen / family.total or 0)
        row:Show()
    end
    for i = #families + 1, #view.familyRows do
        view.familyRows[i]:Hide()
    end
end

ns.DexViews.overview = { Create = Create, Refresh = Refresh }
