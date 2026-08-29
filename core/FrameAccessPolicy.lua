local IG = _G.InterruptGlow
if not IG or not IG.Glow then return end

local Glow = IG.Glow
local _G = _G
local CreateFrame = _G.CreateFrame
local pcall = pcall
local type = type

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
    -- Access can be transient during provider construction or a restricted
    -- context. Fail closed now, but do not permanently blacklist the button.
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
    if not IG.CanAccess(record.button) then
        MarkOverlayDeferred(record)
        IG:BumpStat("ui.shellsDeferred")
        return nil
    end
    if record.button == nil then return nil end
    if record.overlay then return record.overlay end
    if record.overlayForbidden then return nil end
    if IG:IsInCombat() then
        record.overlayPending = true
        return nil
    end
    if record.overlayAccessDeferred and not self:AllowOverlayAccessRetry(record, false) then
        record.overlayPending = true
        return nil
    end

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
        target = CreateUnitBranch(record.button),
        focus = CreateUnitBranch(record.button),
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

local originalQueueShell = Glow.QueueShell
function Glow:QueueShell(record, urgent)
    if record and record.overlayAccessDeferred
        and not self:AllowOverlayAccessRetry(record, false)
    then
        record.overlayPending = true
        return nil
    end
    return originalQueueShell(self, record, urgent)
end

local originalCreatePendingOverlays = Glow.CreatePendingOverlays
function Glow:CreatePendingOverlays(...)
    if not IG:IsInCombat() then
        -- PLAYER_REGEN_ENABLED and explicit lifecycle activation are authoritative
        -- retry points. Re-arm once regardless of the current backoff deadline.
        for _, record in pairs(IG.ObservedButtons or {}) do
            if record.overlayAccessDeferred then
                self:AllowOverlayAccessRetry(record, true)
            end
        end
    end
    return originalCreatePendingOverlays(self, ...)
end

IG:RegisterModule("FrameAccessPolicy", {
    inaccessibleForeignFrameFailsClosed = true,
    checksHasAccessConstraints = true,
    checksCanBeAccessedInContext = true,
    transientAccessFailureIsRetryable = true,
    retryBaseDelay = RETRY_BASE_DELAY,
    retryMaxDelay = RETRY_MAX_DELAY,
    retryBackoffSteps = MAX_RETRY_BACKOFF_STEPS,
    noOnUpdateRetryLoop = true,
    reobservationCanResumePrewarm = true,
    postCombatCanResumePrewarm = true,
    confirmedForbiddenIsPermanent = true,
    forbiddenQueryMustReturnOrdinaryBoolean = true,
    ownsShellCreationBoundary = true,
})
