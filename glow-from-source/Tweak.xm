// STAGE 1 — Dynamic class via objc_allocateClassPair
// @implementation GlowTest crashes pre-constructor on iOS 16+ sideload
// Create class DYNAMICALLY in constructor instead

#include <stdio.h>
#include <stdlib.h>
#include <objc/runtime.h>

// C replacement function
static int hookedTest(id self, SEL _cmd) { return 999; }
static int origTest(id self, SEL _cmd) { return 1; }

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  
  FILE *f = fopen(path, "w");
  if (!f) return;
  
  // Create a new class at runtime (bypasses compile-time ObjC registration)
  Class newClass = objc_allocateClassPair(objc_getClass("NSObject"), "GlowDynamicTest", 0);
  if (!newClass) {
    fprintf(f, "FAIL: objc_allocateClassPair\n");
    fclose(f);
    return;
  }
  
  // Add method
  class_addMethod(newClass, sel_registerName("test"), (IMP)origTest, "i@:");
  
  // Register
  objc_registerClassPair(newClass);
  
  // Create instance
  id obj = class_createInstance(newClass, 0);
  if (!obj) {
    fprintf(f, "FAIL: class_createInstance\n");
    fclose(f);
    return;
  }
  
  // Test before hook
  IMP orig = class_getMethodImplementation(newClass, sel_registerName("test"));
  int before = ((int(*)(id, SEL))orig)(obj, sel_registerName("test"));
  
  // Hook!
  Method m = class_getInstanceMethod(newClass, sel_registerName("test"));
  method_setImplementation(m, (IMP)hookedTest);
  
  // Test after hook
  IMP hooked = class_getMethodImplementation(newClass, sel_registerName("test"));
  int after = ((int(*)(id, SEL))hooked)(obj, sel_registerName("test"));
  
  fprintf(f, "Before: %d\n", before);
  fprintf(f, "After:  %d\n", after);
  
  if (before == 1 && after == 999)
    fprintf(f, "\nHOOK ENGINE: CONFIRMED on dynamic class ✅\n");
  else
    fprintf(f, "\nUNEXPECTED: %d -> %d\n", before, after);
  
  fclose(f);
}
