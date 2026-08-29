local ROOT = arg[1] or "."

_G = _G or _ENV

local dirtyCalls = 0
local fallbackCalls = 0
local interruptCalls = 0
local assistedCalls = 0
local actionInfoCalls = 0
local getSpellCalls = 0
local protectedMemberReads = 0
local observeCalls = 0

local currentInterrupt = false
local currentAssisted = false
local currentActionType = "macro"
local currentActionID = 42
local currentActionSubType = "spell"
local currentSpellID = 1766

InterruptGlow = {
    DB = { debug = false },
    profileCountersEnabled = false,
    modules = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    Buttons = {},
    Data = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:ReadMember(object, key)
    protectedMemberReads = protectedMemberReads + 1
    if object == nil then return nil, false end
    return object[key], true
end
function InterruptGlow:AsNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
end
function InterruptGlow:MarkButtonDirty() dirtyCalls = dirtyCalls + 1 end
function InterruptGlow:BumpStat() error("dormant hot-path counter was called") end

function InterruptGlow.Data:GetCanonicalSpellID(spellID)
    if spellID == 1766 then return 1766 end
end
function InterruptGlow.Data:LearnRuntimeInterrupt(spellID) return spellID end

function InterruptGlow.Buttons:ResolveRecord()
    fallbackCalls = fallbackCalls + 1
    return false
end
function InterruptGlow.Buttons:ObserveButton(button, adapter)
    observeCalls = observeCalls + 1
    local record = InterruptGlow.ObservedButtons[button]
    if not record then
        record = { button = button, adapter = adapter }
        InterruptGlow.ObservedButtons[button] = record
    end
    return record
end

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
    return currentActionType, currentActionID, currentActionSubType
end

local loader, loadError = loadfile(ROOT .. "/core/ActionResolver.lua")
assert(loader, loadError)
loader()

local Buttons = InterruptGlow.Buttons
local button = { action = 7 }

-- Friendly/non-interrupt macro branch: one IsInterruptAction call only. This is
-- the dominant mouseover stress path from the original CPU/FPS complaint.
Buttons:OnNativeActionChanged(button)
assert(interruptCalls == 1)
assert(assistedCalls == 0)
assert(actionInfoCalls == 0)
assert(getSpellCalls == 0)
assert(protectedMemberReads == 0, "native slot used protected generic member reads")
assert(observeCalls == 1)
assert(dirtyCalls == 1)

-- Repeated identical forced feedback does not observe again, call diagnostics,
-- read full identity, or wake the dirty worker.
Buttons:OnNativeActionChanged(button)
assert(interruptCalls == 2)
assert(assistedCalls == 0 and actionInfoCalls == 0 and getSpellCalls == 0)
assert(protectedMemberReads == 0)
assert(observeCalls == 1)
assert(dirtyCalls == 1)

-- Interrupt branch pays the full identity cost once and stores the resolved
-- spell for the next-frame reconcile.
currentInterrupt = true
Buttons:OnNativeActionChanged(button)
assert(interruptCalls == 3)
assert(assistedCalls == 1)
assert(actionInfoCalls == 1)
assert(getSpellCalls == 1)
assert(protectedMemberReads == 0)
assert(observeCalls == 1)
assert(dirtyCalls == 2)

local record = assert(InterruptGlow.ObservedButtons[button])
local isInterrupt, sourceKind, sourceID, spellID, canonicalSpellID =
    Buttons:ResolveRecord(record)
assert(isInterrupt == true)
assert(sourceKind == "action" and sourceID == 7)
assert(spellID == 1766 and canonicalSpellID == 1766)
assert(interruptCalls == 3 and assistedCalls == 1)
assert(actionInfoCalls == 1 and getSpellCalls == 1)
assert(protectedMemberReads == 0)
assert(fallbackCalls == 0, "fresh native snapshot was re-read through the base resolver")

-- Returning to the non-interrupt branch is again classification-only.
currentInterrupt = false
Buttons:OnNativeActionChanged(button)
assert(interruptCalls == 4)
assert(assistedCalls == 1 and actionInfoCalls == 1 and getSpellCalls == 1)
assert(protectedMemberReads == 0)
assert(observeCalls == 1)
assert(dirtyCalls == 3)

-- Empty buttons normalize once instead of waking on every forced update.
button.action = 0
Buttons:OnNativeActionChanged(button)
assert(dirtyCalls == 4)
Buttons:OnNativeActionChanged(button)
assert(dirtyCalls == 4)
assert(interruptCalls == 4)
assert(protectedMemberReads == 0)
assert(observeCalls == 1)

print("ACTION RESOLVER FAST PATH TEST PASSED")
