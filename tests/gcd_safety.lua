local ROOT = arg[1] or "."

_G = _G or _ENV

local receivedHint = nil
local clearCalls = 0
local baseCaptureCalls = 0

InterruptGlow = {
    modules = {},
    Cooldown = {},
}
function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end

function InterruptGlow.Cooldown:GetCachedReadiness(_, _, hint)
    receivedHint = hint
    return false, nil, false, true, true, false
end
function InterruptGlow.Cooldown:ClearGCDHints()
    clearCalls = clearCalls + 1
end
function InterruptGlow.Cooldown:CaptureGCDHints()
    baseCaptureCalls = baseCaptureCalls + 1
end

local loader, loadError = loadfile(ROOT .. "/core/GCDSafetyPolicy.lua")
assert(loader, loadError)
loader()

local ready = InterruptGlow.Cooldown:GetCachedReadiness("action", 1, true)
assert(ready == false)
assert(receivedHint == false, "isOnGCD hint reached the readiness resolver")

InterruptGlow.Cooldown:CaptureGCDHints()
assert(clearCalls == 1)
assert(baseCaptureCalls == 0, "GCD hint collector was not replaced")

local policy = assert(InterruptGlow.modules.GCDSafetyPolicy)
assert(policy.ignoresGlobalCooldownInDurationAPI == true)
assert(policy.treatsIsOnGCDAsReadinessProof == false)

print("GCD SAFETY TEST PASSED")
