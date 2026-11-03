local ROOT = arg[1] or "."
_G = _G or _ENV

local deniedObject
local deniedTable
local inaccessibleLABIdentity = false
local labButton
local observedDirty = {}
local shellQueues = 0

local slotFrame = { scripts = {}, registered = {} }
function slotFrame:Hide() end
function slotFrame:RegisterEvent(event) self.registered[event] = true end
function slotFrame:UnregisterEvent(event) self.registered[event] = nil end
function slotFrame:SetScript(name, fn) self.scripts[name] = fn end
function CreateFrame() return slotFrame end

function hooksecurefunc(object, methodName, callback)
    assert(methodName == "UpdateAction")
    object.__updateActionHook = callback
end

InterruptGlow = {
    DB = { enabled = true, cdText = false, cdm = false },
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
    InterruptRecords = setmetatable({}, { __mode = "k" }),
    AbilityStates = {},
    Glow = {},
    Usability = {},
}
local IG = InterruptGlow
function IG.CanAccess(value) return value ~= deniedObject end
function IG.CanAccessTable(value)
    return IG.CanAccess(value) and type(value) == "table" and value ~= deniedTable
end
function IG:ReadMember(object, key)
    if not IG.CanAccess(object) or object == nil then return nil, false end
    if type(object) == "table" and not IG.CanAccessTable(object) then return nil, false end
    if object == labButton and inaccessibleLABIdentity
        and (key == "_state_type" or key == "_state_action")
    then
        return nil, false
    end
    local value = object[key]
    if not IG.CanAccess(value) then return nil, false end
    return value, true
end
function IG:AsNumber(value)
    if not IG.CanAccess(value) then return nil end
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
end
function IG:NeedsReadinessRuntime() return true end
function IG:QueueButtonForReconcile(button)
    self.PendingButtons[button] = true
end
function IG:MarkButtonDirty(button)
    if self.ConditionalActions then self.ConditionalActions:QueueButton(button) end
    observedDirty[#observedDirty + 1] = button
end
function IG:BumpStat() end
function IG:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function IG:Now() return 1 end
function IG:IsAddOnFullyLoaded() return false end
function IG:IsInCombat() return false end
function IG:Print() end
local resolverFallbackCalls = 0
IG.ActionResolver = {
    GetActionSlot = function(_, button)
        resolverFallbackCalls = resolverFallbackCalls + 1
        return button.action
    end,
}
function IG.Glow:QueueShell() shellQueues = shellQueues + 1 end
function IG.Glow:AllowOverlayAccessRetry() return true end
function IG.Glow:ClearRecord() end
function IG.Glow:EnsureInterruptVisuals() end
function IG.Glow:RefreshRecord() end
function IG.Glow:ApplyStoredInterruptibilityToRecord() return true end
function IG.Glow:RefreshCooldownText() end

local buttonsLoader, buttonsError = loadfile(ROOT .. "/core/Buttons.lua")
assert(buttonsLoader, buttonsError)
buttonsLoader()
local Buttons = assert(IG.Buttons)

local actionsLoader, actionsError = loadfile(ROOT .. "/core/ConditionalActions.lua")
assert(actionsLoader, actionsError)
actionsLoader()
local Actions = assert(IG.ConditionalActions)

local labLoader, labError = loadfile(ROOT .. "/core/LABAdapter.lua")
assert(labLoader, labError)
labLoader()
local Adapter = assert(IG.LABAdapter)

-- PetActionBar and its child table are foreign values. A denied frame is never
-- indexed; an inaccessible child table is never indexed, and the documented
-- global button fallback remains available.
local forbiddenPetBar = setmetatable({}, {
    __index = function() error("PetActionBar indexed while inaccessible") end,
})
deniedObject = forbiddenPetBar
PetActionBar = forbiddenPetBar
PetActionButton1 = { name = "pet-global-fallback" }
Buttons:RefreshPetButtons()
assert(IG.ObservedButtons[PetActionButton1], "global pet-button fallback was skipped")

local inaccessibleButtons = setmetatable({}, {
    __index = function() error("actionButtons indexed without table access") end,
})
deniedTable = inaccessibleButtons
PetActionBar = { actionButtons = inaccessibleButtons }
PetActionButton1 = { name = "pet-table-fallback" }
Buttons:RefreshPetButtons()
assert(IG.ObservedButtons[PetActionButton1], "pet global fallback after denied child table was skipped")
deniedTable = nil
deniedObject = nil
shellQueues = 0

-- AceAddon can be value-accessible while its table is not. Attach must not read
-- GetAddon until the table and consumed method are accessible.
local addonLookups = 0
local aceAddon = setmetatable({}, {
    __index = function(_, key)
        if key == "GetAddon" then error("AceAddon.GetAddon read before CanAccessTable") end
    end,
})
function aceAddon:GetAddon() addonLookups = addonLookups + 1 end
local libStub = {
    GetLibrary = function(_, name)
        if name == "AceAddon-3.0" then return aceAddon end
    end,
}
LibStub = libStub
deniedTable = aceAddon
Buttons:AttachDominosNow(true)
assert(addonLookups == 0, "inaccessible AceAddon table was consumed")
deniedTable = nil

-- A single ConditionalActions index routes shared slot notifications. LAB slot
-- changes must not queue native peers, and zero means LAB-wide invalidation.
Buttons.attached = true
Adapter:Attach()
labButton = {
    _state_type = "action",
    _state_action = 7,
    action = 7,
    UpdateAction = function() end,
}
local buttonList = { labButton }
local library = {
    GetAllButtons = function() return buttonList end,
    RegisterCallback = function() end,
    UnregisterCallback = function() end,
}
Adapter:AttachLibrary(library, true, false)
local labRecord = assert(IG.ObservedButtons[labButton])
assert(labRecord.labSlot == 7 and labRecord.labIdentityRestricted == false)
assert(shellQueues == 1, "provider discovery queued the same shell twice")

local nativeButton = { action = 7 }
local nativeRecord = { button = nativeButton, adapter = "native" }
IG.ObservedButtons[nativeButton] = nativeRecord
Actions:Observe(nativeButton, nativeRecord)

local function clearDirty() observedDirty = {} end
local function dirtyCount(button)
    local count = 0
    for _, dirtyButton in ipairs(observedDirty) do
        if dirtyButton == button then count = count + 1 end
    end
    return count
end

clearDirty()
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", 7)
assert(dirtyCount(labButton) == 1 and dirtyCount(nativeButton) == 0)

-- Accessible empty and unreadable LAB identities both clear their old indexed
-- slot. The old generic action field must not bring that slot back.
labButton._state_type = nil
labButton._state_action = nil
labButton.action = 7
labButton.__updateActionHook(labButton)
clearDirty()
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", 7)
assert(dirtyCount(labButton) == 0, "empty LAB identity retained the prior slot")
assert(resolverFallbackCalls == 0, "empty LAB identity fell back to stale button.action")

labButton._state_type = "action"
labButton._state_action = 8
labButton.__updateActionHook(labButton)
inaccessibleLABIdentity = true
labButton.__updateActionHook(labButton)
assert(labRecord.labIdentityRestricted == true and labRecord.labSlot == nil)
clearDirty()
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", 8)
assert(dirtyCount(labButton) == 0, "restricted LAB identity retained the prior slot")
assert(resolverFallbackCalls == 0, "restricted LAB identity fell back to stale button.action")
inaccessibleLABIdentity = false
labButton._state_action = 9
labButton.__updateActionHook(labButton)
clearDirty()
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", 7)
assert(dirtyCount(labButton) == 0)
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", 9)
assert(dirtyCount(labButton) == 1)

-- Preserve event meaning: zero invalidates only LAB records, negative slots do
-- nothing, and detach/re-attach requires rebuilding the shared index.
clearDirty()
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", "0")
assert(dirtyCount(labButton) == 1 and dirtyCount(nativeButton) == 0)
clearDirty()
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", -1)
assert(#observedDirty == 0)

Actions:Detach()
Adapter:Detach()
assert(Actions:InvalidateSlot(0, "lab") == 0, "detach retained LAB slot membership")
Adapter:Attach()
Adapter:AttachLibrary(library, true, true)
clearDirty()
slotFrame.scripts.OnEvent(slotFrame, "ACTIONBAR_SLOT_CHANGED", 9)
assert(dirtyCount(labButton) == 1, "LAB index was not rebuilt after re-attach")

print("PROVIDER IDENTITY OWNERSHIP TEST PASSED")
