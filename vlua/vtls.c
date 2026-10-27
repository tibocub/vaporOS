/*
 * vtls.c -- require("vtls"): a TLS client connection (mbedTLS) over the same polled TCP socket as vsock.
 *
 *   local c, err = vtls.connect(host, port, cafile [, timeout])   -- certificate AND host name are verified
 *   c:send(data) / c:recv(max [, timeout]) / c:close()             -- same as vsock
 *
 * cafile is a PEM bundle of trusted roots; there is deliberately no "skip verification" switch. The bundle is
 * parsed once per process and kept (it is the largest allocation here; a small board needs a trimmed bundle).
 */

#include <nuttx/config.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>
#include <unistd.h>

#include "lua.h"
#include "lauxlib.h"

#include "mbedtls/ssl.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/error.h"

#define VTLS_MT "vtls"
#define POLL_US 5000

int vsock_dial(const char *host, int port, char *err, size_t errlen);
double vsock_now(void);

struct vtls_s
{
  int fd;
  int ready;                              /* ssl context set up (so it must be freed) */
  mbedtls_ssl_context ssl;
  mbedtls_ssl_config conf;
  mbedtls_ctr_drbg_context drbg;
  mbedtls_entropy_context entropy;
};

static mbedtls_x509_crt g_ca;
static char g_ca_path[128];

static int bio_send(void *ctx, const unsigned char *buf, size_t len)
{
  ssize_t n = send(*(int *)ctx, buf, len, 0);

  if (n < 0)
    {
      return errno == EAGAIN ? MBEDTLS_ERR_SSL_WANT_WRITE : MBEDTLS_ERR_SSL_INTERNAL_ERROR;
    }

  return (int)n;
}

static int bio_recv(void *ctx, unsigned char *buf, size_t len)
{
  ssize_t n = recv(*(int *)ctx, buf, len, 0);

  if (n < 0)
    {
      return errno == EAGAIN ? MBEDTLS_ERR_SSL_WANT_READ : MBEDTLS_ERR_SSL_CONN_EOF;
    }

  return (int)n;
}

static int tls_fail(lua_State *L, const char *what, int code)
{
  char msg[100], text[160];

  mbedtls_strerror(code, msg, sizeof(msg));
  snprintf(text, sizeof(text), "%s: %s (-0x%04x)", what, msg, (unsigned)-code);
  lua_pushnil(L);
  lua_pushstring(L, text);
  return 2;
}

static struct vtls_s *check(lua_State *L)
{
  return (struct vtls_s *)luaL_checkudata(L, 1, VTLS_MT);
}

static void release(struct vtls_s *t)
{
  if (t->ready)
    {
      mbedtls_ssl_free(&t->ssl);
      mbedtls_ssl_config_free(&t->conf);
      mbedtls_ctr_drbg_free(&t->drbg);
      mbedtls_entropy_free(&t->entropy);
      t->ready = 0;
    }

  if (t->fd >= 0)
    {
      close(t->fd);
      t->fd = -1;
    }
}

/* load the PEM bundle once; returns 0 or a message */

static const char *load_ca(const char *path)
{
  FILE *f;
  long size;
  unsigned char *buf;
  int ret;

  if (strcmp(path, g_ca_path) == 0)
    {
      return NULL;
    }

  f = fopen(path, "rb");
  if (f == NULL)
    {
      return "cannot open the CA file";
    }

  fseek(f, 0, SEEK_END);
  size = ftell(f);
  rewind(f);
  buf = malloc(size + 1);
  if (buf == NULL || fread(buf, 1, size, f) != (size_t)size)
    {
      free(buf);
      fclose(f);
      return "cannot read the CA file";
    }

  fclose(f);
  buf[size] = 0;
  mbedtls_x509_crt_free(&g_ca);
  mbedtls_x509_crt_init(&g_ca);
  ret = mbedtls_x509_crt_parse(&g_ca, buf, size + 1);   /* > 0: some certificates skipped, fine */
  free(buf);
  if (ret < 0 || g_ca.version == 0)
    {
      return "no usable certificate in the CA file";
    }

  strncpy(g_ca_path, path, sizeof(g_ca_path) - 1);
  return NULL;
}

static int vtls_connect(lua_State *L)
{
  const char *host = luaL_checkstring(L, 1);
  int port = (int)luaL_checkinteger(L, 2);
  const char *cafile = luaL_checkstring(L, 3);
  double end = vsock_now() + luaL_optnumber(L, 4, 30);
  char err[80];
  const char *msg;
  struct vtls_s *t;
  int ret;

  if ((msg = load_ca(cafile)) != NULL)
    {
      lua_pushnil(L);
      lua_pushstring(L, msg);
      return 2;
    }

  t = (struct vtls_s *)lua_newuserdatauv(L, sizeof(*t), 0);
  memset(t, 0, sizeof(*t));
  t->fd = -1;
  luaL_setmetatable(L, VTLS_MT);

  t->fd = vsock_dial(host, port, err, sizeof(err));
  if (t->fd < 0)
    {
      lua_pushnil(L);
      lua_pushstring(L, err);
      return 2;
    }

  mbedtls_ssl_init(&t->ssl);
  mbedtls_ssl_config_init(&t->conf);
  mbedtls_ctr_drbg_init(&t->drbg);
  mbedtls_entropy_init(&t->entropy);
  t->ready = 1;

  if ((ret = mbedtls_ctr_drbg_seed(&t->drbg, mbedtls_entropy_func, &t->entropy,
                                   (const unsigned char *)"vtls", 4)) != 0 ||
      (ret = mbedtls_ssl_config_defaults(&t->conf, MBEDTLS_SSL_IS_CLIENT,
                                         MBEDTLS_SSL_TRANSPORT_STREAM,
                                         MBEDTLS_SSL_PRESET_DEFAULT)) != 0)
    {
      return tls_fail(L, "setup", ret);
    }

  mbedtls_ssl_conf_max_tls_version(&t->conf, MBEDTLS_SSL_VERSION_TLS1_2);   /* 1.3 needs PSA crypto, not built */
  mbedtls_ssl_conf_authmode(&t->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
  mbedtls_ssl_conf_ca_chain(&t->conf, &g_ca, NULL);
  mbedtls_ssl_conf_rng(&t->conf, mbedtls_ctr_drbg_random, &t->drbg);
  if ((ret = mbedtls_ssl_setup(&t->ssl, &t->conf)) != 0 ||
      (ret = mbedtls_ssl_set_hostname(&t->ssl, host)) != 0)
    {
      return tls_fail(L, "setup", ret);
    }

  mbedtls_ssl_set_bio(&t->ssl, &t->fd, bio_send, bio_recv, NULL);

  while ((ret = mbedtls_ssl_handshake(&t->ssl)) != 0)
    {
      if ((ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) || vsock_now() > end)
        {
          if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE)
            {
              lua_pushnil(L);
              lua_pushliteral(L, "TLS handshake timed out");
              return 2;
            }

          if (ret == MBEDTLS_ERR_X509_CERT_VERIFY_FAILED)
            {
              char info[120];

              mbedtls_x509_crt_verify_info(info, sizeof(info), "", mbedtls_ssl_get_verify_result(&t->ssl));
              lua_pushnil(L);
              lua_pushfstring(L, "certificate of %s rejected: %s", host, info);
              return 2;
            }

          return tls_fail(L, "TLS handshake", ret);
        }

      usleep(POLL_US);
    }

  return 1;
}

static int vtls_send(lua_State *L)
{
  struct vtls_s *t = check(L);
  size_t len, off = 0;
  const char *s = luaL_checklstring(L, 2, &len);
  double end = vsock_now() + 30;

  while (t->ready && off < len)
    {
      int n = mbedtls_ssl_write(&t->ssl, (const unsigned char *)s + off, len - off);

      if (n == MBEDTLS_ERR_SSL_WANT_READ || n == MBEDTLS_ERR_SSL_WANT_WRITE)
        {
          if (vsock_now() > end)
            {
              lua_pushnil(L);
              lua_pushliteral(L, "send: timeout");
              return 2;
            }

          usleep(POLL_US);
          continue;
        }

      if (n < 0)
        {
          return tls_fail(L, "send", n);
        }

      off += n;
    }

  lua_pushboolean(L, t->ready);
  return 1;
}

static int vtls_recv(lua_State *L)
{
  struct vtls_s *t = check(L);
  lua_Integer max = luaL_checkinteger(L, 2);
  double end = vsock_now() + luaL_optnumber(L, 3, 15);
  luaL_Buffer b;
  char *p;
  int n;

  if (!t->ready || max < 1)
    {
      lua_pushnil(L);
      lua_pushliteral(L, "recv: closed");
      return 2;
    }

  p = luaL_buffinitsize(L, &b, (size_t)max);
  while ((n = mbedtls_ssl_read(&t->ssl, (unsigned char *)p, (size_t)max)) < 0)
    {
      if (n == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY || n == MBEDTLS_ERR_SSL_CONN_EOF)
        {
          n = 0;                          /* end of data; the HTTP layer checks that the body is complete */
          break;
        }

      if (n != MBEDTLS_ERR_SSL_WANT_READ && n != MBEDTLS_ERR_SSL_WANT_WRITE)
        {
          return tls_fail(L, "recv", n);
        }

      if (vsock_now() > end)
        {
          lua_pushnil(L);
          lua_pushliteral(L, "timeout");
          return 2;
        }

      usleep(POLL_US);
    }

  luaL_pushresultsize(&b, (size_t)n);
  return 1;
}

static int vtls_close(lua_State *L)
{
  struct vtls_s *t = check(L);

  if (t->ready)
    {
      mbedtls_ssl_close_notify(&t->ssl);      /* best effort */
    }

  release(t);
  return 0;
}

int luaopen_vtls(lua_State *L)
{
  static const luaL_Reg methods[] =
  {
    {"send", vtls_send}, {"recv", vtls_recv}, {"close", vtls_close},
    {"__gc", vtls_close}, {"__close", vtls_close}, {NULL, NULL}
  };

  luaL_newmetatable(L, VTLS_MT);
  luaL_setfuncs(L, methods, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
  lua_createtable(L, 0, 1);
  lua_pushcfunction(L, vtls_connect);
  lua_setfield(L, -2, "connect");
  return 1;
}
