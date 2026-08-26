# Architecture — Interrupt Glow 1.1

```text
Blizzard callback / fixed-unit event / targeted post-hook
                          |
                          v
                    Integration
                          |
                          v
      plain button, ability, cast and cooldown state
                          |
                          v
             per-button candidate decision
                          |
                          v
   ordinary parent alpha × secret child alpha gate
```

## Boundaries

- `core/Data.lua` — pinned spec data, aliases and current-spec/runtime identity.
- `core/Buttons.lua` — provider registries, current action classification and shared ability records.
- `core/CastTracking.lua` — target/focus cast state and one-shot secret interruptibility bridge.
- `core/Cooldown.lua` — per-source readiness cache, event-time GCD hints, charges and LoC.
- `core/Glow.lua` — precreated addon-owned overlays; no Blizzard state discovery.
- `core/CDM.lua` — Cooldown Viewer pooled-item lifecycle.
- `core/Events.lua` — lazy registration, bounded routing and one-frame batching.

## Secret invariant

Potentially secret `notInterruptible` may travel only through:

```text
UnitCastingInfo / UnitChannelInfo
    -> CastTracking:ApplyInterruptibility(local value)
    -> Glow:ApplyUnitInterruptibility(local value)
    -> childRegion:SetAlphaFromBoolean(local value, 0, 255)
```

The secret-carrying child region is never animated or read back. Candidate state is applied to its ordinary parent frame.

The raw value must never be:

- compared before `canaccessvalue`;
- stored in addon state or a table;
- formatted or logged;
- returned through an internal event system;
- passed through a `pcall` result lane.

Cooldown and LoC payloads are normalized into plain readiness/restriction flags. Inaccessible LoC fails closed.

## Performance invariant

Ordinary mouseover, cooldown and cast paths must never call:

- `EnumerateFrames`;
- `C_NamePlate.GetNamePlates`;
- macro-body parsing APIs;
- a global 540-slot scan;
- a Cooldown Viewer child-tree scan;
- `CreateFrame` while in combat.

The current Blizzard spec table contains at most two interrupt families per spec. Cooldown work therefore scales with active abilities, not physical buttons.
