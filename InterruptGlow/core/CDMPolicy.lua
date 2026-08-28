local IG = _G.InterruptGlow
if not IG or not IG.Buttons or not IG.Data or not IG.CDM then return end

local Buttons = IG.Buttons
local Data = IG.Data
local CDM = IG.CDM
local type = type

-- Cooldown Viewer hook callbacks already captured the latest current-spec
-- canonical identity into record.cdmCanonicalSpellID. Reconciliation must use
-- that captured value rather than reading the pooled frame again on the next
-- frame: reset and reuse may happen within one Blizzard layout stack.
function Buttons:ResolveCDM(record)
    if not IG.DB.cdm or not record then return false end

    local observedSpellID = record.cdmCanonicalSpellID
    if type(observedSpellID) ~= "number" then return false end

    -- Revalidate against the current specialization. The cached value is an
    -- ordinary identity snapshot, not a permanent cross-spec whitelist.
    local canonicalSpellID = Data:GetCanonicalSpellID(observedSpellID, "spell")
    if not canonicalSpellID then return false end

    return true, "spell", canonicalSpellID, observedSpellID, canonicalSpellID
end

-- A specialization/talent rebuild can make an already-active CDM item become
-- relevant or irrelevant without changing its physical pooled frame. Refresh
-- only the two active viewer pools after Data has installed the new current-spec
-- registry. This is a rare bounded lifecycle pass, never a hot-path tree scan.
local originalRefreshActiveSpec = Data.RefreshActiveSpec
function Data:RefreshActiveSpec(...)
    local specID, changed = originalRefreshActiveSpec(self, ...)

    if CDM.attached and IG.DB.cdm then
        CDM:ObserveExistingItems()
    end

    return specID, changed
end

IG:RegisterModule("CDMPolicy", {
    usesCapturedPoolIdentity = true,
    refreshesActiveItemsAfterSpecData = true,
})
