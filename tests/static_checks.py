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
    "nameplate traversal": re.compile(r"\bGetNamePlates\b"),
    "540-slot scan": re.compile(r"\b540\b"),
    "macro-body GetMacroInfo": re.compile(r"\bGetMacroInfo\b"),
    "macro-body GetMacroSpell": re.compile(r"\bGetMacroSpell\b"),
    "ACTIONBAR_UPDATE_COOLDOWN subscription": re.compile(
        r"RegisterEvent\s*\(\s*[\"']ACTIONBAR_UPDATE_COOLDOWN"
    ),
    "unconfirmed SPELL_SECRECY_CHANGED subscription": re.compile(
        r"RegisterEvent\s*\(\s*[\"']SPELL_SECRECY_CHANGED"
    ),
    "generic ADDON_LOADED subscription": re.compile(
        r"RegisterEvent\s*\(\s*[\"']ADDON_LOADED"
    ),
    "Blizzard spell-alert manager mutation": re.compile(
        r"\bActionButtonSpellAlertManager\b"
    ),
    "castbar frame inspection": re.compile(
        r"\b(TargetFrameSpellBar|FocusFrameSpellBar|CastingBarMixin)\b"
    ),
    "unverified GCD classification API": re.compile(
        r"\bDoesSpellTriggerGlobalCooldown\b"
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


def require(text: str, symbols: tuple[str, ...], scope: str) -> list[str]:
    return [f"{scope} is missing {symbol}" for symbol in symbols if symbol not in text]


def check_toc() -> list[str]:
    errors: list[str] = []
    toc = read(TOC)
    core = read(ROOT / "Core.lua")

    if len(TOC_ENTRIES) != len(set(TOC_ENTRIES)):
        errors.append("TOC contains duplicate entries")
    for entry in TOC_ENTRIES:
        if not (ROOT / entry).exists():
            errors.append(f"TOC references missing file: {entry}")

    if "## Interface: 120100" not in toc:
        errors.append("TOC Interface is not 120100")
    if f"## Version: {CURRENT_VERSION}" not in toc:
        errors.append(f"TOC version is not {CURRENT_VERSION}")
    if CURRENT_VERSION not in core:
        errors.append("Core fallback version does not match the TOC")
    if "## LoadOnDemand:" in toc:
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
        "core/CDMPolicy.lua",
        "core/Events.lua",
    ]
    try:
        positions = [TOC_ENTRIES.index(entry) for entry in required_order]
        if positions != sorted(positions):
            errors.append("Runtime policy modules are loaded in the wrong order")
    except ValueError as exc:
        errors.append(f"TOC is missing a required module: {exc}")
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
                errors.append(
                    f"{path.relative_to(ROOT)} contains forbidden runtime pattern: {label}"
                )
    return errors


def check_saved_variables_and_workers() -> list[str]:
    errors: list[str] = []
    shared = read(ROOT / "core" / "Shared.lua")
    worker = read(ROOT / "core" / "Worker.lua")
    glow = read(ROOT / "core" / "Glow.lua")

    errors += require(
        shared,
        (
            "CURRENT_SCHEMA = 3",
            "CURRENT_INTERFACE = 120100",
            "producerVersion",
            "ReadBoolean",
            "ReadDebugKeep",
            "InterruptGlowDB = DB",
            "Worker:RunOnce(flushFrame)",
        ),
        "Shared/SavedVariables policy",
    )
    for obsolete in ("debugAutoShow", "slots =", "localCD ="):
        if obsolete in shared:
            errors.append(f"SavedVariables schema retains obsolete data: {obsolete}")
    if "if value > 2000 then return 2000 end" not in shared:
        errors.append("debugKeep upper bound is missing")

    errors += require(
        worker,
        ("SetOnUpdateMode", "modes.Disabled", "modes.RunOnce", "modes.RunAlways"),
        "OnUpdate worker policy",
    )
    errors += require(
        glow,
        (
            "Worker:RunOnce(self.prewarmFrame)",
            "Worker:SetContinuous(self.runtimeFrame, enabled)",
            "runtimeWorkerEnabled = nil",
        ),
        "Glow worker policy",
    )
    return errors


def check_secret_boundary() -> list[str]:
    errors: list[str] = []
    cast = read(ROOT / "core" / "CastTracking.lua")
    glow = read(ROOT / "core" / "Glow.lua")

    errors += require(
        cast,
        ("rawNotInterruptible", "ApplyUnitInterruptibility", "IsStaleCastEvent"),
        "CastTracking secret/lifecycle boundary",
    )
    errors += require(
        glow,
        ("SetAlphaFromBoolean", "ALPHA_VISIBLE = 255", "CreatePulseAnimation(overlay.target.plainGate)"),
        "Glow secret boundary",
    )
    if "pcall(UnitCastingInfo" in cast or "pcall(UnitChannelInfo" in cast:
        errors.append("Raw cast returns travel through a pcall result lane")
    if "pcall(method, region, value" in glow or "pcall(region.SetAlphaFromBoolean" in glow:
        errors.append("Secret visual sink travels through pcall")
    if re.search(r"niRaw\s*=|notInterruptibleRaw\s*=", cast + glow):
        errors.append("Potential raw interruptibility storage detected")
    if "CreatePulseAnimation(overlay.target.niGate)" in glow:
        errors.append("The secret-alpha child region is animated")
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
    errors += require(events, ("ContinueOnPlayerLogin",), "Runtime startup")
    errors += require(shared, ("_loadedOrLoading, loaded",), "Fully-loaded add-on gate")
    errors += require(
        options,
        ('function Options:Build()', 'panel:SetScript("OnShow"'),
        "Lazy options UI",
    )
    errors += require(
        native,
        ("CreateCallbackHandleContainer", "nativeCallbackHandles:Unregister"),
        "Native callback lifecycle",
    )
    errors += require(
        resolver,
        ("actionSnapshotFresh", "IsInterruptAction", "IsAssistedCombatAction"),
        "Native action resolver",
    )
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
    errors += require(
        lab,
        ("buttonsBySlot", "for button in pairs(set)", 'UnregisterCallback(self, "OnButtonUpdate")'),
        "LAB targeted diff policy",
    )

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

    errors += require(
        cast,
        (
            "channelSuppressed",
            "IsStaleCastEvent",
            "UNIT_SPELLCAST_CHANNEL_UPDATE",
            "UNIT_SPELLCAST_EMPOWER_UPDATE",
            "ResetUnitIdentity",
            "ResetAllIdentities",
            "cast.channelSnapshotSuppressed",
        ),
        "Event-authoritative channel lifecycle",
    )
    errors += require(
        events,
        (
            'ResetUnitIdentity("target", event)',
            'ResetUnitIdentity("focus", event)',
            "ResetAllIdentities(event)",
        ),
        "Unit identity reset routing",
    )
    errors += require(
        test,
        (
            "stale UnitChannelInfo resurrected after CHANNEL_STOP",
            "cast.staleStopIgnored",
            "RegisterUnitEvent requires unit varargs",
        ),
        "Channel regression test",
    )
    return errors


def check_readiness_gcd_cache_and_cdm() -> list[str]:
    errors: list[str] = []
    events = read(ROOT / "core" / "Events.lua")
    cooldown = read(ROOT / "core" / "Cooldown.lua")
    readiness = read(ROOT / "core" / "ReadinessPolicy.lua")
    usability = read(ROOT / "core" / "Usability.lua")
    gcd = read(ROOT / "core" / "GCDSafetyPolicy.lua")
    cache = read(ROOT / "core" / "CachePolicy.lua")
    cdm = read(ROOT / "core" / "CDM.lua")
    cdm_policy = read(ROOT / "core" / "CDMPolicy.lua")

    errors += require(
        cooldown,
        (
            "GetActionCooldownDuration, slot, true",
            "GetSpellCooldownDuration, spellID, true",
            "hardRestricted",
        ),
        "Cooldown readiness",
    )
    if "CaptureGCDHints()" in events or "MarkCooldownDirty(true)" in events:
        errors.append("Events still collect or propagate positive GCD readiness hints")
    errors += require(
        gcd,
        (
            "originalGetCachedReadiness(self, sourceKind, sourceID, false)",
            "treatsIsOnGCDAsReadinessProof = false",
            "function Cooldown:CaptureGCDHints()",
        ),
        "Conservative GCD policy",
    )
    errors += require(
        readiness,
        ("ability.hardRestricted == true and ability.needsPoll == true", "GetPetActionSlotUsable"),
        "Hard readiness policy",
    )
    errors += require(
        usability,
        ("IsUsableAction", "IsSpellUsable", "OnActionUsableChanged"),
        "Usability policy",
    )
    errors += require(
        cache,
        ("PruneDormantAbilities", "ResetCaches", "generation = 0"),
        "Specialization cache policy",
    )

    errors += require(
        cdm,
        ("QueueIdentityChange", "IG:MarkButtonDirty(itemFrame)"),
        "Deferred CDM hook policy",
    )
    reset_start = cdm.find("function CDM:ResetItem")
    reset_end = cdm.find("local function OnAcquireItemFrame")
    if reset_start >= 0 and reset_end > reset_start:
        if "UnbindRecord" in cdm[reset_start:reset_end]:
            errors.append("CDM reset mutates binding synchronously inside Blizzard hook stack")

    errors += require(
        cdm_policy,
        (
            "record.cdmCanonicalSpellID",
            'Data:GetCanonicalSpellID(observedSpellID, "spell")',
            "usesCapturedPoolIdentity = true",
            "refreshesActiveItemsAfterSpecData = true",
            "CDM:ObserveExistingItems()",
        ),
        "Captured CDM identity policy",
    )
    if "GetBaseSpellID" in cdm_policy:
        errors.append("CDM reconcile re-reads the pooled frame instead of captured identity")
    return errors


def check_runtime_probe_and_docs() -> list[str]:
    errors: list[str] = []
    debug = read(ROOT / "core" / "Debug.lua")
    probe = read(ROOT / "core" / "RuntimeProbe.lua")
    agents = read(ROOT / "AGENTS.md")
    guide = read(ROOT / "AGENT_GUIDE.md")

    for path_name, text in (("RuntimeProbe", probe), ("AGENTS", agents), ("AGENT_GUIDE", guide)):
        if CURRENT_KB_COMMIT not in text:
            errors.append(f"{path_name} is not pinned to the current KB commit")
    errors += require(
        debug,
        (
            "ProfilerSnapshot",
            "ProfilerDelta",
            "SessionAverageTime",
            "CountTimeOver1000Ms",
            "GetTicksPerSecond",
            "IsEnabled",
        ),
        "Native profiler diagnostics",
    )
    errors += require(
        probe,
        (
            "[providers]",
            "[workers]",
            "[policies]",
            "savedSchema",
            "restrictionTransitions",
            "PeakTimeIncrease",
            "WOWUI-2026-005",
            "gcd.isOnGCDReadinessProof",
        ),
        "Runtime evidence report",
    )
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
        "tests/cdm_policy.lua",
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
    errors += require(
        probe_test,
        (
            f"kbCommit={CURRENT_KB_COMMIT}",
            "gcd.ignoreGlobalCooldownDuration=true",
            "gcd.isOnGCDReadinessProof=false",
            "delta.CountTimeOver5Ms=5",
        ),
        "Runtime probe test",
    )
    gcd_test = read(ROOT / "tests" / "gcd_safety.lua")
    if "isOnGCD hint reached the readiness resolver" not in gcd_test:
        errors.append("Focused GCD safety test is incomplete")

    cdm_policy_test = read(ROOT / "tests" / "cdm_policy.lua")
    errors += require(
        cdm_policy_test,
        (
            "frameReads == 0",
            "cached CDM identity crossed spec policy",
            "refreshesActiveItemsAfterSpecData == true",
        ),
        "Focused CDM policy test",
    )
    return errors


def main() -> int:
    errors = (
        check_toc()
        + check_no_ci_workflows()
        + check_forbidden_patterns()
        + check_saved_variables_and_workers()
        + check_secret_boundary()
        + check_lifecycle_and_hot_paths()
        + check_channel_lifecycle()
        + check_readiness_gcd_cache_and_cdm()
        + check_runtime_probe_and_docs()
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
