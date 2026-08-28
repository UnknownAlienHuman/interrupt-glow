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

## Authority and workflow

- Project rules: `AGENTS.md`.
- Shared workflow: `UnknownAlienHuman/wow-addon-engineering-kb@e45366cb0ca56dfe49664daa9f2579e629af0cb3`.
- Platform authority: `Gethe/wow-ui-source@027d26c3406d3de2cbd2b1f67d468fe033a1bcd4` and generated API docs.
- Current field router: `KB/field/README.md` and `KB/field/Active_Upstream_Issues.md`.
- Runtime-dependent claims: in-client evidence through `core/RuntimeProbe.lua`; never inferred from an offline mock or GitHub status.

## Boundaries

- `core/Data.lua` — pinned spec data, reviewed PvP/pet extras and current-spec/runtime identity.
- `core/Buttons.lua` — provider registries, current action classification and shared ability records.
- `core/NativeCallbackPolicy.lua` — managed lifecycle for native EventRegistry callbacks.
- `core/LABAdapter.lua` — exact LAB action hooks plus changed-slot routing to already-indexed buttons.
- `core/Cooldown.lua` — per-source readiness cache, event-time GCD hints, charges and Loss of Control.
- `core/ReadinessPolicy.lua` — hard pet-usability and restricted-LoC policy.
- `core/CastTracking.lua` — event-authoritative target/focus lifecycle and the sole raw cast-interruptibility bridge.
- `core/Glow.lua` — precreated addon-owned overlays and bounded active-only timing drivers.
- `core/CDM.lua` — Cooldown Viewer pooled-item lifecycle.
- `core/RuntimeProbe.lua` — explicit build/context/provider/secrecy/state/profiler evidence boundary.
- `core/Events.lua` — player-login gating, unit-identity resets, optional-provider lifecycle and frame batching.

## Lifecycle invariant

Public callback/registry surfaces take priority over hooks. Native action feedback uses `EventUtil.CreateCallbackHandleContainer()` when supported and unregisters symmetrically. Permanent `hooksecurefunc` integrations attach once and are behaviorally gated after detach.

Optional providers wait for a verified load surface. Existing registries are enumerated once; no provider is polled. Visual objects are created outside combat and reused.

### Event-authoritative channel lifecycle

Current active issue family `WOWUI-2026-005` shows that `UnitChannelInfo` may report a stale or phantom channel after a real stop. Therefore:

```text
CHANNEL/EMPOWER_START
    -> clear suppression
    -> take one current snapshot

CHANNEL/EMPOWER_STOP
    -> compare NeverSecret castBarID with current state
    -> establish channel snapshot suppression
    -> clear cast synchronously without polling

UNIT_FLAGS / UNIT_FACTION / TARGETABLE_CHANGED after stop
    -> UnitCastingInfo may still establish an ordinary cast
    -> UnitChannelInfo is ignored while suppression is active

PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED / PLAYER_ENTERING_WORLD
    -> reset unit identity
    -> permit one fresh mid-cast snapshot
```

A delayed stop carrying an older `castBarID` cannot clear a newer cast. This guard is retired only after named-build retesting of the public #777/#784/#834 reproductions.

## Secret invariant

Potentially secret `notInterruptible` may travel only through:

```text
UnitCastingInfo / UnitChannelInfo
    -> CastTracking:ApplyInterruptibility(local value)
    -> Glow:ApplyUnitInterruptibility(local value)
    -> childRegion:SetAlphaFromBoolean(local value, 0, 255)
```

The secret-carrying child region is never animated or read back. Candidate state is applied to its ordinary parent. Raw secret-capable payloads are never stored, formatted, logged, table-keyed, queued, returned through an internal bus, or passed through a `pcall` result lane.

Cooldown, charge, usability and Loss-of-Control payloads are normalized to ordinary flags. Restricted LoC and inaccessible usability are hard fail-closed gates.

The repository does not register `SPELL_SECRECY_CHANGED`: that event remains unconfirmed in the pinned generated docs and implementation. Explicit probes record current policy instead.

## Performance invariant

Ordinary mouseover, cooldown and cast paths never perform:

- frame or nameplate enumeration;
- macro-body parsing;
- a global 540-slot scan;
- Cooldown Viewer child-tree traversal;
- frame creation in combat;
- diagnostic formatting while capture/debug is inactive.

The LAB `ACTIONBAR_SLOT_CHANGED` path is a bounded diff:

```text
changed slot -> buttonsBySlot[slot] -> dirty existing buttons only
```

Readiness and timing drivers sleep unless a relevant cast or enabled countdown can use the result.

## Runtime evidence invariant

`/iglow capture start` records an explicit scenario. Native profiler counters are application-session cumulative, so the probe stores start/end snapshots and subtracts threshold counts; it never claims to reset Blizzard counters. Reports include provider state, restriction transitions, normalized channel suppression, all threshold counters through 1000 ms, and marker snapshots.

The probe is evidence for one build/context, not a permanent whitelist or substitute for Mythic+, raid, arena/BG, taint, provider and upstream-regression testing.
