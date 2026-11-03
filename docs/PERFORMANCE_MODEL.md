# Work bounds and performance validation

This document describes the implementation's work bounds. No live CPU/FPS improvement is claimed without matched client captures.

## Work topology

| Signal | Work |
|---|---|
| Target/focus cast event | One fixed-unit snapshot and bound interrupt records; stop events clear state synchronously |
| Native action feedback | No action/cooldown query in the callback; one pending known button, or one idle deferred identity |
| LAB action change | Exact `UpdateAction` post-hook or already-indexed buttons for the event slot |
| Dominos / ButtonForge change | The named provider button or indexed slot |
| Cooldown / charge / usability event | One coalesced pass over active canonical abilities when a cast or countdown needs it |
| CDM acquire/reset | Ordinary identity capture and deferred reconciliation; no synchronous visual changes |
| Visual preparation | At most 16 queue records inspected per RunOnce slice, including skipped records |

Copies of one ability share readiness. A source transition is selected by Buttons and consumed by Cooldown; it is not repeatedly arbitrated through policy wrappers. A true specialization change prunes dormant abilities and resets source caches. Unrelated negative spell matches are capped at 128 and invalidated with runtime proof.

## Workers and cadence

| Worker | Active mode | Idle state |
|---|---|---|
| Shared dirty flush | RunOnce | Disabled |
| Prewarm | RunOnce per bounded slice | Disabled |
| Accessible deadlines / known not-ready state without timing / countdowns | One shared RunAlways worker while needed | Disabled |

The timing worker checks accessible deadlines at 0.05 s, a positively known not-ready state without readable timing during a relevant cast at 0.25 s, and integer countdown text at 0.20 s. Fully unknown readiness does not start this fallback; native invalidation events request a fresh bounded pass. These are configured intervals, not measured end-to-end latency guarantees. A frame budget, frame rate and client scheduling still determine actual latency.

The normal path does not enumerate frames or nameplates, scan all action slots, parse macro bodies, allocate visuals in combat or format diagnostics while logging/capture is off. LAB and conditional-action notifications share one known-button slot index. Readiness invalidation bursts coalesce before walking active abilities and deferred identities. When no relevant cast exists and countdowns are disabled, readiness evaluation and its timer sleep. The master switch detaches runtime traffic and stops pending visual work.

## Readiness correctness precedes cadence

Duration getters use `ignoreGCD=true`; no GCD hint map exists. A successful cast only invalidates affected readiness. Inaccessible charges, usability and Loss of Control stay fail-closed. No timer probes denied object access or treats opaque visual output as feedback.

Permission checks also cover already-created visual destinations. Once denied, a record makes no further object queries from render/timing passes until an explicit recovery signal. If every bound copy of an ability is blocked, its deadlines and fallback polling do not keep the worker awake; an unblocked sibling retains normal timing work.

A pending conditional identity suppresses its previous highlight/countdown until reconciliation succeeds. This guard also applies when a unit refresh occurs between the provider callback and the dirty pass.

## Measurement protocol

Use `/iglow capture start <scenario>`, manual markers and an out-of-combat stop. Run equal-duration, equal-input comparisons for default UI, this addon alone, this addon with one action-bar provider, and the normal addon stack. Retain actual build, addon revision, provider versions, UI state, scenario and taint/error output.

`C_AddOnProfiler` averages and peaks are snapshots. Only cumulative `CountTimeOver*` counters are subtracted. The report retains start/end `PeakTime` and whether a new session peak occurred; it does not claim an interval maximum or a profiler reset. Unavailable native metrics remain unavailable, not zero.

Client acceptance includes Quick Heal mouseover bursts, personal cooldown plus GCD overlap, restricted M+/raid/PvP, provider late load, repeated enable/disable, CDM pool reuse, SavedVariables migration, preview cleanup and idle workers. Follow [runtime procedures](RUNTIME_PROBE.md). All client gates for this revision remain **NOT-RUN** until captured.
