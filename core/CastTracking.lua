local IG = _G.InterruptGlow
if not IG then return end

local Private = IG.Private
local IsSecret = Private.IsSecret
local SafeNow = Private.SafeNow
local UnitExistsSafe = Private.UnitExistsSafe
local UnitCastingInfo = Private.SafeUnitCastingInfo or Private.UnitCastingInfo
local UnitChannelInfo = Private.SafeUnitChannelInfo or Private.UnitChannelInfo
local CastingBarType = Private.CastingBarType
local C_Timer = Private.C_Timer
local GetNamePlateFrame = Private.GetNamePlateFrame
local MapEventUnit = Private.MapEventUnit
local QueryIsCasting = Private.QueryIsCasting
local GuardedCall = Private.GuardedCall
local CastActive = Private.CastActive
local CastNI = Private.CastNI
local CastNISrc = Private.CastNISrc
local CastStartAt = Private.CastStartAt
local CastGen = Private.CastGen
local hooksecurefunc = _G.hooksecurefunc

local function StrategyContext(unit)
    if unit == "target" then return "target" end
    if unit == "focus" then return "focus" end

    if type(unit) == "string" then
        if unit:sub(1, 9) == "nameplate" then
            return "nameplate"
        end
        if unit:match("^boss%d+$") then
            return "boss-token"
        end
    end

    return "unknown/secret"
end

local function ShieldShown(shield)
    if not shield or not shield.IsShown then return nil end

    local okShown, shown = GuardedCall("casttracking:shield-is-shown", shield.IsShown, shield)
    if not okShown or IsSecret(shown) then return nil end
    if shown ~= true then return false end

    if shield.GetAlpha then
        local okAlpha, alpha = GuardedCall("casttracking:shield-get-alpha", shield.GetAlpha, shield)
        if okAlpha and not IsSecret(alpha) and type(alpha) == "number" and alpha <= 0 then
            return false
        end
    end

    return true
end

local function IconShown(icon)
    if not icon or not icon.IsShown then return nil end

    local okShown, shown = GuardedCall("casttracking:icon-is-shown", icon.IsShown, icon)
    if not okShown or IsSecret(shown) then return nil end
    if shown ~= true then return false end

    if icon.GetAlpha then
        local okAlpha, alpha = GuardedCall("casttracking:icon-get-alpha", icon.GetAlpha, icon)
        if okAlpha and not IsSecret(alpha) and type(alpha) == "number" and alpha <= 0 then
            return false
        end
    end

    return true
end

local function ReadBarActiveState(bar)
    if not bar then
        return false, false
    end

    local isForbidden = false
    if bar.IsForbidden then
        local okForbidden, forbidden = GuardedCall("casttracking:bar-is-forbidden", bar.IsForbidden, bar)
        if okForbidden and forbidden == true then
            isForbidden = true
        end
    end

    local active = (bar.casting == true or bar.channeling == true or bar.reverseChanneling == true)
    if not active and not isForbidden and bar.IsShown then
        local okShown, shown = GuardedCall("casttracking:bar-is-shown", bar.IsShown, bar)
        if okShown and not IsSecret(shown) and shown == true then
            active = true
        end
    end

    return active, isForbidden
end

local function ReadBarInterruptibleState(bar)
    if not bar then return nil end

    local active, isForbidden = ReadBarActiveState(bar)
    if not active then return nil end

    -- Castbar barType — надёжный источник только для "точно NI".
    -- StandardCast/nil barType НЕ подтверждает interruptible: Blizzard ставит
    -- StandardCast по умолчанию когда notInterruptible=nil (restricted в инстансе).
    local barType = bar.barType
    if barType ~= nil and not IsSecret(barType) then
        if type(CastingBarType) == "table" and CastingBarType.Uninterruptable ~= nil then
            if barType == CastingBarType.Uninterruptable then
                return true
            end
        elseif barType == "Uninterruptable" or barType == "UNINTERRUPTABLE" then
            return true
        end
    end

    local rothNI = bar.__RothNotInterruptible
    if type(rothNI) == "boolean" and not IsSecret(rothNI) then
        return rothNI
    end
    local directNI = bar.notInterruptible
    if type(directNI) == "boolean" and not IsSecret(directNI) then
        return directNI
    end
    local uninterruptible = bar.isUninterruptible
    if type(uninterruptible) == "boolean" and not IsSecret(uninterruptible) then
        return uninterruptible
    end

    -- Shield shown = точно NI. Shield hidden НЕ подтверждает interruptible:
    -- щит скрывается и когда NI-инфо restricted/nil (инстанс).
    local shield = bar.BorderShield or bar.BorderShieldFrame or bar.Shield or bar.borderShield
    local shown = ShieldShown(shield)
    if shown == true then
        return true
    end

    local hideIconWhenNI = bar.HideIconWhenNotInterruptible
    if not IsSecret(hideIconWhenNI) and hideIconWhenNI == true then
        local icon = bar.Icon or bar.icon
        local iconShown = IconShown(icon)
        if iconShown == false then
            return true
        end
    end

    if isForbidden then
        return nil
    end

    if bar.IsInterruptable then
        local ok, isInterruptable = GuardedCall("casttracking:is-interruptable", bar.IsInterruptable, bar)
        if ok and isInterruptable ~= nil then
            if IsSecret(isInterruptable) then
                return nil
            end
            return isInterruptable ~= true
        end
    end

    return nil
end

local function GetNamePlateCastBar(unit)
    local np = GetNamePlateFrame(unit)
    local uf = np and (np.UnitFrame or np.unitFrame)
    if uf then
        return uf.castBar or uf.CastBar or uf.castbar
    end
    return nil
end

local function GetUnitCastBars(unit)
    if unit == "target" then
        local unitBar = _G.TargetFrameSpellBar
        local npBar = GetNamePlateCastBar("target")
        return unitBar, npBar
    end

    if unit == "focus" then
        return _G.FocusFrameSpellBar, nil
    end

    return nil, GetNamePlateCastBar(unit)
end

local function UnitNI(unit)
    if not UnitExistsSafe(unit) then return nil end

    local _, _, _, _, _, _, _, castNI = UnitCastingInfo(unit)
    if castNI ~= nil then
        if IsSecret(castNI) then return nil end
        return castNI == true
    end

    local _, _, _, _, _, _, channelNI = UnitChannelInfo(unit)
    if channelNI ~= nil then
        if IsSecret(channelNI) then return nil end
        return channelNI == true
    end

    return nil
end

local function NameplateBarNI(unit)
    local _, npBar = GetUnitCastBars(unit)
    if not npBar then
        return nil, false
    end
    if npBar.IsForbidden and npBar:IsForbidden() then
        return nil, true
    end
    return ReadBarInterruptibleState(npBar), false
end

local function BarNI(unit)
    if unit == "target" then
        local unitBar = GetUnitCastBars("target")
        local niTarget = ReadBarInterruptibleState(unitBar)
        if niTarget ~= nil then return niTarget end

        local niNameplate = NameplateBarNI("target")
        if niNameplate ~= nil then return niNameplate end
        return nil
    end

    if unit == "focus" then
        local unitBar = GetUnitCastBars("focus")
        local ni = ReadBarInterruptibleState(unitBar)
        if ni ~= nil then return ni end
        return nil
    end

    if type(unit) == "string" and unit:sub(1, 9) == "nameplate" then
        local niNameplate = NameplateBarNI(unit)
        if niNameplate ~= nil then return niNameplate end
    end

    return nil
end

local function NormalizeExplicitNI(value)
    if value == true then return true end
    if value == false then return false end
    return nil
end

local function MapTrackedCastbarUnit(bar)
    if not bar then return nil end

    local rawUnit = bar.unit
    if type(rawUnit) ~= "string" then
        return nil
    end

    if rawUnit == "target" or rawUnit == "focus" then
        return rawUnit
    end

    if type(MapEventUnit) == "function" then
        return MapEventUnit(rawUnit)
    end

    return nil
end

local function SyncTrackedCastbarState(bar, source, explicitNI, forceActive)
    local mapped = MapTrackedCastbarUnit(bar)
    if mapped ~= "target" and mapped ~= "focus" then
        return
    end

    local active = false
    if forceActive == true then
        active = true
    elseif forceActive == false then
        active = false
    else
        active = ReadBarActiveState(bar)
    end

    if not active then
        if QueryIsCasting(mapped) then
            active = true
        else
            CastActive[mapped] = false
            CastStartAt[mapped] = nil
            CastNI[mapped] = nil
            CastNISrc[mapped] = nil
            CastGen[mapped] = CastGen[mapped] + 1
            IG:MarkGlowDirty()
            return
        end
    end

    CastActive[mapped] = true
    if type(CastStartAt[mapped]) ~= "number" then
        CastStartAt[mapped] = SafeNow()
    end

    local barNI = NormalizeExplicitNI(explicitNI)
    if barNI == nil then
        barNI = ReadBarInterruptibleState(bar)
    end

    if barNI ~= nil then
        CastNI[mapped] = barNI
        CastNISrc[mapped] = source or "castbar-hook"
    end

    IG:MarkGlowDirty()
end

local CastbarHooksInstalled = false

local function InstallCastbarHooks()
    if CastbarHooksInstalled then
        return true
    end
    if type(hooksecurefunc) ~= "function" then
        return false
    end

    local mixin = _G.CastingBarMixin
    if type(mixin) ~= "table" then
        return false
    end

    hooksecurefunc(mixin, "OnEvent", function(self, event, ...)
        if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            SyncTrackedCastbarState(self, "castbar-hook:" .. tostring(event), nil, true)
        elseif event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_INTERRUPTED"
            or event == "UNIT_SPELLCAST_CHANNEL_STOP"
            or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            SyncTrackedCastbarState(self, "castbar-hook:" .. tostring(event), nil, false)
        elseif event == "PLAYER_ENTERING_WORLD" then
            SyncTrackedCastbarState(self, "castbar-hook:" .. tostring(event), nil, nil)
        end
    end)

    hooksecurefunc(mixin, "UpdateInterruptibleState", function(self, notInterruptible)
        SyncTrackedCastbarState(self, "castbar-hook:update", NormalizeExplicitNI(notInterruptible), true)
    end)

    CastbarHooksInstalled = true
    return true
end

-- NI authority matrix, verified against UnitCastingInfo / UnitChannelInfo and Blizzard CastingBarMixin:
-- target: current = event-first -> castbar-fallback(target frame -> target nameplate) -> unit-api; snapshot omits event-first.
-- focus: current = event-first -> castbar-fallback(focus frame) -> unit-api; snapshot omits event-first.
-- nameplate: authoritative only after it maps into tracked target/focus events; forbidden nameplates stay nil via forbidden-nameplate.
-- boss-token: unit-api-first only; this addon does not wire boss castbars as fallback.
-- unknown/secret: unresolved stays nil and is gated later by strictNI.
local NI_STRATEGY = {
    snapshot = {
        target = {
            { lane = "castbar-fallback:target-frame", key = "targetBar" },
            { lane = "castbar-fallback:nameplate", key = "nameplateBar" },
            { lane = "unit-api-first", key = "unit" },
            { lane = "forbidden-nameplate", key = "nameplateForbidden", blockOnTrue = true },
        },
        focus = {
            { lane = "castbar-fallback:focus-frame", key = "focusBar" },
            { lane = "unit-api-first", key = "unit" },
        },
        nameplate = {
            { lane = "forbidden-nameplate", key = "nameplateForbidden", blockOnTrue = true },
        },
        ["boss-token"] = {
            { lane = "unit-api-first", key = "unit" },
        },
        ["unknown/secret"] = {},
    },
    current = {
        target = {
            { lane = "event-first", key = "event" },
            { lane = "castbar-fallback:target-frame", key = "targetBar" },
            { lane = "castbar-fallback:nameplate", key = "nameplateBar" },
            { lane = "unit-api-first", key = "unit" },
            { lane = "forbidden-nameplate", key = "nameplateForbidden", blockOnTrue = true },
        },
        focus = {
            { lane = "event-first", key = "event" },
            { lane = "castbar-fallback:focus-frame", key = "focusBar" },
            { lane = "unit-api-first", key = "unit" },
        },
        nameplate = {
            { lane = "event-first", key = "event" },
            { lane = "forbidden-nameplate", key = "nameplateForbidden", blockOnTrue = true },
        },
        ["boss-token"] = {
            { lane = "event-first", key = "event" },
            { lane = "unit-api-first", key = "unit" },
        },
        ["unknown/secret"] = {},
    },
}

local function EventNI(unit)
    local source = CastNISrc[unit]
    if source ~= "event-first" and source ~= "event" then
        return nil
    end

    local value = CastNI[unit]
    if value == true or value == false then
        return value
    end

    return nil
end

local function CollectNIObservations(unit)
    local context = StrategyContext(unit)
    local targetBar = nil
    local focusBar = nil
    local nameplateBar = nil
    local nameplateForbidden = false

    if context == "target" then
        local unitBar = GetUnitCastBars("target")
        targetBar = ReadBarInterruptibleState(unitBar)
        nameplateBar, nameplateForbidden = NameplateBarNI("target")
    elseif context == "focus" then
        local unitBar = GetUnitCastBars("focus")
        focusBar = ReadBarInterruptibleState(unitBar)
    elseif context == "nameplate" then
        nameplateBar, nameplateForbidden = NameplateBarNI(unit)
    end

    local barValue = targetBar
    if barValue == nil then barValue = focusBar end
    if barValue == nil then barValue = nameplateBar end

    return {
        event = EventNI(unit),
        unit = UnitNI(unit),
        bar = barValue,
        targetBar = targetBar,
        focusBar = focusBar,
        nameplateBar = nameplateBar,
        nameplateForbidden = nameplateForbidden == true,
    }
end

local function ResolveNI(unit, mode)
    local observations = CollectNIObservations(unit)
    local modeStrategy = NI_STRATEGY[mode] or NI_STRATEGY.current
    local context = StrategyContext(unit)
    local strategy = modeStrategy[context] or modeStrategy["unknown/secret"]
    local selectedValue = nil
    local selectedSource = nil

    for i = 1, #strategy do
        local step = strategy[i]
        local value = observations[step.key]
        if step.blockOnTrue then
            if value == true then
                selectedSource = step.lane
                break
            end
        elseif value ~= nil then
            selectedValue = value
            selectedSource = step.lane
            break
        end
    end

    return selectedValue, observations.bar, observations.unit, observations.event, selectedSource
end

local function ResolveSnapshotNI(unit)
    local value, _, _, _, source = ResolveNI(unit, "snapshot")
    return value, source
end

local function MergeNI(unit)
    return ResolveSnapshotNI(unit)
end

local function CurrentNI(unit)
    return ResolveNI(unit, "current")
end

local function HookUnitFrameCastBar(unit, bar)
    return InstallCastbarHooks()
end

function IG:HookUnitFrameCastBars()
    -- Keep this on hooksecurefunc only. HookScript on secure unit-frame castbars tainted edit mode.
    return InstallCastbarHooks()
end

local function SyncUnitState(unit)
    CastActive[unit] = QueryIsCasting(unit)
    if CastActive[unit] then
        if type(CastStartAt[unit]) ~= "number" then CastStartAt[unit] = SafeNow() end
        local ni, niSource = ResolveSnapshotNI(unit)
        CastNI[unit] = ni
        CastNISrc[unit] = niSource
        local gen = CastGen[unit]
        if ni == nil and C_Timer and C_Timer.After then
            C_Timer.After(0.05, function()
                if CastGen[unit] ~= gen then return end
                if CastActive[unit] and CastNI[unit] == nil then
                    local ni2, niSource2 = ResolveSnapshotNI(unit)
                    if ni2 ~= nil or niSource2 ~= nil then
                        CastNI[unit] = ni2
                        CastNISrc[unit] = niSource2
                        IG:MarkGlowDirty()
                    end
                end
            end)
        end
    else
        CastStartAt[unit] = nil
        CastNI[unit] = nil
        CastNISrc[unit] = nil
    end
end

Private.ShieldShown = ShieldShown
Private.IconShown = IconShown
Private.ReadBarInterruptibleState = ReadBarInterruptibleState
Private.GetUnitCastBars = GetUnitCastBars
Private.UnitNI = UnitNI
Private.BarNI = BarNI
Private.MergeNI = MergeNI
Private.CurrentNI = CurrentNI
Private.ResolveNI = ResolveNI
Private.SyncUnitState = SyncUnitState
