local ROOT = arg[1] or "."

_G = _G or _ENV

local frame
local cooldownDirtyCalls = 0
local canonicalCalls = 0
local lastSourceKind = nil
local secretUnit = {}
local secretSpell = {}

InterruptGlow = {
    DB = { debug = false },
    modules = {},
    Data = {},
    Buttons = {},
    CastTracking = {},
    CDM = {},
    Glow = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:NeedsReadinessRuntime() return true end
function InterruptGlow.CanAccess(value)
    return value ~= secretUnit and value ~= secretSpell
end
function InterruptGlow:MarkCooldownDirty()
    cooldownDirtyCalls = cooldownDirtyCalls + 1
end
function InterruptGlow:MarkCastDirty() end
function InterruptGlow:MarkSpecDirty() end
function InterruptGlow:MarkAllButtonsDirty() end
function InterruptGlow:BumpStat() end
function InterruptGlow.Data:RefreshActiveSpec() end
function InterruptGlow.Data:ShouldRefreshForCooldownEvent() return false end
function InterruptGlow.Data:GetCanonicalSpellID(spellID, sourceKind)
    canonicalCalls = canonicalCalls + 1
    lastSourceKind = sourceKind
    if spellID == 15487 or spellID == 19647 then return spellID end
end
function InterruptGlow.Buttons:Attach() end
function InterruptGlow.Buttons:RefreshPetButtons() end
function InterruptGlow.CastTracking:Attach() end
function InterruptGlow.CastTracking:ResetAllIdentities() end
function InterruptGlow.CastTracking:ResetUnitIdentity() end
function InterruptGlow.CDM:Attach() end
function InterruptGlow.Glow:CreatePendingOverlays() end
function InterruptGlow.Glow:RefreshUnitRelation() end
function InterruptGlow.Glow:RefreshUnit() end

function CreateFrame()
    frame = { scripts = {} }
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:RegisterUnitEvent() end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    return frame
end

EventUtil = {
    ContinueOnPlayerLogin = function(callback) callback() end,
}
function IsLoggedIn() return true end

local loader, loadError = loadfile(ROOT .. "/core/Events.lua")
assert(loader, loadError)
loader()

local initialDirty = cooldownDirtyCalls
assert(InterruptGlow.runtimeInitialized == true)

-- Both unit and spellID may be inaccessible under the event's
-- SecretWhenUnitSpellCastRestricted contract. The handler must not compare or
-- classify either value; it performs one bounded fail-closed invalidation.
frame.scripts.OnEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", secretUnit, {}, secretSpell, 1)
assert(cooldownDirtyCalls == initialDirty + 1)
assert(canonicalCalls == 0, "restricted spell payload reached canonical classification")

-- Accessible ordinary player and pet events still use precise filtering.
frame.scripts.OnEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 999999, 2)
assert(cooldownDirtyCalls == initialDirty + 1)
assert(canonicalCalls == 1 and lastSourceKind == "spell")

frame.scripts.OnEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 15487, 3)
assert(cooldownDirtyCalls == initialDirty + 2)
assert(lastSourceKind == "spell")

frame.scripts.OnEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "pet", "guid", 19647, 4)
assert(cooldownDirtyCalls == initialDirty + 3)
assert(lastSourceKind == "pet")

print("RESTRICTED SPELL SUCCESS TEST PASSED")
