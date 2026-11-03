local ROOT = arg[1] or "."
_G = _G or _ENV

local now = 100
local deniedWrites = 0
local SECRET = {}
local dirty = { cast = 0, cooldown = 0, visual = 0 }

local function Accessible(object)
    if object.denied or object.forbidden then return false end
    return object.parent == nil or Accessible(object.parent)
end

local function Permit(object)
    if not Accessible(object) then
        deniedWrites = deniedWrites + 1
        error("mutation of a denied visual")
    end
end

local function NewObject(parent)
    local object = { parent = parent, alpha = 0, text = "", queries = 0, scripts = {} }
    function object:HasAccessConstraints() self.queries = self.queries + 1; return true end
    function object:IsForbidden() self.queries = self.queries + 1; return self.forbidden == true end
    function object:CanBeAccessedInContext() self.queries = self.queries + 1; return Accessible(self) end
    function object:SetAlpha(value) Permit(self); self.alpha = value end
    function object:SetAlphaFromBoolean(value, yes, no)
        Permit(self)
        -- The native sink accepts an opaque payload without addon-side readback.
        assert(value == SECRET)
        self.secretSinkCalls = (self.secretSinkCalls or 0) + 1
        assert(yes == 0 and no == 255)
    end
    function object:SetText(value) Permit(self); self.text = value end
    function object:SetScript(name, callback) Permit(self); self.scripts[name] = callback end
    function object:GetFrameLevel() Permit(self); return 1 end
    function object:SetOnUpdateMode(mode) Permit(self); self.mode = mode end
    for _, name in ipairs({ "ClearAllPoints", "SetAllPoints", "SetFrameLevel", "SetPoint",
        "SetBlendMode", "SetAtlas", "SetTexture", "SetVertexColor", "Show", "Hide",
        "SetJustifyH", "SetLooping", "SetDuration", "SetScale", "SetSmoothing" }) do
        object[name] = Permit
    end
    function object:CreateTexture() Permit(self); return NewObject(self) end
    function object:CreateFontString() Permit(self); return NewObject(self) end
    function object:CreateAnimationGroup() Permit(self); return NewObject(self) end
    function object:CreateAnimation() Permit(self); return NewObject(self) end
    function object:Play() Permit(self); self.playing = true end
    function object:Stop() Permit(self); self.playing = false end
    return object
end

function CreateFrame(_, _, parent) return NewObject(parent) end
function UnitIsUnit() return false end

InterruptGlow = { Worker = {} }
local IG = InterruptGlow
function IG.CanAccess(value) return value ~= SECRET end
function IG:ReadMember(object, key)
    if not self.CanAccess(object) or object == nil then return nil, false end
    local value = object[key]
    if not self.CanAccess(value) then return nil, false end
    return value, true
end
function IG:IsInCombat() return false end
function IG:Now() return now end
function IG:BumpStat() end
function IG:MarkCastDirty() dirty.cast = dirty.cast + 1 end
function IG:MarkCooldownDirty()
    dirty.cooldown = dirty.cooldown + 1
    for _, ability in pairs(self.AbilityStates) do ability.readinessPending = true end
end
function IG:MarkVisualDirty() dirty.visual = dirty.visual + 1 end
function IG.Worker:Disable(frame) frame:SetOnUpdateMode(0) end
function IG.Worker:RunOnce(frame) frame:SetOnUpdateMode(1) end
function IG.Worker:SetContinuous(frame, enabled) frame:SetOnUpdateMode(enabled and 2 or 0) end

assert(loadfile(ROOT .. "/core/Glow.lua"))()
local Glow = IG.Glow

local function AddRecord(ability, countdown, enhance)
    local button = NewObject()
    local record = { button = button, ability = ability, isInterrupt = true,
        ready = not countdown, deadline = countdown and now + 5 or nil }
    ability.records[record] = true
    IG.ObservedButtons[button] = record
    IG.InterruptRecords[record] = true
    assert(Glow:CreateShell(record))
    if enhance ~= false then Glow:EnsureInterruptVisuals(record) end
    Glow:EnsureCooldownText(record)
    Glow:ApplyUnitInterruptibility("target", false, true)
    Glow:RefreshRecord(record)
    assert(record.overlay.target.plainGate.alpha == (countdown and 0 or 1))
    assert(record.overlay.cooldownText.text == (countdown and "5" or ""))
    return record, button
end

local function Fixture(countdown, enhance)
    now = 100
    dirty = { cast = 0, cooldown = 0, visual = 0 }
    IG.DB = { enabled = true, cdText = true, strictNI = true, animateGlow = true }
    IG.RuntimeLifecycle = { active = true, IsActive = function(self) return self.active end }
    IG.ObservedButtons = {}
    IG.InterruptRecords = {}
    IG.CastState = {
        target = { active = true, hostile = true, niState = "interruptible" },
        focus = { active = false, hostile = false, niState = "none" },
    }
    local ability = { records = {}, deadline = countdown and now + 5 or nil }
    IG.AbilityStates = { [1766] = ability }
    Glow:SetRuntimeWorkerEnabled(false)
    return AddRecord(ability, countdown, enhance)
end

local function Queries(record)
    local overlay = record.overlay
    local total = overlay.cooldownText and overlay.cooldownText.queries or 0
    for _, unit in ipairs({ "target", "focus" }) do
        local branch = overlay[unit]
        total = total + branch.plainGate.queries + branch.niGate.queries
            + (branch.animation and branch.animation.queries or 0)
    end
    return total
end

local cases = {
    { name = "candidate", action = function(record) record.ready = false; Glow:RefreshRecord(record) end },
    { name = "ordinary NI", action = function() Glow:ApplyUnitInterruptibility("target", true, true) end },
    { name = "opaque NI", action = function() Glow:ApplyUnitInterruptibility("target", SECRET, true) end },
    { name = "stored NI", action = function(record) Glow:ApplyStoredInterruptibilityToRecord(record) end },
    { name = "clear", action = function(record) Glow:ClearRecord(record) end },
    { name = "animation", action = function() Glow:SetAnimationEnabled(false) end },
    { name = "enhancement", enhance = false, action = function(record) Glow:EnsureInterruptVisuals(record) end },
    { name = "countdown", countdown = true, action = function(record) Glow:RefreshCooldownText(record, now + 1) end },
    { name = "countdown setting", countdown = true, action = function() Glow:EnsureCooldownTexts() end },
}

for _, case in ipairs(cases) do
    local record, button = Fixture(case.countdown, case.enhance)
    button.denied = true
    local ok, err = pcall(case.action, record)
    assert(ok, case.name .. ": " .. tostring(err))
    assert(deniedWrites == 0, case.name .. " mutated a denied descendant")

    local afterDenial = Queries(record)
    for _ = 1, 3 do
        Glow:RefreshRecord(record)
        Glow:ApplyUnitInterruptibility("target", SECRET, true)
        Glow:ClearRecord(record)
        Glow:RefreshCooldownText(record, now + 1)
    end
    assert(Queries(record) == afterDenial, case.name .. " retried a denied destination")

    button.denied = false
    Glow:RetryRecordVisuals(record)
    assert(record.overlay.target.plainGate.alpha == 0, case.name .. " kept stale highlight on recovery")
    assert(record.overlay.cooldownText.text == "", case.name .. " kept stale text on recovery")
    assert(dirty.cast > 0 and dirty.cooldown > 0 and dirty.visual > 0)
    Glow:RefreshRecord(record)
    assert(record.overlay.target.plainGate.alpha == 0, "recovery displayed old pending readiness")
    record.ability.readinessPending = false -- simulate the fresh readiness pass
    record.ready = true
    Glow:ApplyUnitInterruptibility("target", false, true)
    Glow:RefreshRecord(record)
    assert(record.overlay.target.plainGate.alpha == 1, case.name .. " did not repaint after recovery")
end

-- Permission belongs to the exact destination, including a texture or animation
-- that is denied while the button and its other descendants remain accessible.
for _, kind in ipairs({ "parent gate", "NI texture", "animation", "countdown text" }) do
    local record = Fixture(kind == "countdown text")
    local overlay = record.overlay
    local object = kind == "parent gate" and overlay.target.plainGate
        or kind == "NI texture" and overlay.target.niGate
        or kind == "animation" and overlay.target.animation
        or overlay.cooldownText
    object.denied = true
    if kind == "parent gate" then
        record.ready = false
        Glow:RefreshRecord(record)
    elseif kind == "NI texture" then
        Glow:ApplyUnitInterruptibility("target", SECRET, true)
    elseif kind == "animation" then
        Glow:SetAnimationEnabled(false)
    else
        Glow:RefreshCooldownText(record, now + 1)
    end
    assert(deniedWrites == 0, kind .. " was mutated despite exact destination denial")
    local beforeRetry = Queries(record)
    Glow:ClearRecord(record)
    assert(Queries(record) == beforeRetry, kind .. " was probed again without a recovery signal")
end

-- An allowed opaque sink is still reached directly, without inspecting its output.
local record = Fixture()
Glow:ApplyUnitInterruptibility("target", SECRET, true)
assert(record.overlay.target.niGate.secretSinkCalls == 1)

-- Blocked copies cannot hold the timer open; an unblocked sibling still needs it.
local blocked, button = Fixture(true)
button.denied = true
Glow:RefreshCooldownText(blocked, now + 1)
Glow:UpdateRuntimeDriver()
assert(Glow.runtimeWorkerEnabled == false and Glow.runtimeFrame.mode == 0)
local beforeTicks = Queries(blocked)
for _ = 1, 5 do Glow.runtimeFrame.scripts.OnUpdate(Glow.runtimeFrame, 0.25) end
assert(Queries(blocked) == beforeTicks, "timing worker probed a denied record")
assert(Glow.runtimeWorkerEnabled == false)
AddRecord(blocked.ability, true)
Glow:UpdateRuntimeDriver()
assert(Glow.runtimeWorkerEnabled == true, "blocked copy suppressed a usable sibling")
Glow.runtimeFrame.scripts.OnUpdate(Glow.runtimeFrame, 0.25)
assert(Queries(blocked) == beforeTicks, "usable sibling caused denied-object retries")

-- A permanently forbidden destination also denies current context; it must not
-- be misclassified as a temporary denial or rechecked on recovery signals.
local forbidden = Fixture()
forbidden.overlay.target.plainGate.forbidden = true
forbidden.ready = false
Glow:RefreshRecord(forbidden)
local forbiddenQueries = Queries(forbidden)
Glow:RetryDeferredVisuals()
Glow:CreatePendingOverlays()
Glow:SetAnimationEnabled(false)
assert(Queries(forbidden) == forbiddenQueries, "permanently forbidden visual was retried")
local forbiddenOwner = NewObject()
forbiddenOwner.forbidden = true
local noShell = { button = forbiddenOwner }
assert(Glow:CreateShell(noShell) == nil)
local ownerQueries = forbiddenOwner.queries
Glow:QueueShell(noShell, true)
assert(forbiddenOwner.queries == ownerQueries, "permanently forbidden owner was retried")
IG.AbilityStates = { { records = { [noShell] = true }, deadline = now + 5 } }
Glow:UpdateRuntimeDriver()
assert(Glow.runtimeWorkerEnabled == false, "forbidden shell owner kept timing work alive")
local deferredOwner = NewObject()
deferredOwner.denied = true
local deferredShell = { button = deferredOwner }
assert(Glow:CreateShell(deferredShell) == nil)
IG.AbilityStates = { { records = { [deferredShell] = true }, deadline = now + 5 } }
Glow:UpdateRuntimeDriver()
assert(Glow.runtimeWorkerEnabled == false, "context-denied shell owner kept timing work alive")

-- Cleanup survives disabled, unbound and combat-deferred enable states. Recovery
-- may clear old output but must not wake active work until lifecycle activation.
for _, state in ipairs({ "disabled", "unbound", "enable pending" }) do
    local stale, owner = Fixture(state == "unbound")
    owner.denied = true
    Glow:ClearRecord(stale)
    if state == "disabled" then IG.DB.enabled = false
    elseif state == "unbound" then
        stale.isInterrupt = false
        IG.InterruptRecords[stale] = nil
        stale.ability.records[stale] = nil
    else IG.RuntimeLifecycle.active = false end
    owner.denied = false
    Glow:RetryDeferredVisuals()
    assert(stale.overlay.target.plainGate.alpha == 0 and stale.overlay.focus.plainGate.alpha == 0)
    assert(stale.overlay.cooldownText.text == "", state .. " left stale text")
    assert(dirty.cast == 0 and dirty.cooldown == 0 and dirty.visual == 0,
        state .. " woke active work during cleanup")
end

assert(deniedWrites == 0)
print("VISUAL ACCESS TRANSITION TEST PASSED")
