local ROOT = arg[1] or "."

_G = _G or _ENV
local printed = {}

InterruptGlow = {
    name = "InterruptGlow",
    version = "1.1.0-beta.7",
    DB = {
        schema = 3,
        producerVersion = "1.1.0-beta.7",
        interface = 120100,
        debug = false,
        debugKeep = 400,
        debugChat = false,
    },
    AbilityStates = {
        [15487] = {
            key = 15487,
            sourceKind = "action",
            sourceID = 1,
            canonicalSpellID = 15487,
            ready = true,
            readinessPending = false,
            restricted = false,
            hardRestricted = false,
            needsPoll = false,
            deadline = nil,
            records = { [{}] = true },
        },
    },
    Stats = { ["events.actionButtonChanged"] = 10 },
    CastState = {
        target = {
            active = true,
            hostile = true,
            isChannel = true,
            niState = "interruptible",
            castBarID = 5,
            channelSuppressed = false,
            lastEvent = "UNIT_SPELLCAST_CHANNEL_START",
        },
        focus = {
            active = false,
            hostile = false,
            isChannel = false,
            niState = "none",
            castBarID = nil,
            channelSuppressed = true,
            lastEvent = "UNIT_SPELLCAST_CHANNEL_STOP",
        },
    },
    Data = {
        interface = 120100,
        wowBuild = 69497,
        sourceCommit = "027d26c3406d3de2cbd2b1f67d468fe033a1bcd4",
        activeInterrupts = { [15487] = true },
    },
    Buttons = {
        nativeAttached = true,
        dominosAttached = true,
        buttonForgeAttached = false,
    },
    CDM = { attached = false },
    Glow = {
        prewarmFrame = {},
        runtimeFrame = {},
        prewarmHead = 1,
        prewarmTail = 0,
        prewarmScheduled = false,
        runtimeWorkerEnabled = false,
    },
    flushFrame = {},
    modules = {},
    profileCountersEnabled = false,
    profileCounterOwner = nil,
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:IsInCombat() return false end
function InterruptGlow:IsAddOnFullyLoaded(name) return name == "Dominos" end
function InterruptGlow:HasDirtyWork() return false end
function InterruptGlow:Now() return _G.mockNow end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:StartProfileCounters(owner)
    if self.profileCounterOwner and self.profileCounterOwner ~= owner then
        return false, self.profileCounterOwner
    end
    self:WipeMap(self.Stats)
    self.profileCounterOwner = owner
    self.profileCountersEnabled = true
    return true, owner
end
function InterruptGlow:StopProfileCounters(owner)
    if self.profileCounterOwner and self.profileCounterOwner ~= owner then
        return false, self.profileCounterOwner
    end
    self.profileCounterOwner = nil
    self.profileCountersEnabled = false
    return true
end
function InterruptGlow:Print(message) printed[#printed + 1] = message end
function InterruptGlow.Data:GetActiveInterrupts() return pairs(self.activeInterrupts) end
InterruptGlow.Worker = {
    SupportsOnUpdateMode = function(_, frame) return frame ~= nil end,
}
InterruptGlow:RegisterModule("GCDSafetyPolicy", {
    ignoresGlobalCooldownInDurationAPI = true,
    treatsIsOnGCDAsReadinessProof = false,
})

UIParent = {}
ChatFontNormal = {}
function CreateFrame()
    local frame = { scripts = {}, TitleText = { SetText = function() end } }
    function frame:SetSize() end
    function frame:SetPoint() end
    function frame:SetFrameStrata() end
    function frame:Hide() end
    function frame:Show() end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:CreateFontString() return { SetText = function() end } end
    function frame:SetScrollChild() end
    function frame:SetMultiLine() end
    function frame:SetAutoFocus() end
    function frame:SetFontObject() end
    function frame:SetWidth() end
    function frame:SetTextInsets() end
    function frame:SetHeight() end
    function frame:SetText() end
    function frame:HighlightText() end
    return frame
end

local metricValues = {}
Enum = {
    SecrecyLevel = { NeverSecret = 1, AlwaysSecret = 2, ContextuallySecret = 3 },
    AddOnProfilerMetric = {
        SessionAverageTime = 0,
        RecentAverageTime = 1,
        EncounterAverageTime = 2,
        LastTime = 3,
        PeakTime = 4,
        CountTimeOver1Ms = 5,
        CountTimeOver5Ms = 6,
        CountTimeOver10Ms = 7,
        CountTimeOver50Ms = 8,
        CountTimeOver100Ms = 9,
        CountTimeOver500Ms = 10,
        CountTimeOver1000Ms = 11,
    },
}
for index = 0, 11 do metricValues[index] = 0 end
metricValues[Enum.AddOnProfilerMetric.PeakTime] = 0.4
metricValues[Enum.AddOnProfilerMetric.CountTimeOver1Ms] = 10
metricValues[Enum.AddOnProfilerMetric.CountTimeOver5Ms] = 2

C_AddOnProfiler = {
    IsEnabled = function() return true end,
    GetTicksPerSecond = function() return 1000 end,
    GetAddOnMetric = function(_, metric) return metricValues[metric] end,
}
C_Secrets = {
    HasSecretRestrictions = function() return true end,
    ShouldCooldownsBeSecret = function() return false end,
    ShouldUnitSpellCastingBeSecret = function(unit) return unit == "target" end,
    GetSpellCooldownSecrecy = function(_) return 1 end,
    ShouldSpellCooldownBeSecret = function(_) return false end,
    ShouldActionCooldownBeSecret = function(_) return false end,
}
function GetBuildInfo() return "12.1.0", "69497", "Aug 25 2026", 120100 end
function GetInstanceInfo() return "Test", "party", 8, "Mythic Keystone", 5, 0, false, 123, 5, 456 end
function date() return "2026-08-29T00:00:00Z" end
mockNow = 100

local debugLoader, debugError = loadfile(ROOT .. "/core/Debug.lua")
assert(debugLoader, debugError)
debugLoader()

local shownReport
InterruptGlow.Debug.ShowText = function(_, title, text)
    assert(title == "Interrupt Glow Runtime Probe")
    shownReport = text
end

local probeLoader, probeError = loadfile(ROOT .. "/core/RuntimeProbe.lua")
assert(probeLoader, probeError)
probeLoader()

local probe = InterruptGlow.RuntimeProbe
local initialReport = probe:BuildReport()
assert(initialReport:find("cooldownPolicy=NeverSecret"))
assert(initialReport:find("repository=UnknownAlienHuman/interrupt%-glow"))
assert(initialReport:find("kbCommit=5a992ae702a278f3893c7e8f1b212583311438b5", 1, true))
assert(initialReport:find("savedSchema=3", 1, true))
assert(initialReport:find("counterOwner=none", 1, true))
assert(initialReport:find("Dominos.loaded=true"))
assert(initialReport:find("focus.channelSuppressed=true"))
assert(initialReport:find("runtime.enabled=false", 1, true))
assert(initialReport:find("gcd.ignoreGlobalCooldownDuration=true", 1, true))
assert(initialReport:find("gcd.isOnGCDReadinessProof=false", 1, true))
assert(initialReport:find("upstream.WOWUI%-2026%-005=ACTIVE_UPSTREAM"))

assert(probe:Start("quick-heal-mouseover") == true)
assert(InterruptGlow.profileCounterOwner == "capture")
metricValues[Enum.AddOnProfilerMetric.PeakTime] = 2.5
metricValues[Enum.AddOnProfilerMetric.CountTimeOver1Ms] = 14
metricValues[Enum.AddOnProfilerMetric.CountTimeOver5Ms] = 4
metricValues[Enum.AddOnProfilerMetric.CountTimeOver10Ms] = 1
mockNow = 110
assert(probe:Mark("friendly-hover") == true)

metricValues[Enum.AddOnProfilerMetric.PeakTime] = 7.5
metricValues[Enum.AddOnProfilerMetric.CountTimeOver1Ms] = 20
metricValues[Enum.AddOnProfilerMetric.CountTimeOver5Ms] = 7
metricValues[Enum.AddOnProfilerMetric.CountTimeOver10Ms] = 3
mockNow = 120
local printedBeforeRestriction = #printed
probe:OnRestrictionStateChanged(1, 2)
assert(#printed == printedBeforeRestriction, "automatic restriction marker spammed chat")
assert(probe:Stop() == true)
assert(InterruptGlow.profileCounterOwner == nil)
probe:Show()

assert(shownReport)
assert(shownReport:find("start.PeakTime=0.4", 1, true))
assert(shownReport:find("end.PeakTime=7.5", 1, true))
assert(shownReport:find("delta.CountTimeOver1Ms=10", 1, true))
assert(shownReport:find("delta.CountTimeOver5Ms=5", 1, true))
assert(shownReport:find("delta.CountTimeOver10Ms=3", 1, true))
assert(shownReport:find("delta.PeakTimeIncrease=7.1", 1, true))
assert(shownReport:find("marker.1.label=friendly-hover", 1, true))
assert(shownReport:find("restriction.1=20.000 type=1 state=2", 1, true))

-- A manual diagnostic owner must block capture acquisition without losing its
-- counters or mutating probe state.
assert(InterruptGlow:StartProfileCounters("manual") == true)
InterruptGlow.Stats.manual = 7
assert(probe:Start("blocked-by-manual") == false)
assert(InterruptGlow.profileCounterOwner == "manual")
assert(InterruptGlow.Stats.manual == 7)
assert(probe.active == false)
assert(InterruptGlow:StopProfileCounters("manual") == true)

-- A new capture must not inherit the previous context's last restriction state.
mockNow = 130
assert(probe:Start("second-context") == true)
local secondReport = probe:BuildReport()
assert(secondReport:find("lastRestrictionType=unobserved", 1, true))
assert(secondReport:find("lastRestrictionState=unobserved", 1, true))
assert(not secondReport:find("restriction.1=", 1, true))
assert(probe:Stop() == true)

assert(#printed >= 6)
print("RUNTIME PROBE MOCK PASSED")
