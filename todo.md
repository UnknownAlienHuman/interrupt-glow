# Interrupt Glow 1.1 release checklist

## Static implementation

- [x] Remove automatic full action-slot, frame, nameplate, macro-body and Cooldown Viewer tree scans.
- [x] Use current action feedback and `C_ActionBar.IsInterruptAction` for slot-backed classification.
- [x] Deduplicate native and LibActionButton conditional-macro feedback before frame-batched reconciliation.
- [x] Use callback-handle lifecycle for native EventRegistry registration when supported.
- [x] Add current 12.1.0 per-spec interrupt data, reviewed PvP exceptions and direct pet aliases.
- [x] Defer gameplay/provider startup to `PLAYER_LOGIN` and verified late-load surfaces.
- [x] Keep GitHub Actions workflows absent; live-client acceptance remains authoritative.
- [x] Track only fixed `target` and `focus` cast units.
- [x] Route inaccessible `notInterruptible` directly to `SetAlphaFromBoolean(..., 0, 255)` without storage, logging, readback or a `pcall` result lane.
- [x] Share readiness per canonical ability and make cooldown/usability/LoC evaluation on-demand.
- [x] Fail closed on inaccessible LoC and action/spell/pet usability.
- [x] Normalize GCD state only inside `SPELL_UPDATE_COOLDOWN` dispatch.
- [x] Prevent stale readiness and countdown display with `readinessPending`.
- [x] Add Cooldown Viewer pool lifecycle, duplicate suppression and active-item off/on rebinding.
- [x] Incrementally prewarm addon-owned visual shells outside combat.
- [x] Keep internal counters dormant outside explicit debug/capture sessions.
- [x] Add build/context/provider/secrecy/readiness runtime evidence capture.
- [x] Capture all native profiler metrics through the 1000 ms threshold.
- [x] Record native profiler baselines and threshold-count deltas instead of claiming a counter reset.
- [x] Track active upstream `WOWUI-2026-005` and implement event-authoritative channel/empower stop handling.
- [x] Suppress stale `UnitChannelInfo` snapshots after stop until a real start or unit-identity reset.
- [x] Ignore delayed stop events whose NeverSecret `castBarID` belongs to an older cast.
- [x] Add focused runtime-probe, callback-handle, CDM toggle and phantom-channel regression tests.
- [x] Keep unconfirmed `SPELL_SECRECY_CHANGED` out of runtime registrations.

## Fresh local/manual checks before merge

- [ ] `texlua tests/check_syntax.lua .`
- [ ] `python tests/static_checks.py`
- [ ] `texlua tests/mock_wow.lua .`
- [ ] `texlua tests/cdm_toggle.lua .`
- [ ] `texlua tests/runtime_probe.lua .`
- [ ] `texlua tests/native_callback_handles.lua .`
- [ ] `texlua tests/channel_guard.lua .`
- [ ] Confirm `.github/workflows` remains absent.
- [ ] Inspect final PR patch after all fixes; do not rely on an older committed report.

## Required live-client attribution matrix

Run equal-duration/equal-input captures for:

- [ ] default Blizzard UI with third-party addons disabled;
- [ ] Interrupt Glow only;
- [ ] Interrupt Glow plus the required action-bar provider;
- [ ] normal full addon stack.

For every run record build, location/instance, combat/restriction state, visible nameplate count, macro, provider versions, FPS, taint/errors and the complete `/iglow capture show` report.

## Required functional live tests

- [ ] Quick Heal `[@mouseover,help][]` reproduction: friendly hover and hostile/nameplate hover.
- [ ] Conditional heal/interrupt macro changes in combat.
- [ ] No interrupt currently on bars.
- [ ] Target and focus acquired mid-cast.
- [ ] Restricted Mythic+, raid, arena and battleground contexts.
- [ ] Page, stance, form, stealth, vehicle and override changes.
- [ ] Bartender, ElvUI and Dominos current releases.
- [ ] ButtonForge direct, cleared and conditional macro buttons.
- [ ] Warlock Felhunter/Felguard, sacrifice, Command Demon and Call Felhunter.
- [ ] Protection Warrior Pummel plus Disrupting Shout.
- [ ] Cooldown Viewer layout/settings changes, disable/enable and pool reuse.
- [ ] Charges, intrinsic pet usability and Loss of Control under restrictions.
- [ ] Enable/disable during an existing relevant cast.
- [ ] `/reload` with each optional provider already loaded and not loaded yet.
- [ ] `/console taintLog 2`: no blocked/forbidden action.

## Active upstream channel regression tests

- [ ] Target death/invalid unit during an active channel: no resurrected glow after stop.
- [ ] Lightning Lasso phantom second channel reproduction.
- [ ] Ray of Frost phantom second channel reproduction over repeated/long-duration testing.
- [ ] Confirm report contains `channelSuppressed`, `lastEvent`, and `WOWUI-2026-005` evidence.
- [ ] Retire mitigation only after a named live build fixes all three scenarios without the guard.

## Performance acceptance

- [ ] Native profiler is enabled and reports tick frequency.
- [ ] Compare start/end/delta threshold counters for every attribution run.
- [ ] No new >5 ms threshold crossings attributable to Interrupt Glow in the fixed-duration primary scenario.
- [ ] Resolve the first repeating Lua/secret/taint/forbidden error before interpreting later profiler/watchdog output.
- [ ] Confirm no duplicate callback/provider attach after enable/disable and `/reload`.
