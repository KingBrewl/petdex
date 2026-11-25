-- Hunter pet families in WoW Forever: each family's unique ability, and
-- whether it learns Dash (runners) or Dive (fliers).
--
-- From community guides (wowseer.gg, theforeverguides.com, conquestcapped.com,
-- November 2026), not official notes; abilities were still being tuned
-- during the launch period, so descriptions stay general.
-- Classic's "Owl" family is "Bird of Prey" in Forever; Fox is new in Forever.
local _, ns = ...

ns.Families = {
    ["Bat"]          = { ability = "Sonic Blast", effect = "slows the enemy's spellcasting", move = "Dive" },
    ["Bear"]         = { ability = "Swipe", effect = "hits up to three enemies", move = "Dash" },
    ["Bird of Prey"] = { ability = "Mine!", effect = "disarms the enemy", move = "Dive" },
    ["Boar"]         = { ability = "Charge", effect = "charges and roots; the next attack hits harder", move = "Dash" },
    ["Carrion Bird"] = { ability = "Demoralizing Screech", effect = "lowers nearby enemies' attack power", move = "Dive" },
    ["Cat"]          = { ability = "Prowl", effect = "stealth; the opening attack deals bonus damage", move = "Dash" },
    ["Crab"]         = { ability = "Pinch", effect = "damages and slows", move = "Dash" },
    ["Crocolisk"]    = { ability = "Dismember", effect = "reduces the enemy's healing received", move = "Dash" },
    ["Fox"]          = { ability = "Trickster's Dance", effect = "a burst of dodge and attack speed", move = "Dash" },
    ["Gorilla"]      = { ability = "Thunderstomp", effect = "damages nearby enemies", move = "Dash" },
    ["Hyena"]        = { ability = "Tendon Rip", effect = "a bleed that also slows", move = "Dash" },
    ["Raptor"]       = { ability = "Savage Rend", effect = "a strong bleed", move = "Dash" },
    ["Scorpid"]      = { ability = "Scorpid Poison", effect = "a stacking nature poison", move = "Dash" },
    ["Spider"]       = { ability = "Web", effect = "roots the enemy", move = "Dash" },
    ["Tallstrider"]  = { ability = "Dust Cloud", effect = "lowers the target's armor", move = "Dash" },
    ["Turtle"]       = { ability = "Shell Shield", effect = "greatly reduces damage taken", move = "Dash" },
    ["Wind Serpent"] = { ability = "Lightning Breath", effect = "ranged nature damage", move = "Dive" },
    ["Wolf"]         = { ability = "Furious Howl", effect = "raises the party's melee attack power", move = "Dash" },
}
