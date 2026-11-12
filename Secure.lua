-- Secure core. Everything that must work in combat happens in the restricted environment:
-- opening a ring on its key, finding the pointed slice (mouse or gamepad stick), and
-- performing it through one SecureActionButton. The visible ring (Ring.lua) only follows.
--
-- Flow
--   ring key down  -> open (at the cursor, or the screen centre in the gamepad interface)
--   ring key up    -> pointing at a slice: use it.  In the middle: the ring stays open.
--   while open     -> left click / gamepad confirm uses the pointed slice, number keys use a
--                     slice directly, right click / gamepad cancel goes back or closes,
--                     Escape or the ring key again closes.
-- Ring contents change only out of combat (Compile); in combat the last build stays.

local _, H = ...

local header = CreateFrame("Frame", "HaloHeader", nil, "SecureHandlerBaseTemplate")
local button = CreateFrame("Button", "HaloButton", nil, "SecureActionButtonTemplate")
local keys = CreateFrame("Frame", "HaloKeys", nil, "SecureFrameTemplate")
local binds = CreateFrame("Frame", "HaloBindings")

-- The button covers the screen while a ring is open: it catches clicks, and its rect is
-- the coordinate space for pointing. It is invisible.
button:SetFrameStrata("FULLSCREEN_DIALOG")
button:SetAllPoints(WorldFrame)
button:RegisterForClicks("AnyUp", "AnyDown")
button:EnableMouse(true)
-- SecureFrameTemplate lets clicks fall through to the world; a ring click must not.
if button.SetPropagateMouseClicks then pcall(button.SetPropagateMouseClicks, button, false) end
button:Hide()

header:SetFrameRef("button", button)
header:SetFrameRef("keys", keys)

header:Execute([[
    RINGS, OPT, stack = newtable(), newtable(), newtable()
    BTN, keys = self:GetFrameRef("button"), self:GetFrameRef("keys")
    active, sticky, held, cx, cy = nil, false, nil, 0.5, 0.5
    -- The pointing stick's direction keys held right now (u, d, l, r), whether the stick
    -- pointed while this ring was open (a release only counts after that), the furthest
    -- tilt seen, and the last key pressed with where the stick was then.
    aimHeld, aimArmed = newtable(), false
    aimMax, aimLast, aimPX, aimPY = 0, nil, 0, 0
    ATTRS = newtable("type", "spell", "item", "macro", "macrotext", "toy", "equipmentset", "unit")

    SetKeys = [==[
        keys:ClearBindings()
        local r = RINGS[active]
        if not r then return end
        keys:SetBindingClick(true, "ESCAPE", BTN, "close")
        for i = 1, #r.confirm do keys:SetBindingClick(true, r.confirm[i], BTN, "use") end
        if r.padCancel then keys:SetBindingClick(true, r.padCancel, BTN, "back") end
        -- Layers: the opening ring's chord buttons (R3 ring, R3 + L1 ring...). Bound last, so
        -- they replace a confirm or cancel on the same button.
        local root = layerRoot and RINGS[layerRoot]
        if root and root.layers then
            for btn, cid in pairs(root.layers) do keys:SetBindingClick(true, btn, BTN, "y" .. cid) end
        end
        -- Keep / use on release: the stick's directions are real bindable keys
        -- (PADRSTICKUP...). Each time the stick enters or leaves one, "aim<dir>" reads the
        -- angle; a release with the stick near the middle means it was let go.
        if OPT.stickKeys then
            keys:SetBindingClick(true, OPT.stickKeys .. "UP", BTN, "aimu")
            keys:SetBindingClick(true, OPT.stickKeys .. "DOWN", BTN, "aimd")
            keys:SetBindingClick(true, OPT.stickKeys .. "LEFT", BTN, "aiml")
            keys:SetBindingClick(true, OPT.stickKeys .. "RIGHT", BTN, "aimr")
        end
        if OPT.numbers then
            for i = 1, r.n < 10 and r.n or 10 do
                local key = tostring(i % 10)
                keys:SetBindingClick(true, key, BTN, "s" .. i)
                for m = 1, #r.mods do keys:SetBindingClick(true, r.mods[m] .. key, BTN, "s" .. i) end
            end
        end
    ]==]

    Open = [==[
        local rid = ...
        local r = RINGS[rid]
        if not r then return false end
        if r.n == 0 then owner:CallMethod("OnRingEmpty", rid); return false end
        if active then owner:Run(Close) end
        active, sticky, held = rid, false, nil
        layerRoot = r.layers and rid or nil
        stickyPick = nil
        aimCount = 0
        wipe(aimHeld); aimArmed, aimMax, aimLast = false, 0, nil
        wipe(stack)
        -- The full-screen click catcher is only for the mouse. In the gamepad interface it
        -- stays hidden: a clickable full-screen frame switches the gamepad to cursor control
        -- (the camera stick then moves a cursor for seconds after the ring closes). Binding
        -- clicks still reach the hidden button, and the stick picks the slice.
        if not OPT.padUI then BTN:Show() end
        local x, y
        if OPT.at == "cursor" and not OPT.padUI then x, y = BTN:GetMousePosition() end
        if not x then
            if OPT.padUI then x, y = OPT.padX, OPT.padY else x, y = OPT.cX, OPT.cY end
        end
        cx, cy = x, y
        owner:Run(SetKeys)
        owner:CallMethod("OnRingOpen", rid, cx, cy)
        return true
    ]==]

    Close = [==[
        local used = ...
        if not active then return end
        local was = active
        active, sticky, held, layerRoot = nil, false, nil, nil
        stickyPick = nil
        wipe(aimHeld); aimArmed, aimMax, aimLast = false, 0, nil
        wipe(stack)
        keys:ClearBindings()
        BTN:Hide()
        owner:CallMethod("OnRingClose", was, used, lastInput, aimCount or 0)
    ]==]

    -- Pointed slice: a tilted gamepad stick wins, else the mouse (not in the gamepad UI).
    Pick = [==[
        local r = RINGS[active]
        if not r or r.n == 0 then return nil end
        local dx, dy
        if IsGamePadEnabled() or OPT.padUI then
            local st = GetGamePadState()
            local s = st and st.sticks and st.sticks[OPT.stick]
            if s and s.len and s.len >= OPT.padDead then dx, dy = s.x, s.y end
            -- Sticky selection (option): the last slice the stick pointed at. Set by the
            -- visible ring out of combat, by Aim (the stick's direction keys) in combat.
            if not dx and stickyPick and stickyPick <= r.n then return stickyPick end
        end
        if not dx then
            if OPT.padUI then return nil end
            local x, y = BTN:GetMousePosition()
            if not x then return nil end
            local _, _, w, h = BTN:GetRect()
            dx, dy = (x - cx) * w, (y - cy) * h
            if dx * dx + dy * dy < r.dead * r.dead then return nil end
        end
        local full = 2 * math.pi
        local seg = full / r.n
        local i = floor(((math.atan2(dx, dy) + seg / 2) % full) / seg) + 1
        if i > r.n then i = 1 end
        return i
    ]==]

    Aim = [==[
        local r = RINGS[active]
        if not r or r.n == 0 then return end
        aimCount = (aimCount or 0) + 1   -- (debug log: do the stick's direction keys still arrive?)
        local st = GetGamePadState()
        local s = st and st.sticks and st.sticks[OPT.stick]
        -- A direction key means the stick just crossed the game's own threshold, so its angle
        -- is already a clear direction: read it at any tilt (not only past 20%). The game
        -- presses a direction at about 0.25 tilt, within 60 degrees either side of it.
        if not (s and s.len and s.len > 0.05) then return end
        local full = 2 * math.pi
        local seg = full / r.n
        local i = floor(((math.atan2(s.x, s.y) + seg / 2) % full) / seg) + 1
        if i > r.n then i = 1 end
        if i ~= stickyPick then
            stickyPick = i
            owner:CallMethod("OnStickyPick", i)
        end
    ]==]

    Use = [==[
        local i, down = ...
        local r = RINGS[active]
        local s = r and r[i]
        if not s then return false end
        if s.ring then return owner:Run(Switch, s.ring) end
        if not s.attr then owner:Run(Close); return false end
        for k = 1, #ATTRS do self:SetAttribute(ATTRS[k], nil) end
        for k, v in pairs(s.attr) do self:SetAttribute(k, v) end
        self:SetAttribute("useOnKeyDown", down and true or false)
        owner:Run(Close, i)
        return "LeftButton"
    ]==]

    Switch = [==[
        local rid = ...
        local r = RINGS[rid]
        if not r or r.n == 0 or rid == active then return false end
        stack[#stack + 1] = active
        active, sticky = rid, true
        stickyPick, aimArmed, aimMax, aimLast = nil, false, 0, nil
        owner:Run(SetKeys)
        owner:CallMethod("OnRingSwitch", rid, false)
        return false
    ]==]

    Back = [==[
        local n = #stack
        if n == 0 then return owner:Run(Close) end
        active, sticky = stack[n], true
        stack[n] = nil
        stickyPick, aimArmed, aimMax, aimLast = nil, false, 0, nil
        owner:Run(SetKeys)
        owner:CallMethod("OnRingSwitch", active, true)
    ]==]

    -- A layer button held (y<id>): that ring takes over; let go: back to the opening ring.
    Layer = [==[
        local cid, down = ...
        if not layerRoot then return end
        local target = down and cid or layerRoot
        if not down and active ~= cid then return end
        local r = RINGS[target]
        if not r or r.n == 0 or target == active then return end
        wipe(stack)
        active = target
        stickyPick, aimArmed, aimMax, aimLast = nil, false, 0, nil
        owner:Run(SetKeys)
        owner:CallMethod("OnRingSwitch", target, not down)
    ]==]

    -- The open ring is this one, or was opened from it (nested rings).
    Owns = [==[
        local rid = ...
        if active == rid or layerRoot == rid then return true end
        for k = 1, #stack do
            if stack[k] == rid then return true end
        end
        return false
    ]==]
]])

header:WrapScript(button, "OnClick", [[
    local b = button
    lastInput = b   -- how the ring was closed (debug log)
    local rid = tonumber(strmatch(b, "^r(%d+)$"))
    local pad = tonumber(strmatch(b, "^p(%d+)$"))
    -- /click HaloButton t<id> LeftButton true (the ring's macro, e.g. on a gamepad bar
    -- combination slot): a macro sends no release, so it always works like tap mode.
    local macroTap = tonumber(strmatch(b, "^t(%d+)$"))
    -- Tap mode (gamepad buttons): a tap opens the ring and it stays open; the next tap
    -- uses the pointed slice, or closes the ring when nothing is pointed. Release does nothing.
    -- Another ring's button opens that ring instead.
    if macroTap or (pad and OPT.padTap) then
        pad = macroTap or pad
        if not down then return false end
        if active and owner:Run(Owns, pad) then
            -- Stick released: Use. Letting go of the stick is what uses a slice, so the ring's
            -- button closes it without using anything: the way to cancel after pointing.
            if OPT.padRelease then owner:Run(Close); return false end
            local i = owner:Run(Pick)
            if i then return owner:RunFor(self, Use, i, true) end
            owner:Run(Close)
            return false
        end
        if owner:Run(Open, pad) then
            sticky = true
            owner:CallMethod("OnRingSticky", pad)
        end
        return false
    end
    rid = rid or pad
    if rid then
        if down then
            -- The ring's key again closes a ring that stays open; another ring's key opens
            -- that ring (Open closes the current one).
            if active and sticky and owner:Run(Owns, rid) then owner:Run(Close); return false end
            if owner:Run(Open, rid) then held = rid end
            return false
        end
        if held ~= rid or not active then return false end
        held = nil
        local i = owner:Run(Pick)
        owner:CallMethod("OnRingRelease", i or 0)
        -- Gamepad hold: let go with nothing pointed closes (tap mode keeps rings open).
        if not i and pad then
            owner:Run(Close)
            return false
        end
        if not i then
            sticky = true
            owner:CallMethod("OnRingSticky", active)
            return false
        end
        return owner:RunFor(self, Use, i, false)
    end
    if not active then return false end
    if b == "LeftButton" then
        if down then return false end
        local i = owner:Run(Pick)
        if not i then owner:Run(Close); return false end -- click in the middle closes
        return owner:RunFor(self, Use, i, false)
    elseif b == "use" then
        if not down then return false end
        local i = owner:Run(Pick)
        if not i then return false end
        return owner:RunFor(self, Use, i, true)
    elseif b == "RightButton" or b == "back" then
        if down then owner:Run(Back) end
        return false
    elseif b == "close" then
        if down then owner:Run(Close) end
        return false
    end
    -- The pointing stick entered (down) or left (up) one of its four directions.
    local dir = strmatch(b, "^aim([udlr])$")
    if dir then
        local st = GetGamePadState()
        local s = st and st.sticks and st.sticks[OPT.stick]
        local len, x, y = s and s.len or 0, s and s.x or 0, s and s.y or 0
        -- Use on release (option): use the slice the stick pointed at once it is let go.
        -- The game sends only ONE release per press: when two directions are held (a
        -- diagonal), or after a turn around the edge, the later releases never come. So the
        -- decision is made on this release:
        --   turning  the stick is still out at the edge (0.9+, near the furthest it went)
        --            and has moved on since the last press: it points at another slice;
        --   let go   anything else: on its way back to the middle, or a key flickering at
        --            the edge of its zone while the stick is held still on the slice.
        -- The key release is a real input, so the button can still cast or use an item
        -- here, in combat too.
        local turning = false
        if not down then
            local mx, my = x - aimPX, y - aimPY
            turning = len >= 0.9 and len >= aimMax - 0.12
                and (aimLast ~= dir or mx * mx + my * my > 0.0225)
        end
        if down then
            aimHeld[dir], aimArmed = true, true
            aimLast, aimPX, aimPY = dir, x, y
        else
            aimHeld[dir] = nil
        end
        if len > aimMax then aimMax = len end
        -- The direction is read when a key is pressed (the stick just crossed the game's
        -- threshold) and when one is let go while the stick is still well out (turning
        -- around the edge), never on the way back to the middle, where it can drift.
        if down or len >= 0.5 then owner:Run(Aim) end
        local held = (aimHeld.u and "u" or "") .. (aimHeld.d and "d" or "") .. (aimHeld.l and "l" or "") .. (aimHeld.r and "r" or "")
        local result, use = "", nil
        if not down and OPT.padRelease then
            local r = RINGS[active]
            if turning and held ~= "" then result = "still pointing: turning (" .. held .. ")"
            elseif not aimArmed then result = "not used: no pointing since the ring opened"
            elseif not (stickyPick and r and stickyPick <= r.n) then result = "not used: no slice"
            else result, use = "use slice " .. stickyPick, stickyPick end
        end
        owner:CallMethod("OnAim", dir, down, len, x, y, result)
        if use then
            aimArmed = false
            return owner:RunFor(self, Use, use, false)
        end
        return false
    end
    local layer = tonumber(strmatch(b, "^y(%d+)$"))
    if layer then
        owner:Run(Layer, layer, down)
        return false
    end
    local si = tonumber(strmatch(b, "^s(%d+)$"))
    if si then
        if not down then return false end
        return owner:RunFor(self, Use, si, true)
    end
    if down then owner:Run(Close) end
    return false
]])

-- Sticky selection: the visible ring tells the secure side which slice the stick last
-- pointed at. Only possible out of combat (Execute on a protected frame).
function H.SetStickyPick(i)
    if InCombatLockdown() then return false end
    header:Execute("stickyPick = " .. (tonumber(i) and tostring(math.floor(i)) or "nil"))
    return true
end

-- Callbacks into the visible ring -----------------------------------------------------------
function header:OnRingOpen(rid, x, y) H.Fire("open", rid, x, y) end
function header:OnRingClose(rid, used, input, aims) H.Fire("close", rid, used, input, aims) end
function header:OnRingSwitch(rid, back) H.Fire("switch", rid, back) end
function header:OnRingSticky(rid) H.Fire("sticky", rid) end
function header:OnStickyPick(i) H.Fire("stickypick", i) end
function header:OnAim(dir, down, len, x, y, result) H.Fire("aim", dir, down, len, x, y, result) end
-- /halo debug: what the ring key release saw (stick tilt, the slice chosen).
function header:OnRingRelease(slice)
    if not H.debug then return end
    local st = C_GamePad and C_GamePad.GetDeviceMappedState and C_GamePad.GetDeviceMappedState()
    local parts = {}
    for i, stick in ipairs(st and st.sticks or {}) do
        local name = C_GamePad.StickIndexToConfigName and C_GamePad.StickIndexToConfigName(i - 1) or i
        parts[#parts + 1] = ("%s %.2f (x %.2f y %.2f)"):format(tostring(name), stick.len or 0, stick.x or 0, stick.y or 0)
    end
    H.Log(("release: slice %s | reading stick %s | %s"):format(slice > 0 and slice or "none (ring stays open)",
        tostring(H.stickName), #parts > 0 and table.concat(parts, "; ") or "no gamepad state"))
end

function header:OnRingEmpty(rid)
    local ring = H.GetRing(rid)
    UIErrorsFrame:AddMessage((ring and ring.name or "Ring") .. ": empty", 1, 0.82, 0)
end

-- Compile -------------------------------------------------------------------------------------

-- Ring radius in ring units; shared with Ring.lua so pointing matches the picture.
-- spread (per-ring Spacing) only moves slices apart; the middle dead zone uses spread 1.
H.SPREAD_MIN, H.SPREAD_MAX = 0.8, 2
function H.RingRadius(n, spread)
    local spacing = 50
    local r = math.max(58, math.floor(n * spacing / (2 * math.pi) + 0.5))
    spread = math.max(H.SPREAD_MIN, math.min(H.SPREAD_MAX, tonumber(spread) or 1))
    return math.floor(r * spread + 0.5)
end

-- A saved screen position (fractions 0..1), clamped so the ring stays on screen.
function H.Position(key)
    local p = H.db.options[key]
    local default = key == "padPos" and { 0.78, 0.42 } or { 0.5, 0.5 }
    if type(p) ~= "table" or not tonumber(p[1]) or not tonumber(p[2]) then return default end
    local function c(v) return math.max(0.05, math.min(0.95, tonumber(v))) end
    return { c(p[1]), c(p[2]) }
end

local function Q(v)
    if type(v) == "number" then return tostring(v) end
    if type(v) == "boolean" then return v and "true" or "false" end
    return string.format("%q", tostring(v))
end

-- Index of a stick ("Movement" / "Camera") in GetGamePadState().sticks. Shared with Ring.lua.
local function StickIndex(name)
    if C_GamePad and C_GamePad.StickIndexToConfigName then
        for i = 1, 4 do
            local ok, config = pcall(C_GamePad.StickIndexToConfigName, i - 1)
            if ok and config == name then return i end
        end
    end
    return name == "Movement" and 1 or 2
end
H.StickIndex = StickIndex

function H.IsGamepadInterface()
    return C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle and Enum and Enum.InputDeviceInterfaceType
        and C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad or false
end

local function KeyOrNil(key)
    return type(key) == "string" and key ~= "" and key or nil
end

-- A gamepad chord "PADRSTICK+PADLSHOULDER": the ring on the first button, the second held.
function H.SplitChord(key)
    if type(key) ~= "string" then return nil end
    return key:match("^([^+]+)%+([^+]+)$")
end

-- The ring's keys, keyboard and gamepad, without holes. (ipairs({ key, padKey }) stops at
-- the first nil, which left gamepad-only rings unbound.)
local function RingKeys(ring)
    local out = {}
    if KeyOrNil(ring.key) then out[#out + 1] = ring.key end
    if KeyOrNil(ring.padKey) then out[#out + 1] = ring.padKey end
    return out
end
H.RingKeys = RingKeys

local CONFIRM = { "PAD1", "PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER" }
local EMULATE = { SHIFT = "GamePadEmulateShift", CTRL = "GamePadEmulateCtrl", ALT = "GamePadEmulateAlt" }

-- "SHIFT"/"CTRL"/"ALT" if this gamepad button is set as that modifier in the game's settings.
function H.EmulatedModifier(button)
    for mod, cvar in pairs(EMULATE) do
        local set = GetCVar and GetCVar(cvar)
        if set and set ~= "" and set ~= "NONE" and set == button then return mod end
    end
end

local function BaseKey(key) return type(key) == "string" and key:match("([^-]+)$") or nil end

local function ConfirmButtons(ring)
    local skip = {}
    for _, key in ipairs(RingKeys(ring)) do
        if type(key) == "string" then
            skip[BaseKey(key)] = true
            for mod, cvar in pairs(EMULATE) do
                if key:find(mod .. "-", 1, true) then
                    local button = GetCVar and GetCVar(cvar)
                    if button and button ~= "" and button ~= "NONE" then skip[button] = true end
                end
            end
        end
    end
    local out = {}
    for _, button in ipairs(CONFIRM) do
        if not skip[button] then out[#out + 1] = button end
    end
    return out
end
H.ConfirmButtons = ConfirmButtons

local function Modifiers(key)
    local mods = {}
    if type(key) == "string" then
        local prefix = key:match("^(.*%-).+$")
        if prefix then mods[1] = prefix end
    end
    return mods
end

H.live = {}          -- ring id -> concrete slices, as compiled (what the ring shows)
H.stickName = "Camera"

-- The ring keys of the last build: key -> "r<id>" (keyboard/mouse) or "p<id>" (gamepad).
local ringBindings = {}
local function ApplyRingKeys()
    ClearOverrideBindings(binds)
    local count = 0
    for key, click in pairs(ringBindings) do
        SetOverrideBindingClick(binds, true, key, "HaloButton", click)
        count = count + 1
    end
    return count
end

-- Blizzard's gamepad interface binds its own core actions (ping on R3, autorun on L3, the two
-- menu buttons) as priority override bindings owned by UIParent: at login, at a moment that
-- varies, and again whenever one of its gamepad panels closes. On a button with two such
-- bindings the most recent one wins, so a ring on R3 could lose it after a reload until the
-- next rebuild. Put the ring keys back on top right after Blizzard binds one of them (its
-- in-panel bindings use SetOverrideBindingClick and are left alone). Binding is blocked in
-- combat, so a rebind there waits for the end of the fight.
local reassertQueued = false
local function ReassertRingKeys()
    reassertQueued = false
    H.OutOfCombat("ringKeys", function()
        -- Only when Blizzard really took one (every rebind makes the game update all bars).
        local taken
        for key, click in pairs(ringBindings) do
            if GetBindingAction and GetBindingAction(key, true) ~= "CLICK HaloButton:" .. click then taken = key; break end
        end
        if not taken then return end
        local count = ApplyRingKeys()
        if H.debug then H.Log(("Blizzard took %s: %d ring keys put back on top"):format(taken, count)) end
    end)
end
hooksecurefunc("SetOverrideBinding", function(owner, _, key, action)
    if owner ~= UIParent or type(action) ~= "string" or action == "" or not ringBindings[key] then return end
    if not reassertQueued then
        reassertQueued = true
        C_Timer.After(0, ReassertRingKeys)
    end
end)

function H.Compile()
    if InCombatLockdown() then H.OutOfCombat("compile", H.RunCompile); return end
    -- Never swap a ring's contents while it is open: what you see is what you use.
    local ringState = H.RingState
    local ringOpen = ringState and ringState.phase ~= nil and ringState.phase ~= "close"
    if button:IsShown() or ringOpen then
        H.compileInfo.waiting = true
        C_Timer.After(0.5, H.RequestCompile)
        return
    end
    H.compileInfo.waiting = nil
    local o = H.db.options
    local scale = tonumber(o.scale) or 1
    H.stickName = o.stick == "left" and "Movement" or "Camera"
    local lines = {
        "wipe(RINGS)",
        ("OPT.at = %s; OPT.padUI = %s; OPT.padX = %s; OPT.padY = %s; OPT.cX = %s; OPT.cY = %s; OPT.stick = %d; OPT.padDead = 0.5; OPT.numbers = %s; OPT.padTap = %s; OPT.padRelease = %s; OPT.stickKeys = %s"):format(
            Q(o.openAt), Q(H.IsGamepadInterface()), Q(H.Position("padPos")[1]), Q(H.Position("padPos")[2]),
            Q(H.Position("centerPos")[1]), Q(H.Position("centerPos")[2]), StickIndex(H.stickName),
            Q(o.numberKeys == true), Q(o.padMode == "tap"),
            Q(H.StickRelease() == "use"), Q(o.stick == "left" and "PADLSTICK" or "PADRSTICK")),
        "local r, s",
    }
    wipe(H.live)
    wipe(ringBindings)
    -- Chord rings: base button -> { second button -> ring id }. Not bound themselves; the
    -- ring on the base button switches to them while it is open.
    local chords = {}
    for _, ring in ipairs(H.db.rings) do
        local base, second = H.SplitChord(ring.padKey)
        if base and H.RingActiveHere(ring) then
            chords[base] = chords[base] or {}
            chords[base][second] = ring.id
        end
    end
    for _, ring in ipairs(H.db.rings) do
        if H.RingActiveHere(ring) then
            local slices = H.ExpandRing(ring)
            H.live[ring.id] = slices
            local n = #slices
            local key, padKey = KeyOrNil(ring.key), KeyOrNil(ring.padKey)
            local chord = H.SplitChord(padKey) ~= nil
            if chord then padKey = nil end
            local dead = math.min(40, math.max(14, H.RingRadius(n) * scale * 0.4))
            local mods = {}
            for _, m in ipairs(Modifiers(key)) do mods[#mods + 1] = Q(m) end
            for _, m in ipairs(Modifiers(padKey)) do mods[#mods + 1] = Q(m) end
            lines[#lines + 1] = ("r = newtable(); RINGS[%d] = r; r.n = %d; r.dead = %s; r.mods = newtable(%s)"):format(
                ring.id, n, Q(dead), table.concat(mods, ","))
            -- Gamepad confirm/cancel, unless the ring itself opens on that button.
            -- Confirm buttons: A, the shoulders and the triggers, except the ring's own key
            -- and any trigger set as a Shift/Ctrl/Alt modifier that the ring's key uses.
            local confirm = {}
            for _, button in ipairs(ConfirmButtons(ring)) do confirm[#confirm + 1] = Q(button) end
            lines[#lines + 1] = "r.confirm = newtable(" .. table.concat(confirm, ",") .. ")"
            if padKey ~= "PAD2" and key ~= "PAD2" then lines[#lines + 1] = 'r.padCancel = "PAD2"' end
            local layers = padKey and chords[padKey]
            if layers then
                lines[#lines + 1] = "r.layers = newtable()"
                for second, cid in pairs(layers) do
                    lines[#lines + 1] = ("r.layers[%s] = %d"):format(Q(second), cid)
                end
            end
            for i, s in ipairs(slices) do
                lines[#lines + 1] = ("s = newtable(); r[%d] = s"):format(i)
                if s.kind == "ring" then
                    lines[#lines + 1] = ("s.ring = %d"):format(tonumber(s.ringID) or 0)
                else
                    local attr = H.SliceAttributes(s)
                    if attr then
                        lines[#lines + 1] = "s.attr = newtable()"
                        for k, v in pairs(attr) do
                            lines[#lines + 1] = ("s.attr[%s] = %s"):format(Q(k), Q(v))
                        end
                    end
                end
            end
            -- Bound even while empty, so the key never falls back to its normal action.
            -- The gamepad button sends "p<id>" (it may use tap mode), keyboard/mouse "r<id>".
            if key then ringBindings[key] = "r" .. ring.id end
            if padKey and padKey ~= key then ringBindings[padKey] = "p" .. ring.id end
        end
    end
    local bound = ApplyRingKeys()
    header:Execute(table.concat(lines, "\n"))
    button:SetScale(UIParent:GetEffectiveScale())
    if H.debug then H.Log(("rings built: %d rings, %d keys bound"):format(#H.db.rings, bound)) end
    H.Fire("compiled")
end

-- Key conflicts ---------------------------------------------------------------------------------
-- Another addon's top-priority override on the same key beats ours (BindCards does this for
-- its routed keys). GetBindingAction(key, true) returns what the key really does now.
local function DescribeAction(action)
    local frameName = action:match("^CLICK ([^:]+):")
    if frameName then
        if frameName:match("^BindCards") then return "BindCards" end
        return frameName
    end
    local spell = action:match("^SPELL (.+)$")
    if spell then return spell end
    return _G["BINDING_NAME_" .. action] or action
end

-- nil when the key opens this ring; otherwise who has it.
function H.KeyTakenBy(key, ringID)
    if type(key) ~= "string" or key == "" or not GetBindingAction then return nil end
    if H.SplitChord(key) then return nil end   -- chords are not bindings
    local action = GetBindingAction(key, true) or ""
    local own = tonumber(action:match("^CLICK HaloButton:[rp](%d+)$"))
    if own == ringID then return nil end
    local other = own
    if other then
        local ring = H.GetRing(other)
        return "Halo ring " .. (ring and ring.name or other)
    end
    if action == "" then return nil end
    -- Blizzard's own gamepad bindings (InputFunctionBindingButton_*, the gamepad binding
    -- stack) report as the key's action, but Halo's override wins over them in practice.
    if H.IsBlizzardGamepadAction(action) then return nil end
    return DescribeAction(action)
end

-- Blizzard's gamepad core actions (see above): Halo puts its ring keys back over them.
local BLIZZARD_CORE_ACTIONS = { TOGGLEPINGSYSTEM = true, TOGGLEAUTORUN = true, OPENRADIAL = true, TOGGLEUIFOCUS = true }

function H.IsBlizzardGamepadAction(action)
    if type(action) ~= "string" then return false end
    if BLIZZARD_CORE_ACTIONS[action] then return true end
    local frameName = action:match("^CLICK ([^:]+):")
    return frameName ~= nil and (frameName:match("^InputFunctionBindingButton") or frameName:match("^InputButtonBinding")) ~= nil
end

local warned = {}
local function WarnConflicts()
    if not H.db then return end
    for _, ring in ipairs(H.db.rings) do
        if H.RingActiveHere(ring) then
            for _, key in ipairs(RingKeys(ring)) do
                local owner = H.KeyTakenBy(key, ring.id)
                local tag = key and (key .. ">" .. tostring(owner))
                if owner and not warned[tag] then
                    warned[tag] = true
                    H.Print(("%s taken by %s: %s won't open")
                        :format(GetBindingText and GetBindingText(key) or key, owner, ring.name))
                end
            end
        end
    end
end
-- Other addons often rebind right after login or a form change; look a moment later.
H.On("compiled", function() C_Timer.After(2, WarnConflicts) end)

-- Interface style, UI scale and Blizzard's own gamepad bindings all change what we need.
local watch = CreateFrame("Frame")
-- (Not UPDATE_BINDINGS: our own override bindings fire it, which would loop.)
for _, event in ipairs({ "INPUT_DEVICE_INTERFACE_TRANSITION", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_MOUNT_DISPLAY_CHANGED" }) do
    pcall(watch.RegisterEvent, watch, event)
end
watch:SetScript("OnEvent", function(_, event)
    if not H.db then return end
    H.RequestCompile()
    if event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        -- Blizzard installs its gamepad bindings during the switch; bind again after it.
        C_Timer.After(1, H.RequestCompile)
    end
end)
-- Only the options the secure side reads need a rebuild (the others are drawing only, and
-- the rune colour picker fires many times a second).
local SECURE_OPTIONS = { openAt = true, padPos = true, centerPos = true, stick = true, numberKeys = true,
    padMode = true, padRelease = true, scale = true }
H.On("options", function(key)
    if key == nil or SECURE_OPTIONS[key] then H.RequestCompile() end
end)

-- /halo status: build results, and each ring's slices and keys.
function H.Status()
    H.Print("version", H.version, "| gamepad interface:", H.IsGamepadInterface() and "yes" or "no",
        "| stick:", H.stickName, "| in combat:", InCombatLockdown() and "yes" or "no")
    local info = H.compileInfo or {}
    H.Print(("builds: %d tried, %d ok%s | catcher shown: %s"):format(info.runs or 0, info.ok or 0,
        info.waiting and ", waiting for the open ring to close" or "", button:IsShown() and "yes" or "no"))
    if info.lastError then H.Print("|cffff6040last build error:|r " .. info.lastError) end
    for _, ring in ipairs(H.db.rings) do
        local live = H.live[ring.id]
        local notes = {}
        for _, key in ipairs(RingKeys(ring)) do
            local owner = H.KeyTakenBy(key, ring.id)
            if owner then notes[#notes + 1] = key .. " taken by " .. owner end
        end
        H.Print(("  %s: %d slices, key %s, gamepad %s%s%s"):format(ring.name, live and #live or 0,
            ring.key or "-", ring.padKey or "-", H.RingActiveHere(ring) and "" or " (other character)",
            #notes > 0 and (" |cffff6040(" .. table.concat(notes, "; ") .. ")|r") or ""))
    end
end
