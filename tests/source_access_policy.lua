local ROOT = arg[1] or "."

_G = _G or _ENV

local secretFrame = {}
local secretSpell = {}
local weakMapAccesses = 0
local observeDirtyCalls = 0
local petCalls = 0

local observed = setmetatable({}, {
    __index = function()
        weakMapAccesses = weakMapAccesses + 1
    end,
    __newindex = function()
        weakMapAccesses = weakMapAccesses + 1
    end,
})
InterruptGlow = {
    DB = { enabled = true, cdm = true },
    modules = {},
    ObservedButtons = observed,
    PendingButtons = setmetatable({}, { __mode = "k" }),
    AbilityStates = {},
    Data = {},
}
function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= secretFrame and value ~= secretSpell end
function InterruptGlow.CanAccessTable(value)
    return InterruptGlow.CanAccess(value) and type(value) == "table"
end
function InterruptGlow:ReadMember(object, key)
    if not self.CanAccess(object) or object == nil then return nil, false end
    local value = object[key]
    if not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:AsNumber(value) return type(value) == "number" and value or nil end
function InterruptGlow:BumpStat() end
function InterruptGlow:MarkButtonDirty() observeDirtyCalls = observeDirtyCalls + 1 end
function InterruptGlow.Data:GetCanonicalSpellID(spellID)
    if spellID == 1766 then return 1766 end
end
function GetPetActionInfo(slot)
    assert(slot == 3)
    petCalls = petCalls + 1
    return "Kick", nil, false, false, false, false, petSpell
end

local buttonsLoader, buttonsError = loadfile(ROOT .. "/core/Buttons.lua")
assert(buttonsLoader, buttonsError)
buttonsLoader()
local resolverLoader, resolverError = loadfile(ROOT .. "/core/ActionResolver.lua")
assert(resolverLoader, resolverError)
resolverLoader()

local Buttons = assert(InterruptGlow.Buttons)

-- An inaccessible provider frame must be rejected before it becomes a weak
-- table key, regardless of which integration calls the public observer.
assert(Buttons:ObserveButton(secretFrame) == nil)
assert(weakMapAccesses == 0, "inaccessible frame was indexed in ObservedButtons")
assert(observeDirtyCalls == 0)
assert(Buttons:ResolveRecord({ button = secretFrame }) == false)
assert(weakMapAccesses == 0)

-- Pet API results pass through a guarded source boundary. Inaccessible spell
-- identity cannot be sent into data classification.
local secretPetResult = { petSlot = 3 }
assert(Buttons:ResolvePet(secretPetResult) == false)
assert(petCalls == 1)

-- An ordinary frame is observed, and only its NeverSecret pet spell identity
-- is allowed to resolve as a current interrupt.
petSpell = 1766
local petButton = { petSlot = 3 }
local result, sourceKind, sourceID, spellID, canonicalSpellID = Buttons:ResolvePet(petButton)
assert(result == true)
assert(sourceKind == "pet" and sourceID == 3)
assert(spellID == 1766 and canonicalSpellID == 1766)
assert(petCalls == 2)

-- Stored CDM identity resolves without rereading the pooled frame object.
local cdmButton = {}
local cdmRecord = { adapter = "cdm", cdmCanonicalSpellID = 1766 }
result, sourceKind, sourceID, spellID, canonicalSpellID = Buttons:ResolveCDM(cdmRecord)
assert(result == true)
assert(sourceKind == "spell" and sourceID == 1766)
assert(spellID == 1766 and canonicalSpellID == 1766)
assert(weakMapAccesses == 0)

print("SOURCE ACCESS BOUNDARY TEST PASSED")
