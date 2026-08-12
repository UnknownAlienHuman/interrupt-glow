local IG = _G.InterruptGlow
if not IG then return end

local Private = IG.Private
local DB = Private.DB
local IsSecret = Private.IsSecret
local CreateFrame = Private.CreateFrame
local CanHarm = Private.CanHarm
local GuardedCall = Private.GuardedCall
local CurrentNI = function(unit)
    return Private.CurrentNI and Private.CurrentNI(unit)
end
local TRACKED_UNITS = Private.TRACKED_UNITS
local CastActive = Private.CastActive
local CastNISrc = Private.CastNISrc

local PROC_TEMPLATES = {
    "ActionButtonSpellAlertTemplate",
    "ActionBarButtonSpellActivationAlert",
    "ActionButtonSpellActivationAlert",
    "SpellActivationAlertTemplate",
    "SpellActivationAlert",
}

local ButtonAlerts = setmetatable({}, { __mode = "k" })
local AlertTemplates = setmetatable({}, { __mode = "k" })
local HookedAlerts = setmetatable({}, { __mode = "k" })

local function EnsureIGAlert(btn)
    if not btn or not CreateFrame then return nil end
    if btn.IsForbidden and btn:IsForbidden() then return nil end
    if ButtonAlerts[btn] then return ButtonAlerts[btn] end

    local width, height = 0, 0
    if btn.GetSize then width, height = btn:GetSize() end

    for i = 1, #PROC_TEMPLATES do
        local template = PROC_TEMPLATES[i]
        local ok, frame = GuardedCall("glow:create-alert:" .. tostring(template), CreateFrame, "Frame", nil, btn, template)
        if ok and frame then
            if width and height and width > 0 and height > 0 then
                frame:SetSize(width * 1.4, height * 1.4)
            else
                frame:SetAllPoints(btn)
            end
            frame:SetPoint("CENTER", btn, "CENTER", 0, 0)
            frame:SetFrameStrata("HIGH")
            frame:SetFrameLevel((btn.GetFrameLevel and btn:GetFrameLevel() or 0) + 50)
            frame:Hide()
            ButtonAlerts[btn] = frame
            AlertTemplates[btn] = template
            return frame
        end
    end

    return nil
end

local function SafePlay(obj)
    if obj and obj.Play then
        GuardedCall("glow:anim-play", obj.Play, obj)
        return true
    end
    return false
end

local function SafeStop(obj)
    if obj and obj.Stop then
        GuardedCall("glow:anim-stop", obj.Stop, obj)
        return true
    end
    return false
end

local function StartProc(alert)
    if not alert then return end

    local start = alert.ProcStartAnim or alert.procStartAnim or alert.AnimIn or alert.animIn
    local loop = alert.ProcLoopAnim or alert.procLoopAnim or alert.AnimLoop or alert.animLoop
    local startFB = alert.ProcStartFlipbook or alert.procStartFlipbook
    local loopFB = alert.ProcLoopFlipbook or alert.procLoopFlipbook
    local loopFB2 = alert.ProcLoopFlipbook2 or alert.procLoopFlipbook2
    local loopFB3 = alert.ProcLoopFlipbook3 or alert.procLoopFlipbook3
    local out = alert.ProcEndAnim or alert.procEndAnim or alert.AnimOut or alert.animOut
    if out and out.IsPlaying and out:IsPlaying() then GuardedCall("glow:anim-stop-out", out.Stop, out) end
    SafePlay(start or startFB)
    SafePlay(loop or loopFB)
    SafePlay(loopFB2)
    SafePlay(loopFB3)
end

local function StopProc(alert)
    if not alert then return end

    local out = alert.ProcEndAnim or alert.procEndAnim or alert.AnimOut or alert.animOut
    if out and out.Play then
        GuardedCall("glow:anim-play-out", out.Play, out)
        return
    end

    SafeStop(alert.ProcStartAnim or alert.procStartAnim or alert.AnimIn or alert.animIn)
    SafeStop(alert.ProcLoopAnim or alert.procLoopAnim or alert.AnimLoop or alert.animLoop)
    SafeStop(alert.ProcStartFlipbook or alert.procStartFlipbook)
    SafeStop(alert.ProcLoopFlipbook or alert.procLoopFlipbook)
    SafeStop(alert.ProcLoopFlipbook2 or alert.procLoopFlipbook2)
    SafeStop(alert.ProcLoopFlipbook3 or alert.procLoopFlipbook3)
end

local function HookAlertAnims(alert)
    if not alert or HookedAlerts[alert] or not alert.HookScript then return end
    HookedAlerts[alert] = true
    alert:HookScript("OnShow", function(self) StartProc(self) end)
    alert:HookScript("OnHide", function(self) StopProc(self) end)
end

local function ShowGlow(btn)
    local alert = EnsureIGAlert(btn)
    if not alert then return end
    HookAlertAnims(alert)
    alert:SetShown(true)
end

local function HideGlow(btn)
    local alert = btn and ButtonAlerts[btn]
    if not alert then return end
    HookAlertAnims(alert)
    alert:SetShown(false)
end

function IG:SetGlow(active)
    if IsSecret(active) then
        active = false
    end

    active = active and true or false
    if active == self.glowActive then return end
    self.glowActive = active
    self._glowSecretReady = nil

    if active then
        for i = 1, #self.trackedButtons do
            ShowGlow(self.trackedButtons[i])
        end
        for i = 1, #self.extraButtons do
            ShowGlow(self.extraButtons[i])
        end
    else
        for i = 1, #self.trackedButtons do
            HideGlow(self.trackedButtons[i])
        end
        for i = 1, #self.extraButtons do
            HideGlow(self.extraButtons[i])
        end
    end
end

function IG:ApplyGlowDecision()
    if not self.interruptReadyIsSecret and not self.interruptReady then
        self:SetGlow(false)
        return
    end

    for i = 1, #TRACKED_UNITS do
        local unit = TRACKED_UNITS[i]
        local ni, niBar, niUnit, niEvt = CurrentNI(unit)
        if CanHarm(unit) and CastActive[unit] then
            local allowUnknown = (ni == nil and not DB.strictNI)
            if ni == false or allowUnknown then
                self:SetGlow(true)
                if DB and DB.debug then
                    IG:StatInc("ni", (ni == false) and "allow" or "allow-unknown")
                end
                return
            end
            if ni == true then
                if DB and DB.debug then IG:StatInc("ni", "block-ni") end
            elseif ni == nil and DB.strictNI then
                if DB and DB.debug then
                    IG:StatInc("ni", "block-unknown")
                    local now = Private.SafeNow()
                    local key = unit .. ":unknown"
                    if (self._dbgLastBlockTs == nil)
                        or (type(self._dbgLastBlockTs[key]) ~= "number")
                        or ((now - self._dbgLastBlockTs[key]) > 0.5) then
                        self._dbgLastBlockTs = self._dbgLastBlockTs or {}
                        self._dbgLastBlockTs[key] = now
                        Private.Debug(
                            ("NI unknown (strict): unit=%s srcT=%s srcF=%s bar=%s unitNI=%s evt=%s")
                                :format(
                                    tostring(unit),
                                    tostring(CastNISrc.target),
                                    tostring(CastNISrc.focus),
                                    tostring(niBar),
                                    tostring(niUnit),
                                    tostring(niEvt)
                                ),
                            2,
                            "ni"
                        )
                    end
                end
            end
        end
    end

    self:SetGlow(false)
end

IG._glowDirty = IG._glowDirty or false

local glowFlushFrame = CreateFrame("Frame")
glowFlushFrame:Hide()
glowFlushFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    if IG._glowDirty then
        IG._glowDirty = false
        IG:ApplyGlowDecision()
    end
end)

function IG:MarkGlowDirty()
    if self._disabled then return end
    if self._glowDirty then return end
    self._glowDirty = true
    glowFlushFrame:Show()
end

Private.ShowGlow = ShowGlow
Private.HideGlow = HideGlow
