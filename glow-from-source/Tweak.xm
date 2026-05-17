// STAGE 1 — Hook NSObject.description via method_setImplementation
// ObjC runtime C functions work. @implementation and objc_allocateClassPair crash.
// Test: replace description on NSObject, verify via file.

#include <stdio.h>
#include <stdlib.h>
#include <objc/runtime.h>

// Replacement: returns constant string
static id hookedDesc(id self, SEL _cmd) {
  return (id)objc_getClass("NSString");  // lie — just checking if hook fires
}

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  
  FILE *f = fopen(path, "w");
  if (!f) return;
  
  // Get NSObject's description method
  Class cls = objc_getClass("NSObject");
  SEL sel = sel_registerName("description");
  Method m = class_getInstanceMethod(cls, sel);
  
  IMP orig = method_getImplementation(m);
  
  // Create an NSObject instance for testing
  id obj = class_createInstance(cls, 0);
  
  // Call original via C function pointer
  id descBefore = ((id(*)(id, SEL))orig)(obj, sel);
  
  // Hook!
  method_setImplementation(m, (IMP)hookedDesc);
  
  // Get the NEW IMP and call it
  IMP newImp = method_getImplementation(m);
  id descAfter = ((id(*)(id, SEL))newImp)(obj, sel);
  
  fprintf(f, "NSObject instance: %p\n", (void*)obj);
  fprintf(f, "Original IMP: %p\n", (void*)orig);
  fprintf(f, "Hooked IMP:  %p\n", (void*)newImp);
  fprintf(f, "description before: %s\n", ((id(*)(id,SEL))orig)(obj, sel) ? "NON-NULL" : "NULL");
  fprintf(f, "description after:  %s\n", descAfter ? "NON-NULL" : "NULL");
  
  if (newImp == (IMP)hookedDesc) {
    fprintf(f, "\nHOOK ENGINE: method_setImplementation REPLACED IMP ✅\n");
  } else {
    fprintf(f, "\nHOOK ENGINE: IMP NOT REPLACED (still %p)\n", (void*)newImp);
  }
  
  // Restore
  method_setImplementation(m, orig);
  
  fclose(f);
}
