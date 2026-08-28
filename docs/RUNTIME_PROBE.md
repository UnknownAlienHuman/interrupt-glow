# Runtime probe

Interrupt Glow includes a session-only in-client evidence collector. It is disabled until explicitly started and adds no internal-counter work while inactive.

## Commands

```text
/iglow probe
/iglow capture start quick-heal-mouseover
/iglow capture mark baseline
/iglow capture mark friendly-hover
/iglow capture mark hostile-hover
/iglow capture stop
/iglow capture show
```

`/iglow probe` opens an immediate snapshot. `capture start` clears only Interrupt Glow's addon-owned session counters and records a native profiler baseline. Blizzard `C_AddOnProfiler` counters are application-session cumulative and are **not reset**. `capture stop` records the final snapshot and reports threshold-counter deltas.

## Report sections

- `build`: `GetBuildInfo`, Interface, addon version, pinned Blizzard source and KB commit;
- `context`: instance type/difficulty, combat state and every observed restriction transition;
- `providers`: loaded/attached state for native bars, Bartender, ElvUI, Dominos, ButtonForge and Cooldown Viewer;
- `capture`: scenario label, duration and manual markers;
- `casts`: normalized target/focus state, last event and phantom-channel suppression state;
- `secrecy`: `C_Secrets` cooldown/cast policy for active interrupt spells and action slots;
- `abilities`: normalized per-ability readiness/restriction state;
- `counters`: session-only addon path counters;
- `profiler`: native profiler start/end snapshots, peak increase, threshold deltas and marker snapshots.

Profiler fields include:

```text
SessionAverageTime
RecentAverageTime
EncounterAverageTime
LastTime
PeakTime
CountTimeOver1Ms
CountTimeOver5Ms
CountTimeOver10Ms
CountTimeOver50Ms
CountTimeOver100Ms
CountTimeOver500Ms
CountTimeOver1000Ms
```

The probe never stores or formats raw SecretValue payloads. Potentially secret cast interruptibility remains in the direct API-to-widget sink used by the feature runtime.

## Attribution matrix

Run the same measured scenario for the same duration and location:

1. default UI with all third-party addons disabled;
2. Interrupt Glow only;
3. Interrupt Glow plus the required action-bar provider;
4. normal full addon stack.

Do not compare one 20-second run with one 2-minute run. Record the same visible-nameplate count, target/focus behavior, macro, instance and combat state. Native profiler deltas attribute threshold crossings during each capture window; `PeakTime` is session-global and therefore reported as start/end/increase, not as a resettable window maximum.

## Quick Heal mouseover reproduction

1. `/reload` with the intended action-bar provider enabled.
2. `/iglow capture start quick-heal-mouseover`
3. Stand near friendly and hostile units with the reported macro present.
4. `/iglow capture mark baseline`
5. Hover friendly units repeatedly for 30 seconds.
6. `/iglow capture mark friendly-hover-complete`
7. Hover hostile units/nameplates repeatedly for 30 seconds.
8. `/iglow capture mark hostile-hover-complete`
9. `/iglow capture stop`
10. `/iglow capture show`, then copy the complete report.

Also record FPS, visible nameplate count, exact action-bar provider/version, `/console taintLog 2` results, and whether the original lag remains.

## Active UnitChannelInfo regression matrix

`WOWUI-2026-005` remains an active upstream issue family. Interrupt Glow uses a guarded event-authoritative lifecycle: after `UNIT_SPELLCAST_CHANNEL_STOP` or `UNIT_SPELLCAST_EMPOWER_STOP`, later `UnitChannelInfo` snapshots are ignored until a real start event or a target/focus identity change.

Run all three scenarios with a capture:

### A. Target death while channeling

1. Acquire a unit that channels.
2. Start capture and mark `channel-started`.
3. Kill or lose the target while the channel is active.
4. Mark `target-death` and continue changing target/unit flags for at least five seconds.
5. Confirm no interrupt glow resurrects after the stop event.

### B. Lightning Lasso phantom channel

1. Test in an instance where the public issue reproduces.
2. Capture the complete real channel and five seconds after it ends.
3. Confirm `casts.target.active=false` after the stop and `channelSuppressed=true` if the stale snapshot family occurs.

### C. Ray of Frost phantom channel

1. Test on a durable target or target dummy.
2. Capture repeated channels for at least ten minutes if practical.
3. Confirm no second addon-visible channel appears without a new start event.

Retire this workaround only after a named live build fixes the upstream behavior and all three exact repros pass without the guard.

## Evidence boundary

The probe is runtime evidence for one build/context. It is not a permanent secrecy whitelist and does not replace testing in Mythic+, raids, arenas, battlegrounds, provider-specific load-order scenarios, or taint/forbidden-error review.
