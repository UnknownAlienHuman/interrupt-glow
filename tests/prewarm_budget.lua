local ROOT = arg[1] or "."

_G = _G or _ENV

local disableCalls = 0
local scheduleCalls = 0
local processedStat = 0
local createCalls = 0

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
    assert(key == "ui.prewarmRecordsProcessed")
    processedStat = processedStat + amount
end

local Glow = InterruptGlow.Glow
function Glow:DisablePrewarmWorker() disableCalls = disableCalls + 1 end
function Glow:SchedulePrewarm() scheduleCalls = scheduleCalls + 1 end
function Glow:CreateShell()
    createCalls = createCalls + 1
    return nil
end
function Glow:EnsureInterruptVisuals() error("unexpected visual creation") end

-- Every record is already handled. The old implementation bounded successful
-- creations and would drain all 20 in one frame because created stayed zero.
for index = 1, 20 do
    local record = { overlay = {}, overlayQueued = true }
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
assert(createCalls == 0)
for index = 1, 16 do assert(Glow.prewarmQueue[index] == nil) end
for index = 17, 20 do assert(Glow.prewarmQueue[index] ~= nil) end

Glow:ProcessPrewarmBudget()
assert(disableCalls == 2)
assert(scheduleCalls == 1)
assert(processedStat == 20)
assert(Glow.prewarmHead == 1 and Glow.prewarmTail == 0)
assert(next(Glow.prewarmQueue) == nil)

local policy = assert(InterruptGlow.modules.PrewarmPolicy)
assert(policy.budgetCountsInspectedRecords == true)

print("PREWARM BUDGET TEST PASSED")
