from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "InterruptGlow.toc"
EXPECTED_INTERFACE = "120105"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def toc_entries() -> list[str]:
    entries: list[str] = []
    for raw in read(TOC).splitlines():
        line = raw.strip()
        if line and not line.startswith("##"):
            entries.append(line)
    return entries


def require(text: str, snippets: tuple[str, ...], scope: str) -> list[str]:
    return [f"{scope} is missing {snippet}" for snippet in snippets if snippet not in text]


def forbid(text: str, snippets: tuple[str, ...], scope: str) -> list[str]:
    return [f"{scope} contains forbidden {snippet}" for snippet in snippets if snippet in text]


ENTRIES = toc_entries()
RUNTIME_FILES = [ROOT / entry for entry in ENTRIES if (ROOT / entry).is_file()]


def check_toc_and_load_order() -> list[str]:
    errors: list[str] = []
    toc = read(TOC)
    if len(ENTRIES) != len(set(ENTRIES)):
        errors.append("TOC contains duplicate Lua sources")
    for entry in ENTRIES:
        if not (ROOT / entry).is_file():
            errors.append(f"TOC source does not exist: {entry}")

    metadata = [line.strip() for line in toc.splitlines() if line.strip().startswith("##")]
    if f"## Interface: {EXPECTED_INTERFACE}" not in metadata:
        errors.append(f"TOC Interface must be {EXPECTED_INTERFACE}")
    if "## LoadSavedVariablesFirst: 1" not in metadata:
        errors.append("TOC must load SavedVariables before addon Lua files")
    if "## SavedVariables: InterruptGlowDB" not in metadata:
        errors.append("TOC must declare InterruptGlowDB")

    required_order = (
        "Core.lua",
        "core/Worker.lua",
        "core/Shared.lua",
        "core/Data.lua",
        "core/Buttons.lua",
        "core/LABAdapter.lua",
        "core/ActionResolver.lua",
        "core/Cooldown.lua",
        "core/Usability.lua",
        "core/ConditionalActions.lua",
        "core/CastTracking.lua",
        "core/CDM.lua",
        "core/RuntimeLifecycle.lua",
        "core/Events.lua",
        "Options.lua",
    )
    try:
        positions = [ENTRIES.index(entry) for entry in required_order]
        if positions != sorted(positions):
            errors.append("TOC owner modules are loaded in an unsafe order")
    except ValueError as exc:
        errors.append(f"TOC is missing a required owner module: {exc}")

    core_files = {path.name for path in (ROOT / "core").glob("*.lua")}
    toc_core_files = {Path(entry).name for entry in ENTRIES if entry.startswith("core/")}
    for orphan in sorted(core_files - toc_core_files):
        errors.append(f"Unloaded runtime source remains in core/: {orphan}")
    return errors


def check_forbidden_hot_paths() -> list[str]:
    errors: list[str] = []
    forbidden_patterns = {
        "frame enumeration": r"\bEnumerateFrames\b",
        "nameplate traversal": r"\bGetNamePlates\b|\bC_NamePlate\b",
        "global action-slot scan": r"\b540\b",
        "macro body parsing": r"\bGetMacroInfo\s*\(|\bGetMacroSpell\s*\(",
        "cooldown update event subscription": r"RegisterEvent\s*\(\s*[\"']ACTIONBAR_UPDATE_COOLDOWN",
        "unverified spell secrecy event subscription": r"RegisterEvent\s*\(\s*[\"']SPELL_SECRECY_CHANGED",
        "generic addon-loaded event subscription": r"RegisterEvent\s*\(\s*[\"']ADDON_LOADED",
        "legacy global spell LoC API": r"\bGetSpellLossOfControlCooldown\s*\(",
        "legacy scriptProfile setting": r"\bscriptProfile\b",
    }
    for path in RUNTIME_FILES:
        text = read(path)
        relative = path.relative_to(ROOT).as_posix()
        for label, pattern in forbidden_patterns.items():
            if re.search(pattern, text):
                errors.append(f"{relative} contains forbidden {label}")
        if path.name != "LABAdapter.lua" and re.search(
            r"RegisterEvent\s*\(\s*[\"']ACTIONBAR_SLOT_CHANGED", text
        ):
            errors.append(f"{relative} subscribes to ACTIONBAR_SLOT_CHANGED outside LABAdapter")
    return errors


def check_action_and_provider_ownership() -> list[str]:
    errors: list[str] = []
    buttons = read(ROOT / "core/Buttons.lua")
    resolver = read(ROOT / "core/ActionResolver.lua")
    actions = read(ROOT / "core/ConditionalActions.lua")
    lab = read(ROOT / "core/LABAdapter.lua")
    cdm = read(ROOT / "core/CDM.lua")

    callback_start = buttons.find("function Buttons:OnNativeActionChanged")
    callback_end = buttons.find("local function ObserveNativeFrame", callback_start)
    callback = buttons[callback_start:callback_end] if callback_start >= 0 and callback_end >= 0 else ""
    errors += require(
        callback,
        ("IG.PendingButtons[button]", "IG:MarkButtonDirty(button)"),
        "Native action callback",
    )
    errors += forbid(
        callback,
        ("GetActionInfo", "IsInterruptAction", "IsAssistedCombatAction", "ResolveRecord", "GetSpell"),
        "Native action callback",
    )
    errors += require(
        resolver,
        ("function Resolver:ResolveRecord(record)", "IsInterruptAction", "IsAssistedCombatAction", "GetActionSlot"),
        "Action resolver owner",
    )
    errors += require(
        actions,
        ("slotByButton = setmetatable({}, { __mode = \"k\" })", "buttonsBySlot = {}", "deferredButtons = setmetatable({}, { __mode = \"k\" })", "function Actions:FlushDeferred()"),
        "Conditional action index",
    )
    errors += forbid(actions, ("GetMacroInfo", "GetMacroSpell", "EnumerateFrames", "GetNamePlates"), "Conditional action index")
    errors += require(
        lab,
        ("RegisterEvent(\"ACTIONBAR_SLOT_CHANGED\")", 'slotEventFrame:SetScript("OnEvent"', "function Adapter:Detach()"),
        "LAB action-slot routing",
    )
    errors += require(
        cdm,
        ("function CDM:ObserveItem(itemFrame)", "QueueIdentityChange(itemFrame, canonicalSpellID)", "IG:MarkButtonDirty(itemFrame)", "function CDM:Detach()"),
        "Cooldown Viewer lifecycle owner",
    )
    return errors


def check_secret_readiness_and_visual_boundaries() -> list[str]:
    errors: list[str] = []
    shared = read(ROOT / "core/Shared.lua")
    cooldown = read(ROOT / "core/Cooldown.lua")
    usability = read(ROOT / "core/Usability.lua")
    cast = read(ROOT / "core/CastTracking.lua")
    glow = read(ROOT / "core/Glow.lua")

    errors += require(
        shared,
        ("function IG.CanAccessTable(value)", "canaccesstable", "if type(container) == \"table\" and not self.CanAccessTable(container) then"),
        "Shared access gate",
    )
    errors += require(
        cooldown,
        ("GetActionCooldownDuration, slot, true", "GetSpellCooldownDuration, spellID, true", "GetSpellLossOfControlCooldownInfo", "hardRestricted"),
        "Cooldown and Loss of Control owner",
    )
    errors += forbid(cooldown, ("gcdHints", "isOnGCD"), "Cooldown readiness")
    errors += require(
        usability,
        ("GetPetActionSlotUsable", "function Usability:ReadForAbility(ability)", "not IG:NeedsReadinessRuntime() then return false end"),
        "Usability gates",
    )
    errors += require(
        cast,
        ("rawNotInterruptible", "ApplyUnitInterruptibility", "channelSuppressed", "IsStaleCastEvent"),
        "Cast lifecycle and secret bridge",
    )
    if re.search(r"pcall\s*\(\s*Unit(?:Channel|Casting)Info", cast):
        errors.append("Cast secret bridge wraps raw cast results in pcall")
    errors += require(glow, ("SetAlphaFromBoolean", "local function CandidateFor(record, unit)", "record.conditionalIdentityPending == true"), "Glow visual gate")
    errors += forbid(glow, ("CreatePulseAnimation(overlay.target.niGate)", "CreatePulseAnimation(overlay.focus.niGate)"), "Secret alpha region")
    if "pcall(method, region, value" in glow:
        errors.append("Glow wraps the raw secret alpha sink in pcall")
    return errors


def check_events_lifecycle_persistence_and_workers() -> list[str]:
    errors: list[str] = []
    events = read(ROOT / "core/Events.lua")
    lifecycle = read(ROOT / "core/RuntimeLifecycle.lua")
    shared = read(ROOT / "core/Shared.lua")
    worker = read(ROOT / "core/Worker.lua")
    probe = read(ROOT / "core/RuntimeProbe.lua")
    debug = read(ROOT / "core/Debug.lua")

    errors += require(
        events,
        ("local RUNTIME_EVENTS = {", "local PERSISTENT_EVENTS = {", 'frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")', 'frame:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", "player")', 'frame:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", "player")', 'event == "PLAYER_REGEN_DISABLED"'),
        "Runtime events",
    )
    if re.search(r"RegisterUnitEvent\s*\([^)]*,\s*\{", events) or re.search(r"RegisterUnitEvent\s*\([^)]*,\s*\{", read(ROOT / "core/CastTracking.lua")):
        errors.append("RegisterUnitEvent uses a unit-token table instead of unit varargs")
    errors += require(
        lifecycle,
        ("function Lifecycle:Deactivate()", "IG.testMode = false", "SetRuntimeEventsEnabled(false)", "Buttons:Detach()", "CastTracking:Detach()", "CDM:Detach()"),
        "Master runtime lifecycle",
    )
    errors += require(
        shared,
        ("CURRENT_SCHEMA = 4", "CURRENT_INTERFACE = 120105", "producerVersion", "InterruptGlowDB = DB", "Worker:RunOnce(flushFrame)"),
        "SavedVariables and dirty queue",
    )
    errors += forbid(shared, ("rawNotInterruptible", "frame =", "callbackHandle ="), "SavedVariables boundary")
    errors += require(worker, ("SetOnUpdateMode", "modes.Disabled", "modes.RunOnce", "modes.RunAlways"), "Worker mode owner")
    errors += require(probe, ("ProfilerSnapshot", "newSessionPeak", "AppendProfilerDeltas"), "Runtime probe evidence")
    errors += forbid(probe, ("PeakTimeIncrease", "GetAddOnPerformanceInfo", "scriptProfile"), "Runtime profiler")
    errors += require(debug, ("function Debug:ProfilerDelta(startSnapshot, endSnapshot)", "delta.newSessionPeak = afterPeak > beforePeak"), "Session profiler delta")
    return errors


def check_test_harness() -> list[str]:
    errors: list[str] = []
    runner = read(ROOT / "tools/test.py")
    syntax = read(ROOT / "tests/check_syntax.lua")
    toc_test = read(ROOT / "tests/toc_contract.lua")
    integration = read(ROOT / "tests/mock_wow.lua")
    data_test = read(ROOT / "tests/data_cdm_integration.lua")

    errors += require(
        runner,
        ('LUA_CANDIDATES = ("lua5.1", "luajit", "lua", "texlua")', 'add_argument("--lua"', "def lua_files_to_check()", 'glob("*.lua")', "subprocess.run(", "tests/static_checks.py"),
        "Offline test runner",
    )
    errors += require(syntax, ("loadfile(path)", "#arg == 0"), "Discovered Lua syntax check")
    errors += require(toc_test, ("## LoadSavedVariablesFirst: 1", "Core.lua", "core/Worker.lua", "core/Shared.lua"), "TOC/SavedVariables regression")
    errors += require(integration, ('io.open(ROOT .. "/InterruptGlow.toc", "r")', 'loadfile(ROOT .. "/" .. path)', "InterruptGlowDB == IG.DB"), "TOC-driven modeled integration")
    errors += require(
        data_test,
        ("inaccessible spell ID was used as a cache key", "negative cache repeated canonical resolution", "static direct-spell and CDM proof fail", "inaccessible CDM frame reached weak-table indexing", 'CDM:SetEnabled(false)', 'CDM:SetEnabled(true)'),
        "Data/CDM behavior regression",
    )

    workflow_dir = ROOT / ".github/workflows"
    if workflow_dir.exists() and any(workflow_dir.glob("*.y*ml")):
        errors.append("GitHub Actions workflows must remain absent")
    return errors


def main() -> int:
    checks = (
        check_toc_and_load_order,
        check_forbidden_hot_paths,
        check_action_and_provider_ownership,
        check_secret_readiness_and_visual_boundaries,
        check_events_lifecycle_persistence_and_workers,
        check_test_harness,
    )
    errors: list[str] = []
    for check in checks:
        try:
            errors.extend(check())
        except (OSError, UnicodeError) as error:
            errors.append(f"{check.__name__} could not inspect source: {error}")

    if errors:
        print("STATIC CHECKS FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("STATIC CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
