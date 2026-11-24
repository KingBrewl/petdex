-- Model lab (debug): can this client render the dex the way the mockup does?
--
-- Opens a window showing one beast in each state the dex needs, drawn with
-- both of the client's model widgets:
--   Tamed               normal lighting
--   Seen                desaturated / dimly lit
--   Unknown (fog)       black fog over the model, for a silhouette
--   Unknown (no light)  all lights at zero, the other way to get a silhouette
-- Rows: PlayerModel (the classic widget) and ModelScene + actor (the newer
-- one). Buttons test turning, drag-to-turn, zoom, animations, and how the
-- frame rate holds up with a grid of models.
--
-- /petdex lab                 your target
-- /petdex lab <displayID>     a creature display ID
-- /petdex lab npc:<npcID>     a creature (NPC) ID
-- Each API call is checked and the results are printed to chat; what they
-- look like has to be judged by eye in the window.
local _, ns = ...

local STAGE_SIZE = 170
local GAP = 10
local ROW_HEIGHT = 16 + STAGE_SIZE + 22
local LOAD_DELAY = 1.5 -- seconds for models to load before the next step
local GRID_COUNT = 20

local STATES = {
    { key = "tamed", label = "Tamed" },
    { key = "seen", label = "Seen (grey)" },
    { key = "fog", label = "Unknown (fog)" },
    { key = "dark", label = "Unknown (no light)" },
}

local ANIMATIONS = {
    { 0, "stand" }, { 4, "walk" }, { 5, "run" }, { 16, "attack" }, { 1, "death" },
}

local lab
local grid
local stages = {} -- { kind = "model"|"scene", state, frame, actor, baseDistance, centerZ }
local results, resultOrder = {}, {}
local source -- { kind = "display"|"npc"|"unit", id | unit }
local facing, zoom, animIndex, spinning = math.rad(-35), 1, 1, false
local dragging, dragX
local sceneCreateStatus -- recorded when the window is built, reported on each load

---------------------------------------------------------------------------
-- Checked calls
---------------------------------------------------------------------------
-- An error stays recorded even if the same call later succeeds elsewhere.
local function Record(label, status)
    local previous = results[label]
    if not previous then
        table.insert(resultOrder, label)
    elseif previous:find("^error") then
        return
    end
    results[label] = status
end

local function Call(label, obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then
        Record(label, "missing")
        return false
    end
    local ok, err = pcall(fn, obj, ...)
    Record(label, ok and "ok" or ("error: " .. tostring(err)))
    return ok
end

local function Report(displayID)
    ns:Print("Model lab results" .. (displayID and (" for display ID " .. displayID) or "") .. ":")
    for _, label in ipairs(resultOrder) do
        local status = results[label]
        local color = status:find("^ok") and "40ff40" or (status == "missing" and "888888" or "ff4040")
        print(("  %s: |cff%s%s|r"):format(label, color, status))
    end
    print("  Now check the window by eye: is each Unknown a clean black silhouette, does Seen look grey, and does the ModelScene row show the beast at all?")
end

---------------------------------------------------------------------------
-- PlayerModel row
---------------------------------------------------------------------------
-- Classic clients take SetLight(enabled, omni, dirX, dirY, dirZ, ambI, ambR,
-- ambG, ambB, difI, difR, difG, difB); newer ones take (enabled, lightTable).
local function SetModelLight(model, ambient, diffuse)
    if type(model.SetLight) ~= "function" then
        Record("PlayerModel:SetLight", "missing")
        return
    end
    if pcall(model.SetLight, model, true, false, 0, -0.7, -0.7, ambient, 1, 1, 1, diffuse, 1, 1, 1) then
        Record("PlayerModel:SetLight", "ok (classic arguments)")
        return
    end
    if CreateVector3D and CreateColor then
        local ok, err = pcall(model.SetLight, model, true, {
            omnidirectional = false,
            point = CreateVector3D(0, -0.7, -0.7),
            ambientIntensity = ambient,
            ambientColor = CreateColor(1, 1, 1),
            diffuseIntensity = diffuse,
            diffuseColor = CreateColor(1, 1, 1),
        })
        Record("PlayerModel:SetLight", ok and "ok (table argument)" or ("error: " .. tostring(err)))
    else
        Record("PlayerModel:SetLight", "error: no signature worked")
    end
end

local function LoadModel(model)
    pcall(model.ClearModel, model)
    if source.kind == "display" then
        Call("PlayerModel:SetDisplayInfo", model, "SetDisplayInfo", source.id)
    elseif source.kind == "npc" then
        Call("PlayerModel:SetCreature", model, "SetCreature", source.id)
    else
        Call("PlayerModel:SetUnit", model, "SetUnit", source.unit)
    end
end

local function StyleModel(stage)
    local model = stage.frame
    if stage.state == "tamed" then
        SetModelLight(model, 0.8, 0.8)
    elseif stage.state == "seen" then
        Call("PlayerModel:SetDesaturation", model, "SetDesaturation", 1)
        SetModelLight(model, 0.4, 0.3)
    elseif stage.state == "fog" then
        SetModelLight(model, 0.8, 0.8)
        Call("PlayerModel:SetFogColor", model, "SetFogColor", 0, 0, 0)
        Call("PlayerModel:SetFogNear", model, "SetFogNear", 0)
        Call("PlayerModel:SetFogFar", model, "SetFogFar", 0.1)
    else
        SetModelLight(model, 0, 0)
    end
end

---------------------------------------------------------------------------
-- ModelScene row
---------------------------------------------------------------------------
local function SetSceneLight(scene, ambient, diffuse)
    Call("ModelScene:SetLightVisible", scene, "SetLightVisible", true)
    Call("ModelScene:SetLightAmbientColor", scene, "SetLightAmbientColor", ambient, ambient, ambient)
    Call("ModelScene:SetLightDiffuseColor", scene, "SetLightDiffuseColor", diffuse, diffuse, diffuse)
    Call("ModelScene:SetLightDirection", scene, "SetLightDirection", -0.7, 0.3, -0.6)
end

local function StyleScene(stage)
    local scene, actor = stage.frame, stage.actor
    if stage.state == "tamed" then
        SetSceneLight(scene, 0.7, 0.8)
    elseif stage.state == "seen" then
        SetSceneLight(scene, 0.45, 0.35)
        if actor then
            Call("Actor:SetDesaturation", actor, "SetDesaturation", 1)
        end
    elseif stage.state == "fog" then
        SetSceneLight(scene, 0.7, 0.8)
        Call("ModelScene:SetFogColor", scene, "SetFogColor", 0, 0, 0)
        Call("ModelScene:SetFogNear", scene, "SetFogNear", 0)
        Call("ModelScene:SetFogFar", scene, "SetFogFar", 0.1)
    else
        SetSceneLight(scene, 0, 0)
    end
end

local function LoadActor(stage, displayID)
    local actor = stage.actor
    if not actor then return end
    pcall(actor.ClearModel, actor)
    if displayID then
        Call("Actor:SetModelByCreatureDisplayID", actor, "SetModelByCreatureDisplayID", displayID)
    elseif source.kind == "unit" then
        Call("Actor:SetModelByUnit", actor, "SetModelByUnit", source.unit)
    else
        Record("Actor: load by NPC ID", "not possible without a display ID")
    end
end

-- The camera sits on +X looking back at the actor at the origin.
local function ApplyCamera(stage)
    local scene = stage.frame
    local distance = (stage.baseDistance or 4) * zoom
    Call("ModelScene:SetCameraPosition", scene, "SetCameraPosition", distance, 0, stage.centerZ or 1)
    Call("ModelScene:SetCameraOrientationByYawPitchRoll", scene, "SetCameraOrientationByYawPitchRoll", math.pi, 0, 0)
    Call("ModelScene:SetCameraFieldOfView", scene, "SetCameraFieldOfView", math.rad(40))
    Call("ModelScene:SetCameraNearClip", scene, "SetCameraNearClip", 0.01)
    Call("ModelScene:SetCameraFarClip", scene, "SetCameraFarClip", 100)
end

-- Fit the camera to the model's bounding box (vectors on newer clients,
-- six numbers on older ones).
local function FrameActor(stage)
    local actor = stage.actor
    local minX, minY, minZ, maxX, maxY, maxZ = -1, -1, 0, 1, 1, 2
    local label = "Actor:GetActiveBoundingBox"
    if type(actor.GetActiveBoundingBox) ~= "function" then
        Record(label, "missing")
    else
        local ok, a, b, c, d, e, f = pcall(actor.GetActiveBoundingBox, actor)
        if ok and type(a) == "table" and type(b) == "table" then
            minX, minY, minZ, maxX, maxY, maxZ = a.x, a.y, a.z, b.x, b.y, b.z
            Record(label, "ok (vectors)")
        elseif ok and type(a) == "number" and type(f) == "number" then
            minX, minY, minZ, maxX, maxY, maxZ = a, b, c, d, e, f
            Record(label, "ok (numbers)")
        else
            Record(label, ok and "error: no bounds (model not loaded?)" or ("error: " .. tostring(a)))
        end
    end
    local size = math.max(maxX - minX, maxY - minY, maxZ - minZ, 0.5)
    stage.baseDistance = size * 1.9 -- fits the model in a 40 degree field of view
    stage.centerZ = (minZ + maxZ) / 2
    ApplyCamera(stage)
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local function ApplyFacing()
    for _, stage in ipairs(stages) do
        if stage.kind == "model" then
            pcall(stage.frame.SetFacing, stage.frame, facing)
        elseif stage.actor then
            pcall(stage.actor.SetYaw, stage.actor, facing)
        end
    end
end

local function ApplyZoom()
    for _, stage in ipairs(stages) do
        if stage.kind == "model" then
            Call("PlayerModel:SetCamDistanceScale", stage.frame, "SetCamDistanceScale", zoom)
        elseif stage.actor then
            ApplyCamera(stage)
        end
    end
end

local function NextAnimation()
    animIndex = animIndex % #ANIMATIONS + 1
    local id, name = ANIMATIONS[animIndex][1], ANIMATIONS[animIndex][2]
    local okModel, okActor = true, true
    for _, stage in ipairs(stages) do
        if stage.kind == "model" then
            okModel = Call("PlayerModel:SetAnimation", stage.frame, "SetAnimation", id) and okModel
        elseif stage.actor then
            okActor = Call("Actor:SetAnimation", stage.actor, "SetAnimation", id) and okActor
        end
    end
    ns:Print(("Animation %d (%s): PlayerModel %s, ModelScene %s"):format(id, name,
        okModel and "ok" or "failed", okActor and "ok" or "failed"))
end

local function Load()
    wipe(results)
    wipe(resultOrder)
    if sceneCreateStatus then
        Record("CreateFrame(\"ModelScene\")", sceneCreateStatus)
    end
    local directID = source.kind == "display" and source.id or nil

    for _, stage in ipairs(stages) do
        if stage.kind == "model" then
            LoadModel(stage.frame)
            StyleModel(stage)
            Call("PlayerModel:SetFacing", stage.frame, "SetFacing", facing)
        else
            StyleScene(stage)
            if directID then
                LoadActor(stage, directID)
            end
        end
    end

    C_Timer.After(LOAD_DELAY, function()
        local displayID = directID
        if not displayID then
            -- Learn the display ID from the loaded PlayerModel so the
            -- ModelScene row can load the same look.
            local model = stages[1] and stages[1].frame
            if model and type(model.GetDisplayInfo) == "function" then
                local ok, value = pcall(model.GetDisplayInfo, model)
                if ok and not ns.IsSecret(value) and type(value) == "number" and value > 0 then
                    displayID = value
                end
            end
            for _, stage in ipairs(stages) do
                if stage.kind == "scene" then
                    LoadActor(stage, displayID)
                end
            end
        end

        C_Timer.After(LOAD_DELAY, function()
            for _, stage in ipairs(stages) do
                if stage.kind == "model" then
                    -- Loading a model can reset fog and light; apply them again.
                    StyleModel(stage)
                elseif stage.actor then
                    FrameActor(stage)
                    StyleScene(stage)
                    Call("Actor:SetYaw", stage.actor, "SetYaw", facing)
                end
            end
            Report(displayID)
        end)
    end)
end

-- Shows GRID_COUNT small models under the lab and compares the frame rate.
local function ToggleGrid()
    if grid and grid:IsShown() then
        grid:Hide()
        ns:Print("Grid test hidden.")
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

local function StartDrag()
    dragging = true
    dragX = GetCursorPosition()
end

local function CreateStage(kind, state, x, y)
    local holder = CreateFrame("Frame", nil, lab)
    holder:SetSize(STAGE_SIZE, STAGE_SIZE)
    holder:SetPoint("TOPLEFT", x, y)
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.16, 0.10, 0.07, 1)
    AddBorder(holder, 0.35, 0.29, 0.17)

    local label = lab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOP", holder, "BOTTOM", 0, -4)
    label:SetText(state.label)

    local stage = { kind = kind, state = state.key }
    if kind == "model" then
        stage.frame = CreateFrame("PlayerModel", nil, holder)
    else
        local ok, scene = pcall(CreateFrame, "ModelScene", nil, holder)
        sceneCreateStatus = ok and "ok" or ("error: " .. tostring(scene))
        if not ok then return end
        stage.frame = scene
        if type(scene.CreateActor) == "function" then
            local okActor, actor = pcall(scene.CreateActor, scene)
            if okActor then
                stage.actor = actor
            end
        end
    end
    stage.frame:SetAllPoints()
    stage.frame:EnableMouse(true)
    stage.frame:SetScript("OnMouseDown", StartDrag)
    stage.frame:SetScript("OnMouseUp", function() dragging = false end)
    table.insert(stages, stage)
end

local function CreateLab()
    local width = GAP + #STATES * (STAGE_SIZE + GAP)
    lab = CreateFrame("Frame", "PetDexModelLab", UIParent)
    lab:SetSize(width, 36 + 2 * ROW_HEIGHT + 46)
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
    bg:SetColorTexture(0.06, 0.065, 0.08, 0.96)
    AddBorder(lab, 0.79, 0.64, 0.36)

    local title = lab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("PetDex model lab")

    local close = CreateFrame("Button", nil, lab, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    for row, kind in ipairs({ "model", "scene" }) do
        local top = -36 - (row - 1) * ROW_HEIGHT
        local heading = lab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("TOPLEFT", GAP, top)
        heading:SetText(kind == "model" and "PlayerModel" or "ModelScene + actor")
        for i, state in ipairs(STATES) do
            CreateStage(kind, state, GAP + (i - 1) * (STAGE_SIZE + GAP), top - 16)
        end
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
    AddButton("Turn left", 78, function() facing = facing - math.pi / 8; ApplyFacing() end)
    AddButton("Turn right", 82, function() facing = facing + math.pi / 8; ApplyFacing() end)
    AddButton("Spin", 56, function() spinning = not spinning end)
    AddButton("Zoom in", 72, function() zoom = math.max(0.4, zoom - 0.15); ApplyZoom() end)
    AddButton("Zoom out", 76, function() zoom = math.min(3, zoom + 0.15); ApplyZoom() end)
    AddButton("Animation", 82, NextAnimation)
    AddButton("Grid x" .. GRID_COUNT, 74, ToggleGrid)
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
