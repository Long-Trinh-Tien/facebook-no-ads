// Tweak.x - Entry point for Glow for Facebook
// v8.3.8 - Modular Build with restored Settings UI and safe hooks

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"
#import "GlowCommon.h"

static IMP orig_viewDidAppear = NULL;
static int setupDone = 0;

static void installHooks(void) {
    if (setupDone) return;
    setupDone = 1;
    LOG("\n=== Installing Glow v8.3.8 hooks ===\n");

    GlowSettingsManager *settings = [GlowSettingsManager shared];

    // #0 Ad block
    if (settings.removeAds) {
        initAdBlockHooks();
    }

    // #1-3 Story seen (no-op block)
    if (settings.disableStorySeen) {
        initStorySeenHooks();
    }

    // #8 Story download
    if (settings.downloadStory) {
        initStoryDownloadHooks();
    }

    // #9 Newsfeed video download
    if (settings.downloadVideo) {
        initNewsfeedVideoHooks();
        initVideoItemHooks();
    }

    // #11 Reels download
    if (settings.downloadReels) {
        initReelsDownloadHooks();
        initPlaybackStateHooks();
    }

    // Long press to open settings UI
    initLongPressHooks();

    LOG("=== Done ===\n");
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
    LOG("\n=== Glow v8.3.8 (Modular Build — Settings Restored) — %s ===\n", __DATE__ " " __TIME__);

    [[GlowSettingsManager shared] loadSettings];

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)reloadPrefs,
        CFSTR("com.tommy.glow.prefsChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

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
