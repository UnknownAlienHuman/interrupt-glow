local ROOT = arg[1] or "."

_G = _G or _ENV
local printed = {}

InterruptGlow = {
    name = "InterruptGlow",
    version = "1.1.0-beta.2",
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
        target = { active = true, hostile = true, niState = "interruptible", castBarID = 5 },
        focus = { active = false, hostile = false, niState = "none", castBarID = nil },
    },
    Data = {
        interface = 120100,
        wowBuild = 69497,
        sourceCommit = "027d26c",
        activeInterrupts = { [15487] = true },
    },
    Debug = {
        ProfilerReport = function()
            return "PeakTime 0.1\nCountTimeOver5Ms 0"
        end,
        ShowText = function(_, title, text)
            assert(title == "Interrupt Glow Runtime Probe")
            assert(text:find("%[build%]"))
        end,
    },
    modules = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:IsInCombat() return false end
function InterruptGlow:Now() return 100 end
function InterruptGlow:StartProfileCounters() self.Stats = {} end
function InterruptGlow:StopProfileCounters() end
function InterruptGlow:Print(message) printed[#printed + 1] = message end
function InterruptGlow.Data:GetActiveInterrupts() return pairs(self.activeInterrupts) end

C_Secrets = {
    HasSecretRestrictions = function() return true end,
    ShouldCooldownsBeSecret = function() return false end,
    ShouldUnitSpellCastingBeSecret = function(unit) return unit == "target" end,
    GetSpellCooldownSecrecy = function(_) return 1 end,
    ShouldSpellCooldownBeSecret = function(_) return false end,
    ShouldActionCooldownBeSecret = function(_) return false end,
}
Enum = { SecrecyLevel = { NeverSecret = 1, AlwaysSecret = 2, ContextuallySecret = 3 } }
function GetBuildInfo() return "12.1.0", "69497", "Aug 25 2026", 120100 end
function GetInstanceInfo() return "Test", "party", 8, "Mythic Keystone", 5, 0, false, 123, 5, 456 end
function date() return "2026-08-27T00:00:00Z" end

local loader, loadError = loadfile(ROOT .. "/core/RuntimeProbe.lua")
assert(loader, loadError)
loader()

local probe = InterruptGlow.RuntimeProbe
local report = probe:BuildReport()
assert(report:find("cooldownPolicy=NeverSecret"))
assert(report:find("repository=UnknownAlienHuman/interrupt%-glow"))

probe:Start("test")
probe:Mark("step")
probe:OnRestrictionStateChanged(1, 2)
probe:Stop()
probe:Show()

assert(#printed >= 4)
print("RUNTIME PROBE MOCK PASSED")
