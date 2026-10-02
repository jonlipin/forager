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
}
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
function UnitIsDeadOrGhost() return false end
function UnitOnTaxi() return false end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function IsAltKeyDown() return false end
function IsControlKeyDown() return false end
function IsShiftKeyDown() return false end
function GetBindingAction(k) return T.bindings[k] or "" end
function GetCurrentKeyBoardFocus() return nil end
function tinsert(t, v) t[#t + 1] = v end
UISpecialFrames = {}
C_Spell = { GetSpellName = function(id) for _, t in ipairs(T.tracking) do if t.spellID == id then return t.name end end end,
            GetSpellCooldown = function() return { startTime = 0, duration = 0 } end }
local fire
C_Minimap = {
  GetNumTrackingTypes = function() return #T.tracking end,
  GetTrackingInfo = function(i) return T.tracking[i] end,
  SetTracking = function(i, on)
    local fromKey = T.inKey
    if T.blockAll or (T.blockTimer and not fromKey) then fire("ADDON_ACTION_BLOCKED", "Forager", "UNKNOWN()") return end
    for _, t in ipairs(T.tracking) do if t.type == "spell" then t.active = false end end
    T.tracking[i].active = on
    T.switches = (T.switches or 0) + 1
    fire("MINIMAP_UPDATE_TRACKING")
  end,
}
C_Timer = {
  After = function(d, f) T.timers[#T.timers + 1] = { at = T.now + d, f = f } end,
  NewTicker = function(d, f) T.ticker = f end,
}
local Frame = {}
Frame.__index = function(self, k) return Frame[k] or function() end end
function Frame:SetScript(n, f) self.scripts[n] = f if f and (n == "OnKeyDown" or n == "OnKeyUp") then self.keyboard = true end end
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
function Frame:GetScale() return self.scale or 1 end
function Frame:SetScale(v) self.scale = v end
function Frame:GetCenter() return nil end
function Frame:GetFrameLevel() return 1 end
function Frame:GetChecked() return self.checked end
function Frame:IsVisible() return false end
function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ scripts = {}, events = {}, name = name, keyboard = false, propagate = false }, Frame)
  T.frames[#T.frames + 1] = f
  if name then _G[name] = f end
  return f
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

let pass = 0, fail = 0;
function run(name, body) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const src = fs.readFileSync(path.join(__dirname, '..', 'Forager.lua'), 'utf8');
  const code = STUBS +
    `\nlocal chunk = assert(load(${JSON.stringify(src)}, "@Forager.lua"))\nchunk("Forager", {})\n` +
    `T.fire("ADDON_LOADED", "Forager")\nT.fire("PLAYER_LOGIN")\n` +
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
console.log(`${pass} checks passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
