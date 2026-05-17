// STAGE 1 — Hook Engine Validation (FINAL)
// Self-owned class, pure C runtime, no ARC interference
// If this works → runtime mutation works. System class issue was optimization.
// If this fails → ObjC runtime itself is restricted on iOS 16+ sideload.

#include <stdio.h>
#include <stdlib.h>
#include <objc/runtime.h>

// Custom class
@interface GlowTest : NSObject @end
@implementation GlowTest
- (int)test { return 1; }
@end

// Plain C replacement
static int hookedTest(id self, SEL _cmd) { return 999; }

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  
  FILE *f = fopen(path, "w");
  if (!f) return;
  
  // Pure C runtime — no ObjC messaging for setup
  Class cls = objc_getClass("GlowTest");
  if (!cls) { fprintf(f, "FAIL: GlowTest not found\n"); fclose(f); return; }
  
  Method m = class_getInstanceMethod(cls, sel_registerName("test"));
  if (!m) { fprintf(f, "FAIL: test method not found\n"); fclose(f); return; }
  
  IMP orig = method_getImplementation(m);
  
  // Create instance via C API
  id instance = class_createInstance(cls, 0);
  if (!instance) { fprintf(f, "FAIL: class_createInstance\n"); fclose(f); return; }
  
  // Call via objc_msgSend (only ObjC call)
  SEL testSel = sel_registerName("test");
  int before = ((int(*)(id, SEL))objc_msgSend)(instance, testSel);
  
  // Hook
  method_setImplementation(m, (IMP)hookedTest);
  
  // Call again
  int after = ((int(*)(id, SEL))objc_msgSend)(instance, testSel);
  
  fprintf(f, "Before: %d\n", before);
  fprintf(f, "After:  %d\n", after);
  
  if (before == 1 && after == 999)
    fprintf(f, "HOOK_ENGINE: method_setImplementation WORKS\n");
  else if (before == 1 && after == 1)
    fprintf(f, "HOOK_ENGINE: method_setImplementation SILENT FAIL\n");
  else
    fprintf(f, "HOOK_ENGINE: unexpected %d -> %d\n", before, after);
  
  fclose(f);
}
