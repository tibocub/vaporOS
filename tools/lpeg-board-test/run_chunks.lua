-- run_chunks.lua DIR N: run c01..cNN.lua in one global environment, report the first failure
collectgarbage("incremental", 100, 400)
local dir, n = arg[1], tonumber(arg[2])
for i = 1, n do
  local name = string.format("%s/c%02d.lua", dir, i)
  local f, e = loadfile(name)
  if not f then print("LOADFAIL", name, e) os.exit(1) end
  local ok, err = xpcall(f, debug.traceback)
  collectgarbage()
  local sf=io.open("/proc/self/stack") local su=sf and (sf:read("a") or ""):match("StackUsed:%s*(%d+)") if sf then sf:close() end
  print("CHUNK", i, ok and "ok" or ("FAIL " .. tostring(err)), math.floor(collectgarbage("count")) .. "KB", "stack", su)
  io.stdout:flush()
  if not ok then os.exit(1) end
end
print("ALL OK")
