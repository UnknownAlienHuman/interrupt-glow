local ROOT = arg[1] or "."

_G = _G or _ENV

local allowed = true
local refreshCalls = 0
local observeCalls = 0
local frameReads = 0

InterruptGlow = {
    DB = { cdm = true },
    modules = {},
    Buttons = {},
    Data = {},
    CDM = { attached = true },
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end

function InterruptGlow.Data:GetCanonicalSpellID(spellID, sourceKind)
    assert(sourceKind == "spell")
    if allowed and spellID == 15487 then return 15487 end
end

function InterruptGlow.Data:RefreshActiveSpec()
    refreshCalls = refreshCalls + 1
    return 258, refreshCalls == 1
end

function InterruptGlow.CDM:ObserveExistingItems()
    observeCalls = observeCalls + 1
end

local record = {
    adapter = "cdm",
    cdmCanonicalSpellID = 15487,
    button = {
        GetBaseSpellID = function()
            frameReads = frameReads + 1
            return 999999
        end,
    },
}

local loader, loadError = loadfile(ROOT .. "/core/CDMPolicy.lua")
assert(loader, loadError)
loader()

local isInterrupt, sourceKind, sourceID, spellID, canonicalSpellID =
    InterruptGlow.Buttons:ResolveCDM(record)
assert(isInterrupt == true)
assert(sourceKind == "spell")
assert(sourceID == 15487 and spellID == 15487 and canonicalSpellID == 15487)
assert(frameReads == 0, "reconcile re-read a pooled frame instead of captured identity")

allowed = false
assert(InterruptGlow.Buttons:ResolveCDM(record) == false, "cached CDM identity crossed spec policy")
allowed = true

-- CDMPolicy must not wrap the spec refresh itself. RuntimeInterruptPolicy owns
-- the single correctly ordered action-seed -> active-pool -> secondary pass.
local specID, changed = InterruptGlow.Data:RefreshActiveSpec()
assert(specID == 258 and changed == true)
assert(refreshCalls == 1 and observeCalls == 0,
    "CDMPolicy performed a duplicate pre-action pool refresh")

InterruptGlow.DB.cdm = false
assert(InterruptGlow.Buttons:ResolveCDM(record) == false)

local policy = assert(InterruptGlow.modules.CDMPolicy)
assert(policy.usesCapturedPoolIdentity == true)
assert(policy.specRefreshOwnedByRuntimeInterruptPolicy == true)

print("CDM POLICY TEST PASSED")
