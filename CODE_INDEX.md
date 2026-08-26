# Code index

- `Core.lua` — addon namespace and module registry.
- `core/Shared.lua` — DB migration, access gates, lazy dirty queue and frame-batched flush.
- `core/Data.lua` — current spec registry, runtime-learned action identities and pet aliases.
- `core/Debug.lua` — normalized ring log and Blizzard profiler report.
- `core/Glow.lua` — incrementally prewarmed target/focus alpha-gate overlays and shared runtime driver.
- `core/Buttons.lua` — Blizzard, LAB, Dominos, ButtonForge, pet and CDM adapters plus canonical abilities.
- `core/Cooldown.lua` — cached readiness, event-time GCD hints, charges, LoC and accessible deadlines.
- `core/CastTracking.lua` — fixed target/focus watchers and the sole raw SecretValue visual bridge.
- `core/CDM.lua` — Cooldown Viewer acquire/set/reset lifecycle and duplicate suppression.
- `core/Events.lua` — PLAYER_LOGIN-gated runtime event registration and bounded routing.
- `core/Slash.lua` — diagnostics and manual bounded discovery.
- `Options.lua` — lazy Settings canvas.
- `tools/sync_interrupts.py` — build-time sync/check against Blizzard `InterruptSpellsBySpec`.
- `tests/static_checks.py` — architecture and API-use invariants.
- `tests/mock_wow.lua` — regression/stress model.
- `docs/INTERRUPT_IDS.md` — current class/spec mapping.
- `docs/PERFORMANCE_MODEL.md` — update cadence and complexity.
