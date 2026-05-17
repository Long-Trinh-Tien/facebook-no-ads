// STAGE 1v7 — pure C ObjC runtime, ZERO ObjC message sends in constructor
// Use objc_getClass, sel_registerName, objc_msgSend instead of [ClassName] @selector()
// If this works → problem was ObjC messaging in constructor, not hook API

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>
#include <objc/message.h>

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  
  FILE *f = fopen(path, "w");
  if (!f) return;
  
  // Pure C runtime API — NO ObjC message sends
  Class nsstring = objc_getClass("NSString");
  if (!nsstring) { fprintf(f, "FAIL: NSString class not found\n"); fclose(f); return; }
  
  SEL lenSel = sel_registerName("length");
  SEL hashSel = sel_registerName("hash");
  
  Method lenM = class_getInstanceMethod(nsstring, lenSel);
  Method hashM = class_getInstanceMethod(nsstring, hashSel);
  
  if (!lenM || !hashM) {
    fprintf(f, "FAIL: methods not found (len=%p hash=%p)\n", (void*)lenM, (void*)hashM);
    fclose(f);
    return;
  }
  
  // Call methods via objc_msgSend — pure C
  id testStr = (id)objc_getClass("__NSCFString");  // Actually need a string instance
  // Create a string via NSString's alloc/init (this sends ObjC messages too...)
  
  // Simpler: just check the method IMPs before/after swap
  IMP lenImp = method_getImplementation(lenM);
  IMP hashImp = method_getImplementation(hashM);
  
  fprintf(f, "Before swap: lenIMP=%p hashIMP=%p\n", (void*)lenImp, (void*)hashImp);
  
  // Swap
  method_exchangeImplementations(lenM, hashM);
  
  IMP lenImpAfter = method_getImplementation(lenM);
  IMP hashImpAfter = method_getImplementation(hashM);
  
  fprintf(f, "After swap:  lenIMP=%p hashIMP=%p\n", (void*)lenImpAfter, (void*)hashImpAfter);
  
  // Verify: lenIMP should now equal original hashImp, vice versa
  if (lenImpAfter == hashImp && hashImpAfter == lenImp) {
    fprintf(f, "HOOK_ENGINE: method_exchangeImplementations WORKS\n");
  } else {
    fprintf(f, "HOOK_ENGINE: SWAP FAILED — IMPs unchanged\n");
  }
  
  // Swap back
  method_exchangeImplementations(lenM, hashM);
  
  fclose(f);
}
