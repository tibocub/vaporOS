```
                                  ____  _____
 _   ______ _____  ____  _____   / __ \/ ___/
| | / / __ `/ __ \/ __ \/ ___/  / / / /\__ \
| |/ / /_/ / /_/ / /_/ / /     / /_/ /___/ /
|___/\__,_/ .___/\____/_/      \____//____/
         /_/
```
> A tiny, hackable operating system for micro-controllers (currently focused on
ESP32, might extend later to other ARM/RISC-V chips).


> **Status:** Very early alpha, still tinkering the architecture

---

# Overview

VaporOS is an experimental project that aims to build a tiny operating environment for
ARM/RISC-V/x86 devices such as raspberry pis, esp32, etc. Inspired by retro computers,
early Unix systems, ComputerCraft, DOS...

Unlike most ESP32 projects, the goal is **not** to build a single-purpose firmware or
another consumer-oriented device.

Instead, VaporOS aims to provide a reusable software platform that makes tiny embedded
devices feel like real computers.

Imagine turning on a handheld ESP32 device and being greeted by a shell instead of a
splash screen.


From there you can:

- browse files
- launch applications
- write Lua scripts and apps
- automate tasks
- communicate over LoRa mesh networks
- edit text
- customize your environment
- install community-made applications

The project intentionally embraces the constraints of embedded hardware instead of trying to imitate
a modern desktop operating system.

---

# Philosophy

## Tiny hardware can still be exciting

Modern computers have become incredibly powerful, but also incredibly complex.

Micro-controllers such as the ESP32 sits in an interesting middle ground.

Although it has only a few hundred kilobytes of RAM, it is fast enough to build surprisingly capable systems.

Rather than viewing these limitations as obstacles, VaporOS treats them as design constraints that encourage
elegant and creative solutions. These limitations also becomes interresting as it forces us to keep things
simple, making vaporOS' softwares easy to understand and modify.

In other words, unlike on modern OSes, you don't need to be a senior software engineer to understand and
contribute to a codebase and developping an app for vaporOS becomes incredibly trivial when compared to
developping an app for Linux/MacOS/Windows/Android/iOS.

This project takes much of its inspiration from:

- early/retro OSes (Unix, DOS, BSD, Fuzix...)
- ComputerCraft
- cyberdecks
- flipper zero

---

## The ESP32 is more powerful than it looks

In terms of available RAM, we could compare the ESP32 to a computer from the 80s. Howerver, while the
comparison is useful from a software design perspective, the processor itself is vastly more capable
than a 80s PC and even the smallest SD card would outcast from a magnitude storage solutions from that time.

| Machine        |                           CPU |                         RAM |                          STORAGE |
| -------------- | ----------------------------: | --------------------------: | -------------------------------: |
| Apple II       |                         1 MHz |                       64 KB | Audio cassettes            ~ 1MB |
| IBM PC XT      |                      4.77 MHz |                      256 KB | HDD                      10-20MB |
| Macintosh 128K |                         8 MHz |                      128 KB | Floppy disk               400 KB |
| **ESP32**      |         **240 MHz Dual-Core** |             **520 KB SRAM** | **4MB flash + 1GB-32GB SD card** |
| **ESP32-C6**   | **160 MHz + 20MHz low power** |             **520 KB SRAM** | **4MB flash + 1GB-32GB SD card** |
| **ESP32-S3**   |         **240 MHz Dual-Core** | **520 KB SRAM + 8MB PSRAM** | **8MB flash + 1GB-32GB SD card** |

The challenge isn't processing power or available storage, it's making the most of its limited SRAM while
keeping the system reliable, responsive and enjoyable to use.

---

## Not Linux

VaporOS is **not** trying to become another Linux distribution.

It is also **not** trying to implement POSIX or provide full binary compatibility with another OS.

Instead, it focuses on providing a clean, lightweight, and enjoyable operating environment specifically
designed for embedded devices.

This allows us to make design decisions that would be undesirable — or straigt up stupid — on a modern operating system.

For instance, groups/users and proper process isolation are not planned. The current vision of vaporOS would actually
be technically closer to DOS than Unix while still providing a familliar Unix-like feeling for Linux/BSD/Mac users.

---

# Goals

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

# Lua

Lua is one of the smallest and most portable scripting languages ever created.

It also is one of the most popular, reliable and fastest high-level interpreted languages around.

Embedding Lua allows users to automate tasks, write applications, customize interfaces and
prototype ideas without recompiling the firmware.

The firmware provides the low-level capabilities.

Lua provides flexibility.

---

# Architecture

One of the project's primary goals is long-term portability.

Although ESP32 is the initial target platform, the architecture (and because it's built on
zephyr) should make future ports straightforward.

Applications should never directly access ESP32-specific APIs.

Instead, they communicate through stable system interfaces.

```text
+-----------------------------+
|     C/Lua Applications      | <- simple programs and scripts using the high-level vaporOS API
+-----------------------------+
|      VaporOS Services       | <- default services and high-level API for Lua programs
|  Files - UI - Shell - Mesh  |
+-----------------------------+
|       Capability Layer      | <- exposes what the device CAN do (does it have a screen, a keyboard, wifi, etc)
+-----------------------------+
|     Platform Abstraction    | <- hides hardware implementation
+-----------------------------+
|            Zephyr           | <- the "kernel" (actually also a significant part of the OS), provides the low-level API to use the hardware
+-----------------------------+
| ESP32 | RP2040 | STM32 ...  | <- zephyr-supported hardware targets
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

## Software portability and compatibility

I think VaporOS could eventually have two tiers of software:

### Native vaporOS programs
*(computercraft-style programs)*
Use the vapor API directly.
Best performance and integration.

### Portable C programs
*(classic unix programs such as grep, sed, awk, find...)*
C stdlib + a small POSIX-shaped layer (file ops, dirents, getopt).
This is a closed list, not a growing target. This would only be extended
to support a specific port that need one more primitive (no fork/exec/pipe/wait/signals/...).

Full POSIX isn't a goal, we just want enough POSIX to compile some libraries
and utilities with little to no vaporOS-specific changes.

Basically, if a program needs fork, exec, pipe, etc. we should simply make a lighter
vaporOS-specific alternative (using the vapor API), else we might be able to compile
or port it easily.

### What Zephyr already provides

Zephyr's own C library support (minimal libc/newlib/picolibc) only covers the ISO C
standard library: `malloc`/`free`, `printf`/`scanf`, `string.h`, `math.h`... It does
**not** include file I/O, directories, or sockets — those live in a separate layer.

That separate layer already exists in Zephyr, and it's POSIX-**shaped** on purpose:

- a file system API (`fs_open`/`fs_read`/`fs_write`/`fs_unlink`/`fs_rename`/dir reading...)
  explicitly designed to look like POSIX for developer familiarity, without claiming
  POSIX compliance
- an opt-in POSIX subsystem (PSE51/PSE52 profiles + BSD sockets) that can expose real
  POSIX symbol names (`open`, `read`, `socket`...) if we ever want them, instead of the
  old catch-all `CONFIG_POSIX_API` flag

**Decision:** our VFS wraps Zephyr's `fs_*` subsystem as its backend rather than
reimplementing file I/O from scratch, and keeps its own vapor-prefixed naming instead of
enabling Zephyr's POSIX alias config. This gives portable C programs the POSIX-*shaped*
primitives they need (file ops, dirents, getopt) without inheriting Zephyr's growing
POSIX profile surface or its symbol-namespace concerns.

Note: an older Zephyr issue reported that enabling the POSIX file API and BSD sockets
together could break linking. Worth a quick sanity check against whatever Zephyr version
we target before leaning on both at once (relevant for tools like wget/curl that need
file writes + sockets together).

---

# Device Capabilities

VaporOS is designed around **capabilities**, not specific hardware.

Rather than assuming every device has the same peripherals, the operating environment
adapts to the hardware that is actually available.

For example, one device might provide:

- a display
- a keyboard
- LoRa
- Wi-Fi

while another might only provide:

- LoRa
- Bluetooth
- a status LED

Applications should interact with high-level services rather than individual chips or
peripherals whenever possible.

This allows the same application to run on many different devices while automatically
taking advantage of the hardware they provide.

As the project grows, this architecture should make it possible to support not only
different ESP32 variants, but also entirely different microcontroller families with
minimal changes to application code.

---

# What about the "kernel"?

VaporOS does **not** attempt to replace the underlying RTOS.

Instead, it builds on proven embedded technologies that already solve
complex low-level problems such as:

[Zephyr]
- Scheduling
- Networking
- Filesystem (POSIX-shaped `fs_*` API — our VFS builds on top of this)
- Timers
- USB
- Bluetooth
- Synchronization
- Device model
- Hardware drivers

[Lua]
- Super lightweight interpreter for a dynamic user experience
- Perfect language choice to easily expose a C API

VaporOS focuses on everything above that layer:

- shell
- applications
- UI
- scripting
- package management
- user experience

---

# Retro-futurist Computing, not Nostalgia

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

[WIP] - ls
[WIP] - cd
[WIP] - mkdir
[WIP] - mv
[WIP] - rm
[WIP] - df
[WIP] - cat
[WIP] - pwd
[WIP] - write
[ ] - cp
[ ] - ln
[ ] - rmdir
[ ] - touch
[ ] - truncate
[ ] - b2sum
[ ] - base32
[ ] - base63
[ ] - basenc
[ ] - md5sum
[ ] - sha1sum
[ ] - sha224sum
[ ] - sha256sum
[ ] - sha384sum
[ ] - sha512sum
[ ] - shred
[ ] - cut
[ ] - expand
[ ] - unexpand
[ ] - fold
[ ] - nl
[ ] - fmt
[ ] - numfmt
[ ] - sort
[ ] - split
[ ] - sum
[ ] - tac
[ ] - tail
[ ] - tr
[ ] - tsort
[ ] - uniq
[ ] - wc
[ ] - arch
[ ] - basename
[ ] - date
[ ] - echo
[ ] - env
[ ] - printenv
[ ] - expr
[ ] - factor
[ ] - true
[ ] - false
[ ] - logname
[ ] - nice
[ ] - nproc
[ ] - printf
[ ] - readlink
[ ] - seq
[ ] - sleep
[ ] - stty
[ ] - tty
[ ] - uname
[ ] - unlink
[ ] - uptime
[ ] - yes


## ALPHA
Setting up core API, libs, shell, Lua, basic commands to naviagte and execute...

- A minimal yet usable unix-like environement
- A Lua scriptable API for automation, programs, apps...
- A simple pkg manager to share and install native bins, libraries and lua programs/scripts
- Maybe a C compiler such as gcc or tcc (if realistically possible)
to compile native vaporOS apps directly from vaporOS as in unix.

In aproximate priority order:
[WIP] - Temporary Shell (built on zephyr's shell)
[x] - Run (execute external programs)
[WIP] - VFS (filesystem API over LittleFS, ramfs, FAT32...)
    [WIP] - VFS API
    [WIP] - mount
    [WIP] - rootfs
    [WIP] - romfs
    [WIP] - littlefs backend
    [ ] - FAT32 backend
[ ] - Services
    [ ] - cli service manager
    [ ] - maybe runit-like symlink-based service management
    [ ] - service to test services implementation (e.g; a clon of crond)
[ ] - Lua
    [ ] - vaporOS API Lua biddings
    [ ] - vaporOS native TUI lib/engine for both C and Lua
[ ] - Pkg (package manager)
    [ ] - hosted on github/gitea/gitlab... (kinda like Nim's package manager)
    [ ] - post-install/removal scripts
    [ ] - an extensive tags/description/requirement system (unlike in linux, here
          dependencies are not only other programs/libs, they could also be hardware
          components such as LoRa, Bluetooth, Audio, Keyboard, etc.)
[ ] - C Compiler
    [ ] - Multiple choice for different system limitations (full gcc if SD card or tcc/chibicc for storage-less environements)
    [ ] - Must be able to compile and install a vaporOS program from sources
[ ] - Portable C support layer (POSIX-shaped, not POSIX-compliant)
    [ ] - wrap Zephyr's fs_* API for file/dir ops (open/read/write/stat/opendir/readdir)
    [ ] - getopt/getopt_long
    [ ] - no fork/exec/pipe/wait/signals — use native vapor alternatives instead
[ ] - Improved Shell (rewrite custom or improve zephyr's shell)
    [ ] - Make it scriptable to make powerfull one-liners in the repl or write shell scripts (either with lua or with a interpretter)
    [ ] - rc file to persist users configs (aliases, prompt, custom functions, etc)
    [ ] - history persistence
[ ] - Basic security
    [ ] zephyr's CONFIG_STACK_CANARIES (stack overflow detection, available for all zephyr supported targets)

## BETA
Usable but still evolving, breaking changes expected

- Vim-like editor (maybe fork CCVim for computercraft)
- Make sure basic tools such as wget, git, curl, etc can run or provide alternatives
- Improve system customization and hardware/peripheral compatibility

[ ] - Better security
    [ ] - optional zephyr CONFIG_USERSPACE for supported targets (gives actual process isolatoin but not possible on all hardware)
[ ] - (maybe) bare (holepunch's lightweight JS runtime)

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
