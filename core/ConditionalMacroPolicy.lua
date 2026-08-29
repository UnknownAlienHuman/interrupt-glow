local IG = _G.InterruptGlow
if not IG or not IG.Buttons or not IG.Usability then return end

local Buttons = IG.Buttons
local Usability = IG.Usability
local pairs = pairs
local next = next
local type = type
local tonumber = tonumber

-- Conditional macro resolution can change when mouseover/help/harm context
-- changes without changing the physical action slot. Keep a bounded
-- slot -> observed-button index and consume the current ACTION_USABLE_CHANGED
-- batch without scanning action slots or parsing macro bodies.
local slotByButton = setmetatable({}, { __mode = "k" })
local buttonsBySlot = {}

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

local function ReadPhysicalSlot(button, record)
    if not button then return nil end

    local slot = record and NormalizeSlot(record.labSlot)
    if slot then return slot end

    slot = record and NormalizeSlot(record.dominosSlot)
    if slot then return slot end

    if record and record.adapter == "native" then
        -- Native Blizzard action buttons expose an ordinary positive action
        -- field. Avoid protected generic member reads in the mouseover callback.
        local action = button.action
        if not IG.CanAccess(action) then return nil end
        return NormalizeSlot(action)
    end

    local stateType, typeKnown = IG:ReadMember(button, "_state_type")
    local stateAction, actionStateKnown = IG:ReadMember(button, "_state_action")
    if typeKnown and actionStateKnown and stateType == "action" then
        slot = NormalizeSlot(stateAction)
        if slot then return slot end
    end

    local action, actionKnown = IG:ReadMember(button, "action")
    if actionKnown then return NormalizeSlot(action) end
    return nil
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

local function InvalidateSlot(slot)
    if not Buttons.attached or not IG.CanAccess(slot) then return 0 end
    if type(slot) == "string" then slot = tonumber(slot) end
    if type(slot) ~= "number" then return 0 end

    local count = 0
    if slot > 0 then
        local set = buttonsBySlot[slot]
        if set then
            for button in pairs(set) do
                count = count + 1
                IG:MarkButtonDirty(button)
            end
        end
    elseif slot == 0 then
        -- Blizzard uses slot 0 for an explicit global action invalidation. This
        -- rare path remains bounded to already-observed slot-backed buttons.
        for button in pairs(slotByButton) do
            count = count + 1
            IG:MarkButtonDirty(button)
        end
    end

    if count > 0 then IG:BumpStat("events.conditionalMacroSlots", count) end
    return count
end

local function InvalidateChanges(changes)
    if not IG.CanAccess(changes) or type(changes) ~= "table" then return 0 end

    local count = 0
    for _, change in pairs(changes) do
        local slot, slotKnown = IG:ReadMember(change, "slot")
        if slotKnown then
            slot = IG:AsNumber(slot)
            if type(slot) == "number" then count = count + InvalidateSlot(slot) end
        end
    end
    return count
end

local originalObserveButton = Buttons.ObserveButton
function Buttons:ObserveButton(button, adapter, options)
    local record = originalObserveButton(self, button, adapter, options)
    if record then RefreshButtonSlot(button, record) end
    return record
end

-- LibActionButton's exact UpdateAction hook updates record.labSlot immediately
-- before it queues the record. Refresh only that cached LAB identity here; do
-- not add generic member reads to native/CDM/ButtonForge dirty paths.
local originalMarkButtonDirty = IG.MarkButtonDirty
function IG:MarkButtonDirty(button)
    local physicalButton = button and button.button or button
    local record = physicalButton and IG.ObservedButtons[physicalButton]
    if record and record.adapter == "lab" then
        RefreshButtonSlot(physicalButton, record)
    end
    return originalMarkButtonDirty(self, button)
end

-- Keep the native callback queue-only: the wrapper refreshes one ordinary slot
-- field, but performs no C_ActionBar/GetActionInfo classification or cooldown
-- work. The original callback still invalidates before dirty-queue dedupe.
local originalOnNativeActionChanged = Buttons.OnNativeActionChanged
function Buttons:OnNativeActionChanged(button, ...)
    local result = originalOnNativeActionChanged(self, button, ...)
    local record = button and IG.ObservedButtons[button]
    if record then RefreshButtonSlot(button, record) end
    return result
end

local originalOnActionUsableChanged = Usability.OnActionUsableChanged
function Usability:OnActionUsableChanged(changes, ...)
    local result = originalOnActionUsableChanged(self, changes, ...)
    InvalidateChanges(changes)
    return result
end

local originalDetach = Buttons.Detach
function Buttons:Detach()
    for button in pairs(slotByButton) do RemoveButton(button) end
    return originalDetach(self)
end

Buttons.RefreshConditionalMacroSlot = RefreshButtonSlot
Buttons.InvalidateConditionalMacroSlot = InvalidateSlot
Buttons.InvalidateConditionalMacroChanges = InvalidateChanges

IG:RegisterModule("ConditionalMacroPolicy", {
    usesTargetedUsabilitySignal = true,
    identityUpdatesWhileReadinessSleeps = true,
    parsesActionUsableChangeBatch = true,
    dirtyHookIsLABOnly = true,
    nativeCallbackReadsActionAPIs = false,
    slotIndexIsBounded = true,
    parsesMacroBodies = false,
    scansActionSlots = false,
})
