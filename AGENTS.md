# Agent instructions — Interrupt Glow

## Target and route

Retail / Midnight **12.1.5**, Interface **120105**. Current source and KB pins, inspected API contracts and unresolved evidence are owned by [docs/API_REVIEW.md](docs/API_REVIEW.md). Source review is not a runtime PASS.

Read this file, `InterruptGlow.toc`, [architecture](ARCHITECTURE.md) and affected modules first. Then read the shared KB's `AGENTS.md`, `INDEX_MINI.md`, relevant current overlays and owning guides: DevWorkflow, EventPatterns, Performance_Modules, security/current spell secrecy, ActionBars/CooldownViewer and SavedVariables. Check current active issues before changing workarounds. Historical documents do not override selected source.

Keep one manager-owned checkout; workers edit assigned files there. Use the GitHub connector when local Git networking is unavailable. Verify push permission, pin the base, validate changes, re-read the remote head and publish with a non-forced expected-SHA update. Do not merge without authorization. Keep GitHub Actions workflows absent.

## Runtime requirements

- One implementation owner per behavior. Use explicit module methods; do not add runtime wrappers that replace another module's functions.
- No frame/nameplate enumeration, global action-slot scans or macro-body parsing.
- Do not subscribe to `ACTIONBAR_UPDATE_COOLDOWN`. `ACTIONBAR_SLOT_CHANGED` belongs only to LABAdapter and routes to already-indexed buttons.
- Native action callbacks queue known identities; they do not query action/cooldown state in the callback.
- Gate secret-capable values before type/value operations, keys, serialization or logging. Gate foreign tables and consumed fields. `pcall`, delay and copying do not declassify data.
- Raw cast `notInterruptible` may flow only directly to `SetAlphaFromBoolean(..., 0, 255)`. Never retain it, pass it through `pcall`, read back the child alpha or animate that child.
- Do not bind secret duration objects to addon cooldown/statusbar/text widgets.
- Create reusable visual objects outside combat. Recheck foreign-object access at the operation boundary; do not poll denied objects.
- Keep callback attachment/detachment idempotent, handles balanced once, optional-provider waiters deduplicated, and permanent hooks cheaply guarded while detached.
- Use `SetOnUpdateMode`: RunOnce for dirty/prewarm slices, RunAlways only for active timing work, Disabled while idle.
- Disabled means runtime/provider/fixed-unit subscriptions detached, pending work cleared, preview stopped and workers asleep. Regen lifecycle and restriction telemetry may remain.
- Conditional action identities remain pending until reconciliation succeeds. Flush deferred identities before the readiness pass; a stale branch must never display a previous ready result.
- Buttons owns bound-source selection. Cooldown applies duration, charges, Loss of Control and usability gates and commits the final result once. Dormant same-spec abilities may be reused; specialization changes prune them and reset source caches.
- Exclude the GCD using duration getter `true` arguments. `isOnGCD` and `UNIT_SPELLCAST_SUCCEEDED` are never positive readiness evidence. Inaccessible charges, usability and Loss of Control fail closed.
- CDM pool hooks capture ordinary identity and queue work; visual mutation occurs in the addon-owned pass.
- SavedVariables contain only typed preferences and producer/schema metadata. Keep `LoadSavedVariablesFirst` while migration occurs at file scope.
- Use explicit unit varargs with `RegisterUnitEvent`. Keep the phantom-channel stop guard until the documented retirement gate passes.

## Validation and reporting

Run `python3 tools/test.py`; select a Lua interpreter with `--lua` if needed. The runner verifies actual TOC sources and behavioral tests. Add regressions for changed failure boundaries, not assertions that repeat implementation flags.

Report command/scenario, tested ref/tree, result and limits. Missing tools are SKIPPED; unavailable client checks are NOT-RUN. Do not replace client evidence with mocks.

Required client coverage: Quick Heal mouseover, equal-input native profiler attribution, restricted content, `taintLog 2`, provider load order/late load, enable/disable, Warlock/PWarrior variants, CDM reuse, phantom channels, unit filtering, worker idle state, SavedVariables login/reload, preview cleanup and GCD/personal-cooldown overlap. [Runtime probe](docs/RUNTIME_PROBE.md) owns procedures.
