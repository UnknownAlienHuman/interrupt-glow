local ROOT = arg[1] or "."

_G = _G or _ENV

local allButtonsDirty = 0
local reconcileOrder = {}
local refreshCalls = 0
local cdmRefreshCalls = 0
local knownFamilies = {}

InterruptGlow = {
    modules = {},
    DB = { cdm = true },
    ObservedButtons = {},
    Data = {
        runtimeInterrupts = { [8000] = 8000 },
        activeInterrupts = {},
        cooldownSpellMatchCache = {},
    },
    Buttons = {},
    CDM = { attached = true },
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
    self.cooldownSpellMatchCache[spellID] = true
    return spellID
end
function InterruptGlow.Data:GetCanonicalSpellID(spellID)
    if self.activeInterrupts[spellID] then return spellID end
    if self.runtimeInterrupts[spellID] and knownFamilies[spellID] then return spellID end
end
function InterruptGlow.Data:MatchesCurrentInterrupt(spellID)
    return self.runtimeInterrupts[spellID] ~= nil
end

function InterruptGlow.CDM:ObserveExistingItems()
    assert(InterruptGlow.Data.runtimeInterrupts[9001] == 9001,
        "CDM identities refreshed before authoritative action proof")
    cdmRefreshCalls = cdmRefreshCalls + 1
end

function InterruptGlow.Buttons:ReconcileRecord(record)
    reconcileOrder[#reconcileOrder + 1] = record.name
    if record.name == "action" then
        InterruptGlow.Data:LearnRuntimeInterrupt(9001)
    elseif record.name == "secondary" then
        assert(cdmRefreshCalls == 1,
            "secondary copy reconciled before post-action CDM refresh")
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
assert(Data.negativeCooldownSpellMatchCount == 0)

Buttons:ReconcileAll()
assert(reconcileOrder[1] == "action")
assert(reconcileOrder[2] == "secondary")
assert(cdmRefreshCalls == 1)
assert(Buttons.runtimeInterruptSeedPass == nil,
    "mutable seed state can remain stuck after a Lua error")
assert(allButtonsDirty == 1,
    "new runtime proof did not schedule the bounded propagation pass")

-- A new runtime family learned from an ordinary single-button reconcile must
-- rebind already-observed direct/CDM copies exactly once on the next frame.
Data:LearnRuntimeInterrupt(9002)
assert(allButtonsDirty == 2)
Data:LearnRuntimeInterrupt(9002)
assert(allButtonsDirty == 2, "existing runtime proof scheduled duplicate full rebuild")

-- Raw runtime map presence is not sufficient without current-family validation.
Data.runtimeInterrupts[8888] = 8888
knownFamilies[8888] = nil
assert(Data:MatchesCurrentInterrupt(8888) == false)
assert(Data.negativeCooldownSpellMatches[8888] == true)

-- A genuinely new authoritative family clears stale negative alias results.
assert(Data:MatchesCurrentInterrupt(7777) == false)
assert(Data.negativeCooldownSpellMatches[7777] == true)
knownFamilies[7777] = true
Data:LearnRuntimeInterrupt(7777)
assert(Data.negativeCooldownSpellMatches[7777] == nil)
assert(Data:MatchesCurrentInterrupt(7777) == true)

-- Unrelated spell IDs are bounded to 128 negatives; the 129th resets the tiny
-- cache rather than growing for the whole application session.
for spellID = 10001, 10128 do
    assert(Data:MatchesCurrentInterrupt(spellID) == false)
end
assert(Data.negativeCooldownSpellMatchCount == 128)
assert(Data:MatchesCurrentInterrupt(10129) == false)
assert(Data.negativeCooldownSpellMatchCount == 1)
assert(Data.negativeCooldownSpellMatches[10129] == true)
assert(Data.negativeCooldownSpellMatches[10001] == nil)

-- A registry/config rebuild clears both runtime proof and negative cache.
Data:RefreshActiveSpec()
assert(next(Data.runtimeInterrupts) == nil)
assert(next(Data.negativeCooldownSpellMatches) == nil)
assert(Data.negativeCooldownSpellMatchCount == 0)

local policy = assert(InterruptGlow.modules.RuntimeInterruptPolicy)
assert(policy.clearsProofOnRegistryRebuild == true)
assert(policy.actionSlotsSeedBeforeSecondaryCopies == true)
assert(policy.refreshesCDMAfterActionSeed == true)
assert(policy.propagatesNewRuntimeFamilies == true)
assert(policy.revalidatesCooldownEventMatches == true)
assert(policy.negativeMatchLimit == 128)
assert(policy.avoidsStickySeedState == true)

print("RUNTIME INTERRUPT POLICY TEST PASSED")
