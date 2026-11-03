local ROOT = arg[1] or "."

_G = _G or _ENV

local dirtyCalls = 0
local unregisterCalls = 0
local hookedCalls = 0
local restrictedButton = nil
local identityRestricted = false

local slotFrame = { scripts = {}, registered = {} }
function slotFrame:Hide() end
function slotFrame:RegisterEvent(event) self.registered[event] = true end
function slotFrame:UnregisterEvent(event) self.registered[event] = nil end
function slotFrame:SetScript(name, fn) self.scripts[name] = fn end
function CreateFrame() return slotFrame end

function hooksecurefunc(object, methodName, callback)
    assert(methodName == "UpdateAction")
    assert(type(object[methodName]) == "function")
    object.__updateActionHook = callback
    hookedCalls = hookedCalls + 1
end

InterruptGlow = {
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    Buttons = {
        attached = true,
        labLibraries = setmetatable({}, { __mode = "k" }),
        labDiscoveredLibraries = setmetatable({}, { __mode = "k" }),
    },
}
function InterruptGlow:ReadMember(object, key)
    if identityRestricted and object == restrictedButton
        and (key == "_state_type" or key == "_state_action")
    then
        return nil, false
    end
    return object[key], true
end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow.CanAccessTable(value) return type(value) == "table" end
function InterruptGlow:MarkButtonDirty() dirtyCalls = dirtyCalls + 1 end
function InterruptGlow:BumpStat() end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end

local Buttons = InterruptGlow.Buttons
function Buttons:ObserveButton(button, adapter)
    assert(type(button) == "table", "numeric LAB array index was treated as a button")
    local record = InterruptGlow.ObservedButtons[button]
    if not record then
        record = { button = button, adapter = adapter }
        InterruptGlow.ObservedButtons[button] = record
    end
    return record
end
function Buttons:AttachLABLibrary(library)
    self.labLibraries[library] = true
end
function Buttons:Attach() self.attached = true end
function Buttons:Detach()
    for library in pairs(self.labLibraries) do self.labLibraries[library] = nil end
    self.attached = false
end

local allButtons = {}
local library = {
    buttonRegistry = {},
}
function library:GetAllButtons()
    -- Deliberately use an array to cover LAB forks that do not expose the
    -- upstream button-keyed set directly.
    return allButtons
end
function library.RegisterCallback(owner, event, method)
    assert(owner == InterruptGlow.LABAdapter)
    library.callbacks = library.callbacks or {}
    library.callbacks[event] = method
end
function library.UnregisterCallback(owner, event)
    assert(owner == InterruptGlow.LABAdapter)
    assert(event == "OnButtonCreated" or event == "OnButtonUpdate" or event == "OnButtonContentsChanged")
    unregisterCalls = unregisterCalls + 1
end

local loader, loadError = loadfile(ROOT .. "/core/LABAdapter.lua")
assert(loader, loadError)
loader()
local Adapter = assert(InterruptGlow.LABAdapter)
Adapter:Attach()

-- Empty-at-attach providers must retain the broad fallback until a real button
-- exists; otherwise their later creation would be invisible.
Adapter:AttachLibrary(library, false, false)
assert(unregisterCalls == 0)

local button = {
    _state_type = "action",
    _state_action = 7,
    UpdateAction = function() end,
}
restrictedButton = button
allButtons[1] = button
library.buttonRegistry[button] = true
Adapter:OnButtonCreated(nil, button)
assert(hookedCalls == 1)
assert(unregisterCalls == 1, "late-created LAB button did not retire broad callback")
assert(dirtyCalls == 1)

local record = assert(InterruptGlow.ObservedButtons[button])
assert(record.labStateType == "action" and record.labStateAction == 7)
assert(record.labSlot == 7 and record.labIdentityRestricted == false)

-- Accessible empty secure identity is not the same as an unreadable identity.
-- It must clear the previous slot and queue one fail-closed reconciliation.
button._state_type = nil
button._state_action = nil
button.__updateActionHook(button)
assert(record.labStateType == nil and record.labStateAction == nil)
assert(record.labSlot == nil and record.labIdentityRestricted == false)
assert(dirtyCalls == 2)

-- Repeating the same empty identity is a no-op, and the old slot index is gone.
button.__updateActionHook(button)
assert(dirtyCalls == 2)
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", 7)
assert(dirtyCalls == 2)

-- A later readable slot becomes indexed again.
button._state_type = "action"
button._state_action = "8"
button.__updateActionHook(button)
assert(record.labSlot == 8 and record.labIdentityRestricted == false)
assert(dirtyCalls == 3)

-- If secure identity fields become inaccessible, stale ordinary identity and
-- slot membership are discarded immediately. Repeated restricted updates do not
-- create a per-frame dirty storm.
identityRestricted = true
button.__updateActionHook(button)
assert(record.labStateType == nil and record.labStateAction == nil)
assert(record.labSlot == nil and record.labIdentityRestricted == true)
assert(dirtyCalls == 4)
button.__updateActionHook(button)
assert(dirtyCalls == 4)
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", 8)
assert(dirtyCalls == 4)

identityRestricted = false
button._state_action = 9
button.__updateActionHook(button)
assert(record.labSlot == 9 and record.labIdentityRestricted == false)
assert(dirtyCalls == 5)

-- Further content changes must not repeat callback removal or hook installation.
Adapter:OnButtonContentsChanged(nil, button)
assert(hookedCalls == 1)
assert(unregisterCalls == 1)

-- Detach drops targeted slot indexes. Re-attach re-registers provider callbacks
-- in the base adapter and removes the new broad registration once exact hooks
-- are known again.
Adapter:Detach()
assert(Adapter.attached == false)
local beforeDetachedSlot = dirtyCalls
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", 9)
assert(dirtyCalls == beforeDetachedSlot)

Adapter:Attach()
Buttons.attached = true
Adapter:AttachLibrary(library, true, false)
assert(unregisterCalls == 5)

print("LAB CALLBACK POLICY TEST PASSED")
