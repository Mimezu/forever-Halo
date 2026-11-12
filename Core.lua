-- Halo: small radial menus for Forever.
-- Core: saved settings, a tiny event bus, combat-safe work queue, slash command.

local ADDON, H = ...
Halo = H

H.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.9.27"
H.MAX_SLICES = 12

local DEFAULT_OPTIONS = {
    openAt = "cursor",      -- "cursor" or "center" (the gamepad interface always uses the centre)
    scale = 1,
    labels = true,          -- name of the pointed slice under the ring
    background = true,      -- the style's backdrop behind the slots
    style = "A",            -- default ring style (Skins.lua); rings may choose their own
    runeColor = "blue",     -- Runes style: "blue" (the art), "class" or "custom"
    runeCustom = { 0.7, 0.4, 1 },
    sounds = true,
    numberKeys = true,      -- 1-9 / 0 use a slice while a ring is open
    stick = "right",        -- gamepad stick that points
    holdCamera = true,      -- the pointing stick does not turn the camera while a ring is open
    padMode = "hold",       -- gamepad ring button: "hold" (use on release) or "tap" (tap again to use)
    blockSticks = false,    -- fallback: both sticks go to the ring while it is open (walking pauses)
    padRelease = "keep",    -- gamepad, letting go of the stick: "keep" (the slice stays selected) or "use"
    padPos = { 0.78, 0.42 },  -- gamepad interface: ring centre as a fraction of the screen (right side)
    centerPos = { 0.5, 0.5 }, -- "Fixed position" mode for keyboard and mouse
}

-- Starter rings. No keys are assigned: Halo never takes a key without asking.
local function StarterRings()
    return {
        { id = 1, name = "Supplies", hideMissing = true, slices = {
            { kind = "auto", source = "potions" },
            { kind = "auto", source = "food" },
            { kind = "auto", source = "bandages" },
            { kind = "item", itemID = 6948 },            -- Hearthstone
        } },
        { id = 2, name = "Travel", hideMissing = true, slices = {
            { kind = "auto", source = "mounts" },
        } },
        { id = 3, name = "Emotes", hideMissing = true, slices = {
            { kind = "emote", token = "wave" }, { kind = "emote", token = "bow" },
            { kind = "emote", token = "cheer" }, { kind = "emote", token = "dance" },
            { kind = "emote", token = "sit" }, { kind = "emote", token = "laugh" },
            { kind = "emote", token = "thank" }, { kind = "emote", token = "salute" },
        } },
    }
end

-- Event bus ---------------------------------------------------------------------------------
local listeners = {}
function H.On(kind, fn)
    listeners[kind] = listeners[kind] or {}
    table.insert(listeners[kind], fn)
end
-- Errors also go to chat (once per message): many players run with Lua errors hidden.
local reported = {}
function H.ReportError(err)
    err = tostring(err)
    if not reported[err] then
        reported[err] = true
        print("|cffe8c070Halo|r |cffff6040error:|r " .. err)
    end
    geterrorhandler()(err)
end
local NONE = {}
function H.Fire(kind, ...)
    for _, fn in ipairs(listeners[kind] or NONE) do
        local ok, err = pcall(fn, ...)
        if not ok then H.ReportError(err) end
    end
end

-- Out-of-combat work queue: named jobs run once when combat ends.
local pending = {}
function H.OutOfCombat(name, fn)
    if not InCombatLockdown() then fn(); return true end
    pending[name] = fn
    return false
end

function H.Print(...)
    print("|cffe8c070Halo|r", ...)
end

function H.CharacterKey()
    local name, realm = UnitFullName("player")
    return (name or "?") .. "-" .. (realm or GetRealmName() or "?")
end

-- Settings ----------------------------------------------------------------------------------
local function Migrate(db)
    local fresh = type(db.rings) ~= "table"
    db.version = 1
    db.options = type(db.options) == "table" and db.options or {}
    -- Help under an open ring: on for new players, off for anyone who already uses Halo.
    if db.options.hints == nil then db.options.hints = fresh end
    -- 0.9.14: the name in the middle of the ring is the only way now (was the option centerLabel).
    db.options.centerLabel = nil
    -- (0.6.9 gamepad combinations were cleared here until 0.9.27; "A+B" is a chord ring now.)
    -- Old "Ring height" (0.x): the gamepad ring used to sit at the centre, shifted up/down.
    if db.options.padCenterY ~= nil then
        if tonumber(db.options.padCenterY) and db.options.padCenterY ~= 0 then
            db.options.padPos = { 0.5, 0.5 + db.options.padCenterY }
        end
        db.options.padCenterY = nil
    end
    -- Small slice numbers: same rule (the player who asked for the toggle wanted them off).
    if db.options.slotNumbers == nil then db.options.slotNumbers = fresh end
    -- 0.9.x "Keep the selection" checkbox became the "Stick released" choice.
    if db.options.padSticky ~= nil then
        if db.options.padSticky == true and db.options.padRelease == nil then db.options.padRelease = "keep" end
        db.options.padSticky = nil
    end
    -- 0.9.15: "Stick released: Nothing" is gone (it did not work in combat); it becomes Keep.
    if db.options.padRelease == "none" then db.options.padRelease = "keep" end
    -- 0.9.20: the player's own stick-direction setting is no longer recorded (nothing has
    -- restored it since 0.9.15; the setting stays on while Halo is loaded).
    db.stickButtonsSaved = nil
    for k, v in pairs(DEFAULT_OPTIONS) do
        -- Positions and colours are tables: copy them, so the defaults are never shared.
        if db.options[k] == nil then db.options[k] = type(v) == "table" and { unpack(v) } or v end
    end
    if type(db.rings) ~= "table" then db.rings = StarterRings() end
    local maxId = 0
    for _, ring in ipairs(db.rings) do
        ring.slices = type(ring.slices) == "table" and ring.slices or {}
        ring.name = type(ring.name) == "string" and ring.name or "Ring"
        if ring.hideMissing == nil then ring.hideMissing = true end
        maxId = math.max(maxId, tonumber(ring.id) or 0)
    end
    for _, ring in ipairs(db.rings) do
        if not tonumber(ring.id) then maxId = maxId + 1; ring.id = maxId end
    end
    db.nextId = math.max(tonumber(db.nextId) or 1, maxId + 1)
    db.window = type(db.window) == "table" and db.window or {}
    -- Rings tab folders the player opened or closed by hand (true = closed).
    db.window.folders = type(db.window.folders) == "table" and db.window.folders or {}
    return db
end

function H.Option(key) return H.db.options[key] end

-- Gamepad, letting go of the pointing stick: "keep" or "use".
function H.StickRelease()
    local mode = H.db and H.db.options.padRelease
    return mode == "use" and "use" or "keep"
end
function H.SetOption(key, value)
    H.db.options[key] = value
    H.Fire("options", key)
end

function H.GetRing(id)
    for index, ring in ipairs(H.db.rings) do
        if ring.id == id then return ring, index end
    end
end

-- A ring is active on this character unless it belongs to another one.
function H.RingActiveHere(ring)
    return not ring.owner or ring.owner == H.CharacterKey()
end

-- "PALADIN" and so on, for the class colour of a character's folder.
function H.CharacterClass()
    if not UnitClass then return nil end
    local _, class = UnitClass("player")
    return class
end

function H.OwnerName(owner)
    return owner and (owner:match("^([^%-]+)") or owner) or nil
end

-- The character's name as the game shows it, surname included ("Neige Blanche"). UnitName
-- alone leaves the surname out; Forever's GetUnitName(unit, true) adds it.
function H.CharacterFullName()
    if GetUnitName then
        local ok, name = pcall(GetUnitName, "player", true)
        if ok and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
            return (name:gsub("%-.*$", ""))
        end
    end
    return H.OwnerName(H.CharacterKey())
end

-- Who a ring belongs to: a character key ("Name-Realm"), or nil for every character. The
-- owner's class and full name are kept so the Rings tab can show their folder from other
-- characters.
function H.SetRingOwner(ring, owner)
    ring.owner = owner
    if owner == nil then
        ring.ownerClass, ring.ownerFull = nil, nil
    elseif owner == H.CharacterKey() then
        ring.ownerClass, ring.ownerFull = H.CharacterClass(), H.CharacterFullName()
    end
end

-- The name to show for a ring's owner.
function H.RingOwnerName(ring)
    return ring.ownerFull or H.OwnerName(ring.owner)
end

-- Rings made before the class and full name were kept get them the next time their owner
-- logs in.
H.On("login", function()
    local key, class, full = H.CharacterKey(), H.CharacterClass(), H.CharacterFullName()
    for _, ring in ipairs(H.db.rings) do
        if ring.owner == key then
            if ring.ownerClass ~= class then ring.ownerClass = class end
            if ring.ownerFull ~= full then ring.ownerFull = full end
        end
    end
end)

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = DeepCopy(v) end
    return copy
end

-- Is this key or button unavailable to a ring on this character? Another Halo ring active
-- here has it, or something outside Halo (another addon) holds it. Blizzard's own gamepad
-- bindings are not a conflict: Halo's override wins over them.
local function KeyConflict(key)
    if not key then return nil end
    for _, other in ipairs(H.db.rings) do
        if H.RingActiveHere(other) and (other.key == key or other.padKey == key) then
            return "Halo ring " .. other.name
        end
    end
    return H.KeyTakenBy and H.KeyTakenBy(key, -1) or nil
end

-- Copies a ring (any character's) to `owner` (a character key, or nil for everyone). The
-- copy keeps the key and gamepad button unless something here already uses them. Nested
-- rings that the new owner could not see are left out. Returns the copy and a list of
-- sentences describing what was dropped.
function H.CopyRing(id, owner)
    local source = H.GetRing(id)
    if not source then return nil end
    local copy = DeepCopy(source)
    copy.id = H.db.nextId
    H.db.nextId = H.db.nextId + 1
    copy.owner, copy.ownerClass, copy.ownerFull, copy.key, copy.padKey = nil, nil, nil, nil, nil
    H.SetRingOwner(copy, owner)
    local notes = {}
    local function Seen(candidate)
        for _, ring in ipairs(H.db.rings) do
            if ring.name == candidate and (not ring.owner or ring.owner == owner) then return true end
        end
    end
    local name, n = source.name, 1
    if Seen(name) then
        name = source.name .. " copy"
        while Seen(name) do n = n + 1; name = source.name .. " copy " .. n end
    end
    copy.name = name
    for _, field in ipairs({ "key", "padKey" }) do
        local value = source[field]
        if value then
            local taken = KeyConflict(value)
            if taken then
                notes[#notes + 1] = ("%s taken by %s: copy has no %s"):format(
                    value, taken, field == "key" and "key" or "gamepad button")
            else
                copy[field] = value
            end
        end
    end
    local dropped = 0
    for i = #copy.slices, 1, -1 do
        local slice = copy.slices[i]
        if slice.kind == "ring" then
            local target = H.GetRing(slice.ringID)
            if not target or (target.owner and target.owner ~= owner) then
                table.remove(copy.slices, i)
                dropped = dropped + 1
            end
        end
    end
    if dropped > 0 then
        notes[#notes + 1] = ("%d nested %s of another character left out"):format(
            dropped, dropped == 1 and "ring" or "rings")
    end
    table.insert(H.db.rings, copy)
    H.Changed("rings")
    return copy, notes
end

function H.NewRing(name)
    local ring = { id = H.db.nextId, name = name or "New ring", hideMissing = true, slices = {} }
    H.db.nextId = H.db.nextId + 1
    table.insert(H.db.rings, ring)
    H.Changed("rings")
    return ring
end

function H.DeleteRing(id)
    local _, index = H.GetRing(id)
    if not index then return end
    table.remove(H.db.rings, index)
    -- Nested slices that pointed at it would open nothing; drop them.
    for _, ring in ipairs(H.db.rings) do
        for i = #ring.slices, 1, -1 do
            local s = ring.slices[i]
            if s.kind == "ring" and s.ringID == id then table.remove(ring.slices, i) end
        end
    end
    H.Changed("rings")
end

-- Something in the ring data changed: rebuild the secure rings when allowed.
function H.Changed(what)
    H.Fire("changed", what)
    H.RequestCompile()
end

-- Every build attempt is recorded for /halo status.
H.compileInfo = { runs = 0, ok = 0 }
function H.RunCompile()
    if not H.Compile then H.compileInfo.lastError = "Secure.lua did not load"; return false end
    H.compileInfo.runs = H.compileInfo.runs + 1
    local ok, err = xpcall(H.Compile, function(e) return tostring(e) .. " | " .. (debugstack and debugstack(2, 6, 0) or "") end)
    if ok then
        H.compileInfo.ok = H.compileInfo.ok + 1
        H.compileInfo.lastError = nil
    else
        H.compileInfo.lastError = err
        H.ReportError(err)
    end
    return ok
end

-- Compile throttle: many bag/spell events arrive in bursts.
local compileQueued = false
function H.RequestCompile()
    if compileQueued then return end
    compileQueued = true
    C_Timer.After(0.2, function()
        compileQueued = false
        H.OutOfCombat("compile", function()
            if not H.Compile then return end
            H.RunCompile()
        end)
    end)
end

-- Events ------------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        HaloDB = Migrate(type(HaloDB) == "table" and HaloDB or {})
        H.db = HaloDB
        H.debug = H.db.debug == true   -- stays on across /reload until /halo debug turns it off
    elseif event == "PLAYER_LOGIN" then
        if H.debug then H.Log("login / reload (debug on) | Halo " .. tostring(H.version)) end
        H.Fire("login")
        if H.migrationNote then H.Print(H.migrationNote); H.migrationNote = nil end
        if not H.db.welcomed then
            H.db.welcomed = true
            H.Print("/halo to set up rings")
        end
        H.RequestCompile()
    elseif event == "PLAYER_REGEN_ENABLED" then
        local jobs = pending
        pending = {}
        for _, fn in pairs(jobs) do
            local ok, err = pcall(fn)
            if not ok then H.ReportError(err) end
        end
    end
end)

-- Contents that decide which slices exist (items in bags, known spells, collections).
local contentEvents = CreateFrame("Frame")
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
    "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED", "PET_JOURNAL_LIST_UPDATE",
    "EQUIPMENT_SETS_CHANGED", "UPDATE_MACROS", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
    pcall(contentEvents.RegisterEvent, contentEvents, event)
end
contentEvents:SetScript("OnEvent", function()
    if H.db then H.RequestCompile() end
end)

-- Slash -------------------------------------------------------------------------------------
SLASH_HALO1 = "/halo"
SlashCmdList.HALO = function(message)
    message = strtrim(message or ""):lower()
    if message == "debug" then
        H.debug = not H.debug
        H.db.debug = H.debug or nil
        H.Print("debug", H.debug and "on (log saved on /reload)" or "off")
        if H.debug then H.db.debugLog = {}; H.Log("debug on") end
    elseif message == "reset" then
        H.Print("/halo reset yes deletes all rings and options")
    elseif message == "reset yes" then
        local old = H.db
        HaloDB = Migrate({})
        H.db = HaloDB
        -- Keep the debug setting and log.
        H.db.debug, H.db.debugLog = old.debug, old.debugLog
        H.Changed("rings")
        H.Fire("options")
        H.Print("Reset")
    elseif message == "rebuild" then
        if InCombatLockdown() then H.Print("Not in combat"); return end
        local ok = H.RunCompile()
        H.Print(ok and "Rebuilt" or "Rebuild failed")
        if H.Status then H.Status() end
    elseif message == "camstate" then
        if H.CameraState then H.CameraState() end
    elseif message == "textures" then
        if H.DumpTextures then H.DumpTextures() end
    elseif message == "layout a" or message == "layout b" then
        if H.SetOptionsLayout then H.SetOptionsLayout(message:sub(-1)) end
        H.Print("Layout " .. message:sub(-1):upper())
    elseif message == "status" then
        if H.Status then H.Status() end
    else
        if H.ToggleOptions then H.ToggleOptions() end
    end
end

-- Debug log kept in HaloDB.debugLog (written to disk on /reload), last 500 lines.
function H.Log(text)
    if not H.db then return end
    local log = H.db.debugLog
    if type(log) ~= "table" then log = {}; H.db.debugLog = log end
    log[#log + 1] = ("%s %.2f %s"):format(date("%H:%M:%S"), GetTime(), tostring(text))
    while #log > 500 do table.remove(log, 1) end
end
