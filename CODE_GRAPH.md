# Code graph — Interrupt Glow 1.1

```text
InterruptGlow.toc
  -> Core.lua
  -> core/Worker.lua
       Disabled / RunOnce / RunAlways OnUpdate policy
  -> core/Shared.lua
       strict SavedVariables schema + dirty RunOnce flush
  -> core/DiagnosticsPolicy.lua
       dormant counters and safe chat boundary
  -> core/Data.lua
       spec/PvP/pet interrupt identities + event-category filter
  -> core/Debug.lua
       copyable report + native profiler snapshots/deltas
  -> core/RuntimeProbe.lua
       build/context/provider/worker/policy/secrecy/readiness evidence
  -> core/Glow.lua
       target/focus alpha gates + RunOnce prewarm + active timing worker
  -> core/Buttons.lua
       provider registries + canonical ability records
  -> core/NativeCallbackPolicy.lua
       managed native EventRegistry callback lifecycle
  -> core/LABAdapter.lua
       exact LAB action hooks + changed-slot diff index
  -> core/ActionResolver.lua
       current action snapshot + interrupt classification
  -> core/Cooldown.lua
       duration/charge/LoC readiness primitives
  -> core/ReadinessPolicy.lua
       hard pet/LoC restrictions + batched visual scheduling
  -> core/Usability.lua
       action/spell usability policy
  -> core/GCDSafetyPolicy.lua
       discard legacy GCD hints; never use isOnGCD as ready proof
  -> core/CachePolicy.lua
       prune dormant abilities and reset readiness caches on spec change
  -> core/CastTracking.lua
       event-authoritative target/focus lifecycle + raw secret sink path
  -> core/CDM.lua
       pooled identity changes -> one dirty record
  -> core/Events.lua
       login gating, identity resets and bounded invalidation
  -> core/Slash.lua
       user controls and runtime capture commands
  -> Options.lua
       controls built on first show
```

## Action and readiness flow

```text
native/LAB/provider action signal
  -> compare current resolved identity
  -> unchanged: stop
  -> changed: dirty one observed button

RunOnce dirty flush
  -> reconcile physical button
  -> bind/unbind canonical AbilityState
  -> mark readiness pending when required
  -> evaluate each active source once
  -> refresh ordinary candidate gates
```

## GCD flow

```text
SPELL_UPDATE_COOLDOWN
  -> exact/shared-category filter
  -> dirty readiness without GCD hint
  -> Get*CooldownDuration(..., ignoreGlobalCooldown=true)

legacy isOnGCD hint
  -> GCDSafetyPolicy forces false before final resolver
  -> cannot produce ready=true
```

## Cast flow

```text
START / INTERRUPTIBILITY
  -> fixed target/focus watcher
  -> accessible presence/castBarID normalization
  -> raw notInterruptible stays local
  -> child:SetAlphaFromBoolean(raw, 0, 255)

CHANNEL/EMPOWER STOP
  -> compare NeverSecret event castBarID
  -> ignore stale old stop
  -> suppress later UnitChannelInfo snapshots
  -> clear normalized state synchronously

unit identity change or real new start
  -> clear suppression
  -> permit fresh snapshot
```

## Cooldown Viewer flow

```text
Blizzard pool acquire/set/reset hook
  -> read latest ordinary canonical identity
  -> store identity only
  -> dirty one item record

addon RunOnce flush
  -> canonical bind/unbind
  -> addon-owned visual update
```

## Worker states

```text
flush clean             -> Disabled
flush dirty             -> RunOnce
prewarm queue nonempty  -> RunOnce slices
prewarm queue empty     -> Disabled
active deadline/poll    -> RunAlways
no visible timing work  -> Disabled
```

## Persistence flow

```text
raw InterruptGlowDB
  -> read known typed preferences only
  -> clamp debugKeep
  -> add schema/producer/interface metadata
  -> replace SavedVariables root
  -> no runtime caches survive reload
```

## Runtime evidence flow

```text
capture start
  -> addon counter reset + native profiler baseline
capture mark
  -> marker + profiler snapshot
capture stop
  -> final snapshot + cumulative threshold deltas
report
  -> build/provider/worker/policy/cast/readiness/secrecy evidence
```

## Validation boundary

Local scripts catch syntax and modeled state-machine errors. GitHub Actions workflows remain absent. WoW FPS, taint, protected execution, GCD overlap, contextual SecretValue behavior, provider attribution and upstream workaround retirement require live-client captures.
