# Performance model — Interrupt Glow 1.1

## Complexity and latency

| Signal | Work | Expected latency |
|---|---|---:|
| Target/focus cast start or interruptibility event | one fixed-unit snapshot plus bound interrupt records | synchronous |
| Channel/empower stop | event-authoritative clear; no `UnitChannelInfo` re-query | synchronous |
| Native action feedback | one resolved snapshot compare; enqueue only if changed | next frame |
| LAB conditional macro | exact `UpdateAction` hook or `buttonsBySlot[eventSlot]` | next frame |
| Dominos/ButtonForge feedback | changed provider button/slot only | next frame |
| Relevant cooldown event | one bounded pass over active canonical abilities | next frame |
| Accessible deadline | one shared worker while a result can be visible | ≤50 ms plus one frame |
| Restricted timing | one shared worker only during a relevant cast | ≤250 ms |
| Integer countdown | same worker only when enabled | 200 ms |
| Initial shell prewarm | 16 physical buttons per `RunOnce` slice | bounded startup slicing |

Readiness scales with active canonical interrupt sources, not physical button copies or visible nameplates.

## Worker policy

Retail 12.1 `SetOnUpdateMode` is explicit:

```text
flushFrame   -> RunOnce while dirty, Disabled when clean
prewarmFrame -> RunOnce per bounded slice, Disabled when queue is empty
runtimeFrame -> RunAlways only with deadline/poll work, Disabled otherwise
```

The initial state is explicitly written to `Disabled`; state deduplication cannot accidentally leave a newly created OnUpdate frame active.

## Mouseover hot path

### Native Blizzard

```text
ActionButton.OnActionChanged(button)
  -> read current action snapshot
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

No mouseover path performs macro-body parsing, frame/nameplate enumeration, slot scanning, cooldown work for a current shared ability, UI allocation, or diagnostic formatting while capture/debug is inactive.

## GCD correctness

Interrupt readiness is not derived from a GCD heuristic.

Primary sources:

```lua
C_ActionBar.GetActionCooldownDuration(slot, true)
C_Spell.GetSpellCooldownDuration(spellID, true)
```

The second argument explicitly excludes the global cooldown. `isOnGCD=true` is not sufficient to classify an active cooldown as GCD-only because a personal cooldown may overlap. The final `GCDSafetyPolicy` discards all legacy `gcdOnlyHint` inputs and the event path no longer collects them.

`UNIT_SPELLCAST_SUCCEEDED` is only an invalidation signal after confirming the successful source is a current interrupt. It does not prove a GCD transition.

Required live edge case:

```text
interrupt starts personal cooldown
another ability/GCD is active simultaneously
restricted or partially accessible timing context
```

The interrupt must remain not-ready until the ignore-GCD personal duration is actually zero.

## Channel stale-snapshot guard

After a verified channel/empower stop, `UnitChannelInfo` is suppressed until a real start or target/focus identity reset. Ordinary `UnitCastingInfo` remains available. NeverSecret `castBarID` prevents an old delayed stop from clearing a newer cast.

This removes both false glow and repeated readiness work caused by phantom second channels.

## Cooldown filtering and caches

`SPELL_UPDATE_COOLDOWN` accepts exact interrupt families and learned non-global shared categories. Unrelated global-recovery events are discarded. GCD hints are not collected.

Same-spec macro churn retains dormant ability state to avoid allocation churn. A real specialization change reconciles buttons, prunes unreferenced ability records and clears action/spell/pet readiness caches.

## Cooldown Viewer hooks

Pool acquire/set/reset hooks perform only:

```text
read canonical identity
store latest ordinary identity
queue one dirty item record
```

They do not start visual animations, unbind records, or modify addon-owned UI inside Blizzard layout/reset stacks. Reconciliation occurs in the addon `RunOnce` flush.

## Idle and disabled states

When no relevant cast exists and countdown text is disabled:

- cooldown/charge/usability/LoC evaluation is idle;
- deadline/restricted workers are Disabled;
- only bounded action/cast lifecycle state remains active.

When the addon is disabled, readiness work is skipped entirely. Internal counters are dormant unless debug or explicit capture is active.

## Native profiler protocol

Use `C_AddOnProfiler`; never enable legacy `scriptProfile`.

Capture start/end and marker snapshots include session/recent/encounter averages, last/peak time, threshold counters through 1000 ms, enabled state and ticks per second. Threshold counters are cumulative and are subtracted between snapshots. `PeakTime` is shown as start/end/increase, not as a resettable window maximum.

## Attribution matrix

Use equal-duration, equal-input runs:

1. default UI / no third-party addons;
2. Interrupt Glow only;
3. Interrupt Glow plus required action-bar provider;
4. full addon stack.

Record build, location, combat/restriction context, visible nameplate count, macro, target/focus actions, provider versions, worker state, SavedVariables schema and the complete runtime report.

## Startup and persistence cost

Interrupt Glow itself is not LoadOnDemand because it must observe casts automatically. Startup is internally lazy, and the SavedVariables loader reconstructs only a small known-key preference table. No runtime cache is deserialized.

A separate LOD options companion is not introduced before native profiler evidence shows material startup/UI cost; current settings/report UI has no idle OnUpdate and is created only when opened.

## Live acceptance

Required client gates include Quick Heal mouseover stress, GCD/personal-cooldown overlap, phantom-channel regressions, restricted Mythic+/raid/PvP, taint/blocked/forbidden errors, worker idle state, SavedVariables migration, provider load-order/full-stack attribution and no new >5 ms threshold crossings attributable to Interrupt Glow in the fixed-duration primary scenario.
