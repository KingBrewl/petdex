-- Collection model.
--
-- Facts are recorded per NPC (the game identifies units by NPC ID): what the
-- player has seen and tamed, plus beasts learned in game that the shipped data
-- doesn't cover. Dex entries are LOOKS, and a look's status is derived from
-- the NPCs that wear it, so correcting the NPC -> look data fixes everyone's
-- dex without touching saved variables.
local _, ns = ...

local RARITY_RANK = { common = 1, rare = 2, unique = 3 }

---------------------------------------------------------------------------
-- Look index, built once from shipped data
---------------------------------------------------------------------------
local lookNPCs = {} -- [lookID] = { npcID, ... }, most widespread first

for npcID, beast in pairs(ns.Beasts) do
    for _, lookID in ipairs(beast.looks or {}) do
        lookNPCs[lookID] = lookNPCs[lookID] or {}
        table.insert(lookNPCs[lookID], npcID)
    end
end

-- A look is named after, and shown through, the NPC wearing it that has the
-- most spawn points (the one hunters know it by), ties by lowest ID.
for lookID, npcs in pairs(lookNPCs) do
    table.sort(npcs, function(a, b)
        local spawnsA, spawnsB = ns.Beasts[a].spawns or 0, ns.Beasts[b].spawns or 0
        if spawnsA ~= spawnsB then return spawnsA > spawnsB end
        return a < b
    end)
    if not ns.Looks[lookID] then
        local beast = ns.Beasts[npcs[1]]
        local look = { label = beast.name, family = beast.family, model = beast.model }
        for _, npcID in ipairs(npcs) do
            if ns.Beasts[npcID].spirit then look.spirit = true end
        end
        ns.Looks[lookID] = look
    end
end

-- A look is only as rare as the most common NPC that wears it.
for lookID, look in pairs(ns.Looks) do
    if not look.rarity then
        local rarity
        for _, npcID in ipairs(lookNPCs[lookID] or {}) do
            local npcRarity = ns.Beasts[npcID].rarity or "common"
            if not rarity or RARITY_RANK[npcRarity] < RARITY_RANK[rarity] then
                rarity = npcRarity
            end
        end
        look.rarity = rarity or "common"
    end
end

-- NPCs we have no look data for (discovered in game, or shipped without
-- looks) stand in as their own look, "npc:<id>", until the data covers them.
local function StandInNPC(lookID)
    return type(lookID) == "string" and tonumber(lookID:match("^npc:(%d+)$"))
end

---------------------------------------------------------------------------
-- NPCs
---------------------------------------------------------------------------
function ns:GetBeast(npcID)
    return ns.Beasts[npcID] or self.db.discovered[npcID]
end

function ns:GetRecord(npcID, create)
    local record = self.db.beasts[npcID]
    if not record and create then
        record = {}
        self.db.beasts[npcID] = record
    end
    return record
end

-- NPC-level "tamed", "seen" or nil: has this NPC been tamed or seen at all.
function ns:GetStatus(npcID)
    local record = self.db.beasts[npcID]
    if not record then return nil end
    if record.tamed then return "tamed" end
    if record.seen then return "seen" end
end

-- Zone name for a beast: given in data, learned in game (discovered beasts),
-- or worked out from its spawn point (map, x, y in world coordinates).
local zoneCache = {}
local function ZoneFromSpawn(map, x, y)
    local name
    if C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok, uiMapID, mapPos = pcall(C_Map.GetMapPosFromWorldPos, map, CreateVector2D(x, y))
        if ok and uiMapID then
            -- If that's a continent, look for the zone at the point.
            if mapPos and C_Map.GetMapInfoAtPosition then
                local okAt, child = pcall(C_Map.GetMapInfoAtPosition, uiMapID, mapPos.x, mapPos.y)
                if okAt and child and child.name then
                    name = child.name
                end
            end
            if not name then
                local info = C_Map.GetMapInfo(uiMapID)
                name = info and info.name
            end
        end
    end
    -- Dungeons and raids: the instance's name.
    if not name and map ~= 0 and map ~= 1 and GetRealZoneText then
        local ok, text = pcall(GetRealZoneText, map)
        if ok and text and text ~= "" then
            name = text
        end
    end
    return name
end

function ns:GetBeastZone(beast)
    if not beast then return end
    if beast.zone then return beast.zone end
    for zone in pairs(beast.zones or {}) do
        return zone
    end
    if not beast.map then return end
    local key = beast.map .. ":" .. beast.x .. ":" .. beast.y
    if zoneCache[key] == nil then
        zoneCache[key] = ZoneFromSpawn(beast.map, beast.x, beast.y) or false
    end
    return zoneCache[key] or nil
end

-- Spawn rarity of the NPC (rare spawns are worth announcing even when their
-- look is common).
function ns:IsRare(npcID)
    local beast = self:GetBeast(npcID)
    return beast ~= nil and (beast.rarity == "rare" or beast.rarity == "unique")
end

---------------------------------------------------------------------------
-- Looks
---------------------------------------------------------------------------
function ns:GetLooks(npcID)
    local beast = ns.Beasts[npcID]
    if beast and beast.looks and #beast.looks > 0 then
        return beast.looks
    end
    return { "npc:" .. npcID }
end

function ns:GetLookNPCs(lookID)
    local npcID = StandInNPC(lookID)
    if npcID then
        return { npcID }
    end
    return lookNPCs[lookID] or {}
end

-- { label, family, model, spirit, rarity, standIn } or nil
function ns:GetLook(lookID)
    local npcID = StandInNPC(lookID)
    if not npcID then
        return ns.Looks[lookID]
    end
    local beast = self:GetBeast(npcID)
    if beast then
        return { label = beast.name, family = beast.family, model = beast.model, spirit = beast.spirit,
            rarity = beast.rarity or "common", standIn = true }
    end
end

-- Does this NPC record show this look? An NPC with a single look always shows
-- it; for NPCs with several, only looks confirmed in record.looks count.
local function RecordLookStatus(npcID, record, lookID)
    if record.looks and record.looks[lookID] then
        return record.looks[lookID]
    end
    if #ns:GetLooks(npcID) == 1 then
        if record.tamed then return "tamed" end
        if record.seen then return "seen" end
    end
end

-- "tamed", "seen" or nil
function ns:GetLookStatus(lookID)
    local status
    for _, npcID in ipairs(self:GetLookNPCs(lookID)) do
        local record = self.db.beasts[npcID]
        local npcStatus = record and RecordLookStatus(npcID, record, lookID)
        if npcStatus == "tamed" then
            return "tamed"
        end
        status = status or npcStatus
    end
    return status
end

-- Calls fn(lookID, look) for every look in the collection: shipped looks,
-- shipped NPCs without look data, and discovered beasts proven tameable.
-- Returns the number of discovered beasts still waiting to be verified.
function ns:ForEachLook(fn)
    for lookID, look in pairs(ns.Looks) do
        fn(lookID, look)
    end
    for npcID, beast in pairs(ns.Beasts) do
        if not beast.looks or #beast.looks == 0 then
            local lookID = "npc:" .. npcID
            fn(lookID, self:GetLook(lookID))
        end
    end
    local unverified = 0
    for npcID, beast in pairs(self.db.discovered) do
        if beast.verified then
            local lookID = "npc:" .. npcID
            fn(lookID, self:GetLook(lookID))
        else
            unverified = unverified + 1
        end
    end
    return unverified
end

---------------------------------------------------------------------------
-- Dex view: families -> model groups -> looks
---------------------------------------------------------------------------
local RARITY_ORDER = { unique = 1, rare = 2, common = 3 }

-- Everything the dex shows about one look. npcID is a representative NPC
-- (used to load the model when there's no display ID, and for zone/level).
function ns:GetLookInfo(lookID)
    local look = self:GetLook(lookID)
    if not look then return end
    local npcID = self:GetLookNPCs(lookID)[1]
    local beast = npcID and self:GetBeast(npcID)
    return {
        lookID = lookID,
        label = look.label,
        family = look.family or "Unknown",
        -- Until model groups come from the game, a family is one group.
        model = look.model or (beast and beast.model) or look.family or "Unknown",
        rarity = look.rarity or "common",
        spirit = look.spirit,
        displayID = look.displayID or (type(lookID) == "number" and lookID or nil),
        npcID = npcID,
        beast = beast,
        record = npcID and self.db.beasts[npcID],
        status = self:GetLookStatus(lookID),
    }
end

local function CountInto(group, info)
    group.total = group.total + 1
    if info.status == "tamed" then group.tamed = group.tamed + 1 end
end

-- Sorted list of families: { name, total, tamed, models = { { name, total,
-- tamed, looks = { lookInfo, ... } }, ... } }. Looks sort rarest first.
function ns:GetDexFamilies()
    local byName = {}
    self:ForEachLook(function(lookID)
        local info = self:GetLookInfo(lookID)
        if not info then return end
        local family = byName[info.family]
        if not family then
            family = { name = info.family, total = 0, tamed = 0, models = {}, byModel = {} }
            byName[info.family] = family
        end
        local group = family.byModel[info.model]
        if not group then
            group = { name = info.model, total = 0, tamed = 0, looks = {} }
            family.byModel[info.model] = group
            table.insert(family.models, group)
        end
        table.insert(group.looks, info)
        CountInto(group, info)
        CountInto(family, info)
    end)

    local families = {}
    for _, family in pairs(byName) do
        family.byModel = nil
        table.sort(family.models, function(a, b) return a.name < b.name end)
        for _, group in ipairs(family.models) do
            table.sort(group.looks, function(a, b)
                local ra, rb = RARITY_ORDER[a.rarity] or 9, RARITY_ORDER[b.rarity] or 9
                if ra ~= rb then return ra < rb end
                return a.label < b.label
            end)
        end
        table.insert(families, family)
    end
    table.sort(families, function(a, b) return a.name < b.name end)
    return families
end

-- The dex window sets this to refresh itself when the collection changes.
local function NotifyChanged()
    if ns.OnCollectionChanged then
        ns:OnCollectionChanged()
    end
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

-- Record or update a beast that isn't in Data/Beasts.lua.
-- info: { name, family, level, zone, classification, tamed }
function ns:Discover(npcID, info)
    if ns.Beasts[npcID] then return end
    local beast = self.db.discovered[npcID]
    if not beast then
        beast = { name = info.name, family = info.family, zones = {}, rarity = "common" }
        self.db.discovered[npcID] = beast
        self:Debug("discovered beast not in data:", info.name, npcID)
    end
    beast.family = beast.family or info.family
    if info.level and info.level > 0 then
        beast.minLevel = math.min(beast.minLevel or info.level, info.level)
        beast.maxLevel = math.max(beast.maxLevel or info.level, info.level)
    end
    if info.zone and info.zone ~= "" then
        beast.zones[info.zone] = true
    end
    if info.classification == "rare" or info.classification == "rareelite" then
        beast.rarity = "rare"
    end
    -- A beast with a pet family isn't necessarily tameable; a real tame proves it.
    if info.tamed then
        beast.verified = true
    end
end

-- Remember exactly which look was seen or tamed, when we know it
-- (info.lookID). Never downgrades a tamed look to seen.
local function ConfirmLook(record, lookID, status)
    if not lookID then return end
    record.looks = record.looks or {}
    if record.looks[lookID] ~= "tamed" then
        record.looks[lookID] = status
    end
end

function ns:MarkSeen(npcID, info)
    self:Discover(npcID, info)
    local record = self:GetRecord(npcID, true)
    local now = time()
    local firstSighting = not record.seen
    if firstSighting then
        record.seen = now
        if self:IsRare(npcID) and self.db.settings.announce then
            self:Print("First sighting of a rare:", "|cff0070dd" .. info.name .. "|r")
        end
    end
    record.lastSeen = now
    record.lastZone = info.zone
    ConfirmLook(record, info.lookID, "seen")
    if firstSighting then
        NotifyChanged()
    end
end

local function TamedLooks(npcID)
    local tamed = {}
    for _, lookID in ipairs(ns:GetLooks(npcID)) do
        if ns:GetLookStatus(lookID) == "tamed" then
            tamed[lookID] = true
        end
    end
    return tamed
end

-- source: "tame" (watched it happen), "pet" or "stable" (matched an existing pet)
-- info.lookID: the exact look, if known.
-- Returns true if this added a new look to the collection.
function ns:MarkTamed(npcID, info, source)
    info.tamed = true
    self:Discover(npcID, info)
    local before = TamedLooks(npcID)
    local record = self:GetRecord(npcID, true)
    local now = time()
    record.seen = record.seen or now
    record.tamed = record.tamed or now
    record.firstTamedBy = record.firstTamedBy or ns.charKey
    record.source = record.source or source
    if source == "tame" then
        record.tameCount = (record.tameCount or 0) + 1
    end
    ConfirmLook(record, info.lookID, "tamed")

    local isNew = false
    for lookID in pairs(TamedLooks(npcID)) do
        if not before[lookID] then
            isNew = true
        end
    end
    if isNew and self.db.settings.announce then
        local stats = self:GetStats()
        self:Print(("Added %s to your collection! (%d/%d looks)"):format(info.name, stats.tamed, stats.total))
    end
    if isNew then
        NotifyChanged()
    end
    return isNew
end

-- Find a beast by name (and family, if given). Returns an npcID only when
-- exactly one beast matches, so renamed or ambiguous pets stay unmatched.
function ns:MatchByName(name, family)
    if not name then return end
    local found, count = nil, 0
    local function check(npcID, beast)
        if beast.name == name and (not family or not beast.family or beast.family == family) then
            found, count = npcID, count + 1
        end
    end
    for npcID, beast in pairs(ns.Beasts) do check(npcID, beast) end
    for npcID, beast in pairs(self.db.discovered) do check(npcID, beast) end
    if count == 1 then
        return found
    end
end

---------------------------------------------------------------------------
-- Stats, counted in looks
---------------------------------------------------------------------------
function ns:GetStats()
    local stats = { total = 0, seen = 0, tamed = 0, rares = 0, raresTamed = 0 }
    stats.unverified = self:ForEachLook(function(lookID, look)
        local status = self:GetLookStatus(lookID)
        stats.total = stats.total + 1
        if status then stats.seen = stats.seen + 1 end
        if status == "tamed" then stats.tamed = stats.tamed + 1 end
        if look and (look.rarity == "rare" or look.rarity == "unique") then
            stats.rares = stats.rares + 1
            if status == "tamed" then stats.raresTamed = stats.raresTamed + 1 end
        end
    end)
    return stats
end
