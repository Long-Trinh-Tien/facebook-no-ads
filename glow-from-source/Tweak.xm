// STAGE 0v2 — Primitive Injection Proof (REAL)
// NO UIKit. NO Foundation writeToFile. NO dispatch_async.
// POSIX write to /tmp/ (world-writable on iOS, no sandbox issues)
// If /tmp/glow_alive.txt appears → dylib executes.

#include <fcntl.h>
#include <unistd.h>

__attribute__((constructor))
static void glow_init(void) {
  int fd = open("/tmp/glow_alive.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd >= 0) {
    write(fd, "GLOW_ALIVE", 10);
    close(fd);
  }
  
  // Also try Documents (will fail silently if sandbox not ready)
  // /tmp/ is always writable
}
