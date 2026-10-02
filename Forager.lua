-- Forager: switches between Find Herbs and Find Minerals on a set delay while
-- you are out of combat.
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
    -- method: nil = not learned yet, "timer", "key", "none"
}

local db
local lastSwitch = 0   -- GetTime() of the last change to herbs or minerals
local lastActive       -- "herbs", "minerals" or nil, as last seen
local attempt          -- the switch waiting to be confirmed
local silentFails = 0
local RefreshOptions, UpdateMinimapButton, SetUpKeys -- defined below

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

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- Finds the two tracking entries and what is switched on.
-- other = the name of a tracking spell that is neither of ours, when it is on.
local function Scan()
    local s = {}
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return s end
    local herbName, mineralName = SpellName(HERBS), SpellName(MINERALS)
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if info then
            local which
            if info.spellID == HERBS or (herbName and info.name == herbName) then
                which = "herbs"
            elseif info.spellID == MINERALS or (mineralName and info.name == mineralName) then
                which = "minerals"
            end
            if which then s[which] = i end
            if info.active then
                if which then
                    s.active = which
                elseif info.spellID or info.type == "spell" then
                    s.other = info.name or "another tracking spell"
                end
            end
        end
    end
    return s
end

local function Busy()
    local ok, casting = pcall(function()
        return (UnitCastingInfo and UnitCastingInfo("player")) or (UnitChannelInfo and UnitChannelInfo("player"))
    end)
    return ok and casting ~= nil
end

local function OnCooldown()
    if not (C_Spell and C_Spell.GetSpellCooldown) then return false end
    local ok, onCd = pcall(function()
        local cd = C_Spell.GetSpellCooldown(HERBS)
        if not cd then return false end
        if issecretvalue and (issecretvalue(cd.startTime) or issecretvalue(cd.duration)) then return false end
        return cd.startTime > 0 and cd.duration > 0 and cd.startTime + cd.duration > GetTime()
    end)
    return ok and onCd
end

-- Returns nil when a switch may happen now, else the reason it may not.
local function Blocker(s)
    if not db.enabled then return "switched off" end
    if db.method == "none" then return "the game refuses the switch" end
    if InCombatLockdown() or UnitAffectingCombat("player") then return "in combat" end
    if UnitIsDeadOrGhost("player") then return "dead" end
    if UnitOnTaxi("player") then return "on a flight" end
    if not (s.herbs and s.minerals) then return "you need both Find Herbs and Find Minerals" end
    if s.other then return s.other .. " is on" end
    if Busy() then return "casting" end
    if OnCooldown() then return "global cooldown" end
end

local function Due()
    return GetTime() - lastSwitch >= db.delay
end

local function Verify()
    local a = attempt
    if not a or a.done then return end
    a.done = true
    local s = Scan()
    if s.active == a.target then
        silentFails = 0
        if db.method == nil then
            db.method = "timer"
            Log("method learned: timer")
        end
        Log("switched to " .. a.target .. " (" .. a.source .. ")")
    elseif not a.blocked then
        silentFails = silentFails + 1
        Log("switch to " .. a.target .. " (" .. a.source .. ") did not take, now " .. tostring(s.active) .. ", " .. silentFails .. " in a row")
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

local function TrySwitch(source)
    if not Due() then return end
    local s = Scan()
    if Blocker(s) then return end
    if attempt and not attempt.done then return end
    local target = s.active == "herbs" and "minerals" or "herbs"
    attempt = { at = GetTime(), target = target, source = source }
    local ok, err = pcall(C_Minimap.SetTracking, s[target], true)
    if not ok then Log("SetTracking error: " .. tostring(err)) end
    -- Count the try as a switch so a refusal is not repeated every tick.
    lastSwitch = GetTime()
    C_Timer.After(1, Verify)
end

local function OnTrackingChanged()
    local active = Scan().active
    if active ~= lastActive then
        if active then lastSwitch = GetTime() end
        lastActive = active
        if RefreshOptions then RefreshOptions() end
        if UpdateMinimapButton then UpdateMinimapButton() end
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
    else
        db.method = "none"
        Log("method learned: none")
        Print("the game refuses addon tracking switches altogether, so Forager can't switch for you. /forager retest tries again.")
    end
    if RefreshOptions then RefreshOptions() end
end

---------------------------------------------------------------------------
-- Key press mode
---------------------------------------------------------------------------

local ABILITY_BINDINGS = {
    "^ACTIONBUTTON", "^MULTIACTIONBAR", "^BONUSACTIONBUTTON", "^SHAPESHIFTBUTTON",
    "^PETACTIONBUTTON", "^CLICK ", "^SPELL ", "^MACRO ", "^ITEM ", "^INTERACT",
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

local keyFrame = CreateFrame("Frame", "ForagerKeyListener", UIParent)
local keysReady = false

keyFrame:SetScript("OnKeyDown", function(_, key)
    if db.method ~= "key" then return end
    if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return end
    if db.skipAbilityKeys and IsAbilityKey(key) then return end
    TrySwitch("key")
end)

-- The listener lets every key through to the game. Setting that up is not
-- allowed in combat, so it waits for combat to end.
SetUpKeys = function()
    if keysReady or db.method ~= "key" then return end
    if InCombatLockdown() then return end
    keyFrame:SetPropagateKeyboardInput(true)
    keyFrame:EnableKeyboard(true)
    keysReady = true
    Log("key listener on")
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

local NAMES = { herbs = "Find Herbs", minerals = "Find Minerals" }

local function MethodText()
    if db.method == "timer" then return "on a timer" end
    if db.method == "key" then return "on your next key press after the delay" end
    if db.method == "none" then return "|cffff5050refused by the game|r" end
    return "on a timer (first switch still to come)"
end

local function StatusText()
    local s = Scan()
    local now = s.active and NAMES[s.active] or s.other or "nothing"
    local lines = { "Tracking: |cffffffff" .. now .. "|r", "Switches " .. MethodText() }
    local reason = Blocker(s)
    if reason then
        lines[#lines + 1] = "|cffffb040Waiting: " .. reason .. "|r"
    else
        local left = db.delay - (GetTime() - lastSwitch)
        if left > 0 then
            lines[#lines + 1] = string.format("Next switch in %d s", math.ceil(left))
        elseif db.method == "key" then
            lines[#lines + 1] = "Next switch on your next key press"
        else
            lines[#lines + 1] = "Switching now"
        end
    end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local optionRefreshers = {}
local content, window, settingsPage, settingsCategory
local nativeOpenFailed = false
local W, CONTENT_H = 360, 250

local function TryCreate(kind, name, parent, templates)
    for _, template in ipairs(templates) do
        local ok, made = pcall(CreateFrame, kind, name, parent, template)
        if ok and made then return made, template end
    end
    return CreateFrame(kind, name, parent), "bare"
end

local function OptionCheck(parent, label, key, y, after)
    local cb = TryCreate("CheckButton", nil, parent, { "UICheckButtonTemplate", "ChatConfigCheckButtonTemplate" })
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 12, y)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label)
    cb:SetScript("OnClick", function(self)
        db[key] = self:GetChecked() and true or false
        if after then after() end
    end)
    optionRefreshers[#optionRefreshers + 1] = function() cb:SetChecked(db[key] and true or false) end
    return cb
end

local function OptionSlider(parent, label, key, minV, maxV, y)
    local name = "ForagerOptionsSlider" .. key
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", 16, y)
    holder:SetSize(W - 40, 40)
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
    slider:SetSize(W - 46, 18)
    slider:SetMinMaxValues(minV, maxV)
    if slider.SetValueStep then slider:SetValueStep(1) end
    if slider.SetObeyStepOnDrag then pcall(slider.SetObeyStepOnDrag, slider, true) end
    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        value:SetText(v .. " s")
        if self.syncing then return end
        db[key] = v
    end)
    optionRefreshers[#optionRefreshers + 1] = function()
        slider.syncing = true
        slider:SetValue(db[key])
        slider.syncing = false
        value:SetText(db[key] .. " s")
    end
end

local function BuildContent()
    local c = CreateFrame("Frame")
    c:SetSize(W, CONTENT_H)

    OptionCheck(c, "Switch between Find Herbs and Find Minerals", "enabled", -8, function()
        if UpdateMinimapButton then UpdateMinimapButton() end
    end)
    OptionSlider(c, "Time between switches", "delay", 2, 60, -44)
    OptionCheck(c, "Leave ability keys alone (key press mode)", "skipAbilityKeys", -92)
    OptionCheck(c, "Show the minimap button", "minimap", -120, function()
        if UpdateMinimapButton then UpdateMinimapButton() end
    end)

    local status = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOPLEFT", 16, -160)
    status:SetWidth(W - 32)
    status:SetJustifyH("LEFT")
    status:SetSpacing(3)
    optionRefreshers[#optionRefreshers + 1] = function() status:SetText(StatusText()) end

    local retest = TryCreate("Button", nil, c, { "UIPanelButtonTemplate" })
    retest:SetSize(150, 22)
    retest:SetPoint("TOPLEFT", 14, -222)
    retest:SetText("Try the timer again")
    retest:SetScript("OnClick", function()
        db.method = nil
        silentFails = 0
        Log("method reset from options")
        RefreshOptions()
    end)

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

local function Host(parent, x, y)
    content:SetParent(parent)
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
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
        Host(self, 6, -42)
    end)
    local category = Settings.RegisterCanvasLayoutCategory(page, "Forager")
    if category then
        Settings.RegisterAddOnCategory(category)
        settingsPage, settingsCategory = page, category
    end
end

---------------------------------------------------------------------------
-- Minimap button: left-click on/off, right-click options, drag to move
---------------------------------------------------------------------------

local mmButton, mmIcon

local function PlaceMinimapButton()
    local angle = math.rad(db.minimapAngle or 225)
    local radius = (Minimap:GetWidth() or 140) / 2 + 6
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function Toggle(on)
    if on == nil then on = not db.enabled end
    db.enabled = on and true or false
    if on then lastSwitch = GetTime() end
    Print(db.enabled and "on" or "off")
    UpdateMinimapButton()
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
            if button == "RightButton" then ToggleOptions() else Toggle() end
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
            GameTooltip:SetText("Forager " .. (db.enabled and "|cff40ff40on|r" or "|cffff4040off|r"), 1, 1, 1)
            GameTooltip:AddLine(StatusText(), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click: switch on / off", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Drag: move around the minimap", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        mmButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    mmIcon:SetDesaturated(not db.enabled)
    mmButton:SetShown(db.minimap and true or false)
    PlaceMinimapButton()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

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
    elseif cmd == "retest" then
        db.method = nil
        silentFails = 0
        Log("method reset by /forager retest")
        Print("trying the timer again")
    elseif cmd == "debug" then
        local s = Scan()
        Print(StatusText():gsub("\n", " | "))
        Print(string.format("entries: herbs=%s minerals=%s active=%s other=%s method=%s keys=%s",
            tostring(s.herbs), tostring(s.minerals), tostring(s.active), tostring(s.other),
            tostring(db.method), tostring(keysReady)))
    else
        Print("/forager (options), on, off, toggle, delay <seconds>, retest, debug")
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
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ForagerDB = ForagerDB or {}
        db = ForagerDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        ForagerLog = ForagerLog or {}
        ForagerLog.lines = ForagerLog.lines or {}
        ForagerLog.session = (ForagerLog.session or 0) + 1
    elseif event == "PLAYER_LOGIN" then
        lastSwitch = GetTime()
        lastActive = Scan().active
        local s = Scan()
        Log(string.format("login: herbs=%s minerals=%s active=%s other=%s method=%s delay=%s enabled=%s",
            tostring(s.herbs), tostring(s.minerals), tostring(s.active), tostring(s.other),
            tostring(db.method), tostring(db.delay), tostring(db.enabled)))
        RegisterOptionsPage()
        UpdateMinimapButton()
        SetUpKeys()
        C_Timer.NewTicker(0.25, function()
            if db.method == nil or db.method == "timer" then TrySwitch("timer") end
        end)
    elseif event == "MINIMAP_UPDATE_TRACKING" then
        OnTrackingChanged()
    elseif event == "PLAYER_REGEN_ENABLED" then
        SetUpKeys()
    else
        OnRefused(event, arg1)
    end
end)
