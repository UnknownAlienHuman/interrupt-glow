local IG = _G.InterruptGlow
if not IG or not IG.Buttons or not IG.Usability then return end

local Buttons = IG.Buttons
local Usability = IG.Usability
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
local deferredButtons = setmetatable({}, { __mode = "k" })
local hookedDominosControllers = setmetatable({}, { __mode = "k" })

local ACTION_ADAPTER = {
    native = true,
    lab = true,
    dominos = true,
    buttonforge = true,
}

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
        -- Native Blizzard action buttons expose an ordinary positive action
        -- field. Avoid protected generic member reads in the mouseover callback.
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

    -- Pet, Cooldown Viewer and ButtonForge records are not physical action-slot
    -- consumers. Never retain an old native/LAB/Dominos slot after adapter
    -- priority promotes the same frame to one of these providers.
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
        -- Blizzard uses slot 0 for an explicit global action invalidation. This
        -- rare path remains bounded to already-observed slot-backed buttons.
        for button in pairs(slotByButton) do
            count = count + 1
            visitor(button)
        end
    end
    return count
end

local function InvalidateSlot(slot)
    local count = VisitSlot(slot, function(button)
        IG:MarkButtonDirty(button)
    end)
    if count > 0 then IG:BumpStat("events.conditionalMacroSlots", count) end
    return count
end

local function DeferSlot(slot)
    local count = VisitSlot(slot, function(button)
        deferredButtons[button] = true
    end)
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

local function DeferButton(button)
    if button and IG.ObservedButtons[button] then
        deferredButtons[button] = true
    end
end

local function FlushDeferredButtons()
    if not Buttons.attached then
        IG:WipeMap(deferredButtons)
        return 0
    end

    local count = 0
    for button in pairs(deferredButtons) do
        deferredButtons[button] = nil
        if IG.ObservedButtons[button] then
            count = count + 1
            IG:MarkButtonDirty(button)
        end
    end

    if count > 0 then IG:BumpStat("events.conditionalMacroDeferredFlush", count) end
    return count
end

local originalObserveButton = Buttons.ObserveButton
function Buttons:ObserveButton(button, adapter, options)
    local record = originalObserveButton(self, button, adapter, options)
    if record then RefreshButtonSlot(button, record) end
    return record
end

-- Exact provider identity callbacks may fire continuously while mouseover/help/
-- harm context changes. When no cast or countdown consumes readiness, retain one
-- weak deferred record instead of waking the reconciliation worker every frame.
local originalMarkButtonDirty = IG.MarkButtonDirty
function IG:MarkButtonDirty(button)
    local physicalButton = button and button.button or button
    local record = physicalButton and IG.ObservedButtons[physicalButton]

    if record and (record.adapter == "lab" or record.adapter == "dominos") then
        RefreshButtonSlot(physicalButton, record)
    end

    if record and ACTION_ADAPTER[record.adapter] and not ReadinessAwake() then
        record.actionSnapshotFresh = false
        DeferButton(physicalButton)
        return
    end
    return originalMarkButtonDirty(self, button)
end

-- Keep the native callback free of action API work while readiness sleeps. The
-- latest physical slot and invalid snapshot are retained; a new relevant cast
-- flushes the record before the same batched cooldown pass.
local originalOnNativeActionChanged = Buttons.OnNativeActionChanged
function Buttons:OnNativeActionChanged(button, ...)
    local record = button and IG.ObservedButtons[button]
    if not record then
        record = self:ObserveButton(button, "native", { skipDirty = true })
        if not record then return end
    end

    RefreshButtonSlot(button, record)
    if not ReadinessAwake() then
        record.actionSnapshotFresh = false
        DeferButton(button)
        IG:BumpStat("events.nativeActionDeferred")
        return
    end

    return originalOnNativeActionChanged(self, button, ...)
end

-- Dominos updates record.dominosSlot after Buttons:ObserveButton has already
-- run. Install a second, later post-hook on the exact provider callback so the
-- conditional index observes the committed slot rather than the previous one.
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

        -- Original discovery commits record.dominosSlot after ObserveButton.
        -- Repair the bounded index once after that provider-owned pass.
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

-- CastTracking updates normalized cast state before requesting readiness. Flush
-- deferred action identities first so Shared:Flush reconciles buttons before the
-- cooldown pass in the same frame.
local originalMarkCooldownDirty = IG.MarkCooldownDirty
function IG:MarkCooldownDirty(fromSpellCooldownEvent)
    if ReadinessAwake() then FlushDeferredButtons() end
    return originalMarkCooldownDirty(self, fromSpellCooldownEvent)
end

local originalMarkAllButtonsDirty = IG.MarkAllButtonsDirty
function IG:MarkAllButtonsDirty(...)
    IG:WipeMap(deferredButtons)
    return originalMarkAllButtonsDirty(self, ...)
end

local originalDetach = Buttons.Detach
function Buttons:Detach()
    IG:WipeMap(deferredButtons)
    for button in pairs(slotByButton) do RemoveButton(button) end
    return originalDetach(self)
end

-- Public helpers are methods. Bind `self` explicitly instead of exposing the
-- underlying locals directly; callers and tests use the normal colon syntax.
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
    defersIdentityWhileReadinessSleeps = true,
    flushesBeforeCooldownRefresh = true,
    publicHelpersUseMethodSemantics = true,
    parsesActionUsableChangeBatch = true,
    dirtyHookIsActionProviderOnly = true,
    nativeCallbackReadsActionAPIs = false,
    dominosIdentityRefreshesAfterProviderCommit = true,
    adapterPromotionDropsStaleSlots = true,
    slotIndexIsBounded = true,
    deferredSetUsesWeakButtons = true,
    parsesMacroBodies = false,
    scansActionSlots = false,
})
