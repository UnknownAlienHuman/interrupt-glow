local ROOT = arg[1] or "."

_G = _G or _ENV

local dirtyCalls = 0
local memberReads = 0
local interruptCalls = 0
local assistedCalls = 0
local actionInfoCalls = 0
local getSpellCalls = 0
local currentInterrupt = false
local currentAssisted = false
local currentSpellID = 1766

InterruptGlowDB = { enabled = true, cdText = false }
InterruptGlow = {
    DB = InterruptGlowDB,
    modules = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
    InterruptRecords = setmetatable({}, { __mode = "k" }),
    AbilityStates = {},
    Glow = {},
    Data = {},
}
local IG = InterruptGlow
function IG:RegisterModule(name, module) self.modules[name] = module end
function IG.CanAccess(_) return true end
function IG:ReadMember(object, key)
    memberReads = memberReads + 1
    if object == nil then return nil, false end
    return object[key], true
end
function IG:AsNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
end
function IG:BumpStat() end
function IG:MarkButtonDirty(button)
    if self.PendingButtons[button] then return end
    self.PendingButtons[button] = true
    dirtyCalls = dirtyCalls + 1
end
function IG.Glow:QueueShell() end
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
    IsAssistedCombatAction = function(slot)
        assert(slot == 7)
        assistedCalls = assistedCalls + 1
        return currentAssisted
    end,
    GetSpell = function(slot)
        assert(slot == 7)
        getSpellCalls = getSpellCalls + 1
        return currentSpellID
    end,
}
function GetActionInfo(slot)
    assert(slot == 7)
    actionInfoCalls = actionInfoCalls + 1
    return "macro", 42, "spell"
end

local buttonsLoader, buttonsError = loadfile(ROOT .. "/core/Buttons.lua")
assert(buttonsLoader, buttonsError)
buttonsLoader()
local resolverLoader, resolverError = loadfile(ROOT .. "/core/ActionResolver.lua")
assert(resolverLoader, resolverError)
resolverLoader()

local Buttons = assert(IG.Buttons)
Buttons.attached = true
Buttons.nativeAttached = true
local button = { action = 7 }

-- The native callback only observes and queues. It does not inspect action
-- identity, even when many callbacks arrive before the addon flushes its queue.
Buttons:OnNativeActionChanged(button)
local record = assert(IG.ObservedButtons[button])
assert(record.adapter == "native")
assert(interruptCalls == 0 and assistedCalls == 0)
assert(actionInfoCalls == 0 and getSpellCalls == 0 and memberReads == 0)
assert(dirtyCalls == 1 and IG.PendingButtons[button] == true)

for _ = 1, 100 do Buttons:OnNativeActionChanged(button) end
assert(interruptCalls == 0 and actionInfoCalls == 0)
assert(dirtyCalls == 1, "callbacks did not coalesce to one pending button")

-- One addon-owned resolution reads the latest interrupt classification. A
-- confirmed non-interrupt short-circuits before spell/action identity APIs.
IG.PendingButtons[button] = nil
assert(IG.ActionResolver:ResolveRecord(record) == false)
assert(interruptCalls == 1)
assert(assistedCalls == 0 and actionInfoCalls == 0 and getSpellCalls == 0)

-- The next burst still queues only; the following reconciliation performs one
-- complete classification against the latest action state.
currentInterrupt = true
Buttons:OnNativeActionChanged(button)
for _ = 1, 100 do Buttons:OnNativeActionChanged(button) end
assert(interruptCalls == 1 and actionInfoCalls == 0)
assert(dirtyCalls == 2)
IG.PendingButtons[button] = nil
local isInterrupt, sourceKind, sourceID, spellID, canonicalSpellID =
    IG.ActionResolver:ResolveRecord(record)
assert(isInterrupt == true)
assert(sourceKind == "action" and sourceID == 7)
assert(spellID == 1766 and canonicalSpellID == 1766)
assert(interruptCalls == 2 and assistedCalls == 1)
assert(actionInfoCalls == 1 and getSpellCalls == 1)

-- An empty action remains callback-cheap and resolves to no interrupt.
button.action = 0
Buttons:OnNativeActionChanged(button)
assert(interruptCalls == 2 and actionInfoCalls == 1)
IG.PendingButtons[button] = nil
assert(IG.ActionResolver:ResolveRecord(record) == false)
assert(interruptCalls == 2)

-- Provider methods are read through the guarded accessor and invoked behind a
-- fail-closed boundary; a foreign throwing spell getter is not allowed to abort
-- the reconciliation pass.
local throwingDirectRecord = {
    adapter = "lab",
    button = { GetSpellId = function() error("foreign method failed") end },
}
assert(IG.ActionResolver:ResolveRecord(throwingDirectRecord) == false)

print("ACTION RESOLVER QUEUE-ONLY FAST PATH TEST PASSED")
