local IG = _G.InterruptGlow
if not IG or not IG.Glow then return end

local Glow = IG.Glow

-- The original loop bounded successful shell creations, not queue inspections.
-- A queue full of already-created, forbidden, or otherwise skipped records could
-- therefore be drained in one frame. Bound every inspected record so startup and
-- post-combat cleanup remain predictable regardless of record state.
--
-- Every observed physical button also receives its reusable interrupt visual
-- objects while out of combat, even when its current action is not an interrupt.
-- Conditional help/harm and mouseover macros may switch to an interrupt branch
-- during combat; prewarming only the current branch would preserve CPU but lose
-- the glow until combat ended. The bounded queue pays this allocation cost once
-- outside combat and keeps the combat path allocation-free.
function Glow:ProcessPrewarmBudget()
    self:DisablePrewarmWorker()
    if IG:IsInCombat() then return end

    local processed = 0
    local visualsPrepared = 0
    while processed < self.prewarmBudgetPerFrame and self.prewarmHead <= self.prewarmTail do
        local record = self.prewarmQueue[self.prewarmHead]
        self.prewarmQueue[self.prewarmHead] = nil
        self.prewarmHead = self.prewarmHead + 1
        processed = processed + 1

        if record then
            self.prewarmQueued[record] = nil
            record.overlayQueued = false

            if not record.overlay and not record.overlayForbidden then
                self:CreateShell(record)
            end

            if record.overlay and not record.overlayForbidden then
                local before = record.interruptVisualsReady == true
                    or record.visualsReady == true
                    or record.interruptVisuals ~= nil
                self:EnsureInterruptVisuals(record)
                local after = record.interruptVisualsReady == true
                    or record.visualsReady == true
                    or record.interruptVisuals ~= nil
                if not before and after then visualsPrepared = visualsPrepared + 1 end
            end
        end
    end

    if processed > 0 then IG:BumpStat("ui.prewarmRecordsProcessed", processed) end
    if visualsPrepared > 0 then IG:BumpStat("ui.prewarmVisualsPrepared", visualsPrepared) end

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
    prewarmsInterruptVisualsForAllObservedButtons = true,
    combatSwitchingRequiresNoVisualAllocation = true,
})
