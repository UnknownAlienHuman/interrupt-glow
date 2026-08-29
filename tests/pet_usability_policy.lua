local ROOT = arg[1] or "."

_G = _G or _ENV

local usability = true
local secretUsability = {}
local usabilityCalls = 0
local infoCalls = 0

InterruptGlow = {
    modules = {},
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
    return false
end

local loader, loadError = loadfile(ROOT .. "/core/ReadinessPolicy.lua")
assert(loader, loadError)
loader()

local Cooldown = InterruptGlow.Cooldown
local ability = {
    sourceKind = "pet",
    sourceID = 3,
    ready = false,
    restricted = false,
    hardRestricted = false,
    needsPoll = false,
}

-- Actual usability=true must win even though GetPetActionInfo checksRange=false.
assert(Cooldown:RefreshAbility(ability) == false)
assert(ability.ready == true)
assert(ability.hardRestricted == false)
assert(ability.needsPoll == true)
assert(usabilityCalls == 1)
assert(infoCalls == 0, "pet readiness incorrectly read GetPetActionInfo metadata")

-- Explicit unusable is ordinary not-ready, not a secret hard restriction.
usability = false
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == false)
assert(ability.hardRestricted == false)
assert(ability.needsPoll == false)
assert(usabilityCalls == 2 and infoCalls == 0)

-- Inaccessible usability hard-fails closed and cannot poll.
usability = secretUsability
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == false)
assert(ability.restricted == true)
assert(ability.hardRestricted == true)
assert(ability.needsPoll == false)
assert(usabilityCalls == 3 and infoCalls == 0)

local policy = assert(InterruptGlow.modules.ReadinessPolicy)
assert(policy.petUsabilityGate == true)
assert(policy.petUsabilitySource == "GetPetActionSlotUsable")
assert(policy.batchedVisualCommit == true)

print("PET USABILITY POLICY TEST PASSED")
