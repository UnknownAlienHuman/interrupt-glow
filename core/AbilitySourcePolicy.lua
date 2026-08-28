local IG = _G.InterruptGlow
if not IG or not IG.Cooldown then return end

local Cooldown = IG.Cooldown
local pairs = pairs
local type = type

-- A canonical interrupt can be represented by several physical buttons:
-- current action slots, a pet action, ButtonForge/direct spell, and one or more
-- Cooldown Viewer items. Readiness remains shared, but the API source must be a
-- record that is still bound to the ability. Prefer the current resolved action
-- surface, then the direct pet surface, then spell/CDM fallback.
local SOURCE_PRIORITY = {
    action = 300,
    pet = 200,
    spell = 100,
}

local function IsEligibleRecord(record)
    return record ~= nil
        and record.isInterrupt == true
        and type(record.sourceKind) == "string"
        and SOURCE_PRIORITY[record.sourceKind] ~= nil
        and type(record.sourceID) == "number"
end

local function IsBetterSource(record, bestKind, bestID)
    if not bestKind then return true end

    local priority = SOURCE_PRIORITY[record.sourceKind]
    local bestPriority = SOURCE_PRIORITY[bestKind]
    if priority ~= bestPriority then return priority > bestPriority end

    -- Stable deterministic choice among duplicate buttons of one source kind.
    return record.sourceID < bestID
end

local function HasCurrentSource(ability)
    if type(ability.sourceKind) ~= "string" or type(ability.sourceID) ~= "number" then
        return false
    end

    for record in pairs(ability.records or {}) do
        if IsEligibleRecord(record)
            and record.sourceKind == ability.sourceKind
            and record.sourceID == ability.sourceID
        then
            return true
        end
    end
    return false
end

local function SelectBestSource(ability)
    local bestKind, bestID
    for record in pairs(ability.records or {}) do
        if IsEligibleRecord(record) and IsBetterSource(record, bestKind, bestID) then
            bestKind = record.sourceKind
            bestID = record.sourceID
        end
    end
    return bestKind, bestID
end

local function InvalidateForSourceChange(ability)
    ability.hasEvaluation = false
    ability.evaluatedGeneration = nil
    ability.ready = false
    ability.deadline = nil
    ability.needsPoll = false
    ability.restricted = false
    ability.hardRestricted = false
    ability.readinessPending = next(ability.records or {}) ~= nil

    for record in pairs(ability.records or {}) do
        record.ready = false
        record.deadline = nil
        record.restrictedCooldown = false
        record.readinessPending = ability.readinessPending
    end
end

local function EnsureCurrentSource(ability)
    if not ability then return false end

    -- Keep an existing source while at least one current record still owns it.
    -- This avoids source churn when duplicate bars are created or reordered.
    if HasCurrentSource(ability) then return false end

    local sourceKind, sourceID = SelectBestSource(ability)
    if ability.sourceKind == sourceKind and ability.sourceID == sourceID then
        return false
    end

    ability.sourceKind = sourceKind
    ability.sourceID = sourceID
    InvalidateForSourceChange(ability)
    IG:BumpStat("cooldown.abilitySourceChanged")
    return true
end

local originalRefreshAbility = Cooldown.RefreshAbility
function Cooldown:RefreshAbility(ability)
    EnsureCurrentSource(ability)
    return originalRefreshAbility(self, ability)
end

IG:RegisterModule("AbilitySourcePolicy", {
    priority = SOURCE_PRIORITY,
    EnsureCurrentSource = EnsureCurrentSource,
    sharedReadinessRequiresBoundSource = true,
})
