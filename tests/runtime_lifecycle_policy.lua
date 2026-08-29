local ROOT = arg[1] or "."

_G = _G or _ENV

local combat = false
local runtimeEventsEnabled = false
local calls = {}
local stats = {}
local queuedRecord = { overlayQueued = true }

local function Count(key)
    calls[key] = (calls[key] or 0) + 1
end

InterruptGlow = {
    DB = { enabled = true, cdm = true },
    modules = {},
    PendingButtons = setmetatable({ [{}] = true }, { __mode = "k" }),
    _dirty = {
        spec = true,
        allButtons = true,
        cast = true,
        cooldown = true,
        visual = true,
        pruneCaches = true,
    },
    Data = {},
    Buttons = {},
    CastTracking = {},
    CDM = {},
    Cooldown = {},
    Glow = {
        prewarmQueue = { queuedRecord },
        prewarmHead = 1,
        prewarmTail = 1,
        prewarmQueued = setmetatable({ [queuedRecord] = true }, { __mode = "k" }),
    },
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:IsInCombat() return combat end
function InterruptGlow:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function InterruptGlow:BumpStat(key) stats[key] = (stats[key] or 0) + 1 end
function InterruptGlow:MarkAllButtonsDirty() Count("markAll") end
function InterruptGlow:MarkCastDirty() Count("markCast") end
function InterruptGlow:MarkCooldownDirty() Count("markCooldown") end
function InterruptGlow:MarkVisualDirty() Count("markVisual") end
function InterruptGlow:SetRuntimeEventsEnabled(enabled)
    enabled = enabled == true
    if runtimeEventsEnabled == enabled then return false end
    runtimeEventsEnabled = enabled
    Count(enabled and "eventsEnable" or "eventsDisable")
    return true
end

function InterruptGlow.Data:RefreshActiveSpec() Count("specRefresh") end
function InterruptGlow.Buttons:Attach(discover)
    assert(discover == true)
    Count("buttonsAttach")
end
function InterruptGlow.Buttons:Detach() Count("buttonsDetach") end
function InterruptGlow.CastTracking:Attach() Count("castAttach") end
function InterruptGlow.CastTracking:Detach() Count("castDetach") end
function InterruptGlow.CastTracking:ClearUnit(unit, reason)
    assert(unit == "target" or unit == "focus")
    assert(reason == "ADDON_DISABLED")
    Count("castClear")
end
function InterruptGlow.CDM:Attach(discover)
    assert(discover == true)
    Count("cdmAttach")
end
function InterruptGlow.CDM:Detach() Count("cdmDetach") end
function InterruptGlow.Cooldown:ClearGCDHints() Count("clearGCD") end
function InterruptGlow.Glow:DisablePrewarmWorker() Count("disablePrewarm") end
function InterruptGlow.Glow:SetRuntimeWorkerEnabled(enabled)
    assert(enabled == false)
    Count("stopRuntime")
end
function InterruptGlow.Glow:RefreshAll() Count("refreshVisuals") end
function InterruptGlow.Glow:CreatePendingOverlays() Count("createPending") end

local loader, loadError = loadfile(ROOT .. "/core/RuntimeLifecyclePolicy.lua")
assert(loader, loadError)
loader()

local Lifecycle = assert(InterruptGlow.RuntimeLifecycle)
assert(Lifecycle:Initialize() == true)
assert(Lifecycle:IsActive() == true)
assert(runtimeEventsEnabled == true and calls.eventsEnable == 1)
assert(calls.specRefresh == 1)
assert(calls.buttonsAttach == 1 and calls.castAttach == 1 and calls.cdmAttach == 1)
assert(calls.createPending == 1)
assert(calls.markAll == 1 and calls.markCast == 1)
assert(calls.markCooldown == 1 and calls.markVisual == 1)

-- Populate work after activation; master-disable must discard it without trying
-- to manipulate Shared.lua's private flushScheduled flag.
local pendingButton = {}
InterruptGlow.PendingButtons[pendingButton] = true
for key in pairs(InterruptGlow._dirty) do InterruptGlow._dirty[key] = true end
InterruptGlow.Glow.prewarmQueue = { queuedRecord }
InterruptGlow.Glow.prewarmHead = 1
InterruptGlow.Glow.prewarmTail = 1
InterruptGlow.Glow.prewarmQueued[queuedRecord] = true
queuedRecord.overlayQueued = true

assert(Lifecycle:SetEnabled(false) == true)
assert(InterruptGlow.DB.enabled == false)
assert(Lifecycle:IsActive() == false)
assert(runtimeEventsEnabled == false and calls.eventsDisable == 1)
assert(calls.cdmDetach == 1)
assert(calls.castClear == 2 and calls.castDetach == 1)
assert(calls.buttonsDetach == 1)
assert(calls.disablePrewarm == 1 and calls.stopRuntime == 1)
assert(calls.refreshVisuals == 1)
assert(next(InterruptGlow.PendingButtons) == nil)
for _, value in pairs(InterruptGlow._dirty) do assert(value == false) end
assert(InterruptGlow.Glow.prewarmHead == 1 and InterruptGlow.Glow.prewarmTail == 0)
assert(next(InterruptGlow.Glow.prewarmQueue) == nil)
assert(next(InterruptGlow.Glow.prewarmQueued) == nil)
assert(queuedRecord.overlayQueued == false)

-- Repeated disable is idempotent and does not detach or unregister twice.
assert(Lifecycle:SetEnabled(false) == false)
assert(calls.buttonsDetach == 1 and calls.castDetach == 1 and calls.cdmDetach == 1)
assert(calls.eventsDisable == 1)

-- Enabling in combat records the setting but defers provider discovery, event
-- registration and visual construction until PLAYER_REGEN_ENABLED.
combat = true
assert(Lifecycle:SetEnabled(true) == false)
assert(InterruptGlow.DB.enabled == true)
assert(Lifecycle.enablePending == true)
assert(Lifecycle:IsActive() == false)
assert(runtimeEventsEnabled == false)
assert(calls.buttonsAttach == 1 and calls.eventsEnable == 1)
assert((stats["lifecycle.enableDeferred"] or 0) == 1)

combat = false
assert(Lifecycle:OnCombatEnded() == true)
assert(Lifecycle:IsActive() == true)
assert(runtimeEventsEnabled == true and calls.eventsEnable == 2)
assert(calls.specRefresh == 2)
assert(calls.buttonsAttach == 2 and calls.castAttach == 2 and calls.cdmAttach == 2)
assert(calls.createPending == 2)

local policy = assert(InterruptGlow.modules.RuntimeLifecyclePolicy)
assert(policy == Lifecycle)
assert(policy.masterDisableDetachesProviders == true)
assert(policy.masterDisableDetachesCastWatchers == true)
assert(policy.masterDisableUnregistersRuntimeEvents == true)
assert(policy.masterDisableStopsWorkers == true)
assert(policy.enableDiscoveryIsOutOfCombat == true)
assert(policy.scheduledFlushIsAllowedToSelfDisable == true)

print("RUNTIME LIFECYCLE POLICY TEST PASSED")
