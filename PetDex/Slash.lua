-- Slash commands: /petdex or /pdex
local _, ns = ...

local TOGGLES = {
    tooltip = "Tooltip status",
    announce = "Chat announcements",
    debug = "Debug output",
}

local function PrintStatus()
    local stats = ns:GetStats()
    ns:Print(("Tamed %d/%d looks (%d seen). Rare and unique looks: %d/%d.")
        :format(stats.tamed, stats.total, stats.seen, stats.raresTamed, stats.rares))
    if stats.unverified > 0 then
        ns:Print(("%d beasts found in the wild are waiting to be confirmed tameable."):format(stats.unverified))
    end
    if ns.charKey and ns.db.chars[ns.charKey] then
        local unidentified = #ns.db.chars[ns.charKey].unidentified
        if unidentified > 0 then
            ns:Print(("%d stabled pets couldn't be matched to a beast."):format(unidentified))
        end
    end
end

local function PrintHelp()
    ns:Print("v" .. ns.version .. " commands:")
    print("  /petdex - collection summary")
    print("  /petdex tooltip | announce | debug - toggle a setting")
    print("  /petdex probe [unit] - debug: test reading a unit's model (default target)")
    print("  /petdex lab [displayID | npc:<id>] - debug: model lab window (default target)")
    print("  /petdex reset - wipe all collection data")
end

SLASH_PETDEX1 = "/petdex"
SLASH_PETDEX2 = "/pdex"
SlashCmdList.PETDEX = function(message)
    local command, argument = message:lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "" or command == "status" then
        PrintStatus()
    elseif command == "probe" then
        ns:ProbeModel(argument)
    elseif command == "lab" then
        ns:OpenModelLab(argument)
    elseif TOGGLES[command] then
        local settings = ns.db.settings
        settings[command] = not settings[command]
        ns:Print(TOGGLES[command], settings[command] and "|cff40ff40on|r" or "|cffff4040off|r")
    elseif command == "reset" then
        if argument == "confirm" then
            wipe(ns.db.beasts)
            wipe(ns.db.discovered)
            wipe(ns.db.chars)
            ns:Print("All collection data wiped.")
        else
            ns:Print("This deletes your whole collection on every character. Type |cffffd100/petdex reset confirm|r to proceed.")
        end
    else
        PrintHelp()
    end
end
