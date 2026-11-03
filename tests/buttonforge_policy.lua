local ROOT = arg[1] or "."

_G = _G or _ENV

local dirtyCalls = 0
local inaccessible = {}
local refreshHook
function hooksecurefunc(_, methodName, callback)
    if methodName == "FullRefresh" then refreshHook = callback end
end
ButtonForge_API1 = { RegisterCallback = function() end }
BFButton = { FullRefresh = function() end, ClearCommand = function() end }

InterruptGlow = {
    DB = { enabled = true },
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
    InterruptRecords = setmetatable({}, { __mode = "k" }),
    AbilityStates = {},
    Data = {},
    Glow = { ClearRecord = function() end, QueueShell = function() end },
}
function InterruptGlow.CanAccess(value) return value ~= inaccessible end
function InterruptGlow.CanAccessTable(value)
    return InterruptGlow.CanAccess(value) and type(value) == "table"
end
function InterruptGlow:ReadMember(object, key)
    if object == nil then return nil, false end
    return object[key], true
end
function InterruptGlow:AsNumber(value)
    if type(value) == "number" then return value end
end
function InterruptGlow:BumpStat() end
function InterruptGlow:MarkButtonDirty(button)
    dirtyCalls = dirtyCalls + 1
    self.PendingButtons[button] = true
end
function InterruptGlow.Data:GetCanonicalSpellID(spellID)
    if spellID == 1766 then return 1766 end
end

local buttonName = "ButtonForge1"
local buttonObject = { Mode = "spell", MacroMode = nil, SpellId = 1766 }
local button = { ParentButton = buttonObject }
buttonObject.Widget = button
_G[buttonName] = button

local loader, loadError = loadfile(ROOT .. "/core/Buttons.lua")
assert(loader, loadError)
loader()
local Buttons = assert(InterruptGlow.Buttons)
Buttons.attached = true
Buttons.buttonForgeAttached = true

Buttons:ObserveButtonForgeName(buttonName)
local record = assert(InterruptGlow.ObservedButtons[button])
record.isInterrupt = true
assert(record.buttonForgeName == buttonName)
assert(record.buttonForgeDeallocated == false)
assert(record.buttonForgeObject == buttonObject)
InterruptGlow.PendingButtons[button] = nil
dirtyCalls = 0

-- The provider may clear its global before notifying observers. The addon's
-- weak name index still resolves the same physical widget, while unbinding is
-- deferred to the addon reconciliation queue.
_G[buttonName] = nil
Buttons:OnButtonForgeEvent("BUTTON_DEALLOCATED", buttonName)
assert(record.buttonForgeObject == nil)
assert(record.buttonForgeMode == nil)
assert(record.buttonForgeMacroMode == nil)
assert(record.buttonForgeSpellID == nil)
assert(record.buttonForgeDeallocated == true)
assert(record.isInterrupt == true, "deallocation unbound synchronously inside provider callback")
assert(dirtyCalls == 1)

-- Repeated deallocation before the next flush is idempotent.
Buttons:OnButtonForgeEvent("BUTTON_DEALLOCATED", buttonName)
assert(dirtyCalls == 1)

-- A new allocation snapshots its current object again and resolves current
-- identity; later provider events still enter only the deferred queue.
_G[buttonName] = button
Buttons:ObserveButtonForgeName(buttonName)
assert(record.buttonForgeDeallocated == false)
assert(Buttons:ResolveButtonForge(record) == true)
assert(record.buttonForgeDeallocated == false)
Buttons:OnButtonForgeEvent("BUTTON_ALLOCATED", buttonName)
assert(record.buttonForgeDeallocated == false)

-- Persistent restrictions invalidate the last readable identity once, without
-- creating repeated reconciliation work in ButtonForge's per-frame refresh.
Buttons:AttachButtonForgeNow(false)
assert(type(refreshHook) == "function")
refreshHook(buttonObject)
dirtyCalls = 0
buttonObject.SpellId = inaccessible
refreshHook(buttonObject)
assert(dirtyCalls == 1)
assert(record.buttonForgeMode == nil and record.buttonForgeSpellID == nil)
assert(Buttons:ResolveButtonForge(record) == false, "restricted identity retained its old binding")
refreshHook(buttonObject)
assert(dirtyCalls == 1, "persistent restriction queued work on every provider refresh")
buttonObject.SpellId = 1766
refreshHook(buttonObject)
assert(dirtyCalls == 2, "readable identity recovery was not reconciled")
assert(Buttons:ResolveButtonForge(record) == true)

-- Unbinding clears all normalized restriction/readiness values on the actual
-- Buttons owner, so stale cooldown diagnostics cannot cross a new identity.
record.hardRestrictedCooldown = true
record.readinessPending = true
record.restrictedCooldown = true
Buttons:UnbindRecord(record)
assert(record.hardRestrictedCooldown == false)
assert(record.readinessPending == false)
assert(record.restrictedCooldown == false)
assert(record.deadline == nil)

print("BUTTONFORGE LIFECYCLE TEST PASSED")
