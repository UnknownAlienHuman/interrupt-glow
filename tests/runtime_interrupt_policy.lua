local ROOT = arg[1] or "."

_G = _G or _ENV

local allButtonsDirty = 0
local reconcileOrder = {}
local refreshCalls = 0
local knownFamilies = {}

InterruptGlow = {
    modules = {},
    ObservedButtons = {},
    Data = {
        runtimeInterrupts = { [8000] = 8000 },
        activeInterrupts = {},
        cooldownSpellMatchCache = {},
    },
    Buttons = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:ReadMember(object, key)
    if object == nil then return nil, false end
    return object[key], true
end
function InterruptGlow:AsNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
end
function InterruptGlow:MarkAllButtonsDirty() allButtonsDirty = allButtonsDirty + 1 end
function InterruptGlow:BumpStat() end

function InterruptGlow.Data:RefreshActiveSpec()
    refreshCalls = refreshCalls + 1
    assert(next(self.runtimeInterrupts) == nil, "runtime proof was not cleared before registry rebuild")
    self.cooldownSpellMatchCache = {}
    return 258, false
end
function InterruptGlow.Data:LearnRuntimeInterrupt(spellID)
    self.runtimeInterrupts[spellID] = spellID
    return spellID
end
function InterruptGlow.Data:GetCanonicalSpellID(spellID)
    if self.activeInterrupts[spellID] then return spellID end
    if self.runtimeInterrupts[spellID] and knownFamilies[spellID] then return spellID end
end
function InterruptGlow.Data:MatchesCurrentInterrupt(spellID)
    return self.runtimeInterrupts[spellID] ~= nil
end

function InterruptGlow.Buttons:ReconcileRecord(record)
    reconcileOrder[#reconcileOrder + 1] = record.name
    if record.name == "action" then
        InterruptGlow.Data:LearnRuntimeInterrupt(9001)
    elseif record.name == "secondary" then
        assert(InterruptGlow.Data.runtimeInterrupts[9001] == 9001,
            "secondary copy reconciled before authoritative action proof")
    end
end
function InterruptGlow.Buttons:ReconcileAll()
    error("base ReconcileAll should be replaced")
end

local actionRecord = {
    name = "action",
    adapter = "native",
    button = { action = 7 },
}
local secondaryRecord = {
    name = "secondary",
    adapter = "cdm",
    button = {},
}
InterruptGlow.ObservedButtons.secondary = secondaryRecord
InterruptGlow.ObservedButtons.action = actionRecord

local loader, loadError = loadfile(ROOT .. "/core/RuntimeInterruptPolicy.lua")
assert(loader, loadError)
loader()

local Data = InterruptGlow.Data
local Buttons = InterruptGlow.Buttons

local revisionBefore = Data.runtimeProofRevision or 0
local specID, changed = Data:RefreshActiveSpec()
assert(specID == 258 and changed == false)
assert(refreshCalls == 1)
assert((Data.runtimeProofRevision or 0) == revisionBefore + 1)

Buttons:ReconcileAll()
assert(reconcileOrder[1] == "action")
assert(reconcileOrder[2] == "secondary")
assert(Buttons.runtimeInterruptSeedPass == false)
assert(allButtonsDirty == 0, "seed pass scheduled a redundant full rebuild")

-- A new runtime family learned from an ordinary single-button reconcile must
-- rebind already-observed direct/CDM copies exactly once on the next frame.
Data:LearnRuntimeInterrupt(9002)
assert(allButtonsDirty == 1)
Data:LearnRuntimeInterrupt(9002)
assert(allButtonsDirty == 1, "existing runtime proof scheduled duplicate full rebuild")

-- Raw runtime map presence is not sufficient after configuration churn.
Data.runtimeInterrupts[7777] = 7777
Data.cooldownSpellMatchCache[7777] = nil
knownFamilies[7777] = nil
assert(Data:MatchesCurrentInterrupt(7777) == false)
knownFamilies[7777] = true
Data.cooldownSpellMatchCache[7777] = nil
assert(Data:MatchesCurrentInterrupt(7777) == true)

local policy = assert(InterruptGlow.modules.RuntimeInterruptPolicy)
assert(policy.clearsProofOnRegistryRebuild == true)
assert(policy.actionSlotsSeedBeforeSecondaryCopies == true)
assert(policy.propagatesNewRuntimeFamilies == true)
assert(policy.revalidatesCooldownEventMatches == true)

print("RUNTIME INTERRUPT POLICY TEST PASSED")
