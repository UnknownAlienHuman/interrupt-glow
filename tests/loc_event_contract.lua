local ROOT = arg[1] or "."

local path = ROOT .. "/core/Events.lua"
local file, fileError = io.open(path, "r")
assert(file, fileError)
local text = file:read("*a")
file:close()

assert(text:find('"LOSS_OF_CONTROL_ADDED"', 1, true), "LOSS_OF_CONTROL_ADDED is not registered")
assert(text:find('"LOSS_OF_CONTROL_UPDATE"', 1, true), "LOSS_OF_CONTROL_UPDATE is not registered")
assert(
    not text:find('RegisterUnitEvent("LOSS_OF_CONTROL_ADDED"', 1, true),
    "LOSS_OF_CONTROL_ADDED incorrectly uses a unit filter"
)
assert(
    not text:find('RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE"', 1, true),
    "LOSS_OF_CONTROL_UPDATE incorrectly uses a unit filter"
)

local eventListStart = assert(text:find("local EVENTS = {", 1, true))
local eventListEnd = assert(text:find("}", eventListStart, true))
local eventList = text:sub(eventListStart, eventListEnd)
assert(eventList:find('"LOSS_OF_CONTROL_ADDED"', 1, true))
assert(eventList:find('"LOSS_OF_CONTROL_UPDATE"', 1, true))

print("LOSS OF CONTROL EVENT CONTRACT TEST PASSED")
