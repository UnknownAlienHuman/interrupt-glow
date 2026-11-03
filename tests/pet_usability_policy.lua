local ROOT = arg[1] or "."

_G = _G or _ENV

local petUsability = true
local secretUsability = {}
local usabilityCalls = 0
local petCooldownCalls = 0
local petInfoCalls = 0

InterruptGlow = {
    DB = { optimisticRestrictedCooldown = true },
    AbilityStates = {},
    Stats = {},
}
function InterruptGlow.CanAccess(value) return value ~= secretUsability end
function InterruptGlow:ReadMember(object, key)
    if not self.CanAccess(object) or object == nil then return nil, false end
    local value = object[key]
    if not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:AsNumber(value) return type(value) == "number" and value or nil end
function InterruptGlow:Now() return 100 end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat() end

function GetPetActionSlotUsable(slot)
    assert(slot == 3)
    usabilityCalls = usabilityCalls + 1
    return petUsability
end
function GetPetActionCooldown(slot)
    assert(slot == 3)
    petCooldownCalls = petCooldownCalls + 1
    return 0, 0, 1
end
function GetPetActionInfo(slot)
    assert(slot == 3)
    petInfoCalls = petInfoCalls + 1
    error("pet readiness must use GetPetActionSlotUsable, not range metadata")
end

local cooldownLoader, cooldownError = loadfile(ROOT .. "/core/Cooldown.lua")
assert(cooldownLoader, cooldownError)
cooldownLoader()
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

-- Usable pet actions remain ready even though GetPetActionInfo's range flags
-- could say out of range. Only the dedicated usability API supplies this gate.
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == true and ability.hardRestricted == false)
assert(record.ready == true and record.restrictedCooldown == false)
assert(record.hardRestrictedCooldown == false and record.readinessPending == false)
assert(usabilityCalls == 1 and petCooldownCalls == 1 and petInfoCalls == 0)

-- An ordinary unusable result is not ready and does not become a hard restriction.
petUsability = false
record.ready = true
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == false and ability.hardRestricted == false)
assert(record.ready == false and record.hardRestrictedCooldown == false)
assert(usabilityCalls == 2 and petInfoCalls == 0)

-- An inaccessible usability result fails closed, even with optimistic cooldown
-- compatibility enabled, and commits the restriction to every bound record.
petUsability = secretUsability
record.ready = true
record.restrictedCooldown = false
record.hardRestrictedCooldown = false
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == false and ability.restricted == true)
assert(ability.hardRestricted == true and ability.needsPoll == false)
assert(record.ready == false and record.restrictedCooldown == true)
assert(record.hardRestrictedCooldown == true)
assert(usabilityCalls == 3 and petInfoCalls == 0)

print("PET USABILITY FAIL-CLOSED TEST PASSED")
