local IG = _G.InterruptGlow
if not IG or not IG.Buttons then return end

local Buttons = IG.Buttons
local _G = _G
local hooksecurefunc = _G.hooksecurefunc
local type = type
local pairs = pairs
local pcall = pcall

-- LibActionButton fires OnButtonUpdate after every full visual Update(), which
-- includes cooldown, usability, target and other high-frequency refreshes. The
-- action identity itself changes through button:UpdateAction(). Hook that exact
-- method and remove the broad callback so Interrupt Glow does not amplify LAB's
-- own ACTIONBAR_UPDATE_COOLDOWN fan-out.
local hookedButtons = setmetatable({}, { __mode = "k" })

local function CacheIdentity(record, button)
    if not record or not button then return false end

    -- LAB stores these as ordinary addon-owned fields on its frame object. Use
    -- the shared protected-index helper because WoW frame objects are not
    -- guaranteed to be plain Lua tables on every client build.
    local stateType, typeKnown = IG:ReadMember(button, "_state_type")
    local stateAction, actionKnown = IG:ReadMember(button, "_state_action")
    if not typeKnown or not actionKnown then return false end

    local changed = record.labStateType ~= stateType or record.labStateAction ~= stateAction
    record.labStateType = stateType
    record.labStateAction = stateAction
    return changed
end

local function OnUpdateAction(button)
    local record = button and IG.ObservedButtons[button]
    if not record then return end

    if CacheIdentity(record, button) then
        IG:MarkButtonDirty(button)
        IG:BumpStat("events.labActionIdentityChanged")
    end
end

local function HookButton(button)
    if not button or hookedButtons[button] then return false end
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
    if not library then return end

    if type(library.GetAllButtons) == "function" then
        local ok, buttons = pcall(library.GetAllButtons, library)
        if ok and type(buttons) == "table" then
            for button in pairs(buttons) do callback(button) end
            return
        end
    end

    local registry = library.buttonRegistry
    if type(registry) == "table" then
        for button in pairs(registry) do callback(button) end
    end
end

local originalAttachLABLibrary = Buttons.AttachLABLibrary
function Buttons:AttachLABLibrary(library, discoverExisting, forceDiscovery)
    if type(library) ~= "table" then return end

    originalAttachLABLibrary(self, library, discoverExisting, forceDiscovery)

    -- The original adapter registers this callback for compatibility. Current
    -- LAB exposes UpdateAction on every button, so remove the broad callback and
    -- install exact per-button post-hooks instead.
    if type(library.UnregisterCallback) == "function" then
        library.UnregisterCallback(self, "OnButtonUpdate")
    end

    ForEachLibraryButton(library, function(button)
        local record = IG.ObservedButtons[button]
        if record then CacheIdentity(record, button) end
        HookButton(button)
    end)
end

function Buttons:OnLABButtonCreated(_, button)
    local record = self:ObserveButton(button, "lab", { skipDirty = true })
    if not record then return end

    CacheIdentity(record, button)
    HookButton(button)
    IG:MarkButtonDirty(button)
end

function Buttons:OnLABButtonContentsChanged(_, button)
    local record = self:ObserveButton(button, "lab", { skipDirty = true })
    if not record then return end

    CacheIdentity(record, button)
    HookButton(button)
    IG:MarkButtonDirty(button)
end

-- Defensive no-op in case a provider retained a callback registration made
-- before this module loaded. Normal startup removes the registration above.
function Buttons:OnLABButtonUpdate(_, _button)
end
