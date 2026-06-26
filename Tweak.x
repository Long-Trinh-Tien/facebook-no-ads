// Tweak.x - Entry point for Glow for Facebook
// v8.2.68 - Phase 1 Refactor: Modular structure
// 
// This file ONLY handles initialization and dispatches to modules.
// All hooks are in Core/*.xm
// All business logic is in Managers/*.m
// All UI is in UI/*.m
// All utilities are in Utils/*.m

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"
#import "GlowCommon.h"

// Forward declaration for UIApplication hook
static IMP orig_viewDidAppear = NULL;
static int setupDone = 0;

static void installHooks(void) {
    if (setupDone) return;
    setupDone = 1;
    LOG("\n=== Installing v8.0 hooks ===\n");

    GlowSettingsManager *settings = [GlowSettingsManager shared];

    // Ad block
    if (settings.removeAds) {
        initAdBlockHooks();
    }

    // Story seen (3 paths blocked)
    if (settings.disableStorySeen) {
        initStorySeenHooks();
    }

    // Story download (button on FBSnacksMediaContainerView)
    if (settings.downloadStory) {
        initStoryDownloadHooks();
    }

    // Newsfeed video download (long press)
    if (settings.downloadVideo) {
        initNewsfeedVideoHooks();
        initVideoItemHooks();
    }

    // Reels download (button + playback tracking)
    if (settings.downloadReels) {
        initReelsDownloadHooks();
        initPlaybackStateHooks();
    }

    // Long press to open settings
    initLongPressHooks();

    // UI Explorer (debug)
    initExplorerHooks();

    // Runtime enum hooks (after a short delay to find all classes)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        @try { initRuntimeEnumHooks(); } @catch (NSException *e) {}
    });
}

static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear) {
        typedef void (*FnType)(id, SEL, BOOL);
        ((FnType)orig_viewDidAppear)(self, _cmd, animated);
    }
    installHooks();
}

__attribute__((constructor))
static void glow_init(void) {
    const char *home = getenv("HOME");
    if (home) {
        char logPath[512];
        snprintf(logPath, sizeof(logPath), "%s/Documents/glow.txt", home);
        // Log path is now in GlowLogManager
    }
    LOG("\n=== Glow v8.3.6 (RESTORE: GlowStoryDownloadHandler inline) — %s ===\n", __DATE__ " " __TIME__);

    // Load settings on startup
    [[GlowSettingsManager shared] loadSettings];

    // Listen for settings changes
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)reloadPrefs,
        CFSTR("com.tommy.glow.prefsChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    // Defer hook installation to main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class vcClass = objc_getClass("UIViewController");
            if (vcClass) {
                Method m = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
                if (m) {
                    orig_viewDidAppear = method_getImplementation(m);
                    method_setImplementation(m, (IMP)hooked_viewDidAppear);
                    LOG("[ctor] viewDidAppear hook installed\n");
                }
            }
        } @catch (...) {}
    });
}
