local ROOT = arg[1] or "."

_G = _G or _ENV

local secretSpellID = {}
local secretItemFrame = {}
local forbiddenSpellCacheAccesses = 0
local forbiddenButtonMapAccesses = 0
local canonicalResolverCalls = 0
local markAllCalls = 0
local unbindCalls = 0
local observeButtonCalls = 0
local hookCalls = 0
local currentSpecID = 102
local knownSpells = {}

local function IsKnown(spellID)
    return knownSpells[spellID] ~= false
end

C_SpellBook = {
    IsSpellKnownOrInSpellBook = IsKnown,
    FindBaseSpellByID = function(spellID) return spellID end,
    FindSpellOverrideByID = function(spellID) return spellID end,
}
PlayerUtil = { GetCurrentSpecID = function() return currentSpecID end }
Constants = { SpellCooldownConsts = { GLOBAL_RECOVERY_CATEGORY = 133 } }
C_AddOns = { IsAddOnLoaded = function() return true, true end }
CooldownViewerMixin = {
    OnAcquireItemFrame = function() end,
}
CooldownViewerItemDataMixin = {
    OnCooldownIDSet = function() end,
    ResetCooldownData = function() end,
}
function hooksecurefunc(object, methodName, callback)
    assert(type(object[methodName]) == "function")
    assert(type(callback) == "function")
    hookCalls = hookCalls + 1
end

local observedButtons = setmetatable({}, {
    __index = function()
        forbiddenButtonMapAccesses = forbiddenButtonMapAccesses + 1
    end,
    __newindex = function()
        forbiddenButtonMapAccesses = forbiddenButtonMapAccesses + 1
    end,
})

InterruptGlowDB = { enabled = true, cdm = true }
InterruptGlow = {
    DB = InterruptGlowDB,
    ObservedButtons = observedButtons,
    AbilityStates = {},
    playerLoginSeen = true,
    Buttons = {},
}
local IG = InterruptGlow
function IG.CanAccess(value) return value ~= secretSpellID and value ~= secretItemFrame end
function IG:ReadMember(object, key)
    if not self.CanAccess(object) or object == nil then return nil, false end
    local ok, value = pcall(function() return object[key] end)
    if not ok or not self.CanAccess(value) then return nil, false end
    return value, true
end
function IG:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function IG:BumpStat() end
function IG:MarkAllButtonsDirty() markAllCalls = markAllCalls + 1 end
function IG:IsAddOnFullyLoaded(name) return name == "Blizzard_CooldownViewer" end
function IG:IsInCombat() return false end
function IG.Buttons:UnbindRecord(record)
    unbindCalls = unbindCalls + 1
    record.isInterrupt = false
end
function IG.Buttons:ObserveButton()
    observeButtonCalls = observeButtonCalls + 1
    return nil
end

local dataLoader, dataError = loadfile(ROOT .. "/core/Data.lua")
assert(dataLoader, dataError)
dataLoader()
local Data = assert(IG.Data)

-- Every optional specialization extra uses the exact-known spell proof before
-- it enters the active registry.
local optionalExtras = {
    { 102, 106839 },
    { 105, 106839 },
    { 1468, 351338 },
    { 270, 116705 },
    { 65, 96231 },
}
for _, item in ipairs(optionalExtras) do
    currentSpecID = item[1]
    knownSpells[item[2]] = false
    Data:RefreshActiveSpec()
    assert(Data.specInterrupts[item[2]] == nil, "unknown optional extra entered spec registry")
    knownSpells[item[2]] = true
    Data:RefreshActiveSpec()
    assert(Data.specInterrupts[item[2]] == true, "known optional extra was omitted")
end

-- Optional spec extras require the exact spell to be known, even when the
-- primary spellbook API is present and the specialization itself is known.
currentSpecID = 102
knownSpells[106839] = false
Data:RefreshActiveSpec()
assert(Data.specInterrupts[106839] == nil)
assert(Data:GetCanonicalSpellID(106839, "spell") == nil)
knownSpells[106839] = true
Data:RefreshActiveSpec()
assert(Data.specInterrupts[106839] == true)
assert(Data:GetCanonicalSpellID(106839, "spell") == 106839)

-- An inaccessible spell ID is rejected before either positive or negative
-- spell caches are indexed. The cache metatable counts any attempted access.
forbiddenSpellCacheAccesses = 0
setmetatable(Data.cooldownSpellMatchCache, {
    __index = function()
        forbiddenSpellCacheAccesses = forbiddenSpellCacheAccesses + 1
    end,
    __newindex = function()
        forbiddenSpellCacheAccesses = forbiddenSpellCacheAccesses + 1
    end,
})
setmetatable(Data.negativeCooldownSpellMatches, {
    __index = function()
        forbiddenSpellCacheAccesses = forbiddenSpellCacheAccesses + 1
    end,
    __newindex = function()
        forbiddenSpellCacheAccesses = forbiddenSpellCacheAccesses + 1
    end,
})
assert(Data:GetCanonicalSpellID(secretSpellID, "spell") == nil)
assert(Data:MatchesCurrentInterrupt(secretSpellID) == false)
assert(forbiddenSpellCacheAccesses == 0, "inaccessible spell ID was used as a cache key")
setmetatable(Data.cooldownSpellMatchCache, nil)
setmetatable(Data.negativeCooldownSpellMatches, nil)

-- A cached negative result avoids repeating canonical resolution. Learning
-- runtime proof clears that bounded negative cache and the spell becomes a
-- positive match exactly once for the new proof revision.
local originalCanonicalResolver = Data.GetCanonicalSpellID
Data.GetCanonicalSpellID = function(self, spellID, sourceKind)
    canonicalResolverCalls = canonicalResolverCalls + 1
    return originalCanonicalResolver(self, spellID, sourceKind)
end
assert(Data:MatchesCurrentInterrupt(999999) == false)
assert(Data.negativeCooldownSpellMatchCount == 1)
local firstResolutionCount = canonicalResolverCalls
assert(Data:MatchesCurrentInterrupt(999999) == false)
assert(canonicalResolverCalls == firstResolutionCount, "negative cache repeated canonical resolution")
assert(Data:LearnRuntimeInterrupt(999999) == 999999)
assert(Data.negativeCooldownSpellMatchCount == 0)
assert(next(Data.negativeCooldownSpellMatches) == nil)
assert(Data:MatchesCurrentInterrupt(999999) == true)

-- A spec rebuild also invalidates negative results so newly active spells can
-- be found without retaining stale negatives.
assert(Data:MatchesCurrentInterrupt(999998) == false)
assert(Data.negativeCooldownSpellMatchCount == 1)
currentSpecID = 258
Data:RefreshActiveSpec()
assert(Data.negativeCooldownSpellMatchCount == 0)
assert(next(Data.negativeCooldownSpellMatches) == nil)
assert(Data:MatchesCurrentInterrupt(15487) == true)

-- Without the spellbook contract, static direct-spell and CDM proof fail
-- closed. An action source may still use the action-bar-backed current-spec
-- identity, and runtime proof learned from an action remains valid.
C_SpellBook = nil
dataLoader()
Data = IG.Data
currentSpecID = 258
Data:RefreshActiveSpec()
assert(Data:GetCanonicalSpellID(15487, "spell") == nil)
assert(Data:GetCanonicalSpellID(15487, "action") == 15487)
assert(Data:GetCanonicalSpellID(15487, "spell") == nil, "static direct spell escaped missing-contract gate")
assert(Data:LearnRuntimeInterrupt(765432) == 765432)
assert(Data:GetCanonicalSpellID(765432, "spell") == 765432)

-- CDM rejects inaccessible frames before reading or indexing the weak record
-- map, then its real disable/enable path unbinds and reattaches provider hooks.
local cdmLoader, cdmError = loadfile(ROOT .. "/core/CDM.lua")
assert(cdmLoader, cdmError)
cdmLoader()
local CDM = assert(IG.CDM)
local cdmItem = {}
rawset(observedButtons, cdmItem, { adapter = "cdm", cdmCanonicalSpellID = 15487 })
forbiddenButtonMapAccesses = 0
CDM.attached = true
CDM:ObserveItem(secretItemFrame)
assert(forbiddenButtonMapAccesses == 0, "inaccessible CDM frame reached weak-table indexing")
assert(observeButtonCalls == 0)

CDM:SetEnabled(false)
assert(CDM.attached == false)
assert(unbindCalls == 1)
assert(rawget(observedButtons, cdmItem).isInterrupt == false)

CDM:SetEnabled(true)
assert(CDM.attached == true)
assert(CDM.hooksInstalled == true)
assert(hookCalls == 3, "Cooldown Viewer lifecycle hooks did not reattach")

print("DATA + CDM INTEGRATION TEST PASSED")
