local IG = _G.InterruptGlow
if not IG then return end

local Private = IG.Private or {}
IG.Private = Private

InterruptGlowDB = InterruptGlowDB or {}
local DB = InterruptGlowDB
if DB.debug == nil then DB.debug = false end
if DB.debugChat == nil then DB.debugChat = false end
if DB.debugLevel == nil then DB.debugLevel = 2 end
if DB.debugKeep == nil then DB.debugKeep = 400 end
if DB.debugAutoShow == nil then DB.debugAutoShow = true end
if DB.cdText == nil then DB.cdText = false end
if DB.cdm == nil then DB.cdm = true end
if DB.strictNI == nil then DB.strictNI = true end
if type(DB.slots) ~= "table" then DB.slots = {} end
if type(DB.localCD) ~= "table" then DB.localCD = {} end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffInterruptGlow|r: " .. tostring(msg))
end

local function Debug(msg, level, category)
    local dbg = IG.Debug
    if dbg and type(dbg.Log) == "function" then
        dbg:Log(level or 2, category or "dbg", msg)
        if DB.debugChat then
            Print((category and (tostring(category) .. ": ") or "") .. tostring(msg))
        end
        return
    end

    if DB.debug then
        Print(tostring(msg))
    end
end

local function IsSecret(v)
    local fn = _G.issecretvalue
    if type(fn) == "function" then
        local ok, secret = pcall(fn, v)
        if ok then
            return secret == true
        end
    end

    local t = type(v)
    if t == "boolean" then
        local ok = pcall(function()
            if v then return true end
            return false
        end)
        return not ok
    elseif t == "number" then
        local ok = pcall(function()
            local _ = v + 0
        end)
        return not ok
    elseif t == "string" then
        local ok = pcall(function()
            local _ = v .. ""
        end)
        return not ok
    end

    return false
end

local function CanAccess(v)
    local fn = _G.canaccessvalue
    if type(fn) ~= "function" then
        return true
    end
    local ok, can = pcall(fn, v)
    return ok and can == true
end

local function SafeValueString(v)
    if IsSecret(v) then
        if CanAccess(v) then
            return "<secret>"
        end
        return "<secret:noaccess>"
    end
    return tostring(v)
end

local function CleanNumber(v)
    if type(v) ~= "number" then return nil end
    if IsSecret(v) then return nil end
    return v
end

local GuardedCall

local function SafeReadMember(container, key)
    if container == nil then return nil, false end

    local ok, value = GuardedCall("read-member:" .. tostring(key), function()
        return container[key]
    end)
    if not ok then
        return nil, true
    end
    if value == nil then
        return nil, false
    end
    if IsSecret(value) or not CanAccess(value) then
        return nil, true
    end
    return value, false
end

local InCombatLockdown = _G.InCombatLockdown
local UnitClass = _G.UnitClass
local UnitExists = _G.UnitExists
local UnitIsUnit = _G.UnitIsUnit
local UnitCanAttack = _G.UnitCanAttack
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local GetActionInfo = _G.GetActionInfo
local GetMacroInfo = _G.GetMacroInfo
local GetMacroSpell = _G.GetMacroSpell
local GetActionCooldown = _G.GetActionCooldown
local GetSpellBaseCooldown = _G.GetSpellBaseCooldown
local EnumerateFrames = _G.EnumerateFrames
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local C_Spell = _G.C_Spell
local C_ActionBar = _G.C_ActionBar
local C_NamePlate = _G.C_NamePlate
local CastingBarType = _G.CastingBarType
local GetTime = _G.GetTime
local strlower = _G.strlower or string.lower

local function SafeNow()
    local t = (GetTime and GetTime()) or 0
    t = CleanNumber(t)
    if type(t) == "number" then
        return t
    end

    local dp = _G.debugprofilestop
    if type(dp) == "function" then
        local ok, ms = pcall(dp)
        if ok and type(ms) == "number" then
            return ms / 1000
        end
    end

    return 0
end

local unpack = _G.unpack or table.unpack
local GUARD_NOTICE_INTERVAL = 30

IG._guardState = IG._guardState or {
    contexts = {},
    total = 0,
    lastContext = nil,
    lastError = nil,
    lastAt = 0,
    lastNoticeAt = 0,
    inAutoShow = false,
}

local function ReportGuardFailure(context, err)
    context = tostring(context or "unknown")
    err = tostring(err or "unknown")

    local state = IG._guardState
    local now = SafeNow()
    if type(now) ~= "number" then
        now = 0
    end

    local entry = state.contexts[context]
    if not entry then
        entry = { count = 0, lastAt = 0, lastNoticeAt = 0 }
        state.contexts[context] = entry
    end

    entry.count = entry.count + 1
    entry.lastAt = now
    state.total = (state.total or 0) + 1
    state.lastContext = context
    state.lastError = err
    state.lastAt = now

    if IG._dbgStats and type(IG._dbgStats.guard) == "table" then
        IG._dbgStats.guard[context] = (IG._dbgStats.guard[context] or 0) + 1
    end

    Debug(("guard: %s err=%s"):format(context, err), 0, "guard")

    local shouldNotify = ((state.total or 0) == 1)
        or (((now - (entry.lastNoticeAt or 0)) >= GUARD_NOTICE_INTERVAL)
            and ((now - (state.lastNoticeAt or 0)) >= GUARD_NOTICE_INTERVAL))

    if shouldNotify then
        entry.lastNoticeAt = now
        state.lastNoticeAt = now
        Print(("Guard trapped %s; addon stayed alive. See /iglow stats or /iglow log show."):format(context))
        if context ~= "debug:show-window" and not state.inAutoShow and IG and IG.MaybeAutoShowDebugLog then
            state.inAutoShow = true
            IG:MaybeAutoShowDebugLog("guard", false)
            state.inAutoShow = false
        end
    end
end

GuardedCall = function(context, fn, ...)
    local results = { pcall(fn, ...) }
    if results[1] ~= true then
        ReportGuardFailure(context, results[2])
    end
    return unpack(results, 1, #results)
end

local function SafeBool(v)
    if IsSecret(v) then return nil end
    if v == true then return true end
    if v == false then return false end
    return nil
end

local function UnitExistsSafe(unit)
    if not UnitExists then return false end
    local ok, value = GuardedCall("unit-exists:" .. tostring(unit), UnitExists, unit)
    if not ok then return false end
    return SafeBool(value) == true
end

local function UnitIsUnitSafe(a, b)
    if not UnitIsUnit then return false end
    local ok, value = GuardedCall("unit-is-unit:" .. tostring(a) .. ":" .. tostring(b), UnitIsUnit, a, b)
    if not ok then return false end
    return SafeBool(value) == true
end

local function UnitCanAttackSafe(a, b)
    if not UnitCanAttack then return false end
    local ok, value = GuardedCall("unit-can-attack:" .. tostring(a) .. ":" .. tostring(b), UnitCanAttack, a, b)
    if not ok then return false end
    return SafeBool(value) == true
end

local function UnitIsDeadOrGhostSafe(unit)
    if not UnitIsDeadOrGhost then return false end
    local ok, value = GuardedCall("unit-dead-or-ghost:" .. tostring(unit), UnitIsDeadOrGhost, unit)
    if not ok then return false end
    return SafeBool(value) == true
end

local function SafeUnitCastingInfo(unit)
    if type(UnitCastingInfo) ~= "function" then
        return nil
    end

    local ok, a, b, c, d, e, f, g, h, i, j = GuardedCall("unit-casting-info:" .. tostring(unit), UnitCastingInfo, unit)
    if not ok then
        return nil
    end

    return a, b, c, d, e, f, g, h, i, j
end

local function SafeUnitChannelInfo(unit)
    if type(UnitChannelInfo) ~= "function" then
        return nil
    end

    local ok, a, b, c, d, e, f, g, h, i, j = GuardedCall("unit-channel-info:" .. tostring(unit), UnitChannelInfo, unit)
    if not ok then
        return nil
    end

    return a, b, c, d, e, f, g, h, i, j
end

local function SpellName(spellID)
    if _G.GetSpellInfo then
        return _G.GetSpellInfo(spellID)
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        return info and info.name or nil
    end
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    return nil
end

local function SpellTexture(spellID)
    if not spellID then return nil end
    if _G.GetSpellTexture then
        return _G.GetSpellTexture(spellID)
    end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            return info.iconID or info.icon
        end
    end
    return nil
end

local function SpellKnown(spellID)
    if not spellID then return false end
    if _G.IsPlayerSpell and _G.IsPlayerSpell(spellID) then return true end
    if _G.IsSpellKnown and _G.IsSpellKnown(spellID) then return true end
    if C_Spell and C_Spell.IsSpellKnown and C_Spell.IsSpellKnown(spellID) then return true end
    return false
end

local INTERRUPTS_BY_CLASS = {
    DEATHKNIGHT = { 47528 },
    DEMONHUNTER = { 183752 },
    DRUID = { 106839, 78675 },
    EVOKER = { 351338 },
    HUNTER = { 147362, 187707 },
    MAGE = { 2139 },
    MONK = { 116705, 173320 },
    PALADIN = { 96231 },
    PRIEST = { 15487 },
    ROGUE = { 1766 },
    SHAMAN = { 57994 },
    WARLOCK = { 119898, 19647, 115781, 119910 },
    WARRIOR = { 6552 },
}

local function WipeArray(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

local function WipeMap(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

IG.class = IG.class or nil
IG.interruptSpellSet = IG.interruptSpellSet or {}
IG.interruptNameToID = IG.interruptNameToID or {}
IG.interruptTokens = IG.interruptTokens or {}
IG.trackedSlots = IG.trackedSlots or {}
IG.slotSpellID = IG.slotSpellID or {}
IG.trackedButtons = IG.trackedButtons or {}
IG.extraButtons = IG.extraButtons or {}
IG.needsRescan = IG.needsRescan or false
IG.glowActive = IG.glowActive or false
IG.primarySlot = IG.primarySlot or nil
IG.interruptSpellID = IG.interruptSpellID or nil
IG.interruptReady = IG.interruptReady or false
IG.interruptReadyIsSecret = IG.interruptReadyIsSecret or false
IG._glowSecretReady = IG._glowSecretReady or nil
IG.cdRem = IG.cdRem or nil
IG.cdSrc = IG.cdSrc or nil
IG._localCD = IG._localCD or {
    nextReadyTime = nil,
    baseCD = nil,
    lastCastAt = nil,
    armed = false,
}

local TRACKED_UNITS = Private.TRACKED_UNITS or { "target", "focus" }
local CastActive = Private.CastActive or { target = false, focus = false }
local CastNI = Private.CastNI or { target = nil, focus = nil }
local CastNISrc = Private.CastNISrc or { target = nil, focus = nil }
local CastStartAt = Private.CastStartAt or { target = nil, focus = nil }
local CastGen = Private.CastGen or { target = 0, focus = 0 }
local NIEventDiag = Private.NIEventDiag or { target = 0, focus = 0, last = nil, rawUnit = nil }

local function AddUniqueButton(btn)
    for i = 1, #IG.trackedButtons do
        if IG.trackedButtons[i] == btn then
            return
        end
    end
    IG.trackedButtons[#IG.trackedButtons + 1] = btn
end

local function GetNamePlateUnitToken(namePlateFrame)
    if not namePlateFrame then
        return nil
    end

    local token = namePlateFrame.namePlateUnitToken or namePlateFrame.unitToken
    if type(token) ~= "string" then
        local uf = namePlateFrame.UnitFrame or namePlateFrame.unitFrame
        token = uf and uf.unit
    end

    if type(token) == "string" then
        return token
    end

    return nil
end

local function GetVisibleNamePlateForUnit(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        return nil
    end

    local ok, namePlates = GuardedCall("nameplate-get-nameplates", C_NamePlate.GetNamePlates)
    if not ok or type(namePlates) ~= "table" then
        return nil
    end

    for i = 1, #namePlates do
        local namePlateFrame = namePlates[i]
        local token = GetNamePlateUnitToken(namePlateFrame)
        if token and UnitIsUnitSafe(token, unit) then
            return namePlateFrame
        end
    end

    return nil
end

local function GetNamePlateFrame(unit)
    if type(unit) ~= "string" then
        return nil
    end

    if unit:sub(1, 9) == "nameplate" then
        if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
            return nil
        end

        local ok, np = GuardedCall("nameplate-get-for-unit:" .. tostring(unit), C_NamePlate.GetNamePlateForUnit, unit)
        if ok and np then
            return np
        end

        local ok2, np2 = GuardedCall("nameplate-get-for-unit-forbidden:" .. tostring(unit), C_NamePlate.GetNamePlateForUnit, unit, true)
        if ok2 then
            return np2
        end

        return nil
    end

    return GetVisibleNamePlateForUnit(unit)
end

local npCacheTarget = nil
local npCacheFocus = nil
local npCacheTime = 0
local NP_CACHE_TTL = 0.1

local function RefreshNPCache()
    local now = SafeNow()
    if type(now) == "number" and type(npCacheTime) == "number" and (now - npCacheTime) < NP_CACHE_TTL then
        return
    end

    npCacheTime = now
    npCacheTarget = GetNamePlateFrame("target")
    npCacheFocus = GetNamePlateFrame("focus")
end

local function InvalidateNPCache()
    npCacheTime = 0
end

local function MapEventUnit(unit)
    if type(unit) ~= "string" then return nil end
    if unit == "target" then return "target" end
    if unit == "focus" then return "focus" end

    local checkTarget = CastActive.target or UnitExistsSafe("target")
    local checkFocus = CastActive.focus or UnitExistsSafe("focus")
    if not checkTarget and not checkFocus then
        return nil
    end

    if unit:sub(1, 9) == "nameplate" and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        RefreshNPCache()

        if npCacheTarget then
            local token = GetNamePlateUnitToken(npCacheTarget)
            if type(token) == "string" and unit == token then
                return "target"
            end
        end

        if npCacheFocus then
            local token = GetNamePlateUnitToken(npCacheFocus)
            if type(token) == "string" and unit == token then
                return "focus"
            end
        end
    end

    if checkTarget and UnitIsUnitSafe(unit, "target") then return "target" end
    if checkFocus and UnitIsUnitSafe(unit, "focus") then return "focus" end
    return nil
end

local function CanHarm(unit)
    if not UnitExistsSafe(unit) then return false end
    if UnitIsDeadOrGhostSafe(unit) then return false end
    return UnitCanAttackSafe("player", unit)
end

local function QueryIsCasting(unit)
    if not UnitExistsSafe(unit) then return false end
    return (SafeUnitCastingInfo(unit) ~= nil) or (SafeUnitChannelInfo(unit) ~= nil)
end

Private.DB = DB
Private.Print = Print
Private.Debug = Debug
Private.IsSecret = IsSecret
Private.CanAccess = CanAccess
Private.SafeValueString = SafeValueString
Private.CleanNumber = CleanNumber
Private.SafeReadMember = SafeReadMember
Private.ReportGuardFailure = ReportGuardFailure
Private.GuardedCall = GuardedCall
Private.SafeNow = SafeNow
Private.SafeBool = SafeBool
Private.UnitExistsSafe = UnitExistsSafe
Private.UnitIsUnitSafe = UnitIsUnitSafe
Private.UnitCanAttackSafe = UnitCanAttackSafe
Private.UnitIsDeadOrGhostSafe = UnitIsDeadOrGhostSafe
Private.SafeUnitCastingInfo = SafeUnitCastingInfo
Private.SafeUnitChannelInfo = SafeUnitChannelInfo
Private.SpellName = SpellName
Private.SpellTexture = SpellTexture
Private.SpellKnown = SpellKnown
Private.INTERRUPTS_BY_CLASS = INTERRUPTS_BY_CLASS
Private.WipeArray = WipeArray
Private.WipeMap = WipeMap
Private.AddUniqueButton = AddUniqueButton
Private.GetNamePlateUnitToken = GetNamePlateUnitToken
Private.GetNamePlateFrame = GetNamePlateFrame
Private.RefreshNPCache = RefreshNPCache
Private.InvalidateNPCache = InvalidateNPCache
Private.MapEventUnit = MapEventUnit
Private.CanHarm = CanHarm
Private.QueryIsCasting = QueryIsCasting
Private.TRACKED_UNITS = TRACKED_UNITS
Private.CastActive = CastActive
Private.CastNI = CastNI
Private.CastNISrc = CastNISrc
Private.CastStartAt = CastStartAt
Private.CastGen = CastGen
Private.NIEventDiag = NIEventDiag
Private.ADDON_VERSION = (GetAddOnMetadata and GetAddOnMetadata("InterruptGlow", "Version")) or "dev"

Private.InCombatLockdown = InCombatLockdown
Private.UnitClass = UnitClass
Private.UnitCastingInfo = UnitCastingInfo
Private.UnitChannelInfo = UnitChannelInfo
Private.GetActionInfo = GetActionInfo
Private.GetMacroInfo = GetMacroInfo
Private.GetMacroSpell = GetMacroSpell
Private.GetActionCooldown = GetActionCooldown
Private.GetSpellBaseCooldown = GetSpellBaseCooldown
Private.EnumerateFrames = EnumerateFrames
Private.CreateFrame = CreateFrame
Private.C_Timer = C_Timer
Private.C_Spell = C_Spell
Private.C_ActionBar = C_ActionBar
Private.C_NamePlate = C_NamePlate
Private.CastingBarType = CastingBarType
Private.GetTime = GetTime
Private.strlower = strlower
