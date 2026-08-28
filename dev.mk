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
	@echo "make -f dev.mk build sim:nsh"
	@echo "make -f dev.mk build BOARD=vterm_fb"
	@echo "make -f dev.mk clean"
	@echo "make -f dev.mk run"
