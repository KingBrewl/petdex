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
local VIEWER_STAGE_MAX, VIEWER_STAGE_MIN = 260, 140
local VIEWER_BELOW_STAGE = 260 -- room for the text and record box under the stage

local TILE_WIDTH, STAGE_HEIGHT = 124, 108
local TILE_HEIGHT = STAGE_HEIGHT + 34
local TILE_GAP = 10
local GROUP_HEADER_HEIGHT = 26
local PAGER_HEIGHT = 36

local CONTENT_TOP = PAD + 30 -- below the family title
local MIN_WIDTH, MIN_HEIGHT = 880, 560
local MAX_WIDTH, MAX_HEIGHT = 2000, 1300

-- The grid area follows the window size (see UpdateMetrics).
local CONTENT_WIDTH, CONTENT_HEIGHT, COLUMNS
local BODY_HEIGHT, VIEWER_STAGE_HEIGHT

local function UpdateMetrics(width, height)
    CONTENT_WIDTH = width - SIDEBAR_WIDTH - VIEWER_WIDTH
    CONTENT_HEIGHT = height - BODY_TOP - CONTENT_TOP - PAGER_HEIGHT -- room for rows
    COLUMNS = math.max(1, math.floor((CONTENT_WIDTH - 2 * PAD + TILE_GAP) / (TILE_WIDTH + TILE_GAP)))
    BODY_HEIGHT = height - BODY_TOP
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
local DIM = { 0.23, 0.24, 0.27 }
local RARITY_LABELS = { common = "Common", rare = "Rare", unique = "Unique" }
local ANIMATIONS = { 0, 4, 5, 16 } -- stand, walk, run, attack
local TAMED_ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"

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
local function AddBorder(target, color, alpha)
    local lines = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = target:CreateTexture(nil, "BORDER")
        line:SetColorTexture(color[1], color[2], color[3], alpha or 1)
        if side == "TOP" or side == "BOTTOM" then
            line:SetHeight(1)
            line:SetPoint(side .. "LEFT")
            line:SetPoint(side .. "RIGHT")
        else
            line:SetWidth(1)
            line:SetPoint("TOP" .. side)
            line:SetPoint("BOTTOM" .. side)
        end
        table.insert(lines, line)
    end
    return lines
end

local function SetBorderColor(lines, color)
    for _, line in ipairs(lines) do
        line:SetColorTexture(color[1], color[2], color[3], 1)
    end
end

local function Fill(target, r, g, b, a, layer)
    local texture = target:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a)
    return texture
end

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
    frame.headerSeen:SetText(("%d tamed"):format(tamed))
    for rarity, label in pairs(frame.rarityCounters) do
        local counts = byRarity[rarity] or { total = 0, seen = 0 }
        label:SetText(("%s  %d/%d"):format(RARITY_LABELS[rarity], counts.seen, counts.total))
    end
end

---------------------------------------------------------------------------
-- Viewer
---------------------------------------------------------------------------
local function FindGroup(family, modelName)
    for _, group in ipairs(family and family.models or {}) do
        if group.name == modelName then return group end
    end
end

local function UpdateViewer()
    local info = selectedLook
    if not info then
        viewer.stage:SetBeast(nil)
        viewer.name:SetText("")
        viewer.details:SetText("")
        viewer.record:SetText("")
        viewer.note:SetText("")
        viewer.group:SetText("")
        return
    end
    viewer.stage:SetBeast(StageBeast(info))
    local state = StageState(info)
    local beast, record = info.beast, info.record
    local rarityColor = ns.RARITY_COLORS[info.rarity] or ns.RARITY_COLORS.common
    local level, zone = LevelText(beast), ZoneText(beast)

    if state == "unknown" then
        viewer.name:SetText("???")
        ColorText(viewer.name, { 0.62, 0.6, 0.55 })
    else
        viewer.name:SetText(info.label)
        ColorText(viewer.name, rarityColor)
    end

    local lines = { info.model == info.family and info.family
        or ("%s  ·  %s model"):format(info.family, info.model) }
    local rarityLine = "|cff%02x%02x%02x%s|r"
    rarityLine = rarityLine:format(math.floor(rarityColor[1] * 255), math.floor(rarityColor[2] * 255),
        math.floor(rarityColor[3] * 255),
        RARITY_LABELS[info.rarity] or info.rarity)
    if level then rarityLine = rarityLine .. "  ·  Level " .. level end
    table.insert(lines, rarityLine)
    if zone then
        table.insert(lines, state == "unknown" and ("Hint: " .. zone) or zone)
    end
    viewer.details:SetText(table.concat(lines, "\n"))

    local note = beast and beast.note
    viewer.note:SetText(note and state ~= "unknown" and ("\"" .. note .. "\"") or "")

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

    local group = FindGroup(selectedFamily, info.model)
    viewer.group:SetText(group and ("%s: %d / %d documented, %d tamed"):format(
        group.name, group.seen, group.total, group.tamed) or "")
end

local function CreateViewer()
    viewer = CreateFrame("Frame", nil, frame)
    viewer:SetPoint("TOPRIGHT", 0, -BODY_TOP)
    viewer:SetPoint("BOTTOMRIGHT")
    viewer:SetWidth(VIEWER_WIDTH)
    Fill(viewer, 0.045, 0.05, 0.065, 1)
    local divider = viewer:CreateTexture(nil, "BORDER")
    divider:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT")
    divider:SetPoint("BOTTOMLEFT")

    local stageWidth = VIEWER_WIDTH - 2 * PAD
    viewer.stage = ns.CreateBeastStage(viewer, stageWidth, VIEWER_STAGE_HEIGHT)
    viewer.stage.frame:SetPoint("TOP", 0, -PAD)
    viewer.stage:EnableTurning()
    AddBorder(viewer.stage.frame, { 0.35, 0.29, 0.17 })

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

    viewer.name = viewer:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    viewer.name:SetPoint("TOPLEFT", viewer.stage.frame, "BOTTOMLEFT", 0, -30)
    viewer.name:SetPoint("RIGHT", -PAD, 0)
    viewer.name:SetJustifyH("LEFT")

    viewer.details = viewer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    viewer.details:SetPoint("TOPLEFT", viewer.name, "BOTTOMLEFT", 0, -6)
    viewer.details:SetPoint("RIGHT", -PAD, 0)
    viewer.details:SetJustifyH("LEFT")
    viewer.details:SetSpacing(3)

    viewer.note = viewer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    viewer.note:SetPoint("TOPLEFT", viewer.details, "BOTTOMLEFT", 0, -6)
    viewer.note:SetPoint("RIGHT", -PAD, 0)
    viewer.note:SetJustifyH("LEFT")

    local box = CreateFrame("Frame", nil, viewer)
    box:SetPoint("BOTTOMLEFT", PAD, PAD + 26)
    box:SetPoint("BOTTOMRIGHT", -PAD, PAD + 26)
    box:SetHeight(64)
    Fill(box, 0.09, 0.1, 0.13, 1)
    AddBorder(box, { 0.35, 0.29, 0.17 })
    local boxTitle = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    boxTitle:SetPoint("TOPLEFT", 10, -8)
    boxTitle:SetText("Your record")
    viewer.record = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    viewer.record:SetPoint("TOPLEFT", boxTitle, "BOTTOMLEFT", 0, -4)
    viewer.record:SetPoint("RIGHT", -10, 0)
    viewer.record:SetJustifyH("LEFT")

    viewer.group = viewer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    viewer.group:SetPoint("BOTTOMLEFT", PAD, PAD + 4)
end

---------------------------------------------------------------------------
-- Grid of looks, paginated (models aren't clipped by scroll frames)
---------------------------------------------------------------------------
local function SelectLook(info)
    selectedLook = info
    for _, tile in ipairs(tiles) do
        if tile:IsShown() then
            SetBorderColor(tile.border, tile.info == info and GOLD or DIM)
        end
    end
    UpdateViewer()
end

local function GetTile(index)
    local tile = tiles[index]
    if tile then return tile end
    tile = CreateFrame("Button", nil, frame.content)
    tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
    Fill(tile, 0.08, 0.085, 0.1, 1)
    tile.stage = ns.CreateBeastStage(tile, TILE_WIDTH, STAGE_HEIGHT)
    tile.stage.frame:SetPoint("TOP")
    tile.border = AddBorder(tile, DIM)

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

    tile:SetScript("OnClick", function(self) SelectLook(self.info) end)
    tile:SetScript("OnEnter", function(self)
        if self.info ~= selectedLook then SetBorderColor(self.border, { 0.5, 0.42, 0.25 }) end
    end)
    tile:SetScript("OnLeave", function(self)
        SetBorderColor(self.border, self.info == selectedLook and GOLD or DIM)
    end)
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
    SetBorderColor(tile.border, info == selectedLook and GOLD or DIM)
end

-- Split the family into pages of rows: a header per model group, then rows
-- of tiles, packed by height.
local function BuildPages(family)
    local rows = {}
    for _, group in ipairs(family and family.models or {}) do
        table.insert(rows, { kind = "header", group = group, height = GROUP_HEADER_HEIGHT })
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
    page = math.max(1, math.min(#pages, page + delta))
    ShowPage()
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
    button.selected = Fill(button, 0.16, 0.14, 0.09, 1)
    button.border = AddBorder(button, GOLD)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.05)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.label:SetPoint("LEFT", 8, 2)
    button.count = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.count:SetPoint("RIGHT", -8, 2)
    local track = button:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(0.05, 0.05, 0.07, 1)
    track:SetHeight(3)
    track:SetPoint("BOTTOMLEFT", 8, 4)
    track:SetPoint("BOTTOMRIGHT", -8, 4)
    button.bar = button:CreateTexture(nil, "OVERLAY")
    button.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    button.bar:SetHeight(3)
    button.bar:SetPoint("LEFT", track, "LEFT")
    button.barWidth = SIDEBAR_WIDTH - 2 * 10 - 16
    button:SetScript("OnClick", function(self) SelectFamily(self.family) end)
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
        button.count:SetText(("%d/%d"):format(family.seen, family.total))
        local share = family.total > 0 and family.seen / family.total or 0
        button.bar:SetWidth(math.max(1, button.barWidth * share))
        button.bar:SetShown(share > 0)
        local isSelected = selectedFamily and selectedFamily.name == family.name
        button.selected:SetShown(isSelected)
        for _, line in ipairs(button.border) do line:SetShown(isSelected) end
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

-- Rebuild from the collection, keeping the current family, page and look,
-- or jumping to focusLookID.
local function Refresh(focusLookID)
    families = ns:GetDexFamilies()
    local family = families[1]
    local wantedFamily = selectedFamily and selectedFamily.name
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
    SelectFamily(family, true, focusLookID)
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

local function CreateWindow()
    frame = CreateFrame("Frame", "PetDexFrame", UIParent)
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
    Fill(frame, 0.06, 0.065, 0.08, 1)
    AddBorder(frame, GOLD)
    CreateResizeGrip()

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(TITLE_HEIGHT)
    Fill(titleBar, 0.1, 0.11, 0.14, 1)
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER")
    title:SetText("PetDex")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    -- Header
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, -TITLE_HEIGHT)
    header:SetPoint("TOPRIGHT", 0, -TITLE_HEIGHT)
    header:SetHeight(HEADER_HEIGHT)
    Fill(header, 0.085, 0.09, 0.115, 1)
    local headerLine = header:CreateTexture(nil, "BORDER")
    headerLine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
    headerLine:SetHeight(1)
    headerLine:SetPoint("BOTTOMLEFT")
    headerLine:SetPoint("BOTTOMRIGHT")
    frame.headerTotal = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.headerTotal:SetPoint("LEFT", 20, 6)
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

    -- Sidebar
    frame.sidebar = CreateFrame("Frame", nil, frame)
    frame.sidebar:SetPoint("TOPLEFT", 0, -BODY_TOP)
    frame.sidebar:SetPoint("BOTTOMLEFT")
    frame.sidebar:SetWidth(SIDEBAR_WIDTH)
    Fill(frame.sidebar, 0.05, 0.055, 0.07, 1)
    local sidebarLine = frame.sidebar:CreateTexture(nil, "BORDER")
    sidebarLine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
    sidebarLine:SetWidth(1)
    sidebarLine:SetPoint("TOPRIGHT")
    sidebarLine:SetPoint("BOTTOMRIGHT")
    local familiesTitle = frame.sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    familiesTitle:SetPoint("TOPLEFT", 18, -16)
    familiesTitle:SetText("FAMILIES")

    -- Content
    local content = CreateFrame("Frame", nil, frame)
    Fill(content, 0.06, 0.065, 0.08, 1)
    content:SetPoint("TOPLEFT", SIDEBAR_WIDTH, -BODY_TOP)
    content:SetPoint("BOTTOMRIGHT", -VIEWER_WIDTH, 0)
    frame.familyTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.familyTitle:SetPoint("TOPLEFT", PAD, -PAD)
    frame.familyCount = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.familyCount:SetPoint("LEFT", frame.familyTitle, "RIGHT", 10, -1)

    frame.content = CreateFrame("Frame", nil, content)
    frame.content:SetPoint("TOPLEFT", 0, -CONTENT_TOP)
    frame.content:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, PAGER_HEIGHT)

    frame.prevButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    frame.prevButton:SetSize(80, 22)
    frame.prevButton:SetPoint("BOTTOMLEFT", PAD, 10)
    frame.prevButton:SetText("Previous")
    frame.prevButton:SetScript("OnClick", function() ChangePage(-1) end)
    frame.nextButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    frame.nextButton:SetSize(80, 22)
    frame.nextButton:SetPoint("BOTTOMRIGHT", -PAD, 10)
    frame.nextButton:SetText("Next")
    frame.nextButton:SetScript("OnClick", function() ChangePage(1) end)
    frame.pageText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.pageText:SetPoint("BOTTOM", 0, 15)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta) ChangePage(-delta) end)

    CreateViewer()

    frame:SetScript("OnShow", function() Refresh() end)
end

-- Called by Collection.lua when a look is newly seen or tamed.
function ns:OnCollectionChanged()
    if frame and frame:IsShown() then
        Refresh()
    end
end

function ns:ToggleDex()
    if not frame then
        CreateWindow()
        frame:Hide()
    end
    frame:SetShown(not frame:IsShown())
end

-- Open the dex on one look (from a toast).
function ns:OpenDexAt(lookID)
    if not frame then
        CreateWindow()
        frame:Hide()
    end
    if frame:IsShown() then
        Refresh(lookID)
    else
        frame:SetScript("OnShow", nil)
        frame:Show()
        frame:SetScript("OnShow", function() Refresh() end)
        Refresh(lookID)
    end
end
