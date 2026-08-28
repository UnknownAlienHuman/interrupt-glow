# Performance model — Interrupt Glow 1.1

## Complexity and latency

| Signal | Work | Expected latency |
|---|---|---:|
| Target/focus cast start or interruptibility event | one fixed-unit snapshot plus bound interrupt records | synchronous |
| Channel/empower stop | direct event-authoritative clear; no `UnitChannelInfo` re-query | synchronous |
| Native action feedback | one resolved snapshot compare; enqueue only if changed | next frame |
| LAB conditional macro | exact `UpdateAction` hook or `buttonsBySlot[eventSlot]` | next frame |
| Dominos/ButtonForge feedback | changed provider button/slot only | next frame |
| Relevant cooldown event | event-time GCD hint plus one pass over active canonical abilities | next frame |
| Accessible deadline | one shared driver while a result can be visible | ≤50 ms plus one frame |
| Restricted timing | one shared driver only during a relevant cast | ≤250 ms |
| Integer countdown | shared driver only when enabled | 200 ms |
| Initial shell prewarm | 16 physical buttons per frame | bounded startup slicing |

Readiness scales with active canonical interrupt sources, not physical button copies or visible nameplates.

## Mouseover hot path

### Native Blizzard

```text
ActionButton.OnActionChanged(button)
  -> read current slot/action snapshot
  -> unchanged: return
  -> changed: one deduplicated dirty record
```

### LibActionButton

```text
UpdateAction post-hook
or ACTIONBAR_SLOT_CHANGED(slot)
  -> buttonsBySlot[slot]
  -> dirty only known buttons for that slot
```

No mouseover path performs macro-body parsing, frame/nameplate enumeration, 540-slot scanning, cooldown work for a current shared ability, or UI allocation.

## Channel stale-snapshot guard

`UnitChannelInfo` has an active upstream phantom/stale issue family. Polling after `CHANNEL_STOP` is therefore forbidden until a real start or unit-identity reset:

```text
stop event
  -> verify NeverSecret castBarID is not stale
  -> set channelSuppressed
  -> clear normalized cast state

later UNIT_FLAGS / UNIT_FACTION / targetable update
  -> ordinary UnitCastingInfo remains allowed
  -> UnitChannelInfo skipped while suppressed
```

This removes both false glow and repeated readiness work caused by phantom second channels.

## Cooldown filtering

`SPELL_UPDATE_COOLDOWN` supplies spell/base/category/start-recovery information. Interrupt Glow accepts exact interrupt families and learned non-global shared categories, discards unrelated pure GCD events, and evaluates unknown non-global categories only while a cast/countdown can display the result.

`isOnGCD` is normalized only during the actual event dispatch.

## Idle and disabled states

When no relevant cast exists and countdown text is disabled:

- cooldown/charge/usability/LoC evaluation is idle;
- 50 ms and 250 ms drivers are hidden;
- only bounded action/cast lifecycle state remains active.

When the addon is disabled, readiness work is skipped entirely. Internal path counters are also dormant unless debug or an explicit capture is active.

## Native profiler protocol

Use `C_AddOnProfiler`; do not enable legacy `scriptProfile`.

The probe records:

- `SessionAverageTime`;
- `RecentAverageTime`;
- `EncounterAverageTime`;
- `LastTime`;
- `PeakTime`;
- threshold counters from 1 ms through 1000 ms;
- profiler enabled state and tick frequency.

Threshold counters and `PeakTime` are application-session cumulative. A capture records a start baseline and an end snapshot. Only cumulative threshold counts are subtracted. `PeakTime` is shown as start/end/increase and must not be described as a resettable window maximum.

## Attribution matrix

Use equal-duration, equal-input runs:

1. default UI / no third-party addons;
2. Interrupt Glow only;
3. Interrupt Glow plus required action-bar provider;
4. full addon stack.

Record build, location, combat/restriction context, visible nameplate count, macro, target/focus actions, provider versions and the complete runtime report. Fix repeating Lua/secret/taint errors before interpreting later profiler/watchdog lines.

## Startup cost

Interrupt Glow itself is not LoadOnDemand because it must observe casts automatically. Startup is internally lazy:

- gameplay/provider attachment waits for `PLAYER_LOGIN`;
- already-loaded registries are enumerated once;
- optional providers use load callbacks;
- Settings/report UI is constructed only when opened;
- overlays are allocated outside combat in bounded batches.

A separate LOD options companion is not introduced yet: current options/report UI has no idle `OnUpdate`, creates no window until opened, and must first be shown material in a native profiler capture before adding packaging complexity.

## Live acceptance

Local scripts prove syntax and modeled state transitions only. Required client gates:

- Quick Heal mouseover stress with native baseline/deltas;
- target-death, Lightning Lasso and Ray of Frost channel regressions;
- Mythic+, raid, arena/BG restriction states;
- taint/blocked/forbidden errors;
- provider load-order and full-stack attribution;
- no new >5 ms threshold crossings attributable to Interrupt Glow during the fixed-duration primary scenario.
