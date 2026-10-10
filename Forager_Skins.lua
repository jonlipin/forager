-- Forager's pieces in the window styles. Styles.lua does the choosing and the
-- drawing (Blizzard, Dark, or EllesmereUI's look); this file says what
-- Forager has to restyle.
--
-- That is the tracker icons and the frame of the standalone options window,
-- which opens when the game will not show Options > AddOns > Forager. The
-- options inside it are the same frame the AddOns page shows, so they keep
-- the game's look in both places, as EllesmereUI leaves page contents
-- alone. The minimap button is never touched.

local ADDON, ns = ...
local Styles = ns.Styles
local Try = Styles.Try
local FLAT = "Interface\\Buttons\\WHITE8X8"

local function S() return Styles.S end

-- A frame field, but only a real one (never a template's missing key).
local function Field(t, key)
    local v = type(t) == "table" and t[key] or nil
    if type(v) == "table" then return v end
end

-- Puts a button above everything else in its window, a style's border
-- frame included.
local function Raise(button, parent)
    if type(button) ~= "table" or not button.SetFrameLevel then return end
    local level = parent:GetFrameLevel() or 1
    for _, child in ipairs({ parent:GetChildren() }) do
        if child ~= button then level = math.max(level, child:GetFrameLevel() or 0) end
    end
    button:SetFrameLevel(level + 5)
end

-- The window is made the first time it is needed.
function ns.SkinWindow(win)
    if not S() or type(win) ~= "table" then return end
    Try("window", function()
        S().Shell(win)
        -- The window template's own chrome: portrait, metal frame, inset.
        local portrait = Field(win, "PortraitContainer")
        if portrait then S().FadeRegions(portrait) end
        local nine = Field(win, "NineSlice")
        if nine then S().FadeNineSlice(nine) end
        local inset = Field(win, "Inset")
        if inset then S().Inset(inset) end
    end)
    Try("window title", function()
        local bar = Field(win, "TitleContainer")
        local title = Field(bar, "TitleText") or Field(win, "TitleText")
        if not title then return end
        S().Font(title)
        -- The title made room for the portrait, which is gone; center it on
        -- the top bar instead.
        title:ClearAllPoints()
        title:SetPoint("CENTER", win, "TOP", 0, -12)
        if title.SetJustifyH then title:SetJustifyH("CENTER") end
        -- A border frame laid over the whole window would cover the title
        -- bar and the close button; they go back on top of it.
        if bar then Raise(bar, win) end
    end)
    Try("close button", function()
        local close = Field(win, "CloseButton") or Field(_G, "ForagerOptionsCloseButton") or Field(win, "fgClose")
        if not close then return end
        S().CloseButton(close)
        Raise(close, win)
    end)
end

---------------------------------------------------------------------------
-- Tracker icons in three looks, in any style:
--   bar     the action bar's rounded square, as the bar builds it
--   square  cropped square with a thin edge
--   circle  a true circle: the minimap tracking ring under Blizzard's look,
--           a thin dark edge under a drawn style
-- Automatic is the bar look with Blizzard's style and square with a drawn
-- one; Round is the circle; Square is square. Every look is kept on the icon
-- once drawn, so a change shows at once.
--
-- This client's rules: SetTexCoord takes left, right, top, bottom only, and
-- a masked texture refuses it outright, so the crop always comes before a
-- mask goes on and after the old one comes off.
---------------------------------------------------------------------------

local SWIPE_FILE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local CIRCLE_FILE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING_FILE = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BAR_ART = { "fgFrame", "fgPushed", "fgHighlight" }
local CROP = { 0.08, 0.92, 0.08, 0.92 }
-- The ring in MiniMap-TrackingBorder (64 x 64, measured): center at texel
-- 20.05, 18.92, gold from radius 12.67 to 15.69. Scaled so its outside meets
-- the icon's edge, with the picture filling the ring's inside.
local RING = { cx = 20.05, cy = 18.92, outer = 16, inner = 12.67 }

local function HasAtlas(atlas)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    return ok and info ~= nil
end

function ns.IconShape()
    local db = ns.DB and ns.DB()
    local chosen = db and db.iconShape
    if chosen == "round" then return S() and "circle-edge" or "circle-ring" end
    if chosen == "square" then return "square" end
    return S() and "square" or "bar"
end

local function Pieces(frame)
    local set = {}
    for _, region in ipairs({ frame:GetRegions() }) do set[region] = true end
    for _, child in ipairs({ frame:GetChildren() }) do set[child] = true end
    return set
end

-- The square look, drawn the first time it is wanted: the style's own
-- square icon call, or Dark's while Blizzard's look is in use. What it adds
-- (the edge, Forager's flat highlight) is kept to be shown and hidden.
local function SquareParts(button)
    local parts = rawget(button, "fgSquare")
    if parts then return parts end
    local icon = button.icon
    parts = { added = {} }
    local before = Pieces(button)
    -- Forager's own flat highlight, the one it uses without the bar art.
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
    local drawer = S() or Styles.Dark
    drawer.SquareIcon(icon, button)
    -- GetTexCoord gives all four corners (eight values).
    local left, top, _, _, _, _, right, bottom = icon:GetTexCoord()
    if type(left) == "number" and type(bottom) == "number" then
        parts.square = { left, right, top, bottom }
    else
        parts.square = CROP
    end
    for piece in pairs(Pieces(button)) do
        if not before[piece] then parts.added[#parts.added + 1] = piece end
    end
    button.fgSquare = parts
    return parts
end

-- A white disc of the circle texture, tinted, on `layer`.
local function Disc(button, layer, sub, r, g, b, a)
    local tex = button:CreateTexture(nil, layer, nil, sub)
    tex:SetTexture(CIRCLE_FILE)
    tex:SetVertexColor(r, g, b, a)
    tex:SetPoint("CENTER", button.icon, "CENTER")
    return tex
end

-- The circle look, drawn the first time it is wanted: a circle mask, the
-- minimap ring, a dark disc behind the picture for the thin edge, and round
-- highlight and press art.
local function CircleParts(button)
    local parts = rawget(button, "fgCircle")
    if parts then return parts end
    local icon, size = button.icon, ns.ICON_SIZE or 36
    parts = {}
    local mask = button:CreateMaskTexture()
    if HasAtlas("CircleMaskScalable") then
        mask:SetAtlas("CircleMaskScalable")
    else
        mask:SetTexture(CIRCLE_FILE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    mask:SetPoint("CENTER", icon, "CENTER")
    parts.mask = mask

    local scale = size / 2 / RING.outer
    local ring = button:CreateTexture(nil, "OVERLAY", nil, 1)
    ring:SetTexture(RING_FILE)
    ring:SetSize(64 * scale, 64 * scale)
    ring:SetPoint("TOPLEFT", icon, "CENTER", -RING.cx * scale, RING.cy * scale)
    parts.ring = ring
    -- The picture just reaches under the gold.
    parts.ringSize = math.floor(2 * RING.inner * scale + 1.5 + 0.5)

    parts.edge = Disc(button, "BACKGROUND", 1, 0, 0, 0, 1)
    parts.edge:SetSize(size + 2, size + 2)

    parts.hl = Disc(button, "HIGHLIGHT", 0, 1, 1, 1, 0.2)
    parts.press = Disc(button, "OVERLAY", 2, 0, 0, 0, 0.35)
    parts.press:SetAlpha(0)
    -- Press feedback for the circle only; the bar look has its own.
    button:HookScript("OnMouseDown", function(self)
        local shape = rawget(self, "fgShape")
        if shape == "circle-ring" or shape == "circle-edge" then parts.press:SetAlpha(1) end
    end)
    button:HookScript("OnMouseUp", function() parts.press:SetAlpha(0) end)
    parts.all = { ring, parts.edge, parts.hl, parts.press }
    button.fgCircle = parts
    return parts
end

local function SetSweep(cd, shape, icon, size)
    if not cd then return end
    cd:ClearAllPoints()
    local file
    if shape == "square" then
        cd:SetAllPoints(icon)
        file = FLAT
    elseif shape == "bar" then
        cd:SetPoint("TOPLEFT", 2, -2)
        cd:SetPoint("BOTTOMRIGHT", -2, 2)
        file = SWIPE_FILE
    else
        cd:SetPoint("CENTER", icon, "CENTER")
        cd:SetSize(size, size)
        file = CIRCLE_FILE
    end
    if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, file, 0, 0, 0, 0.75) end
    if cd.SetUseCircularEdge then pcall(cd.SetUseCircularEdge, cd, file == CIRCLE_FILE) end
end

-- Back to the art the bar built, from any look.
local function ToBar(button, from)
    if from == "bar" then return end
    local icon = button.icon
    if from == "square" then
        for _, piece in ipairs(rawget(button, "fgSquare").added) do piece:SetAlpha(0) end
    else
        local parts = rawget(button, "fgCircle")
        icon:RemoveMaskTexture(parts.mask)
        for _, piece in ipairs(parts.all) do piece:SetAlpha(0) end
    end
    -- Unmasked now, so the crop can go back before the bar's mask does.
    icon:SetTexCoord(unpack(rawget(button, "fgRound") or { 0, 1, 0, 1 }))
    local mask = Field(button, "fgMask")
    if mask then icon:AddMaskTexture(mask) end
    for _, key in ipairs(BAR_ART) do
        local art = Field(button, key)
        if art then art:SetAlpha(1) end
    end
end

-- From the bar look to `shape`. The proc glow stays in every look.
local function FromBar(button, shape)
    if shape == "bar" then return end
    local icon = button.icon
    local mask = Field(button, "fgMask")
    if mask then icon:RemoveMaskTexture(mask) end
    for _, key in ipairs(BAR_ART) do
        local art = Field(button, key)
        if art then art:SetAlpha(0) end
    end
    if shape == "square" then
        local parts = SquareParts(button)
        icon:SetTexCoord(unpack(parts.square))
        for _, piece in ipairs(parts.added) do piece:SetAlpha(1) end
    else
        local parts = CircleParts(button)
        local ringed = shape == "circle-ring"
        local size = ringed and parts.ringSize or (ns.ICON_SIZE or 36)
        icon:SetTexCoord(unpack(CROP)) -- before the circle mask
        parts.mask:SetSize(size, size)
        icon:AddMaskTexture(parts.mask)
        parts.ring:SetAlpha(ringed and 1 or 0)
        parts.edge:SetAlpha(ringed and 0 or 1)
        parts.hl:SetSize(size, size)
        parts.hl:SetAlpha(1)
        parts.press:SetSize(size, size)
        parts.press:SetAlpha(0)
    end
end

local function SetShape(button, shape)
    local now = rawget(button, "fgShape") or "bar" -- as the bar builds it
    if now == shape then return end
    ToBar(button, now)
    button.fgShape = "bar"
    FromBar(button, shape)
    local size = ns.ICON_SIZE or 36
    if shape == "circle-ring" then size = rawget(button, "fgCircle").ringSize end
    SetSweep(Field(button, "cd"), shape, button.icon, size)
    button.fgShape = shape
end

-- Each tracker icon as it is made, and all of them when the shape or the
-- style changes.
-- A failure also goes to the saved log, readable after a /reload.
local function TryShape(what, button, shape)
    if not Try(what, SetShape, button, shape) and ns.Log then
        ns.Log(what .. " " .. shape .. " failed: " .. tostring(ns.report["skin error: " .. what]))
    end
end

function ns.ShapeIcon(button)
    if type(button) ~= "table" then return end
    TryShape("tracker icon", button, ns.IconShape())
end

function ns.UpdateIconShapes()
    for _, button in ipairs(ns.trackButtons or {}) do ns.ShapeIcon(button) end
end

-- The pause button is squared by a drawn style and keeps its art under
-- Blizzard's, whatever the tracker icons' shape.
function ns.SkinPauseButton(button)
    if not S() or type(button) ~= "table" or rawget(button, "fgShape") then return end
    TryShape("pause button", button, "square")
end

Styles.Setup({
    addon = ADDON,
    title = "Forager",
    db = function() return ns.DB and ns.DB() end,
    report = ns.report,
    accent = { 0.5, 0.85, 0.42 }, -- the green of Forager's chat lines
    skin = function()
        if ns.window then ns.SkinWindow(ns.window) end
        ns.UpdateIconShapes()
        if ns.pauseButton then ns.SkinPauseButton(ns.pauseButton) end
    end,
})

