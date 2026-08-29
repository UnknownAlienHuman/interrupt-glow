local ROOT = arg[1] or "."

_G = _G or _ENV

InterruptGlow = {
    modules = {},
    Data = {
        extraInterruptsBySpec = {
            [265] = { 212619 },
        },
    },
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end

local loader, loadError = loadfile(ROOT .. "/core/SpecInterruptCoveragePolicy.lua")
assert(loader, loadError)
loader()

local extra = InterruptGlow.Data.extraInterruptsBySpec
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
end

assert(#extra[265] == 1 and extra[265][1] == 212619, "existing PvP coverage changed")

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

print("SPEC INTERRUPT COVERAGE TEST PASSED")
