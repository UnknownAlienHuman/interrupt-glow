local ROOT = arg[1] or "."
local tocPath = ROOT .. "/InterruptGlow.toc"
local toc, tocError = io.open(tocPath, "r")
assert(toc, tocError)

local entries, positions = {}, {}
local loadSavedVariablesFirst, sawAddonSource = false, false
for rawLine in toc:lines() do
    local line = rawLine:match("^%s*(.-)%s*$")
    if line == "## LoadSavedVariablesFirst: 1" then
        assert(not sawAddonSource, "SavedVariables load directive appears after addon sources")
        loadSavedVariablesFirst = true
    elseif line ~= "" and not line:match("^##") then
        sawAddonSource = true
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
    "core/Debug.lua",
    "core/RuntimeProbe.lua",
    "core/Glow.lua",
    "core/Buttons.lua",
    "core/LABAdapter.lua",
    "core/ActionResolver.lua",
    "core/Cooldown.lua",
    "core/Usability.lua",
    "core/ConditionalActions.lua",
    "core/CastTracking.lua",
    "core/CDM.lua",
    "core/RuntimeLifecycle.lua",
    "core/Events.lua",
    "core/Slash.lua",
    "Options.lua",
}

assert(loadSavedVariablesFirst, "TOC must load SavedVariables before addon Lua files")
assert(#entries == #requiredOrder, "TOC source list changed; review runtime source order")
local previousPosition = 0
for index, path in ipairs(requiredOrder) do
    local position = positions[path]
    assert(position ~= nil, "TOC is missing required runtime module: " .. path)
    assert(position > previousPosition, "TOC runtime order is invalid at: " .. path)
    previousPosition = position
    local source, sourceError = io.open(ROOT .. "/" .. path, "r")
    assert(source, sourceError or ("TOC source does not exist: " .. path))
    source:close()
end

print("TOC CONTRACT TEST PASSED")
