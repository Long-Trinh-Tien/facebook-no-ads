// AdBlockHooks.xm
// Hooks for blocking ads in NewsFeed using Logos (Non-ARC)
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"

%hook FBMemNewsFeedEdge

- (id)node {
    // Under non-ARC, this is just a raw pointer assignment.
    // ARC will NOT insert retain or release on orig.
    id orig = %orig;
    if (!orig) return nil;
    
    @try {
        SEL catSel = sel_registerName("category");
        if ([orig respondsToSelector:catSel]) {
            id category = [orig performSelector:catSel];
            if (category && [category respondsToSelector:@selector(isEqualToString:)]) {
                if ([category isEqualToString:@"SPONSORED"]) {
                    return nil; // Block SPONSORED ads
                }
            }
        }
    } @catch (NSException *e) {
        LOG("[adblock] Non-ARC exception: %s\n", e.reason.UTF8String);
    }
    return orig;
}

%end

void initAdBlockHooks(void) {
    @try {
        if ([GlowSettingsManager shared].removeAds) {
            %init;
            LOG("  hook #0: FBMemNewsFeedEdge.node -> nil for SPONSORED (Logos Hook, Non-ARC)\n");
        }
    } @catch (NSException *e) {
        LOG("[dl/adblock] init exc: %s\n", e.reason.UTF8String);
    }
}
