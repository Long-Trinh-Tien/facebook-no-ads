// STAGE 0v3 — Injection Proof via Documents
// POSIX write to Documents/glow_alive.txt (readable via Files app)
// NO UIKit, NO ObjC, NO dispatch_async

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  if (!home) return;
  
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_alive.txt", home);
  
  // Ensure Documents dir exists (create if not)
  char dir[512];
  snprintf(dir, sizeof(dir), "%s/Documents", home);
  mkdir(dir, 0755);
  
  FILE *f = fopen(path, "w");
  if (f) {
    fprintf(f, "GLOW_ALIVE\n");
    fclose(f);
  }
}
