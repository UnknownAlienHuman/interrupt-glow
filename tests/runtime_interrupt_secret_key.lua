local ROOT = arg[1] or "."

_G = _G or _ENV

local secretSpellID = {}
local forbiddenKeyReads = 0
local dirtyCalls = 0
local runtimeInterrupts = setmetatable({}, {
    __index = function(_, key)
        if key == secretSpellID then
            forbiddenKeyReads = forbiddenKeyReads + 1
            error("inaccessible spell ID was used as a runtime proof key")
        end
        return nil
    end,
})

InterruptGlow = {
    modules = {},
    Data = nil,
}
function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= secretSpellID end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat() end
function InterruptGlow:MarkAllButtonsDirty() dirtyCalls = dirtyCalls + 1 end

local loader, loadError = loadfile(ROOT .. "/core/Data.lua")
assert(loader, loadError)
loader()
local Data = assert(InterruptGlow.Data)
Data.runtimeInterrupts = runtimeInterrupts

-- The actual Data owner rejects inaccessible input before canonical lookup or
-- any read/write against the session proof map.
assert(Data:LearnRuntimeInterrupt(secretSpellID) == nil)
assert(forbiddenKeyReads == 0)
assert(dirtyCalls == 0)

assert(Data:LearnRuntimeInterrupt(1766) == 1766)
assert(runtimeInterrupts[1766] == 1766)
assert(dirtyCalls == 1)
assert(Data:LearnRuntimeInterrupt(1766) == 1766)
assert(dirtyCalls == 1, "repeat runtime proof triggered redundant rebind work")

print("RUNTIME INTERRUPT SECRET KEY TEST PASSED")
