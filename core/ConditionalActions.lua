local IG = _G.InterruptGlow
if not IG or not IG.Buttons or not IG.Usability then return end

local Buttons = IG.Buttons
local Glow = IG.Glow
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

local ACTION_ADAPTER = {
    native = true,
    lab = true,
    dominos = true,
    buttonforge = true,
}

local Actions = {}
IG.ConditionalActions = Actions

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
    if type(value) ~= "number" or value <= 0 or value % 1 ~= 0 then return nil end
    return value
end

local function ReadPhysicalSlot(button, record)
    if not IG.CanAccess(button) then return nil end
    if button == nil or not record then return nil end

    local adapter = record.adapter
    if adapter == "native" then
        local action, known = IG:ReadMember(button, "action")
        return known and NormalizeSlot(action) or nil
    end

    if adapter == "lab" then
        -- LAB's cached secure identity is authoritative. Falling through to
        -- button.action after an accessible empty or restricted UpdateAction
        -- can preserve the frame's previous slot in the invalidation index.
        if record.labIdentityRestricted == true then return nil end
        return NormalizeSlot(record.labSlot)
    end

    if adapter == "dominos" then
        return NormalizeSlot(record.dominosSlot) or IG.ActionResolver:GetActionSlot(button)
    end

    if adapter == "pet" or adapter == "cdm" or adapter == "buttonforge" then
        return nil
    end

    return IG.ActionResolver:GetActionSlot(button)
end

local function RefreshButtonSlot(button, record)
    if not IG.CanAccess(button) then return nil end
    if button == nil then return nil end
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

local function VisitSlot(slot, visitor, adapter)
    if not Buttons.attached or not IG.CanAccess(slot) then return 0 end
    if type(slot) == "string" then slot = tonumber(slot) end
    if type(slot) ~= "number" then return 0 end

    local set
    if slot > 0 then
        set = buttonsBySlot[slot]
    elseif slot == 0 then
        set = slotByButton
    end
    if not set then return 0 end

    local count = 0
    for button in pairs(set) do
        if IG.CanAccess(button) then
            local record = IG.ObservedButtons[button]
            if adapter == nil or (record and record.adapter == adapter) then
                count = count + 1
                visitor(button)
            end
        end
    end
    return count
end

local function ClearPendingIdentity(record)
    if not record then return end
    record.conditionalIdentityPending = false
    if record.button then
        deferredButtons[record.button] = nil
    end
end

local function MarkIdentityPending(button, deferQueue)
    if not IG.CanAccess(button) then return false end
    if button == nil then return false end

    local record = IG.ObservedButtons[button]
    if not record then return false end

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

local function InvalidateButton(button)
    IG:MarkButtonDirty(button)
end

local function InvalidateSlot(slot, adapter)
    local count = VisitSlot(slot, InvalidateButton, adapter)
    if count > 0 then
        local stat = adapter == "lab"
            and "events.labSlotInvalidations"
            or "events.conditionalMacroSlots"
        IG:BumpStat(stat, count)
    end
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
    if not IG.CanAccessTable(changes) then return 0 end

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
        elseif not IG.PendingButtons or not IG.PendingButtons[button] then
            count = count + 1
            IG:QueueButtonForReconcile(button)
        end
    end

    if count > 0 then IG:BumpStat("events.conditionalMacroDeferredFlush", count) end
    return count
end

-- Explicit integration points keep provider, queue and visual ownership
-- separate without replacing methods after another module defines them.
function Actions:Observe(button, record)
    RefreshButtonSlot(button, record)
end

function Actions:QueueButton(button)
    local record = IG.ObservedButtons[button]
    if record then RefreshButtonSlot(button, record) end
    if record and ACTION_ADAPTER[record.adapter] then
        local awake = ReadinessAwake()
        MarkIdentityPending(button, not awake)
        return awake
    end
    return true
end

function Actions:Reconciled(record)
    ClearPendingIdentity(record)
end

function Actions:InvalidateSlot(slot, adapter)
    return InvalidateSlot(slot, adapter)
end

function Actions:OnUsabilityChanged(changes)
    if not IG.CanAccessTable(changes) then
        -- An opaque batch identifies no slot. Revalidate only the bounded set
        -- already observed by this addon; never inspect or retain its payload.
        if ReadinessAwake() then return InvalidateSlot(0) end
        return DeferSlot(0)
    end
    if ReadinessAwake() then return InvalidateChanges(changes) end
    return DeferChanges(changes)
end

function Actions:FlushDeferred()
    return FlushDeferredButtons()
end

function Actions:Detach()
    for _, record in pairs(IG.ObservedButtons) do
        record.conditionalIdentityPending = false
    end
    IG:WipeMap(deferredButtons)
    for button in pairs(slotByButton) do RemoveButton(button) end
end
