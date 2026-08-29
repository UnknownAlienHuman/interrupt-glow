local IG = _G.InterruptGlow
if not IG or not IG.Cooldown then return end

local Cooldown = IG.Cooldown

-- `isOnGCD == true` means the source is considered to be on the global
-- cooldown. It does not prove that an active cooldown is *only* the GCD. A
-- simultaneous personal cooldown can therefore be misclassified as ready if a
-- generic GCD hint is allowed to override `isActive == true`.
--
-- Interrupt Glow is not a GCD analyzer. Its primary readiness source is the
-- explicit duration API with ignoreGlobalCooldown=true. If that duration is
-- inaccessible, the safe fallback is fail-closed; never convert `isOnGCD` into
-- a positive readiness answer.
local originalGetCachedReadiness = Cooldown.GetCachedReadiness
function Cooldown:GetCachedReadiness(sourceKind, sourceID, _gcdOnlyHint)
    return originalGetCachedReadiness(self, sourceKind, sourceID, false)
end

-- Keep compatibility with callers and older code, but stop collecting GCD
-- hints entirely. This avoids duplicate cooldown API reads inside
-- SPELL_UPDATE_COOLDOWN and prevents accidental future use as readiness proof.
function Cooldown:CaptureGCDHints()
    self:ClearGCDHints()
end

IG:RegisterModule("GCDSafetyPolicy", {
    ignoresGlobalCooldownInDurationAPI = true,
    treatsIsOnGCDAsReadinessProof = false,
})
