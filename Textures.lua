-- Texture manifest: every texture each ring style draws, for re-drawing art by hand.
-- /halo textures records where each one lives in the game files (file ID and the atlas
-- rectangle) into HaloDB.textureDump, so the images can be extracted and replaced.
--
-- Entry: { name, "atlas" | "file", what it is for, size Halo draws it at }

local _, H = ...

H.TEXTURES = {
    { "A-Flyout", {
        { "gamepad-flyout-circular-slot-normal", "atlas", "Slot ring behind each icon", "native" },
        { "gamepad-flyout-circular-slot-mask", "atlas", "Round icon mask", "native" },
        { "gamepad-flyout-circular-slot-over-border", "atlas", "Hover ring", "native" },
        { "gamepad-flyout-circular-slot-highlight", "atlas", "Active slice (current mount etc.)", "native" },
        { "gamepad-flyout-circular-base", "atlas", "Dark disc behind the ring", "native x radius/60" },
        { "gamepad-largecursor", "atlas", "Pointer arrow", "21x35" },
    } },
    { "B-ActionBar", {
        { "Interface\\Buttons\\UI-Quickslot2", "file", "Square button border", "66x66" },
        { "Interface\\Buttons\\ButtonHilight-Square", "file", "Hover square (drawn twice, +30%)", "36x36" },
        { "Interface\\Buttons\\CheckButtonHilight", "file", "Active slice", "36x36" },
        { "NPE_ArrowUp", "atlas", "Pointer arrow", "26 tall" },
    } },
    { "C-Minimap", {
        { "communities-ring-gold", "atlas", "Gold slot ring (and hover, additive)", "44x44 / 46x46" },
        { "communities-ring-blue", "atlas", "Active slice ring", "44x44" },
        { "SpecDial_Center_Shadow", "atlas", "Dark disc (edge feathered 4px)", "0.81 x (2r + 64) - 8" },
        { "common-mask-circle", "atlas", "Feather rings at the disc edge (tinted black)", "disc size" },
        { "Navigation-Tracked-Arrow", "atlas", "Pointer arrow", "30 tall" },
    } },
    { "D-Runes", {
        { "gamepad-flyout-circular-slot-normal", "atlas", "Slot ring (same as Flyout)", "native" },
        { "gamepad-flyout-circular-slot-mask", "atlas", "Round icon mask (same as Flyout)", "native" },
        { "ChallengeMode-RuneBG", "atlas", "Turning rune circle (additive, drawn 2-3x)", "2r + 110" },
        { "ChallengeMode-Runes-CircleGlow", "atlas", "Breathing glow (additive, x3 1px apart)", "2r + 60" },
        { "ChallengeMode-Runes-SmallCircleGlow", "atlas", "Hover glow", "54x54" },
        { "ChallengeMode-AffixRing-Sm", "atlas", "Colour gem ring on the Styles tab", "26x26" },
    } },
    { "E-Parchment", {
        { "QuestBG-Parchment", "atlas", "Paper disc (centre square, 6% margin)", "2r + 70" },
        { "Interface\\QuestFrame\\QuestBG", "file", "Paper fallback if the atlas is missing", "2r + 70" },
        { "GarrMission_PortraitRing", "atlas", "Gilded slot ring (and hover, additive gold)", "48 wide" },
        { "gamepad-largecursor-white", "atlas", "Pointer arrow (tinted brown)", "18x30" },
    } },
    { "Shared", {
        { "Interface\\CharacterFrame\\TempPortraitAlphaMask", "file", "Round mask / tinted discs (all styles)", "various" },
        { "Interface\\Buttons\\WHITE8X8", "file", "Square cooldown swipe (Action bar)", "icon" },
        { "common-icon-forwardarrow", "atlas", "Nested-ring badge on a slot", "14x14" },
        { "Interface\\ChatFrame\\ChatFrameExpandArrow", "file", "Nested-ring badge fallback", "14x14" },
        { "services-icon-warning", "atlas", "Editor: slice hidden right now", "14x14" },
        { "common-sidetab", "atlas", "Window side tab", "native" },
        { "common-sidetab-mask", "atlas", "Window side tab icon mask", "native" },
        { "common-sidetab-selected", "atlas", "Window side tab selected", "native" },
        { "common-sidetab-hover", "atlas", "Window side tab hover", "native" },
    } },
}

function H.DumpTextures()
    local out, found, missing = {}, 0, 0
    for _, group in ipairs(H.TEXTURES) do
        local list = {}
        for _, entry in ipairs(group[2]) do
            local name, kind, use, drawn = entry[1], entry[2], entry[3], entry[4]
            local row = { name = name, kind = kind, use = use, drawn = drawn }
            if kind == "atlas" then
                local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
                if info then
                    row.fileID = info.file
                    row.filename = info.filename
                    row.width, row.height = info.width, info.height
                    row.left, row.right = info.leftTexCoord, info.rightTexCoord
                    row.top, row.bottom = info.topTexCoord, info.bottomTexCoord
                    found = found + 1
                else
                    row.missing = true
                    missing = missing + 1
                end
            else
                row.fileID = GetFileIDFromPath and GetFileIDFromPath(name)
                if row.fileID then found = found + 1 else row.missing = true; missing = missing + 1 end
            end
            list[#list + 1] = row
        end
        out[group[1]] = list
    end
    H.db.textureDump = { build = select(4, GetBuildInfo()), styles = out }
    H.Print(("Recorded %d textures (%d not found). /reload to save them."):format(found, missing))
end
