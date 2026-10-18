# Sourced by the rp2040 tools: tty prints the board's console device, found by
# its USB name so another /dev/ttyACM* (an Arduino, a printer) is never used.
tty() { readlink -f /dev/serial/by-id/usb-NuttX_CDC_ACM* 2>/dev/null | head -1; }
