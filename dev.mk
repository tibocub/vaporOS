# vaporOS-nuttx/dev.mk -- build commands. Not "Makefile": that file is
# required as-is by NuttX's own build (apps/external symlinks here).

BOARD ?= nsh
NUTTX := $(abspath ../nuttx)

RUN := bash
EXT := .sh

.PHONY: build clean run help

build:
	@$(RUN) scripts/build$(EXT) $(BOARD)

clean:
	@$(RUN) scripts/clean$(EXT)

run:
	@"$(NUTTX)/nuttx"

help:
	@echo "make -f dev.mk build                    # the nsh board (NuttX's sim:nsh)"
	@echo "make -f dev.mk build BOARD=vterm_fb"
	@echo "make -f dev.mk clean"
	@echo "make -f dev.mk run"
	@echo
	@echo "The board is BOARD=..., not a goal: an extra goal such as sim:nsh makes"
	@echo "make exit with an error after the build has finished."
