local ROOT = arg[1] or "."

_G = _G or _ENV

local dirtyCalls = 0
local delegatedEvents = 0

InterruptGlow = {
    modules = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    Buttons = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:MarkButtonDirty() dirtyCalls = dirtyCalls + 1 end
function InterruptGlow:BumpStat() end

local buttonName = "ButtonForge1"
local button = {}
local object = {}
_G[buttonName] = button

function InterruptGlow.Buttons:ObserveButtonForgeName(name)
    assert(name == buttonName)
    InterruptGlow.ObservedButtons[button] = InterruptGlow.ObservedButtons[button] or {
        button = button,
        adapter = "buttonforge",
        buttonForgeObject = object,
        buttonForgeMode = "spell",
        buttonForgeMacroMode = "conditional",
        buttonForgeSpellID = 1766,
        isInterrupt = true,
    }
end
function InterruptGlow.Buttons:OnButtonForgeEvent()
    delegatedEvents = delegatedEvents + 1
end

local loader, loadError = loadfile(ROOT .. "/core/ButtonForgePolicy.lua")
assert(loader, loadError)
loader()

local Buttons = InterruptGlow.Buttons
Buttons:ObserveButtonForgeName(buttonName)
local record = assert(InterruptGlow.ObservedButtons[button])
assert(record.buttonForgeName == buttonName)

-- Simulate ButtonForge clearing its global before sending deallocation. The
-- policy-owned weak name map must still locate the observed physical button.
_G[buttonName] = nil
Buttons:OnButtonForgeEvent("BUTTON_DEALLOCATED", buttonName)
assert(record.buttonForgeObject == nil)
assert(record.buttonForgeMode == nil)
assert(record.buttonForgeMacroMode == nil)
assert(record.buttonForgeSpellID == nil)
assert(record.isInterrupt == true,
    "ButtonForge deallocation unbound synchronously inside provider callback")
assert(dirtyCalls == 1)
assert(delegatedEvents == 0)

-- Duplicate deallocation is a no-op once ordinary identity has already cleared.
record.isInterrupt = false
Buttons:OnButtonForgeEvent("BUTTON_DEALLOCATED", buttonName)
assert(dirtyCalls == 1)

Buttons:OnButtonForgeEvent("BUTTON_ALLOCATED", buttonName)
assert(delegatedEvents == 1)

local policy = assert(InterruptGlow.modules.ButtonForgePolicy)
assert(policy.defersDeallocationReconcile == true)
assert(policy.survivesEarlyGlobalRemoval == true)

print("BUTTONFORGE POLICY TEST PASSED")
