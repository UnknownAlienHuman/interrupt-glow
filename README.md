# Interrupt Glow

Current development version: `1.1.0-beta.2`

Interrupt Glow highlights the button that currently performs an interrupt when an interruptible hostile cast is active on `target` or `focus` and that ability is ready.

## 1.1 runtime model

The 1.0 scan-driven runtime has been removed:

- native buttons use `ActionButton.OnActionChanged`;
- slot-backed buttons use `C_ActionBar.IsInterruptAction(slot)` and current Blizzard action feedback;
- conditional macro bodies are not parsed;
- target and focus use fixed-unit `UNIT_SPELLCAST_*` watchers;
- casts are detected through NeverSecret fields from `UnitCastingInfo` / `UnitChannelInfo`;
- potentially secret `notInterruptible` is passed directly to addon-owned `SetAlphaFromBoolean(..., 0, 255)` and is never stored or logged;
- cooldown readiness is shared per canonical ability rather than recalculated for every button copy;
- `isOnGCD` is normalized during the actual `SPELL_UPDATE_COOLDOWN` event, not read later;
- charge, Loss of Control, pet cooldown and restricted-timing states are handled separately;
- Blizzard Cooldown Viewer follows pooled-item acquire/set/reset lifecycle hooks;
- there is no automatic frame enumeration, 540-slot scan, nameplate traversal or CDM tree scan.

## Startup and update speed

Interrupt Glow itself is intentionally not LoadOnDemand: otherwise it could not begin observing casts automatically. Its startup work is lazy:

- gameplay events and provider discovery wait for `PLAYER_LOGIN`;
- already-loaded registries are enumerated once;
- later Bartender, ElvUI, Dominos, ButtonForge and Cooldown Viewer availability is handled through load-order callbacks;
- the Settings panel is only a bare canvas until opened;
- current interrupt visuals are created immediately outside combat;
- other physical button shells are prewarmed at 16 buttons per frame;
- no frames are created during combat.

Runtime latency targets:

- cast/interruptibility change: synchronous;
- action or conditional-macro feedback: next frame;
- relevant cooldown signal: next frame;
- accessible cooldown expiry: at most 50 ms plus one frame;
- restricted timing: 250 ms background, with an immediate refresh when a relevant cast starts;
- custom integer countdown: 200 ms.

See [Performance model](docs/PERFORMANCE_MODEL.md).

## Interrupt data

The per-spec snapshot is generated from Blizzard UI build `12.1.0.69497`. Slot-backed buttons remain runtime-authoritative, so a new hotfix interrupt can be learned for the current session even before the vendored table is updated.

See [Interrupt IDs](docs/INTERRUPT_IDS.md).

## Supported button systems

- Blizzard action bars;
- LibActionButton consumers, including Bartender and ElvUI variants;
- Dominos indexed buttons;
- ButtonForge allocation and resolved-command lifecycle;
- pet action buttons;
- Blizzard Essential and Utility Cooldown Viewers.

Single Button Assistant next-action highlighting is intentionally excluded from 1.1 because Blizzard updates it through a separate polling model rather than the normal action-button callback.

## Commands

```text
/iglow test
/iglow state
/iglow stats
/iglow stats reset
/iglow rescan
/iglow log show
/iglow log clear
/iglow enable
/iglow disable
```

`/iglow rescan` performs bounded discovery of known registries only.

## Validation

Automated checks cover Lua 5.1 syntax, architecture invariants, the Blizzard interrupt snapshot, startup/LOD behavior, 2,000 conditional-macro transitions, SecretValue alpha routing, charge/LoC/restricted cooldowns, provider adapters and CDM pool reuse.

Stable release still requires live WoW 12.1.0 checks for:

- the reported Quick Heal `@mouseover` reproduction;
- Mythic+, raid and PvP restrictions;
- taint and blocked-action logs;
- form/page/vehicle/override switching in combat;
- current installed Bartender, ElvUI, Dominos and ButtonForge releases;
- Warlock pet/sacrifice/Command Demon variants;
- Protection Warrior dual interrupts;
- `C_AddOnProfiler` mouseover and dense-nameplate stress.

## Metadata

- Interface: `120100`
- Author: Neomorph
- Saved variables: `InterruptGlowDB`
- Blizzard UI source baseline: `12.1.0.69497`, commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`

## License

MIT. See [LICENSE](LICENSE).
