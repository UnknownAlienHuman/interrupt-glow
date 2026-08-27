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
- Shared workflow: `UnknownAlienHuman/wow-addon-engineering-kb@bb13f191903ca4ff63a4c93535edb9eacab9630d`.
- Platform authority: `Gethe/wow-ui-source@027d26c3406d3de2cbd2b1f67d468fe033a1bcd4` and generated API docs.
- Runtime-dependent claims: in-client evidence through `core/RuntimeProbe.lua`; never inferred from an offline mock or GitHub status.

## Boundaries

- `core/Data.lua` — pinned spec data, reviewed PvP/pet extras and current-spec/runtime identity.
- `core/Buttons.lua` — provider registries, current action classification and shared ability records.
- `core/NativeCallbackPolicy.lua` — managed lifecycle for native EventRegistry callbacks.
- `core/LABAdapter.lua` — exact LAB `UpdateAction` hooks plus `ACTIONBAR_SLOT_CHANGED` diff routing to already-indexed buttons. It never scans action slots or frames.
- `core/Cooldown.lua` — per-source readiness cache, event-time GCD hints, charges and Loss of Control.
- `core/ReadinessPolicy.lua` — hard pet-usability and restricted-LoC policy that optimistic cooldown compatibility cannot bypass.
- `core/CastTracking.lua` — target/focus cast state and one-shot secret interruptibility bridge.
- `core/Glow.lua` — precreated addon-owned overlays and bounded active-only timing drivers; no Blizzard state discovery.
- `core/CDM.lua` — Cooldown Viewer pooled-item lifecycle.
- `core/RuntimeProbe.lua` — explicit diagnostic boundary for build/context/secrecy/state/profiler evidence.
- `core/Events.lua` — player-login gating, optional-provider lifecycle, bounded routing and one-frame batching.

## Lifecycle invariant

Public callback/registry surfaces take priority over hooks. When `RegisterCallbackWithHandle` is available, native action feedback is owned by an `EventUtil.CreateCallbackHandleContainer()` and is symmetrically removed on detach. Permanent `hooksecurefunc` integrations are attach-once and behaviorally gated after detach.

Optional providers wait for their verified load surface. Existing registries are enumerated once; no provider is polled. Visual objects are created outside combat and reused.

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

The repository does not register `SPELL_SECRECY_CHANGED`: that event is not confirmed in the pinned 12.1.0.69497 generated docs or implementation. Secrecy policy is recorded by explicit current-client probes instead of an invented event contract.

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

## Runtime evidence invariant

`/iglow capture start` is explicit session instrumentation. While active it records only ordinary/access-confirmed values, normalized state, counters and Blizzard profiler metrics. `ADDON_RESTRICTION_STATE_CHANGED` payloads are recorded as observed transitions without querying restriction state during dispatch. Stopping a capture disables internal counters and freezes a copyable report.

The probe is evidence for one build/context, not a permanent spell whitelist or a substitute for Mythic+, raid, arena/BG, taint and provider-specific testing.
