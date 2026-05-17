// STAGE 1 — Crash isolation (writes ONLY to Documents, no /tmp/)
// Step-by-step markers in glow_diag.txt in Documents

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  char diag[512];
  snprintf(diag, sizeof(diag), "%s/Documents/glow_diag.txt", home);
  
  // Helper: write step
  #define STEP(n) do { FILE *s = fopen(diag, "a"); if(s) { fprintf(s, "STEP%d\n", n); fclose(s); } } while(0)
  
  STEP(0);
  
  // 1. fopen/fclose on Documents (proven to work in STAGE 0)
  char test[512];
  snprintf(test, sizeof(test), "%s/Documents/glow_test.txt", home);
  FILE *tf = fopen(test, "w");
  if (tf) { fprintf(tf, "test"); fclose(tf); }
  STEP(1);
  
  // 2. objc_getClass — C function from libobjc
  Class nsobj = objc_getClass("NSObject");
  STEP(2);
  
  // 3. sel_registerName — create selector
  SEL desc = sel_registerName("description");
  STEP(3);
  
  // 4. class_getInstanceMethod — get method
  Method m = class_getInstanceMethod(nsobj, desc);
  STEP(4);
  
  // 5. method_getImplementation — get IMP
  IMP imp = method_getImplementation(m);
  STEP(5);
  
  // 6. method_setImplementation — swap with itself (no-op, just tests the API)
  method_setImplementation(m, imp);
  STEP(6);
  
  // 7. class_createInstance — allocate through runtime
  id instance = class_createInstance(nsobj, 0);
  STEP(7);
  
  // 8. Call method via C function pointer (NOT objc_msgSend)
  if (imp && instance) {
    ((void(*)(id, SEL))imp)(instance, desc);
  }
  STEP(8);
  
  // All steps passed! Write final result
  char result[512];
  snprintf(result, sizeof(result), "%s/Documents/glow_hook.txt", home);
  FILE *rf = fopen(result, "w");
  if (rf) {
    fprintf(rf, "All 8 steps passed. Hook engine primitives OK.\n");
    fclose(rf);
  }
}
