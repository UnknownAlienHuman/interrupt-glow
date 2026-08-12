local IG = _G.InterruptGlow
if not IG then return end

local Private = IG.Private
local DB = Private.DB
local Print = Private.Print
local IsSecret = Private.IsSecret
local SafeNow = Private.SafeNow
local SafeValueString = Private.SafeValueString
local WipeArray = Private.WipeArray
local UnitCastingInfo = Private.SafeUnitCastingInfo or Private.UnitCastingInfo
local UnitChannelInfo = Private.SafeUnitChannelInfo or Private.UnitChannelInfo
local CastActive = Private.CastActive
local CastNI = Private.CastNI
local CastNISrc = Private.CastNISrc
local NIEventDiag = Private.NIEventDiag
local ADDON_VERSION = Private.ADDON_VERSION
local GetLocalCooldownRemaining = Private.GetLocalCooldownRemaining
local GetSpellCooldownState = Private.GetSpellCooldownState
local GetActionCooldownState = Private.GetActionCooldownState
local GetWidgetCooldownState = Private.GetWidgetCooldownState
local GetButtonActionSlot = function(btn)
    return Private.GetButtonActionSlot and Private.GetButtonActionSlot(btn) or nil
end
local UnitNI = function(unit)
    return Private.UnitNI and Private.UnitNI(unit)
end
local BarNI = function(unit)
    return Private.BarNI and Private.BarNI(unit)
end
local CurrentNI = function(unit)
    return Private.CurrentNI and Private.CurrentNI(unit)
end
local GetUnitCastBars = function(unit)
    return Private.GetUnitCastBars and Private.GetUnitCastBars(unit)
end
local ShieldShown = function(shield)
    return Private.ShieldShown and Private.ShieldShown(shield)
end
local IconShown = function(icon)
    return Private.IconShown and Private.IconShown(icon)
end

local function ProbeCooldownLine(label, known, ready, readyIsSecret, rem, src)
    Print(("probe:%s known=%s ready=%s readySecret=%s rem=%s src=%s")
        :format(label, tostring(known), SafeValueString(ready), tostring(readyIsSecret), SafeValueString(rem), SafeValueString(src)))
end

function IG:ProbeReadiness()
    local now = SafeNow()

    do
        local known, ready, readyIsSecret, rem, src = GetSpellCooldownState(self.interruptSpellID, now)
        ProbeCooldownLine("spell", known, ready, readyIsSecret, rem, src)
    end

    if self.primarySlot then
        local known, ready, readyIsSecret, rem, src = GetActionCooldownState(self.primarySlot, now)
        ProbeCooldownLine("action.primarySlot", known, ready, readyIsSecret, rem, src)
    else
        Print("probe:action.primarySlot none")
    end

    if self.primaryButton then
        local liveSlot = GetButtonActionSlot(self.primaryButton)
        if type(liveSlot) == "number" then
            local known, ready, readyIsSecret, rem, src = GetActionCooldownState(liveSlot, now)
            ProbeCooldownLine("action.liveSlot", known, ready, readyIsSecret, rem, src)
        else
            Print("probe:action.liveSlot none")
        end
    else
        Print("probe:primaryButton none")
    end

    local fallbackBtn = self.primaryButton or self.cdmButton
    if fallbackBtn then
        local known, ready, readyIsSecret, rem, src = GetWidgetCooldownState(fallbackBtn, now)
        ProbeCooldownLine("widget.fallback", known, ready, readyIsSecret, rem, src)
    else
        Print("probe:widget.fallback none")
    end

    if self.cdmButton and self.cdmButton ~= fallbackBtn then
        local known, ready, readyIsSecret, rem, src = GetWidgetCooldownState(self.cdmButton, now)
        ProbeCooldownLine("widget.cdm", known, ready, readyIsSecret, rem, src)
    end

    local localRem = GetLocalCooldownRemaining(self._localCD, now)
    local localNRT = self._localCD and self._localCD.nextReadyTime or nil
    local localBase = self._localCD and self._localCD.baseCD or nil
    Print(("probe:state localRem=%s localNRT=%s localBase=%s currentReady=%s currentReadySecret=%s currentSrc=%s")
        :format(
            SafeValueString(localRem),
            SafeValueString(localNRT),
            SafeValueString(localBase),
            SafeValueString(self.interruptReady),
            tostring(self.interruptReadyIsSecret),
            SafeValueString(self.cdSrc)
        ))
end

function IG:PrintStats()
    local stats = self._dbgStats or {}
    local function Flatten(t)
        if type(t) ~= "table" then return "" end
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for i = 1, #keys do
            local k = keys[i]
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(t[k])
        end
        return table.concat(parts, ",")
    end

    local slot = stats.slot or {}
    Print(("stats: ver=%s errors=%s slot(ok=%s bad=%s) cd={%s} ni={%s}")
        :format(
            tostring(ADDON_VERSION),
            tostring(stats.errors or 0),
            tostring(slot.ok or 0),
            tostring(slot.bad or 0),
            Flatten(stats.cd),
            Flatten(stats.ni)
        ))
    local guardState = IG._guardState or {}
    Print(("stats-guard: total=%s lastCtx=%s lastErr=%s guard={%s}")
        :format(
            tostring(guardState.total or 0),
            tostring(guardState.lastContext),
            tostring(guardState.lastError),
            Flatten(stats.guard)
        ))
end

function IG:PrintNIDiag()
    local function One(unit)
        local castingNI = nil
        local channelNI = nil
        do
            local _, _, _, _, _, _, _, ni = UnitCastingInfo(unit)
            if ni ~= nil and not IsSecret(ni) then castingNI = (ni == true) end
        end
        do
            local _, _, _, _, _, _, ni = UnitChannelInfo(unit)
            if ni ~= nil and not IsSecret(ni) then channelNI = (ni == true) end
        end

        local barNI = BarNI(unit)
        local eventNI = CastNI[unit]
        Print(("ni:%s castActive=%s event=%s bar=%s unitCast=%s unitChan=%s strict=%s src=%s evtCount=%s last=%s raw=%s")
            :format(
                tostring(unit),
                tostring(CastActive[unit]),
                tostring(eventNI),
                tostring(barNI),
                tostring(castingNI),
                tostring(channelNI),
                tostring(DB.strictNI),
                tostring(CastNISrc[unit]),
                tostring(NIEventDiag[unit] or 0),
                tostring(NIEventDiag.last),
                tostring(NIEventDiag.rawUnit)
            ))
    end

    One("target")
    One("focus")
end

SLASH_INTERRUPT_GLOW1 = "/iglow"
SlashCmdList["INTERRUPT_GLOW"] = function(msg)
    msg = msg and msg:lower() or ""

    if msg == "debug" then
        DB.debug = not DB.debug
        Print("Debug: " .. (DB.debug and "ON" or "OFF"))
        return
    end

    if msg:match("^log") then
        local sub = msg:match("^log%s*(.*)$") or ""
        if sub == "" or sub == "show" then
            if IG.Debug and IG.Debug.Show then
                IG.Debug:Show(DB.debugKeep or 400)
            else
                Print("Debug log unavailable.")
            end
            return
        end
        if sub == "clear" then
            if IG.Debug and IG.Debug.Clear then IG.Debug:Clear() end
            Print("Debug log cleared.")
            return
        end
        if sub == "chat" then
            DB.debugChat = not DB.debugChat
            Print("Debug chat echo: " .. (DB.debugChat and "ON" or "OFF"))
            return
        end
        local n = tonumber(sub:match("^dump%s+(%d+)$") or "")
        if sub:match("^dump") then
            n = n or 30
            if IG.Debug and IG.Debug.DumpToChat then IG.Debug:DumpToChat(n) end
            return
        end
        local lvl = tonumber(sub:match("^level%s+(%d+)$") or "")
        if lvl then
            DB.debugLevel = lvl
            Print("Debug level: " .. tostring(DB.debugLevel))
            return
        end
        local keep = tonumber(sub:match("^keep%s+(%d+)$") or "")
        if keep then
            DB.debugKeep = keep
            Print("Debug keep: " .. tostring(DB.debugKeep))
            return
        end
        if sub == "on" then
            DB.debug = true
            Print("Debug: ON")
            return
        end
        if sub == "off" then
            DB.debug = false
            Print("Debug: OFF")
            return
        end
        Print("Log commands: /iglow log [show|clear|dump N|level N|keep N|chat|on|off]")
        return
    end

    if msg == "stats" then
        IG:PrintStats()
        return
    end

    if msg == "ni" then
        IG:PrintNIDiag()
        return
    end

    if msg == "cd" then
        IG:SetCDTextEnabled(not DB.cdText)
        Print("CD numbers: " .. (DB.cdText and "ON" or "OFF"))
        return
    end

    if msg == "cdm" then
        DB.cdm = not DB.cdm
        if DB.cdm then
            if Private.C_Timer and Private.C_Timer.After then
                Private.C_Timer.After(0, function() IG:TryFindCDMButton() end)
            end
        elseif IG.ClearExtraButtons then
            IG:ClearExtraButtons()
        else
            WipeArray(IG.extraButtons)
            IG.cdmButton = nil
        end
        if IG.MarkReadyDirty then
            IG:MarkReadyDirty("cmd-cdm")
        elseif IG.MarkGlowDirty then
            IG:MarkGlowDirty()
        else
            IG:ApplyGlowDecision()
        end
        Print("CDM mirror: " .. (DB.cdm and "ON" or "OFF"))
        return
    end

    if msg == "test" then
        IG:SetGlow(true)
        if Private.C_Timer and Private.C_Timer.After then
            Private.C_Timer.After(2, function() IG:SetGlow(false) end)
        end
        Print(("Test glow for 2s. buttons=%d (bar=%d cdm=%d)")
            :format(#IG.trackedButtons + #IG.extraButtons, #IG.trackedButtons, #IG.extraButtons))
        return
    end

    if msg == "rescan" then
        IG:RescanInterruptButtons(true)
        IG:HookCooldownDoneFrames()
        if DB.cdm and Private.C_Timer and Private.C_Timer.After then
            Private.C_Timer.After(0, function() IG:TryFindCDMButton() end)
        end
        if DB.cdText then IG:PrepareCDText() end
        IG:MarkReadyDirty("cmd-rescan")
        Print(("Rescan done. buttons=%d slots=%d spellID=%s")
            :format(#IG.trackedButtons + #IG.extraButtons, #DB.slots, tostring(IG.interruptSpellID)))
        return
    end

    if msg == "state" then
        local function BarDiag(bar)
            if not bar then return "none" end
            local isForbidden = (bar.IsForbidden and bar:IsForbidden()) and true or false
            local barType = bar.barType
            local barTypeString = IsSecret(barType) and "<secret>" or tostring(barType)
            local active = (bar.casting == true or bar.channeling == true) and "active" or "idle"
            local showShield = IsSecret(bar.showShield) and "<secret>" or tostring(bar.showShield)
            local hideIconWhenNI = IsSecret(bar.HideIconWhenNotInterruptible) and "<secret>" or tostring(bar.HideIconWhenNotInterruptible)
            local shield = bar.BorderShield or bar.BorderShieldFrame or bar.Shield or bar.borderShield
            local shieldShown = ShieldShown(shield)
            local icon = bar.Icon or bar.icon
            local iconShown = IconShown(icon)
            local rothNI = IsSecret(bar.__RothNotInterruptible) and "<secret>" or tostring(bar.__RothNotInterruptible)
            return (isForbidden and "forbidden" or "ok")
                .. ":" .. barTypeString
                .. ":" .. active
                .. ":ss=" .. tostring(shieldShown)
                .. ":is=" .. tostring(iconShown)
                .. ":showShield=" .. showShield
                .. ":hideIconNI=" .. hideIconWhenNI
                .. ":rothNI=" .. rothNI
        end

        IG:UpdateInterruptReady()
        local now = SafeNow()
        local localRem = GetLocalCooldownRemaining(IG._localCD, now)
        local localNRT = IG._localCD and IG._localCD.nextReadyTime or nil
        local localBase = IG._localCD and IG._localCD.baseCD or nil
        local tUnitNI, tBarNI, tEventNI = UnitNI("target"), BarNI("target"), CastNI.target
        local fUnitNI, fBarNI, fEventNI = UnitNI("focus"), BarNI("focus"), CastNI.focus
        local tBarUnit, tBarNP = GetUnitCastBars("target")
        local fBarUnit = GetUnitCastBars("focus")
        local slotOk, _, slotReason = IG:ValidateInterruptSlot(IG.primarySlot, now)
        local liveSlot = IG.primaryButton and GetButtonActionSlot(IG.primaryButton) or nil
        local liveOk, _, liveReason = false, nil, "no-live-slot"
        local guardState = IG._guardState or {}
        if type(liveSlot) == "number" then
            liveOk, _, liveReason = IG:ValidateInterruptSlot(liveSlot, now)
        end
        Print(("state: ver=%s buttons=%d (bar=%d cdm=%d) slots=%d primarySlot=%s spellID=%s ready=%s readySecret=%s cdRem=%s cdSrc=%s localRem=%s localNRT=%s localBase=%s localArmed=%s cdCand=%s targetCast=%s focusCast=%s targetNI=%s focusNI=%s targetNIu=%s targetNIb=%s targetNIe=%s focusNIu=%s focusNIb=%s focusNIe=%s targetNISrc=%s focusNISrc=%s targetBar=%s targetNPBar=%s focusBar=%s niEvtT=%s niEvtF=%s niLast=%s niRawUnit=%s cdText=%s cdm=%s dbg=%s dbgChat=%s dbgLvl=%s dbgKeep=%s slotOk=%s slotReason=%s liveSlot=%s liveOk=%s liveReason=%s guardTotal=%s guardLastCtx=%s guardLastErr=%s")
            :format(
                tostring(ADDON_VERSION),
                #IG.trackedButtons + #IG.extraButtons,
                #IG.trackedButtons,
                #IG.extraButtons,
                #DB.slots,
                tostring(IG.primarySlot),
                tostring(IG.interruptSpellID),
                SafeValueString(IG.interruptReady),
                tostring(IG.interruptReadyIsSecret),
                SafeValueString(IG.cdRem),
                SafeValueString(IG.cdSrc),
                SafeValueString(localRem),
                SafeValueString(localNRT),
                SafeValueString(localBase),
                tostring(IG._localCD and IG._localCD.armed),
                tostring(IG._cdCandidatesDbg),
                tostring(CastActive.target),
                tostring(CastActive.focus),
                tostring(CurrentNI("target")),
                tostring(CurrentNI("focus")),
                tostring(tUnitNI),
                tostring(tBarNI),
                tostring(tEventNI),
                tostring(fUnitNI),
                tostring(fBarNI),
                tostring(fEventNI),
                tostring(CastNISrc.target),
                tostring(CastNISrc.focus),
                BarDiag(tBarUnit),
                BarDiag(tBarNP),
                BarDiag(fBarUnit),
                tostring(NIEventDiag.target),
                tostring(NIEventDiag.focus),
                tostring(NIEventDiag.last),
                tostring(NIEventDiag.rawUnit),
                tostring(DB.cdText),
                tostring(DB.cdm),
                tostring(DB.debug),
                tostring(DB.debugChat),
                tostring(DB.debugLevel),
                tostring(DB.debugKeep),
                tostring(slotOk),
                tostring(slotReason),
                tostring(liveSlot),
                tostring(liveOk),
                tostring(liveReason),
                tostring(guardState.total or 0),
                tostring(guardState.lastContext),
                tostring(guardState.lastError)
            ))
        return
    end

    if msg == "probe" then
        IG:UpdateInterruptReady()
        IG:ProbeReadiness()
        return
    end

    Print("Commands: /iglow debug | /iglow log | /iglow stats | /iglow ni | /iglow rescan | /iglow cd | /iglow cdm | /iglow test | /iglow state | /iglow probe")
end
