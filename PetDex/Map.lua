-- Where a beast spawns on the map, and pinning it with the game's own map
-- pin (user waypoint, super-tracked so the hunter can follow it).
--
-- Shipped data has one spawn point per beast in world coordinates
-- (map, x, y); the client converts it to a zone map position.
local _, ns = ...

-- uiMapID and position (0-1) of a beast's spawn point, on the most detailed
-- map at that point (the zone, not the continent). Nil if unknown.
function ns:GetSpawnMapPosition(beast)
    if not beast or not beast.map or not beast.x then return end
    if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
    local world = CreateVector2D(beast.x, beast.y)
    local ok, uiMapID, pos = pcall(C_Map.GetMapPosFromWorldPos, beast.map, world)
    if not ok or not uiMapID or not pos then return end
    if C_Map.GetMapInfoAtPosition then
        local okAt, child = pcall(C_Map.GetMapInfoAtPosition, uiMapID, pos.x, pos.y)
        if okAt and child and child.mapID and child.mapID ~= uiMapID then
            local okChild, childMapID, childPos = pcall(C_Map.GetMapPosFromWorldPos, beast.map, world, child.mapID)
            if okChild and childMapID and childPos then
                return childMapID, childPos
            end
        end
    end
    return uiMapID, pos
end

local function MapName(uiMapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMapID)
    return info and info.name
end

-- Zone name from a spawn point, or the instance's name for dungeons/raids.
function ns:ZoneFromSpawn(beast)
    local uiMapID = self:GetSpawnMapPosition(beast)
    local name = uiMapID and MapName(uiMapID)
    if not name and beast.map and beast.map ~= 0 and beast.map ~= 1 and GetRealZoneText then
        local ok, text = pcall(GetRealZoneText, beast.map)
        if ok and text and text ~= "" then
            name = text
        end
    end
    return name
end

local function SetGamePin(uiMapID, pos)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
    if C_Map.CanSetUserWaypointOnMap then
        local ok, allowed = pcall(C_Map.CanSetUserWaypointOnMap, uiMapID)
        if ok and not allowed then return false end
    end
    local point = UiMapPoint.CreateFromCoordinates(uiMapID, pos.x, pos.y)
    if not pcall(C_Map.SetUserWaypoint, point) then return false end
    -- Track it, so the pin shows on the minimap and screen edge to follow.
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return true
end

-- Pin a look's spawn point on the map. Returns true when a pin was placed.
function ns:PinLook(info)
    local beast = info and info.beast
    local name = info and info.status and info.label or "the undocumented beast"
    if not beast or beast.spawns == 0 then
        self:Print(("%s has no fixed spawn point to pin."):format(name))
        return false
    end
    local uiMapID, pos = self:GetSpawnMapPosition(beast)
    if not uiMapID then
        local zone = self:GetBeastZone(beast)
        self:Print(("Can't pin %s on the map%s."):format(name, zone and (" (it's in " .. zone .. ")") or ""))
        return false
    end
    local zone = MapName(uiMapID) or "?"
    local coords = ("%.1f, %.1f"):format(pos.x * 100, pos.y * 100)
    local more = (beast.spawns or 0) > 1 and (" (1 of %d spawn points)"):format(beast.spawns) or ""

    if SetGamePin(uiMapID, pos) then
        ns.Skin.PlaySound("pin")
        self:Print(("Pinned %s on your map: %s %s%s."):format(name, zone, coords, more))
        return true
    end
    if TomTom and TomTom.AddWaypoint then
        local ok = pcall(TomTom.AddWaypoint, TomTom, uiMapID, pos.x, pos.y, { title = "PetDex: " .. name })
        if ok then
            self:Print(("Added a TomTom waypoint for %s: %s %s%s."):format(name, zone, coords, more))
            return true
        end
    end
    self:Print(("%s: %s %s%s. (Map pins aren't available here.)"):format(name, zone, coords, more))
    return false
end
