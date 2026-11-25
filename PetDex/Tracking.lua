-- Tracking: sightings (target / mouseover), tames, and backfilling pets the
-- hunter already owns (active pet and stable).
local _, ns = ...

local TAME_BEAST_SPELL_ID = 1515
local TAME_WINDOW = 30 -- seconds from cast start for the new pet to appear
local tameSpellName
local pendingTame

local function GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
end

-- Match by ID, and fall back to the spell name in case Forever renumbered it.
local function IsTameSpell(spellID)
    if spellID == TAME_BEAST_SPELL_ID then return true end
    return tameSpellName ~= nil and GetSpellName(spellID) == tameSpellName
end

-- Calls a unit API safely. Returns true/false, or nil when the answer is
-- unknown (API missing, error, or a secret value).
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or ns.IsSecret(value) then return nil end
    return value and true or false
end

-- A wild beast: not a player, not anyone's pet, and something you could
-- attack. On Forever other hunters' pets don't report as player controlled
-- and carry Creature GUIDs, so one check isn't enough. An unknown answer
-- counts against the unit: missing a sighting beats a false one.
local function IsWild(unit)
    if Ask(UnitIsPlayer, unit) ~= false then return false end
    if Ask(UnitPlayerControlled, unit) == true then return false end
    if Ask(UnitIsOtherPlayersPet, unit) == true then return false end
    if Ask(UnitIsUnit, unit, "pet") == true then return false end
    if Ask(UnitIsFriend, "player", unit) == true then return false end
    if UnitCanAttack and Ask(UnitCanAttack, "player", unit) ~= true then return false end
    return true
end

-- Returns the NPC ID if the unit is a wild beast worth tracking.
local function GetBeastNPCID(unit)
    if not UnitExists(unit) or not IsWild(unit) then return end
    local npcID = ns.NPCIDFromGUID(UnitGUID(unit))
    if not npcID then return end
    if ns.Beasts[npcID] or UnitCreatureFamily(unit) then
        return npcID
    end
end

-- The beast's attack speed as the game reports it, rounded to 0.01s. Only
-- out of combat: slows and haste effects in combat would skew it.
local function ObservedSpeed(unit)
    if Ask(UnitAffectingCombat, unit) ~= false then return end
    if type(UnitAttackSpeed) ~= "function" then return end
    local ok, speed = pcall(UnitAttackSpeed, unit)
    if ok and not ns.IsSecret(speed) and type(speed) == "number" and speed > 0 then
        return math.floor(speed * 100 + 0.5) / 100
    end
end

local function DescribeUnit(unit)
    local zone, mapID = ns.GetLocation()
    return {
        speed = ObservedSpeed(unit),
        name = UnitName(unit),
        level = UnitLevel(unit),
        family = UnitCreatureFamily(unit),
        classification = UnitClassification(unit),
        zone = zone,
        mapID = mapID,
    }
end

---------------------------------------------------------------------------
-- Sightings
---------------------------------------------------------------------------
local function ObserveUnit(unit)
    local npcID = GetBeastNPCID(unit)
    if npcID then
        ns:MarkSeen(npcID, DescribeUnit(unit))
    end
end

-- Documenting a beast takes targeting it. Mousing over one only counts with
-- /petdex mouseover, since hovering is too easy to do by accident.
ns:On("PLAYER_TARGET_CHANGED", function() ObserveUnit("target") end)
ns:On("UPDATE_MOUSEOVER_UNIT", function()
    if ns.db.settings.mouseover then
        ObserveUnit("mouseover")
    end
end)

---------------------------------------------------------------------------
-- Owned pets
---------------------------------------------------------------------------
local function LinkCurrentPet(npcID)
    local guid = UnitGUID("pet")
    if guid then
        ns.GetCharData().pets[guid] = npcID
    end
end

-- Work out which beast the active pet came from, for pets tamed before
-- PetDex was installed.
local function IdentifyCurrentPet()
    if ns.playerClass ~= "HUNTER" or not UnitExists("pet") then return end
    local guid = UnitGUID("pet")
    local pets = ns.GetCharData().pets
    if not guid or pets[guid] then return end

    -- A pet GUID may carry the original creature ID. Only trust it if it
    -- points at a beast we know; otherwise try the pet's name.
    local _, idFromGUID = ns.ParseGUID(guid)
    local npcID
    if idFromGUID and ns:GetBeast(idFromGUID) then
        npcID = idFromGUID
    else
        npcID = ns:MatchByName(UnitName("pet"), UnitCreatureFamily("pet"))
    end
    if not npcID then
        ns:Debug("could not identify current pet", UnitName("pet"), guid)
        return
    end

    pets[guid] = npcID
    if ns:GetStatus(npcID) ~= "tamed" then
        local beast = ns:GetBeast(npcID)
        ns:MarkTamed(npcID, { name = beast.name, family = beast.family }, "pet")
    end
end

---------------------------------------------------------------------------
-- Taming: capture the target when Tame Beast starts (it's the only moment we
-- can see the wild creature's GUID), then confirm when the new pet appears.
---------------------------------------------------------------------------
local function OnCastStart(_, unit, _, spellID)
    if unit ~= "player" or not IsTameSpell(spellID) then return end
    local npcID = GetBeastNPCID("target")
    if not npcID then
        ns:Debug("Tame Beast started on a target we can't identify")
        return
    end
    pendingTame = { npcID = npcID, info = DescribeUnit("target"), startedAt = GetTime() }
    ns:Debug("taming", pendingTame.info.name, npcID)
end

local function CheckPendingTame()
    if not pendingTame then return end
    if GetTime() - pendingTame.startedAt > TAME_WINDOW then
        pendingTame = nil
        return
    end
    -- A freshly tamed pet keeps the creature's name until it's renamed.
    if not UnitExists("pet") or UnitName("pet") ~= pendingTame.info.name then return end

    local tame = pendingTame
    pendingTame = nil
    ns:MarkTamed(tame.npcID, tame.info, "tame")
    LinkCurrentPet(tame.npcID)
end

ns:On("UNIT_SPELLCAST_START", OnCastStart)
ns:On("UNIT_SPELLCAST_CHANNEL_START", OnCastStart)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit)
    if unit == "player" then CheckPendingTame() end
end)
ns:On("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit)
    if unit == "player" then CheckPendingTame() end
end)
ns:On("UNIT_PET", function(_, unit)
    if unit ~= "player" then return end
    CheckPendingTame()
    IdentifyCurrentPet()
end)

---------------------------------------------------------------------------
-- Stable: no GUIDs here, so match stabled pets by name and family. Pets
-- that don't match (renamed, ambiguous) are kept so the UI can let the
-- player assign them later.
---------------------------------------------------------------------------
local function ScanStable()
    if ns.playerClass ~= "HUNTER" or not GetStablePetInfo then return end
    local char = ns.GetCharData()
    wipe(char.unidentified)
    local slots = GetNumStableSlots and GetNumStableSlots() or 0
    for slot = 0, slots do -- slot 0 is the active pet
        local icon, name, level, family = GetStablePetInfo(slot)
        if name then
            local npcID = ns:MatchByName(name, family)
            if npcID then
                if ns:GetStatus(npcID) ~= "tamed" then
                    local beast = ns:GetBeast(npcID)
                    ns:MarkTamed(npcID, { name = beast.name, family = beast.family }, "stable")
                end
            else
                table.insert(char.unidentified, { name = name, level = level, family = family, icon = icon })
            end
        end
    end
    ns:Debug("stable scanned,", #char.unidentified, "unidentified")
end

ns:On("PET_STABLE_SHOW", ScanStable)
ns:On("PET_STABLE_UPDATE", ScanStable)

---------------------------------------------------------------------------
ns:On("PLAYER_LOGIN", function()
    tameSpellName = GetSpellName(TAME_BEAST_SPELL_ID)
    if not tameSpellName then
        ns:Debug("Tame Beast spell", TAME_BEAST_SPELL_ID, "not found on this client")
    end
end)
ns:On("PLAYER_ENTERING_WORLD", IdentifyCurrentPet)
