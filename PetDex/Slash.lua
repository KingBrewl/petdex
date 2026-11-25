-- Slash commands: /petdex or /pdex
local _, ns = ...

local TOGGLES = {
    tooltip = "Tooltip status",
    announce = "Chat announcements",
    toasts = "Discovery popups",
    mouseover = "Documenting beasts on mouseover",
    debug = "Debug output",
}

local function PrintStatus()
    local stats = ns:GetStats()
    ns:Print(("Documented %d/%d beasts, %d tamed. Rare and unique tamed: %d/%d.")
        :format(stats.seen, stats.total, stats.tamed, stats.raresTamed, stats.rares))
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
    print("  /petdex - open or close the dex")
    print("  /petdex status - collection summary in chat")
    print("  /petdex tooltip | announce | toasts | mouseover | debug - toggle a setting")
    print("  /petdex probe [unit] - debug: test reading a unit's model (default target)")
    print("  /petdex lab [displayID | npc:<id>] - debug: model lab window (default target)")
    print("  /petdex minimap - show or hide the minimap button")
    print("  /petdex testtoast [rare | unique | tamed | achievement | rank] - preview a popup")
    print("  /petdex clearseen - forget all sightings (seen, not tamed); tames are kept")
    print("  /petdex reset - wipe all collection data")
end

SLASH_PETDEX1 = "/petdex"
SLASH_PETDEX2 = "/pdex"
SlashCmdList.PETDEX = function(message)
    local command, argument = message:lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "" then
        ns:ToggleDex()
    elseif command == "status" then
        PrintStatus()
    elseif command == "probe" then
        ns:ProbeModel(argument)
    elseif command == "lab" then
        ns:OpenModelLab(argument)
    elseif command == "testtoast" then
        ns:TestToast(argument)
    elseif command == "minimap" then
        ns.db.settings.minimap = not ns.db.settings.minimap
        ns:UpdateMinimapButton()
        ns:Print("Minimap button", ns.db.settings.minimap and "|cff40ff40shown|r" or "|cffff4040hidden|r")
    elseif command == "clearseen" then
        -- Forget sightings (seen but never tamed) and unconfirmed discoveries;
        -- tames are kept.
        local cleared = 0
        for npcID, record in pairs(ns.db.beasts) do
            if not record.tamed then
                ns.db.beasts[npcID] = nil
                cleared = cleared + 1
            end
        end
        for npcID, beast in pairs(ns.db.discovered) do
            if not beast.verified then
                ns.db.discovered[npcID] = nil
            end
        end
        ns:Print(("Forgot %d sightings. Your tames are kept."):format(cleared))
        ns:OnCollectionChanged()
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
