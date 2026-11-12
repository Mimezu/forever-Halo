-- The visible ring. It only follows the secure core (Secure.lua): it opens, points and
-- closes when the core says so, and mirrors the core's pointing rules so the highlighted
-- slice is always the one that will be used.
--
-- Look: one of the styles in Skins.lua (per ring, or the Options default), all drawn with
-- Forever's own art. Parent is nil so it still works with the interface hidden (Alt-Z)
-- and in Frame Gambit's Cinematic Mode.

local _, H = ...

local CLOSE_TIME = 0.14
local PAD_DEAD = 0.5

local function Sound(name)
    if H.Option("sounds") and SOUNDKIT and SOUNDKIT[name] then PlaySound(SOUNDKIT[name], "SFX") end
end

-- Frames -----------------------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "HaloRing", nil)
anchor:SetFrameStrata("FULLSCREEN_DIALOG")
anchor:SetFrameLevel(20)
anchor:SetSize(1, 1)
anchor:EnableMouse(false)
anchor:Hide()

local ring = CreateFrame("Frame", nil, anchor)
ring:SetPoint("CENTER")
ring:SetSize(1, 1)

local pointer = CreateFrame("Frame", nil, ring)
pointer:SetFrameLevel(ring:GetFrameLevel() + 30)
local pointerTexture = pointer:CreateTexture(nil, "OVERLAY")
pointerTexture:SetAllPoints()
pointer:Hide()

local label = ring:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
label:SetShadowOffset(1, -1)
label:SetShadowColor(0, 0, 0, 1)
local hint = ring:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetShadowOffset(1, -1)
hint:SetShadowColor(0, 0, 0, 1)
hint:SetPoint("TOP", label, "BOTTOM", 0, -2)

-- The pointed slice's name, in the middle of the ring; the ring's own name when nothing is pointed.
local centerFrame = CreateFrame("Frame", nil, ring)
centerFrame:SetAllPoints(ring)
centerFrame:SetFrameLevel(ring:GetFrameLevel() + 40)
local centerText = centerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
centerText:SetPoint("CENTER")
centerText:SetJustifyH("CENTER")
centerText:SetJustifyV("MIDDLE")
centerText:SetWordWrap(true)
if centerText.SetMaxLines then centerText:SetMaxLines(3) end
local centerBase = { file = nil, size = 12, flags = nil }

local function StyleCenterText(skin, r)
    local c = skin.centerText or {}
    centerText:SetFontObject(c.font or "GameFontHighlight")
    local file, size, flags = centerText:GetFont()
    if c.outline then flags = c.outline end
    centerBase.file, centerBase.size, centerBase.flags = file, size or 12, flags
    if file then centerText:SetFont(file, centerBase.size, flags) end
    local cr, cg, cb = 1, 1, 1
    if type(c.color) == "function" then cr, cg, cb = c.color()
    elseif c.color then cr, cg, cb = c.color[1], c.color[2], c.color[3] end
    centerText:SetTextColor(cr, cg, cb)
    local sh, off = c.shadow or { 0, 0, 0, 1 }, c.offset or { 1, -1 }
    centerText:SetShadowColor(sh[1], sh[2], sh[3], sh[4] or 1)
    centerText:SetShadowOffset(off[1], off[2])
    -- The box fills the free space inside the icons (slots sit at the slot radius and
    -- are ~40px wide), so it grows with bigger rings and Spacing.
    centerText:SetWidth(math.max(64, 2 * (H.RingSkins.SlotRadius(skin, r) - 20)))
end

-- Long names: wrap to up to three lines, then step the size down until nothing is cut.
local function SetCenterName(text)
    centerText:SetText(text or "")
    if not (text and text ~= "" and centerBase.file) then return end
    local size = centerBase.size
    centerText:SetFont(centerBase.file, size, centerBase.flags)
    while centerText.IsTruncated and centerText:IsTruncated() and size > 8 do
        size = size - 1
        centerText:SetFont(centerBase.file, size, centerBase.flags)
        centerText:SetText(text)
    end
end

local slots = {}
local function Slot(i)
    if slots[i] then return slots[i] end
    local slot = CreateFrame("Frame", nil, ring)
    H.RingSkins.BuildSlotKit(slot)
    local top = slot.top
    slot.count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    slot.count:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", 3, -2)
    slot.key = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    slot.key:SetAlpha(0.8)
    slot.nested = top:CreateTexture(nil, "OVERLAY", nil, 2)
    slot.nested:SetSize(14, 14)
    slot.nested:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", 2, -2)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-icon-forwardarrow") then
        slot.nested:SetAtlas("common-icon-forwardarrow")
    else
        slot.nested:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    end
    slots[i] = slot
    return slot
end

-- State ----------------------------------------------------------------------------------------
local state = {
    rid = nil, slices = nil, n = 0, radius = 60,
    phase = nil, t = 0, used = nil,
    pick = nil, pointerAngle = nil, sticky = false,
    scales = {}, animScale = {}, applied = {},
}
H.RingState = state

local function StickIndex() return H.StickIndex(H.stickName) end

local function SliceAngle(i, n) return (i - 1) * 2 * math.pi / n end

-- Same rule as the secure Pick: stick first, then the mouse (never in the gamepad UI).
-- "Stick released: Keep / Use" (gamepad option): the slice the stick last pointed at stays
-- selected when the stick returns to centre (Use then uses it right away). Out of combat
-- the visible ring tells the secure side; in combat the secure side keeps it from the
-- stick's direction keys (see below).
local function StickyActive()
    return not InCombatLockdown()
end

-- In combat the secure side keeps the selection itself (from the stick's direction keys) and
-- tells us which slice it stored, so the ring shows exactly what will be used.
H.On("stickypick", function(i)
    state.stickyPick = i
    if H.debug then H.Log("secure sticky pick from stick direction: slice " .. tostring(i)) end
end)
-- /halo debug: every stick direction key, with where the stick was (shows the threshold at
-- which the game presses and lets go of these keys).
H.On("aim", function(dir, down, len, x, y, result)
    if H.debug then
        H.Log(("stick key %s %s | stick %.2f (x %.2f y %.2f) | slice %s | %s | combat %s"):format(
            tostring(dir), down and "down" or "up", len or 0, x or 0, y or 0, tostring(state.stickyPick),
            result ~= "" and tostring(result) or "-", tostring(InCombatLockdown())))
    end
end)

-- The stick's direction "buttons" (PADRSTICKUP...) only exist when the game's
-- GamePadStickAxisButtons setting is on (off by default). Halo turns it on (out of combat).
-- The game only turns the direction keys on when the setting changes while it runs: after
-- a restart it reads 1 from the config and still sends nothing (seen in 0.9.8: the stick
-- moved, zero direction keys). So at login and when a gamepad connects, switch it off and
-- on again ("wake").
local wakeStickButtons = false
local stickSuspended = false   -- a Blizzard radial has the setting off for now (see SyncRadials)
local function ApplyStickButtons(wake)
    wakeStickButtons = wakeStickButtons or wake == true
    H.OutOfCombat("stickButtons", function()
        -- A Blizzard radial is open: SyncRadials has the setting off and puts it back on close.
        if stickSuspended then return end
        local woke = false
        if wakeStickButtons or GetCVar("GamePadStickAxisButtons") ~= "1" then
            pcall(SetCVar, "GamePadStickAxisButtons", "0")
            pcall(SetCVar, "GamePadStickAxisButtons", "1")
            woke = true
        end
        wakeStickButtons = false
        if H.debug then
            H.Log(("stick direction buttons (GamePadStickAxisButtons): %s%s"):format(
                tostring(GetCVar("GamePadStickAxisButtons")), woke and " (switched off and on)" or ""))
        end
    end)
end
H.On("login", function() ApplyStickButtons(true) end)
H.On("options", function(key) if key == nil or key == "padRelease" then ApplyStickButtons() end end)
-- Blizzard's gamepad radials (class and pet flyouts, the start menu) pick with the right stick
-- and close on ANY gamepad button press. With the stick direction keys on, the first tilt is a
-- button press, so the radial closes at once. So while one of them is open (out of combat) the
-- setting is switched off, and back on when it closes. In combat the setting can't be changed
-- reliably, so those radials stay unusable there while Keep / Use is on.
local RADIALS = { "GamepadSpellFlyout", "GamepadPetActionFlyout", "GamepadPetSpellFlyout", "GamepadRadial" }
local radialHooked = {}
local function RadialShown()
    for _, name in ipairs(RADIALS) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end
local function SyncRadials()
    local shown = RadialShown()
    if shown and not stickSuspended then
        if InCombatLockdown() or GetCVar("GamePadStickAxisButtons") ~= "1" then return end
        if pcall(SetCVar, "GamePadStickAxisButtons", "0") then
            stickSuspended = true
            if H.debug then H.Log("Blizzard radial opened: stick direction buttons off until it closes") end
        end
    elseif not shown and stickSuspended then
        H.OutOfCombat("stickButtonsResume", function()
            if RadialShown() or not stickSuspended then return end
            stickSuspended = false
            ApplyStickButtons()
            if H.debug then H.Log("Blizzard radial closed: stick direction buttons back to " .. tostring(GetCVar("GamePadStickAxisButtons"))) end
        end)
    end
end
H.SyncRadials = SyncRadials   -- (tests)
local function HookRadials()
    for _, name in ipairs(RADIALS) do
        local f = _G[name]
        if f and not radialHooked[f] and f.HookScript then
            radialHooked[f] = pcall(function()
                f:HookScript("OnShow", SyncRadials)
                f:HookScript("OnHide", SyncRadials)
            end)
        end
    end
end
H.HookRadials = HookRadials   -- (tests)
H.On("login", HookRadials)

local padEvents = CreateFrame("Frame")
pcall(padEvents.RegisterEvent, padEvents, "GAME_PAD_CONNECTED")
pcall(padEvents.RegisterEvent, padEvents, "ADDON_LOADED")   -- the radials live in load-on-demand Blizzard addons
padEvents:SetScript("OnEvent", function(_, event)
    if event == "ADDON_LOADED" then HookRadials()
    elseif H.db then ApplyStickButtons(true) end
end)

local PickLive
local function PickNow()
    local i, fromStick = PickLive()
    if i and fromStick then
        -- Out of combat, tell the secure side at once (exact, continuous).
        if StickyActive() and state.stickyPick ~= i and H.SetStickyPick(i) then state.stickyPick = i end
    elseif not i and state.stickyPick then
        return state.stickyPick
    end
    return i
end

function PickLive()
    local n = state.n
    if n == 0 then return nil end
    local dx, dy
    -- IsEnabled() can be false on Forever in the gamepad interface: accept either.
    if C_GamePad and C_GamePad.GetDeviceMappedState and ((C_GamePad.IsEnabled and C_GamePad.IsEnabled()) or state.padUI) then
        local st = C_GamePad.GetDeviceMappedState()
        local s = st and st.sticks and st.sticks[state.stickIndex]
        if s and s.len and s.len >= PAD_DEAD then dx, dy = s.x, s.y end
    end
    local fromStick = dx ~= nil
    if not dx then
        if state.padUI then return nil end
        local x, y = GetCursorPosition()
        local e = anchor:GetEffectiveScale()
        local ax, ay = anchor:GetCenter()
        if not ax then return nil end
        dx, dy = x / e - ax, y / e - ay
        if dx * dx + dy * dy < state.dead * state.dead then return nil end
    end
    local full, seg = 2 * math.pi, 2 * math.pi / n
    local i = math.floor(((math.atan2(dx, dy) + seg / 2) % full) / seg) + 1
    if i > n then i = 1 end -- float rounding right at the top
    return i, fromStick
end

local function UpdateSlotState(slot, s)
    local count, start, duration, usable, active = H.SliceState(s)
    count = H.Plain(count)
    slot.count:SetText(count and tostring(count) or "")
    if start and duration then
        pcall(slot.cooldown.SetCooldown, slot.cooldown, start, duration)
    else
        slot.cooldown:Clear()
    end
    local dim = usable == false
    slot.icon:SetDesaturated(dim)
    slot.icon:SetVertexColor(dim and 0.6 or 1, dim and 0.6 or 1, dim and 0.6 or 1)
    slot.active:SetShown(active == true)
end

local function RefreshStates()
    if not state.slices then return end
    for i, s in ipairs(state.slices) do
        if slots[i] then UpdateSlotState(slots[i], s) end
    end
end

local function Layout()
    local n = state.n
    local ringData = H.GetRing(state.rid)
    local skin = H.RingSkins.ForRing(ringData)
    state.skin = skin
    state.radius = H.RingRadius(n, ringData and ringData.spread)
    local showKeys = H.Option("slotNumbers") and H.Option("numberKeys") and not state.padUI
    for i = 1, math.max(n, #slots) do
        local slot = Slot(i)
        local s = state.slices[i]
        if s then
            H.RingSkins.ApplySlot(slot, skin)
            local name, icon = H.SliceInfo(s)
            slot.icon:SetTexture(icon)
            slot.name = name
            slot.nested:SetShown(s.kind == "ring")
            local co = skin.countOffset or { 3, -2 }
            slot.count:ClearAllPoints()
            slot.count:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", co[1], co[2])
            slot.key:SetFontObject(skin.keyFont or "NumberFontNormalSmallGray")
            slot.key:ClearAllPoints()
            if skin.keyPoint == "TOPRIGHT" then
                slot.key:SetPoint("TOPRIGHT", slot.icon, "TOPRIGHT", -1, -2)
            else
                slot.key:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", -2, 3)
            end
            slot.key:SetText(showKeys and i <= 10 and tostring(i % 10) or "")
            UpdateSlotState(slot, s)
            slot.over:Hide()
            slot:SetAlpha(1)
            state.scales[i] = 1
            state.applied[i] = nil
            slot:Show()
        else
            slot:Hide()
        end
    end
    local r = state.radius
    local art = H.RingSkins.RingArt(ring, skin)
    state.art = art
    if art then
        art:Layout(r)
        H.RingSkins.ShowRingArt(art, H.Option("background") ~= false)
    end
    state.hasPointer = H.RingSkins.ApplyPointer(pointerTexture, pointer, skin)
    label:SetFontObject(skin.labelFont or "GameFontHighlight")
    StyleCenterText(skin, r)
    centerText:SetText("")
    local below
    if skin.labelBelow then
        below = skin.labelBelow(skin, r)
    else
        below = math.max(r + 30, art and art.Extent and (art:Extent(r) / 2 + 12) or 0) + (skin.labelNudge or 0)
    end
    label:ClearAllPoints()
    label:SetPoint("TOP", ring, "CENTER", 0, -below)
    pointer:Hide()
    state.pick, state.pointerAngle, state.pointerDrawn = nil, nil, nil
end

-- Slot scale, set only when it changes (SetScale re-lays out the slot and its children).
local function SetSlotScale(i, value)
    local applied = state.applied[i]
    if applied and math.abs(applied - value) < 0.0005 then return end
    state.applied[i] = value
    slots[i]:SetScale(value)
end

local function PlaceSlots(radiusFactor, angleOffset, _, perSlot)
    local r = H.RingSkins.SlotRadius(state.skin, state.radius) * radiusFactor
    for i = 1, state.n do
        local a = SliceAngle(i, state.n) + (angleOffset or 0)
        local slot = slots[i]
        slot:ClearAllPoints()
        slot:SetPoint("CENTER", ring, "CENTER", r * math.sin(a), r * math.cos(a))
        if perSlot then
            local alpha, scale = perSlot(i, state.n)
            slot:SetAlpha(alpha)
            state.animScale[i] = scale
        else
            slot:SetAlpha(1)
            state.animScale[i] = 1
        end
    end
end

local function HintText()
    if not state.sticky then return "" end
    if state.padUI then
        if H.StickRelease() == "use" then return "Release: use · B: cancel" end
        return "A: use · B: close"
    end
    return "Esc: close"
end

-- Game tooltip for the pointed slice, beside the ring (per-ring setting).
local tooltipShown = false
local function HideTooltip()
    if tooltipShown then
        tooltipShown = false
        if GameTooltip:GetOwner() == anchor then GameTooltip:Hide() end
    end
end
local function ShowTooltip(i)
    local s = state.slices and state.slices[i]
    local ringData = H.GetRing(state.rid)
    if not (s and ringData and ringData.tooltips) then HideTooltip(); return end
    GameTooltip:SetOwner(anchor, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("LEFT", ring, "CENTER", state.radius + 34, 0)
    H.SliceTooltip(s, GameTooltip)
    GameTooltip:Show()
    tooltipShown = true
end

local function SetPick(i)
    if state.pick == i then return end
    if state.pick and slots[state.pick] then slots[state.pick].over:Hide() end
    state.pick = i
    local showLabels = H.Option("labels")
    if i and slots[i] then
        slots[i].over:Show()
        label:SetText("")
        SetCenterName(showLabels and slots[i].name or "")
        hint:SetText("")
        pointer:SetShown(state.hasPointer == true)
        ShowTooltip(i)
    else
        HideTooltip()
        label:SetText("")
        SetCenterName(showLabels and state.ringName or "")
        hint:SetText(H.Option("hints") and HintText() or "")
        pointer:Hide()
    end
end

local function UpdatePointer(elapsed)
    if not state.pick then return end
    local target = SliceAngle(state.pick, state.n)
    local a = state.pointerAngle
    if not a then a = target
    else
        local diff = (target - a + math.pi) % (2 * math.pi) - math.pi
        a = math.abs(diff) < 0.0005 and target or a + diff * math.min(1, elapsed * 22)
    end
    state.pointerAngle = a
    local p = state.skin and state.skin.pointer
    if not p or state.pointerDrawn == a then return end   -- settled: nothing to move
    state.pointerDrawn = a
    local d = state.radius * (p.dist or 0.6)
    pointer:ClearAllPoints()
    pointer:SetPoint("CENTER", ring, "CENTER", d * math.sin(a), d * math.cos(a))
    -- Rotation 0 = the art's own direction; the angle a runs clockwise from the top.
    pointerTexture:SetRotation((p.rot or 0) - a)
end

local function UpdateScales(elapsed)
    local k = math.min(1, elapsed * 18)
    for i = 1, state.n do
        local goal = (i == state.pick) and (state.skin and state.skin.hoverScale or 1.12) or 1
        local cur = state.scales[i] or 1
        cur = math.abs(goal - cur) < 0.0005 and goal or cur + (goal - cur) * k
        state.scales[i] = cur
        SetSlotScale(i, cur * (state.animScale[i] or 1))
    end
end

local function PositionAnchor(fx, fy)
    local scale = UIParent:GetEffectiveScale()
    anchor:SetScale(scale)
    local ws = WorldFrame:GetEffectiveScale()
    local w, h = WorldFrame:GetWidth() * ws / scale, WorldFrame:GetHeight() * ws / scale
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", WorldFrame, "BOTTOMLEFT", fx * w, fy * h)
    ring:SetScale(tonumber(H.Option("scale")) or 1)
end

local function Load(rid)
    state.rid = rid
    state.stickyPick = nil
    state.slices = H.live[rid] or {}
    state.n = #state.slices
    state.padUI = H.IsGamepadInterface()
    state.stickIndex = StickIndex()
    local scale = tonumber(H.Option("scale")) or 1
    state.dead = math.min(40, math.max(14, H.RingRadius(state.n) * scale * 0.4))
    Layout()
    local ringData = H.GetRing(rid)
    state.ringName = ringData and ringData.name or nil
    SetCenterName(H.Option("labels") and state.ringName or "")
end

-- Core callbacks ------------------------------------------------------------------------------
H.On("open", function(rid, fx, fy)
    state.depth, state.sticky, state.used = 0, false, nil
    Load(rid)
    PositionAnchor(fx, fy)
    state.phase, state.t = "open", 0
    ring:SetAlpha(0)
    PlaceSlots(H.RingSkins.Anim(state.skin, 0))
    anchor:Show()
    hint:SetText("")
    Sound("U_CHAT_SCROLL_BUTTON")
end)

H.On("switch", function(rid, back)
    state.depth = math.max(0, (state.depth or 0) + (back and -1 or 1))
    state.sticky = true
    Load(rid)
    state.phase, state.t = "open", 0
    ring:SetAlpha(0.3)
    PlaceSlots(H.RingSkins.Anim(state.skin, 0))
    SetPick(nil)
    Sound("U_CHAT_SCROLL_BUTTON")
end)

H.On("sticky", function()
    state.sticky = true
    if not state.pick then hint:SetText(H.Option("hints") and HintText() or "") end
end)

H.On("close", function(_, used)
    HideTooltip()
    state.used = used
    state.phase, state.t = "close", 0
end)

local statesDirty = false
anchor:SetScript("OnUpdate", function(_, elapsed)
    -- Cooldown and aura events come in bursts: redraw the slot states once per frame at most.
    if statesDirty then statesDirty = false; RefreshStates() end
    if state.art and state.art.Update then state.art:Update(elapsed) end
    if state.phase == "open" then
        state.t = state.t + elapsed
        local p = math.min(1, state.t / (state.skin.openTime or 0.12))
        local radiusFactor, angleOffset, alpha, perSlot = H.RingSkins.Anim(state.skin, p)
        ring:SetAlpha(alpha)
        PlaceSlots(radiusFactor, angleOffset, alpha, perSlot)
        if p >= 1 then state.phase = "shown"; PlaceSlots(1, 0) end
    elseif state.phase == "close" then
        state.t = state.t + elapsed
        local p = math.min(1, state.t / CLOSE_TIME)
        ring:SetAlpha(1 - p)
        if state.used and slots[state.used] then
            SetSlotScale(state.used, (state.skin and state.skin.hoverScale or 1.12) + 0.25 * p)
        end
        if p >= 1 then
            state.phase = nil
            anchor:Hide()
            SetPick(nil)
            for i = 1, #slots do SetSlotScale(i, 1) end
        end
        return
    end
    SetPick(PickNow())
    UpdatePointer(elapsed)
    UpdateScales(elapsed)
end)

-- Live cooldowns and counts while the ring is shown.
local liveEvents = { "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE",
    "BAG_UPDATE_DELAYED", "SPELL_UPDATE_CHARGES", "PLAYER_TARGET_CHANGED" }
anchor:SetScript("OnShow", function(self)
    for _, event in ipairs(liveEvents) do pcall(self.RegisterEvent, self, event) end
    -- Only the player's auras (in a group UNIT_AURA fires for everyone, many times a second).
    if not (self.RegisterUnitEvent and pcall(self.RegisterUnitEvent, self, "UNIT_AURA", "player")) then
        pcall(self.RegisterEvent, self, "UNIT_AURA")
    end
end)
anchor:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
anchor:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    statesDirty = true
end)

-- Gamepad: while a ring is open the camera stick only points; walking still works.
--
-- What does not work on Forever: the camera-speed CVars (0 is refused, the value stays), and
-- an addon frame with stick input (it swallows both sticks whatever it returns).
--
-- What works: Blizzard's own stick listener, the one its start-menu radial uses
-- (inputBindingAxisListener, Blizzard_GamepadSharedUtility). With nothing in its slots it
-- passes both sticks on; a function in its camera slot ("right") takes the camera stick
-- and the movement stick still passes. Out of combat Halo switches the listener on when a
-- ring opens and off when it closes (off gives the camera back at once). It never touches
-- the slot while Blizzard is using it. Blizzard writes the slot itself before using it, so
-- its gamepad UI stays untainted.
--
-- In combat, switching the listener on or off is blocked, but showing and hiding it is not
-- (it is not a protected frame), and a hidden frame gets no stick input. So when a fight
-- starts (PLAYER_REGEN_DISABLED comes just before the lockdown) Halo switches the listener
-- on and hides it: the camera and walking are unchanged. A ring opened in combat shows it
-- (camera held); closing the ring hides it again (camera back). After the fight Halo
-- switches it off and shows it, as Blizzard had it.
local axis = _G.inputBindingAxisListener
-- nil = handled: a tilted camera stick stops here. The return to centre is NOT handled, so
-- the engine sees the stick released; claiming the centre event too left the camera stuck
-- with the listener for seconds after the ring closed.
local stickStats = { claimed = 0, centred = 0 }
local function TakeCamera(x, y)
    if x == 0 and y == 0 then
        stickStats.centred = stickStats.centred + 1
        return true
    end
    stickStats.claimed = stickStats.claimed + 1
    return nil
end
local axisHeld = false

local function AxisUsable()
    return axis and type(axis.right) == "table" and type(axis.left) == "table" and axis.EnableGamePadStick ~= nil
end

-- The listener's slot for the stick that points: "right" is the camera stick, "left" walking.
local function Side()
    return H.stickName == "Movement" and axis.left or axis.right
end
local axisHeldSide   -- the slot Halo wrote while a ring holds its stick

local function AxisOn()
    return AxisUsable() and (not axis.IsGamePadStickEnabled or axis:IsGamePadStickEnabled())
end

-- Blizzard's gamepad UI is using the listener (its radial, a flyout, chat scrolling).
local function BlizzardUsesAxis()
    local r, l = axis.right, axis.left
    return (r.func ~= nil and r.func ~= TakeCamera) or (l.func ~= nil and l.func ~= TakeCamera)
        or r.waitForCentering or l.waitForCentering or false
end

-- Every time the listener is switched on while shown, the game freezes the camera for a few
-- seconds. So out of combat Halo only switches it on when a ring opens (the camera is held
-- then anyway) and off when the ring closes; never in between (not at login, not after a
-- close). For fights it is switched on hidden (see above).
local axisHidden = false    -- hidden by Halo (in combat, between rings)
local combatArmed = false   -- switched on by Halo for this fight
local hiddenCentred         -- the listener's "centred" flag when Halo hid it
local hiddenWatch = CreateFrame("Frame")
hiddenWatch:Hide()
H.cameraWatch = hiddenWatch   -- (tests)

local function ShowAxis()
    hiddenWatch:Hide()
    if axisHidden then
        axisHidden = false
        axis:Show()
    end
end

local function HideAxis()
    if BlizzardUsesAxis() then return false end
    if not axisHidden then
        axisHidden = true
        axis:Hide()
    end
    hiddenCentred = Side().isCentered
    hiddenWatch:Show()
    return true
end

-- While Halo keeps the listener hidden in a fight: give it back to Blizzard's gamepad UI when
-- that uses it, and notice when Blizzard switched it off. A hidden frame should get no stick
-- input; if this one still does (its "centred" flag follows the stick), stop using the method.
hiddenWatch:SetScript("OnUpdate", function(self)
    if not axisHidden then self:Hide(); return end
    if BlizzardUsesAxis() then
        ShowAxis()
        if H.debug then H.Log("Blizzard is using its stick listener: shown again") end
    elseif not AxisOn() then
        combatArmed = false
        ShowAxis()
        if H.debug then H.Log("stick listener switched off by Blizzard: no camera hold for the rest of this fight") end
    elseif Side().isCentered ~= hiddenCentred then
        hiddenCentred = Side().isCentered
        if H.db and not H.db.hiddenAxisReceives then
            H.db.hiddenAxisReceives = true
            H.Print("Combat camera hold unsupported: turned off")
            H.Log("hidden stick listener still receives the camera stick: combat camera hold turned off")
        end
    end
end)

-- Stick catcher (the opt-in "Also block both sticks"): takes both sticks, so walking pauses.
-- Switched on out of combat and kept hidden (a hidden frame gets no stick input); only shown
-- while a ring is open.
local catcher = CreateFrame("Frame", "HaloStickCatcher", nil)
catcher:SetSize(1, 1)
catcher:SetPoint("BOTTOMLEFT", WorldFrame, "BOTTOMLEFT", 0, 0)
catcher:Hide()
catcher:SetScript("OnGamePadStick", function() return false end)
local catcherArmed = false

local function GamepadPresent()
    return (C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled()) or H.IsGamepadInterface()
end

local function ArmCatcher()
    H.OutOfCombat("stickCatcher", function()
        -- Only when the player asks for it (it also stops walking while a ring is open).
        local want = H.Option("blockSticks") and GamepadPresent() and true or false
        -- Leave it alone while a ring is open or the camera cooldown is running.
        local busy = state.phase ~= nil or (H.cameraRelease and H.cameraRelease:IsShown())
        if not busy or not want then catcher:Hide() end
        if catcherArmed ~= want and catcher.EnableGamePadStick and pcall(catcher.EnableGamePadStick, catcher, want) then
            catcherArmed = want
        end
    end)
end

-- Returns a short status for /halo debug.
local function HoldCamera()
    if H.Option("blockSticks") and catcherArmed then catcher:Show(); return "both sticks blocked (Options)" end
    if not H.Option("holdCamera") then return "off in Options" end
    if not GamepadPresent() then return "no gamepad detected" end
    if not AxisUsable() then return "no Blizzard listener" end
    if BlizzardUsesAxis() then return "Blizzard is using its stick listener" end
    if not AxisOn() and not InCombatLockdown() then
        pcall(axis.EnableGamePadStick, axis, true)   -- switched on only while a ring is open
    end
    if not AxisOn() then
        if H.db.hiddenAxisReceives then return "in combat: not held (turned off, see /halo camstate)" end
        return "in combat: not held (the listener was not switched on when the fight started)"
    end
    ShowAxis()
    axisHeldSide = Side()
    axisHeldSide.func = TakeCamera
    axisHeld = true
    stickStats.claimed, stickStats.centred = 0, 0
    local what = H.stickName == "Movement" and "walking stick only" or "camera stick only"
    return InCombatLockdown() and "held in combat (listener shown)" or ("held (" .. what .. ")")
end

-- Gamepad camera mode. The full-screen click catcher of an open ring can switch the gamepad
-- from free-look (stick turns the camera) to cursor control, and it stayed there after the
-- ring closed (the camera "stuck" until the mouse moved). Like OPie, remember both states
-- when a ring opens and put them back when it closes.
local padMode
local function SavePadMode()
    if padMode then return end
    padMode = {
        freelook = IsGamePadFreelookEnabled and IsGamePadFreelookEnabled(),
        cursor = IsGamePadCursorControlEnabled and IsGamePadCursorControlEnabled(),
    }
end
local function RestorePadMode()
    local saved = padMode
    padMode = nil
    if not saved then return end
    if SetGamePadCursorControl and saved.cursor ~= nil and IsGamePadCursorControlEnabled
        and IsGamePadCursorControlEnabled() ~= saved.cursor then
        pcall(SetGamePadCursorControl, saved.cursor and true or false)
    end
    if SetGamePadFreeLook and saved.freelook ~= nil and IsGamePadFreelookEnabled
        and IsGamePadFreelookEnabled() ~= saved.freelook then
        pcall(SetGamePadFreeLook, saved.freelook and true or false)
    end
end

-- Returns true when it switched Blizzard's listener off (or hid it, in combat).
local function ReleaseAxis()
    local wasHeld = axisHeld
    if axisHeld and AxisUsable() and axisHeldSide and axisHeldSide.func == TakeCamera then axisHeldSide.func = nil end
    axisHeldSide = nil
    axisHeld = false
    if not wasHeld or not AxisUsable() or BlizzardUsesAxis() then return false end
    if InCombatLockdown() then
        -- Switching it off is blocked in combat. Hide it instead (no stick input): the camera
        -- comes back, and the listener stays on for the next ring of this fight.
        HideAxis()
        if H.debug then H.Log("in combat: listener hidden to give the camera back") end
        return true
    end
    -- The engine keeps the camera stick with a listener that recently claimed it for a few
    -- seconds, unless the listener is switched off. Like Blizzard's radial: switch it off and
    -- leave it off, which gives the camera back at once. The next ring switches it on again.
    pcall(axis.EnableGamePadStick, axis, false)
    ShowAxis()
    combatArmed = false
    if H.debug then H.Log("listener switched off to give the camera back") end
    return true
end

H.On("open", function()
    SavePadMode()
    local status = HoldCamera()
    if H.debug then
        -- Who gets the stick's "up" key right now (Halo's aim key while a ring is open).
        local upKey = (H.Option("stick") == "left" and "PADLSTICK" or "PADRSTICK") .. "UP"
        H.Log(("ring opened | camera hold: %s | listener on: %s | gamepad UI: %s | in combat: %s | %s: %s | stick keys setting %s"):format(
            status, tostring(AxisOn() and true or false), tostring(H.IsGamepadInterface()), tostring(InCombatLockdown()),
            upKey, tostring(GetBindingAction and GetBindingAction(upKey, true) or "?"),
            tostring(GetCVar("GamePadStickAxisButtons"))))
    end
end)

-- Like Blizzard's radial: if the camera stick is still tilted when a ring closes, keep it
-- held until the stick is back in the centre, then let go (so the selecting flick never
-- turns the camera). 1 s at most, in case the stick is kept tilted on purpose.
local COOLDOWN, CENTRED = 1.0, 0.05
local release = CreateFrame("Frame")
release:Hide()
local function ReleaseCamera()
    release:Hide()
    catcher:Hide()
    ReleaseAxis()
    RestorePadMode()
end
H.cameraRelease = release   -- (tests)
release:SetScript("OnUpdate", function(self, elapsed)
    self.left = self.left - elapsed
    local st = C_GamePad and C_GamePad.GetDeviceMappedState and C_GamePad.GetDeviceMappedState()
    local s = st and st.sticks and st.sticks[StickIndex()]
    if self.left <= 0 or not s or (s.len or 0) < CENTRED then ReleaseCamera() end
end)
H.On("open", function() release:Hide() end)
-- Any close while the camera stick is still tilted (the thumb is usually still on it after
-- choosing) keeps the camera until the stick is centred; otherwise it comes back at once.
local function CameraStickTilted()
    local st = C_GamePad and C_GamePad.GetDeviceMappedState and C_GamePad.GetDeviceMappedState()
    local s = st and st.sticks and st.sticks[StickIndex()]
    return s ~= nil and (s.len or 0) >= CENTRED
end
H.On("close", function()
    if (catcher:IsShown() or axisHeld) and CameraStickTilted() then
        release.left = COOLDOWN
        release:Show()
    else
        ReleaseCamera()
    end
end)

-- Fight start: the last moment the listener can be switched on. Hidden, it changes nothing
-- until a ring opens.
local function ArmForCombat()
    if not (H.db and AxisUsable() and H.Option("holdCamera") and GamepadPresent()) then return end
    if H.db.hiddenAxisReceives then return end
    -- Showing and hiding it in combat needs an unprotected frame (it is one today).
    if axis.IsProtected and axis:IsProtected() then return end
    if axisHeld then combatArmed = true; return end        -- a ring holds the camera right now
    if AxisOn() or BlizzardUsesAxis() then return end      -- Blizzard's
    if InCombatLockdown() then
        if H.debug then H.Log("fight started: too late to switch the stick listener on") end
        return
    end
    HideAxis()
    pcall(axis.EnableGamePadStick, axis, true)
    if AxisOn() then combatArmed = true else ShowAxis() end
    if H.debug then H.Log("fight started: stick listener switched on, hidden: " .. tostring(combatArmed)) end
end

-- Fight end: switch it off and show it again (an open ring or its cooldown does it on close).
local function DisarmAfterCombat()
    if axisHeld or release:IsShown() then return end
    local was = combatArmed or axisHidden
    if was and AxisUsable() and AxisOn() and not BlizzardUsesAxis() then
        pcall(axis.EnableGamePadStick, axis, false)
    end
    combatArmed = false
    ShowAxis()
    if was and H.debug then H.Log("fight ended: stick listener switched off and shown") end
end

local fightEvents = CreateFrame("Frame")
fightEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
fightEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
fightEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then ArmForCombat() else DisarmAfterCombat() end
end)
H.fightEvents = fightEvents   -- (tests)
-- /halo camstate: who holds the camera stick right now.
function H.CameraState()
    local r = AxisUsable() and axis.right or {}
    local l = AxisUsable() and axis.left or {}
    local pointing = H.stickName == "Movement" and l or r
    local owner = pointing.func == TakeCamera and "Halo" or (pointing.func and "Blizzard" or "nobody")
    local other = H.stickName == "Movement" and r or l
    H.Print(("pointing stick (%s): slot %s | wait for centring %s | centred %s | listener on %s | other stick slot %s | stick blocker %s | cooldown %s | ring open %s"):format(
        H.stickName == "Movement" and "left" or "right",
        owner, tostring(pointing.waitForCentering and true or false), tostring(pointing.isCentered),
        tostring(AxisOn() and true or false), other.func and "used" or "free",
        catcher:IsShown() and "shown" or "hidden", release:IsShown() and "running" or "off",
        tostring(state.phase ~= nil and state.phase ~= "close")))
    H.Print(("fight: listener switched on for this fight %s | hidden by Halo %s | combat hold %s"):format(
        tostring(combatArmed), tostring(axisHidden),
        H.db and H.db.hiddenAxisReceives and "turned off (a hidden listener still got stick input)" or "on"))
    -- Blizzard's gamepad binding sets that are active right now (top last), and its radials.
    local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    local names = {}
    for _, set in ipairs(manager and manager.bindingSetStack or {}) do names[#names + 1] = tostring(set.name) end
    local shown = {}
    for _, name in ipairs(RADIALS) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then shown[#shown + 1] = name end
    end
    H.Print(("Blizzard binding sets: %s | radials shown: %s | free-look %s | cursor control %s"):format(
        #names > 0 and table.concat(names, ", ") or "none", #shown > 0 and table.concat(shown, ", ") or "none",
        tostring(IsGamePadFreelookEnabled and IsGamePadFreelookEnabled()),
        tostring(IsGamePadCursorControlEnabled and IsGamePadCursorControlEnabled())))
end
-- /halo debug: how each ring closed.
H.On("close", function(rid, used, input, aims)
    if not H.debug then return end
    H.Log(("ring %s closed (slice %s, by %s) | camera stick while open: %d tilts claimed, %d returns to centre let through | stick direction keys: %s | in combat %s"):format(
        tostring(rid), tostring(used), tostring(input), stickStats.claimed, stickStats.centred, tostring(aims),
        tostring(InCombatLockdown())))
end)

H.On("login", ArmCatcher)
H.On("options", function(key)
    if key == nil or key == "blockSticks" or key == "holdCamera" then ArmCatcher() end
end)
H.On("compiled", function() ArmCatcher() end)

-- Frame Gambit: keep the ring visible in Cinematic Mode.
H.On("login", function()
    if FrameGambitAPI and FrameGambitAPI.RegisterSceneProvider then
        pcall(FrameGambitAPI.RegisterSceneProvider, {
            id = "halo_ring", role = "quick_actions", cinematicKeep = true,
            resolve = function() return anchor end,
        })
    end
end)
