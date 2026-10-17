/* reboot [mode] -- reset the board via boardctl(BOARDIOC_RESET).
 * On the RP2040 board, mode 1 drops into the ROM USB bootloader (BOOTSEL).
 */

#include <nuttx/config.h>

#include <sys/boardctl.h>

#include <stdio.h>
#include <stdlib.h>

int main(int argc, FAR char *argv[])
{
  int mode = argc > 1 ? atoi(argv[1]) : 0;

  boardctl(BOARDIOC_RESET, mode);
  fprintf(stderr, "reboot: not supported on this board\n");
  return 1;
}
