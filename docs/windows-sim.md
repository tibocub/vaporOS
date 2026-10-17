# vaporOS simulator on Windows (spike notes)

Goal: build the native simulator as a Windows program, **from Linux/WSL**, so
development stays on Linux and Windows users get a `.exe` that can read and edit
their own files.

Status: **does not build yet.** Below is what was verified, what was learned and
what is next. Nothing here has produced a running Windows binary.

## What NuttX gives us

- A Windows host layer for the simulator exists: `arch/sim/src/sim/win/` (hostfs,
  memory, uart, time, irq, ...), plus `HOST_WINDOWS`, a Microsoft-ABI option
  (`SIM_X8664_MICROSOFT`) and `configure.sh -c|-g|-n` (Cygwin, MinGW/MSYS, native).
- All of that assumes the build runs **on** Windows. The only code path that picks
  `sim/win/` is `CONFIG_WINDOWS_NATIVE` (cmd.exe, backslash paths), and the `win/`
  layer is missing two files the sim now needs, so it has been bit-rotting.

## What we did (patches/nuttx/sim-windows-host-layer.patch)

1. `arch/sim/src/Makefile`: use `sim/win` for every Windows host that is not
   Cygwin, not just `WINDOWS_NATIVE`.
2. Added `win/sim_testset.c` (same code as POSIX) and `win/sim_hostsmp.c`
   (single-CPU stubs; SMP is not supported there).

Build-system findings, all needed on a Linux build machine (see tools/shims/mingw):

- The helper tools NuttX builds and runs during the build (mkconfig, mkversion, ...)
  run on the build machine but are named `*.exe` when `HOST_WINDOWS` is set, so the
  makefile cannot find them: build with `HOSTEXEEXT=` (target stays `.exe`).
- `Make.defs` asks for `$(CROSSDEV)cc`; mingw-w64 only ships `...-gcc`.
- `Make.defs` passes `-U_WIN32`, which makes the compiler's own `<stdarg.h>`,
  `<float.h>` ... (they `#include_next` the Windows runtime) fail with "Only Win32
  target is supported". Almost nothing in NuttX tests `_WIN32`, so the wrapper
  simply drops that flag.
- The simulator's host-side files are compiled with `$(CC)` (not `$(HOSTCC)`), so
  one cross compiler is enough.

## Why x86_64 MinGW cannot work, and the plan

The first real compile error is not a missing header:

    limits_check.c: static assertion failed: "Compiler definition mismatch for LONG_MAX"
    corecrt.h: conflicting types for 'wint_t' / 'wctype_t'

Windows x86_64 is **LLP64**: `long` is 32 bits, only `long long` and pointers are 64.
NuttX assumes `long` is as wide as a pointer: `arch/sim/include/limits.h` gives
`LONG_MAX` a 64-bit value for 64-bit builds and a 32-bit value for 32-bit builds,
and the code base prints `size_t`/pointers with `%lu`/`%ld` throughout. Making
NuttX LLP64-clean is a project of its own and not something to carry as a patch.
(This is also why NuttX's historical Windows simulator ran under Cygwin, which is
LP64, or as 32-bit x86.)

**Plan:** target 32-bit x86 (`i686-w64-mingw32`, `CONFIG_HOST_X86`, ILP32), which
NuttX supports. A 32-bit `.exe` runs on 64-bit Windows, and under wine for testing
here. Needs `mingw32-gcc` (Fedora package) and its winpthreads.

Steps, in order, each testable on its own:

1. Plain `sim:nsh` for i686-w64-mingw32 builds and runs under wine (console only).
2. vaporOS board `sim-windows` (hardware: the Windows hostfs mount).
3. hostfs bridge: map Windows attributes to POSIX modes (read-only attribute ->
   no write bits, no uid/gid, executable by extension), drive letters and `\`,
   case-insensitivity, reserved names (CON, NUL, ...), symlinks (need privilege).
   `win/sim_hostfs.c` is the starting point (461 lines).
4. Console: Windows console/ANSI escape handling in `win/sim_hostuart.c`.

## Honest risks

- The sim switches contexts with hand-written assembly and stack tricks
  (`sim_fork_x86.S`, setjmp-style); the 32-bit x86 path was written for Linux and
  Cygwin, not for MinGW's different ABI details (SEH, TLS). It may need work.
- NuttX CI does not exercise the Windows simulator, so there may be more than
  the two missing files.
