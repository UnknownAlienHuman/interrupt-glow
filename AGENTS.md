# AGENTS.md — Interrupt Glow

## Current target

- Repository: `UnknownAlienHuman/interrupt-glow`
- Game: World of Warcraft Retail / Midnight
- Patch contract: `12.1.0`
- Interface: `120100`
- Verified Blizzard source: `12.1.0.69497`
- `wow-ui-source` commit: `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`
- Shared engineering KB: `UnknownAlienHuman/wow-addon-engineering-kb@5a992ae702a278f3893c7e8f1b212583311438b5`

Read this repository first. Then follow the current-first KB router and pinned Blizzard source. Historical documents are evidence, not current implementation authority.

## Required task route

1. Read this file, `InterruptGlow.toc`, `ARCHITECTURE.md`, and affected source modules.
2. Read `KB/core/BlizzardUI_DevWorkflow.md`.
3. Route events through `KB/core/BlizzardUI_EventPatterns.md`.
4. Route performance through `KB/core/BlizzardUI_Performance_Modules.md`.
5. Route SecretValue/taint through `KB/core/BlizzardUI_security.md` and `KB/deep/Spell_Secrecy_Registry_12_1_0.md`.
6. Route action-bar/CDM work through `KB/nodes/BlizzardUI_ActionBars.md` and `KB/nodes/BlizzardUI_CooldownViewer.md`.
7. Route persistence through `KB/addon/Addon_SavedVariables.md`.
8. Check `KB/field/README.md` and `KB/field/Active_Upstream_Issues.md` before changing workarounds.
9. Prove API/event/hook claims in current generated docs and implementation.
10. Use the in-client runtime probe for data-, hotfix-, restriction-, provider-, or performance-dependent claims.

## Hard runtime rules

1. Do not restore `EnumerateFrames`, nameplate traversal, or a 1..540 action-slot scan.
2. Do not parse macro bodies for slot-backed buttons.
3. Do not subscribe to `ACTIONBAR_UPDATE_COOLDOWN`.
4. `ACTIONBAR_SLOT_CHANGED` is allowed only in `core/LABAdapter.lua`, where the event slot selects already-indexed LAB buttons.
5. Never store, compare, format, table-key, serialize, or log inaccessible values.
6. Raw cast `notInterruptible` may only flow directly to `SetAlphaFromBoolean(..., 0, 255)`.
7. Never animate or read back the region carrying the Alpha secret aspect.
8. Do not pass a secret `LuaDurationObject` into addon-owned cooldown/statusbar/text bindings.
9. Do not create overlays in combat.
10. Keep provider integration callback-first, idempotent, bounded, and behaviorally guarded after detach.
11. Ignore the global cooldown through `GetActionCooldownDuration(slot, true)` / `GetSpellCooldownDuration(spellID, true)`. Never treat `isOnGCD=true` or `UNIT_SPELLCAST_SUCCEEDED` as positive readiness proof.
12. Restricted Loss of Control and inaccessible action/spell/pet usability are hard fail-closed gates.
13. A synchronous cast/channel stop is authoritative over a later `UnitChannelInfo` snapshot until a real start or unit-identity reset.
14. `RegisterUnitEvent` filters must be unit varargs, never a unit-token table.
15. One-shot and idle workers use `SetOnUpdateMode`; do not leave visible/active `OnUpdate` frames merely to discover no work.
16. Cooldown Viewer pool hooks update ordinary identity and queue reconciliation; do not mutate addon visuals synchronously inside Blizzard reset/layout hooks.
17. SavedVariables contain only known typed preferences and producer/schema metadata. Never persist runtime caches, frames, callback tuples, secret policy, or raw payloads.
18. Keep GitHub Actions workflows absent. Live WoW FPS, taint, secure execution, and restricted contexts are release gates.

## Lifecycle contract

- Prefer callback handles and `EventUtil.CreateCallbackHandleContainer()` when the registry supports handles.
- Optional Blizzard/third-party providers attach through `ContinueOnAddOnLoaded` or another verified lifecycle surface.
- Permanent `hooksecurefunc` hooks have a cheap module-attached guard.
- New visual objects are created out of combat and reused.
- `core/Worker.lua` maps one-shot work to `Enum.OnUpdateMode.RunOnce`, continuous active timing to `RunAlways`, and idle state to `Disabled`; Show/Hide exists only as a compatibility/test fallback.
- The master switch detaches provider callbacks and target/focus watchers, stops addon workers, clears pending work, and unregisters all non-persistent runtime events. Only regen lifecycle and optional restriction telemetry remain registered while disabled.
- Conditional native/LAB/Dominos/ButtonForge identity churn is retained in one bounded weak deferred set while neither a relevant cast nor cooldown text consumes readiness. The set is flushed before the same-frame cooldown pass when readiness wakes.
- Target/focus identity changes reset channel-snapshot suppression; generic unit-state events do not.
- Specialization changes prune dormant canonical abilities and reset source-readiness caches after all buttons reconcile. Same-spec macro churn retains dormant state to avoid GC churn.

## GCD contract

Interrupt Glow is a readiness consumer, not a GCD analyzer. The current KB's GCD observation protocol for analyzers uses explicit GCD spell `61304`, accessibility gating, deduplication, and bounded segment polling. That protocol must not be partially copied into interrupt readiness.

For Interrupt Glow:

```text
accessible ignore-GCD duration == zero  -> ready candidate
accessible ignore-GCD duration > zero   -> not ready
restricted duration + isActive=true     -> fail closed
isOnGCD=true                            -> never proves ready
UNIT_SPELLCAST_SUCCEEDED                -> invalidation only for a confirmed interrupt source
```

`core/GCDSafetyPolicy.lua` forces every wrapped readiness resolver to ignore legacy `gcdOnlyHint` inputs and replaces the collector with a no-op/clear boundary.

## Active upstream issue contract

`WOWUI-2026-005` is active: `UnitChannelInfo` can report stale or phantom channels after a real stop (`WoWUIBugs` #777, #784, #834). Current mitigation is event-authoritative channel lifecycle in `core/CastTracking.lua`.

Retirement gate:

1. named live build with the upstream fix;
2. repeat target-death, Lightning Lasso, and Ray of Frost repros;
3. confirm no phantom channel without the guard;
4. only then remove the workaround and current documentation route.

`WOWUI-2026-009` tracks unresolved `RegisterUnitEvent` table-vs-varargs behavior. Preserve explicit unit varargs until the public contract and current Blizzard callers converge.

## Secrecy policy

Use runtime predicates only as build/context evidence:

```lua
C_Secrets.GetSpellCooldownSecrecy(spellID)
C_Secrets.ShouldSpellCooldownBeSecret(spellID)
C_Secrets.ShouldActionCooldownBeSecret(slot)
C_Secrets.ShouldUnitSpellCastingBeSecret(unit)
```

The current KB recommends `SPELL_SECRECY_CHANGED` invalidation, but that event is not confirmed in pinned `12.1.0.69497` generated docs or implementation. Do not register an unverified event. Re-search current source and probe the live client before adding it.

## Runtime evidence

Use:

```text
/iglow capture start <scenario>
/iglow capture mark <step>
/iglow capture stop
/iglow capture show
```

The report records build/interface, saved schema, provider load state, worker state, instance context, observed restriction transitions, current `C_Secrets` policy, normalized cast/ability state, addon counters, and native `C_AddOnProfiler` start/end/delta metrics. It must never contain raw secret payloads.

Native profiler counters are application-session cumulative. Capture a baseline and subtract threshold counts at stop; do not call this a reset. Use `SessionAverageTime`, `RecentAverageTime`, `EncounterAverageTime`, `PeakTime`, and thresholds through `CountTimeOver1000Ms`. Do not enable legacy `scriptProfile`.

## Validation reporting

Report each check as:

```text
command
status = pass | fail | skipped
ref/tree tested
observed result
```

Missing tooling is `skipped`, never `pass`. Offline/mock checks do not prove WoW behavior. Required in-client validation includes Quick Heal mouseover, equal-input attribution runs, restricted content, `taintLog 2`, provider load order, Warlock/PWarrior variants, CDM pool reuse, phantom-channel repros, unit-event filtering, worker idle state, SavedVariables migration, GCD-overlap readiness, and native profiler baseline/deltas.
