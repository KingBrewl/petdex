-- Native look and sound: backdrops, bars, buttons and UI sounds built from
-- art and sounds the game itself uses, so PetDex feels like part of the UI.
local _, ns = ...

local Skin = {}
ns.Skin = Skin

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- Backdrop styles. Every file here ships with the game.
local BACKDROPS = {
    -- Dark panel with a tooltip border: sections, boxes, toasts.
    panel = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    -- Item-slot-like tile: a border that takes a colour (rarity, selection).
    slot = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    -- The classic gold dialog frame (fallback window border).
    dialog = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    },
}

Skin.BORDER_GREY = { 0.45, 0.45, 0.45 }
Skin.BORDER_GOLD = { 1, 0.82, 0 }
Skin.BORDER_HOVER = { 0.75, 0.75, 0.75 }

-- CreateFrame with the backdrop template where the client needs one.
function Skin.CreateFrame(frameType, parent, style, name, template)
    local templates = template
    if BACKDROP_TEMPLATE then
        templates = template and (template .. "," .. BACKDROP_TEMPLATE) or BACKDROP_TEMPLATE
    end
    local frame = CreateFrame(frameType or "Frame", name, parent, templates)
    if style then
        Skin.SetBackdrop(frame, style)
    end
    return frame
end

function Skin.SetBackdrop(frame, style)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop(BACKDROPS[style])
    if style == "slot" then
        -- The tooltip background is white art that the game tints dark.
        frame:SetBackdropColor(0.04, 0.04, 0.05, 0.92)
    else
        frame:SetBackdropColor(1, 1, 1, 1)
    end
    local grey = Skin.BORDER_GREY
    frame:SetBackdropBorderColor(grey[1], grey[2], grey[3], 1)
end

function Skin.SetBorderColor(frame, color)
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    end
end

-- A recessed panel like the ones inside Blizzard's own windows
-- (InsetFrameTemplate), or a dark panel where the client lacks it.
function Skin.CreateInset(parent)
    local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if ok and inset then
        return inset
    end
    return Skin.CreateFrame("Frame", parent, "panel")
end

-- Put a slot-style border behind a beast stage. The stage is raised above
-- the border so the border's background can't cover it.
function Skin.FrameStage(parent, stage)
    local border = Skin.CreateFrame("Frame", parent, "slot")
    border:SetPoint("TOPLEFT", stage.frame, "TOPLEFT", -4, 4)
    border:SetPoint("BOTTOMRIGHT", stage.frame, "BOTTOMRIGHT", 4, -4)
    local level = parent:GetFrameLevel()
    border:SetFrameLevel(level + 1)
    stage.frame:SetFrameLevel(level + 3)
    stage.model:SetFrameLevel(level + 4)
    return border
end

-- A status bar in the game's own bar texture, on a dark track.
function Skin.CreateBar(parent, height, color)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(color[1], color[2], color[3])
    bar:SetMinMaxValues(0, 1)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.55)
    return bar
end

-- A progress bar like the character window's Skills and Reputation bars:
-- the skill bar texture in a thin slot border, with text centred on it
-- (bar.text). Fill and text are set with bar:SetProgress(value, max).
function Skin.CreateSkillBar(parent, height, color)
    local holder = Skin.CreateFrame("Frame", parent, "slot")
    holder:SetHeight(height)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetPoint("TOPLEFT", 3, -3)
    bar:SetPoint("BOTTOMRIGHT", -3, 3)
    bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    bar:SetStatusBarColor(color[1], color[2], color[3])
    bar:SetMinMaxValues(0, 1)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    track:SetVertexColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25, 0.8)
    holder.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.text:SetPoint("CENTER", 0, 1)
    holder.bar = bar
    function holder:SetProgress(value, max, label)
        bar:SetValue(max > 0 and value / max or 0)
        self.text:SetText(label or ("%d / %d"):format(value, max))
    end
    return holder
end

-- A section heading in gold with the quest log's divider ornament under it.
function Skin.CreateHeading(parent, text, template)
    local heading = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    heading:SetText(text)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\QuestFrame\\UI-HorizontalBreak")
    divider:SetHeight(12)
    divider:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", -6, -1)
    heading.divider = divider
    return heading
end

-- A column heading button like the Who list's (WhoFrameColumnHeaderTemplate),
-- or plain gold text where the client lacks it.
local headerCount = 0
function Skin.CreateColumnHeader(parent, text, width)
    headerCount = headerCount + 1
    local ok, header = pcall(CreateFrame, "Button", "PetDexColumnHeader" .. headerCount, parent,
        "WhoFrameColumnHeaderTemplate")
    if ok and header then
        header:SetText(text)
        if WhoFrameColumn_SetWidth then
            pcall(WhoFrameColumn_SetWidth, header, width)
        else
            header:SetWidth(width)
        end
        header:Disable() -- headings only; the list has a fixed order
        local fontString = header:GetFontString()
        if fontString then fontString:SetTextColor(1, 0.82, 0) end
        return header
    end
    local plain = CreateFrame("Frame", nil, parent)
    plain:SetSize(width, 20)
    local label = plain:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 6, 0)
    label:SetText(text)
    return plain
end

-- Alternating row shading, as in Blizzard's long lists.
function Skin.Stripe(row, index)
    if not row.stripe then
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    row.stripe:SetShown(index % 2 == 0)
end

-- The spellbook's round previous/next page buttons. direction: "Prev"/"Next".
function Skin.CreatePageButton(parent, direction)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(32, 32)
    local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    button:SetNormalTexture(base .. "Up")
    button:SetPushedTexture(base .. "Down")
    button:SetDisabledTexture(base .. "Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return button
end

-- UI sounds by purpose; the first SOUNDKIT entry this client knows plays.
local SOUNDS = {
    open = { "IG_SPELLBOOK_OPEN", "IG_CHARACTER_INFO_OPEN" },
    close = { "IG_SPELLBOOK_CLOSE", "IG_CHARACTER_INFO_CLOSE" },
    page = { "IG_ABILITY_PAGE_TURN", "IG_SPELLBOOK_OPEN" },
    tab = { "IG_CHARACTER_INFO_TAB", "IG_MAINMENU_OPTION_CHECKBOX_ON" },
    select = { "IG_MAINMENU_OPTION_CHECKBOX_ON", "U_CHAT_SCROLL_BUTTON" },
    pin = { "UI_MAP_WAYPOINT_SUPER_TRACK_ON", "MAP_PING" },
}

function Skin.PlaySound(purpose)
    if not PlaySound or not SOUNDKIT then return end
    for _, key in ipairs(SOUNDS[purpose] or {}) do
        local sound = SOUNDKIT[key]
        if sound and pcall(PlaySound, sound) then
            return
        end
    end
end
