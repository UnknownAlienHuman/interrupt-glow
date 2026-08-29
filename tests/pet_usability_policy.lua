local ROOT = arg[1] or "."

_G = _G or _ENV

local usability = true
local secretUsability = {}
local usabilityCalls = 0
local infoCalls = 0

InterruptGlow = {
    modules = {},
    AbilityStates = {},
    Cooldown = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= secretUsability end

function GetPetActionSlotUsable(slot)
    assert(slot == 3)
    usabilityCalls = usabilityCalls + 1
    return usability
end

-- The eighth GetPetActionInfo return is checksRange in current Blizzard UI. It
-- is deliberately the opposite of usability so the old implementation fails.
function GetPetActionInfo(slot)
    assert(slot == 3)
    infoCalls = infoCalls + 1
    return "Spell Lock", nil, false, false, false, false, 19647, false, true
end

function InterruptGlow.Cooldown:RefreshAbility(ability)
    ability.ready = true
    ability.restricted = false
    ability.hardRestricted = false
    ability.needsPoll = true
    ability.deadline = 120
    ability.readinessPending = false
    return false
end

local readinessLoader, readinessError = loadfile(ROOT .. "/core/ReadinessPolicy.lua")
assert(readinessLoader, readinessError)
readinessLoader()

-- Usability is the final policy layer and owns the final ability->record commit.
local usabilityLoader, usabilityError = loadfile(ROOT .. "/core/Usability.lua")
assert(usabilityLoader, usabilityError)
usabilityLoader()

local Cooldown = InterruptGlow.Cooldown
local record = {
    ready = false,
    restrictedCooldown = true,
    hardRestrictedCooldown = true,
    deadline = nil,
    readinessPending = true,
}
local ability = {
    sourceKind = "pet",
    sourceID = 3,
    ready = false,
    restricted = false,
    hardRestricted = false,
    needsPoll = false,
    records = { [record] = true },
}

-- Actual usability=true must win even though GetPetActionInfo checksRange=false.
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == true)
assert(ability.hardRestricted == false)
assert(ability.needsPoll == true)
assert(record.ready == true)
assert(record.restrictedCooldown == false)
assert(record.hardRestrictedCooldown == false)
assert(record.deadline == 120)
assert(record.readinessPending == false)
assert(usabilityCalls == 1)
assert(infoCalls == 0, "pet readiness incorrectly read GetPetActionInfo metadata")

-- Explicit unusable is ordinary not-ready, not a secret hard restriction, and
-- the final physical record must not retain the base ready=true result.
usability = false
record.ready = true
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == false)
assert(ability.hardRestricted == false)
assert(ability.needsPoll == false)
assert(record.ready == false)
assert(record.hardRestrictedCooldown == false)
assert(usabilityCalls == 2 and infoCalls == 0)

-- Inaccessible usability hard-fails closed and is committed to every record.
usability = secretUsability
record.ready = true
record.restrictedCooldown = false
record.hardRestrictedCooldown = false
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == false)
assert(ability.restricted == true)
assert(ability.hardRestricted == true)
assert(ability.needsPoll == false)
assert(record.ready == false)
assert(record.restrictedCooldown == true)
assert(record.hardRestrictedCooldown == true)
assert(usabilityCalls == 3 and infoCalls == 0)

local policy = assert(InterruptGlow.modules.ReadinessPolicy)
assert(policy.petUsabilityGate == true)
assert(policy.petUsabilitySource == "GetPetActionSlotUsable")
assert(policy.batchedVisualCommit == true)
assert(InterruptGlow.Usability.finalRecordCommit == true)

print("PET USABILITY POLICY TEST PASSED")
