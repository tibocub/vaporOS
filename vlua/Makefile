include $(APPDIR)/Make.defs

PROGNAME  = $(CONFIG_VAPOROS_VLUA_PROGNAME)
PRIORITY  = $(CONFIG_VAPOROS_VLUA_PRIORITY)
STACKSIZE = $(CONFIG_VAPOROS_VLUA_STACKSIZE)
MODULE    = $(CONFIG_VAPOROS_VLUA)

# Reuse NuttX's own Lua source/headers (see interpreters/lua) rather
# than bundling a second copy -- this only works once CONFIG_INTERPRETERS_LUA
# has downloaded it, hence the Kconfig dependency below.
CFLAGS += ${INCDIR_PREFIX}$(APPDIR)/interpreters/lua/lua

MAINSRC = vlua_main.c
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

# no vapor-nostdinc.mk: cjson needs the toolchain's math.h, like NuttX's own interpreters/lua does
include $(APPDIR)/Application.mk
