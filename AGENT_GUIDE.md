# Agent guide

Target: World of Warcraft Retail 12.1.0, Interface 120100.

## Hard rules

1. Do not restore `EnumerateFrames`, nameplate traversal or a 1..540 slot scan.
2. Do not parse macro bodies for slot-backed buttons.
3. Do not subscribe to `ACTIONBAR_UPDATE_COOLDOWN`. `ACTIONBAR_SLOT_CHANGED` is allowed only in `core/LABAdapter.lua`, where the event payload selects an already-indexed LAB button set; no slot or frame scan is permitted.
4. Never store, compare, format or log inaccessible values.
5. Raw cast `notInterruptible` may only be passed directly to `SetAlphaFromBoolean(..., 0, 255)`.
6. Never animate or read back the region carrying the Alpha secret aspect.
7. Do not pass a secret `LuaDurationObject` to addon-owned cooldown/statusbar/text bindings.
8. Do not create overlays in combat. Prewarm physical button shells outside combat.
9. Integrations must be idempotent, bounded by existing registries/callbacks and guarded after detach.
10. `isOnGCD` may be normalized only inside `SPELL_UPDATE_COOLDOWN` dispatch.
11. Restricted Loss of Control and inaccessible pet usability are hard fail-closed gates; the optimistic compatibility option applies only to cooldown readiness.
12. Update the ordinary specialization snapshot through `tools/sync_interrupts.py`. Maintain verified PvP-talent and direct-pet exceptions outside the generated block so synchronization cannot silently delete them.
13. GitHub Actions is not an acceptance environment for this addon. Keep workflows absent; live-client FPS, taint, secure execution and SecretValue behavior are mandatory release checks.

## Source baseline

- Blizzard UI build `12.1.0.69497`
- commit `027d26c3406d3de2cbd2b1f67d468fe033a1bcd4`
- ordinary specialization interrupt source: `Blizzard_CooldownBroadcaster/TrackedCooldowns.lua`
- verified extras: explicit PvP-talent and direct pet-action mappings in `core/Data.lua`
