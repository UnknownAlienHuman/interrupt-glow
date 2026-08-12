-- InterruptGlow - Options panel
-- Author: Neomorph

local IG = _G.InterruptGlow
if not IG then return end

InterruptGlowDB = InterruptGlowDB or {}
local DB = InterruptGlowDB

-- Defaults
if DB.cdText == nil then DB.cdText = false end
if DB.cdm == nil then DB.cdm = true end
if DB.strictNI == nil then DB.strictNI = true end

if DB.debug == nil then DB.debug = false end
if DB.debugChat == nil then DB.debugChat = false end
if DB.debugLevel == nil then DB.debugLevel = 2 end
if DB.debugKeep == nil then DB.debugKeep = 400 end
if DB.debugAutoShow == nil then DB.debugAutoShow = true end

local function Apply()
    if IG.SetCDTextEnabled then
        IG:SetCDTextEnabled(DB.cdText)
    end
    if DB.cdm and IG.TryFindCDMButton then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() IG:TryFindCDMButton() end)
        end
    elseif (not DB.cdm) and IG.ClearExtraButtons then
        IG:ClearExtraButtons()
        if IG.MarkGlowDirty then
            IG:MarkGlowDirty()
        elseif IG.ApplyGlowDecision then
            IG:ApplyGlowDecision()
        end
    end
    if IG.MarkReadyDirty then
        IG:MarkReadyDirty("options-apply")
    end
end

local panel = CreateFrame("Frame", "InterruptGlowOptionsPanel", UIParent)
panel.name = "Interrupt Glow"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Interrupt Glow")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetText("Glows your interrupt button when target/focus is casting (respects not-interruptible and your interrupt cooldown).")

local cd = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
cd:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
cd.Text:SetText("Show cooldown countdown numbers")
cd.tooltipText = "Show seconds remaining until your interrupt is ready."
cd:SetScript("OnClick", function(self)
    DB.cdText = self:GetChecked() and true or false
    Apply()
end)

local cdm = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
cdm:SetPoint("TOPLEFT", cd, "BOTTOMLEFT", 0, -10)
cdm.Text:SetText("Mirror glow onto Blizzard Cooldown Manager interrupt icon (if pinned)")
cdm.tooltipText = "If you pin your interrupt to Blizzard's Cooldown Manager, mirror the glow and cooldown numbers there."
cdm:SetScript("OnClick", function(self)
    DB.cdm = self:GetChecked() and true or false
    Apply()
end)


local strictNI = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
strictNI:SetPoint("TOPLEFT", cdm, "BOTTOMLEFT", 0, -10)
strictNI.Text:SetText("Strict not-interruptible detection")
strictNI.tooltipText = "Blocks glow unless the cast is confirmed interruptible. If the game keeps interruptibility hidden behind restricted/secret values, unknown stays blocked until you disable strict mode."
strictNI:SetScript("OnClick", function(self)
    DB.strictNI = self:GetChecked() and true or false
    Apply()
end)

local dbg = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
dbg:SetPoint("TOPLEFT", strictNI, "BOTTOMLEFT", 0, -10)
dbg.Text:SetText("Enable debug log buffer")
dbg.tooltipText = "Stores recent decisions/events in a ring buffer. Use /iglow log show to open a copyable log window."
dbg:SetScript("OnClick", function(self)
    DB.debug = self:GetChecked() and true or false
    Apply()
    if DB.debug and DB.debugAutoShow and IG and IG.MaybeAutoShowDebugLog then
        IG:MaybeAutoShowDebugLog("options-debug-on", true)
    end
end)

local dbgChat = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
dbgChat:SetPoint("TOPLEFT", dbg, "BOTTOMLEFT", 0, -6)
dbgChat.Text:SetText("Echo debug to chat (spammy)")
dbgChat.tooltipText = "Also prints debug lines to chat. Prefer /iglow log show."
dbgChat:SetScript("OnClick", function(self)
    DB.debugChat = self:GetChecked() and true or false
    Apply()
end)

local dbgAuto = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
dbgAuto:SetPoint("TOPLEFT", dbgChat, "BOTTOMLEFT", 0, -6)
dbgAuto.Text:SetText("Auto-open debug log window")
dbgAuto.tooltipText = "Automatically opens the copyable debug log window when the addon loads (and when errors occur), while debug logging is enabled."
dbgAuto:SetScript("OnClick", function(self)
    DB.debugAutoShow = self:GetChecked() and true or false
    Apply()
    if DB.debug and IG and IG.MaybeAutoShowDebugLog then
        IG:MaybeAutoShowDebugLog("options-autoshow", true)
    end
end)


local showLog = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
showLog:SetPoint("LEFT", dbg, "RIGHT", 230, 0)
showLog:SetSize(140, 22)
showLog:SetText("Show Debug Log")
showLog:SetScript("OnClick", function()
    if InterruptGlow and InterruptGlow.Debug and InterruptGlow.Debug.Show then
        InterruptGlow.Debug:Show(DB.debugKeep or 400)
    else
        print("InterruptGlow: Debug log unavailable.")
    end
end)

panel.refresh = function()
    cd:SetChecked(DB.cdText and true or false)
    cdm:SetChecked(DB.cdm and true or false)
    strictNI:SetChecked(DB.strictNI and true or false)
    dbg:SetChecked(DB.debug and true or false)
    dbgChat:SetChecked(DB.debugChat and true or false)
    dbgAuto:SetChecked(DB.debugAutoShow and true or false)
end

panel.default = function()
    DB.cdText = false
    DB.cdm = true
    DB.strictNI = true

    DB.debug = false
    DB.debugChat = false
    DB.debugLevel = 2
    DB.debugKeep = 400
    DB.debugAutoShow = true
end

panel.okay = function()
    Apply()
end

-- Modern Settings support (12.x) + fallback to Interface Options
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
else
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end
