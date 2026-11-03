local ROOT = arg[1] or "."

_G = _G or _ENV

local cooldownDirtyCalls = 0
local stats = {}
InterruptGlow = {
    DB = { enabled = true },
    Stats = stats,
    AbilityStates = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
}
function InterruptGlow:BumpStat(key, amount) stats[key] = (stats[key] or 0) + (amount or 1) end
function InterruptGlow:MarkCooldownDirty() cooldownDirtyCalls = cooldownDirtyCalls + 1 end

local loader, loadError = loadfile(ROOT .. "/core/Buttons.lua")
assert(loader, loadError)
loader()

local action5 = { isInterrupt = true, sourceKind = "action", sourceID = 5, ready = true }
local action2 = { isInterrupt = true, sourceKind = "action", sourceID = 2, ready = true }
local pet3 = { isInterrupt = true, sourceKind = "pet", sourceID = 3, ready = true }
local spell = { isInterrupt = true, sourceKind = "spell", sourceID = 15487, ready = true }
local inactive = { isInterrupt = false, sourceKind = "action", sourceID = 1 }
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
    records = { [spell] = true, [inactive] = true },
}
InterruptGlow.AbilityStates.test = ability

-- The actual Buttons owner arbitrates action > pet > direct spell, marks the
-- new source pending, and invalidates shared readiness when the best source changes.
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

-- Among duplicate action buttons, the lower slot is the stable tie breaker.
ability.records[action2] = true
assert(InterruptGlow.Buttons:RebuildAbilitySource(ability) == true)
assert(ability.sourceKind == "action" and ability.sourceID == 2)
assert(cooldownDirtyCalls == 3)

-- Removing higher-priority records selects the next valid source immediately.
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

-- Once all bound records disappear, same-spec macro churn keeps the dormant
-- canonical object without scheduling pointless readiness work.
ability.records[spell] = nil
ability.records[inactive] = nil
local dirtyBeforeDormant = cooldownDirtyCalls
assert(InterruptGlow.Buttons:RebuildAbilitySource(ability) == false)
assert(ability.dormant == true)
assert(cooldownDirtyCalls == dirtyBeforeDormant)

print("ABILITY SOURCE ARBITRATION TEST PASSED")
