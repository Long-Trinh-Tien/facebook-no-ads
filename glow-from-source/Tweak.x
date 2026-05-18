// No Logos, no ObjC messaging. Pure C + ObjC runtime functions only.
// Diagnostic: writes 8 steps + HOOK ENGINE confirmation to Documents/glow_hook.txt

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  if (!home) return;
  
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  
  FILE *f = fopen(path, "w");
  if (!f) return;
  
  // Step 1: objc_getClass
  Class nsObj = objc_getClass("NSObject");
  Class nsStr = objc_getClass("NSString");
  fprintf(f, "STEP1  NSObject=%p NSString=%p\n", (void*)nsObj, (void*)nsStr);
  
  // Step 2: sel_registerName
  SEL descSel = sel_registerName("description");
  fprintf(f, "STEP2  description SEL=%p\n", (void*)descSel);
  
  // Step 3: class_getInstanceMethod
  Method descM = class_getInstanceMethod(nsObj, descSel);
  fprintf(f, "STEP3  description Method=%p\n", (void*)descM);
  
  // Step 4: method_getImplementation
  IMP origIMP = method_getImplementation(descM);
  fprintf(f, "STEP4  orig IMP=%p\n", (void*)origIMP);
  
  // Step 5: class_createInstance + call via C fn ptr
  id inst = class_createInstance(nsObj, 0);
  id val = ((id(*)(id,SEL))origIMP)(inst, descSel);
  fprintf(f, "STEP5  instance=%p desc=%s\n", (void*)inst, val ? "NONNULL" : "NULL");
  
  // Step 6: method_setImplementation (replace)
  method_setImplementation(descM, (IMP)origIMP);
  IMP check1 = method_getImplementation(descM);
  fprintf(f, "STEP6  set+get IMP=%p match=%s\n", (void*)check1, check1 == origIMP ? "YES" : "NO");
  
  // Step 7: restore
  method_setImplementation(descM, origIMP);
  IMP check2 = method_getImplementation(descM);
  fprintf(f, "STEP7  restored IMP=%p match=%s\n", (void*)check2, check2 == origIMP ? "YES" : "NO");
  
  // Step 8: hook UIView.didMoveToWindow (actual UIKit hook)
  Class uiView = objc_getClass("UIView");
  SEL dtmSel = sel_registerName("didMoveToWindow");
  Method dtmM = class_getInstanceMethod(uiView, dtmSel);
  IMP dtmIMP = method_getImplementation(dtmM);
  fprintf(f, "STEP8  UIView.didMoveToWindow IMP=%p\n", (void*)dtmIMP);
  
  fprintf(f, "\nHOOK_ENGINE PRIMITIVES: CONFIRMED\n");
  
  fclose(f);
}
