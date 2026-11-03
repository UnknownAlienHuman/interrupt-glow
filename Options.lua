local IG = _G.InterruptGlow
if not IG then return end

local DB = IG.DB
local Options = {
    built = false,
    buildDeferred = false,
    controls = {},
}
IG.Options = Options

-- Register a bare canvas at load. Build its controls only when first opened
-- outside combat; Settings can be opened while combat restrictions are active.
local panel = CreateFrame("Frame", "InterruptGlowOptionsPanel", UIParent)
panel.name = "Interrupt Glow"
Options.panel = panel

local Settings = _G.Settings

local function GetPanelWidth()
    if type(panel.GetWidth) == "function" then
        local width = panel:GetWidth()
        if type(width) == "number" and width > 0 then return width end
    end
    return 720
end

local function RuntimeActive()
    return IG.RuntimeLifecycle:IsActive()
end

local function SetMasterEnabled(value)
    return IG.RuntimeLifecycle:SetEnabled(value)
end

local function ApplyDefaultsOrFullRefresh()
    if not RuntimeActive() then return end
    IG:MarkAllButtonsDirty()
    IG:MarkCastDirty()
    IG:MarkCooldownDirty()
    IG:MarkVisualDirty()
end

local function CreateSectionHeading(y, label)
    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -y)
    heading:SetText(label)
    return heading
end

local function CreateCheckButton(y, label, tooltip, getter, setter)
    local check = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -y)
    check.Text:SetText(label)
    check.Text:SetWidth(math.max(120, GetPanelWidth() - 48))
    check.Text:SetWordWrap(true)
    check.tooltipText = tooltip
    check:SetScript("OnClick", function(self)
        setter(self:GetChecked() == true)
    end)
    check.RefreshValue = function(self)
        self:SetChecked(getter() == true)
    end
    Options.controls[#Options.controls + 1] = check
    return check
end

local function CreateActionButton(x, y, width, label, onClick)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    button:SetSize(width, 24)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

local function GetFontStringHeight(fontString, fallback)
    if fontString and type(fontString.GetStringHeight) == "function" then
        local height = fontString:GetStringHeight()
        if type(height) == "number" and height > 0 then return height end
    end
    return fallback
end

function Options:Build()
    if self.built then return true end

    -- If the first visit happens in combat, leave only the registered empty
    -- canvas. PLAYER_REGEN_ENABLED builds controls only while the panel remains
    -- open; otherwise the next OnShow performs the build.
    if IG:IsInCombat() then
        self.buildDeferred = true
        return false
    end

    self.buildDeferred = false
    self.built = true
    IG:BumpStat("ui.optionsBuilt")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("Interrupt Glow")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(math.max(180, GetPanelWidth() - 32))
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Choose which interrupt highlights appear and adjust how they look. Target highlights are cyan; focus highlights are amber.")

    local y = math.max(72, 44 + GetFontStringHeight(subtitle, 18) + 10)
    local function AddHeading(label)
        CreateSectionHeading(y, label)
        y = y + 22
    end
    local function AddCheck(label, tooltip, getter, setter)
        local check = CreateCheckButton(y, label, tooltip, getter, setter)
        y = y + math.max(24, GetFontStringHeight(check.Text, 18) + 2)
        return check
    end
    local buttonRowHeight = 32
    local stackButtons = GetPanelWidth() < 370
    local function AddButtonRow()
        y = y + buttonRowHeight * (stackButtons and 2 or 1)
    end

    AddHeading("Behavior")
    AddCheck(
        "Enable Interrupt Glow",
        "Turns interrupt highlighting on or off.",
        function() return DB.enabled end,
        SetMasterEnabled
    )

    AddCheck(
        "Also highlight interrupt icons in Cooldown Manager",
        "Adds highlights to interrupt abilities shown in Blizzard's Cooldown Manager.",
        function() return DB.cdm end,
        function(value)
            DB.cdm = value
            if RuntimeActive() and IG.CDM then IG.CDM:SetEnabled(value) end
        end
    )

    AddHeading("Appearance")
    AddCheck(
        "Animate highlight",
        "Adds a pulse to the highlight. Turn this off for a steady glow.",
        function() return DB.animateGlow end,
        function(value)
            if IG.Glow and type(IG.Glow.SetAnimationEnabled) == "function" then
                IG.Glow:SetAnimationEnabled(value)
            else
                DB.animateGlow = value
                IG:MarkVisualDirty()
            end
        end
    )

    AddCheck(
        "Show cooldown countdowns",
        "Shows a number while an interrupt is recharging, when the remaining time is available.",
        function() return DB.cdText end,
        function(value)
            DB.cdText = value
            if RuntimeActive() then
                if value then
                    -- Queue a fresh reading before immediately refreshing the UI.
                    IG:MarkCooldownDirty()
                    if IG.Glow then IG.Glow:EnsureCooldownTexts() end
                end
                IG:MarkVisualDirty()
            end
        end
    )

    local preview = CreateActionButton(20, y, 190, "", function()
        if IG.Glow then IG.Glow:SetTestMode(not IG.testMode) end
        if Options.previewButton then Options.previewButton:RefreshValue() end
    end)
    preview.tooltipText = "Shows a sample highlight on interrupt buttons already discovered. Enable the addon and choose Discover Buttons first. Preview is unavailable during combat and ends when combat starts."
    preview.RefreshValue = function(self)
        self:SetText(IG.testMode and "Stop highlight preview" or "Preview highlights")
    end
    Options.previewButton = preview
    preview:RefreshValue()
    y = y + 28

    local previewHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    previewHint:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -y)
    previewHint:SetWidth(math.max(180, GetPanelWidth() - 32))
    previewHint:SetJustifyH("LEFT")
    previewHint:SetWordWrap(true)
    previewHint:SetText("Preview uses buttons already found out of combat. Enable the addon, then choose Discover Buttons to find more.")
    y = y + GetFontStringHeight(previewHint, 18) + 6

    AddHeading("Diagnostics")
    AddCheck(
        "Record troubleshooting details",
        "Keeps a small local record of decisions and counters to help investigate issues. Restricted game values are not recorded.",
        function() return DB.debug end,
        function(value) DB.debug = value end
    )

    CreateActionButton(20, y, 150, "Show Debug Log", function()
        if IG.Debug then IG.Debug:Show(DB.debugKeep) end
    end)

    CreateActionButton(stackButtons and 20 or 180, y + (stackButtons and buttonRowHeight or 0), 170, "Discover Buttons", function()
        if IG:IsInCombat() then
            IG:Print("Button discovery is unavailable during combat.")
            return
        end
        if not RuntimeActive() then
            IG:Print("Enable Interrupt Glow before discovering buttons.")
            return
        end
        if IG.Buttons then IG.Buttons:DiscoverAll(true) end
        if IG.CDM then IG.CDM:ObserveExistingItems() end
    end)
    AddButtonRow()

    AddHeading("Advanced")
    AddCheck(
        "Hide highlights when interruptibility is unknown",
        "Keeps the highlight hidden when the game cannot confirm that a cast can be interrupted. Turning this off can show a false positive.",
        function() return DB.strictNI end,
        function(value)
            DB.strictNI = value
            if not RuntimeActive() then return end
            IG:MarkCastDirty()
            IG:MarkCooldownDirty()
            IG:MarkVisualDirty()
        end
    )

    AddCheck(
        "Show highlights when cooldown status is unavailable",
        "May show a highlight when the game cannot report cooldown status. This can be wrong in some content and does not override known blocked states.",
        function() return DB.optimisticRestrictedCooldown end,
        function(value)
            DB.optimisticRestrictedCooldown = value
            if RuntimeActive() then IG:MarkCooldownDirty() end
        end
    )

    return true
end

function Options:Refresh()
    if not self:Build() then return false end

    for index = 1, #self.controls do
        local control = self.controls[index]
        if control.RefreshValue then control:RefreshValue() end
    end
    if self.previewButton then self.previewButton:RefreshValue() end
    return true
end

function Options:Open()
    if not self.categoryID or not Settings or type(Settings.OpenToCategory) ~= "function" then
        IG:Print("Interrupt Glow settings are unavailable.")
        return false
    end
    Settings.OpenToCategory(self.categoryID)
    return true
end

function Options:OnCombatEnded()
    if not self.buildDeferred then return false end
    if type(panel.IsShown) == "function" and not panel:IsShown() then
        return false
    end
    return self:Refresh()
end

local function RefreshPanel()
    return Options:Refresh()
end

local function ResetDefaults()
    DB.cdText = false
    DB.cdm = true
    DB.strictNI = true
    DB.optimisticRestrictedCooldown = false
    DB.animateGlow = true
    DB.debug = false
    DB.debugChat = false
    DB.debugKeep = 400

    SetMasterEnabled(true)
    if IG.Glow and type(IG.Glow.SetAnimationEnabled) == "function" then
        IG.Glow:SetAnimationEnabled(true)
    end
    if RuntimeActive() and IG.CDM then IG.CDM:SetEnabled(true) end
    ApplyDefaultsOrFullRefresh()
    Options:Refresh()
end

local function CommitPanel()
    -- Controls apply immediately; no pending settings transaction is kept.
end

-- Native Canvas Settings panel lifecycle.
panel.OnRefresh = RefreshPanel
panel.OnDefault = ResetDefaults
panel.OnCommit = CommitPanel
panel:SetScript("OnShow", RefreshPanel)

if Settings
    and type(Settings.RegisterCanvasLayoutCategory) == "function"
    and type(Settings.RegisterAddOnCategory) == "function"
then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    if category then
        if type(category.GetID) == "function" then
            Options.categoryID = category:GetID()
        end
        Settings.RegisterAddOnCategory(category)
    end
end
