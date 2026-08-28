# Code graph — Interrupt Glow 1.1

```text
InterruptGlow.toc
  -> Core.lua
  -> core/Shared.lua
       DB migration, access gates, dirty queues and one-frame flush
  -> core/DiagnosticsPolicy.lua
       dormant production counters and safe chat boundary
  -> core/Data.lua
       generated ordinary spec map + reviewed PvP/pet extras + category cache
  -> core/Debug.lua
       normalized log, copyable report and native profiler snapshots/deltas
  -> core/RuntimeProbe.lua
       build/context/provider/secrecy/cast/readiness/profiler evidence
  -> core/Glow.lua
       precreated target/focus alpha gates and relevant-cast-only time driver
  -> core/Buttons.lua
       provider registries, canonical ability records and custom/pet/CDM adapters
  -> core/NativeCallbackPolicy.lua
       EventRegistry handle-container lifecycle for native action feedback
  -> core/LABAdapter.lua
       exact LAB UpdateAction hooks + changed-slot diff index
  -> core/ActionResolver.lua
       current slot feedback snapshot, dedupe and interrupt classification
  -> core/Cooldown.lua
       per-source readiness, event-time GCD hints, charges and LoC
  -> core/ReadinessPolicy.lua
       hard pet/LoC gates and one visual pass per frame
  -> core/Usability.lua
       action/spell usability policy and targeted invalidation
  -> core/CastTracking.lua
       event-authoritative target/focus lifecycle + raw secret visual bridge
  -> core/CDM.lua
       Cooldown Viewer pooled-item lifecycle
  -> core/Events.lua
       PLAYER_LOGIN gating, unit-identity resets, restriction evidence and bounded invalidation
  -> core/Slash.lua
       user controls and runtime capture commands
  -> Options.lua
       bare Settings canvas; controls built on first show
```

## Action/readiness flow

```text
Blizzard native callback
  -> ActionResolver reads one current slot snapshot
  -> unchanged: stop
  -> changed: one dirty button

LAB conditional macro
  -> ACTIONBAR_SLOT_CHANGED(slot)
  -> LABAdapter buttonsBySlot[slot]
  -> dirty only existing buttons for that slot

Dirty button
  -> Buttons:ReconcileRecord
  -> shared AbilityState
  -> generation-valid readiness reused or one bounded evaluation queued
  -> Glow:RefreshRecord
```

## Cast flow

```text
START / INTERRUPTIBILITY event
  -> fixed target/focus watcher
  -> UnitCastingInfo / permitted UnitChannelInfo snapshot
  -> NeverSecret presence/castBarID normalization
  -> raw notInterruptible remains local
  -> childTexture:SetAlphaFromBoolean(raw, 0, 255)

CHANNEL_STOP / EMPOWER_STOP
  -> read only NeverSecret event castBarID
  -> ignore stale stop for an older cast
  -> set channel snapshot suppression
  -> clear normalized state synchronously

later unit-state event while suppressed
  -> UnitCastingInfo remains permitted
  -> UnitChannelInfo skipped

unit identity change or real channel start
  -> clear suppression
  -> permit one fresh snapshot
```

## Runtime evidence flow

```text
/iglow capture start
  -> clear addon-owned counters
  -> native profiler baseline

capture marks
  -> elapsed marker + native profiler snapshot

restriction transition
  -> record accessible event payload
  -> marker snapshot

/iglow capture stop
  -> native profiler final snapshot
  -> subtract cumulative threshold counters
  -> preserve PeakTime start/end/increase
  -> copyable report with no raw SecretValue
```

## Callback lifecycle

```text
Buttons:AttachNative
  -> NativeCallbackPolicy
  -> EventUtil.CreateCallbackHandleContainer when supported
  -> exact unregister on Detach
  -> owner-based fallback otherwise

Permanent hooksecurefunc integrations
  -> attach once
  -> cheap attached guard after detach
```

## Validation boundary

Local scripts catch syntax, source drift and modeled state-machine errors. GitHub Actions workflows remain absent. WoW FPS, taint, protected execution, contextual SecretValue behavior, provider attribution and upstream channel-fix retirement require explicit live-client captures.
