# local/ -- per-user overrides (untracked)

`local/<board>.conf` is applied after everything else for that board, so
a user can change a pin, a stack size or any `CONFIG_` option without editing
tracked files:

    # local/rp2040-zero.conf
    [config]
    CONFIG_RP2040_FLASH_FS_OFFSET=0x180000   # my firmware is smaller

For a whole different device, copy a board directory and edit it instead
(see boards/README.md, "Making a board for your own hardware").
