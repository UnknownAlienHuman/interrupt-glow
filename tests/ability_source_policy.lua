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
    sourceKind = "action",
    sourceID = 5,
    ready = true,
    deadline = 120,
    restricted = true,
    hardRestricted = true,
    needsPoll = true,
    hasEvaluation = true,
    evaluatedGeneration = 9,
    records = {
        [action5] = true,
        [pet3] = true,
        [spell] = true,
        [inactive] = true,
    },
}

-- Existing source remains stable while a current record owns it.
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(observed[#observed].sourceKind == "action" and observed[#observed].sourceID == 5)
assert(ability.hasEvaluation == true)

-- Removing the selected action must not leave a stale slot as the readiness
-- source. Pet outranks the direct spell fallback.
ability.records[action5] = nil
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == "pet" and ability.sourceID == 3)
assert(ability.ready == false and ability.deadline == nil)
assert(ability.restricted == false and ability.hardRestricted == false)
assert(ability.needsPoll == false)
assert(ability.hasEvaluation == false and ability.evaluatedGeneration == nil)
assert(ability.readinessPending == true)
assert(pet3.readinessPending == true and spell.readinessPending == true)

-- A newly-bound action is more authoritative than pet/spell. Among duplicate
-- action slots, the deterministic lowest slot is selected only after the old
-- source disappears.
ability.records[action2] = true
ability.records[pet3] = nil
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == "action" and ability.sourceID == 2)

-- Direct spell/CDM remains a valid fallback after all action/pet records leave.
ability.records[action2] = nil
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == "spell" and ability.sourceID == 15487)

-- No live records means no source and no pending readiness work.
ability.records[spell] = nil
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(ability.sourceKind == nil and ability.sourceID == nil)
assert(ability.readinessPending == false)

local policy = assert(InterruptGlow.modules.AbilitySourcePolicy)
assert(policy.sharedReadinessRequiresBoundSource == true)
assert(policy.priority.action > policy.priority.pet)
assert(policy.priority.pet > policy.priority.spell)
assert((InterruptGlow.Stats["cooldown.abilitySourceChanged"] or 0) == 4)

print("ABILITY SOURCE POLICY TEST PASSED")
