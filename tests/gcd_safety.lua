local ROOT = arg[1] or "."

_G = _G or _ENV

local actionDurationArgs = {}
local spellDurationArgs = {}
local zeroReads = 0

InterruptGlow = {
    DB = { optimisticRestrictedCooldown = false },
    AbilityStates = {},
}
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:ReadMember(object, key)
    if object == nil then return nil, false end
    return object[key], true
end
function InterruptGlow:AsNumber(value) return type(value) == "number" and value or nil end
function InterruptGlow:Now() return 100 end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat() end

local remainingDuration = {}
function remainingDuration:IsZero()
    zeroReads = zeroReads + 1
    return false
end
function remainingDuration:GetRemainingDuration() return 2 end

C_ActionBar = {
    GetActionLossOfControlCooldownInfo = function() return nil end,
    GetActionCharges = function() return nil end,
    GetActionCooldownDuration = function(slot, ignoreGCD)
        actionDurationArgs = { slot, ignoreGCD }
        return remainingDuration
    end,
    -- `isOnGCD` is not evidence that the interrupt's personal cooldown is clear.
    GetActionCooldown = function() return { isActive = true, isOnGCD = true } end,
}
C_Spell = {
    GetSpellLossOfControlCooldownInfo = function() return nil end,
    GetSpellCharges = function() return nil end,
    GetSpellCooldownDuration = function(spellID, ignoreGCD)
        spellDurationArgs = { spellID, ignoreGCD }
        return remainingDuration
    end,
    GetSpellCooldown = function() return { isActive = true, isOnGCD = true } end,
}

local loader, loadError = loadfile(ROOT .. "/core/Cooldown.lua")
assert(loader, loadError)
loader()
local Cooldown = assert(InterruptGlow.Cooldown)

local actionReady, actionRemaining = Cooldown:GetCachedReadiness("action", 7)
assert(actionReady == false and actionRemaining == 2)
assert(actionDurationArgs[1] == 7 and actionDurationArgs[2] == true)

local spellReady, spellRemaining = Cooldown:GetCachedReadiness("spell", 15487)
assert(spellReady == false and spellRemaining == 2)
assert(spellDurationArgs[1] == 15487 and spellDurationArgs[2] == true)
assert(zeroReads == 2)

print("GCD IGNORE DURATION TEST PASSED")
