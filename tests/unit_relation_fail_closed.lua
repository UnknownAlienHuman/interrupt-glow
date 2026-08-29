local ROOT = arg[1] or "."

_G = _G or _ENV

local secretDead = {}
local deadState = secretDead
local canAttackCalls = 0
local cooldownDirty = 0

InterruptGlow = {
    DB = { strictNI = true, debug = false },
    CastState = {
        target = { active = false, hostile = false, niState = "none" },
        focus = { active = false, hostile = false, niState = "none" },
    },
    Stats = {},
    modules = {},
    Glow = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(value) return value ~= secretDead end
function InterruptGlow:BumpStat(key, amount)
    self.Stats[key] = (self.Stats[key] or 0) + (amount or 1)
end
function InterruptGlow:MarkCooldownDirty() cooldownDirty = cooldownDirty + 1 end
function InterruptGlow.Glow:ApplyUnitInterruptibility() end
function InterruptGlow.Glow:RefreshUnit() end
function InterruptGlow.Glow:RefreshUnitRelation() end

function UnitCastingInfo(unit)
    if unit == "target" then
        return "Cast", "Cast", 1, 1000, 2000, false, 1, false, 123, 9, 0
    end
end
function UnitChannelInfo() return nil end
function UnitExists(unit) return unit == "target" end
function UnitIsDeadOrGhost() return deadState end
function UnitCanAttack(_, unit)
    assert(unit == "target")
    canAttackCalls = canAttackCalls + 1
    return true
end

function CreateFrame()
    local frame = { scripts = {} }
    function frame:RegisterUnitEvent() end
    function frame:UnregisterAllEvents() end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    return frame
end

local loader, loadError = loadfile(ROOT .. "/core/CastTracking.lua")
assert(loader, loadError)
loader()

local tracker = assert(InterruptGlow.CastTracking)
tracker:RefreshUnit("target", nil, false, "SECRET_DEAD_STATE")
local state = InterruptGlow.CastState.target
assert(state.active == true)
assert(state.hostile == false, "inaccessible alive state was treated as hostile")
assert(canAttackCalls == 0, "UnitCanAttack was queried before alive state was known")
assert(cooldownDirty == 0)

-- An explicit accessible alive state permits ordinary hostile classification.
deadState = false
tracker:RefreshUnit("target", nil, false, "KNOWN_ALIVE_STATE")
assert(state.active == true and state.hostile == true)
assert(canAttackCalls == 1)
assert(cooldownDirty == 1)

-- Explicit death remains fail closed and does not query attackability.
deadState = true
tracker:RefreshUnit("target", nil, false, "KNOWN_DEAD_STATE")
assert(state.active == true and state.hostile == false)
assert(canAttackCalls == 1)

print("UNIT RELATION FAIL-CLOSED TEST PASSED")
