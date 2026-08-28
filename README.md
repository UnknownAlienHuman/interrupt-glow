# Interrupt Glow

Current release: `1.1.0-beta.5`

Interrupt Glow highlights the button that currently performs an interrupt when an interruptible hostile cast is active on `target` or `focus` and that ability is ready.

## Runtime model

- Native buttons use `ActionButton.OnActionChanged` with resolved-action snapshot deduplication.
- Slot-backed buttons use `C_ActionBar.IsInterruptAction(slot)` and current action feedback.
- LibActionButton conditional macros route through the changed slot, never a slot/frame scan.
- Macro bodies are not parsed.
- Target and focus use fixed-unit spellcast events.
- Potentially secret `notInterruptible` flows directly to addon-owned `SetAlphaFromBoolean(..., 0, 255)` and is never stored, logged, compared while inaccessible, or routed through `pcall`.
- Readiness is shared per canonical ability and evaluated only while a cast or enabled countdown can display it.
- Action, spell and pet usability, charges, Loss of Control and restricted timing are independent gates.
- Inaccessible usability and Loss of Control fail closed and cannot be bypassed by optimistic cooldown compatibility.
- Cooldown Viewer uses pooled-item acquire/set/reset lifecycle hooks with deferred addon-owned reconciliation.
- There is no automatic frame enumeration, 540-slot scan, nameplate traversal, macro-body read, or Cooldown Viewer child-tree scan.

## Performance and lifecycle

Retail 12.1 `SetOnUpdateMode` is used explicitly:

```text
dirty flush      -> RunOnce
prewarm slice    -> RunOnce
active deadlines -> RunAlways
idle             -> Disabled
```

Gameplay events and provider discovery wait for `PLAYER_LOGIN`. Existing provider registries are enumerated once; Bartender, ElvUI, Dominos, ButtonForge and Cooldown Viewer use verified load-order callbacks. Settings controls, report UI and overlays are created outside combat and reused.

Global cooldown is ignored through:

```lua
C_ActionBar.GetActionCooldownDuration(slot, true)
C_Spell.GetSpellCooldownDuration(spellID, true)
```

`isOnGCD=true` is never accepted as positive interrupt-readiness evidence because a personal cooldown can overlap the GCD.

## Channel lifecycle hardening

Current upstream reports show that `UnitChannelInfo` can return stale or phantom channels after a real stop. Interrupt Glow treats synchronous `UNIT_SPELLCAST_CHANNEL_STOP` and `UNIT_SPELLCAST_EMPOWER_STOP` as authoritative. Later channel snapshots are suppressed until a real channel/empower start or a target/focus identity change.

Delayed stop events are matched against NeverSecret `castBarID`, so an old stop cannot clear a newer cast. The workaround tracks active issue family `WOWUI-2026-005` and remains until named-build retesting passes target-death, Lightning Lasso and Ray of Frost reproductions.

## SavedVariables

Schema 3 retains only typed preferences and producer metadata:

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

Legacy runtime caches, unknown keys, frame references and transient restricted state are discarded on load.

## Runtime probe

The probe is disabled until explicitly started:

```text
/iglow probe
/iglow capture start quick-heal-mouseover
/iglow capture mark friendly-hover
/iglow capture mark hostile-hover
/iglow capture stop
/iglow capture show
```

Reports include build/interface, SavedVariables schema, provider state and versions, worker state, normalized target/focus and ability state, current `C_Secrets` policy, the conservative GCD policy, session-only counters, and native `C_AddOnProfiler` baselines/deltas through `CountTimeOver1000Ms`.

## Supported button systems

- Blizzard action bars
- LibActionButton consumers, including Bartender and ElvUI variants
- Dominos
- ButtonForge
- Pet action buttons
- Blizzard Essential and Utility Cooldown Viewers

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

```text
UnknownAlienHuman/wow-addon-engineering-kb@312085aa8d23dfe283b416ba0f394fef1cae22dd
Gethe/wow-ui-source@027d26c3406d3de2cbd2b1f67d468fe033a1bcd4
WoW 12.1.0.69497 / Interface 120100
```

`SPELL_SECRECY_CHANGED` remains unconfirmed in the pinned generated docs and implementation, so Interrupt Glow does not register it.

## Validation boundary

Local Lua/mock checks catch syntax and modeled state-machine regressions only. GitHub Actions workflows remain absent. Live-client evidence is still authoritative for FPS, taint, provider interactions, restricted contexts, GCD/personal-cooldown overlap, Cooldown Viewer pool reuse, and upstream channel-regression retirement.

## Metadata

- Interface: `120100`
- Version: `1.1.0-beta.5`
- Author: Neomorph
- Saved variables: `InterruptGlowDB`

## License

MIT. See [LICENSE](LICENSE).
