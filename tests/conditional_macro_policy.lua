local ROOT = arg[1] or "."

_G = _G or _ENV

local dirtyCalls = 0
local stats = {}

InterruptGlow = {
    modules = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    Buttons = {
        attached = true,
    },
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= _G.secretValue end
function InterruptGlow:ReadMember(object, key)
    if not object or not self.CanAccess(object) then return nil, false end
    local value = object[key]
    if not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:BumpStat(key, amount)
    stats[key] = (stats[key] or 0) + (amount or 1)
end
function InterruptGlow:MarkButtonDirty(button)
    dirtyCalls = dirtyCalls + 1
    return button
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
function Buttons:Detach()
    self.attached = false
end

local loader, loadError = loadfile(ROOT .. "/core/ConditionalMacroPolicy.lua")
assert(loader, loadError)
loader()

local native = { action = 7 }
local nativeRecord = Buttons:ObserveButton(native, "native")
assert(nativeRecord ~= nil)
assert(Buttons:InvalidateConditionalMacroSlot(7) == 1)
assert(dirtyCalls == 1)
assert(Buttons:InvalidateConditionalMacroSlot(8) == 0)
assert(dirtyCalls == 1)

-- Reindex a physical button when its action page/slot identity changes.
native.action = 8
InterruptGlow:MarkButtonDirty(native)
assert(dirtyCalls == 2)
assert(Buttons:InvalidateConditionalMacroSlot(7) == 0)
assert(Buttons:InvalidateConditionalMacroSlot(8) == 1)
assert(dirtyCalls == 3)

-- LibActionButton secure action state accepts an ordinary numeric string slot.
local lab = { _state_type = "action", _state_action = "9" }
Buttons:ObserveButton(lab, "lab")
assert(Buttons:InvalidateConditionalMacroSlot(9) == 1)
assert(dirtyCalls == 4)

-- Slot zero is a rare bounded global invalidation over observed slot-backed
-- buttons only; it is not an action-slot or frame scan.
assert(Buttons:InvalidateConditionalMacroSlot(0) == 2)
assert(dirtyCalls == 6)

-- Inaccessible state never enters the slot index or a table key.
secretValue = {}
local restricted = { action = secretValue }
Buttons:ObserveButton(restricted, "native")
assert(Buttons:InvalidateConditionalMacroSlot(10) == 0)

Buttons:Detach()
assert(Buttons.attached == false)
assert(Buttons:InvalidateConditionalMacroSlot(8) == 0)

local policy = assert(InterruptGlow.modules.ConditionalMacroPolicy)
assert(policy.usesTargetedUsabilitySignal == true)
assert(policy.identityUpdatesWhileReadinessSleeps == true)
assert(policy.slotIndexIsBounded == true)
assert(policy.parsesMacroBodies == false)
assert(policy.scansActionSlots == false)
assert((stats["events.conditionalMacroSlots"] or 0) == 4)

print("CONDITIONAL MACRO POLICY TEST PASSED")
