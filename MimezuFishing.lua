-- MimezuFishing: the fishing pole swap, shared by Gamepad Companion and Halo. The same file
-- ships in both addons; the newest copy loaded wins, as a library would, so the logic lives in
-- one place. Out of combat each host asks for the swap's macro and puts it on a secure button
-- (a key, a ring slice, a bar slot): one press puts the best pole from the bags in your hands,
-- the next puts back the weapons you held before. The macro's conditions ([equipped:Fishing
-- Poles]) pick the way at the press, so it stays right in combat, where nothing can be rebuilt.
local VERSION = 1
local lib = _G.MimezuFishing
if type(lib) == "table" and (tonumber(lib.version) or 0) >= VERSION then return end
lib = type(lib) == "table" and lib or {}
_G.MimezuFishing = lib
lib.version = VERSION
lib.stores = lib.stores or {}

local WEAPON, POLE = 2, 20                 -- item class Weapon, subclass Fishing Poles
local MAIN, OFF = 16, 17                   -- the hands (a pole never touches the ranged slot)
lib.MAIN, lib.OFF = MAIN, OFF
lib.ICON = "Interface\\Icons\\INV_Fishingpole_02"
lib.WEAPONS_ICON = "Interface\\Icons\\INV_Sword_04"
lib.SPELL = 7620                           -- Fishing (the rank you know is cast by name)
lib.MACRO_MAX = 255                        -- a bar slot's macro

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g end
end

local function Item() return type(C_Item) == "table" and C_Item or {} end

-- An item's class and subclass (instant, cached or not)
local function Kind(id)
    if not id then return nil end
    local _, _, _, _, _, classID, subclass = Call(Item().GetItemInfoInstant or GetItemInfoInstant, id)
    return classID, subclass
end

function lib.IsPole(classID, subclass) return classID == WEAPON and subclass == POLE end
function lib.IsPoleItem(id) return lib.IsPole(Kind(id)) end

-- The game's word for poles, as macro conditions read it ("Fishing Poles")
function lib.PoleType()
    local name = Call(Item().GetItemSubClassInfo or GetItemSubClassInfo, WEAPON, POLE)
    return type(name) == "string" and name ~= "" and name or "Fishing Poles"
end

local function Name(id)
    if not id then return nil end
    local name = Call(Item().GetItemNameByID, id) or Call(Item().GetItemInfo or GetItemInfo, id)
    return type(name) == "string" and name ~= "" and name or nil
end
lib.Name = Name

local function Icon(id)
    if not id then return nil end
    return Call(Item().GetItemIconByID, id) or Call(GetItemIcon, id)
end

local function Equipped(slot) return Call(GetInventoryItemID, "player", slot) end

function lib.PoleEquipped() return lib.IsPoleItem(Equipped(MAIN)) end

--[[ The best pole of a list, or nil. items: { id, ilvl, quality, reqLevel, usable }. One you
can use first, then the highest item level (the better poles are the later ones), then quality,
then the lowest id (the same pole twice: the first). ]]
function lib.Best(items, level)
    local best
    local function Fits(i)
        return i.usable ~= false and not (level and i.reqLevel and i.reqLevel > level)
    end
    for _, i in ipairs(items or {}) do
        if not best then
            best = i
        else
            local a, b = Fits(i), Fits(best)
            if a ~= b then
                if a then best = i end
            elseif (i.ilvl or 0) ~= (best.ilvl or 0) then
                if (i.ilvl or 0) > (best.ilvl or 0) then best = i end
            elseif (i.quality or 0) ~= (best.quality or 0) then
                if (i.quality or 0) > (best.quality or 0) then best = i end
            elseif i.id < best.id then
                best = i
            end
        end
    end
    return best and best.id or nil
end

-- The poles in the bags
function lib.Poles()
    local out, seen = {}, {}
    local C = type(C_Container) == "table" and C_Container or {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, tonumber((Call(C.GetContainerNumSlots, bag))) or 0 do
            local info = Call(C.GetContainerItemInfo, bag, slot)
            local id = info and tonumber(info.itemID)
            if id and not seen[id] and lib.IsPoleItem(id) then
                seen[id] = true
                local _, _, quality, ilvl, reqLevel = Call(Item().GetItemInfo or GetItemInfo, id)
                out[#out + 1] = { id = id, quality = quality, ilvl = ilvl, reqLevel = reqLevel,
                    usable = Call(Item().IsUsableItem, id) and true or false }
            end
        end
    end
    return out
end

function lib.BestPole()
    return lib.Best(lib.Poles(), tonumber((Call(UnitLevel, "player"))))
end

---------------------------------------------------------------------------
-- The weapons to go back to: the hands as they were before the pole, kept
-- in each host's per-character settings (either addon alone remembers)
---------------------------------------------------------------------------
-- A host's table to keep them in (its per-character saved settings)
function lib.Attach(store)
    if type(store) ~= "table" then return end
    for _, s in ipairs(lib.stores) do if s == store then return end end
    lib.stores[#lib.stores + 1] = store
end

-- { [16] = id, [17] = id or nil } or nil
function lib.Weapons()
    for _, s in ipairs(lib.stores) do
        local w = s.fishingWeapons
        if type(w) == "table" and (w[MAIN] or w[OFF]) then return w end
    end
    return lib.memory
end

-- The hands now, when they hold no pole: what to go back to
function lib.Remember()
    local main, off = Equipped(MAIN), Equipped(OFF)
    if lib.IsPoleItem(main) then return false end
    if not (main or off) then return false end      -- (empty hands: keep the last weapons)
    local w = { [MAIN] = main, [OFF] = off }
    lib.memory = w
    for _, s in ipairs(lib.stores) do s.fishingWeapons = { [MAIN] = main, [OFF] = off } end
    return true
end

--[[ The swap's macro text. pole: the pole's name (nil: none in the bags); weapons: { [16] =
name, [17] = name }; poleType: "Fishing Poles". A pole in hand: back to the weapons; none: the
pole on. A note line (nothing to swap to) when it fits a bar slot's macro. nil: nothing to do. ]]
function lib.MacroText(pole, weapons, poleType, note)
    poleType = poleType or "Fishing Poles"
    local lines = {}
    if pole then lines[#lines + 1] = ("/equip [noequipped:%s] %s"):format(poleType, pole) end
    for _, slot in ipairs({ MAIN, OFF }) do
        local name = weapons and weapons[slot]
        if name then lines[#lines + 1] = ("/equipslot [equipped:%s] %d %s"):format(poleType, slot, name) end
    end
    if note then
        local with = table.concat(lines, "\n") .. (#lines > 0 and "\n" or "") .. note
        if #with <= lib.MACRO_MAX then lines[#lines + 1] = note end
    end
    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

-- The macro for now (out of combat: the bags and hands are read)
function lib.Macro()
    lib.Remember()
    local w = lib.Weapons()
    local names = w and { [MAIN] = Name(w[MAIN]), [OFF] = Name(w[OFF]) } or nil
    -- (a two-hander: nothing for the off hand)
    return lib.MacroText(Name(lib.BestPole()), names, lib.PoleType(), "/run MimezuFishing.Note()")
end

-- After a press: a calm word when there was nothing to swap to
function lib.Note()
    local text
    if lib.PoleEquipped() then
        local w = lib.Weapons()
        if not (w and (Name(w[MAIN]) or Name(w[OFF]))) then text = "No weapons to go back to" end
    elseif not lib.BestPole() then
        text = "No fishing pole in your bags"
    end
    if text and UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(text, 1, 0.82, 0, 1, 2)
    end
    return text
end

-- What a button shows: name, icon (the pole to take, or the weapons to go back to)
function lib.Look()
    if lib.PoleEquipped() then
        local w = lib.Weapons()
        local id = w and (w[MAIN] or w[OFF])
        return "Back to weapons", Icon(id) or lib.WEAPONS_ICON
    end
    local pole = lib.BestPole()
    if not pole then return "No fishing pole", lib.ICON end
    return Name(pole) or "Fishing pole", Icon(pole) or lib.ICON
end
