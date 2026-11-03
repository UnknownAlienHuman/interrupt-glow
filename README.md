# Interrupt Glow

**1.1.0-beta.9 · WoW Retail 12.1.5 · Interface 120105**

Highlights your interrupt buttons when a hostile **target** or **focus** is casting and the interrupt is ready. Target highlights are cyan; focus highlights are amber. The pulse can be switched off for a steady highlight.

## Settings

Type **`/iglow`** or open **Settings → AddOns → Interrupt Glow**.

- Enable or disable the addon.
- Include Blizzard Cooldown Manager icons.
- Choose animated or steady highlights.
- Show a countdown when the game allows access to the remaining cooldown.
- Preview highlights on discovered interrupt buttons outside combat. Preview ends when combat starts or the addon is disabled.
- Open troubleshooting logs and rediscover buttons after changing an action-bar addon.

The default settings are conservative. An unavailable cooldown, charge, usability or Loss of Control result is not evidence that an interrupt is ready. The optional cooldown compatibility setting can produce false positives and cannot bypass hard restrictions.

Settings persist across reloads. Schema 4 preserves recognized preferences, adds `animateGlow`, and removes obsolete runtime caches and unknown keys. `LoadSavedVariablesFirst` makes those preferences available before the addon's file-scope initialization.

## Supported surfaces

Blizzard action bars, LibActionButton consumers, Dominos, ButtonForge, pet action buttons, and Blizzard's Essential and Utility Cooldown Viewers. Single Button Assistant prediction is excluded.

Copies of the same interrupt share one readiness result. Provider callbacks queue work for known buttons; they do not scan all frames, nameplates or action slots, or parse macro bodies. Cooldown evaluation sleeps when there is no relevant cast and countdowns are off. The master switch detaches runtime events and provider callbacks.

## Commands

| Command | Action |
|---|---|
| `/iglow` | Open settings |
| `/iglow help` | Show commands |
| `/iglow test` | Toggle the out-of-combat preview |
| `/iglow enable` / `/iglow disable` | Change the master switch |
| `/iglow state` | Print normalized runtime state |
| `/iglow rescan` | Rediscover supported provider buttons outside combat |
| `/iglow log show` / `/iglow log clear` | View or clear diagnostic history |
| `/iglow probe` | Open a current runtime report |
| `/iglow capture start <name>` | Start an explicit diagnostic capture |
| `/iglow capture mark <step>` | Add a capture marker |
| `/iglow capture stop` / `/iglow capture show` | Finalize outside combat or show the report |
| `/iglow stats start` / `stop` / `reset` | Control the manual counter window |

## Development and verification

```sh
python3 tools/test.py
```

The runner discovers the TOC and regression tests, prints the selected Lua interpreter, checks syntax, executes behavioral tests and runs static invariants. `--lua /path/to/lua` selects an interpreter explicitly.

The current source review is pinned to Blizzard UI **12.1.5.70688**, checked **2026-11-02**. See [API review](docs/API_REVIEW.md), [architecture](ARCHITECTURE.md), [interrupt data](docs/INTERRUPT_IDS.md), [performance model](docs/PERFORMANCE_MODEL.md) and [in-client validation](docs/RUNTIME_PROBE.md).

**Live-client validation is NOT-RUN for this beta.** Offline tests do not establish rendering, taint, combat restrictions, provider compatibility or FPS in WoW. The Interface value is the selected patch-family declaration, not a captured client result.

## License

MIT · Author: Neomorph · [LICENSE](LICENSE)
