local IG = _G.InterruptGlow
if not IG or not IG.Buttons then return end

local Buttons = IG.Buttons
local Adapter = { attached = false }
IG.LABAdapter = Adapter
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
-- Use exact UpdateAction hooks plus ConditionalActions' shared slot index
-- instead of waking on every visual update.
local hookedButtons = setmetatable({}, { __mode = "k" })
local broadUpdateDisabled = setmetatable({}, { __mode = "k" })

local slotEventFrame = CreateFrame("Frame")
slotEventFrame:Hide()

local function IsButtonObject(value)
    if not IG.CanAccess(value) then return false end
    local valueType = type(value)
    return valueType == "table" or valueType == "userdata"
end

-- Returns stateType, stateAction, slot, identityKnown. Accessible nil/nil is a
-- real empty identity and must clear the previous slot. Inaccessible fields are
-- a separate fail-closed state; they also clear the old identity, but are marked
-- restricted so one later readable update can be recognized as a transition.
local function GetIdentity(button)
    if not IG.CanAccess(button) or button == nil then return nil, nil, nil, false end

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

local function CacheIdentity(record, button)
    if not record or not IG.CanAccess(button) or button == nil then return false end

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
    return changed
end

local function OnUpdateAction(button)
    if not Adapter.attached or not Buttons.attached then return end
    if not IG.CanAccess(button) or button == nil then return end

    local record = IG.ObservedButtons[button]
    if not record then return end

    if CacheIdentity(record, button) then
        IG:MarkButtonDirty(button)
        IG:BumpStat("events.labActionIdentityChanged")
    end
end

local function HookButton(button)
    if not IG.CanAccess(button) or button == nil then return false end
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
    if not IG.CanAccessTable(buttons) then return 0 end
    local count = 0
    for key, value in pairs(buttons) do
        -- Upstream LAB uses a button-keyed set, while some forks expose arrays.
        -- Never pass a numeric array index to the frame observer.
        local keyIsButton = IsButtonObject(key)
        local valueIsButton = IsButtonObject(value)
        local button = keyIsButton and key or (valueIsButton and value or nil)
        if button then
            count = count + 1
            callback(button)
        end
    end
    return count
end

local function ForEachLibraryButton(library, callback)
    if not IG.CanAccessTable(library) then return 0 end

    local getAllButtons, methodKnown = IG:ReadMember(library, "GetAllButtons")
    if methodKnown and type(getAllButtons) == "function" then
        local ok, buttons = pcall(getAllButtons, library)
        if ok and IG.CanAccessTable(buttons) then
            local count = ForEachButtonTable(buttons, callback)
            if count > 0 then return count end
        end
    end

    local registry, registryKnown = IG:ReadMember(library, "buttonRegistry")
    if registryKnown and IG.CanAccessTable(registry) then
        return ForEachButtonTable(registry, callback)
    end
    return 0
end

local function DiscoverLibraryButtons(library, force)
    if not IG.CanAccessTable(library) then return 0 end
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
    if not IG.CanAccessTable(library) then return false end
    if broadUpdateDisabled[library] then return true end
    local unregisterCallback, methodKnown = IG:ReadMember(library, "UnregisterCallback")
    if not methodKnown or type(unregisterCallback) ~= "function" then return false end

    local allHooked = true
    local buttonCount = ForEachLibraryButton(library, function(button)
        local wasObserved = IG.ObservedButtons[button] ~= nil
        local record = IG.ObservedButtons[button]
            or Buttons:ObserveButton(button, "lab", { skipDirty = true })
        if record then
            local identityChanged = CacheIdentity(record, button)
            if identityChanged or not wasObserved then
                IG:MarkButtonDirty(button)
            end
        end
        if not HookButton(button) then allHooked = false end
    end)

    if buttonCount <= 0 or not allHooked then return false end

    unregisterCallback(Adapter, "OnButtonUpdate")
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

function Adapter:AttachLibrary(library, discoverExisting, forceDiscovery)
    if not IG.CanAccessTable(library) then return end
    if not Buttons.labLibraries[library] then
        local registerCallback, known = IG:ReadMember(library, "RegisterCallback")
        if not known or type(registerCallback) ~= "function" then return end
        Buttons.labLibraries[library] = true
        registerCallback(self, "OnButtonCreated", "OnButtonCreated")
        registerCallback(self, "OnButtonUpdate", "OnButtonUpdate")
        registerCallback(self, "OnButtonContentsChanged", "OnButtonContentsChanged")
    end
    if discoverExisting then DiscoverLibraryButtons(library, forceDiscovery == true) end
    DisableBroadUpdateIfFullyHooked(library)
end

function Adapter:OnButtonCreated(_, button)
    if not self.attached or not Buttons.attached then return end

    local record = Buttons:ObserveButton(button, "lab", { skipDirty = true })
    if not record then return end

    CacheIdentity(record, button)
    HookButton(button)
    IG:MarkButtonDirty(button)
    TryDisableBroadUpdates()
end

function Adapter:OnButtonContentsChanged(_, button)
    if not self.attached or not Buttons.attached then return end

    local record = Buttons:ObserveButton(button, "lab", { skipDirty = true })
    if not record then return end

    CacheIdentity(record, button)
    HookButton(button)
    IG:MarkButtonDirty(button)
    TryDisableBroadUpdates()
end

-- Fallback for an empty-at-attach or nonstandard LAB provider. Even if LAB calls
-- this for every visual update, identity reads prevent discovery, cooldown work,
-- allocation or UI mutation unless the secure action identity actually changed.
function Adapter:OnButtonUpdate(_, button)
    if not self.attached or not Buttons.attached then return end
    if not IG.CanAccess(button) or button == nil then return end

    local record = IG.ObservedButtons[button]
    if not record then return end
    if CacheIdentity(record, button) then
        IG:MarkButtonDirty(button)
        IG:BumpStat("events.labFallbackIdentityChanged")
    end
end

slotEventFrame:SetScript("OnEvent", function(_, _event, slot)
    if not Adapter.attached or not Buttons.attached or not IG.CanAccess(slot) then return end

    if type(slot) == "string" then slot = tonumber(slot) end
    if type(slot) ~= "number" then return end

    if slot < 0 then return end
    -- ConditionalActions owns the shared known-button index. Restrict this
    -- provider event to LAB records so native action work is not widened.
    if IG.ConditionalActions then
        IG.ConditionalActions:InvalidateSlot(slot, "lab")
    end
end)

function Adapter:Attach()
    if self.attached then return end
    self.attached = true
    slotEventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
end

function Adapter:Detach()
    if not self.attached then return end
    self.attached = false
    slotEventFrame:UnregisterEvent("ACTIONBAR_SLOT_CHANGED")
    for library in pairs(Buttons.labLibraries) do
        local unregister, known = IG:ReadMember(library, "UnregisterCallback")
        if known and type(unregister) == "function" then
            unregister(self, "OnButtonCreated")
            unregister(self, "OnButtonUpdate")
            unregister(self, "OnButtonContentsChanged")
        end
        Buttons.labLibraries[library] = nil
    end
    IG:WipeMap(Buttons.labDiscoveredLibraries)
    IG:WipeMap(broadUpdateDisabled)
end
