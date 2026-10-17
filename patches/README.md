# patches/

Small, targeted patches to upstream, pinned repos (currently just
`nuttx-apps`) that `setup.sh` applies automatically, once, right after
cloning fresh -- not a fork of the upstream repo, since the changes
here are narrow and specific enough that a full fork's own ongoing
maintenance (rebasing onto newer upstream commits, etc.) isn't worth
it yet. Revisit this convention if the number or size of patches here
grows much further; a real fork might become the better tradeoff at
that point.

Each patch's own top-of-file comment (in whichever `vaporOS-nuttx`
source called `git apply` on it -- currently `setup.sh`) explains what
it does and why it isn't upstream instead.

## nuttx-rp2040.patch (against the `nuttx` repo)

RP2040 / Waveshare RP2040-Zero support for vaporOS; apply with
`git -C ../nuttx apply ../vaporOS/patches/nuttx-rp2040.patch`:

- `tools/rp2040/Config.mk`: pass `--family rp2040` to `picotool uf2 convert`
  (picotool 2.x otherwise writes the "absolute" family and the bootrom
  silently ignores the file).
- `rp2040_reset.c`: `board_reset(1)` enters the ROM USB bootloader (BOOTSEL);
  any other value does a full-chip watchdog reset (SYSRESETREQ alone leaves
  flash in XIP mode and the board falls into BOOTSEL).
- `rp2040_crashdump.c`: records PC/LR/regs of a crash in SRAM at 0x2003ff00;
  read back with `xd 0x2003ff00 128`.

- `rp2040_flash_mtd.c` + Kconfig + bring-up: `CONFIG_RP2040_FLASH_LITTLEFS`,
  a LittleFS (autoformat) on a *fixed* flash region at
  `RP2040_FLASH_FS_OFFSET` (default 1 MiB, mounted at /flash). Unlike the
  upstream SmartFS option it is not part of the firmware image, so files
  survive reflashing.

Build with `scripts/build-rp2040.sh`; flash with `tools/rp2040-flash.sh`.
