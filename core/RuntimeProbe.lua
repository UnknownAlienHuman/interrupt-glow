local IG = _G.InterruptGlow
if not IG then return end

local Probe = {
    active = false,
    marks = {},
    restrictionTransitions = {},
    lastReport = nil,
    startProfile = nil,
    endProfile = nil,
    diagnosticsOwner = {},
    kbCommit = "5a992ae702a278f3893c7e8f1b212583311438b5",
    sourceCommit = "027d26c3406d3de2cbd2b1f67d468fe033a1bcd4",
}
IG.RuntimeProbe = Probe
IG:RegisterModule("RuntimeProbe", Probe)

local _G = _G
local C_AddOnProfiler = _G.C_AddOnProfiler
local C_AddOns = _G.C_AddOns
local C_Secrets = _G.C_Secrets
local CreateFrame = _G.CreateFrame
local GetBuildInfo = _G.GetBuildInfo
local GetInstanceInfo = _G.GetInstanceInfo
local IsInInstance = _G.IsInInstance
local UnitGUID = _G.UnitGUID
local UnitClassBase = _G.UnitClassBase
local UnitAffectingCombat = _G.UnitAffectingCombat
local type = type
local pairs = pairs
local next = next
local tostring = tostring
local tonumber = tonumber
local pcall = pcall
local table_sort = table.sort
local math_floor = math.floor

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and IG.CanAccess(value) then return value end
    return nil
end

local function SafeBooleanCall(fn, ...)
    local value = SafeCall(fn, ...)
    if value == true then return true end
    if value == false then return false end
    return nil
end

local function SafeString(value, fallback)
    if not IG.CanAccess(value) then return fallback or "<restricted>" end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end
    if value == nil then return fallback or "nil" end
    return fallback or "<non-scalar>"
end

local function CopyScalarMap(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if IG.CanAccess(key) and type(key) == "string" and IG.CanAccess(value) then
            local valueType = type(value)
            if valueType == "string" or valueType == "number" or valueType == "boolean" then
                result[key] = value
            end
        end
    end
    return result
end

local function FormatNumber(value)
    if type(value) ~= "number" then return "n/a" end
    return ("%.4f"):format(value)
end

local function FormatBoolean(value)
    if value == true then return "true" end
    if value == false then return "false" end
    return "unknown"
end

local function CaptureProfilerSnapshot()
    if not C_AddOnProfiler or type(C_AddOnProfiler.GetAddOnPerformanceInfo) ~= "function" then
        return nil
    end

    local ok, info = pcall(C_AddOnProfiler.GetAddOnPerformanceInfo, IG.name)
    if not ok or not IG.CanAccess(info) or type(info) ~= "table" then return nil end

    local result = {}
    for key, value in pairs(info) do
        if IG.CanAccess(key) and type(key) == "string" and IG.CanAccess(value) then
            if type(value) == "number" then result[key] = value end
        end
    end
    return result
end

local function SnapshotDelta(startSnapshot, endSnapshot)
    local delta = {}
    for key, endValue in pairs(endSnapshot or {}) do
        local startValue = startSnapshot and startSnapshot[key]
        if type(endValue) == "number" and type(startValue) == "number" then
            delta[key] = endValue - startValue
        elseif type(endValue) == "number" then
            delta[key] = endValue
        end
    end
    return delta
end

local function CaptureBuild()
    if type(GetBuildInfo) ~= "function" then
        return {
            version = "<unavailable>",
            build = "<unavailable>",
            date = "<unavailable>",
            interface = "<unavailable>",
        }
    end

    local ok, version, build, date, interface = pcall(GetBuildInfo)
    if not ok then
        return {
            version = "<error>",
            build = "<error>",
            date = "<error>",
            interface = "<error>",
        }
    end

    return {
        version = SafeString(version),
        build = SafeString(build),
        date = SafeString(date),
        interface = SafeString(interface),
    }
end

local function CaptureInstance()
    local inInstance, instanceType = nil, nil
    if type(IsInInstance) == "function" then
        local ok, value, kind = pcall(IsInInstance)
        if ok and IG.CanAccess(value) and IG.CanAccess(kind) then
            inInstance = value == true
            if type(kind) == "string" then instanceType = kind end
        end
    end

    local name, instanceID, difficultyID
    if type(GetInstanceInfo) == "function" then
        local ok, rawName, _, rawDifficultyID, _, _, _, _, rawInstanceID = pcall(GetInstanceInfo)
        if ok then
            if IG.CanAccess(rawName) and type(rawName) == "string" then name = rawName end
            if IG.CanAccess(rawDifficultyID) and type(rawDifficultyID) == "number" then
                difficultyID = rawDifficultyID
            end
            if IG.CanAccess(rawInstanceID) and type(rawInstanceID) == "number" then
                instanceID = rawInstanceID
            end
        end
    end

    return {
        inInstance = inInstance,
        instanceType = instanceType,
        name = name,
        instanceID = instanceID,
        difficultyID = difficultyID,
    }
end

local function CaptureProviders()
    local providers = {}
    local names = {
        "Blizzard_CooldownViewer",
        "Bartender4",
        "Dominos",
        "ElvUI",
        "ButtonForge",
    }

    for index = 1, #names do
        local name = names[index]
        providers[name] = IG:IsAddOnFullyLoaded(name)
    end
    return providers
end

local function CaptureUnitIdentity(unit)
    local guid = SafeCall(UnitGUID, unit)
    local classBase = SafeCall(UnitClassBase, unit)
    local combat = SafeBooleanCall(UnitAffectingCombat, unit)
    return {
        guid = SafeString(guid),
        classBase = SafeString(classBase),
        combat = combat,
    }
end

local function CaptureSecretPolicy(record)
    local result = {
        action = nil,
        spell = nil,
        cast = {},
    }

    if C_Secrets then
        if record and record.sourceKind == "action"
            and type(C_Secrets.ShouldActionCooldownBeSecret) == "function"
        then
            result.action = SafeBooleanCall(
                C_Secrets.ShouldActionCooldownBeSecret,
                record.sourceID
            )
        end

        if record and type(record.canonicalSpellID) == "number" then
            if type(C_Secrets.ShouldSpellCooldownBeSecret) == "function" then
                result.spell = SafeBooleanCall(
                    C_Secrets.ShouldSpellCooldownBeSecret,
                    record.canonicalSpellID
                )
            elseif type(C_Secrets.GetSpellCooldownSecrecy) == "function" then
                local secrecy = SafeCall(C_Secrets.GetSpellCooldownSecrecy, record.canonicalSpellID)
                result.spell = secrecy ~= nil and secrecy ~= false
            end
        end

        if type(C_Secrets.ShouldUnitSpellCastingBeSecret) == "function" then
            result.cast.target = SafeBooleanCall(
                C_Secrets.ShouldUnitSpellCastingBeSecret,
                "target"
            )
            result.cast.focus = SafeBooleanCall(
                C_Secrets.ShouldUnitSpellCastingBeSecret,
                "focus"
            )
        end
    end
    return result
end

local function CaptureRepresentativeRecord()
    for record in pairs(IG.InterruptRecords or {}) do
        return record
    end
    return nil
end

local function CaptureAbilityState()
    local result = {}
    for key, ability in pairs(IG.AbilityStates or {}) do
        if type(key) == "number" or type(key) == "string" then
            result[#result + 1] = {
                key = SafeString(key),
                spell = SafeString(ability.canonicalSpellID),
                sourceKind = SafeString(ability.sourceKind),
                sourceID = SafeString(ability.sourceID),
                ready = ability.ready == true,
                restricted = ability.restricted == true,
                hardRestricted = ability.hardRestricted == true,
                needsPoll = ability.needsPoll == true,
                deadline = type(ability.deadline) == "number" and ability.deadline or nil,
                records = 0,
            }

            local entry = result[#result]
            for _ in pairs(ability.records or {}) do entry.records = entry.records + 1 end
        end
    end

    table_sort(result, function(left, right) return left.key < right.key end)
    return result
end

local function CaptureCastState()
    local result = {}
    for _, unit in ipairs({ "target", "focus" }) do
        local state = IG.CastState and IG.CastState[unit]
        if state then
            result[unit] = {
                active = state.active == true,
                hostile = state.hostile == true,
                niState = SafeString(state.niState),
                castBarID = SafeString(state.castBarID),
                isChannel = state.isChannel == true,
                channelSuppressed = state.channelSuppressed == true,
                lastEvent = SafeString(state.lastEvent),
            }
        end
    end
    return result
end

local function CaptureWorkerState()
    local worker = IG.Worker
    local result = {}

    local function Add(name, frame)
        if not frame then return end
        local mode = worker and worker.GetMode and worker:GetMode(frame)
        local shown = frame.IsShown and frame:IsShown() or nil
        result[name] = {
            mode = SafeString(mode),
            shown = shown == true,
        }
    end

    Add("flush", IG.flushFrame)
    Add("prewarm", IG.Glow and IG.Glow.prewarmFrame)
    Add("runtime", IG.Glow and IG.Glow.runtimeFrame)
    return result
end

local function CountWeakMap(map)
    local count = 0
    for _ in pairs(map or {}) do count = count + 1 end
    return count
end

local function CurrentSummary()
    local representative = CaptureRepresentativeRecord()
    return {
        build = CaptureBuild(),
        instance = CaptureInstance(),
        providers = CaptureProviders(),
        player = CaptureUnitIdentity("player"),
        counts = {
            observedButtons = CountWeakMap(IG.ObservedButtons),
            pendingButtons = CountWeakMap(IG.PendingButtons),
            interruptRecords = CountWeakMap(IG.InterruptRecords),
            abilities = CountWeakMap(IG.AbilityStates),
        },
        secretPolicy = CaptureSecretPolicy(representative),
        casts = CaptureCastState(),
        abilities = CaptureAbilityState(),
        workers = CaptureWorkerState(),
        stats = CopyScalarMap(IG.Stats),
        database = {
            schema = IG.DB and IG.DB.schema,
            producerVersion = IG.DB and IG.DB.producerVersion,
            interface = IG.DB and IG.DB.interface,
        },
    }
end

local function SortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table_sort(keys)
    return keys
end

local function AppendMap(lines, prefix, map)
    local keys = SortedKeys(map)
    for index = 1, #keys do
        local key = keys[index]
        lines[#lines + 1] = prefix .. key .. "=" .. SafeString(map[key])
    end
end

local function AppendProfiler(lines, label, snapshot)
    lines[#lines + 1] = "[profiler." .. label .. "]"
    if not snapshot then
        lines[#lines + 1] = "available=false"
        return
    end
    lines[#lines + 1] = "available=true"
    local keys = SortedKeys(snapshot)
    for index = 1, #keys do
        local key = keys[index]
        lines[#lines + 1] = key .. "=" .. FormatNumber(snapshot[key])
    end
end

function Probe:Start(label)
    if self.active then
        IG:Print("A runtime capture is already active.")
        return false
    end

    self.active = true
    self.label = type(label) == "string" and label ~= "" and label or "unnamed"
    self.startedAt = IG:Now()
    self.startSummary = CurrentSummary()
    self.startProfile = CaptureProfilerSnapshot()
    self.endProfile = nil
    self.marks = {}
    self.restrictionTransitions = {}
    self.lastRestrictionType = nil
    self.lastRestrictionState = nil
    self.lastReport = nil
    IG:StartProfileCounters(self.diagnosticsOwner)
    IG:BumpStat("probe.starts")
    IG:Print("Runtime capture started: " .. self.label)
    return true
end

function Probe:AddMark(label, announce)
    if not self.active then
        if announce then IG:Print("No runtime capture is active.") end
        return false
    end

    local mark = {
        label = type(label) == "string" and label ~= "" and label
            or ("mark-" .. tostring(#self.marks + 1)),
        elapsed = IG:Now() - self.startedAt,
        profile = CaptureProfilerSnapshot(),
        stats = CopyScalarMap(IG.Stats),
        counts = {
            observedButtons = CountWeakMap(IG.ObservedButtons),
            pendingButtons = CountWeakMap(IG.PendingButtons),
            interruptRecords = CountWeakMap(IG.InterruptRecords),
            abilities = CountWeakMap(IG.AbilityStates),
        },
        workers = CaptureWorkerState(),
    }
    self.marks[#self.marks + 1] = mark
    IG:BumpStat("probe.marks")
    if announce then IG:Print("Runtime capture mark: " .. mark.label) end
    return true
end

function Probe:OnRestrictionStateChanged(restrictionType, state)
    if not self.active then return end

    local safeType = nil
    if IG.CanAccess(restrictionType) then
        local valueType = type(restrictionType)
        if valueType == "string" or valueType == "number" then safeType = restrictionType end
    end

    local safeState = nil
    if IG.CanAccess(state) then
        local valueType = type(state)
        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            safeState = state
        end
    end

    self.lastRestrictionType = safeType
    self.lastRestrictionState = safeState
    self.restrictionTransitions[#self.restrictionTransitions + 1] = {
        elapsed = IG:Now() - self.startedAt,
        restrictionType = safeType,
        state = safeState,
    }

    -- Segment cumulative native profiler evidence around restriction transitions.
    self:AddMark("restriction:" .. SafeString(safeType), false)
end

function Probe:BuildReport()
    local endSummary = self.endSummary or CurrentSummary()
    local lines = {
        "Interrupt Glow runtime capture",
        "label=" .. SafeString(self.label),
        "addonVersion=" .. SafeString(IG.version),
        "kbCommit=" .. self.kbCommit,
        "wowUiSourceCommit=" .. self.sourceCommit,
        "duration=" .. FormatNumber((self.endedAt or IG:Now()) - (self.startedAt or IG:Now())),
        "",
        "[build]",
        "version=" .. SafeString(endSummary.build.version),
        "build=" .. SafeString(endSummary.build.build),
        "date=" .. SafeString(endSummary.build.date),
        "interface=" .. SafeString(endSummary.build.interface),
        "savedSchema=" .. SafeString(endSummary.database.schema),
        "savedProducerVersion=" .. SafeString(endSummary.database.producerVersion),
        "savedInterface=" .. SafeString(endSummary.database.interface),
        "",
        "[instance]",
        "inInstance=" .. FormatBoolean(endSummary.instance.inInstance),
        "instanceType=" .. SafeString(endSummary.instance.instanceType),
        "name=" .. SafeString(endSummary.instance.name),
        "instanceID=" .. SafeString(endSummary.instance.instanceID),
        "difficultyID=" .. SafeString(endSummary.instance.difficultyID),
        "",
        "[providers]",
    }

    AppendMap(lines, "", endSummary.providers)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[counts]"
    AppendMap(lines, "", endSummary.counts)

    lines[#lines + 1] = ""
    lines[#lines + 1] = "[secretPolicy]"
    lines[#lines + 1] = "action=" .. FormatBoolean(endSummary.secretPolicy.action)
    lines[#lines + 1] = "spell=" .. FormatBoolean(endSummary.secretPolicy.spell)
    lines[#lines + 1] = "targetCast=" .. FormatBoolean(endSummary.secretPolicy.cast.target)
    lines[#lines + 1] = "focusCast=" .. FormatBoolean(endSummary.secretPolicy.cast.focus)

    lines[#lines + 1] = ""
    lines[#lines + 1] = "[workers]"
    for _, name in ipairs({ "flush", "prewarm", "runtime" }) do
        local worker = endSummary.workers[name]
        if worker then
            lines[#lines + 1] = name .. ".mode=" .. SafeString(worker.mode)
            lines[#lines + 1] = name .. ".shown=" .. tostring(worker.shown)
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "[casts]"
    for _, unit in ipairs({ "target", "focus" }) do
        local cast = endSummary.casts[unit]
        if cast then
            lines[#lines + 1] = unit .. ".active=" .. tostring(cast.active)
            lines[#lines + 1] = unit .. ".hostile=" .. tostring(cast.hostile)
            lines[#lines + 1] = unit .. ".ni=" .. cast.niState
            lines[#lines + 1] = unit .. ".castBarID=" .. cast.castBarID
            lines[#lines + 1] = unit .. ".channel=" .. tostring(cast.isChannel)
            lines[#lines + 1] = unit .. ".suppressed=" .. tostring(cast.channelSuppressed)
            lines[#lines + 1] = unit .. ".lastEvent=" .. cast.lastEvent
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "[abilities]"
    if #endSummary.abilities == 0 then
        lines[#lines + 1] = "none=true"
    else
        for index = 1, #endSummary.abilities do
            local ability = endSummary.abilities[index]
            lines[#lines + 1] = table.concat({
                ability.key,
                "spell=" .. ability.spell,
                "source=" .. ability.sourceKind .. ":" .. ability.sourceID,
                "ready=" .. tostring(ability.ready),
                "restricted=" .. tostring(ability.restricted),
                "hard=" .. tostring(ability.hardRestricted),
                "poll=" .. tostring(ability.needsPoll),
                "deadline=" .. SafeString(ability.deadline),
                "records=" .. tostring(ability.records),
            }, " ")
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "[restrictionTransitions]"
    if #self.restrictionTransitions == 0 then
        lines[#lines + 1] = "none=true"
    else
        for index = 1, #self.restrictionTransitions do
            local transition = self.restrictionTransitions[index]
            lines[#lines + 1] = ("%d elapsed=%s type=%s state=%s"):format(
                index,
                FormatNumber(transition.elapsed),
                SafeString(transition.restrictionType),
                SafeString(transition.state)
            )
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "[marks]"
    if #self.marks == 0 then
        lines[#lines + 1] = "none=true"
    else
        for index = 1, #self.marks do
            local mark = self.marks[index]
            lines[#lines + 1] = ("%d label=%s elapsed=%s observed=%s pending=%s interrupt=%s abilities=%s"):format(
                index,
                SafeString(mark.label),
                FormatNumber(mark.elapsed),
                SafeString(mark.counts.observedButtons),
                SafeString(mark.counts.pendingButtons),
                SafeString(mark.counts.interruptRecords),
                SafeString(mark.counts.abilities)
            )
        end
    end

    lines[#lines + 1] = ""
    AppendProfiler(lines, "start", self.startProfile)
    lines[#lines + 1] = ""
    AppendProfiler(lines, "end", self.endProfile)
    lines[#lines + 1] = ""
    AppendProfiler(lines, "delta", SnapshotDelta(self.startProfile, self.endProfile))

    lines[#lines + 1] = ""
    lines[#lines + 1] = "[stats]"
    AppendMap(lines, "", endSummary.stats)

    return table.concat(lines, "\n")
end

local function EnsureReportFrame()
    if Probe.reportFrame then return Probe.reportFrame end
    if type(CreateFrame) ~= "function" then return nil end

    local frame = CreateFrame("Frame", "InterruptGlowRuntimeReportFrame", _G.UIParent, "BackdropTemplate")
    frame:SetSize(820, 600)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Interrupt Glow Runtime Capture")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 24, -48)
    scrollFrame:SetPoint("BOTTOMRIGHT", -38, 48)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(740)
    editBox:SetTextInsets(4, 4, 4, 4)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scrollFrame:SetScrollChild(editBox)

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(90, 24)
    close:SetPoint("BOTTOMRIGHT", -24, 16)
    close:SetText("Close")
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.editBox = editBox
    frame:Hide()
    Probe.reportFrame = frame
    return frame
end

function Probe:Show()
    if not self.lastReport then
        IG:Print("No completed runtime capture is available.")
        return
    end

    local frame = EnsureReportFrame()
    if not frame then
        IG:Print("Runtime report UI is unavailable.")
        return
    end

    frame.editBox:SetText(self.lastReport)
    frame.editBox:HighlightText(0, 0)
    frame.editBox:SetCursorPosition(0)
    frame:Show()
end

function Probe:Stop()
    if not self.active then
        IG:Print("No runtime capture is active.")
        return false
    end

    self:AddMark("final", false)
    self.endProfile = CaptureProfilerSnapshot()
    self.endSummary = CurrentSummary()
    self.endedAt = IG:Now()
    self.active = false
    IG:StopProfileCounters(self.diagnosticsOwner)
    self.lastReport = self:BuildReport()
    IG:BumpStat("probe.stops")
    IG:Print("Runtime capture completed: " .. SafeString(self.label))
    self:Show()
    return true
end

function Probe:Toggle(label)
    if self.active then return self:Stop() end
    return self:Start(label)
end
