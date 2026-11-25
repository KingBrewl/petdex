-- Hunt tab: every tameable beast in the zone you're in, as a checklist.
-- Undocumented beasts first (rares at the top), with level, whether you can
-- tame it now, respawn time and a map pin. Click a row to open it in the
-- Dex. Follows you as you change zones.
local _, ns = ...

local ROW_HEIGHT = 30
local TOP = 74 -- title, summary and column headings
local PAGER_HEIGHT = 40
local QUEST_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local ICONS = {
    new = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    seen = "Interface\\RaidFrame\\ReadyCheck-Ready",
    tamed = "Interface\\Icons\\Ability_Hunter_BeastTaming",
}
local STATE_ORDER = { new = 1, seen = 2, tamed = 3 }
local RARITY_ORDER = { unique = 1, rare = 2, common = 3 }

-- Column x offsets inside a row.
local COL = { icon = 8, name = 34, level = 250, rarity = 320, taming = 400, respawn = 510 }

local function DurationText(minSeconds, maxSeconds)
    local function part(seconds)
        if seconds >= 3600 then return math.floor(seconds / 3600 + 0.5), "h" end
        return math.floor(seconds / 60 + 0.5), "min"
    end
    local low, lowUnit = part(minSeconds)
    local high, highUnit = part(maxSeconds)
    if low == high and lowUnit == highUnit then return low .. " " .. lowUnit end
    if lowUnit == highUnit then return low .. "-" .. high .. " " .. highUnit end
    return low .. " " .. lowUnit .. " - " .. high .. " " .. highUnit
end

local function MinLevel(beast)
    local level = beast.level
    if type(level) == "table" then return level[1] end
    return level or beast.minLevel
end

-- new: one of its looks isn't in your dex yet; seen: all documented;
-- tamed: documented and one of its looks tamed.
local function BeastState(npcID)
    local anyNew, anyTamed = false, false
    for _, lookID in ipairs(ns:GetLooks(npcID)) do
        local status = ns:GetLookStatus(lookID)
        if not status then anyNew = true end
        if status == "tamed" then anyTamed = true end
    end
    if anyNew then return "new" end
    return anyTamed and "tamed" or "seen"
end

local function BeastsInZone(zone)
    local rows = {}
    local function consider(npcID, beast)
        if ns:GetBeastZone(beast) == zone then
            table.insert(rows, { npcID = npcID, beast = beast, state = BeastState(npcID) })
        end
    end
    for npcID, beast in pairs(ns.Beasts) do
        consider(npcID, beast)
    end
    for npcID, beast in pairs(ns.db.discovered) do
        if beast.verified then consider(npcID, beast) end
    end
    table.sort(rows, function(a, b)
        if a.state ~= b.state then return STATE_ORDER[a.state] < STATE_ORDER[b.state] end
        local ra, rb = RARITY_ORDER[a.beast.rarity] or 9, RARITY_ORDER[b.beast.rarity] or 9
        if ra ~= rb then return ra < rb end
        local la, lb = MinLevel(a.beast) or 0, MinLevel(b.beast) or 0
        if la ~= lb then return la < lb end
        return (a.beast.name or "") < (b.beast.name or "")
    end)
    return rows
end

local function Text(row, column, template, justify)
    local text = row:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    text:SetPoint("LEFT", COL[column], 0)
    if justify then text:SetJustifyH(justify) end
    return text
end

local function CreateRow(view, index)
    local row = CreateFrame("Button", nil, view.panel)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture(QUEST_HIGHLIGHT, "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", COL.icon, 0)
    row.name = Text(row, "name", "GameFontNormal")
    row.name:SetWidth(COL.level - COL.name - 8)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.level = Text(row, "level")
    row.rarity = Text(row, "rarity")
    row.taming = Text(row, "taming")
    row.respawn = Text(row, "respawn", "GameFontHighlightSmall")

    row.pin = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.pin:SetSize(60, 20)
    row.pin:SetPoint("RIGHT", -8, 0)
    row.pin:SetText("Pin")
    row.pin:SetScript("OnClick", function(self)
        local data = self:GetParent().data
        if data then
            ns:PinLook({ beast = data.beast, label = data.beast.name, status = data.state ~= "new" or nil })
        end
    end)
    row:SetScript("OnClick", function(self)
        local lookID = self.data and ns:GetLooks(self.data.npcID)[1]
        if lookID then
            ns.Skin.PlaySound("select")
            ns:OpenDexAt(lookID)
        end
    end)
    view.rows[index] = row
    return row
end

local function FillRow(row, data)
    row.data = data
    local beast = data.beast
    row.icon:SetTexture(ICONS[data.state])
    if data.state == "tamed" then
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        row.icon:SetTexCoord(0, 1, 0, 1)
    end
    local color = ns.RARITY_COLORS[beast.rarity] or ns.RARITY_COLORS.common
    if data.state == "new" then
        row.name:SetText("???")
        row.name:SetTextColor(0.62, 0.6, 0.55)
    else
        row.name:SetText(beast.name)
        row.name:SetTextColor(color[1], color[2], color[3])
    end
    row.level:SetText(ns.DexUI.LevelText(beast) or "")
    row.rarity:SetText(ns.DexUI.RARITY_LABELS[beast.rarity] or "")
    row.rarity:SetTextColor(color[1], color[2], color[3])

    local minLevel = MinLevel(beast)
    local playerLevel = UnitLevel("player") or 0
    local taming
    if not minLevel then
        taming = ""
    elseif playerLevel >= minLevel then
        taming = "|cff40ff40Now|r"
    else
        taming = ("|cffff9933Level %d|r"):format(minLevel)
    end
    if beast.elite then
        taming = taming .. "  |cffff9933Elite|r"
    end
    row.taming:SetText(taming)

    if beast.spawns == 0 then
        row.respawn:SetText("Summoned")
    elseif beast.respawn then
        row.respawn:SetText("Every " .. DurationText(beast.respawn[1], beast.respawn[2]))
    else
        row.respawn:SetText("")
    end
    row.pin:SetShown((beast.spawns or 0) > 0 and beast.map ~= nil)
end

local function Create(parent)
    local ui = ns.DexUI
    local view = CreateFrame("Frame", nil, parent)
    view.rows = {}
    view.page = 1

    local panel = ns.Skin.CreateInset(view)
    panel:SetPoint("TOPLEFT", view, "TOPLEFT", ui.INSET.left, -ui.BODY_TOP)
    panel:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -ui.INSET.right, ui.INSET.bottom)
    view.panel = panel

    view.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.title:SetPoint("TOPLEFT", ui.PAD, -ui.PAD)
    view.summary = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.summary:SetPoint("LEFT", view.title, "RIGHT", 12, -1)

    -- Column headings.
    local headings = CreateFrame("Frame", nil, panel)
    headings:SetPoint("TOPLEFT", ui.PAD, -(TOP - 20))
    headings:SetPoint("TOPRIGHT", -ui.PAD, -(TOP - 20))
    headings:SetHeight(18)
    for column, label in pairs({ name = "Beast", level = "Level", rarity = "Rarity", taming = "Tame", respawn = "Respawn" }) do
        local text = headings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", COL[column], 0)
        text:SetText(label)
    end

    view.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    view.empty:SetPoint("TOP", 0, -(TOP + 30))
    view.empty:SetText("No tameable beasts known in this zone.")

    -- The spellbook's page buttons.
    view.pageText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.pageText:SetPoint("BOTTOM", 0, 14)
    view.prev = ns.Skin.CreatePageButton(panel, "Prev")
    view.prev:SetPoint("RIGHT", view.pageText, "LEFT", -10, 0)
    view.next = ns.Skin.CreatePageButton(panel, "Next")
    view.next:SetPoint("LEFT", view.pageText, "RIGHT", 10, 0)
    local function Turn(delta)
        local before = view.page
        view.page = math.max(1, math.min(view.pages or 1, view.page + delta))
        if view.page ~= before then
            ns.Skin.PlaySound("page")
            ns.DexViews.hunt.Refresh(view)
        end
    end
    view.prev:SetScript("OnClick", function() Turn(-1) end)
    view.next:SetScript("OnClick", function() Turn(1) end)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta) Turn(-delta) end)
    return view
end

local function Refresh(view)
    local ui = ns.DexUI
    local zone = ns:GetPlayerZone() or "Unknown zone"
    if view.zone ~= zone then
        view.zone, view.page = zone, 1
    end
    local rows = BeastsInZone(zone)

    local documented, newRares = 0, 0
    for _, data in ipairs(rows) do
        if data.state ~= "new" then
            documented = documented + 1
        elseif data.beast.rarity ~= "common" then
            newRares = newRares + 1
        end
    end
    view.title:SetText("Hunt: " .. zone)
    view.summary:SetText(#rows > 0 and ("%d of %d documented here%s"):format(documented, #rows,
        newRares > 0 and ("  ·  |cff6aa8ff%d rare%s to find|r"):format(newRares, newRares == 1 and "" or "s") or "") or "")
    view.empty:SetShown(#rows == 0)

    local perPage = math.max(1, math.floor((view.panel:GetHeight() - TOP - PAGER_HEIGHT) / ROW_HEIGHT))
    view.pages = math.max(1, math.ceil(#rows / perPage))
    view.page = math.min(view.page, view.pages)
    local first = (view.page - 1) * perPage
    local shown = 0
    for i = 1, perPage do
        local data = rows[first + i]
        if not data then break end
        shown = i
        local row = view.rows[i] or CreateRow(view, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", view.panel, "TOPLEFT", ui.PAD, -(TOP + (i - 1) * ROW_HEIGHT))
        row:SetPoint("RIGHT", view.panel, "RIGHT", -ui.PAD, 0)
        FillRow(row, data)
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

ns.DexViews.hunt = { Create = Create, Refresh = Refresh }

-- Follow the player into new zones.
ns:On("ZONE_CHANGED_NEW_AREA", function()
    if ns.db and ns.db.settings.tab == "hunt" then
        ns:OnCollectionChanged()
    end
end)
