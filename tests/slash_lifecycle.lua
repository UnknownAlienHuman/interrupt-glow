local ROOT = arg[1] or "."

_G = _G or _ENV

local combat = false
local runtimeEventsEnabled = false
local calls = {}
local printed = {}

local function Count(name)
    calls[name] = (calls[name] or 0) + 1
end

InterruptGlow = {
    DB = { enabled = true, cdm = true },
    PendingButtons = setmetatable({}, { __mode = "k" }),
    _dirty = {
        spec = false,
        allButtons = false,
        cast = false,
        cooldown = false,
        visual = false,
        pruneCaches = false,
    },
    Data = {},
    Buttons = {},
    CastTracking = {},
    CDM = {},
    Cooldown = {},
    Glow = { prewarmQueue = {}, prewarmQueued = {} },
    Stats = {},
}
local IG = InterruptGlow
function IG:IsInCombat() return combat end
function IG:BumpStat(key) self.Stats[key] = (self.Stats[key] or 0) + 1 end
function IG:WipeMap(map) for key in pairs(map) do map[key] = nil end end
function IG:Print(message) printed[#printed + 1] = message end
function IG:MarkAllButtonsDirty() Count("markAll") end
function IG:MarkCastDirty() Count("markCast") end
function IG:MarkCooldownDirty() Count("markCooldown") end
function IG:MarkVisualDirty() Count("markVisual") end
function IG:SetRuntimeEventsEnabled(enabled)
    enabled = enabled == true
    if enabled == runtimeEventsEnabled then return false end
    runtimeEventsEnabled = enabled
    Count(enabled and "eventsEnable" or "eventsDisable")
    return true
end

function IG.Data:RefreshActiveSpec() Count("specRefresh") end
function IG.Buttons:Attach(discover)
    assert(discover == true)
    Count("buttonsAttach")
end
function IG.Buttons:Detach() Count("buttonsDetach") end
function IG.CastTracking:Attach() Count("castAttach") end
function IG.CastTracking:Detach() Count("castDetach") end
function IG.CastTracking:ClearUnit(unit, reason)
    assert(unit == "target" or unit == "focus")
    assert(reason == "ADDON_DISABLED")
    Count("castClear")
end
function IG.CDM:Attach(discover)
    assert(discover == true)
    Count("cdmAttach")
end
function IG.CDM:Detach() Count("cdmDetach") end
function IG.Cooldown:ClearGCDHints() Count("clearGCD") end
function IG.Glow:DisablePrewarmWorker() Count("disablePrewarm") end
function IG.Glow:SetRuntimeWorkerEnabled(enabled)
    assert(enabled == false)
    Count("stopRuntime")
end
function IG.Glow:RefreshAll() Count("refreshVisuals") end
function IG.Glow:CreatePendingOverlays() Count("createPending") end
function IG.Glow:RetryDeferredVisuals() Count("retryDeferredVisuals") end

SlashCmdList = {}
local function Load(relative)
    local loader, loadError = loadfile(ROOT .. "/" .. relative)
    assert(loader, loadError)
    loader()
end
Load("core/RuntimeLifecycle.lua")
Load("core/Slash.lua")

local Lifecycle = assert(IG.RuntimeLifecycle)
local Slash = assert(IG.Slash)
local slashEntry = assert(SlashCmdList.INTERRUPTGLOW)
assert(SLASH_INTERRUPTGLOW1 == "/iglow")
assert(Lifecycle:Initialize() == true)
assert(Lifecycle:IsActive() and runtimeEventsEnabled)
assert(calls.buttonsAttach == 1 and calls.castAttach == 1 and calls.cdmAttach == 1)

-- The slash command must use the lifecycle owner so disable detaches providers,
-- unregisters events, clears work and stops a currently active preview.
IG.testMode = true
slashEntry("disable")
assert(IG.DB.enabled == false)
assert(not Lifecycle:IsActive() and not runtimeEventsEnabled)
assert(IG.testMode == false, "slash disable left highlight preview active")
assert(calls.buttonsDetach == 1 and calls.castDetach == 1 and calls.cdmDetach == 1)
assert(calls.eventsDisable == 1 and calls.refreshVisuals == 1)

-- Repeated disable is idempotent through the same lifecycle path.
slashEntry("disable")
assert(calls.buttonsDetach == 1 and calls.castDetach == 1 and calls.cdmDetach == 1)
assert(calls.eventsDisable == 1)

-- Slash enable updates the saved preference but defers all attachment and
-- discovery until combat ends; the lifecycle then completes one activation.
combat = true
slashEntry("enable")
assert(IG.DB.enabled == true)
assert(Lifecycle.enablePending == true and not Lifecycle:IsActive())
assert(not runtimeEventsEnabled)
assert(calls.buttonsAttach == 1 and calls.eventsEnable == 1)
assert(printed[#printed] == "Enable queued until after combat.")

combat = false
assert(Lifecycle:OnCombatEnded() == true)
assert(Lifecycle:IsActive() and runtimeEventsEnabled)
assert(calls.buttonsAttach == 2 and calls.castAttach == 2 and calls.cdmAttach == 2)
assert(calls.eventsEnable == 2 and calls.createPending == 2)

print("SLASH LIFECYCLE ROUTING TEST PASSED")
