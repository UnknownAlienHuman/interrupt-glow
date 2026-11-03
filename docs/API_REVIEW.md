# Retail 12.1.5 source review

Checked **2026-11-02**. The fetched `Gethe/wow-ui-source` **live** branch resolves to `d07eb00237d8891f153215db98a5df880a26cfe5`, commit **12.1.5 (70688)** dated 2026-10-31. Shared guidance: `UnknownAlienHuman/wow-addon-engineering-kb@b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`.

This is source evidence for Retail. Interface **120105** is the selected patch-family declaration. `GetBuildInfo`, rendering, restriction, taint and performance checks in the actual client are **NOT-RUN**.

## Inspected contracts

All source paths below refer to the same [Blizzard UI commit](https://github.com/Gethe/wow-ui-source/tree/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns).

| Source path under `Interface/AddOns/` | Symbol / decision |
|---|---|
| `Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua` | `GetActionCooldownDuration(actionID, ignoreGCD)` returns a duration object. Continue passing `true`; no signature migration needed. |
| `Blizzard_APIDocumentationGenerated/SpellDocumentation.lua` | `GetSpellCooldownDuration(spellID, ignoreGCD)` retains the same contract. A cooldown status marked on GCD does not establish personal-cooldown readiness. |
| `Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` | Cast events are secret-capable; `castBarID` is explicitly NeverSecret. Consume only that sequence identity from stop payloads. |
| `Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua` | Spell/action cooldown and unit casting predicates remain available for scoped diagnostics. Their results are access-gated. |
| `Blizzard_ActionBar/Shared/ActionButton.lua` | `ActionBarActionButtonMixin:UpdateAction` emits `ActionButton.OnActionChanged` except for the Assisted Combat rotation action. The callback is not a universal third-party button feed. |
| `Blizzard_CooldownViewer/CooldownViewer.lua` | `CooldownViewerMixin:OnAcquireItemFrame` remains an internal acquisition hook. |
| `Blizzard_CooldownViewer/CooldownViewerItemData.lua` | `OnCooldownIDSet` and `ResetCooldownData` remain the inspected pooled-identity hooks. These internal hooks are version-sensitive, not a promised public extension API. |
| `Blizzard_DamageMeter/Blizzard_DamageMeter.toc` | Declares `LoadSavedVariablesFirst: 1`; the selected persistence guide supports this for file-scope addon migration. Interrupt Glow now declares it. |
| `Blizzard_Settings_Shared/Blizzard_SettingsPanel.lua` and `.xml` | Canvas categories use the current Settings panel lifecycle; native canvas is a plain frame. Open the stored category ID with `Settings.OpenToCategory`. |
| `Blizzard_CooldownBroadcaster/TrackedCooldowns.lua` | `namespace.InterruptSpellsBySpec`: all **34** generated specialization entries match this addon's snapshot. Source blob: `254e3b8028c5b6e55eb6f4cd380ad3e25b6e8a72`. The broadcaster is never loaded by this addon. |

The current 12.1.5 overlay marks several Cooldown timing setters protected. Interrupt Glow does not send duration objects to those setters; it reads accessible readiness and draws its own highlight. The setter change therefore does not require adding a cooldown-widget adapter.

## Unresolved source conflict

The current KB spell-secrecy registry recommends `SPELL_SECRECY_CHANGED`, but the inspected generated predicate documentation contains no matching event and the source search did not locate a producer. Search absence is not proof that no client event exists. The addon retains restriction/configuration invalidation and does not register an unverified event.

## Retained runtime gates

- `WOWUI-2026-005`: phantom/stale `UnitChannelInfo`; retain event-authoritative suppression until target-death, Lightning Lasso and Ray of Frost reproductions pass without it on a named build.
- `WOWUI-2026-009`: use explicit unit varargs for `RegisterUnitEvent`; no public table overload is established.
- Current cooldown restrictions, provider load order, pooled-frame reuse, visual/access inheritance and measured cost still require client evidence. Offline regression results are reported separately.

## Offline validation

The prepared beta.8 tree was checked on 2026-11-02 with `/usr/bin/texlua` reporting **Lua 5.3**:

- `python3 tools/test.py`: **39/39** behavioral tests passed, syntax passed for **59** TOC/test files, static invariants passed. The modeled integration loads the real TOC; fixtures do not load deleted policy wrappers.
- `python3 tools/sync_interrupts.py --source <pinned TrackedCooldowns.lua> --check`: all **34** specialization entries matched the source blob above.
- `git diff --check`: passed.

No Lua 5.1 interpreter or running WoW client was available. These results establish the tested offline behavior only; the client gates above remain **NOT-RUN**.
