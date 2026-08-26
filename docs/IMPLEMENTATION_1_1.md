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

## Integration points

- `EventRegistry: ActionButton.OnActionChanged`;
- `ActionBarButtonEventsFrame:ForEachFrame`;
- all `LibActionButton-1.0*` callback registries;
- Dominos indexed registry plus targeted action/slot post-hooks;
- ButtonForge allocation API, deduplicated `BFButton:FullRefresh`, and `BFButton:ClearCommand`;
- fixed `RegisterUnitEvent` watchers for `target` and `focus`;
- `CooldownViewerMixin:OnAcquireItemFrame`;
- `CooldownViewerItemDataMixin:OnCooldownIDSet`;
- `CooldownViewerItemDataMixin:ResetCooldownData`.

## Runtime data authority

- Slot-backed classification: `C_ActionBar.IsInterruptAction`.
- Spell identity: `C_ActionBar.GetSpell`, with `GetActionInfo` fallback.
- Direct/pet/CDM classification: pinned per-spec snapshot plus current pet aliases.
- Unknown authoritative slot IDs are learned for the current spec/session only.
- `SPELLS_CHANGED` within the same spec preserves runtime discoveries; a spec change clears them.

## Cooldown rules

- no Interrupt Glow subscription to `ACTIONBAR_UPDATE_COOLDOWN`;
- irrelevant GCD-only `SPELL_UPDATE_COOLDOWN` signals are filtered by payload;
- `isOnGCD` is read and normalized only inside that event dispatch;
- one readiness result is shared by all copies of a canonical ability;
- one source API evaluation per generation;
- exact false charge readiness cannot be overridden by optimistic mode;
- restricted LoC fails closed;
- successful player/pet interrupt casts request an immediate readiness refresh;
- accessible deadlines use a 50 ms shared expiry driver;
- restricted timing uses a 250 ms shared poll and an immediate cast-start poll.

## Deliberate omissions

- Single Button Assistant next-action interrupt highlighting;
- global discovery of unknown arbitrary action-button addons;
- reconstructing restricted remaining seconds;
- loading Blizzard's private CooldownBroadcaster at runtime.

Dedicated adapters can be added only when a stable callback/lifecycle surface is known.
