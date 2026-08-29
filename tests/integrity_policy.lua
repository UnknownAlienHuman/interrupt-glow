local ROOT = arg[1] or "."

_G = _G or _ENV

local secret = {}
local stats = {}
local dirty = 0
local originalResolveCalls = 0
local fontCreateCalls = 0

InterruptGlow = {
    modules = { RuntimeSleepPolicy = {} },
    DB = { enabled = true, cdText = true, cdm = true },
    testMode = false,
    playerLoginSeen = true,
    ObservedButtons = setmetatable({}, { __mode = "k" }),
    CastState = {
        target = { active = false, hostile = false, niState = "none" },
        focus = { active = false, hostile = false, niState = "none" },
    },
    Data = {
        runtimeInterrupts = {},
        negativeCooldownSpellMatches = {},
        negativeCooldownSpellMatchCount = 0,
    },
    Buttons = {},
    Glow = {},
    CDM = { attached = true },
    CastTracking = { channelSuppressed = { target = false, focus = false } },
}

local IG = InterruptGlow

function IG:RegisterModule(name, module) self.modules[name] = module end
function IG.CanAccess(value) return value ~= secret end
function IG:ReadMember(object, key)
    if not self.CanAccess(object) or object == nil then return nil, false end
    local ok, value = pcall(function() return object[key] end)
    if not ok or not self.CanAccess(value) then return nil, false end
    return value, true
end
function IG:BumpStat(key, amount) stats[key] = (stats[key] or 0) + (amount or 1) end
function IG:MarkButtonDirty() dirty = dirty + 1 end
function IG:IsInCombat() return false end

function IG.Data:GetCanonicalSpellID(spellID)
    return spellID + 1000
end
function IG.Data:MatchesCurrentInterrupt(spellID)
    if spellID == 10 then
        self.negativeCooldownSpellMatches[spellID] = nil
        return true
    end
    return false
end

function IG.Buttons:ResolveRecord()
    originalResolveCalls = originalResolveCalls + 1
    return "original"
end
function IG.Buttons:ResolveButtonForge() return false end
function IG.Buttons:UnbindRecord(record)
    record.ready = false
end
function IG.Buttons:AttachRecordToAbility(record)
    local ability = {
        hardRestricted = true,
        readinessPending = true,
    }
    record.ability = ability
    return ability
end
function IG.Buttons:ObserveButton(button, adapter)
    local record = { button = button, adapter = adapter }
    IG.ObservedButtons[button] = record
    return record
end

function IG.Glow:EnsureCooldownText() error("unsafe base implementation used") end
function IG.Glow:ApplyUnitInterruptibility() end
function IG.Glow:RefreshUnit() end
function IG.Glow:SetRuntimeWorkerEnabled() end

function IG.CDM:ObserveItem() error("unsafe base CDM observer used") end

C_SpellBook = nil

local loader, loadError = loadfile(ROOT .. "/core/IntegrityPolicy.lua")
assert(loader, loadError)
loader()

-- Missing spellbook contract: static direct-spell proof fails closed, native
-- action proof stays authoritative, and a runtime-proven family remains usable.
assert(IG.Data:GetCanonicalSpellID(5, "spell") == nil)
assert(IG.Data:GetCanonicalSpellID(5, "pet") == nil)
assert(IG.Data:GetCanonicalSpellID(5, "action") == 1005)
IG.Data.runtimeInterrupts[5] = 42
assert(IG.Data:GetCanonicalSpellID(5, "spell") == 42)
assert((stats["data.spellBookContractUnavailable"] or 0) >= 2)

C_SpellBook = { IsSpellKnownOrInSpellBook = function() return true end }
assert(IG.Data:GetCanonicalSpellID(5, "spell") == 1005)

-- A newly positive negative-cache key decrements the parallel count exactly
-- once when the wrapped implementation forgot to do it.
IG.Data.negativeCooldownSpellMatches[10] = true
IG.Data.negativeCooldownSpellMatchCount = 1
assert(IG.Data:MatchesCurrentInterrupt(10) == true)
assert(IG.Data.negativeCooldownSpellMatchCount == 0)

-- Action-backed records retain the existing optimized resolver.
local actionRecord = { button = { action = 7 }, adapter = "native" }
assert(IG.Buttons:ResolveRecord(actionRecord) == "original")
assert(originalResolveCalls == 1)

-- No-slot direct spell methods are protected and fail closed on errors.
local throwingRecord = {
    adapter = "lab",
    button = { GetSpellId = function() error("foreign method failed") end },
}
assert(IG.Buttons:ResolveRecord(throwingRecord) == false)
assert(originalResolveCalls == 1)

local directRecord = {
    adapter = "lab",
    button = { GetSpellId = function() return 5 end },
}
local isInterrupt, sourceKind, sourceID, spellID, canonicalSpellID =
    IG.Buttons:ResolveRecord(directRecord)
assert(isInterrupt == true)
assert(sourceKind == "spell" and sourceID == 1005)
assert(spellID == 5 and canonicalSpellID == 1005)

-- ButtonForge ordinary object identity remains supported without unsafe frame
-- method access.
local bfRecord = {
    adapter = "buttonforge",
    button = {},
    buttonForgeObject = { Mode = "spell", SpellId = 5 },
}
local bfInterrupt, bfKind, bfSource, bfSpell, bfCanonical =
    IG.Buttons:ResolveButtonForge(bfRecord)
assert(bfInterrupt == true and bfKind == "spell")
assert(bfSource == 1005 and bfSpell == 5 and bfCanonical == 1005)

-- Normalized restriction fields cannot leak across unbind/rebind diagnostics.
local record = { hardRestrictedCooldown = true, readinessPending = true }
IG.Buttons:UnbindRecord(record)
assert(record.hardRestrictedCooldown == false)
assert(record.readinessPending == false)
local ability = IG.Buttons:AttachRecordToAbility(record, 5, "spell", 5)
assert(record.hardRestrictedCooldown == ability.hardRestricted)
assert(record.readinessPending == ability.readinessPending)

-- A foreign owner whose font creation method errors is rejected once and is not
-- retried every countdown frame.
local badTextRecord = {
    overlay = {},
    button = {
        CreateFontString = function()
            fontCreateCalls = fontCreateCalls + 1
            error("font owner rejected")
        end,
    },
}
assert(IG.Glow:EnsureCooldownText(badTextRecord) == nil)
assert(badTextRecord.cooldownTextForbidden == true)
assert(fontCreateCalls == 1)
assert(IG.Glow:EnsureCooldownText(badTextRecord) == nil)
assert(fontCreateCalls == 1)

-- CDM pool identity errors clear a stale ordinary identity and enqueue one
-- fail-closed reconcile instead of escaping through a foreign method call.
local cdmButton = { GetBaseSpellID = function() error("pooled frame unavailable") end }
IG.ObservedButtons[cdmButton] = {
    button = cdmButton,
    adapter = "cdm",
    cdmCanonicalSpellID = 1005,
}
local dirtyBefore = dirty
IG.CDM:ObserveItem(cdmButton)
assert(IG.ObservedButtons[cdmButton].cdmCanonicalSpellID == nil)
assert(dirty == dirtyBefore + 1)
assert((stats["cdm.identityRestricted"] or 0) == 1)

local policy = assert(IG.modules.IntegrityPolicy)
assert(policy.spellBookContractFailsClosed == true)
assert(policy.foreignDirectSpellMethodsAreGated == true)
assert(policy.cdmIdentityMethodsAreGated == true)
assert(policy.cooldownTextOwnerIsGated == true)
assert(policy.negativeCacheCountIsRepaired == true)

print("INTEGRITY POLICY TEST PASSED")
