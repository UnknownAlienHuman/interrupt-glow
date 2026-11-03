local ROOT = arg[1] or "."

_G = _G or _ENV

local createdFrames = {}
function CreateFrame(kind)
    assert(kind == "Frame")
    local frame = { events = {}, scripts = {} }
    function frame:RegisterUnitEvent(event, unit) self.events[event] = unit end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetScript(name, handler) self.scripts[name] = handler end
    createdFrames[#createdFrames + 1] = frame
    return frame
end

InterruptGlow = {
    modules = {},
    CastState = { target = {}, focus = {} },
    CastTracking = nil,
    Glow = {},
}
function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:BumpStat() end
function InterruptGlow:CanAccess(_) return true end
function InterruptGlow.Glow:RefreshUnitRelation() end

local loader, loadError = loadfile(ROOT .. "/core/CastTracking.lua")
assert(loader, loadError)
loader()

local tracking = assert(InterruptGlow.CastTracking)
tracking.RefreshAll = function() end
tracking:Attach()
assert(#createdFrames == 2)
local targetFrame = assert(tracking.unitFrames.target)
local focusFrame = assert(tracking.unitFrames.focus)
assert(type(targetFrame.scripts.OnEvent) == "function")
assert(targetFrame.events.UNIT_SPELLCAST_START == "target")
assert(focusFrame.events.UNIT_SPELLCAST_START == "focus")

tracking:Detach()
assert(targetFrame.scripts.OnEvent == nil and focusFrame.scripts.OnEvent == nil)
assert(next(targetFrame.events) == nil and next(focusFrame.events) == nil)
tracking:Attach()
assert(#createdFrames == 2, "enable cycle allocated duplicate unit watcher frames")
assert(tracking.unitFrames.target == targetFrame and tracking.unitFrames.focus == focusFrame)
assert(type(targetFrame.scripts.OnEvent) == "function")
assert(type(focusFrame.scripts.OnEvent) == "function")
assert(targetFrame.events.UNIT_SPELLCAST_START == "target")
assert(focusFrame.events.UNIT_SPELLCAST_START == "focus")

print("CAST TRACKING FRAME LIFECYCLE TEST PASSED")
