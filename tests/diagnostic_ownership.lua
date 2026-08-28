local ROOT = arg[1] or "."

_G = _G or _ENV

InterruptGlow = {
    DB = { debug = false },
    Stats = { old = 9 },
    modules = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow.CanAccess(_) return true end

DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local loader, loadError = loadfile(ROOT .. "/core/DiagnosticsPolicy.lua")
assert(loader, loadError)
loader()

local IG = InterruptGlow
assert(IG.profileCountersEnabled == false and IG.profileCounterOwner == nil)

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

-- Debug mode remains an independent opt-in for counters without claiming the
-- explicit manual/capture ownership channel.
IG.DB.debug = true
IG:BumpStat("debug.event")
assert(IG.Stats["debug.event"] == 1)
assert(IG.profileCounterOwner == nil)

print("DIAGNOSTIC OWNERSHIP TEST PASSED")
