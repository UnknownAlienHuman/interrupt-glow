local IG = _G.InterruptGlow
if not IG then return end

local _G = _G
local CreateFrame = _G.CreateFrame
local EventUtil = _G.EventUtil
local IsLoggedIn = _G.IsLoggedIn
local type = type
local pcall = pcall

local frame = CreateFrame("Frame")
IG.EventFrame = frame

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "SPELLS_CHANGED",
    "UPDATE_VEHICLE_ACTIONBAR",
    "SPELL_UPDATE_COOLDOWN",
    "SPELL_UPDATE_CHARGES",
    "PET_BAR_UPDATE",
    "PET_BAR_UPDATE_COOLDOWN",
    "PET_UI_UPDATE",
    "ADDON_RESTRICTION_STATE_CHANGED",
}

local function RegisterRuntimeEvents()
    if IG.runtimeEventsRegistered then return end
    IG.runtimeEventsRegistered = true

    for index = 1, #EVENTS do frame:RegisterEvent(EVENTS[index]) end
    frame:RegisterUnitEvent("UNIT_PET", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
    frame:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", "player")
    frame:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", "player")
end

local function InitializeRuntime()
    if IG.runtimeInitialized then return end
    IG.runtimeInitialized = true
    IG.playerLoginSeen = true
    RegisterRuntimeEvents()

    if IG.Data then IG.Data:RefreshActiveSpec() end
    -- Attach callbacks first and enumerate each already-loaded provider exactly
    -- once inside the same bounded startup pass.
    if IG.Buttons then IG.Buttons:Attach(true) end
    if IG.CastTracking then IG.CastTracking:Attach() end
    if IG.CDM then IG.CDM:Attach(true) end

    -- All later structure changes arrive through callbacks, provider lifecycle
    -- hooks, or an explicit manual rescan.
    if IG.Glow then IG.Glow:CreatePendingOverlays() end

    IG:MarkCooldownDirty(false)
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

    if event == "PLAYER_ENTERING_WORLD" then
        -- Loading screens do not require another registry walk. Refresh only
        -- volatile state whose backing unit/pet objects may have changed.
        if IG.Buttons then IG.Buttons:RefreshPetButtons() end
        IG:MarkCastDirty()
        IG:MarkCooldownDirty(false)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if IG.Glow then IG.Glow:CreatePendingOverlays() end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        if IG.Glow then IG.Glow:RefreshUnitRelation() end
        if IG.CastTracking then IG.CastTracking:RefreshUnit("target", nil, true) end
        if IG.Glow then IG.Glow:RefreshUnit("focus") end
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        if IG.Glow then IG.Glow:RefreshUnitRelation() end
        if IG.CastTracking then IG.CastTracking:RefreshUnit("focus", nil, true) end
        if IG.Glow then IG.Glow:RefreshUnit("target") end
        return
    end

    if event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "SPELLS_CHANGED"
    then
        -- These signals commonly cluster during one spec/talent transition.
        -- Coalesce them into one spec data rebuild and one button pass.
        IG:MarkSpecDirty()
        return
    end

    if event == "UPDATE_VEHICLE_ACTIONBAR" then
        IG:MarkAllButtonsDirty()
        IG:MarkCooldownDirty(false)
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _castGUID, spellID = ...
        if IG.CanAccess(spellID) and type(spellID) == "number" and IG.Data then
            local sourceKind = unit == "pet" and "pet" or "spell"
            if IG.Data:GetCanonicalSpellID(spellID, sourceKind) then
                IG:BumpStat("events.interruptSucceeded")
                -- Immediate post-cast refresh prevents stale ready glow if the
                -- broader cooldown event is delayed or coalesced by the client.
                IG:MarkCooldownDirty(false)
            end
        end
        return
    end

    if event == "SPELL_UPDATE_COOLDOWN" then
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
        IG:BumpStat("events.spellCooldown")
        if IG.Cooldown then IG.Cooldown:CaptureGCDHints() end
        IG:MarkCooldownDirty(true)
        return
    end

    if event == "SPELL_UPDATE_CHARGES"
        or event == "LOSS_OF_CONTROL_ADDED"
        or event == "LOSS_OF_CONTROL_UPDATE"
    then
        IG:BumpStat("events.otherCooldown")
        IG:MarkCooldownDirty(false)
        return
    end

    if event == "PET_BAR_UPDATE" or event == "PET_UI_UPDATE" or event == "UNIT_PET" then
        if IG.Buttons then IG.Buttons:RefreshPetButtons() end
        IG:MarkCooldownDirty(false)
        return
    end

    if event == "PET_BAR_UPDATE_COOLDOWN" then
        IG:MarkCooldownDirty(false)
        return
    end

    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- The payload is authoritative during dispatch; Blizzard documents
        -- IsAddOnRestrictionActive() as false while this event is executing.
        local _restrictionType, _state = ...
        IG:BumpStat("events.restrictionChanged")
        -- Defer one frame so APIs observe the new restriction state. Do not call
        -- IsAddOnRestrictionActive() from inside this event dispatch.
        IG:MarkCastDirty()
        IG:MarkCooldownDirty(false)
    end
end)

ScheduleInitialization()
