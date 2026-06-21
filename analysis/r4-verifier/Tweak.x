// R4 Verifier v3 — Targeted class discovery (no global enumeration)
// Output: /var/mobile/Documents/glow_r4.txt
//
// Why v3: v1/v2 crashed in Phase 2 because objc_getClassList
// returns ~10000 classes, and iterating with strstr + fflush per line
// caused memory/IO pressure, killing the process.
//
// Fix: Skip global enumeration. Hardcode candidate class names for
// v8.2 features. Use objc_getClass to check each. Output is bounded
// and fast.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <string.h>
#import <stdlib.h>
#import <dispatch/dispatch.h>

static char g_log_path[512] = {0};
static FILE *g_log_file = NULL;

static void log_msg(const char *fmt, ...) {
    if (g_log_path[0] == 0) {
        const char *home = getenv("HOME");
        if (!home) home = "/var/mobile";
        snprintf(g_log_path, sizeof(g_log_path), "%s/Documents/glow_r4.txt", home);
    }
    if (!g_log_file) {
        g_log_file = fopen(g_log_path, "w");
    }
    if (g_log_file) {
        va_list ap;
        va_start(ap, fmt);
        vfprintf(g_log_file, fmt, ap);
        va_end(ap);
        // Flush at end only, not per line (avoid IO pressure)
    }
    va_list ap2;
    va_start(ap2, fmt);
    vprintf(fmt, ap2);
    va_end(ap2);
}
#define LOG(fmt, ...) log_msg(fmt, ##__VA_ARGS__)

// Dump a single class (full methods + ivars + properties + superclass)
static void dumpClass(const char *name) {
    Class cls = objc_getClass(name);
    if (!cls) {
        LOG("\n=== %s ===\n", name);
        LOG("  CLASS NOT FOUND\n");
        return;
    }

    LOG("\n=== %s ===\n", name);
    LOG("  Address: %p\n", cls);

    LOG("  Superclass chain:\n");
    Class cur = cls;
    int depth = 0;
    while (cur && depth < 10) {
        LOG("    [%d] %s\n", depth++, class_getName(cur));
        cur = class_getSuperclass(cur);
    }

    unsigned int mc = 0;
    Method *methods = class_copyMethodList(cls, &mc);
    LOG("  Methods (%u):\n", mc);
    for (unsigned i = 0; i < mc; i++) {
        SEL sel = method_getName(methods[i]);
        const char *n = sel_getName(sel);
        const char *t = method_getTypeEncoding(methods[i]);
        if (t) {
            LOG("    - %s  // %s\n", n, t);
        } else {
            LOG("    - %s\n", n);
        }
    }
    free(methods);

    unsigned int ic = 0;
    Ivar *ivars = class_copyIvarList(cls, &ic);
    LOG("  Ivars (%u):\n", ic);
    for (unsigned i = 0; i < ic; i++) {
        const char *n = ivar_getName(ivars[i]);
        const char *t = ivar_getTypeEncoding(ivars[i]);
        LOG("    - %s  // %s\n", n ? n : "?", t ? t : "?");
    }
    free(ivars);

    unsigned int pc = 0;
    objc_property_t *props = class_copyPropertyList(cls, &pc);
    LOG("  Properties (%u):\n", pc);
    for (unsigned i = 0; i < pc; i++) {
        const char *n = property_getName(props[i]);
        const char *attrs = property_getAttributes(props[i]);
        LOG("    - %s  // %s\n", n ? n : "?", attrs ? attrs : "?");
    }
    free(props);
}

// Check list of class names, dump only those that exist
static void checkCandidates(const char *category, const char *names[], int n) {
    LOG("\n### %s ###\n", category);
    int found = 0;
    for (int i = 0; i < n; i++) {
        Class c = objc_getClass(names[i]);
        if (c) {
            LOG("  [FOUND] %s\n", names[i]);
            found++;
        }
    }
    LOG("--- %d/%d found ---\n", found, n);
}

// Check then dump full if found
static void checkAndDump(const char *name) {
    if (objc_getClass(name)) {
        dumpClass(name);
    }
}

__attribute__((constructor))
static void r4_init(void) {
    LOG("=== R4 Verifier v3 (targeted) — %s ===\n\n", __DATE__ " " __TIME__);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        @try {
            // ─── Phase 1: Critical classes (full dump) ───
            LOG("\n########## PHASE 1: Critical classes ##########\n");
            const char *critical[] = {
                // Ad block / story seen
                "FBMemNewsFeedEdge",
                "FBMemModelObject",
                "FBSnacksBucketsSeenStateManager",
                "FBComponentCollectionViewDataSource",
                "FBNewsFeedViewController",
                "FBNewsFeedViewControllerConfiguration",

                // Story download
                "FBSnacksMediaContainerView",
                "FBSnacksNewVideoView",
                "FBSnacksPhotoView",
                "FBSnacksWebPhotoView",
                "FBWebPhotoView",
                "FBWebImageNetworkSpecifier",
                "FBWebImageMemorySpecifier",

                // Video download
                "FBVideoPlaybackItem",
                "FBVideoOverlayPluginComponentBackgroundView",

                // PYMK / Suggested
                "FBMemPeopleYouMayKnowEdge",
                "FBMemSuggestedForYouEdge",
            };
            for (int i = 0; i < (int)(sizeof(critical)/sizeof(critical[0])); i++) {
                checkAndDump(critical[i]);
            }

            // ─── Phase 2: Reels candidates ───
            LOG("\n########## PHASE 2: Reels candidates ##########\n");
            const char *reels[] = {
                // Reels carousel (tab icon)
                "FBReelsTabViewController",
                "FBReelsTabContainerView",
                "FBReelsTabView",
                "FBReelTabBarItem",
                // Reels feed
                "FBReelsFeedViewController",
                "FBReelsFeedView",
                "FBReelsCollectionView",
                "FBReelsCollectionViewDataSource",
                "FBReelsCollectionViewLayout",
                "FBReelViewController",
                "FBReelPlayerViewController",
                "FBReelView",
                "FBReelPlayerView",
                "FBReelContainerView",
                "FBReelUnitView",
                "FBReelTrayView",
                "FBReelCarouselView",
                "FBReelHeaderView",
                "FBReelVideoContainerView",
                "FBReelsUnit",
                "FBReelsUnitView",
                "FBReelsUnitLayout",
                // Reel data
                "FBMemReelEdge",
                "FBMemReelTrayEdge",
                "FBMemReelUnitEdge",
                "FBMemReelItem",
                "FBMemReelUnit",
                // Reels overlay
                "FBReelOverlayView",
                "FBReelCommentsView",
                "FBReelsOverlayContainerView",
            };
            checkCandidates("Reels", reels, sizeof(reels)/sizeof(reels[0]));

            // ─── Phase 3: Video container candidates ───
            LOG("\n########## PHASE 3: Video container candidates ##########\n");
            const char *videos[] = {
                // Old name from Glow
                "VideoContainerView",
                // Possible replacements
                "FBVideoContainerView",
                "FBFeedVideoContainerView",
                "FBInlineVideoContainerView",
                "FBNewsFeedVideoContainerView",
                "FBReelVideoContainerView",
                "FBVideoPlayerView",
                "FBVideoView",
                "FBVideoWrapperView",
                "FBVideoBackgroundView",
                "FBVideoOverlayView",
                // Compositional
                "CKComponentView",
                // Pager for reels
                "FBPagingView",
                "FBReelPagingView",
                // Snacks video
                "FBSnacksVideoView",
                "FBSnacksVideoContainer",
                "FBSnacksReelContainerView",
            };
            checkCandidates("Video containers", videos, sizeof(videos)/sizeof(videos[0]));

            // ─── Phase 4: Story viewer candidates ───
            LOG("\n########## PHASE 4: Story viewer candidates ##########\n");
            const char *story[] = {
                "FBSnacksStoryViewerViewController",
                "FBSnacksStoryViewer",
                "FBSnacksStoryViewController",
                "FBSnacksStoryView",
                "FBSnacksThreadViewerViewController",
                "FBSnacksThreadViewer",
                "FBSnacksBucketViewerViewController",
                "FBSnacksBucketViewer",
                "FBSnacksViewerController",
                "FBSnacksViewer",
                "FBSnacksContainerViewController",
                "FBSnacksTrayViewController",
                "FBSnacksTrayView",
                "FBSnacksViewController",
            };
            checkCandidates("Story viewer", story, sizeof(story)/sizeof(story[0]));

            // ─── Phase 5: Composer / PYMK / Suggested ───
            LOG("\n########## PHASE 5: UI Hide candidates ##########\n");
            const char *hide[] = {
                // Composer
                "FBComposerViewController",
                "FBNewsFeedComposerView",
                "FBNewsFeedComposerViewController",
                "FBComposerPublishTargetView",
                "FBFeedComposerView",
                "FBStatusComposerView",
                "FBInlineComposerView",
                // PYMK variants
                "FBMemPYMKEdge",
                "FBMemPYMKUnit",
                "FBMemPYMKRow",
                "FBMemPeopleYouMayKnowUnit",
                "FBMemPeopleYouMayKnowItem",
                "FBMemPeopleYouMayKnowFeedUnit",
                "FBMemPeopleYouMayKnowRow",
                "FBMemPeopleYouMayKnowCard",
                "FBMemPeopleYouMayKnowCell",
                "FBMemPeopleYouMayKnowView",
                "FBMemPeopleYouMayKnowComponent",
                // Suggested
                "FBMemSuggestedEdge",
                "FBMemSuggestedRow",
                "FBMemSuggestedUnit",
                "FBMemSuggestedItem",
                "FBMemSuggestedCell",
                "FBMemSuggestedView",
                "FBMemSuggestedComponent",
                "FBMemSuggestedForYouItem",
                "FBMemSuggestedForYouUnit",
                "FBMemSuggestedForYouRow",
                // Reel carousel (tab)
                "FBReelsTrayViewController",
                "FBReelsTrayView",
                "FBReelsCarouselView",
                "FBReelsCarouselViewController",
                "FBReelsCarouselDataSource",
            };
            checkCandidates("UI Hide", hide, sizeof(hide)/sizeof(hide[0]));

            // ─── Phase 6: Download / share / save candidates ───
            LOG("\n########## PHASE 6: Download/share candidates ##########\n");
            const char *dl[] = {
                "FBDownloadManager",
                "FBDownloader",
                "FBFeedUnitDownloader",
                "FBVideoDownloader",
                "FBStoryDownloader",
                "FBPhotoDownloader",
                "FBSaveToPhotosAction",
                "FBSaveActionSheet",
                "FBLongPressMenu",
                "FBContextMenuAction",
                "FBContextMenuProvider",
                "FBLongPressGestureHandler",
            };
            checkCandidates("Download/share", dl, sizeof(dl)/sizeof(dl[0]));

            // ─── Phase 7: Reels action button candidates ───
            // Goal: find where like/share/comment buttons are init'd in Reels
            // So we can add our download button alongside them.
            LOG("\n########## PHASE 7: Reels action button candidates ##########\n");
            const char *reelsActions[] = {
                // Action button column container
                "FBReelActionBarView",
                "FBReelActionBar",
                "FBReelActionsView",
                "FBReelActionButton",
                "FBReelSideBarView",
                "FBReelSideBar",
                "FBReelRightSideBar",
                "FBReelLeftSideBar",
                "FBReelActionStackView",
                "FBReelToolbarView",
                "FBReelsActionBarView",
                "FBReelsActionBar",
                "FBReelsSideBarView",
                "FBReelsSideBar",
                "FBReelsActionStackView",
                // Specific buttons
                "FBReelLikeButton",
                "FBReelCommentButton",
                "FBReelShareButton",
                "FBReelSaveButton",
                "FBReelMoreButton",
                "FBReelMusicButton",
                "FBReelAuthorButton",
                "FBReelFollowButton",
                // Compositional
                "FBReelActionsComponent",
                "FBReelActionBarComponent",
                "FBReelSideBarComponent",
                "FBReelToolbarComponent",
                // Possible CK-based
                "FBReelCKDataSource",
                "FBReelCKComponent",
                // Snacks (older framework used for Reels)
                "FBSnacksReelView",
                "FBSnacksReelActionView",
                "FBSnacksReelActionBar",
                // Generic
                "FBReelOverlayActionView",
                "FBReelActionMenuView",
                "FBReelActionItemView",
                "FBReelButtonStack",
                "FBReelButtonColumn",
            };
            checkCandidates("Reels action buttons", reelsActions, sizeof(reelsActions)/sizeof(reelsActions[0]));

            LOG("\n=== R4 Verification Complete ===\n");
            LOG("Output: %s\n", g_log_path);
            if (g_log_file) {
                fflush(g_log_file);
                fclose(g_log_file);
            }
            g_log_file = NULL;
        } @catch (NSException *e) {
            LOG("EXC: %s\n", e.reason.UTF8String);
            if (g_log_file) { fflush(g_log_file); fclose(g_log_file); }
        } @catch (...) {
            LOG("EXC(c++)\n");
            if (g_log_file) { fflush(g_log_file); fclose(g_log_file); }
        }
    });
}
