local ROOT = arg[1] or "."

_G = _G or _ENV

local observeCalls = 0
local unbindCalls = 0
local dirtyCalls = 0

local item = {}
function item:GetBaseSpellID()
    return 15487
end

local active = { item }
local function EnumerateActive()
    local index = 0
    return function()
        index = index + 1
        return active[index]
    end
end

local record
local IG = {
    DB = { cdm = true },
    playerLoginSeen = true,
    ObservedButtons = {},
    Data = {
        GetCanonicalSpellID = function(_, spellID)
            if spellID == 15487 then return spellID end
        end,
    },
    Buttons = {},
}

function IG:RegisterModule() end
function IG:CanAccess() return true end
function IG:BumpStat() end
function IG:MarkAllButtonsDirty() dirtyCalls = dirtyCalls + 1 end
function IG:IsAddOnFullyLoaded() return false end

function IG.Buttons:ObserveButton(button, adapter)
    observeCalls = observeCalls + 1
    record = IG.ObservedButtons[button] or { button = button }
    record.adapter = adapter
    record.isInterrupt = true
    IG.ObservedButtons[button] = record
    return record
end

function IG.Buttons:UnbindRecord(current)
    unbindCalls = unbindCalls + 1
    current.isInterrupt = false
end

_G.InterruptGlow = IG
_G.EssentialCooldownViewer = {
    itemFramePool = { EnumerateActive = EnumerateActive },
}
_G.UtilityCooldownViewer = {
    itemFramePool = { EnumerateActive = function() return function() return nil end end },
}

local loader, loadError = loadfile(ROOT .. "/core/CDM.lua")
assert(loader, loadError)
loader()

local CDM = IG.CDM
assert(CDM, "CDM module did not load")
CDM.attached = true

CDM:ObserveExistingItems()
assert(record and record.isInterrupt == true, "active CDM interrupt was not observed")
assert(record.cdmCanonicalSpellID == 15487, "CDM identity was not cached")
assert(observeCalls == 1)

CDM:SetEnabled(false)
assert(record.isInterrupt == false, "CDM disable did not unbind the item")
assert(record.cdmCanonicalSpellID == nil, "CDM disable retained its dedupe identity")
assert(unbindCalls == 1)

IG.DB.cdm = true
CDM:SetEnabled(true)
assert(record.isInterrupt == true, "active pooled item did not rebind after CDM off/on")
assert(record.cdmCanonicalSpellID == 15487)
assert(observeCalls == 2, "re-enable was incorrectly suppressed as a duplicate")
assert(dirtyCalls == 1)

print("CDM TOGGLE TEST PASSED")
