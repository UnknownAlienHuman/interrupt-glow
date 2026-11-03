local ROOT = arg[1] or "."

_G = _G or _ENV

local inaccessible = {}
local currentTime = 100
local printed = {}
local metric = {
    PeakTime = 1,
    CountTimeOver1Ms = 2,
}

Enum = {
    SecrecyLevel = { NeverSecret = 1, AlwaysSecret = 2, ContextuallySecret = 3 },
    AddOnProfilerMetric = {
        SessionAverageTime = 1,
        RecentAverageTime = 2,
        EncounterAverageTime = 3,
        LastTime = 4,
        PeakTime = 5,
        CountTimeOver1Ms = 6,
        CountTimeOver5Ms = 7,
        CountTimeOver10Ms = 8,
        CountTimeOver50Ms = 9,
        CountTimeOver100Ms = 10,
        CountTimeOver500Ms = 11,
        CountTimeOver1000Ms = 12,
    },
}

InterruptGlow = {
    name = "InterruptGlow",
    version = "test",
    DB = {
        schema = 4,
        producerVersion = "test",
        interface = 120105,
        enabled = true,
        cdText = false,
        cdm = true,
        animateGlow = true,
        strictNI = true,
        optimisticRestrictedCooldown = false,
        debug = true,
        debugChat = false,
        debugKeep = 400,
    },
    Stats = {},
    AbilityStates = {},
    CastState = {},
    Data = { interface = 120105, wowBuild = 70688, sourceCommit = "test" },
    Buttons = {},
    CDM = {},
    Glow = {
        prewarmHead = 1,
        prewarmTail = 0,
        prewarmScheduled = false,
        runtimeWorkerEnabled = false,
    },
    Worker = { SupportsOnUpdateMode = function() return false end },
    flushFrame = {},
}
local IG = InterruptGlow
function IG.CanAccess(value) return value ~= inaccessible end
function IG:Now() return currentTime end
function IG:IsInCombat() return false end
function IG:IsAddOnFullyLoaded() return false end
function IG:HasDirtyWork() return false end
function IG:Print(message) printed[#printed + 1] = message end
function IG:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function IG:StartProfileCounters(owner)
    if self.profileCounterOwner and self.profileCounterOwner ~= owner then
        return false, self.profileCounterOwner
    end
    self.profileCounterOwner = owner
    self.profileCountersEnabled = true
    self:WipeMap(self.Stats)
    return true, owner
end
function IG:StopProfileCounters(owner)
    if self.profileCounterOwner ~= owner then return false, self.profileCounterOwner end
    self.profileCounterOwner = nil
    self.profileCountersEnabled = false
    return true
end
function IG:BumpStat(key, amount) self.Stats[key] = (self.Stats[key] or 0) + (amount or 1) end

C_AddOns = { GetAddOnMetadata = function() return "test-version" end }
C_Secrets = {
    HasSecretRestrictions = function() return inaccessible end,
    ShouldCooldownsBeSecret = function() return false end,
    ShouldUnitSpellCastingBeSecret = function() return true end,
    GetSpellCooldownSecrecy = function() return inaccessible end,
    ShouldSpellCooldownBeSecret = function() return inaccessible end,
    ShouldActionCooldownBeSecret = function() return false end,
}
function GetBuildInfo() return inaccessible, 70688, "test", inaccessible end
function GetInstanceInfo() return inaccessible, "party", 1, inaccessible end
function date() return "2026-11-03T00:00:00Z" end

C_AddOnProfiler = {
    IsEnabled = function() return true end,
    GetTicksPerSecond = function() return inaccessible end,
    GetAddOnMetric = function(_, metricID)
        if metricID == Enum.AddOnProfilerMetric.PeakTime then return inaccessible end
        if metricID == Enum.AddOnProfilerMetric.CountTimeOver1Ms then return metric.CountTimeOver1Ms end
        error("simulated profiler metric failure")
    end,
}

local function Load(relative)
    local loader, loadError = loadfile(ROOT .. "/" .. relative)
    assert(loader, loadError)
    loader()
end
Load("core/Debug.lua")
Load("core/RuntimeProbe.lua")

local Debug = assert(IG.Debug)
local RuntimeProbe = assert(IG.RuntimeProbe)

-- Snapshotting must contain API errors and discard inaccessible metric values.
local snapshot = Debug:ProfilerSnapshot()
assert(snapshot.available == true and snapshot.enabled == true)
assert(snapshot.ticksPerSecond == nil)
assert(snapshot.metrics.PeakTime == nil)
assert(snapshot.metrics.CountTimeOver1Ms == 2)
assert(snapshot.metrics.CountTimeOver5Ms == nil)

-- Debug and capture labels are normalized only after accessibility checks; a
-- forbidden canary must never appear in the copyable report.
Debug:Log(inaccessible, inaccessible)
assert(Debug.entries[1]:find("<inaccessible>", 1, true))
assert(not Debug.entries[1]:find(tostring(inaccessible), 1, true))

assert(RuntimeProbe:Start("canary") == true)
RuntimeProbe:OnRestrictionStateChanged(inaccessible, inaccessible)
currentTime = 101
assert(RuntimeProbe:Stop() == true)
local report = assert(RuntimeProbe.lastReport)
assert(report:find("lastRestrictionType=unobserved", 1, true))
assert(report:find("lastRestrictionState=unobserved", 1, true))
assert(not report:find(tostring(inaccessible), 1, true))
assert(IG.profileCounterOwner == nil)

-- A missing profiler is explicitly unavailable, not a fabricated zero sample.
C_AddOnProfiler = nil
local unavailable = Debug:ProfilerSnapshot()
assert(unavailable.available == false)
assert(Debug:ProfilerReport(unavailable) == "C_AddOnProfiler is unavailable.")

print("PROFILER ACCESS AND FAILURE TEST PASSED")
