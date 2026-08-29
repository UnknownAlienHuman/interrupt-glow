local IG = _G.InterruptGlow
if not IG or not IG.Data or not IG.Buttons then return end

local Data = IG.Data
local Buttons = IG.Buttons
local type = type
local pairs = pairs

local NEGATIVE_MATCH_LIMIT = 128
Data.negativeCooldownSpellMatches = Data.negativeCooldownSpellMatches or {}
Data.negativeCooldownSpellMatchCount = Data.negativeCooldownSpellMatchCount or 0

local function PositiveNumber(value)
    return type(value) == "number" and value > 0
end

local function ClearNegativeMatches(self)
    IG:WipeMap(self.negativeCooldownSpellMatches)
    self.negativeCooldownSpellMatchCount = 0
end

local function RecordHasActionSlot(record)
    if not record or record.adapter == "pet"
        or record.adapter == "cdm"
        or record.adapter == "buttonforge"
    then
        return false
    end

    if PositiveNumber(record.labSlot) or PositiveNumber(record.dominosSlot) then
        return true
    end

    local button = record.button
    local stateType, stateTypeKnown = IG:ReadMember(button, "_state_type")
    if stateTypeKnown and stateType == "action" then
        local stateAction, stateActionKnown = IG:ReadMember(button, "_state_action")
        if stateActionKnown and PositiveNumber(IG:AsNumber(stateAction)) then
            return true
        end
    end

    local action, actionKnown = IG:ReadMember(button, "action")
    return actionKnown and PositiveNumber(IG:AsNumber(action))
end

local originalRefreshActiveSpec = Data.RefreshActiveSpec
function Data:RefreshActiveSpec(...)
    -- Runtime action feedback proves an interrupt only for the current spell,
    -- talent and PvP configuration. Clear it before every coalesced registry
    -- rebuild; the action-slot seed pass below restores still-valid families.
    IG:WipeMap(self.runtimeInterrupts)
    ClearNegativeMatches(self)
    self.runtimeProofRevision = (self.runtimeProofRevision or 0) + 1
    return originalRefreshActiveSpec(self, ...)
end

local originalLearnRuntimeInterrupt = Data.LearnRuntimeInterrupt
function Data:LearnRuntimeInterrupt(spellID)
    local previous = type(spellID) == "number" and self.runtimeInterrupts[spellID] or nil
    local canonicalSpellID = originalLearnRuntimeInterrupt(self, spellID)

    if canonicalSpellID and previous ~= canonicalSpellID then
        -- A newly proven family can invalidate an earlier negative alias result.
        -- The negative cache is tiny and cheap to rebuild from later events.
        ClearNegativeMatches(self)
        self.runtimeProofRevision = (self.runtimeProofRevision or 0) + 1
        IG:BumpStat("data.runtimeInterruptFamiliesChanged")

        -- A single action button can discover a new hotfix/talent interrupt after
        -- direct-spell or CDM copies were already reconciled. Schedule one bounded
        -- full rebind. No mutable "seed active" flag can remain stuck after an
        -- unrelated Lua error and suppress later propagation.
        IG:MarkAllButtonsDirty()
    end

    return canonicalSpellID
end

-- Positive matches remain in the authoritative spec/runtime cache. Negative
-- unrelated spell IDs use a separate bounded cache so a long session cannot
-- accumulate every cooldown event ID until the next specialization change.
function Data:MatchesCurrentInterrupt(spellID)
    if not IG.CanAccess(spellID) or type(spellID) ~= "number" then
        return false
    end

    if self.cooldownSpellMatchCache[spellID] == true then return true end

    local matches = self.activeInterrupts[spellID] ~= nil
        or self:GetCanonicalSpellID(spellID, "spell") ~= nil
    if matches then
        self.cooldownSpellMatchCache[spellID] = true
        self.negativeCooldownSpellMatches[spellID] = nil
        return true
    end

    if self.negativeCooldownSpellMatches[spellID] == true then return false end

    if self.negativeCooldownSpellMatchCount >= NEGATIVE_MATCH_LIMIT then
        ClearNegativeMatches(self)
        IG:BumpStat("data.negativeCooldownMatchCacheResets")
    end
    self.negativeCooldownSpellMatches[spellID] = true
    self.negativeCooldownSpellMatchCount = self.negativeCooldownSpellMatchCount + 1
    return false
end

local function RefreshActiveCDMIdentities()
    local cdm = IG.CDM
    if not cdm or cdm.attached ~= true or not IG.DB or IG.DB.cdm ~= true then
        return
    end
    if type(cdm.ObserveExistingItems) == "function" then
        cdm:ObserveExistingItems()
        IG:BumpStat("cdm.postActionSeedRefreshes")
    end
end

-- Full registry rebuilds are rare lifecycle operations. Seed runtime-only
-- families from authoritative action slots first, refresh the two active CDM
-- pools against those newly proven families, then reconcile all secondary
-- copies. This removes weak-table iteration and CDM callback order dependence
-- without adding work to the ordinary single-button mouseover path.
function Buttons:ReconcileAll()
    for _, record in pairs(IG.ObservedButtons) do
        if RecordHasActionSlot(record) then
            self:ReconcileRecord(record)
            IG:BumpStat("buttons.reconciled")
        end
    end

    RefreshActiveCDMIdentities()

    for _, record in pairs(IG.ObservedButtons) do
        if not RecordHasActionSlot(record) then
            self:ReconcileRecord(record)
            IG:BumpStat("buttons.reconciled")
        end
    end
end

IG:RegisterModule("RuntimeInterruptPolicy", {
    clearsProofOnRegistryRebuild = true,
    actionSlotsSeedBeforeSecondaryCopies = true,
    refreshesCDMAfterActionSeed = true,
    propagatesNewRuntimeFamilies = true,
    revalidatesCooldownEventMatches = true,
    negativeMatchLimit = NEGATIVE_MATCH_LIMIT,
    avoidsStickySeedState = true,
})
