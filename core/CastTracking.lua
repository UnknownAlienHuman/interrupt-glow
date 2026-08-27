local IG = _G.InterruptGlow
if not IG then return end

local CastTracking = {
    attached = false,
    unitFrames = {},
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
local pcall = pcall
local type = type
local pairs = pairs

local UNITS = { "target", "focus" }

local function SafeUnitBoolean(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or not IG.CanAccess(value) then return nil end
    if value == true then return true end
    if value == false then return false end
    return nil
end

local function CanHarm(unit)
    local exists = SafeUnitBoolean(UnitExists, unit)
    if exists ~= true then return false end

    local dead = SafeUnitBoolean(UnitIsDeadOrGhost, unit)
    if dead == true then return false end

    local canAttack = SafeUnitBoolean(UnitCanAttack, "player", unit)
    return canAttack == true
end

local function IsRelevantCast(active, hostile, niState)
    if active ~= true or hostile ~= true then return false end
    if niState == "not-interruptible" then return false end
    if niState == "unknown" and IG.DB.strictNI == true then return false end
    return true
end

-- Presence is determined only through NeverSecret fields. All other return
-- values remain local to this call. notInterruptible is consumed directly by
-- the visual sink and is never inserted into addon state.
local function SnapshotCast(unit)
    if type(UnitCastingInfo) == "function" then
        local ok,
            _name,
            _displayName,
            _textureID,
            _startTimeMs,
            _endTimeMs,
            isTradeskill,
            _castID,
            notInterruptible,
            _castingSpellID,
            castBarID,
            _delayTimeMs = pcall(UnitCastingInfo, unit)

        if ok and IG.CanAccess(isTradeskill) and isTradeskill ~= nil then
            if not IG.CanAccess(castBarID) then castBarID = nil end
            return true, notInterruptible, castBarID, false
        end
    end

    if type(UnitChannelInfo) == "function" then
        local ok,
            _name,
            _displayName,
            _textureID,
            _startTimeMs,
            _endTimeMs,
            isTradeskill,
            notInterruptible,
            _spellID,
            _isEmpowered,
            _numEmpowerStages,
            castBarID = pcall(UnitChannelInfo, unit)

        if ok and IG.CanAccess(isTradeskill) and isTradeskill ~= nil then
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
        if IG.Glow then
            IG.Glow:ApplyUnitInterruptibility(unit, rawNotInterruptible, true)
        end
        IG:BumpStat("secret.castInterruptibilityRestricted")
    end
end

function CastTracking:RefreshUnit(unit, forcedNotInterruptible, forceReadinessRefresh)
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

    self:ApplyInterruptibility(unit, rawNotInterruptible, active, forcedNotInterruptible)
    changed = changed or oldNIState ~= state.niState

    -- Target/focus cast feedback is latency-sensitive and bounded by the small
    -- number of currently bound interrupt buttons, so update it synchronously.
    if IG.Glow then IG.Glow:RefreshUnit(unit) end

    -- The background cooldown driver deliberately sleeps while no relevant cast
    -- exists. Re-read readiness once when a new cast becomes relevant, when the
    -- cast identity changes, when hostility/interruptibility makes an existing
    -- cast newly relevant, or when target/focus itself changed.
    local castIdentityChanged = active and (
        not oldActive
        or oldCastBarID ~= safeCastBarID
        or oldIsChannel ~= isChannel
    )
    local newRelevant = IsRelevantCast(active, hostile, state.niState)
    if newRelevant and (
        forceReadinessRefresh == true
        or castIdentityChanged
        or not oldRelevant
    ) then
        IG:MarkCooldownDirty(false)
    end

    if changed then
        IG:BumpStat("cast.transitions")
        if IG.DB.debug and IG.Debug then
            IG.Debug:Log("cast", ("unit=%s active=%s hostile=%s channel=%s ni=%s")
                :format(unit, tostring(active), tostring(hostile), tostring(isChannel), tostring(state.niState)))
        end
    end
end

function CastTracking:RefreshAll()
    if IG.Glow then IG.Glow:RefreshUnitRelation() end
    self:RefreshUnit("target")
    self:RefreshUnit("focus")
end

function CastTracking:OnUnitEvent(unit, event)
    IG:BumpStat("events.cast")

    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        self:RefreshUnit(unit, false)
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        self:RefreshUnit(unit, true)
    else
        self:RefreshUnit(unit)
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
        "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_EMPOWER_START",
        "UNIT_SPELLCAST_EMPOWER_STOP",
        "UNIT_SPELLCAST_INTERRUPTIBLE",
        "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
        "UNIT_FACTION",
        "UNIT_FLAGS",
        "UNIT_TARGETABLE_CHANGED",
    }

    for index = 1, #events do
        frame:RegisterUnitEvent(events[index], unit)
    end

    frame:SetScript("OnEvent", function(_, event)
        CastTracking:OnUnitEvent(unit, event)
    end)
    return frame
end

function CastTracking:Attach()
    if self.attached then return end
    self.attached = true

    for index = 1, #UNITS do
        local unit = UNITS[index]
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
    self.attached = false
end
