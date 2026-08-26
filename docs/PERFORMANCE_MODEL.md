# Performance model — Interrupt Glow 1.1

## Update latency

| Signal | Work | Expected visual latency |
|---|---|---:|
| Target/focus cast start, stop or interruptibility event | fixed-unit snapshot and currently bound interrupt records only | synchronous handler update |
| Blizzard/LAB/Dominos action feedback change | one button enters a deduplicated queue | next frame |
| ButtonForge conditional macro change | three raw field reads; enqueue only if resolved identity changed | next frame |
| Relevant `SPELL_UPDATE_COOLDOWN` | event-time plain GCD hint plus one cooldown pass for active abilities | next frame |
| Accessible cooldown deadline | one shared active driver | at most 50 ms plus one frame |
| Restricted cooldown timing | one shared low-frequency driver | 250 ms background; forced immediately when a relevant cast starts |
| Integer cooldown text | same shared driver | 200 ms, while visible |
| Initial ordinary-button shell prewarm | 16 physical buttons per frame | current interrupts are immediate; remaining bars spread across frames |

Current Blizzard data exposes at most two player interrupt families for a specialization. Therefore a full readiness pass is bounded by one or two ability states, not the number of action buttons.

## Mouseover hot path

For a Blizzard/LAB/Dominos conditional macro transition:

```text
provider callback
  -> weak-map record lookup
  -> one deduplicated dirty entry
  -> current slot classification
  -> reuse existing ability/readiness/cast state
  -> ordinary parent alpha transition
```

It does not perform:

- macro-body parsing;
- frame enumeration;
- 540-slot scanning;
- nameplate traversal;
- cast API reads when accessible cast state is already cached;
- cooldown API reads when the ability generation remains current;
- frame, texture, font string, animation or timer creation.

The mock regression suite executes 2,000 heal/interrupt feedback transitions and asserts zero new UI objects and zero repeated cast/cooldown API reads.

## Cooldown event filtering

`SPELL_UPDATE_COOLDOWN` provides a changed spell and cooldown category. Interrupt Glow ignores an unrelated event with no real cooldown category, which is normally a GCD-only signal. Relevant interrupt, global and shared-category events remain conservative.

`isOnGCD` is never read one frame later. During the actual Blizzard event, it is normalized to a plain per-ability hint; the frame-batched readiness pass consumes only that ordinary boolean.

## Restricted data

- Secret cast interruptibility is sent directly to `SetAlphaFromBoolean(..., 0, 255)`.
- Restricted LoC is treated as unknown/blocking, never as clear.
- Exact `currentCharges == 0` remains not-ready even when recharge timing is secret.
- Secret remaining time never becomes a custom number.
- A newly relevant cast forces an immediate readiness poll if restricted timing had been waiting on the 250 ms background driver.

## Startup cost

Interrupt Glow itself is not LoadOnDemand because it must observe combat automatically. Startup is lazy internally:

1. TOC loads code and a bare Settings canvas.
2. Gameplay event registration, provider attach and registry discovery wait for `PLAYER_LOGIN`.
3. Already-loaded providers are enumerated exactly once.
4. Bartender, ElvUI, Dominos, ButtonForge and Cooldown Viewer use load-order callbacks rather than polling.
5. Current interrupt buttons receive visuals immediately.
6. Other physical button shells are prewarmed at 16 buttons per frame.
7. Options controls, debug window and cooldown font strings are created only when needed.

## Ship gates

- no `EnumerateFrames`;
- no `C_NamePlate.GetNamePlates`;
- no macro-body API in runtime files;
- no Interrupt Glow subscription to `ACTIONBAR_UPDATE_COOLDOWN` or `ACTIONBAR_SLOT_CHANGED`;
- no frame creation during combat;
- no secret payload storage/logging/readback;
- no >5 ms Interrupt Glow spikes during the 60-second live mouseover stress test;
- no duplicate startup/provider discovery;
- no stale CDM binding after pool reset/reuse.
