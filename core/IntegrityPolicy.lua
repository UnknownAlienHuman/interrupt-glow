local IG = _G.InterruptGlow
if not IG or not IG.Data or not IG.Buttons or not IG.Glow then return end
if IG.modules and IG.modules.IntegrityPolicy then return end

local Data = IG.Data
local Buttons = IG.Buttons
local Glow = IG.Glow
local CDM = IG.CDM
local CastTracking = IG.CastTracking

local _G = _G
local type = type
local pcall = pcall
local rawget = rawget
local pairs = pairs

local function PositiveNumber(value)
    if not IG.CanAccess(value) then return nil end
    if type(value) == "string" then value = tonumber(value) end
    if type(value) == "number" and value > 0 then return value end
    return nil
end

local function SafeMethod(object, methodName)
    if not IG.CanAccess(object) or object == nil then return nil end
    local method, known = IG:ReadMember(object, methodName)
    if not known or type(method) ~= "function" then return nil end
    return method
end

local function SafeMethodCall(object, methodName, ...)
    local method = SafeMethod(object, methodName)
    if not method then return false, nil end
    local ok, value = pcall(method, object, ...)
    if not ok or not IG.CanAccess(value) then return false, nil end
    return true, value
end

-- C_SpellBook.IsSpellKnownOrInSpellBook is part of the pinned 12.1 contract.
-- If that contract is unavailable, static spec tables must not become positive
-- proof for direct-spell, pet, or Cooldown Viewer records. A runtime family
-- already proven by C_ActionBar.IsInterruptAction remains usable for the current
-- specialization; native action records retain their authoritative slot path.
local originalGetCanonicalSpellID = Data.GetCanonicalSpellID
function Data:GetCanonicalSpellID(spellID, sourceKind)
    if not IG.CanAccess(spellID) or type(spellID) ~= "number" then return nil end

    local spellBook = _G.C_SpellBook
    if spellBook and type(spellBook.IsSpellKnownOrInSpellBook) == "function" then
        return originalGetCanonicalSpellID(self, spellID, sourceKind)
    end

    if sourceKind == "action" then
        return originalGetCanonicalSpellID(self, spellID, sourceKind)
    end

    local runtimeCanonical = self.runtimeInterrupts and self.runtimeInterrupts[spellID]
    if type(runtimeCanonical) == "number" then return runtimeCanonical end

    IG:BumpStat("data.spellBookContractUnavailable")
    return nil
end

-- RuntimeInterruptPolicy keeps a bounded negative cache. Older implementations
-- removed a newly-positive key without decrementing the parallel count, causing
-- needless whole-cache resets later in the session. Repair only when the wrapped
-- implementation demonstrably left the count unchanged.
local originalMatchesCurrentInterrupt = Data.MatchesCurrentInterrupt
function Data:MatchesCurrentInterrupt(spellID)
    local negatives = self.negativeCooldownSpellMatches
    local beforeCount = self.negativeCooldownSpellMatchCount
    local wasNegative = type(negatives) == "table"
        and IG.CanAccess(spellID)
        and negatives[spellID] == true

    local matches = originalMatchesCurrentInterrupt(self, spellID)

    if matches == true
        and wasNegative
        and negatives[spellID] == nil
        and type(beforeCount) == "number"
        and self.negativeCooldownSpellMatchCount == beforeCount
        and beforeCount > 0
    then
        self.negativeCooldownSpellMatchCount = beforeCount - 1
    end
    return matches
end

local function SafeResolveActionSlot(button)
    if not IG.CanAccess(button) or button == nil then return nil end

    local stateType, typeKnown = IG:ReadMember(button, "_state_type")
    if typeKnown and stateType == "action" then
        local stateAction, actionKnown = IG:ReadMember(button, "_state_action")
        if actionKnown then
            local slot = PositiveNumber(stateAction)
            if slot then return slot end
        end
    end

    local action, actionKnown = IG:ReadMember(button, "action")
    if actionKnown then return PositiveNumber(action) end
    return nil
end

local function SafeResolveDirectSpellID(button)
    if not IG.CanAccess(button) or button == nil then return nil end

    local method = SafeMethod(button, "GetSpellId") or SafeMethod(button, "GetSpellID")
    if method then
        local ok, spellID = pcall(method, button)
        if ok and IG.CanAccess(spellID) and type(spellID) == "number" then
            return spellID
        end
        return nil
    end

    local stateType, typeKnown = IG:ReadMember(button, "_state_type")
    if typeKnown and stateType == "spell" then
        local stateAction, actionKnown = IG:ReadMember(button, "_state_action")
        if actionKnown then return PositiveNumber(stateAction) end
    end
    return nil
end

-- The base resolver's direct-spell fallback historically indexed foreign frame
-- methods before the protected member boundary. Action-backed records continue
-- through the optimized resolver; only no-slot direct-spell records are handled
-- here, entirely through access-gated member reads.
local originalResolveRecord = Buttons.ResolveRecord
function Buttons:ResolveRecord(record)
    if not record then return false end
    if record.adapter == "pet"
        or record.adapter == "cdm"
        or record.adapter == "buttonforge"
    then
        return originalResolveRecord(self, record)
    end

    if SafeResolveActionSlot(record.button) then
        return originalResolveRecord(self, record)
    end

    local spellID = SafeResolveDirectSpellID(record.button)
    if not spellID then return false end

    local canonicalSpellID = Data:GetCanonicalSpellID(spellID, "spell")
    if not canonicalSpellID then return false end
    return true, "spell", canonicalSpellID, spellID, canonicalSpellID
end

-- ButtonForge globals and API results are foreign data. Preserve the ordinary
-- addon-owned table fast path, but access frame methods and API returns through
-- explicit fail-closed boundaries.
function Buttons:ResolveButtonForge(record)
    if not record then return false end

    local button = record.button
    local buttonObject = record.buttonForgeObject
    if not buttonObject then
        local value, known = IG:ReadMember(button, "ParentButton")
        if known then buttonObject = value end
    end

    if IG.CanAccess(buttonObject) and type(buttonObject) == "table" then
        record.buttonForgeObject = buttonObject
        local mode = rawget(buttonObject, "Mode")
        local macroMode = rawget(buttonObject, "MacroMode")
        local rawSpellID = rawget(buttonObject, "SpellId")
        local spellID = type(rawSpellID) == "number" and rawSpellID or nil

        local resolvesSpell = mode == "spell" or (mode == "macro" and macroMode == "spell")
        if resolvesSpell and spellID then
            local canonicalSpellID = Data:GetCanonicalSpellID(spellID, "spell")
            if canonicalSpellID then
                return true, "spell", canonicalSpellID, spellID, canonicalSpellID
            end
        end
        if mode ~= nil then return false end
    end

    local getName = SafeMethod(button, "GetName")
    local name = nil
    if getName then
        local ok, value = pcall(getName, button)
        if ok and IG.CanAccess(value) and type(value) == "string" then name = value end
    end

    local api = _G.ButtonForge_API1
    local getInfo = api and api.GetButtonActionInfo
    if name and type(getInfo) == "function" then
        local ok, actionType, id = pcall(getInfo, name)
        if ok and IG.CanAccess(actionType) and IG.CanAccess(id)
            and actionType == "spell" and type(id) == "number"
        then
            local canonicalSpellID = Data:GetCanonicalSpellID(id, "spell")
            if canonicalSpellID then
                return true, "spell", canonicalSpellID, id, canonicalSpellID
            end
        end
    end
    return false
end

-- Keep record diagnostics and downstream policy fields synchronized through
-- unbind/rebind cycles. These fields are ordinary normalized booleans only.
local originalUnbindRecord = Buttons.UnbindRecord
function Buttons:UnbindRecord(record)
    originalUnbindRecord(self, record)
    if record then
        record.hardRestrictedCooldown = false
        record.readinessPending = false
    end
end

local originalAttachRecordToAbility = Buttons.AttachRecordToAbility
function Buttons:AttachRecordToAbility(record, canonicalSpellID, sourceKind, sourceID)
    local ability = originalAttachRecordToAbility(self, record, canonicalSpellID, sourceKind, sourceID)
    if record and ability then
        record.hardRestrictedCooldown = ability.hardRestricted == true
        record.readinessPending = ability.readinessPending == true
    end
    return ability
end

-- Font strings are created lazily and therefore can encounter a provider frame
-- whose access state changed after shell prewarm. Never index/call that foreign
-- method directly and never retry a permanently unreadable owner every frame.
function Glow:EnsureCooldownText(record)
    if not IG.DB.cdText then return nil end
    if not record or record.cooldownTextForbidden then return nil end

    local overlay = record.overlay
    if not overlay then return nil end
    if overlay.cooldownText then return overlay.cooldownText end
    if IG:IsInCombat() then
        record.cooldownTextPending = true
        return nil
    end

    local createFontString = SafeMethod(record.button, "CreateFontString")
    if not createFontString then
        record.cooldownTextForbidden = true
        record.cooldownTextPending = false
        IG:BumpStat("ui.cooldownTextOwnerRejected")
        return nil
    end

    local ok, text = pcall(createFontString, record.button, nil, "OVERLAY", "NumberFontNormalLarge")
    if not ok or not IG.CanAccess(text) or text == nil then
        record.cooldownTextForbidden = true
        record.cooldownTextPending = false
        IG:BumpStat("ui.cooldownTextCreateFailed")
        return nil
    end

    text:SetPoint("CENTER", record.button, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetText("")
    text:Show()
    overlay.cooldownText = text
    record.cooldownTextPending = false
    IG:BumpStat("ui.cooldownTextsCreated")
    return text
end

if CDM then
    local function ReadCDMIdentity(itemFrame)
        local ok, spellID = SafeMethodCall(itemFrame, "GetBaseSpellID")
        if not ok or type(spellID) ~= "number" then return nil, false end
        return Data:GetCanonicalSpellID(spellID, "spell"), true
    end

    local function QueueCDMIdentity(record, itemFrame, canonicalSpellID)
        if not record or record.adapter ~= "cdm" then return false end
        if record.cdmCanonicalSpellID == canonicalSpellID then return false end
        record.cdmCanonicalSpellID = canonicalSpellID
        IG:MarkButtonDirty(itemFrame)
        return true
    end

    function CDM:ObserveItem(itemFrame)
        if not self.attached or not IG.playerLoginSeen or not IG.DB.cdm
            or not itemFrame or not IG.Buttons
        then
            return
        end

        local canonicalSpellID, identityReadable = ReadCDMIdentity(itemFrame)
        local record = IG.ObservedButtons[itemFrame]
        if not identityReadable then
            if QueueCDMIdentity(record, itemFrame, nil) then
                IG:BumpStat("cdm.identityRestricted")
            end
            return
        end

        if not canonicalSpellID then
            if QueueCDMIdentity(record, itemFrame, nil) then
                IG:BumpStat("cdm.identityCleared")
            end
            return
        end

        if record and record.adapter == "cdm" then
            if QueueCDMIdentity(record, itemFrame, canonicalSpellID) then
                IG:BumpStat("cdm.identityChanged")
            end
            return
        end

        record = IG.Buttons:ObserveButton(itemFrame, "cdm", { skipDirty = true })
        if record then
            record.cdmCanonicalSpellID = canonicalSpellID
            IG:MarkButtonDirty(itemFrame)
            IG:BumpStat("cdm.interruptItemsObserved")
        end
    end
end

-- A disabled master switch must not leave fixed-unit cast watchers performing
-- snapshots. Existing dedicated runtime-sleep policy remains authoritative; the
-- fallback below installs only when that policy is absent.
if CastTracking and not (IG.modules and IG.modules.RuntimeSleepPolicy) then
    local originalRefreshUnit = CastTracking.RefreshUnit
    local originalRefreshAll = CastTracking.RefreshAll
    local originalOnUnitEvent = CastTracking.OnUnitEvent

    local function Suspend(self)
        if self.integritySleeping then return end
        self.integritySleeping = true
        for _, unit in pairs({ "target", "focus" }) do
            self.channelSuppressed[unit] = false
            local state = IG.CastState[unit]
            if state then
                state.active = false
                state.hostile = false
                state.castBarID = nil
                state.isChannel = false
                state.niState = "none"
                state.channelSuppressed = false
            end
            if IG.Glow then
                IG.Glow:ApplyUnitInterruptibility(unit, false, false)
                IG.Glow:RefreshUnit(unit)
            end
        end
        if IG.Glow then IG.Glow:SetRuntimeWorkerEnabled(false) end
        IG:BumpStat("runtime.disabledSleeps")
    end

    function CastTracking:RefreshUnit(...)
        if IG.DB.enabled ~= true and IG.testMode ~= true then
            Suspend(self)
            return
        end
        self.integritySleeping = false
        return originalRefreshUnit(self, ...)
    end

    function CastTracking:RefreshAll(...)
        if IG.DB.enabled ~= true and IG.testMode ~= true then
            Suspend(self)
            return
        end
        self.integritySleeping = false
        return originalRefreshAll(self, ...)
    end

    function CastTracking:OnUnitEvent(...)
        if IG.DB.enabled ~= true and IG.testMode ~= true then
            Suspend(self)
            return
        end
        self.integritySleeping = false
        return originalOnUnitEvent(self, ...)
    end
end

IG:RegisterModule("IntegrityPolicy", {
    spellBookContractFailsClosed = true,
    runtimeProofSurvivesMissingSpellBook = true,
    foreignDirectSpellMethodsAreGated = true,
    buttonForgeMethodsAreGated = true,
    cdmIdentityMethodsAreGated = true,
    cooldownTextOwnerIsGated = true,
    negativeCacheCountIsRepaired = true,
    recordRestrictionStateIsSynchronized = true,
    disabledCastFallbackSleeps = true,
})
