// STAGE 1 — Step-by-step crash isolation
// Writes progress markers to file so we know EXACTLY where it crashes

#include <stdio.h>
#include <stdlib.h>
#include <objc/runtime.h>

#define LOG(fmt, ...) do { FILE *l = fopen("/tmp/glow_diag.txt", "a"); if(l) { fprintf(l, fmt "\n", ##__VA_ARGS__); fclose(l); } } while(0)

__attribute__((constructor))
static void glow_init(void) {
  // Step 0: basic C works
  LOG("STEP0: alive");
  
  // Step 1: getenv + path
  const char *home = getenv("HOME");
  LOG("STEP1: home=%s", home ? home : "NULL");
  
  // Step 2: fopen + fclose
  FILE *f = fopen("/tmp/glow_step2.txt", "w");
  if (f) { fprintf(f, "ok"); fclose(f); }
  LOG("STEP2: fopen=%s", f ? "ok" : "FAIL");
  
  // Step 3: objc_getClass
  Class ns = objc_getClass("NSObject");
  LOG("STEP3: NSObject=%p", (void*)ns);
  
  // Step 4: sel_registerName
  SEL sel = sel_registerName("description");
  LOG("STEP4: description=%p", (void*)sel);
  
  // Step 5: class_getInstanceMethod
  Method m = class_getInstanceMethod(ns, sel);
  LOG("STEP5: method=%p", (void*)m);
  
  // Step 6: method_getImplementation
  IMP imp = method_getImplementation(m);
  LOG("STEP6: imp=%p", (void*)imp);
  
  // Step 7: method_setImplementation (same IMP, no change)
  IMP old = method_setImplementation(m, imp);
  LOG("STEP7: setImplementation old=%p", (void*)old);
  
  // Step 8: try calling via C function pointer
  if (imp) {
    // Call directly without objc_msgSend
    id instance = ((id(*)(Class, SEL))imp)((id)ns, sel);
    LOG("STEP8: instance=%p", (void*)instance);
  }
  
  // Step 9: class_createInstance
  id obj = class_createInstance(ns, 0);
  LOG("STEP9: created=%p", (void*)obj);
  
  // Final: write to Documents
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  f = fopen(path, "w");
  if (f) {
    fprintf(f, "All steps passed. See /tmp/glow_diag.txt for details.\n");
    fclose(f);
  }
}
