local IG = _G.InterruptGlow
if not IG or not IG.Buttons or not IG.Usability then return end

local Buttons = IG.Buttons
local Usability = IG.Usability
local pairs = pairs
local type = type
local tonumber = tonumber

-- Conditional macro resolution can change when mouseover/help/harm context
-- changes without changing the physical action slot. ACTION_USABLE_CHANGED is
-- the bounded current-client signal already consumed by the readiness layer.
-- Maintain an O(1) slot -> observed-button index so that the same event can
-- request identity reconciliation for only the affected physical buttons.
--
-- This preserves in-combat heal/interrupt macro switching without restoring a
-- frame scan, a 1..540 slot scan, macro-body parsing, or LibActionButton's broad
-- visual-update callback.
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

    local action, actionKnown = IG:ReadMember(button, "action")
    if actionKnown then
        slot = NormalizeSlot(action)
        if slot then return slot end
    end

    local stateType, typeKnown = IG:ReadMember(button, "_state_type")
    local stateAction, actionStateKnown = IG:ReadMember(button, "_state_action")
    if typeKnown and actionStateKnown and stateType == "action" then
        return NormalizeSlot(stateAction)
    end

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

local originalObserveButton = Buttons.ObserveButton
function Buttons:ObserveButton(button, adapter, options)
    local record = originalObserveButton(self, button, adapter, options)
    if record then RefreshButtonSlot(button, record) end
    return record
end

local originalMarkButtonDirty = IG.MarkButtonDirty
function IG:MarkButtonDirty(button)
    local physicalButton = button and button.button or button
    if physicalButton then
        RefreshButtonSlot(physicalButton, IG.ObservedButtons[physicalButton])
    end
    return originalMarkButtonDirty(self, button)
end

local originalOnActionUsableChanged = Usability.OnActionUsableChanged
function Usability:OnActionUsableChanged(slot, ...)
    -- Preserve the readiness module's filtering first, then request a physical
    -- identity refresh for the same accessible slot. The shared dirty queue
    -- coalesces repeated signals to one reconciliation per button per frame.
    local result = originalOnActionUsableChanged(self, slot, ...)
    InvalidateSlot(slot)
    return result
end

local originalDetach = Buttons.Detach
function Buttons:Detach()
    for button in pairs(slotByButton) do RemoveButton(button) end
    return originalDetach(self)
end

Buttons.RefreshConditionalMacroSlot = RefreshButtonSlot
Buttons.InvalidateConditionalMacroSlot = InvalidateSlot

IG:RegisterModule("ConditionalMacroPolicy", {
    usesTargetedUsabilitySignal = true,
    slotIndexIsBounded = true,
    parsesMacroBodies = false,
    scansActionSlots = false,
})
