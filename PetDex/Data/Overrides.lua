-- Hand-made corrections on top of the generated Data/Beasts.lua. Fields here
-- replace the generated ones for that NPC; the generator never touches this
-- file.
--
-- Also accepts fields the generator can't know:
--   spirit   true: the model glows, so it can't be a black silhouette
--   model    base model group name, until model groups come from the game
local _, ns = ...

local OVERRIDES = {
    -- Summoned beasts: no fixed spawn, so the generator can't tell them from
    -- unused creatures.
    [3475]  = { rarity = "unique", note = "Summoned" },              -- Echeyakee
    [3619]  = { rarity = "unique", note = "Summoned", spirit = true }, -- Ghost Saber
    [3257]  = { rarity = "unique", note = "Summoned" },              -- Ishamuhale
    [10882] = { rarity = "unique", note = "Summoned" },              -- Arikara
    [10737] = { rarity = "unique", note = "Summoned" },              -- Shy-Rotam
    [10741] = { rarity = "unique", note = "Summoned" },              -- Sian-Rotam
}

for npcID, fields in pairs(OVERRIDES) do
    local beast = ns.Beasts[npcID]
    if beast then
        for key, value in pairs(fields) do
            beast[key] = value
        end
    end
end
