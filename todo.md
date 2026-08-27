# Interrupt Glow 1.1 release checklist

## Static implementation

- [x] Remove automatic full action-slot scan.
- [x] Remove automatic frame enumeration.
- [x] Remove nameplate traversal from cast/glow paths.
- [x] Remove macro-body parsing from slot-backed actions.
- [x] Use `C_ActionBar.IsInterruptAction` and current resolved action feedback.
- [x] Deduplicate native action feedback before frame-batched reconcile.
- [x] Route LAB conditional-macro feedback through the changed action slot only.
- [x] Remove broad LAB visual-update work for hookable providers.
- [x] Add exact 12.1.0 ordinary per-spec interrupt snapshot and generator.
- [x] Keep verified PvP-talent interrupts outside the generated block (`212619` Call Felhunter).
- [x] Add current Warlock pet aliases; exclude obsolete Optical Blast.
- [x] Match Blizzard Cooldown Viewer talent/spec/PvP invalidation surfaces.
- [x] Defer gameplay events/provider discovery to `PLAYER_LOGIN`.
- [x] Use fully-loaded add-on lifecycle gates and late-provider callbacks.
- [x] Keep GitHub Actions workflows absent; acceptance is live-client only.
- [x] Add fixed target/focus unit-event watchers.
- [x] Detect cast presence through NeverSecret fields.
- [x] Route secret `notInterruptible` directly to `SetAlphaFromBoolean(..., 0, 255)` without storage, logging, readback or a `pcall` result lane.
- [x] Share readiness per canonical ability and cache one source result per pass.
- [x] Preserve dormant ability readiness across rapid heal/interrupt macro transitions.
- [x] Normalize `isOnGCD` only during `SPELL_UPDATE_COOLDOWN` dispatch.
- [x] Learn interrupt cooldown/recovery categories and ignore idle unrelated events.
- [x] Add charge, pet, LoC and restricted-timing handling.
- [x] Fail closed on inaccessible LoC and intrinsic pet usability.
- [x] Prevent optimistic cooldown compatibility from bypassing hard restrictions.
- [x] Stop restricted timing polling when no relevant cast exists.
- [x] Skip cooldown/charge/LoC evaluation while the addon is disabled.
- [x] Add immediate player/pet interrupt-success invalidation.
- [x] Add Cooldown Viewer pool lifecycle, duplicate suppression and off/on rebinding.
- [x] Incrementally prewarm lightweight overlays outside combat.
- [x] Keep internal counters disabled outside explicit debug/profile sessions.
- [x] Make diagnostics inaccessible-safe and combat-lazy.
- [x] Retain optional local syntax/source/mock scripts as development aids only.

## Required live tests

- [ ] Quick Heal `[@mouseover,help][]` regression reproduction.
- [ ] Conditional heal/interrupt macro changes in combat.
- [ ] No interrupt currently on bars.
- [ ] 40–60 visible nameplates.
- [ ] Target and focus acquired mid-cast.
- [ ] Restricted Mythic+, raid and PvP.
- [ ] Page, stance, form, stealth, vehicle and override changes.
- [ ] Bartender, ElvUI and Dominos current releases.
- [ ] ButtonForge direct, cleared and conditional macro buttons.
- [ ] Warlock Felhunter/Felguard, sacrifice, Command Demon and Call Felhunter.
- [ ] Protection Warrior Pummel + Disrupting Shout.
- [ ] Cooldown Viewer layout, settings changes, disable/enable and pool reuse.
- [ ] Charges, intrinsic pet usability and Loss of Control under restrictions.
- [ ] Enable/disable during an existing relevant cast.
- [ ] `/reload` with each optional provider already loaded and not loaded yet.
- [ ] `/console taintLog 2`: no blocked/forbidden action.
- [ ] `C_AddOnProfiler`: no new >5 ms ticks during 60-second mouseover stress.
- [ ] Compare enable/disable and `/reload` attach counts for duplicate callbacks.
