-- Training tab: the beast-training planner. Pick a pet ability to see each
-- rank and the beasts that teach it, where they are, whether you can tame
-- them now, and a map pin.
--
-- What each beast teaches comes from the game data (Classic's spell sets,
-- Data/PetSpells.lua), overridden by what PetDex records right after tames.
-- What you already know comes from your Beast Training window
-- (char.training).
local _, ns = ...

local LIST_WIDTH = 230
local ABILITY_ROW_HEIGHT = 24
local RANK_HEADER_HEIGHT = 26
local BEAST_ROW_HEIGHT = 26
local TOP = 92
local PAGER_HEIGHT = 40
local QUEST_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local GREY = "|cff9d9d9d%s|r"

-- Abilities every family can learn (one of Bite/Claw, one of Dash/Dive).
local BASIC_ABILITIES = { "Bite", "Claw", "Cower", "Dash", "Dive" }

-- The ability list: basics, then each family's unique ability, plus any
-- other ability seen in recordings or the Beast Training window.
local function AbilityNames(taughtIndex, known)
    local names, seen = {}, {}
    local function add(name)
        if name and not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end
    for _, name in ipairs(BASIC_ABILITIES) do add(name) end
    local unique = {}
    for _, family in pairs(ns.Families or {}) do
        table.insert(unique, family.ability)
    end
    table.sort(unique)
    for _, name in ipairs(unique) do add(name) end
    local extra = {}
    for name in pairs(taughtIndex) do if not seen[name] then table.insert(extra, name) end end
    for name in pairs(known) do if not seen[name] then table.insert(extra, name) end end
    table.sort(extra)
    for _, name in ipairs(extra) do add(name) end
    return names
end

-- { [abilityName] = { [rank] = { npcID, ... } } } for every beast: what
-- PetDex recorded in game, else the game data (ns:GetTaught).
local function TaughtIndex()
    local index = {}
    local function add(npcID)
        local list = ns:GetTaught(npcID)
        for _, ability in ipairs(list or {}) do
            if not ability.passive then
                local rank = ns.RankNumber(ability.rank)
                index[ability.name] = index[ability.name] or {}
                index[ability.name][rank] = index[ability.name][rank] or {}
                table.insert(index[ability.name][rank], npcID)
            end
        end
    end
    for npcID in pairs(ns.Beasts) do add(npcID) end
    for npcID in pairs(ns.db.taught) do
        if not ns.Beasts[npcID] then add(npcID) end
    end
    return index
end

-- Families that can learn an ability ("All families", or the ones listed).
local function FamiliesFor(name)
    if name == "Bite" or name == "Claw" or name == "Cower" then return "Most families" end
    local matches = {}
    for familyName, family in pairs(ns.Families or {}) do
        if family.ability == name or family.move == name then
            table.insert(matches, familyName)
        end
    end
    table.sort(matches)
    return #matches > 0 and table.concat(matches, ", ") or nil
end

local function MinLevel(beast)
    local level = beast and beast.level
    if type(level) == "table" then return level[1] end
    return level or (beast and beast.minLevel)
end

local function Create(parent)
    local ui = ns.DexUI
    local Skin = ns.Skin
    local view = CreateFrame("Frame", nil, parent)
    view.abilityRows, view.lines, view.page, view.listOffset = {}, {}, 1, 0

    local list = Skin.CreateInset(view)
    list:SetPoint("TOPLEFT", view, "TOPLEFT", ui.INSET.left, -ui.BODY_TOP)
    list:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", ui.INSET.left, ui.INSET.bottom)
    list:SetWidth(LIST_WIDTH)
    view.list = list
    local listTitle = Skin.CreateHeading(list, "Pet abilities", "GameFontNormalLarge")
    listTitle:SetPoint("TOPLEFT", ui.PAD, -ui.PAD)
    listTitle.divider:SetPoint("RIGHT", list, "RIGHT", -ui.PAD, 0)
    view.listHint = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.listHint:SetPoint("BOTTOMLEFT", ui.PAD, ui.PAD)
    view.listHint:SetPoint("RIGHT", list, "RIGHT", -ui.PAD, 0)
    view.listHint:SetJustifyH("LEFT")
    -- The ability list scrolls with the mouse wheel.
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        view.listOffset = math.max(0, view.listOffset - delta * 3)
        ns.DexViews.training.Refresh(view)
    end)

    local detail = Skin.CreateInset(view)
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 4, 0)
    detail:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -ui.INSET.right, ui.INSET.bottom)
    view.detail = detail
    view.title = Skin.CreateHeading(detail, "", "GameFontNormalLarge")
    view.title:SetPoint("TOPLEFT", ui.PAD, -ui.PAD)
    view.title.divider:SetPoint("RIGHT", detail, "RIGHT", -ui.PAD, 0)
    view.summary = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    view.summary:SetPoint("TOPLEFT", view.title, "BOTTOMLEFT", 0, -18)
    view.summary:SetPoint("RIGHT", detail, "RIGHT", -ui.PAD, 0)
    view.summary:SetJustifyH("LEFT")
    view.summary:SetSpacing(3)
    view.empty = detail:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    view.empty:SetPoint("TOPLEFT", ui.PAD, -(TOP + 10))
    view.empty:SetPoint("RIGHT", detail, "RIGHT", -ui.PAD, 0)
    view.empty:SetJustifyH("LEFT")

    view.pageText = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.pageText:SetPoint("BOTTOM", 0, 14)
    view.prev = Skin.CreatePageButton(detail, "Prev")
    view.prev:SetPoint("RIGHT", view.pageText, "LEFT", -10, 0)
    view.next = Skin.CreatePageButton(detail, "Next")
    view.next:SetPoint("LEFT", view.pageText, "RIGHT", 10, 0)
    local function Turn(delta)
        local before = view.page
        view.page = math.max(1, math.min(view.pages or 1, view.page + delta))
        if view.page ~= before then
            Skin.PlaySound("page")
            ns.DexViews.training.Refresh(view)
        end
    end
    view.prev:SetScript("OnClick", function() Turn(-1) end)
    view.next:SetScript("OnClick", function() Turn(1) end)
    detail:EnableMouseWheel(true)
    detail:SetScript("OnMouseWheel", function(_, delta) Turn(-delta) end)
    return view
end

local function AbilityRow(view, index)
    local row = view.abilityRows[index]
    if row then return row end
    row = CreateFrame("Button", nil, view.list)
    row:SetHeight(ABILITY_ROW_HEIGHT)
    row:SetHighlightTexture(QUEST_HIGHLIGHT, "ADD")
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetTexture(QUEST_HIGHLIGHT)
    row.selected:SetBlendMode("ADD")
    row.selected:SetVertexColor(1, 0.82, 0, 0.6)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 8, 0)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnClick", function(self)
        if view.selected ~= self.ability then
            ns.Skin.PlaySound("select")
            view.selected, view.page = self.ability, 1
            ns.DexViews.training.Refresh(view)
        end
    end)
    view.abilityRows[index] = row
    return row
end

-- A line in the detail list: a rank heading or a beast that teaches it.
local function Line(view, index)
    local line = view.lines[index]
    if line then return line end
    line = CreateFrame("Button", nil, view.detail)
    line.highlight = line:CreateTexture(nil, "HIGHLIGHT")
    line.highlight:SetAllPoints()
    line.highlight:SetTexture(QUEST_HIGHLIGHT)
    line.highlight:SetBlendMode("ADD")
    line.heading = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line.heading:SetPoint("LEFT", 4, 0)
    line.name = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line.name:SetPoint("LEFT", 24, 0)
    line.name:SetWidth(200)
    line.name:SetJustifyH("LEFT")
    line.name:SetWordWrap(false)
    line.level = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.level:SetPoint("LEFT", 230, 0)
    line.zone = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.zone:SetPoint("LEFT", 300, 0)
    line.zone:SetWidth(150)
    line.zone:SetJustifyH("LEFT")
    line.zone:SetWordWrap(false)
    line.tame = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.tame:SetPoint("LEFT", 460, 0)
    line.pin = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
    line.pin:SetSize(56, 20)
    line.pin:SetPoint("RIGHT", -4, 0)
    line.pin:SetText("Pin")
    line.pin:SetScript("OnClick", function(self)
        local beast = self:GetParent().beast
        if beast then ns:PinLook({ beast = beast, label = beast.name, status = "seen" }) end
    end)
    line:SetScript("OnClick", function(self)
        local lookID = self.npcID and ns:GetLooks(self.npcID)[1]
        if lookID then
            ns.Skin.PlaySound("select")
            ns:OpenDexAt(lookID)
        end
    end)
    view.lines[index] = line
    return line
end

local function FillBeastLine(line, npcID)
    local beast = ns:GetBeast(npcID)
    line.npcID, line.beast = npcID, beast
    line.highlight:SetAlpha(1)
    line.heading:Hide()
    for _, region in ipairs({ line.name, line.level, line.zone, line.tame }) do region:Show() end
    local color = ns.RARITY_COLORS[beast and beast.rarity or "common"] or ns.RARITY_COLORS.common
    line.name:SetText(beast and beast.name or ("Beast " .. npcID))
    line.name:SetTextColor(color[1], color[2], color[3])
    line.level:SetText(beast and ns.DexUI.LevelText(beast) and ("Level " .. ns.DexUI.LevelText(beast)) or "")
    line.zone:SetText(ns:GetBeastZone(beast) or "")
    local minLevel, playerLevel = MinLevel(beast), UnitLevel("player") or 0
    if not minLevel then
        line.tame:SetText("")
    elseif playerLevel >= minLevel then
        line.tame:SetText("|cff40ff40Tame now|r")
    else
        line.tame:SetText(("|cffff9933Level %d|r"):format(minLevel))
    end
    line.pin:SetShown(beast ~= nil and (beast.spawns or 0) > 0 and beast.map ~= nil)
end

local function FillHeadingLine(line, text)
    line.npcID, line.beast = nil, nil
    line.highlight:SetAlpha(0)
    line.heading:SetText(text)
    line.heading:Show()
    for _, region in ipairs({ line.name, line.level, line.zone, line.tame }) do region:Hide() end
    line.pin:Hide()
end

local function Refresh(view)
    local ui = ns.DexUI
    local index = TaughtIndex()
    local known = ns.playerClass == "HUNTER" and ns.GetCharData().training or {}
    local names = AbilityNames(index, known)
    view.selected = view.selected or names[1]

    -- Ability list: as many rows as fit, from the scroll offset.
    local visible = math.max(1, math.floor((view.list:GetHeight() - ui.PAD - 34 - 44) / ABILITY_ROW_HEIGHT))
    view.listOffset = math.max(0, math.min(view.listOffset, #names - visible))
    local y = ui.PAD + 34
    local shownRows = 0
    for i = 1, visible do
        local name = names[view.listOffset + i]
        if not name then break end
        shownRows = i
        local row = AbilityRow(view, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", view.list, "TOPLEFT", ui.PAD - 8, -y)
        row:SetPoint("RIGHT", view.list, "RIGHT", -ui.PAD + 8, 0)
        row.ability = name
        row.name:SetText(name)
        local ranks, beasts = 0, 0
        for _, npcs in pairs(index[name] or {}) do
            ranks, beasts = ranks + 1, beasts + #npcs
        end
        local knownRank = known[name]
        row.count:SetText((knownRank and ("|cff40ff40R%d|r  "):format(knownRank) or "")
            .. (beasts > 0 and ("%d beast%s"):format(beasts, beasts == 1 and "" or "s") or ""))
        row.selected:SetShown(name == view.selected)
        ns.Skin.Stripe(row, view.listOffset + i)
        row:Show()
        y = y + ABILITY_ROW_HEIGHT
    end
    for i = shownRows + 1, #view.abilityRows do
        view.abilityRows[i]:Hide()
    end
    local more = #names > visible and "Scroll for more abilities. " or ""
    view.listHint:SetText(more .. (next(known) and "R = highest rank you know." or
        "Open your Beast Training window once to show the ranks you know."))

    -- Detail for the selected ability.
    local name = view.selected
    view.title:SetText(name or "")
    local summary = {}
    local families = FamiliesFor(name)
    if families then table.insert(summary, "Learned by: " .. families) end
    if known[name] then
        table.insert(summary, ("You know: |cff40ff40Rank %d|r"):format(known[name]))
    elseif next(known) then
        table.insert(summary, "You know: |cffff9933not learned yet|r")
    end
    view.summary:SetText(table.concat(summary, "\n"))

    -- Ranks, highest first, each with the beasts recorded teaching it.
    local ranks = {}
    for rank in pairs(index[name] or {}) do table.insert(ranks, rank) end
    table.sort(ranks, function(a, b) return a > b end)
    local entries = {}
    for _, rank in ipairs(ranks) do
        local better = known[name] and rank > known[name]
        table.insert(entries, { heading = ("Rank %d%s"):format(rank,
            better and "  |cff40ff40(higher than yours)|r" or (known[name] and GREY:format("  (known)") or "")) })
        local npcs = index[name][rank]
        table.sort(npcs, function(a, b) return (MinLevel(ns:GetBeast(a)) or 0) < (MinLevel(ns:GetBeast(b)) or 0) end)
        for _, npcID in ipairs(npcs) do
            table.insert(entries, { npcID = npcID })
        end
    end

    view.empty:SetShown(#entries == 0)
    view.empty:SetText(("No beast is known to teach %s.\n\nIt may be learned from a pet trainer instead, or come from a beast PetDex hasn't seen. When you tame a beast, PetDex records what it teaches."):format(name or "this"))

    local perPage = math.max(1, math.floor((view.detail:GetHeight() - TOP - PAGER_HEIGHT) / BEAST_ROW_HEIGHT))
    view.pages = math.max(1, math.ceil(#entries / perPage))
    view.page = math.min(view.page, view.pages)
    local first = (view.page - 1) * perPage
    local shown = 0
    for i = 1, perPage do
        local entry = entries[first + i]
        if not entry then break end
        shown = i
        local line = Line(view, i)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", view.detail, "TOPLEFT", ui.PAD, -(TOP + (i - 1) * BEAST_ROW_HEIGHT))
        line:SetPoint("RIGHT", view.detail, "RIGHT", -ui.PAD, 0)
        line:SetHeight(entry.heading and RANK_HEADER_HEIGHT or BEAST_ROW_HEIGHT)
        if entry.heading then
            FillHeadingLine(line, entry.heading)
        else
            FillBeastLine(line, entry.npcID)
        end
        line:Show()
    end
    for i = shown + 1, #view.lines do
        view.lines[i]:Hide()
    end
    view.pageText:SetText(view.pages > 1 and ("Page %d / %d"):format(view.page, view.pages) or "")
    view.prev:SetShown(view.pages > 1)
    view.next:SetShown(view.pages > 1)
    view.prev:SetEnabled(view.page > 1)
    view.next:SetEnabled(view.page < view.pages)
end

ns.DexViews.training = { Create = Create, Refresh = Refresh }
