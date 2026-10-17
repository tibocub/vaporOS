#!/usr/bin/env bash
# scripts/build-rp2040.sh -- build vaporOS (vaporshell + vaporOS-coreutils)
# for the Waveshare RP2040-Zero, console over USB CDC/ACM.
#
# Needs: arm-none-eabi-gcc, picotool, and a pico-sdk checkout (NuttX builds
# the RP2040 second-stage bootloader from it; without boot2 the bootrom
# rejects the image and the board just stays in BOOTSEL). The defaults below
# point at ~/toolchains; override with ARM_TOOLCHAIN_BIN / PICOTOOL_DIR /
# PICO_SDK_PATH.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$(dirname "$DIR")/nuttx"

TC="${HOME}/toolchains"
export PICO_SDK_PATH="${PICO_SDK_PATH:-$TC/pico-sdk}"
export PATH="${PICOTOOL_DIR:-$TC/picotool/picotool}:${ARM_TOOLCHAIN_BIN:-$(echo $TC/arm-gnu/*/bin)}:$PATH"

[ -f .config ] && make distclean
./tools/configure.sh waveshare-rp2040-zero:usbnsh

en() { for o in "$@"; do kconfig-tweak --enable "CONFIG_$o"; done; }
en VAPOROS_VAPORSHELL VAPOROS_TOYBOX VAPOROS_VINIT
# Lua (vlua): NuttX's interpreter sources + libm; vlua needs a roomy stack.
en INTERPRETERS_LUA LIBM LIBC_FLOATINGPOINT VAPOROS_VLUA
kconfig-tweak --set-val CONFIG_VAPOROS_VLUA_STACKSIZE 24576
# vi (NuttX apps system/vi): 80x24 VT100 editor
en SYSTEM_VI
# dmesg: the syslog goes to a RAM log (the USB console isn't a syslog channel)
en RAMLOG RAMLOG_SYSLOG
kconfig-tweak --set-val CONFIG_RAMLOG_BUFSIZE 2048
kconfig-tweak --set-val CONFIG_SYSLOG_MAX_CHANNELS 2
kconfig-tweak --set-str CONFIG_SYSLOG_DEVPATH /dev/kmsg
# ps: stack usage
en STACK_COLORATION
kconfig-tweak --set-str CONFIG_INIT_ENTRYNAME vinit
kconfig-tweak --set-val CONFIG_SYSTEM_VI_COLS 80
kconfig-tweak --set-val CONFIG_SYSTEM_VI_ROWS 24
kconfig-tweak --set-val CONFIG_SYSTEM_VI_STACKSIZE 8192
# Boot straight into vaporshell on the USB console; NSH's session isn't used.
kconfig-tweak --set-str CONFIG_INIT_ENTRYPOINT vinit_main
# vaporshell/toybox runtime needs (pipelines, spawn, symlinks, regex, locale)
en SCHED_CHILD_STATUS PIPES LIBC_EXECFUNCS PSEUDOFS_SOFTLINKS LIBC_LOCALE
en ALLOW_MIT_COMPONENTS LIBC_REGEX NSH_LIBRARY SYSTEM_READLINE
en LIBC_STRERROR LIBC_LOCALTIME ARCH_SETJMP_H
kconfig-tweak --set-val CONFIG_TLS_TASK_NELEM 4
kconfig-tweak --set-val CONFIG_LINE_MAX 256
# vaporshell recurses for subshells/$(...)/functions; the 2KB default overflows.
kconfig-tweak --set-val CONFIG_VAPOROS_VAPORSHELL_STACKSIZE 16384
# Same for toybox applets (each is its own task). NuttX keeps the task-local
# storage block at the bottom of the stack, so an overflow shows up as a
# garbage vapor_ctx() pointer.
kconfig-tweak --set-val CONFIG_VAPOROS_TOYBOX_STACKSIZE 8192
kconfig-tweak --set-val CONFIG_DEFAULT_TASK_STACKSIZE 4096

# Crash visibility without a UART: reset on crash and keep a crash record in
# the top 256 bytes of SRAM (see rp2040_crashdump.c); read it with
# `xd 0x2003ff00 256` after the board comes back up.
en BOARDCTL_RESET
kconfig-tweak --disable CONFIG_BOARD_CRASHDUMP_NONE
kconfig-tweak --enable CONFIG_BOARD_CRASHDUMP_CUSTOM
kconfig-tweak --set-val CONFIG_BOARD_RESET_ON_ASSERT 2
kconfig-tweak --set-val CONFIG_BOARD_ASSERT_RESET_VALUE 0  # 1 means "enter BOOTSEL" in rp2040_reset.c
kconfig-tweak --set-val CONFIG_RAM_SIZE 261888

# Hardware watchdog (fed by a worker): if the system locks up hard (e.g. a
# fault inside a fault handler) the board resets itself instead of needing a
# physical replug. Ctrl-C on the USB console kills the foreground task.
en WATCHDOG WATCHDOG_AUTOMONITOR WATCHDOG_AUTOMONITOR_BY_WORKER SCHED_WORKQUEUE
en TTY_SIGINT TTY_SIGSTP FS_BINFS
kconfig-tweak --set-val CONFIG_TTY_SIGINT_CHAR 0x03  # Ctrl-C; Ctrl-D stays EOF
kconfig-tweak --set-val CONFIG_WATCHDOG_AUTOMONITOR_TIMEOUT 4000

# Persistent storage: LittleFS on the upper half of the 2MB flash (fixed
# offset, so reflashing the firmware leaves the files alone), mounted at
# /flash. The firmware has to stay below CONFIG_RP2040_FLASH_FS_OFFSET.
en MTD RP2040_FLASH_LITTLEFS FS_LITTLEFS
kconfig-tweak --set-val CONFIG_RP2040_FLASH_FS_OFFSET 0x100000
en FS_PROCFS FS_PROCFS_REGISTER

# Tab completion (commands + paths) through the vaporOS readline hook, and
# command history on the up/down arrows.
en READLINE_ECHO READLINE_TABCOMPLETION READLINE_CMD_HISTORY

# readline echoes one byte per write(); give the CDC/ACM driver more headroom
# for bursts of tiny writes.
kconfig-tweak --set-val CONFIG_CDCACM_NRDREQS 8
kconfig-tweak --set-val CONFIG_CDCACM_NWRREQS 8
kconfig-tweak --set-val CONFIG_CDCACM_RXBUFSIZE 513
kconfig-tweak --set-val CONFIG_CDCACM_TXBUFSIZE 513

make olddefconfig
make -j"$(nproc)"
arm-none-eabi-size nuttx
echo "Done: nuttx/nuttx.uf2"
