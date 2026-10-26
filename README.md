```
                                  ____  _____
 _   ______ _____  ____  _____   / __ \/ ___/
| | / / __ `/ __ \/ __ \/ ___/  / / / /\__ \
| |/ / /_/ / /_/ / /_/ / /     / /_/ /___/ /
|___/\__,_/ .___/\____/_/      \____//____/
         /_/
```

> A tiny, hackable operating system, aiming for ARM/RISC-V/x86 devices such as
Raspberry Pis and ESP32s. Runs on NuttX's simulator and on a real board, the
Waveshare RP2040-Zero (2 MB flash, USB console only).

VaporOS is an experimental project that aims to build a tiny operating environment for
ARM/RISC-V/x86 devices such as raspberry pis, esp32, etc. Inspired by retro computers,
early Unix systems, ComputerCraft, DOS...

Experimental vaporOS foundation built on [Apache NuttX](https://nuttx.apache.org/)

---

## STATUS

Targets (`make -f dev.mk boards`): `sim-nsh` (default), `sim-nxterm`, `sim-vterm_fb` and
`rp2040-zero`. On the RP2040-Zero vaporOS boots straight into vaporshell over USB
(no NSH) with Tab completion, vi, Lua (`vlua` REPL), `ps`/`top`/`free`/`df`/`dmesg`, and
a flash filesystem that survives reflashing -- see docs/rp2040.md.

Custom graphical terminal implemented (vterm/vterm_fb) - NSH runs on a real NuttX pty, with live keyboard input and echo working. Input is still only read from the terminal vaporOS was launched from, not the graphical window itself (that's forwarded through, not yet captured directly).
Basic custom Lua implementation with the vapor API activated by default (just tests for now, no real interresting API features currently)

### Lua on vaporOS (status 2026-10-26)

`vlua` runs Lua **5.4.8** (NuttX's default, 5.4.0, is the buggy first release) on the sim and on the
RP2040-Zero, where it gets a 24 KB stack and about 145 KB of heap. Lua libraries written in C are selected at build
time like any other feature (`features/lua-libs.conf`, enabled on `sim-nsh` and `rp2040-zero`) and preloaded, so
`require` works without files:

| library | version   | flash | Lua heap per `require` | notes                                                                                                 |
|---------|-----------|-------|------------------------|-------------------------------------------------------------------------------------------------------|
| `lpeg`  | 1.1.0     | 15 KB | 2.3 KB                 | own test suite passes on the board (chunked and scaled, `tools/lpeg-board-test/`)                     |
| `cjson` | lua-cjson | 8 KB  | 1.8 KB                 |                                                                                                       |
| `lfs`   | 1.9.0     | 4 KB  | 2.6 KB                 | own suite passes on the board; no symlinks, no `.`/`..`, `touch` needs littlefs (ENOSYS on FAT/tmpfs) |

Pure Lua libraries will be expected to be compatible but right now vaporOS don't have a package manager or
a luarocks equivalent (planned) so there is currently no way of getting other Lua libs beside manual download.

Sources are sibling checkouts that `setup.sh` fetches and pins. Limits you will meet on a 24 KB stack:
lpeg grammars are capped at 200 rules and capture nesting at 20 (`VAPOROS_VLUA_LPEG_MAXRULES`/`_MAXRECLEVEL`;
deeper input gives a Lua error, not a reset) and Lua's C-call depth is capped at 40 (`lua-maxccalls` patch).
`os.exit()` closes the Lua state, because NuttX does not reclaim a task's heap and each exit used to leak 35-40 KB.
Everything we changed in NuttX is a documented patch in `patches/` (index: `patches/UPSTREAM.md`); porting
findings are in `docs/compat-log.md`. Details and measurements: [docs/lua-runtime.md](docs/lua-runtime.md).

**Numbers are 64-bit (integers and doubles), on purpose.** NuttX's "32-bit Lua" option never worked (a config typo,
and Lua 5.4.3+ ignores the flag; `lua-32bit-typo` fixes both so it can be turned on). We measured both on the
RP2040 and kept 64-bit so scripts and libraries from the Lua ecosystem behave as they do everywhere else:

| RP2040, one run each                     | 32-bit               | 64-bit               |
|------------------------------------------|----------------------|----------------------|
| 300k integer-loop steps                  | 0.90 s               | 2.43 s               |
| 60k `math.sin`                           | 23.1 s               | 7.4 s                |
| fib(23) / strings / sorting 4000 numbers | 0.33 / 0.86 / 0.48 s | 0.36 / 0.81 / 0.50 s |
| heap for a 4000-number table             | 48 KB                | 83 KB                |
| flash                                    | 628 KB               | 636 KB               |

32-bit saves RAM and integer speed but is slower on floats, keeps ~7 digits (JSON numbers, timestamps), wraps
integers at 2^31 and makes `lfs.touch` round times to 128 s. We'll switch only if RAM or speed become impractical
(`CONFIG_INTERPRETERS_LUA_32BIT=y` in `features/lua.conf`).

**Where `require` looks** (`package.path`, built in `vlua_main.c`): `lua_modules/` in the current directory (project
libraries, so a project can pin its own versions), then the system-wide directory `VAPOROS_VLUA_LIBDIR`
(default `/usr/lib/lua`, `/flash/lib/lua` on the RP2040 so it survives reflashing), then the current directory;
each as `?.lua` and `?/init.lua`. Setting `LUA_PATH` replaces all of it. Only pure-Lua code can live there: C
libraries (lfs, lpeg, cjson) are linked in at build time. A future package manager only has to download files
into one of those two directories.

vlua collects garbage early (`lua_gc(L, LUA_GCINC, 100, 400)`, vlua_main.c): RAM is scarcer than CPU, and lfs's own suite
needs it to fit. Cost measured on the RP2040: the string-building benchmark goes from 0.8 s to 4.8 s, the others are unchanged.
Not yet: a package manager (deferred), cjson's own test suite, the sim with the final 64-bit build re-run.

---

## FLASHING (humans and AI agents)

    make -f dev.mk build BOARD=rp2040     # compile  -> ../nuttx/nuttx.uf2
    make -f dev.mk flash BOARD=rp2040     # reboots a RUNNING board into BOOTSEL by itself, copies the UF2
    make -f dev.mk run   BOARD=rp2040     # flash + serial console

No button presses: the firmware reboots into the boot loader when the host sets the USB serial port to **1200 baud**
(`stty -F /dev/ttyACM0 1200`), even if the application is hung. Details, fallbacks and how to script the console:
[docs/rp2040.md](docs/rp2040.md#reflashing-without-touching-the-board-humans-and-ai-agents).

---

## WHY NUTTX

Real POSIX conformance out of the box -- `chdir`/`getcwd`, `lseek`,
`dup`/`dup2`, `fcntl`, `chmod`/`chown` all work without hand-building a
compatibility layer, unlike Zephyr where several of these are simply absent.
NuttX also ships an in-tree Lua interpreter and a POSIX-shaped
(`open`/`read`/`write`/`ioctl` on `/dev/*`) device driver model, both directly
relevant to vaporOS's ComputerCraft-inspired goals.

The plan is to mobilize as much of this as possible directly -- NSH as the
temporary shell, NuttX's own VFS and filesystem support, the in-tree Lua
interpreter -- rather than rebuild what NuttX already provides well.

---

## THE ESP32, MORE POWERFUL THAN IT LOOKS

In terms of available RAM, we could compare the ESP32 to a computer from the 80s. Howerver, while the
comparison is useful from a software design perspective, the processor itself is vastly more capable
than a 80s PC and even the smallest SD card would outcast from a magnitude storage solutions from that time.

| Machine        |                                      CPU |                     RAM |             ADDITIONAL/EXTERNAL STORAGE |
| -------------- | ---------------------------------------: | ----------------------: | --------------------------------------: |
| Apple II       |                                    1 MHz |              4 to 64 KB |  Audio cassettes / floppy ~ 140 KB-1 MB |
| IBM PC XT      |                                 4.77 MHz |           128 to 640 KB |                         10 to 20 MB HDD |
| Macintosh 128K |                                    8 MHz |           128 to 512 KB |              64 KB ROM +  400 KB floppy |
| **ESP32**      |                    **240 MHz Dual-Core** |              **520 KB** |        **4MB flash + 1GB-32GB SD card** |
| **ESP32-C6**   |            **160 MHz + 20MHz low power** |              **520 KB** |        **4MB flash + 1GB-32GB SD card** |
| **ESP32-S3**   |      **240 MHz Dual-Core 32-bit RISC-V** | **520 KB + 16MB PSRAM** |       **16MB flash + 1GB-32GB SD card** |
| **RP2040**     |                **133 MHz Dual-Core ARM** |  **264 KB + 8MB PSRAM** |        **2MB flash + 1GB-32GB SD card** |
| **RP2350**     |             **150 MHz Dual-Core RISC-V** |  **520 KB + 8MB PSRAM** |        **4MB flash + 1GB-32GB SD card** |

---

# Architecture

One of the project's primary goals is long-term portability.

Although simulator and ESP32 are the initial target platforms, the architecture (and because
it's built on nuttx) should make future ports straightforward.

Applications should never directly access ESP32-specific APIs.

Instead, they communicate through a stable system interfaces.

```text
+-----------------------------+
|     C/Lua Applications      | <- simple programs and scripts using the high-level vaporOS API
+-----------------------------+
|   Vapor API and Services    | <- default services and high-level API for C and Lua programs
|  Files - UI - Shell - Mesh  |
+-----------------------------+
|       Capability Layer      | <- exposes what the device CAN do (does it have a screen, a keyboard, wifi, etc)
+-----------------------------+
|     Platform Abstraction    | <- hides hardware implementation
+-----------------------------+
|            Nuttx            | <- the "kernel" (actually also a significant part of the OS), provides the low-level API to use the hardware
+-----------------------------+
| ESP32 | RP2040 | STM32 ...  | <- nuttx-supported hardware targets
+-----------------------------+
```

This separation keeps platform-specific code isolated and allows most of the project to remain completely portable.

## Hardware Independance

Applications should not care on what platform they are running, and should not assume that every devices has
wifi, a keyboard, LoRa radio, etc.

VaporOS should provide a stable set of high-level services and adapt them to the available hardware on each device.
This allow devs to work with a pleasant API while keeping apps portable.

---

# Platform Abstraction

The operating environment should expose concepts rather than hardware details.
Instead of manipulating GPIO pins directly, applications should work with higher-level APIs whenever possible.

For example:

```lua
display.clear()

mesh.send(peer, message)

led.set(true)

sleep(1000)
```

The implementation behind these functions may differ between platforms, but applications remain identical and compatible.

This both simplifies portability and improves the developer experience.

---

## NOT LINUX

VaporOS is **not** trying to become another Linux distribution.

**However**, we can enjoy the efforts made for the Nuttx project to follow the **POSIX** and **ANSI** standards
which make it possible to be **compatible with a variety of programs and libraries** and a **unix feeling**.

This allows us to make design decisions that would be undesirable — or straigt up stupid — on a modern operating system.

For instance, groups/users and proper process isolation are not planned. The current vision of vaporOS would actually
be technically closer to DOS than Unix while still providing a familliar Unix-like feeling for Linux/BSD/Mac users.

---

## VAPOR APIs

The vapor API is a C library that also have bindings for Lua.

It is both possible to make super efficient application in C (maybe later also Rust and Nim)
and easy Lua programs with optional LuaJIT compilation.


The API was inspired by computercraft, a minecraft mod wich adds computers with
a simpleprogrammable environement that is a sandboxed Lua process running into the
game's server. The architectures of computercraft and vaporOS are quitedifferent,
e.g; for computercraft, the game's server can be considered the "kernel" of multiple
isolated instances (each in-game running computer); in vaporOS, it's much closer to a
unix OS running on real hardware (or the native simulator), being able - amongst many
other things - to run a Lua process with a simple high-level custom Lua API to make
vapor programs.

---

## PORTABILITY

The OS itself should be portable to nuttx compatible targets (ESP32, RP2040 and many
others) and on native nuttx simulators (linux/mac/windows).

VaporOS should have decent compliance with the unix ecosystem such as the POSIX and ANSI
standards in order to be compatible with many programs and libraries

Taking things further, since the point of vaporOS is to make an OS that feels retro and
is simple to hack and fully grasp, we could find a way to compile a vaporOS program into
a single binary that can be flashed hardware compatible with nuttx without the full OS
bload and we could also think of a possibility to export on linux/mac/windows by compiling
a minimal nuttx simulator setup with the binary. This last idea could be challenging since
it would mean establishing an access bewteen nuttx and the host's filesystem so that probably
means extending vaporOS's vfs to support the host filesystem when compiled for the simulator.

---

# GOALS

The long-term vision includes:

- terminal-first user interface
- lightweight graphical text interfaces
- Lua scripting
- application system
- package manager
- shell
- filesystem abstraction
- hardware abstraction
- LoRa integration
- mesh networking (meshcore/meshtastic/reticulum)
- configuration system
- plugin support
- maybe a lightweight C compiler (tinycc, chibicc, etc)

The experience should feel much closer to using an old workstation than a modern smartphone.

---

## GETTING STARTED

No real hardware needed to start. NuttX has its own simulator (`sim`
target) that runs as a native host binary.

Windows dev happens through WSL/Git Bash/MSYS2 -- some of NuttX's own
tooling (`./tools/configure.sh`) is a real bash script, so there's no
avoiding bash somewhere in the chain either way.

```
./setup.sh          # clones nuttx+apps+vaporOS-coreutils, wires them
                     # all in as siblings (see LAYOUT below), applies patches/
make -f dev.mk build
make -f dev.mk run
```

boots into a real NSH shell, entirely on your machine, no board required
(`vaporshell` starts from it).

Every target is a directory under `boards/`; pick one with `BOARD=`:

```
make -f dev.mk boards                    # list targets
make -f dev.mk build BOARD=vterm_fb      # vaporterm, the custom graphical terminal (needs X)
make -f dev.mk run   BOARD=rp2040        # build first; then flash a RP2040-Zero and open its USB console
make -f dev.mk show  BOARD=rp2040        # the full resolved configuration, with the reason for each option
```

A board is a small declarative file naming a NuttX base configuration, the software
`features/` it includes and the `hardware/` it is wired with (console, storage, pins).
Supporting your own device is mostly editing that file, not code: see
[boards/README.md](boards/README.md), [hardware/README.md](hardware/README.md) and
[docs/porting-a-new-board.md](docs/porting-a-new-board.md). Our changes to NuttX
itself, and why we made them, are in [patches/UPSTREAM.md](patches/UPSTREAM.md).
`make -f dev.mk help` lists every command.

---

## LAYOUT

`setup.sh` expects (and creates) this exact sibling layout -- nothing
here is relative to your home directory or any fixed path, only to
each other, so the whole thing can live anywhere:

```
some-parent-dir/
  nuttx/              pinned NuttX checkout
  apps/                pinned nuttx-apps checkout
                       apps/external -> ../vaporOS-nuttx
  vaporOS-nuttx/        this repo
                       toybox -> ../vaporOS-coreutils
                       vaporshell -> ../vaporshell
  vaporOS-coreutils/   the toybox/coreutils port, its own repo (see below)
  vaporshell/          the shell itself, its own repo (see below)
```

`apps/external`, `vaporOS-nuttx/toybox`, and `vaporOS-nuttx/vaporshell`
are all symlinks that only resolve correctly because of this fixed,
sibling relationship -- if you ever move one of these directories
independently of the others, they'll break. `setup.sh` sets this up
for you automatically; this is only worth knowing explicitly if
you're scripting around it, or setting the workspace up by hand
instead.

```
vaporOS-nuttx/
  vhello/       proof-of-concept app: confirms the apps/external
                mechanism actually reaches this repo and a custom
                command shows up in NSH (`Builtin Apps: ... vhello`)

  vlua          vaporOS's Lua host. Creates its own Lua state (doesn't touch
                NuttX's own `lua` command) and always registers the vapor API
                before running anything, so every script run through vlua has it
                available -- this program IS the vapor-enabled Lua runtime, not
                a separate thing that later gets pointed at one.

  vterm         Vendored libvterm (MIT) plus vtermtest, a milestone-1 proof
                that it renders correctly -- see docs/vaporterm.md.

  vterm_fb      vaporterm: a custom graphical terminal, current focus (see
                STATUS above). Runs a real NSH session on a NuttX pty and
                renders it straight to /dev/fb0 via libvterm -- built to
                replace NxTerm, whose own VT100 support is incomplete.

  portable_cat,
  portable_wc   Portability smoke tests, not compatibility shims -- ordinary
                C/POSIX code (fopen/fgetc/getopt, no NuttX-specific headers)
                that's meant to compile and run completely unmodified, as a
                signal that NuttX's POSIX layer is real. See their own
                top-of-file comments for more.

  toybox/       Symlink to the vaporOS-coreutils repo (a sibling checkout,
                see the workspace tree above) -- the toybox/coreutils port
                grew past a compatibility port into its own fork (own
                defaults, own commands beyond what toybox or NSH provide),
                so it now lives, versions, and builds its own commit
                history independently. Kept as a symlink here rather than
                a git submodule so the existing $(APPDIR)/external/toybox
                path (and NuttX's own Kconfig auto-discovery, which
                follows symlinks) both keep working unchanged.

  vaporshell/   Symlink to the vaporshell repo (a sibling checkout, see the
                workspace tree above) -- split out for the same reason
                toybox was, plus one more: keeping vaporshell independent
                of any specific command set, so it isn't coupled to
                vaporOS-coreutils specifically and other NuttX projects
                could use it with a different one. See that repo's own
                README/docs/design.md for the shell itself.

  docs/         vapor-api.md and vaporterm.md -- design notes for the vapor
                API and the vterm_fb milestones, more detailed than this file.
                (vaporshell's own design doc moved to its own repo, along
                with the code -- see vaporshell/docs/design.md.)

  setup.sh      clones nuttx+apps+vaporOS-coreutils+vaporshell, wires them
                all in and applies patches/

  boards/       one directory per target (board.conf): the NuttX base config,
                features, hardware wiring, host toolchain, how to flash/run.
  features/     reusable software bundles (base, lua, vi, ...) as NuttX options,
                each option with its rationale
  hardware/     parameterised peripheral descriptors (consoles, storage, display,
                ...): pins, buses and paths are parameters, not code
  local/        your own per-board overrides (untracked)
  patches/      our changes to NuttX/nuttx-apps, one per concern, with the
                reasoning and upstream status (UPSTREAM.md)
  tools/        vconfig.py (resolves boards), apply-patches.sh, runners/ (flash and
                console per target), RP2040 helpers
  vinit/        init for boards without NSH: console bring-up, then vaporshell

  Makefile      required by NuttX's app-directory convention
                (delegates to apps/Directory.mk)

  Make.defs     registers this repo's apps with NuttX's build

```

Each vaporOS command/app gets its own subdirectory here, following the
same `Makefile`/`Kconfig`/`<name>_main.c` shape as `vhello/` -- this
mirrors NuttX's own convention (see `apps/examples/hello/` upstream) so
nothing about the pattern is vaporOS-specific.

---

# Retro-inspired modern Computing, not Nostalgia

The goal is not to recreate an old computer.

The goal is to rediscover the philosophy that made those systems enjoyable:

- small codebases
- understandable software
- no dependency/DLL hell
- efficient resource usage
- hackability
- complete user control
- software closer to hardware

The constraints are different today, but the philosophy remains attractive and particularily
relevant in embed systems.

**A quote from [Alan Cox's first fuzix code release](https://archive.wikiwix.com/cache/?url=https%3A%2F%2Fplus.google.com%2F%2BAlanCoxLinux%2Fposts%2Fa2jAP7Pz1gj)**:

```text
Fed up of SystemD ?
Kdbus the final straw ?
Linux community too large and noisy ?
Yearn for the good old days when you knew every contributor by
name and the source code fitted on a single floppy disc ?
```

---

# ROADMAP

Current direction and ordered next steps: [docs/next-steps.md](docs/next-steps.md).
The reasoning about a cross-platform Lua runtime (vlua), libuv vs. our own event loop,
portable program formats and the paused Windows simulator:
[docs/lua-runtime.md](docs/lua-runtime.md), [docs/windows-sim.md](docs/windows-sim.md).

## VarporUtils
this section simply keep track of the implementation of the basic commands required to make
any unix-like system usable and isn't tied to a particular roadmap goal (but most should at
least be WIP before ALPHA release to consider vaporOS usable).

Nuttx defaults:
- alias
- basename
- break
- cat
- cd
- cmp
- cp
- dirname
- dmesg
- du
- echo
- exec
- exit
- expr
- false
- help
- hexdump
- kill
- ls
- mkdir
- mkfifo
- mkrd
- mount
- mv
- poweroff
- printf
- pwd
- quit
- rm
- rmdir
- set
- sleep
- source
- test
- time
- true
- truncate
- umount
- unalias
- uname
- unset
- uptime
- usleep
- watch
- xd

vaporOS utils (complement Nuttx's unix compatibility):
[ ] - arch
[ ] - b2sum
[ ] - base32
[ ] - base63
[ ] - basename
[ ] - basenc
[ ] - cut
[ ] - date
[ ] - echo
[ ] - env
[ ] - expand
[ ] - expr
[ ] - factor
[ ] - false
[ ] - fmt
[ ] - fold
[ ] - ln
[ ] - logname
[ ] - md5sum
[ ] - nice
[ ] - nl
[ ] - nproc
[ ] - numfmt
[ ] - printenv
[ ] - printf
[ ] - readlink
[ ] - seq
[ ] - sha1sum
[ ] - sha224sum
[ ] - sha256sum
[ ] - sha384sum
[ ] - sha512sum
[ ] - shred
[ ] - sleep
[ ] - sort
[ ] - split
[ ] - stty
[ ] - sum
[ ] - tac
[ ] - tail
[ ] - touch
[ ] - tr
[ ] - true
[ ] - truncate
[ ] - tsort
[ ] - tty
[ ] - uname
[ ] - unexpand
[ ] - uniq
[ ] - unlink
[ ] - uptime
[ ] - wc
[ ] - yes


## ALPHA
Setting up core API, libs, shell, Lua, basic commands to naviagte and execute...

- A minimal yet usable unix-like environement
- A Lua scriptable API for automation, programs, apps...
- A simple pkg manager to share and install native bins, libraries and lua programs/scripts
- Maybe a C compiler such as gcc or tcc (if realistically possible)
to compile native vaporOS apps directly from vaporOS as in unix.

In aproximate priority order:
[ ] - Services
    [ ] - cli service manager
    [ ] - maybe runit-like symlink-based service management
    [ ] - service to test services implementation (e.g; a clon of crond)
[WIP] - Lua
    [ ] - vaporOS API Lua biddings
[ ] - vaporOS native TUI lib/engine for both C and Lua (and maybe Nim and Rust)
[ ] - Pkg (package manager)
    [ ] - hosted on github/gitea/gitlab... (kinda like Nim's package manager)
    [ ] - post-install/removal scripts
    [ ] - an extensive tags/description/requirement system (unlike in linux, here
          dependencies are not only other programs/libs, they could also be hardware
          components such as LoRa, Bluetooth, Audio, Keyboard, etc.)
[ ] - C Compiler
    [ ] - Multiple choice for different system limitations (full gcc if SD card or tcc/chibicc for storage-less environements)
    [ ] - Must be able to compile and install a vaporOS program from sources
[x] - Portable C support -- no shim layer needed, unlike under Zephyr: NuttX gives
      real POSIX (open/read/write/stat/opendir/readdir, getopt, fork/exec/pipe/wait/
      signals where the target supports them) for free. portable_cat and portable_wc
      exist specifically to prove this -- ordinary C/POSIX code, no vapor-anything,
      meant to compile and run completely unmodified.
[ ] - Improved Shell (extend NSH, or a custom one built on top of it)
    [ ] - Make it scriptable to make powerfull one-liners in the repl or write shell scripts (either with lua or with a interpretter)
    [ ] - rc file to persist users configs (aliases, prompt, custom functions, etc)
    [ ] - history persistence
[ ] - Basic security
    [ ] NuttX's own CONFIG_STACK_CANARIES (stack overflow detection)

## BETA
Usable but still evolving, breaking changes expected

- Vim-like editor (maybe fork CCVim for computercraft)
- Make sure basic tools such as wget, git, curl, etc can run or provide alternatives
- Improve system customization and hardware/peripheral compatibility

[ ] - Better security
    [ ] - optional NuttX PROTECTED/KERNEL build mode for supported targets (gives actual process isolation but not possible on all hardware)
[ ] - (maybe) bare (holepunch's lightweight nodeJS-like runtime, NOT nuttx's bare app)

## RELEASE V1.0
Stable API release and reliable tooling

- Stable vaporOS API and tooling (builtin programs and libs)
- Reliable package manager and full OS updates
- Just enough POSIX compatibility layer to port many unix programs as effortlessly as possible without implementing full POSIX-complience.

---

# Inspirations

Projects that influenced VaporOS:

- [ComputerCraft](https://tweaked.cc)
- [Meshtastic](https://meshtastic.org)/[Meshcore](https://meshcore.co.uk/)/[MicroReticulum](https://github.com/attermann/microReticulum)
- [Flipper zero](https://flipper.net)
- [Fuzix](https://fuzix.org) and early Unix/DOS systems
- [Byzantium](https://linuxfreedom.com/byzantium)

---

# License

MIT
