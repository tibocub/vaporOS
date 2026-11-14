// What QEMU is started with in the browser. nuttx is the vaporOS rv-virt ELF, baked into /pack by `qemu-wasm.sh pack`.
// -bios none: NuttX boots in M-mode itself, no OpenSBI. 32 MB is exactly the board's NuttX RAM; tb-size=32 is the JIT code cache (was 500: ~500 MB of tab RAM for a tiny guest).
// Assign the property: load.js has already put the file-package loader on the global Module, don't replace it.
Module.arguments = [
    "-nographic", "-M", "virt", "-cpu", "rv64", "-smp", "1", "-m", "32M", "-bios", "none",
    "-accel", "tcg,tb-size=32",
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
