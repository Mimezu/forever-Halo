local _, H = ...
local S = {}
H.Skin = S

-- Legacy window art, shared with Petal and Forever Names (copied, not a dependency).

local function Texture(frame, atlas, layer, sub)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetAtlas(atlas, true)
    return t
end

-- The smooth rail uses a center texel of the native atlas. Repeating the
-- entire ornamented edge produces the seams found during Frame Gambit QA.
local function Plate(frame, atlas, borderOnly)
    local art = { pieces = {} }
    function art:Update()
        local info = C_Texture.GetAtlasInfo(atlas)
        if not info then return end
        local w,h = frame:GetSize()
        if w <= 0 or h <= 0 then return end
        if self.w == w and self.h == h then return end
        self.w,self.h = w,h
        local x,y = math.min(5,w/2,info.width/2),math.min(5,h/2,info.height/2)
        local iw,ih = info.width,info.height
        local sections = {
            {0,0,x,y,0,0,x,y}, {w-x,0,x,y,iw-x,0,x,y},
            {0,h-y,x,y,0,ih-y,x,y}, {w-x,h-y,x,y,iw-x,ih-y,x,y},
            {x,0,w-2*x,y,math.floor(iw/2),0,1,y},
            {x,h-y,w-2*x,y,math.floor(iw/2),ih-y,1,y},
            {0,y,x,h-2*y,0,math.floor(ih/2),x,1},
            {w-x,y,x,h-2*y,iw-x,math.floor(ih/2),x,1},
            {x,y,w-2*x,h-2*y,x,y,iw-2*x,ih-2*y},
        }
        for i,p in ipairs(sections) do
            if borderOnly and i==9 then break end
            local t = self.pieces[i] or frame:CreateTexture(nil,borderOnly and "BORDER" or "BACKGROUND",nil,borderOnly and 1 or -2)
            self.pieces[i] = t
            t:SetTexture(info.file or info.filename)
            local du,dv = info.rightTexCoord-info.leftTexCoord,info.bottomTexCoord-info.topTexCoord
            t:SetTexCoord(info.leftTexCoord+du*p[5]/iw,info.leftTexCoord+du*(p[5]+p[7])/iw,
                info.topTexCoord+dv*p[6]/ih,info.topTexCoord+dv*(p[6]+p[8])/ih)
            t:ClearAllPoints(); t:SetPoint("TOPLEFT",frame,"TOPLEFT",p[1],-p[2])
            t:SetSize(math.max(.01,p[3]),math.max(.01,p[4]))
            t:SetShown(self.visible ~= false)
        end
    end
    function art:SetShown(show)
        self.visible=show
        if show then self:Update() end
        for _,t in ipairs(self.pieces) do t:SetAlpha(1); t:SetShown(show) end
    end
    function art:Tint(color)
        for _,t in ipairs(self.pieces) do t:SetVertexColor(color[1],color[2],color[3],color[4] or 1) end
    end
    art:Update()
    return art
end

S.Plate = Plate

local function Leather(frame)
    local t = Texture(frame,"Legacy-Challenge-BG","BACKGROUND",-4)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT",3,-3); t:SetPoint("BOTTOMRIGHT",-3,3)
    local info = C_Texture.GetAtlasInfo("Legacy-Challenge-BG")
    if info then
        local du,dv=info.rightTexCoord-info.leftTexCoord,info.bottomTexCoord-info.topTexCoord
        t:SetTexture(info.file or info.filename)
        t:SetTexCoord(info.leftTexCoord+.05*du,info.rightTexCoord-.05*du,
            info.topTexCoord+.20*dv,info.bottomTexCoord-.02*dv)
    end
    return t
end

function S.Panel(frame)
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    local background=Leather(frame)
    local rim=Plate(frame,"common-button-list-collapseExpand",true)
    frame.legacyRim=rim
    frame:HookScript("OnSizeChanged",function() rim:Update() end)
    return background
end

function S.Button(button)
    -- Remove only template-owned textures; labels and preview colors survive.
    for _,key in ipairs({"Left","Middle","Right","LeftSeparator","RightSeparator"}) do
        if button[key] then button[key]:Hide() end
    end
    for _,key in ipairs({"GetNormalTexture","GetPushedTexture","GetDisabledTexture","GetHighlightTexture"}) do
        local texture=button[key] and button[key](button)
        if texture then texture:SetAlpha(0) end
    end
    local art=Plate(button,"common-button-list-collapseExpand")
    local hover=button:CreateTexture(nil,"HIGHLIGHT")
    hover:SetPoint("TOPLEFT",4,-4); hover:SetPoint("BOTTOMRIGHT",-4,4)
    hover:SetColorTexture(1,.7,.2,.12)
    local pressed=false
    local function Update()
        local shade=not button:IsEnabled() and .45 or pressed and .7 or 1
        art:Tint({shade,shade,shade,1})
    end
    button:HookScript("OnSizeChanged",function() art:Update() end)
    button:HookScript("OnMouseDown",function() pressed=true; Update() end)
    button:HookScript("OnMouseUp",function() pressed=false; Update() end)
    button:HookScript("OnHide",function() pressed=false; Update() end)
    button:HookScript("OnEnable",Update); button:HookScript("OnDisable",Update)
    return art
end

-- Legacy window chrome: leather, native border, centered title, close, drag.
function S.Frame(container,heading)
    local background=S.Panel(container)
    local chrome=S.WindowBorder(container)
    -- Atlas corners include transparent padding. Keep leather inside the
    -- visible metal, rather than filling the padding with a black rectangle.
    background:ClearAllPoints()
    background:SetPoint("TOPLEFT",12,-13); background:SetPoint("BOTTOMRIGHT",-6,6)
    -- Use DefaultPanelBaseTemplate's title area relative to the inset
    -- NineSlice frame. Its TopEdge texture includes padding and corner gaps.
    local border=container.legacyBorder
    local titleArea=CreateFrame("Frame",nil,chrome)
    titleArea:SetPoint("TOPLEFT",border,"TOPLEFT",30,-1)
    titleArea:SetPoint("TOPRIGHT",border,"TOPRIGHT",-24,-1)
    titleArea:SetHeight(20); titleArea:EnableMouse(false)
    heading:SetParent(titleArea)
    heading:ClearAllPoints(); heading:SetPoint("CENTER",titleArea,"CENTER",0,0)
    local close=CreateFrame("Button",nil,chrome,"UIPanelCloseButtonNoScripts")
    close:SetSize(28,28)
    -- Forever's UIPanelCloseButtonDefaultAnchorsMixin: 28 px at (0, 3) since build 70532 (24 px at (-2, 1) before).
    close:SetPoint("TOPRIGHT",border,"TOPRIGHT",0,3)
    close:SetScript("OnClick",function() container:Hide() end)
    container:SetMovable(true); container:SetClampedToScreen(true)
    local drag=CreateFrame("Frame",nil,chrome)
    drag:SetPoint("TOPLEFT",border,"TOPLEFT",0,-1)
    drag:SetPoint("TOPRIGHT",close,"TOPLEFT",-4,-2)
    drag:SetHeight(20); drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function() container:StartMoving() end)
    drag:SetScript("OnDragStop",function() container:StopMovingOrSizing() end)
    return chrome,close
end

function S.WindowBorder(frame)
    if frame.legacyRim then frame.legacyRim:SetShown(false) end
    local border=CreateFrame("Frame",nil,frame)
    -- Compensate the native layout's external offsets, preserving its artwork.
    border:SetPoint("TOPLEFT",8,-16); border:SetPoint("BOTTOMRIGHT",-4,3)
    border:SetFrameLevel(frame:GetFrameLevel()+1); border:EnableMouse(false)
    NineSliceUtil.ApplyLayoutByName(border,"ButtonFrameTemplateNoPortrait")
    frame.legacyBorder=border
    local chrome=CreateFrame("Frame",nil,frame)
    chrome:SetAllPoints(frame); chrome:SetFrameLevel(frame:GetFrameLevel()+2)
    chrome:EnableMouse(false)
    return chrome
end
