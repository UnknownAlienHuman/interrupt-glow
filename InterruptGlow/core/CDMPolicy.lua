local IG = _G.InterruptGlow
if not IG or not IG.Buttons or not IG.Data or not IG.CDM then return end

local Buttons = IG.Buttons
local Data = IG.Data
local type = type

-- Cooldown Viewer callbacks capture the latest pooled-item identity into
-- record.cdmCanonicalSpellID. Reconciliation must consume that snapshot rather
-- than reading the frame again after reset/reuse may already have occurred.
function Buttons:ResolveCDM(record)
    if not IG.DB.cdm or not record then return false end

    local observedSpellID = record.cdmCanonicalSpellID
    if type(observedSpellID) ~= "number" then return false end

    -- Revalidate against the current specialization/runtime proof. The cached
    -- number is ordinary identity, not a permanent cross-spec whitelist.
    local canonicalSpellID = Data:GetCanonicalSpellID(observedSpellID, "spell")
    if not canonicalSpellID then return false end

    return true, "spell", canonicalSpellID, observedSpellID, canonicalSpellID
end

-- Active pool refresh after a specialization/talent rebuild is owned by
-- RuntimeInterruptPolicy. Its order is authoritative action slots -> active CDM
-- pools -> secondary records, avoiding both duplicate enumeration and a pre-seed
-- nil identity race.
IG:RegisterModule("CDMPolicy", {
    usesCapturedPoolIdentity = true,
    specRefreshOwnedByRuntimeInterruptPolicy = true,
})
