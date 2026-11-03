local ROOT = arg[1] or "."

_G = _G or _ENV

local createFrameCalls = 0
local createdTextures = 0
local stats = {}
local secretValue = {}
local inaccessibleButton = {}
local inaccessibleAllowed = false
local mockNow = 0

local function NewTexture()
    createdTextures = createdTextures + 1
    local texture = {}
    function texture:ClearAllPoints() end
    function texture:SetPoint() end
    function texture:SetBlendMode() end
    function texture:SetAtlas() end
    function texture:SetTexture() end
    function texture:SetVertexColor() end
    function texture:SetAlpha() end
    function texture:Show() end
    return texture
end

local function NewFrame(parent)
    assert(parent ~= inaccessibleButton or inaccessibleAllowed, "child created on inaccessible frame")
    if parent and type(parent.CanBeAccessedInContext) == "function" then
        assert(parent:CanBeAccessedInContext() == true, "child created outside permitted context")
    end
    createFrameCalls = createFrameCalls + 1
    local frame = {}
    function frame:SetAllPoints() end
    function frame:SetFrameLevel() end
    function frame:SetAlpha() end
    function frame:Show() end
    function frame:Hide() end
    function frame:SetScript() end
    function frame:CreateTexture() return NewTexture() end
    return frame
end

function CreateFrame(_, _, parent) return NewFrame(parent) end
function UnitIsUnit() return false end

InterruptGlow = {
    DB = { enabled = true, cdText = false, strictNI = true, animateGlow = false },
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    InterruptRecords = setmetatable({}, { __mode = "k" }),
    AbilityStates = {},
    Worker = {
        Disable = function() end,
        RunOnce = function() end,
        SetContinuous = function() end,
    },
}
function InterruptGlow.CanAccess(value)
    if value == secretValue then return false end
    if value == inaccessibleButton and not inaccessibleAllowed then return false end
    return true
end
function InterruptGlow:ReadMember(container, key)
    if not self.CanAccess(container) or container == nil then return nil, false end
    local ok, value = pcall(function() return container[key] end)
    if not ok or not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:IsInCombat() return false end
function InterruptGlow:Now() return mockNow end
function InterruptGlow:BumpStat(key, amount) stats[key] = (stats[key] or 0) + (amount or 1) end
function InterruptGlow:MarkCooldownDirty() end
function InterruptGlow:MarkCastDirty() end
function InterruptGlow:MarkVisualDirty() end

local loader, loadError = loadfile(ROOT .. "/core/Glow.lua")
assert(loader, loadError)
loader()
local Glow = assert(InterruptGlow.Glow)
local framesBeforeShellCreation = createFrameCalls

local function AssertDeferred(button)
    local record = { button = button, overlayPending = true, overlayQueued = true }
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

-- An inaccessible frame is deferred before access-sensitive member reads or
-- child creation. Urgent retries respect bounded backoff too.
local deferredRecord = AssertDeferred(inaccessibleButton)
assert(Glow:QueueShell(deferredRecord, true) == nil)
assert(deferredRecord.overlayAccessFailures == 1)
assert(createFrameCalls == framesBeforeShellCreation)

mockNow = 0.30
assert(Glow:CreateShell(deferredRecord) == nil)
assert(deferredRecord.overlayAccessFailures == 2)
inaccessibleAllowed = true
assert(Glow:QueueShell(deferredRecord, true) == nil, "urgent retry bypassed the active backoff")
assert(deferredRecord.overlayAccessFailures == 2)
mockNow = 0.81
Glow:QueueShell(deferredRecord, true)
assert(deferredRecord.overlay ~= nil)
assert(deferredRecord.overlayAccessFailures == nil)

-- A constrained frame requires an ordinary true context answer before any
-- addon child is created. An explicit lifecycle retry can resume once allowed.
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
Glow:CreatePendingOverlays()
assert(contextualRecord.overlay ~= nil)
assert(contextualRecord.overlayAccessDeferred == false)

-- Erroring or inaccessible access predicates stay retryable, while confirmed
-- forbidden or malformed predicates are permanently skipped.
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

-- Cooldown text creation uses an actual button owner behind an error boundary.
-- A foreign frame that throws is quarantined and is not probed again.
InterruptGlow.DB.cdText = true
local fontCreateCalls = 0
local throwingTextRecord = {
    overlay = {},
    button = {
        CreateFontString = function()
            fontCreateCalls = fontCreateCalls + 1
            error("foreign font owner rejected")
        end,
    },
}
assert(Glow:EnsureCooldownText(throwingTextRecord) == nil)
assert(throwingTextRecord.cooldownTextForbidden == true)
assert(fontCreateCalls == 1)
assert(Glow:EnsureCooldownText(throwingTextRecord) == nil)
assert(fontCreateCalls == 1)

-- Context denial is retryable, but does not invite repeated foreign reads.
inaccessibleAllowed = false
local deniedTextRecord = { overlay = {}, button = inaccessibleButton }
assert(Glow:EnsureCooldownText(deniedTextRecord) == nil)
assert(deniedTextRecord.cooldownTextAccessDeferred == true)
assert(deniedTextRecord.cooldownTextPending == true)

-- Ordinary frames remain supported if they do not expose access constraints.
local ordinaryRecord = { button = { GetFrameLevel = function() return 1 end } }
assert(Glow:CreateShell(ordinaryRecord) ~= nil)
assert(createFrameCalls == 8)
assert(createdTextures == 6)
assert((stats["ui.shellsDeferred"] or 0) == 7)
assert((stats["ui.shellsForbidden"] or 0) == 4)
assert((stats["ui.shellsCreated"] or 0) == 3)

print("FRAME ACCESS BOUNDARY TEST PASSED")
