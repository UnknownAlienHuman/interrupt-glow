# InterruptGlow TODO

## Done in this pass

- [x] Изучены `_Info/KB/core/BlizzardUI_Community_Insights.md`, `_Info/Cleaning/wowuidev_live/05_CASTBARS_COOLDOWNS_ACTIONBARS.md`, `_Info/KB/core/BlizzardUI_HookDecisionTree.md`, `_Info/KB/core/BlizzardUI_security.md`, `_Info/KB/core/BlizzardUI_Lifecycle_LoadOnDemand.md`, `_Info/KB/nodes/BlizzardUI_UnitFrames.md`.
- [x] Перепроверена Blizzard castbar pipeline по локальному source build `12.0.1.66198`.
- [x] `Core.lua` распилен до bootstrap/launcher слоя.
- [x] Логика вынесена в отдельные узлы:
  - `core/Shared.lua`
  - `core/Debug.lua`
  - `core/Buttons.lua`
  - `core/Cooldown.lua`
  - `core/CastTracking.lua`
  - `core/Glow.lua`
  - `core/Events.lua`
  - `core/Slash.lua`
- [x] `InterruptGlow.toc` обновлён под новый load order.

## Current architecture

- [x] `Core.lua` только поднимает `InterruptGlow`, `InterruptGlow.Private` и launcher frame.
- [x] Shared state и safe wrappers живут в `core/Shared.lua`.
- [x] Hot-path logic (`Cooldown`, `CastTracking`, `Glow`) отделена от bootstrap.
- [x] Event routing собран в одном месте (`core/Events.lua`), slash/debug вынесены отдельно.

## Next

- [x] Починить NI detection для dungeon/instance casts через Blizzard castbar authority.
  `core/CastTracking.lua` теперь предпочитает Blizzard castbar verdict (`target`/`focus`/target nameplate) раньше `UnitCastingInfo`, чтобы не терять uninterruptible casts в инстансах, где unit API даёт `nil` или stale state.
- [x] Добавить safe post-hook на Blizzard castbar update path без `HookScript`.
  Введён `hooksecurefunc` на `CastingBarMixin:OnEvent` и `:UpdateInterruptibleState`, чтобы смена interruptibility в середине каста сразу переписывала runtime state без edit-mode taint.
- [x] Прогнать локальную верификацию после фикса и подготовить task commit.
  Прогнан `npx --yes luaparse` по `core/CastTracking.lua`, `git diff --check` чистый; живой тест в данже остаётся отдельным незавершённым шагом ниже.
- [x] Выделить явную strategy matrix внутри `core/CastTracking.lua`.
  Введён единый NI resolver с policy lanes `event-first`, `unit-api-first`, `castbar-fallback:*`, `forbidden-nameplate`.
- [x] Добавить in-code audit comment над strategy selection.
  Матрица authority теперь зафиксирована рядом с `NI_STRATEGY`, включая `target`, `focus`, `nameplate`, `boss-token`, `unknown/secret`.
- [x] Починить resync при появлении normal/forbidden nameplate у `target`/`focus`.
  `core/Events.lua` теперь обрабатывает `NAME_PLATE_UNIT_ADDED` и `FORBIDDEN_NAME_PLATE_UNIT_ADDED` через `MapEventUnit`, а `core/Shared.lua` больше не опирается на недокументированный `GetNamePlateForUnit("target")`.
- [x] Убрать прямой slash-cleanup `extraButtons` и сузить ложные macro matches.
  `/iglow cdm` теперь идёт через `ClearExtraButtons` + `MarkReadyDirty`, а macro text/attributes проверяются с boundary matching вместо голого substring.
- [x] Усилить secret/taint guards на unit/cooldown surfaces.
  `core/Shared.lua` получил `pcall`-safe wrappers для `Unit*`, а `core/Cooldown.lua` читает cooldown/charge tables через safe member access и выделяет отдельный `cdSrc=secret` path.
- [x] Сделать `pcall` observable, а не silent.
  Guarded paths теперь пишут в debug ring, считают `guard` stats, показывают throttled chat warning и попадают в `/iglow stats` + `/iglow state`.
- [x] Убрать runtime state с Blizzard frame userdata там, где это давало taint-риск.
  `core/Glow.lua` и `core/Cooldown.lua` переведены на side tables вместо `__IG_*`, а `core/CastTracking.lua` больше не делает `HookScript` на Blizzard unit-frame castbars.
- [ ] Прогнать живой тест в данже/рейде после модульного рефактора.
  Цель: убедиться, что архитектурный распил не вернул ложные glow или регресс по CPU.
