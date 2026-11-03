local ROOT = arg[1] or "."

_G = _G or _ENV

local disableCalls = 0
local scheduleCalls = 0
local stats = {}

local function NewRegion()
    local region = { scripts = {}, alpha = 0, mode = nil }
    function region:SetOnUpdateMode(mode) self.mode = mode end
    function region:Show() end
    function region:Hide() end
    function region:SetScript(name, fn) self.scripts[name] = fn end
    function region:SetPoint() end
    function region:SetAllPoints() end
    function region:SetAlpha(value) self.alpha = value end
    function region:SetTexture() end
    function region:SetAtlas() end
    function region:SetVertexColor() end
    function region:SetBlendMode() end
    function region:CreateTexture() return NewRegion() end
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

function CreateFrame() return NewRegion() end
function UnitIsUnit() return false end

InterruptGlow = {
    DB = { enabled = true, cdText = false, strictNI = true, animateGlow = false },
    CastState = {
        target = { active = false, hostile = false, niState = "none" },
        focus = { active = false, hostile = false, niState = "none" },
    },
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    InterruptRecords = setmetatable({}, { __mode = "k" }),
    AbilityStates = {},
    modules = {},
    Worker = {
        RunOnce = function(_, frame) scheduleCalls = scheduleCalls + 1; frame:SetOnUpdateMode(1) end,
        Disable = function(_, frame) disableCalls = disableCalls + 1; frame:SetOnUpdateMode(0) end,
        RunAlways = function(_, frame) frame:SetOnUpdateMode(2) end,
        SetContinuous = function(_, frame, enabled) frame:SetOnUpdateMode(enabled and 2 or 0) end,
    },
}
function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:ReadMember(object, key)
    if object == nil then return nil, false end
    return object[key], true
end
function InterruptGlow:IsInCombat() return false end
function InterruptGlow:BumpStat(key, amount) stats[key] = (stats[key] or 0) + (amount or 1) end
function InterruptGlow:Now() return 100 end
function InterruptGlow:MarkCooldownDirty() end
function InterruptGlow:MarkCastDirty() end
function InterruptGlow:MarkVisualDirty() end

local loader, loadError = loadfile(ROOT .. "/core/Glow.lua")
assert(loader, loadError)
loader()
local Glow = assert(InterruptGlow.Glow)

-- Existing shells need enhanced visuals too. The per-frame budget limits both
-- inspected records and visual preparation, then resumes the remaining queue.
for index = 1, 20 do
    local record = {
        overlay = {
            enhanced = false,
            target = { plainGate = NewRegion(), candidate = false },
            focus = { plainGate = NewRegion(), candidate = false },
        },
        overlayQueued = true,
    }
    Glow.prewarmQueue[index] = record
    Glow.prewarmQueued[record] = true
end
Glow.prewarmHead = 1
Glow.prewarmTail = 20

Glow:ProcessPrewarmBudget()
assert(disableCalls >= 1)
assert(Glow.prewarmHead == 17 and Glow.prewarmTail == 20)
assert(scheduleCalls == 1, "remaining prewarm work was not rescheduled")
assert(stats["ui.prewarmRecordsProcessed"] == 16)
assert(stats["ui.prewarmVisualsPrepared"] == 16)
for index = 1, 16 do assert(Glow.prewarmQueue[index] == nil) end
for index = 17, 20 do assert(Glow.prewarmQueue[index] ~= nil) end

Glow:ProcessPrewarmBudget()
assert(disableCalls >= 2)
assert(stats["ui.prewarmRecordsProcessed"] == 20)
assert(stats["ui.prewarmVisualsPrepared"] == 20)
assert(Glow.prewarmHead == 1 and Glow.prewarmTail == 0)
assert(next(Glow.prewarmQueue) == nil)

print("PREWARM BUDGET TEST PASSED")
