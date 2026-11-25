-- Beast stage: one beast's 3D model on a lit stage, drawn in its dex state.
--
-- Everything here was proven on Forever in the model lab (ModelLab.lua and
-- its git history):
-- - PlayerModel, loaded by display ID when known, else by NPC ID
--   (SetCreature), which also tells us the display ID afterwards.
-- - The model's own camera frames inconsistently by model and load path, so
--   the stage takes it over: UseModelCenterToTransform(true), then a custom
--   camera on +X, at a distance proportional to the model's size.
-- - PlayerModel can't report a size, so a hidden ModelScene actor measures
--   the bounding box, once per display ID; sizes are cached in saved vars.
-- - States: tamed (spotlight, rarity glow), seen (full colour on a dimmer
--   stage), unknown (all light at zero: a black silhouette). Glowing spirit models ignore light, so an
--   unknown spirit beast is drawn as a faint grey ghost instead.
local _, ns = ...

local FIT = 1.1 -- camera distance per yard of model size (lab: 1.5 was ~60% too far)
local DEFAULT_SIZE = 3
local DEFAULT_FACING = math.rad(-60) -- 0 faces the camera; this is a three-quarter view
local POLL = 0.1
local LOAD_TIMEOUT = 3
local LIGHT = { ambient = 0.35, diffuse = 0.55 } -- "soft", picked in game
local GHOST_ALPHA = 0.3

local WARM = { 1, 0.89, 0.69 }
local GOLD = { 0.79, 0.64, 0.36 }
local GREY = { 0.6, 0.6, 0.6 }
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

ns.RARITY_COLORS = {
    common = { 0.85, 0.85, 0.85 },
    rare = { 0.42, 0.66, 1 },
    unique = { 0.77, 0.61, 1 },
}

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------
-- Newer clients take colour objects, older ones SetGradientAlpha.
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

-- A soft ellipse: stacked circle-masked textures with low alpha each.
-- Returns the textures so they can be recoloured and shown or hidden.
local function CreateGlow(frame, steps, width, height, y)
    local glow = {}
    for i = 1, steps do
        local scale = 1 - (i - 1) * (0.85 / steps)
        local texture = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        texture:SetSize(width * scale, height * scale)
        texture:SetPoint("CENTER", frame, "BOTTOM", 0, y)
        if frame.CreateMaskTexture then
            local mask = frame:CreateMaskTexture()
            mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(texture)
            texture:AddMaskTexture(mask)
        end
        glow[i] = texture
    end
    return glow
end

local function ShowGlow(glow, color, alpha)
    for _, texture in ipairs(glow) do
        if color then
            texture:SetColorTexture(color[1], color[2], color[3], alpha * 2.2 / #glow)
            texture:Show()
        else
            texture:Hide()
        end
    end
end

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

---------------------------------------------------------------------------
-- Measuring: a hidden ModelScene actor reads each model's bounding box.
-- One model at a time, queued; results cached per display ID.
---------------------------------------------------------------------------
local measureActor
local queue, pending, measuring = {}, {}, false

local function EnsureMeasurer()
    if measureActor ~= nil then return end
    measureActor = false
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, UIParent)
    if not ok then return end
    -- Models only load while shown, so keep it on screen but invisible.
    scene:SetSize(32, 32)
    scene:SetPoint("BOTTOMLEFT")
    scene:SetAlpha(0)
    scene:SetFrameStrata("BACKGROUND")
    local okActor, actor = pcall(scene.CreateActor, scene)
    if okActor and actor then
        measureActor = actor
    end
end

-- Bounding box as six numbers (Forever) or two vectors (newer clients).
local function ReadSize(actor)
    local ok, a, b, c, d, e, f = pcall(actor.GetActiveBoundingBox, actor)
    if not ok then return end
    if type(a) == "table" and type(b) == "table" then
        a, b, c, d, e, f = a.x, a.y, a.z, b.x, b.y, b.z
    end
    if type(a) ~= "number" or type(f) ~= "number" then return end
    local size = math.max(d - a, e - b, f - c)
    if size > 0 then return size end
end

-- The new model has loaded once the actor reports a model file again
-- (ClearModel drops it), so a stale box from the previous model isn't read.
local function HasModel(actor)
    if type(actor.GetModelFileID) ~= "function" then return true end
    local ok, fileID = pcall(actor.GetModelFileID, actor)
    return ok and type(fileID) == "number" and fileID > 0
end

local ProcessQueue

local function FinishJob(job, size)
    if size then
        ns.db.modelCache.sizes[job.displayID] = size
    end
    pending[job.displayID] = nil
    measuring = false
    for _, callback in ipairs(job.callbacks) do
        callback(size)
    end
    ProcessQueue()
end

ProcessQueue = function()
    if measuring or #queue == 0 then return end
    local job = table.remove(queue, 1)
    if not measureActor then
        FinishJob(job, nil)
        return
    end
    measuring = true
    pcall(measureActor.ClearModel, measureActor)
    pcall(measureActor.SetModelByCreatureDisplayID, measureActor, job.displayID)
    local waited = 0
    local function Poll()
        local size = HasModel(measureActor) and ReadSize(measureActor)
        if size then
            FinishJob(job, size)
            return
        end
        waited = waited + POLL
        if waited >= LOAD_TIMEOUT then
            FinishJob(job, nil)
            return
        end
        C_Timer.After(POLL, Poll)
    end
    C_Timer.After(POLL, Poll)
end

-- callback(size or nil), possibly right away when cached.
function ns.MeasureModel(displayID, callback)
    local cached = ns.db.modelCache.sizes[displayID]
    if cached then
        callback(cached)
        return
    end
    local job = pending[displayID]
    if job then
        table.insert(job.callbacks, callback)
        return
    end
    job = { displayID = displayID, callbacks = { callback } }
    pending[displayID] = job
    table.insert(queue, job)
    EnsureMeasurer()
    ProcessQueue()
end

local function ReadDisplayID(model)
    local ok, value = pcall(model.GetDisplayInfo, model)
    if ok and not ns.IsSecret(value) and type(value) == "number" and value > 0 then
        return value
    end
end

---------------------------------------------------------------------------
-- Stage
---------------------------------------------------------------------------
local Stage = {}
Stage.__index = Stage

-- A stage width x height inside parent. Position it with stage.frame.
function ns.CreateBeastStage(parent, width, height)
    local self = setmetatable({ facing = DEFAULT_FACING, zoom = 1 }, Stage)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)
    self.frame = frame

    self.backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    self.backdrop:SetAllPoints()

    -- Spotlight: nested beams of falling width soften the edges.
    self.beams = {}
    for i, widthScale in ipairs({ 0.65, 0.5, 0.36 }) do
        local beam = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        beam:SetPoint("TOP")
        beam:SetSize(width * widthScale, height * (0.75 + i * 0.05))
        self.beams[i] = beam
    end

    -- More, fainter layers blend into a smoother glow; big stages need more.
    local steps = width >= 200 and 24 or 12
    self.floorGlow = CreateGlow(frame, steps, width * 0.8, math.max(16, height * 0.16), height * 0.22)
    self.backGlow = CreateGlow(frame, steps, width * 0.85, height * 0.7, height * 0.5)

    local model = CreateFrame("PlayerModel", nil, frame)
    model:SetAllPoints()
    model:SetAlpha(0)
    -- Loading can reset the camera and light; fit again once it's in.
    pcall(model.SetScript, model, "OnModelLoaded", function()
        if self.size then self:Fit() end
    end)
    self.model = model

    self.missing = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    self.missing:SetTextColor(0.5, 0.5, 0.5)
    self.missing:SetPoint("CENTER")
    self.missing:SetText("?")
    self.missing:Hide()
    return self
end

-- Backdrop, beam and glows for a state; rarity colours the tamed floor glow.
function Stage:Decorate(state, rarity)
    local beamAlpha
    if state == "unknown" then
        SetVerticalGradient(self.backdrop, { 0.11, 0.12, 0.15, 1 }, { 0.04, 0.045, 0.06, 1 })
        ShowGlow(self.floorGlow, nil)
        ShowGlow(self.backGlow, GOLD, 0.4)
    else
        SetVerticalGradient(self.backdrop, { 0.24, 0.14, 0.09, 1 }, { 0.05, 0.035, 0.03, 1 })
        if state == "tamed" then
            ShowGlow(self.floorGlow, ns.RARITY_COLORS[rarity] or ns.RARITY_COLORS.common, 0.6)
            beamAlpha = 0.11
        else
            ShowGlow(self.floorGlow, GREY, 0.3)
            beamAlpha = 0.04
        end
        ShowGlow(self.backGlow, nil)
    end
    for _, beam in ipairs(self.beams) do
        if beamAlpha then
            SetVerticalGradient(beam, { WARM[1], WARM[2], WARM[3], 0 }, { WARM[1], WARM[2], WARM[3], beamAlpha })
            beam:Show()
        else
            beam:Hide()
        end
    end
end

-- beast: { npcID, displayID, state = "tamed"|"seen"|"unknown", rarity, spirit }
-- Same look in the same state again does nothing, so refreshes are cheap.
function Stage:SetBeast(beast)
    local old = self.beast
    if old and beast and old.npcID == beast.npcID and old.displayID == beast.displayID
        and old.state == beast.state and old.rarity == beast.rarity then
        return
    end
    self.beast = beast
    self.size = nil
    self.token = (self.token or 0) + 1
    local token = self.token
    local model = self.model
    model:SetAlpha(0)
    pcall(model.ClearModel, model)
    self.missing:Hide()
    if not beast then return end
    self:Decorate(beast.state, beast.rarity)

    local displayID = beast.displayID or (beast.npcID and ns.db.modelCache.npcDisplay[beast.npcID])
    if displayID then
        pcall(model.SetDisplayInfo, model, displayID)
    elseif beast.npcID then
        pcall(model.SetCreature, model, beast.npcID)
    else
        self.missing:Show()
        return
    end

    local waited = 0
    local function Poll()
        if token ~= self.token then return end
        local id = displayID or ReadDisplayID(model)
        if id then
            if beast.npcID and not beast.displayID then
                ns.db.modelCache.npcDisplay[beast.npcID] = id
            end
            ns.MeasureModel(id, function(size)
                if token ~= self.token then return end
                self.size = size or DEFAULT_SIZE
                self:Fit()
            end)
            return
        end
        waited = waited + POLL
        if waited >= LOAD_TIMEOUT then
            -- SetCreature may need the creature in the client's cache.
            self.missing:Show()
            return
        end
        C_Timer.After(POLL, Poll)
    end
    Poll()
end

-- Camera, light and state for the loaded model.
function Stage:Fit()
    local model, beast = self.model, self.beast
    if not beast or not self.size then return end
    pcall(model.UseModelCenterToTransform, model, true)
    pcall(model.SetPosition, model, 0, 0, 0)
    pcall(model.MakeCurrentCameraCustom, model)
    pcall(model.SetCameraPosition, model, self.size * FIT * self.zoom, 0, 0)
    pcall(model.SetCameraTarget, model, 0, 0, 0)
    pcall(model.SetFacing, model, self.facing)
    if beast.state == "unknown" then
        SetModelLight(model, 0, 0)
        pcall(model.SetDesaturation, model, beast.spirit and 1 or 0)
        model:SetAlpha(beast.spirit and GHOST_ALPHA or 1)
    else
        SetModelLight(model, LIGHT.ambient, LIGHT.diffuse)
        -- Seen beasts are documented, so they show in full colour; taming adds
        -- the spotlight and rarity glow (see Decorate).
        pcall(model.SetDesaturation, model, 0)
        model:SetAlpha(1)
    end
end

function Stage:SetFacing(facing)
    self.facing = facing
    pcall(self.model.SetFacing, self.model, facing)
end

function Stage:SetZoom(zoom)
    self.zoom = math.max(0.4, math.min(3, zoom))
    self:Fit()
end

function Stage:PlayAnimation(animationID)
    pcall(self.model.SetAnimation, self.model, animationID)
end

-- Drag the model sideways to turn it.
function Stage:EnableTurning()
    local model = self.model
    local dragX
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function()
        dragX = GetCursorPosition()
        model:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then
                model:SetScript("OnUpdate", nil)
                return
            end
            local x = GetCursorPosition()
            self:SetFacing(self.facing + (x - dragX) * 0.01)
            dragX = x
        end)
    end)
    model:SetScript("OnMouseUp", function()
        model:SetScript("OnUpdate", nil)
    end)
    if model.EnableMouseWheel then
        model:EnableMouseWheel(true)
        model:SetScript("OnMouseWheel", function(_, delta)
            self:SetZoom(self.zoom - delta * 0.1)
        end)
    end
end
