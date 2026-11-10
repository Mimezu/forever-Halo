-- Run from the addon folder: lua5.1 tests/Smoke.lua
-- Loads every file against a mocked Forever client, runs the secure snippets in an
-- emulated restricted environment, and checks the ring flows end to end.
local assertions = 0
local function check(value, message) assertions = assertions + 1; if not value then error(message, 2) end end

-- Basics ---------------------------------------------------------------------------------------
local now, timers = 1000, {}
function GetTime() return now end
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end }
local function advance(seconds)
    now = now + seconds
    local ran = true
    while ran do
        ran = false
        for i, t in ipairs(timers) do
            if t.at <= now then table.remove(timers, i); t.fn(); ran = true; break end
        end
    end
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
strmatch = string.match
function geterrorhandler() return function(e) error(e) end end
function hooksecurefunc(target, name, hook)
    if type(target) ~= "string" then return end        -- frame methods: not needed here
    local original = _G[target]
    _G[target] = function(...)
        local a, b, c, d = original(...)
        name(...)
        return a, b, c, d
    end
end
function PlaySound() end
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
local combat = false
function InCombatLockdown() return combat end
function UnitFullName() return "Mime", "Forever" end
function UnitClass() return "Mage", "MAGE" end
function GetUnitName(unit, showSurname) return showSurname and "Mime Blanche" or "Mime" end
function GetRealmName() return "Forever" end
function UnitExists() return true end
function GetCursorPosition() return cursorX or 500, cursorY or 400 end
local cvars = { GamePadEmulateShift = "PADLTRIGGER", GamePadEmulateCtrl = "NONE", GamePadEmulateAlt = "NONE",
    GamePadCameraYawSpeed = "2", GamePadCameraPitchSpeed = "1" }
function GetCVar(name) return cvars[name] end
function SetCVar(name, value) cvars[name] = tostring(value) end
function GetBindingText(k) return k end
function GetBindingAction() return "" end
function date() return "12:00:00" end
function IsAltKeyDown() end function IsControlKeyDown() end function IsShiftKeyDown() end
UISpecialFrames, UIErrorsFrame, SlashCmdList = {}, { AddMessage = function() end }, {}
Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
local padUI = false
C_InputInterfaceStyle = { GetCurrentStyle = function() return padUI and 1 or 0 end }
local stickState = { x = 0, y = 0, len = 0 }
padButtons = {}
C_GamePad = {
    IsEnabled = function() return true end,
    StickIndexToConfigName = function(i) return ({ [0] = "Movement", [1] = "Camera" })[i] end,
    GetDeviceMappedState = function() return { sticks = { { x = 0, y = 0, len = 0 }, stickState }, buttons = padButtons } end,
    ButtonBindingToIndex = function(name) return ({ PADRSHOULDER = 5, PADLSHOULDER = 4 })[name] end,
}
C_Texture = { GetAtlasInfo = function() return { width = 44, height = 44, file = 1, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end }
NineSliceUtil = { ApplyLayoutByName = function() end }

-- Game data: a mage who knows Frostbolt (116) and has 3 healing potions (118).
local known = { [116] = true }
local bags = { [0] = { { itemID = 118, quality = 1 }, { itemID = 2070, quality = 1 } } }
C_Spell = {
    GetSpellName = function(id) return ({ [116] = "Frostbolt", [133] = "Fireball" })[id] end,
    GetSpellInfo = function(id) local n = C_Spell.GetSpellName(id) or (id == "Frostbolt" and "Frostbolt"); return n and { name = n, iconID = 1, spellID = type(id) == "number" and id or 116 } end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
    GetSpellCharges = function() return nil end,
    IsSpellUsable = function() return true end,
    IsCurrentSpell = function() return false end,
}
function IsPlayerSpell(id) return known[id] == true end
C_Item = {
    GetItemNameByID = function(id) return "Item" .. id end,
    GetItemIconByID = function() return 2 end,
    GetItemCount = function(id) return id == 118 and 3 or (id == 2070 and 5 or 0) end,
    IsEquippedItem = function() return false end,
    IsUsableItem = function() return true end,
    GetItemMaxStackSizeByID = function() return 20 end,
    GetItemInfoInstant = function(id) if id == 118 then return id, nil, nil, nil, 1, 0, 1 elseif id == 2070 then return id, nil, nil, nil, 1, 0, 5 end end,
    GetItemSpell = function() return "Use" end,
    GetDetailedItemLevelInfo = function() return 5, false, 5 end, -- three returns, like the client
}
C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0, 0 end,
    GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] end,
    GetItemCooldown = function() return 0, 0, 1 end,
}
NUM_BAG_SLOTS = 4

-- Secure environment emulation ----------------------------------------------------------------
local restrictedEnv = {
    newtable = function(...) return { ... } end, wipe = wipe, strmatch = string.match,
    tonumber = tonumber, tostring = tostring, floor = math.floor, math = math, pairs = pairs,
    IsGamePadEnabled = function() return true end,
    GetGamePadState = function() return C_GamePad.GetDeviceMappedState() end,
}
local function Compile(signature, body)
    local fn, err = loadstring("return function(" .. signature .. ") " .. body .. "\nend")
    if not fn then error(err) end
    setfenv(fn, restrictedEnv)
    return fn()
end

local frames, overrides = {}, {}
local function Handle(frame)
    if rawget(frame, "_handle") then return frame._handle end
    frame._handle = setmetatable({}, { __index = function(_, k)
        local h = {
            Show = function() frame.shown = true end,
            Hide = function() frame.shown = false end,
            GetMousePosition = function()
                local x, y = GetCursorPosition()
                return x / 1000, y / 800
            end,
            GetRect = function() return 0, 0, 1000, 800 end,
            SetAttribute = function(_, name, value) frame.attributes[name] = value end,
            GetAttribute = function(_, name) return frame.attributes[name] end,
            GetFrameRef = function(_, name) return Handle(frame.refs[name]) end,
            ClearBindings = function() overrides[frame] = {} end,
            SetBindingClick = function(_, _, key, target, button)
                overrides[frame] = overrides[frame] or {}
                overrides[frame][key] = (type(target) == "table" and target.name or target) .. ":" .. tostring(button)
            end,
            CallMethod = function(_, method, ...) return frame[method](frame, ...) end,
            Run = function(_, body, ...) return Compile("self,...", body)(frame._handle, ...) end,
            RunFor = function(_, other, body, ...) return Compile("self,...", body)(other, ...) end,
        }
        return h[k]
    end })
    frame._handle.name = frame.name
    return frame._handle
end

-- Frame mock: unknown methods are no-ops; secure templates get the handle features.
local function Mock(name)
    local obj = { scripts = {}, attributes = {}, refs = {}, name = name, shown = true }
    local methods = {
        SetScript = function(self, event, fn) self.scripts[event] = fn end,
        GetScript = function(self, event) return self.scripts[event] end,
        HookScript = function(self, event, fn) self.scripts[event] = fn end,
        CreateTexture = function() return Mock() end,
        CreateFontString = function() return Mock() end,
        CreateMaskTexture = function() return Mock() end,
        IsShown = function(self) return self.shown end,
        Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end,
        Hide = function(self) self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end,
        SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
        GetText = function(self) return rawget(self, "text") or "" end,
        SetText = function(self, t) self.text = t end,
        GetChecked = function(self) return rawget(self, "checked") end,
        SetChecked = function(self, v) self.checked = v end,
        GetFontString = function(self) if not rawget(self, "fs") then rawset(self, "fs", Mock()) end return rawget(self, "fs") end,
        GetSize = function(self) return rawget(self, "w") or 100, rawget(self, "h") or 100 end,
        SetSize = function(self, w, h) self.w, self.h = w, h end,
        GetWidth = function(self) return rawget(self, "w") or 1000 end,
        GetHeight = function(self) return rawget(self, "h") or 800 end,
        GetEffectiveScale = function() return 1 end,
        GetScale = function() return 1 end,
        GetCenter = function() return 500, 400 end,
        GetFrameLevel = function() return 1 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        HasFocus = function() return false end,
        SetAttribute = function(self, k, v) self.attributes[k] = v end,
        GetAttribute = function(self, k) return self.attributes[k] end,
        SetFrameRef = function(self, k, f) self.refs[k] = f end,
        Execute = function(self, code)
            restrictedEnv.owner = Handle(self)
            Compile("self", code)(Handle(self))
        end,
        WrapScript = function(self, target, script, pre)
            target.pre = Compile("self,button,down", pre)
        end,
        IsEnabled = function() return true end,
        GetVerticalScrollRange = function() return 0 end,
        NumLines = function() return 1 end,
    }
    local fields = { Text = true, text = true, Left = true, Middle = true, Right = true, LeftSeparator = true,
        RightSeparator = true, SetUseCircularEdge = false, EnableGamePadButton = true,
        folderKey = true, ringID = true }   -- plain fields on the ring list's rows (nil until set)
    return setmetatable(obj, { __index = function(_, key)
        if fields[key] then return nil end
        return methods[key] or function() end
    end })
end
function CreateFrame(kind, name, parent, template)
    local frame = Mock(name)
    if name then _G[name] = frame end
    if kind == "CheckButton" then frame.Text = Mock() end
    frame.template = template
    frames[#frames + 1] = frame
    return frame
end
-- key -> owner of the most recent override and its action (the most recent one wins in game)
bindOrder, bindTop = {}, {}
function ClearOverrideBindings(owner)
    overrides[owner] = {}
    for key, o in pairs(bindOrder) do if o == owner then bindOrder[key], bindTop[key] = nil, nil end end
end
function SetOverrideBindingClick(owner, _, key, target, button)
    overrides[owner] = overrides[owner] or {}
    overrides[owner][key] = target .. ":" .. button
    bindOrder[key], bindTop[key] = owner, "CLICK " .. target .. ":" .. button
end
function SetOverrideBinding(owner, _, key, action)
    if action and action ~= "" then bindOrder[key], bindTop[key] = owner, action
    elseif bindOrder[key] == owner then bindOrder[key], bindTop[key] = nil, nil end   -- clearing removes its own
end
function GetBindingAction(key, checkOverride) return checkOverride and bindTop[key] or "" end
UIParent, WorldFrame = Mock("UIParent"), Mock("WorldFrame")
GameTooltip = Mock("GameTooltip")
Settings ={ RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }

-- Blizzard's gamepad stick listener (Blizzard_GamepadSharedUtility), as a plain table fake.
inputBindingAxisListener = { left = {}, right = {}, stickOn = false, shown = true,
    EnableGamePadStick = function(self, on) self.stickOn = on and true or false end,
    IsGamePadStickEnabled = function(self) return self.stickOn end,
    Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end }
local axisL = inputBindingAxisListener

-- Load ------------------------------------------------------------------------------------------
local before = {}
for k in pairs(_G) do before[k] = true end
local H = {}
local toc = io.open("Halo.toc"):read("*a")
for file in toc:gmatch("\n([%w_]+%.lua)") do
    local chunk = assert(loadfile(file))
    chunk("Halo", H)
end
check(#frames > 0, "files loaded")
local allowed = { Halo = true, SLASH_HALO1 = true, Halo_OpenOptions = true, HaloHeader = true, HaloButton = true,
    HaloKeys = true, HaloBindings = true, HaloRing = true, HaloStick = true, HaloStickCatcher = true }
for k in pairs(_G) do
    if not before[k] then check(allowed[k], "unexpected global: " .. tostring(k)) end
end

-- ADDON_LOADED + login. A save from before 0.9.20 still holds stickButtonsSaved.
local events
for _, f in ipairs(frames) do if f.scripts.OnEvent and not events then events = f end end
HaloDB = { stickButtonsSaved = "0" }
events.scripts.OnEvent(events, "ADDON_LOADED", "Halo")
check(H.db and #H.db.rings == 3, "starter rings")
check(H.db.stickButtonsSaved == nil, "the stale stickButtonsSaved key is cleared on load")
check(H.db.options.hints == true, "help on for a new install")
events.scripts.OnEvent(events, "PLAYER_LOGIN")
advance(1)

local header, button, keys, binds = HaloHeader, HaloButton, HaloKeys, HaloBindings
local env = restrictedEnv

-- Supplies ring: potions + food auto, bandages (none), hearthstone (none -> hidden).
local supplies = H.live[1]
check(#supplies == 2, "supplies expands to potion and food, hides missing: " .. #supplies)
check(supplies[1].itemID == 118 and supplies[2].itemID == 2070, "potion first, then food")
check(env.RINGS[1].n == 2, "secure ring 1 has 2 slices")
check(env.RINGS[1][1].attr.type == "item" and env.RINGS[1][1].attr.item == "item:118", "item attributes")
check(env.RINGS[3].n == 8, "emote ring")
check(env.RINGS[3][1].attr.macrotext == "/wave", "emote macro text")
check(next(overrides[binds]) == nil, "no keys bound by default")

-- A spell ring with a nested ring, bound to Q and a gamepad chord.
local spells = H.NewRing("Spells")
spells.key, spells.padKey = "SHIFT-Q", "PADDUP"
spells.slices = {
    { kind = "spell", spellID = 116 },
    { kind = "spell", spellID = 133 },      -- not known: hidden
    { kind = "ring", ringID = 1 },
    { kind = "text", text = "/say hi", label = "Hi" },
}
H.Changed("test")
advance(1)
local rid = spells.id
check(overrides[binds]["SHIFT-Q"] == "HaloButton:r" .. rid, "ring key bound")
check(overrides[binds]["PADDUP"] == "HaloButton:p" .. rid, "gamepad key bound (sends p<id>)")
local r = env.RINGS[rid]
check(r.n == 3, "unknown spell hidden: " .. r.n)
check(r[1].attr.spell == "Frostbolt", "spell by name (highest rank)")
check(r[2].ring == 1, "nested ring")
check(r[3].attr.macrotext == "/say hi", "custom macro")
check(r.mods[1] == "SHIFT-", "ring key modifiers kept for number keys")

local opened, closed, switched, stickied = {}, {}, {}, 0
H.On("open", function(id, x, y) opened[#opened + 1] = { id, x, y } end)
H.On("close", function(id, used) closed[#closed + 1] = { id, used } end)
H.On("switch", function(id, back) switched[#switched + 1] = { id, back } end)
H.On("sticky", function() stickied = stickied + 1 end)

local function click(name, down) return button.pre(Handle(button), name, down) end

-- 1. Hold, point right-ish (slice 2 of 3 at 120 degrees), release -> nested ring opens.
cursorX, cursorY = 500, 400
check(click("r" .. rid, true) == false, "key down only opens")
check(button.shown, "click catcher shown")
check(opened[1][1] == rid and math.abs(opened[1][2] - 0.5) < 1e-9, "opened at cursor")
check(overrides[keys]["ESCAPE"] == "HaloButton:close", "escape closes")
check(overrides[keys]["1"] == "HaloButton:s1" and overrides[keys]["SHIFT-1"] == "HaloButton:s1", "number keys")
check(overrides[keys]["PAD1"] == "HaloButton:use", "gamepad confirm")
for _, b in ipairs({ "PADLSHOULDER", "PADRSHOULDER", "PADRTRIGGER" }) do
    check(overrides[keys][b] == "HaloButton:use", "shoulder/trigger confirms: " .. b)
end
-- This ring opens on SHIFT-Q and LT is the emulated Shift: LT must stay free.
check(overrides[keys]["PADLTRIGGER"] == nil, "Shift trigger not taken by a Shift ring")
check(axisL.stickOn, "Blizzard listener switched on")
check(type(axisL.right.func) == "function" and axisL.right.func(0.5, 0.2) == nil, "tilted camera stick taken while open")
check(axisL.right.func(0, 0) == true, "the return to centre is let through (clean release)")
check(axisL.left.func == nil, "movement stick untouched (walking works)")
check(not HaloStickCatcher.shown, "walking works: sticks not blocked by default")
cursorX, cursorY = 500 + 100 * math.sin(math.rad(120)), 400 + 100 * math.cos(math.rad(120))
check(click("r" .. rid, false) == false, "release over nested ring does not cast")
check(switched[1] and switched[1][1] == 1, "switched to nested ring")
check(env.active == 1 and env.sticky, "nested ring is sticky")
-- Right click goes back.
click("RightButton", true)
check(env.active == rid and switched[2][2] == true, "back to parent")

-- 2. Left click on slice 1 (top) casts Frostbolt on mouse up.
cursorX, cursorY = 500, 480
check(click("LeftButton", true) == false, "mouse down does nothing")
check(click("LeftButton", false) == "LeftButton", "mouse up performs")
check(button.attributes.type == "spell" and button.attributes.spell == "Frostbolt", "attributes set for Frostbolt")
check(button.attributes.useOnKeyDown == false, "mouse: act on up")
check(not button.shown and closed[#closed][2] == 1, "closed after use with slice 1")

-- 3. Hold and release in the middle -> sticky; press 3 -> custom macro on key down.
cursorX, cursorY = 500, 400
click("r" .. rid, true)
check(click("r" .. rid, false) == false and env.sticky and stickied == 1, "release in the middle keeps it open")
check(click("s3", true) == "LeftButton", "number key performs on down")
check(button.attributes.macrotext == "/say hi" and button.attributes.spell == nil, "old attributes cleared")
check(button.attributes.useOnKeyDown == true, "key: act on down")

-- 3b. Left click in the middle closes a sticky ring.
cursorX, cursorY = 500, 400
click("r" .. rid, true); click("r" .. rid, false)
check(env.sticky, "sticky before middle click")
check(click("LeftButton", true) == false and env.active, "middle mouse down keeps it open")
check(click("LeftButton", false) == false and env.active == nil and not button.shown, "middle click closes")

-- 4. Sticky ring closes when its key is pressed again.
click("r" .. rid, true); click("r" .. rid, false)
check(env.sticky, "sticky again")
click("r" .. rid, true)
check(env.active == nil and not button.shown, "ring key toggles closed")
click("r" .. rid, false)
check(env.active == nil, "stray key up ignored")

-- 5. Gamepad: stick wins over the mouse; release casts the pointed slice.
padUI = true
H.Changed("pad"); advance(1)
check(env.OPT.padUI == true, "gamepad interface flag reaches the secure side")
cursorX, cursorY = 100, 100
click("r" .. rid, true)
check(math.abs(env.cx - 0.78) < 1e-9 and math.abs(env.cy - 0.42) < 1e-9, "gamepad opens at its own position (right side)")
stickState.x, stickState.y, stickState.len = 0, 1, 1  -- up -> slice 1
check(click("r" .. rid, false) == "LeftButton" and button.attributes.spell == "Frostbolt", "stick release casts")
-- Stick centred in gamepad UI -> sticky, then tilt + confirm.
stickState.x, stickState.y, stickState.len = 0, 0, 0
click("r" .. rid, true)
check(click("r" .. rid, false) == false and env.sticky, "centred stick keeps ring open")
stickState.x, stickState.y, stickState.len = -0.8, -0.5, 0.95 -- lower left: 3 slices -> slice 3 (240 deg)
check(click("use", true) == "LeftButton" and button.attributes.macrotext == "/say hi", "confirm uses stick slice")
stickState.len = 0
padUI = false
H.Changed("kbm"); advance(1)

-- Cooldown: the camera stays held while the stick is still tilted, then comes back.
local rel = H.cameraRelease
check(rel.shown and axisL.right.func ~= nil, "camera still held right after closing")
stickState.len = 0.8
rel.scripts.OnUpdate(rel, 0.2)
check(rel.shown and axisL.right.func ~= nil, "held while the stick is still tilted")
stickState.len = 0
rel.scripts.OnUpdate(rel, 0.02)
check(not HaloStickCatcher.shown, "stick catcher hidden once the stick is centred")
check(axisL.right.func == nil, "camera stick given back after the ring closes")
check(H.EmulatedModifier("PADLTRIGGER") == "SHIFT" and H.EmulatedModifier("PADDUP") == nil, "emulated modifier detection")
-- A ring opened with Shift (LT emulated as Shift) does not confirm on LT.
local shiftRing = { key = nil, padKey = "SHIFT-PADDUP" }
local list = table.concat(H.ConfirmButtons(shiftRing), " ")
check(not list:find("PADLTRIGGER") and list:find("PADRTRIGGER") and list:find("PAD1"), "Shift trigger kept free: " .. list)
check(not table.concat(H.ConfirmButtons({ padKey = "PADRSHOULDER" }), " "):find("PADRSHOULDER"), "ring key not a confirm")

-- Forever can report C_GamePad.IsEnabled() == false in the gamepad interface: still hold the camera.
C_GamePad.IsEnabled = function() return false end
padUI = true; H.Changed("padui"); advance(1)
click("r" .. rid, true)
check(axisL.right.func ~= nil, "camera held in the gamepad interface even if IsEnabled() is false")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
check(axisL.right.func == nil, "and given back")
-- Normal close gives the camera back at once; only a pad confirm (use) keeps a short cooldown.
click("r" .. rid, true)
check(axisL.right.func ~= nil, "held while open")
click("close", true)
check(axisL.right.func == nil and not H.cameraRelease.shown, "normal close: camera back at once")
stickState.x, stickState.y, stickState.len = 0, 1, 1
click("r" .. rid, true)
click("use", true)
check(axisL.right.func ~= nil and H.cameraRelease.shown, "confirm with L/R/A: short cooldown")
stickState.len = 0
H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 0.02)
check(axisL.right.func == nil, "cooldown ends once the stick is centred")
-- The game flips to gamepad cursor mode while the ring's click catcher is up: put it back.
local freelook, cursorMode = true, false
function IsGamePadFreelookEnabled() return freelook end
function IsGamePadCursorControlEnabled() return cursorMode end
function SetGamePadFreeLook(v) freelook = v end
function SetGamePadCursorControl(v) cursorMode = v end
click("r" .. rid, true)
freelook, cursorMode = false, true   -- what the game does when the catcher appears
click("close", true)
check(freelook == true and cursorMode == false, "free-look restored, cursor mode off after close")
-- Selecting with the stick still tilted (any close, not only L/R): held until centred.
stickState.x, stickState.y, stickState.len = 0, 1, 1
click("r" .. rid, true)
check(click("r" .. rid, false) == "LeftButton", "select by releasing the ring key")
check(axisL.right.func ~= nil and H.cameraRelease.shown, "camera still held while the stick is tilted")
stickState.len = 0
H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 0.02)
check(axisL.right.func == nil and not axisL.stickOn, "released (listener off) once the stick is centred")
-- Sticky selection (gamepad option, out of combat): a flick selects, the selection stays
-- after the stick is centred, and the secure side uses it.
local padUIBefore = padUI
cvars.GamePadStickAxisButtons = "0"
H.SetOption("padRelease", "keep"); H.SetOption("padMode", "tap"); advance(1); advance(1)
check(cvars.GamePadStickAxisButtons == "1", "sticky selection switches the stick direction buttons on")
padUI = true; H.Changed("sticky"); advance(1)
click("p" .. rid, true); click("p" .. rid, false)
stickState.x, stickState.y, stickState.len = 0, 1, 1           -- flick up: slice 1
HaloRing.scripts.OnUpdate(HaloRing, 0.02)
check(env.stickyPick == 1, "flick remembered on the secure side")
stickState.len = 0
HaloRing.scripts.OnUpdate(HaloRing, 0.02)
check(H.RingState.pick == 1, "selection still shown with the stick centred")
check(click("p" .. rid, true) == "LeftButton" and button.attributes.spell == "Frostbolt", "tap uses the kept selection")
click("p" .. rid, false)
check(env.stickyPick == nil, "kept selection cleared when the ring closes")
-- In combat: nothing is remembered (the secure side cannot be told), the stick is read live.
combat = true
click("p" .. rid, true); click("p" .. rid, false)
stickState.len = 1; HaloRing.scripts.OnUpdate(HaloRing, 0.02)
stickState.len = 0; HaloRing.scripts.OnUpdate(HaloRing, 0.02)
check(env.stickyPick == nil and H.RingState.pick == nil, "in combat: no kept selection")
check(click("p" .. rid, true) == false and env.active == nil, "in combat: centred stick uses nothing")
click("p" .. rid, false)
-- In combat the stick's direction keys (PADRSTICKUP...) come to Halo as "aim" and store the
-- selection securely; the ring shows it and a centred confirm uses it.
click("p" .. rid, true); click("p" .. rid, false)
check(overrides[keys]["PADRSTICKUP"] == "HaloButton:aimu" and overrides[keys]["PADRSTICKLEFT"] == "HaloButton:aiml",
    "stick direction keys bound while a sticky ring is open")
stickState.x, stickState.y, stickState.len = -0.8, -0.5, 0.95  -- lower left: slice 3 of 3
click("aiml", true)
check(env.stickyPick == 3, "in combat: aim stores the pointed slice securely")
stickState.len = 0
HaloRing.scripts.OnUpdate(HaloRing, 0.02)
check(H.RingState.pick == 3, "in combat: the ring shows the stored slice")
check(click("p" .. rid, true) == "LeftButton" and button.attributes.macrotext == "/say hi", "in combat: centred tap uses it")
click("p" .. rid, false)
check(click("aiml", false) == false, "Keep: letting go of the stick uses nothing")
check(overrides[keys]["PADRSTICKUP"] == nil, "direction keys given back when the ring closes")
combat = false; events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
-- Stick released: Use. Point, let go of the stick: the slice is used on the key release of the
-- last stick direction (a real key release, so it works in combat too).
H.SetOption("padRelease", "use"); H.Changed("release use"); advance(1); advance(1)
check(cvars.GamePadStickAxisButtons == "1", "Use keeps the stick direction buttons on")
click("p" .. rid, true); click("p" .. rid, false)
check(env.active == rid and overrides[keys]["PADRSTICKDOWN"] == "HaloButton:aimd", "ring open, stick directions bound")
-- Lower left: slice 3 of 3. On the diagonal two directions are held (down and left); when
-- the stick is let go the game sends only one of the two releases (seen in game, 0.9.5).
stickState.x, stickState.y, stickState.len = -0.8, -0.5, 0.95
check(click("aimd", true) == false and click("aiml", true) == false and env.active == rid, "pointing uses nothing yet")
check(env.stickyPick == 3, "pointed slice kept")
stickState.x, stickState.y, stickState.len = -0.45, -0.28, 0.53   -- on the way back to the middle
check(click("aimd", false) == "LeftButton" and button.attributes.macrotext == "/say hi" and env.active == nil,
    "one release on the way back uses the slice (the other release may never come)")
check(button.attributes.useOnKeyDown == false and H.RingState.used == 3, "used on the key release; the ring shows which")
check(click("aiml", false) == false, "a late second release does nothing")
-- Turning around the edge (the stick still fully out) is not a release.
click("p" .. rid, true); click("p" .. rid, false)
stickState.x, stickState.y, stickState.len = 0, 1.05, 1.05
click("aimu", true)
check(env.stickyPick == 1, "pointing up: slice 1")
stickState.x, stickState.y, stickState.len = -0.94, 0.53, 1.08
click("aiml", true)
stickState.x, stickState.y, stickState.len = -0.96, 0.3, 1.0
check(click("aimu", false) == false and env.active == rid, "turning around the edge uses nothing")
check(env.stickyPick == 3, "the pointed slice follows the turn")
stickState.x, stickState.y, stickState.len = -0.1, 0, 0.1
check(click("aiml", false) == "LeftButton" and button.attributes.macrotext == "/say hi" and env.active == nil,
    "then letting go uses it")
-- Seen in game (0.9.7): letting go of a diagonal near the edge of a direction's zone, the
-- one release comes early, with the stick still at 0.86. It counts as letting go.
click("p" .. rid, true); click("p" .. rid, false)
stickState.x, stickState.y, stickState.len = -0.9, -0.3, 0.95
click("aiml", true)
stickState.x, stickState.y, stickState.len = -0.75, -0.62, 0.97
click("aimd", true)
check(env.stickyPick == 3, "lower left: slice 3")
stickState.x, stickState.y, stickState.len = -0.69, -0.52, 0.86
check(click("aimd", false) == "LeftButton" and button.attributes.macrotext == "/say hi" and env.active == nil,
    "an early release (0.86) on the way back uses the slice")
-- Seen in game (0.9.7): the stick held still on a slice, right where a direction starts; the
-- game presses and releases that direction without the stick moving. That was the one
-- release, so it counts as letting go (the real let-go would send nothing).
click("p" .. rid, true); click("p" .. rid, false)
stickState.x, stickState.y, stickState.len = -0.2, -0.45, 0.49
click("aimd", true)
stickState.x, stickState.y, stickState.len = -0.51, -0.99, 1.12
click("aiml", true)
stickState.x, stickState.y, stickState.len = -0.5, -0.99, 1.11
check(click("aiml", false) == "LeftButton" and button.attributes.macrotext == "/say hi" and env.active == nil,
    "a direction flickering at the edge while the stick is held still uses the slice")
-- The stick swings through the middle: the game drops the first direction's release. The
-- other side's release then counts.
click("p" .. rid, true); click("p" .. rid, false)
stickState.x, stickState.y, stickState.len = 0, 1, 1
click("aimu", true)
stickState.x, stickState.y, stickState.len = 0, -0.3, 0.3
click("aimd", true)
check(env.active == rid and env.stickyPick == 3, "swung to the bottom: slice 3")
stickState.x, stickState.y, stickState.len = 0, -0.1, 0.1
check(click("aimd", false) == "LeftButton" and button.attributes.macrotext == "/say hi" and env.active == nil,
    "letting go after the swing uses the bottom slice")
-- A release without pointing while the ring was open (stick already tilted) uses nothing.
stickState.x, stickState.y, stickState.len = 0, 0, 0
click("p" .. rid, true); click("p" .. rid, false)
check(click("aimu", false) == false and env.active == rid, "a release with no pointing first uses nothing")
-- Cancel (B) before letting go closes without using anything.
stickState.x, stickState.y, stickState.len = 0, 1, 1
click("aimu", true)
click("back", true); click("back", false)
check(env.active == nil, "cancel closes")
stickState.x, stickState.y, stickState.len = 0, 0, 0
check(click("aimu", false) == false, "the release after a cancel uses nothing")
-- Use + Tap: the ring's button again cancels (letting go of the stick is what uses).
click("p" .. rid, true); click("p" .. rid, false)
stickState.x, stickState.y, stickState.len = 0, 1, 1
click("aimu", true)
check(click("p" .. rid, true) == false and env.active == nil, "Use: the ring's button again closes without using")
click("p" .. rid, false)
stickState.x, stickState.y, stickState.len = 0, 0, 0
check(click("aimu", false) == false, "letting go after that uses nothing")
-- A nested ring slice opens that ring; it needs its own point and release.
click("p" .. rid, true); click("p" .. rid, false)
stickState.x, stickState.y, stickState.len = 0.9, -0.4, 0.98     -- lower right: slice 2, the nested ring
click("aimr", true)
check(env.stickyPick == 2, "nested ring slice pointed")
stickState.x, stickState.y, stickState.len = 0.2, -0.1, 0.22
check(click("aimr", false) == false and env.active == 1, "letting go on a nested ring slice opens it")
check(click("aimu", false) == false and env.active == 1, "no use until the nested ring is pointed at")
click("close", true)
-- Out of combat too.
combat = false; events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
click("p" .. rid, true); click("p" .. rid, false)
stickState.x, stickState.y, stickState.len = 0, 1, 1
click("aimu", true)
stickState.x, stickState.y, stickState.len = 0, 0.3, 0.3
check(click("aimu", false) == "LeftButton" and button.attributes.spell == "Frostbolt", "out of combat: release uses slice 1")
-- A light flick (the game presses the direction key at a small tilt) still counts.
click("p" .. rid, true); click("p" .. rid, false)
stickState.x, stickState.y, stickState.len = 0, 0.15, 0.15
click("aimu", true)
stickState.x, stickState.y, stickState.len = 0, 0.1, 0.1
check(click("aimu", false) == "LeftButton" and button.attributes.spell == "Frostbolt", "a light flick still uses the slice")
stickState.x, stickState.y, stickState.len = 0, 0, 0
H.SetOption("padMode", "hold"); padUI = padUIBefore; H.Changed("sticky off"); advance(1); advance(1)
check(cvars.GamePadStickAxisButtons == "1" and H.db.stickButtonsSaved == nil, "the stick direction buttons stay on (Keep is the base); nothing is recorded")

-- The listener is on only while a ring is open: switching it on freezes the camera for a few
-- seconds, so Halo never switches it on between rings.
click("r" .. rid, true)
check(axisL.stickOn, "listener on while a ring is open")
click("close", true)
check(not axisL.stickOn, "listener off after the ring closes")
advance(5); H.Changed("idle"); advance(1)
check(not axisL.stickOn, "and stays off between rings (no re-enable, no rebuild re-enable)")
-- Blizzard is using the camera stick (its radial or a flyout): Halo leaves it alone.
local blizzardFunc = function() end
axisL.right.func = blizzardFunc
click("r" .. rid, true)
check(axisL.right.func == blizzardFunc, "Blizzard's own camera-stick function is never replaced")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
check(axisL.right.func == blizzardFunc, "and not cleared on close")
axisL.right.func = nil
-- In combat the game blocks switching the listener on: the ring opens, the camera is not held.
axisL.stickOn = false; combat = true
click("r" .. rid, true)
check(not HaloStickCatcher.shown and axisL.right.func == nil and not axisL.stickOn, "in combat: camera not held, nothing blocked")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
combat = false; events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED"); advance(1)
check(not axisL.stickOn, "listener not switched on after combat either")
C_GamePad.IsEnabled = function() return true end

-- Fights: at the start (just before the lockdown) the listener is switched on and hidden, so a
-- ring can show it in combat. Hidden, it changes nothing for the camera or walking.
local fight, watch = H.fightEvents, H.cameraWatch
check(axisL.shown and not axisL.stickOn, "listener shown and off before the fight")
fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED"); combat = true
check(axisL.stickOn and not axisL.shown, "fight start: listener switched on and hidden")
check(axisL.right.func == nil and axisL.left.func == nil, "fight start: no stick taken")
watch.scripts.OnUpdate(watch, 0.02)
check(axisL.stickOn and not axisL.shown and H.db.hiddenAxisReceives == nil, "stays on and hidden between rings")
click("r" .. rid, true)
check(axisL.shown and type(axisL.right.func) == "function" and axisL.right.func(0.6, 0.1) == nil,
    "ring in combat: listener shown, camera stick taken")
check(axisL.left.func == nil, "ring in combat: walking untouched")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
check(axisL.right.func == nil and not axisL.shown and axisL.stickOn,
    "closed in combat: hidden again (camera back), still on for the next ring")
-- The cooldown (stick still tilted when the ring closes) also ends hidden.
click("r" .. rid, true)
stickState.x, stickState.y, stickState.len = 0.7, 0, 0.7
click("close", true)
check(env.active == nil and axisL.shown and axisL.right.func ~= nil and H.cameraRelease.shown,
    "combat: held while the stick is still tilted")
stickState.x, stickState.y, stickState.len = 0, 0, 0
H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 0.02)
check(axisL.right.func == nil and not axisL.shown and axisL.stickOn, "then hidden once the stick is centred")
-- Blizzard's gamepad UI uses the listener in the fight: shown again, never hidden under it.
local blizz = function() end
axisL.right.func = blizz
watch.scripts.OnUpdate(watch, 0.02)
check(axisL.shown, "Blizzard uses it: shown again")
click("r" .. rid, true)
check(axisL.right.func == blizz, "Blizzard's function is not replaced in combat")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
check(axisL.right.func == blizz and axisL.shown, "and the listener is left shown")
-- Blizzard is done and switches it off: no hold for the rest of the fight, nothing hidden.
axisL.right.func = nil; axisL.stickOn = false
click("r" .. rid, true)
check(axisL.right.func == nil and axisL.shown and not axisL.stickOn, "switched off by Blizzard: ring opens, camera not held")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
check(not axisL.stickOn and axisL.shown, "fight end: off and shown")
-- Switched off by Blizzard while hidden: shown again at once.
fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED"); combat = true
axisL.stickOn = false
watch.scripts.OnUpdate(watch, 0.02)
check(axisL.shown, "switched off while hidden: shown again")
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
-- A ring open when the fight starts: closing it in combat hides the listener; the fight end
-- switches it off.
click("r" .. rid, true)
check(axisL.stickOn and axisL.shown, "ring open out of combat: listener on")
fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED"); combat = true
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
check(axisL.stickOn and not axisL.shown and axisL.right.func == nil, "ring open at fight start, closed in combat: hidden, still on")
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
check(not axisL.stickOn and axisL.shown, "switched off and shown after the fight")
-- Fight end while a ring is open: the ring's close switches it off (out of combat by then).
fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED"); combat = true
click("r" .. rid, true)
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
check(axisL.stickOn and axisL.shown and axisL.right.func ~= nil, "fight ends with a ring open: still held")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
check(not axisL.stickOn and axisL.shown and axisL.right.func == nil, "then switched off when it closes")
-- Too late (the lockdown already started): nothing is switched on.
combat = true; fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED")
check(not axisL.stickOn and axisL.shown, "fight start already locked: nothing switched on")
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
-- Camera option off: nothing for fights either.
H.SetOption("holdCamera", false)
fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED"); combat = true
check(not axisL.stickOn and axisL.shown, "camera option off: nothing switched on for fights")
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
H.SetOption("holdCamera", true)
-- If a hidden listener still gets stick input (its centred flag follows the stick), the combat
-- hold turns itself off for good.
fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED"); combat = true
axisL.right.isCentered = not axisL.right.isCentered
watch.scripts.OnUpdate(watch, 0.02)
check(H.db.hiddenAxisReceives == true, "hidden listener that still gets stick input: combat hold turned off")
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
check(not axisL.stickOn and axisL.shown, "switched off after that fight")
fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED"); combat = true
check(not axisL.stickOn and axisL.shown, "and not switched on in later fights")
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
-- Even then, a ring open when a fight starts is cleaned up after the fight.
click("r" .. rid, true)
fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED"); combat = true
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
check(not axisL.stickOn and axisL.shown, "leftover from a ring open at fight start: off and shown after the fight")
H.db.hiddenAxisReceives = nil; axisL.right.isCentered = nil
-- A protected listener could not be shown or hidden in combat: not used for fights.
axisL.IsProtected = function() return true end
fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED"); combat = true
check(not axisL.stickOn and axisL.shown, "protected listener: nothing switched on for fights")
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
axisL.IsProtected = nil
-- Pointing with the left stick: the option holds the walking stick, the camera stick stays free.
H.SetOption("stick", "left"); advance(1)
check(H.stickName == "Movement", "left stick chosen")
click("r" .. rid, true)
check(type(axisL.left.func) == "function" and axisL.left.func(0.6, 0.1) == nil and axisL.left.func(0, 0) == true,
    "left stick: walking stick taken, its return to centre passes")
check(axisL.right.func == nil, "left stick: camera stick untouched")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
check(axisL.left.func == nil and axisL.right.func == nil and not axisL.stickOn, "left stick: released and switched off on close")
-- Blizzard's own walking-stick function is left alone.
local blizzLeft = function() end
axisL.left.func = blizzLeft
click("r" .. rid, true)
check(axisL.left.func == blizzLeft, "left stick: Blizzard's function is never replaced")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
check(axisL.left.func == blizzLeft, "and not cleared on close")
axisL.left.func = nil
-- Fights: the listener is switched on hidden for the left stick too.
fight.scripts.OnEvent(fight, "PLAYER_REGEN_DISABLED"); combat = true
check(axisL.stickOn and not axisL.shown, "left stick: fight start switches the listener on, hidden")
click("r" .. rid, true)
check(axisL.shown and type(axisL.left.func) == "function" and axisL.right.func == nil, "left stick: held in combat")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
check(axisL.left.func == nil and not axisL.shown and axisL.stickOn, "left stick: hidden again on close in combat")
combat = false; fight.scripts.OnEvent(fight, "PLAYER_REGEN_ENABLED")
check(not axisL.stickOn and axisL.shown, "left stick: off and shown after the fight")
-- Option off: the left stick is not touched.
H.SetOption("holdCamera", false)
click("r" .. rid, true)
check(axisL.left.func == nil and axisL.right.func == nil, "left stick, option off: nothing taken")
click("close", true); H.cameraRelease.scripts.OnUpdate(H.cameraRelease, 1)
H.SetOption("holdCamera", true)
H.SetOption("stick", "right"); advance(1)
-- The help under Options describes only the active settings.
do
    local function help(o)
        for k, v in pairs(o) do H.SetOption(k, v) end
        return H.HelpText()
    end
    local t = help({ openAt = "cursor", numberKeys = true, padMode = "hold", padRelease = "keep", stick = "right", holdCamera = true, blockSticks = false })
    check(t:find("or press 1-9, 0", 1, true) and t:find("Hold the button", 1, true)
        and t:find("right stick", 1, true) and t:find("The stick keeps the pick", 1, true) and t:find("Let go of the button to use it", 1, true)
        and t:find("The camera stays still", 1, true), "help: hold, keep, right stick, camera")
    t = help({ openAt = "center", numberKeys = false, padMode = "tap", padRelease = "use", stick = "left" })
    check(not t:find("1-9", 1, true) and t:find("Tap the button", 1, true)
        and t:find("left stick", 1, true) and t:find("Let go of the stick to use it", 1, true)
        and t:find("Walking stops", 1, true) and not t:find("camera stays still", 1, true), "help: tap, use, left stick, walking")
    t = help({ padMode = "tap", padRelease = "keep", blockSticks = true })
    check(t:find("The stick keeps the pick", 1, true) and t:find("Tap again to use it", 1, true) and t:find("Both sticks are blocked", 1, true) and not t:find("Walking stops", 1, true),
        "help: keep, both sticks")
    t = help({ holdCamera = false, blockSticks = false })
    check(not t:find("blocked", 1, true) and not t:find("Walking stops", 1, true) and not t:find("camera stays", 1, true), "help: no stick line when off")
    check(select(2, help({ padMode = "hold", padRelease = "use", holdCamera = true }):gsub("\n", "\n")) <= 10, "help stays short")
    help({ openAt = "cursor", numberKeys = true, padMode = "hold", padRelease = "keep", stick = "right", holdCamera = true, blockSticks = false })
end
-- Gamepad interface: the full-screen click catcher stays hidden (no cursor mode), and rings
-- still do not rebuild while one is open.
local nBefore = env.RINGS[rid].n
click("r" .. rid, true)
check(env.active == rid and not button.shown, "gamepad interface: ring open, click catcher hidden")
HaloRing.scripts.OnUpdate(HaloRing, 0.02)
spells.slices[#spells.slices + 1] = { kind = "emote", token = "cheer" }
H.Changed("padui open"); advance(1)
check(env.RINGS[rid].n == nBefore, "no rebuild while a gamepad ring is open")
click("close", true); for _ = 1, 10 do HaloRing.scripts.OnUpdate(HaloRing, 0.02) end
advance(1); advance(1)
check(env.RINGS[rid].n == nBefore + 1, "rebuilt after it closed")
table.remove(spells.slices); H.Changed("undo2"); advance(1)
padUI = false; H.Changed("kbm2"); advance(1)

-- A ring with only a gamepad button (no keyboard key) is bound.
local padOnly = H.NewRing("Pad only")
padOnly.padKey = "PADDLEFT"
padOnly.slices = { { kind = "emote", token = "wave" } }
H.Changed("pad only"); advance(1)
check(overrides[binds]["PADDLEFT"] == "HaloButton:p" .. padOnly.id, "gamepad-only ring is bound")
H.DeleteRing(padOnly.id); advance(1)

-- Positions: saved, clamped on screen, used when not at the cursor.
H.SetOption("openAt", "center"); H.SetOption("centerPos", { 0.3, 0.7 }); advance(1)
click("r" .. rid, true)
check(math.abs(env.cx - 0.3) < 1e-9 and math.abs(env.cy - 0.7) < 1e-9, "screen-centre mode uses its position")
click("close", true)
H.SetOption("centerPos", { 5, -1 })
check(H.Position("centerPos")[1] == 0.95 and H.Position("centerPos")[2] == 0.05, "positions clamped on screen")
H.SetOption("openAt", "cursor"); H.SetOption("centerPos", { 0.5, 0.5 }); advance(1)

-- Hold mode: the gamepad button (p<id>) behaves like the keyboard key.
stickState.x, stickState.y, stickState.len = 0, 1, 1
click("p" .. rid, true)
check(env.active == rid, "pad hold opens")
check(click("p" .. rid, false) == "LeftButton", "pad hold: release uses the pointed slice")
-- Tap mode: tap opens and stays; release does nothing; tap again uses; centred tap closes.
H.SetOption("padMode", "tap"); advance(1); advance(1)
stickState.len = 0
click("p" .. rid, true)
check(env.active == rid and env.sticky, "tap opens and stays open")
check(click("p" .. rid, false) == false and env.active == rid, "releasing the button does not close it")
stickState.x, stickState.y, stickState.len = 0, 1, 1
check(click("p" .. rid, true) == "LeftButton" and env.active == nil, "second tap uses the pointed slice")
click("p" .. rid, false)
stickState.len = 0
click("p" .. rid, true); click("p" .. rid, false)
check(click("p" .. rid, true) == false and env.active == nil, "second tap with the stick centred closes")
click("p" .. rid, false)
click("p" .. rid, true); stickState.len = 1
check(click("use", true) == "LeftButton", "L/R/A still confirm in tap mode")
stickState.len = 0
check(click("r" .. rid, true) == false and env.active == rid, "keyboard key keeps hold behaviour in tap mode")
click("r" .. rid, false); click("close", true)
H.SetOption("padMode", "hold"); advance(1); advance(1)

-- A gamepad-only ring on the right shoulder: bound, and the shoulder is not a confirm
-- button while it is open (it is the ring's own button).
local combo = H.NewRing("Shoulder")
combo.padKey = "PADRSHOULDER"
combo.slices = { { kind = "emote", token = "wave" } }
H.Changed("shoulder"); advance(1)
check(overrides[binds]["PADRSHOULDER"] == "HaloButton:p" .. combo.id, "gamepad-only ring bound to its button")
click("p" .. combo.id, true)
check(env.active == combo.id, "its button opens it")
check(overrides[keys]["PADRSHOULDER"] == nil and overrides[keys]["PADLSHOULDER"] == "HaloButton:use",
    "the ring's own button is not a confirm button; the other shoulder is")
-- Gamepad hold: letting go with the stick centred closes (no stay-open in hold mode).
stickState.len = 0
check(click("p" .. combo.id, false) == false and env.active == nil, "pad hold released centred closes")
H.DeleteRing(combo.id); advance(1)

-- 5b. No rebuild while a ring is open.
click("r" .. rid, true)
spells.slices[#spells.slices + 1] = { kind = "emote", token = "cheer" }
H.Changed("while open"); advance(1)
check(env.RINGS[rid].n == 3, "no rebuild while open")
click("close", true)
advance(1); advance(1)
check(env.RINGS[rid].n == 4, "rebuilt after closing")
table.remove(spells.slices); H.Changed("undo"); advance(1)

-- 6. Combat: changes wait, the last build stays.
combat = true
spells.slices[#spells.slices + 1] = { kind = "emote", token = "bow" }
H.Changed("combat edit"); advance(1)
check(env.RINGS[rid].n == 3, "no rebuild in combat")
combat = false
events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
check(env.RINGS[rid].n == 4, "rebuilt after combat")

-- 7. Empty ring does not open; deleting a ring removes nested slices pointing at it.
local empty = H.NewRing("Empty"); empty.key = "F"; H.Changed("x"); advance(1)
check(overrides[binds]["F"] == "HaloButton:r" .. empty.id, "empty ring keeps its key")
check(click("r" .. empty.id, true) == false and env.active == nil and not button.shown, "empty ring does not open")
H.DeleteRing(1); advance(1)
for _, s in ipairs(spells.slices) do check(not (s.kind == "ring" and s.ringID == 1), "nested slice removed") end

-- 8. Visual pointing agrees with the secure Pick for every direction and ring size.
for n = 1, 12 do
    for deg = 0, 359, 7 do
        local a = math.rad(deg)
        local full, seg = 2 * math.pi, 2 * math.pi / n
        local expect = math.floor(((math.atan2(math.sin(a), math.cos(a)) + seg / 2) % full) / seg) + 1
        if expect > n then expect = 1 end
        check(expect >= 1 and expect <= n, "pick in range")
        -- The secure Pick, fed the same stick direction, agrees.
        env.active = rid; env.RINGS[rid].n = n
        stickState.x, stickState.y, stickState.len = math.sin(a), math.cos(a), 1
        check(Handle(header).Run(nil, env.Pick) == expect, "secure pick matches for n=" .. n .. " deg=" .. deg)
    end
end

stickState.len = 0; env.active = nil
-- 8b. Key conflicts: another addon's top-priority override wins the key.
local foreign = {}
function GetBindingAction(key, checkOverride)
    if checkOverride and foreign[key] then return foreign[key] end
    local ours = overrides[binds] and overrides[binds][key]
    return ours and ("CLICK " .. ours) or ""
end
check(H.KeyTakenBy("SHIFT-Q", rid) == nil, "our own key is free")
foreign["SHIFT-Q"] = "CLICK BindCardsHoverKeys:SPELL 1"
check(H.KeyTakenBy("SHIFT-Q", rid) == "BindCards", "BindCards override detected")
foreign["SHIFT-Q"] = "CLICK InputFunctionBindingButton_PADRSTICK:LeftButton"
check(H.KeyTakenBy("SHIFT-Q", rid) == nil, "Blizzard gamepad binding is not reported as taken")
foreign["SHIFT-Q"] = nil
check(H.KeyTakenBy("SHIFT-Q", empty.id) == "Halo ring Spells", "another Halo ring on the same key")

-- 8c. Per-ring tooltips: shown for the pointed slice only when the ring has them on.
local tipShown = 0
GameTooltip.Show = function() tipShown = tipShown + 1 end
GameTooltip.GetOwner = function() return HaloRing end
local onUpdate = HaloRing.scripts.OnUpdate
spells.tooltips = true
cursorX, cursorY = 500, 400
click("r" .. rid, true)
cursorX, cursorY = 500, 480
onUpdate(HaloRing, 0.2)
check(tipShown == 1, "tooltip shown for pointed slice")
click("close", true)
spells.tooltips = nil
click("r" .. rid, true)
onUpdate(HaloRing, 0.2); onUpdate(HaloRing, 0.2)
check(tipShown == 1, "no tooltip when the ring has them off")
click("close", true); advance(1)

-- 8d. Spacing moves slices apart but leaves pointing (dead zone) alone.
check(H.RingRadius(8, 1.5) == math.floor(H.RingRadius(8) * 1.5 + 0.5), "spacing scales the radius")
check(H.RingRadius(8, 99) == H.RingRadius(8, H.SPREAD_MAX), "spacing clamped")
local deadBefore = env.RINGS[rid].dead
spells.spread = 2; H.Changed("spread"); advance(1)
check(env.RINGS[rid].dead == deadBefore, "dead zone unchanged by spacing")
spells.spread = nil; H.Changed("spread"); advance(1)

-- 8d2. Another ring's key while a ring stays open opens that ring; the ring's own key closes it.
local other = H.NewRing("Other")
other.key = "SHIFT-E"
other.slices = { { kind = "emote", token = "bow" } }
H.Changed("other"); advance(1)
stickState.x, stickState.y, stickState.len = 0, 0, 0
cursorX, cursorY = 500, 400
click("r" .. rid, true); click("r" .. rid, false)
check(env.active == rid and env.sticky, "released in the middle: the ring stays open")
click("r" .. other.id, true)
check(env.active == other.id, "another ring's key opens that ring")
click("r" .. other.id, false)
check(env.active == other.id and env.sticky, "released in the middle: it stays open too")
click("r" .. other.id, true)
check(env.active == nil, "its own key closes it")
click("r" .. other.id, false)
-- A nested ring counts as its parent's: the parent's key closes it.
table.insert(spells.slices, 1, { kind = "ring", ringID = other.id })
H.Changed("nested"); advance(1)
click("r" .. rid, true); click("r" .. rid, false)
check(click("s1", true) == false and env.active == other.id, "nested ring open")
click("r" .. rid, true)
check(env.active == nil, "the parent ring's key closes the nested ring")
click("r" .. rid, false)
table.remove(spells.slices, 1); H.Changed("nested undo"); advance(1)
-- Tap mode: another ring's gamepad button opens that ring instead of using a slice.
other.padKey = "PADDRIGHT"
H.SetOption("padMode", "tap"); H.Changed("tap other"); advance(1); advance(1)
click("p" .. rid, true)
check(env.active == rid, "tap opens")
stickState.x, stickState.y, stickState.len = 0.9, 0, 0.9
check(click("p" .. other.id, true) == false and env.active == other.id, "tap: another ring's button opens that ring")
check(click("p" .. other.id, true) == "LeftButton" and env.active == nil, "tap: its own button uses the pointed slice")
stickState.x, stickState.y, stickState.len = 0, 0, 0
H.SetOption("padMode", "hold"); H.DeleteRing(other.id); advance(1); advance(1)

-- 8e. Every style opens, animates to the end and closes; per-ring style wins over the default.
for _, id in ipairs(H.RingSkins.order) do
    H.SetOption("style", id); advance(1)
    click("r" .. rid, true)
    check(H.RingState.skin.id == id, "style " .. id .. " used")
    for _ = 1, 20 do onUpdate(HaloRing, 0.02) end
    check(H.RingState.phase == "shown", "style " .. id .. " finished opening")
    for i = 1, H.RingState.n do check(H.RingState.animScale[i] == 1, "style " .. id .. " slots settled") end
    click("close", true)
    for _ = 1, 10 do onUpdate(HaloRing, 0.02) end
    check(H.RingState.phase == nil, "style " .. id .. " closed")
end
-- Rune colours: blue (art), class and custom all open cleanly and tint.
function UnitClass() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
H.SetOption("style", "D")
for _, mode in ipairs({ "blue", "class", "custom" }) do
    H.SetOption("runeColor", mode); advance(1)
    local r = H.RingSkins.RuneColor()
    check((mode == "blue") == (r == nil), "rune colour " .. mode)
    click("r" .. rid, true); for _ = 1, 20 do onUpdate(HaloRing, 0.02) end
    click("close", true); for _ = 1, 10 do onUpdate(HaloRing, 0.02) end
end
check(select(3, H.RingSkins.RuneColor()) == 1, "custom colour read")
H.SetOption("runeColor", "blue")
spells.style = "D"; H.SetOption("style", "B"); advance(1)
click("r" .. rid, true)
check(H.RingState.skin.id == "D", "ring's own style wins")
click("close", true); spells.style = nil; H.SetOption("style", "A"); advance(1)
check(H.RingSkins.Get("nope").id == "A", "unknown style falls back to A")
check(H.RingSkins.SlotRadius(H.RingSkins.Get("A"), 64) == 64, "Flyout (final) slots stay on the ring radius")
check(H.RingSkins.SlotRadius(H.RingSkins.Get("D"), 100) < 100, "Runes slots sit inside the rune circle")

-- Copying rings between characters.
do
    local me = H.CharacterKey()
    local n0 = #H.db.rings
    local mineRing = H.NewRing("Mine")
    H.SetRingOwner(mineRing, me)
    check(mineRing.ownerClass == "MAGE", "an owned ring remembers its owner's class")
    check(mineRing.ownerFull == "Mime Blanche" and H.RingOwnerName(mineRing) == "Mime Blanche", "and its full name, surname included")
    local other = H.NewRing("Kaelen's supplies")
    other.owner, other.ownerClass, other.ownerFull = "Kaelen-Forever", "PALADIN", "Kaelen Ashdown"
    other.key, other.padKey = "CTRL-F9", "PAD5"
    other.slices = { { kind = "spell", spell = "Frostbolt" } }
    -- Nested rings: one Kaelen can see (his own), one only a third character can see.
    local nestedOwn = H.NewRing("Kaelen nested"); nestedOwn.owner = "Kaelen-Forever"
    local nestedEveryone = H.NewRing("Shared nested")
    table.insert(other.slices, { kind = "ring", ringID = nestedOwn.id })
    table.insert(other.slices, { kind = "ring", ringID = nestedEveryone.id })
    local copy, notes = H.CopyRing(other.id, me)
    check(copy and copy.owner == me and copy.ownerClass == "MAGE" and copy.id ~= other.id, "copy belongs to this character")
    check(copy.key == "CTRL-F9" and copy.padKey == "PAD5" and #notes == 1, "the copy keeps its key and button; only the nested ring is noted")
    check(#copy.slices == 2 and copy.slices[2].ringID == nestedEveryone.id, "nested rings this character cannot see are left out")
    check(copy.name == "Kaelen's supplies" and other.name == "Kaelen's supplies", "same name when nothing here has it")
    check(other.owner == "Kaelen-Forever" and other.key == "CTRL-F9", "the original is untouched")
    copy.slices[1].spell = "Fireball"
    check(other.slices[1].spell == "Frostbolt", "the copy is independent")
    -- A second copy: the key is now used by the first one, and the name repeats.
    local again, notes2 = H.CopyRing(other.id, me)
    check(again.key == nil and again.padKey == nil and again.name == "Kaelen's supplies copy", "conflicting key dropped, name made unique")
    check(#notes2 >= 2 and notes2[1]:find("CTRL-F9", 1, true), "and said so")
    local everyone = H.CopyRing(other.id, nil)
    check(everyone.owner == nil and everyone.ownerClass == nil, "copy for everyone has no owner")
    -- Duplicating your own ring keeps it in the same folder.
    local dup = H.CopyRing(mineRing.id, mineRing.owner)
    check(dup.owner == me and dup.name == "Mine copy", "duplicate stays with this character")
    -- The folders: this character, everyone, then Kaelen.
    local groups = H.RingGroups()
    check(groups[1].key == "mine" and groups[2].key == "all" and groups[3].key == "Kaelen-Forever" and groups[3].foreign
        and groups[3].class == "PALADIN", "folders: this character, everyone, then the others")
    check(groups[1].title == "Mime Blanche" and groups[3].title == "Kaelen Ashdown", "folder titles are full names")
    for _, ring in ipairs({ copy, again, everyone, dup, mineRing, other, nestedOwn, nestedEveryone }) do H.DeleteRing(ring.id) end
    check(#H.db.rings == n0, "test rings removed")
end

-- 9. Options window builds and refreshes on both pages.
-- A ring made "only this character" on another character is not listed here.
local foreign = { id = 9999, name = "Foreign ring", owner = "Somebody-Elsewhere", slices = {} }
table.insert(H.db.rings, 1, foreign)
H.ToggleOptions()
check(HaloOptions and HaloOptions.shown, "options window opens")
local visible = H.VisibleRings()
local listed, mine = false, 0
for _, ring in ipairs(visible) do
    if ring.id == 9999 then listed = true else mine = mine + 1 end
end
check(not listed and mine == #H.db.rings - 1, "another character's ring is not listed, the others are")
table.remove(H.db.rings, 1)
-- Only other characters' rings exist: the list opens on one of them and the locked banner shows.
do
    local owners = {}
    for i, ring in ipairs(H.db.rings) do owners[i] = ring.owner or false; ring.owner = "Zed-Forever"; ring.ownerClass = "ROGUE" end
    H.Changed("owner"); advance(1)
    local groups = H.RingGroups()
    check(#groups[1].rings == 0 and #groups[2].rings == 0 and #groups[3].rings == #H.db.rings, "all rings in one other character's folder")
    for i, ring in ipairs(H.db.rings) do ring.owner = owners[i] or nil; ring.ownerClass = nil end
    H.Changed("owner"); advance(1)
end
H.ToggleOptions(2)
H.ToggleOptions(3)
-- The window comes back if something hides it while the macro window is open...
MacroFrame = CreateFrame("Frame", "MacroFrame")
HaloOptions:Hide(); advance(0.1)
check(HaloOptions.shown, "window stays open beside the macro window")
-- ...but closing it yourself works.
H.ToggleOptions(); advance(0.1)
check(not HaloOptions.shown, "closing it yourself still works")
MacroFrame:Hide(); H.ToggleOptions()

-- 9b. The Add (+) and Style menus are Halo's own popup: Blizzard's context menus opened from
-- addon code run the gamepad window manager under addon taint.
do
    local menuRing = H.NewRing("Menu ring"); advance(1)
    H.ToggleOptions(1)
    local menuRow
    for _, f in ipairs(frames) do if rawget(f, "ringID") == menuRing.id then menuRow = f end end
    check(menuRow, "the new ring is listed")
    menuRow.scripts.OnClick(menuRow)   -- select it
    local P = H.Popup
    local owner = CreateFrame("Button")
    local function rowsOf(level)
        local list = {}
        for _, row in ipairs(P.panels[level] and P.panels[level].rows or {}) do if row.shown then list[#list + 1] = row end end
        return list
    end
    local function rowNamed(level, text)
        for _, row in ipairs(rowsOf(level)) do if row.text.text == text then return row end end
    end
    H.AddMenu(owner)
    check(P.IsOpen() and P.panels[1].shown and P.catcher.shown, "the Add menu opens on a Halo panel over a click catcher")
    check(P.panels[1].legacyRim ~= nil, "the panel has the Legacy rim (a finished edge)")
    for _, text in ipairs({ "Add to Menu ring", "Automatic", "Emote", "Target marker", "Another ring", "Custom macro...",
        "Or drag a spell, item, mount, toy, pet", "or macro onto the ring." }) do
        check(rowNamed(1, text), "Add menu entry: " .. text)
    end
    check(not rowNamed(1, "Equipment set"), "no equipment sets here")
    check(rowNamed(1, "Another ring").entry.disabled ~= true, "other rings can be nested")
    check(rowNamed(1, "Add to Menu ring").entry.title and not rowNamed(1, "Add to Menu ring").hover.shown, "the title is not a button")
    -- Hovering a group opens its submenu; hovering another group swaps it.
    local emote = rowNamed(1, "Emote")
    emote.scripts.OnEnter(emote)
    check(P.panels[2] and P.panels[2].shown and #rowsOf(2) == #H.EMOTES, "hovering Emote opens its submenu")
    local marker = rowNamed(1, "Target marker")
    marker.scripts.OnEnter(marker)
    check(#rowsOf(2) == #H.MARKERS + 1 and rowNamed(2, "Clear marker"), "hovering Target marker swaps the submenu")
    local custom = rowNamed(1, "Custom macro...")
    custom.scripts.OnEnter(custom)
    check(not P.panels[2].shown, "hovering a plain item closes the submenu")
    marker.scripts.OnEnter(marker)
    local n0 = #menuRing.slices
    local star = rowsOf(2)[1]
    star.scripts.OnClick(star)
    check(#menuRing.slices == n0 + 1 and menuRing.slices[n0 + 1].kind == "marker" and menuRing.slices[n0 + 1].index == 1,
        "clicking a submenu row adds the slice")
    check(not P.IsOpen() and not P.panels[1].shown and not P.panels[2].shown and not P.catcher.shown, "and closes the menu")
    -- The gamepad cursor clicks rather than hovers: a click on a group opens and closes it too.
    H.AddMenu(owner)
    local rings = rowNamed(1, "Another ring")
    rings.scripts.OnClick(rings)
    check(P.panels[2].shown and #rowsOf(2) == #H.VisibleRings() - 1, "clicking a group opens its submenu")
    rings.scripts.OnClick(rings)
    check(not P.panels[2].shown and P.IsOpen(), "clicking it again closes only the submenu")
    -- Escape, a click outside, and the button itself close it.
    P.catcher.scripts.OnKeyDown(P.catcher, "ESCAPE")
    check(not P.IsOpen() and not P.catcher.shown, "Escape closes the menu")
    H.AddMenu(owner)
    P.catcher.scripts.OnMouseDown(P.catcher)
    check(not P.IsOpen(), "a click outside closes the menu")
    H.AddMenu(owner); H.AddMenu(owner)
    check(not P.IsOpen(), "the + button closes the menu it opened")
    -- Style menu: Default plus one choice per style, the current one marked.
    local defaultSkin = H.RingSkins.Get(H.Option("style"))
    local defaultText = "Default (" .. defaultSkin.id .. " " .. defaultSkin.name .. ")"
    H.StyleMenu(owner)
    check(P.IsOpen() and rowNamed(1, "Style of Menu ring") and #rowsOf(1) == #H.RingSkins.order + 2, "style menu: title, Default, one row per style")
    check(rowNamed(1, defaultText).dot.shown, "Default is marked")
    local bText = "B  " .. H.RingSkins.list.B.name
    check(not rowNamed(1, bText).dot.shown, "B is not marked yet")
    rowNamed(1, bText).scripts.OnClick(rowNamed(1, bText)); advance(1)
    check(menuRing.style == "B" and not P.IsOpen(), "picking a style sets it and closes the menu")
    H.StyleMenu(owner)
    check(rowNamed(1, bText).dot.shown and not rowNamed(1, defaultText).dot.shown, "the pick is marked")
    rowNamed(1, defaultText).scripts.OnClick(rowNamed(1, defaultText)); advance(1)
    check(menuRing.style == nil, "Default clears the ring's own style")
    -- Closing the window closes the menu with it.
    H.StyleMenu(owner)
    H.ToggleOptions(); advance(0.1)
    check(not HaloOptions.shown and not P.IsOpen(), "closing the window closes the menu")
    H.ToggleOptions()
    H.DeleteRing(menuRing.id); advance(1)
end

-- 9c. Layout B: the same window redesigned, behind the footer's A | B switch.
do
    check(H.db.window.layout == nil, "layout A by default")
    local first = #frames + 1
    SlashCmdList.HALO("layout b"); advance(0.1)
    check(H.db.window.layout == "b" and HaloOptions.shown, "/halo layout b switches the open window")
    local bRing = H.NewRing("B ring"); advance(1)
    H.ToggleOptions(1); advance(0.1)
    local row, more
    for i = first, #frames do
        local f = frames[i]
        if rawget(f, "ringID") == bRing.id then row = f end
        if rawget(f, "text") == "..." then more = f end
    end
    check(row and more, "layout B has its own ring list and a ... button")
    row.scripts.OnClick(row); advance(0.1)
    -- The ... menu: Duplicate, Make macro, and Delete behind a confirmation submenu.
    local P = H.Popup
    more.scripts.OnClick(more)
    local function rowNamed(level, text)
        for _, r in ipairs(P.panels[level] and P.panels[level].rows or {}) do
            if r.shown and r.text.text == text then return r end
        end
    end
    check(P.IsOpen() and rowNamed(1, "B ring") and rowNamed(1, "Duplicate") and rowNamed(1, "Make macro"), "the ... menu lists the ring's actions")
    local del = rowNamed(1, "Delete ring")
    del.scripts.OnClick(del)
    check(H.GetRing(bRing.id) and rowNamed(2, "Yes, delete it"), "Delete asks first")
    local yes = rowNamed(2, "Yes, delete it")
    yes.scripts.OnClick(yes); advance(1)
    check(not H.GetRing(bRing.id) and not P.IsOpen(), "confirming deletes the ring")
    -- Options page: rows fold with their switch; both states refresh.
    H.ToggleOptions(2)
    H.SetOption("numberKeys", false); advance(0.1)
    H.SetOption("openAt", "center"); advance(0.1)
    H.SetOption("numberKeys", true); H.SetOption("openAt", "cursor"); advance(0.1)
    H.ToggleOptions(3)
    H.SetOptionsLayout("a"); advance(0.1)
    check(H.db.window.layout == nil and HaloOptions.shown, "back to layout A")
    H.ToggleOptions(1)
end

-- Placement tool: drop the outline, Done saves it as a screen fraction.
H.PlaceRing("padPos", "Gamepad ring")
check(HaloPlacer.slots[3] and HaloPlacer.slots[3].shown ~= false and HaloPlacer.art ~= nil or H.RingSkins.Get(H.Option("style")).buildRing == nil,
    "the placement ring draws the default style with its slots")
HaloPlacer:Finish()
local placed = H.Position("padPos")
check(math.abs(placed[1] - 0.5) < 1e-6 and math.abs(placed[2] - 0.5) < 1e-6, "placement saved")
-- Every style can be drawn by the placement tool.
for _, id in ipairs(H.RingSkins.order) do
    H.SetOption("style", id); H.PlaceRing("centerPos", "Fixed position ring")
    HaloPlacer:Finish()
end
H.SetOption("style", "A")
H.ToggleOptions()
H.Status()

print(("Halo smoke: %d checks passed"):format(assertions))

-- Texture paths must use escaped backslashes ("Interface\X"); a single one is a broken escape.
for file in toc:gmatch("\n([%w_]+%.lua)") do
    local text = io.open(file):read("*a")
    check(not text:find('"Interface\[%a]'), file .. " has a texture path with a single backslash")
end
-- No Blizzard menu or popup code: opened from addon code it runs the gamepad window manager
-- under addon taint. Halo's own popup (Options.lua) stands in.
for file in toc:gmatch("\n([%w_]+%.lua)") do
    local text = io.open(file):read("*a")
    for _, name in ipairs({ "MenuUtil", "UIDropDownMenu", "StaticPopup", "EasyMenu", "Menu.ModifyMenu" }) do
        check(not text:find(name, 1, true), file .. " uses Blizzard's " .. name)
    end
end
print(("Halo smoke (with path check): %d checks passed"):format(assertions))

-- Middle name: every style opens and points with it.
for _, id in ipairs(H.RingSkins.order) do
    H.SetOption("style", id); advance(1)
    click("r" .. rid, true); cursorX, cursorY = 500, 480
    for _ = 1, 5 do onUpdate(HaloRing, 0.05) end
    click("close", true); for _ = 1, 10 do onUpdate(HaloRing, 0.02) end
end
H.SetOption("style", "A"); advance(1)

-- Debug log: /halo debug writes to HaloDB.debugLog (saved on /reload), capped at 300 lines.
SlashCmdList.HALO("debug")
click("r" .. rid, true); click("close", true); advance(5)
check(#H.db.debugLog >= 3 and H.db.debugLog[#H.db.debugLog]:find("closed"), "ring close logged")
for i = 1, 700 do H.Log("x" .. i) end
check(#H.db.debugLog == 500, "debug log capped")
SlashCmdList.HALO("debug")

-- Texture manifest: every atlas/file the ring styles use is listed (for hand-made art).
local listed = {}
for _, group in ipairs(H.TEXTURES) do for _, e in ipairs(group[2]) do listed[e[1]] = true end end
for _, file in ipairs({ "Skins.lua", "Ring.lua" }) do
    local text = io.open(file):read("*a")
    for name in text:gmatch('atlas = "([^"]+)"') do check(listed[name], file .. ": atlas missing from manifest: " .. name) end
    for name in text:gmatch('SetAtlas%("([^"]+)"') do check(listed[name], file .. ": atlas missing from manifest: " .. name) end
    for name in text:gmatch('"(Interface\\[^"]+)"') do
        check(listed[(name:gsub("\\\\", "\\"))], file .. ": file missing from manifest: " .. name)
    end
end
function GetBuildInfo() return "1.60.1", "70009", "Sep 2026", 16001 end
H.DumpTextures()
check(H.db.textureDump and H.db.textureDump.styles["A-Flyout"], "texture dump recorded")
print(("Halo smoke (with manifest): %d checks passed"):format(assertions))

-- Rebuilds: drawing-only options do not rebuild the secure rings; the others do.
advance(1)
local runs = H.compileInfo.runs
H.SetOption("labels", false); H.SetOption("runeCustom", { 0.2, 0.9, 0.4 }); H.SetOption("sounds", false); advance(1)
check(H.compileInfo.runs == runs, "drawing-only options do not rebuild")
H.SetOption("numberKeys", false); advance(1)
check(H.compileInfo.runs == runs + 1, "a secure option rebuilds")
H.SetOption("labels", true); H.SetOption("sounds", true); H.SetOption("numberKeys", true); advance(1)

-- Defaults are copied: changing a saved position table never changes the defaults.
H.db.options.padPos[1] = 0.1
SlashCmdList.HALO("reset yes"); advance(1)
check(H.db.options.padPos[1] == 0.78, "defaults are not shared with saved options")

-- /halo reset yes goes back to Keep (Use is not the default); the stick-direction setting stays on.
H.SetOption("padRelease", "use"); advance(1)
check(cvars.GamePadStickAxisButtons == "1" and H.db.stickButtonsSaved == nil, "sticky selection on")
SlashCmdList.HALO("reset yes"); advance(1)
check(H.StickRelease() == "keep" and cvars.GamePadStickAxisButtons == "1" and H.db.stickButtonsSaved == nil,
    "reset goes back to Keep and keeps the stick setting on")
-- Saves from before 0.9.15 with Stick released: Nothing become Keep.
H.db.options.padRelease = "none"
check(H.StickRelease() == "keep", "an old Nothing reads as Keep")
-- Blizzard's gamepad interface binds R3 to ping (a priority override on UIParent) after a
-- reload, at a moment that varies, and whenever one of its panels closes. The most recent
-- override wins, so Halo puts a ring's button back on top right after.
function GetBindingAction(key, checkOverride) return checkOverride and bindTop[key] or "" end   -- most recent wins
local r3 = H.NewRing("R3 ring")
r3.padKey = "PADRSTICK"
r3.slices = { { kind = "emote", token = "wave" } }
H.Changed("r3"); advance(1)
check(bindOrder["PADRSTICK"] == binds, "ring on R3 bound")
SetOverrideBinding(UIParent, true, "PADRSTICK", "TOGGLEPINGSYSTEM")
check(bindOrder["PADRSTICK"] == UIParent, "Blizzard's ping binding on top")
check(H.KeyTakenBy("PADRSTICK", r3.id) == nil, "Blizzard's ping on top is not reported as a conflict")
advance(0.1)
check(bindOrder["PADRSTICK"] == binds, "Halo's ring key put back on top")
SetOverrideBinding(UIParent, true, "PADLSTICK", "TOGGLEAUTORUN"); advance(0.1)
check(bindOrder["PADLSTICK"] == UIParent, "autorun left alone (no ring on L3)")
SetOverrideBinding(UIParent, false, "PADRSTICK", ""); advance(0.1)
check(bindOrder["PADRSTICK"] == binds, "Blizzard clearing a key changes nothing")
-- In combat binding is blocked: the rebind waits for the end of the fight.
combat = true
SetOverrideBinding(UIParent, true, "PADRSTICK", "TOGGLEPINGSYSTEM"); advance(0.1)
check(bindOrder["PADRSTICK"] == UIParent, "in combat: not rebound yet")
combat = false; events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
check(bindOrder["PADRSTICK"] == binds, "rebound when the fight ends")
H.DeleteRing(r3.id); advance(1)
check(bindOrder["PADRSTICK"] == nil, "deleted ring: R3 no longer bound by Halo")
-- Nothing to redo when Halo's binding is still the one on top (in game every rebind makes
-- all action bars update).
local sets = 0
local realSet = SetOverrideBindingClick
SetOverrideBindingClick = function(...) sets = sets + 1; return realSet(...) end
local r3b = H.NewRing("R3 again")
r3b.padKey = "PADRSTICK"
r3b.slices = { { kind = "emote", token = "wave" } }
H.Changed("r3b"); advance(1)
SetOverrideBinding(UIParent, true, "PADRSTICK", "TOGGLEPINGSYSTEM")
bindOrder["PADRSTICK"], bindTop["PADRSTICK"] = binds, "CLICK HaloButton:p" .. r3b.id   -- ours still on top
sets = 0; advance(0.1)
check(sets == 0, "no rebind when Halo's binding is still on top")
SetOverrideBinding(UIParent, true, "PADRSTICK", "TOGGLEPINGSYSTEM"); advance(0.1)
check(sets > 0 and bindOrder["PADRSTICK"] == binds, "rebind when Blizzard really took it")
H.DeleteRing(r3b.id); advance(1)
-- The stick's direction keys: the setting is switched off and on at login (Keep or Use), since
-- the game only turns them on when the setting changes while it runs.
local cvarSets = {}
local realSetCVar = SetCVar
SetCVar = function(name, value) if name == "GamePadStickAxisButtons" then cvarSets[#cvarSets + 1] = tostring(value) end; return realSetCVar(name, value) end
H.SetOption("padRelease", "use"); advance(1)
cvarSets = {}
H.Fire("login"); advance(1)
check(#cvarSets == 2 and cvarSets[1] == "0" and cvarSets[2] == "1" and cvars.GamePadStickAxisButtons == "1",
    "login with Use: the stick keys setting is switched off and on")
cvarSets = {}
H.SetOption("padRelease", "keep"); advance(1)
check(#cvarSets == 0, "changing Use to Keep leaves the setting alone")
-- A Blizzard radial (class flyout) closes on any pad button, and the stick direction keys count:
-- while one is open the setting is off, and it comes back when the radial closes.
do
    local fly = { hooks = {}, shown = false }
    function fly:IsShown() return self.shown end
    function fly:HookScript(event, fn) self.hooks[event] = fn end
    function fly:Set(v) self.shown = v; self.hooks[v and "OnShow" or "OnHide"]() end
    _G.GamepadSpellFlyout = fly
    H.SetOption("padRelease", "use"); advance(1)
    H.HookRadials(); H.HookRadials()
    check(fly.hooks.OnShow and fly.hooks.OnHide, "the Blizzard flyout is hooked")
    check(cvars.GamePadStickAxisButtons == "1", "stick keys on before the flyout")
    fly:Set(true)
    check(cvars.GamePadStickAxisButtons == "0", "flyout open: stick keys off")
    H.SetOption("padRelease", "keep"); advance(1)
    check(cvars.GamePadStickAxisButtons == "0", "an option change while the flyout is open leaves it off")
    fly:Set(false); advance(1)
    check(cvars.GamePadStickAxisButtons == "1", "flyout closed: stick keys back on")
    check(H.db.stickButtonsSaved == nil, "the player's own value is not recorded (nothing restores it)")
    combat = true; fly:Set(true)
    check(cvars.GamePadStickAxisButtons == "1", "in combat the setting is left alone")
    fly:Set(false); combat = false
    events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED"); advance(1)
    check(cvars.GamePadStickAxisButtons == "1", "nothing to undo after a combat flyout")
    fly:Set(true); combat = true; fly:Set(false)
    check(cvars.GamePadStickAxisButtons == "0", "closed in combat: still off until combat ends")
    combat = false; events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED"); advance(1)
    check(cvars.GamePadStickAxisButtons == "1", "back on after combat")
    _G.GamepadSpellFlyout = nil
end
SetCVar, SetOverrideBindingClick = realSetCVar, realSet
-- Healthstones join the Potions list, before the potions (they are not filed as potions).
bags[0][#bags[0] + 1] = { itemID = 5512, quality = 1 }
H.Changed("healthstone"); advance(1)
local sup = H.live[1]
check(sup[1].itemID == 5512 and sup[2].itemID == 118 and sup[3].itemID == 2070,
    "Supplies: healthstone first, then the potion, then food")
check(H.AUTO_BY_ID.potions[4]:find("ealthstone"), "the Potions description mentions healthstones")
-- An item placed by hand is not repeated by an automatic list.
table.insert(H.db.rings[1].slices, 1, { kind = "item", itemID = 118 })
H.Changed("manual potion"); advance(1)
local count118 = 0
for _, s in ipairs(H.live[1]) do if s.itemID == 118 then count118 = count118 + 1 end end
check(count118 == 1 and H.live[1][1].itemID == 118, "a potion placed by hand is not listed twice")
table.remove(H.db.rings[1].slices, 1)
table.remove(bags[0])
H.Changed("undo healthstone"); advance(1)
check(H.live[1][1].itemID == 118, "no healthstone in the bags: the potion comes first again")
print(("Halo smoke (with audit checks): %d checks passed"):format(assertions))
