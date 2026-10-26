include $(APPDIR)/Make.defs

# The benchmark sources live next to this repo (../langbench); $(realpath) resolves the
# apps/external symlink, plain $(abspath) would not.
LB := $(realpath $(APPDIR)/external/../langbench)

PROGNAME  = vbench
PRIORITY  = $(CONFIG_VAPOROS_VBENCH_PRIORITY)
STACKSIZE = $(CONFIG_VAPOROS_VBENCH_STACKSIZE)
MODULE    = $(CONFIG_VAPOROS_VBENCH)

MAINSRC = $(LB)/host/bench_main.c
CFLAGS += ${INCDIR_PREFIX}$(LB)/host ${INCDIR_PREFIX}$(LB)/build

# Per VM: its adapter, its generated script table, its sources and defines.
# These must stay equal to build_native.sh in ../langbench.
ifneq ($(CONFIG_VAPOROS_VBENCH_LUA),)
VM = lua
EXT = lua
LUADIR := $(realpath $(APPDIR)/interpreters/lua/lua)
CFLAGS += ${INCDIR_PREFIX}$(LUADIR) -DLUA_32BITS
CSRCS += $(filter-out %/lua.c %/luac.c %/onelua.c %/linit.c %/lbaselib.c %/lcorolib.c %/ldblib.c %/liolib.c %/lmathlib.c %/loslib.c %/lstrlib.c %/ltablib.c %/lutf8lib.c %/loadlib.c,$(wildcard $(LUADIR)/*.c))
CSRCS += $(addprefix $(LUADIR)/,lbaselib.c lcorolib.c lmathlib.c lstrlib.c ltablib.c)
endif

ifneq ($(CONFIG_VAPOROS_VBENCH_WREN),)
VM = wren
EXT = wren
CFLAGS += ${INCDIR_PREFIX}$(LB)/vendor/wren/src/include ${INCDIR_PREFIX}$(LB)/vendor/wren/src/vm
CFLAGS += -DWREN_OPT_META=0 -DWREN_OPT_RANDOM=0
CSRCS += $(wildcard $(LB)/vendor/wren/src/vm/*.c)
endif

ifneq ($(CONFIG_VAPOROS_VBENCH_BERRY),)
VM = berry
EXT = be
BERRYDIR := $(LB)/vendor/berry
CFLAGS += ${INCDIR_PREFIX}$(LB)/build/berry_conf ${INCDIR_PREFIX}$(BERRYDIR)/src
CSRCS += $(wildcard $(BERRYDIR)/src/*.c) $(BERRYDIR)/default/be_modtab.c

# berry_conf.h: stock minus the modules/file system a small runtime would not ship, allocator = bh_*
$(LB)/build/berry_conf/berry_conf.h:
	$(Q) $(LB)/tools/berry_conf.sh $(LB)/build/berry_conf
context:: $(LB)/build/berry_conf/berry_conf.h
endif

ifneq ($(CONFIG_VAPOROS_VBENCH_MQUICKJS),)
VM = mquickjs
EXT = js
MQ := $(LB)/vendor/mquickjs
MQGEN := $(LB)/build/mq32
# -Dstrstart: mquickjs's cutils.c exports `strstart`, and so does vaporOS-coreutils (one global namespace per image)
CFLAGS += ${INCDIR_PREFIX}$(MQGEN) ${INCDIR_PREFIX}$(MQ) -D_GNU_SOURCE -Dstrstart=bh_mq_strstart
CSRCS += $(addprefix $(MQ)/,mquickjs.c dtoa.c libm.c cutils.c)

# mquickjs generates its stdlib tables with a host tool; -m32 lays them out for a 32-bit target
$(MQGEN)/mqjs_stdlib:
	$(Q) mkdir -p $(MQGEN)
	$(Q) $(HOSTCC) -O2 -D_GNU_SOURCE -I$(MQ) $(MQ)/mqjs_stdlib.c $(MQ)/mquickjs_build.c -o $@
$(MQGEN)/mqjs_stdlib.h: $(MQGEN)/mqjs_stdlib
	$(Q) $< -m32 > $@
$(MQGEN)/mquickjs_atom.h: $(MQGEN)/mqjs_stdlib
	$(Q) $< -a -m32 > $@
context:: $(MQGEN)/mqjs_stdlib.h $(MQGEN)/mquickjs_atom.h
endif

ifneq ($(CONFIG_VAPOROS_VBENCH_JERRYSCRIPT),)
VM = jerryscript
EXT = js
JC := $(LB)/vendor/jerryscript/jerry-core
# the CMake defaults of ../langbench/build_native.sh (error messages off, 16-bit compressed pointers, mem stats on),
# with the heap sized for the board
CFLAGS += -DJERRY_CPOINTER_32_BIT=0 -DJERRY_DEBUGGER=0 -DJERRY_ERROR_MESSAGES=0 -DJERRY_EXTERNAL_CONTEXT=0
CFLAGS += -DJERRY_FUNCTION_TO_STRING=0 -DJERRY_GC_LIMIT=0 -DJERRY_GC_MARK_LIMIT=8 -DJERRY_LINE_INFO=0 -DJERRY_LOGGING=1
CFLAGS += -DJERRY_GLOBAL_HEAP_SIZE=$(CONFIG_VAPOROS_VBENCH_JERRY_HEAP_KB) -DJERRY_MEM_STATS=1 -DJERRY_NDEBUG
CFLAGS += -DJERRY_PARSER=1 -DJERRY_PROMISE_CALLBACK=0 -DJERRY_REGEXP_STRICT_MODE=0 -DJERRY_SNAPSHOT_EXEC=0
CFLAGS += -DJERRY_SNAPSHOT_SAVE=0 -DJERRY_STACK_LIMIT=0 -DJERRY_SYSTEM_ALLOCATOR=0 -DJERRY_VALGRIND=0 -DJERRY_VM_HALT=0
CFLAGS += -DJERRY_VM_THROW=0 -DJERRY_MEM_GC_BEFORE_EACH_ALLOC=0 -DJERRY_PARSER_DUMP_BYTE_CODE=0 -DJERRY_REGEXP_DUMP_BYTE_CODE=0
# -Dparser_free: collides with vaporshell's parser_free (one global namespace per image; scanned with nm, the only clash)
CFLAGS += -Dparser_free=jerry_parser_free
CFLAGS += $(foreach d,$(shell find $(JC) -type d),${INCDIR_PREFIX}$(d))
CSRCS += $(shell find $(JC) -name '*.c')
endif

ifneq ($(CONFIG_VAPOROS_VBENCH_MICROPYTHON),)
VM = micropython
EXT = py
MP := $(LB)/build/mp_src
# the embed sources are generated on the host at parse time (the file list below needs them)
$(shell $(LB)/tools/mp_embed_gen.sh)
CFLAGS += ${INCDIR_PREFIX}$(MP) ${INCDIR_PREFIX}$(MP)/micropython_embed ${INCDIR_PREFIX}$(MP)/micropython_embed/port -fno-common
CSRCS += $(filter-out %/mphalport.c,$(shell find $(MP)/micropython_embed -name '*.c'))
endif

CSRCS += $(LB)/host/vm_$(VM).c $(LB)/build/scripts_$(VM).c

# The script table (bench/<EXT>/, EXT = the language's file extension) is generated from bench/<ext>/ and the CPython reference.
$(LB)/build/scripts_$(VM).c: $(wildcard $(LB)/bench/*/*)
	$(Q) mkdir -p $(LB)/build
	$(Q) python3 -I $(LB)/tools/embed.py $(EXT) $@

context:: $(LB)/build/scripts_$(VM).c

# no vapor-nostdinc.mk: the VMs need the toolchain's math.h, like NuttX's own interpreters/lua does
include $(APPDIR)/Application.mk
