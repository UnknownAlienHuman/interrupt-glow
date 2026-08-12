local IG = _G.InterruptGlow
if not IG then return end

local Private = IG.Private
local DB = Private.DB
local Debug = Private.Debug
local IsSecret = Private.IsSecret
local SafeBool = Private.SafeBool
local SafeNow = Private.SafeNow
local CleanNumber = Private.CleanNumber
local SafeValueString = Private.SafeValueString
local SafeReadMember = Private.SafeReadMember
local GuardedCall = Private.GuardedCall
local GetActionCooldown = Private.GetActionCooldown
local GetSpellBaseCooldown = Private.GetSpellBaseCooldown
local C_ActionBar = Private.C_ActionBar
local C_Spell = Private.C_Spell
local C_Timer = Private.C_Timer
local InCombatLockdown = Private.InCombatLockdown
local CastActive = Private.CastActive
local GetButtonActionSlot = function(btn)
    return Private.GetButtonActionSlot and Private.GetButtonActionSlot(btn) or nil
end

local function CancelTimer(timer)
    if timer and timer.Cancel then
        timer:Cancel()
    end
end

IG._readyDirty = IG._readyDirty or false
IG._readyTimer = IG._readyTimer or nil
IG._cdExpireTimer = IG._cdExpireTimer or nil
IG._cdUnknownTimer = IG._cdUnknownTimer or nil
IG._cdTextDeferred = IG._cdTextDeferred or false
IG._cdTextTimer = IG._cdTextTimer or nil

local READY_COALESCE_WINDOW = 0.04
local GCD_THRESHOLD = 1.8
local HookedCooldowns = setmetatable({}, { __mode = "k" })
local ButtonCDText = setmetatable({}, { __mode = "k" })

local function GetButtonCDText(btn)
    return btn and ButtonCDText[btn] or nil
end

local function GetSpellBaseCooldownSeconds(spellID)
    if not spellID or not GetSpellBaseCooldown then return nil end

    local a, b = GetSpellBaseCooldown(spellID)
    if IsSecret(a) or IsSecret(b) then return nil end
    if type(a) ~= "number" then return nil end

    local ms = a
    if type(b) == "number" and b > ms then
        ms = b
    end

    if ms <= 0 then return 0 end
    return ms / 1000
end

local function GetLocalCooldownRemaining(localCD, now)
    if type(localCD) ~= "table" then return nil end
    local nextReadyTime = CleanNumber(localCD.nextReadyTime)
    if type(nextReadyTime) ~= "number" then return nil end
    local t = CleanNumber(now) or 0
    local rem = nextReadyTime - t
    if rem < 0 then rem = 0 end
    return rem
end

local function RemainingFromStartDuration(startTime, duration, now)
    if IsSecret(startTime) or IsSecret(duration) then return nil end
    if type(startTime) ~= "number" or type(duration) ~= "number" then return nil end
    if startTime <= 0 or duration <= 0 then return 0 end
    local rem = (startTime + duration) - (now or 0)
    if rem < 0 then rem = 0 end
    return rem
end

local function GetDurationIsZero(duration)
    local durType = type(duration)
    if durType ~= "table" and durType ~= "userdata" then
        return false, nil, false
    end

    local hasMethod, isZeroMethod = GuardedCall("cooldown-duration:iszero-method", function() return duration.IsZero end)
    if hasMethod and type(isZeroMethod) == "function" then
        local ok, value = GuardedCall("cooldown-duration:iszero-call", isZeroMethod, duration)
        if ok and value ~= nil then
            if IsSecret(value) then
                return true, nil, true
            end
            return true, (value == true), false
        end
    end

    local getValueMethod
    hasMethod, getValueMethod = GuardedCall("cooldown-duration:getvalue-method", function() return duration.GetValue end)
    if hasMethod and type(getValueMethod) == "function" then
        local ok, value = GuardedCall("cooldown-duration:getvalue-call", getValueMethod, duration)
        if ok and value ~= nil then
            if IsSecret(value) then
                return true, nil, true
            end
            if type(value) == "number" then
                return true, value <= 0, false
            end
        end
    end

    return false, nil, false
end

local function GetWidgetCooldownRemaining(btn, now)
    if not btn then return nil end
    if btn.IsForbidden and btn:IsForbidden() then return nil end

    local cooldown = btn.cooldown or btn.Cooldown or btn.IconCooldown or btn.cooldownFrame
    if not cooldown then return nil end

    if cooldown.GetCooldownTimes then
        local ok, startMS, durationMS = GuardedCall("widget-cooldown:get-times", cooldown.GetCooldownTimes, cooldown)
        if ok and type(startMS) == "number" and type(durationMS) == "number" then
            if IsSecret(startMS) or IsSecret(durationMS) then return nil end
            if durationMS <= 0 or startMS <= 0 then return 0 end
            local nowMS = (now or (Private.GetTime and Private.GetTime() or 0)) * 1000
            local remMS = (startMS + durationMS) - nowMS
            if remMS < 0 then remMS = 0 end
            return remMS / 1000
        end
    end

    if cooldown.GetCooldownDuration then
        local ok, startTime, duration = GuardedCall("widget-cooldown:get-duration", cooldown.GetCooldownDuration, cooldown)
        if ok and type(startTime) == "number" and type(duration) == "number" then
            if IsSecret(startTime) or IsSecret(duration) then return nil end
            if duration <= 0 or startTime <= 0 then return 0 end
            local rem = (startTime + duration) - (now or (Private.GetTime and Private.GetTime() or 0))
            if rem < 0 then rem = 0 end
            return rem
        end
    end

    return nil
end

local function ParseSpellCooldownTable(cooldown, now)
    if not cooldown then return false end

    local isOnGCD, isOnGCDSecret = SafeReadMember(cooldown, "isOnGCD")
    if isOnGCD == true then
        return true, true, false, 0, "gcd"
    end

    local duration, durationSecret = SafeReadMember(cooldown, "duration")
    if type(duration) == "number" then
        local startTime, startSecret = SafeReadMember(cooldown, "startTime")
        if type(startTime) == "number" then
            if startTime <= 0 or duration <= 0 or duration <= GCD_THRESHOLD then
                return true, true, false, 0, "cd.num"
            end
            local rem = RemainingFromStartDuration(startTime, duration, now)
            return true, (rem or 0) <= 0.05, false, rem, "cd.num"
        end

        if startSecret then
            return true, nil, true, nil, "cd.secret"
        end

        if duration <= 0 then
            return true, true, false, 0, "cd.num"
        end
        return false
    end

    if durationSecret then
        return true, nil, true, nil, "cd.secret"
    end

    if isOnGCDSecret then
        return true, nil, true, nil, "gcd:secret"
    end

    local durType = type(duration)
    if durType == "table" or durType == "userdata" then
        local hasZero, zero, zeroIsSecret = GetDurationIsZero(duration)
        if hasZero then
            return true, zero, zeroIsSecret, nil, "cd.duration"
        end
    end

    return false
end

local function GetChargesCooldownState(spellID, now)
    if not spellID then return false end

    local spellAPI = C_Spell or _G.C_Spell

    if spellAPI and spellAPI.GetSpellCharges then
        local charges = spellAPI.GetSpellCharges(spellID)
        if charges then
            local maxCharges, maxSecret = SafeReadMember(charges, "maxCharges")
            maxCharges = CleanNumber(maxCharges)
            if maxSecret then
                return true, nil, true, nil, "charges:secret"
            end
            if type(maxCharges) == "number" and maxCharges > 0 then
                local currentCharges, currentSecret = SafeReadMember(charges, "currentCharges")
                currentCharges = CleanNumber(currentCharges)
                if currentSecret then
                    return true, nil, true, nil, "charges:secret"
                end
                if type(currentCharges) == "number" then
                    if currentCharges > 0 then
                        return true, true, false, 0, "charges:ready"
                    end
                    local startTime, startSecret = SafeReadMember(charges, "cooldownStartTime")
                    local duration, durationSecret = SafeReadMember(charges, "cooldownDuration")
                    startTime = CleanNumber(startTime)
                    duration = CleanNumber(duration)
                    if startSecret or durationSecret then
                        return true, nil, true, nil, "charges:secret"
                    end
                    if type(startTime) == "number" and type(duration) == "number" then
                        if startTime <= 0 or duration <= 0 or duration <= GCD_THRESHOLD then
                            return true, true, false, 0, "charges:ready"
                        end
                        local rem = RemainingFromStartDuration(startTime, duration, now)
                        return true, (rem or 0) <= 0.05, false, rem, "charges:cd"
                    end
                end
            end
        end
    end

    if spellAPI and spellAPI.GetSpellChargeDuration then
        local duration = spellAPI.GetSpellChargeDuration(spellID)
        local hasZero, zero, zeroIsSecret = GetDurationIsZero(duration)
        if hasZero then
            return true, zero, zeroIsSecret, nil, "charges:duration"
        end
    end

    return false
end

local function GetSpellCooldownState(spellID, now)
    if not spellID then return false end

    local spellAPI = C_Spell or _G.C_Spell
    local sawSecret = false
    local secretSrc = nil
    local known, ready, readyIsSecret, rem, src = GetChargesCooldownState(spellID, now)
    if known then
        if not readyIsSecret then
            return true, ready, readyIsSecret, rem, src
        end
        sawSecret = true
        secretSrc = src or "charges:secret"
    end

    if spellAPI and spellAPI.GetSpellCooldown then
        local cooldown = spellAPI.GetSpellCooldown(spellID)
        if cooldown then
            known, ready, readyIsSecret, rem, src = ParseSpellCooldownTable(cooldown, now)
            if known then
                if not readyIsSecret then
                    return true, ready, readyIsSecret, rem, "spell:" .. (src or "unknown")
                end
                sawSecret = true
                secretSrc = "spell:" .. (src or "secret")
            end
        end
    end

    if spellAPI and spellAPI.GetSpellCooldownDuration then
        local duration = spellAPI.GetSpellCooldownDuration(spellID)
        local hasZero, zero, zeroIsSecret = GetDurationIsZero(duration)
        if hasZero then
            if not zeroIsSecret then
                return true, zero, zeroIsSecret, nil, "spell:duration"
            end
            sawSecret = true
            secretSrc = "spell:duration"
        end
    end

    if _G.GetSpellCooldown then
        local startTime, duration = _G.GetSpellCooldown(spellID)
        startTime = CleanNumber(startTime)
        duration = CleanNumber(duration)
        if type(startTime) ~= "number" or type(duration) ~= "number" then return false end
        if startTime <= 0 or duration <= 0 or duration <= GCD_THRESHOLD then
            return true, true, false, 0, "spell:ready"
        end
        local rem = RemainingFromStartDuration(startTime, duration, now)
        return true, (rem or 0) <= 0.05, false, rem, "spell:cd"
    end

    if sawSecret then
        return true, nil, true, nil, secretSrc or "spell:secret"
    end

    return false
end

local function GetActionCooldownState(slot, now)
    if not slot then return false end

    local actionAPI = C_ActionBar or _G.C_ActionBar
    local sawSecret = false
    local secretSrc = nil

    if actionAPI and actionAPI.GetActionCharges then
        local charges = actionAPI.GetActionCharges(slot)
        if charges then
            local maxCharges, maxSecret = SafeReadMember(charges, "maxCharges")
            maxCharges = CleanNumber(maxCharges)
            if maxSecret then
                sawSecret = true
                secretSrc = "action:charges:secret"
            end
            if type(maxCharges) == "number" and maxCharges > 0 then
                local currentCharges, currentSecret = SafeReadMember(charges, "currentCharges")
                currentCharges = CleanNumber(currentCharges)
                if currentSecret then
                    sawSecret = true
                    secretSrc = "action:charges:secret"
                end
                if type(currentCharges) == "number" then
                    if currentCharges > 0 then
                        return true, true, false, 0, "action:charges:ready"
                    end
                    local startTime, startSecret = SafeReadMember(charges, "cooldownStartTime")
                    local duration, durationSecret = SafeReadMember(charges, "cooldownDuration")
                    startTime = CleanNumber(startTime)
                    duration = CleanNumber(duration)
                    if startSecret or durationSecret then
                        sawSecret = true
                        secretSrc = "action:charges:secret"
                    end
                    if type(startTime) == "number" and type(duration) == "number" then
                        if startTime <= 0 or duration <= 0 or duration <= GCD_THRESHOLD then
                            return true, true, false, 0, "action:charges:ready"
                        end
                        local rem = RemainingFromStartDuration(startTime, duration, now)
                        return true, (rem or 0) <= 0.05, false, rem, "action:charges:cd"
                    end
                end
            end
        end
    end

    if actionAPI and actionAPI.GetActionCooldown then
        local cooldown = actionAPI.GetActionCooldown(slot)
        if cooldown then
            local isOnGCDValue, isOnGCDSecret = SafeReadMember(cooldown, "isOnGCD")
            local isOnGCD = SafeBool(isOnGCDValue)
            if isOnGCD == true then
                return true, true, false, 0, "action:gcd"
            end

            local startTime, startSecret = SafeReadMember(cooldown, "startTime")
            local duration, durationSecret = SafeReadMember(cooldown, "duration")
            startTime = CleanNumber(startTime)
            duration = CleanNumber(duration)
            if startSecret or durationSecret then
                sawSecret = true
                secretSrc = "action:secret"
            end
            if type(startTime) == "number" and type(duration) == "number" then
                if startTime <= 0 or duration <= 0 or duration <= GCD_THRESHOLD then
                    return true, true, false, 0, "action:ready"
                end
                local rem = RemainingFromStartDuration(startTime, duration, now)
                return true, (rem or 0) <= 0.05, false, rem, "action:cd"
            end

            if isOnGCDSecret then
                sawSecret = true
                secretSrc = "action:gcd:secret"
            end
        end
    end

    if actionAPI and actionAPI.GetActionCooldownDuration then
        local duration = actionAPI.GetActionCooldownDuration(slot)
        local hasZero, zero, zeroIsSecret = GetDurationIsZero(duration)
        if hasZero then
            if not zeroIsSecret then
                return true, zero, zeroIsSecret, nil, "action:duration"
            end
            sawSecret = true
            secretSrc = "action:duration"
        end
    end

    if GetActionCooldown then
        local startTime, duration = GetActionCooldown(slot)
        startTime = CleanNumber(startTime)
        duration = CleanNumber(duration)
        if type(startTime) ~= "number" or type(duration) ~= "number" then return false end
        if startTime <= 0 or duration <= 0 or duration <= GCD_THRESHOLD then
            return true, true, false, 0, "action:ready"
        end
        local rem = RemainingFromStartDuration(startTime, duration, now)
        return true, (rem or 0) <= 0.05, false, rem, "action:cd"
    end

    if sawSecret then
        return true, nil, true, nil, secretSrc or "action:secret"
    end

    return false
end

local function GetWidgetCooldownState(btn, now)
    local rem = GetWidgetCooldownRemaining(btn, now)
    if type(rem) ~= "number" or IsSecret(rem) then return false end
    if rem <= GCD_THRESHOLD then return true, true, false, 0, "widget:ready" end
    return true, rem <= 0.05, false, rem, "widget:cd"
end

function IG:UpdateLocalCooldownBase()
    if not self._localCD then return end
    local spellID = self.interruptSpellID
    if not spellID then
        self._localCD.baseCD = nil
        return
    end

    local cooldown = GetSpellBaseCooldownSeconds(spellID)
    if type(cooldown) == "number" and cooldown >= 0 then
        self._localCD.baseCD = cooldown
    end
end

function IG:RestoreLocalCooldownFromDB()
    if not self._localCD or type(DB.localCD) ~= "table" then return end

    local savedSpellID = CleanNumber(DB.localCD.lastSpellID)
    if type(savedSpellID) == "number" and self.interruptSpellID and savedSpellID ~= self.interruptSpellID then
        DB.localCD.nextReadyTime = nil
        return
    end

    local now = SafeNow()
    local nextReadyTime = CleanNumber(DB.localCD.nextReadyTime)
    if type(nextReadyTime) ~= "number" then
        return
    end

    if type(now) == "number" and nextReadyTime > (now + 0.05) then
        self._localCD.nextReadyTime = nextReadyTime
        self._localCD.lastCastAt = CleanNumber(DB.localCD.lastCastAt)
        self._localCD.baseCD = CleanNumber(DB.localCD.baseCD) or self._localCD.baseCD
        self._localCD.armed = true
    else
        DB.localCD.nextReadyTime = nil
    end
end

function IG:StartLocalCooldownFromCast(spellID)
    if not spellID or not self._localCD then return end
    if not self.interruptSpellSet or not self.interruptSpellSet[spellID] then return end

    local now = SafeNow()
    if type(self._localCD.baseCD) ~= "number" then
        self:UpdateLocalCooldownBase()
    end

    local duration
    local known, ready, readyIsSecret, rem = GetSpellCooldownState(spellID, now)
    if known and not readyIsSecret and not IsSecret(ready) and ready == false
        and type(rem) == "number" and not IsSecret(rem) and rem > (GCD_THRESHOLD + 0.10) then
        duration = rem
    end

    if type(duration) ~= "number" or duration <= 0 then
        local baseCD = self._localCD.baseCD
        if type(baseCD) == "number" and baseCD > 0 then
            duration = baseCD
        end
    end

    if type(duration) ~= "number" or duration <= 0 then
        duration = 15
    end

    self._localCD.lastCastAt = now
    self._localCD.nextReadyTime = now + duration
    self._localCD.armed = true
    if type(DB.localCD) == "table" then
        DB.localCD.nextReadyTime = self._localCD.nextReadyTime
        DB.localCD.lastCastAt = self._localCD.lastCastAt
        DB.localCD.lastSpellID = spellID
        DB.localCD.baseCD = self._localCD.baseCD
    end

    if C_Timer and C_Timer.After then
        local function RefineLocal()
            if not IG or not IG._localCD then return end
            local t = SafeNow()
            local k2, r2, rs2, rem2 = GetSpellCooldownState(spellID, t)
            if k2 and not rs2 and not IsSecret(r2) and r2 == false
                and type(rem2) == "number" and not IsSecret(rem2) and rem2 > (GCD_THRESHOLD + 0.10) then
                IG._localCD.nextReadyTime = t + rem2
                if type(DB.localCD) == "table" then
                    DB.localCD.nextReadyTime = IG._localCD.nextReadyTime
                end
            end
        end

        C_Timer.After(0.05, RefineLocal)
        C_Timer.After(0.15, RefineLocal)
    end
end

local candRem = {}
local candSrc = {}
local candConf = {}
local candCount = 0
local candDbg = {}
local candDbgCount = 0
local candSawSecret = false

local function WipeCandidates()
    for i = 1, candCount do
        candRem[i] = nil
        candSrc[i] = nil
        candConf[i] = nil
    end
    candCount = 0
    for i = 1, candDbgCount do
        candDbg[i] = nil
    end
    candDbgCount = 0
    candSawSecret = false
end

local function AddCandidate(known, ready, readyIsSecret, rem, src, confidence, doDbg)
    if not known then return end
    if readyIsSecret or IsSecret(ready) then
        candSawSecret = true
        return
    end
    local isReady = (ready == true)
    local remaining = CleanNumber(rem)
    if type(remaining) ~= "number" then
        if isReady then remaining = 0 else return end
    elseif remaining < 0 then
        if isReady then remaining = 0 else return end
    end

    candCount = candCount + 1
    candRem[candCount] = remaining
    candSrc[candCount] = (type(src) == "string" and src or "unknown-src")
    candConf[candCount] = confidence or 0
    if doDbg then
        candDbgCount = candDbgCount + 1
        candDbg[candDbgCount] = tostring(src) .. "=" .. string.format("%.3f", remaining) .. ":c" .. tostring(confidence or 0)
    end
end

function IG:UpdateInterruptReady()
    local ok, err = pcall(function()
        local now = SafeNow()

        if self._localCD and type(self._localCD.nextReadyTime) == "number" and type(now) == "number" then
            if (self._localCD.nextReadyTime - now) <= 0 then
                self._localCD.nextReadyTime = nil
                if type(DB.localCD) == "table" then
                    DB.localCD.nextReadyTime = nil
                end
            end
        end

        self.cdSrc = nil
        self.cdRem = nil
        self.interruptReadyIsSecret = false

        WipeCandidates()
        local localRemVal, localArmedVal = nil, false
        local doDbg = (DB and DB.debug) and true or false

        if self.primarySlot then
            local okSlot, _, reason = self:ValidateInterruptSlot(self.primarySlot, now)
            if okSlot == true then
                local k, r, rs, rm, s = GetActionCooldownState(self.primarySlot, now)
                AddCandidate(k, r, rs, rm, s, 2, doDbg)
                if DB and DB.debug and IG._dbgStats and IG._dbgStats.slot then
                    IG._dbgStats.slot.ok = (IG._dbgStats.slot.ok or 0) + 1
                end
            else
                if doDbg and reason then
                    candDbgCount = candDbgCount + 1
                    candDbg[candDbgCount] = "slot" .. tostring(self.primarySlot) .. "=invalid:" .. tostring(reason)
                end
                if DB and DB.debug and IG._dbgStats and IG._dbgStats.slot then
                    IG._dbgStats.slot.bad = (IG._dbgStats.slot.bad or 0) + 1
                end
            end
        end

        if self.primaryButton then
            local liveSlot = GetButtonActionSlot(self.primaryButton)
            if type(liveSlot) == "number" and liveSlot ~= self.primarySlot then
                local okSlot, _, reason = self:ValidateInterruptSlot(liveSlot, now)
                if okSlot == true then
                    local k, r, rs, rm, s = GetActionCooldownState(liveSlot, now)
                    if k and type(s) == "string" then s = s .. ":liveSlot" end
                    AddCandidate(k, r, rs, rm, s, 2, doDbg)
                    if DB and DB.debug and IG._dbgStats and IG._dbgStats.slot then
                        IG._dbgStats.slot.ok = (IG._dbgStats.slot.ok or 0) + 1
                    end
                else
                    if doDbg and reason then
                        candDbgCount = candDbgCount + 1
                        candDbg[candDbgCount] = "slot" .. tostring(liveSlot) .. "=invalid:" .. tostring(reason)
                    end
                    if DB and DB.debug and IG._dbgStats and IG._dbgStats.slot then
                        IG._dbgStats.slot.bad = (IG._dbgStats.slot.bad or 0) + 1
                    end
                end
            end
        end

        local fallbackBtn = self.primaryButton or self.cdmButton
        if fallbackBtn then
            local k, r, rs, rm, s = GetWidgetCooldownState(fallbackBtn, now)
            AddCandidate(k, r, rs, rm, s, 0, doDbg)
        end
        if self.cdmButton and self.cdmButton ~= fallbackBtn then
            local k, r, rs, rm, s = GetWidgetCooldownState(self.cdmButton, now)
            AddCandidate(k, r, rs, rm, s, 0, doDbg)
        end

        if self.interruptSpellID then
            local k, r, rs, rm, s = GetSpellCooldownState(self.interruptSpellID, now)
            AddCandidate(k, r, rs, rm, s, 2, doDbg)
        end

        local localRem = GetLocalCooldownRemaining(self._localCD, now)
        if type(localRem) == "number" and not IsSecret(localRem) then
            local armed = (self._localCD and (
                self._localCD.armed == true
                or type(self._localCD.lastCastAt) == "number"
                or type(self._localCD.nextReadyTime) == "number"
            )) and true or false
            localArmedVal = armed
            localRemVal = localRem
            local conf = armed and 3 or 1
            candCount = candCount + 1
            candRem[candCount] = localRem
            candSrc[candCount] = "local"
            candConf[candCount] = conf
            if doDbg then
                candDbgCount = candDbgCount + 1
                candDbg[candDbgCount] = "local=" .. string.format("%.3f", localRem) .. ":c" .. tostring(conf)
            end
        end

        local known = (candCount > 0)
        if known then
            local maxHCRem, maxHCSrc = 0, nil
            local maxLCRem, maxLCSrc = 0, nil
            local hasHC = false

            for i = 1, candCount do
                local remaining = candRem[i]
                if type(remaining) == "number" and remaining >= 0 then
                    if (candConf[i] or 0) >= 2 then
                        hasHC = true
                        if remaining > maxHCRem then
                            maxHCRem = remaining
                            maxHCSrc = candSrc[i]
                        end
                    else
                        if remaining > maxLCRem then
                            maxLCRem = remaining
                            maxLCSrc = candSrc[i]
                        end
                    end
                end
            end

            if hasHC then
                self.cdRem = maxHCRem
                self.cdSrc = maxHCSrc or "mixed-hc"
                self.interruptReady = (maxHCRem <= 0.05)
            elseif maxLCRem > 0.05 then
                self.cdRem = maxLCRem
                self.cdSrc = maxLCSrc or "mixed-lc"
                self.interruptReady = false
            else
                self.cdRem = 0
                self.cdSrc = maxLCSrc or "mixed-lc"
                self.interruptReady = true
            end
        end

        if not known and localArmedVal and type(localRemVal) == "number" and not IsSecret(localRemVal) and localRemVal <= 0.05 then
            known = true
            self.cdRem = 0
            self.cdSrc = "local:armed-backstop"
            self.interruptReady = true
        end

        if not known then
            if candSawSecret then
                known = true
                self.interruptReady = true
                self.interruptReadyIsSecret = true
                self.cdRem = nil
                self.cdSrc = "secret"
            end
        end

        if not known then
            self.interruptReady = true
            self.interruptReadyIsSecret = false
            self.cdRem = nil
            self.cdSrc = "unknown"
        end

        if DB and DB.debug then
            local src = tostring(self.cdSrc or "nil")
            local key = src:match("^([^:]+)") or src
            IG:StatInc("cd", key)
        end

        if doDbg then
            self._cdCandidatesDbg = table.concat(candDbg, ",", 1, candDbgCount)
        else
            self._cdCandidatesDbg = nil
        end

        if DB and DB.debug then
            local prevReady = self._dbgPrevReady
            local prevSrc = self._dbgPrevSrc
            local prevRem = self._dbgPrevRem
            local curReady = self.interruptReady
            local curSrc = self.cdSrc
            local curRem = self.cdRem
            local changed = (prevReady ~= curReady) or (prevSrc ~= curSrc)
            if not changed then
                local p = (type(prevRem) == "number" and prevRem > 0.05) and 1 or 0
                local c = (type(curRem) == "number" and curRem > 0.05) and 1 or 0
                if p ~= c then changed = true end
            end
            if changed then
                self._dbgPrevReady = curReady
                self._dbgPrevSrc = curSrc
                self._dbgPrevRem = curRem
                Debug(("CD decision: ready=%s rem=%s src=%s localArmed=%s cand=%s")
                    :format(
                        SafeValueString(curReady),
                        SafeValueString(curRem),
                        SafeValueString(curSrc),
                        tostring(self._localCD and self._localCD.armed),
                        tostring(self._cdCandidatesDbg)
                    ), 2, "cd")
            end
        end

        if self._localCD and type(now) == "number" then
            if self.interruptReady == true then
                self._localCD.nextReadyTime = nil
                if type(DB.localCD) == "table" then DB.localCD.nextReadyTime = nil end
            elseif type(self.cdRem) == "number" and not IsSecret(self.cdRem) and self.cdRem > 0.05 then
                local nextReadyTime = now + self.cdRem
                local current = (type(self._localCD.nextReadyTime) == "number") and self._localCD.nextReadyTime or nil
                if (current == nil) or (nextReadyTime > current) then
                    self._localCD.nextReadyTime = nextReadyTime
                    self._localCD.armed = true
                    if type(DB.localCD) == "table" then DB.localCD.nextReadyTime = nextReadyTime end
                end
            end
        end

        CancelTimer(self._cdExpireTimer)
        self._cdExpireTimer = nil
        CancelTimer(self._cdUnknownTimer)
        self._cdUnknownTimer = nil

        if type(self.cdRem) == "number" and not IsSecret(self.cdRem) and self.cdRem > 0.05 and C_Timer and C_Timer.NewTimer then
            local delay = self.cdRem + 0.05
            self._cdExpireTimer = C_Timer.NewTimer(delay, function()
                IG._cdExpireTimer = nil
                IG:MarkReadyDirty("cd-expire")
            end)
        elseif (self.cdSrc == "unknown" or self.cdSrc == "secret") and (CastActive.target or CastActive.focus) and C_Timer and C_Timer.NewTimer then
            self._cdUnknownTimer = C_Timer.NewTimer(0.8, function()
                IG._cdUnknownTimer = nil
                IG:MarkReadyDirty("cd-unknown")
            end)
        end
    end)

    if not ok then
        self.interruptReady = false
        self.interruptReadyIsSecret = false
        self.cdRem = nil
        self.cdSrc = "error"
        self._cdCandidatesDbg = nil
        CancelTimer(self._cdExpireTimer)
        self._cdExpireTimer = nil
        CancelTimer(self._cdUnknownTimer)
        self._cdUnknownTimer = nil
        if self.HandleError then
            self:HandleError(err, "UpdateInterruptReady")
        else
            Debug("UpdateInterruptReady failed: " .. tostring(err))
        end
    end
end

function IG:MarkReadyDirty(reason)
    if self._readyDirty then return end
    self._readyDirty = true
    if self._readyTimer then return end

    local function FlushReady()
        IG._readyTimer = nil
        IG._readyDirty = false
        IG:UpdateInterruptReady()
        IG:ScheduleCDTextTick()
        if IG.MarkGlowDirty then
            IG:MarkGlowDirty()
        else
            IG:ApplyGlowDecision()
        end
    end

    if C_Timer and C_Timer.NewTimer then
        self._readyTimer = C_Timer.NewTimer(READY_COALESCE_WINDOW, FlushReady)
    elseif C_Timer and C_Timer.After then
        self._readyTimer = true
        C_Timer.After(0, FlushReady)
    else
        self._readyTimer = nil
        self._readyDirty = false
        self:UpdateInterruptReady()
        self:ScheduleCDTextTick()
        self:ApplyGlowDecision()
    end
end

function IG:HookCooldownDoneFrames()
    if InCombatLockdown and InCombatLockdown() then return end

    local function Hook(btn)
        if not btn then return end
        if btn.IsForbidden and btn:IsForbidden() then return end

        local cooldown = btn.cooldown or btn.Cooldown or btn.IconCooldown or btn.cooldownFrame
        if cooldown and cooldown.HookScript and not HookedCooldowns[cooldown] then
            HookedCooldowns[cooldown] = true
            cooldown:HookScript("OnCooldownDone", function()
                IG:MarkReadyDirty("cd-done")
            end)
        end
    end

    Hook(self.primaryButton)
    for i = 1, #self.trackedButtons do
        Hook(self.trackedButtons[i])
    end
    for i = 1, #self.extraButtons do
        Hook(self.extraButtons[i])
    end
end

local function EnsureCDText(btn)
    if not btn or ButtonCDText[btn] then return end
    if btn.IsForbidden and btn:IsForbidden() then return end
    if not btn.CreateFontString then return end

    local fontString = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fontString:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fontString:SetText("")
    fontString:Hide()
    ButtonCDText[btn] = fontString
end

function IG:PrepareCDText()
    if InCombatLockdown and InCombatLockdown() then
        self._cdTextDeferred = true
        return
    end

    self._cdTextDeferred = false
    for i = 1, #self.trackedButtons do
        EnsureCDText(self.trackedButtons[i])
    end
    for i = 1, #self.extraButtons do
        EnsureCDText(self.extraButtons[i])
    end
end

function IG:SetCDTextEnabled(enabled)
    DB.cdText = enabled and true or false

    if DB.cdText then
        self:PrepareCDText()
        self:ScheduleCDTextTick()
    else
        CancelTimer(self._cdTextTimer)
        self._cdTextTimer = nil
        for i = 1, #self.trackedButtons do
            local fontString = GetButtonCDText(self.trackedButtons[i])
            if fontString then fontString:Hide() end
        end
        for i = 1, #self.extraButtons do
            local fontString = GetButtonCDText(self.extraButtons[i])
            if fontString then fontString:Hide() end
        end
    end
end

function IG:UpdateCDText()
    if not DB.cdText then return end

    if self._cdTextDeferred and not (InCombatLockdown and InCombatLockdown()) then
        self:PrepareCDText()
    end

    local rem = self.cdRem
    local text = ""
    if type(rem) == "number" and not IsSecret(rem) and rem > 0.05 then
        text = tostring(math.ceil(rem))
    end

    for i = 1, #self.trackedButtons do
        local fontString = GetButtonCDText(self.trackedButtons[i])
        if fontString then
            if text ~= "" then fontString:SetText(text); fontString:Show() else fontString:Hide() end
        end
    end
    for i = 1, #self.extraButtons do
        local fontString = GetButtonCDText(self.extraButtons[i])
        if fontString then
            if text ~= "" then fontString:SetText(text); fontString:Show() else fontString:Hide() end
        end
    end
end

function IG:ScheduleCDTextTick()
    if not DB.cdText then
        CancelTimer(self._cdTextTimer)
        self._cdTextTimer = nil
        return
    end

    self:UpdateCDText()

    local rem = CleanNumber(self.cdRem)
    if type(rem) ~= "number" or rem <= 0.05 then
        CancelTimer(self._cdTextTimer)
        self._cdTextTimer = nil
        return
    end

    local frac = rem - math.floor(rem)
    local delay
    if frac < 0.05 then
        delay = 0.95
    else
        delay = frac
    end

    CancelTimer(self._cdTextTimer)
    self._cdTextTimer = nil

    if C_Timer and C_Timer.NewTimer then
        self._cdTextTimer = C_Timer.NewTimer(delay, function()
            IG._cdTextTimer = nil
            IG:ScheduleCDTextTick()
        end)
    end
end

Private.CancelTimer = CancelTimer
Private.GetButtonCDText = GetButtonCDText
Private.GetLocalCooldownRemaining = GetLocalCooldownRemaining
Private.GetSpellCooldownState = GetSpellCooldownState
Private.GetActionCooldownState = GetActionCooldownState
Private.GetWidgetCooldownState = GetWidgetCooldownState
