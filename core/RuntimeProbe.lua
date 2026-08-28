local IG = _G.InterruptGlow
if not IG then return end

local RuntimeProbe = {
    active = false,
    label = nil,
    startedAt = nil,
    stoppedAt = nil,
    marks = {},
    restrictionTransitions = {},
    profilerStart = nil,
    profilerStop = nil,
    lastReport = nil,
    lastRestrictionType = nil,
    lastRestrictionState = nil,
}
IG.RuntimeProbe = RuntimeProbe
IG:RegisterModule("RuntimeProbe", RuntimeProbe)

local _G = _G
local C_Secrets = _G.C_Secrets
local Enum = _G.Enum
local GetBuildInfo = _G.GetBuildInfo
local GetInstanceInfo = _G.GetInstanceInfo
local date = _G.date
local pcall = pcall
local type = type
local tostring = tostring
local pairs = pairs
local sort = table.sort
local concat = table.concat
local format = string.format

local KB_COMMIT = "071e6a755f4613908d019b23e8e121b0bf91ce5d"
local PROVIDERS = {
    "Bartender4",
    "ElvUI",
    "Dominos",
    "ButtonForge",
    "Blizzard_CooldownViewer",
}

local function SafeScalar(value, fallback)
    if not IG.CanAccess(value) then return "<inaccessible>" end
    if value == nil then return fallback or "nil" end

    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end
    return "<" .. valueType .. ">"
end

local function CaptureScalar(value)
    if not IG.CanAccess(value) then return nil end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end
    return nil
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return false, "<unavailable>" end

    -- Runtime probes are explicit diagnostics. pcall contains an API error but
    -- never declassifies a value; accessibility is still checked immediately.
    local ok, value = pcall(fn, ...)
    if not ok then return false, "<error>" end
    if not IG.CanAccess(value) then return false, "<inaccessible>" end
    return true, value
end

local function FormatBoolCall(fn, ...)
    local ok, value = SafeCall(fn, ...)
    if not ok then return SafeScalar(value) end
    if value == true then return "true" end
    if value == false then return "false" end
    return SafeScalar(value)
end

local function GetSecrecyName(value)
    if not IG.CanAccess(value) then return "<inaccessible>" end

    local secrecy = Enum and Enum.SecrecyLevel
    if secrecy then
        if value == secrecy.NeverSecret then return "NeverSecret" end
        if value == secrecy.AlwaysSecret then return "AlwaysSecret" end
        if value == secrecy.ContextuallySecret then return "ContextuallySecret" end
    end
    return SafeScalar(value)
end

local function FormatSecrecyCall(fn, spellID)
    local ok, value = SafeCall(fn, spellID)
    if not ok then return SafeScalar(value) end
    return GetSecrecyName(value)
end

local function NormalizeLabel(value, fallback)
    if type(value) ~= "string" then return fallback or "" end
    value = value:gsub("[%c]", " ")
    if #value > 96 then value = value:sub(1, 96) end
    return value
end

local function AddLine(lines, text)
    lines[#lines + 1] = text
end

local function SortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb and (ta == "number" or ta == "string") then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function CollectActiveSpellIDs()
    local set = {}
    local data = IG.Data

    if data and type(data.GetActiveInterrupts) == "function" then
        for spellID in data:GetActiveInterrupts() do
            if type(spellID) == "number" then set[spellID] = true end
        end
    end

    for _, ability in pairs(IG.AbilityStates or {}) do
        local spellID = ability and ability.canonicalSpellID
        if type(spellID) == "number" then set[spellID] = true end
    end

    return SortedKeys(set)
end

local function CollectActionSlots()
    local set = {}
    for _, ability in pairs(IG.AbilityStates or {}) do
        if ability and ability.sourceKind == "action" and type(ability.sourceID) == "number" then
            set[ability.sourceID] = true
        end
    end
    return SortedKeys(set)
end

local function CaptureProfiler()
    if IG.Debug and type(IG.Debug.ProfilerSnapshot) == "function" then
        return IG.Debug:ProfilerSnapshot()
    end
    return nil
end

local function AppendBuildSection(lines)
    AddLine(lines, "[build]")

    if type(GetBuildInfo) == "function" then
        local version, build, buildDate, interfaceVersion = GetBuildInfo()
        AddLine(lines, "version=" .. SafeScalar(version))
        AddLine(lines, "build=" .. SafeScalar(build))
        AddLine(lines, "buildDate=" .. SafeScalar(buildDate))
        AddLine(lines, "interface=" .. SafeScalar(interfaceVersion))
    else
        AddLine(lines, "GetBuildInfo=<unavailable>")
    end

    AddLine(lines, "addon=" .. SafeScalar(IG.name))
    AddLine(lines, "addonVersion=" .. SafeScalar(IG.version))
    AddLine(lines, "repository=UnknownAlienHuman/interrupt-glow")
    AddLine(lines, "expectedInterface=" .. SafeScalar(IG.Data and IG.Data.interface))
    AddLine(lines, "sourceBuild=" .. SafeScalar(IG.Data and IG.Data.wowBuild))
    AddLine(lines, "sourceCommit=" .. SafeScalar(IG.Data and IG.Data.sourceCommit))
    AddLine(lines, "kbCommit=" .. KB_COMMIT)
    AddLine(lines, "savedSchema=" .. SafeScalar(IG.DB and IG.DB.schema))
    AddLine(lines, "savedProducerVersion=" .. SafeScalar(IG.DB and IG.DB.producerVersion))
    AddLine(lines, "savedInterface=" .. SafeScalar(IG.DB and IG.DB.interface))
    AddLine(lines, "capturedAt=" .. SafeScalar(type(date) == "function" and date("!%Y-%m-%dT%H:%M:%SZ") or nil))
end

local function AppendContextSection(lines)
    AddLine(lines, "")
    AddLine(lines, "[context]")
    AddLine(lines, "combat=" .. tostring(IG:IsInCombat()))

    if type(GetInstanceInfo) == "function" then
        local name, instanceType, difficultyID, difficultyName, maxPlayers,
            dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, lfgDungeonID = GetInstanceInfo()

        AddLine(lines, "instanceName=" .. SafeScalar(name))
        AddLine(lines, "instanceType=" .. SafeScalar(instanceType))
        AddLine(lines, "difficultyID=" .. SafeScalar(difficultyID))
        AddLine(lines, "difficultyName=" .. SafeScalar(difficultyName))
        AddLine(lines, "maxPlayers=" .. SafeScalar(maxPlayers))
        AddLine(lines, "dynamicDifficulty=" .. SafeScalar(dynamicDifficulty))
        AddLine(lines, "isDynamic=" .. SafeScalar(isDynamic))
        AddLine(lines, "instanceID=" .. SafeScalar(instanceID))
        AddLine(lines, "instanceGroupSize=" .. SafeScalar(instanceGroupSize))
        AddLine(lines, "lfgDungeonID=" .. SafeScalar(lfgDungeonID))
    else
        AddLine(lines, "GetInstanceInfo=<unavailable>")
    end

    AddLine(lines, "lastRestrictionType=" .. SafeScalar(RuntimeProbe.lastRestrictionType, "unobserved"))
    AddLine(lines, "lastRestrictionState=" .. SafeScalar(RuntimeProbe.lastRestrictionState, "unobserved"))
    for index = 1, #RuntimeProbe.restrictionTransitions do
        local transition = RuntimeProbe.restrictionTransitions[index]
        AddLine(lines, format(
            "restriction.%d=%.3f type=%s state=%s",
            index,
            transition.elapsed,
            SafeScalar(transition.restrictionType),
            SafeScalar(transition.state)
        ))
    end
end

local function AppendProviderSection(lines)
    AddLine(lines, "")
    AddLine(lines, "[providers]")

    for index = 1, #PROVIDERS do
        local name = PROVIDERS[index]
        AddLine(lines, name .. ".loaded=" .. tostring(IG:IsAddOnFullyLoaded(name)))
    end

    local buttons = IG.Buttons
    AddLine(lines, "native.attached=" .. SafeScalar(buttons and buttons.nativeAttached))
    AddLine(lines, "dominos.attached=" .. SafeScalar(buttons and buttons.dominosAttached))
    AddLine(lines, "buttonForge.attached=" .. SafeScalar(buttons and buttons.buttonForgeAttached))
    AddLine(lines, "cooldownViewer.attached=" .. SafeScalar(IG.CDM and IG.CDM.attached))
end

local function AppendWorkerSection(lines)
    AddLine(lines, "")
    AddLine(lines, "[workers]")

    local worker = IG.Worker
    local supportsFlush = false
    local supportsPrewarm = false
    local supportsRuntime = false
    if worker and type(worker.SupportsOnUpdateMode) == "function" then
        supportsFlush = worker:SupportsOnUpdateMode(IG.flushFrame) == true
        supportsPrewarm = worker:SupportsOnUpdateMode(IG.Glow and IG.Glow.prewarmFrame) == true
        supportsRuntime = worker:SupportsOnUpdateMode(IG.Glow and IG.Glow.runtimeFrame) == true
    end

    AddLine(lines, "flush.onUpdateMode=" .. tostring(supportsFlush))
    AddLine(lines, "flush.dirty=" .. tostring(IG:HasDirtyWork()))
    AddLine(lines, "prewarm.onUpdateMode=" .. tostring(supportsPrewarm))
    AddLine(lines, "prewarm.scheduled=" .. SafeScalar(IG.Glow and IG.Glow.prewarmScheduled))
    AddLine(lines, "prewarm.pending=" .. tostring(
        IG.Glow ~= nil and IG.Glow.prewarmHead <= IG.Glow.prewarmTail
    ))
    AddLine(lines, "runtime.onUpdateMode=" .. tostring(supportsRuntime))
    AddLine(lines, "runtime.enabled=" .. SafeScalar(IG.Glow and IG.Glow.runtimeWorkerEnabled))
end

local function AppendCaptureSection(lines)
    AddLine(lines, "")
    AddLine(lines, "[capture]")
    AddLine(lines, "active=" .. tostring(RuntimeProbe.active))
    AddLine(lines, "label=" .. SafeScalar(RuntimeProbe.label, ""))

    local endTime = RuntimeProbe.active and IG:Now() or RuntimeProbe.stoppedAt
    if type(RuntimeProbe.startedAt) == "number" and type(endTime) == "number" then
        AddLine(lines, format("duration=%.3f", endTime - RuntimeProbe.startedAt))
    else
        AddLine(lines, "duration=0")
    end

    for index = 1, #RuntimeProbe.marks do
        local mark = RuntimeProbe.marks[index]
        AddLine(lines, format("mark.%d=%.3f %s", index, mark.elapsed, SafeScalar(mark.label)))
    end
end

local function AppendCastSection(lines)
    AddLine(lines, "")
    AddLine(lines, "[casts]")

    local units = { "target", "focus" }
    for index = 1, #units do
        local unit = units[index]
        local state = IG.CastState and IG.CastState[unit] or nil
        AddLine(lines, unit .. ".active=" .. SafeScalar(state and state.active))
        AddLine(lines, unit .. ".hostile=" .. SafeScalar(state and state.hostile))
        AddLine(lines, unit .. ".isChannel=" .. SafeScalar(state and state.isChannel))
        AddLine(lines, unit .. ".niState=" .. SafeScalar(state and state.niState))
        AddLine(lines, unit .. ".castBarID=" .. SafeScalar(state and state.castBarID))
        AddLine(lines, unit .. ".channelSuppressed=" .. SafeScalar(state and state.channelSuppressed))
        AddLine(lines, unit .. ".lastEvent=" .. SafeScalar(state and state.lastEvent, "unobserved"))
    end

    AddLine(lines, "upstream.WOWUI-2026-005=ACTIVE_UPSTREAM")
    AddLine(lines, "mitigation.WOWUI-2026-005=event-authoritative-channel-stop-guard")
end

local function AppendSecrecySection(lines)
    AddLine(lines, "")
    AddLine(lines, "[secrecy]")

    if not C_Secrets then
        AddLine(lines, "C_Secrets=<unavailable>")
        return
    end

    AddLine(lines, "hasSecretRestrictions=" .. FormatBoolCall(C_Secrets.HasSecretRestrictions))
    AddLine(lines, "cooldownsSecretNow=" .. FormatBoolCall(C_Secrets.ShouldCooldownsBeSecret))
    AddLine(lines, "targetCastSecretNow=" .. FormatBoolCall(C_Secrets.ShouldUnitSpellCastingBeSecret, "target"))
    AddLine(lines, "focusCastSecretNow=" .. FormatBoolCall(C_Secrets.ShouldUnitSpellCastingBeSecret, "focus"))

    local spellIDs = CollectActiveSpellIDs()
    for index = 1, #spellIDs do
        local spellID = spellIDs[index]
        AddLine(lines, format(
            "spell.%d cooldownPolicy=%s cooldownSecretNow=%s",
            spellID,
            FormatSecrecyCall(C_Secrets.GetSpellCooldownSecrecy, spellID),
            FormatBoolCall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
        ))
    end

    local slots = CollectActionSlots()
    for index = 1, #slots do
        local slot = slots[index]
        AddLine(lines, format(
            "action.%d cooldownSecretNow=%s",
            slot,
            FormatBoolCall(C_Secrets.ShouldActionCooldownBeSecret, slot)
        ))
    end
end

local function AppendAbilitySection(lines)
    AddLine(lines, "")
    AddLine(lines, "[abilities]")

    local keys = SortedKeys(IG.AbilityStates)
    if #keys == 0 then AddLine(lines, "count=0") end

    for index = 1, #keys do
        local key = keys[index]
        local ability = IG.AbilityStates[key]
        if ability then
            local recordCount = ability.records and #SortedKeys(ability.records) or 0
            AddLine(lines, format(
                "%s source=%s:%s canonical=%s ready=%s pending=%s restricted=%s hardRestricted=%s needsPoll=%s deadline=%s records=%s",
                SafeScalar(key),
                SafeScalar(ability.sourceKind),
                SafeScalar(ability.sourceID),
                SafeScalar(ability.canonicalSpellID),
                SafeScalar(ability.ready),
                SafeScalar(ability.readinessPending),
                SafeScalar(ability.restricted),
                SafeScalar(ability.hardRestricted),
                SafeScalar(ability.needsPoll),
                SafeScalar(ability.deadline),
                SafeScalar(recordCount)
            ))
        end
    end
end

local function AppendCountersSection(lines)
    AddLine(lines, "")
    AddLine(lines, "[counters]")

    local keys = SortedKeys(IG.Stats)
    if #keys == 0 then AddLine(lines, "count=0") end
    for index = 1, #keys do
        local key = keys[index]
        AddLine(lines, SafeScalar(key) .. "=" .. SafeScalar(IG.Stats[key]))
    end
end

local function AppendSnapshot(lines, prefix, snapshot)
    if not snapshot then
        AddLine(lines, prefix .. ".available=false")
        return
    end

    AddLine(lines, prefix .. ".available=" .. SafeScalar(snapshot.available))
    AddLine(lines, prefix .. ".enabled=" .. SafeScalar(snapshot.enabled, "unknown"))
    AddLine(lines, prefix .. ".ticksPerSecond=" .. SafeScalar(snapshot.ticksPerSecond, "unknown"))

    local metrics = IG.Debug and IG.Debug.profilerMetrics or {}
    for index = 1, #metrics do
        local name = metrics[index][1]
        local value = snapshot.metrics and snapshot.metrics[name]
        if value ~= nil then AddLine(lines, prefix .. "." .. name .. "=" .. SafeScalar(value)) end
    end
end

local function AppendProfilerDeltas(lines, prefix, startSnapshot, endSnapshot)
    if not IG.Debug or type(IG.Debug.ProfilerDelta) ~= "function" then return end
    local delta = IG.Debug:ProfilerDelta(startSnapshot, endSnapshot)
    AddLine(lines, prefix .. ".PeakTimeIncrease=" .. SafeScalar(delta.peakIncrease, "unknown"))

    local metrics = IG.Debug.profilerMetrics or {}
    for index = 1, #metrics do
        local name = metrics[index][1]
        if metrics[index][3] == true and delta.metrics[name] ~= nil then
            AddLine(lines, prefix .. "." .. name .. "=" .. SafeScalar(delta.metrics[name]))
        end
    end
end

local function AppendProfilerSection(lines)
    AddLine(lines, "")
    AddLine(lines, "[profiler]")

    local finish = RuntimeProbe.active and CaptureProfiler()
        or RuntimeProbe.profilerStop
        or CaptureProfiler()
    local start = RuntimeProbe.profilerStart or finish

    AppendSnapshot(lines, "start", start)
    AppendSnapshot(lines, "end", finish)
    AppendProfilerDeltas(lines, "delta", start, finish)

    for index = 1, #RuntimeProbe.marks do
        local mark = RuntimeProbe.marks[index]
        if mark.profiler then
            AddLine(lines, "marker." .. index .. ".label=" .. SafeScalar(mark.label))
            AddLine(lines, "marker." .. index .. ".elapsed=" .. SafeScalar(mark.elapsed))
            AppendSnapshot(lines, "marker." .. index, mark.profiler)
            AppendProfilerDeltas(lines, "marker." .. index .. ".delta", start, mark.profiler)
        end
    end
end

function RuntimeProbe:BuildReport()
    local lines = {}
    AppendBuildSection(lines)
    AppendContextSection(lines)
    AppendProviderSection(lines)
    AppendWorkerSection(lines)
    AppendCaptureSection(lines)
    AppendCastSection(lines)
    AppendSecrecySection(lines)
    AppendAbilitySection(lines)
    AppendCountersSection(lines)
    AppendProfilerSection(lines)
    return concat(lines, "\n")
end

function RuntimeProbe:AddMark(label, announce)
    if not self.active then return false end

    self.marks[#self.marks + 1] = {
        elapsed = IG:Now() - self.startedAt,
        label = NormalizeLabel(label, "mark"),
        profiler = CaptureProfiler(),
    }
    if announce then IG:Print("Capture marker added.") end
    return true
end

function RuntimeProbe:Start(label)
    if self.active then
        IG:Print("A runtime capture is already active.")
        return false
    end

    self.active = true
    self.label = NormalizeLabel(label, "")
    self.startedAt = IG:Now()
    self.stoppedAt = nil
    self.marks = {}
    self.restrictionTransitions = {}
    self.lastRestrictionType = nil
    self.lastRestrictionState = nil
    self.profilerStop = nil
    self.lastReport = nil
    IG:StartProfileCounters()
    self.profilerStart = CaptureProfiler()
    IG:Print("Runtime capture started.")
    return true
end

function RuntimeProbe:Mark(label)
    if not self.active then
        IG:Print("No active capture. Use /iglow capture start.")
        return false
    end
    return self:AddMark(label, true)
end

function RuntimeProbe:Stop()
    if not self.active then
        IG:Print("No active capture.")
        return false
    end

    self.stoppedAt = IG:Now()
    self.profilerStop = CaptureProfiler()
    self.active = false
    IG:StopProfileCounters()
    self.lastReport = self:BuildReport()
    IG:Print("Runtime capture stopped. Use /iglow capture show.")
    return true
end

function RuntimeProbe:Show()
    local report = self.active and self:BuildReport() or self.lastReport or self:BuildReport()
    if IG.Debug and type(IG.Debug.ShowText) == "function" then
        IG.Debug:ShowText("Interrupt Glow Runtime Probe", report)
    else
        IG:Print("Runtime report UI is unavailable.")
    end
end

function RuntimeProbe:OnRestrictionStateChanged(restrictionType, state)
    if not self.active then return end

    local safeType = CaptureScalar(restrictionType)
    local safeState = CaptureScalar(state)
    self.lastRestrictionType = safeType
    self.lastRestrictionState = safeState

    self.restrictionTransitions[#self.restrictionTransitions + 1] = {
        elapsed = IG:Now() - self.startedAt,
        restrictionType = safeType,
        state = safeState,
    }
    self:AddMark("restriction type="
        .. SafeScalar(safeType, "unknown")
        .. " state="
        .. SafeScalar(safeState, "unknown"), false)
end
