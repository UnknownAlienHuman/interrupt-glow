local ROOT = arg[1] or "."

_G = _G or _ENV

local createFrameCalls = 0
local createdTextures = 0
local stats = {}
local secretValue = {}
local inaccessibleButton = {}
local inaccessibleAllowed = false

InterruptGlow = {
    modules = {},
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
    assert(record.overlayPending == true and record.overlayQueued == false)
    assert(Glow.prewarmQueued[record] == nil)
    assert(createFrameCalls == framesBefore)
    return record
end

local deferredRecord = AssertDeferred(inaccessibleButton)
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

-- A normal provider re-observation can resume bounded non-urgent prewarming
-- after construction finishes; the button need not first become an interrupt.
inaccessibleAllowed = true
assert(Glow:QueueShell(deferredRecord, false) == nil)
assert(deferredRecord.overlayAccessDeferred == false)
assert(deferredRecord.overlayQueued == true)
assert(Glow.prewarmQueued[deferredRecord] == true)
assert(Glow:CreateShell(deferredRecord) ~= nil)
assert(deferredRecord.overlayAccessFailures == nil)
assert(deferredRecord.overlayForbidden ~= true)
assert(deferredRecord.overlayQueued == false)
assert(Glow.prewarmQueued[deferredRecord] == nil)

local allowedButton = {
    IsForbidden = function() return false end,
    GetFrameLevel = function() return 3 end,
}
local allowedRecord = { button = allowedButton }
local overlay = assert(Glow:CreateShell(allowedRecord))
assert(overlay == allowedRecord.overlay)
assert(overlay.target and overlay.focus)

-- Frames without an IsForbidden method remain supported when the frame itself is
-- ordinary and readable.
local ordinaryRecord = { button = { GetFrameLevel = function() return 1 end } }
assert(Glow:CreateShell(ordinaryRecord) ~= nil)

assert(createFrameCalls == 6)
assert(createdTextures == 6)
assert((stats["ui.shellsDeferred"] or 0) == 3)
assert((stats["ui.shellsForbidden"] or 0) == 2)
assert((stats["ui.shellsCreated"] or 0) == 3)

local policy = assert(InterruptGlow.modules.FrameAccessPolicy)
assert(policy.inaccessibleForeignFrameFailsClosed == true)
assert(policy.transientAccessFailureIsRetryable == true)
assert(policy.nonUrgentRetryLimit == 3)
assert(policy.reobservationCanResumePrewarm == true)
assert(policy.confirmedForbiddenIsPermanent == true)
assert(policy.forbiddenQueryMustReturnOrdinaryBoolean == true)
assert(policy.ownsShellCreationBoundary == true)

print("FRAME ACCESS POLICY TEST PASSED")
