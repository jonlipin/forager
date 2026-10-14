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

local CIRCLE_FILE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING_FILE = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BAR_ART = { "fgFrame", "fgPushed", "fgHighlight" }
local CROP = { 0.08, 0.92, 0.08, 0.92 }
-- The ring in MiniMap-TrackingBorder (64 x 64, measured by fitting circles to
-- the gold's edges): center at texel 20.05, 18.92 (fit: 19.91, 18.92), gold
-- from radius 12.67 to 15.69. Scaled so its outside meets the icon's edge,
-- with the picture filling the ring's inside. Its drop shadow reaches about
-- 3 px further out at the lower right.
local RING = { cx = 20.05, cy = 18.92, outer = 16, inner = 12.67 }
-- Round glows on this client (measured the same way): where the ring's center
-- sits in the atlas (cx, cy as shares of its width and height) and the radius
-- of its bright band (peak, a share of the width). The first one present is
-- used; with neither, the action bar's shimmer stays.
local ROUND_GLOWS = {
    { atlas = "dragonflight-landingbutton-circleglow", cx = 0.5001, cy = 0.4898, peak = 0.413 },
    { atlas = "garrlanding-circleglow", cx = 0.5, cy = 0.5002, peak = 0.369 },
}
-- The glow's bright band sits this far outside the gold (or the dark edge), so
-- it clears most of the ring's drop shadow and reads as even all round.
local GLOW_GAP = 2

local function HasAtlas(atlas)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    return ok and info ~= nil
end

local function IsCircle(shape) return shape == "circle-ring" or shape == "circle-edge" end

---------------------------------------------------------------------------
-- Fades. Everything that marks the tracker that is on (the action bar's
-- shimmer or the round glow, and the glitter) fades out on the old tracker
-- while it fades in on the new one, over FADE seconds. A fade starts from
-- wherever the last one left off and takes time in proportion to the way
-- left, so a quick toggle turns round smoothly. One driver frame runs only
-- while something is fading.
---------------------------------------------------------------------------

local FADE = 0.4
ns.FADE = FADE
local fades = {}   -- [thing] = { from, to, t, dur, set, done }
local levels = {}  -- [thing] = the alpha last set
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self, elapsed)
    local finished = {}
    for thing, fade in pairs(fades) do
        fade.t = fade.t + elapsed
        local p = fade.dur > 0 and math.min(1, fade.t / fade.dur) or 1
        local alpha = fade.from + (fade.to - fade.from) * p
        levels[thing] = alpha
        fade.set(alpha)
        if p >= 1 then finished[#finished + 1] = thing end
    end
    for _, thing in ipairs(finished) do
        local fade = fades[thing]
        fades[thing] = nil
        if fade.done then fade.done() end
    end
    if next(fades) == nil then self:Hide() end
end)

-- Fades `thing` to `target`: full is its alpha when fully shown, set(alpha)
-- applies a step, done() runs once it gets there. instant skips the fade.
local function Fade(thing, target, full, set, done, instant)
    local from = levels[thing] or 0
    fades[thing] = nil
    if instant or math.abs(target - from) < 1e-6 then
        levels[thing] = target
        set(target)
        if done then done() end
        return
    end
    set(from)
    fades[thing] = { from = from, to = target, t = 0, dur = FADE * math.abs(target - from) / full, set = set, done = done }
    fader:Show()
end
function ns.FadeLevel(thing) return levels[thing] end
function ns.Fading(thing) return fades[thing] ~= nil end

local function Chosen()
    local db = ns.DB and ns.DB()
    return db and db.iconShape
end

function ns.IconShape()
    local chosen = Chosen()
    if chosen == "round" then return S() and "circle-edge" or "circle-ring" end
    if chosen == "square" then return "square" end
    return S() and "square" or "bar"
end

-- The pause button goes round with the trackers; otherwise it is squared by
-- a drawn style and keeps the bar art under Blizzard's, as before.
local function PauseShape()
    if Chosen() == "round" then return ns.IconShape() end
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

-- A circle mask on the icon's center.
local function CircleMask(button, size)
    local mask = button:CreateMaskTexture()
    if HasAtlas("CircleMaskScalable") then
        mask:SetAtlas("CircleMaskScalable")
    else
        mask:SetTexture(CIRCLE_FILE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    mask:SetPoint("CENTER", button.icon, "CENTER")
    if size then mask:SetSize(size, size) end
    return mask
end

-- A flat color seen through a circle mask. The alpha is the color's own and
-- the blend is plain, so a highlight lightens the picture instead of covering
-- it (a tinted circle texture came out as a solid white disc in game).
local function Disc(button, mask, size, layer, sub, r, g, b, a)
    local tex = button:CreateTexture(nil, layer, nil, sub)
    tex:SetColorTexture(r, g, b, a)
    tex:SetBlendMode("BLEND")
    tex:SetPoint("CENTER", button.icon, "CENTER")
    tex:SetSize(size, size)
    tex:AddMaskTexture(mask)
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
    -- Sized for each look in FromBar; the highlight and press art share it.
    parts.mask = CircleMask(button)

    local scale = size / 2 / RING.outer
    local ring = button:CreateTexture(nil, "OVERLAY", nil, 1)
    ring:SetTexture(RING_FILE)
    ring:SetSize(64 * scale, 64 * scale)
    ring:SetPoint("TOPLEFT", icon, "CENTER", -RING.cx * scale, RING.cy * scale)
    parts.ring = ring
    -- The picture just reaches under the gold.
    parts.ringSize = math.floor(2 * RING.inner * scale + 1.5 + 0.5)

    -- One pixel of black round the picture, from a disc just larger than it.
    parts.edgeMask = CircleMask(button, size + 2)
    parts.edge = Disc(button, parts.edgeMask, size + 2, "BACKGROUND", 1, 0, 0, 0, 1)

    parts.hl = Disc(button, parts.mask, size, "HIGHLIGHT", 0, 1, 1, 1, 0.15)
    parts.press = Disc(button, parts.mask, size, "OVERLAY", 2, 0, 0, 0, 0.3)
    parts.press:SetAlpha(0)
    -- Press feedback for the circle only; the bar look has its own.
    button:HookScript("OnMouseDown", function(self)
        local shape = rawget(self, "fgShape")
        if shape == "circle-ring" or shape == "circle-edge" then parts.press:SetAlpha(1) end
    end)
    button:HookScript("OnMouseUp", function() parts.press:SetAlpha(0) end)
    parts.all = { ring, parts.edge, parts.hl, parts.press }

    -- A round glow for the tracker that is on, pulsing, in place of the action
    -- bar's square shimmer. Shown and hidden with the shimmer (GlowChanged),
    -- so it never needs an alpha of its own: the pulse owns the alpha.
    if Field(button, "glow") then
        for _, glow in ipairs(ROUND_GLOWS) do
            if HasAtlas(glow.atlas) then
                local tex = button:CreateTexture(nil, "OVERLAY", nil, 7)
                tex:SetAtlas(glow.atlas)
                tex:SetBlendMode("ADD")
                tex:SetPoint("CENTER", icon, "CENTER")
                tex:Hide()
                local anim = tex:CreateAnimationGroup()
                local pulse = anim:CreateAnimation("Alpha")
                pulse:SetFromAlpha(0.35)
                pulse:SetToAlpha(1)
                pulse:SetDuration(0.8)
                anim:SetLooping("BOUNCE")
                parts.glow, parts.glowAnim, parts.glowSpec = tex, anim, glow
                break
            end
        end
    end
    button.fgCircle = parts
    return parts
end

-- The sweep, per look. The square and action bar looks use the Cooldown's own
-- swipe (a plain color, from CooldownFrameTemplate), which fills the whole
-- frame whatever its size: on the icon exactly for the square, inside the bar
-- frame (fitted inside it in game) for the action bar look. The Cooldown Manager's swipe art
-- left the left side of the icon unswept on this client, though its frame was
-- right (seen with /forager debug icons). Round keeps its circle texture, a
-- standalone image. What was set is noted on the frame for /forager debug icons.
local SWEEP_ALPHA = 0.75

local function SetSweep(cd, shape, icon, size)
    if not cd then return end
    cd:ClearAllPoints()
    local file
    if shape == "square" then
        cd:SetAllPoints(icon)
    elseif shape == "bar" then
        -- 2 px in at the top and left, 3 at the right, 2.5 at the bottom, fitted in game.
        cd:SetPoint("TOPLEFT", 2, -2)
        cd:SetPoint("BOTTOMRIGHT", -3, 2.5)
    else
        cd:SetPoint("CENTER", icon, "CENTER")
        cd:SetSize(size, size)
        file = CIRCLE_FILE
    end
    if file then
        if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, file, 0, 0, 0, SWEEP_ALPHA) end
        cd.fgSweep = file
    else
        -- Back to the color swipe: no texture (the call takes nil), or an empty
        -- one where nil is refused.
        local cleared = cd.SetSwipeTexture and (pcall(cd.SetSwipeTexture, cd, nil, 0, 0, 0, SWEEP_ALPHA)
            or pcall(cd.SetSwipeTexture, cd, "", 0, 0, 0, SWEEP_ALPHA))
        if cd.SetSwipeColor then pcall(cd.SetSwipeColor, cd, 0, 0, 0, SWEEP_ALPHA) end
        cd.fgSweep = cleared and "color" or "color (texture not cleared)"
    end
    if cd.SetDrawSwipe then pcall(cd.SetDrawSwipe, cd, true) end
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
        parts.hl:SetAlpha(1)
        parts.press:SetAlpha(0)
        if parts.glow then
            -- Its bright band GLOW_GAP outside the gold ring, or the dark edge,
            -- with the ring in the art (not the art's middle) on the icon's center.
            local spec = parts.glowSpec
            local outside = ringed and (ns.ICON_SIZE or 36) / 2 or (ns.ICON_SIZE or 36) / 2 + 1
            local across = math.floor((outside + GLOW_GAP) / spec.peak + 0.5)
            parts.glow:SetSize(across, across)
            parts.glow:ClearAllPoints()
            parts.glow:SetPoint("CENTER", icon, "CENTER", (0.5 - spec.cx) * across, (spec.cy - 0.5) * across)
        end
    end
end

-- The tracker that is on glows: the action bar's shimmer, or the round glow
-- while the icon is a circle. Called when the tracker comes on or goes off
-- (each glow fades in or out over FADE), and at once when the look changes.
-- The fade is on the vertex alpha: the region alpha belongs to each glow's own
-- animation (the shimmer's flipbook, the round glow's pulse), which keeps
-- running while it fades in and stops once it has faded out.
function ns.GlowChanged(button, on, instant)
    local square = Field(button, "glow")
    if not square then return end
    local parts = rawget(button, "fgCircle")
    local roundGlow = parts and parts.glow
    local round = roundGlow and IsCircle(rawget(button, "fgShape")) or false
    local function Mark(tex, anim, wanted)
        local function Set(alpha) tex:SetVertexColor(1, 1, 1, alpha) end
        if wanted then
            tex:Show()
            if anim and not anim:IsPlaying() then anim:Play() end
            Fade(tex, 1, 1, Set, nil, instant)
        else
            Fade(tex, 0, 1, Set, function()
                tex:Hide()
                if anim then anim:Stop() end
            end, instant)
        end
    end
    Mark(square, Field(button, "anim"), on and not round)
    if roundGlow then Mark(roundGlow, parts.glowAnim, on and round) end
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
    -- lit: the bar's own note that this tracker is on.
    if Field(button, "glow") then ns.GlowChanged(button, rawget(button, "lit") and true or false, true) end
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

---------------------------------------------------------------------------
-- Sparkles round the tracker that is on. Only that tracker sparkles, and
-- nothing runs while the icons are hidden, Forager is paused, or the option
-- is off (Forager.lua decides).
--
-- The effect is a real spell model, the way Cursor Beacon draws them: one
-- small ModelScene with a camera placed here, and one actor at its center
-- carrying a looping spell effect the player picks. Models draw per frame,
-- not per texture layer, so the nearest to "just behind the border" is a frame behind the
-- whole icon: the bar's own level, which the icons sit one above. The glitter
-- then shows round the ring, edge or frame. A client that will not show a
-- model gets drawn sparkles instead: gold stars that start on the border and
-- drift outward, in the texture layer just behind the border art.
---------------------------------------------------------------------------

-- The sparkle effects to pick from (the Sparkle effect button, or /forager
-- sparkles next). Spell models that loop (state, precast and aura models),
-- mostly from the vanilla era block most likely on this client; the last two
-- are newer and may be missing, in which case they are skipped. yards is each
-- effect's spread, which sets the camera so it reaches MODEL_REACH; alpha its
-- strength; pitch tips a ground effect up to face the camera. Only the first
-- spread was measured (from a screenshot); the rest are guesses to tune from
-- what the player sees.
local SPARK_MODELS = {
    { id = 166336, name = "spells/holy_precast_low_hand.m2", label = "Holy glitter", yards = 0.515, alpha = 0.75 },
    { id = 166060, name = "spells/faeriefire.m2", label = "Faerie fire", yards = 1, alpha = 0.6 },
    { id = 166062, name = "spells/faeriefire_noglow.m2", label = "Faerie fire specks", yards = 1, alpha = 0.75 },
    { id = 165589, name = "spells/arcanepower_state_chest.m2", label = "Arcane power", yards = 0.8, alpha = 0.7 },
    { id = 166338, name = "spells/holy_precast_uber_base.m2", label = "Holy glitter, ground", yards = 1.2, alpha = 0.7, pitch = math.pi / 2 },
    { id = 166322, name = "spells/holy_form_precast.m2", label = "Holy form", yards = 1, alpha = 0.7 },
    { id = 775512, name = "spells/stardust_trail_state.m2", label = "Stardust", yards = 0.8, alpha = 0.75 },
    { id = 426041, name = "spells/sparkler_white.m2", label = "Sparkler", yards = 0.5, alpha = 0.75 },
}
ns.SPARK_MODELS = SPARK_MODELS
-- How far out the glitter reaches, in pixels from the icon's center: just past
-- the gold ring (18) and the round glow (about 24). Ask for more or less here.
local MODEL_REACH = 31
local MODEL_SCENE = 104   -- the scene's size, wide enough that its edge never cuts the glitter
local MODEL_FOV = 0.6

-- The player's Sparkle size and Sparkle intensity, as shares (1 = 100%).
local function Looks()
    local db = ns.DB and ns.DB()
    return ((db and db.sparkleSize) or 100) / 100, ((db and db.sparkleIntensity) or 100) / 100
end

-- How far out the glitter reaches: MODEL_REACH at size 100%.
local function Reach() return MODEL_REACH * (Looks()) end
ns.SparkleReach = Reach

-- The scene grows with the reach, so its edge stays at least 12 px past it.
local function SceneSize() return math.max(MODEL_SCENE, math.ceil(2 * (Reach() + 12))) end

-- The camera distance that puts an effect's spread at the reach: the scene
-- shows tan(fov / 2) * distance yards from its center to its edge. Moving the
-- camera scales everything evenly; scaling the actor would leave the particles
-- their own size (Cursor Beacon's lesson).
local function CameraFor(entry)
    return (SceneSize() / 2) / (math.tan(MODEL_FOV / 2) * Reach() / entry.yards)
end

-- An effect's strength when fully shown: its own alpha times the intensity.
local function FullAlpha(entry)
    local _, strength = Looks()
    return entry.alpha * strength
end

-- Two scenes at most, so the glitter can fade out on the old tracker while
-- it fades in on the new one, or one effect into another; only one is ever
-- fully shown. Each view is { scene, actor, button, entry }.
local model = { views = {}, status = {} } -- entry, current, on; tried, why; status[id] = "loaded" or "skipped"

-- A scene with its camera and one actor, empty. Returns the view, or nil and why.
local function NewView()
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, ns.bar)
    if not ok or not scene then return nil, "this client has no ModelScene" end
    -- Never takes the mouse: the icons under and round it keep their clicks and drags.
    scene:EnableMouse(false)
    if scene.SetMouseClickEnabled then pcall(scene.SetMouseClickEnabled, scene, false) end
    if scene.SetMouseMotionEnabled then pcall(scene.SetMouseMotionEnabled, scene, false) end
    scene:SetSize(SceneSize(), SceneSize())
    scene:Hide()
    pcall(scene.SetCameraFieldOfView, scene, MODEL_FOV)
    pcall(scene.SetCameraNearClip, scene, 0.1)
    pcall(scene.SetCameraFarClip, scene, 100)
    pcall(scene.SetCameraOrientationByAxisVectors, scene, -1, 0, 0, 0, 1, 0, 0, 0, 1)
    -- A bare actor first; Blizzard's template last, since its mixin rescales the actor itself.
    local actor
    for _, make in ipairs({
        function() return scene:CreateActor() end,
        function() return scene:CreateActor(nil, nil) end,
        function() return scene:CreateActor(nil, "ModelSceneActorTemplate") end,
    }) do
        local okA, made = pcall(make)
        if okA and made then actor = made break end
    end
    if not actor then return nil, "the client would not make an actor" end
    pcall(actor.SetAlpha, actor, 0)
    return { scene = scene, actor = actor }
end

-- Puts an effect on a view: its model, camera and tilt. False when the client
-- has no such model; that effect is then skipped from here on.
local function LoadEffect(view, entry)
    if view.entry == entry then return true end
    local ok, loaded = pcall(view.actor.SetModelByFileID, view.actor, entry.id)
    if not ok or loaded == false then
        model.status[entry.id] = "skipped"
        return false
    end
    model.status[entry.id] = "loaded"
    pcall(view.actor.SetPosition, view.actor, 0, 0, 0)
    pcall(view.actor.SetPitch, view.actor, entry.pitch or 0)
    pcall(view.scene.SetCameraPosition, view.scene, CameraFor(entry), 0, 0)
    view.entry = entry
    return true
end

-- Effect number `start`, or the next one going `step` through the list that
-- this client has, loaded onto `view`. Nil when it has none of them.
local function Resolve(view, start, step)
    local n = #SPARK_MODELS
    for k = 0, n - 1 do
        local entry = SPARK_MODELS[(start - 1 + k * step) % n + 1]
        if model.status[entry.id] ~= "skipped" and LoadEffect(view, entry) then return entry end
    end
end

local function EffectIndex(id)
    for i, entry in ipairs(SPARK_MODELS) do
        if entry.id == id then return i end
    end
end

-- The effect the player picked: saved by file id, the first one until they pick.
local function ChosenIndex()
    local db = ns.DB and ns.DB()
    return EffectIndex(db and db.sparkleModel) or 1
end

local function BuildModel()
    model.tried = true
    if not ns.bar then model.why = "the bar is not built" return end
    local view, why = NewView()
    if not view then model.why = why return end
    local entry = Resolve(view, ChosenIndex(), 1)
    if not entry then model.why = "this client has none of the sparkle effects" return end
    model.views[1], model.entry = view, entry
end

-- The glitter's alpha goes on the actor (intensity included) and, as the
-- share of the way faded in, on the scene too: the actor's is the one a model
-- is sure to follow.
local function SetGlitter(view, alpha)
    pcall(view.actor.SetAlpha, view.actor, alpha)
    local full = FullAlpha(view.entry)
    view.scene:SetAlpha(full > 0 and math.min(1, alpha / full) or 0)
end

-- Fades a view in to its effect's strength times the intensity, or out and
-- then hides it. A full fade takes FADE whatever the strength.
local function FadeView(view, on)
    local full = FullAlpha(view.entry)
    local function Set(alpha) SetGlitter(view, alpha) end
    if on then
        view.scene:Show()
        Fade(view, full, math.max(full, 1e-6), Set)
    else
        Fade(view, 0, math.max(full, 1e-6), Set, function() view.scene:Hide() end)
    end
end

-- After the Sparkle size or intensity changes: every scene's size and camera,
-- and the glitter showing takes the new strength (a fade in progress just
-- heads for it). Drawn sparkles pick the new values up with their next spark.
function ns.ApplySparkleLooks()
    for _, view in ipairs(model.views) do
        local size = SceneSize()
        view.scene:SetSize(size, size)
        if view.entry then
            pcall(view.scene.SetCameraPosition, view.scene, CameraFor(view.entry), 0, 0)
            if view == model.current and model.on then
                local full = FullAlpha(view.entry)
                Fade(view, full, math.max(full, 1e-6), function(alpha) SetGlitter(view, alpha) end, nil, not ns.Fading(view))
            end
        end
    end
end

-- Centered on a tracker and behind every icon: the bar's own level, which the
-- icons sit one above.
local function Place(view, button)
    view.scene:ClearAllPoints()
    view.scene:SetPoint("CENTER", button.icon, "CENTER")
    view.scene:SetFrameLevel(ns.bar:GetFrameLevel())
    view.button = button
end

-- The view not showing (made the first time it is needed), or the one there
-- is when the client will not make a second.
local function SpareView()
    for _, view in ipairs(model.views) do
        if view ~= model.current then return view end
    end
    if #model.views < 2 then
        local view = NewView()
        if view then
            model.views[#model.views + 1] = view
            return view
        end
    end
    return model.current or model.views[1]
end

local function PlaceModel(active)
    local current = model.current
    model.on = active ~= nil
    if not active then
        if current then FadeView(current, false) end
        return
    end
    if current and current.button == active and LoadEffect(current, model.entry) then
        FadeView(current, true) -- back on, from wherever its fade had got to
        return
    end
    -- A new tracker: the old glitter fades out where it is while the other
    -- scene fades in on the new tracker.
    if current then FadeView(current, false) end
    local nextView = SpareView()
    LoadEffect(nextView, model.entry)
    Place(nextView, active)
    FadeView(nextView, true)
    model.current = nextView
end

-- Picks sparkle effect `index`, or steps `step` from the one in use. One the
-- client lacks is skipped, going on the same way. The choice is saved; with
-- the glitter showing, the new effect crossfades in over the old one on the
-- active tracker. Returns the effect, its number, and how many there are.
function ns.SetSparkleEffect(index, step)
    local db = ns.DB()
    step = step or 1
    local n = #SPARK_MODELS
    index = ((index or (ChosenIndex() + step)) - 1) % n + 1
    if not model.views[1] then
        -- Nothing built yet: the choice is saved and checked when it first shows.
        db.sparkleModel = SPARK_MODELS[index].id
        return SPARK_MODELS[index], index, n
    end
    local current = model.current
    local view = SpareView()
    local entry = Resolve(view, index, step)
    if not entry then return nil end
    db.sparkleModel = entry.id
    model.entry = entry
    if model.on and current and current ~= view then
        FadeView(current, false)
        Place(view, current.button)
        FadeView(view, true)
        model.current = view
    elseif model.on and view == current then
        FadeView(view, true) -- one scene only: the new effect takes its place
    end
    return entry, EffectIndex(entry.id), n
end

-- The effect in use (or picked), its number, how many there are, and what
-- became of each one this client was asked for.
function ns.SparkleEffect()
    local index = model.entry and EffectIndex(model.entry.id) or ChosenIndex()
    return SPARK_MODELS[index], index, #SPARK_MODELS, model.status
end

-- Which way the sparkles are drawn, and why, for /forager debug.
function ns.SparklePath()
    if model.views[1] then return "model", model.entry.name .. " (" .. model.entry.id .. ")" end
    if model.tried then return "drawn sparkles", tostring(model.why) end
    return "not started", "no tracker has been on yet"
end

-- The drawn sparkles: the bonus objectives sparkle (a white four point star
-- with its own alpha), or the classic cooldown star where that is missing.
local SPARK_ATLAS = "bonusobjectives-bar-starburst"
local SPARK_FILE = "Interface\\Cooldown\\star4" -- a soft white star on black, for ADD
local SPARKS = 6          -- per tracker, made the first time it is on
local SPARK_SIZE = 14
local SPARK_TIME = 1      -- seconds from start to gone
local SPARK_CHANCE = 0.5  -- each tick (four a second): the odds that a free spark starts

-- The layer just behind each look's border art.
function ns.SparkLayer(button)
    local shape = rawget(button, "fgShape") or "bar"
    if shape == "circle-edge" then return "BACKGROUND", 0 end -- the dark edge disc is BACKGROUND 1
    if shape == "square" and not (S() and S() ~= Styles.Dark) then
        return "BORDER", 6 -- Dark's edge lines are BORDER 7
    end
    -- The bar frame (OVERLAY 0), the gold ring (OVERLAY 1), EllesmereUI's edge (OVERLAY 0).
    return "OVERLAY", -1
end

-- A start point on the border, from the icon's center, and the way out from it.
function ns.SparkPath(button)
    local shape = rawget(button, "fgShape") or "bar"
    local half = (ns.ICON_SIZE or 36) / 2
    if IsCircle(shape) then
        local radius = half + (shape == "circle-edge" and 1 or 0)
        local angle = math.random() * 2 * math.pi
        return radius * math.cos(angle), radius * math.sin(angle), math.cos(angle), math.sin(angle)
    end
    -- On the square's edges: anywhere along a side, out across that side.
    local t = math.random() * 4
    local side, along = math.floor(t), (t % 1) * 2 - 1
    if side == 0 then return along * half, half, 0, 1 end
    if side == 1 then return half, along * half, 1, 0 end
    if side == 2 then return along * half, -half, 0, -1 end
    return -half, along * half, -1, 0
end

local function MakeSparks(button)
    local list = {}
    for i = 1, SPARKS do
        local tex = button:CreateTexture(nil, "OVERLAY", nil, -1)
        if HasAtlas(SPARK_ATLAS) then tex:SetAtlas(SPARK_ATLAS) else tex:SetTexture(SPARK_FILE) end
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(1, 0.82, 0.35) -- gold, like the glow
        tex:SetSize(SPARK_SIZE, SPARK_SIZE)
        tex:Hide()
        local anim = tex:CreateAnimationGroup()
        local move = anim:CreateAnimation("Translation")
        move:SetDuration(SPARK_TIME)
        move:SetSmoothing("OUT")
        local fadeIn = anim:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.2)
        local fadeOut = anim:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0)
        fadeOut:SetStartDelay(0.2)
        fadeOut:SetDuration(SPARK_TIME - 0.2)
        local turn = anim:CreateAnimation("Rotation")
        turn:SetDuration(SPARK_TIME)
        anim:SetScript("OnFinished", function() tex:Hide() end)
        list[i] = { tex = tex, anim = anim, move = move, turn = turn, fadeIn = fadeIn, fadeOut = fadeOut }
    end
    button.fgSparks = list
    return list
end

local function StopSparks(button)
    for _, spark in ipairs(rawget(button, "fgSparks") or {}) do
        spark.anim:Stop()
        spark.tex:Hide()
    end
end

-- With each update of the bar: `active` is the tracker that sparkles, or nil
-- for none. Starts at most one spark a tick, so a few are out at a time.
function ns.UpdateSparkles(active)
    -- The model is tried the first time a tracker sparkles, never at login.
    if active and not model.tried then BuildModel() end
    if model.views[1] then
        PlaceModel(active)
        return
    end
    -- Drawn sparkles: a tracker that has gone off lets its sparks finish their
    -- short life; pausing, hiding or switching them off stops them all.
    if not active then
        for _, button in ipairs(ns.trackButtons or {}) do StopSparks(button) end
        return
    end
    local list = rawget(active, "fgSparks") or MakeSparks(active)
    local size, strength = Looks()
    if strength <= 0 or math.random() >= SPARK_CHANCE then return end
    for _, spark in ipairs(list) do
        if not spark.anim:IsPlaying() then
            local x, y, outX, outY = ns.SparkPath(active)
            local drift = (4 + math.random() * 4) * size
            spark.tex:SetSize(SPARK_SIZE * size, SPARK_SIZE * size)
            spark.fadeIn:SetToAlpha(strength)
            spark.fadeOut:SetFromAlpha(strength)
            spark.tex:SetDrawLayer(ns.SparkLayer(active))
            spark.tex:ClearAllPoints()
            spark.tex:SetPoint("CENTER", active.icon, "CENTER", x, y)
            spark.move:SetOffset(outX * drift, outY * drift)
            spark.turn:SetDegrees((math.random() < 0.5 and -1 or 1) * (45 + math.random() * 45))
            spark.tex:Show()
            spark.anim:Play()
            return
        end
    end
end

-- For /forager debug icons: where each icon's pieces really are on screen, to
-- compare in game (centers in the bar's units; "-" when not laid out yet).
-- Each line is pcall'd, so a value the client keeps secret cannot stop it.
function ns.ProbeIcons(out)
    local function At(x, y)
        if type(x) ~= "number" or type(y) ~= "number" then return "-" end
        return ("%.1f,%.1f"):format(x, y)
    end
    local function Center(region)
        if not (region and region.GetCenter) then return "-" end
        return At(region:GetCenter())
    end
    local list = {}
    for _, button in ipairs(ns.trackButtons or {}) do list[#list + 1] = button end
    for _, button in ipairs(ns.pauseButtons or { ns.pauseButton }) do list[#list + 1] = button end
    for i, button in ipairs(list) do
        local ok, line = pcall(function()
            local icon, parts = button.icon, rawget(button, "fgCircle")
            local text = ("icon %d: look %s, on %s, masks %s, picture at %s"):format(i,
                tostring(rawget(button, "fgShape") or "bar"), tostring(rawget(button, "lit") and true or false),
                tostring((icon:GetNumMaskTextures())), Center(icon))
            if parts then
                local ring = parts.ring
                local left, top = ring:GetLeft(), ring:GetTop()
                local scale = (ring:GetWidth() or 0) / 64
                local ringAt = (type(left) == "number" and type(top) == "number")
                    and At(left + RING.cx * scale, top - RING.cy * scale) or "-"
                text = text .. (", gold ring at %s (alpha %s)"):format(ringAt, tostring((ring:GetAlpha())))
                local glow, spec = parts.glow, parts.glowSpec
                if glow then
                    local gx, gy = glow:GetCenter()
                    local w, h = glow:GetSize()
                    local glowAt = type(gx) == "number" and At(gx + (spec.cx - 0.5) * w, gy - (spec.cy - 0.5) * h) or "-"
                    text = text .. (", round glow ring at %s, %s, shown %s"):format(glowAt, spec.atlas, tostring((glow:IsShown())))
                end
                text = text .. (", highlight blend %s alpha %s"):format(tostring((parts.hl:GetBlendMode())), tostring((parts.hl:GetAlpha())))
            end
            local shimmer = Field(button, "glow")
            if shimmer then
                local _, _, _, a = shimmer:GetVertexColor()
                text = text .. (", shimmer shown %s alpha %s"):format(tostring((shimmer:IsShown())), tostring(a))
            end
            -- The picture and its sweep, as on-screen rects (left, right, top, bottom).
            local function Rect(region)
                if not (region and region.GetLeft) then return "-" end
                local l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
                if type(l) ~= "number" or type(r) ~= "number" or type(t) ~= "number" or type(b) ~= "number" then return "-" end
                return ("%.1f..%.1f x %.1f..%.1f"):format(l, r, b, t)
            end
            text = text .. ", picture " .. Rect(icon)
            local cd = Field(button, "cd")
            if cd then
                text = text .. (", sweep %s, %s, shown %s"):format(Rect(cd), tostring(rawget(cd, "fgSweep") or "not set"),
                    tostring((cd:IsShown())))
            end
            local sparks = rawget(button, "fgSparks")
            if sparks then
                local out = 0
                for _, spark in ipairs(sparks) do if spark.anim:IsPlaying() then out = out + 1 end end
                text = text .. (", drawn sparkles %d of %d out"):format(out, #sparks)
            end
            for v, view in ipairs(model.views) do
                if view.button == button then
                    local okL, level = pcall(view.scene.GetFrameLevel, view.scene)
                    text = text .. (", glitter %d (%s) at %s, rect %s, shown %s, alpha %s, level %s"):format(v, model.entry.name,
                        Center(view.scene), Rect(view.scene), tostring((view.scene:IsShown())), tostring(ns.FadeLevel(view)), tostring(okL and level))
                end
            end
            return text
        end)
        out(ok and line or ("icon " .. i .. ": " .. tostring(line)))
    end
end

-- The pause button: round with the trackers under Round, else as before.
function ns.SkinPauseButton(button)
    if type(button) ~= "table" then return end
    TryShape("pause button", button, PauseShape())
end

function ns.UpdateIconShapes()
    for _, button in ipairs(ns.trackButtons or {}) do ns.ShapeIcon(button) end
    for _, button in ipairs(ns.pauseButtons or { ns.pauseButton }) do ns.SkinPauseButton(button) end
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
    end,
})

