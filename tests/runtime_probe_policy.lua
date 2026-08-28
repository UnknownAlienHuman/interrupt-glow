local ROOT = arg[1] or "."

_G = _G or _ENV

local printed = 0
local originalShowCalls = 0
local combat = false

InterruptGlow = {
    modules = {},
    RuntimeProbe = {
        active = false,
        marks = {},
        restrictionTransitions = {},
        startedAt = 100,
    },
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:Print() printed = printed + 1 end
function InterruptGlow:Now() return 150 end
function InterruptGlow:IsInCombat() return combat end

local Probe = InterruptGlow.RuntimeProbe
function Probe:Start()
    self.active = true
    self.marks = {}
    self.restrictionTransitions = {}
    self.startedAt = 100
    return true
end
function Probe:AddMark(label)
    self.marks[#self.marks + 1] = { label = label }
    return true
end
function Probe:OnRestrictionStateChanged(restrictionType, state)
    self.restrictionTransitions[#self.restrictionTransitions + 1] = {
        restrictionType = restrictionType,
        state = state,
    }
    self:AddMark("legacy-restriction", false)
end
function Probe:BuildReport() return "base-report" end
function Probe:Show()
    originalShowCalls = originalShowCalls + 1
end

local loader, loadError = loadfile(ROOT .. "/core/RuntimeProbePolicy.lua")
assert(loader, loadError)
loader()

assert(Probe:Start("bounded") == true)
for index = 1, 257 do
    Probe:AddMark("mark-" .. index, true)
end
assert(#Probe.marks == 256)
assert(Probe.droppedMarks == 1)
assert(printed == 1, "marker limit should report once")

for index = 1, 129 do
    Probe:OnRestrictionStateChanged(index, index)
end
assert(#Probe.restrictionTransitions == 128)
assert(Probe.droppedRestrictions == 1)
assert(#Probe.marks == 256, "restriction transitions created profiler markers")

local report = Probe:BuildReport()
assert(report:find("[probeBounds]", 1, true))
assert(report:find("storedMarks=256", 1, true))
assert(report:find("droppedMarks=1", 1, true))
assert(report:find("storedRestrictions=128", 1, true))
assert(report:find("droppedRestrictions=1", 1, true))

combat = true
assert(Probe:Show() == false)
assert(originalShowCalls == 0, "combat Show built/opened the original report")
combat = false
assert(Probe:Show() == true)
assert(originalShowCalls == 1)

local policy = assert(InterruptGlow.modules.RuntimeProbePolicy)
assert(policy.maxMarks == 256)
assert(policy.maxRestrictions == 128)
assert(policy.buildsReportsOutOfCombatOnly == true)
assert(policy.automaticRestrictionProfilerSnapshots == false)

print("RUNTIME PROBE POLICY TEST PASSED")
