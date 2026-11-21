include $(APPDIR)/Make.defs

PROGNAME  = $(patsubst "%",%,$(CONFIG_VAPOROS_VLR_PROGNAME))
PRIORITY  = $(CONFIG_VAPOROS_VLR_PRIORITY)
STACKSIZE = $(CONFIG_VAPOROS_VLR_STACKSIZE)
MODULE    = $(CONFIG_VAPOROS_VLR)

# The runtime is the sibling checkout ../vlr (a path with no symlink: $(realpath) resolves apps/external).
LIBS := $(realpath $(APPDIR)/external/..)
VLR  := $(LIBS)/vlr
VLR_ROOT := $(VLR)
include $(VLR)/sources.mk

# Backend: NuttX is POSIX, so the posix backend is the NuttX one.
MAINSRC = $(VLR)/$(VLR_MAIN_SRC)
CSRCS   = $(addprefix $(VLR)/,$(VLR_CORE_SRC) src/platform_posix.c) $(addprefix $(VLR)/third_party/lua/,$(VLR_LUA_SRC))
CFLAGS += ${INCDIR_PREFIX}$(VLR)/include ${INCDIR_PREFIX}$(VLR)/third_party/lua
CFLAGS += -DLUAI_MAXCCALLS=$(CONFIG_VAPOROS_VLR_MAXCCALLS)
ifneq ($(CONFIG_VAPOROS_VLR_STRIP_INTERNAL),)
CFLAGS += -DVLR_STRIP_INTERNAL=1
endif
CFLAGS += -DVLR_GC_PAUSE=$(CONFIG_VAPOROS_VLR_GC_PAUSE) -DVLR_GC_STEPMUL=$(CONFIG_VAPOROS_VLR_GC_STEPMUL)
# os.execute goes through vlr_exec (platform_posix.c: vaporshell -c on NuttX, which has no system()); vlr_lua.h wires
# Lua's l_system hook to it.
CFLAGS += -include vlr_lua.h

# Native modules chosen in Kconfig; their sources and -D flags come from vlr's modules.conf.
VLR_MODS :=
ifneq ($(CONFIG_VAPOROS_VLR_FS),)
VLR_MODS += vapor.fs
endif
ifneq ($(CONFIG_VAPOROS_VLR_INPUT),)
VLR_MODS += vapor.term vapor.input
endif
ifneq ($(CONFIG_VAPOROS_VLR_LFS),)
VLR_MODS += lfs
endif
ifneq ($(CONFIG_VAPOROS_VLR_LPEG),)
VLR_MODS += lpeg
CFLAGS += -DMAXRULES=$(CONFIG_VAPOROS_VLR_LPEG_MAXRULES) -DMAXRECLEVEL=$(CONFIG_VAPOROS_VLR_LPEG_MAXRECLEVEL)
endif
ifneq ($(CONFIG_VAPOROS_VLR_CJSON),)
VLR_MODS += cjson
endif
VLR_MODTOK := $(shell sh $(VLR)/tools/modsrc.sh $(VLR)/modules.conf $(LIBS) $(VLR_MODS))
CSRCS  += $(filter-out -%,$(VLR_MODTOK))
CFLAGS += $(filter -%,$(VLR_MODTOK))

# Generated C: the embedded Lua (scheduler, compat) and the module registry for the modules above. Made by vlr's
# own Makefile with the HOST compiler (CC/CFLAGS forced: the NuttX environment holds the target cross flags), into a directory of its own so host builds are not disturbed.
VLR_GEN := build/nuttx
$(shell $(MAKE) -s -C $(VLR) gen CC=cc CFLAGS=-O2 LDFLAGS= GEN=$(VLR_GEN) MODULES="$(VLR_MODS)" >&2)
CSRCS  += $(addprefix $(VLR)/$(VLR_GEN)/,$(addsuffix .c,$(VLR_LUA_EMBED)) vlr_modules.c)

include $(APPDIR)/Application.mk
