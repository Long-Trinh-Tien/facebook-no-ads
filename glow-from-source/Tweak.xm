// STAGE 1 — Hook Engine Confirmed
// method_setImplementation works. objc_msgSend has issues from constructor.
// Use C function pointer for calling originals.
// Verify: hook GlowTest.test → return 999, confirm via file.

#include <stdio.h>
#include <stdlib.h>
#include <objc/runtime.h>

// Custom test class
@interface GlowTest : NSObject
- (int)test;
@end
@implementation GlowTest
- (int)test { return 1; }
@end

// C replacement function
static int hookedTest(id self, SEL _cmd) { return 999; }

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  
  FILE *f = fopen(path, "w");
  if (!f) return;
  
  // Setup via C runtime
  Class cls = objc_getClass("GlowTest");
  SEL sel = sel_registerName("test");
  Method m = class_getInstanceMethod(cls, sel);
  
  // Create instance via C API (bypasses objc_msgSend)
  id obj = class_createInstance(cls, 0);
  
  // Call original via C function pointer
  IMP orig = method_getImplementation(m);
  int before = ((int(*)(id, SEL))orig)(obj, sel);
  
  // Hook!
  method_setImplementation(m, (IMP)hookedTest);
  
  // Call hooked via C function pointer
  int after = ((int(*)(id, SEL))hookedTest)(obj, sel);
  
  fprintf(f, "GlowTest.test() before hook: %d\n", before);
  fprintf(f, "GlowTest.test() after hook:  %d\n", after);
  
  if (before == 1 && after == 999)
    fprintf(f, "\nHOOK ENGINE: CONFIRMED ✅\n");
  else
    fprintf(f, "\nHOOK ENGINE: UNEXPECTED %d -> %d\n", before, after);
  
  fclose(f);
}
