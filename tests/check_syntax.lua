local root = arg[1] or "."
local files = {
    "Core.lua",
    "core/Shared.lua",
    "core/Data.lua",
    "core/Debug.lua",
    "core/Glow.lua",
    "core/Buttons.lua",
    "core/Cooldown.lua",
    "core/CastTracking.lua",
    "core/CDM.lua",
    "core/Events.lua",
    "core/Slash.lua",
    "Options.lua",
    "tests/mock_wow.lua",
}

for index = 1, #files do
    local path = root .. "/" .. files[index]
    local fn, err = loadfile(path)
    if not fn then
        io.stderr:write(path, ": ", tostring(err), "\n")
        os.exit(1)
    end
end

print("LUA 5.1 SYNTAX CHECK PASSED")
