# Changelog

## 1.1.0-beta.5

- Fix inaccessible Loss of Control handling: secret/restricted LoC information now hard-fails closed instead of being treated as clear, and optimistic cooldown compatibility cannot bypass it.
- Add a focused action/spell LoC regression test covering restricted data, optimistic mode, and accessible nil/no-LoC behavior.
- Align the static validation contract and release metadata with `1.1.0-beta.5`.
- Harden canonical readiness source selection across action, pet, direct spell, ButtonForge and Cooldown Viewer copies.
- Reconcile canonical sources before the batched readiness filter so a bound ability with a temporarily missing source cannot be skipped for a full generation.
- Preserve runtime-discovered interrupt families across base/override aliases while revalidating current spellbook availability.
- Keep Cooldown Viewer identity captured at its pool callback and defer bind/unbind and visual work to the addon-owned frame batch.
- Retire broad LibActionButton visual callbacks after late-created buttons expose exact `UpdateAction` hooks; support both set-style and array-style LAB registries.
- Bound prewarm work by records inspected, not only successful shell allocations.
- Add explicit ownership for manual and capture counter windows and bound runtime-probe markers/restriction evidence.
- Implement current Canvas Settings lifecycle methods and defer first control creation until out of combat.
- Keep `UNIT_SPELLCAST_SUCCEEDED` payload access-gated and use inaccessible payloads only as a bounded fail-closed invalidation signal.
- Keep GitHub Actions workflows absent; local and live-client validation remain separate gates.

## 1.1.0-beta.4

- Repin the shared workflow to `wow-addon-engineering-kb@312085aa8d23dfe283b416ba0f394fef1cae22dd` and follow its current-first event, performance, persistence, hook and GCD guidance.
- Add `core/Worker.lua` and use Retail 12.1 `SetOnUpdateMode`: dirty flush and prewarm slices use `RunOnce`, active timing uses `RunAlways`, and idle workers use `Disabled`.
- Fix initial worker state so a default active `OnUpdate` cannot survive a false-state deduplication.
- Replace permissive SavedVariables reuse with schema 3: rebuild a known-key typed preference table on every load, add producer/interface metadata, clamp `debugKeep`, and discard legacy caches and unknown keys.
- Preserve dormant abilities during same-spec macro churn, but prune unreferenced canonical abilities and reset source-readiness caches after a real specialization change.
- Defer Cooldown Viewer pool reset/reuse reconciliation: hook stacks update ordinary identity and queue one dirty record instead of mutating addon bindings/visuals synchronously.
- Add worker, SavedVariables, cache-policy, deferred-CDM and GCD-safety focused tests.
- Fix a readiness false-positive: `isOnGCD=true` is no longer allowed to turn an active cooldown into `ready=true`, because it does not prove absence of an overlapping personal cooldown.
- Keep global-cooldown exclusion solely in `GetActionCooldownDuration(slot, true)` and `GetSpellCooldownDuration(spellID, true)`; inaccessible ignore-GCD duration fails closed.
- Treat `UNIT_SPELLCAST_SUCCEEDED` only as an invalidation signal for a confirmed interrupt source, never as proof of a GCD transition.
- Stop collecting GCD hints in the runtime event path and expose the conservative policy in runtime reports.
- Add SavedVariables schema, worker state and GCD policy to `/iglow probe` output.
- Keep the event-authoritative `UnitChannelInfo` phantom/stale mitigation and callback-handle lifecycle from beta.3.
- Keep GitHub Actions workflows absent; live-client evidence remains the release gate.

## 1.1.0-beta.3

- Add an explicit in-client runtime probe for build/interface, provider attribution, instance context, restriction transitions, active cooldown secrecy, normalized cast/readiness state, session counters, and native profiler evidence.
- Record `C_AddOnProfiler` start/end snapshots and subtract cumulative threshold counters for each capture window; report `PeakTime` as start/end/increase rather than pretending it can be reset.
- Cover native metrics through `CountTimeOver1000Ms`, plus profiler enabled state and tick frequency.
- Add `/iglow probe` and `/iglow capture start|mark|stop|show` commands with marker-level profiler snapshots.
- Keep runtime probe counters dormant until capture is explicitly started.
- Add provider loaded/attached state for default UI, provider and full-stack attribution runs.
- Add a reusable copyable report surface without allowing raw secret payloads into logs/reports.
- Move native `ActionButton.OnActionChanged` registration to `EventUtil.CreateCallbackHandleContainer()` when supported; retain the compatibility fallback.
- Record restriction-state transition payloads during active captures without querying restriction state during dispatch.
- Add an event-authoritative guard for active upstream `UnitChannelInfo` phantom/stale channels (`WOWUI-2026-005`, WoWUIBugs #777/#784/#834).
- Treat synchronous channel/empower stop as authoritative until a real start or target/focus identity reset; ignore delayed stop events whose NeverSecret `castBarID` belongs to an older cast.
- Register channel/empower update events and suppress them while the stale-channel guard is active.
- Add focused tests for stale snapshots, stale stop events, callback handle attach/detach and runtime-profiler deltas.
- Document that `SPELL_SECRECY_CHANGED` remains unconfirmed in pinned 12.1.0.69497 generated docs/implementation.

## 1.1.0-beta.2

- Defer gameplay event registration and provider discovery until `PLAYER_LOGIN`.
- Use the second `C_AddOns.IsAddOnLoaded` return for fully-loaded lifecycle gates.
- Use `C_ActionBar.IsInterruptAction` plus current resolved action feedback as the runtime authority for slot-backed buttons.
- Deduplicate native action feedback before frame-batched reconciliation.
- Replace broad LibActionButton visual-update work with exact `UpdateAction` post-hooks and changed-slot routing to already-indexed buttons.
- Add targeted Blizzard, LibActionButton, Dominos, ButtonForge, pet-action and Cooldown Viewer integrations without global frame, slot, nameplate or macro-body scans.
- Add the pinned WoW `12.1.0.69497` ordinary specialization interrupt snapshot and reviewed Warlock PvP/pet exceptions.
- Share readiness across copies of the same canonical interrupt and preserve dormant ability state through rapid conditional-macro transitions.
- Make readiness on-demand: cooldown, charge, usability, pet and Loss-of-Control evaluation sleeps while no cast or enabled countdown can display it.
- Mark readiness pending before a newly relevant cast/countdown refresh, preventing a one-frame stale glow or stale number.
- Add action, spell and pet usability gates; treat inaccessible usability and Loss of Control as hard fail-closed restrictions.
- Route potentially secret cast interruptibility directly to `SetAlphaFromBoolean(..., 0, 255)` without storage, logging, readback or a `pcall` result lane.
- Prewarm lightweight physical-button shells incrementally outside combat.
- Deduplicate ButtonForge and Cooldown Viewer lifecycle notifications.
- Keep production counters dormant unless debug or an explicit session profiling window is enabled.
- Remove GitHub Actions workflows. Local scripts remain development checks; live WoW acceptance is authoritative.

## 1.1.0-beta.1

- Initial event-driven, scan-free 1.1 runtime.
