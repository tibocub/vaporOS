#!/usr/bin/env bash
# runner: NuttX rv-virt on QEMU.   qemu-riscv.sh flash|term|run
# The console is the emulated UART on stdio (Ctrl-A X quits QEMU), or a virtio-serial port when the image has one.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NUTTX="$(dirname "$DIR")/nuttx"
CON=(-serial mon:stdio)
grep -q '^CONFIG_DRIVERS_VIRTIO_SERIAL=y' "$NUTTX/.config" 2>/dev/null &&
  CON=(-serial null -monitor none -chardev stdio,id=con,signal=off -device virtio-serial-device -device virtconsole,chardev=con)
case "${1:-run}" in
  flash) echo "nothing to flash: QEMU boots the ELF directly" ;;
  term|run) exec qemu-system-riscv64 -M virt -cpu rv64 -smp 1 -bios none -nographic \
              "${CON[@]}" -kernel "$NUTTX/nuttx" ;;
  *) echo "usage: qemu-riscv.sh flash|term|run" >&2; exit 2 ;;
esac
