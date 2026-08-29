local ROOT = arg[1] or "."

_G = _G or _ENV

local dirtyCalls = 0
local nativeCalls = 0
local usabilityCalls = 0
local protectedReads = 0
local stats = {}
local secretValue = {}

InterruptGlow = {
    modules = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
    Buttons = {
        attached = true,
    },
    Usability = {},
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
function InterruptGlow:MarkButtonDirty(button)
    local physical = button and button.button or button
    if not physical or self.PendingButtons[physical] then return end
    self.PendingButtons[physical] = true
    dirtyCalls = dirtyCalls + 1
end

local function ClearPending()
    for button in pairs(InterruptGlow.PendingButtons) do
        InterruptGlow.PendingButtons[button] = nil
    end
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
function Buttons:Detach()
    self.attached = false
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

-- ACTION_USABLE_CHANGED supplies a batch of change records, not one scalar slot.
assert(InterruptGlow.Usability:OnActionUsableChanged({ { slot = 7 } }) == "base-result")
assert(usabilityCalls == 1)
assert(dirtyCalls == 1)
ClearPending()

-- The native callback updates the bounded slot index using one ordinary field
-- read and no generic protected member access or action API call.
local readsBeforeNative = protectedReads
native.action = 8
Buttons:OnNativeActionChanged(native)
assert(nativeCalls == 1)
assert(protectedReads == readsBeforeNative)
assert(Buttons:InvalidateConditionalMacroSlot(7) == 0)
assert(Buttons:InvalidateConditionalMacroSlot(8) == 1)
assert(dirtyCalls == 2)
ClearPending()

-- LibActionButton updates record.labSlot before MarkButtonDirty. The targeted
-- dirty wrapper refreshes only this cached LAB identity.
local lab = { _state_type = "action", _state_action = "9" }
local labRecord = Buttons:ObserveButton(lab, "lab")
labRecord.labSlot = 9
Buttons:RefreshConditionalMacroSlot(lab, labRecord)
assert(Buttons:InvalidateConditionalMacroSlot(9) == 1)
assert(dirtyCalls == 3)
ClearPending()

labRecord.labSlot = 10
InterruptGlow:MarkButtonDirty(lab)
assert(dirtyCalls == 4)
ClearPending()
assert(Buttons:InvalidateConditionalMacroSlot(9) == 0)
assert(Buttons:InvalidateConditionalMacroSlot(10) == 1)
assert(dirtyCalls == 5)
ClearPending()

-- Slot zero is a rare bounded global invalidation over observed slot-backed
-- buttons only; it is not an action-slot or frame scan.
assert(Buttons:InvalidateConditionalMacroSlot(0) == 2)
assert(dirtyCalls == 7)
ClearPending()

-- Restricted payloads and fields never enter the index or become table keys.
assert(InterruptGlow.Usability:OnActionUsableChanged(secretValue) == "base-result")
assert(InterruptGlow.Usability:OnActionUsableChanged({ { slot = secretValue } }) == "base-result")
assert(dirtyCalls == 7)

Buttons:Detach()
assert(Buttons.attached == false)
assert(Buttons:InvalidateConditionalMacroSlot(8) == 0)

local policy = assert(InterruptGlow.modules.ConditionalMacroPolicy)
assert(policy.usesTargetedUsabilitySignal == true)
assert(policy.identityUpdatesWhileReadinessSleeps == true)
assert(policy.parsesActionUsableChangeBatch == true)
assert(policy.dirtyHookIsLABOnly == true)
assert(policy.nativeCallbackReadsActionAPIs == false)
assert(policy.slotIndexIsBounded == true)
assert(policy.parsesMacroBodies == false)
assert(policy.scansActionSlots == false)
assert((stats["events.conditionalMacroSlots"] or 0) == 5)

print("CONDITIONAL MACRO POLICY TEST PASSED")
