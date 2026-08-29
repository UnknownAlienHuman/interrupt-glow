local ROOT = arg[1] or "."

_G = _G or _ENV

local secretSpellID = {}
local forbiddenKeyReads = 0
local baseLearnCalls = 0
local markAllCalls = 0

local runtimeInterrupts = setmetatable({}, {
    __index = function(_, key)
        if key == secretSpellID then
            forbiddenKeyReads = forbiddenKeyReads + 1
            error("secret spell ID was used as a table key")
        end
        return nil
    end,
})

InterruptGlow = {
    modules = {},
    DB = { cdm = false },
    Data = {
        runtimeInterrupts = runtimeInterrupts,
        cooldownSpellMatchCache = {},
        activeInterrupts = {},
        negativeCooldownSpellMatches = {},
        negativeCooldownSpellMatchCount = 0,
    },
    Buttons = {},
    ObservedButtons = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= secretSpellID end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat() end
function InterruptGlow:MarkAllButtonsDirty() markAllCalls = markAllCalls + 1 end
function InterruptGlow:ReadMember(container, key)
    if not self.CanAccess(container) or container == nil then return nil, false end
    local value = container[key]
    if not self.CanAccess(value) then return nil, false end
    return value, true
end
function InterruptGlow:AsNumber(value)
    if not self.CanAccess(value) then return nil end
    if type(value) == "number" then return value end
end

function InterruptGlow.Data:RefreshActiveSpec() return 259, false end
function InterruptGlow.Data:LearnRuntimeInterrupt(spellID)
    baseLearnCalls = baseLearnCalls + 1
    if not InterruptGlow.CanAccess(spellID) or type(spellID) ~= "number" then
        return nil
    end
    self.runtimeInterrupts[spellID] = spellID
    return spellID
end
function InterruptGlow.Data:GetCanonicalSpellID() return nil end
function InterruptGlow.Buttons:ReconcileAll() end

local loader, loadError = loadfile(ROOT .. "/core/RuntimeInterruptPolicy.lua")
assert(loader, loadError)
loader()

-- The wrapper must delegate an inaccessible value to the already guarded base
-- implementation without type-checking or table-keying it first.
assert(InterruptGlow.Data:LearnRuntimeInterrupt(secretSpellID) == nil)
assert(baseLearnCalls == 1)
assert(forbiddenKeyReads == 0)
assert(markAllCalls == 0)

-- Ordinary runtime proof still propagates exactly once.
assert(InterruptGlow.Data:LearnRuntimeInterrupt(1766) == 1766)
assert(baseLearnCalls == 2)
assert(runtimeInterrupts[1766] == 1766)
assert(markAllCalls == 1)

-- Re-learning the same canonical family must not schedule another full rebind.
assert(InterruptGlow.Data:LearnRuntimeInterrupt(1766) == 1766)
assert(baseLearnCalls == 3)
assert(markAllCalls == 1)

local policy = assert(InterruptGlow.modules.RuntimeInterruptPolicy)
assert(policy.accessGatesRuntimeProofKeys == true)
print("RUNTIME INTERRUPT SECRET KEY TEST PASSED")
