#import <objc/runtime.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>

// ========== NOSEEN HOOKS (seen story fix) ==========
static BOOL disableStorySeen = YES;
static IMP orig_attemptSend = NULL;
static IMP orig_markSeen = NULL;

static void hook_attemptSend(id self, SEL _cmd, id response, id bucket) {
  if (disableStorySeen) { return; }
  if (orig_attemptSend) ((void(*)(id, SEL, id, id))orig_attemptSend)(self, _cmd, response, bucket);
}

static void hook_markSeen(id self, SEL _cmd, id threads, id bucket, id tracking, BOOL isAnonymous, id completion) {
  if (disableStorySeen) { return; }
  if (orig_markSeen) ((void(*)(id, SEL, id, id, id, BOOL, id))orig_markSeen)(self, _cmd, threads, bucket, tracking, isAnonymous, completion);
}

static void initNoseen() {
  Class cls = objc_getClass("FBSnacksUnifiedSeenStateMutator");
  if (!cls) { NSLog(@"[noseen] class not found"); return; }
  
  SEL s1 = sel_registerName("_attemptSendSeenStateAndHandleResponse:bucket:");
  Method m1 = class_getInstanceMethod(cls, s1);
  if (m1) { orig_attemptSend = method_getImplementation(m1); method_setImplementation(m1, (IMP)hook_attemptSend); }
  
  SEL s2 = sel_registerName("_markThreadsAsSeen:fromBucket:withTrackingString:isAnonymousView:completion:");
  Method m2 = class_getInstanceMethod(cls, s2);
  if (m2) { orig_markSeen = method_getImplementation(m2); method_setImplementation(m2, (IMP)hook_markSeen); }
}

// ========== GLOW REIMPLEMENTATION ==========
// Glow's features (reverse engineered from Glow.dylib):
// - storyBucketType (property access)
// - MarkStoryAsSeen / _canMarkStoryAsSeen (removed in FB 560.x, skip)
// - UI changes, download features (need to reverse engineer)

// For now: Glow.bundle assets + Glow settings UI
// Glow's non-seen features can be added later via incremental reverse engineering

%ctor {
  @autoreleasepool {
    // Load Glow.bundle assets
    NSString *bundlePath = [[NSBundle mainBundle].bundlePath
      stringByAppendingPathComponent:@"Glow.bundle"];
    NSBundle *glowBundle = [NSBundle bundleWithPath:bundlePath];
    if (glowBundle) {
      [glowBundle load];
      NSLog(@"[noseen] Glow.bundle loaded");
    }
    
    // Hook seen state
    initNoseen();
    NSLog(@"[noseen] init done");
  }
}
