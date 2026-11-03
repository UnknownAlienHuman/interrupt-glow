local ROOT = arg[1] or "."

_G = _G or _ENV

local refreshCalls = 0
local allButtonsDirty = 0
local castDirty = 0
local cooldownDirty = 0
local visualDirty = 0
local cdmEnabled = nil
local animationEnabled = nil
local registeredPanel = nil
local openedCategoryID = nil
local lifecycleEnabledCalls = {}
local printed = {}

InterruptGlow = {
    DB = {
        enabled = false,
        cdText = true,
        cdm = false,
        animateGlow = false,
        strictNI = false,
        optimisticRestrictedCooldown = true,
        debug = true,
        debugChat = true,
        debugKeep = 999,
    },
    CDM = {},
    Glow = {},
    RuntimeLifecycle = { active = false },
}
function InterruptGlow:MarkAllButtonsDirty() allButtonsDirty = allButtonsDirty + 1 end
function InterruptGlow:MarkCastDirty() castDirty = castDirty + 1 end
function InterruptGlow:MarkCooldownDirty() cooldownDirty = cooldownDirty + 1 end
function InterruptGlow:MarkVisualDirty() visualDirty = visualDirty + 1 end
function InterruptGlow:Print(message) printed[#printed + 1] = message end
function InterruptGlow.CDM:SetEnabled(value) cdmEnabled = value end
function InterruptGlow.Glow:SetAnimationEnabled(value)
    animationEnabled = value
    InterruptGlow.DB.animateGlow = value
end
function InterruptGlow.RuntimeLifecycle:IsActive() return self.active end
function InterruptGlow.RuntimeLifecycle:SetEnabled(value)
    value = value == true
    lifecycleEnabledCalls[#lifecycleEnabledCalls + 1] = value
    InterruptGlow.DB.enabled = value
    self.active = value
    return true
end

UIParent = {}
function CreateFrame()
    local frame = { scripts = {} }
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    return frame
end

Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        registeredPanel = panel
        return { GetID = function() return 1 end }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(categoryID) openedCategoryID = categoryID end,
}

local loader, loadError = loadfile(ROOT .. "/Options.lua")
assert(loader, loadError)
loader()

local panel = assert(InterruptGlow.Options.panel)
assert(panel == registeredPanel)
assert(type(panel.OnRefresh) == "function")
assert(type(panel.OnDefault) == "function")
assert(type(panel.OnCommit) == "function")
assert(InterruptGlow.Options.categoryID == 1)
assert(InterruptGlow.Options:Open() == true)
assert(openedCategoryID == 1, "Options:Open did not hand the category ID to Settings")

local savedCategoryID = InterruptGlow.Options.categoryID
InterruptGlow.Options.categoryID = nil
assert(InterruptGlow.Options:Open() == false)
assert(printed[#printed] == "Interrupt Glow settings are unavailable.")
InterruptGlow.Options.categoryID = savedCategoryID
Settings.OpenToCategory = nil
assert(InterruptGlow.Options:Open() == false)
assert(printed[#printed] == "Interrupt Glow settings are unavailable.")
Settings.OpenToCategory = function(categoryID) openedCategoryID = categoryID end

-- Avoid constructing controls; this test targets Settings lifecycle routing.
function InterruptGlow.Options:Refresh()
    refreshCalls = refreshCalls + 1
end

panel.OnRefresh()
assert(refreshCalls == 1)
panel.scripts.OnShow()
assert(refreshCalls == 2)

panel.OnDefault()
local DB = InterruptGlow.DB
assert(DB.enabled == true)
assert(DB.cdText == false)
assert(DB.cdm == true)
assert(DB.strictNI == true)
assert(DB.optimisticRestrictedCooldown == false)
assert(DB.debug == false)
assert(DB.debugChat == false)
assert(DB.debugKeep == 400)
assert(DB.animateGlow == true and animationEnabled == true)
assert(#lifecycleEnabledCalls == 1 and lifecycleEnabledCalls[1] == true,
    "default reset did not route master enable through RuntimeLifecycle")
assert(cdmEnabled == true)
assert(allButtonsDirty == 1)
assert(castDirty == 1)
assert(cooldownDirty >= 1)
assert(visualDirty >= 1)
assert(refreshCalls == 3)

panel.OnCommit()
assert(refreshCalls == 3)

print("OPTIONS LIFECYCLE TEST PASSED")
