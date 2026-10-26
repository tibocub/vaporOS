/*
 * vlua -- vaporOS's Lua host. Creates its own Lua state (doesn't touch
 * NuttX's own `lua` command) and always registers the "vapor" table
 * before running anything, so every script run through vlua has it
 * available -- this program IS the vapor-enabled runtime, not a
 * separate thing that later gets pointed at one.
 */

#include <nuttx/config.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "system/readline.h"

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "vapor_core.h"

void vlua_libs_register(lua_State *L);

/*
 * Sets the global `arg` table the same way the real `lua` CLI does:
 * arg[1], arg[2], ... are the script's own arguments (argv[2] onward
 * here, since argv[1] is the script path itself). Without this, a
 * vapor script has no way to receive command-line arguments at all --
 * fine for a demo, not fine for "build any kind of program".
 */
/*
 * os.exit() that closes the state. Lua's own os.exit skips lua_close unless
 * asked to, and a NuttX task's heap is not reclaimed when it exits (one
 * shared heap), so every script ending in os.exit() leaked its whole Lua
 * state -- a failed test run lost 35-40 KB of a 242 KB heap until reboot.
 */

static int vlua_os_exit(lua_State *L)
{
  int status;

  if (lua_isboolean(L, 1))
    {
      status = lua_toboolean(L, 1) ? EXIT_SUCCESS : EXIT_FAILURE;
    }
  else
    {
      status = (int)luaL_optinteger(L, 1, EXIT_SUCCESS);
    }

  lua_close(L);
  exit(status);
}

static void vlua_setup_args(lua_State *L, int argc, FAR char *argv[])
{
  int i;

  lua_newtable(L);

  for (i = 2; i < argc; i++)
    {
      lua_pushstring(L, argv[i]);
      lua_rawseti(L, -2, i - 1);
    }

  lua_setglobal(L, "arg");
}


/* The interactive prompt, like the stock `lua` one: a line is tried as an
 * expression first ("return <line>"), then as a statement; when the parser
 * says it ended early ("<eof>") more lines are read until it is complete.
 * Ctrl-D (EOF) or `exit`/`quit` leaves.
 */

#define VLUA_LINE 256

static bool vlua_read(const char *prompt, char *buf, int len)
{
  ssize_t n = write(STDOUT_FILENO, prompt, strlen(prompt));

  (void)n;
  readline_prompt(prompt);
  return readline_fd(buf, len, STDIN_FILENO, STDOUT_FILENO) > 0;
}

static bool vlua_incomplete(lua_State *L, int status)
{
  size_t len;
  const char *msg;

  if (status != LUA_ERRSYNTAX)
    {
      return false;
    }

  msg = lua_tolstring(L, -1, &len);
  return msg != NULL && len >= 5 && strcmp(msg + len - 5, "<eof>") == 0;
}

static void vlua_report(lua_State *L, int status)
{
  if (status != LUA_OK)
    {
      const char *msg = lua_tostring(L, -1);

      fprintf(stderr, "%s\n", msg != NULL ? msg : "(error object)");
      lua_pop(L, 1);
    }
}

static void vlua_repl(lua_State *L)
{
  static char line[VLUA_LINE];
  static char chunk[VLUA_LINE * 8];
  bool more = false;

  printf("%s  (Ctrl-D or exit to quit)\n", LUA_VERSION);
  chunk[0] = '\0';

  for (; ; )
    {
      int status;

      if (!vlua_read(more ? ">> " : "> ", line, sizeof(line)))
        {
          break;
        }

      if (line[0] == '\004')     /* NuttX readline passes Ctrl-D through */
        {
          break;
        }

      line[strcspn(line, "\r\n")] = '\0';
      if (!more && (strcmp(line, "exit") == 0 || strcmp(line, "quit") == 0))
        {
          break;
        }

      if (strlen(chunk) + strlen(line) + 2 >= sizeof(chunk))
        {
          fprintf(stderr, "chunk too long\n");
          chunk[0] = '\0';
          more = false;
          continue;
        }

      if (!more)
        {
          /* Expression first, so `1+2` prints 3 */

          char expr[VLUA_LINE + 8];

          snprintf(expr, sizeof(expr), "return %s", line);
          status = luaL_loadstring(L, expr);
          if (status == LUA_OK)
            {
              status = lua_pcall(L, 0, LUA_MULTRET, 0);
              if (status == LUA_OK)
                {
                  int n = lua_gettop(L);

                  if (n > 0)
                    {
                      luaL_checkstack(L, LUA_MINSTACK, "too many results");
                      lua_getglobal(L, "print");
                      lua_insert(L, 1);
                      lua_pcall(L, n, 0, 0);
                    }
                }
              else
                {
                  vlua_report(L, status);
                }

              lua_settop(L, 0);
              continue;
            }

          lua_pop(L, 1);
        }

      strcat(chunk, line);
      strcat(chunk, "\n");
      status = luaL_loadstring(L, chunk);
      if (vlua_incomplete(L, status))
        {
          lua_pop(L, 1);
          more = true;
          continue;
        }

      more = false;
      chunk[0] = '\0';
      if (status == LUA_OK)
        {
          status = lua_pcall(L, 0, 0, 0);
        }

      vlua_report(L, status);
      lua_settop(L, 0);
    }

  putchar('\n');
}

int main(int argc, FAR char *argv[])
{
  lua_State *L = luaL_newstate();

  if (L == NULL)
    {
      fprintf(stderr, "vlua: could not create Lua state\n");
      return 1;
    }

  luaL_openlibs(L);

  /* RAM is the scarce resource, not CPU: collect as soon as garbage equals live data (default waits
   * for 2x) and take bigger steps. Needed for lfs's own test suite to fit on the RP2040. */
  lua_gc(L, LUA_GCINC, 100, 400, 0);

  lua_getglobal(L, "os");
  lua_pushcfunction(L, vlua_os_exit);
  lua_setfield(L, -2, "exit");
  lua_pop(L, 1);

  lua_newtable(L);
  lua_setglobal(L, "vapor");

  vapor_core_register(L);
  vlua_libs_register(L);

  /* No "./" prefix: on the sim's filesystem fopen("./x") fails while fopen("x") works.
   * Project libraries first so a project can pin its own versions, then the system-wide directory. */
  if (getenv("LUA_PATH_5_4") == NULL && getenv("LUA_PATH") == NULL)
    {
      lua_getglobal(L, "package");
      lua_pushliteral(L,
        "lua_modules/?.lua;lua_modules/?/init.lua;"
        CONFIG_VAPOROS_VLUA_LIBDIR "/?.lua;"
        CONFIG_VAPOROS_VLUA_LIBDIR "/?/init.lua;"
        "?.lua;?/init.lua");
      lua_setfield(L, -2, "path");
      lua_pop(L, 1);
    }

  int status;

  if (argc > 2 && strcmp(argv[1], "-e") == 0)
    {
      status = luaL_dostring(L, argv[2]);
    }
  else if (argc == 1 || strcmp(argv[1], "-i") == 0)
    {
      vlua_repl(L);
      status = LUA_OK;
    }
  else if (argc > 1)
    {
      vlua_setup_args(L, argc, argv);
      status = luaL_dofile(L, argv[1]);
    }
  else
    {
      status = LUA_OK;
    }

  if (status != LUA_OK)
    {
      fprintf(stderr, "vlua: %s\n", lua_tostring(L, -1));
      lua_close(L);
      return 1;
    }

  lua_close(L);
  return 0;
}
