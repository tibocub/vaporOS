# vaporOS-nuttx/dev.mk -- build and run commands. Not "Makefile": that file is
# required as-is by NuttX's own build (apps/external symlinks here).
#
# Every command takes BOARD=<name>; the default is the simulator. A board is
# a directory under boards/ (see boards/README.md), so adding a target never
# touches this file.

BOARD ?= sim-nsh
NUTTX := $(abspath ../nuttx)

.PHONY: build clean run flash term configure boards show check help \
        rp2040 rp2040-build rp2040-flash rp2040-term rp2040-run

build:
	@bash scripts/vbuild.sh $(BOARD)

# Produce nuttx/.config only (fast); useful to compare or inspect a board.
configure:
	@bash scripts/vbuild.sh $(BOARD) --configure-only

clean:
	@bash scripts/clean.sh

# flash/term/run are the board's own: the simulator just runs; an RP2040
# copies a UF2 and opens its serial console.
flash:
	@bash tools/vrun.sh $(BOARD) flash

term:
	@bash tools/vrun.sh $(BOARD) term

run:
	@bash tools/vrun.sh $(BOARD) run

boards:
	@python3 tools/vconfig.py list

show:
	@python3 tools/vconfig.py show $(BOARD)

check:
	@python3 tools/vconfig.py check

# Older RP2040 spellings, kept as aliases.
rp2040-build: BOARD := rp2040-zero
rp2040-build: build
rp2040-flash: BOARD := rp2040-zero
rp2040-flash: flash
rp2040-term: BOARD := rp2040-zero
rp2040-term: term
rp2040 rp2040-run: BOARD := rp2040-zero
rp2040 rp2040-run: build run

help:
	@echo "make -f dev.mk boards                     # list targets"
	@echo "make -f dev.mk build [BOARD=<name>]       # compile (default: sim-nsh)"
	@echo "make -f dev.mk run   [BOARD=<name>]       # sim: run it; hardware: flash + console"
	@echo "make -f dev.mk flash|term [BOARD=<name>]  # the parts of 'run'"
	@echo "make -f dev.mk show  [BOARD=<name>]       # the resolved configuration, with reasons"
	@echo "make -f dev.mk configure [BOARD=<name>]   # only produce nuttx/.config"
	@echo "make -f dev.mk check                      # validate boards/features/hardware"
	@echo "make -f dev.mk clean"
	@echo
	@echo "Boards: sim-nsh sim-nxterm sim-vterm_fb rp2040-zero (aliases: nsh nxterm vterm_fb rp2040)"
