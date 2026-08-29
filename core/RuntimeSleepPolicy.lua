local IG = _G.InterruptGlow
if not IG or not IG.Buttons or not IG.Glow or not IG.CastTracking then return end
if IG.modules and IG.modules.RuntimeSleepPolicy then return end

local Buttons = IG.Buttons
local Glow = IG.Glow
local CastTracking = IG.CastTracking
local CDM = IG.CDM

local UNITS = { "target", "focus" }
local pairs = pairs
local type = type

local sleeping = false
local waking = false
local providerState = {
    buttonForge = false,
    dominos = false,
}

local function RuntimeEnabled()
    return IG.DB and IG.DB.enabled == true or IG.testMode == true
end

local function ClearCastState()
    for index = 1, #UNITS do
        local unit = UNITS[index]
        CastTracking.channelSuppressed[unit] = false

        local state = IG.CastState[unit]
        if state then
            state.active = false
            state.hostile = false
            state.castBarID = nil
            state.isChannel = false
            state.niState = "none"
            state.channelSuppressed = false
        end

        Glow:ApplyUnitInterruptibility(unit, false, false)
        Glow:RefreshUnit(unit)
    end
end

local function Sleep()
    if sleeping then return end
    sleeping = true

    providerState.buttonForge = Buttons.buttonForgeAttached == true
    providerState.dominos = Buttons.dominosAttached == true
    Buttons.buttonForgeAttached = false
    Buttons.dominosAttached = false

    ClearCastState()
    Glow:SetRuntimeWorkerEnabled(false)
    IG:BumpStat("runtime.masterDisableSleeps")
end

local function Wake()
    if not sleeping or waking or not RuntimeEnabled() then return end
    waking = true
    sleeping = false

    if Buttons.attached then
        if providerState.buttonForge and _G.ButtonForge_API1 then
            Buttons.buttonForgeAttached = true
        end
        if providerState.dominos and Buttons.DominosActionButtons then
            Buttons.dominosAttached = true
        end
    end
    providerState.buttonForge = false
    providerState.dominos = false

    -- Rebuild from authoritative current state once. Work remains coalesced by
    -- the shared RunOnce flush; no provider callback performs reconciliation.
    IG:MarkAllButtonsDirty()
    IG:MarkCastDirty()
    IG:MarkCooldownDirty(false)
    if CDM and CDM.attached and IG.DB.cdm then CDM:ObserveExistingItems() end

    IG:BumpStat("runtime.masterEnableWakes")
    waking = false
end

local originalNativeActionChanged = Buttons.OnNativeActionChanged
function Buttons:OnNativeActionChanged(...)
    if not RuntimeEnabled() then
        Sleep()
        return
    end
    Wake()
    return originalNativeActionChanged(self, ...)
end

local originalLABButtonUpdate = Buttons.OnLABButtonUpdate
function Buttons:OnLABButtonUpdate(...)
    if not RuntimeEnabled() then
        Sleep()
        return
    end
    Wake()
    return originalLABButtonUpdate(self, ...)
end

local originalLABContentsChanged = Buttons.OnLABButtonContentsChanged
function Buttons:OnLABButtonContentsChanged(...)
    if not RuntimeEnabled() then
        Sleep()
        return
    end
    Wake()
    return originalLABContentsChanged(self, ...)
end

local originalRefreshUnit = CastTracking.RefreshUnit
function CastTracking:RefreshUnit(...)
    if not RuntimeEnabled() then
        Sleep()
        return
    end
    Wake()
    return originalRefreshUnit(self, ...)
end

local originalRefreshAll = CastTracking.RefreshAll
function CastTracking:RefreshAll(...)
    if not RuntimeEnabled() then
        Sleep()
        return
    end
    Wake()
    return originalRefreshAll(self, ...)
end

local originalOnUnitEvent = CastTracking.OnUnitEvent
function CastTracking:OnUnitEvent(...)
    if not RuntimeEnabled() then
        Sleep()
        return
    end
    Wake()
    return originalOnUnitEvent(self, ...)
end

local originalRefreshGlowAll = Glow.RefreshAll
function Glow:RefreshAll(...)
    if not RuntimeEnabled() then
        -- CandidateFor already rejects disabled output. Run one final normalized
        -- hide pass, then stop all expensive runtime paths.
        local result = originalRefreshGlowAll(self, ...)
        Sleep()
        return result
    end
    Wake()
    return originalRefreshGlowAll(self, ...)
end

local originalUpdateRuntimeDriver = Glow.UpdateRuntimeDriver
function Glow:UpdateRuntimeDriver(...)
    if not RuntimeEnabled() then
        Sleep()
        self:SetRuntimeWorkerEnabled(false)
        return
    end
    Wake()
    return originalUpdateRuntimeDriver(self, ...)
end

local originalCreatePendingOverlays = Glow.CreatePendingOverlays
function Glow:CreatePendingOverlays(...)
    if not RuntimeEnabled() then
        Sleep()
        return
    end
    Wake()
    return originalCreatePendingOverlays(self, ...)
end

IG:RegisterModule("RuntimeSleepPolicy", {
    nativeMouseoverCallbacksSleepWhenDisabled = true,
    labRefreshCallbacksSleepWhenDisabled = true,
    fixedUnitSnapshotsSleepWhenDisabled = true,
    providerHooksHaveCheapDisabledGuards = true,
    wakeUsesOneCoalescedAuthoritativeRefresh = true,
    exposesState = function() return sleeping end,
})
