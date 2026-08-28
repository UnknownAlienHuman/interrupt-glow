# Interrupt Glow 1.1 release checklist

## Static implementation

- [x] Remove automatic action-slot, frame, nameplate, macro-body and Cooldown Viewer tree scans.
- [x] Use current action feedback and `C_ActionBar.IsInterruptAction` for slot-backed classification.
- [x] Deduplicate native/LAB conditional-macro feedback before frame-batched reconciliation.
- [x] Use callback-handle lifecycle for native EventRegistry registration when supported.
- [x] Add current 12.1.0 per-spec interrupt data, reviewed PvP exceptions and direct pet aliases.
- [x] Defer gameplay/provider startup to `PLAYER_LOGIN` and verified late-load surfaces.
- [x] Track only fixed `target` and `focus` with unit-vararg `RegisterUnitEvent` calls.
- [x] Route inaccessible `notInterruptible` directly to `SetAlphaFromBoolean(..., 0, 255)` without storage/logging/readback/pcall.
- [x] Share readiness per canonical ability and make readiness evaluation on-demand.
- [x] Fail closed on inaccessible LoC and action/spell/pet usability.
- [x] Prevent stale glow/countdown with `readinessPending`.
- [x] Ignore GCD through duration API `ignoreGlobalCooldown=true`.
- [x] Prevent `isOnGCD` or `UNIT_SPELLCAST_SUCCEEDED` from proving positive readiness.
- [x] Add conservative focused GCD policy/test.
- [x] Add Cooldown Viewer pooled lifecycle and defer hook-stack reconciliation to one dirty record.
- [x] Add explicit `SetOnUpdateMode` worker policy: RunOnce/RunAlways/Disabled.
- [x] Ensure all idle workers are explicitly Disabled after construction and after work settles.
- [x] Rebuild SavedVariables into strict schema 3 and drop unknown/legacy/runtime keys.
- [x] Preserve dormant ability state during same-spec macro churn and prune/reset caches on real spec changes.
- [x] Keep internal counters dormant outside debug/capture.
- [x] Add build/context/provider/worker/policy/secrecy/readiness/profiler runtime evidence.
- [x] Track active `WOWUI-2026-005` and implement event-authoritative channel/empower stop handling.
- [x] Suppress stale `UnitChannelInfo` snapshots until real start or unit-identity reset.
- [x] Ignore delayed stop events whose NeverSecret `castBarID` belongs to an older cast.
- [x] Keep unconfirmed `SPELL_SECRECY_CHANGED` out of runtime registrations.
- [x] Keep GitHub Actions workflows absent.

## Fresh local checks before merge

- [ ] `texlua tests/check_syntax.lua .`
- [ ] `python tests/static_checks.py`
- [ ] `texlua tests/mock_wow.lua .`
- [ ] `texlua tests/cdm_toggle.lua .`
- [ ] `texlua tests/runtime_probe.lua .`
- [ ] `texlua tests/native_callback_handles.lua .`
- [ ] `texlua tests/channel_guard.lua .`
- [ ] `texlua tests/shared_worker.lua .`
- [ ] `texlua tests/glow_worker.lua .`
- [ ] `texlua tests/cache_policy.lua .`
- [x] `texlua tests/gcd_safety.lua .` — focused current-blob reconstruction passed in the audit runtime.
- [x] `texlua tests/cache_policy.lua .` — focused current-blob reconstruction passed in the audit runtime.
- [ ] Confirm `.github/workflows` remains absent on final tree.
- [ ] Inspect final PR patch after all fixes; do not rely on an older report.

## Required live-client attribution matrix

Run equal-duration/equal-input captures for:

- [ ] default Blizzard UI with third-party addons disabled;
- [ ] Interrupt Glow only;
- [ ] Interrupt Glow plus required action-bar provider;
- [ ] normal full addon stack.

Record build, instance, combat/restriction state, visible nameplate count, macro, provider versions, FPS, taint/errors, worker state, SavedVariables schema and complete capture report.

## Required functional live tests

- [ ] Quick Heal `[@mouseover,help][]`: friendly hover and hostile/nameplate hover.
- [ ] Conditional heal/interrupt macro changes in combat.
- [ ] No interrupt currently on bars.
- [ ] Target/focus acquired mid-cast.
- [ ] Restricted Mythic+, raid, arena and battleground contexts.
- [ ] Page, stance, form, stealth, vehicle and override changes.
- [ ] Bartender, ElvUI and Dominos current releases.
- [ ] ButtonForge direct, cleared and conditional macro buttons.
- [ ] Warlock Felhunter/Felguard, sacrifice, Command Demon and Call Felhunter.
- [ ] Protection Warrior Pummel plus Disrupting Shout.
- [ ] Cooldown Viewer reset/reuse, layout/settings changes and disable/enable.
- [ ] Charges, intrinsic pet usability and Loss of Control under restrictions.
- [ ] Enable/disable during an existing relevant cast.
- [ ] `/reload` with optional providers already loaded and loaded later.
- [ ] `/console taintLog 2`: no blocked/forbidden action.

## GCD correctness live tests

- [ ] Personal interrupt cooldown overlapping another active GCD remains not-ready.
- [ ] Same scenario in restricted content remains fail-closed when ignore-GCD duration is inaccessible.
- [ ] `UNIT_SPELLCAST_SUCCEEDED` causes invalidation only for a confirmed interrupt source.
- [ ] Runtime report shows `gcd.isOnGCDReadinessProof=false`.

## Worker and persistence live tests

- [ ] After prewarm settles: `flush.dirty=false`, `prewarm.pending=false`, `prewarm.scheduled=false`, `runtime.enabled=false`.
- [ ] Workers return to Disabled after combat, Settings, target/focus changes and addon disable.
- [ ] Schema 2/corrupt SavedVariables migrate to schema 3 while known preferences survive.
- [ ] Unknown keys, legacy caches and runtime objects are absent after reload.
- [ ] Real spec change prunes dormant abilities and does not leave stale readiness.

## Active upstream channel regression tests

- [ ] Target death/invalid unit during active channel: no resurrected glow after stop.
- [ ] Lightning Lasso phantom second channel.
- [ ] Repeated Ray of Frost phantom-channel reproduction.
- [ ] Report contains `channelSuppressed`, `lastEvent`, and `WOWUI-2026-005` evidence.
- [ ] Retire mitigation only after a named live build fixes all scenarios without the guard.

## Performance acceptance

- [ ] Native profiler enabled and reports tick frequency.
- [ ] Compare start/end/delta threshold counters for every attribution run.
- [ ] No new >5 ms crossings attributable to Interrupt Glow in fixed-duration primary scenario.
- [ ] Resolve first repeating Lua/secret/taint/forbidden error before interpreting later watchdog/profiler output.
- [ ] Confirm no duplicate callback/provider attach after enable/disable and reload.
