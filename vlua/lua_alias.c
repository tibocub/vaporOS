/* lua -- the same program as vlua under the familiar name (VAPOROS_VLUA_LUA_ALIAS). */

#include <nuttx/config.h>

int VLUA_MAIN(int argc, char *argv[]);

int main(int argc, char *argv[])
{
  return VLUA_MAIN(argc, argv);
}
