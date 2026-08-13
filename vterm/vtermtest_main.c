/*
 * Milestone 1 of docs/vaporterm.md: proves libvterm itself builds and
 * works correctly through the real NuttX app pipeline -- not just
 * plain host gcc -- before any NX rendering work is built on top of
 * it. Feeds it a string containing real ANSI escape sequences (bold
 * on, bold off) and prints back what it actually parsed. The bug
 * we're specifically checking isn't recurring here: NxTerm's own
 * minimal interpreter would have dumped those escape codes back out
 * as literal text (that's the exact garbled output that started this
 * whole investigation) -- this confirms libvterm consumes them
 * correctly and only the real characters end up in the parsed cells.
 */

#include <nuttx/config.h>
#include <stdio.h>
#include <string.h>

#include "vterm.h"

static int on_damage(VTermRect rect, void *user)
{
  return 1;
}

static VTermScreenCallbacks g_callbacks =
{
  .damage = on_damage
};

int main(int argc, FAR char *argv[])
{
  VTerm *vt = vterm_new(24, 80);

  if (vt == NULL)
    {
      printf("vtermtest: vterm_new failed\n");
      return 1;
    }

  vterm_set_utf8(vt, 1);

  VTermScreen *screen = vterm_obtain_screen(vt);
  vterm_screen_set_callbacks(screen, &g_callbacks, NULL);
  vterm_screen_reset(screen, 1);

  const char test[] = "Hello, \x1b[1mvaporOS\x1b[0m terminal!";
  vterm_input_write(vt, test, strlen(test));

  VTermPos pos;
  VTermScreenCell cell;
  char parsed[64];
  int i = 0;

  pos.row = 0;

  for (pos.col = 0; pos.col < 40 && i < (int)sizeof(parsed) - 1; pos.col++)
    {
      vterm_screen_get_cell(screen, pos, &cell);

      if (cell.chars[0] == 0)
        {
          break;
        }

      parsed[i++] = (char)cell.chars[0];
    }

  parsed[i] = '\0';

  printf("vtermtest: input  = \"Hello, <bold>vaporOS<reset> terminal!\"\n");
  printf("vtermtest: parsed = \"%s\"\n", parsed);

  if (strcmp(parsed, "Hello, vaporOS terminal!") == 0)
    {
      printf("vtermtest: PASS -- escape sequences consumed correctly, "
             "not leaked as literal text\n");
    }
  else
    {
      printf("vtermtest: FAIL -- output did not match expected text\n");
    }

  vterm_free(vt);
  return 0;
}
