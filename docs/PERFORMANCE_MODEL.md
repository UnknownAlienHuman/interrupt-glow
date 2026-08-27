# Performance model — Interrupt Glow 1.1

## Update latency

| Signal | Work | Expected visual latency |
|---|---|---:|
| Target/focus cast start, stop or interruptibility event | fixed-unit snapshot and currently bound interrupt records only | synchronous handler update |
| Native action feedback | resolved-action snapshot compare; enqueue only if identity changed | next frame |
| LAB action state | exact `UpdateAction` post-hook; conditional macro feedback uses `buttonsBySlot[eventSlot]` | next frame |
| Dominos action feedback | changed controller button or indexed action slot only | next frame |
| ButtonForge conditional macro | three raw resolved-command reads; enqueue only if identity changed | next frame |
| Relevant `SPELL_UPDATE_COOLDOWN` | event-time GCD hint plus one pass over active canonical abilities | next frame |
| Accessible cooldown deadline | one shared driver, only while a relevant cast/countdown needs it | at most 50 ms plus one frame |
| Restricted cooldown timing | one shared driver, only while a relevant cast exists | at most 250 ms; refreshed immediately when a cast becomes relevant |
| Integer cooldown text | same shared driver, only when enabled | 200 ms |
| Initial ordinary-button shell prewarm | 16 physical buttons per frame | current interrupts are immediate; remaining bars spread across frames |

Current Blizzard ordinary data exposes at most two player interrupt families for a specialization. Verified PvP/pet extras add only a small constant. Readiness work therefore scales with active canonical abilities, not physical button copies.

## Mouseover hot path

### Blizzard

```text
ActionButton.OnActionChanged(button)
  -> read slot/actionType/id/subType/interrupt/assisted
  -> compare with record snapshot
  -> no-op if unchanged
  -> otherwise one deduplicated dirty record
```

### LibActionButton

```text
exact UpdateAction post-hook
or ACTIONBAR_SLOT_CHANGED(slot)
  -> buttonsBySlot[slot]
  -> dirty only existing buttons for that slot
  -> one frame-batched classification
```

LAB's broad `OnButtonUpdate` callback is removed for providers whose buttons expose `UpdateAction`; a nonstandard-provider fallback performs identity reads only. There is no action-slot scan.

### ButtonForge

ButtonForge already resolves conditional macros in its own update path. Interrupt Glow reads its resulting `Mode`, `MacroMode` and `SpellId`, then queues only if that normalized identity changed.

None of these paths performs:

- macro-body parsing;
- frame enumeration;
- 540-slot scanning;
- nameplate traversal;
- cooldown API work when the shared ability state is current;
- UI object or timer creation.

## Cooldown event filtering

`SPELL_UPDATE_COOLDOWN` supplies changed spell, base spell, cooldown category and start-recovery category.

Interrupt Glow:

1. accepts exact current interrupt/base/override events;
2. learns the interrupt's non-global cooldown/recovery categories;
3. accepts future events for learned categories;
4. ignores unrelated pure global-recovery events;
5. checks unknown non-global shared-category events only while a relevant cast or enabled countdown can make the result visible.

`isOnGCD` is normalized only during the actual event dispatch and consumed as a plain one-frame hint. It is never read later.

## Restricted data

- Secret cast interruptibility goes directly to `SetAlphaFromBoolean(..., 0, 255)` without `pcall`, storage, logging or readback.
- Restricted Loss of Control is a hard fail-closed gate and is never overridden by optimistic cooldown compatibility.
- Inaccessible pet usability is also a hard fail-closed gate.
- Exact `currentCharges == 0` remains not-ready even when recharge timing is secret.
- Secret remaining time never becomes a custom number.
- Restricted timing polling sleeps without a relevant cast; cast relevance transitions force one immediate readiness snapshot.

## Disabled mode

When `DB.enabled=false`:

- cast/button state remains cheap and current for instant re-enable;
- cooldown, charge, LoC and pet-readiness evaluation is skipped;
- timing/countdown drivers are asleep;
- enabling performs one fresh cast/readiness/visual update.

## Startup cost

Interrupt Glow itself is not LoadOnDemand because it must observe combat automatically. Startup is lazy internally:

1. TOC loads code and a bare Settings canvas.
2. Gameplay events, provider attach and discovery wait for `PLAYER_LOGIN`.
3. Already-loaded providers are enumerated exactly once.
4. Bartender, ElvUI, Dominos, ButtonForge and Cooldown Viewer use load-order callbacks rather than polling.
5. Current interrupt buttons receive visuals immediately.
6. Other physical button shells are prewarmed at 16 buttons per frame.
7. Options controls, debug window and cooldown font strings are created only when needed.

## Acceptance boundary

Local scripts can catch syntax, source drift and state-machine regressions. They cannot validate WoW FPS, taint, protected execution or SecretValue behavior. GitHub Actions workflows are intentionally absent.

Live ship gates:

- no `EnumerateFrames` or nameplate traversal;
- no macro-body API in runtime files;
- no `ACTIONBAR_UPDATE_COOLDOWN` subscription;
- `ACTIONBAR_SLOT_CHANGED` only in the LAB adapter as an event-slot-to-known-buttons diff;
- no frame creation during combat;
- no secret payload storage/logging/readback;
- no duplicate startup/provider discovery;
- no stale CDM binding after pool reset/reuse;
- no blocked/forbidden actions or taint;
- no >5 ms Interrupt Glow spikes during the live 60-second mouseover/nameplate stress test.
