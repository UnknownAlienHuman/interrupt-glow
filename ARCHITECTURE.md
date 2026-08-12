# Architecture

`Core.lua` creates the addon namespace and initial event frame. On login, `core/Events.lua` initializes button discovery, cached interrupt data, target/focus cast state, cooldown state, and glow refresh scheduling.

`core/Buttons.lua` identifies supported buttons; `core/CastTracking.lua` and `core/Cooldown.lua` produce the state used by `core/Glow.lua`. `core/Shared.lua` and `core/Debug.lua` provide common state/diagnostics, while `Options.lua` persists configuration in `InterruptGlowDB`.

The main risks are stale button discovery after UI changes and combat-related deferrals. Test target and focus casts, macros, cooldown changes, and rescan behavior in an instance after reload.
