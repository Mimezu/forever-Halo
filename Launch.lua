-- Ways into the Halo window: a key (Bindings.xml, set from Halo's own Options page and from
-- Blizzard's Settings page), the minimap button, and the page in Esc > Options > AddOns.

local _, H = ...

BINDING_HEADER_HALO = "Halo"
BINDING_NAME_HALO_TOGGLE = "Open Halo"
local ACTION = "HALO_TOGGLE"

-- Window key ---------------------------------------------------------------------------------------
function H.WindowKey()
    return GetBindingKey and GetBindingKey(ACTION) or nil
end

-- key nil clears it. Refused in combat and on a key a Halo ring uses (the ring would win).
function H.SetWindowKey(key)
    if InCombatLockdown() or not SetBinding then
        UIErrorsFrame:AddMessage("Set keys outside combat.", 1, 0.82, 0)
        return false
    end
    if key then
        for _, ring in ipairs(H.db and H.db.rings or {}) do
            if (ring.key == key or ring.padKey == key) and H.RingActiveHere(ring) then
                UIErrorsFrame:AddMessage((GetBindingText and GetBindingText(key) or key) .. " opens " .. ring.name, 1, 0.82, 0)
                return false
            end
        end
    end
    for _, old in ipairs({ GetBindingKey(ACTION) }) do SetBinding(old) end
    if key then
        local previous = GetBindingAction and GetBindingAction(key) or ""
        SetBinding(key, ACTION)
        if previous ~= "" and previous ~= ACTION then
            H.Print((GetBindingText and GetBindingText(key) or key) .. " no longer does "
                .. (_G["BINDING_NAME_" .. previous] or previous))
        end
    end
    if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
    H.Fire("options")
    return true
end

local IGNORED_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local capturing

-- A keycap for the window key: click, press a key (modifiers combine, mouse buttons 3-5 and
-- gamepad buttons too). Esc cancels, Backspace clears.
function H.WindowKeyCap(parent, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height or 22)
    function button:Update()
        if capturing == self then self:SetText("Press a key"); return end
        local key = H.WindowKey()
        self:SetText(key and (GetBindingText and GetBindingText(key) or key) or "Not set")
    end
    function button:StopCapture()
        if capturing == self then capturing = nil end
        self:EnableKeyboard(false)
        if self.EnableGamePadButton and not InCombatLockdown() then pcall(self.EnableGamePadButton, self, false) end
        self:SetScript("OnKeyDown", nil)
        self:SetScript("OnGamePadButtonDown", nil)
        self:Update()
    end
    local function Assign(self, key)
        H.SetWindowKey(key)
        self:StopCapture()
    end
    button:SetScript("OnClick", function(self, mouse)
        if capturing == self then
            if MOUSE_KEYS[mouse] then Assign(self, H.WithModifiers(MOUSE_KEYS[mouse]))
            else self:StopCapture() end
            return
        end
        if mouse ~= "LeftButton" then return end
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage("Set keys outside combat.", 1, 0.82, 0)
            return
        end
        if capturing then capturing:StopCapture() end
        if H.StopRingKeyCapture then H.StopRingKeyCapture() end
        capturing = self
        self:Update()
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(false)
        self:SetScript("OnKeyDown", function(me, key)
            if IGNORED_KEYS[key] then return end
            if key == "ESCAPE" then me:StopCapture(); return end
            if key == "BACKSPACE" or key == "DELETE" then Assign(me, nil); return end
            Assign(me, H.WithModifiers(key))
        end)
        if self.EnableGamePadButton then
            pcall(self.EnableGamePadButton, self, true)
            self:SetScript("OnGamePadButtonDown", function(me, key) Assign(me, key) end)
        end
    end)
    button:SetScript("OnHide", function(self) if capturing == self then self:StopCapture() end end)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp", "Button4Up", "Button5Up")
    button:Update()
    H.On("options", function() button:Update() end)
    return button
end
function H.StopWindowKeyCapture()
    if capturing then capturing:StopCapture() end
end

-- A fight starting mid-capture: stop while gamepad input can still be switched off.
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", H.StopWindowKeyCapture)

-- Minimap button -----------------------------------------------------------------------------------
local ICON = "Interface\\Icons\\Spell_Holy_Aspiration"
local mini

local function MinimapSaved()
    if type(H.db.minimap) ~= "table" then H.db.minimap = {} end
    return H.db.minimap
end

local function PlaceMinimap()
    local angle = math.rad(tonumber(MinimapSaved().angle) or 200)
    local radius = (tonumber(Minimap:GetWidth()) or 140) / 2 + 5
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function DragAngle()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    if not (mx and cx) then return nil end
    return math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
end
H.MinimapDragAngle = DragAngle   -- (tests)

local function BuildMinimap()
    if mini or not Minimap then return end
    mini = CreateFrame("Button", "HaloMinimapButton", Minimap)
    mini:SetSize(31, 31)
    mini:SetFrameStrata("MEDIUM")
    mini:SetFrameLevel(8)
    mini:RegisterForClicks("LeftButtonUp")
    mini:RegisterForDrag("LeftButton")
    mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local back = mini:CreateTexture(nil, "BACKGROUND")
    back:SetSize(20, 20)
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    back:SetPoint("TOPLEFT", 7, -5)
    local icon = mini:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = mini:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    mini:SetScript("OnClick", function() GameTooltip:Hide(); H.ToggleOptions() end)
    mini:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Halo", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mini:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local angle = DragAngle()
            if angle then MinimapSaved().angle = angle; PlaceMinimap() end
        end)
    end)
    mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PlaceMinimap()
end

function H.MinimapShown()
    return not (H.db and type(H.db.minimap) == "table" and H.db.minimap.hide)
end
function H.SetMinimapShown(on)
    MinimapSaved().hide = (not on) or nil
    if on then BuildMinimap() end
    if mini then mini:SetShown(on and true or false) end
    H.Fire("options")
end
H.MinimapButton = function() return mini end   -- (tests)

-- Blizzard Settings page ---------------------------------------------------------------------------
local function OpenFromSettings()
    -- Closing a Blizzard panel from addon code runs the gamepad window manager with addon
    -- taint (the "A and B dead until /reload" bug), so in the gamepad interface Settings stays
    -- open behind the Halo window.
    if SettingsPanel and SettingsPanel:IsShown() and not H.IsGamepadInterface() then HideUIPanel(SettingsPanel) end
    H.ToggleOptions(1)
end

local function SettingsPage()
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Halo")
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
    open:SetText("Open")
    open:SetScript("OnClick", OpenFromSettings)
    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", open, "RIGHT", 10, 0)
    hint:SetText("/halo")

    local keyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    keyLabel:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -20)
    keyLabel:SetText("Open Halo key")
    local key = H.WindowKeyCap(panel, 160, 24)
    key:SetPoint("LEFT", keyLabel, "LEFT", 120, 0)

    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", keyLabel, "BOTTOMLEFT", -4, -14)
    local label = check.Text or check.text
    if label then label:SetFontObject("GameFontHighlight"); label:SetText("Minimap icon") end
    check:SetScript("OnClick", function(self) H.SetMinimapShown(self:GetChecked() == true) end)
    local function Update() check:SetChecked(H.MinimapShown()); key:Update() end
    panel:SetScript("OnShow", Update)
    H.On("options", Update)
    return panel
end

-- Addon compartment / Settings entry.
function Halo_OpenOptions() H.ToggleOptions() end
H.On("login", function()
    if H.MinimapShown() then BuildMinimap() end
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, SettingsPage(), "Halo")
        if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
    end
end)
