-- Forager: rotates through your tracking spells (Find Herbs and Find Minerals
-- by default, any others you tick) on a set delay while you are out of combat.
--
-- The switch goes through C_Minimap.SetTracking, the call Blizzard's own
-- tracking menu makes. Classic clients have at times refused it from a timer
-- and only allowed it inside a key press or click. Forager first tries the
-- timer; if the game blocks that, it remembers and from then on makes each
-- switch on your next key press after the delay, leaving ability keys alone.

local ADDON, ns = ...
-- Lines for /forager debug from Styles.lua (the "skin" state and any errors).
ns.report = {}

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
    swapHunterPvP = true,
    showAllTracks = true,  -- a row of icons for every track, not just the current one
    trackAlign = "start",  -- rows line up on the left (columns at the top), "center" or "end"
    trackGap = 12,         -- space between the tracks' rows (or columns), in pixels
    tracksApart = false,   -- each track's row moves on its own, saved per track  -- hunter in a battleground or arena: Track Humanoids
    style = "auto",        -- window style: "auto", "blizzard" or "dark" (Styles.lua)
    darkAlpha = 0.92,      -- the Dark style's background opacity
    sparkles = true,       -- sparkles round the active tracker's border
    sparkleSize = 100,     -- percent: how far out they reach
    sparkleIntensity = 100, -- percent: how strong they are
    iconShape = "auto",    -- tracker icons: "auto" (square while a style is drawn), "round" or "square"
    -- method: nil = not learned yet, "timer", "key", "none"
    -- rotation: { [spellID] = true } for the trackers that take part
    -- lastTracked: { [player GUID] = key or false } for restoring after death
    -- order: { spellID, ... } the order you set; trackers missing from it
    --        follow in the tracking menu's order
}

local db
function ns.DB() return db end
local lastSwitch = 0  -- GetTime() of the last change of tracking spell
local lastActive       -- key of the tracking spell last seen on
local attempt          -- the switch waiting to be confirmed
local silentFails = 0
local failing = {}     -- [key] = GetTime() until which a tracker that failed to cast is skipped
local looting = false  -- the loot window is open
local override         -- { key, name, why, before } while a situation calls for a tracker
local ownedKey         -- a situational tracker Forager put on, which the rotation may replace
local currentKey       -- the rotation tracker Forager last switched to, while it is on
local placedKey        -- any tracker Forager last turned on (so it is never "your own pick")
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

ns.Log = Log

local function Print(msg)
    print("|cff7fd96aForager|r: " .. msg)
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------

local function InRotation(key)
    return db.rotation[key] == true
end

-- Left out of the rotation for now by a right-click on its icon. It stays on
-- the icons, greyed, and a left-click still turns it on.
local function Skipped(key)
    return db.skipped[key] == true
end

-- Tracks: named sets of ticked and left-out trackers to switch between, for
-- example one for gathering and one for hunting. db.rotation and db.skipped
-- always point at the current track's own tables.
local function SelectTrack(i)
    i = math.max(1, math.min(i or 1, #db.tracks))
    local t = db.tracks[i]
    t.rotation = t.rotation or {}
    t.skipped = t.skipped or {}
    t.name = t.name or ("Track " .. i)
    db.track = i
    db.rotation, db.skipped = t.rotation, t.skipped
    return t
end

-- Ticked in any track, not only the current one.
local function InAnyTrack(key)
    for _, t in ipairs(db.tracks) do
        if t.rotation and t.rotation[key] then return true end
    end
    return false
end

local function TrackName()
    return db.tracks[db.track].name
end

-- Trackers that stay on alongside the others instead of replacing them. On
-- WoW Forever, Find Treasure (the dwarf racial) runs next to hunter tracking
-- and Find Herbs or Find Minerals. Ticked, it is kept on rather than rotated.
local ALONGSIDE = { [2481] = true }
local ALONGSIDE_NAMES = { ["Find Treasure"] = true }

local function Alongside(e)
    return ALONGSIDE[e.key] or ALONGSIDE_NAMES[e.name] or false
end

-- Every tracking spell the character has, in the tracking menu's order.
--   s.list     { key, index, name, texture, active, alongside } per spell
--   s.byKey    the same, by key (the spell ID, or the name when there is none)
--   s.on       [key] = true for every tracker that is on (more than one can be)
--   s.shown    the ticked ones that take turns, left-out ones included (the icons)
--   s.rotation the ticked ones that take turns, without the left-out ones
--   s.keepShown the ticked ones that stay on alongside, left-out ones included
--   s.keep     the ticked ones that stay on alongside the rotation
--   s.active   key of the rotation's tracker that is on: the one Forager last
--              switched to while it is still on, else the first on in the list
--   s.other    name of a tracker that is on, not ticked, and not one that
--              stays on alongside the others (your own pick)
local function Scan()
    local s = { list = {}, byKey = {}, on = {}, shown = {}, rotation = {}, keepShown = {}, keep = {} }
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
                e.alongside = Alongside(e)
                s.list[#s.list + 1] = e
                s.byKey[key] = e
                if e.active then s.on[key] = true end
            end
        end
    end
    local rank = {}
    for i, key in ipairs(db.order) do rank[key] = i end
    for _, e in ipairs(s.list) do e.rank = rank[e.key] or (100000 + e.index) end
    table.sort(s.list, function(a, b) return a.rank < b.rank end)
    for _, e in ipairs(s.list) do
        e.skipped = Skipped(e.key)
        if InRotation(e.key) then
            if e.alongside then
                s.keepShown[#s.keepShown + 1] = e
                if not e.skipped then s.keep[#s.keep + 1] = e end
            else
                s.shown[#s.shown + 1] = e
                if not e.skipped then s.rotation[#s.rotation + 1] = e end
            end
        end
    end
    -- Which tracker the rotation is on. When several are on at once, the one
    -- Forager switched to last wins; reading "the last one on in the menu"
    -- left the rotation stuck on a tracker that stays on (Find Treasure).
    if currentKey and s.on[currentKey] and InRotation(currentKey) then
        s.active = currentKey
    else
        for _, e in ipairs(s.rotation) do
            if e.active then s.active = e.key break end
        end
    end
    if not s.active then
        for _, e in ipairs(s.list) do
            if e.active and not e.alongside then
                s.active = e.key
                -- Your own pick only if no track of yours has it: a tracker left on by
                -- another track (even from before a reload) is fair game.
                if not InAnyTrack(e.key) then s.other = e.name end
                break
            end
        end
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
    if #s.list == 0 then return "this character knows no tracking spells" end
    if #s.rotation == 0 then
        if #s.shown > 0 then return "every tracker is left out (right-click an icon to put it back)" end
        return "tick the trackers to rotate in the options"
    end
    if s.other and s.active ~= ownedKey and s.active ~= placedKey then
        return s.other .. " is on, and it isn't in the rotation"
    end
    local nextEntry = NextEntry(s)
    if not nextEntry then
        if #s.rotation == 1 then return s.rotation[1].name .. " is the only one in the rotation" end
        return "the other trackers can't be cast right now"
    end
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
    if mutedAt and not s.on[a.target] then Unmute() end
    if s.on[a.target] then
        placedKey = a.target
        if InRotation(a.target) and not (s.byKey[a.target] and s.byKey[a.target].alongside) then
            currentKey = a.target
        end
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
    -- A click or a key press of your own keeps the switch's sound, as feedback.
    if source ~= "click" and source ~= "binding" then Mute() end
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

-- Switches to another track. A tracker that is on and in the new track keeps
-- its turn; otherwise the new track takes over at once.
local function UseTrack(i, quiet)
    SelectTrack(i)
    currentKey = nil
    local s = Scan()
    -- Whatever the old track left on is the new track's to replace.
    if s.active then placedKey = s.active end
    if not (s.active and InRotation(s.active) and not Skipped(s.active)) then lastSwitch = 0 end
    Log("track: " .. TrackName())
    if not quiet then Print("track: " .. TrackName()) end
    if UpdateBar then UpdateBar() end
    if RefreshOptions then RefreshOptions() end
end

local function CycleTrack(dir)
    local n = #db.tracks
    if n < 2 then
        Print("there is only one track. Add another in the options.")
        return
    end
    UseTrack((db.track - 1 + dir) % n + 1)
end

local function NewTrack(name)
    db.tracks[#db.tracks + 1] = { name = name or ("Track " .. (#db.tracks + 1)), rotation = {}, skipped = {} }
    UseTrack(#db.tracks, true)
    Print("new track \"" .. TrackName() .. "\": tick its trackers in the options.")
end

local function DeleteTrack()
    if #db.tracks < 2 then return end
    local gone = TrackName()
    table.remove(db.tracks, db.track)
    UseTrack(math.min(db.track, #db.tracks), true)
    Print("deleted track \"" .. gone .. "\". Now on \"" .. TrackName() .. "\".")
end

local function RenameTrack(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if text == "" or text == TrackName() then return end
    db.tracks[db.track].name = text
    Log("track renamed " .. text)
    if UpdateBar then UpdateBar() end
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
    local key = db.lastTracked[UnitGUID("player") or ""]
    if not db.restoreAfterDeath or (key and s.on[key]) or (not key and s.active) or GetTime() - aliveAt > 30 then
        deathAt, aliveAt = nil, nil
        return
    end
    if InCombatLockdown() or UnitAffectingCombat("player") or UnitOnTaxi("player") then return end
    if Momentary(s) or (attempt and not attempt.done) then return end
    local e = key and s.byKey[key]
    if not e then
        deathAt, aliveAt = nil, nil
        return
    end
    Log("restoring " .. e.name .. " after death")
    Cast(e, "restore")
end

-- Ticked trackers that stay on alongside the rotation (Find Treasure) are
-- put back whenever they are off, while Forager is running.
local function KeepOn()
    if not db.enabled or override then return end
    if InCombatLockdown() or UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
    if attempt and not attempt.done then return end
    local s = Scan()
    if Momentary(s) then return end
    for _, e in ipairs(s.keep) do
        if not s.on[e.key] and not ((failing[e.key] or 0) > GetTime()) and not OnCooldown(e.key) then
            Log("keeping " .. e.name .. " on")
            Cast(e, "keep")
            return
        end
    end
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
        if s.on[e.key] then return end
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
    local s = Scan()
    if attempt and not attempt.done and s.on[attempt.target] then
        placedKey = attempt.target
        if InRotation(attempt.target) and s.byKey[attempt.target] and not s.byKey[attempt.target].alongside then
            currentKey = attempt.target
            s = Scan()
        end
    end
    local active = s.active
    if mutedAt and attempt and s.on[attempt.target] then C_Timer.After(0.3, Unmute) end
    if active ~= lastActive then
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
    local names, out = {}, {}
    for _, e in ipairs(s.rotation) do names[#names + 1] = e.name end
    for _, e in ipairs(s.shown) do if e.skipped then out[#out + 1] = e.name end end
    local lines = {
        "Tracking: |cffffffff" .. (s.active and NameOf(s, s.active) or "nothing") .. "|r"
            .. (function()
                local extra = {}
                for _, e in ipairs(s.list) do
                    if e.active and e.alongside then extra[#extra + 1] = e.name end
                end
                return #extra > 0 and (", plus |cffffffff" .. table.concat(extra, ", ") .. "|r") or ""
            end)(),
        "Rotating: |cffffffff" .. (#names > 0 and table.concat(names, ", ") or "nothing") .. "|r",
        "Switches " .. MethodText(),
    }
    if #out > 0 then table.insert(lines, 3, "Left out: |cff9d9d9d" .. table.concat(out, ", ") .. "|r") end
    if #db.tracks > 1 then table.insert(lines, 1, "Track: |cffffffff" .. TrackName() .. "|r") end
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
ns.ICON_SIZE = SIZE
local bar, pauseButton
local trackButtons = {}   -- every tracker button in every row (the skins walk them)
ns.trackButtons = trackButtons
local slots = {}          -- one row of icons per track on show
local barViews, barLayoutKey = {}, nil -- what each row holds, and the layout last drawn
ns.pauseButtons = {}      -- the play / stop button of every row
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
        button.fgMask = mask
        button.fgRound = { 0, 1, 0, 1 } -- the crop, for a window style that squares the icon
    else
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        button.fgRound = { 0.07, 0.93, 0.07, 0.93 }
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
        -- The action bar art, for a window style that squares the icon.
        button.fgFrame, button.fgPushed, button.fgHighlight = border, pushed, hl
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
    if s.on[key] then
        if InRotation(key) then currentKey = key end
        return
    end
    if InCombatLockdown() then Print("tracking can't be switched in combat.") return end
    local e = s.byKey[key]
    if not e then Print("this character doesn't know that tracking spell.") return end
    Cast(e, source or "click")
end

-- The position is the bar's center in UIParent units, so changing the icon
-- size grows the bar about its center.
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

-- Lays out every row on show: its track's name, its tracker buttons and its
-- play / stop button. Rows stack downward, or sit side by side when the icons
-- are stacked vertically. One track alone looks as it always did.
-- Every track's row moves on its own (with more than one row on show).
local function RowsApart()
    return db.tracksApart and db.showAllTracks and #db.tracks > 1
end

-- A row dragged on its own keeps its center, in UIParent units like the bar's.
local function SaveRowPosition(slot)
    local t = db.tracks[slot.track]
    if not t then return end
    local x, y = slot.row:GetCenter()
    if not x then return end
    local scale = bar:GetScale()
    t.pos = { x * scale, y * scale }
end

local function LayoutBar()
    if not bar then return end
    bar:SetScale((db.barScale or 100) / 100)
    local views = barViews
    local named = #db.tracks > 1
    local LH = named and 16 or 0
    local gap = db.trackGap or 12
    local align = db.trackAlign or "start"
    -- First the size of every row, then the bar's size, then where each row
    -- goes: rows of different lengths line up on one side (top or bottom
    -- for columns).
    local longs, across, down, count = {}, 0, 0, 0
    for j in ipairs(slots) do
        local v = views[j]
        if v then
            count = count + 1
            local long = SIZE * (v.count + 1) + GAP * v.count
            longs[j] = long
            if db.barVertical then
                across = across + SIZE + (count > 1 and gap or 0)
                down = math.max(down, long + LH)
            else
                down = down + SIZE + LH + (count > 1 and gap or 0)
                across = math.max(across, long)
            end
        end
    end
    bar:SetSize(math.max(across, SIZE), math.max(down, SIZE))

    -- How far a row of length `long` sits from the line-up side's start.
    local room = db.barVertical and (math.max(down, SIZE) - LH) or math.max(across, SIZE)
    local function Shift(long)
        if align == "end" then return room - long end
        if align == "center" then return (room - long) / 2 end
        return 0
    end
    local at = 0
    for j, slot in ipairs(slots) do
        local v = views[j]
        slot.row:SetShown(v ~= nil)
        if v then
            local n, long = v.count, longs[j]
            slot.row:ClearAllPoints()
            slot.label:ClearAllPoints()
            local own = RowsApart() and db.tracks[slot.track] and db.tracks[slot.track].pos
            if db.barVertical then
                slot.row:SetSize(SIZE, long)
                slot.row:SetPoint("TOPLEFT", bar, "TOPLEFT", at, -(LH + Shift(long)))
                slot.label:SetPoint("BOTTOMLEFT", slot.row, "TOPLEFT", 0, 3)
                at = at + SIZE + gap
            else
                slot.row:SetSize(long, SIZE)
                slot.row:SetPoint("TOPLEFT", bar, "TOPLEFT", Shift(long), -(at + LH))
                -- The name sits over the row's lined-up side.
                if align == "end" and not own then slot.label:SetPoint("BOTTOMRIGHT", slot.row, "TOPRIGHT", 0, 3)
                elseif align == "center" and not own then slot.label:SetPoint("BOTTOM", slot.row, "TOP", 0, 3)
                else slot.label:SetPoint("BOTTOMLEFT", slot.row, "TOPLEFT", 0, 3) end
                at = at + SIZE + LH + gap
            end
            -- Moved on its own: the row goes where it was left. Until it is
            -- dragged, it stays where the joined layout put it.
            if own then
                local scale = bar:GetScale()
                slot.row:ClearAllPoints()
                slot.row:SetPoint("CENTER", UIParent, "BOTTOMLEFT", own[1] / scale, own[2] / scale)
            end
            local function Put(b, i)
                local offset = (i - 1) * (SIZE + GAP)
                b:ClearAllPoints()
                if db.barVertical then b:SetPoint("TOP", slot.row, "TOP", 0, -offset)
                else b:SetPoint("LEFT", slot.row, "LEFT", offset, 0) end
            end
            for i, b in ipairs(slot.buttons) do
                b:SetShown(i <= n)
                if i <= n then Put(b, i) end
            end
            Put(slot.pause, n + 1)
            slot.label:SetShown(named)
        end
    end
    PlaceBar()
end

local function ResetBarPosition()
    db.barPos = nil
    for _, t in ipairs(db.tracks) do t.pos = nil end
    if bar then LayoutBar() end
end

-- Dragging moves the whole bar, or only this button's row when the tracks'
-- rows move apart.
local function Draggable(button, slot)
    local moving
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        if db.barLocked then return end
        moving = (slot and RowsApart()) and slot.row or bar
        moving:StartMoving()
    end)
    button:SetScript("OnDragStop", function()
        if not moving then return end
        moving:StopMovingOrSizing()
        if moving == bar then SaveBarPosition() else SaveRowPosition(slot) LayoutBar() end
        moving = nil
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

-- Right-click on a tracker's icon: leave it out of the rotation for now, or
-- put it back.
local function ToggleSkip(key, trackIndex)
    if not key then return end
    local t = db.tracks[trackIndex or db.track] or db.tracks[db.track]
    t.skipped[key] = (not t.skipped[key]) or nil
    local s = Scan()
    Log(NameOf(s, key) .. (t.skipped[key] and " left out of " or " put back in ") .. t.name)
    UpdateBar()
    if RefreshOptions then RefreshOptions() end
end

-- The trackers a track shows, in the list's order, the ones kept on
-- alongside the rotation last.
local function TrackEntries(s, t)
    local list, keep = {}, {}
    for _, e in ipairs(s.list) do
        if t.rotation[e.key] then
            if e.alongside then keep[#keep + 1] = e else list[#list + 1] = e end
        end
    end
    for _, e in ipairs(keep) do list[#list + 1] = e end
    return list
end

local function SlotTrack(slot)
    return db.tracks[slot.track] or db.tracks[db.track]
end

local function ManyRows()
    return db.showAllTracks and #db.tracks > 1
end

local function TrackButton(slot, i)
    if slot.buttons[i] then return slot.buttons[i] end
    local name = slot.index == 1 and ("ForagerTrackButton" .. i) or ("ForagerSlot" .. slot.index .. "Button" .. i)
    local b = CreateFrame("Button", name, slot.row)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = DressIcon(b)
    b.glow, b.anim = MakeGlow(b)
    -- The swipe that ticks down to the next switch, inside the icon's frame.
    -- Made from the game's CooldownFrameTemplate, whose own swipe is a plain
    -- color filling the whole frame (a bare Cooldown has none), so a look can
    -- go back to it. The template pins itself to every edge of its parent;
    -- its points are cleared before setting ours.
    local okCd, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd = okCd and cd or CreateFrame("Cooldown", nil, b)
    b.cd:ClearAllPoints()
    -- 2 px in at the top and left, 3 at the right and 2.5 at the bottom, fitted
    -- in game: an even 2 px overhung the frame there, 4 left a gap.
    b.cd:SetPoint("TOPLEFT", 2, -2)
    b.cd:SetPoint("BOTTOMRIGHT", -3, 2.5)
    -- The template's color swipe, darker, as the game's own action buttons use
    -- it. (The Cooldown Manager's swipe art left the left side of the icon
    -- unswept on this client.) A bare Cooldown, which has no color swipe, gets
    -- that art instead, since it draws nothing without a texture.
    if okCd then
        pcall(b.cd.SetSwipeColor, b.cd, 0, 0, 0, 0.75)
        b.cd.fgSweep = "color"
    else
        pcall(b.cd.SetSwipeTexture, b.cd, SWIPE_FILE, 0, 0, 0, 0.75)
        b.cd.fgSweep = SWIPE_FILE
    end
    pcall(b.cd.SetDrawEdge, b.cd, false)
    pcall(b.cd.SetDrawBling, b.cd, false)
    pcall(b.cd.SetHideCountdownNumbers, b.cd, true)
    b.cd:Hide()
    -- The seconds, on a layer above the swipe.
    b.textLayer = CreateFrame("Frame", nil, b)
    b.textLayer:SetAllPoints()
    b.textLayer:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.count = b.textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    b.count:SetPoint("CENTER")
    -- Left-click turns the tracker on, whichever row it is in; right-click
    -- leaves it out of that row's track, or puts it back.
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then ToggleSkip(self.key, slot.track) elseif self.key then SwitchTo(self.key) end
    end)
    Draggable(b, slot)
    Tooltip(b, function(self)
        local s = Scan()
        local t = SlotTrack(slot)
        local out = t.skipped[self.key] == true
        local lines = { NameOf(s, self.key) }
        if s.on[self.key] then lines[#lines + 1] = "|cff7fd96aOn now|r" end
        if out then lines[#lines + 1] = "|cff9d9d9dLeft out of the rotation|r" end
        if ManyRows() then lines[#lines + 1] = "Track: " .. t.name end
        if not s.on[self.key] then lines[#lines + 1] = "Left-click: track this now" end
        lines[#lines + 1] = out and "Right-click: put it back in the rotation" or "Right-click: leave it out of the rotation"
        if not db.barLocked then lines[#lines + 1] = "Drag: move" end
        return lines
    end)
    slot.buttons[i] = b
    trackButtons[#trackButtons + 1] = b
    if ns.ShapeIcon then ns.ShapeIcon(b) end
    return b
end

-- A row's play / stop button. Play runs that row's track and stops the one
-- that was running, so only one track runs at a time; stop pauses it.
local function RunSlot(slot)
    if slot.track == db.track then
        Toggle()
        return
    end
    UseTrack(slot.track, true)
    db.enabled = true
    Print(TrackName() .. " is running")
    UpdateMinimapButton()
    UpdateBar()
    if RefreshOptions then RefreshOptions() end
end

local function PauseButtonFor(slot)
    local j = slot.index
    local p = CreateFrame("Button", j == 1 and "ForagerPauseButton" or ("ForagerSlot" .. j .. "Pause"), slot.row)
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
        if button == "RightButton" then SlashCmdList.FORAGER("") else RunSlot(slot) end
    end)
    Draggable(p, slot)
    Tooltip(p, function()
        local key = GetBindingKey("FORAGER_TOGGLE")
        local running = slot.track == db.track and db.enabled
        local title
        if ManyRows() then
            title = (running and "Pause " or "Run ") .. SlotTrack(slot).name
        else
            title = db.enabled and "Pause Forager" or "Resume Forager"
        end
        local lines = { title }
        if ManyRows() and not running and db.enabled then lines[#lines + 1] = "Stops " .. TrackName() .. ": one track runs at a time." end
        lines[#lines + 1] = StatusText()
        lines[#lines + 1] = key and ("Key: " .. ((GetBindingText and GetBindingText(key)) or key)) or "Set a key in the options"
        lines[#lines + 1] = MoveHint()
        return lines
    end)
    ns.pauseButtons[#ns.pauseButtons + 1] = p
    if j == 1 then
        pauseButton = p
        ns.pauseButton = p
    end
    if ns.SkinPauseButton then ns.SkinPauseButton(p) end
    return p
end

-- A row's name: with every track on show, a click makes that track the
-- current one; with only the current track on show, it steps through them.
local function LabelFor(slot)
    local j = slot.index
    local label = CreateFrame("Button", j == 1 and "ForagerTrackLabel" or ("ForagerSlot" .. j .. "Label"), slot.row)
    label:SetSize(120, 14)
    label:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    label.text = label:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label.text:SetPoint("LEFT")
    label.text:SetJustifyH("LEFT")
    if label.text.SetWordWrap then label.text:SetWordWrap(false) end
    label:SetScript("OnClick", function(_, button)
        if ManyRows() then
            if slot.track ~= db.track then UseTrack(slot.track) end
        else
            CycleTrack(button == "RightButton" and -1 or 1)
        end
    end)
    Draggable(label, slot)
    Tooltip(label, function()
        if ManyRows() then
            local t = SlotTrack(slot)
            if slot.track == db.track then
                return { "Track: " .. t.name, db.enabled and "Running" or "Paused", "Its play button runs or pauses it." }
            end
            return { "Track: " .. t.name, "Left-click: make this the current track", "Its play button runs it and stops the one running." }
        end
        return { "Track: " .. TrackName(), "Left-click: next track", "Right-click: previous track" }
    end)
    label:Hide()
    return label
end

local function Slot(j)
    if slots[j] then return slots[j] end
    local slot = { index = j, buttons = {} }
    slot.row = CreateFrame("Frame", j == 1 and "ForagerRow1" or ("ForagerRow" .. j), bar)
    slot.row:SetMovable(true)
    slot.row:SetClampedToScreen(true)
    slot.label = LabelFor(slot)
    slot.pause = PauseButtonFor(slot)
    slots[j] = slot
    return slot
end

local function BuildBar()
    bar = CreateFrame("Frame", "ForagerBar", UIParent)
    ns.bar = bar
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    Slot(1)
    bar.trackLabel = slots[1].label
    LayoutBar()
end

UpdateBar = function()
    if not db then return end
    local s = Scan()
    local show = db.bar and #s.list > 0
    if db.barHideCombat and (InCombatLockdown() or UnitAffectingCombat("player")) then show = false end
    if not show then
        if bar then bar:Hide() end
        if ns.UpdateSparkles then ns.UpdateSparkles(nil) end
        return
    end
    if not bar then BuildBar() end
    bar:Show()

    -- Which tracks get a row: every one, or just the current one.
    local list = {}
    if ManyRows() then
        for i = 1, #db.tracks do list[i] = i end
    else
        list[1] = db.track
    end
    local views, shape = {}, {}
    for j, ti in ipairs(list) do
        local slot = Slot(j)
        slot.track = ti
        local entries = TrackEntries(s, db.tracks[ti])
        for i, e in ipairs(entries) do
            local b = TrackButton(slot, i)
            if b.key ~= e.key then
                b.key = e.key
                b.icon:SetTexture(e.texture or ICON)
            end
        end
        views[j] = { count = #entries }
        shape[#shape + 1] = #entries
    end
    barViews = views
    local layoutKey = table.concat(shape, ",") .. (db.barVertical and "v" or "h") .. #db.tracks
        .. (db.trackAlign or "start") .. (db.trackGap or 12) .. (RowsApart() and "apart" or "")
        .. table.concat(list, ",")
    if barLayoutKey ~= layoutKey then
        barLayoutKey = layoutKey
        LayoutBar()
    end

    local left = math.ceil(db.delay - (GetTime() - lastSwitch))
    -- Nothing counts down while a switch is still landing.
    local landing = attempt and not attempt.done and not s.on[attempt.target]
    local nextEntry = (db.enabled and left > 0 and not landing and not Blocker(s)) and NextEntry(s)
    local sparkleButton
    for j, ti in ipairs(list) do
        local slot = slots[j]
        local t = db.tracks[ti]
        local current = ti == db.track
        -- Only the current track's row is lit; the others wait, dimmed.
        slot.row:SetAlpha(current and 1 or 0.55)
        for i = 1, views[j].count do
            local b = slot.buttons[i]
            -- A tracker kept on alongside glows while it is on; a rotation one
            -- while it is the rotation's current tracker.
            local e = s.byKey[b.key]
            local on = false
            if current then
                if e and e.alongside then on = s.on[b.key] == true else on = s.active == b.key end
            end
            -- Left out of the rotation: greyed and dimmed, still clickable.
            local out = t.skipped[b.key] == true
            if b.out ~= out then
                b.out = out
                b.icon:SetDesaturated(out)
                b.icon:SetAlpha(out and 0.45 or 1)
            end
            if on ~= b.lit then
                b.lit = on
                -- Forager_Skins.lua fades the glow in and out, and swaps in a round
                -- one for round icons.
                if ns.GlowChanged then
                    ns.GlowChanged(b, on)
                else
                    b.glow:SetShown(on)
                    if on then b.anim:Play() else b.anim:Stop() end
                end
            end
            -- Seconds to the next switch, and a swipe ticking down, on the icon
            -- that comes next, in the current track's row.
            local isNext = current and nextEntry and nextEntry.key == b.key
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
            if on and b.key == s.active then sparkleButton = b end
        end

        -- The track's name, gold for the current track.
        local label = slot.label
        if #db.tracks > 1 then
            label.text:SetText(t.name)
            if current then label.text:SetTextColor(1, 0.82, 0) else label.text:SetTextColor(0.75, 0.75, 0.75) end
            if db.barVertical then
                label.text:SetWidth(SIZE + GAP * 2)
                label:SetWidth(SIZE + GAP * 2)
            else
                label.text:SetWidth(0)
                label:SetWidth(math.max(40, (label.text:GetStringWidth() or 0) + 6))
            end
        end

        -- Running: stop art pauses it. Otherwise play art runs it.
        local p = slot.pause
        local running = current and db.enabled
        p.icon:SetDesaturated(not running)
        p.stop:SetShown(running and p.stopArt ~= nil)
        p.play:SetShown(not running and p.playArt ~= nil)
        local art = running and p.stopArt or p.playArt
        p.text:SetText(art and "" or (running and "Pause" or "Go"))
    end

    -- Sparkles on the tracker that is on, while running and the option is on.
    if ns.UpdateSparkles then
        ns.UpdateSparkles((db.sparkles and db.enabled) and sparkleButton or nil)
    end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local optionRefreshers = {}
local content, window, settingsPage, settingsCategory
local nativeOpenFailed = false
local W, CONTENT_H = 680, 1040
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

-- factor: the slider shows db[key] * factor (a 0 to 1 setting as a percent).
local function OptionSlider(parent, label, key, minV, maxV, x, y, unit, step, after, factor)
    step = step or 1
    factor = factor or 1
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
    -- The mouse wheel scrolls the options page instead of stopping on the slider.
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta)
        local sc = ns.optionsScroll
        local handler = sc and sc:GetScript("OnMouseWheel")
        if handler then handler(sc, delta) end
    end)
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
        db[key] = v / factor
        if after then after() end
    end)
    optionRefreshers[#optionRefreshers + 1] = function()
        local shown = math.floor(db[key] * factor + 0.5)
        slider.syncing = true
        slider:SetValue(shown)
        slider.syncing = false
        value:SetText(shown .. unit)
    end
    return slider, caption, value
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

-- How the tracks' rows line up: left or right, or top or bottom when the
-- icons are stacked vertically. Left-click for the other side, right-click too.
local ALIGNS = { "start", "center", "end" }
local ALIGN_NAMES = {
    h = { start = "left", center = "centered", ["end"] = "right" },
    v = { start = "top", center = "centered", ["end"] = "bottom" },
}

local function AlignText()
    local names = ALIGN_NAMES[db.barVertical and "v" or "h"]
    local name = names[db.trackAlign] or names.start
    if db.barVertical then return "Columns: " .. name .. (name == "centered" and "" or " aligned") end
    return "Rows: " .. name .. (name == "centered" and "" or " aligned")
end

local function SetTrackAlign(value)
    db.trackAlign = (value == "end" or value == "center") and value or "start"
    UpdateBar()
    LayoutBar()
    RefreshOptions()
end

local function AlignButton(parent, x, y)
    local b = PanelButton(parent, "", x, y, 176, function(_, mouse)
        local i = 1
        for n, a in ipairs(ALIGNS) do if a == db.trackAlign then i = n end end
        i = (i - 1 + (mouse == "RightButton" and -1 or 1)) % #ALIGNS + 1
        SetTrackAlign(ALIGNS[i])
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Track alignment", 1, 1, 1)
        GameTooltip:AddLine("With the icons side by side, the tracks' rows line up on the left, in the center or on the right. Stacked vertically, the columns line up at the top, in the center or at the bottom.", nil, nil, nil, true)
        GameTooltip:AddLine("Left-click for the next, right-click for the previous.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    optionRefreshers[#optionRefreshers + 1] = function() b:SetText(AlignText()) end
    ns.alignButton = b
    return b
end

-- Which track the list below edits, with buttons to add and delete tracks
-- and a box to rename the one on show.
local function TrackSection(parent, x, y)
    local pick = TryCreate("Button", "ForagerTrackPick", parent, { "UIPanelButtonTemplate" })
    pick:SetSize(150, 22)
    pick:SetPoint("TOPLEFT", x + 2, y)
    pick:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pick:SetScript("OnClick", function(_, mouse) CycleTrack(mouse == "RightButton" and -1 or 1) end)
    pick:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Track: " .. TrackName(), 1, 1, 1)
        GameTooltip:AddLine("A track is a set of trackers to rotate. Switch tracks here, with the name above the icons, or with a key binding.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Left-click: next track   Right-click: previous", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    pick:SetScript("OnLeave", function() GameTooltip:Hide() end)

    PanelButton(parent, "New", x + 154, y, 60, function() NewTrack() end)
    local del = PanelButton(parent, "Delete", x + 218, y, 80, nil)
    local armedAt -- a second click within 3 s deletes, so one stray click can't
    del:SetScript("OnClick", function(self)
        if armedAt and GetTime() - armedAt < 3 then
            armedAt = nil
            DeleteTrack()
        else
            armedAt = GetTime()
            self:SetText("Sure?")
            C_Timer.After(3, function()
                if armedAt and GetTime() - armedAt >= 3 then
                    armedAt = nil
                    RefreshOptions()
                end
            end)
        end
    end)

    local nameLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", x + 4, y - 32)
    nameLabel:SetText("Name")
    -- No auto focus: an edit box with the focus takes every key press.
    local box = TryCreate("EditBox", "ForagerTrackName", parent, { "InputBoxTemplate" })
    box:SetSize(190, 20)
    box:SetPoint("TOPLEFT", x + 52, y - 28)
    box:SetAutoFocus(false)
    if box.SetMaxLetters then box:SetMaxLetters(30) end
    box:SetScript("OnEnterPressed", function(self) RenameTrack(self:GetText()) self:ClearFocus() RefreshOptions() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() RefreshOptions() end)
    box:SetScript("OnEditFocusLost", function(self) RenameTrack(self:GetText()) end)

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", x + 4, y - 56)
    hint:SetWidth(COL - 20)
    hint:SetJustifyH("LEFT")
    hint:SetText("Tick a tracker to put it on the icons. On the icons, right-click one to leave it out of the rotation for now, and again to put it back.")
    OptionCheck(parent, "Show every track's icons at once", "showAllTracks", x, y - 86, function() UpdateBar() end)
    AlignButton(parent, x, y - 118)
    OptionSlider(parent, "Gap between tracks", "trackGap", 0, 40, x, y - 150, " px", 1, function() LayoutBar() UpdateBar() end)
    OptionCheck(parent, "Move each track's row on its own", "tracksApart", x, y - 196, function()
        UpdateBar()
        LayoutBar()
        Print(db.tracksApart and "drag each track's row where you want it." or "the tracks' rows move together again.")
    end)

    optionRefreshers[#optionRefreshers + 1] = function()
        local n = #db.tracks
        pick:SetText(TrackName() .. (n > 1 and (" (" .. db.track .. "/" .. n .. ")") or ""))
        if not armedAt then del:SetText("Delete") end
        del:SetEnabled(n > 1)
        if not (box.HasFocus and box:HasFocus()) then box:SetText(TrackName()) end
    end
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
            row.label:SetText(e.name .. (e.alongside and "  |cff9d9d9d(kept on)|r" or "")
                .. (e.skipped and "  |cff9d9d9d(left out)|r" or "") .. (e.active and "  |cff7fd96a(on)|r" or ""))
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

-- The window style (Styles.lua does the choosing and the drawing) and the
-- Dark style's opacity, which is grayed out for the other styles.
local function LookSection(parent, x, y)
    local styleButton = PanelButton(parent, "", x, y, 200, function(_, button)
        if ns.Styles then ns.Styles.Cycle(button == "RightButton" and -1 or 1) end
        RefreshOptions()
    end)
    styleButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    styleButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Window style", 1, 1, 1)
        for _, line in ipairs(ns.Styles and ns.Styles.HELP or {}) do GameTooltip:AddLine(line, nil, nil, nil, true) end
        GameTooltip:AddLine("Left-click for the next style, right-click for the previous one.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    styleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", x + 4, y - 26)
    note:SetWidth(COL - 20)
    note:SetJustifyH("LEFT")
    local slider, caption, value = OptionSlider(parent, "Dark background opacity", "darkAlpha", 0, 100, x, y - 58, "%", 5,
        function() if ns.Styles then ns.Styles.SetDarkAlpha(db.darkAlpha) end end, 100)
    slider:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Dark background opacity", 1, 1, 1)
        GameTooltip:AddLine("How much of the world shows through the Dark style's window.", nil, nil, nil, true)
        if db.style ~= "dark" then GameTooltip:AddLine("Applies to the Dark style only.", 1, 0.82, 0, true) end
        GameTooltip:Show()
    end)
    slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    optionRefreshers[#optionRefreshers + 1] = function()
        local Styles = ns.Styles
        styleButton:SetText("Window style: " .. (Styles and Styles.Name(db.style) or "Blizzard"))
        note:SetText(Styles and Styles.Note() or "")
        local dark = db.style == "dark"
        slider:SetEnabled(dark)
        slider:SetAlpha(dark and 1 or 0.5)
        caption:SetFontObject(dark and GameFontHighlight or GameFontDisable)
        value:SetFontObject(dark and GameFontNormalSmall or GameFontDisable)
    end
    slider.fgCaption, slider.fgValue = caption, value
    ns.styleButton, ns.opacitySlider = styleButton, slider
end

-- Tracker icons round (the action bars' own art) or square, in any window
-- style. Automatic follows the style; the change shows at once.
local SHAPES = { "auto", "round", "square" }
local SHAPE_NAMES = { auto = "Automatic", round = "Round", square = "Square" }

local function SetIconShape(shape)
    db.iconShape = shape
    if ns.UpdateIconShapes then ns.UpdateIconShapes() end
    RefreshOptions()
end

local function ShapeButton(parent, x, y)
    local b = PanelButton(parent, "", x, y, 176, function(_, mouse)
        local i = 1
        for n, shape in ipairs(SHAPES) do if shape == db.iconShape then i = n end end
        i = (i - 1 + (mouse == "RightButton" and -1 or 1)) % #SHAPES + 1
        SetIconShape(SHAPES[i])
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Icon shape", 1, 1, 1)
        GameTooltip:AddLine("Automatic: square in the Dark and EllesmereUI styles, the action bars' look with Blizzard's.", nil, nil, nil, true)
        GameTooltip:AddLine("Round: circles, in a ring like the minimap buttons' with Blizzard's style, with a thin dark edge in the others.", nil, nil, nil, true)
        GameTooltip:AddLine("Square: cropped square icons with a thin edge.", nil, nil, nil, true)
        GameTooltip:AddLine("The pause button follows the window style.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Left-click for the next shape, right-click for the previous one.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    optionRefreshers[#optionRefreshers + 1] = function()
        b:SetText("Icon shape: " .. (SHAPE_NAMES[db.iconShape] or SHAPE_NAMES.auto))
    end
    ns.shapeButton = b
end

-- Which sparkle effect plays round the active tracker: left-click for the
-- next, right-click for the previous. Effects this client lacks are skipped.
local function EffectButton(parent, x, y)
    local b
    b = PanelButton(parent, "", x, y, 100, function(_, mouse)
        if not ns.SetSparkleEffect then return end
        ns.SetSparkleEffect(nil, mouse == "RightButton" and -1 or 1)
        RefreshOptions()
        -- The tooltip names the new effect while the pointer stays on the button.
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(b) then b:GetScript("OnEnter")(b) end
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sparkle effect", 1, 1, 1)
        if ns.SparkleEffect then
            local entry, index, count = ns.SparkleEffect()
            GameTooltip:AddLine(("%d of %d: %s"):format(index, count, entry.label), 1, 0.82, 0, true)
        end
        GameTooltip:AddLine("The spell effect that plays round the tracker that is on. Effects this client lacks are skipped.", nil, nil, nil, true)
        GameTooltip:AddLine("Left-click for the next effect, right-click for the previous one.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    optionRefreshers[#optionRefreshers + 1] = function()
        if not ns.SparkleEffect then b:SetText("Effect") return end
        local _, index, count = ns.SparkleEffect()
        b:SetText(("Effect %d/%d"):format(index, count))
    end
    ns.effectButton = b
end

-- Sparkle size (how far out they reach) and intensity (how strong), each a
-- percent, applied at once. Grayed while the sparkles are off.
local function SparkleSliders(parent, x, y)
    local function Apply() if ns.ApplySparkleLooks then ns.ApplySparkleLooks() end end
    local size, sizeCaption, sizeValue = OptionSlider(parent, "Sparkle size", "sparkleSize", 50, 200, x, y, "%", 5, Apply)
    local strength, strengthCaption, strengthValue = OptionSlider(parent, "Sparkle intensity", "sparkleIntensity", 0, 100, x, y - 44, "%", 5, Apply)
    size.fgCaption, size.fgValue = sizeCaption, sizeValue
    strength.fgCaption, strength.fgValue = strengthCaption, strengthValue
    optionRefreshers[#optionRefreshers + 1] = function()
        local on = db.sparkles and true or false
        for _, slider in ipairs({ size, strength }) do
            slider:SetEnabled(on)
            slider:SetAlpha(on and 1 or 0.5)
            slider.fgCaption:SetFontObject(on and GameFontHighlight or GameFontDisable)
            slider.fgValue:SetFontObject(on and GameFontNormalSmall or GameFontDisable)
        end
    end
    ns.sparkleSizeSlider, ns.sparkleIntensitySlider = size, strength
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

    -- Above the tracker list, whose length depends on the character.
    Header(c, "Look", LEFT, -300)
    LookSection(c, LEFT, -326)

    Header(c, "Tracks and trackers", LEFT, -450)
    TrackSection(c, LEFT, -476)
    TrackerList(c, LEFT, -706)

    -- Right column: the icons, the minimap button, then status.
    Header(c, "Tracker icons", RIGHT, -4)
    OptionCheck(c, "Show the tracker icons", "bar", RIGHT, -30, Refresh)
    OptionCheck(c, "Lock them in place", "barLocked", RIGHT, -56, Refresh)
    OptionCheck(c, "Stack them vertically", "barVertical", RIGHT, -82, function() LayoutBar() UpdateBar() RefreshOptions() end)
    OptionCheck(c, "Show the seconds to the next switch", "barCountdown", RIGHT, -108, Refresh)
    OptionCheck(c, "Swipe down to the next switch", "barSwipe", RIGHT, -134, Refresh)
    OptionCheck(c, "Hide them in combat", "barHideCombat", RIGHT, -160, Refresh)
    OptionCheck(c, "Sparkles on the active tracker", "sparkles", RIGHT, -186, function() Refresh() RefreshOptions() end)
    EffectButton(c, RIGHT + 212, -186)
    SparkleSliders(c, RIGHT, -218)
    OptionSlider(c, "Icon size", "barScale", 60, 200, RIGHT, -306, "%", 5, function() LayoutBar() end)
    PanelButton(c, "Reset position", RIGHT, -352, 130, ResetBarPosition)
    ShapeButton(c, RIGHT + 138, -352)

    Header(c, "Minimap", RIGHT, -390)
    OptionCheck(c, "Show the minimap button", "minimap", RIGHT, -416, function()
        UpdateMinimapButton()
        if not db.minimap then Print("minimap button hidden. /forager opens the options.") end
    end)
    OptionCheck(c, "Show the current tracker on it", "minimapShowsTracker", RIGHT, -442, function() UpdateMinimapButton() end)

    Header(c, "Swap for the situation", RIGHT, -480)
    OptionCheck(c, "Fishing pole equipped: Find Fish", "swapFishing", RIGHT, -506)
    OptionCheck(c, "Cat Form: Track Humanoids", "swapCatForm", RIGHT, -532)
    OptionCheck(c, "Hunter in a battleground: Track Humanoids", "swapHunterPvP", RIGHT, -558)

    Header(c, "Keys", RIGHT, -596)
    KeyCapture(c, RIGHT, -622)

    Header(c, "Status", RIGHT, -680)
    local status = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", RIGHT + 4, -708)
    status:SetWidth(COL - 20)
    status:SetJustifyH("LEFT")
    status:SetSpacing(3)
    optionRefreshers[#optionRefreshers + 1] = function() status:SetText(StatusText()) end
    PanelButton(c, "Try the timer again", RIGHT, -792, 160, function()
        db.method = nil
        silentFails = 0
        Log("method reset from options")
        RefreshOptions()
    end)
    local hint = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", RIGHT + 4, -826)
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
    ns.content = made
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
    -- Taller than some screens: the whole window shrinks to fit, as the
    -- Options page does.
    local screen = UIParent.GetHeight and UIParent:GetHeight()
    if type(screen) == "number" and screen > 0 then
        f:SetScale(math.min(1, (screen - 40) / (CONTENT_H - top + 10)))
    end
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
        f.fgClose = close
    end
    -- The template's own X goes through HideUIPanel, which this client refuses in combat
    -- ("Interface action blocked"), so every X hides the window itself.
    local close = f.CloseButton
    if type(close) ~= "table" then close = _G["ForagerOptionsCloseButton"] end
    if type(close) ~= "table" then close = f.fgClose end
    if type(close) == "table" and close.SetScript then close:SetScript("OnClick", function() f:Hide() end) end
    f:SetScript("OnShow", function(self) Host(self, 0, top) end)
    ns.window = f
    if ns.SkinWindow then ns.SkinWindow(f) end
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
    -- Hidden until the game's panel shows it. A frame made without a parent is shown (and counts
    -- as visible), so when the panel moved it into an already open window and called Show,
    -- OnShow never ran and the first visit from Esc > Options > AddOns found only the title.
    page:Hide()
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Forager")
    -- The options fill the page's width and scroll when they are taller than
    -- it. (Shrunk to fit the height, the tracks sections of 1.10 to 1.12 left
    -- them at half size in a corner of the page.)
    -- Built the way Shard Grid's page is, which scrolls well on this client: the
    -- modern ScrollFrameTemplate (the minimal scroll bar art draws here; the old
    -- template's arrow buttons use Interface\\Buttons art, which does not), the bar's
    -- range set by hand and the bar hidden when nothing needs scrolling, and the
    -- mouse wheel always scrolling the page.
    local scroll, template
    for _, tmpl in ipairs({ "ScrollFrameTemplate", "UIPanelScrollFrameTemplate" }) do
        local ok, made = pcall(CreateFrame, "ScrollFrame", "ForagerOptionsScroll", page, tmpl)
        if ok and made then scroll, template = made, tmpl break end
    end
    if not scroll then scroll = CreateFrame("ScrollFrame", "ForagerOptionsScroll", page) end
    ns.report["options scroll"] = template or "plain (mouse wheel only)"
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -42)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -22, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(W, CONTENT_H)
    scroll:SetScrollChild(child)
    local bar = scroll.ScrollBar or scroll.scrollBar or _G["ForagerOptionsScrollScrollBar"]
    if type(bar) ~= "table" then bar = nil end
    local function Range()
        return math.max(0, (child:GetHeight() or 0) - (scroll:GetHeight() or 0))
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(Range(), (self:GetVerticalScroll() or 0) - delta * 40)))
    end)
    local function UpdateScroll()
        local range = Range()
        if bar then
            if bar.SetMinMaxValues then pcall(bar.SetMinMaxValues, bar, 0, range) end
            bar:SetShown(range > 1)
        end
        if (scroll:GetVerticalScroll() or 0) > range then scroll:SetVerticalScroll(range) end
    end
    ns.optionsScroll = scroll
    local function Fill(self)
        if not EnsureContent() then return end
        if window and window:IsShown() then window:Hide() end
        local w = scroll:GetWidth() or 0
        local scale = 1
        if w > 0 then scale = math.min(1, (w - 4) / W) end
        child:SetSize(W * scale, CONTENT_H * scale)
        Host(child, 0, 0, scale)
        UpdateScroll()
    end
    page:SetScript("OnShow", Fill)
    -- The page's size can arrive after OnShow: fit again then, and bring the controls here if
    -- they are not here yet.
    page:SetScript("OnSizeChanged", function(self) if self:IsVisible() then Fill(self) end end)
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
    -- Only while it sits on the minimap. A button collector (EllesmereUI's, for one) that
    -- has taken the button keeps it where it put it.
    if mmButton:GetParent() ~= Minimap then return end
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
BINDING_NAME_FORAGER_NEXTTRACK = "Next track"
function Forager_Toggle() Toggle() end
function Forager_NextTrack() CycleTrack(1) end
function Forager_SwitchNow()
    local s = Scan()
    local e = NextEntry(s)
    if e then SwitchTo(e.key, "binding")
    else Print("nothing else in the rotation to switch to.") end
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
    elseif cmd == "sparkles" and (arg:find("^size") or arg:find("^intensity")) then
        -- /forager sparkles size <50-200>, intensity <0-100>
        local what, value = arg:match("^(%a+)%s+(%S+)$")
        local n = tonumber(value)
        local key, low, high = "sparkleSize", 50, 200
        if what == "intensity" then key, low, high = "sparkleIntensity", 0, 100 end
        if not (what == "size" or what == "intensity") or not n or n ~= math.floor(n) or n < low or n > high then
            Print("usage: /forager sparkles size <50-200> or /forager sparkles intensity <0-100>")
            return
        end
        db[key] = n
        if ns.ApplySparkleLooks then ns.ApplySparkleLooks() end
        RefreshOptions()
        Print("sparkle " .. what .. " " .. n .. "%")
    elseif cmd == "sparkles" and arg ~= "" then
        -- next, previous, or an effect's number: picks the sparkle effect.
        if not ns.SetSparkleEffect then return end
        local n = tonumber(arg)
        local entry, index, count
        if arg == "next" then entry, index, count = ns.SetSparkleEffect(nil, 1)
        elseif arg == "prev" or arg == "previous" then entry, index, count = ns.SetSparkleEffect(nil, -1)
        elseif n and n >= 1 and n <= #ns.SPARK_MODELS and n == math.floor(n) then entry, index, count = ns.SetSparkleEffect(n, 1)
        else
            Print("usage: /forager sparkles [next|previous|1-" .. #ns.SPARK_MODELS .. "]")
            return
        end
        RefreshOptions()
        if entry then
            Print(("sparkle effect %d of %d: %s (%s, %d)"):format(index, count, entry.label, entry.name, entry.id))
        else
            Print("this client has none of the sparkle effects")
        end
    elseif cmd == "sparkles" then
        db.sparkles = not db.sparkles
        UpdateBar()
        RefreshOptions()
        Print("sparkles on the active tracker " .. (db.sparkles and "on" or "off"))
    elseif cmd == "minimap" or cmd == "icons" then
        local key = cmd == "minimap" and "minimap" or "bar"
        db[key] = not db[key]
        UpdateMinimapButton()
        UpdateBar()
        RefreshOptions()
        Print((cmd == "minimap" and "minimap button " or "tracker icons ") .. (db[key] and "shown" or "hidden"))
    elseif cmd == "switch" then
        Forager_SwitchNow()
    elseif cmd == "rows" then
        if arg == "apart" or arg == "unlock" then db.tracksApart = true
        elseif arg == "together" or arg == "join" then db.tracksApart = false
        else db.tracksApart = not db.tracksApart end
        UpdateBar()
        LayoutBar()
        RefreshOptions()
        Print(db.tracksApart and "each track's row moves on its own." or "the tracks' rows move together.")
    elseif cmd == "align" then
        if arg == "left" or arg == "top" then SetTrackAlign("start")
        elseif arg == "center" or arg == "centre" or arg == "middle" then SetTrackAlign("center")
        elseif arg == "right" or arg == "bottom" then SetTrackAlign("end")
        else
            local i = 1
            for n, a in ipairs(ALIGNS) do if a == db.trackAlign then i = n end end
            SetTrackAlign(ALIGNS[i % #ALIGNS + 1])
        end
        Print(AlignText())
    elseif cmd == "gap" then
        local n = tonumber(arg)
        if n then
            db.trackGap = math.max(0, math.min(40, math.floor(n + 0.5)))
            LayoutBar()
            UpdateBar()
            RefreshOptions()
            Print("gap between tracks: " .. db.trackGap .. " px")
        else
            Print("usage: /forager gap <0 to 40>")
        end
    elseif cmd == "track" then
        local raw = (msg or ""):match("^%s*%S+%s*(.-)%s*$") or ""
        if arg == "" or arg == "next" then
            CycleTrack(1)
        elseif arg == "prev" or arg == "previous" then
            CycleTrack(-1)
        elseif arg:match("^new") then
            local name = raw:match("^%S+%s+(.+)$")
            NewTrack(name)
        elseif tonumber(arg) and db.tracks[tonumber(arg)] then
            UseTrack(tonumber(arg))
        else
            local found
            for i, t in ipairs(db.tracks) do
                if t.name:lower():find(arg, 1, true) then found = i break end
            end
            if found then UseTrack(found)
            else
                local names = {}
                for i, t in ipairs(db.tracks) do names[#names + 1] = i .. ". " .. t.name end
                Print("tracks: " .. table.concat(names, ", ") .. ". /forager track next, previous, a number, a name, or new <name>.")
            end
        end
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
    elseif cmd == "debug" and arg == "icons" then
        -- Printed, and kept in the saved log for reading after a /reload.
        if not ns.ProbeIcons then return end
        Log("icon probe, shape " .. tostring(db.iconShape) .. ", style " .. tostring(db.style))
        ns.ProbeIcons(function(line)
            Print(line)
            Log(line)
        end)
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
        Print("skin: " .. tostring(ns.report.skin or "Blizzard") .. "; window style setting " .. tostring(db.style)
            .. ", Dark opacity " .. math.floor(db.darkAlpha * 100 + 0.5) .. "%, icon shape " .. tostring(db.iconShape)
            .. (ns.IconShape and (" (" .. ns.IconShape() .. ")") or ""))
        for key, value in pairs(ns.report) do
            if key:find("^skin error") then Print(key .. ": " .. tostring(value)) end
        end
        if ns.SparklePath then
            local path, why = ns.SparklePath()
            Print("sparkles " .. (db.sparkles and "on" or "off") .. ": " .. path .. ", " .. why)
        end
        if ns.SparkleEffect then
            local entry, index, count, status = ns.SparkleEffect()
            local loaded, skipped = {}, {}
            for i, e in ipairs(ns.SPARK_MODELS) do
                if status[e.id] == "loaded" then loaded[#loaded + 1] = i .. " " .. e.label end
                if status[e.id] == "skipped" then skipped[#skipped + 1] = i .. " " .. e.label .. " (" .. e.id .. ")" end
            end
            Print(("sparkle size %d%% (reach %.1f px), intensity %d%%"):format(db.sparkleSize, ns.SparkleReach and ns.SparkleReach() or 0, db.sparkleIntensity))
            Print(("sparkle effect %d of %d: %s; loaded: %s; skipped: %s"):format(index, count, entry.label,
                #loaded > 0 and table.concat(loaded, ", ") or "none yet", #skipped > 0 and table.concat(skipped, ", ") or "none"))
        end
    elseif cmd == "style" then
        local Styles = ns.Styles
        if not Styles then return end
        if arg == "auto" or arg == "automatic" then Styles.Set("auto")
        elseif arg == "blizzard" or arg == "dark" then Styles.Set(arg)
        elseif arg == "" then Styles.Cycle(1)
        else Print("styles: auto, blizzard, dark.") return end
        RefreshOptions()
        Print("window style: " .. Styles.Name(db.style) .. ". " .. Styles.Note())
    elseif cmd == "shape" then
        if arg == "automatic" then arg = "auto" end
        if SHAPE_NAMES[arg] then SetIconShape(arg)
        elseif arg ~= "" then Print("shapes: auto, round, square.") return end
        local looks = { bar = "the action bar look", square = "square", ["circle-ring"] = "round", ["circle-edge"] = "round" }
        Print("icon shape: " .. (SHAPE_NAMES[db.iconShape] or SHAPE_NAMES.auto)
            .. (ns.IconShape and (", now " .. (looks[ns.IconShape()] or ns.IconShape())) or "") .. ".")
    else
        Print("/forager (options), on, off, toggle, switch, delay <seconds>, move <tracker> up|down, icons, minimap, reset, style [auto|blizzard|dark], shape [auto|round|square], sparkles [next|previous|n|size n|intensity n], retest, debug [icons]")
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
        -- Tracks (1.10.0): what was ticked before becomes the first track.
        if type(db.tracks) ~= "table" or #db.tracks == 0 then
            db.tracks = { {
                name = "Track 1",
                rotation = db.rotation or { [HERBS] = true, [MINERALS] = true },
                skipped = {},
            } }
        end
        SelectTrack(db.track or 1)
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
            KeepOn()
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
        -- They point at the current track's tables; saved, they would be
        -- written out a second time.
        db.rotation, db.skipped = nil, nil
    elseif event == "PLAYER_DEAD" then
        deathAt, aliveAt = GetTime(), nil
        Log("died; tracker to restore: " .. tostring(db.lastTracked[UnitGUID("player") or ""]))
    else
        OnRefused(event, arg1)
    end
end)
