# Runtime probe

Interrupt Glow includes a session-only in-client evidence collector. It is disabled until explicitly started and adds no counter work while inactive.

## Commands

```text
/iglow probe
/iglow capture start quick-heal-mouseover
/iglow capture mark before-hover
/iglow capture mark friendly-hover
/iglow capture mark hostile-hover
/iglow capture stop
/iglow capture show
```

`/iglow probe` opens an immediate snapshot. `capture start` resets and enables internal counters; `capture stop` freezes the report and disables them.

## Report sections

- `build`: `GetBuildInfo`, Interface, addon version, pinned Blizzard source and KB commit;
- `context`: instance type/difficulty, combat state, observed restriction transitions;
- `capture`: scenario label, elapsed duration and manual markers;
- `casts`: normalized target/focus state only;
- `secrecy`: `C_Secrets` cooldown/cast policy for active interrupt spells and action slots;
- `abilities`: normalized per-ability readiness/restriction state;
- `counters`: session-only addon path counters;
- `profiler`: current `C_AddOnProfiler` metrics.

The probe never stores or formats raw SecretValue payloads. Potentially secret cast interruptibility remains in the direct API-to-widget sink used by the feature runtime.

## Recommended Quick Heal reproduction

1. `/reload` with the target action-bar addon enabled.
2. `/iglow capture start quick-heal-mouseover`
3. Stand near friendly and hostile units with the reported macro present.
4. `/iglow capture mark baseline`
5. Hover friendly units repeatedly for 30 seconds.
6. `/iglow capture mark friendly-hover-complete`
7. Hover hostile units/nameplates repeatedly for 30 seconds.
8. `/iglow capture mark hostile-hover-complete`
9. `/iglow capture stop`
10. `/iglow capture show`, copy the complete report.

Also record FPS, visible nameplate count, action-bar provider, `/console taintLog 2` results, and whether the original lag remains.

## Evidence boundary

The probe is runtime evidence for one build/context. It is not a permanent secrecy whitelist and does not replace testing in Mythic+, raids, arenas, battlegrounds, and provider-specific load-order scenarios.
