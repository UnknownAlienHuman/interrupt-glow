local IG = _G.InterruptGlow
if not IG then return end

local DB = IG.DB
local Options = { built = false, controls = {} }
IG.Options = Options
IG:RegisterModule("Options", Options)

-- Register only a bare canvas at addon load. Font strings, check buttons and
-- action buttons are created on the first Settings visit, not during login.
local panel = CreateFrame("Frame", "InterruptGlowOptionsPanel", UIParent)
panel.name = "Interrupt Glow"
Options.panel = panel

local function ApplyDefaultsOrFullRefresh()
    IG:MarkAllButtonsDirty()
    IG:MarkCastDirty()
    IG:MarkCooldownDirty(false)
    IG:MarkVisualDirty()
end

local function CreateCheckButton(anchor, offsetY, label, tooltip, getter, setter)
    local check = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
    check.Text:SetText(label)
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

function Options:Build()
    if self.built then return end
    self.built = true
    IG:BumpStat("ui.optionsBuilt")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Interrupt Glow 1.1")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(620)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Event-driven target/focus interrupt highlighting. No macro-body, frame or nameplate scans.")

    local enabled = CreateCheckButton(
        subtitle,
        -14,
        "Enable Interrupt Glow",
        "Master switch for the addon-owned overlays.",
        function() return DB.enabled end,
        function(value)
            DB.enabled = value
            -- Readiness work sleeps while disabled. Re-enabling during an
            -- existing relevant cast must take one fresh snapshot before glow.
            if value then IG:MarkCooldownDirty(false) end
            IG:MarkVisualDirty()
        end
    )

    local cdText = CreateCheckButton(
        enabled,
        -10,
        "Show accessible cooldown countdown",
        "Shows a custom number only when remaining time is accessible. Blizzard-owned cooldown UI remains authoritative for restricted values.",
        function() return DB.cdText end,
        function(value)
            DB.cdText = value
            if value then
                -- Mark pending before the immediate UI refresh so a stale
                -- deadline cannot flash while the fresh snapshot is queued.
                IG:MarkCooldownDirty(false)
                if IG.Glow then IG.Glow:EnsureCooldownTexts() end
            end
            IG:MarkVisualDirty()
        end
    )

    local cdm = CreateCheckButton(
        cdText,
        -10,
        "Mirror onto Blizzard Cooldown Viewer interrupt icons",
        "Uses Cooldown Viewer pooled-item lifecycle hooks; no child-tree scan or texture matching.",
        function() return DB.cdm end,
        function(value)
            DB.cdm = value
            if IG.CDM then IG.CDM:SetEnabled(value) end
        end
    )

    local strictNI = CreateCheckButton(
        cdm,
        -10,
        "Block ordinary unknown interruptibility",
        "Secret interruptibility is sent directly to a visual alpha gate. This option controls only accessible nil/unknown states.",
        function() return DB.strictNI end,
        function(value)
            DB.strictNI = value
            -- A restricted current cast must be sampled again so the raw value
            -- reaches the alpha sink. Turning strict mode off can also make an
            -- existing unknown cast newly relevant, so refresh readiness once.
            IG:MarkCastDirty()
            IG:MarkCooldownDirty(false)
            IG:MarkVisualDirty()
        end
    )

    local optimisticCD = CreateCheckButton(
        strictNI,
        -10,
        "Allow glow when cooldown readiness is fully restricted",
        "Compatibility mode. It may allow a cooldown-readiness false positive, but never overrides blocked or inaccessible usability, pet state, or Loss of Control.",
        function() return DB.optimisticRestrictedCooldown end,
        function(value)
            DB.optimisticRestrictedCooldown = value
            IG:MarkCooldownDirty(false)
        end
    )

    CreateCheckButton(
        optimisticCD,
        -10,
        "Enable debug ring buffer",
        "Stores normalized decisions and counters only. Raw secret payloads are never logged.",
        function() return DB.debug end,
        function(value) DB.debug = value end
    )

    local debug = self.controls[#self.controls]
    local showLog = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    showLog:SetPoint("TOPLEFT", debug, "BOTTOMLEFT", 4, -12)
    showLog:SetSize(150, 24)
    showLog:SetText("Show Debug Log")
    showLog:SetScript("OnClick", function()
        if IG.Debug then IG.Debug:Show(DB.debugKeep) end
    end)

    local rescan = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    rescan:SetPoint("LEFT", showLog, "RIGHT", 10, 0)
    rescan:SetSize(160, 24)
    rescan:SetText("Discover Buttons")
    rescan:SetScript("OnClick", function()
        if IG:IsInCombat() then
            IG:Print("Discovery is unavailable during combat.")
            return
        end
        if IG.Buttons then IG.Buttons:DiscoverAll(true) end
        if IG.CDM then IG.CDM:ObserveExistingItems() end
    end)
end

function Options:Refresh()
    self:Build()
    for index = 1, #self.controls do
        local control = self.controls[index]
        if control.RefreshValue then control:RefreshValue() end
    end
end

local function RefreshPanel()
    Options:Refresh()
end

local function ResetDefaults()
    DB.enabled = true
    DB.cdText = false
    DB.cdm = true
    DB.strictNI = true
    DB.optimisticRestrictedCooldown = false
    DB.debug = false
    if IG.CDM then IG.CDM:SetEnabled(true) end
    ApplyDefaultsOrFullRefresh()
    Options:Refresh()
end

local function CommitPanel()
    -- Controls apply immediately; no deferred transaction is kept.
end

-- Current Canvas Settings contract (10.0+, updated in 11.0/12.x).
panel.OnRefresh = RefreshPanel
panel.OnDefault = ResetDefaults
panel.OnCommit = CommitPanel

-- Legacy Interface Options contract retained for compatibility fallback.
panel.refresh = RefreshPanel
panel.default = ResetDefaults
panel.okay = CommitPanel

panel:SetScript("OnShow", RefreshPanel)

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end
