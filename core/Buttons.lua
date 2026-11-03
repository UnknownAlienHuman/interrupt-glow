local IG = _G.InterruptGlow
if not IG then return end

local Buttons = {
    attached = false,
    nativeAttached = false,
    buttonForgeAttached = false,
    buttonForgeHooked = false,
    buttonForgeClearHooked = false,
    dominosAttached = false,
    dominosHooked = false,
    dominosWaiterPending = false,
    buttonForgeWaiterPending = false,
    labLibraries = setmetatable({}, { __mode = "k" }),
    labDiscoveredLibraries = setmetatable({}, { __mode = "k" }),
    knownLABWaiters = {},
    dominosButtonsBySlot = {},
    dominosDiscovered = false,
    buttonForgeDiscovered = false,
}
IG.Buttons = Buttons

local _G = _G
local GetPetActionInfo = _G.GetPetActionInfo
local EventRegistry = _G.EventRegistry
local EventUtil = _G.EventUtil
local hooksecurefunc = _G.hooksecurefunc
local pcall = pcall
local type = type
local pairs = pairs
local next = next
local tostring = tostring
local rawget = rawget

local ADAPTER_PRIORITY = {
    native = 1,
    dominos = 2,
    lab = 3,
    buttonforge = 4,
    pet = 5,
    cdm = 6,
}

local SOURCE_PRIORITY = {
    action = 300,
    pet = 200,
    spell = 100,
}

local buttonsByName = setmetatable({}, { __mode = "v" })

local function GetLibrary(name)
    local LibStub = _G.LibStub
    if not IG.CanAccess(LibStub) or LibStub == nil then return nil end

    local getLibrary = type(LibStub) == "table"
        and IG:ReadMember(LibStub, "GetLibrary")
        or nil
    if type(getLibrary) == "function" then
        local ok, library = pcall(getLibrary, LibStub, name, true)
        if ok and IG.CanAccessTable(library) then return library end
        return nil
    end

    if type(LibStub) == "function" then
        local ok, library = pcall(LibStub, name, true)
        if ok and IG.CanAccessTable(library) then return library end
    end
    return nil
end

local function IsFrameObject(value)
    if not IG.CanAccess(value) then return false end
    local valueType = type(value)
    return valueType == "table" or valueType == "userdata"
end

local function GetFrameName(frame)
    if not IG.CanAccess(frame) or frame == nil then return nil end
    local getName, known = IG:ReadMember(frame, "GetName")
    if not known or type(getName) ~= "function" then return nil end
    local ok, name = pcall(getName, frame)
    if not ok or not IG.CanAccess(name) or type(name) ~= "string" then
        return nil
    end
    return name
end

local function BuildAbilityKey(canonicalSpellID, sourceKind, sourceID)
    -- The normal path uses a numeric key and allocates no string during rapid
    -- conditional-macro transitions. The fallback is only for an interrupt
    -- action whose spell identity is unavailable.
    if type(canonicalSpellID) == "number" then
        return canonicalSpellID
    end
    return tostring(sourceKind or "unknown") .. ":" .. tostring(sourceID or 0)
end

function Buttons:ObserveButton(button, adapter, extra)
    if not IsFrameObject(button) then return nil end

    local record = IG.ObservedButtons[button]
    local created = record == nil
    if created then
        record = {
            button = button,
            adapter = adapter or "native",
            isInterrupt = false,
            ready = false,
            restrictedCooldown = false,
            sourceKind = nil,
            sourceID = nil,
            spellID = nil,
            canonicalSpellID = nil,
            abilityKey = nil,
            ability = nil,
            deadline = nil,
            lastCooldownText = "",
        }
        IG.ObservedButtons[button] = record
        IG:BumpStat("buttons.observed")
    elseif adapter then
        local oldPriority = ADAPTER_PRIORITY[record.adapter] or 0
        local newPriority = ADAPTER_PRIORITY[adapter] or 0
        if newPriority > oldPriority then
            record.adapter = adapter
        end
    end

    if extra then
        if extra.petSlot then record.petSlot = extra.petSlot end
        if extra.buttonForgeObject then record.buttonForgeObject = extra.buttonForgeObject end
    end

    -- Prewarm the secret-safe shell incrementally. Confirmed interrupt buttons
    -- are promoted to the front of the queue by ReconcileRecord.
    if not record.overlay and IG.Glow then
        IG.Glow:QueueShell(record, false)
    end

    if IG.ConditionalActions then IG.ConditionalActions:Observe(button, record) end
    if created or not (extra and extra.skipDirty) then
        IG:MarkButtonDirty(button)
    end
    return record
end

function Buttons:RebuildAbilitySource(ability)
    if not ability then return false end
    local bestKind, bestID, bestPriority
    for record in pairs(ability.records) do
        local sourceID = record.sourceID
        local priority = record.isInterrupt == true
            and type(record.sourceKind) == "string"
            and SOURCE_PRIORITY[record.sourceKind]
        if priority and type(sourceID) == "number"
            and (priority > (bestPriority or -1)
                or (priority == bestPriority and type(bestID) == "number" and sourceID < bestID))
        then
            bestPriority = priority
            bestKind = record.sourceKind
            bestID = sourceID
        end
    end

    if bestKind == nil then
        if next(ability.records) == nil then
            -- Same-spec conditional macro churn can reuse this canonical record
            -- without reallocating it or re-reading its source immediately.
            ability.dormant = true
            return false
        end

        -- A bound interrupt with no eligible source is unknown. Clear any old
        -- source and keep readiness pending until a valid identity is observed.
        local changed = ability.sourceKind ~= nil or ability.sourceID ~= nil
            or ability.dormant ~= false or ability.hasEvaluation ~= false
            or ability.ready ~= false or ability.restricted ~= true
            or ability.readinessRestricted ~= true or ability.timingRestricted ~= true
            or ability.hardRestricted ~= true or ability.needsPoll ~= false
            or ability.deadline ~= nil or ability.readinessPending ~= true
        ability.sourceKind = nil
        ability.sourceID = nil
        ability.sourceChanged = true
        ability.dormant = false
        ability.hasEvaluation = false
        ability.evaluatedGeneration = nil
        ability.ready = false
        ability.restricted = true
        ability.readinessRestricted = true
        ability.timingRestricted = true
        ability.hardRestricted = true
        ability.needsPoll = false
        ability.deadline = nil
        ability.readinessPending = true
        for record in pairs(ability.records) do
            record.ready = false
            record.deadline = nil
            record.restrictedCooldown = true
            record.hardRestrictedCooldown = true
            record.readinessPending = true
        end
        if changed then
            IG:BumpStat("cooldown.boundAbilityMissingSource")
            IG:MarkCooldownDirty()
        end
        return false
    end

    ability.dormant = false
    if ability.sourceKind ~= bestKind or ability.sourceID ~= bestID then
        ability.sourceKind = bestKind
        ability.sourceID = bestID
        ability.sourceChanged = true
        ability.hasEvaluation = false
        ability.evaluatedGeneration = nil
        ability.ready = false
        ability.deadline = nil
        ability.needsPoll = false
        ability.restricted = false
        ability.readinessRestricted = false
        ability.timingRestricted = false
        ability.hardRestricted = false
        ability.readinessPending = true
        for record in pairs(ability.records) do
            record.ready = false
            record.deadline = nil
            record.restrictedCooldown = false
            record.hardRestrictedCooldown = false
            record.readinessPending = true
        end
        IG:MarkCooldownDirty()
        return true
    end
    return false
end

function Buttons:DetachRecordFromAbility(record)
    local ability = record and record.ability
    if not ability then return end

    ability.records[record] = nil
    record.ability = nil
    record.abilityKey = nil

    if next(ability.records) == nil then
        -- Keep the small canonical ability object dormant. Conditional macros can
        -- switch between heal/interrupt feedback on every mouseover transition;
        -- deleting and recreating this table would turn that path into GC churn.
        ability.dormant = true
    else
        self:RebuildAbilitySource(ability)
    end
end

function Buttons:AttachRecordToAbility(record, canonicalSpellID, sourceKind, sourceID)
    local key = BuildAbilityKey(canonicalSpellID, sourceKind, sourceID)
    local ability = IG.AbilityStates[key]
    if not ability then
        ability = {
            key = key,
            canonicalSpellID = canonicalSpellID,
            records = setmetatable({}, { __mode = "k" }),
            sourceKind = nil,
            sourceID = nil,
            ready = false,
            restricted = false,
            readinessRestricted = false,
            timingRestricted = false,
            needsPoll = false,
            deadline = nil,
            dormant = false,
            hasEvaluation = false,
            evaluatedGeneration = nil,
            sourceChanged = false,
        }
        IG.AbilityStates[key] = ability
        IG:BumpStat("abilities.created")
    end

    if record.ability ~= ability then
        self:DetachRecordFromAbility(record)
        record.ability = ability
        record.abilityKey = key
        ability.records[record] = true
    end

    ability.dormant = false
    self:RebuildAbilitySource(ability)
    record.ready = ability.ready == true
    record.restrictedCooldown = ability.restricted == true
    record.hardRestrictedCooldown = ability.hardRestricted == true
    record.readinessPending = ability.readinessPending == true
    record.deadline = ability.deadline
    return ability
end

function Buttons:UnbindRecord(record)
    if not record then return end

    local changed = record.isInterrupt
        or record.sourceKind ~= nil
        or record.sourceID ~= nil
        or record.spellID ~= nil

    IG.InterruptRecords[record] = nil
    self:DetachRecordFromAbility(record)

    record.isInterrupt = false
    record.sourceKind = nil
    record.sourceID = nil
    record.spellID = nil
    record.canonicalSpellID = nil
    record.ready = false
    record.restrictedCooldown = false
    record.hardRestrictedCooldown = false
    record.readinessPending = false
    record.deadline = nil

    if changed then
        IG:BumpStat("buttons.unbound")
        if IG.Glow then IG.Glow:ClearRecord(record) end
    end
end

function Buttons:PruneDormantAbilities()
    local removed = 0
    for key, ability in pairs(IG.AbilityStates) do
        if not ability or not ability.records or next(ability.records) == nil then
            IG.AbilityStates[key] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then IG:BumpStat("abilities.pruned", removed) end
    return removed
end

function Buttons:ResolveButtonForge(record)
    if record.buttonForgeDeallocated == true then return false end
    local button = record.button
    local buttonObject = record.buttonForgeObject
    if not buttonObject then
        buttonObject = IG:ReadMember(button, "ParentButton")
    end

    if IG.CanAccessTable(buttonObject) then
        record.buttonForgeObject = buttonObject
        -- ButtonForge button objects are ordinary addon-owned Lua tables. Avoid
        -- three protected member reads in its potentially per-frame refresh path.
        local mode = rawget(buttonObject, "Mode")
        local macroMode = rawget(buttonObject, "MacroMode")
        local rawSpellID = rawget(buttonObject, "SpellId")
        if not IG.CanAccess(mode) or not IG.CanAccess(macroMode) or not IG.CanAccess(rawSpellID) then
            return false
        end
        local spellID = type(rawSpellID) == "number" and rawSpellID or nil
        if mode ~= nil or spellID ~= nil then record.buttonForgeDeallocated = false end

        local resolvesSpell = mode == "spell" or (mode == "macro" and macroMode == "spell")
        if resolvesSpell and spellID then
            local canonicalSpellID = IG.Data:GetCanonicalSpellID(spellID, "spell")
            if canonicalSpellID then
                return true, "spell", canonicalSpellID, spellID, canonicalSpellID
            end
        end
        if mode ~= nil then return false end
    end

    local api = _G.ButtonForge_API1
    local name = GetFrameName(button)
    local getButtonActionInfo, methodKnown
    if IG.CanAccessTable(api) then
        getButtonActionInfo, methodKnown = IG:ReadMember(api, "GetButtonActionInfo")
    end
    if methodKnown and name and type(getButtonActionInfo) == "function" then
        local ok, actionType, id = pcall(getButtonActionInfo, name)
        if ok and IG.CanAccess(actionType) and IG.CanAccess(id) then
            if actionType == "spell" and type(id) == "number" then
                local canonicalSpellID = IG.Data:GetCanonicalSpellID(id, "spell")
                if canonicalSpellID then
                    return true, "spell", canonicalSpellID, id, canonicalSpellID
                end
            end
        end
    end

    return false
end

function Buttons:ResolvePet(record)
    local slot = record.petSlot
    if type(slot) ~= "number" or type(GetPetActionInfo) ~= "function" then
        return false
    end

    local ok, _, _, _, _, _, _, spellID = pcall(GetPetActionInfo, slot)
    if not ok or not IG.CanAccess(spellID) or type(spellID) ~= "number" then
        return false
    end

    local canonicalSpellID = IG.Data:GetCanonicalSpellID(spellID, "pet")
    if canonicalSpellID then
        return true, "pet", slot, spellID, canonicalSpellID
    end
    return false
end

function Buttons:ResolveCDM(record)
    if not IG.DB.cdm then return false end

    -- CDM callbacks snapshot ordinary identity before reset/reuse. Never query
    -- the pooled frame later during reconciliation.
    local spellID = record.cdmCanonicalSpellID
    if type(spellID) ~= "number" then return false end

    local canonicalSpellID = IG.Data:GetCanonicalSpellID(spellID, "spell")
    if canonicalSpellID then
        return true, "spell", canonicalSpellID, spellID, canonicalSpellID
    end
    return false
end

function Buttons:ResolveRecord(record)
    return IG.ActionResolver:ResolveRecord(record)
end

function Buttons:ReconcileRecord(record)
    if not record then return end

    local isInterrupt, sourceKind, sourceID, spellID, canonicalSpellID = self:ResolveRecord(record)
    isInterrupt = isInterrupt == true

    local changed = record.isInterrupt ~= isInterrupt
        or record.sourceKind ~= sourceKind
        or record.sourceID ~= sourceID
        or record.spellID ~= spellID
        or record.canonicalSpellID ~= canonicalSpellID

    if not isInterrupt then
        self:UnbindRecord(record)
        if IG.ConditionalActions then IG.ConditionalActions:Reconciled(record) end
        return
    end

    record.isInterrupt = true
    record.sourceKind = sourceKind
    record.sourceID = sourceID
    record.spellID = spellID
    record.canonicalSpellID = canonicalSpellID
    IG.InterruptRecords[record] = true

    local ability = self:AttachRecordToAbility(record, canonicalSpellID, sourceKind, sourceID)

    if IG.Glow then
        IG.Glow:QueueShell(record, true)
        IG.Glow:EnsureInterruptVisuals(record)
    end

    if changed then
        record.ready = ability.ready == true
        record.restrictedCooldown = ability.restricted == true
        record.deadline = ability.deadline
        IG:BumpStat("buttons.bound")

        local cooldown = IG.Cooldown
        local deadlineExpired = type(ability.deadline) == "number" and ability.deadline <= IG:Now()
        local cooldownStateCurrent = cooldown
            and ability.hasEvaluation == true
            and ability.evaluatedGeneration == cooldown.generation
            and ability.sourceChanged ~= true
            and ability.needsPoll ~= true
            and not deadlineExpired
        if not cooldownStateCurrent then IG:MarkCooldownDirty() end

        local storedNIComplete = true
        if IG.Glow then
            storedNIComplete = IG.Glow:ApplyStoredInterruptibilityToRecord(record)
        end
        -- Ordinary accessible NI state is reusable and requires no UnitCastingInfo
        -- call on rapid mouseover macro transitions. Restricted NI is never stored,
        -- so a newly-bound button requests one fresh frame-batched snapshot.
        if not storedNIComplete then IG:MarkCastDirty() end

        if IG.DB.debug and IG.Debug then
            IG.Debug:Log("button", ("bound adapter=%s source=%s:%s spell=%s canonical=%s")
                :format(
                    tostring(record.adapter),
                    tostring(sourceKind),
                    tostring(sourceID),
                    tostring(spellID),
                    tostring(canonicalSpellID)
                ))
        end
    end
    if IG.ConditionalActions then IG.ConditionalActions:Reconciled(record) end
    if IG.Glow then IG.Glow:RefreshRecord(record) end
end

function Buttons:ReconcilePending()
    for button in pairs(IG.PendingButtons) do
        IG.PendingButtons[button] = nil
        local record = IG.ObservedButtons[button]
        if record then
            self:ReconcileRecord(record)
            IG:BumpStat("buttons.reconciled")
        end
    end
end

function Buttons:ReconcileAll()
    local function HasActionSlot(record)
        if not record or record.adapter == "pet" or record.adapter == "cdm"
            or record.adapter == "buttonforge" then return false end
        if record.adapter == "lab" then
            return record.labIdentityRestricted ~= true
                and record.labStateType == "action"
                and type(record.labSlot) == "number"
                and record.labSlot > 0
        end
        if type(record.dominosSlot) == "number" and record.dominosSlot > 0 then return true end
        local slot = IG.ActionResolver:GetActionSlot(record.button)
        return type(slot) == "number" and slot > 0
    end

    -- Runtime-proven interrupts must be learned from action surfaces before
    -- direct-spell and Cooldown Viewer copies are reconciled.
    for _, record in pairs(IG.ObservedButtons) do
        if HasActionSlot(record) then
            self:ReconcileRecord(record)
            IG:BumpStat("buttons.reconciled")
        end
    end

    local cdm = IG.CDM
    if cdm and cdm.attached == true and IG.DB and IG.DB.cdm == true
        and type(cdm.ObserveExistingItems) == "function"
    then
        cdm:ObserveExistingItems()
        IG:BumpStat("cdm.postActionSeedRefreshes")
    end

    for _, record in pairs(IG.ObservedButtons) do
        if not HasActionSlot(record) then
            self:ReconcileRecord(record)
            IG:BumpStat("buttons.reconciled")
        end
    end
end

function Buttons:OnNativeActionChanged(button)
    if not self.attached or not self.nativeAttached or not IG.CanAccess(button) or button == nil then return end
    if not IG.ObservedButtons[button] then self:ObserveButton(button, "native", { skipDirty = true }) end
    if IG.PendingButtons[button] then return end
    IG:MarkButtonDirty(button)
    IG:BumpStat("events.actionButtonQueued")
end

local function ObserveNativeFrame(button)
    Buttons:ObserveButton(button, "native")
end

local function DispatchNativeActionChanged(owner, button)
    if not owner.attached or not owner.nativeAttached then return end
    owner:OnNativeActionChanged(button)
end

function Buttons:AttachNative()
    if self.nativeAttached then return end

    if EventRegistry and EventUtil
        and type(EventUtil.CreateCallbackHandleContainer) == "function"
        and type(EventRegistry.RegisterCallbackWithHandle) == "function"
    then
        self.nativeCallbackHandles = self.nativeCallbackHandles
            or EventUtil.CreateCallbackHandleContainer()
        if self.nativeCallbackHandles:IsEmpty() then
            self.nativeCallbackHandles:RegisterCallback(
                EventRegistry,
                "ActionButton.OnActionChanged",
                DispatchNativeActionChanged,
                self
            )
        end
        self.nativeUsesHandleContainer = true
        self.nativeAttached = true
        return
    end

    self.nativeAttached = true
    if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        EventRegistry:RegisterCallback("ActionButton.OnActionChanged", DispatchNativeActionChanged, self)
    end
end

function Buttons:DiscoverNative()
    local registryFrame = _G.ActionBarButtonEventsFrame
    if not IG.CanAccess(registryFrame) or registryFrame == nil then return end
    local forEachFrame, known = IG:ReadMember(registryFrame, "ForEachFrame")
    if known and type(forEachFrame) == "function" then
        forEachFrame(registryFrame, ObserveNativeFrame)
    end
end

function Buttons:AttachLABLibrary(library, discoverExisting, forceDiscovery)
    if IG.LABAdapter then IG.LABAdapter:AttachLibrary(library, discoverExisting, forceDiscovery) end
end

function Buttons:AttachLAB(discoverExisting, forceDiscovery)
    local LibStub = _G.LibStub
    if not IG.CanAccess(LibStub) or LibStub == nil then return end

    local found = false
    local iterateLibraries, iterateKnown
    if type(LibStub) == "table" then
        iterateLibraries, iterateKnown = IG:ReadMember(LibStub, "IterateLibraries")
    end
    if iterateKnown and type(iterateLibraries) == "function" then
        local ok, iterator, state, initial = pcall(iterateLibraries, LibStub)
        if ok and IG.CanAccess(iterator) and IG.CanAccess(state) and IG.CanAccess(initial)
            and type(iterator) == "function"
        then
            for name, library in iterator, state, initial do
                if IG.CanAccess(name) and IG.CanAccess(library)
                    and type(name) == "string" and name:match("^LibActionButton%-1%.0")
                then
                    self:AttachLABLibrary(library, discoverExisting, forceDiscovery)
                    found = true
                end
            end
        end
    end

    if not found then
        self:AttachLABLibrary(GetLibrary("LibActionButton-1.0"), discoverExisting, forceDiscovery)
    end
end

local function RemoveDominosIndex(button, slot)
    if not IG.CanAccess(button) or button == nil then return end
    if not IG.CanAccess(slot) then slot = nil end
    local bucket = type(slot) == "number" and Buttons.dominosButtonsBySlot[slot] or nil
    if bucket then
        bucket[button] = nil
        if next(bucket) == nil then Buttons.dominosButtonsBySlot[slot] = nil end
    end
end

local function IndexDominosButton(button, slot)
    if not IG.CanAccess(button) or button == nil then return end
    if not IG.CanAccess(slot) then slot = nil end
    local record = IG.ObservedButtons[button]
    if record and record.dominosSlot ~= slot then
        RemoveDominosIndex(button, record.dominosSlot)
        record.dominosSlot = slot
    end

    if type(slot) == "number" then
        local bucket = Buttons.dominosButtonsBySlot[slot]
        if not bucket then
            bucket = setmetatable({}, { __mode = "k" })
            Buttons.dominosButtonsBySlot[slot] = bucket
        end
        bucket[button] = true
    end
    if record and IG.ConditionalActions then IG.ConditionalActions:Observe(button, record) end
end

local function ObserveDominosRegistry(controller)
    if not IG.CanAccessTable(controller) then return end
    local registry, registryKnown = IG:ReadMember(controller, "buttons")
    if not registryKnown or not IG.CanAccessTable(registry) then return end

    for button, action in pairs(registry) do
        if IG.CanAccess(button) and IG.CanAccess(action) then
            Buttons:ObserveButton(button, "dominos")
            IndexDominosButton(button, IG:AsNumber(action))
        end
    end
end

local function OnDominosActionChanged(controller, buttonName, action)
    if not Buttons.dominosAttached then return end
    if not IG.CanAccess(buttonName) then return end
    local button = type(buttonName) == "string" and _G[buttonName] or nil
    if IG.CanAccess(button) and button ~= nil then
        Buttons:ObserveButton(button, "dominos")
        IndexDominosButton(button, IG:AsNumber(action))
    end
end

local function OnDominosSlotChanged(controller, slot)
    if not Buttons.dominosAttached or not IG.CanAccess(slot) then return end

    if type(slot) ~= "number" or slot == 0 then
        local registry = IG.CanAccessTable(controller)
            and IG:ReadMember(controller, "buttons") or nil
        if IG.CanAccessTable(registry) then
            for button in pairs(registry) do
                if IG.CanAccess(button) and button ~= nil then
                    IG:MarkButtonDirty(button)
                end
            end
        end
        IG:BumpStat("events.dominosGlobalSlotChanged")
        return
    end

    local bucket = Buttons.dominosButtonsBySlot[slot]
    if bucket then
        for button in pairs(bucket) do IG:MarkButtonDirty(button) end
    end
    IG:BumpStat("events.dominosSlotChanged")
end

function Buttons:AttachDominosNow(discoverExisting)
    local AceAddon = GetLibrary("AceAddon-3.0")
    if not IG.CanAccessTable(AceAddon) then return end
    local getAddon, methodKnown = IG:ReadMember(AceAddon, "GetAddon")
    if not methodKnown or type(getAddon) ~= "function" then return end

    local ok, addon = pcall(getAddon, AceAddon, "Dominos", true)
    if not ok or not IG.CanAccessTable(addon) then return end

    local controller, controllerKnown = IG:ReadMember(addon, "ActionButtons")
    if not controllerKnown or not IG.CanAccessTable(controller) then return end

    self.dominosAttached = true
    self.Dominos = addon
    self.DominosActionButtons = controller

    if not self.dominosHooked and type(hooksecurefunc) == "function" then
        self.dominosHooked = true
        local onActionChanged, actionChangedKnown = IG:ReadMember(controller, "OnActionChanged")
        if actionChangedKnown and type(onActionChanged) == "function" then
            hooksecurefunc(controller, "OnActionChanged", OnDominosActionChanged)
        end
        local slotChanged, slotChangedKnown = IG:ReadMember(controller, "ACTIONBAR_SLOT_CHANGED")
        if slotChangedKnown and type(slotChanged) == "function" then
            hooksecurefunc(controller, "ACTIONBAR_SLOT_CHANGED", OnDominosSlotChanged)
        end
    end

    if discoverExisting and (not self.dominosDiscovered or discoverExisting == "force") then
        self.dominosDiscovered = true
        ObserveDominosRegistry(controller)
    end
end

function Buttons:AttachDominos(discoverExisting)
    if IG:IsAddOnFullyLoaded("Dominos") then
        self.dominosWaiterPending = false
        self:AttachDominosNow(discoverExisting)
    elseif not self.dominosWaiterPending
        and EventUtil and type(EventUtil.ContinueOnAddOnLoaded) == "function"
    then
        self.dominosWaiterPending = true
        EventUtil.ContinueOnAddOnLoaded("Dominos", function()
            if not Buttons.dominosWaiterPending then return end
            Buttons.dominosWaiterPending = false
            if Buttons.attached then Buttons:AttachDominosNow(IG.playerLoginSeen) end
        end)
    end
end

function Buttons:ObserveButtonForgeName(buttonName)
    if not IG.CanAccess(buttonName) or type(buttonName) ~= "string" then return end
    local button = _G[buttonName]
    if not IG.CanAccess(button) or button == nil then return end
    local buttonObject = IG:ReadMember(button, "ParentButton")
    local record = self:ObserveButton(button, "buttonforge", { buttonForgeObject = buttonObject })
    if record then
        record.buttonForgeName = buttonName
        record.buttonForgeDeallocated = false
        buttonsByName[buttonName] = button
    end
end

function Buttons:OnButtonForgeEvent(event, buttonName)
    if not self.attached or not self.buttonForgeAttached
        or not IG.CanAccess(event) or not IG.CanAccess(buttonName)
    then
        return
    end
    if event == "INITIALISED" then
        if IG.playerLoginSeen then self:DiscoverButtonForgeButtons() end
    elseif event == "BUTTON_ALLOCATED" then
        if IG.playerLoginSeen then self:ObserveButtonForgeName(buttonName) end
    elseif event == "BUTTON_DEALLOCATED" then
        if type(buttonName) ~= "string" then return end
        local button = _G[buttonName] or buttonsByName[buttonName]
        if not IG.CanAccess(button) then return end
        local record = button and IG.ObservedButtons[button]
        buttonsByName[buttonName] = nil
        if not record or record.buttonForgeDeallocated == true then return end
        record.buttonForgeDeallocated = true
        record.buttonForgeObject = nil
        record.buttonForgeMode = nil
        record.buttonForgeMacroMode = nil
        record.buttonForgeSpellID = nil
        IG:MarkButtonDirty(button)
        IG:BumpStat("events.buttonForgeDeallocated")
    end
end

local function ButtonForgeCallback(owner, event, buttonName)
    if not IG.CanAccess(event) or not IG.CanAccess(buttonName) then return end
    if not owner.attached or not owner.buttonForgeAttached then return end
    owner:OnButtonForgeEvent(event, buttonName)
end

local function OnButtonForgeRefresh(buttonObject)
    if not Buttons.attached or not Buttons.buttonForgeAttached
        or not IG.CanAccessTable(buttonObject)
    then
        return
    end

    local button = rawget(buttonObject, "Widget")
    if not IG.CanAccess(button) or button == nil then return end

    local record = IG.ObservedButtons[button]
    if not record then
        record = Buttons:ObserveButton(button, "buttonforge", {
            buttonForgeObject = buttonObject,
            skipDirty = true,
        })
    else
        record.buttonForgeObject = buttonObject
    end
    if not record then return end

    -- FullRefresh can be called every frame for a conditional macro. Restrict
    -- the post-hook to three raw table reads and enqueue work only when the
    -- resolved command identity actually changed.
    local mode = rawget(buttonObject, "Mode")
    local macroMode = rawget(buttonObject, "MacroMode")
    local rawSpellID = rawget(buttonObject, "SpellId")
    if not IG.CanAccess(mode) or not IG.CanAccess(macroMode) or not IG.CanAccess(rawSpellID) then
        if not record.buttonForgeIdentityRestricted then
            record.buttonForgeIdentityRestricted = true
            record.buttonForgeMode = nil
            record.buttonForgeMacroMode = nil
            record.buttonForgeSpellID = nil
            IG:MarkButtonDirty(button)
        end
        return
    end
    local spellID = type(rawSpellID) == "number" and rawSpellID or nil
    if mode ~= nil or spellID ~= nil then record.buttonForgeDeallocated = false end

    if record.buttonForgeIdentityRestricted
        or record.buttonForgeMode ~= mode
        or record.buttonForgeMacroMode ~= macroMode
        or record.buttonForgeSpellID ~= spellID
    then
        record.buttonForgeIdentityRestricted = false
        record.buttonForgeMode = mode
        record.buttonForgeMacroMode = macroMode
        record.buttonForgeSpellID = spellID
        IG:MarkButtonDirty(button)
        IG:BumpStat("events.buttonForgeResolvedChanged")
    end
end

local function OnButtonForgeClear(buttonObject)
    -- ClearCommand does not call FullRefresh. Reuse the same deduplicating
    -- observer after ButtonForge has cleared Mode/SpellId.
    OnButtonForgeRefresh(buttonObject)
end

function Buttons:DiscoverButtonForgeButtons()
    local api = _G.ButtonForge_API1
    if not IG.CanAccessTable(api) then return end
    local getNames, methodKnown = IG:ReadMember(api, "GetButtonFrameNames")
    if not methodKnown or type(getNames) ~= "function" then return end

    local ok, names = pcall(getNames)
    if not ok or not IG.CanAccessTable(names) then return end
    for index = 1, #names do
        local buttonName, known = IG:ReadMember(names, index)
        if known then self:ObserveButtonForgeName(buttonName) end
    end
end

function Buttons:AttachButtonForgeNow(discoverExisting)
    local api = _G.ButtonForge_API1
    if not IG.CanAccessTable(api) then return end

    if not self.buttonForgeAttached then
        self.buttonForgeAttached = true
        local registerCallback, known = IG:ReadMember(api, "RegisterCallback")
        if known and type(registerCallback) == "function" then
            registerCallback(ButtonForgeCallback, self)
        end
    end

    local BFButton = _G.BFButton
    if IG.CanAccessTable(BFButton) and type(hooksecurefunc) == "function" then
        local fullRefresh, refreshKnown = IG:ReadMember(BFButton, "FullRefresh")
        if not self.buttonForgeHooked and refreshKnown and type(fullRefresh) == "function" then
            self.buttonForgeHooked = true
            hooksecurefunc(BFButton, "FullRefresh", OnButtonForgeRefresh)
        end
        local clearCommand, clearKnown = IG:ReadMember(BFButton, "ClearCommand")
        if not self.buttonForgeClearHooked and clearKnown and type(clearCommand) == "function" then
            self.buttonForgeClearHooked = true
            hooksecurefunc(BFButton, "ClearCommand", OnButtonForgeClear)
        end
    end

    if discoverExisting and (not self.buttonForgeDiscovered or discoverExisting == "force") then
        self.buttonForgeDiscovered = true
        self:DiscoverButtonForgeButtons()
    end
end

function Buttons:AttachButtonForge(discoverExisting)
    if IG:IsAddOnFullyLoaded("ButtonForge") then
        self.buttonForgeWaiterPending = false
        self:AttachButtonForgeNow(discoverExisting)
    elseif not self.buttonForgeWaiterPending
        and EventUtil and type(EventUtil.ContinueOnAddOnLoaded) == "function"
    then
        self.buttonForgeWaiterPending = true
        EventUtil.ContinueOnAddOnLoaded("ButtonForge", function()
            if not Buttons.buttonForgeWaiterPending then return end
            Buttons.buttonForgeWaiterPending = false
            if Buttons.attached then Buttons:AttachButtonForgeNow(IG.playerLoginSeen) end
        end)
    end
end

function Buttons:WaitForKnownLABProvider(addOnName)
    if self.knownLABWaiters[addOnName] or IG:IsAddOnFullyLoaded(addOnName) then
        return
    end
    if not EventUtil or type(EventUtil.ContinueOnAddOnLoaded) ~= "function" then
        return
    end

    self.knownLABWaiters[addOnName] = true
    EventUtil.ContinueOnAddOnLoaded(addOnName, function()
        Buttons.knownLABWaiters[addOnName] = nil
        if Buttons.attached then Buttons:AttachLAB(true, false) end
    end)
end

function Buttons:RefreshPetButtons()
    local petBar = _G.PetActionBar
    local actionButtons
    if IG.CanAccess(petBar) and petBar ~= nil then
        local known
        actionButtons, known = IG:ReadMember(petBar, "actionButtons")
        if not known or not IG.CanAccessTable(actionButtons) then
            actionButtons = nil
        end
    end

    for slot = 1, 10 do
        local button
        if actionButtons then
            local known
            button, known = IG:ReadMember(actionButtons, slot)
            if not known then button = nil end
        end
        if not IG.CanAccess(button) or button == nil then
            button = _G["PetActionButton" .. slot]
        end
        if IG.CanAccess(button) and button ~= nil then
            self:ObserveButton(button, "pet", { petSlot = slot })
        end
    end
end

function Buttons:Attach(discoverExisting)
    if self.attached then return end
    self.attached = true
    if IG.LABAdapter then IG.LABAdapter:Attach() end

    self:AttachNative()
    self:AttachLAB(discoverExisting == true, false)
    self:AttachDominos(discoverExisting == true)
    self:AttachButtonForge(discoverExisting == true)
    self:WaitForKnownLABProvider("Bartender4")

    if discoverExisting then
        IG:BumpStat("startup.discoveryPasses")
        self:DiscoverNative()
        self:RefreshPetButtons()
        IG:MarkAllButtonsDirty()
    end
end

function Buttons:DiscoverAll(force)
    IG:BumpStat(force and "manual.discoveryPasses" or "startup.discoveryPasses")
    self:DiscoverNative()
    self:AttachLAB(true, force == true)
    self:AttachDominosNow(force and "force" or true)
    self:AttachButtonForgeNow(force and "force" or true)
    self:RefreshPetButtons()
    IG:MarkAllButtonsDirty()
end

function Buttons:Detach()
    if IG.ConditionalActions then IG.ConditionalActions:Detach() end
    if self.nativeUsesHandleContainer and self.nativeCallbackHandles then
        self.nativeCallbackHandles:Unregister()
        self.nativeUsesHandleContainer = false
        self.nativeAttached = false
    end
    if self.nativeAttached and EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("ActionButton.OnActionChanged", self)
    end
    self.nativeAttached = false

    if IG.LABAdapter then IG.LABAdapter:Detach() end

    local api = _G.ButtonForge_API1
    local unregisterButtonForge, unregisterKnown
    if IG.CanAccessTable(api) then
        unregisterButtonForge, unregisterKnown = IG:ReadMember(api, "UnregisterCallback")
    end
    if self.buttonForgeAttached and unregisterKnown and type(unregisterButtonForge) == "function" then
        unregisterButtonForge(ButtonForgeCallback, self)
    end

    self.buttonForgeAttached = false
    self.dominosAttached = false
    self.dominosDiscovered = false
    self.buttonForgeDiscovered = false
    IG:WipeMap(self.labDiscoveredLibraries)
    for name in pairs(buttonsByName) do buttonsByName[name] = nil end
    self.attached = false
end
