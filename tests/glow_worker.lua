local ROOT = arg[1] or "."

_G = _G or _ENV

Enum = {
    OnUpdateMode = {
        Disabled = 0,
        RunWhenVisible = 1,
        RunWhenVisibleOnce = 2,
        RunOnce = 3,
        RunAlways = 4,
    },
}

InterruptGlow = {
    DB = { enabled = true, cdText = false, strictNI = true },
    CastState = {
        target = { active = false, hostile = false, niState = "none" },
        focus = { active = false, hostile = false, niState = "none" },
    },
    ObservedButtons = {},
    InterruptRecords = {},
    AbilityStates = {},
    modules = {},
}
function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:IsInCombat() return false end
function InterruptGlow:BumpStat() end
function InterruptGlow:Now() return 100 end
function InterruptGlow:MarkCooldownDirty() end
function InterruptGlow:MarkCastDirty() end
function InterruptGlow:MarkVisualDirty() end

function UnitIsUnit() return false end

local function NewRegion(parent)
    local region = { parent = parent, alpha = 0, shown = true, scripts = {}, mode = nil }
    function region:SetOnUpdateMode(mode) self.mode = mode end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetScript(name, fn) self.scripts[name] = fn end
    function region:SetPoint() end
    function region:SetAllPoints() end
    function region:ClearAllPoints() end
    function region:SetFrameLevel() end
    function region:GetFrameLevel() return 1 end
    function region:SetAlpha(value) self.alpha = value end
    function region:SetAlphaFromBoolean(value, yes, no) self.alpha = value and yes or no end
    function region:SetBlendMode() end
    function region:SetTexture() end
    function region:SetAtlas() end
    function region:SetVertexColor() end
    function region:SetText() end
    function region:SetJustifyH() end
    function region:CreateTexture() return NewRegion(self) end
    function region:CreateFontString() return NewRegion(self) end
    function region:CreateAnimationGroup()
        local group = {}
        function group:SetLooping() end
        function group:CreateAnimation()
            return {
                SetDuration = function() end,
                SetScale = function() end,
                SetSmoothing = function() end,
            }
        end
        function group:Play() end
        function group:Stop() end
        return group
    end
    return region
end

function CreateFrame(_, _, parent)
    return NewRegion(parent)
end

local workerLoader, workerError = loadfile(ROOT .. "/core/Worker.lua")
assert(workerLoader, workerError)
workerLoader()

local glowLoader, glowError = loadfile(ROOT .. "/core/Glow.lua")
assert(glowLoader, glowError)
glowLoader()

local Glow = assert(InterruptGlow.Glow)
assert(Glow.prewarmFrame.mode == Enum.OnUpdateMode.Disabled)
assert(Glow.runtimeFrame.mode == Enum.OnUpdateMode.Disabled)
assert(Glow.runtimeWorkerEnabled == false)

local button = NewRegion(nil)
local record = { button = button, isInterrupt = false }
InterruptGlow.ObservedButtons[button] = record
Glow:QueueShell(record, false)
assert(Glow.prewarmScheduled == true)
assert(Glow.prewarmFrame.mode == Enum.OnUpdateMode.RunOnce)

-- Simulate the engine resetting RunOnce before dispatch.
Glow.prewarmFrame.mode = Enum.OnUpdateMode.Disabled
Glow.prewarmFrame.scripts.OnUpdate(Glow.prewarmFrame, 0.016)
assert(record.overlay ~= nil)
assert(Glow.prewarmScheduled == false)
assert(Glow.prewarmFrame.mode == Enum.OnUpdateMode.Disabled)

local abilityRecord = { ability = nil }
local ability = {
    records = { [abilityRecord] = true },
    deadline = 105,
    needsPoll = false,
}
abilityRecord.ability = ability
InterruptGlow.AbilityStates.test = ability
InterruptGlow.CastState.target.active = true
InterruptGlow.CastState.target.hostile = true
InterruptGlow.CastState.target.niState = "interruptible"
Glow:UpdateRuntimeDriver()
assert(Glow.runtimeWorkerEnabled == true)
assert(Glow.runtimeFrame.mode == Enum.OnUpdateMode.RunAlways)

InterruptGlow.CastState.target.active = false
Glow:UpdateRuntimeDriver()
assert(Glow.runtimeWorkerEnabled == false)
assert(Glow.runtimeFrame.mode == Enum.OnUpdateMode.Disabled)

print("GLOW WORKER TEST PASSED")
