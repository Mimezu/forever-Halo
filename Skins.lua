-- Ring styles. Every style uses art that ships with Forever (classic textures and
-- Blizzard atlases referenced by the 70009 UI), so nothing is drawn by the addon itself.
--
--   A  Flyout      Forever's gamepad flyout: dark disc, round slots, cursor arrow.
--   B  Action bar  Vanilla action buttons floating in a circle; all fade in together.
--   C  Minimap     Minimap-style buttons in gold rings around a dark disc; sweeps open.
--   D  Runes       A keystone rune circle that slowly turns, affix rings, glowing hover.
--   E  Parchment   A round parchment with gilded portrait rings; unfolds.
--
-- Ring.lua (the real ring) and Options.lua (the editor preview) both draw through here.

local _, H = ...

local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local S = { order = { "A", "B", "C", "D", "E" }, list = {} }
H.RingSkins = S

local function AtlasInfo(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
end

-- spec: { atlas | file, w, h, native (atlas size), scale (of native), blend, color, alpha, coords }
local function Tex(parent, layer, sub, spec)
    local t = parent:CreateTexture(nil, layer, nil, sub or 0)
    t:SetPoint("CENTER", spec.x or 0, spec.y or 0)
    local info = spec.atlas and AtlasInfo(spec.atlas)
    if spec.atlas and info then
        t:SetAtlas(spec.atlas)
        local k = spec.scale or 1
        t:SetSize(spec.w or info.width * k, spec.h or info.height * k)
    elseif spec.file then
        t:SetTexture(spec.file)
        t:SetSize(spec.w or 36, spec.h or 36)
        if spec.coords then t:SetTexCoord(unpack(spec.coords)) end
    elseif spec.fallback then
        return Tex(parent, layer, sub, spec.fallback)
    else
        t:SetSize(1, 1); t:SetAlpha(0)
        return t
    end
    if spec.blend then t:SetBlendMode(spec.blend) end
    if spec.color then t:SetVertexColor(unpack(spec.color)) end
    if spec.alpha then t:SetAlpha(spec.alpha) end
    return t
end
S.Tex = Tex

local function Ease(t) t = 1 - t; return 1 - t * t * t end
local function Clamp(v) return v < 0 and 0 or (v > 1 and 1 or v) end
local function Back(t) -- ease out with a small overshoot
    local c = 1.7
    t = t - 1
    return 1 + (c + 1) * t * t * t + c * t * t
end

-- Open animations: p goes 0 -> 1. Return radius factor, angle offset (radians),
-- ring alpha, and a per-slot function (i, n) -> alpha, scale.
local ANIM = {
    bloom = function(p)
        local e = Ease(p)
        return 0.72 + 0.28 * e, 0, e
    end,
    deal = function(p)
        return 1, 0, Clamp(p * 4), function(i, n)
            local q = Clamp((p - (i - 1) / n * 0.55) / 0.45)
            return q, 0.55 + 0.45 * Ease(q)
        end
    end,
    sweep = function(p)
        local e = Ease(p)
        return 0.8 + 0.2 * e, -(1 - e) * 0.9, e
    end,
    fade = function(p)
        local e = Ease(p)
        return 0.94 + 0.06 * e, 0, e
    end,
    unfold = function(p)
        return 0.45 + 0.55 * Back(p), 0, Ease(p)
    end,
}

-- Rune colour (style D): nil = the art's own blue; else r, g, b.
-- A tint on the blue art would multiply it dark (blue x red = black), so tinted runes are
-- desaturated first and then coloured, which keeps them bright.
function S.RuneColor()
    local mode = H.Option and H.Option("runeColor")
    if mode == "class" then
        local _, class = UnitClass("player")
        local c = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
            or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
        if c then return c.r, c.g, c.b end
    elseif mode == "custom" then
        local c = H.Option("runeCustom")
        if type(c) == "table" and c[1] then return c[1], c[2], c[3] end
    end
end

-- alpha here is the vertex alpha: the textures keep their own SetAlpha (glow pulse etc.).
-- Colour at full strength: scaled so its strongest channel is 1 (no white mix, which
-- washed colours out). Brightness lost to the greyscale step is made up by extra
-- additive layers that only show while a colour is chosen (see RuneBoost).
local function RichColor()
    local r, g, b = S.RuneColor()
    if not r then return nil end
    local m = math.max(r, g, b, 0.001)
    return r / m, g / m, b / m
end

local function RuneTint(texture, alpha)
    local r, g, b = RichColor()
    if not r then
        texture:SetDesaturated(false)
        texture:SetVertexColor(1, 1, 1, alpha or 1)
        return
    end
    texture:SetDesaturated(true)
    texture:SetVertexColor(r, g, b, alpha or 1)
end

-- Smooth filtering for rotated/scaled art (Blizzard does this on its own rotating art):
-- pixel-grid snapping is what makes the turning runes look jagged.
local function Smooth(texture)
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    return texture
end
S.Smooth = Smooth

-- Extra additive layer shown only with Class/Custom colours.
local function RuneBoost(texture)
    texture.haloWhen = function() return S.RuneColor() ~= nil end
    return texture
end
S.RuneTint = RuneTint

-- Styles --------------------------------------------------------------------------------------
S.list.A = {
    id = "A", name = "Flyout", desc = "Forever's gamepad flyout. Dark disc, round slots, cursor arrow.",
    icon = 36, round = true, mask = "gamepad-flyout-circular-slot-mask", slot = 44,
    labelNudge = -3,   -- slice name 3px higher (player's request)
    centerText = { font = "GameFontHighlight", color = { 1, 1, 1 }, shadow = { 0, 0, 0, 1 }, offset = { 1, -1 } },
    anim = "bloom", openTime = 0.12,
    keyPoint = "TOPLEFT",
    pointer = { atlas = "gamepad-largecursor", w = 21, h = 35, rot = math.pi / 2, dist = 0.63 },
    buildSlot = function(k)
        return {
            normal = Tex(k.slot, "BACKGROUND", 0, { atlas = "gamepad-flyout-circular-slot-normal",
                fallback = { file = ROUND_MASK, w = 44, h = 44, color = { 0.08, 0.06, 0.04, 0.85 } } }),
            over = Tex(k.top, "ARTWORK", 0, { atlas = "gamepad-flyout-circular-slot-over-border",
                fallback = { file = ROUND_MASK, w = 40, h = 40, blend = "ADD", color = { 1, 0.8, 0.3, 0.35 } } }),
            active = Tex(k.top, "OVERLAY", 0, { atlas = "gamepad-flyout-circular-slot-highlight",
                fallback = { file = ROUND_MASK, w = 40, h = 40, blend = "ADD", color = { 0.4, 0.8, 1, 0.3 } } }),
        }
    end,
    buildRing = function(parent)
        local info = AtlasInfo("gamepad-flyout-circular-base")
        local base = Tex(parent, "BACKGROUND", -5, { atlas = "gamepad-flyout-circular-base" })
        return {
            textures = { base },
            Layout = function(_, r)
                if info then base:SetSize(info.width * r / 60, info.height * r / 60) end
            end,
            Extent = function(_, r) return info and info.width * r / 60 or 0 end,
        }
    end,
}

S.list.B = {
    id = "B", name = "Action bar", desc = "Vanilla action buttons floating in a circle. All fade in together.",
    icon = 36, round = false, slot = 44,
    anim = "fade", openTime = 0.14,
    keyPoint = "TOPRIGHT", keyFont = "NumberFontNormalSmallGray",
    countOffset = { 0, -1 },   -- count inside the square frame (default is 3, -2)
    -- No backdrop: gold with a dark outline so it reads over any scenery.
    centerText = { font = "GameFontNormal", color = { 1, 0.82, 0 }, shadow = { 0, 0, 0, 1 }, offset = { 1, -1 },
        outline = "OUTLINE" },
    hoverScale = 1.08,
    pointer = { atlas = "NPE_ArrowUp", height = 26, rot = 0, dist = 0.5 },
    buildSlot = function(k)
        return {
            -- Classic ActionButtonTemplate: UI-Quickslot2 is 66x66 around a 36px icon.
            normal = Tex(k.top, "BACKGROUND", 0, { file = "Interface\\Buttons\\UI-Quickslot2", w = 66, h = 66, y = -1 }),
            over = (function()
                -- Two additive layers: the classic highlight plus a 30% copy = 30% brighter.
                local f = CreateFrame("Frame", nil, k.top)
                f:SetAllPoints(k.top)
                Tex(f, "ARTWORK", 0, { file = "Interface\\Buttons\\ButtonHilight-Square", w = 36, h = 36, blend = "ADD" })
                Tex(f, "ARTWORK", 1, { file = "Interface\\Buttons\\ButtonHilight-Square", w = 36, h = 36, blend = "ADD", alpha = 0.3 })
                return f
            end)(),
            active = Tex(k.top, "OVERLAY", 0, { file = "Interface\\Buttons\\CheckButtonHilight", w = 36, h = 36, blend = "ADD" }),
        }
    end,
}

S.list.C = {
    id = "C", name = "Minimap", desc = "Minimap buttons in gold rings on a soft, blurred dark disc. Sweeps open like a compass.",
    icon = 34, round = true, slot = 46,
    labelNudge = 6,    -- slice name just under the enlarged pointed icon
    centerText = { font = "GameFontNormal", color = { 1, 0.82, 0 }, shadow = { 0, 0, 0, 0.9 }, offset = { 1, -1 } },
    anim = "sweep", openTime = 0.16,
    keyPoint = "TOPLEFT",
    pointer = { atlas = "Navigation-Tracked-Arrow", height = 30, rot = 0, dist = 0.5 },
    -- Sharp art only: communities-ring-gold ships up to 78px (Blizzard draws a 38px icon in
    -- a 48px ring), and the discs are the smooth round portrait mask, tinted.
    buildSlot = function(k)
        local ring = { atlas = "communities-ring-gold", w = 44, h = 44,
            fallback = { atlas = "ChallengeMode-AffixRing-Sm", w = 42, h = 42 } }
        return {
            back = Tex(k.slot, "BACKGROUND", 0, { file = ROUND_MASK, w = 36, h = 36, color = { 0.03, 0.03, 0.03, 0.95 } }),
            normal = Tex(k.top, "ARTWORK", 0, ring),
            over = Tex(k.top, "ARTWORK", 1, { atlas = "communities-ring-gold", w = 46, h = 46, blend = "ADD",
                fallback = { file = ROUND_MASK, w = 44, h = 44, blend = "ADD", color = { 1, 0.8, 0.3, 0.35 } } }),
            active = Tex(k.top, "OVERLAY", 0, { atlas = "communities-ring-blue", w = 44, h = 44,
                fallback = { file = ROUND_MASK, w = 40, h = 40, blend = "ADD", color = { 0.4, 0.8, 1, 0.3 } } }),
        }
    end,
    buildRing = function(parent)
        -- The first-version composition (the player confirmed this size in 0.3.4): a disc of
        -- 0.81 * (2r + 64) from Blizzard's smooth SpecDial shadow. Only its last 4 pixels
        -- are feathered: the shadow ends 4px early, and four faint rings 1px apart ramp
        -- the edge down. Centre ~0.63 dark (10% lighter than 0.3.4's ~0.7).
        local FEATHER, STEPS, EACH = 4, 4, 0.11
        local core = Tex(parent, "BACKGROUND", -7, { atlas = "SpecDial_Center_Shadow", alpha = 0.41,
            fallback = { file = ROUND_MASK, color = { 0, 0, 0, 0.4 } } })
        local rings = {}
        for i = 1, STEPS do
            rings[i] = Tex(parent, "BACKGROUND", -6, { atlas = "common-mask-circle", color = { 0, 0, 0, EACH },
                fallback = { file = ROUND_MASK, color = { 0, 0, 0, EACH } } })
        end
        local textures = { core }
        for _, t in ipairs(rings) do textures[#textures + 1] = t end
        local function Radius(r) return (2 * r + 64) * 0.81 / 2 end
        return {
            textures = textures,
            Layout = function(_, r)
                local R = Radius(r)
                core:SetSize(2 * (R - FEATHER), 2 * (R - FEATHER))
                for i, t in ipairs(rings) do
                    local rad = R - FEATHER + i * (FEATHER / STEPS)   -- R-3, R-2, R-1, R
                    t:SetSize(2 * rad, 2 * rad)
                end
            end,
            Extent = function(_, r) return 2 * Radius(r) end,
        }
    end,
}

S.list.D = {
    id = "D", name = "Runes", desc = "A keystone rune circle that slowly turns. Flyout slots, glowing hover.",
    icon = 36, round = true, mask = "gamepad-flyout-circular-slot-mask", slot = 44,
    slotRadius = 0.85,   -- icons sit a little inside the rune circle (the circle keeps its size)
    -- Pale rune-coloured text (blue, or the chosen colour lifted toward white).
    centerText = { font = "GameFontHighlight", color = function()
            local r, g, b = S.RuneColor()
            if not r then return 0.82, 0.95, 1 end
            return r + (1 - r) * 0.55, g + (1 - g) * 0.55, b + (1 - b) * 0.55
        end, shadow = { 0, 0, 0, 1 }, offset = { 1, -1 } },
    -- Slice name just under the bottom icon (not under the whole rune circle).
    labelBelow = function(skin, r) return r * skin.slotRadius + skin.slot / 2 * (skin.hoverScale or 1.12) + 8 end,
    anim = "fade", openTime = 0.2,
    keyPoint = "TOPLEFT",
    hoverScale = 1.1,
    buildSlot = function(k)
        return {
            back = Tex(k.slot, "BACKGROUND", 0, { file = ROUND_MASK, w = 36, h = 36, color = { 0, 0, 0, 0.8 } }),
            -- The slot rings of the original ring (style A): Flyout's slot art at its native
            -- size behind a 36px icon with Flyout's mask, exactly as A draws it.
            normal = Tex(k.slot, "BACKGROUND", 1, { atlas = "gamepad-flyout-circular-slot-normal",
                fallback = { atlas = "ChallengeMode-AffixRing-Sm", w = 42, h = 42 } }),
            -- Hover: the rune glow kept tight to the affix ring and dimmed (84px was too loud).
            over = Tex(k.slot, "BACKGROUND", -1, { atlas = "ChallengeMode-Runes-SmallCircleGlow", w = 54, h = 54,
                blend = "ADD", alpha = 0.45 }),
            active = Tex(k.top, "OVERLAY", 0, { file = ROUND_MASK, w = 36, h = 36, blend = "ADD", color = { 0.3, 0.7, 1, 0.35 } }),
        }
    end,
    refreshSlot = function(art)
        Smooth(art.over)
        RuneTint(art.over, 1)
        local r, g, b = S.RuneColor()
        if r then art.active:SetVertexColor(r, g, b, 0.35) else art.active:SetVertexColor(0.3, 0.7, 1, 0.35) end
    end,
    buildRing = function(parent)
        -- Additive only: the runes add light and never darken what is behind them (their
        -- art has dark areas that shaded the world in normal blending). A second additive
        -- copy makes them brighter. Both turn together.
        local runes = Tex(parent, "BACKGROUND", -6, { atlas = "ChallengeMode-RuneBG", blend = "ADD", alpha = 1 })
        local runes2 = Tex(parent, "BACKGROUND", -6, { atlas = "ChallengeMode-RuneBG", blend = "ADD", alpha = 0.55 })
        -- The pulsing glow: ChallengeMode-Runes-CircleGlow. Its soft bloom and crisp inner
        -- cut-off (glow only outside the ring) are the look the player wants. The art is
        -- stretched ~4x, so the cut-off steps; three copies only 1px apart (a third of the
        -- brightness each) blend the steps by a pixel without blurring the edge inward.
        -- (3px apart was too soft; a single copy shows the steps.)
        local GLOW, SPREAD = "ChallengeMode-Runes-CircleGlow", { -1, 0, 1 }
        local glows, boosts = {}, {}
        local N = #SPREAD
        for i = 1, N do
            glows[i] = Tex(parent, "BACKGROUND", -5, { atlas = GLOW, blend = "ADD", alpha = 0.33 / N })
            -- Colour boost (Class/Custom only): greyscale art is ~60% as bright as the blue.
            boosts[i] = RuneBoost(Tex(parent, "BACKGROUND", -5, { atlas = GLOW, blend = "ADD", alpha = 0.33 / N }))
        end
        local runes3 = RuneBoost(Tex(parent, "BACKGROUND", -6, { atlas = "ChallengeMode-RuneBG", blend = "ADD", alpha = 0.8 }))
        local all = { runes, runes2, runes3 }
        for i = 1, N do all[#all + 1] = glows[i]; all[#all + 1] = boosts[i] end
        for _, tex in ipairs(all) do Smooth(tex) end
        local t = 0
        return {
            textures = all,
            Layout = function(_, r)
                for _, tex in ipairs({ runes, runes2, runes3 }) do
                    tex:SetSize(2 * r + 110, 2 * r + 110)
                    RuneTint(tex, 1)
                end
                for i = 1, N do
                    local d = 2 * r + 60 + 2 * SPREAD[i]
                    for _, tex in ipairs({ glows[i], boosts[i] }) do
                        tex:SetSize(d, d)
                        RuneTint(tex, 1)
                    end
                end
            end,
            Extent = function(_, r) return 2 * r + 110 end,
            Update = function(_, elapsed)
                t = t + elapsed
                local turn = -t * 2 * math.pi / 90          -- one turn every 90 seconds
                runes:SetRotation(turn); runes2:SetRotation(turn); runes3:SetRotation(turn)
                local breath = (0.29 + 0.16 * math.sin(t * 1.6)) / N  -- breathing
                for i = 1, N do glows[i]:SetAlpha(breath); boosts[i]:SetAlpha(breath) end
            end,
        }
    end,
}

-- Gilded portrait ring at 48px wide, keeping the atlas's own aspect. Its circle sits
-- 5px (native) above the middle of the atlas: Blizzard's follower portrait is anchored
-- to the ring's CENTER with y = 5. So the ring is drawn 5px (scaled) lower, which puts
-- its circle exactly around our centred icon. The hover copies use this same spec.
local function PortraitRingSpec()
    local info = AtlasInfo("GarrMission_PortraitRing")
    if info and info.width > 0 then
        local k = 48 / info.width
        return { atlas = "GarrMission_PortraitRing", scale = k, y = -5 * k }
    end
    return { atlas = "ChallengeMode-AffixRing-Sm", w = 44, h = 44 }
end

S.list.E = {
    id = "E", name = "Parchment", desc = "A round parchment with gilded portrait rings. Unfolds when it opens.",
    -- Icon flush in the ring: Blizzard fits a 44px portrait in this ring at native size,
    -- ~40px at our 48px ring. zoom trims the icon's baked square bevel off the edge.
    icon = 40, zoom = 0.08, round = true, slot = 48,
    anim = "unfold", openTime = 0.2,
    keyPoint = "TOPLEFT",
    labelFont = "GameFontNormal",
    -- Same as Action bar (player's choice): gold with a dark outline and shadow, readable on the paper.
    centerText = { font = "GameFontNormal", color = { 1, 0.82, 0 }, shadow = { 0, 0, 0, 1 }, offset = { 1, -1 },
        outline = "OUTLINE" },
    pointer = { atlas = "gamepad-largecursor-white", w = 18, h = 30, rot = math.pi / 2, dist = 0.55,
        color = { 0.35, 0.22, 0.1, 0.95 } },
    buildSlot = function(k)
        return {
            back = Tex(k.slot, "BACKGROUND", 0, { file = ROUND_MASK, w = 41, h = 41, color = { 0.1, 0.06, 0.03, 1 } }),
            -- The gilded ring, at its native aspect, centred like the icon.
            normal = Tex(k.top, "ARTWORK", 0, PortraitRingSpec()),
            -- Hover: the ring itself lights up. Two additive gold copies of the exact same
            -- texture, size and position, so the highlight can never sit off-centre.
            over = (function()
                local f = CreateFrame("Frame", nil, k.top)
                f:SetAllPoints(k.top)
                local spec = PortraitRingSpec()
                spec.blend, spec.color = "ADD", { 1, 0.85, 0.45, 1 }
                Tex(f, "OVERLAY", 0, spec)
                spec.color = { 1, 0.75, 0.3, 0.6 }
                Tex(f, "OVERLAY", 1, spec)
                return f
            end)(),
            active = Tex(k.top, "OVERLAY", 0, { file = ROUND_MASK, w = 38, h = 38, blend = "ADD",
                color = { 0.45, 0.75, 1, 0.3 } }),
        }
    end,
    buildRing = function(parent)
        -- Only the inner part of the quest parchment, so no border or band shows in the circle.
        local paper = Tex(parent, "BACKGROUND", -6, { atlas = "QuestBG-Parchment", w = 1, h = 1,
            fallback = { file = "Interface\\QuestFrame\\QuestBG", coords = { 0.1, 0.48, 0.12, 0.5 } } })
        local info = AtlasInfo("QuestBG-Parchment")
        if info then
            -- Trim a thin margin (the bands sit at the very edge), then take the largest
            -- centred square, so the paper keeps its own scale instead of being stretched.
            local MARGIN = 0.06
            local w, h = info.width * (1 - 2 * MARGIN), info.height * (1 - 2 * MARGIN)
            local side = math.min(w, h)
            local fx, fy = side / info.width, side / info.height        -- kept fraction per axis
            local du, dv = info.rightTexCoord - info.leftTexCoord, info.bottomTexCoord - info.topTexCoord
            local cu, cv = info.leftTexCoord + du / 2, info.topTexCoord + dv / 2
            paper:SetTexCoord(cu - du * fx / 2, cu + du * fx / 2, cv - dv * fy / 2, cv + dv * fy / 2)
        end
        local mask = parent:CreateMaskTexture()
        mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(paper)
        paper:AddMaskTexture(mask)
        local edge = Tex(parent, "BACKGROUND", -7, { file = ROUND_MASK, color = { 0.22, 0.14, 0.06, 0.95 } })
        local shade = Tex(parent, "BACKGROUND", -5, { file = ROUND_MASK, color = { 0.3, 0.2, 0.1, 0.18 } })
        return {
            textures = { paper, edge, shade },
            Layout = function(_, r)
                paper:SetSize(2 * r + 70, 2 * r + 70)
                edge:SetSize(2 * r + 78, 2 * r + 78)
                shade:SetSize(2 * r - 20, 2 * r - 20)
            end,
            Extent = function(_, r) return 2 * r + 78 end,
        }
    end,
}

-- Resolution ------------------------------------------------------------------------------------

function S.Get(id)
    return S.list[id] or S.list.A
end

-- The style a ring uses: its own choice, else the Options default.
function S.ForRing(ring)
    local id = ring and ring.style
    if not S.list[id] then id = H.Option and H.Option("style") end
    return S.Get(id)
end

-- Where the slots sit for a ring radius r (the ring art always uses r itself).
function S.SlotRadius(skin, r)
    return r * (skin and skin.slotRadius or 1)
end

function S.Anim(skin, p)
    return (ANIM[skin.anim] or ANIM.bloom)(p)
end

-- Slot kit: the parts every style shares, built once per slot frame.
function S.BuildSlotKit(slot)
    slot.icon = slot:CreateTexture(nil, "BORDER")
    slot.icon:SetPoint("CENTER")
    slot.mask = slot:CreateMaskTexture()
    slot.mask:SetPoint("CENTER")
    slot.cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot.cooldown:SetAllPoints(slot.icon)
    slot.cooldown:SetDrawEdge(false)
    slot.cooldown:SetHideCountdownNumbers(true)
    slot.top = CreateFrame("Frame", nil, slot)
    slot.top:SetAllPoints()
    slot.top:SetFrameLevel(slot.cooldown:GetFrameLevel() + 2)
    slot.art = {}
    slot.masked = false
end

local function SetShownAll(art, shown)
    for key, t in pairs(art) do
        if key ~= "over" and key ~= "active" then t:SetShown(shown) end
        if not shown and (key == "over" or key == "active") then t:Hide() end
    end
end

-- Show one style's art on a slot and fit the icon to it.
function S.ApplySlot(slot, skin)
    if slot.skinID == skin.id then
        if skin.refreshSlot then skin.refreshSlot(slot.art[skin.id]) end
        return
    end
    if slot.skinID and slot.art[slot.skinID] then SetShownAll(slot.art[slot.skinID], false) end
    if not slot.art[skin.id] then
        slot.art[skin.id] = skin.buildSlot({ slot = slot, top = slot.top })
    end
    local art = slot.art[skin.id]
    SetShownAll(art, true)
    if skin.refreshSlot then skin.refreshSlot(art) end
    slot.over, slot.active = art.over, art.active
    slot.over:Hide(); slot.active:Hide()
    slot.skinID = skin.id
    slot:SetSize(skin.slot, skin.slot)
    slot.icon:SetSize(skin.icon, skin.icon)
    if skin.round then
        if skin.mask and AtlasInfo(skin.mask) then
            -- Native size, as the first version did: the mask art has padding, so shrinking
            -- it to the icon size made the icon look smaller inside the Flyout ring.
            slot.mask:SetAtlas(skin.mask, true)
        else
            slot.mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            slot.mask:SetSize(skin.icon, skin.icon)
        end
        if not slot.masked then slot.icon:AddMaskTexture(slot.mask); slot.masked = true end
        local z = skin.zoom or 0
        slot.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        slot.cooldown:SetSwipeTexture(ROUND_MASK)
        if slot.cooldown.SetUseCircularEdge then slot.cooldown:SetUseCircularEdge(true) end
    else
        if slot.masked then slot.icon:RemoveMaskTexture(slot.mask); slot.masked = false end
        slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        slot.cooldown:SetSwipeTexture(WHITE)
        slot.cooldown:SetSwipeColor(0, 0, 0, 0.75)
        if slot.cooldown.SetUseCircularEdge then slot.cooldown:SetUseCircularEdge(false) end
    end
end

-- Ring art (backdrop) for one style, cached per parent frame.
local ringArt, ringArtShown = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
function S.RingArt(parent, skin)
    ringArt[parent] = ringArt[parent] or {}
    local cache = ringArt[parent]
    local shown = ringArtShown[parent]
    if shown and shown ~= skin.id and cache[shown] then
        for _, t in ipairs(cache[shown].textures) do t:Hide() end
    end
    ringArtShown[parent] = skin.id
    if not skin.buildRing then return nil end
    if not cache[skin.id] then cache[skin.id] = skin.buildRing(parent) end
    return cache[skin.id]
end

-- Previews (Rings editor, Styles tab): the glow as the real ring shows it mid-breath.
-- (The editor does not animate; before this it froze on the stacked full-strength glow,
-- which looked harsh.)
function S.PreviewTone(art)
    if art and art.Update then art:Update(0) end
end

function S.ShowRingArt(art, shown)
    if not art then return end
    for _, t in ipairs(art.textures) do
        t:SetShown(shown and (not t.haloWhen or t.haloWhen()))
    end
end

-- Pointer art on a texture (sized from the atlas when only a height is given).
function S.ApplyPointer(texture, holder, skin)
    local p = skin.pointer
    if not p then holder:Hide(); return false end
    local info = AtlasInfo(p.atlas)
    if not info then holder:Hide(); return false end
    texture:SetAtlas(p.atlas)
    local w, h = p.w, p.h
    if not w then
        h = p.height or info.height
        w = h * info.width / info.height
    end
    holder:SetSize(w, h)
    if p.color then texture:SetVertexColor(unpack(p.color)) else texture:SetVertexColor(1, 1, 1, 1) end
    return true
end
