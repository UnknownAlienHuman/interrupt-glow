local ROOT = arg[1] or "."

_G = _G or _ENV
local printed = {}
local openedTitle, openedReport
local combat = false

InterruptGlow = {
    modules = {},
    name = "InterruptGlow",
    version = "test",
    DB = {
        enabled = true,
        cdText = false,
        cdm = true,
        animateGlow = true,
        strictNI = true,
        optimisticRestrictedCooldown = false,
        debug = false,
        debugChat = false,
        debugKeep = 400,
    },
    RuntimeProbe = {},
    Stats = {},
    CastState = {},
    AbilityStates = {},
    Data = { interface = 120105, wowBuild = 70688, sourceCommit = "test-commit" },
    Buttons = {},
    CDM = {},
    Glow = { prewarmHead = 1, prewarmTail = 0 },
    Worker = { SupportsOnUpdateMode = function(_, frame) return frame ~= nil end },
    flushFrame = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:Print(message) printed[#printed + 1] = message end
function InterruptGlow:Now() return 150 end
function InterruptGlow:IsInCombat() return combat end
function InterruptGlow:IsAddOnFullyLoaded(name) return name == "Dominos" end
function InterruptGlow:HasDirtyWork() return false end
function InterruptGlow:StartProfileCounters(owner)
    self.profileCounterOwner = owner
    self.profileCountersEnabled = true
    return true, owner
end
function InterruptGlow:StopProfileCounters(owner)
    assert(self.profileCounterOwner == owner)
    self.profileCounterOwner = nil
    self.profileCountersEnabled = false
    return true
end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow.Data:GetActiveInterrupts() return function() end end

C_AddOns = {
    GetAddOnMetadata = function(addOnName, field)
        assert(field == "Version")
        if addOnName == "Dominos" then return "12.1-test" end
        return nil
    end,
}

InterruptGlow.Debug = {
    profilerMetrics = {},
    ProfilerSnapshot = function() return { available = false, metrics = {} } end,
    ProfilerDelta = function() return { newSessionPeak = false, metrics = {} } end,
    ShowText = function(_, title, report)
        openedTitle, openedReport = title, report
    end,
}

local loader, loadError = loadfile(ROOT .. "/core/RuntimeProbe.lua")
assert(loader, loadError)
loader()
local Probe = InterruptGlow.RuntimeProbe

assert(Probe:Start("bounded") == true)
for index = 1, 256 do
    Probe:AddMark("mark-" .. index, false)
end
assert(Probe:AddMark("overflow", true) == false)
assert(Probe:AddMark("overflow-again", true) == false)
assert(#Probe.marks == 256)
assert(Probe.droppedMarks == 2)
assert(#printed == 2, "capture start and first marker-limit notice should print once")

for index = 1, 129 do
    Probe:OnRestrictionStateChanged(index, index)
end
assert(#Probe.restrictionTransitions == 128)
assert(Probe.droppedRestrictions == 1)
assert(#Probe.marks == 256, "restriction transitions must not create profiler markers")

local report = assert(Probe:BuildReport())
assert(report:find("[configuration]", 1, true))
assert(report:find("enabled=true", 1, true))
assert(report:find("animateGlow=true", 1, true))
assert(report:find("strictNI=true", 1, true))
assert(report:find("[providerVersions]", 1, true))
assert(report:find("Dominos=12.1-test", 1, true))
assert(report:find("[probeBounds]", 1, true))
assert(report:find("storedMarks=256", 1, true))
assert(report:find("droppedMarks=2", 1, true))
assert(report:find("storedRestrictions=128", 1, true))
assert(report:find("droppedRestrictions=1", 1, true))
assert(report:find("gcd.ignoreGlobalCooldownDuration=true", 1, true))
assert(report:find("gcd.isOnGCDReadinessProof=false", 1, true))

combat = true
assert(Probe:BuildReport() == nil, "combat report construction must be refused")
assert(Probe:Show() == false)
assert(openedTitle == nil, "combat Show must not build or open a report")
assert(Probe:Stop() == false, "capture stop must be deferred until after combat")
combat = false
assert(Probe:Show() == true)
assert(openedTitle == "Interrupt Glow Runtime Probe")
assert(openedReport == report)

print("RUNTIME PROBE POLICY TEST PASSED")
