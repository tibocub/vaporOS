/* vinit -- vaporOS init for USB-console boards. Does what NSH's
 * nsh_usbconsole.c does (connect CDC/ACM, wait for the host, dup2 onto
 * stdio) but runs vaporshell instead of an NSH session.
 */

#include <nuttx/config.h>

#include <sys/boardctl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <unistd.h>

#include <nuttx/usb/cdcacm.h>

extern char **environ;

/* Open the console and wait for three consecutive Enters, which proves a
 * terminal is actually attached (the device node opens before that). Returns
 * the fd, or -1 on error.
 */

static int wait_for_host(void)
{
  int fd;
  int nlc;
  char ch;

  for (; ; )
    {
      while ((fd = open(CONFIG_VAPOROS_VINIT_TTY, O_RDWR)) < 0)
        {
          sleep(2);          /* ENOTCONN until the host enumerates us */
        }

      nlc = 0;
      while (nlc < 3)
        {
          if (read(fd, &ch, 1) != 1)
            {
              break;         /* error/EOF: host went away, start over */
            }

          nlc = (ch == '\r' || ch == '\n') ? nlc + 1 : 0;
        }

      if (nlc >= 3)
        {
          return fd;
        }

      close(fd);
    }
}

int main(int argc, FAR char *argv[])
{
  struct boardioc_usbdev_ctrl_s ctrl;
  FAR void *handle;
  char *sh_argv[] = { CONFIG_VAPOROS_VINIT_SHELL, NULL };
  pid_t pid;
  int fd;

#if defined(CONFIG_CDCACM) && !defined(CONFIG_USBDEV_COMPOSITE)
  ctrl.usbdev   = BOARDIOC_USBDEV_CDCACM;
  ctrl.action   = BOARDIOC_USBDEV_CONNECT;
  ctrl.instance = 0;
  ctrl.handle   = &handle;
  boardctl(BOARDIOC_USBDEV_CONTROL, (uintptr_t)&ctrl);
#else
#  error "vinit currently supports a plain CDC/ACM console only"
#endif

  /* Expose the builtin apps as /bin/<name>; vaporshell finds commands there */

  mkdir("/bin", 0755);
  mount(NULL, "/bin", "binfs", 0, NULL);

  /* Until a host is attached, stdio must not point at a dead device */

  fd = open("/dev/null", O_RDWR);
  if (fd >= 0)
    {
      dup2(fd, 0); dup2(fd, 1); dup2(fd, 2);
      if (fd > 2) close(fd);
    }

  for (; ; )
    {
      fd = wait_for_host();
      dup2(fd, 0); dup2(fd, 1); dup2(fd, 2);
      if (fd > 2) close(fd);

      if (posix_spawnp(&pid, sh_argv[0], NULL, NULL, sh_argv, environ) == 0)
        {
          waitpid(pid, NULL, 0);
        }
      else
        {
          dprintf(1, "vinit: cannot start %s\r\n", sh_argv[0]);
          sleep(2);
        }
    }

  return 0;
}
