local ROOT = arg[1] or "."
_G = _G or _ENV
local unpackValues = (table and table.unpack) or unpack

local now = 100
local loggedIn = false
local combat = false
local currentSpecID = 258
local frameCount = 0
local textureCount = 0
local fontCount = 0
local animationCount = 0
local castingInfoCalls = 0
local channelInfoCalls = 0
local actionCooldownCalls = 0
local actionDurationCalls = 0
local secretAlphaCalls = 0

local actionData = {
    [1] = { actionType = "spell", id = 15487, interrupt = true },
    [2] = { actionType = "spell", id = 15487, interrupt = true },
    [3] = { actionType = "spell", id = 2061, interrupt = false },
}
local actionCharges = {}
local cooldownData = {
    zero = true,
    remaining = 0,
    secret = false,
    active = false,
    onGCD = false,
    infoSecret = false,
}
local actionLoC = { active = false, replaces = false, secret = false }
local spellLoC = { active = false, replaces = false }
local castData = {
    active = true,
    channel = false,
    notInterruptible = false,
    castBarID = 10,
}

local function secretBoolean(value)
    return { __secretBoolean = true, value = value == true }
end

function canaccessvalue(value)
    return not (type(value) == "table" and (value.__secretBoolean or value.__secret))
end
function GetTime() return now end
function InCombatLockdown() return combat end
function IsLoggedIn() return loggedIn end
function UnitExists(unit) return unit == "target" or unit == "focus" end
function UnitCanAttack(_, unit) return unit == "target" end
function UnitIsDeadOrGhost(_) return false end
function UnitIsUnit(_, _) return false end
function UnitCastingInfo(unit)
    castingInfoCalls = castingInfoCalls + 1
    if unit == "target" and castData.active and not castData.channel then
        return "Spell", "Spell", 1, 100000, 102000, false, "cast", castData.notInterruptible, 123, castData.castBarID, 0
    end
end
function UnitChannelInfo(unit)
    channelInfoCalls = channelInfoCalls + 1
    if unit == "target" and castData.active and castData.channel then
        return "Channel", "Channel", 1, 100000, 102000, false, castData.notInterruptible, 123, false, 0, castData.castBarID
    end
end
function GetActionInfo(slot)
    local data = actionData[slot]
    if not data then return nil end
    return data.actionType, data.id, data.subType
end
function GetPetActionInfo(slot)
    if slot == 1 then return "Spell Lock", nil, false, false, false, false, 19647 end
end
function GetPetActionCooldown(_) return 0, 0, 1 end

PlayerUtil = { GetCurrentSpecID = function() return currentSpecID end }
C_SpellBook = {
    IsSpellKnownOrInSpellBook = function(_) return true end,
    FindBaseSpellByID = function(id) return id end,
    FindSpellOverrideByID = function(id) return id end,
}

local Duration = {}
Duration.__index = Duration
function Duration:HasSecretValues() return cooldownData.secret end
function Duration:IsZero() return cooldownData.zero end
function Duration:GetRemainingDuration() return cooldownData.remaining end

local ChargeDuration = {}
ChargeDuration.__index = ChargeDuration
function ChargeDuration:HasSecretValues() return self.data.secret == true end
function ChargeDuration:IsZero() return self.data.zero == true end
function ChargeDuration:GetRemainingDuration() return self.data.remaining or 0 end

C_ActionBar = {
    IsInterruptAction = function(slot)
        local data = actionData[slot]
        return data and data.interrupt == true or false
    end,
    IsAssistedCombatAction = function(slot)
        local data = actionData[slot]
        return data and data.subType == "assistedcombat" or false
    end,
    GetSpell = function(slot)
        local data = actionData[slot]
        return data and data.id or nil
    end,
    GetActionCharges = function(slot)
        local data = actionCharges[slot]
        if not data then return nil end
        return { currentCharges = data.current, maxCharges = data.max, isActive = data.active }
    end,
    GetActionChargeDuration = function(slot)
        local data = actionCharges[slot]
        if not data then return nil end
        return setmetatable({ data = data }, ChargeDuration)
    end,
    GetActionCooldownDuration = function(_, _)
        actionDurationCalls = actionDurationCalls + 1
        return setmetatable({}, Duration)
    end,
    GetActionCooldown = function(_)
        actionCooldownCalls = actionCooldownCalls + 1
        if cooldownData.infoSecret then return { __secret = true } end
        return { isEnabled = true, isActive = cooldownData.active, isOnGCD = cooldownData.onGCD }
    end,
    GetActionLossOfControlCooldownInfo = function(_)
        if actionLoC.secret then return { __secret = true } end
        return { isActive = actionLoC.active, shouldReplaceNormalCooldown = actionLoC.replaces }
    end,
}
C_Spell = {
    GetSpellCharges = function(_) return nil end,
    GetSpellChargeDuration = function(_) return nil end,
    GetSpellCooldownDuration = function(_, _) return setmetatable({}, Duration) end,
    GetSpellCooldown = C_ActionBar.GetActionCooldown,
    GetSpellLossOfControlCooldownInfo = function(_)
        return { isActive = spellLoC.active, shouldReplaceNormalCooldown = spellLoC.replaces }
    end,
}

local loaded = { Dominos = true, ButtonForge = false, Blizzard_CooldownViewer = false }
local loading = {}
C_AddOns = {
    IsAddOnLoaded = function(name)
        return loaded[name] == true or loading[name] == true, loaded[name] == true
    end,
    GetAddOnMetadata = function(_, key)
        if key == "Version" then return "1.1.0-beta.2" end
    end,
}

Enum = {
    AddOnProfilerMetric = {
        RecentAverageTime = 1,
        EncounterAverageTime = 2,
        LastTime = 3,
        PeakTime = 4,
        CountTimeOver1Ms = 5,
        CountTimeOver5Ms = 6,
        CountTimeOver10Ms = 7,
        CountTimeOver50Ms = 8,
    },
}
C_AddOnProfiler = { GetAddOnMetric = function() return 0 end }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, _) end }
SlashCmdList = {}
UIParent = {}
ChatFontNormal = {}
NumberFontNormalLarge = {}
Settings = nil
InterfaceOptions_AddCategory = function(_) end

local function newRegion(parent)
    local region = {
        parent = parent,
        alpha = 0,
        shown = true,
        text = "",
        r = 0,
        g = 0,
        b = 0,
        scripts = {},
    }
    function region:SetAlpha(value) self.alpha = value end
    function region:SetAlphaFromBoolean(value, alphaTrue, alphaFalse)
        secretAlphaCalls = secretAlphaCalls + 1
        local actual = value
        if type(value) == "table" and value.__secretBoolean then actual = value.value end
        self.alpha = actual and alphaTrue or alphaFalse
    end
    function region:GetAlpha() return self.alpha end
    function region:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end
    function region:SetPoint(...) end
    function region:SetAllPoints(...) end
    function region:ClearAllPoints() end
    function region:SetBlendMode(_) end
    function region:SetTexture(_) end
    function region:SetAtlas(_, _) end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetShown(value) self.shown = value == true end
    function region:IsShown() return self.shown end
    function region:SetText(value) self.text = value end
    function region:SetJustifyH(_) end
    function region:SetWidth(_) end
    function region:SetHeight(_) end
    function region:SetSize(_, _) end
    function region:SetTextInsets(...) end
    function region:SetMultiLine(_) end
    function region:SetAutoFocus(_) end
    function region:SetFontObject(_) end
    function region:HighlightText(...) end
    function region:SetScript(name, fn) self.scripts[name] = fn end
    function region:SetChecked(value) self.checked = value == true end
    function region:GetChecked() return self.checked == true end
    function region:SetScrollChild(value) self.scrollChild = value end
    function region:GetParent() return self.parent end
    function region:CreateAnimationGroup()
        animationCount = animationCount + 1
        local group = { playing = false }
        function group:SetLooping(_) end
        function group:CreateAnimation(_)
            local anim = {}
            function anim:SetDuration(_) end
            function anim:SetScale(_, _) end
            function anim:SetSmoothing(_) end
            return anim
        end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        return group
    end
    return region
end

local allFrames = {}
function CreateFrame(_, name, parent, template)
    frameCount = frameCount + 1
    local frame = newRegion(parent)
    frame.name = name
    if name then _G[name] = frame end
    frame.events = {}
    frame.unitEvents = {}
    frame.frameLevel = 1
    allFrames[#allFrames + 1] = frame
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {}; self.unitEvents = {} end
    function frame:SetFrameStrata(_) end
    function frame:SetFrameLevel(value) self.frameLevel = value end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:GetName() return self.name end
    function frame:IsForbidden() return false end
    function frame:CreateTexture(...)
        textureCount = textureCount + 1
        return newRegion(self)
    end
    function frame:CreateFontString(...)
        fontCount = fontCount + 1
        return newRegion(self)
    end
    if template == "InterfaceOptionsCheckButtonTemplate" then frame.Text = newRegion(frame) end
    if template == "BasicFrameTemplateWithInset" then frame.TitleText = newRegion(frame) end
    return frame
end

EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(event, fn, owner)
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], { fn = fn, owner = owner })
end
function EventRegistry:UnregisterCallback(event, owner)
    local list = self.callbacks[event] or {}
    for index = #list, 1, -1 do if list[index].owner == owner then table.remove(list, index) end end
end
function EventRegistry:TriggerEvent(event, ...)
    for _, entry in ipairs(self.callbacks[event] or {}) do entry.fn(entry.owner, ...) end
end

local loginCallback
local addonCallbacks = {}
EventUtil = {
    ContinueOnPlayerLogin = function(callback)
        if loggedIn then callback() else loginCallback = callback end
    end,
    ContinueOnAddOnLoaded = function(name, callback)
        if loaded[name] then callback() else addonCallbacks[name] = callback end
    end,
}

function hooksecurefunc(target, methodName, hook)
    local old = target[methodName]
    target[methodName] = function(...)
        local results = { old(...) }
        hook(...)
        return unpackValues(results)
    end
end

local LAB = { buttonRegistry = {}, callbacks = {} }
function LAB.RegisterCallback(owner, event, method)
    LAB.callbacks[event] = LAB.callbacks[event] or {}
    LAB.callbacks[event][owner] = method
end
function LAB.UnregisterCallback(owner, event)
    if LAB.callbacks[event] then LAB.callbacks[event][owner] = nil end
end
function LAB:GetAllButtons() return self.buttonRegistry end
function LAB:Fire(event, button)
    for owner, method in pairs(self.callbacks[event] or {}) do owner[method](owner, event, button) end
end

local DominosActionButtons = { buttons = {} }
function DominosActionButtons:OnActionChanged(_, _) end
function DominosActionButtons:ACTIONBAR_SLOT_CHANGED(_) end
local DominosAddon = { ActionButtons = DominosActionButtons }
local AceAddon = {}
function AceAddon:GetAddon(name, silent)
    if name == "Dominos" then return DominosAddon end
    if not silent then error("missing") end
end
LibStub = { libraries = { ["LibActionButton-1.0"] = LAB, ["AceAddon-3.0"] = AceAddon } }
function LibStub:GetLibrary(name, silent)
    local value = self.libraries[name]
    if value then return value end
    if not silent then error("missing") end
end
function LibStub:IterateLibraries() return pairs(self.libraries) end

local native1 = CreateFrame("Button", "ActionButton1", UIParent)
native1.action = 1
local native2 = CreateFrame("Button", "ActionButton2", UIParent)
native2.action = 2
local ordinary = CreateFrame("Button", "ActionButton3", UIParent)
ordinary.action = 3
ActionBarButtonEventsFrame = { frames = { native1, native2, ordinary } }
function ActionBarButtonEventsFrame:ForEachFrame(fn)
    for _, button in ipairs(self.frames) do fn(button) end
end

local labButton = CreateFrame("Button", "LABButton1", UIParent)
labButton._state_type = "action"
labButton._state_action = 2
LAB.buttonRegistry[labButton] = true

local dominosButton = CreateFrame("Button", "DominosActionButton1", UIParent)
dominosButton.action = 1
DominosActionButtons.buttons[dominosButton] = 1

PetActionBar = { actionButtons = {} }
for slot = 1, 10 do PetActionBar.actionButtons[slot] = CreateFrame("Button", "PetActionButton" .. slot, UIParent) end

local addonTable = {}
local files = {
    "Core.lua",
    "core/Shared.lua",
    "core/Data.lua",
    "core/Debug.lua",
    "core/Glow.lua",
    "core/Buttons.lua",
    "core/Cooldown.lua",
    "core/CastTracking.lua",
    "core/CDM.lua",
    "core/Events.lua",
    "core/Slash.lua",
    "Options.lua",
}
for _, path in ipairs(files) do
    local fn, err = loadfile(ROOT .. "/" .. path)
    assert(fn, err)
    fn("InterruptGlow", addonTable)
end
local IG = _G.InterruptGlow
assert(IG == addonTable, "addon namespace mismatch")

local function flush_all()
    for _ = 1, 40 do
        if not IG.flushFrame.shown and not IG:HasDirtyWork() then return end
        local fn = IG.flushFrame.scripts.OnUpdate
        assert(fn, "missing flush OnUpdate")
        fn(IG.flushFrame, 0.016)
    end
    error("flush did not settle")
end

local function pump_prewarm()
    for _ = 1, 100 do
        if not IG.Glow.prewarmFrame.shown then return end
        IG.Glow.prewarmFrame.scripts.OnUpdate(IG.Glow.prewarmFrame, 0.016)
    end
    error("prewarm did not settle")
end

local function fire(event, ...)
    local handler = IG.EventFrame.scripts.OnEvent
    assert(handler, "event handler missing")
    handler(IG.EventFrame, event, ...)
end

assert(IG:IsAddOnFullyLoaded("Dominos") == true)
loading.ButtonForge = true
assert(IG:IsAddOnFullyLoaded("ButtonForge") == false, "loading is not fully loaded")
loading.ButtonForge = nil
assert(loginCallback, "runtime did not defer to PLAYER_LOGIN")
assert(not IG.EventFrame.events.PLAYER_ENTERING_WORLD, "runtime events were registered before PLAYER_LOGIN")
assert((IG.Stats["startup.discoveryPasses"] or 0) == 0)
assert(IG.Options.built == false and fontCount == 0, "options must be lazy")

loggedIn = true
loginCallback()
flush_all()
pump_prewarm()
flush_all()
assert(IG.runtimeInitialized == true)
assert(IG.EventFrame.events.PLAYER_ENTERING_WORLD == true, "runtime events were not registered at PLAYER_LOGIN")
assert(IG.Stats["startup.discoveryPasses"] == 1, "startup discovery must run exactly once")

local record1 = assert(IG.ObservedButtons[native1])
local record2 = assert(IG.ObservedButtons[native2])
local ordinaryRecord = assert(IG.ObservedButtons[ordinary])
local labRecord = assert(IG.ObservedButtons[labButton])
local dominosRecord = assert(IG.ObservedButtons[dominosButton])
assert(record1.isInterrupt and record2.isInterrupt and labRecord.isInterrupt and dominosRecord.isInterrupt)
assert(record1.ability == record2.ability and record1.ability == labRecord.ability and record1.ability == dominosRecord.ability)
assert(record1.ready == true and record2.ready == true, "initial readiness cache is broken")
assert(record1.overlay and record1.overlay.enhanced == true)
assert(ordinaryRecord.overlay and ordinaryRecord.overlay.enhanced == false, "ordinary shell must stay lightweight")
assert(fontCount == 0, "cooldown text and options UI must not be allocated at login")

assert(IG.Data.activeSpecID == 258)
assert(IG.Data:IsInterruptSpell(15487, "spell") == true)
assert(IG.Data:IsInterruptSpell(6552, "spell") == false)
assert(IG.Data:IsInterruptSpell(115781, "spell") == false, "removed Optical Blast must not return")
assert(IG.Data:IsInterruptSpell(212619, "spell") == false, "removed Call Felhunter must not return")
currentSpecID = 257
IG.Data:RefreshActiveSpec()
assert(next(IG.Data.activeInterrupts) == nil, "Holy Priest must not inherit Shadow Silence")
currentSpecID = 265
IG.Data:RefreshActiveSpec()
assert(IG.Data:GetCanonicalSpellID(19647, "pet") == 119910)
assert(IG.Data:GetCanonicalSpellID(89766, "pet") == nil)
currentSpecID = 266
IG.Data:RefreshActiveSpec()
assert(IG.Data:GetCanonicalSpellID(89766, "pet") == 119914)
currentSpecID = 73
IG.Data:RefreshActiveSpec()
assert(IG.Data:IsInterruptSpell(6552, "spell") == true)
assert(IG.Data:IsInterruptSpell(386071, "spell") == true)
currentSpecID = 258
IG.Data:RefreshActiveSpec()
IG:MarkAllButtonsDirty()
flush_all()

assert(IG.CastState.target.active == true)
assert(record1.overlay.target.plainGate.alpha == 1)
assert(record1.overlay.target.niGate.alpha == 1, "accessible interruptible gate uses normal alpha")
castData.notInterruptible = true
IG.CastTracking:RefreshUnit("target")
assert(record1.overlay.target.niGate.alpha == 0)
castData.notInterruptible = secretBoolean(false)
IG.CastTracking:RefreshUnit("target")
assert(IG.CastState.target.niState == "restricted")
assert(record1.overlay.target.niGate.alpha == 255, "secret false gate must use full 255 alpha")
castData.notInterruptible = secretBoolean(true)
IG.CastTracking:RefreshUnit("target")
assert(record1.overlay.target.niGate.alpha == 0)
assert(secretAlphaCalls > 0)
castData.notInterruptible = false
IG.CastTracking:RefreshUnit("target")

-- Targeted GCD-only updates for unrelated spells are ignored before any
-- interrupt cooldown API call; real category/global/interrupt updates remain.
local cooldownCallsBeforeIrrelevant = actionCooldownCalls + actionDurationCalls
fire("SPELL_UPDATE_COOLDOWN", 2061, nil, nil, 133, nil)
flush_all()
assert(actionCooldownCalls + actionDurationCalls == cooldownCallsBeforeIrrelevant)
assert((IG.Stats["events.spellCooldownIgnored"] or 0) == 1)
fire("SPELL_UPDATE_COOLDOWN", 15487, nil, nil, nil, nil)
flush_all()
assert(actionCooldownCalls + actionDurationCalls > cooldownCallsBeforeIrrelevant)
local cooldownCallsBeforeSuccess = actionCooldownCalls + actionDurationCalls
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 2061)
flush_all()
assert(actionCooldownCalls + actionDurationCalls == cooldownCallsBeforeSuccess, "ordinary player casts refreshed interrupt cooldown")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 15487)
flush_all()
assert(actionCooldownCalls + actionDurationCalls > cooldownCallsBeforeSuccess, "successful interrupt did not refresh readiness")

local discoveryBefore = IG.Stats["startup.discoveryPasses"]
fire("PLAYER_ENTERING_WORLD")
flush_all()
assert(IG.Stats["startup.discoveryPasses"] == discoveryBefore, "PEW must not rediscover registries")
fire("PLAYER_REGEN_ENABLED")
flush_all()
assert(IG.Stats["startup.discoveryPasses"] == discoveryBefore, "combat exit must not rediscover registries")

-- A single-button conditional macro must reuse its dormant ability state without
-- frame/region/animation/table churn or repeated cast/cooldown API queries.
local solo = CreateFrame("Button", "SoloConditionalButton", UIParent)
solo.action = 4
actionData[4] = { actionType = "spell", id = 999001, interrupt = true }
EventRegistry:TriggerEvent("ActionButton.OnActionChanged", solo)
flush_all()
local soloRecord = assert(IG.ObservedButtons[solo])
assert(soloRecord.isInterrupt and soloRecord.overlay)
assert(IG.Data.runtimeInterrupts[999001] == 999001)
local specRefreshesBefore = IG.Stats["data.specRefreshes"] or 0
fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
fire("PLAYER_SPECIALIZATION_CHANGED")
fire("SPELLS_CHANGED")
flush_all()
assert((IG.Stats["data.specRefreshes"] or 0) == specRefreshesBefore + 1, "clustered spec/spell signals were not coalesced")
assert(IG.Data.runtimeInterrupts[999001] == 999001, "same-spec runtime interrupt discovery was discarded")
assert(soloRecord.isInterrupt == true, "same-spec refresh lost an authoritative runtime interrupt")
local abilitiesCreated = IG.Stats["abilities.created"]
local framesBeforeStress = frameCount
local texturesBeforeStress = textureCount
local fontsBeforeStress = fontCount
local animBeforeStress = animationCount
local castCallsBeforeStress = castingInfoCalls + channelInfoCalls
local cooldownCallsBeforeStress = actionCooldownCalls + actionDurationCalls
for index = 1, 2000 do
    if index % 2 == 0 then
        actionData[4] = { actionType = "macro", id = 999001, subType = "spell", interrupt = true }
    else
        actionData[4] = { actionType = "macro", id = 2061, subType = "spell", interrupt = false }
    end
    EventRegistry:TriggerEvent("ActionButton.OnActionChanged", solo)
    flush_all()
end
assert(frameCount == framesBeforeStress)
assert(textureCount == texturesBeforeStress)
assert(fontCount == fontsBeforeStress)
assert(animationCount == animBeforeStress)
assert(IG.Stats["abilities.created"] == abilitiesCreated, "dormant ability table was recreated")
assert(castingInfoCalls + channelInfoCalls == castCallsBeforeStress, "accessible NI was re-queried on mouseover")
assert(actionCooldownCalls + actionDurationCalls == cooldownCallsBeforeStress, "cached cooldown was re-queried on mouseover")

-- Restore the shared ability and test exact cooldown propagation.
actionData[1] = { actionType = "spell", id = 15487, interrupt = true }
EventRegistry:TriggerEvent("ActionButton.OnActionChanged", native1)
flush_all()
cooldownData.zero = false
cooldownData.remaining = 4
cooldownData.secret = false
cooldownData.active = true
cooldownData.onGCD = false
IG:MarkCooldownDirty(true)
flush_all()
assert(record1.ready == false and record2.ready == false)
assert(type(record1.deadline) == "number" and record1.deadline == record2.deadline)

cooldownData.zero = true
cooldownData.remaining = 0
cooldownData.active = false
IG:MarkCooldownDirty(true)
flush_all()
assert(record1.ready == true and record2.ready == true)

-- Secret timing with exact not-ready must not be overridden by optimistic mode.
cooldownData.secret = true
cooldownData.active = true
cooldownData.onGCD = false
cooldownData.infoSecret = false
IG.DB.optimisticRestrictedCooldown = true
IG:MarkCooldownDirty(true)
flush_all()
assert(record1.ready == false, "optimistic mode must not override exact false readiness")
assert(record1.ability.readinessRestricted == false and record1.ability.timingRestricted == true)

-- A GCD-only status can remain exactly ready when the event provenance is trusted.
cooldownData.onGCD = true
IG.Cooldown:CaptureGCDHints()
IG:MarkCooldownDirty(true)
flush_all()
assert(record1.ready == true and record1.ability.readinessRestricted == false)
IG:MarkCooldownDirty(false)
flush_all()
assert(record1.ready == false, "isOnGCD was trusted outside SPELL_UPDATE_COOLDOWN provenance")

-- Fully inaccessible readiness may use the explicit compatibility policy only.
cooldownData.infoSecret = true
cooldownData.onGCD = false
IG.DB.optimisticRestrictedCooldown = false
IG:MarkCooldownDirty(true)
flush_all()
assert(record1.ready == false and record1.ability.readinessRestricted == true)
IG.DB.optimisticRestrictedCooldown = true
IG:MarkCooldownDirty(true)
flush_all()
assert(record1.ready == true)
IG.DB.optimisticRestrictedCooldown = false
cooldownData.infoSecret = false
cooldownData.secret = false
cooldownData.active = false
cooldownData.zero = true

-- Charges and LoC are exact readiness gates.
local sharedActionSource = assert(record1.ability.sourceID)
actionCharges[sharedActionSource] = { current = 0, max = 2, active = true, zero = false, remaining = 6, secret = false }
IG:MarkCooldownDirty(true)
flush_all()
assert(record1.ready == false and type(record1.deadline) == "number")
actionCharges[sharedActionSource].current = 1
IG:MarkCooldownDirty(true)
flush_all()
assert(record1.ready == true)
actionCharges[sharedActionSource] = nil
actionLoC.active, actionLoC.replaces = true, true
IG:MarkCooldownDirty(false)
flush_all()
assert(record1.ready == false, "loss of control must block action readiness")
actionLoC.active, actionLoC.replaces = false, false
IG:MarkCooldownDirty(false)
flush_all()
actionLoC.secret = true
IG.DB.optimisticRestrictedCooldown = false
IG:MarkCooldownDirty(false)
flush_all()
assert(record1.ready == false and record1.ability.readinessRestricted == true, "restricted LoC failed open")
actionLoC.secret = false
IG:MarkCooldownDirty(false)
flush_all()

-- Pet aliases are spec-scoped and direct pet cooldowns stay independent.
currentSpecID = 265
IG.Data:RefreshActiveSpec()
IG.Buttons:RefreshPetButtons()
IG:MarkAllButtonsDirty()
flush_all()
local petRecord = assert(IG.ObservedButtons[PetActionBar.actionButtons[1]])
assert(petRecord.isInterrupt and petRecord.canonicalSpellID == 119910)
currentSpecID = 258
IG.Data:RefreshActiveSpec()
IG:MarkAllButtonsDirty()
flush_all()
assert(petRecord.isInterrupt == false)

-- Lazy provider attach uses the second IsAddOnLoaded result and discovers once.
local bfWidget = CreateFrame("Button", "ButtonForge1", UIParent)
local bfObject = { Widget = bfWidget, Mode = "spell", SpellId = 15487 }
bfWidget.ParentButton = bfObject
ButtonForge_API1 = {
    callback = nil,
    owner = nil,
    GetButtonFrameNames = function() return { "ButtonForge1" } end,
    GetButtonActionInfo = function()
        if bfObject.Mode == "spell" then return "spell", bfObject.SpellId end
        if bfObject.Mode == "macro" then return "macro", 1 end
        return nil
    end,
    RegisterCallback = function(callback, owner) ButtonForge_API1.callback, ButtonForge_API1.owner = callback, owner end,
    UnregisterCallback = function() end,
}
BFButton = {
    FullRefresh = function(_) end,
    ClearCommand = function(self)
        self.Mode = nil
        self.MacroMode = nil
        self.SpellId = nil
    end,
}
loaded.ButtonForge = true
assert(addonCallbacks.ButtonForge, "ButtonForge LOD callback missing")
addonCallbacks.ButtonForge()
flush_all()
local bfRecord = assert(IG.ObservedButtons[bfWidget])
assert(bfRecord.isInterrupt)
local bfChanges = IG.Stats["events.buttonForgeResolvedChanged"] or 0
BFButton.FullRefresh(bfObject)
flush_all()
local bfAfterFirst = IG.Stats["events.buttonForgeResolvedChanged"] or 0
BFButton.FullRefresh(bfObject)
flush_all()
assert((IG.Stats["events.buttonForgeResolvedChanged"] or 0) == bfAfterFirst, "ButtonForge duplicate refresh was not deduped")
assert(bfAfterFirst >= bfChanges)
BFButton.ClearCommand(bfObject)
flush_all()
assert(bfRecord.isInterrupt == false, "ButtonForge ClearCommand did not unbind the button")
bfObject.Mode, bfObject.SpellId = "spell", 15487
BFButton.FullRefresh(bfObject)
flush_all()
assert(bfRecord.isInterrupt == true, "ButtonForge button did not rebind after a new command")

-- Cooldown Viewer is not force-loaded and observes only interrupt items after load-order completion.
local cdmItem = CreateFrame("Button", "CDMInterrupt", UIParent)
function cdmItem:GetBaseSpellID() return 15487 end
local otherItem = CreateFrame("Button", "CDMOther", UIParent)
function otherItem:GetBaseSpellID() return 2061 end
local activeItems = { cdmItem, otherItem }
local pool = {}
function pool:EnumerateActive()
    local index = 0
    return function()
        index = index + 1
        return activeItems[index]
    end
end
EssentialCooldownViewer = { itemFramePool = pool }
UtilityCooldownViewer = { itemFramePool = { EnumerateActive = function() return function() return nil end end } }
CooldownViewerMixin = { OnAcquireItemFrame = function(_, _) end }
CooldownViewerItemDataMixin = {
    OnCooldownIDSet = function(_) end,
    ResetCooldownData = function(_) end,
}
loaded.Blizzard_CooldownViewer = true
assert(addonCallbacks.Blizzard_CooldownViewer, "CDM LOD callback missing")
addonCallbacks.Blizzard_CooldownViewer()
flush_all()
assert(IG.ObservedButtons[cdmItem] and IG.ObservedButtons[cdmItem].isInterrupt)
assert(IG.ObservedButtons[otherItem] == nil, "non-interrupt CDM item allocated addon state")
local cdmObserved = IG.Stats["cdm.interruptItemsObserved"] or 0
CooldownViewerMixin:OnAcquireItemFrame(cdmItem)
cdmItem.OnCooldownIDSet = CooldownViewerItemDataMixin.OnCooldownIDSet
cdmItem:OnCooldownIDSet()
flush_all()
assert((IG.Stats["cdm.interruptItemsObserved"] or 0) == cdmObserved, "duplicate CDM lifecycle observations were not suppressed")
cdmItem.ResetCooldownData = CooldownViewerItemDataMixin.ResetCooldownData
cdmItem:ResetCooldownData()
flush_all()
assert(IG.ObservedButtons[cdmItem].isInterrupt == false)

-- Options allocate their controls only on first visit.
local framesBeforeOptions, fontsBeforeOptions = frameCount, fontCount
assert(IG.Options.built == false)
IG.Options.panel.scripts.OnShow(IG.Options.panel)
assert(IG.Options.built == true)
assert(frameCount > framesBeforeOptions and fontCount > fontsBeforeOptions)

-- A button first observed in combat is classified immediately but gets its shell OOC.
combat = true
local late = CreateFrame("Button", "LateButton", UIParent)
late.action = 5
actionData[5] = { actionType = "spell", id = 15487, interrupt = true }
EventRegistry:TriggerEvent("ActionButton.OnActionChanged", late)
flush_all()
local lateRecord = assert(IG.ObservedButtons[late])
assert(lateRecord.isInterrupt and lateRecord.overlay == nil and lateRecord.overlayPending == true)
combat = false
fire("PLAYER_REGEN_ENABLED")
flush_all()
assert(lateRecord.overlay ~= nil)

print("MOCK WOW BETA2 TESTS PASSED")
