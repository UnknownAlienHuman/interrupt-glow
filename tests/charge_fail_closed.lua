local ROOT = arg[1] or "."

_G = _G or _ENV

local secretChargeInfo = {}
local secretCurrentCharges = {}
local secretDuration = {}
local actionChargeInfo = secretChargeInfo
local spellChargeInfo = secretChargeInfo

InterruptGlow = {
    DB = { optimisticRestrictedCooldown = true },
    modules = {},
    AbilityStates = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value)
    return value ~= secretChargeInfo
        and value ~= secretCurrentCharges
        and value ~= secretDuration
end
function InterruptGlow:ReadMember(container, key)
    if container == nil or not self.CanAccess(container) then return nil, false end
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
    GetActionLossOfControlCooldownInfo = function() return nil end,
    GetActionCharges = function() return actionChargeInfo end,
    GetActionChargeDuration = function() return zeroDuration end,
    GetActionCooldownDuration = function() return zeroDuration end,
    GetActionCooldown = function() return { isActive = false } end,
}

C_Spell = {
    GetSpellCharges = function() return spellChargeInfo end,
    GetSpellChargeDuration = function() return zeroDuration end,
    GetSpellCooldownDuration = function() return zeroDuration end,
    GetSpellCooldown = function() return { isActive = false } end,
}
function GetSpellLossOfControlCooldown() return nil end
function GetPetActionCooldown() return 0, 0, 1 end

local loader, loadError = loadfile(ROOT .. "/core/Cooldown.lua")
assert(loader, loadError)
loader()

local Cooldown = assert(InterruptGlow.Cooldown)

-- Inaccessible charge object must not fall through to a zero ordinary cooldown.
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

-- Optimistic restricted-cooldown compatibility cannot override unknown charges.
local record = {}
local ability = {
    key = 15487,
    sourceKind = "spell",
    sourceID = 15487,
    records = { [record] = true },
    readinessPending = true,
}
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == false)
assert(ability.hardRestricted == true)
assert(record.ready == false and record.hardRestrictedCooldown == true)

-- NeverSecret maxCharges==0 is an ordinary non-charge discriminator even if a
-- hypothetical currentCharges field is inaccessible. Normal cooldown fallback
-- must remain available for the common non-charge interrupt path.
actionChargeInfo = { currentCharges = secretCurrentCharges, maxCharges = 0 }
spellChargeInfo = { currentCharges = secretCurrentCharges, maxCharges = 0 }
Cooldown.generation = Cooldown.generation + 1
ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("action", 1, false)
assert(ready == true and remaining == 0)
assert(readinessRestricted == false and hardRestricted == false)

ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("spell", 15487, false)
assert(ready == true and remaining == 0)
assert(readinessRestricted == false and hardRestricted == false)

-- Accessible nil is the documented non-charge result for C_Spell and also falls
-- through to the ignore-GCD ordinary cooldown path.
actionChargeInfo = nil
spellChargeInfo = nil
Cooldown.generation = Cooldown.generation + 1
ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("action", 1, false)
assert(ready == true and remaining == 0)
assert(readinessRestricted == false and hardRestricted == false)

-- For a real charge ability, inaccessible currentCharges hard-fails closed even
-- though maxCharges itself remains available.
actionChargeInfo = { currentCharges = secretCurrentCharges, maxCharges = 2 }
spellChargeInfo = { currentCharges = secretCurrentCharges, maxCharges = 2 }
Cooldown.generation = Cooldown.generation + 1
ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("action", 1, false)
assert(ready == nil and remaining == nil)
assert(readinessRestricted == true and timingRestricted == true)
assert(needsPoll == false and hardRestricted == true)

-- Exact zero charges remain not ready even if recharge timing is inaccessible.
actionChargeInfo = { currentCharges = 0, maxCharges = 2 }
spellChargeInfo = { currentCharges = 0, maxCharges = 2 }
function C_ActionBar.GetActionChargeDuration() return secretDuration end
function C_Spell.GetSpellChargeDuration() return secretDuration end
Cooldown.generation = Cooldown.generation + 1
ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("action", 1, false)
assert(ready == false and remaining == nil)
assert(readinessRestricted == false and timingRestricted == true)
assert(needsPoll == true and hardRestricted == false)

print("CHARGE FAIL-CLOSED TEST PASSED")
