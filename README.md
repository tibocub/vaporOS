```
                                  ____  _____
 _   ______ _____  ____  _____   / __ \/ ___/
| | / / __ `/ __ \/ __ \/ ___/  / / / /\__ \
| |/ / /_/ / /_/ / /_/ / /     / /_/ /___/ /
|___/\__,_/ .___/\____/_/      \____//____/
         /_/
```

> A tiny, hackable operating system, aiming for ARM/RISC-V/x86 devices such as
Raspberry Pis and ESP32s. Currently runs on NuttX's own simulator only --
no real hardware target is wired up yet.

VaporOS is an experimental project that aims to build a tiny operating environment for
ARM/RISC-V/x86 devices such as raspberry pis, esp32, etc. Inspired by retro computers,
early Unix systems, ComputerCraft, DOS...

Experimental vaporOS foundation built on [Apache NuttX](https://nuttx.apache.org/)

---

## STATUS

Custom graphical terminal implemented (vterm/vterm_fb) - NSH runs on a real NuttX pty, with live keyboard input and echo working. Input is still only read from the terminal vaporOS was launched from, not the graphical window itself (that's forwarded through, not yet captured directly).
Basic custom Lua implementation with the vapor API activated by default (just tests for now, no real interresting API features currently)

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
target) that runs as a native host binary -- this is what `setup.sh` builds
by default.

```
./setup.sh
```

This clones `nuttx` and `apps` (pinned to known-good commits, see the top of
the script) as siblings of this repo, symlinks this repo in as `apps/external`
(NuttX's supported mechanism for out-of-tree custom apps -- see
`apps/README.md`, "Adding Applications Outside the Apps Directory"), enables
this repo's apps, and builds the `sim:nsh` config.

```
../nuttx/nuttx
```

boots into a real NSH shell, entirely on your machine, no board required.

`setup.sh` takes an optional board-config argument for other targets --
`./setup.sh vterm_fb` builds vaporterm, the custom graphical terminal
described in STATUS above (needs an X server; see the top of `setup.sh`
for the full list of targets and what each one actually does).

---

## LAYOUT

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

  docs/         vapor-api.md and vaporterm.md -- design notes for the vapor
                API and the vterm_fb milestones, more detailed than this file.

  setup.sh      clones nuttx+apps, wires this repo in, compile

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
