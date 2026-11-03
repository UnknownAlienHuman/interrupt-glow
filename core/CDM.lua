local IG = _G.InterruptGlow
if not IG then return end

local CDM = {
    attached = false,
    hooksInstalled = false,
}
IG.CDM = CDM
IG:RegisterModule("CDM", CDM)

local _G = _G
local EventUtil = _G.EventUtil
local hooksecurefunc = _G.hooksecurefunc
local type = type
local pcall = pcall
local pairs = pairs

local function SafeMethod(object, methodName)
    if not IG.CanAccess(object) or object == nil then return nil end
    local method, known = IG:ReadMember(object, methodName)
    if not known or type(method) ~= "function" then return nil end
    return method
end

local function ReadMember(object, memberName)
    if not IG.CanAccess(object) or object == nil then return nil, false end
    return IG:ReadMember(object, memberName)
end

local function SafeMethodCall(object, methodName, ...)
    local method = SafeMethod(object, methodName)
    if not method then return false, nil end
    local ok, value = pcall(method, object, ...)
    if not ok or not IG.CanAccess(value) then return false, nil end
    return true, value
end

local function GetInterruptIdentity(itemFrame)
    if not IG.CanAccess(itemFrame) or itemFrame == nil or not IG.Data then return nil end
    local ok, spellID = SafeMethodCall(itemFrame, "GetBaseSpellID")
    if not ok or not IG.CanAccess(spellID) or type(spellID) ~= "number" then
        return nil
    end
    return IG.Data:GetCanonicalSpellID(spellID, "spell")
end

local function QueueIdentityChange(itemFrame, canonicalSpellID)
    if not IG.CanAccess(itemFrame) or itemFrame == nil then return false end
    local record = itemFrame and IG.ObservedButtons[itemFrame]
    if not record or record.adapter ~= "cdm" then return false end
    if record.cdmCanonicalSpellID == canonicalSpellID then return false end

    record.cdmCanonicalSpellID = canonicalSpellID
    IG:MarkButtonDirty(itemFrame)
    return true
end

function CDM:ObserveItem(itemFrame)
    if not self.attached or not IG.playerLoginSeen or not IG.DB.cdm
        or not IG.CanAccess(itemFrame) or itemFrame == nil or not IG.Buttons
    then
        return
    end

    -- Pool hooks may run inside Blizzard layout/reset stacks. They update only
    -- ordinary identity and queue one record; visual/canonical reconciliation is
    -- performed by the addon-owned next-frame dirty worker.
    local canonicalSpellID = GetInterruptIdentity(itemFrame)
    local record = IG.ObservedButtons[itemFrame]
    if not canonicalSpellID then
        if QueueIdentityChange(itemFrame, nil) then
            IG:BumpStat("cdm.identityCleared")
        end
        return
    end

    if record and record.adapter == "cdm" then
        if QueueIdentityChange(itemFrame, canonicalSpellID) then
            IG:BumpStat("cdm.identityChanged")
        end
        return
    end

    record = IG.Buttons:ObserveButton(itemFrame, "cdm", { skipDirty = true })
    if record then
        record.cdmCanonicalSpellID = canonicalSpellID
        IG:MarkButtonDirty(itemFrame)
        IG:BumpStat("cdm.interruptItemsObserved")
    end
end

function CDM:ResetItem(itemFrame)
    if not IG.CanAccess(itemFrame) or itemFrame == nil then return end
    if QueueIdentityChange(itemFrame, nil) then
        IG:BumpStat("cdm.itemsReset")
    end
end

local function OnAcquireItemFrame(_viewer, itemFrame)
    CDM:ObserveItem(itemFrame)
end

local function OnCooldownIDSet(itemFrame)
    CDM:ObserveItem(itemFrame)
end

local function OnCooldownDataReset(itemFrame)
    if CDM.attached then CDM:ResetItem(itemFrame) end
end

local function ObserveViewer(viewer)
    if not IG.CanAccess(viewer) or viewer == nil then return end
    local pool, poolKnown = ReadMember(viewer, "itemFramePool")
    if not poolKnown or not IG.CanAccess(pool) or pool == nil then return end
    local enumerateActive = SafeMethod(pool, "EnumerateActive")
    if not enumerateActive then return end

    local ok, iterator, state, initial = pcall(enumerateActive, pool)
    if not ok or not IG.CanAccess(iterator) or not IG.CanAccess(state) or not IG.CanAccess(initial)
        or type(iterator) ~= "function"
    then
        return
    end

    for itemFrame in iterator, state, initial do
        CDM:ObserveItem(itemFrame)
    end
end

function CDM:ObserveExistingItems()
    if not self.attached or not IG.playerLoginSeen or not IG.DB.cdm then return end
    ObserveViewer(_G.EssentialCooldownViewer)
    ObserveViewer(_G.UtilityCooldownViewer)
end

function CDM:SetEnabled(enabled)
    if enabled then
        if self.attached then
            self:ObserveExistingItems()
            IG:MarkAllButtonsDirty()
        else
            self:Attach(true)
        end
        return
    end
    self:Detach()
end

function CDM:AttachNow(discoverExisting)
    if self.hooksInstalled then
        if discoverExisting then self:ObserveExistingItems() end
        return
    end

    local viewerMixin = _G.CooldownViewerMixin
    local itemDataMixin = _G.CooldownViewerItemDataMixin
    if not IG.CanAccess(viewerMixin) or not IG.CanAccess(itemDataMixin)
        or not viewerMixin or not itemDataMixin or type(hooksecurefunc) ~= "function"
    then
        return
    end

    if SafeMethod(viewerMixin, "OnAcquireItemFrame") then
        hooksecurefunc(viewerMixin, "OnAcquireItemFrame", OnAcquireItemFrame)
    end
    if SafeMethod(itemDataMixin, "OnCooldownIDSet") then
        hooksecurefunc(itemDataMixin, "OnCooldownIDSet", OnCooldownIDSet)
    end
    if SafeMethod(itemDataMixin, "ResetCooldownData") then
        hooksecurefunc(itemDataMixin, "ResetCooldownData", OnCooldownDataReset)
    end

    self.hooksInstalled = true
    if discoverExisting then self:ObserveExistingItems() end
end

function CDM:Attach(discoverExisting)
    if self.attached then return end
    self.attached = true

    if IG:IsAddOnFullyLoaded("Blizzard_CooldownViewer") then
        self:AttachNow(discoverExisting == true)
    elseif not self.loadPending and EventUtil and type(EventUtil.ContinueOnAddOnLoaded) == "function" then
        self.loadPending = true
        EventUtil.ContinueOnAddOnLoaded("Blizzard_CooldownViewer", function()
            CDM.loadPending = false
            if CDM.attached then CDM:AttachNow(IG.playerLoginSeen) end
        end)
    end
end

function CDM:Detach()
    self.attached = false

    if IG.Buttons then
        for _, record in pairs(IG.ObservedButtons) do
            if record.adapter == "cdm" then
                record.cdmCanonicalSpellID = nil
                IG.Buttons:UnbindRecord(record)
            end
        end
    end
end
