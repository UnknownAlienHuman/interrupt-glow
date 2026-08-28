local IG = _G.InterruptGlow
if not IG or not IG.RuntimeProbe then return end

local Probe = IG.RuntimeProbe
local type = type

local MAX_MARKS = 256
local MAX_RESTRICTIONS = 128

local function CaptureScalar(value)
    if not IG.CanAccess(value) then return nil end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end
    return nil
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
    return report
        .. "\n\n[probeBounds]"
        .. "\nmaxMarks=" .. tostring(MAX_MARKS)
        .. "\nstoredMarks=" .. tostring(#self.marks)
        .. "\ndroppedMarks=" .. tostring(self.droppedMarks or 0)
        .. "\nmaxRestrictions=" .. tostring(MAX_RESTRICTIONS)
        .. "\nstoredRestrictions=" .. tostring(#self.restrictionTransitions)
        .. "\ndroppedRestrictions=" .. tostring(self.droppedRestrictions or 0)
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
    automaticRestrictionProfilerSnapshots = false,
})
