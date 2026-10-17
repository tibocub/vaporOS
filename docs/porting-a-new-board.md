# Porting vaporOS to a new board

The goal is that supporting a new device is mostly *describing* it, because
the software (vaporshell, coreutils, Lua, vi, ...) only depends on NuttX's POSIX
layer. What follows is the real work involved, in order, with what the RP2040-Zero
port taught us. Bring-up order matters: each step gives you a way to debug the next.

## 0. Does NuttX already support the chip and the board?

Look in `nuttx/boards/<arch>/<chip>/`. Three cases:

- **Your exact board is there** (e.g. `waveshare-rp2040-zero`): go to step 2.
- **The chip is there but not your board** (a custom PCB, a different module):
  copy the closest board's directory; its `defconfig` and `src/` are small.
- **The chip is not supported by NuttX**: that is a NuttX architecture port, out
  of scope here.

## 1. Get *a* console

Nothing else is debuggable without one, and this is where boards differ most:

- UART console: easy; use `hardware/console/uart.conf` (untested so far).
- USB CDC-ACM console (no UART pins, e.g. the RP2040-Zero): `hardware/console/usb-cdcacm.conf`.
  Needs the NuttX `usbnsh` defconfig as the base, and the USB device driver of
  the chip to be sound. Expect to chase driver bugs (see patches/UPSTREAM.md:
  two of the six NuttX patches are USB fixes).

Start with NuttX's own `nsh` on that console. vaporOS's `vinit` replaces NSH only
after the console works.

## 2. Write `boards/<name>/board.conf`

Copy a board and adapt (boards/README.md). The decisions you actually make:

- `nuttx_config`: the NuttX board:config to start from.
- `[tools]`: toolchain and flashing tools the board needs, with environment overrides.
- `[features]`: start with `base` and add what fits. **Check flash and RAM first.**
  The RP2040 image is ~560 KB of a 2 MB flash and uses ~55 KB of 264 KB RAM at idle.
- `[hardware]`: console, storage, watchdog, ... with this device's parameters.
- `runner`: how to flash and open the console. Write `tools/runners/<name>.sh`
  (`flash`, `term`, `run`) if no existing runner fits.

Then `make -f dev.mk check`, `configure` and `build`. The build **fails if Kconfig
drops an option you asked for**; read the message, it names the missing dependency.

## 3. Resource budget

Small chips are where portability bugs show up. Measure, do not guess:

- `ps` shows each task's stack size and how much it used; `free` shows heap.
- Run the same command 20 times and compare `free` before and after: a leak that
  is invisible on a 64 MB simulator exhausts a 264 KB chip in minutes. (The
  tbx per-command leak was found exactly this way; it was ~13 KB per command.)
- Stack sizes of the software are in `features/*.conf`. If a task overflows its stack,
  NuttX does not fault; a garbage pointer appears elsewhere.

## 4. Persistent storage and boot media

- On-chip flash: `hardware/storage/flash-littlefs.conf` (RP2040 only today, via a
  NuttX patch). Keep it at a fixed offset so reflashing leaves files alone.
- SD card boot (a small bootloader in flash, the rest on a card) is the target for
  `hardware/storage/sdcard-spi.conf`, currently a `draft`: the pin assignment needs a
  vaporOS board-glue layer first (hardware/README.md explains why).

## 5. Test on the simulator too

`sim-nsh` builds the same features. If something works on the board and not on the
sim (or the other way round), it is almost always a missing assumption about the
environment, not a chip problem. This is the cheapest portability check there is:
`make -f dev.mk build run` takes a minute and needs no hardware.

## 6. Run compat-scan on anything you port

`compat-scan <path>` (host binary or `compat_scan` on vaporOS) flags the patterns
that have actually bitten this project: shared globals, `_exit()`, hard-coded
device paths, `/sys`, `TIOCGWINSZ`, `alloca`, fork, symlinks, ... See
docs/c-posix-compatibility.md. Log every real fix in docs/compat-log.md.

## 7. Record NuttX changes properly

If you had to change NuttX itself, put each change in its own file under
`patches/nuttx/` with the header described in patches/UPSTREAM.md (problem,
evidence, fix, upstream verdict) and list it in the board's `[patches]`. That record
is what lets a fix be contributed upstream later.
