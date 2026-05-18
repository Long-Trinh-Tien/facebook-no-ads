// Phase 2B.1 — Manual Inspector
// 3-finger tap to scan + highlight main window hierarchy
// No auto-scan. No logging.

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>

static IMP (*orig_sendEvent)(id, SEL, id) = NULL;

// Clear all markers before fresh scan
static void clearMarkers(UIView *view) {
  if (!view) return;
  view.layer.borderWidth = 0;
  view.layer.borderColor = nil;
  view.alpha = 1.0;
  for (UIView *sub in [view subviews]) {
    clearMarkers(sub);
  }
}

static void markView(UIView *view, int depth) {
  if (!view || depth > 15) return;
  if ([view isHidden] || view.window == nil) return;
  
  CGRect f = [view frame];
  CGFloat sw = [UIScreen mainScreen].bounds.size.width;
  
  // Check children for collection/scroll
  BOOL hasCollection = NO;
  BOOL hasScroll = NO;
  for (UIView *sub in [view subviews]) {
    if ([sub isKindOfClass:[UICollectionView class]]) hasCollection = YES;
    if ([sub isKindOfClass:[UIScrollView class]]) hasScroll = YES;
  }
  
  // Classification
  UIColor *color = nil;
  CGFloat borderW = 0;
  
  if (f.size.width >= sw - 10 && depth <= 3) {
    // Full-width, shallow → primary container (feed, reels)
    color = [UIColor redColor];
    borderW = 3.0;
  } else if (hasCollection && f.size.width > 150) {
    // Collection container → feed row
    color = [UIColor blueColor];
    borderW = 2.0;
  } else if (hasScroll && f.size.width > 100) {
    // Scroll container → story/carousel
    color = [UIColor greenColor];
    borderW = 2.0;
  } else if (f.size.width > 250 && f.size.height > 150) {
    // Large media tile
    color = [UIColor orangeColor];
    borderW = 1.5;
  } else if (![view isKindOfClass:[UIView class]] || 
             strcmp(object_getClassName(view), "UIView") != 0) {
    // Custom subclass, non-trivial size
    if (f.size.width > 100 && f.size.height > 50) {
      color = [UIColor purpleColor];
      borderW = 1.0;
    }
  }
  
  if (color && borderW > 0) {
    view.layer.borderWidth = borderW;
    view.layer.borderColor = color.CGColor;
    view.alpha = 0.9;
  }
  
  // Recurse
  for (UIView *sub in [view subviews]) {
    markView(sub, depth + 1);
  }
}

static void inspectAndMark(void) {
  UIWindow *win = [UIApplication sharedApplication].keyWindow;
  if (!win) {
    win = [[UIApplication sharedApplication].windows firstObject];
  }
  if (!win) return;
  clearMarkers(win);
  markView(win, 0);
}

static void hooked_sendEvent(id self, SEL _cmd, id event) {
  if (orig_sendEvent) orig_sendEvent(self, _cmd, event);
  
  // Detect 3-finger tap
  NSSet *touches = [event allTouches];
  if ([touches count] >= 3) {
    UITouch *touch = [touches anyObject];
    if (touch.phase == UITouchPhaseEnded) {
      static BOOL pending = NO;
      if (!pending) {
        pending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          inspectAndMark();
          pending = NO;
        });
      }
    }
  }
}

__attribute__((constructor))
static void glow_init(void) {
  Class appClass = objc_getClass("UIApplication");
  SEL seSel = sel_registerName("sendEvent:");
  Method seM = class_getInstanceMethod(appClass, seSel);
  orig_sendEvent = (IMP(*)(id,SEL,id))method_getImplementation(seM);
  method_setImplementation(seM, (IMP)hooked_sendEvent);
  
  const char *home = getenv("HOME");
  if (!home) return;
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  FILE *f = fopen(path, "w");
  if (f) {
    fprintf(f, "MANUAL INSPECTOR ACTIVE\n3-finger tap → hierarchy scan\n");
    fclose(f);
  }
}
