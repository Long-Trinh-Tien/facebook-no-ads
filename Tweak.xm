#import <objc/runtime.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>

static BOOL disableStorySeen = YES;
static NSMutableDictionary *origIMPs = nil;

static void hook_setSeenState(id self, SEL _cmd, id state) {
  if (disableStorySeen) return;
  NSString *key = NSStringFromClass([self class]);
  NSValue *val = [origIMPs objectForKey:key];
  if (!val) return;
  IMP orig = [val pointerValue];
  if (orig) {
    ((void(*)(id, SEL, id))orig)(self, _cmd, state);
  }
}

static void hookAllClasses() {
  origIMPs = [NSMutableDictionary new];
  SEL targetSel = @selector(setSeenState:);

  int classCount = objc_getClassList(NULL, 0);
  Class *classes = (Class *)malloc(sizeof(Class) * classCount);
  classCount = objc_getClassList(classes, classCount);

  int hooked = 0;
  for (int i = 0; i < classCount; i++) {
    Class cls = classes[i];
    const char *name = class_getName(cls);
    if (strncmp(name, "FB", 2) != 0 && strncmp(name, "FBSnacks", 8) != 0) continue;

    Method m = class_getInstanceMethod(cls, targetSel);
    if (!m) continue;

    NSString *key = @(name);
    if ([origIMPs objectForKey:key]) continue;

    IMP orig = method_getImplementation(m);
    [origIMPs setObject:[NSValue valueWithPointer:orig] forKey:key];
    method_setImplementation(m, (IMP)hook_setSeenState);
    hooked++;
    NSLog(@"[noseen] hooked %s", name);
  }

  free(classes);
  NSLog(@"[noseen] hooked %d classes total", hooked);
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

    // Preload frameworks
    NSString *fwPaths[] = {
      @"Frameworks/FBSharedFramework.framework/FBSharedFramework",
      @"Frameworks/FBSharedDynamicFramework.framework/FBSharedDynamicFramework",
    };
    for (int i = 0; i < 2; i++) {
      NSString *path = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:fwPaths[i]];
      dlopen([path UTF8String], RTLD_NOW | RTLD_GLOBAL);
    }

    hookAllClasses();
  }
}
