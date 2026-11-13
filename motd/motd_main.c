/* motd -- print the vaporOS logo. vinit runs it before the shell (CONFIG_VAPOROS_VINIT_MOTD). */

#include <nuttx/config.h>
#include <stdio.h>

static const char logo[] =
  "                                  ____  _____\n"
  " _   ______ _____  ____  _____   / __ \\/ ___/\n"
  "| | / / __ `/ __ \\/ __ \\/ ___/  / / / /\\__ \\\n"
  "| |/ / /_/ / /_/ / /_/ / /     / /_/ /___/ /\n"
  "|___/\\__,_/ .___/\\____/_/      \\____//____/\n"
  "         /_/\n"
  "\n";

int main(int argc, FAR char *argv[])
{
  fputs(logo, stdout);
  return 0;
}
