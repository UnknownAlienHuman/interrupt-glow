local ROOT = arg[1] or "."

_G = _G or _ENV

local disableCalls = 0
local scheduleCalls = 0
local processedStat = 0
local preparedStat = 0
local createCalls = 0
local visualCalls = 0

InterruptGlow = {
    modules = {},
    Glow = {
        prewarmQueue = {},
        prewarmQueued = setmetatable({}, { __mode = "k" }),
        prewarmHead = 1,
        prewarmTail = 20,
        prewarmBudgetPerFrame = 16,
    },
}

function InterruptGlow:RegisterModule(name, module) self.modules[name] = module end
function InterruptGlow:IsInCombat() return false end
function InterruptGlow:BumpStat(key, amount)
    if key == "ui.prewarmRecordsProcessed" then
        processedStat = processedStat + amount
    elseif key == "ui.prewarmVisualsPrepared" then
        preparedStat = preparedStat + amount
    else
        error("unexpected stat " .. tostring(key))
    end
end

local Glow = InterruptGlow.Glow
function Glow:DisablePrewarmWorker() disableCalls = disableCalls + 1 end
function Glow:SchedulePrewarm() scheduleCalls = scheduleCalls + 1 end
function Glow:CreateShell()
    createCalls = createCalls + 1
    return nil
end
function Glow:EnsureInterruptVisuals(record)
    visualCalls = visualCalls + 1
    record.overlay.enhanced = true
    return true
end

-- Every shell already exists but still needs its reusable animation objects. The
-- inspected-record budget must cap both queue draining and visual construction.
for index = 1, 20 do
    local record = { overlay = { enhanced = false }, overlayQueued = true }
    Glow.prewarmQueue[index] = record
    Glow.prewarmQueued[record] = true
end

local loader, loadError = loadfile(ROOT .. "/core/PrewarmPolicy.lua")
assert(loader, loadError)
loader()

Glow:ProcessPrewarmBudget()
assert(disableCalls == 1)
assert(Glow.prewarmHead == 17)
assert(Glow.prewarmTail == 20)
assert(scheduleCalls == 1, "remaining prewarm work was not rescheduled")
assert(processedStat == 16)
assert(preparedStat == 16)
assert(visualCalls == 16)
assert(createCalls == 0)
for index = 1, 16 do assert(Glow.prewarmQueue[index] == nil) end
for index = 17, 20 do assert(Glow.prewarmQueue[index] ~= nil) end

Glow:ProcessPrewarmBudget()
assert(disableCalls == 2)
assert(scheduleCalls == 1)
assert(processedStat == 20)
assert(preparedStat == 20)
assert(visualCalls == 20)
assert(Glow.prewarmHead == 1 and Glow.prewarmTail == 0)
assert(next(Glow.prewarmQueue) == nil)

local policy = assert(InterruptGlow.modules.PrewarmPolicy)
assert(policy.budgetCountsInspectedRecords == true)
assert(policy.prewarmsInterruptVisualsForAllObservedButtons == true)
assert(policy.preparedVisualCounterUsesOverlayState == true)

print("PREWARM BUDGET TEST PASSED")
