-- split.lua SRC OUTDIR [maxbytes]: top-level locals -> globals, then cut into chunks that each compile
local src, outdir, max = arg[1], arg[2], tonumber(arg[3] or 5000)
local lines = {}
for l in io.lines(src) do if not l:match("^#!") then lines[#lines+1] = l end end
for i, l in ipairs(lines) do
  if l:match("^local function ") then lines[i] = l:sub(7)
  elseif l:match("^local [%w_, ]+$") and not l:match("=") then lines[i] = "-- " .. l   -- bare declaration
  elseif l:match("^local [%w_, ]+=") then lines[i] = l:sub(7) end
end
local chunks, cur = {}, {}
local function size(t) local n = 0 for _, l in ipairs(t) do n = n + #l + 1 end return n end
for i, l in ipairs(lines) do
  cur[#cur+1] = l
  if l == "" and size(cur) >= max and load(table.concat(cur, "\n")) then
    chunks[#chunks+1] = cur; cur = {}
  end
end
if #cur > 0 then chunks[#chunks+1] = cur end
for i, c in ipairs(chunks) do
  local f = assert(io.open(string.format("%s/c%02d.lua", outdir, i), "w"))
  f:write(table.concat(c, "\n"), "\n"); f:close()
end
print(#chunks .. " chunks")
