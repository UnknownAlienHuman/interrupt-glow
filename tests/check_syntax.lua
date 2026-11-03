if #arg == 0 then
    io.stderr:write("Usage: lua tests/check_syntax.lua <Lua source files...>\n")
    os.exit(2)
end

for index = 1, #arg do
    local path = arg[index]
    local chunk, err = loadfile(path)
    if not chunk then
        io.stderr:write(path, ": ", tostring(err), "\n")
        os.exit(1)
    end
end

print(("LUA SYNTAX CHECK PASSED (%d discovered TOC + test files)"):format(#arg))
