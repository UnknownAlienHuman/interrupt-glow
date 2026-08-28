# Interrupt Glow

Current development version: `1.1.0-beta.3`

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

## Channel lifecycle hardening

Current upstream reports show that `UnitChannelInfo` can return stale or phantom channels after a real stop. Interrupt Glow therefore treats synchronous `UNIT_SPELLCAST_CHANNEL_STOP` and `UNIT_SPELLCAST_EMPOWER_STOP` as authoritative. Later channel snapshots are suppressed until a real channel/empower start or a target/focus identity change.

Delayed stop events are matched against the NeverSecret `castBarID`, so a stop from an older cast cannot clear a newer cast. The workaround tracks active issue family `WOWUI-2026-005` and must be retired only after named-build retesting of the target-death, Lightning Lasso and Ray of Frost reproductions.

## Startup and lifecycle

Interrupt Glow itself is intentionally not LoadOnDemand because it must observe casts automatically. Startup remains bounded:

- gameplay events and provider discovery wait for `PLAYER_LOGIN`;
- already-loaded registries are enumerated once;
- Bartender, ElvUI, Dominos, ButtonForge and Cooldown Viewer use load-order callbacks;
- native EventRegistry registration uses Blizzard callback-handle containers when available;
- Settings controls and report UI are created only when opened;
- overlays are precreated outside combat in bounded batches;
- timing drivers are hidden while idle;
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

Reports include:

- build/interface and pinned source revisions;
- instance/restriction context;
- provider loaded/attached state;
- normalized target/focus and ability state;
- current `C_Secrets` policy;
- session-only internal counters;
- native `C_AddOnProfiler` start/end snapshots;
- threshold-count deltas through `CountTimeOver1000Ms`;
- marker-level profiler snapshots.

Blizzard profiler counters are application-session cumulative. The probe records a baseline and subtracts counts at stop; it does not pretend to reset native counters. See [Runtime probe](docs/RUNTIME_PROBE.md).

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
UnknownAlienHuman/wow-addon-engineering-kb@e45366cb0ca56dfe49664daa9f2579e629af0cb3
```

Platform source is pinned to:

```text
Gethe/wow-ui-source@027d26c3406d3de2cbd2b1f67d468fe033a1bcd4
WoW 12.1.0.69497 / Interface 120100
```

The shared KB currently mentions `SPELL_SECRECY_CHANGED`, but the symbol is not confirmed in the pinned generated docs or implementation. Interrupt Glow does not register an unverified event.

## Validation boundary

Local Lua/mock checks catch syntax and state-machine regressions only. GitHub Actions workflows remain absent. Stable release still requires live-client evidence for:

- Quick Heal `@mouseover` stress;
- default UI, InterruptGlow-only, provider, and full-stack attribution runs;
- Mythic+, raid and PvP restrictions;
- `taintLog 2` and forbidden/blocked errors;
- current Bartender, ElvUI, Dominos and ButtonForge versions;
- Warlock pet/sacrifice/Command Demon/Call Felhunter variants;
- Protection Warrior dual interrupts;
- Cooldown Viewer pool reuse;
- target-death, Lightning Lasso and Ray of Frost phantom-channel scenarios.

## Metadata

- Interface: `120100`
- Version: `1.1.0-beta.3`
- Author: Neomorph
- Saved variables: `InterruptGlowDB`

## License

MIT. See [LICENSE](LICENSE).
