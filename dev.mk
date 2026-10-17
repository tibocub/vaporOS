# vaporOS-nuttx/dev.mk -- build commands. Not "Makefile": that file is
# required as-is by NuttX's own build (apps/external symlinks here).

BOARD ?= nsh
NUTTX := $(abspath ../nuttx)

RUN := bash
EXT := .sh

.PHONY: build clean run help rp2040 rp2040-build rp2040-flash rp2040-term rp2040-run

build:
	@$(RUN) scripts/build$(EXT) $(BOARD)

clean:
	@$(RUN) scripts/clean$(EXT)

run:
	@"$(NUTTX)/nuttx"

# --- Waveshare RP2040-Zero (USB console), see docs/rp2040.md ---
rp2040-build:
	@bash scripts/build-rp2040.sh

rp2040-flash:
	@bash tools/rp2040-flash.sh

rp2040-term:
	@bash tools/rp2040-console.sh

# build + flash + open the terminal, the rp2040 equivalent of `build` then `run`
rp2040 rp2040-run: rp2040-build rp2040-flash rp2040-term

help:
	@echo "make -f dev.mk build                    # the nsh board (NuttX's sim:nsh)"
	@echo "make -f dev.mk build BOARD=vterm_fb"
	@echo "make -f dev.mk clean"
	@echo "make -f dev.mk run"
	@echo
	@echo "RP2040-Zero:"
	@echo "make -f dev.mk rp2040-build   # compile"
	@echo "make -f dev.mk rp2040-flash   # reboot to BOOTSEL + copy the UF2"
	@echo "make -f dev.mk rp2040-term    # open the vaporshell console"
	@echo "make -f dev.mk rp2040         # all three"
	@echo
	@echo "The board is BOARD=..., not a goal: an extra goal such as sim:nsh makes"
	@echo "make exit with an error after the build has finished."
