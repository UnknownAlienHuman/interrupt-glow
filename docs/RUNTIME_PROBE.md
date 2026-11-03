# Runtime probe

Interrupt Glow includes a session-only in-client evidence collector. It is disabled until explicitly started and adds no internal-counter work while inactive.

## Commands

```text
/iglow probe
/iglow capture start quick-heal-mouseover
/iglow capture mark baseline
/iglow capture mark friendly-hover
/iglow capture mark hostile-hover
/iglow capture stop
/iglow capture show
```

`/iglow probe` opens an immediate snapshot. `capture start` clears only Interrupt Glow's addon-owned session counters and records a native profiler baseline. Blizzard `C_AddOnProfiler` counters are application-session cumulative and are **not reset**. `capture stop` records the final snapshot and reports threshold-counter deltas.

A capture stores at most 256 manual markers and 128 restriction transitions. Additional entries are counted as dropped. Stop and report construction are deferred by the user until combat ends; restriction callbacks do not trigger automatic profiler snapshots.

## Report sections

- `build`: current WoW build, Interface, addon version, pinned Blizzard source, KB commit, SavedVariables schema/producer;
- `context`: instance type/difficulty, combat state and observed restriction transitions;
- `providers`: loaded/attached state for native bars, LibActionButton, Dominos, ButtonForge and Cooldown Viewer;
- `workers`: OnUpdateMode support, dirty state, prewarm queue state and active runtime timing state;
- `policies`: conservative GCD readiness policy;
- `capture`: scenario label, duration and markers;
- `casts`: normalized target/focus state, last event and phantom-channel suppression;
- `secrecy`: current `C_Secrets` policy for active interrupt spells/action slots;
- `abilities`: normalized per-ability readiness/restriction state;
- `counters`: session-only addon path counters;
- `profiler`: native profiler start/end snapshots, a new-session-peak boolean, threshold deltas and marker snapshots;
- `configuration`, `providerVersions`, `probeBounds`: active preferences, provider versions and stored/dropped evidence counts.

Profiler fields include session/recent/encounter averages, last/peak time and threshold counts from 1 ms through 1000 ms. The probe never stores or formats raw SecretValue payloads.

## Attribution matrix

Run the same measured scenario for the same duration and location:

1. default UI with all third-party addons disabled;
2. Interrupt Glow only;
3. Interrupt Glow plus the required action-bar provider;
4. normal full addon stack.

Keep visible-nameplate count, target/focus behavior, macro, instance, combat state and duration equal. Native profiler deltas attribute threshold crossings during each capture window. `PeakTime` is session-global and is reported as start/end plus a new-session-peak boolean, not a resettable window maximum.

## Quick Heal mouseover reproduction

1. `/reload` with the intended action-bar provider enabled.
2. `/iglow capture start quick-heal-mouseover`
3. Mark `baseline`.
4. Hover friendly units repeatedly for 30 seconds.
5. Mark `friendly-hover-complete`.
6. Hover hostile units/nameplates repeatedly for 30 seconds.
7. Mark `hostile-hover-complete`.
8. Stop and show the capture.

Also record FPS, visible nameplate count, provider/version, `/console taintLog 2`, Lua/secret/forbidden errors and whether the original lag remains.

## GCD/personal-cooldown overlap test

The report must contain:

```text
gcd.ignoreGlobalCooldownDuration=true
gcd.isOnGCDReadinessProof=false
```

Test a real interrupt with a personal cooldown while another global cooldown is active:

1. start a capture before using the interrupt;
2. use the interrupt and immediately trigger/observe another GCD where possible;
3. mark `personal-cooldown-plus-gcd`;
4. target or focus an interruptible cast during the overlap;
5. confirm the interrupt glow stays hidden until the personal ignore-GCD duration reaches zero;
6. repeat in a restricted Mythic+/raid/PvP context.

`isOnGCD=true` must never make an active personal cooldown appear ready. `UNIT_SPELLCAST_SUCCEEDED` may invalidate readiness but is not evidence that a GCD began or ended.

## Worker idle test

After `/reload`, with countdown disabled and no relevant cast:

```text
flush.dirty=false
prewarm.pending=false       -- after bounded startup prewarm settles
prewarm.scheduled=false
runtime.enabled=false
```

Repeat after leaving combat, changing target/focus, opening/closing Settings and disabling the addon. A worker may briefly be active while actual work exists; it must return to Disabled afterward.

## SavedVariables migration test

Before reload, preserve a copy of `InterruptGlowDB`. After beta.9 loads, the report must show:

```text
savedSchema=4
savedProducerVersion=1.1.0-beta.9
savedInterface=120105
```

Only documented typed preferences may remain. Legacy `slots`, `localCD`, `debugAutoShow`, unknown keys, frame references and transient caches must be absent. Verify preferences such as enabled/CD text/CDM/strict policy still migrate correctly.

## Cooldown Viewer pool test

Change Cooldown Viewer layout/settings, disable/re-enable the option and force item pool reuse. Verify:

- no visual flicker or binding mutation occurs inside Blizzard reset callbacks;
- one latest identity wins if reset and reuse occur before the addon flush;
- the active item rebinds after re-enable;
- no stale glow remains on a recycled non-interrupt item.

## Active UnitChannelInfo regression matrix

`WOWUI-2026-005` remains active. After `UNIT_SPELLCAST_CHANNEL_STOP` or `UNIT_SPELLCAST_EMPOWER_STOP`, later `UnitChannelInfo` snapshots are ignored until a real start or target/focus identity change.

Run:

1. target death/loss during channel;
2. Lightning Lasso phantom channel reproduction;
3. repeated Ray of Frost channels.

Confirm no addon-visible channel/glow resurrects after stop, and retire the workaround only after a named live build passes all exact reproductions without the guard.

## Appearance and preview

Open `/iglow` at the intended UI scale. Verify labels fit the Settings canvas, cyan target and amber focus highlights render correctly, and disabling animation stops only the ordinary parent animation. Start the preview outside combat; entering combat or disabling the addon must stop it. Settings first opened in combat must create no controls until combat ends.

## Existing visual access transitions

On a named client/build and provider, observe an already-created highlight, countdown and animation across a real object-access restriction transition. A denied destination must receive no further setters or timer-driven access retries. If all copies are denied, the timing worker must sleep. Do not force forbidden aspects or query opaque output to manufacture evidence.

Repeat with the button unbound and the addon disabled during the restriction. On an ordinary restriction/provider/out-of-combat recovery signal, any now-accessible old display must clear; active records must refresh current cast/readiness before showing again. Confirmed forbidden destinations must remain skipped. Offline permission mocks cover control flow only; this client scenario remains NOT-RUN.

## Evidence boundary

The probe is runtime evidence for one build/context. It is not a permanent secrecy whitelist and does not replace Mythic+, raid, arena/BG, provider load-order, taint, secure-execution or upstream-retirement testing.
