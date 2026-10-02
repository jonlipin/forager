-- Forager: rotates through your tracking spells (Find Herbs and Find Minerals
-- by default, any others you tick) on a set delay while you are out of combat.
--
-- The switch goes through C_Minimap.SetTracking, the call Blizzard's own
-- tracking menu makes. Classic clients have at times refused it from a timer
-- and only allowed it inside a key press or click. Forager first tries the
-- timer; if the game blocks that, it remembers and from then on makes each
-- switch on your next key press after the delay, leaving ability keys alone.

local ADDON = ...

local HERBS, MINERALS = 2383, 2580
local ICON = "Interface\\Icons\\INV_Misc_Flower_02"

local DEFAULTS = {
    enabled = true,
    delay = 6,             -- seconds between switches
    skipAbilityKeys = true, -- key press mode: never switch on an ability key
    minimap = true,
    minimapAngle = 225,
    bar = true,            -- the on-screen tracker icons
    barLocked = false,
    barVertical = false,
    barCountdown = true,
    barSwipe = true,       -- cooldown swipe on the next tracker
    barHideCombat = false,
    barScale = 100,        -- percent
    onlyMoving = false,
    pauseResting = true,   -- cities and inns
    pauseInstances = true, -- dungeons, raids, battlegrounds, arenas
    restoreAfterDeath = true, -- turn the last tracker back on after you die
    quiet = true,          -- mute sound effects for a moment around each switch
    pauseLooting = true,   -- hold a due switch while the loot window is open
    minimapShowsTracker = true, -- the minimap button shows the tracker that is on
    swapFishing = true,    -- fishing pole equipped: Find Fish
    swapCatForm = true,    -- Cat Form: Track Humanoids
    swapHunterPvP = true,  -- hunter in a battleground or arena: Track Humanoids
    -- method: nil = not learned yet, "timer", "key", "none"
    -- rotation: { [spellID] = true } for the trackers that take part
    -- lastTracked: { [player GUID] = key or false } for restoring after death
    -- order: { spellID, ... } the order you set; trackers missing from it
    --        follow in the tracking menu's order
}

local db
local lastSwitch = 0   -- GetTime() of the last change of tracking spell
local lastActive       -- key of the tracking spell last seen on
local attempt          -- the switch waiting to be confirmed
local silentFails = 0
local failing = {}     -- [key] = GetTime() until which a tracker that failed to cast is skipped
local looting = false  -- the loot window is open
local override         -- { key, name, why, before } while a situation calls for a tracker
local ownedKey         -- a situational tracker Forager put on, which the rotation may replace
local mutedAt          -- GetTime() when Forager muted sound effects
local Mute, Unmute     -- defined with Cast
local RefreshOptions, UpdateMinimapButton, SetUpKeys, UpdateBar, Toggle -- defined below

---------------------------------------------------------------------------
-- Log, kept in saved variables so a test session can be read after /reload
---------------------------------------------------------------------------

local function Log(msg)
    if not ForagerLog then return end
    local lines = ForagerLog.lines
    lines[#lines + 1] = "#" .. ForagerLog.session .. " " .. date("%H:%M:%S") .. " " .. msg
    while #lines > 400 do table.remove(lines, 1) end
end

local function Print(msg)
    print("|cff7fd96aForager|r: " .. msg)
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------

local function InRotation(key)
    return db.rotation[key] == true
end

-- Every tracking spell the character has, in the tracking menu's order.
--   s.list     { key, index, name, texture, active } per spell
--   s.byKey    the same, by key (the spell ID, or the name when there is none)
--   s.rotation the ones ticked to take part
--   s.active   key of the tracking spell that is on
--   s.other    name of a tracking spell that is on but not in the rotation
local function Scan()
    local s = { list = {}, byKey = {}, rotation = {} }
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return s end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if info and (info.spellID or info.type == "spell") then
            local key = info.spellID or info.name
            if key then
                local e = {
                    key = key, index = i, name = info.name or tostring(key),
                    texture = info.texture, active = info.active and true or false,
                }
                s.list[#s.list + 1] = e
                s.byKey[key] = e
                if e.active then
                    s.active = key
                    if not InRotation(key) then s.other = e.name end
                end
            end
        end
    end
    local rank = {}
    for i, key in ipairs(db.order) do rank[key] = i end
    for _, e in ipairs(s.list) do e.rank = rank[e.key] or (100000 + e.index) end
    table.sort(s.list, function(a, b) return a.rank < b.rank end)
    for _, e in ipairs(s.list) do
        if InRotation(e.key) then s.rotation[#s.rotation + 1] = e end
    end
    return s
end

-- Moves a tracker one place up (-1) or down (+1). The saved order keeps
-- trackers this character doesn't know, so another character's order stays.
local function MoveTracker(key, dir)
    local s = Scan()
    local keys = {}
    for _, e in ipairs(s.list) do keys[#keys + 1] = e.key end
    local i
    for n, k in ipairs(keys) do if k == key then i = n end end
    local j = i and i + dir
    if not (j and j >= 1 and j <= #keys) then return false end
    keys[i], keys[j] = keys[j], keys[i]
    local known = {}
    for _, k in ipairs(keys) do known[k] = true end
    for _, k in ipairs(db.order) do
        if not known[k] then keys[#keys + 1] = k end
    end
    db.order = keys
    return true
end

local function NameOf(s, key)
    local e = key and s.byKey[key]
    return e and e.name or tostring(key)
end

-- The tracker after the one that is on, skipping any that just failed to cast.
local function NextEntry(s)
    local rot = s.rotation
    local n = #rot
    if n == 0 then return nil end
    local pos = 0
    for i, e in ipairs(rot) do
        if e.key == s.active then pos = i end
    end
    local now = GetTime()
    for step = 1, n do
        local e = rot[(pos + step - 1) % n + 1]
        if e.key ~= s.active and not ((failing[e.key] or 0) > now) then return e end
    end
    return nil
end

local function Busy()
    local ok, casting = pcall(function()
        return (UnitCastingInfo and UnitCastingInfo("player")) or (UnitChannelInfo and UnitChannelInfo("player"))
    end)
    return ok and casting ~= nil
end

local function OnCooldown(spellID)
    if type(spellID) ~= "number" or not (C_Spell and C_Spell.GetSpellCooldown) then return false end
    local ok, onCd = pcall(function()
        local cd = C_Spell.GetSpellCooldown(spellID)
        if not cd then return false end
        if issecretvalue and (issecretvalue(cd.startTime) or issecretvalue(cd.duration)) then return false end
        return cd.startTime > 0 and cd.duration > 0 and cd.startTime + cd.duration > GetTime()
    end)
    return ok and onCd
end

local function Moving()
    local ok, moving = pcall(function()
        local speed = GetUnitSpeed("player")
        if issecretvalue and issecretvalue(speed) then return true end
        return speed > 0
    end)
    return not ok or moving
end

-- Returns nil when a switch may happen now, else the reason it may not.
local function Blocker(s)
    if override then return "using " .. override.name .. " (" .. override.why .. ")" end
    if not db.enabled then return "paused" end
    if db.method == "none" then return "the game refuses the switch" end
    if InCombatLockdown() or UnitAffectingCombat("player") then return "in combat" end
    if UnitIsDeadOrGhost("player") then return "dead" end
    if UnitOnTaxi("player") then return "on a flight" end
    if db.pauseResting and IsResting() then return "in a city or inn" end
    if db.pauseInstances then
        local inside, kind = IsInInstance()
        if inside and kind ~= "none" then return "in a dungeon, raid or battleground" end
    end
    if #s.list < 2 then return "this character knows fewer than two tracking spells" end
    if #s.rotation < 2 then return "tick at least two trackers to rotate" end
    if s.other and s.active ~= ownedKey then return s.other .. " is on, and it isn't in the rotation" end
    local nextEntry = NextEntry(s)
    if not nextEntry then return "the other trackers can't be cast right now" end
    -- Key press mode only switches while you press keys anyway.
    if db.onlyMoving and db.method ~= "key" and not Moving() then return "standing still" end
end

-- Holds back a due switch for a moment without pausing the countdown. Each
-- switch starts the global cooldown, so counting this as a reason to wait
-- hid the countdown for 1.5 s after every switch.
local function Momentary(s)
    if Busy() then return "casting" end
    if db.pauseLooting and looting then return "looting" end
    local nextEntry = NextEntry(s)
    if nextEntry and OnCooldown(nextEntry.key) then return "global cooldown" end
end

local function Due()
    return GetTime() - lastSwitch >= db.delay
end

local function Verify()
    local a = attempt
    if not a or a.done then return end
    a.done = true
    local s = Scan()
    if mutedAt and s.active ~= a.target then Unmute() end
    if s.active == a.target then
        silentFails = 0
        failing[a.target] = nil
        if db.method == nil and a.source == "timer" then
            db.method = "timer"
            Log("method learned: timer")
        end
        Log("switched to " .. a.name .. " (" .. a.source .. ")")
    elseif a.gameError then
        -- The game said why (wrong form, not enough mana...): skip that one a while.
        failing[a.target] = GetTime() + 60
        Log("switch to " .. a.name .. " failed: " .. a.gameError .. ", skipped for 60 s")
    elseif not a.blocked then
        silentFails = silentFails + 1
        Log("switch to " .. a.name .. " (" .. a.source .. ") did not take, now " .. NameOf(s, s.active) .. ", " .. silentFails .. " in a row")
        if a.source == "timer" and silentFails >= 3 then
            db.method = "key"
            silentFails = 0
            Log("method learned: key (timer switches never took)")
            Print("switching from a timer doesn't work here, so Forager will switch on your next key press after the delay.")
            SetUpKeys()
        end
    end
    if RefreshOptions then RefreshOptions() end
end

-- Each switch is a spell cast with its own sound. Sound effects are muted
-- from the cast until just after it lands (2 s at most). db.unmuteSFX lets a
-- reload or crash in between put the sound back at the next login.
Mute = function()
    if not db.quiet then return end
    if mutedAt then
        mutedAt = GetTime()
        return
    end
    local ok, value = pcall(GetCVar, "Sound_EnableSFX")
    if not ok or value ~= "1" then return end
    if pcall(SetCVar, "Sound_EnableSFX", "0") then
        mutedAt = GetTime()
        db.unmuteSFX = true
    end
end

Unmute = function()
    if not (mutedAt or db.unmuteSFX) then return end
    pcall(SetCVar, "Sound_EnableSFX", "1")
    mutedAt, db.unmuteSFX = nil, nil
end

local function Cast(e, source)
    Mute()
    attempt = { at = GetTime(), target = e.key, name = e.name, source = source }
    local ok, err = pcall(C_Minimap.SetTracking, e.index, true)
    if not ok then Log("SetTracking error: " .. tostring(err)) end
    C_Timer.After(1, Verify)
end

local function TrySwitch(source)
    if not Due() then return end
    local s = Scan()
    if Blocker(s) or Momentary(s) then return end
    if attempt and not attempt.done then return end
    Cast(NextEntry(s), source)
    -- Count the try as a switch so a refusal is not repeated every tick.
    lastSwitch = GetTime()
end

-- Death clears tracking. Each character's last tracker is remembered and put
-- back once you're alive again, whether or not the rotation is running.
local deathAt, aliveAt

local function RememberTracker(active)
    local guid = UnitGUID("player")
    if not guid then return end
    if active then
        db.lastTracked[guid] = active
    elseif not deathAt and not UnitIsDeadOrGhost("player") then
        -- You switched tracking off yourself: nothing to restore.
        db.lastTracked[guid] = false
    end
end

local function TryRestore()
    if not deathAt then return end
    if UnitIsDeadOrGhost("player") then aliveAt = nil return end
    aliveAt = aliveAt or GetTime()
    local s = Scan()
    if not db.restoreAfterDeath or s.active or GetTime() - aliveAt > 30 then
        deathAt, aliveAt = nil, nil
        return
    end
    if InCombatLockdown() or UnitAffectingCombat("player") or UnitOnTaxi("player") then return end
    if Momentary(s) or (attempt and not attempt.done) then return end
    local key = db.lastTracked[UnitGUID("player") or ""]
    local e = key and s.byKey[key]
    if not e then
        deathAt, aliveAt = nil, nil
        return
    end
    Log("restoring " .. e.name .. " after death")
    Cast(e, "restore")
end

-- Trackers a situation calls for. Track Humanoids is a druid spell (Cat
-- Form) and a hunter spell; Find Fish came with the Weather-Beaten Journal.
local TRACK_HUMANOIDS = { [5225] = true, [19883] = true }
local FIND_FISH = { [43308] = true }

local function FindEntry(s, ids, name)
    for _, e in ipairs(s.list) do
        if ids[e.key] or e.name == name then return e end
    end
end

local function HoldingFishingPole()
    local id = GetInventoryItemID and GetInventoryItemID("player", 16)
    if not id or not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
    return classID == 2 and subClassID == 20
end

local function InCatForm()
    local ok, form = pcall(GetShapeshiftFormID)
    return ok and form == 1
end

local function HunterInBattleground()
    local _, class = UnitClass("player")
    if class ~= "HUNTER" then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "pvp" or kind == "arena")
end

-- The tracker the moment calls for, and why, or nil.
local function Situation(s)
    if db.swapFishing and HoldingFishingPole() then
        local e = FindEntry(s, FIND_FISH, "Find Fish")
        if e then return e, "fishing pole equipped" end
    end
    if db.swapCatForm and InCatForm() then
        local e = FindEntry(s, TRACK_HUMANOIDS, "Track Humanoids")
        if e then return e, "Cat Form" end
    end
    if db.swapHunterPvP and HunterInBattleground() then
        local e = FindEntry(s, TRACK_HUMANOIDS, "Track Humanoids")
        if e then return e, "battleground" end
    end
end

-- Puts on the tracker a situation calls for, and when it's over hands back
-- to the rotation, or to what was on before when the rotation is paused.
local function UpdateSituation()
    local s = Scan()
    local e, why = Situation(s)
    if e then
        if not override or override.key ~= e.key then
            override = { key = e.key, name = e.name, why = why, before = override and override.before or s.active }
            Log("situation: " .. why .. ", using " .. e.name)
            if UpdateBar then UpdateBar() end
        end
        if s.active == e.key then return end
        if InCombatLockdown() or UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
        if Busy() or OnCooldown(e.key) or (failing[e.key] or 0) > GetTime() then return end
        if attempt and not attempt.done then return end
        Cast(e, "situation")
        ownedKey = e.key
    elseif override then
        local before = override.before
        Log("situation over (" .. override.why .. ")")
        override = nil
        if db.enabled then
            lastSwitch = 0 -- the rotation picks up at once
        elseif before and before ~= s.active and s.byKey[before] then
            Cast(s.byKey[before], "situation")
        end
        if UpdateBar then UpdateBar() end
    end
end

local function OnTrackingChanged()
    local active = Scan().active
    if active ~= lastActive then
        if mutedAt and attempt and active == attempt.target then C_Timer.After(0.3, Unmute) end
        if active ~= ownedKey then ownedKey = nil end
        RememberTracker(active)
        if active then lastSwitch = GetTime() end
        lastActive = active
        if RefreshOptions then RefreshOptions() end
        if UpdateMinimapButton then UpdateMinimapButton() end
        if UpdateBar then UpdateBar() end
    end
end

-- The game blocked a call made by Forager.
local function OnRefused(event, addon)
    if addon ~= ADDON then return end
    local a = attempt
    local stack = debugstack and debugstack(2, 6, 0) or ""
    Log(event .. " during " .. (a and not a.done and a.source or "no switch") .. "\n" .. stack)
    if not a or a.done then return end
    a.blocked = true
    if a.source == "timer" then
        db.method = "key"
        Log("method learned: key")
        Print("the game only allows switching tracking during a key press, so Forager will switch on your next key press after the delay.")
        SetUpKeys()
    elseif a.source == "key" then
        db.method = "none"
        Log("method learned: none")
        Print("the game refuses addon tracking switches altogether, so Forager can't switch for you. /forager retest tries again.")
    end
    if RefreshOptions then RefreshOptions() end
end

-- A red error right after a switch (wrong form, out of mana and so on).
local function OnGameError(message)
    local a = attempt
    if a and not a.done and GetTime() - a.at < 1 and type(message) == "string" then
        a.gameError = message
    end
end

---------------------------------------------------------------------------
-- Key press mode
---------------------------------------------------------------------------

local ABILITY_BINDINGS = {
    "^ACTIONBUTTON", "^MULTIACTIONBAR", "^BONUSACTIONBUTTON", "^SHAPESHIFTBUTTON",
    "^PETACTIONBUTTON", "^CLICK ", "^SPELL ", "^MACRO ", "^ITEM ", "^INTERACT", "^FORAGER_",
}

local function IsAbilityKey(key)
    local prefix = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
    local action = GetBindingAction(prefix .. key, true)
    if (not action or action == "") and prefix ~= "" then action = GetBindingAction(key, true) end
    if not action or action == "" then return false end
    for _, pattern in ipairs(ABILITY_BINDINGS) do
        if action:find(pattern) then return true end
    end
    return false
end

local keyFrame
local keysReady = false

local function OnKey(_, key)
    if db.method ~= "key" then return end
    if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return end
    if db.skipAbilityKeys and IsAbilityKey(key) then return end
    TrySwitch("key")
end

-- The listener exists only in key press mode. Giving a frame an OnKeyDown
-- script turns on its keyboard capture by itself, and a frame that captures
-- without passing keys on swallows the whole keyboard (1.1.0 did exactly
-- that). So pass-through is switched on first, checked, and only then does
-- the frame get its script. Setting it up is not allowed in combat.
SetUpKeys = function()
    if keysReady or db.method ~= "key" then return end
    if InCombatLockdown() then return end
    keyFrame = keyFrame or CreateFrame("Frame", "ForagerKeyListener", UIParent)
    local ok = pcall(keyFrame.SetPropagateKeyboardInput, keyFrame, true)
    if not ok or (keyFrame.GetPropagateKeyboardInput and not keyFrame:GetPropagateKeyboardInput()) then
        pcall(keyFrame.EnableKeyboard, keyFrame, false)
        Log("key listener refused: keys could not be passed through")
        Print("couldn't watch key presses safely, so switching only happens when you click a tracker icon or use the key binding.")
        return
    end
    keyFrame:SetScript("OnKeyDown", OnKey)
    keyFrame:EnableKeyboard(true)
    keysReady = true
    Log("key listener on")
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

local function MethodText()
    if db.method == "timer" then return "on a timer" end
    if db.method == "key" then return "on your next key press after the delay" end
    if db.method == "none" then return "|cffff5050refused by the game|r" end
    return "on a timer (first switch still to come)"
end

local function StatusText()
    local s = Scan()
    local names = {}
    for _, e in ipairs(s.rotation) do names[#names + 1] = e.name end
    local lines = {
        "Tracking: |cffffffff" .. (s.active and NameOf(s, s.active) or "nothing") .. "|r",
        "Rotating: |cffffffff" .. (#names > 0 and table.concat(names, ", ") or "nothing") .. "|r",
        "Switches " .. MethodText(),
    }
    local reason = Blocker(s)
    if reason then
        lines[#lines + 1] = "|cffffb040Waiting: " .. reason .. "|r"
    else
        local nextName = NextEntry(s).name
        local left = db.delay - (GetTime() - lastSwitch)
        if left > 0 then
            lines[#lines + 1] = string.format("%s in %d s", nextName, math.ceil(left))
        elseif db.method == "key" then
            lines[#lines + 1] = nextName .. " on your next key press"
        else
            local hold = Momentary(s)
            lines[#lines + 1] = "Switching to " .. nextName .. (hold and (" after the " .. (hold == "casting" and "cast" or hold)) or "")
        end
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Tracker icons: one per tracker in the rotation, the one that is on glows,
-- and a pause / resume button after them. Same art as the action bars and
-- Conjurer's play and stop buttons, both seen working on this client.
---------------------------------------------------------------------------

local SIZE, GAP = 36, 6
local bar, pauseButton
local trackButtons = {}
local PLAY_ART = { "charactercreate-customize-playbutton", "common-icon-forwardarrow", "CGuy_Play" }
local STOP_ART = { "charactercreate-customize-stopbutton", "CGuy_Stop" }
-- The Cooldown Manager's swipe (Range Lens uses it on this client).
local SWIPE_FILE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"

local function HasAtlas(atlas)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    return ok and info ~= nil
end

local function FirstAtlas(list)
    for _, atlas in ipairs(list) do
        if HasAtlas(atlas) then return atlas end
    end
end

-- An icon under the action bar's rounded mask, with its frame, pressed art
-- and hover highlight.
local function DressIcon(button)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    if HasAtlas("UI-HUD-ActionBar-IconFrame-Mask") and button.CreateMaskTexture then
        local mask = button:CreateMaskTexture()
        mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
        mask:SetPoint("CENTER", icon, "CENTER")
        mask:SetSize(SIZE * 64 / 45, SIZE * 64 / 45)
        icon:AddMaskTexture(mask)
    else
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    if HasAtlas("UI-HUD-ActionBar-IconFrame") then
        local w = SIZE * 46 / 45
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetAtlas("UI-HUD-ActionBar-IconFrame")
        border:SetPoint("TOPLEFT")
        border:SetSize(w, SIZE)
        local pushed = button:CreateTexture(nil, "OVERLAY")
        pushed:SetAtlas("UI-HUD-ActionBar-IconFrame-Down")
        pushed:SetPoint("TOPLEFT")
        pushed:SetSize(w, SIZE)
        button:SetPushedTexture(pushed)
        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
        hl:SetPoint("TOPLEFT")
        hl:SetSize(w, SIZE)
        hl:SetBlendMode("ADD")
    else
        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
    end
    return icon
end

-- The proc glow the action bars use, falling back to a pulsing highlight.
local function MakeGlow(button)
    local glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetPoint("CENTER")
    glow:SetSize(SIZE * 1.42, SIZE * 1.42)
    glow:Hide()
    local anim = glow:CreateAnimationGroup()
    local flipbook = false
    if HasAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook") then
        glow:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
        flipbook = pcall(function()
            local flip = anim:CreateAnimation("FlipBook")
            flip:SetDuration(1)
            flip:SetFlipBookRows(6)
            flip:SetFlipBookColumns(5)
            flip:SetFlipBookFrames(30)
            flip:SetFlipBookFrameWidth(0)
            flip:SetFlipBookFrameHeight(0)
        end)
        if flipbook then anim:SetLooping("REPEAT") end
    end
    if not flipbook then
        if HasAtlas("UI-HUD-ActionBar-IconFrame-Mouseover") then
            glow:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
        else
            glow:SetColorTexture(0.5, 1, 0.4, 0.6)
        end
        glow:SetBlendMode("ADD")
        local pulse = anim:CreateAnimation("Alpha")
        pulse:SetFromAlpha(0.3)
        pulse:SetToAlpha(1)
        pulse:SetDuration(0.6)
        anim:SetLooping("BOUNCE")
    end
    return glow, anim
end

-- A click is a key press as far as the game is concerned, so this works even
-- when the timer can't switch.
local function SwitchTo(key, source)
    local s = Scan()
    if s.active == key then return end
    if InCombatLockdown() then Print("tracking can't be switched in combat.") return end
    local e = s.byKey[key]
    if not e then Print("this character doesn't know that tracking spell.") return end
    Cast(e, source or "click")
end

-- The position is the bar's centre in UIParent units, so changing the icon
-- size grows the bar about its centre.
local function SaveBarPosition()
    local x, y = bar:GetCenter()
    if not x then return end
    local scale = bar:GetScale()
    db.barPos = { x * scale, y * scale }
end

local function PlaceBar()
    bar:ClearAllPoints()
    local scale = bar:GetScale()
    local p = db.barPos
    if p then bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1] / scale, p[2] / scale)
    else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180 / scale) end
end

-- Lays out the first `count` tracker buttons and the pause button.
local function LayoutBar(count)
    if not bar then return end
    count = count or bar.count or 0
    bar.count = count
    bar:SetScale((db.barScale or 100) / 100)
    local long = SIZE * (count + 1) + GAP * count
    if db.barVertical then bar:SetSize(SIZE, long) else bar:SetSize(long, SIZE) end
    local function Put(b, i)
        local offset = (i - 1) * (SIZE + GAP)
        b:ClearAllPoints()
        if db.barVertical then b:SetPoint("TOP", 0, -offset) else b:SetPoint("LEFT", offset, 0) end
    end
    for i, b in ipairs(trackButtons) do
        b:SetShown(i <= count)
        if i <= count then Put(b, i) end
    end
    Put(pauseButton, count + 1)
    PlaceBar()
end

local function ResetBarPosition()
    db.barPos = nil
    if bar then PlaceBar() end
end

local function Draggable(button)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        if not db.barLocked then bar:StartMoving() end
    end)
    button:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        SaveBarPosition()
    end)
end

local function Tooltip(button, lines)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        for i, line in ipairs(lines(self)) do
            if i == 1 then GameTooltip:SetText(line, 1, 1, 1) else GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MoveHint()
    return db.barLocked and "Right-click: options" or "Drag: move   Right-click: options"
end

local function TrackButton(i)
    if trackButtons[i] then return trackButtons[i] end
    local b = CreateFrame("Button", "ForagerTrackButton" .. i, bar)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = DressIcon(b)
    b.glow, b.anim = MakeGlow(b)
    -- The swipe that ticks down to the next switch, inside the icon's frame.
    b.cd = CreateFrame("Cooldown", nil, b)
    b.cd:SetPoint("TOPLEFT", 2, -2)
    b.cd:SetPoint("BOTTOMRIGHT", -2, 2)
    pcall(b.cd.SetSwipeTexture, b.cd, SWIPE_FILE, 0, 0, 0, 0.75)
    pcall(b.cd.SetDrawEdge, b.cd, false)
    pcall(b.cd.SetHideCountdownNumbers, b.cd, true)
    b.cd:Hide()
    -- The seconds, on a layer above the swipe.
    b.textLayer = CreateFrame("Frame", nil, b)
    b.textLayer:SetAllPoints()
    b.textLayer:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.count = b.textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    b.count:SetPoint("CENTER")
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then SlashCmdList.FORAGER("") elseif self.key then SwitchTo(self.key) end
    end)
    Draggable(b)
    Tooltip(b, function(self)
        local s = Scan()
        return { NameOf(s, self.key), (s.active == self.key) and "|cff7fd96aOn now|r" or "Click: track this now", MoveHint() }
    end)
    trackButtons[i] = b
    return b
end

local function BuildBar()
    bar = CreateFrame("Frame", "ForagerBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)

    local p = CreateFrame("Button", "ForagerPauseButton", bar)
    p:SetSize(SIZE, SIZE)
    p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    p.icon = DressIcon(p)
    p.icon:SetTexture(ICON)
    -- Conjurer's Ready button: character creation's play and stop buttons
    -- laid over the icon, sized as there (30 and 26 on a 42 icon).
    local play, stop = FirstAtlas(PLAY_ART), FirstAtlas(STOP_ART)
    p.play = p:CreateTexture(nil, "OVERLAY", nil, 2)
    p.play:SetPoint("CENTER")
    p.play:SetSize(SIZE * 30 / 42, SIZE * 30 / 42)
    if play then p.play:SetAtlas(play) end
    p.stop = p:CreateTexture(nil, "OVERLAY", nil, 2)
    p.stop:SetPoint("CENTER")
    p.stop:SetSize(SIZE * 26 / 42, SIZE * 26 / 42)
    if stop then p.stop:SetAtlas(stop) end
    p.playArt, p.stopArt = play, stop
    -- Without the art, words say it instead.
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
    p.text:SetPoint("BOTTOM", 0, 3)
    p:SetScript("OnClick", function(_, button)
        if button == "RightButton" then SlashCmdList.FORAGER("") else Toggle() end
    end)
    Draggable(p)
    Tooltip(p, function()
        local key = GetBindingKey("FORAGER_TOGGLE")
        return { db.enabled and "Pause Forager" or "Resume Forager", StatusText(),
            key and ("Key: " .. ((GetBindingText and GetBindingText(key)) or key)) or "Set a key in the options", MoveHint() }
    end)
    pauseButton = p
    LayoutBar(0)
end

UpdateBar = function()
    if not db then return end
    local s = Scan()
    local show = db.bar and #s.list > 0
    if db.barHideCombat and (InCombatLockdown() or UnitAffectingCombat("player")) then show = false end
    if not show then
        if bar then bar:Hide() end
        return
    end
    if not bar then BuildBar() end
    bar:Show()

    local entries = s.rotation
    for i, e in ipairs(entries) do
        local b = TrackButton(i)
        if b.key ~= e.key then
            b.key = e.key
            b.icon:SetTexture(e.texture or ICON)
        end
    end
    if bar.count ~= #entries then LayoutBar(#entries) end

    local left = math.ceil(db.delay - (GetTime() - lastSwitch))
    -- Nothing counts down while a switch is still landing.
    local landing = attempt and not attempt.done and s.active ~= attempt.target
    local nextEntry = (db.enabled and left > 0 and not landing and not Blocker(s)) and NextEntry(s)
    for i = 1, #entries do
        local b = trackButtons[i]
        local on = s.active == b.key
        if on ~= b.lit then
            b.lit = on
            b.glow:SetShown(on)
            if on then b.anim:Play() else b.anim:Stop() end
        end
        -- Seconds to the next switch, and a swipe ticking down, on the icon
        -- that comes next.
        local isNext = nextEntry and nextEntry.key == b.key
        b.count:SetText((db.barCountdown and isNext) and left or "")
        if db.barSwipe and isNext then
            if b.swipeStart ~= lastSwitch or b.swipeDuration ~= db.delay then
                b.swipeStart, b.swipeDuration = lastSwitch, db.delay
                pcall(b.cd.SetCooldown, b.cd, lastSwitch, db.delay)
            end
            b.cd:Show()
        elseif b.swipeStart then
            -- Not Cooldown:Clear(): the game marks it as protected.
            b.swipeStart, b.swipeDuration = nil, nil
            b.cd:Hide()
        end
    end

    -- Running: stop art pauses it. Paused: play art resumes it.
    local p = pauseButton
    p.icon:SetDesaturated(not db.enabled)
    p.stop:SetShown(db.enabled and p.stopArt ~= nil)
    p.play:SetShown(not db.enabled and p.playArt ~= nil)
    local art = db.enabled and p.stopArt or p.playArt
    p.text:SetText(art and "" or (db.enabled and "Pause" or "Go"))
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local optionRefreshers = {}
local content, window, settingsPage, settingsCategory
local nativeOpenFailed = false
local W, CONTENT_H = 680, 750
local COL = 320          -- column width
local LEFT, RIGHT = 12, 352

local function TryCreate(kind, name, parent, templates)
    for _, template in ipairs(templates) do
        local ok, made = pcall(CreateFrame, kind, name, parent, template)
        if ok and made then return made, template end
    end
    return CreateFrame(kind, name, parent), "bare"
end

local function CheckButton(parent, label)
    local cb = TryCreate("CheckButton", nil, parent, { "UICheckButtonTemplate", "ChatConfigCheckButtonTemplate" })
    cb:SetSize(24, 24)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label or "")
    return cb
end

local function OptionCheck(parent, label, key, x, y, after)
    local cb = CheckButton(parent, label)
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetScript("OnClick", function(self)
        db[key] = self:GetChecked() and true or false
        if after then after() end
    end)
    optionRefreshers[#optionRefreshers + 1] = function() cb:SetChecked(db[key] and true or false) end
    return cb
end

local function OptionSlider(parent, label, key, minV, maxV, x, y, unit, step, after)
    step = step or 1
    local name = "ForagerOptionsSlider" .. key
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x + 4, y)
    holder:SetSize(COL - 20, 40)
    local caption = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    caption:SetPoint("TOPLEFT", 0, 0)
    caption:SetText(label)
    local value = holder:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    value:SetPoint("TOPRIGHT", 0, -1)

    local slider = TryCreate("Slider", name, holder, { "MinimalSliderTemplate", "UISliderTemplate", "OptionsSliderTemplate" })
    for _, suffix in ipairs({ "Low", "High", "Text" }) do
        local extra = _G[name .. suffix]
        if extra then extra:SetText("") extra:Hide() end
    end
    if slider.SetOrientation then slider:SetOrientation("HORIZONTAL") end
    slider:SetPoint("TOPLEFT", 2, -18)
    slider:SetSize(COL - 26, 18)
    slider:SetMinMaxValues(minV, maxV)
    if slider.SetValueStep then slider:SetValueStep(step) end
    if slider.SetObeyStepOnDrag then pcall(slider.SetObeyStepOnDrag, slider, true) end
    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        value:SetText(v .. unit)
        if self.syncing then return end
        db[key] = v
        if after then after() end
    end)
    optionRefreshers[#optionRefreshers + 1] = function()
        slider.syncing = true
        slider:SetValue(db[key])
        slider.syncing = false
        value:SetText(db[key] .. unit)
    end
end

local function Header(parent, text, x, y)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", x + 4, y)
    h:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetPoint("TOPLEFT", x + 4, y - 20)
    line:SetSize(COL - 20, 1)
end

local function PanelButton(parent, text, x, y, width, onClick)
    local b = TryCreate("Button", nil, parent, { "UIPanelButtonTemplate" })
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x + 2, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- An up or down arrow, in the minimal scroll bar's art (drawn on this
-- client by every ScrollFrameTemplate + MinimalScrollBar), else a text button.
local function OrderArrow(parent, side, tip, keyOf, dir)
    local base = "minimal-scrollbar-arrow-" .. side
    local b
    if HasAtlas(base) then
        b = CreateFrame("Button", nil, parent)
        b:SetSize(17, 11)
        b:SetNormalAtlas(base)
        if HasAtlas(base .. "-over") then b:SetHighlightAtlas(base .. "-over") end
        if HasAtlas(base .. "-down") then b:SetPushedAtlas(base .. "-down") end
    else
        b = TryCreate("Button", nil, parent, { "UIPanelButtonTemplate" })
        b:SetSize(22, 18)
        b:SetText(side == "top" and "^" or "v")
    end
    b:SetScript("OnClick", function()
        if MoveTracker(keyOf(), dir) then
            UpdateBar()
            RefreshOptions()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip, 1, 1, 1)
        GameTooltip:AddLine("Changes the order trackers rotate in.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- One row per tracking spell the character knows: tick it to rotate it, and
-- move it up or down to set the order.
local function TrackerList(parent, x, y)
    local rows = {}
    local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", x + 4, y - 4)
    empty:SetText("This character knows no tracking spells.")
    optionRefreshers[#optionRefreshers + 1] = function()
        local s = Scan()
        empty:SetShown(#s.list == 0)
        for i, e in ipairs(s.list) do
            local row = rows[i]
            if not row then
                row = CheckButton(parent)
                row:SetPoint("TOPLEFT", x, y - (i - 1) * 26)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(18, 18)
                row.icon:SetPoint("LEFT", row, "RIGHT", 2, 0)
                row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row:SetScript("OnClick", function(self)
                    db.rotation[self.key] = self:GetChecked() and true or nil
                    UpdateBar()
                    RefreshOptions()
                end)
                row.up = OrderArrow(parent, "top", "Move up", function() return row.key end, -1)
                row.up:SetPoint("TOPLEFT", parent, "TOPLEFT", x + COL - 60, y - (i - 1) * 26 - 6)
                row.down = OrderArrow(parent, "bottom", "Move down", function() return row.key end, 1)
                row.down:SetPoint("LEFT", row.up, "RIGHT", 6, 0)
                rows[i] = row
            end
            row.key = e.key
            row.icon:SetTexture(e.texture or ICON)
            row.label:SetText(e.name .. (e.active and "  |cff7fd96a(on)|r" or ""))
            row:SetChecked(InRotation(e.key))
            row:Show()
            row.up:Show()
            row.down:Show()
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #s.list)
            row.up:SetAlpha(i > 1 and 1 or 0.3)
            row.down:SetAlpha(i < #s.list and 1 or 0.3)
        end
        for i = #s.list + 1, #rows do
            rows[i]:Hide()
            rows[i].up:Hide()
            rows[i].down:Hide()
        end
    end
end

-- Binding names for a key the pause key would take over.
local function KeyText(key)
    return (GetBindingText and GetBindingText(key)) or key
end

local function ActionText(action)
    return _G["BINDING_NAME_" .. action] or action
end

local function PauseKeys()
    return GetBindingKey("FORAGER_TOGGLE")
end

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true,
}

-- A button that binds the pause / resume key: click it, press a key. It is
-- the same binding as Keybindings > AddOns > Forager, so the two agree.
-- The button takes the keyboard only while it waits for that one key press,
-- and lets go on the key, on Escape, on a second click and when the options
-- close: a frame holding the keyboard swallows every key (Forager 1.1.0).
local function KeyCapture(parent, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", x + 4, y - 4)
    label:SetText("Pause / resume key")

    local b = TryCreate("Button", "ForagerPauseKeyButton", parent, { "UIPanelButtonTemplate" })
    b:SetSize(120, 22)
    b:SetPoint("TOPLEFT", x + 136, y)
    local clear = TryCreate("Button", "ForagerPauseKeyClear", parent, { "UIPanelButtonTemplate" })
    clear:SetSize(60, 22)
    clear:SetPoint("LEFT", b, "RIGHT", 4, 0)
    clear:SetText("Unbind")

    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", x + 4, y - 28)
    note:SetWidth(COL - 20)
    note:SetJustifyH("LEFT")

    local capturing, pending

    local function Show()
        if capturing then return end
        local key = PauseKeys()
        b:SetText(key and KeyText(key) or "Not bound")
        clear:SetEnabled(key ~= nil)
    end

    local function Stop(message)
        if capturing then
            capturing, pending = false, nil
            b:SetScript("OnKeyDown", nil)
            b:EnableKeyboard(false)
        end
        note:SetText(message or "")
        Show()
    end

    local function Bind(key)
        if InCombatLockdown() then
            Stop("|cffff5050Key bindings can't be changed in combat.|r")
            return
        end
        for _, old in ipairs({ PauseKeys() }) do SetBinding(old) end
        local before = GetBindingAction(key)
        local ok = SetBinding(key, "FORAGER_TOGGLE")
        if not ok then
            Stop("|cffff5050The game didn't take that key.|r")
            return
        end
        SaveBindings(GetCurrentBindingSet())
        Log("pause key bound to " .. key .. ((before ~= "" and before ~= "FORAGER_TOGGLE") and (", replacing " .. before) or ""))
        Stop((before ~= "" and before ~= "FORAGER_TOGGLE") and ("Replaced " .. ActionText(before) .. ".") or nil)
    end

    local function OnKey(_, key)
        if MODIFIER_KEYS[key] then return end
        if key == "ESCAPE" then
            Stop()
            return
        end
        local full = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        local current = GetBindingAction(full)
        if current ~= "" and current ~= "FORAGER_TOGGLE" and pending ~= full then
            pending = full
            note:SetText("|cffffb040" .. KeyText(full) .. " is used for " .. ActionText(current)
                .. ". Press it again to use it anyway, or press another key.|r")
            return
        end
        Bind(full)
    end

    b:SetScript("OnClick", function()
        if capturing then
            Stop()
            return
        end
        if InCombatLockdown() then
            note:SetText("|cffff5050Key bindings can't be changed in combat.|r")
            return
        end
        capturing = true
        b:SetText("Press a key...")
        note:SetText("Press the key you want. Escape cancels.")
        b:SetScript("OnKeyDown", OnKey)
        b:EnableKeyboard(true)
    end)
    clear:SetScript("OnClick", function()
        Stop()
        if InCombatLockdown() then
            note:SetText("|cffff5050Key bindings can't be changed in combat.|r")
            return
        end
        for _, old in ipairs({ PauseKeys() }) do SetBinding(old) end
        SaveBindings(GetCurrentBindingSet())
        Log("pause key unbound")
        Show()
    end)
    parent:HookScript("OnHide", function() Stop() end)
    optionRefreshers[#optionRefreshers + 1] = Show
end

local function BuildContent()
    local c = CreateFrame("Frame")
    c:SetSize(W, CONTENT_H)
    local function Refresh()
        if UpdateMinimapButton then UpdateMinimapButton() end
        UpdateBar()
    end

    -- Left column: switching, then which trackers rotate.
    Header(c, "Switching", LEFT, -4)
    OptionCheck(c, "Rotate my tracking", "enabled", LEFT, -30, Refresh)
    OptionSlider(c, "Time between switches", "delay", 2, 60, LEFT, -62, " s")
    OptionCheck(c, "Only switch while moving", "onlyMoving", LEFT, -106)
    OptionCheck(c, "Pause in cities and inns", "pauseResting", LEFT, -132)
    OptionCheck(c, "Pause in dungeons, raids and battlegrounds", "pauseInstances", LEFT, -158)
    OptionCheck(c, "Wait while the loot window is open", "pauseLooting", LEFT, -184)
    OptionCheck(c, "Quiet switches (mutes sound effects briefly)", "quiet", LEFT, -210, function()
        if not db.quiet then Unmute() end
    end)
    OptionCheck(c, "Leave ability keys alone (key press mode)", "skipAbilityKeys", LEFT, -236)
    OptionCheck(c, "Restore tracking after death", "restoreAfterDeath", LEFT, -262)

    Header(c, "Trackers to rotate", LEFT, -300)
    TrackerList(c, LEFT, -326)

    -- Right column: the icons, the minimap button, then status.
    Header(c, "Tracker icons", RIGHT, -4)
    OptionCheck(c, "Show the tracker icons", "bar", RIGHT, -30, Refresh)
    OptionCheck(c, "Lock them in place", "barLocked", RIGHT, -56, Refresh)
    OptionCheck(c, "Stack them vertically", "barVertical", RIGHT, -82, function() LayoutBar() end)
    OptionCheck(c, "Show the seconds to the next switch", "barCountdown", RIGHT, -108, Refresh)
    OptionCheck(c, "Swipe down to the next switch", "barSwipe", RIGHT, -134, Refresh)
    OptionCheck(c, "Hide them in combat", "barHideCombat", RIGHT, -160, Refresh)
    OptionSlider(c, "Icon size", "barScale", 60, 200, RIGHT, -192, "%", 5, function() LayoutBar() end)
    PanelButton(c, "Reset position", RIGHT, -238, 130, ResetBarPosition)

    Header(c, "Minimap", RIGHT, -276)
    OptionCheck(c, "Show the minimap button", "minimap", RIGHT, -302, function()
        UpdateMinimapButton()
        if not db.minimap then Print("minimap button hidden. /forager opens the options.") end
    end)
    OptionCheck(c, "Show the current tracker on it", "minimapShowsTracker", RIGHT, -328, function() UpdateMinimapButton() end)

    Header(c, "Swap for the situation", RIGHT, -366)
    OptionCheck(c, "Fishing pole equipped: Find Fish", "swapFishing", RIGHT, -392)
    OptionCheck(c, "Cat Form: Track Humanoids", "swapCatForm", RIGHT, -418)
    OptionCheck(c, "Hunter in a battleground: Track Humanoids", "swapHunterPvP", RIGHT, -444)

    Header(c, "Keys", RIGHT, -482)
    KeyCapture(c, RIGHT, -508)

    Header(c, "Status", RIGHT, -566)
    local status = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", RIGHT + 4, -594)
    status:SetWidth(COL - 20)
    status:SetJustifyH("LEFT")
    status:SetSpacing(3)
    optionRefreshers[#optionRefreshers + 1] = function() status:SetText(StatusText()) end
    PanelButton(c, "Try the timer again", RIGHT, -678, 160, function()
        db.method = nil
        silentFails = 0
        Log("method reset from options")
        RefreshOptions()
    end)
    local hint = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", RIGHT + 4, -712)
    hint:SetWidth(COL - 20)
    hint:SetJustifyH("LEFT")
    hint:SetText("More key bindings (switch to the next tracker, open these options): Options > Keybindings > AddOns > Forager. /forager opens this page.")

    -- Keeps the countdown live while the options are open.
    local elapsed = 0
    c:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            status:SetText(StatusText())
        end
    end)
    return c
end

local function EnsureContent()
    if content then return content end
    local ok, made = pcall(BuildContent)
    if not ok then
        Print("the options could not be built: " .. tostring(made))
        return nil
    end
    content = made
    return content
end

RefreshOptions = function()
    if not (content and content:IsVisible()) then return end
    for _, refresh in ipairs(optionRefreshers) do refresh() end
end

local function Host(parent, x, y, scale)
    scale = scale or 1
    content:SetParent(parent)
    content:ClearAllPoints()
    content:SetScale(scale)
    content:SetPoint("TOPLEFT", parent, "TOPLEFT", x / scale, y / scale)
    content:Show()
    RefreshOptions()
end

local function BuildWindow()
    local f, template = TryCreate("Frame", "ForagerOptions", UIParent,
        { "ButtonFrameTemplate", "BasicFrameTemplateWithInset" })
    local top = template == "ButtonFrameTemplate" and -60 or -28
    f:SetSize(W, CONTENT_H - top + 10)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()
    tinsert(UISpecialFrames, "ForagerOptions")
    if template == "bare" then
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
    end
    if f.SetTitle then f:SetTitle("Forager")
    elseif f.TitleContainer and f.TitleContainer.TitleText then f.TitleContainer.TitleText:SetText("Forager")
    elseif f.TitleText then f.TitleText:SetText("Forager") end
    if f.SetPortraitToAsset then pcall(f.SetPortraitToAsset, f, ICON)
    elseif f.PortraitContainer and f.PortraitContainer.portrait then f.PortraitContainer.portrait:SetTexture(ICON) end
    if not (f.CloseButton or _G["ForagerOptionsCloseButton"]) then
        local close = TryCreate("Button", nil, f, { "UIPanelCloseButton" })
        close:SetPoint("TOPRIGHT", 2, 2)
        close:SetScript("OnClick", function() f:Hide() end)
    end
    f:SetScript("OnShow", function(self) Host(self, 0, top) end)
    return f
end

local function PageOpen()
    return settingsPage ~= nil and SettingsPanel ~= nil and SettingsPanel:IsShown()
        and settingsPage:GetParent() ~= nil and settingsPage:IsVisible()
end

-- Opens Options > AddOns > Forager. If the game won't show it, a standalone
-- window is used from then on. A second call closes whichever is open.
local function ToggleOptions()
    if PageOpen() then
        if SettingsPanel and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
        return
    end
    if window and window:IsShown() then
        window:Hide()
        return
    end
    if settingsCategory and Settings and Settings.OpenToCategory and not nativeOpenFailed then
        local id = settingsCategory.GetID and settingsCategory:GetID() or settingsCategory.ID or settingsCategory
        pcall(Settings.OpenToCategory, id)
        if PageOpen() then return end
        nativeOpenFailed = true
        Log("Settings.OpenToCategory did not show the page; using the window")
    end
    if not EnsureContent() then return end
    if not window then
        local ok, made = pcall(BuildWindow)
        if not ok then
            Print("the options window could not be built: " .. tostring(made))
            return
        end
        window = made
    end
    window:Show()
end

-- A canvas page only: proxy settings tainted Blizzard's UI on WoW Forever.
local function RegisterOptionsPage()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local page = CreateFrame("Frame")
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Forager")
    page:SetScript("OnShow", function(self)
        if not EnsureContent() then return end
        if window and window:IsShown() then window:Hide() end
        local w, h = self:GetWidth() or 0, self:GetHeight() or 0
        local scale = 1
        if w > 0 and h > 0 then scale = math.min(1, (w - 12) / W, (h - 50) / CONTENT_H) end
        Host(self, 6, -42, scale)
    end)
    local category = Settings.RegisterCanvasLayoutCategory(page, "Forager")
    if category then
        Settings.RegisterAddOnCategory(category)
        settingsPage, settingsCategory = page, category
    end
end

---------------------------------------------------------------------------
-- Minimap button: left-click opens Options > AddOns > Forager, right-click
-- pauses / resumes, drag to move
---------------------------------------------------------------------------

local mmButton, mmIcon

local function PlaceMinimapButton()
    local angle = math.rad(db.minimapAngle or 225)
    local radius = (Minimap:GetWidth() or 140) / 2 + 6
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

Toggle = function(on)
    if on == nil then on = not db.enabled end
    db.enabled = on and true or false
    if on then lastSwitch = GetTime() end
    Print(db.enabled and "resumed" or "paused")
    UpdateMinimapButton()
    UpdateBar()
    RefreshOptions()
end

UpdateMinimapButton = function()
    if not Minimap then return end
    if not mmButton then
        if not db.minimap then return end
        mmButton = CreateFrame("Button", "ForagerMinimapButton", Minimap)
        mmButton:SetSize(31, 31)
        mmButton:SetFrameStrata("MEDIUM")
        mmButton:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
        mmButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        mmButton:RegisterForDrag("LeftButton")
        mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

        local bg = mmButton:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(20, 20)
        bg:SetPoint("TOPLEFT", 7, -5)
        bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

        mmIcon = mmButton:CreateTexture(nil, "ARTWORK")
        mmIcon:SetSize(18, 18)
        mmIcon:SetPoint("TOPLEFT", 7, -6)
        mmIcon:SetTexture(ICON)
        mmIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local border = mmButton:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

        mmButton:SetScript("OnClick", function(_, button)
            if button == "RightButton" then Toggle() else ToggleOptions() end
        end)
        mmButton:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local scale = Minimap:GetEffectiveScale()
                local cx, cy = GetCursorPosition()
                if not (mx and my and cx and cy) then return end
                db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
                PlaceMinimapButton()
            end)
        end)
        mmButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        mmButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Forager " .. (db.enabled and "|cff40ff40running|r" or "|cffff4040paused|r"), 1, 1, 1)
            GameTooltip:AddLine(StatusText(), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click: options", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Right-click: pause / resume", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Drag: move around the minimap", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        mmButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local s = Scan()
    local on = s.active and s.byKey[s.active]
    mmIcon:SetTexture(db.minimapShowsTracker and on and on.texture or ICON)
    mmIcon:SetDesaturated(not db.enabled)
    mmButton:SetShown(db.minimap and true or false)
    PlaceMinimapButton()
end

---------------------------------------------------------------------------
-- Key bindings (Bindings.xml) and slash commands
---------------------------------------------------------------------------

-- A key press may always switch tracking, whatever the timer is allowed.
BINDING_HEADER_FORAGER = "Forager"
BINDING_NAME_FORAGER_TOGGLE = "Pause / resume"
BINDING_NAME_FORAGER_SWITCH = "Switch to the next tracker"
BINDING_NAME_FORAGER_OPTIONS = "Open options"
function Forager_Toggle() Toggle() end
function Forager_SwitchNow()
    local s = Scan()
    local e = NextEntry(s)
    if e then SwitchTo(e.key, "binding")
    else Print("tick at least two trackers to rotate.") end
end
function Forager_Options() ToggleOptions() end

SLASH_FORAGER1 = "/forager"
SlashCmdList.FORAGER = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        ToggleOptions()
    elseif cmd == "on" or cmd == "off" then
        Toggle(cmd == "on")
    elseif cmd == "toggle" then
        Toggle()
    elseif cmd == "delay" then
        local n = tonumber(arg)
        if n and n >= 1 then
            db.delay = math.floor(n + 0.5)
            Print("switching every " .. db.delay .. " s")
            RefreshOptions()
        else
            Print("usage: /forager delay <seconds>")
        end
    elseif cmd == "reset" then
        ResetBarPosition()
        Print("tracker icons moved back to the middle of the screen")
    elseif cmd == "minimap" or cmd == "icons" then
        local key = cmd == "minimap" and "minimap" or "bar"
        db[key] = not db[key]
        UpdateMinimapButton()
        UpdateBar()
        RefreshOptions()
        Print((cmd == "minimap" and "minimap button " or "tracker icons ") .. (db[key] and "shown" or "hidden"))
    elseif cmd == "switch" then
        Forager_SwitchNow()
    elseif cmd == "move" then
        local name, way = arg:match("^(.-)%s+(%a+)$")
        local dir = way == "up" and -1 or way == "down" and 1 or nil
        local found
        if name and dir then
            for _, e in ipairs(Scan().list) do
                if e.name:lower():find(name, 1, true) then found = e break end
            end
        end
        if not found then
            Print("usage: /forager move <tracker name> up|down")
        elseif MoveTracker(found.key, dir) then
            UpdateBar()
            RefreshOptions()
            local names = {}
            for _, e in ipairs(Scan().list) do names[#names + 1] = e.name end
            Print("order: " .. table.concat(names, ", "))
        else
            Print(found.name .. " is already at the " .. (dir < 0 and "top" or "bottom") .. ".")
        end
    elseif cmd == "retest" then
        db.method = nil
        silentFails = 0
        Log("method reset by /forager retest")
        Print("trying the timer again")
    elseif cmd == "debug" then
        local s = Scan()
        Print(StatusText():gsub("\n", " | "))
        local known = {}
        for _, e in ipairs(s.list) do
            known[#known + 1] = e.name .. "=" .. tostring(e.key) .. (InRotation(e.key) and "*" or "")
        end
        Print("trackers (* rotates): " .. (#known > 0 and table.concat(known, ", ") or "none"))
        Print(string.format("active=%s other=%s method=%s keys=%s",
            tostring(s.active), tostring(s.other), tostring(db.method), tostring(keysReady)))
    else
        Print("/forager (options), on, off, toggle, switch, delay <seconds>, move <tracker> up|down, icons, minimap, reset, retest, debug")
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MINIMAP_UPDATE_TRACKING")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ForagerDB = ForagerDB or {}
        db = ForagerDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        db.rotation = db.rotation or { [HERBS] = true, [MINERALS] = true }
        db.order = db.order or {}
        db.lastTracked = db.lastTracked or {}
        -- Sound left muted by a reload in the middle of a switch.
        if db.unmuteSFX then Unmute() end
        db.barPoint = nil -- 1.1.0 kept the position in another form
        ForagerLog = ForagerLog or {}
        ForagerLog.lines = ForagerLog.lines or {}
        ForagerLog.session = (ForagerLog.session or 0) + 1
    elseif event == "PLAYER_LOGIN" then
        lastSwitch = GetTime()
        local s = Scan()
        lastActive = s.active
        RememberTracker(s.active)
        local known = {}
        for _, e in ipairs(s.list) do
            known[#known + 1] = e.name .. "=" .. tostring(e.key) .. (InRotation(e.key) and "*" or "")
        end
        Log(string.format("login: trackers %s; active=%s method=%s delay=%s enabled=%s",
            table.concat(known, ", "), tostring(s.active), tostring(db.method), tostring(db.delay), tostring(db.enabled)))
        RegisterOptionsPage()
        UpdateMinimapButton()
        UpdateBar()
        SetUpKeys()
        C_Timer.NewTicker(0.25, function()
            -- The tracking event can come before the new tracker reads as on,
            -- so the change is also looked for here; the countdown starts
            -- when the switch has really happened.
            OnTrackingChanged()
            TryRestore()
            UpdateSituation()
            if mutedAt and GetTime() - mutedAt > 2 then Unmute() end
            if db.method == nil or db.method == "timer" then TrySwitch("timer") end
            UpdateBar()
        end)
    elseif event == "MINIMAP_UPDATE_TRACKING" then
        OnTrackingChanged()
    elseif event == "PLAYER_REGEN_ENABLED" then
        SetUpKeys()
    elseif event == "UI_ERROR_MESSAGE" then
        OnGameError(arg2)
    elseif event == "LOOT_OPENED" then
        looting = true
    elseif event == "LOOT_CLOSED" then
        looting = false
    elseif event == "UPDATE_BINDINGS" then
        if RefreshOptions then RefreshOptions() end
    elseif event == "PLAYER_LOGOUT" then
        Unmute()
    elseif event == "PLAYER_DEAD" then
        deathAt, aliveAt = GetTime(), nil
        Log("died; tracker to restore: " .. tostring(db.lastTracked[UnitGUID("player") or ""]))
    else
        OnRefused(event, arg1)
    end
end)
