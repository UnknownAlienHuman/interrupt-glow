local ROOT = arg[1] or "."

_G = _G or _ENV

local currentSpecID = 258
local knownFamilies = {}
PlayerUtil = { GetCurrentSpecID = function() return currentSpecID end }
C_SpellBook = {
    IsSpellKnownOrInSpellBook = function(spellID) return knownFamilies[spellID] == true end,
    FindBaseSpellByID = function(spellID) return spellID end,
    FindSpellOverrideByID = function(spellID) return spellID end,
}
Constants = { SpellCooldownConsts = { GLOBAL_RECOVERY_CATEGORY = 133 } }
C_ActionBar = { IsInterruptAction = function() return false end }

InterruptGlow = {
    modules = {},
    DB = { enabled = true, cdm = true },
    ObservedButtons = {},
    PendingButtons = {},
    AbilityStates = {},
    Stats = {},
}
local IG = InterruptGlow
function IG:RegisterModule(name, module) self.modules[name] = module end
function IG.CanAccess(_) return true end
function IG:ReadMember(object, key)
    if object == nil then return nil, false end
    return object[key], true
end
function IG:AsNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
end
function IG:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function IG:BumpStat() end
function IG:MarkAllButtonsDirty() self.allButtonsDirty = (self.allButtonsDirty or 0) + 1 end
function IG:MarkButtonDirty() end

local function load(relative)
    local loader, loadError = loadfile(ROOT .. "/" .. relative)
    assert(loader, loadError)
    loader()
end
load("core/Data.lua")
load("core/ActionResolver.lua")
load("core/Buttons.lua")

local Data = assert(IG.Data)
local Buttons = assert(IG.Buttons)
local actionRecord = { name = "action", adapter = "native", button = { action = 7 } }
local secondaryRecord = { name = "secondary", adapter = "cdm", button = {} }
IG.ObservedButtons[secondaryRecord.button] = secondaryRecord
IG.ObservedButtons[actionRecord.button] = actionRecord
local reconcileOrder = {}
local cdmRefreshCalls = 0
IG.CDM = { attached = true }
function IG.CDM:ObserveExistingItems()
    assert(Data.runtimeInterrupts[9001] == 9001, "secondary refresh ran before action proof")
    cdmRefreshCalls = cdmRefreshCalls + 1
end
function Buttons:ReconcileRecord(record)
    reconcileOrder[#reconcileOrder + 1] = record.name
    if record.name == "action" then
        assert(Data:LearnRuntimeInterrupt(9001) == 9001)
    elseif record.name == "secondary" then
        assert(cdmRefreshCalls == 1, "secondary copy reconciled before CDM refresh")
        assert(Data.runtimeInterrupts[9001] == 9001, "secondary copy preceded action proof")
    end
end

-- Actual Buttons owner classifies action surfaces first, refreshes CDM copies,
-- then reconciles secondary direct spell sources.
Buttons:ReconcileAll()
assert(reconcileOrder[1] == "action" and reconcileOrder[2] == "secondary")
assert(cdmRefreshCalls == 1)
assert(IG.allButtonsDirty == 1)

-- New runtime proof invalidates negative aliases and requests propagation once.
assert(Data:LearnRuntimeInterrupt(9002) == 9002)
assert(IG.allButtonsDirty == 2)
assert(Data:LearnRuntimeInterrupt(9002) == 9002)
assert(IG.allButtonsDirty == 2, "repeat proof scheduled duplicate reconciliation")

-- Unknown ordinary IDs enter a bounded negative cache. A proven family clears
-- those results and becomes positive on the next match check.
assert(Data:MatchesCurrentInterrupt(8888) == false)
assert(Data.negativeCooldownSpellMatches[8888] == true)
assert(Data:LearnRuntimeInterrupt(8888) == 8888)
assert(Data.negativeCooldownSpellMatches[8888] == nil)
assert(Data:MatchesCurrentInterrupt(8888) == true)

for spellID = 10001, 10128 do
    assert(Data:MatchesCurrentInterrupt(spellID) == false)
end
assert(Data.negativeCooldownSpellMatchCount == 128)
assert(Data:MatchesCurrentInterrupt(10129) == false)
assert(Data.negativeCooldownSpellMatchCount == 1)
assert(Data.negativeCooldownSpellMatches[10129] == true)
assert(Data.negativeCooldownSpellMatches[10001] == nil)

-- A registry rebuild invalidates both learned action proof and negatives.
Data:RefreshActiveSpec()
assert(next(Data.runtimeInterrupts) == nil)
assert(next(Data.negativeCooldownSpellMatches) == nil)
assert(Data.negativeCooldownSpellMatchCount == 0)

print("RUNTIME INTERRUPT ORDER AND CACHE TEST PASSED")
