local ROOT = arg[1] or "."

_G = _G or _ENV

InterruptGlow = {
    DB = { enabled = true },
    AbilityStates = {},
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    PendingButtons = setmetatable({}, { __mode = "k" }),
    Stats = {},
}
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat(key, amount)
    self.Stats[key] = (self.Stats[key] or 0) + (amount or 1)
end

local activeRecord = {}
InterruptGlow.AbilityStates[15487] = { records = { [activeRecord] = true } }
InterruptGlow.AbilityStates[6552] = { records = {}, dormant = true }
InterruptGlow.AbilityStates[2139] = { records = setmetatable({}, { __mode = "k" }), dormant = true }

local buttonsLoader, buttonsError = loadfile(ROOT .. "/core/Buttons.lua")
assert(buttonsLoader, buttonsError)
buttonsLoader()
local cooldownLoader, cooldownError = loadfile(ROOT .. "/core/Cooldown.lua")
assert(cooldownLoader, cooldownError)
cooldownLoader()

local Buttons = assert(InterruptGlow.Buttons)
local Cooldown = assert(InterruptGlow.Cooldown)
local removed = Buttons:PruneDormantAbilities()
assert(removed == 2)
assert(InterruptGlow.AbilityStates[15487] ~= nil)
assert(InterruptGlow.AbilityStates[6552] == nil)
assert(InterruptGlow.AbilityStates[2139] == nil)

Cooldown.cache.action[1] = { ready = true }
Cooldown.cache.spell[15487] = { ready = true }
Cooldown.cache.pet[1] = { ready = true }
Cooldown.generation = 42
Cooldown:ResetCaches()
assert(Cooldown.generation == 0)
assert(next(Cooldown.cache.action) == nil)
assert(next(Cooldown.cache.spell) == nil)
assert(next(Cooldown.cache.pet) == nil)
assert(InterruptGlow.Stats["abilities.pruned"] == 2)
assert(InterruptGlow.Stats["cooldown.cacheResets"] == 1)

print("CACHE OWNERSHIP TEST PASSED")
