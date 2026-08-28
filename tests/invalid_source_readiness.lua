local ROOT = arg[1] or "."

_G = _G or _ENV

InterruptGlow = {
    DB = { optimisticRestrictedCooldown = true },
    modules = {},
    AbilityStates = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:ReadMember(container, key) return container and container[key], container ~= nil end
function InterruptGlow:AsNumber(value) return type(value) == "number" and value or nil end
function InterruptGlow:Now() return 100 end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat() end

local loader, loadError = loadfile(ROOT .. "/core/Cooldown.lua")
assert(loader, loadError)
loader()

local record = {}
local ability = {
    key = "invalid",
    sourceKind = nil,
    sourceID = nil,
    records = { [record] = true },
    ready = true,
    restricted = false,
    hardRestricted = false,
    needsPoll = true,
    readinessPending = true,
}

assert(InterruptGlow.Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == false, "optimistic mode made a missing source ready")
assert(ability.restricted == true)
assert(ability.hardRestricted == true)
assert(ability.needsPoll == false)
assert(ability.readinessPending == false)
assert(record.ready == false)
assert(record.hardRestrictedCooldown == true)

local rawReady, _, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    InterruptGlow.Cooldown:GetCachedReadiness(nil, nil, false)
assert(rawReady == nil)
assert(readinessRestricted == true and timingRestricted == true)
assert(needsPoll == false and hardRestricted == true)

print("INVALID SOURCE READINESS TEST PASSED")
