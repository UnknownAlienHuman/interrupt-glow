local ROOT = arg[1] or "."

_G = _G or _ENV

local readinessAwake = false
local dirtyCalls = 0
local cooldownDirtyCalls = 0
local allButtonsDirtyCalls = 0
local nativeCalls = 0
local usabilityCalls = 0
local protectedReads = 0
local hookCalls = 0
local clearVisualCalls = 0
local refreshUnitCalls = 0
local refreshAllCalls = 0
local refreshRecordCalls = 0
local reconcileCalls = 0
local reconcileSawPending = nil
local stats = {}
local secretValue = {}

function hooksecurefunc(object, methodName, hook)
    local original = assert(object[methodName])
    object[methodName] = function(...)
        original(...)
        hook(...)
    end
    hookCalls = hookCalls + 1
end

InterruptGlow = {
    modules = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
    Buttons = {
        attached = true,
    },
    Usability = {},
    Glow = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= secretValue end
function InterruptGlow:ReadMember(object, key)
    protectedReads = protectedReads + 1
    if not object or not self.CanAccess(object) then return nil, false end
    local value = object[key]
    if not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:AsNumber(value)
    if not self.CanAccess(value) then return nil end
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
end
function InterruptGlow:BumpStat(key, amount)
    stats[key] = (stats[key] or 0) + (amount or 1)
end
function InterruptGlow:WipeMap(map)
    for key in pairs(map) do map[key] = nil end
end
function InterruptGlow:NeedsReadinessRuntime()
    return readinessAwake
end
function InterruptGlow:MarkButtonDirty(button)
    local physical = button and button.button or button
    if not physical or self.PendingButtons[physical] then return end
    self.PendingButtons[physical] = true
    dirtyCalls = dirtyCalls + 1
end
function InterruptGlow:MarkCooldownDirty()
    cooldownDirtyCalls = cooldownDirtyCalls + 1
    return readinessAwake
end
function InterruptGlow:MarkAllButtonsDirty()
    allButtonsDirtyCalls = allButtonsDirtyCalls + 1
end

local Buttons = InterruptGlow.Buttons
function Buttons:ObserveButton(button, adapter)
    local record = InterruptGlow.ObservedButtons[button]
    if not record then
        record = { button = button, adapter = adapter }
        InterruptGlow.ObservedButtons[button] = record
    elseif adapter then
        record.adapter = adapter
    end
    return record
end
function Buttons:OnNativeActionChanged()
    nativeCalls = nativeCalls + 1
end
function Buttons:ReconcileRecord(record)
    reconcileCalls = reconcileCalls + 1
    reconcileSawPending = record and record.conditionalIdentityPending == true
end
function Buttons:Detach()
    self.attached = false
end

local Glow = InterruptGlow.Glow
function Glow:ClearRecord(record)
    clearVisualCalls = clearVisualCalls + 1
    record.visualVisible = false
end
function Glow:RefreshRecord(record)
    refreshRecordCalls = refreshRecordCalls + 1
    record.visualVisible = true
end
function Glow:RefreshUnit()
    refreshUnitCalls = refreshUnitCalls + 1
    for _, record in pairs(InterruptGlow.ObservedButtons) do
        self:RefreshRecord(record)
    end
end
function Glow:RefreshAll()
    refreshAllCalls = refreshAllCalls + 1
    for _, record in pairs(InterruptGlow.ObservedButtons) do
        self:RefreshRecord(record)
    end
end

local function ReconcilePending()
    for button in pairs(InterruptGlow.PendingButtons) do
        InterruptGlow.PendingButtons[button] = nil
        local record = InterruptGlow.ObservedButtons[button]
        if record then Buttons:ReconcileRecord(record) end
    end
end

local function ClearPending()
    for button in pairs(InterruptGlow.PendingButtons) do
        InterruptGlow.PendingButtons[button] = nil
    end
end

local dominosButton = {}
_G.DominosButton1 = dominosButton
local dominosController = {
    buttons = { [dominosButton] = 11 },
}
function dominosController:OnActionChanged(buttonName, action)
    local button = _G[buttonName]
    local record = Buttons:ObserveButton(button, "dominos")
    record.dominosSlot = action
    self.buttons[button] = action
end
function Buttons:AttachDominosNow(discoverExisting)
    assert(discoverExisting == true)
    self.dominosAttached = true
    self.DominosActionButtons = dominosController

    for button, slot in pairs(dominosController.buttons) do
        local record = self:ObserveButton(button, "dominos")
        record.dominosSlot = slot
    end
end

function InterruptGlow.Usability:OnActionUsableChanged(changes)
    usabilityCalls = usabilityCalls + 1
    assert(type(changes) == "table")
    return "base-result"
end

local loader, loadError = loadfile(ROOT .. "/core/ConditionalMacroPolicy.lua")
assert(loader, loadError)
loader()

local native = { action = 7 }
local nativeRecord = Buttons:ObserveButton(native, "native")
assert(nativeRecord ~= nil)
nativeRecord.visualVisible = true

-- With no relevant cast/countdown, ACTION_USABLE_CHANGED stores one weak button
-- and skips the base ability scan and dirty worker entirely.
assert(InterruptGlow.Usability:OnActionUsableChanged({ { slot = 7 } }) == false)
assert(usabilityCalls == 0)
assert(dirtyCalls == 0)
assert(nativeRecord.conditionalIdentityPending == true)

local clearBefore = clearVisualCalls
Glow:RefreshUnit("target")
assert(refreshUnitCalls == 1)
assert(clearVisualCalls > clearBefore)
assert(nativeRecord.visualVisible == false)

readinessAwake = true
assert(InterruptGlow:MarkCooldownDirty(false) == true)
assert(cooldownDirtyCalls == 1)
assert(dirtyCalls == 1)
assert(nativeRecord.conditionalIdentityPending == true)
ReconcilePending()
assert(reconcileCalls == 1)
assert(reconcileSawPending == true)
assert(nativeRecord.conditionalIdentityPending == false)

Glow:RefreshRecord(nativeRecord)
assert(refreshRecordCalls >= 1)
assert(nativeRecord.visualVisible == true)

-- Active signals retain the guard during reconciliation but do not leak into the
-- sleeping deferred queue and therefore cannot be scheduled twice later.
assert(InterruptGlow.Usability:OnActionUsableChanged({ { slot = 7 } }) == "base-result")
assert(usabilityCalls == 1)
assert(dirtyCalls == 2)
ClearPending()

local readsBeforeNative = protectedReads
native.action = 8
Buttons:OnNativeActionChanged(native)
assert(nativeCalls == 1)
assert(protectedReads == readsBeforeNative)
assert(Buttons:InvalidateConditionalMacroSlot(7) == 0)
assert(Buttons:InvalidateConditionalMacroSlot(8) == 1)
assert(dirtyCalls == 3)
ClearPending()

readinessAwake = false
native.action = 13
nativeRecord.visualVisible = true
Buttons:OnNativeActionChanged(native)
assert(nativeCalls == 1)
assert(dirtyCalls == 3)
assert(nativeRecord.conditionalIdentityPending == true)
assert(Buttons:InvalidateConditionalMacroSlot(8) == 0)
clearBefore = clearVisualCalls
Glow:RefreshAll()
assert(refreshAllCalls == 1)
assert(clearVisualCalls > clearBefore)
assert(nativeRecord.visualVisible == false)
readinessAwake = true
InterruptGlow:MarkCooldownDirty(false)
assert(cooldownDirtyCalls == 2)
assert(dirtyCalls == 4)
ReconcilePending()
assert(nativeRecord.conditionalIdentityPending == false)
assert(reconcileSawPending == true)

local lab = { _state_type = "action", _state_action = "9" }
local labRecord = Buttons:ObserveButton(lab, "lab")
labRecord.labSlot = 9
Buttons:RefreshConditionalMacroSlot(lab, labRecord)
assert(Buttons:InvalidateConditionalMacroSlot(9) == 1)
assert(dirtyCalls == 5)
ClearPending()

labRecord.labSlot = 10
InterruptGlow:MarkButtonDirty(lab)
assert(dirtyCalls == 6)
ClearPending()
assert(Buttons:InvalidateConditionalMacroSlot(9) == 0)
assert(Buttons:InvalidateConditionalMacroSlot(10) == 1)
assert(dirtyCalls == 7)
ClearPending()

Buttons:AttachDominosNow(true)
assert(hookCalls == 1)
assert(Buttons:InvalidateConditionalMacroSlot(11) == 1)
assert(dirtyCalls == 8)
ClearPending()

dominosController:OnActionChanged("DominosButton1", 12)
assert(Buttons:InvalidateConditionalMacroSlot(11) == 0)
assert(Buttons:InvalidateConditionalMacroSlot(12) == 1)
assert(dirtyCalls == 9)
ClearPending()

Buttons:ObserveButton(native, "buttonforge")
assert(Buttons:InvalidateConditionalMacroSlot(13) == 0)

assert(Buttons:InvalidateConditionalMacroSlot(0) == 2)
assert(dirtyCalls == 11)
ClearPending()

readinessAwake = false
InterruptGlow:MarkButtonDirty(native)
assert(dirtyCalls == 11)
assert(nativeRecord.conditionalIdentityPending == true)
readinessAwake = true
InterruptGlow:MarkCooldownDirty(false)
assert(cooldownDirtyCalls == 3)
assert(dirtyCalls == 12)
ReconcilePending()
assert(nativeRecord.conditionalIdentityPending == false)
assert(reconcileSawPending == true)

readinessAwake = false
assert(InterruptGlow.Usability:OnActionUsableChanged(secretValue) == false)
assert(InterruptGlow.Usability:OnActionUsableChanged({ { slot = secretValue } }) == false)
assert(usabilityCalls == 1)
assert(dirtyCalls == 12)

Buttons:Detach()
assert(Buttons.attached == false)
assert(Buttons:InvalidateConditionalMacroSlot(10) == 0)
assert(Buttons:InvalidateConditionalMacroSlot(12) == 0)
assert(allButtonsDirtyCalls == 0)

local policy = assert(InterruptGlow.modules.ConditionalMacroPolicy)
assert(policy.usesTargetedUsabilitySignal == true)
assert(policy.invalidatesSnapshotsBeforeActiveReconcile == true)
assert(policy.marksIdentityPendingForActiveChanges == true)
assert(policy.retainsVisualGuardThroughReconcile == true)
assert(policy.failedReconcileRemainsFailClosed == true)
assert(policy.separatesActiveGuardFromSleepingQueue == true)
assert(policy.defersIdentityWhileReadinessSleeps == true)
assert(policy.flushesBeforeCooldownRefresh == true)
assert(policy.hidesStaleVisualsUntilReconcile == true)
assert(policy.publicHelpersUseMethodSemantics == true)
assert(policy.parsesActionUsableChangeBatch == true)
assert(policy.dirtyHookIsActionProviderOnly == true)
assert(policy.nativeCallbackReadsActionAPIs == false)
assert(policy.dominosIdentityRefreshesAfterProviderCommit == true)
assert(policy.adapterPromotionDropsStaleSlots == true)
assert(policy.slotIndexIsBounded == true)
assert(policy.pendingGuardSetUsesWeakButtons == true)
assert(policy.deferredSetUsesWeakButtons == true)
assert(policy.parsesMacroBodies == false)
assert(policy.scansActionSlots == false)
assert((stats["events.conditionalMacroDeferred"] or 0) == 1)
assert((stats["events.conditionalMacroDeferredFlush"] or 0) == 3)
assert((stats["events.nativeActionDeferred"] or 0) == 1)
assert((stats["events.conditionalMacroSlots"] or 0) == 8)

print("CONDITIONAL MACRO POLICY TEST PASSED")
