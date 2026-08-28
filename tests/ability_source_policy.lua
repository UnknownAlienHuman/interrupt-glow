local ROOT = arg[1] or "."

_G = _G or _ENV

local observed = {}
local cooldownDirtyCalls = 0

InterruptGlow = {
    modules = {},
    Stats = {},
    Cooldown = {},
    Buttons = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:BumpStat(key, amount)
    self.Stats[key] = (self.Stats[key] or 0) + (amount or 1)
end
function InterruptGlow:MarkCooldownDirty()
    cooldownDirtyCalls = cooldownDirtyCalls + 1
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

-- Button binding must upgrade immediately even while the lower-priority spell
-- source remains bound. Waiting for a later cooldown event would leave stale CDM
-- or direct-spell readiness active on the newly visible action button.
ability.records[pet3] = true
assert(InterruptGlow.Buttons:RebuildAbilitySource(ability) == true)
assert(ability.sourceKind == "pet" and ability.sourceID == 3)
assert(cooldownDirtyCalls == 1)
assert(ability.ready == false and ability.deadline == nil)
assert(ability.restricted == false and ability.hardRestricted == false)
assert(ability.needsPoll == false)
assert(ability.hasEvaluation == false and ability.evaluatedGeneration == nil)
assert(ability.readinessPending == true)
assert(pet3.readinessPending == true and spell.readinessPending == true)

ability.records[action5] = true
assert(InterruptGlow.Buttons:RebuildAbilitySource(ability) == true)
assert(ability.sourceKind == "action" and ability.sourceID == 5)
assert(cooldownDirtyCalls == 2)

-- A lower action slot is the deterministic source among duplicate action records.
ability.records[action2] = true
assert(InterruptGlow.Buttons:RebuildAbilitySource(ability) == true)
assert(ability.sourceKind == "action" and ability.sourceID == 2)
assert(cooldownDirtyCalls == 3)

-- Removing records must immediately fall back through action -> pet -> spell.
ability.records[action2] = nil
assert(InterruptGlow.Buttons:RebuildAbilitySource(ability) == true)
assert(ability.sourceKind == "action" and ability.sourceID == 5)

ability.records[action5] = nil
assert(InterruptGlow.Buttons:RebuildAbilitySource(ability) == true)
assert(ability.sourceKind == "pet" and ability.sourceID == 3)

ability.records[pet3] = nil
assert(InterruptGlow.Buttons:RebuildAbilitySource(ability) == true)
assert(ability.sourceKind == "spell" and ability.sourceID == 15487)
assert(cooldownDirtyCalls == 6)

-- RefreshAbility is a final defensive boundary: if external code corrupts or
-- clears the selected source, it restores authority before the base evaluator.
ability.sourceKind = nil
ability.sourceID = nil
InterruptGlow.Cooldown:RefreshAbility(ability)
assert(observed[#observed].sourceKind == "spell")
assert(observed[#observed].sourceID == 15487)

-- A fully dormant ability keeps its last source/evaluation for same-generation
-- macro churn and queues no pointless refresh.
ability.records[spell] = nil
local dirtyBeforeDormant = cooldownDirtyCalls
assert(InterruptGlow.Buttons:RebuildAbilitySource(ability) == false)
assert(ability.dormant == true)
assert(cooldownDirtyCalls == dirtyBeforeDormant)

local policy = assert(InterruptGlow.modules.AbilitySourcePolicy)
assert(policy.sharedReadinessRequiresBoundSource == true)
assert(policy.upgradesToHigherPrioritySource == true)
assert(policy.ownsButtonSourceRebuild == true)
assert(policy.priority.action > policy.priority.pet)
assert(policy.priority.pet > policy.priority.spell)
assert((InterruptGlow.Stats["cooldown.abilitySourceChanged"] or 0) == 7)

print("ABILITY SOURCE POLICY TEST PASSED")
