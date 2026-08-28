local ROOT = arg[1] or "."
local tocPath = ROOT .. "/InterruptGlow.toc"

local toc, tocError = io.open(tocPath, "r")
assert(toc, tocError)

local entries = {}
local positions = {}
for rawLine in toc:lines() do
    local line = rawLine:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^##") then
        assert(positions[line] == nil, "duplicate TOC entry: " .. line)
        entries[#entries + 1] = line
        positions[line] = #entries
    end
end
toc:close()

local requiredOrder = {
    "Core.lua",
    "core/Worker.lua",
    "core/Shared.lua",
    "core/Data.lua",
    "core/Glow.lua",
    "core/Buttons.lua",
    "core/ActionResolver.lua",
    "core/Cooldown.lua",
    "core/ReadinessPolicy.lua",
    "core/Usability.lua",
    "core/GCDSafetyPolicy.lua",
    "core/CachePolicy.lua",
    "core/AbilitySourcePolicy.lua",
    "core/CastTracking.lua",
    "core/CDM.lua",
    "core/CDMPolicy.lua",
    "core/Events.lua",
}

local previousPosition = 0
for index = 1, #requiredOrder do
    local path = requiredOrder[index]
    local position = positions[path]
    assert(position ~= nil, "TOC is missing required runtime module: " .. path)
    assert(position > previousPosition, "TOC runtime order is invalid at: " .. path)
    previousPosition = position
end

assert(positions["core/AbilitySourcePolicy.lua"] < positions["core/CastTracking.lua"])
assert(positions["core/CDM.lua"] < positions["core/CDMPolicy.lua"])
assert(positions["core/CDMPolicy.lua"] < positions["core/Events.lua"])

print("TOC CONTRACT TEST PASSED")
