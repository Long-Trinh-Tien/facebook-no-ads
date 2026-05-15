#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <Foundation/Foundation.h>

static BOOL disableStorySeen = YES;

static IMP orig_attemptSend = NULL;
static void hook_attemptSend(id self, SEL _cmd, id response, id bucket) {
  if (disableStorySeen) { return; }
  if (orig_attemptSend) ((void(*)(id, SEL, id, id))orig_attemptSend)(self, _cmd, response, bucket);
}

static IMP orig_markSeen = NULL;
static void hook_markSeen(id self, SEL _cmd, id threads, id bucket, id tracking, BOOL isAnonymous, id completion) {
  if (disableStorySeen) { return; }
  if (orig_markSeen) ((void(*)(id, SEL, id, id, id, BOOL, id))orig_markSeen)(self, _cmd, threads, bucket, tracking, isAnonymous, completion);
}

%ctor {
  @autoreleasepool {
    // Bước 1: Fake Glow.plist để Substrate tìm thấy filter
    NSString *plistDir = @"/Library/MobileSubstrate/DynamicLibraries";
    NSString *plistPath = [plistDir stringByAppendingPathComponent:@"Glow.plist"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:plistDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSDictionary *glowFilter = @{
      @"Filter": @{@"Bundles": @[@"com.facebook.Facebook6"]}
    };
    [glowFilter writeToFile:plistPath atomically:YES];
    NSLog(@"[noseen] Glow.plist written: %d", [fm fileExistsAtPath:plistPath]);

    // Bước 2: Load Glow.dylib
    NSString *glowPath = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:@"Frameworks/Glow.dylib"];
    void *handle = dlopen([glowPath UTF8String], RTLD_NOW | RTLD_GLOBAL);
    NSLog(@"[noseen] Glow dlopen: %s", handle ? "OK" : dlerror());

    // Bước 3: Hook seen state
    Class cls = objc_getClass("FBSnacksUnifiedSeenStateMutator");
    if (!cls) {
      NSLog(@"[noseen] FBSnacksUnifiedSeenStateMutator not found");
      return;
    }
    
    SEL sel1 = sel_registerName("_attemptSendSeenStateAndHandleResponse:bucket:");
    Method m1 = class_getInstanceMethod(cls, sel1);
    if (m1) {
      orig_attemptSend = method_getImplementation(m1);
      method_setImplementation(m1, (IMP)hook_attemptSend);
      NSLog(@"[noseen] HOOKED _attemptSendSeenStateAndHandleResponse:bucket:");
    }
    
    SEL sel2 = sel_registerName("_markThreadsAsSeen:fromBucket:withTrackingString:isAnonymousView:completion:");
    Method m2 = class_getInstanceMethod(cls, sel2);
    if (m2) {
      orig_markSeen = method_getImplementation(m2);
      method_setImplementation(m2, (IMP)hook_markSeen);
      NSLog(@"[noseen] HOOKED _markThreadsAsSeen:");
    }
    
    NSLog(@"[noseen] init done");
  }
}
