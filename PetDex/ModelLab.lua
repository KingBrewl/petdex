-- Model lab (debug): a prototype of the dex "stage" for tuning by eye.
--
-- Shows one beast in each dex state on a PlayerModel (the widget that passed
-- the first lab round on Forever; ModelScene couldn't do silhouettes and fog
-- had no effect):
--   Tamed     lit with the chosen light preset, rarity glow on the ground
--   Seen      SetDesaturation(1), same light
--   Unknown   every light at zero (black silhouette) against a back glow
-- Buttons tune the framing (camera distance) and light preset, and test
-- turning, drag-to-turn, animations and frame rate with a grid of models.
--
-- /petdex lab                 your target
-- /petdex lab <displayID>     a creature display ID
-- /petdex lab npc:<npcID>     a creature (NPC) ID
local _, ns = ...

local STAGE_SIZE = 230
local GAP = 10
local LOAD_DELAY = 1 -- seconds for a model to load before it's styled again
local GRID_COUNT = 20

local STATES = {
    { key = "tamed", label = "Tamed" },
    { key = "seen", label = "Seen" },
    { key = "unknown", label = "Unknown" },
}

-- Ambient and diffuse intensity. The first round's 0.8/0.8 was blown out.
local LIGHTS = {
    { name = "soft", ambient = 0.35, diffuse = 0.55 },
    { name = "medium", ambient = 0.5, diffuse = 0.7 },
    { name = "dim", ambient = 0.25, diffuse = 0.45 },
    { name = "bright", ambient = 0.8, diffuse = 0.8 },
}

local ANIMATIONS = {
    { 0, "stand" }, { 4, "walk" }, { 5, "run" }, { 16, "attack" }, { 1, "death" },
}

local RARE_BLUE = { 0.42, 0.66, 1 }
local WARM_LIGHT = { 1, 0.89, 0.69 }

local lab, grid
local stages = {} -- { state, model }
local source -- { kind = "display"|"npc"|"unit", id | unit }
local facing = math.rad(-60) -- 0 faces the camera; this is a three-quarter view
local camScale = 1.05 -- PlayerModel:SetCamDistanceScale; > 1 pulls the camera back
local lightIndex, animIndex, spinning = 1, 1, false
local dragging, dragX

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------
-- Vertical gradient on a plain texture: newer clients take colour objects,
-- older ones SetGradientAlpha. Falls back to a flat colour.
local function SetVerticalGradient(texture, bottom, top)
    texture:SetColorTexture(1, 1, 1, 1)
    if CreateColor and pcall(texture.SetGradient, texture, "VERTICAL",
        CreateColor(bottom[1], bottom[2], bottom[3], bottom[4]),
        CreateColor(top[1], top[2], top[3], top[4])) then
        return
    end
    if texture.SetGradientAlpha and pcall(texture.SetGradientAlpha, texture, "VERTICAL",
        bottom[1], bottom[2], bottom[3], bottom[4], top[1], top[2], top[3], top[4]) then
        return
    end
    texture:SetColorTexture(top[1], top[2], top[3], (top[4] + bottom[4]) / 2)
end

-- A soft ellipse: stacked circles (mask squashed to the texture's size) with
-- low alpha each fake a blur. Four steps showed visible rings; ten blend.
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW_STEPS = 10
local function AddGlow(parent, layer, width, height, color, alpha, x, y)
    for i = 1, GLOW_STEPS do
        local scale = 1 - (i - 1) * (0.85 / GLOW_STEPS)
        local texture = parent:CreateTexture(nil, layer, nil, 2)
        texture:SetSize(width * scale, height * scale)
        texture:SetPoint("CENTER", parent, "BOTTOM", x, y)
        texture:SetColorTexture(color[1], color[2], color[3], alpha * 2.2 / GLOW_STEPS)
        if parent.CreateMaskTexture then
            local mask = parent:CreateMaskTexture()
            mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(texture)
            texture:AddMaskTexture(mask)
        end
    end
end

local function AddBorder(frame, r, g, b)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetColorTexture(r, g, b, 1)
        if side == "TOP" or side == "BOTTOM" then
            line:SetHeight(1)
            line:SetPoint(side .. "LEFT")
            line:SetPoint(side .. "RIGHT")
        else
            line:SetWidth(1)
            line:SetPoint("TOP" .. side)
            line:SetPoint("BOTTOM" .. side)
        end
    end
end

---------------------------------------------------------------------------
-- Models
---------------------------------------------------------------------------
-- Forever takes the table form of SetLight; keep the classic form as a fallback.
local function SetModelLight(model, ambient, diffuse)
    if CreateVector3D and CreateColor and pcall(model.SetLight, model, true, {
        omnidirectional = false,
        point = CreateVector3D(0, -0.7, -0.7),
        ambientIntensity = ambient,
        ambientColor = CreateColor(1, 1, 1),
        diffuseIntensity = diffuse,
        diffuseColor = CreateColor(1, 1, 1),
    }) then
        return
    end
    pcall(model.SetLight, model, true, false, 0, -0.7, -0.7, ambient, 1, 1, 1, diffuse, 1, 1, 1)
end

local function LoadModel(model)
    pcall(model.ClearModel, model)
    local ok, err
    if source.kind == "display" then
        ok, err = pcall(model.SetDisplayInfo, model, source.id)
    elseif source.kind == "npc" then
        ok, err = pcall(model.SetCreature, model, source.id)
    else
        ok, err = pcall(model.SetUnit, model, source.unit)
    end
    if not ok then
        ns:Print("Loading the model failed:", tostring(err))
    end
end

local function StyleModel(stage)
    local model = stage.model
    pcall(model.SetCamDistanceScale, model, camScale)
    pcall(model.SetFacing, model, facing)
    if stage.state == "unknown" then
        SetModelLight(model, 0, 0)
    else
        local light = LIGHTS[lightIndex]
        SetModelLight(model, light.ambient, light.diffuse)
        pcall(model.SetDesaturation, model, stage.state == "seen" and 1 or 0)
    end
end

local function StyleAll()
    for _, stage in ipairs(stages) do
        StyleModel(stage)
    end
end

local function ReadDisplayID()
    local model = stages[1] and stages[1].model
    if not model then return end
    local ok, value = pcall(model.GetDisplayInfo, model)
    if ok and not ns.IsSecret(value) and type(value) == "number" and value > 0 then
        return value
    end
end

local function Load()
    for _, stage in ipairs(stages) do
        LoadModel(stage.model)
        StyleModel(stage)
    end
    -- Loading can reset light and camera, so style again once it's in.
    C_Timer.After(LOAD_DELAY, function()
        StyleAll()
        local displayID = ReadDisplayID()
        ns:Print(("Model lab: %s%s. Light \"%s\", camera distance %.2f."):format(
            source.kind == "unit" and "target" or (source.kind .. " " .. source.id),
            displayID and (", display ID " .. displayID) or "",
            LIGHTS[lightIndex].name, camScale))
    end)
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local function ApplyFacing()
    for _, stage in ipairs(stages) do
        pcall(stage.model.SetFacing, stage.model, facing)
    end
end

local function ChangeCamera(delta)
    camScale = math.max(0.5, math.min(4, camScale + delta))
    StyleAll()
    ns:Print(("Camera distance %.2f"):format(camScale))
end

local function NextLight()
    lightIndex = lightIndex % #LIGHTS + 1
    StyleAll()
    local light = LIGHTS[lightIndex]
    ns:Print(("Light \"%s\" (ambient %.2f, diffuse %.2f)"):format(light.name, light.ambient, light.diffuse))
end

local function NextAnimation()
    animIndex = animIndex % #ANIMATIONS + 1
    local id, name = ANIMATIONS[animIndex][1], ANIMATIONS[animIndex][2]
    for _, stage in ipairs(stages) do
        pcall(stage.model.SetAnimation, stage.model, id)
    end
    ns:Print(("Animation %d (%s)"):format(id, name))
end

-- Shows GRID_COUNT small models under the lab and compares the frame rate.
local function ToggleGrid()
    if grid and grid:IsShown() then
        grid:Hide()
        return
    end
    local cell, perRow = 64, 10
    if not grid then
        grid = CreateFrame("Frame", nil, lab)
        grid:SetSize(perRow * (cell + 4) + 4, math.ceil(GRID_COUNT / perRow) * (cell + 4) + 4)
        grid:SetPoint("TOP", lab, "BOTTOM", 0, -6)
        local bg = grid:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.065, 0.08, 0.96)
        grid.models = {}
        for i = 1, GRID_COUNT do
            local model = CreateFrame("PlayerModel", nil, grid)
            model:SetSize(cell, cell)
            model:SetPoint("TOPLEFT", 4 + ((i - 1) % perRow) * (cell + 4), -4 - math.floor((i - 1) / perRow) * (cell + 4))
            grid.models[i] = model
        end
    end
    local before = GetFramerate()
    grid:Show()
    for i, model in ipairs(grid.models) do
        LoadModel(model)
        pcall(model.SetFacing, model, facing + i * 0.3)
    end
    C_Timer.After(3, function()
        ns:Print(("Grid test: %d models. FPS %.0f before, %.0f with the grid showing."):format(GRID_COUNT, before, GetFramerate()))
    end)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function CreateStage(state, x, y)
    local holder = CreateFrame("Frame", nil, lab)
    holder:SetSize(STAGE_SIZE, STAGE_SIZE)
    holder:SetPoint("TOPLEFT", x, y)
    AddBorder(holder, 0.35, 0.29, 0.17)

    -- Backdrop: warm floor fading to near black at the top.
    local backdrop = holder:CreateTexture(nil, "BACKGROUND", nil, 0)
    backdrop:SetAllPoints()
    if state.key == "unknown" then
        SetVerticalGradient(backdrop, { 0.11, 0.12, 0.15, 1 }, { 0.04, 0.045, 0.06, 1 })
    else
        SetVerticalGradient(backdrop, { 0.24, 0.14, 0.09, 1 }, { 0.05, 0.035, 0.03, 1 })
    end

    -- Spotlight beam from the top (faint for seen, none for unknown). Nested
    -- beams of falling width soften its edges.
    if state.key ~= "unknown" then
        local strength = state.key == "tamed" and 0.22 or 0.08
        for i, widthScale in ipairs({ 0.65, 0.5, 0.36 }) do
            local beam = holder:CreateTexture(nil, "BACKGROUND", nil, 1)
            beam:SetPoint("TOP")
            beam:SetSize(STAGE_SIZE * widthScale, STAGE_SIZE * (0.75 + i * 0.05))
            SetVerticalGradient(beam, { WARM_LIGHT[1], WARM_LIGHT[2], WARM_LIGHT[3], 0 },
                { WARM_LIGHT[1], WARM_LIGHT[2], WARM_LIGHT[3], strength / 2 })
        end
    end

    -- Ground glow at the beast's feet: rarity colour when tamed, grey when
    -- seen. Unknown gets a gold glow behind the body instead, so the black
    -- silhouette stands out.
    local feet = STAGE_SIZE * 0.27
    if state.key == "tamed" then
        AddGlow(holder, "BACKGROUND", STAGE_SIZE * 0.8, 38, RARE_BLUE, 0.6, 0, feet)
    elseif state.key == "seen" then
        AddGlow(holder, "BACKGROUND", STAGE_SIZE * 0.7, 32, { 0.6, 0.6, 0.6 }, 0.3, 0, feet)
    else
        AddGlow(holder, "BACKGROUND", STAGE_SIZE * 0.85, STAGE_SIZE * 0.7, { 0.79, 0.64, 0.36 }, 0.4, 0, STAGE_SIZE * 0.5)
    end

    local label = lab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOP", holder, "BOTTOM", 0, -5)
    label:SetText(state.label)

    local model = CreateFrame("PlayerModel", nil, holder)
    model:SetAllPoints()
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function()
        dragging = true
        dragX = GetCursorPosition()
    end)
    model:SetScript("OnMouseUp", function() dragging = false end)
    table.insert(stages, { state = state.key, model = model })
end

local function CreateLab()
    local width = GAP + #STATES * (STAGE_SIZE + GAP)
    lab = CreateFrame("Frame", "PetDexModelLab", UIParent)
    lab:SetSize(width, 40 + STAGE_SIZE + 26 + 44)
    lab:SetPoint("CENTER")
    lab:SetFrameStrata("DIALOG")
    lab:SetMovable(true)
    lab:EnableMouse(true)
    lab:RegisterForDrag("LeftButton")
    lab:SetScript("OnDragStart", lab.StartMoving)
    lab:SetScript("OnDragStop", lab.StopMovingOrSizing)
    lab:SetScript("OnHide", function()
        spinning, dragging = false, false
    end)
    table.insert(UISpecialFrames, "PetDexModelLab") -- Escape closes it

    local bg = lab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.065, 0.08, 0.97)
    AddBorder(lab, 0.79, 0.64, 0.36)

    local title = lab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("PetDex model lab")

    local close = CreateFrame("Button", nil, lab, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    for i, state in ipairs(STATES) do
        CreateStage(state, GAP + (i - 1) * (STAGE_SIZE + GAP), -36)
    end

    local previous
    local function AddButton(text, buttonWidth, onClick)
        local button = CreateFrame("Button", nil, lab, "UIPanelButtonTemplate")
        button:SetSize(buttonWidth, 24)
        button:SetText(text)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("BOTTOMLEFT", GAP, 12)
        end
        button:SetScript("OnClick", onClick)
        previous = button
    end
    AddButton("Turn left", 76, function() facing = facing - math.pi / 8; ApplyFacing() end)
    AddButton("Turn right", 80, function() facing = facing + math.pi / 8; ApplyFacing() end)
    AddButton("Spin", 52, function() spinning = not spinning end)
    AddButton("Closer", 64, function() ChangeCamera(-0.15) end)
    AddButton("Farther", 68, function() ChangeCamera(0.15) end)
    AddButton("Light", 56, NextLight)
    AddButton("Animation", 80, NextAnimation)
    AddButton("Grid x" .. GRID_COUNT, 72, ToggleGrid)
    AddButton("Reload", 64, Load)

    lab:SetScript("OnUpdate", function(_, elapsed)
        local changed = false
        if spinning then
            facing = facing + elapsed * 0.8
            changed = true
        end
        if dragging then
            if IsMouseButtonDown("LeftButton") then
                local x = GetCursorPosition()
                facing = facing + (x - dragX) * 0.01
                dragX = x
                changed = true
            else
                dragging = false
            end
        end
        if changed then
            ApplyFacing()
        end
    end)
end

function ns:OpenModelLab(argument)
    argument = argument or ""
    local npcID = argument:match("^npc:(%d+)$")
    local displayID = argument:match("^(%d+)$")
    if npcID then
        source = { kind = "npc", id = tonumber(npcID) }
    elseif displayID then
        source = { kind = "display", id = tonumber(displayID) }
    elseif argument == "" or argument == "target" then
        if not UnitExists("target") then
            self:Print("Target a beast, or use /petdex lab <displayID> or /petdex lab npc:<npcID>.")
            return
        end
        source = { kind = "unit", unit = "target" }
    else
        self:Print("Usage: /petdex lab [displayID | npc:<npcID>] (default: your target)")
        return
    end
    if not lab then
        CreateLab()
    end
    lab:Show()
    Load()
end
