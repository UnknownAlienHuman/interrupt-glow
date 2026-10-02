# Architecture — Interrupt Glow 1.1

```text
Blizzard callback / fixed-unit event / targeted slot diff / post-hook
                                |
                                v
                          Integration
                                |
                                v
            plain button, ability, cast and readiness state
                                |
                                v
                   per-button candidate decision
                                |
                                v
         ordinary parent alpha × secret child alpha gate
```

## Authority

- Project rules: `AGENTS.md`.
- Shared workflow: `UnknownAlienHuman/wow-addon-engineering-kb@312085aa8d23dfe283b416ba0f394fef1cae22dd`.
- Platform source: `Gethe/wow-ui-source@027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`, WoW `12.1.0.69497`.
- Field issues: `KB/field/README.md` and `KB/field/Active_Upstream_Issues.md`.
- Runtime-dependent claims require `core/RuntimeProbe.lua` evidence.

## Module boundaries

- `core/Worker.lua` — explicit `Disabled`, `RunOnce` and `RunAlways` OnUpdate policy.
- `core/Shared.lua` — strict SavedVariables schema, access gates, dirty queue and one-frame flush.
- `core/Data.lua` — pinned interrupt data, reviewed PvP/pet exceptions and current-spec identity.
- `core/Buttons.lua` — provider registries, classification and shared canonical ability records.
- `core/NativeCallbackPolicy.lua` — managed EventRegistry callback ownership.
- `core/LABAdapter.lua` — exact LAB action hooks and changed-slot diff routing.
- `core/ActionResolver.lua` — current action snapshot, Assisted Combat exclusion and interrupt classification.
- `core/Cooldown.lua` — per-source duration/charge/LoC readiness primitives.
- `core/ReadinessPolicy.lua` — hard pet/LoC restrictions and one visual pass per batch.
- `core/Usability.lua` — action/spell usability gates.
- `core/GCDSafetyPolicy.lua` — forces all final readiness resolution to ignore legacy GCD hints.
- `core/CachePolicy.lua` — specialization-bounded ability and readiness caches.
- `core/CastTracking.lua` — event-authoritative target/focus lifecycle and sole raw cast-secret bridge.
- `core/Glow.lua` — addon-owned overlays, bounded prewarm and active-only timing driver.
- `core/CDM.lua` — Cooldown Viewer pooled identity; hook stacks only queue dirty records.
- `core/RuntimeProbe.lua` — build/context/provider/worker/policy/secrecy/profiler evidence.
- `core/Events.lua` — player-login gating, identity resets and bounded invalidation.

## Lifecycle invariant

Public callbacks and registries take priority over hooks. Native action feedback uses callback-handle containers when available. Permanent `hooksecurefunc` integrations attach once and have a cheap attached-state guard.

Optional providers wait for verified load surfaces. Existing registries are enumerated once; no provider is polled. Visual objects are created outside combat and reused.

One-shot workers use `RunOnce`; continuous deadline/restricted timing uses `RunAlways` only while needed; idle workers use `Disabled`. The Show/Hide branch is a compatibility/test fallback, not the Retail 12.1 path.

Cooldown Viewer acquire/set/reset hooks update only ordinary identity and queue one addon dirty record. Canonical binding and visual mutation happen on the next addon-owned frame, outside Blizzard reset/layout stacks.

## Persistence invariant

SavedVariables contain only typed preferences plus:

```text
schema
producerVersion
interface
```

Every load rebuilds a known-key table. Legacy slot/cooldown caches, unknown keys, frame references, callback handles, runtime secrecy state and raw payloads are not persisted.

Same-spec conditional macro churn may retain dormant canonical ability state to avoid allocation churn. A real specialization change reconciles all buttons, prunes unreferenced abilities and resets source-readiness caches.

## Cast lifecycle invariant

Active field issue `WOWUI-2026-005` shows that `UnitChannelInfo` can remain stale after a real stop.

```text
CHANNEL/EMPOWER_START
    -> clear suppression
    -> take current snapshot

CHANNEL/EMPOWER_STOP
    -> compare NeverSecret event castBarID
    -> ignore delayed stop for older cast
    -> establish channel suppression
    -> clear normalized state synchronously

later unit-state event
    -> UnitCastingInfo remains allowed
    -> UnitChannelInfo is skipped while suppressed

unit identity change
    -> clear suppression
    -> permit fresh mid-channel snapshot
```

The mitigation is retired only after a named live build passes target-death, Lightning Lasso and Ray of Frost reproductions without it.

## Secret invariant

Potentially secret `notInterruptible` may travel only through:

```text
UnitCastingInfo / UnitChannelInfo
    -> CastTracking local value
    -> Glow:ApplyUnitInterruptibility
    -> childRegion:SetAlphaFromBoolean(value, 0, 255)
```

The secret-carrying child region is never animated or read back. Raw secret-capable values are never stored, formatted, logged, table-keyed, serialized, queued, or passed through a `pcall` result lane.

## Readiness and GCD invariant

Global cooldown is excluded only through:

```lua
C_ActionBar.GetActionCooldownDuration(slot, true)
C_Spell.GetSpellCooldownDuration(spellID, true)
```

`isOnGCD=true` means that the source is considered on GCD; it does not prove absence of an overlapping personal cooldown. Therefore it is never positive readiness evidence. `UNIT_SPELLCAST_SUCCEEDED` is an invalidation signal only.

If the ignore-GCD duration is accessible, zero means ready and positive remaining duration means not ready. If timing is inaccessible, readiness falls back conservatively through NeverSecret status/usability/LoC gates; an active restricted cooldown cannot become ready merely because `isOnGCD` is true.

## Performance invariant

Ordinary mouseover, cooldown and cast paths never perform:

- frame/nameplate enumeration;
- macro-body parsing;
- global action-slot scanning;
- Cooldown Viewer child-tree traversal;
- frame creation in combat;
- diagnostic formatting while capture/debug is inactive.

Readiness and timing workers sleep unless a relevant cast or enabled countdown can use the result.

## Validation boundary

Local scripts prove syntax and modeled state transitions only. GitHub Actions workflows remain absent. WoW FPS, taint, protected execution, contextual SecretValue behavior, GCD/personal-cooldown overlap, provider attribution and upstream-workaround retirement require explicit live-client captures.
