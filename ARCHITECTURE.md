# Architecture

## Ownership

Each behavior has one implementation owner. Modules call explicit integration methods; they do not replace one another's implementations after load.

| File | Responsibility |
|---|---|
| `Core.lua` | Addon namespace and version from TOC |
| `core/Worker.lua` | Disabled / RunOnce / RunAlways worker modes |
| `core/Shared.lua` | Typed preferences, access helpers, diagnostic-counter ownership and dirty flush |
| `core/Data.lua` | Pinned interrupt snapshot, exact-known extras, runtime families and bounded match caches |
| `core/Buttons.lua` | Provider orchestration, physical records, canonical binding and source selection |
| `core/LABAdapter.lua` | LAB callback ownership and exact action hooks; routes slot events through ConditionalActions |
| `core/ActionResolver.lua` | Current action/direct-spell classification; no macro-body parsing |
| `core/ConditionalActions.lua` | Shared known-button slot index, deferred identity and stale-visual guard |
| `core/Cooldown.lua` | Duration, charges, Loss of Control, final readiness and one record commit |
| `core/Usability.lua` | Access-gated usability queries and targeted usability invalidation |
| `core/CastTracking.lua` | Fixed target/focus watchers, cast sequence and raw interruptibility bridge |
| `core/Glow.lua` | Access preflight, bounded visual preparation, opaque alpha sink, parent animation and active timing |
| `core/CDM.lua` | Cooldown Viewer acquisition/reset identity and provider lifecycle |
| `core/RuntimeLifecycle.lua` | Master enable, disable and deferred combat activation |
| `core/Events.lua` | Login, player/unit signals, runtime event registration and restriction invalidation |
| `core/Debug.lua`, `core/RuntimeProbe.lua` | Opt-in normalized diagnostics and native profiler evidence |
| `core/Slash.lua`, `Options.lua` | Commands and lazy native Canvas Settings |

## Initialization and persistence

The TOC opts into `LoadSavedVariablesFirst`. Shared validates the loaded table once before consumers capture `IG.DB`. Schema 4 contains typed preferences plus schema, producer version and declared Interface; runtime state is never persisted. Gameplay discovery waits for `PLAYER_LOGIN`.

The master lifecycle owns attachment through login, slash commands and Settings. Disabling unregisters runtime events, detaches provider and fixed-unit callbacks, clears pending work, stops preview and visual workers, and hides existing highlights. The two fixed-unit watcher frames are reused across enable cycles. Regen lifecycle and optional restriction telemetry remain available. Enabling in combat records one pending activation; out-of-combat activation discovers current state once. Optional-provider continuations are deduplicated and recheck current attachment.

## Update transaction

1. A provider callback or fixed-unit event invalidates known ordinary state.
2. `ConditionalActions` marks changing action identities pending. Idle action churn stays in a weak set bounded by observed buttons; active churn enters the shared dirty queue.
3. `Shared:Flush` handles specialization, button identity, cache pruning, cast snapshots, readiness and visuals in order. Newly awakened deferred identities reconcile before cooldown evaluation.
4. `Buttons` chooses one bound source per canonical ability: action, then pet, then direct spell; the lowest source ID breaks ties. No eligible bound source means hidden, restricted, pending readiness. A completely dormant ability can be reused within the same specialization.
5. `Cooldown` evaluates independent duration, charge, Loss of Control and usability gates, then commits one final result to the ability and its physical copies. It never changes source ownership.
6. `Glow` consumes normalized state. A pending identity cannot reuse a prior branch's highlight or countdown. Clearing that guard happens only after successful reconciliation.

A full rebuild seeds runtime interrupt families from action slots before refreshing active CDM pools and secondary spell copies. The current specialization/configuration owns runtime proof; a registry rebuild clears it before reseeding. Negative spell matches are capped at 128 and invalidated when proof changes.

LAB's gated identity snapshot is authoritative for both binding and the shared slot index. Empty, restricted and non-action states cannot fall back to a frame's old `action` field. Its slot events visit only LAB records in the shared index. Equivalent readiness invalidations coalesce before walking active abilities or deferred identities.

## Secret and foreign-object boundaries

Gate values before comparison, formatting, iteration or map keys. Gate foreign tables with `canaccesstable` when available and check each consumed field. Current object access is not a permission cached across contexts.

Potentially secret cast `notInterruptible` has one direct presentation route: `UnitCastingInfo` / `UnitChannelInfo` → `CastTracking` → `Glow:ApplyUnitInterruptibility` → `SetAlphaFromBoolean(value, 0, 255)`. Do not retain or log it, route it through `pcall`, read the resulting alpha or animate the child texture. Only the ordinary parent is animated.

Addon visuals are created outside combat and reused. Prewarm counts every inspected queue record, including skipped records. A denied foreign owner is not retried by an OnUpdate loop. CDM acquire/reset hooks only capture ordinary identity and queue reconciliation; the addon does not change visuals inside Blizzard's pool-reset stack.

## Readiness and cast lifecycle

The duration getters receive `ignoreGCD=true`. `isOnGCD` and successful-cast events never prove readiness. Inaccessible usability, charges or Loss of Control are hard fail-closed gates, including when cooldown compatibility is enabled.

Unknown cooldown readiness waits for native invalidation events; it does not keep a periodic access retry alive. A positively known not-ready state without an accessible deadline retains the limited timing fallback while a relevant cast is active.

Synchronous channel/empower stop is authoritative over subsequent channel snapshots. Only a real start or unit identity reset clears suppression. Accessible NeverSecret `castBarID` rejects delayed stops for a different cast. The upstream phantom-channel workaround remains active until its named-client retirement tests pass.

## Evidence

[API review](docs/API_REVIEW.md) owns platform pins and source limits. [Performance model](docs/PERFORMANCE_MODEL.md) describes work bounds; [runtime probe](docs/RUNTIME_PROBE.md) describes client checks. Source shape and offline mocks do not prove live performance or taint safety.
