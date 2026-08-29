local ROOT = arg[1] or "."

_G = _G or _ENV

local createFrameCalls = 0
local createdTextures = 0
local stats = {}
local secretValue = {}
local inaccessibleButton = {}
local inaccessibleAllowed = false
local mockNow = 0

InterruptGlow = {
    modules = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    Glow = {
        prewarmQueued = setmetatable({}, { __mode = "k" }),
    },
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value)
    if value == secretValue then return false end
    if value == inaccessibleButton and not inaccessibleAllowed then return false end
    return true
end
function InterruptGlow:ReadMember(container, key)
    if not self.CanAccess(container) or container == nil then return nil, false end
    local value = container[key]
    if not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:IsInCombat() return false end
function InterruptGlow:Now() return mockNow end
function InterruptGlow:BumpStat(key)
    stats[key] = (stats[key] or 0) + 1
end

local function NewTexture()
    createdTextures = createdTextures + 1
    return {
        ClearAllPoints = function() end,
        SetPoint = function() end,
        SetBlendMode = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
        SetVertexColor = function() end,
        SetAlpha = function() end,
        Show = function() end,
    }
end

function CreateFrame(_, _, parent)
    assert(parent ~= inaccessibleButton or inaccessibleAllowed, "created a child on an inaccessible frame")
    if parent and type(parent.CanBeAccessedInContext) == "function" then
        assert(parent:CanBeAccessedInContext() == true, "created a child outside the permitted context")
    end
    createFrameCalls = createFrameCalls + 1
    return {
        SetAllPoints = function() end,
        SetFrameLevel = function() end,
        SetAlpha = function() end,
        Show = function() end,
        CreateTexture = function() return NewTexture() end,
    }
end

local Glow = InterruptGlow.Glow
function Glow:QueueShell(record, urgent)
    if urgent then return self:CreateShell(record) end
    record.overlayQueued = true
    self.prewarmQueued[record] = true
end
function Glow:CreatePendingOverlays()
    for _, record in pairs(InterruptGlow.ObservedButtons) do
        if record.isInterrupt and not record.overlay then self:CreateShell(record) end
    end
end

local loader, loadError = loadfile(ROOT .. "/core/FrameAccessPolicy.lua")
assert(loader, loadError)
loader()

local function AssertDeferred(button)
    local record = {
        button = button,
        overlayPending = true,
        overlayQueued = true,
    }
    Glow.prewarmQueued[record] = true
    local framesBefore = createFrameCalls
    assert(Glow:CreateShell(record) == nil)
    assert(record.overlay == nil)
    assert(record.overlayForbidden ~= true)
    assert(record.overlayAccessDeferred == true)
    assert(record.overlayAccessFailures == 1)
    assert(type(record.overlayAccessNextRetry) == "number")
    assert(record.overlayPending == true and record.overlayQueued == false)
    assert(Glow.prewarmQueued[record] == nil)
    assert(createFrameCalls == framesBefore)
    return record
end

-- An inaccessible frame object is fail-closed. Immediate urgent calls are
-- throttled before the object is touched and do not increase failure count.
local deferredRecord = AssertDeferred(inaccessibleButton)
assert(Glow:QueueShell(deferredRecord, true) == nil)
assert(deferredRecord.overlayAccessFailures == 1)
assert(createFrameCalls == 0)

mockNow = 0.30
assert(Glow:CreateShell(deferredRecord) == nil)
assert(deferredRecord.overlayAccessFailures == 2)
inaccessibleAllowed = true
assert(Glow:QueueShell(deferredRecord, true) == nil, "backoff was bypassed by urgent retry")
assert(deferredRecord.overlayAccessFailures == 2)
mockNow = 0.81
assert(Glow:QueueShell(deferredRecord, true) ~= nil)
assert(deferredRecord.overlayAccessFailures == nil)

-- HasAccessConstraints=true requires an ordinary true result from
-- CanBeAccessedInContext before any child frame is allocated.
local contextAllowed = false
local contextualButton = {
    HasAccessConstraints = function() return true end,
    CanBeAccessedInContext = function() return contextAllowed end,
    IsForbidden = function() return false end,
}
local contextualRecord = AssertDeferred(contextualButton)
InterruptGlow.ObservedButtons[contextualButton] = contextualRecord
contextualRecord.isInterrupt = true
contextAllowed = true

-- Post-combat/lifecycle processing is an explicit retry point and may bypass the
-- timer once. It is not an OnUpdate retry loop.
Glow:CreatePendingOverlays()
assert(contextualRecord.overlay ~= nil)
assert(contextualRecord.overlayAccessDeferred == false)

-- Erroring or inaccessible contextual access predicates remain retryable and
-- never create a child frame.
AssertDeferred({
    HasAccessConstraints = function() return true end,
    CanBeAccessedInContext = function() error("context query failed") end,
    IsForbidden = function() return false end,
})
AssertDeferred({
    HasAccessConstraints = function() return true end,
    CanBeAccessedInContext = function() return secretValue end,
    IsForbidden = function() return false end,
})
AssertDeferred({ IsForbidden = function() error("foreign frame query failed") end })
AssertDeferred({ IsForbidden = function() return secretValue end })

local function AssertForbidden(button)
    local record = { button = button, overlayPending = true, overlayQueued = true }
    Glow.prewarmQueued[record] = true
    local framesBefore = createFrameCalls
    assert(Glow:CreateShell(record) == nil)
    assert(record.overlayForbidden == true)
    assert(record.overlayAccessDeferred == false)
    assert(record.overlayPending == false and record.overlayQueued == false)
    assert(createFrameCalls == framesBefore)
end

AssertForbidden({ IsForbidden = function() return true end })
AssertForbidden({ IsForbidden = "not-a-function" })
AssertForbidden({ HasAccessConstraints = "not-a-function" })
AssertForbidden({
    HasAccessConstraints = function() return true end,
    CanBeAccessedInContext = "not-a-function",
})

-- Frames without access-constraint or forbidden methods remain supported when
-- the frame itself is ordinary and readable.
local ordinaryRecord = { button = { GetFrameLevel = function() return 1 end } }
assert(Glow:CreateShell(ordinaryRecord) ~= nil)

assert(createFrameCalls == 6)
assert(createdTextures == 6)
assert((stats["ui.shellsDeferred"] or 0) == 7)
assert((stats["ui.shellsForbidden"] or 0) == 4)
assert((stats["ui.shellsCreated"] or 0) == 3)

local policy = assert(InterruptGlow.modules.FrameAccessPolicy)
assert(policy.inaccessibleForeignFrameFailsClosed == true)
assert(policy.checksHasAccessConstraints == true)
assert(policy.checksCanBeAccessedInContext == true)
assert(policy.transientAccessFailureIsRetryable == true)
assert(policy.retryBaseDelay == 0.25)
assert(policy.retryMaxDelay == 2.0)
assert(policy.noOnUpdateRetryLoop == true)
assert(policy.reobservationCanResumePrewarm == true)
assert(policy.postCombatCanResumePrewarm == true)
assert(policy.confirmedForbiddenIsPermanent == true)
assert(policy.forbiddenQueryMustReturnOrdinaryBoolean == true)
assert(policy.ownsShellCreationBoundary == true)

print("FRAME ACCESS POLICY TEST PASSED")
