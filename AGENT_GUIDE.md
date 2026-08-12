# Agent guide: InterruptGlow

## Start here

[`InterruptGlow.toc`](InterruptGlow.toc) loads `Core.lua`, then shared/debug/button/cooldown/cast/glow/event/slash modules, and finally `Options.lua`. `Core.lua` creates `Private` and an initial `PLAYER_LOGIN` frame. `core/Events.lua:OnEvent` is the runtime dispatcher and initializes all active event registrations after login.

## Runtime map

- `Options.lua:Apply` reads/writes `InterruptGlowDB` and schedules CDM discovery when enabled. Settings are registered with the Blizzard Settings API when available.
- `core/Buttons.lua` discovers interrupt action slots, macro spell IDs, secure buttons, ButtonForge buttons, and optional Cooldown Manager buttons. `IG:RescanInterruptButtons` and `IG:TryFindCDMButton` are the main routing points.
- `core/CastTracking.lua` merges unit cast APIs, target/focus cast bars, nameplate bars, explicit interruptibility events, and secure-safe observations into per-unit cast state. `core/Events.lua` feeds target/focus/unit/nameplate lifecycle events.
- `core/Cooldown.lua` computes interrupt readiness from action/widget/spell/charge cooldown candidates, local cast-derived cooldown, and secret-safe fallbacks. `IG:UpdateInterruptReady` is the readiness boundary.
- `core/Glow.lua:IG:ApplyGlowDecision` is the only visual decision/output path. It decorates mapped buttons with `ActionButtonSpellAlertTemplate`/fallback alert frames and coalesces updates through an `OnUpdate` flush.
- `core/Slash.lua:174-398` exposes `/iglow debug`, `log [show|clear|dump N|level N|keep N|chat|on|off]`, `stats`, `ni`, `cd`, `cdm`, `test`, `rescan`, `state`, and `probe`; `core/Debug.lua` provides the on-demand debug frame. `core/Events.lua` calls `IG:HandleError` for guarded failures.

## State and dependencies

`InterruptGlowDB` stores options such as cooldown gating, CDM mirroring, strict non-interruptible behavior, debug flags, and local cooldown calibration. Button maps, cast snapshots, readiness candidates, timers, alert frames, and caches are transient. There are no required external dependencies; Blizzard UI action bars/cast bars and optional ButtonForge/CDM/Masque-like button surfaces are discovered opportunistically. Do not turn those integrations into hard TOC dependencies.

## Change routing

- Button/macro/secure-button discovery: `core/Buttons.lua`; preserve the action-slot and attribute fallbacks.
- Cast and interruptibility truth: `core/CastTracking.lua` and event registration/routing in `core/Events.lua`.
- Cooldown/readiness policy: `core/Cooldown.lua`; add a candidate source with provenance/confidence instead of changing Glow directly.
- Glow visuals and refresh scheduling: `core/Glow.lua`; keep `IG:SetGlow`/`ApplyGlowDecision` idempotent.
- Diagnostics and commands: `core/Debug.lua`/`core/Slash.lua`; do not add unbounded logs to event paths.
- User options/schema: `Options.lua` and the DB defaults in `Core.lua`; use `Apply` to trigger recalculation.

## Invariants/risks

- The glow predicate is `mapped interrupt button(s) + target/focus active cast + can harm + interruptible policy + readiness policy`. Unknown interruptibility/readiness must follow configured strictness; never compare secret values directly.
- Secure action buttons, nameplates, castbars, and Blizzard/CDM internals are protected or unstable surfaces. Only post-hook/guarded observation is allowed; do not call protected actions or mutate secure attributes in combat.
- `core/Glow.lua` has an `OnUpdate` flush; keep it coalesced. Cooldown text uses timers, not a per-frame polling loop. Discovery scans must remain out of combat where possible.
- Unit events are narrowed with `RegisterUnitEvent` for target/focus; preserve event-unit filtering and cache invalidation on target/focus/nameplate/actionbar/binding changes.
- CDM/ButtonForge paths are optional and may disappear; nil/no-op behavior is required.

## Verification

Static checks:

```powershell
Get-Content _Addons/InterruptGlow/InterruptGlow.toc
rg -n "InterruptGlowDB|UpdateInterruptReady|ResolveNI|ApplyGlowDecision|RegisterUnitEvent|SlashCmdList" _Addons/InterruptGlow
```

In-game: `/iglow state`, `/iglow rescan`, `/iglow test`, and the debug log; test target and focus casts/channels, interruptible and non-interruptible casts, macro/secure/action-slot buttons, CDM on/off, cooldown/charges, target changes, nameplate changes, combat entry/exit, reload, and a restricted-value build. Verify no protected-action errors and no glow after cast stop/failure/interrupt.

## Unknowns

Exact Blizzard castbar/CDM object names and secret-value behavior vary by client build. Static evidence identifies fallback chains, but current frame availability and visual alert templates require the target client.
