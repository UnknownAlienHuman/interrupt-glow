# Code graph — Interrupt Glow 1.1

```text
InterruptGlow.toc
  -> Core.lua
  -> core/Shared.lua
       owns DB migration, access gates, dirty queues and one-frame flush
  -> core/Data.lua
       owns generated spec interrupt map, aliases and runtime canonical IDs
  -> core/Debug.lua
       owns normalized counters/logs/profiler output
  -> core/Glow.lua
       owns precreated target/focus alpha-gate overlays and shared time driver
  -> core/Buttons.lua
       owns Blizzard/LAB/Dominos/ButtonForge/pet/CDM records
  -> core/Cooldown.lua
       owns shared per-ability readiness and event-time GCD hints
  -> core/CastTracking.lua
       owns fixed target/focus cast watchers and the raw secret visual bridge
  -> core/CDM.lua
       owns Cooldown Viewer pooled-item lifecycle
  -> core/Events.lua
       defers runtime initialization to PLAYER_LOGIN and routes bounded signals
  -> core/Slash.lua
  -> Options.lua
       registers a bare Settings canvas; controls are built on first show
```

## Runtime data flow

```text
Action provider callback
  -> Buttons:ObserveButton / MarkButtonDirty
  -> Buttons:ReconcileRecord
  -> shared AbilityState
  -> Cooldown:RefreshAbility
  -> Glow:RefreshRecord

Target/focus UNIT_SPELLCAST event
  -> CastTracking:RefreshUnit
  -> plain active/hostile/castBarID state
  -> raw notInterruptible (local only)
  -> Glow:ApplyUnitInterruptibility
  -> Texture:SetAlphaFromBoolean(raw, 0, 255)

SPELL_UPDATE_COOLDOWN
  -> Data:ShouldRefreshForCooldownEvent
  -> Cooldown:CaptureGCDHints (inside event dispatch)
  -> one-frame dirty queue
  -> one evaluation per distinct ability source
```

## Dependency rules

```text
Data / Shared
    ↓
Integration (Buttons, CastTracking, CDM, Events)
    ↓
Normalized ability/cast state
    ↓
Feature logic (Cooldown)
    ↓
Addon-owned UI (Glow)
```

Forbidden reverse edges:

- `Glow` must not discover Blizzard frames or read cast/cooldown APIs.
- `Cooldown` must not create regions or register provider hooks.
- `Data` must not load `Blizzard_CooldownBroadcaster` at runtime.
- provider callbacks must not start global scans.
- raw SecretValue must not leave the direct cast API → alpha-sink call chain.
