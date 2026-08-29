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
    PendingButtons = setmetatable({}, { __mode = "k" }),
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
function InterruptGlow:MarkButtonDirty(button)
    if self.PendingButtons[button] then return end
    self.PendingButtons[button] = true
    dirtyCalls = dirtyCalls + 1
end
function InterruptGlow:BumpStat() end

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

local resolverLoader, resolverError = loadfile(ROOT .. "/core/ActionResolver.lua")
assert(resolverLoader, resolverError)
resolverLoader()

local queueLoader, queueError = loadfile(ROOT .. "/core/NativeActionQueuePolicy.lua")
assert(queueLoader, queueError)
queueLoader()

local Buttons = InterruptGlow.Buttons
local button = { action = 7 }

-- The potentially mouseover-driven callback performs no action classification.
-- It observes once, invalidates the snapshot, and queues one physical button.
Buttons:OnNativeActionChanged(button)
assert(interruptCalls == 0 and assistedCalls == 0)
assert(actionInfoCalls == 0 and getSpellCalls == 0)
assert(protectedMemberReads == 0)
assert(observeCalls == 1)
assert(dirtyCalls == 1)

local record = assert(InterruptGlow.ObservedButtons[button])
assert(record.actionSnapshotFresh == false)

-- Any number of callbacks before the addon flush remain one queued record.
for _ = 1, 100 do Buttons:OnNativeActionChanged(button) end
assert(interruptCalls == 0 and actionInfoCalls == 0)
assert(observeCalls == 1 and dirtyCalls == 1)

-- The addon-owned reconcile reads the latest action once.
InterruptGlow.PendingButtons[button] = nil
assert(Buttons:ResolveRecord(record) == false)
assert(interruptCalls == 1)
assert(assistedCalls == 0 and actionInfoCalls == 0 and getSpellCalls == 0)
assert(protectedMemberReads == 0)
assert(fallbackCalls == 0)
assert(record.actionSnapshotFresh == true)

-- Interrupt feedback is still queue-only; full identity work happens in the
-- following reconcile and is reused by that reconcile's resolver call.
currentInterrupt = true
Buttons:OnNativeActionChanged(button)
assert(interruptCalls == 1 and dirtyCalls == 2)
InterruptGlow.PendingButtons[button] = nil
local isInterrupt, sourceKind, sourceID, spellID, canonicalSpellID =
    Buttons:ResolveRecord(record)
assert(isInterrupt == true)
assert(sourceKind == "action" and sourceID == 7)
assert(spellID == 1766 and canonicalSpellID == 1766)
assert(interruptCalls == 2 and assistedCalls == 1)
assert(actionInfoCalls == 1 and getSpellCalls == 1)
assert(protectedMemberReads == 0)
assert(fallbackCalls == 0)

-- Critical race: another signal already queued the button, then a later action
-- callback changes its identity. The callback must invalidate before dedupe so
-- the existing dirty pass cannot reuse the old snapshot.
record.actionSnapshotFresh = true
InterruptGlow.PendingButtons[button] = true
currentInterrupt = false
Buttons:OnNativeActionChanged(button)
assert(record.actionSnapshotFresh == false)
assert(dirtyCalls == 2)
InterruptGlow.PendingButtons[button] = nil
assert(Buttons:ResolveRecord(record) == false)
assert(interruptCalls == 3)

-- Empty action state also remains callback-cheap and is resolved in the batch.
button.action = 0
Buttons:OnNativeActionChanged(button)
assert(dirtyCalls == 3)
assert(interruptCalls == 3)
InterruptGlow.PendingButtons[button] = nil
assert(Buttons:ResolveRecord(record) == false)
assert(interruptCalls == 3)
assert(protectedMemberReads == 0)

local policy = assert(InterruptGlow.modules.NativeActionQueuePolicy)
assert(policy.callbackReadsActionAPIs == false)
assert(policy.coalescesPerPhysicalButton == true)
assert(policy.invalidatesBeforeDedupe == true)

print("ACTION RESOLVER QUEUE-ONLY FAST PATH TEST PASSED")
