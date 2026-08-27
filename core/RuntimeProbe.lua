local IG = _G.InterruptGlow
if not IG then return end

local RuntimeProbe = {
    active = false,
    label = nil,
    startedAt = nil,
    stoppedAt = nil,
    marks = {},
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

local function SafeScalar(value, fallback)
    if not IG.CanAccess(value) then return "<inaccessible>" end
    if value == nil then return fallback or "nil" end

    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end
    return "<" .. valueType .. ">"
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return false, "<unavailable>" end

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
    AddLine(lines, "kbCommit=bb13f191903ca4ff63a4c93535edb9eacab9630d")
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
        AddLine(lines, format("mark.%d=%.3f %s", index, mark.elapsed, mark.label))
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
        AddLine(lines, unit .. ".niState=" .. SafeScalar(state and state.niState))
        AddLine(lines, unit .. ".castBarID=" .. SafeScalar(state and state.castBarID))
    end
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

local function AppendProfilerSection(lines)
    AddLine(lines, "")
    AddLine(lines, "[profiler]")
    if IG.Debug and type(IG.Debug.ProfilerReport) == "function" then
        local report = IG.Debug:ProfilerReport()
        for line in report:gmatch("[^\n]+") do AddLine(lines, line) end
    else
        AddLine(lines, "C_AddOnProfiler=<unavailable>")
    end
end

function RuntimeProbe:BuildReport()
    local lines = {}
    AppendBuildSection(lines)
    AppendContextSection(lines)
    AppendCaptureSection(lines)
    AppendCastSection(lines)
    AppendSecrecySection(lines)
    AppendAbilitySection(lines)
    AppendCountersSection(lines)
    AppendProfilerSection(lines)
    return concat(lines, "\n")
end

function RuntimeProbe:Start(label)
    self.active = true
    self.label = type(label) == "string" and label or ""
    self.startedAt = IG:Now()
    self.stoppedAt = nil
    self.marks = {}
    self.lastReport = nil
    IG:StartProfileCounters()
    IG:Print("Runtime capture started.")
end

function RuntimeProbe:Mark(label)
    if not self.active then
        IG:Print("No active capture. Use /iglow capture start.")
        return
    end

    self.marks[#self.marks + 1] = {
        elapsed = IG:Now() - self.startedAt,
        label = type(label) == "string" and label or "mark",
    }
    IG:Print("Capture marker added.")
end

function RuntimeProbe:Stop()
    if not self.active then
        IG:Print("No active capture.")
        return
    end

    self.stoppedAt = IG:Now()
    self.active = false
    IG:StopProfileCounters()
    self.lastReport = self:BuildReport()
    IG:Print("Runtime capture stopped. Use /iglow capture show.")
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

    if IG.CanAccess(restrictionType) then self.lastRestrictionType = restrictionType end
    if IG.CanAccess(state) then self.lastRestrictionState = state end

    self:Mark("restriction type="
        .. SafeScalar(self.lastRestrictionType, "unknown")
        .. " state="
        .. SafeScalar(self.lastRestrictionState, "unknown"))
end
