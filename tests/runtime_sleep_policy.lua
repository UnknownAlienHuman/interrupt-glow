local ROOT = arg[1] or "."

_G = _G or _ENV

local calls = {
    native = 0,
    labUpdate = 0,
    labContents = 0,
    castUnit = 0,
    castAll = 0,
    castEvent = 0,
    glowAll = 0,
    glowUnit = 0,
    cdmItem = 0,
    cdmExisting = 0,
    workerDisable = 0,
    allDirty = 0,
    castDirty = 0,
    cooldownDirty = 0,
}

InterruptGlow = {
    modules = {},
    DB = { enabled = true, cdm = true },
    testMode = false,
    Buttons = {
        attached = true,
        buttonForgeAttached = true,
        dominosAttached = true,
        DominosActionButtons = {},
    },
    Glow = {},
    CastTracking = {
        channelSuppressed = { target = true, focus = true },
    },
    CDM = { attached = true },
    CastState = {
        target = {
            active = true,
            hostile = true,
            castBarID = 11,
            isChannel = true,
            niState = "interruptible",
            channelSuppressed = true,
        },
        focus = {
            active = true,
            hostile = true,
            castBarID = 22,
            isChannel = false,
            niState = "restricted",
            channelSuppressed = true,
        },
    },
}

local IG = InterruptGlow

ButtonForge_API1 = {}

function IG:RegisterModule(name, module) self.modules[name] = module end
function IG:BumpStat() end
function IG:MarkAllButtonsDirty() calls.allDirty = calls.allDirty + 1 end
function IG:MarkCastDirty() calls.castDirty = calls.castDirty + 1 end
function IG:MarkCooldownDirty() calls.cooldownDirty = calls.cooldownDirty + 1 end

function IG.Buttons:OnNativeActionChanged() calls.native = calls.native + 1 end
function IG.Buttons:OnLABButtonUpdate() calls.labUpdate = calls.labUpdate + 1 end
function IG.Buttons:OnLABButtonContentsChanged() calls.labContents = calls.labContents + 1 end

function IG.Glow:ApplyUnitInterruptibility() end
function IG.Glow:RefreshUnit() calls.glowUnit = calls.glowUnit + 1 end
function IG.Glow:SetRuntimeWorkerEnabled(enabled)
    if enabled == false then calls.workerDisable = calls.workerDisable + 1 end
end
function IG.Glow:RefreshAll() calls.glowAll = calls.glowAll + 1 end
function IG.Glow:UpdateRuntimeDriver() end
function IG.Glow:CreatePendingOverlays() end

function IG.CastTracking:RefreshUnit() calls.castUnit = calls.castUnit + 1 end
function IG.CastTracking:RefreshAll() calls.castAll = calls.castAll + 1 end
function IG.CastTracking:OnUnitEvent() calls.castEvent = calls.castEvent + 1 end

function IG.CDM:ObserveItem() calls.cdmItem = calls.cdmItem + 1 end
function IG.CDM:ObserveExistingItems() calls.cdmExisting = calls.cdmExisting + 1 end

local loader, loadError = loadfile(ROOT .. "/core/RuntimeSleepPolicy.lua")
assert(loader, loadError)
loader()

-- Enabled runtime delegates without extra reconciliation.
IG.Buttons:OnNativeActionChanged({})
assert(calls.native == 1)
assert(calls.allDirty == 0 and calls.castDirty == 0 and calls.cooldownDirty == 0)

-- The first disabled callback performs one state clear and turns off provider
-- hot-path guards. The original callback is not invoked.
IG.DB.enabled = false
IG.Buttons:OnNativeActionChanged({})
assert(calls.native == 1)
assert(IG.Buttons.buttonForgeAttached == false)
assert(IG.Buttons.dominosAttached == false)
assert(IG.CastState.target.active == false and IG.CastState.focus.active == false)
assert(IG.CastState.target.hostile == false and IG.CastState.focus.hostile == false)
assert(IG.CastState.target.castBarID == nil and IG.CastState.focus.castBarID == nil)
assert(IG.CastTracking.channelSuppressed.target == false)
assert(IG.CastTracking.channelSuppressed.focus == false)
assert(calls.workerDisable >= 1)

local policy = assert(IG.modules.RuntimeSleepPolicy)
assert(policy.exposesState() == true)

-- Fixed-unit and provider callbacks remain no-op while disabled.
IG.CastTracking:RefreshUnit("target")
IG.CastTracking:RefreshAll()
IG.CastTracking:OnUnitEvent("target", "UNIT_SPELLCAST_START")
IG.Buttons:OnLABButtonUpdate(nil, {})
IG.Buttons:OnLABButtonContentsChanged(nil, {})
IG.CDM:ObserveItem({})
assert(calls.castUnit == 0 and calls.castAll == 0 and calls.castEvent == 0)
assert(calls.labUpdate == 0 and calls.labContents == 0)
assert(calls.cdmItem == 0)

-- A provider loaded after sleep is guarded again without repeating the cast
-- state transition.
IG.Buttons.buttonForgeAttached = true
IG.Buttons.dominosAttached = true
IG.Buttons:OnNativeActionChanged({})
assert(IG.Buttons.buttonForgeAttached == false)
assert(IG.Buttons.dominosAttached == false)

-- First enabled entry wakes once, restores provider guards, queues one
-- authoritative rebuild and then delegates the current operation.
IG.DB.enabled = true
IG.Glow:RefreshAll()
assert(policy.exposesState() == false)
assert(IG.Buttons.buttonForgeAttached == true)
assert(IG.Buttons.dominosAttached == true)
assert(calls.allDirty == 1)
assert(calls.castDirty == 1)
assert(calls.cooldownDirty == 1)
assert(calls.cdmExisting == 1)
assert(calls.glowAll == 1)

-- Subsequent enabled callbacks do not repeat the wake rebuild.
IG.Buttons:OnNativeActionChanged({})
IG.CastTracking:OnUnitEvent("target", "UNIT_SPELLCAST_START")
IG.CDM:ObserveItem({})
assert(calls.native == 2)
assert(calls.castEvent == 1)
assert(calls.cdmItem == 1)
assert(calls.allDirty == 1 and calls.castDirty == 1 and calls.cooldownDirty == 1)

assert(policy.nativeMouseoverCallbacksSleepWhenDisabled == true)
assert(policy.fixedUnitSnapshotsSleepWhenDisabled == true)
assert(policy.cdmPoolCallbacksSleepWhenDisabled == true)
assert(policy.lateProviderLoadsRemainGuarded == true)
assert(policy.wakeUsesOneCoalescedAuthoritativeRefresh == true)

print("RUNTIME SLEEP POLICY TEST PASSED")
