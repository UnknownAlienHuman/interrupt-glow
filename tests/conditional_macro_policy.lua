local ROOT = arg[1] or "."

_G = _G or _ENV

local readinessAwake = false
local dirtyCalls = 0
local cooldownCalls = 0
local clearCalls = 0
local reconcileCalls = 0
local memberReads = 0
local stats = {}
local opaqueChanges = setmetatable({}, {
    __pairs = function() error("opaque usability batch was iterated") end,
})

InterruptGlow = {
    DB = { enabled = true, cdText = false },
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
    AbilityStates = {},
    Buttons = { attached = true },
    Cooldown = {},
    Glow = {},
}
local IG = InterruptGlow
function IG.CanAccess(_) return true end
function IG.CanAccessTable(value)
    return value ~= opaqueChanges and type(value) == "table"
end
function IG:ReadMember(object, key)
    memberReads = memberReads + 1
    assert(object ~= opaqueChanges, "opaque usability batch reached member access")
    if object == nil then return nil, false end
    return object[key], true
end
function IG:AsNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
end
function IG:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function IG:BumpStat(key, amount) stats[key] = (stats[key] or 0) + (amount or 1) end
function IG:NeedsReadinessRuntime() return readinessAwake end
function IG:QueueButtonForReconcile(button)
    if self.PendingButtons[button] then return false end
    self.PendingButtons[button] = true
    dirtyCalls = dirtyCalls + 1
    return true
end
function IG:MarkButtonDirty(button)
    if self.ConditionalActions and not self.ConditionalActions:QueueButton(button) then return end
    self:QueueButtonForReconcile(button)
end
function IG:MarkCooldownDirty()
    if not self:NeedsReadinessRuntime() then return false end
    cooldownCalls = cooldownCalls + 1
    self.ConditionalActions:FlushDeferred()
    return true
end
function IG.Glow:AllowOverlayAccessRetry() return true end
function IG.Glow:QueueShell() end
function IG.Glow:ClearRecord(record)
    clearCalls = clearCalls + 1
    record.visualVisible = false
end
function IG.Buttons:ReconcileRecord(record)
    reconcileCalls = reconcileCalls + 1
    self.identityPendingDuringReconcile = record.conditionalIdentityPending == true
end

local usabilityLoader, usabilityError = loadfile(ROOT .. "/core/Usability.lua")
assert(usabilityLoader, usabilityError)
usabilityLoader()
local actionsLoader, actionsError = loadfile(ROOT .. "/core/ConditionalActions.lua")
assert(actionsLoader, actionsError)
actionsLoader()

local Actions = assert(IG.ConditionalActions)
local button = { action = 7 }
local record = {
    button = button,
    adapter = "native",
    isInterrupt = true,
    overlay = {},
    visualVisible = true,
}
IG.ObservedButtons[button] = record
Actions:Observe(button, record)

-- Idle native identity signals stay in a bounded weak set and hide stale output
-- without scheduling readiness work or resolving the action early.
IG:MarkButtonDirty(button)
assert(record.conditionalIdentityPending == true)
assert(record.visualVisible == false and clearCalls == 1)
assert(IG.PendingButtons[button] == nil and dirtyCalls == 0)

local changed = IG.Usability:OnActionUsableChanged({ { slot = 7 } })
assert(changed == false)
assert(IG.PendingButtons[button] == nil and dirtyCalls == 0)
assert(record.conditionalIdentityPending == true)

-- When readiness wakes, the deferred button enters the ordinary reconcile
-- queue exactly once. The dirty reconciliation owns the pending-state cleanup.
readinessAwake = true
assert(IG:MarkCooldownDirty() == true)
assert(cooldownCalls == 1 and dirtyCalls == 1)
assert(IG.PendingButtons[button] == true)
for pendingButton in pairs(IG.PendingButtons) do
    IG.PendingButtons[pendingButton] = nil
    local pendingRecord = IG.ObservedButtons[pendingButton]
    assert(pendingRecord.conditionalIdentityPending == true)
    IG.Buttons:ReconcileRecord(pendingRecord)
    Actions:Reconciled(pendingRecord)
end
assert(reconcileCalls == 1 and IG.Buttons.identityPendingDuringReconcile == true)
assert(record.conditionalIdentityPending == false)

-- Active slot invalidations are coalesced through the same physical queue.
record.visualVisible = true
assert(Actions:InvalidateSlot(7) == 1)
assert(Actions:InvalidateSlot(7) == 1)
assert(dirtyCalls == 2 and IG.PendingButtons[button] == true)
assert(record.conditionalIdentityPending == true and record.visualVisible == false)
for pendingButton in pairs(IG.PendingButtons) do
    IG.PendingButtons[pendingButton] = nil
    Actions:Reconciled(IG.ObservedButtons[pendingButton])
end
assert(record.conditionalIdentityPending == false)

-- An opaque ACTION_USABLE_CHANGED batch is gated before iteration or member
-- reads, so no payload is inspected to find affected slots.
local readsBeforeOpaqueBatch = memberReads
local queuedBeforeOpaqueBatch = dirtyCalls
readinessAwake = true
assert(IG.Usability:OnActionUsableChanged(opaqueChanges) == true)
assert(memberReads >= readsBeforeOpaqueBatch)
assert(dirtyCalls == queuedBeforeOpaqueBatch + 1)

print("CONDITIONAL ACTIONS SLEEP/WAKE TEST PASSED")
