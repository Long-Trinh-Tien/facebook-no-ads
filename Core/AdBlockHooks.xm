// AdBlockHooks.xm
// Smooth, flicker-free Ad, PYMK, Suggested & Reels Carousel Blocking for Facebook
#import "GlowCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Hooks.h"
#import "GlowSettingsManager.h"
#import "GlowLogManager.h"

static NSArray *filterCleanEdges(NSArray *origEdges) {
    if (!origEdges || ![origEdges isKindOfClass:[NSArray class]] || origEdges.count == 0) return origEdges;

    GlowSettingsManager *sm = [GlowSettingsManager shared];
    if (!sm.removeAds && !sm.removePYMK && !sm.removeSuggested && !sm.removeReelsCarousel) {
        return origEdges;
    }

    @try {
        NSMutableArray *cleanEdges = [NSMutableArray arrayWithCapacity:origEdges.count];
        SEL catSel = sel_registerName("category");
        SEL sponsoredSel = sel_registerName("isSponsored");
        SEL nodeSel = sel_registerName("node");

        for (id edge in origEdges) {
            if (!edge) continue;

            const char *edgeClassName = class_getName(object_getClass(edge));

            // 1. Check edge category (Ads / Sponsored / Suggested)
            if ([edge respondsToSelector:catSel]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id category = [edge performSelector:catSel];
                #pragma clang diagnostic pop
                if (category && [category isKindOfClass:[NSString class]]) {
                    NSString *catStr = (NSString *)category;
                    if (sm.removeAds && ![catStr isEqualToString:@"ORGANIC"]) {
                        continue; // Skip SPONSORED, PROMOTION
                    }
                    if (sm.removeSuggested && ([catStr isEqualToString:@"SUGGESTED"] || [catStr isEqualToString:@"PROMOTION"])) {
                        continue; // Skip Suggested
                    }
                }
            }

            // 2. Check edge isSponsored
            if (sm.removeAds && [edge respondsToSelector:sponsoredSel]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id sponVal = [edge performSelector:sponsoredSel];
                #pragma clang diagnostic pop
                if ([sponVal respondsToSelector:@selector(boolValue)] && [sponVal boolValue]) {
                    continue;
                }
            }

            // 3. Check PYMK (People You May Know)
            if (sm.removePYMK) {
                if (edgeClassName && (strstr(edgeClassName, "PYMK") != NULL || strstr(edgeClassName, "PeopleYouMayKnow") != NULL)) {
                    continue;
                }
            }

            // 4. Check Reels Carousel in Feed
            if (sm.removeReelsCarousel) {
                if (edgeClassName && (strstr(edgeClassName, "Shorts") != NULL || strstr(edgeClassName, "Reel") != NULL)) {
                    continue;
                }
            }

            // 5. Inspect Node class name if available
            if ([edge respondsToSelector:nodeSel]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id node = [edge performSelector:nodeSel];
                #pragma clang diagnostic pop
                if (node) {
                    const char *nodeClassName = class_getName(object_getClass(node));
                    if (nodeClassName) {
                        if (sm.removePYMK && (strstr(nodeClassName, "PYMK") != NULL || strstr(nodeClassName, "PeopleYouMayKnow") != NULL)) {
                            continue;
                        }
                        if (sm.removeReelsCarousel && (strstr(nodeClassName, "Shorts") != NULL || strstr(nodeClassName, "Reel") != NULL)) {
                            continue;
                        }
                    }
                }
            }

            [cleanEdges addObject:edge];
        }
        return cleanEdges;
    } @catch (NSException *e) {
        LOG("[adblock] filterCleanEdges exception: %s\n", e.reason.UTF8String);
        return origEdges;
    }
}

// Hook Feed Connections
%hook FBMemNewsFeedConnection
- (NSArray *)edges {
    NSArray *edges = %orig;
    return filterCleanEdges(edges);
}
%end

%hook FBMemFeedConnection
- (NSArray *)edges {
    NSArray *edges = %orig;
    return filterCleanEdges(edges);
}
%end

%hook FBGraphQLConnection
- (NSArray *)edges {
    NSArray *edges = %orig;
    return filterCleanEdges(edges);
}
%end

// Hook Feed Stories to strip sponsored flags directly
%hook FBMemFeedStory
- (BOOL)isSponsored {
    if ([GlowSettingsManager shared].removeAds) {
        return NO;
    }
    return %orig;
}

- (BOOL)isSponsoredStory {
    if ([GlowSettingsManager shared].removeAds) {
        return NO;
    }
    return %orig;
}

- (id)sponsoredData {
    if ([GlowSettingsManager shared].removeAds) {
        return nil;
    }
    return %orig;
}
%end

%hook FBMemStory
- (BOOL)isSponsored {
    if ([GlowSettingsManager shared].removeAds) {
        return NO;
    }
    return %orig;
}

- (id)sponsoredData {
    if ([GlowSettingsManager shared].removeAds) {
        return nil;
    }
    return %orig;
}
%end

void initAdBlockHooks(void) {
    @try {
        %init;
        LOG("  hook #0: Clean edges filtering (Ads, PYMK, Suggested, Reels) initialized\n");
    } @catch (NSException *e) {
        LOG("[dl/adblock] init exc: %s\n", e.reason.UTF8String);
    }
}
