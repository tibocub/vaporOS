# Next steps

Written 2026-10-18 after the board/hardware-descriptor work, the RP2040 bring-up
and the Windows spike. Ordered by what unblocks the most. Each step says what
"done" looks like. See docs/lua-runtime.md for the reasoning behind the runtime
direction, and patches/UPSTREAM.md for the NuttX changes we carry.

## 1. A real development loop on a board

Today the only way to get a file onto the RP2040 is to type it into `vi` on the
device. A programmable environment needs the PC side too.

- File transfer over the existing USB console: NuttX ships ymodem and zmodem
  (`nuttx-apps/system/ymodem`, `zmodem`), or we write a small host tool
  (`tools/vput.py`) speaking a trivial protocol to a vaporshell command.
- A few real **vlua apps** written and run on the board (blink-style output,
  files, text processing). They tell us what the vapor API actually lacks.
- Done when: `make -f dev.mk push BOARD=rp2040 FILE=app.lua` (or similar) puts a file
  in `/flash` and `vlua /flash/app.lua` runs it, with no manual typing.

## 2. Small known bugs (cheap, they erode trust)

| bug | where | notes |
|---|---|---|
| `date` leaks about 1 KB per call | tbx / libc | libc-internal (timezone) allocation not covered by the per-task tracker; measure with `free` |
| `find /bin` fails with "No such file or directory" while `ls /bin` works | toybox on binfs | not investigated |
| `..` of `/bin` shows mode `d---------` | binfs cannot stat `..` | cosmetic |
| the simulator's `/` shows a nonsense modification date | sim, early boot clock | does not happen on the RP2040 |
| `ps`/`top` show every toybox command as `tbx`, not the applet name | ps/top | would need tbx to set its task name |
| `console/uart` descriptor never exercised | hardware/ | `untested` |
| the CDC-ACM buffer enlargement may be unnecessary | hardware/console/usb-cdcacm | the real fix was the TX race; test without |
| `termcurses-read-retry` patch is probably unnecessary | patches/ | drop unless a failure is shown |
| a second look at `rp2040-usbdev-w1c-and-watchdog` | patches/ | find out which half, if either, matters |

Done when: each is fixed, or recorded in compat-log.md with the reason it stays.

## 3. A second chip (this is the real test of the board system)

The declarative boards, features and hardware descriptors were designed so that
a new target is mostly a config file. They have only run on the RP2040 and the
simulator, so that claim is untested. NuttX supports several ESP32-S3 boards
(`esp32s3-xiao`, `esp32s3-devkit`, `esp32s3-box`, ...), a priority target for this
project. Following docs/porting-a-new-board.md on a real second board will show
where we are not portable and how long a port actually takes.

- Needs: which board the project owner actually has (not decided).
- Expect work in: the toolchain (Xtensa), the runner (flash tool), console choice
  (USB serial/JTAG vs UART), memory budget, and whatever NuttX still lacks there.
- Done when: `make -f dev.mk run BOARD=<new>` gives a vaporshell, and the effort is
  written up (what was config, what was code, what was NuttX patches).

## 4. SD-card boot and other board wiring

Small bootloader in flash, the rest on a card, and user-configurable pins. Blocked
on a design: pins are usually board C code, not Kconfig, so a vaporOS board-glue
layer driven by descriptor parameters is needed (hardware/README.md). Start with the
design (what the glue layer generates, how a user supplies pins), then
`hardware/storage/sdcard-spi.conf` can leave `draft`.

Also needed for devices like the Cardputer: display, keyboard, audio descriptors.
None are written; the descriptor format is meant to take them.

## 5. The vapor API and the vlua event loop

Design after steps 1 and 3 so real apps and a second chip inform it:

- fill the confirmed gaps in docs/vapor-api.md (directories, mkdir, ...);
- decide the async story (docs/lua-runtime.md, options A/B/C) and measure libuv + luv
  on the RP2040 and the second board if B stays on the table;
- decide the ROM story (Lua source vs a stable bytecode vs wasm).

## 6. Experiments, not commitments

- **tinycc on the simulator** (compile and run C on vaporOS itself). Likely does not
  extend to the Cortex-M0+ or Xtensa (docs/lua-runtime.md).
- **Windows simulator**, paused (docs/windows-sim.md). Next action if resumed:
  install `mingw32-gcc` and try a 32-bit `sim:nsh` under wine.
- A hosted desktop shim of the vapor API (option C), only if "run it in the sim" turns
  out not to be enough.

## Maintenance reminders

- Every NuttX change gets its own patch with a header and a row in patches/UPSTREAM.md.
- Every real porting finding goes in docs/compat-log.md (and a compat-scan check if
  it can be detected from source).
- Test on the simulator as well as on the board; measure memory with `free` before
  and after repeated commands on the small chip.
