# lpeg's own test suite on the RP2040

`test.lua` (50 KB) cannot even be compiled by a Lua state on the board (the heap is ~145 KB), so it is
split into ~5 KB chunks run in one global environment:

    lua split.lua lpeg-1.1.0/test.lua OUTDIR 5000     # top-level locals -> globals, cut where each chunk compiles
    tools/rp2040-send.py OUTDIR/c*.lua tools/lpeg-board-test/run_chunks.lua
    tools/rp2040-stream.py log 'cd /flash; vlua run_chunks.lua /flash 10'

`run_chunks.lua` prints `CHUNK n ok|FAIL <live heap> stack <peak stack>` and `ALL OK`.
Result (2026-10-26): ALL OK with lpeg `MAXRULES=200`, `MAXRECLEVEL=20`, Lua 5.4.8 and these
changes to the tests, each because of the 242 KB of RAM or the 24 KB stack, not a defect:

| test | on the board |
|---|---|
| "large grammars": 1000 rules | 200 rules (`MAXRULES`) |
| "large dynamic Cc": 65535 captures | removed |
| "nesting of captures too deep": 300 nested patterns recurse 300 C levels in lpeg's compiler | removed (a nesting of 25 gives "too deep", checked separately) |
| a table capture of 10000 items | 1000 |
| matching 20-30 KB subject strings (x10000) and `lim = 10000` | 1000 |
| long string capture, `l = 10000` | 1000 |
| `for i=1,14 do p = p * p end` (16384 nodes) | 9 doublings |
| `lim = 2^11 - 10` captures, plus 2^15 "too many" | 2^7 - 10, the second dropped |
