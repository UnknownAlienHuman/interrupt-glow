local ROOT = arg[1] or "."

_G = _G or _ENV

local readinessAwake = true
local currentInterrupt = true
local failActionInfo = false
local dirtyCalls = 0
local interruptCalls = 0
local actionInfoCalls = 0
local clearCalls = 0

InterruptGlow = {
    DB = { enabled = true, cdText = false },
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
    InterruptRecords = setmetatable({}, { __mode = "k" }),
    AbilityStates = {},
    Usability = {},
    Glow = {},
    Data = {},
}
local IG = InterruptGlow
function IG.CanAccess(_) return true end
function IG:ReadMember(object, key)
    if object == nil then return nil, false end
    return object[key], true
end
function IG:AsNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
end
function IG:BumpStat() end
function IG:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function IG:NeedsReadinessRuntime() return readinessAwake end
function IG:QueueButtonForReconcile(button)
    if self.PendingButtons[button] then return false end
    self.PendingButtons[button] = true
    dirtyCalls = dirtyCalls + 1
    return true
end
function IG:MarkButtonDirty(button)
    if self.ConditionalActions and not self.ConditionalActions:QueueButton(button) then return end
    self:QueueButtonForReconcile(button)
end
function IG.Glow:QueueShell() end
function IG.Glow:AllowOverlayAccessRetry() return true end
function IG.Glow:ClearRecord(record)
    clearCalls = clearCalls + 1
    record.visualVisible = false
end
function IG.Data:GetCanonicalSpellID(spellID)
    if spellID == 1766 then return 1766 end
end
function IG.Data:LearnRuntimeInterrupt(spellID) return spellID end

C_ActionBar = {
    IsInterruptAction = function(slot)
        assert(slot == 7)
        interruptCalls = interruptCalls + 1
        return currentInterrupt
    end,
    IsAssistedCombatAction = function() return false end,
    GetSpell = function() return 1766 end,
}
function GetActionInfo()
    actionInfoCalls = actionInfoCalls + 1
    if failActionInfo then error("forced action snapshot error") end
    return "spell", 1766, nil
end

local buttonsLoader, buttonsError = loadfile(ROOT .. "/core/Buttons.lua")
assert(buttonsLoader, buttonsError)
buttonsLoader()
local resolverLoader, resolverError = loadfile(ROOT .. "/core/ActionResolver.lua")
assert(resolverLoader, resolverError)
resolverLoader()
local actionsLoader, actionsError = loadfile(ROOT .. "/core/ConditionalActions.lua")
assert(actionsLoader, actionsError)
actionsLoader()

local Buttons = assert(IG.Buttons)
local Actions = assert(IG.ConditionalActions)
Buttons.attached = true
Buttons.nativeAttached = true
local button = { action = 7 }
local record = {
    button = button,
    adapter = "native",
    isInterrupt = true,
    overlay = {},
    visualVisible = true,
}
IG.ObservedButtons[button] = record
Actions:Observe(button, record)

-- The callback invalidates before queue dedupe, hides the old visual, and
-- leaves all action APIs for the addon-owned reconcile.
Buttons:OnNativeActionChanged(button)
assert(record.conditionalIdentityPending == true and record.visualVisible == false)
assert(clearCalls == 1 and dirtyCalls == 1)
assert(interruptCalls == 0 and actionInfoCalls == 0)
for _ = 1, 100 do Buttons:OnNativeActionChanged(button) end
assert(dirtyCalls == 1 and interruptCalls == 0 and actionInfoCalls == 0)

-- If resolution errors, the pending visual guard survives subsequent refreshes.
IG.PendingButtons[button] = nil
failActionInfo = true
local ok, err = pcall(IG.ActionResolver.ResolveRecord, IG.ActionResolver, record)
assert(ok == false and tostring(err):find("forced action snapshot error", 1, true))
assert(record.conditionalIdentityPending == true and record.visualVisible == false)

-- A successful reconcile uses the latest identity once, then clears the guard.
failActionInfo = false
local isInterrupt, sourceKind, sourceID, spellID, canonicalSpellID =
    IG.ActionResolver:ResolveRecord(record)
assert(isInterrupt == true)
assert(sourceKind == "action" and sourceID == 7)
assert(spellID == 1766 and canonicalSpellID == 1766)
assert(interruptCalls == 2 and actionInfoCalls == 2)
Actions:Reconciled(record)
assert(record.conditionalIdentityPending == false)
assert(clearCalls == 1)

print("CONDITIONAL ACTIVE IDENTITY GUARD TEST PASSED")
