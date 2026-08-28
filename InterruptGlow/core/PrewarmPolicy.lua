local IG = _G.InterruptGlow
if not IG or not IG.Glow then return end

local Glow = IG.Glow

-- The original loop bounded successful shell creations, not queue inspections.
-- A queue full of already-created, forbidden, or otherwise skipped records could
-- therefore be drained in one frame. Bound every inspected record so startup and
-- post-combat cleanup remain predictable regardless of record state.
function Glow:ProcessPrewarmBudget()
    self:DisablePrewarmWorker()
    if IG:IsInCombat() then return end

    local processed = 0
    while processed < self.prewarmBudgetPerFrame and self.prewarmHead <= self.prewarmTail do
        local record = self.prewarmQueue[self.prewarmHead]
        self.prewarmQueue[self.prewarmHead] = nil
        self.prewarmHead = self.prewarmHead + 1
        processed = processed + 1

        if record then
            self.prewarmQueued[record] = nil
            record.overlayQueued = false
            if not record.overlay and not record.overlayForbidden and self:CreateShell(record) then
                if record.isInterrupt then self:EnsureInterruptVisuals(record) end
            end
        end
    end

    if processed > 0 then IG:BumpStat("ui.prewarmRecordsProcessed", processed) end

    if self.prewarmHead > self.prewarmTail then
        self.prewarmQueue = {}
        self.prewarmHead = 1
        self.prewarmTail = 0
    else
        self:SchedulePrewarm()
    end
end

IG:RegisterModule("PrewarmPolicy", {
    budgetCountsInspectedRecords = true,
})
