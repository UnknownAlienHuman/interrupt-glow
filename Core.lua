-- Interrupt Glow 1.1
-- Author: Neomorph

local addonName, addon = ...
if type(addon) ~= "table" then
    addon = {}
end

_G.InterruptGlow = addon

addon.name = addonName or "InterruptGlow"

local C_AddOns = _G.C_AddOns
if C_AddOns and C_AddOns.GetAddOnMetadata then
    addon.version = C_AddOns.GetAddOnMetadata(addon.name, "Version") or "unknown"
else
    addon.version = "unknown"
end
