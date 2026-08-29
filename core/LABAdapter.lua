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
local broadUpdateDisabled = setmetatable({}, { __mode = "k" })

local slotEventFrame = CreateFrame("Frame")
slotEventFrame:Hide()

local function IsButtonObject(value)
    local valueType = type(value)
    return valueType == "table" or valueType == "userdata"
end

-- Returns stateType, stateAction, slot, identityKnown. Accessible nil/nil is a
-- real empty identity and must clear the previous slot. Inaccessible fields are
-- a separate fail-closed state; they also clear the old identity, but are marked
-- restricted so one later readable update can be recognized as a transition.
local function GetIdentity(button)
    if not button or not IG.CanAccess(button) then return nil, nil, nil, false end

    local stateType, typeKnown = IG:ReadMember(button, "_state_type")
    local stateAction, actionKnown = IG:ReadMember(button, "_state_action")
    if not typeKnown or not actionKnown then return nil, nil, nil, false end

    local slot = nil
    if stateType == "action" then
        if type(stateAction) == "number" then
            slot = stateAction
        elseif type(stateAction) == "string" then
            slot = tonumber(stateAction)
        end
        if type(slot) ~= "number" or slot <= 0 then slot = nil end
    end
    return stateType, stateAction, slot, true
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

    local stateType, stateAction, slot, identityKnown = GetIdentity(button)
    local restricted = identityKnown ~= true
    local changed = record.labIdentityRestricted ~= restricted
        or record.labStateType ~= stateType
        or record.labStateAction ~= stateAction
        or record.labSlot ~= slot

    record.labIdentityRestricted = restricted
    record.labStateType = stateType
    record.labStateAction = stateAction
    record.labSlot = slot
    SetButtonSlot(button, slot)
    return changed
end

local function OnUpdateAction(button)
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

    local method, methodKnown = IG:ReadMember(button, "UpdateAction")
    if not methodKnown or type(method) ~= "function" or type(hooksecurefunc) ~= "function" then
        return false
    end

    local ok = pcall(hooksecurefunc, button, "UpdateAction", OnUpdateAction)
    if not ok then return false end
    hookedButtons[button] = true
    return true
end

local function ForEachButtonTable(buttons, callback)
    local count = 0
    for key, value in pairs(buttons) do
        -- Upstream LAB uses a button-keyed set, while some forks expose arrays.
        -- Never pass a numeric array index to the frame observer.
        local button = IsButtonObject(key) and key or (IsButtonObject(value) and value or nil)
        if button then
            count = count + 1
            callback(button)
        end
    end
    return count
end

local function ForEachLibraryButton(library, callback)
    if not library then return 0 end

    if type(library.GetAllButtons) == "function" then
        local ok, buttons = pcall(library.GetAllButtons, library)
        if ok and type(buttons) == "table" then
            local count = ForEachButtonTable(buttons, callback)
            if count > 0 then return count end
        end
    end

    local registry = library.buttonRegistry
    if type(registry) == "table" then
        return ForEachButtonTable(registry, callback)
    end
    return 0
end

local function DiscoverLibraryButtons(library, force)
    if not library then return 0 end
    if Buttons.labDiscoveredLibraries[library] and not force then return 0 end
    Buttons.labDiscoveredLibraries[library] = true

    return ForEachLibraryButton(library, function(button)
        local record = Buttons:ObserveButton(button, "lab", { skipDirty = true })
        if record then
            CacheIdentity(record, button)
            HookButton(button)
            IG:MarkButtonDirty(button)
        end
    end)
end

local function DisableBroadUpdateIfFullyHooked(library)
    if not library or broadUpdateDisabled[library] then return true end
    if type(library.UnregisterCallback) ~= "function" then return false end

    local allHooked = true
    local buttonCount = ForEachLibraryButton(library, function(button)
        local wasObserved = IG.ObservedButtons[button] ~= nil
        local record = IG.ObservedButtons[button]
            or Buttons:ObserveButton(button, "lab", { skipDirty = true })
        if record then
            CacheIdentity(record, button)
            if not wasObserved then IG:MarkButtonDirty(button) end
        end
        if not HookButton(button) then allHooked = false end
    end)

    if buttonCount <= 0 or not allHooked then return false end

    library.UnregisterCallback(Buttons, "OnButtonUpdate")
    broadUpdateDisabled[library] = true
    IG:BumpStat("lab.broadUpdateCallbacksRemoved")
    return true
end

local function TryDisableBroadUpdates()
    for library in pairs(Buttons.labLibraries) do
        if not broadUpdateDisabled[library] then
            DisableBroadUpdateIfFullyHooked(library)
        end
    end
end

local originalAttachLABLibrary = Buttons.AttachLABLibrary
function Buttons:AttachLABLibrary(library, discoverExisting, forceDiscovery)
    if type(library) ~= "table" then return end

    -- Register lifecycle callbacks through the base adapter, but own discovery
    -- here so set- and array-style registries use the same validated enumerator.
    originalAttachLABLibrary(self, library, false, false)
    if discoverExisting then
        DiscoverLibraryButtons(library, forceDiscovery == true)
    end
    DisableBroadUpdateIfFullyHooked(library)
end

function Buttons:OnLABButtonCreated(_, button)
    if not self.attached then return end

    local record = self:ObserveButton(button, "lab", { skipDirty = true })
    if not record then return end

    CacheIdentity(record, button)
    HookButton(button)
    IG:MarkButtonDirty(button)
    TryDisableBroadUpdates()
end

function Buttons:OnLABButtonContentsChanged(_, button)
    if not self.attached then return end

    local record = self:ObserveButton(button, "lab", { skipDirty = true })
    if not record then return end

    CacheIdentity(record, button)
    HookButton(button)
    IG:MarkButtonDirty(button)
    TryDisableBroadUpdates()
end

-- Fallback for an empty-at-attach or nonstandard LAB provider. Even if LAB calls
-- this for every visual update, identity reads prevent discovery, cooldown work,
-- allocation or UI mutation unless the secure action identity actually changed.
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
    -- bounded to already-indexed LAB buttons; no slot or frame scan occurs.
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
    for library in pairs(broadUpdateDisabled) do broadUpdateDisabled[library] = nil end
    for button in pairs(buttonSlots) do RemoveFromSlot(button) end
    originalDetach(self)
end

IG:RegisterModule("LABAdapterPolicy", {
    exactUpdateActionHooks = true,
    accessibleEmptyIdentityClearsSlot = true,
    inaccessibleIdentityFailsClosed = true,
    staleSlotIndexesClearedOnDetach = true,
    broadVisualUpdateCallbackRetiredWhenSafe = true,
})
