# boards/ -- one directory per target

A *board* is everything vaporOS needs to know to build for one target: which
NuttX configuration to start from, which software to include, how the hardware
is wired, which host tools to use, and how to flash and open a console.

    make -f dev.mk boards                 # list
    make -f dev.mk build BOARD=rp2040-zero
    make -f dev.mk run   BOARD=rp2040-zero   # flash + console (the simulator just runs)
    make -f dev.mk show  BOARD=rp2040-zero   # the resolved configuration AND why each option is there

There is no per-target code in the build scripts. Adding a target means adding a
directory here, not editing scripts, `dev.mk` or the Makefiles.

## Where configuration comes from

Options are applied in this order; a later layer wins:

1. the NuttX base configuration named by `nuttx_config` (`./tools/configure.sh`)
2. the parent board, if `extends` is set
3. `features/*.conf`  -- software (vaporshell, Lua, vi, ...): the same on every board
4. `hardware/<type>/<name>.conf` -- how this device is wired: pins, buses, paths
5. the board's own `[config]` -- what is true of this board only
6. `local/<board>.conf` -- your own overrides, never committed

The rule of thumb for where an option belongs: **a property of the software goes
in a feature** (vaporshell needs a 16 KB stack on any chip), **a property of the
wiring goes in a hardware descriptor** (which UART, which flash offset),
**anything else about this board goes in the board.** If the same line appears in
two boards it should have been a feature.

Afterwards `scripts/vbuild.sh` runs `vconfig.py verify`: Kconfig silently drops
an option whose dependency is not met (it did, for months, for options the old
scripts "enabled"), so a requested option that did not take effect fails the
build, naming the option, who asked for it and why. `VCONFIG_LENIENT=1` builds anyway.

## board.conf

    [board]
    name = rp2040-zero
    description = Waveshare RP2040-Zero ...
    nuttx_config = waveshare-rp2040-zero:usbnsh   # argument to NuttX's configure.sh
    extends = other-board                         # optional parent
    aliases = rp2040                              # optional extra names
    runner = rp2040-uf2                           # tools/runners/<runner>.sh: flash|term|run

    [patches]            # NuttX/nuttx-apps patches this board needs (patches/UPSTREAM.md)
    rp2040-uf2-family.patch

    [tools]              # host toolchain; ${VAR:-default} lets the environment override
    path = ${ARM_TOOLCHAIN_BIN:-~/toolchains/arm-gnu/*/bin}
    env.PICO_SDK_PATH = ${PICO_SDK_PATH:-~/toolchains/pico-sdk}
    require = arm-none-eabi-gcc picotool

    [features]           # names of features/*.conf; "-name" removes one inherited from a parent
    base
    lua

    [hardware]           # slot = type/descriptor param=value ...
    console = console/usb-cdcacm tty=/dev/ttyACM0
    storage = storage/flash-littlefs offset=0x100000

    [config]             # raw NuttX options; the comment is the rationale
    CONFIG_LINE_MAX=256   # why

`CONFIG_X=y|n|123|0x10|"text"`. Comments on the line, or on the lines directly
above it, are kept and shown by `make show` / `vconfig.py explain`. **Write the why.**
Several options in this tree exist because of a bug that took a day to find.

## Making a board for your own hardware

You do not need to change any code to describe a different wiring.

1. Copy the closest board: `cp -r boards/rp2040-zero boards/my-device`
   (or write a small one that `extends = rp2040-zero` and only changes what differs).
2. Edit `[board]` (name, description) and the `[hardware]` lines: change a
   `tty=`, an `offset=`, a pin parameter.
3. `make -f dev.mk check` validates every board, feature and descriptor, then
   `make -f dev.mk build BOARD=my-device`.
4. For a one-off tweak that should not be committed (a different flash offset on
   *your* unit), use `local/<board>.conf` instead of a new board.

A board needs a NuttX base configuration to start from. If NuttX has no board for
your chip/module, that is NuttX board-porting work (see docs/porting-a-new-board.md),
which this layer cannot remove; it can only keep everything *above* NuttX
declarative.

## Hardware descriptors

See hardware/README.md. They carry parameters (pins, buses, paths) and a
status (`verified`, `untested`, `draft`) so nobody builds for hardware vaporOS
cannot drive yet without being told.

## Checking your work

    make -f dev.mk check                    # syntax, parameters, patch names, status rules
    make -f dev.mk configure BOARD=...      # produce nuttx/.config only (seconds) and verify it
    python3 tools/vconfig.py explain <board> CONFIG_X   # who set it, who overrode it, why
