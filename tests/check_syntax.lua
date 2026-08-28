local root = arg[1] or "."
local files = {}

local tocPath = root .. "/InterruptGlow.toc"
local toc, tocError = io.open(tocPath, "r")
if not toc then
    io.stderr:write(tocPath, ": ", tostring(tocError), "\n")
    os.exit(1)
end

for rawLine in toc:lines() do
    local line = rawLine:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^##") then
        files[#files + 1] = line
    end
end
toc:close()

-- These files are not loaded by WoW, but must remain valid Lua as part of the
-- local development suite.
files[#files + 1] = "tests/mock_wow.lua"
files[#files + 1] = "tests/cdm_toggle.lua"
files[#files + 1] = "tests/runtime_probe.lua"
files[#files + 1] = "tests/native_callback_handles.lua"
files[#files + 1] = "tests/channel_guard.lua"
files[#files + 1] = "tests/shared_worker.lua"
files[#files + 1] = "tests/cache_policy.lua"
files[#files + 1] = "tests/glow_worker.lua"

for index = 1, #files do
    local path = root .. "/" .. files[index]
    local fn, err = loadfile(path)
    if not fn then
        io.stderr:write(path, ": ", tostring(err), "\n")
        os.exit(1)
    end
end

print(("LUA SYNTAX CHECK PASSED (%d files from TOC + local tests)"):format(#files))
