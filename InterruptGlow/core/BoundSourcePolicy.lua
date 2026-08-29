local IG = _G.InterruptGlow
if not IG or not IG.Buttons or not IG.Cooldown then return end

local Buttons = IG.Buttons
local Cooldown = IG.Cooldown
local pairs = pairs
local type = type
local next = next

local VALID_SOURCE = {
    action = true,
    pet = true,
    spell = true,
}

local function HasRecords(ability)
    return ability ~= nil and next(ability.records or {}) ~= nil
end

local function HasEligibleSourceRecord(ability)
    for record in pairs(ability.records or {}) do
        if record.isInterrupt == true
            and VALID_SOURCE[record.sourceKind] == true
            and type(record.sourceID) == "number"
        then
            return true
        end
    end
    return false
end

local function FailClosed(ability, scheduleRefresh)
    local changed = ability.sourceKind ~= nil
        or ability.sourceID ~= nil
        or ability.ready ~= false
        or ability.restricted ~= true
        or ability.readinessRestricted ~= true
        or ability.timingRestricted ~= true
        or ability.hardRestricted ~= true
        or ability.needsPoll ~= false
        or ability.deadline ~= nil
        or ability.hasEvaluation ~= false
        or ability.readinessPending ~= true

    ability.sourceKind = nil
    ability.sourceID = nil
    ability.sourceChanged = true
    ability.dormant = false
    ability.hasEvaluation = false
    ability.evaluatedGeneration = nil
    ability.ready = false
    ability.deadline = nil
    ability.needsPoll = false
    ability.restricted = true
    ability.readinessRestricted = true
    ability.timingRestricted = true
    ability.hardRestricted = true
    ability.readinessPending = true

    for record in pairs(ability.records or {}) do
        record.ready = false
        record.deadline = nil
        record.restrictedCooldown = true
        record.hardRestrictedCooldown = true
        record.readinessPending = true
    end

    if changed then
        IG:BumpStat("cooldown.boundAbilityMissingSource")
        if scheduleRefresh then IG:MarkCooldownDirty(false) end
    end
    return changed
end

local originalRebuildAbilitySource = Buttons.RebuildAbilitySource
function Buttons:RebuildAbilitySource(ability)
    if HasRecords(ability) and not HasEligibleSourceRecord(ability) then
        return FailClosed(ability, true)
    end

    local changed = originalRebuildAbilitySource(self, ability)
    if changed and ability and ability.sourceKind ~= nil then
        ability.readinessRestricted = false
        ability.timingRestricted = false
    end
    return changed
end

local originalRefreshAbility = Cooldown.RefreshAbility
function Cooldown:RefreshAbility(ability)
    if HasRecords(ability) and not HasEligibleSourceRecord(ability) then
        FailClosed(ability, false)
    end
    return originalRefreshAbility(self, ability)
end

local originalRefreshAll = Cooldown.RefreshAll
function Cooldown:RefreshAll()
    for _, ability in pairs(IG.AbilityStates) do
        if HasRecords(ability) and not HasEligibleSourceRecord(ability) then
            FailClosed(ability, false)
        end
    end
    return originalRefreshAll(self)
end

IG:RegisterModule("BoundSourcePolicy", {
    boundRecordsWithoutSourceFailClosed = true,
    emptyAbilitiesRemainDormant = true,
})
