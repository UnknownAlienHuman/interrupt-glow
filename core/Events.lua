local IG = _G.InterruptGlow
if not IG then return end

local Private = IG.Private
local frame = Private.frame
local DB = Private.DB
local Print = Private.Print
local Debug = Private.Debug
local SafeNow = Private.SafeNow
local UnitClass = Private.UnitClass
local UnitExistsSafe = Private.UnitExistsSafe
local InCombatLockdown = Private.InCombatLockdown
local C_Timer = Private.C_Timer
local GuardedCall = Private.GuardedCall
local ADDON_VERSION = Private.ADDON_VERSION
local CastActive = Private.CastActive
local CastNI = Private.CastNI
local CastNISrc = Private.CastNISrc
local CastStartAt = Private.CastStartAt
local CastGen = Private.CastGen
local NIEventDiag = Private.NIEventDiag
local BuildInterruptCaches = function()
    if Private.BuildInterruptCaches then
        Private.BuildInterruptCaches()
    end
end
local InvalidateNPCache = function()
    if Private.InvalidateNPCache then
        Private.InvalidateNPCache()
    end
end
local MapEventUnit = function(unit)
    if Private.MapEventUnit then
        return Private.MapEventUnit(unit)
    end
    return nil
end
local MergeNI = function(unit)
    if Private.MergeNI then
        return Private.MergeNI(unit)
    end
    return nil
end
local SyncUnitState = function(unit)
    if Private.SyncUnitState then
        Private.SyncUnitState(unit)
    end
end

local function ErrorStack(err)
    local ds = ""
    if type(debugstack) == "function" then
        ds = debugstack(3, 40, 40)
    elseif type(debugstack) == "string" then
        ds = debugstack
    end
    return tostring(err) .. (ds ~= "" and ("\n" .. ds) or "")
end

function IG:HandleError(err, context)
    local now = SafeNow()
    self._errCount = (self._errCount or 0) + 1
    if self._dbgStats then
        self._dbgStats.errors = (self._dbgStats.errors or 0) + 1
    end

    if type(self._errWindowStart) ~= "number" or (now - self._errWindowStart) > 10 then
        self._errWindowStart = now
        self._errWindowCount = 0
    end
    self._errWindowCount = (self._errWindowCount or 0) + 1

    local msg = tostring(context or "error") .. ": " .. tostring(err)
    Debug(msg, 0, "ERR")
    self:MaybeAutoShowDebugLog("error", false)

    if (self._errWindowCount or 0) >= 40 and not self._disabledByErrors then
        self._disabledByErrors = true
        self._disabled = true
        self:SetGlow(false)
        Print("Disabled due to repeated errors (burst). Use /reload to recover. See /iglow log show for details.")
    end
end

function IG:MaybeAutoShowDebugLog(reason, force)
    if DB.debugAutoShow == false then return end
    if not (self.Debug and self.Debug.Show) then return end

    local r = tostring(reason or "auto")
    if not (DB and DB.debug) and r ~= "error" then
        return
    end

    local now = SafeNow()
    self._lastAutoShow = self._lastAutoShow or 0
    if (not force) and type(now) == "number" and (now - self._lastAutoShow) < 1.0 then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        self._pendingAutoShow = true
        self._pendingAutoShowReason = r
        return
    end

    self._pendingAutoShow = false
    if type(now) == "number" then
        self._lastAutoShow = now
    end

    GuardedCall("debug:show-window", function()
        self.Debug:Show((DB and DB.debugKeep) or 400, true)
    end)
end

local function OnEvent(_, event, ...)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        IG.class = class

        BuildInterruptCaches()
        IG:ClearSlotValidationCache()
        IG:RescanInterruptButtons()
        IG:HookCooldownDoneFrames()
        IG:HookButtonForgeCallbacks()

        IG:HookUnitFrameCastBars()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, function() IG:HookUnitFrameCastBars() end)
        end

        SyncUnitState("target")
        SyncUnitState("focus")

        IG:UpdateLocalCooldownBase()
        IG:RestoreLocalCooldownFromDB()
        IG:UpdateInterruptReady()

        if DB.cdText then IG:PrepareCDText() end
        if DB.cdm and C_Timer and C_Timer.After then
            C_Timer.After(1.0, function() IG:TryFindCDMButton() end)
        end

        IG:ScheduleCDTextTick()
        IG:MarkGlowDirty()

        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("ADDON_LOADED")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")

        frame:RegisterEvent("SPELLS_CHANGED")
        frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        frame:RegisterEvent("UPDATE_BINDINGS")

        frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
        frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
        frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        frame:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_ADDED")

        frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "target", "focus")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target", "focus")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "target", "focus")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "focus")
        frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target", "focus")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target", "focus")
        frame:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
        frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")

        Debug("Loaded v" .. tostring(ADDON_VERSION) .. " class=" .. tostring(IG.class))
        IG:MaybeAutoShowDebugLog("login", true)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if IG.needsRescan then
            BuildInterruptCaches()
            IG:ClearSlotValidationCache()
            IG:RescanInterruptButtons(true)
            IG:HookCooldownDoneFrames()
            if DB.cdm and C_Timer and C_Timer.After then
                C_Timer.After(0, function() IG:TryFindCDMButton() end)
            end
            if DB.cdText then IG:PrepareCDText() end
            IG:MarkReadyDirty("regen")
        end
        if IG._pendingAutoShow then
            IG:MaybeAutoShowDebugLog("regen-enabled", true)
        end
        return
    end

    if event == "ADDON_LOADED" then
        local addon = ...
        if addon and type(addon) == "string" and addon:find("Blizzard_UnitFrame") then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.2, function() IG:HookUnitFrameCastBars() end)
            end
        end
        if addon == "ButtonForge" then
            IG:HookButtonForgeCallbacks()
            IG:RescanInterruptButtons(true)
            IG:HookCooldownDoneFrames()
            if DB.cdText then IG:PrepareCDText() end
            IG:MarkReadyDirty("buttonforge-loaded")
        end
        if DB.cdm and addon and type(addon) == "string" and (addon:find("Blizzard_Cooldown") or addon:find("CooldownManager")) then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.2, function() IG:TryFindCDMButton() end)
            end
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if not (InCombatLockdown and InCombatLockdown()) then
            IG:HookUnitFrameCastBars()
        end
        SyncUnitState("target")
        SyncUnitState("focus")
        IG:MarkReadyDirty("entering-world")
        return
    end

    if event == "ACTIONBAR_SLOT_CHANGED" then
        local slot = ...
        if type(slot) == "number" and IG.primarySlot and slot ~= IG.primarySlot and not IG.trackedSlots[slot] then
            return
        end

        BuildInterruptCaches()
        IG:ClearSlotValidationCache()
        IG:RescanInterruptButtons(false)
        IG:HookCooldownDoneFrames()
        if DB.cdm and C_Timer and C_Timer.After then
            C_Timer.After(0, function() IG:TryFindCDMButton() end)
        end
        if DB.cdText then IG:PrepareCDText() end
        IG:MarkReadyDirty("slot-rescan")
        return
    end

    if event == "SPELLS_CHANGED" or event == "UPDATE_BINDINGS" then
        BuildInterruptCaches()
        IG:RescanInterruptButtons(false)
        IG:HookCooldownDoneFrames()
        if DB.cdm and C_Timer and C_Timer.After then
            C_Timer.After(0, function() IG:TryFindCDMButton() end)
        end
        if DB.cdText then IG:PrepareCDText() end
        IG:MarkReadyDirty("rescan")
        return
    end

    if event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        IG:MarkReadyDirty(event)
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED" or event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        InvalidateNPCache()
        local mapped = MapEventUnit(unit)
        if mapped == "target" or mapped == "focus" then
            IG:HookUnitFrameCastBars()
            SyncUnitState(mapped)
            IG:MarkGlowDirty()
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        CastActive.target = false
        CastNI.target = nil
        CastNISrc.target = nil
        CastStartAt.target = nil
        CastGen.target = CastGen.target + 1
        InvalidateNPCache()
        IG:HookUnitFrameCastBars()
        SyncUnitState("target")
        IG:MarkGlowDirty()
        if C_Timer and C_Timer.After then
            local gen = CastGen.target
            C_Timer.After(0.08, function()
                if CastGen.target ~= gen then return end
                IG:HookUnitFrameCastBars()
                SyncUnitState("target")
                IG:MarkGlowDirty()
            end)
        end
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        CastActive.focus = false
        CastNI.focus = nil
        CastNISrc.focus = nil
        CastStartAt.focus = nil
        CastGen.focus = CastGen.focus + 1
        InvalidateNPCache()
        IG:HookUnitFrameCastBars()
        SyncUnitState("focus")
        IG:MarkGlowDirty()
        if C_Timer and C_Timer.After then
            local gen = CastGen.focus
            C_Timer.After(0.08, function()
                if CastGen.focus ~= gen then return end
                IG:HookUnitFrameCastBars()
                SyncUnitState("focus")
                IG:MarkGlowDirty()
            end)
        end
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and type(spellID) == "number" and IG.interruptSpellSet[spellID] then
            IG:StartLocalCooldownFromCast(spellID)
            IG:MarkReadyDirty("interrupt-used")
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, function() IG:MarkReadyDirty("interrupt-used-delay") end)
            end
        end
        return
    end

    local unit = ...
    if (event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_INTERRUPTIBLE")
        and unit ~= "target" and unit ~= "focus"
        and not (CastActive.target or UnitExistsSafe("target"))
        and not (CastActive.focus or UnitExistsSafe("focus")) then
        return
    end

    local mapped = (unit == "target" or unit == "focus") and unit or MapEventUnit(unit)
    if not mapped then return end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        CastActive[mapped] = true
        CastStartAt[mapped] = SafeNow()
        CastGen[mapped] = CastGen[mapped] + 1
        local ni, niSource = MergeNI(mapped)
        CastNI[mapped] = ni
        CastNISrc[mapped] = niSource
        local gen = CastGen[mapped]
        if ni == nil and C_Timer and C_Timer.After then
            C_Timer.After(0.05, function()
                if CastGen[mapped] ~= gen then return end
                if CastActive[mapped] and CastNI[mapped] == nil then
                    local ni2, niSource2 = MergeNI(mapped)
                    if ni2 ~= nil or niSource2 ~= nil then
                        CastNI[mapped] = ni2
                        CastNISrc[mapped] = niSource2
                        IG:MarkGlowDirty()
                    end
                end
            end)
            C_Timer.After(0.15, function()
                if CastGen[mapped] ~= gen then return end
                if CastActive[mapped] and CastNI[mapped] == nil then
                    local ni3, niSource3 = MergeNI(mapped)
                    if ni3 ~= nil or niSource3 ~= nil then
                        CastNI[mapped] = ni3
                        CastNISrc[mapped] = niSource3
                        IG:MarkGlowDirty()
                    end
                end
            end)
        end
        IG:MarkReadyDirty("cast-start")
        IG:MarkGlowDirty()
        return
    end

    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        CastActive[mapped] = false
        CastStartAt[mapped] = nil
        CastNI[mapped] = nil
        CastNISrc[mapped] = nil
        CastGen[mapped] = CastGen[mapped] + 1
        IG:MarkGlowDirty()
        return
    end

    if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        CastNI[mapped] = true
        CastNISrc[mapped] = "event-first"
        NIEventDiag[mapped] = (NIEventDiag[mapped] or 0) + 1
        NIEventDiag.last = "not-interruptible"
        NIEventDiag.rawUnit = tostring(unit)

        if DB and DB.debug then
            IG:StatInc("ni", "event-ni")
            local castGUID = select(2, ...)
            local spellID = select(3, ...)
            Debug(("NI event: mapped=%s raw=%s spellID=%s castGUID=%s")
                :format(tostring(mapped), tostring(unit), tostring(spellID), tostring(castGUID)), 2, "ni")
        end

        IG:MarkGlowDirty()
        return
    end

    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        CastNI[mapped] = false
        CastNISrc[mapped] = "event-first"
        NIEventDiag[mapped] = (NIEventDiag[mapped] or 0) + 1
        NIEventDiag.last = "interruptible"
        NIEventDiag.rawUnit = tostring(unit)

        if DB and DB.debug then
            IG:StatInc("ni", "event-ok")
            local castGUID = select(2, ...)
            local spellID = select(3, ...)
            Debug(("NI event: mapped=%s raw=%s spellID=%s castGUID=%s")
                :format(tostring(mapped), tostring(unit), tostring(spellID), tostring(castGUID)), 2, "ni")
        end

        IG:MarkGlowDirty()
        return
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if IG._disabled then return end
    local ok, err = xpcall(OnEvent, ErrorStack, self, event, ...)
    if not ok then
        IG:HandleError(err, "OnEvent:" .. tostring(event))
    end
end)

frame:RegisterEvent("PLAYER_LOGIN")
