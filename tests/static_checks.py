from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "InterruptGlow.toc"
CURRENT_VERSION = "1.1.0-beta.4"
CURRENT_KB_COMMIT = "312085aa8d23dfe283b416ba0f394fef1cae22dd"


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
    "castbar frame inspection": re.compile(
        r"\b(TargetFrameSpellBar|FocusFrameSpellBar|CastingBarMixin)\b"
    ),
    "unverified GCD classification API": re.compile(r"\bDoesSpellTriggerGlobalCooldown\b"),
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
        errors.append("TOC contains duplicate entries")
    for entry in TOC_ENTRIES:
        if not (ROOT / entry).exists():
            errors.append(f"TOC references missing file: {entry}")

    if "## Interface: 120100" not in text:
        errors.append("TOC Interface is not 120100")
    if f"## Version: {CURRENT_VERSION}" not in text:
        errors.append(f"TOC version is not {CURRENT_VERSION}")
    if CURRENT_VERSION not in core:
        errors.append("Core fallback version does not match TOC")
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
        "core/GCDSafetyPolicy.lua",
        "core/CachePolicy.lua",
        "core/CastTracking.lua",
        "core/CDM.lua",
        "core/Events.lua",
    ]
    try:
        positions = [TOC_ENTRIES.index(entry) for entry in required_order]
        if positions != sorted(positions):
            errors.append("Runtime policy modules are loaded in the wrong order")
    except ValueError as exc:
        errors.append(f"TOC is missing required module: {exc}")

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
    return [] if not workflows else [
        "GitHub Actions workflows must remain absent: " + ", ".join(workflows)
    ]


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
        "CURRENT_INTERFACE = 120100",
        "producerVersion",
        "ReadBoolean",
        "ReadDebugKeep",
        "InterruptGlowDB = DB",
    ):
        if symbol not in shared:
            errors.append(f"SavedVariables sanitation is missing {symbol}")
    for obsolete in ("debugAutoShow", "slots =", "localCD ="):
        if obsolete in shared:
            errors.append(f"SavedVariables runtime schema retains obsolete data: {obsolete}")
    if "if value > 2000 then return 2000 end" not in shared:
        errors.append("debugKeep upper bound is missing")
    return errors


def check_worker_policy() -> list[str]:
    errors: list[str] = []
    worker = read(ROOT / "core" / "Worker.lua")
    shared = read(ROOT / "core" / "Shared.lua")
    glow = read(ROOT / "core" / "Glow.lua")

    for symbol in ("SetOnUpdateMode", "modes.Disabled", "modes.RunOnce", "modes.RunAlways"):
        if symbol not in worker:
            errors.append(f"OnUpdate worker policy is missing {symbol}")
    if "Worker:RunOnce(flushFrame)" not in shared:
        errors.append("Dirty queue does not use RunOnce")
    if "Worker:RunOnce(self.prewarmFrame)" not in glow:
        errors.append("Prewarm queue does not use RunOnce")
    if "Worker:SetContinuous(self.runtimeFrame, enabled)" not in glow:
        errors.append("Runtime timer does not use explicit continuous mode")
    if "runtimeWorkerEnabled = nil" not in glow:
        errors.append("Initial runtime worker disable can be skipped")
    return errors


def check_secret_boundary() -> list[str]:
    errors: list[str] = []
    cast = read(ROOT / "core" / "CastTracking.lua")
    glow = read(ROOT / "core" / "Glow.lua")

    if "rawNotInterruptible" not in cast or "ApplyUnitInterruptibility" not in cast:
        errors.append("Cast secret bridge is missing")
    if "SetAlphaFromBoolean" not in glow or "ALPHA_VISIBLE = 255" not in glow:
        errors.append("Secret alpha sink is incomplete")
    if "pcall(UnitCastingInfo" in cast or "pcall(UnitChannelInfo" in cast:
        errors.append("Raw cast returns travel through pcall")
    if "pcall(method, region, value" in glow or "pcall(region.SetAlphaFromBoolean" in glow:
        errors.append("Secret visual sink travels through pcall")
    if re.search(r"niRaw\s*=|notInterruptibleRaw\s*=", cast + glow):
        errors.append("Potential raw interruptibility storage detected")
    if "CreatePulseAnimation(overlay.target.niGate)" in glow:
        errors.append("Secret-alpha region is animated")
    if "CreatePulseAnimation(overlay.target.plainGate)" not in glow:
        errors.append("Ordinary parent animation is missing")
    return errors


def check_lifecycle_and_hot_paths() -> list[str]:
    errors: list[str] = []
    events = read(ROOT / "core" / "Events.lua")
    shared = read(ROOT / "core" / "Shared.lua")
    buttons = read(ROOT / "core" / "Buttons.lua")
    native = read(ROOT / "core" / "NativeCallbackPolicy.lua")
    lab = read(ROOT / "core" / "LABAdapter.lua")
    resolver = read(ROOT / "core" / "ActionResolver.lua")
    glow = read(ROOT / "core" / "Glow.lua")
    options = read(ROOT / "Options.lua")

    if events.count("Buttons:Attach(true)") != 1:
        errors.append("Startup attach/discovery is not exactly once")
    if "ContinueOnPlayerLogin" not in events:
        errors.append("Runtime initialization is not player-login gated")
    if "_loadedOrLoading, loaded" not in shared:
        errors.append("AddOn fully-loaded gate ignores the second return")
    if "function Options:Build()" not in options or 'panel:SetScript("OnShow"' not in options:
        errors.append("Options UI is not lazy")
    if "CreateCallbackHandleContainer" not in native or "nativeCallbackHandles:Unregister" not in native:
        errors.append("Native callback handle lifecycle is incomplete")
    if "actionSnapshotFresh" not in resolver:
        errors.append("Native resolved action snapshot is not reused")
    if "IsInterruptAction" not in resolver or "IsAssistedCombatAction" not in resolver:
        errors.append("Native current-action classification is incomplete")
    if buttons.count('WaitForKnownLABProvider("ElvUI")') != 1:
        errors.append("ElvUI load-order waiter is missing or duplicated")
    if 'hooksecurefunc(BFButton, "ClearCommand"' not in buttons:
        errors.append("ButtonForge clear lifecycle hook is missing")

    slot_subscription = re.compile(r"RegisterEvent\s*\(\s*[\"']ACTIONBAR_SLOT_CHANGED")
    for path in RUNTIME_FILES:
        if path.name != "LABAdapter.lua" and slot_subscription.search(read(path)):
            errors.append(f"{path.relative_to(ROOT)} has a non-targeted slot subscription")
    if lab.count('RegisterEvent("ACTIONBAR_SLOT_CHANGED")') != 1:
        errors.append("LAB changed-slot subscription is missing or duplicated")
    if "buttonsBySlot" not in lab or "for button in pairs(set)" not in lab:
        errors.append("LAB slot event is not bounded to indexed buttons")
    if 'UnregisterCallback(self, "OnButtonUpdate")' not in lab:
        errors.append("Broad LAB visual callback is retained")

    if "ability.readinessPending = true" not in shared:
        errors.append("Readiness invalidation is not fail-closed")
    if "not ReadinessPending(record)" not in glow or "or ReadinessPending(record)" not in glow:
        errors.append("Glow/countdown pending-readiness guards are incomplete")
    return errors


def check_channel_lifecycle() -> list[str]:
    errors: list[str] = []
    cast = read(ROOT / "core" / "CastTracking.lua")
    events = read(ROOT / "core" / "Events.lua")
    test = read(ROOT / "tests" / "channel_guard.lua")

    for symbol in (
        "channelSuppressed",
        "IsStaleCastEvent",
        "UNIT_SPELLCAST_CHANNEL_UPDATE",
        "UNIT_SPELLCAST_EMPOWER_UPDATE",
        "ResetUnitIdentity",
        "ResetAllIdentities",
        "cast.channelSnapshotSuppressed",
    ):
        if symbol not in cast:
            errors.append(f"Channel lifecycle is missing {symbol}")
    for snippet in (
        'ResetUnitIdentity("target", event)',
        'ResetUnitIdentity("focus", event)',
        "ResetAllIdentities(event)",
    ):
        if snippet not in events:
            errors.append(f"Unit identity reset is missing: {snippet}")
    for assertion in (
        "stale UnitChannelInfo resurrected after CHANNEL_STOP",
        "cast.staleStopIgnored",
        "RegisterUnitEvent requires unit varargs",
    ):
        if assertion not in test:
            errors.append(f"Channel regression test does not prove {assertion}")
    return errors


def check_readiness_and_gcd() -> list[str]:
    errors: list[str] = []
    events = read(ROOT / "core" / "Events.lua")
    cooldown = read(ROOT / "core" / "Cooldown.lua")
    readiness = read(ROOT / "core" / "ReadinessPolicy.lua")
    usability = read(ROOT / "core" / "Usability.lua")
    gcd = read(ROOT / "core" / "GCDSafetyPolicy.lua")
    cache = read(ROOT / "core" / "CachePolicy.lua")
    cdm = read(ROOT / "core" / "CDM.lua")

    if "GetActionCooldownDuration, slot, true" not in cooldown:
        errors.append("Action duration does not explicitly ignore GCD")
    if "GetSpellCooldownDuration, spellID, true" not in cooldown:
        errors.append("Spell duration does not explicitly ignore GCD")
    if "CaptureGCDHints()" in events or "MarkCooldownDirty(true)" in events:
        errors.append("Events still collect or propagate positive GCD readiness hints")
    for symbol in (
        "originalGetCachedReadiness(self, sourceKind, sourceID, false)",
        "treatsIsOnGCDAsReadinessProof = false",
        "function Cooldown:CaptureGCDHints()",
    ):
        if symbol not in gcd:
            errors.append(f"Conservative GCD policy is missing {symbol}")
    if "hardRestricted" not in cooldown:
        errors.append("Hard restrictions are not represented")
    if "ability.hardRestricted == true and ability.needsPoll == true" not in readiness:
        errors.append("Hard restrictions can enter periodic polling")
    if "GetPetActionSlotUsable" not in readiness:
        errors.append("Pet usability gate is missing")
    for symbol in ("IsUsableAction", "IsSpellUsable", "OnActionUsableChanged"):
        if symbol not in usability:
            errors.append(f"Usability policy is missing {symbol}")
    for symbol in ("PruneDormantAbilities", "ResetCaches", "generation = 0"):
        if symbol not in cache:
            errors.append(f"Spec cache policy is missing {symbol}")
    if "QueueIdentityChange" not in cdm or "IG:MarkButtonDirty(itemFrame)" not in cdm:
        errors.append("CDM pool changes are not deferred")
    reset = cdm[cdm.find("function CDM:ResetItem"):cdm.find("local function OnAcquireItemFrame")]
    if "UnbindRecord" in reset:
        errors.append("CDM reset mutates binding synchronously in Blizzard hook stack")
    return errors


def check_runtime_probe() -> list[str]:
    errors: list[str] = []
    debug = read(ROOT / "core" / "Debug.lua")
    probe = read(ROOT / "core" / "RuntimeProbe.lua")
    agents = read(ROOT / "AGENTS.md")
    guide = read(ROOT / "AGENT_GUIDE.md")

    for path_name, text in (("RuntimeProbe", probe), ("AGENTS", agents), ("AGENT_GUIDE", guide)):
        if CURRENT_KB_COMMIT not in text:
            errors.append(f"{path_name} is not pinned to current KB")
    for symbol in (
        "ProfilerSnapshot",
        "ProfilerDelta",
        "SessionAverageTime",
        "CountTimeOver1000Ms",
        "GetTicksPerSecond",
        "IsEnabled",
    ):
        if symbol not in debug:
            errors.append(f"Profiler diagnostics are missing {symbol}")
    for symbol in (
        "[providers]",
        "[workers]",
        "[policies]",
        "savedSchema",
        "restrictionTransitions",
        "PeakTimeIncrease",
        "WOWUI-2026-005",
        "gcd.isOnGCDReadinessProof",
    ):
        if symbol not in probe:
            errors.append(f"Runtime report is missing {symbol}")
    if "scriptProfile" in debug or "scriptProfile" in probe:
        errors.append("Runtime diagnostics enable legacy scriptProfile")
    return errors


def check_interrupt_data() -> list[str]:
    errors: list[str] = []
    data = read(ROOT / "core" / "Data.lua")
    if "-- BEGIN GENERATED INTERRUPTS_BY_SPEC" not in data or "-- END GENERATED INTERRUPTS_BY_SPEC" not in data:
        errors.append("Generated interrupt block markers are missing")
    for spec_id, snippet in EXPECTED_SPEC_SNIPPETS.items():
        if snippet not in data:
            errors.append(f"Missing Blizzard interrupt mapping for spec {spec_id}: {snippet}")
    if re.search(r"\[115781\]\s*=|\{[^\n}]*\b115781\b", data):
        errors.append("Removed Optical Blast ID returned")
    if "EXTRA_INTERRUPTS_BY_SPEC" not in data or data.count("212619") < 3:
        errors.append("Call Felhunter PvP coverage is missing")
    if "[19647] = 119910" not in data or "[89766] = 119914" not in data:
        errors.append("Warlock pet aliases are incomplete")
    return errors


def check_local_tests() -> list[str]:
    errors: list[str] = []
    syntax = read(ROOT / "tests" / "check_syntax.lua")
    required = (
        "tests/mock_wow.lua",
        "tests/cdm_toggle.lua",
        "tests/runtime_probe.lua",
        "tests/native_callback_handles.lua",
        "tests/channel_guard.lua",
        "tests/shared_worker.lua",
        "tests/cache_policy.lua",
        "tests/glow_worker.lua",
        "tests/gcd_safety.lua",
    )
    for path in required:
        if path not in syntax:
            errors.append(f"Syntax checker does not include {path}")

    probe_test = read(ROOT / "tests" / "runtime_probe.lua")
    for assertion in (
        f"kbCommit={CURRENT_KB_COMMIT}",
        "gcd.ignoreGlobalCooldownDuration=true",
        "gcd.isOnGCDReadinessProof=false",
        "delta.CountTimeOver5Ms=5",
    ):
        if assertion not in probe_test:
            errors.append(f"Runtime probe test does not prove {assertion}")

    gcd_test = read(ROOT / "tests" / "gcd_safety.lua")
    if "isOnGCD hint reached the readiness resolver" not in gcd_test:
        errors.append("Focused GCD safety test is incomplete")
    return errors


def main() -> int:
    errors = (
        check_toc()
        + check_no_ci_workflows()
        + check_forbidden_patterns()
        + check_saved_variables()
        + check_worker_policy()
        + check_secret_boundary()
        + check_lifecycle_and_hot_paths()
        + check_channel_lifecycle()
        + check_readiness_and_gcd()
        + check_runtime_probe()
        + check_interrupt_data()
        + check_local_tests()
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
