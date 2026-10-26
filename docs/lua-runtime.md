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
- NuttX Lua is built with 32-bit integers and floats (`INTERPRETERS_LUA_32BIT`,
  default y), which matters for bytecode portability (below). **verified**

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

Verified on the sim (require + basic calls) and compiled for the RP2040 (about
27 KB of flash for all three: lpeg 15, cjson 8, lfs 4). **Not run on the
board** (none attached), so RAM use and littlefs behaviour there are unchecked.

Known gaps, all of them NuttX, not the libraries (see compat-log.md):
`lfs.touch` and mtimes need a filesystem with `chstat` (not FAT/tmpfs; littlefs
only with `FS_LITTLEFS_ATTR_UPDATE`), `lfs.lock_dir` needs `symlink`, and
`dev`/`ino` are always 0.

