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

local function GetInterruptIdentity(itemFrame)
    local getBaseSpellID = itemFrame and itemFrame.GetBaseSpellID
    if type(getBaseSpellID) ~= "function" or not IG.Data then return nil end

    local ok, spellID = pcall(getBaseSpellID, itemFrame)
    if not ok or not IG.CanAccess(spellID) or type(spellID) ~= "number" then
        return nil
    end
    return IG.Data:GetCanonicalSpellID(spellID, "spell")
end

function CDM:ObserveItem(itemFrame)
    if not self.attached or not IG.playerLoginSeen or not IG.DB.cdm or not itemFrame or not IG.Buttons then return end

    -- CDM items have stable base-spell identity and no conditional-macro role.
    -- Do not allocate addon regions for unrelated Essential/Utility entries.
    local canonicalSpellID = GetInterruptIdentity(itemFrame)
    local record = IG.ObservedButtons[itemFrame]
    if not canonicalSpellID then
        if record and record.adapter == "cdm" then
            record.cdmCanonicalSpellID = nil
            IG.Buttons:UnbindRecord(record)
        end
        return
    end

    -- OnAcquireItemFrame and OnCooldownIDSet can both observe the same pool
    -- acquisition. Suppress the duplicate before it reaches the dirty queue.
    if record and record.adapter == "cdm" and record.cdmCanonicalSpellID == canonicalSpellID then
        return
    end

    record = IG.Buttons:ObserveButton(itemFrame, "cdm")
    if record then
        record.cdmCanonicalSpellID = canonicalSpellID
        IG:BumpStat("cdm.interruptItemsObserved")
    end
end

function CDM:ResetItem(itemFrame)
    local record = itemFrame and IG.ObservedButtons[itemFrame]
    if record and IG.Buttons then
        record.cdmCanonicalSpellID = nil
        IG.Buttons:UnbindRecord(record)
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
    local pool = viewer and viewer.itemFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then return end

    local ok, iterator, state, initial = pcall(pool.EnumerateActive, pool)
    if not ok or type(iterator) ~= "function" then return end

    for itemFrame in iterator, state, initial do
        CDM:ObserveItem(itemFrame)
    end
end

function CDM:ObserveExistingItems()
    if not IG.playerLoginSeen or not IG.DB.cdm then return end
    ObserveViewer(_G.EssentialCooldownViewer)
    ObserveViewer(_G.UtilityCooldownViewer)
end

function CDM:SetEnabled(enabled)
    if enabled then
        self:ObserveExistingItems()
        IG:MarkAllButtonsDirty()
        return
    end

    if not IG.Buttons then return end
    for _, record in pairs(IG.ObservedButtons) do
        if record.adapter == "cdm" then
            -- ObserveItem deduplicates acquire/set callbacks by this identity.
            -- Clear it when the feature is disabled so re-enabling can bind the
            -- still-active pooled item immediately without waiting for pool reuse.
            record.cdmCanonicalSpellID = nil
            IG.Buttons:UnbindRecord(record)
        end
    end
end

function CDM:AttachNow(discoverExisting)
    if self.hooksInstalled then
        if discoverExisting then self:ObserveExistingItems() end
        return
    end

    local viewerMixin = _G.CooldownViewerMixin
    local itemDataMixin = _G.CooldownViewerItemDataMixin
    if not viewerMixin or not itemDataMixin or type(hooksecurefunc) ~= "function" then
        return
    end

    if type(viewerMixin.OnAcquireItemFrame) == "function" then
        hooksecurefunc(viewerMixin, "OnAcquireItemFrame", OnAcquireItemFrame)
    end
    if type(itemDataMixin.OnCooldownIDSet) == "function" then
        hooksecurefunc(itemDataMixin, "OnCooldownIDSet", OnCooldownIDSet)
    end
    if type(itemDataMixin.ResetCooldownData) == "function" then
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
    elseif EventUtil and type(EventUtil.ContinueOnAddOnLoaded) == "function" then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_CooldownViewer", function()
            if CDM.attached then CDM:AttachNow(IG.playerLoginSeen) end
        end)
    end
end

function CDM:Detach()
    if not self.attached then return end
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
