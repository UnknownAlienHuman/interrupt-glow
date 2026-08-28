local ROOT = arg[1] or "."

_G = _G or _ENV

local combat = true
local frameCount = 0
local fontStringCount = 0
local optionsBuiltStats = 0
local registeredPanel = nil

InterruptGlow = {
    DB = {
        enabled = true,
        cdText = false,
        cdm = true,
        strictNI = true,
        optimisticRestrictedCooldown = false,
        debug = false,
        debugKeep = 400,
    },
    modules = {},
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:IsInCombat() return combat end
function InterruptGlow:BumpStat(key)
    assert(key == "ui.optionsBuilt")
    optionsBuiltStats = optionsBuiltStats + 1
end
function InterruptGlow:MarkAllButtonsDirty() end
function InterruptGlow:MarkCastDirty() end
function InterruptGlow:MarkCooldownDirty() end
function InterruptGlow:MarkVisualDirty() end

UIParent = {}

local function NewFontString()
    fontStringCount = fontStringCount + 1
    return {
        SetPoint = function() end,
        SetText = function() end,
        SetWidth = function() end,
        SetJustifyH = function() end,
    }
end

function CreateFrame(_, _, _, template)
    frameCount = frameCount + 1
    local frame = {
        scripts = {},
        shown = true,
        Text = template == "InterfaceOptionsCheckButtonTemplate" and NewFontString() or nil,
    }
    function frame:SetPoint() end
    function frame:SetSize() end
    function frame:SetText() end
    function frame:SetChecked(value) self.checked = value end
    function frame:GetChecked() return self.checked == true end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:CreateFontString() return NewFontString() end
    function frame:IsShown() return self.shown end
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

local Options = assert(InterruptGlow.Options)
local panel = assert(Options.panel)
assert(panel == registeredPanel)
assert(frameCount == 1, "more than the bare Settings canvas was created at load")
assert(fontStringCount == 0)

-- Opening Settings for the first time in combat must not create controls.
assert(panel.scripts.OnShow() == nil)
assert(Options.built == false)
assert(Options.buildDeferred == true)
assert(frameCount == 1 and fontStringCount == 0)

-- If the panel closes before combat ends, PLAYER_REGEN_ENABLED must not build a
-- hidden options tree. The next out-of-combat OnShow remains the build surface.
panel.shown = false
combat = false
assert(Options:OnCombatEnded() == false)
assert(Options.built == false and Options.buildDeferred == true)
assert(frameCount == 1 and fontStringCount == 0)

panel.shown = true
assert(panel.scripts.OnShow() == true)
assert(Options.built == true and Options.buildDeferred == false)
assert(#Options.controls == 6)
assert(frameCount == 9, "expected canvas + six checks + two action buttons")
assert(fontStringCount == 8, "expected six check labels plus title/subtitle")
assert(optionsBuiltStats == 1)

-- Refreshing or receiving another regen signal cannot create a second tree.
local framesAfterBuild = frameCount
local stringsAfterBuild = fontStringCount
assert(Options:Refresh() == true)
assert(Options:OnCombatEnded() == false)
assert(frameCount == framesAfterBuild)
assert(fontStringCount == stringsAfterBuild)
assert(optionsBuiltStats == 1)

print("OPTIONS COMBAT DEFER TEST PASSED")
