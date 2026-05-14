#import <objc/runtime.h>
#import <Foundation/Foundation.h>

static BOOL disableStorySeen = YES;
static IMP orig_setSeenState = NULL;

static void hook_setSeenState(id self, SEL _cmd, id state) {
  if (disableStorySeen) return;
  ((void(*)(id, SEL, id))orig_setSeenState)(self, _cmd, state);
}

static void reloadPrefs() {
  @autoreleasepool {
    NSDictionary *settings = [[NSDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/com.tommy.facebooknoseen.plist"];
    if (!settings) settings = @{};
    disableStorySeen = [settings[@"disableStorySeen"] ?: @YES boolValue];
  }
}

%ctor {
  @autoreleasepool {
    reloadPrefs();
    if (!disableStorySeen) return;

    // dlopen FBSharedFramework để đảm bảo class đã load
    NSString *fwPath = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([fwPath UTF8String], RTLD_NOW | RTLD_GLOBAL);

    Class cls = objc_getClass("FBSnacksSurfaceAwareSeenStateWriter");
    if (!cls) {
      NSLog(@"[noseen] FBSnacksSurfaceAwareSeenStateWriter not found");
      // Thử class khác
      cls = objc_getClass("FBSnacksCardSeenStateInfo");
      if (!cls) {
        NSLog(@"[noseen] neither class found");
        return;
      }
    }

    SEL sel = @selector(setSeenState:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
      NSLog(@"[noseen] setSeenState: not found on %s", class_getName(cls));
      return;
    }

    orig_setSeenState = method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_setSeenState);
    NSLog(@"[noseen] hooked %s successfully", class_getName(cls));
  }
}
