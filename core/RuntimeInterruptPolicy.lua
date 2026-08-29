local IG = _G.InterruptGlow
if not IG or not IG.Data or not IG.Buttons then return end

local Data = IG.Data
local Buttons = IG.Buttons
local type = type
local pairs = pairs

local function PositiveNumber(value)
    return type(value) == "number" and value > 0
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
    self.runtimeProofRevision = (self.runtimeProofRevision or 0) + 1
    return originalRefreshActiveSpec(self, ...)
end

local originalLearnRuntimeInterrupt = Data.LearnRuntimeInterrupt
function Data:LearnRuntimeInterrupt(spellID)
    local previous = type(spellID) == "number" and self.runtimeInterrupts[spellID] or nil
    local canonicalSpellID = originalLearnRuntimeInterrupt(self, spellID)

    if canonicalSpellID and previous ~= canonicalSpellID then
        self.runtimeProofRevision = (self.runtimeProofRevision or 0) + 1
        IG:BumpStat("data.runtimeInterruptFamiliesChanged")

        -- A single action button can discover a new hotfix/talent interrupt after
        -- direct-spell or CDM copies were already reconciled. Schedule one bounded
        -- full rebind. A full two-phase rebuild may therefore receive one harmless
        -- follow-up pass, but no mutable "seed active" flag can be left stuck by a
        -- Lua error and suppress future propagation permanently.
        IG:MarkAllButtonsDirty()
    end

    return canonicalSpellID
end

-- Raw presence in runtimeInterrupts is not enough after a configuration change;
-- current spellbook/base/override availability must still validate the family.
function Data:MatchesCurrentInterrupt(spellID)
    if not IG.CanAccess(spellID) or type(spellID) ~= "number" then
        return false
    end

    local cached = self.cooldownSpellMatchCache[spellID]
    if cached ~= nil then return cached end

    local matches = self.activeInterrupts[spellID] ~= nil
        or self:GetCanonicalSpellID(spellID, "spell") ~= nil
    self.cooldownSpellMatchCache[spellID] = matches
    return matches
end

-- Full registry rebuilds are rare lifecycle operations. Seed runtime-only
-- families from authoritative action slots first, then reconcile pet/direct/CDM
-- copies. This removes dependence on weak-table iteration order without adding
-- work to the ordinary single-button mouseover path.
function Buttons:ReconcileAll()
    for _, record in pairs(IG.ObservedButtons) do
        if RecordHasActionSlot(record) then
            self:ReconcileRecord(record)
            IG:BumpStat("buttons.reconciled")
        end
    end

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
    propagatesNewRuntimeFamilies = true,
    revalidatesCooldownEventMatches = true,
    avoidsStickySeedState = true,
})
