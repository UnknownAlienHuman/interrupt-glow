from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "InterruptGlow.toc"

RUNTIME_FILES = [
    ROOT / "Core.lua",
    *sorted((ROOT / "core").glob("*.lua")),
    ROOT / "Options.lua",
]

FORBIDDEN_RUNTIME_PATTERNS = {
    "EnumerateFrames": re.compile(r"\bEnumerateFrames\b"),
    "GetNamePlates": re.compile(r"\bGetNamePlates\b"),
    "540-slot scan": re.compile(r"\b540\b"),
    "GetMacroInfo": re.compile(r"\bGetMacroInfo\b"),
    "GetMacroSpell": re.compile(r"\bGetMacroSpell\b"),
    "ACTIONBAR_UPDATE_COOLDOWN subscription": re.compile(r"RegisterEvent\s*\(\s*[\"']ACTIONBAR_UPDATE_COOLDOWN"),
    "generic ADDON_LOADED subscription": re.compile(r"RegisterEvent\s*\(\s*[\"']ADDON_LOADED"),
    "Blizzard spell-alert manager mutation": re.compile(r"\bActionButtonSpellAlertManager\b"),
    "castbar state inspection": re.compile(r"\b(TargetFrameSpellBar|FocusFrameSpellBar|CastingBarMixin)\b"),
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


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def check_toc() -> list[str]:
    errors: list[str] = []
    text = read(TOC)
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("##"):
            continue
        path = ROOT / line
        if not path.exists():
            errors.append(f"TOC references missing file: {line}")
    if "## Interface: 120100" not in text:
        errors.append("TOC Interface is not 120100")
    if "## Version: 1.1.0-beta.2" not in text:
        errors.append("TOC version is not 1.1.0-beta.2")
    if "## LoadOnDemand:" in text:
        errors.append("Interrupt Glow itself must not be LoadOnDemand; it must observe combat automatically")
    return errors


def check_forbidden_patterns() -> list[str]:
    errors: list[str] = []
    for path in RUNTIME_FILES:
        text = read(path)
        for label, pattern in FORBIDDEN_RUNTIME_PATTERNS.items():
            if pattern.search(text):
                errors.append(f"{path.relative_to(ROOT)} contains forbidden runtime pattern: {label}")
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
    if re.search(r"niRaw\s*=|notInterruptibleRaw\s*=", cast + glow):
        errors.append("Potential raw interruptibility storage detected")
    if "CreatePulseAnimation(overlay.target.niGate)" in glow:
        errors.append("Animation must not be attached to the region carrying the Alpha secret aspect")
    if "CreatePulseAnimation(overlay.target.plainGate)" not in glow:
        errors.append("Ordinary parent-gate animation is missing")
    return errors


def check_startup_and_hot_paths() -> list[str]:
    errors: list[str] = []
    events = read(ROOT / "core" / "Events.lua")
    shared = read(ROOT / "core" / "Shared.lua")
    buttons = read(ROOT / "core" / "Buttons.lua")
    lab = read(ROOT / "core" / "LABAdapter.lua")
    options = read(ROOT / "Options.lua")

    if events.count("Buttons:Attach(true)") != 1:
        errors.append("Expected exactly one integrated callback-first startup attach/discovery call")
    if "DiscoverAll(false)" in events:
        errors.append("Startup must not run a second standalone discovery pass")
    if "ContinueOnPlayerLogin" not in events:
        errors.append("Runtime initialization is not deferred through ContinueOnPlayerLogin")
    if "local function RegisterRuntimeEvents()" not in events or "RegisterRuntimeEvents()" not in events:
        errors.append("Gameplay events are not registered lazily at PLAYER_LOGIN")
    if "_loadedOrLoading, loaded" not in shared:
        errors.append("IsAddOnFullyLoaded must inspect the second IsAddOnLoaded return")
    if "CastTracking:RefreshAll()" in buttons:
        errors.append("Button reconciliation must not snapshot target/focus once per changed button")
    if "function Options:Build()" not in options or 'panel:SetScript("OnShow"' not in options:
        errors.append("Options controls are not lazily built on first panel show")
    if "ability.hasEvaluation" not in buttons or "evaluatedGeneration" not in buttons:
        errors.append("Dormant conditional-macro abilities do not retain generation-validated readiness")
    if buttons.count('WaitForKnownLABProvider("ElvUI")') != 1:
        errors.append("ElvUI load-order waiter is missing or duplicated")
    if 'hooksecurefunc(BFButton, "ClearCommand"' not in buttons:
        errors.append("ButtonForge ClearCommand lifecycle hook is missing")

    # ACTIONBAR_SLOT_CHANGED is allowed only as the LAB action-slot diff surface.
    # The handler must index already-known buttons by the event's slot and must not
    # scan action slots, frames or macro bodies.
    slot_subscription = re.compile(r"RegisterEvent\s*\(\s*[\"']ACTIONBAR_SLOT_CHANGED")
    for runtime_path in RUNTIME_FILES:
        if runtime_path.name == "LABAdapter.lua":
            continue
        if slot_subscription.search(read(runtime_path)):
            errors.append(f"{runtime_path.relative_to(ROOT)} has a non-targeted ACTIONBAR_SLOT_CHANGED subscription")
    if lab.count('RegisterEvent("ACTIONBAR_SLOT_CHANGED")') != 1:
        errors.append("LAB targeted action-slot invalidation is missing or duplicated")
    if "buttonsBySlot" not in lab or "for button in pairs(set)" not in lab:
        errors.append("LAB slot event is not bounded to pre-indexed buttons")
    if 'UnregisterCallback(self, "OnButtonUpdate")' not in lab:
        errors.append("Broad LibActionButton visual-update callback is not removed for hookable providers")
    if 'hooksecurefunc, button, "UpdateAction"' not in lab:
        errors.append("Exact LibActionButton UpdateAction hook is missing")

    cooldown = read(ROOT / "core" / "Cooldown.lua")
    readiness_policy = read(ROOT / "core" / "ReadinessPolicy.lua")
    if "CaptureGCDHints" not in cooldown or "isOnGCD" not in cooldown:
        errors.append("SPELL_UPDATE_COOLDOWN GCD normalization is missing")
    if events.count("CaptureGCDHints()") != 1 or events.count("MarkCooldownDirty(true)") != 1:
        errors.append("GCD provenance must be captured exactly once in the SPELL_UPDATE_COOLDOWN handler")
    for runtime_path in RUNTIME_FILES:
        if runtime_path.name == "Events.lua":
            continue
        if "MarkCooldownDirty(true)" in read(runtime_path):
            errors.append(f"{runtime_path.relative_to(ROOT)} marks cooldown dirty with unverified GCD provenance")
    status_start = cooldown.find("local function ReadCooldownStatus")
    status_end = cooldown.find("local function ReadLossOfControlState")
    if status_start >= 0 and status_end > status_start and 'ReadMember(info, "isOnGCD")' in cooldown[status_start:status_end]:
        errors.append("isOnGCD is read outside the event-time normalization path")
    if "hardRestricted" not in cooldown:
        errors.append("Restricted Loss of Control does not have a non-optimistic hard gate")
    if "ability.hardRestricted == true and ability.needsPoll == true" not in readiness_policy:
        errors.append("Hard restrictions still activate the periodic cooldown poll")
    if "GetPetActionSlotUsable" not in readiness_policy:
        errors.append("Pet interrupt readiness does not include intrinsic pet-action usability")

    cdm = read(ROOT / "core" / "CDM.lua")
    if "record.cdmCanonicalSpellID == canonicalSpellID" not in cdm:
        errors.append("Duplicate Cooldown Viewer acquire/ID notifications are not suppressed")
    return errors


def check_interrupt_data() -> list[str]:
    errors: list[str] = []
    data = read(ROOT / "core" / "Data.lua")

    if "-- BEGIN GENERATED INTERRUPTS_BY_SPEC" not in data or "-- END GENERATED INTERRUPTS_BY_SPEC" not in data:
        errors.append("Generated interrupt snapshot markers are missing")
    for spec_id, snippet in EXPECTED_SPEC_SNIPPETS.items():
        if snippet not in data:
            errors.append(f"Missing current Blizzard interrupt mapping for spec {spec_id}: {snippet}")
    if re.search(r"\[115781\]\s*=|\{[^\n}]*\b115781\b", data):
        errors.append("Removed Retail Optical Blast ID 115781 returned to runtime data")
    if "EXTRA_INTERRUPTS_BY_SPEC" not in data or data.count("212619") < 3:
        errors.append("Warlock Call Felhunter PvP interrupt coverage is missing")
    if "[19647] = 119910" not in data or "[89766] = 119914" not in data:
        errors.append("Current Warlock pet-action aliases are incomplete")
    return errors


def main() -> int:
    errors = (
        check_toc()
        + check_forbidden_patterns()
        + check_secret_sink()
        + check_startup_and_hot_paths()
        + check_interrupt_data()
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
