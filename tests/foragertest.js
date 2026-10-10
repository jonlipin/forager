// Offline checks for Forager: runs Forager.lua in fengari against a stubbed client.
//   NODE_PATH=<dir with fengari> node tests/foragertest.js
'use strict';
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const STUBS = `
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
      for _, t in ipairs(T.tracking) do if t.type == "spell" then t.active = false end end
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
function Frame:ClearAllPoints() self._point, self._all = nil, nil end
function Frame:SetAllPoints(rel) self._all = rel or true end
function Frame:SetSwipeTexture(tex, r, g, b, a) self.swipe = tex end
function Frame:SetUseCircularEdge(on) self.circularEdge = on end
function Frame:SetAtlas(atlas) self.atlas = atlas end
function Frame:SetTexture(file) self.texture = file end
function Frame:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function Frame:SetPoint(...) self._point = { ... } end
function Frame:SetSize(w, h) self._w, self._h = w, h end
T.strings = {}
function Frame:CreateFontString() local fs = setmetatable({ scripts = {}, events = {} }, Frame) T.strings[#T.strings + 1] = fs return fs end
function T.string(text) for _, fs in ipairs(T.strings) do if rawget(fs, "text") == text then return fs end end end
function Frame:CreateTexture()
  local t = setmetatable({ scripts = {}, events = {} }, Frame)
  local list = rawget(self, "texs") or {}
  rawset(self, "texs", list)
  list[#list + 1] = t
  return t
end
function T.texCount(f) local list = rawget(f, "texs") return list and #list or 0 end
function T.drawSnapshot() local snap = {} for _, f in ipairs(T.frames) do snap[f] = T.texCount(f) end return snap end
function T.drawnSince(snap, f) return T.texCount(f) - (snap[f] or 0) end
GameFontNormalSmall, GameFontHighlight, GameFontDisable = { name = "GameFontNormalSmall" }, { name = "GameFontHighlight" }, { name = "GameFontDisable" }
function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ scripts = {}, events = {}, name = name, keyboard = false, propagate = false, parent = parent }, Frame)
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
  local glows = {}
  for _, f in ipairs(T.anims) do if true then glows[#glows + 1] = f end end
  check(#glows == 2, "two glow animations, got " .. #glows)
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
run('an unticked tracker leaves only one and nothing switches', `
  ForagerDB.rotation[2580] = nil
  T.advance(20) check(T.active() == nil, "one tracker is no rotation")
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
        if cd then check(rawget(cd, "swipe") == SWIPE_FILE and rawget(cd, "_all") == nil and not rawget(cd, "circularEdge"), name .. " Cooldown Manager sweep inside the frame") end
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
        if cd then check(rawget(cd, "swipe") == FLAT and rawget(cd, "_all") == icon and not rawget(cd, "circularEdge"), name .. " sweep square, over the icon") end
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
        check(rawget(circle.edge, "texture") == CIRCLE_FILE and rawget(circle.edge, "alpha") == (ringed and 0 or 1), name .. " dark edge " .. (ringed and "hidden" or "shown"))
        -- The ring texture is 64 across with its circle off centre: scaled by 36/32, its
        -- centre (20.05, 18.92) lands on the icon's.
        local rp = rawget(circle.ring, "_point")
        check(rawget(circle.ring, "_w") == 72 and rp[1] == "TOPLEFT" and rp[2] == icon and rp[3] == "CENTER"
          and math.abs(rp[4] + 22.56) < 0.01 and math.abs(rp[5] - 21.29) < 0.01, name .. " ring centred on the icon")
        check(circle.ringSize == 30, name .. " picture 30 across inside the ring, got " .. tostring(circle.ringSize))
        check(Same(rawget(circle.edge, "vertex"), { 0, 0, 0, 1 }) and rawget(circle.edge, "_w") == 38, name .. " dark edge one pixel past the circle")
        check(rawget(circle.hl, "alpha") == 1 and rawget(circle.hl, "_w") == d and rawget(circle.hl, "texture") == CIRCLE_FILE, name .. " round highlight")
        check(rawget(circle.press, "alpha") == 0, name .. " press art waits for a press")
        if cd then
          check(rawget(cd, "swipe") == CIRCLE_FILE and rawget(cd, "circularEdge") == true, name .. " circular sweep")
          check(rawget(cd, "_all") == nil and rawget(cd, "_w") == d, name .. " sweep the size of the circle")
        end
      end
      local glow = rawget(b, "glow")
      if glow then check(rawget(glow, "alpha") == nil, name .. " glow kept") end
    end
    check(#NS.trackButtons >= 2, "tracker icons built: " .. #NS.trackButtons)
    for _, b in ipairs(NS.trackButtons) do Icon(b, "${look}") end
    Icon(ForagerPauseButton, "${pause}")
    -- The tracker that is on still glows, and the next one still sweeps.
    local lit, sweeping = 0, 0
    for _, b in ipairs(NS.trackButtons) do
      if rawget(b, "lit") then lit = lit + 1 check(b.glow.shown and b.anim.playing, "glow on the tracker that is on") end
      if rawget(b.cd, "shown") then sweeping = sweeping + 1 end
    end
    check(lit == 1 and sweeping == 1, "one glowing, one sweeping: " .. lit .. ", " .. sweeping)
  end
`;
}
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
    for _, b in ipairs(NS.trackButtons) do check(T.drawnSince(SNAP, b) == 0, rawget(b, "name") .. " not drawn on twice") end
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
  ` + ICONS('circle-ring', 'dark', 'bar') + `
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
  ` + ICONS('circle-ring', 'dark', 'bar') + `
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
  ` + ICONS('circle-ring', 'dark', 'bar') + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  `, { atlas: true });
  run('icon shape: Round under Dark, live; the pause button stays square', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
  ` + OPEN + ICONS('square') + `
    local shape = NS.shapeButton
    shape.scripts.OnClick(shape, "LeftButton")
    check(ForagerDB.iconShape == "round", "Round chosen")
    check(NS.Styles.Applied() == "dark", "still Dark")
  ` + ICONS('circle-edge', 'dark', 'square') + `
    ForagerDB.rotation[1494] = true
    T.advance(1)
    check(ForagerTrackButton3 ~= nil and rawget(ForagerTrackButton3, "fgShape") == "circle-edge", "an icon built later comes round")
  ` + ICONS('circle-edge', 'dark', 'square') + `
    shape.scripts.OnClick(shape, "LeftButton")
    check(ForagerDB.iconShape == "square", "Square chosen")
  ` + ICONS('square') + `
    shape.scripts.OnClick(shape, "LeftButton")
    check(ForagerDB.iconShape == "auto", "back to Automatic")
  ` + ICONS('square') + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  `, { atlas: true, db: '{ style = "dark" }' });
  run('icon shape: Round saved under Dark; the pause button is still squared at login', `
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(6.5)
    check(NS.Styles.Applied() == "dark", "Dark")
  ` + ICONS('circle-edge', 'dark', 'square'), { atlas: true, db: '{ style = "dark", iconShape = "round" }' });
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
  ` + ICONS('circle-ring', 'dark', 'bar') + `
    SlashCmdList.FORAGER("style dark")
  ` + ICONS('circle-edge', 'dark', 'square') + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
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
    local look, trackers = T.string("Look"), T.string("Trackers to rotate")
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
      if p and rawget(f, "parent") == content and p[2] == 12 and p[3] <= -476 then
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
  ` + ICONS('circle-edge', 'eui', 'square') + `
    SlashCmdList.FORAGER("shape square")
  ` + ICONS('square', 'eui') + `
    local n, errs = T.skinErrors()
    check(n == 0, "no skin errors: " .. errs)
  `, { atlas: true });
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

console.log(`${pass} checks passed, ${fail} failed` + (EUI_ON ? ' (with a stand-in EllesmereUI)' : ''));
process.exit(fail ? 1 : 0);
