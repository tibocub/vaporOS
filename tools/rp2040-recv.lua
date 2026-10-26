-- recv.lua: "F path nbytes" then hex lines until nbytes are written; "Q" quits. Prints "ACK path sum".
while true do
  local l = io.read("l")
  if not l or l:sub(1, 1) == "Q" then break end
  local path, n = l:match("^F (%S+) (%d+)")
  if path then
    n = tonumber(n)
    local f, sum, got = io.open(path, "wb"), 0, 0
    while got < n do
      local h = io.read("l")
      local s = h:gsub("%s", ""):gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end)
      f:write(s); got = got + #s
      for i = 1, #s do sum = (sum + s:byte(i)) % 65536 end
    end
    f:close()
    print("ACK " .. path .. " " .. sum)
  end
end
