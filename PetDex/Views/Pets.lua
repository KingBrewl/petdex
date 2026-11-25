-- My Pets tab: your active pet and your stable (as last seen at a stable
-- master), with the beast each came from. The active pet shows its live
-- details: loyalty, happiness and its effect on damage, training points,
-- attack speed, abilities and diet.
local _, ns = ...

local LIST_WIDTH = 250
local ROW_HEIGHT = 40
local STAGE_HEIGHT = 230
local QUEST_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local HEADING = "|cffffd100%s|r"
local GREY = "|cff9d9d9d%s|r"
local HAPPINESS = {
    [1] = "|cffff4040Unhappy|r (75% damage)",
    [2] = "|cffffd100Content|r (100% damage)",
    [3] = "|cff40ff40Happy|r (125% damage)",
}

-- Calls a game API safely; nil on missing, error or secret values.
local function Pack(...)
    return select("#", ...), { ... }
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local count, results = Pack(pcall(fn, ...))
    if not results[1] then return end
    for i = 2, count do
        if ns.IsSecret(results[i]) then return end
    end
    return unpack(results, 2, count)
end

-- Abilities in the pet spellbook: "Claw (Rank 6)", passives marked.
local function PetAbilities()
    local abilities = {}
    for _, ability in ipairs(ns:GetPetAbilities()) do
        local text = ability.rank and (ability.name .. " (" .. ability.rank .. ")") or ability.name
        table.insert(abilities, ability.passive and GREY:format(text .. ", passive") or text)
    end
    return abilities
end

local function ActivePetEntry()
    if not UnitExists("pet") then return end
    local char = ns.GetCharData()
    local guid = UnitGUID("pet")
    local npcID = guid and not ns.IsSecret(guid) and char.pets[guid]
    local name = UnitName("pet")
    if ns.IsSecret(name) then name = "Your pet" end
    npcID = npcID or (name and char.petNames[name])
    return {
        active = true,
        name = name,
        level = Call(UnitLevel, "pet"),
        family = Call(UnitCreatureFamily, "pet"),
        npcID = npcID,
    }
end

local function PetList()
    local list = {}
    local active = ActivePetEntry()
    if active then table.insert(list, active) end
    for _, pet in ipairs(ns.GetCharData().stable) do
        -- Slot 0 is the active pet when the stable was last opened.
        if pet.slot ~= 0 or not active then
            table.insert(list, { name = pet.name, level = pet.level, family = pet.family,
                npcID = pet.npcID, icon = pet.icon, slot = pet.slot })
        end
    end
    return list
end

local function Create(parent)
    local ui = ns.DexUI
    local Skin = ns.Skin
    local view = CreateFrame("Frame", nil, parent)
    view.rows = {}

    local list = Skin.CreateInset(view)
    list:SetPoint("TOPLEFT", view, "TOPLEFT", ui.INSET.left, -ui.BODY_TOP)
    list:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", ui.INSET.left, ui.INSET.bottom)
    list:SetWidth(LIST_WIDTH)
    view.list = list
    local listTitle = Skin.CreateHeading(list, "Your pets", "GameFontNormalLarge")
    listTitle:SetPoint("TOPLEFT", ui.PAD, -ui.PAD)
    listTitle.divider:SetPoint("RIGHT", list, "RIGHT", -ui.PAD, 0)
    view.listHint = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.listHint:SetPoint("BOTTOMLEFT", ui.PAD, ui.PAD)
    view.listHint:SetPoint("RIGHT", list, "RIGHT", -ui.PAD, 0)
    view.listHint:SetJustifyH("LEFT")
    view.listHint:SetText("Visit a stable master to update your stable here.")

    local detail = Skin.CreateInset(view)
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 4, 0)
    detail:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -ui.INSET.right, ui.INSET.bottom)
    view.detail = detail

    view.stage = ns.CreateBeastStage(detail, 300, STAGE_HEIGHT)
    view.stage.frame:SetPoint("TOPLEFT", ui.PAD + 4, -ui.PAD - 4)
    view.stage:EnableTurning()
    Skin.FrameStage(detail, view.stage)

    view.name = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    view.name:SetPoint("TOPLEFT", view.stage.frame, "TOPRIGHT", 20, 0)
    view.name:SetPoint("RIGHT", detail, "RIGHT", -ui.PAD, 0)
    view.name:SetJustifyH("LEFT")
    view.info = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    view.info:SetPoint("TOPLEFT", view.name, "BOTTOMLEFT", 0, -8)
    view.info:SetPoint("RIGHT", detail, "RIGHT", -ui.PAD, 0)
    view.info:SetJustifyH("LEFT")
    view.info:SetJustifyV("TOP")
    view.info:SetSpacing(3)

    view.open = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    view.open:SetSize(140, 22)
    view.open:SetPoint("TOPLEFT", view.stage.frame, "BOTTOMLEFT", -4, -12)
    view.open:SetText("Open in the Dex")
    view.open:SetScript("OnClick", function()
        local pet = view.selected
        local lookID = pet and pet.npcID and ns:GetLooks(pet.npcID)[1]
        if lookID then ns:OpenDexAt(lookID) end
    end)

    view.empty = detail:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    view.empty:SetPoint("CENTER")
    return view
end

local function Row(view, index)
    local row = view.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, view.list)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture(QUEST_HIGHLIGHT, "ADD")
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetTexture(QUEST_HIGHLIGHT)
    row.selected:SetBlendMode("ADD")
    row.selected:SetVertexColor(1, 0.82, 0, 0.6)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", 6, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row:SetScript("OnClick", function(self)
        ns.Skin.PlaySound("select")
        view.selectedKey = self.key
        ns.DexViews.pets.Refresh(view)
    end)
    view.rows[index] = row
    return row
end

-- Text for the detail panel.
local function DetailLines(pet)
    local lines = {}
    local beast = pet.npcID and ns:GetBeast(pet.npcID)
    table.insert(lines, ("Level %s %s"):format(pet.level or "?", pet.family or ""))
    if beast then
        table.insert(lines, ("Tamed from %s"):format(beast.name))
        local record = ns.db.beasts[pet.npcID]
        if record and record.tamed then
            local zone = ns:GetBeastZone(beast)
            table.insert(lines, GREY:format(("First tamed %s%s"):format(date("%d %b %Y", record.tamed),
                zone and (", " .. zone) or "")))
        end
    else
        table.insert(lines, GREY:format("PetDex doesn't know which beast this pet came from."))
    end
    table.insert(lines, " ")

    if not pet.active then
        table.insert(lines, GREY:format(pet.slot and ("In stable slot %d. Summon it to see loyalty, happiness and abilities.")
            :format(pet.slot) or ""))
        return lines
    end

    table.insert(lines, HEADING:format("Care"))
    local loyalty = Call(GetPetLoyalty)
    if loyalty then table.insert(lines, loyalty) end
    local happiness = Call(GetPetHappiness)
    if happiness and HAPPINESS[happiness] then
        table.insert(lines, "Happiness: " .. HAPPINESS[happiness])
    end
    local foods = { Call(GetPetFoodTypes) }
    local familyData = pet.family and ns.FamilyData and ns.FamilyData[pet.family]
    if #foods == 0 and familyData then
        foods = familyData.diet
    end
    if #foods > 0 then
        table.insert(lines, "Eats: " .. table.concat(foods, ", "))
    end
    local current, needed = Call(GetPetExperience)
    if current and needed and needed > 0 then
        table.insert(lines, ("Experience: %d / %d"):format(current, needed))
    end
    table.insert(lines, " ")

    table.insert(lines, HEADING:format("Training"))
    local total, spent = Call(GetPetTrainingPoints)
    if total then
        table.insert(lines, ("Training points: %d of %d free"):format(total - (spent or 0), total))
    end
    local speed = Call(UnitAttackSpeed, "pet")
    if speed then
        table.insert(lines, ("Attack speed: %.2fs"):format(speed))
    end
    local abilities = PetAbilities()
    if #abilities > 0 then
        table.insert(lines, "Abilities: " .. table.concat(abilities, ", "))
    end
    return lines
end

local function Refresh(view)
    local ui = ns.DexUI
    local pets = PetList()
    if ns.playerClass ~= "HUNTER" then
        pets = {}
        view.empty:SetText("Only hunters have pets to show here.")
    else
        view.empty:SetText("No pets yet. Tame a beast, or visit a stable master.")
    end

    -- Keep the selection by key (active, or stable slot), else the first.
    local selected
    for i, pet in ipairs(pets) do
        pet.key = pet.active and "active" or ("slot" .. (pet.slot or i))
        if pet.key == view.selectedKey then selected = pet end
    end
    selected = selected or pets[1]
    view.selected = selected
    view.selectedKey = selected and selected.key

    local y = ui.PAD + 34
    for i, pet in ipairs(pets) do
        local row = Row(view, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", view.list, "TOPLEFT", ui.PAD - 6, -y)
        row:SetPoint("RIGHT", view.list, "RIGHT", -ui.PAD + 6, 0)
        row.key = pet.key
        row.name:SetText(pet.name or "?")
        row.sub:SetText(("%s%s %s"):format(pet.active and "|cff40ff40Active|r  ·  " or "",
            pet.level and ("Level " .. pet.level) or "", pet.family or ""))
        row.icon:SetTexture(pet.icon or (pet.active and GetPetIcon and Call(GetPetIcon))
            or "Interface\\Icons\\Ability_Hunter_BeastTaming")
        row.selected:SetShown(pet == selected)
        ns.Skin.Stripe(row, i)
        row:Show()
        y = y + ROW_HEIGHT + 2
    end
    for i = #pets + 1, #view.rows do
        view.rows[i]:Hide()
    end

    view.empty:SetShown(selected == nil)
    view.stage.frame:SetShown(selected ~= nil)
    view.name:SetShown(selected ~= nil)
    view.info:SetShown(selected ~= nil)
    view.open:SetShown(selected ~= nil and selected.npcID ~= nil)
    if not selected then return end

    view.name:SetText(selected.name or "?")
    view.info:SetText(table.concat(DetailLines(selected), "\n"))
    local lookID = selected.npcID and ns:GetLooks(selected.npcID)[1]
    local info = lookID and ns:GetLookInfo(lookID)
    if info then
        view.stage:SetBeast({ npcID = selected.npcID, displayID = info.displayID, state = "tamed",
            rarity = info.rarity, spirit = info.spirit })
    else
        view.stage:SetBeast(nil)
    end
end

ns.DexViews.pets = { Create = Create, Refresh = Refresh }

-- Keep the tab current while it's open: pet summoned, dismissed, renamed,
-- fed, levelled, or the stable changed.
-- Pet events fire often in combat, so refreshes are coalesced.
local queued = false
local function Update()
    if queued or not (ns.db and ns.db.settings.tab == "pets") then return end
    queued = true
    C_Timer.After(0.5, function()
        queued = false
        ns:OnCollectionChanged()
    end)
end
for _, event in ipairs({ "UNIT_PET", "PET_STABLE_UPDATE", "UNIT_HAPPINESS", "PET_BAR_UPDATE", "UNIT_NAME_UPDATE" }) do
    ns:On(event, Update)
end
