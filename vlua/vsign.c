/*
 * vsign.c -- require("vsign"): ed25519 signature verification (Monocypher), the check vpm makes on the package
 * index before it trusts a single hash in it.
 *
 *   vsign.verify(signature, message, public_key) -> true | false     (64-, any-, 32-byte strings)
 *
 * Only verification lives on the device; signing is done by the index publisher with openssl.
 */

#include <nuttx/config.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"

#include "monocypher-ed25519.h"

static int vsign_verify(lua_State *L)
{
  size_t siglen, msglen, keylen;
  const char *sig = luaL_checklstring(L, 1, &siglen);
  const char *msg = luaL_checklstring(L, 2, &msglen);
  const char *key = luaL_checklstring(L, 3, &keylen);

  luaL_argcheck(L, siglen == 64, 1, "signature must be 64 bytes");
  luaL_argcheck(L, keylen == 32, 3, "public key must be 32 bytes");
  lua_pushboolean(L, crypto_ed25519_check((const uint8_t *)sig, (const uint8_t *)key,
                                          (const uint8_t *)msg, msglen) == 0);
  return 1;
}

int luaopen_vsign(lua_State *L)
{
  lua_createtable(L, 0, 1);
  lua_pushcfunction(L, vsign_verify);
  lua_setfield(L, -2, "verify");
  return 1;
}
