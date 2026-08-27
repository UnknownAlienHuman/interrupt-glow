local IG = _G.InterruptGlow
if not IG then return end

local Cooldown = {
    generation = 0,
    cache = {
        action = {},
        spell = {},
        pet = {},
    },
    gcdHints = {},
}
IG.Cooldown = Cooldown
IG:RegisterModule("Cooldown", Cooldown)

local _G = _G
local C_ActionBar = _G.C_ActionBar
local C_Spell = _G.C_Spell
local GetPetActionCooldown = _G.GetPetActionCooldown
local pcall = pcall
local type = type
local pairs = pairs
local math_abs = math.abs

local function ReadObjectMethod(object, methodName)
    return object[methodName]
end

local function CallObjectMethod(object, methodName)
    if not IG.CanAccess(object) or object == nil then return false, nil end

    local indexOK, method = pcall(ReadObjectMethod, object, methodName)
    if not indexOK or type(method) ~= "function" then return false, nil end

    local ok, value = pcall(method, object)
    if not ok or not IG.CanAccess(value) then return false, nil end
    return true, value
end

-- Returns ready, remaining, timingRestricted, hasDuration.
-- The duration object itself is never retained. Numeric methods are called only
-- after HasSecretValues is known false.
local function ReadDuration(duration)
    if not IG.CanAccess(duration) then
        return nil, nil, true, true
    end
    if duration == nil then
        return nil, nil, false, false
    end

    local hasSecretKnown, hasSecret = CallObjectMethod(duration, "HasSecretValues")
    if not hasSecretKnown or hasSecret == true then
        return nil, nil, true, true
    end

    local zeroKnown, isZero = CallObjectMethod(duration, "IsZero")
    if not zeroKnown then
        return nil, nil, true, true
    end
    if isZero == true then
        return true, 0, false, true
    end

    local remainingKnown, remaining = CallObjectMethod(duration, "GetRemainingDuration")
    if not remainingKnown or type(remaining) ~= "number" then
        -- Readiness is still exactly false because IsZero was accessible.
        return false, nil, true, true
    end
    if remaining <= 0 then
        return true, 0, false, true
    end
    return false, remaining, false, true
end

-- Returns ready, remaining, readinessRestricted, timingRestricted, isCharge.
local function ReadChargeInfo(info, durationGetter, sourceID)
    if not IG.CanAccess(info) then
        return nil, nil, true, true, true
    end
    if info == nil then
        return nil, nil, false, false, false
    end

    local maxCharges, maxKnown = IG:ReadMember(info, "maxCharges")
    if not maxKnown or type(maxCharges) ~= "number" or maxCharges <= 1 then
        return nil, nil, false, false, false
    end

    local isActive, activeKnown = IG:ReadMember(info, "isActive")
    local currentCharges, currentKnown = IG:ReadMember(info, "currentCharges")

    -- maxCharges and isActive are NeverSecret in 12.1.0.
    if activeKnown and isActive == false then
        return true, 0, false, false, true
    end

    if currentKnown and type(currentCharges) == "number" then
        if currentCharges > 0 then
            return true, 0, false, false, true
        end

        local duration = nil
        if type(durationGetter) == "function" then
            local ok, value = pcall(durationGetter, sourceID)
            if ok then duration = value end
        end
        local _durationReady, remaining, timingRestricted = ReadDuration(duration)
        -- currentCharges == 0 is an exact not-ready answer. A secret recharge
        -- duration only hides the number and requires a low-frequency expiry poll.
        return false, remaining, false, timingRestricted, true
    end

    -- While recharge is active, a restricted currentCharges field leaves the
    -- actual readiness unknown (there may still be one available charge).
    return nil, nil, true, true, true
end

-- Returns ready, readinessRestricted.
local function ReadCooldownStatus(info, gcdOnlyHint)
    if not IG.CanAccess(info) then
        return nil, true
    end
    if info == nil then
        return nil, false
    end

    local enabled, enabledKnown = IG:ReadMember(info, "isEnabled")
    local active, activeKnown = IG:ReadMember(info, "isActive")

    if enabledKnown and enabled == false then
        return false, false
    end
    if activeKnown and active == false then
        return true, false
    end
    if activeKnown and active == true then
        -- isOnGCD is normalized into a plain hint inside the actual
        -- SPELL_UPDATE_COOLDOWN handler; never read it one frame later.
        if gcdOnlyHint == true then return true, false end
        return false, false
    end

    return nil, true
end

-- Returns blocked, restricted. A restricted LoC payload must never be treated
-- as an accessible "not blocked" result.
local function ReadLossOfControlState(info)
    if not IG.CanAccess(info) then return nil, true end
    if info == nil then return false, false end

    local active, activeKnown = IG:ReadMember(info, "isActive")
    local replaces, replacesKnown = IG:ReadMember(info, "shouldReplaceNormalCooldown")
    if not activeKnown or not replacesKnown then return nil, true end
    return active == true and replaces == true, false
end

local function GetActionLossOfControlState(slot)
    if not C_ActionBar or type(C_ActionBar.GetActionLossOfControlCooldownInfo) ~= "function" then
        return false, false
    end
    local ok, info = pcall(C_ActionBar.GetActionLossOfControlCooldownInfo, slot)
    if not ok then return nil, true end
    return ReadLossOfControlState(info)
end

local function GetSpellLossOfControlState(spellID)
    if not C_Spell or type(C_Spell.GetSpellLossOfControlCooldownInfo) ~= "function" then
        return false, false
    end
    local ok, info = pcall(C_Spell.GetSpellLossOfControlCooldownInfo, spellID)
    if not ok then return nil, true end
    return ReadLossOfControlState(info)
end

-- Returns ready, remaining, readinessRestricted, timingRestricted, needsPoll,
-- hardRestricted. hardRestricted is reserved for a restricted Loss of Control
-- state and can never be overridden by optimistic cooldown compatibility.
local function GetActionReadiness(slot, gcdOnlyHint)
    if not C_ActionBar or type(slot) ~= "number" then
        return nil, nil, true, true, true, false
    end

    local locBlocked, locRestricted = GetActionLossOfControlState(slot)
    if locBlocked then
        return false, nil, false, false, false, false
    elseif locRestricted then
        return nil, nil, true, true, true, true
    end

    if type(C_ActionBar.GetActionCharges) == "function" then
        local ok, info = pcall(C_ActionBar.GetActionCharges, slot)
        if ok then
            local ready, remaining, readinessRestricted, timingRestricted, isCharge = ReadChargeInfo(
                info,
                C_ActionBar.GetActionChargeDuration,
                slot
            )
            if isCharge then
                local needsPoll = ready ~= true and remaining == nil
                    and (readinessRestricted or timingRestricted)
                return ready, remaining, readinessRestricted, timingRestricted, needsPoll, false
            end
        end
    end

    local durationTimingRestricted = false
    if type(C_ActionBar.GetActionCooldownDuration) == "function" then
        local ok, duration = pcall(C_ActionBar.GetActionCooldownDuration, slot, true)
        if ok then
            local ready, remaining, timingRestricted, hasDuration = ReadDuration(duration)
            durationTimingRestricted = timingRestricted
            if hasDuration and ready ~= nil then
                local needsPoll = ready == false and remaining == nil and timingRestricted
                return ready, remaining, false, timingRestricted, needsPoll, false
            end
        end
    end

    if type(C_ActionBar.GetActionCooldown) == "function" then
        local ok, info = pcall(C_ActionBar.GetActionCooldown, slot)
        if ok then
            local ready, readinessRestricted = ReadCooldownStatus(info, gcdOnlyHint)
            if ready ~= nil then
                local timingRestricted = ready == false and durationTimingRestricted
                return ready, nil, false, timingRestricted, timingRestricted, false
            end
            if readinessRestricted then
                return nil, nil, true, durationTimingRestricted, true, false
            end
        end
    end

    return nil, nil, true, durationTimingRestricted, true, false
end

local function GetSpellReadiness(spellID, gcdOnlyHint)
    if not C_Spell or type(spellID) ~= "number" then
        return nil, nil, true, true, true, false
    end

    local locBlocked, locRestricted = GetSpellLossOfControlState(spellID)
    if locBlocked then
        return false, nil, false, false, false, false
    elseif locRestricted then
        return nil, nil, true, true, true, true
    end

    if type(C_Spell.GetSpellCharges) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
        if ok then
            local ready, remaining, readinessRestricted, timingRestricted, isCharge = ReadChargeInfo(
                info,
                C_Spell.GetSpellChargeDuration,
                spellID
            )
            if isCharge then
                local needsPoll = ready ~= true and remaining == nil
                    and (readinessRestricted or timingRestricted)
                return ready, remaining, readinessRestricted, timingRestricted, needsPoll, false
            end
        end
    end

    local durationTimingRestricted = false
    if type(C_Spell.GetSpellCooldownDuration) == "function" then
        local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
        if ok then
            local ready, remaining, timingRestricted, hasDuration = ReadDuration(duration)
            durationTimingRestricted = timingRestricted
            if hasDuration and ready ~= nil then
                local needsPoll = ready == false and remaining == nil and timingRestricted
                return ready, remaining, false, timingRestricted, needsPoll, false
            end
        end
    end

    if type(C_Spell.GetSpellCooldown) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok then
            local ready, readinessRestricted = ReadCooldownStatus(info, gcdOnlyHint)
            if ready ~= nil then
                local timingRestricted = ready == false and durationTimingRestricted
                return ready, nil, false, timingRestricted, timingRestricted, false
            end
            if readinessRestricted then
                return nil, nil, true, durationTimingRestricted, true, false
            end
        end
    end

    return nil, nil, true, durationTimingRestricted, true, false
end

local function GetPetReadiness(slot)
    if type(GetPetActionCooldown) ~= "function" or type(slot) ~= "number" then
        return nil, nil, true, true, true, false
    end

    local ok, startTime, duration, enabled = pcall(GetPetActionCooldown, slot)
    if not ok
        or not IG.CanAccess(startTime)
        or not IG.CanAccess(duration)
        or not IG.CanAccess(enabled)
    then
        return nil, nil, true, true, true, false
    end

    if type(startTime) ~= "number" or type(duration) ~= "number" then
        return nil, nil, true, true, true, false
    end
    if enabled == 0 or enabled == false then
        return false, nil, false, false, false, false
    end
    if startTime <= 0 or duration <= 0 then
        return true, 0, false, false, false, false
    end

    local remaining = (startTime + duration) - IG:Now()
    if remaining <= 0 then
        return true, 0, false, false, false, false
    end
    return false, remaining, false, false, false, false
end

local function StoreCachedResult(cache, sourceID, generation, ...)
    local entry = cache[sourceID]
    if not entry then
        entry = {}
        cache[sourceID] = entry
    end

    entry.generation = generation
    entry.ready,
    entry.remaining,
    entry.readinessRestricted,
    entry.timingRestricted,
    entry.needsPoll,
    entry.hardRestricted = ...

    return ...
end

function Cooldown:GetCachedReadiness(sourceKind, sourceID, gcdOnlyHint)
    local cache = self.cache[sourceKind]
    if not cache or type(sourceID) ~= "number" then
        return nil, nil, true, true, true, false
    end

    local entry = cache[sourceID]
    if entry and entry.generation == self.generation then
        return entry.ready,
            entry.remaining,
            entry.readinessRestricted,
            entry.timingRestricted,
            entry.needsPoll,
            entry.hardRestricted
    end

    local ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted
    if sourceKind == "action" then
        ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
            GetActionReadiness(sourceID, gcdOnlyHint)
    elseif sourceKind == "spell" then
        ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
            GetSpellReadiness(sourceID, gcdOnlyHint)
    elseif sourceKind == "pet" then
        ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
            GetPetReadiness(sourceID)
    else
        ready, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
            nil, nil, true, true, true, false
    end

    return StoreCachedResult(
        cache,
        sourceID,
        self.generation,
        ready,
        remaining,
        readinessRestricted,
        timingRestricted,
        needsPoll,
        hardRestricted
    )
end

function Cooldown:RefreshAbility(ability)
    if not ability then return false end

    local rawReady, remaining, readinessRestricted, timingRestricted, needsPoll, hardRestricted =
        self:GetCachedReadiness(ability.sourceKind, ability.sourceID, self.gcdHints[ability.key] == true)

    hardRestricted = hardRestricted == true

    local ready
    if hardRestricted then
        ready = false
    elseif rawReady == true then
        ready = true
    elseif rawReady == false then
        ready = false
    elseif readinessRestricted and IG.DB.optimisticRestrictedCooldown then
        ready = true
    else
        ready = false
    end

    local restricted = readinessRestricted == true or timingRestricted == true or hardRestricted
    local newDeadline = nil
    if not ready and type(remaining) == "number" and remaining > 0 then
        newDeadline = IG:Now() + remaining
    end
    needsPoll = needsPoll == true and newDeadline == nil

    local deadlineChanged
    if type(ability.deadline) == "number" and type(newDeadline) == "number" then
        deadlineChanged = math_abs(ability.deadline - newDeadline) > 0.05
    else
        deadlineChanged = ability.deadline ~= newDeadline
    end

    local changed = ability.ready ~= ready
        or ability.restricted ~= restricted
        or ability.readinessRestricted ~= (readinessRestricted == true)
        or ability.timingRestricted ~= (timingRestricted == true)
        or ability.hardRestricted ~= hardRestricted
        or ability.needsPoll ~= needsPoll
        or deadlineChanged

    ability.ready = ready
    ability.restricted = restricted
    ability.hasEvaluation = true
    ability.evaluatedGeneration = self.generation
    ability.sourceChanged = false
    ability.readinessRestricted = readinessRestricted == true
    ability.timingRestricted = timingRestricted == true
    ability.hardRestricted = hardRestricted
    ability.needsPoll = needsPoll
    if deadlineChanged then ability.deadline = newDeadline end

    for record in pairs(ability.records) do
        record.ready = ready
        record.restrictedCooldown = restricted
        record.hardRestrictedCooldown = hardRestricted
        record.deadline = ability.deadline
    end

    if readinessRestricted then IG:BumpStat("cooldown.readinessRestricted") end
    if timingRestricted then IG:BumpStat("cooldown.timingRestricted") end
    if hardRestricted then IG:BumpStat("cooldown.lossOfControlRestricted") end
    return changed
end

local function CaptureSourceGCDHint(sourceKind, sourceID)
    local fn
    if sourceKind == "action" then
        fn = C_ActionBar and C_ActionBar.GetActionCooldown
    elseif sourceKind == "spell" then
        fn = C_Spell and C_Spell.GetSpellCooldown
    else
        return false
    end
    if type(fn) ~= "function" or type(sourceID) ~= "number" then return false end

    local ok, info = pcall(fn, sourceID)
    if not ok or not IG.CanAccess(info) or info == nil then return false end
    local active, activeKnown = IG:ReadMember(info, "isActive")
    local onGCD, onGCDKnown = IG:ReadMember(info, "isOnGCD")
    return activeKnown and onGCDKnown and active == true and onGCD == true
end

function Cooldown:ClearGCDHints()
    IG:WipeMap(self.gcdHints)
end

function Cooldown:CaptureGCDHints()
    self:ClearGCDHints()
    for _, ability in pairs(IG.AbilityStates) do
        if ability.sourceKind ~= nil and next(ability.records) ~= nil then
            if CaptureSourceGCDHint(ability.sourceKind, ability.sourceID) then
                self.gcdHints[ability.key] = true
            end
        end
    end
end

function Cooldown:HasPendingPoll()
    for _, ability in pairs(IG.AbilityStates) do
        if ability.needsPoll == true and next(ability.records) ~= nil then
            return true
        end
    end
    return false
end

function Cooldown:RefreshAll()
    self.generation = self.generation + 1
    if self.generation > 2147483000 then
        self.generation = 1
        IG:WipeMap(self.cache.action)
        IG:WipeMap(self.cache.spell)
        IG:WipeMap(self.cache.pet)
    end

    IG:BumpStat(next(self.gcdHints) ~= nil and "cooldown.spellEventPasses" or "cooldown.otherPasses")

    local changed = false
    for _, ability in pairs(IG.AbilityStates) do
        if ability.sourceKind ~= nil and next(ability.records) ~= nil then
            if self:RefreshAbility(ability) then changed = true end
            IG:BumpStat("cooldown.abilitiesEvaluated")
        end
    end

    self:ClearGCDHints()

    if changed and IG.Glow then
        IG.Glow:RefreshAll()
    elseif IG.Glow then
        IG.Glow:UpdateRuntimeDriver()
    end
end
