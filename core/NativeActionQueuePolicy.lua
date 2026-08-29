local IG = _G.InterruptGlow
if not IG or not IG.Buttons then return end

local Buttons = IG.Buttons

-- ActionButton.OnActionChanged is a potentially mouseover-driven callback.
-- Never classify the current action inside the callback: invalidate the cached
-- snapshot, coalesce by physical button, enqueue one addon-owned dirty pass, and
-- return. ReconcileRecord reads the latest action at most once per button/frame.
function Buttons:OnNativeActionChanged(button)
    if not button then return end

    local record = IG.ObservedButtons[button]
    if not record then
        record = self:ObserveButton(button, "native", { skipDirty = true })
        if not record then return end
    end

    record.actionSnapshotFresh = false

    -- Another signal may already have queued this button. Snapshot invalidation
    -- still happened above, so the existing dirty pass cannot reuse stale action
    -- identity after a later mouseover/conditional-macro transition.
    if IG.PendingButtons[button] then return end

    IG:MarkButtonDirty(button)
    IG:BumpStat("events.actionButtonQueued")
end

IG:RegisterModule("NativeActionQueuePolicy", {
    callbackReadsActionAPIs = false,
    coalescesPerPhysicalButton = true,
    invalidatesBeforeDedupe = true,
})
