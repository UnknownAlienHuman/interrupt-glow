local ROOT = arg[1] or "."

_G = _G or _ENV

local currentSpecID = 258
local known = { [9002] = true }

InterruptGlow = {
    DB = { enabled = true, cdText = false },
    modules = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat() end

PlayerUtil = {
    GetCurrentSpecID = function() return currentSpecID end,
}
C_SpellBook = {
    IsSpellKnownOrInSpellBook = function(spellID) return known[spellID] == true end,
    FindBaseSpellByID = function(spellID)
        if spellID == 9002 then return 9001 end
    end,
    FindSpellOverrideByID = function(spellID)
        if spellID == 9001 then return 9002 end
    end,
}
Constants = {
    SpellCooldownConsts = { GLOBAL_RECOVERY_CATEGORY = 133 },
}

local loader, loadError = loadfile(ROOT .. "/core/Data.lua")
assert(loader, loadError)
loader()

local Data = InterruptGlow.Data
Data:RefreshActiveSpec()
assert(Data:LearnRuntimeInterrupt(9002) == 9001)

-- The actual override is known while the canonical base is not. Both queried
-- identities must remain in the runtime family learned from authoritative action
-- feedback.
assert(Data:GetCanonicalSpellID(9002, "spell") == 9001)
assert(Data:GetCanonicalSpellID(9001, "spell") == 9001)
assert(Data:MatchesCurrentInterrupt(9002) == true)
assert(Data:MatchesCurrentInterrupt(9001) == true)

-- Same-spec spellbook churn retains the learned mapping but revalidates family
-- availability. Once neither base nor override is known, direct/CDM copies fail
-- closed until a current action slot proves the interrupt again.
known[9002] = nil
Data:RefreshActiveSpec()
assert(Data.runtimeInterrupts[9002] == 9001)
assert(Data:GetCanonicalSpellID(9002, "spell") == nil)
assert(Data:GetCanonicalSpellID(9001, "spell") == nil)

known[9002] = true
assert(Data:GetCanonicalSpellID(9001, "spell") == 9001)

-- A real specialization change clears session-learned interrupt families.
currentSpecID = 257
Data:RefreshActiveSpec()
assert(next(Data.runtimeInterrupts) == nil)
assert(Data:GetCanonicalSpellID(9002, "spell") == nil)

print("RUNTIME INTERRUPT FAMILY TEST PASSED")
