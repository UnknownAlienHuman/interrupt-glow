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
local localTests = {
    "tests/mock_wow.lua",
    "tests/cdm_toggle.lua",
    "tests/cdm_policy.lua",
    "tests/ability_source_policy.lua",
    "tests/lab_callback_policy.lua",
    "tests/restricted_success_event.lua",
    "tests/runtime_probe.lua",
    "tests/runtime_probe_policy.lua",
    "tests/diagnostic_ownership.lua",
    "tests/native_callback_handles.lua",
    "tests/channel_guard.lua",
    "tests/shared_worker.lua",
    "tests/cache_policy.lua",
    "tests/glow_worker.lua",
    "tests/prewarm_budget.lua",
    "tests/gcd_safety.lua",
    "tests/invalid_source_readiness.lua",
    "tests/options_lifecycle.lua",
    "tests/toc_contract.lua",
}

for index = 1, #localTests do
    files[#files + 1] = localTests[index]
end

for index = 1, #files do
    local path = root .. "/" .. files[index]
    local fn, err = loadfile(path)
    if not fn then
        io.stderr:write(path, ": ", tostring(err), "\n")
        os.exit(1)
    end
end

print(("LUA SYNTAX CHECK PASSED (%d files from TOC + local tests)"):format(#files))
