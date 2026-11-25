-- Points, hunter ranks and achievements.
--
-- Documenting a beast (first seeing a look) earns a little, taming it earns
-- a lot more, and rarer looks are worth more. Achievements add their own
-- points. Points are worked out from the collection each time; only the
-- dates achievements were earned are saved (ns.db.achievements).
local _, ns = ...

ns.POINTS = {
    seen = { common = 1, rare = 5, unique = 10 },
    tamed = { common = 5, rare = 25, unique = 50 }, -- on top of documenting it
}

-- 40 ranks; a new title every five.
local MAX_RANK = 40
local RANK_TITLES = {
    [1] = "Novice", [5] = "Tracker", [10] = "Stalker", [15] = "Pathfinder", [20] = "Beastcaller",
    [25] = "Packleader", [30] = "Beastmaster", [35] = "Wildlord", [40] = "Grand Huntsman",
}
ns.RANK_TITLES = RANK_TITLES
ns.MAX_RANK = MAX_RANK

-- Points needed for a rank: rank 2 at 10, rank 10 at ~340, rank 20 at
-- ~1,100, rank 40 at ~3,500 (taming nearly everything).
function ns.RankThreshold(rank)
    if rank <= 1 then return 0 end
    return math.floor(10 * (rank - 1) ^ 1.6)
end

function ns.RankTitle(rank)
    for r = rank, 1, -1 do
        if RANK_TITLES[r] then return RANK_TITLES[r] end
    end
    return RANK_TITLES[1]
end

function ns.RankForPoints(points)
    local rank = 1
    while rank < MAX_RANK and points >= ns.RankThreshold(rank + 1) do
        rank = rank + 1
    end
    return rank
end

---------------------------------------------------------------------------
-- Collection stats used by points and achievements
---------------------------------------------------------------------------
local function CollectStats()
    local stats = {
        total = 0, seen = 0, tamed = 0,
        byRarity = {}, -- [rarity] = { total, seen, tamed }
        families = {}, -- [name] = { total, seen, tamed }
        lookPoints = 0, seenPoints = 0, tamePoints = 0,
    }
    for _, family in ipairs(ns:GetDexFamilies()) do
        stats.families[family.name] = { total = family.total, seen = family.seen, tamed = family.tamed }
        for _, group in ipairs(family.models) do
            for _, info in ipairs(group.looks) do
                local rarity = info.rarity or "common"
                local counts = stats.byRarity[rarity] or { total = 0, seen = 0, tamed = 0 }
                stats.byRarity[rarity] = counts
                stats.total, counts.total = stats.total + 1, counts.total + 1
                if info.status then
                    stats.seen, counts.seen = stats.seen + 1, counts.seen + 1
                    stats.seenPoints = stats.seenPoints + (ns.POINTS.seen[rarity] or 1)
                end
                if info.status == "tamed" then
                    stats.tamed, counts.tamed = stats.tamed + 1, counts.tamed + 1
                    stats.tamePoints = stats.tamePoints + (ns.POINTS.tamed[rarity] or 5)
                end
            end
        end
    end
    stats.lookPoints = stats.seenPoints + stats.tamePoints
    return stats
end

local function Rarity(stats, rarity, field)
    local counts = stats.byRarity[rarity]
    return counts and counts[field] or 0, counts and counts.total or 0
end

---------------------------------------------------------------------------
-- Achievements: id, name, description, points, progress(stats) -> current,
-- target. Earned when current >= target (and target > 0).
---------------------------------------------------------------------------
local ACHIEVEMENTS = {
    { id = "doc1", name = "First Entry", desc = "Document a beast", points = 5,
      progress = function(s) return s.seen, 1 end },
    { id = "doc25", name = "Field Notes", desc = "Document 25 beasts", points = 10,
      progress = function(s) return s.seen, 25 end },
    { id = "doc100", name = "Naturalist", desc = "Document 100 beasts", points = 25,
      progress = function(s) return s.seen, 100 end },
    { id = "doc250", name = "Beast Scholar", desc = "Document 250 beasts", points = 50,
      progress = function(s) return s.seen, 250 end },
    { id = "docAll", name = "The Complete PetDex", desc = "Document every beast", points = 100,
      progress = function(s) return s.seen, s.total end },
    { id = "rare1", name = "Rare Sighting", desc = "Document a rare beast", points = 10,
      progress = function(s) return math.min(1, (Rarity(s, "rare", "seen"))), 1 end },
    { id = "rare10", name = "Rare Hunter", desc = "Document 10 rare beasts", points = 25,
      progress = function(s) return (Rarity(s, "rare", "seen")), 10 end },
    { id = "rareAll", name = "Every Rare", desc = "Document every rare beast", points = 100,
      progress = function(s) return Rarity(s, "rare", "seen") end },
    { id = "unique1", name = "Something Special", desc = "Document a unique beast", points = 10,
      progress = function(s) return math.min(1, (Rarity(s, "unique", "seen"))), 1 end },
    { id = "tame1", name = "First Tame", desc = "Tame a beast", points = 5,
      progress = function(s) return s.tamed, 1 end },
    { id = "tame10", name = "Tamer", desc = "Tame 10 different beasts", points = 15,
      progress = function(s) return s.tamed, 10 end },
    { id = "tame50", name = "Beast Tamer", desc = "Tame 50 different beasts", points = 40,
      progress = function(s) return s.tamed, 50 end },
    { id = "tameRare", name = "Rare Tame", desc = "Tame a rare beast", points = 25,
      progress = function(s) return math.min(1, (Rarity(s, "rare", "tamed"))), 1 end },
    { id = "tameRare5", name = "Collector of Rares", desc = "Tame 5 rare beasts", points = 50,
      progress = function(s) return (Rarity(s, "rare", "tamed")), 5 end },
    { id = "tameUnique", name = "One of a Kind", desc = "Tame a unique beast", points = 25,
      progress = function(s) return math.min(1, (Rarity(s, "unique", "tamed"))), 1 end },
}

-- One per family: document every look in it.
local familyAchievements = {}
local function FamilyAchievements(stats)
    for name in pairs(stats.families) do
        if not familyAchievements[name] then
            familyAchievements[name] = {
                id = "family:" .. name, name = name .. " Expert", family = name,
                desc = ("Document every %s look"):format(name), points = 25,
                progress = function(s)
                    local family = s.families[name]
                    if not family then return 0, 0 end
                    return family.seen, family.total
                end,
            }
        end
    end
    local list = {}
    for _, achievement in pairs(familyAchievements) do
        table.insert(list, achievement)
    end
    table.sort(list, function(a, b) return a.family < b.family end)
    return list
end

-- All achievements with their progress: { def, current, target, earned }.
function ns:GetAchievements(stats)
    stats = stats or CollectStats()
    local result = {}
    local function add(def)
        local current, target = def.progress(stats)
        table.insert(result, { def = def, current = math.min(current or 0, target or 0), target = target or 0,
            earned = self.db.achievements[def.id] })
    end
    for _, def in ipairs(ACHIEVEMENTS) do add(def) end
    for _, def in ipairs(FamilyAchievements(stats)) do add(def) end
    return result
end

-- Total points and their parts: { total, looks, documenting, taming,
-- achievements, rank, stats }.
function ns:GetScore()
    local stats = CollectStats()
    local achievementPoints = 0
    for _, entry in ipairs(self:GetAchievements(stats)) do
        if entry.earned then achievementPoints = achievementPoints + entry.def.points end
    end
    local total = stats.lookPoints + achievementPoints
    return { total = total, looks = stats.lookPoints, documenting = stats.seenPoints, taming = stats.tamePoints,
        achievements = achievementPoints, rank = ns.RankForPoints(total), stats = stats }
end

-- Award newly completed achievements, then announce them and any rank up.
-- silent: record without toasts (catching up at login).
function ns:CheckAchievements(silent)
    if not self.db then return end
    local stats = CollectStats()
    local newlyEarned = {}
    for _, entry in ipairs(self:GetAchievements(stats)) do
        if not entry.earned and entry.target > 0 and entry.current >= entry.target then
            self.db.achievements[entry.def.id] = time()
            table.insert(newlyEarned, entry.def)
        end
    end
    local score = self:GetScore()
    local previousRank = self.db.rank or 1
    self.db.rank = score.rank
    if silent then return end
    for _, def in ipairs(newlyEarned) do
        if self.ShowAchievementToast then self:ShowAchievementToast(def) end
        if self.db.settings.announce then
            self:Print(("Achievement earned: |cffffd100%s|r (+%d points)"):format(def.name, def.points))
        end
    end
    if score.rank > previousRank and self.ShowRankToast then
        self:ShowRankToast(score.rank)
    end
end

ns:On("PLAYER_LOGIN", function()
    -- Catch up quietly on anything completed before this version.
    C_Timer.After(2, function() ns:CheckAchievements(true) end)
end)
