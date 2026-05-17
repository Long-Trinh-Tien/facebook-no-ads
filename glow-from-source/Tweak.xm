// STAGE 1v6 — method_exchangeImplementations test
// Swap NSString.length with NSString.hash
// Sau swap: [@"test" length] trả về hash, [@"test" hash] trả về 4
// KHÔNG imp_implementationWithBlock, KHÔNG MSHookMessageEx
// Verify qua file write (confirmed safe từ STAGE 0v3)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>

__attribute__((constructor))
static void glow_init(void) {
  // Get home path for file write
  const char *home = getenv("HOME");
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  
  // Get methods and swap
  Method lenM = class_getInstanceMethod([NSString class], @selector(length));
  Method hashM = class_getInstanceMethod([NSString class], @selector(hash));
  
  FILE *f = fopen(path, "w");
  if (!f) return;
  
  if (!lenM || !hashM) {
    fprintf(f, "FAIL: methods not found\n");
    fclose(f);
    return;
  }
  
  // Record before swap
  NSUInteger beforeLen = [@"test" length];
  NSUInteger beforeHash = [@"test" hash];
  
  // Swap!
  method_exchangeImplementations(lenM, hashM);
  
  // Record after swap
  NSUInteger afterLen = [@"test" length];
  NSUInteger afterHash = [@"test" hash];
  
  // Swap back (so app doesn't break)
  method_exchangeImplementations(lenM, hashM);
  
  fprintf(f, "Before: length=%lu hash=%lu\n", (unsigned long)beforeLen, (unsigned long)beforeHash);
  fprintf(f, "After:  length=%lu hash=%lu\n", (unsigned long)afterLen, (unsigned long)afterHash);
  fprintf(f, "If length=hash and hash=4 -> method_exchangeImplementations WORKS\n");
  fclose(f);
}
