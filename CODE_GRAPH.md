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
       optional normalized log and on-demand profiler output
  -> core/Glow.lua
       precreated target/focus alpha gates and relevant-cast-only time driver
  -> core/Buttons.lua
       provider registries, canonical ability records and custom/pet/CDM adapters
  -> core/LABAdapter.lua
       exact LAB UpdateAction hooks + changed-slot diff index
  -> core/ActionResolver.lua
       current slot feedback snapshot, dedupe and interrupt classification
  -> core/Cooldown.lua
       per-source readiness, event-time GCD hints, charges and LoC
  -> core/ReadinessPolicy.lua
       hard pet/LoC gates and one visual pass per frame
  -> core/CastTracking.lua
       fixed target/focus watchers and raw secret visual bridge
  -> core/CDM.lua
       Cooldown Viewer pooled-item lifecycle
  -> core/Events.lua
       PLAYER_LOGIN gating, optional-provider lifecycle and bounded invalidation
  -> core/Slash.lua
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

Dominos/ButtonForge/provider callback
  -> provider-owned registry/normalized resolved state
  -> one dirty button

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

SPELL_UPDATE_COOLDOWN
  -> Data exact spell/category filter
  -> event-time GCD hint
  -> one-frame dirty queue
  -> one evaluation per distinct active ability source
```

## Sleep states

```text
no relevant cast + countdown off
  -> expiry/restricted driver hidden

addon disabled
  -> cooldown/charge/LoC/pet-readiness evaluation skipped
  -> internal counters dormant

no optional provider loaded
  -> no polling; ContinueOnAddOnLoaded callback only
```

## Dependency rules

```text
Shared / Data / DiagnosticsPolicy
    ↓
Integration (Buttons adapters, CastTracking, CDM, Events)
    ↓
Normalized ability/cast state
    ↓
Readiness policy
    ↓
Addon-owned Glow UI
```

Forbidden reverse edges:

- `Glow` must not discover Blizzard frames or read cast/cooldown APIs.
- `Cooldown` must not create regions or register provider hooks.
- `Data` must not load `Blizzard_CooldownBroadcaster` at runtime.
- provider callbacks must not start global scans.
- raw SecretValue must not leave the direct cast API → alpha-sink call chain.
- local scripts and GitHub infrastructure must not be represented as WoW acceptance tests.
