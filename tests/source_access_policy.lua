local ROOT = arg[1] or "."

_G = _G or _ENV

local secretValue = {}
local observeCalls = 0
local resolveCalls = 0
local petCalls = 0
local cdmMethodCalls = 0

local petSpellID = 1766
local petRangeCheck = secretValue
local petInRange = secretValue

function GetPetActionInfo(slot)
    assert(slot == 3)
    petCalls = petCalls + 1
    return "Kick", 1, false, false, false, false, petSpellID, petRangeCheck, petInRange
end

InterruptGlow = {
    modules = {},
    DB = { cdm = true },
    AbilityStates = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    Buttons = {},
    Cooldown = {},
    Data = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= secretValue end
function InterruptGlow:ReadMember(container, key)
    if not self.CanAccess(container) or container == nil then return nil, false end
    local ok, value = pcall(function() return container[key] end)
    if not ok or not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:BumpStat() end
function InterruptGlow:MarkCooldownDirty() return true end
function InterruptGlow.Data:GetCanonicalSpellID(spellID, sourceKind)
    if spellID == 1766 and (sourceKind == "pet" or sourceKind == "spell") then
        return 1766
    end
end

function InterruptGlow.Buttons:ObserveButton(button)
    observeCalls = observeCalls + 1
    local record = { button = button }
    InterruptGlow.ObservedButtons[button] = record
    return record
end
function InterruptGlow.Buttons:ResolveRecord()
    resolveCalls = resolveCalls + 1
    return true
end
function InterruptGlow.Buttons:ResolvePet() error("legacy pet resolver must be replaced") end
function InterruptGlow.Buttons:ResolveCDM() error("legacy CDM resolver must be replaced") end
function InterruptGlow.Buttons:RebuildAbilitySource() return false end
function InterruptGlow.Cooldown:RefreshAbility() return false end
function InterruptGlow.Cooldown:RefreshAll() return false end

local loader, loadError = loadfile(ROOT .. "/core/BoundSourcePolicy.lua")
assert(loader, loadError)
loader()

local Buttons = InterruptGlow.Buttons

-- Inaccessible observed objects are rejected before weak-table keying or the
-- legacy resolver/observer can touch them.
assert(Buttons:ObserveButton(secretValue) == nil)
assert(observeCalls == 0)
assert(Buttons:ResolveRecord({ button = secretValue }) == false)
assert(resolveCalls == 0)

local ordinaryButton = {}
assert(Buttons:ObserveButton(ordinaryButton) ~= nil)
assert(observeCalls == 1)
assert(Buttons:ResolveRecord({ button = ordinaryButton }) == true)
assert(resolveCalls == 1)

-- Only pet return 7 crosses the pcall boundary. Secret range fields returned
-- after spellID cannot poison classification because they are never captured.
local isInterrupt, sourceKind, sourceID, spellID, canonicalSpellID =
    Buttons:ResolvePet({ petSlot = 3 })
assert(isInterrupt == true)
assert(sourceKind == "pet" and sourceID == 3)
assert(spellID == 1766 and canonicalSpellID == 1766)
assert(petCalls == 1)

petSpellID = secretValue
assert(Buttons:ResolvePet({ petSlot = 3 }) == false)
assert(petCalls == 2)
petSpellID = 1766

local cdmButton = {
    GetBaseSpellID = function()
        cdmMethodCalls = cdmMethodCalls + 1
        return 1766
    end,
}
isInterrupt, sourceKind, sourceID, spellID, canonicalSpellID =
    Buttons:ResolveCDM({ button = cdmButton })
assert(isInterrupt == true)
assert(sourceKind == "spell" and sourceID == 1766)
assert(spellID == 1766 and canonicalSpellID == 1766)
assert(cdmMethodCalls == 1)

cdmButton.GetBaseSpellID = secretValue
assert(Buttons:ResolveCDM({ button = cdmButton }) == false)
assert(cdmMethodCalls == 1)
assert(Buttons:ResolveCDM({ button = secretValue }) == false)

local policy = assert(InterruptGlow.modules.BoundSourcePolicy)
assert(policy.accessGatesObservedButtons == true)
assert(policy.selectivePetSpellRead == true)
assert(policy.accessGatesCDMFrameMethods == true)

print("SOURCE ACCESS POLICY TEST PASSED")
