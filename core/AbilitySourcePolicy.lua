local IG = _G.InterruptGlow
if not IG or not IG.Cooldown or not IG.Buttons then return end

local Cooldown = IG.Cooldown
local Buttons = IG.Buttons
local pairs = pairs
local type = type
local next = next

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
        record.hardRestrictedCooldown = false
        record.readinessPending = ability.readinessPending
    end
end

local function ApplySource(ability, sourceKind, sourceID, scheduleRefresh)
    if ability.sourceKind == sourceKind and ability.sourceID == sourceID then
        return false
    end

    ability.sourceKind = sourceKind
    ability.sourceID = sourceID
    ability.sourceChanged = true
    InvalidateForSourceChange(ability)
    IG:BumpStat("cooldown.abilitySourceChanged")

    if scheduleRefresh and sourceKind ~= nil then
        IG:MarkCooldownDirty(false)
    end
    return true
end

local function EnsureCurrentSource(ability)
    if not ability then return false end

    local sourceKind, sourceID = SelectBestSource(ability)
    return ApplySource(ability, sourceKind, sourceID, false)
end

-- Replace the earlier keep-current shortcut in Buttons.lua. A still-bound spell
-- or pet source must not block an immediate upgrade when a current action source
-- appears. Conversely, removing the chosen action must fall back immediately.
function Buttons:RebuildAbilitySource(ability)
    if not ability then return false end

    local sourceKind, sourceID = SelectBestSource(ability)
    if sourceKind == nil then
        -- Preserve the last source/evaluation only while the canonical ability is
        -- fully dormant. Rapid macro unbind/rebind can then reuse state within the
        -- same cooldown generation without allocation or API churn.
        ability.dormant = true
        return false
    end

    ability.dormant = false
    return ApplySource(ability, sourceKind, sourceID, true)
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
    upgradesToHigherPrioritySource = true,
    ownsButtonSourceRebuild = true,
})
