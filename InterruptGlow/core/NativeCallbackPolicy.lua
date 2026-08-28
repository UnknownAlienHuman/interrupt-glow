local IG = _G.InterruptGlow
if not IG or not IG.Buttons then return end

local Buttons = IG.Buttons
local _G = _G
local EventRegistry = _G.EventRegistry
local EventUtil = _G.EventUtil
local type = type

local originalAttachNative = Buttons.AttachNative
local originalDetach = Buttons.Detach

function Buttons:AttachNative()
    if self.nativeAttached then return end

    if EventRegistry
        and EventUtil
        and type(EventUtil.CreateCallbackHandleContainer) == "function"
        and type(EventRegistry.RegisterCallbackWithHandle) == "function"
    then
        self.nativeCallbackHandles = self.nativeCallbackHandles
            or EventUtil.CreateCallbackHandleContainer()

        if self.nativeCallbackHandles:IsEmpty() then
            self.nativeCallbackHandles:RegisterCallback(
                EventRegistry,
                "ActionButton.OnActionChanged",
                self.OnNativeActionChanged,
                self
            )
        end

        self.nativeUsesHandleContainer = true
        self.nativeAttached = true
        return
    end

    originalAttachNative(self)
end

function Buttons:Detach()
    if self.nativeUsesHandleContainer and self.nativeCallbackHandles then
        self.nativeCallbackHandles:Unregister()
        self.nativeUsesHandleContainer = false
        self.nativeAttached = false
    end

    originalDetach(self)
end
