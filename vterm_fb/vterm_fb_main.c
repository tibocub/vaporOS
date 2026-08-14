/*
 * Milestone 2 of docs/vaporterm.md: minimal direct-framebuffer
 * rendering, no NX window/compositor involved. Opens /dev/fb0
 * directly (same mechanics as apps/examples/fbcon), feeds libvterm
 * a static string, and on each damage callback blits the affected
 * cells' glyphs straight into the mmap'd framebuffer via nxfonts.
 *
 * Not real NSH output yet (that's Milestone 3) -- this proves the
 * render pipeline in isolation: open fb -> mmap -> vterm parses text
 * -> damage callback -> nxfonts glyph -> pixels written to real
 * framebuffer memory.
 */

#include <nuttx/config.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>

#include <nuttx/video/fb.h>
#include <nuttx/nx/nxfonts.h>

#include "vterm.h"

#define VTERM_ROWS   24
#define VTERM_COLS   80

struct vterm_fb_state
{
  int fd;
  FAR uint8_t *fbmem;
  struct fb_videoinfo_s vinfo;
  struct fb_planeinfo_s pinfo;
  NXHANDLE font;
  FAR const struct nx_font_s *fontset;
  VTermScreen *screen;
};

static struct vterm_fb_state g_st;

/* One character cell's pixel footprint. NXFONT_SANS23X27's own name
 * says roughly what to expect; mxwidth/mxheight from the font metrics
 * is the actual source of truth. */

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

static VTermScreenCallbacks g_callbacks =
{
  .damage = on_damage
};

int main(int argc, FAR char *argv[])
{
  int ret;

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

  printf("vterm_fb: fb is %dx%d, %d bpp, stride %d\n",
         g_st.vinfo.xres, g_st.vinfo.yres, g_st.pinfo.bpp,
         g_st.pinfo.stride);

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

  g_st.font = nxf_getfonthandle(FONTID_SANS23X27);

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

  printf("vterm_fb: font cell is %dx%d px, screen fits ~%dx%d cells\n",
         g_cellw, g_cellh, g_st.vinfo.xres / g_cellw,
         g_st.vinfo.yres / g_cellh);

  /* Clear the whole framebuffer to black first. */

  memset(g_st.fbmem, 0, g_st.pinfo.fblen);

  VTerm *vt = vterm_new(VTERM_ROWS, VTERM_COLS);
  vterm_set_utf8(vt, 1);

  g_st.screen = vterm_obtain_screen(vt);
  vterm_screen_set_callbacks(g_st.screen, &g_callbacks, NULL);
  vterm_screen_reset(g_st.screen, 1);

  const char test[] =
    "vaporOS -- Milestone 2\r\n"
    "libvterm -> nxfonts -> /dev/fb0, no NX window\r\n"
    "\r\n"
    "If you can read this on a real screen, the pipeline works.";

  vterm_input_write(vt, test, strlen(test));

  printf("vterm_fb: done, static content rendered to framebuffer\n");

  vterm_free(vt);
  munmap(g_st.fbmem, g_st.pinfo.fblen);
  close(g_st.fd);

  return 0;
}
