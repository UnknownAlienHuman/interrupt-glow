local ROOT = arg[1] or "."
_G = _G or _ENV

local actionQueries = 0
local actionInfoQueries = 0
local currentInterrupt = { [7] = true }
local spellID = 1766

InterruptGlow = {
    DB = { enabled = true, cdText = false, cdm = false },
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
    InterruptRecords = setmetatable({}, { __mode = "k" }),
    AbilityStates = {},
    Glow = {},
    Data = {},
}
local IG = InterruptGlow
function IG.CanAccess() return true end
function IG:CanAccessTable(value) return type(value) == "table" end
function IG:ReadMember(object, key)
    if object == nil then return nil, false end
    return object[key], true
end
function IG:AsNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
end
function IG:BumpStat() end
function IG:MarkCooldownDirty() end
function IG:MarkCastDirty() end
function IG:Now() return 100 end
function IG:IsInCombat() return false end
function IG.Glow:QueueShell() end
function IG.Glow:EnsureInterruptVisuals() end
function IG.Glow:ApplyStoredInterruptibilityToRecord() return true end
function IG.Glow:RefreshRecord() end
function IG.Glow:ClearRecord() end
function IG.Data:GetCanonicalSpellID(id)
    if id == 1766 then return 1766 end
end
function IG.Data:LearnRuntimeInterrupt(id) return id end

C_ActionBar = {
    IsInterruptAction = function(slot)
        actionQueries = actionQueries + 1
        return currentInterrupt[slot] == true
    end,
    IsAssistedCombatAction = function() return false end,
    GetSpell = function() return spellID end,
    IsUsableAction = function() return true, false end,
}
function GetActionInfo(slot)
    actionInfoQueries = actionInfoQueries + 1
    return "spell", spellID, nil
end

local buttonsLoader, buttonsError = loadfile(ROOT .. "/core/Buttons.lua")
assert(buttonsLoader, buttonsError)
buttonsLoader()
local resolverLoader, resolverError = loadfile(ROOT .. "/core/ActionResolver.lua")
assert(resolverLoader, resolverError)
resolverLoader()

local Buttons = assert(IG.Buttons)
local Resolver = assert(IG.ActionResolver)
local button = { action = 7 }
local record = {
    button = button,
    adapter = "lab",
    labIdentityRestricted = false,
    labStateType = "action",
    labStateAction = 7,
    labSlot = 7,
    ready = false,
    isInterrupt = false,
}
IG.ObservedButtons[button] = record

-- A valid cached LAB action resolves through its authoritative secure slot.
local isInterrupt, sourceKind, sourceID, resolvedSpellID = Resolver:ResolveRecord(record)
assert(isInterrupt == true and sourceKind == "action" and sourceID == 7)
assert(resolvedSpellID == 1766 and actionQueries == 1 and actionInfoQueries == 1)
Buttons:ReconcileRecord(record)
assert(record.isInterrupt == true and record.sourceKind == "action")

-- LAB switches to a direct spell while its generic `action` field still names
-- the previous interrupt slot. The cached spell identity wins without an
-- action-bar query.
local actionQueriesBeforeSpell = actionQueries
local actionInfoBeforeSpell = actionInfoQueries
record.labStateType = "spell"
record.labStateAction = 1766
record.labSlot = nil
local directInterrupt, directKind, directSource, directSpell = Resolver:ResolveRecord(record)
assert(directInterrupt == true and directKind == "spell")
assert(directSource == 1766 and directSpell == 1766)
assert(actionQueries == actionQueriesBeforeSpell and actionInfoQueries == actionInfoBeforeSpell)
Buttons:ReconcileRecord(record)
assert(record.isInterrupt == true and record.sourceKind == "spell")

local function AssertNoActionBinding(message)
    local beforeQueries = actionQueries
    local beforeActionInfo = actionInfoQueries
    assert(Resolver:ResolveRecord(record) == false, message)
    assert(actionQueries == beforeQueries and actionInfoQueries == beforeActionInfo,
        "non-action LAB identity queried the stale action slot")
    Buttons:ReconcileRecord(record)
    assert(record.isInterrupt == false and IG.InterruptRecords[record] == nil,
        "non-action LAB identity retained its interrupt binding")
end

-- Accessible nil/nil is an authoritative empty identity. It cannot revive the
-- valid old action field, and reconciliation removes the existing binding.
record.labIdentityRestricted = false
record.labStateType = nil
record.labStateAction = nil
record.labSlot = nil
AssertNoActionBinding("empty LAB identity revived old action")

-- An inaccessible identity and an explicitly non-action state also fail closed.
record.labIdentityRestricted = true
AssertNoActionBinding("restricted LAB identity revived old action")
record.labIdentityRestricted = false
record.labStateType = "macro"
record.labStateAction = 42
AssertNoActionBinding("non-action LAB state revived old action")

-- A later readable direct spell recovers, then a readable action state again
-- uses its cached slot rather than the generic field.
record.labStateType = "spell"
record.labStateAction = "1766"
record.labSlot = nil
local recovered, recoveredKind = Resolver:ResolveRecord(record)
assert(recovered == true and recoveredKind == "spell")
Buttons:ReconcileRecord(record)
assert(record.isInterrupt == true and record.sourceKind == "spell")

record.labStateType = "action"
record.labStateAction = "7"
record.labSlot = 7
local actionAgain, actionAgainKind, actionAgainSlot = Resolver:ResolveRecord(record)
assert(actionAgain == true and actionAgainKind == "action" and actionAgainSlot == 7)

-- Full reconciliation still seeds action records before refreshing secondary
-- direct-spell/CDM copies.
local actionSeed = {
    button = {}, adapter = "lab", labIdentityRestricted = false,
    labStateType = "action", labStateAction = 7, labSlot = 7, label = "lab-action",
}
local spellSeed = {
    button = {}, adapter = "lab", labIdentityRestricted = false,
    labStateType = "spell", labStateAction = 1766, label = "lab-spell",
}
local cdmSeed = { button = {}, adapter = "cdm", label = "cdm" }
IG.ObservedButtons = setmetatable({
    [actionSeed.button] = actionSeed,
    [spellSeed.button] = spellSeed,
    [cdmSeed.button] = cdmSeed,
}, { __mode = "k" })
IG.DB.cdm = true
local seedOrder = {}
IG.CDM = {
    attached = true,
    ObserveExistingItems = function() table.insert(seedOrder, "cdm-seed") end,
}
function Buttons:ReconcileRecord(seedRecord)
    seedOrder[#seedOrder + 1] = seedRecord.label
end
Buttons:ReconcileAll()
assert(seedOrder[1] == "lab-action", "LAB action proof was not seeded first")
assert(seedOrder[2] == "cdm-seed", "CDM pool was not refreshed after action proof")
local sawLABSpell = false
for index = 3, #seedOrder do
    if seedOrder[index] == "lab-spell" then sawLABSpell = true end
end
assert(sawLABSpell, "direct LAB spell copy was omitted from secondary reconciliation")

print("LAB SOURCE BINDING TEST PASSED")
