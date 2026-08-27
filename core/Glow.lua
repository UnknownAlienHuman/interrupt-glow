local IG = _G.InterruptGlow
if not IG then return end

local Glow = {
    prewarmQueue = {},
    prewarmHead = 1,
    prewarmTail = 0,
    prewarmQueued = setmetatable({}, { __mode = "k" }),
    prewarmBudgetPerFrame = 16,
    driverElapsed = 0,
    restrictedPollElapsed = 0,
    countdownTextElapsed = 0,
    sameTrackedUnit = false,
}
IG.Glow = Glow
IG:RegisterModule("Glow", Glow)

local _G = _G
local CreateFrame = _G.CreateFrame
local UnitIsUnit = _G.UnitIsUnit
local math_ceil = math.ceil
local pairs = pairs
local type = type
local pcall = pcall
local next = next

local UNITS = { "target", "focus" }
local ALPHA_HIDDEN = 0
local ALPHA_VISIBLE = 255

local function ApplySecretBoolean(region, value, alphaIfTrue, alphaIfFalse)
    if not region then return false end

    if IG.CanAccess(value) then
        region:SetAlpha(value == true and (alphaIfTrue / 255) or (alphaIfFalse / 255))
        return true
    end

    local method = region.SetAlphaFromBoolean
    if type(method) ~= "function" then
        region:SetAlpha(0)
        return false
    end

    -- The only raw SecretValue sink in the addon. Do not compare, store,
    -- format, return or wrap the value in pcall. Blizzard's API accepts secret
    -- boolean arguments from addon code and carries the Alpha secret aspect.
    method(region, value, alphaIfTrue, alphaIfFalse)
    return true
end

local function SafeFrameLevel(button)
    if button and type(button.GetFrameLevel) == "function" then
        local ok, value = pcall(button.GetFrameLevel, button)
        if ok and IG.CanAccess(value) and type(value) == "number" then
            return value
        end
    end
    return 1
end

local function ConfigureGlowTexture(texture, gate)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", gate, "TOPLEFT", -10, 10)
    texture:SetPoint("BOTTOMRIGHT", gate, "BOTTOMRIGHT", 10, -10)
    texture:SetBlendMode("ADD")

    local atlasApplied = false
    if type(texture.SetAtlas) == "function" then
        atlasApplied = pcall(texture.SetAtlas, texture, "UI-HUD-RotationHelper-ProcAltGlow", false)
    end
    if not atlasApplied then
        texture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    end

    -- Vertex color is configured once, before any secret alpha reaches the
    -- region. Runtime candidate state is applied to the parent frame instead.
    texture:SetVertexColor(1, 0.82, 0, 1)
    texture:SetAlpha(1)
    texture:Show()
end

local function CreateUnitBranch(button)
    local plainGate = CreateFrame("Frame", nil, button)
    plainGate:SetAllPoints(button)
    plainGate:SetFrameLevel(SafeFrameLevel(button) + 8)
    plainGate:SetAlpha(0)
    plainGate:Show()

    local niGate = plainGate:CreateTexture(nil, "OVERLAY", nil, 7)
    ConfigureGlowTexture(niGate, plainGate)

    return {
        plainGate = plainGate,
        niGate = niGate,
        candidate = false,
        animation = nil,
    }
end

local function CreatePulseAnimation(texture)
    if not texture or type(texture.CreateAnimationGroup) ~= "function" then
        return nil
    end

    local ok, group = pcall(texture.CreateAnimationGroup, texture)
    if not ok or not group or type(group.CreateAnimation) ~= "function" then
        return nil
    end

    group:SetLooping("BOUNCE")
    local scale = group:CreateAnimation("Scale")
    scale:SetDuration(0.55)
    scale:SetScale(1.06, 1.06)
    if type(scale.SetSmoothing) == "function" then
        scale:SetSmoothing("IN_OUT")
    end
    return group
end

local function SetCandidate(branch, candidate)
    if not branch or branch.candidate == candidate then return end
    branch.candidate = candidate
    branch.plainGate:SetAlpha(candidate and 1 or 0)

    if candidate then
        if branch.animation then branch.animation:Play() end
        IG:BumpStat("ui.showTransitions")
    else
        if branch.animation then branch.animation:Stop() end
        IG:BumpStat("ui.hideTransitions")
    end
end

local function ReadinessPending(record)
    return record
        and record.ability
        and record.ability.readinessPending == true
end

function Glow:CreateShell(record)
    if not record or not record.button then return nil end
    if record.overlay then return record.overlay end
    if IG:IsInCombat() then
        record.overlayPending = true
        return nil
    end

    local button = record.button
    if button.IsForbidden then
        local ok, forbidden = pcall(button.IsForbidden, button)
        if ok and forbidden then
            record.overlayForbidden = true
            record.overlayPending = false
            return nil
        end
    end

    record.overlay = {
        target = CreateUnitBranch(button),
        focus = CreateUnitBranch(button),
        cooldownText = nil,
        enhanced = false,
    }
    record.overlayPending = false
    record.overlayQueued = false
    self.prewarmQueued[record] = nil
    IG:BumpStat("ui.shellsCreated")
    return record.overlay
end

function Glow:QueueShell(record, urgent)
    if not record or record.overlay or record.overlayForbidden then return end

    if urgent and not IG:IsInCombat() then
        self:CreateShell(record)
        return
    end

    record.overlayPending = true
    if not self.prewarmQueued[record] then
        self.prewarmQueued[record] = true
        record.overlayQueued = true
        self.prewarmTail = self.prewarmTail + 1
        self.prewarmQueue[self.prewarmTail] = record
    end

    if not IG:IsInCombat() then
        self.prewarmFrame:Show()
    end
end

function Glow:ProcessPrewarmBudget()
    if IG:IsInCombat() then
        self.prewarmFrame:Hide()
        return
    end

    local created = 0
    while created < self.prewarmBudgetPerFrame and self.prewarmHead <= self.prewarmTail do
        local record = self.prewarmQueue[self.prewarmHead]
        self.prewarmQueue[self.prewarmHead] = nil
        self.prewarmHead = self.prewarmHead + 1

        if record then
            self.prewarmQueued[record] = nil
            record.overlayQueued = false
            if not record.overlay and not record.overlayForbidden and self:CreateShell(record) then
                created = created + 1
                if record.isInterrupt then self:EnsureInterruptVisuals(record) end
            end
        end
    end

    if self.prewarmHead > self.prewarmTail then
        self.prewarmQueue = {}
        self.prewarmHead = 1
        self.prewarmTail = 0
        self.prewarmFrame:Hide()
    end
end

function Glow:EnsureCooldownText(record)
    if not IG.DB.cdText then return nil end
    local overlay = record and record.overlay
    if not overlay then return nil end
    if overlay.cooldownText then return overlay.cooldownText end
    if IG:IsInCombat() then
        record.cooldownTextPending = true
        return nil
    end

    local text = record.button:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    text:SetPoint("CENTER", record.button, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetText("")
    text:Show()
    overlay.cooldownText = text
    record.cooldownTextPending = false
    IG:BumpStat("ui.cooldownTextsCreated")
    return text
end

function Glow:EnsureInterruptVisuals(record)
    local overlay = record and (record.overlay or self:CreateShell(record))
    if not overlay then return false end

    local changed = false
    if not overlay.enhanced then
        if IG:IsInCombat() then
            record.enhancementPending = true
            return false
        end

        -- Animate the ordinary parent gate, never the child texture that may
        -- carry Blizzard's Alpha secret aspect after restricted cast feedback.
        overlay.target.animation = CreatePulseAnimation(overlay.target.plainGate)
        overlay.focus.animation = CreatePulseAnimation(overlay.focus.plainGate)
        overlay.enhanced = true
        record.enhancementPending = false
        IG:BumpStat("ui.interruptVisualsCreated")
        changed = true

        if overlay.target.candidate and overlay.target.animation then overlay.target.animation:Play() end
        if overlay.focus.candidate and overlay.focus.animation then overlay.focus.animation:Play() end
    end

    if IG.DB.cdText and not overlay.cooldownText then
        changed = self:EnsureCooldownText(record) ~= nil or changed
    end
    return changed
end

function Glow:CreatePendingOverlays()
    if IG:IsInCombat() then return end

    local changed = false
    for _, record in pairs(IG.ObservedButtons) do
        if record.isInterrupt and not record.overlay then
            changed = self:CreateShell(record) ~= nil or changed
        end
        if record.isInterrupt then
            changed = self:EnsureInterruptVisuals(record) or changed
        end
    end

    if self.prewarmHead <= self.prewarmTail then self.prewarmFrame:Show() end
    if changed and IG.CastTracking then IG:MarkCastDirty() end
    IG:MarkVisualDirty()
end

function Glow:EnsureCooldownTexts()
    if not IG.DB.cdText or IG:IsInCombat() then return end
    for record in pairs(IG.InterruptRecords) do
        self:EnsureCooldownText(record)
    end
    self:RefreshAll()
end

function Glow:ClearRecord(record)
    local overlay = record and record.overlay
    if not overlay then return end

    SetCandidate(overlay.target, false)
    SetCandidate(overlay.focus, false)
    if overlay.cooldownText then overlay.cooldownText:SetText("") end
    record.lastCooldownText = ""
    self:UpdateRuntimeDriver()
end

function Glow:ApplyStoredInterruptibilityToRecord(record)
    local overlay = record and record.overlay
    if not overlay then return true end

    local needsRestrictedRefresh = false
    for index = 1, #UNITS do
        local unit = UNITS[index]
        local state = IG.CastState[unit]
        local branch = overlay[unit]
        if state and branch then
            if not state.active or state.niState == "none" or state.niState == "interruptible" then
                branch.niGate:SetAlpha(1)
            elseif state.niState == "not-interruptible" then
                branch.niGate:SetAlpha(0)
            elseif state.niState == "unknown" then
                branch.niGate:SetAlpha(IG.DB.strictNI and 0 or 1)
            elseif state.niState == "restricted" then
                -- Raw SecretValue is intentionally not retained. Fail closed for
                -- a newly-bound button and request one fresh unit snapshot.
                branch.niGate:SetAlpha(0)
                needsRestrictedRefresh = true
            end
        end
    end
    return not needsRestrictedRefresh
end

function Glow:ApplyUnitInterruptibility(unit, rawNotInterruptible, active)
    if unit ~= "target" and unit ~= "focus" then return end

    local testMode = IG.testMode == true
    for record in pairs(IG.InterruptRecords) do
        local branch = record.overlay and record.overlay[unit]
        if branch then
            if not active or testMode then
                branch.niGate:SetAlpha(1)
            elseif IG.CanAccess(rawNotInterruptible) then
                if rawNotInterruptible == nil then
                    branch.niGate:SetAlpha(IG.DB.strictNI and 0 or 1)
                elseif rawNotInterruptible == true then
                    branch.niGate:SetAlpha(0)
                else
                    branch.niGate:SetAlpha(1)
                end
            else
                ApplySecretBoolean(
                    branch.niGate,
                    rawNotInterruptible,
                    ALPHA_HIDDEN,
                    ALPHA_VISIBLE
                )
                IG:BumpStat("secret.visualGateCalls")
            end
        end
    end
end

function Glow:RefreshUnitRelation()
    self.sameTrackedUnit = false
    if type(UnitIsUnit) ~= "function" then return end

    local ok, same = pcall(UnitIsUnit, "target", "focus")
    if ok and IG.CanAccess(same) and same == true then
        self.sameTrackedUnit = true
    end
end

function Glow:HasRelevantCast()
    if IG.DB.enabled ~= true then return false end

    for index = 1, #UNITS do
        local unit = UNITS[index]
        local state = IG.CastState[unit]
        if state
            and state.active == true
            and state.hostile == true
            and state.niState ~= "not-interruptible"
            and not (state.niState == "unknown" and IG.DB.strictNI == true)
        then
            return true
        end
    end
    return false
end

local function CandidateFor(record, unit)
    if IG.testMode then return record.isInterrupt == true end

    local castState = IG.CastState[unit]
    if not castState then return false end
    if unit == "focus" and Glow.sameTrackedUnit then return false end

    return IG.DB.enabled == true
        and record.isInterrupt == true
        and not ReadinessPending(record)
        and record.ready == true
        and castState.active == true
        and castState.hostile == true
        and castState.niState ~= "not-interruptible"
        and not (castState.niState == "unknown" and IG.DB.strictNI == true)
end

function Glow:RefreshRecord(record)
    if not record then return end
    if not record.overlay then
        self:QueueShell(record, record.isInterrupt == true)
        return
    end

    for index = 1, #UNITS do
        local unit = UNITS[index]
        SetCandidate(record.overlay[unit], CandidateFor(record, unit))
    end
    self:RefreshCooldownText(record, IG:Now())
end

function Glow:RefreshUnit(unit)
    if unit ~= "target" and unit ~= "focus" then return end
    for record in pairs(IG.InterruptRecords) do
        if record.overlay then
            SetCandidate(record.overlay[unit], CandidateFor(record, unit))
        end
    end
    self:UpdateRuntimeDriver()
end

function Glow:RefreshAll()
    for record in pairs(IG.InterruptRecords) do
        self:RefreshRecord(record)
    end
    self:UpdateRuntimeDriver()
end

function Glow:RefreshCooldownText(record, now)
    if not record then return false end
    local text = record.overlay and record.overlay.cooldownText
    if IG.DB.enabled and IG.DB.cdText and not text then text = self:EnsureCooldownText(record) end
    if not text then return false end

    if IG.DB.enabled ~= true
        or not IG.DB.cdText
        or not record.isInterrupt
        or ReadinessPending(record)
        or record.ready
        or record.restrictedCooldown
    then
        if record.lastCooldownText ~= "" then
            record.lastCooldownText = ""
            text:SetText("")
        end
        return false
    end

    local deadline = record.deadline
    if type(deadline) ~= "number" then
        if record.lastCooldownText ~= "" then
            record.lastCooldownText = ""
            text:SetText("")
        end
        return false
    end

    local remaining = deadline - now
    if remaining <= 0 then
        if record.lastCooldownText ~= "" then
            record.lastCooldownText = ""
            text:SetText("")
        end
        return false
    end

    local value = tostring(math_ceil(remaining))
    if value ~= record.lastCooldownText then
        record.lastCooldownText = value
        text:SetText(value)
    end
    return true
end

local prewarmFrame = CreateFrame("Frame")
prewarmFrame:Hide()
Glow.prewarmFrame = prewarmFrame
prewarmFrame:SetScript("OnUpdate", function()
    Glow:ProcessPrewarmBudget()
end)

local runtimeFrame = CreateFrame("Frame")
runtimeFrame:Hide()
Glow.runtimeFrame = runtimeFrame
runtimeFrame:SetScript("OnUpdate", function(self, elapsed)
    local relevantCast = Glow:HasRelevantCast()
    local allowCountdown = IG.DB.enabled == true and IG.DB.cdText == true
    if not relevantCast and not allowCountdown then
        self:Hide()
        return
    end

    Glow.driverElapsed = Glow.driverElapsed + elapsed
    Glow.restrictedPollElapsed = Glow.restrictedPollElapsed + elapsed
    Glow.countdownTextElapsed = Glow.countdownTextElapsed + elapsed

    local runFast = Glow.driverElapsed >= 0.05
    local runRestrictedPoll = Glow.restrictedPollElapsed >= 0.25
    local runCountdownText = Glow.countdownTextElapsed >= 0.20
    if not runFast and not runRestrictedPoll and not runCountdownText then return end
    if runFast then Glow.driverElapsed = 0 end
    if runRestrictedPoll then Glow.restrictedPollElapsed = 0 end
    if runCountdownText then Glow.countdownTextElapsed = 0 end

    local now = IG:Now()
    local keepRunning = false
    local expired = false
    local needsPoll = false

    for _, ability in pairs(IG.AbilityStates) do
        if next(ability.records) ~= nil then
            local deadline = ability.deadline
            if type(deadline) == "number" and (relevantCast or allowCountdown) then
                keepRunning = true
                if runFast and deadline <= now then
                    ability.deadline = nil
                    for record in pairs(ability.records) do record.deadline = nil end
                    expired = true
                end
            end
            if relevantCast and ability.needsPoll then
                keepRunning = true
                needsPoll = true
            end
        end
    end

    if runCountdownText and allowCountdown then
        for record in pairs(IG.InterruptRecords) do
            Glow:RefreshCooldownText(record, now)
        end
    end

    if expired or (runRestrictedPoll and needsPoll) then
        if runRestrictedPoll and needsPoll then IG:BumpStat("cooldown.restrictedPolls") end
        IG:MarkCooldownDirty(false)
    end
    if not keepRunning then self:Hide() end
end)

function Glow:UpdateRuntimeDriver()
    local relevantCast = self:HasRelevantCast()
    local allowCountdown = IG.DB.enabled == true and IG.DB.cdText == true
    if not relevantCast and not allowCountdown then
        runtimeFrame:Hide()
        return
    end

    for _, ability in pairs(IG.AbilityStates) do
        if next(ability.records) ~= nil then
            if type(ability.deadline) == "number" and (relevantCast or allowCountdown) then
                runtimeFrame:Show()
                return
            end
            if relevantCast and ability.needsPoll then
                runtimeFrame:Show()
                return
            end
        end
    end
    runtimeFrame:Hide()
end

function Glow:SetTestMode(enabled)
    IG.testMode = enabled == true
    if IG.testMode then
        self:ApplyUnitInterruptibility("target", false, true)
        self:ApplyUnitInterruptibility("focus", false, true)
    elseif IG.CastTracking then
        IG:MarkCastDirty()
    end
    IG:MarkVisualDirty()
end
