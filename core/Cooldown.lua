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
local GetSpellLossOfControlCooldown = _G.GetSpellLossOfControlCooldown
local pcall = pcall
local type = type
local pairs = pairs
local next = next
local math_abs = math.abs

local function SafeMethodCall(object, methodName, ...)
    if not object or type(object[methodName]) ~= "function" then
        return false, nil
    end
    local ok, value = pcall(object[methodName], object, ...)
    if not ok or not IG.CanAccess(value) then
        return false, nil
    end
    return true, value
end

local function ReadDuration(duration)
    if not IG.CanAccess(duration) then
        return nil, nil, true, true
    end
    if duration == nil then
        return nil, nil, false, false
    end

    local zeroKnown, isZero = SafeMethodCall(duration, "IsZero")
    if zeroKnown and type(isZero) == "boolean" then
        if isZero then
            return true, 0, false, true
        end

        local remainingKnown, remaining = SafeMethodCall(duration, "GetRemainingDuration")
        if remainingKnown and type(remaining) == "number" then
            if remaining <= 0 then return true, 0, false, true end
            return false, remaining, false, true
        end
        return false, nil, true, true
    end

    local remainingKnown, remaining = SafeMethodCall(duration, "GetRemainingDuration")
    if remainingKnown and type(remaining) == "number" then
        if remaining <= 0 then return true, 0, false, true end
        return false, remaining, false, true
    end
    return nil, nil, true, true
end

local function ReadCooldownStatus(info, gcdOnlyHint)
    if not IG.CanAccess(info) or info == nil then
        return nil, true
    end

    local isActive, activeKnown = IG:ReadMember(info, "isActive")
    if activeKnown and type(isActive) == "boolean" then
        if not isActive then return true, false end
        if gcdOnlyHint then return true, false end
        return false, false
    end
    return nil, true
end

-- Returns ready, remaining, readinessRestricted, timingRestricted, isCharge,
-- hardRestricted. Accessible nil is the documented non-charge result for the
-- spell API. An inaccessible charge payload is fundamentally different: the
-- addon cannot know whether the last charge is available, so ordinary cooldown
-- fallback must not be allowed to produce ready=true.
local function ReadChargeInfo(info, durationGetter, sourceID)
    if info == nil then
        return nil, nil, false, false, false, false
    end
    if not IG.CanAccess(info) then
        return nil, nil, true, true, true, true
    end

    local currentCharges, currentKnown = IG:ReadMember(info, "currentCharges")
    local maxCharges, maxKnown = IG:ReadMember(info, "maxCharges")
    local hasChargeShape = currentKnown or maxKnown
    if not hasChargeShape then
        return nil, nil, true, true, true, true
    end

    currentCharges = IG:AsNumber(currentCharges)
    maxCharges = IG:AsNumber(maxCharges)

    if currentCharges and currentCharges > 0 then
        return true, 0, false, false, true, false
    end

    if currentCharges == nil then
        return nil, nil, true, true, true, true
    end

    -- A structurally charge-shaped object with zero/invalid max charges is not a
    -- trustworthy non-charge sentinel. Fail closed rather than falling through
    -- to a normal cooldown that may be zero.
    if maxCharges == nil or maxCharges <= 0 then
        return nil, nil, true, true, true, true
    end

    local timingRestricted = false
    local remaining = nil

    if type(durationGetter) == "function" then
        local ok, duration = pcall(durationGetter, sourceID)
        if ok then
            local _ready, value, restricted = ReadDuration(duration)
            remaining = value
            timingRestricted = restricted
        else
            timingRestricted = true
        end
    else
        timingRestricted = true
    end

    -- currentCharges == 0 is exact not-ready evidence even when recharge timing
    -- is inaccessible. Polling is needed only when no accessible deadline exists.
    return false, remaining, false, timingRestricted, true, false
end

local function ReadLossOfControlState(info)
    if info == nil then
        return "clear"
    end
    if not IG.CanAccess(info) then
        -- LoC cooldown data is SecretWhenCooldownsRestricted. Inaccessibility is
        -- not proof that the action is free to use; optimistic cooldown mode must
        -- never bypass an unknown control-loss gate.
        return "restricted"
    end

    local isActive, activeKnown = IG:ReadMember(info, "isActive")
    local replaces, replacesKnown = IG:ReadMember(info, "shouldReplaceNormalCooldown")
    if not activeKnown or not replacesKnown then
        return "restricted"
    end
    if isActive == true or replaces == true then
        return "blocked"
    end
    if isActive == false and replaces == false then
        return "clear"
    end
    return "restricted"
end

local function GetActionLossOfControlState(slot)
    if C_ActionBar and type(C_ActionBar.GetActionLossOfControlCooldownInfo) == "function" then
        local ok, info = pcall(C_ActionBar.GetActionLossOfControlCooldownInfo, slot)
        if ok then return ReadLossOfControlState(info) end
        return "restricted"
    end
    return "clear"
end

local function GetSpellLossOfControlState(spellID)
    if type(GetSpellLossOfControlCooldown) == "function" then
        local ok, info = pcall(GetSpellLossOfControlCooldown, spellID)
        if ok then return ReadLossOfControlState(info) end
        return "restricted"
    end
    return "clear"
end

local function GetActionReadiness(slot, gcdOnlyHint)
    if not C_ActionBar then
        return nil, nil, true, true, false, true
    end

    local locState = GetActionLossOfControlState(slot)
    if locState == "blocked" then
        return false, nil, false, false, false, false
    end
    if locState == "restricted" then
        return nil, nil, true, true, false, true
    end

    if type(C_ActionBar.GetActionCharges) == "function" then
        local ok, info = pcall(C_ActionBar.GetActionCharges, slot)
        if not ok then
            return nil, nil, true, true, false, true
        end

        local ready, remaining, readinessRestricted, timingRestricted, isCharge, hardRestricted =
            ReadChargeInfo(info, C_ActionBar.GetActionChargeDuration, slot)
        if hardRestricted then
            return nil, nil, true, true, false, true
        end
        if isCharge then
            local needsPoll = ready ~= true and remaining == nil
                and (readinessRestricted or timingRestricted)
            return ready, remaining, readinessRestricted, timingRestricted, needsPoll, false
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
        else
            durationTimingRestricted = true
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
    if not C_Spell then
        return nil, nil, true, true, false, true
    end

    local locState = GetSpellLossOfControlState(spellID)
    if locState == "blocked" then
        return false, nil, false, false, false, false
    end
    if locState == "restricted" then
        return nil, nil, true, true, false, true
    end

    if type(C_Spell.GetSpellCharges) == "function" then
        local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
        if not ok then
            return nil, nil, true, true, false, true
        end

        local ready, remaining, readinessRestricted, timingRestricted, isCharge, hardRestricted =
            ReadChargeInfo(info, C_Spell.GetSpellChargeDuration, spellID)
        if hardRestricted then
            return nil, nil, true, true, false, true
        end
        if isCharge then
            local needsPoll = ready ~= true and remaining == nil
                and (readinessRestricted or timingRestricted)
            return ready, remaining, readinessRestricted, timingRestricted, needsPoll, false
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
        else
            durationTimingRestricted = true
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
        return nil, nil, true, true, false, true
    end

    local ok, startTime, duration, enabled = pcall(GetPetActionCooldown, slot)
    if not ok
        or not IG.CanAccess(startTime)
        or not IG.CanAccess(duration)
        or not IG.CanAccess(enabled)
    then
        return nil, nil, true, true, false, true
    end

    if type(startTime) ~= "number" or type(duration) ~= "number" then
        return nil, nil, true, true, false, true
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
        -- A missing/invalid physical source is not an ordinary restricted
        -- cooldown. It cannot be made ready by optimistic compatibility mode.
        return nil, nil, true, true, false, true
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
            nil, nil, true, true, false, true
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

    local wasReadinessPending = ability.readinessPending == true
    local changed = wasReadinessPending
        or ability.ready ~= ready
        or ability.restricted ~= restricted
        or ability.readinessRestricted ~= (readinessRestricted == true)
        or ability.timingRestricted ~= (timingRestricted == true)
        or ability.hardRestricted ~= hardRestricted
        or ability.needsPoll ~= needsPoll
        or deadlineChanged

    ability.ready = ready
    ability.restricted = restricted
    ability.readinessRestricted = readinessRestricted == true
    ability.timingRestricted = timingRestricted == true
    ability.hardRestricted = hardRestricted
    ability.needsPoll = needsPoll
    ability.deadline = newDeadline
    ability.hasEvaluation = true
    ability.evaluatedGeneration = self.generation
    ability.sourceChanged = false
    ability.readinessPending = false

    for record in pairs(ability.records) do
        record.ready = ready
        record.restrictedCooldown = restricted
        record.hardRestrictedCooldown = hardRestricted
        record.deadline = newDeadline
        record.readinessPending = false
    end

    return changed
end

function Cooldown:ClearGCDHints()
    IG:WipeMap(self.gcdHints)
end

function Cooldown:CaptureGCDHints()
    self:ClearGCDHints()
end

function Cooldown:RefreshAll()
    self.generation = self.generation + 1
    if self.generation > 2147483000 then
        self.generation = 1
        IG:WipeMap(self.cache.action)
        IG:WipeMap(self.cache.spell)
        IG:WipeMap(self.cache.pet)
    end

    IG:BumpStat("cooldown.otherPasses")

    local changed = false
    for _, ability in pairs(IG.AbilityStates) do
        if ability.sourceKind ~= nil and next(ability.records) ~= nil then
            if self:RefreshAbility(ability) then changed = true end
            IG:BumpStat("cooldown.abilitiesEvaluated")
        end
    end

    if changed and IG.Glow then
        IG.Glow:RefreshAll()
    elseif IG.Glow then
        IG.Glow:UpdateRuntimeDriver()
    end
end
