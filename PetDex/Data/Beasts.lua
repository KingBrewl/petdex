-- Shipped beast data.
--
-- SEED DATA FOR TESTING ONLY. These are well-known Classic rares plus a couple
-- of common beasts so every status can be tested. The IDs, levels and zones
-- were written from memory and must be checked against the real data source
-- before release. The full list will be generated from that source.
--
-- A dex entry is a LOOK (a creature model), not an NPC: many NPCs share one
-- look, and some NPCs spawn with one of several looks. The game identifies
-- units by NPC ID, so NPCs are the detection key and each lists its looks.
--
-- ns.Beasts, keyed by creature (NPC) ID:
--   name     creature name (enUS)
--   family   pet family (enUS)
--   model    base model the look belongs to ("Lion", "Saber"); the dex
--            groups a family's looks by model. Seed groupings are guesses.
--   spirit   optional; the model glows (spirit beasts), so it can't be
--            drawn as a black silhouette
--   level    level, or { min, max }
--   zone     main zone (enUS)
--   rarity   spawn rarity: "unique" (one of a kind / summoned), "rare" (rare
--            spawn) or "common"
--   note     optional short collector note
--   looks    look IDs this NPC can appear with
--
-- ns.Looks, keyed by look ID (the creature display ID in real data):
--   label    display name for the dex entry
--   family   pet family
--   model    base model group; spirit: glowing model (as for NPCs)
--   displayID  optional; otherwise numeric look IDs are display IDs, and
--            seed looks are loaded through their NPC
--   rarity   optional; otherwise derived from the NPCs that have the look
--            (a look is only as rare as the most common NPC wearing it)
-- Looks referenced by an NPC but missing here are filled in from that NPC.
--
-- The seed looks use placeholder IDs ("seed:...") until real display IDs
-- come from the data source.
local _, ns = ...

ns.Beasts = {
    -- Rares
    [2850]  = { name = "Broken Tooth",        family = "Cat", model = "Lion",    level = 37, zone = "Badlands",         rarity = "rare", note = "1.0 attack speed", looks = { "seed:broken-tooth" } },
    [5828]  = { name = "Humar the Pridelord", family = "Cat", model = "Lion",    level = 23, zone = "The Barrens",      rarity = "rare", looks = { "seed:humar" } },
    [521]   = { name = "Lupos",               family = "Wolf", model = "Wolf",   level = 23, zone = "Duskwood",         rarity = "rare", note = "Deals shadow damage", looks = { "seed:lupos" } },
    [10200] = { name = "Rak'shiri",           family = "Cat", model = "Saber",    level = 57, zone = "Winterspring",     rarity = "rare", looks = { "seed:rakshiri" } },
    [10741] = { name = "Sian-Rotam",          family = "Cat", model = "Saber",    level = 60, zone = "Winterspring",     rarity = "rare", looks = { "seed:sian-rotam" } },
    [5356]  = { name = "Snarler",             family = "Wolf", model = "Wolf",   level = 42, zone = "Feralas",          rarity = "rare", looks = { "seed:snarler" } },
    [2175]  = { name = "Shadowclaw",          family = "Cat", model = "Saber",    level = 13, zone = "Darkshore",        rarity = "rare", looks = { "seed:shadowclaw" } },
    [5807]  = { name = "The Rake",            family = "Cat", model = "Lion",    level = 10, zone = "Mulgore",          rarity = "rare", looks = { "seed:the-rake" } },
    [5842]  = { name = "Takk the Leaper",     family = "Raptor", model = "Raptor", level = 19, zone = "The Barrens",      rarity = "rare", looks = { "seed:takk" } },
    [1130]  = { name = "Bjarn",               family = "Bear", model = "Bear",   level = 12, zone = "Dun Morogh",       rarity = "rare", looks = { "seed:bjarn" } },
    [10077] = { name = "Deathmaw",            family = "Wolf", model = "Wolf",   level = 53, zone = "Burning Steppes",  rarity = "rare", looks = { "seed:deathmaw" } },
    [12431] = { name = "Gorefang",            family = "Wolf", model = "Wolf",   level = 13, zone = "Silverpine Forest", rarity = "rare", looks = { "seed:gorefang" } },

    -- Uniques (summoned or event creatures)
    [3475]  = { name = "Echeyakee",           family = "Cat", model = "Lion",    level = 16, zone = "The Barrens",      rarity = "unique", note = "Summoned by a Horn of Echeyakee quest", looks = { "seed:echeyakee" } },
    [3619]  = { name = "Ghost Saber",         family = "Cat", model = "Saber",    level = 19, zone = "Darkshore",        rarity = "unique", spirit = true, note = "Summoned at the Cliffspring Falls cave", looks = { "seed:ghost-saber" } },

    -- Commons
    [299]   = { name = "Young Wolf",          family = "Wolf", model = "Wolf",   level = { 1, 2 }, zone = "Elwynn Forest", rarity = "common", looks = { "seed:young-wolf" } },
    [2955]  = { name = "Plainstrider",        family = "Tallstrider", model = "Tallstrider", level = { 1, 2 }, zone = "Mulgore",  rarity = "common", looks = { "seed:plainstrider" } },
}

ns.Looks = {}
