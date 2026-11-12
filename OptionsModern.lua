-- Layout B of the Halo window (the footer's Layout A | B switch, /halo layout a|b).
-- Same settings and the same ring parts as layout A (Options.lua builds those and hands
-- them over as K); only the arrangement differs:
--   Rings:   a header line (icon, name, Only this character, a ... menu for Duplicate, Macro and
--            Delete), one line of keys and style, the ring bigger, and beside it an inspector:
--            the selected slice, or how to fill the ring, and a This ring card.
--   Options: one label column and one control column per card; a group of choices or a
--            stepper sits in one plate; a row that depends on another shows only while it
--            applies; explanations move into the rows' tooltips.

local _, H = ...

local GOLD, NOTE, PLAIN = { 1, 0.82, 0 }, { 0.80, 0.77, 0.70 }, { 0.82, 0.82, 0.82 }
local PLATE = "common-button-list-collapseExpand"

-- Plates and cells ---------------------------------------------------------------------------------
local measure
local function Width(template, text)
    if not measure then
        measure = UIParent:CreateFontString(nil, "ARTWORK")
        measure:Hide()
    end
    measure:SetFontObject(template)
    measure:SetText(text)
    local width = measure:GetStringWidth()
    return tonumber(width) or #text * 7
end

local function Tip(owner, title, body)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title(self) or title, 1, 0.82, 0)
        local text = type(body) == "function" and body(self) or body
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- One frame around a group of cells.
local function Group(parent, width)
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(width, 22)
    if H.Skin and H.Skin.Plate then
        local art = H.Skin.Plate(group, PLATE)
        group:HookScript("OnSizeChanged", function() art:Update() end)
    end
    group.x = 0
    return group
end
local function Divider(group, x)
    local divider = group:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", x, -4)
    divider:SetSize(1, 14)
    divider:SetColorTexture(0.68, 0.50, 0.26, 0.4)
end
local function Cell(group, text, width, onClick)
    local cell = CreateFrame("Button", nil, group)
    cell:SetPoint("TOPLEFT", group.x, 0)
    cell:SetSize(width, 22)
    if group.x > 0 then Divider(group, group.x) end
    group.x = group.x + width
    cell.wash = cell:CreateTexture(nil, "ARTWORK")
    cell.wash:SetPoint("TOPLEFT", 3, -3); cell.wash:SetPoint("BOTTOMRIGHT", -3, 3)
    cell.wash:SetColorTexture(1, 0.72, 0.2, 0.22)
    cell.wash:Hide()
    local hover = cell:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", 3, -3); hover:SetPoint("BOTTOMRIGHT", -3, 3)
    hover:SetColorTexture(1, 0.72, 0.2, 0.12)
    cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cell.label:SetPoint("CENTER", 0, 0)
    cell.label:SetText(text)
    cell:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("CENTER", 1, -1) end end)
    cell:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    cell:SetScript("OnDisable", function(self) self.label:SetAlpha(0.4) end)
    cell:SetScript("OnEnable", function(self) self.label:SetAlpha(1) end)
    cell:SetScript("OnClick", onClick)
    return cell
end
local function Paint(cell, selected)
    cell.wash:SetShown(selected)
    cell.label:SetTextColor(unpack(selected and GOLD or PLAIN))
end

-- [ choice | choice ] in one plate, each cell width wide (or as wide as its text).
local function Choice(parent, choices, get, set, width)
    local widths, total = {}, 0
    for i, choice in ipairs(choices) do
        widths[i] = math.max(26, Width("GameFontHighlight", choice[1]) + 14)
        total = total + widths[i]
    end
    if width then
        local used = 0
        for i = 1, #choices do
            widths[i] = math.floor(width / #choices)
            used = used + widths[i]
        end
        widths[#choices] = widths[#choices] + width - used
        total = width
    end
    local group = Group(parent, total)
    group.cells = {}
    for i, choice in ipairs(choices) do
        group.cells[i] = Cell(group, choice[1], widths[i], function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            set(choice[2])
            group:Update()
        end)
    end
    function group:Update()
        local current = get()
        for i, choice in ipairs(choices) do Paint(self.cells[i], choice[2] == current) end
    end
    group:Update()
    return group
end

-- [ - value + ] in one plate.
local function StepGroup(parent, x, y, valueWidth, onStep)
    local group = Group(parent, 48 + valueWidth)
    group:SetPoint("TOPLEFT", x, y)
    group:EnableMouse(true)   -- its tooltip shows over the value too
    local stepper = { group = group }
    stepper.minus = Cell(group, "-", 24, function() onStep(-1) end)
    Divider(group, 24)
    group.x = 24 + valueWidth
    stepper.plus = Cell(group, "+", 24, function() onStep(1) end)
    stepper.value = group:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    stepper.value:SetPoint("CENTER", 0, 0)
    stepper.value:SetWidth(valueWidth); stepper.value:SetJustifyH("CENTER")
    return stepper
end

-- The footer's Layout A | B switch (both layouts).
function H.LayoutSwitch(parent, get, set)
    local group = Choice(parent, { { "A", "a" }, { "B", "b" } }, get, set)
    for i, cell in ipairs(group.cells) do
        Tip(cell, i == 1 and "Layout A" or "Layout B", i == 1 and "Classic" or "Redesigned")
    end
    return group
end

-- Cards of rows (Options page) ---------------------------------------------------------------------
local ROW, GAP, PAD, INDENT, CONTROL_X = 28, 10, 14, 20, 132

local function Sheet(parent, K)
    local sheet = { columns = {}, updaters = {} }
    local function On(fn) sheet.updaters[#sheet.updaters + 1] = fn end

    local Card = {}
    Card.__index = Card
    function Card:Row(o, height)
        o = o or {}
        local row = { frame = CreateFrame("Frame", nil, self.frame), height = height or ROW, when = o.when,
            x = PAD + (o.indent and INDENT or 0) }
        row.frame:SetSize(self.width, row.height)
        self.rows[#self.rows + 1] = row
        self.row = row
        -- Hovering anywhere on the row explains it.
        if o.tip then
            row.frame:EnableMouse(true)
            Tip(row.frame, o.tip[1], o.tip[2])
        end
        return row
    end
    local function Label(row, text)
        local label = row.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", row.x, 0)
        label:SetJustifyH("LEFT")
        label:SetText(text)
        return label
    end
    -- A switch; o.same puts it beside the previous switch, o.label (function) renames it.
    function Card:Check(text, get, set, o)
        o = o or {}
        local row, x
        if o.same and self.row then
            row, x = self.row, self.row.next
        else
            row = self:Row(o); x = row.x
        end
        local check = K.Check(row.frame, text, x - 4, -1, get, set, o.width or 200)
        local width = math.min(o.width or 200, Width("GameFontHighlight", text) + 4)
        if check.SetHitRectInsets then check:SetHitRectInsets(0, -width, 0, 0) end
        if o.tip then Tip(check, o.tip[1], o.tip[2]) end
        row.next = x + 30 + width + 16
        On(function()
            check:Update()
            if o.label then (check.Text or check.text):SetText(o.label()) end
        end)
        return check
    end
    -- Label, then [ a | b ] filling the control column. o.tips: one {title, body} per choice.
    function Card:Seg(text, choices, get, set, o)
        o = o or {}
        local row = self:Row(o)
        Label(row, text)
        local group = Choice(row.frame, choices, get, set, self.width - PAD - CONTROL_X)
        group:SetPoint("TOPLEFT", CONTROL_X, -3)
        if o.tips then for i, tip in ipairs(o.tips) do Tip(group.cells[i], tip[1], tip[2]) end end
        On(function() group:Update() end)
        return group
    end
    function Card:Step(text, value, onStep, o)
        o = o or {}
        local row = self:Row(o)
        Label(row, text)
        local stepper = StepGroup(row.frame, CONTROL_X, -3, 52, onStep)
        On(function() stepper.value:SetText(value()) end)
        return stepper
    end
    -- Label, then plain buttons side by side: { {text, onClick}, ... }
    function Card:Buttons(text, list, o)
        o = o or {}
        local row = self:Row(o)
        Label(row, text)
        local avail = self.width - PAD - CONTROL_X
        local width = (avail - 4 * (#list - 1)) / #list
        for i, b in ipairs(list) do
            K.Button(row.frame, b[1], CONTROL_X + (i - 1) * (width + 4), -3, width, b[2])
        end
    end
    -- Text that grows with what it says.
    function Card:Note(text)
        local row = self:Row(nil, 20)
        local note = K.Note(row.frame, "", PAD, -2, self.width - 2 * PAD)
        note:SetSpacing(2)
        row.note = note
        On(function() note:SetText(text()) end)
        return note
    end

    function sheet:Column(x, width)
        local col = { x = x, cards = {} }
        self.columns[#self.columns + 1] = col
        function col:Card(title)
            local card = setmetatable({ width = width, rows = {} }, Card)
            card.frame = CreateFrame("Frame", nil, parent)
            card.frame:SetSize(width, 40)
            local wash = card.frame:CreateTexture(nil, "BACKGROUND", nil, -2)
            wash:SetAllPoints()
            wash:SetColorTexture(0.25, 0.17, 0.085, 0.16)
            -- Edges follow the card as its rows come and go.
            local function Edge(from, to, alpha, vertical)
                local line = card.frame:CreateTexture(nil, "BORDER")
                line:SetPoint(from, 0, 0); line:SetPoint(to, 0, 0)
                if vertical then line:SetWidth(1) else line:SetHeight(1) end
                line:SetColorTexture(0.68, 0.50, 0.26, alpha)
            end
            Edge("TOPLEFT", "TOPRIGHT", 0.55); Edge("BOTTOMLEFT", "BOTTOMRIGHT", 0.3)
            Edge("TOPLEFT", "BOTTOMLEFT", 0.3, true); Edge("TOPRIGHT", "BOTTOMRIGHT", 0.3, true)
            K.Text(card.frame, title, PAD, -11, "GameFontNormal")
            card.top = 32
            self.cards[#self.cards + 1] = card
            return card
        end
        return col
    end

    -- Rows that do not apply fold away; cards close up under each other.
    function sheet:Update()
        for _, fn in ipairs(self.updaters) do fn() end
        for _, col in ipairs(self.columns) do
            local top = 0
            for _, card in ipairs(col.cards) do
                local y = card.top
                for _, row in ipairs(card.rows) do
                    local shown = not row.when or row.when()
                    row.frame:SetShown(shown)
                    if shown then
                        if row.note then
                            local height = row.note:GetStringHeight()
                            row.height = math.max(20, (tonumber(height) or 14) + 8)
                        end
                        row.frame:ClearAllPoints()
                        row.frame:SetPoint("TOPLEFT", 0, -y)
                        row.frame:SetHeight(row.height)
                        y = y + row.height
                    end
                end
                card.frame:ClearAllPoints()
                card.frame:SetPoint("TOPLEFT", col.x, -top)
                card.frame:SetHeight(y + 8)
                top = top + y + 8 + GAP
            end
        end
    end
    return sheet
end

-- Options page -------------------------------------------------------------------------------------
function H.BuildOptionsB(page, K)
    local W_ = page:GetSize()
    local half = (W_ - 12) / 2
    local sheet = Sheet(page, K)
    local left, right = sheet:Column(0, half), sheet:Column(half + 12, half)
    local function Opt(key) return function() return H.Option(key) end end
    local function SetOpt(key) return function(v) H.SetOption(key, v) end end

    local open = left:Card("Mouse and keyboard")
    open:Seg("Open rings at", { { "Mouse cursor", "cursor" }, { "Fixed position", "center" } }, Opt("openAt"), SetOpt("openAt"),
        {})
    open:Buttons("Position", {
        { "Place", function() H.PlaceRing("centerPos", "Fixed position ring") end },
        { "Reset", function() H.SetOption("centerPos", { 0.5, 0.5 }) end },
    }, { indent = true, when = function() return H.Option("openAt") == "center" end, })
    open:Step("Size", function() return math.floor((tonumber(H.Option("scale")) or 1) * 100 + 0.5) .. "%" end, function(delta)
        local v = math.floor(((tonumber(H.Option("scale")) or 1) + delta * 0.1) * 10 + 0.5) / 10
        H.SetOption("scale", math.max(0.6, math.min(1.6, v)))
        K.Refresh(2)
    end, {})

    local pad = left:Card("Gamepad")
    pad:Seg("Point with", { { "Right stick", "right" }, { "Left stick", "left" } }, Opt("stick"), SetOpt("stick"))
    pad:Seg("Ring button", { { "Hold", "hold" }, { "Tap", "tap" } }, Opt("padMode"), SetOpt("padMode"), { tips = {
        { "Hold", "Release to use" },
        { "Tap", "Tap again to use" },
    } })
    pad:Seg("Stick released", { { "Keep", "keep" }, { "Use", "use" } }, function() return H.StickRelease() end, SetOpt("padRelease"), { tips = {
        { "Stick released: Keep", "Slice stays selected" },
        { "Stick released: Use", "Uses the slice" },
    } })
    local function StillLabel()
        return H.Option("stick") == "left" and "Hold walking" or "Hold camera"
    end
    pad:Check(StillLabel(), Opt("holdCamera"), SetOpt("holdCamera"), { width = half - 50, label = StillLabel })
    pad:Check("Block both sticks", Opt("blockSticks"), SetOpt("blockSticks"), { width = half - 50,
        tip = { "Block both sticks", "No walking, no camera" } })
    pad:Buttons("Position", {
        { "Place", function() H.PlaceRing("padPos", "Gamepad ring") end },
        { "Reset", function() H.SetOption("padPos", { 0.78, 0.42 }) end },
    }, {})

    local behave = right:Card("While a ring is open")
    behave:Check("Show ring and slice names", Opt("labels"), SetOpt("labels"), { width = half - 50 })
    behave:Check("Show help under the ring", Opt("hints"), SetOpt("hints"), { width = half - 50 })
    behave:Check("Number keys", Opt("numberKeys"), SetOpt("numberKeys"), { width = half - 50,
        tip = { "Number keys", "1-9, 0" } })
    behave:Check("Show slice numbers", Opt("slotNumbers"), SetOpt("slotNumbers"), { width = half - 70, indent = true,
        when = function() return H.Option("numberKeys") == true end,
        tip = { "Show slice numbers", "Keyboard only" } })
    behave:Check("Ring background", Opt("background"), SetOpt("background"), { width = 130 })
    behave:Check("Sounds", Opt("sounds"), SetOpt("sounds"), { width = 100, same = true })

    local how = right:Card("Controls")
    how:Note(H.HelpText)

    return function() sheet:Update() end
end

-- Rings page ---------------------------------------------------------------------------------------
function H.BuildRingsB(page, K)
    local W_, Hh = page:GetSize()
    local LIST_W = K.LIST_W
    local list = K.RingList(page, 0, 0, LIST_W, Hh - 30, { tidy = true })
    Tip(K.Button(page, "+  New ring", 0, -(Hh - 24), LIST_W, K.NewRing), "New ring",
        nil)

    local EX = LIST_W + 14
    local EW = W_ - EX
    local editor = CreateFrame("Frame", nil, page)
    editor:SetPoint("TOPLEFT", EX, 0)
    editor:SetSize(EW, Hh)
    local empty = K.Note(page, "No rings", EX + 20, -40, EW - 40)

    -- Header line: icon, name, Only this character, ... menu.
    local ringIcon = K.RoundIcon(editor, 36)
    ringIcon:SetPoint("TOPLEFT", 0, -2)
    local nameBox = K.EditBox(editor, 42, -8, 206, function(text)
        local ring = K.CurrentRing()
        text = strtrim(text or "")
        if ring and text ~= "" and text ~= ring.name then ring.name = text; H.Changed("name") end
        K.Refresh()
    end)
    nameBox:SetFontObject("GameFontHighlightLarge")
    function nameBox:Reset() local ring = K.CurrentRing(); self:SetText(ring and ring.name or "") end
    Tip(nameBox, "Name", "Enter: keep · Esc: undo")
    local mine = K.Check(editor, "Only this character", 262, -6,
        function() local r = K.CurrentRing(); return r and r.owner ~= nil end,
        function(on)
            local r = K.CurrentRing()
            if r then H.SetRingOwner(r, on and H.CharacterKey() or nil); H.Changed("owner") end
        end, 140)
    Tip(mine, "Only this character", "Others can still copy it")
    local more = K.Button(editor, "...", EW - 36, -6, 36, nil, 24)
    more:SetScript("OnClick", function(self)
        local ring = K.CurrentRing()
        if not ring then return end
        K.OpenPopup(self, {
            { title = ring.name },
            { text = "Duplicate", func = function() K.CopyCurrent(ring.owner, "here") end },
            { text = "Make macro", func = K.MakeRingMacro },
            { note = "For gamepad bars" },
            { divider = true },
            { text = "Delete ring", items = {
                { title = "Delete " .. ring.name .. "?" },
                { text = "Delete", func = K.DeleteCurrent },
                { note = "Can't be undone" },
            } },
        })
    end)
    Tip(more, "More")
    local rule = editor:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", 0, -40); rule:SetSize(EW, 1)
    rule:SetColorTexture(0.68, 0.50, 0.26, 0.25)

    -- Keys and style on one line; what they clash with on the line under it.
    K.Text(editor, "Key", 0, -53, "GameFontNormal")
    local keyButton = K.KeyCapture(editor, 32, -48, 120, "key")
    Tip(keyButton, "Key", "Backspace: clear")
    K.Text(editor, "Gamepad", 166, -53, "GameFontNormal")
    local padButton = K.KeyCapture(editor, 232, -48, 110, "padKey")
    Tip(padButton, "Gamepad button", "Backspace: clear. Hold one, press another: layer")
    K.Text(editor, "Style", 356, -53, "GameFontNormal")
    local styleButton = K.Button(editor, "Default", 394, -48, EW - 394, K.StyleMenu, 24)
    Tip(styleButton, "Style", "Default follows the Styles tab")
    local keyNote = K.Note(editor, "", 0, -78, EW)
    keyNote:SetWordWrap(false)
    local keyNoteHit = CreateFrame("Frame", nil, editor)
    keyNoteHit:SetPoint("TOPLEFT", 0, -76); keyNoteHit:SetSize(EW, 16)
    keyNoteHit:EnableMouse(true)
    Tip(keyNoteHit, "Keys", function() return keyNote:GetText() end)

    -- The ring, bigger than in layout A, with its notes under it.
    local BODY_Y = 98
    local BODY_H = Hh - BODY_Y
    local CW = 290
    local canvas = K.RingCanvas(editor, 0, -BODY_Y, CW, BODY_H - 20, { notesBelow = true })
    local countNote = editor:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    countNote:SetPoint("TOPRIGHT", canvas.frame, "BOTTOMRIGHT", 0, -4)
    countNote:SetJustifyH("RIGHT")

    -- Inspector: the selected slice, or how to fill the ring.
    local IX = CW + 12
    local IW = EW - IX
    local SLICE_H = 172
    local sliceCard = K.Card(editor, nil, IX, -BODY_Y, IW, SLICE_H)
    local sel = CreateFrame("Frame", nil, sliceCard)
    sel:SetAllPoints()
    local sIcon = K.RoundIcon(sel, 36)
    sIcon:SetPoint("TOPLEFT", 10, -10)
    local sName = sel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sName:SetPoint("TOPLEFT", 54, -13)
    sName:SetWidth(IW - 64); sName:SetJustifyH("LEFT"); sName:SetWordWrap(false)
    local sKind = sel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sKind:SetPoint("TOPLEFT", 54, -31)
    local BW = IW - 20
    local back = K.Button(sel, "Earlier", 10, -56, (BW - 4) / 2, function() K.MoveSlice(-1) end)
    local fwd = K.Button(sel, "Later", 10 + (BW + 4) / 2, -56, (BW - 4) / 2, function() K.MoveSlice(1) end)
    Tip(back, "Earlier")
    Tip(fwd, "Later")
    local edit = K.Button(sel, "Edit macro", 10, -82, BW, function()
        local ring, i = K.CurrentRing(), select(2, K.Selected())
        local s = ring and i and ring.slices[i]
        if s and s.kind == "text" then K.OpenMacroEditor(s) end
    end)
    local remove = K.Button(sel, "Remove", 10, -108, BW, function() K.RemoveSlice(select(2, K.Selected())) end)
    local sNote = K.Note(sel, "", 10, -140, BW)
    local guide = CreateFrame("Frame", nil, sliceCard)
    guide:SetAllPoints()
    K.Text(guide, "Fill the ring", 10, -10, "GameFontNormal")
    local guideText = K.Note(guide,
        "|cffffd100+|r  Emotes, markers, lists, macros\n\n" ..
        "|cffffd100Drop|r  Spells, items, mounts, pets\n\n" ..
        "|cffffd100Drag|r  Move a slice", 10, -32, BW)
    guideText:SetSpacing(2)

    local ringCard = K.Card(editor, "This ring", IX, -(BODY_Y + SLICE_H + 8), IW, BODY_H - SLICE_H - 8)
    local hide = K.Check(ringCard, "Hide what you can't use", 8, -32,
        function() local r = K.CurrentRing(); return r and r.hideMissing end,
        function(on) local r = K.CurrentRing(); if r then r.hideMissing = on; H.Changed("hide") end end, IW - 44)
    Tip(hide, "Hide what you can't use", "Updates out of combat")
    local tips = K.Check(ringCard, "Show tooltips", 8, -56,
        function() local r = K.CurrentRing(); return r and r.tooltips end,
        function(on) local r = K.CurrentRing(); if r then r.tooltips = on or nil; H.Changed("tooltips") end end, IW - 44)
    Tip(tips, "Show tooltips")
    K.Text(ringCard, "Spacing", 14, -92, "GameFontHighlight")
    local spacing = StepGroup(ringCard, IW - 114, -88, 52, function(delta)
        local r = K.CurrentRing()
        if not r then return end
        local v = math.floor(((tonumber(r.spread) or 1) + delta * 0.1) * 10 + 0.5) / 10
        v = math.max(H.SPREAD_MIN, math.min(H.SPREAD_MAX, v))
        r.spread = v ~= 1 and v or nil
        H.Changed("spacing")
    end)
    Tip(spacing.group, "Spacing", "Icons keep their size")

    local foreign = K.ForeignBar(editor, EW)
    local macroPanel = K.MacroEditorPanel(editor, 0, -BODY_Y, EW, BODY_H)

    local function Refresh()
        list:Refresh()
        local ring = K.CurrentRing()
        editor:SetShown(ring ~= nil)
        empty:SetShown(ring == nil)
        foreign:Set(ring)
        if not ring then return end
        local _, i = K.Selected()
        if i and not ring.slices[i] then K.SelectSlice(nil); i = nil end
        ringIcon:SetTexture(H.RingIcon(ring))
        if not nameBox:HasFocus() then nameBox:SetText(ring.name) end
        mine:Update(); hide:Update(); tips:Update()
        local spread = tonumber(ring.spread) or 1
        spacing.value:SetText(math.floor(spread * 100 + 0.5) .. "%")
        spacing.minus:SetEnabled(spread > H.SPREAD_MIN + 0.001)
        spacing.plus:SetEnabled(spread < H.SPREAD_MAX - 0.001)
        local capturing = K.Capturing()
        if capturing ~= keyButton then keyButton:SetText(K.KeyText(ring.key)) end
        if capturing ~= padButton then padButton:SetText(K.KeyText(ring.padKey)) end
        keyNote:SetText(K.KeyNotes(ring))
        keyNoteHit:SetShown(keyNote:GetText() ~= "")
        styleButton:SetText(ring.style and H.RingSkins.list[ring.style] and (ring.style .. "  " .. H.RingSkins.list[ring.style].name) or "Default")
        canvas:Refresh(ring)

        local n = #ring.slices
        local live = H.live[ring.id]
        local count = n .. (n == 1 and " slice" or " slices")
        local full = live and #live >= H.MAX_SLICES and " (full)" or ""
        countNote:SetText((live and #live ~= n and (count .. ", " .. #live .. " showing now") or count) .. full)

        local s = i and ring.slices[i]
        sel:SetShown(s ~= nil)
        guide:SetShown(s == nil)
        if s then
            local name, icon = H.SliceInfo(s)
            sIcon:SetTexture(icon)
            sName:SetText(name)
            sKind:SetText(H.KindLabel(s))
            back:SetEnabled(i > 1)
            fwd:SetEnabled(i < n)
            edit:SetShown(s.kind == "text")
            remove:ClearAllPoints()
            remove:SetPoint("TOPLEFT", 10, s.kind == "text" and -108 or -82)
            sNote:ClearAllPoints()
            sNote:SetPoint("TOPLEFT", 10, s.kind == "text" and -138 or -112)
            sNote:SetText(K.SliceNote(s))
        end
    end
    return Refresh, macroPanel
end
