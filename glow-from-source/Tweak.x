// Phase 2A — Visual Runtime Mapping
// Hook UIView.didMoveToWindow, add subtle colored border
// No file I/O at runtime. Visual feedback only.
// Filter: large interactive surfaces only

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>
#include <objc/message.h>

// Cached IMPs for UIKit calls (set in constructor, used in hook)
static IMP (*orig_didMoveToWindow)(id, SEL) = NULL;
static IMP (*imp_setBorderWidth)(id, SEL, CGFloat) = NULL;
static IMP (*imp_setBorderColor)(id, SEL, id) = NULL;
static IMP (*imp_layer)(id, SEL) = NULL;
static id (*imp_redColor)(id, SEL) = NULL;
static id (*imp_blueColor)(id, SEL) = NULL;
static id (*imp_greenColor)(id, SEL) = NULL;
static id (*imp_yellowColor)(id, SEL) = NULL;
static SEL sel_layer = NULL;
static SEL sel_setBorderWidth = NULL;
static SEL sel_setBorderColor = NULL;

static void hooked_didMoveToWindow(id self, SEL _cmd) {
  // Call original first
  if (orig_didMoveToWindow) {
    orig_didMoveToWindow(self, _cmd);
  }
  
  if (!self) return;
  
  // Filter: interactive + visible + large enough
  // Use runtime functions to check properties (avoid objc_msgSend)
  BOOL (*imp_isUserInteractionEnabled)(id, SEL) = NULL;
  SEL sel_ui = sel_registerName("isUserInteractionEnabled");
  Method m_ui = class_getInstanceMethod(object_getClass(self), sel_ui);
  if (m_ui) imp_isUserInteractionEnabled = (BOOL(*)(id,SEL))method_getImplementation(m_ui);
  
  BOOL (*imp_isHidden)(id, SEL) = NULL;
  SEL sel_hidden = sel_registerName("isHidden");
  Method m_hidden = class_getInstanceMethod(object_getClass(self), sel_hidden);
  if (m_hidden) imp_isHidden = (BOOL(*)(id,SEL))method_getImplementation(m_hidden);
  
  CGRect (*imp_frame)(id, SEL) = NULL;
  SEL sel_frame = sel_registerName("frame");
  Method m_frame = class_getInstanceMethod(object_getClass(self), sel_frame);
  if (m_frame) imp_frame = (CGRect(*)(id,SEL))method_getImplementation(m_frame);
  
  if (!imp_ui || !imp_hidden || !imp_frame) return;
  
  BOOL interactive = imp_isUserInteractionEnabled(self, sel_ui);
  BOOL hidden = imp_isHidden(self, sel_hidden);
  CGRect frame = imp_frame(self, sel_frame);
  
  if (!interactive || hidden || frame.size.width < 200) return;
  
  // Visual marker: colored border
  id (*imp_UIColor)(id,SEL) = NULL;
  switch ((int)(frame.size.width * frame.size.height) % 4) {
    case 0: imp_UIColor = imp_redColor; break;
    case 1: imp_UIColor = imp_greenColor; break;
    case 2: imp_UIColor = imp_blueColor; break;
    case 3: imp_UIColor = imp_yellowColor; break;
  }
  
  if (imp_UIColor && imp_setBorderColor && imp_setBorderWidth && imp_layer && sel_layer && sel_setBorderColor && sel_setBorderWidth) {
    id layer = imp_layer(self, sel_layer);
    id color = imp_UIColor(objc_getClass("UIColor"), sel_registerName("redColor"));
    if (layer && color) {
      imp_setBorderColor(layer, sel_setBorderColor, color);
      imp_setBorderWidth(layer, sel_setBorderWidth, 2.0);
    }
  }
}

__attribute__((constructor))
static void glow_init(void) {
  // Cache all needed IMPs at init time
  Class uiView = objc_getClass("UIView");
  Class uiColor = objc_getClass("UIColor");
  Class caLayer = objc_getClass("CALayer");
  
  sel_layer = sel_registerName("layer");
  sel_setBorderWidth = sel_registerName("setBorderWidth:");
  sel_setBorderColor = sel_registerName("setBorderColor:");
  
  // Hook UIView.didMoveToWindow
  SEL dtm = sel_registerName("didMoveToWindow");
  Method dtmM = class_getInstanceMethod(uiView, dtm);
  orig_didMoveToWindow = (IMP(*)(id,SEL))method_getImplementation(dtmM);
  method_setImplementation(dtmM, (IMP)hooked_didMoveToWindow);
  
  // Cache: layer, setBorderWidth:, setBorderColor:
  Method m_layer = class_getInstanceMethod(uiView, sel_layer);
  if (m_layer) imp_layer = (id(*)(id,SEL))method_getImplementation(m_layer);
  
  Method m_bw = class_getInstanceMethod(caLayer, sel_setBorderWidth);
  if (m_bw) imp_setBorderWidth = (void(*)(id,SEL,CGFloat))method_getImplementation(m_bw);
  
  Method m_bc = class_getInstanceMethod(caLayer, sel_setBorderColor);
  if (m_bc) imp_setBorderColor = (void(*)(id,SEL,id))method_getImplementation(m_bc);
  
  // Cache UIColor class methods (+redColor, +blueColor, +greenColor, +yellowColor)
  SEL redS = sel_registerName("redColor");
  Method m_red = class_getClassMethod(uiColor, redS);
  if (m_red) imp_redColor = (id(*)(id,SEL))method_getImplementation(m_red);
  
  SEL blueS = sel_registerName("blueColor");
  Method m_blue = class_getClassMethod(uiColor, blueS);
  if (m_blue) imp_blueColor = (id(*)(id,SEL))method_getImplementation(m_blue);
  
  SEL greenS = sel_registerName("greenColor");
  Method m_green = class_getClassMethod(uiColor, greenS);
  if (m_green) imp_greenColor = (id(*)(id,SEL))method_getImplementation(m_green);
  
  SEL yellowS = sel_registerName("yellowColor");
  Method m_yellow = class_getClassMethod(uiColor, yellowS);
  if (m_yellow) imp_yellowColor = (id(*)(id,SEL))method_getImplementation(m_yellow);
  
  // Write confirmation
  const char *home = getenv("HOME");
  if (home) {
    char path[512];
    snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
    FILE *f = fopen(path, "w");
    if (f) {
      fprintf(f, "VISUAL MAPPING ACTIVE\n");
      fprintf(f, "Hooked: UIView.didMoveToWindow\n");
      fprintf(f, "Filter: width>=200, interactive, visible\n");
      fprintf(f, "Marker: colored border (2pt) on CALayer\n");
      fprintf(f, "Colors: red/green/blue/yellow by area % 4\n");
      fclose(f);
    }
  }
}
