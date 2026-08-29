local IG = _G.InterruptGlow
if not IG or not IG.Buttons or not IG.Usability then return end

local Buttons = IG.Buttons
local Usability = IG.Usability
local Glow = IG.Glow
local _G = _G
local hooksecurefunc = _G.hooksecurefunc
local pairs = pairs
local next = next
local type = type
local tonumber = tonumber

-- Conditional macro resolution can change when mouseover/help/harm context
-- changes without changing the physical action slot. Keep bounded indexes over
-- observed buttons only; never scan action slots or parse macro bodies.
local slotByButton = setmetatable({}, { __mode = "k" })
local buttonsBySlot = {}
local pendingIdentityButtons = setmetatable({}, { __mode = "k" })
local deferredButtons = setmetatable({}, { __mode = "k" })
local hookedDominosControllers = setmetatable({}, { __mode = "k" })

local ACTION_ADAPTER = {
    native = true,
    lab = true,
    dominos = true,
    buttonforge = true,
}

local originalMarkButtonDirty = IG.MarkButtonDirty

local function ReadinessAwake()
    return type(IG.NeedsReadinessRuntime) == "function"
        and IG:NeedsReadinessRuntime() == true
end

local function RemoveButton(button)
    local oldSlot = slotByButton[button]
    if oldSlot == nil then return end

    slotByButton[button] = nil
    local set = buttonsBySlot[oldSlot]
    if set then
        set[button] = nil
        if next(set) == nil then buttonsBySlot[oldSlot] = nil end
    end
end

local function NormalizeSlot(value)
    if not IG.CanAccess(value) then return nil end
    if type(value) == "string" then value = tonumber(value) end
    if type(value) ~= "number" or value <= 0 then return nil end
    return value
end

local function ReadGenericActionSlot(button)
    local stateType, typeKnown = IG:ReadMember(button, "_state_type")
    local stateAction, actionStateKnown = IG:ReadMember(button, "_state_action")
    if typeKnown and actionStateKnown and stateType == "action" then
        local slot = NormalizeSlot(stateAction)
        if slot then return slot end
    end

    local action, actionKnown = IG:ReadMember(button, "action")
    if actionKnown then return NormalizeSlot(action) end
    return nil
end

local function ReadPhysicalSlot(button, record)
    if not button or not record then return nil end

    local adapter = record.adapter
    if adapter == "native" then
        if not IG.CanAccess(button) then return nil end
        local action = button.action
        if not IG.CanAccess(action) then return nil end
        return NormalizeSlot(action)
    end

    if adapter == "lab" then
        return NormalizeSlot(record.labSlot) or ReadGenericActionSlot(button)
    end

    if adapter == "dominos" then
        return NormalizeSlot(record.dominosSlot) or ReadGenericActionSlot(button)
    end

    if adapter == "pet" or adapter == "cdm" or adapter == "buttonforge" then
        return nil
    end

    return ReadGenericActionSlot(button)
end

local function RefreshButtonSlot(button, record)
    if not button then return nil end
    record = record or IG.ObservedButtons[button]

    local slot = ReadPhysicalSlot(button, record)
    local oldSlot = slotByButton[button]
    if oldSlot == slot then return slot end

    RemoveButton(button)
    if slot == nil then return nil end

    local set = buttonsBySlot[slot]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        buttonsBySlot[slot] = set
    end
    set[button] = true
    slotByButton[button] = slot
    return slot
end

local function VisitSlot(slot, visitor)
    if not Buttons.attached or not IG.CanAccess(slot) then return 0 end
    if type(slot) == "string" then slot = tonumber(slot) end
    if type(slot) ~= "number" then return 0 end

    local count = 0
    if slot > 0 then
        local set = buttonsBySlot[slot]
        if set then
            for button in pairs(set) do
                count = count + 1
                visitor(button)
            end
        end
    elseif slot == 0 then
        for button in pairs(slotByButton) do
            count = count + 1
            visitor(button)
        end
    end
    return count
end

local function ClearPendingIdentity(record)
    if not record then return end
    record.conditionalIdentityPending = false
    if record.button then
        pendingIdentityButtons[record.button] = nil
        deferredButtons[record.button] = nil
    end
end

local function MarkIdentityPending(button, deferQueue)
    local record = button and IG.ObservedButtons[button]
    if not record then return false end

    record.actionSnapshotFresh = false
    pendingIdentityButtons[button] = true
    if deferQueue then
        deferredButtons[button] = true
    else
        -- Active signals already own a normal dirty record. Do not let them leak
        -- into the sleeping queue and get scheduled a second time later.
        deferredButtons[button] = nil
    end

    local wasPending = record.conditionalIdentityPending == true
    record.conditionalIdentityPending = true

    if not wasPending
        and record.isInterrupt == true
        and record.overlay
        and Glow
        and type(Glow.ClearRecord) == "function"
    then
        Glow:ClearRecord(record)
    end
    return true
end

local function InvalidateSlot(slot)
    local count = VisitSlot(slot, function(button)
        IG:MarkButtonDirty(button)
    end)
    if count > 0 then IG:BumpStat("events.conditionalMacroSlots", count) end
    return count
end

local function DeferButton(button)
    MarkIdentityPending(button, true)
end

local function DeferSlot(slot)
    local count = VisitSlot(slot, DeferButton)
    if count > 0 then IG:BumpStat("events.conditionalMacroDeferred", count) end
    return count
end

local function VisitChanges(changes, visitor)
    if not IG.CanAccess(changes) or type(changes) ~= "table" then return 0 end

    local count = 0
    for _, change in pairs(changes) do
        local slot, slotKnown = IG:ReadMember(change, "slot")
        if slotKnown then
            slot = IG:AsNumber(slot)
            if type(slot) == "number" then count = count + visitor(slot) end
        end
    end
    return count
end

local function InvalidateChanges(changes)
    return VisitChanges(changes, InvalidateSlot)
end

local function DeferChanges(changes)
    return VisitChanges(changes, DeferSlot)
end

local function FlushDeferredButtons()
    if not Buttons.attached then
        for button in pairs(deferredButtons) do
            ClearPendingIdentity(IG.ObservedButtons[button])
        end
        return 0
    end

    local count = 0
    for button in pairs(deferredButtons) do
        local record = IG.ObservedButtons[button]
        if not record then
            deferredButtons[button] = nil
            pendingIdentityButtons[button] = nil
        elseif not IG.PendingButtons or not IG.PendingButtons[button] then
            count = count + 1
            originalMarkButtonDirty(IG, button)
        end
    end

    if count > 0 then IG:BumpStat("events.conditionalMacroDeferredFlush", count) end
    return count
end

local originalReconcileRecord = Buttons.ReconcileRecord
function Buttons:ReconcileRecord(record, ...)
    ClearPendingIdentity(record)
    return originalReconcileRecord(self, record, ...)
end

local function ClearPendingVisuals()
    if not Glow or type(Glow.ClearRecord) ~= "function" then return end
    for button in pairs(pendingIdentityButtons) do
        local record = IG.ObservedButtons[button]
        if record and record.conditionalIdentityPending == true then
            Glow:ClearRecord(record)
        end
    end
end

if Glow then
    local originalRefreshRecord = Glow.RefreshRecord
    if type(originalRefreshRecord) == "function" then
        function Glow:RefreshRecord(record, ...)
            if record and record.conditionalIdentityPending == true then
                if type(self.ClearRecord) == "function" then self:ClearRecord(record) end
                return
            end
            return originalRefreshRecord(self, record, ...)
        end
    end

    local originalRefreshUnit = Glow.RefreshUnit
    if type(originalRefreshUnit) == "function" then
        function Glow:RefreshUnit(unit, ...)
            local result = originalRefreshUnit(self, unit, ...)
            ClearPendingVisuals()
            return result
        end
    end

    local originalRefreshAll = Glow.RefreshAll
    if type(originalRefreshAll) == "function" then
        function Glow:RefreshAll(...)
            local result = originalRefreshAll(self, ...)
            ClearPendingVisuals()
            return result
        end
    end
end

local originalObserveButton = Buttons.ObserveButton
function Buttons:ObserveButton(button, adapter, options)
    local record = originalObserveButton(self, button, adapter, options)
    if record then
        RefreshButtonSlot(button, record)
        if Glow and type(Glow.AllowOverlayAccessRetry) == "function"
            and Glow:AllowOverlayAccessRetry(record)
            and not record.overlay
        then
            Glow:QueueShell(record, false)
        end
    end
    return record
end

function IG:MarkButtonDirty(button)
    local physicalButton = button
    local record = physicalButton and IG.ObservedButtons[physicalButton]

    if record and (record.adapter == "lab" or record.adapter == "dominos") then
        RefreshButtonSlot(physicalButton, record)
    end

    if record and ACTION_ADAPTER[record.adapter] then
        local awake = ReadinessAwake()
        MarkIdentityPending(physicalButton, not awake)
        if not awake then return end
    end
    return originalMarkButtonDirty(self, physicalButton)
end

local originalOnNativeActionChanged = Buttons.OnNativeActionChanged
function Buttons:OnNativeActionChanged(button, ...)
    local record = button and IG.ObservedButtons[button]
    if not record then
        record = self:ObserveButton(button, "native", { skipDirty = true })
        if not record then return end
    end

    RefreshButtonSlot(button, record)
    local awake = ReadinessAwake()
    MarkIdentityPending(button, not awake)
    if not awake then
        IG:BumpStat("events.nativeActionDeferred")
        return
    end

    return originalOnNativeActionChanged(self, button, ...)
end

local function OnDominosActionChanged(_controller, buttonName)
    if not Buttons.attached or not Buttons.dominosAttached then return end
    local button = type(buttonName) == "string" and _G[buttonName] or nil
    local record = button and IG.ObservedButtons[button]
    if record and record.adapter == "dominos" then
        RefreshButtonSlot(button, record)
        if not ReadinessAwake() then DeferButton(button) end
    end
end

local function RefreshDominosRegistry(controller)
    local registry = controller and controller.buttons
    if type(registry) ~= "table" then return end

    for button in pairs(registry) do
        local record = IG.ObservedButtons[button]
        if record and record.adapter == "dominos" then
            RefreshButtonSlot(button, record)
        end
    end
end

local originalAttachDominosNow = Buttons.AttachDominosNow
function Buttons:AttachDominosNow(discoverExisting)
    local result = originalAttachDominosNow(self, discoverExisting)
    local controller = self.DominosActionButtons

    if self.dominosAttached and type(controller) == "table" then
        if not hookedDominosControllers[controller]
            and type(hooksecurefunc) == "function"
            and type(controller.OnActionChanged) == "function"
        then
            hookedDominosControllers[controller] = true
            hooksecurefunc(controller, "OnActionChanged", OnDominosActionChanged)
        end
        RefreshDominosRegistry(controller)
    end
    return result
end

local originalOnActionUsableChanged = Usability.OnActionUsableChanged
function Usability:OnActionUsableChanged(changes, ...)
    if ReadinessAwake() then
        local result = originalOnActionUsableChanged(self, changes, ...)
        InvalidateChanges(changes)
        return result
    end

    DeferChanges(changes)
    return false
end

local originalMarkCooldownDirty = IG.MarkCooldownDirty
function IG:MarkCooldownDirty(fromSpellCooldownEvent)
    if ReadinessAwake() then FlushDeferredButtons() end
    return originalMarkCooldownDirty(self, fromSpellCooldownEvent)
end

local originalMarkAllButtonsDirty = IG.MarkAllButtonsDirty
function IG:MarkAllButtonsDirty(...)
    return originalMarkAllButtonsDirty(self, ...)
end

local originalDetach = Buttons.Detach
function Buttons:Detach()
    for _, record in pairs(IG.ObservedButtons) do
        if record.conditionalIdentityPending == true then
            record.conditionalIdentityPending = false
        end
    end
    IG:WipeMap(pendingIdentityButtons)
    IG:WipeMap(deferredButtons)
    for button in pairs(slotByButton) do RemoveButton(button) end
    return originalDetach(self)
end

function Buttons:RefreshConditionalMacroSlot(button, record)
    return RefreshButtonSlot(button, record)
end

function Buttons:InvalidateConditionalMacroSlot(slot)
    return InvalidateSlot(slot)
end

function Buttons:InvalidateConditionalMacroChanges(changes)
    return InvalidateChanges(changes)
end

function Buttons:DeferConditionalMacroChanges(changes)
    return DeferChanges(changes)
end

function Buttons:FlushDeferredConditionalActions()
    return FlushDeferredButtons()
end

IG:RegisterModule("ConditionalMacroPolicy", {
    usesTargetedUsabilitySignal = true,
    invalidatesSnapshotsBeforeActiveReconcile = true,
    marksIdentityPendingForActiveChanges = true,
    separatesActiveGuardFromSleepingQueue = true,
    defersIdentityWhileReadinessSleeps = true,
    flushesBeforeCooldownRefresh = true,
    hidesStaleVisualsUntilReconcile = true,
    fullRebuildPreservesVisualGuard = true,
    publicHelpersUseMethodSemantics = true,
    parsesActionUsableChangeBatch = true,
    dirtyHookIsActionProviderOnly = true,
    nativeCallbackReadsActionAPIs = false,
    dominosIdentityRefreshesAfterProviderCommit = true,
    adapterPromotionDropsStaleSlots = true,
    slotIndexIsBounded = true,
    pendingGuardSetUsesWeakButtons = true,
    deferredSetUsesWeakButtons = true,
    parsesMacroBodies = false,
    scansActionSlots = false,
})
