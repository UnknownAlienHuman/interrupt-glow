local ROOT = arg[1] or "."

_G = _G or _ENV

InterruptGlow = {
    AbilityStates = {},
    Stats = {},
    Buttons = {},
    Cooldown = {
        generation = 42,
        cache = {
            action = { [1] = { ready = true } },
            spell = { [15487] = { ready = true } },
            pet = { [1] = { ready = true } },
        },
        gcdHints = { [15487] = true },
    },
    modules = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat(key, amount)
    self.Stats[key] = (self.Stats[key] or 0) + (amount or 1)
end

local activeRecord = {}
InterruptGlow.AbilityStates[15487] = {
    records = { [activeRecord] = true },
}
InterruptGlow.AbilityStates[6552] = {
    records = {},
    dormant = true,
}
InterruptGlow.AbilityStates[2139] = {
    records = setmetatable({}, { __mode = "k" }),
    dormant = true,
}

local loader, loadError = loadfile(ROOT .. "/core/CachePolicy.lua")
assert(loader, loadError)
loader()

local removed = InterruptGlow.Buttons:PruneDormantAbilities()
assert(removed == 2)
assert(InterruptGlow.AbilityStates[15487] ~= nil)
assert(InterruptGlow.AbilityStates[6552] == nil)
assert(InterruptGlow.AbilityStates[2139] == nil)

InterruptGlow.Cooldown:ResetCaches()
assert(InterruptGlow.Cooldown.generation == 0)
assert(next(InterruptGlow.Cooldown.cache.action) == nil)
assert(next(InterruptGlow.Cooldown.cache.spell) == nil)
assert(next(InterruptGlow.Cooldown.cache.pet) == nil)
assert(next(InterruptGlow.Cooldown.gcdHints) == nil)
assert(InterruptGlow.Stats["abilities.pruned"] == 2)
assert(InterruptGlow.Stats["cooldown.cacheResets"] == 1)

print("CACHE POLICY TEST PASSED")
