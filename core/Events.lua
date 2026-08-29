local IG = _G.InterruptGlow
if not IG then return end

local _G = _G
local CreateFrame = _G.CreateFrame
local EventUtil = _G.EventUtil
local IsLoggedIn = _G.IsLoggedIn
local type = type
local pcall = pcall
local select = select

local frame = CreateFrame("Frame")
IG.EventFrame = frame

-- These events exist only while the addon runtime is active. The master switch
-- unregisters them rather than paying a permanent Lua dispatch cost merely to
-- discover that RuntimeActive() is false.
local RUNTIME_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_COMBAT_CONFIG_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "PLAYER_PVP_TALENT_UPDATE",
    "SPELLS_CHANGED",
    "UPDATE_VEHICLE_ACTIONBAR",
    "SPELL_UPDATE_COOLDOWN",
    "SPELL_UPDATE_CHARGES",
    "SPELL_UPDATE_USABLE",
    "ACTION_USABLE_CHANGED",
    "PET_BAR_UPDATE",
    "PET_BAR_UPDATE_COOLDOWN",
    "PET_BAR_UPDATE_USABLE",
    "PET_UI_UPDATE",
}

-- PLAYER_REGEN_ENABLED completes an enable requested in combat and finishes a
-- deferred Settings build. Restriction transitions remain available to an
-- explicit runtime capture even if the feature itself is disabled.
local PERSISTENT_EVENTS = {
    "PLAYER_REGEN_ENABLED",
    "ADDON_RESTRICTION_STATE_CHANGED",
}

local function RuntimeActive()
    local lifecycle = IG.RuntimeLifecycle
    if lifecycle and type(lifecycle.IsActive) == "function" then
        return lifecycle:IsActive()
    end
    return IG.DB and IG.DB.enabled == true
end

local function RuntimeNeedsReadiness()
    return RuntimeActive()
        and IG.NeedsReadinessRuntime
        and IG:NeedsReadinessRuntime() == true
end

local function RegisterPersistentEvents()
    if IG.runtimePersistentEventsRegistered then return false end
    IG.runtimePersistentEventsRegistered = true
    for index = 1, #PERSISTENT_EVENTS do
        frame:RegisterEvent(PERSISTENT_EVENTS[index])
    end
    return true
end

function IG:SetRuntimeEventsEnabled(enabled)
    enabled = enabled == true
    if (IG.runtimeEventsRegistered == true) == enabled then return false end

    if enabled then
        for index = 1, #RUNTIME_EVENTS do frame:RegisterEvent(RUNTIME_EVENTS[index]) end
        frame:RegisterUnitEvent("UNIT_PET", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")

        -- Both events carry unitTarget and Blizzard's own ActionButton event
        -- frame registers them for player. Party/raid crowd-control changes must
        -- not wake every interrupt ability.
        frame:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", "player")
        frame:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", "player")
    else
        for index = 1, #RUNTIME_EVENTS do frame:UnregisterEvent(RUNTIME_EVENTS[index]) end
        frame:UnregisterEvent("UNIT_PET")
        frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        frame:UnregisterEvent("LOSS_OF_CONTROL_ADDED")
        frame:UnregisterEvent("LOSS_OF_CONTROL_UPDATE")
    end

    IG.runtimeEventsRegistered = enabled
    IG:BumpStat(enabled and "lifecycle.runtimeEventsRegistered"
        or "lifecycle.runtimeEventsUnregistered")
    return true
end

local function InitializeRuntime()
    if IG.runtimeInitialized then return end
    IG.runtimeInitialized = true
    IG.playerLoginSeen = true
    RegisterPersistentEvents()

    if IG.RuntimeLifecycle and type(IG.RuntimeLifecycle.Initialize) == "function" then
        IG.RuntimeLifecycle:Initialize()
    else
        if IG.Data then IG.Data:RefreshActiveSpec() end
        if IG.Buttons then IG.Buttons:Attach(true) end
        if IG.CastTracking then IG.CastTracking:Attach() end
        if IG.CDM then IG.CDM:Attach(true) end
        if IG.Glow then IG.Glow:CreatePendingOverlays() end
        IG:SetRuntimeEventsEnabled(true)
        IG:MarkCooldownDirty(false)
    end

    if IG.DB.debug and IG.Debug then IG.Debug:Log("init", "version=" .. tostring(IG.version)) end
end

local function ScheduleInitialization()
    if EventUtil and type(EventUtil.ContinueOnPlayerLogin) == "function" then
        EventUtil.ContinueOnPlayerLogin(InitializeRuntime)
        return
    end

    if type(IsLoggedIn) == "function" then
        local ok, loggedIn = pcall(IsLoggedIn)
        if ok and loggedIn == true then
            InitializeRuntime()
            return
        end
    end

    frame:RegisterEvent("PLAYER_LOGIN")
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        frame:UnregisterEvent("PLAYER_LOGIN")
        InitializeRuntime()
        return
    end

    if not IG.runtimeInitialized then return end

    if event == "PLAYER_REGEN_ENABLED" then
        if IG.RuntimeLifecycle and type(IG.RuntimeLifecycle.OnCombatEnded) == "function" then
            IG.RuntimeLifecycle:OnCombatEnded()
        elseif RuntimeActive() and IG.Glow then
            IG.Glow:CreatePendingOverlays()
        end
        if IG.Options and type(IG.Options.OnCombatEnded) == "function" then
            IG.Options:OnCombatEnded()
        end
        return
    end

    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local restrictionType, state = ...
        if IG.RuntimeProbe then
            IG.RuntimeProbe:OnRestrictionStateChanged(restrictionType, state)
        end
        if RuntimeActive() then
            IG:BumpStat("events.restrictionChanged")
            IG:MarkCastDirty()
            IG:MarkCooldownDirty(false)
        end
        return
    end

    -- Defensive guard for a signal already queued by the client while the
    -- master switch was unregistering runtime events.
    if not RuntimeActive() then return end

    if event == "PLAYER_ENTERING_WORLD" then
        if IG.Buttons then IG.Buttons:RefreshPetButtons() end
        if IG.CastTracking and type(IG.CastTracking.ResetAllIdentities) == "function" then
            IG.CastTracking:ResetAllIdentities(event)
        else
            IG:MarkCastDirty()
        end
        IG:MarkCooldownDirty(false)
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        if IG.Glow then IG.Glow:RefreshUnitRelation() end
        if IG.CastTracking and type(IG.CastTracking.ResetUnitIdentity) == "function" then
            IG.CastTracking:ResetUnitIdentity("target", event)
        elseif IG.CastTracking then
            IG.CastTracking:RefreshUnit("target", nil, true)
        end
        if IG.Glow then IG.Glow:RefreshUnit("focus") end
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        if IG.Glow then IG.Glow:RefreshUnitRelation() end
        if IG.CastTracking and type(IG.CastTracking.ResetUnitIdentity) == "function" then
            IG.CastTracking:ResetUnitIdentity("focus", event)
        elseif IG.CastTracking then
            IG.CastTracking:RefreshUnit("focus", nil, true)
        end
        if IG.Glow then IG.Glow:RefreshUnit("target") end
        return
    end

    if event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "ACTIVE_COMBAT_CONFIG_CHANGED"
        or event == "ACTIVE_TALENT_GROUP_CHANGED"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "PLAYER_PVP_TALENT_UPDATE"
        or event == "SPELLS_CHANGED"
    then
        IG:MarkSpecDirty()
        return
    end

    if event == "UPDATE_VEHICLE_ACTIONBAR" then
        IG:MarkAllButtonsDirty()
        IG:MarkCooldownDirty(false)
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not RuntimeNeedsReadiness() then return end

        -- This event is SecretWhenUnitSpellCastRestricted. RegisterUnitEvent
        -- narrows dispatch to player/pet, but does not make its payload ordinary.
        -- Read only access-confirmed fields; an inaccessible payload still
        -- invalidates the tiny active interrupt set so stale ready state cannot
        -- survive a successful secret interrupt cast.
        local unit = select(1, ...)
        local spellID = select(3, ...)
        if not IG.CanAccess(unit)
            or not IG.CanAccess(spellID)
            or type(unit) ~= "string"
            or type(spellID) ~= "number"
        then
            IG:BumpStat("events.restrictedSpellSucceeded")
            IG:MarkCooldownDirty(false)
            return
        end

        if IG.Data then
            local sourceKind = unit == "pet" and "pet" or "spell"
            if IG.Data:GetCanonicalSpellID(spellID, sourceKind) then
                -- This is only an interrupt-source invalidation signal. It is
                -- never treated as proof that a GCD started or ended.
                IG:BumpStat("events.interruptSucceeded")
                IG:MarkCooldownDirty(false)
            end
        end
        return
    end

    if event == "SPELL_UPDATE_COOLDOWN" then
        if not RuntimeNeedsReadiness() then return end

        local spellID, baseSpellID, category, startRecoveryCategory = ...
        if IG.Data and not IG.Data:ShouldRefreshForCooldownEvent(
            spellID,
            baseSpellID,
            category,
            startRecoveryCategory
        ) then
            IG:BumpStat("events.spellCooldownIgnored")
            return
        end

        -- Readiness ignores the global cooldown through the duration API's
        -- ignoreGlobalCooldown flag. `isOnGCD` is not collected as a positive
        -- readiness hint because it cannot prove absence of a personal cooldown.
        IG:BumpStat("events.spellCooldown")
        IG:MarkCooldownDirty(false)
        return
    end

    if event == "ACTION_USABLE_CHANGED" then
        if IG.Usability then
            -- Identity changes for conditional macros must be consumed even
            -- while no relevant cast is active. MarkCooldownDirty itself keeps
            -- readiness work asleep when there is nothing to display.
            IG.Usability:OnActionUsableChanged(...)
        end
        return
    end

    if event == "SPELL_UPDATE_USABLE" then
        if RuntimeNeedsReadiness() and IG.Usability and IG.Usability:HasTrackedSpellSource() then
            IG:MarkCooldownDirty(false)
        end
        return
    end

    if event == "SPELL_UPDATE_CHARGES"
        or event == "LOSS_OF_CONTROL_ADDED"
        or event == "LOSS_OF_CONTROL_UPDATE"
    then
        if RuntimeNeedsReadiness() then
            IG:BumpStat("events.otherCooldown")
            IG:MarkCooldownDirty(false)
        end
        return
    end

    if event == "PET_BAR_UPDATE" or event == "PET_UI_UPDATE" or event == "UNIT_PET" then
        if IG.Buttons then IG.Buttons:RefreshPetButtons() end
        IG:MarkCooldownDirty(false)
        return
    end

    if event == "PET_BAR_UPDATE_COOLDOWN" or event == "PET_BAR_UPDATE_USABLE" then
        IG:MarkCooldownDirty(false)
        return
    end
end)

RegisterPersistentEvents()
ScheduleInitialization()

IG:RegisterModule("RuntimeEventPolicy", {
    masterDisableUnregistersRuntimeEvents = true,
    persistentEvents = PERSISTENT_EVENTS,
    runtimeEvents = RUNTIME_EVENTS,
    playerLossOfControlUsesUnitFilter = true,
})
