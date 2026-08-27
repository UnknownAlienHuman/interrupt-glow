# Architecture — Interrupt Glow 1.1

```text
Blizzard callback / fixed-unit event / targeted slot diff / post-hook
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

- `core/Data.lua` — pinned spec data, verified PvP/pet extras and current-spec/runtime identity.
- `core/Buttons.lua` — provider registries, current action classification and shared ability records.
- `core/LABAdapter.lua` — exact LAB `UpdateAction` hooks plus `ACTIONBAR_SLOT_CHANGED` diff routing to already-indexed buttons. It never scans action slots or frames.
- `core/Cooldown.lua` — per-source readiness cache, event-time GCD hints, charges and Loss of Control.
- `core/ReadinessPolicy.lua` — hard pet-usability and restricted-LoC policy that optimistic cooldown compatibility cannot bypass.
- `core/CastTracking.lua` — target/focus cast state and one-shot secret interruptibility bridge.
- `core/Glow.lua` — precreated addon-owned overlays and bounded active-only timing drivers; no Blizzard state discovery.
- `core/CDM.lua` — Cooldown Viewer pooled-item lifecycle.
- `core/Events.lua` — player-login gating, optional-provider lifecycle, bounded routing and one-frame batching.

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

Cooldown, charge, pet-usability and Loss-of-Control payloads are normalized into plain readiness/restriction flags. Restricted LoC and inaccessible pet usability are hard fail-closed gates.

## Performance invariant

Ordinary mouseover, cooldown and cast paths must never call:

- `EnumerateFrames`;
- `C_NamePlate.GetNamePlates`;
- macro-body parsing APIs;
- a global 540-slot scan;
- a Cooldown Viewer child-tree scan;
- `CreateFrame` while in combat.

`ACTIONBAR_SLOT_CHANGED` is not used as a global discovery signal. The only addon subscription is the LAB adapter's exact diff route:

```text
changed slot -> buttonsBySlot[slot] -> dirty those existing buttons only
```

The 50 ms expiry and 250 ms restricted fallback driver is asleep unless a relevant target/focus cast exists; the 200 ms text path additionally runs only when custom countdown text is enabled.

The current Blizzard specialization table contains at most two ordinary interrupt families per spec. Cooldown work therefore scales with active canonical abilities, not physical buttons.

## Validation boundary

Local scripts may catch syntax, source drift and state-machine mistakes. GitHub Actions workflows are intentionally absent because they cannot run WoW, secure execution, restricted SecretValue contexts, taint logging or real FPS measurements. Live-client acceptance remains mandatory.
