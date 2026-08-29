local IG = _G.InterruptGlow
if not IG then return end

local CastTracking = {
    attached = false,
    unitFrames = {},
    channelSuppressed = {
        target = false,
        focus = false,
    },
}
IG.CastTracking = CastTracking
IG:RegisterModule("CastTracking", CastTracking)

local _G = _G
local CreateFrame = _G.CreateFrame
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitExists = _G.UnitExists
local UnitCanAttack = _G.UnitCanAttack
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local type = type
local pairs = pairs
local select = select

local UNITS = { "target", "focus" }

local function SafeUnitBoolean(fn, ...)
    if type(fn) ~= "function" then return nil end

    local value = fn(...)
    if not IG.CanAccess(value) then return nil end
    if value == true then return true end
    if value == false then return false end
    return nil
end

local function CanHarm(unit)
    local exists = SafeUnitBoolean(UnitExists, unit)
    if exists ~= true then return false end

    -- Unknown/inaccessible alive state is not proof that a unit is a valid
    -- hostile interrupt target. Require an explicit accessible false.
    local dead = SafeUnitBoolean(UnitIsDeadOrGhost, unit)
    if dead ~= false then return false end

    local canAttack = SafeUnitBoolean(UnitCanAttack, "player", unit)
    return canAttack == true
end

local function IsRelevantCast(active, hostile, niState)
    if active ~= true or hostile ~= true then return false end
    if niState == "not-interruptible" then return false end
    if niState == "unknown" and IG.DB.strictNI == true then return false end
    return true
end

local function SafeEventCastBarID(value)
    if IG.CanAccess(value) and type(value) == "number" then return value end
    return nil
end

-- The generated 12.1 event contract marks castBarID NeverSecret. Select only
-- that return position from otherwise secret-capable event payloads; castGUID,
-- spellID, interruptedBy and complete are never bound into addon locals.
local function GetEventCastBarID(event, ...)
    if event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET"
    then
        return SafeEventCastBarID(select(4, ...))
    elseif event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
    then
        return SafeEventCastBarID(select(5, ...))
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        return SafeEventCastBarID(select(6, ...))
    end
    return nil
end

local function IsStaleCastEvent(state, eventCastBarID)
    return state ~= nil
        and type(eventCastBarID) == "number"
        and type(state.castBarID) == "number"
        and eventCastBarID ~= state.castBarID
end

function CastTracking:SetChannelSuppressed(unit, suppressed, reason)
    suppressed = suppressed == true
    self.channelSuppressed[unit] = suppressed

    local state = IG.CastState[unit]
    if state then
        state.channelSuppressed = suppressed
        if reason then state.lastEvent = reason end
    end
end

-- UnitChannelInfo has an active upstream stale/phantom family (#777/#784/#834).
-- Once a synchronous channel/empower stop is observed, that event is more
-- authoritative than a subsequent polling snapshot. Suppression is cleared by
-- a real start event or by an explicit unit-identity reset.
local function SnapshotCast(unit)
    if type(UnitCastingInfo) == "function" then
        local _name,
            _displayName,
            _textureID,
            _startTimeMs,
            _endTimeMs,
            isTradeskill,
            _castID,
            notInterruptible,
            _castingSpellID,
            castBarID,
            _delayTimeMs = UnitCastingInfo(unit)

        if IG.CanAccess(isTradeskill) and isTradeskill ~= nil then
            if not IG.CanAccess(castBarID) then castBarID = nil end
            return true, notInterruptible, castBarID, false
        end
    end

    if CastTracking.channelSuppressed[unit] == true then
        IG:BumpStat("cast.channelSnapshotSuppressed")
        return false, nil, nil, false
    end

    if type(UnitChannelInfo) == "function" then
        local _name,
            _displayName,
            _textureID,
            _startTimeMs,
            _endTimeMs,
            isTradeskill,
            notInterruptible,
            _spellID,
            _isEmpowered,
            _numEmpowerStages,
            castBarID = UnitChannelInfo(unit)

        if IG.CanAccess(isTradeskill) and isTradeskill ~= nil then
            if not IG.CanAccess(castBarID) then castBarID = nil end
            return true, notInterruptible, castBarID, true
        end
    end

    return false, nil, nil, false
end

function CastTracking:ApplyInterruptibility(unit, rawNotInterruptible, active, forcedNotInterruptible)
    local state = IG.CastState[unit]
    if not state then return end

    if not active then
        state.niState = "none"
        if IG.Glow then IG.Glow:ApplyUnitInterruptibility(unit, false, false) end
        return
    end

    if forcedNotInterruptible ~= nil then
        state.niState = forcedNotInterruptible and "not-interruptible" or "interruptible"
        if IG.Glow then IG.Glow:ApplyUnitInterruptibility(unit, forcedNotInterruptible, true) end
        return
    end

    if IG.CanAccess(rawNotInterruptible) then
        if rawNotInterruptible == true then
            state.niState = "not-interruptible"
        elseif rawNotInterruptible == false then
            state.niState = "interruptible"
        else
            state.niState = "unknown"
        end
        if IG.Glow then IG.Glow:ApplyUnitInterruptibility(unit, rawNotInterruptible, true) end
    else
        state.niState = "restricted"
        if IG.Glow then IG.Glow:ApplyUnitInterruptibility(unit, rawNotInterruptible, true) end
        IG:BumpStat("secret.castInterruptibilityRestricted")
    end
end

function CastTracking:ClearUnit(unit, reason, eventCastBarID)
    local state = IG.CastState[unit]
    if not state then return false end

    if IsStaleCastEvent(state, eventCastBarID) then
        IG:BumpStat("cast.staleStopIgnored")
        return false
    end

    local changed = state.active == true
        or state.hostile == true
        or state.castBarID ~= nil
        or state.isChannel == true
        or state.niState ~= "none"

    state.active = false
    state.hostile = false
    state.castBarID = nil
    state.isChannel = false
    state.lastEvent = reason
    state.channelSuppressed = self.channelSuppressed[unit] == true
    self:ApplyInterruptibility(unit, false, false)

    if IG.Glow then IG.Glow:RefreshUnit(unit) end

    if changed then
        IG:BumpStat("cast.transitions")
        IG:BumpStat("cast.eventStops")
        if IG.DB.debug and IG.Debug then
            IG.Debug:Log("cast", ("unit=%s active=false reason=%s suppressed=%s")
                :format(unit, tostring(reason), tostring(state.channelSuppressed)))
        end
    end
    return true
end

function CastTracking:RefreshUnit(unit, forcedNotInterruptible, forceReadinessRefresh, reason)
    local state = IG.CastState[unit]
    if not state then return end

    local active, rawNotInterruptible, castBarID, isChannel = SnapshotCast(unit)
    local hostile = active and CanHarm(unit) or false

    local safeCastBarID = nil
    if IG.CanAccess(castBarID) and type(castBarID) == "number" then
        safeCastBarID = castBarID
    end

    local oldActive = state.active
    local oldHostile = state.hostile
    local oldCastBarID = state.castBarID
    local oldIsChannel = state.isChannel
    local oldNIState = state.niState
    local oldRelevant = IsRelevantCast(oldActive, oldHostile, oldNIState)

    local changed = state.active ~= active
        or state.hostile ~= hostile
        or state.castBarID ~= safeCastBarID
        or state.isChannel ~= isChannel

    state.active = active
    state.hostile = hostile
    state.castBarID = safeCastBarID
    state.isChannel = isChannel
    state.channelSuppressed = self.channelSuppressed[unit] == true
    if reason then state.lastEvent = reason end

    self:ApplyInterruptibility(unit, rawNotInterruptible, active, forcedNotInterruptible)
    changed = changed or oldNIState ~= state.niState

    local castIdentityChanged = active and (
        not oldActive
        or oldCastBarID ~= safeCastBarID
        or oldIsChannel ~= isChannel
    )
    local newRelevant = IsRelevantCast(active, hostile, state.niState)
    local needsReadinessRefresh = newRelevant and (
        forceReadinessRefresh == true
        or castIdentityChanged
        or not oldRelevant
    )
    if needsReadinessRefresh then IG:MarkCooldownDirty(false) end

    if IG.Glow then IG.Glow:RefreshUnit(unit) end

    if changed then
        IG:BumpStat("cast.transitions")
        if IG.DB.debug and IG.Debug then
            IG.Debug:Log("cast", ("unit=%s active=%s hostile=%s channel=%s ni=%s reason=%s suppressed=%s")
                :format(
                    unit,
                    tostring(active),
                    tostring(hostile),
                    tostring(isChannel),
                    tostring(state.niState),
                    tostring(reason),
                    tostring(state.channelSuppressed)
                ))
        end
    end
end

function CastTracking:ResetUnitIdentity(unit, reason)
    self:SetChannelSuppressed(unit, false, reason or "UNIT_IDENTITY_RESET")
    self:RefreshUnit(unit, nil, true, reason or "UNIT_IDENTITY_RESET")
end

function CastTracking:ResetAllIdentities(reason)
    if IG.Glow then IG.Glow:RefreshUnitRelation() end
    for index = 1, #UNITS do
        self:ResetUnitIdentity(UNITS[index], reason or "WORLD_IDENTITY_RESET")
    end
end

function CastTracking:RefreshAll()
    if IG.Glow then IG.Glow:RefreshUnitRelation() end
    self:RefreshUnit("target", nil, false, "REFRESH_ALL")
    self:RefreshUnit("focus", nil, false, "REFRESH_ALL")
end

function CastTracking:OnUnitEvent(unit, event, ...)
    IG:BumpStat("events.cast")

    if event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START"
    then
        self:SetChannelSuppressed(unit, false, event)
        self:RefreshUnit(unit, nil, false, event)
        return
    end

    if event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP"
    then
        local eventCastBarID = GetEventCastBarID(event, ...)
        local state = IG.CastState[unit]
        if IsStaleCastEvent(state, eventCastBarID) then
            IG:BumpStat("cast.staleStopIgnored")
            return
        end

        self:SetChannelSuppressed(unit, true, event)
        if state and state.active == true and state.isChannel ~= true then
            -- A delayed channel/empower stop without a usable castBarID must not
            -- delete a newer ordinary cast. Keep suppression so the stale
            -- UnitChannelInfo family still cannot resurrect.
            IG:BumpStat("cast.channelStopIgnoredForOrdinaryCast")
            return
        end
        self:ClearUnit(unit, event, eventCastBarID)
        return
    end

    if event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
    then
        local state = IG.CastState[unit]
        local eventCastBarID = GetEventCastBarID(event, ...)
        if IsStaleCastEvent(state, eventCastBarID) then
            IG:BumpStat("cast.staleStopIgnored")
            return
        end
        if state and state.isChannel == true then
            self:SetChannelSuppressed(unit, true, event)
        end
        self:ClearUnit(unit, event, eventCastBarID)
        return
    end

    if event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_UPDATE"
    then
        if self.channelSuppressed[unit] == true then
            IG:BumpStat("cast.suppressedUpdateIgnored")
            return
        end
        self:RefreshUnit(unit, nil, false, event)
        return
    end

    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        self:RefreshUnit(unit, false, false, event)
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        self:RefreshUnit(unit, true, false, event)
    else
        self:RefreshUnit(unit, nil, false, event)
    end
end

local function CreateUnitWatcher(unit)
    local frame = CreateFrame("Frame")
    frame.unit = unit

    local events = {
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_FAILED_QUIET",
        "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_UPDATE",
        "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_EMPOWER_START",
        "UNIT_SPELLCAST_EMPOWER_UPDATE",
        "UNIT_SPELLCAST_EMPOWER_STOP",
        "UNIT_SPELLCAST_INTERRUPTIBLE",
        "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
        "UNIT_FACTION",
        "UNIT_FLAGS",
        "UNIT_TARGETABLE_CHANGED",
    }

    for index = 1, #events do frame:RegisterUnitEvent(events[index], unit) end

    frame:SetScript("OnEvent", function(_, event, ...)
        CastTracking:OnUnitEvent(unit, event, ...)
    end)
    return frame
end

function CastTracking:Attach()
    if self.attached then return end
    self.attached = true

    for index = 1, #UNITS do
        local unit = UNITS[index]
        self.channelSuppressed[unit] = false
        self.unitFrames[unit] = CreateUnitWatcher(unit)
    end

    self:RefreshAll()
end

function CastTracking:Detach()
    for _, frame in pairs(self.unitFrames) do
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
    end
    self.unitFrames = {}
    for index = 1, #UNITS do
        self.channelSuppressed[UNITS[index]] = false
    end
    self.attached = false
end
