local ROOT = arg[1] or "."

_G = _G or _ENV

local createFrameCalls = 0
local createdTextures = 0
local stats = {}
local secretValue = {}
local inaccessibleButton = {}

InterruptGlow = {
    modules = {},
    Glow = {
        prewarmQueued = setmetatable({}, { __mode = "k" }),
    },
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value)
    return value ~= secretValue and value ~= inaccessibleButton
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
    assert(parent ~= inaccessibleButton, "created a child on an inaccessible frame")
    createFrameCalls = createFrameCalls + 1
    return {
        SetAllPoints = function() end,
        SetFrameLevel = function() end,
        SetAlpha = function() end,
        Show = function() end,
        CreateTexture = function() return NewTexture() end,
    }
end

local loader, loadError = loadfile(ROOT .. "/core/FrameAccessPolicy.lua")
assert(loader, loadError)
loader()

local Glow = InterruptGlow.Glow

local function AssertBlocked(button)
    local record = {
        button = button,
        overlayPending = true,
        overlayQueued = true,
    }
    Glow.prewarmQueued[record] = true
    local framesBefore = createFrameCalls
    assert(Glow:CreateShell(record) == nil)
    assert(record.overlay == nil)
    assert(record.overlayForbidden == true)
    assert(record.overlayPending == false and record.overlayQueued == false)
    assert(Glow.prewarmQueued[record] == nil)
    assert(createFrameCalls == framesBefore)
end

AssertBlocked(inaccessibleButton)
AssertBlocked({ IsForbidden = function() error("foreign frame query failed") end })
AssertBlocked({ IsForbidden = function() return secretValue end })
AssertBlocked({ IsForbidden = function() return true end })
AssertBlocked({ IsForbidden = "not-a-function" })

local allowedButton = {
    IsForbidden = function() return false end,
    GetFrameLevel = function() return 3 end,
}
local allowedRecord = { button = allowedButton }
local overlay = assert(Glow:CreateShell(allowedRecord))
assert(overlay == allowedRecord.overlay)
assert(overlay.target and overlay.focus)
assert(createFrameCalls == 2)
assert(createdTextures == 2)
assert((stats["ui.shellsForbidden"] or 0) == 5)
assert((stats["ui.shellsCreated"] or 0) == 1)

-- Frames without an IsForbidden method remain supported when the frame itself is
-- ordinary and readable.
local ordinaryRecord = { button = { GetFrameLevel = function() return 1 end } }
assert(Glow:CreateShell(ordinaryRecord) ~= nil)
assert(createFrameCalls == 4 and createdTextures == 4)

local policy = assert(InterruptGlow.modules.FrameAccessPolicy)
assert(policy.inaccessibleForeignFrameFailsClosed == true)
assert(policy.forbiddenQueryMustReturnOrdinaryBoolean == true)
assert(policy.ownsShellCreationBoundary == true)

print("FRAME ACCESS POLICY TEST PASSED")
