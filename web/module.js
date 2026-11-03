// What QEMU is started with in the browser. nuttx is the vaporOS rv-virt ELF, baked into /pack by `qemu-wasm.sh pack`.
// -bios none: NuttX boots in M-mode itself, no OpenSBI. 64 MB is plenty (the board has 32 MB of NuttX RAM).
// Assign the property: load.js has already put the file-package loader on the global Module, don't replace it.
Module.arguments = [
    "-nographic", "-M", "virt", "-cpu", "rv64", "-smp", "1", "-m", "64M", "-bios", "none",
    "-accel", "tcg,tb-size=500",
    "-kernel", "/pack/nuttx",
    // The shell runs on a virtio-serial port (the guest hands over whole buffers); the UART, the boot console, is dropped.
    "-serial", "null", "-monitor", "none",
    "-chardev", "stdio,id=con", "-device", "virtio-serial-device", "-device", "virtconsole,chardev=con",
];

// Debug: ?qemu=<args separated by |> replaces the command line (to try accelerator/serial settings without rebuilding).
{
  const a = new URLSearchParams(location.search).get("qemu");
  if (a) Module.arguments = a.split("|");
}
