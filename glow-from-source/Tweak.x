// Stage 2: Hook UIView.didMoveToWindow — verify runtime hook fires
// Constructor: install hook via method_setImplementation
// Hook IMP: C function writes to file + calls original

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>

static IMP orig_didMoveToWindow = NULL;

static void hooked_didMoveToWindow(id self, SEL _cmd) {
  // This runs when UIKit calls objc_msgSend(self, @selector(didMoveToWindow))
  // PAC context is valid here — we're inside the runtime's call chain
  
  // Write evidence
  const char *home = getenv("HOME");
  if (home) {
    char path[512];
    snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
    FILE *f = fopen(path, "a");
    if (f) {
      fprintf(f, "HOOK_FIRED: UIView %p didMoveToWindow\n", (void*)self);
      fclose(f);
    }
  }
  
  // Call original
  if (orig_didMoveToWindow) {
    ((void(*)(id,SEL))orig_didMoveToWindow)(self, _cmd);
  }
}

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  if (!home) return;
  
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  
  FILE *f = fopen(path, "w");
  if (!f) return;
  
  // Hook UIView.didMoveToWindow
  Class uiView = objc_getClass("UIView");
  SEL dtmSel = sel_registerName("didMoveToWindow");
  Method dtmM = class_getInstanceMethod(uiView, dtmSel);
  
  orig_didMoveToWindow = method_getImplementation(dtmM);
  method_setImplementation(dtmM, (IMP)hooked_didMoveToWindow);
  
  IMP check = method_getImplementation(dtmM);
  
  fprintf(f, "UIView class: %p\n", (void*)uiView);
  fprintf(f, "orig IMP: %p\n", (void*)orig_didMoveToWindow);
  fprintf(f, "hooked IMP: %p\n", (void*)check);
  fprintf(f, "match: %s\n", check == (IMP)hooked_didMoveToWindow ? "YES" : "NO");
  fprintf(f, "\nHOOK INSTALLED: UIView.didMoveToWindow\n");
  fprintf(f, "Waiting for hook to fire...\n");
  
  fclose(f);
}
