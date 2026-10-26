# NuttX patches: what, why, and whether they could go upstream

vaporOS targets stock NuttX 13.0.x. Every change to NuttX or nuttx-apps lives
here as a separate patch so that (a) it is clear *why* it exists, and (b) the ones
that are real fixes can be contributed once there is a clean reproducer.
`tools/apply-patches.sh` applies them (idempotently); `setup.sh` and `vbuild.sh`
run it. Each board lists the patches it needs under `[patches]`.

## Rules for a patch

1. One concern per patch file, named after what it does.
2. A header (text before the first `diff`) with: **Problem**, **Evidence**,
   **Fix**, **Upstream** (yes / maybe / no, and what is missing before sending it).
3. Say plainly when the evidence is indirect. A patch that "happened to help"
   while chasing something else is documented as such (see the two below).
4. Never mix a vaporOS-specific policy into a general fix.

## nuttx (apache/nuttx, releases/13.0)

| patch | what | upstream? |
|---|---|---|
| `cdcacm-tx-ring-race` | `cdcacm_sndpacket()` ran `uart_xmitchars_dma()` from both a writing thread and the bulk-IN completion interrupt; the TX ring was advanced twice and the console wedged under bursts of output. Critical section around it. | **Likely yes.** Generic CDC-ACM bug. Needs a vaporOS-free reproducer (a loop of small `write()`s to `/dev/ttyACM0`) and a check that master still has the window. The exact mechanism is from reading the code; the *effect* (vi paints, tab lists no longer wedge) is verified on hardware. |
| `vfs-stat-zero-mountpoint` | `stat()` zeroed its buffer for pseudo-fs nodes but not before a mountpoint's `stat()`; binfs fills only mode/size, so `ls -l /bin` showed 0xDEADBEEF owners and garbage dates. One-line `RESET_BUF`. | **Yes.** Trivial, generic. Check whether master already fixed binfs. |
| `sim-windows-host-layer` | **WIP.** Use `sim/win` for non-Cygwin Windows hosts; add the two files the Windows host layer is missing (`sim_testset.c`, `sim_hostsmp.c`). | **Not yet**: no Windows binary has run. See docs/windows-sim.md. |
| `rp2040-uf2-family` | pass `--family rp2040` to picotool; otherwise the bootrom silently ignores the UF2 | **Yes**, as is. Smallest and safest first contribution. |
| `rp2040-reset-bootsel-watchdog` | `board_reset(0)` = real full-chip watchdog reset (SYSRESETREQ alone falls into BOOTSEL); `board_reset(1)` = jump to the ROM USB bootloader | **Partly.** The watchdog reset is a bug fix. The "1 means BOOTSEL" convention should be discussed (a dedicated boardctl mode?). |
| `rp2040-usbdev-w1c-and-watchdog` | (1) clear the write-1-to-clear status registers by writing only the handled bit; (2) a 10 ms poll that completes/re-arms a bulk endpoint whose completion was lost | (1) **Yes** after a second review against the datasheet. (2) **No**: a workaround, found while chasing the CDC-ACM race above. Neither was shown on its own to fix anything. Drop (2) and re-test under load before upstreaming (1). |
| `rp2040-flash-littlefs` | LittleFS on a fixed flash window, mounted at a configurable path, surviving firmware updates | **Maybe.** Overlaps existing SmartFS/ROMFS options; upstream would want one flash-fs configuration, not a third. |
| `rp2040-crashdump-waveshare` | crash record (pc, lr, regs, stack bounds, task) in the top of SRAM, read back after the watchdog reset | **Maybe**, generalised into a reusable RAM crash-record helper. |
| `cdcacm-reset-on-1200bps` | Setting the CDC-ACM line rate to exactly 1200 bps calls `board_reset(1)` (the Arduino "1200 baud touch"), from the USB interrupt, so a board whose application is hung or owns the console can be reflashed without BOOT. | **Maybe.** De-facto convention (Arduino, Pico SDK, Adafruit); NuttX would want it generic (a callback or boardctl mode) rather than `board_reset(1)`. Verified on the RP2040-Zero. |

## nuttx-apps (apache/nuttx-apps, releases/13.0)

| patch | what | upstream? |
|---|---|---|
| `lua-32bit-typo` | `interpreters/lua` tested `CONFIG_INTERPRETERS_LUA_32BITS` but the option is `..._32BIT`, so the "32-bit integers and floats" setting never took effect; and Lua 5.4.3+ ignores `-DLUA_32BITS` (luaconf.h hard-codes 0), so the Makefile also flips that line once after unpacking. | Typo part **yes**. The sed on luaconf.h is a workaround; upstream would want a cleaner way to pick the number types. |
| `lua-maxccalls` | `INTERPRETERS_LUA_MAXCCALLS` passed as `-DLUAI_MAXCCALLS`. Lua's default of 200 nested C calls needs ~100 KB of stack; a small task stack (vlua: 24 KB, 464 B per nested pcall) overflows silently with no guard page and resets the board. | **Maybe.** Small and generic; needs the measurements (docs/lua-runtime.md) reproduced on a second port. Only honoured by Lua 5.4.3+. |
| `readline-eof-ctrl-d` | Ctrl-D on an empty line returns EOF from readline | **Likely yes**; make it configurable if asked. |
| `termcurses-read-retry` | sleep and retry instead of returning -1 on an empty key read | **No.** Written for a wrong theory of the vi hang; harmless but unproven. Remove unless a failure is shown. |

## Not patches, but worth knowing (found along the way)

- `olddefconfig` silently discards options whose dependencies are unmet. This
  hid several bugs (docs/compat-log.md, `kconfig-silent-drop`). vaporOS verifies
  its configuration afterwards (`tools/vconfig.py verify`); NuttX itself could
  offer a strict mode.
- NuttX's `_exit()` skips the task-local-storage destructors that `exit()` runs.
  That is defined behaviour, but a trap for code ported from Unix (it leaked ~13 KB
  per command in toybox). Worth a sentence in NuttX's porting documentation.
