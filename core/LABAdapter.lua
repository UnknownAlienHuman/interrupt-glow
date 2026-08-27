local IG = _G.InterruptGlow
if not IG or not IG.Buttons then return end

local Buttons = IG.Buttons
local _G = _G
local CreateFrame = _G.CreateFrame
local hooksecurefunc = _G.hooksecurefunc
local type = type
local pairs = pairs
local pcall = pcall
local tonumber = tonumber

-- LibActionButton fires OnButtonUpdate after every full visual Update(), which
-- includes cooldown, usability, target and other high-frequency refreshes. LAB
-- separately receives ACTIONBAR_SLOT_CHANGED for slot-backed action buttons.
-- Use exact UpdateAction hooks plus a targeted slot index instead of waking on
-- every visual update.
local hookedButtons = setmetatable({}, { __mode = "k" })
local buttonSlots = setmetatable({}, { __mode = "k" })
local buttonsBySlot = {}

local slotEventFrame = CreateFrame("Frame")
slotEventFrame:Hide()

local function GetIdentity(button)
    if not button then return nil, nil, nil end

    local stateType, typeKnown = IG:ReadMember(button, "_state_type")
    local stateAction, actionKnown = IG:ReadMember(button, "_state_action")
    if not typeKnown or not actionKnown then return nil, nil, nil end

    local slot = nil
    if stateType == "action" and IG.CanAccess(stateAction) then
        if type(stateAction) == "number" then
            slot = stateAction
        elseif type(stateAction) == "string" then
            slot = tonumber(stateAction)
        end
    end
    return stateType, stateAction, slot
end

local function RemoveFromSlot(button)
    local oldSlot = buttonSlots[button]
    if oldSlot == nil then return end

    buttonSlots[button] = nil
    local set = buttonsBySlot[oldSlot]
    if set then
        set[button] = nil
        if next(set) == nil then buttonsBySlot[oldSlot] = nil end
    end
end

local function SetButtonSlot(button, slot)
    local oldSlot = buttonSlots[button]
    if oldSlot == slot then return end

    RemoveFromSlot(button)
    if type(slot) ~= "number" or slot <= 0 then return end

    local set = buttonsBySlot[slot]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        buttonsBySlot[slot] = set
    end
    set[button] = true
    buttonSlots[button] = slot
end

local function CacheIdentity(record, button)
    if not record or not button then return false end

    local stateType, stateAction, slot = GetIdentity(button)
    if stateType == nil and stateAction == nil and slot == nil then return false end

    local changed = record.labStateType ~= stateType
        or record.labStateAction ~= stateAction
        or record.labSlot ~= slot

    record.labStateType = stateType
    record.labStateAction = stateAction
    record.labSlot = slot
    SetButtonSlot(button, slot)
    return changed
end

local function OnUpdateAction(button)
    -- hooksecurefunc hooks cannot be removed. The attach flag provides the
    -- symmetric behavioral detach required by the module contract.
    if not Buttons.attached then return end

    local record = button and IG.ObservedButtons[button]
    if not record then return end

    if CacheIdentity(record, button) then
        IG:MarkButtonDirty(button)
        IG:BumpStat("events.labActionIdentityChanged")
    end
end

local function HookButton(button)
    if not button then return false end
    if hookedButtons[button] then return true end

    local method = button.UpdateAction
    if type(method) ~= "function" or type(hooksecurefunc) ~= "function" then
        return false
    end

    local ok = pcall(hooksecurefunc, button, "UpdateAction", OnUpdateAction)
    if not ok then return false end
    hookedButtons[button] = true
    return true
end

local function ForEachLibraryButton(library, callback)
    local count = 0
    if not library then return count end

    if type(library.GetAllButtons) == "function" then
        local ok, buttons = pcall(library.GetAllButtons, library)
        if ok and type(buttons) == "table" then
            for button in pairs(buttons) do
                count = count + 1
                callback(button)
            end
            return count
        end
    end

    local registry = library.buttonRegistry
    if type(registry) == "table" then
        for button in pairs(registry) do
            count = count + 1
            callback(button)
        end
    end
    return count
end

local originalAttachLABLibrary = Buttons.AttachLABLibrary
function Buttons:AttachLABLibrary(library, discoverExisting, forceDiscovery)
    if type(library) ~= "table" then return end

    originalAttachLABLibrary(self, library, discoverExisting, forceDiscovery)

    local allHooked = true
    local buttonCount = ForEachLibraryButton(library, function(button)
        local record = IG.ObservedButtons[button]
        if record then CacheIdentity(record, button) end
        if not HookButton(button) then allHooked = false end
    end)

    -- Remove the broad callback only after proving that this current provider's
    -- existing buttons expose an exact UpdateAction hook surface. Empty or
    -- nonstandard providers retain the identity-deduped fallback below.
    if buttonCount > 0 and allHooked and type(library.UnregisterCallback) == "function" then
        library.UnregisterCallback(self, "OnButtonUpdate")
    end
end

function Buttons:OnLABButtonCreated(_, button)
    if not self.attached then return end

    local record = self:ObserveButton(button, "lab", { skipDirty = true })
    if not record then return end

    CacheIdentity(record, button)
    HookButton(button)
    IG:MarkButtonDirty(button)
end

function Buttons:OnLABButtonContentsChanged(_, button)
    if not self.attached then return end

    local record = self:ObserveButton(button, "lab", { skipDirty = true })
    if not record then return end

    CacheIdentity(record, button)
    HookButton(button)
    IG:MarkButtonDirty(button)
end

-- Fallback for an empty-at-attach or nonstandard LAB provider. Even if LAB calls
-- this for every visual update, identity reads prevent any discovery, cooldown
-- query, allocation or UI work unless the secure state itself changed. Macro
-- feedback within a stable action slot is handled by the targeted slot event.
function Buttons:OnLABButtonUpdate(_, button)
    if not self.attached then return end

    local record = button and IG.ObservedButtons[button]
    if not record then return end
    if CacheIdentity(record, button) then
        IG:MarkButtonDirty(button)
        IG:BumpStat("events.labFallbackIdentityChanged")
    end
end

slotEventFrame:SetScript("OnEvent", function(_, _event, slot)
    if not Buttons.attached or not IG.CanAccess(slot) then return end

    if type(slot) == "string" then slot = tonumber(slot) end
    if type(slot) ~= "number" then return end

    if slot > 0 then
        local set = buttonsBySlot[slot]
        if set then
            for button in pairs(set) do IG:MarkButtonDirty(button) end
        end
        return
    end

    -- slot == 0 is Blizzard's explicit global invalidation. It is rare and still
    -- bounded to the already-indexed LAB button set; no action-slot or frame scan.
    for button in pairs(buttonSlots) do IG:MarkButtonDirty(button) end
end)

local originalAttach = Buttons.Attach
function Buttons:Attach(discoverExisting)
    local wasAttached = self.attached
    originalAttach(self, discoverExisting)
    if not wasAttached and self.attached then
        slotEventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    end
end

local originalDetach = Buttons.Detach
function Buttons:Detach()
    if self.attached then slotEventFrame:UnregisterEvent("ACTIONBAR_SLOT_CHANGED") end
    originalDetach(self)
end
