local ROOT = arg[1] or "."

_G = _G or _ENV

Enum = {
    OnUpdateMode = {
        Disabled = 0,
        RunWhenVisible = 1,
        RunWhenVisibleOnce = 2,
        RunOnce = 3,
        RunAlways = 4,
    },
}

local frames = {}
function CreateFrame()
    local frame = { mode = nil, shown = true, scripts = {} }
    function frame:SetOnUpdateMode(mode) self.mode = mode end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    frames[#frames + 1] = frame
    return frame
end

function canaccessvalue(_) return true end
function GetTime() return 100 end
function InCombatLockdown() return false end
C_AddOns = {
    IsAddOnLoaded = function() return false, false end,
}

local function LoadShared(saved, version)
    local addon = {
        name = "InterruptGlow",
        version = version or "1.1.0-beta.4",
        modules = {},
    }
    function addon:RegisterModule(name, module) self.modules[name] = module end

    _G.InterruptGlow = addon
    _G.InterruptGlowDB = saved

    local workerLoader, workerError = loadfile(ROOT .. "/core/Worker.lua")
    assert(workerLoader, workerError)
    workerLoader()

    local sharedLoader, sharedError = loadfile(ROOT .. "/core/Shared.lua")
    assert(sharedLoader, sharedError)
    sharedLoader()
    return addon
end

local legacy = {
    schema = 2,
    enabled = false,
    cdText = "invalid",
    cdm = false,
    strictNI = false,
    optimisticRestrictedCooldown = true,
    debug = true,
    debugChat = true,
    debugKeep = 99999,
    debugAutoShow = true,
    slots = { 1, 2, 3 },
    localCD = { old = true },
    unknownLegacyKey = "remove-me",
}

local IG = LoadShared(legacy)
local DB = IG.DB
assert(DB == InterruptGlowDB)
assert(DB.schema == 3)
assert(DB.producerVersion == "1.1.0-beta.4")
assert(DB.interface == 120100)
assert(DB.enabled == false)
assert(DB.cdText == false, "invalid boolean was not reset")
assert(DB.cdm == false)
assert(DB.strictNI == false)
assert(DB.optimisticRestrictedCooldown == true)
assert(DB.debug == true and DB.debugChat == true)
assert(DB.debugKeep == 2000, "debugKeep was not clamped")
assert(DB.slots == nil and DB.localCD == nil)
assert(DB.debugAutoShow == nil and DB.unknownLegacyKey == nil)

local visualRuns = 0
IG.Glow = {
    RefreshAll = function()
        visualRuns = visualRuns + 1
        if visualRuns == 1 then IG:MarkVisualDirty() end
    end,
}

IG:MarkVisualDirty()
assert(IG.flushFrame.mode == Enum.OnUpdateMode.RunOnce)

-- Simulate the engine resetting RunOnce to Disabled before dispatch.
IG.flushFrame.mode = Enum.OnUpdateMode.Disabled
IG.flushFrame.scripts.OnUpdate(IG.flushFrame, 0.016)
assert(visualRuns == 1)
assert(IG.flushFrame.mode == Enum.OnUpdateMode.RunOnce, "re-dirty did not rearm RunOnce")

IG.flushFrame.mode = Enum.OnUpdateMode.Disabled
IG.flushFrame.scripts.OnUpdate(IG.flushFrame, 0.016)
assert(visualRuns == 2)
assert(IG.flushFrame.mode == Enum.OnUpdateMode.Disabled)
assert(not IG:HasDirtyWork())

local clean = LoadShared("corrupt-root", "1.1.0-beta.4")
assert(clean.DB.schema == 3)
assert(clean.DB.enabled == true)
assert(clean.DB.debugKeep == 400)
assert(clean.flushFrame.mode == Enum.OnUpdateMode.Disabled)

print("SHARED WORKER TEST PASSED")
