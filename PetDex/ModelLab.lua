-- Model lab (debug): find a way to frame every beast automatically.
--
-- A fixed camera distance and offset tuned on a lion (Broken Tooth) left a
-- hunter's bear huge, cropped and off centre, so each model must be fitted
-- on its own. This round compares two auto-fit methods, side by side:
--   PlayerModel  UseModelCenterToTransform(true) to turn around the middle,
--                SetModelScale to normalise the size measured from a hidden
--                ModelScene actor's bounding box
--   ModelScene   SetUseCenterForOrigin on the actor, camera placed from the
--                bounding box; the silhouette is retried with the light off
-- Rows: Tamed (soft light, spotlight, rarity glow) and Unknown (silhouette).
--
-- /petdex lab                 your target
-- /petdex lab <displayID>     a creature display ID
-- /petdex lab npc:<npcID>     a creature (NPC) ID
local _, ns = ...

local STAGE_SIZE = 220
local GAP = 10
local LOAD_DELAY = 1 -- seconds for a model to load before the next step
local TARGET_SIZE = 2.5 -- PlayerModel: scale every beast to this many yards
local FIT = 1.5 -- ModelScene: camera distance per yard of model size

local COLUMNS = {
    { key = "player", label = "PlayerModel: centred + scaled" },
    { key = "scene", label = "ModelScene: centred + fitted" },
}
local ROWS = {
    { key = "tamed", label = "Tamed" },
    { key = "unknown", label = "Unknown" },
}

local LIGHT = { ambient = 0.35, diffuse = 0.55 } -- "soft", picked in game

local ANIMATIONS = {
    { 0, "stand" }, { 4, "walk" }, { 5, "run" }, { 16, "attack" }, { 1, "death" },
}

local RARE_BLUE = { 0.42, 0.66, 1 }
local WARM_LIGHT = { 1, 0.89, 0.69 }

local lab, measurer, measureActor
local stages = {} -- { column, state, frame, actor }
local source -- { kind = "display"|"npc"|"unit", id | unit }
local facing = math.rad(-60) -- 0 faces the camera; this is a three-quarter view
local camScale = 1.05 -- PlayerModel:SetCamDistanceScale, picked in game
local zoom = 1 -- ModelScene multiplier on the fitted distance
local offsetY, offsetZ = 0, 0 -- PlayerModel:SetPosition nudge; - is left / down
local NUDGE = 0.1
local measured -- { size, centerZ } from the bounding box
local animIndex, spinning = 1, false
local dragging, dragX

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------
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

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW_STEPS = 10
local function AddGlow(parent, width, height, color, alpha, y)
    for i = 1, GLOW_STEPS do
        local scale = 1 - (i - 1) * (0.85 / GLOW_STEPS)
        local texture = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
        texture:SetSize(width * scale, height * scale)
        texture:SetPoint("CENTER", parent, "BOTTOM", 0, y)
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

-- Runs obj:method(...) if it exists; returns "ok", "missing" or "error".
local function Try(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return "missing" end
    return pcall(fn, obj, ...) and "ok" or "error"
end

---------------------------------------------------------------------------
-- PlayerModel column
---------------------------------------------------------------------------
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

local function LoadPlayerModel(model)
    pcall(model.ClearModel, model)
    if source.kind == "display" then
        pcall(model.SetDisplayInfo, model, source.id)
    elseif source.kind == "npc" then
        pcall(model.SetCreature, model, source.id)
    else
        pcall(model.SetUnit, model, source.unit)
    end
end

local function StylePlayerModel(stage)
    local model = stage.frame
    pcall(model.UseModelCenterToTransform, model, true)
    if measured then
        pcall(model.SetModelScale, model, TARGET_SIZE / measured.size)
    end
    pcall(model.SetCamDistanceScale, model, camScale)
    pcall(model.SetPosition, model, 0, offsetY, offsetZ)
    pcall(model.SetFacing, model, facing)
    if stage.state == "unknown" then
        SetModelLight(model, 0, 0)
    else
        SetModelLight(model, LIGHT.ambient, LIGHT.diffuse)
    end
end

---------------------------------------------------------------------------
-- ModelScene column, and the hidden actor that measures the model
---------------------------------------------------------------------------
local function LoadActor(actor, displayID)
    pcall(actor.ClearModel, actor)
    if displayID then
        pcall(actor.SetModelByCreatureDisplayID, actor, displayID)
    elseif source.kind == "unit" then
        pcall(actor.SetModelByUnit, actor, source.unit)
    end
end

-- Bounding box as six numbers (Forever) or two vectors (newer clients).
local function Measure(actor)
    local fn = actor and actor.GetActiveBoundingBox
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d, e, f = pcall(fn, actor)
    if not ok then return end
    if type(a) == "table" and type(b) == "table" then
        a, b, c, d, e, f = a.x, a.y, a.z, b.x, b.y, b.z
    end
    if type(a) ~= "number" or type(f) ~= "number" then return end
    local size = math.max(d - a, e - b, f - c)
    if size <= 0 then return end
    return { size = size, centerZ = (c + f) / 2 }
end

local function StyleScene(stage)
    local scene, actor = stage.frame, stage.actor
    if stage.state == "unknown" then
        -- Round one: zero light colours left the model lit. Try the light off.
        pcall(scene.SetLightVisible, scene, false)
        pcall(scene.SetLightAmbientColor, scene, 0, 0, 0)
        pcall(scene.SetLightDiffuseColor, scene, 0, 0, 0)
    else
        pcall(scene.SetLightVisible, scene, true)
        pcall(scene.SetLightAmbientColor, scene, LIGHT.ambient * 2, LIGHT.ambient * 2, LIGHT.ambient * 2)
        pcall(scene.SetLightDiffuseColor, scene, LIGHT.diffuse * 1.4, LIGHT.diffuse * 1.4, LIGHT.diffuse * 1.4)
        pcall(scene.SetLightDirection, scene, -0.7, 0.3, -0.6)
    end
    if not actor then return end
    pcall(actor.SetUseCenterForOrigin, actor, true, true, true)
    pcall(actor.SetPosition, actor, 0, 0, 0)
    pcall(actor.SetYaw, actor, facing)
    -- Centred origin: the model's middle is at 0,0,0 and the camera sits on
    -- +X looking back at it.
    local distance = (measured and measured.size or 2.5) * FIT * zoom
    pcall(scene.SetCameraPosition, scene, distance, 0, 0)
    pcall(scene.SetCameraOrientationByYawPitchRoll, scene, math.pi, 0, 0)
    pcall(scene.SetCameraFieldOfView, scene, math.rad(40))
    pcall(scene.SetCameraNearClip, scene, 0.01)
    pcall(scene.SetCameraFarClip, scene, 200)
end

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
local function StyleAll()
    for _, stage in ipairs(stages) do
        if stage.column == "player" then
            StylePlayerModel(stage)
        else
            StyleScene(stage)
        end
    end
end

local function ReadDisplayID()
    for _, stage in ipairs(stages) do
        if stage.column == "player" then
            local ok, value = pcall(stage.frame.GetDisplayInfo, stage.frame)
            if ok and not ns.IsSecret(value) and type(value) == "number" and value > 0 then
                return value
            end
            return
        end
    end
end

local function Report(displayID)
    local player, scene
    for _, stage in ipairs(stages) do
        if stage.column == "player" and not player then player = stage.frame end
        if stage.column == "scene" and stage.actor and not scene then scene = stage.actor end
    end
    ns:Print(("Model lab: %s%s."):format(
        source.kind == "unit" and "target" or (source.kind .. " " .. source.id),
        displayID and (", display ID " .. displayID) or ""))
    print(("  Measured size: %s"):format(measured
        and ("%.2f yards, PlayerModel scale %.2f"):format(measured.size, TARGET_SIZE / measured.size)
        or "|cffff4040none (no bounding box)|r"))
    print(("  PlayerModel:UseModelCenterToTransform %s, SetModelScale %s"):format(
        Try(player, "UseModelCenterToTransform", true), Try(player, "SetModelScale", 1)))
    print(("  Actor:SetUseCenterForOrigin %s"):format(Try(scene, "SetUseCenterForOrigin", true, true, true)))
    print("  Which column frames the beast whole and centred, and does it stay centred while it spins?")
    StyleAll() -- the Try calls above reset the model scale
end

local function Load()
    measured = nil
    local directID = source.kind == "display" and source.id or nil
    for _, stage in ipairs(stages) do
        if stage.column == "player" then
            LoadPlayerModel(stage.frame)
        end
    end
    StyleAll()

    -- The display ID (read from a PlayerModel when loading by NPC) lets the
    -- actors load the same look.
    C_Timer.After(LOAD_DELAY, function()
        local displayID = directID or ReadDisplayID()
        LoadActor(measureActor, displayID)
        for _, stage in ipairs(stages) do
            if stage.actor then
                LoadActor(stage.actor, displayID)
            end
        end
        C_Timer.After(LOAD_DELAY, function()
            measured = Measure(measureActor)
            StyleAll()
            Report(displayID)
        end)
    end)
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local function ApplyFacing()
    for _, stage in ipairs(stages) do
        if stage.column == "player" then
            pcall(stage.frame.SetFacing, stage.frame, facing)
        elseif stage.actor then
            pcall(stage.actor.SetYaw, stage.actor, facing)
        end
    end
end

local function ChangeDistance(step)
    camScale = math.max(0.4, math.min(4, camScale + step))
    zoom = math.max(0.4, math.min(4, zoom + step))
    StyleAll()
    ns:Print(("PlayerModel camera distance %.2f, ModelScene zoom %.2f"):format(camScale, zoom))
end

local function Nudge(dy, dz)
    offsetY, offsetZ = offsetY + dy, offsetZ + dz
    StyleAll()
    ns:Print(("PlayerModel offset: sideways %.2f, up/down %.2f"):format(offsetY, offsetZ))
end

local function NextAnimation()
    animIndex = animIndex % #ANIMATIONS + 1
    local id, name = ANIMATIONS[animIndex][1], ANIMATIONS[animIndex][2]
    for _, stage in ipairs(stages) do
        if stage.column == "player" then
            pcall(stage.frame.SetAnimation, stage.frame, id)
        elseif stage.actor then
            pcall(stage.actor.SetAnimation, stage.actor, id)
        end
    end
    ns:Print(("Animation %d (%s)"):format(id, name))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function DecorateStage(holder, state)
    local backdrop = holder:CreateTexture(nil, "BACKGROUND", nil, 0)
    backdrop:SetAllPoints()
    if state == "unknown" then
        SetVerticalGradient(backdrop, { 0.11, 0.12, 0.15, 1 }, { 0.04, 0.045, 0.06, 1 })
        AddGlow(holder, STAGE_SIZE * 0.85, STAGE_SIZE * 0.7, { 0.79, 0.64, 0.36 }, 0.4, STAGE_SIZE * 0.5)
        return
    end
    SetVerticalGradient(backdrop, { 0.24, 0.14, 0.09, 1 }, { 0.05, 0.035, 0.03, 1 })
    for i, widthScale in ipairs({ 0.65, 0.5, 0.36 }) do
        local beam = holder:CreateTexture(nil, "BACKGROUND", nil, 1)
        beam:SetPoint("TOP")
        beam:SetSize(STAGE_SIZE * widthScale, STAGE_SIZE * (0.75 + i * 0.05))
        SetVerticalGradient(beam, { WARM_LIGHT[1], WARM_LIGHT[2], WARM_LIGHT[3], 0 },
            { WARM_LIGHT[1], WARM_LIGHT[2], WARM_LIGHT[3], 0.11 })
    end
    AddGlow(holder, STAGE_SIZE * 0.8, 38, RARE_BLUE, 0.6, STAGE_SIZE * 0.22)
end

local function StartDrag()
    dragging = true
    dragX = GetCursorPosition()
end

local function CreateStage(column, row, x, y)
    local holder = CreateFrame("Frame", nil, lab)
    holder:SetSize(STAGE_SIZE, STAGE_SIZE)
    holder:SetPoint("TOPLEFT", x, y)
    AddBorder(holder, 0.35, 0.29, 0.17)
    DecorateStage(holder, row.key)

    local stage = { column = column.key, state = row.key }
    if column.key == "player" then
        stage.frame = CreateFrame("PlayerModel", nil, holder)
    else
        local ok, scene = pcall(CreateFrame, "ModelScene", nil, holder)
        if not ok then return end
        stage.frame = scene
        local okActor, actor = pcall(scene.CreateActor, scene)
        stage.actor = okActor and actor or nil
    end
    stage.frame:SetAllPoints()
    stage.frame:EnableMouse(true)
    stage.frame:SetScript("OnMouseDown", StartDrag)
    stage.frame:SetScript("OnMouseUp", function() dragging = false end)
    table.insert(stages, stage)
end

local function CreateLab()
    local labelWidth = 70
    local width = labelWidth + #COLUMNS * (STAGE_SIZE + GAP) + GAP
    local top = 54
    lab = CreateFrame("Frame", "PetDexModelLab", UIParent)
    lab:SetSize(width, top + #ROWS * (STAGE_SIZE + GAP) + 72)
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
    title:SetText("PetDex model lab: auto-fit")

    local close = CreateFrame("Button", nil, lab, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- Hidden actor that measures the model; models only load while shown.
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, lab)
    if ok then
        measurer = scene
        measurer:SetSize(32, 32)
        measurer:SetPoint("BOTTOMLEFT")
        measurer:SetAlpha(0)
        local okActor, actor = pcall(measurer.CreateActor, measurer)
        measureActor = okActor and actor or nil
    end

    for c, column in ipairs(COLUMNS) do
        local x = labelWidth + (c - 1) * (STAGE_SIZE + GAP)
        local heading = lab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("BOTTOM", lab, "TOPLEFT", x + STAGE_SIZE / 2, -top + 6)
        heading:SetText(column.label)
        for r, row in ipairs(ROWS) do
            local y = -top - (r - 1) * (STAGE_SIZE + GAP)
            if c == 1 then
                local label = lab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                label:SetPoint("RIGHT", lab, "TOPLEFT", labelWidth - 8, y - STAGE_SIZE / 2)
                label:SetText(row.label)
            end
            CreateStage(column, row, x, y)
        end
    end

    local previous
    local rowBottom = 40
    local function AddButton(text, buttonWidth, onClick)
        local button = CreateFrame("Button", nil, lab, "UIPanelButtonTemplate")
        button:SetSize(buttonWidth, 24)
        button:SetText(text)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("BOTTOMLEFT", GAP, rowBottom)
        end
        button:SetScript("OnClick", onClick)
        previous = button
    end
    AddButton("Turn left", 76, function() facing = facing - math.pi / 8; ApplyFacing() end)
    AddButton("Turn right", 80, function() facing = facing + math.pi / 8; ApplyFacing() end)
    AddButton("Spin", 52, function() spinning = not spinning end)
    AddButton("Closer", 64, function() ChangeDistance(-0.15) end)
    AddButton("Farther", 68, function() ChangeDistance(0.15) end)
    AddButton("Animation", 80, NextAnimation)
    AddButton("Reload", 64, Load)

    previous, rowBottom = nil, 12
    AddButton("Move left", 80, function() Nudge(-NUDGE, 0) end)
    AddButton("Move right", 84, function() Nudge(NUDGE, 0) end)
    AddButton("Move up", 72, function() Nudge(0, NUDGE) end)
    AddButton("Move down", 84, function() Nudge(0, -NUDGE) end)

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
