local ROOT = arg[1] or "."

_G = _G or _ENV

local stats = {}
InterruptGlow = {
    DB = { optimisticRestrictedCooldown = true },
    modules = {},
    AbilityStates = {},
    Stats = stats,
}
function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:ReadMember(object, key)
    if object == nil then return nil, false end
    return object[key], true
end
function InterruptGlow:AsNumber(value) return type(value) == "number" and value or nil end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat(key, amount)
    stats[key] = (stats[key] or 0) + (amount or 1)
end

local loader, loadError = loadfile(ROOT .. "/core/Cooldown.lua")
assert(loader, loadError)
loader()

local record = {
    ready = true,
    deadline = 105,
    restrictedCooldown = false,
    hardRestrictedCooldown = false,
    readinessPending = false,
}
local ability = {
    records = { [record] = true },
    sourceKind = nil,
    sourceID = nil,
    hasEvaluation = true,
    evaluatedGeneration = 8,
    ready = true,
    deadline = 105,
    restricted = false,
    readinessRestricted = false,
    timingRestricted = false,
    hardRestricted = false,
    needsPoll = true,
    readinessPending = false,
}

-- A still-bound ability with no currently eligible source is unknown, never
-- ready. The fail-closed state remains pending until Buttons binds a real source.
assert(InterruptGlow.Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == false and ability.restricted == true)
assert(ability.hardRestricted == true and ability.needsPoll == false)
assert(ability.hasEvaluation == false and ability.evaluatedGeneration == nil)
assert(ability.readinessPending == true)
assert(record.ready == false and record.readinessPending == true)
assert(record.restrictedCooldown == true and record.hardRestrictedCooldown == true)
assert(record.deadline == nil)

-- Repeating the same malformed snapshot does not repeatedly clear/requeue it.
assert(InterruptGlow.Cooldown:RefreshAbility(ability) == false)
assert(ability.readinessPending == true and record.readinessPending == true)

print("BOUND SOURCE FAIL-CLOSED TEST PASSED")
