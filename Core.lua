-- Interrupt Glow (Retail)
-- Core bootstrap / launcher

InterruptGlowDB = InterruptGlowDB or {}

local IG = _G.InterruptGlow or {}
_G.InterruptGlow = IG

local Private = IG.Private or {}
IG.Private = Private

if not Private.frame then
    Private.frame = CreateFrame("Frame")
end

if not Private.launcherBound then
    Private.launcherBound = true
    Private.frame:RegisterEvent("PLAYER_LOGIN")
end
