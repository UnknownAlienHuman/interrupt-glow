-- Interrupt Glow 1.1
-- Author: Neomorph

local addonName, addon = ...
if type(addon) ~= "table" then
    addon = {}
end

_G.InterruptGlow = addon

addon.name = addonName or "InterruptGlow"
addon.modules = addon.modules or {}

local C_AddOns = _G.C_AddOns
if C_AddOns and C_AddOns.GetAddOnMetadata then
    addon.version = C_AddOns.GetAddOnMetadata(addon.name, "Version") or "1.1.0-beta.6"
else
    addon.version = "1.1.0-beta.6"
end

function addon:RegisterModule(name, module)
    if type(name) ~= "string" or type(module) ~= "table" then
        return
    end
    self.modules[name] = module
end

function addon:GetModule(name)
    return self.modules[name]
end
