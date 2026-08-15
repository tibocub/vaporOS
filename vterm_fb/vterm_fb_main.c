/*
 * Milestone 3 of docs/vaporterm.md: a real NSH session rendered into
 * the framebuffer via libvterm, not static test content anymore.
 *
 * Runs NSH on the SLAVE side of a real NuttX pseudo-terminal
 * (openpty(), drivers/serial/pty.c) instead of a bespoke character
 * device -- the same master/slave split every real terminal emulator
 * uses (xterm, tmux, screen: shell on the slave, emulator reads the
 * master). This buys two concrete things a hand-rolled device
 * couldn't: the slave's own OPOST|ONLCR termios handling translates
 * NSH's bare '\n' to '\r\n' automatically (confirmed directly in
 * pty_write(), drivers/serial/pty.c) -- no manual translation needed
 * here any more -- and a real, symmetric channel for keyboard input
 * later (write to the master), rather than stdin staying bolted to
 * the host terminal indefinitely.
 *
 * The slave has ICANON and ECHO explicitly turned off after opening
 * it (see main(), tcsetattr below). This is deliberate, not a
 * leftover default: with ICANON on, read() on the slave would block
 * until a full line is buffered by the *pty driver itself*, which
 * would break NSH's own readline (apps/system/readline), which reads
 * and reacts one raw character at a time (confirmed: it does its own
 * backspace handling, RL_PUTC(vtbl, ASCII_BS) in readline_common.c).
 * With ECHO on, the driver would *also* echo every typed character
 * back out independently of NSH's own echo (see setup.sh --
 * CONFIG_READLINE_EDIT=n, which makes readline_common.c do its own
 * RL_PUTC echo), producing doubled output. This is exactly the
 * standard raw-mode setup any interactive shell puts its controlling
 * terminal into -- not something specific to us.
 *
 * A separate thread (vterm_reader_thread below) owns reading the
 * master and feeding libvterm, since nsh_consolemain() on the main
 * thread blocks for the whole session -- same reason a real terminal
 * emulator's PTY-reading loop and the shell it's driving are always
 * separate processes/threads, not one.
 */

#include <nuttx/config.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <pty.h>
#include <termios.h>
#include <pthread.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/boardctl.h>
#include <sys/mount.h>

#include <nuttx/fs/fs.h>
#include <nuttx/video/fb.h>
#include <nuttx/nx/nxfonts.h>

#include "vterm.h"
#include "nshlib/nshlib.h"

/* Matches the 800x600 display at 10x20 cells (X11_MISC_FIXED_10X20) --
 * 80x30 is also the classic standard terminal size, not a coincidence
 * worth losing: chosen because it lines up exactly, not picked first. */
#define VTERM_ROWS   30
#define VTERM_COLS   80

struct vterm_fb_state
{
  int fd;
  FAR uint8_t *fbmem;
  struct fb_videoinfo_s vinfo;
  struct fb_planeinfo_s pinfo;
  NXHANDLE font;
  FAR const struct nx_font_s *fontset;
  VTerm *vt;
  VTermScreen *screen;
  int master;
};

static struct vterm_fb_state g_st;

struct forward_arg_s
{
  int host_stdin;
  int master;
};

static struct forward_arg_s g_forward_arg;

static uint16_t g_cellw;
static uint16_t g_cellh;

static void draw_cell(int row, int col, uint32_t ch)
{
  FAR const struct nx_fontbitmap_s *fbm;
  uint32_t glyph[64 * 64];  /* generous fixed scratch, cellw*cellh always smaller */
  uint16_t stride;
  int gy;
  int gx;
  FAR uint32_t *dest;
  FAR uint32_t *src;

  if (ch == 0 || ch == ' ')
    {
      ch = ' ';
    }

  fbm = nxf_getbitmap(g_st.font, ch);

  stride = g_cellw * sizeof(uint32_t);

  /* Background fill first -- nxf_convert_* only paints foreground
   * ('1') bits, exactly like apps/examples/fbcon does. */

  for (gy = 0; gy < g_cellh; gy++)
    {
      for (gx = 0; gx < g_cellw; gx++)
        {
          glyph[gy * g_cellw + gx] = 0x00000000;  /* black background */
        }
    }

  if (fbm != NULL)
    {
      nxf_convert_32bpp(glyph, g_cellh, g_cellw, stride, fbm, 0x00ffffff);
    }

  /* Blit into the real framebuffer at this cell's pixel offset. */

  for (gy = 0; gy < g_cellh; gy++)
    {
      int fby = row * g_cellh + gy;

      if (fby >= g_st.vinfo.yres)
        {
          break;
        }

      dest = (FAR uint32_t *)(g_st.fbmem + fby * g_st.pinfo.stride +
                               col * g_cellw * sizeof(uint32_t));
      src  = &glyph[gy * g_cellw];

      memcpy(dest, src, g_cellw * sizeof(uint32_t));
    }
}

/* Same as draw_cell, but background/foreground swapped -- a simple
 * block cursor. Fetches the actual character so the cursor shows what
 * it's sitting on (inverted), not just a blank block. */

static void draw_cell_inverted(int row, int col)
{
  VTermPos pos;
  VTermScreenCell cell;
  FAR const struct nx_fontbitmap_s *fbm;
  uint32_t glyph[64 * 64];
  uint16_t stride;
  int gy;
  int gx;
  FAR uint32_t *dest;
  FAR uint32_t *src;
  uint32_t ch;

  pos.row = row;
  pos.col = col;
  vterm_screen_get_cell(g_st.screen, pos, &cell);
  ch = cell.chars[0];

  if (ch == 0)
    {
      ch = ' ';
    }

  fbm = nxf_getbitmap(g_st.font, ch);
  stride = g_cellw * sizeof(uint32_t);

  for (gy = 0; gy < g_cellh; gy++)
    {
      for (gx = 0; gx < g_cellw; gx++)
        {
          glyph[gy * g_cellw + gx] = 0x00ffffff;  /* inverted: white bg */
        }
    }

  if (fbm != NULL)
    {
      nxf_convert_32bpp(glyph, g_cellh, g_cellw, stride, fbm, 0x00000000);
    }

  for (gy = 0; gy < g_cellh; gy++)
    {
      int fby = row * g_cellh + gy;

      if (fby >= g_st.vinfo.yres)
        {
          break;
        }

      dest = (FAR uint32_t *)(g_st.fbmem + fby * g_st.pinfo.stride +
                               col * g_cellw * sizeof(uint32_t));
      src  = &glyph[gy * g_cellw];

      memcpy(dest, src, g_cellw * sizeof(uint32_t));
    }
}

static int on_damage(VTermRect rect, void *user)
{
  int row;
  int col;
  VTermPos pos;
  VTermScreenCell cell;

  for (row = rect.start_row; row < rect.end_row; row++)
    {
      for (col = rect.start_col; col < rect.end_col; col++)
        {
          pos.row = row;
          pos.col = col;
          vterm_screen_get_cell(g_st.screen, pos, &cell);
          draw_cell(row, col, cell.chars[0]);
        }
    }

  return 1;
}

/* Redraws the cell the cursor just left (so it doesn't stay lit up
 * forever) and the cell it's moving to, inverted, as a simple block
 * cursor. Minimal -- no blink, no shape options -- but a real visible
 * position indicator, which draw_cell()/on_damage() alone never gave
 * us (they only ever draw actual character cells). */

static int on_movecursor(VTermPos pos, VTermPos oldpos, int visible,
                          void *user)
{
  VTermScreenCell cell;

  vterm_screen_get_cell(g_st.screen, oldpos, &cell);
  draw_cell(oldpos.row, oldpos.col, cell.chars[0]);

  if (visible)
    {
      draw_cell_inverted(pos.row, pos.col);
    }

  return 1;
}

static VTermScreenCallbacks g_callbacks =
{
  .damage     = on_damage,
  .movecursor = on_movecursor
};

/****************************************************************************
 * Reads everything NSH writes to the PTY slave back out via the
 * master, and feeds it straight into libvterm -- the damage callback
 * drives the same rendering Milestone 2 already proved works. No '\n'
 * translation needed here: the slave's own OPOST|ONLCR already turned
 * NSH's bare '\n' into '\r\n' before it ever reached this end (see
 * pty_write() in drivers/serial/pty.c) -- unlike the old
 * /dev/vaporterm0 device, which had no termios layer at all and
 * needed that done by hand.
 *
 * Runs on its own thread because main() is about to block in
 * nsh_consolemain() for the whole session -- this loop has to be
 * running concurrently with that, not before or after it.
 ****************************************************************************/

static FAR void *vterm_reader_thread(FAR void *arg)
{
  char buffer[64];
  ssize_t nread;

#ifdef VAPORTERM_DEBUG_LOG
  /* Same diagnostic as before, now logging what arrives at the
   * master rather than what NSH wrote directly -- useful again if
   * anything about the pty switch itself needs debugging. */

  FILE *dbg;
  size_t i;
#endif

  for (; ; )
    {
      nread = read(g_st.master, buffer, sizeof(buffer));

      if (nread <= 0)
        {
          /* EOF (slave closed) or a real error -- either way, this
           * session is over; let the thread exit rather than spin.
           */

          break;
        }

#ifdef VAPORTERM_DEBUG_LOG
      dbg = fopen("/data/vaporterm_debug.log", "a");

      if (dbg != NULL)
        {
          fprintf(dbg, "read(%zd): ", nread);

          for (i = 0; i < (size_t)nread; i++)
            {
              unsigned char c = (unsigned char)buffer[i];

              if (c == '\r')
                {
                  fprintf(dbg, "\\r");
                }
              else if (c == '\n')
                {
                  fprintf(dbg, "\\n");
                }
              else if (c == 0x1b)
                {
                  fprintf(dbg, "\\e");
                }
              else if (c >= 0x20 && c < 0x7f)
                {
                  fputc(c, dbg);
                }
              else
                {
                  fprintf(dbg, "\\x%02x", c);
                }
            }

          fprintf(dbg, "\n");
          fclose(dbg);
        }
#endif

      vterm_input_write(g_st.vt, buffer, (size_t)nread);
    }

  return NULL;
}

/****************************************************************************
 * Forwards whatever arrives on this process's ORIGINAL stdin (the host
 * console, on sim -- saved as host_stdin before stdin got dup2'd onto
 * the pty slave below) into the pty master. Necessary, not optional:
 * without this, stdin now points at the slave and nothing would ever
 * write to the master, so NSH's read() on fd 0 would block forever --
 * a real regression from the old setup, where stdin stayed on the
 * host console directly. This is the "v1 keyboard" forwarding path
 * vaporterm.md called out as later work; the pty switch needed it
 * done now rather than left dangling.
 ****************************************************************************/

static FAR void *vterm_input_forward_thread(FAR void *arg)
{
  FAR struct forward_arg_s *fa = (FAR struct forward_arg_s *)arg;
  char buffer[64];
  ssize_t nread;

  for (; ; )
    {
      nread = read(fa->host_stdin, buffer, sizeof(buffer));

      if (nread <= 0)
        {
          break;
        }

      write(fa->master, buffer, (size_t)nread);
    }

  return NULL;
}

int main(int argc, FAR char *argv[])
{
  int ret;

  /* A standard sim:nsh boot mounts hostfs at /data via its rcS init
   * script (etc/init.d/rcS: "mount -t hostfs -o fs=. /data") before
   * ever reaching a shell. Our own entrypoint skips that script
   * entirely -- nsh_consolemain() is called directly below, not
   * through the normal boot sequence -- so /data never existed in
   * this build at all. Confirmed directly: CONFIG_FS_HOSTFS wasn't
   * even in .config, and the debug log's fopen() was failing
   * silently every time as a result. Doing the same mount() call
   * ourselves fixes that, and also makes /data genuinely usable from
   * inside a vaporterm NSH session generally, not just for the log.
   */

  ret = mount(NULL, "/data", "hostfs", 0, "fs=.");

  if (ret < 0)
    {
      fprintf(stderr, "vterm_fb: mount /data failed: ret=%d errno=%d "
              "(continuing without it)\n", ret, errno);
    }

  g_st.fd = open("/dev/fb0", O_RDWR);

  if (g_st.fd < 0)
    {
      fprintf(stderr, "vterm_fb: could not open /dev/fb0: %d\n", errno);
      return 1;
    }

  ret = ioctl(g_st.fd, FBIOGET_VIDEOINFO, (unsigned long)&g_st.vinfo);

  if (ret < 0)
    {
      fprintf(stderr, "vterm_fb: FBIOGET_VIDEOINFO failed: %d\n", errno);
      close(g_st.fd);
      return 1;
    }

  ret = ioctl(g_st.fd, FBIOGET_PLANEINFO, (unsigned long)&g_st.pinfo);

  if (ret < 0)
    {
      fprintf(stderr, "vterm_fb: FBIOGET_PLANEINFO failed: %d\n", errno);
      close(g_st.fd);
      return 1;
    }

  if (g_st.pinfo.bpp != 32)
    {
      fprintf(stderr, "vterm_fb: this milestone only handles 32bpp, "
              "got %d\n", g_st.pinfo.bpp);
      close(g_st.fd);
      return 1;
    }

  g_st.fbmem = mmap(NULL, g_st.pinfo.fblen, PROT_READ | PROT_WRITE,
                     MAP_SHARED, g_st.fd, 0);

  if (g_st.fbmem == MAP_FAILED)
    {
      fprintf(stderr, "vterm_fb: mmap failed: %d\n", errno);
      close(g_st.fd);
      return 1;
    }

  g_st.font = nxf_getfonthandle(FONTID_X11_MISC_FIXED_10X20);

  if (g_st.font == NULL)
    {
      fprintf(stderr, "vterm_fb: nxf_getfonthandle failed\n");
      munmap(g_st.fbmem, g_st.pinfo.fblen);
      close(g_st.fd);
      return 1;
    }

  g_st.fontset = nxf_getfontset(g_st.font);
  g_cellw = g_st.fontset->mxwidth;
  g_cellh = g_st.fontset->mxheight;

  memset(g_st.fbmem, 0, g_st.pinfo.fblen);

  g_st.vt = vterm_new(VTERM_ROWS, VTERM_COLS);
  vterm_set_utf8(g_st.vt, 1);

  g_st.screen = vterm_obtain_screen(g_st.vt);
  vterm_screen_set_callbacks(g_st.screen, &g_callbacks, NULL);
  vterm_screen_reset(g_st.screen, 1);

  {
    int slave;
    struct termios tio;
    pthread_t reader;
    pthread_t forwarder;

    ret = openpty(&g_st.master, &slave, NULL, NULL, NULL);

    if (ret < 0)
      {
        fprintf(stderr, "vterm_fb: openpty failed: %d\n", errno);
        vterm_free(g_st.vt);
        munmap(g_st.fbmem, g_st.pinfo.fblen);
        close(g_st.fd);
        return 1;
      }

    /* Raw mode on the slave: NSH's own readline does per-character
     * reads and its own echo (see the comment block at the top of
     * this file for why both ICANON and ECHO have to come off, not
     * just one). tcgetattr() first rather than zeroing the struct,
     * so we only touch the two flags that actually need changing and
     * leave everything else (baud-rate-shaped fields don't apply to
     * a pty, but c_cc[] special characters etc. do) at the driver's
     * own defaults.
     */

    ret = tcgetattr(slave, &tio);

    if (ret < 0)
      {
        fprintf(stderr, "vterm_fb: tcgetattr failed: %d\n", errno);
        close(slave);
        close(g_st.master);
        vterm_free(g_st.vt);
        munmap(g_st.fbmem, g_st.pinfo.fblen);
        close(g_st.fd);
        return 1;
      }

    tio.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(slave, TCSANOW, &tio);

    /* stdin now moves too, unlike the old /dev/vaporterm0 setup, since
     * the pty slave is a real bidirectional endpoint and NSH reads
     * its input from fd 0 same as always. Saving the ORIGINAL stdin
     * here (the host console, same fd this process would otherwise
     * have kept reading from) before overwriting fd 0, so
     * vterm_input_forward_thread has something to forward from --
     * see that function's comment for why this has to exist now
     * rather than staying deferred.
     */

    g_forward_arg.host_stdin = dup(0);
    g_forward_arg.master     = g_st.master;

    /* NuttX's sim itself is supposed to already put the real host
     * terminal (the one you launched ./nuttx from) into raw mode --
     * arch/sim/src/sim/posix/sim_hostuart.c, host_uart_start(),
     * called from sim_uartinit() when CONFIG_DEV_CONSOLE is set
     * (default y). Whether that path actually runs for vterm_fb's
     * boot sequence -- which uses vterm_fb_main as INIT_ENTRYPOINT
     * directly, bypassing the normal console/rcS bring-up nsh_main
     * would otherwise go through -- isn't something static reading
     * of the source can confirm either way. Doing it again here is
     * cheap and idempotent if NuttX already did it, and is the actual
     * fix if it didn't: without raw mode on the host side, the host's
     * own OS-level line discipline would buffer every keystroke until
     * Enter, which is indistinguishable from the "nothing shows while
     * typing" symptom actually being about our own code. Logging the
     * resulting state below so if this *isn't* the whole story, the
     * debug log says so directly instead of leaving another guess.
     */

    {
      struct termios host_tio;

      if (tcgetattr(g_forward_arg.host_stdin, &host_tio) == 0)
        {
          host_tio.c_lflag &= ~(ICANON | ECHO);
          host_tio.c_cc[VMIN]  = 1;
          host_tio.c_cc[VTIME] = 0;
          tcsetattr(g_forward_arg.host_stdin, TCSANOW, &host_tio);
        }

#ifdef VAPORTERM_DEBUG_LOG
      {
        FILE *dbg = fopen("/data/vaporterm_debug.log", "a");

        if (dbg != NULL)
          {
            struct termios check;

            fprintf(dbg, "-- pty/session setup --\n");

            if (tcgetattr(g_forward_arg.host_stdin, &check) == 0)
              {
                fprintf(dbg, "host_stdin: ICANON=%d ECHO=%d\n",
                        !!(check.c_lflag & ICANON),
                        !!(check.c_lflag & ECHO));
              }
            else
              {
                fprintf(dbg, "host_stdin: tcgetattr failed: %d\n",
                        errno);
              }

            if (tcgetattr(slave, &check) == 0)
              {
                fprintf(dbg, "slave: ICANON=%d ECHO=%d\n",
                        !!(check.c_lflag & ICANON),
                        !!(check.c_lflag & ECHO));
              }

            fclose(dbg);
          }
      }
#endif
    }

    fflush(stdout);
    fflush(stderr);

    dup2(slave, 0);
    dup2(slave, 1);
    dup2(slave, 2);

    close(slave);

    ret = pthread_create(&reader, NULL, vterm_reader_thread, NULL);

    if (ret != 0)
      {
        fprintf(stderr, "vterm_fb: pthread_create failed: %d\n", ret);
        close(g_forward_arg.host_stdin);
        close(g_st.master);
        vterm_free(g_st.vt);
        munmap(g_st.fbmem, g_st.pinfo.fblen);
        close(g_st.fd);
        return 1;
      }

    pthread_detach(reader);

    ret = pthread_create(&forwarder, NULL, vterm_input_forward_thread,
                          &g_forward_arg);

    if (ret != 0)
      {
        /* Non-fatal: rendering still works without this, just no
         * keyboard input -- same observable state as before this
         * milestone, so warn and keep going rather than tearing the
         * whole session down over it.
         */

        fprintf(stderr, "vterm_fb: pthread_create (input forward) "
                "failed: %d (no keyboard input this session)\n", ret);
      }
    else
      {
        pthread_detach(forwarder);
      }
  }

  /* Blocks here for the whole NSH session -- same as any other NSH
   * entrypoint. "exit" calls libc exit() directly from deep inside
   * NSH's own nsh_consoleexit() (apps/nshlib/nsh_console.c, marked
   * noreturn_function) -- confirmed from source, not assumed -- so
   * nothing after this call ever runs when the user types "exit".
   * That's also the conceptually correct behaviour: exit should end
   * this session, not power off the whole machine, the same way
   * exiting a shell on a real Unix system doesn't shut down the
   * computer. "poweroff" is NSH's own real command for that (needs
   * CONFIG_BOARDCTL_POWEROFF, which setup.sh already enables for this
   * target) -- confirmed working by piping it through plain sim:nsh
   * and checking the process actually terminated. No need to
   * duplicate that here.
   */

  nsh_consolemain(argc, argv);

  vterm_free(g_st.vt);
  munmap(g_st.fbmem, g_st.pinfo.fblen);
  close(g_st.fd);

  return 0;
}
