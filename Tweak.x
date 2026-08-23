// Tweak.x - Entry point for Glow for Facebook
// v8.5.1 - No auto refresh & keep reading position

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"
#import "GlowCommon.h"

extern BOOL g_tabBarGestureInstalled;

static IMP orig_viewDidAppear = NULL;
static int setupDone = 0;

static BOOL reelsHooksInstalled = NO;
static BOOL playbackHooksInstalled = NO;

void reloadPrefs(void) {
    [[GlowSettingsManager shared] loadSettings];
}

static void tryInstallReelsHooks(void) {
    if (reelsHooksInstalled) return;
    if (![GlowSettingsManager shared].downloadReels) return;
    Class sideBarCls = objc_getClass("FBShortsSideBarView");
    if (sideBarCls) {
        initReelsDownloadHooks();
        reelsHooksInstalled = YES;
        LOG("[ctor] Dynamically installed Reels download hooks!\n");
    }
}

static void tryInstallPlaybackHooks(void) {
    // Disabled to prevent startup crashes caused by hook on high-frequency FBVideoPlaybackController methods
}

static void clearAppCacheIfNeeded(void) {
    if (![GlowSettingsManager shared].clearCacheOnLaunch) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        @try {
            NSString *tempPath = NSTemporaryDirectory();
            NSArray *tempFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tempPath error:nil];
            for (NSString *file in tempFiles) {
                [[NSFileManager defaultManager] removeItemAtPath:[tempPath stringByAppendingPathComponent:file] error:nil];
            }
            LOG("[cache] Cleared temp files on launch\n");
        } @catch (NSException *e) {}
    });
}

static void installHooks(void) {
    if (setupDone) return;
    setupDone = 1;
    LOG("\n=== Installing Glow v8.5.1 hooks ===\n");

    GlowSettingsManager *settings = [GlowSettingsManager shared];

    // #0 Clean Feed (Ads, PYMK, Suggested, Reels Carousel)
    initAdBlockHooks();

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
    }

    // Capture URLs if either Newsfeed video download OR Reels download is enabled
    if (settings.downloadVideo || settings.downloadReels) {
        initVideoItemHooks();
    }

    // #11 Reels download
    if (settings.downloadReels) {
        tryInstallReelsHooks();
        tryInstallPlaybackHooks();
    }

    // Like confirmation dialogs (Posts & Reels)
    initLikeConfirmHooks();

    // No auto-reload / freeze foreground feed state
    initNoAutoRefreshHooks();

    // Long press on TabBar to open settings UI
    initLongPressHooks();

    // Clear cache on launch
    clearAppCacheIfNeeded();

    LOG("=== Done ===\n");
}

static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear) {
        typedef void (*FnType)(id, SEL, BOOL);
        ((FnType)orig_viewDidAppear)(self, _cmd, animated);
    }
    installHooks();
    tryInstallReelsHooks();
    tryInstallPlaybackHooks();
    
    // Attach long press once TabBar appears
    if (!g_tabBarGestureInstalled) {
        installLongPressOnCurrentUI();
    }
}

__attribute__((constructor))
static void glow_init(void) {
    LOG("\n=== Glow v8.5.1 (Modular Build) — %s ===\n", __DATE__ " " __TIME__);

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
