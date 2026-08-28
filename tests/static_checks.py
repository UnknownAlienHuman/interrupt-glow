from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "InterruptGlow.toc"
CURRENT_VERSION = "1.1.0-beta.4"
CURRENT_KB_COMMIT = "071e6a755f4613908d019b23e8e121b0bf91ce5d"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def toc_entries() -> list[str]:
    entries: list[str] = []
    for raw in read(TOC).splitlines():
        line = raw.strip()
        if line and not line.startswith("##"):
            entries.append(line)
    return entries


TOC_ENTRIES = toc_entries()
RUNTIME_FILES = [ROOT / entry for entry in TOC_ENTRIES]

FORBIDDEN_RUNTIME_PATTERNS = {
    "EnumerateFrames": re.compile(r"\bEnumerateFrames\b"),
    "GetNamePlates": re.compile(r"\bGetNamePlates\b"),
    "540-slot scan": re.compile(r"\b540\b"),
    "GetMacroInfo": re.compile(r"\bGetMacroInfo\b"),
    "GetMacroSpell": re.compile(r"\bGetMacroSpell\b"),
    "ACTIONBAR_UPDATE_COOLDOWN subscription": re.compile(
        r"RegisterEvent\s*\(\s*[\"']ACTIONBAR_UPDATE_COOLDOWN"
    ),
    "unconfirmed SPELL_SECRECY_CHANGED subscription": re.compile(
        r"RegisterEvent\s*\(\s*[\"']SPELL_SECRECY_CHANGED"
    ),
    "generic ADDON_LOADED subscription": re.compile(
        r"RegisterEvent\s*\(\s*[\"']ADDON_LOADED"
    ),
    "Blizzard spell-alert manager mutation": re.compile(r"\bActionButtonSpellAlertManager\b"),
    "castbar state inspection": re.compile(
        r"\b(TargetFrameSpellBar|FocusFrameSpellBar|CastingBarMixin)\b"
    ),
}

EXPECTED_SPEC_SNIPPETS = {
    250: "[250] = { 47528 }",
    1480: "[1480] = { 183752 }",
    102: "[102] = { 78675 }",
    103: "[103] = { 106839 }",
    1467: "[1467] = { 351338 }",
    253: "[253] = { 147362 }",
    255: "[255] = { 187707 }",
    268: "[268] = { 116705 }",
    66: "[66] = { 96231 }",
    258: "[258] = { 15487 }",
    262: "[262] = { 57994 }",
    265: "[265] = { 119910, 132409 }",
    266: "[266] = { 119910, 119914 }",
    73: "[73] = { 6552, 386071 }",
}


def check_toc() -> list[str]:
    errors: list[str] = []
    text = read(TOC)
    core = read(ROOT / "Core.lua")

    if len(TOC_ENTRIES) != len(set(TOC_ENTRIES)):
        errors.append("TOC contains duplicate file entries")
    for entry in TOC_ENTRIES:
        if not (ROOT / entry).exists():
            errors.append(f"TOC references missing file: {entry}")

    if "## Interface: 120100" not in text:
        errors.append("TOC Interface is not 120100")
    if f"## Version: {CURRENT_VERSION}" not in text:
        errors.append(f"TOC version is not {CURRENT_VERSION}")
    if CURRENT_VERSION not in core:
        errors.append("Core fallback version does not match the TOC")
    if "## LoadOnDemand:" in text:
        errors.append("Interrupt Glow itself must not be LoadOnDemand")

    required_order = [
        "core/Worker.lua",
        "core/Shared.lua",
        "core/Debug.lua",
        "core/RuntimeProbe.lua",
        "core/Glow.lua",
        "core/Buttons.lua",
        "core/NativeCallbackPolicy.lua",
        "core/LABAdapter.lua",
        "core/ActionResolver.lua",
        "core/Cooldown.lua",
        "core/ReadinessPolicy.lua",
        "core/Usability.lua",
        "core/CachePolicy.lua",
        "core/CastTracking.lua",
        "core/Events.lua",
    ]
    try:
        positions = [TOC_ENTRIES.index(entry) for entry in required_order]
        if positions != sorted(positions):
            errors.append("Runtime integration/policy modules are loaded in the wrong order")
    except ValueError as exc:
        errors.append(f"TOC is missing a required runtime module: {exc}")

    return errors


def check_no_ci_workflows() -> list[str]:
    workflow_dir = ROOT / ".github" / "workflows"
    if not workflow_dir.exists():
        return []

    workflows = sorted(
        path.relative_to(ROOT).as_posix()
        for path in workflow_dir.iterdir()
        if path.is_file() and path.suffix.lower() in {".yml", ".yaml"}
    )
    if workflows:
        return ["GitHub Actions workflows must remain absent: " + ", ".join(workflows)]
    return []


def check_forbidden_patterns() -> list[str]:
    errors: list[str] = []
    for path in RUNTIME_FILES:
        text = read(path)
        for label, pattern in FORBIDDEN_RUNTIME_PATTERNS.items():
            if pattern.search(text):
                errors.append(f"{path.relative_to(ROOT)} contains forbidden runtime pattern: {label}")
    return errors


def check_saved_variables() -> list[str]:
    errors: list[str] = []
    shared = read(ROOT / "core" / "Shared.lua")

    for symbol in (
        "CURRENT_SCHEMA = 3",
        "producerVersion",
        "CURRENT_INTERFACE = 120100",
        "ReadBoolean",
        "ReadDebugKeep",
        "InterruptGlowDB = DB",
    ):
        if symbol not in shared:
            errors.append(f"SavedVariables sanitation is missing {symbol}")
    if "debugAutoShow" in shared or "unknownLegacyKey" in shared:
        errors.append("Runtime SavedVariables schema retains an obsolete/unknown key")
    if "slots =" in shared or "localCD =" in shared:
        errors.append("Runtime SavedVariables schema retains obsolete caches")
    return errors


def check_worker_policy() -> list[str]:
    errors: list[str] = []
    worker = read(ROOT / "core" / "Worker.lua")
    shared = read(ROOT / "core" / "Shared.lua")
    glow = read(ROOT / "core" / "Glow.lua")

    for symbol in ("SetOnUpdateMode", "modes.Disabled", "modes.RunOnce", "modes.RunAlways"):
        if symbol not in worker:
            errors.append(f"12.1 OnUpdate worker policy is missing {symbol}")
    if "Worker:RunOnce(flushFrame)" not in shared:
        errors.append("Shared dirty queue does not use a RunOnce worker")
    if "Worker:RunOnce(self.prewarmFrame)" not in glow:
        errors.append("Prewarm batching does not use a RunOnce worker")
    if "Worker:SetContinuous(self.runtimeFrame, enabled)" not in glow:
        errors.append("Runtime timer driver does not use explicit continuous mode")
    if "runtimeWorkerEnabled = nil" not in glow:
        errors.append("Runtime worker initial disable can be skipped by false-state deduplication")
    return errors


def check_secret_sink() -> list[str]:
    errors: list[str] = []
    cast = read(ROOT / "core" / "CastTracking.lua")
    glow = read(ROOT / "core" / "Glow.lua")

    if "rawNotInterruptible" not in cast or "ApplyUnitInterruptibility" not in cast:
        errors.append("CastTracking secret bridge is missing")
    if "SetAlphaFromBoolean" not in glow:
        errors.append("Visual secret sink is missing")
    if "ALPHA_VISIBLE = 255" not in glow:
        errors.append("Secret visual gate does not use documented full alpha 255")
    if "pcall(method, region, value" in glow or "pcall(region.SetAlphaFromBoolean" in glow:
        errors.append("Secret visual sink must be a direct API call, not a pcall result lane")
    if "pcall(UnitCastingInfo" in cast or "pcall(UnitChannelInfo" in cast:
        errors.append("Raw cast returns must not travel through a pcall result lane")
    if re.search(r"niRaw\s*=|notInterruptibleRaw\s*=", cast + glow):
        errors.append("Potential raw interruptibility storage detected")
    if "CreatePulseAnimation(overlay.target.niGate)" in glow:
        errors.append("Animation must not be attached to the secret-alpha region")
    if "CreatePulseAnimation(overlay.target.plainGate)" not in glow:
        errors.append("Ordinary parent-gate animation is missing")
    return errors


def check_startup_and_hot_paths() -> list[str]:
    errors: list[str] = []
    events = read(ROOT / "core" / "Events.lua")
    shared = read(ROOT / "core" / "Shared.lua")
    buttons = read(ROOT / "core" / "Buttons.lua")
    native = read(ROOT / "core" / "NativeCallbackPolicy.lua")
    lab = read(ROOT / "core" / "LABAdapter.lua")
    action_resolver = read(ROOT / "core" / "ActionResolver.lua")
    options = read(ROOT / "Options.lua")
    glow = read(ROOT / "core" / "Glow.lua")

    if events.count("Buttons:Attach(true)") != 1:
        errors.append("Expected exactly one callback-first startup attach/discovery call")
    if "DiscoverAll(false)" in events:
        errors.append("Startup must not run a second standalone discovery pass")
    if "ContinueOnPlayerLogin" not in events:
        errors.append("Runtime initialization is not deferred through ContinueOnPlayerLogin")
    if "local function RegisterRuntimeEvents()" not in events or "RegisterRuntimeEvents()" not in events:
        errors.append("Gameplay events are not registered lazily at PLAYER_LOGIN")
    if "_loadedOrLoading, loaded" not in shared:
        errors.append("IsAddOnFullyLoaded must inspect the second IsAddOnLoaded return")
    if "CastTracking:RefreshAll()" in buttons:
        errors.append("Button reconciliation must not snapshot target/focus per button")
    if "function Options:Build()" not in options or 'panel:SetScript("OnShow"' not in options:
        errors.append("Options controls are not lazily built on first panel show")
    if "ability.hasEvaluation" not in buttons or "evaluatedGeneration" not in buttons:
        errors.append("Dormant conditional-macro readiness is not generation-validated")
    if buttons.count('WaitForKnownLABProvider("ElvUI")') != 1:
        errors.append("ElvUI load-order waiter is missing or duplicated")
    if 'hooksecurefunc(BFButton, "ClearCommand"' not in buttons:
        errors.append("ButtonForge ClearCommand lifecycle hook is missing")

    if "CreateCallbackHandleContainer" not in native or "nativeCallbackHandles:Unregister" not in native:
        errors.append("Native callback registration lacks managed handle lifecycle")
    if "actionSnapshotFresh" not in action_resolver:
        errors.append("Native action snapshots are not reused by the reconcile pass")
    if "IsInterruptAction" not in action_resolver or "IsAssistedCombatAction" not in action_resolver:
        errors.append("Documented current-action classification is incomplete")

    slot_subscription = re.compile(r"RegisterEvent\s*\(\s*[\"']ACTIONBAR_SLOT_CHANGED")
    for runtime_path in RUNTIME_FILES:
        if runtime_path.name == "LABAdapter.lua":
            continue
        if slot_subscription.search(read(runtime_path)):
            errors.append(
                f"{runtime_path.relative_to(ROOT)} has a non-targeted ACTIONBAR_SLOT_CHANGED subscription"
            )
    if lab.count('RegisterEvent("ACTIONBAR_SLOT_CHANGED")') != 1:
        errors.append("LAB targeted action-slot invalidation is missing or duplicated")
    if "buttonsBySlot" not in lab or "for button in pairs(set)" not in lab:
        errors.append("LAB slot event is not bounded to pre-indexed buttons")
    if 'UnregisterCallback(self, "OnButtonUpdate")' not in lab:
        errors.append("Broad LAB visual-update callback is not removed for hookable providers")
    if 'hooksecurefunc, button, "UpdateAction"' not in lab:
        errors.append("Exact LAB UpdateAction post-hook is missing")

    if "function IG:NeedsReadinessRuntime()" not in shared:
        errors.append("On-demand readiness gate is missing")
    if "ability.readinessPending = true" not in shared:
        errors.append("Cooldown invalidation does not mark active abilities pending")
    if "not ReadinessPending(record)" not in glow:
        errors.append("Glow can display stale readiness while a refresh is pending")
    if "or ReadinessPending(record)" not in glow:
        errors.append("Cooldown text can display a stale deadline while pending")

    cd_text_order = re.compile(
        r"DB\.cdText\s*=\s*value.*?IG:MarkCooldownDirty\(false\).*?EnsureCooldownTexts\(\)",
        re.S,
    )
    if not cd_text_order.search(options):
        errors.append("Enabling cooldown text does not queue readiness before UI refresh")

    return errors


def check_channel_lifecycle() -> list[str]:
    errors: list[str] = []
    cast = read(ROOT / "core" / "CastTracking.lua")
    events = read(ROOT / "core" / "Events.lua")
    focused_test = ROOT / "tests" / "channel_guard.lua"

    required_cast_symbols = (
        "channelSuppressed",
        "IsStaleCastEvent",
        "UNIT_SPELLCAST_CHANNEL_UPDATE",
        "UNIT_SPELLCAST_EMPOWER_UPDATE",
        "ResetUnitIdentity",
        "ResetAllIdentities",
        "cast.channelSnapshotSuppressed",
    )
    for symbol in required_cast_symbols:
        if symbol not in cast:
            errors.append(f"Channel lifecycle mitigation is missing {symbol}")

    if 'SetChannelSuppressed(unit, true, event)' not in cast:
        errors.append("Channel/empower stop does not establish a phantom-snapshot guard")
    if 'ResetUnitIdentity("target", event)' not in events:
        errors.append("Target identity changes do not clear channel suppression")
    if 'ResetUnitIdentity("focus", event)' not in events:
        errors.append("Focus identity changes do not clear channel suppression")
    if "ResetAllIdentities(event)" not in events:
        errors.append("World transitions do not reset unit channel identities")

    if not focused_test.exists():
        errors.append("Focused UnitChannelInfo phantom regression test is missing")
    else:
        test_text = read(focused_test)
        for assertion in (
            "stale UnitChannelInfo resurrected after CHANNEL_STOP",
            "cast.staleStopIgnored",
            "PLAYER_TARGET_CHANGED",
            "RegisterUnitEvent requires unit varargs",
        ):
            if assertion not in test_text:
                errors.append(f"Channel regression test does not prove {assertion}")
    return errors


def check_readiness_policy() -> list[str]:
    errors: list[str] = []
    events = read(ROOT / "core" / "Events.lua")
    cooldown = read(ROOT / "core" / "Cooldown.lua")
    readiness_policy = read(ROOT / "core" / "ReadinessPolicy.lua")
    usability = read(ROOT / "core" / "Usability.lua")
    data = read(ROOT / "core" / "Data.lua")
    cache_policy = read(ROOT / "core" / "CachePolicy.lua")

    if "CaptureGCDHints" not in cooldown or "isOnGCD" not in cooldown:
        errors.append("SPELL_UPDATE_COOLDOWN GCD normalization is missing")
    if events.count("CaptureGCDHints()") != 1 or events.count("MarkCooldownDirty(true)") != 1:
        errors.append("GCD provenance must be captured exactly once in its event handler")
    for runtime_path in RUNTIME_FILES:
        if runtime_path.name == "Events.lua":
            continue
        if "MarkCooldownDirty(true)" in read(runtime_path):
            errors.append(
                f"{runtime_path.relative_to(ROOT)} marks cooldown dirty with unverified GCD provenance"
            )

    status_start = cooldown.find("local function ReadCooldownStatus")
    status_end = cooldown.find("local function ReadLossOfControlState")
    if (
        status_start >= 0
        and status_end > status_start
        and 'ReadMember(info, "isOnGCD")' in cooldown[status_start:status_end]
    ):
        errors.append("isOnGCD is read outside the event-time normalization path")

    if "hardRestricted" not in cooldown:
        errors.append("Hard restrictions are not represented separately")
    if "wasReadinessPending" not in cooldown or "ability.readinessPending = false" not in cooldown:
        errors.append("Fresh readiness evaluation does not resolve pending state")
    if "ability.hardRestricted == true and ability.needsPoll == true" not in readiness_policy:
        errors.append("Hard restrictions still activate periodic cooldown polling")
    if "GetPetActionSlotUsable" not in readiness_policy:
        errors.append("Pet readiness lacks intrinsic pet-action usability")

    for symbol in ("IsUsableAction", "IsSpellUsable", "OnActionUsableChanged"):
        if symbol not in usability:
            errors.append(f"Usability policy is missing {symbol}")
    if '"ACTION_USABLE_CHANGED"' not in events or '"SPELL_UPDATE_USABLE"' not in events:
        errors.append("Action/spell usability invalidation events are incomplete")
    if "return nil, nil, true, false, false, true" not in usability:
        errors.append("Inaccessible usability is not a hard fail-closed result")

    if "category ~= GLOBAL_RECOVERY_CATEGORY" not in data:
        errors.append("Global recovery category can be learned as an interrupt category")
    for symbol in ("PruneDormantAbilities", "ResetCaches", "generation = 0"):
        if symbol not in cache_policy:
            errors.append(f"Specialization cache policy is missing {symbol}")

    cdm = read(ROOT / "core" / "CDM.lua")
    if "QueueIdentityChange" not in cdm or "IG:MarkButtonDirty(itemFrame)" not in cdm:
        errors.append("Cooldown Viewer pool changes are not deferred through one dirty record")
    reset_start = cdm.find("function CDM:ResetItem")
    reset_end = cdm.find("local function OnAcquireItemFrame")
    if reset_start >= 0 and reset_end > reset_start and "UnbindRecord" in cdm[reset_start:reset_end]:
        errors.append("Cooldown Viewer reset mutates binding synchronously inside the hook stack")
    return errors


def check_runtime_probe() -> list[str]:
    errors: list[str] = []
    debug = read(ROOT / "core" / "Debug.lua")
    probe = read(ROOT / "core" / "RuntimeProbe.lua")
    agents = read(ROOT / "AGENTS.md")

    if CURRENT_KB_COMMIT not in probe or CURRENT_KB_COMMIT not in agents:
        errors.append("Runtime/project guidance is not pinned to the current KB commit")
    for symbol in (
        "ProfilerSnapshot",
        "ProfilerDelta",
        "SessionAverageTime",
        "CountTimeOver1000Ms",
        "GetTicksPerSecond",
        "IsEnabled",
    ):
        if symbol not in debug:
            errors.append(f"Native profiler diagnostics are missing {symbol}")
    for symbol in (
        "profilerStart",
        "profilerStop",
        "PeakTimeIncrease",
        "restrictionTransitions",
        "[providers]",
        "[workers]",
        "savedSchema",
        "WOWUI-2026-005",
        "channelSuppressed",
        "CaptureScalar",
    ):
        if symbol not in probe:
            errors.append(f"Runtime evidence report is missing {symbol}")
    if "scriptProfile" in debug or "scriptProfile" in probe:
        errors.append("Runtime diagnostics must not enable legacy scriptProfile")
    return errors


def check_interrupt_data() -> list[str]:
    errors: list[str] = []
    data = read(ROOT / "core" / "Data.lua")

    if "-- BEGIN GENERATED INTERRUPTS_BY_SPEC" not in data or "-- END GENERATED INTERRUPTS_BY_SPEC" not in data:
        errors.append("Generated interrupt snapshot markers are missing")
    for spec_id, snippet in EXPECTED_SPEC_SNIPPETS.items():
        if snippet not in data:
            errors.append(f"Missing current Blizzard mapping for spec {spec_id}: {snippet}")
    if re.search(r"\[115781\]\s*=|\{[^\n}]*\b115781\b", data):
        errors.append("Removed Retail Optical Blast ID 115781 returned to runtime data")
    if "EXTRA_INTERRUPTS_BY_SPEC" not in data or data.count("212619") < 3:
        errors.append("Warlock Call Felhunter PvP interrupt coverage is missing")
    if "[19647] = 119910" not in data or "[89766] = 119914" not in data:
        errors.append("Current Warlock pet-action aliases are incomplete")
    return errors


def check_local_test_harness() -> list[str]:
    errors: list[str] = []
    syntax = read(ROOT / "tests" / "check_syntax.lua")
    mock = read(ROOT / "tests" / "mock_wow.lua")

    if "InterruptGlow.toc" not in syntax or "toc:lines()" not in syntax:
        errors.append("Syntax checker does not derive runtime coverage from the TOC")
    for test_file in (
        "tests/mock_wow.lua",
        "tests/cdm_toggle.lua",
        "tests/runtime_probe.lua",
        "tests/native_callback_handles.lua",
        "tests/channel_guard.lua",
        "tests/shared_worker.lua",
        "tests/cache_policy.lua",
    ):
        if test_file not in syntax:
            errors.append(f"Syntax checker does not include {test_file}")

    for module in (
        "core/Worker.lua",
        "core/DiagnosticsPolicy.lua",
        "core/LABAdapter.lua",
        "core/ActionResolver.lua",
        "core/ReadinessPolicy.lua",
        "core/Usability.lua",
        "core/CachePolicy.lua",
        "core/RuntimeProbe.lua",
        "core/NativeCallbackPolicy.lua",
    ):
        if module not in mock and "InterruptGlow.toc" not in mock:
            errors.append(f"Mock harness does not load {module}")
    if "212619" not in mock:
        errors.append("Mock harness lacks Call Felhunter coverage")
    if "ACTION_USABLE_CHANGED" not in mock:
        errors.append("Mock harness lacks action-usability invalidation coverage")
    if "readinessPending" not in mock:
        errors.append("Mock harness lacks pending-readiness regression coverage")

    runtime_probe_test = read(ROOT / "tests" / "runtime_probe.lua")
    for assertion in (
        "delta.CountTimeOver5Ms=5",
        f"kbCommit={CURRENT_KB_COMMIT}",
        "focus.channelSuppressed=true",
        "runtime.enabled=false",
    ):
        if assertion not in runtime_probe_test:
            errors.append(f"Runtime probe test does not prove {assertion}")
    return errors


def main() -> int:
    errors = (
        check_toc()
        + check_no_ci_workflows()
        + check_forbidden_patterns()
        + check_saved_variables()
        + check_worker_policy()
        + check_secret_sink()
        + check_startup_and_hot_paths()
        + check_channel_lifecycle()
        + check_readiness_policy()
        + check_runtime_probe()
        + check_interrupt_data()
        + check_local_test_harness()
    )
    if errors:
        print("STATIC CHECKS FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("STATIC CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
