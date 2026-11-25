-- Toasts: a short popup when a beast joins the dex (first seen) or is tamed.
-- Shows the beast's model, its name in rarity colour and the new progress.
-- Several in a row queue up; hovering keeps one open; clicking opens the dex
-- on that beast. Toggle with /petdex toasts.
local _, ns = ...

local WIDTH, HEIGHT = 340, 92
local SHOW_TIME, FADE_TIME = 4, 0.6
local GOLD = { 1, 0.82, 0 }

local toast
local queue = {}
local current

-- The game's own reward sounds, best first per tier; the first one this
-- client's SOUNDKIT knows is played. Bigger finds, bigger sounds.
local SOUNDS = {
    seen = { "UI_LOOT_TOAST_LESSER_ITEM_WON_01", "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },
    rare = { "UI_EPICLOOT_TOAST", "UI_LEGENDARY_LOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },
    tamed = { "UI_LEGENDARY_LOOT_TOAST", "UI_EPICLOOT_TOAST", "LEVELUPSOUND", "IG_QUEST_LIST_COMPLETE" },
}

local function PlayToastSound(kind, rarity)
    if not PlaySound or not SOUNDKIT then return end
    local tier = kind == "tamed" and "tamed" or (rarity ~= "common" and "rare" or "seen")
    for _, key in ipairs(SOUNDS[tier]) do
        local sound = SOUNDKIT[key]
        if sound and pcall(PlaySound, sound, "SFX") then
            ns:Debug("toast sound", tier, key)
            return
        end
    end
end

-- "Cat 13/51  ·  PetDex 120/588" (documented counts).
local function ProgressText(info)
    local total, seen, familySeen, familyTotal = 0, 0, 0, 0
    for _, family in ipairs(ns:GetDexFamilies()) do
        total = total + family.total
        seen = seen + family.seen
        if family.name == info.family then
            familySeen, familyTotal = family.seen, family.total
        end
    end
    return ("%s %d/%d  ·  PetDex %d/%d"):format(info.family, familySeen, familyTotal, seen, total)
end

local ShowNext

local function Finish()
    toast:Hide()
    current = nil
    ShowNext()
end

local function CreateToast()
    -- A native panel, with the model in an item-slot frame.
    toast = ns.Skin.CreateFrame("Button", UIParent, "panel", "PetDexToast")
    toast:SetSize(WIDTH, HEIGHT)
    toast:SetPoint("TOP", 0, -150)
    toast:SetFrameStrata("HIGH")
    toast:Hide()

    toast.stage = ns.CreateBeastStage(toast, 76, 76)
    toast.stage.frame:SetPoint("LEFT", 12, 0)
    toast.slot = ns.Skin.FrameStage(toast, toast.stage)

    toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toast.title:SetPoint("TOPLEFT", toast.stage.frame, "TOPRIGHT", 12, -4)
    toast.name = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    toast.name:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -3)
    toast.name:SetPoint("RIGHT", -10, 0)
    toast.name:SetJustifyH("LEFT")
    toast.name:SetWordWrap(false)
    toast.sub = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toast.sub:SetPoint("TOPLEFT", toast.name, "BOTTOMLEFT", 0, -3)
    toast.progress = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    toast.progress:SetPoint("TOPLEFT", toast.sub, "BOTTOMLEFT", 0, -4)

    toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    toast:SetScript("OnClick", function(_, button)
        if button == "LeftButton" and current and ns.OpenDexAt then
            ns:OpenDexAt(current.lookID)
        end
        Finish()
    end)
    toast:SetScript("OnUpdate", function(self, elapsed)
        -- Hovering holds the toast fully visible.
        if self:IsMouseOver() then
            self.elapsed = math.min(self.elapsed, SHOW_TIME)
            self:SetAlpha(1)
            return
        end
        self.elapsed = self.elapsed + elapsed
        if self.elapsed <= SHOW_TIME then return end
        local alpha = 1 - (self.elapsed - SHOW_TIME) / FADE_TIME
        if alpha <= 0 then
            Finish()
        else
            self:SetAlpha(alpha)
        end
    end)
end

ShowNext = function()
    local entry = table.remove(queue, 1)
    if not entry then return end
    local info = ns:GetLookInfo(entry.lookID)
    if not info then
        ShowNext()
        return
    end
    if not toast then CreateToast() end
    current = entry

    local rarityColor = ns.RARITY_COLORS[info.rarity] or ns.RARITY_COLORS.common
    local rare = info.rarity ~= "common"
    local title
    if entry.kind == "tamed" then
        title = "Beast tamed!"
    elseif rare then
        title = (info.rarity == "unique" and "Unique" or "Rare") .. " beast documented!"
    else
        title = "New beast documented"
    end
    toast.title:SetText(title)
    toast.name:SetText(info.label)
    toast.name:SetTextColor(rarityColor[1], rarityColor[2], rarityColor[3])
    local zone = ns:GetBeastZone(info.beast)
    toast.sub:SetText(zone and (info.family .. "  ·  " .. zone) or info.family)
    toast.progress:SetText(ProgressText(info))
    local accent = (entry.kind == "tamed" or rare) and rarityColor or GOLD
    ns.Skin.SetBorderColor(toast, accent)
    ns.Skin.SetBorderColor(toast.slot, accent)

    toast.stage:SetBeast({ npcID = info.npcID, displayID = info.displayID,
        state = entry.kind == "tamed" and "tamed" or "seen", rarity = info.rarity, spirit = info.spirit })
    toast.elapsed = 0
    toast:SetAlpha(1)
    toast:Show()
    PlayToastSound(entry.kind, info.rarity)
end

-- /petdex testtoast [rare|unique|tamed]: preview a toast and its sound with
-- a random beast of that rarity, without touching the collection.
function ns:TestToast(kind)
    local rarity = (kind == "rare" or kind == "unique") and kind or "common"
    local picks = {}
    self:ForEachLook(function(lookID, look)
        if look and look.rarity == rarity then
            picks[#picks + 1] = lookID
        end
    end)
    if #picks == 0 then
        self:Print("No beast of that rarity to show.")
        return
    end
    table.insert(queue, { lookID = picks[math.random(#picks)], kind = kind == "tamed" and "tamed" or "seen" })
    if not current then
        ShowNext()
    end
end

-- Called by Collection.lua. kind: "seen" (newly documented) or "tamed".
function ns:ShowDiscovery(lookID, kind)
    if not self.db.settings.toasts then return end
    -- A tame replaces a queued "documented" toast for the same look.
    for i = #queue, 1, -1 do
        if queue[i].lookID == lookID then
            table.remove(queue, i)
        end
    end
    table.insert(queue, { lookID = lookID, kind = kind })
    if not current then
        ShowNext()
    end
end
