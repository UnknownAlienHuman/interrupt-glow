# Interrupt Glow

Current development version: `1.1.0-beta.4`

Interrupt Glow highlights the button that currently performs an interrupt when an interruptible hostile cast is active on `target` or `focus` and that ability is ready.

## Runtime model

The old scan-driven runtime is gone:

- native buttons use `ActionButton.OnActionChanged` with resolved-action snapshot deduplication;
- slot-backed buttons use `C_ActionBar.IsInterruptAction(slot)` and current action feedback;
- LibActionButton conditional macros route through the changed slot, never a slot/frame scan;
- macro bodies are not parsed;
- target/focus use fixed-unit spellcast events;
- potentially secret `notInterruptible` flows directly to addon-owned `SetAlphaFromBoolean(..., 0, 255)` and is never stored, logged, compared while inaccessible, or routed through `pcall`;
- readiness is shared per canonical ability and evaluated only while a cast/countdown can display it;
- action, spell and pet usability, charges, Loss of Control and restricted timing are separate gates;
- Cooldown Viewer uses pooled-item acquire/set/reset lifecycle hooks;
- no automatic frame enumeration, 540-slot scan, nameplate traversal, macro-body read, or CDM child-tree scan remains.

## Beta.4 hardening

### Explicit worker modes

One-shot dirty work and button prewarming now use Retail 12.1 `SetOnUpdateMode`:

```text
dirty flush      -> RunOnce
prewarm slice    -> RunOnce
active deadlines -> RunAlways
idle             -> Disabled
```

The workers are explicitly disabled at construction; they do not remain visible or active merely to discover that there is no work.

### Strict SavedVariables schema

Only typed preferences and producer metadata are retained:

```text
schema
producerVersion
interface
enabled
cdText
cdm
strictNI
optimisticRestrictedCooldown
debug
debugChat
debugKeep
```

Legacy slot/cooldown caches, unknown keys, corrupt types, frame references and transient runtime state are discarded on load. `debugKeep` is clamped to `20..2000`.

### Bounded caches

Dormant ability state is preserved during same-specialization conditional-macro churn to avoid allocation/GC churn. A real specialization change reconciles all buttons, prunes unreferenced abilities and resets source-readiness caches.

### Deferred Cooldown Viewer reconciliation

Blizzard Cooldown Viewer pool hooks now change only ordinary identity and queue one dirty record. Binding and addon-owned visual changes occur on the next addon frame, outside Blizzard reset/layout stacks.

### Conservative GCD handling

Interrupt Glow ignores the global cooldown through:

```lua
C_ActionBar.GetActionCooldownDuration(slot, true)
C_Spell.GetSpellCooldownDuration(spellID, true)
```

`isOnGCD=true` does **not** prove that an active cooldown is only the GCD; a personal cooldown may overlap. Therefore it is never accepted as positive readiness evidence. `UNIT_SPELLCAST_SUCCEEDED` is only an invalidation signal for a confirmed interrupt source.

If the ignore-GCD duration is inaccessible, the fallback is conservative rather than showing a false-ready glow.

## Channel lifecycle hardening

Current upstream reports show that `UnitChannelInfo` can return stale or phantom channels after a real stop. Interrupt Glow treats synchronous `UNIT_SPELLCAST_CHANNEL_STOP` and `UNIT_SPELLCAST_EMPOWER_STOP` as authoritative. Later channel snapshots are suppressed until a real channel/empower start or a target/focus identity change.

Delayed stop events are matched against NeverSecret `castBarID`, so an old stop cannot clear a newer cast. The workaround tracks active issue family `WOWUI-2026-005` and remains until named-build retesting passes target-death, Lightning Lasso and Ray of Frost reproductions.

## Startup and lifecycle

Interrupt Glow itself is intentionally not LoadOnDemand because it must observe casts automatically. Startup remains bounded:

- gameplay events and provider discovery wait for `PLAYER_LOGIN`;
- already-loaded registries are enumerated once;
- Bartender, ElvUI, Dominos, ButtonForge and Cooldown Viewer use load-order callbacks;
- native EventRegistry registration uses callback-handle containers when available;
- Settings controls and report UI are created only when opened;
- overlays are created outside combat in bounded batches;
- no frames are created during combat.

## In-client runtime probe

The probe is disabled until explicitly started:

```text
/iglow probe
/iglow capture start quick-heal-mouseover
/iglow capture mark friendly-hover
/iglow capture mark hostile-hover
/iglow capture stop
/iglow capture show
```

Reports include build/interface, SavedVariables schema, provider state, worker state, normalized target/focus and ability state, current `C_Secrets` policy, the conservative GCD policy, session-only counters and native `C_AddOnProfiler` baselines/deltas through `CountTimeOver1000Ms`.

Blizzard profiler counters are application-session cumulative. The probe records a baseline and subtracts threshold counts; it does not pretend to reset native counters. See [Runtime probe](docs/RUNTIME_PROBE.md).

## Supported button systems

- Blizzard action bars;
- LibActionButton consumers, including Bartender and ElvUI variants;
- Dominos;
- ButtonForge;
- pet action buttons;
- Blizzard Essential and Utility Cooldown Viewers.

Single Button Assistant next-action highlighting remains intentionally excluded because it uses a different polling model.

## Commands

```text
/iglow test
/iglow state
/iglow probe
/iglow capture start|mark|stop|show
/iglow stats
/iglow stats start|stop|reset
/iglow rescan
/iglow log show|clear
/iglow enable
/iglow disable
```

## Engineering authority

Repository rules are in `AGENTS.md`. Shared workflow is pinned to:

```text
UnknownAlienHuman/wow-addon-engineering-kb@312085aa8d23dfe283b416ba0f394fef1cae22dd
```

Platform source is pinned to:

```text
Gethe/wow-ui-source@027d26c3406d3de2cbd2b1f67d468fe033a1bcd4
WoW 12.1.0.69497 / Interface 120100
```

`SPELL_SECRECY_CHANGED` remains unconfirmed in the pinned generated docs and implementation. Interrupt Glow does not register an unverified event.

## Validation boundary

Local Lua/mock checks catch syntax and modeled state-machine regressions only. GitHub Actions workflows remain absent. Stable release still requires live-client evidence for Quick Heal mouseover stress, GCD/personal-cooldown overlap, default/provider/full-stack attribution, restricted contexts, taint, provider versions, Warlock/PWarrior variants, Cooldown Viewer pool reuse and the active phantom-channel scenarios.

## Metadata

- Interface: `120100`
- Version: `1.1.0-beta.4`
- Author: Neomorph
- Saved variables: `InterruptGlowDB`

## License

MIT. See [LICENSE](LICENSE).
