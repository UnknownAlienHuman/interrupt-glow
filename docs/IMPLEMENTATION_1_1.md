# Interrupt Glow 1.1 implementation authority

Baseline: WoW Retail `12.1.0.69497`, Interface `120100`, Blizzard UI commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`.

## Lifecycle

- Interrupt Glow is not LoadOnDemand because automatic cast observation must begin without user interaction.
- Gameplay registrations and registry discovery wait for `EventUtil.ContinueOnPlayerLogin`.
- `C_AddOns.IsAddOnLoaded` is gated by its second, fully-loaded return.
- Already-loaded providers are discovered once.
- Provider load-order callbacks attach Bartender/ElvUI/LAB, Dominos, ButtonForge and Cooldown Viewer later without polling.
- Cooldown Viewer is not forced to load.
- Options controls, debug window and cooldown text are lazy.
- No addon-owned frame, texture, font string or animation is created during combat.

## Integration points

- native buttons: `EventRegistry` callback `ActionButton.OnActionChanged`, deduplicated by a current action snapshot;
- initial native discovery: `ActionBarButtonEventsFrame:ForEachFrame` once after login;
- LibActionButton: exact `button:UpdateAction()` post-hooks plus `ACTIONBAR_SLOT_CHANGED(slot)` routed only through `buttonsBySlot[slot]`;
- Dominos: its indexed registry plus targeted action/slot post-hooks;
- ButtonForge: allocation API, deduplicated `BFButton:FullRefresh`, and `BFButton:ClearCommand`;
- pet buttons: fixed ten-slot pet-action registry, refreshed by pet lifecycle events;
- target/focus: fixed `RegisterUnitEvent` cast watchers;
- Cooldown Viewer: `CooldownViewerMixin:OnAcquireItemFrame`, `CooldownViewerItemDataMixin:OnCooldownIDSet`, and `ResetCooldownData`.

There is no automatic frame enumeration, 1..540 action-slot sweep, nameplate traversal, macro-body parsing or Cooldown Viewer child-tree scan.

## Runtime data authority

- Slot-backed classification: `C_ActionBar.IsInterruptAction(slot)`.
- Current resolved identity: `GetActionInfo(slot)`; Assisted Combat actions are excluded.
- Direct spell, pet and Cooldown Viewer classification: pinned current-spec data plus reviewed PvP/pet exceptions.
- Ordinary specialization data comes from Blizzard's `InterruptSpellsBySpec` snapshot.
- Warlock `212619` Call Felhunter and direct pet-action aliases are maintained outside the generated block.
- Unknown authoritative slot IDs are learned for the current spec/session only.
- Clustered `SPELLS_CHANGED`, combat-config, talent, trait and PvP-talent signals coalesce into one rebuild.
- Same-spec rebuilds preserve runtime discoveries; a specialization change clears them.

## Readiness rules

Readiness is evaluated only while its result can be visible:

```text
addon enabled
AND
(relevant target/focus cast OR custom countdown enabled)
```

Outside that state, cooldown, charge, usability, pet and Loss-of-Control work sleeps.

A newly relevant cast, target/focus identity change, re-enable, policy change or countdown enable marks active abilities `readinessPending`. Glow and custom text fail closed until the next frame completes one bounded readiness pass. This prevents a stale ready result or deadline from being shown for one frame.

The readiness decision combines:

- action/spell cooldown duration with GCD ignored;
- charge count and recharge duration;
- `C_ActionBar.IsUsableAction` or `C_Spell.IsSpellUsable`;
- intrinsic `GetPetActionSlotUsable` for pet sources;
- Loss of Control;
- current addon policy for fully restricted ordinary cooldown readiness.

Inaccessible usability, pet state and Loss of Control are hard fail-closed restrictions. The optimistic compatibility option cannot override them.

## Cooldown event rules

- no Interrupt Glow subscription to `ACTIONBAR_UPDATE_COOLDOWN`;
- `isOnGCD` is read and normalized only inside `SPELL_UPDATE_COOLDOWN` dispatch;
- exact interrupt events teach only non-global cooldown/start-recovery categories;
- unrelated global-recovery events are discarded;
- unknown non-global shared-category events are evaluated only while readiness is visible;
- one readiness result is shared by all copies of a canonical ability;
- one source API evaluation occurs per generation;
- successful player/pet interrupt casts request an immediate readiness refresh;
- accessible deadlines use a shared 50 ms expiry driver only while needed;
- restricted timing uses a shared 250 ms poll only while a relevant cast exists;
- hard restrictions never enter periodic polling.

## Secret-value boundary

Potentially secret `notInterruptible` follows one direct path:

```text
UnitCastingInfo / UnitChannelInfo
  -> local raw value
  -> Glow:ApplyUnitInterruptibility
  -> childRegion:SetAlphaFromBoolean(raw, 0, 255)
```

The raw value is not stored, formatted, logged, returned through an internal event system, compared before `canaccessvalue`, or routed through a `pcall` result lane. The child region carrying the Alpha secret aspect is never animated or read back; candidate state and animation remain on an ordinary parent frame.

## Diagnostics and validation

- Internal counters are dormant unless debug or `/iglow stats start` enables a session profiling window.
- Debug output rejects inaccessible payloads and stores only normalized text.
- GitHub Actions workflows are intentionally absent.
- Local Lua syntax, static invariants, source mapping and mock state-machine scripts are development checks only.
- Live WoW acceptance remains required for secure execution, SecretValue behavior, taint and FPS/CPU measurements.

## Deliberate omissions

- Single Button Assistant next-action interrupt highlighting;
- global discovery of unknown arbitrary action-button addons;
- reconstructing restricted remaining seconds;
- loading Blizzard's private CooldownBroadcaster at runtime.

Dedicated adapters can be added only when a stable callback or lifecycle surface is verified in the current Blizzard UI source.
