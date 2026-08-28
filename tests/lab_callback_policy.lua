local ROOT = arg[1] or "."

_G = _G or _ENV

local dirtyCalls = 0
local unregisterCalls = 0
local hookedCalls = 0

local slotFrame = { scripts = {} }
function slotFrame:Hide() end
function slotFrame:RegisterEvent() end
function slotFrame:UnregisterEvent() end
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
    modules = {},
    Buttons = {
        attached = true,
        labLibraries = setmetatable({}, { __mode = "k" }),
    },
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:ReadMember(object, key) return object[key], true end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:MarkButtonDirty() dirtyCalls = dirtyCalls + 1 end
function InterruptGlow:BumpStat() end

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
function library.UnregisterCallback(owner, event)
    assert(owner == Buttons)
    assert(event == "OnButtonUpdate")
    unregisterCalls = unregisterCalls + 1
end

local loader, loadError = loadfile(ROOT .. "/core/LABAdapter.lua")
assert(loader, loadError)
loader()

-- Empty-at-attach providers must retain the broad fallback until a real button
-- exists; otherwise their later creation would be invisible.
Buttons:AttachLABLibrary(library, false, false)
assert(unregisterCalls == 0)

local button = {
    _state_type = "action",
    _state_action = 7,
    UpdateAction = function() end,
}
allButtons[1] = button
library.buttonRegistry[button] = true
Buttons:OnLABButtonCreated(nil, button)
assert(hookedCalls == 1)
assert(unregisterCalls == 1, "late-created LAB button did not retire broad callback")
assert(dirtyCalls == 1)

-- Further content changes must not repeat callback removal.
Buttons:OnLABButtonContentsChanged(nil, button)
assert(hookedCalls == 1)
assert(unregisterCalls == 1)

-- Detach/re-attach re-registers provider callbacks in the base adapter. The
-- policy must forget its previous removal state and remove the new broad
-- registration again once exact hooks are known.
Buttons:Detach()
Buttons.attached = true
Buttons:AttachLABLibrary(library, true, false)
assert(unregisterCalls == 2)

print("LAB CALLBACK POLICY TEST PASSED")
