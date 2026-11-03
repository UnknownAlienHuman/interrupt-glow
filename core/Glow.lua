local IG = _G.InterruptGlow
if not IG then return end

local Glow = {
    prewarmQueue = {},
    prewarmHead = 1,
    prewarmTail = 0,
    prewarmQueued = setmetatable({}, { __mode = "k" }),
    prewarmBudgetPerFrame = 16,
    prewarmScheduled = false,
    runtimeWorkerEnabled = nil,
    driverElapsed = 0,
    timingPollElapsed = 0,
    countdownTextElapsed = 0,
    sameTrackedUnit = false,
}
IG.Glow = Glow

local _G = _G
local CreateFrame = _G.CreateFrame
local UnitIsUnit = _G.UnitIsUnit
local Worker = IG.Worker
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
    -- format, return or wrap the value in pcall.
    method(region, value, alphaIfTrue, alphaIfFalse)
    return true
end

local ACCESS_ALLOWED = 1
local ACCESS_DEFERRED = 2
local ACCESS_FORBIDDEN = 3
local RETRY_BASE_DELAY = 0.25
local RETRY_MAX_DELAY = 2.0
local MAX_RETRY_BACKOFF_STEPS = 4

local function ClearQueuedState(record)
    record.overlayQueued = false
    Glow.prewarmQueued[record] = nil
end

local function ClearRetryState(record)
    record.overlayAccessDeferred = false
    record.overlayAccessFailures = nil
    record.overlayAccessNextRetry = nil
end

local function MarkOverlayForbidden(record)
    record.overlayForbidden = true
    ClearRetryState(record)
    record.overlayPending = false
    ClearQueuedState(record)
end

local function RetryDelay(failures)
    local step = failures
    if step < 1 then step = 1 end
    if step > MAX_RETRY_BACKOFF_STEPS then step = MAX_RETRY_BACKOFF_STEPS end

    local delay = RETRY_BASE_DELAY * (2 ^ (step - 1))
    if delay > RETRY_MAX_DELAY then delay = RETRY_MAX_DELAY end
    return delay
end

local function MarkOverlayDeferred(record)
    record.overlayForbidden = false
    record.overlayAccessDeferred = true
    record.overlayAccessFailures = (record.overlayAccessFailures or 0) + 1
    record.overlayAccessNextRetry = IG:Now() + RetryDelay(record.overlayAccessFailures)
    record.overlayPending = true
    ClearQueuedState(record)
end

local function ReadOrdinaryBooleanMethod(object, methodName)
    local method, memberKnown = IG:ReadMember(object, methodName)
    if not memberKnown then return nil, false, false end
    if method == nil then return nil, true, false end
    if type(method) ~= "function" then return nil, false, true end

    local ok, value = pcall(method, object)
    if not ok or not IG.CanAccess(value) or type(value) ~= "boolean" then
        return nil, false, false
    end
    return value, true, false
end

local function InspectButtonAccess(button)
    -- Accessibility precedes every comparison, method lookup and call.
    if not IG.CanAccess(button) then return ACCESS_DEFERRED end
    if button == nil then return ACCESS_DEFERRED end

    local constrained, constraintsKnown, constraintsMalformed =
        ReadOrdinaryBooleanMethod(button, "HasAccessConstraints")
    if constraintsMalformed then return ACCESS_FORBIDDEN end
    if not constraintsKnown then return ACCESS_DEFERRED end

    if constrained == true then
        local accessible, contextKnown, contextMalformed =
            ReadOrdinaryBooleanMethod(button, "CanBeAccessedInContext")
        if contextMalformed then return ACCESS_FORBIDDEN end
        if not contextKnown or accessible ~= true then return ACCESS_DEFERRED end
    end

    local forbidden, forbiddenKnown, forbiddenMalformed =
        ReadOrdinaryBooleanMethod(button, "IsForbidden")
    if forbiddenMalformed then return ACCESS_FORBIDDEN end
    if not forbiddenKnown then return ACCESS_DEFERRED end
    if forbidden == true then return ACCESS_FORBIDDEN end
    return ACCESS_ALLOWED
end

local function SafeFrameLevel(button)
    if not IG.CanAccess(button) or button == nil then return 1 end

    local method, memberKnown = IG:ReadMember(button, "GetFrameLevel")
    if not memberKnown or type(method) ~= "function" then return 1 end

    local ok, value = pcall(method, button)
    if ok and IG.CanAccess(value) and type(value) == "number" then
        return value
    end
    return 1
end

local function ConfigureGlowTexture(texture, gate, unit)
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

    -- Configure visual constants before any secret alpha reaches the region.
    if unit == "focus" then
        texture:SetVertexColor(1, 0.64, 0.18, 1)
    else
        texture:SetVertexColor(0.18, 0.82, 1, 1)
    end
    texture:SetAlpha(1)
    texture:Show()
end

local function CreateUnitBranch(button, unit)
    local plainGate = CreateFrame("Frame", nil, button)
    plainGate:SetAllPoints(button)
    plainGate:SetFrameLevel(SafeFrameLevel(button) + 8)
    plainGate:SetAlpha(0)
    plainGate:Show()

    local niGate = plainGate:CreateTexture(nil, "OVERLAY", nil, 7)
    ConfigureGlowTexture(niGate, plainGate, unit)

    return {
        plainGate = plainGate,
        niGate = niGate,
        candidate = false,
        animation = nil,
    }
end

local function CreatePulseAnimation(region)
    if not region or type(region.CreateAnimationGroup) ~= "function" then
        return nil
    end

    local ok, group = pcall(region.CreateAnimationGroup, region)
    if not ok or not group or type(group.CreateAnimation) ~= "function" then
        return nil
    end

    group:SetLooping("BOUNCE")
    local scale = group:CreateAnimation("Scale")
    scale:SetDuration(0.55)
    scale:SetScale(1.06, 1.06)
    if type(scale.SetSmoothing) == "function" then scale:SetSmoothing("IN_OUT") end
    return group
end

local function SetCandidate(branch, candidate)
    if not branch or branch.candidate == candidate then return end
    branch.candidate = candidate
    branch.plainGate:SetAlpha(candidate and 1 or 0)

    if candidate then
        if IG.DB.animateGlow ~= false and branch.animation then branch.animation:Play() end
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

function Glow:SchedulePrewarm()
    if self.prewarmScheduled or IG:IsInCombat() or not self.prewarmFrame then return end
    if self.prewarmHead > self.prewarmTail then return end

    self.prewarmScheduled = true
    if Worker then
        Worker:RunOnce(self.prewarmFrame)
    else
        self.prewarmFrame:Show()
    end
end

function Glow:DisablePrewarmWorker()
    self.prewarmScheduled = false
    if not self.prewarmFrame then return end

    if Worker then
        Worker:Disable(self.prewarmFrame)
    else
        self.prewarmFrame:Hide()
    end
end

function Glow:SetRuntimeWorkerEnabled(enabled)
    enabled = enabled == true
    if self.runtimeWorkerEnabled == enabled then return end
    self.runtimeWorkerEnabled = enabled

    if Worker then
        Worker:SetContinuous(self.runtimeFrame, enabled)
    elseif enabled then
        self.runtimeFrame:Show()
    else
        self.runtimeFrame:Hide()
    end
end

-- Explicit lifecycle/provider signals may re-arm one access preflight. Ordinary
-- repeated calls are time-throttled and do not form an OnUpdate retry loop.
function Glow:AllowOverlayAccessRetry(record, force)
    if not record or record.overlay or record.overlayForbidden then return false end
    if not record.overlayAccessDeferred then return true end
    if IG:IsInCombat() then return false end

    local nextRetry = record.overlayAccessNextRetry
    if force ~= true
        and type(nextRetry) == "number"
        and IG:Now() < nextRetry
    then
        return false
    end

    record.overlayAccessDeferred = false
    return true
end

-- Own the complete shell creation boundary. A confirmed forbidden frame is
-- permanently skipped. Contextually inaccessible/erroring frames remain hidden
-- and are retried only on a later bounded provider/lifecycle signal.
function Glow:CreateShell(record)
    if not record then return nil end
    if record.overlay then return record.overlay end
    if record.overlayForbidden then return nil end
    if IG:IsInCombat() then
        record.overlayPending = true
        return nil
    end

    -- Apply the throttle before touching the foreign object. This also covers a
    -- frame object that itself is currently inaccessible.
    if record.overlayAccessDeferred and not self:AllowOverlayAccessRetry(record, false) then
        record.overlayPending = true
        return nil
    end

    if not IG.CanAccess(record.button) then
        MarkOverlayDeferred(record)
        IG:BumpStat("ui.shellsDeferred")
        return nil
    end
    if record.button == nil then return nil end

    local access = InspectButtonAccess(record.button)
    if access == ACCESS_FORBIDDEN then
        MarkOverlayForbidden(record)
        IG:BumpStat("ui.shellsForbidden")
        return nil
    end
    if access == ACCESS_DEFERRED then
        MarkOverlayDeferred(record)
        IG:BumpStat("ui.shellsDeferred")
        return nil
    end

    record.overlay = {
        target = CreateUnitBranch(record.button, "target"),
        focus = CreateUnitBranch(record.button, "focus"),
        cooldownText = nil,
        enhanced = false,
    }
    record.overlayPending = false
    record.overlayForbidden = false
    ClearRetryState(record)
    ClearQueuedState(record)
    IG:BumpStat("ui.shellsCreated")
    return record.overlay
end

function Glow:QueueShell(record, urgent)
    if not record or record.overlay or record.overlayForbidden then return end
    if record.overlayAccessDeferred and not self:AllowOverlayAccessRetry(record, false) then
        record.overlayPending = true
        return
    end

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

    self:SchedulePrewarm()
end

function Glow:ProcessPrewarmBudget()
    self:DisablePrewarmWorker()
    if IG:IsInCombat() then return end

    local processed = 0
    local visualsPrepared = 0
    while processed < self.prewarmBudgetPerFrame and self.prewarmHead <= self.prewarmTail do
        local record = self.prewarmQueue[self.prewarmHead]
        self.prewarmQueue[self.prewarmHead] = nil
        self.prewarmHead = self.prewarmHead + 1
        processed = processed + 1

        if record then
            self.prewarmQueued[record] = nil
            record.overlayQueued = false

            if not record.overlay and not record.overlayForbidden then
                self:CreateShell(record)
            end

            if record.overlay and not record.overlayForbidden then
                local before = record.overlay.enhanced == true
                self:EnsureInterruptVisuals(record)
                if not before and record.overlay.enhanced == true then
                    visualsPrepared = visualsPrepared + 1
                end
            end
        end
    end

    if processed > 0 then IG:BumpStat("ui.prewarmRecordsProcessed", processed) end
    if visualsPrepared > 0 then IG:BumpStat("ui.prewarmVisualsPrepared", visualsPrepared) end

    if self.prewarmHead > self.prewarmTail then
        self.prewarmQueue = {}
        self.prewarmHead = 1
        self.prewarmTail = 0
    else
        self:SchedulePrewarm()
    end
end

function Glow:EnsureCooldownText(record)
    if not IG.DB.cdText or not record or record.cooldownTextForbidden then return nil end
    local overlay = record.overlay
    if not overlay then return nil end
    if overlay.cooldownText then return overlay.cooldownText end
    if record.cooldownTextAccessDeferred then return nil end
    if IG:IsInCombat() then
        record.cooldownTextPending = true
        return nil
    end
    local access = InspectButtonAccess(record.button)
    if access == ACCESS_FORBIDDEN then
        record.cooldownTextForbidden = true
        record.cooldownTextPending = false
        IG:BumpStat("ui.cooldownTextOwnerRejected")
        return nil
    elseif access == ACCESS_DEFERRED then
        -- Do not probe denied foreign owners from the countdown worker. A
        -- later out-of-combat lifecycle or settings action may retry once.
        record.cooldownTextAccessDeferred = true
        record.cooldownTextPending = true
        return nil
    end
    local createFontString, readable = IG:ReadMember(record.button, "CreateFontString")
    if not readable or type(createFontString) ~= "function" then
        record.cooldownTextForbidden = true
        record.cooldownTextPending = false
        IG:BumpStat("ui.cooldownTextOwnerRejected")
        return nil
    end
    local ok, text = pcall(createFontString, record.button, nil, "OVERLAY", "NumberFontNormalLarge")
    if not ok or not IG.CanAccess(text) or text == nil then
        record.cooldownTextForbidden = true
        record.cooldownTextPending = false
        IG:BumpStat("ui.cooldownTextCreateFailed")
        return nil
    end
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

        -- Animate the ordinary parent gate, never the child texture carrying a
        -- possible Alpha secret aspect.
        overlay.target.animation = CreatePulseAnimation(overlay.target.plainGate)
        overlay.focus.animation = CreatePulseAnimation(overlay.focus.plainGate)
        overlay.enhanced = true
        record.enhancementPending = false
        IG:BumpStat("ui.interruptVisualsCreated")
        changed = true

        if IG.DB.animateGlow ~= false and overlay.target.candidate and overlay.target.animation then overlay.target.animation:Play() end
        if IG.DB.animateGlow ~= false and overlay.focus.candidate and overlay.focus.animation then overlay.focus.animation:Play() end
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
        if record.overlayAccessDeferred then self:AllowOverlayAccessRetry(record, true) end
        if record.isInterrupt and not record.overlay then
            changed = self:CreateShell(record) ~= nil or changed
        end
        if record.isInterrupt then
            record.cooldownTextAccessDeferred = false
            changed = self:EnsureInterruptVisuals(record) or changed
        end
    end

    self:SchedulePrewarm()
    if changed and IG.CastTracking then IG:MarkCastDirty() end
    IG:MarkVisualDirty()
end

function Glow:EnsureCooldownTexts()
    if not IG.DB.cdText or IG:IsInCombat() then return end
    for record in pairs(IG.InterruptRecords) do
        record.cooldownTextAccessDeferred = false
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
    if ok and IG.CanAccess(same) and same == true then self.sameTrackedUnit = true end
end

function Glow:HasRelevantCast()
    if IG.DB.enabled ~= true then return false end

    for index = 1, #UNITS do
        local state = IG.CastState[UNITS[index]]
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
    if record.conditionalIdentityPending == true then return false end
    if IG.testMode then return record.isInterrupt == true and unit == "target" end

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
        if record.overlay then SetCandidate(record.overlay[unit], CandidateFor(record, unit)) end
    end
    self:UpdateRuntimeDriver()
end

function Glow:RefreshAll()
    for record in pairs(IG.InterruptRecords) do self:RefreshRecord(record) end
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
        or record.conditionalIdentityPending == true
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
Glow.prewarmFrame = prewarmFrame
prewarmFrame:SetScript("OnUpdate", function()
    Glow:ProcessPrewarmBudget()
end)
Glow:DisablePrewarmWorker()

local runtimeFrame = CreateFrame("Frame")
Glow.runtimeFrame = runtimeFrame
runtimeFrame:SetScript("OnUpdate", function(_, elapsed)
    local relevantCast = Glow:HasRelevantCast()
    local allowCountdown = IG.DB.enabled == true and IG.DB.cdText == true
    if not relevantCast and not allowCountdown then
        Glow:SetRuntimeWorkerEnabled(false)
        return
    end

    Glow.driverElapsed = Glow.driverElapsed + elapsed
    Glow.timingPollElapsed = Glow.timingPollElapsed + elapsed
    Glow.countdownTextElapsed = Glow.countdownTextElapsed + elapsed

    local runFast = Glow.driverElapsed >= 0.05
    local runTimingPoll = Glow.timingPollElapsed >= 0.25
    local runCountdownText = Glow.countdownTextElapsed >= 0.20
    if not runFast and not runTimingPoll and not runCountdownText then return end
    if runFast then Glow.driverElapsed = 0 end
    if runTimingPoll then Glow.timingPollElapsed = 0 end
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
        for record in pairs(IG.InterruptRecords) do Glow:RefreshCooldownText(record, now) end
    end

    if expired or (runTimingPoll and needsPoll) then
        if runTimingPoll and needsPoll then IG:BumpStat("cooldown.timingPolls") end
        IG:MarkCooldownDirty()
    end
    if not keepRunning then Glow:SetRuntimeWorkerEnabled(false) end
end)
Glow:SetRuntimeWorkerEnabled(false)

function Glow:UpdateRuntimeDriver()
    local relevantCast = self:HasRelevantCast()
    local allowCountdown = IG.DB.enabled == true and IG.DB.cdText == true
    if not relevantCast and not allowCountdown then
        self:SetRuntimeWorkerEnabled(false)
        return
    end

    for _, ability in pairs(IG.AbilityStates) do
        if next(ability.records) ~= nil then
            if type(ability.deadline) == "number" and (relevantCast or allowCountdown) then
                self:SetRuntimeWorkerEnabled(true)
                return
            end
            if relevantCast and ability.needsPoll then
                self:SetRuntimeWorkerEnabled(true)
                return
            end
        end
    end
    self:SetRuntimeWorkerEnabled(false)
end

function Glow:SetTestMode(enabled)
    enabled = enabled == true
    if enabled and (IG.DB.enabled ~= true or (IG.RuntimeLifecycle and not IG.RuntimeLifecycle:IsActive())) then
        IG:Print("Enable Interrupt Glow before previewing highlights.")
        return false
    end
    if enabled and IG:IsInCombat() then
        IG:Print("Highlight previews are available after combat.")
        return false
    end
    IG.testMode = enabled
    if IG.testMode then
        self:ApplyUnitInterruptibility("target", false, true)
        self:ApplyUnitInterruptibility("focus", false, true)
    elseif IG.CastTracking then
        IG:MarkCastDirty()
    end
    IG:MarkVisualDirty()
end

-- Only ordinary parent animations are changed; the opaque alpha texture is
-- configured once at creation and is never queried or animated.
function Glow:SetAnimationEnabled(enabled)
    IG.DB.animateGlow = enabled == true
    for _, record in pairs(IG.ObservedButtons) do
        local overlay = record.overlay
        if overlay then
            for index = 1, #UNITS do
                local branch = overlay[UNITS[index]]
                if branch.animation then
                    if IG.DB.animateGlow and branch.candidate then
                        branch.animation:Play()
                    else
                        branch.animation:Stop()
                    end
                end
            end
        end
    end
end
