local ROOT = arg[1] or "."

_G = _G or _ENV
InterruptGlow = {
    DB = { debug = false, debugKeep = 400 },
    Stats = { old = 9 },
    modules = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end

function CreateFrame()
    return { SetScript = function() end }
end
function InCombatLockdown() return false end
function GetTime() return 10 end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local loader, loadError = loadfile(ROOT .. "/core/Shared.lua")
assert(loader, loadError)
loader()

local IG = InterruptGlow
assert(IG.profileCountersEnabled == false and IG.profileCounterOwner == nil)
assert(IG.Stats.old == 9, "Shared should preserve the existing runtime stats map on load")

local ok, owner = IG:StartProfileCounters("manual")
assert(ok == true and owner == "manual")
assert(IG.profileCountersEnabled == true and IG.profileCounterOwner == "manual")
assert(next(IG.Stats) == nil)

IG:BumpStat("manual.event")
assert(IG.Stats["manual.event"] == 1)

ok, owner = IG:StartProfileCounters("capture")
assert(ok == false and owner == "manual")
assert(IG.Stats["manual.event"] == 1, "failed acquisition cleared another owner's counters")

ok, owner = IG:ResetProfileCounters("capture")
assert(ok == false and owner == "manual")
assert(IG.Stats["manual.event"] == 1)

ok, owner = IG:StopProfileCounters("capture")
assert(ok == false and owner == "manual")
assert(IG.profileCountersEnabled == true and IG.profileCounterOwner == "manual")

assert(IG:StopProfileCounters("manual") == true)
assert(IG.profileCountersEnabled == false and IG.profileCounterOwner == nil)

assert(IG:StartProfileCounters("capture") == true)
assert(IG.profileCounterOwner == "capture")
IG:BumpStat("capture.event", 2)
assert(IG.Stats["capture.event"] == 2)
assert(IG:ResetProfileCounters("capture") == true)
assert(next(IG.Stats) == nil)
assert(IG:StopProfileCounters("capture") == true)

-- Debug logging independently enables counters without taking ownership of an
-- explicit manual or capture window.
IG.DB.debug = true
IG:BumpStat("debug.event")
assert(IG.Stats["debug.event"] == 1)
assert(IG.profileCounterOwner == nil)

print("DIAGNOSTIC OWNERSHIP TEST PASSED")
