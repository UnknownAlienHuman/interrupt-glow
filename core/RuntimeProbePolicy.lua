local IG = _G.InterruptGlow
if not IG or not IG.RuntimeProbe then return end

local Probe = IG.RuntimeProbe
local _G = _G
local C_AddOns = _G.C_AddOns
local type = type
local pcall = pcall

local MAX_MARKS = 256
local MAX_RESTRICTIONS = 128
local PROVIDERS = {
    "Bartender4",
    "ElvUI",
    "Dominos",
    "ButtonForge",
    "Blizzard_CooldownViewer",
}

local function CaptureScalar(value)
    if not IG.CanAccess(value) then return nil end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end
    return nil
end

local function ReportScalar(value, fallback)
    local captured = CaptureScalar(value)
    if captured == nil then return fallback or "unknown" end
    return tostring(captured)
end

local function GetProviderVersion(addOnName)
    if not C_AddOns or type(C_AddOns.GetAddOnMetadata) ~= "function" then
        return "<unavailable>"
    end

    local ok, value = pcall(C_AddOns.GetAddOnMetadata, addOnName, "Version")
    if not ok or not IG.CanAccess(value) then return "<inaccessible>" end
    if type(value) ~= "string" and type(value) ~= "number" then return "<unknown>" end
    return tostring(value)
end

local originalStart = Probe.Start
function Probe:Start(label)
    local started = originalStart(self, label)
    if started then
        self.droppedMarks = 0
        self.droppedRestrictions = 0
        self.markerLimitReported = false
    end
    return started
end

local originalAddMark = Probe.AddMark
function Probe:AddMark(label, announce)
    if not self.active then return false end

    if #self.marks >= MAX_MARKS then
        self.droppedMarks = (self.droppedMarks or 0) + 1
        if announce and not self.markerLimitReported then
            self.markerLimitReported = true
            IG:Print("Runtime capture marker limit reached; further markers are counted but not stored.")
        end
        return false
    end

    return originalAddMark(self, label, announce)
end

-- Restriction events are already timestamped evidence. Do not automatically
-- take a full profiler snapshot for each synchronous transition: that would add
-- observer cost to the very context being measured. Manual capture marks remain
-- the explicit profiler segmentation surface.
function Probe:OnRestrictionStateChanged(restrictionType, state)
    if not self.active then return end

    local safeType = CaptureScalar(restrictionType)
    local safeState = CaptureScalar(state)
    self.lastRestrictionType = safeType
    self.lastRestrictionState = safeState

    if #self.restrictionTransitions >= MAX_RESTRICTIONS then
        self.droppedRestrictions = (self.droppedRestrictions or 0) + 1
        return
    end

    self.restrictionTransitions[#self.restrictionTransitions + 1] = {
        elapsed = IG:Now() - self.startedAt,
        restrictionType = safeType,
        state = safeState,
    }
end

local originalBuildReport = Probe.BuildReport
function Probe:BuildReport()
    local report = originalBuildReport(self)
    local DB = IG.DB or {}

    report = report
        .. "\n\n[configuration]"
        .. "\nenabled=" .. ReportScalar(DB.enabled)
        .. "\ncdText=" .. ReportScalar(DB.cdText)
        .. "\ncdm=" .. ReportScalar(DB.cdm)
        .. "\nstrictNI=" .. ReportScalar(DB.strictNI)
        .. "\noptimisticRestrictedCooldown=" .. ReportScalar(DB.optimisticRestrictedCooldown)
        .. "\ndebug=" .. ReportScalar(DB.debug)
        .. "\ndebugChat=" .. ReportScalar(DB.debugChat)
        .. "\ndebugKeep=" .. ReportScalar(DB.debugKeep)
        .. "\n\n[providerVersions]"

    for index = 1, #PROVIDERS do
        local name = PROVIDERS[index]
        report = report .. "\n" .. name .. "=" .. GetProviderVersion(name)
    end

    return report
        .. "\n\n[probeBounds]"
        .. "\nmaxMarks=" .. tostring(MAX_MARKS)
        .. "\nstoredMarks=" .. tostring(#self.marks)
        .. "\ndroppedMarks=" .. tostring(self.droppedMarks or 0)
        .. "\nmaxRestrictions=" .. tostring(MAX_RESTRICTIONS)
        .. "\nstoredRestrictions=" .. tostring(#self.restrictionTransitions)
        .. "\ndroppedRestrictions=" .. tostring(self.droppedRestrictions or 0)
end

-- Final report construction walks normalized state, provider metadata, secrecy
-- policy and native profiler metrics. Running that work in combat both adds a
-- visible spike and contaminates the endpoint being measured. Users should mark
-- the end of the scenario in combat, then stop/finalize after combat.
local originalStop = Probe.Stop
function Probe:Stop()
    if self.active and IG:IsInCombat() then
        IG:Print("Capture is still active. Add an end marker now and stop it after combat.")
        return false
    end
    return originalStop(self)
end

local originalShow = Probe.Show
function Probe:Show()
    if IG:IsInCombat() then
        IG:Print("Runtime reports can be built and opened after combat.")
        return false
    end
    originalShow(self)
    return true
end

IG:RegisterModule("RuntimeProbePolicy", {
    maxMarks = MAX_MARKS,
    maxRestrictions = MAX_RESTRICTIONS,
    buildsReportsOutOfCombatOnly = true,
    finalizesCaptureOutOfCombatOnly = true,
    automaticRestrictionProfilerSnapshots = false,
    includesConfiguration = true,
    includesProviderVersions = true,
})
