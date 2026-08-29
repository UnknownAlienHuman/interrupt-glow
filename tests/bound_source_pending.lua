local ROOT = arg[1] or "."

_G = _G or _ENV

local baseRebuildCalls = 0
local baseRefreshCalls = 0
local cooldownDirtyCalls = 0
local stats = {}

InterruptGlow = {
    modules = {},
    AbilityStates = {},
    Buttons = {},
    Cooldown = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:BumpStat(key) stats[key] = (stats[key] or 0) + 1 end
function InterruptGlow:MarkCooldownDirty()
    cooldownDirtyCalls = cooldownDirtyCalls + 1
    return true
end

function InterruptGlow.Buttons:RebuildAbilitySource(ability)
    baseRebuildCalls = baseRebuildCalls + 1
    for record in pairs(ability.records) do
        if record.isInterrupt and type(record.sourceID) == "number" then
            ability.sourceKind = record.sourceKind
            ability.sourceID = record.sourceID
            ability.sourceChanged = true
            return true
        end
    end
    return false
end

function InterruptGlow.Cooldown:RefreshAbility(ability)
    baseRefreshCalls = baseRefreshCalls + 1
    ability.hasEvaluation = true
    ability.evaluatedGeneration = 9
    ability.readinessPending = false
    ability.ready = true
    for record in pairs(ability.records) do
        record.readinessPending = false
        record.ready = true
    end
    return true
end
function InterruptGlow.Cooldown:RefreshAll() return false end

local loader, loadError = loadfile(ROOT .. "/core/BoundSourcePolicy.lua")
assert(loader, loadError)
loader()

local record = {
    isInterrupt = true,
    sourceKind = nil,
    sourceID = nil,
    ready = true,
    deadline = 105,
    restrictedCooldown = false,
    hardRestrictedCooldown = false,
    readinessPending = false,
}
local ability = {
    records = { [record] = true },
    sourceKind = "action",
    sourceID = 7,
    sourceChanged = false,
    dormant = false,
    hasEvaluation = true,
    evaluatedGeneration = 8,
    ready = true,
    deadline = 105,
    needsPoll = true,
    restricted = false,
    readinessRestricted = false,
    timingRestricted = false,
    hardRestricted = false,
    readinessPending = false,
}

-- A bound record without any eligible source is unknown, not evaluated. The
-- base evaluator must not run with sourceKind/sourceID=nil and clear pending.
assert(InterruptGlow.Cooldown:RefreshAbility(ability) == true)
assert(baseRefreshCalls == 0)
assert(ability.sourceKind == nil and ability.sourceID == nil)
assert(ability.ready == false and ability.restricted == true)
assert(ability.hardRestricted == true and ability.needsPoll == false)
assert(ability.hasEvaluation == false and ability.evaluatedGeneration == nil)
assert(ability.readinessPending == true)
assert(record.ready == false and record.readinessPending == true)
assert(record.restrictedCooldown == true and record.hardRestrictedCooldown == true)

-- Repeating the same invalid snapshot remains stable and still does not enter
-- the base readiness evaluator.
assert(InterruptGlow.Cooldown:RefreshAbility(ability) == false)
assert(baseRefreshCalls == 0)
assert(ability.readinessPending == true and record.readinessPending == true)

-- Once a valid record source appears, source arbitration and the normal base
-- evaluator resume.
record.sourceKind = "action"
record.sourceID = 7
assert(InterruptGlow.Buttons:RebuildAbilitySource(ability) == true)
assert(baseRebuildCalls == 1)
assert(ability.sourceKind == "action" and ability.sourceID == 7)
assert(InterruptGlow.Cooldown:RefreshAbility(ability) == true)
assert(baseRefreshCalls == 1)
assert(ability.hasEvaluation == true and ability.readinessPending == false)
assert(record.ready == true and record.readinessPending == false)

assert(cooldownDirtyCalls == 0)
assert((stats["cooldown.boundAbilityMissingSource"] or 0) == 1)
local policy = assert(InterruptGlow.modules.BoundSourcePolicy)
assert(policy.missingSourceRemainsReadinessPending == true)
print("BOUND SOURCE PENDING TEST PASSED")
