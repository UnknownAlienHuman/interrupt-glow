local ROOT = arg[1] or "."

_G = _G or _ENV

local legacyCalls = 0
local currentCalls = 0
local cooldownCalls = 0
local locInfo = {
    isActive = true,
    shouldReplaceNormalCooldown = true,
}

function GetSpellLossOfControlCooldown()
    legacyCalls = legacyCalls + 1
    error("legacy spell Loss of Control API must not be used")
end

C_Spell = {
    GetSpellLossOfControlCooldown = function(spellID)
        assert(spellID == 1766)
        currentCalls = currentCalls + 1
        return locInfo
    end,
    GetSpellCharges = function() return nil end,
    GetSpellCooldownDuration = function()
        cooldownCalls = cooldownCalls + 1
        error("blocked Loss of Control must short-circuit normal cooldown reads")
    end,
    GetSpellCooldown = function()
        cooldownCalls = cooldownCalls + 1
        error("blocked Loss of Control must short-circuit normal cooldown reads")
    end,
}
C_ActionBar = {}

InterruptGlow = {
    modules = {},
    DB = { optimisticRestrictedCooldown = true },
    AbilityStates = {},
    CastState = {},
    Stats = {},
}
function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= "secret" end
function InterruptGlow:ReadMember(container, key)
    if not self.CanAccess(container) or container == nil then return nil, false end
    local ok, value = pcall(function() return container[key] end)
    if not ok or not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:AsNumber(value)
    if type(value) == "number" then return value end
end
function InterruptGlow:Now() return 100 end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat() end

local loader, loadError = loadfile(ROOT .. "/core/Cooldown.lua")
assert(loader, loadError)
loader()

local Cooldown = assert(InterruptGlow.Cooldown)
local ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("spell", 1766, false)
assert(ready == false)
assert(remaining == nil)
assert(readinessRestricted == false)
assert(timingRestricted == false)
assert(needsPoll == false)
assert(hardRestricted == false)
assert(currentCalls == 1)
assert(legacyCalls == 0)
assert(cooldownCalls == 0)

Cooldown.generation = Cooldown.generation + 1
C_Spell.GetSpellLossOfControlCooldown = function(spellID)
    assert(spellID == 1766)
    currentCalls = currentCalls + 1
    return nil
end
C_Spell.GetSpellCooldownDuration = function(spellID, ignoreGCD)
    assert(spellID == 1766 and ignoreGCD == true)
    cooldownCalls = cooldownCalls + 1
    return {
        IsZero = function() return true end,
    }
end

ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
    Cooldown:GetCachedReadiness("spell", 1766, false)
assert(ready == true and remaining == 0)
assert(readinessRestricted == false and timingRestricted == false)
assert(needsPoll == false and hardRestricted == false)
assert(currentCalls == 2 and legacyCalls == 0 and cooldownCalls == 1)

print("SPELL LOSS OF CONTROL API TEST PASSED")
