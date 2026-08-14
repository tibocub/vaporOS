/*
 * Milestone 3 of docs/vaporterm.md: a real NSH session rendered into
 * the framebuffer via libvterm, not static test content anymore.
 *
 * Registers our own character device (/dev/vaporterm0) -- same idiom
 * NuttX's own NXTERM uses, not a pipe/separate-task scheme. Its write
 * callback feeds bytes straight into libvterm and triggers the same
 * damage-driven rendering Milestone 2 already proved works. NSH's
 * stdout/stderr get redirected to that device (dup2, same exact
 * pattern apps/examples/nxterm_main.c uses); stdin is deliberately
 * left untouched -- keyboard input still comes from wherever this
 * process's own stdin is (the host terminal, on sim), matching the
 * "v1 keyboard" stage in vaporterm.md. True in-window typing is later
 * work, not this milestone.
 */

#include <nuttx/config.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/boardctl.h>

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

#define VAPORTERM_DEVPATH "/dev/vaporterm0"

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
};

static struct vterm_fb_state g_st;

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
 * /dev/vaporterm0 character device -- NSH's stdout/stderr get
 * redirected here. Every write() (i.e. every printf/puts NSH does)
 * lands in vaporterm_write(), which feeds libvterm and lets its
 * damage callback drive the same rendering Milestone 2 proved works.
 * Synchronous, on purpose -- same idiom NXTERM itself uses, no
 * separate task or pipe needed.
 ****************************************************************************/

static ssize_t vaporterm_write(FAR struct file *filep,
                                FAR const char *buffer, size_t buflen)
{
  /* A real TTY's line discipline translates outgoing \n to \r\n
   * (ONLCR) before a terminal ever sees it. /dev/vaporterm0 is a raw
   * character device with no such translation, so NSH's bare \n
   * reaches libvterm unchanged -- which, correctly per strict VT100
   * behaviour, moves the cursor down without returning to column 0.
   * Confirmed directly: this produces the exact "staircase" pattern
   * where each new line starts one column further right than the
   * last. Translating here is the fix, not a workaround -- this is
   * exactly the job a TTY driver would otherwise be doing for us.
   * Extra \r before an already-present \r\n is harmless (idempotent),
   * so no need to check first.
   */

  size_t i;

  for (i = 0; i < buflen; i++)
    {
      if (buffer[i] == '\n')
        {
          vterm_input_write(g_st.vt, "\r", 1);
        }

      vterm_input_write(g_st.vt, &buffer[i], 1);
    }

  return buflen;
}

static int vaporterm_open(FAR struct file *filep)
{
  return OK;
}

static int vaporterm_close(FAR struct file *filep)
{
  return OK;
}

static const struct file_operations g_vaporterm_fops =
{
  vaporterm_open,   /* open */
  vaporterm_close,  /* close */
  NULL,             /* read */
  vaporterm_write,  /* write */
};

int main(int argc, FAR char *argv[])
{
  int ret;
  int fd;

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

  ret = register_driver(VAPORTERM_DEVPATH, &g_vaporterm_fops, 0666, NULL);

  if (ret < 0)
    {
      fprintf(stderr, "vterm_fb: register_driver failed: %d\n", ret);
      vterm_free(g_st.vt);
      munmap(g_st.fbmem, g_st.pinfo.fblen);
      close(g_st.fd);
      return 1;
    }

  fd = open(VAPORTERM_DEVPATH, O_WRONLY);

  if (fd < 0)
    {
      fprintf(stderr, "vterm_fb: open %s failed: %d\n",
              VAPORTERM_DEVPATH, errno);
      vterm_free(g_st.vt);
      munmap(g_st.fbmem, g_st.pinfo.fblen);
      close(g_st.fd);
      return 1;
    }

  /* stdin is deliberately untouched -- NSH keeps reading from wherever
   * this process's own stdin already is. Only stdout/stderr move. */

  fflush(stdout);
  fflush(stderr);

  dup2(fd, 1);
  dup2(fd, 2);

  close(fd);

  /* Blocks here for the whole NSH session -- same as any other NSH
   * entrypoint. Returns when the user types "exit" (or "poweroff",
   * which never reaches here since it terminates the process
   * directly). */

  nsh_consolemain(argc, argv);

  vterm_free(g_st.vt);
  munmap(g_st.fbmem, g_st.pinfo.fblen);
  close(g_st.fd);

  /* Confirmed directly (piped "poweroff" through plain sim:nsh, exit
   * code showed the whole process actually terminated, not just this
   * task returning): native_sim keeps running as a simulated OS after
   * its boot task exits -- same idle-forever behaviour Milestone 2's
   * SIGTERM finding already established. Without this, "exit" would
   * only end the NSH session while the underlying process kept
   * running, same complaint as needing `kill` to stop it. poweroff
   * the board explicitly so "exit" gives a real, complete shutdown.
   */

  boardctl(BOARDIOC_POWEROFF, 0);

  return 0;
}
