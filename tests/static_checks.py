from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "InterruptGlow.toc"
CURRENT_VERSION = "1.1.0-beta.7"
CURRENT_INTERFACE = "120100"
CURRENT_KB_COMMIT = "5a992ae702a278f3893c7e8f1b212583311438b5"
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


def section(text: str, start: str, end: str | None = None) -> str:
    begin = text.find(start)
    if begin < 0:
        return ""
    if end is None:
        return text[begin:]
    finish = text.find(end, begin + len(start))
    return text[begin:] if finish < 0 else text[begin:finish]


def require(text: str, snippets: tuple[str, ...], scope: str) -> list[str]:
    return [f"{scope} is missing {snippet}" for snippet in snippets if snippet not in text]


def forbid(text: str, snippets: tuple[str, ...], scope: str) -> list[str]:
    return [f"{scope} contains forbidden {snippet}" for snippet in snippets if snippet in text]


def require_before(text: str, first: str, second: str, scope: str) -> list[str]:
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
        "core/SpecInterruptCoveragePolicy.lua",
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
        "core/ConditionalMacroPolicy.lua",
        "core/GCDSafetyPolicy.lua",
        "core/CachePolicy.lua",
        "core/AbilitySourcePolicy.lua",
        "core/BoundSourcePolicy.lua",
        "core/CastTracking.lua",
        "core/CDM.lua",
        "core/CDMPolicy.lua",
        "core/RuntimeInterruptPolicy.lua",
        "core/RuntimeLifecyclePolicy.lua",
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


def check_forbidden_runtime_patterns() -> list[str]:
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
        "legacy spell LoC global": r"\bGetSpellLossOfControlCooldown\s*\(",
        "Blizzard spell-alert manager mutation": r"\bActionButtonSpellAlertManager\b",
        "Blizzard castbar inspection": r"\b(TargetFrameSpellBar|FocusFrameSpellBar)\b",
        "legacy scriptProfile": r"\bscriptProfile\b",
    }

    for path in RUNTIME_FILES:
        text = read(path)
        for label, pattern in patterns.items():
            if re.search(pattern, text):
                errors.append(f"{path.relative_to(ROOT)} contains forbidden {label}")

        if path.name != "LABAdapter.lua" and re.search(
            r"RegisterEvent\s*\(\s*[\"']ACTIONBAR_SLOT_CHANGED", text
        ):
            errors.append(
                f"{path.relative_to(ROOT)} registers ACTIONBAR_SLOT_CHANGED outside LABAdapter"
            )

    return errors


def check_conditional_action_policy() -> list[str]:
    errors: list[str] = []
    policy = read(ROOT / "core/ConditionalMacroPolicy.lua")
    native_queue = read(ROOT / "core/NativeActionQueuePolicy.lua")

    errors += require(
        policy,
        (
            'deferredButtons = setmetatable({}, { __mode = "k" })',
            "local function ReadinessAwake()",
            "local function FlushDeferredButtons()",
            "function IG:MarkCooldownDirty(fromSpellCooldownEvent)",
            "if ReadinessAwake() then FlushDeferredButtons() end",
            "function Buttons:OnNativeActionChanged(button, ...)",
            "record.actionSnapshotFresh = false",
            "function Usability:OnActionUsableChanged(changes, ...)",
            "DeferChanges(changes)",
            "originalAttachDominosNow",
            "dominosIdentityRefreshesAfterProviderCommit = true",
            "adapterPromotionDropsStaleSlots = true",
            "defersIdentityWhileReadinessSleeps = true",
            "flushesBeforeCooldownRefresh = true",
            "publicHelpersUseMethodSemantics = true",
            "function Buttons:InvalidateConditionalMacroSlot(slot)",
            "function Buttons:RefreshConditionalMacroSlot(button, record)",
            "parsesMacroBodies = false",
            "scansActionSlots = false",
        ),
        "Conditional action policy",
    )
    errors += forbid(
        policy,
        (
            "GetActionInfo",
            "IsInterruptAction",
            "IsAssistedCombatAction",
            "GetMacroInfo",
            "GetMacroSpell",
        ),
        "Conditional action callback layer",
    )

    callback = section(
        native_queue,
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
        "Native queue callback",
    )
    errors += require_before(
        callback,
        "record.actionSnapshotFresh = false",
        "if IG.PendingButtons[button] then return end",
        "Native queue invalidation/dedupe",
    )
    errors += forbid(
        callback,
        (
            "ReadActionSnapshot",
            "IsInterruptAction",
            "IsAssistedCombatAction",
            "GetActionInfo",
            "GetSpell",
            "ResolveRecord",
        ),
        "Native queue callback",
    )
    return errors


def check_runtime_sleep_policy() -> list[str]:
    errors: list[str] = []
    events = read(ROOT / "core/Events.lua")
    lifecycle = read(ROOT / "core/RuntimeLifecyclePolicy.lua")

    errors += require(
        events,
        (
            "local RUNTIME_EVENTS = {",
            "local PERSISTENT_EVENTS = {",
            '"PLAYER_REGEN_ENABLED"',
            '"ADDON_RESTRICTION_STATE_CHANGED"',
            "function IG:SetRuntimeEventsEnabled(enabled)",
            "frame:UnregisterEvent(RUNTIME_EVENTS[index])",
            'frame:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", "player")',
            'frame:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", "player")',
            'frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")',
            'frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")',
            "masterDisableUnregistersRuntimeEvents = true",
            "RegisterPersistentEvents()",
        ),
        "Runtime event sleep policy",
    )
    errors += forbid(
        events,
        (
            'frame:RegisterEvent("LOSS_OF_CONTROL_ADDED")',
            'frame:RegisterEvent("LOSS_OF_CONTROL_UPDATE")',
        ),
        "Loss of Control registration",
    )

    errors += require(
        lifecycle,
        (
            "SetRuntimeEventsEnabled(false)",
            "SetRuntimeEventsEnabled(true)",
            "masterDisableDetachesProviders = true",
            "masterDisableDetachesCastWatchers = true",
            "masterDisableUnregistersRuntimeEvents = true",
            "masterDisableStopsWorkers = true",
            "enableDiscoveryIsOutOfCombat = true",
        ),
        "Master runtime lifecycle",
    )
    deactivate = section(lifecycle, "function Lifecycle:Deactivate()", "function Lifecycle:Activate()")
    errors += require_before(
        deactivate,
        "SetRuntimeEventsEnabled(false)",
        "IG.CDM:Detach()",
        "Runtime event shutdown/provider detach",
    )
    activate = section(lifecycle, "function Lifecycle:Activate()", "function Lifecycle:Initialize()")
    errors += require_before(
        activate,
        "self.active = true",
        "SetRuntimeEventsEnabled(true)",
        "Runtime activation/event registration",
    )
    return errors


def check_secret_and_frame_boundaries() -> list[str]:
    errors: list[str] = []
    cooldown = read(ROOT / "core/Cooldown.lua")
    cast = read(ROOT / "core/CastTracking.lua")
    glow = read(ROOT / "core/Glow.lua")
    frame_access = read(ROOT / "core/FrameAccessPolicy.lua")

    charge = section(cooldown, "local function ReadChargeInfo", "local function ReadLossOfControlState")
    loc = section(cooldown, "local function ReadLossOfControlState", "local function GetActionLossOfControlState")
    errors += require_before(
        charge,
        "if not IG.CanAccess(info) then",
        "if info == nil then",
        "Charge SecretValue ordering",
    )
    errors += require_before(
        loc,
        "if not IG.CanAccess(info) then",
        "if info == nil then",
        "Loss of Control SecretValue ordering",
    )
    errors += require(
        cooldown,
        (
            "C_Spell.GetSpellLossOfControlCooldownInfo",
            "GetActionCooldownDuration, slot, true",
            "GetSpellCooldownDuration, spellID, true",
            'type(isActive) ~= "boolean"',
            'type(replaces) ~= "boolean"',
            "hardRestricted",
        ),
        "Cooldown/LoC contract",
    )
    if re.search(r"\bGetSpellLossOfControlCooldown\s*\(", cooldown):
        errors.append("Cooldown resolver still calls the legacy spell LoC global")

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
            "if dead ~= false then return false end",
        ),
        "Cast secret/channel boundary",
    )
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
        errors.append("Raw SecretValue alpha sink is wrapped in pcall")

    errors += require(
        frame_access,
        (
            "local function InspectButtonAccess(button)",
            "if not IG.CanAccess(button) then return ACCESS_DEFERRED end",
            'IG:ReadMember(button, "IsForbidden")',
            "MAX_TRANSIENT_RETRIES = 3",
            "overlayAccessFailures",
            "reobservationCanResumePrewarm = true",
            "confirmedForbiddenIsPermanent = true",
            "function Glow:CreateShell(record)",
        ),
        "Foreign frame access policy",
    )
    create_shell = section(
        frame_access,
        "function Glow:CreateShell(record)",
        "local originalQueueShell",
    )
    errors += require_before(
        create_shell,
        "local access = InspectButtonAccess(record.button)",
        "CreateUnitBranch(record.button)",
        "Foreign frame preflight/allocation",
    )
    return errors


def check_readiness_and_provider_policies() -> list[str]:
    errors: list[str] = []
    readiness = read(ROOT / "core/ReadinessPolicy.lua")
    usability = read(ROOT / "core/Usability.lua")
    gcd = read(ROOT / "core/GCDSafetyPolicy.lua")
    source = read(ROOT / "core/AbilitySourcePolicy.lua")
    bound = read(ROOT / "core/BoundSourcePolicy.lua")
    data = read(ROOT / "core/Data.lua")
    spec = read(ROOT / "core/SpecInterruptCoveragePolicy.lua")
    runtime = read(ROOT / "core/RuntimeInterruptPolicy.lua")
    prewarm = read(ROOT / "core/PrewarmPolicy.lua")
    cdm = read(ROOT / "core/CDM.lua")

    errors += require(
        readiness,
        ("GetPetActionSlotUsable", "ability.hardRestricted == true"),
        "Pet readiness policy",
    )
    errors += require(
        usability,
        ("IsUsableAction", "IsSpellUsable", "OnActionUsableChanged"),
        "Usability policy",
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
        "Bound source policy",
    )
    errors += require(
        data,
        (
            "-- BEGIN GENERATED INTERRUPTS_BY_SPEC",
            "-- END GENERATED INTERRUPTS_BY_SPEC",
            "PET_ACTION_ALIASES",
            "IsRuntimeFamilyKnown",
            BLIZZARD_SOURCE_COMMIT,
        ),
        "Interrupt data",
    )
    errors += require(
        spec,
        (
            "extraInterruptsBySpec",
            "RequiresExactKnownSpell",
            "neverAddsUnknownOptionalInterrupts = true",
        ),
        "Optional interrupt coverage policy",
    )
    errors += require(
        runtime,
        (
            "IG:WipeMap(self.runtimeInterrupts)",
            "function Buttons:ReconcileAll()",
            "actionSlotsSeedBeforeSecondaryCopies = true",
            "refreshesCDMAfterActionSeed = true",
            "negativeMatchLimit = NEGATIVE_MATCH_LIMIT",
        ),
        "Runtime interrupt proof policy",
    )
    errors += require(
        prewarm,
        (
            "processed < self.prewarmBudgetPerFrame",
            "self:EnsureInterruptVisuals(record)",
            "prewarmsInterruptVisualsForAllObservedButtons = true",
            "combatSwitchingRequiresNoVisualAllocation = true",
        ),
        "Prewarm policy",
    )
    errors += require(
        cdm,
        ("QueueIdentityChange", "IG:MarkButtonDirty(itemFrame)"),
        "Cooldown Viewer deferred identity policy",
    )
    return errors


def check_lifecycle_persistence_and_evidence() -> list[str]:
    errors: list[str] = []
    shared = read(ROOT / "core/Shared.lua")
    worker = read(ROOT / "core/Worker.lua")
    native = read(ROOT / "core/NativeCallbackPolicy.lua")
    options = read(ROOT / "Options.lua")
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
        native,
        ("CreateCallbackHandleContainer", "nativeCallbackHandles:Unregister"),
        "Native callback lifecycle",
    )
    errors += require(
        options,
        (
            "RuntimeLifecycle",
            "SetMasterEnabled",
            "panel.OnRefresh",
            "panel.OnDefault",
            "panel.OnCommit",
            "OnCombatEnded",
        ),
        "Settings lifecycle",
    )
    errors += require(
        probe_policy,
        (
            "MAX_MARKS = 256",
            "MAX_RESTRICTIONS = 128",
            "buildsReportsOutOfCombatOnly = true",
            "finalizesCaptureOutOfCombatOnly = true",
        ),
        "Runtime probe policy",
    )

    for scope, text in (
        ("AGENTS", read(ROOT / "AGENTS.md")),
        ("AGENT_GUIDE", read(ROOT / "AGENT_GUIDE.md")),
        ("RuntimeProbe", probe),
    ):
        if CURRENT_KB_COMMIT not in text:
            errors.append(f"{scope} is not pinned to current KB {CURRENT_KB_COMMIT}")

    return errors


def check_tests_and_repository_contract() -> list[str]:
    errors: list[str] = []
    syntax = read(ROOT / "tests/check_syntax.lua")
    for path in sorted((ROOT / "tests").glob("*.lua")):
        if path.name == "check_syntax.lua":
            continue
        relative = path.relative_to(ROOT).as_posix()
        if f'"{relative}"' not in syntax:
            errors.append(f"Syntax checker does not include {relative}")

    required_tests = (
        "tests/action_resolver_fast_path.lua",
        "tests/conditional_macro_policy.lua",
        "tests/frame_access_policy.lua",
        "tests/runtime_lifecycle_policy.lua",
        "tests/runtime_event_sleep.lua",
        "tests/loc_fail_closed.lua",
        "tests/loc_event_contract.lua",
        "tests/prewarm_budget.lua",
        "tests/toc_contract.lua",
    )
    for relative in required_tests:
        if not (ROOT / relative).is_file():
            errors.append(f"Required regression test is missing: {relative}")

    conditional_test = read(ROOT / "tests/conditional_macro_policy.lua")
    errors += require(
        conditional_test,
        (
            "CONDITIONAL MACRO POLICY TEST PASSED",
            "defersIdentityWhileReadinessSleeps == true",
            "dominosIdentityRefreshesAfterProviderCommit == true",
            "Buttons:InvalidateConditionalMacroSlot",
        ),
        "Conditional macro regression test",
    )
    event_test = read(ROOT / "tests/runtime_event_sleep.lua")
    errors += require(
        event_test,
        (
            "RUNTIME EVENT SLEEP TEST PASSED",
            "runtimeEventsRegistered == false",
            "registered.SPELL_UPDATE_COOLDOWN == nil",
        ),
        "Runtime event sleep regression test",
    )

    workflow_dir = ROOT / ".github/workflows"
    if workflow_dir.exists() and any(workflow_dir.glob("*.y*ml")):
        errors.append("GitHub Actions workflows must remain absent")

    for forbidden_name in ("todo.md", "TODO.md", "agents.md"):
        if (ROOT / forbidden_name).exists():
            errors.append(f"Service file should not be part of the installable root: {forbidden_name}")

    return errors


def main() -> int:
    errors = (
        check_toc_and_version()
        + check_forbidden_runtime_patterns()
        + check_conditional_action_policy()
        + check_runtime_sleep_policy()
        + check_secret_and_frame_boundaries()
        + check_readiness_and_provider_policies()
        + check_lifecycle_persistence_and_evidence()
        + check_tests_and_repository_contract()
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
