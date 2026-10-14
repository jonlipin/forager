// Offline checks for Forager: runs Forager.lua in fengari against a stubbed client.
//   NODE_PATH=<dir with fengari> node tests/foragertest.js
'use strict';
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const STUBS = `
math.randomseed(7) -- the sparkle tests use math.random; a fixed seed keeps the counts steady
T = { anims = {}, now = 100, combat = false, blockTimer = false, blockAll = false, frames = {}, timers = {}, prints = {}, bindings = {} }
T.tracking = {
  { name = "Find Herbs", spellID = 2383, type = "spell", active = false, texture = 1 },
  { name = "Find Minerals", spellID = 2580, type = "spell", active = false, texture = 2 },
  { name = "Track Beasts", spellID = 1494, type = "spell", active = false, texture = 3 },
  { name = "Flight Master", type = "townfolk", active = true, texture = 4 },
  { name = "Find Fish", spellID = 43308, type = "spell", active = false, texture = 5 },
  { name = "Track Humanoids", spellID = 5225, type = "spell", active = false, texture = 6 },
}
T.cvars = { Sound_EnableSFX = "1" }
T.sfxLog = {}
function GetCVar(k) return T.cvars[k] end
function SetCVar(k, v) T.cvars[k] = v if k == "Sound_EnableSFX" then T.sfxLog[#T.sfxLog + 1] = { T.now, v } end end
function GetInventoryItemID(_, slot) if slot == 16 then return T.mainHand end end
C_Item = { GetItemInfoInstant = function(id) if id == 6256 then return id, "Weapon", "Fishing Poles", "INVTYPE_2HWEAPON", 0, 2, 20 end return id, "Weapon", "Swords", "INVTYPE_WEAPON", 0, 2, 7 end }
function GetShapeshiftFormID() return T.form end
function UnitClass() return T.className or "Mage", T.class or "MAGE" end
function GetTime() return T.now end
function IsResting() return T.resting end
function IsInInstance() return T.instance ~= nil, T.instance or "none" end
function GetUnitSpeed() return T.speed or 7 end
function T.keyboardSafe()
  for _, f in ipairs(T.frames) do if f.keyboard and not f.propagate then return false end end
  return true
end
function date() return "12:00:00" end
function print(m) T.prints[#T.prints + 1] = m end
function debugstack() return "stack" end
function InCombatLockdown() return T.combat end
function UnitAffectingCombat() return T.combat end
function UnitIsDeadOrGhost() return T.dead == true end
function UnitGUID() return "Player-1-0001" end
function UnitOnTaxi() return false end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function IsAltKeyDown() return false end
function IsControlKeyDown() return false end
function IsShiftKeyDown() return false end
function GetBindingAction(k) return T.bindings[k] or "" end
function GetBindingKey(a) local keys = {} for k, v in pairs(T.bindings) do if v == a then keys[#keys + 1] = k end end table.sort(keys) return unpack(keys) end
function SetBinding(k, a) if T.combat then error("protected") end T.bindings[k] = a T.fire("UPDATE_BINDINGS") return true end
function SaveBindings(set) T.saved = (T.saved or 0) + 1 end
function GetCurrentBindingSet() return 2 end
function GetBindingText(k) return k end
unpack = unpack or table.unpack
function GetCurrentKeyBoardFocus() return nil end
function tinsert(t, v) t[#t + 1] = v end
UISpecialFrames = {}
C_Spell = { GetSpellName = function(id) for _, t in ipairs(T.tracking) do if t.spellID == id then return t.name end end end,
            GetSpellCooldown = function()
              if T.landedAt and T.now < T.landedAt + 1.5 then return { startTime = T.landedAt, duration = 1.5 } end
              return { startTime = 0, duration = 0 }
            end }
local fire
C_Minimap = {
  GetNumTrackingTypes = function() return #T.tracking end,
  GetTrackingInfo = function(i) return T.tracking[i] end,
  SetTracking = function(i, on)
    local fromKey = T.inKey
    if T.blockAll or (T.blockTimer and not fromKey) then fire("ADDON_ACTION_BLOCKED", "Forager", "UNKNOWN()") return end
    T.sfxAtCast = T.cvars.Sound_EnableSFX
    local function land()
      if T.tracking[i].spellID ~= 2481 then
        for _, t in ipairs(T.tracking) do if t.type == "spell" and t.spellID ~= 2481 then t.active = false end end
      end
      T.tracking[i].active = on
      T.switches = (T.switches or 0) + 1
      T.landedAt = T.now
    end
    if T.lag then
      fire("MINIMAP_UPDATE_TRACKING")
      C_Timer.After(T.lag, land)
    else
      land()
      fire("MINIMAP_UPDATE_TRACKING")
    end
  end,
}
C_Timer = {
  After = function(d, f) T.timers[#T.timers + 1] = { at = T.now + d, f = f } end,
  NewTicker = function(d, f) T.ticker = f end,
}
local Frame = {}
Frame.__index = function(self, k) return Frame[k] or function() end end
function Frame:SetScript(n, f) self.scripts[n] = f if f and (n == "OnKeyDown" or n == "OnKeyUp") then self.keyboard = true end end
function Frame:GetParent() return rawget(self, "parent") end
function Frame:SetParent(p) self.parent = p end
function Frame:GetPropagateKeyboardInput() return self.propagate end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:EnableKeyboard(on) self.keyboard = on end
function Frame:SetPropagateKeyboardInput(on) if T.combat then error("protected") end self.propagate = on end
function Frame:CreateAnimationGroup() local a = setmetatable({ scripts = {}, events = {} }, Frame) T.anims[#T.anims + 1] = a return a end
function Frame:CreateAnimation() return setmetatable({ scripts = {}, events = {} }, Frame) end
function Frame:SetShown(on) self.shown = on end
function Frame:Play() self.playing = true end
function Frame:IsPlaying() return rawget(self, "playing") == true end
function Frame:SetOffset(x, y) self.offset = { x, y } end
function Frame:SetToAlpha(v) self.toAlpha = v end
function Frame:SetFromAlpha(v) self.fromAlpha = v end
function Frame:SetDegrees(d) self.degrees = d end
function Frame:SetDrawLayer(layer, sub) self._layer, self._sub = layer, sub or 0 end
function Frame:Stop() self.playing = false end
function Frame:SetText(v) self.text = v end
function Frame:CreateTexture() return setmetatable({ scripts = {}, events = {} }, Frame) end
function Frame:CreateFontString() return setmetatable({ scripts = {}, events = {} }, Frame) end
function Frame:GetWidth() return 140 end
function Frame:SetCooldown(start, dur) self.cdStart, self.cdDur = start, dur end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:GetFrameLevel() return 1 end
function Frame:GetScale() return self.scale or 1 end
function Frame:SetScale(v) self.scale = v end
function Frame:GetCenter() return nil end
function Frame:GetFrameLevel() return 1 end
function Frame:GetChecked() return self.checked end
function Frame:IsVisible() return false end
function Frame:HookScript(n, f) local old = self.scripts[n] self.scripts[n] = function(...) if old then old(...) end f(...) end end
-- What the window styles need: levels, children, and textures counted per frame.
function Frame:SetFrameLevel(v) self.level = v end
function Frame:GetFrameLevel() return rawget(self, "level") or 1 end
function Frame:GetChildren()
  local out = {}
  for _, f in ipairs(T.frames) do if rawget(f, "parent") == self then out[#out + 1] = f end end
  return unpack(out)
end
function Frame:SetAlpha(v) self.alpha = v end
function Frame:SetEnabled(v) self.enabled = v and true or false end
function Frame:SetFontObject(v) self.font = v end
function Frame:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
-- Masks, crops and the cooldown sweep, for the tracker icons.
function Frame:CreateMaskTexture() return setmetatable({ scripts = {}, events = {}, isMask = true }, Frame) end
function Frame:AddMaskTexture(m) local l = rawget(self, "masks") or {} rawset(self, "masks", l) l[#l + 1] = m end
function Frame:RemoveMaskTexture(m) local l = rawget(self, "masks") or {} for i = #l, 1, -1 do if l[i] == m then table.remove(l, i) end end end
function Frame:GetNumMaskTextures() local l = rawget(self, "masks") return l and #l or 0 end
-- As the client does: SetTexCoord takes left, right, top, bottom and nothing
-- else, and refuses a masked texture outright; GetTexCoord gives the four
-- corners, eight values.
function Frame:SetTexCoord(...)
  local n = select("#", ...)
  if n ~= 4 then error("Usage: SetTexCoord(left, right, top, bottom), got " .. n .. " values") end
  for i = 1, 4 do if type((select(i, ...))) ~= "number" then error("SetTexCoord: value " .. i .. " is not a number") end end
  if (rawget(self, "masks") and #rawget(self, "masks") or 0) > 0 then error("SetTexCoord on a masked texture") end
  self.coords = { ... }
end
function Frame:GetTexCoord()
  local c = rawget(self, "coords")
  if not c then return 0, 0, 0, 1, 1, 0, 1, 1 end
  local l, r, t, b = c[1], c[2], c[3], c[4]
  return l, t, l, b, r, t, r, b
end
function Frame:GetRegions() return unpack(rawget(self, "texs") or {}) end
function Frame:ClearAllPoints() self._point, self._all, self._points = nil, nil, nil end
function Frame:SetAllPoints(rel) self._all = rel or true end
function Frame:SetSwipeTexture(tex, r, g, b, a) self.swipe = tex self.swipeSet = true end
function Frame:SetSwipeColor(r, g, b, a) self.swipeColor = { r, g, b, a } end
function Frame:SetDrawSwipe(on) self.drawSwipe = on end
function Frame:SetUseCircularEdge(on) self.circularEdge = on end
function Frame:SetAtlas(atlas) self.atlas = atlas end
function Frame:SetTexture(file) self.texture = file end
function Frame:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function Frame:SetBlendMode(mode) self.blend = mode end
function Frame:EnableMouse(on) self.mouse = on end
function Frame:SetPoint(...)
  self._point = { ... }
  local points = rawget(self, "_points") or {}
  rawset(self, "_points", points)
  points[(...)] = { ... }
end
function Frame:SetSize(w, h) self._w, self._h = w, h end
T.strings = {}
function Frame:CreateFontString() local fs = setmetatable({ scripts = {}, events = {} }, Frame) T.strings[#T.strings + 1] = fs return fs end
function T.string(text) for _, fs in ipairs(T.strings) do if rawget(fs, "text") == text then return fs end end end
function Frame:CreateTexture(_, layer, _, sub)
  local t = setmetatable({ scripts = {}, events = {}, _layer = layer or "ARTWORK", _sub = sub or 0 }, Frame)
  local list = rawget(self, "texs") or {}
  rawset(self, "texs", list)
  list[#list + 1] = t
  return t
end
function T.texCount(f) local list = rawget(f, "texs") return list and #list or 0 end
function T.drawSnapshot() local snap = {} for _, f in ipairs(T.frames) do snap[f] = T.texCount(f) end return snap end
function T.drawnSince(snap, f) return T.texCount(f) - (snap[f] or 0) end
GameFontNormalSmall, GameFontHighlight, GameFontDisable = { name = "GameFontNormalSmall" }, { name = "GameFontHighlight" }, { name = "GameFontDisable" }
-- A ModelScene and its actors, as Cursor Beacon's harness has them: the camera
-- is recorded, and an actor takes any model but the ones in T.modelDeny.
-- T.noModelScene makes a client without the frame type.
T.modelDeny = T.modelDeny or {}
local function SceneActor()
  local a = setmetatable({ scripts = {}, events = {} }, Frame)
  rawset(a, "SetModelByFileID", function(self, id) if T.modelDeny[id] then return false end self.model = id return true end)
  rawset(a, "SetPosition", function(self, x, y, z) self.pos = { x, y, z } end)
  rawset(a, "SetAlpha", function(self, v) self.actorAlpha = v end)
  rawset(a, "SetPitch", function(self, v) self.pitch = v end)
  return a
end
local function AddSceneMethods(f)
  f.cam = {}
  f.actors = {}
  rawset(f, "SetCameraPosition", function(self, x, y, z) self.cam.pos = { x, y, z } end)
  rawset(f, "SetCameraFieldOfView", function(self, v) self.cam.fov = v end)
  rawset(f, "SetCameraOrientationByAxisVectors", function(self, ...) self.cam.axes = { ... } end)
  rawset(f, "CreateActor", function(self) local a = SceneActor() self.actors[#self.actors + 1] = a return a end)
end
function CreateFrame(kind, name, parent, template)
  if kind == "ModelScene" and T.noModelScene then error("Unknown frame type ModelScene") end
  local f = setmetatable({ scripts = {}, events = {}, name = name, keyboard = false, propagate = false, parent = parent, kind = kind }, Frame)
  if kind == "ModelScene" then AddSceneMethods(f) end
  rawset(f, "template", template)
  if template == "CooldownFrameTemplate" then rawset(f, "_all", parent) rawset(f, "swipeColor", { 0, 0, 0, 0.64 }) end
  -- As the client does: a child starts one level above its parent.
  if type(parent) == "table" and parent.GetFrameLevel then rawset(f, "level", parent:GetFrameLevel() + 1) end
  T.frames[#T.frames + 1] = f
  if name then _G[name] = f end
  -- The window template's own pieces, as real frames.
  -- The close button and the window templates that bring one click through the game's own
  -- UIPanelCloseButton_OnClick, as SharedUIPanelTemplates.lua has it.
  if template == "UIPanelCloseButton" then f.scripts.OnClick = function(...) return UIPanelCloseButton_OnClick(...) end end
  if template == "BasicFrameTemplateWithInset" then
    f.CloseButton = CreateFrame("Button", name and (name .. "CloseButton"), f, "UIPanelCloseButton")
  end
  if template == "ButtonFrameTemplate" then
    f.CloseButton = CreateFrame("Button", name and (name .. "CloseButton"), f, "UIPanelCloseButton")
    f.TitleContainer = CreateFrame("Frame", nil, f)
    f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
    f.PortraitContainer = CreateFrame("Frame", nil, f)
    f.NineSlice = CreateFrame("Frame", nil, f)
    f.Inset = CreateFrame("Frame", nil, f)
  end
  return f
end
-- On this client ShowUIPanel and HideUIPanel refuse addon code in combat: the player sees an
-- "Interface action blocked" message and nothing else. T.blocked counts the refusals.
T.blocked = 0
function ShowUIPanel(f)
  if not f then return end
  if InCombatLockdown() then T.blocked = T.blocked + 1 return end
  f:Show()
end
function HideUIPanel(f)
  if not f then return end
  if InCombatLockdown() then T.blocked = T.blocked + 1 return end
  f:Hide()
end
-- The close button template's own click, as the client's SharedUIPanelTemplates.lua has it.
function UIPanelCloseButton_OnClick(self)
  local parent = self:GetParent()
  if parent then
    local continueHide = true
    local callback = rawget(parent, "onCloseCallback") -- this stub answers every unknown key with a function
    if callback then continueHide = callback(self) end
    if continueHide then HideUIPanel(parent) end
  end
end
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
SlashCmdList = {}
fire = function(e, ...)
  for _, f in ipairs(T.frames) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end
end
T.fire = fire
function T.advance(sec)
  local stop = T.now + sec
  while T.now < stop do
    T.now = T.now + 0.25
    local due = {}
    for i = #T.timers, 1, -1 do if T.timers[i].at <= T.now then due[#due + 1] = table.remove(T.timers, i) end end
    for _, t in ipairs(due) do t.f() end
    if T.ticker then T.ticker() end
    T.frame(0.25)
  end
end
-- Frame updates without the clock moving: every shown frame's OnUpdate gets
-- dt, in steps of at most 0.05 s, as the client's frames would.
function T.frame(dt)
  while dt > 1e-9 do
    local step = math.min(0.05, dt)
    dt = dt - step
    local list = {}
    for _, f in ipairs(T.frames) do
      if rawget(f, "shown") ~= false and f.scripts.OnUpdate then list[#list + 1] = f end
    end
    for _, f in ipairs(list) do f.scripts.OnUpdate(f, step) end
  end
end
function T.active()
  for _, t in ipairs(T.tracking) do if t.active and t.type == "spell" then return t.name end end
end
function T.key(k)
  local kf = _G.ForagerKeyListener
  if not (kf and kf.keyboard and kf.propagate) then return end
  T.inKey = true
  kf.scripts.OnKeyDown(kf, k)
  T.inKey = false
end
`;

// A stand-in EllesmereUI (EUI=1): its skinning facade records every call on
// the object it was given, in T.skinned, and its Shell lays a border frame
// over the window as the real one does. It calls back at login, before
// Forager's own login handler.
const EUI_STUB = `
T.skinned = {}
local function rec(name) return function(f) if f then T.skinned[f] = (T.skinned[f] or "") .. name .. "," end end end
T.S = { apiVersion = 3, GetStyle = function() return "eui" end }
for _, n in ipairs({ "Inset", "FadeRegions", "FadeNineSlice", "Button", "WhiteButtonLabel", "StateButtonLabel", "EditBox",
    "Checkbox", "Dropdown", "ScrollBar", "Tab", "SetTabSelection", "CloseButton", "PageButton", "SquareIcon", "SortHeaderBar",
    "Font", "White", "ApplyBarFill", "Panel" }) do T.S[n] = rec(n) end
T.S.Shell = function(f)
  rec("Shell")(f)
  local border = CreateFrame("Frame", nil, f)
  border:SetFrameLevel(f:GetFrameLevel() + 6)
  T.border = border
end
-- Like the real one: a masked icon is left alone, else it is cropped and
-- four edge lines are drawn on the parent.
T.S.SquareIcon = function(icon, parent)
  rec("SquareIcon")(icon)
  if icon:GetNumMaskTextures() > 0 then return end
  if not pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92) then return end
  if parent and not rawget(icon, "euiEdged") then
    icon.euiEdged = true
    for _ = 1, 4 do parent:CreateTexture(nil, "OVERLAY"):SetColorTexture(0, 0, 0, 1) end
  end
  return true
end
EllesmereUI = { RegisterSkin = function(name, fn) T.euiName = name T.euiFn = fn end, _DispatchSkinRegistration = function() end }
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() if T.euiFn then T.euiFn(T.S) end end)
function T.did(f, what) return f ~= nil and (T.skinned[f] or ""):find(what .. ",", 1, true) ~= nil end
`;

// The game's options panel, with the client's rules for OnShow: it runs only when a frame turns
// from not visible to visible, and a frame made without a parent starts out shown, which counts
// as visible. The panel shows a canvas page by moving it into its window and calling Show.
const FIRST_OPEN_STUB = `
do
  local realCreate = CreateFrame
  function CreateFrame(...) local f = realCreate(...) f.shown = true return f end
  local function vis(f) if not f.shown then return false end local p = rawget(f, "parent") if p == nil then return true end return vis(p) end
  function Frame:IsVisible() return vis(self) end
  function Frame:IsShown() return self.shown and true or false end
  function Frame:GetParent() return rawget(self, "parent") end
  function Frame:Show() local was = vis(self) self.shown = true if not was and vis(self) and self.scripts.OnShow then self.scripts.OnShow(self) end end
  function Frame:SetParent(p) local was = vis(self) self.parent = p if not was and vis(self) and self.scripts.OnShow then self.scripts.OnShow(self) end end
  SettingsPanel = CreateFrame("Frame") SettingsPanel.shown = false
  function SettingsPanel:Show()
    if self.shown then return end
    self.shown = true
    for _, f in ipairs(T.frames) do if rawget(f, "parent") == self and f.shown and f.scripts.OnShow then f.scripts.OnShow(f) end end
  end
  function HideUIPanel(f) f.shown = false end
  Settings = {
    RegisterCanvasLayoutCategory = function(page, name) T.page = page return { ID = 9 } end,
    RegisterAddOnCategory = function() end,
    -- Opening to the category: the page goes in before the window shows.
    OpenToCategory = function() T.page:SetParent(SettingsPanel) T.page:Show() SettingsPanel:Show() end,
  }
  function T.hosted()
    for _, f in ipairs(T.frames) do if rawget(f, "parent") == T.page and f:IsVisible() then return f end end
  end
end
`;
const EUI_ON = process.env.EUI === '1';
let pass = 0, fail = 0;
function run(name, body, opts) {
  opts = opts || {};
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const src = fs.readFileSync(path.join(__dirname, '..', 'Forager.lua'), 'utf8');
  const stylesSrc = fs.readFileSync(path.join(__dirname, '..', 'Styles.lua'), 'utf8');
  const skinSrc = fs.readFileSync(path.join(__dirname, '..', 'Forager_Skins.lua'), 'utf8');
  // opts.db: saved settings to start from (a Lua table). opts.atlas: every
  // atlas exists, so the icons wear the action bar art as on the client.
  const code = STUBS +
    (opts.db ? `ForagerDB = ${opts.db}\n` : '') +
    (opts.atlas ? `C_Texture = { GetAtlasInfo = function() return {} end }\nT.atlas = true\n` : '') +
    // opts.noModelScene: a client without ModelScene; opts.modelDeny: model ids it lacks.
    (opts.noModelScene ? `T.noModelScene = true\n` : '') +
    (opts.modelDeny ? `T.modelDeny = ${opts.modelDeny}\n` : '') +
    (opts.page ? FIRST_OPEN_STUB : '') +
    (EUI_ON ? EUI_STUB : '') +
    `\nNS = {}\nlocal chunk = assert(load(${JSON.stringify(src)}, "@Forager.lua"))\nchunk("Forager", NS)\n` +
    `assert(load(${JSON.stringify(stylesSrc)}, "@Styles.lua"))("Forager", NS)\n` +
    // Every Dark drawing call is recorded on the object it was given, in T.darkCalls.
    `T.darkCalls = {}\nfor name, fn in pairs(NS.Styles.Dark) do if type(fn) == "function" then NS.Styles.Dark[name] = function(f, ...) if type(f) == "table" then T.darkCalls[f] = (T.darkCalls[f] or "") .. name .. "," end return fn(f, ...) end end end\n` +
    `assert(load(${JSON.stringify(skinSrc)}, "@Forager_Skins.lua"))("Forager", NS)\n` +
    `T.fire("ADDON_LOADED", "Forager")\nT.fire("PLAYER_LOGIN")\n` +
    `function T.skinErrors() local list = {} for k, v in pairs(NS.report) do if k:find("^skin error") then list[#list + 1] = k .. ": " .. tostring(v) end end return #list, table.concat(list, "; ") end\n` +
    `local function check(ok, what) if ok then CHECKS_PASS = (CHECKS_PASS or 0) + 1 else error("FAILED: " .. what, 2) end end\n` +
    `check(T.keyboardSafe(), "keyboard passes through after login")\n` + body +
    `\ncheck(T.keyboardSafe(), "keyboard passes through at the end")\n`;
  const status = lauxlib.luaL_dostring(L, to_luastring(code));
  if (status !== 0) { fail++; console.log('FAIL ' + name + ': ' + lua.lua_tojsstring(L, -1)); return; }
  lua.lua_getglobal(L, to_luastring('CHECKS_PASS'));
  pass += lua.lua_tonumber(L, -1) || 0;
  console.log('ok   ' + name);
}

run('timer switches back and forth on the delay', `
  check(T.active() == nil, "nothing tracked at start")
  T.advance(5.5) check(T.active() == nil, "no switch before 6 s")
  T.advance(1) check(T.active() == "Find Herbs", "herbs first, got " .. tostring(T.active()))
  T.advance(2) check(ForagerDB.method == "timer", "learned timer")
  T.advance(4.5) check(T.active() == "Find Minerals", "then minerals")
  T.advance(6.5) check(T.active() == "Find Herbs", "then herbs again")
`);
run('no switching in combat', `
  T.combat = true T.advance(20) check(T.active() == nil, "nothing in combat")
  T.combat = false T.advance(0.5) check(T.active() == "Find Herbs", "switches right after combat")
`);
run('another tracking spell pauses it', `
  T.tracking[3].active = true T.advance(20)
  check(T.active() == "Track Beasts", "Track Beasts left alone")
`);
run('off means off', `
  SlashCmdList.FORAGER("off") T.advance(20) check(T.active() == nil, "nothing while off")
  SlashCmdList.FORAGER("on") T.advance(6.5) check(T.active() == "Find Herbs", "on again")
`);
run('a blocked timer falls back to key presses', `
  T.blockTimer = true
  T.advance(7) check(ForagerDB.method == "key", "learned key, got " .. tostring(ForagerDB.method))
  check(ForagerKeyListener.keyboard and ForagerKeyListener.propagate, "listener on and passing keys through")
  T.advance(10) check(T.active() == nil, "timer no longer tries")
  T.bindings["1"] = "ACTIONBUTTON1"
  T.key("1") check(T.active() == nil, "ability key left alone")
  T.bindings["W"] = "MOVEFORWARD"
  T.key("W") check(T.active() == "Find Herbs", "movement key switches")
  T.key("W") check(T.active() == "Find Herbs", "not again before the delay")
  T.advance(6) T.key("W") check(T.active() == "Find Minerals", "next key press after the delay")
`);
run('key listener set up only out of combat', `
  T.combat = true T.blockTimer = true
  ForagerDB.method = "key"
  T.fire("PLAYER_REGEN_DISABLED")
  check(not (ForagerKeyListener and ForagerKeyListener.keyboard), "not in combat")
  T.combat = false T.fire("PLAYER_REGEN_ENABLED")
  check(ForagerKeyListener.keyboard, "after combat")
`);
run('refused even from a key press stops trying', `
  T.blockAll = true
  T.advance(7) T.advance(6) T.bindings["W"] = "MOVEFORWARD" T.key("W")
  check(ForagerDB.method == "none", "gave up, got " .. tostring(ForagerDB.method))
  SlashCmdList.FORAGER("retest") check(ForagerDB.method == nil, "retest resets")
`);
run('slash delay', `
  SlashCmdList.FORAGER("delay 15") check(ForagerDB.delay == 15, "delay set")
  T.advance(14) check(T.active() == nil, "waits 15 s") T.advance(1.5) check(T.active() == "Find Herbs", "then switches")
  SlashCmdList.FORAGER("debug")
`);
run('tracker icons glow on the active tracker and pause resumes', `
  T.advance(6.5) check(T.active() == "Find Herbs", "herbs on")
  -- The glows' own animations (the sparkles have animations of their own).
  local glows = { ForagerTrackButton1.anim, ForagerTrackButton2.anim }
  check(#NS.trackButtons == 2 and rawget(ForagerTrackButton1, "anim") and rawget(ForagerTrackButton2, "anim"), "two glow animations")
  check(glows[1].playing == true and glows[2].playing == false, "herbs glows")
  T.advance(6.5) check(glows[1].playing == false and glows[2].playing == true, "minerals glows")
  ForagerPauseButton.scripts.OnClick(ForagerPauseButton, "LeftButton")
  check(ForagerDB.enabled == false, "paused")
  T.advance(20) check(T.active() == "Find Minerals", "no switching while paused")
  ForagerPauseButton.scripts.OnClick(ForagerPauseButton, "LeftButton")
  check(ForagerDB.enabled == true, "resumed")
  T.advance(6.5) check(T.active() == "Find Herbs", "switching again")
`);
run('rotates through every ticked tracker', `
  ForagerDB.rotation[1494] = true
  T.advance(6.5) check(T.active() == "Find Herbs", "1: herbs")
  T.advance(6.5) check(T.active() == "Find Minerals", "2: minerals")
  T.advance(6.5) check(T.active() == "Track Beasts", "3: beasts, got " .. tostring(T.active()))
  T.advance(6.5) check(T.active() == "Find Herbs", "back to herbs")
`);
run('with one tracker ticked it is kept on and nothing else switches', `
  ForagerDB.rotation[2580] = nil
  T.advance(20) check(T.active() == "Find Herbs", "herbs put on, got " .. tostring(T.active()))
  check(T.switches == 1, "and left on: " .. tostring(T.switches) .. " switches")
`);
run('a tracker that fails to cast is skipped', `
  ForagerDB.rotation[1494] = true
  local real = C_Minimap.SetTracking
  C_Minimap.SetTracking = function(i, on)
    if i == 3 then T.fire("UI_ERROR_MESSAGE", 50, "Must be in Cat Form") return end
    real(i, on)
  end
  T.advance(6.5) T.advance(6.5) check(T.active() == "Find Minerals", "minerals")
  T.advance(6.5) check(T.active() == "Find Minerals", "beasts failed")
  check(ForagerDB.method == "timer", "a game error is not a refusal, got " .. tostring(ForagerDB.method))
  T.advance(6.5) check(T.active() == "Find Herbs", "skipped to herbs, got " .. tostring(T.active()))
`);
run('pauses in cities, instances and standing still', `
  T.resting = true T.advance(20) check(T.active() == nil, "resting")
  T.resting = false T.instance = "party" T.advance(20) check(T.active() == nil, "dungeon")
  T.instance = nil ForagerDB.onlyMoving = true T.speed = 0 T.advance(20) check(T.active() == nil, "standing")
  T.speed = 7 T.advance(0.5) check(T.active() == "Find Herbs", "moving")
`);
run('timer mode never captures the keyboard', `
  T.advance(30) check(ForagerDB.method == "timer", "timer")
  check(_G.ForagerKeyListener == nil, "no listener frame at all")
`);
run('a swipe ticks down on the next tracker', `
  T.advance(6.5) check(T.active() == "Find Herbs", "herbs on")
  local herbsCd, mineralsCd
  for _, f in ipairs(T.frames) do
    if rawget(f, "cdStart") and rawget(f, "shown") then mineralsCd = f end
  end
  check(mineralsCd ~= nil and mineralsCd.shown, "swipe running on minerals")
  check(mineralsCd.cdDur == 6, "over the delay, got " .. tostring(mineralsCd.cdDur) .. " start " .. tostring(mineralsCd.cdStart))
  T.advance(6.5) check(T.active() == "Find Minerals", "minerals on")
  check(mineralsCd.shown == false, "no swipe on the tracker that is on")
  SlashCmdList.FORAGER("off")
  for _, f in ipairs(T.frames) do if rawget(f, "cdStart") and rawget(f, "shown") then check(false, "no swipe while paused") end end
`);
run('the swipe starts full when a slow switch lands', `
  T.lag = 0.6
  T.advance(7.5) check(T.active() == "Find Herbs", "herbs landed")
  local landed = T.landedAt
  local swipe
  for _, f in ipairs(T.frames) do
    if rawget(f, "cdStart") and rawget(f, "shown") then swipe = f end
  end
  check(swipe ~= nil, "swipe on minerals")
  check(swipe.cdStart >= landed, "starts when the switch landed (" .. landed .. "), not when asked (" .. swipe.cdStart .. ")")
  check(swipe.cdStart - landed <= 0.25, "within a tick of landing")
  T.advance(6.5) check(T.active() == "Find Minerals", "next one lands too")
`);
run('the swipe is full after every switch, not only the first', `
  T.lag = 0.6
  for round = 1, 4 do
    T.advance(7.5)
    local landed = T.landedAt
    local swipe
    for _, f in ipairs(T.frames) do
      if rawget(f, "cdStart") and rawget(f, "shown") then swipe = f end
    end
    check(swipe ~= nil, "round " .. round .. ": swipe showing during the global cooldown")
    check(swipe.cdStart >= landed and swipe.cdStart - landed <= 0.25,
      "round " .. round .. ": swipe starts as the switch lands (" .. landed .. "), got " .. tostring(swipe.cdStart))
  end
  check(T.switches == 4, "four switches, got " .. tostring(T.switches))
`);
run('trackers rotate in the order you set', `
  ForagerDB.rotation[1494] = true
  SlashCmdList.FORAGER("move beasts up")
  check(ForagerDB.order[1] == 2383 and ForagerDB.order[2] == 1494 and ForagerDB.order[3] == 2580,
    "beasts moved above minerals")
  T.advance(6.5) check(T.active() == "Find Herbs", "1: herbs")
  T.advance(6.5) check(T.active() == "Track Beasts", "2: beasts, got " .. tostring(T.active()))
  T.advance(6.5) check(T.active() == "Find Minerals", "3: minerals, got " .. tostring(T.active()))
  T.advance(6.5) check(T.active() == "Find Herbs", "back to herbs")
  SlashCmdList.FORAGER("move herbs up")
  check(ForagerDB.order[1] == 2383, "the top one can't move up")
  SlashCmdList.FORAGER("move humanoids down")
  check(ForagerDB.order[5] == 5225, "the bottom one can't move down")
`);
run('an order saved on another character is kept', `
  ForagerDB.order = { 9999, 2580, 2383 }
  T.advance(6.5) check(T.active() == "Find Minerals", "minerals first now")
  SlashCmdList.FORAGER("move herbs up")
  check(ForagerDB.order[1] == 2383 and ForagerDB.order[2] == 2580, "herbs on top")
  local kept = false
  for _, k in ipairs(ForagerDB.order) do if k == 9999 then kept = true end end
  check(kept, "the unknown tracker stays in the saved order")
`);
const DIE = `
  function T.die()
    T.dead = true
    for _, t in ipairs(T.tracking) do if t.type == "spell" then t.active = false end end
    T.fire("PLAYER_DEAD")
    T.fire("MINIMAP_UPDATE_TRACKING")
  end
`
run('tracking comes back after death', DIE + `
  T.advance(6.5) check(T.active() == "Find Herbs", "herbs on")
  T.die() T.advance(30) check(T.active() == nil, "nothing while dead")
  T.dead = false T.advance(1) check(T.active() == "Find Herbs", "herbs restored, got " .. tostring(T.active()))
`);
run('restores after death while paused, and a manual pick too', DIE + `
  SlashCmdList.FORAGER("off")
  T.tracking[3].active = true T.fire("MINIMAP_UPDATE_TRACKING") T.advance(0.5)
  T.die() T.advance(5)
  T.dead = false T.advance(1) check(T.active() == "Track Beasts", "beasts restored while paused, got " .. tostring(T.active()))
`);
run('nothing restored when the option is off or tracking was off', DIE + `
  T.advance(6.5) ForagerDB.restoreAfterDeath = false SlashCmdList.FORAGER("off")
  T.die() T.dead = false T.advance(2) check(T.active() == nil, "option off")
  ForagerDB.restoreAfterDeath = true
  T.tracking[1].active = true T.fire("MINIMAP_UPDATE_TRACKING") T.advance(0.5)
  T.tracking[1].active = false T.fire("MINIMAP_UPDATE_TRACKING") T.advance(0.5)
  T.die() T.dead = false T.advance(2) check(T.active() == nil, "you had switched it off")
`);
run('quiet switches mute sound effects only around the switch', `
  T.lag = 0.6
  T.advance(7) check(T.active() == "Find Herbs", "herbs on")
  check(T.sfxAtCast == "0", "muted when the switch is cast")
  T.advance(1) check(T.cvars.Sound_EnableSFX == "1", "sound back after it lands")
  check(#T.sfxLog == 2, "muted once and unmuted once, got " .. #T.sfxLog)
  check(T.sfxLog[2][1] - T.sfxLog[1][1] <= 1.5, "muted for at most a moment")
  ForagerDB.quiet = false T.advance(7) check(T.sfxAtCast == "1", "not muted with the option off")
`);
run('a switch waits while the loot window is open', `
  T.fire("LOOT_OPENED") T.advance(10) check(T.active() == nil, "no switch while looting")
  T.fire("LOOT_CLOSED") T.advance(0.5) check(T.active() == "Find Herbs", "switches when it closes")
`);
run('a fishing pole swaps in Find Fish and hands back to the rotation', `
  T.advance(6.5) check(T.active() == "Find Herbs", "herbs on")
  T.mainHand = 6256 T.advance(2) check(T.active() == "Find Fish", "Find Fish with a pole, got " .. tostring(T.active()))
  T.advance(20) check(T.active() == "Find Fish", "the rotation waits while fishing")
  T.mainHand = 1234 T.advance(2) check(T.active() == "Find Minerals" or T.active() == "Find Herbs", "rotation back at once, got " .. tostring(T.active()))
  T.advance(14) check(T.switches >= 4, "rotation keeps going, " .. tostring(T.switches))
`);
run('Cat Form tracks humanoids; paused rotation gets the old tracker back', `
  T.advance(6.5) SlashCmdList.FORAGER("off")
  T.form = 1 T.advance(2) check(T.active() == "Track Humanoids", "humanoids in Cat Form")
  T.form = nil T.advance(2) check(T.active() == "Find Herbs", "herbs back after Cat Form, got " .. tostring(T.active()))
  ForagerDB.swapCatForm = false T.form = 1 T.advance(5) check(T.active() == "Find Herbs", "option off")
`);
run('hunters track humanoids in battlegrounds', `
  T.class = "HUNTER" T.instance = "pvp"
  T.advance(2) check(T.active() == "Track Humanoids", "humanoids in a battleground, got " .. tostring(T.active()))
  T.class = "MAGE" T.instance = nil
`);
run('the pause key button binds a key, warns about a taken one, and lets go of the keyboard', `
  SlashCmdList.FORAGER("")
  local b = ForagerPauseKeyButton
  check(b ~= nil, "the button exists")
  check(not b.keyboard, "no keyboard before clicking")
  b.scripts.OnClick(b)
  check(b.keyboard, "listening after a click")
  b.scripts.OnKeyDown(b, "LSHIFT") check(b.keyboard, "a modifier alone keeps waiting")
  b.scripts.OnKeyDown(b, "P")
  check(T.bindings["P"] == "FORAGER_TOGGLE", "P bound")
  check(not b.keyboard, "keyboard let go after the key")
  check(T.saved == 1, "bindings saved")
  Forager_Toggle() check(ForagerDB.enabled == false, "the binding pauses")
  Forager_Toggle()
  T.bindings["W"] = "MOVEFORWARD"
  b.scripts.OnClick(b) b.scripts.OnKeyDown(b, "W")
  check(T.bindings["W"] == "MOVEFORWARD" and b.keyboard, "a taken key asks first")
  b.scripts.OnKeyDown(b, "W")
  check(T.bindings["W"] == "FORAGER_TOGGLE" and T.bindings["P"] == nil, "pressed again: W replaces P")
  check(not b.keyboard, "let go")
  b.scripts.OnClick(b) b.scripts.OnKeyDown(b, "ESCAPE")
  check(not b.keyboard and T.bindings["W"] == "FORAGER_TOGGLE", "Escape cancels")
  b.scripts.OnClick(b) ForagerPauseKeyClear.scripts.OnClick(ForagerPauseKeyClear)
  check(not b.keyboard and GetBindingKey("FORAGER_TOGGLE") == nil, "Unbind clears and lets go")
  T.combat = true b.scripts.OnClick(b)
  check(not b.keyboard, "no capture in combat")
  T.combat = false
`);
// -- SKIN TEST -------------------------------------------------------------
// Opens the options in their standalone window (this harness has no Options
// panel) and lets RefreshOptions see them as shown.
const OPEN = `
  function Frame:IsVisible() return rawget(self, "shown") == true end
  SlashCmdList.FORAGER("")
  ForagerOptions.scripts.OnShow(ForagerOptions)
  local content = rawget(NS.styleButton, "parent")
`;
// Only the window's own frame, the tracker icons and the reload prompt may
// be drawn on: the options inside, the bar holding the icons and the minimap
// button keep their art.
const ONLY_WINDOW_DRAWN = `
  do
    local win = ForagerOptions
    local allowed = { [win] = true, [win.CloseButton] = true, [win.TitleContainer] = true,
      [win.PortraitContainer] = true, [win.NineSlice] = true, [win.Inset] = true, [ForagerPauseButton] = true }
    for _, b in ipairs(NS.trackButtons) do allowed[b] = true end
    local function inPrompt(f)
      while f do if f == ForagerReloadPrompt then return true end f = rawget(f, "parent") end
    end
    for _, f in ipairs(T.frames) do
      if not allowed[f] and not inPrompt(f) then
        local name = tostring(rawget(f, "name") or "a frame")
        check(not T.darkCalls[f], "not restyled: " .. name .. " (" .. tostring(T.darkCalls[f]) .. ")")
        if SNAP[f] then check(T.drawnSince(SNAP, f) == 0, "nothing drawn on " .. name) end
      end
    end
    check(ForagerBar ~= nil and ForagerTrackButton1 ~= nil and ForagerMinimapButton ~= nil, "icons and minimap button exist")
  end
`;
// Every tracker icon in `look`, and the pause button in `pause` (default:
// the same). Looks: "bar" (the action bar art as built), "square" (squared by
// `drawer`, "dark" or "eui"), "circle-ring" (circle in the minimap ring) and
// "circle-edge" (circle with a thin dark edge). The glow is kept in all.
function ICONS(look, drawer, pause) {
  drawer = drawer || 'dark';
  pause = pause || look;
  return `
  do
    local SWIPE_FILE, FLAT = "Interface\\\\HUD\\\\UI-HUD-CoolDownManager-Icon-Swipe", "Interface\\\\Buttons\\\\WHITE8X8"
    local CIRCLE_FILE, RING_FILE = "Interface\\\\CharacterFrame\\\\TempPortraitAlphaMask", "Interface\\\\Minimap\\\\MiniMap-TrackingBorder"
    local function Same(a, b)
      if #a ~= #b then return false end
      for i = 1, #a do if math.abs(a[i] - b[i]) > 0.01 then return false end end
      return true
    end
    local function Masks(icon) return rawget(icon, "masks") or {} end
    -- The sweep art this addon uses: its clear margin on each side and how many texels
    -- its solid part has across (measured from the files). A sweep follows its texels,
    -- so one with fewer texels than the icon has pixels steps visibly (WHITE8X8 drew a
    -- pie stepped in eighths and left a strip unswept).
    local ART = {
      [SWIPE_FILE] = { clear = 6 / 128, texels = 116 },
      [CIRCLE_FILE] = { clear = 0, texels = 128 },
      [FLAT] = { clear = 0, texels = 8 },
    }
    -- The only texture files a sweep may use: standalone images, decoded and checked
    -- (an atlas name, or a sheet holding other images, would stretch the whole sheet).
    local STANDALONE = { [SWIPE_FILE] = true, [CIRCLE_FILE] = true }
    local function SweepArt(cd, name)
      check(rawget(cd, "template") == "CooldownFrameTemplate", name .. " sweep made from CooldownFrameTemplate")
      local tex = rawget(cd, "swipe")
      check(tex == nil or STANDALONE[tex], name .. " sweep texture is a standalone image: " .. tostring(tex))
      check(rawget(cd, "drawSwipe") ~= false, name .. " sweep drawn")
    end
    local function Hidden(list, what, name)
      for _, piece in ipairs(list or {}) do check(rawget(piece, "alpha") == 0, name .. " " .. what .. " hidden") end
    end
    local function Icon(b, look)
      local name, icon, cd = rawget(b, "name"), b.icon, rawget(b, "cd")
      local frame, pushed, hl, barMask = rawget(b, "fgFrame"), rawget(b, "fgPushed"), rawget(b, "fgHighlight"), rawget(b, "fgMask")
      local square, circle = rawget(b, "fgSquare"), rawget(b, "fgCircle")
      local masks = Masks(icon)
      if T.atlas then check(frame and pushed and hl and barMask, name .. " was built with the bar art") end
      check((rawget(b, "fgShape") or "bar") == look, name .. " look " .. look .. ", got " .. tostring(rawget(b, "fgShape")))
      if look ~= "square" and square then Hidden(square.added, "square edge", name) end
      if look:sub(1, 6) ~= "circle" and circle then Hidden(circle.all, "circle art", name) end
      local function Art(alpha)
        for _, art in ipairs({ frame or false, pushed or false, hl or false }) do
          if art then check((rawget(art, "alpha") or 1) == alpha, name .. " bar art alpha " .. alpha) end
        end
      end
      if look == "bar" then
        if T.atlas then check(#masks == 1 and masks[1] == barMask, name .. " the bar's mask only, " .. #masks .. " masks") end
        Art(1)
        if square or circle then
          check(Same(rawget(icon, "coords") or {}, rawget(b, "fgRound") or {}), name .. " icon back to its round crop")
        else
          check(not T.darkCalls[icon] and not (T.skinned and T.skinned[icon]), name .. " never restyled")
        end
        if cd then
          SweepArt(cd, name)
          local pts = rawget(cd, "_points") or {}
          -- The Cooldown's own color swipe, as the game's action buttons use it: the
          -- Cooldown Manager's swipe art left the left side unswept on this client.
          local c = rawget(cd, "swipeColor") or {}
          check(rawget(cd, "swipe") == nil and rawget(cd, "_all") == nil and not rawget(cd, "circularEdge"), name .. " no swipe texture on the action bar look: " .. tostring(rawget(cd, "swipe")))
          check(c[1] == 0 and c[2] == 0 and c[3] == 0 and c[4] == 0.75 and rawget(cd, "fgSweep") == "color", name .. " a black color swipe at 0.75, noted as color")
          check(pts.TOPLEFT and pts.TOPLEFT[2] == 2 and pts.TOPLEFT[3] == -2 and pts.BOTTOMRIGHT and pts.BOTTOMRIGHT[2] == -3 and pts.BOTTOMRIGHT[3] == 2.5
            and pts.CENTER == nil, name .. " the bar look's own inset, 2 px top and left, 3 right, 2.5 bottom")
        end
      elseif look == "square" then
        check(#masks == 0 and square, name .. " square, no mask")
        Art(0)
        local c = { icon:GetTexCoord() }
        check(c[1] == 0.08 and c[4] == 0.92, name .. " icon cropped square")
        if ${drawer === 'eui'} then
          check(T.did(icon, "SquareIcon"), name .. " squared by EllesmereUI")
          check(#square.added == 5, name .. " EllesmereUI's edge and the flat highlight added: " .. #square.added)
        else
          check((T.darkCalls[icon] or ""):find("SquareIcon", 1, true), name .. " squared by Dark")
          check(#square.added == 5, name .. " edge and flat highlight added: " .. #square.added)
        end
        for _, piece in ipairs(square.added) do check(rawget(piece, "alpha") == 1, name .. " square edge shown") end
        if cd then
          SweepArt(cd, name)
          check(not rawget(cd, "circularEdge") and (rawget(cd, "_points") or {}).CENTER == nil, name .. " no circle settings on a square")
          -- The Cooldown's own color swipe fills its frame whatever its size, and the
          -- frame is the icon exactly: no texture at all, so nothing can stretch.
          check(rawget(cd, "_all") == icon and rawget(cd, "_points") == nil, name .. " the sweep frame is the icon, all four edges")
          check(rawget(cd, "swipeSet") and rawget(cd, "swipe") == nil, name .. " no swipe texture on the square look: " .. tostring(rawget(cd, "swipe")))
          local c = rawget(cd, "swipeColor") or {}
          check(c[1] == 0 and c[2] == 0 and c[3] == 0 and c[4] == 0.75, name .. " a black color swipe at 0.75")
          check(rawget(cd, "fgSweep") == "color", name .. " noted for debug: " .. tostring(rawget(cd, "fgSweep")))
        end
      else
        local ringed = look == "circle-ring"
        check(circle and #masks == 1 and masks[1] == circle.mask, name .. " the circle mask only, " .. #masks .. " masks")
        if T.atlas then check(rawget(circle.mask, "atlas") == "CircleMaskScalable", name .. " circle mask atlas")
        else check(rawget(circle.mask, "texture") == CIRCLE_FILE, name .. " circle mask texture") end
        Art(0)
        check(Same(rawget(icon, "coords") or {}, { 0.08, 0.92, 0.08, 0.92 }), name .. " cropped before the mask")
        local d = ringed and circle.ringSize or 36
        check(rawget(circle.mask, "_w") == d and rawget(circle.mask, "_h") == d, name .. " circle " .. d .. " across, got " .. tostring(rawget(circle.mask, "_w")))
        check(rawget(circle.ring, "texture") == RING_FILE and rawget(circle.ring, "alpha") == (ringed and 1 or 0), name .. " minimap ring " .. (ringed and "shown" or "hidden"))
        check(rawget(circle.edge, "alpha") == (ringed and 0 or 1), name .. " dark edge " .. (ringed and "hidden" or "shown"))
        -- The ring texture is 64 across with its circle off centre: scaled by 36/32, its
        -- centre (20.05, 18.92) lands on the icon's.
        local rp = rawget(circle.ring, "_point")
        check(rawget(circle.ring, "_w") == 72 and rp[1] == "TOPLEFT" and rp[2] == icon and rp[3] == "CENTER"
          and math.abs(rp[4] + 22.56) < 0.01 and math.abs(rp[5] - 21.29) < 0.01, name .. " ring centred on the icon")
        check(circle.ringSize == 30, name .. " picture 30 across inside the ring, got " .. tostring(circle.ringSize))
        -- Flat colors under circle masks: the alpha is the color's own, with plain blending.
        local function Under(tex, mask) for _, m in ipairs(Masks(tex)) do if m == mask then return true end end return false end
        local ec, hc, pc = rawget(circle.edge, "color"), rawget(circle.hl, "color"), rawget(circle.press, "color")
        check(ec and Same(ec, { 0, 0, 0, 1 }) and rawget(circle.edge, "blend") == "BLEND", name .. " dark edge a black disc")
        check(Under(circle.edge, circle.edgeMask) and rawget(circle.edgeMask, "_w") == 38 and rawget(circle.edge, "_w") == 38, name .. " dark edge one pixel past the circle")
        check(rawget(circle.hl, "texture") == nil and rawget(circle.hl, "vertex") == nil, name .. " highlight is not a tinted circle texture")
        check(hc and hc[1] == 1 and hc[4] <= 0.2 and rawget(circle.hl, "blend") == "BLEND", name .. " highlight a faint lightening: " .. tostring(hc and hc[4]))
        check(Under(circle.hl, circle.mask) and rawget(circle.hl, "alpha") == 1, name .. " round highlight, in the picture's circle")
        check(pc and pc[1] == 0 and pc[4] <= 0.35 and rawget(circle.press, "blend") == "BLEND", name .. " press a faint darkening: " .. tostring(pc and pc[4]))
        check(Under(circle.press, circle.mask) and rawget(circle.press, "alpha") == 0, name .. " press art waits for a press")
        if cd then
          SweepArt(cd, name)
          check(rawget(cd, "swipe") == CIRCLE_FILE and rawget(cd, "circularEdge") == true, name .. " circular sweep")
          local pts = rawget(cd, "_points") or {}
          check(rawget(cd, "_all") == nil and rawget(cd, "_w") == d and pts.CENTER and pts.CENTER[2] == icon and pts.CENTER[3] == "CENTER"
            and pts.TOPLEFT == nil and pts.BOTTOMRIGHT == nil, name .. " sweep the size of the circle, on its center")
        end
      end
      local glow = rawget(b, "glow")
      if glow then
        check(rawget(glow, "alpha") == nil, name .. " shimmer's own alpha left to its animation")
        local roundGlow = circle and circle.glow
        local lit = rawget(b, "lit") and true or false
        local vertex = rawget(glow, "vertex")
        if look:sub(1, 6) == "circle" and T.atlas then
          check(roundGlow and rawget(roundGlow, "atlas") == "dragonflight-landingbutton-circleglow", name .. " round glow from the client's circle glow")
          -- Its bright band (0.413 of its width) 2 px outside the gold (18) or the edge (19).
          local across = look == "circle-ring" and 48 or 51
          check(rawget(roundGlow, "_w") == across and rawget(roundGlow, "_h") == across, name .. " round glow " .. across .. " across, got " .. tostring(rawget(roundGlow, "_w")))
          -- The ring in the art sits at 0.5001, 0.4898 of it, so the art moves to put that on the icon's center.
          local gp = rawget(roundGlow, "_point")
          check(gp and gp[1] == "CENTER" and gp[2] == icon and gp[3] == "CENTER"
            and math.abs(gp[4] - (0.5 - 0.5001) * across) < 0.001 and math.abs(gp[5] - (0.4898 - 0.5) * across) < 0.001,
            name .. " round glow's ring on the icon's center: " .. tostring(gp and gp[4]) .. ", " .. tostring(gp and gp[5]))
          -- Settled: shown, pulsing and at full alpha on the tracker that is on; faded out and stopped elsewhere.
          local rv = rawget(roundGlow, "vertex") or {}
          check(rawget(roundGlow, "shown") == lit and rawget(circle.glowAnim, "playing") == lit and rv[4] == (lit and 1 or 0),
            name .. " round glow " .. (lit and "on" or "off") .. " with the tracker")
          check(vertex and vertex[4] == 0 and not rawget(glow, "shown"), name .. " square shimmer faded out under the round glow")
        else
          if roundGlow then check(not rawget(roundGlow, "shown") and not rawget(circle.glowAnim, "playing"), name .. " round glow off outside Round") end
          check(vertex and vertex[4] == (lit and 1 or 0) and (rawget(glow, "shown") or false) == lit,
            name .. " square shimmer " .. (lit and "shown" or "faded out") .. " with the tracker")
        end
      end
    end
    check(#NS.trackButtons >= 2, "tracker icons built: " .. #NS.trackButtons)
    for _, b in ipairs(NS.trackButtons) do Icon(b, "${look}") end
    Icon(ForagerPauseButton, "${pause}")
    -- The play and stop symbols stay readable on top, whatever the look.
    local p = ForagerPauseButton
    check(rawget(p.play, "alpha") ~= 0 and rawget(p.stop, "alpha") ~= 0, "pause symbols not faded")
    if "${pause}" == "circle-ring" then
      check(rawget(p.fgCircle, "ringSize") >= 36 * 26 / 42, "the stop symbol fits inside the ring")
    end
    -- The tracker that is on still glows, and the next one still sweeps.
    local lit, sweeping = 0, 0
    for _, b in ipairs(NS.trackButtons) do
      if rawget(b, "lit") then
        lit = lit + 1
        local c = rawget(b, "fgCircle")
        local roundOn = c and c.glow and rawget(c.glow, "shown")
        check((b.glow.shown and b.anim.playing) or (roundOn and rawget(c.glowAnim, "playing")), "glow on the tracker that is on")
      end
      if rawget(b.cd, "shown") then sweeping = sweeping + 1 end
    end
    check(lit == 1 and sweeping == 1, "one glowing, one sweeping: " .. lit .. ", " .. sweeping)
  end
`;
}
// Sparkles: forty ticks of the bar (time standing still, so the tracker does
// not change), finishing each spark after its tick so the pool never runs
// dry. Only tracker `active` may have sparks out; each starts on `look`'s
// border, drifts 4 to 8 px straight out, in star4 with ADD blending, in the
// same layer as the border art and just below it.
const SPARK_HELPERS = `
  function T.sparksOut(b) local n = 0 for _, s in ipairs(rawget(b, "fgSparks") or {}) do if rawget(s.anim, "playing") then n = n + 1 end end return n end
  function T.finishSparks()
    for _, b in ipairs(NS.trackButtons) do
      for _, s in ipairs(rawget(b, "fgSparks") or {}) do
        if rawget(s.anim, "playing") then s.anim.playing = false local f = s.anim.scripts.OnFinished if f then f(s.anim) end end
      end
    end
  end
  function T.sparkTicks(n, watch)
    local launched = 0
    for _ = 1, n do
      T.ticker()
      for _, b in ipairs(NS.trackButtons) do
        if T.sparksOut(b) > 0 then
          if watch then watch(b) end
          launched = launched + T.sparksOut(b)
        end
      end
      T.finishSparks()
    end
    return launched
  end
`;
function SPARKS(look, active) {
  return SPARK_HELPERS + `
  do
    local look, active = "${look}", ForagerTrackButton${active}
    local icon = active.icon
    local circle, square = rawget(active, "fgCircle"), rawget(active, "fgSquare")
    local borders = {}
    if look == "bar" then borders = { rawget(active, "fgFrame") }
    elseif look == "circle-ring" then borders = { circle.ring }
    elseif look == "circle-edge" then borders = { circle.edge }
    else for _, piece in ipairs(square.added) do if rawget(piece, "_layer") ~= "HIGHLIGHT" then borders[#borders + 1] = piece end end end
    check(#borders >= 1, look .. ": found the border art")
    local starts = 0
    local launched = T.sparkTicks(40, function(b)
      check(b == active, "only the active tracker sparkles, not " .. tostring(rawget(b, "name")))
      for _, s in ipairs(b.fgSparks) do
        if rawget(s.anim, "playing") then
          starts = starts + 1
          local tex, p, o = s.tex, rawget(s.tex, "_point"), rawget(s.move, "offset")
          local art = T.atlas and rawget(tex, "atlas") == "bonusobjectives-bar-starburst"
            or not T.atlas and rawget(tex, "texture") == "Interface\\\\Cooldown\\\\star4"
          local v = rawget(tex, "vertex") or {}
          check(art and rawget(tex, "blend") == "ADD" and v[1] == 1 and v[2] == 0.82 and v[3] == 0.35,
            "a gold star, added: " .. tostring(rawget(tex, "atlas") or rawget(tex, "texture")))
          check(p[1] == "CENTER" and p[2] == icon and p[3] == "CENTER", "placed from the icon's center")
          local x, y, ox, oy = p[4], p[5], o[1], o[2]
          local drift = math.sqrt(ox * ox + oy * oy)
          check(drift >= 4 - 1e-6 and drift <= 8 + 1e-6, "drifts 4 to 8 px, got " .. drift)
          if look:sub(1, 6) == "circle" then
            local r = math.sqrt(x * x + y * y)
            local want = look == "circle-ring" and 18 or 19
            check(math.abs(r - want) < 1e-6, look .. ": starts on the rim (" .. want .. "), got " .. r)
            check(math.abs(ox * y - oy * x) < 1e-6 and ox * x + oy * y > 0, look .. ": drifts straight out from the center")
          else
            check(math.abs(math.max(math.abs(x), math.abs(y)) - 18) < 1e-6, look .. ": starts on the square's edge")
            if math.abs(math.abs(y) - 18) < 1e-6 and math.abs(x) < 18 then
              check(math.abs(ox) < 1e-6 and oy * y > 0, look .. ": out across the top or bottom")
            else
              check(math.abs(oy) < 1e-6 and ox * x > 0, look .. ": out across a side")
            end
          end
          for _, border in ipairs(borders) do
            check(rawget(tex, "_layer") == rawget(border, "_layer") and rawget(tex, "_sub") < rawget(border, "_sub"),
              look .. ": just behind the border art, " .. tostring(rawget(tex, "_layer")) .. " " .. tostring(rawget(tex, "_sub"))
              .. " under " .. tostring(rawget(border, "_layer")) .. " " .. tostring(rawget(border, "_sub")))
          end
        end
      end
    end)
    check(launched >= 5 and launched <= 40, "a few at a time: " .. launched .. " in 40 ticks")
    check(#active.fgSparks == 6, "six sparks in the pool")
  end
`;
}
// The glitter model, settled (frames run past the fade first): at most two
// ModelScenes, parented to the bar at the bar's own level so every icon (one
// above) draws in front; the one on tracker `active` is shown at full (actor
// 0.75, scene 1); any other is faded out and hidden. Each is 104 across with
// the camera placing the glitter just past the ring, one actor at its center
// carrying model `id`; and no drawn sparkles anywhere.
const SCENES = `
  function T.scenes()
    local list = {}
    for _, f in ipairs(T.frames) do if rawget(f, "kind") == "ModelScene" then list[#list + 1] = f end end
    return list
  end
`;
function MODEL(active, id) {
  return SCENES + `
  T.frame(0.6)
  do
    local scenes = T.scenes()
    check(#scenes >= 1 and #scenes <= 2, "one or two model scenes, never more: " .. #scenes)
    local b = ForagerTrackButton${active}
    local want
    for _, e in ipairs(NS.SPARK_MODELS) do if e.id == ${id} then want = e end end
    check(want ~= nil, "model ${id} is one of the effects")
    local on = 0
    for _, scene in ipairs(scenes) do
      local p = rawget(scene, "_point")
      local actor = scene.actors[1]
      if rawget(scene, "shown") then
        on = on + 1
        check(p and p[1] == "CENTER" and p[2] == b.icon and p[3] == "CENTER", "the glitter shown is on tracker ${active}")
        -- Fully faded in: the effect's own strength times the Sparkle intensity.
        local full = want.alpha * ForagerDB.sparkleIntensity / 100
        check(math.abs(actor.actorAlpha - full) < 1e-9 and math.abs((rawget(scene, "alpha") or 0) - (full > 0 and 1 or 0)) < 1e-6,
          "fully faded in: " .. tostring(actor.actorAlpha) .. " of " .. full)
      else
        check(actor.actorAlpha == 0 and (rawget(scene, "alpha") or 0) == 0, "a hidden scene is fully faded out")
      end
      check(rawget(scene, "parent") == ForagerBar and scene:GetFrameLevel() == ForagerBar:GetFrameLevel(), "at the bar's own level")
      for _, button in ipairs(NS.trackButtons) do
        check(scene:GetFrameLevel() < button:GetFrameLevel(), "behind " .. rawget(button, "name"))
      end
      check(scene:GetFrameLevel() < ForagerPauseButton:GetFrameLevel(), "behind the pause button")
      check(rawget(scene, "mouse") == false, "never takes the mouse")
      local cam = scene.cam
      check(cam.pos and cam.pos[2] == 0 and cam.pos[3] == 0 and cam.fov == 0.6, "camera placed straight on")
      -- Where the effect's spread lands on screen: the scene shows tan(fov / 2) * distance
      -- yards from its center to its edge. A hidden scene may still carry the last effect.
      local w, h = rawget(scene, "_w"), rawget(scene, "_h")
      -- The reach is 31 px at Sparkle size 100%; the scene grows to stay 12 px past it.
      local wantReach = 31 * ForagerDB.sparkleSize / 100
      local wantScene = math.max(104, math.ceil(2 * (wantReach + 12)))
      check(w == wantScene and h == wantScene, "the scene is " .. wantScene .. " across, got " .. tostring(w))
      local yards = want.yards
      if not rawget(scene, "shown") then for _, e in ipairs(NS.SPARK_MODELS) do if e.id == actor.model then yards = e.yards end end end
      local reach = yards * (h / 2) / (math.tan(cam.fov / 2) * cam.pos[1])
      check(math.abs(reach - wantReach) < 1e-6, "the glitter reaches " .. wantReach .. " px, got " .. reach)
      check(h / 2 >= reach + 12, "the scene's edge is well clear of the glitter")
      check(#scene.actors == 1, "one actor")
      if rawget(scene, "shown") then check(actor.model == ${id}, "model ${id}, got " .. tostring(actor.model)) end
      check(actor.pos and actor.pos[1] == 0 and actor.pos[2] == 0 and actor.pos[3] == 0, "at the center")
    end
    check(on == 1, "exactly one glitter shown: " .. on)
    for _, button in ipairs(NS.trackButtons) do
      check(rawget(button, "fgSparks") == nil, "no drawn sparkles alongside the model")
    end
    check(NS.SparklePath() == "model", "the model is the path in use")
  end
`;
}
// Settled after the fade: every scene hidden and faded out.
const MODEL_OFF = SCENES + `
  T.frame(0.6)
  do
    for _, scene in ipairs(T.scenes()) do
      check(rawget(scene, "shown") == false and scene.actors[1].actorAlpha == 0, "the glitter faded out and hidden")
    end
  end
`;
const WINDOW_DRAWN = `
  do
    local win = ForagerOptions
    check(T.drawnSince(SNAP, win) == 11, "window: backdrop, title strip, accent rule, edges (" .. T.drawnSince(SNAP, win) .. ")")
    check(T.drawnSince(SNAP, win.CloseButton) == 2, "close button X")
    check(win.CloseButton:GetFrameLevel() > 1 and win.TitleContainer:GetFrameLevel() > 1, "title bar and close button raised")
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  end
`;
function SLIDER(dark) {
  return `
    do
      local sl = NS.opacitySlider
      check(rawget(sl, "enabled") == ${dark} and rawget(sl, "alpha") == ${dark ? 1 : 0.5}, "slider ${dark ? 'live' : 'grayed'}")
      check(rawget(sl.fgCaption, "font") == ${dark ? 'GameFontHighlight' : 'GameFontDisable'}
        and rawget(sl.fgValue, "font") == ${dark ? 'GameFontNormalSmall' : 'GameFontDisable'}, "slider labels ${dark ? 'normal' : 'grayed'}")
    end
  `;
}
function STYLE_BUTTON(name) {
  return `
    check(rawget(NS.styleButton, "text") == "Window style: ${name}", "style button: " .. tostring(rawget(NS.styleButton, "text")))
  `;
}

if (!EUI_ON) {
  run('Blizzard: nothing is drawn, and debug says why', OPEN + `
    check(ForagerDB.style == "auto" and ForagerDB.darkAlpha == 0.92, "defaults: auto, 0.92")
    SNAP = T.drawSnapshot()
    T.fire("PLAYER_ENTERING_WORLD")
    check(NS.Styles.S == nil and NS.Styles.Applied() == nil, "no style applied")
    check(NS.report.skin == "Blizzard (EllesmereUI is not loaded)", "status: " .. tostring(NS.report.skin))
    for _, f in ipairs(T.frames) do check(T.drawnSince(SNAP, f) == 0, "nothing drawn on " .. tostring(rawget(f, "name") or "a frame")) end
    SlashCmdList.FORAGER("debug")
    local seen = false for _, m in ipairs(T.prints) do if m:find("skin: Blizzard (EllesmereUI is not loaded)", 1, true) then seen = true end end
    check(seen, "debug says why")
  ` + SLIDER(false) + STYLE_BUTTON('Automatic'));
  run('Dark chosen in the options: the window drawn at once, slider live, reload offered on leaving', OPEN + `
    T.advance(6.5) -- the tracker icons are up
    SNAP = T.drawSnapshot()
    local button = NS.styleButton
    button.scripts.OnClick(button, "LeftButton")
    check(ForagerDB.style == "blizzard", "left-click: Blizzard")
  ` + SLIDER(false) + `
    button.scripts.OnClick(button, "LeftButton")
    check(ForagerDB.style == "dark" and NS.Styles.Applied() == "dark" and NS.report.skin == "Dark", "Dark applied: " .. tostring(NS.report.skin))
    check(not (ForagerReloadPrompt and ForagerReloadPrompt.shown), "no reload prompt from Blizzard to Dark")
  ` + WINDOW_DRAWN + ONLY_WINDOW_DRAWN + ICONS('square') + SLIDER(true) + STYLE_BUTTON('Dark') + `
    local bg = rawget(ForagerOptions, "texs")[SNAP[ForagerOptions] + 1]
    check(bg.color[4] == 0.92, "backdrop opacity from the settings: " .. tostring(bg.color[4]))
    local sl = NS.opacitySlider
    sl.scripts.OnValueChanged(sl, 61)
    check(ForagerDB.darkAlpha == 0.6 and bg.color[4] == 0.6, "slider sets the opacity live, in steps of 5")
    check(rawget(sl.fgValue, "text") == "60%", "value shown: " .. tostring(rawget(sl.fgValue, "text")))
    local rule = rawget(ForagerOptions, "texs")[SNAP[ForagerOptions] + 3]
    check(rule.color[1] == 0.5 and rule.color[2] == 0.85 and rule.color[3] == 0.42, "accent rule in Forager green")
    button.scripts.OnClick(button, "RightButton")
    check(ForagerDB.style == "blizzard", "right-click goes back")
    check(ForagerReloadPrompt and ForagerReloadPrompt.shown, "leaving Dark offers a reload")
    check(ForagerReloadPrompt.text.text:find("Forager to Blizzard", 1, true), "prompt says what: " .. tostring(ForagerReloadPrompt.text.text))
    check(T.drawnSince(SNAP, ForagerReloadPrompt) == 11, "the prompt is drawn Dark too")
    check(NS.report.skin == "Dark, Blizzard after a /reload", "status: " .. tostring(NS.report.skin))
    check(NS.Styles.Note():find("/reload", 1, true), "the note line says so")
  ` + SLIDER(false) + `
    C_UI = { Reload = function() T.reloaded = true end }
    ForagerReloadPrompt.reload.scripts.OnClick(ForagerReloadPrompt.reload)
    check(T.reloaded, "Reload now reloads")
    button.scripts.OnClick(button, "LeftButton")
    check(not ForagerReloadPrompt.shown and NS.report.skin == "Dark", "back to Dark: prompt gone, nothing pending")
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  `);
  run('Dark saved: drawn on the window when it is first built', `
    T.fire("PLAYER_ENTERING_WORLD")
    check(NS.Styles.Applied() == "dark", "Dark applied at login")
    check(ForagerOptions == nil, "window not built yet")
    SNAP = T.drawSnapshot()
  ` + OPEN + WINDOW_DRAWN + ONLY_WINDOW_DRAWN + SLIDER(true) + STYLE_BUTTON('Dark'), { db: '{ style = "dark" }' });
  run('tracker icons: Blizzard keeps the action bar art, also on icons built later', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    ForagerDB.rotation[1494] = true
    T.advance(1)
    check(ForagerTrackButton3 ~= nil, "a third icon built for the new tracker")
  ` + ICONS('bar'), { atlas: true });
  run('tracker icons: Dark squares them, keeps the glow and sweep, and icons built later follow', `
    T.fire("PLAYER_ENTERING_WORLD")
    check(NS.Styles.Applied() == "dark", "Dark applied")
    check(ForagerTrackButton1 and ForagerTrackButton1.fgShape == "square", "icons built at login restyled")
    T.advance(6.5)
    check(T.active() == "Find Herbs", "herbs on")
    ForagerDB.rotation[1494] = true
    T.advance(1)
    check(ForagerTrackButton3 ~= nil, "a third icon built for the new tracker")
  ` + ICONS('square') + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
    SNAP = T.drawSnapshot()
    T.advance(6.5)
    check(T.active() == "Find Minerals", "the rotation goes on")
    for _, b in ipairs(NS.trackButtons) do
      -- The sparkles' own textures come with the first time a tracker is on.
      local isSpark = {}
      for _, spark in ipairs(rawget(b, "fgSparks") or {}) do isSpark[spark.tex] = true end
      local texs, new = rawget(b, "texs") or {}, 0
      for i = (SNAP[b] or 0) + 1, #texs do if not isSpark[texs[i]] then new = new + 1 end end
      check(new == 0, rawget(b, "name") .. " not drawn on twice")
    end
  ` + ICONS('square'), { atlas: true, db: '{ style = "dark" }' });
  run('icon shape: Square under Blizzard and back to Round, live', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + OPEN + `
    local shape = NS.shapeButton
    check(rawget(shape, "text") == "Icon shape: Automatic", "shape button: " .. tostring(rawget(shape, "text")))
  ` + ICONS('bar') + `
    shape.scripts.OnClick(shape, "LeftButton")
    check(ForagerDB.iconShape == "round" and rawget(shape, "text") == "Icon shape: Round", "left-click: Round")
  ` + ICONS('circle-ring') + `
    shape.scripts.OnClick(shape, "LeftButton")
    check(ForagerDB.iconShape == "square" and rawget(shape, "text") == "Icon shape: Square", "left-click again: Square")
    check(NS.Styles.Applied() == nil, "still the Blizzard style")
    check(ForagerReloadPrompt == nil, "no reload needed")
  ` + ICONS('square', 'dark', 'bar') + `
    ForagerDB.rotation[1494] = true
    T.advance(1)
    check(ForagerTrackButton3 ~= nil, "a third icon built for the new tracker")
  ` + ICONS('square', 'dark', 'bar') + `
    shape.scripts.OnClick(shape, "RightButton")
    check(ForagerDB.iconShape == "round", "right-click: back to Round")
  ` + ICONS('circle-ring') + `
    SlashCmdList.FORAGER("shape square")
  ` + ICONS('square', 'dark', 'bar') + `
    SlashCmdList.FORAGER("shape auto")
  ` + ICONS('bar') + `
    SlashCmdList.FORAGER("shape round")
    local b = ForagerTrackButton1
    b.scripts.OnMouseDown(b, "LeftButton")
    check(rawget(b.fgCircle.press, "alpha") == 1, "a press darkens the circle")
    b.scripts.OnMouseUp(b, "LeftButton")
    check(rawget(b.fgCircle.press, "alpha") == 0, "and lets go")
    SlashCmdList.FORAGER("shape square")
    b.scripts.OnMouseDown(b, "LeftButton")
    check(rawget(b.fgCircle.press, "alpha") == 0, "no round press art on a square icon")
    b.scripts.OnMouseUp(b, "LeftButton")
    SlashCmdList.FORAGER("shape round")
  ` + ICONS('circle-ring') + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  `, { atlas: true });
  run('icon shape: Round under Dark, live, the pause button round with the trackers', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + OPEN + ICONS('square') + `
    local shape = NS.shapeButton
    shape.scripts.OnClick(shape, "LeftButton")
    check(ForagerDB.iconShape == "round", "Round chosen")
    check(NS.Styles.Applied() == "dark", "still Dark")
  ` + ICONS('circle-edge') + `
    ForagerDB.rotation[1494] = true
    T.advance(1)
    check(ForagerTrackButton3 ~= nil and rawget(ForagerTrackButton3, "fgShape") == "circle-edge", "an icon built later comes round")
  ` + ICONS('circle-edge') + `
    shape.scripts.OnClick(shape, "LeftButton")
    check(ForagerDB.iconShape == "square", "Square chosen")
  ` + ICONS('square') + `
    shape.scripts.OnClick(shape, "LeftButton")
    check(ForagerDB.iconShape == "auto", "back to Automatic")
  ` + ICONS('square') + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  `, { atlas: true, db: '{ style = "dark" }' });
  run('icon shape: Round saved under Dark: trackers and the pause button round at login', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    check(NS.Styles.Applied() == "dark", "Dark")
  ` + ICONS('circle-edge'), { atlas: true, db: '{ style = "dark", iconShape = "round" }' });
  run('a failed icon shape lands in the saved log', `
    T.advance(6.5)
    local real = Frame.SetTexCoord
    Frame.SetTexCoord = function() error("refused") end
    SlashCmdList.FORAGER("shape square")
    Frame.SetTexCoord = real
    local found = false
    for _, line in ipairs(ForagerLog.lines) do if line:find("tracker icon square failed", 1, true) then found = true end end
    check(found, "logged for reading after a /reload")
  `, { atlas: true });
  run('icon shape: Round follows a style drawn live, the ring giving way to the dark edge', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    SlashCmdList.FORAGER("shape round")
  ` + ICONS('circle-ring') + `
    SlashCmdList.FORAGER("style dark")
  ` + ICONS('circle-edge') + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  `, { atlas: true });
  run('icon shape: the round glow moves to the tracker that comes on', `
    T.fire("PLAYER_ENTERING_WORLD")
    SlashCmdList.FORAGER("shape round")
    T.advance(6.5)
    check(T.active() == "Find Herbs", "herbs on")
  ` + ICONS('circle-ring') + `
    check(rawget(ForagerTrackButton1.fgCircle.glow, "shown") == true, "herbs glows round")
    T.advance(6.5)
    check(T.active() == "Find Minerals", "minerals on")
  ` + ICONS('circle-ring') + `
    check(rawget(ForagerTrackButton2.fgCircle.glow, "shown") == true and rawget(ForagerTrackButton1.fgCircle.glow, "shown") == false, "the round glow moved to minerals")
    SlashCmdList.FORAGER("shape auto")
  ` + ICONS('bar') + `
    check(rawget(ForagerTrackButton2.glow, "shown") == true and rawget(ForagerTrackButton2.glow, "vertex")[4] == 1, "the shimmer back on minerals")
  `, { atlas: true });
  run('sparkles: a real glitter model behind the active tracker, and debug says so', `
    T.fire("PLAYER_ENTERING_WORLD")
    check(NS.SparklePath() == "not started", "nothing made at login")
    T.advance(6.5)
    check(T.active() == "Find Herbs", "herbs on")
  ` + MODEL(1, 166336) + `
    SlashCmdList.FORAGER("debug")
    local seen = false
    for _, m in ipairs(T.prints) do if m:find("sparkles on: model, spells/holy_precast_low_hand.m2 (166336)", 1, true) then seen = true end end
    check(seen, "debug names the model")
    local before = #T.prints
    SlashCmdList.FORAGER("debug icons")
    check(T.prints[before + 1]:find("glitter 1 (spells/holy_precast_low_hand.m2)", 1, true), "debug icons shows it: " .. T.prints[before + 1])
  `, { atlas: true });
  run('sparkles: the glitter model follows the active tracker', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + MODEL(1, 166336) + `
    T.advance(6.5)
    check(T.active() == "Find Minerals", "minerals on")
  ` + MODEL(2, 166336), { atlas: true });
  run('sparkles: the glitter model stops when paused, hidden, hidden in combat, or switched off', OPEN + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + MODEL(1, 166336) + `
    SlashCmdList.FORAGER("off")
  ` + MODEL_OFF + `
    SlashCmdList.FORAGER("on")
  ` + MODEL(1, 166336) + `
    SlashCmdList.FORAGER("sparkles")
    check(ForagerDB.sparkles == false, "the command turns them off")
  ` + MODEL_OFF + `
    local box
    for _, f in ipairs(T.frames) do local l = rawget(f, "label") if type(l) == "table" and rawget(l, "text") == "Sparkles on the active tracker" then box = f end end
    box.checked = true box.scripts.OnClick(box)
    check(ForagerDB.sparkles == true, "the option turns them on")
  ` + MODEL(1, 166336) + `
    SlashCmdList.FORAGER("icons")
  ` + MODEL_OFF + `
    SlashCmdList.FORAGER("icons")
    ForagerDB.barHideCombat = true
    T.combat = true
    T.ticker()
  ` + MODEL_OFF + `
    T.combat = false
    T.ticker()
  ` + MODEL(1, 166336), { atlas: true });
  run('sparkles: the glitter model in every shape and style', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    SlashCmdList.FORAGER("shape round")
  ` + MODEL(1, 166336) + `
    SlashCmdList.FORAGER("shape square")
  ` + MODEL(1, 166336) + `
    SlashCmdList.FORAGER("style dark")
    SlashCmdList.FORAGER("shape round")
  ` + MODEL(1, 166336) + `
    SlashCmdList.FORAGER("shape auto")
  ` + MODEL(1, 166336) + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  `, { atlas: true });
  // Steps the clock a quarter second at a time until the tracker changes; the
  // fades are then 0.25 s into their 0.4 s.
  const TO_NEXT = `
    local was = T.active()
    for _ = 1, 40 do T.advance(0.25) if T.active() ~= was then break end end
    check(T.active() ~= was, "the next tracker came on")
  `;
  // The four marks on a tracker: its glitter scene, shimmer, round glow (if any).
  const FADE_HELPERS = SCENES + `
    function T.sceneOn(button)
      for _, scene in ipairs(T.scenes()) do
        local p = rawget(scene, "_point")
        if rawget(scene, "shown") and p and p[2] == button.icon then return scene end
      end
    end
    function T.va(tex) local v = rawget(tex, "vertex") return v and v[4] end
  `;
  run('crossfade: on a tracker change the glitter and the shimmer fade out on the old while they fade in on the new', FADE_HELPERS + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + MODEL(1, 166336) + TO_NEXT + `
    local old, new = T.sceneOn(ForagerTrackButton1), T.sceneOn(ForagerTrackButton2)
    check(old and new and old ~= new, "both glitters showing mid-fade, on their own trackers")
    local oa, na = old.actors[1].actorAlpha, new.actors[1].actorAlpha
    check(oa > 0 and oa < 0.75 and na > 0 and na < 0.75, "both part way: " .. oa .. ", " .. na)
    local os, ns_ = T.va(ForagerTrackButton1.glow), T.va(ForagerTrackButton2.glow)
    check(os > 0 and os < 1 and ns_ > 0 and ns_ < 1, "both shimmers part way: " .. os .. ", " .. ns_)
    check(rawget(ForagerTrackButton1.glow, "shown") and rawget(ForagerTrackButton1.anim, "playing"), "the old shimmer keeps its flipbook while it fades")
    check(rawget(ForagerTrackButton2.glow, "shown") and rawget(ForagerTrackButton2.anim, "playing"), "the new shimmer plays as it fades in")
    T.frame(0.05)
    check(old.actors[1].actorAlpha < oa and new.actors[1].actorAlpha > na, "the old glitter goes down while the new one comes up")
    check(T.va(ForagerTrackButton1.glow) < os and T.va(ForagerTrackButton2.glow) > ns_, "the old shimmer goes down while the new one comes up")
    check(rawget(old, "shown"), "the old glitter is not hidden before it has faded out")
    T.frame(0.5)
    check(rawget(old, "shown") == false and old.actors[1].actorAlpha == 0, "the old glitter hidden once faded out")
    check(rawget(ForagerTrackButton1.glow, "shown") == false and not rawget(ForagerTrackButton1.anim, "playing") and T.va(ForagerTrackButton1.glow) == 0, "the old shimmer faded out and stopped")
    check(T.va(ForagerTrackButton2.glow) == 1 and new.actors[1].actorAlpha == 0.75, "the new one at full")
  ` + MODEL(2, 166336) + TO_NEXT + MODEL(1, 166336) + TO_NEXT + `
    check(#T.scenes() == 2, "never a third scene, however many changes")
  `, { atlas: true });
  run('crossfade: the round glow fades the same way, its pulse running', FADE_HELPERS + `
    T.fire("PLAYER_ENTERING_WORLD")
    SlashCmdList.FORAGER("shape round")
    T.advance(6.5)
  ` + TO_NEXT + `
    local og, ng = ForagerTrackButton1.fgCircle.glow, ForagerTrackButton2.fgCircle.glow
    local oa, na = T.va(og), T.va(ng)
    check(oa > 0 and oa < 1 and na > 0 and na < 1, "both round glows part way: " .. oa .. ", " .. na)
    check(rawget(ForagerTrackButton2.fgCircle.glowAnim, "playing") and rawget(ng, "shown"), "the new round glow pulses as it fades in")
    check(not rawget(ForagerTrackButton1.glow, "shown") and not rawget(ForagerTrackButton2.glow, "shown"), "no square shimmer on round icons")
    T.frame(0.05)
    check(T.va(og) < oa and T.va(ng) > na, "the old round glow goes down while the new one comes up")
    T.frame(0.5)
    check(not rawget(og, "shown") and not rawget(ForagerTrackButton1.fgCircle.glowAnim, "playing") and T.va(ng) == 1, "settled")
  `, { atlas: true });
  run('crossfade: pausing fades the glitter out, then hides it; a quick toggle turns round from where it was', FADE_HELPERS + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + MODEL(1, 166336) + `
    local scene = T.sceneOn(ForagerTrackButton1)
    SlashCmdList.FORAGER("off")
    T.frame(0.1)
    local a = scene.actors[1].actorAlpha
    check(rawget(scene, "shown") and a > 0 and a < 0.75, "fading out, still shown: " .. a)
    T.frame(0.1)
    local half = scene.actors[1].actorAlpha
    check(math.abs(half - 0.375) < 1e-6, "halfway after 0.2 s of 0.4: " .. half)
    SlashCmdList.FORAGER("on")
    check(math.abs(scene.actors[1].actorAlpha - half) < 1e-6, "no jump when it turns round")
    T.frame(0.1)
    check(scene.actors[1].actorAlpha > half and rawget(scene, "shown"), "back up from there")
    T.frame(0.1)
    check(math.abs(scene.actors[1].actorAlpha - 0.75) < 1e-6, "full again after the 0.2 s that was left")
    SlashCmdList.FORAGER("off")
    T.frame(0.2)
    check(rawget(scene, "shown"), "not hidden part way")
  ` + MODEL_OFF, { atlas: true });
  run('sparkle effect: the button cycles, the choice is saved, and the new effect crossfades in', FADE_HELPERS + OPEN + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + MODEL(1, 166336) + `
    local b = NS.effectButton
    check(rawget(b, "text") == "Effect 1/8", "the button: " .. tostring(rawget(b, "text")))
    check(ForagerDB.sparkleModel == nil, "nothing saved until the player picks")
    b.scripts.OnClick(b, "LeftButton")
    check(ForagerDB.sparkleModel == 166060 and rawget(b, "text") == "Effect 2/8", "left-click: the next effect, saved")
    T.frame(0.1)
    local shown = {}
    for _, scene in ipairs(T.scenes()) do if rawget(scene, "shown") then shown[scene.actors[1].model] = scene end end
    local old, new = shown[166336], shown[166060]
    check(old and new, "both effects showing mid-fade")
    local p1, p2 = rawget(old, "_point"), rawget(new, "_point")
    check(p1[2] == ForagerTrackButton1.icon and p2[2] == ForagerTrackButton1.icon, "both on the active tracker")
    local oa, na = old.actors[1].actorAlpha, new.actors[1].actorAlpha
    check(oa > 0 and oa < 0.75 and na > 0 and na < 0.6, "both part way: " .. oa .. ", " .. na)
    T.frame(0.05)
    check(old.actors[1].actorAlpha < oa and new.actors[1].actorAlpha > na, "the old effect goes down while the new one comes up")
  ` + MODEL(1, 166060) + `
    b.scripts.OnClick(b, "RightButton")
    check(ForagerDB.sparkleModel == 166336 and rawget(b, "text") == "Effect 1/8", "right-click: back")
  ` + MODEL(1, 166336) + `
    for _ = 1, 8 do b.scripts.OnClick(b, "LeftButton") T.frame(0.5) end
    check(ForagerDB.sparkleModel == 166336, "all the way round")
    check(#T.scenes() == 2, "never a third scene")
  `, { atlas: true });
  run('sparkle effect: one the client lacks is skipped both ways, and debug lists it', FADE_HELPERS + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    SlashCmdList.FORAGER("sparkles next")
    check(ForagerDB.sparkleModel == 166062, "faerie fire skipped, on to the specks")
  ` + MODEL(1, 166062) + `
    SlashCmdList.FORAGER("sparkles previous")
    check(ForagerDB.sparkleModel == 166336, "skipped going back too")
    SlashCmdList.FORAGER("debug")
    local seen = false
    for _, m in ipairs(T.prints) do
      if m:find("loaded: 1 Holy glitter, 3 Faerie fire specks; skipped: 2 Faerie fire (166060)", 1, true) then seen = true end
    end
    check(seen, "debug lists what loaded and what was skipped")
  `, { atlas: true, modelDeny: '{ [166060] = true }' });
  run('sparkle effect: the slash forms', FADE_HELPERS + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    SlashCmdList.FORAGER("sparkles 5")
    check(ForagerDB.sparkleModel == 166338 and T.prints[#T.prints]:find("sparkle effect 5 of 8: Holy glitter, ground", 1, true), "a number picks it: " .. T.prints[#T.prints])
  ` + MODEL(1, 166338) + `
    local scene = T.sceneOn(ForagerTrackButton1)
    check(math.abs((scene.actors[1].pitch or 0) - math.pi / 2) < 1e-6, "the ground effect tipped to face the camera")
    SlashCmdList.FORAGER("sparkles previous")
    check(ForagerDB.sparkleModel == 165589, "previous")
  ` + MODEL(1, 165589) + `
    check((T.sceneOn(ForagerTrackButton1).actors[1].pitch or 0) == 0, "an upright effect is not tipped")
    SlashCmdList.FORAGER("sparkles next")
    check(ForagerDB.sparkleModel == 166338, "next")
    for _, bad in ipairs({ "0", "9", "2.5", "banana" }) do
      SlashCmdList.FORAGER("sparkles " .. bad)
      check(ForagerDB.sparkleModel == 166338 and T.prints[#T.prints]:find("usage: /forager sparkles", 1, true), "refused: " .. bad)
    end
    SlashCmdList.FORAGER("sparkles")
    check(ForagerDB.sparkles == false, "the bare command still turns them off")
  `, { atlas: true });
  run('sparkle effect: the saved choice is used after a reload', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + MODEL(1, 165589), { atlas: true, db: '{ sparkleModel = 165589 }' });
  run('sparkle effect: picked before any tracker is on, used when one is', `
    SlashCmdList.FORAGER("sparkles 3")
    check(ForagerDB.sparkleModel == 166062, "saved before anything is built")
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + MODEL(1, 166062), { atlas: true });
  run('sparkle size: live, the scene grows with it, saved; the slider and the slash form', FADE_HELPERS + OPEN + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    check(ForagerDB.sparkleSize == 100 and ForagerDB.sparkleIntensity == 100, "defaults 100%")
  ` + MODEL(1, 166336) + `
    local sl = NS.sparkleSizeSlider
    sl.scripts.OnValueChanged(sl, 200)
    check(ForagerDB.sparkleSize == 200, "the slider saves 200%")
    check(math.abs(NS.SparkleReach() - 62) < 1e-9, "reach 62 px at 200%")
  ` + MODEL(1, 166336) + `
    local scene = T.sceneOn(ForagerTrackButton1)
    check(rawget(scene, "_w") == 148, "the scene grew to 148, got " .. tostring(rawget(scene, "_w")))
    SlashCmdList.FORAGER("sparkles size 50")
    check(ForagerDB.sparkleSize == 50 and T.prints[#T.prints]:find("sparkle size 50%", 1, true), "the slash form")
  ` + MODEL(1, 166336) + `
    check(rawget(T.sceneOn(ForagerTrackButton1), "_w") == 104, "the scene back to its least, 104")
    for _, bad in ipairs({ "45", "205", "120.5", "big", "" }) do
      SlashCmdList.FORAGER("sparkles size " .. bad)
      check(ForagerDB.sparkleSize == 50 and T.prints[#T.prints]:find("usage: /forager sparkles size", 1, true), "refused: '" .. bad .. "'")
    end
    SlashCmdList.FORAGER("sparkles next")
  ` + MODEL(1, 166060) + `
  `, { atlas: true });
  run('sparkle intensity: live, and it multiplies with the fades', FADE_HELPERS + OPEN + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    local sl = NS.sparkleIntensitySlider
    sl.scripts.OnValueChanged(sl, 50)
    check(ForagerDB.sparkleIntensity == 50, "the slider saves 50%")
    local scene = T.sceneOn(ForagerTrackButton1)
    check(math.abs(scene.actors[1].actorAlpha - 0.375) < 1e-9, "at once: 0.75 times 50%, got " .. scene.actors[1].actorAlpha)
  ` + MODEL(1, 166336) + TO_NEXT + `
    local old, new = T.sceneOn(ForagerTrackButton1), T.sceneOn(ForagerTrackButton2)
    local oa, na = old.actors[1].actorAlpha, new.actors[1].actorAlpha
    check(oa > 0 and oa < 0.375 and na > 0 and na < 0.375, "a crossfade runs between 0 and the chosen strength: " .. oa .. ", " .. na)
  ` + MODEL(2, 166336) + `
    SlashCmdList.FORAGER("off")
    T.frame(0.1)
    local scene2 = T.sceneOn(ForagerTrackButton2)
    check(math.abs(scene2.actors[1].actorAlpha - 0.28125) < 1e-9, "fading out from the chosen strength, a quarter gone after 0.1 s: " .. scene2.actors[1].actorAlpha)
    SlashCmdList.FORAGER("on")
  ` + MODEL(2, 166336) + `
    SlashCmdList.FORAGER("sparkles intensity 0")
    check(ForagerDB.sparkleIntensity == 0 and T.sceneOn(ForagerTrackButton2).actors[1].actorAlpha == 0, "0% draws nothing")
    SlashCmdList.FORAGER("sparkles intensity 100")
  ` + MODEL(2, 166336) + `
    for _, bad in ipairs({ "101", "-5", "half" }) do
      SlashCmdList.FORAGER("sparkles intensity " .. bad)
      check(ForagerDB.sparkleIntensity == 100 and T.prints[#T.prints]:find("usage: /forager sparkles", 1, true), "refused: " .. bad)
    end
  `, { atlas: true });
  run('sparkle size and intensity: grayed while the sparkles are off, laid out without overlap', OPEN + `
    local box
    for _, f in ipairs(T.frames) do local l = rawget(f, "label") if type(l) == "table" and rawget(l, "text") == "Sparkles on the active tracker" then box = f end end
    local size, strength = NS.sparkleSizeSlider, NS.sparkleIntensitySlider
    for _, s in ipairs({ size, strength }) do check(rawget(s, "enabled") == true and rawget(s, "alpha") == 1, "live while on") end
    box.checked = false box.scripts.OnClick(box)
    for _, s in ipairs({ size, strength }) do
      check(rawget(s, "enabled") == false and rawget(s, "alpha") == 0.5 and rawget(s.fgCaption, "font") == GameFontDisable, "grayed while off")
    end
    box.checked = true box.scripts.OnClick(box)
    check(rawget(size, "enabled") == true, "live again")
    -- The rows: the checkbox and effect button, then the two sliders, then Icon size.
    local function y(f) local p = rawget(f, "_point") return p[#p] end
    local function holder(s) return rawget(s, "parent") end
    local iconSize = holder(NS.opacitySlider) -- any OptionSlider holder has the same height
    local below
    for _, f in ipairs(T.frames) do
      local cap = rawget(f, "parent") and rawget(f, "_h") == 40 and f ~= holder(size) and f ~= holder(strength) and f
      if cap then local p = rawget(f, "_point") if p and p[2] == 356 and p[3] < y(holder(strength)) and (not below or p[3] > y(below)) then below = f end end
    end
    check(y(box) - 24 >= y(holder(size)), "the checkbox row ends above the size slider")
    check(y(NS.effectButton) - 22 >= y(holder(size)), "the effect button ends above the size slider")
    check(y(holder(size)) - 40 >= y(holder(strength)), "the size slider ends above the intensity slider")
    check(below ~= nil and y(holder(strength)) - 40 >= y(below), "the intensity slider ends above Icon size")
    local hint
    for _, fs in ipairs(T.strings) do local t = rawget(fs, "text") if type(t) == "string" and t:find("^More key bindings") then hint = fs end end
    check(y(hint) - 36 >= -rawget(content, "_h"), "the right column still fits: hint at " .. y(hint) .. " of " .. tostring(rawget(content, "_h")))
  `);
  run('the standalone window shrinks to fit a short screen', `
    UIParent.GetHeight = function() return 768 end
  ` + OPEN + `
    local scale = rawget(ForagerOptions, "scale")
    check(scale and math.abs(scale - (768 - 40) / (930 + 70)) < 1e-9, "scaled to fit: " .. tostring(scale))
  `);
  run('drawn sparkles follow the size and intensity', SPARK_HELPERS + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    SlashCmdList.FORAGER("sparkles size 200")
    SlashCmdList.FORAGER("sparkles intensity 50")
    T.finishSparks() -- the ones out before the change finish at the old size
    local seen = 0
    T.sparkTicks(40, function(b)
      for _, s in ipairs(b.fgSparks) do
        if rawget(s.anim, "playing") then
          seen = seen + 1
          local o = rawget(s.move, "offset")
          local drift = math.sqrt(o[1] * o[1] + o[2] * o[2])
          check(drift >= 8 - 1e-6 and drift <= 16 + 1e-6, "drift doubled: " .. drift)
          check(rawget(s.tex, "_w") == 28, "spark doubled: " .. tostring(rawget(s.tex, "_w")))
          check(rawget(s.fadeIn, "toAlpha") == 0.5 and rawget(s.fadeOut, "fromAlpha") == 0.5, "at half strength")
        end
      end
    end)
    check(seen > 0, "sparks ran")
    SlashCmdList.FORAGER("sparkles intensity 0")
    check(T.sparkTicks(40) == 0, "none at 0%")
  `, { atlas: true, noModelScene: true });
  run('sparkles: a client missing the first effect gets the next one', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + MODEL(1, 166060), { atlas: true, modelDeny: '{ [166336] = true }' });
  run('sparkles: none of the effects on the client, so drawn sparkles, and debug says why', SPARK_HELPERS + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    local path, why = NS.SparklePath()
    check(path == "drawn sparkles" and why:find("none of the sparkle effects", 1, true), "path: " .. tostring(path) .. ", " .. tostring(why))
    check(T.sparkTicks(40) > 0, "the drawn sparkles run instead")
    SlashCmdList.FORAGER("debug")
    local seen = false
    for _, m in ipairs(T.prints) do if m:find("sparkles on: drawn sparkles, this client has none of the sparkle effects", 1, true) then seen = true end end
    check(seen, "debug says why")
  `, { atlas: true, modelDeny: '{ [166336] = true, [166060] = true, [166062] = true, [165589] = true, [166338] = true, [166322] = true, [775512] = true, [426041] = true }' });
  run('sparkles: no ModelScene on the client, so drawn sparkles', SPARK_HELPERS + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    local path, why = NS.SparklePath()
    check(path == "drawn sparkles" and why:find("no ModelScene", 1, true), "path: " .. tostring(path) .. ", " .. tostring(why))
    check(T.sparkTicks(40) > 0, "the drawn sparkles run instead")
  `, { atlas: true, noModelScene: true });
  run('drawn sparkles: only on the active tracker, from its edge, just behind the bar frame', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    check(T.active() == "Find Herbs" and ForagerDB.sparkles == true, "herbs on, sparkles on by default")
  ` + SPARKS('bar', 1) + `
    check(rawget(ForagerTrackButton2, "fgSparks") == nil, "nothing made for a tracker that has not been on")
  `, { noModelScene: true, atlas: true });
  run('drawn sparkles follow the active tracker', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + SPARKS('bar', 1) + `
    T.advance(6.5)
    check(T.active() == "Find Minerals", "minerals on")
    -- Herbs' sparks finish their own short life; none start there now.
    T.finishSparks()
  ` + SPARKS('bar', 2), { noModelScene: true, atlas: true });
  run('drawn sparkles stop when paused, hidden, hidden in combat, or switched off', SPARK_HELPERS + OPEN + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    check(T.sparkTicks(20) > 0, "sparkling")
    SlashCmdList.FORAGER("off")
    check(T.sparkTicks(20) == 0, "none while paused")
    SlashCmdList.FORAGER("on")
    check(T.sparkTicks(20) > 0, "back when resumed")
    T.ticker()
    SlashCmdList.FORAGER("sparkles")
    check(ForagerDB.sparkles == false and T.sparksOut(ForagerTrackButton1) == 0, "the command turns them off at once")
    check(T.sparkTicks(20) == 0, "and they stay off")
    local box
    for _, f in ipairs(T.frames) do local l = rawget(f, "label") if type(l) == "table" and rawget(l, "text") == "Sparkles on the active tracker" then box = f end end
    check(box ~= nil, "the option is in the options")
    box.checked = true box.scripts.OnClick(box)
    check(ForagerDB.sparkles == true and T.sparkTicks(20) > 0, "the option turns them on")
    SlashCmdList.FORAGER("icons")
    check(ForagerDB.bar == false and T.sparkTicks(20) == 0, "none while the icons are hidden")
    SlashCmdList.FORAGER("icons")
    ForagerDB.barHideCombat = true
    T.combat = true
    check(T.sparkTicks(20) == 0, "none in combat when the icons hide there")
    T.combat = false
    check(T.sparkTicks(20) > 0, "back after combat")
  `, { noModelScene: true, atlas: true });
  run('drawn sparkles round the minimap ring, just under it', `
    T.fire("PLAYER_ENTERING_WORLD")
    SlashCmdList.FORAGER("shape round")
    T.advance(6.5)
  ` + SPARKS('circle-ring', 1), { noModelScene: true, atlas: true });
  run('drawn sparkles behind the dark edge of a round icon', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + SPARKS('circle-edge', 1), { noModelScene: true, atlas: true, db: '{ style = "dark", iconShape = "round" }' });
  run("drawn sparkles behind Dark's square edge, also after a live change of shape", `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + SPARKS('square', 1) + `
    SlashCmdList.FORAGER("shape round")
  ` + SPARKS('circle-edge', 1), { noModelScene: true, atlas: true, db: '{ style = "dark" }' });
  run('/forager debug icons reports each icon and keeps it in the saved log', `
    T.fire("PLAYER_ENTERING_WORLD")
    SlashCmdList.FORAGER("shape round")
    T.advance(6.5)
    local before = #T.prints
    SlashCmdList.FORAGER("debug icons")
    check(#T.prints - before == 3, "a line per icon and the pause button, got " .. (#T.prints - before))
    check(T.prints[before + 1]:find("look circle%-ring") and T.prints[before + 1]:find("round glow ring at"), "the circle's pieces: " .. T.prints[before + 1])
    local logged = 0
    for _, line in ipairs(ForagerLog.lines) do if line:find("icon %d: look") then logged = logged + 1 end end
    check(logged == 3, "kept in the saved log")
  `, { atlas: true });
  run('/forager debug icons names the color sweep on the action bar look', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    local before = #T.prints
    SlashCmdList.FORAGER("debug icons")
    check(T.prints[before + 1]:find("look bar", 1, true) and T.prints[before + 1]:find(", color, shown", 1, true), "the line: " .. T.prints[before + 1])
  `, { atlas: true });
  run('icon shape: Automatic follows a style drawn live', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + ICONS('bar') + `
    SlashCmdList.FORAGER("style dark")
  ` + ICONS('square') + `
    SlashCmdList.FORAGER("shape")
    check(T.prints[#T.prints]:find("icon shape: Automatic, now square.", 1, true), "prints: " .. T.prints[#T.prints])
    SlashCmdList.FORAGER("shape oval")
    check(ForagerDB.iconShape == "auto" and T.prints[#T.prints]:find("shapes: auto, round, square", 1, true), "unknown shape refused")
  `, { atlas: true });
  run('the shape button sits beside Reset position, inside the column', OPEN + `
    local reset
    for _, f in ipairs(T.frames) do if rawget(f, "text") == "Reset position" then reset = f end end
    local shape = NS.shapeButton
    local rp, sp = rawget(reset, "_point"), rawget(shape, "_point")
    check(rp[3] == sp[3], "same row")
    check(rp[2] + rawget(reset, "_w") < sp[2], "right of Reset position")
    check(sp[2] + rawget(shape, "_w") <= 352 + 320, "inside the right column")
    local minimap = T.string("Minimap")
    local mp = rawget(minimap, "_point")
    check(sp[3] - 22 > mp[#mp], "above the Minimap header")
  `);
  run('slash command sets the style and prints the note', OPEN + `
    SlashCmdList.FORAGER("style dark")
    check(ForagerDB.style == "dark" and NS.Styles.Applied() == "dark", "style dark")
    check(T.prints[#T.prints]:find("window style: Dark. In use: Dark.", 1, true), "prints: " .. T.prints[#T.prints])
  ` + SLIDER(true) + STYLE_BUTTON('Dark') + `
    SlashCmdList.FORAGER("style auto")
    check(ForagerDB.style == "auto" and T.prints[#T.prints]:find("Type /reload to switch to Blizzard", 1, true), "auto: " .. T.prints[#T.prints])
    SlashCmdList.FORAGER("style blizzard")
    check(ForagerDB.style == "blizzard", "style blizzard")
    SlashCmdList.FORAGER("style")
    check(ForagerDB.style == "dark", "bare style cycles: " .. tostring(ForagerDB.style))
    SlashCmdList.FORAGER("style purple")
    check(ForagerDB.style == "dark" and T.prints[#T.prints]:find("styles: auto, blizzard, dark", 1, true), "unknown style refused")
  `);
  run('Look sits above the tracker list, and twelve trackers still fit', `
    for i = 1, 7 do T.tracking[#T.tracking + 1] = { name = "Track " .. i, spellID = 9000 + i, type = "spell", active = false, texture = 9 } end
  ` + OPEN + `
    local function y(f) local p = rawget(f, "_point") return p[#p] end
    local look, trackers = T.string("Look"), T.string("Tracks and trackers")
    local note
    for _, fs in ipairs(T.strings) do local t = rawget(fs, "text") if type(t) == "string" and t:find("^In use") then note = fs end end
    local holder = rawget(NS.opacitySlider, "parent")
    check(look and trackers and holder, "found the pieces")
    check(y(look) > y(NS.styleButton) and y(NS.styleButton) - 22 > y(note), "header, then the style button, then the note")
    check(y(note) - 26 >= y(holder), "two lines of note fit above the slider")
    check(y(holder) - rawget(holder, "_h") > y(trackers), "the slider ends above the tracker list header")
    local lowest, rows = 0, 0
    for _, f in ipairs(T.frames) do
      local p = rawget(f, "_point")
      if p and rawget(f, "parent") == content and p[2] == 12 and p[3] <= -596 then
        rows = rows + 1
        lowest = math.min(lowest, p[3] - 24)
      end
    end
    check(rows == 12, "twelve tracker rows, got " .. rows)
    check(lowest >= -rawget(content, "_h"), "the last row fits in the options (" .. lowest .. " of " .. tostring(rawget(content, "_h")) .. ")")
  `);
} else {
  run('EllesmereUI: the window frame and the tracker icons are skinned, the options are not', OPEN + `
    check(T.euiName == "Forager", "registered under the folder name")
    check(NS.report.skin == "EllesmereUI (eui style)", "status: " .. tostring(NS.report.skin))
    local win = ForagerOptions
    check(T.did(win, "Shell"), "window shelled")
    check(T.did(win.PortraitContainer, "FadeRegions"), "portrait faded")
    check(T.did(win.NineSlice, "FadeNineSlice"), "metal frame faded")
    check(T.did(win.Inset, "Inset"), "inset blended")
    check(T.did(win.TitleContainer.TitleText, "Font"), "title font")
    check(T.did(win.CloseButton, "CloseButton"), "close button")
    check(T.border and rawget(T.border, "parent") == win, "border laid over the window")
    check(win.CloseButton:GetFrameLevel() > T.border:GetFrameLevel(), "close button above the border")
    check(win.TitleContainer:GetFrameLevel() > T.border:GetFrameLevel(), "title bar above the border")
    local allowed = { [win] = true, [win.CloseButton] = true, [win.PortraitContainer] = true, [win.NineSlice] = true,
      [win.Inset] = true, [win.TitleContainer.TitleText] = true, [ForagerPauseButton.icon] = true }
    for _, b in ipairs(NS.trackButtons) do allowed[b.icon] = true end
    for f in pairs(T.skinned) do check(allowed[f], "only the window frame and icons skinned: " .. tostring(rawget(f, "name"))) end
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
    SlashCmdList.FORAGER("debug")
    local seen = false for _, m in ipairs(T.prints) do if m:find("skin: EllesmereUI (eui style)", 1, true) then seen = true end end
    check(seen, "debug prints the skin state")
  ` + SLIDER(false) + STYLE_BUTTON('Automatic') + `
    local button = NS.styleButton
    button.scripts.OnClick(button, "LeftButton")
    check(ForagerDB.style == "blizzard" and ForagerReloadPrompt and ForagerReloadPrompt.shown, "leaving EllesmereUI offers a reload")
    check(T.did(ForagerReloadPrompt, "Shell"), "the prompt is in EllesmereUI's look")
    button.scripts.OnClick(button, "RightButton")
    check(ForagerDB.style == "auto" and not ForagerReloadPrompt.shown, "back to Automatic: prompt gone")
  `);
  run('EllesmereUI: tracker icons squared at login and when built later', `
    check(NS.Styles.Applied() == "eui", "EllesmereUI applied at login")
    T.advance(6.5)
    ForagerDB.rotation[1494] = true
    T.advance(1)
    check(ForagerTrackButton3 ~= nil, "a third icon built for the new tracker")
  ` + ICONS('square', 'eui') + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  `, { atlas: true });
  run('icon shape: Round under EllesmereUI, live, and Square again', `
    T.advance(6.5)
  ` + ICONS('square', 'eui') + `
    SlashCmdList.FORAGER("shape round")
    check(ForagerDB.iconShape == "round" and NS.Styles.Applied() == "eui", "Round under EllesmereUI")
  ` + ICONS('circle-edge', 'eui') + `
    T.advance(6.5) -- the next tracker comes on, and the round glow with it
    check(rawget(ForagerTrackButton2.fgCircle.glow, "shown") == true, "round glow on the new tracker")
  ` + ICONS('circle-edge', 'eui') + `
    SlashCmdList.FORAGER("shape square")
  ` + ICONS('square', 'eui') + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  `, { atlas: true });
  run('sparkles: the glitter model under EllesmereUI', `
    T.advance(6.5)
  ` + MODEL(1, 166336) + `
    SlashCmdList.FORAGER("shape round")
  ` + MODEL(1, 166336), { atlas: true });
  run("drawn sparkles behind EllesmereUI's square edge", `
    T.advance(6.5)
  ` + SPARKS('square', 1), { noModelScene: true, atlas: true });
  run('Blizzard chosen with EllesmereUI running: nothing skinned', OPEN + `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    check(NS.report.skin == "Blizzard (chosen in the options)", "status: " .. tostring(NS.report.skin))
    check(next(T.skinned) == nil, "nothing skinned")
  ` + ICONS('bar'), { db: '{ style = "blizzard" }', atlas: true });
  run('Dark chosen with EllesmereUI running: Dark drawn, EllesmereUI not used', `
    SNAP = T.drawSnapshot()
  ` + OPEN + `
    check(NS.Styles.Applied() == "dark" and NS.report.skin == "Dark", "status: " .. tostring(NS.report.skin))
    check(next(T.skinned) == nil, "EllesmereUI's calls not used")
  ` + WINDOW_DRAWN + ONLY_WINDOW_DRAWN, { db: '{ style = "dark" }' });
}

run('the options page has its controls on the first visit from Esc > Options', `
  check(T.page ~= nil, "the canvas page is registered")
  check(not T.page:IsVisible(), "the page waits hidden until the panel shows it")
  -- Esc > Options opens the panel on another page; then AddOns > Forager.
  SettingsPanel:Show()
  T.page:SetParent(SettingsPanel) T.page:Show()
  check(T.hosted() ~= nil, "first visit: the controls are on the page")
  -- Away and back, and the panel closed and opened again.
  T.page:Hide() T.page:Show()
  check(T.hosted() ~= nil, "second visit: still there")
  SettingsPanel.shown = false SettingsPanel:Show()
  check(T.hosted() ~= nil, "after closing the panel: still there")
  -- /forager opens and closes it.
  SettingsPanel.shown = false T.page:Hide()
  SlashCmdList.FORAGER("")
  check(SettingsPanel.shown and T.hosted() ~= nil, "/forager opens the page with its controls")
  SlashCmdList.FORAGER("")
  check(not SettingsPanel.shown and not (ForagerOptions and ForagerOptions.shown), "and closes it, with no window left open")
`, { page: true });

// The window's close X: the template's own click goes through HideUIPanel, which this client
// refuses in combat, so the X has to hide the window itself.
run('the options window closes from its X, in combat too', OPEN + `
  local win = ForagerOptions
  local close = win.CloseButton
  check(close ~= nil and close.scripts.OnClick ~= nil, "the window has its X")
  check(win.shown, "the window is open")
  T.combat = true
  local blocked = T.blocked
  pcall(close.scripts.OnClick, close, "LeftButton")
  T.combat = false
  check(not win.shown, "in combat the X closes the window")
  check(T.blocked == blocked, "with no interface action blocked (" .. (T.blocked - blocked) .. ")")
  SlashCmdList.FORAGER("")
  check(win.shown, "/forager opens it again")
  pcall(close.scripts.OnClick, close, "LeftButton")
  check(not win.shown, "out of combat the X still closes it")
`);

run('minimap button: left where a collector puts it, dragged round the rim on the minimap', `
-- A minimap button collector (EllesmereUI's, for one) takes the button off the minimap. Neither a
-- refresh nor a drag tick may put it back on the rim then; on the minimap a drag still moves it.
do
  local mm = ForagerMinimapButton
  local function Script(f, e) return f.scripts[e] end
  local holder = CreateFrame("Frame", nil, UIParent)
  local own, setPoint = rawget(mm, "SetPoint"), mm.SetPoint
  local moves, rel = 0, nil
  rawset(mm, "SetPoint", function(self, ...) moves = moves + 1 rel = select(2, ...) return setPoint(self, ...) end)
  local center, escale, cursor = rawget(Minimap, "GetCenter"), rawget(Minimap, "GetEffectiveScale"), GetCursorPosition
  rawset(Minimap, "GetCenter", function() return 500, 500 end)
  rawset(Minimap, "GetEffectiveScale", function() return 1 end)
  GetCursorPosition = function() return 600, 560 end
  -- The game has both: a degree based global atan2 and the radian based math.atan2.
  local atan2Was, mathAtan2Was = atan2, math.atan2
  atan2 = atan2 or function(y, x) return math.deg(math.atan(y, x)) end
  math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
  local function Drag()
    local start, stop = Script(mm, "OnDragStart"), Script(mm, "OnDragStop")
    if not start then return false end
    start(mm)
    local tick = Script(mm, "OnUpdate")
    if tick then tick(mm, 0.02) end
    if stop then stop(mm) end
    return tick ~= nil
  end
  mm:SetParent(holder)
  Drag()
  SlashCmdList.FORAGER("minimap") SlashCmdList.FORAGER("minimap")
  check(moves == 0, "minimap: a button a collector (EllesmereUI's) has taken stays where the collector put it")
  mm:SetParent(Minimap)
  local dragged = Drag()
  check(dragged and moves > 0 and rel == Minimap, "minimap: on the minimap a drag still moves it round the rim")
  rawset(mm, "SetPoint", own)
  rawset(Minimap, "GetCenter", center)
  rawset(Minimap, "GetEffectiveScale", escale)
  GetCursorPosition = cursor
  atan2, math.atan2 = atan2Was, mathAtan2Was
end
`);

const TREASURE = `
  T.tracking[#T.tracking + 1] = { name = "Find Treasure", spellID = 2481, type = "spell", active = false, texture = 9 }
`
run('Find Treasure on but not ticked does not hold up the rotation', TREASURE + `
  T.tracking[#T.tracking].active = true T.fire("MINIMAP_UPDATE_TRACKING")
  T.advance(6.5) check(T.active() == "Find Herbs" or T.tracking[1].active, "herbs on next to treasure")
  check(T.tracking[1].active and T.tracking[#T.tracking].active, "both on")
  T.advance(6.5) check(T.tracking[2].active and not T.tracking[1].active, "then minerals, rotation going")
  check(T.tracking[#T.tracking].active, "treasure left alone")
`);
run('Find Treasure ticked is kept on and the rotation keeps going', TREASURE + `
  ForagerDB.rotation[2481] = true
  T.advance(2) check(T.tracking[#T.tracking].active, "treasure put on")
  local seen = {}
  for n = 1, 6 do
    T.advance(6.5)
    if T.tracking[1].active then seen.herbs = (seen.herbs or 0) + 1 end
    if T.tracking[2].active then seen.minerals = (seen.minerals or 0) + 1 end
    check(T.tracking[#T.tracking].active, "treasure still on, round " .. n)
  end
  check((seen.herbs or 0) >= 2 and (seen.minerals or 0) >= 2, "herbs and minerals both keep coming round: " .. tostring(seen.herbs) .. "/" .. tostring(seen.minerals))
  check(ForagerDB.method == "timer", "no switch read as failed, method " .. tostring(ForagerDB.method))
`);
run('a kept-on tracker comes back if it drops off', TREASURE + `
  ForagerDB.rotation[2481] = true
  T.advance(2) T.tracking[#T.tracking].active = false T.fire("MINIMAP_UPDATE_TRACKING")
  T.advance(3) check(T.tracking[#T.tracking].active, "treasure back on")
  SlashCmdList.FORAGER("off") T.tracking[#T.tracking].active = false
  T.advance(5) check(not T.tracking[#T.tracking].active, "not while paused")
`);
run('a tracker that unexpectedly stays on does not stick the rotation', `
  ForagerDB.rotation[1494] = true
  -- Track Beasts behaving like Find Treasure: nothing turns it off
  local real = C_Minimap.SetTracking
  C_Minimap.SetTracking = function(i, on)
    local beasts = T.tracking[3].active
    real(i, on)
    if beasts then T.tracking[3].active = true end
  end
  local herbs, minerals = 0, 0
  for n = 1, 9 do
    T.advance(6.5)
    if T.tracking[1].active then herbs = herbs + 1 end
    if T.tracking[2].active then minerals = minerals + 1 end
  end
  check(herbs >= 2 and minerals >= 2, "still rotating: herbs " .. herbs .. ", minerals " .. minerals)
  check(ForagerDB.method == "timer", "no switch read as failed")
`);

const TRACKBTN = `
  function T.trackButton(name)
    for i = 1, 20 do
      local b = _G["ForagerTrackButton" .. i]
      if b and rawget(b, "key") then
        for _, e in ipairs(T.tracking) do
          if e.name == name and e.spellID == rawget(b, "key") then return b end
        end
      end
    end
  end
`;
run('right-click an icon to leave it out of the rotation, and again to put it back', TRACKBTN + `
  ForagerDB.rotation[1494] = true
  T.advance(1)
  local beasts = T.trackButton("Track Beasts")
  check(beasts ~= nil, "beasts has an icon")
  beasts.scripts.OnClick(beasts, "RightButton")
  check(ForagerDB.skipped[1494] == true, "left out")
  local seen = {}
  for n = 1, 6 do T.advance(6.5) seen[T.active() or "none"] = true end
  check(seen["Find Herbs"] and seen["Find Minerals"], "the others still rotate")
  check(not seen["Track Beasts"], "beasts skipped")
  check(T.trackButton("Track Beasts") ~= nil, "still on the icons")
  beasts.scripts.OnClick(beasts, "RightButton")
  check(ForagerDB.skipped[1494] == nil, "put back")
  seen = {}
  for n = 1, 6 do T.advance(6.5) seen[T.active() or "none"] = true end
  check(seen["Track Beasts"], "beasts back in the rotation")
`);
run('left-click still turns a left-out tracker on, with its sound', TRACKBTN + `
  ForagerDB.rotation[1494] = true
  T.advance(1)
  local beasts = T.trackButton("Track Beasts")
  beasts.scripts.OnClick(beasts, "RightButton")
  T.sfxAtCast = nil
  beasts.scripts.OnClick(beasts, "LeftButton")
  T.advance(1)
  check(T.active() == "Track Beasts", "beasts on, got " .. tostring(T.active()))
  check(T.sfxAtCast == "1", "sound kept on a click, got " .. tostring(T.sfxAtCast))
  check(ForagerDB.skipped[1494] == true, "still left out")
  T.advance(6.5)
  check(T.active() == "Find Herbs" or T.active() == "Find Minerals", "the rotation carries on from it: " .. tostring(T.active()))
  T.sfxAtCast = nil T.advance(6.5)
  check(T.sfxAtCast == "0", "timer switches still quiet")
`);
run('leaving all but one out keeps that one on', TRACKBTN + `
  ForagerDB.rotation[1494] = true
  T.advance(1)
  T.trackButton("Find Herbs").scripts.OnClick(T.trackButton("Find Herbs"), "RightButton")
  T.trackButton("Find Minerals").scripts.OnClick(T.trackButton("Find Minerals"), "RightButton")
  T.advance(7) check(T.active() == "Track Beasts", "beasts on")
  local n = T.switches
  T.advance(30) check(T.switches == n and T.active() == "Track Beasts", "and kept")
`);
run('tracks: only one runs, and switching hands over to the new one', `
  ForagerDB.rotation[1494] = true
  T.advance(6.5) check(T.active() == "Find Herbs", "track 1 running")
  SlashCmdList.FORAGER("track new Hunting")
  check(#ForagerDB.tracks == 2 and ForagerDB.track == 2, "new track is the current one")
  check(ForagerDB.tracks[2].name == "Hunting", "named " .. tostring(ForagerDB.tracks[2].name))
  ForagerDB.rotation[1494] = true ForagerDB.rotation[5225] = true
  check(ForagerDB.tracks[2].rotation[1494] and not ForagerDB.tracks[1].rotation[5225], "ticks go to the current track only")
  local seen = {}
  for n = 1, 8 do T.advance(6.5) seen[T.active() or "none"] = true end
  check(seen["Track Beasts"] and seen["Track Humanoids"], "Hunting rotates beasts and humanoids")
  check(not seen["Find Herbs"] and not seen["Find Minerals"], "and only those: track 1 is not running")
  -- Make sure Hunting's own tracker is the one on when the track changes.
  local hum = ForagerTrackButton2
  for i = 1, 4 do local b = _G["ForagerSlot2Button" .. i] if b and rawget(b, "key") == 5225 then hum = b end end
  hum.scripts.OnClick(hum, "LeftButton") T.advance(1.5)
  check(T.active() == "Track Humanoids", "humanoids on before switching")
  SlashCmdList.FORAGER("track 1")
  check(ForagerDB.track == 1, "back on track 1")
  T.advance(1)
  check(T.active() == "Find Herbs" or T.active() == "Find Minerals" or T.active() == "Track Beasts",
    "track 1 takes over at once: " .. tostring(T.active()))
  seen = {}
  for n = 1, 8 do T.advance(6.5) seen[T.active() or "none"] = true end
  check(not seen["Track Humanoids"], "Hunting's humanoids no longer come round")
  check(seen["Track Beasts"], "track 1's own beasts do")
`);
run('tracks: names above the rows, the key binding and the command switch them', `
  SlashCmdList.FORAGER("track new Second")
  ForagerDB.rotation[1494] = true ForagerDB.rotation[5225] = true
  T.advance(1)
  check(rawget(ForagerTrackLabel, "shown") ~= false and rawget(ForagerSlot2Label, "shown") ~= false, "a name over each row")
  ForagerTrackLabel.scripts.OnClick(ForagerTrackLabel, "LeftButton") check(ForagerDB.track == 1, "row 1's name: track 1")
  ForagerSlot2Label.scripts.OnClick(ForagerSlot2Label, "LeftButton") check(ForagerDB.track == 2, "row 2's name: track 2")
  Forager_NextTrack() check(ForagerDB.track == 1, "binding: next")
  SlashCmdList.FORAGER("track sec") check(ForagerDB.track == 2, "by name")
  -- Only the current track on show: its name steps through them.
  ForagerDB.showAllTracks = false T.advance(0.5)
  check(rawget(ForagerSlot2Label, "shown") == false or rawget(ForagerRow2, "shown") == false, "row 2 hidden")
  ForagerTrackLabel.scripts.OnClick(ForagerTrackLabel, "LeftButton") check(ForagerDB.track == 1, "name: next wraps to 1")
  ForagerTrackLabel.scripts.OnClick(ForagerTrackLabel, "RightButton") check(ForagerDB.track == 2, "name: previous")
`);
run('every track on screen at once; play on a row runs it and stops the other', `
  ForagerDB.rotation[1494] = true
  SlashCmdList.FORAGER("track new Hunting")
  ForagerDB.rotation[1494] = true ForagerDB.rotation[5225] = true
  SlashCmdList.FORAGER("track 1")
  T.advance(1)
  check(rawget(ForagerRow1, "shown") ~= false and rawget(ForagerRow2, "shown") ~= false, "both rows on screen")
  local function keys(prefix)
    local out = {}
    for i = 1, 6 do local b = _G[prefix .. i] if b and rawget(b, "shown") ~= false and rawget(b, "key") then out[#out + 1] = rawget(b, "key") end end
    table.sort(out) return table.concat(out, ",")
  end
  check(keys("ForagerTrackButton") == "1494,2383,2580", "row 1 holds track 1's trackers: " .. keys("ForagerTrackButton"))
  check(keys("ForagerSlot2Button") == "1494,5225", "row 2 holds Hunting's: " .. keys("ForagerSlot2Button"))
  check(rawget(ForagerRow1, "alpha") == 1 and rawget(ForagerRow2, "alpha") < 1, "the running row is bright, the other dimmed")
  T.advance(6.5)
  local p1, p2 = ForagerPauseButton, ForagerSlot2Pause
  check(rawget(p1.stop, "shown") and not rawget(p2.stop, "shown"), "row 1 shows stop, row 2 play")
  -- Play on row 2: Hunting runs, track 1 stops.
  p2.scripts.OnClick(p2, "LeftButton")
  check(ForagerDB.track == 2 and ForagerDB.enabled, "Hunting running")
  T.advance(0.5)
  check(rawget(p2.stop, "shown") and not rawget(p1.stop, "shown"), "now row 2 shows stop, row 1 play")
  check(rawget(ForagerRow2, "alpha") == 1 and rawget(ForagerRow1, "alpha") < 1, "Hunting's row lit")
  local seen = {}
  for n = 1, 8 do T.advance(6.5) seen[T.active() or "none"] = true end
  check(seen["Track Humanoids"] and not seen["Find Herbs"] and not seen["Find Minerals"], "only Hunting rotates")
  -- Stop on the running row pauses it.
  p2.scripts.OnClick(p2, "LeftButton")
  check(ForagerDB.enabled == false and ForagerDB.track == 2, "Hunting paused")
  local n = T.switches T.advance(20) check(T.switches == n, "nothing runs")
  -- Play on row 1 runs track 1 again.
  p1.scripts.OnClick(p1, "LeftButton")
  check(ForagerDB.track == 1 and ForagerDB.enabled, "track 1 running")
`);
run('a dimmed row still turns trackers on and leaves them out of its own track', `
  SlashCmdList.FORAGER("track new Hunting")
  ForagerDB.rotation[1494] = true ForagerDB.rotation[5225] = true
  SlashCmdList.FORAGER("track 1")
  T.advance(1)
  local hum
  for i = 1, 4 do local b = _G["ForagerSlot2Button" .. i] if b and rawget(b, "key") == 5225 then hum = b end end
  hum.scripts.OnClick(hum, "RightButton")
  check(ForagerDB.tracks[2].skipped[5225] == true and not ForagerDB.tracks[1].skipped[5225], "left out of Hunting only")
  hum.scripts.OnClick(hum, "LeftButton") T.advance(1.5)
  check(T.active() == "Track Humanoids", "left-click still turns it on")
  check(ForagerDB.track == 1, "and does not change the running track")
`);

run('tracks: delete needs a second click, rename sticks, saved once', `
  SlashCmdList.FORAGER("track new Spare")
  SlashCmdList.FORAGER("")
  local del
  for _, f in ipairs(T.frames) do if rawget(f, "text") == "Delete" then del = f end end
  check(del ~= nil, "delete button")
  del.scripts.OnClick(del) check(#ForagerDB.tracks == 2, "one click arms it")
  del.scripts.OnClick(del) check(#ForagerDB.tracks == 1 and ForagerDB.track == 1, "second click deletes")
  local box = ForagerTrackName
  box.GetText = function() return "  Gathering  " end
  box.scripts.OnEnterPressed(box)
  check(ForagerDB.tracks[1].name == "Gathering", "renamed and trimmed: " .. tostring(ForagerDB.tracks[1].name))
  T.fire("PLAYER_LOGOUT")
  check(ForagerDB.rotation == nil and ForagerDB.skipped == nil, "the current track's tables are not saved twice")
  check(ForagerDB.tracks[1].rotation[2383], "the track keeps its ticks")
`);
run('after a reload, play on another track starts it at once', `
  SlashCmdList.FORAGER("track new Hunting")
  ForagerDB.rotation[1494] = true ForagerDB.rotation[5225] = true
  SlashCmdList.FORAGER("track 1")
  SlashCmdList.FORAGER("off")
  T.advance(1)
  -- As after a reload: Find Herbs (track 1's) is on, and Forager has no
  -- memory of turning it on.
  T.tracking[1].active = true
  T.fire("MINIMAP_UPDATE_TRACKING")
  T.advance(0.5)
  ForagerSlot2Pause.scripts.OnClick(ForagerSlot2Pause, "LeftButton")
  check(ForagerDB.track == 2 and ForagerDB.enabled, "Hunting running")
  T.advance(1.5)
  check(T.active() == "Track Beasts" or T.active() == "Track Humanoids", "Hunting's tracker on at once, got " .. tostring(T.active()))
  local seen = {}
  for n = 1, 6 do T.advance(6.5) seen[T.active() or "none"] = true end
  check(seen["Track Beasts"] and seen["Track Humanoids"], "and rotating")
`);
run('a tracker in none of your tracks still counts as your own pick', `
  T.advance(6.5) check(T.active() == "Find Herbs", "rotating")
  T.tracking[1].active = false T.tracking[3].active = true -- Track Beasts, ticked nowhere
  T.fire("MINIMAP_UPDATE_TRACKING")
  local n = T.switches
  T.advance(20) check(T.active() == "Track Beasts" and T.switches == n, "left alone")
`);
console.log(`${pass} checks passed, ${fail} failed` + (EUI_ON ? ' (with a stand-in EllesmereUI)' : ''));
process.exit(fail ? 1 : 0);
