local ROOT = arg[1] or "."

_G = _G or _ENV

local readinessAwake = true
local dirtyCalls = 0
local cooldownDirtyCalls = 0
local allDirtyCalls = 0
local nativeBaseCalls = 0
local usabilityBaseCalls = 0
local clearCalls = 0
local refreshUnitCalls = 0
local reconcileCalls = 0
local reconcileSawPending = nil
local reconcileSawFreshSnapshot = nil

InterruptGlow = {
    modules = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
    InterruptRecords = setmetatable({}, { __mode = "k" }),
    Buttons = { attached = true },
    Usability = {},
    Glow = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess() return true end
function InterruptGlow:ReadMember(object, key)
    if not object then return nil, false end
    return object[key], true
end
function InterruptGlow:AsNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
end
function InterruptGlow:WipeMap(map)
    for key in pairs(map) do map[key] = nil end
end
function InterruptGlow:BumpStat() end
function InterruptGlow:NeedsReadinessRuntime() return readinessAwake end
function InterruptGlow:MarkButtonDirty(button)
    if self.PendingButtons[button] then return end
    self.PendingButtons[button] = true
    dirtyCalls = dirtyCalls + 1
end
function InterruptGlow:MarkCooldownDirty()
    cooldownDirtyCalls = cooldownDirtyCalls + 1
    return true
end
function InterruptGlow:MarkAllButtonsDirty()
    allDirtyCalls = allDirtyCalls + 1
end

local Buttons = InterruptGlow.Buttons
function Buttons:ObserveButton(button, adapter)
    local record = InterruptGlow.ObservedButtons[button]
    if not record then
        record = { button = button, adapter = adapter }
        InterruptGlow.ObservedButtons[button] = record
    end
    return record
end
function Buttons:OnNativeActionChanged(button)
    nativeBaseCalls = nativeBaseCalls + 1
    local record = InterruptGlow.ObservedButtons[button]
    record.actionSnapshotFresh = false
    InterruptGlow:MarkButtonDirty(button)
end
function Buttons:ReconcileRecord(record)
    reconcileCalls = reconcileCalls + 1
    reconcileSawPending = record.conditionalIdentityPending == true
    reconcileSawFreshSnapshot = record.actionSnapshotFresh == true
end
function Buttons:AttachDominosNow() end
function Buttons:Detach() self.attached = false end

function InterruptGlow.Usability:OnActionUsableChanged()
    usabilityBaseCalls = usabilityBaseCalls + 1
    return true
end

local Glow = InterruptGlow.Glow
function Glow:ClearRecord(record)
    clearCalls = clearCalls + 1
    record.visualVisible = false
end
function Glow:RefreshRecord(record)
    record.visualVisible = true
end
function Glow:RefreshUnit()
    refreshUnitCalls = refreshUnitCalls + 1
    -- Match the real Glow:RefreshUnit boundary: it writes candidates directly
    -- and therefore can try to expose stale record state before reconciliation.
    for record in pairs(InterruptGlow.InterruptRecords) do
        record.visualVisible = true
    end
end
function Glow:RefreshAll()
    for record in pairs(InterruptGlow.InterruptRecords) do
        record.visualVisible = true
    end
end

local loader, loadError = loadfile(ROOT .. "/core/ConditionalMacroPolicy.lua")
assert(loader, loadError)
loader()

local button = { action = 7 }
local record = assert(Buttons:ObserveButton(button, "native"))
record.isInterrupt = true
record.overlay = {}
record.actionSnapshotFresh = true
record.visualVisible = true
InterruptGlow.InterruptRecords[record] = true

local function ReconcilePending()
    for pendingButton in pairs(InterruptGlow.PendingButtons) do
        InterruptGlow.PendingButtons[pendingButton] = nil
        Buttons:ReconcileRecord(assert(InterruptGlow.ObservedButtons[pendingButton]))
    end
end

-- Active ACTION_USABLE_CHANGED must invalidate the normalized action snapshot,
-- mark identity pending and hide the old interrupt visual before next-frame work.
assert(InterruptGlow.Usability:OnActionUsableChanged({ { slot = 7 } }) == true)
assert(usabilityBaseCalls == 1)
assert(dirtyCalls == 1)
assert(record.actionSnapshotFresh == false)
assert(record.conditionalIdentityPending == true)
assert(record.visualVisible == false)

-- A synchronous unit refresh is allowed to write the old candidate first, but
-- the policy must clear it again before returning to the renderer.
local clearsBeforeRefresh = clearCalls
Glow:RefreshUnit("target")
assert(refreshUnitCalls == 1)
assert(clearCalls > clearsBeforeRefresh)
assert(record.visualVisible == false)

ReconcilePending()
assert(reconcileCalls == 1)
assert(reconcileSawPending == false)
assert(reconcileSawFreshSnapshot == false)
assert(record.conditionalIdentityPending == false)

-- The exact native callback has the same active-cast guard.
record.actionSnapshotFresh = true
record.visualVisible = true
Buttons:OnNativeActionChanged(button)
assert(nativeBaseCalls == 1)
assert(dirtyCalls == 2)
assert(record.actionSnapshotFresh == false)
assert(record.conditionalIdentityPending == true)
assert(record.visualVisible == false)
ReconcilePending()

-- While readiness sleeps, callbacks do not wake reconciliation. A later full
-- rebuild must preserve the pending visual guard instead of deleting its weak
-- deferred entry before the new cast can flush it.
readinessAwake = false
record.actionSnapshotFresh = true
record.visualVisible = true
Buttons:OnNativeActionChanged(button)
assert(nativeBaseCalls == 1)
assert(dirtyCalls == 2)
assert(record.actionSnapshotFresh == false)
assert(record.conditionalIdentityPending == true)
assert(record.visualVisible == false)

InterruptGlow:MarkAllButtonsDirty()
assert(allDirtyCalls == 1)
Glow:RefreshUnit("target")
assert(record.visualVisible == false)

readinessAwake = true
InterruptGlow:MarkCooldownDirty(false)
assert(cooldownDirtyCalls == 1)
assert(dirtyCalls == 3)
assert(record.conditionalIdentityPending == true)
ReconcilePending()
assert(record.conditionalIdentityPending == false)
assert(reconcileSawPending == false)
assert(reconcileSawFreshSnapshot == false)

-- Detach clears any retained pending marker so a later lifecycle activation
-- starts from a normal full discovery/reconcile boundary.
readinessAwake = false
Buttons:OnNativeActionChanged(button)
assert(record.conditionalIdentityPending == true)
Buttons:Detach()
assert(record.conditionalIdentityPending == false)

local policy = assert(InterruptGlow.modules.ConditionalMacroPolicy)
assert(policy.invalidatesSnapshotsBeforeActiveReconcile == true)
assert(policy.marksIdentityPendingForActiveChanges == true)
assert(policy.defersIdentityWhileReadinessSleeps == true)
assert(policy.flushesBeforeCooldownRefresh == true)
assert(policy.hidesStaleVisualsUntilReconcile == true)
assert(policy.fullRebuildPreservesVisualGuard == true)
assert(policy.nativeCallbackReadsActionAPIs == false)
assert(policy.parsesMacroBodies == false)
assert(policy.scansActionSlots == false)

print("CONDITIONAL ACTIVE IDENTITY GUARD TEST PASSED")
