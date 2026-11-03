#!/usr/bin/env bash
# runner: NuttX rv-virt on QEMU.   qemu-riscv.sh flash|term|run
# The console is the emulated UART on stdio; Ctrl-A X quits QEMU.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
case "${1:-run}" in
  flash) echo "nothing to flash: QEMU boots the ELF directly" ;;
  term|run) exec qemu-system-riscv64 -M virt -cpu rv64 -smp 1 -bios none -nographic \
              -serial mon:stdio -kernel "$(dirname "$DIR")/nuttx/nuttx" ;;
  *) echo "usage: qemu-riscv.sh flash|term|run" >&2; exit 2 ;;
esac
