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

local function ClearQueuedState(record)
    record.overlayQueued = false
    Glow.prewarmQueued[record] = nil
end

local function MarkOverlayForbidden(record)
    record.overlayForbidden = true
    record.overlayAccessDeferred = false
    record.overlayPending = false
    ClearQueuedState(record)
end

local function MarkOverlayDeferred(record)
    -- Access can be transient during provider construction or a restricted
    -- context. Fail closed now, but do not permanently blacklist the button.
    record.overlayForbidden = false
    record.overlayAccessDeferred = true
    record.overlayPending = true
    ClearQueuedState(record)
end

local function InspectButtonAccess(button)
    if not IG.CanAccess(button) then return ACCESS_DEFERRED end

    local method, memberKnown = IG:ReadMember(button, "IsForbidden")
    if not memberKnown then return ACCESS_DEFERRED end
    if method == nil then return ACCESS_ALLOWED end
    if type(method) ~= "function" then return ACCESS_FORBIDDEN end

    local ok, forbidden = pcall(method, button)
    if not ok or not IG.CanAccess(forbidden) or type(forbidden) ~= "boolean" then
        return ACCESS_DEFERRED
    end
    return forbidden and ACCESS_FORBIDDEN or ACCESS_ALLOWED
end

local function SafeFrameLevel(button)
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

-- Own the complete shell creation boundary. A confirmed forbidden frame is
-- permanently skipped. An inaccessible/erroring query is deferred and may be
-- retried after combat/provider construction instead of silently losing the
-- overlay for the rest of the session.
function Glow:CreateShell(record)
    if not record or not record.button then return nil end
    if record.overlay then return record.overlay end
    if record.overlayForbidden then return nil end
    if IG:IsInCombat() then
        record.overlayPending = true
        return nil
    end

    record.overlayAccessDeferred = false
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
    record.overlayAccessDeferred = false
    ClearQueuedState(record)
    IG:BumpStat("ui.shellsCreated")
    return record.overlay
end

local originalQueueShell = Glow.QueueShell
function Glow:QueueShell(record, urgent)
    if record and record.overlayAccessDeferred then
        if urgent and not IG:IsInCombat() then
            -- A button that became an interrupt deserves one fresh out-of-combat
            -- preflight. Persistent failures remain deferred, not hot-looped.
            record.overlayAccessDeferred = false
            return self:CreateShell(record)
        end
        record.overlayPending = true
        return nil
    end
    return originalQueueShell(self, record, urgent)
end

IG:RegisterModule("FrameAccessPolicy", {
    inaccessibleForeignFrameFailsClosed = true,
    transientAccessFailureIsRetryable = true,
    confirmedForbiddenIsPermanent = true,
    forbiddenQueryMustReturnOrdinaryBoolean = true,
    ownsShellCreationBoundary = true,
})
