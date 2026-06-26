// LongPressHooks.xm - STUB
// Long press to open settings UI
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"

void initLongPressHooks(void) {
    @try {
        // Full implementation will be in Phase 1.5
        LOG("  hook: LongPressHooks (STUB - full impl in Phase 1.5)\n");
    } @catch (NSException *e) {
        LOG("[dl/longpress] init exc: %s\n", e.reason.UTF8String);
    }
}
