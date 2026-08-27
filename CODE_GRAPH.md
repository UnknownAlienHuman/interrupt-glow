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
       optional normalized log, copyable report window and profiler output
  -> core/RuntimeProbe.lua
       session-only build/context/secrecy/state/profiler evidence
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
       fixed target/focus watchers and raw secret visual bridge
  -> core/CDM.lua
       Cooldown Viewer pooled-item lifecycle
  -> core/Events.lua
       PLAYER_LOGIN gating, optional-provider lifecycle, restriction evidence and bounded invalidation
  -> core/Slash.lua
       user controls and runtime capture commands
  -> Options.lua
       bare Settings canvas; controls built on first show
```

## Runtime data flow

```text
Blizzard native callback
  -> ActionResolver reads one current slot snapshot
  -> unchanged: stop
  -> changed: one dirty button

LAB conditional macro
  -> ACTIONBAR_SLOT_CHANGED(slot)
  -> LABAdapter buttonsBySlot[slot]
  -> only existing buttons for that slot become dirty

Dirty button
  -> Buttons:ReconcileRecord
  -> shared dormant-capable AbilityState
  -> generation-valid readiness reused or one cooldown evaluation queued
  -> Glow:RefreshRecord

Target/focus UNIT_SPELLCAST event
  -> CastTracking direct UnitCastingInfo/UnitChannelInfo
  -> NeverSecret active/castBarID state
  -> raw notInterruptible remains local
  -> childTexture:SetAlphaFromBoolean(raw, 0, 255)
  -> ordinary parent receives candidate alpha/animation

Explicit runtime capture
  -> session counters enabled
  -> build/context/restriction/secrecy/normalized-state/profiler snapshot
  -> copyable addon-owned report window
  -> no raw SecretValue retained
```

## Lifecycle

```text
Buttons:AttachNative
  -> NativeCallbackPolicy
  -> EventUtil.CreateCallbackHandleContainer when supported
  -> exact unregister on Detach
  -> legacy owner-based callback fallback otherwise

Permanent hooksecurefunc integrations
  -> attach-once
  -> cheap attached flag in post-hook
  -> no attempt to unhook unsupported permanent hooks
```

## Validation boundary

Local scripts may catch syntax, source drift and state-machine errors. GitHub Actions workflows remain absent. WoW FPS, taint, protected execution and contextual SecretValue behavior require `/iglow capture ...` plus live-client smoke tests.
