local ROOT = arg[1] or "."

_G = _G or _ENV

local observed = {}

InterruptGlow = {
    modules = {},
    Stats = {},
    Cooldown = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:BumpStat(key, amount)
    self.Stats[key] = (self.Stats[key] or 0) + (amount or 1)
end

function InterruptGlow.Cooldown:RefreshAbility(ability)
    observed[#observed + 1] = {
        sourceKind = ability.sourceKind,
        sourceID = ability.sourceID,
        pending = ability.readinessPending,
        hasEvaluation = ability.hasEvaluation,
    }
    return true
end

local loader, loadError = loadfile(ROOT .. "/core/AbilitySourcePolicy.lua")
assert(loader, loadError)
loader()

local action5 = {
    isInterrupt = true,
    sourceKind = "action",
    sourceID = 5,
    ready = true,
}
local action2 = {
    isInterrupt = true,
    sourceKind = "action",
    sourceID = 2,
    ready = true,
}
local pet3 = {
    isInterrupt = true,
    sourceKind = "pet",
    sourceID = 3,
    ready = true,
}
local spell = {
    isInterrupt = true,
    sourceKind = "spell",
    sourceID = 15487,
    ready = true,
}
local inactive = {
    isInterrupt = false,
    sourceKind = "action",
    sourceID = 1,
}

local ability = {
    sourceKind = "spell",
    sourceID = 15487,
    ready = true,
    deadline = 120,
    restricted = true,
    hardRestricted = true,
    needsPoll = true,
    hasEvaluation = true,
    evaluatedGeneration = 9,
    records = {
        [spell] = true,
        [inactive] = true,
    },
}

-- A newly available stronger source must upgrade immediately even while the old
-- spell/CDM source remains bound. This is the regression that the previous
-- HasCurrentSource early-return missed.
ability.records[pet3] = true
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == "pet" and ability.sourceID == 3)
assert(ability.ready == false and ability.deadline == nil)
assert(ability.restricted == false and ability.hardRestricted == false)
assert(ability.needsPoll == false)
assert(ability.hasEvaluation == false and ability.evaluatedGeneration == nil)
assert(ability.readinessPending == true)
assert(pet3.readinessPending == true and spell.readinessPending == true)

-- Action outranks pet as soon as it appears; the pet record does not have to
-- disappear first.
ability.hasEvaluation = true
ability.ready = true
ability.records[action5] = true
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == "action" and ability.sourceID == 5)
assert(ability.hasEvaluation == false and ability.ready == false)

-- Among duplicate action sources, choose the deterministic lowest current slot.
ability.records[action2] = true
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == "action" and ability.sourceID == 2)

-- Removing the selected action falls back to the remaining action before pet.
ability.records[action2] = nil
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == "action" and ability.sourceID == 5)

-- Removing all action records falls back to pet, then direct spell/CDM.
ability.records[action5] = nil
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == "pet" and ability.sourceID == 3)

ability.records[pet3] = nil
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == "spell" and ability.sourceID == 15487)

-- No live records means no source and no pending readiness work.
ability.records[spell] = nil
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == nil and ability.sourceID == nil)
assert(ability.readinessPending == false)

local policy = assert(InterruptGlow.modules.AbilitySourcePolicy)
assert(policy.sharedReadinessRequiresBoundSource == true)
assert(policy.upgradesToHigherPrioritySource == true)
assert(policy.priority.action > policy.priority.pet)
assert(policy.priority.pet > policy.priority.spell)
assert((InterruptGlow.Stats["cooldown.abilitySourceChanged"] or 0) == 7)

print("ABILITY SOURCE POLICY TEST PASSED")
