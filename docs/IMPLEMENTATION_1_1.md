# Interrupt Glow 1.1 implementation authority

Baseline: WoW Retail `12.1.0.69497`, Interface `120100`, Blizzard UI commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`.

Shared workflow: `UnknownAlienHuman/wow-addon-engineering-kb@312085aa8d23dfe283b416ba0f394fef1cae22dd`.

## Startup and workers

- Interrupt Glow is not LoadOnDemand because target/focus observation must begin automatically.
- Gameplay registration and provider discovery wait for `EventUtil.ContinueOnPlayerLogin`.
- `C_AddOns.IsAddOnLoaded` uses its second, fully-loaded return.
- Existing provider registries are discovered once; late providers use verified load callbacks.
- Native action feedback uses a callback-handle container when supported.
- Settings/report UI and cooldown text are lazy.
- No addon-owned visual object is created in combat.
- `core/Worker.lua` maps dirty flush and prewarm slices to `RunOnce`, active timing to `RunAlways`, and idle state to `Disabled`.

## Persistence

SavedVariables schema 3 is reconstructed from known typed preferences on every load. It stores producer version and Interface metadata and discards unknown/legacy fields. Runtime ability/cooldown caches, frames, callback state, secrecy policy and raw values are never persisted.

## Integration points

- native buttons: `ActionButton.OnActionChanged`, deduplicated by current action snapshot;
- native discovery: `ActionBarButtonEventsFrame:ForEachFrame` once after login;
- LibActionButton: exact `UpdateAction` post-hooks and `buttonsBySlot[slot]` diff routing;
- Dominos: indexed registry and targeted action/slot post-hooks;
- ButtonForge: allocation, resolved refresh and clear-command lifecycle;
- pet buttons: fixed ten-slot registry refreshed by pet lifecycle events;
- target/focus: fixed `RegisterUnitEvent(event, unit)` watchers using unit varargs;
- Cooldown Viewer: pooled acquire/set/reset hooks that queue identity changes for next-frame reconciliation.

There is no automatic frame enumeration, action-slot sweep, nameplate traversal, macro-body parsing, or Cooldown Viewer child-tree scan.

## Canonical ability caches

Same-spec conditional-macro churn preserves dormant canonical ability state to avoid repeated allocation and GC. A real specialization change:

1. refreshes current-spec data;
2. reconciles every observed button;
3. prunes unreferenced abilities;
4. resets action/spell/pet readiness caches;
5. performs a fresh bounded readiness pass only if its result can be visible.

## Cast lifecycle and active upstream mitigation

Active field issue `WOWUI-2026-005` tracks stale/phantom `UnitChannelInfo` after a real channel end.

```text
CHANNEL/EMPOWER_START
  -> clear suppression
  -> snapshot current cast

CHANNEL/EMPOWER_STOP
  -> read only NeverSecret event castBarID
  -> ignore delayed stop belonging to an older cast
  -> establish channel snapshot suppression
  -> clear normalized state synchronously

later unit-state event
  -> UnitCastingInfo remains available
  -> UnitChannelInfo is skipped while suppressed

PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED / PLAYER_ENTERING_WORLD
  -> reset unit identity and suppression
  -> permit fresh mid-channel snapshot
```

The workaround remains until a named live build passes target-death, Lightning Lasso and Ray of Frost reproductions without it.

## Runtime data authority

- slot-backed classification: `C_ActionBar.IsInterruptAction(slot)`;
- current resolved identity: `GetActionInfo(slot)`;
- Assisted Combat actions are excluded;
- direct spell, pet and Cooldown Viewer classification uses pinned current-spec data plus reviewed PvP/pet exceptions;
- unknown authoritative slot IDs are learned for the current specialization/session only.

## Readiness rules

Readiness is evaluated only while:

```text
addon enabled
AND
(relevant target/focus cast OR custom countdown enabled)
```

A new relevant cast, identity change, re-enable, policy change or countdown enable marks active abilities `readinessPending`. Glow and custom text fail closed until a fresh pass completes.

The decision combines:

- ignore-GCD action/spell duration;
- charges and recharge duration;
- action/spell usability;
- intrinsic pet usability;
- Loss of Control;
- conservative policy for restricted ordinary cooldown timing.

Inaccessible usability, pet state and Loss of Control are hard fail-closed restrictions. Optimistic cooldown compatibility cannot override them.

## GCD contract

Global cooldown exclusion is performed only by:

```lua
C_ActionBar.GetActionCooldownDuration(slot, true)
C_Spell.GetSpellCooldownDuration(spellID, true)
```

`isOnGCD=true` does not prove that an active cooldown is GCD-only. `core/GCDSafetyPolicy.lua` therefore discards all legacy GCD hints before final readiness resolution and replaces GCD-hint collection with a clear/no-op boundary.

`UNIT_SPELLCAST_SUCCEEDED` is only a readiness invalidation signal after confirming the source is an interrupt. It is never positive GCD or readiness evidence.

## Cooldown event rules

- no subscription to `ACTIONBAR_UPDATE_COOLDOWN`;
- exact interrupt events teach only non-global shared categories;
- unrelated global-recovery events are discarded;
- one source API evaluation occurs per readiness generation;
- one result is shared by every physical copy of the canonical ability;
- accessible deadlines use one active-only 50 ms worker;
- restricted timing uses one active-only 250 ms worker;
- hard restrictions never enter periodic polling.

## Cooldown Viewer hook rule

Pool hooks may run inside Blizzard reset/layout stacks. They may only read/store ordinary identity and queue one dirty item record. Canonical unbinding/rebinding and visual mutation happen in the addon-owned next-frame flush.

## Secret-value boundary

Potentially secret `notInterruptible` follows one direct path:

```text
UnitCastingInfo / UnitChannelInfo
  -> local raw value
  -> Glow:ApplyUnitInterruptibility
  -> childRegion:SetAlphaFromBoolean(raw, 0, 255)
```

The raw value is never stored, formatted, logged, table-keyed, serialized, compared before `canaccessvalue`, returned through an internal bus, or routed through a `pcall` result lane. The child region carrying the Alpha secret aspect is never animated or read back.

Spellcast event code retains only generated-contract NeverSecret `castBarID`; it does not retain `castGUID`, `spellID`, or `interruptedBy`.

`SPELL_SECRECY_CHANGED` remains unconfirmed in pinned generated docs/implementation and is not registered.

## Runtime evidence

`/iglow capture start|mark|stop|show` records build, instance, provider state, worker state, SavedVariables schema, GCD policy, restriction transitions, normalized cast/readiness state, secrecy predicates, session-only counters and native profiler start/end/delta data.

Profiler threshold counters are cumulative and are subtracted between snapshots. `PeakTime` is reported as start/end/increase, not a resettable capture-window maximum. Legacy `scriptProfile` is never enabled.

## Validation boundary

Local syntax/static/mock scripts prove source and modeled state transitions only. GitHub Actions workflows remain absent. Live WoW remains authoritative for FPS, taint, secure execution, restricted contexts, provider interactions, GCD/personal-cooldown overlap and upstream workaround retirement.

## Deliberate omissions

- Single Button Assistant next-action highlighting;
- global discovery of arbitrary action-button addons;
- reconstructing restricted remaining seconds;
- loading Blizzard's private CooldownBroadcaster at runtime;
- speculative LOD options packaging without profiler evidence of material cost.
