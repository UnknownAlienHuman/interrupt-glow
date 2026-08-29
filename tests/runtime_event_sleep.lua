local ROOT = arg[1] or "."

_G = _G or _ENV

local registered = {}
local unitFilters = {}
local stats = {}
local markCastCalls = 0
local markCooldownCalls = 0
local restrictionCalls = 0
local regenCalls = 0
local onEvent

local frame = {}
function frame:RegisterEvent(event)
    registered[event] = true
end
function frame:RegisterUnitEvent(event, ...)
    registered[event] = true
    unitFilters[event] = { ... }
end
function frame:UnregisterEvent(event)
    registered[event] = nil
    unitFilters[event] = nil
end
function frame:SetScript(script, handler)
    assert(script == "OnEvent")
    onEvent = handler
end

function CreateFrame(kind)
    assert(kind == "Frame")
    return frame
end

EventUtil = {
    ContinueOnPlayerLogin = function(callback)
        callback()
    end,
}

InterruptGlow = {
    DB = { enabled = false, debug = false },
    modules = {},
    RuntimeProbe = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:BumpStat(key)
    stats[key] = (stats[key] or 0) + 1
end
function InterruptGlow:MarkCastDirty() markCastCalls = markCastCalls + 1 end
function InterruptGlow:MarkCooldownDirty() markCooldownCalls = markCooldownCalls + 1 end
function InterruptGlow.RuntimeProbe:OnRestrictionStateChanged()
    restrictionCalls = restrictionCalls + 1
end

local runtimeActive = false
InterruptGlow.RuntimeLifecycle = {
    Initialize = function()
        InterruptGlow:SetRuntimeEventsEnabled(InterruptGlow.DB.enabled == true)
    end,
    IsActive = function()
        return runtimeActive
    end,
    OnCombatEnded = function()
        regenCalls = regenCalls + 1
    end,
}

local loader, loadError = loadfile(ROOT .. "/core/Events.lua")
assert(loader, loadError)
loader()

assert(type(onEvent) == "function")
assert(InterruptGlow.runtimeInitialized == true)
assert(InterruptGlow.runtimeEventsRegistered ~= true)

-- Only lifecycle/diagnostic events remain while the feature is disabled.
assert(registered.PLAYER_REGEN_ENABLED == true)
assert(registered.ADDON_RESTRICTION_STATE_CHANGED == true)
assert(registered.PLAYER_TARGET_CHANGED == nil)
assert(registered.SPELL_UPDATE_COOLDOWN == nil)
assert(registered.ACTION_USABLE_CHANGED == nil)
assert(registered.UNIT_SPELLCAST_SUCCEEDED == nil)
assert(registered.LOSS_OF_CONTROL_ADDED == nil)

runtimeActive = true
assert(InterruptGlow:SetRuntimeEventsEnabled(true) == true)
assert(InterruptGlow.runtimeEventsRegistered == true)
assert(registered.PLAYER_TARGET_CHANGED == true)
assert(registered.SPELL_UPDATE_COOLDOWN == true)
assert(registered.ACTION_USABLE_CHANGED == true)
assert(registered.UNIT_PET == true)
assert(registered.UNIT_SPELLCAST_SUCCEEDED == true)
assert(registered.LOSS_OF_CONTROL_ADDED == true)
assert(registered.LOSS_OF_CONTROL_UPDATE == true)
assert(unitFilters.UNIT_PET[1] == "player" and unitFilters.UNIT_PET[2] == nil)
assert(unitFilters.UNIT_SPELLCAST_SUCCEEDED[1] == "player")
assert(unitFilters.UNIT_SPELLCAST_SUCCEEDED[2] == "pet")
assert(unitFilters.LOSS_OF_CONTROL_ADDED[1] == "player")
assert(unitFilters.LOSS_OF_CONTROL_UPDATE[1] == "player")
assert(InterruptGlow:SetRuntimeEventsEnabled(true) == false)

runtimeActive = false
assert(InterruptGlow:SetRuntimeEventsEnabled(false) == true)
assert(InterruptGlow.runtimeEventsRegistered == false)
assert(registered.PLAYER_TARGET_CHANGED == nil)
assert(registered.SPELL_UPDATE_COOLDOWN == nil)
assert(registered.ACTION_USABLE_CHANGED == nil)
assert(registered.UNIT_PET == nil)
assert(registered.UNIT_SPELLCAST_SUCCEEDED == nil)
assert(registered.LOSS_OF_CONTROL_ADDED == nil)
assert(registered.LOSS_OF_CONTROL_UPDATE == nil)
assert(registered.PLAYER_REGEN_ENABLED == true)
assert(registered.ADDON_RESTRICTION_STATE_CHANGED == true)
assert(InterruptGlow:SetRuntimeEventsEnabled(false) == false)

-- Defensive queued-event handling remains a no-op after unregister. Persistent
-- restriction telemetry still records the transition without waking runtime work.
onEvent(frame, "SPELL_UPDATE_COOLDOWN", 1766, 1766, 1, 1)
assert(markCastCalls == 0 and markCooldownCalls == 0)
onEvent(frame, "ADDON_RESTRICTION_STATE_CHANGED", "cooldown", true)
assert(restrictionCalls == 1)
assert(markCastCalls == 0 and markCooldownCalls == 0)
onEvent(frame, "PLAYER_REGEN_ENABLED")
assert(regenCalls == 1)

assert((stats["lifecycle.runtimeEventsRegistered"] or 0) == 1)
assert((stats["lifecycle.runtimeEventsUnregistered"] or 0) == 1)

local policy = assert(InterruptGlow.modules.RuntimeEventPolicy)
assert(policy.masterDisableUnregistersRuntimeEvents == true)
assert(policy.playerLossOfControlUsesUnitFilter == true)
assert(type(policy.persistentEvents) == "table")
assert(type(policy.runtimeEvents) == "table")

print("RUNTIME EVENT SLEEP TEST PASSED")
