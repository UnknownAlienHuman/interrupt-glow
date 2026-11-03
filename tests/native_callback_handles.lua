local ROOT = arg[1] or "."

_G = _G or _ENV

local registerCount = 0
local unregisterCount = 0

InterruptGlow = {
    DB = { enabled = true },
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
}
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow.CanAccessTable(value) return type(value) == "table" end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat() end

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
        IsEmpty = function() return #handles == 0 end,
    }
end

local loader, loadError = loadfile(ROOT .. "/core/Buttons.lua")
assert(loader, loadError)
loader()
local Buttons = assert(InterruptGlow.Buttons)

Buttons:AttachNative()
Buttons:AttachNative()
assert(registerCount == 1)
assert(Buttons.nativeAttached == true and Buttons.nativeUsesHandleContainer == true)

Buttons:Detach()
assert(unregisterCount == 1)
assert(Buttons.nativeAttached == false and Buttons.attached == false)

Buttons:AttachNative()
Buttons:Detach()
assert(registerCount == 2)
assert(unregisterCount == 2)

print("NATIVE CALLBACK HANDLE TEST PASSED")
