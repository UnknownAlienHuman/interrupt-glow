# Interrupt Glow 1.1 implementation authority

Baseline: WoW Retail `12.1.0.69497`, Interface `120100`, Blizzard UI commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`.

Shared workflow: `UnknownAlienHuman/wow-addon-engineering-kb@e45366cb0ca56dfe49664daa9f2579e629af0cb3`.

## Lifecycle

- Interrupt Glow is not LoadOnDemand because automatic target/focus cast observation must begin without user interaction.
- Gameplay registrations and provider discovery wait for `EventUtil.ContinueOnPlayerLogin`.
- `C_AddOns.IsAddOnLoaded` is gated by its second, fully-loaded return.
- Already-loaded provider registries are discovered once.
- Bartender/ElvUI/LAB, Dominos, ButtonForge and Cooldown Viewer attach later through verified load-order surfaces without polling.
- Native `ActionButton.OnActionChanged` registration uses a callback-handle container when the current registry supports handles and unregisters symmetrically.
- Cooldown Viewer is not forced to load.
- Settings controls, report window and cooldown text are lazy.
- No addon-owned frame, texture, font string or animation is created in combat.

## Integration points

- native buttons: `ActionButton.OnActionChanged`, deduplicated by a current action snapshot;
- native discovery: `ActionBarButtonEventsFrame:ForEachFrame` once after login;
- LibActionButton: exact `button:UpdateAction()` post-hooks plus changed-slot routing through `buttonsBySlot[slot]`;
- Dominos: its indexed registry plus targeted action/slot post-hooks;
- ButtonForge: allocation API, deduplicated `BFButton:FullRefresh`, and `BFButton:ClearCommand`;
- pet buttons: fixed ten-slot pet registry refreshed by pet lifecycle events;
- target/focus: fixed `RegisterUnitEvent` spellcast watchers;
- Cooldown Viewer: `OnAcquireItemFrame`, `OnCooldownIDSet`, and `ResetCooldownData` pooled-item lifecycle.

There is no automatic frame enumeration, action-slot sweep, nameplate traversal, macro-body parsing, or Cooldown Viewer child-tree scan.

## Cast lifecycle and active upstream mitigation

Active field issue `WOWUI-2026-005` tracks stale/phantom `UnitChannelInfo` results after a real channel end (`WoWUIBugs` #777, #784 and #834).

Interrupt Glow follows Blizzard's event-authoritative castbar model:

```text
CHANNEL_START / EMPOWER_START
  -> clear channel suppression
  -> snapshot current cast once

CHANNEL_STOP / EMPOWER_STOP
  -> read only NeverSecret event castBarID
  -> ignore a delayed stop belonging to an older cast
  -> establish channel-snapshot suppression
  -> clear normalized cast state synchronously

UNIT_FLAGS / UNIT_FACTION / UNIT_TARGETABLE_CHANGED after stop
  -> ordinary UnitCastingInfo remains available
  -> UnitChannelInfo is skipped while suppression is active

PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED / PLAYER_ENTERING_WORLD
  -> reset unit identity and suppression
  -> permit one fresh mid-cast snapshot
```

`UNIT_SPELLCAST_CHANNEL_UPDATE` and `UNIT_SPELLCAST_EMPOWER_UPDATE` are observed, but ignored while suppression is active. The workaround remains current until a named live build fixes the upstream issue and target-death, Lightning Lasso, and Ray of Frost reproductions pass without it.

## Runtime data authority

- Slot-backed classification: `C_ActionBar.IsInterruptAction(slot)`.
- Current resolved identity: `GetActionInfo(slot)`; Assisted Combat actions are excluded.
- Direct spell, pet and Cooldown Viewer classification: pinned current-spec data plus reviewed PvP/pet exceptions.
- Ordinary specialization data comes from Blizzard's current `InterruptSpellsBySpec` snapshot.
- Warlock `212619` Call Felhunter and direct pet aliases remain outside the generated block.
- Unknown authoritative slot IDs are learned for the current specialization/session only.
- Clustered spellbook, combat-config, talent, trait and PvP-talent signals coalesce into one rebuild.

## Readiness rules

Readiness is evaluated only while its result can be visible:

```text
addon enabled
AND
(relevant target/focus cast OR custom countdown enabled)
```

A newly relevant cast, target/focus identity change, re-enable, policy change, or countdown enable marks active abilities `readinessPending`. Glow and custom text fail closed until the next frame completes one bounded readiness pass.

The decision combines:

- action/spell cooldown duration with GCD ignored;
- charge count and recharge duration;
- `C_ActionBar.IsUsableAction` or `C_Spell.IsSpellUsable`;
- intrinsic pet-action usability;
- Loss of Control;
- explicit policy for fully restricted ordinary cooldown readiness.

Inaccessible usability, pet state and Loss of Control are hard fail-closed restrictions. Optimistic cooldown compatibility cannot override them.

## Cooldown event rules

- no Interrupt Glow subscription to `ACTIONBAR_UPDATE_COOLDOWN`;
- `isOnGCD` is normalized only during the actual `SPELL_UPDATE_COOLDOWN` dispatch;
- exact interrupt events teach only non-global cooldown/start-recovery categories;
- unrelated global-recovery events are discarded;
- one source API evaluation occurs per readiness generation;
- one result is shared by every copy of a canonical ability;
- accessible deadlines use one shared 50 ms expiry driver only while needed;
- restricted timing uses one shared 250 ms poll only during a relevant cast;
- hard restrictions never enter periodic polling.

## Secret-value boundary

Potentially secret `notInterruptible` follows one direct path:

```text
UnitCastingInfo / UnitChannelInfo
  -> local raw value
  -> Glow:ApplyUnitInterruptibility
  -> childRegion:SetAlphaFromBoolean(raw, 0, 255)
```

The raw value is never stored, formatted, logged, table-keyed, serialized, compared before `canaccessvalue`, returned through an internal event bus, or routed through a `pcall` result lane. The child region carrying the Alpha secret aspect is never animated or read back.

Spellcast event payloads are secret-capable. Cast lifecycle code consumes only the generated-contract `castBarID` field, which is NeverSecret, and does not retain `castGUID`, `spellID`, or `interruptedBy`.

`SPELL_SECRECY_CHANGED` remains unconfirmed in the pinned generated docs and implementation. The addon does not register an invented event; current secrecy is recorded through explicit client probes.

## Runtime evidence and profiler contract

`/iglow capture start|mark|stop|show` creates one explicit client-context record. It includes build, instance, restriction transitions, provider state, normalized cast/readiness state, secrecy predicates, session-only addon counters, and native profiler data.

`C_AddOnProfiler` values are interpreted according to the generated contract:

- `SessionAverageTime`, `RecentAverageTime`, `EncounterAverageTime`, `LastTime`, and `PeakTime` are recorded at start and end;
- threshold counts from 1 ms through 1000 ms are cumulative application-session counters and are subtracted between snapshots;
- `PeakTime` is shown as start/end/increase, not as a resettable capture-window maximum;
- profiler enabled state and ticks per second are recorded;
- legacy `scriptProfile` is never enabled.

The required attribution matrix is equal-duration/equal-input runs for default UI, Interrupt Glow only, Interrupt Glow plus the required provider, and the normal full stack.

## Validation boundary

- Local syntax/static/mock scripts prove only source and modeled state transitions.
- GitHub Actions workflows are intentionally absent.
- Live WoW remains authoritative for FPS, taint, secure execution, restriction behavior, provider interactions, and upstream channel regression retirement.

## Deliberate omissions

- Single Button Assistant next-action interrupt highlighting;
- global discovery of arbitrary unknown action-button addons;
- reconstructing restricted remaining seconds;
- loading Blizzard's private CooldownBroadcaster at runtime;
- speculative LOD packaging for the small idle-free settings surface before native profiler evidence shows material startup/UI cost.
