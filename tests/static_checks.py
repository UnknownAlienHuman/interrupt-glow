from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "InterruptGlow.toc"
CURRENT_VERSION = "1.1.0-beta.5"
CURRENT_INTERFACE = "120100"
CURRENT_KB_COMMIT = "312085aa8d23dfe283b416ba0f394fef1cae22dd"
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


TOC_ENTRIES = toc_entries()
RUNTIME_FILES = [ROOT / entry for entry in TOC_ENTRIES]


def require(text: str, symbols: tuple[str, ...], scope: str) -> list[str]:
    return [f"{scope} is missing {symbol}" for symbol in symbols if symbol not in text]


def between(text: str, start: str, end: str) -> str:
    start_index = text.find(start)
    end_index = text.find(end, start_index + len(start)) if start_index >= 0 else -1
    if start_index < 0 or end_index < 0:
        return ""
    return text[start_index:end_index]


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
        errors.append(f"TOC core entry has no file: {path}")

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
        "core/PrewarmPolicy.lua",
        "core/Buttons.lua",
        "core/NativeCallbackPolicy.lua",
        "core/LABAdapter.lua",
        "core/ActionResolver.lua",
        "core/Cooldown.lua",
        "core/ReadinessPolicy.lua",
        "core/Usability.lua",
        "core/GCDSafetyPolicy.lua",
        "core/CachePolicy.lua",
        "core/AbilitySourcePolicy.lua",
        "core/CastTracking.lua",
        "core/CDM.lua",
        "core/CDMPolicy.lua",
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


def check_secret_and_restriction_boundaries() -> list[str]:
    errors: list[str] = []
    cast = read(ROOT / "core/CastTracking.lua")
    glow = read(ROOT / "core/Glow.lua")
    cooldown = read(ROOT / "core/Cooldown.lua")
    events = read(ROOT / "core/Events.lua")

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
    selector = between(cast, "local function GetEventCastBarID", "local function IsStaleCastEvent")
    for forbidden in ("_castGUID", "_spellID", "_interruptedBy", "_complete"):
        if forbidden in selector:
            errors.append(f"Event castBarID selector binds secret-capable field {forbidden}")
    if "pcall(UnitCastingInfo" in cast or "pcall(UnitChannelInfo" in cast:
        errors.append("Raw cast returns travel through pcall")

    errors += require(
        glow,
        (
            "SetAlphaFromBoolean",
            "ALPHA_VISIBLE = 255",
            "CreatePulseAnimation(overlay.target.plainGate)",
        ),
        "Glow secret sink",
    )
    if "CreatePulseAnimation(overlay.target.niGate)" in glow:
        errors.append("Secret-alpha child region is animated")
    if "pcall(method, region, value" in glow:
        errors.append("Secret alpha sink is wrapped in pcall")

    loc = between(cooldown, "local function ReadLossOfControlState", "local function GetActionLossOfControlState")
    errors += require(
        loc,
        (
            'if info == nil then',
            'return "clear"',
            'if not IG.CanAccess(info) then',
            'return "restricted"',
        ),
        "Loss of Control fail-closed policy",
    )
    if loc.find("not IG.CanAccess(info)") > loc.find('return "clear"', loc.find("not IG.CanAccess(info)")) >= 0:
        errors.append("Inaccessible Loss of Control still falls through to clear")

    errors += require(
        events,
        (
            "not IG.CanAccess(unit)",
            "not IG.CanAccess(spellID)",
            "events.restrictedSpellSucceeded",
        ),
        "Restricted spell-success event boundary",
    )
    return errors


def check_readiness_and_sources() -> list[str]:
    errors: list[str] = []
    cooldown = read(ROOT / "core/Cooldown.lua")
    readiness = read(ROOT / "core/ReadinessPolicy.lua")
    usability = read(ROOT / "core/Usability.lua")
    gcd = read(ROOT / "core/GCDSafetyPolicy.lua")
    source = read(ROOT / "core/AbilitySourcePolicy.lua")
    data = read(ROOT / "core/Data.lua")
    cdm = read(ROOT / "core/CDM.lua")
    cdm_policy = read(ROOT / "core/CDMPolicy.lua")

    errors += require(
        cooldown,
        (
            "GetActionCooldownDuration, slot, true",
            "GetSpellCooldownDuration, spellID, true",
            "return nil, nil, true, true, false, true",
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
            "function Buttons:RebuildAbilitySource",
            "reconcilesBeforeRefreshFilter = true",
        ),
        "Canonical source policy",
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
        cdm,
        ("QueueIdentityChange", "IG:MarkButtonDirty(itemFrame)"),
        "Deferred Cooldown Viewer hooks",
    )
    errors += require(
        cdm_policy,
        (
            "record.cdmCanonicalSpellID",
            "usesCapturedPoolIdentity = true",
            "refreshesActiveItemsAfterSpecData = true",
        ),
        "Cooldown Viewer identity policy",
    )
    return errors


def check_lifecycle_workers_and_diagnostics() -> list[str]:
    errors: list[str] = []
    shared = read(ROOT / "core/Shared.lua")
    worker = read(ROOT / "core/Worker.lua")
    prewarm = read(ROOT / "core/PrewarmPolicy.lua")
    native = read(ROOT / "core/NativeCallbackPolicy.lua")
    lab = read(ROOT / "core/LABAdapter.lua")
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
        lab,
        (
            "buttonsBySlot",
            "DisableBroadUpdateIfFullyHooked",
            "ForEachButtonTable",
            'library.UnregisterCallback(Buttons, "OnButtonUpdate")',
        ),
        "LAB callback policy",
    )
    errors += require(
        options,
        (
            "panel.OnRefresh = RefreshPanel",
            "panel.OnDefault = ResetDefaults",
            "panel.OnCommit = CommitPanel",
        ),
        "Settings canvas lifecycle",
    )
    errors += require(
        diagnostics,
        ("profileCounterOwner", "StartProfileCounters(owner)", "StopProfileCounters(owner)"),
        "Diagnostic ownership",
    )
    for scope, text in (("RuntimeProbe", probe), ("AGENTS", read(ROOT / "AGENTS.md"))):
        if CURRENT_KB_COMMIT not in text:
            errors.append(f"{scope} is not pinned to the current KB commit")
    errors += require(
        probe_policy,
        (
            "MAX_MARKS = 256",
            "MAX_RESTRICTIONS = 128",
            "buildsReportsOutOfCombatOnly = true",
        ),
        "Runtime probe bounds",
    )
    return errors


def check_test_manifest_and_no_ci() -> list[str]:
    errors: list[str] = []
    syntax = read(ROOT / "tests/check_syntax.lua")
    for path in sorted((ROOT / "tests").glob("*.lua")):
        if path.name == "check_syntax.lua":
            continue
        relative = path.relative_to(ROOT).as_posix()
        if f'"{relative}"' not in syntax:
            errors.append(f"Syntax checker does not include {relative}")

    loc_test = read(ROOT / "tests/loc_fail_closed.lua")
    errors += require(
        loc_test,
        (
            "optimistic option may not turn inaccessible LoC",
            "LOSS OF CONTROL FAIL-CLOSED TEST PASSED",
        ),
        "LoC focused regression test",
    )

    workflow_dir = ROOT / ".github/workflows"
    if workflow_dir.exists() and any(workflow_dir.glob("*.y*ml")):
        errors.append("GitHub Actions workflows must remain absent")
    return errors


def main() -> int:
    errors = (
        check_toc_and_version()
        + check_forbidden_hot_paths()
        + check_secret_and_restriction_boundaries()
        + check_readiness_and_sources()
        + check_lifecycle_workers_and_diagnostics()
        + check_test_manifest_and_no_ci()
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
