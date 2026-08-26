# Interrupt Glow 1.1 release checklist

## Static implementation

- [x] Remove automatic full action-slot scan.
- [x] Remove automatic frame enumeration.
- [x] Remove nameplate traversal from cast/glow paths.
- [x] Remove macro-body parsing from slot-backed actions.
- [x] Use `C_ActionBar.IsInterruptAction` and current action feedback.
- [x] Add exact 12.1.0 per-spec interrupt snapshot and generator.
- [x] Add current Warlock pet aliases; remove obsolete Retail IDs.
- [x] Defer gameplay events/provider discovery to `PLAYER_LOGIN`.
- [x] Use fully-loaded add-on lifecycle gates and late-provider callbacks.
- [x] Add fixed target/focus unit-event watchers.
- [x] Route secret `notInterruptible` only to `SetAlphaFromBoolean(..., 0, 255)`.
- [x] Share readiness per canonical ability and cache one source result per pass.
- [x] Normalize `isOnGCD` during `SPELL_UPDATE_COOLDOWN` dispatch.
- [x] Add charge, pet, LoC and restricted-timing handling.
- [x] Fail closed on inaccessible LoC.
- [x] Add immediate player/pet interrupt-success invalidation.
- [x] Add Cooldown Viewer pool lifecycle and duplicate suppression.
- [x] Incrementally prewarm lightweight overlays outside combat.
- [x] Add targeted Blizzard/LAB/Dominos/ButtonForge integrations.
- [x] Add static checks, Lua syntax, mapping check, mock stress and CI.

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
- [ ] Warlock Felhunter/Felguard, sacrifice and Command Demon.
- [ ] Protection Warrior Pummel + Disrupting Shout.
- [ ] Cooldown Viewer layout and pool reuse.
- [ ] Charges and Loss of Control under restrictions.
- [ ] `/console taintLog 2`: no blocked/forbidden action.
- [ ] `C_AddOnProfiler`: no new >5 ms ticks during 60-second mouseover stress.
- [ ] Compare enable/disable and `/reload` attach counts for duplicate callbacks.
