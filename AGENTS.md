# AGENTS.md — Interrupt Glow

## Current target

- Repository: `UnknownAlienHuman/interrupt-glow`
- Game: World of Warcraft Retail / Midnight
- Patch contract: `12.1.0`
- Interface: `120100`
- Verified Blizzard source: `12.1.0.69497`
- `wow-ui-source` commit: `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`
- Shared engineering KB: `UnknownAlienHuman/wow-addon-engineering-kb@e45366cb0ca56dfe49664daa9f2579e629af0cb3`

Read this repository first. Then route through the KB and pinned Blizzard source. Project behavior does not override the current Blizzard API/security contract.

## Required task route

1. Read this file, `InterruptGlow.toc`, `ARCHITECTURE.md`, and the affected source modules.
2. Read `wow-addon-engineering-kb/KB/core/BlizzardUI_DevWorkflow.md`.
3. For performance, read `KB/core/BlizzardUI_Performance_Modules.md`.
4. For SecretValue/taint, read `KB/core/BlizzardUI_security.md` and `KB/deep/WoWDevSecretValue_KB_12.1.0.md`.
5. For developer-chat findings and upstream regressions, read `KB/field/README.md` and `KB/field/Active_Upstream_Issues.md`.
6. Prove API/event/hook claims in pinned generated docs and implementation.
7. Use the in-client runtime probe for data-, hotfix-, restriction-, or performance-dependent claims.

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
11. `isOnGCD` may be normalized only during `SPELL_UPDATE_COOLDOWN` dispatch.
12. Restricted Loss of Control and inaccessible action/spell/pet usability are hard fail-closed gates.
13. A synchronous cast/channel stop is authoritative over a later `UnitChannelInfo` snapshot until a real start or unit-identity reset.
14. Keep GitHub Actions workflows absent. Live WoW FPS, taint, secure execution, and restricted contexts are the release gate.

## Lifecycle contract

- Prefer callback handles and `EventUtil.CreateCallbackHandleContainer()` when the registry supports handles.
- Optional Blizzard/third-party providers attach through `ContinueOnAddOnLoaded` or an equivalent verified lifecycle surface.
- Permanent `hooksecurefunc` hooks must have a cheap module-attached guard.
- New visual objects are created out of combat and reused.
- Target/focus identity changes explicitly reset channel-snapshot suppression; generic unit-state events do not.

## Active upstream issue contract

`WOWUI-2026-005` is active: `UnitChannelInfo` can report stale or phantom channels after a real stop (`WoWUIBugs` #777, #784, #834). Current mitigation is event-authoritative channel lifecycle in `core/CastTracking.lua`.

Retirement gate:

1. named live build with the upstream fix;
2. repeat target-death, Lightning Lasso, and Ray of Frost repros;
3. confirm no phantom channel without the guard;
4. only then remove the active workaround and current documentation route.

Do not close or silently remove the workaround merely because source changed.

## Secrecy policy

Use runtime predicates only as build/context evidence:

```lua
C_Secrets.GetSpellCooldownSecrecy(spellID)
C_Secrets.ShouldSpellCooldownBeSecret(spellID)
C_Secrets.ShouldActionCooldownBeSecret(slot)
C_Secrets.ShouldUnitSpellCastingBeSecret(unit)
```

The shared KB recommends `SPELL_SECRECY_CHANGED` cache invalidation, but that event is **not confirmed** in the pinned `12.1.0.69497` generated docs or implementation. Do not register an unverified event. Re-search current source and probe the live client before adding it.

## Runtime evidence

Use:

```text
/iglow capture start <scenario>
/iglow capture mark <step>
/iglow capture stop
/iglow capture show
```

The report records build/interface, addon version, instance context, provider load state, observed restriction transitions, current `C_Secrets` policy, normalized cast/ability state, internal counters, and native `C_AddOnProfiler` start/end/delta metrics. It must never contain raw secret payloads.

Native profiler counters are application-session cumulative. Capture a baseline at start and subtract threshold counts at stop; do not call the operation a reset. Use `SessionAverageTime`, `RecentAverageTime`, `EncounterAverageTime`, `PeakTime`, and all threshold counters through `CountTimeOver1000Ms`. Do not enable legacy `scriptProfile`.

## Validation reporting

Report every check as:

```text
command
status = pass | fail | skipped
ref/tree tested
observed result
```

Missing tooling is `skipped`, never `pass`. Offline/mock checks do not prove WoW behavior. Required in-client validation includes:

- Quick Heal `@mouseover` reproduction;
- no-addons/default UI, InterruptGlow-only, required-provider, and full-stack attribution runs;
- restricted Mythic+/raid/PvP;
- `taintLog 2`;
- provider load-order cases;
- Warlock pet variants;
- Protection Warrior dual interrupts;
- Cooldown Viewer pool reuse;
- target-death channel, Lightning Lasso, and Ray of Frost phantom-channel repros;
- native profiler baseline/delta capture.
