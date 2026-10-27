# A cross-platform Lua runtime for vaporOS (design reflection)

Status: **thinking, not building.** This records the reasoning so far (2026-10-18)
so we do not redo it. Nothing here is implemented beyond today's `vlua`.
Claims are marked **verified** (checked in this tree or on hardware) or
**unverified** (from memory; check before relying on it).

## Where this came from

The question: how far should vaporOS go as "write once, run anywhere"? Two ideas
competed:

1. Make **all of vaporOS** cross-platform: a single runtime/VM (working name
   "vaporVM") that runs vaporOS programs (vaporshell, C binaries built for
   vaporOS, Lua) on Windows, macOS, Linux and BSD as well as on chips.
2. Keep vaporOS what it is, **a programmable environment that supports many
   boards/processors and is easy to port to new ones**, and make **vlua** the part
   that is truly cross-platform.

Decision (for now): **idea 2.** Reasons:

- A NuttX program is native machine code linked into an OS image. A "ROM" built
  that way cannot move between architectures (the ELF loader we enabled on the
  simulator makes x86 programs; an RP2040 cannot run them). Ideas like uxn are
  portable because their programs are bytecode for a fixed tiny machine. NuttX
  provides a portable *runtime*, not a portable *program format*.
- So the portable program formats have to sit *above* the OS: Lua, and possibly
  WebAssembly for C. That is exactly what a vlua-centred plan gives us.
- Making the whole OS run natively on every desktop OS is a large, uncertain
  project (see "The Windows question") and not on the critical path.

## What exists today

- `vlua` (vaporOS/vlua): its own Lua 5.4 state with a `vapor` table, a script
  runner (`vlua file.lua`), `-e`, and a REPL (Ctrl-D or `exit` leaves). It runs on
  the simulator and on the RP2040-Zero. **verified**
- `docs/vapor-api.md`: the API rule: `vapor` holds only what plain Lua cannot do
  (directory listing, mkdir, ... are the confirmed gaps). `vapor.print` and
  `vapor.read` exist; the rest is design. **verified (docs)**
- NuttX Lua is *meant* to be built with 32-bit integers and floats (`INTERPRETERS_LUA_32BIT`, default y), which
  matters for bytecode portability (below). Until 2026-10-26 it was not (see the typo fix below); now it is.
  **verified on the board**

## What the runtime needs beyond today's vlua

- Directory/filesystem metadata functions (per vapor-api.md).
- **Asynchrony**: timers, waiting on several files/sockets/the console without
  blocking, coroutine-based scheduling. This is the "libuv problem".
- Network and (later) display/input/audio through the vapor API, implemented per
  board via the hardware descriptors (hardware/README.md), not in Lua code.
- A way to **get programs onto a device** (see docs/next-steps.md, step 1).

## The async / event-loop options

| option | what it is | cost | fits |
|---|---|---|---|
| **A. Own small loop** | a `poll()`/`select()` loop plus Lua coroutines, timers and a handful of vapor bindings, written for NuttX | small; we control it | every NuttX target incl. a 264 KB RP2040; on desktops via the NuttX sim |
| **B. libuv + luv** (luvit's approach) | libuv with the `luv` Lua bindings | larger; unmeasured here | boards with room; not obviously the RP2040 |
| **C. A hosted shim** | the vapor API implemented directly over POSIX/Win32 for desktops, no NuttX underneath | two runtimes to keep equivalent | desktops only |

Facts:

- **libuv is already ported to NuttX**: `nuttx-apps/system/libuv` carries a port
  patch and an epoll backend (depends on `PIPES`). So option B is not blocked on
  porting. **verified (present in tree; not built or measured by us)**
- NuttX has an epoll implementation (`fs/Kconfig`). **verified (present)**
- Unmeasured and needed before choosing B: flash and RAM of libuv + luv on the RP2040.
- `luv` itself is **not** in the tree; it would be an added dependency.

Leaning: **A as the default** (small, portable, ours), with **B optional** on boards
that can afford it, behind the same vapor-level API so scripts do not care.

## Lua vs LuaJIT (the luvit question)

- luvit normally runs on **LuaJIT**. LuaJIT only supports certain CPUs; to my
  knowledge that excludes the Cortex-M0+ (RP2040) and Xtensa (ESP32-S3).
  **unverified.** `interpreters/luajit` exists in nuttx-apps but we have not tried it.
- Plain **PUC Lua 5.4**, which vlua uses, runs on all NuttX targets. I believe
  luvit's launcher (luvi) can also be built against PUC Lua. **unverified.**
- Luvit remains a good *API inspiration* (promise-less, coroutine-friendly I/O,
  a module system). We borrow ideas, not the code base.

## What is a "ROM"?

A vlua program, in decreasing order of how much I would trust it:

1. **Lua source**: portable everywhere, trivially. Costs parse time/RAM on a
   small chip. Default.
2. **Lua bytecode**: *not* portable by default. It depends on integer/float size and
   endianness, and our build uses 32-bit integers. If we want shipped bytecode we
   must fix and document one format (e.g. always the 32-bit-number build).
3. **WebAssembly for C programs**: the closest thing to uxn's property for C
   (portable, sandboxed). NuttX has `interpreters/wamr`, `wasm3` and `toywasm`.
   **Unverified:** whether they build for our boards and what they cost on a
   264 KB chip.
4. **Native binaries built for a vaporOS target** (ELF): fine as an SDK, but per-target.

A single "vaporVM" executable that runs ROMs on a host terminal/GUI is therefore
realistic **for Lua (and maybe wasm)**; it is not for native binaries.

## The Windows question

Original idea: build the NuttX simulator for Windows so vlua (and everything else)
runs there, with NuttX's scheduler acting as the async/threading layer instead of
libuv.

Status: **paused.** See docs/windows-sim.md for the spike. Summary: the simulator
cannot be built as 64-bit Windows (LLP64 vs NuttX's pointer-sized `long`), the
Windows host layer in NuttX has bit-rotted, a 32-bit MinGW build is the next thing
to try, and nothing has booted yet. Reading and writing Windows files would be the
easy part if it did (win/sim_hostfs.c exists).

How it fits the plan if resumed: it would make *everything* (shell, vlua, tools) run
on Windows through the sim, at the price of the sim's constraints. That is a bonus.
The plan above does not depend on it. The alternative for desktops is option C, a
hosted vapor-API shim, which gives native file and network access on Windows
trivially but duplicates the runtime.

## Compiling C on the device (tinycc)

Considered as a later step ("programmable environment"). Constraint, **unverified**:
tinycc's code generators cover x86, x86_64, 32-bit ARM, arm64 and riscv64. That
suggests it is useful on the simulator and on bigger ARM/RISC-V boards, but not on
the Cortex-M0+ (Thumb-only), nor on Xtensa, and 264 KB is tight for a compiler
anyway. For MCUs the realistic path is cross-compiling on the host, or Lua.
Treat as an experiment on the simulator first.

## Open questions

- Event loop: how much of A do we really need before a real app exists? Write the
  apps first (docs/next-steps.md) and let them tell us.
- Measure libuv + luv on the RP2040 and on an ESP32-S3 before deciding on B.
- Which bytecode/ROM format, if any, do we promise to keep stable?
- Do we want option C (hosted shim) at all, or is "run it in the sim" enough?
- Graphics and input in the vapor API: per-board descriptors are the plan; the first
  real driver (an SPI display?) has not been chosen.

## Non-goals (for now)

- Running NuttX natively as a first-class Windows/macOS product.
- LuaJIT.
- Binary compatibility of native programs across architectures.

## Lua C libraries (implemented 2026-10-26)

`features/lua-libs.conf` links three unmodified upstream libraries into `vlua`:
`lfs` (luafilesystem), `lpeg` and `cjson`. Each has a `CONFIG_VAPOROS_VLUA_*`
switch (vlua/Kconfig); sources are sibling checkouts fetched by `setup.sh`, like
vaporshell. No dynamic linking, so `vlua/vlua_libs.c` puts them in
`package.preload` and `require("lfs")` works as on a desktop Lua. A new library
is one Kconfig bool, three Makefile lines and one table entry.

Verified on the sim and on the RP2040-Zero (require + basic calls; lpeg, cjson
and lfs all work). Flash: about 27 KB for all three (lpeg 15, cjson 8, lfs 4).
RAM on the board, Lua heap per `require`: lpeg 2.3 KB, cjson 1.8 KB, lfs 2.6 KB
(base Lua state 16.7 KB). The libraries' own test suites have not been run.

Known gaps, all of them NuttX, not the libraries (see compat-log.md):
`lfs.touch` and mtimes need a filesystem with `chstat`: not FAT/tmpfs (the sim's
`/tmp` reports mtime 0), but littlefs has it (`FS_LITTLEFS_ATTR_UPDATE=y`), and
`touch`, `attributes`, `mkdir` and `rmdir` work on the board's `/flash`.
`lfs.lock_dir` needs `symlink` and fails everywhere tested. `dev`/`ino` are always 0
(on the sim; `ino` also 0 on `/flash`). Like upstream, `lfs.touch` does not create
a missing file.

### Test suites on the RP2040 (2026-10-26)

- **lfs's own suite passes** (`Ok!`, 13 checks) on a fresh boot, after `mkdir /tmp` (the test hardcodes it and
  the board's `/tmp` does not survive a reboot). Its symlink/hard-link checks are skipped by the suite itself.
- **lpeg's suite passes on the board, chunked and scaled** (`tools/lpeg-board-test/`, `ALL OK`, peak stack 11.8 KB,
  Lua heap at most 75 KB). It does not fit as one file: compiling the 50 KB script needs more than the ~145 KB a Lua
  state gets, so it runs in 10 chunks (top-level locals made global; also verified on the host). Eight tests had to
  shrink or go because of RAM or stack (table in the README there), not because of a defect.
- **Two lpeg resets were stack overflows, found with the crash record and `objdump`, not Lua bugs** (the same
  crash happened on Lua 5.4.0 and 5.4.8): (1) left-recursion detection recurses `MAXRULES` (1000) levels at ~40
  bytes each, ~45 KB; (2) collecting nested captures recurses `MAXRECLEVEL` (200) levels with a 572-byte frame.
  Both are compile-time macros, now `VAPOROS_VLUA_LPEG_MAXRULES` (200) and `..._MAXRECLEVEL` (20). A grammar can
  have at most 200 rules and captures nest at most 20 deep; 25 nested gives the error "subcapture nesting too
  deep" instead of a reset. Building a pattern nested 300 deep still recurses 300 C levels in the compiler and
  would still overflow: lpeg has no limit for that, so patterns that deep are unsupported on 24 KB.
- **`os.exit()` leaked the whole Lua state.** A NuttX task's heap is not reclaimed at exit and Lua's `os.exit`
  skips `lua_close` by default, so each failed test run lost 35-40 KB of the 242 KB heap until reboot (it looked
  like a mysterious shrinking heap). `vlua` now replaces `os.exit` with a version that closes the state.
- **The 24 KB `vlua` stack held only ~45 nested C calls** (pcall in pcall: 480 B per level on 5.4.0, 464 B on
  5.4.8, measured with `/proc/self/stack`), but Lua allows 200, and there is no stack guard: deep nesting
  silently overwrote memory and reset the board (crash record: stack pointer 19 KB below the stack base).
  `patches/nuttx-apps/lua-maxccalls.patch` makes the limit configurable; the rp2040 board sets 40. With it,
  unbounded `pcall` recursion stops at depth 39 with a Lua error, peak stack 18.9 KB, board alive (5.4.8).
- **Decision (2026-10-26): vaporOS keeps 64-bit Lua numbers** (`features/lua.conf` sets
  `CONFIG_INTERPRETERS_LUA_32BIT=n`) for ecosystem compatibility; switch only if RAM or speed become impractical.
  The `lua-32bit-typo` patch makes the option work (it never did: the Makefile tested `..._32BITS`, and Lua 5.4.3+
  ignores `-DLUA_32BITS`, so the patch also flips `luaconf.h`; vlua and the libs pass the flag too). Measured on
  the RP2040, 32-bit vs 64-bit (`bench.lua`, one run each):
  fib(23) 0.33 s vs 0.36 s; 300k integer-loop steps 0.90 s vs 2.43 s; 60k `math.sin` **23.1 s vs 7.4 s** (float32
  goes through slower soft-float routines, so 32-bit is not faster for floats); strings 0.86 vs 0.81 s; sorting
  4000 numbers 0.48 vs 0.50 s; the 4000-number table takes 48 KB vs 83 KB of heap; flash 628 vs 636 KB; nested
  call stack 392 vs 464 B/level. Costs of 32-bit: ~7 significant digits (cjson 1234567.891 -> 1234567.875),
  integers wrap at 2^31, and `lfs.touch` rounds times to 128 s (lfs.c reads them as `lua_Number`). With 32-bit
  the lfs suite needs six timestamp checks relaxed and the lpeg suite passes unchanged. So 64-bit costs mostly
  table RAM (about 1.7x) and integer speed (2.7x on integer loops).
- vlua now builds **Lua 5.4.8** (NuttX defaults to 5.4.0).
- Handy while testing: `tools/rp2040-stream.py` (stream a command's output to a log), and sending big files by
  a Lua receiver on stdin (50 KB in 30 s) instead of typing hex into the shell (~9 min).


## Module search path

`require` looks in `lua_modules/` next to the script (current directory for `-e`/REPL), then
`CONFIG_VAPOROS_VLUA_LIBDIR` (per board; `/flash/lib/lua` on the RP2040), then the script's directory; `LUA_PATH`
replaces it. Verified on the RP2040 (system module found from any directory, a project's `lua_modules` wins over
the system copy, a script elsewhere uses its own project) and on the sim (project directory, relative and absolute
script paths, and the system directory: `vlua` mounts the host folder `vaporos-lua/` at `/usr/lib/lua` with hostfs
when `CONFIG_VAPOROS_VLUA_HOSTLIBDIR` is set; the mount happens in `vlua` itself, so no NuttX patch; it is skipped
if the directory already exists, and silently absent if the host folder does not exist). Shortcut: the path is fixed when `vlua` starts, so a script cannot change which project it belongs
to except by editing `package.path`. Native libraries are not searchable: no dynamic linking, they are build-time
features.

## Command names

`lua` and `vlua` are the same program (`vlua/lua_alias.c` forwards to it; `CONFIG_VAPOROS_VLUA_LUA_ALIAS`).
Reason for the alias rather than a pure rename: it differs from stock Lua in a few deliberate ways (early garbage
collection, `os.exit` closes the state, preloaded C libraries, vapor table, module path), so `vlua` stays as the
unambiguous name. NuttX's stock interpreter is renamed `nxlua` (`lua-progname` patch) because two built-ins cannot
share a name. Verified on the sim and the RP2040. Shebangs (`#!/usr/bin/env lua`, `#!/bin/lua`) work in vaporshell (see its
`docs/design.md`); `lua script a b` sets `arg[0]` (script), `arg[-1]` (interpreter) and passes `...` like stock Lua.

