local ROOT = arg[1] or "."

_G = _G or _ENV

local observeCalls = 0
local unbindCalls = 0
local recordDirtyCalls = 0
local allDirtyCalls = 0

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
function IG:MarkButtonDirty(button)
    assert(button == item)
    recordDirtyCalls = recordDirtyCalls + 1
end
function IG:MarkAllButtonsDirty() allDirtyCalls = allDirtyCalls + 1 end
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

local CDM = assert(IG.CDM, "CDM module did not load")
CDM.attached = true

CDM:ObserveExistingItems()
assert(record and record.isInterrupt == true, "active CDM interrupt was not observed")
assert(record.cdmCanonicalSpellID == 15487, "CDM identity was not cached")
assert(observeCalls == 1 and recordDirtyCalls == 1)

-- A Blizzard pool reset must not mutate visual/binding state synchronously from
-- the post-hook. It clears ordinary identity and queues one next-frame record.
CDM:ResetItem(item)
assert(record.cdmCanonicalSpellID == nil)
assert(record.isInterrupt == true, "pool reset unbound synchronously inside hook stack")
assert(unbindCalls == 0)
assert(recordDirtyCalls == 2)

-- Reuse before the next frame collapses onto the same dirty record and latest ID.
CDM:ObserveItem(item)
assert(record.cdmCanonicalSpellID == 15487)
assert(observeCalls == 1, "pool reuse allocated a duplicate record")
assert(recordDirtyCalls == 3)

CDM:SetEnabled(false)
assert(record.isInterrupt == false, "explicit CDM disable did not unbind the item")
assert(record.cdmCanonicalSpellID == nil)
assert(unbindCalls == 1)

IG.DB.cdm = true
CDM:SetEnabled(true)
assert(record.cdmCanonicalSpellID == 15487)
assert(record.isInterrupt == false, "CDM re-enable mutated binding before reconcile")
assert(recordDirtyCalls == 4)
assert(allDirtyCalls == 1)

print("CDM TOGGLE TEST PASSED")
