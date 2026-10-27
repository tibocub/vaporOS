/*
 * vsock.c -- require("vsock"): the TCP primitives vpm's HTTP client is built on. Polled non-blocking sockets (see POLL_US), with a timeout in
 * seconds on recv; everything above this (HTTP, redirects, TLS later) is Lua.
 *
 *   local c, err = vsock.connect(host, port)  -- a connection, or nil, err
 *   c:send(data)             -> true | nil, err            -- sends all of it
 *   c:recv(max [, timeout])  -> string | "" at EOF | nil, "timeout" | nil, err
 *   c:close()                -- also done by the garbage collector and by <close>
 */

#include <nuttx/config.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <time.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "lua.h"
#include "lauxlib.h"

#define VSOCK_MT "vsock"

static int fail(lua_State *L, const char *what)
{
  lua_pushnil(L);
  lua_pushfstring(L, "%s: %s", what, strerror(errno));
  return 2;
}

static int *check(lua_State *L)
{
  return (int *)luaL_checkudata(L, 1, VSOCK_MT);
}

/* Sockets are non-blocking and polled every few ms: in the simulator a blocking recv() on a usrsock socket waits
 * for an event the host bridge does not always deliver (measured: the reply never arrives), whereas a
 * non-blocking recv() asks the host socket directly. Costs a little latency, needs no event support. */

#define POLL_US 5000

int vsock_dial(const char *host, int port, char *err, size_t errlen);
double vsock_now(void);

double vsock_now(void)
{
  struct timespec t;

  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec / 1e9;
}

/* TCP connection to host:port as a non-blocking fd; -1 and a message in err on failure (shared with vtls.c) */

int vsock_dial(const char *host, int port, char *err, size_t errlen)
{
  struct addrinfo hints = { .ai_socktype = SOCK_STREAM }, *res, *ai;
  char service[8];
  int fd = -1;

  snprintf(service, sizeof(service), "%d", port);
  if (getaddrinfo(host, service, &hints, &res) != 0)
    {
      snprintf(err, errlen, "cannot resolve %s", host);
      return -1;
    }

  for (ai = res; ai != NULL && fd < 0; ai = ai->ai_next)
    {
      fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
      if (fd >= 0 && connect(fd, ai->ai_addr, ai->ai_addrlen) < 0)
        {
          close(fd);
          fd = -1;
        }
    }

  freeaddrinfo(res);
  if (fd < 0)
    {
      snprintf(err, errlen, "connect: %s", strerror(errno));
      return -1;
    }

  fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
  return fd;
}

static int vsock_connect(lua_State *L)
{
  char err[80];
  int *c, fd = vsock_dial(luaL_checkstring(L, 1), (int)luaL_checkinteger(L, 2), err, sizeof(err));

  if (fd < 0)
    {
      lua_pushnil(L);
      lua_pushstring(L, err);
      return 2;
    }

  c = (int *)lua_newuserdatauv(L, sizeof(int), 0);
  *c = fd;
  luaL_setmetatable(L, VSOCK_MT);
  return 1;
}

static int vsock_send(lua_State *L)
{
  int *c = check(L);
  size_t len, off = 0;
  const char *s = luaL_checklstring(L, 2, &len);

  while (*c >= 0 && off < len)
    {
      ssize_t n = send(*c, s + off, len - off, 0);

      if (n < 0 && errno == EAGAIN)
        {
          usleep(POLL_US);
          continue;
        }

      if (n < 0)
        {
          return fail(L, "send");
        }

      off += n;
    }

  lua_pushboolean(L, *c >= 0);
  return 1;
}

static int vsock_recv(lua_State *L)
{
  int *c = check(L);
  lua_Integer max = luaL_checkinteger(L, 2);
  double timeout = luaL_optnumber(L, 3, 15);
  luaL_Buffer b;
  char *p;
  ssize_t n;
  double end;

  if (*c < 0 || max < 1)
    {
      return fail(L, "recv");
    }

  p = luaL_buffinitsize(L, &b, (size_t)max);
  for (end = vsock_now() + timeout; ; usleep(POLL_US))
    {
      n = recv(*c, p, (size_t)max, 0);
      if (n >= 0 || errno != EAGAIN)
        {
          break;
        }

      if (vsock_now() > end)
        {
          lua_pushnil(L);
          lua_pushliteral(L, "timeout");
          return 2;
        }
    }

  if (n < 0)
    {
      return fail(L, "recv");
    }

  luaL_pushresultsize(&b, (size_t)n);
  return 1;
}

static int vsock_close(lua_State *L)
{
  int *c = check(L);

  if (*c >= 0)
    {
      close(*c);
      *c = -1;
    }

  return 0;
}

int luaopen_vsock(lua_State *L)
{
  static const luaL_Reg methods[] =
  {
    {"send", vsock_send}, {"recv", vsock_recv}, {"close", vsock_close},
    {"__gc", vsock_close}, {"__close", vsock_close}, {NULL, NULL}
  };

  luaL_newmetatable(L, VSOCK_MT);
  luaL_setfuncs(L, methods, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
  lua_createtable(L, 0, 1);
  lua_pushcfunction(L, vsock_connect);
  lua_setfield(L, -2, "connect");
  return 1;
}
