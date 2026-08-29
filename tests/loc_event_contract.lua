local ROOT = arg[1] or "."

local path = ROOT .. "/core/Events.lua"
local file, fileError = io.open(path, "r")
assert(file, fileError)
local text = file:read("*a")
file:close()

assert(
    text:find('RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", "player")', 1, true),
    "LOSS_OF_CONTROL_ADDED is not unit-filtered to player"
)
assert(
    text:find('RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", "player")', 1, true),
    "LOSS_OF_CONTROL_UPDATE is not unit-filtered to player"
)
assert(
    not text:find('frame:RegisterEvent("LOSS_OF_CONTROL_ADDED")', 1, true),
    "LOSS_OF_CONTROL_ADDED is also globally registered"
)
assert(
    not text:find('frame:RegisterEvent("LOSS_OF_CONTROL_UPDATE")', 1, true),
    "LOSS_OF_CONTROL_UPDATE is also globally registered"
)

-- Generated 12.1 documentation gives these events a unitTarget payload, and
-- Blizzard ActionButton code uses the same explicit player unit filter.
assert(text:find("Both events carry unitTarget", 1, true))

print("LOSS OF CONTROL EVENT CONTRACT TEST PASSED")
