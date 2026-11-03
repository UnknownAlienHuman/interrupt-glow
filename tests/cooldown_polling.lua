local ROOT = arg[1] or "."

_G = _G or _ENV
local secret = {}
local actionDurationResult, actionCooldownResult
local spellDurationResult, spellCooldownResult
local actionChargesResult, spellChargesResult
local actionLocResult, spellLocResult

InterruptGlow = {
    DB = { optimisticRestrictedCooldown = false },
    AbilityStates = {},
    _dirty = {},
}
function InterruptGlow.CanAccess(value) return value ~= secret end
function InterruptGlow:ReadMember(object, key)
    if not self.CanAccess(object) or object == nil then return nil, false end
    local ok, value = pcall(function() return object[key] end)
    if not ok or not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:CanAccessTable(value)
    return self.CanAccess(value) and type(value) == "table"
end
function InterruptGlow:AsNumber(value)
    if not self.CanAccess(value) or type(value) ~= "number" then return nil end
    return value
end
function InterruptGlow:Now() return 10 end
function InterruptGlow:BumpStat() end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:MarkCooldownDirty() end

C_ActionBar = {
    GetActionLossOfControlCooldownInfo = function() return actionLocResult end,
    GetActionCharges = function() return actionChargesResult end,
    GetActionChargeDuration = function() return secret end,
    GetActionCooldownDuration = function() return actionDurationResult end,
    GetActionCooldown = function() return actionCooldownResult end,
}
C_Spell = {
    GetSpellLossOfControlCooldownInfo = function() return spellLocResult end,
    GetSpellCharges = function() return spellChargesResult end,
    GetSpellChargeDuration = function() return secret end,
    GetSpellCooldownDuration = function() return spellDurationResult end,
    GetSpellCooldown = function() return spellCooldownResult end,
}

local loader, loadError = loadfile(ROOT .. "/core/Cooldown.lua")
assert(loader, loadError)
loader()
local Cooldown = assert(InterruptGlow.Cooldown)

local function Read(kind, expectedReady, expectedRestricted, expectedPoll)
    Cooldown.generation = Cooldown.generation + 1
    local ready, _remaining, restricted, _timingRestricted, needsPoll, hardRestricted =
        Cooldown:GetCachedReadiness(kind, kind == "action" and 1 or 15487)
    assert(ready == expectedReady, kind .. " readiness mismatch")
    assert(restricted == expectedRestricted, kind .. " restriction mismatch: " .. tostring(restricted))
    assert(needsPoll == expectedPoll, kind .. " poll mismatch: " .. tostring(needsPoll))
    return hardRestricted
end

-- Opaque or malformed cooldown status provides no accessible non-ready fact.
-- It must remain fail-closed and wait for an invalidation event, not the timer.
actionDurationResult = secret
actionCooldownResult = secret
actionChargesResult = nil
actionLocResult = nil
spellDurationResult = secret
spellCooldownResult = secret
spellChargesResult = nil
spellLocResult = nil
assert(Read("action", nil, true, false) == false)
assert(Read("spell", nil, true, false) == false)

-- Missing and throwing getters also leave readiness unknown and do not poll.
C_ActionBar.GetActionCooldownDuration = nil
C_ActionBar.GetActionCooldown = function() error("mock action getter failure") end
C_Spell.GetSpellCooldownDuration = nil
C_Spell.GetSpellCooldown = function() error("mock spell getter failure") end
assert(Read("action", nil, true, false) == false)
assert(Read("spell", nil, true, false) == false)

-- A readable duration says the cooldown is active, but its remaining time is
-- inaccessible. This is a legitimate timing fallback: keep checking while the
-- known-not-ready state remains active and no usable deadline exists.
local durationWithKnownActiveState = {
    IsZero = function() return false end,
    GetRemainingDuration = function() return secret end,
}
C_ActionBar.GetActionCooldownDuration = function() return durationWithKnownActiveState end
C_ActionBar.GetActionCooldown = nil
C_Spell.GetSpellCooldownDuration = function() return durationWithKnownActiveState end
C_Spell.GetSpellCooldown = nil
assert(Read("action", false, false, true) == false)
assert(Read("spell", false, false, true) == false)

-- An accessible cooldown-status boolean also supports the timing fallback
-- when no duration deadline can be read.
C_ActionBar.GetActionCooldownDuration = function() return secret end
C_ActionBar.GetActionCooldown = function() return { isActive = true } end
C_Spell.GetSpellCooldownDuration = function() return secret end
C_Spell.GetSpellCooldown = function() return { isActive = true } end
assert(Read("action", false, false, true) == false)
assert(Read("spell", false, false, true) == false)

-- Exact zero charges are also accessible non-ready evidence, even when the
-- charge duration has no readable deadline.
actionChargesResult = { currentCharges = 0, maxCharges = 2 }
spellChargesResult = { currentCharges = 0, maxCharges = 2 }
assert(Read("action", false, false, true) == false)
assert(Read("spell", false, false, true) == false)
actionChargesResult = nil
spellChargesResult = nil

-- Hard loss-of-control restrictions never enter periodic polling.
actionLocResult = secret
spellLocResult = secret
assert(Read("action", nil, true, false) == true)
assert(Read("spell", nil, true, false) == true)

-- Optimistic compatibility may normalize unknown cooldown state to ready, but
-- it still cannot start a poll loop for inaccessible readiness.
actionLocResult = nil
spellLocResult = nil
C_ActionBar.GetActionCooldownDuration = function() return secret end
C_ActionBar.GetActionCooldown = function() return secret end
C_Spell.GetSpellCooldownDuration = function() return secret end
C_Spell.GetSpellCooldown = function() return secret end
InterruptGlow.DB.optimisticRestrictedCooldown = true
InterruptGlow.Usability = { ReadForAbility = function() return true, false, false end }
local ability = {
    sourceKind = "action",
    sourceID = 1,
    ready = false,
    restricted = true,
    readinessRestricted = true,
    timingRestricted = true,
    hardRestricted = false,
    needsPoll = false,
    records = {},
}
assert(Cooldown:RefreshAbility(ability) == true)
assert(ability.ready == true and ability.needsPoll == false)

-- A later invalidation generation reads the changed accessible status and
-- recovers without relying on the timing worker.
C_ActionBar.GetActionCooldownDuration = function()
    return { IsZero = function() return true end }
end
InterruptGlow.DB.optimisticRestrictedCooldown = false
Cooldown.generation = Cooldown.generation + 1
local ready, _remaining, _restricted, _timingRestricted, needsPoll =
    Cooldown:GetCachedReadiness("action", 1)
assert(ready == true and needsPoll == false)

print("COOLDOWN POLLING BOUNDARY TEST PASSED")
