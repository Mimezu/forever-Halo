-- The Halo window: a Legacy frame with two side tabs.
--   Rings:   ring list on the left, the selected ring drawn as a ring on the right.
--            Drag spells, items, mounts, toys, pets or macros onto it.
--   Options: how rings open and behave, gamepad settings, a short how-to.

local _, H = ...

local W, H_ = 760, 520
local GOLD, NOTE, DIM = { 1, 0.82, 0 }, { 0.80, 0.77, 0.70 }, { 0.5, 0.5, 0.5 }
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local PAGES = {
    { "Rings", "Interface\\Icons\\Spell_Holy_Aspiration", "Make rings and choose what is in them." },
    { "Options", "Interface\\Icons\\INV_Misc_PocketWatch_01", "How rings open and behave." },
    { "Styles", "Interface\\Icons\\INV_Misc_Gem_Variety_01", "Compare the ring styles and pick the default." },
}

local frame, skin
local userClose, quietShow = false, false -- window: closed by the player / re-shown silently
local pageFrames, tabs, pageRefresh = {}, {}, {}
local styleHint   -- the Styles tab's hint, on the window's footer line
local selectedRing, selectedSlice

-- Building blocks (same family as Petal / Forever Names) ----------------------------------------
local function Text(parent, text, x, y, template, width, color)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetText(text or "")
    if width then label:SetWidth(width); label:SetWordWrap(true) end
    if color then label:SetTextColor(unpack(color)) end
    return label
end
local function Note(parent, text, x, y, width)
    return Text(parent, text, x, y, "GameFontHighlightSmall", width, NOTE)
end
local function Line(parent, x, y, width, height, alpha)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", x, y)
    line:SetSize(width, height)
    line:SetColorTexture(0.68, 0.50, 0.26, alpha or 0.45)
    return line
end
local function Card(parent, title, x, y, width, height)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", x, y)
    card:SetSize(width, height)
    local wash = card:CreateTexture(nil, "BACKGROUND", nil, -2)
    wash:SetAllPoints()
    wash:SetColorTexture(0.25, 0.17, 0.085, 0.16)
    Line(card, 0, 0, width, 1, 0.55); Line(card, 0, -height + 1, width, 1, 0.3)
    Line(card, 0, 0, 1, height, 0.3); Line(card, width - 1, 0, 1, height, 0.3)
    if title then
        card.title = Text(card, title, 12, -10, "GameFontNormal")
        Line(card, 8, -28, width - 16, 1, 0.25)
    end
    return card
end
local function Tooltip(owner, title, body)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title(self) or title, 1, 0.82, 0)
        local text = type(body) == "function" and body(self) or body
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function Button(parent, text, x, y, width, onClick, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, height or 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    if skin then skin.Button(button) end
    return button
end
local function Check(parent, text, x, y, get, set, width)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", x, y)
    check:SetSize(26, 26)
    local label = check.Text or check.text
    label:SetFontObject("GameFontHighlight")
    label:SetText(text)
    label:SetWidth(width or 300)
    label:SetJustifyH("LEFT")
    check:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        set(self:GetChecked() == true)
    end)
    check.Update = function(self) self:SetChecked(get() == true) end
    return check
end
local function Segmented(parent, x, y, width, choices, get, set)
    local buttons, left = {}, x
    for i, choice in ipairs(choices) do
        local button = Button(parent, choice[1], left, y, width, function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON); set(choice[2]); buttons:Update()
        end)
        left = left + width + 4
        button.wash = button:CreateTexture(nil, "ARTWORK")
        button.wash:SetPoint("TOPLEFT", 4, -4); button.wash:SetPoint("BOTTOMRIGHT", -4, 4)
        button.wash:SetColorTexture(1, 0.72, 0.2, 0.2)
        buttons[i] = button
    end
    function buttons:Update()
        local current = get()
        for i, choice in ipairs(choices) do
            local selected = choice[2] == current
            self[i].wash:SetShown(selected)
            self[i]:GetFontString():SetTextColor(unpack(selected and GOLD or { 0.9, 0.9, 0.9 }))
        end
    end
    return buttons
end
local function Stepper(parent, x, y, valueWidth, onStep)
    local stepper = {}
    stepper.minus = Button(parent, "-", x, y, 24, function() onStep(-1) end)
    stepper.value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    stepper.value:SetPoint("TOPLEFT", x + 24, y - 4)
    stepper.value:SetWidth(valueWidth)
    stepper.value:SetJustifyH("CENTER")
    stepper.plus = Button(parent, "+", x + 24 + valueWidth, y, 24, function() onStep(1) end)
    return stepper
end
local function EditBox(parent, x, y, width, onCommit)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", x + 6, y)
    box:SetSize(width - 6, 22)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlight")
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self.revert = true; self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function(self)
        if self.revert then self.revert = nil; if self.Reset then self:Reset() end; return end
        onCommit(self:GetText())
    end)
    return box
end
local function RoundIcon(parent, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    return icon
end

-- Keys ---------------------------------------------------------------------------------------------
local function KeyText(key)
    if not key or key == "" then return "Not set" end
    local text = GetBindingText and GetBindingText(key) or key
    return text ~= "" and text or key
end

local function BindingOwnerText(key)
    if not key then return nil end
    local current = GetBindingAction and GetBindingAction(key, true)
    if H.IsBlizzardGamepadAction(current) then return "Overrides Blizzard's gamepad binding." end
    local takenBy = H.KeyTakenBy(key, selectedRing)
    if takenBy then
        return "|cffff6040Taken by " .. takenBy .. ", so this ring will not open. Pick another key or free it there.|r"
    end
    for _, ring in ipairs(H.db.rings) do
        if ring.id ~= selectedRing and (ring.key == key or ring.padKey == key) and H.RingActiveHere(ring) then
            return "Also opens " .. ring.name .. "."
        end
    end
    local action = GetBindingAction and GetBindingAction(key, false)
    if action and action ~= "" and not action:match("^CLICK HaloButton") then
        local name = _G["BINDING_NAME_" .. action] or action
        return "Replaces " .. name .. " while Halo is loaded."
    end
end

local IGNORED_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function WithModifiers(key)
    local prefix = ""
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    if IsMetaKeyDown and IsMetaKeyDown() then prefix = prefix .. "META-" end
    return prefix .. key
end

-- A button that captures the next key (field "key") or gamepad button (field "padKey").
local capturing
local function KeyCapture(parent, x, y, width, field)
    local button = Button(parent, "", x, y, width, nil, 24)
    button.field = field
    local function Stop(self)
        capturing = nil
        self:EnableKeyboard(false)
        if self.EnableGamePadButton and not InCombatLockdown() then pcall(self.EnableGamePadButton, self, false) end
        self:SetScript("OnKeyDown", nil)
        self:SetScript("OnGamePadButtonDown", nil)
        self:SetScript("OnGamePadButtonUp", nil)
        self.pendingModifier = nil
        if pageRefresh[1] then pageRefresh[1]() end
    end
    button.StopCapture = Stop
    local function Assign(self, key)
        local ring = H.GetRing(selectedRing)
        if ring then
            ring[field] = key
            H.Changed("keys")
        end
        Stop(self)
    end
    button:SetScript("OnClick", function(self, mouse)
        if capturing == self then
            if MOUSE_KEYS[mouse] and field == "key" then Assign(self, WithModifiers(MOUSE_KEYS[mouse]))
            elseif mouse == "LeftButton" then Stop(self) end
            return
        end
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage("Set keys outside combat.", 1, 0.82, 0)
            return
        end
        if capturing then Stop(capturing) end
        if mouse ~= "LeftButton" then return end
        capturing = self
        self:SetText(field == "padKey" and "Press a gamepad button" or "Press a key")
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(false)
        self:SetScript("OnKeyDown", function(me, key)
            if IGNORED_KEYS[key] then return end
            if key == "ESCAPE" then Stop(me); return end
            if key == "BACKSPACE" or key == "DELETE" then Assign(me, nil); return end
            if field == "padKey" then return end -- gamepad buttons arrive through the gamepad handlers
            Assign(me, WithModifiers(key))
        end)
        if self.EnableGamePadButton and not InCombatLockdown() then
            pcall(self.EnableGamePadButton, self, true)
            -- One gamepad button, recorded when it is let go (combinations: the ring's macro
            -- on a gamepad bar slot).
            self:SetScript("OnGamePadButtonDown", function(me, key)
                if field ~= "padKey" then return end
                me.pendingModifier = me.pendingModifier or key
            end)
            self:SetScript("OnGamePadButtonUp", function(me, key)
                if field == "padKey" and me.pendingModifier == key then
                    me.pendingModifier = nil
                    Assign(me, key)
                end
            end)
        end
    end)
    button:SetScript("OnHide", function(self) if capturing == self then Stop(self) end end)
    button:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "Button4Up", "Button5Up")
    return button
end

-- A fight starting while a key is being captured: stop now, while gamepad input can still be
-- switched off (PLAYER_REGEN_DISABLED comes just before the lockdown). Otherwise the capture
-- button would keep taking the gamepad's buttons for the whole fight.
local captureGuard = CreateFrame("Frame")
captureGuard:RegisterEvent("PLAYER_REGEN_DISABLED")
captureGuard:SetScript("OnEvent", function()
    if capturing then capturing:StopCapture() end
end)

-- Slice editing helpers ---------------------------------------------------------------------------
local function CurrentRing() return selectedRing and H.GetRing(selectedRing) end

-- Rings meant for this character. A ring marked "Only this character" on another one is not
-- listed, offered as a nested ring or used for previews here.
local function VisibleRings()
    local list = {}
    for _, ring in ipairs(H.db.rings) do
        if H.RingActiveHere(ring) then list[#list + 1] = ring end
    end
    return list
end
H.VisibleRings = VisibleRings   -- (tests)

local function AddSlice(slice, at)
    local ring = CurrentRing()
    if not ring or not slice then return end
    if #ring.slices >= H.MAX_SLICES and not at then
        UIErrorsFrame:AddMessage("A ring holds up to " .. H.MAX_SLICES .. " slices.", 1, 0.82, 0)
        return
    end
    if at and ring.slices[at] then ring.slices[at] = slice
    else table.insert(ring.slices, slice); at = #ring.slices end
    selectedSlice = at
    PlaySound(SOUNDKIT.IG_ABILITY_ICON_DROP or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    H.Changed("slices")
end

local function DropCursor(at)
    local slice = H.CursorSlice()
    if not slice then return false end
    ClearCursor()
    AddSlice(slice, at)
    return true
end

local macroEditor
local function OpenMacroEditor(slice)
    macroEditor.slice = slice
    macroEditor.labelBox:SetText(slice and slice.label or "")
    macroEditor.textBox:SetText(slice and slice.text or "")
    macroEditor:Show()
    macroEditor.textBox:SetFocus()
end

local function AddMenu(owner)
    local ring = CurrentRing()
    if not ring then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Add to " .. ring.name)
        local auto = root:CreateButton("Automatic")
        for _, a in ipairs(H.AUTO) do
            auto:CreateButton(a[2], function() AddSlice({ kind = "auto", source = a[1] }) end)
        end
        local emote = root:CreateButton("Emote")
        for _, e in ipairs(H.EMOTES) do
            emote:CreateButton(e[2], function() AddSlice({ kind = "emote", token = e[1] }) end)
        end
        local marker = root:CreateButton("Target marker")
        for i, name in ipairs(H.MARKERS) do
            marker:CreateButton(name, function() AddSlice({ kind = "marker", index = i }) end)
        end
        marker:CreateButton("Clear marker", function() AddSlice({ kind = "marker", index = 0 }) end)
        local rings = root:CreateButton("Another ring")
        local any = false
        for _, other in ipairs(VisibleRings()) do
            if other.id ~= ring.id then
                any = true
                rings:CreateButton(other.name, function() AddSlice({ kind = "ring", ringID = other.id }) end)
            end
        end
        if not any then rings:SetEnabled(false) end
        if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
            local ids = C_EquipmentSet.GetEquipmentSetIDs() or {}
            if #ids > 0 then
                local sets = root:CreateButton("Equipment set")
                for _, id in ipairs(ids) do
                    local name = C_EquipmentSet.GetEquipmentSetInfo(id)
                    if name then sets:CreateButton(name, function() AddSlice({ kind = "equipset", name = name }) end) end
                end
            end
        end
        root:CreateButton("Custom macro...", function() OpenMacroEditor(nil) end)
        root:CreateDivider()
        root:CreateTitle("Or drag a spell, item, mount, toy, pet")
        root:CreateTitle("or macro onto the ring.")
    end)
end

-- The macro whose text is exactly body (account macros, then this character's).
local function FindRingMacro(body)
    local account, character = GetNumMacros()
    local first = MAX_ACCOUNT_MACROS or 120
    local function Matches(index)
        local _, _, text = GetMacroInfo(index)
        return type(text) == "string" and strtrim(text) == body
    end
    for index = 1, account or 0 do
        if Matches(index) then return index end
    end
    for index = first + 1, first + (character or 0) do
        if Matches(index) then return index end
    end
end

-- Folders: this character's rings, rings for everyone, then one folder per other character.
function H.RingGroups()
    local myKey = H.CharacterKey()
    local mineList, everyoneList, byOwner, order = {}, {}, {}, {}
    for _, ring in ipairs(H.db.rings) do
        if not ring.owner then everyoneList[#everyoneList + 1] = ring
        elseif ring.owner == myKey then mineList[#mineList + 1] = ring
        else
            if not byOwner[ring.owner] then byOwner[ring.owner] = {}; order[#order + 1] = ring.owner end
            local list = byOwner[ring.owner]
            list[#list + 1] = ring
        end
    end
    table.sort(order, function(a, b) return (H.OwnerName(a) or a):lower() < (H.OwnerName(b) or b):lower() end)
    local myRealm = myKey:match("%-(.+)$")
    local groups = {
        { key = "mine", title = H.CharacterFullName() or "This character", rings = mineList, class = H.CharacterClass() },
        { key = "all", title = "Everyone", rings = everyoneList },
    }
    for _, owner in ipairs(order) do
        local _, realm = owner:match("^([^%-]+)%-(.+)$")
        local name = H.RingOwnerName(byOwner[owner][1])
        local title = realm and realm ~= myRealm and (name .. " (" .. realm .. ")") or name
        groups[#groups + 1] = { key = owner, title = title, rings = byOwner[owner],
            class = byOwner[owner][1].ownerClass, foreign = true }
    end
    return groups
end

-- Rings page ---------------------------------------------------------------------------------------
local LIST_W, ROW_H = 196, 40

local function BuildRings(page)
    local W_, Hh = page:GetSize()
    -- Ring list.
    local listCard = Card(page, nil, 0, 0, LIST_W, Hh - 30)
    local scroll = CreateFrame("ScrollFrame", nil, listCard, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(LIST_W - 30, 10)
    scroll:SetScrollChild(child)
    local rows = {}
    local FOLDER_H = 26
    local function Row(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Button", nil, child)
        row:SetSize(LIST_W - 30, ROW_H - 2)
        row.icon = RoundIcon(row, 30)
        row.icon:SetPoint("LEFT", 4, 0)
        row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
        row.name:SetPoint("RIGHT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.key = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.key:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
        row.key:SetPoint("RIGHT", -4, 0)
        row.key:SetJustifyH("LEFT")
        row.key:SetWordWrap(false)
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(1, 0.72, 0.2, 0.18)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 0.8, 0.4, 0.08)
        -- Folder header: arrow, name in the character's class colour, ring count.
        row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
        row.stripe:SetAllPoints()
        row.stripe:SetColorTexture(0.25, 0.17, 0.085, 0.45)
        row.arrow = row:CreateTexture(nil, "ARTWORK")
        row.arrow:SetSize(12, 12)
        row.arrow:SetPoint("LEFT", 6, 0)
        if C_Texture.GetAtlasInfo("common-icon-forwardarrow") then row.arrow:SetAtlas("common-icon-forwardarrow") end
        row.folder = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.folder:SetPoint("LEFT", row.arrow, "RIGHT", 6, 0)
        row.folder:SetPoint("RIGHT", -30, 0)
        row.folder:SetJustifyH("LEFT")
        row.folder:SetWordWrap(false)
        row.count = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.count:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnClick", function(self)
            PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
            if self.folderKey then
                H.db.window.folders[self.folderKey] = not self.folderClosed
            else
                selectedRing, selectedSlice = self.ringID, nil
            end
            pageRefresh[1]()
        end)
        rows[i] = row
        return row
    end
    local newRing = Button(page, "New ring", 0, -(Hh - 24), LIST_W, function()
        local ring = H.NewRing("Ring " .. #H.db.rings + 1)
        selectedRing, selectedSlice = ring.id, nil
        pageRefresh[1]()
    end)

    -- Editor.
    local EX = LIST_W + 14
    local EW = W_ - EX
    local editor = CreateFrame("Frame", nil, page)
    editor:SetPoint("TOPLEFT", EX, 0)
    editor:SetSize(EW, Hh)
    local empty = Note(page, "Make a ring with New ring.", EX + 20, -40, EW - 40)

    Text(editor, "Name", 0, -4, "GameFontNormal")
    local nameBox = EditBox(editor, 60, 0, 150, function(text)
        local ring = CurrentRing()
        text = strtrim(text or "")
        if ring and text ~= "" and text ~= ring.name then ring.name = text; H.Changed("name") end
        pageRefresh[1]()
    end)
    function nameBox:Reset() local ring = CurrentRing(); self:SetText(ring and ring.name or "") end
    local mine = Check(editor, "Only this character", 218, 0,
        function() local r = CurrentRing(); return r and r.owner ~= nil end,
        function(on)
            local r = CurrentRing()
            if r then H.SetRingOwner(r, on and H.CharacterKey() or nil); H.Changed("owner") end
        end, 140)
    Tooltip(mine, "Only this character", "Other characters do not use this ring and its keys. They can still see it under this character's folder and copy it.")
    local function CopyCurrent(owner, where)
        local ring = CurrentRing()
        if not ring then return end
        local copy, notes = H.CopyRing(ring.id, owner)
        if not copy then return end
        selectedRing, selectedSlice = copy.id, nil
        H.db.window.folders[owner and "mine" or "all"] = false   -- show it: open its folder
        H.Print(('Copied "%s" %s as "%s".'):format(ring.name, where, copy.name))
        for _, note in ipairs(notes) do H.Print(note) end
        pageRefresh[1]()
    end
    Tooltip(Button(editor, "Duplicate", 410, 0, EW - 410, function()
        local ring = CurrentRing()
        if ring then CopyCurrent(ring.owner, "here") end
    end, 24), "Duplicate", "Makes a copy of this ring in the same folder. The copy keeps its key unless something already uses it.")

    Text(editor, "Key", 0, -38, "GameFontNormal")
    local keyButton = KeyCapture(editor, 60, -34, 130, "key")
    Tooltip(keyButton, "Key", "Click, then press a key or mouse button (with Shift, Ctrl or Alt if you like). Backspace clears it.")
    Text(editor, "Gamepad", 204, -38, "GameFontNormal")
    local padButton = KeyCapture(editor, 270, -34, 130, "padKey")
    Tooltip(padButton, "Gamepad button", "Click, then press a gamepad button. Backspace clears it. For combinations like R1 + D-pad down, use Make macro and put the macro on that slot of your gamepad bars.")
    local keyNote = Note(editor, "", 0, -62, EW)
    local styleButton = Button(editor, "Style", 410, -34, EW - 410, function(self)
        local ring = CurrentRing()
        if not ring then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Style of " .. ring.name)
            local default = H.RingSkins.Get(H.Option("style"))
            root:CreateRadio("Default (" .. default.id .. " " .. default.name .. ")",
                function() return not (ring.style and H.RingSkins.list[ring.style]) end,
                function() ring.style = nil; H.Changed("style") end)
            for _, id in ipairs(H.RingSkins.order) do
                local skin = H.RingSkins.list[id]
                root:CreateRadio(id .. "  " .. skin.name, function() return ring.style == id end,
                    function() ring.style = id; H.Changed("style") end)
            end
        end)
    end, 24)
    Tooltip(styleButton, "Style", "How this ring looks. Default follows the Styles tab.")

    -- The ring drawn as a ring.
    local CANVAS = 250
    local canvas = CreateFrame("Frame", nil, editor)
    canvas:SetPoint("TOPLEFT", 0, -84)
    canvas:SetSize(CANVAS + 20, CANVAS)
    -- The stage draws the ring at its real size: same radius rule, Spacing, Size option,
    -- 36px icons and backdrop as Ring.lua. Scaled down evenly only when it would not fit.
    local stage = CreateFrame("Frame", nil, canvas)
    stage:SetPoint("CENTER")
    stage:SetSize(1, 1)
    local halo = stage:CreateTexture(nil, "BACKGROUND")
    halo:SetPoint("CENTER")
    halo:SetTexture(ROUND_MASK)
    halo:SetVertexColor(0, 0, 0, 0.25)
    local fitNote = canvas:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fitNote:SetPoint("TOPLEFT", 0, 0)
    fitNote:SetJustifyH("LEFT")

    local add = CreateFrame("Button", nil, canvas)
    add:SetSize(40, 40)
    add:SetPoint("CENTER")
    add:SetFrameLevel(canvas:GetFrameLevel() + 10)
    add.bg = add:CreateTexture(nil, "BACKGROUND")
    add.bg:SetAllPoints()
    add.bg:SetTexture(ROUND_MASK)
    add.bg:SetVertexColor(0.25, 0.17, 0.08, 0.9)
    add.plus = add:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    add.plus:SetPoint("CENTER", 0, 1)
    add.plus:SetText("+")
    local addHover = add:CreateTexture(nil, "HIGHLIGHT")
    addHover:SetAllPoints()
    addHover:SetTexture(ROUND_MASK)
    addHover:SetBlendMode("ADD")
    addHover:SetVertexColor(1, 0.8, 0.3, 0.3)
    add:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    add:SetScript("OnClick", function(self) if not DropCursor() then AddMenu(self) end end)
    add:SetScript("OnReceiveDrag", function() DropCursor() end)
    Tooltip(add, "Add a slice", "Drop a spell, item, mount, toy, pet or macro here, or click for emotes, markers, automatic lists, other rings and custom macros.")

    local slotButtons = {}
    local function SlotButton(i)
        if slotButtons[i] then return slotButtons[i] end
        local b = CreateFrame("Button", nil, stage)
        H.RingSkins.BuildSlotKit(b)
        b.badge = b.top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.badge:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 2, -2)
        b.missing = b.top:CreateTexture(nil, "OVERLAY", nil, 2)
        b.missing:SetSize(14, 14)
        b.missing:SetPoint("TOPRIGHT", b.icon, "TOPRIGHT", 4, 4)
        b.missing:SetAtlas("services-icon-warning")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", function(self, mouse)
            if DropCursor(self.index) then return end
            if mouse == "RightButton" then
                local ring = CurrentRing()
                if ring then table.remove(ring.slices, self.index); selectedSlice = nil; H.Changed("slices") end
                return
            end
            selectedSlice = self.index
            PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
            pageRefresh[1]()
        end)
        b:SetScript("OnReceiveDrag", function(self) DropCursor(self.index) end)
        b:SetScript("OnEnter", function(self)
            local ring = CurrentRing()
            local s = ring and ring.slices[self.index]
            if not s then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            H.SliceTooltip(s, GameTooltip)
            if s.kind ~= "auto" and ring.hideMissing and not H.SliceKnown(s) then
                GameTooltip:AddLine("Hidden right now: not learned or not in your bags.", 1, 0.5, 0.25, true)
            end
            GameTooltip:AddLine("Click: select   Right-click: remove", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        slotButtons[i] = b
        return b
    end

    -- Selected slice details.
    local DX = CANVAS + 36
    local DW = EW - DX
    local detail = CreateFrame("Frame", nil, editor)
    detail:SetPoint("TOPLEFT", DX, -84)
    detail:SetSize(DW, CANVAS)
    local dIcon = RoundIcon(detail, 40)
    dIcon:SetPoint("TOPLEFT", 0, -4)
    local dName = detail:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dName:SetPoint("TOPLEFT", dIcon, "TOPRIGHT", 8, -3)
    dName:SetPoint("RIGHT", 0, 0)
    dName:SetJustifyH("LEFT")
    dName:SetWordWrap(false)
    local dKind = detail:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    dKind:SetPoint("TOPLEFT", dName, "BOTTOMLEFT", 0, -3)
    local function Move(delta)
        local ring = CurrentRing()
        local i = selectedSlice
        if not (ring and i and ring.slices[i] and ring.slices[i + delta]) then return end
        ring.slices[i], ring.slices[i + delta] = ring.slices[i + delta], ring.slices[i]
        selectedSlice = i + delta
        H.Changed("slices")
    end
    local back = Button(detail, "Earlier", 0, -56, (DW - 4) / 2, function() Move(-1) end)
    local fwd = Button(detail, "Later", (DW + 4) / 2, -56, (DW - 4) / 2, function() Move(1) end)
    Tooltip(back, "Earlier", "Moves the slice one place anticlockwise. Slice 1 is at the top.")
    Tooltip(fwd, "Later", "Moves the slice one place clockwise.")
    local edit = Button(detail, "Edit macro", 0, -82, DW, function()
        local ring = CurrentRing()
        local s = ring and selectedSlice and ring.slices[selectedSlice]
        if s and s.kind == "text" then OpenMacroEditor(s) end
    end)
    local remove = Button(detail, "Remove", 0, -108, DW, function()
        local ring = CurrentRing()
        if ring and selectedSlice and ring.slices[selectedSlice] then
            table.remove(ring.slices, selectedSlice)
            selectedSlice = nil
            H.Changed("slices")
        end
    end)
    local dNote = Note(detail, "", 0, -140, DW)
    local noSelection = Note(editor, "Select a slice to move or remove it.", DX, -90, DW)

    -- Ring-level controls.
    local hide = Check(editor, "Hide what you can't use now", 0, -(84 + CANVAS + 4),
        function() local r = CurrentRing(); return r and r.hideMissing end,
        function(on) local r = CurrentRing(); if r then r.hideMissing = on; H.Changed("hide") end end, 220)
    Tooltip(hide, "Hide what you can't use now", "Leaves out spells you have not learned and items that are not in your bags. The ring updates outside combat.")
    local tips = Check(editor, "Show tooltips", 0, -(84 + CANVAS + 28),
        function() local r = CurrentRing(); return r and r.tooltips end,
        function(on) local r = CurrentRing(); if r then r.tooltips = on or nil; H.Changed("tooltips") end end, 220)
    Tooltip(tips, "Show tooltips", "Shows the game tooltip of the slice you point at, beside the ring.")
    local liveNote = Note(editor, "", 250, -(84 + CANVAS + 10), 180)
    Text(editor, "Spacing", 250, -(84 + CANVAS + 32), "GameFontHighlight")
    local spacing = Stepper(editor, 316, -(84 + CANVAS + 28), 56, function(delta)
        local r = CurrentRing()
        if not r then return end
        local v = math.floor(((tonumber(r.spread) or 1) + delta * 0.1) * 10 + 0.5) / 10
        v = math.max(H.SPREAD_MIN, math.min(H.SPREAD_MAX, v))
        r.spread = v ~= 1 and v or nil
        H.Changed("spacing")
    end)
    local spacingHelp = CreateFrame("Frame", nil, editor)
    spacingHelp:SetPoint("TOPLEFT", 250, -(84 + CANVAS + 28))
    spacingHelp:SetSize(62, 22)
    Tooltip(spacingHelp, "Spacing", "Moves the slices further apart or closer together. Icons keep their size.")
    -- Ring macro: /click the ring from a macro, so it can sit on any slot of Blizzard's
    -- gamepad bars (R1 + D-pad down etc.). Blizzard handles the combination; each button
    -- alone keeps its normal action. A macro opens the ring like tap mode.
    local macroButton = Button(editor, "Macro", EW - 78, -(84 + CANVAS + 28), 78, function()
        local ring = CurrentRing()
        if not ring then return end
        if InCombatLockdown() then UIErrorsFrame:AddMessage("Make the macro outside combat.", 1, 0.82, 0); return end
        local name = ("Halo " .. ring.name):sub(1, 16)
        local body = "/click HaloButton t" .. ring.id .. " LeftButton true"
        local icon = H.RingIcon(ring, true)
        if type(icon) == "string" then icon = GetFileIDFromPath and GetFileIDFromPath(icon) or 134400 end
        -- Found by what it does, not by name: names are cut to 16 letters, so two rings
        -- starting with the same words would share one macro.
        local index = FindRingMacro(body)
        if index then
            EditMacro(index, name, icon or 134400, body)
        else
            local perChar = ring.owner ~= nil
            local ok, created = pcall(CreateMacro, name, icon or 134400, body, perChar)
            if not ok or not created then
                UIErrorsFrame:AddMessage("Could not make the macro (the macro list may be full).", 1, 0.3, 0.3)
                return
            end
            index = created
        end
        PickupMacro(index)
        H.Print(("Macro \"%s\" is on your cursor: put it on a gamepad bar slot (for example R1 + D-pad down)."):format(name))
    end)
    Tooltip(macroButton, "Macro", "Makes a macro that opens this ring and puts it on your cursor. Place it on any slot of your gamepad bars, such as a shoulder + D-pad combination: that combination opens the ring and each button alone still does its normal action. Opened this way, the ring works like tap: press again to use the pointed slice, or L1/R1/L2/R2/A.")
    local deleteArmed = false
    local delete = Button(editor, "Delete ring", EW - 120, -(84 + CANVAS + 4), 120, nil)
    delete:SetScript("OnClick", function(self)
        if not deleteArmed then
            deleteArmed = true
            self:SetText("Click to confirm")
            C_Timer.After(3, function() deleteArmed = false; if self:IsShown() then self:SetText("Delete ring") end end)
            return
        end
        deleteArmed = false
        self:SetText("Delete ring")
        H.DeleteRing(selectedRing)
        selectedRing, selectedSlice = nil, nil
        pageRefresh[1]()
    end)

    -- A ring of another character: shown dimmed and locked, with a banner to copy it here.
    local foreignBar = CreateFrame("Frame", nil, editor)
    foreignBar:SetAllPoints(editor)
    foreignBar:SetFrameLevel(editor:GetFrameLevel() + 30)
    foreignBar:EnableMouse(true)
    foreignBar:Hide()
    local dim = foreignBar:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0.05, 0.03, 0.02, 0.45)
    local strip = foreignBar:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT"); strip:SetPoint("TOPRIGHT"); strip:SetHeight(80)
    strip:SetColorTexture(0.07, 0.05, 0.03, 0.97)
    local foreignText = Text(foreignBar, "", 10, -8, "GameFontHighlight", EW - 20)
    Tooltip(Button(foreignBar, "Copy to this character", 10, -46, 178, function()
        CopyCurrent(H.CharacterKey(), "to this character")
    end, 24), "Copy to this character", "Makes your own copy, marked \"Only this character\". It keeps its key and gamepad button unless something here already uses them.")
    Tooltip(Button(foreignBar, "Copy for everyone", 194, -46, 150, function()
        CopyCurrent(nil, "for every character")
    end, 24), "Copy for everyone", "Makes a copy that every character sees, for rings that are not class-specific.")
    local foreignArmed = false
    local foreignDelete = Button(foreignBar, "Delete ring", EW - 110, -46, 100, nil, 24)
    foreignDelete:SetScript("OnClick", function(self)
        if not foreignArmed then
            foreignArmed = true
            self:SetText("Click to confirm")
            C_Timer.After(3, function() foreignArmed = false; if self:IsShown() then self:SetText("Delete ring") end end)
            return
        end
        foreignArmed = false
        self:SetText("Delete ring")
        H.DeleteRing(selectedRing)
        selectedRing, selectedSlice = nil, nil
        pageRefresh[1]()
    end)
    function foreignBar:Set(ring)
        local shown = ring ~= nil and not H.RingActiveHere(ring)
        self:SetShown(shown)
        if shown then
            local class = ring.ownerClass and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[ring.ownerClass]
            foreignText:SetText(("Belongs to %s%s. It does not show up on this character."):format(
                H.RingOwnerName(ring) or "another character", class and (" (" .. class .. ")") or ""))
        end
    end

    -- Custom macro editor (over the canvas).
    macroEditor = CreateFrame("Frame", nil, editor)
    macroEditor:SetPoint("TOPLEFT", 0, -84)
    macroEditor:SetSize(EW, CANVAS + 30)
    macroEditor:SetFrameLevel(editor:GetFrameLevel() + 20)
    macroEditor:EnableMouse(true)
    macroEditor:Hide()
    local mbg = macroEditor:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints()
    mbg:SetColorTexture(0.07, 0.05, 0.03, 0.97)
    Text(macroEditor, "Custom macro", 10, -8, "GameFontNormal")
    Text(macroEditor, "Name", 10, -36, "GameFontHighlightSmall")
    macroEditor.labelBox = EditBox(macroEditor, 60, -32, 200, function() end)
    Text(macroEditor, "Macro text", 10, -64, "GameFontHighlightSmall")
    local mscroll = CreateFrame("ScrollFrame", nil, macroEditor, "UIPanelScrollFrameTemplate")
    mscroll:SetPoint("TOPLEFT", 12, -82)
    mscroll:SetPoint("BOTTOMRIGHT", -30, 40)
    local mtext = CreateFrame("EditBox", nil, mscroll)
    mtext:SetMultiLine(true)
    mtext:SetAutoFocus(false)
    mtext:SetFontObject("ChatFontNormal")
    mtext:SetWidth(EW - 50)
    mtext:SetMaxLetters(1023)
    mtext:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    mscroll:SetScrollChild(mtext)
    local mbox = macroEditor:CreateTexture(nil, "BORDER")
    mbox:SetPoint("TOPLEFT", mscroll, -4, 4); mbox:SetPoint("BOTTOMRIGHT", mscroll, 4, -4)
    mbox:SetColorTexture(0, 0, 0, 0.5)
    macroEditor.textBox = mtext
    Button(macroEditor, "Save", EW - 200, -(CANVAS + 2), 90, function()
        local text = macroEditor.textBox:GetText() or ""
        local labelText = strtrim(macroEditor.labelBox:GetText() or "")
        if strtrim(text) == "" then macroEditor:Hide(); return end
        if macroEditor.slice then
            macroEditor.slice.text, macroEditor.slice.label = text, labelText
            H.Changed("slices")
        else
            AddSlice({ kind = "text", text = text, label = labelText })
        end
        macroEditor:Hide()
    end)
    Button(macroEditor, "Cancel", EW - 104, -(CANVAS + 2), 90, function() macroEditor:Hide() end)

    local Groups = H.RingGroups

    pageRefresh[1] = function()
        local groups = Groups()
        if selectedRing and not H.GetRing(selectedRing) then selectedRing = nil end
        if not selectedRing then
            for _, group in ipairs(groups) do
                if group.rings[1] then selectedRing = group.rings[1].id; break end
            end
        end
        local n, y = 0, 0
        for _, group in ipairs(groups) do
            -- This character's and everyone's folders start open, other characters' closed.
            local closed = H.db.window.folders[group.key]
            if closed == nil then closed = group.foreign == true end
            n = n + 1
            local head = Row(n)
            head.folderKey, head.folderClosed, head.ringID = group.key, closed, nil
            head:SetHeight(FOLDER_H - 2)
            head:ClearAllPoints(); head:SetPoint("TOPLEFT", 0, -y)
            y = y + FOLDER_H
            head.icon:Hide(); head.name:Hide(); head.key:Hide(); head.selected:Hide()
            head.stripe:Show(); head.arrow:Show(); head.folder:Show(); head.count:Show()
            head.arrow:SetRotation(closed and 0 or -math.pi / 2)
            head.folder:SetText(group.title)
            local color = group.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[group.class]
            if color then head.folder:SetTextColor(color.r, color.g, color.b) else head.folder:SetTextColor(1, 0.82, 0) end
            head.count:SetText(#group.rings > 0 and tostring(#group.rings) or "")
            head:Show()
            if not closed then
                for _, ring in ipairs(group.rings) do
                    n = n + 1
                    local row = Row(n)
                    row.folderKey, row.ringID = nil, ring.id
                    row:SetHeight(ROW_H - 2)
                    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y)
                    y = y + ROW_H
                    row.stripe:Hide(); row.arrow:Hide(); row.folder:Hide(); row.count:Hide()
                    row.icon:Show(); row.name:Show(); row.key:Show()
                    row.icon:SetTexture(H.RingIcon(ring))
                    row.icon:SetAlpha(group.foreign and 0.55 or 1)
                    row.name:SetText(ring.name)
                    if group.foreign then row.name:SetTextColor(0.7, 0.7, 0.7) else row.name:SetTextColor(1, 1, 1) end
                    local keysText = {}
                    if ring.key then keysText[#keysText + 1] = KeyText(ring.key) end
                    if ring.padKey then keysText[#keysText + 1] = KeyText(ring.padKey) end
                    row.key:SetText(#keysText > 0 and table.concat(keysText, ", ") or "No key")
                    row.selected:SetShown(ring.id == selectedRing)
                    row:Show()
                end
            end
        end
        for i = n + 1, #rows do rows[i]:Hide() end
        child:SetHeight(math.max(10, y))

        local ring = CurrentRing()
        editor:SetShown(ring ~= nil)
        empty:SetShown(ring == nil)
        foreignBar:Set(ring)
        if not ring then return end
        if selectedSlice and not ring.slices[selectedSlice] then selectedSlice = nil end
        if not nameBox:HasFocus() then nameBox:SetText(ring.name) end
        mine:Update()
        hide:Update()
        tips:Update()
        local spread = tonumber(ring.spread) or 1
        spacing.value:SetText(math.floor(spread * 100 + 0.5) .. "%")
        spacing.minus:SetEnabled(spread > H.SPREAD_MIN + 0.001)
        spacing.plus:SetEnabled(spread < H.SPREAD_MAX - 0.001)
        if capturing ~= keyButton then keyButton:SetText(KeyText(ring.key)) end
        if capturing ~= padButton then padButton:SetText(KeyText(ring.padKey)) end
        local notes = {}
        local n1, n2 = BindingOwnerText(ring.key), BindingOwnerText(ring.padKey)
        if n1 then notes[#notes + 1] = KeyText(ring.key) .. ": " .. n1 end
        if n2 then notes[#notes + 1] = KeyText(ring.padKey) .. ": " .. n2 end
        if not ring.key and not ring.padKey then notes[#notes + 1] = "Give the ring a key to open it." end
        keyNote:SetText(table.concat(notes, "  "))

        local n = #ring.slices
        -- Real ring size: the ring shows the live (expanded) slices, so size it by those.
        local live = H.live[ring.id]
        local count = math.max(n, live and #live or 0)
        local radius = H.RingRadius(count, spread)
        local size = tonumber(H.Option("scale")) or 1
        local skin = H.RingSkins.ForRing(ring)
        local diameter = 2 * (radius + 24)
        local art = H.RingSkins.RingArt(stage, skin)
        if art and H.Option("background") ~= false then
            art:Layout(radius)
            H.RingSkins.PreviewTone(art)
            H.RingSkins.ShowRingArt(art, true)
            halo:Hide()
            diameter = math.max(diameter, art:Extent(radius))
        else
            H.RingSkins.ShowRingArt(art, false)
            halo:SetSize(2 * radius + 50, 2 * radius + 50); halo:Show()
        end
        styleButton:SetText("Style: " .. (ring.style and H.RingSkins.list[ring.style] and ring.style or "Default"))
        local fit = math.min(1, (CANVAS - 4) / (diameter * size))
        stage:SetScale(size * fit)
        fitNote:SetText(fit < 0.995 and ("Shown at " .. math.floor(fit * 100 + 0.5) .. "% of real size") or "")
        for i = 1, math.max(n, #slotButtons) do
            local b = SlotButton(i)
            local s = ring.slices[i]
            if s then
                b.index = i
                H.RingSkins.ApplySlot(b, skin)
                local _, icon = H.SliceInfo(s)
                b.icon:SetTexture(icon)
                local a = (i - 1) * 2 * math.pi / math.max(n, 1)
                b:ClearAllPoints()
                local sr = H.RingSkins.SlotRadius(skin, radius)
                b:SetPoint("CENTER", stage, "CENTER", sr * math.sin(a), sr * math.cos(a))
                b.over:SetShown(i == selectedSlice)
                b.badge:SetText(s.kind == "auto" and "A" or (s.kind == "ring" and ">" or ""))
                local hidden = s.kind ~= "auto" and ring.hideMissing and not H.SliceKnown(s)
                b.icon:SetDesaturated(hidden)
                b.icon:SetAlpha(hidden and 0.5 or 1)
                b.missing:SetShown(hidden)
                b:Show()
            else
                b:Hide()
            end
        end
        add:SetShown(n < H.MAX_SLICES)

        local s = selectedSlice and ring.slices[selectedSlice]
        detail:SetShown(s ~= nil)
        noSelection:SetShown(s == nil)
        if s then
            local name, icon = H.SliceInfo(s)
            dIcon:SetTexture(icon)
            dName:SetText(name)
            dKind:SetText(H.KindLabel(s))
            back:SetEnabled(selectedSlice > 1)
            fwd:SetEnabled(selectedSlice < n)
            edit:SetShown(s.kind == "text")
            remove:ClearAllPoints()
            remove:SetPoint("TOPLEFT", 0, s.kind == "text" and -108 or -82)
            local note = ""
            if s.kind == "auto" then
                local a = H.AUTO_BY_ID[s.source]
                note = (a and a[4] or "") .. " Fills in by itself."
            elseif s.kind == "ring" then
                note = "Opens that ring in place. Right-click or the gamepad cancel button goes back."
            elseif s.kind == "spell" then
                note = "Casts the highest rank you know."
            end
            dNote:SetText(note)
        end
        local live = H.live[ring.id]
        liveNote:SetText(live and ("Showing now: " .. #live .. (#live == 1 and " slice" or " slices")) or "")
    end
end

-- Options page ------------------------------------------------------------------------------------
local function BuildOptions(page)
    local W_ = page:GetSize()
    local half = (W_ - 12) / 2
    local updaters = {}

    -- One grid for both cards: labels at LABEL_X, controls from CTRL_X, every button BTN_W wide.
    local LABEL_X, CTRL_X, BTN_W = 14, 128, 100
    local BTN_2 = CTRL_X + BTN_W + 4
    local TOP_H, BOTTOM_H = 172, 224
    local BOTTOM_Y = -(TOP_H + 12)
    local open = Card(page, "Mouse and keyboard", 0, 0, half, TOP_H)
    Text(open, "Open rings at", LABEL_X, -50, "GameFontHighlight")
    local at = Segmented(open, CTRL_X, -46, BTN_W, { { "Mouse cursor", "cursor" }, { "Fixed position", "center" } },
        function() return H.Option("openAt") end, function(v) H.SetOption("openAt", v) end)
    updaters[#updaters + 1] = function() at:Update() end
    Text(open, "Size", LABEL_X, -88, "GameFontHighlight")
    local size = Stepper(open, CTRL_X, -84, 60, function(delta)
        local v = math.floor(((tonumber(H.Option("scale")) or 1) + delta * 0.1) * 10 + 0.5) / 10
        H.SetOption("scale", math.max(0.6, math.min(1.6, v)))
        pageRefresh[2]()
    end)
    updaters[#updaters + 1] = function() size.value:SetText(math.floor((tonumber(H.Option("scale")) or 1) * 100 + 0.5) .. "%") end
    Text(open, "Fixed position", LABEL_X, -126, "GameFontHighlight")
    local centerPlace = Button(open, "Place", CTRL_X, -122, BTN_W, function() H.PlaceRing("centerPos", "Fixed position ring") end)
    Button(open, "Reset", BTN_2, -122, BTN_W, function() H.SetOption("centerPos", { 0.5, 0.5 }) end)
    Tooltip(centerPlace, "Fixed position", "Where rings open when \"Fixed position\" is chosen (keyboard and mouse). Drag the ring, then click Done.")

    local behave = Card(page, "While a ring is open", half + 12, 0, half, TOP_H)
    local checks = {
        Check(behave, "Show ring and slice names", 10, -46, function() return H.Option("labels") end,
            function(v) H.SetOption("labels", v) end, half - 50),
        Check(behave, "Show help under the ring", 10, -70, function() return H.Option("hints") end,
            function(v) H.SetOption("hints", v) end, half - 50),
        Check(behave, "Keyboard keys 1-9 and 0 use a slice", 10, -94, function() return H.Option("numberKeys") end,
            function(v) H.SetOption("numberKeys", v) end, half - 50),
        Check(behave, "Show slice numbers", 30, -118, function() return H.Option("slotNumbers") end,
            function(v) H.SetOption("slotNumbers", v) end, half - 70),
        Check(behave, "Ring background", 10, -142, function() return H.Option("background") end,
            function(v) H.SetOption("background", v) end, (half - 50) / 2),
        Check(behave, "Sounds", 10 + (half - 20) / 2, -142, function() return H.Option("sounds") end,
            function(v) H.SetOption("sounds", v) end, (half - 50) / 2),
    }
    Tooltip(checks[4], "Show slice numbers", "The small numbers on the slices. The number keys work either way. Keyboard only: the gamepad does not use them.")

    local pad = Card(page, "Gamepad", 0, BOTTOM_Y, half, BOTTOM_H)
    Text(pad, "Point with", LABEL_X, -46, "GameFontHighlight")
    local stick = Segmented(pad, CTRL_X, -42, BTN_W, { { "Right stick", "right" }, { "Left stick", "left" } },
        function() return H.Option("stick") end, function(v) H.SetOption("stick", v) end)
    updaters[#updaters + 1] = function() stick:Update() end
    -- Blocks the stick that points: the camera with the right stick, walking with the left.
    local still = Check(pad, "", 10, -74,
        function() return H.Option("holdCamera") end, function(v) H.SetOption("holdCamera", v) end, half - 50)
    local stillLabel = still.Text or still.text
    local stillUpdate = still.Update
    still.Update = function(self)
        stillUpdate(self)
        stillLabel:SetText(H.Option("stick") == "left" and "Stop walking while pointing" or "Keep the camera still while pointing")
    end
    Tooltip(still, "Block the pointing stick", "While a ring is open the stick you point with does nothing else: the camera with the right stick (you can still walk), walking with the left stick (the camera still turns).")
    checks[#checks + 1] = still
    local block = Check(pad, "Block both sticks", 10, -98,
        function() return H.Option("blockSticks") end, function(v) H.SetOption("blockSticks", v) end, half - 50)
    Tooltip(block, "Block both sticks", "While a ring is open both sticks go to the ring: no walking and no camera. Use it if the option above does not hold the stick.")
    checks[#checks + 1] = block
    Text(pad, "Ring position", LABEL_X, -134, "GameFontHighlight")
    local padPlace = Button(pad, "Place", CTRL_X, -130, BTN_W, function() H.PlaceRing("padPos", "Gamepad ring") end)
    Button(pad, "Reset", BTN_2, -130, BTN_W, function() H.SetOption("padPos", { 0.78, 0.42 }) end)
    Tooltip(padPlace, "Gamepad ring position", "Shows the ring on screen: drag it where you want it, then click Done.")
    Text(pad, "Ring button", LABEL_X, -164, "GameFontHighlight")
    local mode = Segmented(pad, CTRL_X, -160, BTN_W, { { "Hold", "hold" }, { "Tap", "tap" } },
        function() return H.Option("padMode") end, function(v) H.SetOption("padMode", v) end)
    updaters[#updaters + 1] = function() mode:Update() end
    Tooltip(mode[1], "Hold", "Hold the button, point, let go: the slice is used.")
    Tooltip(mode[2], "Tap", "Tap to open, point, tap again to use (tap with the stick centred closes). L1, R1, L2, R2 and A also use the slice.")
    Text(pad, "Stick released", LABEL_X, -194, "GameFontHighlight")
    local release = Segmented(pad, CTRL_X, -190, BTN_W, { { "Keep", "keep" }, { "Use", "use" } },
        function() return H.StickRelease() end, function(v) H.SetOption("padRelease", v) end)
    updaters[#updaters + 1] = function() release:Update() end
    Tooltip(release[1], "Stick released: Keep", "The slice you pointed at stays selected when you let go of the stick. Use it with the ring button, L1, R1, L2, R2 or A. Works in combat too.")
    Tooltip(release[2], "Stick released: Use", "Point at a slice and let go of the stick: the slice is used, like Blizzard's own radial menus. Works in combat too. To close without using anything, press the ring's button again (Tap) or B before you let go.")

    local how = Card(page, "How to use", half + 12, BOTTOM_Y, half, BOTTOM_H)
    local howText = Note(how, H.HelpText(), 14, -38, half - 28)
    howText:SetSpacing(2)

    pageRefresh[2] = function()
        for _, fn in ipairs(updaters) do fn() end
        for _, check in ipairs(checks) do check:Update() end
        howText:SetText(H.HelpText())
    end
end

-- The help under Options shows only what applies to the current settings.
function H.HelpText()
    local head = "|cffe8c070"
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    add(head .. "Keyboard and mouse|r")
    add("Hold the key, point at a slice, let go to use it.")
    add("Let go in the middle: it stays open. Click a slice" ..
        (H.Option("numberKeys") == true and " or press 1-9, 0." or "."))
    add("Right-click: back. Esc or middle click: close.")
    add(" ")
    add(head .. "Gamepad|r")
    local tap, use = H.Option("padMode") == "tap", H.StickRelease() == "use"
    local stick = H.Option("stick") == "left" and "left" or "right"
    add((tap and "Tap the button, tilt the %s stick to a slice." or "Hold the button, tilt the %s stick to a slice."):format(stick))
    if use then
        add(tap and "Let go of the stick to use it, or tap again." or "Let go of the stick or the button to use it.")
    else
        add(tap and "Tap again to use it. The stick keeps the pick." or "Let go of the button to use it. The stick keeps the pick.")
    end
    add("A, L1, R1, L2, R2 also use it. B: back or close.")
    if H.Option("blockSticks") then
        add("Both sticks are blocked.")
    elseif H.Option("holdCamera") then
        add(stick == "left" and "Walking stops." or "The camera stays still.")
    end
    return table.concat(lines, "\n")
end


-- Styles page ---------------------------------------------------------------------------------------
-- All styles side by side, drawn live with the real ring code's art and the icons of the
-- ring selected on the Rings tab. Click a preview to replay its opening.
local SAMPLE_ICONS = { "Interface\\Icons\\INV_Potion_54", "Interface\\Icons\\INV_Misc_Food_15",
    "Interface\\Icons\\Ability_Mount_RidingHorse", "Interface\\Icons\\INV_Misc_Bandage_15",
    "Interface\\Icons\\INV_Misc_Rune_01", "Interface\\Icons\\Spell_Holy_Heal" }

local function BuildStyles(page)
    local W_, Hh = page:GetSize()
    local gap = 8
    local cw = (W_ - gap * 4) / 5
    local AREA = 150
    local cards = {}
    -- The hint sits on the footer line (left of the version and Close), so the cards can use the
    -- whole page height. SelectPage shows it on this tab; a combat note takes its place.
    styleHint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    styleHint:SetPoint("BOTTOMLEFT", 26, 18)
    styleHint:SetTextColor(unpack(NOTE))
    styleHint:SetText("Click a preview to see it open. Each ring can also choose its own style on the Rings tab.")
    styleHint:Hide()

    for index, id in ipairs(H.RingSkins.order) do
        local skin = H.RingSkins.list[id]
        local card = Card(page, nil, (index - 1) * (cw + gap), 0, cw, Hh)
        card.skin = skin
        local area = CreateFrame("Button", nil, card)
        area:SetPoint("TOP", 0, -6)
        area:SetSize(cw - 8, AREA + 10)
        area:SetClipsChildren(true)
        local stage = CreateFrame("Frame", nil, area)
        stage:SetPoint("CENTER")
        stage:SetSize(1, 1)
        card.stage = stage
        card.slots = {}
        local pointer = CreateFrame("Frame", nil, stage)
        pointer:SetFrameLevel(stage:GetFrameLevel() + 30)
        local pointerTexture = pointer:CreateTexture(nil, "OVERLAY")
        pointerTexture:SetAllPoints()

        local name = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        name:SetPoint("TOP", area, "BOTTOM", 0, -6)
        name:SetText(id .. "  " .. skin.name)
        local desc = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        desc:SetPoint("TOP", name, "BOTTOM", 0, -6)
        desc:SetWidth(cw - 16)
        desc:SetText(skin.desc)
        desc:SetTextColor(unpack(NOTE))
        local use = Button(card, "Use as default", 8, -(Hh - 32), cw - 16, function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            H.SetOption("style", id)
        end)
        local wash = card:CreateTexture(nil, "BACKGROUND", nil, -1)
        wash:SetAllPoints()
        wash:SetColorTexture(1, 0.72, 0.2, 0.1)

        local colorRow
        if id == "D" then
            -- Stacked options above "Use as default": Blue, Class, Custom (+ its colour gem).
            local ROW = 25
            local y = -(Hh - 32) + 12 + 3 * ROW   -- top of the first button
            local heading = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            heading:SetPoint("TOPLEFT", 8, y + 16)
            heading:SetText("Rune colour")
            local bw = cw - 16
            local function PickCustom()
                local c = H.Option("runeCustom") or { 0.7, 0.4, 1 }
                local before = { c[1], c[2], c[3] }
                local function Apply(r, g, b)
                    H.SetOption("runeCustom", { r, g, b })
                    H.SetOption("runeColor", "custom")
                end
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = c[1], g = c[2], b = c[3], hasOpacity = false,
                    swatchFunc = function() Apply(ColorPickerFrame:GetColorRGB()) end,
                    cancelFunc = function() Apply(before[1], before[2], before[3]) end,
                })
            end
            colorRow = Segmented(card, 8, y, bw, { { "Blue", "blue" }, { "Class", "class" }, { "Custom", "custom" } },
                function() return H.Option("runeColor") end,
                function(v)
                    if v == "custom" then PickCustom() else H.SetOption("runeColor", v) end
                end)
            for i = 1, 3 do
                local b = colorRow[i]
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", card, "TOPLEFT", 8, y - (i - 1) * ROW)
                b:SetWidth(i == 3 and bw - 30 or bw)
            end
            -- The custom colour as a round gem set in the style's own gold affix ring.
            local gem = CreateFrame("Button", nil, card)
            gem:SetSize(24, 24)
            gem:SetPoint("LEFT", colorRow[3], "RIGHT", 4, 0)
            local dark = gem:CreateTexture(nil, "BACKGROUND")
            dark:SetPoint("CENTER"); dark:SetSize(20, 20)
            dark:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            dark:SetVertexColor(0, 0, 0, 0.9)
            local fill = gem:CreateTexture(nil, "ARTWORK")
            fill:SetPoint("CENTER"); fill:SetSize(17, 17)
            fill:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            local shine = gem:CreateTexture(nil, "ARTWORK", nil, 1)
            shine:SetPoint("CENTER", -2, 2); shine:SetSize(9, 9)
            shine:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            shine:SetBlendMode("ADD"); shine:SetVertexColor(1, 1, 1, 0.25)
            local rim = gem:CreateTexture(nil, "OVERLAY")
            rim:SetPoint("CENTER"); rim:SetSize(26, 26)
            if C_Texture.GetAtlasInfo("ChallengeMode-AffixRing-Sm") then rim:SetAtlas("ChallengeMode-AffixRing-Sm")
            else rim:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask"); rim:SetVertexColor(0.8, 0.65, 0.3, 1) end
            local hover = gem:CreateTexture(nil, "HIGHLIGHT")
            hover:SetPoint("CENTER"); hover:SetSize(26, 26)
            hover:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            hover:SetBlendMode("ADD"); hover:SetVertexColor(1, 0.85, 0.5, 0.25)
            gem:SetScript("OnClick", function() PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON); PickCustom() end)
            Tooltip(gem, "Custom colour", "Click to pick the colour used by Custom.")
            colorRow.swatch = fill
            Tooltip(colorRow[2], "Class colour", "Your class colour, kept bright.")
            Tooltip(colorRow[3], "Custom colour", "Pick any colour. Click again to change it.")
        end

        local t, animating = 0, false
        function card:Layout(icons)
            local n = #icons
            local r = H.RingRadius(n)
            for i = 1, math.max(n, #self.slots) do
                local slot = self.slots[i]
                if not slot then
                    slot = CreateFrame("Frame", nil, stage)
                    H.RingSkins.BuildSlotKit(slot)
                    self.slots[i] = slot
                end
                if icons[i] then
                    H.RingSkins.ApplySlot(slot, skin)
                    slot.icon:SetTexture(icons[i])
                    slot.over:SetShown(i == 1)
                    slot:SetScale(i == 1 and (skin.hoverScale or 1.12) or 1)
                    slot:Show()
                else
                    slot:Hide()
                end
            end
            local art = H.RingSkins.RingArt(stage, skin)
            local extent = 2 * (r + 26)
            if art and H.Option("background") ~= false then
                art:Layout(r)
                H.RingSkins.PreviewTone(art)
                H.RingSkins.ShowRingArt(art, true)
                extent = math.max(extent, art:Extent(r))
            else
                H.RingSkins.ShowRingArt(art, false)
            end
            self.art, self.r, self.n = art, r, n
            stage:SetScale(math.min(1, (cw - 10) / extent, AREA / extent))
            local hasPointer = H.RingSkins.ApplyPointer(pointerTexture, pointer, skin)
            if hasPointer and n > 0 then
                local p = skin.pointer
                pointer:ClearAllPoints()
                pointer:SetPoint("CENTER", stage, "CENTER", 0, r * (p.dist or 0.6))
                pointerTexture:SetRotation(p.rot or 0)
                pointer:Show()
            end
            self:Place(1, 0)
            if colorRow then
                colorRow:Update()
                local c = H.Option("runeCustom") or { 0.7, 0.4, 1 }
                colorRow.swatch:SetVertexColor(c[1], c[2], c[3], 1)
            end
            use:SetEnabled(H.Option("style") ~= id)
            use:SetText(H.Option("style") == id and "Default" or "Use as default")
            wash:SetShown(H.Option("style") == id)
        end
        function card:Place(radiusFactor, angleOffset, _, perSlot)
            local r = H.RingSkins.SlotRadius(skin, self.r or 60) * radiusFactor
            for i = 1, self.n or 0 do
                local a = (i - 1) * 2 * math.pi / self.n + (angleOffset or 0)
                local slot = self.slots[i]
                slot:ClearAllPoints()
                slot:SetPoint("CENTER", stage, "CENTER", r * math.sin(a), r * math.cos(a))
                local alpha, scale = 1, 1
                if perSlot then alpha, scale = perSlot(i, self.n) end
                slot:SetAlpha(alpha)
                slot:SetScale(scale * (i == 1 and (skin.hoverScale or 1.12) or 1))
            end
        end
        area:SetScript("OnClick", function()
            t, animating = 0, true
        end)
        area:SetScript("OnUpdate", function(_, elapsed)
            if card.art and card.art.Update then card.art:Update(elapsed) end
            if animating then
                t = t + elapsed
                local p = math.min(1, t / (skin.openTime or 0.12))
                local radiusFactor, angleOffset, alpha, perSlot = H.RingSkins.Anim(skin, p)
                stage:SetAlpha(alpha)
                card:Place(radiusFactor, angleOffset, alpha, perSlot)
                if p >= 1 then animating = false; stage:SetAlpha(1); card:Place(1, 0) end
            end
        end)
        Tooltip(area, id .. "  " .. skin.name, "Click to replay the opening.")
        cards[index] = card
    end

    pageRefresh[3] = function()
        local icons = {}
        local ring = CurrentRing() or VisibleRings()[1]
        local live = ring and H.live[ring.id]
        for i, slice in ipairs(live or {}) do
            if i > 8 then break end
            local _, icon = H.SliceInfo(slice)
            icons[i] = icon
        end
        if #icons < 3 then icons = SAMPLE_ICONS end
        for _, card in ipairs(cards) do card:Layout(icons) end
    end
end

-- Placement tool: a ring outline you drag to where rings should open --------------------------------
local placer
function H.PlaceRing(key, title)
    if not placer then
        placer = CreateFrame("Frame", "HaloPlacer", UIParent)
        placer:SetFrameStrata("FULLSCREEN_DIALOG")
        placer:SetSize(180, 180)
        placer:SetMovable(true); placer:EnableMouse(true); placer:SetClampedToScreen(true)
        placer:RegisterForDrag("LeftButton")
        placer:SetScript("OnDragStart", function(self) self:StartMoving() end)
        placer:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        -- The ring as it will really look: the default style, with the icons of the ring
        -- selected on the Rings tab (sample icons when it has fewer than three).
        placer.stage = CreateFrame("Frame", nil, placer)
        placer.stage:SetPoint("CENTER")
        placer.stage:SetSize(1, 1)
        placer.slots = {}
        placer.pointer = CreateFrame("Frame", nil, placer.stage)
        placer.pointer:SetFrameLevel(placer.stage:GetFrameLevel() + 30)
        placer.pointerTexture = placer.pointer:CreateTexture(nil, "OVERLAY")
        placer.pointerTexture:SetAllPoints()
        -- A small dot marks the exact point rings open at.
        local dotHolder = CreateFrame("Frame", nil, placer)
        dotHolder:SetAllPoints()
        dotHolder:SetFrameLevel(placer.stage:GetFrameLevel() + 60)
        local dot = dotHolder:CreateTexture(nil, "OVERLAY")
        dot:SetPoint("CENTER"); dot:SetSize(6, 6); dot:SetTexture(ROUND_MASK); dot:SetVertexColor(1, 0.82, 0, 0.9)
        placer.title = placer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        placer.title:SetPoint("BOTTOM", placer, "TOP", 0, 22)
        local help = placer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        help:SetPoint("BOTTOM", placer, "TOP", 0, 6)
        help:SetText("Drag to move")
        placer:SetScript("OnUpdate", function(self, elapsed)
            if self.art and self.art.Update then self.art:Update(elapsed) end
        end)
        function placer:Refresh()
            local skin = H.RingSkins.Get(H.Option("style"))
            local icons = {}
            local ring = CurrentRing() or VisibleRings()[1]
            for i, slice in ipairs(ring and H.live[ring.id] or {}) do
                if i > 8 then break end
                local _, icon = H.SliceInfo(slice)
                icons[i] = icon
            end
            if #icons < 3 then icons = SAMPLE_ICONS end
            local n = #icons
            local r = H.RingRadius(n)
            for i = 1, math.max(n, #self.slots) do
                local slot = self.slots[i]
                if not slot then
                    slot = CreateFrame("Frame", nil, self.stage)
                    H.RingSkins.BuildSlotKit(slot)
                    self.slots[i] = slot
                end
                if icons[i] then
                    H.RingSkins.ApplySlot(slot, skin)
                    slot.icon:SetTexture(icons[i])
                    slot.over:SetShown(i == 1)
                    slot:SetScale(i == 1 and (skin.hoverScale or 1.12) or 1)
                    local a = (i - 1) * 2 * math.pi / n
                    local sr = H.RingSkins.SlotRadius(skin, r)
                    slot:ClearAllPoints()
                    slot:SetPoint("CENTER", self.stage, "CENTER", sr * math.sin(a), sr * math.cos(a))
                    slot:Show()
                else
                    slot:Hide()
                end
            end
            local art = H.RingSkins.RingArt(self.stage, skin)
            local extent = 2 * (r + 26)
            if art and H.Option("background") ~= false then
                art:Layout(r)
                H.RingSkins.PreviewTone(art)
                H.RingSkins.ShowRingArt(art, true)
                extent = math.max(extent, art:Extent(r))
            else
                H.RingSkins.ShowRingArt(art, false)
            end
            self.art = art
            if H.RingSkins.ApplyPointer(self.pointerTexture, self.pointer, skin) then
                local p = skin.pointer
                self.pointer:ClearAllPoints()
                self.pointer:SetPoint("CENTER", self.stage, "CENTER", 0, r * (p.dist or 0.6))
                self.pointerTexture:SetRotation(p.rot or 0)
                self.pointer:Show()
            end
            local scale = tonumber(H.Option("scale")) or 1
            self.stage:SetScale(scale)
            self:SetSize(extent * scale, extent * scale)
        end
        local done = CreateFrame("Button", nil, placer, "UIPanelButtonTemplate")
        done:SetSize(80, 22); done:SetPoint("TOP", placer, "BOTTOM", 0, -6); done:SetText("Done")
        if skin then skin.Button(done) end
        done:SetScript("OnClick", function() placer:Finish() end)
        placer:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then placer:Finish() end end)
        function placer:Finish()
            local x, y = self:GetCenter()
            local w, h = UIParent:GetWidth(), UIParent:GetHeight()
            local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if x and w > 0 and h > 0 then
                H.SetOption(self.key, { math.floor(x * scale / w * 1000 + 0.5) / 1000, math.floor(y * scale / h * 1000 + 0.5) / 1000 })
            end
            self:Hide()
            if frame and self.reopen then frame:Show() end
        end
    end
    local pos = H.Position(key)
    placer.key = key
    placer.title:SetText(title)
    placer:ClearAllPoints()
    placer:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1] * UIParent:GetWidth(), pos[2] * UIParent:GetHeight())
    placer:Refresh()
    placer.reopen = frame and frame:IsShown()
    if frame then userClose = true; frame:Hide() end
    placer:Show()
end

-- Window ---------------------------------------------------------------------------------------------
local header
local function SelectPage(index)
    index = pageFrames[index] and index or 1
    H.db.window.page = index
    for i, page in ipairs(pageFrames) do
        page:SetShown(i == index)
        tabs[i].selected:SetShown(i == index)
    end
    header:SetText(PAGES[index][1])
    if styleHint then styleHint:SetShown(index == 3 and not InCombatLockdown()) end
    pageRefresh[index]()
end

local function Build()
    skin = H.Skin
    frame = CreateFrame("Frame", "HaloOptions", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(W, H_)
    local point = H.db.window.point
    if type(point) == "table" and point[1] then
        frame:SetPoint(point[1], UIParent, point[3] or point[1], point[4] or 0, point[5] or 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetToplevel(true)
    table.insert(UISpecialFrames, "HaloOptions")
    if FrameGambitAPI and FrameGambitAPI.RegisterCinematicWindow then
        pcall(FrameGambitAPI.RegisterCinematicWindow, frame)
    end
    local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetText("Halo")
    local _, xButton = skin.Frame(frame, heading)
    if xButton then xButton:HookScript("PreClick", function() userClose = true end) end
    hooksecurefunc(frame, "StopMovingOrSizing", function(self)
        local p, _, rel, x, y = self:GetPoint()
        H.db.window.point = { p, nil, rel, x, y }
    end)
    local border = frame.legacyBorder or frame

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 26, -42)
    content:SetPoint("BOTTOMRIGHT", -22, 44)
    header = Text(content, "", 2, -2, "GameFontNormalLarge")
    local PW, PH = W - 48, H_ - 122
    Line(content, 0, -26, PW, 1, 0.45)

    local close = Button(frame, "Close", 0, 0, 96, function() userClose = true; frame:Hide() end, 22)
    close:ClearAllPoints(); close:SetPoint("BOTTOMRIGHT", -18, 13)
    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("RIGHT", close, "LEFT", -10, 0)
    version:SetText("v" .. H.version)
    local combat = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    combat:SetPoint("BOTTOMLEFT", 26, 18)
    combat:SetTextColor(1, 0.5, 0.25)
    local function CombatNote(inCombat)
        combat:SetText(inCombat and "In combat: changes apply when combat ends." or "")
        if styleHint then styleHint:SetShown(not inCombat and H.db.window.page == 3) end
    end
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event) CombatNote(event == "PLAYER_REGEN_DISABLED") end)

    -- Same size as Forever Names' side tabs (90% of Blizzard's), so both windows match.
    local TAB_SCALE = 0.9
    local tabInfo = C_Texture.GetAtlasInfo("common-sidetab")
    local tabWidth, tabHeight = tabInfo and tabInfo.width or 43, tabInfo and (tabInfo.height - 5) or 55
    for i, info in ipairs(PAGES) do
        local page = CreateFrame("Frame", nil, content)
        page:SetPoint("TOPLEFT", 0, -36)
        page:SetSize(PW, PH)
        page:Hide()
        pageFrames[i] = page
        local tab = CreateFrame("Button", nil, frame)
        tab:SetSize(tabWidth, tabHeight)
        tab:SetScale(TAB_SCALE)
        -- Offsets are in the tab's own (scaled) units, so the first tab keeps its place.
        if i == 1 then tab:SetPoint("TOPLEFT", border, "TOPRIGHT", 0, -44 / TAB_SCALE)
        else tab:SetPoint("TOPLEFT", tabs[i - 1], "BOTTOMLEFT", 0, -2) end
        local background = tab:CreateTexture(nil, "BACKGROUND")
        background:SetAtlas("common-sidetab", true)
        background:SetPoint("CENTER")
        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(info[2])
        icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
        icon:SetPoint("CENTER", -4, 0)
        icon:SetSize(50, 50)
        local mask = tab:CreateMaskTexture()
        mask:SetAtlas("common-sidetab-mask", true)
        mask:SetPoint("CENTER")
        icon:AddMaskTexture(mask)
        tab.selected = tab:CreateTexture(nil, "OVERLAY")
        tab.selected:SetAtlas("common-sidetab-selected", true)
        tab.selected:SetPoint("CENTER")
        local hover = tab:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAtlas("common-sidetab-hover", true)
        hover:SetPoint("CENTER")
        tab:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", -3, -1) end)
        tab:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", -4, 0) end)
        tab:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            SelectPage(i)
        end)
        Tooltip(tab, info[1], info[3])
        tabs[i] = tab
    end

    BuildRings(pageFrames[1])
    BuildOptions(pageFrames[2])
    BuildStyles(pageFrames[3])

    frame:SetScript("OnShow", function(self)
        if not quietShow then PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN) end
        quietShow = false
        CombatNote(InCombatLockdown())   -- also when the window opens mid-fight
        SelectPage(H.db.window.page or 1)
    end)
    -- Stay open while the spellbook, talents or macro window is open (you drag from those),
    -- unless you closed Halo yourself. Esc closes those panels first, so Esc still works.
    local function DragSourceOpen()
        for _, name in ipairs({ "PlayerSpellsFrame", "SpellBookFrame", "MacroFrame" }) do
            local f = _G[name]
            if f and f.IsShown and f:IsShown() then return true end
        end
        return false
    end
    frame:SetScript("OnHide", function(self)
        if not userClose then
            C_Timer.After(0, function()
                if not self:IsShown() and not userClose and DragSourceOpen() then
                    quietShow = true
                    self:Show()
                end
            end)
        end
        C_Timer.After(0, function() userClose = false end)
        if self:IsShown() then return end
        PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE)
        if macroEditor then macroEditor:Hide() end
    end)
end

-- One refresh per frame at most, only while open.
local queued = false
local function QueueRefresh()
    if not (frame and frame:IsShown()) or queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        if frame and frame:IsShown() then
            local refresh = pageRefresh[H.db.window.page or 1]
            if refresh then refresh() end
        end
    end)
end
H.On("changed", QueueRefresh)
H.On("compiled", QueueRefresh)
H.On("options", QueueRefresh)

function H.ToggleOptions(page)
    if not frame then Build() end
    if frame:IsShown() and not page then userClose = true; frame:Hide()
    else
        if page then H.db.window.page = page end
        frame:Show()
    end
end

-- Addon compartment / Settings entry.
function Halo_OpenOptions() H.ToggleOptions() end
H.On("login", function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local panel = CreateFrame("Frame")
        local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        open:SetSize(160, 24)
        open:SetPoint("TOPLEFT", 16, -16)
        open:SetText("Open Halo")
        open:SetScript("OnClick", function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
            H.ToggleOptions(1)
        end)
        local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        note:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -10)
        note:SetText("Or type /halo")
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Halo")
        if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
    end
end)
