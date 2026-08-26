# Changelog

## 1.1.0-beta.2

- Defer gameplay event registration and provider discovery until `PLAYER_LOGIN`.
- Use the second `C_AddOns.IsAddOnLoaded` return for fully-loaded lifecycle gates.
- Add exact 12.1.0 per-specialization interrupt data and current Warlock pet aliases.
- Add a pinned-source mapping generator and CI snapshot check.
- Use `C_ActionBar.IsInterruptAction` as runtime authority for slot-backed buttons.
- Share readiness across copies of the same canonical interrupt.
- Preserve same-spec runtime discoveries across clustered `SPELLS_CHANGED` events.
- Coalesce specialization/spellbook signals into one frame-batched rebuild.
- Normalize `isOnGCD` inside the actual `SPELL_UPDATE_COOLDOWN` handler.
- Treat inaccessible Loss of Control as restricted instead of clear.
- Add immediate readiness invalidation after successful player/pet interrupt casts.
- Add current `19647 -> 119910` and `89766 -> 119914` pet mappings; remove obsolete Retail IDs.
- Use full secret alpha `255`; never animate or read back the secret-carrying region.
- Prewarm lightweight physical-button shells incrementally; create animations/text only for interrupt buttons.
- Deduplicate ButtonForge conditional refreshes and handle `ClearCommand`.
- Deduplicate Cooldown Viewer acquire/ID lifecycle notifications.
- Add CI, Lua 5.1 syntax checks, static invariants and expanded mock regressions.

## 1.1.0-beta.1

- Initial event-driven, scan-free 1.1 runtime.
