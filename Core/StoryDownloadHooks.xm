// StoryDownloadHooks.xm
// FIX v8.3.4: DISABLED entirely to prevent crash
// Story download was causing crash when tapping on stories
// Need to debug properly before re-enabling
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowCacheManager.h"
#import "GlowLogManager.h"
#import "GlowViewUtils.h"

void initStoryDownloadHooks(void) {
    // v8.3.4: DISABLED - was causing crash when tapping story
    // The didMoveToWindow hook was adding gesture + button,
    // but something in the interaction flow caused a crash.
    // Need to investigate further before re-enabling.
    LOG("  hook #8/8b: StoryDownloadHooks DISABLED (v8.3.4 crash fix)\n");
}
