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
    labLibraries = setmetatable({}, { __mode = "k" }),
    labDiscoveredLibraries = setmetatable({}, { __mode = "k" }),
    knownLABWaiters = {},
    dominosButtonsBySlot = {},
    dominosDiscovered = false,
    buttonForgeDiscovered = false,
}
IG.Buttons = Buttons
IG:RegisterModule("Buttons", Buttons)

local _G = _G
local C_ActionBar = _G.C_ActionBar
local GetActionInfo = _G.GetActionInfo
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
    action = 30,
    pet = 20,
    spell = 10,
}

local function GetLibrary(name)
    local LibStub = _G.LibStub
    if not LibStub then return nil end

    local getLibrary = LibStub.GetLibrary
    if type(getLibrary) == "function" then
        local ok, library = pcall(getLibrary, LibStub, name, true)
        if ok then return library end
        return nil
    end

    if type(LibStub) == "function" then
        local ok, library = pcall(LibStub, name, true)
        if ok then return library end
    end
    return nil
end

local function IsFrameObject(value)
    local valueType = type(value)
    return valueType == "table" or valueType == "userdata"
end

local function GetFrameName(frame)
    if not frame or type(frame.GetName) ~= "function" then return nil end
    local ok, name = pcall(frame.GetName, frame)
    if not ok or not IG.CanAccess(name) or type(name) ~= "string" then
        return nil
    end
    return name
end

local function SafeGetActionInfo(slot)
    if type(GetActionInfo) ~= "function" or type(slot) ~= "number" then
        return nil, nil, nil
    end

    local ok, actionType, id, subType = pcall(GetActionInfo, slot)
    if not ok then return nil, nil, nil end
    if not IG.CanAccess(actionType) or not IG.CanAccess(id) or not IG.CanAccess(subType) then
        return nil, nil, nil
    end
    return actionType, id, subType
end

local function IsInterruptAction(slot)
    if not C_ActionBar or type(C_ActionBar.IsInterruptAction) ~= "function" then
        return nil
    end

    local ok, result = pcall(C_ActionBar.IsInterruptAction, slot)
    if not ok or not IG.CanAccess(result) then return nil end
    if result == true then return true end
    if result == false then return false end
    return nil
end

local function IsAssistedCombatAction(slot)
    if C_ActionBar and type(C_ActionBar.IsAssistedCombatAction) == "function" then
        local ok, result = pcall(C_ActionBar.IsAssistedCombatAction, slot)
        if ok and IG.CanAccess(result) then
            return result == true
        end
    end

    local _actionType, _id, subType = SafeGetActionInfo(slot)
    return subType == "assistedcombat"
end

local function ResolveActionSpellID(slot)
    if C_ActionBar and type(C_ActionBar.GetSpell) == "function" then
        local ok, spellID = pcall(C_ActionBar.GetSpell, slot)
        if ok and IG.CanAccess(spellID) and type(spellID) == "number" then
            return spellID
        end
    end

    local actionType, id, subType = SafeGetActionInfo(slot)
    if actionType == "spell" and type(id) == "number" then
        return id
    end
    if actionType == "macro" and subType == "spell" and type(id) == "number" then
        return id
    end
    return nil
end

local function ResolveActionSlot(button)
    local stateType, hasStateType = IG:ReadMember(button, "_state_type")
    if hasStateType and stateType == "action" then
        local stateAction = IG:ReadMember(button, "_state_action")
        local slot = IG:AsNumber(stateAction)
        if slot then return slot end
    end

    local action = IG:ReadMember(button, "action")
    return IG:AsNumber(action)
end

local function ResolveDirectSpellID(button)
    if not button then return nil end

    local getSpellID = button.GetSpellId or button.GetSpellID
    if type(getSpellID) == "function" then
        local ok, spellID = pcall(getSpellID, button)
        if ok and IG.CanAccess(spellID) and type(spellID) == "number" then
            return spellID
        end
    end

    local stateType, hasStateType = IG:ReadMember(button, "_state_type")
    if hasStateType and stateType == "spell" then
        local stateAction = IG:ReadMember(button, "_state_action")
        local spellID = IG:AsNumber(stateAction)
        if spellID then return spellID end
    end

    return nil
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

    if created or not (extra and extra.skipDirty) then
        IG:MarkButtonDirty(button)
    end
    return record
end

function Buttons:RebuildAbilitySource(ability)
    if not ability then return false end

    -- Keep the current source while at least one record still exposes it. For a
    -- shared cooldown, switching from slot 1 to slot 2 and back on every
    -- mouseover transition would cause pointless API invalidation.
    if ability.sourceKind ~= nil then
        for record in pairs(ability.records) do
            if record.sourceKind == ability.sourceKind and record.sourceID == ability.sourceID then
                return false
            end
        end
    end

    local bestKind, bestID, bestPriority
    for record in pairs(ability.records) do
        local priority = SOURCE_PRIORITY[record.sourceKind] or 0
        local sourceID = record.sourceID
        if priority > (bestPriority or -1)
            or (priority == bestPriority and type(sourceID) == "number" and type(bestID) == "number" and sourceID < bestID)
        then
            bestPriority = priority
            bestKind = record.sourceKind
            bestID = sourceID
        end
    end

    if bestKind == nil then
        -- A dormant canonical ability retains its last source and evaluated
        -- state. Cooldown generations make it stale if an event occurs while no
        -- button exposes it, allowing rapid macro unbind/rebind with zero API
        -- calls and zero table churn.
        ability.dormant = true
        return false
    end

    ability.dormant = false
    if ability.sourceKind ~= bestKind or ability.sourceID ~= bestID then
        ability.sourceKind = bestKind
        ability.sourceID = bestID
        ability.sourceChanged = true
        IG:MarkCooldownDirty(false)
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
    record.deadline = nil

    if changed then
        IG:BumpStat("buttons.unbound")
        if IG.Glow then IG.Glow:ClearRecord(record) end
    end
end

function Buttons:ResolveButtonForge(record)
    local button = record.button
    local buttonObject = record.buttonForgeObject
    if not buttonObject then
        buttonObject = IG:ReadMember(button, "ParentButton")
    end

    if buttonObject then
        record.buttonForgeObject = buttonObject
        -- ButtonForge button objects are ordinary addon-owned Lua tables. Avoid
        -- three protected member reads in its potentially per-frame refresh path.
        local mode = rawget(buttonObject, "Mode")
        local macroMode = rawget(buttonObject, "MacroMode")
        local rawSpellID = rawget(buttonObject, "SpellId")
        local spellID = type(rawSpellID) == "number" and rawSpellID or nil

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
    if api and name and type(api.GetButtonActionInfo) == "function" then
        local ok, actionType, id = pcall(api.GetButtonActionInfo, name)
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

    local button = record.button
    local getBaseSpellID = button and button.GetBaseSpellID
    if type(getBaseSpellID) ~= "function" then return false end

    local ok, spellID = pcall(getBaseSpellID, button)
    if not ok or not IG.CanAccess(spellID) or type(spellID) ~= "number" then
        return false
    end

    local canonicalSpellID = IG.Data:GetCanonicalSpellID(spellID, "spell")
    if canonicalSpellID then
        return true, "spell", canonicalSpellID, spellID, canonicalSpellID
    end
    return false
end

function Buttons:ResolveRecord(record)
    if not record then return false end

    if record.adapter == "pet" then
        return self:ResolvePet(record)
    end
    if record.adapter == "cdm" then
        return self:ResolveCDM(record)
    end
    if record.adapter == "buttonforge" then
        return self:ResolveButtonForge(record)
    end

    local button = record.button
    local slot = ResolveActionSlot(button)
    if slot then
        if IsAssistedCombatAction(slot) then
            return false
        end

        local interrupt = IsInterruptAction(slot)
        if interrupt == true then
            local spellID = ResolveActionSpellID(slot)
            local canonicalSpellID = spellID and IG.Data:GetCanonicalSpellID(spellID, "action") or nil
            if spellID and not canonicalSpellID then
                canonicalSpellID = IG.Data:LearnRuntimeInterrupt(spellID)
            end
            canonicalSpellID = canonicalSpellID or spellID
            return true, "action", slot, spellID, canonicalSpellID
        end
        if interrupt == false then
            return false
        end
    end

    local spellID = ResolveDirectSpellID(button)
    if spellID then
        local canonicalSpellID = IG.Data:GetCanonicalSpellID(spellID, "spell")
        if canonicalSpellID then
            return true, "spell", canonicalSpellID, spellID, canonicalSpellID
        end
    end

    return false
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
        if not cooldownStateCurrent then IG:MarkCooldownDirty(false) end

        local storedNIComplete = true
        if IG.Glow then
            storedNIComplete = IG.Glow:ApplyStoredInterruptibilityToRecord(record)
            IG.Glow:RefreshRecord(record)
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
    for _, record in pairs(IG.ObservedButtons) do
        self:ReconcileRecord(record)
        IG:BumpStat("buttons.reconciled")
    end
end

function Buttons:OnNativeActionChanged(button)
    self:ObserveButton(button, "native")
    IG:BumpStat("events.actionButtonChanged")
end

local function ObserveNativeFrame(button)
    Buttons:ObserveButton(button, "native")
end

function Buttons:AttachNative()
    if self.nativeAttached then return end
    self.nativeAttached = true

    if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        EventRegistry:RegisterCallback("ActionButton.OnActionChanged", self.OnNativeActionChanged, self)
    end
end

function Buttons:DiscoverNative()
    local registryFrame = _G.ActionBarButtonEventsFrame
    if registryFrame and type(registryFrame.ForEachFrame) == "function" then
        registryFrame:ForEachFrame(ObserveNativeFrame)
    end
end

function Buttons:OnLABButtonCreated(_, button)
    self:ObserveButton(button, "lab")
end

function Buttons:OnLABButtonUpdate(_, button)
    -- LAB may fire OnButtonUpdate during construction, before OnButtonCreated.
    local record = button and IG.ObservedButtons[button]
    if record then self:ObserveButton(button, "lab") end
end

function Buttons:OnLABButtonContentsChanged(_, button)
    self:ObserveButton(button, "lab")
end

local function DiscoverLABLibrary(library, force)
    if not library then return end
    if Buttons.labDiscoveredLibraries[library] and not force then return end
    Buttons.labDiscoveredLibraries[library] = true

    if type(library.GetAllButtons) == "function" then
        local ok, buttons = pcall(library.GetAllButtons, library)
        if ok and type(buttons) == "table" then
            for button in pairs(buttons) do
                Buttons:ObserveButton(button, "lab")
            end
            return
        end
    end

    local registry = library.buttonRegistry
    if type(registry) == "table" then
        for button in pairs(registry) do
            Buttons:ObserveButton(button, "lab")
        end
    end
end

function Buttons:AttachLABLibrary(library, discoverExisting, forceDiscovery)
    if type(library) ~= "table" then return end

    if not self.labLibraries[library] then
        self.labLibraries[library] = true
        if type(library.RegisterCallback) == "function" then
            library.RegisterCallback(self, "OnButtonCreated", "OnLABButtonCreated")
            library.RegisterCallback(self, "OnButtonUpdate", "OnLABButtonUpdate")
            library.RegisterCallback(self, "OnButtonContentsChanged", "OnLABButtonContentsChanged")
        end
    end

    if discoverExisting then DiscoverLABLibrary(library, forceDiscovery) end
end

function Buttons:AttachLAB(discoverExisting, forceDiscovery)
    local LibStub = _G.LibStub
    if not LibStub then return end

    local found = false
    if type(LibStub.IterateLibraries) == "function" then
        local ok, iterator, state, initial = pcall(LibStub.IterateLibraries, LibStub)
        if ok and type(iterator) == "function" then
            for name, library in iterator, state, initial do
                if type(name) == "string" and name:match("^LibActionButton%-1%.0") then
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
    local bucket = type(slot) == "number" and Buttons.dominosButtonsBySlot[slot] or nil
    if bucket then
        bucket[button] = nil
        if next(bucket) == nil then Buttons.dominosButtonsBySlot[slot] = nil end
    end
end

local function IndexDominosButton(button, slot)
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
end

local function ObserveDominosRegistry(controller)
    local registry = controller and controller.buttons
    if type(registry) ~= "table" then return end

    for button, action in pairs(registry) do
        Buttons:ObserveButton(button, "dominos")
        IndexDominosButton(button, IG:AsNumber(action))
    end
end

local function OnDominosActionChanged(controller, buttonName, action)
    if not Buttons.dominosAttached then return end
    local button = type(buttonName) == "string" and _G[buttonName] or nil
    if button then
        Buttons:ObserveButton(button, "dominos")
        IndexDominosButton(button, IG:AsNumber(action))
    end
end

local function OnDominosSlotChanged(controller, slot)
    if not Buttons.dominosAttached then return end

    if type(slot) ~= "number" or slot == 0 then
        local registry = controller and controller.buttons
        if type(registry) == "table" then
            for button in pairs(registry) do IG:MarkButtonDirty(button) end
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
    if not AceAddon or type(AceAddon.GetAddon) ~= "function" then return end

    local ok, addon = pcall(AceAddon.GetAddon, AceAddon, "Dominos", true)
    if not ok or type(addon) ~= "table" then return end

    local controller = addon.ActionButtons
    if type(controller) ~= "table" then return end

    self.dominosAttached = true
    self.Dominos = addon
    self.DominosActionButtons = controller

    if not self.dominosHooked and type(hooksecurefunc) == "function" then
        self.dominosHooked = true
        if type(controller.OnActionChanged) == "function" then
            hooksecurefunc(controller, "OnActionChanged", OnDominosActionChanged)
        end
        if type(controller.ACTIONBAR_SLOT_CHANGED) == "function" then
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
        self:AttachDominosNow(discoverExisting)
    elseif EventUtil and type(EventUtil.ContinueOnAddOnLoaded) == "function" then
        EventUtil.ContinueOnAddOnLoaded("Dominos", function()
            if Buttons.attached then Buttons:AttachDominosNow(IG.playerLoginSeen) end
        end)
    end
end

function Buttons:ObserveButtonForgeName(buttonName)
    if type(buttonName) ~= "string" then return end
    local button = _G[buttonName]
    if not button then return end
    local buttonObject = IG:ReadMember(button, "ParentButton")
    self:ObserveButton(button, "buttonforge", { buttonForgeObject = buttonObject })
end

function Buttons:OnButtonForgeEvent(event, buttonName)
    if event == "INITIALISED" then
        if IG.playerLoginSeen then self:DiscoverButtonForgeButtons() end
    elseif event == "BUTTON_ALLOCATED" then
        if IG.playerLoginSeen then self:ObserveButtonForgeName(buttonName) end
    elseif event == "BUTTON_DEALLOCATED" then
        local button = type(buttonName) == "string" and _G[buttonName] or nil
        local record = button and IG.ObservedButtons[button]
        if record then self:UnbindRecord(record) end
    end
end

local function ButtonForgeCallback(owner, event, buttonName)
    owner:OnButtonForgeEvent(event, buttonName)
end

local function OnButtonForgeRefresh(buttonObject)
    if not Buttons.buttonForgeAttached or type(buttonObject) ~= "table" then return end

    local button = rawget(buttonObject, "Widget")
    if not button then return end

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
    local spellID = type(rawSpellID) == "number" and rawSpellID or nil

    if record.buttonForgeMode ~= mode
        or record.buttonForgeMacroMode ~= macroMode
        or record.buttonForgeSpellID ~= spellID
    then
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
    if not api or type(api.GetButtonFrameNames) ~= "function" then return end

    local ok, names = pcall(api.GetButtonFrameNames)
    if not ok or type(names) ~= "table" then return end
    for index = 1, #names do self:ObserveButtonForgeName(names[index]) end
end

function Buttons:AttachButtonForgeNow(discoverExisting)
    local api = _G.ButtonForge_API1
    if not api then return end

    if not self.buttonForgeAttached then
        self.buttonForgeAttached = true
        if type(api.RegisterCallback) == "function" then
            api.RegisterCallback(ButtonForgeCallback, self)
        end
    end

    local BFButton = _G.BFButton
    if BFButton and type(hooksecurefunc) == "function" then
        if not self.buttonForgeHooked and type(BFButton.FullRefresh) == "function" then
            self.buttonForgeHooked = true
            hooksecurefunc(BFButton, "FullRefresh", OnButtonForgeRefresh)
        end
        if not self.buttonForgeClearHooked and type(BFButton.ClearCommand) == "function" then
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
        self:AttachButtonForgeNow(discoverExisting)
    elseif EventUtil and type(EventUtil.ContinueOnAddOnLoaded) == "function" then
        EventUtil.ContinueOnAddOnLoaded("ButtonForge", function()
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
    local actionButtons = petBar and petBar.actionButtons

    for slot = 1, 10 do
        local button = actionButtons and actionButtons[slot] or _G["PetActionButton" .. slot]
        if button then self:ObserveButton(button, "pet", { petSlot = slot }) end
    end
end

function Buttons:Attach(discoverExisting)
    if self.attached then return end
    self.attached = true

    self:AttachNative()
    self:AttachLAB(discoverExisting == true, false)
    self:AttachDominos(discoverExisting == true)
    self:AttachButtonForge(discoverExisting == true)
    self:WaitForKnownLABProvider("Bartender4")
    self:WaitForKnownLABProvider("ElvUI")

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
    if self.nativeAttached and EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("ActionButton.OnActionChanged", self)
    end
    self.nativeAttached = false

    for library in pairs(self.labLibraries) do
        if type(library.UnregisterCallback) == "function" then
            library.UnregisterCallback(self, "OnButtonCreated")
            library.UnregisterCallback(self, "OnButtonUpdate")
            library.UnregisterCallback(self, "OnButtonContentsChanged")
        end
        self.labLibraries[library] = nil
    end

    local api = _G.ButtonForge_API1
    if self.buttonForgeAttached and api and type(api.UnregisterCallback) == "function" then
        api.UnregisterCallback(ButtonForgeCallback, self)
    end

    self.buttonForgeAttached = false
    self.dominosAttached = false
    self.dominosDiscovered = false
    self.buttonForgeDiscovered = false
    IG:WipeMap(self.labDiscoveredLibraries)
    self.attached = false
end
