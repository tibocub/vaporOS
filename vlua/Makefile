include $(APPDIR)/Make.defs

PROGNAME  = $(CONFIG_VAPOROS_VLUA_PROGNAME)
PRIORITY  = $(CONFIG_VAPOROS_VLUA_PRIORITY)
STACKSIZE = $(CONFIG_VAPOROS_VLUA_STACKSIZE)
MODULE    = $(CONFIG_VAPOROS_VLUA)

# Reuse NuttX's own Lua source/headers (see interpreters/lua) rather
# than bundling a second copy -- this only works once CONFIG_INTERPRETERS_LUA
# has downloaded it, hence the Kconfig dependency below.
CFLAGS += ${INCDIR_PREFIX}$(APPDIR)/interpreters/lua/lua

# vlua and the libraries below include Lua's headers and must see the same number types as the interpreter
# built by interpreters/lua (whose Makefile passes this itself, but only to its own objects).
ifeq ($(CONFIG_INTERPRETERS_LUA_32BIT),y)
CFLAGS += -DLUA_32BITS
endif

MAINSRC = vlua_main.c

# Optional second command "lua" running the same program (needs the stock interpreter renamed, see
# features/lua.conf and patches/nuttx-apps/lua-progname.patch).
ifeq ($(CONFIG_VAPOROS_VLUA_LUA_ALIAS),y)
PROGNAME += lua
MAINSRC += lua_alias.c
CFLAGS += -DVLUA_MAIN=$(patsubst "%",%,$(CONFIG_VAPOROS_VLUA_PROGNAME))_main
endif
CSRCS = vapor_core.c vlua_libs.c

# Third-party Lua C libraries: unmodified upstream sources in sibling
# directories (fetched by setup.sh, like vaporshell). Each is optional and is
# registered in package.preload by vlua_libs.c.
# $(realpath) resolves the apps/external symlink; $(abspath) would not.
LIBS := $(realpath $(APPDIR)/external/..)

ifneq ($(CONFIG_VAPOROS_VLUA_LFS),)
CFLAGS += -DVLUA_LFS
CSRCS += $(LIBS)/luafilesystem/src/lfs.c
endif

ifneq ($(CONFIG_VAPOROS_VLUA_LPEG),)
CFLAGS += -DVLUA_LPEG -DMAXRULES=$(CONFIG_VAPOROS_VLUA_LPEG_MAXRULES) -DMAXRECLEVEL=$(CONFIG_VAPOROS_VLUA_LPEG_MAXRECLEVEL)
CSRCS += $(addprefix $(LIBS)/lpeg-1.1.0/,lpcap.c lpcode.c lpcset.c lpprint.c lptree.c lpvm.c)
endif

ifneq ($(CONFIG_VAPOROS_VLUA_CJSON),)
CFLAGS += -DVLUA_CJSON
CSRCS += $(addprefix $(LIBS)/lua-cjson/,lua_cjson.c strbuf.c fpconv.c)
endif

ifneq ($(CONFIG_VAPOROS_VLUA_SOCKET),)
CFLAGS += -DVLUA_SOCKET
CSRCS += vsock.c
endif

ifneq ($(CONFIG_VAPOROS_VLUA_ED25519),)
CFLAGS += -DVLUA_ED25519 ${INCDIR_PREFIX}$(LIBS)/Monocypher/src/optional ${INCDIR_PREFIX}$(LIBS)/Monocypher/src
CSRCS += vsign.c $(addprefix $(LIBS)/Monocypher/src/,monocypher.c optional/monocypher-ed25519.c)
endif

ifneq ($(CONFIG_VAPOROS_VLUA_TLS),)
CFLAGS += -DVLUA_TLS
CSRCS += vtls.c
endif

# no vapor-nostdinc.mk: cjson needs the toolchain's math.h, like NuttX's own interpreters/lua does
include $(APPDIR)/Application.mk
