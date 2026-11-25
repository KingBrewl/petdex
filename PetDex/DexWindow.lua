-- The dex window: families on the left, the chosen family's looks grouped by
-- model in the middle (one beast stage each), and a large viewer for the
-- selected look on the right. Opened with /petdex.
--
-- Layout follows the mockup (claude.ai artifact "PetDex UI Mockup"). Points,
-- ranks and achievements come later; the header shows collection counts.
local _, ns = ...

local WIDTH, HEIGHT = 1060, 660
local TITLE_HEIGHT, HEADER_HEIGHT = 34, 50
local SIDEBAR_WIDTH, VIEWER_WIDTH = 180, 320
local BODY_TOP = TITLE_HEIGHT + HEADER_HEIGHT
local PAD = 16
local FAMILY_HEIGHT_MAX, FAMILY_HEIGHT_MIN = 30, 20
local FAMILY_LIST_TOP = 40 -- below the "FAMILIES" label
local VIEWER_STAGE_MAX, VIEWER_STAGE_MIN = 260, 120
local VIEWER_BELOW_STAGE = 330 -- room for the sections and record box under the stage

local TILE_WIDTH, STAGE_HEIGHT = 124, 108
local TILE_HEIGHT = STAGE_HEIGHT + 34
local TILE_GAP = 10
local GROUP_HEADER_HEIGHT = 26
local PAGER_HEIGHT = 36

local CONTENT_TOP = PAD + 30 -- below the family title
local MIN_WIDTH, MIN_HEIGHT = 880, 560
local MAX_WIDTH, MAX_HEIGHT = 2000, 1300

-- Space taken by the window's border, set when the window is built (the
-- native frame and the dialog fallback have different borders).
local INSET = { left = 0, right = 0, bottom = 0 }

-- The grid area follows the window size (see UpdateMetrics).
local CONTENT_WIDTH, CONTENT_HEIGHT, COLUMNS
local BODY_HEIGHT, VIEWER_STAGE_HEIGHT

local function UpdateMetrics(width, height)
    CONTENT_WIDTH = width - SIDEBAR_WIDTH - VIEWER_WIDTH - INSET.left - INSET.right
    CONTENT_HEIGHT = height - BODY_TOP - INSET.bottom - CONTENT_TOP - PAGER_HEIGHT -- room for rows
    COLUMNS = math.max(1, math.floor((CONTENT_WIDTH - 2 * PAD + TILE_GAP) / (TILE_WIDTH + TILE_GAP)))
    BODY_HEIGHT = height - BODY_TOP - INSET.bottom
    -- The viewer's stage gives up height first, so its text never overlaps
    -- the record box in a short window.
    VIEWER_STAGE_HEIGHT = math.max(VIEWER_STAGE_MIN,
        math.min(VIEWER_STAGE_MAX, BODY_HEIGHT - PAD - VIEWER_BELOW_STAGE))
end

-- Family rows shrink to fit every family in the sidebar.
local function FamilyRowHeight(count)
    local available = BODY_HEIGHT - FAMILY_LIST_TOP - 10
    local height = math.floor(available / math.max(1, count))
    return math.max(FAMILY_HEIGHT_MIN, math.min(FAMILY_HEIGHT_MAX, height))
end
UpdateMetrics(WIDTH, HEIGHT)

local GOLD = { 0.79, 0.64, 0.36 }
local RARITY_LABELS = { common = "Common", rare = "Rare", unique = "Unique" }
local ANIMATIONS = { 0, 4, 5, 16 } -- stand, walk, run, attack
local TAMED_ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"
local Skin = ns.Skin

-- Tabs along the bottom, like Blizzard's windows. The Dex view is built
-- here; other views register in ns.DexViews[key] = { Create(parent),
-- Refresh(view) } from their own files.
local TABS = {
    { key = "overview", label = "Overview" },
    { key = "dex", label = "Dex" },
    { key = "hunt", label = "Hunt" },
    { key = "training", label = "Training" },
    { key = "pets", label = "My Pets" },
    { key = "profile", label = "Profile" },
}
ns.DexViews = ns.DexViews or {}
local views = {}
local currentTab

local frame
local families = {}
local selectedFamily, selectedLook
local page, pages = 1, {}
local tiles, headers, familyButtons = {}, {}, {}
local viewer
local animIndex = 1

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function ColorText(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3])
end

local function LevelText(beast)
    if not beast then return end
    local level = beast.level
    if type(level) == "table" then
        return level[1] == level[2] and tostring(level[1]) or (level[1] .. "-" .. level[2])
    elseif level then
        return tostring(level)
    elseif beast.minLevel then
        return beast.minLevel == beast.maxLevel and tostring(beast.minLevel)
            or (beast.minLevel .. "-" .. beast.maxLevel)
    end
end

local function ZoneText(beast)
    return ns:GetBeastZone(beast)
end

local function StageState(info)
    return info.status or "unknown"
end

local function StageBeast(info)
    return { npcID = info.npcID, displayID = info.displayID, state = StageState(info),
        rarity = info.rarity, spirit = info.spirit }
end

---------------------------------------------------------------------------
-- Header
---------------------------------------------------------------------------
local function UpdateHeader()
    -- Completion counts documented (seen) looks, like a Pokedex; tames are
    -- the second, harder number.
    local total, tamed, seen = 0, 0, 0
    local byRarity = {}
    for _, family in ipairs(families) do
        for _, group in ipairs(family.models) do
            for _, info in ipairs(group.looks) do
                total = total + 1
                local counts = byRarity[info.rarity] or { total = 0, seen = 0 }
                byRarity[info.rarity] = counts
                counts.total = counts.total + 1
                if info.status then
                    seen = seen + 1
                    counts.seen = counts.seen + 1
                end
                if info.status == "tamed" then tamed = tamed + 1 end
            end
        end
    end
    frame.headerTotal:SetText(("Documented %d / %d beasts"):format(seen, total))
    -- Rank and points (Points.lua) next to the tame count.
    local score = ns.GetScore and ns:GetScore()
    if score then
        frame.headerSeen:SetText(("%d tamed   ·   Rank %d  %s   ·   %d points"):format(tamed, score.rank,
            ns.RankTitle(score.rank), score.total))
    else
        frame.headerSeen:SetText(("%d tamed"):format(tamed))
    end
    for rarity, label in pairs(frame.rarityCounters) do
        local counts = byRarity[rarity] or { total = 0, seen = 0 }
        label:SetText(("%s  %d/%d"):format(RARITY_LABELS[rarity], counts.seen, counts.total))
    end
end

---------------------------------------------------------------------------
-- Viewer
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Viewer sections: Combat, Taming, Where
---------------------------------------------------------------------------
local HEADING = "|cffffd100%s|r"
local GREY = "|cff9d9d9d%s|r"
local GOOD = "|cff40ff40%s|r"
local WARN = "|cffff9933%s|r"

local function SpeedLabel(speed)
    if speed <= 1.2 then return "Fast" end
    if speed < 1.8 then return "Quick" end
    if speed <= 2.0 then return "Normal" end
    return "Slow"
end

-- "8 h", "1-24 h", "45 min"
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
    local level = beast and beast.level
    if type(level) == "table" then return level[1] end
    return level or (beast and beast.minLevel)
end

local function CombatLines(info, lines)
    local beast, record = info.beast, info.record
    table.insert(lines, HEADING:format("Combat"))
    local measured = record and record.speed
    local speed = measured or (beast and beast.speed) or 2.0
    table.insert(lines, ("Attack speed %.1fs  %s%s"):format(speed, SpeedLabel(speed),
        measured and GREY:format("  (measured)") or ""))
    if math.abs(speed - 2.0) > 0.05 then
        table.insert(lines, GREY:format(speed < 2.0
            and "Damage is normalized; faster swings keep Frenzy up and push back casts."
            or "Damage is normalized; fewer, harder swings."))
    end
    local family = ns.Families[info.family]
    if family then
        table.insert(lines, ("%s: %s"):format(family.ability, family.effect))
    end
    if beast and beast.school then
        table.insert(lines, ("Deals %s damage"):format(beast.school))
    end
    -- What taming it teaches, as recorded when a beast of this look was
    -- tamed (the game data doesn't say).
    local taught
    for _, npcID in ipairs(ns:GetLookNPCs(info.lookID)) do
        taught = taught or ns.db.taught[npcID]
    end
    if taught and #taught.abilities > 0 then
        local names = {}
        for _, ability in ipairs(taught.abilities) do
            local text = ability.rank and (ability.name .. " " .. ability.rank:gsub("Rank ", "")) or ability.name
            table.insert(names, ability.passive and GREY:format(text) or text)
        end
        table.insert(lines, "Taming teaches: " .. table.concat(names, ", "))
    elseif taught then
        table.insert(lines, GREY:format("Taming teaches nothing new"))
    else
        table.insert(lines, GREY:format("Tame it to record which abilities it teaches."))
    end
end

local function TamingLines(info, lines)
    local beast = info.beast
    table.insert(lines, HEADING:format("Taming"))
    local minLevel = MinLevel(beast)
    if minLevel then
        local playerLevel = UnitLevel("player") or 0
        if ns.playerClass ~= "HUNTER" then
            table.insert(lines, ("Hunters can tame it from level %d"):format(minLevel))
        elseif playerLevel >= minLevel then
            table.insert(lines, GOOD:format("Tameable now") .. ("  (level %s, you're %d)"):format(LevelText(beast), playerLevel))
        else
            table.insert(lines, WARN:format(("Tameable at level %d"):format(minLevel)) .. ("  (you're %d)"):format(playerLevel))
        end
    end
    if beast and beast.elite then
        table.insert(lines, WARN:format("Elite") .. ": bring help")
    end
    local familyData = ns.FamilyData and ns.FamilyData[info.family]
    if familyData then
        table.insert(lines, "Eats: " .. table.concat(familyData.diet, ", "))
    end
end

local function WhereLines(info, lines, state)
    local beast = info.beast
    table.insert(lines, HEADING:format("Where"))
    local zone = ZoneText(beast)
    if zone then
        table.insert(lines, state == "unknown" and ("Hint: " .. zone) or zone)
    end
    if beast and beast.spawns == 0 then
        table.insert(lines, info.rarity == "unique" and "Summoned: no fixed spawn" or "No known spawn point")
    elseif beast and beast.spawns then
        local spawnText = beast.spawns == 1 and "1 spawn point" or (beast.spawns .. " spawn points")
        if beast.respawn then
            spawnText = spawnText .. ", respawns every " .. DurationText(beast.respawn[1], beast.respawn[2])
        end
        table.insert(lines, spawnText)
    end
end

local function UpdateViewer()
    local info = selectedLook
    if not info then
        viewer.stage:SetBeast(nil)
        viewer.name:SetText("")
        viewer.info:SetText("")
        viewer.record:SetText("")
        viewer.pin:Hide()
        return
    end
    viewer.stage:SetBeast(StageBeast(info))
    local state = StageState(info)
    local beast, record = info.beast, info.record
    local rarityColor = ns.RARITY_COLORS[info.rarity] or ns.RARITY_COLORS.common
    local level = LevelText(beast)

    if state == "unknown" then
        viewer.name:SetText("???")
        ColorText(viewer.name, { 0.62, 0.6, 0.55 })
    else
        viewer.name:SetText(info.label)
        ColorText(viewer.name, rarityColor)
    end

    -- Summary line: family (and model group), rarity, level.
    local rarityText = ("|cff%02x%02x%02x%s|r"):format(math.floor(rarityColor[1] * 255),
        math.floor(rarityColor[2] * 255), math.floor(rarityColor[3] * 255), RARITY_LABELS[info.rarity] or info.rarity)
    local summary = (info.model == info.family and info.family or (info.family .. "  ·  " .. info.model))
        .. "  ·  " .. rarityText .. (level and ("  ·  Level " .. level) or "")
    local lines = { summary, " " }
    -- Combat stats are the reward for documenting a beast.
    if state == "unknown" then
        table.insert(lines, GREY:format("Target this beast in the wild to document it and reveal its combat stats."))
    else
        CombatLines(info, lines)
    end
    table.insert(lines, " ")
    TamingLines(info, lines)
    table.insert(lines, " ")
    WhereLines(info, lines, state)
    viewer.info:SetText(table.concat(lines, "\n"))
    viewer.pin:SetShown(beast ~= nil and (beast.spawns or 0) > 0 and beast.map ~= nil)

    local recordText
    if state == "tamed" and record then
        recordText = "Tamed " .. date("%d %b %Y", record.tamed)
        if record.firstTamedBy then
            recordText = recordText .. " by " .. (strsplit("-", record.firstTamedBy))
        end
        if record.source == "stable" then
            recordText = recordText .. "\n(found in your stable)"
        elseif record.source == "pet" then
            recordText = recordText .. "\n(your active pet)"
        elseif (record.tameCount or 0) > 1 then
            recordText = recordText .. ("\nTamed %d times"):format(record.tameCount)
        end
    elseif state == "seen" and record then
        recordText = "Seen " .. date("%d %b %Y", record.seen)
        if record.lastZone and record.lastZone ~= "" then
            recordText = recordText .. ", last in " .. record.lastZone
        end
        recordText = recordText .. "\nNot tamed yet"
    else
        recordText = "Not seen yet"
    end
    viewer.record:SetText(recordText)

end

local function CreateViewer()
    viewer = Skin.CreateInset(views.dex)
    viewer:SetPoint("TOPRIGHT", -INSET.right, -BODY_TOP)
    viewer:SetPoint("BOTTOMRIGHT", -INSET.right, INSET.bottom)
    viewer:SetWidth(VIEWER_WIDTH)

    local stageWidth = VIEWER_WIDTH - 2 * PAD
    viewer.stage = ns.CreateBeastStage(viewer, stageWidth, VIEWER_STAGE_HEIGHT)
    viewer.stage.frame:SetPoint("TOP", 0, -PAD)
    viewer.stage:EnableTurning()
    Skin.FrameStage(viewer, viewer.stage)

    local hint = viewer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", viewer.stage.frame, "BOTTOMLEFT", 0, -4)
    hint:SetText("Drag to turn, scroll to zoom")

    local animate = CreateFrame("Button", nil, viewer, "UIPanelButtonTemplate")
    animate:SetSize(90, 20)
    animate:SetPoint("TOPRIGHT", viewer.stage.frame, "BOTTOMRIGHT", 0, -2)
    animate:SetText("Animate")
    animate:SetScript("OnClick", function()
        animIndex = animIndex % #ANIMATIONS + 1
        viewer.stage:PlayAnimation(ANIMATIONS[animIndex])
    end)

    viewer.name = viewer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    viewer.name:SetPoint("TOPLEFT", viewer.stage.frame, "BOTTOMLEFT", 0, -28)
    viewer.name:SetPoint("RIGHT", -PAD, 0)
    viewer.name:SetJustifyH("LEFT")
    viewer.name:SetWordWrap(false)

    -- Summary, then the Combat, Taming and Where sections.
    viewer.info = viewer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    viewer.info:SetPoint("TOPLEFT", viewer.name, "BOTTOMLEFT", 0, -5)
    viewer.info:SetPoint("RIGHT", -PAD, 0)
    viewer.info:SetJustifyH("LEFT")
    viewer.info:SetJustifyV("TOP")
    viewer.info:SetSpacing(2)

    -- Pin the spawn point on the world map to follow it.
    viewer.pin = CreateFrame("Button", nil, viewer, "UIPanelButtonTemplate")
    viewer.pin:SetSize(110, 22)
    viewer.pin:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    viewer.pin:SetText("Show on map")
    viewer.pin:SetScript("OnClick", function()
        if selectedLook then ns:PinLook(selectedLook) end
    end)

    local box = Skin.CreateInset(viewer)
    box:SetPoint("BOTTOMLEFT", PAD, PAD + 26)
    box:SetPoint("BOTTOMRIGHT", -PAD, PAD + 26)
    box:SetHeight(64)
    local boxTitle = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    boxTitle:SetPoint("TOPLEFT", 10, -8)
    boxTitle:SetText("Your record")
    viewer.record = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    viewer.record:SetPoint("TOPLEFT", boxTitle, "BOTTOMLEFT", 0, -4)
    viewer.record:SetPoint("RIGHT", -10, 0)
    viewer.record:SetJustifyH("LEFT")

end

---------------------------------------------------------------------------
-- Grid of looks, paginated (models aren't clipped by scroll frames)
---------------------------------------------------------------------------
-- Selected: gold. Tamed: its rarity colour, like an item's quality.
-- Otherwise grey; hovering lightens it.
local function UpdateTileBorder(tile, hovering)
    local info = tile.info
    local color = Skin.BORDER_GREY
    if info and info == selectedLook then
        color = Skin.BORDER_GOLD
    elseif hovering then
        color = Skin.BORDER_HOVER
    elseif info and info.status == "tamed" then
        color = ns.RARITY_COLORS[info.rarity] or Skin.BORDER_GREY
    end
    Skin.SetBorderColor(tile, color)
end

local function SelectLook(info)
    selectedLook = info
    for _, tile in ipairs(tiles) do
        if tile:IsShown() then
            UpdateTileBorder(tile)
        end
    end
    UpdateViewer()
end

local function GetTile(index)
    local tile = tiles[index]
    if tile then return tile end
    tile = Skin.CreateFrame("Button", frame.content, "slot")
    tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
    -- The stage sits inside the slot border.
    tile.stage = ns.CreateBeastStage(tile, TILE_WIDTH - 8, STAGE_HEIGHT - 4)
    tile.stage.frame:SetPoint("TOP", 0, -4)

    tile.name = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.name:SetPoint("TOP", tile.stage.frame, "BOTTOM", 0, -5)
    tile.name:SetWidth(TILE_WIDTH - 8)
    tile.name:SetWordWrap(false)
    tile.sub = tile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tile.sub:SetPoint("TOP", tile.name, "BOTTOM", 0, -2)
    tile.sub:SetWidth(TILE_WIDTH - 8)
    tile.sub:SetWordWrap(false)

    -- Tamed badge, on a frame above the model so it draws on top of it.
    local overlay = CreateFrame("Frame", nil, tile)
    overlay:SetAllPoints(tile.stage.frame)
    overlay:SetFrameLevel(tile.stage.frame:GetFrameLevel() + 10)
    tile.badge = overlay:CreateTexture(nil, "OVERLAY")
    tile.badge:SetSize(18, 18)
    tile.badge:SetPoint("TOPRIGHT", -4, -4)
    tile.badge:SetTexture(TAMED_ICON)
    tile.badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    tile:SetScript("OnClick", function(self)
        if self.info ~= selectedLook then
            Skin.PlaySound("select")
        end
        SelectLook(self.info)
    end)
    tile:SetScript("OnEnter", function(self) UpdateTileBorder(self, true) end)
    tile:SetScript("OnLeave", function(self) UpdateTileBorder(self) end)
    tiles[index] = tile
    return tile
end

local function GetHeader(index)
    local header = headers[index]
    if header then return header end
    header = CreateFrame("Frame", nil, frame.content)
    header:SetSize(CONTENT_WIDTH - 2 * PAD, GROUP_HEADER_HEIGHT)
    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.title:SetPoint("LEFT")
    header.count = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.count:SetPoint("LEFT", header.title, "RIGHT", 8, 0)
    local line = header:CreateTexture(nil, "BORDER")
    line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
    line:SetHeight(1)
    line:SetPoint("LEFT", header.count, "RIGHT", 10, 0)
    line:SetPoint("RIGHT")
    headers[index] = header
    return header
end

local function FillTile(tile, info)
    tile.info = info
    tile.stage:SetBeast(StageBeast(info))
    local state = StageState(info)
    tile.badge:SetShown(state == "tamed")
    if state == "unknown" then
        tile.name:SetText("???")
        ColorText(tile.name, { 0.62, 0.6, 0.55 })
        tile.sub:SetText(ZoneText(info.beast) or "")
    else
        tile.name:SetText(info.label)
        ColorText(tile.name, ns.RARITY_COLORS[info.rarity] or ns.RARITY_COLORS.common)
        local level = LevelText(info.beast)
        local sub = level and ("Level " .. level) or ""
        if state == "tamed" then
            sub = sub ~= "" and (sub .. "  ·  Tamed") or "Tamed"
        end
        tile.sub:SetText(sub)
    end
    UpdateTileBorder(tile)
end

-- Split the family into pages of rows: a header per model group, then rows
-- of tiles, packed by height.
local function BuildPages(family)
    local rows = {}
    for _, group in ipairs(family and family.models or {}) do
        local single = #family.models == 1 and group.name == family.name
        if not single then
            table.insert(rows, { kind = "header", group = group, height = GROUP_HEADER_HEIGHT })
        end
        for first = 1, #group.looks, COLUMNS do
            local looks = {}
            for i = first, math.min(first + COLUMNS - 1, #group.looks) do
                table.insert(looks, group.looks[i])
            end
            table.insert(rows, { kind = "tiles", looks = looks, height = TILE_HEIGHT + TILE_GAP })
        end
    end
    local result, current, used = {}, {}, 0
    for i, row in ipairs(rows) do
        -- Don't leave a header alone at the bottom of a page.
        local needed = row.height
        if row.kind == "header" and rows[i + 1] then
            needed = needed + rows[i + 1].height
        end
        if used + needed > CONTENT_HEIGHT and #current > 0 then
            table.insert(result, current)
            current, used = {}, 0
        end
        table.insert(current, row)
        used = used + row.height
    end
    if #current > 0 then
        table.insert(result, current)
    end
    return result
end

local function ShowPage()
    local tileIndex, headerIndex = 0, 0
    local y = 0
    for _, row in ipairs(pages[page] or {}) do
        if row.kind == "header" then
            headerIndex = headerIndex + 1
            local header = GetHeader(headerIndex)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", PAD, -y)
            header:SetWidth(CONTENT_WIDTH - 2 * PAD)
            header.title:SetText(row.group.name)
            header.count:SetText(("%d/%d documented  ·  %d tamed"):format(
                row.group.seen, row.group.total, row.group.tamed))
            header:Show()
        else
            for column, info in ipairs(row.looks) do
                tileIndex = tileIndex + 1
                local tile = GetTile(tileIndex)
                tile:ClearAllPoints()
                tile:SetPoint("TOPLEFT", PAD + (column - 1) * (TILE_WIDTH + TILE_GAP), -y)
                FillTile(tile, info)
                tile:Show()
            end
        end
        y = y + row.height
    end
    for i = tileIndex + 1, #tiles do
        tiles[i]:Hide()
        tiles[i].stage:SetBeast(nil)
    end
    for i = headerIndex + 1, #headers do
        headers[i]:Hide()
    end
    frame.pageText:SetText(#pages > 1 and ("Page %d / %d"):format(page, #pages) or "")
    frame.prevButton:SetShown(#pages > 1)
    frame.nextButton:SetShown(#pages > 1)
    frame.prevButton:SetEnabled(page > 1)
    frame.nextButton:SetEnabled(page < #pages)
end

local function ChangePage(delta)
    local before = page
    page = math.max(1, math.min(#pages, page + delta))
    if page ~= before then
        Skin.PlaySound("page")
        ShowPage()
    end
end

---------------------------------------------------------------------------
-- Families
---------------------------------------------------------------------------
local SelectFamily

local function GetFamilyButton(index)
    local button = familyButtons[index]
    if button then return button end
    button = CreateFrame("Button", nil, frame.sidebar)
    button:SetWidth(SIDEBAR_WIDTH - 2 * 10)
    -- The quest log's title highlight, for hover and (tinted) selection.
    local questHighlight = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
    button.selected = button:CreateTexture(nil, "BACKGROUND")
    button.selected:SetAllPoints()
    button.selected:SetTexture(questHighlight)
    button.selected:SetBlendMode("ADD")
    button.selected:SetVertexColor(1, 0.82, 0, 0.6)
    button:SetHighlightTexture(questHighlight, "ADD")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(16, 16)
    button.icon:SetPoint("LEFT", 6, 2)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.label:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
    button.count = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.count:SetPoint("RIGHT", -8, 2)
    button.bar = Skin.CreateBar(button, 3, GOLD)
    button.bar:SetPoint("BOTTOMLEFT", 8, 3)
    button.bar:SetPoint("BOTTOMRIGHT", -8, 3)
    button:SetScript("OnClick", function(self)
        if not selectedFamily or selectedFamily.name ~= self.family.name then
            Skin.PlaySound("tab")
        end
        SelectFamily(self.family)
    end)
    familyButtons[index] = button
    return button
end

local function UpdateFamilyButtons()
    local rowHeight = FamilyRowHeight(#families)
    for index, family in ipairs(families) do
        local button = GetFamilyButton(index)
        button:SetHeight(rowHeight - 2)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 10, -FAMILY_LIST_TOP - (index - 1) * rowHeight)
        button.family = family
        button.label:SetText(family.name)
        local familyData = ns.FamilyData and ns.FamilyData[family.name]
        button.icon:SetTexture(familyData and familyData.icon or TAMED_ICON)
        button.count:SetText(("%d/%d"):format(family.seen, family.total))
        button.bar:SetValue(family.total > 0 and family.seen / family.total or 0)
        local isSelected = selectedFamily and selectedFamily.name == family.name
        button.selected:SetShown(isSelected)
        button.label:SetFontObject(isSelected and "GameFontNormal" or "GameFontHighlight")
        button:Show()
    end
    for i = #families + 1, #familyButtons do
        familyButtons[i]:Hide()
    end
end

local function PageOf(lookID)
    for index, rows in ipairs(pages) do
        for _, row in ipairs(rows) do
            for _, info in ipairs(row.looks or {}) do
                if info.lookID == lookID then return index end
            end
        end
    end
end

-- focusLookID: select that look and turn to its page.
SelectFamily = function(family, keepPage, focusLookID)
    selectedFamily = family
    frame.familyTitle:SetText(family and family.name or "")
    frame.familyCount:SetText(family and ("%d of %d documented  ·  %d tamed"):format(
        family.seen, family.total, family.tamed) or "")
    pages = BuildPages(family)
    if not keepPage then page = 1 end
    if focusLookID then page = PageOf(focusLookID) or page end
    page = math.max(1, math.min(page, #pages))
    UpdateFamilyButtons()
    ShowPage()
    -- Keep the selected look if it's in this family, else pick the first.
    local wanted = focusLookID or (selectedLook and selectedLook.lookID)
    local keep
    if wanted and family then
        for _, group in ipairs(family.models) do
            for _, info in ipairs(group.looks) do
                if info.lookID == wanted then keep = info end
            end
        end
    end
    local first = family and family.models[1] and family.models[1].looks[1]
    SelectLook(keep or first)
end

-- Rebuild from the collection: the header, then the current tab. On the
-- Dex, keep the current family, page and look, or jump to focusLookID or
-- focusFamily (a family name).
local function Refresh(focusLookID, focusFamily)
    families = ns:GetDexFamilies()
    if currentTab ~= "dex" then
        UpdateHeader()
        local view, spec = views[currentTab], ns.DexViews[currentTab]
        if view and spec and spec.Refresh then
            spec.Refresh(view)
        end
        return
    end
    local family = families[1]
    local wantedFamily = focusFamily or (selectedFamily and selectedFamily.name)
    if focusLookID then
        local look = ns:GetLookInfo(focusLookID)
        wantedFamily = look and look.family or wantedFamily
    end
    if wantedFamily then
        for _, candidate in ipairs(families) do
            if candidate.name == wantedFamily then family = candidate end
        end
    end
    UpdateHeader()
    -- A family opened from another tab starts on its first page.
    SelectFamily(family, not focusFamily, focusLookID)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- Size and position are remembered in ns.db.settings.window.
local function SaveGeometry()
    local point, _, relativePoint, x, y = frame:GetPoint()
    ns.db.settings.window = {
        width = math.floor(frame:GetWidth() + 0.5), height = math.floor(frame:GetHeight() + 0.5),
        point = point, relativePoint = relativePoint, x = x, y = y,
    }
end

local function RestoreGeometry()
    local saved = ns.db.settings.window
    local width = saved and saved.width or WIDTH
    local height = saved and saved.height or HEIGHT
    frame:SetSize(math.max(MIN_WIDTH, math.min(MAX_WIDTH, width)), math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, height)))
    frame:ClearAllPoints()
    if saved and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        frame:SetPoint("CENTER")
    end
    UpdateMetrics(frame:GetWidth(), frame:GetHeight())
end

-- After a resize: new column count and page size, same family and look.
local function Relayout()
    UpdateMetrics(frame:GetWidth(), frame:GetHeight())
    if currentTab and currentTab ~= "dex" then
        Refresh()
        return
    end
    viewer.stage:SetStageSize(VIEWER_WIDTH - 2 * PAD, VIEWER_STAGE_HEIGHT)
    if viewer.stage.size then viewer.stage:Fit() end
    if selectedFamily then
        SelectFamily(selectedFamily, true, selectedLook and selectedLook.lookID)
    end
end

local function CreateResizeGrip()
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    else
        pcall(frame.SetMinResize, frame, MIN_WIDTH, MIN_HEIGHT)
        pcall(frame.SetMaxResize, frame, MAX_WIDTH, MAX_HEIGHT)
    end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SaveGeometry()
        Relayout()
    end)
end

-- Blizzard's standard window (portrait, title, close button) when this
-- client has the template; otherwise a frame with the classic gold dialog
-- border. Returns the frame and whether it's the native template.
local function CreateWindowFrame()
    local ok, native = pcall(CreateFrame, "Frame", "PetDexFrame", UIParent, "ButtonFrameTemplate")
    if ok and native then
        if native.Inset then native.Inset:Hide() end
        local portrait = native.portrait or (native.PortraitContainer and native.PortraitContainer.portrait)
        if native.SetPortraitToAsset then
            pcall(native.SetPortraitToAsset, native, TAMED_ICON)
        elseif portrait and SetPortraitToTexture then
            pcall(SetPortraitToTexture, portrait, TAMED_ICON)
        elseif portrait then
            portrait:SetTexture(TAMED_ICON)
        end
        if native.SetTitle then
            pcall(native.SetTitle, native, "PetDex")
        else
            local titleText = native.TitleText or (native.TitleContainer and native.TitleContainer.TitleText)
            if titleText then titleText:SetText("PetDex") end
        end
        INSET.left, INSET.right, INSET.bottom = 4, 6, 4
        return native, true
    end
    local plain = Skin.CreateFrame("Frame", UIParent, "dialog", "PetDexFrame")
    INSET.left, INSET.right, INSET.bottom = 11, 11, 11
    return plain, false
end

local ShowTab

local function CreateTabs()
    frame.tabs = {}
    local blizzardTabs = true
    local template = "PanelTabButtonTemplate"
    -- Newer tab art (atlases) sits side by side; the older art is drawn to
    -- overlap its neighbour.
    local gap = -15
    for index, tab in ipairs(TABS) do
        local name = "PetDexFrameTab" .. index
        local ok, button = pcall(CreateFrame, "Button", name, frame, "PanelTabButtonTemplate")
        if not ok then
            template = "CharacterFrameTabButtonTemplate"
            ok, button = pcall(CreateFrame, "Button", name, frame, "CharacterFrameTabButtonTemplate")
        end
        if not ok then
            blizzardTabs = false
            template = "UIPanelButtonTemplate"
            button = CreateFrame("Button", name, frame, "UIPanelButtonTemplate")
            button:SetSize(96, 24)
        end
        if index == 1 and blizzardTabs then
            local left = button.Left or button.LeftActive or _G[name .. "Left"]
            local atlas = left and left.GetAtlas and left:GetAtlas()
            if atlas and atlas ~= "" then gap = 3 end
            ns:Debug("tabs:", template, atlas and ("atlas " .. atlas) or "classic art", "gap", gap)
        end
        button:SetID(index)
        button:SetText(tab.label)
        if blizzardTabs and PanelTemplates_TabResize then
            pcall(PanelTemplates_TabResize, button, 0)
        end
        if index == 1 then
            button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, blizzardTabs and 2 or -2)
        else
            -- Blizzard's tab art overlaps its neighbours.
            button:SetPoint("LEFT", frame.tabs[index - 1], "RIGHT", blizzardTabs and gap or 4, 0)
        end
        button:SetScript("OnClick", function()
            if currentTab ~= tab.key then
                Skin.PlaySound("tab")
            end
            ShowTab(tab.key)
        end)
        frame.tabs[index] = button
    end
    frame.numTabs = #TABS
    if blizzardTabs and PanelTemplates_SetNumTabs then
        pcall(PanelTemplates_SetNumTabs, frame, #TABS)
    end
end

-- Show one tab's view (built on first use) and refresh it.
ShowTab = function(key, focusLookID, focusFamily)
    currentTab = key
    ns.db.settings.tab = key
    if not views[key] then
        local spec = ns.DexViews[key]
        if spec and spec.Create then
            views[key] = spec.Create(frame)
            views[key]:SetAllPoints()
        end
    end
    for viewKey, view in pairs(views) do
        view:SetShown(viewKey == key)
    end
    for index, tab in ipairs(TABS) do
        if tab.key == key and PanelTemplates_SetTab then
            pcall(PanelTemplates_SetTab, frame, index)
        end
    end
    Refresh(focusLookID, focusFamily)
end

local function CreateWindow()
    local native
    frame, native = CreateWindowFrame()
    frame:SetFrameStrata("DIALOG") -- above action bars and unit frames
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveGeometry()
    end)
    table.insert(UISpecialFrames, "PetDexFrame") -- Escape closes it
    RestoreGeometry()
    CreateResizeGrip()

    if not native then
        -- Dialog fallback: the classic header plate and a close button.
        local plate = frame:CreateTexture(nil, "ARTWORK")
        plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
        plate:SetSize(256, 64)
        plate:SetPoint("TOP", 0, 12)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", plate, "TOP", 0, -14)
        title:SetText("PetDex")
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end

    -- Header, starting right of the native window's round portrait (the
    -- portrait is drawn on the window, so a panel over it would hide it).
    -- Native windows put header text straight on the window; the fallback
    -- dialog gets a panel.
    local header = native and CreateFrame("Frame", nil, frame) or Skin.CreateFrame("Frame", frame, "panel")
    header:SetPoint("TOPLEFT", INSET.left + (native and 56 or 0), -TITLE_HEIGHT)
    header:SetPoint("TOPRIGHT", -INSET.right, -TITLE_HEIGHT)
    header:SetHeight(HEADER_HEIGHT)
    frame.headerTotal = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.headerTotal:SetPoint("LEFT", 16, 6)
    frame.headerSeen = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.headerSeen:SetPoint("TOPLEFT", frame.headerTotal, "BOTTOMLEFT", 0, -3)
    frame.rarityCounters = {}
    local previous
    for _, rarity in ipairs({ "unique", "rare", "common" }) do
        local label = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        if previous then
            label:SetPoint("RIGHT", previous, "LEFT", -24, 0)
        else
            label:SetPoint("RIGHT", -20, 0)
        end
        ColorText(label, ns.RARITY_COLORS[rarity])
        frame.rarityCounters[rarity] = label
        previous = label
    end

    -- The Dex view: family list, grid and viewer.
    views.dex = CreateFrame("Frame", nil, frame)
    views.dex:SetAllPoints()

    -- Sidebar
    frame.sidebar = Skin.CreateInset(views.dex)
    frame.sidebar:SetPoint("TOPLEFT", INSET.left, -BODY_TOP)
    frame.sidebar:SetPoint("BOTTOMLEFT", INSET.left, INSET.bottom)
    frame.sidebar:SetWidth(SIDEBAR_WIDTH)
    local familiesTitle = frame.sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    familiesTitle:SetPoint("TOPLEFT", 18, -16)
    familiesTitle:SetText("FAMILIES")

    -- Content
    local content = Skin.CreateInset(views.dex)
    content:SetPoint("TOPLEFT", INSET.left + SIDEBAR_WIDTH, -BODY_TOP)
    content:SetPoint("BOTTOMRIGHT", -(INSET.right + VIEWER_WIDTH), INSET.bottom)
    frame.familyTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.familyTitle:SetPoint("TOPLEFT", PAD, -PAD)
    frame.familyCount = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.familyCount:SetPoint("LEFT", frame.familyTitle, "RIGHT", 10, -1)

    frame.content = CreateFrame("Frame", nil, content)
    frame.content:SetPoint("TOPLEFT", 0, -CONTENT_TOP)
    frame.content:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, PAGER_HEIGHT)

    -- The spellbook's page buttons, with the page number between them.
    frame.pageText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pageText:SetPoint("BOTTOM", 0, 14)
    frame.prevButton = Skin.CreatePageButton(content, "Prev")
    frame.prevButton:SetPoint("RIGHT", frame.pageText, "LEFT", -10, 0)
    frame.prevButton:SetScript("OnClick", function() ChangePage(-1) end)
    frame.nextButton = Skin.CreatePageButton(content, "Next")
    frame.nextButton:SetPoint("LEFT", frame.pageText, "RIGHT", 10, 0)
    frame.nextButton:SetScript("OnClick", function() ChangePage(1) end)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta) ChangePage(-delta) end)

    CreateViewer()

    -- Lay out again while the window is being resized (a few times a
    -- second), not only when the grip is let go.
    local relayoutQueued = false
    frame:SetScript("OnSizeChanged", function()
        if relayoutQueued or not viewer then return end
        relayoutQueued = true
        C_Timer.After(0.05, function()
            relayoutQueued = false
            Relayout()
        end)
    end)

    CreateTabs()
    frame:SetScript("OnShow", function()
        Skin.PlaySound("open")
        ShowTab(currentTab or ns.db.settings.tab or "overview")
    end)
    frame:SetScript("OnHide", function() Skin.PlaySound("close") end)
end

-- Called by Collection.lua when a look is newly seen or tamed.
function ns:OnCollectionChanged()
    if frame and frame:IsShown() then
        Refresh()
    end
end

-- Layout and helpers the other views share with the Dex.
ns.DexUI = {
    BODY_TOP = BODY_TOP,
    INSET = INSET, -- filled in when the window is built
    PAD = PAD,
    LevelText = function(beast) return LevelText(beast) end,
    RARITY_LABELS = RARITY_LABELS,
}

function ns:HideDex()
    if frame then frame:Hide() end
end

function ns:ToggleDex()
    if not frame then
        CreateWindow()
        frame:Hide()
    end
    frame:SetShown(not frame:IsShown())
end

-- Show the window on a tab, without the usual OnShow refresh first.
local function OpenOn(key, focusLookID, focusFamily)
    if not frame then
        CreateWindow()
        frame:Hide()
    end
    if frame:IsShown() then
        ShowTab(key, focusLookID, focusFamily)
        return
    end
    local onShow = frame:GetScript("OnShow")
    frame:SetScript("OnShow", nil)
    frame:Show()
    frame:SetScript("OnShow", onShow)
    Skin.PlaySound("open")
    ShowTab(key, focusLookID, focusFamily)
end

-- Open the dex on one look (from a toast or the other tabs).
function ns:OpenDexAt(lookID)
    OpenOn("dex", lookID)
end

-- Open the window on a tab by key (e.g. "profile" from an achievement toast).
function ns:OpenDexTab(key)
    OpenOn(key)
end

-- Open the Dex tab on a family (from the Overview).
function ns:OpenDexFamily(familyName)
    OpenOn("dex", nil, familyName)
end
