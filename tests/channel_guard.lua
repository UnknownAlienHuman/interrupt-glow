local ROOT = arg[1] or "."

_G = _G or _ENV

local channel = {
    active = true,
    castBarID = 10,
    notInterruptible = false,
}
local cooldownInvalidations = 0
local glowRefreshes = 0
local registeredEvents = {}

InterruptGlow = {
    DB = { strictNI = true, debug = false },
    CastState = {
        target = { active = false, hostile = false, niState = "none", castBarID = nil },
        focus = { active = false, hostile = false, niState = "none", castBarID = nil },
    },
    Stats = {},
    modules = {},
    Glow = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow.CanAccess(_) return true end
function InterruptGlow:BumpStat(key, amount)
    self.Stats[key] = (self.Stats[key] or 0) + (amount or 1)
end
function InterruptGlow:MarkCooldownDirty() cooldownInvalidations = cooldownInvalidations + 1 end
function InterruptGlow.Glow:ApplyUnitInterruptibility(_, _, _) end
function InterruptGlow.Glow:RefreshUnit(_) glowRefreshes = glowRefreshes + 1 end
function InterruptGlow.Glow:RefreshUnitRelation() end

function UnitCastingInfo(_) return nil end
function UnitChannelInfo(unit)
    if unit == "target" and channel.active then
        return "Channel", "Channel", 1, 100000, 105000, false,
            channel.notInterruptible, 123, false, 0, channel.castBarID
    end
end
function UnitExists(unit) return unit == "target" or unit == "focus" end
function UnitCanAttack(_, unit) return unit == "target" end
function UnitIsDeadOrGhost(_) return false end

function CreateFrame()
    local frame = { scripts = {} }
    function frame:RegisterUnitEvent(event, unit)
        assert(type(unit) == "string", "RegisterUnitEvent requires unit varargs, not a table")
        assert(unit == "target" or unit == "focus")
        registeredEvents[event] = registeredEvents[event] or {}
        registeredEvents[event][unit] = true
    end
    function frame:UnregisterAllEvents() end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    return frame
end

local loader, loadError = loadfile(ROOT .. "/core/CastTracking.lua")
assert(loader, loadError)
loader()

local tracker = assert(InterruptGlow.CastTracking)
tracker:Attach()

local state = InterruptGlow.CastState.target
assert(state.active == true and state.isChannel == true)
assert(state.castBarID == 10)
assert(registeredEvents.UNIT_SPELLCAST_CHANNEL_UPDATE.target == true)
assert(registeredEvents.UNIT_SPELLCAST_EMPOWER_UPDATE.target == true)

-- The client can continue returning the old channel after its synchronous stop
-- event. The stop must clear immediately and suppress later polling snapshots.
tracker:OnUnitEvent(
    "target",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "target",
    "cast-guid-10",
    123,
    nil,
    10
)
assert(state.active == false)
assert(state.channelSuppressed == true)
assert(tracker.channelSuppressed.target == true)

tracker:OnUnitEvent("target", "UNIT_FLAGS", "target")
assert(state.active == false, "stale UnitChannelInfo resurrected after CHANNEL_STOP")
assert((InterruptGlow.Stats["cast.channelSnapshotSuppressed"] or 0) >= 1)

-- A real new start is the authoritative signal that polling may resume.
channel.castBarID = 11
tracker:OnUnitEvent("target", "UNIT_SPELLCAST_CHANNEL_START", "target", "cast-guid-11", 123, 11)
assert(state.active == true and state.isChannel == true)
assert(state.castBarID == 11)
assert(state.channelSuppressed == false)

-- A delayed stop for the previous cast must not clear the newer cast.
tracker:OnUnitEvent(
    "target",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "target",
    "cast-guid-10",
    123,
    nil,
    10
)
assert(state.active == true and state.castBarID == 11)
assert((InterruptGlow.Stats["cast.staleStopIgnored"] or 0) >= 1)

-- Current stop clears again. A unit identity reset intentionally permits a
-- mid-channel snapshot for a newly acquired target/focus token.
tracker:OnUnitEvent(
    "target",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "target",
    "cast-guid-11",
    123,
    nil,
    11
)
assert(state.active == false and state.channelSuppressed == true)
tracker:ResetUnitIdentity("target", "PLAYER_TARGET_CHANGED")
assert(state.active == true and state.castBarID == 11)
assert(state.channelSuppressed == false)

assert(cooldownInvalidations >= 2)
assert(glowRefreshes > 0)
print("CHANNEL GUARD TEST PASSED")
