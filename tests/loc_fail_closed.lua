local ROOT = arg[1] or "."

_G = _G or _ENV

local secretLoC = {}
local actionLoC = secretLoC
local spellLoC = secretLoC

InterruptGlow = {
    DB = { optimisticRestrictedCooldown = true },
    modules = {},
    AbilityStates = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= secretLoC end
function InterruptGlow:ReadMember(container, key)
    if not self.CanAccess(container) or container == nil then return nil, false end
    local value = container[key]
    if not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:AsNumber(value) return type(value) == "number" and value or nil end
function InterruptGlow:Now() return 100 end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat() end

local zeroDuration = {}
function zeroDuration:IsZero() return true end
function zeroDuration:GetRemainingDuration() return 0 end

C_ActionBar = {
    GetActionLossOfControlCooldownInfo = function() return actionLoC end,
    GetActionCharges = function() return nil end,
    GetActionCooldownDuration = function() return zeroDuration end,
    GetActionCooldown = function() return { isActive = false } end,
}

C_Spell = {
    GetSpellLossOfControlCooldownInfo = function() return spellLoC end,
    GetSpellCharges = function() return nil end,
    GetSpellCooldownDuration = function() return zeroDuration end,
    GetSpellCooldown = function() return { isActive = false } end,
}

-- A legacy global with an incompatible return shape must never be consulted.
function GetSpellLossOfControlCooldown()
    error("legacy spell LoC global was called")
end
function GetPetActionCooldown() return 0, 0, 1 end

local loader, loadError = loadfile(ROOT .. "/core/Cooldown.lua")
assert(loader, loadError)
loader()

local Cooldown = assert(InterruptGlow.Cooldown)

local ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("action", 1, false)
assert(ready == nil and remaining == nil)
assert(readinessRestricted == true and timingRestricted == true)
assert(needsPoll == false and hardRestricted == true)

ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("spell", 15487, false)
assert(ready == nil and remaining == nil)
assert(readinessRestricted == true and timingRestricted == true)
assert(needsPoll == false and hardRestricted == true)

-- The optimistic option may not turn inaccessible LoC into a ready glow.
local record = {}
local ability = {
    key = 15487,
    sourceKind = "action",
    sourceID = 1,
    records = { [record] = true },
    readinessPending = true,
}
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == false)
assert(ability.restricted == true)
assert(ability.hardRestricted == true)
assert(ability.needsPoll == false)
assert(record.ready == false and record.hardRestrictedCooldown == true)

-- An accessible nil LoC result means no LoC record and permits ordinary
-- ignore-GCD cooldown evaluation for both action and direct-spell sources.
actionLoC = nil
spellLoC = nil
Cooldown.generation = Cooldown.generation + 1
ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("action", 1, false)
assert(ready == true and remaining == 0)
assert(readinessRestricted == false and hardRestricted == false)

ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("spell", 15487, false)
assert(ready == true and remaining == 0)
assert(readinessRestricted == false and hardRestricted == false)

-- NeverSecret fields still require ordinary boolean types.
spellLoC = { isActive = "false", shouldReplaceNormalCooldown = false }
Cooldown.generation = Cooldown.generation + 1
ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("spell", 15487, false)
assert(ready == nil and hardRestricted == true)

local cooldownSource, sourceError = io.open(ROOT .. "/core/Cooldown.lua", "r")
assert(cooldownSource, sourceError)
local source = cooldownSource:read("*a")
cooldownSource:close()
assert(source:find("C_Spell.GetSpellLossOfControlCooldownInfo", 1, true))
assert(not source:find("_G.GetSpellLossOfControlCooldown", 1, true))

print("LOSS OF CONTROL FAIL-CLOSED TEST PASSED")
