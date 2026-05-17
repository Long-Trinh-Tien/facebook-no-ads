// STAGE 1 — Minimal check: does fopen even work in this build?

#include <stdio.h>
#include <stdlib.h>

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  
  // Just write "alive" — same as STAGE 0v3 which worked
  FILE *f = fopen(path, "w");
  if (f) {
    fprintf(f, "alive\n");
    fclose(f);
  }
}
