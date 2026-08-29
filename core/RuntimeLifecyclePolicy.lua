local IG = _G.InterruptGlow
if not IG then return end

local Lifecycle = {
    initialized = false,
    active = false,
    enablePending = false,
}
IG.RuntimeLifecycle = Lifecycle
IG:RegisterModule("RuntimeLifecyclePolicy", Lifecycle)

local type = type

local function SetRuntimeEventsEnabled(enabled)
    if type(IG.SetRuntimeEventsEnabled) == "function" then
        IG:SetRuntimeEventsEnabled(enabled)
    end
end

local function ClearDirtyState()
    if IG.PendingButtons then IG:WipeMap(IG.PendingButtons) end

    local dirty = IG._dirty
    if dirty then
        dirty.spec = false
        dirty.allButtons = false
        dirty.cast = false
        dirty.cooldown = false
        dirty.visual = false
        dirty.pruneCaches = false
    end

    if IG.Cooldown and type(IG.Cooldown.ClearGCDHints) == "function" then
        IG.Cooldown:ClearGCDHints()
    end
end

local function StopAndClearPrewarm()
    local Glow = IG.Glow
    if not Glow then return end

    if type(Glow.DisablePrewarmWorker) == "function" then
        Glow:DisablePrewarmWorker()
    end
    if type(Glow.SetRuntimeWorkerEnabled) == "function" then
        Glow:SetRuntimeWorkerEnabled(false)
    end

    local head = Glow.prewarmHead or 1
    local tail = Glow.prewarmTail or 0
    local queue = Glow.prewarmQueue or {}
    for index = head, tail do
        local record = queue[index]
        if record then record.overlayQueued = false end
    end

    Glow.prewarmQueue = {}
    Glow.prewarmHead = 1
    Glow.prewarmTail = 0
    if Glow.prewarmQueued then IG:WipeMap(Glow.prewarmQueued) end
end

local function ClearCastState()
    local CastTracking = IG.CastTracking
    if not CastTracking or type(CastTracking.ClearUnit) ~= "function" then return end

    CastTracking:ClearUnit("target", "ADDON_DISABLED")
    CastTracking:ClearUnit("focus", "ADDON_DISABLED")
end

function Lifecycle:Deactivate()
    self.enablePending = false
    local wasActive = self.active == true

    -- Stop new native event traffic before provider/cast callback teardown. A
    -- signal already queued by the client is still rejected by RuntimeActive().
    SetRuntimeEventsEnabled(false)

    if wasActive then
        if IG.CDM and type(IG.CDM.Detach) == "function" then IG.CDM:Detach() end

        ClearCastState()
        if IG.CastTracking and type(IG.CastTracking.Detach) == "function" then
            IG.CastTracking:Detach()
        end
        if IG.Buttons and type(IG.Buttons.Detach) == "function" then
            IG.Buttons:Detach()
        end
    end

    self.active = false
    StopAndClearPrewarm()
    ClearDirtyState()

    -- Hide existing addon-owned regions immediately. No discovery, action API,
    -- cast API or cooldown API is required for this transition.
    if IG.Glow and type(IG.Glow.RefreshAll) == "function" then
        IG.Glow:RefreshAll()
    end

    if wasActive then IG:BumpStat("lifecycle.disabled") end
    return wasActive
end

function Lifecycle:Activate()
    if self.active then
        self.enablePending = false
        return false
    end

    -- Enabling can discover provider buttons and create reusable visual shells.
    -- Keep the whole attach/discovery boundary out of combat; the saved setting
    -- is applied immediately and PLAYER_REGEN_ENABLED completes activation.
    if IG:IsInCombat() then
        self.enablePending = true
        IG:BumpStat("lifecycle.enableDeferred")
        return false
    end

    self.enablePending = false

    if IG.Data and type(IG.Data.RefreshActiveSpec) == "function" then
        IG.Data:RefreshActiveSpec()
    end
    if IG.Buttons and type(IG.Buttons.Attach) == "function" then
        IG.Buttons:Attach(true)
    end
    if IG.CastTracking and type(IG.CastTracking.Attach) == "function" then
        IG.CastTracking:Attach()
    end
    if IG.DB.cdm == true and IG.CDM and type(IG.CDM.Attach) == "function" then
        IG.CDM:Attach(true)
    end

    self.active = true
    SetRuntimeEventsEnabled(true)

    if IG.Glow and type(IG.Glow.CreatePendingOverlays) == "function" then
        IG.Glow:CreatePendingOverlays()
    end

    IG:MarkAllButtonsDirty()
    IG:MarkCastDirty()
    IG:MarkCooldownDirty(false)
    IG:MarkVisualDirty()
    IG:BumpStat("lifecycle.enabled")
    return true
end

function Lifecycle:Initialize()
    if self.initialized then return self.active end
    self.initialized = true

    if IG.DB.enabled == true then
        self:Activate()
    else
        self:Deactivate()
    end
    return self.active
end

function Lifecycle:SetEnabled(enabled)
    enabled = enabled == true
    IG.DB.enabled = enabled

    if not self.initialized then
        self.enablePending = enabled
        return false
    end

    if enabled then return self:Activate() end
    return self:Deactivate()
end

function Lifecycle:OnCombatEnded()
    if not self.initialized or IG.DB.enabled ~= true then return false end
    if self.enablePending or not self.active then return self:Activate() end

    if IG.Glow and type(IG.Glow.CreatePendingOverlays) == "function" then
        IG.Glow:CreatePendingOverlays()
    end
    return false
end

function Lifecycle:IsActive()
    return self.initialized == true and self.active == true and IG.DB.enabled == true
end

Lifecycle.masterDisableDetachesProviders = true
Lifecycle.masterDisableDetachesCastWatchers = true
Lifecycle.masterDisableUnregistersRuntimeEvents = true
Lifecycle.masterDisableStopsWorkers = true
Lifecycle.enableDiscoveryIsOutOfCombat = true
Lifecycle.scheduledFlushIsAllowedToSelfDisable = true
