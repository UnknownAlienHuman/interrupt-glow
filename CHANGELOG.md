# Changelog

## Unreleased — KB/runtime probe hardening

- Adopt `wow-addon-engineering-kb@bb13f191903ca4ff63a4c93535edb9eacab9630d` as the shared project workflow and add repository-local `AGENTS.md`.
- Add an explicit in-client runtime probe for build/interface, instance context, observed restriction transitions, active spell/action cooldown secrecy, normalized cast/readiness state, session counters, and `C_AddOnProfiler` metrics.
- Add `/iglow probe` and `/iglow capture start|mark|stop|show` commands.
- Keep runtime probe counters completely dormant until a capture is started.
- Add a reusable copyable report surface to the debug window without allowing raw secret payloads into logs or reports.
- Move the native `ActionButton.OnActionChanged` registration to `EventUtil.CreateCallbackHandleContainer()` when the current EventRegistry supports handles; retain the existing fallback for compatibility.
- Record restriction-state transition payloads in active captures without querying restriction state during event dispatch.
- Document that `SPELL_SECRECY_CHANGED` is not confirmed in the pinned 12.1.0.69497 source and must not be registered until current source/client evidence exists.
- Keep GitHub Actions workflows absent; live-client evidence remains the release gate.

## 1.1.0-beta.2

- Defer gameplay event registration and provider discovery until `PLAYER_LOGIN`.
- Use the second `C_AddOns.IsAddOnLoaded` return for fully-loaded lifecycle gates.
- Use `C_ActionBar.IsInterruptAction` plus current resolved action feedback as the runtime authority for slot-backed buttons.
- Deduplicate native action feedback before frame-batched reconciliation.
- Replace broad LibActionButton visual-update work with exact `UpdateAction` post-hooks and changed-slot routing to already-indexed buttons.
- Add targeted Blizzard, LibActionButton, Dominos, ButtonForge, pet-action and Cooldown Viewer integrations without global frame, slot, nameplate or macro-body scans.
- Add the pinned WoW `12.1.0.69497` ordinary specialization interrupt snapshot.
- Keep verified exceptions outside the generated snapshot: Warlock `212619` Call Felhunter and current direct pet-action aliases.
- Match Blizzard's specialization, combat-config, talent, trait and PvP-talent invalidation surfaces.
- Preserve same-spec runtime discoveries across clustered spell/talent signals; clear them on specialization change.
- Share readiness across copies of the same canonical interrupt and preserve dormant ability state through rapid conditional-macro transitions.
- Make readiness fully on-demand: cooldown, charge, usability, pet and Loss-of-Control evaluation sleeps while no cast or enabled countdown can display it.
- Mark readiness pending before a newly relevant cast or countdown refresh, preventing a one-frame stale glow or stale number.
- Normalize `isOnGCD` only inside the actual `SPELL_UPDATE_COOLDOWN` dispatch.
- Learn only non-global interrupt cooldown/recovery categories and discard unrelated global-recovery events.
- Add `C_ActionBar.IsUsableAction`, `C_Spell.IsSpellUsable` and intrinsic pet-action usability gates.
- Treat inaccessible usability, pet state and Loss of Control as hard fail-closed restrictions that optimistic cooldown mode cannot bypass.
- Stop periodic polling for hard restrictions; keep restricted timing polling active only while a relevant cast exists.
- Add immediate readiness invalidation after successful player/pet interrupt casts.
- Route potentially secret cast interruptibility directly to `SetAlphaFromBoolean(..., 0, 255)` without storage, logging, readback or a `pcall` result lane.
- Keep animation on an ordinary parent gate, never on the region carrying the Alpha secret aspect.
- Prewarm lightweight physical-button shells incrementally outside combat; create animations and text only when required.
- Deduplicate ButtonForge conditional refreshes and handle `ClearCommand`.
- Deduplicate Cooldown Viewer acquire/ID lifecycle notifications and preserve off/on rebinding for active pooled items.
- Keep production counters dormant unless debug or an explicit session profiling window is enabled.
- Make debug output inaccessible-safe and create the debug window only outside combat.
- Remove GitHub Actions workflows. Local syntax, source and mock scripts remain development checks; live WoW acceptance is authoritative.

## 1.1.0-beta.1

- Initial event-driven, scan-free 1.1 runtime.
