# hardware/ -- how a board is wired

A *descriptor* is one reusable piece of hardware (a console, a storage device,
a display, ...) expressed as the NuttX options it needs plus **parameters**
for the things that differ between builds: pins, buses, device paths, offsets.
A board lists the descriptors it has in its `[hardware]` section and sets the
parameters that are specific to it:

    [hardware]
    console = console/usb-cdcacm tty=/dev/ttyACM0
    storage = storage/flash-littlefs offset=0x100000 mount=/flash

so someone building their own device copies a board, changes a few `key=value`
words and builds. They never edit C or Kconfig.

## Descriptor format

    [hardware]
    type = storage                 # console | storage | display | input | audio | usb | ...
    description = ...
    status = verified              # verified | untested | draft (see below)
    verified_on = rp2040-zero      # which boards it was actually tested on

    [params]
    mount = /flash                 # name = default
    offset =                       # empty default => the board MUST set it

    [config]
    CONFIG_X=${offset}             # ${param} is substituted
    CONFIG_Y=y                     # the comment is the rationale

Status:

- `verified`  tested on real hardware or the sim (`verified_on` says where).
- `untested`  written from the datasheet/NuttX docs and compiles in principle,
              but nothing has run it.
- `draft`     a schema for hardware vaporOS cannot drive yet; the build
              refuses it unless `VCONFIG_ALLOW_DRAFT=1`. Drafts exist so the
              parameter names are agreed on before the code is written.

## What a descriptor can and cannot do

A descriptor only sets `CONFIG_` options. That is enough when NuttX's Kconfig
already exposes the parameter (a flash offset, a console path, a framebuffer
size). Many NuttX boards instead hard-code pins in board C code (for example the
SD card chip-select of a given board). For those, a descriptor can only select
the driver; the *pins* need a vaporOS board-glue layer driven by the
parameters, which does not exist yet. Descriptors that need it are `draft`
(see `storage/sdcard-spi.conf`). That is the work to do before the SD-card
boot and Cardputer-style devices; this directory is where it will be described.
