include $(APPDIR)/Make.defs

# The vaporUI checkout next to vaporOS. apps/external is a symlink to this
# directory, so ".." from it is the workspace.
VUI := $(APPDIR)/external/../vaporUI

PROGNAME  = vui_windows vui_textarea vui_input vui_colors vui_buttons vui_layout
PRIORITY  = $(CONFIG_VAPOROS_VAPORUI_PRIORITY)
STACKSIZE = $(CONFIG_VAPOROS_VAPORUI_STACKSIZE)
MODULE    = $(CONFIG_VAPOROS_VAPORUI)

CFLAGS += ${INCDIR_PREFIX}$(VUI)/include

CSRCS = $(wildcard $(VUI)/src/*.c) $(wildcard $(VUI)/src/widgets/*.c) $(VUI)/src/platform/posix.c

# Terminal widget (needs a pty and RAM for libvterm's cell grid: ~40 B per cell, so not for the RP2040)
ifeq ($(CONFIG_VAPOROS_VAPORUI_TERMINAL),y)
# One libvterm in the image: vaporOS's own copy (vterm/), which the vtermtest app compiles when it is enabled.
VTERM := $(APPDIR)/external/vterm/libvterm
CFLAGS += -DVUI_TERMINAL ${INCDIR_PREFIX}$(VTERM)/include ${INCDIR_PREFIX}$(VTERM)/src
CSRCS += $(VUI)/src/ext/terminal.c
ifneq ($(CONFIG_VAPOROS_VTERMTEST),y)
CSRCS += $(wildcard $(VTERM)/src/*.c)
endif
endif

MAINSRC  = $(VUI)/examples/windows.c
MAINSRC += $(VUI)/examples/text-area.c
MAINSRC += $(VUI)/examples/input-handling.c
MAINSRC += $(VUI)/examples/colors.c
MAINSRC += $(VUI)/examples/buttons-and-lists.c
MAINSRC += $(VUI)/examples/layout-resize.c

include $(APPDIR)/external/vapor-nostdinc.mk
include $(APPDIR)/Application.mk
