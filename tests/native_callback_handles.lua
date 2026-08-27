local ROOT = arg[1] or "."

_G = _G or _ENV

local registerCount = 0
local unregisterCount = 0
local fallbackAttachCount = 0
local fallbackDetachCount = 0

InterruptGlow = {
    modules = {},
    Buttons = {
        nativeAttached = false,
    },
}
function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end

function InterruptGlow.Buttons:OnNativeActionChanged() end
function InterruptGlow.Buttons:AttachNative()
    fallbackAttachCount = fallbackAttachCount + 1
    self.nativeAttached = true
end
function InterruptGlow.Buttons:Detach()
    fallbackDetachCount = fallbackDetachCount + 1
    self.nativeAttached = false
end

EventRegistry = {}
function EventRegistry:RegisterCallbackWithHandle(event, callback, owner)
    assert(event == "ActionButton.OnActionChanged")
    assert(type(callback) == "function")
    assert(owner == InterruptGlow.Buttons)
    registerCount = registerCount + 1
    local active = true
    return {
        Unregister = function()
            if active then
                active = false
                unregisterCount = unregisterCount + 1
            end
        end,
    }
end

EventUtil = {}
function EventUtil.CreateCallbackHandleContainer()
    local handles = {}
    return {
        RegisterCallback = function(self, registry, event, callback, owner)
            handles[#handles + 1] = registry:RegisterCallbackWithHandle(event, callback, owner)
        end,
        Unregister = function()
            for index = 1, #handles do handles[index]:Unregister() end
            handles = {}
        end,
        IsEmpty = function()
            return #handles == 0
        end,
    }
end

local loader, loadError = loadfile(ROOT .. "/core/NativeCallbackPolicy.lua")
assert(loader, loadError)
loader()

local buttons = InterruptGlow.Buttons
buttons:AttachNative()
buttons:AttachNative()
assert(registerCount == 1)
assert(fallbackAttachCount == 0)
assert(buttons.nativeAttached == true)

buttons:Detach()
assert(unregisterCount == 1)
assert(fallbackDetachCount == 1)
assert(buttons.nativeAttached == false)

buttons:AttachNative()
buttons:Detach()
assert(registerCount == 2)
assert(unregisterCount == 2)

print("NATIVE CALLBACK HANDLE TEST PASSED")
