local ROOT = arg[1] or "."

_G = _G or _ENV

local currentSpecID = 102
local secretValue = {}

InterruptGlow = {
    modules = {},
    Data = {
        extraInterruptsBySpec = {
            [265] = { 212619 },
        },
        specInterrupts = {},
        activeInterrupts = {},
    },
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= secretValue end
function InterruptGlow.Data:RefreshActiveSpec()
    for key in pairs(self.specInterrupts) do self.specInterrupts[key] = nil end
    for key in pairs(self.activeInterrupts) do self.activeInterrupts[key] = nil end

    -- Simulate the base compatibility path, which admits an entry before the
    -- optional coverage policy applies its stricter exact-known gate.
    local list = self.extraInterruptsBySpec[currentSpecID]
    if list then
        for index = 1, #list do
            local spellID = list[index]
            self.specInterrupts[spellID] = true
            self.activeInterrupts[spellID] = true
        end
    end
    return currentSpecID, false
end

local loader, loadError = loadfile(ROOT .. "/core/SpecInterruptCoveragePolicy.lua")
assert(loader, loadError)
loader()

local Data = InterruptGlow.Data
local extra = Data.extraInterruptsBySpec
local expected = {
    [102] = 106839,
    [105] = 106839,
    [1468] = 351338,
    [270] = 116705,
    [65] = 96231,
}

for specID, spellID in pairs(expected) do
    local list = assert(extra[specID], "missing optional spec list " .. specID)
    local count = 0
    for index = 1, #list do
        if list[index] == spellID then count = count + 1 end
    end
    assert(count == 1, ("spec %d expected one spell %d, found %d"):format(specID, spellID, count))
    assert(Data.exactKnownInterrupts[spellID] == true)
end

assert(#extra[265] == 1 and extra[265][1] == 212619, "existing PvP coverage changed")

-- Missing API is fail-closed for optional talents.
C_SpellBook = nil
Data:RefreshActiveSpec()
assert(Data.specInterrupts[106839] == nil)
assert(Data.activeInterrupts[106839] == nil)
assert(Data:RequiresExactKnownSpell(106839) == false)

-- False and inaccessible results are also fail-closed.
C_SpellBook = { IsSpellKnownOrInSpellBook = function() return false end }
Data:RefreshActiveSpec()
assert(Data.activeInterrupts[106839] == nil)
C_SpellBook.IsSpellKnownOrInSpellBook = function() return secretValue end
Data:RefreshActiveSpec()
assert(Data.activeInterrupts[106839] == nil)

-- Only an ordinary exact true admits the optional interrupt.
C_SpellBook.IsSpellKnownOrInSpellBook = function(spellID)
    return spellID == 106839
end
Data:RefreshActiveSpec()
assert(Data.specInterrupts[106839] == true)
assert(Data.activeInterrupts[106839] == true)
assert(Data:RequiresExactKnownSpell(106839) == true)

-- Non-optional existing PvP coverage keeps the base policy.
currentSpecID = 265
C_SpellBook = nil
Data:RefreshActiveSpec()
assert(Data.activeInterrupts[212619] == true)

-- Loading the policy again must remain idempotent rather than duplicating data.
loader()
for specID, spellID in pairs(expected) do
    local count = 0
    for index = 1, #extra[specID] do
        if extra[specID][index] == spellID then count = count + 1 end
    end
    assert(count == 1, ("spec %d duplicated spell %d"):format(specID, spellID))
end

local policy = assert(InterruptGlow.modules.SpecInterruptCoveragePolicy)
assert(policy.spellbookGated == true)
assert(policy.requiresExactKnownSpell == true)
assert(policy.neverAddsUnknownOptionalInterrupts == true)

print("SPEC INTERRUPT COVERAGE TEST PASSED")
