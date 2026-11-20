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
# os.execute: NuttX has no system() in this configuration (link error NXsystem); Lua's own hook reports "no shell".
CFLAGS += -D'l_system(cmd)=((cmd)==NULL?0:-1)'

# Native modules chosen in Kconfig; their sources and -D flags come from vlr's modules.conf.
VLR_MODS :=
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
# own Makefile (host tools), into a directory of its own so host builds are not disturbed.
VLR_GEN := build/nuttx
$(shell $(MAKE) -s -C $(VLR) gen GEN=$(VLR_GEN) MODULES="$(VLR_MODS)" >&2)
CSRCS  += $(addprefix $(VLR)/$(VLR_GEN)/,$(addsuffix .c,$(VLR_LUA_EMBED)) vlr_modules.c)

include $(APPDIR)/Application.mk
