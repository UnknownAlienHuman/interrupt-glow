from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "InterruptGlow.toc"
CURRENT_VERSION = "1.1.0-beta.7"
CURRENT_INTERFACE = "120100"
CURRENT_KB_COMMIT = "d1a077b4f04a8b1ec1845563220a5af8a4fa2a53"
BLIZZARD_SOURCE_COMMIT = "027d26c3406d3de2cbd2b1f67d468fe033a1bcd4"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def toc_entries() -> list[str]:
    entries: list[str] = []
    for raw in read(TOC).splitlines():
        line = raw.strip()
        if line and not line.startswith("##"):
            entries.append(line)
    return entries


def block(text: str, start: str, end: str | None = None) -> str:
    begin = text.find(start)
    if begin < 0:
        return ""
    if end is None:
        return text[begin:]
    finish = text.find(end, begin + len(start))
    return text[begin:] if finish < 0 else text[begin:finish]


def require(text: str, snippets: tuple[str, ...], scope: str) -> list[str]:
    return [f"{scope} is missing {snippet}" for snippet in snippets if snippet not in text]


def assert_before(text: str, first: str, second: str, scope: str) -> list[str]:
    first_index = text.find(first)
    second_index = text.find(second)
    if first_index < 0 or second_index < 0:
        return [f"{scope} cannot prove ordering: {first!r} before {second!r}"]
    if first_index >= second_index:
        return [f"{scope} has unsafe ordering: {second!r} precedes {first!r}"]
    return []


TOC_ENTRIES = toc_entries()
RUNTIME_FILES = [ROOT / entry for entry in TOC_ENTRIES]


def check_toc_and_version() -> list[str]:
    errors: list[str] = []
    toc = read(TOC)
    core = read(ROOT / "Core.lua")

    if len(TOC_ENTRIES) != len(set(TOC_ENTRIES)):
        errors.append("TOC contains duplicate entries")
    for entry in TOC_ENTRIES:
        if not (ROOT / entry).is_file():
            errors.append(f"TOC references missing file: {entry}")

    core_files = {
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "core").glob("*.lua")
    }
    toc_core = {entry for entry in TOC_ENTRIES if entry.startswith("core/")}
    for path in sorted(core_files - toc_core):
        errors.append(f"Runtime core file is not loaded by TOC: {path}")
    for path in sorted(toc_core - core_files):
        errors.append(f"TOC core entry has no matching file: {path}")

    if f"## Interface: {CURRENT_INTERFACE}" not in toc:
        errors.append(f"TOC Interface is not {CURRENT_INTERFACE}")
    if f"## Version: {CURRENT_VERSION}" not in toc:
        errors.append(f"TOC version is not {CURRENT_VERSION}")
    if CURRENT_VERSION not in core:
        errors.append("Core fallback version does not match TOC")
    if "## LoadOnDemand:" in toc:
        errors.append("Interrupt Glow itself must not be LoadOnDemand")

    required_order = [
        "Core.lua",
        "core/Worker.lua",
        "core/Shared.lua",
        "core/DiagnosticsPolicy.lua",
        "core/Data.lua",
        "core/Debug.lua",
        "core/RuntimeProbe.lua",
        "core/RuntimeProbePolicy.lua",
        "core/Glow.lua",
        "core/FrameAccessPolicy.lua",
        "core/PrewarmPolicy.lua",
        "core/Buttons.lua",
        "core/ButtonForgePolicy.lua",
        "core/NativeCallbackPolicy.lua",
        "core/LABAdapter.lua",
        "core/ActionResolver.lua",
        "core/NativeActionQueuePolicy.lua",
        "core/Cooldown.lua",
        "core/ReadinessPolicy.lua",
        "core/Usability.lua",
        "core/GCDSafetyPolicy.lua",
        "core/CachePolicy.lua",
        "core/AbilitySourcePolicy.lua",
        "core/BoundSourcePolicy.lua",
        "core/CastTracking.lua",
        "core/CDM.lua",
        "core/CDMPolicy.lua",
        "core/RuntimeInterruptPolicy.lua",
        "core/Events.lua",
        "core/Slash.lua",
        "Options.lua",
    ]
    try:
        positions = [TOC_ENTRIES.index(entry) for entry in required_order]
        if positions != sorted(positions):
            errors.append("TOC runtime policy order is invalid")
    except ValueError as exc:
        errors.append(f"TOC is missing a required module: {exc}")

    return errors


def check_forbidden_hot_paths() -> list[str]:
    errors: list[str] = []
    patterns = {
        "EnumerateFrames": r"\bEnumerateFrames\b",
        "nameplate traversal": r"\bGetNamePlates\b|\bC_NamePlate\b",
        "540-slot scan": r"\b540\b",
        "macro-body parsing": r"\bGetMacroInfo\b|\bGetMacroSpell\b",
        "ACTIONBAR_UPDATE_COOLDOWN subscription": (
            r"RegisterEvent\s*\(\s*[\"']ACTIONBAR_UPDATE_COOLDOWN"
        ),
        "unconfirmed SPELL_SECRECY_CHANGED subscription": (
            r"RegisterEvent\s*\(\s*[\"']SPELL_SECRECY_CHANGED"
        ),
        "generic ADDON_LOADED subscription": (
            r"RegisterEvent\s*\(\s*[\"']ADDON_LOADED"
        ),
        "Blizzard spell-alert manager mutation": r"\bActionButtonSpellAlertManager\b",
        "Blizzard castbar inspection": r"\b(TargetFrameSpellBar|FocusFrameSpellBar)\b",
        "legacy scriptProfile": r"\bscriptProfile\b",
    }
    for path in RUNTIME_FILES:
        text = read(path)
        for label, pattern in patterns.items():
            if re.search(pattern, text):
                errors.append(f"{path.relative_to(ROOT)} contains forbidden {label}")
    return errors


def check_native_callback_boundary() -> list[str]:
    errors: list[str] = []
    policy = read(ROOT / "core/NativeActionQueuePolicy.lua")
    callback = block(
        policy,
        "function Buttons:OnNativeActionChanged",
        'IG:RegisterModule("NativeActionQueuePolicy"',
    )
    errors += require(
        callback,
        (
            "record.actionSnapshotFresh = false",
            "if IG.PendingButtons[button] then return end",
            "IG:MarkButtonDirty(button)",
        ),
        "Native action callback",
    )
    for forbidden in (
        "ReadActionSnapshot",
        "IsInterruptAction",
        "IsAssistedCombatAction",
        "GetActionInfo",
        "GetSpell",
        "ResolveRecord",
    ):
        if forbidden in callback:
            errors.append(f"Native action callback performs hot-path work: {forbidden}")
    errors += assert_before(
        callback,
        "record.actionSnapshotFresh = false",
        "if IG.PendingButtons[button] then return end",
        "Native action invalidation/dedupe",
    )
    return errors


def check_secret_ordering() -> list[str]:
    errors: list[str] = []
    cooldown = read(ROOT / "core/Cooldown.lua")
    charge = block(cooldown, "local function ReadChargeInfo", "local function ReadLossOfControlState")
    loc = block(cooldown, "local function ReadLossOfControlState", "local function GetActionLossOfControlState")

    errors += assert_before(
        charge,
        "if not IG.CanAccess(info) then",
        "if info == nil then",
        "Charge SecretValue ordering",
    )
    errors += assert_before(
        loc,
        "if not IG.CanAccess(info) then",
        "if info == nil then",
        "Loss of Control SecretValue ordering",
    )
    errors += require(
        charge,
        ("return nil, nil, true, true, true, true",),
        "Charge fail-closed policy",
    )
    errors += require(
        loc,
        ('return "restricted"', 'return "clear"'),
        "Loss of Control fail-closed policy",
    )

    cast = read(ROOT / "core/CastTracking.lua")
    errors += require(
        cast,
        (
            "rawNotInterruptible",
            "ApplyUnitInterruptibility",
            "return SafeEventCastBarID(select(4, ...))",
            "return SafeEventCastBarID(select(5, ...))",
            "return SafeEventCastBarID(select(6, ...))",
            "channelSuppressed",
            "IsStaleCastEvent",
        ),
        "CastTracking secret/channel boundary",
    )
    if "pcall(UnitCastingInfo" in cast or "pcall(UnitChannelInfo" in cast:
        errors.append("Raw cast returns travel through pcall")

    glow = read(ROOT / "core/Glow.lua")
    if "CreatePulseAnimation(overlay.target.niGate)" in glow:
        errors.append("Secret-alpha child region is animated")
    errors += require(
        glow,
        ("SetAlphaFromBoolean", "ALPHA_VISIBLE = 255"),
        "Glow secret sink",
    )
    return errors


def check_foreign_frame_boundary() -> list[str]:
    errors: list[str] = []
    policy = read(ROOT / "core/FrameAccessPolicy.lua")
    errors += require(
        policy,
        (
            'IG:ReadMember(button, "IsForbidden")',
            "not ok or not IG.CanAccess(forbidden)",
            'type(forbidden) ~= "boolean"',
            "function Glow:CreateShell(record)",
            "MarkOverlayForbidden(record)",
            "ownsShellCreationBoundary = true",
        ),
        "Foreign frame access policy",
    )
    preflight = block(policy, "local function CanCreateOnButton", "local function SafeFrameLevel")
    errors += assert_before(
        preflight,
        "not IG.CanAccess(forbidden)",
        'type(forbidden) ~= "boolean"',
        "IsForbidden result ordering",
    )
    create_shell = block(policy, "function Glow:CreateShell", 'IG:RegisterModule("FrameAccessPolicy"')
    errors += assert_before(
        create_shell,
        "if not CanCreateOnButton(button) then",
        "CreateUnitBranch(button)",
        "Foreign frame preflight/allocation",
    )
    return errors


def check_readiness_and_providers() -> list[str]:
    errors: list[str] = []
    cooldown = read(ROOT / "core/Cooldown.lua")
    readiness = read(ROOT / "core/ReadinessPolicy.lua")
    usability = read(ROOT / "core/Usability.lua")
    gcd = read(ROOT / "core/GCDSafetyPolicy.lua")
    source = read(ROOT / "core/AbilitySourcePolicy.lua")
    bound = read(ROOT / "core/BoundSourcePolicy.lua")
    data = read(ROOT / "core/Data.lua")
    lab = read(ROOT / "core/LABAdapter.lua")
    cdm = read(ROOT / "core/CDM.lua")
    cdm_policy = read(ROOT / "core/CDMPolicy.lua")

    errors += require(
        cooldown,
        (
            "GetActionCooldownDuration, slot, true",
            "GetSpellCooldownDuration, spellID, true",
            "hardRestricted",
        ),
        "Cooldown readiness",
    )
    errors += require(
        gcd,
        (
            "originalGetCachedReadiness(self, sourceKind, sourceID, false)",
            "treatsIsOnGCDAsReadinessProof = false",
        ),
        "GCD safety policy",
    )
    errors += require(
        readiness,
        ("GetPetActionSlotUsable", "ability.hardRestricted == true"),
        "Pet/LoC readiness policy",
    )
    errors += require(
        usability,
        ("IsUsableAction", "IsSpellUsable", "OnActionUsableChanged"),
        "Usability policy",
    )
    errors += require(
        source,
        (
            "action = 300",
            "pet = 200",
            "spell = 100",
            "reconcilesBeforeRefreshFilter = true",
        ),
        "Canonical source policy",
    )
    errors += require(
        bound,
        ("boundRecordsWithoutSourceFailClosed = true",),
        "Bound source fail-closed policy",
    )
    errors += require(
        data,
        (
            "-- BEGIN GENERATED INTERRUPTS_BY_SPEC",
            "-- END GENERATED INTERRUPTS_BY_SPEC",
            "EXTRA_INTERRUPTS_BY_SPEC",
            "PET_ACTION_ALIASES",
            "IsRuntimeFamilyKnown",
            BLIZZARD_SOURCE_COMMIT,
        ),
        "Interrupt data",
    )
    for snippet in (
        "[250] = { 47528 }",
        "[1480] = { 183752 }",
        "[1467] = { 351338 }",
        "[258] = { 15487 }",
        "[265] = { 119910, 132409 }",
        "[266] = { 119910, 119914 }",
        "[73] = { 6552, 386071 }",
        "[19647] = 119910",
        "[89766] = 119914",
    ):
        if snippet not in data:
            errors.append(f"Interrupt data is missing {snippet}")
    if re.search(r"\[115781\]\s*=|\{[^\n}]*\b115781\b", data):
        errors.append("Removed Optical Blast ID 115781 returned")
    if data.count("212619") < 3:
        errors.append("Call Felhunter PvP coverage is missing")

    errors += require(
        lab,
        (
            "buttonsBySlot",
            "DisableBroadUpdateIfFullyHooked",
            'library.UnregisterCallback(Buttons, "OnButtonUpdate")',
        ),
        "LAB callback policy",
    )
    errors += require(
        cdm,
        ("QueueIdentityChange", "IG:MarkButtonDirty(itemFrame)"),
        "Deferred Cooldown Viewer hooks",
    )
    errors += require(
        cdm_policy,
        ("record.cdmCanonicalSpellID", "usesCapturedPoolIdentity = true"),
        "Cooldown Viewer identity policy",
    )
    return errors


def check_lifecycle_and_evidence() -> list[str]:
    errors: list[str] = []
    shared = read(ROOT / "core/Shared.lua")
    worker = read(ROOT / "core/Worker.lua")
    prewarm = read(ROOT / "core/PrewarmPolicy.lua")
    native = read(ROOT / "core/NativeCallbackPolicy.lua")
    options = read(ROOT / "Options.lua")
    diagnostics = read(ROOT / "core/DiagnosticsPolicy.lua")
    probe = read(ROOT / "core/RuntimeProbe.lua")
    probe_policy = read(ROOT / "core/RuntimeProbePolicy.lua")

    errors += require(
        shared,
        (
            "CURRENT_SCHEMA = 3",
            "CURRENT_INTERFACE = 120100",
            "InterruptGlowDB = DB",
            "Worker:RunOnce(flushFrame)",
            "_loadedOrLoading, loaded",
        ),
        "Shared lifecycle/persistence",
    )
    errors += require(
        worker,
        ("SetOnUpdateMode", "modes.Disabled", "modes.RunOnce", "modes.RunAlways"),
        "Worker policy",
    )
    errors += require(
        prewarm,
        ("processed < self.prewarmBudgetPerFrame", "budgetCountsInspectedRecords = true"),
        "Prewarm budget",
    )
    errors += require(
        native,
        ("CreateCallbackHandleContainer", "nativeCallbackHandles:Unregister"),
        "Native callback lifecycle",
    )
    errors += require(
        options,
        ("panel.OnRefresh", "panel.OnDefault", "panel.OnCommit", "OnCombatEnded"),
        "Settings lifecycle",
    )
    errors += require(
        diagnostics,
        ("profileCounterOwner", "StartProfileCounters(owner)", "StopProfileCounters(owner)"),
        "Diagnostic ownership",
    )
    errors += require(
        probe_policy,
        ("MAX_MARKS = 256", "MAX_RESTRICTIONS = 128", "buildsReportsOutOfCombatOnly = true"),
        "Runtime probe bounds",
    )

    for scope, text in (
        ("RuntimeProbe", probe),
        ("AGENTS", read(ROOT / "AGENTS.md")),
        ("AGENT_GUIDE", read(ROOT / "AGENT_GUIDE.md")),
    ):
        if CURRENT_KB_COMMIT not in text:
            errors.append(f"{scope} is not pinned to current KB {CURRENT_KB_COMMIT}")
    return errors


def check_tests_and_workflows() -> list[str]:
    errors: list[str] = []
    syntax = read(ROOT / "tests/check_syntax.lua")
    for path in sorted((ROOT / "tests").glob("*.lua")):
        if path.name == "check_syntax.lua":
            continue
        relative = path.relative_to(ROOT).as_posix()
        if f'"{relative}"' not in syntax:
            errors.append(f"Syntax checker does not include {relative}")

    errors += require(
        read(ROOT / "tests/action_resolver_fast_path.lua"),
        (
            "Any number of callbacks before the addon flush",
            "invalidates before dedupe",
            "callbackReadsActionAPIs == false",
        ),
        "Native queue regression test",
    )
    errors += require(
        read(ROOT / "tests/frame_access_policy.lua"),
        (
            "created a child on an inaccessible frame",
            "foreign frame query failed",
            "FRAME ACCESS POLICY TEST PASSED",
        ),
        "Foreign frame regression test",
    )

    workflow_dir = ROOT / ".github/workflows"
    if workflow_dir.exists() and any(workflow_dir.glob("*.y*ml")):
        errors.append("GitHub Actions workflows must remain absent")
    return errors


def main() -> int:
    errors = (
        check_toc_and_version()
        + check_forbidden_hot_paths()
        + check_native_callback_boundary()
        + check_secret_ordering()
        + check_foreign_frame_boundary()
        + check_readiness_and_providers()
        + check_lifecycle_and_evidence()
        + check_tests_and_workflows()
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
