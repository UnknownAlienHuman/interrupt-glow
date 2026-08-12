# Interrupt Glow

Current version: `1.0.24`

Notes (1.0.x):
- 12.x secret/restricted values hardened paths for cooldown + interruptible detection.

Fixes for environments where:
- GetActionSpell() is missing,
- GetActionInfo(slot) can report actionType="macro" with id=spellID,
- Some buttons are SecureActionButtonTemplate-based and not tied to an action slot.

Behavior:
- Glows your interrupt button(s) when your current target or focus is casting or channeling.
- Glows even out of combat to simplify testing.

v0.6.0: Creates a Blizzard-style SpellActivationAlert using ActionButtonSpellAlertTemplate (or fallbacks) and plays ProcStartAnim/ProcLoopAnim if present. Adds /iglow test.

v0.6.1: Fixes stray backslash syntax error.

v0.6.2: Adds filters: hostile target only; interruptible casts only (or unknown).

v0.6.3: Simplifies filters: glow only if you can harm the target (UnitCanAttack). Interruptibility filter removed. Cast-start driven logic.

v0.6.12: Adds a secret-safe non-interruptible check. Primary signal is UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE (boolean). Optional fallback uses Blizzard castbar shield visibility (IsShown/GetAlpha) when state is unknown (e.g. target acquired mid-cast). No spell identity or castGUID comparisons.


New in v0.6.43:
- Target + Focus support (event-driven cast state; no polling).
- Interrupt SpellID resolution prefers your actual button/slot (spell / macro / secure button attributes).
- Cooldown numbers update on a per-second timer while on cooldown (no OnUpdate).
- Blizzard Cooldown Manager (CDM) mirroring remains optional and is only scanned out of combat.
- Hooks Blizzard TargetFrameSpellBar/FocusFrameSpellBar OnShow/OnHide as a zero-cost fallback for cast detection.
- Forces a readiness refresh when you successfully use an interrupt (UNIT_SPELLCAST_SUCCEEDED) to prevent stale cooldown state.


New in v0.6.45:
- Cooldown gating: if C_Spell.GetSpellCooldown reports isOnGCD=false but start/duration are unreadable (secret), we no longer hard-block the glow. We fall back to action-slot / widget cooldown, and if still unknown we prefer a false-positive over silence.

## Current project documentation

- Interface: `120001`, `120005`; version: `1.0.24`; saved variables: `InterruptGlowDB`.
- Install by copying `InterruptGlow` to `World of Warcraft/_retail_/Interface/AddOns/`, then restart or `/reload`.
- `/iglow test` exercises the visual path; `/iglow state` reports state while a target is casting.
- Development status: modular refactor complete; a live dungeon/raid test remains. See [todo.md](todo.md).
- [CurseForge project](https://www.curseforge.com/wow/addons/interrupt-glow)
- [Architecture](ARCHITECTURE.md) · [Code index](CODE_INDEX.md) · [Code graph](CODE_GRAPH.md)
