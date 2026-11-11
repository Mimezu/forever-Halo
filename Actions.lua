-- Slice kinds: what each slice shows, whether it is available, its live state, and the
-- secure attributes that perform it. "auto" slices expand into several concrete slices.

local _, H = ...

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local RING_ICON = "Interface\\Icons\\Spell_Holy_Aspiration"

-- Forever may hand back secret values in combat; treat them as unknown for logic.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
H.Plain = Plain

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k end
end

-- Emotes: token (slash command), label, icon.
H.EMOTES = {
    { "wave", "Wave", "Interface\\Icons\\INV_Gauntlets_04" },
    { "hello", "Hello", "Interface\\Icons\\INV_Gauntlets_05" },
    { "bow", "Bow", "Interface\\Icons\\Spell_Holy_Devotion" },
    { "cheer", "Cheer", "Interface\\Icons\\Ability_Warrior_BattleShout" },
    { "applaud", "Applaud", "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
    { "dance", "Dance", "Interface\\Icons\\INV_Misc_Drum_01" },
    { "laugh", "Laugh", "Interface\\Icons\\Ability_Rogue_Disguise" },
    { "thank", "Thank", "Interface\\Icons\\Spell_Holy_PrayerOfHealing02" },
    { "salute", "Salute", "Interface\\Icons\\Ability_Warrior_Challange" },
    { "kneel", "Kneel", "Interface\\Icons\\Spell_Holy_Restoration" },
    { "sit", "Sit", "Interface\\Icons\\Spell_Nature_Tranquility" },
    { "sleep", "Sleep", "Interface\\Icons\\Spell_Nature_Sleep" },
    { "roar", "Roar", "Interface\\Icons\\Ability_Druid_ChallangingRoar" },
    { "flex", "Flex", "Interface\\Icons\\Spell_Nature_Strength" },
    { "point", "Point", "Interface\\Icons\\Ability_Hunter_SniperShot" },
    { "kiss", "Kiss", "Interface\\Icons\\Spell_Shadow_SoothingKiss" },
}
local EMOTE_BY_TOKEN = {}
for _, e in ipairs(H.EMOTES) do EMOTE_BY_TOKEN[e[1]] = e end

H.MARKERS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

-- Auto sources: filled from bags or collections whenever Halo rebuilds (out of combat).
H.AUTO = {
    { "potions", "Potions", "Interface\\Icons\\INV_Potion_54", "Healthstones and potions in your bags, healthstones first." },
    { "elixirs", "Elixirs and flasks", "Interface\\Icons\\INV_Potion_45", "Elixirs and flasks in your bags." },
    { "food", "Food and drink", "Interface\\Icons\\INV_Misc_Food_15",
        "One slice: the best food in your bags, and the best drink too if your class uses mana. One press eats and drinks." },
    { "bandages", "Bandages", "Interface\\Icons\\INV_Misc_Bandage_15", "One slice: the best bandage in your bags that you can use." },
    { "scrolls", "Scrolls", "Interface\\Icons\\INV_Scroll_02", "Scrolls in your bags." },
    { "mounts", "Favourite mounts", "Interface\\Icons\\Ability_Mount_RidingHorse",
        "Your favourite mounts that can be used here. With no favourites, all your mounts." },
    { "pets", "Favourite pets", "Interface\\Icons\\INV_Box_PetCarrier_01",
        "Your favourite companion pets." },
}
local AUTO_BY_ID = {}
for _, a in ipairs(H.AUTO) do AUTO_BY_ID[a[1]] = a end
H.AUTO_BY_ID = AUTO_BY_ID

-- Consumable subclasses (item class 0).
local CONSUMABLE_SOURCES = {
    potions = { [1] = true },
    elixirs = { [2] = true, [3] = true },
    scrolls = { [4] = true },
    food = { [5] = true },
    bandages = { [7] = true },
}

-- Healthstones (made by warlocks) are not filed as potions, but they belong with them: the
-- Potions list includes them, before the potions (they are free). Minor, Lesser, plain,
-- Greater and Major, each also in its two Improved Healthstone versions.
local HEALTHSTONES = {}
for _, id in ipairs({ 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009,
    5510, 19010, 19011, 9421, 19012, 19013 }) do
    HEALTHSTONES[id] = true
end
H.HEALTHSTONES = HEALTHSTONES

local function SpellName(id)
    local name = C_Spell and Call(C_Spell.GetSpellName, id)
    if not name and C_Spell and C_Spell.GetSpellInfo then
        local info = Call(C_Spell.GetSpellInfo, id)
        name = info and info.name
    end
    return Plain(name)
end

local function SpellKnown(id)
    if IsPlayerSpell and Call(IsPlayerSpell, id) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook and Call(C_SpellBook.IsSpellKnownOrInSpellBook, id) then return true end
    -- A dropped rank is "this spell": any learned rank with the same name counts.
    local name = SpellName(id)
    local info = name and C_Spell and Call(C_Spell.GetSpellInfo, name)
    local other = info and tonumber(Plain(info.spellID))
    return other ~= nil and other ~= id and IsPlayerSpell ~= nil and Call(IsPlayerSpell, other) == true
end

local function ItemCount(id)
    return tonumber(Plain(C_Item and Call(C_Item.GetItemCount, id, false, true))) or 0
end

local function ItemCooldown(id)
    local getter = C_Container and C_Container.GetItemCooldown or (C_Item and C_Item.GetItemCooldown)
    local start, duration, enable = Call(getter, id)
    return start, duration, enable
end

local function MountInfo(id)
    if not (C_MountJournal and C_MountJournal.GetMountInfoByID) then return end
    local name, spellID, icon, isActive, isUsable, _, isFavorite, _, _, _, isCollected = Call(C_MountJournal.GetMountInfoByID, id)
    return name, spellID, icon, isActive, isUsable, isFavorite, isCollected
end

local function PetInfo(guid)
    if not (C_PetJournal and C_PetJournal.GetPetInfoByPetID) then return end
    local speciesID, customName, _, _, _, _, isFavorite, name, icon = Call(C_PetJournal.GetPetInfoByPetID, guid)
    if not speciesID then return end
    return customName ~= "" and customName or name, icon, isFavorite
end

local function Q(text) return string.format("%q", tostring(text)) end

-- Kind table ---------------------------------------------------------------------------------
-- info(s) -> name, icon      known(s) -> bool      attr(s) -> secure attributes
-- state(s) -> count, cdStart, cdDuration, usable, active
local K = {}
H.Kinds = K

K.spell = {
    label = "Spell",
    info = function(s)
        local info = C_Spell and Call(C_Spell.GetSpellInfo, s.spellID)
        return info and Plain(info.name) or ("Spell " .. tostring(s.spellID)), info and Plain(info.iconID) or QUESTION
    end,
    known = function(s) return SpellKnown(s.spellID) end,
    -- By name: casts the highest rank you know, and follows new ranks.
    attr = function(s) return { type = "spell", spell = SpellName(s.spellID) or s.spellID } end,
    state = function(s)
        local key = SpellName(s.spellID) or s.spellID
        local cd = C_Spell and Call(C_Spell.GetSpellCooldown, key)
        local charges = C_Spell and Call(C_Spell.GetSpellCharges, key)
        local count = charges and Plain(charges.maxCharges) and Plain(charges.maxCharges) > 1 and Plain(charges.currentCharges) or nil
        local usable = C_Spell and Call(C_Spell.IsSpellUsable, key)
        local active = C_Spell and Call(C_Spell.IsCurrentSpell, key)
        return count, cd and cd.startTime, cd and cd.duration, Plain(usable) ~= false, Plain(active) == true
    end,
    tooltip = function(s, tip) tip:SetSpellByID(s.spellID) end,
}

K.item = {
    label = "Item",
    info = function(s)
        local name = C_Item and Call(C_Item.GetItemNameByID, s.itemID)
        local icon = C_Item and Call(C_Item.GetItemIconByID, s.itemID)
        return Plain(name) or ("Item " .. tostring(s.itemID)), Plain(icon) or QUESTION
    end,
    known = function(s)
        return ItemCount(s.itemID) > 0 or (C_Item and Call(C_Item.IsEquippedItem, s.itemID)) == true
    end,
    attr = function(s) return { type = "item", item = "item:" .. s.itemID } end,
    state = function(s)
        local start, duration = ItemCooldown(s.itemID)
        local count = ItemCount(s.itemID)
        local stackable = C_Item and Call(C_Item.GetItemMaxStackSizeByID, s.itemID)
        local showCount = (tonumber(Plain(stackable)) or 1) > 1 or count > 1
        local usable = C_Item and Call(C_Item.IsUsableItem, s.itemID)
        return showCount and count or nil, start, duration, count > 0 and Plain(usable) ~= false, false
    end,
    tooltip = function(s, tip) tip:SetItemByID(s.itemID) end,
}

K.toy = {
    label = "Toy",
    info = function(s)
        local _, name, icon = Call(C_ToyBox and C_ToyBox.GetToyInfo, s.itemID)
        if not name then return K.item.info(s) end
        return name, icon or QUESTION
    end,
    known = function(s) return not PlayerHasToy or Call(PlayerHasToy, s.itemID) == true end,
    attr = function(s) return { type = "toy", toy = s.itemID } end,
    state = function(s)
        local start, duration = ItemCooldown(s.itemID)
        return nil, start, duration, true, false
    end,
    tooltip = function(s, tip)
        if tip.SetToyByItemID then tip:SetToyByItemID(s.itemID) else tip:SetItemByID(s.itemID) end
    end,
}

K.mount = {
    label = "Mount",
    info = function(s)
        local name, _, icon = MountInfo(s.mountID)
        return name or "Mount", icon or QUESTION
    end,
    known = function(s)
        local name, _, _, _, isUsable, _, isCollected = MountInfo(s.mountID)
        return name ~= nil and isCollected ~= false and isUsable ~= false
    end,
    attr = function(s)
        local _, spellID = MountInfo(s.mountID)
        if spellID then return { type = "spell", spell = spellID } end
        return { type = "macro", macrotext = "/run C_MountJournal.SummonByID(" .. tonumber(s.mountID) .. ")" }
    end,
    state = function(s)
        local _, spellID, _, isActive, isUsable = MountInfo(s.mountID)
        local cd = spellID and C_Spell and Call(C_Spell.GetSpellCooldown, spellID)
        return nil, cd and cd.startTime, cd and cd.duration, isUsable ~= false, isActive == true
    end,
    tooltip = function(s, tip)
        local _, spellID = MountInfo(s.mountID)
        if tip.SetMountBySpellID and spellID then tip:SetMountBySpellID(spellID)
        elseif spellID then tip:SetSpellByID(spellID) end
    end,
}

K.pet = {
    label = "Pet",
    info = function(s)
        local name, icon = PetInfo(s.petID)
        return name or "Pet", icon or QUESTION
    end,
    known = function(s) return PetInfo(s.petID) ~= nil end,
    attr = function(s) return { type = "macro", macrotext = "/run C_PetJournal.SummonPetByGUID(" .. Q(s.petID) .. ")" } end,
    state = function(s)
        local summoned = C_PetJournal and Call(C_PetJournal.GetSummonedPetGUID)
        return nil, nil, nil, true, Plain(summoned) == s.petID
    end,
}

-- Pre-journal companions (CallCompanion), in case Forever hands those out on drag.
K.companion = {
    label = "Companion",
    info = function(s)
        local _, name, _, icon = Call(GetCompanionInfo, s.ctype or "CRITTER", s.index)
        return name or "Companion", icon or QUESTION
    end,
    known = function(s) return Call(GetCompanionInfo, s.ctype or "CRITTER", s.index) ~= nil end,
    attr = function(s)
        return { type = "macro", macrotext = "/run CallCompanion(" .. Q(s.ctype or "CRITTER") .. "," .. tonumber(s.index) .. ")" }
    end,
    state = function() return nil, nil, nil, true, false end,
}

K.macro = {
    label = "Macro",
    info = function(s)
        local name, icon = Call(GetMacroInfo, s.name)
        return name or s.name or "Macro", icon or QUESTION
    end,
    known = function(s) return (tonumber((Call(GetMacroIndexByName, s.name))) or 0) > 0 end,
    attr = function(s) return { type = "macro", macro = s.name } end,
    state = function() return nil, nil, nil, true, false end,
    tooltip = function(s, tip)
        local name, _, body = Call(GetMacroInfo, s.name)
        tip:AddLine(name or s.name, 1, 1, 1)
        if body then tip:AddLine(body, 0.75, 0.75, 0.75, true) end
    end,
}

K.equipset = {
    label = "Equipment set",
    info = function(s)
        local id = C_EquipmentSet and Call(C_EquipmentSet.GetEquipmentSetID, s.name)
        local _, icon = id and Call(C_EquipmentSet.GetEquipmentSetInfo, id)
        return s.name or "Equipment set", icon or "Interface\\Icons\\INV_Chest_Chain_04"
    end,
    known = function(s) return C_EquipmentSet ~= nil and Call(C_EquipmentSet.GetEquipmentSetID, s.name) ~= nil end,
    attr = function(s) return { type = "equipmentset", equipmentset = s.name } end,
    state = function(s)
        local id = C_EquipmentSet and Call(C_EquipmentSet.GetEquipmentSetID, s.name)
        local _, _, _, equipped = id and Call(C_EquipmentSet.GetEquipmentSetInfo, id)
        return nil, nil, nil, true, equipped == true
    end,
}

K.emote = {
    label = "Emote",
    info = function(s)
        local e = EMOTE_BY_TOKEN[s.token]
        return e and e[2] or ("/" .. tostring(s.token)), e and e[3] or "Interface\\Icons\\Spell_Holy_Heal"
    end,
    known = function() return true end,
    attr = function(s) return { type = "macro", macrotext = "/" .. tostring(s.token):gsub("[^%w_]", "") } end,
    state = function() return nil, nil, nil, true, false end,
}

K.marker = {
    label = "Target marker",
    info = function(s)
        if s.index == 0 then return "Clear marker", "Interface\\Icons\\INV_Misc_Rune_01" end
        return H.MARKERS[s.index] or "Marker", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. s.index
    end,
    known = function() return true end,
    attr = function(s) return { type = "macro", macrotext = "/tm " .. (tonumber(s.index) or 0) } end,
    state = function(s)
        local current = GetRaidTargetIndex and Call(GetRaidTargetIndex, "target")
        return nil, nil, nil, UnitExists("target"), s.index ~= 0 and Plain(current) == s.index
    end,
}

K.text = {
    label = "Custom macro",
    info = function(s) return s.label ~= "" and s.label or "Custom macro", s.icon or "Interface\\Icons\\INV_Misc_Note_01" end,
    known = function() return true end,
    attr = function(s) return { type = "macro", macrotext = s.text or "" } end,
    state = function() return nil, nil, nil, true, false end,
    tooltip = function(s, tip)
        tip:AddLine(K.text.info(s), 1, 1, 1)
        tip:AddLine(s.text or "", 0.75, 0.75, 0.75, true)
    end,
}

K.ring = {
    label = "Ring",
    info = function(s)
        local ring = H.GetRing(s.ringID)
        local icon = ring and H.RingIcon(ring, true)
        return ring and ring.name or "Missing ring", icon or RING_ICON
    end,
    known = function(s)
        local ring = H.GetRing(s.ringID)
        return ring ~= nil and H.RingActiveHere(ring)
    end,
    state = function() return nil, nil, nil, true, false end,
}

-- Food and drink in one press (the automatic Food and drink list): /use the food, then the drink.
K.meal = {
    label = "Food and drink",
    info = function(s)
        local food, icon = K.item.info({ itemID = s.food })
        local drink = K.item.info({ itemID = s.drink })
        return food .. " + " .. drink, icon
    end,
    known = function(s) return ItemCount(s.food) > 0 or ItemCount(s.drink) > 0 end,
    attr = function(s)
        return { type = "macro", macrotext = "/use item:" .. tonumber(s.food) .. "\n/use item:" .. tonumber(s.drink) }
    end,
    state = function(s)
        local count = ItemCount(s.food)
        return count, nil, nil, count > 0 or ItemCount(s.drink) > 0, false
    end,
    tooltip = function(s, tip)
        tip:AddLine("Eat and drink", 1, 1, 1)
        for _, id in ipairs({ s.food, s.drink }) do
            tip:AddLine((K.item.info({ itemID = id })) .. "  x" .. ItemCount(id), 1, 0.82, 0)
        end
        tip:AddLine("One press uses both.", 0.75, 0.75, 0.75, true)
    end,
}

K.auto = {
    label = "Automatic",
    info = function(s)
        local a = AUTO_BY_ID[s.source]
        return a and a[2] or "Automatic", a and a[3] or QUESTION
    end,
    known = function() return true end,
    state = function() return nil, nil, nil, true, false end,
    tooltip = function(s, tip)
        local a = AUTO_BY_ID[s.source]
        tip:AddLine(a and a[2] or "Automatic", 1, 1, 1)
        if a then tip:AddLine(a[4], 1, 0.82, 0, true) end
        if s.source ~= "food" and s.source ~= "bandages" then
            tip:AddLine("Fills in by itself, up to the ring's 12 slices.", 0.75, 0.75, 0.75, true)
        end
    end,
}

-- Public helpers ------------------------------------------------------------------------------

function H.SliceInfo(s)
    local k = K[s.kind]
    if not k then return "Unknown", QUESTION end
    local ok, name, icon = pcall(k.info, s)
    if not ok then return "Unknown", QUESTION end
    if s.kind ~= "text" and s.label and s.label ~= "" then name = s.label end
    return name or "Unknown", s.icon or icon or QUESTION
end

function H.SliceKnown(s)
    local k = K[s.kind]
    if not k then return false end
    local ok, known = pcall(k.known, s)
    return ok and known == true
end

function H.SliceState(s)
    local k = K[s.kind]
    if not (k and k.state) then return end
    local ok, count, start, duration, usable, active = pcall(k.state, s)
    if ok then return count, start, duration, usable, active end
end

function H.SliceAttributes(s)
    local k = K[s.kind]
    if not (k and k.attr) then return nil end
    local ok, attr = pcall(k.attr, s)
    return ok and attr or nil
end

function H.SliceTooltip(s, tip)
    local k = K[s.kind]
    if k and k.tooltip then
        local ok = pcall(k.tooltip, s, tip)
        if ok and tip:NumLines() > 0 then return end
    end
    tip:AddLine((H.SliceInfo(s)), 1, 1, 1)
end

function H.KindLabel(s)
    local k = K[s.kind]
    return k and k.label or s.kind
end

-- First usable icon of a ring (for lists and nested slices).
function H.RingIcon(ring, avoidRings)
    for _, s in ipairs(ring.slices) do
        if not (avoidRings and s.kind == "ring") then
            local _, icon = H.SliceInfo(s)
            if icon then return icon end
        end
    end
    return RING_ICON
end

-- Auto expansion -------------------------------------------------------------------------------

-- Usable consumables in the bags: { itemID, subclass, order }, one entry per item. A rebuild
-- expands every ring in one go, so the bags are read once per rebuild, not once per list.
local bagScan, bagScanTime
local function ScanBags()
    local now = GetTime()
    if bagScan and bagScanTime == now then return bagScan end
    local out, seen = {}, {}
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, (tonumber((Call(C_Container.GetContainerNumSlots, bag))) or 0) do
                local info = Call(C_Container.GetContainerItemInfo, bag, slot)
                local id = info and tonumber(Plain(info.itemID))
                if id and not seen[id] then
                    seen[id] = true
                    local _, _, _, _, _, classID, subclassID = Call(C_Item.GetItemInfoInstant, id)
                    local usable = C_Item.GetItemSpell and Call(C_Item.GetItemSpell, id)
                    local stone = HEALTHSTONES[id] == true
                    if (classID == 0 and usable) or stone then
                        -- Best first: quality, then item level; healthstones before everything.
                        local order = -(tonumber(Plain(info.quality)) or 0) * 1000 - (tonumber((Call(C_Item.GetDetailedItemLevelInfo, id))) or 0)
                        if stone then order = order - 1000000 end
                        out[#out + 1] = { itemID = id, subclass = subclassID, healthstone = stone, order = order,
                            spell = type(Plain(usable)) == "string" and Plain(usable) or nil }
                    end
                end
            end
        end
    end
    bagScan, bagScanTime = out, now
    return out
end

local function BagConsumables(subclasses, limit, withHealthstones)
    local out = {}
    for _, entry in ipairs(ScanBags()) do
        if (entry.healthstone and withHealthstones) or (not entry.healthstone and subclasses[entry.subclass]) then
            out[#out + 1] = { kind = "item", itemID = entry.itemID, auto = true, order = entry.order }
        end
    end
    table.sort(out, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.itemID > b.itemID end)
    for i = limit + 1, #out do out[i] = nil end
    return out
end

-- One-slice lists (Food and drink, Bandages): the best item of the kind you can use now.
-- Best is the bag order above (quality, then item level); items above your level, or that the
-- game says you cannot use (a bandage beyond your First Aid), are passed over.
local MANA_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, PALADIN = true, SHAMAN = true, HUNTER = true }
local function CanUse(id)
    local reqLevel = tonumber(Plain(select(5, Call(C_Item and C_Item.GetItemInfo or GetItemInfo, id))))
    local level = tonumber(Plain((Call(UnitLevel, "player"))))
    if reqLevel and level and reqLevel > level then return false end
    return Plain((Call(C_Item and C_Item.IsUsableItem, id))) ~= false
end
-- Food or drink, by the item's use spell: "Drink", "Food", or both ("Refreshment", "Food & Drink").
local function MealKind(spell)
    spell = (spell or ""):lower()
    local drink, food = spell:find("drink") ~= nil, spell:find("food") ~= nil
    if spell:find("refreshment") or (drink and food) then return "both" end
    return drink and "drink" or "food"
end
H.MealKind = MealKind   -- (tests)

local function BestUsable(subclasses, placed, accept)
    local list = {}
    for _, entry in ipairs(ScanBags()) do
        if not entry.healthstone and subclasses[entry.subclass] and not placed[entry.itemID] and (not accept or accept(entry)) then
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.itemID > b.itemID end)
    for _, entry in ipairs(list) do
        if CanUse(entry.itemID) then return entry.itemID end
    end
end

local function Meal(placed)
    local function Is(kind) return function(entry) local k = MealKind(entry.spell); return k == kind or k == "both" end end
    local food = BestUsable(CONSUMABLE_SOURCES.food, placed, Is("food"))
    local drink
    local _, class = Call(UnitClass, "player")
    if MANA_CLASSES[Plain(class)] then drink = BestUsable(CONSUMABLE_SOURCES.food, placed, Is("drink")) end
    if food and drink and food ~= drink then return { { kind = "meal", food = food, drink = drink, auto = true } } end
    local one = food or drink
    return one and { { kind = "item", itemID = one, auto = true } } or {}
end

local function Bandage(placed)
    local id = BestUsable(CONSUMABLE_SOURCES.bandages, placed)
    return id and { { kind = "item", itemID = id, auto = true } } or {}
end

local function Mounts(limit)
    local out, all = {}, {}
    local ids = C_MountJournal and Call(C_MountJournal.GetMountIDs)
    for _, id in ipairs(ids or {}) do
        local name, _, _, _, isUsable, isFavorite, isCollected = MountInfo(id)
        if name and isCollected and isUsable then
            local s = { kind = "mount", mountID = id, auto = true, name = name }
            if isFavorite then out[#out + 1] = s else all[#all + 1] = s end
        end
    end
    if #out == 0 then out = all end
    table.sort(out, function(a, b) return a.name < b.name end)
    for i = limit + 1, #out do out[i] = nil end
    return out
end

local function Pets(limit)
    local out = {}
    local ids = C_PetJournal and Call(C_PetJournal.GetOwnedPetIDs)
    for _, guid in ipairs(ids or {}) do
        local name, _, isFavorite = PetInfo(guid)
        if name and isFavorite then out[#out + 1] = { kind = "pet", petID = guid, auto = true, name = name } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    for i = limit + 1, #out do out[i] = nil end
    return out
end

-- The concrete slices a ring shows right now, in order. hideMissing drops the ones
-- you cannot use (spell not learned, item not in bags). A ring shows up to MAX_SLICES:
-- slices placed by hand always get their place, automatic lists fill the room left.
function H.ExpandRing(ring)
    local out = {}
    local limit = H.MAX_SLICES
    -- Items placed by hand are not repeated by an automatic list.
    local placed = {}
    local shows, later = {}, 0
    for i, s in ipairs(ring.slices) do
        if s.kind == "item" and s.itemID then placed[s.itemID] = true end
        shows[i] = s.kind ~= "auto" and (not ring.hideMissing or H.SliceKnown(s))
        if shows[i] then later = later + 1 end
    end
    for i, s in ipairs(ring.slices) do
        if #out >= limit then break end
        if s.kind == "auto" then
            -- Room for this list: what is left after the hand-placed slices still to come.
            local room = limit - #out - later
            local list
            if room <= 0 then list = nil
            elseif s.source == "food" then list = Meal(placed)
            elseif s.source == "bandages" then list = Bandage(placed)
            elseif CONSUMABLE_SOURCES[s.source] then
                list = BagConsumables(CONSUMABLE_SOURCES[s.source], room + 4, s.source == "potions")
            elseif s.source == "mounts" then list = Mounts(room)
            elseif s.source == "pets" then list = Pets(room) end
            local taken = 0
            for _, item in ipairs(list or {}) do
                if taken >= room then break end
                if not (item.itemID and placed[item.itemID]) then out[#out + 1] = item; taken = taken + 1 end
            end
        elseif shows[i] then
            out[#out + 1] = s
            later = later - 1
        end
    end
    return out
end

-- Drag and drop: the thing on the cursor as a slice, or nil.
function H.CursorSlice()
    local kind, a, b, c = GetCursorInfo()
    if kind == "spell" then
        local spellID = tonumber(c) or tonumber(a)
        if not spellID then return nil end
        local mountID = C_MountJournal and Call(C_MountJournal.GetMountFromSpell, spellID)
        if mountID then return { kind = "mount", mountID = mountID } end
        return { kind = "spell", spellID = spellID }
    elseif kind == "item" then
        local itemID = tonumber(a)
        if not itemID then return nil end
        local toy = C_ToyBox and Call(C_ToyBox.GetToyInfo, itemID)
        if toy and PlayerHasToy and Call(PlayerHasToy, itemID) and ItemCount(itemID) == 0 then
            return { kind = "toy", itemID = itemID }
        end
        return { kind = "item", itemID = itemID }
    elseif kind == "toy" then
        return tonumber(a) and { kind = "toy", itemID = tonumber(a) }
    elseif kind == "mount" or kind == "summonmount" then
        return tonumber(a) and { kind = "mount", mountID = tonumber(a) }
    elseif kind == "battlepet" then
        return a and { kind = "pet", petID = a }
    elseif kind == "companion" then
        return tonumber(a) and { kind = "companion", index = tonumber(a), ctype = b or "CRITTER" }
    elseif kind == "macro" then
        local name = Call(GetMacroInfo, a)
        return name and { kind = "macro", name = name }
    elseif kind == "equipmentset" then
        return a and { kind = "equipset", name = a }
    end
end
