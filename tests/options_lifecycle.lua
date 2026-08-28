local ROOT = arg[1] or "."

_G = _G or _ENV

local refreshCalls = 0
local allButtonsDirty = 0
local castDirty = 0
local cooldownDirty = 0
local visualDirty = 0
local cdmEnabled = nil
local registeredPanel = nil

InterruptGlow = {
    DB = {
        enabled = false,
        cdText = true,
        cdm = false,
        strictNI = false,
        optimisticRestrictedCooldown = true,
        debug = true,
        debugKeep = 400,
    },
    modules = {},
    CDM = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:MarkAllButtonsDirty() allButtonsDirty = allButtonsDirty + 1 end
function InterruptGlow:MarkCastDirty() castDirty = castDirty + 1 end
function InterruptGlow:MarkCooldownDirty() cooldownDirty = cooldownDirty + 1 end
function InterruptGlow:MarkVisualDirty() visualDirty = visualDirty + 1 end
function InterruptGlow.CDM:SetEnabled(value) cdmEnabled = value end

UIParent = {}
function CreateFrame()
    local frame = { scripts = {} }
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    return frame
end

Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        registeredPanel = panel
        return { id = 1 }
    end,
    RegisterAddOnCategory = function() end,
}

local loader, loadError = loadfile(ROOT .. "/Options.lua")
assert(loader, loadError)
loader()

local panel = assert(InterruptGlow.Options.panel)
assert(panel == registeredPanel)
assert(type(panel.OnRefresh) == "function")
assert(type(panel.OnDefault) == "function")
assert(type(panel.OnCommit) == "function")
assert(panel.refresh == panel.OnRefresh)
assert(panel.default == panel.OnDefault)
assert(panel.okay == panel.OnCommit)

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
assert(cdmEnabled == true)
assert(allButtonsDirty == 1)
assert(castDirty == 1)
assert(cooldownDirty == 1)
assert(visualDirty == 1)
assert(refreshCalls == 3)

panel.OnCommit()
assert(refreshCalls == 3)

print("OPTIONS LIFECYCLE TEST PASSED")
