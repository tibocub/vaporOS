# vaporOS-nuttx/dev.mk -- build commands. Not "Makefile": that file is
# required as-is by NuttX's own build (apps/external symlinks here).
#
#   make -f dev.mk build               sim:nsh
#   make -f dev.mk build BOARD=vterm_fb
#   make -f dev.mk clean
#   make -f dev.mk help
#
# Picks bash+.sh or PowerShell+.ps1 based on OS automatically -- $(OS)
# is set to "Windows_NT" by cmd/PowerShell, but NOT by WSL (which
# looks like a real Linux box to Make and correctly falls through to
# bash there).

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
